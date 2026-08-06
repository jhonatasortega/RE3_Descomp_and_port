#!/usr/bin/env python3
"""Decodifica backgrounds .BSS do Resident Evil 3 (PS1, NTSC-U) para PNG.

Um arquivo .BSS e um contentor de N backgrounds de 320x240, um por angulo de
camera da sala. Cada background ocupa um "slot" de 64 KiB (0x10000):

    [ frame MDEC comprimido ] [ padding com 0x00 ate 64 KiB ]

O frame e exatamente o formato de quadro de video da PlayStation (STR/MDEC),
versao 3 do bitstream ("BS v3"). Ou seja: compressao DCT estilo MPEG-1 /
JPEG (apenas I-frames), decodificada em duas etapas:

  1. Descompressao VLC (Huffman) do bitstream -> coeficientes DCT (run/level).
  2. Emulacao do chip MDEC: un-zig-zag, dequantizacao, IDCT 8x8, junta os
     6 blocos do macrobloco (Cr, Cb, Y1..Y4) em 4:2:0 e converte YCbCr->RGB.

Cabecalho do slot (8 bytes, little-endian) -- identico ao header de frame
STR "demultiplexado":

    +0 u16  numero de blocos de 32 bits p/ os MDEC codes (tamanho comprimido)
    +2 u16  0x3800  (magic constante do formato STR)
    +4 u16  escala de quantizacao (qscale) do frame
    +6 u16  versao do bitstream (== 3 no RE3)

Referencia do formato: jPSXdec "PlayStation1_STR_format.txt" (m35/jpsxdec) e
psx-spx (nocash). As 111 entradas da tabela VLC de coeficientes AC foram
extraidas dessa referencia (identicas as tabelas de coeficientes DCT do MPEG-1).

Dependencias: apenas a stdlib (Python puro, como tim2png.py). Se `numpy`
estiver disponivel, a IDCT usa numpy e fica ~10x mais rapida; caso contrario
cai para uma implementacao pura equivalente.

Uso:
    python bss2png.py [--out RAIZ] arquivo1.BSS [arquivo2.BSS ...]

Para cada arquivo gera RAIZ/STAGE{n}/<nome>_<idx>.png (um PNG por slot).
Se o caminho de entrada nao contiver .../STAGEn/ os PNGs vao para a raiz.
"""
import sys
import os
import re
import math
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tim2png import write_png  # reutiliza o escritor de PNG (zlib puro)

try:
    import numpy as _np
    HAVE_NUMPY = True
except ImportError:
    HAVE_NUMPY = False

SLOT = 0x10000          # 64 KiB por background
IMG_W, IMG_H = 320, 240
MB_COLS, MB_ROWS = IMG_W // 16, IMG_H // 16   # 20 x 15 = 300 macroblocos
STR_MAGIC = 0x3800

