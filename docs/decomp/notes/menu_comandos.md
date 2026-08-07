# Submenu de COMANDO do item, USE/EQUIP, COMBINE e a CAIXA — RE3 NTSC-U (`SLUS_009.23`)

**Alvo:** Resident Evil 3: Nemesis, PS1 NTSC-U, `extracted/ntsc-u/SLUS_009.23`
(PS-X EXE, base `0x80010000`, tsize `0xd3800`).
**Ferramentas:** [`tools/exe_combine.py`](../../../tools/exe_combine.py) (novo, gera
`port/data/re3_combinacoes.json`), [`tools/exe_parse.py`](../../../tools/exe_parse.py),
[`tools/status_layout.py`](../../../tools/status_layout.py) (de outro agente; usei o formato de
retângulo dele), [`tools/tim2png.py`](../../../tools/tim2png.py).
**Escopo:** o que acontece depois de você apertar CONFIRMAR em cima de um item do inventário.
Não cobre: layout completo da tela de status, tela de MAPA, tela de ARQUIVO, tela de CAIXA
por dentro (só a porta de entrada), animação de cura do modelo do player.

> A tela de inventário **não é um overlay `BIN/*.BIN`**: é uma *task* do EXE principal
> (entry `0x8006dfdc`, contexto em `0x800e01c0`). Confere com `menu_overlays.md` (nenhum dos 17
> overlays é o inventário).
>
> **Correção a `exe_items.md` §2.1:** `inv+0x128` **não é o cursor**. É o **índice do slot da
> arma equipada** (`0xff` = nada equipado) — provado em §3 (EQUIP) e §9 (recarga rápida).
> O cursor da grade fica em `ctx+0x1c` do contexto da tela, não na struct do inventário.

---

## 0. Endereços-âncora (resumo)

| endereço | o que é |
|---|---|
| `0x800e01c0` | contexto (`ctx`) da task da tela de status. `ctx+4` = MODO, `ctx+0x10` = estado externo |
| `0x800a02f0` | tabela de 14 handlers do estado externo (`ctx+0x10`) |
| `0x800a0100` | **tabela de 14 handlers do inventário** (`ctx+0x11`) |
| `0x800a0138` | tabela de 6 handlers do modo COMBINE (`ctx+0x12`) |
| `0x800665c8` | dispatcher do inventário: `handlers[ctx[0x11]](ctx)` |
| `0x80066604` | ctx[0x11]=0 — navegar a grade |
| `0x800668e4` | ctx[0x11]=1 — animação de ABRIR a lista de comandos |
| `0x80066920` | ctx[0x11]=2 — **interação com a lista de comandos** |
| `0x80066a90` | ctx[0x11]=3 — animação de FECHAR a lista |
| `0x800676b8` | ctx[0x11]=6 — executor do comando 0 (USE / EQUIP) |
| `0x80067b70` | ctx[0x11]=7 — dispatcher do COMBINE |
| `0x80069280` | ctx[0x11]=8 — executor do comando 2 (CHECK) |
| `0x8006954c` | ctx[0x11]=9 — executor do comando 3 (AUTO/MANUAL) |
| `0x80069614` | animação da lista de comandos (`a1`=0 abre, `a1`≠0 fecha) |
| `0x8006b66c` | rotina de DESENHO da tela de status/inventário |
| `0x800a0514` | descritor de item (4 B × `0xac` entradas) |
| `0x800a07c4` | **tabela de combinação** (8 B/reg, terminador `rec[1]==0xff` em `0x800a0bac`) |
| `0x8006a898` | `combine_find(a1=idA, a2=idB)` — busca linear simétrica |
| `0x80068024` | executor genérico da combinação (calcula o efeito) |
| `0x80068bc0` | ctx[0x12]=3 — animação + **aplicação final** da combinação |
| `0x8006e598` | `health_state()` → 0..5 (FINE/CAUTION/CAUTION/DANGER/POISON/?) |
| `0x8009e0bc` | jump-table de SCE/AOT: **`sce==8` = máquina de escrever, `sce==9` = CAIXA DE ITENS** |

Globais (base do gamestruct `gs = 0x800ca738`):

| endereço | o que é |
|---|---|
| `gs+0x7c7c` = `0x800d23b4` | ponteiro da struct do inventário (= `0x800d2134`) |
| `gs+0x2558` = `0x800ccc90` | **HP atual** (u16) |
| `gs+0x255a` = `0x800ccc92` | **HP máximo** (u16) |
| `gs+0x255e` = `0x800ccc96` | flags de estado; **bit `0x0200` = ENVENENADO**, bit `0x0100` = estado 5 |
| `gs+0x2100` = `0x800cc838` | u16 de direcionais (edge): `0x1000`=CIMA `0x4000`=BAIXO `0x8000`=ESQ `0x2000`=DIR |
| `gs+0x2108` = `0x800cc840` | u32 de botões (edge): `0x1000` = CONFIRMAR, `0x2000` = CANCELAR |
| `gs+0x20fc` = `0x800cc834` | u16; bit `0x20` também cancela |
| `gs+0x2110` = `0x800cc848` | qual campo/buffer duplo está ativo (0 ou 1) |
| `gs+0x7910` = `0x800d2048` | bitfield "item examinado" (bit = `descritor.b2`) |
| `0x800dbb58` | u8; bit `0x80` = **há mensagem na tela** (as telas esperam esse bit cair) |

Helpers usados o tempo todo:
- `0x800746c0(a0=id_som, 0,0,0)` — SFX de UI. Ids vistos: **4** mover cursor, **5** cancelar,
  **6** confirmar, **7** erro/negado, **9** trocar para FILE/MAP, `0x214`/`0x215` na caixa.
- `0x8002fd30(a0=0, a1=canal, a2=índice, a3=0)` — abre uma mensagem. `a1` visto: `0x1000`,
  `0x1100`, `0x1400`. Índices vistos em §3/§5: 2, 3, 5, 7, 8, 9, 0xa, 0xd, 0xe, e `id+0x10`
  (texto de EXAME do item — confirma o `idx = id + 16` do `re3_items.json`).
- `0x80078930(a0=ponteiro_de_banco, a1=bit)` = `flag_test`; `0x800788dc` = `flag_set`.
- `0x8006ae20(a0=slot_dst, a1=slot_src)` — `MoveImage` de VRAM entre dois retângulos de
  20×30 (halfwords) da tabela `0x800a004c`; usado para mover/apagar o ícone de um slot.
- `0x8006ab08(a0=slot)` — `LoadImage` do ícone recém-carregado no retângulo do slot.
- `0x8006aa84(a0=item_id)` — lê do CD o asset do ícone daquele item
  (`cd_read_file(a0=0x34, lba = filetab[0x34].lba + item_id, size = 0x800)`;
  o byte de "flags" do request vem de `0x8009f568[item_id]`). **Qual arquivo é o índice `0x34`
  eu NÃO conferi.**

---

## 1. A LISTA DE COMANDOS — quais, em que ordem, para que item

### 1.1 Como se entra e sai

`ctx+0x1c` = cursor da grade principal (byte **com sinal**). `>= 0` é slot; `-1` = aba
ARQUIVO; `-2` = aba MAPA; `< -2` = sair da tela.

Em `0x80066604` (navegar), com CONFIRMAR (`gs[0x2108] & 0x1000`) sobre um slot **não vazio**:
```
ctx[0x11] = 1          # 0x80066684..0x8006668c
ctx[0x1e] = 4          # 0x80066694  (índice do comando; 4 = "nenhum" durante a animação)
ctx[0x2a] = slot.flags # 0x800666a4  (hword +2 do slot)
som 6
```
Slot vazio → som 7 e nada. Ao terminar a animação (`0x800668e4`): `ctx[0x11] = 2`,
`ctx[0x1e] = 0`.

