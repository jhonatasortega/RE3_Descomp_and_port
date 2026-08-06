"""bake_textures.py — assa os backgrounds pré-renderizados nas superfícies da sala.

Fecha o ciclo da v2: transforma as fotos do jogo em TEXTURAS de parede, chão e
teto, para a sala poder ser percorrida livremente em vez de só olhada do ponto
exato de cada câmera.

Como funciona, por superfície (uma parede, o chão, o teto):

 1. a superfície é um retângulo no espaço 3D; cada texel vira um ponto 3D;
 2. o ponto é projetado em TODAS as câmeras do RID daquela sala;
 3. entre as que o enxergam (dentro do quadro, de frente e SEM OBSTÁCULO no
    caminho), ganha a de melhor score = cos(ângulo com a normal) / distância² —
    quem vê mais de frente e mais de perto;
 4. texel que nenhuma câmera vê fica BURACO;
 5. os buracos são preenchidos com um material tileável extraído dos próprios
    texels cobertos (recorte espelhado), então a superfície fecha inteira sem
    inventar arte de fora do jogo.

O passo 5 existe porque só ~60% das superfícies foram fotografadas (ver
coverage.py). Sem ele, 40% da sala fica cinza.

O teste de oclusão do passo 3 usa os **volumes de colisão** (`blockers` do
room.geom.json) como obstáculos. É o uso certo para eles: inúteis como geometria
visível — são caixas de altura cheia —, descrevem exatamente onde há um armário
ou uma pilha de caixas tapando a vista. Sem esse teste, os móveis da foto
escorrem pelo chão, porque o pixel de um armário acaba pintado no piso atrás.

Saída: v2/reconstruction/STAGE{n}/{sala}/tex/*.png + tex/index.json

Uso:
    python v2/tools/bake_textures.py --stage 1 --room R100
    python v2/tools/bake_textures.py --stage 1
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

SCHEMA = "re3.room.baked/1"
WORLD_SCALE = 808.0
FOV = math.radians(55)
ASPECT = 320 / 240
PX_PER_M = 42            # resolução da textura assada
MAX_SIDE = 1024
MIN_SIDE = 16
TILE_MIN = 24            # menor retalho aceitável para virar material tileável

# Os volumes de colisão têm ALTURA CHEIA: um armário de 1 m vira caixa de 5 m,
# do chão ao teto. Usá-los inteiros como oclusores derruba o chão de R100 de 78%
# para 8,6% de cobertura — eles tapam como colunas. Este fator corta a caixa para
# uma altura plausível de móvel. É heurística: o jogo não guarda a altura real.
BLOCKER_HEIGHT = 0.45

ROOT = Path(__file__).resolve().parents[2]
RECON = ROOT / "v2" / "reconstruction"


def load(p: Path):
    if not p.exists():
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


# ----------------------------------------------------------------- oclusão

def collect_occluders(geom, include_walls=False) -> np.ndarray:
    """AABBs que tapam a vista.

    Por padrão SÓ os móveis (`blockers`). As paredes ficam de fora: as câmeras do
    RE3 são posicionadas dentro/acima delas (a cena original era renderizada sem
    a parede da frente), então tratá-las como oclusores derruba a cobertura de
    78% para 4% no chão de R100 — recorta justamente o que a foto mostra.

    Devolve array (N,6) = [xmin, ymin, zmin, xmax, ymax, zmax] em coords de
    mundo (Y já invertido, crescendo para cima).
    """
    boxes = []
    for b in geom.get("blockers", []):
        x0, z0, x1, z1 = b["rect"]
        y0 = -b["y"]                       # piso do volume
        y1 = y0 + b["h"] * BLOCKER_HEIGHT  # topo plausível do móvel
        boxes.append([min(x0, x1), y0, min(z0, z1), max(x0, x1), y1, max(z0, z1)])
    if include_walls:
        for w in geom.get("walls", []):
            ax, az = w["a"]
            bx, bz = w["b"]
            half = w["thickness"] / 2
            y0 = -w["y"]
            y1 = y0 + w["height"]
            boxes.append([
                min(ax, bx) - half, y0, min(az, bz) - half,
                max(ax, bx) + half, y1, max(az, bz) + half,
            ])
    return np.array(boxes, float) if boxes else np.zeros((0, 6))


def occluded(pts, cam_pos, boxes, eps=90.0, cam_slack=900.0, cam_frac=0.15):
    """Para cada ponto, diz se a reta até a câmera cruza algum AABB.

    Slab method vetorizado, com duas folgas necessárias:

    `eps` afasta a origem da própria superfície — sem isso a parede do ponto se
    auto-oclui.

    `cam_slack`/`cam_frac` encurtam o raio ANTES de chegar à câmera. Isso não é
    tolerância numérica: as câmeras pré-renderizadas do RE3 ficam embutidas na
    geometria — a câmera 1 de R100 está 198 unidades acima do topo de uma parede,
    e sem essa folga aquela parede bloqueava 100% dos raios, zerando a sala.
    """
    n = len(pts)
    if len(boxes) == 0:
        return np.zeros(n, bool)

    d = cam_pos - pts
    dist = np.linalg.norm(d, axis=1)
    dist = np.maximum(dist, 1e-3)
    dirs = d / dist[:, None]
    origins = pts + dirs * eps
    tmax_ray = dist - eps - np.maximum(cam_slack, dist * cam_frac)

    blocked = np.zeros(n, bool)
    safe = np.where(np.abs(dirs) < 1e-9, 1e-9, dirs)
    inv = 1.0 / safe

    for box in boxes:
        lo = (box[:3] - origins) * inv
        hi = (box[3:] - origins) * inv
        t0 = np.minimum(lo, hi).max(axis=1)
        t1 = np.maximum(lo, hi).min(axis=1)
        hit = (t1 >= np.maximum(t0, 0.0)) & (t0 < tmax_ray) & (t1 > 0)
        blocked |= hit
        if blocked.all():
            break
    return blocked


# ------------------------------------------------------------------ câmeras

class Camera:
    """Câmera do RID, em coordenadas de mundo (Y já invertido)."""

    def __init__(self, entry, image):
        p = np.array([entry["pos"][0], -entry["pos"][1], entry["pos"][2]], float)
        t = np.array([entry["target"][0], -entry["target"][1], entry["target"][2]], float)
        f = t - p
        n = np.linalg.norm(f)
        self.ok = n > 1
        if not self.ok:
            return
        self.pos = p
        self.fwd = f / n
        up = np.array([0.0, 1.0, 0.0])
        r = np.cross(self.fwd, up)
        rn = np.linalg.norm(r)
        if rn < 1e-6:                       # câmera olhando reto para baixo
            up = np.array([0.0, 0.0, 1.0])
            r = np.cross(self.fwd, up)
            rn = np.linalg.norm(r)
        self.right = r / rn
        self.up = np.cross(self.right, self.fwd)
        self.img = image
        self.h, self.w = image.shape[:2]
        self.ty = math.tan(FOV / 2)
        self.tx = self.ty * ASPECT

    def sample(self, pts, normal, occluders=None):
        """Amostra a foto nos pontos dados.

        Devolve (cor RGB, score, máscara de válidos). Score negativo = inválido.
        """
        d = pts - self.pos                       # (N,3)
        zc = d @ self.fwd
        xc = d @ self.right
        yc = d @ self.up

        with np.errstate(divide="ignore", invalid="ignore"):
            ndc_x = np.nan_to_num((xc / zc) / self.tx, nan=9e9, posinf=9e9, neginf=-9e9)
            ndc_y = np.nan_to_num((yc / zc) / self.ty, nan=9e9, posinf=9e9, neginf=-9e9)

        px = np.clip((ndc_x * 0.5 + 0.5) * (self.w - 1), 0, self.w - 1)
        py = np.clip((1.0 - (ndc_y * 0.5 + 0.5)) * (self.h - 1), 0, self.h - 1)

        valid = (zc > 1.0) & (np.abs(ndc_x) < 1.0) & (np.abs(ndc_y) < 1.0)

        dist = np.linalg.norm(d, axis=1)
        dist = np.maximum(dist, 1.0)
        # de frente para a câmera? (normal contra a direção de chegada)
        facing = -((d / dist[:, None]) @ normal)
        valid &= facing > 0.08

        # oclusão: só testa quem já passou nos filtros baratos
        if occluders is not None and len(occluders) and valid.any():
            idx = np.nonzero(valid)[0]
            blocked = occluded(pts[idx], self.pos, occluders)
            valid[idx[blocked]] = False

        score = np.where(valid, facing / (dist ** 2), -1.0)

        xi = px.astype(np.int32)
        yi = py.astype(np.int32)
        color = self.img[yi, xi]
        return color, score, valid


# ------------------------------------------------------- material tileável

def make_tile(color, filled):
    """Extrai um retalho sólido e o torna tileável por espelhamento.

    Procura a maior janela quadrada totalmente coberta; espelhar garante bordas
    contínuas sem precisar de síntese de textura.
    """
    h, w = filled.shape
    if not filled.any():
        return None

    # integral image: soma de cobertura, para achar janela cheia rapidamente
    integral = np.zeros((h + 1, w + 1), np.int32)
    integral[1:, 1:] = np.cumsum(np.cumsum(filled.astype(np.int32), 0), 1)

    def full(y, x, s):
        return (integral[y + s, x + s] - integral[y, x + s]
                - integral[y + s, x] + integral[y, x]) == s * s

    # Centroide do que foi fotografado: o retalho deve sair do MIOLO da área
    # coberta, não da primeira janela sólida que aparecer. Sem isso o chão de
    # R100 puxava um pedaço escuro de armário na borda e a sala inteira ficava
    # com um padrão de losangos pretos.
    ys, xs = np.nonzero(filled)
    cy, cx = ys.mean(), xs.mean()

    best = None
    size = min(h, w)
    while size >= TILE_MIN and best is None:
        step = max(1, size // 6)
        candidates = []
        for y in range(0, h - size + 1, step):
            for x in range(0, w - size + 1, step):
                if full(y, x, size):
                    d = (y + size / 2 - cy) ** 2 + (x + size / 2 - cx) ** 2
                    candidates.append((d, y, x))
        if candidates:
            _, y, x = min(candidates)
            best = (y, x, size)
        else:
            size = int(size * 0.7)

    if best is None:                     # nada sólido: usa a cor média do que há
        mean = color[filled].mean(axis=0).astype(np.uint8)
        return np.tile(mean, (TILE_MIN, TILE_MIN, 1))

    y, x, s = best
    patch = color[y:y + s, x:x + s]
    # espelha nos dois eixos -> as bordas casam quando repetido
    top = np.concatenate([patch, patch[:, ::-1]], axis=1)
    return np.concatenate([top, top[::-1]], axis=0)


def fill_holes(color, filled, tile):
    """Preenche o que nenhuma câmera viu com o material tileável."""
    if tile is None:
        return color, 0
    h, w = filled.shape
    th, tw = tile.shape[:2]
    ys, xs = np.nonzero(~filled)
    if len(ys) == 0:
        return color, 0
    color[ys, xs] = tile[ys % th, xs % tw]
    return color, len(ys)


# ---------------------------------------------------------------- superfícies

def surface_points(origin, u_axis, v_axis, nu, nv):
    """Grade de pontos 3D no retângulo definido por origem + dois eixos."""
    u = (np.arange(nu) + 0.5) / nu
    v = (np.arange(nv) + 0.5) / nv
    uu, vv = np.meshgrid(u, v)
    return (origin
            + uu[..., None] * u_axis
            + vv[..., None] * v_axis).reshape(-1, 3)


def bake_surface(name, origin, u_axis, v_axis, normal, cams, occluders=None):
    """Assa uma superfície retangular. Devolve (imagem, estatísticas)."""
    lu = np.linalg.norm(u_axis) / WORLD_SCALE      # metros
    lv = np.linalg.norm(v_axis) / WORLD_SCALE
    nu = int(np.clip(lu * PX_PER_M, MIN_SIDE, MAX_SIDE))
    nv = int(np.clip(lv * PX_PER_M, MIN_SIDE, MAX_SIDE))

    pts = surface_points(origin, u_axis, v_axis, nu, nv)
    best_score = np.full(len(pts), -1.0)
    best_color = np.zeros((len(pts), 3), np.uint8)

    for cam in cams:
        color, score, _ = cam.sample(pts, normal, occluders)
        take = score > best_score
        best_score[take] = score[take]
        best_color[take] = color[take]

    filled = (best_score > 0).reshape(nv, nu)
    img = best_color.reshape(nv, nu, 3)
    # a grade V cresce para cima no mundo; imagem cresce para baixo
    img = img[::-1].copy()
    filled = filled[::-1].copy()

    covered = int(filled.sum())
    tile = make_tile(img, filled)
    img, patched = fill_holes(img, filled, tile)

    return img, {
        "name": name,
        "size": [nu, nv],
        "covered_px": covered,
        "total_px": nu * nv,
        "coverage": round(100 * covered / (nu * nv), 1),
        "patched_px": patched,
    }


def wall_surfaces(geom):
    """Cada parede vira duas faces (uma para cada lado)."""
    out = []
    for i, w in enumerate(geom.get("walls", [])):
        ax, az = w["a"]
        bx, bz = w["b"]
        dx, dz = bx - ax, bz - az
        L = math.hypot(dx, dz)
        if L < 1:
            continue
        nx, nz = -dz / L, dx / L
        half = w["thickness"] / 2
        base_y = -w["y"]
        H = w["height"]
        for side in (1, -1):
            origin = np.array([ax + nx * half * side, base_y, az + nz * half * side])
            out.append({
                "name": f"wall{i}_{'a' if side > 0 else 'b'}",
                "wall": i,
                "side": "a" if side > 0 else "b",
                "origin": origin,
                "u": np.array([dx, 0.0, dz]),
                "v": np.array([0.0, H, 0.0]),
                "normal": np.array([nx * side, 0.0, nz * side]),
            })
    return out


def slab_surfaces(geom):
    out = []
    fl = geom.get("floor")
    if fl:
        x0, z0, x1, z1 = fl["aabb"]
        out.append({
            "name": "floor", "wall": None, "side": None,
            "origin": np.array([x0, -fl["y"], z0]),
            "u": np.array([x1 - x0, 0.0, 0.0]),
            "v": np.array([0.0, 0.0, z1 - z0]),
            "normal": np.array([0.0, 1.0, 0.0]),
        })
    ce = geom.get("ceiling")
    if ce:
        x0, z0, x1, z1 = ce["aabb"]
        out.append({
            "name": "ceiling", "wall": None, "side": None,
            "origin": np.array([x0, -ce["y"], z0]),
            "u": np.array([x1 - x0, 0.0, 0.0]),
            "v": np.array([0.0, 0.0, z1 - z0]),
            "normal": np.array([0.0, -1.0, 0.0]),
        })
    return out


def bake_room(stage: int, room: str, verbose=True):
    d = RECON / f"STAGE{stage}" / room
    src = load(d / "room.src.json")
    geom = load(d / "room.geom.json")
    if not src or not geom:
        return None

    cams = []
    for c in src.get("cameras", []):
        if not c.get("hd"):
            continue
        path = d / c["hd"]
        if not path.exists():
            continue
        cam = Camera(c, np.asarray(Image.open(path).convert("RGB")))
        if cam.ok:
            cams.append(cam)
    if not cams:
        return None

    out_dir = d / "tex"
    out_dir.mkdir(exist_ok=True)

    occluders = collect_occluders(geom)
    surfaces = wall_surfaces(geom) + slab_surfaces(geom)
    entries = []
    for s in surfaces:
        img, stats = bake_surface(s["name"], s["origin"], s["u"], s["v"], s["normal"],
                                  cams, occluders)
        fname = f"{s['name']}.png"
        Image.fromarray(img).save(out_dir / fname, optimize=True)
        entries.append({**stats, "file": fname, "wall": s["wall"], "side": s["side"]})

    total = sum(e["total_px"] for e in entries)
    cov = sum(e["covered_px"] for e in entries)
    index = {
        "schema": SCHEMA,
        "generated_by": "v2/tools/bake_textures.py",
        "note": ("Texturas assadas dos backgrounds. `coverage` e o quanto veio de "
                 "foto real; o resto foi preenchido com material tileavel extraido "
                 "da propria superficie."),
        "room": room,
        "stage": stage,
        "fov_deg": 55,
        "cameras": len(cams),
        "coverage": round(100 * cov / total, 1) if total else 0,
        "surfaces": entries,
    }
    with open(out_dir / "index.json", "w", encoding="utf-8") as f:
        json.dump(index, f, ensure_ascii=False, indent=1)

    if verbose:
        print(f"  {room}: {len(entries)} superficies, {len(cams)} cameras, "
              f"{index['coverage']}% de foto real")
    return index


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append")
    ap.add_argument("--room", action="append")
    args = ap.parse_args()

    for stage in (args.stage or list(range(1, 8))):
        stage_dir = RECON / f"STAGE{stage}"
        if not stage_dir.exists():
            continue
        rooms = args.room or sorted(
            d.name for d in stage_dir.iterdir() if d.is_dir() and d.name.startswith("R")
        )
        print(f"STAGE{stage}:")
        done = 0
        covs = []
        for room in rooms:
            r = bake_room(stage, room)
            if r:
                done += 1
                covs.append(r["coverage"])
        if covs:
            print(f"  -> {done} salas assadas, cobertura media {sum(covs)/len(covs):.1f}%")


if __name__ == "__main__":
    main()
