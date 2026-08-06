#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Localiza, isola, cataloga e DESMONTA o overlay de IA de inimigo do RE3 (PS1, SLUS_009.23).

DESCOBERTA (docs/decomp/notes/exe_ai.md §5.6): a "arvore de decisao por-classe" do inimigo
(handlers chamados por gs+0x3de0[char+0x4a-0x10] no loop de chars 0x80023e00) NAO esta no EXE
principal (0x80100000+ fica alem de vend=0x800e3800). Ela vive num OVERLAY de CODIGO MIPS
EMBUTIDO como um BLOCO do arquivo de sala CD_DATA/STAGE#/R###.BIN (rotulado "VRAM" em
enemy_bin.md porque o tag nao tem high-byte 0x80/0x81 — mas o low16 do tag = 0x0001 (codigo) /
0x0002 (par), e o conteudo e' MIPS puro NAO comprimido, pre-relocado p/ base 0x80100000).

ARQUITETURA (provada, §5.6):
  * gs+0x3fa0 (init estatica 0x80017adc) e' um MAPA GLOBAL class->offset-de-bloco: agrupa as
    classes 0x10..0x40 em ~17 "familias" de handler (ex.: classes 16-21,23 -> overlay+0x254;
    24-31 -> +0x1ec; 32 -> +0x30; ...). Cada overlay de um TIPO de inimigo poe o handler daquela
    familia no offset designado. => as familias que sao PROLOGO num overlay = as classes que ele serve.
  * dispatch: 0x80023ea8 (per-frame) / 0x80049b08 (room-load): jalr *(gs+0x3de0[class-0x10]); a0=char.
  * o handler de CLASSE (per-frame) despacha por char+0x04 (acao, 5 valores) via uma tabela de
    rotina (ex. overlay+0xc8e8); cada rotina despacha por char+0x06/+0x18 (sub-estado) via
    sub-tabelas -> handlers-folha (idle/andar/perseguir/atacar/dano/morte).
  * carga em RAM: primario -> 0x80100000; secundario -> memcpy 0x800100a4 p/ 0x8010d000 (loader
    de char 0x8001760c, src = secao [s3+8] do modelo).

Uso:
    python tools/overlay_ai.py scan                     # lista blocos de codigo por sala
    python tools/overlay_ai.py catalog [--json ARQ]     # overlays UNICOS + salas + familias + handlers
    python tools/overlay_ai.py info   <R###.BIN> <blk>  # header + tabela +0x14
    python tools/overlay_ai.py handlers <R###.BIN> <blk># enumera+fingerprint TODOS os handlers
    python tools/overlay_ai.py tree   <R###.BIN> <blk>  # maquina de estados (classe->acao->folha) c/ prosa
    python tools/overlay_ai.py dis    <R###.BIN> <blk> <off_hex> [n]
    python tools/overlay_ai.py helpers <R###.BIN> <blk>
