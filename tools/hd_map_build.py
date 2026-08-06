#!/usr/bin/env python3
"""Gera o mapa autoritativo sala -> assets HD (`<out>/data/hd_map.json`).

Este arquivo existia no projeto sem script que o regerasse (foi produzido ad-hoc):
sem ele o pipeline nao e reproduzivel a partir de uma instalacao limpa. Aqui esta o
gerador, seguindo o formato PROVADO em docs/formatos/hd_mapping.md:

    hires/cache/ROOM<SRRP>.dat = array plano de uint32 LITTLE-ENDIAN, sem cabecalho.
    Cada uint32 -> "%08X" = nome de um .webp em hires/{bgd,mask0,mask1}.
    A ordem e agrupada por CAMERA: [background, mask0, mask1] [background, ...]
    (cada hash de bgd abre uma camera nova; mascaras seguintes pertencem a ela).

    ROOM S RR P: S=stage(1 hex), RR=sala(2 hex), P=player(1 hex, sempre 0 no RE3).
    PS1: stage = pc.stage + stage_offset (=1, CONFIRMADO: PC ROOM0000 = PS1 STAGE1/R100).

Uso:
    python tools/hd_map_build.py                       # gera <out>/data/hd_map.json
    python tools/hd_map_build.py --hires "<caminho>"   # instalacao HD alternativa
    python tools/hd_map_build.py --compare <arq.json>  # so compara com um hd_map existente

O destino segue NOSTALGIA_OUT (ver tools/paths.py). A instalacao do jogo e lida
SOMENTE PARA LEITURA. Assets do Seamless HD Project: nao redistribuir.
"""
import json
import os
import sys

import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

DEFAULT_HIRES = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3\hires"
ENV_HIRES = "NOSTALGIA_HIRES"
STAGE_OFFSET = 1
# prioridade quando o mesmo hash existe em mais de uma pasta (colisao de conteudo)
KIND_PRIORITY = ["bgd", "mask0", "mask1", "door", "map", "item", "slide", "info",
                 "memo", "effect", "effect0", "skin", "skin0", "misc"]


def hires_root(argv):
    if "--hires" in argv:
        return argv[argv.index("--hires") + 1]
    return os.environ.get(ENV_HIRES) or DEFAULT_HIRES


def index_hires(root):
    """hash(str 8 hex maiusculo) -> pasta de maior prioridade onde ele existe."""
    idx = {}
    for kind in KIND_PRIORITY:
        d = os.path.join(root, kind)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            stem, ext = os.path.splitext(f)
            if ext.lower() != ".webp":
                continue
            h = stem.upper()
            if h not in idx:                      # 1a pasta na ordem de prioridade ganha
                idx[h] = kind
    return idx


def read_cache(path):
    """Le o ROOMxxxx.dat -> lista de hashes '%08X'. Exige tamanho multiplo de 4."""
    b = open(path, "rb").read()
    if len(b) % 4:
        raise ValueError(f"{os.path.basename(path)}: {len(b)} bytes nao e multiplo de 4")
    return ["%08X" % int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]


def group_cameras(hashes, idx):
    """Agrupa por camera: cada bgd abre uma camera; mascaras seguintes sao dela."""
    cams, other, unresolved = [], [], []
    for h in hashes:
        kind = idx.get(h)
        if kind is None:
            unresolved.append(h)                  # asset nao substituido em HD (usa o SD)
            continue
        if kind == "bgd":
            cams.append({"index": len(cams), "background": h,
                         "mask0": None, "mask1": None, "masks_extra": []})
        elif kind in ("mask0", "mask1") and cams:
            cam = cams[-1]
            if cam[kind] is None:
                cam[kind] = h
            else:
                cam["masks_extra"].append(h)
        else:
            other.append({"hash": h, "kind": kind})
    return cams, other, unresolved


