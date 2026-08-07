#!/usr/bin/env python3
"""Exporta os MODELOS DE OBJETO DA SALA (`nOmodel`) de um `.ARD` para `.glb`.

São os objetos 3D do cenário que o script instala com o opcode `0x7f` (`om_set`) e que o AOT
de item (`0x67`/`0x68`) referencia pelo campo `om`: **é a malha real do item no chão**, do
cadeado na porta, do telefone, da caixa que o Nemesis derruba.

── Onde mora (provado) ──
`offset_table[10]` (`rdt+0x30`) é um DIRETÓRIO de `nOmodel` (header `rdt+0x02`, máx. 32)
registros de 8 bytes:

    { u32 offset_TIM ; u32 offset_MODELO }      ambos relativos ao início do RDT

Provas: `0x800521e8/0x800521ec` leem `nOmodel` (`lbu $s2,2($v0)`) colado com `lw $s4,48($v0)`
(= `rdt+8+4*10`) e caminham com stride 8 (`0x8005226c`); `0x80058250`/`0x800584cc` pegam o
campo `+4` do registro (`sll $v0,$s4,3`) e o entregam ao setup de malha `0x80035790`.
Estruturalmente: `off[10] == 0x60 + nCut*32` (o bloco logo depois das câmeras) em 143/143
salas com `nOmodel > 0`.

── Formato ──
O MODELO é o **MD1/EMD3 dos inimigos**, não o `.DO1` das portas: descritor de 24 B
(`vtx_off, nor_off, vtx_count, tri_off, quad_off, u16 tri_count, u16 quad_count`), triângulo
de 12 B, quad de 16 B, vértice/normal de 8 B. Prova: o relocador `0x8002ac40` relocaliza
exatamente `+0x00,+0x04,+0x0c,+0x10` com stride 24. Por isso este script **reusa
`pld2gltf.parse_md1` sem alteração** — nada de varredura por assinatura.

A TEXTURA é um TIM 8bpp+CLUT dentro do próprio RDT (712/712 com magic `0x10` válido); a região
de TIMs começa em `offset_table[20]` (141/143 salas). Indexação igual à dos inimigos:
linha de CLUT = `(u16@prim+2 >> 6) - 480`, coluna de tpage = `byte@prim+6 & 0x0F`.

── Duas variantes de bloco ──
O EXE decide por `char+0x4a`: `== 1` → MD1 direto; senão há um cabeçalho de esqueleto antes.
Aqui a discriminação é ESTRUTURAL (tenta MD1 direto; se a aritmética não fecha, usa o `u32@+0`
como deslocamento do MD1): 682/712 são variante A (com header) e 30/712 variante B (direto).

Uso:
    python tools/omodel2gltf.py --all --out port/assets/OMODEL     # 169 salas -> <sala>/omN.glb
    python tools/omodel2gltf.py R204 2 saida.glb                   # uma sala, um slot
"""

import os
import sys
import glob
import struct

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pld2gltf as P                                                # noqa: E402
import paths                                                        # noqa: E402

SECTOR = 0x800
OFF_TAB = 0x08          # rdt+0x08 = offset_table[0]; entrada k em rdt+0x08+4k
OFF_OMOD = 10           # offset_table[10] = diretório dos modelos de objeto
OFF_OTEX = 20           # offset_table[20] = início da região de TIMs (informativo)
HDR_NOMODEL = 0x02      # header +2 = nOmodel


def rup(x, a):
    return (x + a - 1) // a * a


def get_rdt(path):
    """Bloco tipo 0x00 do contêiner `.ARD` (é o índice 8 nas 169 salas, mas procura por tipo)."""
    d = open(path, "rb").read()
    _total, count = struct.unpack_from("<II", d, 0)
    pos = SECTOR
    for i in range(count):
        length, fa, _fb = struct.unpack_from("<IHH", d, 8 + i * 8)
        if (fa & 0xFF) == 0x00:
            return d[pos:pos + length]
        pos = rup(pos + length, SECTOR)
    raise ValueError("sem bloco RDT em %s" % path)


def omodel_table(rdt):
    """`[(tim_off, model_off)]` com `nOmodel` entradas. `model_off == 0` = SLOT VAZIO (o EXE
    marca `be_flg = 0x80000000` em `0x80052248` e não carrega nada)."""
    n = rdt[HDR_NOMODEL]
    base = struct.unpack_from("<I", rdt, OFF_TAB + 4 * OFF_OMOD)[0]
    out = []
    for i in range(n):
        if base + i * 8 + 8 > len(rdt):
            break
        out.append(struct.unpack_from("<II", rdt, base + i * 8))
    return out


