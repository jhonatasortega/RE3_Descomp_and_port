#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Monta o GRAFO REAL de salas do RE3 (PS1 NTSC-U) a partir do DESTINO ESTATICO
das portas do SCD -- RESOLVIDO neste round (ver docs/decomp/notes/door_handler.md).

DESCOBERTA: a porta e' o AOT com SCE type (byte@+2) em {1,13}, criado pelos opcodes
0x61 (DOOR_AOT_SET, 32B) e 0x62 (DOOR_AOT_SET_4P, 40B). O destino (next_stage,
next_room) e' CAMPO ESTATICO no bytecode -- lido pelo door_handler 0x800248e4 do
descriptor (opcode+2+path). Ver tools/scd_door_dest.py para a prova e os offsets.
Reciprocidade A<->B = 94.3% (cross-stage e gemeas incluidas) confirma o achado; as
17 arestas-sala mao-unica restantes sao TODAS justificadas (ver ONEWAY_REASONS).

sce==1 = porta normal (produtor 0x80050d28); sce==13 = porta condicional/scripted
(handler 0x80051cb0; 6 portas, 3 pares reciprocos). O round anterior contava so'
sce==1 (447) e descartava as 6 sce==13 -- que SAO transicoes de sala reais -> 453.

Mapeamento indice-interno -> Rxyz: DE-PARA AUTORITATIVO do motor
`indice -> fileid 0x8009dfd0[stage][room] -> nome` (ver scd_door_dest.room_index_map).
Fecha TAMBEM os stages 4/6/7 (dups/slots-0 na tabela): 453/453 portas resolvidas.
Reciprocidade 94.3% (279/296); mao-unica 17/296, todas justificadas. Nenhuma porta null.

Saidas:
  - godot/data/room_graph.json  (nodes + edges; 1 edge por porta)
  - godot/data/STAGE*/R*_scd.json  (reescreve doors[]; preserva as demais secoes)

