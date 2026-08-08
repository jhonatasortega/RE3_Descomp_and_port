#!/usr/bin/env python3
"""Converte o áudio solto da instalação de PC para Ogg Vorbis no destino do port.

Fecha duas etapas que estavam MANUAIS no `build_assets.py`:

  • **bgm_render** — trilha: `DATA_A/SOUND/*.WAV` (125 faixas, PCM 22 kHz estéreo)
    → `<out>/assets/SOUND/BGM/gog/<nome minúsculo>.ogg`
    (é a fonte que o `bgm_map.json` já referencia: `BGM/gog/<track>.ogg`)
  • **voices_ptbr** — vozes dubladas: `DATA_A/VOICE/*.wav` (441)
    → `<out>/assets/VOICE/ptbr/<nome>.ogg`

Por que Ogg e não WAV: o Godot toca Ogg Vorbis nativo com loop e streaming, e os 441 WAV de
voz somam 310 MB (a trilha, outros 258 MB). Em Ogg isso cai para uma fração, sem diferença
audível no material do jogo (22 kHz).

Fonte: instalação de PC/GOG com o pacote PT-BR (ver docs/formatos/localizacao_ptbr.md).
**Somente leitura** — nada é modificado na instalação. Assets não redistribuíveis.

Uso:
    python tools/audio_gog.py               # trilha + vozes
    python tools/audio_gog.py --bgm         # só a trilha
    python tools/audio_gog.py --voice       # só as vozes
    python tools/audio_gog.py --force       # reconverte o que já existe
    python tools/audio_gog.py --quality 5   # qualidade do Vorbis (0..10, default 4)
    python tools/audio_gog.py --mapa        # gera data/bgm_map.json (de-para SALA -> faixa)
"""
import glob
import hashlib
import json
import os
import struct
import subprocess
import sys

import paths

GOG_DEFAULT = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"


def gog_root():
    return os.environ.get("NOSTALGIA_GOG") or GOG_DEFAULT


def _bin(nomes):
    base = os.path.join(paths.ROOT, "tools", "ffmpeg")
    for r, _d, fs in os.walk(base):
        for f in fs:
            if f.lower() in nomes:
                return os.path.join(r, f)
    return None


def ffmpeg_bin():
    return _bin(("ffmpeg.exe", "ffmpeg"))


def ffprobe_bin():
    return _bin(("ffprobe.exe", "ffprobe"))


def convert(ff, src, dst, quality, force):
    if os.path.isfile(dst) and not force:
        return "existe"
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    p = subprocess.run([ff, "-y", "-v", "error", "-i", src,
                        "-c:a", "libvorbis", "-q:a", str(quality), dst],
                       capture_output=True, text=True)
    if p.returncode != 0:
        return "ERRO: %s" % (p.stderr or "").strip()[:120]
    return "ok"


def lote(ff, arquivos, out_dir, quality, force, rotulo, minusculo=False):
    n_ok = n_skip = n_err = 0
    for i, src in enumerate(sorted(arquivos)):
        stem = os.path.splitext(os.path.basename(src))[0]
        if minusculo:
            stem = stem.lower()
        r = convert(ff, src, os.path.join(out_dir, stem + ".ogg"), quality, force)
        if r == "ok":
            n_ok += 1
        elif r == "existe":
            n_skip += 1
        else:
            n_err += 1
            print("  %-14s %s" % (stem, r))
        if (i + 1) % 50 == 0:
            print("  ... %d/%d" % (i + 1, len(arquivos)))
    print("%s: %d convertidos, %d já existiam, %d erros -> %s"
          % (rotulo, n_ok, n_skip, n_err, out_dir))
    return n_err


