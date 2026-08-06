#!/usr/bin/env python3
"""Decodifica COLISAO (SCA) e o layout das MASCARAS de profundidade do RDT do RE3.

Duas secoes do RDT, ate agora "sem papel", foram decodificadas byte-a-byte:

1. COLISAO  -> offset_table[6]   -- FORMATO FECHADO CONTRA O EXE (2026-07-31)
   Cabecalho de 16 bytes:
       +0x00  s16 count         // inclui o proprio cabecalho como registro 0
       +0x04  s16 cx1, cz1      // CENTRO 1 (broadphase de quadrante)
       +0x08  s16 cx2, cz2      // CENTRO 2 -- pode ser DIFERENTE do 1 (R101)
       +0x0E  s16 ?             // 0 em todas as salas medidas
   Depois, `count-1` registros de 16 bytes:
       +0x00  s16 f0, f1        // par de coordenadas 1 (x,z) -- ORDEM CRUA, nao normalizar
       +0x04  s16 f2, f3        // par de coordenadas 2 (x,z)
       +0x08  u16 bits          // 0..3 FORMA | 4..5 canto (forma 6) | 6..15 ESTADO (script)
       +0x0A  u16 mask          // 0..7 bitmap de QUADRANTE | 8..11 arestas (formas 9/10)
       +0x0C  s8  base          // base do collider em Y = -1800 * base
       +0x0D  s8  nivel         // nivel/andar (informativo; 15 nas paredes da sala)
       +0x0E  s16 topo          // topo do collider em Y

   O collider NAO E UMA CAIXA CHEIA: cada forma e uma LISTA DE SEGMENTOS, e o motor
   testa se o SEGMENTO DE MOVIMENTO (origem->destino) cruza algum deles, por interseccao
   segmento-x-segmento na GTE (NCLIP, `0x8004ef74`). Tabela de 16 formas em `0x8009e088`:

       forma 0      circulo inscrito: raio=(f2-f0)/2, centro no meio da caixa. Bloqueia se o
                    trajeto cruza o DIAMETRO PERPENDICULAR ao movimento ou se o DESTINO
                    esta dentro do circulo.                                  (632 registros)
       forma 1,7    retangulo pelas DUAS DIAGONAIS: (f0,f3)-(f2,f1) e (f0,f1)-(f2,f3).
                    E uma aproximacao do proprio jogo: raspar um canto NAO colide. (3163)
       forma 2      linha media em Z + 2 diagonais deslocadas de (f3-f1)/2 em X.      (484)
       forma 3      linha media em X + 2 diagonais deslocadas de (f2-f0)/2 em Z.      (373)
       forma 4      cruz "+" das duas linhas medias.                                   (17)
       forma 5      uma diagonal: (f0,f1)-(f2,f3).                                      (3)
       forma 6      "L" de DUAS arestas perpendiculares; o CANTO vem de `bits & 0x30`
                    (0x00/0x10/0x20/0x30 = os 4 cantos -- e por isso que os tipos
                    observados sao 6, 22, 38 e 54). A 3a diagonal devolve 2, e o
                    chamador do PLAYER descarta o 2.                                  (463)
       forma 9,10   retangulo com as 4 ARESTAS MASCARAVEIS por `mask` bits 8..11
                    (0x100 = aresta x0, 0x200 = z1, 0x400 = x1, 0x800 = z0).          (121)
       forma 8,11,12  `return 0` -- NUNCA colide.                                      (33)

   Filtros aplicados ANTES da forma (laco `0x8004e830`):
       1. `bits & mascara_do_chamador` (player = 0x40; outro consumidor usa 0x2000)
       2. QUADRANTE: `mask & codigo`, onde codigo = 1<<(sinal_x + 2*sinal_z) para o
          centro 1 (bits 0..3) e o mesmo << 4 para o centro 2 (`0x8004d6b8`). Origem e
          destino sao testados; se os quadrantes diferem, o codigo e 0xff (todos).
       3. ALTURA (so quando o chamador passa a3 bit 0 -- o player passa):
          pula se `topo > maxY` ou se `(-1800*base) < minY` do trajeto.
   79% dos registros tem base 0 (terreo); os outros sao andares/saliencias e o teste de
   altura os descarta quando o jogador esta no chao.

2. MASCARAS -> camera[i].mask_data_ptr  (offset dentro do RDT) -- FORMATO 100% FECHADO.
   RE completa em docs/decomp/notes/occlusion.md. Sistema de "priority sprites" do PS1:
   o cenario que fica NA FRENTE do personagem e redesenhado por cima dele. Formato RE3
   (reevengi .RDT, herdado do RE1/RE2), VALIDADO byte-a-byte nas 1507 cameras com mascara
   (soma dos counts == n_masks em 1507/1507; 0 overruns). Layout (little-endian):
       +0x00  u16 n_offsets   // nº de GRUPOS (0xFFFF = sem mascara)
       +0x02  u16 n_masks     // total de sprites
       n_offsets DESCRITORES de grupo, 8 bytes cada:
         +0x00 u16 count      // sprites deste grupo (SOMA dos counts == n_masks)  [invariante]
         +0x02 u16 z_base     // CONSTANTE 30720 (0x7800) em todas as cameras (Z-base do OT)
         +0x04 u16 add_x      // deslocamento de TELA somado ao dst de cada sprite do grupo
         +0x06 u16 add_y
       depois: n_masks SPRITES (em ordem de grupo). Discriminador de tamanho: byte +6:
         - SQUARE (8 bytes): byte +6 != 0
             +0x00 u8 sx, +0x01 u8 sy   // ORIGEM no atlas de mascara (godot/assets/MASK, VRAM PS1)
             +0x02 u8 dx, +0x03 u8 dy   // canto do sprite na TELA (px, espaco 320x240)
             +0x04 u16 depth            // Z/16 (RE1: "distancia/16"); Z real = depth*16
             +0x06 u8 size              // largura E altura (w=h), em px; != 0
             +0x07 u8 0
         - RECT (12 bytes): byte +6 == 0 (marcador; w/h explicitos)
             +0x00 u8 sx, +0x01 u8 sy
             +0x02 u8 dx, +0x03 u8 dy
             +0x04 u16 depth
             +0x06 u16 0                // marcador de "rect"
             +0x08 u16 w
             +0x0A u16 h
   TELA de cada sprite = (dx + add_x, dy + add_y). Z per-sprite = depth*16 (mesma familia de
   unidade do z_base 30720; faixa observada ~48..49136). O atlas (sx,sy) foi CONFIRMADO contra
   a mascara HD (godot/assets/MASK): 100% do alpha do atlas cai dentro das regioes src
   decodificadas (recall=1.0, escala horizontal 8x na R100).

   CORRECAO (fecha oclusao 80%->100%): a decodificacao ANTERIOR estava com os CAMPOS TROCADOS
   (lia `attr`/`w` de bytes que na verdade sao sx/sy; discriminador errado em byte +2; header de
   grupo tratado como 4B/"lista plana"). O correto e': header de grupo de 8B com add_x/add_y de
   TELA, discriminador em byte +6, e a ordem sx,sy,dx,dy,depth,size. O antigo `depth0`=30720 e' o
   z_base do descritor (constante). O Z de ordenacao real e' o `depth` POR-SPRITE (+0x04)*16.
     ACHADOS (1507 cameras / 111644 mascaras): RECT(12B)=85748 (76.8%), SQUARE(8B)=25896 (23.2%);
     598 cameras sem mascara (n_offsets=0xFFFF ou n_masks=0). z_base = 30720 em 100% dos grupos.

Uso:
    python tools/rdt_collision.py                 # todas as salas de todos os stages
    python tools/rdt_collision.py STAGE1/R100     # uma sala

Saida:  godot/data/STAGE{n}/{sala}_col.json
"""
import os
import sys
import glob
import json
import struct
import paths  # destino do pipeline (NOSTALGIA_OUT) - ver tools/paths.py

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IN_ROOT = os.path.join(ROOT, "extracted", "ntsc-u", "CD_DATA")
OUT_ROOT = paths.data()
SECTOR = 0x800


