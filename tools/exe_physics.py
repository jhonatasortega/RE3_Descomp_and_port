#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Gera godot/data/physics.json a partir da FONTE (EXE SLUS_009.23 + PL00.PLD).

Fecha a dívida P0-11 do physics.json: antes era uma semente ad-hoc; agora o build o
produz do disco/EXE. Partes DINÂMICAS (extraídas a cada build):
  * sin_cos_table  : metadados validados contra a tabela real no EXE (0x800a3310 /
                     file 0x93b10, 1025×s16, T[0]=0, T[1024]=4096). Os 1025 valores
                     crus ficam em ps1_sincos.json (tools/exe_sincos.py); aqui vai só
                     o descritor (endereço, simetria) — igual à semente.
  * velocidades.*  : motion_por_pose_xyz = deslocamento do root POR FRAME, medido de
                     PL00.PLD (banco base, seq0=andar / seq10=correr / seq3=giro);
                     vel_un_por_frame_media/pico = média/máx da magnitude XZ do delta.
Partes ESTÁTICAS (conhecimento de eng. reversa, versionado como constante aqui):
  ângulo 12 bits, fórmula de integração root-motion, offsets do player-struct, fps,
  spans de sala medidos (world_scale) e giro_graus_por_frame por clipe.

Uso:
    python tools/exe_physics.py            # extrai + grava <out>/data/physics.json
    python tools/exe_physics.py --compare  # compara os DADOS gerados com a semente
