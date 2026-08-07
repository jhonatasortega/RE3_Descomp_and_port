"""Sumariza a maquina de estados do MENU DE JOGO de RE3 (status/inventario),
que mora no EXE principal (nao e overlay).

Ancoras (provadas em docs/decomp/notes/menu_pc_sys.md):
  ctx            = 0x800e01c0     (struct global da tela)
  ctx+0x04 u8    = screen kind (0..5)
  ctx+0x10 u8    = estado   -> tabela 0x800a02f0 (14 handlers)
  ctx+0x11 u8    = subestado-> tabela 0x800a0100 (20 handlers)
  ctx+0x27 u8    = "menu aberto" (task 1 roda enquanto != 0)
  task entry     = 0x8006dfdc ; init = 0x8006d948 ; exit = 0x8006e0a4

Para cada handler/subestado imprime: escritas em ctx+0x10..0x13, ids de ESP
(`0x800746c0`), mascaras de pad lidas, indices de arquivo em `cd_read_file`
e chamadas notaveis. Uso: `python tools/menu_ingame.py`
"""
import sys, os, bisect
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe_fn import Ana
from exe_struct import scan_fn, LOADS, STORES

CTX = 0x800e01c0
STATE_TBL = 0x800a02f0
SUB_TBL = 0x800a0100
PADS = {0x800cc830: 'raw_held', 0x800cc834: 'raw_edge', 0x800cc838: 'rpt',
        0x800cc83c: 'log_held', 0x800cc840: 'log_edge'}
ESP = 0x800746c0
CDREAD = 0x80012818


def summarize(a, start, end, label):
    out = {'esp': [], 'pad': [], 'st': [], 'cd': [], 'calls': []}
    i = a.idx[start]
    while i < len(a.ins) and a.ins[i][0] < end:
        ad, m, o = a.ins[i]
        if m == 'jal':
            t = int(o.strip(), 0)
            ar = a.args(ad)
            if t == ESP:
                out['esp'].append((ad, ar.get('$a0')))
            elif t == CDREAD:
                out['cd'].append((ad, ar.get('$a0')))
            else:
                out['calls'].append(t)
        i += 1
    for ad, m, reg, ea, br, d in scan_fn(a, start, seed={'$a0': CTX}, end=end):
        if ea in PADS:
            j = a.idx[ad]
            mask = None
            for k in range(j + 1, min(j + 4, len(a.ins))):
                if a.ins[k][1] == 'andi':
                    p = a.ins[k][2].split(',')
                    try:
                        mask = int(p[-1], 0)
                    except ValueError:
                        pass
                    break
            out['pad'].append((PADS[ea], mask))
        if m in STORES and CTX + 0x10 <= ea <= CTX + 0x13:
            out['st'].append((ad, ea - CTX))
    return out


def main():
    a = Ana()
    hs = [a.e.u32(STATE_TBL + 4 * i) for i in range(14)]
    ss = [a.e.u32(SUB_TBL + 4 * i) for i in range(20)]
    bounds = sorted(set(a.starts) | set(hs) | set(ss))
    def end_of(f):
        k = bisect.bisect_right(bounds, f)
        return bounds[k] if k < len(bounds) else f + 0x400
    for tag, lst in (('ESTADO', hs), ('SUBESTADO', ss)):
        print('===== %s =====' % tag)
        for i, f in enumerate(lst):
            e = end_of(f)
            s = summarize(a, f, e, '%s %d' % (tag, i))
            print('[%2d] 0x%08x..0x%08x  esp=%s pad=%s st=%s cd=%s' % (
                i, f, e,
                [hex(x[1]) if x[1] is not None else '?' for x in s['esp']],
                ['%s&%s' % (n, hex(mk) if mk is not None else '?') for n, mk in s['pad']],
                ['+0x%02x' % x[1] for x in s['st']],
                [hex(x[1]) if x[1] is not None else '?' for x in s['cd']]))


if __name__ == '__main__':
    main()