def rup(x, a):
    return (x + a - 1) // a * a


def load_rdt(path):
    data = open(path, "rb").read()
    _, count = struct.unpack_from("<II", data, 0)
    pos = SECTOR
    for i in range(count):
        length, fa, _ = struct.unpack_from("<IHH", data, 8 + i * 8)
        if (fa & 0xFF) == 0x00:
            return data[pos:pos + length]
        pos = rup(pos + length, SECTOR)
    return None


def decode_collision(rdt, off):
    """offset_table[6] -> registros CRUS de colisao (ver secao 1 da docstring do modulo).

    Emite os 4 campos de coordenada na ORDEM CRUA (`raw`), porque a forma decide o que
    cada par significa -- normalizar min/max destroi a informacao. O campo `rect`
    (normalizado) continua saindo, mas serve APENAS para desenho/broadphase: usar ele
    como caixa cheia cobre a sala inteira (medido na R101: 0% caminhavel).
    """
    base = off[6]
    if not base or base + 16 > len(rdt):
        return None
    count = struct.unpack_from("<I", rdt, base)[0]
    if count < 1 or count > 4000:
        return None
    cx1, cz1, cx2, cz2 = struct.unpack_from("<4h", rdt, base + 4)
    # +0x0E: Y de piso PADRAO da sala (fallback do floor_height 0x8004d720; 0 em 154/169)
    piso_padrao = struct.unpack_from("<h", rdt, base + 14)[0]
    rects = []
    for k in range(1, count):
        o = base + 16 * k
        if o + 16 > len(rdt):
            break
        f0, f1, f2, f3, bits, mask = struct.unpack_from("<4hHH", rdt, o)
        base_lv, nivel = struct.unpack_from("<2b", rdt, o + 0x0C)
        topo = struct.unpack_from("<h", rdt, o + 0x0E)[0]
        # sanidade: cantos plausiveis (dentro de +-32768). Mantemos +-32000 (paredes
        # que encostam na borda) mas descartamos lixo obvio.
        if not all(-32768 <= v <= 32767 for v in (f0, f1, f2, f3)):
            continue
        rects.append({
            "raw": [f0, f1, f2, f3],                # ordem CRUA (a forma interpreta)
            "rect": [min(f0, f2), min(f1, f3), max(f0, f2), max(f1, f3)],  # so desenho
            "forma": bits & 0x0F,                   # indice na tabela 0x8009e088
            "canto": (bits >> 4) & 0x03,            # forma 6: qual "L"
            "bits": bits,                           # +0x08 completo (filtro 1 usa isto)
            "mask": mask,                           # +0x0A: quadrante | arestas
            "base": base_lv,                        # base Y = -1800 * base
            "base_y": -1800 * base_lv,
            "nivel": nivel,
            "topo": topo,                           # topo Y (s16)
            # compat: campos antigos (y era lido como altura -- e bitfield; ver docstring)
            "y": bits if bits < 0x8000 else bits - 0x10000,
            "h": mask if mask < 0x8000 else mask - 0x10000,
            "type": [base_lv & 0xFF | (nivel & 0xFF) << 8, topo],
            "wall": (k <= 4),   # heuristica: os 4 primeiros sao a moldura da sala
        })
    return {
        "offset_in_rdt": base,
        "count_field": count,
        "center": [cx1, cz1],
        "center2": [cx2, cz2],
        "piso_padrao": piso_padrao,
        "rects": rects,
    }


