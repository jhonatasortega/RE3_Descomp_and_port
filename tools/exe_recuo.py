#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""RECUO DO TIRO: prova, lida do `SLUS_009.23`, de que o disparo TEM clipe proprio.

Por que este arquivo existe
---------------------------
A doc do port dizia que "o EXE nao tem clipe de tiro -- o disparo sai num QUADRO DENTRO da
animacao de mira (tabela 0x8009cf28, byte2 & 0x7f = 12 no handgun)". **Esta errado.** O disparo
tem clipe dedicado: as sequencias 1/3/5 do banco 2 do `.PLW` (20 quadros cada), uma por altura de
mira -- os clipes que o `pld2gltf.py` exporta como `mira01`/`mira03`/`mira05`. O recuo E' esse
clipe (sobe e volta em 20 quadros); os `mira02/04/06` de 1 quadro sao os HOLDs.

Este script nao "acha" nada em runtime: ele RECONFERE, palavra de instrucao por palavra de
instrucao, cada sitio que sustenta a conclusao, e sai com codigo != 0 se o binario nao casar.
Serve de regressao para a decomp (se alguem trocar de versao de EXE, ele grita).

Uso:
    python tools/exe_recuo.py            # confere e imprime a tabela
    python tools/exe_recuo.py --dis      # confere e desassembla os sitios

