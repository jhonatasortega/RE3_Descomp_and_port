#!/usr/bin/env python3
"""Localiza cada tile HD (hires/map/*.webp) dentro das paginas do MAP_U.MAP e gera o de-para.

Cada .webp e o 4x de um bloco SD 256x256 (ou 256x216) recortado de uma pagina 512x256
(ou 256x256) da VRAM do mapa. Como o HD veio de um PC russo e e redesenhado, casamos por
GEOMETRIA (mascara de comodos, independente de cor): downscale da mascara HD e NCC
deslizante (vetorizado) sobre a mascara de cada pagina PS1 -> (pagina, dx, dy, ncc).

Duas visoes:
  - HD-centrica: cada HD -> pagina de maior NCC (com flag ok).
  - Pagina-centrica: cada pagina -> tiles HD com NCC alto (evita rouba-match entre
    paginas parecidas do trio Park/DeadFactory/Hospital).

Uso:
    python map_hd_locate.py            # relatorio
    python map_hd_locate.py --emit     # + PNG PS1, webp representativos e JSON
"""
import sys, os, glob, json, struct, shutil
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view as swv
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPFILE = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "ETC", "MAP_U.MAP")
HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires/map"
OUT = paths.assets("MAP")
DS = 4
THR = 0.55          # aceite HD-centrico
PAGE_THR = 0.80     # aceite pagina-centrico (alto: separa paginas parecidas)
AREAS = ["UPTOWN", "DOWNTOWN", "CLOCK_TOWER", "PARK", "DEAD_FACTORY",
         "POLICE_STATION", "HOSPITAL", "UPTOWN_B", "DOWNTOWN_B"]
DUP_OF = {7: 0, 8: 1}   # paginas duplicatas (geometria identica)


def u16(b, o): return b[o] | (b[o + 1] << 8)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


def bgr555a(v):
    r = (v & 0x1F) << 3; g = ((v >> 5) & 0x1F) << 3; b = ((v >> 10) & 0x1F) << 3
    return (r | r >> 5, g | g >> 5, b | b >> 5, 0 if v == 0 else 255)


def find_tims(data):
    offs, i, n = [], 0, len(data)
    while i < n - 12:
        if data[i] == 0x10 and u32(data, i) == 0x10 and u32(data, i + 4) in (0, 1, 2, 3, 8, 9, 10, 11):
            try:
                flag = u32(data, i + 4); pos = i + 8
                if (flag >> 3) & 1:
                    bl = u32(data, pos); assert 12 <= bl and pos + bl <= n; pos += bl
                pl = u32(data, pos); assert 12 <= pl and pos + pl <= n
                offs.append(i); i = pos + pl; continue
            except Exception:
                pass
        i += 4
    return offs


