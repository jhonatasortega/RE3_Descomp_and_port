# door_dest — handler de porta e DESTINO de sala (RE3 PS1 NTSC-U)

> **RESOLVIDO — 100% (453/453 destinos; reciprocidade EXPLICADA a 100%).** O destino
> (stage,room) de uma porta É **campo estático do SCD**. A porta é o **AOT cujo SCE type
> (byte@+2) troca de sala** — SCE em **{1, 13}** — criado pelos opcodes **`0x61`
> (DOOR_AOT_SET, 32B)** e **`0x62` (DOOR_AOT_SET_4P, 40B)**. O de-para índice→fileid
> `0x8009dfd0[stage][room]`→nome (autoritativo do motor) resolve **453/453**.
> Reciprocidade A↔B = **94,3% (279/296 arestas-sala)**; as **17 arestas mão-única**
> restantes são **TODAS justificadas** (Mercenaries, variante de estado, gate de
> progressão, endgame/boss, queda, placeholder) — **0 erro de parse/destino**.
> Ferramentas: `tools/scd_door_dest.py` (extrator) + `tools/room_graph_build.py`.
>
> **AUDITORIA (este round) — 3 achados:**
> 1. **sce==13 é uma 2ª porta.** Além do produtor de porta sce==1 (`0x80050d28`), o
>    handler **`0x80051cb0` (jump-table de SCE `0x8009e0bc[13]`)** também faz
>    `gs+0x2154 = descriptor` + `flag-troca 0x800c7960 = 1` (em `0x80051d04`/`0x80051d10`),
>    após gates de estado. As **6× `0x61` com `sce==13`** (antes descartadas como "sce≠1")
>    SÃO transições reais: 3 pares **recíprocos** `R114↔R118`, `R304↔R30A`, `R40C↔R40E`.
>    ⇒ **total de portas 447 → 453**.
> 2. **Não há outro mecanismo de troca de sala.** Varredura de TODOS os opcodes AOT
>    (`0x61/0x62/0x63/0x64/0x65/0x67/0x68`) das 169 salas: só `sce∈{1,13}` troca de sala
>    (`0x63/0x64` nunca têm `sce==1`; `0x67/0x68` são `sce==2`). O **room-loader
>    `0x800493ec` só é chamado pelo cluster do door_handler** (2 sites: `0x800247cc`,
>    `0x80024a64`) — **não há warp por opcode de script**. As **55× `0x65` (aot_reset,
>    10B) `sce==1`** apenas RE-ARMAM AOTs de porta existentes (10B não cabe destino) — não
>    adicionam transição.
> 3. **17 mão-única auditadas 1-a-1** (prova por SCD/box/arrival/disassembly): nenhuma é
>    erro de destino. Ver §"Auditoria das 17 mão-única".

## A correção (o que estava errado)

Rounds anteriores trataram a "porta de 62B" = par `0x67`(22B)+`0x7f`(40B) como a
porta e concluíram (corretamente, para ESSE opcode) que os bytes de destino eram
sempre zero → "destino é runtime". **Mas `0x67` é `sce==2`** (outro tipo de AOT) e
**`0x7f`** só monta uma struct de colisão 3D (quad de 4 vértices) — nenhum dos dois
carrega o destino. A porta de verdade é `sce==1`, em opcodes diferentes.

## Cadeia consumidora — CONFIRMADA byte-a-byte

1. **Registro (handler do opcode):** `0x61`→`0x80055b5c`, `0x62`→`0x80055bbc`. Ambos
   fazem `gs+0x2158[id] = &(opcode + 2)` (registram o AOT apontando p/ o bytecode).
   O `0x62` ainda liga `byte@+3 |= 0x80` (= AOT byte@+1) — muda o *path* (ver adiante).
2. **VM de AOT per-frame** (dispatch `0x80050aac`, jump-table por SCE `0x8009e0bc`):
   - `sce = *(AOT+0) = opcode byte@+2`.
   - se `(AOT byte@+1 & 0x80)`: `a0 = AOT + 0x14` (**path 0x14**, usado pelo `0x62`);
     senão `a0 = AOT + 0xc` (**path 0x0c**, usado pelo `0x61`).
   - `sce==1` → `*(0x8009e0bc + 1*4)` = **produtor de porta `0x80050d28`**, com `a0` = descriptor.
3. **Produtor `0x80050d28`:** ao tocar o gatilho, `gs+0x2154 = descriptor` (`= a0`) e
   liga a flag-troca `0x800c7960`.
