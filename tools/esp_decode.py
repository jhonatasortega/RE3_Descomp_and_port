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

QUEM CRIA OS EFEITOS DA SALA (provado; ver docs/decomp/notes/esp_efeitos.md §11)
--------------------------------------------------------------------------------
  Nao e o carregador da sala: e o **opcode SCD `0x70`**, handler `0x80056004`
  (jump-table `0x8009e0f8` + 0x70*4 = `0x8009e2b8`), 16 bytes, que chama
  `esp_spawn` (`0x8001b484`) direto. Layout lido do handler:

      +0x00 u8  0x70
      +0x01 u8  TIPO do banco     -> id & 0xff          (0x80056074 `lbu v1,1(s0)`)
      +0x02 u8  EFEITO            -> (id >> 8) & 0xff   (0x8005602c/0x80056048)
      +0x03 u8  VARIANTE (nibble) -> (id >> 24) & 0xf   (0x8005603c..0x80056044)
      +0x04 s8  ancora_tipo   } argumentos de `0x80055e38`, que devolve a MATRIX*
      +0x05 s8  ancora_indice }  passada como `a2` de esp_spawn
      +0x06 u16 param_hi      -> slot+0x2e = ESCALA base do sprite
      +0x08 s16 ofs.x   }  SVECTOR passado como `a3` (deslocamento local)
      +0x0a s16 ofs.y   }
      +0x0c s16 ofs.z   }
      +0x0e u16 param_lo      -> slot+0x2c
      (`sw zero,0x10(sp)` = rotacao NULL; `s0 += 0x10` = 16 B de avanco)

  `0x80055e38(ancora_tipo, ancora_indice)`: jump-table de 7 casos em `0x80010bc8`
  quando `ancora_tipo >= 0`, mais um caminho empacotado quando o bit 7 esta ligado.
      caso 0 -> `0x80098970`  = MATRIZ IDENTIDADE COM TRANSLACAO ZERO (lida do EXE:
                 `00 10 00 00 00 00 | 00 00 00 10 00 00 | 00 00 00 00 00 10 |
                  00 00 | 00 00 00 00 00 00 00 00 00 00 00 00`)
                 => com ancora 0 o `ofs` do opcode E A POSICAO ABSOLUTA DE MUNDO.
      caso 1 -> `[0x800ccd94] + 0x20`   (matriz de personagem)
      caso 2 -> `[0x800ccd98] + 0x20`
      caso 3 -> `[0x800ccd9c + i*4] + 0x20`
      caso 4 -> `0x800cea60 + i*0x194 + 0x20`  = matriz do OBJETO DE SALA i
      caso 5 -> retorno tardio (0x80055ffc)    caso 6 -> NULL

USO
---
    python tools/esp_decode.py scan                 # CORE00.ESP
    python tools/esp_decode.py scan --room STAGE1/R101
    python tools/esp_decode.py scan --all-rooms     # resumo de tipos por sala
    python tools/esp_decode.py dump port/assets/ESP # PNGs + esp_core00.json
    python tools/esp_decode.py dump --room STAGE1/R10D    # PNGs dos bancos da SALA
    python tools/esp_decode.py spawns --room STAGE1/R10D  # instancias do opcode 0x70
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
    cols = clut_row(clut, unpack_clut(clut_word)["vram_y"])
    return recortar_sprite(pixinfo, cols, tpage, u, v, size)


def recortar_sprite(pixinfo, cols, tpage, u, v, size):
    """Recorta um sprite `size`x`size` 4bpp de um bloco de VRAM, com as 16 cores dadas."""
    tp = unpack_tpage(tpage)
    assert tp["tp"] == 0, "esperava 4bpp"
    # x, em pixels de 4bpp, da origem da tpage dentro do bloco
    page_px = (tp["vram_x"] - pixinfo["x"]) * 4
    page_py = tp["vram_y"] - pixinfo["y"]
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


def room_vram(rdt, vram_off):
    """Blocos de VRAM que a sala sobe para o ESP: `off[19]` do RDT.

    Formato (esp_init_room 0x8001b1e8 -> 0x8001b2a4, que chama LoadImage 0x8008b2ac):
        u32 n; u32 rel[n];        rel[i] = offset RELATIVO a off[19]
        cada bloco: u16 x, u16 y, u16 w, u16 h, depois w*2*h bytes de pixel
    `x`,`y`,`w` estao em UNIDADES DE 16 BITS de VRAM (como no RECT do LoadImage);
    `h` em linhas. Devolve dicts no mesmo formato que `load_tim` usa em `cut_sprite`.
    """
    n = u32(rdt, vram_off)
    if not 1 <= n <= 32:
        raise ValueError("n de blocos de VRAM implausivel: %d" % n)
    rels = struct.unpack_from("<%dI" % n, rdt, vram_off + 4)
    out = []
    for i, rel in enumerate(rels):
        p = vram_off + rel
        x, y, w, h = struct.unpack_from("<4H", rdt, p)
        out.append({"index": i, "x": x, "y": y, "w_words": w, "h": h,
                    "data": rdt[p + 8:p + 8 + w * 2 * h], "pmode": 0,
                    "rel": rel})
    return out