"""
import json
import math
import os
import struct
import sys

import paths
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import find_anim_banks as F

EXE = paths.extracted("SLUS_009.23")
PLD = paths.cd_data("PLD", "PL00.PLD")
SIN_FILE_OFF = 0x93B10
SIN_RAM = 0x800A3310
SIN_N = 1025
SIN_AMP = 4096

# giro (net-Y do clipe) por frame — medido do ângulo do osso 0 de PL00.PLD (12 bits).
# Constante documentada: a rotação net não sai do delta de translação do root.
GIRO_GRAUS_POR_FRAME = {"andar_frente": 0.072, "correr_frente": 0.0, "giro": 3.386}
SEQ = {"andar_frente": 0, "correr_frente": 10, "giro": 3}
ANIM = {"andar_frente": "anim00", "correr_frente": "anim10", "giro": "anim03"}


def read_sin_table():
    b = open(EXE, "rb").read()
    t = list(struct.unpack_from("<%dh" % SIN_N, b, SIN_FILE_OFF))
    assert t[0] == 0 and t[SIN_N - 1] == SIN_AMP, "tabela sin/cos não confere no EXE"
    return t


def seq_root_frames(b, bank, s):
    """Root (x,y,z) por frame de uma sequência EDD (PL00.PLD pose+0x00 s16 x,y,z)."""
    kf, nb, fsz = F.is_emr(b, bank["emr"]); pool = bank["emr"] + kf
    edd = bank["edd"]
    nf = F.u16(b, edd + s * 8); fo = F.u16(b, edd + s * 8 + 2); ps = F.u32(b, edd + s * 8 + 4)
    fl = edd + fo; out = []
    for f in range(nf):
        prel = F.u16(b, fl + f * 2) & 0xff
        po = pool + (ps + prel) * fsz
        out.append((F.s16(b, po), F.s16(b, po + 2), F.s16(b, po + 4)))
    return out


def measure_velocity(b, bank, name):
    r = seq_root_frames(b, bank, SEQ[name])
    d = [[r[f + 1][i] - r[f][i] for i in range(3)] for f in range(len(r) - 1)]
    mags = [math.hypot(dx, dz) for dx, _dy, dz in d]
    media = round(sum(mags) / len(mags), 1)
    pico = round(max(mags), 1)
    return len(r), d, media, pico


def build():
    sin_t = read_sin_table()          # valida a tabela real no EXE
    b = open(PLD, "rb").read()
    _ents, banks = F.all_banks(b)
    base = banks[0]                    # banco base/desarmado (22 seqs, 531 poses)

    vel = {}
    for name in ("andar_frente", "correr_frente", "giro"):
        nf, motion, media, pico = measure_velocity(b, base, name)
        v = {
            "anim": ANIM[name],
            "nframes": nf if name != "andar_frente" else nf,
        }
        if name == "andar_frente":
            v["timing"] = {
                "nframes_jogo": nf, "poses": nf,
                "mapeamento_frame_pose": "1:1 (frame-list = pose 0..33, sem hold) => duracao exata",
                "fps_gameplay": 30, "duracao_s": round(nf / 30.0, 3),
                "loop": "ciclo completo [0..33] -> 0; passada de 2 passos (flags de som nos frames 5 e 22)",
                "frame_list_offset": "EDD+176 (0xB8 no arquivo PLD); 2B/frame: baixo=pose, alto=flag de evento",
            }
        v["vel_un_por_frame_media"] = media
        v["vel_un_por_frame_pico"] = pico
        v["giro_graus_por_frame"] = GIRO_GRAUS_POR_FRAME[name]
        v["motion_por_pose_xyz"] = motion
        vel[name] = v
    vel["unidade"] = "unidades PS1 do modelo; 1 personagem ~2400 un de altura; ver world_scale"

    return {
        "_meta": {
            "descricao": "Constantes de movimento/fisica da Jill (RE3 PS1 NTSC-U, SLUS_009.23) por eng. reversa.",
            "gerado_por": "tools/exe_physics.py (sin/cos do EXE + root-motion medido de PL00.PLD)",
            "achado_chave": "O movimento do RE3 e ROOT-MOTION (dirigido por animacao): NAO existe uma constante escalar de 'velocidade de andar' no executavel. O deslocamento por frame vem de VETORES DE MOVIMENTO por POSE, guardados na tabela de poses do personagem (carregada de PL00.PLD), rotacionados pela direcao atual e somados a posicao no mundo. O que E constante e universal (angulo de 12 bits, tabela de seno, formula de integracao) esta abaixo com ALTA confianca; os escalares de velocidade sao MEDIDOS do root de PL00.PLD.",
        },
        "angle_units": {
            "_confianca": "ALTA",
            "full_circle": 4096, "bits": 12, "graus_por_unidade": 0.087890625, "half_turn": 2048,
            "evidencia": "mascara 'andi ang,0xfff' e bit de menor-rotacao 'andi ...,0x800' no controlador do player (0x8001a248..0x8001a5b0).",
        },
        "sin_cos_table": {
            "_confianca": "ALTA (match exato indices 0..1024)",
            "endereco": hex(SIN_RAM), "file_offset": hex(SIN_FILE_OFF),
            "entradas": SIN_N, "tipo": "s16", "amplitude": SIN_AMP,
            "cobertura": "quarto de onda: indices 0..1024 = 0..90 graus (0..4096 unidades de angulo)",
            "rsin_por_simetria": [
                "a in [0,1024):    TBL[a]",
                "a in [1024,2048): TBL[2048-a]",
                "a in [2048,3072): -TBL[a-2048]",
                "a in [3072,4096): -TBL[4096-a]",
            ],
            "rcos": "rsin(a + 1024)",
            "nota": "tabela de QUARTO de onda (nao circulo completo); escala 1.0 == 4096 (ponto-fixo 12 bits). Reconstruir sin/cos por simetria. Valores crus dos 1025 em ps1_sincos.json (tools/exe_sincos.py).",
        },
        "integracao": {
            "_confianca": "ALTA (estrutural)",
            "modelo": "root-motion", "player_control_fn": "0x8001a248",
            "formula": "pos_mundo += rotate(pose_motion_vec, facing_angle) ; rotacao usa a matriz do modelo construida com sin_cos_table (lib GTE em 0x80088000+)",
            "player_struct_offsets": {
                "+0x74": "angulo de direcao atual (facing, 12 bits)",
                "+0x108": "ponteiro p/ tabela de poses (do PLD); stride 0xbc (188) por pose",
                "+0x114": "ponteiro p/ estado/animacao secundaria",
                "+0x120": "pad segurado (bits: 0x10=cima,0x20=direita,0x40=baixo,0x80=esquerda,0x800=R1)",
                "+0x121": "pose/rotina atual (indice na tabela de poses)",
                "+0x164/+0x166/+0x168": "contadores/sub-posicao de interpolacao",
                "pose_entry+0x54..0x60": "vetor de MOVIMENTO da pose (dx,dy,dz,..) = fonte da velocidade",
                "pose_entry+0x62": "parametro de rotacao/velocidade da pose",
            },
            "pose_table_setter": "0x80026184 (sw a1,0x108(a0)) - a1 vem do parse de PL00.PLD",
        },
        "fps": {
            "_confianca": "ALTA (cruzado com a frame-list do EDD)",
            "ntsc_field_hz": 60, "gameplay_fps": 30,
            "nota": "RE3 PS1 processa gameplay a 30 fps. Confirmado pela frame-list do EDD: cada registro EDD tem 'nframes' = numero de frames de JOGO e uma frame-list (EDD+176, 2B/frame) que mapeia frame->pose. Para o andar (anim00) e 1 pose por frame (34 frames = 34 poses), logo duracao = 34/30 = 1.133s. O pld2gltf ja usa FPS=30 => a duracao do andar esta CORRETA.",
        },
        "world_scale": {
            "_confianca": "ALTA (medido dos dados de sala)",
            "unidade": "mesma escala do ARD (coords de camera/porta)",
            "room_span_x_mediana": 19150, "room_span_z_mediana": 15250,
            "nota": "medido das posicoes de porta+entidade em 124 salas. Caixas de trigger de porta ~900-2560 un. Jill ~ altura de poucos milhares de unidades.",
        },
        "velocidades": {
            "_confianca": "ALTA (MEDIDO em PL00.PLD, root em pose+0x00 s16 x,y,z; delta por frame)",
            "_fonte": "tools/exe_physics.py (find_anim_banks) sobre PL00.PLD banco base; deslocamento por frame = delta do root acumulado entre poses consecutivas.",
            "_nota_offset": "No struct de RAM (188B, player+0x108) o vetor de movimento fica em pose+0x54; no ARQUIVO PL00.PLD (poses de 76B) o mesmo dado e o root em pose+0x00 s16 x,y,z. O giro/facing vem do angulo Y do osso 0 (pose+8, angulo idx 1, 12 bits).",
            **vel,
        },
        "pendencias": [
            "RESOLVIDO: passo de fisica = 30 fps (frame-list do EDD: nframes por sequencia = frames de jogo).",
            "RESOLVIDO: o ANDAR e anim00 (nao anim16). anim16 e passo lateral/virar. Ver godot/data/anim_map.json 'mapa_do_exe'.",
            "RESOLVIDO: vetores de movimento reais extraidos de PL00.PLD -> velocidades.*.motion_por_pose_xyz; deltas por frame em anim_map.json 'timing_e_loop'.",
            "Validar in-game o candidato de andar_tras (anim11) e o par de virar (anim15/anim16 vs anim03).",
            "OPCIONAL: fazer pld2gltf seguir a frame-list (respeitar holds/reuso) p/ clipes nao-1:1 (o andar anim00 ja e 1:1, sem impacto).",
        ],
    }


DATA_FIELDS = ("angle_units", "sin_cos_table", "fps", "world_scale")


def compare(gen):
    """Compara os DADOS (números e estrutura) gerados com a semente atual."""
    seed = json.load(open(os.path.join(paths.ROOT, "godot", "data", "physics.json"), encoding="utf-8"))
    ok = True
    for k in DATA_FIELDS:
        g, s = gen[k], seed[k]
        if k == "sin_cos_table":     # 'nota' é prosa (o gerador estende p/ apontar ps1_sincos.json)
            g = {kk: vv for kk, vv in g.items() if kk != "nota"}
            s = {kk: vv for kk, vv in s.items() if kk != "nota"}
        same = g == s
        print("  [%s] %s" % ("ok" if same else "DIF", k)); ok = ok and same
    for name in ("andar_frente", "correr_frente", "giro"):
        gv, sv = gen["velocidades"][name], seed["velocidades"][name]
        for f in ("motion_por_pose_xyz", "vel_un_por_frame_media", "vel_un_por_frame_pico",
                  "giro_graus_por_frame", "nframes"):
            same = gv.get(f) == sv.get(f)
            print("  [%s] velocidades.%s.%s" % ("ok" if same else "DIF", name, f)); ok = ok and same
    print("  ==> DADOS %s a semente" % ("EQUIVALENTES" if ok else "DIVERGEM DA"))
    return ok


def main(argv):
    gen = build()
    if "--compare" in argv:
        return 0 if compare(gen) else 1
    out = paths.data("physics.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    json.dump(gen, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("gravado", out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
