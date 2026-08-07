#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Decodificador do formato .ESP (banco de sprites de EFEITO) do RE3 PS1 NTSC-U.

O formato foi recuperado do EXE (SLUS_009.23), nao adivinhado. Enderecos-prova:

  esp_register    0x8001b204   monta a tabela de bancos a partir do arquivo
  esp_init_core   0x8001b08c   carrega ETC/CORE00.ESP (file_index 0x14) em 0x801fc200
  esp_init_room   0x8001b148   registra o ESP da SALA (RDT offset-table 17/18/19)
  esp_spawn       0x8001b484   cria efeito; le o header do banco e a tabela de efeitos
  esp_anim_step   0x8001c168   toca a animacao sobre a "tabela A"
  esp_draw_all    0x80022990   monta os POLY_FT4

LAYOUT DO ARQUIVO (provado; ver docs/decomp/notes/esp_efeitos.md)
-----------------------------------------------------------------
  arquivo+0x00 : lista de TIPOS de banco, 1 byte por banco, terminada por 0xff
                 (maximo 16 bancos; esp_register para no 0xff ou em 16)
  fim-4, fim-8, ... : tabela de OFFSETS, u32, LIDA DE TRAS PARA FRENTE.
                 offset[i] = offset (relativo ao inicio do arquivo) do banco i.
                 (0x8001b24c: `lw v1,(a1)` + `addiu a1,a1,-4`)
                 Para CORE00.ESP o chamador passa `fim_do_arquivo - 4`
                 (0x8001b104..0x8001b12c). Para a sala o ponteiro ja vem
                 apontando a ULTIMA palavra da tabela (RDT offset-table[18]).

  BANCO (em arquivo+offset[i]):
      +0x00 u16 A        numero de entradas da "tabela A" (quadros de animacao)
      +0x02 u16 B        numero de entradas da "tabela B" (retangulos de sprite)
      +0x04 u16 clut     valor de CLUT do GPU do PS1: y=clut>>6, x=(clut&0x3f)*16
      +0x06 u16 tpage    valor de tpage: x=(t&0xf)*64, y=((t>>4)&1)*256,
                         abr=(t>>5)&3, tp=(t>>7)&3   (tp=0 -> 4bpp)
      +0x08            tabela A: A entradas de 8 bytes
                         {u8 b_index, u8 n_prims, u8 ctl_dur, u8 size_texels, u32 0}
                         ctl_dur: 0x00 = mata o efeito
                                  0x01..0xfd = duracao do quadro em ticks de 30 Hz
                                  0xfe = congela no quadro anterior (para de animar)
                                  0xff = volta para a entrada b_index (loop)
      +0x08+A*8        tabela B: B entradas de 4 bytes
                         {u8 u, u8 v, s8 ox, s8 oy}   (u,v em pixels de textura
                          dentro da tpage; ox,oy = pivo, tipico -size/2)
      +0x08+A*8+B*4    tabela de EFEITOS:
                         u16 idx[]  -> indexada por (id>>8)&0xff.
                         registro = tabela_efeitos + idx[e]*4:
                            u32 n_slots
                            repetido n_slots vezes:
                               u32 n_frames
                               n_frames * 36 bytes de "frame record"
                         idx[e] == 0 significa efeito inexistente.

  FRAME RECORD (36 = 0x24 bytes) -> copiado para slot+0x00..0x23 por esp_spawn
      +0x00 u8   handler   indice na tabela de 64 handlers 0x80097bd4
      +0x01 u8   state     estado interno do handler
      +0x04 u16 flags     -> slot+0x24 (bit15 vivo, bit13 desenhar, bit12 semi-transp,
                             bit11 seguir matriz do dono, bit9 quad orientado pela
                             matriz, bit1 integrar fisica, bit0 animar)
      +0x08 u16 scale_x   Q12 (0x1000 = 1.0)
      +0x0a u16 scale_y   Q12
      +0x0c..0x0e s8      aceleracao angular x,y,z
      +0x0f u8   a_start  entrada inicial da tabela A
      +0x10..0x14 u16     velocidade x,y,z
      +0x16 u16  tpage_or -> OR no tpage (bits 5-6 = modo de semi-transparencia)
      +0x2c/+0x2e         sobrescritos pelo argumento `param` de esp_spawn

