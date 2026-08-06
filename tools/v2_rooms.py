#!/usr/bin/env python3
"""Organiza a v2 (remake 3D) POR SALA, com as imagens HD como referencia de modelagem.

Para cada sala cria:
    v2/reconstruction/STAGE{n}/<sala>/
        cameras.json        # rig de cameras (pos/alvo/forward/dist) + HD por camera
        <sala>_<cam>.webp   # background HD daquela camera (referencia p/ modelar em 3D)

Le godot/data/STAGE{n}/*.json (cameras do ARD) + godot/data/hd_map.json (hash HD por camera)
e copia os HD de godot/assets_hd/ (populado antes por hd_copy.py).

Uso: python v2_rooms.py
"""
import os
import json
import glob
import math
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "godot", "data")
ASSETS_HD = os.path.join(ROOT, "godot", "assets")  # HD (.webp) agora mora junto do PS1
OUT = os.path.join(ROOT, "v2", "reconstruction")


def unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return ([c / n for c in v] if n else [0.0, 0.0, 0.0]), n


def load_hd_index():
    """(stage_n, room_name) -> {cam_index: background_hash}"""
    p = os.path.join(DATA, "hd_map.json")
    if not os.path.exists(p):
        return {}
    d = json.load(open(p, encoding="utf-8"))
    idx = {}
    for _, r in d.get("rooms", {}).items():
        ps1 = r.get("ps1") or {}
        st, rm = ps1.get("stage"), ps1.get("room")
        if st is None or rm is None:
            continue
        name = "R%d%02X" % (st, rm)
        idx[(st, name)] = {c.get("index"): c.get("background") for c in r.get("cameras", [])}
    return idx


def main():
    hd_idx = load_hd_index()
    total_rooms = total_hd = 0
    for stage_dir in sorted(glob.glob(os.path.join(DATA, "STAGE*"))):
        stage = os.path.basename(stage_dir)
        stage_n = int(stage.replace("STAGE", ""))
        for room_json in sorted(glob.glob(os.path.join(stage_dir, "*.json"))):
            room = os.path.splitext(os.path.basename(room_json))[0]
            d = json.load(open(room_json, encoding="utf-8"))
            cams_in = d.get("rdt", {}).get("cameras", [])
            out_dir = os.path.join(OUT, stage, room)
            os.makedirs(out_dir, exist_ok=True)
            hd_for_room = hd_idx.get((stage_n, room), {})
            cams_out = []
            for c in cams_in:
                frm, to = c.get("from"), c.get("to")
                if not frm or not to:
                    continue
                fwd, dist = unit([to[i] - frm[i] for i in range(3)])
                ci = c.get("index")
                hd_name = "%s_%d.webp" % (room, ci)
                src_hd = os.path.join(ASSETS_HD, stage, hd_name)
                has_hd = os.path.exists(src_hd)
                if has_hd:
                    shutil.copy(src_hd, os.path.join(out_dir, hd_name))
                    total_hd += 1
                cams_out.append({
                    "index": ci,
                    "pos": frm,
                    "target": to,
                    "forward": [round(x, 6) for x in fwd],
                    "distance": round(dist, 2),
                    "hd_background": hd_name if has_hd else None,
                    "hd_hash": hd_for_room.get(ci),
                    "ps1_background": "%s_%d.png" % (room, ci),
                })
            with open(os.path.join(out_dir, "cameras.json"), "w", encoding="utf-8") as f:
                json.dump({
                    "room": room,
                    "stage": stage_n,
                    "n_cameras": len(cams_out),
                    "note": "Rig de cameras + background HD por camera para reconstrucao 3D. "
                            "Coords PS1 em ponto-fixo (calibrar escala/Y). forward e invariante a escala.",
                    "cameras": cams_out,
                }, f, ensure_ascii=False, indent=1)
            total_rooms += 1
    print("salas organizadas: %d | imagens HD colocadas: %d" % (total_rooms, total_hd))
    print("saida:", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
