"""solve_layout.py — resolve o LAYOUT GLOBAL de um stage a partir das portas.

Problema: o RE3 nao tem espaco mundial. Cada sala usa o range inteiro de s16
localmente (99% dos AABB do STAGE1 se sobrepoem se plotados crus). Para montar o
mapa 3D navegavel precisamos de uma pose (rotacao + translacao no plano XZ) por sala.

Restricao que resolve isso: cada porta reciproca A<->B da um par de pontos que
descrevem O MESMO umbral fisico, um em cada sistema local:

    arrival_here  (ponto em A, facing apontando para DENTRO de A)   <- vindo de B
    arrival_there (ponto em B, facing apontando para DENTRO de B)   <- vindo de A

Atravessar a porta nao teleporta: o par de pontos coincide no mundo e os dois
facings sao OPOSTOS. Logo, para a transformada T_AB que leva coordenadas de B
para o frame de A:

    theta = (f_here - f_there) + meia-volta
    t     = p_here - R(theta) * p_there

Como a convencao de sinal do angulo do RE3 (horario/anti-horario) e a fase da
meia-volta nao estao documentadas, o script TESTA as 4 combinacoes e escolhe a
que fecha melhor os ciclos do grafo -- o proprio dado decide a convencao.

SNAP ORTOGONAL: medido nas 108 portas do STAGE1, 82% das rotacoes relativas caem
a menos de 15 graus de um multiplo de 90 (desvio mediano 3,5 graus). As salas do
RE3 sao ortogonais entre si; o residuo e ruido do dado. Arredondar cada rotacao
para o multiplo de 90 mais proximo elimina o drift que, sem snap, acumulava ~22
graus de erro medio de fechamento. Arestas cujo desvio passa de TOL_SNAP_DEG sao
marcadas `suspect` no relatorio em vez de contaminarem o layout.

Depois: arvore geradora (BFS) da a pose inicial, e uma relaxacao Gauss-Seidel
distribui o erro pelas arestas redundantes (portas fora da arvore).

Saida: v2/reconstruction/STAGE{n}/stage_layout.json
       (poses + relatorio de erro por aresta + componentes desconexos)

Uso:
    python v2/tools/solve_layout.py --stage 1
    python v2/tools/solve_layout.py            # todos
"""
from __future__ import annotations

import argparse
import json
import math
from collections import deque
from pathlib import Path

SCHEMA = "re3.stage.layout/1"
FULL_TURN = 4096
WORLD_SCALE = 808.0
RELAX_ITERS = 200
TOL_SNAP_DEG = 25.0     # acima disto o snap ortogonal e chute: marca a porta como suspeita

ROOT = Path(__file__).resolve().parents[2]
RECON = ROOT / "v2" / "reconstruction"


# ---------------------------------------------------------------- geometria 2D

def rot(a: float):
    return math.cos(a), math.sin(a)


def apply(pose, p):
    """pose = (ca, sa, tx, tz) aplicada ao ponto local (x, z)."""
    ca, sa, tx, tz = pose
    x, z = p
    return (ca * x - sa * z + tx, sa * x + ca * z + tz)


def compose(outer, inner):
    """outer ∘ inner: leva o frame de `inner` (expresso em outer) para o mundo."""
    ca, sa, tx, tz = outer
    cb, sb, bx, bz = inner
    return (ca * cb - sa * sb,
            sa * cb + ca * sb,
            ca * bx - sa * bz + tx,
            sa * bx + ca * bz + tz)


def pose_angle(pose) -> float:
    return math.atan2(pose[1], pose[0])


# ---------------------------------------------------------------- restricoes

def load_stage(stage: int) -> dict[str, dict]:
    stage_dir = RECON / f"STAGE{stage}"
    rooms = {}
    if not stage_dir.exists():
        return rooms
    for d in sorted(stage_dir.iterdir()):
        src = d / "room.src.json"
        if d.is_dir() and src.exists():
            with open(src, "r", encoding="utf-8") as f:
                rooms[d.name] = json.load(f)
    return rooms


def _box_point(box: dict, mode: str):
    """Ponto de ancoragem do gatilho da porta. `box.x/z` parece ser o CANTO
    (a mediana de |arrival - canto| e 1,8 m contra 3,0 m para o centro), mas a
    escolha e decidida empiricamente junto com a convencao angular."""
    if not box:
        return None
    if mode == "box_center":
        return (box["x"] + box.get("w", 0) / 2, box["z"] + box.get("d", 0) / 2)
    return (box["x"], box["z"])