def bloco_de_pixels(blocos, vram_x, vram_y, largura16, altura):
    """Bloco que contem o retangulo (em unidades de 16 bits) pedido; None se nenhum."""
    for b in blocos:
        if (b["x"] <= vram_x and vram_x + largura16 <= b["x"] + b["w_words"]
                and b["y"] <= vram_y and vram_y + altura <= b["y"] + b["h"]):
            return b
    return None


def linha_clut_vram(blocos, vram_x, vram_y):
    """As 16 cores BGR555 da CLUT que mora em (vram_x, vram_y) da VRAM da sala."""
    b = bloco_de_pixels(blocos, vram_x, vram_y, 16, 1)
    if b is None:
        return None
    o = (vram_y - b["y"]) * b["w_words"] * 2 + (vram_x - b["x"]) * 2
    return [u16(b["data"], o + 2 * i) for i in range(16)]


# ------------------------------------------- quem cria os efeitos: opcode SCD 0x70
OP_ESP_SPAWN = 0x70            # handler 0x80056004, 16 B, chama esp_spawn
OP_GOSUB = 0x19                # handler grava PC = func_offset[byte+1] (desce JA)
OP_EVT_EXEC = (0x03, 0x04)     # inicia OUTRA thread (roda depois, nao aqui)
OP_IF = 0x06                   # if_begin: empilha o alvo do else
OP_ELSE = 0x07
OP_ENDBLOCK = 0x08


def spawns_da_sala(ard_path):
    """Le TODAS as instancias do opcode `0x70` do script da sala.

    Devolve (lista_de_instancias, alcance), onde `alcance[f]` diz como a funcao `f`
    e atingida a partir da funcao 0 (a que o load da sala inicia: `0x80052ad0` passa
    `a0=1, a1=0` para `0x80052478`, e `0x80052af8` roda o loop da VM):
        "init"   = corrente de `gosub` (0x19) desde a f0 -> roda na ENTRADA da sala
        "thread" = alcancada por `evt_exec` (0x03/0x04) -> roda depois, em outra thread
        None     = nao alcancada pelo que este parser ve
    Cada instancia leva `bloco` = profundidade de `if` aberto naquele ponto
    (0 = incondicional dentro da funcao).
    """
    import scd_decode as SCD
    res, _unk, _rdt, _so = SCD.decode_room(ard_path)

    # --- grafo de chamadas: gosub (desce ja) e evt_exec (outra thread) ---
    gosubs = {}
    threads = {}
    for fi, _start, insns, _ok in res:
        gosubs[fi] = []
        threads[fi] = []
        for _rel, op, sz, b in insns:
            if op == OP_GOSUB and sz == 2 and len(b) >= 2:
                gosubs[fi].append(b[1])
            elif op in OP_EVT_EXEC and len(b) >= 4 and b[2] == OP_GOSUB:
                threads[fi].append(b[3])
    alcance = {}
    fila = [(0, "init")]
    while fila:
        f, como = fila.pop(0)
        if f in alcance and (alcance[f] == "init" or como == "thread"):
            continue
        alcance[f] = como
        for g in gosubs.get(f, []):
            fila.append((g, como))
        for g in threads.get(f, []):
            fila.append((g, "thread"))

    saida = []
    for fi, _start, insns, _ok in res:
        prof = 0
        for rel, op, sz, b in insns:
            if op == OP_IF:
                prof += 1
            elif op in (OP_ELSE, OP_ENDBLOCK):
                prof = max(0, prof - 1)
            if op != OP_ESP_SPAWN or sz != 16 or len(b) != 16:
                continue
            saida.append({
                "func": fi, "off": rel, "bloco": prof,
                "alcance": alcance.get(fi),
                "tipo": b[1], "efeito": b[2], "variante": b[3] & 0xF,
                "ancora_tipo": s8(b[4]), "ancora_indice": s8(b[5]),
                "escala": u16(b, 6),
                "pos": list(struct.unpack_from("<3h", b, 8)),
                "param_lo": u16(b, 14),
                "bruto": b.hex(" "),
            })
    return saida, alcance


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


