#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""CENSO DOS OPCODES DE CENA nas 169 salas do RE3 (SLUS_009.23).

Pedido do dono do repo: "nao da para ficar extraindo as cenas uma por uma, precisa de um
padrao". Este script e' o levantamento que diz QUAL padrao: varre todas as salas, acha as
funcoes que sao CINEMATICA (nao a mao: pelas raizes que o proprio dado declara), fecha o grafo
de chamadas dessas funcoes e conta cada opcode -- quantas vezes, em quantas salas, em quantas
cenas.

Como uma funcao e' reconhecida como CENA (nada aqui e' escolhido por gosto):
  * RAIZ "init"     -- alvo de um `0x04`/`0x03` (evt_exec, handlers 0x80052ea4/0x80052e78):
                       `slot = byte@+1`, `funcao = byte@+3`. E o que abre a cena de ENTRADA
                       (R10D func 7, R101 func 3).
  * RAIZ "sce5"     -- payload de um AOT com `sce == 5` (handler 0x800512bc: le `u16@+0` = slot
                       e `u8@+3` = funcao do payload e chama 0x80052478). E o que abre a cena
                       disparada por caixa (R10D func 11).
  * FECHAMENTO      -- de cada raiz, segue `0x19` (gosub, 0x800537bc) e `0x03`/`0x04` (thread).

O decode de cada funcao e' o LINEAR de tools/scd_decode.py (tabela de tamanhos lida dos
avancos de PC dos handlers da jump-table 0x8009e0f8), o que visita os DOIS ramos de cada `if` --
para censo isso e' o certo: interessa todo opcode que a cena pode executar.

Saida (JSON versionavel, no mesmo espirito dos 155 pedidos de som do exe_audio):
    port/data/cena_opcodes.json

Uso:
    python tools/scd_cena_censo.py                 # imprime o resumo e grava o JSON
    python tools/scd_cena_censo.py --sala R101     # so uma sala, com detalhe
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scd_decode import decode_room, OPCODE_SEM, SIZES  # noqa: E402

RAIZ_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CD_DATA = os.path.join(RAIZ_DIR, "extracted", "ntsc-u", "CD_DATA")
SAIDA = os.path.join(RAIZ_DIR, "port", "data", "cena_opcodes.json")

# ── opcodes que ABREM cena / fecham o grafo ───────────────────────────────────────────────
OP_THREAD = (0x03, 0x04)      # evt_exec: funcao = byte@+3
OP_GOSUB = 0x19               # gosub:    funcao = byte@+1
OP_AOT = (0x61, 0x62, 0x63, 0x64, 0x67, 0x68)   # todos registram AOT: sce = byte@+2
SCE_EVENTO = 5
SAT_QUAD = 0x80               # bit que move o payload de +0x0e para +0x16

# ── CLASSES, para o intérprete poder ser ligado por categoria ─────────────────────────────
# Cada opcode entra numa categoria do que o dono listou. A categoria NAO e' semantica nova: e'
# so um rotulo sobre o handler que os docs ja registram (ver docs/decomp/notes/cena_r10d.md §3
# e cena_r101.md §6). Opcode sem handler medido fica em "desconhecido".
CLASSE = {
    "fluxo": [0x01, 0x02, 0x03, 0x04, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0D, 0x0F, 0x10,
              0x11, 0x12, 0x13, 0x14, 0x15, 0x17, 0x18, 0x19, 0x1B, 0x1C, 0x1D, 0x22, 0x00],
    "variavel": [0x20, 0x21, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x47],
    "flag": [0x4C, 0x4D, 0x4E, 0x4F, 0x23, 0x24],
    "camera": [0x50, 0x51, 0x52, 0x53, 0x54],
    "fade": [0x46],
    "som": [0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B, 0x83, 0x8A],
    "ator": [0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8B, 0x8C,
             0x8D, 0x8E, 0x8F, 0x74, 0x76, 0x77],
    "cenario": [0x6E, 0x7B, 0x7F, 0x65, 0x66, 0x6F],
    "efeito": [0x70, 0x71, 0x72, 0x73, 0x75, 0x78, 0x79],
    "personagem": [0x7D, 0x7E, 0x79],
    "fmv": [0x7A],
}
CLASSE_DE = {}
for _c, _ops in CLASSE.items():
    for _o in _ops:
        CLASSE_DE.setdefault(_o, _c)


