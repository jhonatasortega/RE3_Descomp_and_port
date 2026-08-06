#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bin2gltf.py - Extrator dos contêineres de sala `STAGE#/R###.BIN` do RE3 (PS1 NTSC-U).

Os R###.BIN sao "pacotes de carregamento de sala": uma lista de blocos que o
loader do RE3 copia para (a) a RAM principal -> MODELOS de criatura/objeto, ou
(b) a VRAM da GPU -> TEXTURAS (fundo, mascaras de profundidade, pele de inimigo).

Este modulo REUTILIZA os decoders de `pld2gltf.py` (EMR/EDD/TIM). Estado atual:
  - Contêiner R###.BIN ....................... DECODIFICADO (validado em 122 salas)
  - Classificacao modelo/textura ............. DECODIFICADO
  - Sub-contêiner do modelo (8 secoes) ....... DECODIFICADO (EMR + EDD localizados)
  - EMR (esqueleto) do inimigo ............... OK (mesmo formato do PLD: nb=15, fs=76)
  - EDD (animacoes) .......................... OK (mesmo formato do PLD)
  - TIM (textura de pele) .................... OK (8bpp+CLUT, reusa parse_tim_atlas)
  - MALHA (secoes 2/4) ....................... PARCIAL - formato proprio, ver docs

Uso:
  python tools/bin2gltf.py info  <R###.BIN>            # manifesto + classificacao
  python tools/bin2gltf.py model <R###.BIN> <idx>      # dump do sub-contêiner do modelo
  python tools/bin2gltf.py mesh  <R###.BIN> [blk]      # decodifica malha (tabelas sec3/sec5)
  python tools/bin2gltf.py tims  <R###.BIN> <outdir>   # exporta TIMs embutidos -> PNG
  python tools/bin2gltf.py catalog [outdir]            # varre TODAS as salas
