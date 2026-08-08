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
import math
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
#: O mapa de recortes do PRÓPRIO pacote PT-BR (mora ao lado do `hires`, na raiz do jogo).
TITLE_MAPPING_REL = os.path.join("mod_BH3_Portuguese", "xml", "title_mapping.xml")
#: Mesmo corte de `tools/memo_pt.py`: o pack russo é de jan/2025, o PT-BR de jun/2025.
CORTE_MTIME = 1748000000                       # 2025-05-23

#: Tabela seno de 256 bytes ASSINADOS do EXE, usada pelo pulso do item selecionado
#: (`0x80195564`: `ctx[0x0f] += 4 ; ctx[0x0e] = (s8)tab[ctx[0x0f]]/3 - 0x80`).
SIN_TAB = 0x80098828
SIN_N = 256

#: Tick de tarefa = 1 retraço vertical NTSC (o divisor `*(u8*)0x800d442c` vale 1).
#: É a unidade de `TEMPOS`; serve para converter a duração de um som em ticks.
TAXA_TICK = 60000.0 / 1001.0

# ─────────────────────────────── assets HD em PT-BR ───────────────────────────────
#: nome no port -> (subpasta do hires, hash, o que a imagem mostra)
HD_PT = {
    "aviso":        ("bgd",  "4784F00D", "ESSE JOGO CONTEM CENAS DE VIOLENCIA EXPLICITA E SANGUE"),
    "capcom":       ("bgd",  "5E54FDD9", "logo CAPCOM sobre fundo branco"),
    "titulo":       ("bgd",  "ED2C2D33", "EDICAO DEFINITIVA / RESIDENT EVIL 3 NEMESIS"),
    "titulo_merc":  ("bgd",  "81AA5030", "OS MERCENARIOS / OPERACAO MAD JACKAL"),
    "atlas":        ("misc", "3776D4A3", "atlas 1024x1024 dos rotulos do titulo, em PT-BR"),
    # As DUAS imagens de tela cheia do PROLOGO (a "vinheta" que faltava antes do FMV).
    # Sao `ETC/OPENING1.DAT` TIM[0] e TIM[1] (320x240, 16 bpp), e o `op 6` do script do
    # prologo instala uma delas como fundo (arg 0 -> TIM[0], arg 1 -> TIM[1]). Os pares HD
    # sao os de `boot_ptbr_hd.md` §8.6 (NCC 0,9449 e 0,9998) e foram CONFERIDOS aqui
    # decodificando os dois TIM e comparando a olho com os webp.
    "prologo0":     ("bgd",  "B6306D2E", "logo da Umbrella sobre uma rua de Raccoon City"),
    "prologo1":     ("bgd",  "CB8189B6", "Jill carregando a arma no apartamento"),
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
    # TITLE.BIN sub 1 (0x80195c68) — a TRANSICAO de "escolhi a dificuldade" ate o filme.
    # Depois de gravar o bit 0x100 (0x80195db8/0x80195dcc) o codigo sacode o controle, pede
    # a VINHETA (0x80195e70, ver VINHETA_TITULO) e roda TRES fades em fila, esperando cada
    # um acabar (0x8002a6bc) antes do proximo. Assinatura de 0x8002a35c calibrada em dois
    # sitios de abr conhecido: (slot, ?, ?, ABR, c0@sp+0x10, c1@sp+0x14, T@sp+0x18) —
    # 0x80185480 tem a3=2 e o doc diz abr=2; 0x80194248 tem a3=1 e o doc diz abr=1.
    ("inicio_clarao_in",   4,   "0x80195e9c fade(0x000000->0xffffff, T=4) abr=1"),
    ("inicio_clarao_out",  12,  "0x80195eec fade(0xffffff->0x000000, T=0xc) abr=1"),
    ("inicio_para_preto",  180, "0x80195f3c fade(0x000000->0xffffff, T=0xb4) abr=2"),
]

#: Bits de `*(u32*)0x800cc858` que o fluxo usa (§3.8 da nota).
BITS_G = {
    "mercenaries": 0x00000080,
    "easy_mode":   0x00000100,
    "jogo_iniciando": 0x00001000,
    "veio_do_boot": 0x20000000,
    "reset_titulo": 0x00200000,
    #: postos por `filme_prepara` em 0x80032478 (`lui a1,1; ori a1,0x8000` -> 0x18000);
    #: 0x10000 e' o que o TITLE espera limpar para saber que o filme acabou
    #: (0x801943ac, 0x801960f0, 0x801964cc, 0x80196ee0).
    "filme_tocando": 0x00010000,
    "filme_bit_8000": 0x00008000,
}

# ─────────────────────────── FMV: a tabela de filmes do EXE ───────────────────────────
#
# ACHADO DESTA RODADA. O reprodutor de FMV do RE3 e' uma TAREFA do EXE, nao um overlay:
#
#   `0x800321c4  filme_prepara(a0 = indice do filme)`   <- unico ponto de entrada
#       rec = 0x8009ca64 + a0*0x18            (0x800321f0: base 0x800a0000-0x359c)
#       0x800cc858 |= 0x18000                 (0x80032478/0x80032484)
#   `0x800324a0  filme_tick()`                chamado pelo laco de quadro em 0x80029370
#       despacha `0x8009cbb4[estado]` = {0x800325a4, 0x800327a4, 0x80032ad4}
#   `0x80032644  0x80074658(1)`               liga a entrada de CD/XA no SPU a 0x7fff
#   `0x80032638  0x8003331c(vol)`             volume do filme (campo +0x14 / 127)
#
# A tabela comeca EXATAMENTE onde acaba a de overlays (0x8009c944 + 24*12 = 0x8009ca64)
# e tem **14 registros de 0x18 bytes**. Campos medidos:
#
#   +0x00 u32  indice de arquivo do `.STR` (casa com a tabela de arquivos 0x800946a4)
#   +0x04 u16  QUADROS a tocar  -> = (quadros do jPSXdec - 5) em 13/13 videos
#   +0x06 u16  0x00ff em 14/14                                   (NAO DECODIFICADO)
#   +0x08 u16  flags; vai para ctx+0x24 (0x8003247c)              (NAO DECODIFICADO)
#   +0x0a u16  0x0140 = 320 = LARGURA          (0x8003239c)
#   +0x0c u16  x = 0                           (0x800323b8)
#   +0x0e u16  y = 0x28 = 40                   (0x800323c4)  -> 40+160+40 = 240 ✔
#   +0x10 u16  acrescimo de endereco do buffer (0x800322e8)       (NAO DECODIFICADO)
#   +0x12 u16  flags: bit 0x200 -> buffer 0x80100000, senao 0x80194000 (0x80032204);
#              bit 0x008 -> caminho extra de SPU (0x8003222c)
#   +0x14 u16  VOLUME 0..127 (0x80032428: vol * *(s16*)0x800e0dda / 127 -> 0x8003331c)
FILMES_TABELA = 0x8009CA64
FILMES_N = 14
FILMES_STRIDE = 0x18