Ver `docs/decomp/notes/recuo_tiro.md` para a prosa completa.
"""
from __future__ import annotations

import os
import struct
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
from exe_parse import Exe  # noqa: E402

EXE = os.path.join(RAIZ, "extracted", "ntsc-u", "SLUS_009.23")

# ── A maquina de MIRA/TIRO do gameplay e a ROTINA 5, nao a 7 ──
# `0x80039738 bgez $v1, 0x80039760` com `sw $v0, 4($s0)` no DELAY SLOT: o write da rotina 5
# acontece SEMPRE (delay slot executa nos dois ramos), e a rotina 7 (`0x20701`) so sobrescreve
# quando `$v1 < 0`, isto e, quando o **bit 31 de `player+0`** esta aceso E `player+0xcc >= 0x15`.
ROTINA5_SITIOS = [0x8003973C, 0x80039788]
ROTINA7_SITIOS = [0x8003975C, 0x800397A8]

# Tabelas de subestado por familia de arma, 11 ponteiros cada (`lbu 6($a0)` em `0x8003eb34`,
# indexando `0x800a0000 - 0x2fd0 = 0x8009d030` em `0x8003eb38`).
TAB_SUBESTADO = {
    0x8009D004: "faca",
    0x8009D030: "generica (handgun e cia)",
    0x8009D05C: "variante 3",
    0x8009D088: "variante 4",
}
N_SUBESTADOS = 11

# O byte da ALTURA de mira (0/1/2). Endereco absoluto: `0x800a0000 - 0x32c3`.
AIM_TIER = 0x8009CD3D

# Sitios que escrevem `player+0xc8` (o word {seq, quadro, +0xca}) no pipeline de arma.
# Cada entrada: (endereco do `sw`, base do word, "soma tier*2"?, papel)
SITIOS_C8 = [
    (0x8003EBBC, 0x00070000, False, "sub 0 LEVANTAR   -> seq 0        (mira00, 10 quadros)"),
    (0x8003EF6C, 0x00070002, True, "sub 1 HOLD       -> seq 2|4|6    (mira02/04/06, 1 quadro)"),
    (0x8003F268, 0x00030001, True, "sub 2 FOGO/RECUO -> seq 1|3|5    (mira01/03/05, 20 quadros)"),
    (0x8003F554, 0x00070007, False, "sub 4 RECARGA    -> seq 7        (mira07, 32 quadros)"),
]

# Fim do clipe de fogo -> volta para o HOLD. `0x8003f344 jal 0x80026be8(player, gs+0x2618,
# gs+0x2614, 0x400)`; se o retorno != 0 (clipe acabou) `0x8003f354 sh 1, 6($s0)` poe
# `player+6 = 1` (hold) e `player+7 = 0` (solta a tranca do "ja comecei").
FIM_DO_FOGO = 0x8003F354
AVANCA_FOGO = 0x8003F344
ANIM_STEP = 0x80026BE8

# O banco de animacao usado: **banco 2 do PLW**. O equipar-arma copia o diretorio do `.PLW` para
# `gs+0x260c/0x2610` (banco 1, pernas) e `gs+0x2614/0x2618` (banco 2, tronco), e e' esse par que
# o pipeline de arma passa ao motor de animacao.
BANCO2 = (0x80043D94, 0x2614)           # sw ..., 0x2614($v1)  <- dir[+0x14]
BANCO1 = (0x80043D64, 0x260C)           # sw ..., 0x260c($v1)  <- dir[+0x08]

# Tabela de limiares por arma. **20 entradas** de 3 bytes (`0x8009cf28`..`0x8009cf63`), e em
# `0x8009cf64` comeca outra tabela de 1 byte por arma. Os tres bytes NAO sao "o quadro do tiro":
#   byte0 & 0x7f  `0x8003ee70`  levantar: se > quadro e pad & 0x20 -> vai para o hold
#   byte1 & 0x7f  `0x8003eec0`  idem com pad & 0x10
#   byte2 & 0x7f  `0x8003f3dc`  FOGO: se soltou a mira e quadro > byte2 -> corta e volta ao hold
#   bit 7 do byte0 `0x8003e454` -> `0x80019318(player,0,bit)`: escolhe o no de referencia de
#                                 correcao de posicao por osso. Nada a ver com recuo.
LIMIARES = 0x8009CF28
N_ARMAS = 20
GIRO = 0x8009CF64                       # 1 byte/arma: &0x7f = taxa de giro; bit7 = pula o cano

# Recuo de VIBRACAO do controle, por arma: 6 bytes, indice `weapon-2` (`0x8003e230`).
VIBRACAO = 0x8009CF90


def _word(e: Exe, va: int) -> int:
    return e.u32(va)


def _checar(cond: bool, msg: str, falhas: list) -> None:
    print("  %s %s" % ("ok  " if cond else "FALHA", msg))
    if not cond:
        falhas.append(msg)


def _lui_ori(e: Exe, va_lui: int, va_ori: int):
    """Devolve o imediato de 32 bits montado por `lui`+`ori` ADJACENTES (ou None)."""
    w1, w2 = e.u32(va_lui), e.u32(va_ori)
    if (w1 >> 26) != 0x0F:                       # lui
        return None
    alto = (w1 & 0xFFFF) << 16
    if (w2 >> 26) != 0x0D:                       # ori
        return None
    return alto | (w2 & 0xFFFF)


def _monta_constante(e: Exe, va_sw: int, base: int, janela: int = 12) -> bool:
    """O `lui`(+`ori`) que monta `base` esta nas `janela` instrucoes antes do `sw`?

    O compilador nao poe os dois lado a lado: em `0x8003ef44` o `lui $v1,7` fica 10 instrucoes
    antes do `ori $v1,$v1,2` de `0x8003ef58`. Por isso a busca e' por PRESENCA na janela, nao
    por adjacencia.
    """
    alto, baixo = base >> 16, base & 0xFFFF
    tem_lui = False
    tem_ori = baixo == 0                          # sem parte baixa nao precisa de `ori`
    for d in range(1, janela + 1):
        w = e.u32(va_sw - d * 4)
        if (w >> 26) == 0x0F and (w & 0xFFFF) == alto:
            tem_lui = True
        if (w >> 26) == 0x0D and (w & 0xFFFF) == baixo:
            tem_ori = True
    return tem_lui and tem_ori


def main() -> int:
    if not os.path.exists(EXE):
        print("EXE ausente: %s (rode tools/extract_iso.py)" % EXE)
        return 2
    e = Exe(EXE)
    falhas: list = []

    print("== 1. a maquina de mira/tiro do gameplay e a ROTINA 5")
    for va in ROTINA5_SITIOS:
        w = e.u32(va)
        # sw $v0, 4($s0)
        _checar((w >> 26) == 0x2B and (w & 0xFFFF) == 4,
                "%08x  sw ..., 4($player)  (delay slot do bgez -> roda SEMPRE)" % va, falhas)
    for va in ROTINA7_SITIOS:
        imm = _lui_ori(e, va - 8, va - 4)
        _checar(imm == 0x00020701,
                "%08x  rotina 7 = 0x%08x, atras de `bgez` (bit 31 de player+0)"
                % (va, imm or 0), falhas)

    print("== 2. as 4 tabelas de subestado, 11 ponteiros cada")
    for base, nome in sorted(TAB_SUBESTADO.items()):
        ptrs = [e.u32(base + i * 4) for i in range(N_SUBESTADOS)]
        ok = all(0x80010000 <= p < 0x80090000 for p in ptrs)
        _checar(ok, "0x%08x %-26s %s" % (base, nome,
                " ".join("%08x" % p for p in ptrs[:5]) + " ..."), falhas)
    # espacamento de 0x2c = 11 ponteiros: as tabelas sao contiguas
    chaves = sorted(TAB_SUBESTADO)
    _checar(all(chaves[i + 1] - chaves[i] == N_SUBESTADOS * 4 for i in range(len(chaves) - 1)),
            "as tabelas sao contiguas de 0x2c em 0x2c = exatamente 11 entradas", falhas)

    print("== 3. os sitios que escrevem player+0xc8 (seq de animacao)")
    for va, base, soma_tier, papel in SITIOS_C8:
        w = e.u32(va)
        ok_sw = (w >> 26) == 0x2B and (w & 0xFFFF) == 0xC8
        _checar(ok_sw and _monta_constante(e, va, base),
                "%08x  sw base=0x%08x  %s" % (va, base, papel), falhas)
        if soma_tier:
            # ...e o `lbu` do byte de altura no meio (0x8009cd3d) + `sll 1`
            achou_tier = any(
                (e.u32(va - d * 4) >> 26) == 0x24                      # lbu
                and ((e.u32(va - d * 4) & 0xFFFF) - 0x10000) + 0x800A0000 == AIM_TIER
                for d in range(1, 10))
            _checar(achou_tier,
                    "         ...somando (0x%08x)*2 = a ALTURA de mira" % AIM_TIER, falhas)

    print("== 4. o clipe de fogo termina e volta para o HOLD")
    w = e.u32(FIM_DO_FOGO)
    _checar((w >> 26) == 0x29 and (w & 0xFFFF) == 6,
            "%08x  sh ..., 6($player) = player+6 = 1 (hold) e player+7 = 0" % FIM_DO_FOGO,
            falhas)
    w = e.u32(AVANCA_FOGO)
    alvo = ((AVANCA_FOGO + 4) & 0xF0000000) | ((w & 0x03FFFFFF) << 2)
    _checar((w >> 26) == 0x03 and alvo == ANIM_STEP,
            "%08x  jal 0x%08x = passo de animacao do banco parcial" % (AVANCA_FOGO, alvo),
            falhas)

    print("== 5. o banco animado e o BANCO 2 do PLW")
    for va, off in (BANCO2, BANCO1):
        w = e.u32(va)
        _checar((w >> 26) == 0x2B and (w & 0xFFFF) == off,
                "%08x  sw ..., 0x%04x($gs)  (diretorio do .PLW -> banco)" % (va, off), falhas)

    print("== 6. tabelas por arma (numeros, sem interpretacao)")
    lim = [tuple(e.u8(LIMIARES + i * 3 + k) for k in range(3)) for i in range(N_ARMAS)]
    print("  0x%08x limiares (20 armas x 3 bytes):" % LIMIARES)
    for i, (b0, b1, b2) in enumerate(lim, start=1):
        print("    w%-2d  b0=0x%02x(%2d, bit7=%d)  b1=0x%02x(%2d)  b2=0x%02x(%2d)"
              % (i, b0, b0 & 0x7F, 1 if b0 & 0x80 else 0, b1, b1 & 0x7F, b2, b2 & 0x7F))
    print("  0x%08x giro/cano (1 byte por arma): %s" % (GIRO,
          " ".join("w%d=0x%02x" % (i + 1, e.u8(GIRO + i)) for i in range(N_ARMAS))))
    print("  0x%08x vibracao do controle (6 bytes por arma, indice weapon-2):" % VIBRACAO)
    for i in range(N_ARMAS - 1):
        bs = [e.u8(VIBRACAO + i * 6 + k) for k in range(6)]
        print("    w%-2d  %s" % (i + 2, " ".join("%02x" % b for b in bs)))

    print("\n== TABELA FINAL (subestado -> sequencia do banco 2 -> clipe exportado)")
    print("  sub 0  LEVANTAR      seq 0        mira00   10 quadros")
    print("  sub 1  HOLD          seq 2|4|6    mira02/04/06   1 quadro  (altura media/alta/baixa)")
    print("  sub 2  FOGO+RECUO    seq 1|3|5    mira01/03/05  20 quadros  <-- O RECUO")
    print("  sub 3  BAIXAR        seq 0 ao CONTRARIO (a3 alto != 0 -> playback reverso)")
    print("  sub 4  RECARGA       seq 7        mira07   32 quadros")
    print("  sub 8/9/10           seqs 13..17 do BANCO 0 (arm13..arm17, corpo inteiro)")

    if falhas:
        print("\n%d CONFERENCIA(S) FALHOU: o binario nao casa com a decomp." % len(falhas))
        return 1
    print("\ntodas as conferencias passaram: o recuo do tiro E' o clipe mira01/03/05.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
