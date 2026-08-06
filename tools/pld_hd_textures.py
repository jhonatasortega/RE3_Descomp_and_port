#!/usr/bin/env python3
"""Troca as texturas PS1 dos modelos PLD pelas versões HD do Seamless (pasta `hires`).

O GOG é SOMENTE LEITURA — nada é escrito lá. As HD ficam em
`hires/skin0` (personagens) e `hires/skin` (misto: personagem + cenário/objeto),
`.webp` **512×1024** = um bloco PS1 de **128×256** em 4×.

A textura embutida no PLD é 8bpp 384×256 com 3 paletas → o conversor monta um atlas
de 3 bandas (384×768). Só os **blocos diagonais** (banda k, coluna k) são amostrados:
col0=corpo (paleta0), **col1=rosto** (paleta1), col2=detalhes (paleta2).

Método: para cada bloco diagonal (128×256, decodificado com a sua paleta), faz
**content-match** por NCC (correlação cruzada normalizada em thumbnail cinza 64×128,
mesma técnica do `hd_match.py` dos backgrounds) contra `skin0` (limiar 0.85) e `skin`
(limiar 0.93, mais rígido por conter cenário). Blocos casados recebem a HD (512×1024);
os não casados ficam com o PS1 em 4×. O GLB é reconstruído com o atlas HD (as UVs são
normalizadas pelas dims lógicas do PS1, então continuam válidas).

Uso:
    python pld_hd_textures.py PL00            # 1 modelo (dry-run: só reporta match)
    python pld_hd_textures.py PL00 --apply    # reconstrói godot/assets/PLD/PL00.glb com HD
    python pld_hd_textures.py --all --apply   # todos os PLD
"""
import os
import sys
import glob
import numpy as np
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pld2gltf as P

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
SRC = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "PLD")
DST = paths.assets("PLD")
THUMB = (64, 128)          # 1:2 (igual a 128×256 e 512×1024)
NCC = {"skin0": 0.85, "skin": 0.93}
SCALE = 4                  # HD = 4× o PS1


def nthumb(im):
    a = np.asarray(im.convert("L").resize(THUMB), np.float32).ravel()
    a -= a.mean(); n = np.linalg.norm(a)
    return a / n if n > 0 else a


def index_hd():
    idx = {}
    for sub in ("skin0", "skin"):
        H, hp = [], []
        for f in sorted(glob.glob(os.path.join(HIRES, sub, "*.webp"))):
            try:
                H.append(nthumb(Image.open(f))); hp.append(f)
            except Exception:
                pass
        idx[sub] = (np.vstack(H) if H else np.zeros((0, THUMB[0] * THUMB[1])), hp)
    return idx


def ps1_atlas(pld_path):
    d = open(pld_path, "rb").read()
    offs, sec = P.parse_container(d)
    roles = P.classify(d, offs, sec)
    aw, ah, bh, npal, atlas = P.parse_tim_atlas(d, sec[roles["tim"]][0])
    return aw, ah, np.frombuffer(atlas, np.uint8).reshape(ah, aw, 3)


def match_blocks(arr):
    """arr = atlas 384×768. Retorna, por coluna k (0,1,2), (webp|None, ncc, sub)."""
    idx = match_blocks.idx
    out = []
    for k in range(3):
        block = arr[k * 256:(k + 1) * 256, k * 128:(k + 1) * 128]
        if block.shape[0] < 256 or block.shape[1] < 128:
            out.append(None); continue
        v = nthumb(Image.fromarray(block))
        best = None
        for sub in ("skin0", "skin"):
            H, hp = idx[sub]
            if len(hp) == 0:
                continue
            s = H @ v; j = int(s.argmax())
            if s[j] >= NCC[sub] and (best is None or s[j] > best[1]):
                best = (hp[j], float(s[j]), sub)
        out.append(best)
    return out


def build_hd_atlas(arr, matches):
    ah, aw = arr.shape[:2]                          # 768, 384
    HW, HH = aw * SCALE, ah * SCALE                 # 1536, 3072
    hd = np.asarray(Image.fromarray(arr).resize((HW, HH), Image.NEAREST)).copy()
    used = 0
    for k, mt in enumerate(matches):
        if mt is None:
            continue
        webp = Image.open(mt[0]).convert("RGB").resize((128 * SCALE, 256 * SCALE))
        x0, y0 = k * 128 * SCALE, k * 256 * SCALE
        hd[y0:y0 + 256 * SCALE, x0:x0 + 128 * SCALE] = np.asarray(webp)
        used += 1
    return HW, HH, hd.tobytes(), used


LABEL = {0: "corpo", 1: "rosto", 2: "detalhes"}


def process(name, apply):
    pld = os.path.join(SRC, name + ".PLD")
    if not os.path.exists(pld) or os.path.getsize(pld) < 64:
        print(f"  {name}: (stub/ausente)"); return 0
    aw, ah, arr = ps1_atlas(pld)
    matches = match_blocks(arr)
    tags = []
    for k, mt in enumerate(matches):
        if mt:
            tags.append(f"{LABEL[k]}={os.path.basename(mt[0])}[{mt[2]} NCC={mt[1]:.3f}]")
    used = sum(1 for mt in matches if mt)
    print(f"  {name}: {used}/3 blocos HD  {'; '.join(tags) if tags else '(sem match)'}")
    if apply:
        out = os.path.join(DST, name + ".glb")
        try:
            if used:
                HW, HH, rgb, _ = build_hd_atlas(arr, matches)
                P.convert(pld, out, hd_atlas=(HW, HH, rgb))
            else:
                P.convert(pld, out)                 # mantém PS1
        except Exception as e:
            print(f"    ERRO ao reconstruir {name}: {e}")
            return 0
    return used


def main():
    args = sys.argv[1:]
    apply = "--apply" in args
    names = [a for a in args if not a.startswith("--")]
    if "--all" in args or not names:
        names = sorted(os.path.splitext(os.path.basename(f))[0]
                       for f in glob.glob(os.path.join(SRC, "*.PLD")))
    print("Indexando HD (skin0 + skin)...")
    match_blocks.idx = index_hd()
    print("skin0:", len(match_blocks.idx["skin0"][1]),
          " skin:", len(match_blocks.idx["skin"][1]))
    total_hd = 0; models_hd = 0
    for nm in names:
        u = process(nm, apply)
        total_hd += u; models_hd += (1 if u else 0)
    print(f"\n== {models_hd}/{len(names)} modelos com >=1 bloco HD; "
          f"{total_hd} blocos HD no total ({'APLICADO' if apply else 'DRY-RUN'}) ==")


if __name__ == "__main__":
    main()