"""
import sys, struct, glob, os, hashlib, json
from collections import Counter, OrderedDict

OVL_BASE = 0x80100000
EXE_LO, EXE_HI = 0x80010000, 0x800e3800
OVL_LO = 0x80100000

# helpers de IA conhecidos no EXE (exe_ai.md)
KNOWN = {
    0x800102e8: "rand",        0x8001b35c: "MOVE_DRV",     0x8001b894: "motion_trig",
    0x8001808c: "ratan2",      0x800445c8: "auto_lock",    0x80044804: "dmg_scan_A",
    0x80047860: "dmg_scan_B",  0x800472ec: "contact",      0x8001b484: "spawn_obj",
    0x80018110: "anim_setpos", 0x800187cc: "anim_play",    0x8001b148: "obj_init",
    0x80049ba8: "obj_scan",    0x80026be8: "emr_interp",
}

# offsets de "familia" no mapa global gs+0x3fa0 (docs §5.6). class-groups -> offset.
FAMILY_OFFS = [0x04, 0x1c, 0x20, 0x30, 0x3c, 0xac, 0xbc, 0xc4, 0xc8, 0xd4,
               0xf8, 0x144, 0x14c, 0x154, 0x180, 0x1ec, 0x254]
# class -> family offset (reconstruido da init estatica 0x80017adc, row0)
CLASS_FAMILY = {
    16: 0x254, 17: 0x254, 18: 0x254, 19: 0x254, 20: 0x254, 21: 0x254, 23: 0x254,
    22: 0x1ec, 24: 0x1ec, 25: 0x1ec, 26: 0x1ec, 27: 0x1ec, 28: 0x1ec, 29: 0x1ec,
    30: 0x1ec, 31: 0x1ec, 32: 0x30, 33: 0x14c, 34: 0xbc, 35: 0x144, 36: 0xbc,
    37: 0xc8, 38: 0x1c, 39: 0x1c, 40: 0x144, 44: 0x1c, 45: 0x20, 46: 0x254,
    47: 0x254, 48: 0xac, 50: 0xc4, 51: 0xd4, 52: 0x180, 53: 0x180, 54: 0xf8,
    55: 0x3c, 56: 0x154, 57: 0x04, 58: 0xf8, 59: 0x3c, 62: 0x20, 63: 0x20, 64: 0x04,
}

# campos do char-struct relevantes p/ a maquina de estados (exe_ai.md / exe_combat.md)
CHAR_FIELDS = {
    0x04: "action", 0x05: "routine", 0x06: "substate", 0x18: "ai_state",
    0xc8: "anim_seq", 0xc9: "anim_frame", 0xcc: "HP", 0x110: "pose/anim_ptr",
    0xb8: "hurt_timer", 0xba: "dir_angle", 0x46: "weapon/flags", 0x4a: "class",
    0x1e4: "timer", 0x1ed: "timer", 0x1f2: "timer", 0x1fb: "timer", 0x12d: "flash/ammo",
}

_MD = None
def _md():
    global _MD
    if _MD is None:
        import capstone
        _MD = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
        _MD.detail = True
    return _MD


def read_blocks(fn):
    d = open(fn, "rb").read()
    fsz, bc = struct.unpack("<II", d[:8])
    ent = [struct.unpack("<II", d[8 + i * 8:16 + i * 8]) for i in range(bc)]
    off, out = 0x800, []
    for i, (sz, tag) in enumerate(ent):
        out.append((i, tag, off, sz, d[off:off + sz]))
        off = (off + sz + 0x7ff) & ~0x7ff
    return out


def u32(buf, o):
    return struct.unpack("<I", buf[o:o + 4])[0]


def code_score(buf):
    je = jo = lu = 0
    for i in range(0, len(buf) - 4, 4):
        w = u32(buf, i); op = w >> 26
        if op == 3:
            t = ((w & 0x3ffffff) << 2) | 0x80000000
            if EXE_LO <= t < EXE_HI: je += 1
            elif OVL_LO <= t < OVL_LO + len(buf): jo += 1
        elif op == 0x0f and (w & 0xffff) == 0x8010:
            lu += 1
    return je, jo, lu


def is_code_block(buf):
    je, jo, lu = code_score(buf)
    return je > 200 and (jo > 0 or lu > 0)


def entropy(buf):
    import math
    c = Counter(buf); n = len(buf) or 1
    return -sum((v / n) * math.log2(v / n) for v in c.values())


def is_prologue(buf, off):
    if off < 0 or off + 4 > len(buf): return False
    w = u32(buf, off)
    return (w >> 26) == 9 and ((w >> 21) & 31) == 29 and ((w >> 16) & 31) == 29 and (w & 0x8000)


def families_present(buf):
    """Offsets de familia que sao prologo neste overlay = classes servidas."""
    return [o for o in FAMILY_OFFS if is_prologue(buf, o)]


def classes_for_families(fams):
    fset = set(fams)
    return sorted(c for c, o in CLASS_FAMILY.items() if o in fset)


def find_ptr_tables(buf):
    """Corridas de >=3 words consecutivos apontando p/ a regiao de codigo do overlay."""
    N = len(buf); runs = []; cur = []; start = 0
    for o in range(0, N - 4, 4):
        v = u32(buf, o)
        if OVL_BASE + 0x254 <= v < OVL_BASE + N:
            if not cur: start = o
            cur.append(v)
        else:
            if len(cur) >= 3: runs.append((start, cur))
            cur = []
    if len(cur) >= 3: runs.append((start, cur))
    return runs


def func_bounds(buf, off):
    """Desmonta ate jr $ra (inclui delay slot). Retorna lista de (addr,mnem,ops)."""
    md = _md(); out = []
    for ins in md.disasm(buf[off:off + 2000 * 4], OVL_BASE + off):
        out.append((ins.address, ins.mnemonic, ins.op_str))
        if ins.mnemonic == "jr" and ins.op_str.strip() == "$ra":
            break
    return out


# classificacao COARSE de helpers do EXE por faixa de endereco (.text do SLUS_009.23)
def exe_region(addr):
    if 0x800102e0 <= addr < 0x80010300: return "RNG"
    if 0x80074000 <= addr < 0x80075000 or 0x80080000 <= addr < 0x80089000: return "GEOM"   # GTE/vetor/matriz
    if (0x80016000 <= addr < 0x80016c00 or 0x80018000 <= addr < 0x8001a200
            or 0x80026000 <= addr < 0x80028800): return "ANIM"                             # anim/pose/EMR/evento
    if 0x8001a200 <= addr < 0x8001c800: return "MOVE"                                       # locomocao/colisao
    if 0x8004c000 <= addr < 0x80053000: return "COLL"                                       # colisao de geometria
    if 0x80038000 <= addr < 0x80046000: return "THINK"                                      # think/combate/dano
    return None

REGION_DESC = {
    "RNG": "RNG", "GEOM": "matematica GTE/vetorial (dist/angulo/projecao)",
    "ANIM": "anim/pose/EMR/evento de anim", "MOVE": "locomocao/colisao do corpo",
    "COLL": "colisao com a geometria da sala", "THINK": "rotina de think/combate do EXE",
}
HELPER_DESC = {
    "rand": "rola dado (decisao aleatoria)", "MOVE_DRV": "aplica locomocao/colisao",
    "motion_trig": "dispara motion/anim/sfx", "ratan2": "calcula angulo p/ o alvo",
    "auto_lock": "oferece hitbox ao auto-lock do player",
    "contact": "testa contato corpo-a-corpo com o player",
    "dmg_scan_A": "varre chars e aplica dano (ataque)", "dmg_scan_B": "2a varredura de dano",
    "spawn_obj": "cria objeto (projetil/parte/efeito)", "anim_setpos": "posiciona/inicia anim",
    "anim_play": "toca sequencia de anim", "obj_init": "inicializa objeto",
    "emr_interp": "interpola esqueleto/EMR (pose)",
}
STATE_FIELDS = {0x04: "action", 0x05: "routine", 0x06: "substate", 0x18: "ai_state"}
POS_OFFS = {0x1c, 0x20, 0x24, 0x2c, 0x34, 0x3c, 0x40}   # componentes de posicao 3D do char


def fingerprint(buf, off):
    """Analise ESTATICA profunda de um handler: aliasing de reg p/ char/globais, helpers
    (exatos + por faixa), contadores, comparacoes, e atribuicao de PAPEL concreto."""
    md = _md()
    ins = list(md.disasm(buf[off:off + 800 * 4], OVL_BASE + off))
    # convencao do overlay: leaves recebem char em $s0/$s1 (setados pelo class-entry);
    # o class-entry faz move $s0,$a0. Seed com os 3 candidatos.
    char_regs = {"$a0", "$s0", "$s1"}; abs_regs = {}
    writes = OrderedDict(); read_offs = set(); write_offs = set()
    helpers = Counter(); regions = Counter(); ovl_calls = 0
    globs = set(); transitions = []
    uses_rand = has_cmp = has_incdec = reads_pos = jr_dispatch = 0
    nins = 0
    for x in ins:
        nins += 1
        m = x.mnemonic; ops = [o.strip() for o in x.op_str.split(",")]
        if m == "jr" and x.op_str.strip() == "$ra":
            break
        if m == "jr":                       # jr $vX = salto indexado (tail sub-dispatch)
            jr_dispatch = 1; break
        if m == "jalr":                     # jalr $vX = chamada indireta via tabela (sub-dispatch)
            jr_dispatch = 1
        if m in ("slti", "sltiu", "slt", "sltu"):
            has_cmp = 1
        if m == "jal" and x.op_str:
            try: t = int(x.op_str, 0)
            except: t = 0
            if EXE_LO <= t < EXE_HI:
                nm = KNOWN.get(t)
                if nm:
                    helpers[nm] += 1
                    if nm == "rand": uses_rand = 1
                else:
                    reg = exe_region(t)
                    if reg == "RNG": uses_rand = 1; helpers["rand"] += 1
                    elif reg: regions[reg] += 1
                    else: helpers["%08x" % t] += 1
            elif OVL_LO <= t < OVL_LO + len(buf):
                ovl_calls += 1
            continue
        # aliasing de registradores p/ char (a0) e p/ enderecos absolutos (lui+lo)
        if m == "move" and len(ops) == 2:
            if ops[1] in char_regs: char_regs.add(ops[0])
            else: char_regs.discard(ops[0])
            abs_regs.pop(ops[0], None)
        elif m == "lui":
            abs_regs[ops[0]] = int(ops[1], 0) << 16; char_regs.discard(ops[0])
        elif m == "addiu" and len(ops) == 3 and ops[1] in abs_regs:
            abs_regs[ops[0]] = (abs_regs[ops[1]] + int(ops[2], 0)) & 0xffffffff; char_regs.discard(ops[0])
        elif m in ("sb", "sh", "sw", "lbu", "lhu", "lw", "lb", "lh") and "(" in x.op_str:
            part = x.op_str.split(",", 1)[1].strip()
            try: foff = int(part.split("(")[0] or "0", 0)
            except: foff = None
            breg = part.split("(")[1].rstrip(")")
            store = m in ("sb", "sh", "sw")
            if foff is not None and breg in char_regs and 0 <= foff < 0x200:
                if store:
                    nm = CHAR_FIELDS.get(foff, "+0x%x" % foff)
                    writes[nm] = writes.get(nm, 0) + 1; write_offs.add(foff)
                    if foff in STATE_FIELDS: transitions.append(STATE_FIELDS[foff])
                else:
                    read_offs.add(foff)
                    if foff in POS_OFFS: reads_pos = 1
            elif foff is not None and breg in abs_regs:
                ga = (abs_regs[breg] + foff) & 0xffffffff
                rel = ga - 0x800ca738
                if 0 <= rel < 0x8000: globs.add("gs+0x%x" % rel)
                elif ga == 0x800cc83c: globs.add("pad")
            if not store: char_regs.discard(ops[0]); abs_regs.pop(ops[0], None)
        elif m == "addiu" and len(ops) == 3:
            # incremento/decremento pequeno (candidato a contador/timer)
            try:
                if 0 < abs(int(ops[2], 0)) <= 8: has_incdec = 1
            except Exception:
                pass
            char_regs.discard(ops[0]); abs_regs.pop(ops[0], None)
        else:
            if ops and ops[0].startswith("$"):
                char_regs.discard(ops[0]); abs_regs.pop(ops[0], None)

    reads = sorted(CHAR_FIELDS.get(f, "+0x%x" % f) for f in read_offs) + sorted(globs)
    counter_offs = sorted(read_offs & write_offs)
    is_entry = off in FAMILY_OFFS
    role, sem = _classify(off, is_entry, writes, write_offs, read_offs, reads, helpers,
                          regions, ovl_calls, globs, transitions, counter_offs,
                          uses_rand, has_cmp, has_incdec, reads_pos, nins, jr_dispatch)
    return {
        "off": "0x%x" % off, "addr": "0x%08x" % (OVL_BASE + off), "n_ins": nins,
        "role": role, "writes": dict(writes), "helpers": dict(helpers),
        "regions": dict(regions), "ovl_calls": ovl_calls,
        "transitions": list(dict.fromkeys(transitions)), "reads": reads,
        "counters": ["+0x%x" % o for o in counter_offs], "semantics": sem,
    }


def _fld(o):
    return CHAR_FIELDS.get(o, "+0x%x" % o) if isinstance(o, int) else o


def _classify(off, is_entry, W, woffs, roffs, reads, H, regions, ovl_calls, globs,
              transitions, counters, uses_rand, has_cmp, has_incdec, reads_pos, nins, jr_dispatch=0):
    """Retorna (role, semantics) — prosa HONESTA derivada dos fatos. [incerto] so quando
    genuinamente indeterminavel estaticamente, e nesse caso diz EXATAMENTE o que falta."""
    hs = set(H); rg = set(regions)
    gate = "gs+0x77f4" in globs
    reads_player = any(g in globs for g in ("gs+0x2660", "gs+0x2664", "gs+0x24c0", "gs+0x24c8", "gs+0x248c"))
    tset = list(dict.fromkeys(transitions))
    trans = ("; transiciona " + "/".join("char+0x%02x(%s)" % (
        {"action": 4, "routine": 5, "substate": 6, "ai_state": 0x18}[t], t) for t in tset)) if tset else ""

    if is_entry:
        return ("CLASS-ENTRY", "handler de CLASSE (per-frame): decrementa timers, checa gate de boss "
                "gs+0x77f4 e despacha por char+0x04 (acao)")
    if jr_dispatch and not W and not H and not regions:
        idx = sorted(_fld(o) for o in roffs) or list(globs)
        return ("SUB-DISPATCH", "SUB-DISPATCH: le %s e SALTA (jr) p/ sub-handler via tabela" % (
            ", ".join(idx[:3]) if idx else "campo de estado"))
    if "contact" in hs or "dmg_scan_A" in hs or "dmg_scan_B" in hs:
        return ("ATTACK", "ATAQUE: testa contato/dano ao player (hitbox)%s" % trans)
    if "spawn_obj" in hs:
        return ("SPAWN", "SPAWN: cria objeto (projetil/parte/hitbox de ataque/efeito)%s%s" % (
            ("; seta anim char+0xc8" if "anim_seq" in W else ""), trans))
    if "ratan2" in hs or ("GEOM" in rg and reads_player):
        return ("AIM/GEOM", "GEOMETRIA: calcula distancia/angulo ao alvo (%s) e ajusta rumo%s" % (
            "ratan2" if "ratan2" in hs else "GTE", trans))
    if "MOVE_DRV" in hs or "MOVE" in rg or (reads_pos and woffs & POS_OFFS):
        return ("MOVE", "LOCOMOCAO: desloca o corpo com colisao (integra posicao)%s" % trans)
    if "COLL" in rg:
        return ("COLLISION", "COLISAO: testa o corpo contra a geometria da sala%s" % trans)
    anim = ("anim_seq" in W or "pose/anim_ptr" in W or "ANIM" in rg
            or any(h in hs for h in ("anim_play", "anim_setpos", "emr_interp", "motion_trig")))
    if anim and uses_rand:
        return ("IDLE/DECIDE", "IDLE/DECISAO: rola dado, seta anim (char+0xc8) e escolhe proxima acao%s" % trans)
    if "HP" in reads or "gs+0x77f4" in globs and ("+0xd2" in reads or "+0xda" in reads):
        return ("DEATH/DAMAGE", "DANO/MORTE: le HP/flags de status e reage (stagger/morte)%s" % trans)
    if anim:
        return ("ANIM/STATE", "ANIM/ESTADO: ajusta animacao/pose (char+0xc8)%s" % trans)
    if tset:
        return ("STATE-SET", "TRANSICAO de estado%s" % trans.replace("; transiciona", ": escreve"))
    if counters or (has_incdec and woffs and (woffs & roffs)):
        c = counters or sorted(woffs & roffs)
        return ("TIMER", "CONTADOR/TIMER: incrementa/decrementa e compara %s" % ", ".join(_fld(o) for o in c))
    if uses_rand and has_cmp:
        return ("CHANCE", "CHANCE: rola dado (rand) e ramifica por limiar")
    if not W and not H and not regions and not ovl_calls and (roffs or globs) and has_cmp:
        return ("PREDICATE", "PREDICADO/GETTER: le %s e ramifica (retorna decisao ao chamador)" % (
            ", ".join(sorted(_fld(o) for o in list(roffs)[:4])) or "campos do char"))
    if ovl_calls and not W and not H:
        return ("DELEGATE", "DELEGA: chama %d sub-rotina(s) interna(s) do overlay (dispatcher/wrapper)" % ovl_calls)
    if regions and not W:
        rl = ", ".join(REGION_DESC[r] for r in regions)
        return ("EXE-CALL", "chama rotina(s) do EXE: %s" % rl)
    # writes com sinal fraco
    if W:
        flds = ", ".join("%s" % k for k in W)
        if has_cmp or roffs:
            return ("FIELD-SET", "ajusta campo(s) char %s (condicional)" % flds)
        return ("FIELD-SET", "grava campo(s) char %s (valor imediato)" % flds)
    if regions or H:
        parts = [REGION_DESC[r] for r in regions] + [HELPER_DESC.get(h, "EXE %s" % h) for h in H]
        return ("EXE-CALL", "chama: %s" % "; ".join(dict.fromkeys(parts)))
    # genuinamente indeterminavel
    reason = "sem escrita/helper/comparacao observaveis"
    if globs: reason = "so le globais (%s) sem efeito local observavel" % ", ".join(sorted(globs)[:3])
    return ("?", "sub-rotina utilitaria (%d ins): %s — papel exato requer contexto de chamada/runtime  [incerto]" % (nins, reason))


def find_dispatch(buf, off):
    """Acha despachos `tbl[char+F]` dentro de uma funcao: retorna [(site, table_off, char_field)]."""
    md = _md()
    ins = list(md.disasm(buf[off:off + 800 * 4], OVL_BASE + off))
    reg_abs = {}; reg_idx = {}; charfld = {}; disp = []
    for x in ins:
        m = x.mnemonic; ops = [o.strip() for o in x.op_str.split(",")]
        if m == "jr" and x.op_str.strip() == "$ra":
            break
        if m == "lui":
            reg_abs[ops[0]] = int(ops[1], 0) << 16; reg_idx.pop(ops[0], None); charfld.pop(ops[0], None)
        elif m == "addiu" and len(ops) == 3 and ops[1] in reg_abs:
            reg_abs[ops[0]] = (reg_abs[ops[1]] + int(ops[2], 0)) & 0xffffffff
            reg_idx.pop(ops[0], None); charfld.pop(ops[0], None)
        elif m == "sll" and len(ops) == 3 and ops[2] == "2" and ops[1] in charfld:
            reg_idx[ops[0]] = charfld[ops[1]]; reg_abs.pop(ops[0], None)
        elif m == "addu" and len(ops) == 3:
            if ops[1] in reg_idx and ops[2] in reg_abs:
                reg_abs[ops[0]] = reg_abs[ops[2]]; reg_idx[ops[0]] = reg_idx[ops[1]]
            elif ops[2] in reg_idx and ops[1] in reg_abs:
                reg_abs[ops[0]] = reg_abs[ops[1]]; reg_idx[ops[0]] = reg_idx[ops[2]]
            else:
                reg_abs.pop(ops[0], None); reg_idx.pop(ops[0], None); charfld.pop(ops[0], None)
        elif m == "lw" and "(" in x.op_str:
            part = x.op_str.split(",", 1)[1].strip()
            to = int(part.split("(")[0] or "0", 0); br = part.split("(")[1].rstrip(")")
            if br in reg_idx and br in reg_abs:
                toff = (((reg_abs[br] + to) & 0xffffffff) - OVL_BASE)
                if 0 <= toff < len(buf) - 4:
                    disp.append((x.address, toff, reg_idx[br]))
            else:
                charfld[ops[0]] = to
            reg_abs.pop(ops[0], None); reg_idx.pop(ops[0], None)
        elif m in ("lbu", "lhu", "lb", "lh") and "(" in x.op_str:
            part = x.op_str.split(",", 1)[1].strip()
            charfld[ops[0]] = int(part.split("(")[0] or "0", 0)
            reg_abs.pop(ops[0], None); reg_idx.pop(ops[0], None)
    return disp


def table_targets(buf, table_off, maxn=64, stop_at_stub=False):
    """Le uma tabela de ponteiros ate parar de apontar p/ codigo do overlay.
    stop_at_stub=True para a 1a entrada nula (usado no nivel de ACAO, cujas entradas
    sao contiguas; as sub-tabelas podem ter stubs 0 no meio)."""
    out = []
    o = table_off
    if o < 0:
        return out
    while o + 4 <= len(buf) and len(out) < maxn:
        v = u32(buf, o)
        if v == 0:
            if stop_at_stub:
                break
            out.append(None); o += 4; continue
        fo = v - OVL_BASE
        if not (0x254 <= fo < len(buf)) or not is_prologue(buf, fo):
            break
        out.append(fo); o += 4
    return out


def field_name(f):
    return CHAR_FIELDS.get(f, "+0x%x" % f)


def state_machine(buf, entry_off):
    """Arvore: class-entry -> dispatch(char+F) -> acao -> sub-dispatch -> folhas."""
    efp = fingerprint(buf, entry_off)
    node = {"entry": "0x%08x" % (OVL_BASE + entry_off), "entry_fp": efp}
    disp = find_dispatch(buf, entry_off)
    if not disp:
        node["note"] = "entry sem dispatch por char (folha/linear)"
        return node
    site, tbl, fld = disp[0]
    efp["semantics"] = ("handler de CLASSE (per-frame): decrementa timers do char, checa o gate de "
                        "boss gs+0x77f4, e DESPACHA por %s -> tabela de acoes" % field_name(fld))
    node["dispatch"] = {"table": "0x%08x" % (OVL_BASE + tbl), "index": field_name(fld)}
    acts = []
    for i, ao in enumerate(table_targets(buf, tbl, stop_at_stub=True)):
        if ao is None:
            acts.append({"i": i, "handler": None, "note": "STUB"}); continue
        afp = fingerprint(buf, ao)
        sub = find_dispatch(buf, ao)
        entry = {"i": i, "handler": "0x%08x" % (OVL_BASE + ao),
                 "role": afp["role"], "semantics": afp["semantics"]}
        if sub:
            s2, t2, f2 = sub[0]
            leaves = []
            for j, lo in enumerate(table_targets(buf, t2)):
                if lo is None:
                    leaves.append({"j": j, "handler": None}); continue
                lfp = fingerprint(buf, lo)
                leaves.append({"j": j, "handler": "0x%08x" % (OVL_BASE + lo),
                               "role": lfp["role"], "semantics": lfp["semantics"]})
            entry["sub_dispatch"] = {"table": "0x%08x" % (OVL_BASE + t2),
                                     "index": field_name(f2), "leaves": leaves}
        acts.append(entry)
    node["actions"] = acts
    return node


def enumerate_handlers(buf):
    """Todos os handlers alcancaveis: class-entries + alvos das tabelas de ponteiro. Dedup."""
    targets = set(families_present(buf))
    for start, ptrs in find_ptr_tables(buf):
        for v in ptrs:
            targets.add(v - OVL_BASE)
    handlers = sorted(t for t in targets if is_prologue(buf, t))
    return handlers


# ---------------------------------------------------------------------------

def load_overlay(fn, blk):
    return read_blocks(fn)[blk][4]


def cmd_scan(patt):
    print("== blocos de CODIGO (overlay de IA) em R###.BIN ==\n")
    seen = {}
    for fn in sorted(glob.glob(patt)):
        for i, tag, off, sz, buf in read_blocks(fn):
            if sz >= 4096 and is_code_block(buf):
                h = hashlib.md5(buf).hexdigest()[:8]
                seen.setdefault((sz, h), []).append("%s:blk%d(tag=%08x)" % (os.path.basename(fn), i, tag))
    for (sz, h), rooms in sorted(seen.items(), key=lambda x: -len(x[1])):
        print("  size=%-6d md5=%s  x%d  ex.: %s" % (sz, h, len(rooms), rooms[0]))


def _iter_unique(patt, low16=0x0001):
    uniq = OrderedDict()
    for fn in sorted(glob.glob(patt)):
        for i, tag, off, sz, buf in read_blocks(fn):
            if (tag & 0xffff) == low16 and sz >= 4096 and is_code_block(buf):
                h = hashlib.md5(buf).hexdigest()[:8]
                d = uniq.setdefault((sz, h), {"rooms": [], "buf": buf, "tag": tag})
                d["rooms"].append(os.path.basename(fn)[:-4])
    return uniq


def cmd_catalog(jpath=None):
    uniq = _iter_unique("extracted/ntsc-u/CD_DATA/STAGE*/R*.BIN")
    print("== CATALOGO de overlays de IA UNICOS (tag low16=0x0001, codigo) ==\n")
    out = []
    for (sz, h), d in sorted(uniq.items(), key=lambda x: -len(x[1]["rooms"])):
        buf = d["buf"]
        fams = families_present(buf)
        classes = classes_for_families(fams)
        handlers = enumerate_handlers(buf)
        fps = [fingerprint(buf, o) for o in handlers]
        roles = Counter(f["role"].split(" ")[0] for f in fps)
        print("  sz=%-6d %s x%2d salas | familias=%s | classes=%s | %d handlers" % (
            sz, h, len(d["rooms"]), [hex(x) for x in fams], classes, len(handlers)))
        print("      roles: %s" % dict(roles))
        print("      salas: %s%s" % (", ".join(d["rooms"][:8]), " ..." if len(d["rooms"]) > 8 else ""))
        sms = [state_machine(buf, o) for o in fams]
        out.append(OrderedDict([
            ("size", sz), ("md5", h), ("tag", "0x%08x" % d["tag"]),
            ("n_rooms", len(d["rooms"])), ("rooms", d["rooms"]),
            ("family_offsets", ["0x%x" % x for x in fams]),
            ("classes_served", classes), ("n_handlers", len(handlers)),
            ("state_machines", sms), ("handlers", fps),
        ]))
    print("\n  total de overlays UNICOS de codigo: %d" % len(uniq))
    tot_h = sum(len(o["handlers"]) for o in out)
    print("  total de handlers enumerados/fingerprintados: %d" % tot_h)
    if jpath:
        d = os.path.dirname(jpath)
        if d:
            os.makedirs(d, exist_ok=True)
        json.dump({"note": "RE3 PS1 enemy-AI overlays embedded in STAGE#/R###.BIN; base 0x80100000",
                   "overlays": out}, open(jpath, "w"), indent=1)
        print("  -> JSON: %s" % jpath)


def cmd_info(fn, blk):
    buf = load_overlay(fn, blk)
    je, jo, lu = code_score(buf)
    print("== overlay %s blk%d ==" % (os.path.basename(fn), blk))
    print("  size=%d entropia=%.2f (%s) jal_exe=%d jal_ovl=%d lui8010=%d" % (
        len(buf), entropy(buf), "MIPS nao-comprimido" if entropy(buf) < 6.5 else "?", je, jo, lu))
    print("  header count=%d" % u32(buf, 0))
    s = buf[4:0x14].split(b"\x00")[0]
    if s and all(9 <= c < 127 for c in s):
        print("  fmt-string=%r" % s.decode("ascii", "replace"))
    fams = families_present(buf)
    print("  familias (classes servidas): %s -> classes %s" % (
        [hex(x) for x in fams], classes_for_families(fams)))
    print("  tabela @+0x14:")
    md = _md()
    o = 0x14
    while o + 4 <= len(buf):
        v = u32(buf, o)
        if v and not (OVL_LO <= v < OVL_LO + len(buf)): break
        fo = v - OVL_BASE if v else -1
        txt = "STUB" if v == 0 else " ; ".join(
            "%s %s" % (x.mnemonic, x.op_str) for x in list(md.disasm(buf[fo:fo + 8], v))[:2])
        print("    [%2d] %08x : %s" % ((o - 0x14) // 4, v, txt))
        o += 4


def cmd_handlers(fn, blk):
    buf = load_overlay(fn, blk)
    fams = families_present(buf)
    handlers = enumerate_handlers(buf)
    print("== handlers do overlay %s blk%d ==" % (os.path.basename(fn), blk))
    print("   familias=%s classes=%s | %d handlers-folha (prologos alcancaveis por tabela)\n" % (
        [hex(x) for x in fams], classes_for_families(fams), len(handlers)))
    for o in handlers:
        f = fingerprint(buf, o)
        w = ", ".join("%s(x%d)" % (k, v) for k, v in f["writes"].items()) or "-"
        h = ", ".join("%s(x%d)" % (k, v) for k, v in f["helpers"].items()) or "-"
        print("  %08x [%3d ins] %-32s" % (OVL_BASE + o, f["n_ins"], f["role"]))
        print("      escreve: %s" % w)
        print("      chama  : %s" % h)


def cmd_tree(fn, blk):
    buf = load_overlay(fn, blk)
    fams = families_present(buf)
    print("== maquina de estados do overlay %s blk%d ==" % (os.path.basename(fn), blk))
    print("   familias=%s classes=%s\n" % ([hex(x) for x in fams], classes_for_families(fams)))
    for fo in fams:
        sm = state_machine(buf, fo)
        print("CLASS-ENTRY %s (familia +0x%x -> classes %s)" % (
            sm["entry"], fo, classes_for_families([fo])))
        print("  %s" % sm["entry_fp"]["semantics"])
        if "dispatch" not in sm:
            print("  %s\n" % sm.get("note", "")); continue
        print("  dispatch por %s -> tabela %s:" % (sm["dispatch"]["index"], sm["dispatch"]["table"]))
        for a in sm["actions"]:
            if a["handler"] is None:
                print("    [%d] STUB" % a["i"]); continue
            print("    [%d] %s  %s" % (a["i"], a["handler"], a["semantics"]))
            if "sub_dispatch" in a:
                sd = a["sub_dispatch"]
                print("        sub-dispatch por %s -> %s (%d folhas):" % (
                    sd["index"], sd["table"], len(sd["leaves"])))
                for lf in sd["leaves"]:
                    if lf["handler"] is None:
                        print("          <%d> STUB" % lf["j"]); continue
                    print("          <%d> %s %s" % (lf["j"], lf["handler"], lf["semantics"]))
        print()


def cmd_dis(fn, blk, off, n):
    buf = load_overlay(fn, blk); md = _md()
    for ins in list(md.disasm(buf[off:off + n * 4], OVL_BASE + off))[:n]:
        t = ""
        if ins.mnemonic == "jal":
            try: tt = int(ins.op_str, 0); t = "  ; %s" % KNOWN[tt] if tt in KNOWN else ""
            except: pass
        print("  %08x  %-8s %s%s" % (ins.address, ins.mnemonic, ins.op_str, t))


def cmd_helpers(fn, blk):
    buf = load_overlay(fn, blk); jals = Counter()
    for i in range(0, len(buf) - 4, 4):
        w = u32(buf, i)
        if (w >> 26) == 3:
            t = ((w & 0x3ffffff) << 2) | 0x80000000
            if EXE_LO <= t < EXE_HI: jals[t] += 1
    print("== helpers do EXE chamados (%d distintos) ==" % len(jals))
    for t, c in jals.most_common():
        print("  %08x x%-4d %s" % (t, c, KNOWN.get(t, "")))


if __name__ == "__main__":
    a = sys.argv
    if len(a) >= 2 and a[1] == "scan":
        cmd_scan(a[2] if len(a) > 2 else "extracted/ntsc-u/CD_DATA/STAGE*/R*.BIN")
    elif len(a) >= 2 and a[1] == "catalog":
        jp = a[a.index("--json") + 1] if "--json" in a else None
        cmd_catalog(jp)
    elif len(a) >= 4 and a[1] == "info":
        cmd_info(a[2], int(a[3]))
    elif len(a) >= 4 and a[1] == "handlers":
        cmd_handlers(a[2], int(a[3]))
    elif len(a) >= 4 and a[1] == "tree":
        cmd_tree(a[2], int(a[3]))
    elif len(a) >= 5 and a[1] == "dis":
        cmd_dis(a[2], int(a[3]), int(a[4], 16), int(a[5]) if len(a) > 5 else 40)
    elif len(a) >= 4 and a[1] == "helpers":
        cmd_helpers(a[2], int(a[3]))
    else:
        print(__doc__)
