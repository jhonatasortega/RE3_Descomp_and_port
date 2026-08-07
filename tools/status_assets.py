#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Assets da TELA DE STATUS/INVENTARIO do RE3 PS1 NTSC-U.

A geometria da tela esta em `tools/status_layout.py` + `docs/decomp/notes/menu_inventario.md`.
Aqui saem as IMAGENS que ela desenha, com a PALETA certa (o pulo do gato: cada peca da tela usa
uma linha de CLUT diferente do mesmo TIM, e escolher a linha errada da uma tela com as cores
trocadas).

  ETC/STMAIN0U.TIM  8bpp, imagem 256x272, **4 CLUTs** (DX=0 DY=480 w=256 h=4)
                    -> moldura, grade, retratos. Paleta 2 = retratos JILL/CARLOS.
  ETC/STMOJIU.TIM   4bpp, imagem 256x72, **9 CLUTs** (DX=304 DY=480 w=16 h=9)
                    -> palavras (condition/FINE/CAUTION/...), digitos, rotulos de comando.
  ETC/ITEMA.SLD     134 icones de item 40x30 8bpp COMPRIMIDOS; o indice por item_id esta no
                    EXE em `0x8009f678` (u32 por item). A paleta e a **CLUT (0,485)**, que e a
                    linha 1 do STMAIN0U depois do upload (`tag 0x041a` -> CLUT y = 4 + 480).

DESCOMPRESSOR (`0x80010000`, LZ77 simples; disasm em menu_inventario.md secao 15.4):

    u32 n = *(u32*)src; src += 4;              // numero de TOKENS
    while (n--) {
        s8 b = *src++;
        if (b < 0) { len = b & 0x7f;  copia literal de `len` bytes }
        else       { v = (b << 8) | *src++;
                     dist = v & 0x7ff; len = (v >> 11) + 2;
                     copia `len` bytes de (dst - dist - 4) }
    }

Criterio de aceite (o mesmo da auditoria): **as 134 entradas descomprimem para exatamente
1200 bytes** = 40*30 8bpp. Se alguma nao der 1200, o descompressor esta errado.

Uso:
    python tools/status_assets.py --atlas   # STMAIN0U (4 paletas) + STMOJIU (9 paletas)
    python tools/status_assets.py --icons   # os 134 icones 40x30 do ITEMA.SLD
    python tools/status_assets.py --all