# ══════════════════════ de-para SALA -> FAIXA (medido) ══════════════════════
#
# O vínculo sala->trilha do RE3 PS1 **não é uma tabela**: cada `R###.ARD` CARREGA a própria
# música. O contêiner ARD tem 10 sub-blocos e os 8 primeiros são **4 pares (SEQ+VH, VB)**:
#
#   blk0/blk1  tipo 0x0005/0x0205   MAIN BGM #0   (SEQ + header VAB / corpo PS-ADPCM)
#   blk2/blk3  tipo 0x0005/0x0205   MAIN BGM #1
#   blk4/blk5  tipo 0x0006/0x0206   SUB  BGM #0   (camada de ambiente)
#   blk6/blk7  tipo 0x0006/0x0206   SUB  BGM #1
#   blk8       tipo 0x0000          RDT (lógica da sala)
#   blk9       tipo 0x0202          payload extra
#
# O bloco de tipo 5/6 começa com um **bloco de sequência** no formato do `.BGM`
# (`u32 tamanho, u32 tempo_us, u16 ppqn, u8 num, u8 den`, eventos estilo-MIDI com delta
# TRAILING — ver `tools/bgm2midi.py`) e termina com o header VAB (magic `0x0001eeee`).
#
# COMO O NOME É PROVADO: a instalação de PC guarda as MESMAS sequências como arquivos
# NOMEADOS em `Rofs7.dat` (`DATA/SOUND/MAIN00.BGM`..`MAIN3F.BGM`, `SUB_00.BGM`..`SUB_2C`,
# `SUB_3F`). Basta comparar o **sha1 do bloco** da ARD com o sha1 do arquivo do PC:
# **676/676 blocos (169 salas x 4) casam, 0 falhas** — 98 nomes distintos. `SUB_3F` é o
# bloco MUDO (116 B, sequência de 20 B com só `B0 0A 40` + `FF 2F 00`).
#
# O QUE CONTINUA NÃO MEDIDO: qual dos DOIS slots MAIN toca ao entrar na sala quando os dois
# têm música (64 salas). O port usa o primeiro não-mudo. Evidência a favor: em STAGE7 as 21
# salas de Mercenaries têm `MAIN3A` no slot 0, e a única sala com slot 0 mudo (`R70F`) tem
# `MAIN3A` no slot 1 — ou seja, a mesma faixa migra de slot, e "primeiro não-mudo" reproduz
# o conjunto. Idem STAGE6 com `MAIN3B`.
#
# ÚLTIMO PASSO (o único aproximado): a faixa TOCÁVEL do port é o Ogg vindo de
# `DATA_A/SOUND/<nome>.WAV`. O nome do WAV do PC **não é** garantidamente o render da
# sequência de mesmo nome: comparando a duração da sequência (ticks/ppqn * tempo) com a do
# WAV, 78 salas fecham em <= 1,5 %, outras batem só de forma aproximada e algumas divergem
# muito (ex.: `MAIN0D.BGM` = 80,2 s vs `MAIN0D.WAV` = 10,5 s -> são peças DIFERENTES).
# Só entra no `room_override` o que casa dentro de `TOL_MEDIA`; o resto fica no fallback por
# stage, com a divergência registrada em `salas[<sala>].erro_dur`.
SECTOR = 0x800
BGM_TIPOS = (0x0005, 0x0006)      # flagA dos blocos SEQ+VH (0x0205/0x0206 = o .VB do par)
MUDO = "SUB_3F"                   # bloco de 116 B = sequência vazia
# `DUMMY.BGM`, `MAIN3F.BGM` e `SUB_3F.BGM` do PC são BYTE-IDÊNTICOS (116 B, mesmo sha1): três
# nomes para o MESMO bloco mudo — é o único grupo de aliases nos 107 `.BGM` (107 arquivos ->
# 105 sha1 distintos). Normalizamos para `SUB_3F`; sem isto 296 dos 676 slots viravam
# "DUMMY"/"MAIN3F" e a sala parecia não ter música.
MUDOS = ("SUB_3F", "DUMMY", "MAIN3F")
TOL_ALTA = 0.015                  # duração casa: mesmo render, confiança ALTA
TOL_MEDIA = 0.20                  # casa de forma aproximada (loop do render difere)


def _rup(x, a):
    return (x + a - 1) // a * a


def ard_blocos(d):
    """Tabela de sub-blocos do contêiner ARD: [(indice, offset, tamanho, flagA, flagB)]."""
    _total, count = struct.unpack_from("<II", d, 0)
    pos = SECTOR
    out = []
    for i in range(count):
        length, fa, fb = struct.unpack_from("<IHH", d, 8 + i * 8)
        out.append((i, pos, length, fa, fb))
        pos = _rup(pos + length, SECTOR)
    return out


def seq_duracao(buf, start, end):
    """Duração (s) de TODOS os blocos de sequência em buf[start:end]."""
    from bgm2midi import parse_seq_block
    pos, total = start, 0.0
    while pos + 12 <= end:
        b = parse_seq_block(buf, pos)
        if b is None or b.get("error"):
            break
        tempo, ppqn, ticks = b["tempo"], b["ppqn"], 0
        for ev, dt in b["events"]:
            if ev[0] == 0xFF and ev[1] == 0x51:          # meta set-tempo
                total += ticks * tempo / ppqn / 1e6
                ticks, tempo = 0, int.from_bytes(ev[-3:], "big")
            ticks += dt
        total += ticks * tempo / ppqn / 1e6
        pos = b["end"]
    return total


