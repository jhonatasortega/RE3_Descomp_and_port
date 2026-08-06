#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
emd2gltf.py - Exporta modelos de INIMIGO do RE3 (versao PC/GOG) para .glb.

Os inimigos do RE3 estao como .EMD standalone dentro dos `Rofs*.dat` do port de PC
(GOG): `ROOM/EMD` (Rofs9) e `ROOM/EMD08` (Rofs10). Extraia com `rofs_extract.py`.
O .EMD do PS1 embutido no `R###.BIN` e' reempacotado in-RAM (formato empacotado, ver
docs/decomp/notes/enemy_mesh.md); o .EMD do PC e' o MESMO modelo em formato LIMPO
(structs `emd3.h` do reevengi-tools), o que permite decodificar a geometria.

Formato EMD RE3 (reevengi `src/emd3.h`), little-endian:
  emd_header_t   @0     : { u32 offset(->diretorio), u32 length }
  emd3_directory_t @offset (15 u32): unknown0[2], anim0, skel0, anim1, skel1,
                                     anim2, skel2, unknown1[6], model
  MODELO @dir.model:
    emd3_model_header_t { u32 length; u32 count }         count = nº de objetos (=ossos)
    emd3_model_object_t[count] (24B): u32 vtx_off, nor_off, vtx_count,
                                      tri_off, quad_off; u16 tri_count, quad_count
      (offsets relativos ao INICIO do array de objetos = model+8)
    vertices/normais: emd_vertex4_t { s16 x,y,z; s16 pad } (8B); nor_count == vtx_count
    emd3_triangle_t (12B): u8 tu0,tv0, page,dummy0, tu1,tv1, clutid,v0, tu2,tv2, v1,v2
    emd3_quad_t    (16B): u8 tu0,tv0, page,dummy0, tu1,tv1, clutid,dummy1,
                          tu2,tv2, v0,v1, tu3,tv3, v2,v3
  SKINNING RIGIDO: 1 objeto por osso; verts em espaco LOCAL do osso.

Esqueleto/animacao: o esqueleto do PC e' quase identico ao EMR do PS1 (15 ossos, mesma
ordem/hierarquia, move_size=76). Reusamos o EMR + as 16 animacoes ja provadas do
`R###.BIN` do PS1 (pld2gltf.parse_emr/build_anim_clips) p/ animar a malha do PC.

Uso:
  python tools/emd2gltf.py <EM##.EMD> <EM##.TIM> <saida.glb> [--ps1 <R###.BIN> <blk>]
"""
import os, sys, struct, json
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pld2gltf as P
import bin2gltf as B

def u8(d, o):  return d[o]
def u16(d, o): return struct.unpack_from("<H", d, o)[0]
def s16(d, o): return struct.unpack_from("<h", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]


# ---------------------------------------------------------------------------
# EMD (RE3 PC) — geometria
# ---------------------------------------------------------------------------
def emd_directory(d):
    off = u32(d, 0)
    keys = ["u0", "u1", "anim0", "skel0", "anim1", "skel1", "anim2", "skel2",
            "u2", "u3", "u4", "u5", "u6", "u7", "model"]
    return {keys[i]: u32(d, off + i * 4) for i in range(15)}


def parse_emd_model(d):
    """Retorna (objs, count, anomalias). objs = lista dict(verts, norms, prims).
    ROBUSTO: alguns EMDs tem objetos com offset/contagem invalidos (osso sem malha,
    dados compartilhados) -> tais objetos/prims sao pulados e registrados em 'anomalias'
    (ver docs/decomp/notes/enemy_mesh.md). prims = (tipo, vi, uv, clut, page).

    VARIANTE COM FLAGS NO U16 ALTO (EM16, EM1E, EM25, EM2D): nesses EMDs o u16 ALTO de
    vtx_count/vtx_off/nor_off/tri_off/quad_off carrega bytes de flag (ex.: 0x15xx0000),
    NAO uma parte real do valor. A regiao de modelo de TODOS os 69 EMD tem <64 KB
    (max model_len=28760), logo todo offset/contagem interno cabe em 16 bits -> mascarar
    com 0xFFFF e' seguro p/ os 69 e recupera o EM2D 100% (era o unico que nao decodificava
    antes, marcado 'corrompido' por engano). Prova: com a mascara, os vtx_off ficam
    sequenciais e batem 15/15 com vtx_count na aritmetica (ver docs/decomp/notes/enemy_mesh.md).
    Regra estrutural: a lista de tri vem ANTES da de quad, entao tri_off==quad_off <=> 0 tris
    (nos objetos com flag o tri_count le lixo; forcar tc=0 quando tri_off==quad_off)."""
    n = len(d)
    dirn = emd_directory(d)
    model = dirn["model"]
    count = u32(d, model + 4)
    ob = model + 8                              # base dos offsets internos
    objs = []; anom = []
    for i in range(count):
        o = ob + i * 24
        # mascara 16 bits: descarta flags no u16 alto (variante EM16/EM1E/EM25/EM2D).
        vtx = u32(d, o) & 0xFFFF; nor = u32(d, o + 4) & 0xFFFF; vc = u32(d, o + 8) & 0xFFFF
        tri = u32(d, o + 12) & 0xFFFF; quad = u32(d, o + 16) & 0xFFFF
        tc = u16(d, o + 20); qc = u16(d, o + 22)
        # tri_count/quad_count sao efetivamente u8+u8_flag na variante com flags: o max
        # legitimo nos 69 EMD e' 232 (<256), entao um valor >0xFF => byte alto = flag
        # (ex.: EM25 obj19 qc=0xFD35 -> 53; EM16/EM1E obj8/10 tc). No-op p/ os sadios.
        if tc > 0xFF:
            tc &= 0xFF
        if qc > 0xFF:
            qc &= 0xFF
        if tri == quad:                         # invariante: sem lista de tri separada
            tc = 0
        verts, norms, prims = [], [], []
        if vc > 4000 or ob + vtx + vc * 8 > n or ob + nor + vc * 8 > n:
            anom.append("obj%d verts invalidos (vc=%d)" % (i, vc))
        else:
            verts = [(s16(d, ob + vtx + k * 8), s16(d, ob + vtx + k * 8 + 2),
                      s16(d, ob + vtx + k * 8 + 4)) for k in range(vc)]
            norms = [(s16(d, ob + nor + k * 8), s16(d, ob + nor + k * 8 + 2),
                      s16(d, ob + nor + k * 8 + 4)) for k in range(vc)]
        nv = len(verts)
        if tc <= 4000 and ob + tri + tc * 12 <= n:
            for t in range(tc):
                p = ob + tri + t * 12
                vi = (u8(d, p + 7), u8(d, p + 10), u8(d, p + 11))
                if max(vi) >= nv:
                    continue
                uv = ((u8(d, p + 0), u8(d, p + 1)), (u8(d, p + 4), u8(d, p + 5)),
                      (u8(d, p + 8), u8(d, p + 9)))
                prims.append(("tri", vi, uv, u8(d, p + 6), u8(d, p + 2)))
        elif tc:
            anom.append("obj%d tri invalido (tc=%d)" % (i, tc))
        if qc <= 4000 and ob + quad + qc * 16 <= n:
            for q in range(qc):
                p = ob + quad + q * 16
                vi = (u8(d, p + 10), u8(d, p + 11), u8(d, p + 14), u8(d, p + 15))
                if max(vi) >= nv:
                    continue
                uv = ((u8(d, p + 0), u8(d, p + 1)), (u8(d, p + 4), u8(d, p + 5)),
                      (u8(d, p + 8), u8(d, p + 9)), (u8(d, p + 12), u8(d, p + 13)))
                prims.append(("quad", vi, uv, u8(d, p + 6), u8(d, p + 2)))
        elif qc:
            anom.append("obj%d quad invalido (qc=%d)" % (i, qc))
        objs.append(dict(verts=verts, norms=norms, prims=prims))
    return objs, count, anom


# ---------------------------------------------------------------------------
# Mapeamento UV -> atlas do TIM
#   page (tpage): bit0-3 = X base em unidades de 64 halfwords; 8bpp -> *128 texels
#   clutid: bits0-5 = indice de CLUT -> banda de paleta vertical no atlas
# ---------------------------------------------------------------------------
def uv_to_atlas(page, clut, u, v, atlas_w, atlas_h, band_h, npal):
    tx = (page >> 6) & 0x03                 # unidade de tpage X (8bpp: passo 128 texels)
    pal = clut & 0x3F                       # id de CLUT (paleta)
    if pal >= npal:
        pal = 0
    ax = tx * 128 + u
    ay = pal * band_h + v
    return (ax / atlas_w, ay / atlas_h)


# ---------------------------------------------------------------------------
# SECAO dir[0] ("unknown0[0]" do reevengi) = TABELA REAL DE SKINNING
# ---------------------------------------------------------------------------
# ***ISTO SUBSTITUI TODA A HEURISTICA DE OSSO/ESPACO.***  (revisa emd_skinning.md
# sec.10-12, que concluia que o binding por-vertice era irrecuperavel do EMD do PC:
# ele NUNCA foi perdido — esta em dir[0], que ninguem havia decodificado.)
#
# Layout (little-endian, offsets relativos ao inicio da secao):
#   +0  u32 mask        bitmask de OBJETOS que tem binding explicito (multi-osso).
#                       popcount(mask) == u16@6.  Objeto fora da mask = rigido 1:1.
#   +4  u16 coord_off   offset da TABELA DE COORDENADAS
#   +6  u16 nent        numero de entradas (== popcount(mask))
#   +8  nent x 8B       1 entrada por bit setado, na ordem dos bits. Cada entrada tem
#                       ate 4 u16 = offsets AUTO-RELATIVOS (relativos ao endereco da
#                       PROPRIA entrada, i.e. abs = sec+8+8k+valor); 0 = ausente.
#   +coord_off  nb x (s16 x,y,z) = -world[i] (relpos ACUMULADO, negado) = a translacao
#                       do INVERSE BIND.  Verificado identico ao EMR em 41/41 arquivos.
#   listas: [u8 osso][u8 nbatches][3*nbatches u8 indices de vertice] ... [0xFF]
#                       nbatches = ceil(n/3) (o GTE do PS1 transforma 3 verts por RTPT);
#                       o slot sobrando e' preenchido repetindo o ultimo indice ou com
#                       0xFF. A uniao dos indices de um objeto cobre EXATAMENTE
#                       range(vtx_count) (validado em 221/235 objetos).
#
# CONVENCAO DE ESPACO (medido: 607 grupos a favor contra 16): nos objetos listados na
# mask os vertices estao em ESPACO-MODELO ABSOLUTO (espaco do osso 0) — e' exatamente
# o "model-space" que _is_model_space tentava adivinhar. Fora da mask: bone-local.
def parse_u0_skin(d, nb, objs):
    """-> None, ou dict(mask, inv_world, obj_bones={obj: {vidx: [ossos]}}).
    obj_bones[o][v] = lista de ossos que dirigem o vertice v do objeto o (o 1o = principal)."""
    off = u32(d, 0)
    vals = [u32(d, off + i * 4) for i in range(15)]
    o = vals[0]
    n = min([v for v in vals + [off] if v > o] or [off]) - o
    if n <= 8 or o + n > len(d):
        return None
    mask = u32(d, o); coff = u16(d, o + 4); nent = u16(d, o + 6)
    bits = [b for b in range(32) if mask >> b & 1]
    if not bits or nent != len(bits) or coff + nb * 6 > n:
        return None
    inv_world = [(s16(d, o + coff + i * 6), s16(d, o + coff + i * 6 + 2),
                  s16(d, o + coff + i * 6 + 4)) for i in range(nb)]
    end = o + n

    def read_groups(p, vc):
        """FORMATO A (listas 0 e 1): [osso][nbatches][idx...] ate 0xFF -> [(osso,[idx])]

        RESSINCRONIZA em cabecalho invalido em vez de abortar a lista inteira: avanca 1 byte
        e tenta de novo (ate 24). No EM40 o cabecalho do 1o grupo le `00 00` (nbat=0) onde
        deveria ser `00 03` — abortando ali, os 72 vertices ficavam TODOS sem osso; com
        ressincronia recuperam-se os grupos dos ossos 1..4 (64 dos 72 vertices) e o resto
        cai no fallback limitado. A soma dos grupos legiveis fecha 72/72 exatos, entao o
        dado esta la; so o header do 1o grupo e' que nao decodifica."""
        out = []
        skipped = 0
        while p < end and d[p] != 0xFF:
            b = d[p]; nbat = d[p + 1] if p + 1 < end else 0
            if b >= nb or nbat == 0 or p + 2 + nbat * 3 > end:
                skipped += 1
                if skipped > 24:
                    break
                p += 1
                continue
            raw = d[p + 2:p + 2 + nbat * 3]
            out.append((b, sorted(set(x for x in raw if x != 0xFF and x < vc))))
            p += 2 + nbat * 3
        return out

    def read_seams(p, vc):
        """FORMATO B (lista 2+) = COSTURA: registro de 8 B
             [u8 ossoA][u8 ossoB] + 3x ([u8 idx][u8 peso])   ; 0xFF encerra
        Sao os vertices da JUNTA, influenciados por DOIS ossos. Sem esta lista ~6% dos
        vertices dos objetos multi-osso ficavam sem osso (caiam na ancora) — era o
        resto do descolamento em EM5F/EM30/EM33. Prova: os vertices que faltavam no
        obj8 do EM5F (66,78,80,83) estao exatamente aqui (0x42,0x4e,0x50,0x53).
        O 2o byte de cada par (0x20/0x60/0x74/...) parece ser PESO; nao usado (ver §13.6)."""
        out = []
        while p + 8 <= end and d[p] != 0xFF:
            a = d[p]; b = d[p + 1]
            if a >= nb or b >= nb:
                break
            idx = [x for x in (d[p + 2], d[p + 4], d[p + 6]) if x < vc]
            out.append((a, b, sorted(set(idx))))
            p += 8
        return out

    obj_bones = {}
    for k, bit in enumerate(bits):
        if bit >= len(objs):
            continue
        vc = len(objs[bit]["verts"])
        if vc == 0:
            continue
        ent = o + 8 + k * 8
        vb = {}

        def add(x, b):
            if b not in vb.setdefault(x, []):
                vb[x].append(b)

        for j in range(4):
            v = u16(d, ent + j * 2)
            if v == 0 or ent + v >= end:
                continue
            if j < 2:
                for b, idx in read_groups(ent + v, vc):
                    for x in idx:
                        add(x, b)
            else:
                for a, b, idx in read_seams(ent + v, vc):
                    for x in idx:
                        add(x, a); add(x, b)
        if vb:
            obj_bones[bit] = vb
    if not obj_bones:
        return None
    return dict(mask=mask, inv_world=inv_world, obj_bones=obj_bones)


