#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Extrator do SISTEMA DE TEXTO do RE3 PS1 NTSC-U (SLUS_009.23) + tela de ARQUIVO.

Tudo aqui foi lido do binario/dos dados do CD. Ver a prova completa em
`docs/decomp/notes/menu_texto.md`.

===============================================================================
1. ATLAS DE FONTE  ->  `ETC/TEXU.TIM` (indice 0x63 na tabela de arquivos do CD)
===============================================================================
TIM 4bpp, bloco de pixels 256 halfwords x 256 linhas = **1024 x 256 px**,
bloco de CLUT em VRAM (256,480) 32x30 (= 2 CLUTs de 16 cores por linha, 60 CLUTs).

O EXE carrega em `0x80029bd0`: `cd_read_file(a0=0x63, a1=0x8011a000, a2=1, a3="TEX_TIM")`
e sobe para a VRAM com `0x800784e0` depois de escrever `0x001c` em `0x800ccbbc`
(u8 pagina de textura = 0x1c, u8 linha de CLUT = 0x00).
O alocador de VRAM (`0x800784e0`) faz:
    prect.x = pagina*64 ; se pagina >= 0x10:  prect.x -= 1024 ; prect.y = 256
    crect.y = 480 + linha_de_clut       (crect.x fica o do proprio TIM)
=> pagina 0x1c = 28  ->  x = 28*64-1024 = **768**, y = **256**.
=> a fonte fica em VRAM (768,256)..(1023,511) e a CLUT em (256,480) 32x30.

GRADE DE GLIFOS (provada por desmontagem de `0x80031504`):
    celula = **14 x 14 px**,  **18 colunas por linha**
    U = (cod % 18) * 14
    V = (cod / 18) * 14 + 28        <- banco NORMAL (base V = 28)
Os bancos alternativos (prefixo 0xEA..0xF0) usam a mesma grade com outra base de V
e/ou a segunda pagina de textura -- ver BANCOS abaixo.

O codigo do caractere e' ASCII - 0x24 para 0x24..0x7A (o espaco ASCII 0x20 vira 0x00),
provado por `0x80031970` (`a3 = a1 - 0x24; if (a3 < 0x57)`) que indexa a MESMA tabela
de larguras que `0x800319f8` indexa com o codigo cru.

===============================================================================
2. DESENHO DE STRING
===============================================================================
`0x80031504  draw_string(a0 = x, a1 = y, a2 = const u8 *s, a3 = attr)`
    attr bits 0..2 : indice do "head" DR_MODE (camada) -> `0x800d4590 + buf*128 + n*16`
    attr bits 4..7 : cor -> CLUT y = 480 + 2*(attr>>4)
    attr bit  8    : 1 = proporcional (kerning), 0 = passo fixo de 14 px
    termina em 0xFE (ou 0xF7, que retorna SEM confirmar o ponteiro de prims)

`0x8003114c  draw_item_name(a0 = x, a1 = y, a2 = attr, a3 = item_id)`
    chama `get_item_name(0x800318dc)`; termina em 0xF7.

`0x80030cb8  draw_message(a0 = ctx)`  (efeito maquina de escrever, quebra de linha)
`0x800319f8  advance(a0 = proporcional?, a1 = cod, a2 = &x) -> passo`
    if (!a0 || cod >= 0x57) return 14;  *a2 -= tbl[cod].b0;  return tbl[cod].b0+tbl[cod].b1

