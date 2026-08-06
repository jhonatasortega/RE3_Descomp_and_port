#!/usr/bin/env python3
"""Parser do formato de sala .ARD do Resident Evil 3 (PS1, NTSC-U) -> JSON.

O .ARD e um contêiner alinhado a setor de CD (0x800) que guarda 10 sub-blocos:
graficos/VRAM (texturas e mascaras de profundidade) e o "RDT" com a logica da
sala (cameras, colisao, modelos de objeto, script SCD). Este script decodifica o
que ja foi confirmado byte-a-byte (ver docs/formatos/ARD.md):

  - cabecalho do contêiner + tabela de blocos (10 entradas);
  - cabecalho do RDT + tabela de offsets (22 ponteiros);
  - lista de CAMERAS (posicao/alvo em ponto-fixo 3D)  -> totalmente decodificada;
  - SCRIPT SCD: tabela de funcoes + PORTAS, TRIGGERS de area e ENTIDADES posicionadas
    (via varredura por assinatura de opcode) -> ver docs/formatos/SCD.md.

Itens/inimigos no RE3 sao posicionados via opcodes DENTRO do script SCD (nao ha tabela
estatica). Portas (0x67), triggers/aot (0x63/0x64) e entidades (0x61/0x62) ja sao
extraidos; o mapeamento fino de item_id/tipo de inimigo depende das tabelas SCE do exe.

Python puro (so stdlib). Uso:

    # uma sala:
    python ard_parse.py extracted/ntsc-u/CD_DATA/STAGE1/R100.ARD

    # todas as salas de todos os stages (varre extracted/.../STAGE*):
    python ard_parse.py --all

    # escolher raiz de entrada e de saida:
    python ard_parse.py --all --in extracted/ntsc-u/CD_DATA --out godot/data

Saida (espelha o disco):  godot/data/STAGE{n}/<nome>.json
"""
import sys
import os
import glob
import json
import struct
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

SECTOR = 0x800          # blocos sao alinhados a 2048 bytes (setor de CD)
N_BLOCKS = 10           # todo .ARD do RE3 tem exatamente 10 sub-blocos
RDT_BLOCK = 8           # o bloco 8 (flagA==0x0000) e sempre o RDT (logica da sala)
CAM_STRIDE = 32         # cada camera ocupa 32 bytes
OFFTAB_N = 22           # tabela de offsets do RDT: 22 ponteiros u32 a partir de +0x08
OFF_CAMERAS = 7         # indice da tabela que aponta as cameras (RID)
OFF_SCRIPT = 16         # indice da tabela que aponta o script SCD

# Rotulo de cada tipo de bloco (byte baixo de flagA). Ver ARD.md.
BLOCK_ROLE = {
    0x00: "rdt",         # logica da sala (cameras, colisao, script...) — DECODIFICADO
    0x05: "graphics_a",  # VRAM: descritor de textura/CLUT + imagem (sprite/mascara)
    0x06: "graphics_b",  # idem, segundo conjunto
    0x02: "mask_extra",  # payload extra de mascara/sprite (comprimido)
}


def rup(x, a):
    """Arredonda x para cima ao proximo multiplo de a."""
    return (x + a - 1) // a * a


def parse_blocks(data):
    """Le o cabecalho do contêiner e devolve a lista de blocos (offset/len/flags)."""
    total, count = struct.unpack_from("<II", data, 0)
    blocks = []
    pos = SECTOR                      # os dados comecam no setor 1 (0x800)
    for i in range(count):
        length, flag_a, flag_b = struct.unpack_from("<IHH", data, 8 + i * 8)
        blocks.append({
            "index": i,
            "offset": pos,
            "length": length,
            "type": flag_a & 0xFF,            # categoria do recurso
            "variant": (flag_a >> 8) & 0xFF,  # 0x00=cru / 0x02=payload(provavel comprimido)
            "checksum": flag_b,               # provavel hash do conteudo
            "role": BLOCK_ROLE.get(flag_a & 0xFF, "unknown"),
        })
        pos = rup(pos + length, SECTOR)
    return total, count, blocks


def parse_cameras(rdt, cam_ptr, n_cut):
    """Decodifica a lista de cameras (RID) a partir de rdt[cam_ptr:], n_cut entradas."""
    cams = []
    for c in range(n_cut):
        o = cam_ptr + c * CAM_STRIDE
        if o + CAM_STRIDE > len(rdt):
            break
        flag, attr, fx, fy, fz, tx, ty, tz, mask_ptr = struct.unpack_from(
            "<HH6iI", rdt, o)
        cams.append({
            "index": c,
            "flag": flag,            # u16 (quase sempre 0, as vezes 1)
            "attr": attr,            # u16 — provavel FOV/projecao (24 valores distintos no jogo)
            "from": [fx, fy, fz],    # posicao da camera (ponto-fixo mundo)
            "to": [tx, ty, tz],      # alvo/olhar da camera
            "mask_data_ptr": mask_ptr,  # offset (no RDT) da mascara de profundidade desta camera
        })
    return cams


