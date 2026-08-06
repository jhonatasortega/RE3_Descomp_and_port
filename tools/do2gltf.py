#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
do2gltf.py - Converte os MODELOS DE PORTA do RE3 (PS1, NTSC-U) para .glb.

Os arquivos `STAGE#/DOOR##.DO#` (76 por stage; a extensao .DO1..DO7 = o numero do
stage) sao os modelos+textura da PORTA usada na animacao de transicao entre salas
(a "cutscene" curta de porta abrindo do RE classico).

Formato do conteiner `.DO#` (RE byte-a-byte -- ver docs/decomp/notes/doors_model.md):

  +0x00  header (0x40 bytes): 2 u32 constantes (0x00601408, 0x00612408), depois
         u32 nParts (@+0x1c) e alguns offsets/flags. NAO usado p/ a malha renderizavel.
  +0x40  tabela de partes: nParts registros de 0x20 bytes (marcador 'b1 b2' @+0x0e).
  ...    BLOCO GRANDE (~12-20 KB, alta entropia): e' a ANIMACAO de abertura (PROVADO por
         independencia malha<->bloco; ver doc). Cabecalho decodificado (u16 @+2 = nframes = 6);
         payload por-frame bit-packed IRREDUTIVEL (mesma familia do stream in-RAM de inimigo).
         A abertura e' rotacao RIGIDA da folha em torno da dobradica -> exportada via --anim
         (dobradica extraida da geometria; nframes do bloco). NAO contem vertices crus.
  ...    padding 0x00
  BLOCO DE MALHA RENDERIZAVEL (termina exatamente onde comeca o TIM):
    - lista de TRIANGULOS: N registros de 12 bytes, estilo emd3_triangle_t, com o
      campo (page,flag) @+2 == 0x7800 (flag 0x78). Layout:
        u8 tu0,tv0 ; u8 page(=0),flag(=0x78) ; u8 tu1,tv1 ; u8 clut,v0 ;
        u8 tu2,tv2 ; u8 v1,v2
    - ARRAY DE VERTICES (4 bytes depois do fim dos triangulos): (maxidx+1) verts de
      8 bytes cada = `s16 x ; s16 pad(==0) ; s16 z ; s16 y`  (a POSICAO util e' x,y,z).
  TIM @fim: textura 8bpp+CLUT, 1 paleta, 128x256 (formato PS1 padrao).

Reaproveita o pipeline de `pld2gltf.py` (parse_tim_atlas / assemble_static /
write_glb_static). Sem esqueleto (malha estatica texturizada).

Uso:
  python tools/do2gltf.py <DOORxx.DOn> <saida.glb>
  python tools/do2gltf.py --all [n_por_stage]     # exporta N portas de cada stage
                                                    p/ godot/assets/DOOR/
"""
import os, sys, struct, glob
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pld2gltf as P

ROOT = os.path.join("extracted", "ntsc-u", "CD_DATA")


def s16(d, o): return struct.unpack_from("<h", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]


def find_tim(d):
    """TIM = ultimo bloco que comeca com 0x10 00 00 00 + flag valido (9 = 8bpp+CLUT)."""
    n = len(d)
    for i in range(n - 8, -1, -4):
        if d[i] == 0x10 and d[i + 1:i + 4] == b"\x00\x00\x00" and u32(d, i + 4) in (2, 3, 8, 9):
            return i
    return None


def parse_mesh(d):
    """Retorna (verts, tris). tris = (vidx3, uv3, clut, page)."""
    n = len(d)
    tim = find_tim(d)
    if tim is None:
        raise ValueError("TIM nao encontrado")
    # marcadores 0x7800 (campo page/flag dos triangulos), passo 12
    marks = [i for i in range(0, tim - 1, 2) if d[i] == 0x00 and d[i + 1] == 0x78]
    if not marks:
        raise ValueError("nenhuma primitiva 0x7800")
    # run contiguo de passo 12 que termina mais perto do TIM
    marks = [m for m in marks if m + 10 <= tim]
    tris = []
    maxidx = 0
    for m in marks:
        b = m - 2
        tu0, tv0 = d[b], d[b + 1]
        page, flag = d[b + 2], d[b + 3]
        tu1, tv1 = d[b + 4], d[b + 5]
        clut, v0 = d[b + 6], d[b + 7]
        tu2, tv2 = d[b + 8], d[b + 9]
        v1, v2 = d[b + 10], d[b + 11]
        if flag != 0x78:
            continue
        tris.append(((v0, v1, v2), ((tu0, tv0), (tu1, tv1), (tu2, tv2)), clut, page))
        maxidx = max(maxidx, v0, v1, v2)
    tri_end = marks[-1] - 2 + 12
    nv = maxidx + 1
    # array de vertices: 1o offset (alinhado a 4) apos os triangulos com nv registros
    # de 8B cujo campo +2 (pad) == 0 e coordenadas nao-nulas.
    vb = None
    for cand in range(tri_end, tim - nv * 8, 4):
        ok = True
        allzero = True
        for i in range(nv):
            x, pad, z, y = struct.unpack_from("<4h", d, cand + i * 8)
            if pad != 0:
                ok = False
                break
            if x or y or z:
                allzero = False
        if ok and not allzero:
            vb = cand
            break
    if vb is None:
        raise ValueError("array de vertices nao localizado")
    verts = []
    for i in range(nv):
        x, pad, z, y = struct.unpack_from("<4h", d, vb + i * 8)
        verts.append((x, y, z))       # posicao util: x, y(=campo+6), z(=campo+4)
    return verts, tris, tim


def build_objs(verts, tris, npal, band_h):
    """Constroi 1 objeto no formato esperado por pld2gltf.assemble_static, com
    normais por-vertice (media das faces adjacentes, em coords PS1)."""
    import math
    norms = [[0.0, 0.0, 0.0] for _ in verts]
    for (vi, uv, clut, page) in tris:
        a, b, c = (verts[vi[0]], verts[vi[1]], verts[vi[2]])
        ux, uy, uz = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        vx, vy, vz = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        for k in vi:
            norms[k][0] += nx; norms[k][1] += ny; norms[k][2] += nz
    fnorms = []
    for nx, ny, nz in norms:
        L = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        fnorms.append((nx / L * 4096, ny / L * 4096, nz / L * 4096))
    prims = []
    for (vi, uv, clut, page) in tris:
        pal = clut & 0x3F
        tx = (page >> 6) & 3
        prims.append(("tri", vi, uv, pal, tx))
    return [dict(verts=verts, norms=fnorms, prims=prims)]


def convert(path, out_glb):
    d = open(path, "rb").read()
    verts, tris, tim = parse_mesh(d)
    aw, ah, band_h, npal, atlas_rgb = P.parse_tim_atlas(d, tim)
    objs = build_objs(verts, tris, npal, band_h)
    Pp, N, UV, faces = P.assemble_static(objs, aw, ah, band_h, npal)
    os.makedirs(os.path.dirname(os.path.abspath(out_glb)), exist_ok=True)
    info = P.write_glb_static(out_glb, Pp, N, UV, faces, aw, ah, atlas_rgb)
    info["ntris"] = len(tris)
    info["nverts_src"] = len(verts)
    info["tex"] = (aw, ah)
    return info


# ----------------------------------------------------------------------------
# ANIMACAO DE ABERTURA (swing rigido da folha em torno da dobradica)
#
# O bloco @[u32[5], u32[4]) e' comprovadamente a ANIMACAO de abertura (prova de
# independencia malha<->bloco: DOOR01/DOOR05 tem a MESMA malha e blocos DIFERENTES;
# DOOR04(24v)/DOOR06(42v) tem malhas DIFERENTES e o MESMO bloco). Ver
# docs/decomp/notes/doors_model.md secao "Bloco de animacao". O cabecalho do bloco
# da o Nº DE FRAMES (u16 @+2 == 6, constante em 532/532). O *payload* por-frame e'
# bit-packed (mesma familia irredutivel do stream in-RAM de inimigo) e NAO e'
# decodificado estaticamente -- o payload NAO contem vertices crus (verificado:
# nenhuma coord da malha aparece no bloco). A abertura classica do RE e' uma ROTACAO
# RIGIDA da folha em torno de uma DOBRADICA VERTICAL; reconstruimos isso a partir da
# GEOMETRIA (eixo da dobradica = aresta vertical do painel oposta ao trinco) + o Nº
# DE FRAMES do bloco. Angulo de abertura: 90 graus (quarto de volta, padrao RE).
# ----------------------------------------------------------------------------
ANIM_TAG_OFF = 0x02      # u16 @ inicio-do-bloco+2 = nframes da anim (==6)


def read_anim_tag(d):
    """Nº de frames declarado no cabecalho do bloco de animacao (u16 @ blockStart+2)."""
    partsEnd = u32(d, 0x14)      # u32[5]: inicio do bloco grande
    return struct.unpack_from("<H", d, partsEnd + ANIM_TAG_OFF)[0]


def find_hinge_x(verts):
    """Eixo (X) da dobradica: a aresta vertical do painel OPOSTA ao trinco/maçaneta.
    O trinco e' o detalhe que MAIS SALTA em Z (|z| grande); a dobradica fica no
    extremo X mais distante do centroide-X desse detalhe."""
    xs = [v[0] for v in verts]
    xmin, xmax = min(xs), max(xs)
    zabs = max(abs(v[2]) for v in verts) or 1
    knob = [v for v in verts if abs(v[2]) > 0.6 * zabs]
    kx = sum(v[0] for v in knob) / len(knob) if knob else (xmin + xmax) / 2
    return xmin if abs(kx - xmax) < abs(kx - xmin) else xmax


def _quat_y(theta):
    """quaternion glTF (x,y,z,w) p/ rotacao de theta rad em torno de +Y."""
    import math
    return (0.0, math.sin(theta / 2.0), 0.0, math.cos(theta / 2.0))


def write_glb_door_anim(path, Pp, N, UV, faces, aw, ah, atlas_rgb,
                        hinge_x_glb, nframes, angle_deg=90.0, duration=0.8):
    """Como write_glb_static, mas com no-PIVO na dobradica animado (rotacao em Y)
    -> a folha inteira gira em torno da aresta vertical (abertura da porta).
    hinge_x_glb ja' em coordenadas glTF (x*SCALE)."""
    import json, math
    S = P.SCALE

    def cvt(p):
        return (p[0] * S, -p[1] * S, -p[2] * S)
    positions = [cvt(p) for p in Pp]
    normals = []
    for (nx, ny, nz) in N:
        L = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        normals.append((nx / L, -ny / L, -nz / L))

    bin_parts = []; offset = 0; views = []; accessors = []

    def add_view(data, target=None):
        nonlocal offset
        pad = (4 - (len(data) % 4)) % 4
        bin_parts.append(data + b"\x00" * pad)
        v = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v); offset += len(data) + pad
        return len(views) - 1

    pos_data = b"".join(struct.pack("<3f", *p) for p in positions)
    mn = [min(p[i] for p in positions) for i in range(3)]
    mx = [max(p[i] for p in positions) for i in range(3)]
    a_pos = add_view(pos_data, 34962)
    accessors.append({"bufferView": a_pos, "componentType": 5126, "count": len(positions),
                      "type": "VEC3", "min": mn, "max": mx})
    nrm = add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962)
    accessors.append({"bufferView": nrm, "componentType": 5126, "count": len(normals), "type": "VEC3"})
    uvv = add_view(b"".join(struct.pack("<2f", u, v) for (u, v) in UV), 34962)
    accessors.append({"bufferView": uvv, "componentType": 5126, "count": len(UV), "type": "VEC2"})
    flat = []
    for f in faces:
        flat += list(f)
    idx = add_view(b"".join(struct.pack("<I", i) for i in flat), 34963)
    accessors.append({"bufferView": idx, "componentType": 5125, "count": len(flat), "type": "SCALAR"})

    # --- animacao: nframes keyframes, rotacao 0 -> angle_deg em torno de +Y ---
    nf = max(2, nframes)
    times = [duration * i / (nf - 1) for i in range(nf)]
    rots = [_quat_y(math.radians(angle_deg) * i / (nf - 1)) for i in range(nf)]
    t_data = b"".join(struct.pack("<f", t) for t in times)
    a_time = add_view(t_data)
    accessors.append({"bufferView": a_time, "componentType": 5126, "count": nf,
                      "type": "SCALAR", "min": [times[0]], "max": [times[-1]]})
    r_data = b"".join(struct.pack("<4f", *q) for q in rots)
    a_rot = add_view(r_data)
    accessors.append({"bufferView": a_rot, "componentType": 5126, "count": nf, "type": "VEC4"})

    png = P.png_bytes_rgb(aw, ah, atlas_rgb)
    vi_img = add_view(png)

    gltf = {
        "asset": {"version": "2.0", "generator": "do2gltf door-anim"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [
            {"name": "hinge", "translation": [hinge_x_glb, 0.0, 0.0],
             "rotation": [0.0, 0.0, 0.0, 1.0], "children": [1]},
            {"name": "door", "translation": [-hinge_x_glb, 0.0, 0.0], "mesh": 0},
        ],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                    "indices": 3, "material": 0}]}],
        "materials": [{"name": "door", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"bufferView": vi_img, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "animations": [{
            "name": "open",
            "samplers": [{"input": 4, "output": 5, "interpolation": "LINEAR"}],
            "channels": [{"sampler": 0, "target": {"node": 0, "path": "rotation"}}],
        }],
        "bufferViews": views, "accessors": accessors, "buffers": [{"byteLength": offset}],
    }
    bin_blob = b"".join(bin_parts)
    json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_blob += b" " * ((4 - len(json_blob) % 4) % 4)
    glb = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(json_blob) + 8 + len(bin_blob))
    glb += struct.pack("<I", len(json_blob)) + b"JSON" + json_blob
    glb += struct.pack("<I", len(bin_blob)) + b"BIN\x00" + bin_blob
    with open(path, "wb") as f:
        f.write(glb)
    return dict(vertices=len(Pp), faces=len(faces), nframes=nf, hinge_x_glb=hinge_x_glb)