# ---------------------------------------------------------------------------
# Tabela VLC dos coeficientes AC (MPEG-1 / MDEC). Cada entrada:
#   (comprimento_do_prefixo, valor_do_prefixo, run_de_zeros, nivel_absoluto)
# O bit de sinal vem LOGO APOS o prefixo (nao esta incluido aqui).
# Extraida de jPSXdec PlayStation1_STR_format.txt (111 codigos).
# ---------------------------------------------------------------------------
AC_VLC = [(2, 3, 0, 1), (3, 3, 1, 1), (4, 4, 0, 2), (4, 5, 2, 1), (5, 5, 0, 3), (5, 6, 4, 1), (5, 7, 3, 1), (6, 4, 7, 1), (6, 5, 6, 1), (6, 6, 1, 2), (6, 7, 5, 1), (7, 4, 2, 2), (7, 5, 9, 1), (7, 6, 0, 4), (7, 7, 8, 1), (8, 32, 13, 1), (8, 33, 0, 6), (8, 34, 12, 1), (8, 35, 11, 1), (8, 36, 3, 2), (8, 37, 1, 3), (8, 38, 0, 5), (8, 39, 10, 1), (10, 8, 16, 1), (10, 9, 5, 2), (10, 10, 0, 7), (10, 11, 2, 3), (10, 12, 1, 4), (10, 13, 15, 1), (10, 14, 14, 1), (10, 15, 4, 2), (12, 16, 0, 11), (12, 17, 8, 2), (12, 18, 4, 3), (12, 19, 0, 10), (12, 20, 2, 4), (12, 21, 7, 2), (12, 22, 21, 1), (12, 23, 20, 1), (12, 24, 0, 9), (12, 25, 19, 1), (12, 26, 18, 1), (12, 27, 1, 5), (12, 28, 3, 3), (12, 29, 0, 8), (12, 30, 6, 2), (12, 31, 17, 1), (13, 16, 10, 2), (13, 17, 9, 2), (13, 18, 5, 3), (13, 19, 3, 4), (13, 20, 2, 5), (13, 21, 1, 7), (13, 22, 1, 6), (13, 23, 0, 15), (13, 24, 0, 14), (13, 25, 0, 13), (13, 26, 0, 12), (13, 27, 26, 1), (13, 28, 25, 1), (13, 29, 24, 1), (13, 30, 23, 1), (13, 31, 22, 1), (14, 16, 0, 31), (14, 17, 0, 30), (14, 18, 0, 29), (14, 19, 0, 28), (14, 20, 0, 27), (14, 21, 0, 26), (14, 22, 0, 25), (14, 23, 0, 24), (14, 24, 0, 23), (14, 25, 0, 22), (14, 26, 0, 21), (14, 27, 0, 20), (14, 28, 0, 19), (14, 29, 0, 18), (14, 30, 0, 17), (14, 31, 0, 16), (15, 16, 0, 40), (15, 17, 0, 39), (15, 18, 0, 38), (15, 19, 0, 37), (15, 20, 0, 36), (15, 21, 0, 35), (15, 22, 0, 34), (15, 23, 0, 33), (15, 24, 0, 32), (15, 25, 1, 14), (15, 26, 1, 13), (15, 27, 1, 12), (15, 28, 1, 11), (15, 29, 1, 10), (15, 30, 1, 9), (15, 31, 1, 8), (16, 16, 1, 18), (16, 17, 1, 17), (16, 18, 1, 16), (16, 19, 1, 15), (16, 20, 6, 3), (16, 21, 16, 2), (16, 22, 15, 2), (16, 23, 14, 2), (16, 24, 13, 2), (16, 25, 12, 2), (16, 26, 11, 2), (16, 27, 31, 1), (16, 28, 30, 1), (16, 29, 29, 1), (16, 30, 28, 1), (16, 31, 27, 1)]

# Tabelas VLC dos coeficientes DC (v3), diferenciais. (prefixo, nbits_dc)
DC_CHROMA = [("11111110", 8), ("1111110", 7), ("111110", 6), ("11110", 5),
             ("1110", 4), ("110", 3), ("10", 2), ("01", 1), ("00", 0)]
DC_LUMA = [("1111110", 8), ("111110", 7), ("11110", 6), ("1110", 5),
           ("110", 4), ("101", 3), ("01", 2), ("00", 1), ("100", 0)]

# Zig-zag MPEG-1/JPEG: ZZ[linha][coluna] = indice na lista de 64 coeficientes.
ZIGZAG = [
    [0,  1,  5,  6, 14, 15, 27, 28],
    [2,  4,  7, 13, 16, 26, 29, 42],
    [3,  8, 12, 17, 25, 30, 41, 43],
    [9, 11, 18, 24, 31, 40, 44, 53],
    [10, 19, 23, 32, 39, 45, 52, 54],
    [20, 22, 33, 38, 46, 51, 55, 60],
    [21, 34, 37, 47, 50, 56, 59, 61],
    [35, 36, 48, 49, 57, 58, 62, 63],
]
# lista raster dos indices (para o un-zig-zag)
_ZZ_FLAT = [ZIGZAG[r][c] for r in range(8) for c in range(8)]
# posicao (linha, coluna) de cada indice da lista (para o caminho puro/esparso)
_ZZ_POS = [None] * 64
for _r in range(8):
    for _c in range(8):
        _ZZ_POS[ZIGZAG[_r][_c]] = (_r, _c)

