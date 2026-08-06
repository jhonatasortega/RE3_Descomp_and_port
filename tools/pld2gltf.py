#!/usr/bin/env python3
"""Converte modelos de personagem RE3 (.PLD / .PLW) para glTF binario (.glb).

Engenharia reversa do formato (ver docs/formatos/PLD.md):

  Conteiner PLD:
    header: u32 dirOffset ; u32 dirCount
    dirCount offsets (u32) em dirOffset (no FIM do arquivo), apontando sub-blocos:
      [EDD]  tabela de animacoes (sequencias -> frames)
      [EMR]  esqueleto (hierarquia + offsets de pose de descanso) + pool de keyframes
      [MD1]  malha (geometria dividida por osso, estilo TMD do PS1)
      [???]  bloco auxiliar pequeno
      [TIM]  textura embutida (8bpp + CLUTs)

Uso:
    python pld2gltf.py <arquivo.PLD> <saida.glb>
    python pld2gltf.py --all           (converte todos p/ godot/assets/PLD)
    python pld2gltf.py <arquivo.PLD> --preview preview.png

Python puro (stdlib + numpy opcional so p/ preview). Escreve .glb self-contained
(geometria + esqueleto/skin + textura PNG embutidos no buffer binario).
"""
import struct
import json
import os
import sys
import zlib
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

# ----------------------------------------------------------------------------
# leitores little-endian
# ----------------------------------------------------------------------------
def u8(d, o):  return d[o]
def u16(d, o): return d[o] | (d[o + 1] << 8)
def s16(d, o):
    v = u16(d, o)
    return v - 0x10000 if v & 0x8000 else v
def u32(d, o): return struct.unpack_from("<I", d, o)[0]


# ----------------------------------------------------------------------------
# 1) Conteiner
# ----------------------------------------------------------------------------
def parse_container(d):
    dir_off = u32(d, 0)
    dir_cnt = u32(d, 4)
    assert dir_off + dir_cnt * 4 == len(d), "diretorio nao termina no EOF"
    offs = [u32(d, dir_off + i * 4) for i in range(dir_cnt)]
    bounds = sorted(set(offs + [dir_off]))
    sec = []
    for o in offs:
        nxt = min([b for b in bounds if b > o], default=dir_off)
        sec.append((o, nxt))
    return offs, sec


def classify(d, offs, sec):
    """Identifica cada secao por conteudo (robusto a ordem)."""
    roles = {}
    for idx, (start, end) in enumerate(sec):
        size = end - start
        # TIM: cabecalho exato 10 00 00 00 (id=0x10, versao=0) + flag de bpp valido
        if d[start:start + 4] == b"\x10\x00\x00\x00" and (u32(d, start + 4) & 7) in (0, 1, 2, 3):
            roles.setdefault("tim", idx)
        elif u32(d, start) == size:                 # MD1: primeiro u32 = tamanho da secao
            roles.setdefault("md1", idx)
        else:
            nb = u16(d, start + 4)
            f0 = u16(d, start)
            if 1 <= nb <= 64 and 8 <= f0 < size:     # EMR: bone count plausivel + offset hierarquia
                roles.setdefault("emr", idx)
            else:
                roles.setdefault("edd", idx)         # primeiro sem papel = EDD
    return roles


# ----------------------------------------------------------------------------
# 2) MD1 (malha)
# ----------------------------------------------------------------------------
def parse_md1(d, off):
    length = u32(d, off)
    count = u32(d, off + 4)
    base = off + 8                                   # offsets dos objetos sao relativos a aqui
    objs = []
    for i in range(count):
        o = base + i * 24
        vtx = u32(d, o); nor = u32(d, o + 4); vcnt = u32(d, o + 8)
        tri = u32(d, o + 12); quad = u32(d, o + 16)
        tc = u16(d, o + 20); qc = u16(d, o + 22)
        verts = [(s16(d, base + vtx + k * 8), s16(d, base + vtx + k * 8 + 2),
                  s16(d, base + vtx + k * 8 + 4)) for k in range(vcnt)]
        norms = [(s16(d, base + nor + k * 8), s16(d, base + nor + k * 8 + 2),
                  s16(d, base + nor + k * 8 + 4)) for k in range(vcnt)]
        prims = []
        # triangulos 12B: uv0[0,1] clut[2:4] uv1[4,5] page[6] vi0[7] uv2[8,9] vi1[10] vi2[11]
        for t in range(tc):
            p = base + tri + t * 12
            clut = u16(d, p + 2)
            pal = (clut >> 6) - 480
            tx = d[p + 6] & 0x0F            # tpage X (unidade de 64 halfwords)
            vi = (d[p + 7], d[p + 10], d[p + 11])
            uv = ((d[p + 0], d[p + 1]), (d[p + 4], d[p + 5]), (d[p + 8], d[p + 9]))
            prims.append(("tri", vi, uv, pal, tx))
        # quads 16B: uv0[0,1] clut[2:4] uv1[4,5] page[6:8] uv2[8,9] vi0[10] vi1[11] uv3[12,13] vi2[14] vi3[15]
        for q in range(qc):
            p = base + quad + q * 16
            clut = u16(d, p + 2)
            pal = (clut >> 6) - 480
            tx = u16(d, p + 6) & 0x0F
            vi = (d[p + 10], d[p + 11], d[p + 14], d[p + 15])
            uv = ((d[p + 0], d[p + 1]), (d[p + 4], d[p + 5]),
                  (d[p + 8], d[p + 9]), (d[p + 12], d[p + 13]))
            prims.append(("quad", vi, uv, pal, tx))
        objs.append(dict(verts=verts, norms=norms, prims=prims))
    return objs


# ----------------------------------------------------------------------------
# 3) EMR (esqueleto)
# ----------------------------------------------------------------------------
def parse_emr(d, off, end):
    hier_off = u16(d, off)          # campo0 = offset da hierarquia (rel. ao inicio da secao)
    nb = u16(d, off + 4)            # campo2 = numero de ossos
    frame_size = u16(d, off + 6)    # campo3 = bytes por frame de animacao (EDD)
    # posicoes relativas: logo apos header de 8 bytes, nb x (s16 x,y,z)
    relpos = [(s16(d, off + 8 + i * 6), s16(d, off + 8 + i * 6 + 2),
               s16(d, off + 8 + i * 6 + 4)) for i in range(nb)]
    # hierarquia: nb pares (u16 nChildren, u16 childListOffset) ; filhos = u8
    hb = off + hier_off
    parent = [-1] * nb
    children = [[] for _ in range(nb)]
    for i in range(nb):
        cnt = u16(d, hb + i * 4)
        coff = u16(d, hb + i * 4 + 2)
        for k in range(cnt):
            c = d[hb + coff + k]
            if 0 <= c < nb:
                parent[c] = i
                children[i].append(c)
    # A malha e' autorada em ESPACO-MODELO absoluto (pose neutra) com a raiz na
    # ORIGEM. O relpos[raiz] (ex.: (0,-1839,0)) e' um deslocamento global de
    # posicionamento no mundo -> descartado no bind para alinhar ossos <-> malha.
    root_offset = None
    node_translation = [list(relpos[i]) for i in range(nb)]
    for i in range(nb):
        if parent[i] < 0:
            root_offset = relpos[i]
            node_translation[i] = [0, 0, 0]
    # posicoes de mundo (pose de descanso) = soma acumulada (raiz = origem)
    world = [None] * nb
    def calc(i):
        if world[i] is not None:
            return world[i]
        p = parent[i]
        x, y, z = node_translation[i]
        if p < 0:
            world[i] = (x, y, z)
        else:
            px, py, pz = calc(p)
            world[i] = (px + x, py + y, pz + z)
        return world[i]
    for i in range(nb):
        calc(i)
    return dict(nb=nb, frame_size=frame_size, relpos=relpos,
                node_translation=node_translation, root_offset=root_offset,
                parent=parent, children=children, world=world)


# ----------------------------------------------------------------------------
# 3b) Animacao: pool de poses (keyframes) + EDD (sequencias)
# ----------------------------------------------------------------------------
import math

def _get12(d, base, i):
    """Le o i-esimo valor de 12 bits empacotado (little-endian) a partir de base."""
    bit = i * 12
    byte = base + bit // 8
    sh = bit % 8
    v = (d[byte] | (d[byte + 1] << 8) | (d[byte + 2] << 16)) >> sh
    return v & 0xFFF