def _is_model_space(ob, wb):
    """True se a PARTE ja esta em ESPACO-MODELO absoluto (verts ~ posicao do osso),
    em vez de espaco-de-osso (verts ~ pequenos, relativos a junta).

    ***RESIDUO (b): cabeca/maos/pes descolados.*** Igual ao .PLD (ver PLD.md sec.4), a
    maioria dos EMD sao bone-local (obj i centrado perto da origem -> soma-se world[i]),
    MAS algumas PARTES-FOLHA (ex.: os PES do EM2E, raw verts com Y~1860 == world Y 1844)
    sao autoradas em MODELO ABSOLUTO. Somar world nelas as DUPLICA -> a parte "voa"
    (pe pra baixo, cabeca pra cima) em TODOS os frames. Detecta-se comparando o
    centroide da parte com o world do osso: se o centroide ja ESTA no osso
    (|centroide-world| << |world|), a parte e' model-space e NAO leva offset.
    Conservador (so dispara quando o centroide praticamente coincide com o osso) p/
    nao reclassificar partes bone-local legitimas (que tem centroide=offset local,
    longe do world)."""
    vs = ob["verts"]; n = len(vs)
    if n == 0:
        return False
    cx = sum(v[0] for v in vs) / n
    cy = sum(v[1] for v in vs) / n
    cz = sum(v[2] for v in vs) / n
    wmag = (wb[0] * wb[0] + wb[1] * wb[1] + wb[2] * wb[2]) ** 0.5
    if wmag <= 400.0:
        return False                                  # osso perto da origem: sempre soma (no-op)
    dc = ((cx - wb[0]) ** 2 + (cy - wb[1]) ** 2 + (cz - wb[2]) ** 2) ** 0.5
    return dc < 0.30 * wmag


def _declaw_outliers(verts):
    """Solda vertices ESPETO (flung) ISOLADOS ao vizinho mais proximo da propria parte.

    ***RESIDUO (b): vertices "espeto".*** Algumas malhas incerto/BAIXA (EM2C, EM2D e uns
    poucos objetos de EM36/EM3A) tem no ARQUIVO vertices genuinamente anomalos (ex.: EM2C
    obj4 vert13 y=1321 com o resto da parte em ~±300; os bytes conferem, NAO e' misread).
    Ligados por faces aos vertices normais viram espinhos longos.

    Deteccao ROBUSTA por vizinho-mais-proximo (NN) RELATIVA a parte: numa parte COMPACTA
    (NN mediano pequeno), um vertice cujo NN > max(6x o NN mediano, 500) esta ISOLADO ->
    espeto. Snap p/ a posicao do vizinho mais proximo (o triangulo colapsa num sliver).
    Distingue de malhas legitimamente ESPARSAS (helicopteros EM3E/EM3F, vermes): nelas o
    NN mediano ja e' grande, entao o limiar sobe junto e NADA e' marcado. Validado
    varrendo os 69: so EM2C/EM2D/EM36/EM3A disparam; EM3E/EM3F/vermes ficam intactos."""
    n = len(verts)
    if n < 5:
        return verts
    nn = []; nni = []
    for j in range(n):
        vj = verts[j]; best = 1e18; bi = j
        for k in range(n):
            if k == j:
                continue
            u = verts[k]
            dd = (vj[0] - u[0]) ** 2 + (vj[1] - u[1]) ** 2 + (vj[2] - u[2]) ** 2
            if dd < best:
                best = dd; bi = k
        nn.append(best ** 0.5); nni.append(bi)
    s = sorted(nn); mnn = s[len(s) // 2] or 1.0
    thr = max(6.0 * mnn, 500.0)
    if all(x <= thr for x in nn):
        return verts                                  # caminho comum: nada a fazer
    return [verts[nni[j]] if nn[j] > thr else verts[j] for j in range(n)]


# --- helpers de matriz 3x3 (row-major) para a bind pose completa (com rotacao) ---
def _qm(q):
    x, y, z, w = q
    return [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y),
            2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x),
            2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)]


def _mm(a, b):
    return [sum(a[r * 3 + k] * b[k * 3 + c] for k in range(3)) for r in range(3) for c in range(3)]


def _mv(m, v):
    return (m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
            m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
            m[6] * v[0] + m[7] * v[1] + m[8] * v[2])


def _mt(m):
    return [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]


def gbind(emr, bind_rot):
    """FK da BIND POSE em espaco glTF: por osso, (R 3x3 row-major, t vec3) globais,
    usando node_translation (cvt p/ glTF) + rotacao de bind (pose0, ja em quat glTF).
    Se bind_rot==None -> rotacoes identidade (recai no caso humano = so translacao)."""
    SCALE = P.SCALE
    nb = emr["nb"]; parent = emr["parent"]; nt = emr["node_translation"]

    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)

    Rg = [None] * nb; tg = [None] * nb
    done = [False] * nb
    guard = 0
    while not all(done) and guard < nb * nb + 8:
        guard += 1
        for j in range(nb):
            if done[j]:
                continue
            p = parent[j]
            if p >= 0 and not done[p]:
                continue
            Rj = _qm(bind_rot[j]) if (bind_rot and j < len(bind_rot) and bind_rot[j]) \
                else [1, 0, 0, 0, 1, 0, 0, 0, 1]
            Tj = cvt(nt[j])
            if p < 0:
                Rg[j] = Rj; tg[j] = Tj
            else:
                Rg[j] = _mm(Rg[p], Rj)
                rp = _mv(Rg[p], Tj)
                tg[j] = (tg[p][0] + rp[0], tg[p][1] + rp[1], tg[p][2] + rp[2])
            done[j] = True
    for j in range(nb):                               # tolerante a hierarquia quebrada
        if not done[j]:
            Rg[j] = [1, 0, 0, 0, 1, 0, 0, 0, 1]; tg[j] = cvt(nt[j])
    return Rg, tg


def _skin_gap_proxy(pos, bones, parent, nb):
    """Replica (em CPU) a metrica 'vao' do godot/dev/rig_check.gd na POSE DE REPOUSO:
    agrupa as posicoes model-space por osso, mede o vao (dist entre AABBs) de cada grupo
    ate o grupo do seu OSSO-PAI, normalizado pela diagonal do corpo, e devolve o maior.
    Em repouso a posicao skinada == pos (G*G^-1*pos), entao esta e' EXATAMENTE a metrica
    que o rig_check reporta no frame 'rest'. Usada p/ escolher, POR MODELO, a atribuicao
    osso->vertice que MINIMIZA o vao (nunca regride os modelos ja corretos)."""
    if not pos:
        return 0.0
    from collections import defaultdict
    grp = defaultdict(list)
    for p, b in zip(pos, bones):
        grp[b].append(p)
    mn = [min(p[i] for p in pos) for i in range(3)]
    mx = [max(p[i] for p in pos) for i in range(3)]
    diag = max(1e-3, sum((mx[i] - mn[i]) ** 2 for i in range(3)) ** 0.5)
    box = {b: ([min(q[i] for q in g) for i in range(3)],
               [max(q[i] for q in g) for i in range(3)]) for b, g in grp.items()}
    worst = 0.0
    for b, (amn, amx) in box.items():
        par = parent[b] if 0 <= b < len(parent) else -1
        if 0 <= par < nb and par in box:
            bmn, bmx = box[par]; d = 0.0
            for ax in range(3):
                if amx[ax] < bmn[ax]:
                    d += (bmn[ax] - amx[ax]) ** 2
                elif bmx[ax] < amn[ax]:
                    d += (amn[ax] - bmx[ax]) ** 2
            g = d ** 0.5 / diag
            if g > worst:
                worst = g
    return worst


