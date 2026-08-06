#!/usr/bin/env python3
"""Gera docs/decomp/PROGRESS.md a partir de docs/decomp/progress.json.

Método inspirado em decomp.dev: cada UNIDADE de conteúdo tem % 'decompilado' e
% 'vinculado' (integrado no protótipo Godot), ponderados por 'peso'. Fonte única
de verdade = progress.json; este script só RENDERIZA (nunca edite o .md à mão).

Uso:  python tools/decomp_progress.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "decomp", "progress.json")
OUT = os.path.join(ROOT, "docs", "decomp", "PROGRESS.md")


def bar(pct, width=20):
    fill = int(round(pct / 100.0 * width))
    return "█" * fill + "░" * (width - fill)


def wavg(units, key):
    tw = sum(u["peso"] for u in units)
    if tw == 0:
        return 0.0
    return sum(u["peso"] * u[key] for u in units) / tw


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    cats = d["categorias"]
    all_units = [u for c in cats for u in c["unidades"]]

    dec = wavg(all_units, "decompilado")
    lnk = wavg(all_units, "vinculado")

    L = []
    L.append("# Decompilação de conteúdo RE3 — PROGRESSO")
    L.append("")
    L.append("> **GERADO** por `tools/decomp_progress.py` a partir de "
             "[`progress.json`](progress.json). Não edite à mão — edite o JSON e rode o script.")
    L.append(">")
    L.append("> Método (decomp.dev-adaptado): decompila o **conteúdo** (formatos/assets/lógica), "
             "não binário nativo. **decompilado** = entendemos+extraímos · **vinculado** = ligado no protótipo Godot.")
    L.append("")
    L.append(f"## Geral (ponderado por peso, {len(all_units)} unidades)")
    L.append("")
    L.append(f"- **Decompilado:** `{bar(dec)}` **{dec:.0f}%**")
    L.append(f"- **Vinculado:**  `{bar(lnk)}` **{lnk:.0f}%**")
    L.append("")

    # resumo por categoria
    L.append("## Por categoria")
    L.append("")
    L.append("| Categoria | Decompilado | Vinculado |")
    L.append("|---|---|---|")
    for c in cats:
        cd = wavg(c["unidades"], "decompilado")
        cl = wavg(c["unidades"], "vinculado")
        L.append(f"| {c['nome']} | {bar(cd,12)} {cd:.0f}% | {bar(cl,12)} {cl:.0f}% |")
    L.append("")

    # detalhe por unidade
    L.append("## Detalhe por unidade")
    for c in cats:
        L.append("")
        L.append(f"### {c['nome']}")
        L.append("")
        L.append("| Unidade | P | Dec% | Vinc% | Ferramenta | Doc | Nota |")
        L.append("|---|--:|--:|--:|---|---|---|")
        for u in c["unidades"]:
            L.append(f"| {u['nome']} | {u['peso']} | {u['decompilado']} | {u['vinculado']} | "
                     f"`{u['tool']}` | {u['doc']} | {u['nota']} |")
    L.append("")

    # bloqueios e não-iniciados (radar)
    blockers = [u for u in all_units if u["decompilado"] < 50]
    L.append("## Radar — bloqueios / baixo decompilado (<50%)")
    L.append("")
    for u in sorted(blockers, key=lambda x: (x["decompilado"], -x["peso"])):
        L.append(f"- **{u['nome']}** (dec {u['decompilado']}%, peso {u['peso']}): {u['nota']}")
    L.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"OK -> {OUT}")
    print(f"decompilado={dec:.1f}%  vinculado={lnk:.1f}%  ({len(all_units)} unidades)")


if __name__ == "__main__":
    main()
