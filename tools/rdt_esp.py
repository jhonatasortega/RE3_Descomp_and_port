#!/usr/bin/env python3
"""Efeitos ESP **da sala** (fogo, fumaca, faisca): tabela de ids + folha de sprites.

O que este script estabelece
----------------------------
A tabela de offsets do RDT tem 22 ponteiros e so quatro papeis estavam identificados
(cameras, RVD, script e "provavel luz/objeto"). Medindo os blocos:

  * **off[17] = tabela de IDs de ESP da sala.** 16 bytes: ate 8 ids `u8` e o resto `0xFF`
    (= slot livre). Em `R10D` sao `08 09 18 0c 24 26` — seis efeitos.
  * **off[20] NAO e a folha de efeito** — foi meu primeiro palpite e esta ERRADO: os dois TIMs
    do RDT do R10D (off[20] e um segundo em 0x1fa90, fora da tabela) sao **texturas de PORTA**
    (128x256 8bpp; conferi as duas na tela). Os SPRITES dos efeitos vem da pagina de VRAM
    (960,0) que a sala carrega, e os bancos de animacao ficam no proprio RDT — e o
    `tools/esp_decode.py --room` ja os le usando exatamente esta tabela off[17], o que
    confirma o papel dela por um caminho independente.

Criterio de aceite (o que faz isso ser leitura e nao chute): em TODAS as salas com
off[17] != 0 os bytes seguem o padrao "ids validos e depois so 0xFF" — 167 salas passam.

Saida: port/data/rdt_esp.json — por sala, os ids de ESP que ela carrega.

Uso: python tools/rdt_esp.py [--sala R10D]
"""
from __future__ import annotations

import argparse
import json
import os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OFF_ESP_ID = 17
N_SLOTS_ESP = 8            # o RDT reserva 8; os demais bytes do bloco vem 0xFF
VAZIO = 0xFF


def bloco_rdt(caminho_json: str) -> tuple[bytes, dict]:
    with open(caminho_json, encoding="utf-8") as f:
        meta = json.load(f)
    ard = os.path.join(os.path.dirname(caminho_json).replace(
        os.path.join("port", "data"), os.path.join("extracted", "ntsc-u", "CD_DATA")),
        os.path.basename(meta["file"]))
    if not os.path.exists(ard):
        return b"", meta
    with open(ard, "rb") as f:
        raw = f.read()
    b = next((x for x in meta["blocks"] if x.get("role") == "rdt"), None)
    if b is None:
        return b"", meta
    return raw[b["offset"]:b["offset"] + b["length"]], meta


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sala")
    a = ap.parse_args()

    saida = {"_fonte": "RDT off[17] = tabela de ids de ESP da sala (8 slots, 0xFF = livre)",
             "salas": {}}
    n_ok = 0
    n_erro = 0
    for stage in sorted(os.listdir(os.path.join(RAIZ, "port", "data"))):
        if not stage.startswith("STAGE"):
            continue
        pasta = os.path.join(RAIZ, "port", "data", stage)
        for nome in sorted(os.listdir(pasta)):
            if not nome.endswith(".json") or "_" in nome:
                continue
            sala = nome[:-5]
            if a.sala and sala != a.sala:
                continue
            rdt, meta = bloco_rdt(os.path.join(pasta, nome))
            if not rdt:
                continue
            ot = meta["rdt"]["offset_table"]
            if len(ot) <= OFF_ESP_ID:
                continue
            reg: dict = {"stage": stage}
            off_id = ot[OFF_ESP_ID]
            if off_id:
                bruto = rdt[off_id:off_id + 16]
                ids = [b for b in bruto[:N_SLOTS_ESP] if b != VAZIO]
                # aceite: depois do último id válido só vem 0xFF
                cauda = bruto[len(ids):N_SLOTS_ESP]
                reg["esp_ids"] = ids
                reg["padrao_ok"] = all(x == VAZIO for x in cauda)
                if not reg["padrao_ok"]:
                    n_erro += 1
                reg["bruto"] = bruto[:N_SLOTS_ESP].hex(" ")
            if reg.get("esp_ids"):
                saida["salas"][sala] = reg
                n_ok += 1
    caminho = os.path.join(RAIZ, "port", "data", "rdt_esp.json")
    with open(caminho, "w", encoding="utf-8") as f:
        json.dump(saida, f, ensure_ascii=False, indent=1)
    print("%d salas com ESP · %d problemas · gravado %s"
          % (n_ok, n_erro, os.path.relpath(caminho, RAIZ)))
    todos: dict[int, int] = {}
    for reg in saida["salas"].values():
        for i in reg.get("esp_ids", []):
            todos[i] = todos.get(i, 0) + 1
    print("ids de ESP usados no jogo (id: nº de salas): %s"
          % {("0x%02x" % k): v for k, v in sorted(todos.items(), key=lambda x: -x[1])})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
