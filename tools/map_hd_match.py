#!/usr/bin/env python3
"""Casa as telas de mapa do PS1 (MAP_x.MAP) com o HD (hires/map/*.webp).

Metodo: match por GEOMETRIA, independente de cor/idioma. O HD do Seamless veio de
um PC russo e e redesenhado; nao da pra reproduzir o CRC do blit. Entao:
  - PS1: mascara de "tinta" = canal alpha do TIM (comodos preenchidos != transparente).
  - HD : mascara = pixels que diferem do fundo (fundo = cor de canto dominante).
Cada pagina PS1 (512x256) e fatiada em tiles de 256 (esq/dir); a de 256 (Clock Tower)
fica inteira. NCC das mascaras em 96x96. 1:N (varios tiles/cores por pagina).

Uso:
    python map_hd_match.py           # relatorio
    python map_hd_match.py --emit    # + escreve JSON e copia assets
"""
import sys, os, glob, json, struct, shutil
import numpy as np
from PIL import Image
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAPFILE = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA", "ETC", "MAP_U.MAP")
HIRES = r"C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires/map"
OUT = paths.assets("MAP")
N = 96

AREAS = ["UPTOWN", "DOWNTOWN", "CLOCK_TOWER", "PARK", "DEAD_FACTORY",
         "POLICE_STATION", "HOSPITAL", "UPTOWN_B", "DOWNTOWN_B"]


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
    """Decodifica pagina 4bpp com palette 0; retorna RGBA (alpha=comodo)."""
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


def mask_ps1(img):
    a = np.asarray(img)[:, :, 3]
    return (a > 0).astype(np.float32)


def mask_hd(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im, np.int16)
    corners = np.vstack([a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]])
    bg = np.median(corners, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(2))
    m = (d > 60).astype(np.float32)
    # se quase tudo virou "fundo" (tile totalmente preenchido), inverte a nocao
    if m.mean() < 0.02:
        m = 1.0 - m
    return m


def ncc_vec(mask):
    im = Image.fromarray((mask * 255).astype(np.uint8)).resize((N, N))
    v = np.asarray(im, np.float32).ravel()
    v -= v.mean(); n = np.linalg.norm(v)
    return v / n if n > 0 else v


def main():
    emit = "--emit" in sys.argv
    data = open(MAPFILE, "rb").read()
    offs = find_tims(data)
    pages = [o for k, o in enumerate(offs) if k % 2 == 0]   # blocos pares = paginas
    # tiles PS1: (area, tile_idx, vetor)
    ps1 = []
    for ai, o in enumerate(pages):
        img = decode_page(data, o)
        W = img.width
        m = mask_ps1(img)
        ntiles = 2 if W >= 512 else 1
        for t in range(ntiles):
            sub = m[:, t * 256:(t + 1) * 256]
            ps1.append(dict(area=AREAS[ai], areai=ai, off=o, tile=t,
                            W=W, vec=ncc_vec(sub), img=img))
    print("paginas PS1:", len(pages), "| tiles PS1:", len(ps1))

    hd = sorted(glob.glob(HIRES + "/*.webp"))
    print("HD map webp:", len(hd))

    # para cada HD, melhor tile PS1
    assign = {}
    per_area = {a: [] for a in AREAS}
    for hp in hd:
        m = mask_hd(hp)
        v = ncc_vec(m)
        best, bj = -1, -1
        for j, p in enumerate(ps1):
            s = float(np.dot(p["vec"], v))
            if s > best:
                best, bj = s, j
        p = ps1[bj]
        h = os.path.splitext(os.path.basename(hp))[0]
        assign[h] = dict(area=p["area"], tile=p["tile"], ncc=round(best, 3))
        per_area[p["area"]].append((h, p["tile"], round(best, 3)))

    print("\n== HD por area (ncc do melhor tile) ==")
    for a in AREAS:
        lst = sorted(per_area[a], key=lambda x: -x[2])
        print("%-14s n=%2d  " % (a, len(lst)) + ", ".join("%s(t%d,%.2f)" % x for x in lst[:12]))

    if emit:
        os.makedirs(OUT, exist_ok=True)
        # PNG PS1 por pagina (palette 0, pagina inteira) + strip
        for ai, o in enumerate(pages):
            img = decode_page(data, o)
            img.save(os.path.join(OUT, "PS1_%d_%s.png" % (ai, AREAS[ai])))
        # 1 HD representativo por (area,tile): o de maior NCC, cor "verde" preferida
        chosen = {}
        for h, meta in assign.items():
            key = (meta["area"], meta["tile"])
            if key not in chosen or meta["ncc"] > chosen[key][1]:
                chosen[key] = (h, meta["ncc"])
        for (area, tile), (h, ncc) in chosen.items():
            src = os.path.join(HIRES, h + ".webp")
            shutil.copy(src, os.path.join(OUT, "HD_%s_t%d_%s.webp" % (area, tile, h)))
        # JSON de-para
        depara = {
            "formato": "MAP_U.MAP (RE3 PS1) -> hires/map (Seamless HD)",
            "areas": AREAS,
            "paginas": [{"idx": ai, "area": AREAS[ai], "off": "0x%08x" % o,
                         "png": "PS1_%d_%s.png" % (ai, AREAS[ai])} for ai, o in enumerate(pages)],
            "hd_por_hash": assign,
            "representantes": {"%s_t%d" % k: {"hash": v[0], "ncc": v[1]} for k, v in chosen.items()},
        }
        json.dump(depara, open(os.path.join(OUT, "map_depara.json"), "w"),
                  indent=2, ensure_ascii=False)
        print("\nEMITIDO em", OUT, "| representantes:", len(chosen))


if __name__ == "__main__":
    main()