def catalogo_pc(g):
    """{sha1: nome} e {nome: duracao_s} dos `DATA/SOUND/*.BGM` do `Rofs7.dat` do PC."""
    import rofs_extract
    p = os.path.join(g, "Rofs7.dat")
    if not os.path.isfile(p):
        return None, None
    data = open(p, "rb").read()
    _d1, _d2, entries = rofs_extract.list_entries(data)
    por_sha, dur = {}, {}
    # `SUB_3F` primeiro: os aliases mudos (`DUMMY`, `MAIN3F`) não devem roubar o nome.
    alvo = [e for e in entries if e[0].upper().endswith(".BGM")]
    alvo.sort(key=lambda e: (0 if e[0].upper().startswith(MUDO) else 1, e[0]))
    for nome, off, _ln in alvo:
        stem = os.path.splitext(nome)[0].upper()
        b = rofs_extract.extract_file(data, off)
        por_sha.setdefault(hashlib.sha1(b).hexdigest(), stem)
        dur[stem] = seq_duracao(b, 0, len(b))
    return por_sha, dur


def duracoes_wav(g):
    """{NOME: duracao_s} dos `DATA_A/SOUND/*.WAV` (a fonte dos Ogg do port)."""
    fp = ffprobe_bin()
    out = {}
    for f in sorted(glob.glob(os.path.join(g, "DATA_A", "SOUND", "*"))):
        if not f.lower().endswith(".wav"):
            continue
        r = subprocess.run([fp, "-v", "error", "-show_entries", "format=duration",
                            "-of", "csv=p=0", f], capture_output=True, text=True)
        try:
            out[os.path.splitext(os.path.basename(f))[0].upper()] = float(r.stdout.strip())
        except ValueError:
            pass
    return out


def _ogg_candidatos(nome, wav):
    """Nomes de WAV que podem ser o render de `nome` (o PC parte faixa em `_0`, `_1`...)."""
    if nome in wav:
        return [nome]
    partes = sorted(k for k in wav if k.startswith(nome + "_"))
    return partes


def salas_bgm(por_sha):
    """{sala: {"main": [n0, n1], "sub": [n0, n1]}} por sha1 dos blocos das 169 ARD."""
    salas = {}
    for f in sorted(glob.glob(paths.cd_data("STAGE*", "R*.ARD"))):
        sala = os.path.basename(f)[:4]
        d = open(f, "rb").read()
        main, sub = [], []
        for _i, off, ln, fa, _fb in ard_blocos(d):
            if fa not in BGM_TIPOS:
                continue
            nome = por_sha.get(hashlib.sha1(d[off:off + ln]).hexdigest())
            (main if fa == 0x0005 else sub).append(nome)
        salas[sala] = {"main": main, "sub": sub}
    return salas