def parse_rvd(rdt, off, n_cameras):
    """Decodifica as ZONAS DE TROCA DE CAMERA (RVD / "camera switch").

    Apontadas por offset_table[8] (confirmado nas salas de STAGE1: o bloco comeca
    logo depois das cameras e casa com o marcador 0x8001 no 1o campo). Cada entrada
    tem 20 bytes e a lista termina em 0xFFFF:

        +0x00  u16  flags        // bits de controle (0x8001, 0x0100, ...); 0xFFFF = fim
        +0x02  u8   from_cam     // camera de ORIGEM (voce esta nela)
        +0x03  u8   to_cam       // camera de DESTINO (troca pra ela ao entrar no quad)
        +0x04  s16[8]            // 4 pontos (x,z) do quadrilatero no plano do chao

    Semantica (engenharia reversa sobre as 169 salas; ver docs/formatos/ARD.md 3.5):
    cada entrada e uma ZONA DIRECIONAL `from -> to`. `degenerate=true` (coord +-32768)
    = quad ilimitado (frustum) -- NAO e' a cobertura propria da camera (427/456 deg tem
    from != to). As zonas `from != to` sao FAIXAS de histerese na FRONTEIRA entre
    cameras (vem em pares opostos deslocados), nao a area toda da camera de destino --
    por isso o remake NAO as usa como gatilho de borda (enquadra mal no corte), e sim
    escolhe a camera por ENQUADRAMENTO, usando o RVD como grafo de vizinhanca. Ver
    docs/formatos/ARD.md 3.5 (pseudo-codigo) e docs/godot_gameplay.md.

    ---- FLAGS: papel FINO fechado (round 100%; 4585 entradas / 169 salas) ----
    O u16 `flags` = [byte ALTO = id de GRUPO/zona de camera][byte BAIXO = controle].
    * byte BAIXO bit0 (0x01) = ZONA ATIVA. bit0=0 aparece em 246 entradas, e 245/246 sao
      `from != to` -> fronteira/limite DESATIVADO (nao dispara troca). Conf ALTA.
    * byte ALTO = ID DE GRUPO/ZONA de camera (nao "prioridade" solta). PROVA estrutural:
      em R101 o byte alto AGRUPA as cameras por regiao espacial -- grupo 1 = {0,1,8..13},
      grupo 2 = {2,7}, grupo ~3/4 = {3,4,5,6}; as transicoes DENTRO/PARA um grupo carregam
      o id daquele grupo. `0x80` (93,7 %, dominante) = grupo PADRAO/global (todas as voltas
      `to=0`/hub e a cobertura geral). Pequenos 0x01..0x1f = sub-grupos espaciais especificos.
      `0xff` (R107) = grupo especial/max. Conf ALTA (clustering espacial limpo).
    * `degenerate` vem so das COORDENADAS (+-32768), NAO do flag. Confirmado: 456 degenerate,
      449 com alto=0x80, cobrindo tanto `from==to` (29) quanto `from!=to` (427). Conf ALTA.

    ---- CONSUMIDOR PER-FRAME DO RVD -- LOCALIZADO E PROVADO NO EXE (round 100%) ----
    O "residuo" antigo ("a funcao consumidora nao foi localizavel estaticamente") esta
    FECHADO. A rotina que a cada frame le a posicao do player + a tabela RVD e decide a
    camera e' **0x8002a84c** (SLUS_009.23, base 0x80010000). Ela NAO aparecia nos xrefs
    por stride porque le o RDT via load ABSOLUTO (`lui 0x800d; lw -0x3794(...)` =
    0x800cc86c = gs+0x2134), nao via `lw 0x2134(gsreg)`. Prova byte-a-byte:
      - RVD ptr = `*(0x800cc86c) + 0x28` (offset_table[8]); confirmado tambem no finder
        0x8002a968 (`lw $v0,-0x3794($..)` ; `lw $v1,0x28($v0)`).
      - STRIDE 0x14 (20 B): 0x8002a87c `addiu $s1,$a0,0x14`; 0x8002a8d4/0x8e8 `addiu ..,0x14`.
        Ancora de HISTERESE: comeca da entrada ATIVA atual gs+0x2148 (0x8002a874) e varre
        o bloco contiguo cujo from_cam == camera atual (0x8002a8e4 `beq next.from,cur`).
      - from_cam(+2) == camera atual gs+0x2486: 0x8002a880 `lbu $v1,2($s1)` / 0x8002a888 `bne`.
      - **TESTE DE BIT0 / ZONA ATIVA (byte baixo dos flags, +0):** 0x8002a894 `lbu $v0,($s1)`
        + 0x8002a89c `beqz $v0` -> PULA a entrada se o byte baixo == 0. Como os flags reais
        so tem baixo 0x00/0x01, isso == teste de bit0 (0x01=ativa). PROVADO no codigo.
      - **USO DO BYTE-ALTO (GRUPO, flags +1):** 0x8002a8a4 `lb $v1,-1($s0)` (= entry+1) +
        0x8002a8ac `beq $v1,-0x80` (0x80 = grupo wildcard/global) OU 0x8002a8bc
        `bne $v1, gs+0x2495` (seletor de grupo em runtime) -> so avalia a entrada se o
        grupo casa. Confirma "byte-alto = id de grupo" NO CODIGO (0x80 = global; senao
        precisa == grupo corrente gs+0x2495). Eleva a semantica de "inferida por clustering"
        para "provada no binario".
      - PONTO-EM-QUAD = 0x8001020c(a0 = player gs+0x24c0 [X@+0, Z@+8], a1 = entry): le os 4
        pontos do quad em entry+4/+6, +8/+0xa, +0xc/+0xe, +0x10/+0x12 e faz 4 testes de
        sinal de produto vetorial (aresta a aresta). Player X/Z em gs+0x24c0/+0x24c8
        (escritos em 0x8002498c/0x800249c0).
      - to_cam(+3): 0x8002a8fc `lbu $a0,3($s1)`. COMMIT via 0x8002a938 (seta req-cam
        gs+0x2486 e ancora gs+0x2148); a maquina de estados de fade 0x8005190c faz a
        transicao e por fim copia gs+0x7846(alvo)->gs+0x7842 (INDICE DE CAMERA CORRENTE
        usado pelo render/GTE em 0x80074fd0 e 0x80029edc: `lh cur,0x7842; sll cur,5` ->
        indexa camera[cur] em rdt+0x24).
      - CHAMADORES per-frame: 0x80023b84 (a0=0) e 0x80024abc (a0=1); o arg a0 controla
        detectar-vs-commitar (0x8002a8ec `bnez $s4`), dando a histerese em 2 fases.
    O opcode SCD 0x80054a68 (handler; avanca PC+3) REMAPEIA from/to no RVD em runtime
    (puzzles que trocam roteamento de camera) -- corrobora o layout (rdt+0x28, stride 0x14,
    from@+2, to@+3). O remake continua usando o RVD como grafo + enquadramento (equivalente
    e sem flicker), independente do bit-test agora provado.
    """
    base = off[8] if len(off) > 8 else 0
    if not (0 < base < len(rdt) - 4):
        return None
    laters = [t for t in off if t > base]
    end = min(laters) if laters else len(rdt)
    entries = []
    o = base
    while o + 20 <= end:
        flags = struct.unpack_from("<H", rdt, o)[0]
        if flags == 0xFFFF:
            break
        frm = rdt[o + 2]
        to = rdt[o + 3]
        pts = struct.unpack_from("<8h", rdt, o + 4)
        # sanidade: cameras validas; senao provavelmente saimos da secao
        if frm > 64 or to > 64:
            break
        quad = [[pts[0], pts[1]], [pts[2], pts[3]], [pts[4], pts[5]], [pts[6], pts[7]]]
        degenerate = any(abs(v) >= 32000 for v in pts)
        entries.append({
            "flags": flags,
            "from": frm,
            "to": to,
            "quad": quad,               # [[x,z] x4] no plano do chao (unidades PS1)
            "degenerate": degenerate,   # True = quad de fronteira (+-32768), nao gatilho
            "active": bool(flags & 0x01),      # bit0 do byte baixo = zona ATIVA (senao fronteira desativada)
            "cam_group": (flags >> 8) & 0xff,  # byte ALTO = id de grupo/zona de camera (0x80 = grupo padrao/global)
        })
        o += 20
    return {
        "offset_in_rdt": base,
        "count": len(entries),
        "entries": entries,
        "note": ("zonas de troca de camera (from->to + quad). Ver ard_parse.parse_rvd. "
                 "flags = [alto=cam_group][baixo: bit0=active]; 'degenerate' (+-32768) = "
                 "quad de fronteira/frustum (vem das coords, nao do flag)."),
    }


