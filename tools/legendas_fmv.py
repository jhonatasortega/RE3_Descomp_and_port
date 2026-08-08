#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Legendas PT-BR dos FMV: decodifica a marcação do `prologue.xml`/`epilogue.xml`.

FONTE
-----
`mod_BH3_Portuguese/xml/prologue.xml` (abertura) e `epilogue.xml` (final), do pacote
"Edição Definitiva Dublado" que já está aplicado na instalação GOG do usuário
(ver `docs/formatos/localizacao_ptbr.md` §1). São XML `<Strings><Text>…</Text></Strings>`
com BOM UTF-8, um `<Text>` por BLOCO da narração.

A MARCAÇÃO — o que está PROVADO
-------------------------------
As diretivas são do motor **Classic REbirth** (`ddraw.dll` da instalação). A lista
completa está no próprio binário como oito formatos `printf`, em endereços de arquivo
consecutivos (offsets medidos com uma varredura de literais):

    0x2fe138  "snd %d"      0x2fe140  "cut %d"     0x2fe150  "string %d"
    0x2fe15c  "color %d"    0x2fe168  "scroll %d"  0x2fe174  "branch %d"
    0x2fe180  "clear %d"    0x2fe18c  "timed %d"

Logo: **as oito diretivas existem, todas levam UM inteiro, e a grafia é essa.**
(`Strings` em `0x2fd11c` e `Text` em `0x2a0b80` são os nomes de nó do XML;
`xml\\prologue.xml` está em `0x2fedd0`.) Isso é fato verificável.

O que é LEITURA MINHA (declarado, não provado)
---------------------------------------------
A SEMÂNTICA não foi extraída do código de máquina. Lendo o texto como um fluxo de
tokens, a única interpretação auto-consistente é:

    {scroll N}  abre o bloco (N=0 nos dois arquivos) — modo de rolagem
    <texto>     acumula no buffer da tela; `\\n` = quebra de linha
    {clear N}   SEGURA o buffer por N quadros e depois LIMPA a tela
    {timed N}   SEGURA o buffer por N quadros e ENCERRA o bloco (é sempre o último)

Três coisas sustentam essa leitura:

  1. **Posição.** `{clear}` só aparece entre pedaços de texto e `{timed}` só aparece
     no fim de cada `<Text>` — nos 4 blocos do prólogo e no 1 do epílogo, sem exceção.
  2. **O primeiro `{clear}` vem depois de um `\\n` sozinho** (`{scroll 0}\\n{clear 34}`),
     isto é, um buffer vazio: 34 quadros de tela em branco = o atraso inicial antes de
     a narração começar. É exatamente o que se espera de um vídeo que abre com imagem.
  3. **A soma fecha dentro do vídeo.** Prólogo = 1414 quadros = **47,18 s a 29,97 fps**,
     contra **90,624 s** de `zmovie/opn.mp4`. A 59,94 fps daria 23,6 s e sobrariam 67 s
     de vídeo sem legenda; a 29,97 a narração cobre a primeira metade do FMV, que é
     onde ela está. Epílogo = 1435 quadros = 47,88 s, contra 54,2 s de `enda`.

**EM ABERTO:** o instante ABSOLUTO em que cada bloco começa. Não há timestamp nos
arquivos; a única leitura disponível é **sequencial** (o bloco n+1 começa quando o
bloco n termina), e é o que este script emite. `{snd}`, `{cut}`, `{string}`,
`{color}` e `{branch}` **não aparecem** nestes dois arquivos e **não** foram
decodificados.

Uso:
    NOSTALGIA_OUT=port python tools/legendas_fmv.py
    python tools/legendas_fmv.py --mostrar          # imprime a linha do tempo
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths                                   # noqa: E402

MOD_PADRAO = (r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"
              r"\mod_BH3_Portuguese\xml")
