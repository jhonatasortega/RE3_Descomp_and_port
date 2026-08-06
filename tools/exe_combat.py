#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Analise de COMBATE do player no SLUS_009.23 (RE3 NTSC-U): mira / tiro / dano
e complemento da maquina de estados (routines player+5).

Base ja provada (docs/formatos/exe.md):
  * player-struct base 0x800ccbc4 (deref *(u32*)0x800ccd94)
  * player+0x04 = acao macro (1=on-foot); dispatch 0x80038c7c -> tabela 0x8009cd40
  * player+0x05 = rotina; action1 (0x80039020) -> T1_move 0x8009cd60 / T2_anim 0x8009cda0
  * player+0xc8 = indice de sequencia EDD (0..21); +0xc9 frame; +0xcc = HP (u16, nao "momentum")
  * integrador tank 0x8001a248; pad segurado em player+0x120

Uso:
    python tools/exe_combat.py            # roda o relatorio completo
    python tools/exe_combat.py fn 0x80039020 120   # disasm de uma funcao
    python tools/exe_combat.py scan 0x80039020     # sinais de uma funcao
"""
import sys, re
sys.path.insert(0, "tools")
from exe_parse import Exe

EXE = "extracted/ntsc-u/SLUS_009.23"

# offsets conhecidos do player-struct
PLAYER_FIELDS = {
    0x04: "action", 0x05: "routine", 0x4a: "weapon_state",
    0x6e: "facing_ang", 0xc7: "hit_partid", 0xc8: "anim_seq", 0xc9: "frame",
    0xcc: "HP",  # CORRIGIDO: era rotulado "momentum"; e o HP (u16, max 200) -> exe_combat.md sec 0
    0x108: "pose_tbl", 0x114: "state2", 0x120: "pad_held", 0x121: "pose_cur",
}


def func_end(e, start, maxins=400):
    """Desmonta ate encontrar 'jr $ra' + delay slot (fim de funcao) ou maxins."""
    md = e._md()
    o = e.off(start)
    code = e.text[o:o + maxins * 4]
    out = []
    seen_jr_ra = False
    delay = 0
    for insn in md.disasm(code, start):
        out.append(insn)
        if seen_jr_ra:
            delay += 1
            if delay >= 1:
                break
        if insn.mnemonic == "jr" and insn.op_str.strip() == "$ra":
            seen_jr_ra = True
    return out


def scan_func(e, start, maxins=400):
    """Extrai sinais: escritas em offsets do player, checagens andi (pad),
    stores de constante em 0xc8 (anim), jal/jalr targets, transicoes action/routine."""
    ins = func_end(e, start, maxins)
    sig = {
        "anim_writes": [],   # (addr, offset, value|reg)
        "field_writes": [],  # (addr, mnem, offset, name)
        "andi": [],          # (addr, imm, op_str)  possiveis testes de pad
        "calls": [],         # (addr, target)
        "consts": {},        # reg -> last const (rough)
    }
    # rastreio simples de li/lui-ori p/ resolver stores de constante
    last_const = {}   # reg -> value
    for i in ins:
        m = i.mnemonic; o = i.op_str
        ops = [x.strip() for x in o.split(",")] if o else []
        if m == "li" and len(ops) == 2:
            try: last_const[ops[0]] = int(ops[1], 0)
            except: pass
        elif m == "lui" and len(ops) == 2:
            try: last_const[ops[0]] = (int(ops[1], 0) << 16) & 0xffffffff
            except: pass
        elif m == "ori" and len(ops) == 3:
            b = last_const.get(ops[1])
            try: imm = int(ops[2], 0)
            except: imm = None
            if b is not None and imm is not None:
                last_const[ops[0]] = (b | imm) & 0xffffffff
        elif m == "addiu" and len(ops) == 3 and ops[1] in ("$zero", "$0"):
            try: last_const[ops[0]] = int(ops[2], 0) & 0xffffffff
            except: pass
        # stores em offset(base)
        if m in ("sb", "sh", "sw") and "(" in o:
            mo = re.match(r"(\$\w+),\s*(-?\w+)\((\$\w+)\)", o)
            if mo:
                rt, off, base = mo.group(1), mo.group(2), mo.group(3)
                try: offv = int(off, 0)
                except: offv = None
                if offv is not None:
                    if offv == 0xc8:
                        val = last_const.get(rt)
                        sig["anim_writes"].append((i.address, m, val, rt))
                    if offv in PLAYER_FIELDS or offv in (0x04, 0x05):
                        val = last_const.get(rt)
                        sig["field_writes"].append((i.address, m, offv,
                                                    PLAYER_FIELDS.get(offv, hex(offv)), val))
        if m == "andi" and len(ops) == 3:
            try: imm = int(ops[2], 0)
            except: imm = None
            sig["andi"].append((i.address, imm, o))
        if m in ("jal", "jalr", "j"):
            tgt = ops[-1]
            try:
                tv = int(tgt, 0)
                sig["calls"].append((i.address, m, tv))
            except:
                sig["calls"].append((i.address, m, tgt))
    return sig, ins


def print_scan(e, start):
    sig, ins = scan_func(e, start)
    print("== scan %08x (%d insns) ==" % (start, len(ins)))
    if sig["anim_writes"]:
        print(" anim writes (sb/sh/sw ->0xc8):")
        for a, m, v, rt in sig["anim_writes"]:
            print("   %08x %s %s = %s" % (a, m, rt, hex(v) if v is not None else "?"))
    if sig["field_writes"]:
        print(" field writes:")
        for a, m, off, name, v in sig["field_writes"]:
            print("   %08x %s +%#x(%s) = %s" % (a, m, off, name, hex(v) if v is not None else "?"))
    if sig["andi"]:
        print(" andi (testes de bits/pad):")
        for a, imm, o in sig["andi"]:
            print("   %08x  %s" % (a, o))
    if sig["calls"]:
        print(" calls:")
        for a, m, tv in sig["calls"]:
            print("   %08x %s %s" % (a, m, hex(tv) if isinstance(tv, int) else tv))


# ---------------------------------------------------------------------------
# MAPA de combate (derivado por disassembly + confirmado por GameShark NTSC-U)
# ---------------------------------------------------------------------------
ROUTINES = {
    0:  ("idle/parado",        "anim {2,5,8} por zona de saude; fidgets/anim21", "0x8003910c/0x80039294"),
    1:  ("andar FRENTE",       "anim {0,3,6}; ROTEADOR-MESTRE de input->rotina", "0x8003957c/0x800397dc"),
    2:  ("re / giro-DOWN",     "anim {1,4,7}",                                   "0x80039924/0x80039b84"),
    3:  ("CORRER frente",      "anim 9(parado)/10(mov)",                         "0x80039ccc/0x80039f08"),
    4:  ("frente variante",    "anim {0,3,6} (== r1)",                           "0x8003a398/0x8003a574"),
    5:  ("levantar arma/ready","transicao -> rotina 7 (aim). estado curto",      "0x8003e2a4/0x8003e2ac"),
    6:  ("giro-180 / quickturn","anim {1,4,7}; volta a action1",                 "0x8003a664/0x8003a688"),
    7:  ("MIRAR + ATIRAR",     "sub-estado player+6: 0 raise(a13) 1 pitch 2 aim(a14/auto-lock) 3 hold/fire", "0x8003a7d0/0x8003a7d8"),
    8:  ("?",                  "curto; volta action1",                           "0x8003b078/0x8003b080"),
    9:  ("subir/descer (0x10)","anim 6/7; entrada por flag global &0x10",        "0x8003b1c4/0x8003b244"),
    10: ("andar-FRENTE c/ mira","roteador loco+driver de mira/fogo; anim=linha{0,3,6} (3x3+3). Entra por r1@0x800396a0 / r14@0x8003ba74", "0x8003b4fc/0x8003b784"),
    11: ("transicao (set r12)","seta player+5=0xc (@0x8003c8a4); sub-dispatch proprio por player+7 (tab 0x800107f0); toca gate Nemesis gs+0x77f4|0x100", "0x8003c738/0x8003c740"),
    12: ("anim scriptada 1/2/3","move=STUB(jr ra); anim escreve 0xc8=1/3/2/1. Entra por r11@0x8003c8a4 / acao a4 (evento) @0x80060ad8/0x80060b6c", "0x8003ca80/0x8003ca88"),
    13: ("acao anim 18",       "seta action=0x60501",                           "0x8003ce98/0x8003cea0"),
    14: ("acao anim 9/10",     "",                                              "0x8003b9fc/0x8003bca4"),
    15: ("re/DOWN c/ mira (evento)","roteador loco+driver de mira/fogo; anim=linha{1,4,7} (3x3+6). Entra por r2@0x80039a4c / VM de script 0x8005a9fc,0x8005aa50,0x8005b334,0x8005ba2c,0x8005c354", "0x8003bf28/0x8003c104"),
}
# --- aim_shoot: geometria/hitscan/timing (fechado; ver exe_combat.md sec 1.6/2.5) ---
AIM_HEIGHT_SEL  = 0x8003ac90   # seletor de altura: 15->19/16->20 se player+0xc7 & 0x20 (alvo alto); facing +-0x400
AIM_TIER_PITCH  = 0x8003ac40   # aim_tier(0..3) -> player+0x6e = (tier<<9)+0x800 ; poses 14/15/16 / (17 se tier3)
WPN_FIRE_TBL    = 0x8009ce88   # 16 ptrs: w0=faca 0x8003e494, generico(hitscan) 0x8003eb28, w10=rocket 0x800408c4, w14=granada 0x8003ff9c
WPN_TIMING_TBL  = 0x8009cf28   # 21x3B: byte2&0x7f = frame de disparo (rearme volta a rotina 5)
HITSCAN_A       = 0x80044804   # varredura hitscan (dist-min 0x7fffffff, itera chars gs+0x2664..0x2704)


# ---------------------------------------------------------------------------
# ELO BALA->ALVO + DANO (round 2, este agente) — ver exe_combat.md sec 2.2 / exe_ai.md sec 3
# ---------------------------------------------------------------------------
# CORRECAO ao "negativo" antigo: o TIRO aplica dano sim. Handler de arma
# (0x8009ce88[weapon]) -> ex. handgun 0x8003e4d0 -> ao chegar o frame de disparo
# calcula o ponto do cano e chama DUAS rotinas de dano genericas por VARREDURA:
#   0x80044804 (CONTACT_A) e 0x80047860 (CONTACT_B).
# Cada uma percorre o ARRAY de personagens (0x800ccd9c .. *(0x800cce3c)), acha o
# char mais proximo cuja hitbox cai na linha de tiro e faz  char+0xcc -= dano.
FIRE_DMG_A   = 0x80044804   # varredura de dano A (usada pelo tiro E pelo ataque inimigo)
FIRE_DMG_B   = 0x80047860   # varredura de dano B (o tiro chama as duas)
CHAR_ARRAY   = 0x800ccd9c   # array de ptrs de char-struct (0x1fc B); player = slot0 = 0x800ccbc4
# Tabela de DANO arma-vs-inimigo (dano = *(linha[alvo+0x4a] + (weapon-1)*8) & 0x3ff):
DMG_POSTURE_TBL = 0x8009dbb4  # 16 ptrs por postura (player+0x4a) -> todos 0x8009d934
DMG_WPN_DESC    = 0x8009d934  # descritor por arma (0x20 B; +0x1c -> rowptrs+0x40)
DMG_ROWPTRS     = 0x8009d834  # ptrs-de-linha por classe-do-alvo (alvo+0x4a = 16..48)
DMG_ROW_DEFAULT = 0x8009d0f4  # linha default; use `python tools/exe_ai.py dmg` p/ a matriz completa


def report(e):
    print("== SLUS_009.23  base %08x  vend %08x ==\n" % (e.base, e.vend))
    print("== action table 0x8009cd40 (player+4) ==")
    anames = {0: "idle-macro", 1: "on-foot (loco/mira/tiro)", 2: "hit/melee-connect",
              3: "HURT/dano (sub por +5 em 0x8009ce80)", 4: "evento/objeto especial",
              5: "arma postura B (por +0x4a)", 6: "arma postura C (por +0x4a)", 7: "empurrar/mover objeto"}
    for i in range(8):
        v = e.u32(0x8009cd40 + i * 4)
        print("  a%-2d -> %08x  %s" % (i, v, anames.get(i, "")))
    print("\n== routines (player+5): T1_move 0x8009cd60 / T2_anim 0x8009cda0 ==")
    for i in range(16):
        m = e.u32(0x8009cd60 + i * 4); a = e.u32(0x8009cda0 + i * 4)
        r = ROUTINES.get(i, ("", "", ""))
        print("  r%-2d move=%08x anim=%08x  %s" % (i, m, a, r[0]))
    print("\n== SAUDE (confirmado GameShark NTSC-U) ==")
    print("  HP   u16 @ player+0xcc = 0x800ccc90  (max=200/0xC8)")
    print("  MAX  u16 @ player+0xce = 0x800ccc92")
    print("  cond byte @ player+0xd3 = 0x800ccc97 (0x04=FINE)")
    print("  dano:  0x8003dd7c (a0=dano,a1=modo)   cura: 0x8003de5c (clampa a +0xce)")
    print("  zona-de-anim (limp): motionType @0x8009cd3c <- HP: >=101 fine, 21..100 caution, <21 danger")
    print("  ECG/condicao: 0x80038080 (HP escalado 0..0xff -> flags em gamestruct+0x20f8)")
    print("\n== MIRA / TIRO ==")
    print("  botao mira/fogo: pad bits 0x100|0x400 (mask 0x500). held @gamestruct+0x2104=0x800cc83c")
    print("  auto-lock: 0x800445c8 (testa hitbox no arco) <- loop p/ inimigos 0x8001e900")
    print("  angulo p/ alvo: ratan2 0x8001808c ; ponto de mira do esqueleto: 0x80018d34")
    print("  alvo: player+0x16c/0x170 (=&enemy+0x34 pos); part-id atingido: player+0xc7")
    print("  arma equipada: player+0x46 ; municao/timer: player+0x12d ; trigger-debounce: player+0xe3")
    print("  tabela por-arma (idx=weapon-1): 0x8009ce88 (pistola w1 -> 0x8003e494; generico 0x8003eb28)")
    print("\n== ELO BALA->ALVO (dano ao inimigo) — RESOLVIDO ==")
    print("  tiro -> handler de arma -> FIRE_DMG_A %08x + FIRE_DMG_B %08x (varredura)" % (FIRE_DMG_A, FIRE_DMG_B))
    print("  varrem o array de personagens %08x, acham hitbox na linha de tiro, char+0xcc -= dano" % CHAR_ARRAY)
    print("  dano = *(rowptrs[alvo+0x4a] + (weapon-1)*8) & 0x3ff ; tabelas %08x/%08x/%08x" % (
        DMG_POSTURE_TBL, DMG_WPN_DESC, DMG_ROWPTRS))
    print("  HP do inimigo = char+0xcc (mesmo offset do player); setado por SCRIPT (member-set 0x80053f84).")
    print("  >> matriz completa arma-vs-tipo: python tools/exe_ai.py dmg")
    print("\n== AIM: GEOMETRIA / HITSCAN / TIMING (aim_shoot 100%) ==")
    print("  altura/pitch: %08x aim_tier(0..3)->player+0x6e=(tier<<9)+0x800; poses 14/15/16 (17 se tier3)" % AIM_TIER_PITCH)
    print("  upper-aim:    %08x  15->19 / 16->20 se player+0xc7 & 0x20 (alvo alto); facing +-0x400" % AIM_HEIGHT_SEL)
    print("  handler/arma: %08x  faca w0=0x8003e494 | generico(HITSCAN) 0x8003eb28 | rocket w10=0x800408c4 | granada w14=0x8003ff9c" % WPN_FIRE_TBL)
    print("  HITSCAN:      %08x  dist-min 0x7fffffff; itera chars gs+0x2664..0x2704; nao ha entidade-bala" % HITSCAN_A)
    print("  timing:       %08x  21x3B byte2&0x7f = frame do tiro (faca50 handgun12 magnum30 w11=8); rearme->rotina5" % WPN_TIMING_TBL)


MEM_RE = re.compile(r"(\$\w+),\s*(-?0x[0-9a-fx]+)\((\$\w+)\)")


def scan_stores(e, offsets):
    """Acha todos sb/sh/sw para os offsets dados (em qualquer base)."""
    by = e.disasm_all()
    hits = []
    for a, m, o in by:
        if m in ("sb", "sh", "sw") and o:
            mo = MEM_RE.search(o)
            if mo:
                try: off = int(mo.group(2), 0)
                except: continue
                if off in offsets:
                    hits.append((a, m, off, o))
    return hits


def scan_hp(e):
    """Heuristica: acha 'lhu/lh R,off(B); ...; subu R,R,D; sh R,off(B)' seguido de
    compare-com-zero (blez/bltz/slti). Candidatos a campo de HP com dano."""
    by = e.disasm_all()
    out = []
    for i in range(len(by) - 8):
        a, m, o = by[i]
        if m in ("lhu", "lh") and o:
            mo = MEM_RE.search(o)
            if not mo: continue
            reg, off, base = mo.group(1), mo.group(2), mo.group(3)
            # procura subu do mesmo reg e store de volta no mesmo offset em ate 8 insns
            win = by[i+1:i+9]
            has_sub = any(w[1] in ("subu", "sub", "addu", "addiu") and reg in (w[2] or "") for w in win)
            store = None
            for w in win:
                if w[1] in ("sh", "sb") and w[2] and off in w[2] and base in w[2]:
                    store = w; break
            if has_sub and store:
                cmp = any(w[1] in ("blez", "bltz", "slti", "slt", "bgtz") for w in by[i+1:i+12])
                out.append((a, off, base, cmp))
    return out


if __name__ == "__main__":
    e = Exe(EXE)
    if len(sys.argv) >= 2 and sys.argv[1] == "stores":
        offs = set(int(x, 0) for x in sys.argv[2:])
        for a, m, off, o in scan_stores(e, offs):
            print("%08x %s %s" % (a, m, o))
    elif len(sys.argv) >= 2 and sys.argv[1] == "hp":
        for a, off, base, cmp in scan_hp(e):
            print("%08x  field %s(%s)  cmp0=%s" % (a, off, base, cmp))
    elif len(sys.argv) >= 2 and sys.argv[1] == "fn":
        addr = int(sys.argv[2], 0)
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 120
        e.disasm(addr, n)
    elif len(sys.argv) >= 2 and sys.argv[1] == "scan":
        print_scan(e, int(sys.argv[2], 0))
    else:
        report(e)
