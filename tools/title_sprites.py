#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Recorta os SPRT do menu de TITULO do RE3 (PS1 NTSC-U) da textura de texto.

De onde vem cada coisa:
  * `ETC/TITLEU.DAT` = 3 TIMs concatenados (`python tools/menu_extract.py scan`):
        [0] off 0x00000  320x240 16bpp   -> fundo do titulo (quadro A)
        [1] off 0x25814  320x240 16bpp   -> fundo do titulo (quadro B)
        [2] off 0x4b028  256x256  4bpp   -> ATLAS DE TEXTO (1 CLUT, 16 cores)
    O atlas [2] e o que os SPRT de `TITLE.BIN` endereçam: `clut = 0x7fc0`
    (= VRAM (0,511)) e `tpage = 5` (SetDrawMode em `0x80194a8c`, a3=5).
  * Os retangulos (x, y, u, v, w, h) vem do inicializador de sprites
    `0x801945e4` de `TITLE.BIN` (base 0x80194000): cada bloco chama
    `SetSprt` (EXE `0x8008f6b4`) e depois escreve
    x0@+0x08, y0@+0x0a, u0@+0x0c, v0@+0x0d, clut@+0x0e, w@+0x10, h@+0x12.

Uso:
    PYTHONIOENCODING=utf-8 python tools/title_sprites.py <outdir>
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tim2png import write_png, bgr555   # noqa: E402

DAT = os.path.join("extracted", "ntsc-u", "CD_DATA", "ETC", "TITLEU.DAT")
ATLAS_OFF = 0x4B028

#: (nome, x, y, u, v, w, h) - `x,y` em pixel de tela 320x240; `u,v` no atlas 4bpp de
#: 256x256; `w,h` em pixels. Ordem = ordem de inicializacao em `0x801945e4`.
#: O rotulo depois do `=` foi LIDO da imagem recortada, nao suposto.
#:
#: RAMO A = `*(u32*)0x800cc858 & 0x80` != 0  -> THE MERCENARIES (0x80194684..0x80194890)
RAMO_A = [
    ("copyright",      60,  213, 0,   160, 208, 16),   # 2 linhas de (c)CAPCOM
    ("GAME_START",     133, 140, 0,   144, 54,  12),
    ("RESULT",         143, 158, 64,  144, 34,  12),
    ("GAME_CONFIG",    130, 176, 0,   128, 60,  12),
    ("EXIT",           149, 194, 104, 144, 22,  12),
    ("sh_GAME_START",  134, 141, 0,   144, 54,  12),   # sombra preta (+1,+1)
    ("sh_RESULT",      144, 159, 64,  144, 34,  12),
    ("sh_GAME_CONFIG", 131, 177, 0,   128, 60,  12),
    ("sh_EXIT",        150, 195, 104, 144, 22,  12),
]
#: RAMO B = `*(u32*)0x800cc858 & 0x80` == 0 -> titulo normal (0x80194894..0x80194a7c)
RAMO_B = [
    ("copyright",        60,  213, 0,   160, 208, 16),
    ("NEW_GAME",         68,  193, 0,   104, 48,  12),   # item 0
    ("LOAD_GAME",        132, 193, 64,  104, 50,  12),   # item 1
    ("GAME_CONFIG",      200, 193, 0,   128, 60,  12),   # item 2
    ("PRESS_ANY_BUTTON", 76,  156, 0,   0,   168, 12),
    ("sub_GAME_CONFIG",  80,  193, 0,   128, 60,  12),   # submenu de GAME CONFIG
    ("sub_INFORMATION",  180, 193, 64,  128, 62,  12),
    ("diff_HARD_MODE",   80,  193, 56,  176, 56,  12),   # dificuldade, indice 0
    ("diff_EASY_MODE",   180, 193, 0,   176, 54,  12),   # dificuldade, indice 1
]


