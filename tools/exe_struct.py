"""Rastreador de acessos a um struct global do EXE de RE3.

Propaga constantes de endereco (`lui`/`addiu`/`ori`/`move`) para frente dentro
de uma funcao e reporta todo `lb/lbu/lh/lhu/lw/sb/sh/sw` cujo registrador-base
seja uma constante conhecida. Permite semear registradores na entrada
(ex.: `$a0 = 0x800e01c0` porque os handlers do menu recebem o ctx em a0).

Uso:
    from exe_struct import scan_fn
    for r in scan_fn(ana, 0x8006e424, seed={'$a0':0x800e01c0}):
        print(r)      # (endereco, mnemonico, reg_dest, addr_efetivo, off_no_struct)
"""

LOADS = ('lb','lbu','lh','lhu','lw')
STORES = ('sb','sh','sw')


def scan_fn(ana, fn, seed=None, end=None, follow_jal=False):
    end = end or ana.fn_end(fn)
    st = dict(seed or {})
    st['$zero'] = 0
    out = []
    i = ana.idx[fn]
    while i < len(ana.ins) and ana.ins[i][0] < end:
        ad, m, o = ana.ins[i]
        p = [x.strip() for x in o.split(',')]
        i += 1
        if m in LOADS + STORES and len(p) == 2 and '(' in p[1]:
            disp, reg = p[1].split('(')
            reg = reg.rstrip(')')
            try:
                d = int(disp, 0) if disp else 0
            except ValueError:
                d = None
            if reg in st and d is not None:
                out.append((ad, m, p[0], (st[reg] + d) & 0xffffffff, reg, d))
            if m in LOADS:
                st.pop(p[0], None)
            continue
        if not p or not p[0].startswith('$'):
            continue
        dst = p[0]
        try:
            if m == 'lui' and len(p) == 2:
                st[dst] = int(p[1], 0) << 16
            elif m == 'addiu' and len(p) == 3 and p[1] in st:
                v = int(p[2], 0)
                st[dst] = (st[p[1]] + (v if v < 0x8000 else v - 0x10000)) & 0xffffffff
            elif m == 'ori' and len(p) == 3 and p[1] in st:
                st[dst] = st[p[1]] | int(p[2], 0)
            elif m == 'move' and len(p) == 2:
                if p[1] in st: st[dst] = st[p[1]]
                else: st.pop(dst, None)
            elif m in ('jal', 'jalr', 'nop', 'j', 'b'):
                if m in ('jal', 'jalr'):
                    for r in ('$a0','$a1','$a2','$a3','$v0','$v1','$t0','$t1','$t2','$t3',
                              '$t4','$t5','$t6','$t7','$t8','$t9','$at'):
                        st.pop(r, None)
            else:
                st.pop(dst, None)
        except ValueError:
            st.pop(dst, None)
    return out
