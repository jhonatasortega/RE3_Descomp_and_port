#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Onde esta a animacao de LOCOMOCAO (andar/correr) do player do RE3 (PS1 NTSC-U)?

RESPOSTA (provada por RE do EXE SLUS_009.23 + medicao dos arquivos):
  O player NAO tem UM unico banco de animacao. player+0xc8 (indice de sequencia)
  indexa um EDD cujo PONTEIRO-BASE e' SELECIONADO em runtime entre varios slots
  do player-struct, conforme a arma/postura:

    player+0xec / +0xe8  = banco BASE/desarmado  -> vem do PL00.PLD (as 22 seqs)
                           setado no spawn da Jill em 0x80038aac (fileid 108 =
                           PL00.PLD, casa por tamanho exato 159116).
    player+0xf4 / +0xf0  = banco ARMADO          -> vem do PLW da ARMA EQUIPADA
    player+0xfc / +0xf8  = banco ARMADO 2
    player+0x104/ +0x100 = banco ARMADO 3
                           setados ao EQUIPAR arma em 0x80043be4, que:
                             lbu 0x4a(char); lbu 0x46(weapon);
                             fileid = weaponBase[char] + weapon;  (0x8009dcb4)
                             jal 0x80012818 (load do PLW);
                             sw ...,0xf4(player);  sw ...,0xf0(player)
                           weapon0->PL00W00.PLW(43904) w1->PL00W01(44608)...

  Seletor de banco: 0x800168b8 (bit 0x80 de player+0x150 + valor de player+0x4a).

  => Na jogabilidade normal a Jill esta SEMPRE com uma arma na mao; o ciclo de
     ANDAR/CORRER que se ve vem do BANCO DO PLW, NAO das 22 seqs do PL00.PLD.
     Cada PLW carrega um banco de CORPO INTEIRO proprio (handgun: 15 ossos,
     frameSize=76, 18 seqs, 399 poses) com andar/correr/re/mira segurando a arma.