def sequencia_anim(bk, start, limit=64):
    """Igual a `anim_seq`, mas ESTRUTURADO: percorre a tabela A como `esp_anim_step`.

    Devolve {"quadros": [{a, b, px, ticks, ox, oy}], "fim": "loop"|"morre"|"congela",
             "loop_para": int|None, "ticks_total": int}
    """
    quadros = []
    fim = "?"
    loop_para = None
    i = start
    while len(quadros) < limit:
        if i >= len(bk["atab"]):
            fim = "fora-da-tabela-A"
            break
        a = bk["atab"][i]
        c = a["ctl_dur"]
        if c == 0x00:
            fim = "morre"
            break
        if c == 0xFE:
            fim = "congela"
            break
        if c == 0xFF:
            fim = "loop"
            loop_para = a["b_index"]
            break
        b = bk["btab"][a["b_index"]] if a["b_index"] < bk["B"] else {"ox": 0, "oy": 0}
        quadros.append({"a": i, "b": a["b_index"], "px": a["size"], "ticks": c,
                        "ox": b["ox"], "oy": b["oy"], "n_prims": a["n_prims"]})
        i += 1
    return {"quadros": quadros, "fim": fim, "loop_para": loop_para,
            "ticks_total": sum(q["ticks"] for q in quadros)}


NOME_PNG_SALA = "ESP/sala/%s/t%02x_A%02d_B%02d_v%d_%dx%d.png"


def dump_sala(sala, outdir, variantes=4, so_usados=False):
    """Recorta em PNG os quadros dos bancos de ESP de UMA sala.

    Os pixels NAO vem de nenhum TIM: vem dos blocos de VRAM que a propria sala sobe
    (`off[19]` do RDT), que e o que `esp_init_room` manda para o `LoadImage`.
    Com `so_usados` recorta apenas os quadros que as instancias do opcode `0x70` da
    propria sala pedem (banco, efeito e variante) — e o que o port precisa desenhar.
    Devolve o registro de metadados da sala (o que vai para port/data/esp_sala.json).
    """
    ard = os.path.join(CD_DATA, sala + ".ARD")
    info = room_esp(ard)
    if not info:
        return None
    r = info["rdt"]
    sub = r[info["data_off"]:]
    esp = parse_esp(sub, info["offtab_off"] - info["data_off"])
    blocos = room_vram(r, info["vram_off"])
    nome_sala = os.path.basename(sala)
    dstdir = os.path.join(outdir, "sala", nome_sala)
    os.makedirs(dstdir, exist_ok=True)

    inst, _alc = spawns_da_sala(ard)
    reg = {
        "arquivo": sala + ".ARD",
        "tipos": esp["types"],
        "vram": [{"x": b["x"], "y": b["y"], "w16": b["w_words"], "h": b["h"]}
                 for b in blocos],
        "bancos": {},
        "instancias": inst,
        "n_png": 0,
    }
    for bk in esp["banks"]:
        tp, cl = bk["tpage"], bk["clut"]
        # quais (entrada A, variante) as instancias desta sala realmente pedem
        precisa = None
        if so_usados:
            precisa = set()
            for x in inst:
                if x["tipo"] != bk["type"]:
                    continue
                ef = bk["effects"].get(x["efeito"])
                if not ef or "erro" in ef:
                    continue
                for sl in ef["slots"]:
                    for fr in sl["frames"]:
                        if not fr["flag_draw"]:
                            continue
                        for q in sequencia_anim(bk, fr["a_start"])["quadros"]:
                            precisa.add((q["a"], x["variante"]))
        # --- os PNG: um por (entrada da tabela A, variante de CLUT) ---
        feitos = set()
        vars_ok = set()
        for ai, a in enumerate(bk["atab"]):
            if a["ctl_dur"] in (0x00, 0xFE, 0xFF) or a["size"] == 0:
                continue
            if a["b_index"] >= bk["B"]:
                continue
            b = bk["btab"][a["b_index"]]
            # retangulo pedido, em unidades de 16 bits de VRAM (4 texels de 4bpp cada)
            x16 = tp["vram_x"] + (b["u"] >> 2)
            w16 = ((b["u"] & 3) + a["size"] + 3) >> 2
            px = bloco_de_pixels(blocos, x16, tp["vram_y"] + b["v"], w16, a["size"])
            if px is None:
                continue
            for var in range(variantes):
                if precisa is not None and (ai, var) not in precisa:
                    continue
                cw = cl["raw"] + var * 0x40
                cols = linha_clut_vram(blocos, unpack_clut(cw)["vram_x"],
                                       unpack_clut(cw)["vram_y"])
                if cols is None:
                    continue
                chave = (ai, a["b_index"], var, a["size"])
                if chave in feitos:
                    continue
                try:
                    rgba = recortar_sprite(px, cols, tp["raw"], b["u"], b["v"],
                                           a["size"])
                except Exception:                # noqa: BLE001
                    continue
                arq = "t%02x_A%02d_B%02d_v%d_%dx%d.png" % (
                    bk["type"], ai, a["b_index"], var, a["size"], a["size"])
                png(os.path.join(dstdir, arq), a["size"], a["size"], rgba)
                feitos.add(chave)
                vars_ok.add(var)
                reg["n_png"] += 1

        usa_efeito = None
        if so_usados:
            usa_efeito = {x["efeito"] for x in inst if x["tipo"] == bk["type"]}
        efeitos = {}
        for e in sorted(bk["effects"]):
            if usa_efeito is not None and e not in usa_efeito:
                continue
            ef = bk["effects"][e]
            if "erro" in ef:
                efeitos[str(e)] = {"erro": ef["erro"]}
                continue
            slots = []
            for sl in ef["slots"]:
                for fr in sl["frames"]:
                    abr = ((tp["raw"] | fr["tpage_or"]) >> 5) & 3
                    seq = sequencia_anim(bk, fr["a_start"])
                    slots.append({
                        "handler": fr["handler"], "flags": fr["flags"],
                        "desenha": fr["flag_draw"],
                        "semitransp": fr["flag_semitrans"],
                        "segue_matriz": fr["flag_follow_mtx"],
                        "quad_matriz": fr["flag_mtx_quad"],
                        "fisica": fr["flag_physics"], "anima": fr["flag_anim"],
                        "escala_x": fr["scale_x"], "escala_y": fr["scale_y"],
                        "a_start": fr["a_start"],
                        "vel": fr["vel"], "acc": fr["acc"],
                        "tpage_or": fr["tpage_or"], "abr": abr,
                        "aditivo": abr == 1,
                        "anim": seq,
                    })
            efeitos[str(e)] = {"n_slots": ef["n_slots"], "slots": slots}
        reg["bancos"][str(bk["type"])] = {
            "indice": bk["index"], "offset": bk["offset"],
            "A": bk["A"], "B": bk["B"],
            "clut": cl["raw"], "clut_vram": [cl["vram_x"], cl["vram_y"]],
            "tpage": tp["raw"], "tpage_vram": [tp["vram_x"], tp["vram_y"]],
            "abr_banco": tp["abr"],
            "variantes": sorted(vars_ok),
            "efeitos": efeitos,
        }
    return reg