def salas():
    """Todas as salas do CD, por stage. Devolve [(id, caminho)] ordenado."""
    fora = []
    for st in range(1, 8):
        d = os.path.join(CD_DATA, "STAGE%d" % st)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.upper().endswith(".ARD") and f.upper().startswith("R"):
                fora.append((os.path.splitext(f)[0].upper(), os.path.join(d, f)))
    vistos = {}
    for rid, p in fora:
        vistos.setdefault(rid, p)
    return sorted(vistos.items())


def raizes_e_grafo(insns_por_func):
    """Devolve (raizes, chamadas) da sala.

    raizes   = {func: "init" | "sce5"}
    chamadas = {func: set(func)} por `0x19` (gosub) e `0x03`/`0x04` (thread)
    """
    raizes = {}
    chamadas = {}
    for fi, insns in insns_por_func.items():
        alvos = set()
        for _rel, op, _sz, bs in insns:
            if op in OP_THREAD and len(bs) >= 4:
                alvos.add(bs[3])
                raizes.setdefault(bs[3], "init")
            elif op == OP_GOSUB and len(bs) >= 2:
                alvos.add(bs[1])
            elif op in OP_AOT and len(bs) >= 4 and bs[2] == SCE_EVENTO:
                pbase = 0x16 if (bs[3] & SAT_QUAD) else 0x0E
                if len(bs) >= pbase + 4:
                    raizes[bs[pbase + 3]] = "sce5"
        chamadas[fi] = alvos
    return raizes, chamadas


def fechamento(raizes, chamadas):
    """Toda funcao alcancavel a partir das raizes por gosub/thread."""
    fora = set()
    pilha = list(raizes.keys())
    while pilha:
        f = pilha.pop()
        if f in fora:
            continue
        fora.add(f)
        for g in chamadas.get(f, ()):
            if g not in fora:
                pilha.append(g)
    return fora


def condicoes_de_while(insns):
    """Opcodes usados como CONDICAO de `while` (0x10) numa funcao.

    Por que isto e' o dado mais importante do censo: o `while` do motor
    (`0x80053364` -> avalia por `0x80053550`, que DESPACHA o opcode em PC+4) e' o unico ponto
    em que um opcode nao implementado PRENDE a cena para sempre -- todos os outros o interprete
    pode atravessar andando o PC. `cena.gd` cobre o `0x4c`; qualquer outro aqui e' bloqueante.
    """
    fora = []
    for i, (_rel, op, sz, _bs) in enumerate(insns):
        if op != 0x10:
            continue
        if i + 1 < len(insns):
            fora.append(insns[i + 1][1])
    return fora