#: indice de arquivo -> nome do `.STR` no disco. Achado casando a tabela de arquivos
#: `0x800946a4` com os LBA do indice do jPSXdec (`tools/re3.idx`): os 13 videos sao os
#: unicos registros com flags = 0xff.
FILMES_STR = {
    0x53A: "ENDA", 0x53B: "ENDB", 0x53C: "INS01", 0x53D: "INS02", 0x53E: "INS03",
    0x53F: "INS04", 0x540: "INS05", 0x541: "INS06", 0x542: "INS07", 0x543: "INS08",
    0x544: "INS09", 0x545: "OPN", 0x546: "ROOPNE",
}
#: `.STR` do PS1 -> nome do `.mp4` no pacote HD/PT-BR (`zmovie/`). `ROOPNE` -> `roop`
#: (15,7 s de 236 quadros no PS1 contra 15,49 s no mp4). `snl.mp4` (3,31 s) **nao existe
#: no disco do PS1** — o indice do jPSXdec lista 13 `.STR`, sem SNL. E' extra do PC.
FILMES_MP4 = {
    "OPN": "opn", "ROOPNE": "roop", "ENDA": "enda", "ENDB": "endb",
    "INS01": "ins01", "INS02": "ins02", "INS03": "ins03", "INS04": "ins04",
    "INS05": "ins05", "INS06": "ins06", "INS07": "ins07", "INS08": "ins08",
    "INS09": "ins09",
}
#: Quadros que o jPSXdec conta em cada `.STR` (docs/formatos/audio_video.md §4). O campo
#: +0x04 do registro e' SEMPRE este numero MENOS 5 — e' o que prova o campo.
FILMES_QUADROS_JPSXDEC = {
    "OPN": 1350, "ROOPNE": 236, "ENDA": 813, "ENDB": 840, "INS01": 392, "INS02": 220,
    "INS03": 299, "INS04": 442, "INS05": 188, "INS06": 461, "INS07": 347, "INS08": 278,
    "INS09": 242,
}
#: Os 4 sitios que chamam `filme_prepara` de dentro do `TITLE.BIN`, com o `a0` constante.
FILMES_CHAMADAS_TITLE = [
    (0x801943A4, 0x0C, "fim do handler 0: DEPOIS do logo CAPCOM (ou do reset/pulo) e "
                       "ANTES do estado 1 (carga do titulo). So se o bit 0x80 "
                       "(Mercenaries) estiver LIMPO (0x8019439c). Em seguida "
                       "0x801943ac espera o bit 0x10000 limpar = espera o filme acabar."),
    (0x801960E8, 0x00, "NEW GAME: depois da dificuldade + INIT_TBL + "
                       "load_overlay_task(1, ovl 5 = OPENING) em 0x801960d8."),
    (0x801964BC, 0x0D, "sub 6 (0x8019644c), depois de um fade-out de 12 ticks."),
    (0x80196ED8, 0x00, "sub 11 (0x80196800), depois de load_overlay_task(1, OPENING) "
                       "em 0x80196ec8."),
]
#: Opcode SCD que toca FMV, achado nesta rodada.
FILME_OPCODE_SCD = dict(
    opcode=0x7A, handler="0x80055520", bytes=2,
    prova="0x80055538 lbu a0, 1(PC) ; 0x8005553c jal 0x800321c4 ; PC += 2. O handler e' a "
          "entrada 0x7a da jump-table 0x8009e0f8.",
    salas={"INS01": "STAGE1/R110 func 3", "INS02": "STAGE2/R217 func 6 e 14",
           "INS03": "STAGE1/R11C func 2",
           "INS04": "STAGE2/R215 funcs 18, 20, 21 e 23", "INS05": "STAGE2/R215 func 52",
           "INS06": "STAGE3/R30D func 8", "INS07": "STAGE4/R417 func 7",
           "INS08": "STAGE4/R415 func 9", "INS09": "STAGE5/R508 func 4"},
    nota_r10d="R10D **nao tem nenhum opcode 0x7a** (varredura das 49 funcoes). A "
              "cinematica de abertura da sala inicial NAO e' FMV.")

# ───────────────────── som da tela de TITULO (medido no TITLE.BIN) ─────────────────────
#
# `0x801944c0  0x8007809c(a0 = 0, a1 = (0x800cc858 & 0x80) ? 0xb : 1, ...)`
#
# `0x8007809c(cat, banco)` carrega o par `.VH`/`.VB` do banco: le a tabela de 4 pares de
# u16 em `0x800110b0` (`04 01 03 01 da 00 d9 00`) com passo 4 e faz
# `file_index = tab[cat] + banco*2`. Conferido contra a tabela de arquivos:
#   cat 0 -> 0x104 = SOUND/C_00.VH  => banco 1 -> 0x106 = SOUND/C_01.VH  ✔
#   cat 1 -> 0x0da = SOUND/A_01.VH (base A_00 inexistente; banco 1 = A_01)
# Logo a tela de TITULO usa o banco **C_01** no cat 0 (nao C_00), e o Mercenaries usa C_0B.
SOM_TITULO = dict(
    banco_se="C_01", cat=0, banco_id=1,
    banco_se_mercenaries="C_0B", banco_id_mercenaries=0x0B,
    sitio_banco="0x801944c0 0x8007809c(a0=0, a1=1) ; tabela de bases 0x800110b0",
    nota_banco="Os 5 WAV de UI de C_01 sao BYTE-IDENTICOS aos de C_00 (conferido nos "
               "arquivos extraidos), entao o som AUDIVEL e' o mesmo — mas o banco que o "
               "binario carrega e' o C_01.",
    bgm="main38", bgm_indice=0x121,
    sitio_bgm="0x801944dc cd_read_file(0x121 = SOUND/MAIN38.BGM, 0x801f7e00, 1, "
              "'OPTION BGM') + 0x800782f4(0, 0x38, ...) ; MAIN38.VB = 0x122",
    nota_bgm="O rotulo de depuracao diz 'OPTION BGM' e eu NAO consigo conferir de ouvido. "
             "O que esta provado e' o INDICE DE ARQUIVO (0x121 = SOUND/MAIN38.BGM).",
    bgm_comeca_em="estado 1 (0x80194444), isto e' DEPOIS do filme de atracao do "
                  "handler 0 — por isso o port pede a BGM so no titulo_espera.",
    sfx={"cursor": 4, "cancelar": 5, "confirmar": 6, "invalido": 7, "abrir": 9},
)