def folha_prova_sala(sala, outdir, cel=60, variante=0):
    """Folha de contato: uma LINHA por banco da sala, uma coluna por quadro do efeito 0.

    Serve de prova visual do que cada banco e (fogo, explosao, faisca...). O fundo e
    escuro e os sprites entram SOMANDO, que e o `abr = 1` da maioria dos efeitos.
    """
    ard = os.path.join(CD_DATA, sala + ".ARD")
    info = room_esp(ard)
    if not info:
        return None
    r = info["rdt"]
    esp = parse_esp(r[info["data_off"]:], info["offtab_off"] - info["data_off"])
    blocos = room_vram(r, info["vram_off"])
    linhas = []
    for bk in esp["banks"]:
        eff = sorted(bk["effects"])
        if not eff:
            continue
        ef = bk["effects"][eff[0]]
        if "erro" in ef or not ef["slots"]:
            continue
        seq = sequencia_anim(bk, ef["slots"][0]["frames"][0]["a_start"])
        if seq["quadros"]:
            linhas.append((bk, seq["quadros"]))
    if not linhas:
        return None
    W = cel * max(len(q) for _, q in linhas)
    H = cel * len(linhas)
    buf = bytearray(W * H * 4)
    for i in range(W * H):
        buf[i * 4:i * 4 + 4] = bytes((24, 24, 32, 255))
    for li, (bk, quadros) in enumerate(linhas):
        tp, cl = bk["tpage"], bk["clut"]
        cw = cl["raw"] + variante * 0x40
        cols = linha_clut_vram(blocos, unpack_clut(cw)["vram_x"],
                               unpack_clut(cw)["vram_y"])
        if cols is None:
            continue
        for ci, q in enumerate(quadros):
            a = bk["atab"][q["a"]]
            b = bk["btab"][a["b_index"]]
            x16 = tp["vram_x"] + (b["u"] >> 2)
            w16 = ((b["u"] & 3) + a["size"] + 3) >> 2
            px = bloco_de_pixels(blocos, x16, tp["vram_y"] + b["v"], w16, a["size"])
            if px is None:
                continue
            rgba = recortar_sprite(px, cols, tp["raw"], b["u"], b["v"], a["size"])
            ox = ci * cel + (cel - a["size"]) // 2
            oy = li * cel + (cel - a["size"]) // 2
            for yy in range(a["size"]):
                for xx in range(a["size"]):
                    s = (yy * a["size"] + xx) * 4
                    if rgba[s + 3] == 0:
                        continue
                    o = ((oy + yy) * W + (ox + xx)) * 4
                    for k in range(3):
                        buf[o + k] = min(255, buf[o + k] + rgba[s + k])
    nome_sala = os.path.basename(sala)
    dstdir = os.path.join(outdir, "sala", nome_sala)
    os.makedirs(dstdir, exist_ok=True)
    caminho = os.path.join(dstdir, "_prova_bancos_v%d.png" % variante)
    png(caminho, W, H, buf)
    return {"caminho": caminho, "linhas": [hex(bk["type"]) for bk, _ in linhas],
            "colunas": [len(q) for _, q in linhas]}


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