def censo(uma_sala=None):
    ops = {}          # opcode -> {"n", "salas": set, "cenas": n}
    cenas = []
    por_sala = {}
    for rid, caminho in salas():
        if uma_sala and rid != uma_sala:
            continue
        try:
            res, unk, _rdt, _so = decode_room(caminho)
        except Exception as e:                                    # sala ilegivel: registra
            por_sala[rid] = {"erro": str(e)}
            continue
        insns_por_func = {fi: insns for fi, _start, insns, _ok in res}
        raizes, chamadas = raizes_e_grafo(insns_por_func)
        # Uma CENA = uma RAIZ (uma thread que o dado manda abrir) + tudo que ela alcanca. Contar
        # por raiz, e nao por funcao, e' o que casa com a decisao que o port precisa tomar:
        # "esta cena pode rodar?" e' uma pergunta sobre a raiz inteira.
        for fi in sorted(raizes):
            if fi not in insns_por_func:
                continue
            alc = fechamento({fi: raizes[fi]}, chamadas)
            usados = {}
            cond = set()
            n_insn = 0
            for g in sorted(alc):
                insns = insns_por_func.get(g)
                if insns is None:
                    continue
                n_insn += len(insns)
                for _rel, op, _sz, _bs in insns:
                    usados[op] = usados.get(op, 0) + 1
                cond.update(condicoes_de_while(insns))
            item = {
                "sala": rid,
                "func": fi,
                "raiz": raizes[fi],
                "funcs": sorted(alc),
                "n_insn": n_insn,
                "opcodes": ["0x%02x" % k for k in sorted(usados)],
                "cond_while": sorted("0x%02x" % c for c in cond),
            }
            cenas.append(item)
            for op, n in usados.items():
                e = ops.setdefault(op, {"n": 0, "salas": set(), "cenas": 0})
                e["n"] += n
                e["salas"].add(rid)
                e["cenas"] += 1
        por_sala[rid] = {
            "n_funcs": len(res),
            "raizes": {str(k): v for k, v in sorted(raizes.items())},
            "desconhecidos_no_decode": sorted("0x%02x" % u for u in unk),
        }
    return ops, cenas, por_sala


def main():
    uma = None
    if "--sala" in sys.argv:
        uma = sys.argv[sys.argv.index("--sala") + 1].upper()
    ops, cenas, por_sala = censo(uma)

    tabela = {}
    for op in sorted(ops):
        nome, det = OPCODE_SEM.get(op, ("?", "sem handler medido"))
        tabela["0x%02x" % op] = {
            "nome": nome,
            "handler": det,
            "classe": CLASSE_DE.get(op, "desconhecido"),
            "tamanho": SIZES.get(op),
            "ocorrencias": ops[op]["n"],
            "salas": len(ops[op]["salas"]),
            "cenas": ops[op]["cenas"],
        }
    # condicoes de `while` agregadas: e' o criterio de "a cena pode rodar"
    cond = {}
    for c in cenas:
        for k in c["cond_while"]:
            cond[k] = cond.get(k, 0) + 1

    saida = {
        "_meta": {
            "descricao": "Censo dos opcodes usados pelas FUNCOES DE CENA das salas do RE3 "
                         "(NTSC-U, SLUS_009.23). Gerado por tools/scd_cena_censo.py.",
            "raizes": "0x04/0x03 evt_exec (0x80052ea4) e payload de AOT sce 5 (0x800512bc); "
                      "fechamento por 0x19 gosub e 0x03/0x04 thread",
            "decode": "linear por funcao (tools/scd_decode.py), visita os dois ramos de cada if",
            "n_salas": len(por_sala),
            "n_cenas": len(cenas),
            "n_opcodes": len(tabela),
        },
        "opcodes": tabela,
        "condicoes_de_while": cond,
        "cenas": cenas,
        "por_sala": por_sala,
    }
    os.makedirs(os.path.dirname(SAIDA), exist_ok=True)
    with open(SAIDA, "w", encoding="utf-8") as f:
        json.dump(saida, f, indent=1, ensure_ascii=False, sort_keys=False)

    print("salas: %d   funcoes de cena: %d   opcodes distintos: %d" % (
        len(por_sala), len(cenas), len(tabela)))
    print("\n%-6s %-5s %-6s %-6s %-12s %s" % (
        "op", "salas", "cenas", "vezes", "classe", "nome"))
    for k in sorted(tabela, key=lambda k: -tabela[k]["salas"]):
        t = tabela[k]
        print("%-6s %-5d %-6d %-6d %-12s %s" % (
            k, t["salas"], t["cenas"], t["ocorrencias"], t["classe"], t["nome"][:52]))
    print("\nCONDICOES DE `while` (o unico lugar onde opcode nao implementado PRENDE a cena):")
    for k in sorted(cond, key=lambda k: -cond[k]):
        nm = OPCODE_SEM.get(int(k, 16), ("?",))[0]
        print("  %-6s %4d cenas   %s" % (k, cond[k], nm))
    print("\nJSON: %s" % SAIDA)


if __name__ == "__main__":
    main()
