#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mensagens.py — extrai TODO o texto de CAIXA DE MENSAGEM do RE3 (PS1 NTSC-U) em PT-BR.

Alvos:
  * `extracted/ntsc-u/CD_DATA/STAGE{1..7}/R*.ARD`  -> mensagens POR SALA (secao MSG do RDT)
  * `extracted/ntsc-u/SLUS_009.23`                 -> as duas POOLS lineares do EXE
  * `<GOG>/mod_BH3_Portuguese/xml/`                -> o texto em PT-BR (rdt/R###.xml,
                                                      prompt.xml, system.xml)

Saida: `<out>/data/mensagens.json` (out = NOSTALGIA_OUT, ver tools/paths.py).
Consumidor: `port/present/mensagem.gd`.

================================================================================
1. DE ONDE VEM CADA MENSAGEM  — PROVADO por desmontagem
================================================================================
O unico "abridor de caixa de mensagem" do jogo e **`0x8002fd30`** (30 sitios de `jal` no EXE):

    0x8002fd30  abre_mensagem(a0 = x/param, a1 = flags, a2 = indice, a3 = param<<16)

`a1 & 0x3000` escolhe a POOL (`0x8002fd88`..`0x8002fdb4`):

  | a1 & 0x3000 | tabela de offsets | base do texto      | caixa (x,y) | sitio          |
  |-------------|-------------------|--------------------|-------------|----------------|
  | `0x0000`    | `0x80099654`      | `0x80098e88`       | **34, 185** | `0x8002fdc4`+  |
  | `0x1000`    | `0x8009bdb4`      | `0x800996e4`       | **14, 173** | `0x8002fdf0`+  |
  | `0x2000`    | `RDT + 0x3c`      | idem (auto-relativa)| **34, 185** | `0x8002fe20`+  |

O caso `0x2000` e a prova de onde vive a mensagem DE SALA:

    8002fe28  lw $v1, 0x2134($t1)   # t1 = 0x800ca738 -> *(0x800cc86c) = ponteiro do RDT
    8002fe34  lw $v1, 0x3c($v1)     # RDT + 0x3c
    8002fe38  sll $v0, $a2, 1       # indice * 2
    8002fe44  lhu $v0, ($v0)        # offs[indice]  (u16)
    8002fe4c  addu $v1, $v1, $v0    # ponteiro do texto

A tabela de offsets do RDT comeca em `RDT + 0x08`, logo `0x3c` = entrada
**(0x3c - 0x08) / 4 = 13**  ->  **`offset_table[13]` = a secao MSG da sala.**
Confirmacao pelo conteudo: em `R100` a secao tem `u16[0] = 8` (=> `8/2 = 4` mensagens) e a
primeira decodifica como `"An area map for the\ndelivery service."`, que e exatamente a 1a
`<Text>` do `mod_BH3_Portuguese/xml/rdt/R100.xml` ("Um mapa da area pro servico de entrega").
Formato da secao: `u16 offs[n]` (n = `offs[0]/2`), offsets relativos ao inicio da secao,
texto terminado em `0xFE`.

Quem dispara mensagem de sala (as duas portas de entrada, ambas com `| 0x2000`):
  * **AOT `sce == 4`** — handler `0x80051284`: `a1 = u16@payload+2 | 0x2000`,
    `a2 = u16@payload+0` (= o INDICE na sala), `a3 = u16@payload+4 << 16`.
  * **opcode `0x5B` do SCD** (6 B) — handler `0x80054d74` (ponteiro em `0x8009e264`, e a
    jump-table da VM e `0x8009e0f8`, logo `op = (0x8009e264-0x8009e0f8)/4 = 0x5B`):
    `a2 = u8@+1` = indice, `a1 = u16@+2 | 0x2000`, `a3 = u16@+4 << 16`.

================================================================================
2. AS MENSAGENS DE PORTA  — PROVADO em `0x80050d28` (o handler de `sce 1`)
================================================================================
Todos os indices abaixo sao da **pool 0 (prompt)**, exceto onde dito:

    desc+0x0f & 0x80 == 0            -> porta livre, nenhuma mensagem      (0x80050d80)
    flag "ja destrancada" acesa      -> porta livre, nenhuma mensagem      (0x80050db4)
    Key_Type (desc+0x10) == 0xFE     -> mensagem  17  + SE 0x226           (0x80050de8)
    Key_Type == 0xFF                 -> mensagem  18  + SE 0x216           (0x80050e24)
    TEM a chave (0x8006cc8c >= 0)    -> mensagem   5  + SE 0x225/0x204     (0x80050e44)
    NAO tem a chave:
        desc+0x11 & 0x80             -> mensagem DA SALA, indice = desc+0x11 & 0x0F
                                        (`a1 = 0x2000` em 0x80050ee4/0x80050ee8)
        senao                        -> mensagem `Key_Type - 0x5F`         (0x80050f24)
    desc+0x11 & 0x40 (ESCADA)        -> mensagem 10 (sobe, desc+0x0d == 4)
                                        ou 11 (desce)                     (0x80050f68/0x80050f70)