# ---------------------------------------------------------------------------
# ENVELOPE SKINNING (metodo `assemble` do pld2gltf/Jill, ADAPTADO ao EMD do inimigo)
# ---------------------------------------------------------------------------
# A Jill (PL00) resolve o problema "malha solta dos ossos" (objetos que abrangem
# VaRIOS ossos: braco=braco+antebraco numa peca) com ENVELOPE GEOMeTRICO: cada osso
# vira um SEGMENTO de reta e cada vertice pesa nos 2 segmentos MAIS PROXIMOS por
# 1/dist^POWER (sem indice-de-osso do arquivo). Ver pld2gltf.assemble.
#
# ***POR QUE o `assemble` cru REGRIDE o zumbi EM10 (vao 0,000 -> 0,283)?***
# O `assemble` da Jill classifica os pedacos "corpo" como SUBSTANCIAIS testando
# `not _is_bone_local` (verts em ESPACO-MODELO, longe da origem) — convencao do .PLD.
# MAS a malha do EMD do inimigo e' TODA bone-local (verts pequenos, relativos a junta).
# Logo NENHUM objeto e' "substancial" -> `subst_bone` fica VAZIO -> `_chain_cands`
# nunca acha o batente `if c in subst_bone` e DESCE A CADEIA FK INTEIRA: cada objeto
# vira candidato de TODA a sub-arvore abaixo dele. O zumbi (15 obj = 15 ossos LIMPOS,
# cada objeto ja e' seu proprio osso) e' entao super-misturado entre dezenas de
# segmentos distantes -> a malha racha. (Confirmado varrendo EM10 vs EM22/EM28/EM38.)
#
# ***CORRECAO (envelope que SE ADAPTA):*** os candidatos de cada objeto saem da
# GEOMETRIA, nao da classificacao model-space. Para cada objeto montamos o HISTOGRAMA
# do osso de SEGMENTO mais proximo dos seus vertices (posados na bind) e mantemos como
# candidatos so os ossos REALMENTE tocados (>= limiar de verts). Um objeto 1:1 limpo
# (zumbi) toca so o proprio osso -> candidato unico -> RIGIDO (identico ao obj->osso).
# Um objeto multi-osso (hunter/deimos/nemesis, cuja geometria esta assada sobre 2+
# ossos ou ate sobre um osso VIZINHO por causa dos ossos-marcador de 3 verts) toca
# varios -> envelope real. Depois cada vertice pesa nos 2 segmentos mais proximos do
# proprio conjunto de candidatos. Selecao final por MODELO via vao (nunca regride: o
# envelope so e' aceito se BAIXA o vao de A=obj->osso por margem; zumbi tem A=0,000
# imbativel -> fica em A).
def _bone_seg_posed(b, tg, children, parent, nb):
    """Segmento (start,end) do osso b em ESPACO glTF POSADO (junta da bind = tg): do seu
    tg ao tg do 1o filho; se for PONTA, extrapola a direcao do pai. Igual ao _bone_seg da
    Jill, mas sobre as juntas POSADAS (com rotacao de bind) em vez do world so-translacao —
    imprescindivel nos esqueletos de inimigo, cuja bind e' rotacionada (world != junta posada)."""
    start = tg[b]
    kids = [c for c in children[b] if 0 <= c < nb]
    if kids:
        end = tg[kids[0]]
    else:
        p = parent[b]
        if 0 <= p < nb:
            end = (2 * start[0] - tg[p][0], 2 * start[1] - tg[p][1], 2 * start[2] - tg[p][2])
        else:
            end = (start[0], start[1] + 1.0, start[2])
    return start, end


def _seg_dist_g(p, a, b):
    """Distancia do ponto p ao SEGMENTO [a,b] (espaco glTF). = pld2gltf._seg_dist."""
    ax, ay, az = a; bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    l2 = dx * dx + dy * dy + dz * dz
    if l2 < 1e-12:
        t = 0.0
    else:
        t = ((p[0] - ax) * dx + (p[1] - ay) * dy + (p[2] - az) * dz) / l2
        t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    cx, cy, cz = ax + dx * t, ay + dy * t, az + dz * t
    return ((p[0] - cx) ** 2 + (p[1] - cy) ** 2 + (p[2] - cz) ** 2) ** 0.5


def envelope_weights(P_, vert_obj, own_bone, emr, tg, thr=None):
    """Envelope adaptativo -> (J, W) por vertice (ate 2 ossos). P_ = posicoes posadas glTF;
    vert_obj[gi] = indice do objeto de origem; own_bone[oi] = osso-raiz do objeto oi.

    DUAS regras que evitam a RACHADURA (o `assemble` cru e o nearest-joint RASGAM a malha:
    baixam o vao mas dividem um objeto entre ossos que se AFASTAM -> as faces esticam):

      1) POR-OBJETO, RE-ANCORAGEM RiGIDA: cada objeto e' re-atribuido ao osso cuja regiao
         de SEGMENTO a sua geometria REALMENTE ocupa (moda do histograma de segmento mais
         proximo). Isso conserta o "objeto no osso errado" (obj i cuja geometria esta assada
         sobre um osso-marcador/vizinho) SEM rachar: o objeto inteiro anda rigido com 1 osso.

      2) BLEND So ENTRE OSSOS ADJACENTES (pai/filho) = uma JUNTA REAL. Um vertice so ganha
         peso num 2o osso se esse osso for pai/filho do seu osso dominante (a dobra do
         cotovelo/joelho/etc). NUNCA mistura ossos nao-ligados (que rasgariam). Fora da
         faixa fina da junta -> rigido puro. e' o envelope da Jill, mas com o vinculo
         topologico que os esqueletos de inimigo (cheios de ossos-marcador) exigem.

    Params (env, em ESPACO glTF-metros: corpo ~2 m, ossos ~0,2-0,4 m):
      EMD_ENV_POWER  expoente 1/dist^POWER (maior = faixa de blend mais estreita)  default 6.0
      EMD_ENV_EPS    epsilon de distancia (m) p/ nao estourar na junta             default 0.015
      EMD_ENV_MINW   peso min. do 2o osso; abaixo disso -> rigido puro              default 0.10
      EMD_ENV_THR    fracao de verts p/ um osso ser "significativo" no objeto       default 0.05
    """
    nb = emr["nb"]; parent = emr["parent"]; children = emr["children"]
    POW = float(os.environ.get("EMD_ENV_POWER", "6.0"))
    EPS = float(os.environ.get("EMD_ENV_EPS", "0.015"))
    MINW = float(os.environ.get("EMD_ENV_MINW", "0.10"))
    THR = float(os.environ.get("EMD_ENV_THR", "0.05")) if thr is None else thr
    segs = [_bone_seg_posed(b, tg, children, parent, nb) for b in range(nb)]

    def adj(a, b):                                     # a e b sao pai/filho? (junta real)
        return 0 <= a < nb and 0 <= b < nb and (parent[a] == b or parent[b] == a)

    from collections import defaultdict, Counter
    obj_gis = defaultdict(list)
    for gi, oi in enumerate(vert_obj):
        obj_gis[oi].append(gi)

    J = [[0, 0, 0, 0] for _ in P_]
    W = [[1.0, 0.0, 0.0, 0.0] for _ in P_]
    for oi, gis in obj_gis.items():
        own = own_bone[oi]
        nv = len(gis)
        # distancia de cada vertice a CADA osso + histograma do osso mais proximo (segmento)
        vdist = {}
        hist = Counter()
        for gi in gis:
            p = P_[gi]
            dl = [_seg_dist_g(p, segs[b][0], segs[b][1]) for b in range(nb)]
            vdist[gi] = dl
            hist[min(range(nb), key=lambda b: dl[b])] += 1
        # EXTRAS (oi>=nb: acessorios sem osso proprio no formato) -> rigidos ao osso da
        # regiao que ocupam (moda do histograma). Nunca blendam: evita espinho/pico solto.
        if oi >= nb:
            anchor = hist.most_common(1)[0][0] if hist else max(0, min(own, nb - 1))
            for gi in gis:
                J[gi] = [anchor, 0, 0, 0]; W[gi] = [1.0, 0.0, 0.0, 0.0]
            continue
        thr = max(2, int(round(THR * nv)))
        # ossos SIGNIFICATIVOS do objeto (regiao realmente ocupada). Sempre >=1.
        S = set(b for b, c in hist.items() if c >= thr)
        if not S:
            S = {hist.most_common(1)[0][0]} if hist else {max(0, min(own, nb - 1))}
        # PODA p/ o COMPONENTE CONECTADO (pai/filho) que contem a ANCORA (moda do
        # histograma). Um objeto so pode abranger uma CADEIA REAL de ossos ligados; hits
        # esparsos num osso DISTANTE (marcador cuja ponta extrapolada varre a peca) sao
        # descartados -> a peca nunca e' dividida atraves do corpo (evita a rachadura).
        anchor = hist.most_common(1)[0][0] if hist else next(iter(S))
        comp = set([anchor]); stack = [anchor]
        while stack:
            x = stack.pop()
            for b in S:
                if b not in comp and adj(b, x):
                    comp.add(b); stack.append(b)
        S = comp
        for gi in gis:
            dl = vdist[gi]
            # osso dominante = o significativo de segmento mais proximo (re-ancoragem rigida)
            b0 = min(S, key=lambda b: dl[b])
            # 2o osso: so um ADJACENTE (pai/filho) a b0 e significativo (junta real)
            adjS = [b for b in S if b != b0 and adj(b, b0)]
            if not adjS:
                J[gi] = [b0, 0, 0, 0]; W[gi] = [1.0, 0.0, 0.0, 0.0]
                continue
            b1 = min(adjS, key=lambda b: dl[b])
            w0 = 1.0 / ((dl[b0] + EPS) ** POW)
            w1 = 1.0 / ((dl[b1] + EPS) ** POW)
            s = w0 + w1; w0 /= s; w1 /= s
            if w1 < MINW:
                J[gi] = [b0, 0, 0, 0]; W[gi] = [1.0, 0.0, 0.0, 0.0]
            else:
                J[gi] = [b0, b1, 0, 0]; W[gi] = [w0, w1, 0.0, 0.0]
    return J, W