# ─────────── a VINHETA: o que toca entre a DIFICULDADE e o filme (MEDIDO) ───────────
#
# O dono do repo: "no menu, depois de selecionar o modo, deveria tocar o som do
# 'Resident Evil' e depois ir para o video". Nao e' BGM nem XA: e' um **SE**.
#
# SITIO, dentro do sub 1 do TITLE.BIN (`0x80195c68` = a tela de dificuldade), logo depois
# de `0x80195db8`/`0x80195dcc` gravarem/limparem o bit 0x100 (EASY) de `0x800cc858`:
#
#     0x80195e2c  bnez  (0x800cc858 & 0x10000000)  -> pula o bloco inteiro
#     0x80195e38  jal 0x80038678(7, 0)             vibracao do motor pequeno
#     0x80195e48  jal 0x80038704(9, 0xff, 0)       vibracao do motor grande
#     0x80195e5c  jal 0x8003879c(4, 0xff, 60, 10)  rampa de vibracao
#     0x80195e70  jal 0x800746c0(a0 = 0, 0, 0, 0)  <<< SE_pede: cat 0, id 0
#
# e SO DEPOIS vem a transicao (os 3 fades de TEMPOS), `0x80196068` (INIT_TBL),
# `0x801960d8` (overlay 5 = OPENING, o prologo) e `0x801960e8` (`filme_prepara(0)` = o
# `opn`). Ou seja: dificuldade -> VINHETA -> prologo -> filme, nessa ordem.
#
# `a0 = 0` e' `move $a0, $zero` (0x80195e64), o que o `--calls` do overlay_parse nao
# recupera por back-walk de imediato — foi lido na desmontagem.
#
# O MESMO trio de vibracao + `SE_pede(0)` aparece em exatamente outros dois sitios do
# TITLE, e em nenhum outro: `0x80195a08` (sub 2, que carrega o MEM_CARD) e `0x80196c34`
# (sub 11). E' o "beat de apresentacao" do overlay, nao um blip de UI.
#
# `cat 0` na tela de titulo e' o banco **C_01** (`0x801944c0`, ver SOM_TITULO). No C_01 o
# id 0 e' de longe o maior ativo do banco, e e' ESTEREO:
#
#   • descritor `0x03e005e0` -> **(byte0 >> 6) + 1 = 4 VOZES**. MEDIDO em `0x80074c84`
#     (`lbu v1,0(s6) ; srl v1,6 ; addiu v1,1` e' o limite do laco que comeca em
#     `0x80074a74`), e cada volta usa o tom `(byte1 >> 4) + i` (`0x80074ab4`:
#     `lbu v0,1(s6) ; srl v0,4 ; addu v0,s2,v0`). Isso RESOLVE o "byte0 bits 6-7 NAO
#     PROVADO" de exe_audio.md §4.1: e' o numero de vozes menos 1.
#   • os tons 0..3 do C_01 tem pan **0 / 127 / 0 / 127** e apontam os VAGs **7 e 8** —
#     sao os UNICOS tons do banco fora do centro (todos os outros tem pan = 64). Par
#     estereo, tocado em dobro.
#   • os VAGs 7 e 8 ocupam **79,0 % do `C_01.VB`** (2 x 81 264 de 205 616 B).
#   • 30 392 Hz, 142 212 amostras => **4,679 s**, contra 0,08..0,86 s dos blips de UI.
#   • o `C_0B` (banco de titulo do Mercenaries) tem o MESMO descritor no id 0 apontando
#     uma amostra DIFERENTE (44 100 Hz, 4,21 s, 83 % do banco) — jingle por modo. Os ids
#     4/5/6/7 (os blips) sao byte-identicos em 13 dos 14 bancos `C_`; este nao e'.
#
# O que eu **NAO** posso afirmar: que a voz diga "Resident Evil". Nao ha etiqueta no dado
# e eu nao ouco. Confira de ouvido:
#     tools/ffmpeg/.../ffplay.exe port/assets/SOUND/SFX/C_01/C_01_05.wav
VINHETA_TITULO = dict(
    cat=0, id_se=0, banco="C_01", banco_mercenaries="C_0B",
    sitio="0x80195e70 0x800746c0(a0 = 0) no sub 1 (0x80195c68), depois do bit 0x100",
    sitio_a0="0x80195e64 move $a0, $zero (imediato nao recuperavel por back-walk)",
    sitios_irmaos=["0x80195a08 (sub 2, MEM_CARD)", "0x80196c34 (sub 11)"],
    vibracao=["0x80038678(7, 0)", "0x80038704(9, 0xff, 0)", "0x8003879c(4, 0xff, 60, 10)"],
    porta="0x80195e2c: o bloco inteiro e' pulado quando 0x800cc858 & 0x10000000",
    sitio_vozes="0x80074c84 (byte0 >> 6) + 1 ; tom = (byte1 >> 4) + i em 0x80074ab4",
    ordem="dificuldade -> VINHETA (0x80195e70) -> 3 fades -> INIT_TBL (0x80196068) -> "
          "OPENING/prologo (0x801960d8) -> filme opn (0x801960e8)",
    nao_esperado="MEDIDO: a transicao dura 4+12+180 = 196 ticks = 3,27 s e o som tem "
                 "4,679 s — o original NAO espera o SE acabar; o rabo dele soa por cima "
                 "do inicio do prologo (as vozes do SPU sobrevivem ao load do overlay).",
    idioma="NAO VERIFICADO POR AUDICAO: que a voz diga 'Resident Evil' e' o relato do "
           "dono do repo, nao medicao. O que esta medido e' o sitio, o banco, o id, as "
           "4 vozes, o par estereo e a duracao.",
)

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
        celula=(28, 128, 34, 13), origem="title_mapping(configuration)", pt="CONFIG",
        equivale="declarado",
        nota="O item do PS1 é 'GAME CONFIG' (célula 0,128,60,12). No atlas PT essa célula "
             "MISTURA DUAS FONTES: o pacote redesenhou só 'CONFIG' (fonte nova) e deixou "
             "'GAME' no desenho original — renderizado junto fica visivelmente quebrado "
             "(conferido em port/_boot_menu.png). Uso só 'CONFIG', que é exatamente a "
             "célula que title_mapping.xml declara para `configuration`. Não há variante "
             "PT-BR de 'GAME CONFIG' inteiro no pack."),
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
    "GAME_CONFIG": ((0, 128, 60, 12), "GAME CONFIG (duas fontes misturadas no pack)"),
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