# Tabela de quantizacao do PSX (= MPEG-1 intra, mas [0,0]=2 em vez de 8).
QUANT = [
    [2, 16, 19, 22, 26, 27, 29, 34],
    [16, 16, 22, 24, 27, 29, 34, 37],
    [19, 22, 26, 27, 29, 34, 34, 38],
    [22, 22, 26, 27, 29, 34, 37, 40],
    [22, 26, 27, 29, 32, 35, 40, 48],
    [26, 27, 29, 32, 35, 40, 48, 58],
    [26, 27, 29, 34, 38, 46, 56, 69],
    [27, 29, 35, 38, 46, 56, 69, 83],
]


def _idct_matrix():
    """A[k][n] = c(k) * cos((2n+1) k pi / 16), c(0)=sqrt(1/8), senao 0.5."""
    A = [[0.0] * 8 for _ in range(8)]
    for k in range(8):
        ck = math.sqrt(1.0 / 8.0) if k == 0 else math.sqrt(2.0 / 8.0)
        for n in range(8):
            A[k][n] = ck * math.cos((2 * n + 1) * k * math.pi / 16.0)
    return A


IDCT_A = _idct_matrix()

# Tipos de simbolo AC
RL, EOB, ESC, BAD = 0, 1, 2, 3


def _build_ac_lut():
    """LUT indexada pelos proximos 16 bits (alinhados no MSB) -> (nbits_prefixo,
    run, nivel_abs, tipo). O bit de sinal NAO esta incluido no prefixo."""
    lut = [(0, 0, 0, BAD)] * 65536
    for (L, V, run, lvl) in AC_VLC:
        base = V << (16 - L)
        for j in range(1 << (16 - L)):
            lut[base + j] = (L, run, lvl, RL)
    base = 0b10 << 14                       # EOB = "10"
    for j in range(1 << 14):
        lut[base + j] = (2, 0, 0, EOB)
    base = 0b000001 << 10                   # Escape = "000001"
    for j in range(1 << 10):
        lut[base + j] = (6, 0, 0, ESC)
    return lut


AC_LUT = _build_ac_lut()


def _build_dc_lut(table):
    """LUT de 8 bits -> (nbits_prefixo, nbits_dc)."""
    lut = [(0, -1)] * 256
    for (code, dcbits) in table:
        L = len(code)
        V = int(code, 2)
        base = V << (8 - L)
        for j in range(1 << (8 - L)):
            lut[base + j] = (L, dcbits)
    return lut


DC_LUT_CHROMA = _build_dc_lut(DC_CHROMA)
DC_LUT_LUMA = _build_dc_lut(DC_LUMA)


class BitReader:
    """Le o bitstream em palavras de 16 bits little-endian, bits do MSB p/ LSB."""
    __slots__ = ("data", "pos", "n", "buf", "cnt")

    def __init__(self, data, start):
        self.data = data
        self.pos = start
        self.n = len(data)
        self.buf = 0
        self.cnt = 0

    def _fill(self, need):
        while self.cnt < need:
            p = self.pos
            if p + 1 < self.n:
                w = self.data[p] | (self.data[p + 1] << 8)
            elif p < self.n:
                w = self.data[p]
            else:
                w = 0
            self.pos = p + 2
            self.buf = (self.buf << 16) | w
            self.cnt += 16

    def peek(self, nbits):
        if self.cnt < nbits:
            self._fill(nbits)
        return (self.buf >> (self.cnt - nbits)) & ((1 << nbits) - 1)

    def skip(self, nbits):
        self.cnt -= nbits
        self.buf &= (1 << self.cnt) - 1

    def read(self, nbits):
        if nbits == 0:
            return 0
        if self.cnt < nbits:
            self._fill(nbits)
        self.cnt -= nbits
        v = (self.buf >> self.cnt) & ((1 << nbits) - 1)
        self.buf &= (1 << self.cnt) - 1
        return v

    def read_signed(self, nbits):
        v = self.read(nbits)
        if v >= (1 << (nbits - 1)):
            v -= (1 << nbits)
        return v


def _read_dc(br, dc_lut, prev):
    """Decodifica um coeficiente DC diferencial v3. Retorna o DC absoluto."""
    L, dcbits = dc_lut[br.peek(8)]
    br.skip(L)
    if dcbits == 0:
        diff = 0
    else:
        sign = br.read(1)
        mag = br.read(dcbits - 1)
        if sign:
            diff = mag + (1 << (dcbits - 1))
        else:
            diff = mag - ((1 << dcbits) - 1)
    return prev + diff * 4   # *4: v3 tem 8 bits de precisao DC (sobe p/ 10 bits)


