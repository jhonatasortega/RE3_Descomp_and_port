#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
item_logic no SLUS_009.23 (RE3 Nemesis, NTSC-U): FLAGS de progresso, inventario
(pegar/usar item) e como um flag muda o estado da sala.
Complementa tools/exe_combat.py (player) e tools/exe_ai.py (inimigos).

Base ja provada:
  * gamestruct base 0x800ca738 (= 0x800d0000 - 0x58c8)
  * player-struct base 0x800ccbc4 (deref *(u32*)0x800ccd94)

DESCOBERTAS desta unidade (derivadas dos bytes reais do EXE):
  * BANCO DE FLAGS: tabela de PONTEIROS de banco @ 0x8009e3f8 (16 entradas).
    Um flag = par (bank, bit). Endereco do word = bank_ptr + ((bit>>3)&0x1c);
    mascara = 0x80000000 >> (bit & 0x1f)   (bits gravados MSB-first no word).
  * SET/CLEAR de flag (args numa struct a0):  0x800512fc
      a0->[0]=bank(hword), a0->[2]=bit(hword), a0->[4]=modo(hword) 0=clear/!=0=set
  * SET/CLEAR de flag (operandos inline no script, IP=a0+0x1c):  0x8005472c
      byte1=bank, byte2=bit, byte3=modo (0=clear, 1=set, 2..=variantes)
  * CHECK de flag (opcode condicional do script):  0x800546cc
      byte1=bank, hword2=bit; retorna ((word & mask)!=0) XOR negacao(bit>>8==0)
  * bank1 -> 0x800d1f2c  = flags de PROGRESSO de jogo (mesmo bloco que o player_sm
    r9/escada le com &0x10). bank3.. -> 0x800d1fa0.. = flags de mapa/sala (GameShark
    de mapas 0x300D2127/0x300D212B caem aqui).
  * INVENTARIO: slot = {byte0=item id, byte1=quantidade, hword+2 = flags (bits altos
    0xc000 = slot vazio/consumido)}. Rotina de USO/consumo (decrementa qtd) em 0x8006d0a8
    (o GameShark "uso ilimitado" 8006D0CA 2400 nopa o store dessa rotina).

Uso:
    python tools/exe_items.py               # relatorio
    python tools/exe_items.py banks          # tabela de bancos de flags
    python tools/exe_items.py fn 0x800512fc 60
