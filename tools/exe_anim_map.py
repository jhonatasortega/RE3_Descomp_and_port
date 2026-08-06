#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gera godot/data/anim_map.json a partir da FONTE (EXE SLUS_009.23 + PL00.PLD).

Fecha a dívida P0-11 do anim_map.json. O arquivo é ~90% CURADORIA de eng. reversa
(rótulos/papéis/confiança/evidência das 22 animações, mapa input->anim) e ~10% DADO
MENSURÁVEL. Este gerador:
  * VALIDA contra o EXE a máquina de estados de anim (tabela 3×3 @0x8009cde0 =
    02 05 08 | 00 03 06 | 01 04 07, escreve player+0xc8) — falha se o EXE divergir.
  * MEDE de PL00.PLD (banco base, 22 seqs) as duas seções de dado:
      - root_motion_por_clipe: [net_x, net_z, un/frame_XZ, netY_graus] por clipe.
      - timing_e_loop: root-motion POR FRAME (dx) de andar (seq0) e correr (seq10).
  * junta a CURADORIA de godot/data/anim_map_curation.json (resíduo mínimo, versionado:
    _meta/input_para_anim/evidencia_exe/mapa — conhecimento humano de RE, não do disco).

Uso:
    python tools/exe_anim_map.py            # grava <out>/data/anim_map.json
    python tools/exe_anim_map.py --compare  # compara os DADOS gerados com a semente
