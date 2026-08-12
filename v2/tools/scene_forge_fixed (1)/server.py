"""
RE3 Scene Forge — servidor Flask
Serve a SPA e a API de dados do Resident Evil 3.
"""
import json
import os
import re
import glob
from pathlib import Path
from flask import Flask, jsonify, request, send_file, send_from_directory, abort
from flask_cors import CORS

# ---------------------------------------------------------------------------
# Configuração de caminhos (ajuste se necessário)
# ---------------------------------------------------------------------------
BASE = Path(__file__).resolve().parent          # .../v2/tools/scene_forge
V2   = BASE.parent.parent                       # .../v2
RECON = V2 / "reconstruction"                  # v2/reconstruction/STAGE{n}/
PORT_DATA  = V2.parent / "port" / "data"       # port/data/
PORT_ASSETS = V2.parent / "port" / "assets"   # port/assets/STAGE{n}/
STATIC = BASE / "static"

WORLD_SCALE = 808.0
NUM_STAGES  = 7

app = Flask(__name__, static_folder=str(STATIC))
CORS(app)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _load_json(path: Path):
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return None


def _stage_rooms(stage: int) -> list[str]:
    """Retorna IDs de sala ordenados para um stage (a partir dos dirs em RECON)."""
    stage_dir = RECON / f"STAGE{stage}"
    if not stage_dir.exists():
        return []
    rooms = sorted(
        d.name for d in stage_dir.iterdir()
        if d.is_dir() and re.match(r"^R[0-9A-F]{3}$", d.name, re.I)
    )
    return rooms


def _room_asset_dir(stage: int, room_id: str) -> Path | None:
    """Descobre onde estão os .webp/.png de uma sala.

    Suporta dois layouts:
      1) reconstruction/STAGE{n}/{room}/{room}_{i}.webp   (layout atual dos dados)
      2) port/assets/STAGE{n}/{room}_{i}.webp             (layout legado)
    """
    room_dir = RECON / f"STAGE{stage}" / room_id
    if room_dir.exists() and any(room_dir.glob(f"{room_id.upper()}_*.webp")):
        return room_dir
    legacy_dir = PORT_ASSETS / f"STAGE{stage}"
    if legacy_dir.exists():
        return legacy_dir
    return None


def _room_backgrounds(stage: int, room_id: str) -> list[str]:
    """Lista os nomes de arquivo dos backgrounds HD de uma sala (sem caminho)."""
    asset_dir = _room_asset_dir(stage, room_id)
    if not asset_dir:
        return []
    prefix = room_id.upper()
    # Pega .webp e .png, exclui _tmp
    files = sorted([
        f.name for f in asset_dir.iterdir()
        if f.stem.startswith(prefix + "_")
           and "_tmp" not in f.stem
           and f.suffix in (".webp", ".png")
    ], key=lambda n: int(re.search(r"_(\d+)\.", n).group(1)) if re.search(r"_(\d+)\.", n) else 999)
    return files


# ---------------------------------------------------------------------------
# Rotas de dados
# ---------------------------------------------------------------------------

@app.get("/api/stages")
def api_stages():
    stages = []
    for s in range(1, NUM_STAGES + 1):
        rooms = _stage_rooms(s)
        if rooms:
            stages.append({"stage": s, "room_count": len(rooms), "rooms": rooms})
    return jsonify(stages)


@app.get("/api/stage/<int:stage>")
def api_stage(stage: int):
    rooms = _stage_rooms(stage)
    if not rooms:
        abort(404, f"Stage {stage} não encontrado")

    layout_path = RECON / f"STAGE{stage}" / "stage_layout.json"
    layout = _load_json(layout_path) or {}

    # Monta sumário rápido de cada sala
    room_summaries = []
    for rid in rooms:
        src = _load_json(RECON / f"STAGE{stage}" / rid / "room.src.json") or {}
        b   = src.get("bounds", {})
        pose = layout.get("rooms", {}).get(rid, {"tx": 0, "tz": 0, "rot_deg": 0})
        bgs  = _room_backgrounds(stage, rid)
        thumb = bgs[0] if bgs else None
        room_summaries.append({
            "id": rid,
            "desc": src.get("desc", ""),
            "area": src.get("area", ""),
            "pose": pose,
            "bounds": b,
            "camera_count": src.get("counts", {}).get("cameras", 0),
            "door_count": src.get("counts", {}).get("doors", 0),
            "thumb": f"/assets/STAGE{stage}/{thumb}" if thumb else None,
        })

    return jsonify({
        "stage": stage,
        "layout": layout,
        "rooms": room_summaries,
    })


