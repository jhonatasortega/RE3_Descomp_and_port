#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""map_screen.py - Decodifica COMPLETAMENTE o arquivo da TELA DE MAPA do RE3 PS1
(`CD_DATA/ETC/MAP_U.MAP` / `MAP_J.MAP`) e as tabelas do EXE que o acompanham.

FORMATO PROVADO (ver docs/decomp/notes/menu_mapa.md)
===================================================
O arquivo NAO tem cabecalho global. Ele e a concatenacao de 9 PAGINAS, cujos
tamanhos vem de uma tabela NO EXE (`0x800a03ac`, u32[9]); a soma bate exatamente
com os 634880 bytes do arquivo. O carregador (`0x800713dc`) le UMA pagina por vez
direto do CD, somando os tamanhos das paginas anteriores para achar o setor.

    pagina p  ->  offset  sum(SIZES[0:p])   tamanho SIZES[p]
    SIZES = [0x12000,0x12800,0xa000,0x12000,0x12000,0x12000,0x12000,0x12000,0x12800]

Cada pagina comeca com uma tabela de secoes:

    +0x00  u32               n = 4  (sempre)
    +0x04  {u32 off; u32 size} x n      offsets RELATIVOS ao inicio da pagina
                                        (contiguos: off[k]+size[k] == off[k+1])
    sec[0] = "grupos" (geometria dos comodos) - ver abaixo
    sec[1] = ancoras/scroll/ligacoes        - ver abaixo
    sec[2] = TIM 4bpp 512x256 (ou 256x256 na Clock Tower) com 16 CLUTs: O DESENHO
    sec[3] = TIM 4bpp 256x40 com 1 CLUT: a TIRA DE ROTULOS (nome da area, "1F"...)

sec[0] - geometria:
    +0x00  u32 n_grupos
    +0x04  {u32 off; u16 n1; u16 n2} x n_grupos     off relativo ao inicio de sec[0]
    ...    arrays de REGISTROS DE 12 BYTES em off, primeiro n1 (lista A = comodo),
           depois n2 (lista B = porta/marca).
    registro de 12 bytes:
        +0x00 u8 u0     +0x01 u8 v0     +0x02 u8 u1    +0x03 u8 v1   (UV no TIM, incl.)
        +0x04 s16 x     +0x06 s16 y                      (posicao em px de mapa)
        +0x08 u8 clut_row   (linha de CLUT 0..7; ==7 desliga o realce)
        +0x09 u8 misc       (bit0 -> +8 na linha de CLUT; >>1 -> +N na texpage X)
        +0x0a u16 ?         (NAO LIDO por 0x8007116c - papel nao provado)
    largura = u1-u0+1, altura = v1-v0+1  (o emissor usa u1+1/v1+1 no vertice oposto)

sec[1] - tabela de 8 u32 (offsets relativos a sec[1]; entradas nao usadas = 0):
    sub[0] = {s16 px_x, s16 px_y, s16 w_x, s16 w_z} x n_grupos, terminador ffffffff x2
             ANCORA por grupo: converte mundo->pixel de mapa (divisor 450).
    sub[1] = {s16 scroll_x, s16 scroll_y, u8 tem_marcador, u8 n_andares, u32 0}
    sub[2] = {u8 a, u8 b, u16 c} x N, terminador ff ff ff 00  (pares que compartilham c)
    sub[3], sub[4] = normalmente vazios (so o terminador)

Uso:
    python tools/map_screen.py                 # relatorio no terminal
    python tools/map_screen.py --json ARQ      # despeja tudo em JSON
    python tools/map_screen.py --png PASTA     # paginas (16 CLUTs) + tiras de rotulo