#: Taxa em que os quadros da marcação são contados. Ver §3 do docstring.
FPS = 30000.0 / 1001.0                          # 29,97 — a do próprio mp4
#: `<arquivo do mod>` -> `<vídeo a que a legenda pertence>` e a duração medida do mp4.
ALVO = {
    "prologue.xml": dict(video="opn", duracao_mp4=90.624),
    "epilogue.xml": dict(video="enda", duracao_mp4=54.2,
                         nota="ALVO DECLARADO: o epílogo é narração de FIM. Casei com "
                              "`enda` por duração (47,9 s de fala em 54,2 s de vídeo); "
                              "não medi qual dos dois finais o motor legenda."),
}
DIRETIVA = re.compile(r"\{(snd|cut|string|color|scroll|branch|clear|timed)\s+(-?\d+)\}")
#: O XML do mod escreve **trema onde deveria haver til**: "destruiçäo", "näo", "perdäo",
#: "operaçäo", "situaçäo", "entäo". Não é escolha do tradutor: o próprio `encoding.xml`
#: do mod tem `ã` (código 0x58) e `ä` (0x9F) como entradas SEPARADAS, e as palavras são
#: português correntes com til. Corrijo e guardo o texto cru ao lado (`linhas_cru`).
#: DECLARADO: correção do port sobre o dado do mod, não medição.
TREMA_POR_TIL = {"ä": "ã", "Ä": "Ã"}


def corrigir_til(s):
    for a, b in TREMA_POR_TIL.items():
        s = s.replace(a, b)
    return s
#: offsets DE ARQUIVO das oito diretivas em `ddraw.dll` (prova de que a lista é essa)
OFFSETS_DDRAW = {
    "snd": 0x2FE138, "cut": 0x2FE140, "string": 0x2FE150, "color": 0x2FE15C,
    "scroll": 0x2FE168, "branch": 0x2FE174, "clear": 0x2FE180, "timed": 0x2FE18C,
}


def ler_blocos(caminho):
    """Devolve a lista de strings `<Text>` do XML (com o BOM tolerado)."""
    with open(caminho, "r", encoding="utf-8-sig") as f:
        raiz = ET.fromstring(f.read())
    return [(t.text or "") for t in raiz.findall("Text")]


def decodificar(bruto):
    """Um bloco `<Text>` -> lista de cues `{quadro_inicio, quadros, linhas, fim}`.

    Percorre o texto como fluxo. `{clear N}`/`{timed N}` fecham a cue corrente; as
    outras diretivas são registradas em `outras` e não afetam o tempo (nenhuma delas
    aparece nestes arquivos — se aparecer, o JSON mostra).
    """
    cues, outras = [], []
    buffer_ = ""
    t = 0
    pos = 0
    for m in DIRETIVA.finditer(bruto):
        buffer_ += bruto[pos:m.start()]
        pos = m.end()
        nome, valor = m.group(1), int(m.group(2))
        if nome in ("clear", "timed"):
            linhas = [l for l in buffer_.replace("\\n", "\n").split("\n")]
            # tira as linhas vazias das PONTAS, mas guarda o texto como está no meio
            while linhas and linhas[0].strip() == "":
                linhas.pop(0)
            while linhas and linhas[-1].strip() == "":
                linhas.pop()
            cru = [l.strip() for l in linhas]
            corr = [corrigir_til(l) for l in cru]
            cue = dict(quadro_inicio=t, quadros=valor,
                       segundo_inicio=round(t / FPS, 3),
                       segundos=round(valor / FPS, 3),
                       linhas=corr, fim=(nome == "timed"))
            if corr != cru:
                cue["linhas_cru"] = cru
            cues.append(cue)
            t += valor
            buffer_ = ""
        else:
            outras.append(dict(diretiva=nome, valor=valor, quadro=t))
    resto = (buffer_ + bruto[pos:]).strip()
    return cues, outras, t, resto


