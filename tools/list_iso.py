#!/usr/bin/env python3
"""Lista o sistema de arquivos ISO9660 de uma imagem raw de PS1 (MODE2/2352).

Nao depende de bibliotecas externas. Extrai os 2048 bytes de dados de usuario
de cada setor (Mode 2 Form 1: 12 sync + 4 header + 8 subheader + 2048 dados).

Uso:
    python list_iso.py "<caminho da imagem>.bin"
"""
import sys
import struct
from collections import Counter

SECTOR = 2352
USER_OFFSET = 24   # inicio dos dados de usuario dentro do setor raw
USER_SIZE = 2048


def read_sector(f, lsn):
    f.seek(lsn * SECTOR + USER_OFFSET)
    return f.read(USER_SIZE)


def parse_dir(f, lba, length, path, out, seen):
    if lba in seen:          # guarda contra loops
        return
    seen.add(lba)
    nsec = (length + USER_SIZE - 1) // USER_SIZE
    data = b"".join(read_sector(f, lba + i) for i in range(nsec))
    pos = 0
    while pos < len(data):
        rec_len = data[pos]
        if rec_len == 0:
            # registros nao cruzam limite de setor: pula p/ o proximo
            pos = ((pos // USER_SIZE) + 1) * USER_SIZE
            continue
        rec = data[pos:pos + rec_len]
        ext_lba = struct.unpack_from("<I", rec, 2)[0]
        size = struct.unpack_from("<I", rec, 10)[0]
        flags = rec[25]
        name_len = rec[32]
        name = rec[33:33 + name_len]
        is_dir = bool(flags & 0x02)
        if name_len == 1 and name in (b"\x00", b"\x01"):   # '.' e '..'
            pos += rec_len
            continue
        nm = name.decode("ascii", "replace")
        if nm.endswith(";1"):
            nm = nm[:-2]
        full = path + "/" + nm
        out.append((full, size, is_dir))
        if is_dir:
            parse_dir(f, ext_lba, size, full, out, seen)
        pos += rec_len


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    with open(path, "rb") as f:
        pvd = read_sector(f, 16)
        if pvd[1:6] != b"CD001":
            print("PVD nao encontrado no setor 16.")
            print("bytes[0:8] =", pvd[0:8].hex(" "))
            print("A imagem pode ter offset/modo diferente.")
            return 2
        root = pvd[156:156 + 34]
        root_lba = struct.unpack_from("<I", root, 2)[0]
        root_size = struct.unpack_from("<I", root, 10)[0]
        out = []
        parse_dir(f, root_lba, root_size, "", out, set())

    files = [o for o in out if not o[2]]
    dirs = [o for o in out if o[2]]
    total = sum(o[1] for o in files)
    print(f"Diretorios: {len(dirs)} | Arquivos: {len(files)}")
    print(f"Tamanho total dos arquivos: {total:,} bytes")
    print("-" * 64)
    for full, size, is_dir in out:
        kind = "DIR " if is_dir else "    "
        print(f"{kind}{size:>11,}  {full}")

    ext = Counter()
    for full, size, is_dir in files:
        base = full.rsplit("/", 1)[-1]
        e = base.rsplit(".", 1)[-1].upper() if "." in base else "(sem ext)"
        ext[e] += 1
    print("-" * 64)
    print("Por extensao:", dict(ext.most_common()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