def decode_masks(rdt, cam_ptr):
    """camera.mask_data_ptr -> priority sprites (1o plano por camera). Formato RE3 completo.

    Ver docstring do modulo (secao 2) e docs/decomp/notes/occlusion.md. Emite os sprites
    como REGIOES de TELA (dx,dy,w,h em 320x240, com o add_x/add_y do grupo ja SOMADO) com o
    Z per-sprite RESOLVIDO (depth*16), reagrupados por profundidade (formato que o remake usa
    direto: cameras_masks[cam].groups[{depth, blocks:[{dx,dy,w,h,sx,sy,z}]}]).
    """
    if not cam_ptr or cam_ptr + 4 > len(rdt):
        return None
    n_offsets, n_masks = struct.unpack_from("<HH", rdt, cam_ptr)
    if n_offsets == 0xFFFF or n_masks == 0 or n_offsets == 0 or n_offsets > 512:
        return None                                  # sem mascara / cabecalho invalido
    o = cam_ptr + 4
    descs = []                                       # (count, z_base, add_x, add_y) por grupo
    for _ in range(n_offsets):
        if o + 8 > len(rdt):
            return None
        descs.append(struct.unpack_from("<4H", rdt, o))
        o += 8
    if sum(d[0] for d in descs) != n_masks:          # invariante do formato (1507/1507)
        return None
    z_base = descs[0][1]
    buckets = {}                                     # z per-sprite -> lista de blocos de tela
    gi, rem = 0, descs[0][0]
    parsed = 0
    for _ in range(n_masks):
        while rem == 0 and gi < len(descs) - 1:
            gi += 1
            rem = descs[gi][0]
        if o + 8 > len(rdt):
            break
        add_x, add_y = descs[gi][2], descs[gi][3]
        if rdt[o + 6] == 0:                          # RECT (12 bytes)
            if o + 12 > len(rdt):
                break
            sx, sy, dx, dy = rdt[o], rdt[o + 1], rdt[o + 2], rdt[o + 3]
            depth = rdt[o + 4] | (rdt[o + 5] << 8)
            w = rdt[o + 8] | (rdt[o + 9] << 8)
            h = rdt[o + 10] | (rdt[o + 11] << 8)
            o += 12
        else:                                        # SQUARE (8 bytes)
            sx, sy, dx, dy = rdt[o], rdt[o + 1], rdt[o + 2], rdt[o + 3]
            depth = rdt[o + 4] | (rdt[o + 5] << 8)
            w = h = rdt[o + 6]
            o += 8
        z = depth * 16                               # RE1: depth = distancia/16
        buckets.setdefault(z, []).append({
            "dx": dx + add_x, "dy": dy + add_y,      # canto na TELA (320x240), add ja aplicado
            "w": w, "h": h,                          # tamanho do sprite (px de tela)
            "sx": sx, "sy": sy,                      # origem no atlas de mascara (godot/assets/MASK)
            "z": z,                                  # Z per-sprite (menor = mais perto da camera)
        })
        rem -= 1
        parsed += 1
    # grupos = 1 por profundidade per-sprite, do mais PERTO (menor z) ao mais LONGE.
    groups = [{"depth": z, "count": len(b), "blocks": b}
              for z, b in sorted(buckets.items())]
    return {
        "offset_in_rdt": cam_ptr,
        "n_offsets": n_offsets,
        "n_masks": n_masks,
        "parsed_masks": parsed,
        "z_base": z_base,                            # 30720 (0x7800) constante
        "primary_depth": groups[0]["depth"] if groups else z_base,   # plano mais a frente
        "groups": groups,
    }


