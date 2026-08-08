#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Extrator da GEOMETRIA da tela de status/inventario do RE3 PS1 (SLUS_009.23).

A tela de status NAO e um overlay de `BIN/*.BIN`: e uma TASK do EXE principal
(`0x8006dfdc`, contexto em `0x800e01c0`). Ela monta primitivas GPU (SPRT / TILE /
POLY_FT4) em buffers fixos de RAM a partir de uma TABELA DE RETANGULOS de
12 bytes por registro, achada em `0x8009f2ec` (tabela A) e `0x8009f890` (tabela B).

FORMATO PROVADO DO REGISTRO (12 bytes) -- veja `docs/decomp/notes/menu_inventario.md`:

    +0x00  u16  u    coordenada U na pagina de textura (pixels)
    +0x02  u16  v    coordenada V na pagina de textura (pixels)
    +0x04  u16  w    largura  em pixels de tela
    +0x06  u16  h    altura   em pixels de tela
    +0x08  u16  dx   X de tela (somado a base[idx].x)
    +0x0a  u16  dy   Y de tela (somado a base[idx].y)

Prova do layout: as 6 rotinas de montagem em `0x8006e600`..`0x8006eaf0` leem
exatamente esses campos (offsets +0/+2 -> u/v da SPRT; +4/+6 -> w/h da SPRT ou
TILE; +8/+0xa -> x0/y0 somados a `*(s16*)(ctx+0xe4+idx*4)`).

Espaco de coordenadas: PIXELS DE TELA 320x240 (NTSC-U, 1 buffer por campo).

Rotinas (a0=ctx, a1=buffer de primitivas, a2=tabela de retangulos, a3=empacotado):
    0x8006e600  monta SPRT      (len=4, code=0x64)   a3 = cnt | clut_y<<8 | semitrans<<16
    0x8006e6d8  monta POLY_FT4  (len=9, code=0x2c)   a3 = cnt | clut_y<<8 | tp<<16 | lado<<24
    0x8006e7d4  monta TILE      (len=3, code=0x60)   a3 = cnt                (rgb = 8,8,8)
    0x8006e8bc  posiciona SPRT      + AddPrim        a3 = cnt | base_idx<<8 | ot<<16
    0x8006e9d4  posiciona POLY_FT4  + AddPrim        a3 = cnt | base_idx<<8 | ot<<16
    0x8006eaf0  posiciona TILE      + AddPrim        a3 = cnt | base_idx<<8 | ot<<16

O ECG (os batimentos) do painel de condicao NAO passa por essas 6 rotinas: ele e um sexto
primitivo, `LINE_F2` (code 0x40), montado em `0x8006e84c` e desenhado em `0x8006c484`.
Ver `docs/decomp/notes/menu_ecg.md` e o subcomando `ecg` abaixo.

Uso:
    python tools/status_layout.py rects            # dump das 2 tabelas de retangulo
    python tools/status_layout.py calls            # sitios de montagem/posicionamento
    python tools/status_layout.py slots            # tabela VRAM de icone por slot
    python tools/status_layout.py sld              # offsets de ITEMA.SLD por item_id
    python tools/status_layout.py ecg              # ECG: cor, ponteiros e forma de onda
    python tools/status_layout.py json <saida>     # tudo em JSON
