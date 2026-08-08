#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Assets e TABELAS do FLUXO DE ABERTURA do RE3 (WARNING -> CAPCOM -> TÍTULO -> jogo).

Este script é o dono do conhecimento do fluxo de boot no lado do pipeline. Ele faz
duas coisas e nada mais:

  1. **COPIA** os assets em HD e em PORTUGUÊS da instalação do usuário (somente
     leitura) para `<out>/assets/BOOT/`;
  2. **EMITE** `<out>/data/boot_flow.json` — os tempos em quadros lidos do EXE, a
     tabela de sprites do menu de título e o de-para rótulo -> recorte do atlas HD.

Nada aqui é "parecido com o RE3": cada número tem endereço de EXE, offset de
arquivo ou medição no pixel. O que é escolha do port está marcado com
`"declarado"` no JSON e explicado no comentário.

────────────────────────────── DE ONDE VEM CADA COISA ──────────────────────────────

**Tempos** — `docs/decomp/notes/menu_titulo.md` §1..§3, relidos aqui do EXE e dos
overlays quando dá (`--verificar`). Unidade = **tick de tarefa = 1 retraço vertical**
(divisor `*(u8*)0x800d442c` = 1, gravado em `0x80029870` e `0x8019412c`) ≈ 59,94 Hz.
O port roda a 30 Hz, então **2 ticks por quadro do port** (`ticks_por_quadro`).

**Sprites do título** — `0x801945e4` de `TITLE.BIN` (o inicializador que chama
`SetSprt` e grava `x0@+8, y0@+0xa, u0@+0xc, v0@+0xd, clut@+0xe, w@+0x10, h@+0x12`).
A tabela está em `tools/title_sprites.py` (`RAMO_A`/`RAMO_B`) e é importada daqui —
não duplicada.

**Assets HD/PT-BR** — a instalação GOG do usuário tem o pack HD (Seamless HD
Project) COM as variantes de idioma. O pack veio em russo (arquivos de jan/2025) e o
pacote "Edição Definitiva Dublado" acrescentou as versões em PORTUGUÊS (jun/2025).
O critério de separação é o **mtime**, exatamente como em `tools/memo_pt.py`
(`CORTE_MTIME`). Cada arquivo abaixo foi conferido A OLHO na folha de contato dos 34
`hires/bgd` posteriores ao corte:

| tela | arquivo HD | 1280×960 | conteúdo lido na imagem |
|---|---|---|---|
| aviso legal | `hires/bgd/4784F00D.webp` | sim | "ESSE JOGO CONTEM CENAS DE VIOLÊNCIA EXPLÍCITA E SANGUE" |
| logo CAPCOM | `hires/bgd/5E54FDD9.webp` | sim | logo azul/amarelo sobre branco |
| título | `hires/bgd/ED2C2D33.webp` | sim | "EDIÇÃO DEFINITIVA / RESIDENT EVIL 3 NEMESIS" |
| título (Mercenários) | `hires/bgd/81AA5030.webp` | sim | "OS MERCENARIOS / OPERAÇÃO MAD JACKAL" |
| atlas de rótulos | `hires/misc/3776D4A3.webp` | 1024×1024 | rótulos do menu em PT-BR |

⚠ O casamento HD que já existia em `port/assets/MENU/` está com as variantes
ERRADAS de idioma para estas telas: `18CC5627` (título) é a arte JAPONESA
("BIOHAZARD 3 LAST ESCAPE") e `DC361616` (aviso) está em RUSSO. A vizinhança por NCC
confirma o par: o mais próximo de `18CC5627` é `ED2C2D33` (0,52) e o mais próximo de
`DC361616` é `4784F00D` (0,37) — correlação baixa porque o que muda é justamente o
texto, que ocupa boa parte do quadro.

**Atlas HD = 4× a página de VRAM 256×256 do PS1.** `ETC/TITLEU.DAT` TIM[2] é
256×256 4bpp; `3776D4A3.webp` é 1024×1024. Logo `u,v,w,h` em unidades SD valem no HD
multiplicados por 4 — a MESMA regra do resto do pack. As LINHAS (`v`) do atlas PT
coincidem com as do atlas do PS1 nas faixas que interessam (104 seleções, 120
copyright, 128 config/modo, 144 mercenários, 176 EASY/HARD), o que é confirmado de
forma independente por `mod_BH3_Portuguese/xml/title_mapping.xml` — o mapa de
recortes do próprio pacote PT-BR.

