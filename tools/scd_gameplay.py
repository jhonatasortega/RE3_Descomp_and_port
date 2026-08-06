#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Gera o MODELO DE DADOS DE GAMEPLAY por sala do RE3 (PS1 NTSC-U) a partir do SCD.

Le cada .ARD (bloco 8 = RDT, offset_table[16] = script SCD), varre os opcodes de
posicionamento por assinatura de bytes fixos (robusto a opcodes de fluxo nao mapeados)
e emite, por sala:  godot/data/STAGE{n}/{sala}_scd.json  com:
    doors     [{aot, aot_quad, box, to_x, to_z, to_y, to_facing, to_stage, to_room, dest_raw, ...}]
    enemies   [{type_id, x, z, facing, state, opcode, index}]   (ver nota de confianca)
    items     [{type_id, amount, x, z, aot}]
    triggers  [{aot, sce, event, quad/box, data}]
    flags     [ ... triggers do tipo FLAG_CHG ... ]
    messages  [ ... triggers do tipo MESSAGE ... ]
E o grafo global godot/data/room_graph.json (nos=salas, arestas=portas).

EVIDENCIA DO EXE / STRIDES (ver docs/formatos/scd_gameplay.md):
  - 0x67 door_aot_set : 62 bytes FIXOS. CONFIRMADO: em R100 func6 os 0x67 estao a
    exatamente 62 bytes (4 portas), func5=1 porta 62B, func7=1 porta 62B + '01 00'(end).
  - 0x63 sce_aot_set  : 20 bytes. handler no exe @0x800766ec registra a AABB numa
    slot de 32B (array em base+0x4c0), lendo os campos +4/+6/+c/+d/+e/+f do opcode.
  - 0x64 sce_aot_set_4p: 28 bytes (trigger em quadrilatero).
  - 0x68 sce_item_aot_set: ~30 bytes (item no chao); item_id@+22, amount@+24.
  - 0x61/0x62 entity  : 32 bytes (modelo posicionado; type@+24). Inclui NPCs/objetos e
    (provavelmente) inimigos misturados -> ver nota de confianca em 'enemies'.