Duas ancoras independentes travam a formula `idx = Key_Type - 0x5F`:
  * `Key_Type 0x73` (Warehouse Key, cujo nome alternativo e "Backdoor Key") -> `0x73-0x5F = 20`
    e `prompt[20]` = *"It's the backdoor exit. It's locked."*
  * `Key_Type 0x75` (Emblem Key / alt. o cartao com os glifos `EA24..EA28`) -> `22`
    e `prompt[22]` = *"You'll need the {S.T.A.R.S.} Key to unlock it."*

================================================================================
3. AS MENSAGENS DE ITEM  — sitios de `jal 0x8002fd30` (todos varridos)
================================================================================
    0x8006a1d8  a1=0x1000 a2=6   -> sistema[6]  "Voce pegou: {item}."   (dentro de 0x8006a020,
                                    que grava {id,qtd,flags} no slot)
    0x80069dfc  a1=0x1000 a2=1   -> sistema[1]  "Voce nao pode carregar mais itens."
    0x80069db0  a1=0x1400 a2=var -> sistema[?]  (janela de obter, com prompt sim/nao)
    0x80069380  a1=0x1100 a2=u8  -> sistema[16 + item_id] = EXAME do item (tela de status)
    0x800516a4  a1=0      a2=4   -> prompt[4]   "Nao tem mais nada."      (`sce 11`)
    0x8005190c  a1=0      a2=5   -> prompt[5]   "Voce usou: {item}."
    0x800513cc  a1=0      a2=0/1 -> prompt[0]/[1] maquina de escrever     (`sce 8`)
    0x80051d60  a1=0      a2=7/9 -> prompt[7]/[9] ervas                   (`sce 14`)

================================================================================
4. O PT-BR
================================================================================
`mod_BH3_Portuguese` (pacote da versao GOG) traz o texto ja traduzido:
  * `xml/rdt/R###.xml`  -> 129 arquivos; a ORDEM das `<Text>` == o indice de mensagem da sala.
    **As 127 salas que tem secao MSG no NTSC-U estao TODAS cobertas** (o mod ainda traz `R623`
    e `R416`, que no NTSC-U nao tem secao MSG / nao existem como `.ARD`).
  * `xml/prompt.xml`    -> pool 0 (72 entradas uteis; o arquivo tem 73)
  * `xml/system.xml`    -> pool 1 (16 de sistema + os exames de item a partir do indice 17)