Em `0x80066920` (interação):
```
n = (INV[ctx[0x1c]].flags & 0x10) ? 4 : 3         # 0x8006694c..0x80066958
CANCELAR (0x2108 & 0x2000)  -> ctx[0x11] = 3, som 5
CIMA   (0x2100 & 0x1000)    -> ctx[0x1e]--
BAIXO  (0x2100 & 0x4000)    -> ctx[0x1e]++
clamp: se ctx[0x1e] < 0 -> n-1 ; se ctx[0x1e] >= n -> 0    (dá a volta)
CONFIRMAR (0x2108 & 0x1000):
    se ctx[0x1e] == 0 e (u8)(slot.id + 0x7d) < 2      # id == 0x83 ou 0x84
        ctx[0x11] = 8
    senão
        ctx[0x11] = ctx[0x1e] + 6
    ctx[0x12] = 0 ; ctx[0x13] = 0 ; som 6
```
Ou seja **comando i → estado `6+i`**: 0→6 (USE/EQUIP), 1→7 (COMBINE), 2→8 (CHECK),
3→9 (AUTO/MANUAL). A exceção `0x83`/`0x84` (*Game Inst. A/B*) manda o comando 0 direto para o
CHECK (estado 8).

### 1.2 Os rótulos — PROVADOS na textura

Os rótulos são SPRTs de **48×16** vindos de **`ETC/STMOJIU.TIM`**
(`extracted/ntsc-u/CD_DATA/ETC/STMOJIU.TIM`, **256×72**, 4bpp+CLUT; já existe convertido em
`port/assets/ETC/STMOJIU.webp`, e pode ser regerado com
`python tools/tim2png.py <saida> extracted/ntsc-u/CD_DATA/ETC/STMOJIU.TIM`).
Conteúdo por faixa de `v` (medido pelos bounding boxes de tinta por coluna):
`v=0..16` setas ↑↓←→ + `EXIT` + 3 molduras vazias · `v=16..32` dígitos `0123456789%:` ·
`v=32..40` os 6 estados de saúde (§4.3) · `v=40..56` `FILE EXIT MAP AUTO MANUAL` ·
`v=56..72` **`EQUIP USE COMBINE PIECES CHECK`**.

Registros de retângulo (12 B: `u16 u, u16 v, u16 w, u16 h, u16 dx, u16 dy`; **dx/dy em pixels de
tela 320×240**, somados à base `(*(s16*)(ctx+0xe4+idx*4), *(s16*)(ctx+0xe6+idx*4))`):

| registro | u | v | w | h | dx | dy | rótulo | onde é colocado |
|---|---|---|---|---|---|---|---|---|
| `0x8009ffb0` | 0 | 56 | 48 | 16 | **163** | **84** | **EQUIP** | `0x8006be48` (se cat==1) |
| `0x8009ffbc` | 48 | 56 | 48 | 16 | **163** | **84** | **USE** | `0x8006be60` (senão) |
| `0x8009ffc8` | 96 | 56 | 48 | 16 | **163** | **104** | **COMBINE** | `0x8006be88` (sempre) |
| `0x8009ffd4` | 144 | 56 | 48 | 16 | 163 | 104 | *PIECES* | **construído em `0x8006b590` e NUNCA colocado — MORTO no retail** |
| `0x8009ffe0` | 192 | 56 | 48 | 16 | **163** | **124** | **CHECK** | `0x8006beb0` (sempre) |
| `0x8009ffec` | 112 | 40 | 48 | 16 | **163** | **144** | **AUTO** | `0x8006bf04` (se `flags&0x10` e `!(flags&0x100)`) |
| `0x8009fff8` | 160 | 40 | 48 | 16 | **163** | **144** | **MANUAL** | `0x8006bef4` (se `flags&0x10` e `flags&0x100`) |

Prova de que PIECES é morto: varri o `.text` inteiro procurando qualquer par `lui/addiu` que
forme `0x8009ffd4` — só existe **um**, em `0x8006b590`, que é a chamada de *build*
(`0x8006e600`), nunca a de *place* (`0x8006e8bc`).

### 1.3 Regra por TIPO de item — PROVADA

O tipo vem do byte 0 do **descritor** `0x800a0514 + id*4` (`s7` em `0x8006b9a0`):

| cat | itens | linha 0 |
|---|---|---|
| 1 | armas `0x01..0x14` | **EQUIP** |
| 2,3,4,5,6,7,8 e 0 | todo o resto | **USE** |

Prova: `0x8006be2c` `lbu $v1, ($s7)` e `bne $v1, 1` → EQUIP se `cat == 1`.

A **4ª linha (AUTO/MANUAL)** só existe se `slot.flags & 0x10`. Nos defaults do descritor
(byte 3) o bit `0x10` só aparece em **`0x0e` e `0x0f` = Assault Rifle** (`0x12` e `0x16`).
O rótulo é MANUAL quando `slot.flags & 0x100`, senão AUTO (`0x8006bec4`/`0x8006bed8`).

### 1.4 Geometria da lista (pixels de tela 320×240)

- **Painel/moldura**, 4 retângulos, `base_idx = 3` (`ctx+0xf0/0xf2`):
  - com 4 comandos (`flags&0x10`): `0x8009fbcc..0x8009fbf8` →
    (148,80) 72×48 · (148,**128**) 56×36 · (204,128) 16×16 · (204,144) 16×20
  - com 3 comandos: `0x8009fbfc..0x8009fc28` →
    (148,80) 72×48 · (148,**108**) 56×36 · (204,108) 16×16 · (204,124) 16×20
- **Barras de realce** (u=24 v=184, 64×24), uma por linha, `base_idx` 4/5/6/7:
  `0x8009fc2c` (155,**80**) · `0x8009fc38` (155,**100**) · `0x8009fc44` (155,**120**) ·
  `0x8009fc50` (155,**140**) — a última só com `flags&0x10`.
- **Rótulos** em (163, 84/104/124/144), `base_idx` 4/5/6/7 (§1.2).
- **Sombra/gradiente de 2 linhas** por linha, POLY_FT4 × 2, 56×8 em
  (159, 84/92), (159, 104/112), (159, 124/132), (159, 144/152), com duas variantes de textura
  (`v=200/208` quando a linha **está** selecionada, `v=184/192` quando **não** está) —
  registros `0x8009fe6c..0x8009ff28`. **A página de textura desses POLY_FT4 não é a
  `STMOJIU` (v=184..216 está fora dos 72 px dela); NÃO IDENTIFIQUEI qual é.**

### 1.5 Animação de abrir/fechar (`0x80069614`)