def _md1_ok(rdt, base):
    """Valida um cabeçalho MD1 pela ARITMÉTICA dos descritores.

    NÃO usa o `u32` de `+0x00` como tamanho: a semântica dele é inconsistente (às vezes inclui
    o header de 8 B, às vezes não, às vezes sobra um array extra) — validar por ele descarta
    modelos válidos."""
    if base < 0 or base + 8 > len(rdt):
        return False
    nobj = struct.unpack_from("<I", rdt, base + 4)[0]
    if not (0 < nobj <= 64) or base + 8 + nobj * 24 > len(rdt):
        return False
    ob = base + 8
    nprim = 0
    for k in range(nobj):
        vtx, nor, vc, tri, quad, tc, qc = struct.unpack_from("<5I2H", rdt, ob + k * 24)
        if tri + tc * 12 != quad:            # a lista de triângulos vem antes da de quads
            return False
        if tri < nobj * 24:                  # as primitivas começam depois dos descritores
            return False
        if not (0 <= vc <= 4000) or tc > 4000 or qc > 4000:
            return False
        if max(ob + nor + vc * 8, ob + vtx + vc * 8, ob + quad + qc * 16) > len(rdt):
            return False
        nprim += tc + qc
    return nprim > 0


def mesh_base(rdt, model_off):
    """Onde começa o MD1: direto (variante B) ou depois do header de esqueleto (variante A)."""
    if _md1_ok(rdt, model_off):
        return model_off, "B"
    rel = struct.unpack_from("<I", rdt, model_off)[0]
    if _md1_ok(rdt, model_off + rel):
        return model_off + rel, "A"
    raise ValueError("MD1 não localizado em 0x%x" % model_off)


def convert(ard_path, index, out_glb):
    rdt = get_rdt(ard_path)
    tab = omodel_table(rdt)
    if index >= len(tab):
        raise ValueError("slot %d fora de nOmodel=%d" % (index, len(tab)))
    tim_off, model_off = tab[index]
    if model_off == 0:
        raise ValueError("slot %d vazio (ptr == 0)" % index)
    mb, kind = mesh_base(rdt, model_off)

    objs = P.parse_md1(rdt, mb)
    # ZERO-PAD obrigatório: em 2/712 (R11A om4/om5) o `length` do bloco RDT corta os últimos
    # 0x80 bytes do PIX que o próprio TIM declara. Sem o pad o parser estoura no fim.
    buf = rdt + b"\x00" * 0x200
    aw, ah, band_h, npal, atlas = P.parse_tim_atlas(buf, tim_off)
    pos, nor, uv, faces = P.assemble_static(objs, aw, ah, band_h, npal)
    os.makedirs(os.path.dirname(os.path.abspath(out_glb)), exist_ok=True)
    info = P.write_glb_static(out_glb, pos, nor, uv, faces, aw, ah, atlas)
    info.update(kind=kind, tim=hex(tim_off), model=hex(model_off), mesh=hex(mb),
                nobj=len(objs))
    return info


def sala_de(path):
    """`.../R204.ARD` -> `R204` (o nome que o port usa como room_id)."""
    return os.path.splitext(os.path.basename(path))[0].upper()


def main():
    args = sys.argv[1:]
    if args and args[0] == "--all":
        raiz = paths.cd_data()
        alvos = sorted(glob.glob(os.path.join(raiz, "**", "R*.ARD"), recursive=True))
        if not alvos:
            print("nenhum .ARD em %s — rode a extração primeiro" % raiz)
            return 1
        outdir = args[args.index("--out") + 1] if "--out" in args else paths.assets("OMODEL")
        ok = vazio = err = 0
        falhas = []
        for ard in alvos:
            sala = sala_de(ard)
            try:
                rdt = get_rdt(ard)
                tab = omodel_table(rdt)
            except Exception as e:                       # noqa: BLE001
                falhas.append("%s: %s" % (sala, e))
                err += 1
                continue
            for i, (_t, m) in enumerate(tab):
                if m == 0:
                    vazio += 1
                    continue
                dest = os.path.join(outdir, sala, "om%d.glb" % i)
                try:
                    convert(ard, i, dest)
                    ok += 1
                except Exception as e:                   # noqa: BLE001
                    falhas.append("%s om%d: %s" % (sala, i, e))
                    err += 1
        print("omodel: %d exportados · %d slots vazios · %d falhas -> %s" % (
            ok, vazio, err, outdir))
        for f in falhas[:20]:
            print("  falha:", f)
        return 0 if err == 0 else 2

    if len(args) < 3:
        print(__doc__)
        return 1
    sala, idx, dest = args[0], int(args[1]), args[2]
    ard = None
    for p in glob.glob(os.path.join(paths.cd_data(), "**", "%s.ARD" % sala), recursive=True):
        ard = p
        break
    if ard is None:
        print("sala %s não encontrada" % sala)
        return 1
    print(convert(ard, idx, dest))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