4. **door_handler `0x800248e4`:** lê `descriptor = *(gs+0x2154)` e daí:
   - `+0/+2/+4/+6` (u16) = **chegada** next_x/next_y/next_z/next_dir → spawn do player;
   - **`+8` = next_stage** (`multu 0x38e38e39` ⇒ ÷9 ⇒ aplica **mod 9** → exe-stage 0..6);
     grava `current_stage 0x800d1f76` (só se mudou);
   - **`+9` = next_room** → grava `current_room 0x800d1f78`;
   - `+0xa` = câmera/cut, `+0xb` = flag.

Como `descriptor = opcode + 2 + path`, os campos caem em offsets ON-DISK fixos:

| opcode | path | chegada (s16) | next_stage | next_room | cut |
|---|---|---|---|---|---|
| `0x61` (32B) | 0x0c | +0xe/+0x10/+0x12/+0x14 | **+0x16** | **+0x17** | +0x18 |
| `0x62` (40B) | 0x14 | +0x16/+0x18/+0x1a/+0x1c | **+0x1e** | **+0x1f** | +0x20 |

- **next_stage** = byte cru; `mod 9` → exe-stage. Distribuição real: 100% em {0..6}.
- **next_room** = **índice interno** na tabela de fileids `0x8009dfd0[stage]`. Esse índice
  **É o número hex do nome** (`Rxyz`→`int(yz,16)`) — o de-para correto é `índice→fileid→
  nome` (a tabela pode ter dups/0). NÃO é a posição-ordenada-na-pasta (que só coincide
  quando não há dups, i.e. stages 0–2).
- **gatilho AABB (`0x61`)**: X@+6, Z@+8, W@+10, D@+12 (s16). (`0x62` = quad de 4 vértices em +6..+0x15.)

## LINK FINO DO CALLBACK DE COLISÃO — FECHADO byte-a-byte  ✅ (este round)

Faltava provar **exatamente** como a colisão do player com o AOT de porta dispara o
handler. Desmontado fim-a-fim (100%):

1. **Driver per-frame `0x80050b58`** (chamado no loop principal em `0x80023f38`) roda a
   **VM de colisão de AOT `0x800505ac`** DUAS vezes sobre o player (`a0 = gs+0x248c =
   0x800ccbc4`): `a2=0x10` (passe de detecção) e `a2=0` (passe de gatilho). Gate no topo:
   `lh 0x2558(gs) bltz→sai`, checa `gs+0x25b9`, e limpa/atualiza `0x800decac`.
2. **VM `0x800505ac`** itera os AOTs registrados `gs+0x2158[id]` (o mesmo array que os
   handlers `0x61/0x62` preencheram). Para cada AOT com `byte@+1 & <mask a3>` e
   `byte@+1 & 0x10`, **monta a forma de colisão** a partir do descriptor:
   - `byte@+1 & 0x40 == 0` → **AABB**: origem `[+4]/[+6]`, extensão `[+8]/[+0xa]`
     (montada no stack em `sp+0x2c/0x2e/0x30/0x32`).
   - `byte@+1 & 0x40` → **QUAD** de 4 vértices (`+4..+0x12`, em `sp+0x28..0x3a`).
   A posição do player vem de `s5+0x34 / s5+0x3c` (X/Z do char).
3. **Teste ponto-em-forma** (`0x800509dc`–`0x80050a60`):
   - `byte@+1 & 0x80` → **`0x8001020c`** = ponto-em-QUAD (produto vetorial dos 4 lados).
   - senão → **`0x800101c8`** = ponto-em-AABB (`(X-x0) u< w && (Z-z0) u< d` ⇒ dentro).
   Resultado (`v0`: 1=dentro/0=fora) é gravado no global `0x800decac` (`s7-0x1354`) e o
   índice do AOT em `gs+0x780e/gs+0x7810` (`s2`). Se **fora**, salta p/ o próximo AOT.
4. **Dispatch por SCE** (`0x80050a64`+): grava `player+0xc = AOT id` (`s2`), seleciona o
   **path** por `byte@+1 & 0x80` (`a0 = AOT+0x14` se setado [0x62], senão `AOT+0xc` [0x61]),
   lê `sce = byte@+0`, e `jalr *(0x8009e0bc + sce*4)` com `a0 = descriptor`.
5. **`sce==1` → produtor `0x80050d28`**: grava `gs+0x21d8 = *(0x800decac)`,
   `gs+0x21dc = descriptor`, e no site de disparo (`0x80050f90`+ / `0x800510e8`+):
   **`0x800c7960 = 1`** (flag-troca), **`gs+0x2154 = descriptor`**, `gs+0x2468 |= 0xff000000`.
