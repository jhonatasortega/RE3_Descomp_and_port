#!/usr/bin/env python3
"""Substitui os backgrounds do jogo pelos HD (Seamless HD Project), casados por sala/camera.

Usa godot/data/hd_map.json (mapa autoritativo hash<->sala via cache do Classic REbirth).
Origem: a instalacao GOG (SOMENTE LEITURA). Destino = a MESMA pasta assets do jogo:
    godot/assets/STAGE{n}/R{stage}{room:02X}_{cam}.webp

Onde ha HD, o .webp e colocado e o .png (PS1) correspondente e REMOVIDO (substituicao).
Onde NAO ha HD (o mod nao cobre ~600 cameras), o .png do PS1 permanece.

Uso: python hd_copy.py
"""
import os
import json
import shutil
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HD_MAP = paths.data("hd_map.json")
GOG = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"


def main():
    with open(HD_MAP, encoding="utf-8") as f:
        d = json.load(f)
    rooms = d["rooms"]
    bgd_dir = os.path.join(GOG, "bgd")
    copied = missing = removed_png = 0
    for _, r in rooms.items():
        ps1 = r.get("ps1") or {}
        st, rm = ps1.get("stage"), ps1.get("room")
        if st is None or rm is None:
            continue
        out_dir = paths.assets("STAGE%d" % st)
        os.makedirs(out_dir, exist_ok=True)
        name = "R%d%02X" % (st, rm)          # espelha o nome PS1: R100, R10C...
        for c in r.get("cameras", []):
            idx = c.get("index", 0)
            h = c.get("background")
            if not h:
                continue
            src = os.path.join(bgd_dir, h + ".webp")
            dst = os.path.join(out_dir, "%s_%d.webp" % (name, idx))
            if os.path.exists(src):
                if not os.path.exists(dst):
                    shutil.copy(src, dst)
                copied += 1
                # substitui: remove o PS1 png (e seu .import) superado pelo HD
                png = os.path.join(out_dir, "%s_%d.png" % (name, idx))
                if os.path.exists(png):
                    os.remove(png)
                    if os.path.exists(png + ".import"):
                        os.remove(png + ".import")
                    removed_png += 1
            else:
                missing += 1
    print("HD colocados em assets: %d | PS1 png substituidos: %d | referenciados sem arquivo: %d"
          % (copied, removed_png, missing))


if __name__ == "__main__":
    main()
