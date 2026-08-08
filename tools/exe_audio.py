#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""exe_audio.py — de-para PROVADO `id de SE` -> amostra (WAV) do RE3 PS1 (SLUS_009.23).

Fecha o buraco que `docs/decomp/notes/sfx.md` §8.3 declarava insolúvel ("não há link
estático id -> vag"). **Há**: a tabela id -> descritor mora no INÍCIO do próprio
`.VH`/`.SND` do banco, e o descritor traz o índice do TOM (`VagAtr`), cujo campo `vag`
aponta a amostra. O que é resolvido em runtime é só QUAL banco está carregado.

────────────────────────── O que foi provado no EXE ──────────────────────────
Motor de som (endereços virtuais do `SLUS_009.23`, base 0x80010000):

  0x800746c0  SE_pede(a0=id, a1=ptr param 16B, a2, a3)
              id = (b2<<16) | (cat<<8) | idx
              grava um registro de 32 B no anel `0x800e0de4` (24 slots):
                +0x08..+0x17 = 16 B copiados de `a1` (posição 3D quando a1 != 0)
                +0x18 = a3   +0x1a = a2
                +0x1c = u16 idx      (`sh v0,0x1c` com v0 = a0 & 0xff)
                +0x1e = u8 (a0>>16)  +0x1f = u8 cat (a0>>8)
              avança o ponteiro de escrita `0x800e10e4` em 0x20.
              Porta de prioridade: se `*(0x800cc858) & 0x10000000` e cat >= 5, descarta.
  0x800744e0  laço consumidor (dentro do tick do motor): varre o anel de
              `0x800e0de4` até `*(0x800e10e4)`, passo 0x20, e para cada registro chama
              `*(0x800a1130 + (cat >= 5 ? 4 : 0))` = 0x80074770 (cat<5) / 0x80074820
              (cat>=5); depois zera o ponteiro de escrita.
  0x80074770  resolve: cat = u8@+0x1f, idx = u16@+0x1c;
              `desc = *( *(0x800e0610 + cat*4) + idx*4 )`; **desc == -1 -> descarta**;
              `banco = (desc.byte0 & 0xe) >> 1`, procurado em `0x800750e4`.
  0x800750e4  busca_banco(a0): varre 8 slots de 8 B em `0x800e0664` por `s16 == a0`;
              devolve o slot ou -1. É a MESMA função usada para `cat` e para o
              `banco` do descritor -> logo **cat == id de banco VAB**.
  0x800749a0  aloca voz do SPU + aplica volume/pan/pitch (lê `desc.byte2/byte3`).
  0x80075b90  volume/pan: `voz+0x08 = vol`, `voz+0x0a = vol`; se pan < 0x40
              `voz+0x08 = vol*pan/63`; se pan > 0x40 `voz+0x0a = vol*(0x7f-pan)/63`
              (divisão por 63 pelo idioma de magic-number 0x82082083 + shift 5).
  0x8007f768  libspu `SpuSetVoiceAttr` (chamado com mask=3 = VOLL|VOLR por 0x80075120).
  0x8007eda8  libspu `SpuSetKey(a0=on/off, a1=bitmask de 24 vozes)` — escreve
              KON/KOFF em `+0x188/+0x18a` e `+0x18c/+0x18e` do bloco de registradores
              do SPU, cujo ponteiro (0x1f801c00) vive em `*(0x800a1250)`.
  0x8007f518  libspu `SpuGetAllKeysStatus` (a1=0x17, a2=`0x800e116c`) — o array de
              status por voz que `0x800749a0` usa para achar voz livre.

Cadeia completa: `0x800746c0` -> anel -> `0x80074770`/`0x80074820` -> `0x800749a0`
-> `SpuSetVoiceAttr` / `SpuSetKey`.

────────────────────── Formato do banco (`.VH` / `.SND`) ──────────────────────
    [tabela de SE: N x u32]  [header VAB: 0x30 B]  [tons: 32 B cada]  [tabela VAG]

  * A tabela de SE começa no offset **0** do arquivo. `0xffffffff` = id não usado.
  * O header VAB é localizado pelo **magic `0x0001eeee`** gravado em `hdr+0x10`
    (35/35 arquivos). Logo `N = hdr/4`: `C_*` -> 16, `A_*` -> 32, `R000` -> 48.
  * `hdr+0x00` u32 = tamanho do `.VB` (confere em 35/35).
  * `hdr+0x14` u16 = nº de tons (confere com `vab.parse_tones` em 35/35).
  * `hdr+0x16` u16 = nº de VAGs.
  * `hdr+0x18` u8 = volume mestre (0x7f), `hdr+0x19` u8 = pan mestre (0x40).
  * tons em `hdr+0x30`; tabela VAG em `hdr + u32@hdr+0x08`.

  Descritor de SE (u32 little-endian), campos confirmados no disassembly:
    byte0 bits1-3 : **id do banco VAB** (0..7)     -> `(b0 & 0x0e) >> 1`
    byte1 bits4-7 : **índice do TOM** no banco      -> `b1 >> 4`
    byte2 bit7    : 1 = aloca voz dinamicamente / 0 = voz fixa (lido em 0x800749e8)
    byte2 bits0-4 : voz/grupo base (lido em 0x800749f8)
    byte3 bit0    : flag lida em 0x80074a08
    byte1 bits0-3, byte3 bits1-7: **NÃO PROVADO** (ver §resíduo do doc)

  Validação: `b1>>4 < n_tons` em **278/278** descritores usados dos 35 bancos, e o
  `banco` do descritor é sempre o mesmo dentro de um arquivo (`C_*`=0, `A_*`=1,
  `R000`=2) — o que sustenta `cat == id de banco`.

  Amostra final: `tom.vag` (1-based). VAG#1 é o bloco mudo padrão do SPU e é
  descartado por `re3_sfx.py`, que numera os WAV por posição entre as amostras
  reais -> **`vag k` => `<banco>_{k-2:02d}.wav`**.

Além dos 35 bancos do disco (`SOUND/*.VH` + `R000.SND`), **todo `STAGE*/DOOR??.DO1`
embute um banco VAB de PORTA** com o mesmo formato (`cat 4`, 4 ids) — 76 bancos, provado
em 76/76. Ver o bloco `bancos_porta`/`parse_porta` e `exe_audio.md §4.4`.

Uso:
    python tools/exe_audio.py                 # gera <out>/data/re3_se.json + sfx_map.json
    NOSTALGIA_OUT=port python tools/exe_audio.py
    python tools/exe_audio.py --verificar     # 1345 asserções; sai != 0 se alguma falhar
    python tools/exe_audio.py --tabela C_00   # imprime a tabela de SE de um banco
    NOSTALGIA_OUT=port python tools/exe_audio.py --portas   # 147 WAV dos bancos de porta

Ver: docs/decomp/notes/exe_audio.md
"""
import json
import os
import struct
import sys

import paths
import vab

MAGIC_VAB = 0x0001EEEE           # gravado em hdr+0x10 nos 35 bancos
VAG_DUMMY = 1                    # VAG#1 = bloco mudo padrão do SPU (descartado)

# Corpo (.VB) com nome diferente do header (mesma regra de re3_sfx.py).
CORPO_ESPECIAL = {"R000": "R_000.VB"}

# ─────────────────────────── Ações nomeadas ───────────────────────────
# `cat` = id de banco VAB: 0 = C_xx (jogador/UI/global), 1 = A_xx (área), 2 = R###.SND (sala).
#
# PROVA de cada nome está no campo `prova`. Só os 5 de menu têm confirmação de
# comportamento (observada pelo dono do repo no jogo) + corroboração estática: são os
# únicos ids de cat 0 chamados com `a1 = 0` (sem posição 3D) e todos os seus call sites
# caem em código de menu. O resto é **DECLARADO** (escolha do port) — o call site está
# registrado para quem quiser fechar por ouvido.
ACOES = {
    # ---- confirmados (comportamento observado + call sites de menu) ----
    "menu_mover": dict(cat=0, id=4, conf="ALTA", prova=(
        "11 call sites de 0x800746c0 com a0=4 (a1=0, sem posição 3D), todos em código "
        "de menu: 0x8003054c 0x800308f8 0x800638f4 0x80064684 0x8006688c 0x80066a78 "
        "0x800670f4 0x800672b0 ...; comportamento confirmado no jogo pelo dono do repo")),
    "menu_cancelar": dict(cat=0, id=5, conf="ALTA", prova=(
        "20 call sites com a0=5 (o mais frequente — 'voltar' existe em toda tela): "
        "0x800304e0 0x8003088c 0x80063c20 0x80063e74 0x80064538 ...")),
    "menu_confirmar": dict(cat=0, id=6, conf="ALTA", prova=(
        "13 call sites com a0=6: 0x80023d10 0x80064500 0x80064aa4 0x8006669c ...")),
    "menu_invalido": dict(cat=0, id=7, conf="ALTA", prova=(
        "5 call sites com a0=7: 0x800666bc 0x80067e90 0x80067ebc 0x800687b0 0x8006fdd0")),
    "menu_abrir": dict(cat=0, id=9, conf="ALTA", prova=(
        "5 call sites com a0=9: 0x80023db8 0x800666f0 0x80066728 0x8006dd40 0x8006fdb4")),
    # ---- declarados: call site provado, SEMÂNTICA NÃO PROVADA ----
    "tiro": dict(cat=0, id=11, conf="DECLARADO", prova=(
        "call sites 0x8003ad6c (`lui a0,1; ori a0,a0,0xb` -> a0=0x1000b) e 0x8003cf10, "
        "ambos com a1 = player+0x34 (posição) na sequência de disparo/ataque "
        "(exe_combat.md §2). Nome 'tiro' é DECLARADO: o par id->ação não foi ouvido. "
        "NOTA: C_00/C_01 (bancos de menu) NÃO definem o id 11 — só os C_02..C_0D de "
        "área — o que é coerente com 'não há tiro no menu'")),
    "impacto_ataque": dict(cat=0, id=0, conf="DECLARADO", prova=(
        "call site 0x8003d208 (`lui a0,1` -> a0=0x10000), grava player+0xc8=0x30004 e "
        "player+6=1, na vizinhança de 0x8003d14c = 'acerto/hit conectado' "
        "(exe_combat.md §linha 236). NÃO PROVADO")),
    "acao_1": dict(cat=0, id=1, conf="DECLARADO", prova="call site 0x8003d560. NÃO PROVADO"),
    "acao_2": dict(cat=0, id=2, conf="DECLARADO", prova="call site 0x8003d82c. NÃO PROVADO"),
    "acao_3": dict(cat=0, id=3, conf="DECLARADO", prova="call site 0x8003dac8. NÃO PROVADO"),
    "acao_8": dict(cat=0, id=8, conf="DECLARADO", prova=(
        "call sites 0x80063984 0x80063a2c (a1=0 -> UI). NÃO PROVADO")),
    "acao_13": dict(cat=0, id=13, conf="DECLARADO", prova=(
        "call sites 0x80045b10 0x80045e68 0x800465fc. NÃO PROVADO")),
    "acao_14": dict(cat=0, id=14, conf="DECLARADO", prova=(
        "call site 0x80077f40 (a1=0 -> UI). NÃO PROVADO")),
    "acao_15": dict(cat=0, id=15, conf="DECLARADO", prova=(
        "call site 0x800485e4 (a1=0 -> UI). NÃO PROVADO")),
    # ---- porta: banco cat 4, embutido nos DOOR*.DO1 ----
    "porta_abrir": dict(cat=4, id=0, conf="MEDIA", prova=(
        "cat 4 = banco de PORTA: os 76 STAGE*/DOOR??.DO1 embutem um banco VAB (magic "
        "0x0001eeee) cujos descritores usam banco 4 em 76/76, e é o recurso que o loader "
        "0x80012818 carrega com a string de depuração 'DOOR SOUND' (0x800103ac, passada em "
        "a3 por 0x80016534). Call site de cat 4 no EXE: 0x800161c4 (a0=0x401 -> cat 4, "
        "id 1), na região de setup/animação de porta. A tabela tem só 4 ids (0..3) e 3-4 "
        "amostras por porta — coerente com abrir/fechar/trancada. QUAL id é abrir e qual é "
        "fechar NÃO foi medido: 'abrir'=0 e 'fechar'=1 é ORDEM DECLARADA")),
    "porta_fechar": dict(cat=4, id=1, conf="MEDIA", prova=(
        "mesmo banco de porta_abrir; o id 1 é o que aparece no call site 0x800161c4 "
        "(a0=0x401). A associação id->abrir/fechar é DECLARADA, não medida")),
    "porta_trancada": dict(cat=4, id=2, conf="DECLARADO", prova=(
        "3º id do banco de porta. Nome DECLARADO por eliminação (abrir/fechar/trancada) — "
        "NÃO PROVADO")),
}

# Banco padrão de cada `cat` quando o port não sabe qual está carregado.
# C_00 é o banco de MENU (mesma tabela de SE que C_01) — é o certo para som de UI.
BANCO_PADRAO = {0: "C_00", 1: "A_01", 2: "R000", 4: "S1_DOOR00"}

# Reserva para os ids de cat 0 que só existem nos bancos DE ÁREA (C_02..C_0D) — o
# tiro, por exemplo, não existe em C_00/C_01. Qual C_ vale em cada sala é decidido no
# load da sala (indireção de runtime, não medida aqui).
# **declarado: escolha do port, não medida.**
BANCO_JOGO = {0: "C_02"}


# ─────────────────────────────── parsing ───────────────────────────────
def sound_dir():
    return paths.cd_data("SOUND")


def bancos_disponiveis(d=None):
    """[(nome, caminho_header, caminho_corpo)] de todos os bancos do disco."""
    d = d or sound_dir()
    out = []
    for f in sorted(os.listdir(d)):
        if not f.endswith((".VH", ".SND")):
            continue
        nome = f.rsplit(".", 1)[0]
        corpo = os.path.join(d, CORPO_ESPECIAL.get(nome, nome + ".VB"))
        if os.path.isfile(corpo):
            out.append((nome, os.path.join(d, f), corpo))
    return out


def parse_header(vh, vb_len):
    """Acha o header VAB pelo magic e devolve os campos + o offset (= tamanho da tabela SE)."""
    i = vh.find(struct.pack("<I", MAGIC_VAB))
    if i < 0:
        raise ValueError("magic 0x0001eeee (header VAB) ausente")
    hdr = i - 0x10
    if hdr < 0:
        raise ValueError("magic 0x0001eeee em offset impossível (%d)" % i)
    vb_size = struct.unpack_from("<I", vh, hdr)[0]
    total, off_vagtab = struct.unpack_from("<2I", vh, hdr + 4)
    n_tons, n_vags = struct.unpack_from("<2H", vh, hdr + 0x14)
    return {
        "hdr": hdr, "n_se": hdr // 4,
        "vb_size": vb_size, "vb_size_ok": vb_size == vb_len,
        "total": total, "off_vagtab": off_vagtab,
        "n_tons": n_tons, "n_vags": n_vags,
        "vol_mestre": vh[hdr + 0x18], "pan_mestre": vh[hdr + 0x19],
    }


def tons_do_header(vh, h):
    """Tons `VagAtr` lidos por OFFSET (`hdr+0x30`, `n_tons` x 32 B).

    `vab.parse_tones` acha os tons pelo marcador `c0 00 c1 00 c2 00 c3 00` em
    `reserved[4]`. Isso funciona nos `.VH`/`.SND` do disco, mas **falha nos bancos
    embutidos nos `DOOR*.DO1`**: lá alguns tons não têm o marcador, e o resto do arquivo
    (modelo/textura) pode conter bytes parecidos. Como o layout do header está provado
    (35/35 + 76/76), ler por offset é determinístico e mais rigoroso.
    """
    out = []
    for i in range(h["n_tons"]):
        t = h["hdr"] + 0x30 + i * 32
        a = vh[t:t + 8]
        adsr1, adsr2, prog, vg = struct.unpack_from("<4H", vh, t + 16)
        out.append({
            "prior": a[0], "mode": a[1], "vol": a[2], "pan": a[3],
            "center": a[4], "shift": a[5], "min": a[6], "max": a[7],
            "adsr1": adsr1, "adsr2": adsr2, "prog": prog, "vag": vg,
        })
    return out


def vagtab_do_header(vh, h):
    """Tabela VAG lida por OFFSET (`hdr + u32@hdr+0x08`, `n_vags+1` entradas u16)."""
    off = h["hdr"] + h["off_vagtab"]
    return list(struct.unpack_from("<%dH" % (h["n_vags"] + 1), vh, off))


def decodifica_descritor(desc):
    """Campos do descritor de SE (u32). Só os campos PROVADOS ganham nome."""
    b0, b1, b2, b3 = desc & 0xFF, (desc >> 8) & 0xFF, (desc >> 16) & 0xFF, (desc >> 24) & 0xFF
    return {
        "desc": "0x%08x" % desc,
        "banco": (b0 & 0x0E) >> 1,          # 0x80074770 / 0x800747d8
        "tom": b1 >> 4,                      # 0x80074cd0 (índice * 32 = sizeof VagAtr)
        "voz_dinamica": bool(b2 & 0x80),     # 0x800749e8
        "voz_base": b2 & 0x1F,               # 0x800749f8
        "flag_b3": b3 & 1,                   # 0x80074a08
        "nao_provado": {"b1_lo": b1 & 0x0F, "b3_hi": b3 >> 1},
    }


def parse_banco(nome, ph, pc):
    """Tabela de SE + tons + amostras de um banco (par de arquivos `.VH`+`.VB`)."""
    return parse_bytes(nome, open(ph, "rb").read(), os.path.getsize(pc),
                       os.path.basename(ph), os.path.basename(pc))


def parse_bytes(nome, vh, vb_len, arq="", corpo=""):
    """Núcleo do parse: `vh` = bytes do header, `vb_len` = tamanho do corpo PS-ADPCM.

    Serve tanto para o par `.VH`+`.VB` do disco quanto para o banco **embutido** nos
    `DOOR*.DO1` (§porta), onde header e corpo moram no mesmo arquivo.
    """
    h = parse_header(vh, vb_len)
    tons = tons_do_header(vh, h)
    vagtab = vagtab_do_header(vh, h)
    se = {}
    for i in range(h["n_se"]):
        d = struct.unpack_from("<I", vh, i * 4)[0]
        if d == 0xFFFFFFFF:
            continue
        info = decodifica_descritor(d)
        it = info["tom"]
        if it >= len(tons):
            # Acontece em **12 dos 159** descritores dos bancos de porta e em NENHUM dos
            # 278 dos bancos do disco. Motivo medido: a tabela de SE das portas é um
            # TEMPLATE — os ids 0 e 1 são byte-idênticos (`0x00601408`, `0x00612408`) nas
            # 76 portas, mas 12 portas têm só 2 tons, e aí o id 1 (que aponta o tom 2)
            # fica pendurado. É inconsistência do dado original, não do formato: marcamos
            # e seguimos, em vez de inventar outro layout de campo para forçar o encaixe.
            info["invalido"] = "tom %d >= n_tons %d (entrada sobrando do template)" % (it, len(tons))
            se[i] = info
            continue
        tom = tons[it]
        vg = tom["vag"]
        info["vag"] = vg
        info["dummy"] = vg == VAG_DUMMY      # aponta o bloco mudo -> placeholder silencioso
        info["wav"] = None if info["dummy"] else "%s/%s_%02d.wav" % (nome, nome, vg - 2)
        info["taxa_hz"] = vab.tone_rate(tom["center"], tom["shift"], tom["min"])
        info["tom_vol"] = tom["vol"]
        info["tom_pan"] = tom["pan"]
        if 1 <= vg < len(vagtab):
            info["vb_bytes"] = (vagtab[vg] - vagtab[vg - 1]) * 8
        se[i] = info
    return {
        "arquivo": arq, "corpo": corpo,
        "banco": (min(v["banco"] for v in se.values()) if se else None),
        "n_se": h["n_se"], "n_tons": len(tons), "n_vags": len(vagtab) - 1,
        "vb_bytes": vb_len, "vol_mestre": h["vol_mestre"], "pan_mestre": h["pan_mestre"],
        "se": se, "_hdr": h, "_vagtab": vagtab,
        # taxa por VAG (vem do tom que o referencia) — usada na extração dos WAV de porta
        "_taxa_por_vag": {v["vag"]: v["taxa_hz"] for v in se.values() if "vag" in v},
    }


# ───────────────────────── bancos de PORTA (`DOOR*.DO1`) ─────────────────────────
# Achado desta rodada: **todo `STAGE*/DOOR??.DO1` embute um banco VAB completo** com o
# mesmo magic `0x0001eeee`. É o "DOOR SOUND" que o loader `0x80012818` carrega (a string
# de depuração está em `0x800103ac` e é passada em `a3` por `0x80016534`).
#
# Layout do banco embutido — provado em **76/76** arquivos:
#     [tabela de SE: 4 x u32] [header VAB @0x10] [tons @0x40] [tabela VAG] [corpo PS-ADPCM]
#     corpo começa em `hdr + u32@hdr+0x04` (fim do bloco do header) e tem `u32@hdr+0x00` bytes
# Todos usam **banco 4** no descritor → **`cat 4` é o banco de PORTA**.
DOOR_GLOB = os.path.join("STAGE*", "DOOR*.DO1")


def bancos_porta():
    """[(nome, caminho)] dos bancos de som de porta."""
    import glob
    out = []
    for p in sorted(glob.glob(paths.cd_data(DOOR_GLOB))):
        stage = os.path.basename(os.path.dirname(p))          # STAGE1..STAGE7
        porta = os.path.splitext(os.path.basename(p))[0]       # DOOR00..
        out.append(("S%s_%s" % (stage[-1], porta), p))
    return out


def parse_porta(nome, caminho):
    """Banco VAB embutido num `.DO1`. Devolve (info, bytes_do_corpo)."""
    b = open(caminho, "rb").read()
    i = b.find(struct.pack("<I", MAGIC_VAB))
    if i < 0:
        raise ValueError("%s: sem magic 0x0001eeee" % caminho)
    hdr = i - 0x10
    vb_size, total = struct.unpack_from("<2I", b, hdr)
    base = hdr + total                                   # corpo logo após o bloco do header
    if base + vb_size > len(b):
        raise ValueError("%s: corpo não cabe (base %#x + %d > %d)" % (caminho, base, vb_size, len(b)))
    info = parse_bytes(nome, b, vb_size, os.path.basename(caminho), "(embutido)")
    info["vb_offset"] = base
    return info, b[base:base + vb_size]


def coletar(portas=False):
    d = {n: parse_banco(n, ph, pc) for n, ph, pc in bancos_disponiveis()}
    if portas:
        for n, p in bancos_porta():
            try:
                d[n] = parse_porta(n, p)[0]
            except ValueError as ex:
                print("  aviso: %s" % ex)
    return d


def extrair_portas():
    """Escreve os WAV dos bancos de porta em `<out>/assets/SOUND/SFX/<banco>/`."""
    import wave
    n_wav = 0
    for nome, p in bancos_porta():
        info, corpo = parse_porta(nome, p)
        vagtab = info["_vagtab"]
        outdir = paths.assets("SOUND", "SFX", nome)
        os.makedirs(outdir, exist_ok=True)
        for k in range(2, len(vagtab)):                  # VAG#1 = bloco mudo, descartado
            a, z = vagtab[k - 1] * 8, vagtab[k] * 8
            pcm = vab.decode_adpcm(corpo, a, z)
            taxa = info["_taxa_por_vag"].get(k, 22050)
            with wave.open(os.path.join(outdir, "%s_%02d.wav" % (nome, k - 2)), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(taxa)
                w.writeframes(struct.pack("<%dh" % len(pcm), *pcm))
            n_wav += 1
    print("portas: %d WAV -> %s" % (n_wav, paths.assets("SOUND", "SFX")))
    return n_wav


# ─────────────────────────────── saída ───────────────────────────────
META = {
    "descricao": "De-para PROVADO id de SE -> amostra do RE3 PS1 (SLUS_009.23). "
                 "Gerado por tools/exe_audio.py. Ver docs/decomp/notes/exe_audio.md.",
    "exe": "SLUS_009.23 (NTSC-U), base 0x80010000",
    "enderecos_provados": {
        "SE_pede": "0x800746c0  (a0 = (b2<<16)|(cat<<8)|idx; a1 = ptr 16B; a2; a3)",
        "anel_pedidos": "0x800e0de4 (24 x 32B), ponteiro de escrita 0x800e10e4",
        "tabela_handler": "0x800a1130 -> {0x80074770 (cat<5), 0x80074820 (cat>=5)}",
        "consumidor": "0x800744e0",
        "resolve": "0x80074770  desc = *( *(0x800e0610 + cat*4) + idx*4 ); -1 = descarta",
        "busca_banco": "0x800750e4  (8 slots de 8B em 0x800e0664; mesma fn p/ cat e p/ banco)",
        "voz_setup": "0x800749a0",
        "vol_pan": "0x80075b90  (div por 63; pan centro 0x40)",
        "SpuSetVoiceAttr": "0x8007f768 (mask=3 via 0x80075120)",
        "SpuSetKey": "0x8007eda8 (KON/KOFF em +0x188/+0x18a e +0x18c/+0x18e)",
        "SpuGetAllKeysStatus": "0x8007f518 (status por voz em 0x800e116c)",
        "regs_SPU": "*(0x800a1250) = 0x1f801c00",
    },
    "formato_banco": {
        "tabela_se": "offset 0 do .VH/.SND, N x u32; 0xffffffff = id nao usado; N = hdr/4",
        "magic_header_vab": "0x0001eeee em hdr+0x10 (35/35 bancos)",
        "campos": "hdr+0x00 |.VB| (35/35 ok) | hdr+0x08 off tabela VAG | "
                  "hdr+0x14 n_tons (35/35 ok) | hdr+0x16 n_vags | hdr+0x18/+0x19 vol/pan mestre | "
                  "hdr+0x30 tons (32B, VagAtr)",
        "descritor": "byte0 bits1-3 = banco VAB; byte1 bits4-7 = indice do TOM; "
                     "byte2 bit7 = voz dinamica; byte2 bits0-4 = voz base; byte3 bit0 = flag. "
                     "byte1 bits0-3 e byte3 bits1-7 NAO PROVADOS",
        "amostra": "tom.vag (1-based); VAG#1 = bloco mudo descartado -> wav = <banco>_{vag-2:02d}",
    },
    "cat": {"0": "C_xx (jogador/UI/global)", "1": "A_xx (area)", "2": "R###.SND (sala)",
            "nota": "cat == id de banco VAB (mesma fn de busca 0x800750e4 para os dois)"},
    "CORRECOES": [
        "docs/decomp/notes/sfx.md §8 dizia que os opcodes SCD 0x57/0x58/0x59 eram filas de "
        "SE. NAO SAO: 0x80038678/0x80038704/0x8003879c alimentam as duas filas de RUMBLE "
        "(0x800de648 motor pequeno on/off, 0x800de798 motor grande com rampa linear). O tick "
        "0x800389a0 gera nivel = acc>>7 e o resultado vai para 0x800c79c8 (2 bytes), passado "
        "a PadSetAct pelo stub 0x80091710 (a1=0x800c79c8, a2=2). Slot de 10B: +0 ativo, "
        "+1 nivel, +2 atraso, +4 duracao, +6 passo, +8 acumulador<<7.",
        "docs/decomp/notes/menus.md §8.2 lia 0x800746c0 como enqueue de SPRITE de GPU. E' o "
        "enqueue de SE: a cadeia termina em SpuSetVoiceAttr/SpuSetKey (ver enderecos acima). "
        "menu_comandos.md:66 e menu_mapa.md:657/916, que diziam 'SFX', estavam CERTOS.",
        "docs/decomp/notes/sfx.md §8.3 concluia que NAO existia link estatico id->vag. "
        "Existe: a tabela mora no inicio do .VH/.SND. O que e' runtime e' so QUAL banco "
        "esta carregado em cada cat.",
        "docs/decomp/notes/exe_combat.md diz que 0x800776b0 'seleciona seco/tiro/vazio pelos "
        "bits 0x200/0x400 de (player+0xe4)'. NAO PROVADO: nao existe nenhum `andi 0x200/0x400` "
        "nem leitura de +0xe4 em 0x800776b0..0x80077b84. O que a rotina faz e' pedir um SE de "
        "cat 2 (SALA) com idx = base + a0, base em {0x17, 0x1a, (retorno de 0x80077b84)&0x7f} "
        "ou 0x2d, e a0 in {0,1} — e chamar 0x8001b484 (spawn de efeito/modelo, tabela "
        "0x800ba728) 10 vezes. Compativel com IMPACTO/ricochete de sala, nao com o estouro "
        "da arma.",
    ],
}


def gerar():
    bancos = coletar(portas=True)
    dados = {"_meta": META, "acoes": {}, "banco_padrao": BANCO_PADRAO,
             "banco_jogo": BANCO_JOGO, "bancos": {}}

    for nome, b in sorted(bancos.items()):
        dados["bancos"][nome] = {
            "arquivo": b["arquivo"], "corpo": b["corpo"], "banco": b["banco"],
            "n_se": b["n_se"], "n_tons": b["n_tons"], "n_vags": b["n_vags"],
            "vb_bytes": b["vb_bytes"],
            "se": {str(i): {k: v for k, v in info.items() if k != "nao_provado"}
                   for i, info in sorted(b["se"].items())},
        }

    for acao, a in ACOES.items():
        cat, sid = a["cat"], a["id"]
        # resolve em CADA banco daquele cat (o mesmo id toca amostras diferentes por área)
        por_banco = {}
        for nome, b in sorted(bancos.items()):
            if b["banco"] != cat:
                continue
            info = b["se"].get(sid)
            if info and not info.get("dummy", True) and "invalido" not in info:
                por_banco[nome] = info["wav"]
        # 1ª escolha: o banco padrão do cat. Se o id não existir lá (caso do tiro, que só
        # vive nos bancos de área), cai no BANCO_JOGO — declarado, não medido.
        padrao = BANCO_PADRAO.get(cat)
        origem = padrao if padrao in por_banco else BANCO_JOGO.get(cat)
        if origem not in por_banco:
            origem = None
        dados["acoes"][acao] = {
            "cat": cat, "id": sid, "confianca": a["conf"], "prova": a["prova"],
            "wav_padrao": por_banco.get(origem),
            "banco_padrao": origem,
            "banco_declarado": origem is not None and origem != padrao,
            "por_banco": por_banco,
        }

    out = paths.data("re3_se.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    print("%s  (%d bancos, %d acoes)" % (out, len(bancos), len(ACOES)))

    # sfx_map.json: nome lógico -> wav, agora com origem provada (substitui a heurística)
    mapa = {
        "_meta": {
            "descricao": "Nome logico -> WAV de SFX, relativo a assets/SOUND/SFX/. "
                         "Gerado por tools/exe_audio.py a partir da tabela de SE do .VH "
                         "(PROVADA). Substitui a versao antiga, escolhida por heuristica "
                         "de duracao (que estava ERRADA: menu_move apontava C_00_01).",
            "confianca": "ALTA nos 5 sons de menu; DECLARADO no resto (ver re3_se.json.acoes)",
            "banco_global": "C_00/C_01 = banco de MENU; C_02..C_0D = banco de area do jogador",
        },
        "sfx": {a: d["wav_padrao"] for a, d in sorted(dados["acoes"].items())
                if d["wav_padrao"]},
    }
    out2 = paths.data("sfx_map.json")
    with open(out2, "w", encoding="utf-8") as f:
        json.dump(mapa, f, ensure_ascii=False, indent=1)
    print("%s  (%d nomes)" % (out2, len(mapa["sfx"])))
    return dados


# ─────────────────────────────── verificação ───────────────────────────────
def verificar():
    """Re-roda todas as asserções que sustentam o de-para. Devolve (n_ok, n_falha)."""
    ok = falha = 0

    def chk(cond, msg):
        nonlocal ok, falha
        if cond:
            ok += 1
        else:
            falha += 1
            print("  [FALHA] %s" % msg)
        return cond

    bancos = bancos_disponiveis()
    chk(len(bancos) == 35, "esperados 35 bancos, achei %d" % len(bancos))

    n_desc = 0
    for nome, ph, pc in bancos:
        vh = open(ph, "rb").read()
        vb_len = os.path.getsize(pc)
        h = parse_header(vh, vb_len)
        chk(h["vb_size_ok"],
            "%s: hdr+0x00 (%d) != |.VB| (%d)" % (nome, h["vb_size"], vb_len))
        # nos bancos do disco os dois caminhos (marcador vs offset) tem de CONCORDAR —
        # e' o que valida ler por offset nos DOOR*.DO1, onde o marcador nao serve
        tons_sig = vab.parse_tones(vh)
        chk(h["n_tons"] == len(tons_sig),
            "%s: hdr+0x14 (%d) != tons achados pelo marcador (%d)" % (nome, h["n_tons"], len(tons_sig)))
        tons = tons_do_header(vh, h)
        chk(tons == tons_sig, "%s: tons por offset != tons por marcador" % nome)
        chk(0x30 + 32 * len(tons) == h["off_vagtab"],
            "%s: tons nao terminam onde hdr+0x08 aponta a tabela VAG" % nome)
        vagtab = vagtab_do_header(vh, h)
        chk(vagtab == vab.find_vagtab(vh, vb_len),
            "%s: tabela VAG por offset != por varredura" % nome)
        chk(vagtab[0] == 0 and vagtab[-1] * 8 == vb_len,
            "%s: tabela VAG nao vai de 0 a |.VB|/8" % nome)
        bks = set()
        for i in range(h["n_se"]):
            d = struct.unpack_from("<I", vh, i * 4)[0]
            if d == 0xFFFFFFFF:
                continue
            n_desc += 1
            info = decodifica_descritor(d)
            bks.add(info["banco"])
            chk(info["tom"] < len(tons),
                "%s id %d: tom %d >= n_tons %d" % (nome, i, info["tom"], len(tons)))
            vg = tons[info["tom"]]["vag"]
            chk(1 <= vg <= len(vagtab) - 1,
                "%s id %d: vag %d fora da tabela VAG" % (nome, i, vg))
        chk(len(bks) <= 1,
            "%s: descritores citam bancos diferentes (%s)" % (nome, sorted(bks)))

    chk(n_desc == 278, "esperados 278 descritores usados, achei %d" % n_desc)

    # o de-para dos 5 sons de menu, banco C_00 (tabela identica em C_01)
    esperado = {4: (5, 4, "C_00_02"), 5: (6, 5, "C_00_03"), 6: (7, 6, "C_00_04"),
                7: (8, 2, "C_00_00"), 9: (12, 3, "C_00_01")}
    b = parse_banco("C_00", os.path.join(sound_dir(), "C_00.VH"),
                    os.path.join(sound_dir(), "C_00.VB"))
    for sid, (tom, vg, wav) in esperado.items():
        info = b["se"].get(sid)
        chk(info is not None and info["tom"] == tom and info["vag"] == vg
            and info["wav"] == "C_00/%s.wav" % wav,
            "C_00 id %d: esperado tom %d vag %d %s, obtido %s" % (sid, tom, vg, wav, info))

    # Os ids de UI têm o MESMO descritor em 13 dos 14 bancos C_ (o som de UI é global).
    # `C_0C` é a ÚNICA exceção: não define o id 4 e usa outros tons nos ids 5/6/7
    # (0x0fe3a400/0x0fe3b400/0x0fe39400). Isso é medida, não suposição.
    UI_COMUM = {4: 0x3FE05300, 5: 0x3FE06300, 6: 0x3FE07300, 7: 0x3FE08300}
    for sid, esp in sorted(UI_COMUM.items()):
        iguais = []
        for nome, ph, pc in bancos:
            if not nome.startswith("C_"):
                continue
            if struct.unpack_from("<I", open(ph, "rb").read(), sid * 4)[0] == esp:
                iguais.append(nome)
        chk(len(iguais) == 13 and "C_0C" not in iguais,
            "id %d de UI: esperado o mesmo descritor em 13 bancos C_ (menos C_0C), "
            "obtido %s" % (sid, iguais))

    # Cruzamento independente com sfx.md §9.1: as 5 amostras que aquele estudo achou
    # BYTE-IDÊNTICAS nos 13 bancos C_ são os WAV de índice 00..04 — e são exatamente
    # as 5 dos sons de UI. Dois caminhos independentes, mesmo resultado.
    ui_wavs = sorted(b["se"][s]["wav"] for s in (4, 5, 6, 7, 9))
    chk(ui_wavs == ["C_00/C_00_%02d.wav" % i for i in range(5)],
        "os 5 sons de UI deviam ser os WAV 00..04 de C_00, obtido %s" % ui_wavs)

    # ── bancos de PORTA embutidos nos DOOR*.DO1 ──
    portas = bancos_porta()
    chk(len(portas) == 76, "esperados 76 DOOR*.DO1, achei %d" % len(portas))
    n_porta = 0
    for nome, p in portas:
        try:
            info, corpo = parse_porta(nome, p)
        except ValueError as ex:
            chk(False, str(ex))
            continue
        n_porta += 1
        tab = info["_vagtab"]
        chk(tab[0] == 0 and tab[-1] * 8 == len(corpo),
            "%s: tabela VAG não fecha com o corpo (%d vs %d)" % (nome, tab[-1] * 8, len(corpo)))
        # cada VAG tem de terminar num bloco com flag de fim (bit0) — prova de que a base
        # do corpo (hdr + total) está certa
        for k in range(1, len(tab)):
            chk(corpo[tab[k] * 8 - 16 + 1] & 0x01,
                "%s: VAG %d não termina em flag de fim" % (nome, k))
        chk(info["n_se"] == 4, "%s: esperadas 4 entradas de SE, achei %d" % (nome, info["n_se"]))
        chk(info["banco"] == 4, "%s: banco deveria ser 4 (porta), achei %s" % (nome, info["banco"]))
    chk(n_porta == 76, "76 bancos de porta parseados, achei %d" % n_porta)

    # o id 0 (som principal da porta) existe e e' VALIDO nas 76; e a tabela e' template
    padroes = set()
    n_desc_porta = n_inval = 0
    for nome, p in portas:
        info = parse_porta(nome, p)[0]
        vh = open(p, "rb").read()
        padroes.add(tuple(struct.unpack_from("<4I", vh, 0)))
        n_desc_porta += len(info["se"])
        n_inval += sum(1 for v in info["se"].values() if "invalido" in v)
        chk(0 in info["se"] and "invalido" not in info["se"][0],
            "%s: id 0 (som principal) deveria ser valido" % nome)
    chk(len(padroes) == 3,
        "esperados 3 padroes distintos de tabela SE nas portas, achei %d" % len(padroes))
    chk(all(pd[0] == 0x00601408 and pd[1] == 0x00612408 for pd in padroes),
        "os ids 0 e 1 das portas deveriam ser identicos nas 76 (template)")
    chk((n_desc_porta, n_inval) == (159, 12),
        "portas: esperados 159 descritores com 12 invalidos, achei %d com %d"
        % (n_desc_porta, n_inval))

    print("verificacao: %d ok, %d falha" % (ok, falha))
    return ok, falha


def tabela(nome):
    d = sound_dir()
    ph = os.path.join(d, nome + (".SND" if nome == "R000" else ".VH"))
    pc = os.path.join(d, CORPO_ESPECIAL.get(nome, nome + ".VB"))
    b = parse_banco(nome, ph, pc)
    print("%s: banco=%s n_se=%d n_tons=%d n_vags=%d |.VB|=%d"
          % (nome, b["banco"], b["n_se"], b["n_tons"], b["n_vags"], b["vb_bytes"]))
    print(" id  descritor  tom vag  Hz    voz          wav")
    for i, v in sorted(b["se"].items()):
        print("%3d  %s %3d %3d %6d  %-11s %s"
              % (i, v["desc"], v["tom"], v["vag"], v["taxa_hz"],
                 "dinamica" if v["voz_dinamica"] else "fixa/%d" % v["voz_base"],
                 v["wav"] or "(mudo)"))


def main(argv):
    if "--verificar" in argv:
        return 1 if verificar()[1] else 0
    if "--tabela" in argv:
        tabela(argv[argv.index("--tabela") + 1])
        return 0
    if "--portas" in argv:
        extrair_portas()
        return 0
    gerar()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
