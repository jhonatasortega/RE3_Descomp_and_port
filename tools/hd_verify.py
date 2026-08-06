#!/usr/bin/env python3
"""Verifica se o background HD está colado na CÂMERA CERTA (item P1-03).

O `hd_copy.py` grava `assets/STAGE{n}/R###_{cam}.webp` usando a ORDEM do cache do Classic
REbirth. Mas o cache só tem as câmeras que o jogador visitou no PC: medindo, apenas **58 das
169 salas** têm a mesma contagem de câmeras que o RDT do PS1 (108 salas têm MAIS câmeras no
RDT). Se a ordem do cache não coincidir com o índice de câmera do RDT, o HD fica no ângulo
errado — e isso não aparece em nenhum teste de contagem.

Este script decide por CONTEÚDO, que é a única evidência confiável: para cada câmera, decodifica
o slot correspondente do `.BSS` do PS1 (320×240), reduz o HD (1280×960) para 320×240 e mede a
correlação. Se o HD daquele índice casa com o `.BSS` do MESMO índice, o alinhamento está certo.

    python tools/hd_verify.py                 # amostra de 25 salas
    python tools/hd_verify.py --all           # as 169
    python tools/hd_verify.py --room R101     # uma sala, detalhando cada câmera

Saída: por sala, quantas câmeras casam no próprio índice, quantas casam em OUTRO índice (o que
prova desalinhamento e dá o mapa correto) e quantas não casam com nada.
"""
import glob
import os
import sys

import paths

try:
    from PIL import Image
except ImportError:
    sys.exit("ERRO: este verificador precisa do Pillow (PIL)")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bss2png  # noqa: E402  (decoder do .BSS, fonte única)

LIMIAR = 0.80          # correlação mínima para considerar "casa"
TAM = (80, 60)         # compara em miniatura: robusto a ruído de compressão e upscale


def cinza(img):
    return img.convert("L").resize(TAM, Image.LANCZOS)


def correl(a, b):
    """Correlação normalizada (NCC) entre duas miniaturas em tons de cinza."""
    pa = list(a.getdata())
    pb = list(b.getdata())
    n = len(pa)
    ma = sum(pa) / n
    mb = sum(pb) / n
    va = sum((p - ma) ** 2 for p in pa)
    vb = sum((p - mb) ** 2 for p in pb)
    if va == 0 or vb == 0:
        return 0.0
    cov = sum((pa[i] - ma) * (pb[i] - mb) for i in range(n))
    return cov / ((va * vb) ** 0.5)


SLOT = 0x10000          # cada slot do .BSS tem 64 KiB (contêiner de slots — ver BSS.md)