def parse_script(rdt, script_off, offtab_all):
    """Mapeia o script SCD: a 1a u16 e o tamanho da tabela de ponteiros de funcao."""
    if not (0 < script_off < len(rdt) - 2):
        return None
    tbl_size = struct.unpack_from("<H", rdt, script_off)[0]
    if tbl_size < 2 or tbl_size % 2 or script_off + tbl_size > len(rdt):
        return None
    n_func = tbl_size // 2
    func_offs = list(struct.unpack_from("<%dH" % n_func, rdt, script_off))

    # Delimita a secao do script (ate o proximo offset da tabela do RDT).
    later = [t for t in offtab_all if script_off < t <= len(rdt)]
    end = min(later) if later else len(rdt)
    code = rdt[script_off:end]

    placements = scan_placements(code)
    return {
        "offset_in_rdt": script_off,
        "func_count": n_func,
        "func_offsets": func_offs,   # relativos ao inicio do script
        "doors": placements["doors"],
        "events": placements["events"],
        "entities": placements["entities"],
        "note": ("posicionamento por opcodes SCD (ver docs/formatos/SCD.md). "
                 "items/enemies exatos dependem de decode adicional do sat_type/type."),
    }


def _s16(b, o):
    return struct.unpack_from("<h", b, o)[0] if o + 2 <= len(b) else 0