def build_constraints(rooms: dict, sign: int, half_turn: float,
                      anchor: str = "arrival", snap: bool = True,
                      rot_mode: str = "facing") -> list[dict]:
    """Uma restricao por porta reciproca, sob uma convencao candidata.

    `anchor` escolhe QUAIS pontos correspondentes ancoram a translacao:
      arrival     -> arrival_here <-> arrival_there (lados opostos do umbral, ~3 m de vao)
      box_corner  -> gatilho da porta A <-> gatilho da porta de volta em B (mesmo umbral)
      box_center  -> idem, usando o centro da caixa

    `rot_mode`:
      facing -> rotacao relativa derivada dos dois `facing` de chegada
      zero   -> todas as salas na MESMA orientacao, so translacao. Medido no STAGE1:
                102/108 portas fecham com erro < 2 m e mediana 0,00 m, contra 2,45 m
                de erro medio do modo `facing`. As salas do RE3 compartilham os eixos;
                o que muda entre elas e so a origem (offset mediano de 32 m).
    """
    quarter = math.pi / 2
    cons = []
    for rid, room in rooms.items():
        for door in room.get("doors", []):
            dst = door.get("to_room")
            if not dst or dst not in rooms or not door.get("reciprocal"):
                continue
            if door.get("to_stage") != room.get("stage"):
                continue                                  # porta entre stages: outro grafo
            here, there = door.get("arrival_here"), door.get("arrival_there")
            if not here or not there:
                continue

            if rot_mode == "zero":
                theta, snap_dev = 0.0, 0.0
            else:
                theta = sign * (here["facing"] - there["facing"]) * (2 * math.pi / FULL_TURN) + half_turn
                snap_dev = 0.0
            if snap and rot_mode != "zero":
                snapped = round(theta / quarter) * quarter
                snap_dev = abs(math.degrees(theta - snapped))
                theta = snapped

            if anchor == "arrival":
                p_here, p_there = (here["x"], here["z"]), (there["x"], there["z"])
            else:
                back = next((d for d in rooms[dst].get("doors", []) if d.get("to_room") == rid), None)
                p_here = _box_point(door.get("box"), anchor)
                p_there = _box_point(back.get("box") if back else None, anchor)
                if not p_here or not p_there:
                    continue

            ca, sa = rot(theta)
            px, pz = p_there
            tx = p_here[0] - (ca * px - sa * pz)
            tz = p_here[1] - (sa * px + ca * pz)
            cons.append({
                "a": rid, "b": dst, "T": (ca, sa, tx, tz), "door": door["i"],
                "snap_dev_deg": round(snap_dev, 1),
                "suspect": snap_dev > TOL_SNAP_DEG,
            })
    return cons


def spanning_poses(rooms: dict, cons: list[dict]):
    """BFS por componente conexo. Retorna (poses, componentes, arestas fora da arvore)."""
    adj: dict[str, list] = {r: [] for r in rooms}
    for c in cons:
        adj[c["a"]].append((c["b"], c["T"], c))
        # aresta inversa: T^-1 leva A para o frame de B
        ca, sa, tx, tz = c["T"]
        inv = (ca, -sa, -(ca * tx + sa * tz), -(-sa * tx + ca * tz))
        adj[c["b"]].append((c["a"], inv, c))

    poses: dict[str, tuple] = {}
    components: list[list[str]] = []
    tree_edges = set()

    for start in rooms:
        if start in poses:
            continue
        poses[start] = (1.0, 0.0, 0.0, 0.0)
        comp = [start]
        q = deque([start])
        while q:
            cur = q.popleft()
            for nxt, T, c in adj[cur]:
                if nxt in poses:
                    continue
                poses[nxt] = compose(poses[cur], T)
                tree_edges.add(id(c))
                comp.append(nxt)
                q.append(nxt)
        components.append(comp)

    loop_cons = [c for c in cons if id(c) not in tree_edges]
    return poses, components, loop_cons