"""
import sys, struct
sys.path.insert(0, "tools")
from exe_parse import Exe

EXE = "extracted/ntsc-u/SLUS_009.23"

FLAG_BANK_TBL = 0x8009e3f8   # 16 ponteiros de banco de flags
FLAG_SET_A    = 0x800512fc   # set/clear (args em struct a0)
FLAG_SET_IP   = 0x8005472c   # set/clear (operandos inline no script)
FLAG_CHECK    = 0x800546cc   # check (opcode condicional)
ITEM_USE_DEC  = 0x8006d0a8   # decremento de quantidade (consumo/USE)
SCD_OP_TBL    = 0x8009e0f8   # jump-table de opcodes do VM de script de sala

# ---- INVENTARIO: struct, ponteiro e helpers (round 'pegar/usar/combinar') ----
# O array de slots vive em gamestruct+0x79fc (=0x800d2134); o PONTEIRO p/ ele em
# gamestruct+0x7c7c (=0x800d23b4), setado no init 0x8006d0d8 (0x8006d124 sw ...,0x7c7c).
INV_ARRAY     = 0x800d2134   # base do array de slots (gs+0x79fc)
INV_PTR       = 0x800d23b4   # ptr p/ a struct dona do inventario (gs+0x7c7c)
# Layout da struct do inventario (base = *(INV_PTR)):
#   +0x00.. : MAIN inventory (10 slots x 4B = 0x28)
#   +0x28.. : ITEM BOX (64 slots x 4B = 0x100) — organize/status screen
#   +0x128  : cursor / slot selecionado (byte)
#   +0x129  : id da ARMA equipada (byte)
#   +0x12a  : contagem de slots do MAIN inventory (byte)
# Slot (4B): b0=item id (0=vazio), b1=quantidade, hword+2=flags (0xc000=consumido).
INV_SLOT_CURSOR = 0x128
INV_SLOT_EQUIP  = 0x129
INV_SLOT_COUNT  = 0x12a
STACK_MAX_TBL   = 0x800a0514  # por item id, 4B/entrada: b0=categoria, b1=qtd MAX de stack,
                              # b2=idx de nome, b3=flags default do slot
# Helpers do modulo de inventario (base 0x8006cxxx):
INV_FIND_BY_ID  = 0x8006cc8c  # (a0=id,a1=start)->idx do 1o slot MAIN com esse id (-1 se nao);
                              #   find_by_id(0) = 1o slot VAZIO (id==0) = "achar slot livre"
INV_REMOVE_DEC  = 0x8006ccf0  # remove/decrementa qtd; se zera chama compact_shift
INV_COMPACT     = 0x8006cd68  # shift-left ao remover (compacta os slots MAIN)
INV_STACK_MERGE = 0x8006cf0c  # empilha/consolida municao (prologo real; 0x8006cf00 e o epilogo da fn anterior).
                              #   room=STACK_MAX_TBL[id].b1-qtd; transfere clampando a room; chama INV_REMOVE_DEC; gs+0x255e|0x400
INV_INIT        = 0x8006d0d8  # zera arrays de slots (10x) e seta o INV_PTR
# ---- PEGAR item (add-to-inventory) — janela "obter" ----
# Disparo: AOT de item/evento (SCE tipo 2, handler 0x8005111c) grava
#   gs+0x21dc = ptr do DESCRITOR do item (id@0, qtd@2) e gs+0x21d8 = alvo; e ativa a
#   maquina de estado da JANELA DE OBTER (ptr @0x800a012c -> 0x80069c3c).
ITEM_EVENT_SCE2 = 0x8005111c  # SCE tipo 2: arma gs+0x21dc/0x21d8 e a janela de obter
GET_WINDOW_SM   = 0x80069c3c  # maquina de estado da janela de obter item (obj+0x12 = estado)
GET_WINDOW_PTR  = 0x800a012c  # ptr de dados que aponta p/ GET_WINDOW_SM
GET_DESC_PTR    = 0x800d21dc  # gs+0x21dc: ptr p/ o descritor do item a obter
GET_FIND_SLOT   = 0x80069cb8  # estado0: acha slot (empilha via INV_FIND_BY_ID(id)+STACK_MAX_TBL;
                              #   senao INV_FIND_BY_ID(0)=1o vazio). Grava obj+0x6e=slot, obj+0x73=flag-empilhar.
                              #   Se cheio -> estado1 (msg "sem espaco").
GET_WRITE_SLOT  = 0x8006a020  # estado3: GRAVA {id@0, qtd@1, flags@2} em INV[obj+0x6e], OU
                              #   slot.qtd += desc.qtd (empilhar, sitio 0x8006a0f0). flags default = STACK_MAX_TBL[id].b3.
# AOT de item no chao (cria o modelo visivel; NAO concede): opcodes SCD
ITEM_AOT_OPS    = {0x67: 0x800574f4, 0x68: 0x800576c4}  # sce_item/msg_aot_set (22B/30B)
OP_NOTES = {0x25: "evento de BOSS/Nemesis (grava 0x800e01c0+0xb8 do script)",
            0x3b: "cria objeto de DISPLAY (struct 0x194B; NAO e sce_em_set)",
            0x4c: "CHECK flag (condicional)", 0x4d: "SET/CLEAR flag (inline)"}

# nomes provaveis dos bancos (bank1 provado como progresso; demais por endereco)
BANK_NOTES = {
    0: "0x800cc858  (bloco do gamestruct)",
    1: "0x800d1f2c  PROGRESSO de jogo (player_sm r9/escada le &0x10 aqui)",
    2: "0x800ccba0  (adjacente ao player-struct)",
    3: "0x800d1fa0  flags de mapa/sala",
}


def flag_addr(e, bank, bit):
    base = e.u32(FLAG_BANK_TBL + bank * 4)
    word = base + ((bit >> 3) & 0x1c)
    mask = (0x80000000 >> (bit & 0x1f)) & 0xffffffff
    return word, mask


def ops_report(e):
    print("== jump-table de opcodes SCD @ %08x ==" % SCD_OP_TBL)
    for i in range(72):
        v = e.u32(SCD_OP_TBL + i * 4)
        if not (0x80010000 <= v < 0x800a0000):
            break
        print("  op 0x%02x -> %08x   %s" % (i, v, OP_NOTES.get(i, "")))


def banks_report(e):
    print("== banco de flags @ %08x ==" % FLAG_BANK_TBL)
    for i in range(16):
        v = e.u32(FLAG_BANK_TBL + i * 4)
        print("  bank%-2d -> %08x   %s" % (i, v, BANK_NOTES.get(i, "")))
    print("\n  word = bank_ptr + ((bit>>3)&0x1c) ; mask = 0x80000000 >> (bit&0x1f)")


def pickup_report(e):
    print("== CICLO DO ITEM: pegar / usar / combinar ==\n")
    print("INVENTARIO: struct em *(0x%08x) (gs+0x7c7c); array em 0x%08x (gs+0x79fc)." % (INV_PTR, INV_ARRAY))
    print("  MAIN 10 slots @+0, BOX 64 slots @+0x28, cursor +0x%02x, arma equip +0x%02x, count +0x%02x." % (
        INV_SLOT_CURSOR, INV_SLOT_EQUIP, INV_SLOT_COUNT))
    print("  slot(4B): b0=id(0=vazio) b1=qtd hword+2=flags(0xc000=consumido). stack-max tbl @0x%08x[id].b1." % STACK_MAX_TBL)
    print()
    print("PEGAR (add-to-inventory):")
    print("  1) AOT item/evento (SCE 2, %08x) -> gs+0x21dc = descritor(id@0,qtd@2); janela de obter %08x." % (
        ITEM_EVENT_SCE2, GET_WINDOW_SM))
    print("  2) estado0 %08x: empilha (find_by_id(id) %08x + stack-max) OU find_by_id(0)=1o VAZIO;" % (
        GET_FIND_SLOT, INV_FIND_BY_ID))
    print("     grava obj+0x6e=slot, obj+0x73=flag-empilhar; se cheio -> msg 'sem espaco'.")
    print("  3) estado3 %08x: GRAVA {id,qtd,flags} no slot, ou slot.qtd += qtd (0x8006a0f0)." % GET_WRITE_SLOT)
    print()
    print("USAR/consumir: %08x (dec qtd; GS 8006D0CA 2400). remove/dec %08x ; compact %08x." % (
        ITEM_USE_DEC, INV_REMOVE_DEC, INV_COMPACT))
    print("COMBINAR: menu 0x80064xxx (categorias em stack-max tbl) ; stack-merge %08x." % INV_STACK_MERGE)
    print("AOT item no chao (so modelo visivel): op 0x67 %08x / op 0x68 %08x." % (
        ITEM_AOT_OPS[0x67], ITEM_AOT_OPS[0x68]))


def report(e):
    print("== SLUS_009.23  item_logic / flags  (base %08x) ==\n" % e.base)
    banks_report(e)
    print("\n== rotinas de flag ==")
    print("  SET/CLEAR (struct a0)  %08x   a0[0]=bank a0[2]=bit a0[4]=modo" % FLAG_SET_A)
    print("  SET/CLEAR (inline)     %08x   b1=bank b2=bit b3=modo(0clr/1set)" % FLAG_SET_IP)
    print("  CHECK (condicional)    %08x   b1=bank hw2=bit -> (word&mask)!=0 XOR neg" % FLAG_CHECK)
    print("\n== inventario ==")
    print("  slot = {b0=id, b1=qtd, hw+2=flags(0xc000=vazio)}")
    print("  USO/consumo (decrementa qtd): %08x  (GS 8006D0CA 2400 = uso ilimitado)" % ITEM_USE_DEC)
    print("  PEGAR (add-to-inv): janela de obter %08x; acha slot livre = find_by_id(0) %08x;" % (
        GET_WINDOW_SM, INV_FIND_BY_ID))
    print("     grava {id,qtd} em %08x. (rode 'python tools/exe_items.py pickup')" % GET_WRITE_SLOT)
    print("\n== como um flag muda a sala ==")
    print("  o opcode CHECK (%08x) le um flag de progresso e gateia a execucao do" % FLAG_CHECK)
    print("  script da sala (habilita/desabilita AOTs, portas, presenca de item);")
    print("  codigo de gameplay tambem le bank1 (0x800d1f2c) direto (ex.: escada r9).")


if __name__ == "__main__":
    e = Exe(EXE)
    a = sys.argv
    if len(a) >= 2 and a[1] == "banks":
        banks_report(e)
    elif len(a) >= 2 and a[1] == "ops":
        ops_report(e)
    elif len(a) >= 2 and a[1] == "pickup":
        pickup_report(e)
    elif len(a) >= 3 and a[1] == "flag":
        w, m = flag_addr(e, int(a[2], 0), int(a[3], 0))
        print("bank=%s bit=%s -> word %08x  mask %08x" % (a[2], a[3], w, m))
    elif len(a) >= 3 and a[1] == "fn":
        n = int(a[3]) if len(a) > 3 else 60
        e.disasm(int(a[2], 0), n)
    else:
        report(e)