def medir_vinheta(banco=None, id_se=None):
    """Mede o SE da VINHETA no `.VH` do disco do usuario (ver VINHETA_TITULO).

    Le o descritor do id no offset 0 do header, resolve as `(byte0 >> 6) + 1` vozes com os
    tons `(byte1 >> 4) + i`, e devolve pan/vag/taxa/duracao de cada uma. NENHUM numero
    digitado a mao: tudo sai do arquivo. Devolve `None` se o banco nao estiver extraido.
    """
    banco = banco or VINHETA_TITULO["banco"]
    id_se = VINHETA_TITULO["id_se"] if id_se is None else id_se
    vh_p = paths.cd_data("SOUND", banco + ".VH")
    vb_p = paths.cd_data("SOUND", banco + ".VB")
    if not (os.path.exists(vh_p) and os.path.exists(vb_p)):
        return None
    import vab                                   # noqa: E402  (opcional: so quando ha disco)
    with open(vh_p, "rb") as f:
        vh = f.read()
    vb_bytes = os.path.getsize(vb_p)
    b = vab.parse_bank(vh, vb_bytes)
    desc = struct.unpack_from("<I", vh, id_se * 4)[0]
    if desc == 0xFFFFFFFF:
        return None
    b0, b1 = desc & 0xFF, (desc >> 8) & 0xFF
    vozes = (b0 >> 6) + 1                        # 0x80074c84
    tom0 = b1 >> 4                               # 0x80074ab4 (+ i por volta do laco)
    saida, usados = [], {}
    for i in range(vozes):
        if tom0 + i >= len(b["tones"]):
            break
        t = b["tones"][tom0 + i]
        s = b["samples"][t["vag"] - 1]
        amostras = s["blocks"] * 28              # PS-ADPCM: 16 B -> 28 amostras
        usados[t["vag"]] = s["end"] - s["start"]
        saida.append(dict(
            tom=tom0 + i, pan=t["pan"], vol=t["vol"], vag=t["vag"],
            vag_bytes=s["end"] - s["start"], amostras=amostras, taxa_hz=s["rate"],
            duracao_s=round(amostras / float(s["rate"]), 4),
            # `re3_sfx.py` descarta o VAG#1 (bloco mudo do SPU): vag k -> <banco>_{k-2}.wav
            wav="%s/%s_%02d.wav" % (banco, banco, t["vag"] - 2),
            lado=("esquerda" if t["pan"] < 0x40 else
                  "direita" if t["pan"] > 0x40 else "centro"),
        ))
    if not saida:
        return None
    dur = max(v["duracao_s"] for v in saida)
    return dict(
        banco=banco, id_se=id_se, descritor="0x%08x" % desc, vozes=vozes, tom_base=tom0,
        vozes_detalhe=saida,
        duracao_s=dur,
        ticks=int(math.ceil(dur * TAXA_TICK)),
        vb_bytes=vb_bytes,
        fracao_do_banco=round(sum(usados.values()) / float(vb_bytes), 4),
        estereo=len({v["lado"] for v in saida}) > 1,
        wavs=[v["wav"] for v in saida],
        wavs_distintos=sorted({v["wav"] for v in saida}),
    )


def filmes(exe_path=EXE):
    """Os 14 registros de `0x8009ca64`, decodificados. Le do EXE, nao de tabela copiada."""
    from exe_parse import Exe
    if not os.path.exists(exe_path):
        return []
    exe = Exe(exe_path)
    saida = []
    for i in range(FILMES_N):
        a = FILMES_TABELA + i * FILMES_STRIDE
        b = exe.bytes_at(a, FILMES_STRIDE)
        h = list(struct.unpack_from("<12H", b, 0))
        idx = h[0] | (h[1] << 16)
        nome = FILMES_STR.get(idx, "?")
        jp = FILMES_QUADROS_JPSXDEC.get(nome)
        saida.append(dict(
            indice=i, endereco="0x%08x" % a, arquivo_indice=idx, str=nome,
            mp4=FILMES_MP4.get(nome, ""),
            quadros=h[2], quadros_jpsxdec=jp,
            quadros_menos_jpsxdec=(h[2] - jp) if jp is not None else None,
            campo_06=h[3], flags_08=h[4],
            largura=h[5], x=h[6], y=h[7],
            campo_10=h[8], flags_12=h[9], volume=h[10],
            buffer="0x80100000" if (h[9] & 0x200) else "0x80194000",
            segundos_15fps=round(h[2] / 15.0, 3),
        ))
    return saida


# ───────────────────────── PROLOGO: o script dentro de OPENING1.DAT ─────────────────────────
#
# ACHADO DESTA RODADA, e' a "vinheta antes do proximo video" que faltava no port.
#
# `OPENING.BIN` (overlay 5, base **0x801c2000**) NAO e' tocador de video: e' um INTERPRETADOR
# de 13 opcodes que roda um script de 80 bytes. O script mora no FIM de `ETC/OPENING1.DAT`
# (offset 0x4b02a de 0x4b07a), e o ponteiro dele e' armado em `0x801c21a8`:
#
#     0x801c21a0  lui v1,0x8014 ; ori v1,0xb02a       -> 0x8014b02a
#     0x801c21b8  sw  v1, 0x244(ctx = 0x801c3048)     -> PC do script
#     0x801c2084  v0 = *(u8*)*(ctx+0x244) ; v0 <<= 2 ; jalr *(0x801c2f70 + v0)
#
# `OPENING1.DAT` e' lido em `0x80100000` (`0x801c2284`: `cd_read_file(0x3e, 0x80100000, …)`),
# logo `0x8014b02a` = offset **0x4b02a** do arquivo. Confere: o arquivo tem 0x4b07a bytes.
#
# A tabela de handlers `0x801c2f70` tem **13 entradas** (0x801c2b38 … 0x801c2ee0), e os
# opcodes que o script usa vao de 0x00 a 0x0c — nenhum fora da tabela. Cada handler devolve
# 1 (segue no mesmo tick), 0 (sai do laco deste tick) ou 2, e avanca o PC ele mesmo:
OPS_PROLOGO = {
    0x00: dict(n=1, nome="nop", sitio="0x801c2b38", efeito="PC += 1 ; devolve 1"),
    0x01: dict(n=2, nome="fim", sitio="0x801c2b50", efeito="PC += 1 ; devolve 0 (encerra)"),
    0x02: dict(n=1, nome="devolve_2", sitio="0x801c2b68", efeito="PC += 1 ; devolve 2"),
    0x03: dict(n=1, nome="timer", sitio="0x801c2b80",
               efeito="ctx+0x248 = u16 em PC+2, DOBRADO se o divisor de quadro "
                      "*(u8*)0x800d442c == 1 ; PC += 1"),
    0x04: dict(n=3, nome="espera", sitio="0x801c2bd4",
               efeito="enquanto ctx+0x248 != 0: decrementa e devolve 0 ; no fim PC += 3"),
    0x05: dict(n=1, nome="espera_som", sitio="0x801c2c04",
               efeito="devolve 0 enquanto *(u32*)0x800d1f2c & 0x20 ou "
                      "!(*(u8*)0x800dbb58 & 0x80) ; depois PC += 1"),
    0x06: dict(n=2, nome="imagem", sitio="0x801c2c4c",
               efeito="copia 0x25814 B (uma imagem 320x240 16bpp) de "
                      "*(0x801c2f0c + arg*4) para 0x8019c000 e poe modo de tela 2"),
    0x07: dict(n=2, nome="modo_desenho", sitio="0x801c2cbc",
               efeito="modo de tela 1 (limpa) ; ctx+0 = ctx+1 = 0 ; ctx+4 = arg "
                      "(escolhe a rotina por quadro: 0x801c2488 / 0x801c2618 / 0x801c2788)"),
    0x08: dict(n=2, nome="fade_in", sitio="0x801c2d0c",
               efeito="fade(slot 0, abr=2, 0xffffff -> 0x000000, T = arg [x2 se divisor 1])"),
    0x09: dict(n=2, nome="fade_out", sitio="0x801c2d8c",
               efeito="fade(slot 0, abr=2, 0x000000 -> 0xffffff, T = arg [x2 se divisor 1])"),
    0x0A: dict(n=2, nome="pede_recurso", sitio="0x801c2e0c",
               efeito="0x80011df4(3, arg + 0x13) e liga o bit 0x20 de 0x800d1f2c "
                      "(o mesmo que o op 5 espera)"),
    0x0B: dict(n=2, nome="xa", sitio="0x801c2e70",
               efeito="0x8002fd30(0x00b90022, 0x3000, 0x801c2f3c + *(u16*)(0x801c2f68 + "
                      "arg*2), 0) = comeca o trecho `arg` do stream de XA (a narracao)"),
    0x0C: dict(n=2, nome="divisor", sitio="0x801c2ee0",
               efeito="*(u8*)0x800d442c = arg (divisor de quadro: 1 = 59,94 Hz, 2 = 29,97)"),
}
#: offset do script dentro de `ETC/OPENING1.DAT` (= 0x8014b02a - 0x80100000)
PROLOGO_OFF = 0x4B02A


