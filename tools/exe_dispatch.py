#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Acha dispatches por tabela indexada (base + idx*4) via propagacao de constantes.

Distingue:
  - INDEXED: lw t9, off(base) onde `base` recebeu um `addu base,base,idx` (tabela!) -> jr/jalr
  - PTRVAR : lw t9, off(base) constante puro (ponteiro de funcao global) -> jr/jalr
"""
import sys, re
sys.path.insert(0, "tools")
from exe_parse import Exe

REG = None

def track(e):
    by = e.disasm_all()
    dispatches = []   # (site, table_addr, indexed_bool)
    # estado de registradores: reg -> (const_value or None, indexed_flag)
    regs = {}
    def getc(r):
        return regs.get(r, (None, False))
    for k,(a,m,o) in enumerate(by):
        ops = [x.strip() for x in o.split(",")] if o else []
        # reset heuristico em prologo de funcao
        if m == "addiu" and len(ops)==3 and ops[0]=="$sp" and ops[1]=="$sp":
            regs = {}  # novo frame -> zera
        if m == "lui" and len(ops)==2:
            try: regs[ops[0]] = ((int(ops[1],0)<<16)&0xffffffff, False)
            except: regs[ops[0]] = (None, False)
        elif m == "addiu" and len(ops)==3:
            cv,idx = getc(ops[1])
            try: imm=int(ops[2],0)
            except: imm=None
            if cv is not None and imm is not None:
                if imm>=0x8000: imm-=0x10000
                regs[ops[0]] = ((cv+imm)&0xffffffff, idx)
            else:
                regs[ops[0]] = (None, False)
        elif m == "ori" and len(ops)==3:
            cv,idx=getc(ops[1])
            try: imm=int(ops[2],0)
            except: imm=None
            if cv is not None and imm is not None: regs[ops[0]]=((cv|imm)&0xffffffff,idx)
            else: regs[ops[0]]=(None,False)
        elif m in ("addu","add") and len(ops)==3:
            c1,i1=getc(ops[1]); c2,i2=getc(ops[2])
            # base + index: um lado constante, outro nao -> mantem constante mas marca indexed
            if c1 is not None and c2 is None:
                regs[ops[0]] = (c1, True)
            elif c2 is not None and c1 is None:
                regs[ops[0]] = (c2, True)
            elif c1 is not None and c2 is not None:
                regs[ops[0]] = ((c1+c2)&0xffffffff, i1 or i2)
            else:
                regs[ops[0]] = (None, False)
        elif m in ("sll","sra","srl") and len(ops)==3:
            # resultado de shift = indice (nao constante p/ nossos fins)
            regs[ops[0]] = (None, False)
        elif m == "lw" and "(" in o:
            # lw rt, off(base)
            rt = ops[0]
            try:
                off = o.split(",")[1].strip()
                loff = int(off.split("(")[0],0); base = off.split("(")[1].rstrip(")")
            except:
                regs[rt]=(None,False); continue
            cv,idx = getc(base)
            if cv is not None:
                if loff>=0x8000: loff-=0x10000
                tbl = (cv+loff)&0xffffffff
                regs[rt] = (None, False)  # valor lido nao e constante
                # guarda info p/ possivel jr/jalr logo a frente
                regs["__lastload__"] = (tbl, idx, rt, a)
            else:
                regs[rt]=(None,False)
        elif m in ("jr","jalr"):
            reg = ops[-1]
            if reg == "$ra":
                continue
            ll = regs.get("__lastload__")
            if ll and ll[2]==reg:
                tbl, idx, rt, la = ll
                if e.base <= tbl < e.vend:
                    dispatches.append((a, tbl, idx))
        else:
            # instrucoes que escrevem em rd desconhecido -> invalida
            if ops:
                rd = ops[0]
                if rd.startswith("$") and rd not in ("$sp",):
                    regs[rd] = (None, False)
    return dispatches

if __name__ == "__main__":
    e = Exe("extracted/ntsc-u/SLUS_009.23")
    disp = track(e)
    from collections import Counter, defaultdict
    idxd = [d for d in disp if d[2]]
    print("total dispatch calls:", len(disp), "| indexed:", len(idxd))
    c = Counter(t for _,t,ix in disp if ix)
    print("\n== TABELAS INDEXADAS (base+idx*4) ==")
    sites = defaultdict(list)
    for a,t,ix in disp:
        if ix: sites[t].append(a)
    for tbl,cnt in sorted(c.items(), key=lambda x:-x[1]):
        print("  %08x  x%-3d  sites: %s"%(tbl,cnt," ".join("%08x"%s for s in sites[tbl][:5])))