"""
import os
import sys
import zlib
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import paths                                                        # noqa: E402
from exe_parse import Exe                                           # noqa: E402

ETC = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "ETC")
EXE = os.path.join(ROOT, "extracted", "ntsc-u", "SLUS_009.23")
SLD_OFFSETS = 0x8009F678        # u32 por item_id (134 itens; a 135a palavra ja e outra tabela)
N_ITENS = 134
ICONE_W, ICONE_H = 40, 30
CLUT_ICONE = 1                  # CLUT (0,485) = linha 1 do STMAIN0U apos o upload


def bgr555(v):
    r = (v & 0x1F) << 3
    g = ((v >> 5) & 0x1F) << 3
    b = ((v >> 10) & 0x1F) << 3
    a = 0 if v == 0 else 255            # cor 0 = transparente no PS1
    return r, g, b, a


def png_rgba(path, w, h, px):
    """PNG RGBA sem dependencia externa (mesmo esquema dos outros tools do repo)."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += px[y * w * 4:(y + 1) * w * 4]

    def chunk(typ, data):
        c = struct.pack(">I", len(data)) + typ + data
        return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)

    hdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", hdr))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def ler_tim(caminho):
    """TIM 4bpp/8bpp -> (w, h, indices, [paletas]). Cada paleta = lista de (r,g,b,a)."""
    d = open(caminho, "rb").read()
    magic, flag = struct.unpack_from("<II", d, 0)
    assert magic == 0x10, caminho
    bpp = flag & 3                                   # 0 = 4bpp, 1 = 8bpp
    tem_clut = (flag & 8) != 0
    o = 8
    paletas = []
    if tem_clut:
        blen, _dx, _dy, cw, ch = struct.unpack_from("<I4H", d, o)
        base = o + 12
        for linha in range(ch):
            pal = []
            for i in range(cw):
                pal.append(bgr555(struct.unpack_from("<H", d, base + (linha * cw + i) * 2)[0]))
            paletas.append(pal)
        o += blen
    blen, _dx, _dy, ww, hh = struct.unpack_from("<I4H", d, o)
    pix = d[o + 12:o + blen]
    if bpp == 1:                                     # 8bpp: 2 pixels por word de VRAM
        w, h = ww * 2, hh
        idx = list(pix[:w * h])
    else:                                            # 4bpp: 4 pixels por word
        w, h = ww * 4, hh
        idx = []
        for b in pix[:w * h // 2]:
            idx.append(b & 0x0F)
            idx.append(b >> 4)
    return w, h, idx, paletas


def desenhar(w, h, idx, pal):
    px = bytearray(w * h * 4)
    for i, v in enumerate(idx):
        r, g, b, a = pal[v] if v < len(pal) else (0, 0, 0, 0)
        px[i * 4 + 0] = r
        px[i * 4 + 1] = g
        px[i * 4 + 2] = b
        px[i * 4 + 3] = a
    return px


def descomprimir(src, esperado=None):
    """O LZ77 de `0x80010000`. `src` comeca no u32 de contagem de tokens."""
    n = struct.unpack_from("<I", src, 0)[0]
    p = 4
    out = bytearray()
    for _ in range(n):
        b = src[p]
        p += 1
        if b & 0x80:                                  # s8 < 0 => literal
            ln = b & 0x7F
            out += src[p:p + ln]
            p += ln
        else:
            v = (b << 8) | src[p]
            p += 1
            dist = v & 0x7FF
            ln = (v >> 11) + 2
            ini = len(out) - dist - 4
            if ini < 0:
                raise ValueError("referencia antes do inicio (dist=%d)" % dist)
            for k in range(ln):
                out.append(out[ini + k])
        if esperado is not None and len(out) >= esperado:
            break
    return bytes(out)


def cmd_atlas(outdir):
    feitos = []
    for nome in ("STMAIN0U", "STMOJIU"):
        w, h, idx, pals = ler_tim(os.path.join(ETC, nome + ".TIM"))
        for i, pal in enumerate(pals):
            dest = os.path.join(outdir, "%s_p%d.png" % (nome.lower(), i))
            png_rgba(dest, w, h, desenhar(w, h, idx, pal))
            feitos.append(dest)
        print("%s: %dx%d, %d paleta(s)" % (nome, w, h, len(pals)))
    return feitos


def cmd_icons(outdir):
    e = Exe(EXE)
    sld = open(os.path.join(ETC, "ITEMA.SLD"), "rb").read()
    _w, _h, _idx, pals = ler_tim(os.path.join(ETC, "STMAIN0U.TIM"))
    pal = pals[CLUT_ICONE]
    ok = ruins = 0
    for item in range(N_ITENS):
        off = e.u32(SLD_OFFSETS + item * 4)
        if off >= len(sld):
            ruins += 1
            continue
        try:
            bruto = descomprimir(sld[off:], ICONE_W * ICONE_H)
        except Exception as ex:                        # noqa: BLE001
            print("  item %d (off 0x%x): %s" % (item, off, ex))
            ruins += 1
            continue
        if len(bruto) < ICONE_W * ICONE_H:
            print("  item %d: %d bytes (esperado %d)" % (item, len(bruto), ICONE_W * ICONE_H))
            ruins += 1
            continue
        px = desenhar(ICONE_W, ICONE_H, list(bruto[:ICONE_W * ICONE_H]), pal)
        png_rgba(os.path.join(outdir, "itema", "%03d.png" % item), ICONE_W, ICONE_H, px)
        ok += 1
    print("icones ITEMA.SLD: %d ok, %d falharam (criterio: 1200 B cada)" % (ok, ruins))
    return ok, ruins


def main():
    a = sys.argv[1:]
    outdir = paths.assets("MENU", "status")
    if "--out" in a:
        outdir = a[a.index("--out") + 1]
    fez = False
    if "--atlas" in a or "--all" in a:
        cmd_atlas(outdir)
        fez = True
    if "--icons" in a or "--all" in a:
        cmd_icons(outdir)
        fez = True
    if not fez:
        print(__doc__)
        return 1
    print("-> %s" % outdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
