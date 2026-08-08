#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""exe_audio.py — de-para PROVADO `id de SE` -> amostra (WAV) do RE3 PS1 (SLUS_009.23).

Fecha o buraco que `docs/decomp/notes/sfx.md` §8.3 declarava insolúvel ("não há link
estático id -> vag"). **Há**: a tabela id -> descritor mora no INÍCIO do próprio
`.VH`/`.SND` do banco, e o descritor traz o índice do TOM (`VagAtr`), cujo campo `vag`
aponta a amostra. O que é resolvido em runtime é só QUAL banco está carregado.

────────────────────────── O que foi provado no EXE ──────────────────────────
Motor de som (endereços virtuais do `SLUS_009.23`, base 0x80010000):

  0x800746c0  SE_pede(a0=id, a1=ptr param 16B, a2, a3)
              id = (b2<<16) | (cat<<8) | idx
              grava um registro de 32 B no anel `0x800e0de4` (24 slots):
                +0x08..+0x17 = 16 B copiados de `a1` (posição 3D quando a1 != 0)
                +0x18 = a3   +0x1a = a2
                +0x1c = u16 idx      (`sh v0,0x1c` com v0 = a0 & 0xff)
                +0x1e = u8 (a0>>16)  +0x1f = u8 cat (a0>>8)
              avança o ponteiro de escrita `0x800e10e4` em 0x20.
              Porta de prioridade: se `*(0x800cc858) & 0x10000000` e cat >= 5, descarta.
  0x800744e0  laço consumidor (dentro do tick do motor): varre o anel de
              `0x800e0de4` até `*(0x800e10e4)`, passo 0x20, e para cada registro chama
              `*(0x800a1130 + (cat >= 5 ? 4 : 0))` = 0x80074770 (cat<5) / 0x80074820
              (cat>=5); depois zera o ponteiro de escrita.
  0x80074770  resolve: cat = u8@+0x1f, idx = u16@+0x1c;
              `desc = *( *(0x800e0610 + cat*4) + idx*4 )`; **desc == -1 -> descarta**;
              `banco = (desc.byte0 & 0xe) >> 1`, procurado em `0x800750e4`.
  0x800750e4  busca_banco(a0): varre 8 slots de 8 B em `0x800e0664` por `s16 == a0`;
              devolve o slot ou -1. É a MESMA função usada para `cat` e para o
              `banco` do descritor -> logo **cat == id de banco VAB**.
  0x800749a0  aloca voz do SPU + aplica volume/pan/pitch (lê `desc.byte2/byte3`).
  0x80075b90  volume/pan: `voz+0x08 = vol`, `voz+0x0a = vol`; se pan < 0x40
              `voz+0x08 = vol*pan/63`; se pan > 0x40 `voz+0x0a = vol*(0x7f-pan)/63`
              (divisão por 63 pelo idioma de magic-number 0x82082083 + shift 5).
  0x8007f768  libspu `SpuSetVoiceAttr` (chamado com mask=3 = VOLL|VOLR por 0x80075120).
  0x8007eda8  libspu `SpuSetKey(a0=on/off, a1=bitmask de 24 vozes)` — escreve
              KON/KOFF em `+0x188/+0x18a` e `+0x18c/+0x18e` do bloco de registradores
              do SPU, cujo ponteiro (0x1f801c00) vive em `*(0x800a1250)`.
  0x8007f518  libspu `SpuGetAllKeysStatus` (a1=0x17, a2=`0x800e116c`) — o array de
              status por voz que `0x800749a0` usa para achar voz livre.

Cadeia completa: `0x800746c0` -> anel -> `0x80074770`/`0x80074820` -> `0x800749a0`
-> `SpuSetVoiceAttr` / `SpuSetKey`.

────────────────────── Formato do banco (`.VH` / `.SND`) ──────────────────────
    [tabela de SE: N x u32]  [header VAB: 0x30 B]  [tons: 32 B cada]  [tabela VAG]

  * A tabela de SE começa no offset **0** do arquivo. `0xffffffff` = id não usado.
  * O header VAB é localizado pelo **magic `0x0001eeee`** gravado em `hdr+0x10`
    (35/35 arquivos). Logo `N = hdr/4`: `C_*` -> 16, `A_*` -> 32, `R000` -> 48.
  * `hdr+0x00` u32 = tamanho do `.VB` (confere em 35/35).
  * `hdr+0x14` u16 = nº de tons (confere com `vab.parse_tones` em 35/35).
  * `hdr+0x16` u16 = nº de VAGs.
  * `hdr+0x18` u8 = volume mestre (0x7f), `hdr+0x19` u8 = pan mestre (0x40).
  * tons em `hdr+0x30`; tabela VAG em `hdr + u32@hdr+0x08`.

  Descritor de SE (u32 little-endian), campos confirmados no disassembly:
    byte0 bits1-3 : **id do banco VAB** (0..7)     -> `(b0 & 0x0e) >> 1`
    byte1 bits4-7 : **índice do TOM** no banco      -> `b1 >> 4`
    byte2 bit7    : 1 = aloca voz dinamicamente / 0 = voz fixa (lido em 0x800749e8)
    byte2 bits0-4 : voz/grupo base (lido em 0x800749f8)
    byte3 bit0    : flag lida em 0x80074a08
    byte1 bits0-3, byte3 bits1-7: **NÃO PROVADO** (ver §resíduo do doc)

  Validação: `b1>>4 < n_tons` em **278/278** descritores usados dos 35 bancos, e o
  `banco` do descritor é sempre o mesmo dentro de um arquivo (`C_*`=0, `A_*`=1,
  `R000`=2) — o que sustenta `cat == id de banco`.

  Amostra final: `tom.vag` (1-based). VAG#1 é o bloco mudo padrão do SPU e é
  descartado por `re3_sfx.py`, que numera os WAV por posição entre as amostras
  reais -> **`vag k` => `<banco>_{k-2:02d}.wav`**.

Além dos 35 bancos do disco (`SOUND/*.VH` + `R000.SND`), **todo `STAGE*/DOOR??.DO1`
embute um banco VAB de PORTA** com o mesmo formato (`cat 4`, 4 ids) — 76 bancos, provado
em 76/76. Ver o bloco `bancos_porta`/`parse_porta` e `exe_audio.md §4.4`.

E **todo `STAGE*/R???.ARD` embute o banco de SALA (`cat 2`, 48 ids)**: a tabela de SE e o
header VAB moram no RDT e o corpo PS-ADPCM é o **sub-bloco 9 do contêiner** (o que
`ARD.md §2` rotulava `mask_extra`) — 169 bancos, provado em 169/169. Ver `bancos_sala`/
`parse_sala` e `exe_audio.md §13`.

Uso:
    python tools/exe_audio.py                 # gera <out>/data/re3_se.json + sfx_map.json
    NOSTALGIA_OUT=port python tools/exe_audio.py
    python tools/exe_audio.py --verificar     # sai != 0 se alguma asserção falhar
    python tools/exe_audio.py --tabela C_00   # imprime a tabela de SE de um banco
    NOSTALGIA_OUT=port python tools/exe_audio.py --portas   # 147 WAV dos bancos de porta
    NOSTALGIA_OUT=port python tools/exe_audio.py --salas    # 1702 WAV dos bancos de sala
    python tools/exe_audio.py --armas         # SE por QUADRO de animação das 21 armas (§14)

Ver: docs/decomp/notes/exe_audio.md
"""
import json
import os
import struct
import sys

import paths
import vab

MAGIC_VAB = 0x0001EEEE           # header VAB **versão 1** (35 bancos do disco, 76 portas, 94 salas)
MAGIC_VAB_V2 = 0x0002EEEE        # header VAB **versão 2** (75 salas) — só o tamanho do header muda
MAGICS_VAB = (MAGIC_VAB, MAGIC_VAB_V2)
VAG_DUMMY = 1                    # VAG#1 = bloco mudo padrão do SPU (descartado)

# `N` = quantos ids de SE cada `cat` tem. **Tabela `0x800a0fe4` do EXE** (8 bytes),
# lida em `0x80078384..0x80078390` dentro de `0x8007836c(a0 = cat, a1 = base do banco)`:
#     *(0x800e0610 + cat*4) = a1                  ; a base da TABELA DE SE
#     a1 += *(0x800a0fe4 + cat) * 4               ; -> o header VAB
# Ou seja **`hdr == base_da_tabela + N*4`** é instrução, não regularidade observada. Nos
# arquivos do disco a tabela começa no offset 0 e por isso `hdr == N*4` (C_ = 0x40,
# A_ = 0x80, R000 = 0xC0); nos bancos EMBUTIDOS (porta, sala) a tabela é `hdr - N*4`.
N_SE_POR_CAT = {0: 16, 1: 32, 2: 48, 3: 32, 4: 4}
EXE_N_SE_POR_CAT = 0x800A0FE4    # endereço da tabela acima no SLUS_009.23 (8 bytes)


def tam_header(versao):
    """Tamanho do header VAB em bytes. **PROVADO** em `0x800783a4..0x800783b0`:

        lhu  $v0, 0x12($a1)     ; hdr+0x12 = u16 ALTO do magic = a VERSÃO (1 ou 2)
        addiu $a1, $a1, 0x20
        sll  $v0, $v0, 4        ; versao * 16
        addu $a1, $a1, $v0      ; base do array de TONS = hdr + 0x20 + versao*0x10
        sw   $a1, 0x18($a2)

    Logo `0x0001eeee` -> tons em `hdr+0x30` e `0x0002eeee` -> `hdr+0x40`. A §11.4 media
    isso por estatística (`u32@hdr+0x08 == tam + 32*n_tons` em 168/168); agora é a
    aritmética do motor.
    """
    return 0x20 + versao * 0x10

# Corpo (.VB) com nome diferente do header (mesma regra de re3_sfx.py).
CORPO_ESPECIAL = {"R000": "R_000.VB"}

# ─────────────────────────── Ações nomeadas ───────────────────────────
# `cat` = id de banco VAB: 0 = C_xx (personagem/UI/global), 1 = A_xx (ARMA equipada — ver
#           `tiro_arma`), 2 = R###.SND (sala), 4 = porta (banco embutido no DOORxx.DOn).
#
# PROVA de cada nome está no campo `prova`. Só os 5 de menu têm confirmação de
# comportamento (observada pelo dono do repo no jogo) + corroboração estática: são os
# únicos ids de cat 0 chamados com `a1 = 0` (sem posição 3D) e todos os seus call sites
# caem em código de menu. O resto é **DECLARADO** (escolha do port) — o call site está
# registrado para quem quiser fechar por ouvido.
ACOES = {
    # ---- confirmados (comportamento observado + call sites de menu) ----
    "menu_mover": dict(cat=0, id=4, conf="ALTA", prova=(
        "11 call sites de 0x800746c0 com a0=4 (a1=0, sem posição 3D), todos em código "
        "de menu: 0x8003054c 0x800308f8 0x800638f4 0x80064684 0x8006688c 0x80066a78 "
        "0x800670f4 0x800672b0 ...; comportamento confirmado no jogo pelo dono do repo")),
    "menu_cancelar": dict(cat=0, id=5, conf="ALTA", prova=(
        "20 call sites com a0=5 (o mais frequente — 'voltar' existe em toda tela): "
        "0x800304e0 0x8003088c 0x80063c20 0x80063e74 0x80064538 ...")),
    "menu_confirmar": dict(cat=0, id=6, conf="ALTA", prova=(
        "13 call sites com a0=6: 0x80023d10 0x80064500 0x80064aa4 0x8006669c ...")),
    "menu_invalido": dict(cat=0, id=7, conf="ALTA", prova=(
        "5 call sites com a0=7: 0x800666bc 0x80067e90 0x80067ebc 0x800687b0 0x8006fdd0")),
    "menu_abrir": dict(cat=0, id=9, conf="ALTA", prova=(
        "5 call sites com a0=9: 0x80023db8 0x800666f0 0x80066728 0x8006dd40 0x8006fdb4")),
    # ---- ARMA: o estouro é cat 1 / id 0 (MEDIDO em 2026-08-08) ----
    # Duas provas independentes:
    #  1. Tabela de 20 funções POR ARMA em 0x8009ced8..0x8009cf24, indexada por `w - 1`
    #     (`0x8003ea1c`: `lbu v1,0x46(s3)` -> `addiu v1,-1` -> `sll 2` -> `lw` -> `jalr`).
    #     Em cada entrada aparece o mesmo trecho: 0x80044804 (HITSCAN, a2 = lbu player+0x46)
    #     -> 0x80047860 -> 0x8006d030(1) -> SE_pede(cat 1, idx 0, a1 = *(player+0x108)+0x344).
    #     São ~20 dos 155 `jal 0x800746c0`, todos com o MESMO id (ex.: 0x80041018, 0x80041184,
    #     0x8004161c, 0x80041904, 0x80041ab8, ... 0x80043a40).
    #  2. `A_01` é o ÚNICO dos 20 bancos `A_` que NÃO define o id 0 (define 6..10) — e `A_01`
    #     é o banco de `w = 1`, a FACA. 19/20 definem o id 0.
    # A tabela de TIMING vizinha (0x8009cf28) é lida com stride 3 e o mesmo índice `w - 1`
    # (`0x8003e454`: `sll v0,v1,1` + `addu v0,v0,v1`), o que confirma a base do índice.
    "tiro_arma": dict(cat=1, id=0, conf="MEDIA", prova=(
        "MEDIDO: as 20 funções da tabela POR ARMA 0x8009ced8 (indexada por player+0x46 - 1, "
        "ver 0x8003ea1c) pedem cat 1 / idx 0 logo depois do hitscan 0x80044804 e do "
        "0x8006d030(1); e A_01 (w=1, a FACA) é o único dos 20 bancos A_ que não define o "
        "id 0. Banco = A_{w:02X} (0x80043eb4 -> 0x8007809c(1, lbu player+0x46); base 0xda, e "
        "o fid 0xdc mede 384 B = |A_01.VH|). O que falta é o de-para item -> w")),
    # ---- declarados: call site provado, SEMÂNTICA NÃO PROVADA ----
    "tiro": dict(cat=0, id=11, conf="DECLARADO", prova=(
        "call sites 0x8003ad6c (`lui a0,1; ori a0,a0,0xb` -> a0=0x1000b) e 0x8003cf10, "
        "ambos com a1 = player+0x34 (posição) na sequência de disparo/ataque "
        "(exe_combat.md §2). Nome 'tiro' é DECLARADO: o par id->ação não foi ouvido. "
        "NOTA: C_00/C_01 (bancos de menu) NÃO definem o id 11 — só os C_02..C_0D de "
        "área — o que é coerente com 'não há tiro no menu'. CORREÇÃO 2026-08-08: o ESTOURO "
        "da arma é a ação `tiro_arma` (cat 1 / id 0); este id 11 é pedido dentro da rotina 7 "
        "(mira, 0x8003a7d8), num trecho que mexe em player+0x6e (pitch) e num contador u16 "
        "@0x800d1f96 — não no hitscan. Fica como FALLBACK do port")),
    # ---- DANO ao player: cat 0, ids 0..3 (CORRIGIDO na varredura dos 155) ----
    # O que estava aqui: `impacto_ataque` (id 0) = "acerto do ataque do player conectou" e
    # `acao_1/2/3` sem nome. **Errado.** Os 5 pedidos de cat 0 / ids 0..3 estão TODOS nas
    # funções 0x8003d1a8, 0x8003d2d8, 0x8003d4c0, 0x8003d780 e 0x8003da3c, e as cinco são a
    # REAÇÃO DE DANO do player: `exe_combat.md §1.3` mediu por exaustão os 168 escritores de
    # `player+0xc8` e concluiu que as anims de hurt são 4/5/9/10/11/12, com escritores
    # 0x8003d200, 0x8003d52c, 0x8003d630, 0x8003d6ec, 0x8003d72c, 0x8003d910 e 0x8003d990 —
    # todos dentro dessas mesmas funções. E o idioma de cada uma é idêntico:
    #     sub 0 (player+6 == 0): grava `player+0xc8 = 0x3____` (a anim), `player+6 = 1`
    #                            e pede o SE com `a1 = player+0x34` (posição do player).
    # Logo cat 0 / id 0 = o som que sai quando a Jill TOMA dano (anim 4), e 1/2/3 são as
    # outras variantes de gravidade/direção. Qual é qual continua DECLARADO.
    "dano_player": dict(cat=0, id=0, conf="MEDIA", prova=(
        "0x8003d208 (`lui a0,1` -> a0=0x10000) em 0x8003d1a8, que grava player+0xc8=0x30004 "
        "(anim 4) e player+6=1 com a1 = player+0x34. `exe_combat.md §1.3` mediu que as anims "
        "de HURT do player são 4/5/9/10/11/12 e que 0x8003d200 (esta função) é um dos "
        "escritores. É reação de DANO — não 'acerto do ataque', como esta tabela dizia")),
    "dano_player_2": dict(cat=0, id=1, conf="DECLARADO", prova=(
        "0x8003d560 (em 0x8003d4c0, que contém os escritores de anim de hurt 0x8003d52c/"
        "0x8003d630/0x8003d6ec/0x8003d72c) e 0x8003d354 (em 0x8003d2d8, onde "
        "`a0 = 0x10000 | ((u8 player+5 & 1) + 1)` = id 1 OU 2 por paridade da rotina). "
        "Variante de dano; qual gravidade é DECLARADO")),
    "dano_player_3": dict(cat=0, id=2, conf="DECLARADO", prova=(
        "0x8003d82c (em 0x8003d780, com os escritores de hurt 0x8003d910/0x8003d990) e o "
        "ramo par de 0x8003d354. Variante de dano")),
    "dano_player_4": dict(cat=0, id=3, conf="DECLARADO", prova=(
        "0x8003dac8 (em 0x8003da3c, última função da região de dano). Variante de dano")),
    "agarrado": dict(cat=0, id=11, conf="DECLARADO", prova=(
        "0x8003cf10, sub 0 da macro-ação 13 (0x8003cea0): grava `player+0xc8 = 0x30012` "
        "(anim 18), `player+6 = 1`, liga `gs+0x77f4 |= 0x100`, INCREMENTA o contador u16 "
        "`gs+0x785e` e, no mesmo bloco (0x8003d114), pede um SE de **cat 3 (banco do "
        "INIMIGO)** com id 3 ou 19 conforme o tipo do inimigo (`u8 @ *(0x800cc858+...)+3`). "
        "Player + inimigo soando juntos, com contador = **ser AGARRADO/mordido**. O id 11 é o "
        "MESMO que a rotina 7 (mira) pede em 0x8003ad6c — por isso o nome segue DECLARADO")),
    # ---- ARQUIVO: virar página é o id 8 (MEDIDO nesta rodada) ----
    "arquivo_pagina": dict(cat=0, id=8, conf="ALTA", prova=(
        "MEDIDO em 0x80063850, o estado 8 da tela (ARQUIVO — ver menu_pc_sys.md §6.1), "
        "sub-estado 0: com `*(0x800cc830) & 0x8000` e `ctx+0xbd != 0` o fluxo cai em "
        "0x80063948 (`a0 = 8`), faz `ctx+0xbd -= 1`, grava `ctx+0xc6 = 2` (direção do "
        "deslize) e `ctx+0x11++` — o pedido é 0x80063984. Com `*(0x800cc830) & 0x2000` e "
        "`ctx+0xbd < u16 *(0x8009f2ac + ctx+0xbc*2) - 1` cai em 0x800639f0 (`a0 = 8`), faz "
        "`ctx+0xbd += 1` e `ctx+0xc6 = -2` — pedido em 0x80063a2c. Ou seja **os dois únicos "
        "call sites do id 8 do EXE são as duas direções de VIRAR PÁGINA**, com a checagem de "
        "borda (0x8009f2ac = nº de páginas por documento). O nome do botão físico "
        "(0x8000 / 0x2000 no pad cru) NÃO foi medido. C_00/C_01 (bancos de MENU) não definem "
        "o id 8 — só os C_02..C_0D de personagem: em jogo o banco de cat 0 é o C_02")),
    "impacto_projetil": dict(cat=0, id=13, conf="DECLARADO", prova=(
        "0x80045b10 0x80045e68 0x800465fc, todos em 0x80045950 — a rotina de "
        "colisão/integração de projétil que `exe_combat.md` linha 268 encadeia como "
        "0x80045094 -> 0x80045950 -> 0x80040d40. Nome DECLARADO")),
    "sala_entrada": dict(cat=0, id=14, conf="DECLARADO", prova=(
        "0x80077f40 (a1=0 -> UI/global) em 0x80077ed4, que é chamada por 0x800495fc — "
        "DENTRO do room-loader 0x800493ec, o mesmo que carrega o banco de cat 0 em "
        "0x800495d0. Som de entrada/ambiente de sala. Nome DECLARADO")),
    "acao_15": dict(cat=0, id=15, conf="DECLARADO", prova=(
        "call site 0x800485e4 (a1=0 -> UI) em 0x80048520, chamada por 0x8002378c dentro do "
        "fluxo de jogo 0x80023268. NÃO SEI o evento; nenhum banco C_ do disco define o "
        "id 15, então não há amostra")),
    # ---- inventário / comandos: ids de UI com evento MEDIDO no handler ----
    "item_pego": dict(cat=0, id=5, conf="MEDIA", prova=(
        "os 2 pedidos da JANELA DE OBTER ITEM (0x80069c3c, sub-estado 0xb / kind 1 — "
        "`exe_items.md §2.3`) são 0x80069ed0 (`a0 = 5` imediato) e 0x80069fb0, cujo `a0` sai "
        "do DELAY SLOT do `beq v0,a1,0x80069f9c` de 0x80069eb8 (`addiu a0,zero,5`) — único "
        "predecessor do bloco. Ou seja pegar item usa o MESMO id do 'cancelar' (5); é o dado "
        "que manda, não é erro de leitura")),
    "combinar_ok": dict(cat=0, id=6, conf="MEDIA", prova=(
        "0x80068a10, no executor genérico da COMBINAÇÃO (0x80068024, `menu_comandos.md §5`). "
        "O `a0` não é imediato no bloco: o bloco 0x800689b0 tem 7 predecessores "
        "(0x8006857c 0x800685c4 0x80068660 0x800686a4 0x8006884c 0x8006892c 0x80068970) e "
        "**todos os 7 carregam `a0 = 6`** — logo a combinação bem-sucedida toca o id 6")),
    "combinar_erro": dict(cat=0, id=7, conf="MEDIA", prova=(
        "0x800687b0 (`a0 = 7` imediato), no mesmo executor 0x80068024 — o ramo em que a "
        "receita não fecha. Mesma família do 'inválido' de 0x800666bc")),
    "examinar": dict(cat=0, id=6, conf="MEDIA", prova=(
        "0x80069454 (`a0 = 6`) em 0x80069280 = comando 2 = CHECK/examinar "
        "(`menu_comandos.md §6`); o outro pedido da mesma função é o id 5 de sair "
        "(0x80069470)")),
    "equipar": dict(cat=0, id=5, conf="MEDIA", prova=(
        "0x80067b40 (`a0 = 5`) em 0x800676b8 = comando 0 = USE/EQUIP "
        "(`menu_comandos.md §3`) — é o ÚNICO pedido de SE dessa função")),
    "bau_mover": dict(cat=2, id=0x15, conf="DECLARADO", prova=(
        "4 pedidos de cat 2 / id 0x15 em 0x800646f0 (sub-estado 1 da tela do BAÚ, tabela "
        "0x8009f4e4[1]): 0x80064b2c 0x80064bc8 0x80064d1c 0x80064d90 — a transferência de "
        "item entre inventário e caixa. É banco de SALA (cat 2), logo SEM amostra no port")),
    "bau_abrir": dict(cat=2, id=0x14, conf="DECLARADO", prova=(
        "0x80051578 (`a0 = 0x214`) em 0x800514f0 = o driver da tela da CAIXA DE ITENS que o "
        "`sce 9` instala em `gs+0x75e0` (`menu_bau.md`, 0x800514e0). Banco de SALA: sem "
        "amostra no port")),
    "subir": dict(cat=2, id=0, conf="MEDIA", prova=(
        "0x8003b224 em 0x8003b1c4 = a macro-ação 9 (SUBIR/DESCER; o port a reimplementa em "
        "`port/script_vm/subir.gd`). Antes do SE a função grava `+0xc8 = 6`, `+0xc9 = 0`, "
        "`+0xca = 7` e depois chama a vibração 0x8003893c. Banco de SALA: sem amostra")),
    "subir_impacto": dict(cat=2, id=0x2c, conf="DECLARADO", prova=(
        "0x8003b3e8 (`a0 = 0x22c`) em 0x8003b244 = a animação da macro-ação 9, no sub 5 com "
        "`+0xc9 == 1` — é o que `subir.gd` já chama de SFX_IMPACTO. Banco de SALA")),
    "mensagem_avanca": dict(cat=0, id=4, conf="DECLARADO", prova=(
        "0x8003054c e 0x800308f8 (`a0 = 4`, a1 = 0) nos dois desenhadores de mensagem "
        "0x800303ec / 0x80030764, que o interpretador 0x8002fee8 chama em 0x800302e4 / "
        "0x800302d4 (`menu_texto.md §linha 413`). Mesmo id do 'mover cursor'")),
    "mensagem_fecha": dict(cat=0, id=5, conf="DECLARADO", prova=(
        "0x800304e0 e 0x8003088c (`a0 = 5`) nos mesmos dois desenhadores de mensagem")),
    # ---- porta: banco cat 4, embutido nos DOOR*.DO1 ----
    # MEDIDO nesta rodada: o ÚNICO id de cat 4 que o motor toca é o **1**. A máquina de
    # estados da animação de porta é a tabela de 3 funções `0x800979f0` =
    # {0x80015498, 0x80015754, 0x80016150}; varrendo os 155 `jal 0x800746c0` do EXE, o único
    # que cai em 0x80014000..0x80019000 é `0x800161c4` (`a0 = 0x401` -> cat 4, id 1), dentro
    # do estado 2 (`0x80016150`). Os estados 0 e 1 não pedem SE nenhum. O gatilho é a flag
    # `0x2000` do `u16@+6` da entrada de animação da porta (0x800163ec -> `sh 1, 0x240(gs)`),
    # lida de volta em `0x800161b4` antes do pedido.
    "porta_abrir": dict(cat=4, id=1, conf="MEDIA", prova=(
        "cat 4 = banco de PORTA: os 76 STAGE*/DOORxx.DOn embutem um banco VAB (magic "
        "0x0001eeee) cujos descritores usam banco 4 em 76/76, e é o recurso que o loader "
        "0x80012818 carrega com a string de depuração 'DOOR SOUND' (0x800103ac, passada em "
        "a3 por 0x80016534 dentro de 0x8001644c). O **id é MEDIDO**: 0x800161c4 (a0=0x401 "
        "-> cat 4, id 1) é o ÚNICO pedido de cat 4 do EXE inteiro, no estado 2 da máquina "
        "de porta 0x800979f0, gatilhado pela flag 0x2000 da entrada de animação. O NOME "
        "'abrir' é interpretação: que o momento seja abrir e não fechar NÃO foi medido")),
    "porta_som_0": dict(cat=4, id=0, conf="DECLARADO", prova=(
        "id 0 do banco de porta — o único VÁLIDO em 76/76 bancos (aponta o tom 1). "
        "NENHUM call site: não existe pedido de cat 4 com id 0 no EXE. Fica exposto para "
        "quem quiser experimentar, mas o motor NÃO o toca pela via de porta")),
    "porta_som_2": dict(cat=4, id=2, conf="DECLARADO", prova=(
        "3º id do banco de porta; existe em só 4 dos 76 bancos e não tem call site. "
        "NÃO PROVADO")),
    # ---- porta TRANCADA / destrancar: são cat 2 (banco de SALA), não cat 4 ----
    # MEDIDO no produtor de porta `0x80050d28` (jump-table de SCE `0x8009e0bc[1]`), que é
    # quem roda quando o personagem usa a porta. Ele pede 5 SE, TODOS com cat 2:
    #   desc+0x10 (Key_Type) == 0xfe -> a0=0x226 (0x80050dd8) + mensagem 0x11
    #   desc+0x10 == 0xff            -> a0=0x216 (0x80050e10) + mensagem 0x12
    #   tem a chave (0x8006cc8c>=0)  -> a0 = desc+0xe ? 0x204 : 0x225  (0x80050e74)
    #   não tem a chave              -> a0 = desc+0xe ? 0x205 : 0x216  (0x80050ed8/0x80050f14)
    # `desc+0xe` é o `Knock_Type` do SCE_DOOR_AOT_SET (0 em 449 das 453 portas).
    "porta_trancada": dict(cat=2, id=0x16, conf="MEDIA", prova=(
        "MEDIDO: 0x80050ed8/0x80050f14 no produtor de porta 0x80050d28 pedem a0=0x216 "
        "(cat 2 = banco de SALA, id 0x16) no caminho 'não tem a chave', e 0x80050e10 "
        "usa o mesmo id quando Key_Type==0xff (porta que nunca abre). O port não tem "
        "amostra: o único banco de sala do disco é R000.SND e a tabela de SE dele é toda "
        "0xffffffff — logo wav_padrao fica nulo (honesto, não inventado)")),
    "porta_destrancar": dict(cat=2, id=0x25, conf="MEDIA", prova=(
        "MEDIDO: 0x80050e74 pede a0 = (desc+0xe ? 0x204 : 0x225) no caminho 'tem a chave', "
        "logo antes de instalar o callback 0x80050fe0. id 0x25 é o caso Knock_Type==0 "
        "(449 das 453 portas); id 4 é o outro")),
    "porta_emperrada": dict(cat=2, id=0x26, conf="MEDIA", prova=(
        "MEDIDO: 0x80050dd8 pede a0=0x226 quando Key_Type==0xfe (10 das 453 portas), "
        "junto da mensagem 0x11")),
    # ---- ARMA VAZIA / clique seco: cat 1 / id 1 (MEDIDO nesta rodada) ----
    # Os 4 sítios de cat 1 / id 1 do EXE são o MESMO idioma, em 4 subestados de arma:
    #     if (*(gs+0x2108) & 0x40) {                     ; botão de RECARREGAR
    #         if (0x8006cf0c(0) == -1)  SE cat 1 / id 1  ; munição NÃO encontrada
    #         else                      player+6 = 4 (ou 10)   ; TEM -> subestado de RECARGA
    #     }
    # Sítios: 0x8003f190 (sub 1 = mira/hold, 0x8003ef08) · 0x8003fd90 (sub 8 = mira de corpo
    # inteiro, 0x8003fb78) · 0x8004029c (0x8003ffd8) · 0x8004070c (0x800402f4).
    # `0x8006cf0c(a0 = 0)` é CONSULTA de munição (`exe_items.md §144`): devolve **-1** quando
    # `0x8006cc8c` não acha o item de munição no inventário e **0** quando acha (com a0 = 0 ele
    # não consolida nada; o `beqz` de 0x8006cf84 sai com v0 = 0). Logo o ramo do SE é
    # exatamente "pediu recarga e NÃO TEM BALA" — o clique seco.
    # Sanidade: A_01 (a FACA) é o único banco de arma que NÃO define o id 1, e faca não recarrega.
    "arma_vazia": dict(cat=1, id=1, conf="MEDIA", prova=(
        "MEDIDO: os 4 sítios de cat 1 / id 1 (0x8003f190, 0x8003fd90, 0x8004029c, 0x8004070c) "
        "são o mesmo idioma: sob `*(gs+0x2108) & 0x40` (pedido de recarga), o SE só sai no ramo "
        "em que `0x8006cf0c(0)` devolve -1 = a munição NÃO está no inventário; no ramo em que "
        "devolve 0 o código vai para o subestado de RECARGA (player+6 = 4 / 10) e NÃO pede SE. "
        "Ou seja é o som de 'sem bala'. O NOME 'clique seco' é DECLARADO")),
}

# O som da RECARGA não é um id fixo: são EVENTOS POR QUADRO da animação de recarga
# (`seq 7` do banco 2 do `.PLW`). Ver `eventos_de_arma()`.

# Banco padrão de cada `cat` quando o port não sabe qual está carregado.
# C_00 é o banco de MENU (mesma tabela de SE que C_01) — é o certo para som de UI.
BANCO_PADRAO = {0: "C_00", 1: "A_01", 2: "R000", 4: "S1_DOOR00"}

# Banco de JOGO por cat, para os ids que não existem no banco padrão:
#   cat 0 -> C_02: MEDIDO. O room-loader 0x800493ec chama 0x8007809c(0, 2) para a Jill
#            (0x800495d0; a1 = 8 quando *(gs+0x784e) >= 8). É banco de PERSONAGEM.
#   cat 1 -> A_02: DECLARADO. O banco de cat 1 é o da ARMA (A_{w}, w = player+0x46) e o
#            padrão A_01 é a FACA — que não define o id 0 (o estouro). A_02 é o primeiro
#            banco de arma de fogo; o de-para item -> w continua NÃO MEDIDO.
BANCO_JOGO = {0: "C_02", 1: "A_02"}


# ─────────────────────────────── parsing ───────────────────────────────
def sound_dir():
    return paths.cd_data("SOUND")


def bancos_disponiveis(d=None):
    """[(nome, caminho_header, caminho_corpo)] de todos os bancos do disco."""
    d = d or sound_dir()
    out = []
    for f in sorted(os.listdir(d)):
        if not f.endswith((".VH", ".SND")):
            continue
        nome = f.rsplit(".", 1)[0]
        corpo = os.path.join(d, CORPO_ESPECIAL.get(nome, nome + ".VB"))
        if os.path.isfile(corpo):
            out.append((nome, os.path.join(d, f), corpo))
    return out


def parse_header(vh, vb_len, inicio=0, limite=None, n_se=None):
    """Acha o header VAB pelo magic e devolve os campos + a base da tabela de SE.

    `inicio`/`limite` delimitam a busca do magic (nos bancos embutidos o arquivo inteiro
    tem falso-positivo em potencial). `n_se` = quantos ids o `cat` daquele banco tem
    (`N_SE_POR_CAT`); sem ele vale a regra dos arquivos do disco, em que a tabela começa no
    offset 0 e portanto `n_se = hdr/4`.
    """
    fim = len(vh) if limite is None else limite
    i, versao = -1, 0
    for m in MAGICS_VAB:
        j = vh.find(struct.pack("<I", m), inicio, fim)
        if j >= 0 and (i < 0 or j < i):
            i, versao = j, m >> 16
    if i < 0:
        raise ValueError("magic 0x000{1,2}eeee (header VAB) ausente")
    hdr = i - 0x10
    if hdr < 0:
        raise ValueError("magic do header VAB em offset impossível (%d)" % i)
    n = hdr // 4 if n_se is None else n_se
    base_se = hdr - n * 4                    # 0x80078384..0x80078390 (ver N_SE_POR_CAT)
    if base_se < 0:
        raise ValueError("tabela de SE de %d ids não cabe antes do header (%#x)" % (n, hdr))
    vb_size = struct.unpack_from("<I", vh, hdr)[0]
    total, off_vagtab = struct.unpack_from("<2I", vh, hdr + 4)
    n_tons, n_vags = struct.unpack_from("<2H", vh, hdr + 0x14)
    return {
        "hdr": hdr, "n_se": n, "base_se": base_se,
        "versao": versao, "tam_header": tam_header(versao),
        "vb_size": vb_size, "vb_size_ok": vb_size == vb_len,
        "total": total, "off_vagtab": off_vagtab,
        "n_tons": n_tons, "n_vags": n_vags,
        "vol_mestre": vh[hdr + 0x18], "pan_mestre": vh[hdr + 0x19],
    }


def tons_do_header(vh, h):
    """Tons `VagAtr` lidos por OFFSET (`hdr + tam_header`, `n_tons` x 32 B).

    `vab.parse_tones` acha os tons pelo marcador `c0 00 c1 00 c2 00 c3 00` em
    `reserved[4]`. Isso funciona nos `.VH`/`.SND` do disco, mas **falha nos bancos
    embutidos nos `DOOR*.DO1`**: lá alguns tons não têm o marcador, e o resto do arquivo
    (modelo/textura) pode conter bytes parecidos. Como o layout do header está provado
    (35/35 + 76/76), ler por offset é determinístico e mais rigoroso.
    """
    out = []
    for i in range(h["n_tons"]):
        t = h["hdr"] + h["tam_header"] + i * 32
        a = vh[t:t + 8]
        adsr1, adsr2, prog, vg = struct.unpack_from("<4H", vh, t + 16)
        out.append({
            "prior": a[0], "mode": a[1], "vol": a[2], "pan": a[3],
            "center": a[4], "shift": a[5], "min": a[6], "max": a[7],
            "adsr1": adsr1, "adsr2": adsr2, "prog": prog, "vag": vg,
        })
    return out


def vagtab_do_header(vh, h):
    """Tabela VAG lida por OFFSET (`hdr + u32@hdr+0x08`, `n_vags+1` entradas u16)."""
    off = h["hdr"] + h["off_vagtab"]
    return list(struct.unpack_from("<%dH" % (h["n_vags"] + 1), vh, off))


def decodifica_descritor(desc):
    """Campos do descritor de SE (u32). Só os campos PROVADOS ganham nome."""
    b0, b1, b2, b3 = desc & 0xFF, (desc >> 8) & 0xFF, (desc >> 16) & 0xFF, (desc >> 24) & 0xFF
    return {
        "desc": "0x%08x" % desc,
        "banco": (b0 & 0x0E) >> 1,          # 0x80074770 / 0x800747d8
        "tom": b1 >> 4,                      # 0x80074cd0 (índice * 32 = sizeof VagAtr)
        "voz_dinamica": bool(b2 & 0x80),     # 0x800749e8
        "voz_base": b2 & 0x1F,               # 0x800749f8
        "flag_b3": b3 & 1,                   # 0x80074a08
        "nao_provado": {"b1_lo": b1 & 0x0F, "b3_hi": b3 >> 1},
    }


def parse_banco(nome, ph, pc):
    """Tabela de SE + tons + amostras de um banco (par de arquivos `.VH`+`.VB`)."""
    return parse_bytes(nome, open(ph, "rb").read(), os.path.getsize(pc),
                       os.path.basename(ph), os.path.basename(pc))


def parse_bytes(nome, vh, vb_len, arq="", corpo="", inicio=0, limite=None, n_se=None,
                banco_esperado=None, taxa_dos_tons=False):
    """Núcleo do parse: `vh` = bytes do header, `vb_len` = tamanho do corpo PS-ADPCM.

    Serve para o par `.VH`+`.VB` do disco, para o banco **embutido** nos `DOOR*.DO1`
    (§porta) e para o banco **embutido no RDT** dos `R???.ARD` (§sala).

    `banco_esperado` = o `cat` do próprio arquivo. Quando dado, descritores que citam
    OUTRO banco são marcados `banco_externo` e **não** recebem `wav`: o índice de tom
    deles vale no array de tons do outro banco, que não é este arquivo. Isso acontece em
    **25 dos 2209** descritores das salas (R30C -> banco 6, R50D -> banco 5, R509 -> 3) e
    em **0** dos 278 do disco.
    """
    h = parse_header(vh, vb_len, inicio=inicio, limite=limite, n_se=n_se)
    tons = tons_do_header(vh, h)
    vagtab = vagtab_do_header(vh, h)
    se = {}
    for i in range(h["n_se"]):
        d = struct.unpack_from("<I", vh, h["base_se"] + i * 4)[0]
        if d == 0xFFFFFFFF:
            continue
        info = decodifica_descritor(d)
        if banco_esperado is not None and info["banco"] != banco_esperado:
            info["banco_externo"] = (
                "descritor cita o banco %d, não o %d deste arquivo — o índice de tom vale "
                "no array de tons do banco %d (carregado em outro cat)"
                % (info["banco"], banco_esperado, info["banco"]))
            se[i] = info
            continue
        it = info["tom"]
        if it >= len(tons):
            # Acontece em **12 dos 159** descritores dos bancos de porta e em NENHUM dos
            # 278 dos bancos do disco. Motivo medido: a tabela de SE das portas é um
            # TEMPLATE — os ids 0 e 1 são byte-idênticos (`0x00601408`, `0x00612408`) nas
            # 76 portas, mas 12 portas têm só 2 tons, e aí o id 1 (que aponta o tom 2)
            # fica pendurado. É inconsistência do dado original, não do formato: marcamos
            # e seguimos, em vez de inventar outro layout de campo para forçar o encaixe.
            info["invalido"] = "tom %d >= n_tons %d (entrada sobrando do template)" % (it, len(tons))
            se[i] = info
            continue
        tom = tons[it]
        vg = tom["vag"]
        info["vag"] = vg
        info["dummy"] = vg == VAG_DUMMY      # aponta o bloco mudo -> placeholder silencioso
        info["wav"] = None if info["dummy"] else "%s/%s_%02d.wav" % (nome, nome, vg - 2)
        info["taxa_hz"] = vab.tone_rate(tom["center"], tom["shift"], tom["min"])
        info["tom_vol"] = tom["vol"]
        info["tom_pan"] = tom["pan"]
        if 1 <= vg < len(vagtab):
            info["vb_bytes"] = (vagtab[vg] - vagtab[vg - 1]) * 8
        se[i] = info
    # Taxa por VAG: vem do TOM que aponta aquela amostra. Nos bancos do disco/porta só os
    # vags citados por um descritor têm taxa conhecida (o resto sai a 22050, comportamento
    # histórico que os 147 WAV de porta já publicados assumem). Nos bancos de SALA a maioria
    # dos vags não é citada por descritor nenhum, então lá a taxa vem direto dos tons
    # (`taxa_dos_tons=True`) — senão 3 de cada 4 amostras sairiam com pitch errado.
    taxa = {}
    if taxa_dos_tons:
        for t in tons:
            taxa.setdefault(t["vag"], vab.tone_rate(t["center"], t["shift"], t["min"]))
    taxa.update({v["vag"]: v["taxa_hz"] for v in se.values() if "vag" in v})
    bancos_citados = sorted({v["banco"] for v in se.values()})
    return {
        "arquivo": arq, "corpo": corpo,
        "banco": (banco_esperado if banco_esperado is not None
                  else (min(bancos_citados) if bancos_citados else None)),
        "bancos_citados": bancos_citados,
        "versao_header": h["versao"], "tam_header": h["tam_header"],
        "n_se": h["n_se"], "n_tons": len(tons), "n_vags": len(vagtab) - 1,
        "vb_bytes": vb_len, "vol_mestre": h["vol_mestre"], "pan_mestre": h["pan_mestre"],
        "se": se, "_hdr": h, "_vagtab": vagtab, "_tons": tons,
        "_taxa_por_vag": taxa,
    }


# ───────────────────────── bancos de PORTA (`DOOR*.DO1`) ─────────────────────────
# Achado desta rodada: **todo `STAGE*/DOOR??.DO1` embute um banco VAB completo** com o
# mesmo magic `0x0001eeee`. É o "DOOR SOUND" que o loader `0x80012818` carrega (a string
# de depuração está em `0x800103ac` e é passada em `a3` por `0x80016534`).
#
# Layout do banco embutido — provado em **76/76** arquivos:
#     [tabela de SE: 4 x u32] [header VAB @0x10] [tons @0x40] [tabela VAG] [corpo PS-ADPCM]
#     corpo começa em `hdr + u32@hdr+0x04` (fim do bloco do header) e tem `u32@hdr+0x00` bytes
# Todos usam **banco 4** no descritor → **`cat 4` é o banco de PORTA**.
DOOR_GLOB = os.path.join("STAGE*", "DOOR*.DO1")


def bancos_porta():
    """[(nome, caminho)] dos bancos de som de porta."""
    import glob
    out = []
    for p in sorted(glob.glob(paths.cd_data(DOOR_GLOB))):
        stage = os.path.basename(os.path.dirname(p))          # STAGE1..STAGE7
        porta = os.path.splitext(os.path.basename(p))[0]       # DOOR00..
        out.append(("S%s_%s" % (stage[-1], porta), p))
    return out


def parse_porta(nome, caminho):
    """Banco VAB embutido num `.DO1`. Devolve (info, bytes_do_corpo)."""
    b = open(caminho, "rb").read()
    i = b.find(struct.pack("<I", MAGIC_VAB))
    if i < 0:
        raise ValueError("%s: sem magic 0x0001eeee" % caminho)
    hdr = i - 0x10
    vb_size, total = struct.unpack_from("<2I", b, hdr)
    base = hdr + total                                   # corpo logo após o bloco do header
    if base + vb_size > len(b):
        raise ValueError("%s: corpo não cabe (base %#x + %d > %d)" % (caminho, base, vb_size, len(b)))
    info = parse_bytes(nome, b, vb_size, os.path.basename(caminho), "(embutido)",
                       n_se=N_SE_POR_CAT[4], banco_esperado=None)
    info["vb_offset"] = base
    return info, b[base:base + vb_size]


# ─────────────────────── bancos de SALA (`R???.ARD`, `cat 2`) ───────────────────────
# **Todo `STAGE*/R???.ARD` embute o banco de som da SALA** (`cat 2`, 48 ids). Três peças,
# provadas em 169/169 (a §11.4 tinha as duas primeiras; a TERCEIRA é o achado desta rodada):
#
#  1. **Corpo PS-ADPCM = o sub-bloco 9 do contêiner** (tipo `0x02`, variante `0x02`), que
#     `ARD.md §2` rotula `mask_extra`. Prova dupla: `len(bloco 9) == u32@hdr+0x00` (o
#     tamanho do `.VB` declarado no header VAB) em **169/169**, e com essa base **todo** VAG
#     da tabela termina num bloco com flag de fim — **1871/1871**.
#  2. **Header VAB no RDT**, achado pelo magic `0x000{1,2}eeee` em `hdr+0x10`, 8 a 28 bytes
#     depois de `offset_table[1]`.
#  3. **A tabela de SE é `hdr - 48*4` (= `hdr - 0xC0`), NÃO `offset_table[0]`.** É aritmética
#     do motor (`0x80078384`: `hdr = base + N*4`, `N = *(0x800a0fe4 + cat)` = 48 para cat 2).
#     A §11.4 dizia "off[0] = tabela de 48 ids" porque `off[1] - off[0] == 0xC0` em 169/169 —
#     mas `hdr = off[1] + pad` com `pad` de 8..28 B, então as duas janelas de 0xC0 são
#     DIFERENTES. Quem decide é a validação cruzada com o SCD: com a base `hdr-0xC0`, **as
#     9 salas que têm porta com `Key_Type == 0xfe` definem TODAS o SE id 38** (o id que
#     `0x80050dd8` pede justamente nesse caso) e nenhuma sala sem essa porta fica de fora;
#     com a base `off[0]` isso desanda (9 salas com a porta e SEM o id). Idem ids 22 e 37.
ARD_GLOB = os.path.join("STAGE*", "R???.ARD")
ARD_SETOR = 0x800                    # os sub-blocos do .ARD são alinhados ao setor de CD
ARD_BLOCO_RDT = 8                    # bloco tipo 0x00 = RDT (lógica da sala)
ARD_BLOCO_VB = 9                     # bloco tipo 0x02 = **corpo PS-ADPCM do banco da sala**
RDT_OFFTAB = 22                      # 22 ponteiros u32 em rdt+0x08
RDT_OFF_AUDIO = 1                    # offset_table[1] = onde procurar o header VAB
BUSCA_HDR = 0x40                     # janela de busca do magic depois de offset_table[1]


def bancos_sala():
    """[(nome, caminho)] dos 169 `R???.ARD`. O nome do banco é o id da sala (`R100`...)."""
    import glob
    return [(os.path.splitext(os.path.basename(p))[0], p)
            for p in sorted(glob.glob(paths.cd_data(ARD_GLOB)))]


def blocos_do_ard(dados):
    """[(offset, tamanho, tipo, variante)] dos sub-blocos do contêiner `.ARD`."""
    _total, n = struct.unpack_from("<2I", dados, 0)
    out, pos = [], ARD_SETOR
    for i in range(n):
        tam, fa, _fb = struct.unpack_from("<IHH", dados, 8 + i * 8)
        out.append((pos, tam, fa & 0xFF, (fa >> 8) & 0xFF))
        pos = (pos + tam + ARD_SETOR - 1) // ARD_SETOR * ARD_SETOR
    return out


def parse_sala(nome, caminho):
    """Banco VAB (`cat 2`) embutido num `.ARD`. Devolve (info, bytes_do_corpo)."""
    b = open(caminho, "rb").read()
    blocos = blocos_do_ard(b)
    if len(blocos) <= ARD_BLOCO_VB:
        raise ValueError("%s: só %d sub-blocos" % (caminho, len(blocos)))
    o_rdt, t_rdt, tipo_rdt, _v = blocos[ARD_BLOCO_RDT]
    if tipo_rdt != 0x00:
        raise ValueError("%s: bloco %d não é o RDT (tipo %#x)" % (caminho, ARD_BLOCO_RDT, tipo_rdt))
    rdt = b[o_rdt:o_rdt + t_rdt]
    off = list(struct.unpack_from("<%dI" % RDT_OFFTAB, rdt, 0x08))
    o_vb, t_vb, _t, _v = blocos[ARD_BLOCO_VB]
    ini = off[RDT_OFF_AUDIO]
    info = parse_bytes(nome, rdt, t_vb, os.path.basename(caminho), "sub-bloco %d" % ARD_BLOCO_VB,
                       inicio=ini, limite=min(ini + BUSCA_HDR + 0x14, len(rdt)),
                       n_se=N_SE_POR_CAT[2], banco_esperado=2, taxa_dos_tons=True)
    info["vb_offset"] = o_vb
    info["off_audio"] = ini
    info["alinhamento"] = info["_hdr"]["hdr"] - ini
    return info, b[o_vb:o_vb + t_vb]


# ───────── SE por QUADRO DE ANIMAÇÃO da ARMA (`cat 1`, dado do `.PLW`) ─────────
# Fecha o resíduo "o id do mecanismo da arma vem de RAM e NÃO é extraível do estático"
# (§12.1). Vem de RAM, sim — mas a RAM é um CURSOR para dado do disco:
#
#   0x8003f5b0  lw   $v0, 0xe4($s0)      ; player+0xe4
#   0x8003f5b8  lhu  $v0, ($v0)          ; u16 apontado
#   0x8003f5c0  andi $v0, $v0, 0xf000
#   0x8003f5c4  beqz $v0, ...            ; nibble 0 = quadro sem som
#   0x8003f5d0  srl  $v0, $v0, 0xc
#   0x8003f5d4  addiu $v0, $v0, -1       ; id = nibble - 1
#   0x8003f5d8  or   $a0, $v0, 0x10100   ; cat 1
#
# E quem escreve `player+0xe4` é o AVANÇADOR DE ANIMAÇÃO: `0x8001ae04`/`0x8001ae20`
# (caminhando a lista de quadros pelo bit `0x100` de cada u16) e `0x80026ca8`/`0x80026cc0`
# (dentro de `0x80026be8`, que os subestados da arma chamam com `a1 = gs+0x2618` e
# `a2 = gs+0x2614` = o **banco 2 do `.PLW` da arma equipada**, ver `recuo_tiro.md §2`).
#
# Ou seja **`player+0xe4` aponta para a FRAME-LIST do EDD**, e o nibble alto de cada quadro é
# um EVENTO DE SOM por quadro — exatamente a forma que `sfx.md`/§11.2 suspeitava. A frame-list
# é `2 bytes por quadro` com "pose no byte baixo + flags no alto" (`pld2gltf.parse_edd`).
#
# Prova cruzada, byte a byte: **31 dos 31** ids de evento das 20 armas reais estão definidos no
# `A_{w}.VH` daquela arma (o único "furo" é `w = 0`, que não tem banco `A_00` no disco). E o
# `w = 1` (FACA) usa só o id **7**, dentro do conjunto `{6..10}` que é o único que o `A_01`
# define — a mesma peça que provou o estouro em `cat 1 / id 0` (§11.1).
PLW_GLOB = os.path.join("PLD", "PL00W*.PLW")
PLW_OSSOS_BANCO2 = 9        # o banco 2 (tronco/braços, o da mira) tem 9 ossos — plw.md §9.4
SEQ_RECARGA = 7             # `player+0xc8 = 0x00070007` no subestado 4 (recuo_tiro.md §linha 110)
SE_ARMA_VAZIA = 1           # `cat 1 / id 1`: ver ACOES["arma_vazia"]


def eventos_de_arma():
    """{w: {plw, banco, eventos: [{seq, quadro, id}]}} — os SE por quadro de cada arma."""
    import glob
    import find_anim_banks as fab
    out = {}
    for p in sorted(glob.glob(paths.cd_data(PLW_GLOB))):
        nome = os.path.splitext(os.path.basename(p))[0]        # PL00W02
        w = int(nome[-2:], 16)
        b = open(p, "rb").read()
        _ents, bancos = fab.all_banks(b)
        cands = [k for k in bancos if k["nb"] == PLW_OSSOS_BANCO2]
        if not cands:
            continue
        bk = cands[0]
        edd, nseq = bk["edd"], bk["nseq"]
        ev = []
        for s in range(nseq):
            n_quadros = struct.unpack_from("<H", b, edd + s * 8)[0]
            off = struct.unpack_from("<H", b, edd + s * 8 + 2)[0]
            for q in range(n_quadros):
                nib = struct.unpack_from("<H", b, edd + off + q * 2)[0] >> 12
                if nib:
                    ev.append({"seq": s, "quadro": q, "id": nib - 1})
        out[w] = {"plw": os.path.basename(p), "banco": "A_%02X" % w,
                  "n_seq": nseq, "eventos": ev}
    return out


# ───────────────── qual banco de porta cada SALA/PORTA usa (MEDIDO) ─────────────────
# O índice do arquivo `DOORxx` é **campo estático do SCD**: é o `Dtex_Type` do
# `SCE_DOOR_AOT_SET`, em `descriptor+0xc` (= opcode `0x61`+0x1a / `0x62`+0x22).
#
# Prova (disassembly): o loader de SOM de porta `0x8001644c` faz
#     dtex  = lbu *(*(gs+0x2154) + 0xc)                 # 0x8001647c / 0x80016490
#     rec   = 0x800971e4 + dtex*12                      # 0x80016498..0x800164b0
#     fid   = lhu *( *(0x800979d4 + stage*4) + dtex*2 ) # 0x800164e4..0x80016510
#     lba   = 0x800946a4 + fid*8                        # 0x80016518
#     jal 0x80012818(a3 = "DOOR SOUND" 0x800103ac)      # 0x80016544
# e depois `0x8007836c(a0 = 4, a1 = 0x801fc100)` — que é o **cat 4** do motor de SE, com
# `SND_CTX+0x74 = 4` (`0x80016598`). O loader de TEXTURA (`0x80016208`, a3 = "DOOR TEXTURE")
# usa o MESMO `dtex` e o mesmo par de tabelas, só com o offset `rec+4` dentro do arquivo.
#
# `0x800979d4` = 7 ponteiros (1 por stage) para arrays de **76 u16** (fileid), contíguos em
# `0x800975b4..0x8009793c` (passo 0x98 = 76*2) — casa 1:1 com os 76 `DOORxx` de cada STAGE.
#
# E os 76 `DOORxx.DOn` são **byte-idênticos nos 7 stages** (medido, 76/76): o banco de som de
# porta depende SÓ do índice `xx`. Por isso o nome `S1_DOORxx` do `re3_se.json` serve para
# qualquer stage — o prefixo é histórico, não semântico. A instalação de PC confirma: lá os
# bancos são arquivos soltos `DATA/SOUND/D_00.VH`..`D_4D.VH`, um por índice, sem stage.
DOOR_TEX_TYPE = 0xC                  # offset do Dtex_Type DENTRO do descriptor
EXE_DOOR_FILEID_PTRS = 0x800979D4    # 7 ponteiros u32 (1 por exe-stage)
EXE_DOOR_REC = 0x800971E4            # registro de 12 B por dtex
N_DOOR = 76                          # DOOR00..DOOR4B


def banco_de_dtex(dtex):
    """Nome do banco no `re3_se.json` para um índice de porta (`Dtex_Type`)."""
    return "S1_DOOR%02X" % dtex


def portas_por_sala():
    """{sala: [{aot, sce, dtex, banco, ...}]} — o banco de porta de cada porta de cada sala.

    Reusa o extrator de portas já validado (`tools/scd_door_dest.py`, 453/453 destinos) só
    para varrer o SCD; o campo novo é o `dtex`.
    """
    import glob
    import scd_door_dest as sdd
    name2si, _si2name = sdd.room_index_map()
    salas = {}
    for f in sorted(glob.glob(paths.cd_data("STAGE*", "R*.ARD"))):
        nome = os.path.splitext(os.path.basename(f))[0]
        if nome not in name2si:
            continue
        rdt = sdd.rdt_of(open(f, "rb").read())
        so = sdd.script_off(rdt)
        nf = struct.unpack_from("<H", rdt, so)[0] // 2
        foffs = list(struct.unpack_from("<%dH" % nf, rdt, so))
        achadas = []
        for fi in range(nf):
            pc = so + foffs[fi]
            end = so + foffs[fi + 1] if fi + 1 < nf else len(rdt)
            guard = 0
            while pc < end and pc + 1 < len(rdt) and guard < 8000:
                guard += 1
                op = rdt[pc]
                if op == 0x01:
                    break
                sz = sdd.VM_SIZES.get(op)
                if sz is None:
                    break
                if op in sdd.DOOR_OPCODES and pc + sz <= len(rdt) and rdt[pc + 2] in sdd.DOOR_SCE:
                    b = bytes(rdt[pc:pc + sz])
                    d = 2 + sdd.DOOR_PATH[op]
                    dtex = b[d + DOOR_TEX_TYPE]
                    achadas.append({
                        "aot": b[1], "sce": b[2], "opcode": op, "dtex": dtex,
                        "banco": banco_de_dtex(dtex),
                        "door_type": b[d + 0xD],      # SCE_DOOR_AOT_SET.Door_Type
                        "knock": b[d + 0xE],          # Knock_Type: escolhe o par de SE de cat 2
                        "key_id": b[d + 0xF],
                        "key_type": b[d + 0x10],      # 0xfe = emperrada, 0xff = nunca abre
                    })
                pc += sz
        salas[nome] = achadas
    return salas


def _exe_bytes():
    """(bytes do .text, endereço virtual da base) do `SLUS_009.23` (header PS-EXE = 0x800)."""
    with open(paths.extracted("SLUS_009.23"), "rb") as f:
        d = f.read()
    assert d[:8] == b"PS-X EXE", "nao e PS-X EXE"
    return d[0x800:], struct.unpack_from("<I", d, 0x18)[0]


def tabela_fileid_porta():
    """{stage(0..6): [fileid u16 ...]} lida de `0x800979d4` no EXE.

    Os 7 arrays são CONTÍGUOS: o fim de um é o começo do próximo, e o do stage 6 termina
    exatamente na tabela de ponteiros. Daí sai o tamanho de cada um — 76 entradas em 6 dos 7
    stages e **72** no stage 5 (`R6xx`, Mercenaries), que só usa até o índice 41.
    """
    text, base = _exe_bytes()
    ptrs = [struct.unpack_from("<I", text, EXE_DOOR_FILEID_PTRS - base + s * 4)[0]
            for s in range(7)]
    fim = ptrs[1:] + [EXE_DOOR_FILEID_PTRS]
    out = {}
    for s, (p, q) in enumerate(zip(ptrs, fim)):
        out[s] = list(struct.unpack_from("<%dH" % ((q - p) // 2), text, p - base))
    return out


def gerar_portas_salas():
    """Escreve `<out>/data/porta_banco.json` (sala -> banco de som de cada porta)."""
    salas = portas_por_sala()
    fid = tabela_fileid_porta()
    n = sum(len(v) for v in salas.values())
    usados = sorted({p["dtex"] for v in salas.values() for p in v})
    dados = {
        "_meta": {
            "descricao": "Banco de som de PORTA (cat 4) por sala/porta do RE3 PS1. Gerado "
                         "por tools/exe_audio.py --portas-salas.",
            "PROVA": "dtex = SCE_DOOR_AOT_SET.Dtex_Type = descriptor+0xc (opcode 0x61 +0x1a, "
                     "0x62 +0x22). O loader de som de porta 0x8001644c lê exatamente esse "
                     "byte (0x8001647c) e indexa 0x800979d4[stage] (76 u16 de fileid) e "
                     "0x800971e4 + dtex*12, carregando com a string 'DOOR SOUND' "
                     "(0x800103ac) e abrindo o VAB como cat 4 (0x8007836c com a0=4).",
            "STAGE_IRRELEVANTE": "os 76 STAGE*/DOORxx.DOn são byte-idênticos nos 7 stages "
                                 "(medido 76/76) -> o banco depende só de dtex. O prefixo "
                                 "'S1_' dos nomes em re3_se.json é histórico.",
            "chave": "salas[<sala>] = lista de portas na ordem em que o SCD as registra; "
                     "'aot' é o id do AOT (byte +1 do opcode), que é como o motor as indexa.",
            "portas": n, "dtex_usados": len(usados),
        },
        "dtex_para_banco": {str(i): banco_de_dtex(i) for i in range(N_DOOR)},
        "fileid_por_stage": {str(k): v for k, v in fid.items()},
        "salas": salas,
    }
    out = paths.data("porta_banco.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    print("%s  (%d portas em %d salas, %d indices de porta usados)"
          % (out, n, sum(1 for v in salas.values() if v), len(usados)))
    return dados


def coletar(portas=False, salas=False):
    d = {n: parse_banco(n, ph, pc) for n, ph, pc in bancos_disponiveis()}
    if portas:
        for n, p in bancos_porta():
            try:
                d[n] = parse_porta(n, p)[0]
            except ValueError as ex:
                print("  aviso: %s" % ex)
    if salas:
        for n, p in bancos_sala():
            try:
                d[n] = parse_sala(n, p)[0]
            except (ValueError, struct.error) as ex:
                print("  aviso: %s" % ex)
    return d


def _escrever_wav(caminho, pcm, taxa):
    import wave
    with wave.open(caminho, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(taxa)
        w.writeframes(struct.pack("<%dh" % len(pcm), *pcm))


def extrair_salas():
    """Escreve os WAV dos 169 bancos de SALA em `<out>/assets/SOUND/SFX/<sala>/`.

    Critério de aceite (medido, ver `--verificar`): **169 salas, 1702 amostras**. Nenhuma
    sala falha — a §11.4 dizia que `R11B` não tinha header VAB e isso estava ERRADO: ela
    tem, é versão 2, e o que ela quebra é só a regra `u32@hdr+0x08 == tam_header + 32*n_tons`
    (960 em vez de 928, um slot de tom sobrando). Como a tabela VAG é lida pelo OFFSET
    `hdr+u32@hdr+0x08`, isso não afeta a extração.
    """
    n_wav = n_sala = 0
    falhas = []
    for nome, p in bancos_sala():
        try:
            info, corpo = parse_sala(nome, p)
        except (ValueError, struct.error) as ex:
            falhas.append("%s: %s" % (nome, ex))
            continue
        vagtab = info["_vagtab"]
        outdir = paths.assets("SOUND", "SFX", nome)
        os.makedirs(outdir, exist_ok=True)
        for k in range(2, len(vagtab)):                  # VAG#1 = bloco mudo, descartado
            a, z = vagtab[k - 1] * 8, vagtab[k] * 8
            if z <= a:
                continue
            pcm = vab.decode_adpcm(corpo, a, z)
            _escrever_wav(os.path.join(outdir, "%s_%02d.wav" % (nome, k - 2)),
                          pcm, info["_taxa_por_vag"].get(k, 22050))
            n_wav += 1
        n_sala += 1
    print("salas: %d bancos, %d WAV -> %s" % (n_sala, n_wav, paths.assets("SOUND", "SFX")))
    for f in falhas:
        print("  FALHA %s" % f)
    return n_sala, n_wav


def extrair_portas():
    """Escreve os WAV dos bancos de porta em `<out>/assets/SOUND/SFX/<banco>/`."""
    n_wav = 0
    for nome, p in bancos_porta():
        info, corpo = parse_porta(nome, p)
        vagtab = info["_vagtab"]
        outdir = paths.assets("SOUND", "SFX", nome)
        os.makedirs(outdir, exist_ok=True)
        for k in range(2, len(vagtab)):                  # VAG#1 = bloco mudo, descartado
            a, z = vagtab[k - 1] * 8, vagtab[k] * 8
            pcm = vab.decode_adpcm(corpo, a, z)
            _escrever_wav(os.path.join(outdir, "%s_%02d.wav" % (nome, k - 2)),
                          pcm, info["_taxa_por_vag"].get(k, 22050))
            n_wav += 1
    print("portas: %d WAV -> %s" % (n_wav, paths.assets("SOUND", "SFX")))
    return n_wav


# ─────────────────────────────── saída ───────────────────────────────
META = {
    "descricao": "De-para PROVADO id de SE -> amostra do RE3 PS1 (SLUS_009.23). "
                 "Gerado por tools/exe_audio.py. Ver docs/decomp/notes/exe_audio.md.",
    "exe": "SLUS_009.23 (NTSC-U), base 0x80010000",
    "enderecos_provados": {
        "SE_pede": "0x800746c0  (a0 = (b2<<16)|(cat<<8)|idx; a1 = ptr 16B; a2; a3)",
        "anel_pedidos": "0x800e0de4 (24 x 32B), ponteiro de escrita 0x800e10e4",
        "tabela_handler": "0x800a1130 -> {0x80074770 (cat<5), 0x80074820 (cat>=5)}",
        "consumidor": "0x800744e0",
        "resolve": "0x80074770  desc = *( *(0x800e0610 + cat*4) + idx*4 ); -1 = descarta",
        "busca_banco": "0x800750e4  (8 slots de 8B em 0x800e0664; mesma fn p/ cat e p/ banco)",
        "voz_setup": "0x800749a0",
        "vol_pan": "0x80075b90  (div por 63; pan centro 0x40)",
        "SpuSetVoiceAttr": "0x8007f768 (mask=3 via 0x80075120)",
        "SpuSetKey": "0x8007eda8 (KON/KOFF em +0x188/+0x18a e +0x18c/+0x18e)",
        "SpuGetAllKeysStatus": "0x8007f518 (status por voz em 0x800e116c)",
        "regs_SPU": "*(0x800a1250) = 0x1f801c00",
    },
    "formato_banco": {
        "tabela_se": "N x u32 terminando em `hdr` (base = hdr - N*4); 0xffffffff = id nao usado. "
                     "N = *(0x800a0fe4 + cat) = {0:16, 1:32, 2:48, 3:32, 4:4}, lido em "
                     "0x80078390 dentro de 0x8007836c. Nos arquivos do disco a tabela comeca "
                     "no offset 0, logo hdr == N*4; nos bancos EMBUTIDOS (porta/sala) nao.",
        "magic_header_vab": "0x0001eeee (versao 1) ou 0x0002eeee (versao 2) em hdr+0x10. "
                            "O u16 ALTO e' a VERSAO e ela decide o tamanho do header: "
                            "tons = hdr + 0x20 + versao*0x10 (0x30 ou 0x40) — PROVADO em "
                            "0x800783a4..0x800783b0 (`lhu 0x12(hdr)`, `sll 4`, `addu`).",
        "campos": "hdr+0x00 |.VB| (35/35 ok) | hdr+0x08 off tabela VAG | "
                  "hdr+0x12 VERSAO | hdr+0x14 n_tons (35/35 ok) | hdr+0x16 n_vags | "
                  "hdr+0x18/+0x19 vol/pan mestre | hdr+0x20+versao*0x10 tons (32B, VagAtr)",
        "descritor": "byte0 bits1-3 = banco VAB; byte1 bits4-7 = indice do TOM; "
                     "byte2 bit7 = voz dinamica; byte2 bits0-4 = voz base; byte3 bit0 = flag. "
                     "byte1 bits0-3 e byte3 bits1-7 NAO PROVADOS",
        "amostra": "tom.vag (1-based); VAG#1 = bloco mudo descartado -> wav = <banco>_{vag-2:02d}",
    },
    "cat": {"0": "C_xx (personagem/UI/global)",
            "1": "A_xx da ARMA equipada (0x80043eb4 -> 0x8007809c(1, lbu player+0x46); A_{w:02X}, w=1 = faca)",
            "2": "banco da SALA: R000.SND no disco (tabela toda 0xffffffff) + os 169 EMBUTIDOS "
                 "nos R???.ARD (nome do banco = id da sala). 48 ids.",
            "3": "banco do INIMIGO (32 ids) — de qual arquivo vem NAO LOCALIZADO",
            "4": "porta (4 ids), embutido no DOORxx.DOn",
            "nota": "cat == id de banco VAB (mesma fn de busca 0x800750e4 para os dois)"},
    "CORRECOES": [
        "docs/decomp/notes/exe_audio.md §11.4 dizia que a tabela de SE da sala ficava em "
        "offset_table[0] do RDT. NAO fica: fica em `hdr - 48*4`, e `hdr = offset_table[1] + "
        "pad` com pad de 8..28 B (medido em 169/169) — as duas janelas de 0xC0 diferem. Base "
        "certa provada por 0x80078384 (hdr = base + N*4) e corroborada pelo SCD: com "
        "`hdr-0xC0` as 9 salas com porta Key_Type==0xfe definem TODAS o SE id 38.",
        "docs/decomp/notes/exe_audio.md §11.4 dizia 'header VAB achado em 168/169 (R11B "
        "falha)'. Achado em 169/169. R11B tem header versao 2; o que ela quebra e' so a regra "
        "u32@hdr+0x08 == tam_header + 32*n_tons (960 vs 928 = um slot de tom sobrando), o que "
        "nao afeta nada porque a tabela VAG e' lida pelo offset.",
        "docs/formatos/ARD.md §2 rotula o sub-bloco 9 (tipo 0x02) de 'mask_extra' / 'payload "
        "extra de mascara'. E' o CORPO PS-ADPCM do banco de som da sala: len(bloco 9) == "
        "u32@hdr+0x00 em 169/169 e todos os 1871 VAG terminam em flag de fim com essa base.",
        "docs/decomp/notes/sfx.md §8 dizia que os opcodes SCD 0x57/0x58/0x59 eram filas de "
        "SE. NAO SAO: 0x80038678/0x80038704/0x8003879c alimentam as duas filas de RUMBLE "
        "(0x800de648 motor pequeno on/off, 0x800de798 motor grande com rampa linear). O tick "
        "0x800389a0 gera nivel = acc>>7 e o resultado vai para 0x800c79c8 (2 bytes), passado "
        "a PadSetAct pelo stub 0x80091710 (a1=0x800c79c8, a2=2). Slot de 10B: +0 ativo, "
        "+1 nivel, +2 atraso, +4 duracao, +6 passo, +8 acumulador<<7.",
        "docs/decomp/notes/menus.md §8.2 lia 0x800746c0 como enqueue de SPRITE de GPU. E' o "
        "enqueue de SE: a cadeia termina em SpuSetVoiceAttr/SpuSetKey (ver enderecos acima). "
        "menu_comandos.md:66 e menu_mapa.md:657/916, que diziam 'SFX', estavam CERTOS.",
        "docs/decomp/notes/sfx.md §8.3 concluia que NAO existia link estatico id->vag. "
        "Existe: a tabela mora no inicio do .VH/.SND. O que e' runtime e' so QUAL banco "
        "esta carregado em cada cat.",
        "docs/decomp/notes/exe_combat.md diz que 0x800776b0 'seleciona seco/tiro/vazio pelos "
        "bits 0x200/0x400 de (player+0xe4)'. NAO PROVADO: nao existe nenhum `andi 0x200/0x400` "
        "nem leitura de +0xe4 em 0x800776b0..0x80077b84. O que a rotina faz e' pedir um SE de "
        "cat 2 (SALA) com idx = base + a0, base em {0x17, 0x1a, (retorno de 0x80077b84)&0x7f} "
        "ou 0x2d, e a0 in {0,1} — e chamar 0x8001b484 (spawn de efeito/modelo, tabela "
        "0x800ba728) 10 vezes. Compativel com IMPACTO/ricochete de sala, nao com o estouro "
        "da arma.",
    ],
}


def gerar():
    bancos = coletar(portas=True, salas=True)
    dados = {"_meta": META, "acoes": {}, "banco_padrao": BANCO_PADRAO,
             "banco_jogo": BANCO_JOGO, "bancos": {}}

    for nome, b in sorted(bancos.items()):
        dados["bancos"][nome] = {
            "arquivo": b["arquivo"], "corpo": b["corpo"], "banco": b["banco"],
            "versao_header": b["versao_header"],
            "n_se": b["n_se"], "n_tons": b["n_tons"], "n_vags": b["n_vags"],
            "vb_bytes": b["vb_bytes"],
            "se": {str(i): {k: v for k, v in info.items() if k != "nao_provado"}
                   for i, info in sorted(b["se"].items())},
        }

    for acao, a in ACOES.items():
        cat, sid = a["cat"], a["id"]
        # resolve em CADA banco daquele cat (o mesmo id toca amostras diferentes por área)
        por_banco = {}
        for nome, b in sorted(bancos.items()):
            if b["banco"] != cat:
                continue
            info = b["se"].get(sid)
            if (info and not info.get("dummy", True)
                    and "invalido" not in info and "banco_externo" not in info):
                por_banco[nome] = info["wav"]
        # 1ª escolha: o banco padrão do cat. Se o id não existir lá (caso do tiro, que só
        # vive nos bancos de área), cai no BANCO_JOGO — declarado, não medido.
        padrao = BANCO_PADRAO.get(cat)
        origem = padrao if padrao in por_banco else BANCO_JOGO.get(cat)
        if origem not in por_banco:
            origem = None
        dados["acoes"][acao] = {
            "cat": cat, "id": sid, "confianca": a["conf"], "prova": a["prova"],
            "wav_padrao": por_banco.get(origem),
            "banco_padrao": origem,
            "banco_declarado": origem is not None and origem != padrao,
            "por_banco": por_banco,
        }

    # ── SE por QUADRO da animação da arma (mecanismo/recarga) ──
    ev = eventos_de_arma()
    n_ev = 0
    for w, e in sorted(ev.items()):
        b = bancos.get(e["banco"])
        se = b["se"] if b else {}
        for it in e["eventos"]:
            info = se.get(it["id"]) if se else None
            it["wav"] = info["wav"] if info and not info.get("dummy", True) else None
            it["no_banco"] = info is not None
            n_ev += 1
    dados["eventos_arma"] = {
        "_meta": {
            "descricao": "SE de MECANISMO da arma (cat 1) por QUADRO de animação. O id NÃO é "
                         "fixo: 0x8003f5b0 lê `u16 @ *(player+0xe4)` e faz id = (u16>>12)-1, e "
                         "`player+0xe4` é o CURSOR da frame-list do EDD do banco 2 do .PLW da "
                         "arma (escrito por 0x8001ae04/0x8001ae20 e 0x80026ca8/0x80026cc0, "
                         "dentro de 0x80026be8, que os subestados chamam com gs+0x2614/+0x2618 "
                         "= banco 2). Logo o id É extraível do disco.",
            "PROVA_CRUZADA": "31 dos 31 ids de evento das 20 armas reais estão definidos no "
                             "A_{w}.VH daquela arma; o w=0 (desarmado) não tem banco A_00. E o "
                             "w=1 (FACA) usa só o id 7, dentro do {6..10} que é o único "
                             "conjunto que o A_01 define.",
            "seq_recarga": SEQ_RECARGA,
            "seq_tiro": [1, 3, 5],
            "nota_seq": "seq 7 = RECARGA (player+0xc8 = 0x00070007 no subestado 4, "
                        "recuo_tiro.md); seq 1/3/5 = as 3 variantes de FOGO. Os rótulos das "
                        "outras seqs do banco 2 não foram medidos.",
            "n_eventos": n_ev,
        },
        "por_arma": {str(w): ev[w] for w in sorted(ev)},
    }

    out = paths.data("re3_se.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1)
    print("%s  (%d bancos, %d acoes, %d eventos de arma)" % (out, len(bancos), len(ACOES), n_ev))

    # sfx_map.json: nome lógico -> wav, agora com origem provada (substitui a heurística)
    mapa = {
        "_meta": {
            "descricao": "Nome logico -> WAV de SFX, relativo a assets/SOUND/SFX/. "
                         "Gerado por tools/exe_audio.py a partir da tabela de SE do .VH "
                         "(PROVADA). Substitui a versao antiga, escolhida por heuristica "
                         "de duracao (que estava ERRADA: menu_move apontava C_00_01).",
            "confianca": "ALTA nos 5 sons de menu; DECLARADO no resto (ver re3_se.json.acoes)",
            "banco_global": "C_00/C_01 = banco de MENU; C_02..C_0D = banco de area do jogador",
        },
        "sfx": {a: d["wav_padrao"] for a, d in sorted(dados["acoes"].items())
                if d["wav_padrao"]},
    }
    out2 = paths.data("sfx_map.json")
    with open(out2, "w", encoding="utf-8") as f:
        json.dump(mapa, f, ensure_ascii=False, indent=1)
    print("%s  (%d nomes)" % (out2, len(mapa["sfx"])))
    return dados


# ─────────────────────────────── verificação ───────────────────────────────
def verificar():
    """Re-roda todas as asserções que sustentam o de-para. Devolve (n_ok, n_falha)."""
    ok = falha = 0

    def chk(cond, msg):
        nonlocal ok, falha
        if cond:
            ok += 1
        else:
            falha += 1
            print("  [FALHA] %s" % msg)
        return cond

    bancos = bancos_disponiveis()
    chk(len(bancos) == 35, "esperados 35 bancos, achei %d" % len(bancos))

    n_desc = 0
    for nome, ph, pc in bancos:
        vh = open(ph, "rb").read()
        vb_len = os.path.getsize(pc)
        h = parse_header(vh, vb_len)
        chk(h["vb_size_ok"],
            "%s: hdr+0x00 (%d) != |.VB| (%d)" % (nome, h["vb_size"], vb_len))
        # nos bancos do disco os dois caminhos (marcador vs offset) tem de CONCORDAR —
        # e' o que valida ler por offset nos DOOR*.DO1, onde o marcador nao serve
        tons_sig = vab.parse_tones(vh)
        chk(h["n_tons"] == len(tons_sig),
            "%s: hdr+0x14 (%d) != tons achados pelo marcador (%d)" % (nome, h["n_tons"], len(tons_sig)))
        tons = tons_do_header(vh, h)
        chk(tons == tons_sig, "%s: tons por offset != tons por marcador" % nome)
        chk(h["versao"] == 1, "%s: banco do disco deveria ser header versao 1, e' %d"
            % (nome, h["versao"]))
        chk(h["base_se"] == 0, "%s: tabela de SE do disco deveria comecar no offset 0" % nome)
        chk(h["tam_header"] + 32 * len(tons) == h["off_vagtab"],
            "%s: tons nao terminam onde hdr+0x08 aponta a tabela VAG" % nome)
        vagtab = vagtab_do_header(vh, h)
        chk(vagtab == vab.find_vagtab(vh, vb_len),
            "%s: tabela VAG por offset != por varredura" % nome)
        chk(vagtab[0] == 0 and vagtab[-1] * 8 == vb_len,
            "%s: tabela VAG nao vai de 0 a |.VB|/8" % nome)
        bks = set()
        for i in range(h["n_se"]):
            d = struct.unpack_from("<I", vh, i * 4)[0]
            if d == 0xFFFFFFFF:
                continue
            n_desc += 1
            info = decodifica_descritor(d)
            bks.add(info["banco"])
            chk(info["tom"] < len(tons),
                "%s id %d: tom %d >= n_tons %d" % (nome, i, info["tom"], len(tons)))
            vg = tons[info["tom"]]["vag"]
            chk(1 <= vg <= len(vagtab) - 1,
                "%s id %d: vag %d fora da tabela VAG" % (nome, i, vg))
        chk(len(bks) <= 1,
            "%s: descritores citam bancos diferentes (%s)" % (nome, sorted(bks)))

    chk(n_desc == 278, "esperados 278 descritores usados, achei %d" % n_desc)

    # o de-para dos 5 sons de menu, banco C_00 (tabela identica em C_01)
    esperado = {4: (5, 4, "C_00_02"), 5: (6, 5, "C_00_03"), 6: (7, 6, "C_00_04"),
                7: (8, 2, "C_00_00"), 9: (12, 3, "C_00_01")}
    b = parse_banco("C_00", os.path.join(sound_dir(), "C_00.VH"),
                    os.path.join(sound_dir(), "C_00.VB"))
    for sid, (tom, vg, wav) in esperado.items():
        info = b["se"].get(sid)
        chk(info is not None and info["tom"] == tom and info["vag"] == vg
            and info["wav"] == "C_00/%s.wav" % wav,
            "C_00 id %d: esperado tom %d vag %d %s, obtido %s" % (sid, tom, vg, wav, info))

    # Os ids de UI têm o MESMO descritor em 13 dos 14 bancos C_ (o som de UI é global).
    # `C_0C` é a ÚNICA exceção: não define o id 4 e usa outros tons nos ids 5/6/7
    # (0x0fe3a400/0x0fe3b400/0x0fe39400). Isso é medida, não suposição.
    UI_COMUM = {4: 0x3FE05300, 5: 0x3FE06300, 6: 0x3FE07300, 7: 0x3FE08300}
    for sid, esp in sorted(UI_COMUM.items()):
        iguais = []
        for nome, ph, pc in bancos:
            if not nome.startswith("C_"):
                continue
            if struct.unpack_from("<I", open(ph, "rb").read(), sid * 4)[0] == esp:
                iguais.append(nome)
        chk(len(iguais) == 13 and "C_0C" not in iguais,
            "id %d de UI: esperado o mesmo descritor em 13 bancos C_ (menos C_0C), "
            "obtido %s" % (sid, iguais))

    # Cruzamento independente com sfx.md §9.1: as 5 amostras que aquele estudo achou
    # BYTE-IDÊNTICAS nos 13 bancos C_ são os WAV de índice 00..04 — e são exatamente
    # as 5 dos sons de UI. Dois caminhos independentes, mesmo resultado.
    ui_wavs = sorted(b["se"][s]["wav"] for s in (4, 5, 6, 7, 9))
    chk(ui_wavs == ["C_00/C_00_%02d.wav" % i for i in range(5)],
        "os 5 sons de UI deviam ser os WAV 00..04 de C_00, obtido %s" % ui_wavs)

    # ── bancos de PORTA embutidos nos DOOR*.DO1 ──
    portas = bancos_porta()
    chk(len(portas) == 76, "esperados 76 DOOR*.DO1, achei %d" % len(portas))
    n_porta = 0
    for nome, p in portas:
        try:
            info, corpo = parse_porta(nome, p)
        except ValueError as ex:
            chk(False, str(ex))
            continue
        n_porta += 1
        tab = info["_vagtab"]
        chk(tab[0] == 0 and tab[-1] * 8 == len(corpo),
            "%s: tabela VAG não fecha com o corpo (%d vs %d)" % (nome, tab[-1] * 8, len(corpo)))
        # cada VAG tem de terminar num bloco com flag de fim (bit0) — prova de que a base
        # do corpo (hdr + total) está certa
        for k in range(1, len(tab)):
            chk(corpo[tab[k] * 8 - 16 + 1] & 0x01,
                "%s: VAG %d não termina em flag de fim" % (nome, k))
        chk(info["n_se"] == 4, "%s: esperadas 4 entradas de SE, achei %d" % (nome, info["n_se"]))
        chk(info["banco"] == 4, "%s: banco deveria ser 4 (porta), achei %s" % (nome, info["banco"]))
    chk(n_porta == 76, "76 bancos de porta parseados, achei %d" % n_porta)

    # o id 0 (som principal da porta) existe e e' VALIDO nas 76; e a tabela e' template
    padroes = set()
    n_desc_porta = n_inval = 0
    for nome, p in portas:
        info = parse_porta(nome, p)[0]
        vh = open(p, "rb").read()
        padroes.add(tuple(struct.unpack_from("<4I", vh, 0)))
        n_desc_porta += len(info["se"])
        n_inval += sum(1 for v in info["se"].values() if "invalido" in v)
        chk(0 in info["se"] and "invalido" not in info["se"][0],
            "%s: id 0 (som principal) deveria ser valido" % nome)
    chk(len(padroes) == 3,
        "esperados 3 padroes distintos de tabela SE nas portas, achei %d" % len(padroes))
    chk(all(pd[0] == 0x00601408 and pd[1] == 0x00612408 for pd in padroes),
        "os ids 0 e 1 das portas deveriam ser identicos nas 76 (template)")
    chk((n_desc_porta, n_inval) == (159, 12),
        "portas: esperados 159 descritores com 12 invalidos, achei %d com %d"
        % (n_desc_porta, n_inval))

    # ── o banco de porta NÃO depende do stage: os 76 DOORxx sao byte-identicos nos 7 ──
    import hashlib

    def sha_arquivo(p):
        h = hashlib.sha1()
        with open(p, "rb") as f:                     # em blocos: a maquina do dono e' apertada
            for pedaco in iter(lambda: f.read(1 << 16), b""):
                h.update(pedaco)
        return h.hexdigest()

    for xx in range(N_DOOR):
        shas = set()
        for st in range(1, 8):
            p = paths.cd_data("STAGE%d" % st, "DOOR%02X.DO%d" % (xx, st))
            shas.add(sha_arquivo(p) if os.path.isfile(p) else "(falta %s)" % p)
        chk(len(shas) == 1,
            "DOOR%02X difere entre os 7 stages (%d conteudos distintos)" % (xx, len(shas)))

    # ── dtex (Dtex_Type) de TODAS as portas do jogo cai na faixa dos 76 DOORxx ──
    salas = portas_por_sala()
    n_p = sum(len(v) for v in salas.values())
    chk(n_p == 453, "esperadas 453 portas (sce in {1,13}), achei %d" % n_p)
    fora = [(s, p["aot"], p["dtex"]) for s, v in salas.items() for p in v
            if not 0 <= p["dtex"] < N_DOOR]
    chk(not fora, "dtex fora de 0..%d em %s" % (N_DOOR - 1, fora[:5]))
    for s, v in salas.items():
        for p in v:
            chk(banco_de_dtex(p["dtex"]) in dict(portas),
                "%s aot %d: banco %s nao existe" % (s, p["aot"], p["banco"]))

    # ── e a tabela do EXE que o loader usa: 1 array de fileids CONTIGUOS por stage ──
    fid = tabela_fileid_porta()
    chk(len(fid) == 7, "esperados 7 arrays de fileid de porta, achei %d" % len(fid))
    usa = {}
    for s, v in salas.items():
        usa.setdefault(int(s[1]) - 1, set()).update(p["dtex"] for p in v)
    for s, arr in sorted(fid.items()):
        chk(len(arr) in (72, N_DOOR) and all(a > 0 for a in arr),
            "stage %d: array de fileid de porta invalido (%d entradas)" % (s, len(arr)))
        chk(arr == list(range(arr[0], arr[0] + len(arr))),
            "stage %d: fileids de porta deviam ser contiguos (%s...)" % (s, arr[:4]))
        chk(max(usa.get(s, {0})) < len(arr),
            "stage %d: usa dtex %d mas o array tem so %d entradas"
            % (s, max(usa.get(s, {0})), len(arr)))

    # ── N de ids de SE por cat: a tabela `0x800a0fe4` do EXE (a base de tudo acima) ──
    text_exe, base_exe = _exe_bytes()
    tab_n = list(text_exe[EXE_N_SE_POR_CAT - base_exe:EXE_N_SE_POR_CAT - base_exe + 8])
    chk(tab_n == [16, 32, 48, 32, 4, 0, 0, 0],
        "0x800a0fe4 (N de ids de SE por cat) deveria ser [16,32,48,32,4,0,0,0], e' %s" % tab_n)
    for cat, n in sorted(N_SE_POR_CAT.items()):
        chk(tab_n[cat] == n, "cat %d: N_SE_POR_CAT diz %d, o EXE diz %d" % (cat, n, tab_n[cat]))

    # ── bancos de SALA embutidos nos R???.ARD (§13) ──
    salas_ard = bancos_sala()
    chk(len(salas_ard) == 169, "esperados 169 R???.ARD, achei %d" % len(salas_ard))
    n_sala = n_vag_sala = n_fim = n_desc_sala = n_ext = n_inv_sala = n_mudo = 0
    n_vag0 = []
    vers = {1: 0, 2: 0}
    pads = set()
    regra_hdr = []
    id_por_sala = {}
    for nome, p in salas_ard:
        dados_ard = open(p, "rb").read()
        blocos = blocos_do_ard(dados_ard)
        chk(len(blocos) == 10, "%s: esperados 10 sub-blocos, achei %d" % (nome, len(blocos)))
        chk(blocos[ARD_BLOCO_VB][2] == 0x02 and blocos[ARD_BLOCO_VB][3] == 0x02,
            "%s: sub-bloco %d deveria ser tipo 0x02 variante 0x02" % (nome, ARD_BLOCO_VB))
        try:
            info, corpo = parse_sala(nome, p)
        except (ValueError, struct.error) as ex:
            chk(False, "%s: %s" % (nome, ex))
            continue
        n_sala += 1
        h = info["_hdr"]
        vers[h["versao"]] = vers.get(h["versao"], 0) + 1
        pads.add(info["alinhamento"])
        # (1) o CORPO e' o sub-bloco 9: o tamanho declarado no header VAB casa com ele
        chk(h["vb_size"] == len(corpo),
            "%s: hdr+0x00 (%d) != |sub-bloco 9| (%d)" % (nome, h["vb_size"], len(corpo)))
        # (2) e com essa base TODO VAG termina num bloco com flag de fim (bit0)
        tabv = info["_vagtab"]
        chk(tabv[0] == 0 and tabv[-1] * 8 == len(corpo),
            "%s: tabela VAG nao vai de 0 a |corpo|/8" % nome)
        for k in range(1, len(tabv)):
            if tabv[k] <= tabv[k - 1]:
                continue
            n_vag_sala += 1
            if corpo[tabv[k] * 8 - 16 + 1] & 0x01:
                n_fim += 1
            else:
                chk(False, "%s: VAG %d nao termina em flag de fim" % (nome, k))
        # (3) o VAG#1 e' o bloco mudo de 48 B (3 blocos), como nos bancos do disco
        chk(tabv[1] * 8 == 48, "%s: VAG#1 (mudo) deveria ter 48 B, tem %d" % (nome, tabv[1] * 8))
        # (4) tabela de SE de 48 ids terminando exatamente no header
        chk(h["n_se"] == 48 and h["base_se"] == h["hdr"] - 0xC0,
            "%s: tabela de SE deveria ser 48 ids em hdr-0xC0" % nome)
        # (5) a janela off[1]-off[0] tambem mede 0xC0 (o que confundiu a §11.4), mas fica
        #     `alinhamento` bytes ANTES da tabela de verdade
        rdt_off = struct.unpack_from("<%dI" % RDT_OFFTAB, dados_ard,
                                     blocos[ARD_BLOCO_RDT][0] + 0x08)
        chk(rdt_off[1] - rdt_off[0] == 0xC0,
            "%s: offset_table[1]-[0] deveria medir 0xC0" % nome)
        chk(8 <= info["alinhamento"] <= 28,
            "%s: alinhamento hdr-off[1] fora de 8..28 (%d)" % (nome, info["alinhamento"]))
        # (6) a regra do tamanho do header (0x20 + versao*0x10)
        if h["tam_header"] + 32 * h["n_tons"] != h["off_vagtab"]:
            regra_hdr.append(nome)
        ids_usados = set()
        for i, v in info["se"].items():
            n_desc_sala += 1
            ids_usados.add(i)
            if "banco_externo" in v:
                n_ext += 1
            elif "invalido" in v:
                n_inv_sala += 1
            else:
                chk(v["banco"] == 2, "%s id %d: banco %d != 2" % (nome, i, v["banco"]))
                if v["vag"] == 0:
                    # 1 caso em 2209: R11B id 5 (tom 13). É a MESMA sala do slot de tom
                    # sobrando; nenhuma outra sala tem `vag == 0`. Dado inconsistente.
                    n_vag0.append((nome, i))
                else:
                    chk(1 <= v["vag"] <= info["n_vags"],
                        "%s id %d: vag %d fora da tabela" % (nome, i, v["vag"]))
                if v["dummy"]:
                    n_mudo += 1
        id_por_sala[nome] = ids_usados
    chk(n_sala == 169, "169 bancos de sala parseados, achei %d" % n_sala)
    chk((vers.get(1), vers.get(2)) == (94, 75),
        "esperadas 94 salas com header versao 1 e 75 com versao 2, achei %s" % vers)
    chk(pads == {8, 12, 16, 20, 24, 28},
        "alinhamentos hdr-off[1] observados deviam ser {8,12,16,20,24,28}, sao %s" % sorted(pads))
    chk(n_vag_sala == 1871 and n_fim == 1871,
        "esperados 1871 VAG nas salas, todos terminando em flag de fim; achei %d/%d"
        % (n_fim, n_vag_sala))
    chk(regra_hdr == ["R11B"],
        "a regra hdr+0x08 == tam_header + 32*n_tons deveria falhar SO na R11B; falha em %s"
        % regra_hdr)
    chk(n_desc_sala == 2209,
        "esperados 2209 descritores usados nas salas, achei %d" % n_desc_sala)
    chk(n_ext == 25,
        "esperados 25 descritores de sala citando OUTRO banco (R30C/R50D/R509), achei %d" % n_ext)
    chk(n_inv_sala == 1,
        "esperado 1 descritor de sala com tom fora da faixa (R708 id 24), achei %d" % n_inv_sala)
    # 56 descritores apontam o VAG#1 (bloco mudo do SPU): são PLACEHOLDERS silenciosos —
    # o motor toca, o waveform é silêncio. É o mesmo fenômeno dos bancos do disco (§4.2).
    chk(n_mudo == 56,
        "esperados 56 descritores de sala apontando o VAG mudo, achei %d" % n_mudo)
    chk(n_vag0 == [("R11B", 5)],
        "so a R11B id 5 deveria ter vag 0 (a mesma sala do slot de tom sobrando); achei %s"
        % n_vag0)

    # ── VALIDAÇÃO CRUZADA COM O SCD: é ela que prova a BASE da tabela (hdr-0xC0) ──
    # `0x80050dd8` pede `cat 2 / id 38` quando `Key_Type == 0xfe`. Se a base estiver certa,
    # TODA sala que registra uma porta com `Key_Type == 0xfe` define o id 38 no seu banco.
    # (Com a base `off[0]` da §11.4, 9 dessas salas NÃO definem o id — foi assim que o erro
    # apareceu.) Idem para o id 22 (`Key_Type == 0xff` / sem a chave) e o 37 (com a chave).
    portas_sala = portas_por_sala()
    faltando = []
    n_fe = 0
    for s, v in sorted(portas_sala.items()):
        if any(p["key_type"] == 0xFE for p in v):
            n_fe += 1
            if 38 not in id_por_sala.get(s, set()):
                faltando.append(s)
    chk(n_fe == 9, "esperadas 9 salas com porta Key_Type==0xfe, achei %d" % n_fe)
    chk(not faltando,
        "salas com porta Key_Type==0xfe SEM o SE id 38 no banco: %s (base da tabela errada?)"
        % faltando)
    com_ff = [s for s, v in sorted(portas_sala.items())
              if any(p["key_type"] == 0xFF for p in v)]
    sem22 = [s for s in com_ff if 22 not in id_por_sala.get(s, set())]
    chk(len(com_ff) == 8, "esperadas 8 salas com porta Key_Type==0xff, achei %d" % len(com_ff))
    chk(sem22 == ["R20B"],
        "das 8 salas com porta Key_Type==0xff, so a R20B nao define o SE id 22 "
        "(a porta 'nunca abre' dela fica MUDA no original); achei %s" % sem22)
    # comparação honesta com a base ERRADA da §11.4: ela deixa 9 salas com porta 0xfe SEM o
    # id 38. É esta a medida que escolheu `hdr-0xC0` — fica no teste para não reincidir.
    sem38_off0 = 0
    for s, v in sorted(portas_sala.items()):
        if not any(p["key_type"] == 0xFE for p in v):
            continue
        cam = dict(bancos_sala()).get(s)
        if cam is None:
            continue
        dados_ard = open(cam, "rb").read()
        blocos = blocos_do_ard(dados_ard)
        o_rdt = blocos[ARD_BLOCO_RDT][0]
        off0 = struct.unpack_from("<I", dados_ard, o_rdt + 0x08)[0]
        d = struct.unpack_from("<I", dados_ard, o_rdt + off0 + 38 * 4)[0]
        if d == 0xFFFFFFFF:
            sem38_off0 += 1
    chk(sem38_off0 == 9,
        "com a base off[0] da §11.4, 9 das 9 salas com porta 0xfe ficam sem o id 38; achei %d"
        % sem38_off0)

    # ── SE por QUADRO da animação da arma (mecanismo/recarga) — §14 ──
    ev = eventos_de_arma()
    chk(len(ev) == 21, "esperados 21 PL00W*.PLW (w = 0..20), achei %d" % len(ev))
    bancos_arma = {n: parse_banco(n, ph, pc) for n, ph, pc in bancos_disponiveis()
                   if n.startswith("A_")}
    chk(len(bancos_arma) == 20, "esperados 20 bancos A_, achei %d" % len(bancos_arma))
    n_ev = n_ev_ok = 0
    ids_por_w = {}
    for w, e in sorted(ev.items()):
        ids = sorted({it["id"] for it in e["eventos"]})
        ids_por_w[w] = ids
        b = bancos_arma.get(e["banco"])
        for i in ids:
            n_ev += 1
            if b is None:
                chk(w == 0, "%s (w=%d) nao existe no disco e nao e' o w=0" % (e["banco"], w))
                continue
            if i in b["se"]:
                n_ev_ok += 1
            else:
                chk(False, "%s: evento de quadro pede o id %d, que o banco nao define (define %s)"
                    % (e["banco"], i, sorted(b["se"])))
    chk((n_ev, n_ev_ok) == (33, 31),
        "esperados 33 ids de evento (31 nas 20 armas reais + 2 do w=0 sem banco), achei %d/%d"
        % (n_ev, n_ev_ok))
    chk(ids_por_w.get(1) == [7],
        "a FACA (w=1) deveria usar so o id 7 nos eventos de quadro, usa %s" % ids_por_w.get(1))
    chk(7 in bancos_arma["A_01"]["se"] and 0 not in bancos_arma["A_01"]["se"],
        "A_01 define o id 7 (o evento da facada) e NAO define o id 0 (o estouro)")
    # a RECARGA: os eventos da seq 7 são o som dela; as armas que recarregam têm evento lá
    com_recarga = sorted(w for w, e in ev.items()
                         if any(it["seq"] == SEQ_RECARGA for it in e["eventos"]))
    chk(com_recarga == [0, 2, 3, 4, 5, 13, 14, 16, 17, 18, 19],
        "armas com evento de som na seq %d (RECARGA): %s" % (SEQ_RECARGA, com_recarga))
    # ARMA VAZIA (clique seco) = cat 1 / id 1, e a FACA é a única que não o define
    sem_id1 = sorted(n for n, b in bancos_arma.items() if 1 not in b["se"])
    chk(sem_id1 == ["A_01", "A_0B"],
        "os unicos bancos de arma sem o id 1 (arma vazia) deveriam ser A_01 (a FACA, que nao "
        "recarrega) e A_0B (que tambem nao tem evento de quadro nenhum); sem: %s" % sem_id1)

    # ── os 155 call sites de SE_pede (§12 do doc) ──
    tab = tabela_callsites()
    chk(len(tab) == 155, "esperava 155 `jal 0x800746c0`, achei %d" % len(tab))
    chk(all(r["fn"] is not None for r in tab), "todo call site tem funcao envolvente")
    chk(all(r["cat"] is not None or r["addr"] in A0_DINAMICO for r in tab),
        "todo sitio sem `cat` constante tem entrada em A0_DINAMICO")
    chk(all(r["idx"] is not None or r["idx_expr"] for r in tab),
        "todo sitio sem `idx` constante explica de onde o idx sai")
    chk(sum(1 for r in tab if r["cat"] == 1 and r["idx"] == 0) == 17,
        "o ESTOURO da arma (cat 1 / id 0) tem 17 sitios")
    chk(sum(1 for r in tab if r["cat"] == 0 and r["idx"] == 8) == 2,
        "o id 8 (virar pagina do ARQUIVO) tem exatamente 2 sitios, um por direcao")
    chk(sum(1 for r in tab if r["cat"] == 4) == 1,
        "cat 4 (porta) tem UM sitio no EXE inteiro")
    chk(sum(1 for r in tab if r["conf"] == "NAO_SEI") == 17,
        "17 sitios seguem sem evento identificado (se mudar, atualize o doc §12)")
    # cada acao nomeada com call site de cat/id constante tem de aparecer na tabela
    pares = set((r["cat"], r["idx"]) for r in tab)
    for nome, a in ACOES.items():
        if nome.startswith("porta_som"):
            continue                      # ids sem call site, declarados como tal
        chk((a["cat"], a["id"]) in pares,
            "a acao '%s' (cat %d / id %d) nao aparece em nenhum dos 155 sitios"
            % (nome, a["cat"], a["id"]))

    print("verificacao: %d ok, %d falha" % (ok, falha))
    return ok, falha


def tabela(nome):
    """Imprime a tabela de SE de um banco. Aceita banco do disco, `S?_DOORxx` e SALA (`R100`)."""
    b = None
    for n, p in bancos_sala():                       # sala (banco embutido no .ARD)
        if n == nome:
            b = parse_sala(n, p)[0]
            break
    if b is None:
        for n, p in bancos_porta():                  # porta (banco embutido no .DO1)
            if n == nome or n.endswith("_" + nome):
                b = parse_porta(n, p)[0]
                break
    if b is None:
        d = sound_dir()
        ph = os.path.join(d, nome + (".SND" if nome == "R000" else ".VH"))
        pc = os.path.join(d, CORPO_ESPECIAL.get(nome, nome + ".VB"))
        b = parse_banco(nome, ph, pc)
    print("%s: banco=%s n_se=%d n_tons=%d n_vags=%d |.VB|=%d header v%d (0x%x)"
          % (nome, b["banco"], b["n_se"], b["n_tons"], b["n_vags"], b["vb_bytes"],
             b["versao_header"], b["tam_header"]))
    print(" id  descritor  tom vag  Hz    voz          wav")
    for i, v in sorted(b["se"].items()):
        if "banco_externo" in v or "invalido" in v:
            print("%3d  %s %3d   -      -  -            (%s)"
                  % (i, v["desc"], v["tom"],
                     "banco %d, fora deste arquivo" % v["banco"] if "banco_externo" in v
                     else "tom invalido"))
            continue
        print("%3d  %s %3d %3d %6d  %-11s %s"
              % (i, v["desc"], v["tom"], v["vag"], v["taxa_hz"],
                 "dinamica" if v["voz_dinamica"] else "fixa/%d" % v["voz_base"],
                 v["wav"] or "(mudo)"))


SE_PEDE = 0x800746C0

# ═══════════════ Os 155 `jal 0x800746c0` — a tabela COMPLETA ═══════════════
# Por que ela existe: o anel `0x800e0de4` só é escrito por `0x800746c0` e só é lido/zerado
# por `0x800744e0` (§2 do doc), logo **todo** som do jogo passa por um destes 155 sítios.
# Fechar a lista de uma vez é o que evita perseguir som item a item.
#
# `conf` (o mesmo critério do resto do repo):
#   PROVADO   — o (cat, idx) E o evento saem da desmontagem, com endereço
#   DECLARADO — o (cat, idx) é medido; o NOME do evento é escolha nossa
#   NAO_SEI   — o (cat, idx) é medido e o evento não foi identificado
#
# `FN_ROTULO[fn] = (rótulo da função, evento padrão dos sítios dela, conf)`.
FN_ROTULO = {
    0x80016150: ("estado 2 da animação de PORTA (tabela 0x800979f0[2])",
                 "porta: transição (o único cat 4 do EXE)", "PROVADO"),
    0x8001C38C: ("tick de OBJETO do cenário", "objeto: SE empacotado em u8@obj+0x19", "PROVADO"),
    0x8001C49C: ("tick de OBJETO do cenário (2ª variante)",
                 "objeto: SE empacotado em u8@obj+0x19", "PROVADO"),
    0x8001C5BC: ("tick de OBJETO tipo 5/6 (u8@obj+1)",
                 "objeto: SE de sala com idx = u16@obj+0x22", "PROVADO"),
    0x8001D210: ("IA do inimigo tipo 21 (sub-rotina)", "inimigo t21: som de ação", "DECLARADO"),
    0x8001D7D0: ("IA do inimigo tipo 21 (exe_ai.md §linha 47, 2340 B)",
                 "inimigo t21: som de ação", "DECLARADO"),
    0x8001E0F4: ("IA do inimigo tipo 22 (exe_ai.md, 848 B)",
                 "inimigo t22: som de ação", "DECLARADO"),
    0x8001E444: ("IA do ZUMBI (tipo 23, exe_ai.md §2)", "zumbi: som de ação", "DECLARADO"),
    0x8002198C: ("função de ator alcançada por tabela", "", "NAO_SEI"),
    0x80023268: ("fluxo de jogo / task 0 (menu_pc_sys.md §linha 170)",
                 "abrir a tela de STATUS (id 6) / entrar no MAPA (id 9)", "PROVADO"),
    0x80024CE8: ("região de DRAW/ator (emd_skinning.md §linha 362)", "", "NAO_SEI"),
    0x80024F74: ("chamada por 0x80024ce8 (DRAW/ator)", "", "NAO_SEI"),
    0x800250CC: ("chamada por 0x80024ce8 (DRAW/ator)", "", "NAO_SEI"),
    0x8002FEE8: ("interpretador do stream de mensagem/cena (opcodes 0xEA..0xFE, "
                 "jump-table 0x80010508)",
                 "SE pedido pelo SCRIPT: cat 2, idx = próximo byte do stream", "PROVADO"),
    0x800303EC: ("desenhador de mensagem (menu_texto.md §linha 413)",
                 "caixa de mensagem: avançar (4) / fechar (5)", "DECLARADO"),
    0x80030764: ("desenhador de mensagem, 2ª variante",
                 "caixa de mensagem: avançar (4) / fechar (5)", "DECLARADO"),
    0x800366EC: ("chamada por 0x80036d5c/0x80036f10/0x80036f40", "", "NAO_SEI"),
    0x8003A7D8: ("rotina 7 = MÁQUINA DE MIRA/TIRO (exe_combat.md §1.3)",
                 "mira: fim do sub 2 / entrada no sub 3 (FOGO) — NÃO é o estouro", "NAO_SEI"),
    0x8003B1C4: ("macro-ação 9 = SUBIR/DESCER (port: script_vm/subir.gd)",
                 "subir: início do movimento", "PROVADO"),
    0x8003B244: ("macro-ação 9, animação (menu_bau.md §linha 267)",
                 "subir: impacto/aterrissagem", "DECLARADO"),
    0x8003CEA0: ("macro-ação 13, sub 0: anim 18 + contador gs+0x785e + SE do inimigo",
                 "player AGARRADO (voz) + mordida do inimigo (cat 3)", "DECLARADO"),
    0x8003D1A8: ("reação de DANO do player, sub 0 (anim 4)", "dano ao player", "PROVADO"),
    0x8003D2D8: ("reação de DANO do player (id 1 ou 2 por paridade de u8@player+5)",
                 "dano ao player (variante)", "PROVADO"),
    0x8003D4C0: ("reação de DANO do player (escritores de anim de hurt 0x8003d52c+)",
                 "dano ao player (variante)", "PROVADO"),
    0x8003D780: ("reação de DANO do player (escritores 0x8003d910/0x8003d990)",
                 "dano ao player (variante)", "PROVADO"),
    0x8003DA3C: ("reação de DANO do player (última função da região)",
                 "dano ao player (variante)", "PROVADO"),
    0x8003E4D0: ("handler da PISTOLA (exe_ai.md §linha 159; lê stats em 0x8009cf28)",
                 "arma: som de mecanismo", "DECLARADO"),
    0x8003EF08: ("subestado 1 da arma = hold/aim (recuo_tiro.md §linha 49)",
                 "arma: mecanismo do sub 1", "DECLARADO"),
    0x8003F520: ("subestado 4 da arma = **RECARGA** (recuo_tiro.md §linha 50)",
                 "RECARGA da arma", "PROVADO"),
    0x8003FB78: ("subestado 8 da arma (recuo_tiro.md §linha 51)",
                 "arma: mecanismo do sub 8", "DECLARADO"),
    0x8003FFD8: ("subestado de arma (2ª tabela)", "arma: mecanismo", "DECLARADO"),
    0x800402F4: ("subestado de arma (2ª tabela)", "arma: mecanismo", "DECLARADO"),
    0x80040764: ("subestado de arma (2ª tabela)", "arma: mecanismo (id dinâmico)", "DECLARADO"),
    0x80040900: ("subestado de arma (ids 18/19)", "", "NAO_SEI"),
    0x80040F34: ("handler da arma w=1 = FACA (0x8009ced8[0])",
                 "facada (A_01 define só os ids 6..10)", "DECLARADO"),
    0x80045094: ("chamada por 0x80038d34 (exe_combat.md §linha 268)", "", "NAO_SEI"),
    0x800452E8: ("vizinha de 0x80045094 (projétil)", "", "NAO_SEI"),
    0x80045950: ("colisão/integração de PROJÉTIL (0x80045094 -> 0x80045950 -> 0x80040d40)",
                 "impacto do projétil", "DECLARADO"),
    0x80048520: ("chamada por 0x8002378c, dentro do fluxo de jogo 0x80023268", "", "NAO_SEI"),
    0x80050D28: ("sce 1 = produtor de PORTA (jump-table de SCE 0x8009e0bc[1])",
                 "porta: trancada / destrancar / bloqueada", "PROVADO"),
    0x800514F0: ("driver da tela da CAIXA DE ITENS (sce 9 grava em gs+0x75e0)",
                 "baú: abrir", "DECLARADO"),
    0x800516A4: ("sce 11 (jump-table de SCE 0x8009e0bc[11]); testa flag 0x80078930 e "
                 "mostra a mensagem 0x72", "", "NAO_SEI"),
    0x80055038: ("handler do opcode SCD 0x77", "SE por script: cat/idx nos operandos",
                 "PROVADO"),
    0x8005518C: ("handler do opcode SCD 0x78",
                 "ambiente por script: cat = arg + 5, idx 0", "PROVADO"),
    0x80063850: ("tela de ARQUIVO — estado 8 (menu_pc_sys.md §6.1)",
                 "arquivo: virar página (8), cursor (4), sair (5)", "PROVADO"),
    0x80063CAC: ("tela de ARQUIVO — estado 9 (carrega FILEI.TIM)",
                 "arquivo: fechar a leitura", "DECLARADO"),
    0x8006446C: ("tela do BAÚ — sub 0 (tabela 0x8009f4e4[0])",
                 "baú: confirmar / cancelar / mover", "DECLARADO"),
    0x800646F0: ("tela do BAÚ — sub 1 (tabela 0x8009f4e4[1])",
                 "baú: transferir item (cat 2 / id 0x15)", "DECLARADO"),
    0x800650C4: ("tela do BAÚ — outro sub", "baú: cancelar", "DECLARADO"),
    0x80066604: ("GRADE do inventário — sub 0 (menu_pc_sys.md §6.2)",
                 "inventário: confirmar/vazio/MAPA/ARQ./sair/mover", "PROVADO"),
    0x80066920: ("lista de COMANDOS — sub 2 (menu_comandos.md §linha 34)",
                 "comandos: mover", "DECLARADO"),
    0x80066CA0: ("sub 5 = entrar no ARQUIVO (põe ctx+0x10 = 7)",
                 "arquivo: entrar / mover / cancelar", "DECLARADO"),
    0x800676B8: ("comando 0 = USE / EQUIP (menu_comandos.md §3)", "equipar/usar", "PROVADO"),
    0x80067C14: ("2º cursor da COMBINAÇÃO — sub 0xf (menu_comandos.md §linha 372)",
                 "combinar: mover / recusado / cancelar", "PROVADO"),
    0x80068024: ("executor genérico da COMBINAÇÃO (menu_comandos.md §5)",
                 "combinar: deu (6) / não combina (7)", "PROVADO"),
    0x80068A5C: ("espera de mensagem da combinação (sub 4)", "combinar: cancelar", "DECLARADO"),
    0x80068ABC: ("espera de resposta da combinação (sub 5)", "combinar: cancelar",
                 "DECLARADO"),
    0x80069280: ("comando 2 = CHECK / examinar (menu_comandos.md §6)",
                 "examinar item", "PROVADO"),
    0x80069C3C: ("janela de OBTER ITEM (exe_items.md §2.3)", "item pego", "PROVADO"),
    0x8006A234: ("sub 0xc = confirmação/mensagem (menu_pc_sys.md §linha 289)",
                 "confirmar / cancelar", "DECLARADO"),
    0x8006D948: ("braço 5 da tabela de init 0x8001100c (kind 5 = mensagem/mapa por item)",
                 "entrar em sub-tela (id 9)", "PROVADO"),
    0x8006F708: ("MAPA — sub 0 (tabela 0x800a0500[0], menu_mapa.md §linha 656)",
                 "mapa: navegar", "DECLARADO"),
    0x8006FC68: ("MAPA — sub 2 (tabela 0x800a0500[2])", "mapa: navegar/sair", "DECLARADO"),
    0x80070024: ("lógica do MAPA (ESP 5, menu_pc_sys.md §linha 262)", "mapa: sair",
                 "DECLARADO"),
    0x800775A0: ("helper: pede SE do INIMIGO (cat 3) com idx = argumento",
                 "inimigo: SE por id (cat 3)", "PROVADO"),
    0x80077618: ("helper: pede SE do INIMIGO (cat 3), 2ª variante",
                 "inimigo: SE por id (cat 3)", "PROVADO"),
    0x800776B0: ("SFX de tiro/impacto na SALA (exe_audio.md §6.4)",
                 "impacto/ricochete na sala (cat 2, idx variável)", "PROVADO"),
    0x80077ED4: ("chamada por 0x800495fc, dentro do room-loader 0x800493ec",
                 "entrada de sala / ambiente global", "DECLARADO"),
    0x80077F60: ("ligador de ambiente cat 5/6/7 (idx 0), sob os bits 1/2/4 de um byte de "
                 "estado", "", "NAO_SEI"),
}
# Os 17 handlers POR ARMA da tabela `0x8009ced8[w-1]` — todos pedem o ESTOURO (cat 1 / id 0).
for _fn in (0x80040F90, 0x800410F8, 0x80041594, 0x800418CC, 0x80041A80, 0x80041C34,
            0x80041DE8, 0x80041F9C, 0x800421F8, 0x80042474, 0x80042660, 0x800427D8,
            0x80042AE4, 0x80042E34, 0x80043328, 0x800434F8, 0x800439F8):
    FN_ROTULO[_fn] = ("handler POR ARMA (tabela 0x8009ced8, índice w-1)",
                      "ESTOURO da arma (cat 1 / id 0)", "PROVADO")

# Sítios com evento próprio (sobrepõe o da função).
SITE_EVENTO = {
    0x80023D10: ("abrir a tela de STATUS (id 6)", "PROVADO"),
    0x80023DB8: ("abrir a tela de STATUS (id 6, ctx+0x04 == 0) OU entrar no MAPA "
                 "(id 9, ctx+0x04 == 4)", "PROVADO"),
    0x8003AD6C: ("mira: sub 2 -> 3 (mexe em player+0x6e e no contador u16 0x800d1f96)",
                 "NAO_SEI"),
    0x8003B224: ("subir: início do movimento (grava +0xc8=6/+0xc9=0/+0xca=7 e vibra)",
                 "PROVADO"),
    0x8003B3E8: ("subir: impacto (sub 5 com +0xc9 == 1)", "DECLARADO"),
    0x8003CF10: ("player AGARRADO: voz (anim 18 + gs+0x785e++)", "DECLARADO"),
    0x8003D114: ("mordida do inimigo que agarrou (cat 3, id 3 ou 19 pelo tipo)", "DECLARADO"),
    0x8003F5E8: ("RECARGA da arma", "PROVADO"),
    0x80050DD8: ("porta: BLOQUEADA (Key_Type == 0xfe) + mensagem 0x11", "PROVADO"),
    0x80050E10: ("porta: TRANCADA para sempre (Key_Type == 0xff) + mensagem 0x12", "PROVADO"),
    0x80050E74: ("porta: DESTRANCAR com a chave", "PROVADO"),
    0x80050ED8: ("porta: TRANCADA — não tem a chave", "PROVADO"),
    0x80050F14: ("porta: TRANCADA — não tem a chave (2º ramo)", "PROVADO"),
    0x80051578: ("baú: abrir a caixa de itens", "DECLARADO"),
    0x800638F4: ("arquivo: confirmar já na última página (ctx+0xbd >= páginas-1) -> sub 4",
                 "PROVADO"),
    0x80063984: ("arquivo: VIRAR PÁGINA para trás (ctx+0xbd -= 1, ctx+0xc6 = 2)", "PROVADO"),
    0x80063A2C: ("arquivo: VIRAR PÁGINA para frente (ctx+0xbd += 1, ctx+0xc6 = -2)",
                 "PROVADO"),
    0x80063C20: ("arquivo: sair da leitura", "PROVADO"),
    0x80063E74: ("arquivo: fechar a tela (estado 9 -> 13)", "DECLARADO"),
    0x8006669C: ("inventário: confirmar em slot COM item", "PROVADO"),
    0x800666BC: ("inventário: confirmar em slot VAZIO", "PROVADO"),
    0x800666F0: ("inventário: botão MAPA (ctx+0x1c == -1 -> sub 4)", "PROVADO"),
    0x80066728: ("inventário: botão ARQ. (ctx+0x1c == -2 -> sub 5)", "PROVADO"),
    0x8006675C: ("inventário: FECHAR (cancelar ou botão SAIR)", "PROVADO"),
    0x8006688C: ("inventário: mover o cursor da grade", "PROVADO"),
    0x80067B40: ("equipar/usar: confirma e sai (comando 0)", "PROVADO"),
    0x800687B0: ("combinar: receita NÃO fecha", "PROVADO"),
    0x80068A10: ("combinar: DEU (7 predecessores, todos com a0 = 6)", "PROVADO"),
    0x80069454: ("examinar: entra no texto de exame", "PROVADO"),
    0x80069ED0: ("item PEGO (janela de obter)", "PROVADO"),
    0x80069FB0: ("item PEGO — a0 vem do delay slot do beq de 0x80069eb8 (a0 = 5)", "PROVADO"),
    0x800517D0: ("sce 11: a0 = 0x228 vem do delay slot do bnez de 0x8005175c", "NAO_SEI"),
    0x80077B50: ("impacto/ricochete de bala na sala (cat 2, idx = base + a0)", "PROVADO"),
    0x80064740: ("baú: cancelar", "DECLARADO"),
    0x80064AA4: ("baú: confirmar", "DECLARADO"),
    0x80064B2C: ("baú: transferir item (cat 2 / id 0x15)", "DECLARADO"),
    0x80064BC8: ("baú: transferir item (cat 2 / id 0x15)", "DECLARADO"),
    0x80064D1C: ("baú: transferir item (cat 2 / id 0x15)", "DECLARADO"),
    0x80064D90: ("baú: transferir item (cat 2 / id 0x15)", "DECLARADO"),
    0x80069470: ("examinar: sair do texto de exame", "DECLARADO"),
}
# Os 7 sítios de `arma: mecanismo` que moram DENTRO dos handlers por arma — o evento é o do
# sítio, não o da função (a função existe para o ESTOURO, mas este `jal` é o outro som).
for _s in (0x800414E0, 0x80041A14, 0x80041BC8, 0x80041D7C, 0x80041F30, 0x80043244,
           0x80043928):
    SITE_EVENTO[_s] = ("arma: som de mecanismo (id = nibble dos props em RAM)", "DECLARADO")

# Sítios em que o `a0` NÃO é imediato: `(cat, "idx", como_o_idx_sai)`.
# `cat = None` = nem o cat é constante.
A0_DINAMICO = {
    0x8001C3E0: (None, "u8@obj+0x19", "cat = byte >> 6, idx = byte & 0x3f (0x8001c3b0+)"),
    0x8001C440: (None, "u8@obj+0x19", "cat = byte >> 6, idx = byte & 0x3f (0x8001c410+)"),
    0x8001C578: (None, "u8@obj+0x19", "cat = byte >> 6, idx = byte & 0x3f (0x8001c548+)"),
    0x8001C838: (2, "u16@obj+0x22 + (rand & 1)", "objeto tipo 5 (u8@obj+1 == 5)"),
    0x8001C864: (2, "u16@obj+0x22", "objeto tipo 6 (u8@obj+1 == 6)"),
    0x8001DFEC: (1, "17", "`ori a0,a0,0x111` em 0x8001dfe0 com o `lui a0,1` fora da janela"),
    0x8001EC4C: (3, "8 ou 24", "s0 = 8 / 0x18 por `u8@+0x12f == u8@(*0x800cc858)+3`"),
    0x8001EDB8: (2, "14 ou 30", "s0 = 0xe / 0x1e pelo mesmo teste de tipo"),
    0x80030010: (2, "byte do stream", "`lbu a0,(s0)` + `ori a0,a0,0x200`; s0 = PC do script"),
    0x8003D114: (3, "3 ou 19", "v1 = 3 / 0x13 por `sltiu (u8@tipo - 1), 0x1e`"),
    0x8003D354: (0, "1 ou 2", "`(u8@player+5 & 1) + 1`"),
    0x8003F5E8: (1, "(u16@*(player+0xe4) >> 12) - 1",
                 "props da ARMA em RAM; `andi 0xf000` + `srl 12` + `-1` (0x8003f5b0+)"),
    0x8004082C: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma de 0x8003f5e8"),
    0x80040F78: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma (FACA: A_01 tem 6..10)"),
    0x800414E0: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma, após o hitscan"),
    0x80041A14: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80041BC8: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80041D7C: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80041F30: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80043244: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80043928: (1, "(u16@*(player+0xe4) >> 12) - 1", "mesmo idioma"),
    0x80055164: (None, "operandos do opcode 0x77",
                 "a0 = (arg<<16) | (a3<<8) | (a2 & 0xff) — cat E idx vêm do script"),
    0x800553D0: (None, "0", "a0 = (arg + 5) << 8 -> cat = arg + 5, idx 0 (opcode 0x78)"),
    0x80077600: (3, "a2 (+0x10 quando o tipo casa)", "helper de SE de inimigo"),
    0x80077698: (3, "a3 (+0x10 quando o tipo casa)", "helper de SE de inimigo"),
    0x80077B50: (2, "s5", "s5 = base + a0, base em {0x17, 0x1a, ret&0x7f} ou 0x2d (§6.4)"),
}

# Sítios cujo `a0` é constante mas vem do DELAY SLOT de um desvio para o bloco do `jal`
# (o back-walk linear pega a instrução do bloco vizinho, que não é o caminho executado).
# Cada um foi conferido enumerando TODOS os predecessores do bloco.
A0_POR_PREDECESSOR = {
    0x800517D0: (0x228, "único predecessor: `bnez v0, 0x800517b8` em 0x8005175c, delay slot "
                        "`addiu a0,zero,0x228`"),
    0x80068A10: (0x6, "7 predecessores do bloco 0x800689b0 (0x8006857c 0x800685c4 0x80068660 "
                      "0x800686a4 0x8006884c 0x8006892c 0x80068970) e TODOS com a0 = 6"),
    0x80069FB0: (0x5, "único predecessor: `beq v0,a1,0x80069f9c` em 0x80069eb8, delay slot "
                      "`addiu a0,zero,5`"),
}


def funcoes_do_exe(e):
    """Endereços de início de função: `addiu $sp,$sp,-N` = palavra 0x27BD8xxx..0x27BDFxxx.

    Mesmo critério do `exe_fn.Ana`, mas sem desmontar o `.text` inteiro (só compara a
    palavra), o que deixa isto rápido o suficiente para rodar dentro do `--verificar`.
    """
    out = []
    for o in range(0, len(e.text) - 4, 4):
        w = struct.unpack_from("<I", e.text, o)[0]
        if (w >> 16) == 0x27BD and (w & 0x8000):
            out.append(e.base + o)
    return out


def callsites():
    """Os `jal 0x800746c0` do EXE com `(cat, idx)` recuperado por back-walk do imediato.

    É a EVIDÊNCIA de duas coisas que o doc afirma:
      * `tiro_arma` (cat 1 / id 0) aparece ~20 vezes, uma por arma da tabela `0x8009ced8`;
      * **nenhuma** rotina de LOCOMOÇÃO do player pede SE — as 16 macro-ações do player estão
        na tabela `0x8009cda0` e as de andar/correr/ré/idle (índices 0..3 = `0x80039294`,
        `0x800397dc`, `0x80039b84`, `0x80039f08`) não contêm um único `jal 0x800746c0`.
        É o que sustenta o **NÃO PROVADO** do som de PASSO.

    Devolve [(addr, cat, idx, a0_bruto)]; `cat`/`idx` = None quando `a0` vem de registrador.
    Para a tabela completa (função envolvente, `a1`, evento e confiança) use
    `tabela_callsites()`.
    """
    return [(r["addr"], r["cat"], r["idx"], r["a0"]) for r in tabela_callsites()]


def _back(md, e, h, reg, n=28):
    """Última escrita CONSTANTE em `reg` na janela de `n` instruções antes de `h`.

    Varredura linear (não segue fluxo): é o que resolve 126 dos 155 sítios. Onde ela falha
    porque o valor vem do delay slot de um desvio, a resposta está em `A0_POR_PREDECESSOR`,
    conferida enumerando os predecessores do bloco. Devolve (valor, texto da instrução).
    """
    lo = h - n * 4
    val, lui, txt = None, None, ""
    for i in md.disasm(e.text[e.off(lo):e.off(h) + 8], lo):
        ops = [x.strip() for x in i.op_str.split(",")]
        if not ops or ops[0] != reg:
            continue
        txt = "%s %s" % (i.mnemonic, i.op_str)
        if i.mnemonic == "lui":
            lui = int(ops[1], 0) << 16
            val = lui
        elif i.mnemonic in ("ori", "addiu", "addi"):
            if ops[1] == "$zero":
                val = int(ops[2], 0) & 0xFFFF
            elif ops[1] == reg and lui is not None:
                val = lui | (int(ops[2], 0) & 0xFFFF)
            else:
                val = None
        elif i.mnemonic == "move" and len(ops) > 1 and ops[1] == "$zero":
            val = 0
        else:
            val = None
    return val, txt


def tabela_callsites():
    """A tabela COMPLETA dos 155 `jal 0x800746c0`, uma linha por sítio.

    Cada linha: endereço do `jal`, função envolvente, `cat`/`idx` pedidos (com o texto da
    instrução que produziu o `a0` — nada é deduzido), se o `a1` é 0 (UI, sem posição 3D) ou
    um ponteiro de posição, o EVENTO de jogo e a CONFIANÇA.
    """
    from exe_parse import Exe
    import bisect
    import capstone

    e = Exe(paths.extracted("SLUS_009.23"))
    md = capstone.Cs(capstone.CS_ARCH_MIPS,
                     capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
    md.detail = True
    alvo = (3 << 26) | ((SE_PEDE & 0x0FFFFFFF) >> 2)          # jal = opcode 3
    hits = [e.base + o for o in range(0, len(e.text) - 4, 4)
            if struct.unpack_from("<I", e.text, o)[0] == alvo]
    inicios = funcoes_do_exe(e)

    out = []
    for h in hits:
        val, txt = _back(md, e, h, "$a0")
        a1, txt1 = _back(md, e, h, "$a1")
        k = bisect.bisect_right(inicios, h) - 1
        fn = inicios[k] if k >= 0 else None
        rot, evento, conf = FN_ROTULO.get(fn, ("", "", "NAO_SEI"))
        origem = txt
        if h in A0_POR_PREDECESSOR:
            val, origem = A0_POR_PREDECESSOR[h][0], A0_POR_PREDECESSOR[h][1]
        cat = idx = None
        idx_txt = ""
        if val is not None:
            cat, idx = (val >> 8) & 0xFF, val & 0xFF
            idx_txt = str(idx)
        if h in A0_DINAMICO:
            c, ix, como = A0_DINAMICO[h]
            cat, idx, idx_txt, origem = c, None, ix, "%s [%s]" % (txt, como)
        if h in SITE_EVENTO:
            evento, conf = SITE_EVENTO[h]
        out.append({
            "addr": h, "fn": fn, "fn_rotulo": rot,
            "cat": cat, "idx": idx, "idx_expr": idx_txt, "a0": val,
            "a0_origem": origem,
            "a1": ("0 (UI, sem posição 3D)" if a1 == 0 else
                   ("posição: %s" % txt1 if txt1 else "?")),
            "evento": evento, "conf": conf,
        })
    return out


# As 16 macro-ações do player (`player+5` indexa esta tabela); 0..3 = locomoção.
PLAYER_ACOES = 0x8009CDA0
PLAYER_ACOES_N = 16


def imprimir_callsites():
    tab = tabela_callsites()
    cs = [(r["addr"], r["cat"], r["idx"], r["a0"]) for r in tab]
    id_conf = {}
    for r in tab:
        id_conf.setdefault(r["conf"], 0)
        id_conf[r["conf"]] += 1
    print("jal 0x800746c0: %d call sites (%d com a0 constante) — %s"
          % (len(cs), sum(1 for c in cs if c[3] is not None),
             ", ".join("%s %d" % (k, v) for k, v in sorted(id_conf.items()))))
    print(" addr      fn        cat idx   a1        conf       evento")
    for r in tab:
        print(" %08x  %08x %3s %-5s %-9s %-10s %s"
              % (r["addr"], r["fn"] or 0,
                 "?" if r["cat"] is None else r["cat"], r["idx_expr"] or "?",
                 "0" if r["a1"].startswith("0") else "pos", r["conf"],
                 r["evento"] or "(NÃO SEI) " + r["fn_rotulo"]))
    por_cat = {}
    for r in tab:
        if r["cat"] is not None:
            por_cat.setdefault(r["cat"], []).append(r["idx"])
    print("\npor cat (idx None = pedido com id dinâmico):")
    for cat in sorted(por_cat):
        ids = sorted(set(i for i in por_cat[cat] if i is not None))
        din = sum(1 for i in por_cat[cat] if i is None)
        print("  cat %d: %d pedidos (%d dinâmicos), ids %s"
              % (cat, len(por_cat[cat]), din, ids))
    print("  sem cat constante: %d" % sum(1 for r in tab if r["cat"] is None))
    n_arma = sum(1 for _a, cat, idx, _b in cs if cat == 1 and idx == 0)
    print("\ncat 1 / id 0 (estouro da arma, tabela 0x8009ced8): %d call sites" % n_arma)

    # PASSO — o achado NEGATIVO, medido: as macro-ações do player vivem na tabela
    # `0x8009cda0` (16 ponteiros, indexada por `player+5`); 0..3 = idle / frente / ré /
    # correr. O intervalo de cada rotina é [ptr[i], ptr[i+1]) porque a tabela está em ordem
    # crescente de endereço. Se nenhum dos 155 `jal 0x800746c0` cair nesses intervalos, o
    # motor NÃO pede SE de dentro da locomoção.
    from exe_parse import Exe
    e2 = Exe(paths.extracted("SLUS_009.23"))
    ptrs = [e2.u32(PLAYER_ACOES + i * 4) for i in range(PLAYER_ACOES_N)]
    print("\nPASSO — macro-ações do player (0x%08x):" % PLAYER_ACOES)
    for i in range(4):
        ini, fim = ptrs[i], ptrs[i + 1]
        dentro = [a for a, _c, _x, _b in cs if ini <= a < fim]
        print("  rotina %d [%08x, %08x): %d pedido(s) de SE %s"
              % (i, ini, fim, len(dentro), [hex(x) for x in dentro]))
    total = sum(1 for a, _c, _x, _b in cs if ptrs[0] <= a < ptrs[4])
    print("  => %d pedidos de SE em TODA a locomoção (idle/frente/ré/correr)" % total)
    print("  => som de PASSO: NÃO PROVADO (nenhum call site amarrável)")


CALLSITES_JSON = "se_callsites.json"


def gerar_callsites():
    """Escreve `<out>/data/se_callsites.json` — os 155 sítios, versionáveis."""
    tab = tabela_callsites()
    por_conf, por_cat = {}, {}
    for r in tab:
        por_conf[r["conf"]] = por_conf.get(r["conf"], 0) + 1
        c = "?" if r["cat"] is None else str(r["cat"])
        por_cat[c] = por_cat.get(c, 0) + 1
    dados = {
        "_meta": {
            "descricao": "Os 155 `jal 0x800746c0` (SE_pede) do SLUS_009.23, com a função "
                         "envolvente, o (cat, idx) pedido, o a1 e o EVENTO de jogo. Gerado "
                         "por tools/exe_audio.py --callsites. Ver "
                         "docs/decomp/notes/exe_audio.md §12.",
            "PROVA": "o anel de pedidos 0x800e0de4 só é escrito por 0x800746c0 e só é lido/"
                     "zerado por 0x800744e0, logo TODO som do jogo passa por um destes 155 "
                     "sítios. `a0` recuperado por back-walk do imediato (nada deduzido); os "
                     "3 sítios cujo a0 vem do delay slot de um desvio estão em "
                     "A0_POR_PREDECESSOR, com todos os predecessores enumerados.",
            "conf": {"PROVADO": "cat/idx E evento saem da desmontagem",
                     "DECLARADO": "cat/idx medido, NOME do evento é escolha do port",
                     "NAO_SEI": "cat/idx medido, evento não identificado"},
            "total": len(tab), "por_conf": por_conf, "por_cat": por_cat,
        },
        "sites": [{
            "jal": "0x%08x" % r["addr"],
            "fn": "0x%08x" % (r["fn"] or 0),
            "fn_rotulo": r["fn_rotulo"],
            "cat": r["cat"], "idx": r["idx"], "idx_expr": r["idx_expr"],
            "a0": None if r["a0"] is None else "0x%x" % r["a0"],
            "a0_origem": r["a0_origem"], "a1": r["a1"],
            "evento": r["evento"], "conf": r["conf"],
        } for r in tab],
    }
    p = paths.data(CALLSITES_JSON)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=1, sort_keys=False)
    print("%s: %d sitios (%s)" % (p, len(tab),
          ", ".join("%s %d" % (k, v) for k, v in sorted(por_conf.items()))))
    return dados


def imprimir_eventos_arma():
    """Imprime os SE por quadro de animação de cada arma (mecanismo/recarga) — §14."""
    ev = eventos_de_arma()
    bancos_arma = {n: parse_banco(n, ph, pc) for n, ph, pc in bancos_disponiveis()
                   if n.startswith("A_")}
    print(" w  plw          banco  eventos (seq/quadro -> cat 1 / id -> wav)")
    for w, e in sorted(ev.items()):
        b = bancos_arma.get(e["banco"])
        partes = []
        for it in e["eventos"]:
            info = (b["se"].get(it["id"]) if b else None)
            wav = info["wav"] if info and not info.get("dummy", True) else "-"
            marca = "" if info else "  <- NAO no banco"
            partes.append("seq%d/f%d=id%d(%s)%s" % (it["seq"], it["quadro"], it["id"], wav, marca))
        print("%2d  %-12s %-6s %s" % (w, e["plw"], e["banco"],
                                      "  ".join(partes) if partes else "(nenhum)"))
    print("\nseq %d = RECARGA · seq 1/3/5 = FOGO. `cat 1 / id 1` (arma vazia) NAO vem de quadro:"
          % SEQ_RECARGA)
    print("vem do codigo, nos 4 sitios de 0x8003f190/0x8003fd90/0x8004029c/0x8004070c.")


def main(argv):
    if "--callsites" in argv:
        imprimir_callsites()
        if "--json" in argv:
            gerar_callsites()
        return 0
    if "--verificar" in argv:
        return 1 if verificar()[1] else 0
    if "--tabela" in argv:
        tabela(argv[argv.index("--tabela") + 1])
        return 0
    if "--portas" in argv:
        extrair_portas()
        return 0
    if "--salas" in argv:
        extrair_salas()
        return 0
    if "--armas" in argv:
        imprimir_eventos_arma()
        return 0
    if "--portas-salas" in argv:
        gerar_portas_salas()
        return 0
    gerar()
    gerar_portas_salas()
    gerar_callsites()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
