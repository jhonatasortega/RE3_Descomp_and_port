#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Analise da IA de INIMIGOS e do sistema de HP/DANO do inimigo no SLUS_009.23
(RE3 Nemesis, NTSC-U). Complementa tools/exe_combat.py (que cobre o player).

Base ja provada (docs/formatos/exe.md, docs/decomp/notes/exe_combat.md):
  * player-struct base 0x800ccbc4 (deref *(u32*)0x800ccd94)
  * gamestruct base 0x800ca738 (= 0x800d0000 - 0x58c8)
  * auto-lock 0x800445c8 (testa hitbox do inimigo contra o arco de mira do player)

DESCOBERTAS desta unidade (todas derivadas dos bytes reais do EXE):
  * Loop de OBJETOS/ENTIDADES: 0x8001bb24. Itera work-structs de 0xD4 (212) bytes,
    stride -0xD4, ate 0x60 (96) slots. Bounds em 0x80098084/0x80098088.
    Despacha por work+0 (byte tipo 0..63) via tabela T64 @ 0x80097bd4 (0x8001bbe8).
  * INIMIGOS = tipos de objeto ~16..44 (cada especie/NPC = um handler da T64).
    Handlers de combate completos (tem timer de hurt +0xb8): 22,23,26,27,30,33,37,38,40,41.
    Type 23 (0x8001e444) e o MAIOR (~3524 B) = ZUMBI (walker) com maior probabilidade.
  * Struct do inimigo (offsets provados) — ver ENEMY_FIELDS.
  * Cada inimigo, no seu update, OFERECE suas hitboxes de parte (0x41=corpo, 0x42=cabeca)
    ao auto-lock do player (0x800445c8), a partir dos ossos em [enemy+0xbc]+0x34.
  * Maquina de estados por +enemy+0x18 (0..4): tabela 0x800103f8 (5 entradas) no type 23.

Uso:
    python tools/exe_ai.py               # relatorio completo
    python tools/exe_ai.py t64           # tabela de 64 handlers + classificacao
    python tools/exe_ai.py enemy 23      # detalha o handler do tipo N
    python tools/exe_ai.py states 23     # tabela de estados (+0x18) do tipo N
    python tools/exe_ai.py fn 0x8001e444 200
    python tools/exe_ai.py stores 0xb8   # acha sh/sb/sw para enemy+0xNN
    python tools/exe_ai.py hp             # HP/dano/spawn (achados do round HP)
    python tools/exe_ai.py dmg            # elo bala->alvo + tabela de dano arma-vs-inimigo
    python tools/exe_ai.py hpinit         # HP inicial via member-set do script
    python tools/exe_ai.py nemesis        # Nemesis: descritores de ataque + fases
    python tools/exe_ai.py char           # dispatcher por-classe + FRONTEIRA de overlay (teto real)