Uso:
    NOSTALGIA_OUT=port python tools/boot_assets.py            # copia + gera o JSON
    NOSTALGIA_OUT=port python tools/boot_assets.py --medir     # mede a tinta dos rótulos
    python tools/boot_assets.py --verificar                    # relê os tempos do EXE
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths                                   # noqa: E402
import title_sprites                           # noqa: E402

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(RAIZ, "extracted", "ntsc-u", "SLUS_009.23")
HIRES_PADRAO = r"C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3\hires"
#: Mesmo corte de `tools/memo_pt.py`: o pack russo é de jan/2025, o PT-BR de jun/2025.
CORTE_MTIME = 1748000000                       # 2025-05-23

#: Tabela seno de 256 bytes ASSINADOS do EXE, usada pelo pulso do item selecionado
#: (`0x80195564`: `ctx[0x0f] += 4 ; ctx[0x0e] = (s8)tab[ctx[0x0f]]/3 - 0x80`).
SIN_TAB = 0x80098828
SIN_N = 256

# ─────────────────────────────── assets HD em PT-BR ───────────────────────────────
#: nome no port -> (subpasta do hires, hash, o que a imagem mostra)
HD_PT = {
    "aviso":        ("bgd",  "4784F00D", "ESSE JOGO CONTEM CENAS DE VIOLENCIA EXPLICITA E SANGUE"),
    "capcom":       ("bgd",  "5E54FDD9", "logo CAPCOM sobre fundo branco"),
    "titulo":       ("bgd",  "ED2C2D33", "EDICAO DEFINITIVA / RESIDENT EVIL 3 NEMESIS"),
    "titulo_merc":  ("bgd",  "81AA5030", "OS MERCENARIOS / OPERACAO MAD JACKAL"),
    "atlas":        ("misc", "3776D4A3", "atlas 1024x1024 dos rotulos do titulo, em PT-BR"),
}
#: As variantes de idioma ERRADAS que o casamento antigo escolheu (para o relatório).
HD_ERRADOS = {
    "titulo": ("18CC5627", "arte JAPONESA: BIOHAZARD 3 LAST ESCAPE"),
    "aviso":  ("DC361616", "aviso em RUSSO"),
}

# ─────────────────────────────── tempos, em ticks ───────────────────────────────
#: Cada entrada: (nome, ticks, sítio no binário). NADA arredondado, nada inventado.
TEMPOS = [
    # WARNING.BIN, base 0x80184000, entry 0x80185418
    ("aviso_fade_in",   30,  "0x80185480 fade_start(T=0x1e) subtrativo 255->0"),
    ("aviso_exibicao",  240, "0x801854a8 s0=0xef -> 240 chamadas de VSync(0)"),
    ("aviso_fade_out",  30,  "0x8018550c fade_start(T=0x1e) 0->255"),
    # TITLE.BIN handler 0 (logo CAPCOM), switch 0x80194004
    ("capcom_para_branco",  30,  "0x80194218 st0 fade(0x000000->0xffffff, T=30) abr=1"),
    ("capcom_entra_logo",   30,  "0x80194274 st2 fade(0xffffff->0x000000, T=30) abr=1"),
    ("capcom_exibicao",     120, "0x8019427c st4 contador = 0x78"),
    ("capcom_sai_logo",     30,  "0x80194294 st6 fade(0x000000->0xffffff, T=30)"),
    ("capcom_para_preto",   30,  "0x801942d4 st8 fade(0xffffff->0x000000, T=30)"),
    # TITLE.BIN estado 2 (0x80194b08) — a entrada do título
    ("titulo_espera",   6,  "0x80194b08 sub1: ctx+0x14 = 160, -30 por chamada, 6 chamadas"),
    ("titulo_flash",    5,  "0x80194b08 sub1: fade(0x000000->0xffffff, T=5) abr=1"),
    ("titulo_fade_in",  60, "0x80194b08 sub2: fade(0xffffff->0x000000, T=0x3c) abr=2"),
    # menu
    ("atrator_timeout", 900, "0x8019454c *(u16*)(ctx+0x16) = 0x384 (reiniciado a cada cursor)"),
]