def _euler_to_quat_gltf(ax, ay, az):
    """Angulos 12-bit (0..4095 = 0..2pi) -> quaternion no espaco glTF (x,-y,-z).

    Rotacao local do osso = Rx*Ry*Rz (ordem XYZ, validada visualmente). Converte
    para o espaco glTF conjugando por F=diag(1,-1,-1) (equivalente a negar as
    componentes y,z do quaternion)."""
    a = ax / 4096.0 * 2 * math.pi
    b = ay / 4096.0 * 2 * math.pi
    c = az / 4096.0 * 2 * math.pi
    # quaternions dos eixos
    def qaxis(angle, ux, uy, uz):
        s = math.sin(angle / 2); return (ux * s, uy * s, uz * s, math.cos(angle / 2))
    def qmul(p, q):
        px, py, pz, pw = p; qx, qy, qz, qw = q
        return (pw*qx + px*qw + py*qz - pz*qy,
                pw*qy - px*qz + py*qw + pz*qx,
                pw*qz + px*qy - py*qx + pz*qw,
                pw*qw - px*qx - py*qy - pz*qz)
    q = qmul(qmul(qaxis(a, 1, 0, 0), qaxis(b, 0, 1, 0)), qaxis(c, 0, 0, 1))
    qx, qy, qz, qw = q
    # F=diag(1,-1,-1): conjugacao -> nega y,z do vetor do quaternion
    return (qx, -qy, -qz, qw)


def parse_poses(d, emr_off, nb):
    """Pool de keyframes logo apos o EMR (176 bytes). Cada pose = 76 bytes:
       s16 root x,y,z ; s16 flag ; 45 angulos de 12 bits (15 ossos x XYZ)."""
    POOL = emr_off + 176
    FS = 76
    # numero de poses = (tamanho_da_secao - 176) / 76  (mas nao sabemos o fim aqui;
    # o chamador passa; usamos ate o proximo bloco). Descoberto empiricamente = exato.
    poses = []
    # o chamador limita; aqui devolvemos um leitor
    def read_pose(k):
        o = POOL + k * FS
        root = (s16(d, o), s16(d, o + 2), s16(d, o + 4))
        quats = [_euler_to_quat_gltf(_get12(d, o + 8, b * 3),
                                     _get12(d, o + 8, b * 3 + 1),
                                     _get12(d, o + 8, b * 3 + 2)) for b in range(nb)]
        return root, quats
    return read_pose, POOL, FS


def parse_edd(d, edd_off, edd_end, npose):
    """Sequencias de animacao (RE COMPLETA do EDD — ver docs/formatos/PLD.md sec.6).

    A secao EDD e' composta de DOIS pedacos contiguos:
      1) TABELA DE SEQUENCIAS: N registros de 8 bytes
         { u16 nframes, u16 frameOff, u32 poseStart }
         - nframes  = numero de frames de JOGO (30 fps) da sequencia.
         - frameOff = offset EM BYTES (a partir do inicio do EDD) para dentro da
                      frame-list onde comeca a lista de frames desta sequencia.
         - poseStart= indice absoluto (no pool de 76B) da 1a pose da sequencia.
      2) FRAME-LIST: comeca em EDD+min(frameOff). 2 bytes por frame:
         byte BAIXO = indice de pose RELATIVO a poseStart ; byte ALTO = flags de evento
         (som de passo etc). Da o mapeamento frame->pose com HOLDS/REUSO.

    A quantidade de sequencias N NAO e' um campo do arquivo: a tabela termina exatamente
    onde a frame-list comeca. Como toda frameOff aponta PARA a frame-list, o menor frameOff
    visto e' o inicio da frame-list => N = min(frameOff)//8. (No PL00: min=176 => N=22.)

    Isto substitui a heuristica antiga (pstart monotonico), que (a) DERRUBAVA a ultima
    sequencia por falta de um 'proximo registro' p/ o pend, e (b) marcava como
    'tamanho zero' sequencias cujo poseStart coincide com o da seguinte (06/08), mas que
    na verdade REUSAM poses da regiao seguinte via frame-list. Recupera as 22 sequencias.

    Retorna (seqs, recs, flstart, N):
      seqs = lista de dicts {index, nframes, foff, pstart} p/ i em [0,N)."""
    ntot = (edd_end - edd_off) // 8
    # localiza o inicio da frame-list = menor frameOff dos registros lideres
    flstart = 10 ** 9
    i = 0
    while i * 8 < flstart and i < ntot:
        foff = u16(d, edd_off + i * 8 + 2)
        if 8 <= foff < flstart:
            flstart = foff
        i += 1
    N = flstart // 8
    recs = [(u16(d, edd_off + i * 8), u16(d, edd_off + i * 8 + 2),
             u32(d, edd_off + i * 8 + 4)) for i in range(N)]
    seqs = [dict(index=i, nframes=recs[i][0], foff=recs[i][1], pstart=recs[i][2])
            for i in range(N)]
    return seqs, recs, flstart, N


# ----------------------------------------------------------------------------
# 4) TIM -> atlas RGB (uma copia por paleta, empilhadas verticalmente)
# ----------------------------------------------------------------------------
def bgr555(v):
    r = (v & 0x1F) << 3
    g = ((v >> 5) & 0x1F) << 3
    b = ((v >> 10) & 0x1F) << 3
    return (r | r >> 5, g | g >> 5, b | b >> 5)


def parse_tim_atlas(d, off):
    assert d[off] == 0x10
    flag = u32(d, off + 4)
    bpp = flag & 3
    has_clut = (flag >> 3) & 1
    pos = off + 8
    palettes = []
    if has_clut:
        blen = u32(d, pos)
        ncol = u16(d, pos + 8)
        npal = u16(d, pos + 10)
        pbase = pos + 12
        for pi in range(npal):
            pal = [bgr555(u16(d, pbase + pi * ncol * 2 + c * 2)) for c in range(ncol)]
            palettes.append(pal)
        pos += blen
    blen = u32(d, pos)
    iw = u16(d, pos + 8)
    ih = u16(d, pos + 10)
    pix = d[pos + 12: pos + blen]
    if bpp == 1:      # 8bpp
        w = iw * 2
    elif bpp == 0:    # 4bpp
        w = iw * 4
    else:
        w = iw
    h = ih
    npal = max(1, len(palettes))
    # atlas w x (h*npal): banda pi = imagem inteira decodificada com a paleta pi
    atlas = bytearray(w * h * npal * 3)
    for pi in range(npal):
        pal = palettes[pi] if palettes else None
        for y in range(h):
            for x in range(w):
                if bpp == 1:
                    idx = pix[y * w + x]
                    r, g, b = pal[idx] if idx < len(pal) else (0, 0, 0)
                elif bpp == 0:
                    byte = pix[(y * w + x) >> 1]
                    idx = (byte & 0x0F) if (x & 1) == 0 else (byte >> 4)
                    r, g, b = pal[idx] if idx < len(pal) else (0, 0, 0)
                else:
                    r, g, b = bgr555(u16(pix, (y * w + x) * 2))
                o = ((pi * h + y) * w + x) * 3
                atlas[o] = r; atlas[o + 1] = g; atlas[o + 2] = b
    return w, h * npal, h, npal, bytes(atlas)


def tim_alpha_atlas(d, off):
    """Plano de ALFA do atlas do TIM, no mesmo layout de parse_tim_atlas (w x h*npal).

    REGRA DO GPU DO PS1 (exata, nao heuristica): um texel cujo valor 15-bit resultante e'
    `0x0000` (RGB=0 E o bit STP=0) NAO e' desenhado — e' transparente. `0x8000` e' "preto
    semi-transparente" e E' desenhado. Em textura paletizada a regra vale sobre a COR que
    sai da CLUT, nao sobre o indice.
    Ex.: `EM23.TIM` tem 3 paletas com entrada 0 = 0x0000 / 0x8000 / 0x0000 e 10,1% dos
    pixels usando o indice 0 -> era a mancha PRETA opaca no lugar do vazado.
    Devolve bytes (1 por pixel: 0 = transparente, 255 = opaco)."""
    assert d[off] == 0x10
    flag = u32(d, off + 4)
    bpp = flag & 3
    has_clut = (flag >> 3) & 1
    pos = off + 8
    raw_pals = []
    if has_clut:
        blen = u32(d, pos)
        ncol = u16(d, pos + 8)
        npal = u16(d, pos + 10)
        pbase = pos + 12
        for pi in range(npal):
            raw_pals.append([u16(d, pbase + pi * ncol * 2 + c * 2) for c in range(ncol)])
        pos += blen
    blen = u32(d, pos)
    iw = u16(d, pos + 8)
    ih = u16(d, pos + 10)
    pix = d[pos + 12: pos + blen]
    w = iw * 2 if bpp == 1 else (iw * 4 if bpp == 0 else iw)
    h = ih
    npal = max(1, len(raw_pals))
    out = bytearray()
    plane = w * h
    for pi in range(npal):
        pal = raw_pals[pi] if raw_pals else None
        if bpp == 1:                                   # 8bpp: LUT de 256 + translate (rapido)
            lut = bytes(0 if (pal and i < len(pal) and pal[i] == 0) else 255 for i in range(256))
            out += bytes(pix[:plane]).translate(lut)
        elif bpp == 0:                                 # 4bpp
            a = bytearray([255]) * plane
            for k in range(plane):
                byte = pix[k >> 1]
                idx = (byte & 0x0F) if (k & 1) == 0 else (byte >> 4)
                if pal and idx < len(pal) and pal[idx] == 0:
                    a[k] = 0
            out += bytes(a)
        else:                                          # 16bpp direto
            a = bytearray([255]) * plane
            for k in range(plane):
                if u16(pix, k * 2) == 0:
                    a[k] = 0
            out += bytes(a)
    if len(out) < plane * npal:
        out += bytes([255]) * (plane * npal - len(out))
    return bytes(out[:plane * npal])