"""
import os, sys, struct, glob, hashlib, json
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pld2gltf as P

ROOT = os.path.join("extracted", "ntsc-u", "CD_DATA")


def u16(d, o): return struct.unpack_from("<H", d, o)[0]
def u32(d, o): return struct.unpack_from("<I", d, o)[0]
def s16(d, o): return struct.unpack_from("<h", d, o)[0]
def align(x, a): return (x + a - 1) & ~(a - 1)


# ---------------------------------------------------------------------------
# 1) Contêiner R###.BIN
# ---------------------------------------------------------------------------
def parse_bin(d):
    """Retorna lista de blocos: dict(idx, foff, size, tag, kind).
    kind = 'model' (tag 0x80xx/0x81xx = destino RAM) ou 'vram' (textura)."""
    assert u32(d, 0) == len(d), "u32[0] != tamanho do arquivo (nao e R###.BIN)"
    cnt = u32(d, 4)
    off = 8
    pos = 0x800                       # blocos comecam no setor 1, alinhados a 0x800
    blocks = []
    for i in range(cnt):
        size = u32(d, off); tag = u32(d, off + 4); off += 8
        kind = "model" if (tag >> 24) in (0x80, 0x81) else "vram"
        blocks.append(dict(idx=i, foff=pos, size=size, tag=tag, kind=kind))
        pos = align(pos + size, 0x800)
    assert pos == len(d), "blocos nao terminam no EOF"
    return blocks


# ---------------------------------------------------------------------------
# 2) Sub-contêiner de um bloco de MODELO
# ---------------------------------------------------------------------------
def parse_model(b):
    """Um bloco de modelo (destino RAM) e ele mesmo um contêiner com diretorio no
    FIM. Layout:
        +0x00 u32 dir_off
        +0x04 u32 ? (contagem de "grupos" logica)
        +0x08 ... secoes ...
        dir_off: u32 nSecoes(=8) ; u32 off1..off7   (off0 implicito = 0x08)
    Retorna dict com secoes e papeis (emr/edd/mesh)."""
    do = u32(b, 0)
    if not (8 <= do < len(b)):
        return None
    tail = [u32(b, do + k * 4) for k in range((len(b) - do) // 4)]
    if not tail or tail[0] < 2 or tail[0] > 32:
        return None
    nsec = tail[0]
    bounds = [0x08] + tail[1:] + [do]
    if len(bounds) < 3 or any(bounds[i] > bounds[i + 1] for i in range(len(bounds) - 1)):
        return None
    secs = [(bounds[i], bounds[i + 1]) for i in range(len(bounds) - 1)]
    roles = {}
    for i, (s, e) in enumerate(secs):
        # EMR: presente no inicio da secao (com prefixo u32 de 4 bytes: dado em +0x04)
        for base in (s, s + 4):
            hier = u16(b, base); nb = u16(b, base + 4); fs = u16(b, base + 6)
            if 3 <= nb <= 40 and fs in (40, 52, 60, 68, 76, 84, 92, 100) and 8 <= hier < (e - base):
                roles.setdefault("emr", []).append((i, base, nb, fs))
                break
    return dict(nsec=nsec, secs=secs, roles=roles)


# ---------------------------------------------------------------------------
# 3) Export de TIMs embutidos (blocos VRAM que comecam com 0x10 00 00 00)
# ---------------------------------------------------------------------------
def export_tims(d, outdir, prefix=""):
    os.makedirs(outdir, exist_ok=True)
    out = []
    for blk in parse_bin(d):
        b = d[blk["foff"]:blk["foff"] + blk["size"]]
        if b[:4] != b"\x10\x00\x00\x00":
            continue
        try:
            aw, ah, band_h, npal, atlas = P.parse_tim_atlas(b, 0)
        except Exception:
            continue
        h = hashlib.md5(b).hexdigest()[:8]
        name = "%sb%02d_%dx%d_%s.png" % (prefix, blk["idx"], aw, ah, h)
        P.write_png_rgb(os.path.join(outdir, name), aw, ah, atlas)
        out.append((blk["idx"], aw, ah, npal, h))
    return out


# ---------------------------------------------------------------------------
# 2b) MALHA do inimigo (formato in-RAM proprio do RE3, NAO e' o EMD standalone).
#     Ver docs/decomp/notes/enemy_mesh.md. Estado: container + TABELAS de objetos
#     (sec3/sec5) DECODIFICADOS; encoding do payload por-registro (sec2/sec4)
#     PENDENTE (parece bit-packed / GTE). Reusa a spec RE3 do reevengi (emd3.h).
# ---------------------------------------------------------------------------
def parse_mesh_table(seg):
    """Tabela de objetos de malha (sec3 p/ sec2; sec5 p/ sec4).
    Registro de 8B: {u16 count, u16 off_idx(passo 2*count), u16 off_elem(passo count), u16 0}.
    n_obj = off_idx[0]//8 (a tabela termina onde a lista de indices comeca).
    Retorna (n_obj, [dict(count, off_idx, off_elem)], total_elems)."""
    if len(seg) < 8:
        return 0, [], 0
    n_obj = u16(seg, 2) // 8
    if not (1 <= n_obj <= 64) or n_obj * 8 > len(seg):
        return 0, [], 0
    objs = []
    for i in range(n_obj):
        o = i * 8
        objs.append(dict(count=u16(seg, o), off_idx=u16(seg, o + 2),
                         off_elem=u16(seg, o + 4)))
    total = objs[-1]["off_elem"] + objs[-1]["count"] if objs else 0
    return n_obj, objs, total


def parse_mesh_obj0(seg):
    """obj0 'limpo' no inicio de sec2/sec4: header 12B + verts de 6B (s16 x,y,z).
       header: {u16 f0, u16 f1, u16 A=fim_verts, u16 B, u16 nVerts, u16 C}."""
    nV = u16(seg, 8)
    verts = [(s16(seg, 12 + k * 6), s16(seg, 12 + k * 6 + 2), s16(seg, 12 + k * 6 + 4))
             for k in range(nV) if 12 + k * 6 + 6 <= len(seg)]
    return dict(nVerts=nV, verts=verts, hdr=[u16(seg, k * 2) for k in range(6)])


def parse_mesh(b):
    """Decodifica a MALHA de um bloco-modelo. sec2<-sec3 (16 obj, 432 reg 52B),
    sec4<-sec5 (4 obj, 108 reg 32B). Valida payload = obj0 + N*recsize.
    NB: o conteudo de cada registro (posicao/normal) ainda NAO e' decodificado
    (ver docs/decomp/notes/enemy_mesh.md sec.4)."""
    m = parse_model(b)
    if not m or m["nsec"] < 6:
        return None
    out = {"parts": []}
    for pay, tab, recsize in ((2, 3, 52), (4, 5, 32)):
        (ps, pe) = m["secs"][pay]
        (ts, te) = m["secs"][tab]
        pseg = b[ps:pe]; tseg = b[ts:te]
        n_obj, objs, total = parse_mesh_table(tseg)
        obj0 = parse_mesh_obj0(pseg)
        # tamanho do 'obj0 limpo' = onde comeca o stream = payload - total*recsize
        stream_bytes = total * recsize
        hdr_bytes = len(pseg) - stream_bytes
        ok = (total > 0 and 0 < hdr_bytes < len(pseg))
        out["parts"].append(dict(pay=pay, tab=tab, recsize=recsize, n_obj=n_obj,
                                 counts=[o["count"] for o in objs], total=total,
                                 obj0=obj0, hdr_bytes=hdr_bytes, valid=ok))
    return out


def mesh_hash(d):
    """Assinatura de geometria de cada modelo da sala (secoes constantes 2 e 4 do
    sub-contêiner). Serve p/ deduplicar 'qual criatura' entre salas."""
    hs = []
    for blk in parse_bin(d):
        if blk["kind"] != "model":
            continue
        b = d[blk["foff"]:blk["foff"] + blk["size"]]
        m = parse_model(b)
        if not m:
            hs.append(("nofmt", blk["size"])); continue
        parts = b"".join(b[s:e] for i, (s, e) in enumerate(m["secs"]) if i in (2, 4))
        hs.append((hashlib.md5(parts).hexdigest()[:8] if parts else "empty", blk["size"]))
    return hs


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def cmd_info(path):
    d = open(path, "rb").read()
    blocks = parse_bin(d)
    print("%s  (%d bytes, %d blocos)" % (os.path.basename(path), len(d), len(blocks)))
    for blk in blocks:
        b = d[blk["foff"]:blk["foff"] + blk["size"]]
        extra = ""
        if blk["kind"] == "model":
            m = parse_model(b)
            if m:
                emr = m["roles"].get("emr", [])
                extra = "secoes=%d EMR=%s" % (m["nsec"], [(e[0], "nb%d" % e[2]) for e in emr])
        elif b[:4] == b"\x10\x00\x00\x00":
            extra = "TIM"
        print("  blk%-2d foff=0x%06x size=%7d tag=0x%08x %-6s %s"
              % (blk["idx"], blk["foff"], blk["size"], blk["tag"], blk["kind"], extra))


def cmd_model(path, idx):
    d = open(path, "rb").read()
    blk = parse_bin(d)[int(idx)]
    b = d[blk["foff"]:blk["foff"] + blk["size"]]
    m = parse_model(b)
    print("bloco %d tag=0x%08x size=%d -> %s" % (blk["idx"], blk["tag"], blk["size"],
          "modelo" if blk["kind"] == "model" else "vram"))
    if not m:
        print("  (sub-contêiner nao reconhecido)"); return
    print("  nSecoes=%d  papeis=%s" % (m["nsec"], m["roles"]))
    for i, (s, e) in enumerate(m["secs"]):
        print("   sec%d 0x%05x..0x%05x size=%6d  u32=%s" %
              (i, s, e, e - s, " ".join("%08x" % u32(b, s + k * 4) for k in range(4))))


def cmd_mesh(path, idx=0):
    d = open(path, "rb").read()
    blk = parse_bin(d)[int(idx)]
    b = d[blk["foff"]:blk["foff"] + blk["size"]]
    mesh = parse_mesh(b)
    if not mesh:
        print("  (bloco sem malha reconhecida)"); return
    print("%s blk%d  MALHA (formato in-RAM RE3; ver docs/decomp/notes/enemy_mesh.md)"
          % (os.path.basename(path), int(idx)))
    for p in mesh["parts"]:
        print("  payload=sec%d tabela=sec%d recsize=%dB  n_obj=%d total_reg=%d  valido=%s"
              % (p["pay"], p["tab"], p["recsize"], p["n_obj"], p["total"], p["valid"]))
        print("     counts=%s" % p["counts"])
        print("     obj0: nVerts=%d verts[:3]=%s" % (p["obj0"]["nVerts"], p["obj0"]["verts"][:3]))
        print("     stream por-registro: encoding in-RAM empacotado (NAO decodificado)")
    print("  NOTA: a malha decodificavel esta no port de PC (.EMD standalone nos Rofs).")
    print("        Exporte o .glb com tools/emd2gltf.py (ver docs/decomp/notes/enemy_mesh.md).")


def cmd_tims(path, outdir):
    d = open(path, "rb").read()
    got = export_tims(d, outdir, prefix=os.path.splitext(os.path.basename(path))[0] + "_")
    for idx, aw, ah, npal, h in got:
        print("  blk%d  %dx%d  npal=%d  %s" % (idx, aw, ah, npal, h))
    print("%d TIM(s) -> %s" % (len(got), outdir))


def cmd_catalog(outdir=None):
    outdir = outdir or paths.assets("ENEMY")
    os.makedirs(outdir, exist_ok=True)
    rooms = sorted(glob.glob(os.path.join(ROOT, "STAGE*", "R*.BIN")))
    from collections import defaultdict
    byhash = defaultdict(list)
    table = {}
    for p in rooms:
        d = open(p, "rb").read()
        try:
            if u32(d, 0) != len(d):
                continue
            hs = mesh_hash(d)
        except Exception:
            continue
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        table[rel] = hs
        for h, sz in hs:
            byhash[h].append(rel)
    out = {
        "rooms_with_models": sum(1 for v in table.values() if v),
        "distinct_meshes": len(byhash),
        "mesh_to_rooms": {h: sorted(set(v)) for h, v in
                          sorted(byhash.items(), key=lambda kv: -len(set(kv[1])))},
        "room_to_meshes": table,
    }
    jp = os.path.join(outdir, "catalog.json")
    json.dump(out, open(jp, "w"), indent=1)
    print("salas com modelo:", out["rooms_with_models"], " meshes distintas:", out["distinct_meshes"])
    for h, rr in list(out["mesh_to_rooms"].items())[:15]:
        print("  %s : %2d salas : %s" % (h, len(rr), ", ".join(rr[:6]) + (" ..." if len(rr) > 6 else "")))
    print("->", jp)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return 1
    cmd = a[0]
    if cmd == "info":     cmd_info(a[1])
    elif cmd == "model":  cmd_model(a[1], a[2])
    elif cmd == "mesh":   cmd_mesh(a[1], *(a[2:3] or ["0"]))
    elif cmd == "tims":   cmd_tims(a[1], a[2])
    elif cmd == "catalog": cmd_catalog(*(a[1:2] or []))
    else:
        print("comando desconhecido:", cmd); print(__doc__); return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