def montar(mod_dir):
    saida = {
        "meta": {
            "gerado_por": "tools/legendas_fmv.py",
            "fonte": "mod_BH3_Portuguese/xml/{prologue,epilogue}.xml (pacote PT-BR "
                     "'Edição Definitiva Dublado', já aplicado na instalação GOG)",
            "fps_da_marcacao": round(FPS, 4),
            "diretivas_provadas": {k: "ddraw.dll +0x%06x" % v
                                   for k, v in sorted(OFFSETS_DDRAW.items())},
            "semantica": {
                "scroll": "abre o bloco (valor 0 nos dois arquivos) — DECLARADO",
                "clear": "segura o texto acumulado por N quadros e LIMPA — DECLARADO",
                "timed": "segura por N quadros e ENCERRA o bloco — DECLARADO",
                "prova": "posição das diretivas + o 1º {clear} sobre buffer vazio "
                         "(atraso inicial) + a soma cabendo na duração do mp4",
            },
            "em_aberto": "o instante ABSOLUTO de cada bloco: os arquivos não têm "
                         "timestamp, então os blocos entram em SEQUÊNCIA. "
                         "{snd}/{cut}/{string}/{color}/{branch} não aparecem e não "
                         "foram decodificados.",
            "correcao_de_texto":
                "trema -> til (ä->ã, Ä->Ã): o XML do mod escreve 'destruiçäo', 'näo', "
                "'perdäo', 'operaçäo', 'situaçäo', 'entäo'. O encoding.xml do próprio "
                "mod tem ã (0x58) e ä (0x9F) separados, logo o trema é erro de dado, "
                "não escolha. O texto cru fica em `linhas_cru`. DECLARADO.",
        },
        "videos": {},
    }
    for arq, info in ALVO.items():
        p = os.path.join(mod_dir, arq)
        if not os.path.exists(p):
            saida["videos"][info["video"]] = dict(ok=False, motivo="não existe: %s" % p)
            continue
        t = 0
        cues, outras = [], []
        for i, bruto in enumerate(ler_blocos(p)):
            c, o, dur, resto = decodificar(bruto)
            for x in c:
                x["bloco"] = i
                x["quadro_inicio"] += t
                x["segundo_inicio"] = round(x["quadro_inicio"] / FPS, 3)
            cues += c
            outras += [dict(bloco=i, **y) for y in o]
            if resto:
                cues.append(dict(bloco=i, quadro_inicio=t + dur, quadros=0,
                                 segundo_inicio=round((t + dur) / FPS, 3), segundos=0.0,
                                 linhas=[resto], fim=True,
                                 nota="texto SEM diretiva de tempo no fim do bloco"))
            t += dur
        saida["videos"][info["video"]] = dict(
            ok=True, arquivo=arq, blocos=i + 1, cues=len(cues), quadros_total=t,
            segundos_total=round(t / FPS, 3), duracao_mp4=info["duracao_mp4"],
            cabe_no_video=t / FPS <= info["duracao_mp4"],
            nota=info.get("nota", ""), outras_diretivas=outras, legendas=cues)
    return saida


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mod", default=None, help="pasta xml/ do mod PT-BR")
    ap.add_argument("--mostrar", action="store_true", help="imprime a linha do tempo")
    a = ap.parse_args()
    mod = a.mod or os.environ.get("NOSTALGIA_MOD") or MOD_PADRAO
    d = montar(mod)
    os.makedirs(paths.data(), exist_ok=True)
    saida = paths.data("legendas_fmv.json")
    with open(saida, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    for v, info in d["videos"].items():
        if not info.get("ok"):
            print("  FALTA %-6s %s" % (v, info["motivo"]))
            continue
        print("  %-6s %d blocos, %d legendas, %d quadros = %.2f s  (mp4 %.2f s) cabe=%s"
              % (v, info["blocos"], info["cues"], info["quadros_total"],
                 info["segundos_total"], info["duracao_mp4"], info["cabe_no_video"]))
        if a.mostrar:
            for c in info["legendas"]:
                print("     %7.2fs +%5.2fs  %s" % (c["segundo_inicio"], c["segundos"],
                                                   " / ".join(c["linhas"]) or "(em branco)"))
    print("-> %s" % saida)


if __name__ == "__main__":
    main()