O mod codifica os controles como tags textuais. O de-para tag <-> byte foi MEDIDO comparando,
mensagem a mensagem, a sequencia de controles do EN (bytes do RDT) com a do PT (tags do XML)
nas 127 salas: 1128 mensagens, e nas que a sequencia tem o mesmo tamanho o valor numerico bate
em 100% dos casos de `{snd}` (11/11), `{cut}` (10/10), `{string}` (6/6), `{color}` (66/66),
`{scroll}` (653/654) e `{clear}` (152/155):

    {scroll N} / {timed N} = 0xFA N   (temporizacao; sem efeito visual)
    {snd N}                = 0xF3 N
    {cut N}                = 0xF4 N
    {s}                    = 0xF5      (avanca a largura de um espaco)
    {string N}             = 0xF8 N    (insere o NOME do item; 0 = item corrente)
    {color N}              = 0xF9 N
    {branch N}             = 0xFB N    (prompt sim/nao; 2 bytes, nao 1)
    \n                     = 0xFC
    {clear N}              = 0xFD N    (nova PAGINA)
    {live}                 = 0xFE      separador de OPCAO dentro de uma mensagem de `{branch}`
                                       (ex.: R110 msg 1 = "Lutar com monstro." / "Entrar na
                                       delegacia.", duas opcoes numa unica entrada da tabela)

### Normalizacao de acento — DECLARADA (decisao do port, nao medida)
A fonte alternativa que o mod usa nao tem `a`/`o` com TIL, e o tradutor escreveu **trema**:
"Nao"->"Näo", "municao"->"municäo", "portao"->"portäo", "Municoes"->"Municöes". O atlas HD que
o port usa (`assets/FONT/hd_texu.webp`) TEM `a` e `o` com til (codigos 159 e 129 em
`data/re3_font_pt.json`), entao o extrator troca `ä->a-til`, `ö->o-til` (e as maiusculas).
Sao 431 + 24 ocorrencias. Tambem normaliza `<<`/`>>` -> as aspas curvas do charset (codigos
`0x09`/`0x0A`), `„`/`‟` idem, e os S/T/A/R/S de largura dupla -> "S.T.A.R.S.".

================================================================================
5. MARCACAO CANONICA DA SAIDA (a que `port/present/mensagem.gd` interpreta)
================================================================================
    \n          nova linha
    {p}         nova pagina (limpa a caixa)
    {c:N}       cor N (linha de CLUT; 1 = verde de destaque de item)
    {i:NN}      nome do item NN em hex; `{i:00}` = "item corrente"
    {sn}        prompt SIM/NAO
    {op}        separador de OPCAO (as opcoes de um `{sn}` multiplo)
    {s:NN}      efeito sonoro NN
    {cam:NN}    troca de camera
    {t:NN}      temporizacao (ignorada no desenho)

Uso:
    python tools/mensagens.py --censo
    NOSTALGIA_OUT=port python tools/mensagens.py --build
    PYTHONIOENCODING=utf-8 python tools/mensagens.py --dump R100
"""
import argparse
import collections
import glob
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths                                    # noqa: E402  destino do pipeline

sys.stdout.reconfigure(encoding="utf-8")

ROOT = paths.ROOT
CD_DATA = paths.cd_data()
SLUS = paths.extracted("SLUS_009.23")
GOG = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"
MOD = os.path.join(GOG, "mod_BH3_Portuguese", "xml")

# ---------------------------------------------------------------- RDT / .ARD
SECTOR = 0x800
OFFTAB_N = 22
OFF_MSG = 13                    # PROVADO: 0x8002fe34 le RDT+0x3c = offset_table[13]

# ---------------------------------------------------------------- as duas pools do EXE
EXE_BASE = 0x80010000
POOL = [
    # (nome, tabela de offsets, base do texto, caixa x, caixa y, n)
    ("prompt", 0x80099654, 0x80098E88, 34, 185, 72),
    ("sistema", 0x8009BDB4, 0x800996E4, 14, 173, 151),
]
# Mini-pool do prompt SIM/NAO, 8 B antes da base da pool 0. PROVADO: os bytes em
# `0x80098E80` sao `35 41 4f FE 2a 4b FE` = "Yes" `0xFE` "No" `0xFE`, e `0x800303ec` usa esta
# mini-pool quando o nibble `(*s >> 4) & 7` do 1o byte da mensagem e' 0 (menu_texto.md §3.2).
SIM_NAO_EN = 0x80098E80
# O mod NAO traduz esta mini-pool (prompt.xml comeca em 0x80098E88). O PT vem de `card.xml`
# indices 7/8 ("Sim"/"Näo"), que e' a MESMA dupla na tela de memory card. DECLARADO: outra pool.
SIM_NAO_PT_XML = ("card.xml", 7, 8)

# mensagens de PORTA (pool "prompt") — ver §2 do docstring
MSG_PORTA = {
    "key_type_fe": 17,          # 0x80050de8  a2 = 0x11
    "key_type_ff": 18,          # 0x80050e24  a2 = 0x12
    "usou_a_chave": 5,          # 0x80050e44  a2 = 5
    "escada_sobe": 10,          # 0x80050f68  a2 = 0x0a  (desc+0x0d == 4)
    "escada_desce": 11,         # 0x80050f70  a2 = 0x0b
    "base_key_type": 0x5F,      # 0x80050f24  a2 = Key_Type - 0x5F
    "porta_travada_global": 12,  # 0x80050da4  a2 = 0x0c  ("A porta nao abre!")
}
# mensagens de ITEM / uso (pool "sistema" e "prompt") — §3
MSG_ITEM = {
    "pegou": 6,                 # sistema[6]  0x8006a1d8
    "sem_espaco": 1,            # sistema[1]  0x80069dfc
    "quer_pegar": 0,            # sistema[0]  "Voce quer pegar: {item}?" + {sn}
    "exame_base": 16,           # sistema[16 + item_id] (0x80069380)
    "nada_aqui": 4,             # prompt[4]   0x800516a4 (sce 11)
    "usou": 5,                  # prompt[5]   0x8005190c
    "nao_preciso": 9,           # prompt[9]
}

# ---------------------------------------------------------------- charset (byte -> caractere)
# Tabela do EXE, a mesma de tools/menu_texto.py §1.4 (docs/decomp/notes/menu_texto.md).
CHARSET = {
    0x00: " ", 0x01: ".", 0x02: "\u25b6", 0x03: "\u300c", 0x04: "\u300d", 0x05: "(",
    0x06: ")", 0x07: "\u300e", 0x08: "\u300f", 0x09: "\u201c", 0x0A: "\u201d",
    0x0B: "\u25bc", 0x16: ":", 0x17: "\u3001", 0x18: ",", 0x19: "\u25b2", 0x1A: "!",
    0x1B: "?", 0x1C: "$", 0x37: "+", 0x38: "/", 0x39: "\u2212", 0x3A: "\u2019",
    0x3B: "\u2014", 0x3C: "\u00b7",
}
for _i in range(10):
    CHARSET[0x0C + _i] = chr(0x30 + _i)
for _i in range(26):
    CHARSET[0x1D + _i] = chr(0x41 + _i)
for _i in range(26):
    CHARSET[0x3D + _i] = chr(0x61 + _i)

# a sequencia do banco 0xEA que o jogo usa para o cartao S.T.A.R.S. (menu_texto.md §1.5)
STARS_EA = "{gEA:24}{gEA:25}{gEA:26}{gEA:27}{gEA:24}"


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def rdt_of(path):
    """Devolve o bloco RDT (tipo 0x00, sempre o indice 8) de um `.ARD`."""
    d = open(path, "rb").read()
    _total, count = struct.unpack_from("<II", d, 0)
    pos = SECTOR
    for i in range(count):
        length, flag_a, _flag_b = struct.unpack_from("<IHH", d, 8 + i * 8)
        if (flag_a & 0xFF) == 0x00:
            return d[pos:pos + length]
        pos = (pos + length + SECTOR - 1) // SECTOR * SECTOR
    return None


def secao_msg(rdt):
    """`(inicio, fim)` da secao MSG (`offset_table[13]`), ou `None` se a sala nao tem."""
    if rdt is None or len(rdt) < 8 + OFFTAB_N * 4:
        return None
    off = struct.unpack_from("<%dI" % OFFTAB_N, rdt, 8)
    p = off[OFF_MSG]
    if p == 0 or p >= len(rdt):
        return None
    fim = min([x for x in off if x > p] + [len(rdt)])
    return (p, fim)


# ---------------------------------------------------------------- decoder EN (bytes -> canonico)
CTRL_GLIFO = (0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF0)


def decode_en(buf, i, fim):
    """Decodifica uma mensagem do charset RE3 para a marcacao canonica (§5).

    Para em `0xFE` — o chamador decide se o `0xFE` era fim de mensagem ou separador de opcao.
    Devolve `(texto, i_apos_o_0xFE, parou_em_fe)`.
    """
    out = []
    while i < fim:
        c = buf[i]
        if c == 0xFE:
            return "".join(out), i + 1, True
        if c in CHARSET:
            out.append(CHARSET[c])
            i += 1
        elif c == 0xFC:
            out.append("\n")
            i += 1
        elif c == 0xF5:
            out.append(" ")
            i += 1
        elif c == 0xF6:
            out.append(" ")          # 0xF6 = meio espaco (avanca 7 px)
            i += 1
        elif c in CTRL_GLIFO:
            out.append("{g%02X:%02X}" % (c, buf[i + 1] if i + 1 < fim else 0))
            i += 2
        elif c == 0xF3:
            out.append("{s:%02X}" % buf[i + 1])
            i += 2
        elif c == 0xF4:
            out.append("{cam:%02X}" % buf[i + 1])
            i += 2
        elif c == 0xF8:
            out.append("{i:%02X}" % buf[i + 1])
            i += 2
        elif c == 0xF9:
            out.append("{c:%d}" % (buf[i + 1] & 0x0F))
            i += 2
        elif c == 0xFA:
            out.append("{t:%02X}" % buf[i + 1])
            i += 2
        elif c == 0xFB:
            out.append("{sn}")
            i += 2
        elif c == 0xFD:
            out.append("{p}")
            i += 2
        elif c == 0xF7:
            i += 1                   # fim de nome de item — nao ocorre em mensagem de sala
        else:
            out.append("<%02X>" % c)
            i += 1
    return "".join(out), i, False


def normaliza(t):
    """S.T.A.R.S. e aspas — igual nos dois idiomas."""
    t = t.replace(STARS_EA, "S.T.A.R.S.")
    for fw in ("\uff33\uff34\uff21\uff32\uff33", "\uff33 \uff34 \uff21 \uff32 \uff33",
               "\uff33 \uff34 \uff21 \uff32\uff33", "\uff33\uff34\uff21\uff32"):
        t = t.replace(fw, "S.T.A.R.S.")
    t = t.replace("\u2160", "I")
    t = (t.replace("\u00ab", "\u201c").replace("\u00bb", "\u201d")
          .replace("\u201e", "\u201c").replace("\u201f", "\u201d"))
    return t


# `ä`/`ö` do mod == `ã`/`õ` (a fonte alternativa do mod nao tem til). DECLARADO.
TIL = {"\u00e4": "\u00e3", "\u00c4": "\u00c3", "\u00f6": "\u00f5", "\u00d6": "\u00d5"}


def normaliza_pt(t):
    n = 0
    for a, b in TIL.items():
        n += t.count(a)
        t = t.replace(a, b)
    return normaliza(t), n


# ---------------------------------------------------------------- decoder PT (tags -> canonico)
TAG_PT = {
    "clear": "{p}",
    "color": "{c:%d}",
    "string": "{i:%02X}",
    "branch": "{sn}",
    "snd": "{s:%02X}",
    "cut": "{cam:%02X}",
    "scroll": "{t:%02X}",
    "timed": "{t:%02X}",
    "live": "{op}",
    "s": " ",
}


def _sub_tag(m):
    nome = m.group(1)
    val = int(m.group(2)) if m.group(2) else 0
    if nome not in TAG_PT:
        return ""                                  # tag desconhecida: derruba (nada inventado)
    forma = TAG_PT[nome]
    return forma % (val & 0xFF) if "%" in forma else forma


def decode_pt(t):
    t = (t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
          .replace("&#34;", '"').replace("&#39;", "'").replace("&quot;", '"'))
    t = re.sub(r"\{(\w+)\s*(\d*)\}", _sub_tag, t)
    t = t.replace("\\n", "\n")
    return t


def texts_xml(path):
    x = open(path, encoding="utf-8-sig").read()
    return re.findall(r"<Text>(.*?)</Text>", x, re.S)


# ---------------------------------------------------------------- coleta
def salas_en():
    """`{sala: [texto_canonico, ...]}` das 169 salas (ausente = sala sem secao MSG)."""
    out = {}
    for p in sorted(glob.glob(os.path.join(CD_DATA, "STAGE*", "R*.ARD"))):
        nome = os.path.basename(p)[:-4]
        rdt = rdt_of(p)
        sec = secao_msg(rdt)
        if sec is None:
            out[nome] = None
            continue
        ini, fim = sec
        n = _u16(rdt, ini) // 2
        offs = [_u16(rdt, ini + i * 2) for i in range(n)]
        msgs = []
        for k, o in enumerate(offs):
            lim = ini + (offs[k + 1] if k + 1 < n else (fim - ini))
            i = ini + o
            # A mensagem termina no 1o `0xFE`... EXCETO quando ela tem prompt (`0xFB`): aí o
            # `0xFE` separa as OPÇÕES e a entrada da tabela cobre todas (o mod chama isso de
            # `{live}`; ex.: R110 msg 1 = "Lutar com monstro." / "Entrar na delegacia.").
            # Paro na primeira parte que só tem padding (`0x00`) ou byte desconhecido — é o
            # que impede a última mensagem de invadir a seção seguinte do RDT.
            partes = []
            for _ in range(9):
                txt, i, achou = decode_en(rdt, i, lim)
                partes.append(txt)
                if not achou or "{sn}" not in "".join(partes):
                    break
                if i >= lim:
                    break
                prox, _j, _a = decode_en(rdt, i, lim)
                if prox.strip() == "" or "<" in prox:
                    break
            msgs.append(normaliza("{op}".join(partes)))
        out[nome] = msgs
    return out


def salas_pt():
    """`{sala: [texto_canonico, ...]}` do mod PT-BR + total de acentos normalizados."""
    out, tot_til = {}, 0
    for p in sorted(glob.glob(os.path.join(MOD, "rdt", "*.xml"))):
        nome = os.path.basename(p)[:-4]
        msgs = []
        for t in texts_xml(p):
            t, n = normaliza_pt(decode_pt(t))
            tot_til += n
            msgs.append(t)
        out[nome] = msgs
    return out, tot_til


def pools_en():
    """As duas pools lineares do EXE -> `{nome: [texto, ...]}`."""
    raw = open(SLUS, "rb").read()

    def rd(v):
        return (v - EXE_BASE) + 0x800

    out = {}
    for nome, tbl, base, _cx, _cy, n in POOL:
        msgs = []
        for i in range(n):
            o = struct.unpack_from("<H", raw, rd(tbl) + i * 2)[0]
            ini = rd(base) + o
            txt, _i, _f = decode_en(raw, ini, min(ini + 0x400, len(raw)))
            msgs.append(normaliza(txt))
        out[nome] = msgs
    return out


def portas():
    """Resolve, para as 453 portas do jogo, QUAL mensagem o `0x80050d28` mostraria.

    O descritor da porta comeca em `opcode + 2 + DOOR_PATH[op]` (`0x61` -> +0x0E, `0x62` -> +0x16;
    e o mesmo caminho que `tools/exe_audio.py --portas-salas` usa para o `Dtex_Type`, provado em
    `0x8001647c`). Os campos que a arvore de decisao le:

        desc+0x0D  Door_Type   (== 4 -> escada SOBE, senao DESCE)
        desc+0x0E  Knock_Type  (so muda o SE)
        desc+0x0F  Key_Id      (bit 0x80 = "esta porta e trancada"; bits 0..5 = indice da flag)
        desc+0x10  Key_Type    (0xFE / 0xFF especiais; senao o item da chave)
        desc+0x11  bit 0x80 -> a mensagem vem da SALA (indice = & 0x0F)
                   bit 0x40 -> e ESCADA (prompt 10/11)
    """
    import scd_door_dest as sdd
    out = {}
    hist = collections.Counter()
    for p in sorted(glob.glob(os.path.join(CD_DATA, "STAGE*", "R*.ARD"))):
        nome = os.path.basename(p)[:-4]
        rdt = rdt_of(p)
        if rdt is None:
            continue
        so = sdd.script_off(rdt)
        nf = _u16(rdt, so) // 2
        foffs = [_u16(rdt, so + i * 2) for i in range(nf)]
        achadas = []
        for fi in range(nf):
            pc = so + foffs[fi]
            fim = so + foffs[fi + 1] if fi + 1 < nf else len(rdt)
            guarda = 0
            while pc < fim and pc + 1 < len(rdt) and guarda < 8000:
                guarda += 1
                op = rdt[pc]
                if op == 0x01:
                    break
                sz = sdd.VM_SIZES.get(op)
                if sz is None:
                    break
                if op in sdd.DOOR_OPCODES and pc + sz <= len(rdt) and rdt[pc + 2] in sdd.DOOR_SCE:
                    b = bytes(rdt[pc:pc + sz])
                    d = 2 + sdd.DOOR_PATH[op]
                    e = {"aot": b[1], "sce": b[2],
                         "door_type": b[d + 0x0D], "knock": b[d + 0x0E],
                         "key_id": b[d + 0x0F], "key_type": b[d + 0x10],
                         "campo_11": b[d + 0x11]}
                    hist["campo11=0x%02x" % e["campo_11"]] += 1
                    achadas.append(e)
                pc += sz
        if achadas:
            out[nome] = achadas
    return out, dict(hist)


def resolve_porta(e, tem_chave=False):
    """`(caixa, indice)` da mensagem daquela porta — a arvore de `0x80050d28`.

    `caixa` = `"prompt"` (pool 0) ou `"sala"` (a secao MSG da propria sala); `""` = sem mensagem.
    QUIRK registrado: 10 portas tem `Key_Id & 0x80` (trancada) com `Key_Type == 0`. No motor,
    `0x8006cc8c(0)` = "achar slot VAZIO", que devolve >= 0 quase sempre, entao o jogo cai no
    ramo "TEM a chave" e mostra `prompt[5]`. Aqui devolvo `""` (sem mensagem), porque o texto
    seria "Voce usou: ." com nome de item vazio. **DECLARADO.**
    """
    if e["campo_11"] & 0x40:
        return ("prompt",
                MSG_PORTA["escada_sobe" if e["door_type"] == 4 else "escada_desce"])
    if not (e["key_id"] & 0x80):
        return ("", -1)
    if e["key_type"] == 0xFE:
        return ("prompt", MSG_PORTA["key_type_fe"])
    if e["key_type"] == 0xFF:
        return ("prompt", MSG_PORTA["key_type_ff"])
    if tem_chave:
        return ("prompt", MSG_PORTA["usou_a_chave"])
    if e["campo_11"] & 0x80:
        return ("sala", e["campo_11"] & 0x0F)
    i = e["key_type"] - MSG_PORTA["base_key_type"]
    return ("prompt", i) if i >= 0 else ("", -1)


def sim_nao():
    """A mini-pool `Yes`/`No` de `0x80098E80` + o PT de `card.xml` (ver a nota da constante)."""
    raw = open(SLUS, "rb").read()
    o = (SIM_NAO_EN - EXE_BASE) + 0x800
    en = []
    i = o
    for _ in range(2):
        t, i, _f = decode_en(raw, i, o + 16)
        en.append(normaliza(t))
    arq, i_sim, i_nao = SIM_NAO_PT_XML
    c = texts_xml(os.path.join(MOD, arq))
    pt = [normaliza_pt(decode_pt(c[i_sim]))[0], normaliza_pt(decode_pt(c[i_nao]))[0]]
    return {
        "en": en, "pt": pt, "addr": "0x%08X" % SIM_NAO_EN,
        "nota": "EN provado nos bytes de 0x80098E80 ('Yes' 0xFE 'No' 0xFE). PT de "
                "card.xml[%d]/[%d] — o mod nao traduz esta mini-pool. DECLARADO."
                % (i_sim, i_nao),
    }


def pools_pt():
    """`prompt.xml` -> pool 0 · `system.xml` -> pool 1."""
    out, tot = {}, 0
    for nome, arq in (("prompt", "prompt.xml"), ("sistema", "system.xml")):
        msgs = []
        for t in texts_xml(os.path.join(MOD, arq)):
            t, n = normaliza_pt(decode_pt(t))
            tot += n
            msgs.append(t)
        out[nome] = msgs
    return out, tot


# ---------------------------------------------------------------- montagem
def vazio(t):
    """Mensagem sem NADA para mostrar (so controles / so espaco em branco)."""
    return re.sub(r"\{[^}]*\}|\s", "", t) == ""


def so_lixo(t):
    """Sobra JAPONESA no dado NTSC-U: a mensagem existe mas so tem bytes >= 0x57 (kana/kanji,
    que a versao US nao desenha) e glifos de banco alternativo. Ex.: `R105[6]`, `R315[0]`.
    Nao e' 'traducao faltando' — nao ha o que traduzir."""
    return re.sub(r"\{g[0-9A-F]{2}:[0-9A-F]{2}\}|<[0-9A-F]{2}>|\{[^}]*\}|\s", "", t) == ""


def build():
    en = salas_en()
    pt, til_salas = salas_pt()
    pen = pools_en()
    ppt, til_pools = pools_pt()

    salas = {}
    cen = collections.Counter()
    sem_msg, sem_pt, divergentes, vazias, sem_pt_msg, lixo = [], [], [], [], [], []
    for nome in sorted(en):
        lst = en[nome]
        if lst is None:
            sem_msg.append(nome)
            continue
        cen["salas_com_msg"] += 1
        cen["mensagens"] += len(lst)
        ptl = pt.get(nome)
        if ptl is None:
            sem_pt.append(nome)
            ptl = []
        elif len(ptl) != len(lst):
            divergentes.append("%s (%d en / %d pt)" % (nome, len(lst), len(ptl)))
        msgs = []
        for i, t_en in enumerate(lst):
            t_pt = ptl[i] if i < len(ptl) else ""
            if vazio(t_en) and vazio(t_pt):
                cen["vazias"] += 1
                vazias.append("%s[%d]" % (nome, i))
            elif not vazio(t_pt):
                cen["com_pt"] += 1
            elif so_lixo(t_en):
                cen["lixo_jp"] += 1
                lixo.append("%s[%d]" % (nome, i))
            else:
                cen["sem_pt"] += 1
                sem_pt_msg.append("%s[%d]" % (nome, i))
            msgs.append({"i": i, "pt": t_pt, "en": t_en})
        salas[nome] = msgs

    prt, hist11 = portas()
    n_portas = sum(len(v) for v in prt.values())
    cen["portas"] = n_portas
    for v in prt.values():
        for e in v:
            r = resolve_porta(e)
            e["caixa"] = r[0]
            e["idx"] = r[1]
            if r[0] != "":
                cen["portas_com_mensagem"] += 1

    pools = {}
    for nome, tbl, base, cx, cy, n in POOL:
        lst_en = pen[nome]
        lst_pt = ppt[nome]
        msgs = []
        for i, t_en in enumerate(lst_en):
            t_pt = lst_pt[i] if i < len(lst_pt) else ""
            msgs.append({"i": i, "pt": t_pt, "en": t_en})
            cen["pool_mensagens"] += 1
            if vazio(t_en) and vazio(t_pt):
                cen["pool_vazias"] += 1
            elif not vazio(t_pt):
                cen["pool_com_pt"] += 1
            else:
                cen["pool_sem_pt"] += 1
                sem_pt_msg.append("%s[%d]" % (nome, i))
        pools[nome] = {
            "caixa": [cx, cy],
            "tabela_offsets": "0x%08X" % tbl,
            "base_texto": "0x%08X" % base,
            "n": n,
            "msgs": msgs,
        }

    doc = {
        "_meta": {
            "gerado_por": "tools/mensagens.py",
            "fonte_en": "extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD (RDT offset_table[13]) + "
                        "SLUS_009.23 (pools 0x80099654 / 0x8009BDB4)",
            "fonte_pt": "mod_BH3_Portuguese/xml (rdt/R###.xml, prompt.xml, system.xml)",
            "abridor": "0x8002fd30 (a1 & 0x3000 escolhe a pool: 0=prompt, 0x1000=sistema, "
                       "0x2000=sala/RDT)",
            "gatilhos_de_sala": "AOT sce 4 (0x80051284, indice = u16@payload+0) e "
                                "opcode 0x5B do SCD (0x80054d74, indice = u8@+1)",
            "marcacao": {
                "\\n": "nova linha (0xFC)",
                "{p}": "nova pagina (0xFD)",
                "{c:N}": "cor / linha de CLUT (0xF9)",
                "{i:NN}": "nome do item NN em hex; 00 = item corrente (0xF8)",
                "{sn}": "prompt sim/nao (0xFB)",
                "{op}": "separador de opcao (0xFE interno / {live} do mod)",
                "{s:NN}": "efeito sonoro (0xF3)",
                "{cam:NN}": "troca de camera (0xF4)",
                "{t:NN}": "temporizacao, sem efeito visual (0xFA)",
                "{gXX:YY}": "glifo de banco alternativo nao mapeado",
            },
            "caixas": {"prompt": [34, 185], "sistema": [14, 173], "sala": [34, 185]},
            "altura_linha": 16,
            "normalizacao_pt": ("DECLARADA: 'a'/'o' com trema do mod -> com til (%d trocas); "
                               "<< >> -> aspas curvas do charset; S/T/A/R/S de largura dupla "
                               "-> 'S.T.A.R.S.'" % (til_salas + til_pools)),
            "censo": dict(cen),
            "salas_sem_secao_msg": sem_msg,
            "salas_sem_traducao": sem_pt,
            "salas_com_contagem_divergente": divergentes,
            "mensagens_vazias": vazias,
            "mensagens_sem_pt": sem_pt_msg,
            "mensagens_so_lixo_jp": lixo,
            "portas_descritor": ("desc = opcode + 2 + DOOR_PATH[op] (0x61 -> +0x0E, "
                                 "0x62 -> +0x16); campos +0x0D Door_Type, +0x0F Key_Id, "
                                 "+0x10 Key_Type, +0x11 seletor de mensagem"),
            "portas_campo_11": hist11,
        },
        "porta": MSG_PORTA,
        "item": MSG_ITEM,
        "sim_nao": sim_nao(),
        "portas": prt,
        "pools": pools,
        "salas": salas,
    }
    return doc


def censo(doc):
    m = doc["_meta"]
    c = m["censo"]
    print("== MENSAGENS DE SALA ==")
    print("  salas com secao MSG (offset_table[13]) : %d" % c.get("salas_com_msg", 0))
    print("  salas SEM secao MSG                    : %d" % len(m["salas_sem_secao_msg"]))
    print("  mensagens de sala                      : %d" % c.get("mensagens", 0))
    print("  ... com texto PT-BR do mod             : %d" % c.get("com_pt", 0))
    print("  ... COM texto EN e SEM PT-BR           : %d" % c.get("sem_pt", 0))
    print("  ... vazias nos DOIS idiomas (no dado)  : %d" % c.get("vazias", 0))
    print("  ... so sobra JP no EN (nada a traduzir) : %d" % c.get("lixo_jp", 0))
    print("  salas sem traducao                     : %s"
          % (", ".join(m["salas_sem_traducao"]) or "nenhuma"))
    print("  contagem EN != PT                      : %s"
          % (", ".join(m["salas_com_contagem_divergente"]) or "nenhuma"))
    print("== POOLS DO EXE ==")
    for nome, p in doc["pools"].items():
        com = sum(1 for x in p["msgs"] if not vazio(x["pt"]))
        vaz = sum(1 for x in p["msgs"] if vazio(x["pt"]) and vazio(x["en"]))
        print("  %-8s caixa=%s  n=%3d  com PT=%3d  vazias=%2d  EN sem PT=%d"
              % (nome, p["caixa"], p["n"], com, vaz, p["n"] - com - vaz))
    print("== PORTAS ==")
    print("  portas no SCD                          : %d" % c.get("portas", 0))
    print("  ... que mostram mensagem                : %d" % c.get("portas_com_mensagem", 0))
    print("  histograma do campo +0x11              : %s" % m["portas_campo_11"])
    if m["mensagens_sem_pt"]:
        print("== SEM PT-BR (tem EN de verdade, nao tem PT) ==")
        print("  " + ", ".join(m["mensagens_sem_pt"]))
    if m["mensagens_so_lixo_jp"]:
        print("== SO SOBRA JP no dado NTSC-U (nao ha o que traduzir) ==")
        print("  " + ", ".join(m["mensagens_so_lixo_jp"]))
    print("== SALAS SEM SECAO MSG ==")
    print("  " + ", ".join(m["salas_sem_secao_msg"]))


def dump(doc, sala):
    if sala in doc["salas"]:
        for e in doc["salas"][sala]:
            print("[%2d] PT: %s" % (e["i"], e["pt"].replace("\n", "\\n")))
            print("     EN: %s" % e["en"].replace("\n", "\\n"))
        return
    if sala in doc["pools"]:
        for e in doc["pools"][sala]["msgs"]:
            print("[%3d] PT: %s" % (e["i"], e["pt"].replace("\n", "\\n")))
            print("      EN: %s" % e["en"].replace("\n", "\\n"))
        return
    print("nao achei '%s' (salas R### ou pools: %s)" % (sala, list(doc["pools"])))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", action="store_true", help="grava <out>/data/mensagens.json")
    ap.add_argument("--censo", action="store_true", help="imprime a contagem e o que falta")
    ap.add_argument("--dump", metavar="SALA", help="imprime uma sala (R100) ou pool")
    a = ap.parse_args()
    if not (a.build or a.censo or a.dump):
        ap.print_help()
        return 0
    doc = build()
    if a.censo:
        censo(doc)
    if a.dump:
        dump(doc, a.dump)
    if a.build:
        d = paths.data()
        os.makedirs(d, exist_ok=True)
        out = os.path.join(d, "mensagens.json")
        with open(out, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=1)
        print("gravado: %s (%d salas, %d mensagens de sala, %d nas pools)"
              % (out, len(doc["salas"]), doc["_meta"]["censo"].get("mensagens", 0),
                 doc["_meta"]["censo"].get("pool_mensagens", 0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
