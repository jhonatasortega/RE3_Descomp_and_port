#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
re3_sfx.py - Extrai SFX individuais dos bancos VAB do RE3 (PS1) com CORTE E PITCH
             corretos, decodificando a TABELA VAG do header (.VH).

Fonte (somente leitura): extracted/ntsc-u/CD_DATA/SOUND/<banco>.VH + <banco>.VB
  - .VH = header/tabela VAB (variante compacta Capcom): tons de 32 B (VagAtr) +
          tabela VAG (u16, offsets cumulativos em unidades de 8 B).  Ver tools/vab.py
          e docs/decomp/notes/sfx.md para a prova do layout byte-a-byte.
  - .VB = corpo PS-ADPCM (blocos de 16 B).

Metodo (preciso, via .VH -- substitui a antiga separacao GROSSEIRA por flags):
  1. Le a TABELA VAG do .VH  -> fronteiras EXATAS de cada amostra no .VB.
     (Prova: as 298 fronteiras de todos os bancos caem num bloco com flag de fim
      ADPCM e sao alinhadas a 16 B; e cada amostra real contem UM flag de fim
      interno -- justamente o que fazia a separacao antiga fragmentar as amostras.)
  2. Descarta o VAG#1 (bloco dummy/mudo padrao do SPU) de cada banco.
  3. Decodifica cada amostra (PS-ADPCM -> PCM 16-bit) e grava WAV mono na TAXA DO TOM:
        rate = 44100 * 2^((key - center - shift/128) / 12)
     onde center/shift/key vem do tom (VagAtr) que referencia a amostra. Como os SFX
     tem min==max, a tecla tocada e' fixa -> pitch determinado inteiramente pelo .VH.

Saida: godot/assets/SOUND/SFX/<banco>/<banco>_NN.wav (mono, taxa por-amostra) +
       godot/assets/SOUND/SFX/sfx_manifest.json (mapa amostra->vag/pitch/fronteiras).

Uso:
  python tools/re3_sfx.py --all            # todos os A_/C_ (+ R000) presentes
  python tools/re3_sfx.py C_00 C_01        # bancos especificos
  python tools/re3_sfx.py --map            # gera sfx_map.json (mapa semantico estatico)

