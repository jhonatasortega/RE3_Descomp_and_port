#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Extrai as PORTAS (opcode 0x67, stride 62B) das 169 salas, atualiza rdt.script.doors
nos JSONs (preservando items/events/entities) e monta godot/data/map_graph.json.

Struct da porta 0x67 (62 bytes) — campos CONFIRMADOS + observados (ver docs/formatos/SCD.md):
  +0..5   header: 67 [aot] 02 31 [floor] 00
  +6..13  caixa de trigger AABB: x,z (s16, centro) + w,d (s16)
  +14..23 bloco de destino (10B) — sala/camera-alvo NAO decodificados (reciprocidade < 6%)
  +20/+23 contador de sequencia da porta (nao e o destino)
  ~+33    marcador 'ff 00 60 10 00' (quando presente)
  ~+38    posicao de ENTRADA: x,y,z (s16) + orientacao
O ENCODING do destino (sala-alvo) permanece EM ABERTO — precisa do handler de porta no exe.
"""
import struct, glob, os, json, sys
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py
sys.path.insert(0, "tools")
import scd_decode as S

def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]

def extract_doors(rdt, so):
    b = rdt; out = []
    for i in range(so, len(b) - 62):
        if b[i] == 0x67 and b[i+2] == 0x02 and b[i+3] == 0x31 and b[i+5] == 0:
            x, z, w, d = struct.unpack_from("<hhhh", b, i+6)
            if not (abs(x) < 32000 and 0 < w < 20000):
                continue
            g = bytes(b[i:i+62])
            entry = None
            # marcador 'ff 00 60 10 00' precede a posicao de entrada (x,y,z,dir)
            m = g.find(b"\xff\x00\x60\x10\x00")
            if m != -1 and m + 5 + 8 <= 62:
                ex, ez = s16(g, m+5), s16(g, m+9)
                if 2000 < abs(ex) < 40000 and 2000 < abs(ez) < 40000:
                    entry = {"x": ex, "y": s16(g, m+7), "z": ez, "dir": s16(g, m+11)}
            out.append({
                "aot": g[1], "floor": g[4],
                "pos": [x, z], "size": [w, d],
                "entry": entry,
                "dest_room": None,               # NAO decodificado (ver docs)
                "dest_raw": list(g[14:24]),
            })
    return out

def main():
    graph_nodes = []; graph_edges = []; total = 0
    for f in sorted(glob.glob("extracted/ntsc-u/CD_DATA/STAGE*/R*.ARD")):
        data = open(f, "rb").read()
        try:
            rdt = S.rdt_of(data); so = S.script_of(rdt)
        except Exception:
            continue
        stage_dir = os.path.basename(os.path.dirname(f))
        name = os.path.splitext(os.path.basename(f))[0]
        stg = int(name[1]); rm = int(name[2:], 16)
        doors = extract_doors(rdt, so)
        total += len(doors)
        graph_nodes.append({"id": name, "stage": stg, "room": rm, "n_doors": len(doors)})
        for dd in doors:
            graph_edges.append({
                "src": name, "aot": dd["aot"],
                "box": dd["pos"], "entry": dd["entry"],
                "dest_room": None, "dest_raw": dd["dest_raw"],
            })
        # atualiza rdt.script.doors preservando o resto
        jp = os.path.join(paths.data(), stage_dir, name + ".json")
        if os.path.exists(jp):
            j = json.load(open(jp, encoding="utf-8"))
            j.setdefault("rdt", {}).setdefault("script", {})["doors"] = doors
            json.dump(j, open(jp, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    graph = {
        "_meta": {
            "descricao": "Grafo de mapa do RE3 (PS1 NTSC-U). NOS=salas; ARESTAS=portas 0x67.",
            "aviso": "dest_room NAO decodificado: o encoding do destino (sala/camera-alvo) da porta "
                     "resistiu a 6 abordagens (bytes fixos->3%% recip; intra-stage->12%%; match por "
                     "posicao de entrada vs bbox/trigger->5%% e coords de sala se sobrepoem). "
                     "Precisa do handler de porta no executavel. dest_raw guardado para decodificacao futura.",
            "nos": len(graph_nodes), "arestas": len(graph_edges),
        },
        "nodes": graph_nodes,
        "edges": graph_edges,
    }
    json.dump(graph, open(paths.data("map_graph.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("portas extraidas:", total, "| nos:", len(graph_nodes), "| arestas:", len(graph_edges))
    withentry = sum(1 for e in graph_edges if e["entry"])
    print("arestas com posicao de entrada:", withentry)

if __name__ == "__main__":
    main()
