#!/usr/bin/env python3
"""Extrai a TABELA SIN/COS do EXE (SLUS_009.23) -> `<out>/data/ps1_sincos.json`.

Base do item P0-05 do port: o RE3 não usa float — ângulo é inteiro de 12 bits
(4096 = 360°) e seno/cosseno vêm de uma tabela de QUARTO DE ONDA no executável.
Sem esta tabela, qualquer rotação no port é aproximação.

Fatos (docs/formatos/exe.md, godot/data/physics.json -> sin_cos_table):
    endereço 0x800a3310 · file offset 0x93b10 · 1025 × s16 · amplitude 4096
    cobertura: índices 0..1024 = 0..90° (quarto de onda)
    rsin(a): a<1024 -> T[a] | a<2048 -> T[2048-a] | a<3072 -> -T[a-2048] | senão -T[4096-a]
    rcos(a) = rsin(a + 1024)

Uso:
    python tools/exe_sincos.py                 # extrai + valida
    python tools/exe_sincos.py --exe <arq>     # outro executável
"""
import json
import math
import os
import struct
import sys

import paths

EXE_DEFAULT = paths.extracted("SLUS_009.23")
FILE_OFFSET = 0x93B10
RAM_ADDR = 0x800A3310
N = 1025
AMPLITUDE = 4096
FULL_CIRCLE = 4096


def rsin(t, a):
    """Reconstrói sin(a) em ponto-fixo (escala 4096) por simetria — igual ao EXE."""
    a &= FULL_CIRCLE - 1
    if a < 1024:
        return t[a]
    if a < 2048:
        return t[2048 - a]
    if a < 3072:
        return -t[a - 2048]
    return -t[4096 - a]


def validate(t):
    """Prova o que dá para provar sobre a tabela, sem 'confiar'."""
    ok = True
    checks = []

    checks.append(("1025 entradas", len(t) == N))
    checks.append(("T[0] == 0", t[0] == 0))
    checks.append(("T[1024] == 4096 (sin 90 = 1.0)", t[1024] == AMPLITUDE))
    checks.append(("monotônica crescente", all(t[i] <= t[i + 1] for i in range(N - 1))))
    checks.append(("0 <= T <= 4096", min(t) == 0 and max(t) == AMPLITUDE))

    # a tabela do jogo é exatamente o seno arredondado?
    err = max(abs(t[i] - round(AMPLITUDE * math.sin(i * math.pi / 2 / 1024))) for i in range(N))
    checks.append((f"== round(4096*sin(i*pi/2/1024)) (erro máx {err})", err == 0))

    # simetria: os 4096 ângulos reconstruídos batem com o seno arredondado?
    err2 = max(abs(rsin(t, a) - round(AMPLITUDE * math.sin(a * 2 * math.pi / FULL_CIRCLE)))
               for a in range(FULL_CIRCLE))
    checks.append((f"simetria fecha nos 4096 ângulos (erro máx {err2})", err2 <= 1))

    # identidades em ponto-fixo
    quad = [(a, rsin(t, a) ** 2 + rsin(t, a + 1024) ** 2) for a in range(0, FULL_CIRCLE, 7)]
    worst = max(abs(v - AMPLITUDE ** 2) for _a, v in quad)
    checks.append((f"sin²+cos² ~ 4096² (desvio máx {worst}, {100.0*worst/AMPLITUDE**2:.3f}%)",
                   worst <= AMPLITUDE ** 2 * 0.001))

    for nome, passou in checks:
        print(f"  [{'ok' if passou else 'FALHA'}] {nome}")
        ok = ok and passou
    return ok


def main(argv):
    exe = argv[argv.index("--exe") + 1] if "--exe" in argv else EXE_DEFAULT
    if not os.path.isfile(exe):
        sys.exit(f"ERRO: executável não encontrado: {exe}")
    b = open(exe, "rb").read()
    t = list(struct.unpack_from("<%dh" % N, b, FILE_OFFSET))
    print(f"exe: {exe}\ntabela: {N} × s16 em file offset {FILE_OFFSET:#x} (RAM {RAM_ADDR:#x})")
    ok = validate(t)

    out = paths.data("ps1_sincos.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump({
        "_meta": {
            "descricao": "tabela sin/cos de quarto de onda do RE3 (PS1 NTSC-U)",
            "gerado_por": "tools/exe_sincos.py",
            "exe": os.path.basename(exe),
            "ram_addr": hex(RAM_ADDR), "file_offset": hex(FILE_OFFSET),
            "entradas": N, "tipo": "s16", "amplitude": AMPLITUDE,
            "full_circle": FULL_CIRCLE, "bits": 12, "half_turn": FULL_CIRCLE // 2,
            "graus_por_unidade": 360.0 / FULL_CIRCLE,
            "cobertura": "índices 0..1024 = 0..90 graus (quarto de onda)",
            "rsin_por_simetria": ["a<1024: T[a]", "a<2048: T[2048-a]",
                                  "a<3072: -T[a-2048]", "senão: -T[4096-a]"],
            "rcos": "rsin(a + 1024)",
            "achado": ("a tabela é EXATAMENTE round(4096*sin(i*pi/2/1024)) — erro 0 nas 1025 "
                       "entradas; ou seja, o port pode conferir sua implementação contra o dado "
                       "real sem margem de dúvida."),
            "validacao_ok": ok,
        },
        "quarter_wave": t,
    }, open(out, "w", encoding="utf-8"), indent=1)
    print(f"OK -> {out}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