Alem do WAV+manifesto, cada amostra tras: loop (marcadores ADPCM 0x01/0x02/0x04) e
ADSR (adsr1/adsr2 do VagAtr decodificados). O mapa semantico indice->acao
(--map) cruza compartilhamento entre bancos + envelope + pitch (ver docstring de
build_map e docs/decomp/notes/sfx.md).
"""
import glob
import json
import os
import struct
import sys
import wave

import vab
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

SND = 'extracted/ntsc-u/CD_DATA/SOUND'
OUT = paths.assets("SOUND", "SFX")

# Bancos com nomes de header/corpo diferentes (ex.: R000.SND + R_000.VB).
SPECIAL = {'R000': ('R000.SND', 'R_000.VB')}


def bank_paths(name):
    if name in SPECIAL:
        vh, vb = SPECIAL[name]
        return f'{SND}/{vh}', f'{SND}/{vb}'
    return f'{SND}/{name}.VH', f'{SND}/{name}.VB'


def clear_bank_dir(outdir):
    """Remove WAVs (e .import do Godot) antigos para nao deixar arquivos obsoletos."""
    if not os.path.isdir(outdir):
        return
    for f in os.listdir(outdir):
        if f.endswith('.wav') or f.endswith('.wav.import'):
            os.remove(os.path.join(outdir, f))


def write_wav(path, pcm, rate):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack('<%dh' % len(pcm), *pcm))


def extract_bank(name):
    vh_path, vb_path = bank_paths(name)
    if not (os.path.exists(vh_path) and os.path.exists(vb_path)):
        print(f'  [pular] {name}: header/corpo ausente')
        return []
    vh = open(vh_path, 'rb').read()
    vb = open(vb_path, 'rb').read()
    bank = vab.parse_bank(vh, len(vb))

    outdir = f'{OUT}/{name}'
    os.makedirs(outdir, exist_ok=True)
    clear_bank_dir(outdir)

    entries = []
    n = 0
    for s in bank['samples']:
        if s['is_dummy']:
            continue                          # VAG#1 = bloco dummy/mudo padrao
        pcm = vab.decode_adpcm(vb, s['start'], s['end'])
        fn = f'{name}_{n:02d}.wav'
        write_wav(os.path.join(outdir, fn), pcm, s['rate'])
        loop = vab.analyze_loop(vb, s['start'], s['end'])
        adsr = (vab.decode_adsr(s['adsr1'], s['adsr2'])
                if s['adsr1'] is not None else None)
        entries.append({
            'file': f'{name}/{fn}', 'vag': s['index'],
            'vb_start': s['start'], 'vb_end': s['end'], 'blocks': s['blocks'],
            'pcm_samples': len(pcm), 'rate': s['rate'],
            'center': s['center'], 'key': s['key'], 'shift': s['shift'],
            'prog': s['prog'], 'orphan': not s['tones'],
            'loop': loop, 'adsr': adsr,
        })
        n += 1
    orphans = sum(1 for e in entries if e['orphan'])
    print(f'  {name}: {n} SFX (orfas={orphans})  vags={len(bank["samples"])}'
          f' (1 dummy descartado)')
    return entries


# =============================================================================
# MAPA SEMANTICO indice->acao (ESTATICO, sem ouvir audio)
# -----------------------------------------------------------------------------
# Sinais discriminantes usados (todos ESTATICOS e reproduziveis):
#   1) PAPEL por COMPARTILHAMENTO entre bancos (ALTA, prova byte-a-byte): hash MD5
#      do PCM cru de cada amostra -> amostras byte-identicas em N bancos. As de
#      idx 00-04 sao identicas nos 13 bancos C_00..C_0C -> NUCLEO GLOBAL (sons de
#      acao do jogador sempre carregados). Compartilhamento menor = comum de
#      grupo de area; unico = especifico de area/situacao.
#   2) ENVELOPE/DURACAO (ALTA como MEDIDA): duracao, posicao do pico e razao de
#      cauda do PCM decodificado -> classe (curtissimo/transiente/medio/longo).
#   3) PITCH (center/key/rate) e ADSR/loop: emitidos (ver vab.decode_adsr/analyze_loop).
#      ADSR ~uniforme (one-shot) e loop uniforme (convencao) -> pouco sinal per-SFX.
#   4) CONTEXTO DO SCD (reportado a parte, NAO no rotulo per-wav): os opcodes de
#      som 0x57/0x58/0x59 carregam um ID LOGICO de SE (u16), NAO um vag por banco;
#      o id e' resolvido em runtime pela fila de SE + banco carregado. Logo NAO ha
#      link estatico id->vag -> nomes exatos de acao ficam em confianca MEDIA/BAIXA.
#
# HONESTIDADE: 'acao_provavel' e' INFERENCIA (papel+envelope+banco). O nome EXATO
# (porta vs tiro vs passo de um SFX ambiguo) so' e' decidivel OUVINDO -> marcado
# com confianca MEDIA (quando papel+envelope restringem bem) ou BAIXA (ambiguo).
# =============================================================================
import hashlib


def _envelope(pcm, rate):
    ab = [abs(x) for x in pcm]
    pk = max(ab) if ab else 0
    n = len(ab)
    dur = n / rate if rate else 0.0
    if pk == 0 or n == 0:
        return {'dur_s': round(dur, 3), 'peak_pos': None, 'tail_ratio': None,
                'peak': 0, 'class': 'silencio'}
    pki = ab.index(pk)
    tail = sum(ab[int(n * 0.85):]) / max(1, n - int(n * 0.85))
    peak_pos = pki / n
    tail_ratio = tail / pk
    if dur < 0.13:
        cls = 'curtissimo'
    elif dur >= 1.5:
        cls = 'longo_sustentado'
    elif dur < 0.6 and peak_pos < 0.35 and tail_ratio < 0.15:
        cls = 'transiente'
    else:
        cls = 'medio_com_cauda'
    return {'dur_s': round(dur, 3), 'peak_pos': round(peak_pos, 3),
            'tail_ratio': round(tail_ratio, 3), 'peak': pk, 'class': cls}


def _role(shared_count, bank):
    if shared_count >= 13:
        return ('nucleo_global_jogador', 'ALTA',
                'PCM byte-identico nos 13 bancos C_00..C_0C (idx 00-04): sempre '
                'carregado -> sons de acao do jogador/UI')
    if shared_count >= 3:
        return ('comum_multi_area', 'ALTA',
                'PCM byte-identico em %d bancos -> som comum a um grupo de areas'
                % shared_count)
    if shared_count == 2:
        return ('comum_par_area', 'ALTA',
                'PCM byte-identico em 2 bancos (par de areas irmas)')
    return ('unico_area', 'ALTA',
            'PCM unico (nenhum outro banco tem os mesmos bytes) -> especifico da area')


def _acao(role, env, bank):
    cls = env['class']
    if role == 'nucleo_global_jogador':
        if cls in ('curtissimo', 'transiente'):
            return ('acao pontual do jogador (passo/manuseio/impacto)', 'MEDIA',
                    'nucleo global + envelope %s; nome exato (passo/tiro/item) '
                    'exige audio' % cls)
        if cls == 'medio_com_cauda':
            return ('acao do jogador com cauda (porta/mecanismo/arma)', 'MEDIA',
                    'nucleo global + envelope medio com cauda; porta vs arma exige audio')
        return ('acao/stinger global do jogador', 'BAIXA',
                'nucleo global + envelope %s; indeterminado sem audio' % cls)
    if cls == 'longo_sustentado':
        return ('ambiente/drone de area', 'MEDIA',
                'envelope longo sustentado (%.2fs) + banco de area' % env['dur_s'])
    if cls in ('curtissimo', 'transiente'):
        return ('efeito pontual de area (impacto/pingo/click)', 'BAIXA',
                'envelope %s em banco de area; nome exato exige audio' % cls)
    return ('efeito de area (indeterminado)', 'BAIXA',
            'envelope %s; nome exato exige audio' % cls)


def build_map():
    """Constroi godot/assets/SOUND/SFX/sfx_map.json (mapa semantico estatico)."""
    banks = sorted({os.path.splitext(os.path.basename(p))[0]
                    for p in glob.glob(f'{SND}/[AC]_*.VB')})
    if os.path.exists(f'{SND}/R000.SND') and os.path.exists(f'{SND}/R_000.VB'):
        banks.append('R000')

    # 1a passada: decodifica tudo, calcula hash do PCM cru p/ agrupar por bytes
    parsed = {}
    hashgroups = {}
    for name in banks:
        vh_path, vb_path = bank_paths(name)
        if not (os.path.exists(vh_path) and os.path.exists(vb_path)):
            continue
        vh = open(vh_path, 'rb').read()
        vb = open(vb_path, 'rb').read()
        bank = vab.parse_bank(vh, len(vb))
        reals = [s for s in bank['samples'] if not s['is_dummy']]
        parsed[name] = (vb, reals)
        for n, s in enumerate(reals):
            h = hashlib.md5(vb[s['start']:s['end']]).hexdigest()
            hashgroups.setdefault(h, []).append('%s_%02d' % (name, n))

    # 2a passada: monta cada entrada com papel/envelope/adsr/loop/acao
    out_banks = {}
    counts = {'ALTA_role': 0, 'MEDIA_acao': 0, 'BAIXA_acao': 0, 'total': 0}
    for name in banks:
        if name not in parsed:
            continue
        vb, reals = parsed[name]
        ents = []
        for n, s in enumerate(reals):
            wav = '%s_%02d' % (name, n)
            h = hashlib.md5(vb[s['start']:s['end']]).hexdigest()
            group = sorted(hashgroups[h])
            sc = len(group)
            role, role_conf, role_ev = _role(sc, name)
            pcm = vab.decode_adpcm(vb, s['start'], s['end'])
            env = _envelope(pcm, s['rate'])
            loop = vab.analyze_loop(vb, s['start'], s['end'])
            adsr = (vab.decode_adsr(s['adsr1'], s['adsr2'])
                    if s['adsr1'] is not None else None)
            acao, acao_conf, acao_ev = _acao(role, env, name)
            counts['total'] += 1
            if role_conf == 'ALTA':
                counts['ALTA_role'] += 1
            counts['%s_acao' % acao_conf] = counts.get('%s_acao' % acao_conf, 0) + 1
            ents.append({
                'file': '%s/%s.wav' % (name, wav), 'vag': s['index'],
                'role': role, 'role_conf': role_conf, 'role_evidence': role_ev,
                'shared_count': sc, 'shared_with': [g for g in group if g != wav],
                'envelope': env,
                'pitch': {'rate': s['rate'], 'center': s['center'],
                          'key': s['key'], 'shift': s['shift']},
                'adsr': adsr, 'loop': loop, 'orphan': not s['tones'],
                'acao_provavel': acao, 'acao_conf': acao_conf,
                'acao_evidence': acao_ev,
            })
        out_banks[name] = ents

    doc = {
        '_meta': {
            'descricao': 'Mapa semantico ESTATICO indice->acao dos SFX (VAB) do RE3 '
                         'PS1 NTSC-U. Gerado por tools/re3_sfx.py --map. Sem ouvir audio.',
            'metodo': 'papel por compartilhamento byte-a-byte entre bancos (ALTA); '
                      'classe de envelope/duracao do PCM (ALTA como medida); pitch/'
                      'ADSR/loop emitidos; acao_provavel = INFERENCIA (papel+envelope).',
            'honestidade': 'Os opcodes de som do SCD (0x57/0x58/0x59) carregam um ID '
                           'LOGICO de SE (u16), resolvido em runtime pela fila de SE + '
                           'banco carregado -> NAO ha link estatico id->vag. Por isso o '
                           'NOME EXATO de acao (porta vs tiro vs passo de SFX ambiguo) '
                           'fica em confianca MEDIA/BAIXA: so decidivel OUVINDO. Papel, '
                           'envelope, pitch, ADSR e loop sao byte-provados (ALTA).',
            'scd_contexto': 'Ver docs/decomp/notes/sfx.md secao 8 (opcodes de som + '
                            'estatisticas de id nas 169 salas).',
            'cobertura': counts,
        },
        'banks': out_banks,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(f'{OUT}/sfx_map.json', 'w', encoding='utf-8') as f:
        json.dump(doc, f, indent=1, ensure_ascii=False)
    print('sfx_map.json: %d SFX | papel ALTA=%d | acao MEDIA=%d BAIXA=%d -> %s/sfx_map.json'
          % (counts['total'], counts['ALTA_role'],
             counts.get('MEDIA_acao', 0), counts.get('BAIXA_acao', 0), OUT))
    return 0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 0
    if args == ['--map']:
        return build_map()
    if args == ['--all']:
        banks = sorted({os.path.splitext(os.path.basename(p))[0]
                        for p in glob.glob(f'{SND}/[AC]_*.VB')})
        if os.path.exists(f'{SND}/R000.SND') and os.path.exists(f'{SND}/R_000.VB'):
            banks.append('R000')
    else:
        banks = args

    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    total = 0
    for b in banks:
        ents = extract_bank(b)
        if ents:
            manifest[b] = ents
            total += len(ents)
    with open(f'{OUT}/sfx_manifest.json', 'w', encoding='utf-8') as f:
        json.dump({'total_sfx': total, 'banks': manifest}, f,
                  indent=1, ensure_ascii=False)
    print(f'TOTAL SFX: {total} (bancos: {len(manifest)})  '
          f'-> {OUT}/sfx_manifest.json')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