Este script mede o root-motion dos bancos EDD de um PLD/PLW e identifica
o ciclo de ANDAR (deslocamento moderado ~60-90/frame, loopavel) e CORRER
(~200-230/frame) em cada banco.
"""
import struct, sys, os, glob
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def container_dir(b):
    do = u32(b, 0)
    nd = (len(b) - do) // 4
    return [u32(b, do + i * 4) for i in range(nd)]


def is_emr(b, off):
    """header EMR: u16 hierOff, u16 kfOff, u16 nBones(1..64), u16 frameSize."""
    if off + 8 > len(b):
        return None
    kf = u16(b, off + 2); nb = u16(b, off + 4); fsz = u16(b, off + 6)
    if 1 <= nb <= 64 and 8 <= fsz <= 256 and 4 <= kf <= 4096:
        return (kf, nb, fsz)
    return None


def is_edd(b, off):
    """1o registro: u16 nframes(1..400), u16 frameOff(mult 8, 8..8192)."""
    if off + 8 > len(b):
        return None
    nf = u16(b, off); fo = u16(b, off + 2)
    if 1 <= nf <= 400 and fo >= 8 and fo % 8 == 0 and fo <= 0x4000:
        return fo // 8  # nseq
    return None


def measure_bank(b, edd, emr, label):
    kf, nb, fsz = is_emr(b, emr)
    pool = emr + kf
    nseq = is_edd(b, edd)
    print("  %s  EDD@0x%x EMR@0x%x  nBones=%d frameSize=%d nseq=%d"
          % (label, edd, emr, nb, fsz, nseq))
    for s in range(nseq):
        nf = u16(b, edd + s * 8); fo = u16(b, edd + s * 8 + 2); ps = u32(b, edd + s * 8 + 4)
        fl = edd + fo
        xs = []; zs = []
        for f in range(nf):
            if fl + f * 2 + 2 > len(b):
                break
            prel = u16(b, fl + f * 2) & 0xff
            po = pool + (ps + prel) * fsz
            if po + 6 <= len(b):
                xs.append(s16(b, po)); zs.append(s16(b, po + 4))
        if len(xs) < 2:
            continue
        nx = xs[-1] - xs[0]; nz = zs[-1] - zs[0]
        perf = (abs(nx) + abs(nz)) / max(1, nf)
        tag = ""
        if 45 <= perf <= 110 and abs(nz) < abs(nx) * 0.3:
            tag = "  <= ANDAR?"
        elif perf > 150 and abs(nz) < abs(nx) * 0.3:
            tag = "  <= CORRER?"
        print("     seq%2d nf=%3d pose0=%3d net=(%6d,%6d) ~%.0f/f%s"
              % (s, nf, ps, nx, nz, perf, tag))


def analyze_file(path):
    b = open(path, "rb").read()
    ents = container_dir(b)
    print("== %s (%d sub-blocos) ==" % (os.path.basename(path), len(ents)))
    # acha todos os pares EDD+EMR consecutivos
    i = 0
    banks = 0
    while i < len(ents) - 1:
        e0 = ents[i]
        if is_edd(b, e0) and is_emr(b, ents[i + 1]):
            measure_bank(b, e0, ents[i + 1], "banco%d" % banks)
            banks += 1
            i += 2
        else:
            i += 1
    if banks == 0:
        print("  (nenhum par EDD+EMR)")
    print()


def all_banks(b):
    """Todos os pares EDD+EMR (bancos de animacao) de um contêiner PLD/PLW.
    Retorna lista de dicts {edd, emr, nb, fsz, nseq, npose}."""
    ents = container_dir(b)
    do = u32(b, 0)
    banks = []
    i = 0
    while i < len(ents) - 1:
        e0 = ents[i]
        if is_edd(b, e0) and is_emr(b, ents[i + 1]):
            kf, nb, fsz = is_emr(b, ents[i + 1])
            pool = ents[i + 1] + kf
            pend = min([e for e in ents if e > pool] + [do])
            npose = (pend - pool) // fsz
            nseq = is_edd(b, e0)
            banks.append(dict(edd=e0, emr=ents[i + 1], nb=nb, fsz=fsz, nseq=nseq, npose=npose))
            i += 2
        else:
            i += 1
    return ents, banks


def validate_all():
    """VALIDACAO COMPLETA da unidade `plw`: para TODOS os *.PLW confirma
    (a) banco de animacao ARMADO extraivel, (b) malha da arma (MD1) presente,
    (c) _WPN.glb exportado (ou justificado 'sem slot'), e reporta a contagem de
    BANCOS por arma (multi-banco). Tambem imprime o OSSO DE ANEXO da arma (punho)
    extraido do esqueleto do PLD base -- o DADO que o controller usa p/ prender a
    arma (isso e' decomp: o offset esta no PLD/PLW; o uso no controller e' vinculo).
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import pld2gltf as P
    ROOT = "extracted/ntsc-u/CD_DATA/PLD"
    ASSETS = paths.assets("PLD")
    plws = sorted(glob.glob(os.path.join(ROOT, "*.PLW")))
    n_bank = n_md1 = n_glb = n_slot = n_noslot = 0
    bankhist = {}
    noslot_list = []
    for fn in plws:
        base = os.path.splitext(os.path.basename(fn))[0]
        d = open(fn, "rb").read()
        _, banks = all_banks(d)
        if banks:
            n_bank += 1
        bankhist[len(banks)] = bankhist.get(len(banks), 0) + 1
        slot = None
        try:
            offs, sec = P.parse_container(d)
            roles = P.classify(d, offs, sec)
            if "md1" in roles:
                n_md1 += 1
                objs = P.parse_md1(d, sec[roles["md1"]][0])
                pld = P._load_pld_atlas_for(fn)
                if pld:
                    aw, ah, band, npal, atlas = pld
                    w, _, _ = P.split_weapon_prims(objs, aw, ah, band, npal, atlas)
                    slot = len(w)
        except Exception as e:
            slot = -1
        if slot and slot > 0:
            n_slot += 1
        elif slot == 0:
            n_noslot += 1; noslot_list.append(base)
        if os.path.exists(os.path.join(ASSETS, base + "_WPN.glb")):
            n_glb += 1
    print("== VALIDACAO plw: %d arquivos .PLW ==" % len(plws))
    print("  com banco de animacao armado : %d/%d" % (n_bank, len(plws)))
    print("  com malha MD1 (mao+arma)     : %d/%d" % (n_md1, len(plws)))
    print("  com slot de arma (separavel) : %d  -> %d _WPN.glb exportados" % (n_slot, n_glb))
    print("  sem slot (arma na pele/punho): %d  (esperado, nao e' erro)" % n_noslot)
    print("  bancos por arma (histograma) : %s" % bankhist)
    print("  sem-slot: %s" % ", ".join(noslot_list))
    # detalha os 3 bancos de um PLW representativo
    d = open(os.path.join(ROOT, "PL00W00.PLW"), "rb").read()
    _, banks = all_banks(d)
    print("\n  PL00W00: %d bancos de animacao:" % len(banks))
    role = {15: "corpo inteiro (locomocao armada: seq0=andar seq1=correr seq2=mira seq9=re)",
            7: "parcial superior (7 ossos; overlay de mira/gesto)",
            9: "parcial (9 ossos; overlay)"}
    for bi, bk in enumerate(banks):
        print("    bank%d nBones=%2d frameSize=%d nseq=%d npose=%d  %s" % (
            bi, bk["nb"], bk["fsz"], bk["nseq"], bk["npose"], role.get(bk["nb"], "")))
    # OSSO DE ANEXO da arma (punho direito = bone4) do PLD base
    dp = open(os.path.join(ROOT, "PL00.PLD"), "rb").read()
    offs, sec = P.parse_container(dp); roles = P.classify(dp, offs, sec)
    eo, ee = sec[roles["emr"]]
    emr = P.parse_emr(dp, eo, ee)
    w4 = emr["world"][4]; w7 = emr["world"][7]
    print("\n  OSSO DE ANEXO DA ARMA (dado p/ o controller):")
    print("    bone4 = PUNHO DIREITO (parent chain 0->2->3->4) - Jill segura a arma na destra")
    print("    world-rest bone4 = (%.0f, %.0f, %.0f) unid PS1  (= *SCALE p/ metros; glTF x,-y,-z)"
          % (w4[0], w4[1], w4[2]))
    print("    bone7 = punho ESQUERDO (%.0f, %.0f, %.0f) - anexo p/ armas em 2 maos/espelho"
          % (w7[0], w7[1], w7[2]))
    print("    (a geometria da arma no PLW ja' vem em espaco do osso do punho - obj4/bone4)")


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--validate-all":
        validate_all()
        return
    root = "extracted/ntsc-u/CD_DATA/PLD"
    targets = sys.argv[1:] or [
        os.path.join(root, "PL00.PLD"),    # base/desarmado (22 seqs)
        os.path.join(root, "PL00W00.PLW"),  # handgun -> andar/correr armado
        os.path.join(root, "PL00W03.PLW"),  # outra arma
    ]
    for t in targets:
        if os.path.exists(t):
            analyze_file(t)
        else:
            print("nao encontrado:", t)


if __name__ == "__main__":
    main()
