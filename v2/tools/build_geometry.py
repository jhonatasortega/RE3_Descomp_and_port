"""build_geometry.py — gera a GEOMETRIA da sala a partir dos dados do jogo.

Ponte entre "volumes de colisão" e "cômodo modelado". O RE3 não guarda malha de
cenário (é tudo pré-renderizado), mas guarda o suficiente para um primeiro corte
honesto da arquitetura:

  rects `wall`  -> segmentos de parede, com espessura e altura reais
  portas (grafo)-> vãos recortados na parede que elas atravessam
  AABB + piso   -> chão e teto

O que NÃO sai daqui: móveis, detalhes, salas em L de verdade. Os rects `prop`
são volumes de bloqueio de altura cheia (em R100 todos com os 5,0 m do
pé-direito), então NÃO viram geometria — viram colisão invisível.

Saída: v2/reconstruction/STAGE{n}/{sala}/room.geom.json  (GERADO)
Os ajustes manuais continuam em `room3d.json`, que o editor aplica por cima.

Uso:
    python v2/tools/build_geometry.py --stage 1
    python v2/tools/build_geometry.py
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

SCHEMA = "re3.room.geom/1"
WORLD_SCALE = 808.0
DOOR_HEIGHT = 2000        # unidades PS1 (~2,5 m) quando o dado não diz a altura
DOOR_MARGIN = 900         # tolerância para dizer que a porta atravessa a parede
MIN_WALL_LEN = 200        # abaixo disto o rect é ruído, não parede

ROOT = Path(__file__).resolve().parents[2]
RECON = ROOT / "v2" / "reconstruction"


def _load(p: Path):
    if not p.exists():
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def rect_to_wall(r: dict) -> dict | None:
    """Converte o rect de colisão num segmento de parede com espessura.

    O rect é uma AABB fina: o lado MAIOR é o comprimento da parede, o menor é a
    espessura. A linha de centro é o que a modelagem usa.
    """
    x0, z0, x1, z1 = r["rect"]
    x0, x1 = min(x0, x1), max(x0, x1)
    z0, z1 = min(z0, z1), max(z0, z1)
    w, d = x1 - x0, z1 - z0

    if max(w, d) < MIN_WALL_LEN:
        return None

    if w >= d:                                  # corre ao longo de X
        cz = (z0 + z1) / 2
        a, b, thickness = (x0, cz), (x1, cz), max(d, 60)
    else:                                       # corre ao longo de Z
        cx = (x0 + x1) / 2
        a, b, thickness = (cx, z0), (cx, z1), max(w, 60)

    return {
        "from_rect": r["i"],
        "a": [round(a[0]), round(a[1])],
        "b": [round(b[0]), round(b[1])],
        "thickness": round(thickness),
        "y": r["y"],                            # piso do collider
        "height": r["h"],                       # altura (não é coordenada de topo)
        "length": round(math.dist(a, b)),
        "edge": r.get("edge", False),
        "openings": [],
    }


def project_on_segment(p, a, b):
    """Devolve (u em 0..1, distância perpendicular) do ponto ao segmento."""
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    if L2 < 1e-6:
        return 0.0, math.dist(p, a)
    u = ((p[0] - ax) * dx + (p[1] - az) * dz) / L2
    u = max(0.0, min(1.0, u))
    proj = (ax + u * dx, az + u * dz)
    return u, math.dist(p, proj)


def door_center_and_span(box: dict, wall: dict):
    """Centro do gatilho e quanto ele ocupa AO LONGO da parede."""
    cx = box["x"] + box.get("w", 0) / 2
    cz = box["z"] + box.get("d", 0) / 2
    ax, az = wall["a"]
    bx, bz = wall["b"]
    horizontal = abs(bx - ax) >= abs(bz - az)
    span = box.get("w", 0) if horizontal else box.get("d", 0)
    return (cx, cz), max(span, 800)


def carve_openings(walls: list[dict], doors: list[dict]) -> int:
    """Recorta um vão na parede que cada porta atravessa.

    Escolhe a parede mais próxima do gatilho: a caixa da porta fica em cima do
    umbral, então a parede correta é a que passa por baixo dela.
    """
    carved = 0
    for door in doors:
        box = door.get("box")
        if not box:
            continue
        best = None
        for wall in walls:
            center, span = door_center_and_span(box, wall)
            u, dist = project_on_segment(center, wall["a"], wall["b"])
            limit = wall["thickness"] / 2 + DOOR_MARGIN
            if dist > limit:
                continue
            if best is None or dist < best[1]:
                best = (wall, dist, u, span)
        if not best:
            continue
        wall, dist, u, span = best
        wall["openings"].append({
            "kind": "door",
            "door_index": door.get("i"),
            "to_room": door.get("to_room"),
            "u": round(u, 4),                    # posição ao longo da parede
            "width": round(span),
            "height": DOOR_HEIGHT,
            "sill": 0,                           # porta nasce no piso
            "source": "grafo",
        })
        carved += 1
    return carved


def build_room(src: dict) -> dict | None:
    bounds = src.get("bounds")
    if not bounds:
        return None

    rects = src.get("collision", {}).get("rects", [])
    walls = []
    for r in rects:
        if r.get("sentinel") or not r.get("wall"):
            continue
        w = rect_to_wall(r)
        if w:
            walls.append(w)

    carved = carve_openings(walls, src.get("doors", []))

    # Colisão que NÃO vira geometria: os volumes de bloqueio.
    blockers = [
        {"from_rect": r["i"], "rect": r["rect"], "y": r["y"], "h": r["h"]}
        for r in rects if not r.get("sentinel") and not r.get("wall")
    ]

    y_floor = bounds["y_floor"]
    ceiling_h = bounds.get("ceiling_h") or abs(y_floor - bounds["y_ceiling"])

    return {
        "schema": SCHEMA,
        "generated_by": "v2/tools/build_geometry.py",
        "note": ("GERADO a partir da colisao + grafo de portas. Primeiro corte da "
                 "arquitetura, nao modelagem final. Ajustes vao em room3d.json."),
        "room": src["room"],
        "stage": src["stage"],
        "units": {"world_scale": WORLD_SCALE, "y_axis": "PS1 Y para BAIXO"},
        "floor": {
            "aabb": bounds["aabb"],
            "y": y_floor,
        },
        "ceiling": {
            "aabb": bounds["aabb"],
            "y": y_floor - ceiling_h,
            "height": ceiling_h,
        },
        "walls": walls,
        "blockers": blockers,
        "counts": {
            "walls": len(walls),
            "openings": carved,
            "doors": len(src.get("doors", [])),
            "blockers": len(blockers),
        },
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append")
    args = ap.parse_args()

    grand = {"rooms": 0, "walls": 0, "openings": 0, "no_wall": 0, "doors": 0}
    for stage in (args.stage or list(range(1, 8))):
        stage_dir = RECON / f"STAGE{stage}"
        if not stage_dir.exists():
            continue
        n = w = o = nw = 0
        for d in sorted(stage_dir.iterdir()):
            if not d.is_dir() or not d.name.startswith("R"):
                continue
            src = _load(d / "room.src.json")
            if not src:
                continue
            geom = build_room(src)
            if not geom:
                continue
            with open(d / "room.geom.json", "w", encoding="utf-8") as f:
                json.dump(geom, f, ensure_ascii=False, indent=1)
            n += 1
            w += geom["counts"]["walls"]
            o += geom["counts"]["openings"]
            grand["doors"] += geom["counts"]["doors"]
            if not geom["counts"]["walls"]:
                nw += 1
        grand["rooms"] += n
        grand["walls"] += w
        grand["openings"] += o
        grand["no_wall"] += nw
        print(f"STAGE{stage}: {n} salas | {w} paredes | {o} vaos de porta"
              + (f" | {nw} salas SEM parede na colisao" if nw else ""))

    print(f"\ntotal: {grand['rooms']} salas, {grand['walls']} paredes, "
          f"{grand['openings']}/{grand['doors']} portas viraram vao")
    if grand["no_wall"]:
        print(f"ATENCAO: {grand['no_wall']} salas nao tem nenhum rect marcado como "
              f"parede — precisam ser modeladas do zero.")


if __name__ == "__main__":
    main()