JSON_SALA = os.path.join(ROOT, "port", "data", "esp_sala.json")


def salas_com_esp():
    """Nomes 'STAGEn/Rxxx' de todas as salas cujo RDT declara ESP."""
    out = []
    for p in sorted(glob.glob(os.path.join(CD_DATA, "STAGE*/R*.ARD"))):
        if room_esp(p):
            out.append(os.path.relpath(p, CD_DATA).replace("\\", "/")[:-4])
    return out


def gravar_json_sala(regs, caminho=JSON_SALA):
    """Grava port/data/esp_sala.json MESCLANDO com o que ja estava la.

    Assim `dump --all-rooms` (todas as salas, so os quadros usados) e depois
    `dump --room STAGE1/R10D --todos-quadros` (uma sala inteira, para inspecao)
    convivem no mesmo arquivo em vez de um apagar o outro.
    """
    antigas = {}
    if os.path.exists(caminho):
        try:
            with open(caminho, encoding="utf-8") as f:
                antigas = json.load(f).get("salas", {})
        except Exception:                        # noqa: BLE001
            antigas = {}
    antigas.update(regs)
    regs = dict(sorted(antigas.items()))
    meta = {
        "_fonte": {
            "exe": "SLUS_009.23 base 0x80010000",
            "bancos": "RDT off[17] (dados) / off[18] (tabela de offsets, lida de tras "
                      "para frente) / off[19] (blocos de VRAM) — esp_init_room 0x8001b148",
            "instancias": "opcode SCD 0x70, handler 0x80056004 (16 B), que chama "
                          "esp_spawn 0x8001b484; ancora via 0x80055e38",
            "ancora_0": "0x80098970 = matriz identidade com translacao ZERO -> com "
                        "ancora_tipo 0 o campo `pos` do opcode E a posicao de mundo",
            "png": "assets/ESP/sala/<SALA>/t{tipo:02x}_A{a:02d}_B{b:02d}_v{var}_{px}x{px}.png",
            "ticks": "duracao dos quadros em ticks de 30 Hz (tabela A, campo ctl_dur)",
        },
        "salas": regs,
    }
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    return caminho


# ------------------------------------------------- quadros em HD (Seamless HD Project)
#
# O pack HD do PC (Classic REbirth + Seamless HD Project) substitui TEXTURA POR TEXTURA,
# nomeando cada arquivo pelo hash do bloco SD que ele substitui — hash que NAO da para
# reproduzir estaticamente (ver port/data/hd_ui_map.json, campo `meta.hash`). Entao o
# de-para e feito POR CONTEUDO, e aqui ele e barato porque a GEOMETRIA e conhecida:
#
#   • todo asset HD do pack e exatamente 4x o SD (medido em todas as categorias);
#   • hires/effect e hires/effect0 tem 391 arquivos, TODOS 1024x1024 = 4 x 256x256,
#     e 256x256 e exatamente uma TPAGE de 4bpp do PS1 (64 halfwords x 256 linhas);
#   • logo o sprite que mora em (u, v) da tpage mora em (u*4, v*4) do .webp, com lado
#     `size*4` — nao ha busca de posicao, so a escolha do ARQUIVO.
#
# Cada arquivo HD e uma pagina JA COLORIDA (a CLUT foi aplicada), por isso a mesma pagina
# aparece em varios arquivos: um por linha de CLUT em uso. A escolha e em duas etapas:
#   1. FORMA: NCC da luminancia x alfa nos pixels do banco (recorte exato das entradas B
#      que a sala usa). Verdadeiro ~0,999 · segundo colocado <0,75 — separacao enorme.
#   2. COR: entre os empatados na forma, o menor erro RMS de cor contra o sprite SD
#      daquela VARIANTE de CLUT. E isto que separa "a mesma chama na paleta 488" de
#      "na paleta 490".
# NAO ha atribuicao global (Hungarian) aqui de proposito: o pareamento nao e 1:1 — uma
# pagina HD serve MUITAS salas (as 156 salas com ESP compartilham as paginas de efeito),
# entao a restricao de unicidade seria falsa. O que substitui a atribuicao global e o
# vinculo geometrico (u,v)x4, que torna cada par decidivel sozinho com folga medida.
HIRES_DEFAULT = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3\hires"
HIRES_ENV = "NOSTALGIA_HIRES"
HD_PASTAS = ("effect", "effect0")
HD_ESCALA = 4                  # 1024/256: medido em todos os 391 arquivos
HD_LADO_SD = 256               # lado da tpage de 4bpp em pixels
HD_NCC_MIN = 0.95              # verdadeiros >=0.99; o segundo colocado real fica <0.75
JSON_HD = os.path.join(ROOT, "port", "data", "esp_hd_map.json")