"""
import sys, os, struct, json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe_parse import Exe

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE_PATH = os.path.join(REPO, "extracted", "ntsc-u", "SLUS_009.23")

# --- constantes provadas (endereco virtual no EXE) ---
CTX = 0x800E01C0            # contexto da task de status
TASK_ENTRY = 0x8006DFDC     # entry da task
STATE_TABLE = 0x800A02F0    # 14 handlers por estado (ctx+0x10)
MODE_JUMP_INIT = 0x80011064  # modo (ctx+4) -> estado inicial
MODE_JUMP_DRAW = 0x8001104C  # modo (ctx+4) -> rotina de desenho
RECT_A = 0x8009F2EC         # tabela de retangulos A (telas FILE / caixa)
RECT_A_END = 0x8009F4E4
RECT_B = 0x8009F890         # tabela de retangulos B (status principal)
RECT_B_END = 0x800A0010
ICON_SLOT_VRAM = 0x800A004C  # (u16 x, u16 y) VRAM por slot de icone
SLD_OFFSETS = 0x8009F678    # u32 offset em ITEMA.SLD por item_id
ITEMI_FLAGS = 0x8009F568    # u8 por item_id (byte de flags do pedido de CD)

# --- ECG do painel de condicao (provado; ver docs/decomp/notes/menu_ecg.md) ---
ECG_MONTA = 0x8006E84C      # monta 32 LINE_F2 (code 0x42 = 0x40|semitrans) em 0x801af0e8
ECG_DESENHA = 0x8006C484    # escreve xy/rgb e AddPrim, chamada em 0x8006c33c
ECG_BUFFER = 0x801AF0E8     # 32 colunas x 2 buffers x 16 B = 0x400 -> termina em 0x801af4e8
ECG_COR = 0x800A0150        # 6 bytes por condicao: r,g,b + dr,dg,db (decaimento do rastro)
ECG_ONDA_PTR = 0x800A0174   # u32 por condicao -> tabela de (desloc_y, altura) por coluna
ECG_N_COND = 6
ECG_ONDA_BYTES = 160        # 80 pares; so os indices 0..73 sao alcancaveis (guarda k < 0x4a)
ECG_X = 0x4B                # 0x8006c518: x = base[0].x + 0x4b + k
ECG_Y = 0x25                # 0x8006c51c: y = base[0].y + 0x25 + onda[k]
ECG_K_LIMITE = 0x4A         # 0x8006c554
ECG_FASE_FIM = 0x51         # 0x8006e32c: fase >= 0x51 -> fase = -0x20 (0x8006e334)

BUILDERS = {
    0x8006E600: ("SPRT",     "build"),
    0x8006E6D8: ("POLY_FT4", "build"),
    0x8006E7D4: ("TILE",     "build"),
    0x8006E8BC: ("SPRT",     "place"),
    0x8006E9D4: ("POLY_FT4", "place"),
    0x8006EAF0: ("TILE",     "place"),
}

MOD_LO, MOD_HI = 0x80063000, 0x80073000


def rects(e, base, end):
    out = []
    a = base
    while a + 12 <= end:
        u, v, w, h, dx, dy = struct.unpack_from("<6H", e.bytes_at(a, 12), 0)
        out.append(dict(addr=a, u=u, v=v, w=w, h=h, dx=dx, dy=dy))
        a += 12
    return out


def func_starts(e):
    st = []
    for o in range(0, len(e.text), 4):
        w = struct.unpack_from("<I", e.text, o)[0]
        if (w >> 16) == 0x27BD and (w & 0x8000):
            st.append(e.base + o)
    return st


def call_sites(e, target, lo=MOD_LO, hi=MOD_HI):
    out = []
    for o in range(e.off(lo), e.off(hi), 4):
        w = struct.unpack_from("<I", e.text, o)[0]
        if (w >> 26) == 3 and (0x80000000 | ((w & 0x03FFFFFF) << 2)) == target:
            out.append(e.base + o)
    return out


class Tracer(object):
    """rastreador linear de constantes em registrador (lui/addiu/ori/move)."""

    def __init__(self, e):
        self.e = e
        self.all = e.disasm_all()
        self.idx = {a: i for i, (a, m, o) in enumerate(self.all)}

    def at(self, site, back=90):
        i = self.idx.get(site)
        if i is None:
            return {}
        regs = {}
        for j in range(max(0, i - back), i + 2):   # +2 inclui o delay slot
            a, m, op = self.all[j]
            ops = [o.strip() for o in op.split(",")]
            if m == "lui" and len(ops) == 2:
                try:
                    regs[ops[0]] = int(ops[1], 0) << 16
                except ValueError:
                    regs.pop(ops[0], None)
            elif m in ("addiu", "addi", "ori", "andi", "xori"):
                if len(ops) == 3:
                    d, s = ops[0], ops[1]
                    try:
                        val = int(ops[2], 0)
                    except ValueError:
                        val = None
                    if val is not None and (s in regs or s == "$zero"):
                        b = 0 if s == "$zero" else regs[s]
                        if m in ("addiu", "addi"):
                            if val >= 0x8000:
                                val -= 0x10000
                            regs[d] = (b + val) & 0xFFFFFFFF
                        elif m == "ori":
                            regs[d] = b | val
                        elif m == "andi":
                            regs[d] = b & val
                        else:
                            regs[d] = b ^ val
                    else:
                        regs.pop(d, None)
                else:
                    regs.pop(ops[0], None)
            elif m == "move":
                if len(ops) == 2 and ops[1] in regs:
                    regs[ops[0]] = regs[ops[1]]
                else:
                    regs.pop(ops[0], None)
            elif m in ("jal", "jalr"):
                if j != i:
                    for r in ("$a0", "$a1", "$a2", "$a3", "$v0", "$v1"):
                        regs.pop(r, None)
            elif m in ("nop", "j", "b", "beq", "bne", "beqz", "bnez",
                       "blez", "bgtz", "bltz", "bgez", "jr"):
                pass
            else:
                if ops and ops[0].startswith("$"):
                    regs.pop(ops[0], None)
        return regs


def enclosing(starts, addr):
    prev = None
    for s in starts:
        if s > addr:
            break
        prev = s
    return prev


def cmd_rects(e):
    for name, b, en in (("A", RECT_A, RECT_A_END), ("B", RECT_B, RECT_B_END)):
        print("== tabela %s: 0x%08x .. 0x%08x (%d registros) ==" %
              (name, b, en, (en - b) // 12))
        for i, r in enumerate(rects(e, b, en)):
            print("  %s[%3d] 0x%08x  u=%4d v=%4d  w=%4d h=%4d   x=%4d y=%4d" %
                  (name, i, r["addr"], r["u"], r["v"], r["w"], r["h"], r["dx"], r["dy"]))
        print()


def cmd_calls(e):
    tr = Tracer(e)
    starts = func_starts(e)
    rows = []
    for tgt, (kind, role) in BUILDERS.items():
        for s in call_sites(e, tgt):
            r = tr.at(s)
            a1, a2, a3 = r.get("$a1"), r.get("$a2"), r.get("$a3")
            rows.append((s, enclosing(starts, s), kind, role, a1, a2, a3))
    rows.sort()
    for s, fn, kind, role, a1, a2, a3 in rows:
        extra = ""
        if a3 is not None:
            cnt = a3 & 0xFF
            if role == "place":
                extra = "cnt=%d base_idx=0x%02x ot=0x%02x" % (cnt, (a3 >> 8) & 0xFF, (a3 >> 16) & 0xFF)
            else:
                extra = "cnt=%d clut_y=%d f=0x%02x lado=%d" % (
                    cnt, (a3 >> 8) & 0xFF, (a3 >> 16) & 0xFF, (a3 >> 24) & 0xFF)
        tb = "tab=0x%08x" % a2 if a2 else "tab=?"
        pb = "prim=0x%08x" % a1 if a1 else "prim=?"
        print("0x%08x  fn=0x%08x  %-8s %-5s  %-16s %-16s %s" %
              (s, fn or 0, kind, role, pb, tb, extra))


def cmd_slots(e):
    print("== 0x%08x: VRAM (x,y) por slot de icone; rect 20 words x 30 linhas (=40x30 px 8bpp) ==" % ICON_SLOT_VRAM)
    print("   13 entradas (0..12). Depois de 0x800a0080 comeca a tabela de posicao do NUMERO.")
    print("   u = (x - base_da_pagina)*2 ; v = y - 256 ; pagina x=640 -> tpage 0x9a, x=448 -> tpage 0x97")
    for i in range(13):
        a = ICON_SLOT_VRAM + i * 4
        x, y = struct.unpack_from("<2H", e.bytes_at(a, 4), 0)
        pg = 640 if x >= 640 else 448
        tp = "0x9a" if pg == 640 else "0x97"
        print("   slot %2d  vram=(%4d,%4d)  tpage %s  u=%3d v=%3d" %
              (i, x, y, tp, (x - pg) * 2, y - 256))
    print()
    print("== 0x%08x: tela (x,y) do NUMERO de quantidade por slot (11 entradas) ==" % 0x800A0080)
    for i in range(11):
        a = 0x800A0080 + i * 4
        x, y = struct.unpack_from("<2H", e.bytes_at(a, 4), 0)
        print("   slot %2d  tela=(%4d,%4d)" % (i, x, y))


def cmd_sld(e):
    print("== 0x%08x: offset em ETC/ITEMA.SLD por item_id (u32) ==" % SLD_OFFSETS)
    prev = None
    for i in range(135):
        v = e.u32(SLD_OFFSETS + i * 4)
        d = "" if prev is None else "delta=%d" % (v - prev)
        prev = v
        print("   id %3d  off=%8d  %s" % (i, v, d))


def ecg_tables(e):
    """Devolve (cores, ondas): cores = [(r,g,b,dr,dg,db)] x6, ondas = {endereco: bytes}."""
    cores = [tuple(e.bytes_at(ECG_COR + i * 6, 6)) for i in range(ECG_N_COND)]
    ptrs = [e.u32(ECG_ONDA_PTR + i * 4) for i in range(ECG_N_COND)]
    ondas = {}
    for p in ptrs:
        if p not in ondas:
            ondas[p] = e.bytes_at(p, ECG_ONDA_BYTES)
    return cores, ptrs, ondas


def cmd_ecg(e):
    print("== ECG do painel de condicao (B1 = 0x8009f89c) ==")
    print("   monta   0x%08x  32 x LINE_F2 code 0x42 (semitrans) em 0x%08x" % (ECG_MONTA, ECG_BUFFER))
    print("   desenha 0x%08x  x = base.x + %d + k   y = base.y + %d + onda[k]" %
          (ECG_DESENHA, ECG_X, ECG_Y))
    print("   guarda  0 <= k < 0x%02x (%d colunas)   fase de -0x20 a 0x%02x-1 = %d quadros" %
          (ECG_K_LIMITE, ECG_K_LIMITE, ECG_FASE_FIM, ECG_FASE_FIM + 0x20))
    print()
    cores, ptrs, ondas = ecg_tables(e)
    nomes = ["FINE", "CAUTION", "CAUTION2", "DANGER", "POISON", "VIRUS"]
    print("== 0x%08x: cor do rastro (base r,g,b + decaimento dr,dg,db) ==" % ECG_COR)
    for i, c in enumerate(cores):
        print("   cond %d %-9s base=(%3d,%3d,%3d) delta=(%3d,%3d,%3d)  cauda(i=0)=(%3d,%3d,%3d)"
              % (i, nomes[i], c[0], c[1], c[2], c[3], c[4], c[5],
                 c[0] - c[3] * 31, c[1] - c[4] * 31, c[2] - c[5] * 31))
    print()
    print("== 0x%08x: ponteiro da forma de onda por condicao ==" % ECG_ONDA_PTR)
    for i, p in enumerate(ptrs):
        print("   cond %d %-9s -> 0x%08x" % (i, nomes[i], p))
    print()
    for p in sorted(ondas):
        w = ondas[p]
        usados = ECG_K_LIMITE
        print("== onda 0x%08x (%d B = %d pares; %d alcancaveis) ==" %
              (p, len(w), len(w) // 2, usados))
        print("   y :", " ".join("%3d" % w[k * 2] for k in range(usados)))
        print("   h :", " ".join("%3d" % w[k * 2 + 1] for k in range(usados)))
        y0 = [ECG_Y + w[k * 2] for k in range(usados)]
        y1 = [ECG_Y + w[k * 2] + w[k * 2 + 1] for k in range(usados)]
        print("   tela: x %d..%d   y %d..%d   (linha de base y=%d)" %
              (ECG_X, ECG_X + usados - 1, min(y0), max(y1), ECG_Y + w[0]))
        print("   hex :", w.hex())
        print()


def cmd_json(e, out):
    tr = Tracer(e)
    starts = func_starts(e)
    data = {
        "ctx": CTX, "task_entry": TASK_ENTRY,
        "state_handlers": [e.u32(STATE_TABLE + i * 4) for i in range(14)],
        "mode_init_labels": [e.u32(MODE_JUMP_INIT + i * 4) for i in range(6)],
        "mode_draw_labels": [e.u32(MODE_JUMP_DRAW + i * 4) for i in range(6)],
        "rect_a": rects(e, RECT_A, RECT_A_END),
        "rect_b": rects(e, RECT_B, RECT_B_END),
        "icon_slot_vram": [list(struct.unpack_from("<2H", e.bytes_at(ICON_SLOT_VRAM + i * 4, 4), 0))
                           for i in range(20)],
        "sld_offsets": [e.u32(SLD_OFFSETS + i * 4) for i in range(135)],
        "calls": [],
    }
    cores, ptrs, ondas = ecg_tables(e)
    data["ecg"] = {
        "monta": ECG_MONTA, "desenha": ECG_DESENHA, "buffer": ECG_BUFFER,
        "n_colunas": 32, "n_colunas_flash": 28,
        "x_origem": ECG_X, "y_origem": ECG_Y, "k_limite": ECG_K_LIMITE,
        "fase_fim": ECG_FASE_FIM, "fase_inicio": -0x20,
        "cor": [list(c) for c in cores],
        "onda_ptr": ptrs,
        "onda": {"0x%08x" % p: ondas[p].hex() for p in sorted(ondas)},
    }
    for tgt, (kind, role) in BUILDERS.items():
        for s in call_sites(e, tgt):
            r = tr.at(s)
            data["calls"].append(dict(site=s, helper=tgt, kind=kind, role=role,
                                      fn=enclosing(starts, s),
                                      a1=r.get("$a1"), a2=r.get("$a2"), a3=r.get("$a3")))
    data["calls"].sort(key=lambda c: c["site"])
    json.dump(data, open(out, "w"), indent=1)
    print("escrito", out)


if __name__ == "__main__":
    e = Exe(EXE_PATH)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "rects"
    if cmd == "rects":
        cmd_rects(e)
    elif cmd == "calls":
        cmd_calls(e)
    elif cmd == "slots":
        cmd_slots(e)
    elif cmd == "sld":
        cmd_sld(e)
    elif cmd == "ecg":
        cmd_ecg(e)
    elif cmd == "json":
        cmd_json(e, sys.argv[2])
    else:
        print(__doc__)