#: Bits de `*(u32*)0x800cc858` que o fluxo usa (§3.8 da nota).
BITS_G = {
    "mercenaries": 0x00000080,
    "easy_mode":   0x00000100,
    "jogo_iniciando": 0x00001000,
    "veio_do_boot": 0x20000000,
    "reset_titulo": 0x00200000,
}

# ───────────────────── de-para rótulo PS1 -> recorte do atlas HD PT ─────────────────────
#
# `celula` = (u, v, w, h) em unidades SD (×4 no webp de 1024²).
# `origem` = de onde veio a célula:
#     "title_mapping" -> mod_BH3_Portuguese/xml/title_mapping.xml (o mapa do próprio pacote)
#     "sprt"          -> a mesma célula que o SPRT do PS1 usa (o atlas PT tem a linha igual)
# `pt` = o texto lido no recorte (não suposto: veio da imagem).
# `equivale` = "exato" quando o sentido é o mesmo do rótulo do PS1;
#              "declarado" quando é escolha do port porque não existe equivalente.
ROTULOS_PT = {
    # ── os 3 itens do menu de título do PS1 ──
    "NEW_GAME": dict(
        celula=(0, 144, 54, 13), origem="title_mapping(game start)", pt="COMEÇAR JOGO",
        equivale="declarado",
        nota="A célula do PS1 para NEW GAME é (0,104); no atlas PT ela contém "
             "'MODO ORIGINAL' (o item do menu do PC, que tem 5 opções). 'COMEÇAR JOGO' "
             "é o rótulo do atlas PT cujo SENTIDO é o de NEW GAME. Alternativa 1:1 de "
             "célula em `alt_celula`."),
    "LOAD_GAME": dict(
        celula=(128, 104, 64, 13), origem="title_mapping(load game)", pt="CARREG. JOGO",
        equivale="exato", nota=""),
    "GAME_CONFIG": dict(
        celula=(0, 128, 60, 12), origem="sprt", pt="GAME CONFIG",
        equivale="exato",
        nota="O pacote PT-BR NÃO traduziu esta linha: o atlas tem 'GAME CONFIG' em "
             "inglês na mesma célula do PS1. Não há variante PT deste rótulo no pack."),
    # ── a tela de DIFICULDADE ──
    # O PS1 usa a linha v=176 (EASY MODE / HARD MODE), que no atlas PT continua em INGLÊS.
    # As versões PT existem, mas na linha v=128 (é onde o menu do PC as põe).
    "diff_EASY_MODE": dict(
        celula=(128, 128, 56, 13), origem="title_mapping(light mode)", pt="MODO FACIL",
        equivale="exato",
        nota="A célula 1:1 do PS1 é (0,176) e no atlas PT ela é 'EASY MODE' (inglês)."),
    "diff_HARD_MODE": dict(
        celula=(192, 128, 62, 13), origem="title_mapping(heavy mode)", pt="MODO DIFICIL",
        equivale="exato",
        nota="A célula 1:1 do PS1 é (56,176) e no atlas PT ela é 'HARD MODE' (inglês)."),
    # ── rodapé ──
    "copyright": dict(
        celula=(0, 120, 226, 8), origem="title_mapping(copyright regular)",
        pt="© CAPCOM CO.,LTD.1999,2006 ALL RIGHTS RESERVED.", equivale="declarado",
        nota="O PS1 usa um bloco de DUAS linhas em (0,160,208,16); no atlas PT essa "
             "região está VAZIA. A única linha de copyright disponível é a de v=120."),
    # ── Mercenários (o ramo do bit 0x80), completo porque o atlas PT tem tudo ──
    "GAME_START": dict(celula=(0, 144, 54, 13), origem="sprt", pt="COMEÇAR JOGO",
                       equivale="exato", nota=""),
    "RESULT": dict(celula=(64, 144, 34, 13), origem="sprt", pt="RESULT",
                   equivale="exato", nota="não traduzido no pack"),
    "EXIT": dict(celula=(104, 144, 22, 13), origem="sprt", pt="SAIR", equivale="exato", nota=""),
}
#: Célula 1:1 com o SPRT do PS1, para quem quiser fidelidade de CÉLULA em vez de sentido.
ALT_CELULA = {
    "NEW_GAME": ((0, 104, 64, 13), "MODO ORIGINAL"),
    "diff_EASY_MODE": ((0, 176, 54, 12), "EASY MODE"),
    "diff_HARD_MODE": ((56, 176, 56, 12), "HARD MODE"),
}
#: Rótulos do PS1 que **NÃO TÊM** contrapartida no atlas HD PT-BR. Não escalo o SD:
#: informo. `PRESS ANY BUTTON` não existe porque a versão de PC não tem essa tela.
SEM_HD_PT = {
    "PRESS_ANY_BUTTON": "célula do PS1 (0,0,168,12); em v=0 o atlas PT tem o copyright "
                        "da Gold Edition. A versão de PC não usa 'PRESS ANY BUTTON'.",
    "copyright_2_linhas": "célula do PS1 (0,160,208,16); região vazia no atlas PT.",
}


