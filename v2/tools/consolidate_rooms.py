"""consolidate_rooms.py — torna cada pasta de sala AUTOCONTIDA para o editor 3D.

Le as fontes espalhadas (somente leitura) e escreve UM arquivo por sala dentro de v2:

    entrada (read-only)                          saida (v2/)
    godot/data/STAGE{n}/{sala}_col.json     ┐
    godot/data/STAGE{n}/{sala}.json         │
    godot/data/STAGE{n}/{sala}_scd.json     ├──> v2/reconstruction/STAGE{n}/{sala}/room.src.json
    godot/data/room_graph.json              │
    v2/reconstruction/STAGE{n}/{sala}/cameras.json (+ .webp) ┘

`room.src.json` e GERADO e nunca editado a mao: e o "dado do jogo" normalizado.
Os ajustes do usuario vivem em `room3d.json` (outro arquivo, escrito pelo editor),
para que regerar isto aqui nunca destrua trabalho manual.

Uso:
    python v2/tools/consolidate_rooms.py            # todos os stages
    python v2/tools/consolidate_rooms.py --stage 1
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

SCHEMA = "re3.room.src/2"
WORLD_SCALE = 808.0        # unidades PS1 por unidade Godot/metro (calibrado, ver blueprints/01)
FULL_TURN = 4096           # unidade angular do RE3 (facing): 4096 = 360 graus

# Tocar a borda do range s16 e NORMAL: e so a parede externa da sala encostando no
# limite. Sentinela de verdade e o rect degenerado, que atravessa o mapa inteiro.
S16_EDGE = 31900           # marca `edge` (informativo) — continua sendo geometria real
SENTINEL_SPAN = 55000      # ~68 m num eixo: nao existe parede assim, e placeholder

ROOT = Path(__file__).resolve().parents[2]     # .../Nostalgia
GODOT_DATA = ROOT / "godot" / "data"
RECON = ROOT / "v2" / "reconstruction"


def _load(path: Path):
    if not path.exists():
        return None
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _touches_edge(rect) -> bool:
    return any(abs(v) >= S16_EDGE for v in rect)


def _is_sentinel(rect) -> bool:
    x0, z0, x1, z1 = rect
    return abs(x1 - x0) > SENTINEL_SPAN or abs(z1 - z0) > SENTINEL_SPAN


def build_graph_index(graph: dict) -> tuple[dict, dict, dict]:
    """Indexa o room_graph por sala.

    Retorna (out_edges, in_edges, nodes):
      out_edges[sala] = arestas que SAEM da sala
      in_edges[sala]  = arestas que CHEGAM na sala (o `arrival` delas e um ponto DESTA sala)
    """
    out_edges: dict[str, list] = {}
    in_edges: dict[str, list] = {}
    for e in graph.get("edges", []):
        out_edges.setdefault(e["src"], []).append(e)
        dst = e.get("to_room_id")
        if dst:
            in_edges.setdefault(dst, []).append(e)
    nodes = {n["id"]: n for n in graph.get("nodes", [])}
    return out_edges, in_edges, nodes


def collect_doors(room_id: str, out_edges: dict, in_edges: dict) -> list[dict]:
    """Portas da sala, ja com as duas pontas da restricao de layout.

    Para cada porta que sai desta sala rumo a B:
      box            -> o gatilho da porta, em coordenadas DESTA sala
      arrival_there  -> onde o jogador aparece em B (coordenadas de B)
      arrival_here   -> onde o jogador aparece AQUI vindo de B (coordenadas desta sala),
                        lido da aresta reciproca B->A. E o par de `arrival_there`:
                        os dois descrevem o MESMO umbral fisico, um em cada sistema local.
    """
    doors = []
    incoming = in_edges.get(room_id, [])
    for i, e in enumerate(out_edges.get(room_id, [])):
        dst = e.get("to_room_id")
        # aresta reciproca: a que sai do destino e chega aqui
        back = next((b for b in incoming if b["src"] == dst), None)
        doors.append({
            "i": i,
            "to_room": dst,
            "to_stage": e.get("to_stage"),
            "to_camera": e.get("to_camera"),
            "sce": e.get("sce"),
            "opcode": e.get("opcode"),
            "box": e.get("box"),
            "arrival_there": e.get("arrival"),
            "arrival_here": back.get("arrival") if back else None,
            "reciprocal": bool(back),
            "dest_conf": e.get("dest_conf"),
        })
    return doors


def collect_gameplay(stage: int, room_id: str) -> dict:
    """Gatilhos, itens, inimigos e objetos da sala — o de-para do jogo original.

    Vem pronto do `{sala}_scd.json` (tools/scd_gameplay.py). Aqui so normalizamos
    o que a v2 consome: tudo com `box`/`quad` em coordenadas LOCAIS da sala, para
    o editor poder desenhar cada gatilho no mesmo espaco da geometria.
    """
    scd = _load(GODOT_DATA / f"STAGE{stage}" / f"{room_id}_scd.json")
    if not scd:
        return {"available": False}

    def strip(entries, keep):
        out = []
        for e in entries or []:
            out.append({k: e[k] for k in keep if k in e})
        return out

    aot_keys = ("aot", "sce", "event", "floor", "kind", "box", "quad", "data")
    return {
        "available": True,
        "triggers": strip(scd.get("triggers"), aot_keys),
        "flags": strip(scd.get("flags"), aot_keys),
        "messages": strip(scd.get("messages"), aot_keys),
        "items": strip(scd.get("items"),
                       ("item_id", "item_name", "amount", "x", "y", "z", "aot", "box", "quad")),
        "enemies": strip(scd.get("enemies"),
                         ("class", "class_hex", "species", "species_conf", "kind",
                          "x", "y", "z", "dir", "weapon", "slot", "model")),
        "objects": strip(scd.get("objects"),
                         ("type_id", "x", "z", "facing", "state", "opcode", "index", "flag")),
        "counts": {
            k: len(scd.get(k) or [])
            for k in ("triggers", "flags", "messages", "items", "enemies", "objects")
        },
    }


def consolidate_room(stage: int, room_id: str, out_edges, in_edges, nodes) -> dict | None:
    godot_dir = GODOT_DATA / f"STAGE{stage}"
    room_dir = RECON / f"STAGE{stage}" / room_id

    col = _load(godot_dir / f"{room_id}_col.json")
    if not col:
        return None
    rdt = _load(godot_dir / f"{room_id}.json") or {}
    rig = _load(room_dir / "cameras.json") or {}

    collision = col.get("collision", {}) or {}
    raw_rects = collision.get("rects", []) or []

    rects = []
    for i, r in enumerate(raw_rects):
        rect = r["rect"]
        rects.append({
            "i": i,
            "rect": rect,                    # [x0, z0, x1, z1] em unidades PS1
            "y": r["y"],                     # Y do PISO do collider (Y do PS1 aponta p/ BAIXO)
            "h": r["h"],                     # ALTURA do collider, nao a coordenada do topo
            "top": r["y"] - r["h"],          # Y p/ baixo => subir h e SUBTRAIR
            "wall": bool(r.get("wall")),
            "type": r.get("type"),
            "edge": _touches_edge(rect),     # encosta no limite s16 — normal em parede externa
            "sentinel": _is_sentinel(rect),  # degenerado: atravessa o mapa, nao e geometria
        })

    solid = [r for r in rects if not r["sentinel"]]
    if solid:
        xs = [v for r in solid for v in (r["rect"][0], r["rect"][2])]
        zs = [v for r in solid for v in (r["rect"][1], r["rect"][3])]
        heights = sorted(r["h"] for r in solid)
        # Pe-direito para a CASCA: a mediana das alturas, nao o rect mais alto.
        # Em R103 (rua) um unico collider alto levava o teto a 40 m; a mediana
        # devolve ~5 m, que e o comodo de verdade.
        ceiling_h = heights[len(heights) // 2]
        y_floor = max(r["y"] for r in solid)
        bounds = {
            "aabb": [min(xs), min(zs), max(xs), max(zs)],
            "size": [max(xs) - min(xs), max(zs) - min(zs)],
            # Y p/ baixo: o piso e o MAIOR y; subir e SUBTRAIR.
            "y_floor": y_floor,
            "y_ceiling": min(r["top"] for r in solid),   # ponto mais alto que existe
            "ceiling_h": ceiling_h,                       # altura tipica -> usar na casca
            "y_ceiling_typical": y_floor - ceiling_h,
        }
    else:
        bounds = None

    # --- cameras: funde o rig da v2 (pos/target/forward + HD) com o RID cru do RDT (attr) ---
    rdt_cams = (rdt.get("rdt", {}) or {}).get("cameras", []) or []
    masks = col.get("cameras_masks", []) or []
    cameras = []
    for c in rig.get("cameras", []):
        idx = c["index"]
        raw = rdt_cams[idx] if idx < len(rdt_cams) else {}
        mk = masks[idx] if idx < len(masks) else None
        hd_name = c.get("hd_background")
        hd_path = room_dir / hd_name if hd_name else None
        cameras.append({
            "index": idx,
            "pos": c["pos"],
            "target": c["target"],
            "forward": c["forward"],
            "distance": c.get("distance"),
            "attr": raw.get("attr"),          # 24 valores distintos no jogo -> provavel FOV por camera
            "flag": raw.get("flag"),
            "hd": hd_name,
            "hd_bytes": hd_path.stat().st_size if hd_path and hd_path.exists() else None,
            "mask": None if not mk else {
                "n_masks": mk.get("n_masks"),
                "z_base": mk.get("z_base"),
                "primary_depth": mk.get("primary_depth"),
                "group_depths": [g.get("depth") for g in (mk.get("groups") or [])],
            },
        })

    node = nodes.get(room_id, {})
    gameplay = collect_gameplay(stage, room_id)
    lights = _load(room_dir / "lights.json")
    return {
        "schema": SCHEMA,
        "generated_by": "v2/tools/consolidate_rooms.py",
        "note": "GERADO. Nao editar a mao - os ajustes vao em room3d.json.",
        "room": room_id,
        "stage": stage,
        "area": node.get("area"),
        "desc": node.get("desc"),
        "units": {
            "world_scale": WORLD_SCALE,
            "to_godot": "(x, -y, z) / 808",
            "to_blender": "(x, z, -y) / 808",
            "y_axis": "PS1 Y aponta para BAIXO",
            "full_turn": FULL_TURN,
            "space": "coordenadas LOCAIS da sala (nao ha espaco mundial; ver stage_layout.json)",
        },
        "bounds": bounds,
        "counts": {
            "rects": len(rects),
            "rects_solid": len(solid),
            "rects_sentinel": len(rects) - len(solid),
            "rects_edge": sum(1 for r in rects if r["edge"] and not r["sentinel"]),
            "rects_wall": sum(1 for r in solid if r["wall"]),
            "cameras": len(cameras),
            "doors": len(out_edges.get(room_id, [])),
            **{f"gp_{k}": v for k, v in (gameplay.get("counts") or {}).items()},
            "lights": (lights or {}).get("counts", {}).get("unique", 0),
        },
        "collision": {"center": collision.get("center"), "rects": rects},
        "cameras": cameras,
        "doors": collect_doors(room_id, out_edges, in_edges),
        "gameplay": gameplay,
        "lights": {
            # decodificacao PARCIAL do LIT — ver v2/tools/extract_lights.py
            "confidence": (lights or {}).get("confidence", "none"),
            "points": (lights or {}).get("lights", []),
        },
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append", help="stage(s) a processar (default: 1..7)")
    args = ap.parse_args()
    stages = args.stage or list(range(1, 8))

    graph = _load(GODOT_DATA / "room_graph.json")
    if not graph:
        raise SystemExit(f"room_graph.json nao encontrado em {GODOT_DATA}")
    out_edges, in_edges, nodes = build_graph_index(graph)

    total = 0
    for stage in stages:
        stage_dir = RECON / f"STAGE{stage}"
        if not stage_dir.exists():
            print(f"STAGE{stage}: pasta ausente, pulando")
            continue
        rooms = sorted(d.name for d in stage_dir.iterdir() if d.is_dir() and d.name.startswith("R"))
        ok = skipped = 0
        no_cam = no_door = 0
        for room_id in rooms:
            data = consolidate_room(stage, room_id, out_edges, in_edges, nodes)
            if data is None:
                skipped += 1
                continue
            with open(stage_dir / room_id / "room.src.json", "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
            ok += 1
            no_cam += not data["counts"]["cameras"]
            no_door += not data["counts"]["doors"]
        total += ok
        print(f"STAGE{stage}: {ok} salas consolidadas"
              f"{f', {skipped} sem colisao' if skipped else ''}"
              f"{f', {no_cam} sem camera' if no_cam else ''}"
              f"{f', {no_door} sem porta' if no_door else ''}")
    print(f"\ntotal: {total} room.src.json")


if __name__ == "__main__":
    main()
