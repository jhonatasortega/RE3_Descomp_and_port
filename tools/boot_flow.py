#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Mapa do FLUXO DE BOOT do RE3 PS1 NTSC-U (SLUS_009.23) e dos menus de titulo.

O que este script prova/imprime:

1. `--ids`  A tabela de overlays do EXE em `0x8009c944` (24 registros de 12 B:
   `{u32 file_index, u32 entry, u32 *dest}`) resolvida para NOME de arquivo.
   ATENCAO: `ovl_id != file_index`. A ordem dos ids e:
       0 TITLE, 1 WARNING, 2 MEM_CARD, 3 DIEDEMO, 4 OPTION, 5 OPENING,
       6 SELECT, 7 JILL_SEL, 8 RESULT, 9 ENDING, 10 EPILOG, 11 STAFF_R,
       12 PC_SYS, 13 LTSOUT, 14 R214_OL, 15 MUSICBOX, 16 GEARBOX,
       17..23 overlays de sala (slot 0x8011a000).
   A identidade sai do campo `entry`: cada `entry` cai no prologo
   `addiu $sp,$sp,-N` de exatamente um arquivo (a matriz de
   `docs/decomp/notes/menu_overlays.md` §4). `file_index` confere de forma
   independente porque a tabela de arquivos do CD (`0x800946a4`) esta em ordem
   ISO e `BIN/` e o 1o diretorio -> BIN/*.BIN sao os indices 0x00..0x10 em
   ordem alfabetica.

2. `--loads`  Todo sitio (no EXE e nos 17 overlays) que chama
   `load_overlay_task 0x80031f50(a0=task_slot, a1=ovl_id)` ou
   `load_overlay_run  0x80031fc0(a0=ovl_id)`, com o argumento resolvido por
   propagacao de constante para tras (inclui o delay slot do `jal`).

3. `--frames NOME`  Todos os `sh`/`sb`/`addiu` de constante que alimentam um
   contador comparado com `beqz/bne` no overlay - candidatos a DURACAO EM
   FRAMES. Sem interpretacao: imprime o sitio para o humano conferir.

Uso:
    PYTHONIOENCODING=utf-8 python tools/boot_flow.py --ids
    PYTHONIOENCODING=utf-8 python tools/boot_flow.py --loads
    PYTHONIOENCODING=utf-8 python tools/boot_flow.py --calls WARNING
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe_parse import Exe                       # noqa: E402
from overlay_parse import Overlay, all_overlays, DEST_SLOTS   # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE_PATH = os.path.join(REPO, "extracted", "ntsc-u", "SLUS_009.23")

OVL_TABLE_ADDR = 0x8009C944
OVL_TABLE_N = 24
LOAD_TASK = 0x80031F50
LOAD_RUN = 0x80031FC0
CD_READ = 0x80012818

#: BIN/*.BIN em ordem alfabetica == file_index 0x00..0x10 (ordem ISO)
BIN_ALPHA = [
    "DIEDEMO", "ENDING", "EPILOG", "GEARBOX", "JILL_SEL", "LTSOUT",
    "MEM_CARD", "MUSICBOX", "OPENING", "OPTION", "PC_SYS", "R214_OL",
    "RESULT", "SELECT", "STAFF_R", "TITLE", "WARNING",
]


def overlay_ids(exe=None):
    """ovl_id -> (nome, file_index, entry, dest_ptr, dest_addr). Le do EXE."""
    exe = exe or Exe(EXE_PATH)
    out = {}
    for i in range(OVL_TABLE_N):
        a = OVL_TABLE_ADDR + i * 12
        fi, entry, dp = exe.u32(a), exe.u32(a + 4), exe.u32(a + 8)
        name = BIN_ALPHA[fi] if fi < len(BIN_ALPHA) else "ROOM_%03x" % fi
        out[i] = (name, fi, entry, dp, exe.u32(dp) if exe.valid_vaddr(dp) else 0)
    return out


def _prop_args(ins):
    """Propagacao forward de constantes simples; devolve lista de
    (sitio, alvo, {reg: valor}) para jal em LOAD_TASK/LOAD_RUN/CD_READ."""
    res = []
    regs = {}
    ARGS = ("$a0", "$a1", "$a2", "$a3")

    def apply(regs, m, ops, o):
        if m == "lui" and len(ops) == 2:
            try:
                regs[ops[0]] = (int(ops[1], 0) << 16) & 0xFFFFFFFF
            except ValueError:
                regs[ops[0]] = None
        elif m in ("addiu", "ori", "addi") and len(ops) == 3:
            try:
                v = int(ops[2], 0)
            except ValueError:
                regs[ops[0]] = None
                return
            if m != "ori" and v >= 0x8000:
                v -= 0x10000
            b = 0 if ops[1] == "$zero" else regs.get(ops[1])
            regs[ops[0]] = None if b is None else (
                (b | v) if m == "ori" else (b + v)) & 0xFFFFFFFF
        elif m == "move" and len(ops) == 2:
            regs[ops[0]] = 0 if ops[1] == "$zero" else regs.get(ops[1])
        elif m in ("sw", "sh", "sb", "beq", "bne", "beqz", "bnez", "j", "jal",
                   "jr", "jalr", "blez", "bgtz", "bltz", "bgez", "nop", "b"):
            pass
        elif ops and ops[0].startswith("$"):
            regs[ops[0]] = None

    for i, rec in enumerate(ins):
        a, m, o = rec[0], rec[1], rec[2]
        ops = [x.strip() for x in o.split(",")] if o else []
        if m == "addiu" and len(ops) == 3 and ops[0] == "$sp" and ops[1] == "$sp":
            regs = {}
        if m == "jal" and o:
            try:
                tgt = int(o, 0)
            except ValueError:
                tgt = -1
            if tgt in (LOAD_TASK, LOAD_RUN, CD_READ):
                r = dict(regs)
                if i + 1 < len(ins):                     # delay slot conta
                    n = ins[i + 1]
                    nops = [x.strip() for x in n[2].split(",")] if n[2] else []
                    apply(r, n[1], nops, n[2])
                res.append((a, tgt, {k: r.get(k) for k in ARGS}))
        apply(regs, m, ops, o)
    return res


def loads(exe=None):
    exe = exe or Exe(EXE_PATH)
    ids = overlay_ids(exe)
    rows = []
    for a, tgt, r in _prop_args(exe.disasm_all()):
        if tgt == CD_READ:
            continue
        oid = r["$a1"] if tgt == LOAD_TASK else r["$a0"]
        nm = ids[oid][0] if isinstance(oid, int) and oid in ids else "?"
        rows.append(("EXE", a, "task" if tgt == LOAD_TASK else "run",
                     r["$a0"] if tgt == LOAD_TASK else None, oid, nm))
    for o in all_overlays():
        for a, tgt, r in o.call_args():
            if tgt not in (LOAD_TASK, LOAD_RUN):
                continue
            r = r or {}
            oid = r.get("a1") if tgt == LOAD_TASK else r.get("a0")
            nm = ids[oid][0] if isinstance(oid, int) and oid in ids else "?"
            rows.append((o.name, a, "task" if tgt == LOAD_TASK else "run",
                         r.get("a0") if tgt == LOAD_TASK else None, oid, nm))
    return rows


def _cli(argv):
    exe = Exe(EXE_PATH)
    if "--ids" in argv:
        print("ovl_id  file_idx  arquivo     entry      dest_ptr   dest")
        for i, (nm, fi, entry, dp, da) in sorted(overlay_ids(exe).items()):
            print("  %2d      0x%03x   %-10s %08x   %08x   %08x"
                  % (i, fi, nm, entry, dp, da))
    if "--loads" in argv:
        print("origem     sitio     modo  task  ovl_id  overlay")
        for src, a, mode, task, oid, nm in loads(exe):
            print("%-10s %08x  %-4s  %-4s  %-6s  %s"
                  % (src, a, mode, task if task is not None else "-",
                     oid if oid is not None else "?", nm))
    for i, a in enumerate(argv):
        if a == "--calls" and i + 1 < len(argv):
            o = Overlay(argv[i + 1])
            ins = [(x[0], x[1], x[2]) for x in o.disasm(o.base, o.size // 4, show=False)]
            for site, tgt, r in _prop_args(ins):
                print("%08x -> %08x  %s" % (site, tgt, r))


if __name__ == "__main__":
    _cli(sys.argv[1:])
