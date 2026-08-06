#!/usr/bin/env python3
"""Raiz de saída do pipeline de assets — um só lugar para decidir 'onde escrever'.

Antes desta camada cada script tinha `godot/assets` / `godot/data` fixo no código.
Agora o destino é parametrizado pela variável de ambiente **`NOSTALGIA_OUT`**:

    NOSTALGIA_OUT=port   python tools/bss2png.py --all     -> port/assets, port/data
    (sem a variável)     python tools/bss2png.py --all     -> godot/assets, godot/data

O default é `godot` **de propósito**: mantém o comportamento histórico dos scripts
(nada quebra) enquanto o port novo passa a ser alvo explícito. Quem normalmente
define a variável é `tools/build_assets.py --out port` (item P0-02 do plano).

Aceita caminho relativo à raiz do repo (`port`, `godot`) ou absoluto.

Ver: docs/port/PLANO_MIGRACAO.md · docs/port/PROGRESSO.md (P0-02, P0-03)
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_VAR = "NOSTALGIA_OUT"
DEFAULT_OUT = "godot"


def out_root(*parts):
    """Raiz de saída (absoluta), opcionalmente com sub-caminho."""
    o = os.environ.get(ENV_VAR, DEFAULT_OUT).strip() or DEFAULT_OUT
    base = o if os.path.isabs(o) else os.path.join(ROOT, o)
    return os.path.join(base, *parts) if parts else base


def assets(*parts):
    """<out>/assets[/parts] — assets convertidos (png/webp/glb/ogg)."""
    return out_root("assets", *parts)


def data(*parts):
    """<out>/data[/parts] — dados de sala e tabelas (JSON)."""
    return out_root("data", *parts)


def extracted(*parts):
    """extracted/ntsc-u[/parts] — arquivos crus do disco PS1 (entrada, não muda com o destino)."""
    return os.path.join(ROOT, "extracted", "ntsc-u", *parts)


def cd_data(*parts):
    """extracted/ntsc-u/CD_DATA[/parts]."""
    return extracted("CD_DATA", *parts)


def name():
    """Nome do destino atual, para log ('godot' ou 'port')."""
    return os.environ.get(ENV_VAR, DEFAULT_OUT).strip() or DEFAULT_OUT


if __name__ == "__main__":
    print(f"{ENV_VAR}={name()}")
    print("out_root  =", out_root())
    print("assets    =", assets())
    print("data      =", data())
    print("extracted =", extracted())