@app.get("/api/room/<room_id>")
def api_room(room_id: str):
    room_id = room_id.upper()
    # Descobre o stage pela ID (R1xx → stage 1, etc.)
    stage = _room_stage(room_id)
    if stage is None:
        abort(404, f"Sala {room_id} não encontrada")

    room_dir = RECON / f"STAGE{stage}" / room_id
    src  = _load_json(room_dir / "room.src.json")
    geom = _load_json(room_dir / "room.geom.json")

    if src is None:
        abort(404, f"room.src.json não encontrado para {room_id}")

    # Backgrounds com URL servível
    bgs = _room_backgrounds(stage, room_id)
    bg_urls = {int(re.search(r"_(\d+)\.", f).group(1)): f"/assets/STAGE{stage}/{f}"
               for f in bgs if re.search(r"_(\d+)\.", f)}

    # Enriquece cada câmera com a URL do background
    for cam in src.get("cameras", []):
        idx = cam.get("index", 0)
        cam["bg_url"] = bg_urls.get(idx)

    return jsonify({
        "stage": stage,
        "room": src,
        "geom": geom,
        "bg_urls": bg_urls,
    })


@app.get("/api/room/<room_id>/cameras")
def api_room_cameras(room_id: str):
    """Retorna só as câmeras com URLs de background."""
    room_id = room_id.upper()
    stage = _room_stage(room_id)
    if stage is None:
        abort(404)
    src = _load_json(RECON / f"STAGE{stage}" / room_id / "room.src.json") or {}
    bgs = _room_backgrounds(stage, room_id)
    bg_urls = {int(re.search(r"_(\d+)\.", f).group(1)): f"/assets/STAGE{stage}/{f}"
               for f in bgs if re.search(r"_(\d+)\.", f)}
    cameras = []
    for cam in src.get("cameras", []):
        c = dict(cam)
        c["bg_url"] = bg_urls.get(cam.get("index", 0))
        cameras.append(c)
    return jsonify(cameras)


@app.post("/api/room/<room_id>/edit")
def api_room_edit(room_id: str):
    """Salva edições manuais em room3d.json (nunca toca room.src.json)."""
    room_id = room_id.upper()
    stage = _room_stage(room_id)
    if stage is None:
        abort(404)
    data = request.get_json(force=True)
    if not data:
        abort(400, "Body JSON inválido")
    out_path = RECON / f"STAGE{stage}" / room_id / "room3d.json"
    out_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return jsonify({"ok": True, "saved": str(out_path)})


@app.get("/api/graph")
def api_graph():
    """Retorna o room_graph.json completo (grafo de portas)."""
    g = _load_json(PORT_DATA / "room_graph.json")
    if g is None:
        abort(404, "room_graph.json não encontrado")
    return jsonify(g)


@app.post("/api/export")
def api_export():
    """Exporta salas para OBJ ou GLB e retorna o arquivo para download."""
    import exporter
    req = request.json
    rooms = req.get('rooms', [])
    fmt = req.get('format', 'obj')
    inc_cams = req.get('include_cameras', True)
    custom_boxes = req.get('custom_boxes', [])
    try:
        out = exporter.export_rooms(rooms, fmt, inc_cams, custom_boxes, RECON)
        return send_file(out, as_attachment=True, download_name=out.name)
    except Exception as e:
        abort(500, str(e))


# ---------------------------------------------------------------------------
# Servir assets (backgrounds HD)
# ---------------------------------------------------------------------------

@app.get("/assets/STAGE<int:stage>/<path:filename>")
def serve_asset(stage: int, filename: str):
    # O nome do arquivo comeca com o ID da sala (ex.: R100_0.webp) -> usa isso
    # para achar a pasta certa (reconstruction/STAGE{n}/{room}/ ou o legado).
    room_id = filename.split("_")[0].upper()
    asset_dir = _room_asset_dir(stage, room_id) or (PORT_ASSETS / f"STAGE{stage}")
    return send_from_directory(asset_dir, filename)


# ---------------------------------------------------------------------------
# Servir SPA
# ---------------------------------------------------------------------------

@app.get("/")
def index():
    return send_file(STATIC / "index.html")


@app.get("/<path:path>")
def static_files(path: str):
    full = STATIC / path
    if full.exists() and full.is_file():
        return send_file(full)
    return send_file(STATIC / "index.html")


# ---------------------------------------------------------------------------
# Utilitários internos
# ---------------------------------------------------------------------------

def _room_stage(room_id: str) -> int | None:
    """Descobre o stage de uma sala procurando nos dirs de RECON."""
    for s in range(1, NUM_STAGES + 1):
        if (RECON / f"STAGE{s}" / room_id).exists():
            return s
    return None


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 60)
    print("  RE3 Scene Forge")
    print(f"  Dados:  {RECON}")
    print(f"  Assets: {PORT_ASSETS}")
    print("  Acesse: http://localhost:5000")
    print("=" * 60)
    app.run(debug=True, port=5000, host="127.0.0.1")