def scan_placements(code):
    """Varre o bytecode SCD procurando os opcodes de posicionamento (assinaturas
    de bytes fixos, robusto a opcodes ainda nao mapeados). Ver docs/formatos/SCD.md.

      0x67 door_aot_set (24B): porta — caixa de trigger + destino.
      0x63 sce_aot_set  (20B): trigger de area (sat_type distingue item/evento/etc).
      0x64 sce_aot_set_4p(28B): trigger de area em 4 pontos (quadrilatero).
      0x61 / 0x62       (32B): entidade posicionada (inimigo/NPC/objeto) — pos + type.
    """
    doors, events, entities = [], [], []
    n = len(code)
    i = 0
    while i < n - 3:
        b = code[i]
        # --- porta (door_aot_set) — stride REAL de 62 bytes (ver docs/formatos/SCD.md) ---
        if (b == 0x67 and i + 62 <= n and code[i + 2] == 0x02
                and code[i + 3] == 0x31 and code[i + 5] == 0):
            g = code[i:i + 62]
            if abs(_s16(g, 6)) < 32000 and 0 < _s16(g, 10) < 20000:
                # posicao de ENTRADA: precedida do marcador 'ff 00 60 10 00' (off ~33)
                entry = None
                m = bytes(g).find(b"\xff\x00\x60\x10\x00")
                if m != -1 and m + 13 <= 62:
                    ex, ez = _s16(g, m + 5), _s16(g, m + 9)
                    if 2000 < abs(ex) < 40000 and 2000 < abs(ez) < 40000:
                        entry = {"x": ex, "y": _s16(g, m + 7), "z": ez, "dir": _s16(g, m + 11)}
                doors.append({
                    "aot": g[1],
                    "pos": [_s16(g, 6), _s16(g, 8)],       # x, z (centro da caixa de trigger)
                    "size": [_s16(g, 10), _s16(g, 12)],    # w, d
                    "entry": entry,                        # posicao de entrada na sala-destino (quando presente)
                    "dest_raw": list(g[14:24]),            # bytes de destino (sala/cam ainda NAO decodificados)
                    "raw62": list(g),                      # struct completo (para decodificacao futura do destino)
                })
                i += 62
                continue
        # --- trigger de area (sce_aot_set) ---
        if (b == 0x63 and i + 20 <= n and code[i + 3] in (0x31, 0x41, 0x51, 0x61)
                and code[i + 5] == 0):
            g = code[i:i + 20]
            if abs(_s16(g, 6)) < 32000:
                events.append({
                    "kind": "aot",
                    "aot": g[1],
                    "sat_type": g[2],                      # tipo do trigger (item/evento/msg/...)
                    "floor": g[3],
                    "pos": [_s16(g, 6), _s16(g, 8)],
                    "size": [_s16(g, 10), _s16(g, 12)],
                    "data": list(g[14:20]),
                })
                i += 20
                continue
        # --- trigger de area em 4 pontos (sce_aot_set_4p) ---
        if (b == 0x64 and i + 28 <= n and code[i + 3] == 0x31 and code[i + 5] == 0):
            g = code[i:i + 28]
            events.append({
                "kind": "aot_4p",
                "aot": g[1],
                "sat_type": g[2],
                "points": [[_s16(g, 6 + 4 * k), _s16(g, 8 + 4 * k)] for k in range(4)],
            })
            i += 28
            continue
        # --- entidade (inimigo/NPC/objeto) ---
        if (b in (0x61, 0x62) and i + 32 <= n and code[i + 2] == 0x01
                and code[i + 3] == 0x21 and code[i + 5] == 0):
            g = code[i:i + 32]
            entities.append({
                "opcode": b,
                "index": g[23],
                "type": g[24],                             # tipo da entidade (a mapear p/ inimigos)
                "pos": [_s16(g, 6), _s16(g, 8)],
            })
            i += 32
            continue
        i += 1
    return {"doors": doors, "events": events, "entities": entities}