def slots_bss(caminho):
    """Decodifica todos os slots do .BSS -> lista de miniaturas em cinza.

    Usa `bss2png.decode_frame` (o decoder canônico, MDEC/DCT "BS v3") em vez de reimplementar.
    """
    saida = []
    data = open(caminho, "rb").read()
    for slot in range(len(data) // SLOT):
        try:
            w, h, rgb, _q, _v = bss2png.decode_frame(data, slot * SLOT)
        except Exception:
            saida.append(None)
            continue
        im = Image.frombytes("RGB", (w, h), bytes(rgb))
        saida.append(cinza(im))
    return saida


def verifica_sala(rid, detalhe=False):
    st = int(rid[1], 16)
    bss = paths.cd_data("STAGE%d" % st, "%s.BSS" % rid)
    if not os.path.isfile(bss):
        return None
    ps1 = slots_bss(bss)
    if not ps1:
        return None
    proprio = outro = nenhum = 0
    remap = {}
    i = 0
    while True:
        hd_path = paths.assets("STAGE%d" % st, "%s_%d.webp" % (rid, i))
        if not os.path.isfile(hd_path):
            break
        hd = cinza(Image.open(hd_path))
        if i < len(ps1) and ps1[i] is not None:
            c_proprio = correl(hd, ps1[i])
        else:
            c_proprio = -1.0
        if c_proprio >= LIMIAR:
            proprio += 1
            if detalhe:
                print("    cam %2d: casa no próprio índice (ncc %.3f)" % (i, c_proprio))
        else:
            # procura em qual índice ele casaria
            melhor = -1
            melhor_c = -1.0
            for j, p in enumerate(ps1):
                if p is None:
                    continue
                c = correl(hd, p)
                if c > melhor_c:
                    melhor_c = c
                    melhor = j
            if melhor_c >= LIMIAR:
                outro += 1
                remap[i] = melhor
                if detalhe:
                    print("    cam %2d: DESALINHADO -> casa com o slot %d (ncc %.3f, próprio %.3f)"
                          % (i, melhor, melhor_c, c_proprio))
            else:
                nenhum += 1
                if detalhe:
                    print("    cam %2d: não casa com nenhum slot (melhor %.3f no %d)"
                          % (i, melhor_c, melhor))
        i += 1
    return {"rid": rid, "hd": i, "slots": len(ps1), "proprio": proprio,
            "outro": outro, "nenhum": nenhum, "remap": remap}


def emitir(salas):
    """Gera `<out>/data/hd_align.json`: por sala, o índice de câmera CORRETO de cada HD."""
    import json
    mapa = {}
    tot = dict(hd=0, proprio=0, outro=0, nenhum=0)
    for k, rid in enumerate(salas):
        r = verifica_sala(rid)
        if r is None:
            continue
        for c in ("hd", "proprio", "outro", "nenhum"):
            tot[c] += r[c]
        # mapa completo: todo índice HD -> índice de câmera correto (identidade quando já casa)
        completo = {}
        for i in range(r["hd"]):
            completo[str(i)] = r["remap"].get(i, i)
        mapa[rid] = {"n_hd": r["hd"], "n_slots": r["slots"], "correto": r["proprio"],
                     "realinhar": len(r["remap"]), "sem_par": r["nenhum"],
                     "de_para": completo}
        print("[%3d/%3d] %-5s HD=%2d slots=%2d proprio=%2d realinhar=%2d sem_par=%d"
              % (k + 1, len(salas), rid, r["hd"], r["slots"], r["proprio"],
                 len(r["remap"]), r["nenhum"]))
    out = paths.data("hd_align.json")
    json.dump({"_meta": {
        "gerado_por": "tools/hd_verify.py --all --emit",
        "metodo": ("correlacao normalizada (NCC) em miniatura 80x60 entre o HD reduzido e cada "
                   "slot do .BSS do PS1; limiar %.2f" % LIMIAR),
        "por_que": ("o hd_copy.py grava na ORDEM do cache do Classic REbirth, que so tem as "
                    "cameras visitadas no PC; medido, o indice do cache NAO corresponde ao "
                    "indice de camera do RDT na maioria das salas"),
        "totais": tot,
    }, "salas": mapa}, open(out, "w", encoding="utf-8"), indent=0)
    print("\nTOTAL: %d HD · %d no proprio indice · %d a realinhar · %d sem par" % (
        tot["hd"], tot["proprio"], tot["outro"], tot["nenhum"]))
    print("-> %s" % out)
    return 0


def main(argv):
    if "--room" in argv:
        rid = argv[argv.index("--room") + 1].upper()
        r = verifica_sala(rid, detalhe=True)
        print(r)
        return 0
    salas = sorted(os.path.basename(f)[:-4] for f in
                   glob.glob(os.path.join(paths.cd_data(), "STAGE*", "R*.BSS")))
    if "--all" not in argv:
        salas = salas[::max(1, len(salas) // 25)][:25]
    if "--emit" in argv:
        return emitir(salas)
    tot = dict(hd=0, proprio=0, outro=0, nenhum=0)
    desalinhadas = []
    for rid in salas:
        r = verifica_sala(rid)
        if r is None:
            continue
        for k in ("hd", "proprio", "outro", "nenhum"):
            tot[k] += r[k]
        marca = ""
        if r["outro"]:
            desalinhadas.append(rid)
            marca = "  <<< DESALINHADA: %s" % r["remap"]
        print("%-5s HD=%2d slots=%2d  proprio=%2d outro=%2d nenhum=%2d%s"
              % (rid, r["hd"], r["slots"], r["proprio"], r["outro"], r["nenhum"], marca))
    print("\nTOTAL (%d salas): %d imagens HD · %d casam no próprio índice · %d em outro · %d em nenhum"
          % (len(salas), tot["hd"], tot["proprio"], tot["outro"], tot["nenhum"]))
    if tot["hd"]:
        print("alinhamento correto: %.1f%%" % (100.0 * tot["proprio"] / tot["hd"]))
    if desalinhadas:
        print("salas com desalinhamento: %s" % ", ".join(desalinhadas))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
