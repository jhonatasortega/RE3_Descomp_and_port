#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
rofs_extract.py - Extrator dos arquivos empacotados Rofs*.dat do Resident Evil 3 (PC classico).

Formato Rofs (engenharia reversa; confere com reevengi-tools/rofs.c de P. Mandin, GPL):

  Cabecalho do container (offsets em bytes):
    0x00  u8[21]  cabecalho "cru" (rofs_header_t): 5 x u32 + 1 byte
    ...   asciiz  nome do diretorio nivel 1 (ex.: "DATA_A")
    ...   u32     offset do indice (em unidades de 8 bytes)  <- dir nivel 2
          u32     length
    ...   asciiz  nome do diretorio nivel 2 (ex.: "VOICE")

  Indice de arquivos (em offset_dir2 * 8):
    u32     num_files
    Para cada arquivo:
      u32   offset  (em unidades de 8 bytes -> byte_offset = offset*8)
      u32   length  (tamanho bruto no container, informativo)
      asciiz nome do arquivo (8.3, ex.: "M101A010.WAV")

  Cada arquivo (em byte_offset) e CRIPTOGRAFADO e opcionalmente COMPACTADO:
    Cabecalho de cripto (rofs_crypt_header_t, 16 bytes):
      u16   data_offset   (do inicio do cabecalho ate os dados criptografados)
      u16   num_blocks    (numero de blocos / chaves)
      u32   dec_length    (tamanho final descriptografado/descompactado)
      u8    ident[8]      ("NotComp"/"Hi_Comp" XOR ident[7])
    Seguido de:
      u32[num_blocks]  chaves de descriptografia
      u32[num_blocks]  tamanhos de cada bloco (criptografado)
    Seguido de num_blocks blocos criptografados.

  Descriptografia por bloco: XOR com keystream de um LCG (re3_next_key).
  Descompactacao (se ident=="Hi_Comp"): LZ com janela de 4096 bytes (depack_block).

  Resultado: um WAV RIFF padrao (as vozes usam MS-ADPCM mono 22050 Hz, 4 bits).

Uso:
    python tools/rofs_extract.py <rofs.dat> <outdir>          # extrai todos os arquivos
    python tools/rofs_extract.py <rofs.dat> --list            # apenas lista