6. Daí segue a cadeia já documentada: **door_handler `0x800248e4`** lê `gs+0x2154` e chama o
   **room-loader `0x800493ec`**.

Jump-table de SCE `0x8009e0bc` (16 entradas, extraída): `sce0=0x80050d00`, **`sce1=0x80050d28`
(porta)**, `sce2=0x8005111c`, `sce3=0x80051284`... A porta é `sce==1`, confirmando a §"correção".

> **Primitivas de colisão (provadas):** `0x800101c8` = ponto-em-AABB (`a0`=ponto word@+0/+8,
> `a1`=rect s16@+0/+2 & u16@+4/+6; retorna 1=dentro). `0x8001020c` = ponto-em-QUAD convexo
> (4 vértices, 4 testes de sinal de produto vetorial). São as mesmas primitivas de todos os
> AOTs — o dispatch por SCE é o que diferencia porta/item/evento.

## Prova (reciprocidade) — o destino é ESTÁTICO

Extraí `to_stage=next_stage%9`, `to_room=next_room` de **453 portas** (`sce∈{1,13}`;
408× `0x61 sce1` + 39× `0x62 sce1` + 6× `0x61 sce13`). Mapeando (stage,índice)→`Rxyz`
pela tabela de fileids (de-para autoritativo `índice→fileid→nome`):

| métrica | valor |
|---|---|
| portas (arestas) | **453** (447 `sce1` + 6 `sce13`) |
| destino resolvido p/ `Rxyz` | **453 (100%)** |
| portas cross-stage resolvidas | 17 |
| abertas (TODO) | **0** |
| arestas-sala únicas (gêmeas coladas) | 296 |
| **recíprocas A↔B** | **279 (94,3%)** |
| mão-única (todas justificadas) | **17 (0 não-explicada)** |

**Offsets do descriptor (idênticos p/ sce1 e sce13; ambos usam o mesmo door_handler):**
`0x61` path `0x0c` → next_stage=+0x16, next_room=+0x17, cut=+0x18, chegada s16@+0xe..+0x14;
`0x62` path `0x14` → next_stage=+0x1e, next_room=+0x1f, cut=+0x20, chegada s16@+0x16..+0x1c.
(`sce==13` só ocorre em `0x61`; byte@+3=`0x21` ⇒ path `0x0c`, confirmado nas 6.)

## Auditoria das 17 mão-única (todas justificadas — 0 erro de parse)

Calibração: em 412 portas recíprocas, a chegada A→B cai a **p95 = 747 u** da box da
porta de volta em B (400/412 ≤ 2000 u). Nenhuma das 17 tem porta-de-volta a A dentro
desse limiar ⇒ são mão-única de fato, não destino errado. Motivos (gravados em
`oneway_reason` de cada aresta):

| aresta (real) | motivo | prova |
|---|---|---|
| `R601→R600`, `R701→R600` | mercenaries_hub_terminal | `R600` = hub de Mercenaries, **0 portas** de saída |
| `R621→R61B`, `R706→R316` | mercenaries_route | porta só de Mercenaries; jogo principal não liga; rota dirigida |
| `R109→R10E` | story_variant | volta de `R10E` vai a `R123` = variante de `R109` (fingerprint de portas igual) |
| `R20D→R217` | story_variant | `R20D` usa a MESMA box p/ `R20E`(normal) e `R217`(alt); `R20D↔R20E` recíproco |
| `R30B→R30D` | story_variant | `R30B` usa a MESMA box p/ `R30A`(normal) e `R30D`(alt); `R30A↔R30B` recíproco |
| `R30D→R310` | transient_variant_scripted | `R30D`(variante) sai por box ZERO (scripted) p/ `R310`; passagem |
| `R215→R303`, `R215→R305` | story_progression_gate | cross-stage 2→3 (Uptown→Clock Tower); box ZERO (cutscene); sem retorno |
| `R50C→R50D` | endgame_boss | entrada da sala do chefe final |
| `R50D→R50F` | endgame_boss_scripted | chefe→elevador; box ZERO (cutscene) |
| `R50F→R50E` | endgame_ending_scripted | elevador→helicóptero (fim); `R50E` terminal (0 portas) |
| `R510→R504` | one_way_fall | queda da ponte p/ esgoto; arrival ZERADO (spawn scripted) |
| `R10A→R10F` | one_way_layout | única saída estática de `R10F` vai a `R106/R121`; sem volta a `R10A` |
| `R212→R206` | one_way_special | `sat=0x31`, trigger PONTUAL 1×1 p/ o hub `R206`; sem volta estática |
| `R10D→R101` | placeholder_unused | `R10D` inalcançável (nada aponta p/ ela); porta com box+arrival ZERADOS (único no jogo) |

