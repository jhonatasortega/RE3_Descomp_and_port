#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Loader + desassemblador do executavel PS1 (SLUS_009.23, RE3 NTSC-U).

Uso como biblioteca:
    from exe_parse import Exe
    e = Exe("extracted/ntsc-u/SLUS_009.23")
    e.disasm(0x80011b80, 40)          # desmonta N instrucoes
    e.u32(0x80010000)                 # le u32 no endereco virtual
    e.find_pointer_tables()           # acha arrays de ponteiros 0x800xxxxx

Rodado direto: imprime header + resumo de tabelas de ponteiros.
"""
import struct, sys

class Exe:
    def __init__(self, path):
        self.path = path
        self.raw = open(path, "rb").read()
        assert self.raw[:8] == b"PS-X EXE", "nao e PS-X EXE"
        self.pc    = struct.unpack("<I", self.raw[0x10:0x14])[0]
        self.gp    = struct.unpack("<I", self.raw[0x14:0x18])[0]
        self.base  = struct.unpack("<I", self.raw[0x18:0x1c])[0]
        self.tsize = struct.unpack("<I", self.raw[0x1c:0x20])[0]
        self.sp    = struct.unpack("<I", self.raw[0x30:0x34])[0]
        self.text  = self.raw[0x800:0x800 + self.tsize]
        self.vend  = self.base + self.tsize

    # ---- mapeamento vaddr <-> offset ----
    def off(self, vaddr):
        """offset no array self.text para um endereco virtual"""
        return vaddr - self.base

    def valid_vaddr(self, v):
        return self.base <= v < self.vend

    def u32(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<I", self.text[o:o+4])[0]

    def u16(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<H", self.text[o:o+2])[0]

    def s16(self, vaddr):
        o = self.off(vaddr)
        return struct.unpack("<h", self.text[o:o+2])[0]

    def u8(self, vaddr):
        return self.text[self.off(vaddr)]

    def bytes_at(self, vaddr, n):
        o = self.off(vaddr)
        return self.text[o:o+n]

    # ---- disassembler ----
    def _md(self):
        import capstone
        md = capstone.Cs(capstone.CS_ARCH_MIPS,
                         capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
        md.detail = True
        return md

    def disasm(self, vaddr, count=40, show=True):
        md = self._md()
        o = self.off(vaddr)
        code = self.text[o:o + count*4]
        out = []
        for insn in md.disasm(code, vaddr):
            out.append((insn.address, insn.mnemonic, insn.op_str, insn.bytes))
            if show:
                print("%08x  %-8s %s" % (insn.address, insn.mnemonic, insn.op_str))
            if len(out) >= count:
                break
        return out

    def disasm_all(self):
        """Desmonta TODO o text linearmente, pulando 4 bytes quando capstone falha
        (o text mistura codigo e dados). Cacheia o resultado."""
        if getattr(self, "_all", None) is not None:
            return self._all
        md = self._md()
        out = []
        t = self.text
        n = len(t)
        pos = 0
        while pos + 4 <= n:
            got = False
            for insn in md.disasm(t[pos:], self.base + pos):
                out.append((insn.address, insn.mnemonic, insn.op_str))
                got = True
                pos = (insn.address - self.base) + insn.size
                # continua o generator normalmente ate ele parar
            if not got:
                pos += 4
        self._all = out
        return out

    # ---- xref: acha lui/(addiu|ori|lw|sw) que formam um endereco ----
    def find_hi_lo_refs(self, target):
        """Retorna lista de (vaddr_do_lui, mnem_lo) onde um par lui+lo forma `target`
        (com combinacao hi/lo do MIPS: addr = (hi<<16) + signed(lo))."""
        import capstone
        md = self._md()
        insns = list(md.disasm(self.text, self.base))
        # indexa lui por registrador -> (addr, imm_hi) mais recente
        res = []
        last_lui = {}   # reg -> (vaddr, hi)
        for ins in insns:
            m = ins.mnemonic
            ops = [o.strip() for o in ins.op_str.split(",")]
            if m == "lui" and len(ops) == 2:
                reg = ops[0]
                try:
                    hi = int(ops[1], 0)
                except ValueError:
                    hi = None
                if hi is not None:
                    last_lui[reg] = (ins.address, hi)
            elif m in ("addiu", "ori", "lw", "sw", "lbu", "lhu", "lb", "lh", "sb", "sh", "lwc2", "addu"):
                # formatos: "rd, rs, imm"  ou  "rt, imm(rs)"
                lo = None; base_reg = None
                if "(" in ins.op_str:
                    # rt, off(base)
                    try:
                        off = ins.op_str.split(",")[1].strip()
                        loval = off.split("(")[0]
                        base_reg = off.split("(")[1].rstrip(")")
                        lo = int(loval, 0)
                    except Exception:
                        pass
                elif len(ops) == 3:
                    base_reg = ops[1]
                    try:
                        lo = int(ops[2], 0)
                    except ValueError:
                        lo = None
                if lo is not None and base_reg in last_lui:
                    hi_addr, hi = last_lui[base_reg]
                    if lo >= 0x8000:
                        lo -= 0x10000
                    addr = ((hi << 16) + lo) & 0xffffffff
                    if addr == target:
                        res.append((hi_addr, ins.address, m, ins.op_str))
        return res

    # ---- scan de tabelas de ponteiros ----
    def find_pointer_tables(self, min_run=6, lo=None, hi=None):
        """Acha corridas de u32 consecutivos que caem na faixa [lo,hi] (default: faixa do codigo)."""
        lo = self.base if lo is None else lo
        hi = self.vend if hi is None else hi
        t = self.text
        n = len(t)
        runs = []
        i = 0
        cur = []
        cur_start = 0
        while i + 4 <= n:
            v = struct.unpack("<I", t[i:i+4])[0]
            if lo <= v < hi:
                if not cur:
                    cur_start = i
                cur.append(v)
            else:
                if len(cur) >= min_run:
                    runs.append((self.base + cur_start, cur))
                cur = []
            i += 4
        if len(cur) >= min_run:
            runs.append((self.base + cur_start, cur))
        return runs


if __name__ == "__main__":
    e = Exe(sys.argv[1] if len(sys.argv) > 1 else "extracted/ntsc-u/SLUS_009.23")
    print("== PS-X EXE ==")
    print("entry  %08x" % e.pc)
    print("base   %08x" % e.base)
    print("tsize  %08x (%d)" % (e.tsize, e.tsize))
    print("vend   %08x" % e.vend)
    print("sp     %08x" % e.sp)
    print()
    runs = e.find_pointer_tables(min_run=6)
    print("tabelas de ponteiros (>=6 consecutivos):", len(runs))
    # ordena por tamanho desc
    for start, ptrs in sorted(runs, key=lambda r: -len(r[1]))[:40]:
        print("  @%08x  n=%-4d  [%08x .. %08x]" % (start, len(ptrs), ptrs[0], ptrs[-1]))