def decode_priority_zones(rdt, off, n_cameras):
    """offset_table[14] -> ZONAS DE PRIORIDADE (banco da Ordering Table por regiao do chao).

    E o dado que decide a CAMADA de oclusao do personagem (achado 2026-08-01, EXE):
    o RE3 nao compara profundidade sprite-a-sprite -- e painter's algorithm na OT do PS1.
    A OT tem 1024 entradas por BANCO e N+1 bancos (N = u16 no inicio desta secao, 0..3).
    Cada sprite de mascara entra com bank = depth>>10 / entry = depth & 1023 (o `depth` CRU
    do RDT). O personagem entra com bank = zona desta secao que contem o (x,z) dele
    (`0x80037d50`) e entry = media dos SZ >> 5. Ordem de desenho: banco N..1 e por ultimo o
    banco 0 -> CHAVE MENOR = desenhado DEPOIS = na frente.

    Layout (base = offset_table[14]; 78/169 salas tem):
        +0x00 u16 N_EXTRA_BANKS  (medido: {0,1,2,3})
        +0x02 u16 n_cam_entries  (<= n_cameras)
        +0x04 u32 off[cam]       (RELATIVO a base)
    bloco por camera: +0 u16 n_zones, +2 u16 (nao lido), depois entradas:
        +0 u8 flags (bit1=IGNORAR) | +1 u8 type (0=RECT 12B, !=0=QUAD 20B) | +2 u16 bank
        RECT: +4 s16 x0, +6 s16 z0, +8 u16 w, +10 u16 h   (dentro: 0<=px-x0<=w unsigned)
        QUAD: +4..+0x12 = 4 pontos (s16 x, s16 z)
    """
    base = off[14] if len(off) > 14 else 0
    if not (0 < base < len(rdt) - 8):
        return None
    n_banks, n_cam = struct.unpack_from("<HH", rdt, base)
    if n_banks > 8 or n_cam > max(n_cameras, 1) or n_cam == 0:
        return None
    out = {"n_extra_banks": n_banks, "cameras": []}
    for c in range(n_cam):
        rel = struct.unpack_from("<I", rdt, base + 4 + c * 4)[0]
        o = base + rel
        if not (0 < o < len(rdt) - 4):
            out["cameras"].append([])
            continue
        n_zones = struct.unpack_from("<H", rdt, o)[0]
        o += 4
        zonas = []
        for _ in range(min(n_zones, 64)):
            if o + 12 > len(rdt):
                break
            flags, typ, bank = struct.unpack_from("<BBH", rdt, o)
            if typ == 0:
                x0, z0, w, h = struct.unpack_from("<2h2H", rdt, o + 4)
                zonas.append({"flags": flags, "bank": bank, "rect": [x0, z0, w, h]})
                o += 12
            else:
                pts = struct.unpack_from("<8h", rdt, o + 4)
                zonas.append({"flags": flags, "bank": bank,
                              "quad": [[pts[0], pts[1]], [pts[2], pts[3]],
                                       [pts[4], pts[5]], [pts[6], pts[7]]]})
                o += 20
        out["cameras"].append(zonas)
    return out