def decode_page(data, o):
    pos = o + 8
    bl = u32(data, pos); cw = u16(data, pos + 8)
    clut = [bgr555a(u16(data, pos + 12 + 2 * i)) for i in range(cw)]
    pos += bl
    pl = u32(data, pos); iw = u16(data, pos + 8); ih = u16(data, pos + 10)
    pix = data[pos + 12: pos + pl]
    w = iw * 4
    arr = np.zeros((ih, w, 4), np.uint8)
    for i in range(w * ih):
        byte = pix[i >> 1]
        idx = (byte & 0x0F) if (i & 1) == 0 else (byte >> 4)
        arr[i // w, i % w] = clut[idx]
    return Image.fromarray(arr, "RGBA")


def page_mask(img):
    a = np.asarray(img)[:, :, 3]
    m = (a > 0).astype(np.float32)
    im = Image.fromarray((m * 255).astype(np.uint8)).resize((img.width // DS, img.height // DS))
    return np.asarray(im, np.float32) / 255.0


def hd_mask(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, np.int16)
    corners = np.vstack([a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]])
    bg = np.median(corners, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    m = (d > 60).astype(np.float32)
    if m.mean() < 0.02:
        m = 1.0 - m
    sd = 256 // DS
    th = m.shape[0] // (1024 // sd)
    im2 = Image.fromarray((m * 255).astype(np.uint8)).resize((sd, th))
    return np.asarray(im2, np.float32) / 255.0


def best_on_page(pm, hv, hh, hw):
    """Melhor NCC deslizante do template hv (achatado, ja normalizado) na pagina pm."""
    ph, pw = pm.shape
    if hh > ph or hw > pw:
        return -1, 0, 0
    win = swv(pm, (hh, hw)).reshape(-1, hh * hw)     # (npos, hh*hw)
    win = win - win.mean(1, keepdims=True)
    nrm = np.linalg.norm(win, axis=1)
    nrm[nrm == 0] = 1
    hn = np.linalg.norm(hv)
    scores = (win @ hv) / nrm / (hn if hn > 0 else 1)
    k = int(np.argmax(scores))
    ny = ph - hh + 1
    return float(scores[k]), (k % (pw - hw + 1)) * DS, (k // (pw - hw + 1)) * DS


def main():
    emit = "--emit" in sys.argv
    data = open(MAPFILE, "rb").read()
    offs = find_tims(data)
    pages = [o for k, o in enumerate(offs) if k % 2 == 0]
    imgs = [decode_page(data, o) for o in pages]
    pages_m = [page_mask(im) for im in imgs]
    print("paginas:", len(pages), "dims:", [im.size for im in imgs])

    hd = sorted(glob.glob(HIRES + "/*.webp"))
    print("HD:", len(hd))
    hashes = [os.path.splitext(os.path.basename(p))[0] for p in hd]

    # matriz score[hd, page] e offset
    npg = len(pages)
    M = np.full((len(hd), npg), -1.0)
    OFF = {}
    for hi, hp in enumerate(hd):
        hm = hd_mask(hp)
        hh, hw = hm.shape
        hv = (hm - hm.mean()).ravel()
        for pi, pm in enumerate(pages_m):
            s, dx, dy = best_on_page(pm, hv, hh, hw)
            M[hi, pi] = s
            OFF[(hi, pi)] = (dx, dy, hw * DS, hh * DS)

    # --- HD-centrico ---
    results = {}
    for hi, h in enumerate(hashes):
        pi = int(np.argmax(M[hi]))
        dx, dy, w, ht = OFF[(hi, pi)]
        results[h] = dict(area=AREAS[pi], page=pi, dx=dx, dy=dy, w=w, h=ht,
                          ncc=round(float(M[hi, pi]), 3), ok=bool(M[hi, pi] >= THR))
    ok = sum(1 for r in results.values() if r["ok"])
    print("\n[HD-centrico] NCC>=%.2f: %d/%d" % (THR, ok, len(hd)))
    d = np.array([r["ncc"] for r in results.values()])
    print("  dist: >=.9=%d .7-.9=%d .55-.7=%d <.55=%d" %
          ((d >= .9).sum(), ((d >= .7) & (d < .9)).sum(),
           ((d >= .55) & (d < .7)).sum(), (d < .55).sum()))

    # --- Pagina-centrico (paginas base, sem duplicatas) ---
    base_pages = [i for i in range(npg) if i not in DUP_OF]
    page_hd = {}
    print("\n[Pagina-centrico] tiles HD por area (NCC>=%.2f):" % PAGE_THR)
    for pi in base_pages:
        idx = np.where(M[:, pi] >= PAGE_THR)[0]
        idx = idx[np.argsort(-M[idx, pi])]
        lst = []
        for hi in idx:
            dx, dy, w, ht = OFF[(hi, pi)]
            lst.append(dict(hash=hashes[hi], dx=dx, ncc=round(float(M[hi, pi]), 3)))
        page_hd[AREAS[pi]] = lst
        print("  %-14s n=%2d : " % (AREAS[pi], len(lst)) +
              ", ".join("%s(x%d,%.2f)" % (x["hash"], x["dx"], x["ncc"]) for x in lst[:14]))

    if emit:
        os.makedirs(OUT, exist_ok=True)
        for ai, o in enumerate(pages):
            imgs[ai].save(os.path.join(OUT, "PS1_%d_%s.png" % (ai, AREAS[ai])))
        # representante por (area_base, dx): melhor NCC
        chosen = {}
        for pi in base_pages:
            for x in page_hd[AREAS[pi]]:
                key = (AREAS[pi], x["dx"])
                if key not in chosen or x["ncc"] > chosen[key]["ncc"]:
                    chosen[key] = dict(hash=x["hash"], ncc=x["ncc"])
        for (area, dx), c in chosen.items():
            shutil.copy(os.path.join(HIRES, c["hash"] + ".webp"),
                        os.path.join(OUT, "HD_%s_x%03d_%s.webp" % (area, dx, c["hash"])))
        json.dump({
            "fonte_ps1": "extracted/ntsc-u/CD_DATA/ETC/MAP_U.MAP",
            "fonte_hd": "hires/map/*.webp (Seamless HD; PC russo, redesenhado)",
            "metodo": ("mascara de comodos (alpha do TIM PS1 vs nao-fundo do HD) + NCC "
                       "deslizante vetorizado; dx/dy em px SD; HD = 4x do bloco SD"),
            "areas_distintas": [AREAS[i] for i in base_pages],
            "paginas": [{"idx": ai, "area": AREAS[ai], "off": "0x%08x" % o,
                         "dim_sd": list(imgs[ai].size),
                         "duplicata_de": AREAS[DUP_OF[ai]] if ai in DUP_OF else None,
                         "png": "PS1_%d_%s.png" % (ai, AREAS[ai])}
                        for ai, o in enumerate(pages)],
            "por_area": page_hd,
            "representantes": {"%s_x%03d" % k: v for k, v in chosen.items()},
            "hd_centrico": results,
        }, open(os.path.join(OUT, "map_depara.json"), "w"), indent=2, ensure_ascii=False)
        print("\nEMITIDO:", OUT, "| representantes:", len(chosen),
              "| webp casados (pagina-centrico):", sum(len(v) for v in page_hd.values()))


if __name__ == "__main__":
    main()