def cycle_error(poses: dict, cons: list[dict]) -> tuple[float, float]:
    """Erro medio (translacao em unidades PS1, rotacao em graus) das restricoes."""
    if not cons:
        return 0.0, 0.0
    et = er = 0.0
    for c in cons:
        pa, pb = poses.get(c["a"]), poses.get(c["b"])
        if not pa or not pb:
            continue
        pred = compose(pa, c["T"])
        et += math.hypot(pred[2] - pb[2], pred[3] - pb[3])
        d = abs(math.degrees(pose_angle(pred) - pose_angle(pb))) % 360.0
        er += min(d, 360.0 - d)
    n = len(cons)
    return et / n, er / n


def relax(poses: dict, cons: list[dict], iters: int = RELAX_ITERS):
    """Gauss-Seidel nas TRANSLACOES (rotacoes ficam as da arvore).

    Cada restricao puxa as duas salas para a posicao que a porta exige; iterar
    espalha o erro de fechamento pelo ciclo em vez de acumular na ultima aresta.
    """
    for _ in range(iters):
        acc = {r: [0.0, 0.0, 0] for r in poses}
        for c in cons:
            pa, pb = poses.get(c["a"]), poses.get(c["b"])
            if not pa or not pb:
                continue
            pred = compose(pa, c["T"])            # onde B deveria estar, segundo A
            dx, dz = pred[2] - pb[2], pred[3] - pb[3]
            acc[c["b"]][0] += dx * 0.5
            acc[c["b"]][1] += dz * 0.5
            acc[c["b"]][2] += 1
            acc[c["a"]][0] -= dx * 0.5
            acc[c["a"]][1] -= dz * 0.5
            acc[c["a"]][2] += 1
        for r, (dx, dz, n) in acc.items():
            if n:
                ca, sa, tx, tz = poses[r]
                poses[r] = (ca, sa, tx + dx / n, tz + dz / n)
    return poses


# ---------------------------------------------------------------- relatorio

