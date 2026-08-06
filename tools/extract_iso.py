#!/usr/bin/env python3
"""Extrai o sistema de arquivos de uma imagem raw de PS1 (MODE2/2352) para uma pasta.

Arquivos de dados normais (Mode 2 Form 1) sao extraidos corretamente (2048 bytes/setor).
Midia em streaming (Form 2: .STR video, .XA/.XAS audio) NAO e extraida aqui — esses
precisam do jPSXdec para saida valida; sao apenas listados no final.

Uso:
    python extract_iso.py "<imagem>.bin" "<pasta de saida>"
"""
import sys
import os
import struct

SECTOR = 2352
USER_OFFSET = 24
USER_SIZE = 2048
STREAMED = {"STR", "XA", "XAS"}   # precisam de jPSXdec p/ saida valida


def read_sector(f, lsn):
    f.seek(lsn * SECTOR + USER_OFFSET)
    return f.read(USER_SIZE)


def parse_dir(f, lba, length, path, out, seen):
    if lba in seen:
        return
    seen.add(lba)
    nsec = (length + USER_SIZE - 1) // USER_SIZE
    data = b"".join(read_sector(f, lba + i) for i in range(nsec))
    pos = 0
    while pos < len(data):
        rl = data[pos]
        if rl == 0:
            pos = ((pos // USER_SIZE) + 1) * USER_SIZE
            continue
        rec = data[pos:pos + rl]
        ext_lba = struct.unpack_from("<I", rec, 2)[0]
        size = struct.unpack_from("<I", rec, 10)[0]
        flags = rec[25]
        nl = rec[32]
        name = rec[33:33 + nl]
        is_dir = bool(flags & 0x02)
        if nl == 1 and name in (b"\x00", b"\x01"):
            pos += rl
            continue
        nm = name.decode("ascii", "replace")
        if nm.endswith(";1"):
            nm = nm[:-2]
        full = path + "/" + nm
        out.append((full, size, is_dir, ext_lba))
        if is_dir:
            parse_dir(f, ext_lba, size, full, out, seen)
        pos += rl


def extract_file(f, lba, size, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    nsec = (size + USER_SIZE - 1) // USER_SIZE
    written = 0
    with open(dest, "wb") as o:
        for i in range(nsec):
            chunk = read_sector(f, lba + i)
            take = min(USER_SIZE, size - written)
            o.write(chunk[:take])
            written += take


def ext_of(full):
    base = full.rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[-1].upper() if "." in base else ""


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    img, outdir = sys.argv[1], sys.argv[2]
    with open(img, "rb") as f:
        pvd = read_sector(f, 16)
        if pvd[1:6] != b"CD001":
            print("PVD nao encontrado no setor 16 — imagem em modo/offset diferente?")
            return 2
        root = pvd[156:156 + 34]
        rlba = struct.unpack_from("<I", root, 2)[0]
        rsize = struct.unpack_from("<I", root, 10)[0]
        tree = []
        parse_dir(f, rlba, rsize, "", tree, set())

        files = [t for t in tree if not t[2]]
        skipped = []
        n = 0
        for full, size, is_dir, lba in files:
            if ext_of(full) in STREAMED:
                skipped.append(full)
                continue
            dest = os.path.join(outdir, full.lstrip("/").replace("/", os.sep))
            extract_file(f, lba, size, dest)
            n += 1
            if n % 100 == 0:
                print(f"  {n} arquivos...")

    print(f"\nExtraidos: {n} arquivos -> {outdir}")
    if skipped:
        print(f"\nPulados ({len(skipped)}) — usar jPSXdec p/ midia em streaming:")
        for s in skipped:
            print("  ", s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
