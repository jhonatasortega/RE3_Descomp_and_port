#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""DESTINO das portas do SCD (RE3 PS1 NTSC-U) -- RESOLVIDO: e' campo ESTATICO.

>>> ACHADO DESTE ROUND (prova por disassembly + reciprocidade 91.9%) <<<

A porta NAO e' o opcode 0x67 (esse e' sce==2, um AOT de outro tipo). A PORTA e'
qualquer AOT cujo SCE type (byte@+2) troca de sala, criado pelos opcodes:
    * 0x61 = DOOR_AOT_SET      (32B)  -- descriptor em opcode+0xe
    * 0x62 = DOOR_AOT_SET_4P   (40B)  -- descriptor em opcode+0x16
SCE types que TROCAM de sala (DOOR_SCE): {1, 13}. Ambos setam gs+0x2154 +
flag-troca 0x800c7960 e sao lidos pelo door_handler 0x800248e4 no MESMO descriptor.
    * sce==1  : porta normal              -> 447 (408x 0x61 + 39x 0x62)
    * sce==13 : porta condicional/scripted ->   6 (todas 0x61; 3 pares reciprocos:
                R114<->R118, R304<->R30A, R40C<->R40E)  [handler 0x80051cb0]
Total: 453 portas. (Rounds anteriores contavam so' sce==1 = 447; os 6 sce==13
eram descartados como "sce!=1" -- ERAM transicoes de sala reais. Ver docs.)

CADEIA CONSUMIDORA (byte-a-byte, ver docs/decomp/notes/door_handler.md):
  1. Handler do opcode (0x61=0x80055b5c / 0x62=0x80055bbc) faz
        gs+0x2158[id] = &(opcode + 2)                  (registra o AOT)
     e o 0x62 ainda liga bit 0x80 em byte@+3 (AOT+1) -> muda o "path" (ver adiante).
  2. VM de AOT per-frame (dispatch 0x80050aac, jump-table por SCE 0x8009e0bc):
        sce = *(AOT+0) = opcode byte@+2
        se (AOT byte@+1 & 0x80): a0 = AOT + 0x14   (path 0x14)  <- 0x62
        senao                  : a0 = AOT + 0xc    (path 0x0c)  <- 0x61
     sce==1 -> chama o PRODUTOR de porta 0x80050d28 com a0 = descriptor.
  3. Produtor 0x80050d28: quando o gatilho e' tocado, faz gs+0x2154 = descriptor
     (=a0) e liga a flag-troca 0x800c7960.

CALLBACK FINO DE COLISAO (FECHADO byte-a-byte neste round; 100% EXE):
  * Driver per-frame 0x80050b58 (chamado no loop principal em 0x80023f38) roda a VM de
    colisao de AOT 0x800505ac 2x sobre o player (a0=gs+0x248c=0x800ccbc4): a2=0x10 (deteccao)
    e a2=0 (gatilho).
  * A VM itera gs+0x2158[id], monta a FORMA do AOT a partir do descriptor:
      - byte@+1 & 0x40 == 0 -> AABB (origem +4/+6, extensao +8/+0xa) em sp+0x2c..
      - byte@+1 & 0x40      -> QUAD de 4 vertices (+4..+0x12)
    e testa a posicao do player (char+0x34/+0x3c) por:
      - 0x800101c8 = ponto-em-AABB ((X-x0) u< w && (Z-z0) u< d ; retorna 1=dentro)
      - 0x8001020c = ponto-em-QUAD convexo (4 testes de sinal de produto vetorial)
    Se DENTRO: grava player+0xc = AOT id, gs+0x780e/gs+0x7810 = indice; senao pula o AOT.
  * So entao despacha por SCE (jalr 0x8009e0bc[sce], a0=descriptor). sce==1 -> 0x80050d28,
    que grava gs+0x2154=descriptor e 0x800c7960=1 (flag-troca) e gs+0x2468 |= 0xff000000.
  * A partir dai: door_handler 0x800248e4 le gs+0x2154 -> room-loader 0x800493ec.
  4. door_handler 0x800248e4 le do descriptor (= opcode + 2 + path):
        +0/+2/+4/+6 (u16)  = CHEGADA next_x / next_y / next_z / next_dir
        +8 (u8)            = next_stage   (aplica mod 9 -> exe-stage 0..6)
        +9 (u8)            = next_room    (INDICE INTERNO na tabela de fileids
                                           0x8009dfd0[stage], = posicao ordenada
                                           da sala na pasta STAGE(stage+1))
        +0xa (u8)          = next_camera/cut
        +0xb (u8)          = flag/needs_key-ish
  => OFFSETS ON-DISK do destino:
        0x61: next_stage = byte@+0x16, next_room = byte@+0x17, cut = byte@+0x18,
              chegada = s16@+0xe/+0x10/+0x12/+0x14
        0x62: next_stage = byte@+0x1e, next_room = byte@+0x1f, cut = byte@+0x20,
              chegada = s16@+0x16/+0x18/+0x1a/+0x1c