def decodificar_prologo(dados):
    """Decodifica os 80 bytes do script do prologo em (opcodes, linha do tempo).

    A unidade dos numeros do script e' **quadro de 29,97 Hz**: o `op 3` DOBRA o valor quando
    o divisor de quadro vale 1 (`0x801c2b9c`: `lh` + `sll 1`), e o `op 0x0c` troca o divisor
    entre 1 e 2 no meio do prologo — as duas coisas juntas dizem que o autor escreveu tudo
    em quadros de 30 Hz e o motor converte para ticks de vsync.
    """
    ops, t, divisor, timer = [], 0, 1, 0
    i = PROLOGO_OFF
    imagem, modo = -1, 0
    while i < len(dados):
        op = dados[i]
        d = OPS_PROLOGO.get(op)
        if d is None:
            ops.append(dict(off=i, op=op, nome="DESCONHECIDO"))
            break
        arg = dados[i + 1] if i + 1 < len(dados) else 0
        e = dict(off=i, op=op, nome=d["nome"], arg=arg, quadro=t, divisor=divisor)
        if op == 0x03:
            # o `op 3` le o u16 em PC+2 e avanca so 1 byte: quem consome `04 xx yy` e' o `op 4`
            timer = struct.unpack_from("<H", dados, i + 2)[0]
            e["arg"] = timer
            e["quadros"] = timer
        elif op == 0x04:
            t += timer                              # a espera consome o timer armado
            e["arg"] = timer
            e["espera_quadros"] = timer
            timer = 0
        elif op == 0x08 or op == 0x09:
            e["quadros"] = arg
        elif op == 0x06:
            imagem = arg
            e["imagem"] = arg
        elif op == 0x07:
            modo = arg
            e["modo"] = arg
        elif op == 0x0C:
            divisor = arg
        e["imagem_no_ar"] = imagem
        e["modo_no_ar"] = modo
        ops.append(e)
        i += d["n"]
        if op == 0x01:
            break
    return ops, t


def prologo(rel_assets=None):
    """Le e decodifica o script do prologo, com os cruzamentos que o sustentam."""
    p = paths.cd_data("ETC", "OPENING1.DAT")
    if not os.path.exists(p):
        return dict(ok=False, motivo="não existe: %s" % p)
    with open(p, "rb") as f:
        dados = f.read()
    ops, total = decodificar_prologo(dados)
    xa = [o for o in ops if o["op"] == 0x0B]
    esperas = [o["espera_quadros"] for o in ops if o["op"] == 0x04]
    # a espera que vem DEPOIS de cada trecho de XA = quanto cada trecho de narracao dura
    dur_xa, esperando = [], False
    for o in ops:
        if o["op"] == 0x0B:
            esperando = True
        elif o["op"] == 0x04 and esperando:
            dur_xa.append(o["espera_quadros"])
            esperando = False
    return dict(
        ok=True,
        overlay="BIN/OPENING.BIN (overlay 5, base 0x801c2000)",
        arquivo="ETC/OPENING1.DAT",
        arquivo_bytes=len(dados),
        script_offset=PROLOGO_OFF,
        script_bytes=len(dados) - PROLOGO_OFF,
        script_hex=dados[PROLOGO_OFF:].hex(),
        sitio_pc="0x801c21a0 lui 0x8014 / ori 0xb02a -> sw 0x244(0x801c3048)",
        sitio_despachante="0x801c2084 (tabela de 13 handlers em 0x801c2f70)",
        sitio_leitura="0x801c2204 cd_read_file(0x3d = OPENING0.DAT, 0x80100000) e "
                      "0x801c2284 cd_read_file(0x3e = OPENING1.DAT, 0x80100000)",
        opcodes={"0x%02x" % k: v for k, v in sorted(OPS_PROLOGO.items())},
        script=ops,
        quadros_total=total,
        segundos_total=round(total / (30000.0 / 1001.0), 3),
        esperas=esperas,
        trechos_xa=len(xa),
        quadros_por_trecho_xa=dur_xa,
        soma_esperas_xa=sum(dur_xa),
        imagens={
            "0": dict(tim="ETC/OPENING1.DAT TIM[0]", hd="prologo0",
                      mostra="logo da Umbrella sobre uma rua de Raccoon City"),
            "1": dict(tim="ETC/OPENING1.DAT TIM[1]", hd="prologo1",
                      mostra="Jill carregando a arma no apartamento"),
        },
        narracao={
            "faixa": "main06",
            "por_que": "os 4 trechos de XA do script somam 1395 quadros = 46,55 s a 29,97, "
                       "e BGM/gog/main06.ogg tem 46,567 s (ffprobe) — 0,03 %. "
                       "MAIN06 nao existe no disco do PS1 (la a narracao e' XA), o que "
                       "casa com o 0x8002fd30 (stream de XA) do op 0x0b.",
        },
        legendas={
            "arquivo": "mod_BH3_Portuguese/xml/prologue.xml",
            "por_que": "4 blocos <Text> contra 4 trechos de XA, e 1414 quadros de marcacao "
                       "contra 1395 de espera (1,4 %). ⚠ O port desenhava esta legenda sobre "
                       "o `opn.mp4` (90,6 s, DUBLADO) — era o alvo errado.",
        },
        nao_decodificado=[
            "as 3 rotinas por quadro (0x801c2488 / 0x801c2618 / 0x801c2788) que o op 7 "
            "escolhe: e' o movimento (panoramica) e o desenho das 9 fotos de OPENING0.DAT",
            "qual das 9 fotos de OPENING0.DAT aparece em cada momento (elas sao subidas "
            "para a VRAM no init, 0x801c2224 e 0x801c225c, e desenhadas pelas rotinas acima)",
            "os campos do op 0x0b: a tabela 0x801c2f68 (offsets u16) e a estrutura 0x801c2f3c",
        ],
    )


