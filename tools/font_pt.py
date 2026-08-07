#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""De-para de CARACTERE -> codigo de glifo do RE3, incluindo os ACENTOS do portugues.

Por que existe: a tabela de larguras do EXE (`0x80098dd0`, 87 entradas) cobre os codigos
`0x00..0x56`, que sao ASCII. Os glifos ACENTUADOS ficam nos codigos `0x57..0x9x` e o EXE nao
guarda um de-para "caractere unicode -> codigo" — ele recebe o texto JA CODIFICADO (as strings
do jogo sao bytes de codigo, nao ASCII). Sem esse de-para, escrever "acao" com cedilha e til
some com as letras.

Quem tem o de-para completo e o **mod de traducao**, que precisou dele para reescrever os textos:

    <raiz do jogo>/mod_BH3_Portuguese/encoding.xml
    <Entry Encode="0x8B" Char="a-com-acento" width="9" indent="3"/>

Sao 160 entradas com `Encode` (codigo do glifo), `Char` (o caractere), `width` (avanco) e
`indent` (quanto pular a esquerda dentro da celula). Os campos `width`/`indent` sao as metricas
do mod para a fonte HD; para o SD valem as do EXE (ver `re3_font.json`).

Uso:
    python tools/font_pt.py                      # grava <out>/data/re3_font_pt.json
    python tools/font_pt.py --mod <caminho>      # se o mod estiver em outro lugar
