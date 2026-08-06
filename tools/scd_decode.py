#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Decodificador linear do SCD do RE3 usando a tabela de tamanhos de opcode.
Extrai o SCD do .ARD (bloco 8 = RDT, offset_table[16]) e decodifica funcao a funcao
(limites dados pela tabela de ponteiros de funcao). Reporta opcodes desconhecidos."""
import struct, sys, glob, os

SECTOR = 0x800

# =============================================================================
# INTERPRETADOR (VM) DO SCRIPT DE SALA -- LOCALIZADO E VERIFICADO no EXE
# (SLUS_009.23, base 0x80010000). Ver docs/decomp/notes/scd_opcodes.md.
# -----------------------------------------------------------------------------
#  - O SCD (offset_table[16] do RDT) e' o bytecode; o RDT e' carregado pelo
#    room-loader 0x800493ec, que RELOCA a offset_table (soma a base do RDT a
#    cada entrada, s1+8..s1+0x60) -> offset_table[16] vira ponteiro ABSOLUTO
#    para o script. Base do RDT em global 0x800cc86c (gs+0x2134).
#  - JUMP-TABLE da VM = 0x8009e0f8 (256 entradas u32). No boot da sala e'
#    COPIADA p/ o scratchpad 0x1f800000 (memcpy 0x400 bytes em 0x80052a98).
#  - LOOP principal = 0x80052ba4 ; DISPATCH = 0x80052c48:
#        lw   $v0, 0x1c($s0)        ; PC do script (campo +0x1c do obj de script)
#        lbu  $v0, ($v0)            ; opcode
#        sll  $v0, $v0, 2
#        lui  $v1, 0x1f80 ; addu ; lw $v0,($v0) ; jalr $v0   ; a0 = obj de script
#     retorno do handler: 1 = continua (re-dispatch) ; 2 = fim (evt_end 0x01).
#  - INIT do PC (gosub/thread start) = 0x80052474:
#        PC(obj+0x1c) = script_base + func_offset[id]   (func_offset = tabela u16
#        no inicio do script; script_base = RDT + offset_table[16]).
#  - Cada handler LE seus operandos de PC(=+0x1c) e AVANCA o PC por N bytes ->
#    os tamanhos abaixo sao os avancos REAIS lidos dos handlers (nao mais
#    inferidos por restricao). Opcodes de controle (if/while/switch/gosub)
#    escrevem o PC diretamente (desvio) em vez de avanco fixo.
#  - NAO confundir: 0x8009e0bc / dispatch 0x80050aac = VM de EVENTO/AOT
#    (per-frame, opcodes compactos 0x67->6). 0x8007688c = VM de IA de entidade.
# =============================================================================
VM_JUMP_TABLE   = 0x8009e0f8   # base da jump-table (op*4), copiada p/ scratchpad
VM_SCRATCHPAD   = 0x1f800000
VM_MAIN_LOOP    = 0x80052ba4
VM_DISPATCH     = 0x80052c48
VM_PC_INIT      = 0x80052474   # obj+0x1c = script_base + func_offset[id]
VM_TABLE_COPY   = 0x80052a98   # memcpy 0x8009e0f8 -> 0x1f800000 (0x400 B)

# Handlers notaveis (endereco EXE do handler de cada opcode; = *(0x8009e0f8+op*4)):
#   0x06 -> 0x800512fc  (flag check/set; MESMO handler do banco de flags 0x8009e3f8)
#   TODOS os 0x61..0x68 REGISTRAM um AOT: gs+0x2158[id] = &(opcode+2). O SCE type
#   (byte@+2) e' que decide o comportamento no toque (jump-table 0x8009e0bc):
#     sce==1 -> PORTA (produtor 0x80050d28); sce==2 -> outro AOT; 4=msg,6=flag,8=move...
#   0x61 -> 0x80055b5c  aot_set 32B  (sce==1 => DOOR_AOT_SET; destino em +0x16/+0x17)
#   0x62 -> 0x80055bbc  aot_set 40B  (sce==1 => DOOR_AOT_SET_4P; liga byte@+3|=0x80 ->
#                                     path 0x14; destino em +0x1e/+0x1f)
#   0x63 -> 0x80055c34  aot_set 20B          0x64 -> 0x80055c94  aot_set_4p 28B
#   0x67 -> 0x800574f4  aot_set 22B (sce==2, NAO e' porta -- erro do round antigo)
#   0x68 -> 0x800576c4  aot_set 30B (item)   0x7b -> 0x80055568  map data write (6B)
#   0x7f -> 0x80056510  monta struct de colisao 0x194 (quad 3D), NAO carrega destino.
#   Ver tools/scd_door_dest.py e docs/decomp/notes/door_handler.md.

# Tamanhos de opcode (bytes, inclui o opcode) -- AUTORITATIVO, lido dos avancos
# de PC dos handlers da VM (jump-table 0x8009e0f8). "CONFIRMADO_VM".
# Correcao vs versao antiga (constraint-fit): a "porta de 62B" era o PAR
# 0x67(22B) + 0x7f(40B) = 62; 0x62=40 (era 32); 0x64=28 (ja batia).
CONFIRMADO_VM = {
 0x00:1,0x01:1,0x02:1,0x03:4,0x04:4,0x05:2,0x06:4,0x08:2,0x09:1,0x0a:3,0x0b:1,0x0c:1,
 0x0d:6,0x0e:5,0x12:4,0x13:2,0x14:4,0x15:6,0x16:2,0x17:2,0x1c:1,0x1d:4,0x1e:4,0x1f:3,
 0x20:6,0x21:4,0x22:2,0x23:1,0x25:4,0x26:6,0x27:1,0x28:1,0x29:8,0x2b:2,0x2c:4,0x2d:4,
 0x2e:6,0x30:6,0x34:10,0x35:6,0x36:3,0x37:2,0x38:2,0x39:16,0x3a:16,0x3d:2,0x3e:2,0x3f:3,
 0x40:4,0x41:3,0x42:3,0x43:6,0x44:6,0x45:4,0x46:11,0x47:3,0x48:4,0x49:1,0x4a:1,0x4c:4,
 0x4d:4,0x4e:6,0x4f:1,0x50:2,0x51:1,0x52:2,0x53:3,0x54:4,0x55:8,0x56:8,0x57:6,0x58:6,
 0x59:8,0x5a:2,0x5b:6,0x5c:2,0x5d:1,0x5e:3,0x5f:2,0x60:22,0x61:32,0x62:40,0x63:20,0x64:28,
 0x65:10,0x66:2,0x67:22,0x68:30,0x69:14,0x6a:16,0x6b:2,0x6c:4,0x6d:4,0x6e:4,0x6f:2,0x70:16,
 0x71:18,0x72:22,0x73:24,0x74:5,0x75:2,0x76:3,0x79:4,0x7a:2,0x7b:6,0x7c:1,0x7e:2,0x7f:40,
 0x80:4,0x83:1,0x84:4,0x85:2,0x86:1,0x87:1,0x88:4,0x89:2,0x8a:1,0x8b:1,0x8c:1,0x8d:1,0x8e:4,0x8f:2,
}
# Opcodes de CONTROLE de fluxo (a VM escreve o PC diretamente / avanco calculado);
# os valores sao o "tamanho da instrucao" p/ varredura linear (o desvio e' tratado
# a parte). 0x19 gosub salva PC+2 e desvia; 0x07 if, 0x10 while, 0x2a switch, etc.
#
# CORRECOES ROUND 100% (5 tamanhos RE-LIDOS BYTE-A-BYTE do epilogo do handler; cada
# handler tem UM unico writeback de PC e UM unico `jr $ra` -> avanco INCONDICIONAL,
# nao e' inferencia). Com estes 5 => fechamento 99.95% -> 100.00% (4238/4238) e ZERO
# opcodes invalidos em TODAS as 169 salas:
#   0x3b: 1 -> 3   handler 0x80057f84; epilogo 0x80058604: lw+addiu $v1,$v1,3+sw 0x1c
#                  (le byte@+1 e byte@+2; era o "opcode raro nao isolavel" -> RESOLVIDO;
#                   fecha R208 func0). ret1.
#   0x3c: 2 -> 1   handler 0x80057cf8; epilogo 0x80057db0: lw+addu($v0=1)+sw 0x1c
#                  (weapon/inv check, le player+0x46). Fecha o drift de R123 func17.
#   0x24: 2 -> 1   handler 0x80058cd0; epilogo 0x80058dac: lw+addu($v0=1)+sw 0x1c
#                  (event-state check, le global 0x800d1f94). Fecha R211 func44.
#   0x2f: 2 -> 1   handler 0x80055004; epilogo 0x80055018: lw+addu($v0=1)+sw 0x1c.
#   0x4b: 2 -> 1   handler 0x80054628; epilogo 0x800546ac: lw+addu($v0=1)+sw 0x1c.
# (Os antigos scans erravam por so rastrear `addiu` e nao `addu rt,rt,rN` no epilogo,
#  e por confundir `sw ...,0x1c($sp)` [save de $ra na pilha] com o PC em `0x1c($obj)`.)
CONTROLE_VM = {
 0x07:4,0x0f:2,0x10:4,0x11:2,0x18:6,0x19:2,0x1a:2,0x1b:2,0x24:1,0x2a:6,0x2f:1,0x31:6,
 0x32:6,0x33:4,0x3b:3,0x3c:1,0x4b:1,0x77:12,0x78:6,0x7d:24,0x81:8,0x82:10,
}

# ---- compat com codigo antigo (CONFIRMADO/ALTA/UNCERTAIN) ----
CONFIRMADO = dict(CONFIRMADO_VM)
ALTA = dict(CONTROLE_VM)
UNCERTAIN = {}
# SIZES = tabela definitiva da VM (fixos + controle). Fecha as funcoes das 169 salas.
SIZES = dict(CONFIRMADO_VM); SIZES.update(CONTROLE_VM)
VM_SIZES = dict(SIZES)

# =============================================================================
# ESPACO DE OPCODES E SEMANTICA -- FECHAMENTO (round 100%)
# -----------------------------------------------------------------------------
# ACHADO 1 (espaco de opcodes): a jump-table 0x8009e0f8 tem handlers VALIDOS
#   SOMENTE para op 0x00..0x8f (144 opcodes). 0x90/0x91 = 0x00000000 (invalido);
#   0xc0..0xf1 = e' a TABELA DE BANCOS DE FLAGS 0x8009e3f8 (=0x8009e0f8+0xc0*4),
#   que fica logo depois e foi copiada junto no memcpy de 0x400 B. => NAO existem
#   opcodes >= 0x90 no SCD. O "~3% que nao fechava" NAO era opcode raro >=0x90 e
#   sim DRIFT da varredura linear por tamanhos errados + o cabecalho do switch.
#
# ACHADO 2 (divergencia 0x14 RESOLVIDA): handler 0x80053638 le var(u8)@+1,
#   count(u16)@+2 e a case-table comeca em +4 => o CABECALHO do switch = 4 BYTES
#   (o 4B do reevengi esta CORRETO; o "6B" da prosa antiga e o "2" do codigo
#   estavam errados). So corrigir 0x14=4 sobe o fechamento 97.07% -> 99.10%.
#
# ACHADO 3 (7 tamanhos relidos dos handlers): 0x03=4(0x80052e78 le +3, par do 0x04),
#   0x0e=5(0x80053228, PC+5 no continue), 0x14=4(switch), 0x2a=6(0x80058918 le +4/+5),
#   0x31=6(0x80055944), 0x32=6(0x800559a0), 0x6e=4(0x800556e0 addiu +4).
#   Com os 7 => fechamento de funcao = 4236/4238 = 99.95% nas 169 salas.
# ACHADO 4 (ROUND 100% -- FECHAMENTO TOTAL): os "2 residuos" (R123 func17 e R208
#   func0) NAO eram dado-embutido-genuino/opcode-raro -- eram DRIFT causado por 5
#   tamanhos de opcode ainda errados na tabela, agora RE-LIDOS do epilogo dos
#   handlers (ver CONTROLE_VM): 0x3b=3, 0x3c=1, 0x24=1, 0x2f=1, 0x4b=1. Cada handler
#   tem UM unico writeback `sw PC,0x1c($obj)` precedido de `addiu/addu +N`, com UM
#   unico `jr $ra` => avanco fixo INCONDICIONAL (verdade do binario, nao restricao).
#     - 0x3b=3 fecha R208 func0 (o "opcode raro" era so tamanho errado: 1 -> 3).
#     - 0x3c=1 fecha o drift de R123 func17 (o byte 0xd3@+0x2ae que parecia
#       "opcode invalido / dado inline" era coord s16 dentro do operando de um 0x6a
#       AOT (16B) -- a varredura desincronizava por 0x3c=2 e reancorava em +0x2a1
#       `47 04 01`+`6a`, padrao identico ao 0x6a limpo em +0x06b da mesma func).
#     - 0x24=1 fecha R211 func44 (`...24|01|00`: com 0x24=1 o `01` vira evt_end).
#   RESULTADO: 4238/4238 = 100.00% das funcoes decodificam so com opcodes validos
#   (0x00..0x8f) e ZERO opcodes invalidos, nas 169 salas. Nao ha mais residuo.
OPCODE_SPACE = range(0x00, 0x90)   # 144 opcodes validos; >= 0x90 nao existe
SCD_CLOSURE = (4238, 4238)         # 100%: TODAS as funcoes fecham (169 salas)

# Semantica por opcode (nome + evidencia). Handler = *(0x8009e0f8 + op*4).
# Marcas: nome sem "?" = provado no handler; com "?" = inferido pelo call-target.
OPCODE_SEM = {
 0x00:("nop","adv1, ret1"),
 0x01:("evt_end/return","pop pilha de chamada obj+2; ret2 se vazia, senao restaura PC@obj+0x144"),
 0x02:("evt_next/chain","adv1, ret2"),
 0x03:("evt_exec (fork id@+3)","chama 0x8005242c(a1=byte+3); 4B; par do 0x04"),
 0x04:("evt_exec (thread start)","chama 0x80052478(a0=byte+1, arg+3); 4B"),
 0x05:("?","adv2"), 0x06:("if_begin/block","push (PC+4+u16@+2) na pilha de loop obj+0x140; 4B"),
 0x07:("else/endif","pop 0x140; PC += u16@+2"), 0x08:("end-block","pop 0x140"),
 0x09:("?","adv1"), 0x0a:("evt_yield?","adv3, ret2"), 0x0b:("?","adv1"), 0x0c:("?","adv1, ret2"),
 0x0d:("for (begin)","6B; push frame de loop"), 0x0e:("while/for-var (begin)","5B; peek var@+5; salta na saida"),
 0x0f:("?","adv2"), 0x10:("ewhile/while","chama 0x80053550; 4B"), 0x11:("break/loop-exit","restaura PC de obj+0x20"),
 0x12:("?","adv4"), 0x13:("ewhile2","chama 0x80053550; 2B"),
 0x14:("switch","4B: 14 var(u8) count(u16); case-table @+4 (handler 0x80053638)"),
 0x15:("case","6B (entrada da case-table)"), 0x16:("esac/end-switch","2B (marca t4=0x16 no scan)"),
 0x17:("default","2B (marca t3=0x17 no scan)"), 0x18:("for/loop frame begin","salta por s16@+4; frame obj+0x140"),
 0x19:("gosub (call func id@+1)","2B; PC=func_offset[id]; ret salvo em obj+0x144"),
 0x1a:("loop-back/next","restaura PC de obj+0x144"), 0x1b:("next-case","salta pela tabela switch obj+0x60"),
 0x1c:("?","adv1"), 0x1d:("?","adv4"), 0x1e:("?","adv4"), 0x1f:("?","adv3"),
 0x20:("? (0x80053a54)","6B"), 0x21:("? (0x80053a54)","4B"), 0x22:("?","adv2"), 0x23:("nop (=h0x00)","adv1"),
 0x24:("event/msg state check","1B: handler 0x80058cd0; le global 0x800d1f94; epilogo 0x80058dac PC+=1; ret1"),
 0x25:("boss/Nemesis event","0x80058c70; struct 0x800e01c0; 4B (ver exe_ai.md)"),
 0x26:("? boss (0x80048308)","6B"), 0x27:("?","adv1"), 0x28:("?","adv1"), 0x29:("? (0x800181cc)","8B"),
 0x2a:("? (0x80058918)","6B; le u16@+4"), 0x2b:("?","adv2"), 0x2c:("?","4B"),
 0x2d:("message/texto","chama 0x80028e4c; 4B"), 0x2e:("message/texto","chama 0x80028cc4; 6B"),
 0x2f:("message/janela","1B: handler 0x80055004; chama 0x80028e18; draw 0x800746c0; epilogo 0x80055018 PC+=1"),
 0x30:("work-var set/get","6B; indexa tabelas de var gs"), 0x31:("work-var op","6B"), 0x32:("work-var op","6B"),
 0x33:("?","4B"), 0x34:("entity-slot update (EM_UPDATE)","chama 0x8001ba48; 10B"), 0x35:("?",""),
 0x36:("item/inventario check","find-slot 0x8006cc8c; 3B"), 0x37:("model-loaded check","0x80078904/0x800788dc"),
 0x38:("?","2B"), 0x39:("?","16B"), 0x3a:("?","16B"),
 0x3b:("entity-spawn/reset (gs+0x2120)","3B: handler 0x80057f84; le byte@+1/+2; monta struct 0x194; epilogo 0x80058604 PC+=3; ret1"),
 0x3c:("weapon/inv check","1B: handler 0x80057cf8; le player+0x46 (arma); 0x8006cc8c; epilogo 0x80057db0 PC+=1"), 0x3d:("?","2B"),
 0x3e:("item check","0x8006cc8c/0x8006cd68; 2B"), 0x3f:("?","3B"),
 0x40:("calc/set var","0x80053e10; 4B"), 0x41:("calc/set var","0x80053e10; 3B"),
 0x42:("calc/set var","0x80053fac; 3B"), 0x43:("calc/set var","0x80053fac; 6B"),
 0x44:("calc","0x800541f0/0x80053a54; 6B"), 0x45:("calc","0x800541f0/0x80053a54; 4B"),
 0x46:("? (0x8002a35c)","11B"), 0x47:("?","3B"), 0x48:("?","4B"), 0x49:("?","1B"), 0x4a:("?","1B"),
 0x4b:("camera/pos accumulate","1B: handler 0x80054628; le obj+0x158..; soma em 0x800e0150; epilogo 0x800546ac PC+=1"), 0x4c:("?","4B"), 0x4d:("?","4B"),
 0x4e:("?","6B"), 0x4f:("?","1B"), 0x50:("? (0x800549c4)","2B"), 0x51:("? (0x800549c4)","1B"),
 0x52:("?","2B"), 0x53:("? (0x8002a938)","3B"), 0x54:("?","4B"), 0x55:("som? (0x80034124)","8B"),
 0x56:("?","8B"), 0x57:("som/SE (0x80038678)","6B"), 0x58:("som/SE (0x80038704)","6B"),
 0x59:("som/SE (0x8003879c)","8B"), 0x5a:("?","2B"), 0x5b:("? (0x8002fd30)","6B"),
 0x5c:("? (0x80048974)","2B"), 0x5d:("?","1B"), 0x5e:("message/janela (largura)","0x80028e4c; ret 320; 3B"),
 0x5f:("item check","0x8006cc8c; 2B"),
 0x60:("char/model spawn","handler 0x80016334; class@+2->char+0x4a, model@+1, pos; 22B (indexa MODEL_TBL 0x800ba728)"),
 0x61:("aot_set/entidade 32B","sce type@+2; sce==1 => DOOR (dest +0x16/+0x17)"),
 0x62:("aot_set/entidade 40B","sce type@+2; sce==1 => DOOR_4P (dest +0x1e/+0x1f)"),
 0x63:("sce_aot_set (trigger AABB)","20B"), 0x64:("sce_aot_set_4p (quad)","28B"),
 0x65:("aot_reset","10B"), 0x66:("aot?","2B"), 0x67:("door_aot_set","22B"), 0x68:("item_aot_set","30B"),
 0x69:("aot (0x8001a200)","14B"), 0x6a:("aot (0x8001a1d8)","16B"), 0x6b:("item check aot (0x8006cc8c)","2B"),
 0x6c:("aot","4B"), 0x6d:("aot","4B"), 0x6e:("aot member set","4B"), 0x6f:("aot","2B"),
 0x70:("sce_em_set/spawn obj","SPAWN_OBJ 0x8001b484; 16B"), 0x71:("sce_em_set/spawn obj","0x8001b484; 18B"),
 0x72:("sce_em_set/spawn obj","0x8001b484; 22B"), 0x73:("sce_em_set/spawn obj","0x8001b484; 24B"),
 0x74:("motion/anim trigger","MOTION_TRIG 0x8001b894; 5B"), 0x75:("motion/anim trigger","0x8001b894; 2B"),
 0x76:("motion/anim trigger","0x8001b894; 3B"), 0x77:("entity update","12B"),
 0x78:("sub-dispatch por byte@+2","tabela 0x80010bb0[b]; 6B"), 0x79:("? (0x80011df4)","4B"),
 0x7a:("? (0x800321c4)","2B"), 0x7b:("map data write","0x80078498; 6B"), 0x7c:("?","1B"),
 0x7d:("sce_em_set (spawn char de combate)","handler 0x80056a2c; 24B (ver sce_em_set.md)"),
 0x7e:("?","2B"), 0x7f:("door dest/arrival","handler 0x80056510; 40B"),
 0x80:("?","4B"), 0x81:("?","8B"), 0x82:("?","10B"), 0x83:("som? (0x80034124)","1B"), 0x84:("?","4B"),
 0x85:("?","2B"), 0x86:("?","1B"), 0x87:("?","1B"), 0x88:("?","4B"), 0x89:("?","2B"),
 0x8a:("som? (0x80034124)","1B"), 0x8b:("?","1B"), 0x8c:("?","1B"), 0x8d:("?","1B"),
 0x8e:("?","4B"), 0x8f:("? (0x800261ac)","2B"),
}

def rdt_of(data):
    fsz,bc = struct.unpack_from("<II", data, 0)
    lens = [struct.unpack_from("<I", data, 8+i*8)[0] for i in range(bc)]
    cur = SECTOR; starts=[]
    for i in range(bc):
        starts.append(cur)
        cur = (cur+lens[i]+SECTOR-1)//SECTOR*SECTOR
    return data[starts[8]:starts[8]+lens[8]]

def script_of(rdt):
    n_off = 22
    offs = struct.unpack_from("<%dI" % n_off, rdt, 8)
    so = offs[16]
    return so

def decode_room(path, sizes=SIZES, verbose=False):
    data = open(path,"rb").read()
    rdt = rdt_of(data)
    so = script_of(rdt)
    # tabela de ponteiros de funcao
    tbl_size = struct.unpack_from("<H", rdt, so)[0]
    nfunc = tbl_size//2
    func_offs = list(struct.unpack_from("<%dH" % nfunc, rdt, so))
    # limites: fim do script = inicio de outra secao ou fim do rdt; usamos proxima func
    results=[]  # (func_idx, list of (rel_off, opcode, size, bytes))
    unknown=set()
    for fi in range(nfunc):
        start = so + func_offs[fi]
        end = so + (func_offs[fi+1] if fi+1<nfunc else None) if fi+1<nfunc else None
        if end is None:
            # ate o proximo bloco: usa fim do rdt (com folga) — para a func final
            end = len(rdt)
        pc = start
        insns=[]
        ok=True
        while pc < end:
            op = rdt[pc]
            if op == 0x01 and pc>=start:  # evt_end
                insns.append((pc-start, op, 1, rdt[pc:pc+1]))
                pc += 1
                # alinhamento: pula nops ate o proximo func offset
                break
            sz = sizes.get(op)
            if sz is None:
                unknown.add(op)
                insns.append((pc-start, op, None, rdt[pc:pc+8]))
                ok=False
                break
            insns.append((pc-start, op, sz, rdt[pc:pc+sz]))
            pc += sz
        results.append((fi, start, insns, ok))
    return results, unknown, rdt, so

if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv)>1 else "extracted/ntsc-u/CD_DATA/STAGE1/R100.ARD"
    res, unk, rdt, so = decode_room(path, verbose=True)
    print("sala:", os.path.basename(path), "| script@0x%x | funcs=%d" % (so, len(res)))
    print("opcodes desconhecidos encontrados:", sorted('0x%02x'%u for u in unk))
    for fi,start,insns,ok in res:
        flag = "OK" if ok else "**PAROU (opcode desconhecido)**"
        last = insns[-1] if insns else None
        print(" func %2d @+0x%03x  n_insn=%d  %s" % (fi, start-so, len(insns), flag))
        if not ok and last:
            print("    -> op 0x%02x @+0x%x bytes=%s" % (last[1], last[0], ' '.join('%02x'%b for b in last[3])))