Base de posição da tela: pares `(s16 x, s16 y)` em `ctx+0xe4 + idx*4`. `idx = 3` é o painel de
comandos, `idx = 4..7` são as 4 linhas. Init (`0x80066530`/`0x8006dec0`): X de todos os pares
3..7 = **0x48 (=72)**, Y = 0; `ctx[0x104]` (par 8, painel de descrição) = **-0xd8 (=-216)`**;
`ctx[0x10e] = 0x30`.

Abrir (`a1 = 0`, contadores `ctx+0x3a/0x3b/0x3c/0x3d`):
- par `3+k` desliza **-0x18 (=-24) por frame** enquanto `ctx[0x3d] - k` ∈ {0,1,2} → 3 frames,
  72 → 0 (escalonado; o par 7 só entra se `flags & 0x10`).
- `ctx[0x3d]` vai de 0 até **7** (com 4 linhas) ou **6** (com 3 linhas) e então a função
  retorna 1 (`0x800697e0` `slti 8` vs `0x8006981c` `slti 7`).
- Em paralelo, nos 4 primeiros frames (`ctx[0x3a]==0`, `ctx[0x3c]` 0..3), os bytes **V** dos
  4 vértices dos 3 POLY_FT4 da barra vertical em `0x801ae5a8` (registros `0x8009f9b0..0x8009f9c8`,
  4×4/4×76/4×4 em x=216, y=80..164) recebem **+0x10 por frame** — stride entre prims `0x50`
  (dois POLY_FT4 de `0x28`, porque o buffer é duplo: campo 0 em `0x801ae5a8`, campo 1 em
  `0x801ae5d0`, escolhido por `gs[0x2110]`). Não interpretei o efeito visual.

Fechar: `0x80066a90` chama `0x80069614(a1=1)` e no fim faz `ctx[0x11] = 0`,
`ctx[0x22] = 0`, `ctx[0x24] = 0`, `ctx[0x18] |= 0x20000000`.

### 1.6 A grade principal — passo de 40×30 px, 2 colunas × 5 linhas

`0x800668a4`..`0x800668cc`:
```
ctx[0x114] = (ctx[0x1c] & 1) * 40         # (v0*4+v0)<<3 = v0*40
ctx[0x116] = ((s8)ctx[0x1c] >> 1) * 30    # ((v1*16)-v1)*2 = v1*30
```
Movimento (`0x8006676c`..`0x80066878`): ESQUERDA só se `idx&1`; DIREITA só se `!(idx&1)`;
CIMA `idx -= 2` se `idx >= -2`; BAIXO `idx += 2` se `idx < inv[0x12a] - 2`. Ou seja
**2 colunas, `inv[0x12a]/2` linhas (10 slots = 5 linhas)**.

---

## 2. Descritor de item — `0x800a0514`, layout campo a campo (PROVADO)

4 bytes por `item_id`, **`0xac` entradas (`0x00`..`0xab`)** — o array termina exatamente onde
começa a tabela de combinação em `0x800a07c4` (`0x800a0514 + 0xac*4 = 0x800a07c4`). Isso
**invalida** as entradas `0xac`..`0xc1` do `by_id` de `port/data/re3_items.json`, que na verdade
são as primeiras receitas de combinação lidas como descritor.

| off | tipo | nome | uso provado |
|---|---|---|---|
| +0 | u8 | **cat** | 1=arma 2=munição 3=cura 4=key_item 5=chave 6=ferramenta 7=arquivo 8=mapa, 0=nenhum. Lido em `0x8006be2c` (EQUIP vs USE), `0x800676fc` (dispatch do USE), `0x800647d4` (empilhável na caixa) |
| +1 | u8 | **max** | capacidade/stack máximo do slot. Lido em `0x800684f4` (recarga), `0x800687c0` (upgrade), `0x80069cb8` (pegar item) |
| +2 | u8 | **bit** | índice de bit num bitfield em `gs+0x7910`, setado com `flag_set` quando você dá **CHECK** no item (`0x80069368`). Só é ≠0 em 17 key_items/chaves |
| +3 | u8 | **flags** | flags default gravadas no `hword+2` do slot ao criar/pegar o item |

Bits de `slot.flags` provados neste trabalho:

| bit | significado | prova |
|---|---|---|
| `0x0003` (ambos) | **munição infinita** — não decrementa | `0x800684dc`, `0x8006858c`, `0x800690a8` (`ori 3`), e o Gatling `0x0b` já vem com `0x03` |
| `0x0010` | o item tem a 4ª linha de comando | `0x8006694c`, `0x8006bd60`, `0x8006be04` |
| `0x0020` | ao USAR (cat 4/5/6) desequipa a arma antes da ação | `0x80067a48` |
| `0x0100` | 4ª linha mostra MANUAL (senão AUTO) | `0x8006bed8`, `0x8006956c` |
| `0xc000` | slot vazio/consumido (já estava em `exe_items.md`) | — |

Bits `0x04` e `0x08` aparecem nos defaults (0x05, 0x09, 0x0d, 0x12, 0x16) mas **NÃO MEDI** o que
fazem. Dump completo: `python tools/exe_combine.py`.

---

## 3. Comando 0 — USE / EQUIP (`0x800676b8`)

`cat = descritor[slot.id].cat`; se `cat-1 >= 6` → `ctx[0x11] = 3` (fecha, não faz nada — é o
caso de **arquivo (7) e mapa (8)**). Senão salta pela tabela **`0x80010e34`** (6 entradas):

| cat | destino | o que faz |
|---|---|---|
| 1 arma | `0x80067730` | **EQUIP** (abaixo) |
| 2 munição | `0x8006779c` | mensagem 5 ("não pode usar") e espera botão |
| 3 cura | `0x800677bc` | máquina de cura (§4) |
| 4 key_item | `0x80067a20` | usar item no contexto |
| 5 chave | `0x80067a20` | idem |
| 6 ferramenta | `0x80067a20` | idem |

### 3.1 EQUIP (`0x80067730`) — PROVADO
```
inv = *(gs+0x7c7c)
if inv[0x128] == ctx[0x1c]:            # já é a arma equipada -> DESEQUIPA
    inv[0x129] = 0
    inv[0x128] = 0xff
    MoveImage(dst=0x0a, src=0x0b)      # 0x0b = retângulo em branco -> apaga o ícone
else:
    inv[0x129] = slot.id               # id da arma equipada
    inv[0x128] = ctx[0x1c]             # ÍNDICE DO SLOT equipado
    MoveImage(dst=0x0a, src=inv[0x128])
ctx[0x11] = 3                          # fecha a lista
```
Não muda mais nada no estado do player aqui — o modelo/animação da arma é trocado por
`0x8004551c(a0 = 0x800ccbc4)` + `0x80046c90()`, chamados nos caminhos de USE (`0x80067ab4`) e
de combinação (`0x800690d8`), não no EQUIP.

### 3.2 Usar key_item / chave / ferramenta (`0x80067a20`)
```
if !flag_test(a0 = gs+0x2474 (=0x800ccbac), a1 = slot.id):
     mensagem 7 ("não pode usar aqui")
else:
     gs+0x7812 = slot.id                              # (u16) item que o script vai consumir
     if slot.flags & 0x20:
         ctx[0x2e]=1 ; ctx[0x2f]=inv[0x128] ; ctx[0x30]=inv[0x129]   # salva o equipamento
         inv[0x128]=0xff ; inv[0x129]=0                              # e desequipa
         gs+0x24d2 &= 0xff00 ; 0x80043ee4(gs+0x248c) ; 0x80043be4(gs+0x248c)
     ctx[0x10]++            # sai da tela de status; o script da sala continua
```
`gs+0x2474` é um bitfield de "itens usáveis aqui" mantido pelo script da sala.
**Quem preenche esse bitfield eu NÃO investiguei.**

---

## 4. USE em item de CURA — valores REAIS

Sub-máquina em `ctx+0x12`:
- `0x12 == 0`: `ctx[0x36] = 0`; se `id-0x20 < 0xb` salta pela tabela **`0x80010e4c`** (11
  entradas, `id-0x20`), que grava **`ctx[0x35]` = HP a curar** e **`ctx[0x36]` = curar veneno**,
  e põe `ctx[0x12] = 2`.
- `0x12 == 2` (`0x80067910`): `ctx[0x32] = -0x20`, `ctx[0x12] = 3`, `ctx[0x18] |= 0x00800000`
  (liga a animação de cura; `ctx[0x32]` avança **+3 por frame** enquanto esse bit está ligado —
  `0x8006e308` — até `>= 0x51`, ou seja **39 frames**).
- `0x12 == 3` (`0x80067934`): **aplica** (abaixo).
- `0x12 == 1`: mostra mensagem e espera o bit `0x80` de `0x800dbb58` cair; depois `ctx[0x11]=3`.

### 4.1 Tabela de efeito por item (`0x80010e4c`) — PROVADA

`maxHP = *(u16*)(gs+0x255a)`. `>>2` = `maxHP/4`, `>>1` = `maxHP/2`,
"cheio" = `(u8)maxHP` (**lbu**, então é o byte baixo de maxHP).

| id | item | handler | cura HP | cura veneno |
|---|---|---|---|---|
| `0x20` | F. Aid Spray | `0x800678e0` | **cheio** `(u8)maxHP` | **não** |
| `0x21` | Green Herb | `0x80067834` | **maxHP/4** | não |
| `0x22` | Blue Herb | `0x80067840` | **0** | **sim** |
| `0x23` | Red Herb | `0x80067858` | — | — (mensagem 7, não usa) |
| `0x24` | Mixed Herb (V+V) | `0x80067868` | **maxHP/2** | não |
| `0x25` | Mixed Herb (V+Azul) | `0x80067874` | **maxHP/4** | **sim** |
| `0x26` | Mixed Herb (V+Vermelha) | `0x800678e0` | **cheio** | não |
| `0x27` | Mixed Herb (V+V+V) | `0x800678e0` | **cheio** | não |
| `0x28` | Mixed Herb (V+V+Azul) | `0x80067894` | **maxHP/2** | **sim** |
| `0x29` | Mixed Herb (V+Verm+Azul) | `0x800678b4` | **cheio** | **sim** |
| `0x2a` | F. Aid Box | `0x800678d0` | **cheio** (se `qtd != 0`; senão mensagem 0xe) | não |

(A identificação "qual mistura é qual" vem de cruzar estes handlers com a tabela de receitas §5:
`0x21+0x21→0x24`, `0x21+0x22→0x25`, `0x21+0x23→0x26`, `0x21+0x24→0x27`,
`0x22+0x24→0x28` = `0x21+0x25`, `0x23+0x25→0x29` = `0x22+0x26`. Fecha com `0x22` = Blue Herb e
`0x23` = Red Herb do `re3_items.json`.)

### 4.2 Aplicação (`0x80067934`) — PROVADA
```
if ctx[0x32] < 0x51: return                       # espera a animação
if ctx[0x36]: gs[0x255e] &= ~0x0200               # cura o veneno
ctx[0x32] = -0x20 ; ctx[0x18] &= ~0x00800000
gs[0x2558] += ctx[0x35]                           # HP += cura   (u16)
gs[0x7e94] += ctx[0x35]                           # contador acumulado (u32)
if (s16)gs[0x255a] < (s16)gs[0x2558]: gs[0x2558] = gs[0x255a]   # clamp em maxHP
if slot.id == 0x2a:      slot.qty -= 1 ; ctx[0x11] = 2
else:                    slot = {0,0,0} ; MoveImage(dst=ctx[0x1c], src=0x0b)
                         ctx[0x11] = 0xa ; ctx[0x12] = ctx[0x1c] ; ctx[0x13] = 0
