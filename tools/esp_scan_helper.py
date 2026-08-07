#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Helpers de busca no EXE do RE3: xrefs hi/lo, jal, e imediatos.

Uso:  python tools/esp_scan_helper.py xref 0x800ba8a8 [...]
      python tools/esp_scan_helper.py jal 0x80022990 [...]
      python tools/esp_scan_helper.py imm 0xd4        (acha addiu com esse imediato)
"""
import sys, os, struct, collections
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__))))
from exe_parse import Exe

LOAD_STORE = {0x20,0x21,0x23,0x24,0x25,0x27,0x28,0x29,0x2b,0x2f,0x37,0x3f,0x09,0x0d,0x0c}

def xrefs(e, targets):
    res = collections.defaultdict(list)
    lui = {}
    t, base = e.text, e.base
    for off in range(0, len(t) - 3, 4):
        w = struct.unpack('<I', t[off:off+4])[0]
        op = w >> 26
        if op == 0x0f:
            lui[(w >> 16) & 31] = (w & 0xffff) << 16
        elif op in LOAD_STORE:
            rs = (w >> 21) & 31
            imm = w & 0xffff
            if imm >= 0x8000: imm -= 0x10000
            if rs in lui:
                a = (lui[rs] + imm) & 0xffffffff
                if a in targets: res[a].append(base + off)
    return res

def jals(e, targets):
    res = collections.defaultdict(list)
    t, base = e.text, e.base
    for off in range(0, len(t) - 3, 4):
        w = struct.unpack('<I', t[off:off+4])[0]
        if (w >> 26) in (2, 3):
            d = ((base + off) & 0xf0000000) | ((w & 0x3ffffff) << 2)
            if d in targets: res[d].append(base + off)
    return res

def imms(e, val):
    """addiu/addi rt, rs, +/-val  (procura stride de laco)."""
    out = []
    t, base = e.text, e.base
    for off in range(0, len(t) - 3, 4):
        w = struct.unpack('<I', t[off:off+4])[0]
        op = w >> 26
        if op in (0x08, 0x09):
            imm = w & 0xffff
            s = imm - 0x10000 if imm >= 0x8000 else imm
            if abs(s) == val: out.append((base + off, s))
    return out

if __name__ == '__main__':
    e = Exe('extracted/ntsc-u/SLUS_009.23')
    mode = sys.argv[1]
    if mode == 'imm':
        for a, s in imms(e, int(sys.argv[2], 0)):
            print('%08x  imm=%d' % (a, s))
    else:
        tg = [int(x, 0) for x in sys.argv[2:]]
        r = xrefs(e, set(tg)) if mode == 'xref' else jals(e, set(tg))
        for x in tg:
            print('%08x: %s' % (x, ' '.join('%08x' % v for v in r[x])))