def build(root):
    cache_dir = os.path.join(root, "cache")
    if not os.path.isdir(cache_dir):
        sys.exit(f"ERRO: nao achei {cache_dir}\n"
                 f"      Aponte a instalacao com --hires ou {ENV_HIRES}=<caminho>")
    idx = index_hires(root)
    n_bgd_files = sum(1 for h, k in idx.items() if k == "bgd")

    rooms, backgrounds = {}, {}
    n_vals = n_ok = 0
    for f in sorted(os.listdir(cache_dir)):
        up = f.upper()
        if not (up.startswith("ROOM") and up.endswith(".DAT")):
            continue
        srrp = up[4:-4]                            # 'ROOM1000.dat' -> '1000'
        hashes = read_cache(os.path.join(cache_dir, f))
        n_vals += len(hashes)
        n_ok += sum(1 for h in hashes if h in idx)
        cams, other, unres = group_cameras(hashes, idx)

        is_global = (srrp.upper() == "FFFF")
        pc = {"id": "ROOM" + srrp}
        ps1 = None
        if not is_global:
            st, rm, pl = int(srrp[0], 16), int(srrp[1:3], 16), int(srrp[3], 16)
            pc.update({"stage": st, "room": rm, "player": pl})
            ps1 = {"stage": st + STAGE_OFFSET, "room": rm,
                   "name": "R%d%02X" % (st + STAGE_OFFSET, rm),
                   "note": "stage = pc.stage + stage_offset (=1, confirmado)"}
        rooms[srrp] = {"pc": pc, "ps1": ps1, "global": is_global,
                       "n_cameras": len(cams), "cameras": cams,
                       "other_assets": other, "unresolved": unres}
        for c in cams:
            e = backgrounds.setdefault(c["background"],
                                       {"webp": "hires/bgd/%s.webp" % c["background"],
                                        "rooms": []})
            if srrp not in e["rooms"]:
                e["rooms"].append(srrp)

    meta = {
        "generated_from": "Classic REbirth HD cache (instalacao com Seamless HD Project)",
        "generator": "tools/hd_map_build.py",
        "source_game": "Resident Evil 3 (PC/GOG) - SOMENTE LEITURA, assets nao redistribuidos",
        "hires_root": root,
        "cache_glob": "hires/cache/ROOM<SRRP>.dat",
        "dat_format": ("array plano de uint32 little-endian, sem cabecalho; cada valor = nome-hash "
                       "(8 hex) de um .webp em hires/. Agrupado por CAMERA: [background, mask0, mask1]."),
        "endianness": "little-endian (BE casa 0%, LE casa ~99,7%)",
        "image_format": "WEBP; bgd=1280x960 (4x PS1); mask0/mask1=2048x2048 lossless",
        "stage_offset": STAGE_OFFSET,
        "stage_offset_note": ("PS1 STAGE{n} = pc.stage + 1. CONFIRMADO por render: "
                             "PC ROOM0000 = PS1 STAGE1/R100 (escritorio S.T.A.R.S.)."),
        "coverage_note": ("o cache so cobre salas JA VISITADAS no PC; hashes sem .webp = asset "
                         "nao substituido em HD (o jogo usa o SD)."),
        "rooms_cached": len(rooms),
        "bgd_total_files": n_bgd_files,
        "bgd_referenced": len(backgrounds),
        "cache_values": n_vals,
        "cache_values_resolved": n_ok,
        "cache_resolved_pct": round(100.0 * n_ok / n_vals, 2) if n_vals else 0.0,
    }
    return {"meta": meta, "rooms": rooms, "backgrounds": backgrounds}


def compare(new, ref_path):
    """Compara com um hd_map.json de referencia (prova de equivalencia do gerador)."""
    if not os.path.isfile(ref_path):
        print(f"[compare] referencia ausente: {ref_path}")
        return True
    ref = json.load(open(ref_path, encoding="utf-8"))
    ok = True
    rn, rr = set(new["rooms"]), set(ref["rooms"])
    if rn != rr:
        ok = False
        print(f"[compare] salas diferentes: so no novo {sorted(rn - rr)[:5]} | "
              f"so na ref {sorted(rr - rn)[:5]}")
    else:
        print(f"[compare] salas: {len(rn)} identicas")
    dif_cam = dif_trip = 0
    for k in sorted(rn & rr):
        a, b = new["rooms"][k], ref["rooms"][k]
        if len(a["cameras"]) != len(b["cameras"]):
            dif_cam += 1
            continue
        for ca, cb in zip(a["cameras"], b["cameras"]):
            if (ca["background"], ca["mask0"], ca["mask1"]) != \
               (cb["background"], cb["mask0"], cb["mask1"]):
                dif_trip += 1
    print(f"[compare] salas com nº de cameras diferente: {dif_cam}")
    print(f"[compare] cameras com tripleto diferente:    {dif_trip}")
    if dif_cam or dif_trip:
        ok = False
    bn, bb = set(new["backgrounds"]), set(ref["backgrounds"])
    print(f"[compare] backgrounds: novo {len(bn)}, ref {len(bb)}, "
          f"so-novo {len(bn - bb)}, so-ref {len(bb - bn)}")
    if bn != bb:
        ok = False
    print("[compare]", "EQUIVALENTE" if ok else "DIVERGENTE")   # ASCII: console cp1252
    return ok


def main(argv):
    root = hires_root(argv)
    print(f"hires: {root}")
    hd = build(root)
    m = hd["meta"]
    print(f"salas no cache: {m['rooms_cached']} | cameras: "
          f"{sum(r['n_cameras'] for r in hd['rooms'].values())} | "
          f"backgrounds referenciados: {m['bgd_referenced']}/{m['bgd_total_files']} | "
          f"hashes resolvidos: {m['cache_values_resolved']}/{m['cache_values']} "
          f"({m['cache_resolved_pct']}%)")

    if "--compare" in argv:
        ref = argv[argv.index("--compare") + 1]
        return 0 if compare(hd, ref) else 1

    out = paths.data("hd_map.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    ref_ok = compare(hd, out) if os.path.isfile(out) else None
    with open(out, "w", encoding="utf-8") as f:
        json.dump(hd, f, ensure_ascii=False, indent=1)
    print(f"OK -> {out}" + ("" if ref_ok is None else f"  (equivalente ao anterior: {ref_ok})"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