def png_bytes_rgba(w, h, rgb, alpha):
    """PNG RGBA a partir do atlas RGB + plano de alfa de tim_alpha_atlas."""
    import io
    buf = io.BytesIO()

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)   # color type 6 = RGBA
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        o3 = y * w * 3; oa = y * w
        for x in range(w):
            raw += rgb[o3 + x * 3:o3 + x * 3 + 3]
            raw.append(alpha[oa + x])
    idat = zlib.compress(bytes(raw), 9)
    buf.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
              chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    return buf.getvalue()


def write_png_rgb(path, w, h, rgb):
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    raw = bytearray()
    row = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * row:(y + 1) * row]
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
                chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def png_bytes_rgb(w, h, rgb):
    import io
    buf = io.BytesIO()
    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    raw = bytearray()
    row = w * 3
    for y in range(h):
        raw.append(0)
        raw += rgb[y * row:(y + 1) * row]
    idat = zlib.compress(bytes(raw), 9)
    buf.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
              chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    return buf.getvalue()


# ----------------------------------------------------------------------------
# Montagem: gera listas de vertices/faces em espaco-modelo (pose de descanso)
# ----------------------------------------------------------------------------
SCALE = 0.001   # 1 unidade PS1 -> 1 mm ; personagem ~2.4m

def _extra_bone_map(objs, emr):
    """Determina o osso correto de cada objeto EXTRA (indice >= nBones).

    Muitos PLD tem MAIS objetos de malha que ossos: os extras sao pecas pequenas
    (tampas/pinos de junta, dedos) autoradas em ESPACO-DE-OSSO (centradas na
    origem). O codigo antigo jogava TODOS no ultimo osso (nb-1) -> ficavam grudados
    e "voando" num pe so (detachment). Aqui os distribuimos.

    Override p/ testes: env PLD_EXTRA_BONES='b0,b1,...' (um osso por objeto extra)."""
    import os as _os
    nb = emr["nb"]
    extras = [i for i in range(len(objs)) if i >= nb]
    if not extras:
        return {}
    env = _os.environ.get("PLD_EXTRA_BONES")
    if env:
        vals = [int(x) for x in env.split(",") if x.strip() != ""]
        return {extras[k]: vals[k] for k in range(min(len(extras), len(vals)))}
    # Objetos EXTRA (pecas pequenas em espaco-de-osso, centroide ~0, sem osso proprio):
    # o codigo antigo empilhava TODOS no ultimo osso (o pe) -> num tombo/queda eles
    # "voavam" longe do corpo. Ancoramos na RAIZ (quadril): ficam escondidos dentro do
    # tronco e acompanham o corpo, sem nunca se soltar. Geral p/ qualquer PLD.
    return {i: 0 for i in extras}


def _bone_depth(parent):
    """Profundidade de cada osso na cadeia FK (raiz = 0)."""
    nb = len(parent)
    depth = [None] * nb
    def d(i):
        if depth[i] is not None:
            return depth[i]
        p = parent[i]
        depth[i] = 0 if p < 0 else d(p) + 1
        return depth[i]
    for i in range(nb):
        d(i)
    return depth


def _seg_dist(p, a, b):
    """Distancia do ponto p ao SEGMENTO de reta [a,b] (espaco-modelo)."""
    ax, ay, az = a; bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    l2 = dx * dx + dy * dy + dz * dz
    if l2 < 1e-9:
        t = 0.0
    else:
        t = ((p[0] - ax) * dx + (p[1] - ay) * dy + (p[2] - az) * dz) / l2
        t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    cx, cy, cz = ax + dx * t, ay + dy * t, az + dz * t
    return ((p[0] - cx) ** 2 + (p[1] - cy) ** 2 + (p[2] - cz) ** 2) ** 0.5


