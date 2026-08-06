#!/usr/bin/env python3
"""Extrai os ICONES DE ITEM do RE3 (ETC/ITEMG.PIX) para PNG com alpha.

Achado (2026-08-05): `ETC/ITEMG.PIX` nao e' um atlas unico -- e' um ARRAY de TIMs de tamanho
FIXO, um por icone, com passo de **10240 bytes** (0x2800):

    +0x0000  u32 0x10          magic TIM
    +0x0004  u32 0x09          flags: 8bpp (bits 0-1 = 1) + tem CLUT (bit 3)
    +0x0008  u32 clut_len=524  header 12 B + 256 cores de 16 bits
             u16 cx=0, cy=480  posicao da CLUT na VRAM  (a MESMA linha da CLUT de mascara)
             u16 cw=256, ch=1
    +0x0214  u32 img_len=8076  header 12 B + pixels
             u16 ix, iy        posicao na VRAM
             u16 iw=56, ih=72  56 halfwords = **112 px** de largura, 72 de altura
    resto    padding 0x00 ate 10240

134 icones no arquivo (1372160 / 10240). **O indice do array E' o item_id** -- validado por
inspecao visual em 11 itens de faixas diferentes (0x01 faca, 0x03 pistola M92F, 0x04 escopeta,
0x05 magnum, 0x0a lanca-granadas, 0x14 lanca-minas, 0x21 erva verde, 0x33 cabo de forca,
0x41 oleo de isqueiro, 0x60 cartao Umbrella, 0x80 chave da boutique). O indice 0 nao e' item
(e' a SIGPRO verde). O de-para sai em `item_icons.json.por_item_id`.

Cor 0 da paleta = TRANSPARENTE (padrao do PS1 com STP; validado: o fundo dos icones e' o
indice 0 em 134/134).

Uso:
    python tools/item_icons.py              # extrai PNGs para {OUT}/assets/ETC/items/
    python tools/item_icons.py --montagem    # + folha de contato para inspecao
"""
import os
import sys
import json
import struct
import paths

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "ETC", "ITEMG.PIX")
PASSO = 10240                      # tamanho fixo de cada slot de icone
OUT_REL = os.path.join("ETC", "items")


def decode_tim(buf):
    """TIM 8bpp com CLUT -> (largura, altura, lista RGBA). Cor 0 = transparente."""
    magic, flags = struct.unpack_from("<II", buf, 0)
    if magic != 0x10 or (flags & 3) != 1 or not (flags & 8):
        return None
    o = 8
    clut_len, _cx, _cy, cw, ch = struct.unpack_from("<I4H", buf, o)
    pal = []
    for i in range(cw):
        v = struct.unpack_from("<H", buf, o + 12 + i * 2)[0]
        r = (v & 31) * 255 // 31
        g = ((v >> 5) & 31) * 255 // 31
        b = ((v >> 10) & 31) * 255 // 31
        pal.append((r, g, b, 0 if i == 0 else 255))
    o += clut_len
    img_len, _ix, _iy, iw, ih = struct.unpack_from("<I4H", buf, o)
    px = buf[o + 12:o + img_len]
    w = iw * 2                     # 8bpp: cada halfword da VRAM guarda 2 pixels
    dados = [pal[px[k]] if k < len(px) else (0, 0, 0, 0) for k in range(w * ih)]
    return w, ih, dados


def png_bytes(w, h, rgba):
    """PNG RGBA sem dependencia externa (zlib da stdlib)."""
    import zlib
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(rgba[y * w + x])
    def chunk(tipo, data):
        c = struct.pack(">I", len(data)) + tipo + data
        return c + struct.pack(">I", zlib.crc32(tipo + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def main(argv):
    if not os.path.exists(SRC):
        print("ITEMG.PIX nao encontrado em %s" % SRC)
        return 1
    d = open(SRC, "rb").read()
    n = len(d) // PASSO
    dest = os.path.join(paths.assets(), OUT_REL)
    os.makedirs(dest, exist_ok=True)
    ok = 0
    tamanhos = set()
    icones = []
    for i in range(n):
        t = decode_tim(d[i * PASSO:(i + 1) * PASSO])
        if t is None:
            continue
        w, h, rgba = t
        tamanhos.add((w, h))
        open(os.path.join(dest, "%03d.png" % i), "wb").write(png_bytes(w, h, rgba))
        opacos = sum(1 for p in rgba if p[3])
        icones.append({"indice": i, "w": w, "h": h, "px_opacos": opacos})
        ok += 1
    # DE-PARA PROVADO POR INSPECAO VISUAL: **indice = item_id**. Conferido em 11 itens de
    # faixas diferentes: 0x01 faca, 0x03 pistola M92F, 0x04 escopeta, 0x05 magnum,
    # 0x0a lanca-granadas, 0x14 lanca-minas melhorado, 0x21 erva verde, 0x33 cabo de forca,
    # 0x41 oleo de isqueiro, 0x60 cartao Umbrella, 0x80 chave da boutique -- todos batem.
    # (O indice 0 nao e' item: e' a SIGPRO verde, variante que o jogo usa em outro contexto.)
    itens_path = os.path.join(paths.data(), "re3_items.json")
    mapa = {}
    if os.path.exists(itens_path):
        db = json.load(open(itens_path, encoding="utf-8"))
        for k in db.get("by_id", {}):
            idx = int(k, 16)
            if 0 <= idx < ok:
                mapa[k] = idx
    json.dump({
        "_meta": {
            "fonte": "extracted/ntsc-u/CD_DATA/ETC/ITEMG.PIX",
            "formato": "array de TIM 8bpp+CLUT, passo fixo 10240 B, 112x72 px, cor 0 = alpha",
            "n_icones": ok,
            "de_para": ("indice = item_id (validado visualmente em 11 itens de faixas "
                        "diferentes: 0x01/0x03/0x04/0x05/0x0a/0x14/0x21/0x33/0x41/0x60/0x80). "
                        "O indice 0 nao corresponde a item."),
        },
        "icones": icones,
        "por_item_id": mapa,
    }, open(os.path.join(paths.data(), "item_icons.json"), "w", encoding="utf-8"),
        ensure_ascii=False, indent=1)
    print("%d icones -> %s (tamanhos: %s)" % (ok, dest, sorted(tamanhos)))
    if "--montagem" in argv:
        cols = 12
        rows = (ok + cols - 1) // cols
        W, H = 112, 72
        folha = [(20, 20, 25, 255)] * (cols * W * rows * H)
        for i in range(ok):
            t = decode_tim(d[i * PASSO:(i + 1) * PASSO])
            if t is None:
                continue
            w, h, rgba = t
            bx, by = (i % cols) * W, (i // cols) * H
            for y in range(h):
                for x in range(w):
                    p = rgba[y * w + x]
                    if p[3]:
                        folha[(by + y) * cols * W + bx + x] = p
        out = os.path.join(paths.assets(), OUT_REL, "_folha.png")
        open(out, "wb").write(png_bytes(cols * W, rows * H, folha))
        print("folha de contato -> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