```

### 4.3 Limiares FINE / CAUTION / DANGER — `0x8006e598` (PROVADO)
```
st = gs[0x255e] ; hp = (s16)gs[0x2558]
if st & 0x0100 : return 5
if st & 0x0200 : return 4                 # POISON
if hp >= 101   : return 0                 # FINE
if hp >=  41   : return 1                 # CAUTION (amarelo)
if hp >=  21   : return 2                 # CAUTION (laranja)
               return 3                 # DANGER
```
Só um chamador: `0x8006e274`, que grava em `ctx+0x34`. O desenho usa
`retângulo = 0x800a0004 + estado*12` e `cor = 0x800a0150 + estado*6` (`0x8006ba34`, `0x8006c4c4`):

| est. | u | v | w | h | dx | dy | palavra na `STMOJIU` | RGB claro | RGB escuro |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 32 | 24 | 8 | 121 | 25 | `Fine` | `20 ff 20` | `01 08 01` |
| 1 | 24 | 32 | 40 | 8 | 113 | 25 | `Caution` | `ff ff 20` | `08 08 01` |
| 2 | 64 | 32 | 40 | 8 | 113 | 25 | `Caution` | `ff 80 20` | `08 04 01` |
| 3 | 104 | 32 | 40 | 8 | 113 | 25 | `Danger` | `ff 20 20` | `08 01 01` |
| 4 | 144 | 32 | 32 | 8 | 115 | 25 | `Poison` | `ff 20 ff` | `08 01 08` |
| 5 | 184 | 32 | 32 | 8 | 120 | 25 | **ilegível na textura** | `ff 20 ff` | `08 01 08` |

Há também `0x800a0174 + estado*4` → 5 tabelas de **0xa0 bytes** em `0x800a0cbc`, `0x800a0d5c`,
`0x800a0dfc`, `0x800a0e9c`, `0x800a0f3c` — pela forma (pares `x,y` pequenos) é a **onda do
eletrocardiograma** por estado. **NÃO decodifiquei o formato.**

---

## 5. COMBINE

### 5.1 Fluxo (`ctx[0x11] = 7`, dispatcher `0x80067b70` por `ctx+0x12`, tabela `0x800a0138`)

| `ctx[0x12]` | handler | o que é |
|---|---|---|
| 0 | `0x80067bac` | init: `ctx[0x1d] = ctx[0x1c]`, `ctx[0x118] = (idx&1)*40`, `ctx[0x18] \|= 0x22000000` |
| 1 | `0x80067c14` | **mover o 2º cursor e confirmar** |
| 2 | `0x80068a54` | esperar mensagem de erro; volta a `ctx[0x11]=3` |
| 3 | `0x80068bc0` | animação (5 frames) + **aplicação final** |
| 4 | `0x80068ab4` | espera mensagem e, se `gs+0x7848 == 0`, reexecuta `0x80068024` |
| 5 | `0x80068b5c` | espera a resposta em `0x800d1f80`; se `0` avança `ctx[0x58] += 8` (**próxima receita = munição "E"**, §5.6) e reexecuta `0x80068024` |

`ctx+0x1d` = **2º cursor** (o alvo da combinação). Mesmo passo de grade da §1.6, mas nos pares
`ctx+0x118/0x11a`:
```
ctx[0x118] = (ctx[0x1d] & 1) * 40
ctx[0x11a] = ((s8)ctx[0x1d] >> 1) * 30      # 0x80067fd0..0x80068000
```
Limites idênticos (`0x80067ecc..0x80067fb4`), usando `inv[0x12a] - 2` para BAIXO.

Ao CONFIRMAR (`0x80067cac`):
```
s1 = &INV[ctx[0x1c]] ; s2 = &INV[ctx[0x1d]]
rec = combine_find(s1->id, s2->id)          # 0x8006a898
ctx[0x48] = s1 ; ctx[0x4c] = s2 ; ctx[0x58] = rec
if rec == -1 or ctx[0x1c] == ctx[0x1d]:  som 7 (erro) e volta
kind = rec[0]
kind == 0 -> caso especial do Mine Thrower (§5.5) ; kind == 2 -> pré-cálculo de pólvora
outros    -> 0x80068024 (executor genérico)
```

### 5.2 A tabela — `0x800a07c4`, 8 bytes por registro, **125 registros**

Terminador: `rec[1] == 0xFF`, em `0x800a0bac`. Layout:

```
+0  u8  kind        0..6
+1  u8  A           item A
+2  u8  B           item B
+3  u8  C           item resultante (0 = nenhum item novo)
+4  u8  n           quantidade / parâmetro (depende do kind)
+5..+7              zero (padding)
```

**Algoritmo de busca — `0x8006a898 combine_find(a1=idA, a2=idB)`, LINEAR e SIMÉTRICO:**
```
rec = 0x800a07c4
while rec[1] != 0xFF:
    if rec[1]==idA and rec[2]==idB: return rec      # 0x8006a8bc..0x8006a8d8
    if rec[1]==idB and rec[2]==idA: return rec      # 0x8006a8dc..0x8006a8f8
    rec += 8