def assemble(objs, emr, atlas_w, atlas_h, band_h, npal):
    """Retorna arrays para exportacao.

    SKINNING POR ENVELOPE LOCAL DE MEMBRO (rigido por regiao + blend fino em TODAS as
    juntas que dobram). Base: cada OBJETO e' um pedaco de malha autorado em espaco-modelo
    e preso a um osso-raiz (o seu own_bone). POReM varios objetos abrangem MAIS DE UM
    osso da cadeia FK — a geometria do proximo elo esta "assada" dentro do mesmo objeto
    porque o osso desse elo e' so um CONECTOR vazio (3 verts, sem objeto proprio):

      * obj8 (pelve) = pelve + as DUAS COXAS -> as coxas devem seguir bone9/bone12.
      * obj10/obj13 (canela) = canela + BOTA/pe -> a bota deve seguir bone11/bone14
        (o TORNOZELO), senao "flutua" abaixo da canela quando a perna dobra.
      * obj2/obj5 (braco inteiro) = braco + antebraco -> antebraco segue bone3/bone6
        (cotovelo) e a ponta segue bone4/bone7 (punho).

    Para cada objeto montamos a lista de ossos CANDIDATOS = o osso-raiz + os
    DESCENDENTES na cadeia FK cuja geometria esta assada aqui (descem enquanto o osso
    for NAO-substancial; param ao topar um osso que tem objeto proprio) + o PAI FK (p/
    selar a junta do topo contra o segmento vizinho). Cada osso vira um SEGMENTO de reta
    (do seu world ao world do 1o filho, ou extrapolado se for ponta). Cada vertice pesa
    nos 2 ossos cujos segmentos estao MAIS PERTO, por 1/dist^POWER. Como os segmentos de
    um membro so ficam equidistantes PERTO da junta, o blend e' automaticamente uma
    FAIXA FINA na dobra e RiGIDO fora dela — sem o amassamento "papel" do blend global
    (poucos candidatos, todos do mesmo membro). Generico p/ qualquer PLD humano.

    Reutiliza a nocao de "osso substancial" (o que realmente carrega geometria) p/ saber
    onde a cadeia de um objeto termina. Posicionamento na pose de descanso identico ao
    anterior: objetos model-space ficam como estao; MAOS/conectores bone-local (centroide
    ~0) sao trazidos somando world[osso]. inverseBindMatrices (write_glb) = translate(-world)."""
    nb = emr["nb"]
    world = emr["world"]
    parent = emr["parent"]; children = emr["children"]
    depth = _bone_depth(parent)

    # Envelope: expoente do peso 1/dist^POWER (maior = faixa de blend mais estreita),
    # e peso minimo p/ manter o 2o osso (abaixo disso -> rigido puro). Ajustaveis p/ calibrar.
    ENV_POWER = float(os.environ.get("PLD_ENV_POWER", "5.0"))
    ENV_EPS = float(os.environ.get("PLD_ENV_EPS", "1.0"))
    ENV_MINW = float(os.environ.get("PLD_ENV_MINW", "0.03"))
    ENV_JOINT_MIN = float(os.environ.get("PLD_ENV_JOINT_MIN", "50.0"))  # junta minima p/ selar o topo
    NO_BLEND = bool(os.environ.get("PLD_NO_JOINT_BLEND"))

    extra_map = _extra_bone_map(objs, emr)   # obj extra (i>=nb) -> osso correto
    drop_extras = bool(os.environ.get("PLD_DROP_EXTRAS"))

    # --- Classificacao objeto->osso (chave p/ as maos nao se soltarem) -----------
    # Cada objeto tem um "osso de origem" (own_bone): oi p/ objetos do corpo, ou o
    # osso do extra_map. Alem disso, decidimos o "osso de VINCULO" (skin):
    #   * SUBSTANCIAL (segmento proprio: torso, cabeca, BRACO-inteiro, coxa, canela)
    #     = objeto model-space (nao bone-local) e com varios vertices -> vincula ao
    #       proprio osso.
    #   * CAP/PONTA (mao, conector, pe, pino de junta) = objeto bone-local (autorado
    #     centrado na origem) ou degenerado -> vincula ao osso do ANCESTRAL
    #     SUBSTANCIAL mais proximo. Assim a MAO (obj bone-local no punho) anda junto
    #     do BRACO (obj2, que e' o membro inteiro no ombro) em vez de seguir sozinha
    #     a cadeia FK punho e se DESCONECTAR. Correcao do bug "maos dentro/soltas".
    def _own_bone(oi):
        return oi if oi < nb else extra_map.get(oi, nb - 1)

    def _is_bone_local(oi):
        ob = objs[oi]; vs = ob["verts"]; n = max(1, len(vs))
        cx = sum(v[0] for v in vs) / n; cy = sum(v[1] for v in vs) / n; cz = sum(v[2] for v in vs) / n
        cmag = (cx * cx + cy * cy + cz * cz) ** 0.5
        wx, wy, wz = world[_own_bone(oi)]
        wmag = (wx * wx + wy * wy + wz * wz) ** 0.5
        return wmag > 200 and cmag < 0.5 * wmag

    def _is_substantial(oi):
        # segmento proprio: geometria model-space com corpo (>=8 verts)
        return (oi < nb) and (not _is_bone_local(oi)) and (len(objs[oi]["verts"]) >= 8)

    # osso substancial por osso (se o objeto daquele osso e' substancial)
    subst_bone = set(b for b in range(min(len(objs), nb)) if _is_substantial(b))

    def _bind_bone(oi):
        own = _own_bone(oi)
        if _is_substantial(oi):
            return own                                # segmento proprio
        a = own                                       # sobe a cadeia ate um osso substancial
        for _ in range(nb + 1):
            if a in subst_bone:
                return a
            p = parent[a] if 0 <= a < nb else -1
            if p < 0:
                break
            a = p
        return own

    # --- Envelope por membro: segmento de reta de cada osso + candidatos por objeto ---
    def _bone_seg(b):
        """Segmento (start,end) do osso b em espaco-modelo: do seu world ao world do
        1o filho na cadeia; se for PONTA (sem filho), extrapola a direcao do pai (assim
        a bota/mao tem um eixo p/ frente e os verts distais caem no osso da ponta)."""
        start = world[b]
        kids = [c for c in children[b] if 0 <= c < nb]
        if kids:
            end = world[kids[0]]
        else:
            p = parent[b]
            if 0 <= p < nb:
                end = (2 * start[0] - world[p][0], 2 * start[1] - world[p][1],
                       2 * start[2] - world[p][2])
            else:
                end = (start[0], start[1] + 1.0, start[2])
        return start, end

    def _chain_cands(root):
        """Ossos candidatos p/ o envelope de um objeto de raiz `root`:
        root + DESCENDENTES cuja geometria esta assada aqui (desce enquanto o osso for
        NAO-substancial; para ao topar um osso com objeto proprio) + o PAI FK (p/ selar
        a junta do topo, se a junta for real)."""
        cands = [root]
        stack = [c for c in children[root] if 0 <= c < nb]
        while stack:
            c = stack.pop()
            if c in subst_bone:            # tem objeto proprio -> outra regiao, para
                continue
            cands.append(c)
            stack += [k for k in children[c] if 0 <= k < nb]
        p = parent[root]
        if 0 <= p < nb:
            wr = world[root]; wp = world[p]
            d = ((wr[0] - wp[0]) ** 2 + (wr[1] - wp[1]) ** 2 + (wr[2] - wp[2]) ** 2) ** 0.5
            if d > ENV_JOINT_MIN:
                cands.append(p)
        return cands

    P, N, UV, J, W, faces = [], [], [], [], [], []
    for oi, ob in enumerate(objs):
        if oi >= nb and (drop_extras or oi not in extra_map):
            continue                                 # pino de junta extra descartado
        own_bone = _own_bone(oi)                      # p/ POSICIONAR na pose de descanso
        bind_bone = _bind_bone(oi)                    # osso-raiz do envelope
        vs = ob["verts"]
        bone_local = _is_bone_local(oi)
        wx, wy, wz = world[own_bone]
        off = (wx, wy, wz) if bone_local else (0.0, 0.0, 0.0)

        # --- ENVELOPE LOCAL DO MEMBRO: candidatos = raiz + descendentes assados + pai FK.
        # Cada vertice pesa nos 2 ossos com SEGMENTO mais proximo (1/dist^POWER). Como os
        # segmentos de um membro so ficam equidistantes PERTO da junta, o blend e' uma
        # faixa fina na dobra e rigido fora dela. Selar TODAS as juntas: joelho, TORNOZELO,
        # cotovelo, punho, quadril, pescoco. Sem blend global (poucos candidatos do membro).
        env_root = bind_bone
        cands = [env_root] if NO_BLEND else _chain_cands(env_root)
        segs = {b: _bone_seg(b) for b in cands}
        single = len(cands) < 2

        cache = {}
        def corner(vl, uv, pal, tx):
            key = (vl, uv[0], uv[1], pal, tx)
            gi = cache.get(key)
            if gi is None:
                gi = len(P)
                v = ob["verts"][vl]
                pos = (v[0] + off[0], v[1] + off[1], v[2] + off[2])
                P.append(pos)
                N.append(ob["norms"][vl])
                ax = tx * 128 + uv[0]                # 8bpp: 1 unidade de tpage = 128 texels
                ay = pal * band_h + uv[1]            # paleta seleciona a banda vertical
                UV.append((ax / atlas_w, ay / atlas_h))
                if single:
                    J.append([env_root, 0, 0, 0]); W.append([1.0, 0.0, 0.0, 0.0])
                else:
                    ds = sorted((_seg_dist(pos, segs[b][0], segs[b][1]), b) for b in cands)
                    (d0, b0), (d1, b1) = ds[0], ds[1]
                    w0 = 1.0 / ((d0 + ENV_EPS) ** ENV_POWER)
                    w1 = 1.0 / ((d1 + ENV_EPS) ** ENV_POWER)
                    s = w0 + w1
                    w0 /= s; w1 /= s
                    if w1 < ENV_MINW:               # 2o osso irrelevante -> rigido puro
                        J.append([b0, 0, 0, 0]); W.append([1.0, 0.0, 0.0, 0.0])
                    else:
                        J.append([b0, b1, 0, 0]); W.append([w0, w1, 0.0, 0.0])
                cache[key] = gi
            return gi
        for prim in ob["prims"]:
            ptype, vi, uv, pal, tx = prim
            if pal < 0 or pal >= npal:
                pal = 0
            if ptype == "tri":
                a = corner(vi[0], uv[0], pal, tx)
                b = corner(vi[1], uv[1], pal, tx)
                c = corner(vi[2], uv[2], pal, tx)
                faces.append((a, b, c))
            else:                                    # quad (0,1,2,3) -> (0,1,2)+(1,3,2)
                a = corner(vi[0], uv[0], pal, tx)
                b = corner(vi[1], uv[1], pal, tx)
                c = corner(vi[2], uv[2], pal, tx)
                e = corner(vi[3], uv[3], pal, tx)
                faces.append((a, b, c))
                faces.append((b, e, c))
    return P, N, UV, J, W, faces


def assemble_static(objs, atlas_w, atlas_h, band_h, npal):
    """Montagem sem esqueleto (armas .PLW): so malha + UV/textura."""
    P, N, UV, faces = [], [], [], []
    for ob in objs:
        cache = {}
        def corner(vl, uv, pal, tx):
            key = (vl, uv[0], uv[1], pal, tx)
            gi = cache.get(key)
            if gi is None:
                gi = len(P)
                P.append(ob["verts"][vl]); N.append(ob["norms"][vl])
                UV.append(((tx * 128 + uv[0]) / atlas_w, (pal * band_h + uv[1]) / atlas_h))
                cache[key] = gi
            return gi
        for prim in ob["prims"]:
            ptype, vi, uv, pal, tx = prim
            if not (0 <= pal < npal):
                pal = 0
            if ptype == "tri":
                faces.append((corner(vi[0], uv[0], pal, tx), corner(vi[1], uv[1], pal, tx),
                              corner(vi[2], uv[2], pal, tx)))
            else:
                a = corner(vi[0], uv[0], pal, tx); b = corner(vi[1], uv[1], pal, tx)
                c = corner(vi[2], uv[2], pal, tx); e = corner(vi[3], uv[3], pal, tx)
                faces.append((a, b, c)); faces.append((b, e, c))
    return P, N, UV, faces