def convert_anim(path, out_glb, angle_deg=90.0):
    """Exporta a porta COM a animacao de abertura (swing rigido em torno da
    dobradica; nframes = tag do bloco de anim; angulo = 90 graus, padrao RE)."""
    d = open(path, "rb").read()
    verts, tris, tim = parse_mesh(d)
    aw, ah, band_h, npal, atlas_rgb = P.parse_tim_atlas(d, tim)
    objs = build_objs(verts, tris, npal, band_h)
    Pp, N, UV, faces = P.assemble_static(objs, aw, ah, band_h, npal)
    nframes = read_anim_tag(d)
    hinge_x = find_hinge_x(verts)
    os.makedirs(os.path.dirname(os.path.abspath(out_glb)), exist_ok=True)
    info = write_glb_door_anim(out_glb, Pp, N, UV, faces, aw, ah, atlas_rgb,
                               hinge_x * P.SCALE, nframes, angle_deg)
    info["ntris"] = len(tris)
    info["nverts_src"] = len(verts)
    info["hinge_x_ps1"] = hinge_x
    info["tag_nframes"] = nframes
    return info


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--anim":
        # --anim <DOORxx.DOn> <saida.glb>  -> porta COM animacao de abertura
        info = convert_anim(sys.argv[2], sys.argv[3])
        print(info)
        return
    if len(sys.argv) >= 2 and sys.argv[1] == "--anim-all":
        # --anim-all [n_por_stage] -> N portas animadas de cada stage p/ DOOR/ (sufixo _ANIM)
        per = int(sys.argv[2]) if len(sys.argv) > 2 else 2
        outdir = paths.assets("DOOR")
        n_ok = 0
        for stg in range(1, 8):
            files = sorted(glob.glob(os.path.join(ROOT, "STAGE%d" % stg, "DOOR*.DO%d" % stg)))
            for fn in files[:per]:
                base = os.path.splitext(os.path.basename(fn))[0]
                out = os.path.join(outdir, "S%d_%s_ANIM.glb" % (stg, base))
                try:
                    info = convert_anim(fn, out)
                    n_ok += 1
                    print("OK  %-30s v=%-4d f=%-4d nfr=%d hinge_x=%d" % (
                        os.path.basename(out), info["vertices"], info["faces"],
                        info["tag_nframes"], info["hinge_x_ps1"]))
                except Exception as e:
                    print("ERR %s: %s" % (fn, e))
        print("animadas:", n_ok)
        return
    if len(sys.argv) >= 2 and sys.argv[1] == "--all":
        per = int(sys.argv[2]) if len(sys.argv) > 2 else 3
        outdir = paths.assets("DOOR")
        n_ok = 0
        for stg in range(1, 8):
            files = sorted(glob.glob(os.path.join(ROOT, "STAGE%d" % stg, "DOOR*.DO%d" % stg)))
            for fn in files[:per]:
                base = os.path.splitext(os.path.basename(fn))[0]
                out = os.path.join(outdir, "S%d_%s.glb" % (stg, base))
                try:
                    info = convert(fn, out)
                    n_ok += 1
                    print("OK  %-28s v=%-4d f=%-4d tris=%-4d tex=%s" % (
                        os.path.basename(out), info["vertices"], info["faces"],
                        info["ntris"], info["tex"]))
                except Exception as e:
                    print("ERR %s: %s" % (fn, e))
        print("exportados:", n_ok)
        return
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    info = convert(sys.argv[1], sys.argv[2])
    print(info)


if __name__ == "__main__":
    main()