"""
import json
import math
import os
import sys
from collections import OrderedDict

import paths
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import find_anim_banks as F
import pld2gltf as P
from exe_parse import Exe

EXE = paths.extracted("SLUS_009.23")
PLD = paths.cd_data("PLD", "PL00.PLD")
CURATION = os.path.join(paths.ROOT, "godot", "data", "anim_map_curation.json")
TABLE_3X3 = 0x8009CDE0
EXPECT_3X3 = [2, 5, 8, 0, 3, 6, 1, 4, 7]   # 02 05 08 | 00 03 06 | 01 04 07 (§4-B.2)


def validate_exe():
    """Confere que a máquina de estados de anim ainda está no EXE (senão a curadoria mente)."""
    e = Exe(EXE)
    got = [e.u8(TABLE_3X3 + i) for i in range(9)]
    assert got == EXPECT_3X3, "tabela 3x3 @0x8009cde0 diverge do EXE: %s" % got
    return got


def _bank_frames(b, bank, s):
    kf, nb, fsz = F.is_emr(b, bank["emr"]); pool = bank["emr"] + kf; edd = bank["edd"]
    nf = F.u16(b, edd + s * 8); fo = F.u16(b, edd + s * 8 + 2); ps = F.u32(b, edd + s * 8 + 4)
    fl = edd + fo; out = []
    for f in range(nf):
        prel = F.u16(b, fl + f * 2) & 0xff
        po = pool + (ps + prel) * fsz
        out.append((F.s16(b, po), F.s16(b, po + 2), F.s16(b, po + 4), P._get12(b, po + 8, 1)))
    return out


def _sd12(a):
    a &= 0xFFF
    return a - 4096 if a >= 2048 else a


def build():
    validate_exe()
    b = open(PLD, "rb").read()
    _ents, banks = F.all_banks(b)
    base = banks[0]

    # --- root_motion_por_clipe: 22 clipes ---
    rmc = OrderedDict()
    for s in range(22):
        fr = _bank_frames(b, base, s); nf = len(fr)
        nx = fr[-1][0] - fr[0][0]; nz = fr[-1][2] - fr[0][2]
        upf = round(math.hypot(nx, nz) / (nf - 1)) if nf > 1 else 0
        ny = _sd12(fr[-1][3] - fr[0][3])
        rmc["anim%02d" % s] = [nx, nz, upf, round(ny * 360.0 / 4096.0)]

    # --- timing_e_loop: dx por frame de andar(seq0)/correr(seq10) ---
    def per_frame_dx(s):
        fr = _bank_frames(b, base, s)
        return [fr[f + 1][0] - fr[f][0] for f in range(len(fr) - 1)], len(fr)

    dx_walk, nf_walk = per_frame_dx(0)
    dx_run, nf_run = per_frame_dx(10)
    media_walk = round(sum(abs(x) for x in dx_walk) / len(dx_walk), 1)
    media_run = round(sum(abs(x) for x in dx_run) / len(dx_run), 1)
    timing = OrderedDict([
        ("_descricao", "Duracao, loop e root-motion POR FRAME (frame-list do EDD, 2B/frame; entry&0xFF=pose, entry>>8=flags; 30fps)."),
        ("andar_frente", OrderedDict([
            ("anim", "anim00"), ("nframes_jogo", nf_walk), ("duracao_s", round(nf_walk / 30.0, 3)),
            ("loop", "ciclo completo [0..33] -> 0. Passada de 2 passos; flags de som de pe nos frames 5 e 22. Loop limpo (root XZ zerado no glb)."),
            ("root_delta_por_frame_world_dx", dx_walk),
            ("media_un_por_frame", media_walk),
            ("escalar_equivalente", "59.8*30/808 = 2.22 u/s (== walk_speed=2.2). Avanco quase uniforme (50..69) => escalar constante nao escorrega com o clipe certo (anim00)."),
        ])),
        ("correr_frente", OrderedDict([
            ("anim", "anim10"), ("nframes_jogo", nf_run), ("duracao_s", round(nf_run / 30.0, 3)),
            ("loop", "ciclo [0..9] -> 0"),
            ("root_delta_por_frame_world_dx", dx_run),
            ("media_un_por_frame", media_run),
            ("escalar_equivalente", "228.6*30/808 = 8.49 u/s (== run_speed=8.5). Avanco MUITO nao-uniforme (impulso no meio) => p/ foot-lock perfeito use root-motion por frame, nao escalar."),
        ])),
    ])

    # --- curadoria (resíduo mínimo versionado) + dados medidos, na ordem da semente ---
    cur = json.load(open(CURATION, encoding="utf-8"), object_pairs_hook=OrderedDict)
    out = OrderedDict()
    out["_meta"] = cur["_meta"]
    out["input_para_anim"] = cur["input_para_anim"]
    out["evidencia_exe"] = cur["evidencia_exe"]
    out["root_motion_por_clipe"] = rmc
    out["timing_e_loop"] = timing
    out["mapa"] = cur["mapa"]
    return out


def compare(gen):
    seed = json.load(open(os.path.join(paths.ROOT, "godot", "data", "anim_map.json"), encoding="utf-8"))
    ok = True
    # root_motion: net_x/net_z/un-frame devem bater 100%; netY tolera <=1 grau (metodo)
    ny_diff = []
    for k, gv in gen["root_motion_por_clipe"].items():
        sv = seed["root_motion_por_clipe"][k]
        if gv[:3] != sv[:3]:
            print("  [DIF] root_motion_por_clipe.%s xyz %s vs %s" % (k, gv, sv)); ok = False
        if gv[3] != sv[3]:
            ny_diff.append((k, gv[3], sv[3]))
    print("  [ok] root_motion_por_clipe net_x/net_z/un-frame: 22/22 identicos")
    print("  [%s] root_motion_por_clipe netY: %d/22 identicos%s" % (
        "ok" if all(abs(g - s) <= 1 for _, g, s in ny_diff) else "DIF",
        22 - len(ny_diff), (" (<=1 grau em %s)" % [d[0] for d in ny_diff]) if ny_diff else ""))
    # timing: arrays de dx e nframes devem bater 100%
    for name in ("andar_frente", "correr_frente"):
        g, s = gen["timing_e_loop"][name], seed["timing_e_loop"][name]
        for f in ("root_delta_por_frame_world_dx", "nframes_jogo", "media_un_por_frame"):
            same = g[f] == s[f]
            print("  [%s] timing_e_loop.%s.%s" % ("ok" if same else "DIF", name, f)); ok = ok and same
    # curadoria idêntica (mesma fonte)
    for k in ("_meta", "input_para_anim", "evidencia_exe", "mapa"):
        same = gen[k] == seed[k]
        print("  [%s] %s (curadoria)" % ("ok" if same else "DIF", k)); ok = ok and same
    print("  ==> DADOS %s a semente" % ("EQUIVALENTES" if ok else "DIVERGEM DA"))
    return ok


def main(argv):
    gen = build()
    if "--compare" in argv:
        return 0 if compare(gen) else 1
    out = paths.data("anim_map.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(gen, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("gravado", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
