#!/usr/bin/env python3
"""Gera docs/port/PROGRESSO.md a partir de docs/port/port_progress.json.

Tracker do PORT 1:1 para Godot (pasta port/). Dois eixos por item:
  impl  = código existe no port/ e roda
  valid = conferido contra o original pelo critério do item

Fonte única de verdade = port_progress.json; este script só RENDERIZA
(nunca edite o .md à mão). Companheiro de docs/port/PLANO_MIGRACAO.md.

Uso:  python tools/port_progress.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "port", "port_progress.json")
OUT = os.path.join(ROOT, "docs", "port", "PROGRESSO.md")


def bar(pct, width=20):
    fill = int(round(pct / 100.0 * width))
    return "█" * fill + "░" * (width - fill)


def wavg(items, key):
    tw = sum(i["peso"] for i in items)
    if tw == 0:
        return 0.0
    return sum(i["peso"] * i[key] for i in items) / tw


def box(item):
    """Checkbox de 3 estados: [ ] a fazer · [~] em andamento/implementado · [x] validado."""
    if item["valid"] >= 100:
        return "[x]"
    if item["impl"] > 0:
        return "[~]"
    return "[ ]"


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    meta, fases, itens = d["_meta"], d["fases"], d["itens"]

    impl = wavg(itens, "impl")
    valid = wavg(itens, "valid")
    n_done = sum(1 for i in itens if i["valid"] >= 100)
    n_wip = sum(1 for i in itens if i["valid"] < 100 and i["impl"] > 0)

    L = []
    L.append("# Port 1:1 RE3 → Godot — PROGRESSO")
    L.append("")
    L.append("> **GERADO** por `tools/port_progress.py` a partir de "
             "[`port_progress.json`](port_progress.json). Não edite à mão — edite o JSON e rode o script.")
    L.append(">")
    L.append(f"> Estratégia e critérios em [`PLANO_MIGRACAO.md`](PLANO_MIGRACAO.md). "
             f"Destino: **`{meta['pasta_destino']}`**. Escopo: {meta['decisoes']['escopo']}.")
    L.append(">")
    L.append("> **impl** = código existe no port/ e roda · **valid** = conferido contra o original "
             "pelo critério do item. Checkbox: `[ ]` a fazer · `[~]` implementado, não validado · `[x]` validado.")
    L.append("")
    L.append(f"## Geral (ponderado por peso, {len(itens)} itens)")
    L.append("")
    L.append(f"- **Implementado:** `{bar(impl)}` **{impl:.0f}%**")
    L.append(f"- **Validado:**    `{bar(valid)}` **{valid:.0f}%**")
    L.append(f"- Itens: **{n_done} validados** · **{n_wip} em andamento** · "
             f"**{len(itens) - n_done - n_wip} a fazer**")
    L.append("")

    L.append("## Por fase")
    L.append("")
    L.append("| Fase | Título | O QUÊ (entrega) | COMO se prova (gate) | Itens | Impl | Valid |")
    L.append("|---|---|---|---|--:|---|---|")
    for f in fases:
        its = [i for i in itens if i["fase"] == f["id"]]
        fi, fv = wavg(its, "impl"), wavg(its, "valid")
        L.append(f"| **{f['id']}** | {f['titulo']} | {f.get('o_que','—')} | "
                 f"{f.get('como_prova','—')} | {len(its)} | "
                 f"{bar(fi,8)} {fi:.0f}% | {bar(fv,8)} {fv:.0f}% |")
    L.append("")

    L.append("## Checklist por fase")
    for f in fases:
        its = [i for i in itens if i["fase"] == f["id"]]
        fi, fv = wavg(its, "impl"), wavg(its, "valid")
        L.append("")
        L.append(f"### {f['id']} — {f['titulo']}  ·  impl {fi:.0f}% / valid {fv:.0f}%")
        L.append("")
        L.append(f"**Objetivo:** {f['objetivo']}")
        L.append("")
        L.append(f"**Gate de saída:** {f['gate']}")
        L.append("")
        for i in its:
            L.append(f"- {box(i)} **{i['id']}** (peso {i['peso']}, impl {i['impl']}%, valid {i['valid']}%) — {i['titulo']}")
            L.append(f"  - **Validação:** {i['criterio']}")
            if i.get("fonte") and i["fonte"] != "—":
                L.append(f"  - **Fonte:** {i['fonte']}")
            if i.get("reuso") and i["reuso"] != "—":
                L.append(f"  - **Reaproveita:** {i['reuso']}")
            if i.get("nota"):
                L.append(f"  - **Nota:** {i['nota']}")
    L.append("")

    # próximo trabalho: primeiros itens não iniciados, na ordem das fases
    L.append("## Próximo trabalho (ordem do plano)")
    L.append("")
    pend = [i for i in itens if i["valid"] < 100]
    for i in pend[:5]:
        L.append(f"1. **{i['id']}** — {i['titulo']}")
    if not pend:
        L.append("- Nada pendente: todos os itens validados.")
    L.append("")

    # radar de risco: itens de peso alto ainda não implementados
    L.append("## Radar — peso alto ainda não implementado (peso ≥ 4, impl 0%)")
    L.append("")
    risco = [i for i in itens if i["peso"] >= 4 and i["impl"] == 0]
    for i in sorted(risco, key=lambda x: (-x["peso"], x["id"])):
        nota = f" — {i['nota']}" if i.get("nota") else ""
        L.append(f"- **{i['id']}** (peso {i['peso']}, {i['fase']}): {i['titulo']}{nota}")
    L.append("")

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))
    print(f"OK -> {OUT}")
    print(f"impl={impl:.1f}%  valid={valid:.1f}%  ({len(itens)} itens, "
          f"{n_done} validados, {n_wip} em andamento)")


if __name__ == "__main__":
    main()
