#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vab.py - Decodificador do banco VAB (SFX) do RE3 (PS1).

Formato do banco (variante COMPACTA da Capcom, derivada do VAB padrao SONY):
  - Par de arquivos:  <nome>.VH (header/tabela)  +  <nome>.VB (corpo PS-ADPCM).
  - O RE3 NAO usa o cabecalho classico "pBAV"/"VABp"; usa um header proprio, porem
    os TONS e a TABELA VAG sao os do VAB padrao (comprovado byte-a-byte, ver
    docs/decomp/notes/sfx.md).

Estruturas relevantes (comprovadas):
  * TOM = VagAtr de 32 bytes (identico ao SONY libsnd VagAtr):
        +0  prior   (u8)
        +1  mode    (u8)
        +2  vol     (u8)
        +3  pan     (u8)
        +4  center  (u8)   nota-raiz (rootKey)
        +5  shift   (u8)   ajuste fino da nota-raiz (center += shift/128 semitom)
        +6  min     (u8)   tecla minima do range
        +7  max     (u8)   tecla maxima do range   (nos SFX do RE3: min==max)
        +8  vibW,vibT,porW,porT,pbmin,pbmax,resv1,resv2 (8x u8)
        +16 adsr1   (u16)
        +18 adsr2   (u16)
        +20 prog    (u16)  programa a que o tom pertence
        +22 vag     (u16)  indice 1-based na TABELA VAG (qual amostra tocar)
        +24 reserved[4] (u16) -> preenchido pela Capcom com o marcador fixo
                                 c0 00 c1 00 c2 00 c3 00  (usado para localizar os tons)
  * TABELA VAG: array de u16 no fim do .VH. Cada valor = offset CUMULATIVO no .VB em
    unidades de 8 bytes. Comeca com 0 (VAG#0 = bloco dummy/mudo) e termina em
    len(.VB)/8. A amostra 'vag k' (1-based) ocupa [tab[k-1]*8, tab[k]*8).
    -> vag 1 = bloco dummy silencioso/mudo padrao (3 blocos: flag 0x07 + dados 0x77).
       As amostras REAIS sao vag 2..N.

PS-ADPCM (VAG): blocos de 16 B = byte0 (shift|predictor), byte1 (flag), 14 B de dados
  (28 amostras/bloco). Filtros SPU padrao. Flags de fim: 0x01/0x03/0x07.
"""
import struct

# Filtros PS-ADPCM (SPU) - identicos aos de re3_sound.py.
POS = (0, 60, 115, 98, 122)
NEG = (0, 0, -52, -55, -60)

TONE_SIG = b'\xc0\x00\xc1\x00\xc2\x00\xc3\x00'   # reserved[4] preenchido pela Capcom
END_FLAGS = (0x01, 0x03, 0x07)
SPU_BASE_RATE = 44100   # Hz: nota tocada == center -> pitch 1.0 -> saida a 44100 Hz


def decode_adpcm(vb, a, b, s_init=(0, 0)):
    """Decodifica PS-ADPCM de vb[a:b] (a,b alinhados a 16) -> lista de int16."""
    out = []
    s1, s2 = s_init
    for base in range(a, b, 16):
        h = vb[base]
        shift = h & 0x0F
        pred = h >> 4
        if pred > 4:
            pred = 0
        if shift > 12:
            shift = 12
        f0 = POS[pred]
        f1 = NEG[pred]
        for j in range(14):
            byte = vb[base + 2 + j]
            for nib in (byte & 0x0F, byte >> 4):
                s = nib - 16 if nib >= 8 else nib
                s = (s << 12) >> shift
                pr = s + ((s1 * f0 + s2 * f1) >> 6)
                if pr > 32767:
                    pr = 32767
                elif pr < -32768:
                    pr = -32768
                out.append(pr)
                s2 = s1
                s1 = pr
    return out


def _u16_array(d):
    return list(struct.unpack('<%dH' % (len(d) // 2), d[:len(d) // 2 * 2]))


def find_vagtab(vh, vb_len):
    """Localiza a TABELA VAG no fim do .VH.

    Metodo (robusto e verificavel): o ultimo valor da tabela e' len(.VB)/8. A partir
    dele, caminha para tras enquanto os valores forem estritamente decrescentes e > 0,
    e inclui o 0 inicial (VAG#0). Retorna a lista de offsets cumulativos (unidades 8 B).
    """
    target = vb_len // 8
    arr = _u16_array(vh)
    pos = None
    for i in range(len(arr) - 1, -1, -1):
        if arr[i] == target:
            pos = i
            break
    if pos is None:
        raise ValueError('tabela VAG nao encontrada (len(VB)/8=%d ausente no VH)' % target)
    s = pos
    while s > 0 and 0 < arr[s - 1] < arr[s]:
        s -= 1
    if s > 0 and arr[s - 1] == 0:      # inclui o VAG#0 (offset 0 do bloco dummy)
        s -= 1
    return arr[s:pos + 1]


def parse_tones(vh):
    """Extrai todos os tons (VagAtr) localizando o marcador reserved[4]."""
    tones = []
    off = 0
    while True:
        i = vh.find(TONE_SIG, off)
        if i < 0:
            break
        t = i - 24                     # inicio do VagAtr (o marcador esta em +24)
        if t >= 0:
            a = vh[t:t + 8]
            adsr1, adsr2, prog, vag = struct.unpack_from('<4H', vh, t + 16)
            tones.append({
                'prior': a[0], 'mode': a[1], 'vol': a[2], 'pan': a[3],
                'center': a[4], 'shift': a[5], 'min': a[6], 'max': a[7],
                'adsr1': adsr1, 'adsr2': adsr2, 'prog': prog, 'vag': vag,
            })
        off = i + len(TONE_SIG)
    return tones


def decode_adsr(adsr1, adsr2):
    """Decodifica os 32 bits de ADSR do SPU (VagAtr.adsr1/adsr2) -> campos nomeados.

    Layout do SPU (psx-spx / SsUtSetVoiceAttr; provado byte-a-byte no exemplo de
    C_00 documentado em docs/decomp/notes/sfx.md):
      adsr1 (u16): bit15  attack_mode (0=linear,1=exp)
                   bit10-14 attack_shift (0..31 = rapido..lento)
                   bit8-9   attack_step  (0..3 -> +7,+6,+5,+4)
                   bit4-7   decay_shift  (0..15)
                   bit0-3   sustain_level (Sl -> nivel = (Sl+1)*0x800)
      adsr2 (u16): bit15  sustain_mode (0=linear,1=exp)
                   bit14  sustain_dir  (0=increase,1=decrease)
                   bit8-12 sustain_shift (0..31)
                   bit6-7  sustain_step  (0..3)
                   bit5   release_mode (0=linear,1=exp)
                   bit0-4 release_shift (0..31)
    Nao converte para ms (o tempo exato exige simular o contador de 32 bits do SPU
    com a tabela de rates); emite os campos crus + um descritor qualitativo do
    ataque/release (shift baixo = rapido). Isto e' o suficiente para caracterizar o
    envelope de cada SFX sem inventar tempos.
    """
    at_shift = (adsr1 >> 10) & 0x1F
    re_shift = adsr2 & 0x1F

    def _speed(shift):
        if shift <= 2:
            return 'instantaneo'
        if shift <= 8:
            return 'rapido'
        if shift <= 18:
            return 'medio'
        return 'lento'

    return {
        'adsr1': adsr1, 'adsr2': adsr2,
        'attack_mode': 'exp' if (adsr1 >> 15) & 1 else 'lin',
        'attack_shift': at_shift, 'attack_step': (adsr1 >> 8) & 3,
        'attack_speed': _speed(at_shift),
        'decay_shift': (adsr1 >> 4) & 0xF,
        'sustain_level': adsr1 & 0xF,
        'sustain_mode': 'exp' if (adsr2 >> 15) & 1 else 'lin',
        'sustain_dir': 'dec' if (adsr2 >> 14) & 1 else 'inc',
        'sustain_shift': (adsr2 >> 8) & 0x1F, 'sustain_step': (adsr2 >> 6) & 3,
        'release_mode': 'exp' if (adsr2 >> 5) & 1 else 'lin',
        'release_shift': re_shift, 'release_speed': _speed(re_shift),
    }


def analyze_loop(vb, a, b):
    """Decodifica os marcadores de loop do PS-ADPCM em vb[a:b] (blocos de 16 B).

    O byte de flag (byte1 de cada bloco) do SPU tem 3 bits:
      bit0 (0x01) = End  (fim da amostra; SPU salta para o loop-address)
      bit1 (0x02) = Repeat (ao chegar no End, faz LOOP; sem este bit -> release/para)
      bit2 (0x04) = Loop-Start (marca o endereco de retorno do loop)
    Retorna: loop_start_block/pcm (1o bloco com bit2), terminal_block/flag (ultimo
    bloco com bit0), repeat (bit1 no terminal) e mute (dados 0x77 do bloco dummy).

    NOTA (achado, ver sfx.md): nos 267 SFX do RE3 estes marcadores sao UNIFORMES
    (todos: loop_start=bloco 1, terminal=0x07=End+Repeat+LoopStart) -> sao
    CONVENCAO de autoria, NAO um sinal per-SFX de "loopa vs one-shot". Quem decide
    se o som sustenta e' a FILA de SE do runtime (opcode SCD 0x57=loop / 0x58-0x59=
    one-shot), nao o waveform. Os campos sao emitidos assim mesmo (verdade do binario).
    """
    nb = (b - a) // 16
    loop_start_block = None
    term_block = None
    term_flag = None
    for i in range(nb):
        fl = vb[a + i * 16 + 1]
        if (fl & 0x04) and loop_start_block is None:
            loop_start_block = i
        if fl & 0x01:
            term_block = i
            term_flag = fl
    return {
        'blocks': nb,
        'loop_start_block': loop_start_block,
        'loop_start_pcm': None if loop_start_block is None else loop_start_block * 28,
        'terminal_block': term_block,
        'terminal_flag': term_flag,
        'repeat': bool(term_flag & 0x02) if term_flag is not None else False,
    }


def tone_rate(center, shift, key):
    """Taxa de saida (Hz) da amostra tocada na tecla 'key' com raiz (center,shift).

    No SPU, tocar note==center -> saida a SPU_BASE_RATE (44100 Hz). Cada semitom
    abaixo do center reduz a taxa por 2^(-1/12) (temperamento igual, aproximacao
    padrao do SsUtKeyToPitch). shift ajusta o center em shift/128 de semitom.
    """
    eff_center = center + shift / 128.0
    rate = SPU_BASE_RATE * (2.0 ** ((key - eff_center) / 12.0))
    return int(round(max(4000.0, min(float(SPU_BASE_RATE), rate))))


def parse_bank(vh_bytes, vb_len):
    """Parseia um banco VAB. Retorna dict com vagtab, tones e amostras.

    Cada amostra: {index (1-based), start, end, blocks, is_dummy, tones, rate,
    center, key, shift, prog}. is_dummy=True para o VAG#1 (bloco mudo padrao).
    Amostras sem tom ('orfas') recebem rate padrao 22050 e tones=[].
    """
    vagtab = find_vagtab(vh_bytes, vb_len)
    tones = parse_tones(vh_bytes)
    by_vag = {}
    for t in tones:
        by_vag.setdefault(t['vag'], []).append(t)

    samples = []
    nvag = len(vagtab) - 1
    for k in range(1, nvag + 1):
        start = vagtab[k - 1] * 8
        end = vagtab[k] * 8
        refs = by_vag.get(k, [])
        is_dummy = (k == 1)             # VAG#1 = bloco dummy/mudo padrao
        if refs:
            t = refs[0]                 # nos SFX do RE3 todos os tons de um vag concordam
            rate = tone_rate(t['center'], t['shift'], t['min'])
            center, key, shift, prog = t['center'], t['min'], t['shift'], t['prog']
            adsr1, adsr2 = t['adsr1'], t['adsr2']
        else:
            rate, center, key, shift, prog = 22050, None, None, None, None
            adsr1 = adsr2 = None
        samples.append({
            'index': k, 'start': start, 'end': end, 'blocks': (end - start) // 16,
            'is_dummy': is_dummy, 'tones': refs, 'rate': rate,
            'center': center, 'key': key, 'shift': shift, 'prog': prog,
            'adsr1': adsr1, 'adsr2': adsr2,
        })
    return {'vagtab': vagtab, 'tones': tones, 'samples': samples}
