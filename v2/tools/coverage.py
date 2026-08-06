"""coverage.py — quanto de cada sala as fotos do jogo conseguem cobrir.

Pergunta que decide o rumo da v2: se as superfícies forem texturizadas
projetando os backgrounds pré-renderizados, QUANTO fica coberto e quanto sobra
sem foto nenhuma?

Método: amostra pontos no chão e nas paredes de `room.geom.json` e testa, para
cada câmera do RID, se o ponto (a) cai dentro do frustum e (b) está de frente
para ela. Um ponto que nenhuma câmera vê nunca foi fotografado — nenhum truque
de projeção inventa aquele pixel.

Resultado no STAGE1: **61,3% de cobertura média**, de 18% (R117) a 100% (R108).
Ou seja, ~40% das superfícies precisam de textura autoral, não de extração.

Uso:
    python v2/tools/coverage.py --stage 1
    python v2/tools/coverage.py --json
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECON = ROOT / "v2" / "reconstruction"

FOV = math.radians(55)        # sem o FOV por câmera decodificado, usa o da v1
FRUSTUM_SLACK = 1.35          # o frustum real é retangular; cone + folga aproxima
GRID_FLOOR = 14               # amostras por eixo no chão
GRID_WALL_U, GRID_WALL_V = 10, 4


def load(p: Path):
    if not p.exists():
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def cameras_of(src: dict):
    out = []
    for c in src.get("cameras", []):
        if not c.get("hd"):
            continue
        p = (c["pos"][0], -c["pos"][1], c["pos"][2])
        t = (c["target"][0], -c["target"][1], c["target"][2])
        f = [t[i] - p[i] for i in range(3)]
        L = math.sqrt(sum(v * v for v in f))
        if L < 1:
            continue
        out.append((p, [v / L for v in f]))
    return out


def sample_points(geom: dict):
    """Pontos (posição, normal) no chão e nas duas faces de cada parede."""
    pts = []
    fl = geom.get("floor")
    if fl:
        x0, z0, x1, z1 = fl["aabb"]
        fy = -fl["y"]
        for i in range(GRID_FLOOR):
            for j in range(GRID_FLOOR):
                pts.append((
                    (x0 + (x1 - x0) * (i + .5) / GRID_FLOOR, fy,
                     z0 + (z1 - z0) * (j + .5) / GRID_FLOOR),
                    (0, 1, 0),
                ))
    for w in geom.get("walls", []):
        ax, az = w["a"]
        bx, bz = w["b"]
        dx, dz = bx - ax, bz - az
        L = math.hypot(dx, dz)
        if L < 1:
            continue
        nx, nz = -dz / L, dx / L
        by, H = -w["y"], w["height"]
        for i in range(GRID_WALL_U):
            for k in range(GRID_WALL_V):
                p = (ax + dx * (i + .5) / GRID_WALL_U,
                     by + H * (k + .5) / GRID_WALL_V,
                     az + dz * (i + .5) / GRID_WALL_U)
                pts.append((p, (nx, 0, nz)))
                pts.append((p, (-nx, 0, -nz)))
    return pts


def visible(point, normal, cams) -> bool:
    for cam_pos, fwd in cams:
        d = [point[i] - cam_pos[i] for i in range(3)]
        dist = math.sqrt(sum(v * v for v in d))
        if dist < 1:
            continue
        dn = [v / dist for v in d]
        cos_fwd = sum(dn[i] * fwd[i] for i in range(3))
        if cos_fwd <= 0:
            continue
        if math.acos(max(-1.0, min(1.0, cos_fwd))) > FOV * 0.5 * FRUSTUM_SLACK:
            continue
        if sum(-dn[i] * normal[i] for i in range(3)) <= 0.02:
            continue                       # superfície de costas para a câmera
        return True
    return False


def room_coverage(src: dict, geom: dict):
    cams = cameras_of(src)
    pts = sample_points(geom)
    if not cams or not pts:
        return None
    seen = sum(1 for p, n in pts if visible(p, n, cams))
    return {
        "room": src["room"],
        "cameras": len(cams),
        "samples": len(pts),
        "covered": seen,
        "pct": round(100 * seen / len(pts), 1),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append")
    ap.add_argument("--json", action="store_true", help="grava coverage.json por stage")
    args = ap.parse_args()

    for stage in (args.stage or list(range(1, 8))):
        stage_dir = RECON / f"STAGE{stage}"
        if not stage_dir.exists():
            continue
        rows = []
        for d in sorted(stage_dir.iterdir()):
            if not d.is_dir():
                continue
            src = load(d / "room.src.json")
            geom = load(d / "room.geom.json")
            if not src or not geom:
                continue
            r = room_coverage(src, geom)
            if r:
                rows.append(r)
        if not rows:
            continue
        total = sum(r["samples"] for r in rows)
        seen = sum(r["covered"] for r in rows)
        rows.sort(key=lambda r: r["pct"])
        print(f"STAGE{stage}: cobertura media {100 * seen / total:.1f}% "
              f"({len(rows)} salas)")
        print("  piores:   " + ", ".join(f"{r['room']}={r['pct']:.0f}%({r['cameras']}cam)"
                                         for r in rows[:4]))
        print("  melhores: " + ", ".join(f"{r['room']}={r['pct']:.0f}%({r['cameras']}cam)"
                                         for r in rows[-4:]))
        if args.json:
            with open(stage_dir / "coverage.json", "w", encoding="utf-8") as f:
                json.dump({
                    "schema": "re3.stage.coverage/1",
                    "generated_by": "v2/tools/coverage.py",
                    "note": "% das superficies vistas por ALGUMA camera. O resto "
                            "nunca foi fotografado: precisa de textura autoral.",
                    "stage": stage,
                    "fov_deg": 55,
                    "average_pct": round(100 * seen / total, 1),
                    "rooms": rows,
                }, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