def parse_ard(data, name=""):
    """Parseia um .ARD inteiro e devolve um dicionario pronto para virar JSON."""
    if len(data) < 8 + N_BLOCKS * 8:
        raise ValueError("arquivo pequeno demais para ser um .ARD")
    total, count, blocks = parse_blocks(data)

    result = {
        "file": name,
        "size": len(data),
        "size_header": total,
        "size_match": (total == len(data)),
        "block_count": count,
        "blocks": blocks,
    }

    # Localiza o RDT (bloco tipo 0x00; sempre indice 8 nas 169 salas).
    rdt_blocks = [b for b in blocks if b["type"] == 0x00]
    if not rdt_blocks:
        result["rdt"] = None
        return result
    rb = rdt_blocks[0]
    rdt = data[rb["offset"]: rb["offset"] + rb["length"]]

    header = list(rdt[:8])
    n_cut = header[1]                                   # numero de cameras
    offtab = list(struct.unpack_from("<%dI" % OFFTAB_N, rdt, 0x08))
    cam_ptr = offtab[OFF_CAMERAS]                       # == 0x60 nas 169 salas
    script_off = offtab[OFF_SCRIPT]

    result["rdt"] = {
        "block_index": rb["index"],
        "length": rb["length"],
        "header_bytes": header,      # bytes 0..7; byte[1] = n_cameras
        "n_cameras": n_cut,
        "offset_table": offtab,      # 22 ponteiros (offsets dentro do RDT); 0 = ausente
        "offset_table_roles": {      # papeis confirmados/ provaveis (ver ARD.md)
            str(OFF_CAMERAS): "cameras (RID)",
            "8": "camera_switches (RVD: zonas from->to + quad de chao) — DECODIFICADO",
            "10": "provavel dados de luz/objeto (ponteiros; logo apos as cameras)",
            str(OFF_SCRIPT): "script (SCD)",
        },
        "cameras": parse_cameras(rdt, cam_ptr, n_cut),
        "rvd": parse_rvd(rdt, offtab, n_cut),
        "script": parse_script(rdt, script_off, offtab),
    }
    return result


def stage_of(path):
    """Extrai 'STAGEn' do caminho, ou None."""
    for part in path.replace("\\", "/").split("/"):
        if part.upper().startswith("STAGE"):
            return part.upper()
    return None


def process(path, out_root):
    data = open(path, "rb").read()
    name = os.path.basename(path)
    parsed = parse_ard(data, name)
    stage = stage_of(path) or "STAGE_UNKNOWN"
    out_dir = os.path.join(out_root, stage)
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(name)[0]
    dest = os.path.join(out_dir, base + ".json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(parsed, f, ensure_ascii=False, indent=2)
    ncam = len(parsed.get("rdt", {}).get("cameras", []) if parsed.get("rdt") else [])
    return dest, ncam


def main(argv):
    args = argv[1:]
    in_root = "extracted/ntsc-u/CD_DATA"
    out_root = paths.data()
    do_all = False
    files = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--all":
            do_all = True
        elif a == "--in":
            i += 1
            in_root = args[i]
        elif a == "--out":
            i += 1
            out_root = args[i]
        else:
            files.append(a)
        i += 1

    if do_all:
        files = sorted(glob.glob(os.path.join(in_root, "STAGE*", "*.ARD")))
    if not files:
        print(__doc__)
        return 1

    ok = 0
    total_cam = 0
    for p in files:
        try:
            dest, ncam = process(p, out_root)
            total_cam += ncam
            ok += 1
            if len(files) <= 10 or ok % 50 == 0:
                print(f"  OK {os.path.basename(p):12s} -> {dest}  ({ncam} cameras)")
        except Exception as e:
            print(f"  ERRO {os.path.basename(p):12s}: {e}")
    print(f"\n{ok}/{len(files)} salas -> {out_root}  ({total_cam} cameras no total)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