def room_aabb_world(room: dict, pose) -> list[float] | None:
    b = room.get("bounds")
    if not b:
        return None
    x0, z0, x1, z1 = b["aabb"]
    pts = [apply(pose, p) for p in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return [min(xs), min(zs), max(xs), max(zs)]


def overlap_report(rooms: dict, poses: dict) -> dict:
    boxes = {}
    for rid, room in rooms.items():
        bb = room_aabb_world(room, poses[rid]) if rid in poses else None
        if bb:
            boxes[rid] = bb
    ids = sorted(boxes)
    pairs = 0
    worst = []
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            A, B = boxes[a], boxes[b]
            ox = min(A[2], B[2]) - max(A[0], B[0])
            oz = min(A[3], B[3]) - max(A[1], B[1])
            if ox > 0 and oz > 0:
                pairs += 1
                worst.append((ox * oz / (WORLD_SCALE ** 2), a, b))
    worst.sort(reverse=True)
    total = len(ids) * (len(ids) - 1) // 2
    return {
        "pairs_overlapping": pairs,
        "pairs_total": total,
        "pct": round(100 * pairs / total, 1) if total else 0.0,
        "worst": [{"rooms": [a, b], "area_m2": round(m2, 1)} for m2, a, b in worst[:8]],
    }


def solve_stage(stage: int, verbose: bool = True) -> dict | None:
    rooms = load_stage(stage)
    if not rooms:
        print(f"STAGE{stage}: sem room.src.json (rode consolidate_rooms.py antes)")
        return None

    # Nem a convencao angular do facing nem o significado de box.x/z estao
    # documentados -> enumera os candidatos e deixa o fechamento de ciclo decidir.
    best = None
    trials = []
    candidates = [("zero", 1, 0.0, a, False) for a in ("arrival", "box_corner", "box_center")]
    candidates += [("facing", s, h, a, sn)
                   for s in (1, -1) for h in (math.pi, 0.0)
                   for a in ("arrival", "box_corner", "box_center") for sn in (True, False)]

    for rot_mode, sign, half, anchor, snap in candidates:
        cons = build_constraints(rooms, sign, half, anchor, snap, rot_mode)
        if not cons:
            continue
        poses, comps, loops = spanning_poses(rooms, cons)
        et, er = cycle_error(poses, loops)
        trials.append({
            "rot_mode": rot_mode, "sign": sign, "half_turn_deg": round(math.degrees(half)),
            "anchor": anchor, "snap90": snap, "loop_edges": len(loops),
            "err_translation_m": round(et / WORLD_SCALE, 2),
            "err_rotation_deg": round(er, 2),
        })
        # 1 grau de erro de rotacao entorta a sala inteira: pesa como ~0,5 m
        score = et / WORLD_SCALE + er * 0.5
        if best is None or score < best["score"]:
            best = {"score": score, "rot_mode": rot_mode, "sign": sign, "half": half,
                    "anchor": anchor, "snap": snap, "cons": cons,
                    "poses": poses, "comps": comps, "loops": loops}

    if best is None:
        print(f"STAGE{stage}: nenhuma porta reciproca utilizavel")
        return None

    before = cycle_error(best["poses"], best["loops"])
    poses = relax(dict(best["poses"]), best["cons"])
    after = cycle_error(poses, best["loops"])

    comps = sorted(best["comps"], key=len, reverse=True)
    out = {
        "schema": SCHEMA,
        "generated_by": "v2/tools/solve_layout.py",
        "note": ("Poses derivadas das portas. E um PALPITE BOM, nao verdade absoluta: "
                 "ajuste fino e manual no editor (room3d.json.transform sobrepoe isto)."),
        "stage": stage,
        "units": {"world_scale": WORLD_SCALE, "space": "XZ em unidades PS1; rot em graus"},
        "convention": {
            "rot_mode": best["rot_mode"],
            "sign": best["sign"],
            "half_turn_deg": round(math.degrees(best["half"])),
            "anchor": best["anchor"],
            "snap90": best["snap"],
            "chosen_by": "menor erro de fechamento de ciclo",
            "trials": sorted(trials, key=lambda t: t["err_translation_m"] + t["err_rotation_deg"])[:6],
        },
        "quality": {
            "constraints": len(best["cons"]),
            "loop_edges": len(best["loops"]),
            "err_before_relax": {"translation_m": round(before[0] / WORLD_SCALE, 2),
                                 "rotation_deg": round(before[1], 2)},
            "err_after_relax": {"translation_m": round(after[0] / WORLD_SCALE, 2),
                                "rotation_deg": round(after[1], 2)},
            "suspect_doors": [
                {"from": c["a"], "to": c["b"], "door": c["door"],
                 "snap_dev_deg": c["snap_dev_deg"]}
                for c in best["cons"] if c.get("suspect")
            ],
        },
        "components": [{"size": len(c), "rooms": sorted(c)} for c in comps],
        "rooms": {},
    }

    for rid in sorted(rooms):
        pose = poses.get(rid)
        if not pose:
            continue
        out["rooms"][rid] = {
            "tx": round(pose[2], 1),
            "tz": round(pose[3], 1),
            "rot_deg": round(math.degrees(pose_angle(pose)), 2),
            "aabb_world": [round(v, 1) for v in (room_aabb_world(rooms[rid], pose) or [])] or None,
            "solved": True,
        }

    out["overlap"] = overlap_report(rooms, poses)

    stage_dir = RECON / f"STAGE{stage}"
    with open(stage_dir / "stage_layout.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)

    if verbose:
        q = out["quality"]
        print(f"STAGE{stage}: {len(out['rooms'])}/{len(rooms)} salas posicionadas | "
              f"{q['constraints']} restricoes ({q['loop_edges']} redundantes)")
        print(f"  convencao: rot={best['rot_mode']} anchor={best['anchor']}"
              + (f" sign={best['sign']} half={round(math.degrees(best['half']))}deg snap90={best['snap']}"
                 if best["rot_mode"] != "zero" else ""))
        if q["suspect_doors"]:
            print(f"  portas suspeitas (snap >{TOL_SNAP_DEG:.0f}deg): {len(q['suspect_doors'])} "
                  f"-> {', '.join(f'{d['from']}>{d['to']}' for d in q['suspect_doors'][:5])}")
        print(f"  erro de fechamento: {q['err_before_relax']['translation_m']}m -> "
              f"{q['err_after_relax']['translation_m']}m  "
              f"(rot {q['err_after_relax']['rotation_deg']}deg)")
        print(f"  componentes: {[c['size'] for c in out['components']]}")
        print(f"  sobreposicao de salas: {out['overlap']['pct']}% dos pares")
        if out["overlap"]["worst"]:
            w = out["overlap"]["worst"][0]
            print(f"  pior: {w['rooms'][0]}x{w['rooms'][1]} = {w['area_m2']} m2")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append")
    args = ap.parse_args()
    for stage in (args.stage or list(range(1, 8))):
        solve_stage(stage)


if __name__ == "__main__":
    main()
