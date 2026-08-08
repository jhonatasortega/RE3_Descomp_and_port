#!/usr/bin/env python3
"""Tabelas de MIRA e TIRO do player, lidas do `SLUS_009.23`.

Fonte da leitura: `docs/decomp/notes/exe_combat.md` §1-2 (o `aim_shoot` esta 100%
decompilado la; aqui so extraio os NUMEROS para o port nao ter constante batida no codigo).

O que sai
---------
* **timing** `0x8009cf28` — 21 x 3 bytes por arma; **`byte2 & 0x7f` = o quadro, dentro da
  animacao de mira, em que o tiro sai**. Confere com a nota: faca w0 = 50, handgun w1/w2 = 12,
  magnum w5..w8 = 30.
* **handler de disparo** `0x8009ce88` — 16 ponteiros. `0x8003e494` = faca (contato),
  `0x8003eb28` = hitscan genérico, `0x800408c4` = rocket (projetil/AoE),
  `0x8003ff9c` = granada (projetil/AoE). Vira o campo `tipo` de cada arma.
* **caixa do auto-lock** `0x80098064` e `0x8009806c` — 4 `s16` por descritor, que a rotina de
  teste `0x800445c8` le como meia-extensoes (`lh 0/2/4/6`) no espaco local da mira. Os dois
  primeiros descritores medem `(3000, -1000, 1600, 1000)` e `(3000, +1000, 1600, 1000)`:
  **3000 de alcance, 1600 de altura e +-1000 de largura**, o par espelhado (esquerda/direita).

O que NAO foi achado (declarado)
--------------------------------
O de-para **item -> indice de arma `w`** (o `player+0x46`). Testei o descritor de item
`0x800a0514`: o byte 2 e sempre 0 nas armas e o byte 3 e o **modo/paleta do numero** (Hand Gun 1,
G. Launcher 1/5/9/13 = modo 1 com paletas diferentes), nao o indice. Enquanto nao aparecer a
tabela, o port usa faca = w0 e o resto = w1 (timing do handgun) e isso esta ETIQUETADO no JSON.

Uso: python tools/exe_aim_shoot.py
"""
from __future__ import annotations

import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
from exe_parse import Exe  # noqa: E402

TIMING = 0x8009CF28
N_ARMAS = 21
HANDLERS = 0x8009CE88
N_HANDLERS = 16
CAIXA_A = 0x80098064
CAIXA_B = 0x8009806C
TIPO = {
    0x8003E494: "contato",       # faca
    0x8003EB28: "hitscan",       # generico (0x80044804 + 0x80047860)
    0x800408C4: "projetil",      # rocket launcher
    0x8003FF9C: "projetil",      # granada
}


def s16(v: int) -> int:
    return v - 0x10000 if v & 0x8000 else v


def main() -> int:
    e = Exe(os.path.join(RAIZ, "extracted", "ntsc-u", "SLUS_009.23"))
    armas = []
    for w in range(N_ARMAS):
        a = TIMING + w * 3
        b = [e.u8(a + k) for k in range(3)]
        ptr = e.u32(HANDLERS + w * 4) if w < N_HANDLERS else 0
        armas.append({
            "w": w,
            "bytes": "%02x %02x %02x" % tuple(b),
            "quadro_do_tiro": b[2] & 0x7F,
            "handler": "0x%08x" % ptr if ptr else None,
            "tipo": TIPO.get(ptr, "desconhecido" if ptr else None),
        })
    caixas = []
    for base in (CAIXA_A, CAIXA_B):
        for i in range(4):
            off = base + i * 8
            caixas.append({
                "endereco": "0x%08x" % off,
                "valores": [s16(e.u16(off + k * 2)) for k in range(4)],
            })
    saida = {
        "_fonte": "SLUS_009.23 — ver docs/decomp/notes/exe_combat.md §1-2",
        "timing": {"endereco": "0x%08x" % TIMING, "n": N_ARMAS,
                   "campo": "byte2 & 0x7f = quadro do tiro dentro da animação de mira"},
        "armas": armas,
        "auto_lock": {
            "teste": "0x800445c8",
            "loop": "0x8001e900",
            "arco_clamp": 0x1000,
            "descritores": caixas,
            "leitura": "4 s16 = meias-extensões no espaço local da mira (lh 0/2/4/6)",
        },
        "pitch": {
            "formula": "player+0x6e = (tier << 9) + 0x800",
            "passo": 0x200,
            "sub1_interp": 0x28,
            "poses": {"0": 14, "1": 15, "2": 16, "3": 17,
                      "promocao_alta": {"15": 19, "16": 20, "bit": "player+0xc7 & 0x20",
                                        "facing": "+-0x400"}},
        },
        "item_para_w": {
            "_declarado": "tabela NÃO achada no EXE; faca = w0 e o resto = w1 (handgun)",
            "0x01": 0,
        },
    }
    caminho = os.path.join(RAIZ, "port", "data", "re3_aim_shoot.json")
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, indent=1)
    print("gravado %s" % os.path.relpath(caminho, RAIZ))
    print("quadro do tiro por arma: %s"
          % {("w%d" % a["w"]): a["quadro_do_tiro"] for a in armas})
    print("tipos: %s" % {("w%d" % a["w"]): a["tipo"] for a in armas if a["tipo"]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