def hires_root(arg=None):
    return arg or os.environ.get(HIRES_ENV) or HIRES_DEFAULT


def hd_indexar(raiz):
    """Le hires/effect* e devolve (nomes, paginas_sd) com as paginas reduzidas a 256x256.

    A reducao e por MEDIA (BOX) de blocos 4x4, que e o inverso exato do upscale 4x do
    pack; comparar em SD (e nao em HD) e o que permite casar com os pixels do PS1.
    """
    import numpy as np
    from PIL import Image
    nomes = []
    arqs = []
    for pasta in HD_PASTAS:
        d = os.path.join(raiz, pasta)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.lower().endswith(".webp"):
                nomes.append("%s/%s" % (pasta, os.path.splitext(f)[0]))
                arqs.append(os.path.join(d, f))
    if not nomes:
        raise SystemExit("ERRO: nao achei .webp em %s/{effect,effect0}" % raiz)
    pag = np.zeros((len(nomes), HD_LADO_SD, HD_LADO_SD, 4), dtype=np.uint8)
    for i, p in enumerate(arqs):
        im = Image.open(p).convert("RGBA")
        if im.size != (HD_LADO_SD * HD_ESCALA, HD_LADO_SD * HD_ESCALA):
            im = im.resize((HD_LADO_SD * HD_ESCALA,) * 2, Image.BOX)
        pag[i] = np.asarray(im.resize((HD_LADO_SD, HD_LADO_SD), Image.BOX), dtype=np.uint8)
    return nomes, pag, arqs


def _lum(a):
    """Luminancia x alfa (float32) de um array RGBA — o que se compara na etapa FORMA."""
    return (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) * (a[..., 3] / 255.0)


def hd_quadros_pedidos(bk, inst):
    """{(variante): {entrada_A: (u, v, size)}} que as instancias da sala pedem deste banco."""
    import collections
    out = collections.defaultdict(dict)
    for x in inst:
        if x["tipo"] != bk["type"]:
            continue
        ef = bk["effects"].get(x["efeito"])
        if not ef or "erro" in ef:
            continue
        for sl in ef["slots"]:
            for fr in sl["frames"]:
                if not fr["flag_draw"]:
                    continue
                for q in sequencia_anim(bk, fr["a_start"])["quadros"]:
                    a = bk["atab"][q["a"]]
                    if a["b_index"] >= bk["B"] or a["size"] == 0:
                        continue
                    b = bk["btab"][a["b_index"]]
                    out[x["variante"]][q["a"]] = (b["u"], b["v"], a["size"],
                                                  a["b_index"])
    return out