USO
---
    python tools/esp_decode.py scan                 # CORE00.ESP
    python tools/esp_decode.py scan --room STAGE1/R101
    python tools/esp_decode.py scan --all-rooms     # resumo de tipos por sala
    python tools/esp_decode.py dump port/assets/ESP # PNGs + esp_core00.json
"""
import os
import sys
import json
import glob
import zlib
import struct
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

CORE_ESP = os.path.join(ROOT, "extracted/ntsc-u/CD_DATA/ETC/CORE00.ESP")
CORE_TIM = os.path.join(ROOT, "extracted/ntsc-u/CD_DATA/ETC/CORE00.TIM")
CD_DATA = os.path.join(ROOT, "extracted/ntsc-u/CD_DATA")

MAX_BANKS = 16          # 0x8001b288: `sltiu v0, a3, 0x10`
FRAME_SIZE = 0x24       # 0x8001b810: memcpy(..., 0x24)


# ---------------------------------------------------------------- utilitarios
def u8(b, o):
    return b[o]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def s8(v):
    return v - 256 if v >= 128 else v


def unpack_tpage(t):
    """Decodifica o valor de tpage do GPU do PS1."""
    return {
        "raw": t,
        "vram_x": (t & 0xF) * 64,
        "vram_y": ((t >> 4) & 1) * 256,
        "abr": (t >> 5) & 3,          # 0=B/2+F/2 1=B+F 2=B-F 3=B+F/4
        "tp": (t >> 7) & 3,           # 0=4bpp 1=8bpp 2=16bpp
    }


def unpack_clut(c):
    return {"raw": c, "vram_x": (c & 0x3F) * 16, "vram_y": c >> 6}


ABR_NAME = {0: "B/2+F/2 (50%)", 1: "B+F (aditivo)", 2: "B-F (subtrativo)", 3: "B+F/4"}


# ------------------------------------------------------------------- parser
def parse_esp(data, offtab_last=None):
    """Decodifica um arquivo/bloco ESP.

    `offtab_last` = offset (dentro de `data`) da ULTIMA palavra da tabela de
    offsets, isto e, a palavra que contem offset[0]. Se None assume
    len(data)-4 (como faz esp_init_core para CORE00.ESP).
    """
    if offtab_last is None:
        offtab_last = (len(data) & ~3) - 4

    types = []
    for i in range(MAX_BANKS):
        t = data[i]
        if t == 0xFF:
            break
        types.append(t)

    banks = []
    for i, t in enumerate(types):
        off = u32(data, offtab_last - 4 * i)
        banks.append(parse_bank(data, off, t, i))
    return {"n_banks": len(types), "types": types,
            "offtab_last": offtab_last, "banks": banks}


def parse_bank(data, off, btype, index):
    A = u16(data, off + 0)
    B = u16(data, off + 2)
    clut = u16(data, off + 4)
    tpage = u16(data, off + 6)

    a_off = off + 8
    b_off = a_off + A * 8
    e_off = b_off + B * 4
    # prova de coerencia: esp_register calcula e_off = off + (A*2 + B + 2)*4
    assert e_off == off + (A * 2 + B + 2) * 4, "header incoerente"

    atab = []
    for i in range(A):
        p = a_off + 8 * i
        atab.append({
            "b_index": data[p], "n_prims": data[p + 1],
            "ctl_dur": data[p + 2], "size": data[p + 3],
            "tail": u32(data, p + 4),
        })

    btab = []
    for i in range(B):
        p = b_off + 4 * i
        btab.append({"u": data[p], "v": data[p + 1],
                     "ox": s8(data[p + 2]), "oy": s8(data[p + 3])})

    # tabela de efeitos: nao ha contagem explicita; varremos os u16 enquanto
    # apontarem para dentro do banco. Paramos no primeiro indice cujo registro
    # sairia do arquivo.
    idx = []
    p = e_off
    while p + 2 <= len(data):
        w = u16(data, p)
        if w == 0:
            idx.append(0)
        else:
            rec = e_off + w * 4
            if rec + 4 > len(data):
                break
            idx.append(w)
        p += 2
        # o primeiro registro nao-nulo delimita o fim do array de u16
        nz = [x for x in idx if x]
        if nz and e_off + min(nz) * 4 <= p:
            break

    effects = {}
    for e, w in enumerate(idx):
        if w == 0:
            continue
        try:
            effects[e] = parse_effect(data, e_off + w * 4)
        except Exception as ex:              # noqa: BLE001
            effects[e] = {"erro": str(ex)}

    return {
        "index": index, "type": btype, "offset": off,
        "A": A, "B": B,
        "clut": unpack_clut(clut), "tpage": unpack_tpage(tpage),
        "a_off": a_off, "b_off": b_off, "e_off": e_off,
        "atab": atab, "btab": btab,
        "eff_idx": idx, "effects": effects,
    }


def parse_effect(data, rec):
    n_slots = u32(data, rec)
    if not 1 <= n_slots <= 64:
        raise ValueError("n_slots implausivel: %d" % n_slots)
    p = rec + 4
    slots = []
    for _ in range(n_slots):
        n_frames = u32(data, p)
        p += 4
        if not 1 <= n_frames <= 64:
            raise ValueError("n_frames implausivel: %d" % n_frames)
        frames = []
        for _ in range(n_frames):
            frames.append(parse_frame(data[p:p + FRAME_SIZE]))
            p += FRAME_SIZE
        slots.append({"n_frames": n_frames, "frames": frames})
    return {"rec": rec, "n_slots": n_slots, "slots": slots, "end": p}


def parse_frame(r):
    f = u16(r, 4)
    return {
        "handler": r[0], "state": r[1],
        "flags": f,
        "flag_alive": bool(f & 0x8000), "flag_draw": bool(f & 0x2000),
        "flag_semitrans": bool(f & 0x1000), "flag_follow_mtx": bool(f & 0x0800),
        "flag_mtx_quad": bool(f & 0x0200), "flag_physics": bool(f & 0x0002),
        "flag_anim": bool(f & 0x0001),
        "scale_x": u16(r, 8), "scale_y": u16(r, 0x0A),
        "acc": [s8(r[0x0C]), s8(r[0x0D]), s8(r[0x0E])],
        "a_start": r[0x0F],
        "vel": [u16(r, 0x10), u16(r, 0x12), u16(r, 0x14)],
        "tpage_or": u16(r, 0x16),
        "raw": r.hex(),
    }


# ---------------------------------------------------------------- textura TIM
def load_tim(path):
    """Le um TIM 4bpp com CLUT e devolve (clut_rows, pix_bytes, meta)."""
    d = open(path, "rb").read()
    assert u32(d, 0) == 0x10, "nao e TIM"
    flag = u32(d, 4)
    pmode = flag & 7
    p = 8
    clut = None
    if flag & 8:
        bl = u32(d, p)
        cx, cy, cw, ch = struct.unpack_from("<HHHH", d, p + 4)
        cdata = d[p + 12:p + bl]
        clut = {"x": cx, "y": cy, "w": cw, "h": ch, "data": cdata}
        p += bl
    bl = u32(d, p)
    px, py, pw, ph = struct.unpack_from("<HHHH", d, p + 4)
    pix = d[p + 12:p + bl]
    return clut, {"x": px, "y": py, "w_words": pw, "h": ph, "data": pix,
                  "pmode": pmode}


def bgr555_rgba(v):
    r = ((v & 31) * 255) // 31
    g = (((v >> 5) & 31) * 255) // 31
    b = (((v >> 10) & 31) * 255) // 31
    stp = (v >> 15) & 1
    # No PS1 a cor 0x0000 (preto sem STP) e transparente.
    a = 0 if v == 0 else 255
    return (r, g, b, a, stp)


def clut_row(clut, y):
    """16 cores da linha VRAM `y` do bloco de CLUT."""
    row = y - clut["y"]
    assert 0 <= row < clut["h"], "linha de CLUT %d fora do bloco" % y
    o = row * clut["w"] * 2
    return [u16(clut["data"], o + 2 * i) for i in range(clut["w"])]


def png(path, w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y * w * 4:(y + 1) * w * 4]) for y in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c))
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)


def cut_sprite(pixinfo, clut, tpage, clut_word, u, v, size):
    """Recorta um sprite `size`x`size` 4bpp da imagem do TIM."""
    tp = unpack_tpage(tpage)
    assert tp["tp"] == 0, "esperava 4bpp"
    # x, em pixels de 4bpp, da origem da tpage dentro da imagem do TIM
    page_px = (tp["vram_x"] - pixinfo["x"]) * 4
    page_py = tp["vram_y"] - pixinfo["y"]
    cols = clut_row(clut, unpack_clut(clut_word)["vram_y"])
    stride = pixinfo["w_words"] * 2          # bytes por linha
    out = bytearray()
    for yy in range(size):
        for xx in range(size):
            X = page_px + u + xx
            Y = page_py + v + yy
            byte = pixinfo["data"][Y * stride + (X >> 1)]
            idx = (byte & 0xF) if (X & 1) == 0 else (byte >> 4)
            r, g, b, a, _ = bgr555_rgba(cols[idx])
            out += bytes((r, g, b, a))
    return out


# ------------------------------------------------------------------ salas
def room_esp(ard_path):
    """Extrai (data, offtab_last, vram_blocks) do ESP de uma sala .ARD."""
    import ard_parse as A
    d = open(ard_path, "rb").read()
    _t, _c, bl = A.parse_blocks(d)
    rdt_b = [x for x in bl if x["type"] == 0][0]
    r = d[rdt_b["offset"]:rdt_b["offset"] + rdt_b["length"]]
    off = struct.unpack_from("<22I", r, 8)
    if not off[17]:
        return None
    if u32(r, off[17]) == 0xFFFFFFFF:        # 0x8001b1cc: -1 = sem ESP
        return None
    # esp_register recebe (data = r+off[17], offtab = r+off[18])
    return {"rdt": r, "data_off": off[17], "offtab_off": off[18],
            "vram_off": off[19]}


# -------------------------------------------------------------------- saidas
def show(esp, label):
    print("== %s ==  %d bancos, tipos %s" % (
        label, esp["n_banks"], [hex(t) for t in esp["types"]]))
    for bk in esp["banks"]:
        tp, cl = bk["tpage"], bk["clut"]
        print("  banco %d  tipo 0x%02x  off 0x%05x  A=%d B=%d" % (
            bk["index"], bk["type"], bk["offset"], bk["A"], bk["B"]))
        print("     tpage 0x%04x -> VRAM(%d,%d) abr=%d[%s] bpp=%s   "
              "clut 0x%04x -> VRAM(%d,%d)" % (
                  tp["raw"], tp["vram_x"], tp["vram_y"], tp["abr"],
                  ABR_NAME[tp["abr"]], [4, 8, 16, "?"][tp["tp"]],
                  cl["raw"], cl["vram_x"], cl["vram_y"]))
        for e in sorted(bk["effects"]):
            ef = bk["effects"][e]
            if "erro" in ef:
                print("     efeito 0x%02x: ERRO %s" % (e, ef["erro"]))
                continue
            print("     efeito 0x%02x  rec 0x%05x  n_slots=%d" % (
                e, ef["rec"], ef["n_slots"]))
            for si, sl in enumerate(ef["slots"]):
                for fi, fr in enumerate(sl["frames"]):
                    print("        s%d f%d handler=0x%02x flags=0x%04x "
                          "(draw=%d semi=%d follow=%d mtxquad=%d phys=%d anim=%d) "
                          "esc=(%d,%d) a_start=%d tpage|=0x%04x" % (
                              si, fi, fr["handler"], fr["flags"],
                              fr["flag_draw"], fr["flag_semitrans"],
                              fr["flag_follow_mtx"], fr["flag_mtx_quad"],
                              fr["flag_physics"], fr["flag_anim"],
                              fr["scale_x"], fr["scale_y"], fr["a_start"],
                              fr["tpage_or"]))
                    seq = anim_seq(bk, fr["a_start"])
                    print("           anim: %s" % seq)


def anim_seq(bk, start, limit=64):
    """Percorre a tabela A como esp_anim_step (0x8001c168) e devolve a sequencia."""
    out = []
    i = start
    seen = 0
    while seen < limit:
        if i >= len(bk["atab"]):
            out.append("(fora da tabela A)")
            break
        a = bk["atab"][i]
        c = a["ctl_dur"]
        if c == 0x00:
            out.append("morre")
            break
        if c == 0xFE:
            out.append("congela")
            break
        if c == 0xFF:
            out.append("loop->%d" % a["b_index"])
            break
        out.append("B%d/%dpx/%dt" % (a["b_index"], a["size"], c))
        i += 1
        seen += 1
    return " ".join(out)


def dump(outdir):
    os.makedirs(outdir, exist_ok=True)
    data = open(CORE_ESP, "rb").read()
    esp = parse_esp(data)
    clut, pix = load_tim(CORE_TIM)
    meta = {"_fonte": {"esp": "extracted/ntsc-u/CD_DATA/ETC/CORE00.ESP",
                       "tim": "extracted/ntsc-u/CD_DATA/ETC/CORE00.TIM",
                       "exe": "SLUS_009.23; esp_register 0x8001b204, "
                              "esp_spawn 0x8001b484, esp_draw_all 0x80022990"},
            "tim": {"clut_vram": [clut["x"], clut["y"], clut["w"], clut["h"]],
                    "pix_vram": [pix["x"], pix["y"], pix["w_words"], pix["h"]],
                    "pmode": pix["pmode"]},
            "banks": []}
    npng = 0
    for bk in esp["banks"]:
        bmeta = {k: bk[k] for k in ("index", "type", "offset", "A", "B",
                                   "clut", "tpage", "atab", "btab", "eff_idx")}
        bmeta["effects"] = {str(e): bk["effects"][e] for e in bk["effects"]}
        meta["banks"].append(bmeta)
        # PNGs: para cada entrada da tabela A, e para cada variante de CLUT
        # (clut + variante*0x40, ver esp_spawn 0x8001b57c).
        # 0..3 = as 4 variantes que `(obj_flags & 0x60) << 19` pode gerar;
        # v4 existe porque o handler 0x32 (brilho do item) passa `variante+1`
        # ao filho (0x80021804), logo a faisca usa v1..v4.
        for ai, a in enumerate(bk["atab"]):
            if a["ctl_dur"] in (0x00, 0xFE, 0xFF) or a["size"] == 0:
                continue
            if a["b_index"] >= bk["B"]:
                continue
            b = bk["btab"][a["b_index"]]
            for var in range(5):
                cw = bk["clut"]["raw"] + var * 0x40
                try:
                    rgba = cut_sprite(pix, clut, bk["tpage"]["raw"], cw,
                                      b["u"], b["v"], a["size"])
                except Exception:            # noqa: BLE001
                    continue
                name = "t%02x_A%02d_B%02d_v%d_%dx%d.png" % (
                    bk["type"], ai, a["b_index"], var, a["size"], a["size"])
                png(os.path.join(outdir, name), a["size"], a["size"], rgba)
                npng += 1
    # paletas: dump das 30 linhas de CLUT
    pal = {}
    for row in range(clut["h"]):
        y = clut["y"] + row
        pal[str(y)] = ["#%02x%02x%02x%s" % (bgr555_rgba(c)[0], bgr555_rgba(c)[1],
                                           bgr555_rgba(c)[2],
                                           "" if c else "00")
                       for c in clut_row(clut, y)]
    meta["cluts_por_linha_vram"] = pal
    with open(os.path.join(outdir, "esp_core00.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("%d PNG + esp_core00.json em %s" % (npng, outdir))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["scan", "dump"])
    ap.add_argument("out", nargs="?", default="port/assets/ESP")
    ap.add_argument("--room")
    ap.add_argument("--all-rooms", action="store_true")
    args = ap.parse_args()

    if args.cmd == "dump":
        dump(args.out if args.out else "port/assets/ESP")
        return

    if args.all_rooms:
        for p in sorted(glob.glob(os.path.join(CD_DATA, "STAGE*/R*.ARD"))):
            info = room_esp(p)
            if not info:
                print("%s: sem ESP" % os.path.basename(p))
                continue
            r = info["rdt"]
            sub = r[info["data_off"]:]
            last = info["offtab_off"] - info["data_off"]
            esp = parse_esp(sub, last)
            print("%-10s tipos %s" % (os.path.basename(p),
                                      [hex(t) for t in esp["types"]]))
        return

    if args.room:
        p = os.path.join(CD_DATA, args.room + ".ARD")
        info = room_esp(p)
        if not info:
            print("sem ESP")
            return
        r = info["rdt"]
        sub = r[info["data_off"]:]
        esp = parse_esp(sub, info["offtab_off"] - info["data_off"])
        show(esp, args.room)
        return

    show(parse_esp(open(CORE_ESP, "rb").read()), "ETC/CORE00.ESP")


if __name__ == "__main__":
    main()
