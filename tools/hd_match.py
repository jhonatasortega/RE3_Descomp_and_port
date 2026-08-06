#!/usr/bin/env python3
"""Completa a cobertura HD por content-matching (Metodo A).

Para cada camera PS1 sem HD (godot/assets/STAGE{n}/R###_#.png sem .webp), acha o
.webp de hires/bgd que casa por imagem — NCC (correlacao cruzada normalizada) em
thumbnail cinza. Match verdadeiro NCC~0.99 vs falso <0.5 (gap enorme, calibrado).
Se NCC >= NCC_MIN, copia o webp p/ assets e remove o png (substituicao).

Uso:
    python hd_match.py            # dry-run (so mostra a distribuicao)
    python hd_match.py --apply    # aplica (copia webp, remove png)
"""
import os
import sys
import glob
import shutil
import numpy as np
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = paths.assets()
BGD = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires/bgd"
THUMB = (64, 48)     # cinza p/ NCC (4:3, igual ao PS1 e HD)
NCC_MIN = 0.92       # margem enorme (verdadeiros ~0.99, falsos <0.5)


def norm_thumb(path):
    im = Image.open(path).convert("L").resize(THUMB)
    a = np.asarray(im, dtype=np.float32).ravel()
    a -= a.mean()
    n = np.linalg.norm(a)
    return a / n if n > 0 else a


def main():
    apply = "--apply" in sys.argv
    hd_files = sorted(glob.glob(os.path.join(BGD, "*.webp")))
    H, hp = [], []
    for p in hd_files:
        try:
            H.append(norm_thumb(p))
            hp.append(p)
        except Exception:
            pass
    H = np.vstack(H)
    print("HD indexados:", len(hp))

    todo = [png for png in glob.glob(os.path.join(ASSETS, "STAGE*", "*.png"))
            if not os.path.exists(png[:-4] + ".webp")]
    print("PS1 sem HD:", len(todo))

    buckets = {">=0.99": 0, "0.92-0.99": 0, "0.5-0.92": 0, "<0.5": 0}
    matched = applied = 0
    ambiguous = []
    for png in todo:
        try:
            v = norm_thumb(png)
        except Exception:
            continue
        s = H @ v
        j = int(np.argmax(s))
        best = float(s[j])
        if best >= 0.99:
            buckets[">=0.99"] += 1
        elif best >= 0.92:
            buckets["0.92-0.99"] += 1
        elif best >= 0.5:
            buckets["0.5-0.92"] += 1
            ambiguous.append((os.path.basename(png), round(best, 3)))
        else:
            buckets["<0.5"] += 1
        if best >= NCC_MIN:
            matched += 1
            if apply:
                dst = png[:-4] + ".webp"
                shutil.copy(hp[j], dst)
                os.remove(png)
                if os.path.exists(png + ".import"):
                    os.remove(png + ".import")
                applied += 1

    print("distribuicao do melhor NCC:", buckets)
    print(("APLICADO" if apply else "DRY-RUN") +
          ": casados (NCC>=%.2f): %d/%d | sem HD real: %d" %
          (NCC_MIN, matched, len(todo), len(todo) - matched))
    if apply:
        print("aplicados (webp copiado, png removido):", applied)
    if ambiguous:
        print("zona ambigua (0.5-0.92) — conferir:", ambiguous[:15])


if __name__ == "__main__":
    main()