DE-PARA indice->nome (RESOLVE OS 35 TODO): o indice interno = digitos hex do nome
  (Rxyz -> int(yz,16)) e' o MESMO indice de `fileid = 0x8009dfd0[stage][room]`
  (room-loader 0x800493ec). A tabela tem DUPLICATAS (varios indices -> mesmo fileid =
  sala reusada) e slots 0 nos stages 4/6/7. Logo o de-para correto e'
  `indice -> fileid -> nome`, NAO posicao-na-pasta. Com isso: 447/447 resolvidos
  (era 412 c/ posicao-na-pasta). Ver room_index_map().

VALIDACAO (reciprocidade A->B <-> B->A, cross-stage OK, gemeas coladas):
  94.1% (273/290 arestas-sala). raw_stage 100% em {0..6}. Portas cross-stage
  (R124<->R21A, R309<->R400, R40F<->R510) e gemeas Mercenaries (R6xx->R1xx)
  aparecem recíprocas. Das 35 antes-abertas, 34/35 fecham RECIPROCAMENTE (a 35a e'
  direcao-unica). => o par (stage,room) destino E' campo ESTATICO do SCD.
  (Encerra a hipotese antiga de "runtime": o erro era ler o opcode ERRADO -- 0x67.)

Uso:
    python tools/scd_door_dest.py        # extrai portas e mede reciprocidade