def _decode_block(br, dc_lut, prev_dc):
    """Decodifica 1 bloco (DC + ACs + EOB). Retorna (lista_de_64, dc_absoluto)."""
    out = [0] * 64
    dc = _read_dc(br, dc_lut, prev_dc)
    out[0] = dc
    i = 0
    while True:
        L, run, lvl, kind = AC_LUT[br.peek(16)]
        br.skip(L)
        if kind == RL:
            level = -lvl if br.read(1) else lvl
        elif kind == EOB:
            break
        elif kind == ESC:
            run = br.read(6)
            level = br.read_signed(10)
        else:
            raise ValueError("codigo VLC AC invalido (bitstream dessincronizado)")
        i += 1 + run
        if i > 63:
            break
        out[i] = level
    return out, dc


def _decode_coeffs(data, offset):
    """Etapa 1 (VLC). Retorna (qscale, version, blocos) com blocos = lista de
    n_mb*6 listas de 64 coeficientes, na ordem Cr,Cb,Y1,Y2,Y3,Y4 por macrobloco."""
    magic = data[offset + 2] | (data[offset + 3] << 8)
    if magic != STR_MAGIC:
        raise ValueError("magic 0x3800 ausente em offset 0x%X (nao e frame BSS/STR)"
                         % offset)
    qscale = data[offset + 4] | (data[offset + 5] << 8)
    version = data[offset + 6] | (data[offset + 7] << 8)
    br = BitReader(data, offset + 8)
    n_mb = MB_COLS * MB_ROWS
    blocks = []
    prev_cr = prev_cb = prev_lum = 0
    for _mb in range(n_mb):
        b, prev_cr = _decode_block(br, DC_LUT_CHROMA, prev_cr)
        blocks.append(b)
        b, prev_cb = _decode_block(br, DC_LUT_CHROMA, prev_cb)
        blocks.append(b)
        for _y in range(4):
            b, prev_lum = _decode_block(br, DC_LUT_LUMA, prev_lum)
            blocks.append(b)
    return qscale, version, blocks


