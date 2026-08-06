#!/usr/bin/env python3
"""Aplica o realinhamento HD→câmera (item P1-03) usando `data/hd_align.json`.

**O problema que isto corrige.** O `hd_copy.py` grava `assets/STAGE{n}/R###_{cam}.webp` na
ORDEM do cache do Classic REbirth. Mas o cache só contém as câmeras que o jogador visitou no
PC — medindo, apenas 58 das 169 salas têm a mesma contagem de câmeras do RDT do PS1. Resultado:
na maioria das salas o background HD ficou colado na **câmera errada**. Na R101, só 2 de 23
estavam certas.

Nenhum teste de contagem pega isso: os arquivos existem, o número fecha, e o jogo mostra o
cenário de outro ângulo. Quem detecta é comparação de CONTEÚDO — feita por `hd_verify.py`, que
casa cada HD com o slot do `.BSS` por correlação (NCC ≈ 0,999, ou seja, casamento exato).

**O que este script faz:**
  1. lê o de-para `hd_align.json`;
  2. renomeia os `.webp` para o índice correto (via nomes temporários, para não colidir);
  3. para câmera que ficar SEM HD, decodifica o slot do `.BSS` e grava o `.png` do PS1 —
     assim nenhuma câmera fica sem imagem (era garantia do P1-02 e continua valendo).

Uso:
    python tools/hd_realign.py --dry     # só mostra o que faria
    python tools/hd_realign.py --apply
"""
import json
import os
import sys

import paths

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bss2png  # noqa: E402

SLOT = 0x10000


def main(argv):
    aplicar = "--apply" in argv
    mapa_path = paths.data("hd_align.json")
    if not os.path.isfile(mapa_path):
        sys.exit("ERRO: %s ausente — rode `python tools/hd_verify.py --all --emit`" % mapa_path)
    d = json.load(open(mapa_path, encoding="utf-8"))
    salas = d["salas"]

    n_mov = n_ident = n_png = n_sem = 0
    for rid in sorted(salas):
        info = salas[rid]
        st = int(rid[1], 16)
        dirp = paths.assets("STAGE%d" % st)
        de_para = {int(k): int(v) for k, v in info["de_para"].items()}

        # 1) tira todos os HD para nomes temporários (evita colisão de renome)
        temporarios = {}
        for i, destino in sorted(de_para.items()):
            src = os.path.join(dirp, "%s_%d.webp" % (rid, i))
            if not os.path.isfile(src):
                continue
            tmp = os.path.join(dirp, "%s__tmp%d.webp" % (rid, i))
            if aplicar:
                os.replace(src, tmp)
            temporarios[destino] = tmp
            if destino == i:
                n_ident += 1
            else:
                n_mov += 1

        # 2) devolve cada um no índice correto
        for destino, tmp in sorted(temporarios.items()):
            dst = os.path.join(dirp, "%s_%d.webp" % (rid, destino))
            if aplicar:
                os.replace(tmp, dst)

        # 3) câmeras sem HD: garante o PS1 (.png) decodificando o slot do .BSS
        n_slots = int(info["n_slots"])
        bss = paths.cd_data("STAGE%d" % st, "%s.BSS" % rid)
        faltando = [c for c in range(n_slots)
                    if c not in temporarios
                    and not os.path.isfile(os.path.join(dirp, "%s_%d.png" % (rid, c)))]
        if faltando and os.path.isfile(bss):
            data = open(bss, "rb").read()
            for c in faltando:
                if c * SLOT >= len(data):
                    n_sem += 1
                    continue
                try:
                    w, h, rgb, _q, _v = bss2png.decode_frame(data, c * SLOT)
                except Exception:
                    n_sem += 1
                    continue
                if aplicar:
                    bss2png.write_png(os.path.join(dirp, "%s_%d.png" % (rid, c)), w, h, rgb)
                n_png += 1
        elif faltando:
            n_sem += len(faltando)

        if de_para:
            print("%-5s %2d HD (%2d realinhados) · %d PNG do PS1 gerados"
                  % (rid, len(de_para), sum(1 for i, v in de_para.items() if i != v),
                     len(faltando)))

    print("\n%s: %d HD movidos para o índice correto · %d já estavam certos · "
          "%d PNG do PS1 gerados para câmeras sem HD · %d sem imagem possível"
          % ("APLICADO" if aplicar else "DRY-RUN", n_mov, n_ident, n_png, n_sem))
    if not aplicar:
        print("(rode com --apply para efetivar)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