"""
import os
import re
import sys
import json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import paths                                                        # noqa: E402

# ── DE-PARA DA FONTE HD (atlas `misc/AED42717`) ──
# O `encoding.xml` do mod mapeia para a FONTE ALTERNATIVA dele (`ConfigAltFont = 1` no
# manifesto): la `0x58` e "a-til", aqui e "a-trema". Este mapa foi lido da propria fonte HD, com
# a folha AUTO-ROTULADA de `port/dev/hd_fonte_folha.gd` (cada celula sai com o proprio numero de
# codigo escrito embaixo, usando os digitos do proprio atlas). Grade provada com a frase
# "ACAO...0159": celula 14 (56 no HD, 4x), 18 colunas, v = (cod/18)*14 + 28.
MAPA_HD = {
    "Á": None,  # (placeholder para deixar claro que a chave e o caractere composto, nao NFD)
}
MAPA_HD = {
    "Á": 138, "á": 139,     # A agudo
    "À": 156, "à": 160,     # A grave
    "Ã": 158, "ã": 159,     # A til
    "Â": 96,  "â": 97,      # A circunflexo
    "Ç": 114, "ç": 115,     # C cedilha
    "É": 100, "é": 101,     # E agudo
    "È": 98,  "è": 99,      # E grave
    "Ê": 102, "ê": 103,     # E circunflexo
    "Ë": 134, "ë": 135,     # E trema
    "Í": 140, "í": 141,     # I agudo
    "Ì": 148, "ì": 149,     # I grave
    "Î": 106, "î": 107,     # I circunflexo
    "Ï": 104, "ï": 105,     # I trema
    "Ó": 142, "ó": 143,     # O agudo
    "Ò": 150, "ò": 151,     # O grave
    "Ô": 108, "ô": 109,     # O circunflexo
    "Õ": 128, "õ": 129,     # O til
    "Ö": 89,  "ö": 90,      # O trema
    "Ú": 144, "ú": 145,     # U agudo
    "Ù": 110, "ù": 111,     # U grave
    "Û": 112, "û": 113,     # U circunflexo
    "Ü": 91,  "ü": 92,      # U trema
    "Ä": 87,  "ä": 88,      # A trema
    "Ñ": 132, "ñ": 133,     # N til
    "ß": 93,                      # eszett
    "°": 136, "ª": 137, "¿": 146, "¡": 147,
}
# Largura/indent do glifo acentuado: uso a do caractere BASE (a de "a" para "a-agudo", a de "C"
# para "C-cedilha"). O EXE so tem tabela ate o codigo 0x56 (ASCII) e a do mod e de outra fonte.
# Escolha DECLARADA, nao medida.
BASE_SEM_ACENTO = {
    "Á": "A", "á": "a", "À": "A", "à": "a", "Ã": "A", "ã": "a",
    "Â": "A", "â": "a", "Ä": "A", "ä": "a",
    "Ç": "C", "ç": "c",
    "É": "E", "é": "e", "È": "E", "è": "e", "Ê": "E", "ê": "e",
    "Ë": "E", "ë": "e",
    "Í": "I", "í": "i", "Ì": "I", "ì": "i", "Î": "I", "î": "i",
    "Ï": "I", "ï": "i",
    "Ó": "O", "ó": "o", "Ò": "O", "ò": "o", "Ô": "O", "ô": "o",
    "Õ": "O", "õ": "o", "Ö": "O", "ö": "o",
    "Ú": "U", "ú": "u", "Ù": "U", "ù": "u", "Û": "U", "û": "u",
    "Ü": "U", "ü": "u",
    "Ñ": "N", "ñ": "n",
}

MOD_PADRAO = ("C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/"
              "mod_BH3_Portuguese/encoding.xml")
LINHA = re.compile(r'Encode="0x([0-9A-Fa-f]+)"\s+Char="([^"]*)"(?:\s+width="(\d+)")?'
                   r'(?:\s+indent="(\d+)")?')

# `&#34;` etc. aparecem escapados no XML
ESCAPES = {"&#34;": '"', "&quot;": '"', "&amp;": "&", "&lt;": "<", "&gt;": ">"}


def ler(caminho):
    txt = open(caminho, encoding="utf-8-sig").read()
    saida = []
    for m in LINHA.finditer(txt):
        cod = int(m.group(1), 16)
        ch = m.group(2)
        for k, v in ESCAPES.items():
            ch = ch.replace(k, v)
        if ch == "":
            continue
        saida.append({
            "code": cod,
            "char": ch,
            "width": int(m.group(3)) if m.group(3) else None,
            "indent": int(m.group(4)) if m.group(4) else None,
        })
    return saida


def main():
    a = sys.argv[1:]
    mod = a[a.index("--mod") + 1] if "--mod" in a else MOD_PADRAO
    if not os.path.exists(mod):
        print("encoding.xml nao encontrado: %s" % mod)
        return 1
    entradas = ler(mod)
    # char -> codigo. Quando o mesmo codigo tem dois chars (ex.: 0x16 = ':' e '^'), o PRIMEIRO
    # vence no de-para reverso, mas os dois viram chave (o desenho e o mesmo glifo).
    de_para = {}
    for e in entradas:
        de_para.setdefault(e["char"], e["code"])
    acentos = [e for e in entradas
               if any(c in e["char"] for c in "áàãâçéêíóôõúüñÁÀÃÂÇÉÊÍÓÔÕÚÜÑ")]
    d = {
        "atlas_hd": {
            "arquivo": "misc/AED42717.webp (1024x1024 = 4x a pagina de VRAM 256x256)",
            "celula_sd": 14, "colunas": 18, "v_base_sd": 28, "fator": 4,
            "metodo": ("de-para lido da folha AUTO-ROTULADA (port/dev/hd_fonte_folha.gd): cada "
                       "celula sai com o proprio codigo escrito embaixo com os digitos do atlas"),
            "prova_grade": "a tira da frase 'ACAO...0159' sai legivel com celula 56 e base 112",
        },
        "char_para_codigo_hd": MAPA_HD,
        "base_sem_acento": BASE_SEM_ACENTO,
        "_fonte": ("mod_BH3_Portuguese/encoding.xml (o mod de traducao precisou do de-para "
                   "caractere->codigo para reescrever os textos; o EXE so guarda os codigos)"),
        "_nota": ("width/indent aqui sao as metricas do MOD (fonte HD). Para o SD valem as da "
                  "tabela 0x80098dd0, em re3_font.json."),
        "n": len(entradas),
        "n_acentuados": len(acentos),
        "entradas": entradas,
        "char_para_codigo": de_para,
    }
    dest = paths.data("re3_font_pt.json")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    json.dump(d, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("%d entradas (%d acentuadas) -> %s" % (len(entradas), len(acentos), dest))
    print("exemplos:", ", ".join("%s=0x%02x" % (e["char"], e["code"]) for e in acentos[:8]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