return -1
```
Não há índice nem matriz — é varredura na ordem do arquivo, então **a primeira receita que
casar ganha** (importante para as receitas duplicadas de kind 4, §5.4).

Tabela completa: `python tools/exe_combine.py` (texto) ou `port/data/re3_combinacoes.json`
(gerado por `python tools/exe_combine.py --json`). Resumo por `kind`:

| kind | dispatcher `0x80010e9c[kind]` | n registros | semântica |
|---|---|---|---|
| 0 | `0x800684dc` | **31** | recarregar arma **e** juntar pilhas |
| 1 | `0x800685cc` | **28** | A+B → C simples, quantidade `n` |
| 2 | `0x8006860c` | **21** | Reloading Tool + pólvora → munição |
| 3 | `0x800686ac` | **6** | upgrade/downgrade de arma |
| 4 | `0x80068854` | **12** | trocar o tipo de granada carregada |
| 5 | `0x800688d8` | **9** | pólvora + Grenade Rounds → outro tipo |
| 6 | `0x80068978` | **18** | arma + `Inf. Bullets` → munição infinita |

(Total 125. Contagem por `collections.Counter` sobre o JSON gerado.)

#### kind 0 — recarregar / empilhar (`0x800684dc`)
```
s3 = slot que contém A (fica) ; s0 = slot que contém B (é consumido)
if (s3->flags & 3) == 3: s3->qty = 0
cap = descritor[s3->id].max
if s3->qty >= cap:  mensagem 2 (se cat==1) ou 3 ; aborta
room = cap - s3->qty
if room >= s0->qty:  ctx[0x65] = s0->qty ; s0 = {0,0,0} ; ctx[0x64] = 1
else:                ctx[0x65] = room    ; if (s0->flags&3)!=3: s0->qty -= room ; ctx[0x64] = 2
ctx[0x12] = 3 ; som 6
```
Os 31 registros: **17** de `arma + munição`, **11** de `munição + a mesma munição`
(consolidar pilha), `Ink Ribbon + Ink Ribbon`, `Reloading Tool + Reloading Tool` e
**`F. Aid Box + F. Aid Spray`** (a caixa tem `max = 3`).

#### kind 1 — simples
```
s0 = {0,0,0} ; MoveImage(dst=cursor de s0, src=0x0b) ; carrega ícone de C (0x8006aa84)
ctx[0x64] = 0 ; ctx[0x12] = 3 ; som 6
# na aplicação (0x80068d14): s3->id = C ; s3->qty = n ; s3->flags = descritor[C].flags
```
As 33 receitas: 8 misturas de erva, 11 misturas de pólvora, e:
`Machine Oil + Oil Additive → Mixed Oil`, `0x35 + 0x3e → Fire Hose`,
`Lighter Oil + Lighter(0x42) → Lighter(0x43)`, `0x49 + 0x4b → 0x4a`,
`Gold Gear + Silver Gear → Chronos Gear`, `EAGLE Parts A + B → EAGLE 6.0 (n=15)`,
`M37 Parts A + B → Western Custom (n=6)`, `Clock T. Key(0x78) + Chronos Chain → Chronos Key`,
`Vaccine Medium + Vaccine Base → Vaccine`.
(`0x35`, `0x3e`, `0x49`, `0x4a`, `0x4b` aparecem como `BOTU`/sem nome no
`re3_items.json` — a lacuna é da tabela de nomes, não da tabela de receitas.)

#### kind 3 — upgrade/downgrade de arma (`0x800686ac`)
6 registros: `SIGPRO E + H.Gun Bullets → Merc's Handgun`, `M92F E + H.Gun Bullets → Hand Gun`,
`Benelli M3S E + Shotgun Shells → Shotgun`, e os três inversos com munição *E*.
```
if (s3->flags & 3) != 3:                    # arma normal
    if s3->qty != 0:  mensagem 8 ; ctx[0x12] = 2 ; som 7 ; ABORTA   (precisa estar vazia)
    else: vai para a transferência de munição (idêntica ao kind 0)
else:                                       # arma com munição infinita
    if s3->qty != 0:
        devolve a munição antiga: salto por 0x80010ebc[id-2] -> item_id
        (0x02→0x15, 0x03→0x15, 0x04→0x17, 0x11→0x1e, 0x12→0x1e, 0x13→0x1f;
         demais ids caem no "não devolve nada")
        ctx[0x64] = 7 ; ctx[0x65] = s0->qty ; ctx[0x12] = 3
```

#### kind 4 — trocar o tipo de granada (`0x80068854`)
12 registros. `A` = variante atual do lança-granadas (`0x06` normal, `0x07` flame,
`0x08` acid, `0x09` freeze), `B` = a munição nova, `C` = a variante resultante, e
**`n` = o `item_id` da munição ANTIGA que volta para o inventário**
(`0x18` grenade, `0x19` flame, `0x1a` acid, `0x1b` freeze).
```
if s3->qty == 0:  vai para o caminho "carrega direto" (ctx[0x64] = 1)
else:             0x8006aa84(rec[4]) ; ctx[0x64] = 5 ; ctx[0x65] = s0->qty ; ctx[0x12] = 3
# na aplicação (ctx[0x64]==5, cauda 0x800691a0): o slot da munição nova recebe rec[4]
# com quantidade = s3->qty (exatamente os cartuchos que estavam DENTRO do lançador),
# e s3 vira rec[3].
```
Como a busca é linear e simétrica (§5.2), as 12 receitas cobrem todas as 12 transições
`(variante atual) × (3 outras munições)`; a variante `A` no registro é a arma atual, então
não há ambiguidade com as receitas de kind 0 (`0x06+0x18`, `0x07+0x19`…) porque essas usam a
munição *da própria variante*.

#### kind 6 — munição infinita (`0x80068978`)
18 registros: `arma + 0x6e (Inf. Bullets) → nada`.
```
s0 = {0,0,0} ; MoveImage ; ctx[0x64] = 6 ; ctx[0x12] = 3
# aplicação (0x80069040): s3->flags |= 3
#   caso especial: se s3->id == 0x0c (Mine Thrower) -> id = 0x14 (M. Thrower E), flags = 7,
#   inv[0x129] = 0x14 e troca o modelo da arma (0x8004551c / 0x80046c90)
```

### 5.3 Qual slot sobrevive — regra PROVADA (`0x800683ec`..`0x8006846c`)
```
swap = (slotA.id != rec[1]) ? 1 : (slotA.id == rec[2])
if swap: s3 = &INV[ctx[0x1d]] ; s0 = &INV[ctx[0x1c]] ; s4 = &ctx[0x1d] ; s2 = &ctx[0x1c]
else:    s3 = &INV[ctx[0x1c]] ; s0 = &INV[ctx[0x1d]] ; s4 = &ctx[0x1c] ; s2 = &ctx[0x1d]
ctx[0x48]=s3 ; ctx[0x4c]=s0 ; ctx[0x58]=rec ; ctx[0x5c]=s4 ; ctx[0x60]=s2
ctx[0x50]=&descritor[s3->id] ; ctx[0x54]=&descritor[s0->id]
```
Em palavras: **o slot que contém o item `A` da receita é o que sobrevive e se transforma no
resultado; o slot que contém `B` é zerado.** Quando `rec[1] == rec[2]` (erva+erva, munição+
munição) `swap = 1`, ou seja sobrevive o slot **selecionado em 2º lugar** (`ctx[0x1d]`).
Para kind 2 e kind 5 o pré-cálculo escolhe `swap` explicitamente (§5.6/§5.7).

### 5.4 Munição das armas — `0x800a0bc4` (11 registros, 4 B, terminador `rec[0]==0xff`)
Busca linear por `rec[0]` em **`0x8006a95c ammo_for_weapon(a1=weapon_id)`**:
`0x02→0x15`, `0x03→0x15`, `0x04→0x17`, `0x05→0x16`, `0x0d→0x15`, `0x10→0x17`,
`0x11→0x1e`, `0x12→0x1e`, `0x13→0x1f`, `0x0e→0x1d`, `0x0f→0x1d`.
Só é usada pela **recarga rápida fora do menu** (§9). Note que o lança-granadas, o Mine Thrower
e o R. Launcher **não estão** nela.

### 5.5 Caso especial do Mine Thrower (kind 0, `0x80067dcc`)
Antes de chamar o executor genérico, se `rec[1] == 0x0c`:
```
s1 = o slot que tem o 0x0c
if s1->qty != 0:  mensagem 0xa ("não precisa"), ctx[0x12] = 2, som 7
else if 0x8004575c() != 0:  mensagem 9, ctx[0x12] = 4
else: 0x8004551c(gs+0x248c) ; 0x80046c90()   # troca o modelo, depois cai no genérico
```
`0x8004575c` **não investiguei** (retorna se o player está em algum estado que impede).

### 5.6 kind 2 — Reloading Tool + pólvora (pré-cálculo `0x80068080`)

21 registros. `A = 0x82` (Reloading Tool), `B` = a pólvora, `C` = a munição, `n` = quantidade
BASE. A quantidade final tem **bônus de perícia**:

```
grupo = 0x800a00ec[C]                                # tabela 2 B/reg, terminador 0xFF
cnt   = *(u16*)(inv + 0x12c + grupo*2)               # quantas vezes você já fez esse grupo
bloco = 0x800a0bf4 + grupo*20                        # 5 registros de 4 B {limiar, bonus}
i = 0 ; while i < 4 and bloco[i].limiar < cnt: i++
bonus = bloco[i].bonus                               # em DÉCIMOS
if C == 0x1e or C == 0x1f:                           # munição "E"
    bonus = 0x80010e7c[bonus]  ->  0/1/3 -> (mantém n cru) ; 2/4/6 -> (mantém n cru) ;
                                   5 -> bonus=3 ; 7 -> bonus=5 ; (0/1/3 -> bonus=1)
qty = n + (n*bonus)/10 ; se (n*bonus) % 10 >= 5 então qty += 1     # arredonda
ctx[0x65] = qty
if flag_test(0x800cc858, bit 0x17):  ctx[0x65] = qty * 2
inv[0x12c + grupo*2] += 1
```

Grupos (`0x800a00ec`): `0x15`→0, `0x1e`→0, `0x17`→1, `0x1f`→1, `0x16`→2,
`0x18`→3, `0x1a`→3, `0x19`→3, `0x1b`→3.

Tabela de bônus (`0x800a0bf4`) — **os 4 blocos são idênticos**:
`cnt<=2: +0%` · `cnt<=5: +10%` · `cnt<=10: +30%` · `cnt<=20: +50%` · `cnt<=250: +70%`.

#### A PERGUNTA "munição normal ou melhorada?" — receitas DUPLICADAS (achado importante)

A tabela tem **8 pares de registros com a MESMA chave (A,B)** e resultados diferentes:

| A | B | 1º registro (normal) | 2º registro (melhorada) | n |
|---|---|---|---|---|
| `0x82` | `0x61` Gun Powder A | `0x15` H. Gun Bullets | `0x1e` H.G. Bullets E | 15 |
| `0x82` | `0x64` Gun Powder AA | `0x15` | `0x1e` | 35 |
| `0x82` | `0x69` Gun Powder AAA | `0x15` | `0x1e` | 55 |
| `0x82` | `0x6b` Gun Powder BBA | `0x15` | `0x1e` | 60 |
| `0x82` | `0x62` Gun Powder B | `0x17` Shotgun Shells | `0x1f` S.G. Shell E | 7 |
| `0x82` | `0x65` Gun Powder BB | `0x17` | `0x1f` | 18 |
| `0x82` | `0x6a` Gun Powder AAB | `0x17` | `0x1f` | 20 |
| `0x82` | `0x6c` Gun Powder BBB | `0x17` | `0x1f` | 30 |

Como a busca é linear, `combine_find` sempre devolve o **1º** (a munição normal). O 2º é
alcançado por um **incremento explícito do ponteiro de receita**:
```
# 0x80067d80..0x80067e38  (só quando grupo é 0 ou 1, isto é a0 == 6)
cnt = *(u16*)(inv + 0x12c + grupo*2)
if cnt > 6:                              # slt a0(=6), cnt
    mensagem(a1 = 0x1400, a2 = 0xd)      # PERGUNTA
    ctx[0x12] = 5 ; ctx[0x18] &= ~0x20000000
# 0x80068b5c  (ctx[0x12] == 5)
espera o bit 0x80 de 0x800dbb58 cair
resposta = *(s16*)0x800d1f80
if resposta == 0:  ctx[0x58] += 8 ; 0x80068024(ctx)   # usa o PRÓXIMO registro = versão "E"
if resposta == 1:                 0x80068024(ctx)     # usa o registro atual = normal
```
Ou seja: **depois de fabricar mais de 6 lotes daquele grupo (só grupos 0 = pistola e
1 = escopeta, os únicos com variante "E"), o jogo pergunta e o 2º registro do par é usado**.
Os grupos 2 (magnum) e 3 (granada) têm `a0 = 0` e nunca perguntam — coerente, não existe
munição "E" para eles. As contagens fecham: 8 pares (16 registros) + 5 receitas únicas
(`0x63→0x18`, `0x66→0x19`, `0x67→0x1a`, `0x68→0x1b`, `0x6d→0x16`) = **21 registros de kind 2**.

`ctx[0x12] = 4` (`0x80068ab4`) é o mesmo mecanismo para a pergunta do Mine Thrower (§5.5),
mas lendo a resposta em `gs+0x7848`: `0` = prossegue (troca o modelo e reexecuta `0x80068024`),
`1` = aborta (`ctx[0x11] = 3`).

Sobre `flag_test(0x800cc858, 0x17)` que **DOBRA** a quantidade: `0x800cc858` é o banco 0 da
tabela `0x8009e3f8`. **NÃO descobri quem seta o bit 0x17** — minha hipótese (dificuldade EASY)
NÃO está provada; trate como flag externa.

Sobre o remap `0x80010e7c[bonus]` para as munições E: os alvos são labels
(`0x80068140` → `bonus=1`, `0x80068148` → `bonus=3`, `0x80068150` → `bonus=5`,
`0x80068154` → sem alteração). Mapa por índice: `0→1, 1→1, 2→(nada), 3→1, 4→(nada), 5→3,
6→(nada), 7→5`. Como o `bonus` cru só vale 0/1/3/5/7, o efeito prático é
`0→1, 1→1, 3→1, 5→3, 7→5` — ou seja **munição E ganha um bônus MENOR**.

Consumo (handler `0x8006860c`, decidido por `ctx[0x64]`, calculado em `0x8006821c`):
```
tool = o slot que tem 0x82
ctx[0x64] = (tool->qty == 1) ? 3 : 4
swap escolhido de modo que s0 (o consumido) seja SEMPRE o slot da FERRAMENTA
ctx[0x64]==3 -> s0 = {0,0,0} (acabou a ferramenta) ; ctx[0x64]==4 -> s0->qty -= 1
em ambos: s3 (o outro slot) recebe a munição criada
```
Isto é, **o Reloading Tool perde 1 unidade por craft** e o slot da pólvora vira a munição
(ou, se a ferramenta era a última, o slot da ferramenta vira a munição e o da pólvora
esvazia). Está no binário; se contradiz alguma FAQ, o binário manda.

### 5.7 kind 5 — pólvora + Grenade Rounds (pré-cálculo `0x80068264`)
9 registros. `A = 0x18` (Grenade Rounds), `B` = pólvora, `C` = a nova munição, `n` = base.
```
usa SEMPRE o bloco 3 (0x800a0bf4 + 0x3c) e o contador inv+0x132  (= grupo 3)
bonus e arredondamento idênticos ao kind 2 ; flag 0x17 idem ; inv[0x132] += 1
rounds = qty de 0x18 no slot
if rounds >= 7:  ctx[0x64] = 4  -> s0->qty -= 6            # consome 6 unidades
else:            ctx[0x64] = 3  -> s0 = {0,0,0}
                 ctx[0x65] = (ctx[0x65] * rounds) / 6      # proporcional (0x2aaaaaab = 1/6)
```

### 5.8 Aplicação final (`0x80068bc0`) — animação e escrita

`s2 = ctx[0x48]` (slot que sobrevive), `s3 = ctx[0x5c]` (ponteiro para o cursor dele),
`s4 = ctx[0x60]` (ponteiro para o cursor do consumido), `s5 = ctx[0x58]` (registro).

Animação: enquanto `ctx[0x13] < 5` (**5 frames**), soma `ctx[0x66]`/`ctx[0x68]` nos pares de
cursor. Os deltas são calculados em `0x800689b4`:
```
ctx[0x66] = ((*s4 & 1) - (*s2 & 1)) * 8         # (colA - colB) * 8   -> 5 frames × 8 = 40
ctx[0x68] = ((*s4 >> 1) - (*s2 >> 1)) * 6       # (linA - linB) * 6   -> 5 frames × 6 = 30
```
Casa exatamente com o passo de grade 40×30. Qual par recebe o delta depende de `s2->id`:
`0xff` → `ctx[0x118]/0x11a` **e** `ctx[0x114]/0x116`; `s4 == ctx[0x60]` → só `0x118/0x11a`;
senão só `0x114/0x116` (`0x80068c18`..`0x80068ca0`).

Depois, salto por **`0x80010f04[ctx[0x64]]`** (8 entradas):