def process(path):
    rdt = load_rdt(path)
    if rdt is None:
        return None
    off = list(struct.unpack_from("<22I", rdt, 8))
    n_cut = rdt[1]
    cams = []
    for c in range(n_cut):
        o = 0x60 + c * 32
        mask_ptr = struct.unpack_from("<I", rdt, o + 0x1C)[0]
        cams.append(decode_masks(rdt, mask_ptr))
    return {
        "collision": decode_collision(rdt, off),
        "cameras_masks": cams,
        "priority_zones": decode_priority_zones(rdt, off, n_cut),
    }


def stage_of(path):
    for part in path.replace("\\", "/").split("/"):
        if part.upper().startswith("STAGE"):
            return part.upper()
    return "STAGE_UNKNOWN"


def main(argv):
    args = argv[1:]
    if args:
        files = []
        for a in args:
            files.append(os.path.join(IN_ROOT, a if a.upper().endswith(".ARD") else a + ".ARD"))
    else:
        files = sorted(glob.glob(os.path.join(IN_ROOT, "STAGE*", "*.ARD")))
    ok = 0
    ncol = 0
    for p in files:
        try:
            res = process(p)
            if res is None:
                print("  ERRO %s: sem RDT" % os.path.basename(p))
                continue
            stage = stage_of(p)
            out_dir = os.path.join(OUT_ROOT, stage)
            os.makedirs(out_dir, exist_ok=True)
            base = os.path.splitext(os.path.basename(p))[0]
            dest = os.path.join(out_dir, base + "_col.json")
            json.dump(res, open(dest, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            nr = len(res["collision"]["rects"]) if res["collision"] else 0
            ncol += nr
            ok += 1
            if len(files) <= 12 or ok % 50 == 0:
                nm = sum((c["n_masks"] if c else 0) for c in res["cameras_masks"])
                print("  OK %-12s -> %s  (%d colisoes, %d blocos de mascara)"
                      % (os.path.basename(p), os.path.relpath(dest, ROOT), nr, nm))
        except Exception as e:
            print("  ERRO %s: %s" % (os.path.basename(p), e))
    print("\n%d/%d salas  (%d retangulos de colisao no total)" % (ok, len(files), ncol))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