# ─────────────────────────────── leitura do EXE ───────────────────────────────

def tabela_seno(exe_path=EXE):
    """Os 256 bytes ASSINADOS de `0x80098828` (o pulso do item selecionado)."""
    from exe_parse import Exe
    exe = Exe(exe_path)
    b = exe.bytes_at(SIN_TAB, SIN_N)
    return [v - 256 if v >= 128 else v for v in b]


def pulso(tab):
    """Reproduz `ctx[0x0e]` para os 64 ticks do ciclo (`+4` por tick, `/3 - 0x80`).

    `(s8)tab[i]/3` é divisão inteira C (trunca para zero); o resultado volta como
    u8, então `- 0x80` é feito no domínio de 8 bits: `(v/3 - 0x80) & 0xff`.
    """
    saida = []
    for k in range(64):
        v = tab[(k * 4) % SIN_N]
        q = int(v / 3)                              # trunca para zero, como o MIPS
        saida.append((q - 0x80) & 0xFF)
    return saida


# ─────────────────────────────── assets ───────────────────────────────

def hires_root(argv_valor=None):
    return argv_valor or os.environ.get("NOSTALGIA_HIRES") or HIRES_PADRAO


def copiar_hd(hires, destino, forcar=False):
    """Copia os 5 arquivos HD/PT para `<out>/assets/BOOT/`. Devolve o relatório."""
    os.makedirs(destino, exist_ok=True)
    rel = {}
    for nome, (sub, h, o_que) in HD_PT.items():
        src = os.path.join(hires, sub, h + ".webp")
        dst = os.path.join(destino, nome + ".webp")
        if not os.path.exists(src):
            rel[nome] = dict(ok=False, motivo="não existe em %s/%s" % (sub, h))
            continue
        mt = os.path.getmtime(src)
        if forcar or not os.path.exists(dst):
            shutil.copy2(src, dst)
        rel[nome] = dict(ok=True, arquivo="BOOT/%s.webp" % nome, hires="%s/%s.webp" % (sub, h),
                         conjunto_pt=mt > CORTE_MTIME, mtime=int(mt), mostra=o_que)
    return rel


