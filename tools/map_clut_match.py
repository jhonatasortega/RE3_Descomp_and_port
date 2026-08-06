#!/usr/bin/env python3
"""De-para MAP_U.MAP <-> hires/map por template PER-CLUT.

Cada pagina de mapa e um TIM 4bpp com 16 CLUTs. A transparencia depende do VALOR da
entrada da CLUT (0x0000 = transparente), que muda por paleta -> cada CLUT desenha um
SUBCONJUNTO de comodos (andar/estado). O HD (Seamless, russo) tem um .webp por
tile x cor/estado. Entao casamos a mascara de CADA (pagina,CLUT) com cada HD por NCC
deslizante (vetorizado). Isso captura os variantes de cor/andar que o palette-0 perde.

Uso:
    python map_clut_match.py            # relatorio
    python map_clut_match.py --emit     # + PNG PS1, webp casados e JSON completo
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
THR = 0.80
AREAS = ["UPTOWN", "DOWNTOWN", "CLOCK_TOWER", "PARK", "DEAD_FACTORY",
         "POLICE_STATION", "HOSPITAL", "UPTOWN_B", "DOWNTOWN_B"]
DUP_OF = {7: 0, 8: 1}


def u16(b, o): return b[o] | (b[o + 1] << 8)
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


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


def page_indices(data, o):
    """Retorna (indices HxW, cw, ch, clut_zero[ch][cw])."""
    pos = o + 8
    bl = u32(data, pos); cw = u16(data, pos + 8); ch = u16(data, pos + 10)
    p = pos + 12
    zero = [[u16(data, p + 2 * (c * cw + i)) == 0 for i in range(cw)] for c in range(ch)]
    pos += bl
    pl = u32(data, pos); iw = u16(data, pos + 8); ih = u16(data, pos + 10)
    pix = data[pos + 12: pos + pl]
    w = iw * 4
    idx = np.zeros((ih, w), np.uint8)
    for i in range(w * ih):
        byte = pix[i >> 1]
        idx[i // w, i % w] = (byte & 0x0F) if (i & 1) == 0 else (byte >> 4)
    return idx, cw, ch, zero


def mask_from_clut(idx, zero_c):
    """mask = 1 onde a entrada NAO e transparente na CLUT c."""
    opaque = ~np.array(zero_c, bool)      # (16,)
    m = opaque[idx].astype(np.float32)
    im = Image.fromarray((m * 255).astype(np.uint8)).resize((idx.shape[1] // DS, idx.shape[0] // DS))
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


def best_on(pm, hv, hh, hw):
    ph, pw = pm.shape
    if hh > ph or hw > pw:
        return -1, 0, 0
    win = swv(pm, (hh, hw)).reshape(-1, hh * hw)
    win = win - win.mean(1, keepdims=True)
    nrm = np.linalg.norm(win, axis=1); nrm[nrm == 0] = 1
    hn = np.linalg.norm(hv) or 1
    sc = (win @ hv) / nrm / hn
    k = int(np.argmax(sc))
    return float(sc[k]), (k % (pw - hw + 1)) * DS, (k // (pw - hw + 1)) * DS


def main():
    emit = "--emit" in sys.argv
    data = open(MAPFILE, "rb").read()
    offs = find_tims(data)
    pages = [o for k, o in enumerate(offs) if k % 2 == 0]

    # templates: por (page, clut), deduplicando mascaras identicas por pagina
    templ = []          # dict(page, clut, mask)
    idxs = []
    for pi, o in enumerate(pages):
        idx, cw, ch, zero = page_indices(data, o)
        idxs.append(idx)
        seen = set()
        for c in range(ch):
            m = mask_from_clut(idx, zero[c])
            key = m.tobytes()
            if key in seen or m.sum() < 4:
                continue
            seen.add(key)
            templ.append(dict(page=pi, clut=c, mask=m))
    print("paginas:", len(pages), "| templates (page,clut) unicos:", len(templ))

    hd = sorted(glob.glob(HIRES + "/*.webp"))
    hashes = [os.path.splitext(os.path.basename(p))[0] for p in hd]
    print("HD:", len(hd))

    results = {}
    for hp, h in zip(hd, hashes):
        hm = hd_mask(hp); hh, hw = hm.shape; hv = (hm - hm.mean()).ravel()
        best = dict(ncc=-1)
        for t in templ:
            s, dx, dy = best_on(t["mask"], hv, hh, hw)
            if s > best["ncc"]:
                best = dict(ncc=round(s, 3), page=t["page"], clut=t["clut"], dx=dx, dy=dy,
                            w=hw * DS, h=hh * DS)
        best["area"] = AREAS[best["page"]]
        best["ok"] = bool(best["ncc"] >= THR)
        results[h] = best

    ok = sum(1 for r in results.values() if r["ok"])
    d = np.array([r["ncc"] for r in results.values()])
    print("\nHD casados NCC>=%.2f: %d/%d" % (THR, ok, len(hd)))
    print("dist: >=.9=%d .8-.9=%d .6-.8=%d <.6=%d" %
          ((d >= .9).sum(), ((d >= .8) & (d < .9)).sum(),
           ((d >= .6) & (d < .8)).sum(), (d < .6).sum()))

    # por area base (mapeando duplicatas)
    base = lambda p: DUP_OF.get(p, p)
    per = {}
    for h, r in results.items():
        if not r["ok"]:
            continue
        a = AREAS[base(r["page"])]
        per.setdefault(a, []).append((h, r["dx"], r["clut"], r["ncc"]))
    print("\n== HD casados por area distinta ==")
    for a in [AREAS[i] for i in range(len(pages)) if i not in DUP_OF]:
        lst = sorted(per.get(a, []), key=lambda x: (x[1], -x[3]))
        print("%-14s n=%2d : " % (a, len(lst)) +
              ", ".join("%s(x%d,c%d,%.2f)" % x for x in lst[:16]))

    if emit:
        os.makedirs(OUT, exist_ok=True)
        # PNG PS1 (palette 0) por pagina — plano completo
        import importlib.util
        spec = importlib.util.spec_from_file_location("loc", os.path.join(ROOT, "tools", "map_hd_locate.py"))
        loc = importlib.util.module_from_spec(spec); spec.loader.exec_module(loc)
        for ai, o in enumerate(pages):
            loc.decode_page(data, o).save(os.path.join(OUT, "PS1_%d_%s.png" % (ai, AREAS[ai])))
        # representante por (area,dx): maior NCC; copia webp
        chosen = {}
        for h, r in results.items():
            if not r["ok"]:
                continue
            key = (AREAS[base(r["page"])], r["dx"])
            if key not in chosen or r["ncc"] > chosen[key]["ncc"]:
                chosen[key] = dict(hash=h, ncc=r["ncc"], clut=r["clut"])
        for (area, dx), c in chosen.items():
            shutil.copy(os.path.join(HIRES, c["hash"] + ".webp"),
                        os.path.join(OUT, "HD_%s_x%03d_%s.webp" % (area, dx, c["hash"])))
        json.dump({
            "fonte_ps1": "extracted/ntsc-u/CD_DATA/ETC/MAP_U.MAP",
            "fonte_hd": "hires/map/*.webp (Seamless HD; PC russo, redesenhado)",
            "metodo": ("templates por (pagina,CLUT) via transparencia da CLUT; NCC "
                       "deslizante vetorizado das mascaras de comodos; dx/dy em px SD; HD=4x SD"),
            "areas_distintas": [AREAS[i] for i in range(len(pages)) if i not in DUP_OF],
            "paginas": [{"idx": ai, "area": AREAS[ai], "off": "0x%08x" % o,
                         "dim_sd": [int(idxs[ai].shape[1]), int(idxs[ai].shape[0])],
                         "duplicata_de": AREAS[DUP_OF[ai]] if ai in DUP_OF else None,
                         "png": "PS1_%d_%s.png" % (ai, AREAS[ai])} for ai, o in enumerate(pages)],
            "representantes": {"%s_x%03d" % k: v for k, v in chosen.items()},
            "hd": results,
        }, open(os.path.join(OUT, "map_depara.json"), "w"), indent=2, ensure_ascii=False)
        print("\nEMITIDO:", OUT, "| representantes:", len(chosen), "| HD casados:", ok)


if __name__ == "__main__":
    main()
