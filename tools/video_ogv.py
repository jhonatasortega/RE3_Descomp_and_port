#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Converte os FMV em HD (`zmovie/*.mp4`) para **Ogg Theora**, o único formato de
vídeo que o Godot 4 toca nativamente.

POR QUE TRANSCODIFICAR (a decisão, com o custo de cada caminho)
--------------------------------------------------------------
O `VideoStreamPlayer` do Godot 4 só tem um backend embutido: **Theora**
(`VideoStreamTheora`). Os três caminhos possíveis e o que custa cada um:

(a) **Transcodificar mp4 -> ogv** (ESCOLHIDO).
    Custo: Theora é um codec de 2004 e rende pior que H.264 no mesmo bitrate, e o
    `libtheora` do ffmpeg é **monothread** — medido nesta máquina: ~0,27 s por quadro
    em 1280×960, ou seja **~8× o tempo real** (`opn`, 90,6 s / 2716 quadros, levou
    ~12 min e saiu com ~60 MB contra 135 MB do mp4 em `-q:v 8`). É um custo de
    pipeline, pago uma vez, e o resultado toca sem dependência externa.
(b) **GDExtension de vídeo** (ffmpeg/libvlc). Zero perda de qualidade, mas exige
    compilar e distribuir um binário nativo por plataforma. Custo alto e recorrente,
    para um projeto de estudo que já é pesado de assets.
(c) **Sequência de imagens + áudio separado**. Sem perda de codec, mas 2716 WebP de
    1280×960 (~150 KB cada) = ~400 MB só na abertura, mais o trabalho de sincronizar
    áudio à mão. Pior em tudo que (a).

Como o port já é 1280×960 e os `.mp4` do pacote PT-BR são exatamente 1280×960
h264 29,97 fps **com áudio dublado em português**, (a) mantém resolução, taxa e
faixa de áudio sem reescalar nada.

⚠ **AVISO DE ESCRITA:** este script só escreve em `<out>/assets/ZMOVIE/`. A
instalação do jogo é lida SOMENTE PARA LEITURA. Os `.ogv` são assets da Capcom +
trabalho de fãs: **não versionar, não redistribuir** (mesma política de
`docs/formatos/hd_seamless.md` §6).

Uso:
    NOSTALGIA_OUT=port python tools/video_ogv.py opn          # um vídeo
    NOSTALGIA_OUT=port python tools/video_ogv.py --abertura    # só o que o boot usa
    NOSTALGIA_OUT=port python tools/video_ogv.py --todos       # os 14 (leva ~1 h)
    python tools/video_ogv.py --listar                         # inventário + duração
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths                                   # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FF_DIR = os.path.join(RAIZ, "tools", "ffmpeg", "ffmpeg-master-latest-win64-gpl", "bin")
FFMPEG = os.path.join(FF_DIR, "ffmpeg.exe")
FFPROBE = os.path.join(FF_DIR, "ffprobe.exe")
ZMOVIE_PADRAO = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3\zmovie"

#: O que o FLUXO DE ABERTURA precisa. `opn` é o FMV que `OPENING.BIN` (ovl 5) toca
#: depois de o TITLE ler o `INIT_TBL.DAT` (`0x801960d8`); `roop` é o atrator.
ABERTURA = ["opn", "roop"]
#: Qualidade do vídeo (0..10 no libtheora). 8 = o maior que ainda dá arquivo menor que
#: o mp4 de origem. DECLARADO: escolha do port, não medida.
QV_PADRAO = 8
QA_PADRAO = 4                                   # libvorbis 0..10