TABELA DE LARGURAS: **`0x80098dd0`**, 0x57 (87) entradas de 2 bytes SIGNED
    b0 = margem esquerda da celula (o glifo e' desenhado em x - b0)
    b1 = complemento;  passo = b0 + b1
Indexada pelo CODIGO do charset (0x00..0x56). cod >= 0x57 -> passo fixo 14.

ALTURA DE LINHA = **16 px** (`0x80030fb0`: y += 0x10 no codigo 0xFC).

===============================================================================
3. CODIGOS DE CONTROLE (tabela de salto em `0x80010688`, cods 0xEA..0xFE,
   e a do renderizador de mensagem em `0x80010610`)
===============================================================================
  0xEA..0xF0 XX : glifo de BANCO ALTERNATIVO (2 bytes). XX passa pela mesma
                  grade 18x14. (tpage, CLUT, base de V) por codigo:
                    0xEA  pagina A (768,256)  CLUT +0    V = row*14 - 46
                    0xEB  pagina B (832,256)  CLUT +0    V = row*14 + 0
                    0xEC  pagina B (832,256)  CLUT +0    V = row*14 - 60
                    0xED  pagina A (768,256)  CLUT +10   V = row*14 + 0
                    0xEE  pagina A (768,256)  CLUT +10   V = row*14 - 60
                    0xEF  pagina B (832,256)  CLUT +10   V = row*14 + 0
                    0xF0  pagina B (832,256)  CLUT +10   V = row*14 - 60
                  (V e' gravado como BYTE -> negativo da' a volta em 256)
  0xF5          : avanca a largura de um espaco (1 byte)
  0xF6          : avanca 7 px (1 byte)
  0xF7          : fim de NOME de item; no renderizador de mensagem, RETORNA da
                  insercao iniciada por 0xF8
  0xF8 XX       : insere o NOME do item XX (XX = 0 -> item "corrente",
                  `0x800dbb5b`); ao achar o 0xF7 do nome volta para depois do par
  0xF9 XX       : cor do texto = XX & 0x0F  -> CLUT y = 480 + 2*cor
  0xFC          : nova linha: y += 16, x = x_inicial da caixa
  0xFD XX       : nova pagina: y = y base da caixa
  0xFE          : fim da string
  0xF1/0xF2/0xFB: NAO sao controle - caem no caminho de glifo normal
  0xF3/0xF4/0xFA XX: 2 bytes, sem efeito visual nos desenhadores medidos

===============================================================================
4. TABELAS DE TEXTO (EN, no EXE; base virtual 0x80010000, off. arquivo = v-0x80010000+0x800)
===============================================================================
  NOMES de item  : pool `0x8009bee4` + tabela de offsets u16 `0x8009c7c0`
                   (indice = item_id, 0x00..0xC1). Terminador 0xF7.
                   `get_item_name(0x800318dc)`: se `desc[item].b2 != 0` e
                   `flag_test(0x800d2048, desc[item].b2)` -> usa o item
                   `(b2 - 0x55) & 0xff` (nome "identificado").
  MENSAGENS A    : pool `0x80098e88` + tabela u16 `0x80099654`  (caixa em x=34, y=185)
  MENSAGENS B    : pool `0x800996e4` + tabela u16 `0x8009bdb4`  (caixa em x=14, y=173)
                   (o 2o pool contem os EXAMES de item: o exame do item 1 esta em
                    `0x80099924` = pool_B + 0x240)

===============================================================================
5. TELA DE ARQUIVO (documentos)  ->  `ETC/FILEGU.PIX` (idx 0x1c) + `ETC/FILEI.TIM` (idx 0x1d)
===============================================================================
`FILEGU.PIX` = **183 TIMs concatenados** (nao ha cabecalho de container). A soma
dos 183 tamanhos da tabela `0x8009ef90` (u32) e' EXATAMENTE 4814848 = o tamanho do
arquivo. Duas formas de pagina:
    CAPA  (1a pagina de cada documento): 8bpp, 34816 B, 128x256 px, CLUT 256x1
    TEXTO (demais paginas)             : 4bpp, 24576 B, 256x176 px, CLUT 32x2
O texto dos documentos e' BITMAP PRE-RENDERIZADO -- nao passa pela fonte.

  `0x8009ef90` u32[183] : tamanho de cada pagina (offset = soma dos anteriores)
  `0x8009eed8` u8[183]  : byte copiado para `req+0x2a` do pedido de CD (NAO DECODIFICADO)
  `0x8009f26c` u16[31]  : 1a pagina (1-based) de cada documento
  `0x8009f2ac` u16[31]  : indice da ULTIMA pagina do documento (0-based)
                          -> n_paginas = valor + 1
  documento = item_id - 0x85  (itens 0x85..0xA3, classe 0x07)

Leitura parcial: `0x800636d4` monta o pedido de CD a mao (size = tabela, lba =
lba(FILEGU.PIX) + soma_anterior/2048) e chama `cd_read_file(a0=0x1c, ..., a2=2)`.
VRAM: capa -> pagina 0x17 (x=448,y=256) + CLUT y=490 ; texto -> pagina 0x18
(x=512,y=256) + CLUT y=491. tpages usados no desenho: **0x97** (8bpp,448,256) e
**0x18** (4bpp,512,256).

===============================================================================
USO
===============================================================================
    PYTHONIOENCODING=utf-8 python tools/menu_texto.py --all
    PYTHONIOENCODING=utf-8 python tools/menu_texto.py --font      # PNG + re3_font.json
    PYTHONIOENCODING=utf-8 python tools/menu_texto.py --text      # re3_text_en.json
    PYTHONIOENCODING=utf-8 python tools/menu_texto.py --file      # re3_file_screen.json + PNGs
    PYTHONIOENCODING=utf-8 python tools/menu_texto.py --dump-msg  # imprime as mensagens EN
"""
import argparse
import json
import os
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))

EXE = os.path.join(REPO, "extracted", "ntsc-u", "SLUS_009.23")
ETC = os.path.join(REPO, "extracted", "ntsc-u", "CD_DATA", "ETC")
DATA_OUT = os.path.join(REPO, "port", "data")
ASSET_OUT = os.path.join(REPO, "port", "assets")

# ---------------------------------------------------------------- enderecos
FONT_TIM_U = "TEXU.TIM"
FONT_TIM_J = "TEXJ.TIM"
GLYPH_W = GLYPH_H = 14
GLYPH_COLS = 18
GLYPH_V_BASE = 28          # banco normal
LINE_HEIGHT = 16

WIDTH_TBL = 0x80098DD0     # 0x57 entradas de 2 bytes signed
WIDTH_TBL_N = 0x57

NAME_POOL = 0x8009BEE4     # pool de nomes de item
NAME_OFFS = 0x8009C7C0     # u16[0xC2] offsets no pool
ITEM_DESC = 0x800A0514     # 4 bytes/item: {classe, stack, bit_flag, attr}
ITEM_ID_MAX = 0xC1

MSG_A_POOL = 0x80098E88
MSG_A_OFFS = 0x80099654
MSG_B_POOL = 0x800996E4
MSG_B_OFFS = 0x8009BDB4

FILE_PAGE_SIZE = 0x8009EF90   # u32[183]
FILE_PAGE_FLAG = 0x8009EED8   # u8[183]
FILE_DOC_START = 0x8009F26C   # u16[31]
FILE_DOC_LAST = 0x8009F2AC    # u16[31]
FILE_N_PAGES = 183
FILE_N_DOCS = 31
FILE_ITEM_ID0 = 0x85

# tabelas de salto de codigo de controle
CTRL_TBL_DRAWSTRING = 0x80010688
CTRL_TBL_MESSAGE = 0x80010610

# ---------------------------------------------------------------- charset
# Mapa cod -> caractere, LIDO DO ATLAS (recorte celula a celula de TEXU.TIM,
# grade 18x14 base V=28) e conferido contra a tabela de larguras 0x80098dd0.
# Codigos >= 0x57 existem na grade mas sao kana/kanji: nao mapeados aqui.
CHARSET = {
    0x00: " ",  0x01: ".",  0x02: "▶", 0x03: "「", 0x04: "」",
    0x05: "(",  0x06: ")",  0x07: "『", 0x08: "』", 0x09: "“",
    0x0A: "”", 0x0B: "▼",
    0x16: ":",  0x17: "、", 0x18: ",",  0x19: "▲", 0x1A: "!",
    0x1B: "?",  0x1C: "$",
    0x37: "+",  0x38: "/",  0x39: "−", 0x3A: "’", 0x3B: "—",
    0x3C: "·",
}
for _i in range(10):
    CHARSET[0x0C + _i] = chr(0x30 + _i)
for _i in range(26):
    CHARSET[0x1D + _i] = chr(0x41 + _i)
for _i in range(26):
    CHARSET[0x3D + _i] = chr(0x61 + _i)

CTRL_1BYTE = {0xF5: "{sp}", 0xF6: "{hsp}", 0xFC: "\n", 0xFE: "{end}", 0xF7: "{ret}"}
CTRL_2BYTE_GLYPH = (0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF0)
CTRL_2BYTE_OTHER = (0xF3, 0xF4, 0xF8, 0xF9, 0xFA, 0xFD)


def load_exe():
    from exe_parse import Exe
    return Exe(EXE)


# ---------------------------------------------------------------- decoder
def decode(buf, i, stop=(0xFE,)):
    """Decodifica uma string do charset RE3 -> texto legivel + tags.

    Devolve (texto, indice_apos_terminador, bytes_crus).
    """
    out = []
    start = i
    n = len(buf)
    while i < n:
        c = buf[i]
        if c in stop:
            i += 1
            break
        if c in CHARSET:
            out.append(CHARSET[c])
            i += 1
        elif c in CTRL_2BYTE_GLYPH:
            out.append("{g%02X:%02X}" % (c, buf[i + 1]))
            i += 2
        elif c == 0xF8:
            out.append("{item:%02X}" % buf[i + 1])
            i += 2
        elif c == 0xF9:
            out.append("{color:%d}" % (buf[i + 1] & 0x0F))
            i += 2
        elif c == 0xFD:
            out.append("{page:%02X}" % buf[i + 1])
            i += 2
        elif c in CTRL_2BYTE_OTHER:
            out.append("{%02X:%02X}" % (c, buf[i + 1]))
            i += 2
        elif c == 0xFC:
            out.append("\n")
            i += 1
        elif c in CTRL_1BYTE:
            out.append(CTRL_1BYTE[c])
            i += 1
        elif c in (0xF1, 0xF2, 0xFB):
            out.append("{g%02X}" % c)
            i += 1
        elif c == 0xF7:
            i += 1
            break
        else:
            out.append("<%02X>" % c)
            i += 1
    return "".join(out), i, bytes(buf[start:i])


# ---------------------------------------------------------------- TIM
def read_tim(raw, off=0):
    """Le um TIM cru -> dict {bpp, clut_rect, clut, pix_rect, pix, size}."""
    magic, flag = struct.unpack_from("<II", raw, off)
    assert magic == 0x10, "nao e TIM (magic=%08x)" % magic
    bpp = flag & 3
    o = off + 8
    clut = None
    crect = None
    if flag & 8:
        ln, cx, cy, cw, ch = struct.unpack_from("<IHHHH", raw, o)
        crect = (cx, cy, cw, ch)
        clut = raw[o + 12:o + ln]
        o += ln
    ln, px, py, pw, ph = struct.unpack_from("<IHHHH", raw, o)
    pix = raw[o + 12:o + ln]
    o += ln
    return {"bpp": bpp, "clut_rect": crect, "clut": clut,
            "pix_rect": (px, py, pw, ph), "pix": pix, "size": o - off}


def clut_colors(clut):
    cols = []
    for i in range(0, len(clut), 2):
        v = clut[i] | (clut[i + 1] << 8)
        r = (v & 31) << 3
        g = ((v >> 5) & 31) << 3
        b = ((v >> 10) & 31) << 3
        stp = (v >> 15) & 1
        # cor 0 do CLUT e' transparente no PS1 quando STP=0
        a = 0 if (i == 0 and v == 0) else 255
        cols.append((r | r >> 5, g | g >> 5, b | b >> 5, a, stp))
    return cols


def tim_to_image(tim, clut_row=0):
    """Devolve PIL.Image RGBA. Largura vem de pix_rect: 4bpp = w*4, 8bpp = w*2."""
    from PIL import Image
    px, py, pw, ph = tim["pix_rect"]
    bpp = tim["bpp"]
    cols = clut_colors(tim["clut"]) if tim["clut"] else None
    if bpp == 0:
        W = pw * 4
        rowb = pw * 2
        base = clut_row * 16
    elif bpp == 1:
        W = pw * 2
        rowb = pw * 2
        base = clut_row * 256
    else:
        raise ValueError("bpp %d nao suportado" % bpp)
    H = len(tim["pix"]) // rowb
    img = Image.new("RGBA", (W, H))
    put = img.load()
    pix = tim["pix"]
    for y in range(H):
        ro = y * rowb
        for x in range(W):
            if bpp == 0:
                by = pix[ro + (x >> 1)]
                idx = (by & 0xF) if (x & 1) == 0 else (by >> 4)
            else:
                idx = pix[ro + x]
            c = cols[base + idx] if cols and base + idx < len(cols) else (idx, idx, idx, 255, 0)
            put[x, y] = (c[0], c[1], c[2], 0 if idx == 0 else 255)
    return img


# ---------------------------------------------------------------- fonte
def do_font(e):
    outdir = os.path.join(ASSET_OUT, "FONT")
    os.makedirs(outdir, exist_ok=True)
    raw = open(os.path.join(ETC, FONT_TIM_U), "rb").read()
    tim = read_tim(raw)
    px, py, pw, ph = tim["pix_rect"]
    n_clut = len(tim["clut"]) // 32
    # PNG por linha de CLUT da coluna x=256 (a que draw_string usa: GetClut(0x100,y))
    cr = tim["clut_rect"]
    per_row = cr[2] // 16
    saved = []
    for row in range(cr[3]):
        idx = row * per_row  # coluna x=256 -> primeiro CLUT da linha
        img = tim_to_image(tim, clut_row=idx)
        name = "TEXU_clut_y%d.png" % (cr[1] + row)
        img.save(os.path.join(outdir, name))
        saved.append(name)
    # folha de conferencia: glifos 0x00..0x56 em ordem de codigo
    from PIL import Image
    base = tim_to_image(tim, clut_row=0)
    sheet = Image.new("RGBA", (16 * (GLYPH_W + 2), 6 * (GLYPH_H + 2)), (0, 0, 0, 255))
    for c in range(WIDTH_TBL_N):
        r, cl = divmod(c, GLYPH_COLS)
        g = base.crop((cl * GLYPH_W, r * GLYPH_H + GLYPH_V_BASE,
                       cl * GLYPH_W + GLYPH_W, r * GLYPH_H + GLYPH_V_BASE + GLYPH_H))
        sheet.paste(g, ((c % 16) * (GLYPH_W + 2), (c // 16) * (GLYPH_H + 2)))
    sheet.save(os.path.join(outdir, "TEXU_charset_sheet.png"))

    widths = []
    for i in range(WIDTH_TBL_N):
        b0, b1 = struct.unpack("<bb", e.bytes_at(WIDTH_TBL + i * 2, 2))
        widths.append({"code": i, "char": CHARSET.get(i), "trim_left": b0,
                       "b1": b1, "advance": b0 + b1})
    cols = clut_colors(tim["clut"])
    palettes = []
    for row in range(cr[3]):
        idx = row * per_row
        palettes.append({"vram_y": cr[1] + row, "vram_x": cr[0],
                         "colors": ["#%02x%02x%02x" % (c[0], c[1], c[2])
                                    for c in cols[idx:idx + 16]]})
    out = {
        "_fonte": "SLUS_009.23 + ETC/TEXU.TIM; ver docs/decomp/notes/menu_texto.md",
        "atlas": {
            "arquivo_cd": "ETC/TEXU.TIM", "indice_cd": 0x63,
            "bpp": 4, "largura_px": pw * 4, "altura_px": ph,
            "vram_x": 768, "vram_y": 256,
            "vram_pagina": 0x1C,
            "clut_vram": {"x": cr[0], "y": cr[1], "w": cr[2], "h": cr[3]},
            "n_cluts": n_clut,
            "pngs": saved, "folha_conferencia": "TEXU_charset_sheet.png",
        },
        "grade": {"celula_w": GLYPH_W, "celula_h": GLYPH_H, "colunas": GLYPH_COLS,
                  "v_base_banco_normal": GLYPH_V_BASE,
                  "u": "(cod % 18) * 14", "v": "(cod / 18) * 14 + 28"},
        "altura_de_linha": LINE_HEIGHT,
        "charset": {"%02X" % k: v for k, v in sorted(CHARSET.items())},
        "charset_regra": "cod = ASCII - 0x24 para ASCII 0x24..0x7A; espaco ASCII 0x20 -> cod 0x00",
        "tabela_larguras": {"endereco": "0x%08X" % WIDTH_TBL, "n": WIDTH_TBL_N,
                            "passo_default": 14, "entradas": widths},
        "attr_draw_string": {
            "bits_0_2": "indice do head DR_MODE (camada) em 0x800d4590+buf*128+n*16",
            "bits_4_7": "cor: CLUT y = 480 + 2*(attr>>4)",
            "bit_8": "1 = proporcional (usa tabela de larguras); 0 = passo fixo 14",
        },
        "cores_clut_coluna_256": palettes,
        "bancos_alternativos": {
            "0xEA": {"tpage_vram_x": 768, "clut_offset": 0, "v_offset": -46},
            "0xEB": {"tpage_vram_x": 832, "clut_offset": 0, "v_offset": 0},
            "0xEC": {"tpage_vram_x": 832, "clut_offset": 0, "v_offset": -60},
            "0xED": {"tpage_vram_x": 768, "clut_offset": 10, "v_offset": 0},
            "0xEE": {"tpage_vram_x": 768, "clut_offset": 10, "v_offset": -60},
            "0xEF": {"tpage_vram_x": 832, "clut_offset": 10, "v_offset": 0},
            "0xF0": {"tpage_vram_x": 832, "clut_offset": 10, "v_offset": -60},
            "_nota": "V e' byte: valor negativo da' a volta em 256",
        },
        "rotinas": {
            "draw_string": "0x80031504 (a0=x, a1=y, a2=str, a3=attr)",
            "draw_item_name": "0x8003114C (a0=x, a1=y, a2=attr, a3=item_id)",
            "draw_message": "0x80030CB8 (a0=ctx)",
            "advance": "0x800319F8 (a0=proporcional, a1=cod, a2=&x)",
            "advance_ascii": "0x80031970 (mesma tabela, indice = ASCII-0x24)",
            "get_item_name": "0x800318DC (a0=item_id)",
            "init_drmode_heads": "0x80031A48",
            "tabela_ctrl_draw_string": "0x%08X" % CTRL_TBL_DRAWSTRING,
            "tabela_ctrl_message": "0x%08X" % CTRL_TBL_MESSAGE,
        },
        "estado_caixa_de_texto": {
            "0x800DBB6E": "u16 y do cursor",
            "0x800DBB70": "u16 x inicial da linha",
            "0x800DBB72": "u16 y base da caixa",
            "0x800DBB76": "u16 flags (bits0-2 camada, bit8 proporcional)",
            "0x800DBB5B": "u8 item corrente para {item:00}",
            "0x800DBA94": "u32 ponteiro do alocador de primitivas",
            "0x800D8890": "base do buffer de primitivas (12800 B por buffer, 640 SPRT de 20 B)",
        },
    }
    out["rotulos_de_menu"] = do_stmoji(outdir)
    p = os.path.join(DATA_OUT, "re3_font.json")
    json.dump(out, open(p, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("fonte: %d PNG em %s" % (len(saved) + 1, outdir))
    print("gravado %s" % p)


def do_stmoji(outdir):
    """`ETC/STMOJIU.TIM` (idx 0x60) = rotulos de menu COMO SPRITE, nao como texto.

    256x72 px 4bpp, 9 CLUTs em VRAM (304,480). Carregado pelo EXE em `0x8006d82c`
    (`cd_read_file(a0=0x60, a1=0x801b1500, a2=0, a3="STMOJI.TIM")`) e subido com
    `0x800784e0` apos escrever `0x001a` em `0x800ccbbc` (pagina 0x1a -> VRAM x=640,
    y=256; linha de CLUT 0 -> y=480).

    As FAIXAS (v, altura) abaixo foram MEDIDAS por bounding box de tinta no atlas.
    Os u/w por rotulo sao aproximados (dependem do limiar de separacao): a tabela
    de descritores u/v/w/h do proprio jogo NAO FOI LOCALIZADA.
    """
    raw = open(os.path.join(ETC, "STMOJIU.TIM"), "rb").read()
    t = read_tim(raw)
    saved = []
    for r in range(t["clut_rect"][3]):
        nm = "STMOJIU_clut_y%d.png" % (480 + r)
        tim_to_image(t, clut_row=r).save(os.path.join(outdir, nm))
        saved.append(nm)
    return {
        "arquivo_cd": "ETC/STMOJIU.TIM", "indice_cd": 0x60,
        "bpp": 4, "w": 256, "h": 72,
        "vram_x": 640, "vram_y": 256, "vram_pagina": 0x1A,
        "clut_vram": {"x": t["clut_rect"][0], "y": t["clut_rect"][1],
                      "w": t["clut_rect"][2], "h": t["clut_rect"][3]},
        "carregado_em": "0x8006D82C",
        "pngs": saved,
        "_aviso": "u/w por rotulo MEDIDOS no atlas (bounding box de tinta); a tabela "
                  "u/v/w/h do jogo NAO foi localizada",
        "faixas": [
            {"v": 0, "h": 17, "conteudo": [
                {"nome": "setas ^ v < >", "u": 0, "w": 39},
                {"nome": "EXIT (grande)", "u": 43, "w": 40},
                {"nome": "3 molduras vazias", "u": 120, "w": 112, "v": 0, "h": 40}]},
            {"v": 20, "h": 11, "conteudo": [
                {"nome": "digitos 0-9 + % + 2 simbolos", "u": 5, "w": 102}]},
            {"v": 33, "h": 7, "conteudo": [
                {"nome": "Fine", "u": 1, "w": 23},
                {"nome": "Caution", "u": 27, "w": 34},
                {"nome": "Caution", "u": 67, "w": 34},
                {"nome": "Danger", "u": 107, "w": 35},
                {"nome": "Poison", "u": 147, "w": 30},
                {"nome": "NAO IDENTIFICADO (6o)", "u": 185, "w": 24}]},
            {"v": 41, "h": 14, "conteudo": [
                {"nome": "FILE", "u": 2, "w": 21},
                {"nome": "EXIT", "u": 26, "w": 40},
                {"nome": "MAP", "u": 75, "w": 29},
                {"nome": "AUTO", "u": 116, "w": 39},
                {"nome": "MANUAL", "u": 160, "w": 48}]},
            {"v": 56, "h": 15, "conteudo": [
                {"nome": "EQUIP", "u": 2, "w": 44},
                {"nome": "USE", "u": 53, "w": 38},
                {"nome": "COMBINE", "u": 96, "w": 55},
                {"nome": "PIECES", "u": 153, "w": 38},
                {"nome": "CHECK", "u": 194, "w": 44}]},
        ],
    }


# ---------------------------------------------------------------- texto
def read_pool(e, pool, offs_tbl, n, stop=(0xFE,)):
    """Le n strings via tabela de offsets u16."""
    res = []
    for i in range(n):
        off = e.u16(offs_tbl + i * 2)
        buf = e.bytes_at(pool + off, 512)
        txt, _, raw = decode(buf, 0, stop=stop)
        res.append({"idx": i, "offset": off, "addr": "0x%08X" % (pool + off),
                    "text": txt, "raw": raw.hex()})
    return res


def count_offs_table(e, tbl, pool_limit):
    """Conta entradas monotonicas plausiveis de uma tabela de offsets u16."""
    n = 0
    prev = -1
    while True:
        v = e.u16(tbl + n * 2)
        if v < prev or v > pool_limit:
            break
        prev = v
        n += 1
        if n > 400:
            break
    return n


def do_text(e):
    # nomes de item
    names = []
    for i in range(ITEM_ID_MAX + 1):
        off = e.u16(NAME_OFFS + i * 2)
        buf = e.bytes_at(NAME_POOL + off, 64)
        txt, _, raw = decode(buf, 0, stop=(0xF7,))
        d = e.bytes_at(ITEM_DESC + i * 4, 4)
        alt = ((d[2] - 0x55) & 0xFF) if d[2] else None
        names.append({"id": i, "offset": off, "name": txt, "raw": raw.hex(),
                      "desc": d.hex(), "flag_bit": d[2] or None,
                      "alt_name_id": alt})
    n_a = count_offs_table(e, MSG_A_OFFS, MSG_B_POOL - MSG_A_POOL)
    n_b = count_offs_table(e, MSG_B_OFFS, NAME_POOL - MSG_B_POOL)
    msg_a = read_pool(e, MSG_A_POOL, MSG_A_OFFS, n_a)
    msg_b = read_pool(e, MSG_B_POOL, MSG_B_OFFS, n_b)
    out = {
        "_fonte": "SLUS_009.23 (NTSC-U). Ver docs/decomp/notes/menu_texto.md",
        "item_names": {"pool": "0x%08X" % NAME_POOL, "offs": "0x%08X" % NAME_OFFS,
                       "terminador": "0xF7", "n": len(names), "entries": names},
        "messages_a": {"pool": "0x%08X" % MSG_A_POOL, "offs": "0x%08X" % MSG_A_OFFS,
                       "caixa_x": 34, "caixa_y": 185, "n": n_a, "entries": msg_a},
        "messages_b": {"pool": "0x%08X" % MSG_B_POOL, "offs": "0x%08X" % MSG_B_OFFS,
                       "caixa_x": 14, "caixa_y": 173, "n": n_b, "entries": msg_b,
                       "_nota": "contem os EXAMES de item; exame do item 1 em 0x80099924 = pool+0x240"},
    }
    p = os.path.join(DATA_OUT, "re3_text_en.json")
    json.dump(out, open(p, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("nomes=%d  msgA=%d  msgB=%d -> %s" % (len(names), n_a, n_b, p))


def do_dump_msg(e):
    n_a = count_offs_table(e, MSG_A_OFFS, MSG_B_POOL - MSG_A_POOL)
    n_b = count_offs_table(e, MSG_B_OFFS, NAME_POOL - MSG_B_POOL)
    for tag, pool, tbl, n in (("A", MSG_A_POOL, MSG_A_OFFS, n_a),
                              ("B", MSG_B_POOL, MSG_B_OFFS, n_b)):
        print("=== POOL %s  (%d entradas) ===" % (tag, n))
        for m in read_pool(e, pool, tbl, n):
            print("%s[%3d] %s  %r" % (tag, m["idx"], m["addr"], m["text"]))


# ---------------------------------------------------------------- tela ARQUIVO
def do_file(e, dump_png=True):
    sizes = [e.u32(FILE_PAGE_SIZE + i * 4) for i in range(FILE_N_PAGES)]
    flags = list(e.bytes_at(FILE_PAGE_FLAG, FILE_N_PAGES))
    starts = [e.u16(FILE_DOC_START + i * 2) for i in range(FILE_N_DOCS)]
    lasts = [e.u16(FILE_DOC_LAST + i * 2) for i in range(FILE_N_DOCS)]
    pix = os.path.join(ETC, "FILEGU.PIX")
    raw = open(pix, "rb").read()
    assert sum(sizes) == len(raw), "soma dos tamanhos != tamanho de FILEGU.PIX"
    offs = []
    o = 0
    for s in sizes:
        offs.append(o)
        o += s
    pages = []
    for i, s in enumerate(sizes):
        t = read_tim(raw, offs[i])
        px, py, pw, ph = t["pix_rect"]
        pages.append({"page": i + 1, "offset": offs[i], "size": s,
                      "bpp": [4, 8, 16][t["bpp"]],
                      "w": pw * (4 if t["bpp"] == 0 else 2), "h": ph,
                      "clut_rect": t["clut_rect"], "req_flag": flags[i]})
    docs = []
    for i in range(FILE_N_DOCS):
        docs.append({"doc": i, "item_id": FILE_ITEM_ID0 + i,
                     "first_page": starts[i], "last_index": lasts[i],
                     "n_pages": lasts[i] + 1,
                     "cover_page": starts[i],
                     "text_pages": list(range(starts[i] + 1, starts[i] + lasts[i] + 1))})
    out = {
        "_fonte": "SLUS_009.23 + ETC/FILEGU.PIX. Ver docs/decomp/notes/menu_texto.md",
        "assets": {"paginas": "ETC/FILEGU.PIX (idx 0x1C)",
                   "icones": "ETC/FILEI.TIM (idx 0x1D)"},
        "tabelas": {"tamanhos_u32": "0x%08X" % FILE_PAGE_SIZE,
                    "flags_u8": "0x%08X" % FILE_PAGE_FLAG,
                    "primeira_pagina_u16": "0x%08X" % FILE_DOC_START,
                    "ultimo_indice_u16": "0x%08X" % FILE_DOC_LAST},
        "n_paginas": FILE_N_PAGES, "n_documentos": FILE_N_DOCS,
        "doc_de_item": "doc = item_id - 0x85 (itens 0x85..0xA3, classe 0x07)",
        "vram": {"capa": {"pagina": 0x17, "x": 448, "y": 256, "clut_y": 490, "tpage": 0x97},
                 "texto": {"pagina": 0x18, "x": 512, "y": 256, "clut_y": 491, "tpage": 0x18}},
        "sprites": {"capa": {"u": 0, "v": 0, "w": 128, "h": 168, "desc": "0x8009F2EC"},
                    "texto": {"u": 0, "v": 0, "w": 256, "h": 176, "desc": "0x8009F2F8"}},
        "carregador": {"pagina_de_texto": "0x800641D0", "documento": "0x800636D4",
                       "upload_capa": "0x8006EBEC", "upload_texto": "0x800784E0"},
        "documentos": docs, "paginas": pages,
    }
    p = os.path.join(DATA_OUT, "re3_file_screen.json")
    json.dump(out, open(p, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("tela de arquivo -> %s" % p)
    if dump_png:
        outdir = os.path.join(ASSET_OUT, "FILE")
        os.makedirs(outdir, exist_ok=True)
        for i, s in enumerate(sizes):
            t = read_tim(raw, offs[i])
            img = tim_to_image(t, clut_row=0)
            kind = "capa" if t["bpp"] == 1 else "pag"
            img.save(os.path.join(outdir, "%s_%03d.png" % (kind, i + 1)))
        ft = read_tim(open(os.path.join(ETC, "FILEI.TIM"), "rb").read())
        tim_to_image(ft, 0).save(os.path.join(outdir, "FILEI.png"))
        print("%d PNG em %s" % (len(sizes) + 1, outdir))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", action="store_true")
    ap.add_argument("--text", action="store_true")
    ap.add_argument("--file", action="store_true")
    ap.add_argument("--dump-msg", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--no-png", action="store_true")
    a = ap.parse_args()
    e = load_exe()
    if a.all or a.font:
        do_font(e)
    if a.all or a.text:
        do_text(e)
    if a.all or a.file:
        do_file(e, dump_png=not a.no_png)
    if a.dump_msg:
        do_dump_msg(e)
    if not any((a.all, a.font, a.text, a.file, a.dump_msg)):
        ap.print_help()


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
