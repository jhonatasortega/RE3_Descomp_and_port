#!/usr/bin/env python3
"""Exporta o BYTECODE CRU do SCD + a tabela autoritativa de opcodes para o port (F2).

A VM do port precisa executar o script de sala de verdade — e para isso precisa dos BYTES,
não do resumo em JSON. Este script grava, por sala:

    <out>/data/STAGE{n}/R###.scd      bytecode cru (o bloco offset_table[16] do RDT)
    <out>/data/scd_opcodes.json       tabela de 144 opcodes: tamanho + semântica + fonte

A tabela vem de `tools/scd_decode.py` (`VM_SIZES`/`OPCODE_SEM`), que é a fonte de verdade
lida byte a byte dos 144 handlers do EXE. Duplicar esses números à mão no GDScript seria
criar uma segunda verdade — por isso o port lê este JSON.

Uso:
    python tools/scd_export.py            # todas as 169 salas
    python tools/scd_export.py STAGE1/R100

Fatos que o formato exige (docs/decomp/notes/scd_opcodes.md):
  • o script começa com uma tabela de u16 = offsets das funções (relativos ao início do SCD);
  • `func_offsets[0]` também diz onde a tabela termina (nº de funções = offset[0]/2);
  • cada função fecha em `evt_end` (0x01) — 4238/4238 nas 169 salas;
  • o espaço de opcodes é `0x00..0x8f`; não existem opcodes >= 0x90.
"""
import glob
import json
import os
import struct
import sys

import ard_parse as AP
import paths
import scd_decode as SD

SECTOR = 0x800


def rdt_and_script(path):
    """Devolve (bytes do RDT, offset do SCD dentro do RDT) de um .ARD.

    Reusa `ard_parse` de propósito: o parsing do contêiner (blocos alinhados a 0x800,
    tabela de 22 offsets do RDT) já é fonte de verdade validada nas 169 salas. Reimplementar
    aqui criaria uma segunda verdade — e a primeira tentativa deste script errou exatamente
    por isso (lia a tabela de blocos no offset errado e estourava em 3 salas).
    """
    d = open(path, "rb").read()
    parsed = AP.parse_ard(d, os.path.basename(path))
    rdt_info = parsed.get("rdt") or {}
    bi = rdt_info.get("block_index")
    if bi is None:
        raise ValueError("sem bloco RDT")
    blk = parsed["blocks"][bi]
    rdt = d[blk["offset"]:blk["offset"] + blk["length"]]
    scd_off = rdt_info["offset_table"][16]
    return rdt, scd_off


def export_room(path, out_dir):
    rdt, scd_off = rdt_and_script(path)
    name = os.path.splitext(os.path.basename(path))[0]
    if scd_off == 0 or scd_off >= len(rdt):
        return name, 0, 0
    scd = rdt[scd_off:]
    n_func = struct.unpack_from("<H", scd, 0)[0] // 2
    offs = list(struct.unpack_from("<%dH" % n_func, scd, 0)) if n_func else []
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, name + ".scd"), "wb") as f:
        f.write(scd)
    return name, len(scd), n_func


def main(argv):
    alvo = argv[1] if len(argv) > 1 else None
    src = paths.cd_data()
    arquivos = sorted(glob.glob(os.path.join(src, "STAGE*", "R*.ARD")))
    if alvo:
        arquivos = [f for f in arquivos if alvo.replace("/", os.sep) in f]
    total_b = total_f = 0
    for f in arquivos:
        stage = os.path.basename(os.path.dirname(f))
        try:
            name, nb, nf = export_room(f, paths.data(stage))
            total_b += nb
            total_f += nf
            print("OK  %-6s %6d B  %3d funcoes" % (name, nb, nf))
        except Exception as e:
            print("ERRO %s: %s" % (os.path.basename(f), e))

    # tabela de opcodes (fonte: scd_decode.py, lida dos 144 handlers do EXE)
    ops = {}
    for op in SD.OPCODE_SPACE:
        nome, desc = SD.OPCODE_SEM.get(op, ("?", ""))
        ops["%d" % op] = {
            "hex": "0x%02x" % op,
            "size": SD.VM_SIZES.get(op, 0),
            "nome": nome,
            "desc": desc,
        }
    # Histograma de opcodes por sala, PELO DECODIFICADOR PYTHON — é o lado independente do
    # diff exigido pelo gate P2-10: se a VM em GDScript percorre o mesmo bytecode do mesmo
    # jeito, os dois histogramas têm de ser idênticos.
    hist = {}
    for f in arquivos:
        name = os.path.splitext(os.path.basename(f))[0]
        try:
            funcs = SD.decode_room(f)[0]
        except Exception as e:
            print("HIST ERRO %s: %s" % (name, e))
            continue
        h = {}
        for (_fid, _base, instrs, _fecha) in funcs:
            for (_off, op, _sz, _raw) in instrs:
                h[str(op)] = h.get(str(op), 0) + 1
        hist[name] = h
    json.dump({"_meta": {"gerado_por": "tools/scd_export.py via scd_decode.decode_room",
                         "uso": "lado Python do diff do gate P2-10 (contagem de opcodes por sala)"},
               "por_sala": hist},
              open(paths.data("scd_hist.json"), "w", encoding="utf-8"), indent=0)
    print("histograma de opcodes -> %s (%d salas)" % (paths.data("scd_hist.json"), len(hist)))

    out = paths.data("scd_opcodes.json")
    json.dump({
        "_meta": {
            "gerado_por": "tools/scd_export.py (fonte: tools/scd_decode.py)",
            "espaco": "0x00..0x8f (144 opcodes); NAO existem opcodes >= 0x90",
            "jump_table": hex(SD.VM_JUMP_TABLE),
            "loop": hex(SD.VM_MAIN_LOOP),
            "dispatch": hex(SD.VM_DISPATCH),
            "pc_init": hex(SD.VM_PC_INIT),
            "fechamento": "%d/%d funcoes fecham em evt_end nas 169 salas" % SD.SCD_CLOSURE,
            "retorno_handler": "1 = continua (re-dispatch) · 2 = fim (evt_end 0x01)",
            "nota": ("tamanhos lidos BYTE A BYTE dos 144 handlers do EXE; opcodes de controle "
                     "(if/while/switch/gosub) escrevem o PC em vez de avancar fixo"),
        },
        "opcodes": ops,
    }, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n%d salas, %d bytes de bytecode, %d funcoes" % (len(arquivos), total_b, total_f))
    print("tabela de opcodes -> %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
