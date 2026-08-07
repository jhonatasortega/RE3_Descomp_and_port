"""Utilitario de analise de funcoes do EXE de RE3 (SLUS_009.23).

Descobre inicios de funcao (`addiu $sp,$sp,-N`), monta o grafo de `jal`,
rastreia imediatos constantes em `$a0..$a3`/`$v0` por varredura linear
(reconstruindo `lui`+`addiu`/`ori`) e resolve tabelas de `switch`
(`sltiu` limite + `lw` de tabela + `jr`).

Uso como biblioteca:
    from exe_fn import Ana
    a = Ana()
    a.fn_of(0x8006d7f8)      -> inicio da funcao que contem o endereco
    a.callers(0x8006d700)    -> [(sitio, funcao_chamadora), ...]
    a.calls_in(fn)           -> [(sitio, alvo, args_constantes), ...]
    a.dump(0x8006d700, 60)   -> imprime desmontagem anotada
"""
import sys, os, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe_parse import Exe

EXE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   'extracted', 'ntsc-u', 'SLUS_009.23')

REGS = ('$a0','$a1','$a2','$a3','$v0','$v1','$s0','$s1','$s2','$s3','$t0','$t1','$t2')


class Ana:
    def __init__(self, path=EXE):
        self.e = Exe(path)
        self.ins = self.e.disasm_all()
        self.idx = {a: i for i, (a, m, o) in enumerate(self.ins)}
        self.starts = sorted(a for a, m, o in self.ins
                             if m == 'addiu' and o.replace(' ', '').startswith('$sp,$sp,-'))
        self._jal = None

    # ---------- funcoes ----------
    def fn_of(self, addr):
        import bisect
        i = bisect.bisect_right(self.starts, addr) - 1
        return self.starts[i] if i >= 0 else None

    def fn_end(self, fn):
        """Primeiro `jr $ra` seguido do epilogo, a partir de fn."""
        i = self.idx[fn]
        last = fn
        while i < len(self.ins):
            a, m, o = self.ins[i]
            if a != fn and a in self.starts:
                return last
            if m == 'jr' and o.strip() == '$ra':
                last = a + 8
            i += 1
        return last

    # ---------- grafo de jal ----------
    @property
    def jal(self):
        if self._jal is None:
            d = {}
            for a, m, o in self.ins:
                if m in ('jal',):
                    t = int(o.strip(), 0)
                    d.setdefault(t, []).append(a)
            self._jal = d
        return self._jal

    def callers(self, target):
        return [(s, self.fn_of(s)) for s in self.jal.get(target, [])]

    def calls_in(self, fn, end=None):
        end = end or self.fn_end(fn)
        out = []
        i = self.idx[fn]
        while i < len(self.ins) and self.ins[i][0] < end:
            a, m, o = self.ins[i]
            if m in ('jal', 'jalr'):
                out.append((a, (int(o.strip(), 0) if m == 'jal' else o.strip()),
                            self.args(a)))
            i += 1
        return out

    # ---------- rastreio de imediatos ----------
    def args(self, call_addr, back=32):
        """Varre linearmente de (call-back) ate o delay slot, reconstruindo li/lui+addiu."""
        i = self.idx[call_addr]
        st = {}
        for j in range(max(0, i - back), i + 2):
            a, m, o = self.ins[j]
            p = [x.strip() for x in o.split(',')]
            if not p or not p[0].startswith('$'):
                continue
            d = p[0]
            try:
                if m == 'lui' and len(p) == 2:
                    st[d] = int(p[1], 0) << 16
                elif m == 'addiu' and len(p) == 3 and p[1] == '$zero':
                    st[d] = int(p[2], 0) & 0xffffffff
                elif m in ('ori', 'addiu') and len(p) == 3 and p[1] in st:
                    v = int(p[2], 0)
                    if m == 'ori':
                        st[d] = st[p[1]] | v
                    else:
                        st[d] = (st[p[1]] + (v if v < 0x8000 else v - 0x10000)) & 0xffffffff
                elif m == 'move' and len(p) == 2:
                    if p[1] in st: st[d] = st[p[1]]
                    elif p[1] == '$zero': st[d] = 0
                    else: st.pop(d, None)
                else:
                    st.pop(d, None)
            except ValueError:
                st.pop(d, None)
        return {k: st[k] for k in ('$a0', '$a1', '$a2', '$a3') if k in st}

    # ---------- switch ----------
    def switches(self, lo=None, hi=None):
        """Acha (jr, bound, endereco_da_tabela, [labels])."""
        out = []
        for i, (a, m, o) in enumerate(self.ins):
            if m != 'jr' or o.strip() == '$ra':
                continue
            if lo and not (lo <= a < hi):
                continue
            reg = o.strip()
            bound = tbl = None
            base = off = None
            for j in range(i - 1, max(0, i - 14), -1):
                b, m2, o2 = self.ins[j]
                p = [x.strip() for x in o2.split(',')]
                if m2 == 'sltiu' and bound is None and len(p) == 3:
                    try: bound = int(p[2], 0)
                    except ValueError: pass
                if m2 == 'lw' and p and p[0] == reg and tbl is None:
                    mm = p[1]
                    if '(' in mm:
                        d = mm.split('(')[0]
                        r = mm.split('(')[1].rstrip(')')
                        try: off = int(d, 0) if d else 0
                        except ValueError: off = None
                        # procura lui do registrador r
                        for k in range(j - 1, max(0, j - 12), -1):
                            c, m3, o3 = self.ins[k]
                            p3 = [x.strip() for x in o3.split(',')]
                            if p3 and p3[0] == r and m3 == 'lui':
                                base = int(p3[1], 0) << 16
                                break
                            if p3 and p3[0] == r and m3 == 'addiu' and len(p3) == 3 and p3[1] != r:
                                for k2 in range(k - 1, max(0, k - 8), -1):
                                    c2, m4, o4 = self.ins[k2]
                                    p4 = [x.strip() for x in o4.split(',')]
                                    if p4 and p4[0] == p3[1] and m4 == 'lui':
                                        base = (int(p4[1], 0) << 16)
                                        off = (off or 0) + (int(p3[2], 0) if int(p3[2], 0) < 0x8000
                                                            else int(p3[2], 0) - 0x10000)
                                        break
                                break
                        if base is not None:
                            tbl = (base + (off or 0)) & 0xffffffff
            labels = []
            if tbl and bound and bound < 64 and self.e.valid_vaddr(tbl):
                for k in range(bound):
                    labels.append(self.e.u32(tbl + 4 * k))
            out.append((a, bound, tbl, labels))
        return out

    def dump(self, addr, n=40):
        for a, m, o in self.e.disasm(addr, n):
            print('%08x  %-9s %s' % (a, m, o))


if __name__ == '__main__':
    a = Ana()
    print('funcoes detectadas:', len(a.starts))