def hd_sala(sala, outdir, nomes, pag, arqs, verbose=True):
    """Casa e recorta os quadros HD dos bancos de ESP de UMA sala. Devolve o registro."""
    import numpy as np
    from PIL import Image
    ard = os.path.join(CD_DATA, sala + ".ARD")
    info = room_esp(ard)
    if not info:
        return None
    r = info["rdt"]
    esp = parse_esp(r[info["data_off"]:], info["offtab_off"] - info["data_off"])
    blocos = room_vram(r, info["vram_off"])
    inst, _alc = spawns_da_sala(ard)
    nome_sala = os.path.basename(sala)
    dstdir = os.path.join(outdir, "sala", nome_sala, "hd")

    reg = {"arquivo": sala + ".ARD", "bancos": {}, "n_png": 0}
    for bk in esp["banks"]:
        tp, cl = bk["tpage"], bk["clut"]
        if tp["tp"] != 0:
            continue
        pedidos = hd_quadros_pedidos(bk, inst)
        for var in sorted(pedidos):
            quadros = pedidos[var]
            cw = cl["raw"] + var * 0x40
            cols = linha_clut_vram(blocos, unpack_clut(cw)["vram_x"],
                                   unpack_clut(cw)["vram_y"])
            if cols is None:
                continue
            # --- referencia SD: SO os pixels dos quadros pedidos, no espaco da tpage ---
            us = [q[0] for q in quadros.values()]
            vs = [q[1] for q in quadros.values()]
            sz = max(q[2] for q in quadros.values())
            x0, y0 = min(us), min(vs)
            w = max(u + q[2] for u, q in zip(us, quadros.values())) - x0
            h = max(v + q[2] for v, q in zip(vs, quadros.values())) - y0
            if x0 + w > HD_LADO_SD or y0 + h > HD_LADO_SD:
                continue
            sd = np.zeros((h, w, 4), dtype=np.uint8)
            val = np.zeros((h, w), dtype=bool)
            for (u, v, size, _bi) in quadros.values():
                x16 = tp["vram_x"] + (u >> 2)
                w16 = ((u & 3) + size + 3) >> 2
                px = bloco_de_pixels(blocos, x16, tp["vram_y"] + v, w16, size)
                if px is None:
                    continue
                rgba = recortar_sprite(px, cols, tp["raw"], u, v, size)
                sd[v - y0:v - y0 + size, u - x0:u - x0 + size] = np.frombuffer(
                    bytes(rgba), dtype=np.uint8).reshape(size, size, 4)
                val[v - y0:v - y0 + size, u - x0:u - x0 + size] = True
            if not val.any():
                continue
            # --- etapa 1: FORMA (NCC da luminancia) sobre os pixels validos ---
            alvo = _lum(sd.astype(np.float32))[val]
            alvo = alvo - alvo.mean()
            n_alvo = np.linalg.norm(alvo)
            if n_alvo == 0:
                continue
            alvo /= n_alvo
            cand = pag[:, y0:y0 + h, x0:x0 + w, :].astype(np.float32)
            L = _lum(cand)[:, val]
            L -= L.mean(axis=1, keepdims=True)
            nn = np.linalg.norm(L, axis=1)
            nn[nn == 0] = 1.0
            ncc = (L / nn[:, None]) @ alvo
            # --- etapa 2: COR (RMS) entre os que passaram na forma ---
            op = val & (sd[..., 3] > 0)
            sdc = sd[..., :3].astype(np.float32)[op]
            hdc = cand[..., :3][:, op]
            rms = np.sqrt(((hdc - sdc) ** 2).sum(-1)).mean(axis=1)
            aopt = cand[..., 3][:, op] > 8
            iou = (aopt.sum(axis=1) / max(1, int(op.sum())))
            passou = np.where(ncc >= HD_NCC_MIN)[0]
            if passou.size == 0:
                if verbose:
                    print("      banco 0x%02x v%d: SEM par HD (melhor NCC %.3f em %s)" % (
                        bk["type"], var, float(ncc.max()), nomes[int(ncc.argmax())]))
                continue
            j = int(passou[np.argmin(rms[passou])])
            outros = [k for k in passou if k != j]
            reg["bancos"].setdefault(str(bk["type"]), {})["v%d" % var] = {
                "webp": nomes[j], "ncc": round(float(ncc[j]), 4),
                "rms_cor": round(float(rms[j]), 2), "alfa_iou": round(float(iou[j]), 3),
                "empatados_na_forma": len(passou),
                "rms_do_2o": (round(float(min(rms[k] for k in outros)), 2)
                              if outros else None),
                "ncc_do_1o_reprovado": round(float(max(
                    [ncc[k] for k in range(len(nomes)) if k not in set(passou)] or [0.0])), 4),
                "quadros": len(quadros),
            }
            # --- recorte dos quadros do arquivo escolhido, em 4x ---
            os.makedirs(dstdir, exist_ok=True)
            im = Image.open(arqs[j]).convert("RGBA")
            k = im.size[0] // HD_LADO_SD
            for ai, (u, v, size, bi) in sorted(quadros.items()):
                crop = im.crop((u * k, v * k, (u + size) * k, (v + size) * k))
                arq = "t%02x_A%02d_B%02d_v%d_%dx%d.png" % (
                    bk["type"], ai, bi, var, size * k, size * k)
                crop.save(os.path.join(dstdir, arq))
                reg["n_png"] += 1
            if verbose:
                print("      banco 0x%02x v%d -> %s  ncc=%.4f rms=%.1f iou=%.2f "
                      "(%d empatado(s) na forma, melhor reprovado ncc=%.3f)" % (
                          bk["type"], var, nomes[j], ncc[j], rms[j], iou[j],
                          len(passou), reg["bancos"][str(bk["type"])]["v%d" % var]
                          ["ncc_do_1o_reprovado"]))
    return reg


