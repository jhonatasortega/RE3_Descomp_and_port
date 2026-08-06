#!/usr/bin/env python3
"""Content-match das imagens de UI (godot/assets/ETC/*.png) contra as pastas HD do
hires (misc/info/slide/map/item/memo/door) e migra as que casam para .webp.

NCC em thumbnail 64x64 (squash de aspecto, pois os tamanhos variam bastante).

Uso:
    python etc_hd_match.py           # dry-run (so mostra os matches)
    python etc_hd_match.py --apply   # aplica (copia webp, remove o png PS1)
"""
import os
import sys
import glob
import shutil
import numpy as np
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETC = paths.assets("ETC")
HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
POOLS = ["misc", "info", "slide", "map", "item", "memo", "door", "effect", "effect0"]
THUMB = (64, 64)
NCC_MIN = 0.88


def thumb(path):
    im = Image.open(path).convert("L").resize(THUMB)
    a = np.asarray(im, dtype=np.float32).ravel()
    a -= a.mean()
    n = np.linalg.norm(a)
    return a / n if n > 0 else a


def main():
    apply = "--apply" in sys.argv
    H, hp = [], []
    for pool in POOLS:
        for f in glob.glob(os.path.join(HIRES, pool, "*.webp")):
            try:
                H.append(thumb(f))
                hp.append(f)
            except Exception:
                pass
    H = np.vstack(H)
    print("HD UI indexadas:", len(hp))
    pngs = sorted(glob.glob(os.path.join(ETC, "*.png")))
    print("ETC png:", len(pngs))

    buckets = {">=0.95": 0, "0.88-0.95": 0, "0.7-0.88": 0, "<0.7": 0}
    matched = 0
    for png in pngs:
        try:
            v = thumb(png)
        except Exception:
            continue
        s = H @ v
        j = int(np.argmax(s))
        best = float(s[j])
        b = ">=0.95" if best >= 0.95 else "0.88-0.95" if best >= 0.88 else "0.7-0.88" if best >= 0.7 else "<0.7"
        buckets[b] += 1
        name = os.path.basename(png)
        if best >= NCC_MIN:
            matched += 1
            print(f"  MATCH {name:16} <- {os.path.relpath(hp[j], HIRES).replace(os.sep,'/'):18} ncc={best:.3f}")
            if apply:
                dst = png[:-4] + ".webp"
                shutil.copy(hp[j], dst)
                os.remove(png)
                if os.path.exists(png + ".import"):
                    os.remove(png + ".import")
    print("distribuicao do melhor NCC:", buckets)
    print(("APLICADO" if apply else "DRY-RUN") + f": casados {matched}/{len(pngs)}")


if __name__ == "__main__":
    main()
