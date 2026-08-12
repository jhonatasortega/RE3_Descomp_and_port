"""
exporter.py — Exporta salas do RE3 para OBJ ou GLB.
Sistema de coordenadas Blender: (x, z, -y) / 808
"""
import json
import math
import tempfile
from pathlib import Path

WORLD_SCALE = 808.0


def _m(v):
    return v / WORLD_SCALE


def _bl(x, y, z):
    """PS1 → Blender: (x, z, -y) / scale"""
    return (_m(x), _m(z), -_m(y))


def export_rooms(room_ids: list, fmt: str, include_cameras: bool, custom_boxes: list, recon_dir: Path) -> Path:
    """
    Exporta uma lista de salas para .obj ou .glb.
    Retorna o caminho do arquivo gerado em /tmp.
    """
    if fmt == "glb":
        return _export_glb(room_ids, include_cameras, custom_boxes, recon_dir)
    return _export_obj(room_ids, include_cameras, custom_boxes, recon_dir)


# ---------------------------------------------------------------------------
# OBJ export
# ---------------------------------------------------------------------------

def _export_obj(room_ids: list, include_cameras: bool, custom_boxes: list, recon_dir: Path) -> Path:
    lines = ["# RE3 Scene Forge — OBJ export", "# Blender: (x, z, -y) / 808", ""]
    voff = 1  # vertex offset (OBJ é 1-indexed)

    def _box(cx, cy, cz, sx, sy, sz, group_name):
        nonlocal voff, lines
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        verts = [
            (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
            (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
            (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
        ]
        faces = [
            (1, 2, 3, 4), (5, 8, 7, 6), (1, 5, 6, 2),
            (2, 6, 7, 3), (3, 7, 8, 4), (4, 8, 5, 1),
        ]
        lines.append(f"g {group_name}")
        for v in verts:
            lines.append(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}")
        for f in faces:
            fi = " ".join(str(voff + i - 1) for i in f)
            lines.append(f"f {fi}")
        voff += len(verts)
        lines.append("")

    for rid in room_ids:
        rid = rid.upper()
        room_dir, src, stage = _find_room(rid, recon_dir)
        if src is None:
            continue
        b = src.get("bounds", {})
        pose = _get_pose(rid, stage, recon_dir)
        tx, tz = pose.get("tx", 0), pose.get("tz", 0)

        lines.append(f"# ---- {rid} — {src.get('desc', '')} ----")

        for r in src.get("collision", {}).get("rects", []):
            if r.get("hidden"):
                continue
            x0, z0, x1, z1 = r["rect"]
            h = abs(r.get("h", 1000))
            y  = r.get("y", 0)

            cx_ps1 = (x0 + x1) / 2 + tx
            cz_ps1 = (z0 + z1) / 2 + tz
            cy_ps1 = -y + h / 2

            cx, cy, cz = _bl(cx_ps1, -cy_ps1, cz_ps1)
            sx = _m(abs(x1 - x0))
            sy = _m(h)
            sz = _m(abs(z1 - z0))

            kind = "wall" if r.get("wall") else "prop"
            _box(cx, cy, cz, sx, sy, sz, f"{rid}_rect{r['i']}_{kind}")

        # Câmeras como empties (comentário + vertex pontual)
        if include_cameras:
            for cam in src.get("cameras", []):
                px, py, pz = [cam["pos"][i] + (tx if i == 0 else tz if i == 2 else 0) for i in range(3)]
                bx, by, bz = _bl(px, py, pz)
                lines.append(f"# camera {cam['index']} pos={bx:.3f},{by:.3f},{bz:.3f}")
                lines.append(f"v {bx:.4f} {by:.4f} {bz:.4f}")
                lines.append(f"p {voff}")
                voff += 1
                lines.append("")

        # Custom boxes (do front-end)
        s_base = 1000.0 / WORLD_SCALE
        for i, box in enumerate(custom_boxes):
            if box["roomId"] == rid:
                px, py, pz = box["pos"]
                sx, sy, sz = box["scale"]
                
                # Para OBJ, Y e Z são invertidos em relação ao Blender?
                # O exportador faz _bl que mapeia (x, z, -y)/808
                # No front-end (px,py,pz) já são (x/808, -y/808, z/808)
                # Então cx = px + tx/808, cy = py, cz = pz + tz/808? Não, _box espera coordenadas Blender.
                cx = px + _m(tx)
                cy = pz + _m(tz)
                cz = py
                
                _box(cx, cy, cz, s_base * sx, s_base * sz, s_base * sy, f"{rid}_customBox{i}")

    tmp = Path(tempfile.mkdtemp()) / "re3_export.obj"
    tmp.write_text("\n".join(lines), encoding="utf-8")
    return tmp


# ---------------------------------------------------------------------------
# GLB export (trimesh)
# ---------------------------------------------------------------------------

def _export_glb(room_ids: list, include_cameras: bool, custom_boxes: list, recon_dir: Path) -> Path:
    try:
        import trimesh
        import numpy as np
    except ImportError:
        raise RuntimeError("trimesh e numpy são necessários para export GLB. Execute: pip install trimesh numpy")

    scene = trimesh.Scene()

    for rid in room_ids:
        rid = rid.upper()
        room_dir, src, stage = _find_room(rid, recon_dir)
        if src is None:
            continue
        pose = _get_pose(rid, stage, recon_dir)
        tx, tz = pose.get("tx", 0), pose.get("tz", 0)

        for r in src.get("collision", {}).get("rects", []):
            if r.get("hidden"):
                continue
            x0, z0, x1, z1 = r["rect"]
            h   = abs(r.get("h", 1000))
            y   = r.get("y", 0)

            cx_ps1 = (x0 + x1) / 2 + tx
            cz_ps1 = (z0 + z1) / 2 + tz
            cy_ps1 = -y + h / 2

            cx, cy, cz = _bl(cx_ps1, -cy_ps1, cz_ps1)
            sx = max(_m(abs(x1 - x0)), 0.01)
            sy = max(_m(h), 0.01)
            sz = max(_m(abs(z1 - z0)), 0.01)

            box = trimesh.creation.box(extents=[sx, sy, sz])
            box.apply_translation([cx, cy, cz])

            kind = "wall" if r.get("wall") else "prop"
            # Cor por tipo
            if r.get("wall"):
                box.visual.vertex_colors = [107, 116, 136, 200]
            else:
                box.visual.vertex_colors = [162, 118, 47, 200]

            scene.add_geometry(box, node_name=f"{rid}_rect{r['i']}_{kind}")

        # Câmeras como nodes
        if include_cameras:
            for cam in src.get("cameras", []):
                px = cam["pos"][0] + tx
                py = cam["pos"][1]
                pz = cam["pos"][2] + tz
                bx, by, bz = _bl(px, py, pz)

                # Marcador de câmera: esfera pequena
                sph = trimesh.creation.icosphere(radius=0.15)
                sph.apply_translation([bx, by, bz])
                sph.visual.vertex_colors = [126, 224, 129, 255]
                scene.add_geometry(sph, node_name=f"{rid}_cam{cam['index']}")

        # Custom boxes (do front-end)
        s_base = 1000.0 / WORLD_SCALE
        for i, box in enumerate(custom_boxes):
            if box["roomId"] == rid:
                px, py, pz = box["pos"]
                sx, sy, sz = box["scale"]
                rx, ry, rz = box["rot"]
                
                cx = px + _m(tx)
                cy = pz + _m(tz)
                cz = py
                
                dimX = s_base * sx
                dimY = s_base * sz
                dimZ = s_base * sy
                
                m = trimesh.creation.box(extents=[dimX, dimY, dimZ])
                # Rotação (Three.js default Euler is XYZ? YXZ)
                # Convertendo Euler rot para GLB/Blender: (rx, ry, rz) no ThreeJS.
                # Eixo Y ThreeJS = Eixo Z GLB.
                # Aproximação simples para Y:
                rot_mat = trimesh.transformations.euler_matrix(rx, ry, rz, 'sxyz')
                m.apply_transform(rot_mat)
                
                m.apply_translation([cx, cy, cz])
                m.visual.vertex_colors = [0, 255, 170, 200]
                
                scene.add_geometry(m, node_name=f"{rid}_customBox{i}")

    tmp = Path(tempfile.mkdtemp()) / "re3_export.glb"
    scene.export(str(tmp))
    return tmp


# ---------------------------------------------------------------------------
# Helpers internos
# ---------------------------------------------------------------------------

def _find_room(room_id: str, recon_dir: Path):
    for s in range(1, 8):
        d = recon_dir / f"STAGE{s}" / room_id
        if d.exists():
            src_path = d / "room.src.json"
            if src_path.exists():
                src = json.loads(src_path.read_text(encoding="utf-8"))
                return d, src, s
    return None, None, None


def _get_pose(room_id: str, stage: int, recon_dir: Path) -> dict:
    layout_path = recon_dir / f"STAGE{stage}" / "stage_layout.json"
    if not layout_path.exists():
        return {"tx": 0, "tz": 0, "rot_deg": 0}
    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    return layout.get("rooms", {}).get(room_id, {"tx": 0, "tz": 0, "rot_deg": 0})