| `ctx[0x64]` | destino | `ctx[0x11]` | efeito |
|---|---|---|---|
| 0 | `0x80068d14` | `0xa` | `s2->id = rec[3]`, `s2->qty = rec[4]`, `s2->flags = descritor[rec[3]].flags`. Se `flag_test(0x800d1f30, 9)` **e** o resultado é `0x0d` ou `0x10` → `flags \|= 3` (munição infinita) |
| 1 | `0x80068de0` | `0xa` | se `kind ∈ {3,4}` → cauda `0x80068ec0`; senão cauda `0x80068f18`: **`s2->qty += ctx[0x65]`** |
| 2 | `0x80068e60` | `3` | idem ao 1 (recarga parcial), sem popup |
| 3 | `0x80068f30` | `0xa` | `s2->id = rec[3]`, `s2->qty = ctx[0x65]`, `s2->flags = descritor[rec[3]].flags`, `LoadImage(*s3)` |
| 4 | `0x80068f4c` | `3` | igual ao 3, sem popup |
| 5 | `0x80068fe4` | `3` | `consumido->id = rec[4]` (munição antiga volta) + cauda `0x800691a0` |
| 6 | `0x80069040` | `0xa` | `s2->flags \|= 3`; se `s2->id == 0x0c` → `0x14 M. Thrower E`, `flags = 7`, `inv[0x129] = 0x14`, troca o modelo |
| 7 | `0x800690f0` | `3` | `consumido->id = 0x80010f24[s2->id - 2]` (`0x02/0x03→0x15`, `0x04→0x17`, `0x11/0x12→0x1e`, `0x13→0x1f`, demais → nada) + cauda `0x800691a0` |

Caudas comuns:
```
0x80068ec0  (kind 3/4 no ctx[0x64]==1/2)
    s2->id    = rec[3]
    s2->flags = (s2->flags & 0xff00) | descritor[rec[3]].flags
    if inv[0x128] == *s3:  inv[0x129] = rec[3]

0x80068f18  (kind 0 no ctx[0x64]==1/2)
    s2->qty += ctx[0x65]

0x800691a0  (ctx[0x64]==5 e 7; `a0` = ctx[0x4c] = slot CONSUMIDO)
    a0->flags = (a0->flags & 0xff00) | descritor[a0->id].flags
    a0->qty   = s2->qty                  # devolve a munição que estava DENTRO da arma
    LoadImage(*s4)
    s2->id    = rec[3]
    s2->flags = (s2->flags & 0xff00) | descritor[rec[3]].flags
    if inv[0x128] == *s3:  inv[0x129] = rec[3]
```

`ctx[0x11] = 0xa` = estado 10 (`0x80069a6c`) = **popup "obteve N × item"**; eu não desmontei
esse popup por dentro (**NÃO MEDIDO**: seus textos e coordenadas).

### 5.9 Tabela auxiliar `0x800a0bb4` — transformação por item
4 B por registro, terminador `rec[1]==0xff`, busca linear por `rec[1]` em **`0x8006a918`**
(chamada em `0x80069400` e `0x800694bc`, dentro da tela de ARQUIVO/CHECK):
`{0, 0x37 Card Case → 0x38 S.T.A.R.S. Card, 0}` ·
`{1, 0x83 Game Inst. A → 0x85 Game Instructions A, 0}` ·
`{1, 0x84 Game Inst. B → 0xa1 Game Instructions B, 1}`.
O significado exato de `rec[0]`/`rec[3]` **NÃO MEDI**.

---

## 6. Comando 2 — CHECK (`0x80069280`)

Sub-máquina em `ctx+0x12`:
- 0: `0x8006ac88(a0 = slot.id)` (carrega o gráfico grande do item), `ctx[0x3e]=0`, `ctx[0x13]=0`.
- 1: enquanto `ctx[0x13] < 0xc` (**12 frames**) `ctx[0x104] += 0x12` (=+18) → o painel de
  descrição entra de `-0xd8` (=-216) até 0 (12 × 18 = 216 ✓). No frame 12:
  ```
  flag_set(a0 = gs+0x7910, a1 = descritor[slot.id].bit)      # 0x80069368
  mensagem(a1 = 0x1100, a2 = slot.id + 0x10)                 # 0x80069380  -> texto de EXAME
  ```
- 2/3: `0x800693cc` / `0x80069480` — fecham (chamam `0x80069614(a1=1)`).

O `+0x10` no índice de mensagem **confirma** o mapeamento `exame_idx = item_id + 16` que o
`re3_items.json` já usava.

---

## 7. Comando 3 — AUTO / MANUAL (`0x8006954c`) — só o Assault Rifle

```
slot = &INV[ctx[0x1c]] ; old_flags = slot->flags ; old_id = slot->id
if slot->flags & 0x100:  slot->flags &= ~0x100 ; slot->id = 0x0f
else:                    slot->flags |=  0x100 ; slot->id = 0x0e
slot->flags = (slot->flags & 0xff00) | descritor[slot->id].flags     # recarrega o byte baixo
if (old_flags & 3) == 3: slot->flags |= 3                            # preserva infinito
if old_id == inv[0x129] and ctx[0x1c] == inv[0x128]:  inv[0x129] = slot->id
ctx[0x11] = 2                                                        # volta para a lista
```
Ou seja é um **toggle entre os item_ids `0x0e` e `0x0f`** (os dois "Assault Rifle"), que
o `player`/combate vê como duas armas diferentes. O rótulo desenhado depende de
`flags & 0x100` (§1.2/§1.3) — e como os dois ids nascem com `0x100` limpo, o rótulo inicial é
sempre `AUTO`. **NÃO MEDI** o que muda no comportamento de tiro (isso está no módulo de combate).

---

## 8. DESCARTAR / REORDENAR e a CAIXA DE ITENS

### 8.1 Não existe DESCARTAR nem reordenar dentro do inventário principal
Provado por exaustão: o handler de navegação `0x80066604` só reage a CONFIRMAR, CANCELAR e
d-pad; a lista de comandos tem no máximo 4 linhas e as 4 estão identificadas (§1.2); a 5ª
posição de rótulo (`PIECES`) nunca é colocada. Não há nenhuma outra transição de `ctx[0x11]`
a partir dos estados 0/1/2. **Não há botão de jogar item fora nem de trocar dois slots de
lugar na tela normal.**

### 8.2 A CAIXA existe: 64 slots em `inv + 0x28`
- **Onde:** `sce == 9` na jump-table de AOT `0x8009e0bc` → `0x800514c4`:
  ```
  *(u8*)0x800e01c4 = 2          # MODO 2 da tela de status
  gs+0x75e0 = 0x800514f0        # driver da tela da caixa
  gs+0x75db = 0
  ```
  (`sce == 8` → `0x80051388` é a **máquina de escrever**: instala o driver `0x800513cc`, que
  faz `find_by_id(0x81 = Ink Ribbon)` e pede confirmação de save.)
- **Modo → estado externo** (`0x80011064`): modo 0/1 → estado 1 (inventário normal),
  **modo 2 → estado 0xa (`0x800643e4`)**, modo 3 → estado 7, modo 4/5 → estado 4.
- **Modo → rotina de desenho** (`0x8001104c`): modo 0/1 → `0x8006b66c`;
  **modo 2 → `0x800654a8`** (usa a tabela de retângulos A, `0x8009f2ec`); modo 3 → `0x80063fe4`;
  modo 4/5 → `0x80070244`.
- **Estado 11 (`0x80064424`)** despacha `handlers[ctx[0x11]]` pela tabela `0x8009f4e4`
  (5 entradas: `0x8006446c`, `0x800646f0`, `0x80064e80`, `0x80065054`, `0x800650bc`).
- **Cursor da caixa = `ctx+0x1f`**, 0..63, passo de **±2** com wrap
  (`0x80064b88`: `if (s8)(idx) >= 0x40 → 0`; `0x80064bb0`: `if (s8)(idx+2) >= 0x40 → idx-0x3e`).
- **Endereçamento:** `MAIN[i] = inv + i*4` e `BOX[j] = inv + 0x28 + j*4`
  (`0x80064820` `addiu $v0, $v0, 0x28`; `0x80064c2c` `lbu $a1, 0x28($s1)`).
  Confirma o layout de `exe_items.md` §2.1 (MAIN 10 slots em +0, BOX 64 slots em +0x28).