def ler_title_mapping(hires=None):
    """Le `mod_BH3_Portuguese/xml/title_mapping.xml` — o mapa do PROPRIO pacote PT-BR.

    Devolve `{nome do comentario: {x, y, w, h, u, v}}` em unidades de tela do PS1 (320x240).
    O arquivo lista, para cada recorte do atlas PT, ONDE o motor Classic REbirth desenha —
    ou seja e' uma SEGUNDA FONTE, independente do EXE, para posicao de tela.

    ⚠ O de-para ate' agora usava so as CELULAS deste arquivo (`u,v,w,h`) e ignorava `x,y`.
    E `x,y` fecha com o EXE de um jeito que nao pode ser coincidencia:

      * `heavy mode`  x=80  == `x` do SPRT `diff_HARD_MODE` (`0x801945e4`);
      * `light mode`  x=180 == `x` do SPRT `diff_EASY_MODE`;
      * `copyright`   x=60  == `x` do SPRT de copyright, e **y=217 = 213 + (16-8)/2**, isto e'
        a linha PT de 8 px CENTRADA no bloco de 2 linhas (16 px) que o PS1 usa.

    Logo a convencao do pacote e': **a CELULA do atlas PT vai na origem do SPRT do PS1** (e,
    no caso do copyright, centrada em Y no bloco original). Como a tinta nao comeca na borda
    da celula, a posicao da TINTA e' `x + tinta_x` — e era ai que o port errava por 3..6 px.
    """
    raiz_jogo = os.path.dirname(hires_root(hires))
    p = os.path.join(raiz_jogo, TITLE_MAPPING_REL)
    if not os.path.exists(p):
        return {}
    import re
    with open(p, "r", encoding="utf-8-sig", errors="replace") as f:
        txt = f.read()
    pad = re.compile(
        r'<Map\s+x="(-?\d+)"\s+y="(-?\d+)"\s+w="(\d+)"\s+h="(\d+)"\s+u="(\d+)"\s+v="(\d+)"\s*/>'
        r'\s*<!--\s*(.*?)\s*-->')
    saida = {}
    for m in pad.finditer(txt):
        x, y, w, h, u, v, nome = m.groups()
        saida.setdefault(nome, dict(x=int(x), y=int(y), w=int(w), h=int(h),
                                    u=int(u), v=int(v)))
    return saida


def pos_do_mapping(mapa):
    """Para cada rotulo, a posicao declarada pelo pacote PT-BR, se a CELULA bater.

    A checagem e' o ponto: `ROTULOS_PT[k]["origem"]` diz de qual entrada do
    `title_mapping.xml` a celula saiu, e aqui isso deixa de ser comentario e passa a ser
    CONFERIDO — se `u,v,w,h` do XML nao baterem com a celula gravada no de-para, o rotulo
    nao recebe posicao (e `--medir` reclama).
    """
    saida = {}
    for k, d in ROTULOS_PT.items():
        origem = d["origem"]
        if not origem.startswith("title_mapping("):
            continue
        nome = origem[len("title_mapping("):-1]
        #: o comentario do XML para a linha de copyright PT e' so `regular`
        nome = {"copyright regular": "regular"}.get(nome, nome)
        e = mapa.get(nome)
        if e is None:
            continue
        u, v, w, h = d["celula"]
        confere = (e["u"], e["v"], e["w"], e["h"]) == (u, v, w, h)
        saida[k] = dict(nome_mod=nome, x=e["x"], y=e["y"], celula_confere=confere)
    return saida


def layout_rotulos(tinta, sprites, mapping=None):
    """Posicao de tela X de cada rotulo PT-BR — a correcao do desalinhamento.

    PROBLEMA MEDIDO: os rotulos PT tem largura DIFERENTE dos do PS1 (COMECAR JOGO tem
    53 px de tinta contra 48 da celula NEW GAME; CONFIG tem 28 contra 60 de GAME CONFIG).
    A regra anterior do port — "centralizar cada rotulo no centro do retangulo do SPRT
    original" — produz vaos de **13 e 32 px** entre os tres itens (contra 16 e 18 do
    original) e encolhe a linha para a esquerda: a borda direita cai de 260 para 244.

    REGRA A — **posicao do proprio pacote PT-BR**, quando o `title_mapping.xml` declara o
    item (ver `ler_title_mapping`): a celula vai no `x,y` do XML e a tinta em `x + tinta_x`.
    Vale para a tela de DIFICULDADE (`heavy mode` / `light mode`) e para o copyright, porque
    sao os unicos rotulos do nosso conjunto que o pacote posiciona na MESMA tela do PS1.

    ⚠ Foi assim que se descobriu um erro de 6 px do port: o doc dizia "MODO DIFICIL em x=80,
    o mesmo x que o title_mapping declara para heavy mode" — mas 80 e' onde vai a CELULA, e a
    tinta dela comeca 6 px adiante. Comparava-se tinta com celula.

    REGRA B — para os 3 itens do MENU o `title_mapping.xml` NAO serve: os `x` dele (8, 88,
    158, 231, 282) sao da linha de **cinco** itens da versao de PC (`original game`,
    `arrange game`, `load game`, `special`, `configuration`), tela que o PS1 nao tem. Ai vale
    a regra anterior, com duas ancoras MEDIDAS e uma escolha DECLARADA:
      * ancoras medidas = a borda ESQUERDA do primeiro `SPRT` e a borda DIREITA do ultimo
        (`0x801945e4`: 68 e 200+60 = 260);
      * escolha declarada = os VAOS entre os rotulos ficam IGUAIS (medido no render:
        30,25 px de vao dos dois lados, margem 68,75 na esquerda e 60,25 na direita — a
        mesma faixa horizontal do original).
    """
    mapping = mapping or {}
    grupos = [
        ("menu", ["NEW_GAME", "LOAD_GAME", "GAME_CONFIG"]),
        ("dificuldade", ["diff_HARD_MODE", "diff_EASY_MODE"]),
    ]
    saida = {}
    # REGRA A: quem o pacote PT-BR posiciona na mesma tela do PS1 (dificuldade + copyright)
    for k in ("diff_HARD_MODE", "diff_EASY_MODE", "copyright"):
        e = mapping.get(k)
        m = tinta.get(k)
        if e is None or m is None or not e.get("celula_confere"):
            continue
        saida[k] = dict(x=int(e["x"]) + int(m.get("tinta_x", 0)), y=int(e["y"]),
                        w=int(m.get("tinta_w", 0)),
                        grupo="dificuldade" if k.startswith("diff_") else "rodape",
                        regra="title_mapping.xml do pacote PT-BR: celula em x=%d y=%d "
                              "(+ tinta_x=%d)" % (e["x"], e["y"], m.get("tinta_x", 0)))
    for nome_grupo, chaves in grupos:
        if all(k in saida for k in chaves):
            continue                                # REGRA A ja resolveu este grupo
        larguras, ok = [], True
        for k in chaves:
            m = tinta.get(k)
            if not m or not m.get("tinta_w"):
                ok = False
                break
            larguras.append(int(m["tinta_w"]))
        if not ok or any(k not in sprites for k in chaves):
            continue
        esq = int(sprites[chaves[0]]["x"])
        dire = int(sprites[chaves[-1]]["x"]) + int(sprites[chaves[-1]]["w"])
        vaos = max(len(chaves) - 1, 1)
        sobra = (dire - esq) - sum(larguras)
        passo = sobra // vaos
        resto = sobra - passo * vaos
        x = esq
        for i, k in enumerate(chaves):
            saida[k] = dict(x=x, w=larguras[i], grupo=nome_grupo,
                            y=int(sprites[k]["y"]),
                            regra="vaos iguais entre [%d, %d] (ancoras 0x801945e4)"
                                  % (esq, dire))
            x += larguras[i] + passo + (1 if i < resto else 0)
    return saida


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


