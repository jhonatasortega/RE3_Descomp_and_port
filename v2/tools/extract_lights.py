"""extract_lights.py — extrai os PONTOS DE LUZ do bloco LIT do RDT.

O RE3 se passa a noite: a iluminacao esta assada nos backgrounds, mas o jogo
tambem carrega luzes de verdade (usadas para sombrear os MODELOS sobre a foto).
Sao essas que servem de ponto de partida para iluminar a v2 em 3D real.

Bloco: `offset_table[9]` do RDT (papel "LIT", ver docs/formatos/ARD.md §5).

Layout (engenharia reversa feita aqui, validada nas 169 salas):

    +0  u16 ?            (contador/id, decresce ao longo da sala)
    +2  u16 0            (padding, sempre 0)
    tabela, uma entrada por CAMERA:  u16 n_lights, u16 offset (relativo ao bloco)
    registro de luz, 12 bytes:
      +0  u16 id/indice
      +2  u16 0
      +4  s16 x
      +6  s16 y          (Y do PS1 aponta para BAIXO)
      +8  s16 z
      +10 u16 brightness (sempre multiplo de 100)

**As posicoes sao RELATIVAS A CAMERA**, nao a sala. Medido em salas pequenas
(AABB estrito): `camera.from + (x,y,z)` cai dentro da sala em 60% dos casos,
contra 4% se lidas como absolutas. O resto fica fora do AABB de colisao, o que
e esperado — luz de teto, de rua ou atras de parede nao tem collider.

ESTADO: 🟡 PARCIAL — NAO tratar como verdade absoluta.

O layout acima bate muito bem em parte das salas (R101: ids decrescentes, posicoes
coerentes, brightness sempre multiplo de 100), mas NAO em todas: em R11A os mesmos
12 bytes dao `(0, 0, 1, 248, 3, 1)`, que nao se parece com posicao nenhuma. Ou o
bloco `offset_table[9]` guarda coisas diferentes conforme a sala, ou falta um
discriminador que ainda nao identificamos.

Por isso cada luz sai com `plausible` e cada sala com `confidence`. Consuma apenas
`lights` (ja filtrado); `per_camera` traz o cru para continuar a engenharia reversa.

PENDENTE: (1) a COR da luz — nenhum campo se comporta como RGB, provavelmente vem
de outro bloco ou de paleta fixa, entao `color` sai null e o consumidor deve assumir
ambar noturno; (2) o discriminador que explica as salas em que o layout nao bate.

Saida: v2/reconstruction/STAGE{n}/{sala}/lights.json

Uso:
    python v2/tools/extract_lights.py --stage 1
    python v2/tools/extract_lights.py
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

SCHEMA = "re3.room.lights/1"
LIT_INDEX = 9          # offset_table[9] = iluminacao (LIT)
REC_SIZE = 12
MAX_LIGHTS_PER_CAM = 64

ROOT = Path(__file__).resolve().parents[2]
GODOT_DATA = ROOT / "godot" / "data"
EXTRACTED = ROOT / "extracted" / "ntsc-u" / "CD_DATA"
RECON = ROOT / "v2" / "reconstruction"


def is_plausible(x: int, y: int, z: int, bright: int) -> bool:
    """Filtro de sanidade de um registro de luz.

    Assinaturas de um registro BOM (vistas em R101 e afins):
      - brightness > 0 e multiplo de 100 (todos os reais sao redondos);
      - o deslocamento em relacao a camera tem magnitude de cena (centenas de
        unidades PS1 para cima), nao 1..3 como no lixo de R11A.
    """
    if bright <= 0 or bright % 100 != 0:
        return False
    if max(abs(x), abs(y), abs(z)) < 500:
        return False
    return True


def read_rdt(stage: int, room: str):
    """Devolve (bytes do RDT, metadados do JSON) ou (None, None)."""
    meta_path = GODOT_DATA / f"STAGE{stage}" / f"{room}.json"
    ard_path = EXTRACTED / f"STAGE{stage}" / f"{room}.ARD"
    if not meta_path.exists() or not ard_path.exists():
        return None, None
    with open(meta_path, "r", encoding="utf-8") as f:
        meta = json.load(f)
    blk = meta["blocks"][meta["rdt"]["block_index"]]
    raw = ard_path.read_bytes()
    return raw[blk["offset"]: blk["offset"] + blk["length"]], meta


def parse_lights(rdt: bytes, meta: dict) -> dict | None:
    base = meta["rdt"]["offset_table"][LIT_INDEX]
    ncam = meta["rdt"]["n_cameras"]
    cams = meta["rdt"]["cameras"]
    if not base or base + 4 + ncam * 4 > len(rdt):
        return None

    per_camera = []
    total = good = 0
    for ci in range(ncam):
        n, off = struct.unpack_from("<2H", rdt, base + 4 + ci * 4)
        if n > MAX_LIGHTS_PER_CAM or base + off + n * REC_SIZE > len(rdt):
            return None                          # layout nao bate: aborta a sala
        cam_from = cams[ci]["from"] if ci < len(cams) else [0, 0, 0]
        lights = []
        for li in range(n):
            p = base + off + li * REC_SIZE
            idx, _pad, x, y, z, bright = struct.unpack_from("<HH3hH", rdt, p)
            if x == 0 and y == 0 and z == 0 and bright == 0:
                continue                          # registro nulo (preenchimento)
            lights.append({
                "i": li,
                "id": idx,
                "offset_from_camera": [x, y, z],
                "pos": [cam_from[0] + x, cam_from[1] + y, cam_from[2] + z],
                "brightness": bright,
                "color": None,                    # nao identificado no bloco
                "plausible": is_plausible(x, y, z, bright),
            })
        total += len(lights)
        good += sum(1 for L in lights if L["plausible"])
        per_camera.append({"camera": ci, "n_declared": n, "lights": lights})

    return {"per_camera": per_camera, "total": total, "plausible": good}


def dedupe(parsed: dict, tol: int = 300) -> list[dict]:
    """Junta luzes repetidas entre cameras (a mesma lampada aparece em varias).

    Duas luzes viram uma se ficam a menos de `tol` unidades PS1 uma da outra.
    """
    uniq: list[dict] = []
    for cam in parsed["per_camera"]:
        for L in cam["lights"]:
            if not L["plausible"]:
                continue                    # so entra no resultado o que passa na sanidade
            x, y, z = L["pos"]
            hit = None
            for u in uniq:
                ux, uy, uz = u["pos"]
                if abs(ux - x) <= tol and abs(uy - y) <= tol and abs(uz - z) <= tol:
                    hit = u
                    break
            if hit:
                hit["seen_in"].append(cam["camera"])
                hit["brightness"] = max(hit["brightness"], L["brightness"])
            else:
                uniq.append({
                    "pos": L["pos"],
                    "brightness": L["brightness"],
                    "color": None,
                    "seen_in": [cam["camera"]],
                })
    return uniq


def run_room(stage: int, room: str) -> dict | None:
    rdt, meta = read_rdt(stage, room)
    if rdt is None:
        return None
    parsed = parse_lights(rdt, meta)
    if parsed is None:
        return None
    uniq = dedupe(parsed)
    return {
        "schema": SCHEMA,
        "generated_by": "v2/tools/extract_lights.py",
        "note": ("Pontos de luz do bloco LIT (offset_table[9]). Posicoes sao "
                 "camera.from + offset. COR nao decodificada: assumir ambar noturno."),
        "room": room,
        "stage": stage,
        "units": {"world_scale": 808, "space": "coordenadas LOCAIS da sala", "y_axis": "PS1 Y para BAIXO"},
        "counts": {
            "raw": parsed["total"],
            "plausible": parsed["plausible"],
            "unique": len(uniq),
            "cameras": len(parsed["per_camera"]),
        },
        "confidence": (
            "none" if not parsed["total"]
            else "high" if parsed["plausible"] == parsed["total"]
            else "mixed" if parsed["plausible"]
            else "low"
        ),
        "lights": uniq,
        "per_camera": parsed["per_camera"],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--stage", type=int, action="append")
    args = ap.parse_args()

    grand = 0
    for stage in (args.stage or list(range(1, 8))):
        stage_dir = RECON / f"STAGE{stage}"
        if not stage_dir.exists():
            continue
        ok = failed = 0
        n_lights = 0
        conf = {"high": 0, "mixed": 0, "low": 0, "none": 0}
        for d in sorted(stage_dir.iterdir()):
            if not d.is_dir() or not d.name.startswith("R"):
                continue
            data = run_room(stage, d.name)
            if data is None:
                failed += 1
                continue
            with open(d / "lights.json", "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
            ok += 1
            n_lights += data["counts"]["unique"]
            conf[data["confidence"]] += 1
        grand += n_lights
        print(f"STAGE{stage}: {ok} salas, {n_lights} luzes utilizaveis | "
              f"confianca: {conf['high']} alta, {conf['mixed']} mista, "
              f"{conf['low']} baixa (descartada), {conf['none']} sem dado"
              + (f" | {failed} layout incompativel" if failed else ""))
    print(f"\ntotal: {grand} pontos de luz que passam na sanidade")
    print("ATENCAO: decodificacao do LIT e PARCIAL — ver docstring do script.")


if __name__ == "__main__":
    main()
