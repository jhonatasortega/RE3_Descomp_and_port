#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Desassemblador MIPS R3000 com suporte a COP2 (GTE) para o EXE do RE3 PS1.

O capstone PARA quando encontra uma instrucao do coprocessador 2 (a GTE do PS1:
`rtps`, `nclip`, `gte_ldv0`/`ctc2`/`mfc2` ...), o que corta o desassembly no meio
das rotinas graficas. Este modulo tenta o capstone instrucao-por-instrucao e, se
ele falhar, decodifica a palavra a mao (COP2 + alguns casos).

Uso:
    from mips_dis import dis
    for a, m, o in dis(exe, 0x8001bda0, 200): print('%08x %-10s %s' % (a, m, o))
"""
import struct

REG = ['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7',
       's0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra']

# GTE: nome por bits 0..5 do "cop2 function" (bit 25 setado)
GTE_FN = {
    0x01:'rtps', 0x06:'nclip', 0x0c:'op', 0x10:'dpcs', 0x11:'intpl', 0x12:'mvmva',
    0x13:'ncds', 0x14:'cdp', 0x16:'ncdt', 0x1b:'nccs', 0x1c:'cc', 0x1e:'ncs',
    0x20:'nct', 0x28:'sqr', 0x29:'dcpl', 0x2a:'dpct', 0x2d:'avsz3', 0x2e:'avsz4',
    0x30:'rtpt', 0x3d:'gpf', 0x3e:'gpl', 0x3f:'ncct',
}

def _cop2(w, addr):
    rs = (w >> 21) & 31   # sub-opcode
    rt = (w >> 16) & 31
    rd = (w >> 11) & 31
    if w & (1 << 25):
        fn = w & 0x3f
        return (GTE_FN.get(fn, 'cop2fn_0x%02x' % fn), 'sf=%d' % ((w >> 19) & 1))
    m = {0:'mfc2', 2:'cfc2', 4:'mtc2', 6:'ctc2'}.get(rs)
    if m:
        return (m, '$%s, $%d' % (REG[rt], rd))
    return ('cop2', '0x%08x' % w)

def decode(w, addr):
    """Decodifica uma palavra que o capstone rejeitou. Devolve (mnem, ops)."""
    op = w >> 26
    rs = (w >> 21) & 31
    rt = (w >> 16) & 31
    imm = w & 0xffff
    simm = imm - 0x10000 if imm >= 0x8000 else imm
    if op == 0x12:                       # COP2
        return _cop2(w, addr)
    if op == 0x32:                       # LWC2
        return ('lwc2', '$%d, %d($%s)' % (rt, simm, REG[rs]))
    if op == 0x3a:                       # SWC2
        return ('swc2', '$%d, %d($%s)' % (rt, simm, REG[rs]))
    return ('.word', '0x%08x' % w)

def dis(exe, vaddr, count=64):
    """Lista [(addr, mnem, ops)] a partir de vaddr, sem parar em COP2."""
    import capstone
    md = capstone.Cs(capstone.CS_ARCH_MIPS,
                     capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
    out = []
    a = vaddr
    for _ in range(count):
        b = exe.bytes_at(a, 4)
        if len(b) < 4:
            break
        got = None
        for ins in md.disasm(b, a):
            got = (ins.address, ins.mnemonic, ins.op_str)
            break
        if got is None:
            w = struct.unpack('<I', b)[0]
            m, o = decode(w, a)
            got = (a, m, o)
        out.append(got)
        a += 4
    return out

if __name__ == '__main__':
    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from exe_parse import Exe
    e = Exe(sys.argv[1] if len(sys.argv) > 3 else
            'extracted/ntsc-u/SLUS_009.23')
    start = int(sys.argv[-2], 16); n = int(sys.argv[-1])
    for a, m, o in dis(e, start, n):
        print('%08x  %-10s %s' % (a, m, o))
