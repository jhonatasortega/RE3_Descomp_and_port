#!/usr/bin/env python3
"""Decodifica MAP_x.MAP (telas de mapa do menu do RE3, PS1) para PNG.

O arquivo e uma sequencia de blocos TIM (formato PS1) concatenados:
- paginas grandes 4bpp (512x256 ou 256x256) com 16 CLUTs -> o desenho da planta
- tiras 256x40 4bpp com 1 CLUT   -> o rotulo (nome da area, EN/JP)

Uso:
    python map_decode.py <arquivo.MAP> <pasta_saida> [--all-cluts]
"""
import sys, os, struct
from PIL import Image


def u16(b, o): return b[o] | (b[o + 1] << 8)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


def bgr555(v, transparent0=True):
    r = (v & 0x1F) << 3
    g = ((v >> 5) & 0x1F) << 3
    b = ((v >> 10) & 0x1F) << 3
    stp = (v >> 15) & 1
    r |= r >> 5; g |= g >> 5; b |= b >> 5
    # RE/TIM: valor 0x0000 = transparente
    a = 0 if (transparent0 and v == 0) else 255
    return (r, g, b, a)


def find_tims(data):
    offs = []
    i = 0
    n = len(data)
    while i < n - 12:
        if data[i] == 0x10 and u32(data, i) == 0x10 and u32(data, i + 4) in (0, 1, 2, 3, 8, 9, 10, 11):
            # valida parseando os blocos
            try:
                flag = u32(data, i + 4)
                pos = i + 8
                if (flag >> 3) & 1:
                    blen = u32(data, pos)
                    if blen < 12 or pos + blen > n: raise ValueError
                    pos += blen
                plen = u32(data, pos)
                if plen < 12 or pos + plen > n: raise ValueError
                offs.append(i)
                i = pos + plen
                continue
            except Exception:
                pass
        i += 4
    return offs


def decode_tim(data, o, palette=0):
    flag = u32(data, o + 4)
    bpp = flag & 3
    has_clut = (flag >> 3) & 1
    pos = o + 8
    cluts = []
    cx = cy = cw = ch = 0
    if has_clut:
        blen = u32(data, pos)
        cx = u16(data, pos + 4); cy = u16(data, pos + 6)
        cw = u16(data, pos + 8); ch = u16(data, pos + 10)
        p = pos + 12
        for pal in range(ch):
            row = [bgr555(u16(data, p + 2 * (pal * cw + i))) for i in range(cw)]
            cluts.append(row)
        pos += blen
    plen = u32(data, pos)
    ix = u16(data, pos + 4); iy = u16(data, pos + 6)
    iw = u16(data, pos + 8); ih = u16(data, pos + 10)
    pix = data[pos + 12: pos + plen]
    clut = cluts[palette] if cluts and palette < len(cluts) else None

    if bpp == 0:
        w = iw * 4
        img = Image.new("RGBA", (w, ih))
        px = img.load()
        for y in range(ih):
            for x in range(w):
                i = y * w + x
                byte = pix[i >> 1]
                idx = (byte & 0x0F) if (i & 1) == 0 else (byte >> 4)
                px[x, y] = clut[idx] if clut and idx < len(clut) else (0, 0, 0, 255)
    elif bpp == 1:
        w = iw * 2
        img = Image.new("RGBA", (w, ih))
        px = img.load()
        for y in range(ih):
            for x in range(w):
                idx = pix[y * w + x]
                px[x, y] = clut[idx] if clut and idx < len(clut) else (0, 0, 0, 255)
    elif bpp == 2:
        w = iw
        img = Image.new("RGBA", (w, ih))
        px = img.load()
        for y in range(ih):
            for x in range(w):
                px[x, y] = bgr555(u16(pix, 2 * (y * w + x)))
    else:
        raise ValueError("bpp %d" % bpp)
    meta = dict(off=o, bpp=bpp, ncluts=ch, cw=cw, ix=ix, iy=iy, iw=iw, ih=ih, w=img.width, h=ih, cx=cx, cy=cy)
    return img, meta


def main():
    src = sys.argv[1]
    outdir = sys.argv[2]
    all_cluts = "--all-cluts" in sys.argv
    os.makedirs(outdir, exist_ok=True)
    data = open(src, "rb").read()
    offs = find_tims(data)
    print("blocos TIM:", len(offs))
    base = os.path.splitext(os.path.basename(src))[0]
    for k, o in enumerate(offs):
        img, m = decode_tim(data, o, 0)
        name = "%s_%02d_%08x_%dx%d_c%d.png" % (base, k, o, m["w"], m["h"], m["ncluts"])
        img.save(os.path.join(outdir, name))
        print("  [%2d] off=%08x %dx%d bpp=%d cluts=%d vram(ix=%d,iy=%d,cx=%d,cy=%d) -> %s"
              % (k, o, m["w"], m["h"], m["bpp"], m["ncluts"], m["ix"], m["iy"], m["cx"], m["cy"], name))
        if all_cluts and m["ncluts"] > 1:
            for pal in range(m["ncluts"]):
                im2, _ = decode_tim(data, o, pal)
                im2.save(os.path.join(outdir, "%s_%02d_pal%02d.png" % (base, k, pal)))


if __name__ == "__main__":
    main()