#: `ETC/INIT_TBL.DAT` (índice 0x30, 2312 B) é o que o TITLE lê ao começar um JOGO NOVO
#: (`0x80196068`, destino `0x800d1d28`). O LAYOUT NÃO FOI DECODIFICADO — o port copia o
#: arquivo e confere tamanho + sha1 para provar que é o certo, e nada mais.
INIT_DATS = ["INIT_TBL.DAT", "INIT_SUB.DAT"]


def copiar_init_tbl(destino):
    """Copia `ETC/INIT_TBL.DAT`/`INIT_SUB.DAT` de `extracted/` para `assets/BOOT/`."""
    import hashlib
    os.makedirs(destino, exist_ok=True)
    rel = {}
    for nome in INIT_DATS:
        src = paths.cd_data("ETC", nome)
        if not os.path.exists(src):
            rel[nome] = dict(ok=False, motivo="não existe: %s" % src)
            continue
        b = open(src, "rb").read()
        shutil.copy2(src, os.path.join(destino, nome))
        rel[nome] = dict(ok=True, arquivo="BOOT/%s" % nome, tamanho=len(b),
                         sha1=hashlib.sha1(b).hexdigest(),
                         bytes_nao_zero=sum(1 for x in b if x))
    return rel


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

def montar_json(rel_assets, tinta, rel_init=None, mapping=None):
    tab = tabela_seno() if os.path.exists(EXE) else []
    rel_filmes = filmes()
    tempos = {n: dict(ticks=t, sitio=s) for n, t, s in TEMPOS}
    # posição de tela dos sprites: a tabela do SPRT de `title_sprites.py`, sem cópia
    ramo_b = {s[0]: dict(x=s[1], y=s[2], u=s[3], v=s[4], w=s[5], h=s[6])
              for s in title_sprites.RAMO_B}
    ramo_a = {s[0]: dict(x=s[1], y=s[2], u=s[3], v=s[4], w=s[5], h=s[6])
              for s in title_sprites.RAMO_A}
    mapping = mapping if mapping is not None else pos_do_mapping(ler_title_mapping())
    lay = layout_rotulos(tinta, ramo_b, mapping)
    rot = {}
    for nome, d in ROTULOS_PT.items():
        u, v, w, h = d["celula"]
        e = dict(u=u, v=v, w=w, h=h, pt=d["pt"], origem=d["origem"],
                 equivale=d["equivale"], nota=d["nota"])
        if nome in tinta:
            e["tinta_x"] = tinta[nome]["tinta_x"]
            e["tinta_w"] = tinta[nome]["tinta_w"]
        if nome in mapping:
            e["pos_mod"] = mapping[nome]
        if nome in lay:
            e["x_tela"] = lay[nome]["x"]
            e["y_tela"] = lay[nome]["y"]
            e["regra_x"] = lay[nome]["regra"]
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
                                  "o arquivo e confere tamanho+sha1, mas o layout não foi "
                                  "medido — o inventário de jogo novo continua vindo do "
                                  "template do EXE (0x800a018c, já em GameState.novo_jogo)."),
            "INIT_SUB": dict(indice=0x2F, destino="0x800d1d28", tamanho=2312,
                             sitio="0x80195fac (só no Mercenaries)", decodificado=False),
            "copiados": rel_init or {},
        },
        "fmv_abertura": {
            "overlay": "OPENING (ovl 5)",
            "sitio": "0x801960d8 load_overlay_task(1, 5) depois do INIT_TBL",
            "sitio_filme": "0x801960e8 filme_prepara(0) = ZMOVIE/OPN.STR, logo depois",
            "arquivo_ps1": "CD_DATA/ZMOVIE/OPN.STR (1350 quadros a 15 fps = 90,0 s)",
            "arquivo_hd": "ZMOVIE/opn.ogv (de zmovie/opn.mp4, 1280x960 h264 29,97 fps, 90,624 s)",
            "correcao": "o OPENING (ovl 5) NAO e' o tocador do filme: e' um SLIDESHOW de "
                        "imagens paradas (ETC/OPENING0.DAT = 9 TIM 8bpp + OPENING1.DAT = "
                        "2 TIM 320x240 16bpp) — o prologo com o logo da Umbrella, as ruas "
                        "de Raccoon City e a Jill carregando a arma. Quem toca o filme e' a "
                        "tarefa de FMV do EXE (0x800321c4 / 0x800324a0).",
        },
        "filmes": {
            "tabela": "0x%08x" % FILMES_TABELA,
            "registros": FILMES_N,
            "registro_bytes": FILMES_STRIDE,
            "prepara": "0x800321c4 filme_prepara(a0 = indice)",
            "tick": "0x800324a0, chamado pelo laco de quadro em 0x80029370",
            "handlers": "0x8009cbb4 = {0x800325a4, 0x800327a4, 0x80032ad4}",
            "fim": "o TITLE espera o bit 0x10000 de 0x800cc858 limpar",
            "prova_quadros": "o campo +0x04 e' (quadros do jPSXdec - 5) em 13/13 videos",
            "prova_geometria": "+0x0a = 320 e +0x0e = 40; 40 + 160 + 40 = 240 -> o quadro "
                               "320x160 do .STR centralizado na tela 320x240",
            "lista": rel_filmes or [],
            "chamadas_title": [dict(sitio="0x%08x" % s, indice=i, onde=o)
                               for s, i, o in FILMES_CHAMADAS_TITLE],
            "opcode_scd": FILME_OPCODE_SCD,
            "snl": "zmovie/snl.mp4 (3,31 s) NAO existe no disco do PS1: o indice do jPSXdec "
                   "lista 13 .STR (ENDA, ENDB, INS01..INS09, OPN, ROOPNE) e nenhum SNL. "
                   "E' extra do PC — nao entra no fluxo de abertura recompilado.",
        },
        "filme_atracao": {
            "nome_port": "filme_atracao",
            "indice": 0x0C,
            "str": "ROOPNE", "mp4": "roop",
            "sitio": "0x801943a4 filme_prepara(0xc) no FIM do handler 0 do TITLE.BIN",
            "quando": "depois do logo CAPCOM (ou do reset 0x80194374, ou do pulo 0x8019432c) "
                      "e ANTES do estado 1 (0x80194444, que carrega o titulo e a MAIN38). "
                      "0x8019439c pula o filme quando o bit 0x80 (Mercenaries) esta ligado; "
                      "0x801943ac espera o bit 0x10000 limpar.",
            "correcao": "o fluxo do port nao tinha este passo — era o VIDEO QUE FALTAVA "
                        "antes do menu principal.",
        },
        "atrator": {
            "timeout_ticks": 900,
            "sitio_timeout": "0x8019454c *(u16*)(ctx+0x16) = 0x384",
            "para_onde": "sub 10 (0x801966cc) = DEMO JOGAVEL",
            "sitio": "0x8019566c: quando o contador vira 0xffff, ctx[1] = 0xa (10)",
            "demo": "ETC/PDEMO00/01/02.DAT (indices 0x41/0x42/0x43, 3620 B cada) em "
                    "rodizio por *(u8*)0x800c79af, carregados em 0x80192000; a tarefa e' "
                    "0x80031bdc e no fim o handler 0 poe *(u8*)ctx = 4 (0x801967e4).",
            "correcao": "o atrator do original **NAO toca o FMV de abertura**. O sub 11 "
                        "(0x80196800), que carrega o OPENING e chama filme_prepara(0), "
                        "nao e' alcancado pelo timeout: varri todas as escritas em ctx+1 "
                        "no TITLE.BIN e nenhuma grava 11. O port tocava `opn` no timeout "
                        "— era o 'video comecando antes de clicar'.",
            "port": "sem reprodutor de PDEMO, o port repete o filme de atracao (roop) e "
                    "volta ao titulo. DECLARADO: escolha do port.",
        },
        "som_titulo": SOM_TITULO,
        "vinheta_titulo": dict(VINHETA_TITULO, medida=medir_vinheta()),
        "prologo": prologo(),
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
    rel_init = copiar_init_tbl(destino)
    tinta = medir_tinta(hires)
    mapping = pos_do_mapping(ler_title_mapping(hires))
    d = montar_json(rel, tinta, rel_init, mapping)

    os.makedirs(paths.data(), exist_ok=True)
    saida = paths.data("boot_flow.json")
    with open(saida, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)

    print("destino  = %s" % paths.name())
    for nome, r in rel.items():
        marca = "ok " if r.get("ok") else "FALTA"
        pt = "PT" if r.get("conjunto_pt") else "?? (fora do conjunto PT)"
        print("  %-5s %-12s %-22s %s" % (marca, nome, r.get("hires", r.get("motivo", "")), pt))
    for nome, r in rel_init.items():
        print("  %-5s %-12s %s" % ("ok " if r.get("ok") else "FALTA", nome,
                                   "%d B sha1 %s (%d bytes não-zero)"
                                   % (r["tamanho"], r["sha1"][:12], r["bytes_nao_zero"])
                                   if r.get("ok") else r["motivo"]))
    print("-> %s" % saida)
    def soma(prefixo):
        return sum(t for n, t, _s in TEMPOS if n.startswith(prefixo))
    for fase, pref in [("aviso", "aviso"), ("capcom", "capcom"), ("titulo (entrada)", "titulo")]:
        n = soma(pref)
        print("  tempo %-17s %4d ticks = %5.2f s a 59,94 Hz (%d quadros a 30 Hz)"
              % (fase, n, n / 59.94, n // 2))
    at = soma("atrator")
    print("  atrator            %4d ticks = %5.2f s" % (at, at / 59.94))
    ini = soma("inicio")
    print("  transicao inicio   %4d ticks = %5.2f s (0x80195e9c/0x80195eec/0x80195f3c)"
          % (ini, ini / TAXA_TICK))

    v = medir_vinheta()
    if v is None:
        print("  VINHETA: %s.VH/.VB nao extraidos (extracted/ntsc-u/CD_DATA/SOUND)"
              % VINHETA_TITULO["banco"])
    else:
        print("  VINHETA cat %d / id %d do %s  desc %s  %d vozes (tons %d..%d)"
              % (VINHETA_TITULO["cat"], v["id_se"], v["banco"], v["descritor"],
                 v["vozes"], v["tom_base"], v["tom_base"] + v["vozes"] - 1))
        for e in v["vozes_detalhe"]:
            print("     tom %2d pan %3d (%-9s) vag %d  %6d B  %5.3f s @ %5d Hz  %s"
                  % (e["tom"], e["pan"], e["lado"], e["vag"], e["vag_bytes"],
                     e["duracao_s"], e["taxa_hz"], e["wav"]))
        print("     duracao %5.3f s = %d ticks ; %.1f%% do %s.VB ; estereo=%s"
              % (v["duracao_s"], v["ticks"], 100.0 * v["fracao_do_banco"],
                 v["banco"], v["estereo"]))
        print("     a transicao tem %d ticks (%.2f s): o original NAO espera o som acabar"
              % (ini, ini / TAXA_TICK))

    if a.medir:
        print("\ntinta medida no atlas HD (unidades SD):")
        for nome, m in tinta.items():
            print("  %-16s celula=%s  tinta x=%d w=%d   pt=%r"
                  % (nome, m["celula"], m["tinta_x"], m["tinta_w"], ROTULOS_PT[nome]["pt"]))
        print("\ntitle_mapping.xml do pacote PT-BR (posicao declarada pelo proprio pacote):")
        if not mapping:
            print("  AUSENTE: %s" % os.path.join(os.path.dirname(hires), TITLE_MAPPING_REL))
        for nome, e in mapping.items():
            print("  %-16s <!-- %-18s -->  celula em x=%3d y=%3d  celula_confere=%s"
                  % (nome, e["nome_mod"], e["x"], e["y"], e["celula_confere"]))
        print("\nposicao final da TINTA na tela (o que o titulo.gd desenha):")
        ramo = {s0[0]: dict(x=s0[1], y=s0[2], u=s0[3], v=s0[4], w=s0[5], h=s0[6])
                for s0 in title_sprites.RAMO_B}
        for nome, e in layout_rotulos(tinta, ramo, mapping).items():
            print("  %-16s x=%3d..%3d y=%3d   %s"
                  % (nome, e["x"], e["x"] + e["w"], e["y"], e["regra"]))

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
        # os fades do aviso/CAPCOM vivem nos OVERLAYS (0x80184000 / 0x80194000), fora do EXE:
        # para relê-los use `python tools/boot_flow.py --calls WARNING` / `--calls TITLE`.
        print("  tabela de overlays 0x8009c944[1] (WARNING) file_index = 0x%02x"
              % exe.u32(0x8009C944 + 12))


if __name__ == "__main__":
    main()
