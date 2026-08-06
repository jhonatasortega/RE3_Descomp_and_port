#!/usr/bin/env python3
"""Exporta o rig de câmeras (do .ARD já parseado) para dados de reconstrução 3D da v2.

Lê os JSONs de sala em godot/data/STAGE{n}/*.json (campo rdt.cameras) e gera, por sala,
um arquivo em v2/reconstruction/STAGE{n}/<sala>.cameras.json com posição, alvo, direção
(forward unitário) e distância de cada câmera fixa — a base para montar a cena 3D e
projetar os backgrounds HD por ângulo.

As coordenadas ficam em ponto-fixo do PS1 (cru). A ESCALA e o eixo Y ainda precisam de
calibração (ver v2/README.md); a direção (forward) é invariante à escala.

Uso: python cameras_to_3d.py
"""
import os
import json
import glob
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "godot", "data")
DST = os.path.join(ROOT, "v2", "reconstruction")


def unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return [c / n for c in v] if n else [0.0, 0.0, 0.0], n


def process_room(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    rdt = d.get("rdt") or {}
    cams_in = rdt.get("cameras") or []
    cams_out = []
    pts = []
    for c in cams_in:
        frm = c.get("from")
        to = c.get("to")
        if not frm or not to:
            continue
        d3 = [to[i] - frm[i] for i in range(3)]
        fwd, dist = unit(d3)
        cams_out.append({
            "index": c.get("index"),
            "attr": c.get("attr"),
            "pos": frm,
            "target": to,
            "forward": [round(x, 6) for x in fwd],
            "distance": round(dist, 2),
            "mask_data_ptr": c.get("mask_data_ptr"),
        })
        pts.append(frm)
        pts.append(to)
    aabb = None
    if pts:
        mn = [min(p[i] for p in pts) for i in range(3)]
        mx = [max(p[i] for p in pts) for i in range(3)]
        aabb = {"min": mn, "max": mx, "size": [mx[i] - mn[i] for i in range(3)]}
    return {
        "room": os.path.splitext(os.path.basename(path))[0],
        "source": os.path.relpath(path, ROOT).replace("\\", "/"),
        "n_cameras": len(cams_out),
        "world": {
            "units": "ps1_fixed",
            "note": "escala/eixo a calibrar; Y provavelmente para baixo no PS1. forward e invariante a escala.",
        },
        "aabb": aabb,
        "cameras": cams_out,
    }


def main():
    total_rooms = total_cams = 0
    index = []
    for stage_dir in sorted(glob.glob(os.path.join(SRC, "STAGE*"))):
        stage = os.path.basename(stage_dir)
        out_dir = os.path.join(DST, stage)
        os.makedirs(out_dir, exist_ok=True)
        for room_json in sorted(glob.glob(os.path.join(stage_dir, "*.json"))):
            room = process_room(room_json)
            with open(os.path.join(out_dir, room["room"] + ".cameras.json"), "w", encoding="utf-8") as f:
                json.dump(room, f, ensure_ascii=False, indent=1)
            total_rooms += 1
            total_cams += room["n_cameras"]
            index.append({"stage": stage, "room": room["room"], "n_cameras": room["n_cameras"]})
    os.makedirs(DST, exist_ok=True)
    with open(os.path.join(DST, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"total_rooms": total_rooms, "total_cameras": total_cams, "rooms": index},
                  f, ensure_ascii=False, indent=1)
    print(f"Salas processadas: {total_rooms} | cameras exportadas: {total_cams}")
    print(f"Saida: {os.path.relpath(DST, ROOT)}")


if __name__ == "__main__":
    main()