def cpu_anim_check(P_, J_, W_, vert_obj, emr, Rg, tg, clips, fracs=(0.0, 0.25, 0.5, 0.75)):
    """Checagem HONESTA em CPU do skin ANIMADO (o vao do rig_check em REPOUSO engana:
    um modelo pode dar vao baixo e mesmo assim RACHAR ao animar). Roda a MESMA conta do
    GPU/Godot (skin = global_pose(osso) . bind^-1) sobre o 1o clip em varias fracoes e mede:

      * TEAR (rachadura): p/ cada OBJETO original (peca autorada contigua), quanto a sua
        diagonal de bounding-box CRESCE vs repouso. Objeto rigido num osso -> ~1,00. Objeto
        cujos verts foram divididos entre ossos que se AFASTAM -> >>1,00 = malha rasgando.
        e' o sinal direto de "as partes nao seguem o esqueleto".
      * OUTSIDE (malha-fora-do-osso): fracao de verts cujo resultado misturado se afasta
        > 5 cm do que o osso DOMINANTE daria sozinho (rigido). Mede quanto peso "puxa" de
        um osso distante. Pequeno nas juntas e' esperado; grande = vertice solto.

    Retorna dict com numeros crus (nada de mascarar)."""
    if not clips:
        return None
    nb = emr["nb"]; parent = emr["parent"]; nt = emr["node_translation"]
    SCALE = P.SCALE
    root = [j for j in range(nb) if parent[j] < 0][0]

    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)

    RgT = [_mt(Rg[b]) for b in range(nb)]             # bind^-1 rotacao

    def skinpos(b, p, Rgf, tgf):                       # global_pose(b) . bind^-1 . p
        loc = _mv(RgT[b], (p[0] - tg[b][0], p[1] - tg[b][1], p[2] - tg[b][2]))
        g = _mv(Rgf[b], loc)
        return (g[0] + tgf[b][0], g[1] + tgf[b][1], g[2] + tgf[b][2])

    clip = clips[0]
    npose = len(clip["times"])
    # diagonal do corpo em repouso (normalizador) + diag por objeto em repouso
    from collections import defaultdict
    obj_gis = defaultdict(list)
    for gi, oi in enumerate(vert_obj):
        obj_gis[oi].append(gi)

    def diag(gis, pts):
        mn = [min(pts[g][k] for g in gis) for k in range(3)]
        mx = [max(pts[g][k] for g in gis) for k in range(3)]
        return sum((mx[k] - mn[k]) ** 2 for k in range(3)) ** 0.5

    rest_diag = {oi: max(1e-4, diag(gis, P_)) for oi, gis in obj_gis.items() if gis}
    body_mn = [min(p[k] for p in P_) for k in range(3)]
    body_mx = [max(p[k] for p in P_) for k in range(3)]
    body_diag = max(1e-3, sum((body_mx[k] - body_mn[k]) ** 2 for k in range(3)) ** 0.5)

    worst_tear = 1.0; worst_obj = -1; worst_frac = 0.0
    outside_cnt = 0; outside_tot = 0; outside_max = 0.0
    for fr in fracs:
        idx = int(round(fr * (npose - 1)))
        # FK do frame: R,t globais por osso
        Rgf = [None] * nb; tgf = [None] * nb; done = [False] * nb; guard = 0
        while not all(done) and guard < nb * nb + 8:
            guard += 1
            for j in range(nb):
                if done[j]:
                    continue
                p = parent[j]
                if p >= 0 and not done[p]:
                    continue
                Rl = _qm(clip["rot"][j][idx])
                if p < 0:
                    Rgf[j] = Rl; tgf[j] = clip["roottr"][idx]
                else:
                    Rgf[j] = _mm(Rgf[p], Rl)
                    tl = cvt(nt[j]); rp = _mv(Rgf[p], tl)
                    tgf[j] = (tgf[p][0] + rp[0], tgf[p][1] + rp[1], tgf[p][2] + rp[2])
                done[j] = True
        for j in range(nb):
            if not done[j]:
                Rgf[j] = [1, 0, 0, 0, 1, 0, 0, 0, 1]; tgf[j] = cvt(nt[j])
        # posicao skinada (blend) por vertice + comparacao com o osso dominante
        skinned = [None] * len(P_)
        for gi, p in enumerate(P_):
            js = J_[gi]; ws = W_[gi]
            sp = skinpos(js[0], p, Rgf, tgf)
            if ws[1] > 1e-6:
                sp2 = skinpos(js[1], p, Rgf, tgf)
                w0, w1 = ws[0], ws[1]
                sp = (sp[0] * w0 + sp2[0] * w1, sp[1] * w0 + sp2[1] * w1, sp[2] * w0 + sp2[2] * w1)
                dom = js[0] if w0 >= w1 else js[1]
                rp = skinpos(dom, p, Rgf, tgf)
                dd = ((sp[0] - rp[0]) ** 2 + (sp[1] - rp[1]) ** 2 + (sp[2] - rp[2]) ** 2) ** 0.5
                outside_tot += 1
                if dd > 0.05:
                    outside_cnt += 1
                if dd > outside_max:
                    outside_max = dd
            skinned[gi] = sp
        for oi, gis in obj_gis.items():
            if len(gis) < 2:
                continue
            dg = diag(gis, skinned) / rest_diag[oi]
            if dg > worst_tear:
                worst_tear = dg; worst_obj = oi; worst_frac = fr
    return dict(tear=worst_tear, tear_obj=worst_obj, tear_frac=worst_frac,
                outside_frac=(outside_cnt / outside_tot if outside_tot else 0.0),
                outside_max=outside_max, body_diag=body_diag)


