#!/usr/bin/env python3
"""De-para das paginas de documento em **HD e PORTUGUES** do pack `hires/memo`.

O ACHADO
--------
O `hires/memo` do usuario tem **280 arquivos 1024x768** e eles sao DOIS conjuntos:

  * 137 arquivos de 2025-01-17, luminancia maxima 214 -> paginas em **RUSSO**
    (o Seamless HD Project e russo; foi esse conjunto que meu casamento por
    conteudo pegou antes, e por isso dava pagina trocada);
  * 143 arquivos de 2025-06-07/09/10, luminancia maxima 255 -> paginas em
    **PORTUGUES**, tipografadas de novo (fonte serifada proporcional) e com as
    tabelas de polvora redesenhadas com renders HD dos itens.

Ou seja: o texto dos documentos em PT-BR EXISTE em HD. O que nao existe e o
de-para: o nome do arquivo e um hash (testei CRC32/Adler32 do TIM, do corpo e do
CLUT do `FILEGU.PIX` do PS1 e do `FILEGJ.PIX` do PC: **zero acertos**), e a ordem
de mtime nao e a ordem de leitura (o tradutor fez paginas fora de ordem).

COMO O DE-PARA FOI FEITO (e por que ele fecha)
----------------------------------------------
Montei folhas de contato com o topo de cada uma das 143 paginas PT em ordem de
mtime, li todas, e casei cada uma com a pagina SD em ingles correspondente
(`assets/FILE/pag_NNN.png`, extraida do `FILEGU.PIX`). O casamento se auto-valida
em tres contas independentes:

  1. **143 = 146 - 3.** O SD tem 152 paginas de texto, das quais **6 sao em
     branco** (112, 138, 143, 151, 155, 160) -> 146 com conteudo. O conjunto PT
     nao traduziu pagina em branco, e falta exatamente 3 paginas de "rabicho"
     (uma linha solta): SD 56, 75 e 86.
  2. **Cada documento fecha.** A contagem por documento do conjunto PT bate com
     (paginas de texto SD - brancas) em 28 dos 31 documentos, e nos outros 3
     (doc8, doc11, doc13) falta a pagina de rabicho do item 1.
  3. **A sequencia interna bate frase a frase.** Ex.: o Diario da Jill fecha 1:1
     (SD 177 "August 7th" = PT "7 de Agosto"; SD 179 "...gave me a wink" = PT
     "apenas piscou para mim"; SD 183 "somewhere in Europe" = PT "em algum lugar
     da Europa"), mesmo com o tradutor tendo feito 15/Ago ANTES de 7/Ago.

Saida: `port/data/hd_memo_pt.json` (o de-para, versionado) e os arquivos copiados
como `port/assets/FILE/pt/pag_NNN.webp` (asset, nao versionado).

Uso: python tools/memo_pt.py [--hires CAMINHO]
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HIRES_PADRAO = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3\hires"
# Os dois conjuntos se separam pela data de modificacao: o russo veio com o pack
# (janeiro/2025), o portugues foi adicionado depois (junho/2025).
CORTE_MTIME = 1748000000  # 2025-05-23

# indice na ordem de mtime do conjunto PT  ->  numero da pagina SD (pag_NNN.png)
# Lido por mim nas folhas de contato; cada linha e um documento.
DE_PARA = {
    # doc29 Foto secreta / doc10 Cartao postal de arte / doc27 Cartao da torre
    0: 172, 1: 173, 2: 174,
    3: 67, 4: 68, 5: 69,
    6: 158, 7: 159, 8: 161,
    # doc30 Diario da Jill (o tradutor fez 15/Ago antes de 7/Ago)
    9: 176, 10: 180, 11: 181, 12: 177, 13: 178, 14: 179, 15: 182, 16: 183,
    # doc13 Diario do diretor (falta o rabicho SD 86)
    17: 82, 18: 83, 19: 84, 20: 85, 21: 87,
    # doc14 Diario do gerente
    22: 89, 23: 90, 24: 91, 25: 92, 26: 93, 27: 94, 28: 95, 29: 96,
    # doc2 Diario do mercenario
    30: 18, 31: 19, 32: 20, 33: 21, 34: 22, 35: 23, 36: 24,
    # doc20 Fax do Q.G. (conteudo veio antes do titulo)
    37: 129, 38: 128,
    # doc17 Fax da Kendo (SD 112 e em branco)
    39: 109, 40: 110, 41: 111, 42: 113, 43: 114,
    # doc3 Fax comercial
    44: 26, 45: 27,
    # doc22..doc26 fotos: 5 titulos seguidos, depois os 8 versos
    46: 136, 47: 141, 48: 146, 49: 153, 50: 149,
    51: 137, 52: 139, 53: 142, 54: 144, 55: 147, 56: 154, 57: 156, 58: 150,
    # doc6 Guia da cidade
    59: 41, 60: 42, 61: 43, 62: 44, 63: 45,
    # doc8 Instrucao de operacao (falta o rabicho SD 56)
    64: 54, 65: 55, 66: 57, 67: 58,
    # doc0 / doc28: os dois titulos, depois o corpo de A e o de B
    68: 2, 69: 163,
    70: 3, 71: 4, 72: 5, 73: 6, 74: 7, 75: 8, 76: 9, 77: 10,
    78: 164, 79: 167,
    # doc9 Bloquinho do mercenario
    80: 60, 81: 61, 82: 62, 83: 63, 84: 64, 85: 65,
    # doc19 Manual de instrucao medica
    86: 123, 87: 124, 88: 125, 89: 126,
    # doc15 Manual de seguranca
    90: 98, 91: 99, 92: 100, 93: 101,
    # doc21 Manual do incinerador
    94: 131, 95: 132, 96: 133, 97: 134,
    # doc5 Memorando do David
    98: 35, 99: 36, 100: 37, 101: 38, 102: 39,
    # doc1 Memorando do Dario
    103: 12, 104: 13, 105: 14, 106: 15, 107: 16,
    # doc16 Memorando do mecanico
    108: 103, 109: 104, 110: 105, 111: 106, 112: 107,
    # doc7 Memorando do reporter
    113: 47, 114: 48, 115: 49, 116: 50, 117: 51, 118: 52,
    # doc12 Ordens escritas
    119: 78, 120: 79, 121: 80,
    # doc4 Relatorio do Marvin
    122: 29, 123: 30, 124: 31, 125: 32, 126: 33,
    # doc18 Relatorio do gerente
    127: 116, 128: 117, 129: 118, 130: 119, 131: 120, 132: 121,
    # doc11 Relatorio do supervisor (falta o rabicho SD 75)
    133: 71, 134: 72, 135: 73, 136: 74, 137: 76,
    # doc28 Instrucoes de jogo B: o resto do corpo, refeito em 10/jun com tabelas
    138: 165, 139: 166, 140: 168, 141: 170, 142: 169,
}
# As paginas SD que o conjunto PT nao cobre, e por que.
SEM_PT = {
    112: "em branco no SD",
    138: "em branco no SD",
    143: "em branco no SD",
    151: "em branco no SD",
    155: "em branco no SD",
    160: "em branco no SD",
    56: "rabicho de uma linha nao traduzido (doc8)",
    75: "rabicho de uma linha nao traduzido (doc11)",
    86: "rabicho de uma linha nao traduzido (doc13)",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hires", default=HIRES_PADRAO)
    ap.add_argument("--sem-copia", action="store_true", help="só valida e grava o JSON")
    a = ap.parse_args()

    pasta = os.path.join(a.hires, "memo")
    if not os.path.isdir(pasta):
        print("memo/ ausente em %s" % a.hires, file=sys.stderr)
        return 1
    pt = sorted(
        (os.stat(os.path.join(pasta, f)).st_mtime, f)
        for f in os.listdir(pasta)
        if f.lower().endswith(".webp") and os.stat(os.path.join(pasta, f)).st_mtime > CORTE_MTIME
    )
    print("conjunto PT: %d arquivos" % len(pt))
    if len(pt) != len(DE_PARA):
        print(
            "ERRO: o de-para tem %d entradas e a pasta tem %d arquivos PT.\n"
            "O de-para e por ORDEM DE MTIME; se o pack mudou, refaca as folhas de contato."
            % (len(DE_PARA), len(pt)),
            file=sys.stderr,
        )
        return 2

    with open(os.path.join(RAIZ, "port", "data", "re3_file_screen.json"), encoding="utf-8") as f:
        tela = json.load(f)
    validas = {int(p["page"]) for p in tela["paginas"]}
    alvos = list(DE_PARA.values())
    if len(set(alvos)) != len(alvos):
        print("ERRO: pagina SD repetida no de-para", file=sys.stderr)
        return 3
    fora = [p for p in alvos if p not in validas]
    if fora:
        print("ERRO: paginas fora do indice: %s" % fora, file=sys.stderr)
        return 4

    # confere documento por documento
    texto_por_doc = {int(d["doc"]): [int(x) for x in d["text_pages"]] for d in tela["documentos"]}
    mapa = {}
    for i, (_m, nome) in enumerate(pt):
        mapa[DE_PARA[i]] = nome[:-5]  # sem .webp
    resumo = []
    for doc, paginas in sorted(texto_por_doc.items()):
        com = [p for p in paginas if p in mapa]
        falta = [p for p in paginas if p not in mapa]
        for p in falta:
            if p not in SEM_PT:
                print("ERRO: doc%d pagina %d sem PT e sem explicacao" % (doc, p), file=sys.stderr)
                return 5
        resumo.append((doc, len(paginas), len(com)))
    print("documentos: %d · paginas com PT: %d de %d"
          % (len(resumo), sum(r[2] for r in resumo), sum(r[1] for r in resumo)))

    saida = {
        "fonte": "hires/memo (conjunto de junho/2025 = portugues; o de janeiro e russo)",
        "n": len(mapa),
        "sem_pt": {str(k): v for k, v in sorted(SEM_PT.items())},
        "paginas": {str(k): v for k, v in sorted(mapa.items())},
    }
    destino_json = os.path.join(RAIZ, "port", "data", "hd_memo_pt.json")
    with open(destino_json, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, indent=1)
    print("gravado %s" % os.path.relpath(destino_json, RAIZ))

    if a.sem_copia:
        return 0
    destino = os.path.join(RAIZ, "port", "assets", "FILE", "pt")
    os.makedirs(destino, exist_ok=True)
    for pagina, nome in mapa.items():
        shutil.copyfile(
            os.path.join(pasta, "%s.webp" % nome),
            os.path.join(destino, "pag_%03d.webp" % pagina),
        )
    print("copiadas %d paginas para assets/FILE/pt/" % len(mapa))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