- **Empilhar na troca** (`0x800647d4`): só é permitido se `descritor[id].cat ∈ {2, 5, 6}`
  (munição, chave, ferramenta) e `qtdA + qtdB <= descritor.max`; há um caso à parte para
  `0x20 F. Aid Spray` + `0x2a F. Aid Box`.
- Ao mexer na caixa, se o slot movido era o equipado, o código desequipa
  (`0x800647ac` `inv[0x129] = 0`, `inv[0x128] = 0xff`).

Portanto **é na tela da caixa que se "descarta"/reorganiza**: você move itens entre MAIN e BOX.
O interior dessa tela (coordenadas, grade, textos) **está fora do que eu medi** — só provei
a porta de entrada, o cursor e o endereçamento dos slots.

---

## 9. Recarga rápida fora do menu — `0x8006cf0c` (corrige `exe_items.md` §2.2)

```
inv = *(gs+0x7c7c)
if inv[0x128] == 0xff: return -1                        # nada equipado
r = ammo_for_weapon(inv[0x129])                         # 0x8006a95c / tabela 0x800a0bc4
if r == -1: return -1
src = find_by_id(r[1], 0)                               # 0x8006cc8c
if src == -1: return -1
wslot = &inv[inv[0x128] * 4]                            # slot da ARMA EQUIPADA
room  = descritor[wslot->id].max - wslot->qty
... transfere de src para wslot, remove src se esgotar (0x8006ccf0)
gs+0x255e (ver 0x8006d004/0x8006d010) e gs+0x255e |= flag de UI
```
`0x8006cf0c` é chamado de 6 lugares no módulo de combate/player
(`0x8003f160`, `0x8003f684`, `0x8003fd60`, `0x8004026c`, `0x800406dc`, `0x80040898`) — é o
**R1/recarregar durante o jogo**, não "consolidar pilha no menu". E `inv+0x128` é
inequivocamente o **índice do slot equipado**.

---

## 10. Como medir de novo

```bash
# tabelas de combinação (texto e JSON)
PYTHONIOENCODING=utf-8 python tools/exe_combine.py
PYTHONIOENCODING=utf-8 python tools/exe_combine.py --json

# textura dos rótulos
PYTHONIOENCODING=utf-8 python tools/tim2png.py /tmp/out \
    extracted/ntsc-u/CD_DATA/ETC/STMOJIU.TIM
# depois recorte (u,v,w,h) de cada rótulo da §1.2

# retângulos do menu
PYTHONIOENCODING=utf-8 python tools/status_layout.py rects
PYTHONIOENCODING=utf-8 python tools/status_layout.py calls

# desassemblar qualquer coisa citada aqui
PYTHONIOENCODING=utf-8 python -c "
import sys; sys.path.insert(0,'tools')
from exe_parse import Exe
e = Exe('extracted/ntsc-u/SLUS_009.23'); e.disasm(0x80066920, 90)"
```

**Atenção ao usar `exe_parse`:** `Exe.find_hi_lo_refs()` e `Exe.disasm_all()` usam
`capstone.disasm()` sobre o `.text` inteiro, que **para na primeira palavra inválida** (o
`.text` do RE3 mistura código e dados) e por isso devolvem resultados vazios/truncados. Para
achar referências `lui`+`lo` de verdade, decodifique palavra por palavra (op = `w >> 26`;
`lui` = 0x0f, `addiu` = 0x09, `lw` = 0x23, …). Foi assim que localizei todas as tabelas desta
nota; o script está reproduzido no bloco abaixo.

```python
import struct, sys
sys.path.insert(0, 'tools')
from exe_parse import Exe
E = Exe('extracted/ntsc-u/SLUS_009.23')
W = struct.unpack('<%dI' % (len(E.text)//4), E.text[:len(E.text)//4*4])
LO = {0x09:'addiu',0x0d:'ori',0x23:'lw',0x2b:'sw',0x24:'lbu',0x25:'lhu',0x28:'sb',0x29:'sh'}
last = [None]*32
ALVO = 0x800a07c4
for i, x in enumerate(W):
    op = x >> 26
    if op == 0x0f:
        last[(x >> 16) & 31] = (E.base + i*4, x & 0xffff)
    elif op in LO:
        rs, rt, imm = (x >> 21) & 31, (x >> 16) & 31, x & 0xffff
        if imm >= 0x8000: imm -= 0x10000
        if last[rs]:
            _, hi = last[rs]
            if ((hi << 16) + imm) & 0xffffffff == ALVO:
                print('%08x %s' % (E.base + i*4, LO[op]))
        if op in (0x09, 0x0d):
            if rt != rs: last[rt] = None
        else:
            last[rt] = None
```

---

## 11. EM ABERTO (não medido / não provado)

1. **Popup "obteve N × item"** (`ctx[0x11] = 0xa`, handler `0x80069a6c`): não desmontei. Textos,
   coordenadas e duração NÃO MEDIDOS.
2. **Página de textura dos POLY_FT4** de sombra das linhas de comando (registros
   `0x8009fe6c..0x8009ff28`, `v` = 184..216): não é a `STMOJIU` (72 px de altura). NÃO SEI qual é.
3. **Quem seta `flag_test(0x800cc858, bit 0x17)`** que DOBRA a quantidade de munição criada com
   pólvora. Hipótese "dificuldade EASY" **NÃO PROVADA**.
4. **Bits `0x04` e `0x08` de `slot.flags`**: aparecem nos defaults do descritor (0x05/0x09/0x0d/
   0x12/0x16) mas não achei quem os lê. NÃO MEDIDO.
5. **`gs+0x2474` (`0x800ccbac`)**: bitfield "item usável aqui" testado no USE de key_item.
   Quem escreve nele (que opcode SCD) NÃO INVESTIGUEI.
6. **`0x8004575c`** (guarda do caso Mine Thrower) e **`0x80043ee4`/`0x80043be4`/`0x8004551c`/
   `0x80046c90`** (troca de modelo/animação da arma): identificados por posição, não decompilados.
7. **Estado de saúde 5** (`gs[0x255e] & 0x100`): a palavra na textura em `u=184 v=32` está
   ilegível no dump; NÃO SEI o que é nem quem seta esse bit.
8. **Tabelas de `0xa0` bytes em `0x800a0cbc`/`0x800a0d5c`/`0x800a0dfc`/`0x800a0e9c`/`0x800a0f3c`**
   (uma por estado de saúde, apontadas por `0x800a0174 + estado*4`): provavelmente a onda do
   ECG. Formato NÃO DECODIFICADO.
9. **Tabela VRAM de slot `0x800a004c`** (24 registros `{u16 x, u16 y}`, retângulo 20×30 em
   halfwords): provei que os índices 0..11 são usados como origem/destino de `MoveImage`/
   `LoadImage` pelo código do inventário (0..9 = um por slot MAIN, 0x0a = ícone da arma
   equipada, 0x0b = retângulo em branco). Os índices 12..23 (incluindo o bloco em x=226/266,
   y=84..204 com passo 40×30) NÃO SEI quem usa. Valores brutos:
   `(640,328) (660,328) (640,358) (660,358) (640,388) (660,388) (640,418) (660,418)
   (680,328) (680,358) (680,388) (680,418) (448,328) (226,84) (266,84) (226,114) (266,114)
   (226,144) (266,144) (226,174) (266,174) (226,204) (266,204) (174,55)`.
10. **Arquivo do CD de índice `0x34`** usado por `0x8006aa84` para streamar o ícone do item
    novo (`lba = filetab[0x34].lba + item_id`, 1 setor). Não conferi qual arquivo é, e isso
    aparentemente conflita com o stride de 10240 B de `ETC/ITEMG.PIX` documentado em
    `menus.md` — **precisa de uma segunda passada**.
11. **Interior das telas de ARQUIVO (estado externo 4), MAPA (5) e CAIXA (11)**: fora de escopo.
12. Índices exatos de mensagem (2/3/5/7/8/9/0xa/0xd/0xe) → texto: não cruzei com
    `port/data/re3_messages.json`. Os números estão aqui, a tradução não.