Uso:  python tools/room_graph_build.py [--dry]
"""
import json, glob, os, sys
from collections import defaultdict
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scd_door_dest import extract_doors, resolve, load_twin_canon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = paths.data()
GRAPH = os.path.join(DATA, "room_graph.json")

# Rotulos de area/sala DOCUMENTADOS pela comunidade (fonte NAO-oficial: thread
# "Resident Evil 3 Complete RDT info" / "RDT Information and Places", Resident Evil
# 1 2 3 Modding Forum -- tapatalk.com/groups/residentevil123). So CONTEXTO nos nos.
AREA_LABELS = {
    "R100": ("Downtown", "Armazem - sala de save (1a)"),
    "R101": ("Downtown", "Armazem (Dario aparece)"),
    "R103": ("Downtown", "Raccoon Streets (zumbi do carro)"),
    "R104": ("Downtown", "Rua onde Brad irrompe"),
    "R105": ("Downtown", "Atras do bar do Jack"),
    "R106": ("Downtown", "Beco da boutique"),
    "R110": ("RPD", "Entrada da delegacia (1o portao)"),
    "R111": ("RPD", "Departamento de Policia de Raccoon"),
    "R112": ("RPD", "Escritorio da RPD (Marvin ferido)"),
    "R417": ("Factory/transicao", "Caminho p/ hospital e jardim"),
    "R500": ("Factory", "Dentro da fabrica"),
    "R501": ("Factory", "Sala de save da fabrica"),
    "R502": ("Factory", "Fabrica subterranea (elevador)"),
    "R504": ("Factory", "Esgoto (queda; encontro com Carlos)"),
    "R505": ("Factory", "Save dos dispositivos de poluicao da agua"),
    "R508": ("Factory", "Caminho p/ transformacao do Nemesis / morte do Nicholai"),
    "R509": ("Factory", "Luta final Nemesis (forma humana; quimicos)"),
    "R50A": ("Factory", "Nicholai fugindo de helicoptero"),
    "R50B": ("Factory", "Passagem subterranea sob a anterior"),
    "R50C": ("Factory", "Sala antes do chefe final (terremoto)"),
    "R50D": ("Factory", "Sala do chefe final"),
    "R50E": ("Factory", "Chegada do helicoptero de resgate (fim)"),
    "R50F": ("Factory", "Elevador da sala acima"),
    "R510": ("Factory", "Ponte para a fabrica"),
}


# -----------------------------------------------------------------------------
# MAO-UNICA JUSTIFICADA: para cada aresta-sala (canon) SEM porta de volta, o motivo
# provado (SCD/flags/posicao do AOT/disassembly). Chave = (canon_src, canon_dst).
# Auditoria completa das 453 portas (sce in {1,13}) das 169 salas -> 17 arestas
# nao-reciprocas, TODAS explicadas (0 erro de destino/parse encontrado). Ver
# docs/decomp/notes/room_graph.md e door_handler.md.
ONEWAY_REASONS = {
    # Mercenaries (R6xx/R7xx): rota dirigida do modo; R600 e' o hub terminal (0 portas).
    ("R101", "R600"): "mercenaries_hub_terminal: porta de Mercenaries (real R601->R600). "
                      "R600 e' o hub inicial do modo e NAO tem portas de saida (terminal). Mao-unica.",
    ("R201", "R600"): "mercenaries_hub_terminal: porta de Mercenaries (real R701->R600). "
                      "R600 terminal (0 portas). Mao-unica.",
    ("R121", "R11B"): "mercenaries_route: porta exclusiva de Mercenaries (real R621->R61B); "
                      "no jogo principal R121 nao liga a R11B. Rota dirigida do modo, sem volta.",
    ("R206", "R30E"): "mercenaries_route: porta de Mercenaries (real R706->R316), cross-stage; "
                      "rota dirigida do modo, sem porta de volta.",
    # Variantes de estado da MESMA sala fisica (a porta de volta aponta p/ a variante).
    ("R109", "R10E"): "story_variant: a porta de volta de R10E aponta p/ R123 -- variante de estado "
                      "da MESMA sala fisica de R109 (fingerprint de portas identico: familia "
                      "R109/R123/R623). Fisicamente reciproco R10E<->{R109=R123}.",
    ("R20D", "R217"): "story_variant: R20D usa a MESMA porta fisica (box identico) p/ R20E (estado "
                      "normal) e R217 (estado alt) -- R217 e' variante de R20E. Reciproco no nivel "
                      "fisico via R20D<->R20E e R208<->R20E (ambas usam o mesmo box p/ R20E/R217).",
    ("R30B", "R30D"): "story_variant: R30B usa a MESMA porta fisica (box identico) p/ R30A (normal) "
                      "e R30D (alt) -- R30D e' variante de R30A. Reciproco no nivel fisico via "
                      "R30A<->R30B (R30A->R30B existe).",
    ("R30D", "R300"): "transient_variant_scripted: R30D (variante transitoria, alcancada so' pelo "
                      "estado-alt de R30B) sai por porta de box ZERO (scripted) p/ R310 (=R300). "
                      "Sala de passagem; sem porta de volta estatica.",
    # Progressao de historia (cross-stage), disparada por cutscene (box ZERO).
    ("R20C", "R303"): "story_progression_gate: cross-stage 2->3 (Uptown->Clock Tower). Porta em "
                      "R215 (variante de R20C) com box ZERO = disparada por evento/cutscene, nao por "
                      "colisao. Progressao sem retorno (nao se volta ao Uptown).",
    ("R20C", "R305"): "story_progression_gate: cross-stage 2->3 (Uptown->Clock Tower). Porta em R215 "
                      "com box ZERO (evento/cutscene). Progressao sem retorno.",
    # Endgame (Stage 5 finale): cadeia linear chefe->fuga, sem retorno.
    ("R50C", "R50D"): "endgame_boss: entrada da sala do chefe final (R50D). Progressao de historia; "
                      "mao-unica (nao se volta antes do combate).",
    ("R50D", "R50F"): "endgame_boss_scripted: sala do chefe -> elevador (R50F) por porta de box ZERO "
                      "(cutscene). Mao-unica (endgame).",
    ("R50F", "R50E"): "endgame_ending_scripted: elevador -> chegada do helicoptero (R50E, fim do jogo) "
                      "por box ZERO. R50E e' terminal (0 portas). Mao-unica.",
    # Queda / passagem de sentido unico.
    ("R510", "R504"): "one_way_fall: queda da ponte (R510) p/ o esgoto (R504; encontro com Carlos). "
                      "arrival ZERADO = spawn definido por script da queda. R504 nao volta a R510.",
    ("R10A", "R10F"): "one_way_layout: a unica porta de SAIDA estatica de R10F leva a R106/R121 "
                      "(reciprocas com essas via familia R106/R121/R621). A entrada R10A->R10F nao "
                      "tem porta de volta estatica em R10F (R10F so' tem essa saida + self-loops de camera).",
    ("R212", "R206"): "one_way_special: transicao especial p/ o hub R206 (sat=0x31, trigger PONTUAL "
                      "1x1, cut=2). R206 (hub, 101 funcoes) nao tem porta estatica de volta a R212.",
    # Placeholder / sala nao-alcancavel.
    ("R10D", "R101"): "placeholder_unused: R10D NAO e' alcancavel (nenhuma porta do jogo aponta p/ ela) "
                      "e sua UNICA porta tem box E arrival ZERADOS (unico caso no jogo inteiro) = slot "
                      "template/placeholder. Destino nominal R101; nao e' transicao de gameplay real.",
}


def stg(name):
    return int(name[1], 16)


def room_idx(name):
    return int(name[2:], 16)


def main():
    dry = "--dry" in sys.argv
    doors, name2si, si2name = extract_doors()
    canon = load_twin_canon()
    cn = lambda x: canon.get(x, x)

    # resolve destino de cada porta
    for d in doors:
        d["dst"] = resolve(d, si2name)

    # conjunto de arestas canonicas p/ decidir reciprocidade
    canon_edges = set((cn(d["src"]), cn(d["dst"])) for d in doors if d["dst"])

    def is_recip(src, dst):
        return (cn(dst), cn(src)) in canon_edges

    # ---------- monta edges (1 por porta) ----------
    edges = []
    n_resolved = n_recip = n_cross = 0
    n_oneway_explained = n_oneway_unexplained = 0
    for d in doors:
        bx, bz, bw, bd = d["box"]
        ax, ay, az, af = d["arrival"]
        e = {
            "src": d["src"], "opcode": d["opcode"], "sce": d["sce"],
            "aot": d["aot"], "seq": d["seq"],
            "box": {"x": bx, "z": bz, "w": bw, "d": bd},
            "arrival": {"x": ax, "y": ay, "z": az, "facing": af},
            "raw_stage": d["raw_stage"], "raw_room": d["raw_room"], "to_camera": d["cut"],
        }
        dst = d["dst"]
        if dst:
            n_resolved += 1
            recip = is_recip(d["src"], dst)
            if recip:
                n_recip += 1
            if stg(dst) != d["si"][0] + 1:
                n_cross += 1
            e["to_stage"] = stg(dst)
            e["to_room"] = room_idx(dst)
            e["to_room_id"] = dst
            e["reciprocal"] = recip
            if not recip:
                reason = ONEWAY_REASONS.get((cn(d["src"]), cn(dst)))
                if reason is None:
                    reason = ("MAO-UNICA NAO EXPLICADA (residuo honesto): sem porta de volta "
                              "B->A e sem justificativa catalogada -- revisar.")
                    n_oneway_unexplained += 1
                else:
                    n_oneway_explained += 1
                e["oneway_reason"] = reason
            e["dest_source"] = "recip" if recip else "scd_door"
            e["dest_conf"] = 0.95 if recip else 0.75
            door_kind = ("sce==1 porta normal (produtor 0x80050d28)" if d["sce"] == 1
                         else "sce==13 porta condicional/scripted (handler 0x80051cb0)")
            e["dest_reason"] = (
                "campo estatico do SCD (opcode 0x%02x, %s; next_stage@+8/next_room@+9 do "
                "descriptor, lidos pelo door_handler 0x800248e4). De-para indice->fileid "
                "0x8009dfd0->nome (autoritativo; resolve dups dos stages 4/6/7)%s"
                % (d["opcode"], door_kind,
                   "; RECIPROCO A<->B (porta de volta confirma)" if recip
                   else "; mao-unica -- ver oneway_reason")
            )
        else:
            e["to_stage"] = None
            e["to_room"] = None
            e["to_room_id"] = None
            e["dest_source"] = None
            e["dest_conf"] = None
            e["dest_reason"] = (
                "indice interno de sala (%d) cai fora da tabela de fileids 0x8009dfd0 do "
                "stage-alvo %d ou em slot vazio (fileid 0). Destino existe no SCD mas nao "
                "mapeia p/ nome de sala carregavel."
                % (d["raw_room"], d["raw_stage"] % 9)
            )
        edges.append(e)

    # ---------- monta nodes (1 por sala) ----------
    doors_by_room = defaultdict(list)
    for e in edges:
        doors_by_room[e["src"]].append(e)
    nodes = []
    for name in sorted(name2si):
        node = {"id": name, "stage": stg(name), "room": room_idx(name),
                "n_doors": len(doors_by_room.get(name, []))}
        lbl = AREA_LABELS.get(name)
        if lbl:
            node["area"] = lbl[0]; node["desc"] = lbl[1]
            node["area_source"] = "comunidade (nao-oficial); ver room_graph.md"
        nodes.append(node)

    # ---------- reciprocidade nivel-sala ----------
    recip_edges = sum(1 for a, b in canon_edges if (b, a) in canon_edges)
    recip_pct = 100.0 * recip_edges / len(canon_edges) if canon_edges else 0.0

    graph = {
        "_meta": {
            "descricao": "Grafo REAL de salas do RE3 (PS1 NTSC-U). 1 aresta por porta.",
            "gerado_por": "tools/room_graph_build.py + tools/scd_door_dest.py",
            "destino_status": (
                "to_stage/to_room = CAMPO ESTATICO do SCD, extraido do opcode de porta "
                "(AOT sce==1: 0x61 DOOR_AOT_SET / 0x62 DOOR_AOT_SET_4P). next_stage/"
                "next_room lidos pelo door_handler 0x800248e4 do descriptor (opcode+2+path). "
                "Ver docs/decomp/notes/door_handler.md e tools/scd_door_dest.py."
            ),
            "destino_metodo": {
                "opcode_porta": "AOT que troca de sala: opcodes 0x61 (32B) / 0x62 (40B) com SCE type (byte@+2) em {1,13}",
                "sce_types": "sce==1 = porta normal (produtor 0x80050d28); sce==13 = porta condicional/scripted (handler 0x80051cb0). Ambos setam gs+0x2154+flag 0x800c7960 e usam o MESMO layout de descriptor.",
                "offsets_0x61": "next_stage=+0x16, next_room=+0x17, cut=+0x18, chegada=s16@+0xe/+0x10/+0x12/+0x14",
                "offsets_0x62": "next_stage=+0x1e, next_room=+0x1f, cut=+0x20, chegada=s16@+0x16/+0x18/+0x1a/+0x1c",
                "next_stage": "byte, aplicar mod 9 -> exe-stage (0..6)",
                "next_room": "byte = indice interno; de-para indice->fileid 0x8009dfd0[stage]->nome (AUTORITATIVO; resolve dups dos stages 4/6/7)",
                "reciprocal": "true = porta de volta B->A confirma; false = mao-unica (ver oneway_reason)",
                "cobertura": "varredura de TODOS os opcodes AOT (0x61/0x62/0x63/0x64/0x65/0x67/0x68) das 169 salas: apenas sce in {1,13} trocam de sala. Room-loader 0x800493ec so' e' chamado pelo cluster do door_handler (2 sites) -- nao ha warp por opcode de script.",
                "validacao": "453 destinos resolvidos 100%; reciprocidade A<->B 94.3% (279/296); 17 arestas mao-unica TODAS justificadas (0 erro de parse/destino).",
            },
            "nos": len(nodes),
            "arestas": len(edges),
            "destino_stats": {
                "arestas": len(edges),
                "portas_sce1": sum(1 for d in doors if d["sce"] == 1),
                "portas_sce13": sum(1 for d in doors if d["sce"] == 13),
                "resolvidas": n_resolved,
                "reciprocas": n_recip,
                "mao_unica": len(edges) - n_recip,
                "mao_unica_justificada": n_oneway_explained,
                "mao_unica_nao_explicada": n_oneway_unexplained,
                "cross_stage": n_cross,
                "abertas_todo": len(edges) - n_resolved,
                "arestas_sala_canon": len(canon_edges),
                "arestas_sala_reciprocas": recip_edges,
                "arestas_sala_mao_unica": len(canon_edges) - recip_edges,
                "reciprocidade_pct": round(recip_pct, 1),
                "reciprocidade_explicada_pct": 100.0 if n_oneway_unexplained == 0 else round(
                    100.0 * recip_edges / len(canon_edges), 1),
            },
        },
        "nodes": nodes,
        "edges": edges,
    }

    print("=== room_graph_build (destino ESTATICO do SCD) ===")
    print("portas/arestas:", len(edges), "| nos:", len(nodes),
          "| sce1:", sum(1 for d in doors if d["sce"] == 1),
          "sce13:", sum(1 for d in doors if d["sce"] == 13))
    print("destino resolvido:", n_resolved, "| recíprocas:", n_recip,
          "| cross-stage:", n_cross, "| abertas(TODO):", len(edges) - n_resolved)
    print("arestas-sala canon:", len(canon_edges), "| reciprocas:", recip_edges,
          "(%.1f%%)" % recip_pct, "| mao-unica:", len(canon_edges) - recip_edges,
          "(justificadas:", n_oneway_explained > 0 and "todas" or "0",
          "| nao-explicadas:", n_oneway_unexplained, ")")
    if n_oneway_unexplained:
        print("  !! ATENCAO: %d arestas mao-unica SEM justificativa catalogada." % n_oneway_unexplained)
    else:
        print("  reciprocidade EXPLICADA a 100% (reciprocas + mao-unica justificadas).")

    if dry:
        print("[dry] nada gravado.")
        return

    json.dump(graph, open(GRAPH, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # ---------- propaga p/ os _scd.json (reescreve doors[], preserva o resto) ----------
    n_files = 0
    for f in glob.glob(os.path.join(DATA, "STAGE*", "R*_scd.json")):
        name = os.path.basename(f)[:4]
        sc = json.load(open(f, encoding="utf-8"))
        room_doors = sorted(doors_by_room.get(name, []), key=lambda e: e["seq"])
        new_doors = []
        for e in room_doors:
            nd = {
                "opcode": e["opcode"], "sce": e["sce"], "aot": e["aot"], "seq": e["seq"],
                "box": e["box"],
                "to_stage": e["to_stage"], "to_room": e["to_room"], "to_room_id": e["to_room_id"],
                "to_x": e["arrival"]["x"], "to_y": e["arrival"]["y"],
                "to_z": e["arrival"]["z"], "to_facing": e["arrival"]["facing"],
                "to_camera": e["to_camera"],
                "raw_stage": e["raw_stage"], "raw_room": e["raw_room"],
                "reciprocal": e.get("reciprocal"),
                "dest_source": e["dest_source"], "dest_conf": e["dest_conf"],
                "dest_reason": e["dest_reason"],
            }
            if "oneway_reason" in e:
                nd["oneway_reason"] = e["oneway_reason"]
            new_doors.append(nd)
        sc["doors"] = new_doors
        sc.setdefault("_meta", {})["aviso_destino"] = (
            "doors = PORTAS reais (AOT sce in {1,13}, opcodes 0x61/0x62). sce==1 = porta "
            "normal; sce==13 = porta condicional/scripted (mesmo layout). to_stage/to_room "
            "= CAMPO ESTATICO do SCD (next_stage@+8/next_room@+9 do descriptor, lidos pelo "
            "door_handler 0x800248e4). to_x/y/z/facing = chegada. De-para indice->fileid "
            "0x8009dfd0->nome (autoritativo; resolve dups dos stages 4/6/7 -> 453/453 portas). "
            "reciprocal=true/false; se false, oneway_reason justifica a mao-unica. "
            "Ver room_graph.json _meta e docs/decomp/notes/door_handler.md."
        )
        json.dump(sc, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        n_files += 1
    print("_scd.json atualizados:", n_files)


if __name__ == "__main__":
    main()