def write_glb_static(path, P, N, UV, faces, atlas_w, atlas_h, atlas_rgb):
    """GLB minimo: POSITION/NORMAL/TEXCOORD_0 + material texturizado, sem skin."""
    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)
    positions = [cvt(p) for p in P]
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
    png = png_bytes_rgb(atlas_w, atlas_h, atlas_rgb)
    vi_img = add_view(png)
    gltf = {
        "asset": {"version": "2.0", "generator": "pld2gltf static"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "weapon", "mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                    "indices": 3, "material": 0}]}],
        "materials": [{"name": "plw", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"bufferView": vi_img, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
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
    return dict(vertices=len(P), faces=len(faces), bones=0, tex=(atlas_w, atlas_h))


# ----------------------------------------------------------------------------
# Preview: rasterizador ortografico simples (numpy) -> PNG
# ----------------------------------------------------------------------------
def render_preview(P, UV, faces, atlas_w, atlas_h, atlas_rgb, path, size=512):
    import numpy as np
    pos = np.array(P, dtype=np.float64)
    uv = np.array(UV, dtype=np.float64)
    tex = np.frombuffer(atlas_rgb, dtype=np.uint8).reshape(atlas_h, atlas_w, 3)
    mn = pos.min(0); mx = pos.max(0)
    ctr = (mn + mx) / 2
    span = (mx - mn).max() * 1.1
    def project(view):
        if view == "front":  # olha -Z : col=x, row=y (y p/ baixo)
            u = pos[:, 0]; v = pos[:, 1]; depth = pos[:, 2]
        else:                # side : col=z, row=y
            u = pos[:, 2]; v = pos[:, 1]; depth = pos[:, 0]
        sx = (u - ctr[0 if view == "front" else 2]) / span * size + size / 2
        sy = (v - ctr[1]) / span * size + size / 2
        return sx, sy, depth
    img = np.zeros((size, size * 2, 3), dtype=np.uint8)
    for vi, view in enumerate(("front", "side")):
        sx, sy, depth = project(view)
        zbuf = np.full((size, size), -1e9)
        xoff = vi * size
        for (a, b, c) in faces:
            xs = [sx[a], sx[b], sx[c]]; ys = [sy[a], sy[b], sy[c]]
            x0 = int(max(0, min(xs))); x1 = int(min(size - 1, max(xs)))
            y0 = int(max(0, min(ys))); y1 = int(min(size - 1, max(ys)))
            if x1 < x0 or y1 < y0:
                continue
            ax, ay = xs[0], ys[0]; bx, by = xs[1], ys[1]; cx, cy = xs[2], ys[2]
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-6:
                continue
            for py in range(y0, y1 + 1):
                for px in range(x0, x1 + 1):
                    l0 = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / det
                    l1 = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / det
                    l2 = 1 - l0 - l1
                    if l0 < -0.001 or l1 < -0.001 or l2 < -0.001:
                        continue
                    dep = l0 * depth[a] + l1 * depth[b] + l2 * depth[c]
                    if view == "front":
                        dep = -dep
                    if dep <= zbuf[py, px]:
                        continue
                    zbuf[py, px] = dep
                    tu = l0 * uv[a, 0] + l1 * uv[b, 0] + l2 * uv[c, 0]
                    tv = l0 * uv[a, 1] + l1 * uv[b, 1] + l2 * uv[c, 1]
                    txx = min(atlas_w - 1, max(0, int(tu * atlas_w)))
                    tyy = min(atlas_h - 1, max(0, int(tv * atlas_h)))
                    img[py, xoff + px] = tex[tyy, txx]
    write_png_rgb(path, size * 2, size, img.tobytes())


# ----------------------------------------------------------------------------
# GLB writer (self-contained, com skin)
# ----------------------------------------------------------------------------
def mat_translate(x, y, z):
    # coluna-maior (glTF)
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]


def write_glb(path, P, N, UV, J, W, faces, emr, atlas_w, atlas_h, atlas_rgb, anim_clips=None):
    nb = emr["nb"]
    parent = emr["parent"]; world = emr["world"]
    node_translation = emr["node_translation"]

    # transforma p/ eixo-Y-para-cima, destro: (x,-y,-z)*SCALE
    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)

    positions = [cvt(p) for p in P]
    normals = []
    for (nx, ny, nz) in N:
        L = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        normals.append((nx / L, -ny / L, -nz / L))

    bin_parts = []
    offset = 0
    views = []
    accessors = []

    def add_view(data, target=None):
        nonlocal offset
        pad = (4 - (len(data) % 4)) % 4
        bin_parts.append(data + b"\x00" * pad)
        v = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        offset += len(data) + pad
        return len(views) - 1

    # POSITION
    pos_data = b"".join(struct.pack("<3f", *p) for p in positions)
    mn = [min(p[i] for p in positions) for i in range(3)]
    mx = [max(p[i] for p in positions) for i in range(3)]
    vi_pos = add_view(pos_data, 34962)
    accessors.append({"bufferView": vi_pos, "componentType": 5126, "count": len(positions),
                      "type": "VEC3", "min": mn, "max": mx})
    A_POS = len(accessors) - 1
    # NORMAL
    nrm_data = b"".join(struct.pack("<3f", *n) for n in normals)
    vi_nrm = add_view(nrm_data, 34962)
    accessors.append({"bufferView": vi_nrm, "componentType": 5126, "count": len(normals), "type": "VEC3"})
    A_NRM = len(accessors) - 1
    # TEXCOORD_0
    uv_data = b"".join(struct.pack("<2f", u, v) for (u, v) in UV)
    vi_uv = add_view(uv_data, 34962)
    accessors.append({"bufferView": vi_uv, "componentType": 5126, "count": len(UV), "type": "VEC2"})
    A_UV = len(accessors) - 1
    # JOINTS_0 (ubyte x4) + WEIGHTS_0 (float x4) — skinning suave por vértice
    j_data = b"".join(struct.pack("<4B", *js) for js in J)
    vi_j = add_view(j_data, 34962)
    accessors.append({"bufferView": vi_j, "componentType": 5121, "count": len(J), "type": "VEC4"})
    A_J = len(accessors) - 1
    w_data = b"".join(struct.pack("<4f", *ws) for ws in W)
    vi_w = add_view(w_data, 34962)
    accessors.append({"bufferView": vi_w, "componentType": 5126, "count": len(J), "type": "VEC4"})
    A_W = len(accessors) - 1
    # indices
    flat = []
    for f in faces:
        flat += list(f)
    idx_data = b"".join(struct.pack("<I", i) for i in flat)
    vi_idx = add_view(idx_data, 34963)
    accessors.append({"bufferView": vi_idx, "componentType": 5125, "count": len(flat), "type": "SCALAR"})
    A_IDX = len(accessors) - 1
    # inverseBindMatrices
    ibm = b""
    for j in range(nb):
        wx, wy, wz = cvt(world[j])
        ibm += struct.pack("<16f", *mat_translate(-wx, -wy, -wz))
    vi_ibm = add_view(ibm)
    accessors.append({"bufferView": vi_ibm, "componentType": 5126, "count": nb, "type": "MAT4"})
    A_IBM = len(accessors) - 1
    # textura PNG
    png = png_bytes_rgb(atlas_w, atlas_h, atlas_rgb)
    vi_img = add_view(png)

    # ---- animacoes ----
    animations = []
    if anim_clips:
        FPS = 30.0
        for clip in anim_clips:
            npose = len(clip["times"])
            times = struct.pack("<%df" % npose, *clip["times"])
            vt = add_view(times)
            accessors.append({"bufferView": vt, "componentType": 5126, "count": npose,
                              "type": "SCALAR", "min": [clip["times"][0]], "max": [clip["times"][-1]]})
            a_time = len(accessors) - 1
            samplers = []; channels = []
            for b in range(nb):
                quats = b"".join(struct.pack("<4f", *q) for q in clip["rot"][b])
                vq = add_view(quats)
                accessors.append({"bufferView": vq, "componentType": 5126,
                                  "count": npose, "type": "VEC4"})
                samplers.append({"input": a_time, "output": len(accessors) - 1,
                                 "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1,
                                 "target": {"node": b, "path": "rotation"}})
            # translacao da raiz (root motion)
            root_b = [j for j in range(nb) if parent[j] < 0][0]
            tr = b"".join(struct.pack("<3f", *t) for t in clip["roottr"])
            vtr = add_view(tr)
            accessors.append({"bufferView": vtr, "componentType": 5126,
                              "count": npose, "type": "VEC3"})
            samplers.append({"input": a_time, "output": len(accessors) - 1,
                             "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1,
                             "target": {"node": root_b, "path": "translation"}})
            animations.append({"name": clip["name"], "samplers": samplers, "channels": channels})

    # nodes: 0..nb-1 = ossos ; nb = malha
    nodes = []
    for j in range(nb):
        rx, ry, rz = cvt(node_translation[j])
        node = {"name": f"bone{j:02d}", "translation": [rx, ry, rz]}
        kids = emr["children"][j]
        if kids:
            node["children"] = list(kids)
        nodes.append(node)
    mesh_node = {"name": "mesh", "mesh": 0, "skin": 0}
    nodes.append(mesh_node)
    mesh_node_idx = nb
    roots = [j for j in range(nb) if parent[j] < 0]
    scene_nodes = roots + [mesh_node_idx]

    gltf = {
        "asset": {"version": "2.0", "generator": "pld2gltf (RE3 reverse-engineering)"},
        "scene": 0,
        "scenes": [{"nodes": scene_nodes}],
        "nodes": nodes,
        "meshes": [{"primitives": [{
            "attributes": {"POSITION": A_POS, "NORMAL": A_NRM, "TEXCOORD_0": A_UV,
                           "JOINTS_0": A_J, "WEIGHTS_0": A_W},
            "indices": A_IDX, "material": 0}]}],
        "skins": [{"inverseBindMatrices": A_IBM, "joints": list(range(nb)),
                   "skeleton": roots[0]}],
        "materials": [{"name": "pld", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"bufferView": vi_img, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": offset}],
    }
    if animations:
        gltf["animations"] = animations

    bin_blob = b"".join(bin_parts)
    json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_blob += b" " * ((4 - len(json_blob) % 4) % 4)
    glb = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(json_blob) + 8 + len(bin_blob))
    glb += struct.pack("<I", len(json_blob)) + b"JSON" + json_blob
    glb += struct.pack("<I", len(bin_blob)) + b"BIN\x00" + bin_blob
    with open(path, "wb") as f:
        f.write(glb)
    return dict(vertices=len(P), faces=len(faces), bones=nb, tex=(atlas_w, atlas_h))


# ----------------------------------------------------------------------------
def build_anim_clips(d, emr, emr_off, emr_end, edd_off, edd_end):
    """Decodifica poses + sequencias EDD -> lista de clips p/ o glTF.

    Exporta TODAS as N sequencias do EDD (22 no PL00) usando a FRAME-LIST para o
    mapeamento frame->pose (com holds/reuso), 1 keyframe glTF por frame de jogo (30 fps).
    Assim: (a) a ultima sequencia (anim21) — antes derrubada — entra; (b) sequencias que
    reusam poses da regiao seguinte (anim06/08) — antes vistas como 'zero' — entram; e
    (c) clipes com hold (anim01/07/11/18) ganham a DURACAO EXATA do jogo."""
    nb = emr["nb"]
    npose = (emr_end - (emr_off + 176)) // 76      # keyframes de 76 bytes apos EMR
    read_pose, POOL, FS = parse_poses(d, emr_off, nb)
    seqs, recs, flstart, N = parse_edd(d, edd_off, edd_end, npose)
    clips = []
    FPS = 30.0
    for cm in seqs:
        nfr = cm["nframes"]; foff = cm["foff"]; pstart = cm["pstart"]
        if nfr < 1:
            continue
        # frame-list: 2 bytes/frame -> pose absoluta = pstart + (entry & 0xFF)
        frames = [u16(d, edd_off + foff + k * 2) for k in range(nfr)]
        idxs = [pstart + (f & 0xFF) for f in frames]
        if any(pi < 0 or pi >= npose for pi in idxs):
            continue                                 # sequencia invalida -> pula
        times = [k / FPS for k in range(len(idxs))]
        rot = [[] for _ in range(nb)]
        roottr = []
        for pi in idxs:
            root, quats = read_pose(pi)
            for b in range(nb):
                q = quats[b]
                # continuidade de hemisfério: um quaternion e o seu negado representam a
                # MESMA rotação, mas a interpolação LINEAR do glTF entre hemisférios
                # opostos "dá a volta" (~360°) e arremessa os membros de extremidade.
                # Garantimos dot>=0 com o keyframe anterior (evita o detachment no Godot).
                if rot[b]:
                    p = rot[b][-1]
                    if q[0]*p[0] + q[1]*p[1] + q[2]*p[2] + q[3]*p[3] < 0:
                        q = (-q[0], -q[1], -q[2], -q[3])
                rot[b].append(q)
            # IN-PLACE: o root (pose+0x00) e' a POSICAO ACUMULADA do quadril ao
            # longo do clipe (root-motion embutido: ex. anim00 vai de X=-69 ate
            # X=-2041 nos 34 frames). Deixar isso no glb faz o mesh (1) DERIVAR sem
            # input, (2) SNAPAR de volta no loop, (3) ficar deslocado do eixo do node
            # (offset inicial != 0) -> ORBITA ao girar. O gameplay ja translada o
            # NODE por velocidade escalar (jill_controller.gd), entao a animacao deve
            # ser puramente visual/IN-PLACE. Zeramos XZ do root (mantendo so o Y,
            # bob vertical) -> quadril fixo no XZ=0 do node em todos os keyframes.
            roottr.append((0.0, -root[1] * SCALE, 0.0))
        clips.append(dict(name=f"anim{cm['index']:02d}", times=times, rot=rot, roottr=roottr))
    return clips, npose


def _edd_nseq(d, edd):
    """nseq de um banco EDD = menor frameOffset dos registros / 8."""
    fl = 10 ** 9
    i = 0
    while i * 8 < fl and i < 512:
        fo = u16(d, edd + i * 8 + 2)
        if 8 <= fo < fl:
            fl = fo
        i += 1
    return fl // 8


def _is_edd_start(d, off):
    if off + 8 > len(d):
        return None
    nf = u16(d, off); fo = u16(d, off + 2)
    if 1 <= nf <= 400 and fo >= 8 and fo % 8 == 0 and fo <= 0x4000:
        return fo // 8
    return None


def _is_emr_hdr(d, off):
    if off + 8 > len(d):
        return None
    kf = u16(d, off + 2); nb = u16(d, off + 4); fsz = u16(d, off + 6)
    if 1 <= nb <= 64 and 8 <= fsz <= 256 and 4 <= kf <= 4096:
        return (kf, nb, fsz)
    return None


def build_armed_clips(plw_path, emr, prefix="arm"):
    """Locomocao ARMADA de gameplay do RE3 — vem do PLW da arma, NAO do PL00.PLD.

    DESCOBERTA (ver tools/find_anim_banks.py e docs/formatos/exe.md): o player anda
    SEMPRE com uma arma na mao; o EXE seleciona o banco de animacao ATIVO conforme a
    arma equipada (player+0xf4/0xf0 = banco do PLW), e o indice player+0xc8 indexa ESSE
    banco. As 22 seqs do PL00.PLD sao o set DESARMADO/base. O andar/correr que se ve no
    jogo estao no BANCO0 do PLW (corpo inteiro, 15 ossos, 76B/pose): seq0=ANDAR,
    seq1=CORRER, seq2/5/8=parado/mira, seq9=re.

    Esta funcao extrai o banco0 do PLW e monta clips RETARGETADOS ao esqueleto do PLD
    (mesmos 15 ossos, mesma ordem => rotacoes locais aplicam direto). Root XZ zerado
    (in-place; o gameplay translada por velocidade escalar). Retorna [] se incompativel."""
    if not os.path.exists(plw_path) or os.path.getsize(plw_path) < 64:
        return []
    d = open(plw_path, "rb").read()
    do = u32(d, 0)
    nd = (len(d) - do) // 4
    ents = [u32(d, do + i * 4) for i in range(nd)]
    edd = bemr = None
    for i in range(len(ents) - 1):
        if _is_edd_start(d, ents[i]) and _is_emr_hdr(d, ents[i + 1]):
            edd, bemr = ents[i], ents[i + 1]
            break
    if edd is None:
        return []
    kf, nb, fsz = _is_emr_hdr(d, bemr)
    if nb != emr["nb"]:
        return []                                    # esqueleto incompativel
    pool = bemr + kf
    pend = min([e for e in ents if e > pool] + [do])
    npose = (pend - pool) // fsz
    nseq = _edd_nseq(d, edd)

    def read_pose(k):
        o = pool + k * fsz
        root = (s16(d, o), s16(d, o + 2), s16(d, o + 4))
        quats = [_euler_to_quat_gltf(_get12(d, o + 8, b * 3),
                                     _get12(d, o + 8, b * 3 + 1),
                                     _get12(d, o + 8, b * 3 + 2)) for b in range(nb)]
        return root, quats

    clips = []
    FPS = 30.0
    for s in range(nseq):
        nf = u16(d, edd + s * 8); fo = u16(d, edd + s * 8 + 2); ps = u32(d, edd + s * 8 + 4)
        if nf < 1:
            continue
        frames = [u16(d, edd + fo + k * 2) & 0xFF for k in range(nf)]
        idxs = [ps + f for f in frames]
        if any(pi < 0 or pi >= npose for pi in idxs):
            continue
        times = [k / FPS for k in range(len(idxs))]
        rot = [[] for _ in range(nb)]
        roottr = []
        for pi in idxs:
            root, quats = read_pose(pi)
            for b in range(nb):
                q = quats[b]
                if rot[b]:
                    p = rot[b][-1]
                    if q[0]*p[0] + q[1]*p[1] + q[2]*p[2] + q[3]*p[3] < 0:
                        q = (-q[0], -q[1], -q[2], -q[3])
                rot[b].append(q)
            roottr.append((0.0, -root[1] * SCALE, 0.0))   # in-place (mantem bob Y)
        clips.append(dict(name=f"{prefix}{s:02d}", times=times, rot=rot, roottr=roottr))
    return clips


def composite_weapon_tim(atlas, aw, ah, UVs, wtex, waw, wah):
    """Sobrepõe a TIM PRÓPRIA da arma sobre a região do atlas do PLD onde a
    geometria da ARMA amostra pixels quase-brancos (o "slot" da arma, que em jogo
    é sobrescrito pela TIM da arma). A caixa dessa região ≈ o tamanho da TIM."""
    whites = []
    for (u, v) in UVs:
        px = min(aw - 1, int(u * aw)); py = min(ah - 1, int(v * ah))
        o = (py * aw + px) * 3
        if atlas[o] > 200 and atlas[o + 1] > 200 and atlas[o + 2] > 200:
            whites.append((px, py))
    if len(whites) < 3:
        return atlas
    xs = [p[0] for p in whites]; ys = [p[1] for p in whites]
    x0, x1 = min(xs), max(xs) + 1; y0, y1 = min(ys), max(ys) + 1
    if (x1 - x0) < 4 or (y1 - y0) < 4 or (x1 - x0) > 160 or (y1 - y0) > 160:
        return atlas                              # região implausível -> não mexe
    a = bytearray(atlas)
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            sy = min(wah - 1, int((yy - y0) / (y1 - y0) * wah))
            sx = min(waw - 1, int((xx - x0) / (x1 - x0) * waw))
            so = (sy * waw + sx) * 3; oo = (yy * aw + xx) * 3
            a[oo] = wtex[so]; a[oo + 1] = wtex[so + 1]; a[oo + 2] = wtex[so + 2]
    return bytes(a)


# ----------------------------------------------------------------------------
# MESH REAL DA ARMA dentro do .PLW  (ver docs/decomp/notes/plw.md)
# ----------------------------------------------------------------------------
# O MD1 do .PLW (bloco de self-length; roles['md1']) NAO e' so a mao: e' a MAO +
# a ARMA numa mesma malha (1-2 objetos). As primitivas se dividem por REGIAO DE
# TEXTURA amostrada no atlas do PLD:
#   * MAO  -> amostra a PELE (regiao normal do atlas do personagem).
#   * ARMA -> amostra o "SLOT" da arma: um retangulo quase-BRANCO no atlas do PLD
#             (banda da paleta 1, canto inf-central) que EM JOGO e' sobrescrito
#             pela TIM PROPRIA da arma (56x32, bloco TIM do .PLW, VRAM 512,0).
# Logo a GEOMETRIA da arma = as primitivas cujos cantos amostram esse branco.
# Reusa parse_md1 / parse_tim_atlas / write_glb_static. Confirmado por render:
# W01 (cano/rifle), W03/W02 (lamina+guarda da faca) saem como malha branca; o
# handgun W00 NAO tem slot (fica so o punho -> a arma esta pintada na pele).
def _load_pld_atlas_for(plw_path):
    """Atlas de PELE do PLD correspondente (PL00W03 -> PL00.PLD), p/ localizar o
    slot branco da arma. Retorna (aw,ah,band,npal,atlas) ou None."""
    import re
    m = re.match(r"(PL[0-9A-Fa-f]{2})W", os.path.basename(plw_path), re.I)
    if not m:
        return None
    pld = os.path.join(os.path.dirname(plw_path), m.group(1) + ".PLD")
    if not (os.path.exists(pld) and os.path.getsize(pld) > 64):
        return None
    dp = open(pld, "rb").read()
    po, ps = parse_container(dp)
    pr = classify(dp, po, ps)
    if "tim" not in pr:
        return None
    return parse_tim_atlas(dp, ps[pr["tim"]][0])


def _prim_samples_white(prim, aw, ah, band, npal, atlas, thr=200):
    """True se a MAIORIA dos cantos da primitiva amostra pixel quase-branco no
    atlas do PLD (o slot da arma). atlas_x = tx*128 + u (8bpp) ; atlas_y = pal*band + v."""
    ptype, vi, uv, pal, tx = prim
    pp = pal if 0 <= pal < npal else 0
    white = 0
    for (u, v) in uv:
        ax = tx * 128 + u
        ay = pp * band + v
        if 0 <= ax < aw and 0 <= ay < ah:
            o = (ay * aw + ax) * 3
            if atlas[o] > thr and atlas[o + 1] > thr and atlas[o + 2] > thr:
                white += 1
    return white * 2 >= len(uv)               # >= metade dos cantos


def split_weapon_prims(objs, aw, ah, band, npal, atlas):
    """Divide as primitivas do MD1 do PLW em ARMA (amostram o slot branco) e MAO.
    Retorna (weapon_prims, hand_prims, box) onde cada prim = (obj_idx, prim) e box =
    [x0,y0,x1,y1] do slot no atlas (bbox dos cantos brancos das prims de arma)."""
    weapon, hand = [], []
    box = [10 ** 9, 10 ** 9, -1, -1]
    for oi, ob in enumerate(objs):
        for prim in ob["prims"]:
            if _prim_samples_white(prim, aw, ah, band, npal, atlas):
                weapon.append((oi, prim))
                ptype, vi, uv, pal, tx = prim
                pp = pal if 0 <= pal < npal else 0
                for (u, v) in uv:
                    ax = tx * 128 + u; ay = pp * band + v
                    box[0] = min(box[0], ax); box[1] = min(box[1], ay)
                    box[2] = max(box[2], ax); box[3] = max(box[3], ay)
            else:
                hand.append((oi, prim))
    return weapon, hand, box


def extract_weapon(plw_path, out_glb, preview=None):
    """Exporta a GEOMETRIA REAL DA ARMA do .PLW como malha estatica propria,
    texturizada com a TIM PROPRIA da arma (56x32). As UVs das prims de arma
    (que no atlas do PLD apontam p/ o slot branco) sao REMAPEADAS p/ dentro da
    TIM da arma: uv_arma = (atlas_xy - slot_min) / slot_dim. Levanta ValueError se
    a arma nao tiver slot (ex.: handgun W00 -> arma embutida na pele da mao)."""
    d = open(plw_path, "rb").read()
    offs, sec = parse_container(d)
    roles = classify(d, offs, sec)
    if "md1" not in roles or "tim" not in roles:
        raise ValueError("PLW sem MD1/TIM")
    objs = parse_md1(d, sec[roles["md1"]][0])
    pld = _load_pld_atlas_for(plw_path)
    if pld is None:
        raise ValueError("PLD base ausente (nao da p/ localizar o slot da arma)")
    aw, ah, band, npal, atlas = pld
    # TIM PROPRIA da arma (bloco TIM do PLW), decodificada com a sua CLUT -> 56x32
    waw, wah, wband, wnpal, watlas = parse_tim_atlas(d, sec[roles["tim"]][0])
    weapon, hand, box = split_weapon_prims(objs, aw, ah, band, npal, atlas)
    if not weapon:
        raise ValueError("nenhuma primitiva de arma (slot branco) — arma na pele?")
    bx0, by0, bx1, by1 = box
    bw = max(1, bx1 - bx0); bh = max(1, by1 - by0)

    P_, N_, UV_, faces = [], [], [], []
    cache = {}

    def corner(oi, vl, u, v, pp, tx):
        ax = tx * 128 + u; ay = pp * band + v
        wu = (ax - bx0) / bw                          # 0..1 dentro do slot -> TIM da arma
        wv = (ay - by0) / bh
        wu = 0.0 if wu < 0 else (1.0 if wu > 1 else wu)
        wv = 0.0 if wv < 0 else (1.0 if wv > 1 else wv)
        key = (oi, vl, round(wu, 4), round(wv, 4))
        gi = cache.get(key)
        if gi is None:
            gi = len(P_)
            P_.append(objs[oi]["verts"][vl]); N_.append(objs[oi]["norms"][vl])
            UV_.append((wu, wv))
            cache[key] = gi
        return gi

    for oi, prim in weapon:
        ptype, vi, uv, pal, tx = prim
        pp = pal if 0 <= pal < npal else 0
        if ptype == "tri":
            a = corner(oi, vi[0], uv[0][0], uv[0][1], pp, tx)
            b = corner(oi, vi[1], uv[1][0], uv[1][1], pp, tx)
            c = corner(oi, vi[2], uv[2][0], uv[2][1], pp, tx)
            faces.append((a, b, c))
        else:
            a = corner(oi, vi[0], uv[0][0], uv[0][1], pp, tx)
            b = corner(oi, vi[1], uv[1][0], uv[1][1], pp, tx)
            c = corner(oi, vi[2], uv[2][0], uv[2][1], pp, tx)
            e = corner(oi, vi[3], uv[3][0], uv[3][1], pp, tx)
            faces.append((a, b, c)); faces.append((b, e, c))

    info = write_glb_static(out_glb, P_, N_, UV_, faces, waw, wah, watlas)
    info.update(roles=roles, objects=len(objs), weapon_prims=len(weapon),
                hand_prims=len(hand), slot_box=box, static=True, weapon=True,
                tex=(waw, wah))
    if preview:
        render_preview(P_, UV_, faces, waw, wah, watlas, preview)
    return info


def convert(path, out_glb, preview=None, with_anim=True, hd_atlas=None):
    """hd_atlas=(w,h,rgb): substitui a textura PS1 por uma versão HD (mesmo layout,
    resolução maior). As UVs são normalizadas pelas dims LÓGICAS do PS1, então a
    imagem HD (múltiplo inteiro) mapeia sem alterar as UVs."""
    d = open(path, "rb").read()
    offs, sec = parse_container(d)
    roles = classify(d, offs, sec)
    objs = parse_md1(d, sec[roles["md1"]][0])
    aw, ah, band_h, npal, atlas = parse_tim_atlas(d, sec[roles["tim"]][0])
    # armas (.PLW) e afins nao tem esqueleto padrao -> exporta malha estatica
    try:
        emr_off, emr_end = sec[roles["emr"]]
        emr = parse_emr(d, emr_off, emr_end)
        if not (1 <= emr["nb"] <= 64) or emr["nb"] != len(objs) and emr["nb"] > len(objs):
            raise ValueError("EMR incompativel com a malha")
    except Exception:
        # .PLW: a MÃO usa a textura de PELE do PERSONAGEM (PLD); a ARMA usa a TIM
        # própria dela. Carregamos o atlas do PLD e SOBREPOMOS a TIM da arma na
        # região onde a geometria da arma amostra (PL00W03 -> PL00.PLD).
        import re
        weapon_tim = (aw, ah, atlas)             # TIM própria da arma (56x32)
        m = re.match(r"(PL[0-9A-Fa-f]{2})W", os.path.basename(path))
        tex_src = "propria (PLW)"
        if m:
            pld_path = os.path.join(os.path.dirname(path), m.group(1) + ".PLD")
            if os.path.exists(pld_path) and os.path.getsize(pld_path) > 64:
                dp = open(pld_path, "rb").read()
                po, ps = parse_container(dp)
                pr = classify(dp, po, ps)
                if "tim" in pr:
                    aw, ah, band_h, npal, atlas = parse_tim_atlas(dp, ps[pr["tim"]][0])
                    tex_src = m.group(1) + ".PLD (pele) + TIM da arma"
        Ps, Ns, UVs, fs = assemble_static(objs, aw, ah, band_h, npal)
        if tex_src != "propria (PLW)":
            atlas = composite_weapon_tim(atlas, aw, ah, UVs, weapon_tim[2],
                                         weapon_tim[0], weapon_tim[1])
        info = write_glb_static(out_glb, Ps, Ns, UVs, fs, aw, ah, atlas)
        info.update(roles=roles, objects=len(objs), poses=0, animations=0,
                    static=True, tex_src=tex_src)
        if preview:
            render_preview(Ps, UVs, fs, aw, ah, atlas, preview)
        return info
    P, N, UV, J, W, faces = assemble(objs, emr, aw, ah, band_h, npal)
    clips = None
    npose = 0
    if with_anim and "edd" in roles:
        edd_off, edd_end = sec[roles["edd"]]
        clips, npose = build_anim_clips(d, emr, emr_off, emr_end, edd_off, edd_end)
        # Locomocao ARMADA (andar/correr/parada/re REAIS de gameplay) do PLW da arma
        # padrao (handgun W00). Retargetada ao esqueleto do PLD. Prefixo "arm".
        import re as _re
        _m = _re.match(r"(PL[0-9A-Fa-f]{2})\.PLD$", os.path.basename(path), _re.I)
        if _m:
            _plw = os.path.join(os.path.dirname(path), _m.group(1) + "W00.PLW")
            _armed = build_armed_clips(_plw, emr)
            if _armed:
                clips = (clips or []) + _armed
    taw, tah, trgb = hd_atlas if hd_atlas else (aw, ah, atlas)
    info = write_glb(out_glb, P, N, UV, J, W, faces, emr, taw, tah, trgb, anim_clips=clips)
    info["roles"] = roles
    info["objects"] = len(objs)
    info["poses"] = npose
    info["animations"] = len(clips) if clips else 0
    if preview:
        render_preview(P, UV, faces, aw, ah, atlas, preview)
    return info


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); return 1
    if args[0] == "--weapon":
        # python pld2gltf.py --weapon <arq.PLW> [saida.glb] [--preview p.png]
        src = args[1]
        out = args[2] if len(args) > 2 and not args[2].startswith("--") else \
            os.path.splitext(os.path.basename(src))[0] + "_WPN.glb"
        prev = args[args.index("--preview") + 1] if "--preview" in args else None
        info = extract_weapon(src, out, prev)
        print("ARMA: %d prims (mao=%d) slot=%s tex=%s -> %d v %d f -> %s" %
              (info["weapon_prims"], info["hand_prims"], info["slot_box"],
               info["tex"], info["vertices"], info["faces"], out))
        if prev:
            print("preview ->", prev)
        return 0
    if args[0] == "--weapons-all":
        # extrai a arma de TODOS os .PLW p/ godot/assets/PLD/<nome>_WPN.glb
        src = "extracted/ntsc-u/CD_DATA/PLD"
        dst = args[1] if len(args) > 1 else paths.assets("PLD")
        os.makedirs(dst, exist_ok=True)
        import glob
        ok = skip = fail = 0
        for f in sorted(glob.glob(os.path.join(src, "*.PLW"))):
            if os.path.getsize(f) < 64:
                continue
            name = os.path.splitext(os.path.basename(f))[0]
            out = os.path.join(dst, name + "_WPN.glb")
            try:
                info = extract_weapon(f, out)
                print("OK  %-9s arma=%dprims %dv %df -> %s" %
                      (name, info["weapon_prims"], info["vertices"], info["faces"], out))
                ok += 1
            except ValueError as e:
                print("--  %-9s sem malha de arma (%s)" % (name, e)); skip += 1
            except Exception as e:
                print("ERR %-9s %s" % (name, e)); fail += 1
        print("--- %d armas exportadas, %d sem-slot, %d erros ---" % (ok, skip, fail))
        return 0
    if args[0] == "--all":
        src = "extracted/ntsc-u/CD_DATA/PLD"
        dst = paths.assets("PLD")
        os.makedirs(dst, exist_ok=True)
        import glob
        want_plw = "--plw" in args
        pats = ["*.PLD"] + (["*.PLW"] if want_plw else [])
        files = []
        for p in pats:
            files += glob.glob(os.path.join(src, p))
        ok = fail = 0
        for f in sorted(files):
            if os.path.getsize(f) < 64:
                print(f"skip {os.path.basename(f)} (stub)"); continue
            name = os.path.splitext(os.path.basename(f))[0]
            out = os.path.join(dst, name + ".glb")
            try:
                info = convert(f, out)
                tag = "static" if info.get("static") else f"{info['poses']}poses {info['animations']}anim"
                print(f"OK  {name}: {info['vertices']}v {info['faces']}f {info['bones']}b {tag} -> {out}")
                ok += 1
            except Exception as e:
                print(f"ERRO {name}: {e}"); fail += 1
        print(f"--- {ok} convertidos, {fail} falhas ---")
        return 0
    path = args[0]
    out = args[1] if len(args) > 1 and not args[1].startswith("--") else "out.glb"
    preview = None
    if "--preview" in args:
        preview = args[args.index("--preview") + 1]
    info = convert(path, out, preview)
    print("roles:", info["roles"], "objects:", info["objects"])
    print(f"vertices={info['vertices']} faces={info['faces']} bones={info['bones']} "
          f"tex={info['tex']} poses={info['poses']} animations={info['animations']}")
    print("->", out)
    if preview:
        print("preview ->", preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