def ffprobe(caminho):
    """`{largura, altura, fps, duracao, audio_codec, audio_canais}` de um vídeo."""
    if not os.path.exists(FFPROBE):
        return {}
    r = subprocess.run([FFPROBE, "-v", "error", "-print_format", "json",
                        "-show_format", "-show_streams", caminho],
                       capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return {}
    out = {"duracao": float(d.get("format", {}).get("duration", 0) or 0)}
    for s in d.get("streams", []):
        if s.get("codec_type") == "video":
            num, den = (s.get("r_frame_rate", "0/1").split("/") + ["1"])[:2]
            out.update(largura=s.get("width"), altura=s.get("height"),
                       video_codec=s.get("codec_name"),
                       fps=(float(num) / float(den)) if float(den) else 0.0)
        elif s.get("codec_type") == "audio":
            out.update(audio_codec=s.get("codec_name"), audio_canais=s.get("channels"),
                       audio_hz=s.get("sample_rate"),
                       audio_idioma=(s.get("tags") or {}).get("language"))
    return out


def converter(nome, src_dir, qv=QV_PADRAO, qa=QA_PADRAO, forcar=False):
    src = os.path.join(src_dir, nome + ".mp4")
    if not os.path.exists(src):
        return dict(nome=nome, ok=False, motivo="sem %s.mp4 em %s" % (nome, src_dir))
    dst_dir = paths.assets("ZMOVIE")
    os.makedirs(dst_dir, exist_ok=True)
    dst = os.path.join(dst_dir, nome + ".ogv")
    info = ffprobe(src)
    if os.path.exists(dst) and not forcar:
        return dict(nome=nome, ok=True, pulado=True, saida=dst,
                    bytes=os.path.getsize(dst), origem=info)
    t0 = time.time()
    cmd = [FFMPEG, "-y", "-hide_banner", "-loglevel", "error", "-i", src,
           "-c:v", "libtheora", "-q:v", str(qv),
           "-c:a", "libvorbis", "-q:a", str(qa), "-ar", "44100", dst]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return dict(nome=nome, ok=False, motivo=r.stderr.strip()[:400])
    return dict(nome=nome, ok=True, pulado=False, saida=dst, bytes=os.path.getsize(dst),
                segundos_de_encode=round(time.time() - t0, 1), origem=info,
                origem_bytes=os.path.getsize(src))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("nomes", nargs="*", help="nomes sem extensão (opn, ins01, enda…)")
    ap.add_argument("--zmovie", default=None, help="pasta zmovie/ da instalação")
    ap.add_argument("--abertura", action="store_true", help="só %s" % ", ".join(ABERTURA))
    ap.add_argument("--todos", action="store_true", help="todos os .mp4 da pasta")
    ap.add_argument("--listar", action="store_true", help="só inventaria, não converte")
    ap.add_argument("--forcar", action="store_true", help="reconverte se já existir")
    ap.add_argument("--qv", type=int, default=QV_PADRAO)
    ap.add_argument("--qa", type=int, default=QA_PADRAO)
    a = ap.parse_args()

    src_dir = a.zmovie or os.environ.get("NOSTALGIA_ZMOVIE") or ZMOVIE_PADRAO
    if not os.path.isdir(src_dir):
        print("zmovie não encontrado: %s" % src_dir)
        return 1
    if not os.path.exists(FFMPEG):
        print("ffmpeg não encontrado em %s (baixe para tools/ffmpeg/)" % FF_DIR)
        return 1

    disponiveis = sorted(os.path.splitext(os.path.basename(p))[0]
                         for p in glob.glob(os.path.join(src_dir, "*.mp4")))
    if a.listar:
        print("%-8s %-11s %-8s %8s  %-10s %s" % ("nome", "resolução", "fps",
                                                 "duração", "áudio", "MB"))
        for n in disponiveis:
            i = ffprobe(os.path.join(src_dir, n + ".mp4"))
            print("%-8s %-11s %-8.2f %7.2fs  %-10s %.1f"
                  % (n, "%sx%s" % (i.get("largura"), i.get("altura")), i.get("fps", 0),
                     i.get("duracao", 0), "%s %sch" % (i.get("audio_codec"),
                                                       i.get("audio_canais")),
                     os.path.getsize(os.path.join(src_dir, n + ".mp4")) / 1e6))
        print("\nAVISO: a etiqueta de idioma do contêiner diz 'eng' nos 14 arquivos, mas o "
              "\náudio é o do pacote PT-BR (a instalação é a versão dublada — ver "
              "\ndocs/formatos/localizacao_ptbr.md §3). Etiqueta != conteúdo; confirme "
              "\nOUVINDO, eu não tenho como ouvir.")
        return 0

    alvos = a.nomes or (ABERTURA if a.abertura else (disponiveis if a.todos else []))
    if not alvos:
        ap.print_usage()
        print("\nnada a fazer: passe nomes, --abertura, --todos ou --listar")
        return 1

    print("destino = %s/assets/ZMOVIE  (q:v=%d q:a=%d)" % (paths.name(), a.qv, a.qa))
    for n in alvos:
        r = converter(n, src_dir, a.qv, a.qa, a.forcar)
        if not r.get("ok"):
            print("  FALHA %-7s %s" % (n, r["motivo"]))
            continue
        o = r.get("origem", {})
        if r.get("pulado"):
            print("  já existe %-7s %.1f MB" % (n, r["bytes"] / 1e6))
            continue
        print("  ok %-7s %sx%s %.2f fps %.1fs  mp4 %.1f MB -> ogv %.1f MB  em %.0f s (%.1f× tempo real)"
              % (n, o.get("largura"), o.get("altura"), o.get("fps", 0), o.get("duracao", 0),
                 r["origem_bytes"] / 1e6, r["bytes"] / 1e6, r["segundos_de_encode"],
                 r["segundos_de_encode"] / max(o.get("duracao", 1), 0.001)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
