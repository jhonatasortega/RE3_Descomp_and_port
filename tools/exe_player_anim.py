#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Mapa AUTORITATIVO input -> indice de animacao (EDD 0..21) do PLAYER,
extraido do codigo do SLUS_009.23 (RE3 NTSC-U).

Achado central (provado por disassembly):
  * player+0xc8 = INDICE DE SEQUENCIA EDD ATUAL (0..21), 1:1 com animNN do PLD.
    Provado em 0x80018ec8: `lbu v0,0xc8(player); sll v0,3; addu base` -> le
    {u16 nframes, u16 frameOffset, u32 poseStart} (registro EDD de 8 bytes) e
    percorre a frame-list em base+frameOffset (2 bytes/frame). player+0xc9 = frame.

  * A locomocao da Jill on-foot e' uma maquina de estados:
      - player+4 = acao macro (1 = on-foot). Dispatch em 0x80038c7c -> tabela 0x8009cd40.
      - player+5 = rotina (0=idle, 1..15). Dispatch em action1 (0x80039020) via
        DUAS tabelas: T1_move=0x8009cd60 (input) e T2_anim=0x8009cda0 (animacao).
      - T2_anim[rotina] escreve player+0xc8 (a sequencia).

  * A sequencia por rotina vem de uma TABELA 3x3 em 0x8009cde0 indexada por
    "speed tier" (motionType, var 0x8009cd3c, derivada de player+0xcc):
        offset0 (idle r0)      : {2,5,8}
        offset3 (r1 fwd, r4)   : {0,3,6}
        offset6 (r2 down, r6)  : {1,4,7}
    r3 (corrida) NAO usa a tabela: seq 9 (parado) / 10 (movendo)  [0x80039f6c..].

  * Bit de direcao PROVADO: player-pad bit0 (0x01) = FRENTE/UP. T1 r1 (0x8003957c)
    mantem a rotina 1 enquanto (a1 & 1); solta -> volta a idle (routine 0).
    T1 r3 (0x80039ccc) mantem enquanto (a1 & 4). Correr (anim10) tem root-motion
    net(-2057,0) = MESMO eixo -X do andar (anim00) -> corrida pra frente.

Uso: python tools/exe_player_anim.py [caminho_do_exe]
"""
import sys
sys.path.insert(0, "tools")
from exe_parse import Exe

EXE = sys.argv[1] if len(sys.argv) > 1 else "extracted/ntsc-u/SLUS_009.23"


def main():
    e = Exe(EXE)
    print("== SLUS_009.23  base %08x  vend %08x ==\n" % (e.base, e.vend))

    # --- tabela 3x3 de sequencias (0x8009cde0) ---
    T = 0x8009cde0
    b = e.bytes_at(T, 9)
    print("Tabela 3x3 de sequencias @%08x:" % T)
    print("  bytes:", " ".join("%02x" % x for x in b))
    fam = {"idle r0 (off0)": 0, "fwd  r1/r4 (off3)": 3, "back r2/r6 (off6)": 6}
    for name, off in fam.items():
        vals = [e.u8(T + off + t) for t in range(3)]
        print("  %-20s tier0/1/2 -> anim %s" % (name, vals))
    print("  r3 (corrida)         parado->anim9  movendo->anim10")
    print()

    # --- dispatch tables ---
    print("Jill action table @0x8009cd40 (player+4):")
    for i in range(6):
        print("  a%-2d -> %08x" % (i, e.u32(0x8009cd40 + i * 4)))
    print("\nT1_move @0x8009cd60 / T2_anim @0x8009cda0 (player+5=rotina):")
    for i in range(8):
        print("  r%-2d  move=%08x  anim=%08x"
              % (i, e.u32(0x8009cd60 + i * 4), e.u32(0x8009cda0 + i * 4)))
    print()

    # --- mapa final ---
    print("== MAPA acao -> anim (EDD 0..21) ==")
    rows = [
        ("idle / parado",        "anim02", "r0 idle base (motionType0). fidget: anim05/anim08; wait especial: anim21"),
        ("andar FRENTE",         "anim00", "r1 (pad bit0=UP). root -X. tiers -> anim03/anim06"),
        ("CORRER frente",        "anim10", "r3 (pad bit2). root -2057 -X (mesmo eixo do andar)"),
        ("andar TRAS / giro-DOWN","anim01", "r2/r6 (pad bit9=DOWN). tiers -> anim04/anim07"),
        ("dano / knockback",     "anim19/anim20", "acoes de dano da Jill (sb 19@0x8003acb8, 20@0x8003accc)"),
    ]
    for a, idx, ev in rows:
        print("  %-22s = %-12s  # %s" % (a, idx, ev))


if __name__ == "__main__":
    main()