def read_atlas(path=DAT, off=ATLAS_OFF):
    """Devolve (w, h, indices, clut_rgb) do TIM 4bpp de `off`."""
    b = open(path, "rb").read()
    assert b[off] == 0x10, "nao e TIM"
    flag = b[off + 4]
    bpp = flag & 3
    has_clut = bool(flag & 8)
    assert bpp == 0 and has_clut, "esperava 4bpp com CLUT"
    p = off + 8
    bnum = struct.unpack_from("<I", b, p)[0]
    clut_body = b[p + 4: p + bnum]
    ncol = struct.unpack_from("<H", clut_body, 4)[0]
    clut = [bgr555(struct.unpack_from("<H", clut_body, 8 + 2 * i)[0])
            for i in range(ncol)]
    p += bnum
    struct.unpack_from("<I", b, p)[0]          # bnum da imagem
    ix, iy, iw, ih = struct.unpack_from("<4H", b, p + 4)
    pix = b[p + 12: p + 12 + iw * ih * 2]
    w, h = iw * 4, ih                          # 4bpp: 1 halfword = 4 texels
    idx = bytearray(w * h)
    for y in range(h):
        row = pix[y * iw * 2:(y + 1) * iw * 2]
        for i, by in enumerate(row):
            idx[y * w + i * 2] = by & 0xF
            idx[y * w + i * 2 + 1] = by >> 4
    return w, h, idx, clut, (ix, iy)


def crop_png(path, w, h, idx, clut, u, v, cw, ch, scale=3):
    """Recorta (u,v,cw,ch) do atlas e grava PNG ampliado `scale` vezes."""
    out = bytearray()
    for y in range(ch * scale):
        sy = v + y // scale
        for x in range(cw * scale):
            sx = u + x // scale
            c = clut[idx[sy * w + sx]] if 0 <= sy < h and 0 <= sx < w else (255, 0, 255)
            out += bytes(c)
    write_png(path, cw * scale, ch * scale, bytes(out))


def bg_tim(off):
    """Le um dos dois TIMs 16bpp de fundo de TITLEU.DAT -> matriz de (r,g,b)."""
    b = open(DAT, "rb").read()
    p = off + 8
    iw, ih = struct.unpack_from("<2H", b, p + 8)
    px = b[p + 12: p + 12 + iw * ih * 2]
    return [[bgr555(struct.unpack_from("<H", px, (y * iw + x) * 2)[0])
             for x in range(iw)] for y in range(ih)]


def mock(outdir, bg_off, sprs, name):
    """Compoe o fundo + os SPRT (indice 0 do atlas = transparente) -> PNG 320x240."""
    w, h, idx, clut, _ = read_atlas()
    fb = bg_tim(bg_off)
    for (_nm, x0, y0, u, v, sw, sh) in sprs:
        for y in range(sh):
            for x in range(sw):
                c = idx[(v + y) * w + (u + x)]
                if c == 0:
                    continue
                if 0 <= y0 + y < len(fb) and 0 <= x0 + x < len(fb[0]):
                    fb[y0 + y][x0 + x] = clut[c]
    out = bytearray()
    for row in fb:
        for c in row:
            out += bytes(c)
    write_png(os.path.join(outdir, name), len(fb[0]), len(fb), bytes(out))
    print("->", name)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "docs/decomp/assets/boot"
    os.makedirs(outdir, exist_ok=True)
    w, h, idx, clut, vram = read_atlas()
    print("atlas 4bpp %dx%d  vram TIM=(%d,%d)  clut=%s" % (w, h, vram[0], vram[1], clut))
    full = bytearray()
    for y in range(h):
        for x in range(w):
            full += bytes(clut[idx[y * w + x]])
    write_png(os.path.join(outdir, "TITLEU_atlas.png"), w, h, bytes(full))
    print("-> TITLEU_atlas.png")
    # recorte de cada rotulo (4x) para leitura
    for nm, _x, _y, u, v, cw, ch in RAMO_A:
        crop_png(os.path.join(outdir, "merc_%s.png" % nm), w, h, idx, clut, u, v, cw, ch, 4)
    for nm, _x, _y, u, v, cw, ch in RAMO_B:
        crop_png(os.path.join(outdir, "titulo_%s.png" % nm), w, h, idx, clut, u, v, cw, ch, 4)
    # telas montadas: TIM[0] = titulo normal, TIM[1] = Mercenaries
    mock(outdir, 0x00000, [s for s in RAMO_B if not s[0].startswith(("sub_", "diff_"))],
         "TITLE_normal_mock.png")
    mock(outdir, 0x25814, RAMO_A, "TITLE_bit80_mock.png")
    mock(outdir, 0x00000, [s for s in RAMO_B if s[0].startswith("diff_")]
         + [RAMO_B[0]], "TITLE_dificuldade_mock.png")


if __name__ == "__main__":
    main()