- **Cross-stage recíproco de verdade:** `R124↔R21A`, `R309↔R400`, `R40F↔R510`;
  gêmeas Mercenaries `R6xx→R1xx`/`R7xx→R2xx` aparecem naturalmente.
- **94,1% ≫ o teto de ~15%** da hipótese antiga → o par (stage,room) **É** campo estático.
  O "≤15%" de antes era artefato de ler o opcode errado (`0x67`), não ausência do dado.

## Os 35 antes-abertos — FECHADOS (de-para autoritativo do fileid)

Eram portas cujo **next_room (índice interno)** apontava para um slot que o de-para
antigo (posição-na-pasta) não conseguia mapear, porque **stages 4/6/7 têm DUPLICATAS e
slots vazios (0)** na tabela de fileids `0x8009dfd0`. A correção: o índice interno **É os
dígitos hex do nome** (`Rxyz`→`int(yz,16)`) e é o MESMO índice de `fileid =
0x8009dfd0[stage][room]`. Logo o de-para correto é **`índice→fileid→nome`** (não
posição-na-pasta): vários índices caindo num fileid duplicado apontam para a MESMA sala
reusada/placeholder. Isso fecha **35/35** (ex.: `R402#23→R417`, `R601#29→R61D`,
`R700#24→R718`, `R71A#24→R718`) — **34 delas recíprocas** (a porta de volta confirma), 1
direção-única. `dest_source="recip"` quando a volta B→A existe; `"scd_door"` na
direção-única. Nada fabricado: o de-para é a tabela que o próprio motor usa.

## Tabela de fileids `0x8009dfd0` (extraída do EXE; base do de-para)

9 ponteiros u32 (1 por exe-stage). Os stages REAIS são 0..6 (`raw_stage%9` = 100% em
{0..6}); seus arrays são **contíguos** em `0x8009de30..0x8009dfd0` (fim de um = início do
próximo; o do stage 6 termina na própria tabela de ponteiros). Ponteiros 7/8 apontam p/
outra região (dados não-sala) → ignorados. Cada array = u16 de fileids por índice interno;
**dups** (índices→mesmo fileid) e **0** (slot vazio) nos stages 4/6/7. Room-loader
`0x800493ec`: `fileid = tabela[stage][room]` → `jal 0x80012818` (`a3="ARD"`); `fileid+1`
= BIN/RDT. Leitura em `scd_door_dest.fileid_tables()`/`room_index_map()`.

## Chegada (arrival) — 100% decodificada, agora do opcode CERTO

`to_x/to_y/to_z/to_facing` = chegada em coords de mundo (spawn do player na sala-destino),
lida dos offsets acima. Gravada em todas as 447 portas.

## Saídas gravadas

- `godot/data/room_graph.json` — 169 nós + **453 arestas**; cada aresta tem
  `to_stage/to_room/to_room_id`, `sce` (1|13), `arrival`, `box`, **`reciprocal`
  (true/false)** e **`oneway_reason`** (quando false), `dest_source`, `dest_conf`,
  `dest_reason`, `raw_stage/raw_room`, `to_camera`. `_meta.destino_stats` traz
  `reciprocidade_explicada_pct = 100.0`.
- `godot/data/STAGE*/R*_scd.json` — `doors[]` reescrito com as portas reais (`sce==1`);
  demais seções (enemies/items/triggers/flags/messages) preservadas.

## Endereços (resumo p/ retomar)

`0x800248e4` door_handler · `0x80050d28` produtor de porta (**sce==1**, jump-table[1]) ·
**`0x80051cb0` handler de porta condicional (sce==13, jump-table[13]; escreve flag+
descriptor em `0x80051d04`/`0x80051d10`)** · jump-table AOT per-frame por SCE `0x8009e0bc`
(dispatch `0x80050aac`) · handlers de registro `0x80055b5c`(0x61)/`0x80055bbc`(0x62) ·
room-loader `0x800493ec` (chamado só do cluster do door_handler: `0x800247cc`,`0x80024a64`) ·
tabela fileid `0x8009dfd0` · descriptor `*(0x800cc88c)` (gs+0x2154) · current_stage
`0x800d1f76` · current_room `0x800d1f78` · flag-troca `0x800c7960` (STOREs: `0x80050fa0`,
`0x800510f4` [sce1], `0x80051d04` [sce13], reset `0x80023470`).