DESTINO DA PORTA (to_stage/to_room): NAO decodificado. 8 encodings candidatos
(off14/16/18 como stage/room, com e sem bit-packing) deram reciprocidade global de
0-4% -> REFUTADOS. A troca de sala e resolvida em runtime pelo handler/evento, nao por
um campo cru trivial. Preservamos os bytes em dest_raw e a POSICAO DE CHEGADA (to_x/y/z/
facing), que ESTAO decodificadas. Ver docs/formatos/scd_gameplay.md secao 'Destino'.
"""
import struct, glob, os, json, sys, re
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

SECTOR = 0x800

# enum SCE de trigger (byte +2 do opcode 0x63/0x64). Ver docs/formatos/exe.md 2.1.
SCE = {
    0: "SCE_AUTO", 1: "SCE_DOOR", 2: "SCE_ITEM", 3: "SCE_NORMAL", 4: "SCE_MESSAGE",
    5: "SCE_EVENT", 6: "SCE_FLAG_CHG", 7: "SCE_WATER", 8: "SCE_MOVE", 9: "SCE_SAVE",
    10: "SCE_ITEMBOX", 11: "SCE_DAMAGE", 12: "SCE_STATUS", 13: "SCE_HIKIDASHI",
    14: "SCE_WINDOWS", 15: "SCE_15",
}

# ------------------------------------------------------------------ RDT / script
def rdt_of(data):
    _fsz, bc = struct.unpack_from("<II", data, 0)
    lens = [struct.unpack_from("<I", data, 8 + i * 8)[0] for i in range(bc)]
    cur = SECTOR; starts = []
    for i in range(bc):
        starts.append(cur)
        cur = (cur + lens[i] + SECTOR - 1) // SECTOR * SECTOR
    return data[starts[8]:starts[8] + lens[8]]

def script_bounds(rdt):
    offs = struct.unpack_from("<22I", rdt, 8)
    so = offs[16]
    later = [t for t in offs if so < t <= len(rdt)]
    end = min(later) if later else len(rdt)
    return so, end

def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]

def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]

def aabb_quad(x, z, w, d):
    """AABB (canto x,z + largura/profundidade) -> 4 cantos [x,z] no plano do chao."""
    return [[x, z], [x + w, z], [x + w, z + d], [x, z + d]]

# ------------------------------------------------------------------ extracao
MARK = re.compile(rb"\xff.\x60\x10\x00")   # marcador 'ff [var] 60 10 00' antes da pos de chegada

def parse_room(path):
    data = open(path, "rb").read()
    rdt = rdt_of(data)
    so, end = script_bounds(rdt)
    b = rdt
    doors, triggers, items, enemies = [], [], [], []

    # ---- PORTAS: ancoradas no MARCADOR DE CHEGADA 'ff [x] 60 10 00' ----
    # O TAIL do struct de porta e' de layout FIXO (confirmado: 0x7f em marker-13 em 100%
    # das 481 portas); o HEAD (opcode + AABB + destino) e' de tamanho VARIAVEL, por isso
    # a varredura por opcode 0x67 so' pegava 254/481. Campos relativos a 'm' (posicao do
    # byte 0x60 do marcador):
    #   m-13 = 0x7f (const) ; m-12 = seq (indice da porta) ; m-2 = 0xff (inicio marcador)
    #   m+3/+5/+7/+9 = chegada x,y,z,facing (s16)  <- SEMPRE confiavel (validado por coord)
    #   AABB do gatilho: em m-29 (x,z,w,d) quando o head tem 35B (caso 0x67); senao ausente.
    for mm in MARK.finditer(b):
        m = mm.start() + 2                       # posicao do '60'
        if b[m - 13] != 0x7f:                    # exige o tail fixo (anti falso-positivo)
            continue
        tx, ty, tz, tdir = s16(b, m + 3), s16(b, m + 5), s16(b, m + 7), s16(b, m + 9)
        if not (abs(tx) < 40000 and abs(tz) < 40000):
            continue
        # AABB do gatilho na sala de ORIGEM (best-effort: offset fixo do caso 0x67)
        box = None; quad = None; aot = None; dest_raw = None
        opcode = b[m - 35] if m - 35 >= 0 else None
        bx, bz, bw, bd = s16(b, m - 29), s16(b, m - 27), s16(b, m - 25), s16(b, m - 23)
        if abs(bx) < 32000 and 0 < bw < 20000 and 0 < bd < 20000:
            box = {"x": bx, "z": bz, "w": bw, "d": bd}
            quad = aabb_quad(bx, bz, bw, bd)
        if opcode == 0x67:
            aot = b[m - 34]
            dest_raw = list(b[m - 21:m - 15])    # candidatos de destino (nao resolvidos)
        doors.append({
            "aot": aot, "opcode": opcode, "seq": b[m - 12],
            "box": box, "aot_quad": quad,
            "to_stage": None, "to_room": None,   # NAO decodificado (ver doc)
            "to_x": tx, "to_y": ty, "to_z": tz, "to_facing": tdir,
            "needs_key": None,
            "dest_raw": dest_raw,
        })

    i = so
    while i < end - 1:
        op = b[i]

        # ---- ITEM no chao 0x68 (~30B) ----
        if op == 0x68 and i + 30 <= end and b[i + 2] == 0x02 and b[i + 3] in (0x31, 0x21, 0x41, 0x51, 0x11, 0x01) and b[i + 5] == 0:
            fA = u16(b, i + 22); amt = u16(b, i + 24); fB = u16(b, i + 26)
            pts = [[s16(b, i + 6 + k * 4), s16(b, i + 8 + k * 4)] for k in range(4)]
            if fA < 0x100 and amt <= 999 and fB < 0x100 and all(abs(px) < 45000 and abs(pz) < 45000 for px, pz in pts):
                cx = sum(p[0] for p in pts) // 4; cz = sum(p[1] for p in pts) // 4
                items.append({
                    "type_id": fA, "amount": amt, "x": cx, "z": cz,
                    "aot": b[i + 1], "quad": pts, "type_id_alt": fB,
                })
                i += 30
                continue

        # ---- TRIGGER de area 0x63 (20B) ----
        if op == 0x63 and i + 20 <= end and b[i + 3] in (0x31, 0x41, 0x51, 0x61) and b[i + 5] == 0:
            x, z = s16(b, i + 6), s16(b, i + 8)
            if abs(x) < 32000:
                sce = b[i + 2]
                w, dd = s16(b, i + 10), s16(b, i + 12)
                triggers.append({
                    "aot": b[i + 1], "sce": sce, "event": SCE.get(sce, "SCE_%d" % sce),
                    "floor": b[i + 3], "kind": "box",
                    "quad": aabb_quad(x, z, w, dd),
                    "box": {"x": x, "z": z, "w": w, "d": dd},
                    "data": list(b[i + 14:i + 20]),
                })
                i += 20
                continue

        # ---- TRIGGER de area em 4 pontos 0x64 (28B) ----
        if op == 0x64 and i + 28 <= end and b[i + 3] == 0x31 and b[i + 5] == 0:
            sce = b[i + 2]
            pts = [[s16(b, i + 6 + 4 * k), s16(b, i + 8 + 4 * k)] for k in range(4)]
            if all(abs(px) < 45000 for px, pz in pts):
                triggers.append({
                    "aot": b[i + 1], "sce": sce, "event": SCE.get(sce, "SCE_%d" % sce),
                    "kind": "quad", "quad": pts, "data": list(b[i + 22:i + 28]),
                })
                i += 28
                continue

        # ---- ENTIDADE / (poss.) INIMIGO 0x61 / 0x62 (32B) ----
        if op in (0x61, 0x62) and i + 32 <= end and b[i + 2] == 0x01 and b[i + 3] == 0x21 and b[i + 5] == 0:
            g = bytes(b[i:i + 32])
            enemies.append({
                "type_id": g[24], "x": s16(g, 6), "z": s16(g, 8),
                "facing": None, "state": None,
                "opcode": op, "index": g[23], "flag": g[4],
            })
            i += 32
            continue

        i += 1

    # separa flags e messages dos triggers (conveniencia p/ o remake)
    flags = [t for t in triggers if t["sce"] == 6]
    messages = [t for t in triggers if t["sce"] == 4]
    return {
        "doors": doors, "enemies": enemies, "items": items,
        "triggers": triggers, "flags": flags, "messages": messages,
    }

# ------------------------------------------------------------------ main
def main():
    files = sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD"))
    nodes = []; edges = []
    tot = {"doors": 0, "enemies": 0, "items": 0, "triggers": 0}
    for f in files:
        stage_dir = os.path.basename(os.path.dirname(f))
        name = os.path.splitext(os.path.basename(f))[0]
        stg = int(name[1], 16); rm = int(name[2:], 16)
        try:
            g = parse_room(f)
        except Exception as e:
            print("ERRO", name, e); continue
        for k in tot:
            tot[k] += len(g[k])
        out = {
            "_meta": {
                "sala": name, "stage": stg, "room": rm,
                "descricao": "Modelo de gameplay do SCD (RE3 PS1 NTSC-U). Gerado por tools/scd_gameplay.py.",
                "aviso_destino": "doors.to_stage/to_room NAO decodificados (encoding resistiu a 8 hipoteses, "
                                 "reciprocidade 0-4%). to_x/to_y/to_z/to_facing = posicao de CHEGADA (decodificada).",
                "aviso_inimigos": "enemies = opcodes 0x61/0x62 (modelos posicionados). type_id e' cru; a "
                                  "lista MISTURA inimigos com NPCs/objetos (0x61 aparece em salas seguras). "
                                  "facing/state ainda nao isolados. Confianca de 'e inimigo': BAIXA.",
            },
            "doors": g["doors"], "enemies": g["enemies"], "items": g["items"],
            "triggers": g["triggers"], "flags": g["flags"], "messages": g["messages"],
        }
        dest = os.path.join(paths.data(), stage_dir, name + "_scd.json")
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        json.dump(out, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

        nodes.append({"id": name, "stage": stg, "room": rm,
                      "n_doors": len(g["doors"]), "n_enemies": len(g["enemies"]),
                      "n_items": len(g["items"]), "n_triggers": len(g["triggers"])})
        for dd in g["doors"]:
            edges.append({
                "src": name, "aot": dd["aot"],
                "box": dd["box"], "seq": dd["seq"],
                "to_stage": None, "to_room": None,
                "arrival": None if dd["to_x"] is None else
                           {"x": dd["to_x"], "y": dd["to_y"], "z": dd["to_z"], "facing": dd["to_facing"]},
                "dest_raw": dd["dest_raw"],
            })

    graph = {
        "_meta": {
            "descricao": "Grafo de salas do RE3 (PS1 NTSC-U). NOS=salas; ARESTAS=portas (opcode SCD 0x67).",
            "gerado_por": "tools/scd_gameplay.py",
            "destino_status": "to_stage/to_room NAO decodificados (ver docs/formatos/scd_gameplay.md). "
                              "'arrival' (posicao de chegada + facing) ESTA decodificada; use-a p/ posicionar "
                              "o player quando o mapeamento sala-destino for resolvido (via handler do exe).",
            "nos": len(nodes), "arestas": len(edges),
            "arestas_com_chegada": sum(1 for e in edges if e["arrival"]),
        },
        "nodes": nodes, "edges": edges,
    }
    json.dump(graph, open(paths.data("room_graph.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    print("salas:", len(nodes))
    print("totais:", tot)
    print("arestas c/ chegada:", graph["_meta"]["arestas_com_chegada"], "/", len(edges))

if __name__ == "__main__":
    main()