"""
import os
import sys
import json
import struct
import argparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPFILE = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "ETC", "MAP_U.MAP")
EXE = os.path.join(ROOT, "extracted", "ntsc-u", "SLUS_009.23")

# Tabela de tamanhos de pagina: EXE 0x800a03ac (u32[9]). Ver nota.
SIZES = [0x12000, 0x12800, 0xa000, 0x12000, 0x12000, 0x12000, 0x12000, 0x12000, 0x12800]
# Rotulos: strings codificadas do EXE em 0x800a0328, indice u16 em 0x800a038c.
AREAS = ["UPTOWN", "DOWNTOWN", "CLOCK TOWER", "PARK", "DEAD FACTORY",
         "POLICE STATION", "HOSPITAL", "UPTOWN(2)", "DOWNTOWN(2)"]


def u8(b, o):
    return b[o]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def page_offsets():
    off, out = 0, []
    for s in SIZES:
        out.append(off)
        off += s
    return out


def parse_tim_header(b, o):
    """Devolve (bpp, clut_rect, img_rect, off_pix, n_cluts, cluts) de um TIM."""
    assert u32(b, o) == 0x10, "sem magic TIM em %#x" % o
    flag = u32(b, o + 4)
    bpp = flag & 3
    pos = o + 8
    cluts, crect = [], None
    if (flag >> 3) & 1:
        blen = u32(b, pos)
        crect = (u16(b, pos + 4), u16(b, pos + 6), u16(b, pos + 8), u16(b, pos + 10))
        p = pos + 12
        for pal in range(crect[3]):
            cluts.append([u16(b, p + 2 * (pal * crect[2] + i)) for i in range(crect[2])])
        pos += blen
    plen = u32(b, pos)
    irect = (u16(b, pos + 4), u16(b, pos + 6), u16(b, pos + 8), u16(b, pos + 10))
    return bpp, crect, irect, pos + 12, len(cluts), cluts


def bgr555(v):
    r = (v & 0x1F) << 3
    g = ((v >> 5) & 0x1F) << 3
    b = ((v >> 10) & 0x1F) << 3
    return (r | r >> 5, g | g >> 5, b | b >> 5, 0 if v == 0 else 255)


def tim_to_image(b, o, palette=0):
    from PIL import Image
    bpp, crect, irect, po, n, cluts = parse_tim_header(b, o)
    assert bpp == 0, "esperava 4bpp, achei bpp=%d" % bpp
    w = irect[2] * 4
    h = irect[3]
    clut = cluts[palette] if cluts else [0] * 16
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        row = b[po + y * irect[2] * 2: po + (y + 1) * irect[2] * 2]
        for x in range(w):
            byte = row[x >> 1]
            idx = (byte & 0xF) if (x & 1) == 0 else (byte >> 4)
            px[x, y] = bgr555(clut[idx])
    return img


def parse_page(b, base):
    n = u32(b, base)
    secs = [struct.unpack_from("<II", b, base + 4 + 8 * k) for k in range(n)]
    out = {"n_sec": n, "secs": [{"off": a, "size": s} for a, s in secs]}

    # --- sec[0]: grupos ---------------------------------------------------
    s0 = base + secs[0][0]
    ng = u32(b, s0)
    groups = []
    for g in range(ng):
        goff, n1, n2 = struct.unpack_from("<IHH", b, s0 + 4 + 8 * g)
        recs = []
        for i in range(n1 + n2):
            r = s0 + goff + 12 * i
            recs.append({
                "lista": "A" if i < n1 else "B",
                "u0": u8(b, r), "v0": u8(b, r + 1), "u1": u8(b, r + 2), "v1": u8(b, r + 3),
                "x": s16(b, r + 4), "y": s16(b, r + 6),
                "clut_row": u8(b, r + 8), "misc": u8(b, r + 9),
                "extra": u16(b, r + 10),
            })
        groups.append({"off": goff, "n1": n1, "n2": n2, "recs": recs})
    out["n_grupos"] = ng
    out["grupos"] = groups
    esperado = 4 + 8 * ng + 12 * sum(g["n1"] + g["n2"] for g in groups)
    out["sec0_fecha"] = (esperado == secs[0][1])

    # --- sec[1]: ancoras --------------------------------------------------
    s1 = base + secs[1][0]
    subs = [u32(b, s1 + 4 * k) for k in range(8)]
    anchors = []
    p = s1 + subs[0]
    while u32(b, p) != 0xFFFFFFFF:
        anchors.append({"px_x": s16(b, p), "px_y": s16(b, p + 2),
                        "w_x": s16(b, p + 4), "w_z": s16(b, p + 6)})
        p += 8
    q = s1 + subs[1]
    out["sub_offs"] = subs
    out["ancoras"] = anchors
    out["scroll"] = {"x": s16(b, q), "y": s16(b, q + 2),
                     "tem_marcador": u8(b, q + 4), "n_andares": u8(b, q + 5)}
    links = []
    if subs[2]:
        p = s1 + subs[2]
        while not (u8(b, p) == 0xFF and u8(b, p + 1) == 0xFF):
            links.append({"a": u8(b, p), "b": u8(b, p + 1), "c": u16(b, p + 2)})
            p += 4
    out["ligacoes"] = links
    for k in (3, 4):
        if subs[k]:
            p = s1 + subs[k]
            extra = []
            while not (u8(b, p) == 0xFF and u8(b, p + 1) == 0xFF):
                extra.append([u8(b, p + i) for i in range(4)])
                p += 4
            out["sub%d" % k] = extra

    # --- sec[2]/sec[3]: TIMs ---------------------------------------------
    for k, nome in ((2, "tim_mapa"), (3, "tim_rotulo")):
        o = base + secs[k][0]
        bpp, crect, irect, po, ncl, _ = parse_tim_header(b, o)
        out[nome] = {"off": secs[k][0], "bpp": [4, 8, 16, 24][bpp],
                     "clut_rect": crect, "img_rect": irect,
                     "px": (irect[2] * 4, irect[3]), "n_cluts": ncl}
    return out


# --------------------------------------------------------------------------
# Tabelas do EXE que acompanham a tela de mapa (enderecos provados na nota)
# --------------------------------------------------------------------------
T_SIZES = 0x800A03AC   # u32[9]  tamanho de cada pagina do MAP_x.MAP
T_FLAGS = 0x800A03A0   # u8[9]   byte de "flags" do pedido de CD por pagina
T_LABEL_BLOB = 0x800A0328   # texto codificado (0xfe = fim)
T_LABEL_IDX = 0x800A038C    # u16[10] offsets dentro do blob
T_ARROWS = 0x800A03D0  # 2 estados x 4 setas x {u16 u0,v0,u1,v1; s16 x,y}
T_REMAP = 0x800A0430   # {u8 stage,u8 room,u8 page,u8 group} ... 0xff


def exe_tables(exe_path=EXE):
    """Le as tabelas do SLUS_009.23 usadas pela tela de mapa."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from exe_parse import Exe
    e = Exe(exe_path)
    out = {}
    out["tamanhos_pagina"] = [e.u32(T_SIZES + 4 * i) for i in range(9)]
    out["flags_pedido_cd"] = [e.u8(T_FLAGS + i) for i in range(9)]
    # rotulos: charset do mod PT-BR nao esta garantido aqui, entao devolve bytes
    idx = [e.u16(T_LABEL_IDX + 2 * i) for i in range(10)]
    rot = []
    for o in idx:
        p, s = T_LABEL_BLOB + o, []
        while e.u8(p) != 0xFE:
            s.append(e.u8(p))
            p += 1
        rot.append(s)
    out["rotulos_bytes"] = rot
    setas = []
    for st in range(2):
        for i in range(4):
            b = T_ARROWS + st * 48 + i * 12
            setas.append({"estado": st, "seta": i,
                          "u0": e.u16(b), "v0": e.u16(b + 2),
                          "u1": e.u16(b + 4), "v1": e.u16(b + 6),
                          "cx": e.u16(b + 8), "cy": e.u16(b + 10)})
    out["setas"] = setas
    rem, i = [], 0
    while e.u8(T_REMAP + i * 4) != 0xFF:
        b = T_REMAP + i * 4
        rem.append({"stage": e.u8(b), "room": e.u8(b + 1),
                    "page": e.u8(b + 2), "group": e.u8(b + 3)})
        i += 1
    out["remap_sala"] = rem
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=MAPFILE)
    ap.add_argument("--json")
    ap.add_argument("--png")
    a = ap.parse_args()
    b = open(a.file, "rb").read()
    assert len(b) == sum(SIZES), "tamanho inesperado: %d" % len(b)
    offs = page_offsets()
    pages = []
    for p, o in enumerate(offs):
        d = parse_page(b, o)
        d["idx"] = p
        d["base"] = o
        d["area"] = AREAS[p]
        pages.append(d)
        print("== pagina %d  %-14s base=%#08x  grupos=%d fecha=%s  mapa=%s cluts=%d  rotulo=%s"
              % (p, d["area"], o, d["n_grupos"], d["sec0_fecha"], d["tim_mapa"]["px"],
                 d["tim_mapa"]["n_cluts"], d["tim_rotulo"]["img_rect"]))
        print("   ancoras=%d  scroll=%s  ligacoes=%d  recs=%d"
              % (len(d["ancoras"]), d["scroll"], len(d["ligacoes"]),
                 sum(g["n1"] + g["n2"] for g in d["grupos"])))
    if a.json:
        doc = {"fonte": os.path.relpath(a.file, ROOT).replace("\\", "/"),
               "exe": exe_tables(), "paginas": pages}
        json.dump(doc, open(a.json, "w"), indent=1)
        print("-> %s" % a.json)
    if a.png:
        os.makedirs(a.png, exist_ok=True)
        for p, o in enumerate(offs):
            d = pages[p]
            for c in range(d["tim_mapa"]["n_cluts"]):
                im = tim_to_image(b, o + d["secs"][2]["off"], c)
                im.save(os.path.join(a.png, "page%d_clut%02d.png" % (p, c)))
            tim_to_image(b, o + d["secs"][3]["off"], 0).save(
                os.path.join(a.png, "page%d_rotulo.png" % p))
        print("-> %s" % a.png)


if __name__ == "__main__":
    main()
