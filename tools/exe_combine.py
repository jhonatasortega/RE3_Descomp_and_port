#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Extrator da TABELA DE COMBINACAO (receitas) do RE3 PS1 NTSC-U (SLUS_009.23).

De onde saem os dados (tudo lido do EXE, base 0x80010000):

  0x800a0514  DESCRITOR DE ITEM, 4 bytes por item_id, 0xac entradas (0x00..0xab):
                +0  u8  cat    categoria (1=arma 2=municao 3=cura 4=key_item
                               5=chave 6=ferramenta 7=arquivo 8=mapa, 0=nenhum)
                +1  u8  max    capacidade/stack maximo do slot
                +2  u8  bit    indice de bit no bitfield gs+0x7910 (setado ao dar CHECK)
                +3  u8  flags  flags default gravadas no slot ao pegar o item

  0x800a07c4  TABELA DE COMBINACAO, 8 bytes por registro, terminador rec[1]==0xFF
              (o terminador esta em 0x800a0bac). Busca LINEAR e SIMETRICA em
              `0x8006a898 combine_find(a1=idA, a2=idB)`:
                +0  u8  kind   tipo de receita (0..6) -- ver KIND_DOC
                +1  u8  a      item A
                +2  u8  b      item B
                +3  u8  c      item resultante (0 = nenhum item novo)
                +4  u8  n      quantidade/param (significado depende de kind)
                +5..7          zero (padding)

  0x800a0bb4  TABELA DE TRANSFORMACAO POR ITEM, 4 bytes por registro, terminador
              rec[1]==0xFF. Busca linear por rec[1] em `0x8006a918`.
                +0 u8 ? , +1 u8 item, +2 u8 resultado, +3 u8 ?

  0x800a0bc4  ARMA -> MUNICAO, 4 bytes por registro, terminador rec[0]==0xFF.
              Busca linear por rec[0] em `0x8006a95c ammo_for_weapon(a1=weapon_id)`.
                +0 u8 weapon_id , +1 u8 ammo_id

  0x800a00ec  GRUPO DE MUNICAO (para o bonus de polvora), 2 bytes por registro,
              terminador 0xFF: {+0 ammo_id, +1 grupo 0..3}.

  0x800a0bf4  BONUS DE POLVORA: 4 blocos (grupo 0..3) x 5 registros de 4 bytes
              {+0 limiar u8, +1 bonus u8}. O jogo acha o 1o registro com
              limiar >= contador e usa esse bonus (em decimos):
              qty = n + round(n*bonus/10).  contador = *(u16*)(inv+0x12c+grupo*2).

Uso:
    python tools/exe_combine.py                 # dump legivel no terminal
    python tools/exe_combine.py --json ARQUIVO  # grava JSON (default:
                                                # port/data/re3_combinacoes.json)