def _clamp8(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


# --- Etapa 2 (emulacao MDEC): reconstrucao ---------------------------------

def _reconstruct_numpy(blocks, qscale):
    coeffs = _np.array(blocks, dtype=_np.float64)
    F = coeffs[:, _ZZ_FLAT].reshape(-1, 8, 8)
    Q = _np.array(QUANT, dtype=_np.float64)
    S = (2.0 * Q / 16.0) * qscale
    deq = F * S
    deq[:, 0, 0] = F[:, 0, 0] * Q[0, 0]     # DC nao usa qscale
    A = _np.array(IDCT_A, dtype=_np.float64)
    spatial = _np.matmul(_np.matmul(A.T, deq), A).reshape(-1, 6, 8, 8)
    img = _np.empty((IMG_H, IMG_W, 3), dtype=_np.float64)
    n_mb = MB_COLS * MB_ROWS
    for mb in range(n_mb):
        cr, cb = spatial[mb, 0], spatial[mb, 1]
        Y = _np.empty((16, 16), dtype=_np.float64)
        Y[0:8, 0:8] = spatial[mb, 2]
        Y[0:8, 8:16] = spatial[mb, 3]
        Y[8:16, 0:8] = spatial[mb, 4]
        Y[8:16, 8:16] = spatial[mb, 5]
        Y += 128.0
        Cr = _np.repeat(_np.repeat(cr, 2, 0), 2, 1)
        Cb = _np.repeat(_np.repeat(cb, 2, 0), 2, 1)
        x0 = (mb // MB_ROWS) * 16
        y0 = (mb % MB_ROWS) * 16
        img[y0:y0 + 16, x0:x0 + 16, 0] = Y + 1.402 * Cr
        img[y0:y0 + 16, x0:x0 + 16, 1] = Y - 0.3437 * Cb - 0.7143 * Cr
        img[y0:y0 + 16, x0:x0 + 16, 2] = Y + 1.772 * Cb
    _np.clip(img, 0, 255, out=img)
    return img.astype(_np.uint8).tobytes()


def _idct_block_py(coeff, qscale):
    """IDCT esparsa de 1 bloco -> matriz 8x8 (lista de listas). So percorre
    coeficientes nao-nulos: spatial += c * outer(A[lin], A[col])."""
    sp = [[0.0] * 8 for _ in range(8)]
    A = IDCT_A
    for idx in range(64):
        c = coeff[idx]
        if c == 0:
            continue
        r, col = _ZZ_POS[idx]
        if idx == 0:
            val = c * QUANT[0][0]                       # DC
        else:
            val = 2.0 * c * qscale * QUANT[r][col] / 16.0
        Ar = A[r]
        Ac = A[col]
        for x in range(8):
            axc = Ar[x] * val
            if axc == 0.0:
                continue
            spx = sp[x]
            for y in range(8):
                spx[y] += axc * Ac[y]
    return sp


def _reconstruct_py(blocks, qscale):
    rgb = bytearray(IMG_W * IMG_H * 3)
    n_mb = MB_COLS * MB_ROWS
    for mb in range(n_mb):
        base = mb * 6
        cr = _idct_block_py(blocks[base + 0], qscale)
        cb = _idct_block_py(blocks[base + 1], qscale)
        y1 = _idct_block_py(blocks[base + 2], qscale)
        y2 = _idct_block_py(blocks[base + 3], qscale)
        y3 = _idct_block_py(blocks[base + 4], qscale)
        y4 = _idct_block_py(blocks[base + 5], qscale)
        x0 = (mb // MB_ROWS) * 16
        y0 = (mb % MB_ROWS) * 16
        for ly in range(16):
            yy = y0 + ly
            row_off = (yy * IMG_W + x0) * 3
            luma_top = ly < 8
            for lx in range(16):
                if luma_top:
                    Yv = (y1 if lx < 8 else y2)[ly][lx & 7]
                else:
                    Yv = (y3 if lx < 8 else y4)[ly & 7][lx & 7]
                Yv += 128.0
                crv = cr[ly >> 1][lx >> 1]
                cbv = cb[ly >> 1][lx >> 1]
                o = row_off + lx * 3
                rgb[o] = _clamp8(Yv + 1.402 * crv)
                rgb[o + 1] = _clamp8(Yv - 0.3437 * cbv - 0.7143 * crv)
                rgb[o + 2] = _clamp8(Yv + 1.772 * cbv)
    return bytes(rgb)


def decode_frame(data, offset):
    """Decodifica um frame MDEC (um slot) em (w, h, rgb, qscale, version)."""
    qscale, version, blocks = _decode_coeffs(data, offset)
    if HAVE_NUMPY:
        rgb = _reconstruct_numpy(blocks, qscale)
    else:
        rgb = _reconstruct_py(blocks, qscale)
    return IMG_W, IMG_H, rgb, qscale, version


def stage_of(path):
    m = re.search(r"STAGE(\d+)", path, re.IGNORECASE)
    return m.group(1) if m else None


def decode_file(path, outroot):
    data = open(path, "rb").read()
    n_slots = len(data) // SLOT
    name = os.path.splitext(os.path.basename(path))[0]
    stage = stage_of(path)
    outdir = os.path.join(outroot, "STAGE%s" % stage) if stage else outroot
    os.makedirs(outdir, exist_ok=True)
    made = []
    for slot in range(n_slots):
        w, h, rgb, q, v = decode_frame(data, slot * SLOT)
        dest = os.path.join(outdir, "%s_%d.png" % (name, slot))
        write_png(dest, w, h, rgb)
        made.append(dest)
        print("OK  %s slot %d -> %s  (%dx%d q=%d v%d)"
              % (os.path.basename(path), slot, os.path.basename(dest), w, h, q, v))
    return made


def main(argv):
    args = argv[1:]
    outroot = None
    files = []
    i = 0
    while i < len(args):
        if args[i] == "--out":
            outroot = args[i + 1]
            i += 2
        else:
            files.append(args[i])
            i += 1
    if not files:
        print(__doc__)
        return 1
    if outroot is None:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        outroot = paths.assets()
    total = 0
    for f in files:
        try:
            total += len(decode_file(f, outroot))
        except Exception as e:
            print("ERRO %s: %s" % (os.path.basename(f), e))
    print("Total de PNGs gerados: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
