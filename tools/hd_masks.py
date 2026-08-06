#!/usr/bin/env python3
"""Migra as MASCARAS de profundidade HD (Seamless HD) por camera, via hd_map.

Cada camera do hd_map tem mask0/mask1 (hashes). Copia de hires/mask0 e mask1 para:
    godot/assets/MASK/STAGE{n}/R{stage}{room:02X}_{cam}_m0.webp  (e _m1)

Cria um .gdignore em MASK/ para o Godot NAO importar (2048x2048 e pesado);
serao ligadas na OCLUSAO do personagem 3D (feature futura).

Uso: python hd_masks.py
"""
import os
import json
import shutil
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HD_MAP = paths.data("hd_map.json")
GOG = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"


def main():
    d = json.load(open(HD_MAP, encoding="utf-8"))
    dirs = {"mask0": os.path.join(GOG, "mask0"), "mask1": os.path.join(GOG, "mask1")}
    mroot = paths.assets("MASK")
    os.makedirs(mroot, exist_ok=True)
    open(os.path.join(mroot, ".gdignore"), "w").close()  # Godot ignora esta pasta

    copied = missing = 0
    for _, r in d["rooms"].items():
        ps1 = r.get("ps1") or {}
        st, rm = ps1.get("stage"), ps1.get("room")
        if st is None or rm is None:
            continue
        out = os.path.join(mroot, "STAGE%d" % st)
        os.makedirs(out, exist_ok=True)
        name = "R%d%02X" % (st, rm)
        for c in r.get("cameras", []):
            i = c.get("index")
            for mkey, suf in (("mask0", "m0"), ("mask1", "m1")):
                h = c.get(mkey)
                if not h:
                    continue
                src = os.path.join(dirs[mkey], h + ".webp")
                if os.path.exists(src):
                    dst = os.path.join(out, "%s_%d_%s.webp" % (name, i, suf))
                    if not os.path.exists(dst):
                        shutil.copy(src, dst)
                    copied += 1
                else:
                    missing += 1
    print("mascaras copiadas: %d | referenciadas sem arquivo: %d" % (copied, missing))
    print("saida: godot/assets/MASK/ (com .gdignore — Godot nao importa por ora)")


if __name__ == "__main__":
    main()