def gerar_mapa(g):
    """Escreve `<out>/data/bgm_map.json` com o de-para SALA -> faixa medido."""
    por_sha, dur_seq = catalogo_pc(g)
    if por_sha is None:
        sys.exit("ERRO: %s não tem Rofs7.dat (preciso dos DATA/SOUND/*.BGM nomeados)"
                 % g)
    wav = duracoes_wav(g)
    salas = salas_bgm(por_sha)

    n_sem_nome = sum(1 for v in salas.values() for n in v["main"] + v["sub"] if n is None)
    override, detalhe = {}, {}
    conta = {"ALTA": 0, "MEDIA": 0, "NAO_CASADO": 0, "SEM_MAIN": 0}
    for sala, v in sorted(salas.items()):
        principal = next((n for n in v["main"] if n and n not in MUDOS), None)
        info = {"main": [None if n in MUDOS else n for n in v["main"]],
                "sub": [None if n in MUDOS else n for n in v["sub"]]}
        if principal is None:
            info["conf"] = "SEM_MAIN"           # sala sem música: só ambiente (SUB)
            conta["SEM_MAIN"] += 1
            detalhe[sala] = info
            continue
        info["ps1"] = principal
        cands = _ogg_candidatos(principal, wav)
        if not cands:
            info["conf"] = "NAO_CASADO"
            info["motivo"] = "DATA_A/SOUND não tem WAV com o nome %s" % principal
            conta["NAO_CASADO"] += 1
            detalhe[sala] = info
            continue
        alvo = sum(wav[c] for c in cands)
        erro = abs(dur_seq.get(principal, 0.0) - alvo) / max(alvo, 1e-3)
        info["erro_dur"] = round(erro, 4)
        info["dur_seq"] = round(dur_seq.get(principal, 0.0), 3)
        info["dur_wav"] = round(alvo, 3)
        if erro <= TOL_MEDIA:
            info["conf"] = "ALTA" if erro <= TOL_ALTA else "MEDIA"
            info["faixa"] = cands[0].lower()
            override[sala] = cands[0].lower()
        else:
            info["conf"] = "NAO_CASADO"
            info["motivo"] = ("o WAV de mesmo nome tem outra duração -> não é o render "
                              "desta sequência")
        conta[info["conf"]] += 1
        detalhe[sala] = info

    mapa = {
        "_meta": {
            "descricao": "Trilha do RE3 por SALA. Faixas em "
                         "res://assets/SOUND/BGM/gog/<faixa>.ogg (fonte DATA_A/SOUND do PC). "
                         "Gerado por tools/audio_gog.py --mapa.",
            "PROVA": "O de-para SALA -> BGM do PS1 é BYTE-EXATO: cada R###.ARD embute 4 pares "
                     "(SEQ+VH, VB) nos sub-blocos de tipo 0x05 (MAIN) e 0x06 (SUB), e o sha1 "
                     "de cada bloco casa com um DATA/SOUND/<nome>.BGM nomeado do Rofs7.dat do "
                     "PC em 676/676 blocos (169 salas x 4), 0 falhas, 98 nomes distintos. "
                     "SUB_3F = bloco MUDO.",
            "SLOT": "Qual dos 2 slots MAIN toca ao entrar NÃO foi medido (64 salas têm os "
                    "dois). Usamos o primeiro não-mudo; em STAGE6/STAGE7 isso reproduz o "
                    "conjunto observado (MAIN3B/MAIN3A em todas as salas, inclusive R70F, "
                    "onde a faixa está no slot 1).",
            "TODO": "`area_default` (por STAGE) segue PROVISORIO — é só o fallback das salas "
                    "em `NAO_CASADO`. O que é medido está em `room_override`/`salas`.",
            "RENDER": "faixa = o WAV do PC de MESMO nome, aceito quando a duração da "
                      "sequência do PS1 casa (<= %.1f%% = ALTA, <= %.0f%% = MEDIA). "
                      "`NAO_CASADO` = o nome do PS1 está provado mas o WAV homônimo do PC é "
                      "outra peça (ex.: MAIN0D 80,2 s vs 10,5 s)." % (TOL_ALTA * 100,
                                                                     TOL_MEDIA * 100),
            "areas": ["UPTOWN", "DOWNTOWN", "CLOCK_TOWER", "PARK", "DEAD_FACTORY",
                      "POLICE_STATION", "HOSPITAL"],
            "fallback": "Se a sala não estiver em room_override, cai na área do stage.",
            "contagem": conta,
            "blocos_sem_nome": n_sem_nome,
        },
        "default": "main2c",
        "area_default": {
            "UPTOWN": "main1e", "DOWNTOWN": "main1e", "CLOCK_TOWER": "main1a",
            "PARK": "main2a", "DEAD_FACTORY": "main2c", "POLICE_STATION": "main1d",
            "HOSPITAL": "main2d",
        },
        "context": {
            "TITLE": "main00", "SAVE": "main32", "SAVE_ALT": "main33",
            "DANGER": "main0a", "NEMESIS": "main0b", "GAMEOVER": "main1e",
            "ITEM_GET_JINGLE": "main21",
        },
        "room_override": override,
        "salas": detalhe,
    }
    out = paths.data("bgm_map.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(mapa, f, ensure_ascii=False, indent=1)
    print("%s\n  %d salas: %s\n  room_override: %d salas\n  blocos sem nome: %d"
          % (out, len(salas), conta, len(override), n_sem_nome))
    return mapa


def main(argv):
    if "--mapa" in argv:
        gerar_mapa(gog_root())
        return 0
    ff = ffmpeg_bin()
    if ff is None:
        sys.exit("ERRO: ffmpeg não encontrado em tools/ffmpeg")
    g = gog_root()
    quality = int(argv[argv.index("--quality") + 1]) if "--quality" in argv else 4
    force = "--force" in argv
    so_bgm = "--bgm" in argv
    so_voz = "--voice" in argv
    fazer_bgm = so_bgm or not so_voz
    fazer_voz = so_voz or not so_bgm
    print("ffmpeg: %s\ninstalacao: %s\nqualidade vorbis: %d" % (ff, g, quality))

    erros = 0
    if fazer_bgm:
        src = os.path.join(g, "DATA_A", "SOUND")
        arquivos = [f for f in glob.glob(os.path.join(src, "*"))
                    if f.lower().endswith(".wav")]
        if not arquivos:
            print("AVISO: nenhum WAV em %s (trilha)" % src)
        else:
            # minusculo: o bgm_map.json referencia as faixas em minusculas (main2c, main17...)
            erros += lote(ff, arquivos, paths.assets("SOUND", "BGM", "gog"), quality, force,
                          "trilha (BGM)", minusculo=True)
    if fazer_voz:
        src = os.path.join(g, "DATA_A", "VOICE")
        arquivos = [f for f in glob.glob(os.path.join(src, "*"))
                    if f.lower().endswith(".wav")]
        if not arquivos:
            print("AVISO: nenhum WAV em %s (vozes)" % src)
        else:
            erros += lote(ff, arquivos, paths.assets("VOICE", "ptbr"), quality, force,
                          "vozes PT-BR")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