Formato do JSON: ver a chave "_meta" do arquivo gerado.
"""
import sys, os, json, struct

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from exe_parse import Exe

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE_PATH = os.path.join(REPO, "extracted", "ntsc-u", "SLUS_009.23")
OUT_JSON = os.path.join(REPO, "port", "data", "re3_combinacoes.json")
ITEMS_JSON = os.path.join(REPO, "port", "data", "re3_items.json")

DESC = 0x800A0514        # descritor de item (4 B/id)
DESC_N = 0xAC            # 0x00..0xab
COMBINE = 0x800A07C4     # tabela de receitas (8 B/reg)
XFORM = 0x800A0BB4       # transformacao por item (4 B/reg)
W2A = 0x800A0BC4         # arma -> municao (4 B/reg)
AMMOGRP = 0x800A00EC     # municao -> grupo (2 B/reg)
POWDER = 0x800A0BF4      # bonus de polvora (4 blocos x 5 x 4 B)

CAT = {0: "nenhum", 1: "arma", 2: "municao", 3: "cura", 4: "key_item",
       5: "chave", 6: "ferramenta", 7: "arquivo", 8: "mapa"}

KIND_DOC = {
    0: ("recarregar_arma",
        "A=arma, B=municao, C=0. Transfere min(desc[A].max - A.qtd, B.qtd) balas "
        "da municao para a arma. n nao e usado. Handler 0x800684dc."),
    1: ("simples",
        "A+B -> C com quantidade n. O slot que contem A e SOBRESCRITO por C; o slot "
        "que contem B e zerado. Handler 0x800685cc / final 0x80068d14."),
    2: ("polvora_municao",
        "A=0x82 Reloading Tool, B=polvora, C=municao criada, n=quantidade BASE. "
        "A quantidade final recebe o bonus de pericia (tabela 0x800a0bf4) e o "
        "Reloading Tool perde 1 unidade. Handler 0x8006860c, pre-calculo 0x80068080."),
    3: ("upgrade_arma",
        "A=arma, B=municao especial, C=arma resultante, n nao usado. Exige a arma "
        "VAZIA (senao mensagem 8); se a arma tem municao infinita (flags&3==3) a "
        "municao antiga e devolvida via tabela 0x80010ebc. Handler 0x800686ac."),
    4: ("troca_granada",
        "A=lanca-granadas, B=municao nova, C=lanca-granadas resultante, "
        "n=item_id da municao ANTIGA que e devolvida ao inventario. "
        "Handler 0x80068854."),
    5: ("polvora_granada",
        "A=0x18 Grenade Rounds, B=polvora, C=municao resultante, n=quantidade base. "
        "Consome 6 unidades de A (ou o resto todo, com quantidade proporcional "
        "n*qtd/6). Bonus usa SEMPRE o bloco 3 e o contador inv+0x132. "
        "Handler 0x800688d8, pre-calculo 0x80068264."),
    6: ("municao_infinita",
        "A=arma, B=0x6e Inf. Bullets, C=0. Marca a arma como municao infinita "
        "(o slot de B e consumido). Handler 0x80068978."),
}


def le_nomes():
    """nomes EN por item_id (de port/data/re3_items.json, se existir)."""
    try:
        d = json.load(open(ITEMS_JSON, encoding="utf-8"))
    except Exception:
        return {}
    out = {}
    for k, v in d.get("by_id", {}).items():
        out[int(k, 16)] = v.get("name_en")
    return out


def descritores(e):
    out = []
    for i in range(DESC_N):
        b = e.bytes_at(DESC + i * 4, 4)
        out.append({"id": i, "cat": b[0], "cat_nome": CAT.get(b[0], "?"),
                    "max": b[1], "bit_check": b[2], "flags_default": b[3]})
    return out


def receitas(e):
    """Le a tabela de combinacao ate o terminador rec[1]==0xFF (mesmo teste do EXE).

    Marca `alternativa_de` nos registros cuja chave (A,B) -- simetrica -- ja apareceu
    antes: como a busca do jogo e LINEAR, esses registros so sao alcancados quando o
    codigo avanca o ponteiro em +8 (a pergunta "municao normal ou melhorada?").
    """
    out = []
    vistos = {}
    a = COMBINE
    while True:
        b = e.bytes_at(a, 8)
        if b[1] == 0xFF:
            break
        chave = tuple(sorted((b[1], b[2])))
        r = {"addr": "0x%08x" % a, "kind": b[0],
             "kind_nome": KIND_DOC[b[0]][0] if b[0] in KIND_DOC else "?",
             "a": b[1], "b": b[2], "c": b[3], "n": b[4],
             "raw": " ".join("%02x" % x for x in b),
             "alternativa_de": vistos.get(chave)}
        vistos.setdefault(chave, r["addr"])
        out.append(r)
        a += 8
        if a > COMBINE + 0x2000:
            raise RuntimeError("sem terminador")
    return out, a


def transformacoes(e):
    out = []
    a = XFORM
    while True:
        b = e.bytes_at(a, 4)
        if b[1] == 0xFF:
            break
        out.append({"addr": "0x%08x" % a, "f0": b[0], "item": b[1],
                    "resultado": b[2], "f3": b[3]})
        a += 4
    return out, a


def arma_municao(e):
    out = []
    a = W2A
    while True:
        b = e.bytes_at(a, 4)
        if b[0] == 0xFF:
            break
        out.append({"addr": "0x%08x" % a, "arma": b[0], "municao": b[1]})
        a += 4
    return out, a


def grupos_municao(e):
    out = []
    a = AMMOGRP
    while True:
        b = e.bytes_at(a, 2)
        if b[0] == 0xFF:
            break
        out.append({"addr": "0x%08x" % a, "municao": b[0], "grupo": b[1]})
        a += 2
    return out, a


def bonus_polvora(e):
    blocos = []
    for g in range(4):
        regs = []
        for i in range(5):
            a = POWDER + g * 20 + i * 4
            b = e.bytes_at(a, 4)
            regs.append({"limiar": b[0], "bonus_decimos": b[1]})
        blocos.append(regs)
    return blocos


def main():
    e = Exe(EXE_PATH)
    nomes = le_nomes()
    desc = descritores(e)
    recs, rec_end = receitas(e)
    xf, xf_end = transformacoes(e)
    w2a, w2a_end = arma_municao(e)
    grp, grp_end = grupos_municao(e)
    pw = bonus_polvora(e)

    def nm(i):
        return nomes.get(i) or ("0x%02x" % i)

    if "--json" not in sys.argv:
        print("== descritor de item 0x%08x (%d entradas) ==" % (DESC, DESC_N))
        for d in desc:
            if d["cat"] or d["max"] or d["bit_check"] or d["flags_default"]:
                print("  0x%02x %-22s cat=%d(%-11s) max=%-3d bit=0x%02x flags=0x%02x"
                      % (d["id"], nm(d["id"]), d["cat"], d["cat_nome"],
                         d["max"], d["bit_check"], d["flags_default"]))
        print()
        print("== receitas 0x%08x .. 0x%08x (%d registros, terminador em 0x%08x) =="
              % (COMBINE, rec_end - 8, len(recs), rec_end))
        for r in recs:
            print("  %s k=%d %-18s %-22s + %-22s -> %-22s n=%d"
                  % (r["addr"], r["kind"], r["kind_nome"], nm(r["a"]), nm(r["b"]),
                     nm(r["c"]) if r["c"] else "(nada)", r["n"]))
        print()
        print("== arma -> municao 0x%08x (%d) ==" % (W2A, len(w2a)))
        for r in w2a:
            print("  %-22s -> %s" % (nm(r["arma"]), nm(r["municao"])))
        print()
        print("== municao -> grupo de polvora 0x%08x (%d) ==" % (AMMOGRP, len(grp)))
        for r in grp:
            print("  %-22s grupo %d" % (nm(r["municao"]), r["grupo"]))
        print()
        print("== bonus de polvora 0x%08x ==" % POWDER)
        for g, regs in enumerate(pw):
            print("  grupo %d: %s" % (g, "  ".join(
                "cnt<=%d:+%d0%%" % (x["limiar"], x["bonus_decimos"]) for x in regs)))
        print()
        print("== transformacao por item 0x%08x (%d) ==" % (XFORM, len(xf)))
        for r in xf:
            print("  %-22s -> %-22s (f0=%d f3=%d)"
                  % (nm(r["item"]), nm(r["resultado"]), r["f0"], r["f3"]))
        return

    out_path = OUT_JSON
    args = sys.argv[sys.argv.index("--json") + 1:]
    if args:
        out_path = args[0]

    for r in recs:
        r["a_nome"] = nm(r["a"])
        r["b_nome"] = nm(r["b"])
        r["c_nome"] = nm(r["c"]) if r["c"] else None
    for r in w2a:
        r["arma_nome"] = nm(r["arma"])
        r["municao_nome"] = nm(r["municao"])
    for r in grp:
        r["municao_nome"] = nm(r["municao"])
    for r in xf:
        r["item_nome"] = nm(r["item"])
        r["resultado_nome"] = nm(r["resultado"])

    doc = {
        "_meta": {
            "descricao": "Tabelas de COMBINACAO/receita do RE3 PS1 NTSC-U, lidas byte-a-byte "
                         "do SLUS_009.23. Nada aqui foi inventado.",
            "exe": "extracted/ntsc-u/SLUS_009.23 (PS-X EXE, base 0x80010000)",
            "ferramenta": "tools/exe_combine.py (--json)",
            "nota": "docs/decomp/notes/menu_comandos.md",
            "enderecos": {
                "descritor_item": "0x800a0514 (4 B x 0xac)",
                "receitas": "0x800a07c4 (8 B/reg, terminador rec[1]==0xFF em 0x%08x)" % rec_end,
                "busca_receita": "0x8006a898 combine_find(a1=idA,a2=idB) - linear, simetrica",
                "arma_para_municao": "0x800a0bc4 (4 B/reg, terminador rec[0]==0xFF), busca 0x8006a95c",
                "transformacao_item": "0x800a0bb4 (4 B/reg, terminador rec[1]==0xFF), busca 0x8006a918",
                "municao_para_grupo": "0x800a00ec (2 B/reg, terminador 0xFF)",
                "bonus_polvora": "0x800a0bf4 (4 blocos x 5 regs de 4 B)",
                "dispatch_por_kind": "0x80010e9c (7 entradas), executor 0x80068024",
                "dispatch_final": "0x80010f04 (8 entradas, indexado por ctx+0x64)",
                "devolve_municao_upgrade": "0x80010ebc (18 entradas, item_id-2)",
            },
            "layout_receita": {
                "+0": "u8 kind (0..6)",
                "+1": "u8 item A",
                "+2": "u8 item B",
                "+3": "u8 item resultante (0 = nenhum)",
                "+4": "u8 n (quantidade ou param, depende do kind)",
                "+5..+7": "zero",
            },
            "kinds": {str(k): {"nome": v[0], "doc": v[1]} for k, v in KIND_DOC.items()},
            "regra_de_slot": "O slot que contem o item A da receita e SOBRESCRITO pelo "
                             "resultado; o slot que contem o item B e zerado (para kind 2/5 a "
                             "escolha e invertida pelo pre-calculo -- ver a nota).",
            "bonus_polvora_formula": "grupo = 0x800a00ec[municao]; cnt = *(u16*)(inv+0x12c+grupo*2); "
                                     "acha o 1o registro com limiar >= cnt; "
                                     "qty = n + arredonda(n*bonus/10); cnt += 1. "
                                     "Se flag_test(0x800cc858, bit 0x17) entao qty *= 2.",
            "receitas_alternativas": "8 pares de registros de kind 2 tem a MESMA chave (A,B). "
                                     "A busca linear sempre acha o 1o (municao normal). O 2o "
                                     "(municao 'E') e alcancado quando o grupo e 0 ou 1 e "
                                     "cnt > 6: o jogo mostra a pergunta (mensagem 0xd no canal "
                                     "0x1400, sitio 0x80067da8) e, se a resposta em 0x800d1f80 "
                                     "for 0, faz ctx[0x58] += 8 (0x80068b98) antes de executar. "
                                     "O campo 'alternativa_de' aponta o registro anterior.",
        },
        "descritor_item": desc,
        "receitas": recs,
        "arma_para_municao": w2a,
        "municao_para_grupo": grp,
        "bonus_polvora": pw,
        "transformacao_item": xf,
    }
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print("gravado %s (%d receitas)" % (out_path, len(recs)))


if __name__ == "__main__":
    main()
