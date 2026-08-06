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
"""
import glob
import os
import subprocess
import sys

import paths

GOG_DEFAULT = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3"


def gog_root():
    return os.environ.get("NOSTALGIA_GOG") or GOG_DEFAULT


def ffmpeg_bin():
    base = os.path.join(paths.ROOT, "tools", "ffmpeg")
    for r, _d, fs in os.walk(base):
        for f in fs:
            if f.lower() in ("ffmpeg.exe", "ffmpeg"):
                return os.path.join(r, f)
    return None


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


def main(argv):
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