Referencia do formato: reevengi-tools (github.com/pmandin/reevengi-tools), GPLv2.
"""
import os
import struct
import sys

BASE_ARRAY = [
    0x00e6, 0x01a4, 0x00e6, 0x01c5, 0x0130, 0x00e8, 0x03db, 0x008b,
    0x0141, 0x018e, 0x03ae, 0x0139, 0x00f0, 0x027a, 0x02c9, 0x01b0,
    0x01f7, 0x0081, 0x0138, 0x0285, 0x025a, 0x015b, 0x030f, 0x0335,
    0x02e4, 0x01f6, 0x0143, 0x00d1, 0x0337, 0x0385, 0x007b, 0x00c6,
    0x0335, 0x0141, 0x0186, 0x02a1, 0x024d, 0x0342, 0x01fb, 0x03e5,
    0x01b0, 0x006d, 0x0140, 0x00c0, 0x0386, 0x016b, 0x020b, 0x009a,
    0x0241, 0x00de, 0x015e, 0x035a, 0x025b, 0x0154, 0x0068, 0x02e8,
    0x0321, 0x0071, 0x01b0, 0x0232, 0x02d9, 0x0263, 0x0164, 0x0290,
]


def _next_key(key):
    key = (key * 0x5d588b65) & 0xFFFFFFFF
    key = (key + 0x8000000b) & 0xFFFFFFFF
    return (key >> 24) & 0xFF, key


def decrypt_block(data, key):
    """XOR-descriptografa um bloco usando o keystream do LCG (re3_next_key)."""
    out = bytearray(data)
    xor_key, key = _next_key(key)
    bi, key = _next_key(key)
    base_index = bi % 0x3f
    block_index = 0
    for i in range(len(out)):
        if block_index > BASE_ARRAY[base_index]:
            bi, key = _next_key(key)
            base_index = bi % 0x3f
            xor_key, key = _next_key(key)
            block_index = 0
        out[i] ^= xor_key
        block_index += 1
    return bytes(out)


def depack_block(src, dst_length):
    """Descompacta um bloco 'Hi_Comp' (LZ com janela de 4096 bytes)."""
    tmp = bytearray(4096 + 256)
    for i in range(256):
        for j in range(16):
            tmp[i * 16 + j] = i
    dst = bytearray(dst_length)
    src_num_bit = 0
    src_index = 0
    tmp_index = 0
    dst_index = 0
    n = len(src)
    while src_index < n and dst_index < dst_length:
        src_num_bit += 1
        value = src[src_index] << src_num_bit
        src_index += 1
        if src_index < n:
            value |= src[src_index] >> (8 - src_num_bit)
        if src_num_bit == 8:
            src_index += 1
            src_num_bit = 0
        if (value & (1 << 8)) == 0:
            dst[dst_index] = value & 0xFF
            tmp[tmp_index] = value & 0xFF
            dst_index += 1
            tmp_index += 1
        else:
            if src_index >= n:
                break
            value2 = (src[src_index] << src_num_bit) & 0xFF
            src_index += 1
            if src_index < n:
                value2 |= src[src_index] >> (8 - src_num_bit)
            tmp_length = (value2 & 0x0f) + 2
            tmp_start = (value2 >> 4) & 0xfff
            tmp_start |= (value & 0xff) << 4
            if dst_index + tmp_length > dst_length:
                tmp_length = dst_length - dst_index
            for k in range(tmp_length):
                b = tmp[tmp_start + k]
                dst[dst_index + k] = b
                tmp[tmp_index + k] = b
            dst_index += tmp_length
            tmp_index += tmp_length
        if tmp_index >= 4096:
            tmp_index = 0
    return bytes(dst[:dst_index])


def _cstr(buf, off):
    end = buf.index(b'\x00', off)
    return buf[off:end].decode('latin1'), end + 1


def list_entries(data):
    """Retorna (dir1, dir2, [(nome, byte_offset, length), ...])."""
    # cabecalho cru = 21 bytes (5*u32 + 1)
    off = 21
    dir1, off = _cstr(data, off)
    dir2_offset, dir2_length = struct.unpack_from('<II', data, off)
    off += 8
    dir2, off = _cstr(data, off)
    idx = dir2_offset * 8
    num_files = struct.unpack_from('<I', data, idx)[0]
    idx += 4
    entries = []
    for _ in range(num_files):
        foff, flen = struct.unpack_from('<II', data, idx)
        idx += 8
        name, idx = _cstr(data, idx)
        entries.append((name, foff * 8, flen))
    return dir1, dir2, entries


def extract_file(data, byte_offset):
    """Descriptografa/descompacta um arquivo e retorna os bytes originais (ex.: WAV)."""
    doff, num_blocks, dec_length = struct.unpack_from('<HHI', data, byte_offset)
    ident = bytearray(data[byte_offset + 8:byte_offset + 16])
    k = ident[7]
    plain = bytes(b ^ k for b in ident)
    compressed = plain.startswith(b'Hi_Comp')
    keys = struct.unpack_from('<%dI' % num_blocks, data, byte_offset + 16)
    lens = struct.unpack_from('<%dI' % num_blocks, data, byte_offset + 16 + num_blocks * 4)
    p = byte_offset + doff
    out = bytearray()
    for i in range(num_blocks):
        blk = data[p:p + lens[i]]
        p += lens[i]
        dec = decrypt_block(blk, keys[i])
        if compressed:
            dec = depack_block(dec, 32768)
        out += dec
    return bytes(out[:dec_length]) if not compressed else bytes(out)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    path = argv[1]
    data = open(path, 'rb').read()
    dir1, dir2, entries = list_entries(data)
    print("Rofs: %s/%s  (%d arquivos)" % (dir1, dir2, len(entries)))
    if len(argv) >= 3 and argv[2] == '--list':
        for name, off, ln in entries:
            print("  %-14s off=0x%08x len=%d" % (name, off, ln))
        return 0
    if len(argv) < 3:
        print("Uso: python rofs_extract.py <rofs.dat> <outdir>")
        return 1
    outdir = argv[2]
    os.makedirs(outdir, exist_ok=True)
    for name, off, ln in entries:
        blob = extract_file(data, off)
        with open(os.path.join(outdir, name), 'wb') as f:
            f.write(blob)
    print("Extraidos %d arquivos em %s" % (len(entries), outdir))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
