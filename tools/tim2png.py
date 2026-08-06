#!/usr/bin/env python3
"""Decodifica imagens TIM (formato padrao do PlayStation) para PNG.

Python puro — usa apenas a stdlib (zlib para o PNG). Suporta 4bpp e 8bpp
(com CLUT) e 16bpp (cor direta). Alpha sempre opaco (bom para visualizar
backgrounds/telas; tratamento de transparencia fica para depois).

Uso:
    python tim2png.py <pasta_saida> <arquivo1.TIM> [arquivo2.TIM ...]
"""
import sys
import os
import zlib
import struct


def u16(b, o):
    return b[o] | (b[o + 1] << 8)


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def bgr555(v):
    r = (v & 0x1F) << 3
    g = ((v >> 5) & 0x1F) << 3
    b = ((v >> 10) & 0x1F) << 3
    # replica os bits altos nos baixos p/ usar toda a faixa 0..255
    return (r | r >> 5, g | g >> 5, b | b >> 5)


def write_png(path, w, h, rgb):
    """rgb: bytes RGB (3 por pixel), tamanho w*h*3."""
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)  # 8-bit, color type 2 (RGB)
    raw = bytearray()
    row = w * 3
    for y in range(h):
        raw.append(0)                 # filtro "none"
        raw += rgb[y * row:(y + 1) * row]
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def decode_tim(data):
    if data[0] != 0x10:
        raise ValueError("nao e TIM (byte 0 != 0x10)")
    flag = data[4]
    bpp = flag & 3          # 0=4bpp, 1=8bpp, 2=16bpp, 3=24bpp
    has_clut = (flag >> 3) & 1
    pos = 8
    clut = None
    if has_clut:
        blen = u32(data, pos)
        cw = u16(data, pos + 8)     # cores por paleta
        ch = u16(data, pos + 10)    # numero de paletas
        p = pos + 12
        clut = [bgr555(u16(data, p + 2 * i)) for i in range(cw)]  # usa paleta 0
        pos += blen

    blen = u32(data, pos)
    iw = u16(data, pos + 8)         # largura em unidades de 16 bits
    ih = u16(data, pos + 10)
    pix = data[pos + 12: pos + blen]

    if bpp == 0:       # 4bpp
        w = iw * 4
        out = bytearray(w * ih * 3)
        for i in range(w * ih):
            byte = pix[i >> 1]
            idx = (byte & 0x0F) if (i & 1) == 0 else (byte >> 4)
            r, g, b = clut[idx] if idx < len(clut) else (0, 0, 0)
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
        return w, ih, bytes(out)

    if bpp == 1:       # 8bpp
        w = iw * 2
        out = bytearray(w * ih * 3)
        for i in range(w * ih):
            idx = pix[i]
            r, g, b = clut[idx] if idx < len(clut) else (0, 0, 0)
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
        return w, ih, bytes(out)

    if bpp == 2:       # 16bpp cor direta
        w = iw
        out = bytearray(w * ih * 3)
        for i in range(w * ih):
            r, g, b = bgr555(u16(pix, 2 * i))
            out[i * 3:i * 3 + 3] = bytes((r, g, b))
        return w, ih, bytes(out)

    raise ValueError(f"bpp={bpp} (24bpp) ainda nao suportado")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    for path in sys.argv[2:]:
        try:
            data = open(path, "rb").read()
            w, h, rgb = decode_tim(data)
            name = os.path.splitext(os.path.basename(path))[0] + ".png"
            dest = os.path.join(outdir, name)
            write_png(dest, w, h, rgb)
            print(f"OK  {os.path.basename(path):<16} -> {name}  ({w}x{h})")
        except Exception as e:
            print(f"ERRO {os.path.basename(path):<16}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