def gravar_json_hd(regs, raiz, caminho=JSON_HD):
    antigas = {}
    if os.path.exists(caminho):
        try:
            with open(caminho, encoding="utf-8") as f:
                antigas = json.load(f).get("salas", {})
        except Exception:                            # noqa: BLE001
            antigas = {}
    antigas.update(regs)
    meta = {
        "_fonte": {
            "hd": "Seamless HD Project / Classic REbirth (%s) — SOMENTE LEITURA, "
                  "assets nao redistribuidos" % raiz,
            "geometria": "todo arquivo de hires/effect* e 1024x1024 = 4x uma TPAGE de "
                         "4bpp (256x256); o sprite em (u,v) da tpage esta em (u*4, v*4)",
            "criterio": "1) NCC de luminancia x alfa nos pixels dos quadros usados "
                        "(>= %.2f); 2) menor RMS de cor entre os empatados, que e o que "
                        "separa as variantes de CLUT da mesma pagina" % HD_NCC_MIN,
            "sem_atribuicao_global": "o pareamento nao e 1:1 (uma pagina HD serve muitas "
                                     "salas), logo unicidade seria uma restricao falsa",
            "png": "assets/ESP/sala/<SALA>/hd/t{tipo:02x}_A{a:02d}_B{b:02d}_v{var}_"
                   "{px}x{px}.png, com px = size*4",
        },
        "salas": dict(sorted(antigas.items())),
    }
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    return caminho


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["scan", "dump", "spawns", "hd"])
    ap.add_argument("out", nargs="?", default="port/assets/ESP")
    ap.add_argument("--room")
    ap.add_argument("--salas", help="lista separada por virgula (STAGE1/R10D,...)")
    ap.add_argument("--all-rooms", action="store_true")
    ap.add_argument("--todos-quadros", action="store_true",
                    help="dump: recorta TODOS os quadros de todos os bancos da sala "
                         "(o padrao com --all-rooms/--salas e so os que o 0x70 pede)")
    ap.add_argument("--folha", action="store_true",
                    help="dump: gera tambem a folha de contato de prova por sala")
    ap.add_argument("--hires", help="hd: raiz da instalacao HD (default %s)" % HIRES_DEFAULT)
    args = ap.parse_args()

    if args.cmd == "hd":
        outdir = args.out if args.out else "port/assets/ESP"
        if not os.path.isabs(outdir):
            outdir = os.path.join(ROOT, outdir)
        alvos = ([args.room] if args.room
                 else (args.salas.split(",") if args.salas else salas_com_esp()))
        raiz = hires_root(args.hires)
        print("hires: %s" % raiz)
        nomes, pag, arqs = hd_indexar(raiz)
        print("%d paginas HD indexadas (%s), reduzidas a %dx%d" % (
            len(nomes), "+".join(HD_PASTAS), HD_LADO_SD, HD_LADO_SD))
        regs = {}
        n = 0
        for sala in alvos:
            print("   %s" % sala)
            reg = hd_sala(sala, outdir, nomes, pag, arqs)
            if reg is None:
                print("      sem ESP")
                continue
            if reg["n_png"] == 0:
                continue
            regs[os.path.basename(sala)] = reg
            n += reg["n_png"]
        print("%d salas com quadro HD · %d PNG · gravado %s" % (
            len(regs), n, os.path.relpath(gravar_json_hd(regs, raiz), ROOT)))
        return

    if args.cmd == "spawns":
        alvos = ([args.room] if args.room
                 else (args.salas.split(",") if args.salas else salas_com_esp()))
        for sala in alvos:
            inst, alc = spawns_da_sala(os.path.join(CD_DATA, sala + ".ARD"))
            print("== %s ==  %d instancias do opcode 0x70" % (sala, len(inst)))
            for x in inst:
                print("   f%-3d +0x%04x bloco=%d %-6s tipo=0x%02x ef=0x%02x var=%d "
                      "ancora=(%d,%d) esc=0x%04x pos=(%d,%d,%d)" % (
                          x["func"], x["off"], x["bloco"], x["alcance"] or "-",
                          x["tipo"], x["efeito"], x["variante"],
                          x["ancora_tipo"], x["ancora_indice"], x["escala"],
                          x["pos"][0], x["pos"][1], x["pos"][2]))
            del alc
        return

    if args.cmd == "dump":
        outdir = args.out if args.out else "port/assets/ESP"
        if not os.path.isabs(outdir):
            outdir = os.path.join(ROOT, outdir)
        if args.room or args.salas or args.all_rooms:
            alvos = ([args.room] if args.room
                     else (args.salas.split(",") if args.salas else salas_com_esp()))
            # uma sala so: dump completo (para inspecao). Muitas: so o que o 0x70 usa.
            so_usados = not args.todos_quadros and len(alvos) > 1
            regs = {}
            n = 0
            for sala in alvos:
                reg = dump_sala(sala, outdir, so_usados=so_usados)
                if reg is None:
                    print("%s: sem ESP" % sala)
                    continue
                regs[os.path.basename(sala)] = reg
                n += reg["n_png"]
                print("%-14s %d bancos · %d PNG · %d instancias 0x70" % (
                    sala, len(reg["bancos"]), reg["n_png"],
                    len(reg["instancias"])))
                if args.folha:
                    f = folha_prova_sala(sala, outdir)
                    if f:
                        print("               folha %s  linhas=%s colunas=%s" % (
                            os.path.relpath(f["caminho"], ROOT), f["linhas"],
                            f["colunas"]))
            print("%d salas · %d PNG · gravado %s" % (
                len(regs), n, os.path.relpath(gravar_json_sala(regs), ROOT)))
            return
        dump(outdir)
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