"""
import struct, glob, os, sys, json
from collections import defaultdict, Counter
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scd_decode import VM_SIZES  # tamanhos autoritativos da VM
from exe_parse import Exe        # loader do SLUS_009.23 (leitura da tabela de fileids)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SECTOR = 0x800
CD = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA")
DATA = paths.data()
EXE = os.path.join(ROOT, "extracted", "ntsc-u", "SLUS_009.23")

# Tabela de fileids 0x8009dfd0: 9 ponteiros u32 (1 por exe-stage). Os stages REAIS
# sao 0..6 (raw_stage%9 == 100% em {0..6}); os arrays deles sao CONTIGUOS na regiao
# 0x8009de30..0x8009dfd0 (logo o fim de um array = inicio do proximo, e o fim do
# ultimo = o inicio da propria tabela de ponteiros). Os ponteiros 7/8 apontam p/
# outra regiao (dados nao-sala) e nao sao usados.
FILEID_TBL = 0x8009dfd0

# SCE types (byte@+2) que DISPARAM troca de sala. Ambos os handlers da jump-table
# de SCE (0x8009e0bc) fazem `gs+0x2154 = descriptor` + `flag-troca 0x800c7960 = 1`,
# e o door_handler 0x800248e4 le do MESMO descriptor next_stage@+8 / next_room@+9:
#   sce==1  -> produtor de porta 0x80050d28  (jump-table[1]); porta normal (447x).
#   sce==13 -> handler 0x80051cb0 (jump-table[13]); porta CONDICIONAL/scripted:
#              seta flag-troca + descriptor em 0x80051d04/0x80051d10 apos gates de
#              estado (lbu 0x25b9; bit 0x100; 0x800e-0x44a8 & 0xc0). Mesmo layout de
#              descriptor (mesmo path). 6x, todos 0x61, formam 3 pares RECIPROCOS
#              (R114<->R118, R304<->R30A, R40C<->R40E). Provado por disassembly +
#              reciprocidade + chegada coerente. (Antes descartadas como "sce!=1".)
DOOR_SCE = {1, 13}                 # SCE types que sao PORTA (trocam de sala)
SCE_DOOR = 1                       # compat: SCE type "porta normal"
DOOR_OPCODES = {0x61: 32, 0x62: 40}  # opcodes que criam AOTs de porta (+ tamanho)
# opcode -> "path" da VM de AOT (a0 = AOT + path). 0x62 liga bit 0x80 -> path 0x14.
DOOR_PATH = {0x61: 0x0c, 0x62: 0x14}


def rdt_of(data):
    _fsz, bc = struct.unpack_from("<II", data, 0)
    lens = [struct.unpack_from("<I", data, 8 + i * 8)[0] for i in range(bc)]
    cur = SECTOR; st = []
    for i in range(bc):
        st.append(cur); cur = (cur + lens[i] + SECTOR - 1) // SECTOR * SECTOR
    return data[st[8]:st[8] + lens[8]]


def script_off(rdt):
    return struct.unpack_from("<22I", rdt, 8)[16]


def s16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


def fileid_tables():
    """Le a tabela de fileids 0x8009dfd0 do EXE. Retorna dict exe_stage(0..6) ->
    lista de u16 (fileid por indice interno). Comprimento de cada array derivado
    da contiguidade (fim = inicio do proximo ponteiro; ultimo = tabela de ponteiros)."""
    e = Exe(EXE)
    ptrs = [e.u32(FILEID_TBL + i * 4) for i in range(9)]
    bounds = [ptrs[s] for s in range(7)] + [FILEID_TBL]  # ptrs[0..6] monotonicos < TBL
    tbls = {}
    for s in range(7):
        p, nxt = bounds[s], bounds[s + 1]
        tbls[s] = [e.u16(p + i * 2) for i in range((nxt - p) // 2)]
    return tbls


def room_index_map():
    """(exe_stage, indice_interno) <-> nome Rxyz, pelo DE-PARA AUTORITATIVO do motor.

    O indice interno de uma sala = os digitos hex do nome (`Rxyz` -> int(yz,16)); esse
    e' exatamente o indice usado em `fileid = 0x8009dfd0[stage][room]` (room-loader
    0x800493ec). Como a tabela pode ter DUPLICATAS e slots vazios (0) -- varios indices
    apontando p/ o MESMO fileid (sala reusada/placeholder) nos stages 4/6/7 --, o de-para
    correto e' `indice -> fileid -> nome`, NAO posicao-ordenada-na-pasta (que quebra
    quando ha dups). Construimos:
      - name2si[nome]      = (stage, int(nome[2:],16))            (indice PROPRIO da sala)
      - fid2name[(stage,fileid)] = nome                          (do indice proprio)
      - si2name[(stage,idx)]     = fid2name[ tabela[stage][idx] ] (p/ QUALQUER idx valido)
    Assim `si2name` resolve tambem os indices que caem em dups (o fileid manda). Bate
    exato p/ stages 0-2 (sem dups) e fecha os stages 4/6/7 (com dups)."""
    tbls = fileid_tables()
    name2si = {}
    fid2name = {}
    for folder in sorted(glob.glob(os.path.join(CD, "STAGE*"))):
        st = int(os.path.basename(folder)[5:]) - 1
        if st not in tbls:
            continue
        t = tbls[st]
        for f in sorted(glob.glob(folder + "/R*.ARD")):
            name = os.path.basename(f)[:-4]
            idx = int(name[2:], 16)                 # indice interno = hex do nome
            name2si[name] = (st, idx)
            if idx < len(t) and t[idx] != 0:
                fid2name[(st, t[idx])] = name        # fileid PROPRIO da sala -> nome
    si2name = {}
    for st, t in tbls.items():
        for idx, fid in enumerate(t):
            if fid == 0:
                continue
            nm = fid2name.get((st, fid))
            if nm is not None:
                si2name[(st, idx)] = nm              # indice -> fileid -> nome (dups OK)
    return name2si, si2name


def extract_doors():
    """Extrai TODAS as portas (AOTs sce==1) do jogo com destino ESTATICO.
    Retorna (doors, name2si, si2name). Cada door e' um dict:
      src, si=(exe_stage,idx), opcode, aot(id), seq(por sala),
      raw_stage, raw_room, cut, arrival=(x,y,z,dir), box=(x,z,w,d)."""
    name2si, si2name = room_index_map()
    doors = []
    seq_by_room = defaultdict(int)
    for f in sorted(glob.glob(os.path.join(CD, "STAGE*", "R*.ARD"))):
        name = os.path.splitext(os.path.basename(f))[0]
        if name not in name2si:
            continue
        data = open(f, "rb").read()
        try:
            rdt = rdt_of(data); so = script_off(rdt)
        except Exception:
            continue
        tbl = struct.unpack_from("<H", rdt, so)[0]; nf = tbl // 2
        foffs = list(struct.unpack_from("<%dH" % nf, rdt, so))
        for fi in range(nf):
            start = so + foffs[fi]
            end = so + foffs[fi + 1] if fi + 1 < nf else len(rdt)
            pc = start; guard = 0
            while pc < end and pc + 1 < len(rdt) and guard < 8000:
                guard += 1
                op = rdt[pc]
                if op == 0x01:
                    break
                sz = VM_SIZES.get(op)
                if sz is None:
                    break
                if op in DOOR_OPCODES and pc + sz <= len(rdt) and rdt[pc + 2] in DOOR_SCE:
                    b = bytes(rdt[pc:pc + sz])
                    path = DOOR_PATH[op]
                    d = 2 + path  # offset do descriptor dentro do opcode
                    if op == 0x61:
                        # gatilho AABB: X@+6, Z@+8, W@+10, D@+12 (s16); chegada em +0xe
                        box = (s16(b, 6), s16(b, 8), s16(b, 10), s16(b, 12))
                    else:  # 0x62: 4-point -> AABB dos 4 vertices (x,z) em +6..+0x15
                        xs = [s16(b, 6 + 4 * k) for k in range(4)]
                        zs = [s16(b, 8 + 4 * k) for k in range(4)]
                        box = (min(xs), min(zs), max(xs) - min(xs), max(zs) - min(zs))
                    doors.append({
                        "src": name, "si": name2si[name], "opcode": op,
                        "sce": b[2],
                        "aot": b[1], "seq": seq_by_room[name],
                        "raw_stage": b[d + 8], "raw_room": b[d + 9],
                        "cut": b[d + 10] if d + 10 < sz else None,
                        "arrival": (s16(b, d), s16(b, d + 2), s16(b, d + 4), s16(b, d + 6)),
                        "box": box,
                    })
                    seq_by_room[name] += 1
                pc += sz
    return doors, name2si, si2name


def resolve(door, si2name):
    """(raw_stage,raw_room) -> nome Rxyz destino via de-para autoritativo do motor
    (indice interno -> fileid 0x8009dfd0[stage][room] -> nome). None so' se o indice
    cair fora da tabela ou em slot vazio (fileid 0)."""
    return si2name.get((door["raw_stage"] % 9, door["raw_room"]))


def load_twin_canon():
    """Mapa nome -> nome canonico (gemeos por fingerprint de colisao identico)."""
    fp = {}
    for f in glob.glob(os.path.join(DATA, "STAGE*", "R*_col.json")):
        nm = os.path.basename(f)[:4]
        c = json.load(open(f, encoding="utf-8"))
        rects = c.get("collision", {}).get("rects", [])
        if rects:
            fp[nm] = tuple(sorted(tuple(r["rect"]) for r in rects))
    fam = defaultdict(list)
    for n, k in fp.items():
        fam[k].append(n)
    canon = {}
    for members in fam.values():
        m = sorted(members)
        for n in m:
            canon[n] = m[0]
    return canon


def reciprocity(doors, si2name):
    canon = load_twin_canon()
    cn = lambda x: canon.get(x, x)
    edges = set()
    resolved = 0
    for d in doors:
        dn = resolve(d, si2name)
        if dn:
            resolved += 1
            edges.add((cn(d["src"]), cn(dn)))
    recip = sum(1 for a, b in edges if (b, a) in edges)
    return resolved, edges, recip


if __name__ == "__main__":
    doors, name2si, si2name = extract_doors()
    print("portas (AOT sce in {1,13}):", len(doors),
          "| opcodes:", dict(Counter(d["opcode"] for d in doors)),
          "| por sce:", dict(Counter(d["sce"] for d in doors)))
    print("distrib raw_stage (byte destino):",
          dict(sorted(Counter(d["raw_stage"] for d in doors).items())))
    resolved, edges, recip = reciprocity(doors, si2name)
    print("destino resolvido p/ nome:", resolved, "/", len(doors),
          "(de-para autoritativo indice->fileid 0x8009dfd0->nome; dups dos stages 4/6/7 resolvidas)")
    print("arestas-sala unicas (gemeas coladas):", len(edges),
          "| reciprocas:", recip,
          "(%.1f%%)" % (100.0 * recip / len(edges) if edges else 0))
    print("=> o par (stage,room) destino E' CAMPO ESTATICO do SCD (opcode 0x61/0x62, sce==1).")