def build_arrays(objs, emr, atlas_w, atlas_h, band_h, npal, Rg=None, tg=None, skin_tbl=None):
    """Skinning rigido. POSICOES JA EM ESPACO glTF (modelo). Duas atribuicoes osso->vertice
    sao computadas e a de MENOR VAO (metrica do rig_check) e' escolhida POR MODELO:

    (A) POSICIONAL 1:1  (obj i <-> osso i; extras -> junta mais proxima). Prova reevengi;
        e' o mapa REAL para zumbis/humanos-15-ossos (vao ~0,000) e nunca e' regredido.
    (B) NEAREST-JOINT por-VERTICE (cada vertice -> osso da junta POSADA mais proxima). E' um
        AUTO-SKIN HEURISTICO que APROXIMA o binding osso-por-primitiva do PS1 (perdido no EMD
        standalone do PC — ver docs/decomp/notes/emd_skinning.md sec.10). Nas criaturas multi-
        osso (hunters/deimos/nemesis/vermes) e nos humanos NPC o PC-EMD amontoa a geometria de
        varios ossos num so objeto (com ossos-marcador degenerados de ~3 verts no meio), o que
        deixa a malha do osso real "descolada" do pai degenerado. Redistribuir por junta mais
        proxima re-liga (vao 0,18 -> ~0,04-0,10). NAO e' o indice real do PS1 (irrecuperavel do
        PC-EMD: geometria in-RAM do PS1 nao decodificada e estrutura de objetos nao-alinhada,
        ver enemy_mesh.md sec.4) — e' a melhor aproximacao deterministica.

    A POSICAO/normal de cada vertice sao IDENTICAS em (A) e (B): so muda o OSSO que dirige o
    vertice (peso), logo o repouso e' visualmente inalterado; muda a animacao e o agrupamento.
    Escolha auto-guardada: usa (B) so quando o vao de (B) < vao de (A) - 0,02 E o esqueleto
    tem juntas espalhadas (nao e' o fallback colapsado na origem). MODEL-SPACE (_is_model_space)
    segue igual: parte cujo centroide ja coincide com a junta nao leva a matriz do osso."""
    SCALE = P.SCALE
    nb = emr["nb"]
    if Rg is None:                                    # fallback: sem rotacao (so translacao)
        Rg, tg = gbind(emr, None)

    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)

    def cvtn(nn):
        return (nn[0], -nn[1], -nn[2])

    def _centroid_gltf(ob):
        vs = ob["verts"]; n = max(1, len(vs))
        cx = sum(v[0] for v in vs) / n; cy = sum(v[1] for v in vs) / n; cz = sum(v[2] for v in vs) / n
        return (cx * SCALE, -cy * SCALE, -cz * SCALE)

    def _nearest_bone(cg):
        best = nb - 1; bd = 1e30
        for b in range(nb):
            tb = tg[b]
            dd = (cg[0] - tb[0]) ** 2 + (cg[1] - tb[1]) ** 2 + (cg[2] - tb[2]) ** 2
            if dd < bd:
                bd = dd; best = b
        return best

    # --- EXTRAS (i >= nb): objetos acessorios que o formato NAO amarra a osso nenhum -----
    # (arma/item na mao dos NPC, casaco e tampas de junta do Nemesis, espinhos). A bitmask do
    # dir[0] so cobre bits < nb, entao aqui NAO ha dado: e' o buraco real do formato (§12.4).
    # O que da p/ decidir por GEOMETRIA, sem inventar:
    #
    #  1) ESPACO: no eixo de MAIOR extensao do extra, onde cai a origem local?
    #       origem numa PONTA (t<0.25 ou t>0.75) -> BONE-LOCAL: e' um acessorio PENDURADO na
    #         junta (arma do EM50 t=0,00; rifle do EM51 t=0,15; espinhos do EM36 t=0,06).
    #       origem no MEIO (0,25<=t<=0,75) -> MODEL-SPACE: e' uma peca de CORPO centrada na
    #         propria origem (obj17 do EM34/EM35, t=0,53/0,59 — 1,9 m de altura; asa/manto).
    #     ***Tratar TODO extra como model-space punha a ARMA no meio das PERNAS*** (centroide
    #     ~(50,196,9) mm cai no quadril e a junta mais proxima e' a raiz). E tratar todo extra
    #     como bone-local punha o obj17 do EM34 atravessado no corpo (a "barra listrada").
    #     ***ANTES todo extra era tratado como model-space -> a ARMA ficava no meio das PERNAS***
    #     (centroide ~(50,196,9) mm cai no quadril, e a junta mais proxima e' a raiz).
    #  2) OSSO: o extra bone-local vai no osso que faz a peca ENCOSTAR no corpo. Medido no
    #     EM50: osso4 (mao esq) 0 mm e osso7 (mao dir) 21 mm de distancia da malha, contra
    #     >=24 mm em todos os outros; no EM51, 8 mm e 13 mm. Ou seja, a geometria diz "mao".
    #     ESQUERDA vs DIREITA e' IRRECUPERAVEL do arquivo (o corpo e' simetrico e o empate
    #     fica em poucos mm) — fica com o menor indice e esta' documentado.
    def _is_variant_copy(i):
        """EXTRA que e' VARIANTE de uma peca do corpo (a engine desenha uma OU outra, nunca
        as duas). Detecta por: mesma CONTAGEM de vertices e bbox igual a <5%.
        ***ISTO CONSERTA A "CABECA NO BRACO" do EM36/EM3A***: obj22 tem 78 verts e bbox
        428x438x310 contra 430x442x310 do obj2 (a CABECA) — e' uma 2a cabeca (outro estado
        de dano), que ia para o osso da mao. Varrido nos 69 EMD, a regra pega EXATAMENTE 4
        casos: EM36/EM3A obj22 (~obj2, difere 0,9%) e obj23 (~obj4, difere 0,4%)."""
        vs = objs[i]["verts"]
        if len(vs) < 4:
            return False
        ei = [max(v[k] for v in vs) - min(v[k] for v in vs) for k in range(3)]
        ci = [sum(v[k] for v in vs) / len(vs) for k in range(3)]
        for j in range(min(nb, len(objs))):
            vj = objs[j]["verts"]
            if len(vj) < 4:
                continue
            ej = [max(v[k] for v in vj) - min(v[k] for v in vj) for k in range(3)]
            cj = [sum(v[k] for v in vj) / len(vj) for k in range(3)]
            db = max(abs(ei[k] - ej[k]) / max(1.0, ej[k]) for k in range(3))
            dv = abs(len(vs) - len(vj)) / max(1, len(vj))
            dc = sum((ci[k] - cj[k]) ** 2 for k in range(3)) ** 0.5
            # (a) MESMA contagem + bbox ~igual  -> EM36/EM3A obj22 (~cabeca) e obj23
            if dv == 0.0 and db < 0.05:
                return True
            # (b) contagem e bbox proximas + MESMO LUGAR -> EM17 obj15 (~torso obj0):
            #     58 vs 56 verts (4%), bbox 8%, centroides a 61 mm
            if dv <= 0.10 and db <= 0.15 and dc <= 0.15 * max(ei):
                return True
        return False

    def _hand_bones():
        """MAOS = ossos-FOLHA fora da linha central e ACIMA dos pes. So hierarquia+juntas:
        folha = sem filhos; descarta a cabeca (|z| ~ 0) e os pes (maior Y, pois +Y = baixo)."""
        kc = [0] * nb
        for b in range(nb):
            p = emr["parent"][b]
            if 0 <= p < nb:
                kc[p] += 1
        wj = emr["world"]
        zmax = max(1.0, max(abs(wj[c][2]) for c in range(nb)))
        off = [b for b in range(nb) if kc[b] == 0 and abs(wj[b][2]) > 0.15 * zmax]
        if len(off) < 2:
            return []
        ymax = max(wj[b][1] for b in off)
        hands = [b for b in off if wj[b][1] < ymax - 0.20 * max(1.0, abs(ymax))]
        return hands if len(hands) >= 2 else []

    def _extra_anchor(ob, body):
        vs = ob["verts"]
        if not vs or not body:
            return _nearest_bone(_centroid_gltf(ob)), True
        mn = [min(v[k] for v in vs) for k in range(3)]
        mx = [max(v[k] for v in vs) for k in range(3)]
        # (1) ESPACO — teste r = |centroide| / maior_extensao:
        #       r < 1  -> a peca ATRAVESSA a propria origem => BONE-LOCAL (pendurada na junta)
        #       r >= 1 -> a peca esta INTEIRA deslocada da origem => MODEL-SPACE (posicao
        #                 autorada absoluta)
        #     Separa limpo em todos os 42 extras dos 69 EMD: armas/bazuca/lancador/espinhos
        #     ficam em r=0,00..0,55 e SO o casaco/tocos do Nemesis (EM38 obj27-30) dao
        #     r=1,65..2,01. Tratar tudo como model-space punha a ARMA NO MEIO DO CORPO;
        #     tratar tudo como bone-local deslocava o casaco do Nemesis do peito para o
        #     quadril (era a regressao de esticao 0,396 -> 0,613 no EM38).
        cen = [sum(v[k] for v in vs) / len(vs) for k in range(3)]
        cmag = sum(x * x for x in cen) ** 0.5
        if cmag >= max(1.0, max(mx[k] - mn[k] for k in range(3))):
            return _nearest_bone(_centroid_gltf(ob)), True
        # (2) OSSO. Peca grande e densa = ARMA -> vai na MAO. As maos sao os ossos-FOLHA
        # fora da linha central e acima dos pes. ESQUERDA x DIREITA nao esta no arquivo:
        # a orientacao (frente = +X, medida pela geometria do pe em EM34/EM50/EM10) da
        # esquerda = EMD z>0, e a escolha da esquerda vem da referencia do JOGO (Nemesis
        # carrega o lanca-rockets na mao esquerda), nao do dado.
        # ARMA = peca DENSA (>=30 verts), com tamanho (>300 mm) e ALONGADA (maior extensao
        # >= 1,7x a do meio). Varrido nos 42 extras dos 69 EMD, isto seleciona EXATAMENTE as
        # armas e nada mais: bazuca do Nemesis (EM34/EM35 obj17, alng 3,4/3,6), pistola
        # (EM50/52/53/56, 1,7-2,0), rifle (EM51/5C/5E, 3,0), lancador (EM5D, 2,8). Fica de
        # fora tampa de junta (alng 1,0), espinho fino de 18 verts (alng 17-23) e os tocos
        # do Nemesis (1,0-1,2).
        e = sorted(mx[k] - mn[k] for k in range(3))
        if len(vs) >= 30 and e[2] > 300.0 and e[2] >= 1.7 * max(1.0, e[1]):
            hands = _hand_bones()
            if hands:
                return max(hands, key=lambda b: emr["world"][b][2]), False
        # Demais acessorios (tampas de junta, espinhos, tocos): osso de menor PENETRACAO.
        # O osso sai de um score de PENETRACAO, nao de "distancia minima": uma peca ATRAVESSADA
        # no corpo tambem tem distancia 0. Score = quantos vertices do extra ficam a menos de
        # TOUCH do corpo. A peca certa so ENCOSTA (poucos verts perto, >=1); a errada
        # atravessa (muitos verts perto). Desempate: menor distancia minima.
        TOUCH = 70.0                                    # mm
        best = None
        for b in range(nb):
            wb = emr["world"][b]
            inside = 0; dmin = 1e30
            for v in vs:
                px, py, pz = v[0] + wb[0], v[1] + wb[1], v[2] + wb[2]
                d2 = min((px - q[0]) ** 2 + (py - q[1]) ** 2 + (pz - q[2]) ** 2 for q in body)
                if d2 < TOUCH * TOUCH:
                    inside += 1
                if d2 < dmin:
                    dmin = d2
            if dmin > (3.0 * TOUCH) ** 2:
                continue                                # nao encosta em nada -> descarta
            key = (inside, dmin)
            if best is None or key < best[0]:
                best = (key, b)
        if best is None:
            return _nearest_bone(_centroid_gltf(ob)), True
        return best[1], False

    # nuvem do CORPO (objetos 0..nb-1 em espaco-modelo, unidades do EMD) p/ o teste acima.
    # Amostrada: o custo e' O(nb x |extra| x |corpo|) e so roda quando existe extra.
    _body_pts = []
    if len(objs) > nb:
        for _i in range(min(nb, len(objs))):
            _w = emr["world"][_i]
            _vv = objs[_i]["verts"]
            for _v in _vv[::max(1, len(_vv) // 24)]:
                _body_pts.append((_v[0] + _w[0], _v[1] + _w[1], _v[2] + _w[2]))

    P_, N_, UV_, JA_, W_, faces = [], [], [], [], [], []
    JB_ = []                                          # atribuicao alternativa (nearest-joint)
    JT_, WT_ = [], []                                 # (D) TABELA REAL do dir[0] (autoritativa)
    tbl_objs = (skin_tbl or {}).get("obj_bones", {})
    parent0 = emr["parent"]
    _SEAM_BLEND = os.environ.get("EMD_SEAM_BLEND", "") not in ("", "0")

    def _adj(a, b):                                   # a e b sao pai/filho? (junta real)
        return 0 <= a < nb and 0 <= b < nb and (parent0[a] == b or parent0[b] == a)

    vert_obj = []                                     # gi -> indice do objeto de origem
    own_bone = []                                     # oi -> osso-raiz do objeto (p/ o envelope)
    for i, ob in enumerate(objs):
        cg = _centroid_gltf(ob)
        tbl_v = tbl_objs.get(i)                       # {vidx: [ossos]} deste objeto, ou None
        if i < nb:
            bone = i                                  # POSICIONAL 1:1 (reevengi)
            # ESPACO DO VERTICE — 100% data-driven, ZERO heuristica:
            # objeto na bitmask do dir[0]  -> ESPACO-MODELO ABSOLUTO (multi-osso)
            # qualquer outro objeto        -> BONE-LOCAL 1:1
            # A bitmask E' a lista dos objetos model-space; se o EMD nem tem a secao,
            # NAO EXISTE objeto model-space nele.
            #
            # ***ISTO CONSERTA "cabeca dentro do peito" e "canela colapsada".*** A antiga
            # heuristica (centroide mais perto da junta posada que da origem) disparava
            # FALSO na CABECA dos zumbis (EM10 obj1: cen (0.16,0.32) vs junta (0.15,0.63)
            # -> dc=0.31 < |cen|=0.35 => "model-space") e nas CANELAS dos zumbis de 11
            # ossos (EM16/EM19/EM1C obj8/obj10). Resultado: a peca ficava na posicao da
            # junta do PAI em vez de descer do proprio osso -> cabeca dentro do torso.
            # O vao do rig_check nao pegava isso porque peca sobreposta nao gera VAO.
            model_space = (tbl_v is not None)
        else:
            if _is_variant_copy(i):                   # 2a cabeca/2o braco = variante de dano
                own_bone.append(nb - 1)
                continue                              # NAO desenha (a engine mostra 1 das 2)
            bone, model_space = _extra_anchor(ob, _body_pts)   # EXTRA (ver _extra_anchor)
        own_bone.append(bone)
        # ossos que a tabela usa NESTE objeto (dominio do fallback limitado acima)
        # candidatos do fallback = ossos que a tabela usa NESTE objeto + a ANCORA (obj i).
        # A ancora entra porque quando um grupo nao decodifica (EM40, cabecalho do 1o grupo),
        # o osso que ficou de fora e' justamente o do proprio objeto.
        tbl_used = sorted({b for bl2 in tbl_v.values() for b in bl2 if b < nb} | {bone}) if tbl_v else []
        vclean = _declaw_outliers(ob["verts"])
        R = Rg[bone]; t = tg[bone]
        cache = {}
        def corner(vl, uv, clut, page):
            key = (vl, uv, clut, page)
            gi = cache.get(key)
            if gi is None:
                gi = len(P_)
                v = cvt(vclean[vl])
                nrm = cvtn(ob["norms"][vl])
                if model_space:
                    pos = v; nn = nrm                 # ja em espaco-modelo glTF
                else:
                    mv = _mv(R, v)
                    pos = (mv[0] + t[0], mv[1] + t[1], mv[2] + t[2])
                    nn = _mv(R, nrm)                  # normal roda com o osso
                P_.append(pos); N_.append(nn)
                UV_.append(uv_to_atlas(page, clut, uv[0], uv[1], atlas_w, atlas_h, band_h, npal))
                JA_.append(bone)
                JB_.append(_nearest_bone(pos))        # (B): junta posada mais proxima do vertice
                W_.append([1.0, 0.0, 0.0, 0.0])
                # (D) TABELA: osso REAL do vertice. RIGIDO por padrao = leitura fiel: no PS1
                # nao existe peso, o vertice de costura e' desenhado 1x por grupo (cada copia
                # rigida no seu osso) e a fenda fica escondida pela sobreposicao. Aqui as
                # copias colapsam num vertice unico, entao usamos o PRIMEIRO osso citado.
                # EMD_SEAM_BLEND=1 divide 50/50 os vertices citados em 2 ossos PAI/FILHO
                # (12,9% do total): junta lisa, porem deforma o objeto (sobe tear).
                bl = tbl_v.get(vl) if tbl_v is not None else None
                if tbl_v is not None and not bl and tbl_used:
                    # vertice do objeto que a tabela NAO cobre (6 objetos em 242: EM40 obj0
                    # e EM64). Nao cai na ancora (que jogaria a peca longe): vai p/ o osso
                    # MAIS PROXIMO ENTRE OS QUE A TABELA JA USA NESTE OBJETO — fallback
                    # limitado, nunca inventa um osso fora do conjunto do dado real.
                    bl = [min(tbl_used, key=lambda b: (pos[0] - tg[b][0]) ** 2
                              + (pos[1] - tg[b][1]) ** 2 + (pos[2] - tg[b][2]) ** 2)]
                if bl:
                    b0 = min(bl[0], nb - 1)
                    b1 = min(bl[1], nb - 1) if len(bl) > 1 else b0
                    if _SEAM_BLEND and b1 != b0 and _adj(b0, b1):
                        JT_.append([b0, b1, 0, 0]); WT_.append([0.5, 0.5, 0.0, 0.0])
                    else:
                        JT_.append([b0, 0, 0, 0]); WT_.append([1.0, 0.0, 0.0, 0.0])
                else:
                    JT_.append([bone, 0, 0, 0]); WT_.append([1.0, 0.0, 0.0, 0.0])
                vert_obj.append(i)
                cache[key] = gi
            return gi
        for prim in ob["prims"]:
            ptype, vi, uv, clut, page = prim
            if ptype == "tri":
                a = corner(vi[0], uv[0], clut, page)
                b = corner(vi[1], uv[1], clut, page)
                c = corner(vi[2], uv[2], clut, page)
                faces.append((a, b, c))
            else:
                a = corner(vi[0], uv[0], clut, page)
                b = corner(vi[1], uv[1], clut, page)
                c = corner(vi[2], uv[2], clut, page)
                e = corner(vi[3], uv[3], clut, page)
                faces.append((a, b, c)); faces.append((b, e, c))

    # (C) ENVELOPE ADAPTATIVO (metodo Jill, candidatos guiados pela geometria) -----------
    parent = emr["parent"]
    spread = max((tg[b][0] ** 2 + tg[b][1] ** 2 + tg[b][2] ** 2) ** 0.5 for b in range(nb)) if nb else 0.0

    def _dom(J, W):                                   # osso dominante (maior peso) por vertice
        out = []
        for js, ws in zip(J, W):
            out.append(js[0] if ws[0] >= ws[1] else js[1])
        return out

    # Nao ha um unico limiar THR (fracao de verts p/ um osso "contar" no objeto) otimo p/
    # todos: baixo ajuda hunters/humanos, alto ajuda deimos/brain-sucker. Como TODA variante
    # do envelope e' tear-safe por construcao (rigido + blend so em juntas de ossos ligados),
    # varremos alguns THR e ficamos com o de MENOR vao por MODELO (auto). EMD_ENV_THR fixa um.
    JC_ = WC_ = None; gapC = 1e9
    if spread > 0.1:
        thr_env = os.environ.get("EMD_ENV_THR")
        thr_list = [float(thr_env)] if thr_env else [0.05, 0.10, 0.15]
        for thr in thr_list:
            jc, wc = envelope_weights(P_, vert_obj, own_bone, emr, tg, thr=thr)
            g = _skin_gap_proxy(P_, _dom(jc, wc), parent, nb)
            if g < gapC:
                gapC = g; JC_, WC_ = jc, wc

    # escolha auto-guardada da atribuicao osso->vertice, por MODELO (nunca regride):
    #   A = obj->osso 1:1 (rigido; e' o certo p/ 15-ossos limpos, vao ~0,000)
    #   B = nearest-joint por-vertice (osso da junta posada mais proxima; rigido)
    #   C = ENVELOPE (2 ossos por segmento; amarra membros multi-osso e SELA as juntas)
    # B/C so entram se BAIXAREM o vao de A por margem (0,02). Empate B~C -> prefere C
    # (envelope: deforma suave nas juntas e nao "racha" o membro). Assim zumbi/cao/corvo/
    # aranha/heli (A=0,000) NUNCA saem de A; hunters/deimos/nemesis/humanos migram p/ C.
    mode = os.environ.get("EMD_SKIN", "auto").lower()
    gapA = _skin_gap_proxy(P_, JA_, parent, nb)
    gapB = _skin_gap_proxy(P_, JB_, parent, nb) if spread > 0.1 else 1e9
    if not JC_:
        gapC = 1e9
    # (D) TABELA dir[0]: e' o DADO REAL do arquivo, nao uma aproximacao -> vence de saida.
    # Nao passa pelo torneio de vao: o vao e' uma PROXY (mede AABB de grupo vs AABB do pai)
    # e nao tem autoridade sobre o dado. Os 28 EMD sem a secao seguem no torneio A/B/C.
    # EMD_SKIN=heur reproduz o comportamento ANTERIOR a' tabela (torneio A/B/C) — usado
    # so p/ medir o antes/depois no rig_check.
    if tbl_objs and mode in ("auto", "tabela", "table"):
        gapD = _skin_gap_proxy(P_, [j[0] for j in JT_], parent, nb)
        build_arrays.last_choice = ("tabela-dir0", gapA, gapB, gapD)
        build_arrays.last_meta = dict(vert_obj=vert_obj, own_bone=own_bone, parent=parent, nb=nb)
        return P_, N_, UV_, [list(j) for j in JT_], [list(w) for w in WT_], faces
    if mode == "obj":
        sel = "A"
    elif mode == "nj":
        sel = "B" if spread > 0.1 else "A"
    elif mode == "env":
        sel = "C" if JC_ else "A"
    else:                                             # auto: A (rigido 1:1) vs C (envelope)
        # B (nearest-joint por-vertice, SEM blend) BAIXA o vao mas RACHA a malha (divide o
        # objeto entre ossos que se afastam; tear 2-3x) -> FORA da escolha automatica; fica so
        # como modo manual de diagnostico. C (envelope) e' tear-safe por construcao (rigido +
        # blend so em juntas de ossos ligados) -> so ele disputa com A. Zumbi & cia: A=0,000
        # imbativel por 0,02 -> ficam rigidos; multi-osso: C baixa o vao sem rachar.
        sel = "C" if (JC_ and gapC < gapA - 0.02) else "A"
    if sel == "C" and JC_:
        J_, W_ = [list(j) for j in JC_], [list(w) for w in WC_]
        label = "envelope"
    elif sel == "B":
        J_ = [[b, 0, 0, 0] for b in JB_]
        label = "nearest-joint"
    else:
        J_ = [[b, 0, 0, 0] for b in JA_]
        label = "obj->bone"
    build_arrays.last_choice = (label, gapA, gapB, gapC)
    build_arrays.last_meta = dict(vert_obj=vert_obj, own_bone=own_bone, parent=parent, nb=nb)
    return P_, N_, UV_, J_, W_, faces


# ---------------------------------------------------------------------------
# Esqueleto + animacoes do PS1 (EMR/EDD ja provados)
# ---------------------------------------------------------------------------
def _fallback_emr(d, skel0):
    """EMR minimo tolerante a hierarquia ciclica/invalida (ex.: EM64). Cada osso na
    origem (world=(0,0,0)) -> malha bone-local fica centrada; sem animacao FK, mas
    exporta a geometria."""
    nb = u16(d, skel0 + 4)
    parent = [-1] + [0] * (nb - 1)
    world = [(0, 0, 0)] * nb
    return dict(nb=nb, frame_size=u16(d, skel0 + 6), relpos=[(0, 0, 0)] * nb,
                node_translation=[[0, 0, 0] for _ in range(nb)], root_offset=(0, 0, 0),
                parent=parent, children=[[] for _ in range(nb)], world=world)


def build_emd_clips(d, emr, skel0, pool_end, edd_off, edd_end):
    """Decodifica poses + sequencias EDD do PROPRIO EMD -> clips p/ o glTF.

    ***CAUSA-RAIZ DO BUG DE ANIMACAO (esqueleto explodindo nos mobs !=15 ossos).***
    O `pld2gltf.build_anim_clips`/`parse_poses` sao GABARITO PROVADO, mas assumem o
    esqueleto HUMANO: pool de poses em `skel0+176` com passo `76B/pose` FIXOS. Isso so
    vale p/ 15 ossos (EM10 zumbi, EM2E, EM2D). Nos demais inimigos o cabecalho do skel
    traz `move_offset` (u16 @skel0+2) e `move_size`/`frame_size` (u16 @skel0+6) DIFERENTES:

        nb=17 (cao)   -> move_off=196 fs=88     nb=20 (aranha/hunter) -> 228 / 100
        nb=21 (deimos)-> move_off=240 fs=104    nb=16 (em35)          -> 184 / 80
        nb=10 (corvo) -> move_off=120 fs=56     nb=15 (humano)        -> 176 / 76

    Lendo com 176/76 fixos, as poses caem no OFFSET ERRADO com PASSO ERRADO -> os
    `s16 root x,y,z` e os 12-bit por-osso viram LIXO (ex.: EM35 root Y=+29440 vs 0 no
    offset certo -> a malha voa ~29 unidades sendo de ~5.6; angulos aleatorios giram os
    membros pra qualquer lado). Como as rotacoes sao limitadas a [0,2pi) o AABB nao
    "estoura" muito (a diagonal e' invariante a translacao), mas a malha DESLIGA e "voa".

    CORRECAO: ler `move_offset` e `frame_size` do CABECALHO do skel (identico ao PS1),
    espelhando o RESTO da matematica do pld2gltf (ordem XYZ, quat conjugado por
    diag(1,-1,-1), root in-place mantendo so o bob Y, continuidade de hemisferio). Assim
    canal->osso, pivô e rotacao-relativa-ao-pai ficam IGUAIS ao gabarito, so que com o
    layout de pose correto p/ QUALQUER numero de ossos."""
    nb = emr["nb"]
    fs = emr["frame_size"]                    # = move_size do cabecalho (u16 @skel0+6)
    move_off = P.u16(d, skel0 + 2)            # inicio do pool de poses (varia por nb)
    pool = skel0 + move_off
    npose = (pool_end - pool) // fs if fs else 0
    if npose <= 0:
        return [], 0

    def read_pose(k):
        o = pool + k * fs
        root = (P.s16(d, o), P.s16(d, o + 2), P.s16(d, o + 4))
        quats = [P._euler_to_quat_gltf(P._get12(d, o + 8, b * 3),
                                       P._get12(d, o + 8, b * 3 + 1),
                                       P._get12(d, o + 8, b * 3 + 2)) for b in range(nb)]
        return root, quats

    seqs, recs, flstart, N = P.parse_edd(d, edd_off, edd_end, npose)
    clips = []
    bind_rot = None                                  # rotacoes da BIND POSE = 1a pose do 1o clip
    FPS = 30.0
    for cm in seqs:
        nfr = cm["nframes"]; foff = cm["foff"]; pstart = cm["pstart"]
        if nfr < 1:
            continue
        frames = [P.u16(d, edd_off + foff + k * 2) for k in range(nfr)]
        idxs = [pstart + (f & 0xFF) for f in frames]
        if any(pi < 0 or pi >= npose for pi in idxs):
            continue                                 # sequencia invalida -> pula
        if bind_rot is None:
            bind_rot = read_pose(idxs[0])[1]         # rest = frame0 da 1a anim (sem "pop")
        times = [k / FPS for k in range(len(idxs))]
        rot = [[] for _ in range(nb)]
        roottr = []
        for pi in idxs:
            root, quats = read_pose(pi)
            for b in range(nb):
                q = quats[b]
                if rot[b]:                           # continuidade de hemisferio (igual pld)
                    p = rot[b][-1]
                    if q[0]*p[0] + q[1]*p[1] + q[2]*p[2] + q[3]*p[3] < 0:
                        q = (-q[0], -q[1], -q[2], -q[3])
                rot[b].append(q)
            roottr.append((0.0, -root[1] * P.SCALE, 0.0))   # in-place (so bob Y)
        clips.append(dict(name=f"anim{cm['index']:02d}", times=times, rot=rot, roottr=roottr))
    return clips, npose, bind_rot


def emd_emr_anims(d):
    """Esqueleto + animacoes do PROPRIO EMD (bank 0). O formato skel/anim do EMD-PC e'
    identico ao PS1: skel_header {relpos_len=hier_off, move_off, count=nb, move_size=fs};
    poses em skel0+move_off (fs B cada); anim0 = mesmo EDD. Reusa parse_emr; decodifica
    os clips com build_emd_clips (que le move_off/fs do cabecalho — ver a nota de causa-raiz
    la; NAO usa o pld build_anim_clips, que fixa 176/76 e so serve p/ 15 ossos).
    ROBUSTO: se a hierarquia for invalida, cai p/ EMR minimo sem animacao."""
    dirn = emd_directory(d)
    skel0 = dirn["skel0"]; anim0 = dirn["anim0"]; anim1 = dirn["anim1"]
    lim = sys.getrecursionlimit()
    try:
        sys.setrecursionlimit(2000)
        emr = P.parse_emr(d, skel0, anim1)
    except (RecursionError, Exception):
        sys.setrecursionlimit(lim)
        return _fallback_emr(d, skel0), [], None
    finally:
        sys.setrecursionlimit(lim)
    # fronteiras robustas: fim do pool de poses e fim do EDD = proximo offset do diretorio
    n = len(d)
    move_off = P.u16(d, skel0 + 2)
    pool = skel0 + move_off
    offs = [v for v in dirn.values() if 0 < v <= n]
    pool_end = min([v for v in offs if v > pool] + [n])
    edd_end = min([v for v in offs if v > anim0] + [n])
    bind_rot = None
    try:
        clips, _, bind_rot = build_emd_clips(d, emr, skel0, pool_end, anim0, edd_end)
    except Exception:
        clips = []
    return emr, clips, bind_rot


def ps1_emr_anims(bin_path, blk_idx):
    r = open(bin_path, "rb").read()
    blk = B.parse_bin(r)[int(blk_idx)]
    b = r[blk["foff"]:blk["foff"] + blk["size"]]
    secs = B.parse_model(b)["secs"]
    emr_off = 12; emr_end = secs[0][1]
    edd_off = secs[1][0]; edd_end = secs[1][1]
    emr = P.parse_emr(b, emr_off, emr_end)
    clips, npose = P.build_anim_clips(b, emr, emr_off, emr_end, edd_off, edd_end)
    bind_rot = clips[0]["rot"] and [clips[0]["rot"][j][0] for j in range(emr["nb"])] if clips else None
    return emr, clips, bind_rot


# ---------------------------------------------------------------------------
# GLB writer proprio do EMD: como o pld2gltf.write_glb, POReM grava a ROTACAO de
# REPOUSO por osso (rest = pose0/bind).  ***RESIDUO (a): rest != bind.***
# O write_glb do pld grava so translacao no node (rotacao = identidade), assumindo
# que a BIND e' a pose identidade (T-pose humana). Para os inimigos a identidade e'
# um "espalhado" incoerente (hunters/deimos) -> o modelo NAO-animado fica descolado.
# A bind real desses modelos e' a POSE 0 (1o frame da 1a anim). Aqui gravamos a
# rotacao de repouso = pose0 por osso: com a malha em bind-identidade (P = vert+world)
# e inverseBind = T(-world), no repouso globalJoint = G0 (FK com pose0) e o vertice
# skinado = G0 * (P - world) = G0 * vert_local = POSE0 coerente. A animacao (rotacoes
# absolutas por frame) fica IDENTICA a antes: Gt * vert_local. So o rest muda.
# ---------------------------------------------------------------------------
def write_glb_emd(path, P_, N_, UV, J, W, faces, emr, atlas_w, atlas_h, atlas_rgb,
                  anim_clips=None, node_rot=None, Rg=None, tg=None, atlas_alpha=None):
    SCALE = P.SCALE
    nb = emr["nb"]
    parent = emr["parent"]; world = emr["world"]
    node_translation = emr["node_translation"]
    if Rg is None:
        Rg, tg = gbind(emr, node_rot)

    def cvt(p):
        return (p[0] * SCALE, -p[1] * SCALE, -p[2] * SCALE)

    positions = list(P_)                              # ja em espaco glTF (build_arrays)
    normals = []
    for (nx, ny, nz) in N_:
        L = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        normals.append((nx / L, ny / L, nz / L))      # ja convertidas p/ glTF

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
    A_POS = add_view(pos_data, 34962)
    accessors.append({"bufferView": A_POS, "componentType": 5126, "count": len(positions),
                      "type": "VEC3", "min": mn, "max": mx})
    A_POS = len(accessors) - 1
    A_NRM = add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962)
    accessors.append({"bufferView": A_NRM, "componentType": 5126, "count": len(normals), "type": "VEC3"})
    A_NRM = len(accessors) - 1
    A_UV = add_view(b"".join(struct.pack("<2f", u, v) for (u, v) in UV), 34962)
    accessors.append({"bufferView": A_UV, "componentType": 5126, "count": len(UV), "type": "VEC2"})
    A_UV = len(accessors) - 1
    A_J = add_view(b"".join(struct.pack("<4B", *js) for js in J), 34962)
    accessors.append({"bufferView": A_J, "componentType": 5121, "count": len(J), "type": "VEC4"})
    A_J = len(accessors) - 1
    A_W = add_view(b"".join(struct.pack("<4f", *ws) for ws in W), 34962)
    accessors.append({"bufferView": A_W, "componentType": 5126, "count": len(W), "type": "VEC4"})
    A_W = len(accessors) - 1
    flat = []
    for f in faces:
        flat += list(f)
    A_IDX = add_view(b"".join(struct.pack("<I", i) for i in flat), 34963)
    accessors.append({"bufferView": A_IDX, "componentType": 5125, "count": len(flat), "type": "SCALAR"})
    A_IDX = len(accessors) - 1
    ibm = b""
    for j in range(nb):
        Rt = _mt(Rg[j])                               # R^T
        ti = _mv(Rt, tg[j]); ti = (-ti[0], -ti[1], -ti[2])   # -R^T t
        # coluna-maior (glTF): col0=(Rt00,Rt10,Rt20,0) ...
        ibm += struct.pack("<16f",
                           Rt[0], Rt[3], Rt[6], 0.0,
                           Rt[1], Rt[4], Rt[7], 0.0,
                           Rt[2], Rt[5], Rt[8], 0.0,
                           ti[0], ti[1], ti[2], 1.0)
    A_IBM = add_view(ibm)
    accessors.append({"bufferView": A_IBM, "componentType": 5126, "count": nb, "type": "MAT4"})
    A_IBM = len(accessors) - 1
    # TEXTURA com ALFA: no GPU do PS1 o texel de cor 15-bit `0x0000` NAO e' desenhado.
    # Sem isso a regiao vazada virava mancha PRETA opaca (EM23: 10,1% dos pixels usam o
    # indice 0, cuja cor de CLUT e' 0x0000). Ver pld2gltf.tim_alpha_atlas.
    if atlas_alpha is not None and len(atlas_alpha) == atlas_w * atlas_h:
        png = P.png_bytes_rgba(atlas_w, atlas_h, atlas_rgb, atlas_alpha)
    else:
        png = P.png_bytes_rgb(atlas_w, atlas_h, atlas_rgb)
    vi_img = add_view(png)

    animations = []
    if anim_clips:
        for clip in anim_clips:
            npose = len(clip["times"])
            vt = add_view(struct.pack("<%df" % npose, *clip["times"]))
            accessors.append({"bufferView": vt, "componentType": 5126, "count": npose,
                              "type": "SCALAR", "min": [clip["times"][0]], "max": [clip["times"][-1]]})
            a_time = len(accessors) - 1
            samplers = []; channels = []
            for b in range(nb):
                vq = add_view(b"".join(struct.pack("<4f", *q) for q in clip["rot"][b]))
                accessors.append({"bufferView": vq, "componentType": 5126, "count": npose, "type": "VEC4"})
                samplers.append({"input": a_time, "output": len(accessors) - 1, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": b, "path": "rotation"}})
            root_b = [j for j in range(nb) if parent[j] < 0][0]
            vtr = add_view(b"".join(struct.pack("<3f", *t) for t in clip["roottr"]))
            accessors.append({"bufferView": vtr, "componentType": 5126, "count": npose, "type": "VEC3"})
            samplers.append({"input": a_time, "output": len(accessors) - 1, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": root_b, "path": "translation"}})
            animations.append({"name": clip["name"], "samplers": samplers, "channels": channels})

    nodes = []
    for j in range(nb):
        rx, ry, rz = cvt(node_translation[j])
        node = {"name": f"bone{j:02d}", "translation": [rx, ry, rz]}
        if node_rot is not None and j < len(node_rot) and node_rot[j] is not None:
            qx, qy, qz, qw = node_rot[j]                 # rest = pose0 (bind) -> residuo (a)
            node["rotation"] = [qx, qy, qz, qw]
        kids = emr["children"][j]
        if kids:
            node["children"] = list(kids)
        nodes.append(node)
    nodes.append({"name": "mesh", "mesh": 0, "skin": 0})
    mesh_node_idx = nb
    roots = [j for j in range(nb) if parent[j] < 0]
    scene_nodes = roots + [mesh_node_idx]

    gltf = {
        "asset": {"version": "2.0", "generator": "emd2gltf (RE3 enemy, rest=pose0)"},
        "scene": 0, "scenes": [{"nodes": scene_nodes}], "nodes": nodes,
        "meshes": [{"primitives": [{
            "attributes": {"POSITION": A_POS, "NORMAL": A_NRM, "TEXCOORD_0": A_UV,
                           "JOINTS_0": A_J, "WEIGHTS_0": A_W}, "indices": A_IDX, "material": 0}]}],
        "skins": [{"inverseBindMatrices": A_IBM, "joints": list(range(nb)), "skeleton": roots[0]}],
        "materials": [{"name": "emd", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0},
            "doubleSided": True,
            # MASK (cutout) e' o casamento certo com o PS1: o texel 0x0000 nao e' desenhado,
            # nao existe alfa parcial. BLEND traria ordenacao/z-fight sem ganho.
            "alphaMode": "MASK", "alphaCutoff": 0.5}],
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"bufferView": vi_img, "mimeType": "image/png"}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "bufferViews": views, "accessors": accessors, "buffers": [{"byteLength": offset}],
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
    return dict(vertices=len(P_), faces=len(faces), bones=nb, tex=(atlas_w, atlas_h))


def convert(emd_path, tim_path, out_glb, ps1_bin=None, ps1_blk=0, preview=None):
    """Converte um .EMD (+ .TIM) do RE3-PC para .glb animado, AUTOSSUFICIENTE
    (esqueleto+anim do proprio EMD). Se ps1_bin for dado, usa o EMR/EDD do PS1."""
    d = open(emd_path, "rb").read()
    objs, count, anom = parse_emd_model(d)
    if anom:
        print("  [anomalias %s] %s" % (os.path.basename(emd_path), "; ".join(anom)))
    t = open(tim_path, "rb").read()
    atlas_w, atlas_h, band_h, npal, atlas = P.parse_tim_atlas(t, 0)
    atlas_a = P.tim_alpha_atlas(t, 0)                  # alfa: cor 0x0000 = nao desenhado
    if ps1_bin:
        emr, clips, bind_rot = ps1_emr_anims(ps1_bin, ps1_blk)
    else:
        emr, clips, bind_rot = emd_emr_anims(d)
    # RIG: skinning por-objeto com 3 atribuicoes auto-guardadas por-modelo (ver build_arrays):
    #   A=obj->osso 1:1 (rigido, certo p/ 15-ossos limpos, vao ~0,00);
    #   B=nearest-joint; C=ENVELOPE (metodo Jill: 2 ossos por segmento, amarra membros multi-osso).
    # C so entra se BAIXA o vao de A por margem -> zumbi/cao/corvo/aranha/heli ficam em A (0,00),
    # hunters/deimos/nemesis/humanos migram p/ C. Regressao do EM10 (assemble cru cascateava a
    # cadeia FK toda pois nenhum obj bone-local era "substancial") consertada: candidatos do
    # envelope vem da GEOMETRIA (ossos realmente tocados), nao da classificacao model-space.
    # TABELA REAL de skinning do proprio arquivo (secao dir[0]); presente em 41/69 EMD —
    # justamente os multi-osso que descolavam. Quando existe, dispensa a heuristica.
    skin_tbl = parse_u0_skin(d, emr["nb"], objs)
    # BIND = TRANSLACAO PURA. A tabela de coordenadas do dir[0] e' exatamente `-world[i]`
    # (relpos acumulado, SEM rotacao) => o inverse bind da engine e' T(-world) e a bind e'
    # T(+world) com rotacao IDENTIDADE. Usar a pose0 como rotacao de repouso (o que se fazia
    # aqui) desalinha a malha do esqueleto: no visualizador o osso aparece num lugar e a
    # peca noutro. Com a bind de translacao a conta fecha com o PS1: no PS1 o vertice e'
    # bone-local e desenhado por M_b = T(relpos).R acumulado; em glTF vira
    # G_b(t) . T(-world_b) . (v + world_b) = M_b . v. EMD_BIND=pose0 volta ao antigo.
    if os.environ.get("EMD_BIND", "trans").lower() != "pose0":
        bind_rot = None
    Rg, tg = gbind(emr, bind_rot)
    Pp, Nn, UV, J, W, faces = build_arrays(objs, emr, atlas_w, atlas_h, band_h, npal, Rg, tg,
                                           skin_tbl=skin_tbl)
    choice = getattr(build_arrays, "last_choice", ("?", 0, 0, 0))
    meta = getattr(build_arrays, "last_meta", {})
    chk = None
    if not os.environ.get("EMD_NO_CHECK") and meta:
        try:
            chk = cpu_anim_check(Pp, J, W, meta["vert_obj"], emr, Rg, tg, clips)
        except Exception as ex:
            chk = {"err": str(ex)[:50]}
    info = write_glb_emd(out_glb, Pp, Nn, UV, J, W, faces, emr,
                         atlas_w, atlas_h, atlas, anim_clips=clips, node_rot=bind_rot, Rg=Rg, tg=tg,
                         atlas_alpha=atlas_a)
    ck = ""
    if chk and "err" not in chk:
        ck = " tear=%.2f(obj%d@%.2f) fora>5cm=%.1f%%(max=%.2fm)" % (
            chk["tear"], chk["tear_obj"], chk["tear_frac"],
            100.0 * chk["outside_frac"], chk["outside_max"])
    print("objs=%d verts=%d faces=%d bones=%d anims=%d tex=%dx%d skin=%s(A=%.3f B=%.3f C=%.3f)%s -> %s"
          % (count, len(Pp), len(faces), emr["nb"], len(clips), atlas_w, atlas_h,
             choice[0], choice[1], choice[2], choice[3], ck, os.path.basename(out_glb)))
    if preview:
        P.render_preview(Pp, UV, faces, atlas_w, atlas_h, atlas, preview)
        print("preview ->", preview)
    return info


def cmd_batch(emd_dir, out_dir, names=None):
    """Converte todos os EM##.EMD de um diretorio (com EM##.TIM ao lado)."""
    import glob
    os.makedirs(out_dir, exist_ok=True)
    names = names or {}
    done, fail = [], []
    for emd in sorted(glob.glob(os.path.join(emd_dir, "EM*.EMD"))):
        base = os.path.splitext(os.path.basename(emd))[0]
        tim = os.path.join(emd_dir, base + ".TIM")
        if not os.path.exists(tim):
            fail.append((base, "sem TIM")); continue
        nm = names.get(base, base.lower())
        out = os.path.join(out_dir, nm + ".glb")
        try:
            convert(emd, tim, out)
            done.append((base, nm))
        except Exception as ex:
            fail.append((base, str(ex)[:60]))
    print("\nOK=%d  FALHA=%d" % (len(done), len(fail)))
    for b, e in fail:
        print("  FALHA %s: %s" % (b, e))
    return done, fail


def cmd_reexport(src="C:/tmp/re3pc_emd", enemy_dir=None, only=None):
    """Re-exporta os 69 .glb de inimigo PRESERVANDO o nome do arquivo existente.
    Itera godot/assets/ENEMY/*.glb, extrai o EM## do nome (curados p/ os que nao tem
    EM## no nome) e converte de src/EM##.EMD + .TIM por cima do proprio .glb.

    only = set opcional de EM## (maiusculo) p/ re-exportar so alguns."""
    import glob, re
    if enemy_dir is None:
        here = os.path.dirname(os.path.abspath(__file__))
        enemy_dir = paths.assets("ENEMY")
    cur = {"zumbi_macho": "EM10", "cao_cerberus": "EM20", "corvo": "EM21", "aranha": "EM25"}
    done, fail = [], []
    for glb in sorted(glob.glob(os.path.join(enemy_dir, "*.glb"))):
        nm = os.path.splitext(os.path.basename(glb))[0]
        low = nm.lower()
        em = cur.get(low)
        if em is None:
            m = re.search(r"em([0-9a-f]{2})", low)
            if not m:
                fail.append((nm, "sem EM## no nome")); continue
            em = "EM" + m.group(1).upper()
        if only and em not in only:
            continue
        emd = os.path.join(src, em + ".EMD"); tim = os.path.join(src, em + ".TIM")
        if not (os.path.exists(emd) and os.path.exists(tim)):
            fail.append((nm, "sem %s.EMD/.TIM" % em)); continue
        try:
            print("[%s <- %s] " % (nm, em), end="")
            convert(emd, tim, glb)
            done.append((nm, em))
        except Exception as ex:
            import traceback; traceback.print_exc()
            fail.append((nm, "%s: %s" % (em, str(ex)[:60])))
    print("\nRE-EXPORT OK=%d  FALHA=%d" % (len(done), len(fail)))
    for b, e in fail:
        print("  FALHA %s: %s" % (b, e))
    return done, fail


def main():
    a = sys.argv[1:]
    if a and a[0] == "reexport":
        only = set(x.upper() for x in a[1:]) or None
        cmd_reexport(only=only)
        return 0
    if a and a[0] == "batch":
        # python emd2gltf.py batch <emd_dir> <out_dir>
        cmd_batch(a[1], a[2])
        return 0
    if len(a) < 3:
        print(__doc__); return 1
    emd, tim, out = a[0], a[1], a[2]
    ps1_bin = None; ps1_blk = 0
    if "--ps1" in a:
        i = a.index("--ps1"); ps1_bin = a[i + 1]; ps1_blk = a[i + 2]
    preview = None
    if "--preview" in a:
        preview = a[a.index("--preview") + 1]
    convert(emd, tim, out, ps1_bin, ps1_blk, preview)
    return 0


if __name__ == "__main__":
    sys.exit(main())