"""
import sys, re
sys.path.insert(0, "tools")
from exe_parse import Exe

EXE = "extracted/ntsc-u/SLUS_009.23"

T64          = 0x80097bd4   # tabela de 64 handlers de objeto/entidade (dispatch por work+0)
OBJ_LOOP     = 0x8001bb24   # laco principal de objetos (stride 0xD4)
OBJ_BOUND_LO = 0x80098084   # ptr: inicio do array de work-structs (RAM)
OBJ_BOUND_HI = 0x80098088   # ptr: fim do array
AUTO_LOCK    = 0x800445c8   # testa hitbox de parte do inimigo contra o arco de mira
RAND         = 0x800102e8   # rand()
MOVE_DRV     = 0x8001b35c   # driver de locomocao/colisao do inimigo (a3 = &enemy+0x90)
MOTION_TRIG  = 0x8001b894   # dispara motion/anim/sfx (a0=motion id, a1=&enemy+0x90)
BEHAV_TBL    = 0x80098728   # tabela (bytes com sinal) indexada por rand -> offset de vagar
ENTITY_LIST  = 0x800ccd9c   # cabeca da lista encadeada de personagens (player + inimigos)
WPN_FIRE_TBL = 0x8009ce88   # 16 ptrs: handler de FOGO por arma (idx = weapon id)
WPN_STAT_TBL = 0x8009cf28   # 21 x 3B: b0=flags|municao, b1=cadencia/qtd, b2&0x7f=frame de disparo
                            # (NAO e dano-vs-inimigo; lida so pelos handlers de arma 0x8003exxx)
CONTACT_A    = 0x80044804   # teste de contato inimigo->player (percorre lista 0x800ccd9c)
CONTACT_B    = 0x80047860   # idem (2o teste; OR do resultado gateia a IA)
WALL_COLL    = 0x8001bfd0   # colisao do inimigo c/ geometria -> seta +0x26 bits 0x10/0x20
BOSS_STRUCT  = 0x800e01c0   # struct de evento de BOSS (Nemesis?) armada por 0x80058c70 (SCD)
BOSS_GATE    = 0x800ca738 + 0x77f4  # gamestruct+0x77f4: gate global (|0x200 no evento de boss)

# ---- HP / DANO (round HP) — ver exe_ai.md secao 3 ----------------------------
# HP vive na STRUCT de PERSONAGEM (0x194 B, lista 0x800ccd9c): player + aliados + bosses.
# NAO no work-struct 0xD4 do inimigo comum (o 0xD4 usa +0xcc como ptr de animacao).
CHAR_HP_CUR  = 0xcc         # hword: HP ATUAL (char-struct); decrementado pelo dano
CHAR_HP_MAX  = 0xce         # hword: HP MAXIMO (char-struct); teto do heal
CHAR_DEAD_FL = 0xd2         # hword: flags de status; bit 0x800 setado quando HP chega a 0
DMG_TO_CHAR  = 0x8003dd7c   # dano AO player/char: char+0xcc -= a0; clamp 0; +0xd2|=0x800
HEAL_CHAR    = 0x8003de5c   # cura: char+0xcc += a0; clamp ao teto char+0xce
PLAYER_BASE  = 0x800ccbc4   # = 0x800d0000-0x343c (base a2 hardcoded em DMG_TO_CHAR/HEAL)

# ---- SPAWN de inimigo/objeto (round HP) --------------------------------------
# Pool ESTATICO de work-structs 0xD4: 96 slots. Bounds (ptr) em 0x80098084/88.
ENEMY_POOL_LO = 0x800ba8a8  # inicio do pool (RAM); *(0x80098084)
ENEMY_POOL_HI = 0x800bf828  # fim do pool; *(0x80098088). (HI-LO = 0x4f80 = 96*0xD4)
MODEL_TBL     = 0x800ba728  # tabela runtime 32x12B (chave=byte+8=tipo; w+0=skel/mesh, w+4=anim);
                            # populada na carga da sala; fica logo ANTES do pool
SPAWN_OBJ     = 0x8001b484  # cria objeto no pool: aloca slot (0x8001c254), le MODEL_TBL[tipo],
                            # seta modelo/esqueleto/anim/pos. NAO seta HP.
SLOT_ALLOC    = 0x8001c254  # aloca um slot livre do pool (retorna ptr ou -1)
EM_UPDATE     = 0x8001ba48  # op 0x77: atualiza slot ativo casando (+0x28=id, +0xc0=subid)
# Opcodes SCD que chamam SPAWN_OBJ (sce_em_set e variantes): so tipo/id/pos/dir — SEM HP.
SPAWN_OPCODES = {0x70: 0x80056004, 0x71: 0x800560b8, 0x72: 0x80056178, 0x73: 0x8005624c}
EM_KILL_OP    = 0x800563e4   # op 0x76: mata inimigo (zera slot+0/1/0x24 casando +0xc0)
# Tabela de DESCRITORES DE COMBATE por-tipo (hitbox/ataque), adjacente a T64:
COMBAT_TBL    = 0x80097fc4   # 38 ptrs (stride 0x14) p/ registros de 20B em 0x80097cd4+;
                            # record+8 indexado por estado (+0x18) = descritor de contato/ataque
                            # (usado no contato de ataque 0x8001cb00, e no ataque do Nemesis t41
                            #  via 0x80097fcc[estado] -> 0x800472ec). NAO e' HP.

# ============================================================================
# ELO BALA->ALVO + HP DO INIMIGO  (round 2, este agente) — ver exe_ai.md sec 3
# ============================================================================
# CORRIGE a conclusao "negativa" antiga: o tiro do player APLICA dano sim, via a
# rotina GENERICA de dano 0x80044804 (irma de base-em-registrador de 0x8003dd7c).
#
# ARRAY DE PERSONAGENS (nao "lista"): ponteiros de char-struct de 0x1fc bytes.
CHAR_ARRAY_LO = 0x800ccd9c   # = gamestruct+0x2664 : inicio do array de ptrs de personagem
CHAR_ARRAY_END= 0x800ca738 + 0x2704  # ptr RAM p/ FIM do array (bump a cada registro)
CHAR_STRUCT_SZ= 0x1fc        # tamanho de uma char-struct (508 B). Player = slot 0 = 0x800ccbc4
CHAR_POOL_PTR = 0x800ca738 + 0x213c  # ptr RAM do pool de char-structs (bump 0x1fc por char)
CHAR_COUNT    = 0x800ca738 + 0x2487  # byte: numero de personagens registrados
CHAR_ARRAY_INIT = 0x80017580 # zera o array (slot0=player 0x248c) e reserva N=+0x2487 chars
CHAR_REGISTER  = 0x8001af3c  # registra 1 char no array (copia template, bump count/end)
CHAR_CLASS_OFF = 0x4a        # char+0x4a = CLASSE do personagem: 0..7 player/aliado, 16..44 inimigo
                            # (== indice na T64 e na tabela de dano). Player usa +0x4a p/ postura.
# --- rotina GENERICA de dano (varre o array, acha o char mais proximo com overlap
#     de hitbox e faz char+0xcc -= dano). a0=ponto/hitbox, a1=desc de ataque, a2=arma. ---
DMG_SCAN_A    = 0x80044804   # dano por VARREDURA (CONTACT_A): usada pelo TIRO do player e
                            #   pelo ataque do inimigo. Retorna ptr do char atingido (ou 0/-1).
DMG_SCAN_B    = 0x80047860   # 2a varredura (CONTACT_B) — o tiro chama as DUAS.
DMG_APPLY_C   = 0x800477ac   # outra rotina de dano (char+0xcc -= s2), base $s0
DMG_APPLY_D   = 0x80048290   # idem, base $s1
DMG_SCRIPT_SUB= 0x80051b9c   # opcode SCD: char+0xcc -= operando (char = *(gamestruct+0x2140))
DMG_MEMBER_SET= 0x80053f84   # setter de membro por script: char+0xcc = a2 (SET de HP via SCD)
# handlers de arma que chamam DMG_SCAN_A/B (idx = weapon id em 0x8009ce88):
WPN_FIRE_HANDLERS = {0: 0x8003e494, 1: 0x8003e4d0}  # 0=trampolim (por +6); 1=handgun etc
# --- TABELA DE DANO arma-vs-inimigo (isolada) ---
DMG_POSTURE_TBL = 0x8009dbb4  # 16 ptrs (idx = player+0x4a postura); todos -> 0x8009d934
DMG_WPN_DESC    = 0x8009d934  # descritor de ataque por arma (0x20 B cada; +0x1c -> DMG_ROWPTRS+0x40)
DMG_ROWPTRS     = 0x8009d834  # array de ptrs-de-linha (idx = alvo+0x4a = tipo 16..48)
DMG_ROW_DEFAULT = 0x8009d0f4  # linha default (tipos 16-31,38-47): 8B por arma; dano = word0 & 0x3ff
# linhas por-tipo (resistencias): idx = alvo+0x4a
DMG_ROWS_BY_TYPE = {32: 0x8009d194, 33: 0x8009d234, 34: 0x8009d2d4, 36: 0x8009d2d4,
                    35: 0x8009d374, 40: 0x8009d374, 37: 0x8009d414, 48: 0x8009d4b4}
# opcode SCD 0x7d (0x80056a2c) = cria char-struct de combate a partir do descritor de script
# 0x800e0198 (byte+3=classe->char+0x4a, +4=arma, +8/9/a/b=ids, +0xc/e/10=pos, +0x12=ang). SEM HP.
CHAR_CREATE_OP  = 0x80056a2c  # (op 0x7d) — candidato a sce_em_set / spawn de personagem de combate
CHAR_DESC_PTR   = 0x800e0198   # ptr p/ o operando do script lido pelo CHAR_CREATE_OP

# ============================================================================
# HP INICIAL do inimigo — via MEMBER-SET do script (round 'fios finos')
# ============================================================================
# HP (char+0xcc) NAO tem default estatico por-classe (varredura EXAUSTIVA de TODOS os
# stores a +0xcc: so player/aliado=200 no room-load 0x800494e4/0x80049534 e op0x59180,
# dano/cura, member-set e o ptr de anim do 0xD4). op 0x7d (spawn) NAO grava +0xcc; o
# char registrado herda +0xcc do pool (nao-inicializado) ate o SCRIPT gravar via member-set.
MEMBER_SET_DISP = 0x80053e10   # dispatcher: member_set(a0=char, a1=idx<0x2b, a2=valor) via tabela
MEMBER_SET_TBL  = 0x80010950   # 43 setters (stubs 'jr $ra; <store>' no delay-slot)
MEMBER_GET_DISP = 0x80053fac   # dispatcher de GETTERS (tabela 0x80010a00)
MEMBER_HP_IDX   = 0x26         # member[0x26] -> 0x80053f80: 'jr $ra; sh a2,0xcc(a0)' = SET HP
MEMBER_SET_HP   = 0x80053f80   # setter stub do HP (store no delay-slot em 0x80053f84)
# Opcodes SCD que gravam membro no char ATIVO (obj+0x154):
OP40_SET_LIT    = 0x80053b74   # op 0x40: [op, member_idx, value_hword] (PC+=4) -> member_set literal
OP41_SET_VAR    = 0x80053bc0   # op 0x41: [op, member_idx, var_idx] valor=*(0x800d1f46+var*2) (PC+=3)
OP42_GET        = 0x80053c20   # op 0x42: member_get -> variavel
# HP por-sala achado no SCD real (decode via scd_decode): op 0x40 member 0x26 = 24 sitios,
# valores {1,20,99,100,200,400,500,600,800} (400/500/600/800 = bosses/Hunters; 200=Carlos).
HP_SCRIPT_VALUES = {1: 6, 20: 1, 99: 1, 100: 5, 200: 1, 400: 2, 500: 2, 600: 2, 800: 2, 0: 1}

# ============================================================================
# LINK 0xD4 (IA) <-> char-struct 0x1fc — status (round 'fios finos')
# ============================================================================
# CLARIFICADO (mas ponteiro 1:1 NAO isolado — segue 🟡):
#  - op 0x7d (0x80056a2c) cria SO a char-struct (0x1fc); NAO chama o spawn 0xD4
#    (0x8001b484) nem aloca slot 0xD4. So chama 0x80078930 (checa modelo).
#  - NAO ha dispatcher de IA indexado por char+0x4a (classe): o char-struct e' o lado
#    PASSIVO de combate (HP/hitbox/dano por varredura); o 0xD4 e' a IA ATIVA (dispatch
#    T64 por work+0 no loop 0x8001bb24). Sao pools/loops distintos.
#  - work+0xd0 (0xD4) e' ptr p/ OUTRO 0xD4 (parte secundaria do modelo multi-mesh:
#    spawn 0x8001b7fc 'sw s1,0xd0(s0)' apos memcpy de 0xb0 B) — NAO e' a char-struct.
#  - O loop de objetos le work+0xd0 e checa (ptr)+0x24 (render) p/ despawn — link 0xD4<->0xD4.
LINK_D4_TO_D4   = 0xd0          # work+0xd0 -> 0xD4 secundario (multi-parte), NAO char-struct
# ============================================================================
# NEMESIS por-forma — descritores de ataque por-estado (round 'fios finos')
# ============================================================================
# t41 (0x80020eb8) despacha por +0x01 (fase) e +0x22 (modo 2/3/4); ataque por estado +0x18
# le NEMESIS_ATK_TBL[estado] = 0x80097fcc + estado*4 -> registro de 20B (hitbox/ataque, NAO HP).
NEMESIS_STATE_DESC = 0x80097cd4  # base dos registros por-estado (6 x 20B); ver nemesis_report()
# HP do Nemesis: char+0xcc via member-set (op 0x40 idx 0x26) por-encontro (comunidade ~400-800).
# --- Nemesis (boss) ---
NEMESIS_HANDLER = 0x80020eb8   # t41: fase +0x01, sub-modo +0x22 (2/3/4), estado +0x18, timers +0xb8/+0x2c
NEMESIS_ATK_TBL = 0x80097fcc   # = COMBAT_TBL+8: descritor de ataque por estado (+0x18) -> 0x800472ec
BOSS_ARM_OP     = 0x80058c70   # op 0x25: arma o evento; boss+4=4, boss+0xb8=param, gate 0x77f4|0x200

# ============================================================================
# TETO REAL (round 'overlay') — dispatcher de char por CLASSE + fronteira estatica
# ============================================================================
# CORRIGE exe_ai.md §3.9 ("NAO ha dispatcher de IA por char+0x4a"): ELE EXISTE.
# O loop principal de chars 0x80023e00 despacha por classe e chama a0=char:
#   v1 = (char+0x4a) - 0x10 ; v0 = *(gamestruct+0x3de0 + v1*4) ; jalr v0 ; a0=char
CHAR_LOOP        = 0x80023e00   # loop principal de char-structs (por classe)
CHAR_DISPATCH    = 0x80023ea8   # jalr do handler de classe (a0=char) [per-frame]
CHAR_DISPATCH_RL = 0x80049b08   # mesmo dispatch no room-load (+0x80049b44 c/ mira +0xd8)
CLASS_AI_TBL     = 0x800ca738 + 0x3de0  # gs+0x3de0: handler ATIVO por (classe-0x10)
CLASS_AI_SRC     = 0x800ca738 + 0x3fa0  # gs+0x3fa0: tabela 2D fonte (stride 0x1c0/slot)
CLASS_AI_POPULATE= 0x80013700  # copia gs+0x3fa0[slot][classe-0x10] -> gs+0x3de0[classe-0x10]
CLASS_AI_INIT    = 0x80017adc  # inicializacao ESTATICA de gs+0x3fa0 (ptrs -> OVERLAY 0x8010xxxx)
# FRONTEIRA: os handlers de classe apontam p/ 0x80100000+ (upper-RAM), ALEM do text
# do EXE (0x80010000..0x800e3800, tsize 0xd3800). => a ARVORE DE DECISAO por-classe do
# inimigo (inclui Nemesis) NAO existe estaticamente neste binario; roda de um overlay.
OVERLAY_BASE     = 0x80100000  # base do overlay de IA (>= vend 0x800e3800)
ENEMY_SEG_COPY   = 0x800179b8  # jal 0x800100a4: copia segmento do inimigo p/ 0x8010d000
ENEMY_SEG_DST    = 0x8010d000  # destino do segmento por-inimigo (char+0xec aponta p/ ca)
CHAR_SEG_PTR_OFF = 0xec        # char+0xec = ptr do segmento carregado (upper-RAM)
# LINK 0xD4<->char: hitbox do char segue a POSE (nao um ptr ao 0xD4):
CHAR_POSE_OFF    = 0x108       # char+0x108 = buffer de pose/anim (setado 0x80026184)
CHAR_HITBOX_NODE = 0x13c       # char+0x13c = *(char+0x108)+0x40 (0x80038f08); dano le +0x14/+0x1c
# HP inicial (setter verificado):
OP40_MEMBER_HP   = 0x80053f80  # tbl 0x80010950[0x26]: jr $ra; sh a2,0xcc(a0)  (= char+0xcc)
# Nemesis:
NEMESIS_OP25     = 0x80058c70  # arma boss: boss(0x800e01c0)+0xb8 = byte@PC+2 (param de forma)
# op 0x25 real (169 salas): R502=2, R506=2, R70C=1  -> boss+0xb8 in {1,2} (indice de forma)
NEMESIS_OP25_SITES = {"R502": 2, "R506": 2, "R70C": 1}

# faixa dos handlers que sao inimigos/personagens (T64 idx 16..44)
ENEMY_TYPE_LO, ENEMY_TYPE_HI = 16, 44

# ---------------------------------------------------------------------------
# Struct do INIMIGO (work-struct de 0xD4 bytes). Base = a0 do handler.
# ✅ = provado no disasm ; 🟡 = inferido
# ---------------------------------------------------------------------------
ENEMY_FIELDS = {
    0x00: "flags/tipo (word): low byte=tipo(dispatch T64); demais bits=flags",   # ✅
    0x02: "fase (byte): 0=init, 1=ativo, 2=morrendo",                            # ✅ (handler 23 topo)
    0x18: "estado de IA (byte): 0..2=vivo, 3..4=morte; dispatch em tbl 0x800103f8",# ✅
    0x19: "sub-estado/estado-2 (byte)",                                          # 🟡
    0x24: "flags de render/animacao (hword): bit 0x8000=visivel",                # ✅
    0x26: "flags COLISAO/status (hword): bits 0x10/0x20 = bloqueado em parede "     # ✅ (CORRIGIDO)
          "(via 0x8001bfd0), NAO 'atingido'",
    0x2c: "angulo pendente (hword) -> copiado p/ +0xba",                         # ✅
    0x32: "contador/limite de movimento (hword)",                                # 🟡
    0x34: "posicao no mundo (x,y,z a partir daqui; alvo do player+0x170)",        # ✅
    0x48: "descritor de HITBOX/colisao (base; player+0x16c aponta p/ ca)",        # ✅
    0x50: "componente de posicao (usado no clamp +-0x7918)",                      # ✅
    0x60: "componente de posicao (media com +0x50 = centro)",                     # ✅
    0x90: "work de locomocao/colisao (passado como a3 ao 0x8001b35c)",            # ✅
    0xb4: "contador de morte/anim (lido na fase 2 morrendo)",                     # 🟡
    0xb8: "TIMER de hurt/stagger (hword): >0 congela a IA normal ate zerar",      # ✅
    0xba: "angulo de direcao atual (hword, 12-bit)",                              # ✅
    0xbc: "ptr p/ dados de osso/parte; [+0xbc]+0x34 = pos 3D da parte",           # ✅
    # HP: ainda nao isolado byte-a-byte (ver exe_ai.md secao HP/DANO)
}

ENEMY_STATES_T23 = {  # tabela 0x800103f8 (type 23)
    0: ("idle/vagar",  0x8001eafc, "rand->BEHAV_TBL; anda devagar (spd 0x1200); fidget"),
    1: ("aproximar",   0x8001eba0, "rand->rumo; MOVE_DRV spd 0x1c00; checa frame p/ atacar"),
    2: ("atacar",      0x8001ed00, "MOVE_DRV spd 0x1300; motion 0xd02+0x805 (bote/mordida)"),
    3: ("morte A",     0x8001ee18, "rand escolhe anim de queda (motion 0x3d/0x10c)"),
    4: ("morte B",     0x8001ee18, "(mesma rotina de morte)"),
}


def md_ops(o):
    return [x.strip() for x in o.split(",")] if o else []


def func_end(e, start, maxins=1200):
    ins = e.disasm(start, maxins, show=False)
    out = []
    for t in ins:
        out.append(t)
        if t[1] == "jr" and (t[2] or "").strip() == "$ra":
            # inclui delay slot
            break
    return out


def t64_report(e):
    print("== T64 handlers @ %08x (dispatch por work+0; loop %08x, stride 0xD4) ==" % (T64, OBJ_LOOP))
    print("   stubs conhecidos: 9..15, 45..50 (jr $ra)")
    print("   INIMIGOS/PERSONAGENS = tipos %d..%d\n" % (ENEMY_TYPE_LO, ENEMY_TYPE_HI))
    for i in range(64):
        h = e.u32(T64 + i * 4)
        tag = ""
        if ENEMY_TYPE_LO <= i <= ENEMY_TYPE_HI:
            ins = e.disasm(h, 160, show=False)
            def has(s): return any(s in (t[2] or "") for t in ins)
            flags = []
            if has("0x18("): flags.append("state")
            if has("0xb8("): flags.append("hurt")
            if has("0x2c("): flags.append("ang")
            if any(t[1] in ("jal", "jalr") and hex(RAND)[2:] in (t[2] or "") for t in ins):
                flags.append("rand")
            fe = func_end(e, h)
            tag = "  [ENEMY?  size~%d  %s]" % ((fe[-1][0] - h + 8), ",".join(flags))
        print("  t%2d -> %08x%s" % (i, h, tag))


def enemy_detail(e, idx):
    h = e.u32(T64 + idx * 4)
    fe = func_end(e, h)
    print("== handler do tipo %d @ %08x  (size~%d) ==" % (idx, h, fe[-1][0] - h + 8))
    # acha dispatch por +0x18 (sltiu N; ... jr Vx via tabela)
    for i, t in enumerate(fe):
        if t[1] == "sltiu" and t[2]:
            ops = md_ops(t[2])
            if len(ops) == 3 and "0x18" not in t[2]:
                win = fe[i:i + 10]
                jr = [w for w in win if w[1] == "jr" and (w[2] or "").strip() != "$ra"]
                lui = [w for w in win if w[1] in ("lui", "addiu")]
                if jr and lui:
                    print("  dispatch de estado: %s  (site %08x)" % (t[2], t[0]))
    print("  (use 'python tools/exe_ai.py fn %#x %d' para o disasm)" % (h, min(400, len(fe) + 20)))


def states_report(e, idx):
    if idx == 23:
        print("== estados (+enemy+0x18) do tipo 23 (ZUMBI?) — tabela 0x800103f8 ==")
        for s, (nome, addr, desc) in ENEMY_STATES_T23.items():
            v = e.u32(0x800103f8 + s * 4)
            mark = "ok" if v == addr else "!!"
            print("  st%d %08x [%s] %-11s %s" % (s, v, mark, nome, desc))
    else:
        # tenta achar a tabela via o dispatch
        enemy_detail(e, idx)


def stores_report(e, off):
    al = e.disasm_all()
    MEM = re.compile(r"(\$\w+),\s*(-?\w+)\((\$\w+)\)")
    for a, m, o in al:
        if m in ("sb", "sh", "sw") and o and "(" in o:
            mo = MEM.search(o)
            if mo:
                try: v = int(mo.group(2), 0)
                except: continue
                if v == off and "$sp" not in o:
                    print("%08x %-4s %s" % (a, m, o))


def hp_report(e):
    print("== HP / DANO / SPAWN do inimigo (round HP) ==\n")
    print("HP vive na STRUCT DE PERSONAGEM (0x194 B; lista %08x) — player + aliados + bosses." % ENTITY_LIST)
    print("  +0x%02x = HP ATUAL (hword)   +0x%02x = HP MAX (hword)   +0x%02x bit 0x800 = morto" % (
        CHAR_HP_CUR, CHAR_HP_MAX, CHAR_DEAD_FL))
    print("  dano AO char: %08x  (char+0xcc -= a0[dano]; clamp 0; seta +0xd2|0x800)" % DMG_TO_CHAR)
    print("  cura:         %08x  (char+0xcc += a0; teto = char+0xce)" % HEAL_CHAR)
    print("  player-base (a2 hardcoded) = %08x" % PLAYER_BASE)
    print()
    print("Inits de HP MAX (char+0xce) encontrados (todos = 0xc8 = 200 = Carlos/aliado/boss):")
    for a in (0x800495e4, 0x80057430, 0x80059214, 0x80024608):
        print("    %08x  sh (0xc8) ,0xce(base)" % a)
    print()
    print("Inimigo COMUM = work-struct 0xD4 (pool %08x..%08x, 96 slots):" % (ENEMY_POOL_LO, ENEMY_POOL_HI))
    print("  spawn %08x (via SCD op 0x70-0x73) le MODEL_TBL %08x[tipo] e so seta modelo/pos." % (SPAWN_OBJ, MODEL_TBL))
    print("  -> o 0xD4 NAO tem campo de HP (+0xcc do 0xD4 = ptr de animacao, nao HP).")
    print("  -> os opcodes de spawn carregam so tipo/id/pos/dir: HP NAO vem do RDT/SCD.")
    print()
    print("Opcodes SCD de spawn (chamam %08x):" % SPAWN_OBJ)
    for op, h in sorted(SPAWN_OPCODES.items()):
        print("    op 0x%02x -> %08x" % (op, h))
    print("  op 0x76 (kill) %08x ; op 0x77 (update pos) -> %08x" % (EM_KILL_OP, EM_UPDATE))
    print()
    print("Tabela de descritores de combate por-tipo: %08x (38 x 20B; record+8[estado]=hitbox/ataque)" % COMBAT_TBL)


def dmg_report(e):
    print("== ELO BALA->ALVO e TABELA DE DANO arma-vs-inimigo ==\n")
    print("Tiro do player -> handler de arma (0x8009ce88[weapon]) -> chama DMG_SCAN_A %08x" % DMG_SCAN_A)
    print("  e DMG_SCAN_B %08x. Cada um VARRE o array de personagens %08x..*(%08x)," % (
        DMG_SCAN_B, CHAR_ARRAY_LO, CHAR_ARRAY_END))
    print("  acha o char mais proximo com overlap de hitbox e faz  char+0x%02x -= dano." % CHAR_HP_CUR)
    print("  (mesma rotina que o inimigo usa p/ bater no player; base em REGISTRADOR, nao no player).")
    print()
    print("Dano = *(linha[alvo+0x4a] + (weapon-1)*8) & 0x3ff  (10 bits).")
    print("  postura tbl %08x[player+0x4a] -> desc %08x[weapon] ; desc+0x1c -> rowptrs %08x[alvo+0x4a]" % (
        DMG_POSTURE_TBL, DMG_WPN_DESC, DMG_ROWPTRS))
    print("  alvo+0x4a = CLASSE do inimigo (16..48). linha default %08x ; resistencias por-tipo:" % DMG_ROW_DEFAULT)
    for t in sorted(set(DMG_ROWS_BY_TYPE)):
        print("    tipo %2d -> %08x" % (t, DMG_ROWS_BY_TYPE[t]))
    print()
    cols = [("default", DMG_ROW_DEFAULT), ("t32", 0x8009d194), ("t33", 0x8009d234),
            ("t34/36", 0x8009d2d4), ("t35/40", 0x8009d374), ("t37", 0x8009d414), ("t48", 0x8009d4b4)]
    print("arma | " + " | ".join("%6s" % c[0] for c in cols))
    for w in range(1, 17):
        vals = [" %4d " % (e.u32(base + (w - 1) * 8) & 0x3ff) for _, base in cols]
        print("  w%-2d | %s" % (w, "|".join(vals)))
    print()
    print("HP do inimigo/boss: vive em char+0x%02x (mesmo offset do player). NAO ha tabela de HP" % CHAR_HP_CUR)
    print("  por-tipo com imediato no EXE (varredura negativa). E' setado por SCRIPT:")
    print("   - SET:  %08x (member-set char+0xcc = a2)" % DMG_MEMBER_SET)
    print("   - SUB:  %08x (opcode SCD char+0xcc -= operando)" % DMG_SCRIPT_SUB)
    print("  spawn de char de combate: op 0x7d %08x (descritor %08x; sem campo de HP)." % (
        CHAR_CREATE_OP, CHAR_DESC_PTR))


def hpinit_report(e):
    print("== HP INICIAL do inimigo — member-set do script ==\n")
    print("SEM default estatico por-classe (varredura exaustiva de +0xcc: player=200, dano/cura,")
    print("member-set, ptr-anim do 0xD4). op 0x7d NAO grava HP; char herda +0xcc do pool.")
    print()
    print("member_set dispatcher %08x (tabela %08x, 43 setters); member[0x%02x] = HP:" % (
        MEMBER_SET_DISP, MEMBER_SET_TBL, MEMBER_HP_IDX))
    v = e.u32(MEMBER_SET_TBL + MEMBER_HP_IDX * 4)
    ins = e.disasm(v, 2, show=False)
    print("  member[0x%02x] -> %08x : %s %s ; %s %s  (HP = char+0xcc)" % (
        MEMBER_HP_IDX, v, ins[0][1], ins[0][2], ins[1][1], ins[1][2]))
    print()
    print("Opcodes SCD que gravam membro no char ATIVO (obj+0x154):")
    print("  op 0x40 %08x  [op, member_idx, value_hword]  (PC+=4) literal" % OP40_SET_LIT)
    print("  op 0x41 %08x  [op, member_idx, var_idx] valor=*(0x800d1f46+var*2) (PC+=3)" % OP41_SET_VAR)
    print("  op 0x42 %08x  member_get" % OP42_GET)
    print()
    print("HP achado no SCD real (op 0x40 member 0x26, 169 salas): valor -> qtd de sitios")
    for hp in sorted(HP_SCRIPT_VALUES):
        print("    hp=%-4d x%d" % (hp, HP_SCRIPT_VALUES[hp]))
    print("  (400/500/600/800 = bosses/Hunters; 200 = Carlos/aliado; comuns usam member-set por-sala)")


def nemesis_report(e):
    print("== NEMESIS (t41 %08x) por-forma: fase +0x01 / modo +0x22 / estado +0x18 ==\n" % NEMESIS_HANDLER)
    print("Ataque por estado: NEMESIS_ATK_TBL[estado] = 0x%08x + estado*4 -> registro 20B:" % NEMESIS_ATK_TBL)
    print("Descritores por-estado (0x%08x, 10x hword cada):" % NEMESIS_STATE_DESC)
    lbl = {0: "idle/aproxima", 1: "ataque A (garra)", 2: "ataque B", 3: "ataque C (agarrar)",
           4: "ataque D", 5: "especial/tentaculo"}
    for st in range(6):
        base = NEMESIS_STATE_DESC + st * 0x14
        ws = [e.u16(base + k * 2) for k in range(10)]
        print("  st%d @%08x [%-16s]: %s" % (st, base, lbl.get(st, "?"),
              " ".join("%04x" % w for w in ws)))
    print()
    print("Leitura do registro (via contato 0x800472ec): +0=flags/id, +2=alcance, +4=offset,")
    print("  +0xa/+0xc=extensoes de hitbox, +0x10/0x12=dano/reacao (geometria de ataque, NAO HP).")
    print("FORMAS (fase +0x22): modo 2 (arma timer +0xb8), modo 3/4 (transicoes) — 1a/2a/3a forma")
    print("  do RE3 mapeiam nos modos +0x22 + troca de modelo; HP por-encontro via member-set (~400-800). [incerto]")


def char_report(e):
    print("== DISPATCHER de char por CLASSE + FRONTEIRA de OVERLAY (teto real) ==\n")
    print("Loop principal de chars %08x: para cada char ativo," % CHAR_LOOP)
    print("  v1 = (char+0x4a[classe]) - 0x10 ; v0 = *(gs+0x3de0 + v1*4) ; jalr v0 ; a0=char")
    print("  -> dispatch em %08x (per-frame) e %08x (room-load)." % (CHAR_DISPATCH, CHAR_DISPATCH_RL))
    print("  tabela ATIVA: gs+0x3de0 (%08x) ; fonte 2D gs+0x3fa0 (%08x, stride 0x1c0)" % (
        CLASS_AI_TBL, CLASS_AI_SRC))
    print("  popula: %08x ; init ESTATICA: %08x" % (CLASS_AI_POPULATE, CLASS_AI_INIT))
    print()
    print("FRONTEIRA ESTATICA: text do EXE = %08x..%08x (tsize %08x)." % (e.base, e.vend, e.tsize))
    print("  Os handlers de classe apontam p/ %08x+ (OVERLAY em upper-RAM, STACK=0x801FFF00)." % OVERLAY_BASE)
    print("  %08x >= vend(%08x)? %s  -> a ARVORE DE DECISAO por-classe NAO esta neste EXE." % (
        OVERLAY_BASE, e.vend, OVERLAY_BASE >= e.vend))
    print("  copia de segmento do inimigo: %08x (jal 0x800100a4) -> %08x ; char+0x%02x = ptr" % (
        ENEMY_SEG_COPY, ENEMY_SEG_DST, CHAR_SEG_PTR_OFF))
    print()
    print("LINK 0xD4<->char (2 pools distintos):")
    print("  char-struct 0x1fc: HP/classe/combate ; hitbox char+0x%02x = *(char+0x%02x[pose])+0x40" % (
        CHAR_HITBOX_NODE, CHAR_POSE_OFF))
    print("  work-struct 0xD4 : corpo/anim/efeitos ; T64 %08x[work+0] ; pool %08x..%08x" % (
        T64, ENEMY_POOL_LO, ENEMY_POOL_HI))
    print("  -> ptr direto 1:1 NAO existe no EXE; a ligacao e' feita pelo overlay (decisao).")
    print()
    print("HP inicial: op 0x40 %08x -> disp %08x -> tbl[0x26]=%08x (sh a2,0xcc(a0)). SEM default." % (
        OP40_SET_LIT, MEMBER_SET_DISP, OP40_MEMBER_HP))
    print("Nemesis op 0x25 %08x: boss+0xb8 = param de forma (indice). Sitios reais: %s" % (
        NEMESIS_OP25, NEMESIS_OP25_SITES))
    print("  (nenhuma string de nome/forma no EXE -> 'forma' e' indice numerico, nao texto).")
    print()
    print("*** FRONTEIRA RESOLVIDA (§5.6): o overlay 0x80100000+ e' um bloco de CODIGO MIPS")
    print("    embutido no STAGE#/R###.BIN da sala (NAO comprimido). Isole/desmonte com:")
    print("      python tools/overlay_ai.py scan")
    print("      python tools/overlay_ai.py info extracted/ntsc-u/CD_DATA/STAGE1/R101.BIN 4")
    print("    Prova: chama rand/spawn_obj/ratan2 do EXE; handler recebe a0=char (§5.6.1).")


def report(e):
    print("== SLUS_009.23  IA de inimigo + HP/dano  (base %08x) ==\n" % e.base)
    t64_report(e)
    print("\n== struct do inimigo (work-struct 0xD4) ==")
    for off in sorted(ENEMY_FIELDS):
        print("  +0x%02x  %s" % (off, ENEMY_FIELDS[off]))
    print("\n== ZUMBI (tipo 23) — maquina de estados ==")
    states_report(e, 23)
    print("\n== auto-lock (inimigo -> mira do player) ==")
    print("  %08x: cada inimigo oferece parte 0x41(corpo)/0x42(cabeca) de [enemy+0xbc]+0x34" % AUTO_LOCK)
    print("  seta player+0=|0x80000000, player+0x16c=&enemy+0x48, player+0x170=ptr osso, player+0xc7=part-id")
    print("\n== tabelas de arma (lado player) ==")
    print("  fogo por arma @ %08x: w0(handgun)->0x8003e494, w10->0x800408c4, w14->0x8003ff9c, generico 0x8003eb28" % WPN_FIRE_TBL)
    print("  stats por arma @ %08x (21 x 3B; byte2 &0x7f = frame de disparo)" % WPN_STAT_TBL)
    print("\n  ELO BALA->INIMIGO + dano-por-arma-vs-inimigo: RESOLVIDO -> 'python tools/exe_ai.py dmg'")
    print("  (tiro -> 0x80044804/0x80047860 varrem o array de chars 0x800ccd9c; char+0xcc -= dano).")


if __name__ == "__main__":
    e = Exe(EXE)
    a = sys.argv
    if len(a) >= 2 and a[1] == "t64":
        t64_report(e)
    elif len(a) >= 3 and a[1] == "enemy":
        enemy_detail(e, int(a[2], 0))
    elif len(a) >= 3 and a[1] == "states":
        states_report(e, int(a[2], 0))
    elif len(a) >= 3 and a[1] == "fn":
        n = int(a[3]) if len(a) > 3 else 120
        e.disasm(int(a[2], 0), n)
    elif len(a) >= 3 and a[1] == "stores":
        stores_report(e, int(a[2], 0))
    elif len(a) >= 2 and a[1] == "hp":
        hp_report(e)
    elif len(a) >= 2 and a[1] == "dmg":
        dmg_report(e)
    elif len(a) >= 2 and a[1] == "hpinit":
        hpinit_report(e)
    elif len(a) >= 2 and a[1] == "nemesis":
        nemesis_report(e)
    elif len(a) >= 2 and a[1] == "char":
        char_report(e)
    else:
        report(e)