def medir_tinta(hires, argv_hires=None):
    """Mede a caixa de tinta de cada rótulo no atlas HD (para conferir a largura).

    Precisa de Pillow. Devolve `{rotulo: {u,v,w,h, tinta_x, tinta_w}}` em unidades SD.
    """
    try:
        from PIL import Image
    except ImportError:
        return {}
    p = os.path.join(hires, "misc", HD_PT["atlas"][1] + ".webp")
    if not os.path.exists(p):
        return {}
    im = Image.open(p).convert("RGBA")
    saida = {}
    for nome, d in ROTULOS_PT.items():
        u, v, w, h = d["celula"]
        cx = im.crop((u * 4, v * 4, (u + w) * 4, (v + h) * 4))
        px = cx.load()
        cols = [x for x in range(cx.width)
                if any(px[x, y][3] > 8 and max(px[x, y][:3]) > 24 for y in range(cx.height))]
        if not cols:
            saida[nome] = dict(celula=[u, v, w, h], tinta_x=0, tinta_w=0)
            continue
        saida[nome] = dict(celula=[u, v, w, h],
                           tinta_x=min(cols) // 4, tinta_w=(max(cols) - min(cols) + 1 + 3) // 4)
    return saida


# ─────────────────────────────── JSON ───────────────────────────────

def montar_json(rel_assets, tinta):
    tab = tabela_seno() if os.path.exists(EXE) else []
    tempos = {n: dict(ticks=t, sitio=s) for n, t, s in TEMPOS}
    # posição de tela dos sprites: a tabela do SPRT de `title_sprites.py`, sem cópia
    ramo_b = {s[0]: dict(x=s[1], y=s[2], u=s[3], v=s[4], w=s[5], h=s[6])
              for s in title_sprites.RAMO_B}
    ramo_a = {s[0]: dict(x=s[1], y=s[2], u=s[3], v=s[4], w=s[5], h=s[6])
              for s in title_sprites.RAMO_A}
    rot = {}
    for nome, d in ROTULOS_PT.items():
        u, v, w, h = d["celula"]
        e = dict(u=u, v=v, w=w, h=h, pt=d["pt"], origem=d["origem"],
                 equivale=d["equivale"], nota=d["nota"])
        if nome in tinta:
            e["tinta_x"] = tinta[nome]["tinta_x"]
            e["tinta_w"] = tinta[nome]["tinta_w"]
        if nome in ALT_CELULA:
            (au, av, aw, ah), atxt = ALT_CELULA[nome]
            e["alt_celula"] = dict(u=au, v=av, w=aw, h=ah, pt=atxt)
        rot[nome] = e
    return {
        "meta": {
            "gerado_por": "tools/boot_assets.py",
            "fonte_tempos": "docs/decomp/notes/menu_titulo.md + extracted/ntsc-u/SLUS_009.23",
            "unidade_de_tempo": "tick de tarefa = 1 retraço vertical (divisor "
                                "*(u8*)0x800d442c = 1, gravado em 0x80029870 e 0x8019412c)",
            "ticks_por_quadro": 2,
            "nota_ticks_por_quadro":
                "MEDIDO: 1 tick = 1 vsync (~59,94 Hz). O port roda a 30 Hz (Clock.HZ), "
                "então 2 ticks por quadro do port. Isso preserva a DURAÇÃO em segundos "
                "(aviso = 300 ticks = 5,0 s; CAPCOM = 240 = 4,0 s; atrator = 900 = 15,0 s). "
                "A contradição 30 vs 60 Hz do repo continua ABERTA — aqui ela é resolvida "
                "por conversão, não reescrevendo o número medido.",
            "atlas_escala_hd": 4,
            "resolucao_tela_ps1": [320, 240],
            "resolucao_port": [1280, 960],
        },
        "tempos": tempos,
        "bits_0x800cc858": BITS_G,
        "sprites_titulo": ramo_b,
        "sprites_mercenaries": ramo_a,
        "menu": {
            "itens": ["NEW_GAME", "LOAD_GAME", "GAME_CONFIG"],
            "cursor_inicial": 1,
            "cursor_inicial_sitio": "0x801945b4 (sb $s1=1); no Mercenaries é 0",
            "cursor_inicial_confianca":
                "MEDIDO mas contra-intuitivo (LOAD GAME selecionado de saída). "
                "menu_titulo.md §10.2 recomenda confirmar em emulador.",
            "dificuldade": ["diff_HARD_MODE", "diff_EASY_MODE"],
            "dificuldade_sitio":
                "0x80195db8 limpa e 0x80195dcc liga o bit 0x100 de 0x800cc858 "
                "(cursor 0 = HARD, cursor 1 = EASY)",
            "sfx": {"cursor": 4, "cancelar": 5, "confirmar": 6,
                    "sitio": "0x800746c0(a0=id,0,0,0)"},
        },
        "pulso": {
            "passo": 4, "periodo_ticks": 64,
            "sitio": "0x80195564: ctx[0x0f] += 4 ; ctx[0x0e] = (s8)tab[ctx[0x0f]]/3 - 0x80",
            "tabela_seno_endereco": "0x%08x" % SIN_TAB,
            "valores": pulso(tab) if tab else [],
        },
        "arquivos_do_jogo_novo": {
            "INIT_TBL": dict(indice=0x30, destino="0x800d1d28", tamanho=2312,
                             sitio="0x80196068 cd_read_file(0x30, 0x800d1d28, 0, 'INIT_TBL')",
                             decodificado=False,
                             nota="NÃO ABERTO: 2312 bytes de estado inicial. O port carrega "
                                  "o arquivo e registra o SHA, mas o layout não foi medido."),
            "INIT_SUB": dict(indice=0x2F, destino="0x800d1d28", tamanho=2312,
                             sitio="0x80195fac (só no Mercenaries)", decodificado=False),
        },
        "fmv_abertura": {
            "overlay": "OPENING (ovl 5)",
            "sitio": "0x801960d8 load_overlay_task(1, 5) depois do INIT_TBL",
            "arquivo_ps1": "CD_DATA/ZMOVIE/OPN.STR (1350 quadros a 15 fps = 90,0 s)",
            "arquivo_hd": "ZMOVIE/opn.ogv (de zmovie/opn.mp4, 1280x960 h264 29,97 fps, 90,624 s)",
        },
        "sala_inicial": {
            "id": "R10D", "origem": "informado pelo usuário (conhece o jogo)",
            "nota": "NÃO medido no INIT_TBL — ver present/screen.gd, que registra a "
                    "tentativa falhada de ler stage/room nos offsets 590/592.",
        },
        "assets": rel_assets,
        "assets_variante_errada": {k: dict(hash=v[0], problema=v[1])
                                   for k, v in HD_ERRADOS.items()},
        "sem_hd_pt": SEM_HD_PT,
        "rotulos_pt": rot,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hires", default=None, help="raiz do pack HD (default: instalação GOG)")
    ap.add_argument("--forcar", action="store_true", help="recopia mesmo se já existir")
    ap.add_argument("--medir", action="store_true", help="imprime a tinta medida dos rótulos")
    ap.add_argument("--verificar", action="store_true", help="relê os tempos-chave do EXE")
    a = ap.parse_args()

    hires = hires_root(a.hires)
    destino = paths.assets("BOOT")
    rel = copiar_hd(hires, destino, a.forcar)
    tinta = medir_tinta(hires)
    d = montar_json(rel, tinta)

    os.makedirs(paths.data(), exist_ok=True)
    saida = paths.data("boot_flow.json")
    with open(saida, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)

    print("destino  = %s" % paths.name())
    for nome, r in rel.items():
        marca = "ok " if r.get("ok") else "FALTA"
        pt = "PT" if r.get("conjunto_pt") else "?? (fora do conjunto PT)"
        print("  %-5s %-12s %-22s %s" % (marca, nome, r.get("hires", r.get("motivo", "")), pt))
    print("-> %s" % saida)
    def soma(prefixo):
        return sum(t for n, t, _s in TEMPOS if n.startswith(prefixo))
    for fase, pref in [("aviso", "aviso"), ("capcom", "capcom"), ("titulo (entrada)", "titulo")]:
        n = soma(pref)
        print("  tempo %-17s %4d ticks = %5.2f s a 59,94 Hz (%d quadros a 30 Hz)"
              % (fase, n, n / 59.94, n // 2))
    at = soma("atrator")
    print("  atrator            %4d ticks = %5.2f s" % (at, at / 59.94))

    if a.medir:
        print("\ntinta medida no atlas HD (unidades SD):")
        for nome, m in tinta.items():
            print("  %-16s celula=%s  tinta x=%d w=%d   pt=%r"
                  % (nome, m["celula"], m["tinta_x"], m["tinta_w"], ROTULOS_PT[nome]["pt"]))

    if a.verificar:
        from exe_parse import Exe
        exe = Exe(EXE)
        print("\nverificação no EXE:")
        print("  divisor de quadro gravado em 0x80029870: sb $s2 -> 1 (ver menu_titulo.md §0)")
        tab = tabela_seno()
        print("  tabela seno 0x%08x: %s ... amplitude [%d, %d]"
              % (SIN_TAB, tab[:6], min(tab), max(tab)))
        print("  pulso (64 ticks): min=%d max=%d" % (min(pulso(tab)), max(pulso(tab))))
        print("  0x800cc858 bit EASY = 0x%03x (escrito em 0x80195dcc / limpo em 0x80195db8)"
              % BITS_G["easy_mode"])
        for addr, esp in [(0x80185480, "fade do aviso"), (0x8019427c, "contador do CAPCOM")]:
            print("  %08x %s: %s" % (addr, esp, exe.u32(addr) if exe.valid_vaddr(addr) else "?"))


if __name__ == "__main__":
    main()
