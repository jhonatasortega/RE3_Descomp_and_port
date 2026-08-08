# Tela de STATUS / INVENTÁRIO — geometria exata (RE3 PS1 NTSC-U, `SLUS_009.23`)

**Alvo:** `extracted/ntsc-u/SLUS_009.23` (PS-X EXE, base `0x80010000`).
**Ferramenta desta nota:** [`tools/status_layout.py`](../../../tools/status_layout.py)
(`rects` / `calls` / `slots` / `sld` / `json`).
**Espaço de coordenadas de TODA coordenada de tela desta nota: pixels de tela 320×240**
(um único framebuffer por campo; o jogo é 320×240 NTSC — não há 640×480 aqui).
Todos os campos `u16`/`s16` estão indicados; `x`/`y` de tela são `u16` somados a uma base `s16`.

> **A tela de status NÃO é um overlay de `BIN/*.BIN`.** Ela é uma **task do EXE principal**.
> `PC_SYS.BIN`, `MEM_CARD.BIN` etc. não têm nada a ver com ela. Se você procurou nos overlays,
> procurou no lugar errado (foi o erro da rodada anterior).

---

## 0. Sumário dos números que o implementador precisa

| coisa | valor | prova |
|---|---|---|
| Grade de itens | **2 colunas × 5 linhas**, célula **40×30 px**, origem da célula 0 = **(224, 66)**, passo coluna **+40**, passo linha **+30** | `0x8009F9D4` (rect 80×120 em (224,66)) + `0x8009F9E0/EC` + fórmula do cursor em `0x800668A4`–`0x800668CC` |
| Nº de slots visíveis | **`*(u8*)(inv+0x12a)`** (8 ou 10 — é dado de save, não constante) | laço de quantidade `0x8006C0C0` (`sltu $v1,$s1,*(u8*)0x800D225E`); nav. baixo `0x800667C4` |
| Slots do array | 10 no principal (`inv+0x00`) + 64 na caixa (`inv+0x28`) | laço de 10 em `0x8006D89C`; `inv+slot*4+0x28` em `0x80064C2C`; `0x128 = 40+256` |
| Ícone do item | **40×30 px, 8bpp**, de `ETC/ITEMA.SLD` **comprimido**, offset por `item_id` na tabela `0x8009F678` | `0x8006AB68` (`LoadImage` rect 20 words × 30 linhas) |
| Quantidade "N" | dígitos **8×11 px** do atlas `ETC/STMOJIU.TIM` em **u = 4 + dígito·8, v = 19**, avanço **8 px**, 3 dígitos com supressão de zero, posição por slot em `0x800A0080` (célula + (2,18)) | `0x8006C910`–`0x8006C9A0` |
| Cursor | retângulo vazado 40×30 do `STMOJIU` em **u=120, v=0**; pisca modulando RGB de 128→191 em passos de 2/frame (ciclo 64 frames) | rect `0x8009FF68`; `0x8006E290`–`0x8006E2F0` (contador) + `0x8006B6D0`–`0x8006B6FC` (cor) |
| Arma equipada | mostrada como **ícone 40×30 em (172, 37)**, dentro do quadro "EQUIP" 64×64 em (160,16); slot em `inv+0x128`, item_id em `inv+0x129` | rect `0x8009FBC0`; `0x8006D8B8`; gráfico "EQUIP" em `STMAIN0U` |
| Condição | `0x8006E598`: **VÍRUS** se `flags&0x100`; **Poison** se `flags&0x200`; senão **Fine** hp≥101, **Caution** 41..100, **Caution(2)** 21..40, **Danger** ≤20 | disasm `0x8006E598`–`0x8006E5F8`; palavras lidas em `STMOJIU` v=32 |
| HP / status | `s16 hp = *(s16*)0x800CCC90`, `s16 hp_max = 0x800CCC92`, `u16 flags = 0x800CCC96` | `0x8006E5A0`/`0x8006E5A4` |
| "Nome/descrição" do item | **não é texto** — é a placa **112×72 de `ETC/ITEMG.PIX`** (índice = item_id) desenhada em **(56, 88)** | rect `0x8009FBA8`; `0x8006AC88` (lba + item_id·5, 10240 B) |
| Fundo/moldura | **composto** de ~160 retângulos de `ETC/STMAIN0U.TIM` (256×272 8bpp, 4 CLUTs) + `ETC/STMOJIU.TIM` (256×72 4bpp, 9 CLUTs). Não existe uma imagem de tela cheia. | tabelas de retângulo `0x8009F890` e `0x8009F2EC` |

---

## 1. Onde a tela vive

```
task entry     0x8006DFDC          (nenhum xref: é registrada como task)
contexto       0x800E01C0          ("ctx" no resto da nota)
init           0x8006D948(ctx)
loop           st = *(u8*)(ctx+0x10);
               handlers[st](ctx);          # handlers = 0x800A02F0, 14 entradas
               0x8006E268(ctx);            # update (piscada, condição, arma)
               0x8006E34C(ctx);            # DESENHO (despacho por modo)
               0x80073E7C(ctx);
               yield(1)                    # 0x8003203c
               while (*(u8*)(ctx+0x27))
saída          0x8006E0A4(ctx); 0x80032070()
```

### 1.1 Carga dos gráficos — `0x8006D720` (chamada de `0x80024764`)

```
if (flag_test(0x800CC858, 0x18)) {                   # 0x80078930
    ch = *(u8*)0x800CCC0E;                           # id do personagem
    if (ch == 8)  idx = 0x5A   # ETC/STMAIN1U.TIM
    if (ch == 9)  idx = 0x5C   # ETC/STMAIN2U.TIM
    if (ch == 10) idx = 0x5E   # ETC/STMAIN3U.TIM
    else          (não carrega nada)
} else            idx = 0x58   # ETC/STMAIN0U.TIM   <- Jill, caso normal
cd_read_file(idx, 0x801B1500, 0, "STMAIN0.TIM")
*(u16*)0x800CCBBC = 0x041A;  load_tim_vram(0x801B1500)     # 0x800784E0
cd_read_file(0x60, 0x801B1500, 0, "STMOJI.TIM")            # ETC/STMOJIU.TIM
*(u16*)0x800CCBBC = 0x001A;  load_tim_vram(0x801B1500)
cd_read_file(0x32, 0x801B1500, 0, "ITEMA.SLD")             # ETC/ITEMA.SLD
for (i = 0; i < 10; i++)                                   # 10 SLOTS
    icon_upload(i, inv[i].id, 0x801B1500, 0x801B1000);     # 0x8006AB68
if (inv[0x128] != 0xFF) vram_copy_icon(10, inv[0x128]);    # 0x8006AE20
ctx+0x28 = inv[0x129];  ctx+0x29 = *(u8*)0x800CCC0E;
ctx+0xd0..0xd8 = {4,5,6,0,8,0x0e,0,0x0a,9}                 # índices de CLUT
```

`0x800784E0 = load_tim_vram(a0 = ponteiro do TIM)` — provado por `OpenTIM(0x8008DBE4)` +
`ReadTIM(0x8008DBF4)` + `LoadImage(0x8008B2AC)`:

```
tagX = *(u8*)0x800CCBBC;  tagY = *(u8*)0x800CCBBD
prect->x = (tagX >= 0x10) ? tagX*64 - 1024 : tagX*64
prect->y = (tagX >= 0x10) ? 256 : 0
LoadImage(prect, paddr);        tagX += (prect->w + 63) >> 6
if (caddr) { crect->y = tagY + 480;  LoadImage(crect, caddr);  tagY += crect->h }
   # crect->x NÃO é tocado: vem do arquivo TIM
```

**Mapa de VRAM resultante (medido, não suposto):**

| região VRAM (palavras x, linhas y) | conteúdo | página de textura |
|---|---|---|
| `x 640..767, y 256..527` | `STMAIN0U.TIM` cru (256×272 px 8bpp) — a metade esquerda é **sobrescrita** logo depois | `0x9A` (x=640) / `0x9B` (x=704) |
| `x 640..703, y 256..327` | `STMOJIU.TIM` (256×72 px 4bpp) — sobrescreve o topo-esquerdo do STMAIN | `0x3A` (4bpp, x=640, semitransp.) / `0x17` |
| `x 640..699, y 328..447` | **12 ícones de item 40×30 8bpp** (tabela `0x800A004C`) | `0x9A` |
| `x 448..503, y 256..327` | placa 112×72 de `ITEMG.PIX` do item selecionado | `0x97` (8bpp, x=448) |
| `x 448..467, y 256..495` | 8 ícones 40×30 (tela de caixa; tabela `0x8009F4F8`) | `0x97` |
| CLUT `x 0..255, y 484..487` | 4 paletas do `STMAIN0U` | — |
| CLUT `x 304..319, y 480..488` | 9 paletas do `STMOJIU` | — |

Confirmação visual independente: em `port/assets/ETC/STMAIN0U.png` o retângulo
`x 0..127, y 0..191` é **cinza chapado** (placeholder) — exatamente a área que o
STMOJI e os ícones sobrescrevem em VRAM.

### 1.2 Modo e estado

`ctx+0x04` = **modo**. Setado de fora: `0x80051174` (modo 1, abrir status pelo gameplay),
`0x800514CC` (modo 2), `0x8005123C`, `0x80051AC0`, `0x8003B128`, `0x80023CD0`, `0x80058C88`.

| modo | estado inicial (tab. `0x80011064`) | rotina de desenho (tab. `0x8001104C`) | tela |
|---|---|---|---|
| 0, 1 | 1 (`0x80066530`) | `0x8006E3C0` → `0x8006B66C` | **STATUS / INVENTÁRIO** |
| 2 | 10 (`0x800643E4`) | `0x8006E3B0` → `0x800654A8` | caixa de itens (item box) |
| 3 | 7 (`0x800636D4`) | `0x8006E3F8` → `0x80063FE4` | FILE (arquivos; carrega `FILEG.PIX`/`FILEI.TIM`) |
| 4, 5 | 4 (`0x8006ED98`) | `0x8006E38C` → `0x80070244` | MAPA (carrega `ETC/MAP_U.MAP` em `0x800714AC`) |

Handlers por estado — `0x800A02F0`, 14 entradas:
`0x8006E424, 0x80066530, 0x800665C8, 0x8006A888, 0x8006ED98, 0x8006F6CC, 0x80070024,
0x800636D4, 0x80063850, 0x80063CAC, 0x800643E4, 0x80064424, 0x80064460, 0x8006E4CC`.
(A partir do índice 14 a memória já é texto de glifo, não ponteiro — a tabela tem
exatamente 14 entradas.)

Máscaras de `ctx+0x18` que ligam cada desenho:
`0x40000000` = status, `0x00200000` = mapa, `0x00100000` = FILE,
`0x02000000` = 2º marcador de seleção, `0x00400000` = `0x8006C370`.

---

## 2. O FORMATO que resolve tudo: registro de retângulo de 12 bytes

Existem **duas** tabelas de registros de 12 bytes:

* **Tabela A** — `0x8009F2EC` .. `0x8009F4E4` (**20 registros**): telas FILE (A[0..4]) e caixa de itens.
* **Tabela B** — `0x8009F890` .. `0x800A0058` (**≥165 registros**): tela de **STATUS**.
  (De B[165] em diante o conteúdo já é a tabela `0x800A004C`; use B[0..164].)

```c
struct rect {              // 12 bytes
    u16 u;      // +0x00  U na página de textura (pixels)
    u16 v;      // +0x02  V na página de textura (pixels)
    u16 w;      // +0x04  largura  em px de tela  (= largura na textura, 1:1, sem escala)
    u16 h;      // +0x06  altura   em px de tela
    u16 dx;     // +0x08  X de tela  (somado a base[idx].x)
    u16 dy;     // +0x0a  Y de tela  (somado a base[idx].y)
};
```

Prova do layout, campo por campo (as 6 rotinas montadoras leem exatamente esses offsets):

| rotina | tipo GPU | o que lê do registro | onde escreve na primitiva |
|---|---|---|---|
| `0x8006E600` | `SPRT` (`len=4`, `code=0x64`) | `u8 @+0` → `u0`; `u8 @+2` → `v0`; `u16 @+4` → `w`; `u16 @+6` → `h` | `prim+0x0c/0x0d/0x10/0x12`; `rgb=0x80` em `+4/5/6`; CLUT em `+0x0e` |
| `0x8006E6D8` | `POLY_FT4` (`len=9`, `code=0x2c`) | `u16 @+0` → `u`; `u16 @+2` → `v`; lado = `a3>>24` | 4 pares `u,v` = `(u,v)(u+d,v)(u,v+d)(u+d,v+d)` |
| `0x8006E7D4` | `TILE` (`len=3`, `code=0x60`) | `u16 @+4` → `w`; `u16 @+6` → `h` | `prim+0x0c/0x0e`; **`rgb = (8,8,8)`** (painel escuro) |
| `0x8006E8BC` | posiciona SPRT | `u16 @+8` → `dx`; `u16 @+0xa` → `dy` | `prim+8 = base.x + dx`, `prim+0xa = base.y + dy`, `AddPrim` |
| `0x8006E9D4` | posiciona POLY_FT4 | `+4 w`, `+6 h`, `+8 dx`, `+0xa dy` | 4 vértices `(x,y)(x+w,y)(x,y+h)(x+w,y+h)` |
| `0x8006EAF0` | posiciona TILE | `+8 dx`, `+0xa dy` | `prim+8/0xa` |

Assinatura comum: `f(a0 = ctx, a1 = buffer de primitivas, a2 = &rect[0], a3 = empacotado)`.

```
a3 dos montadores  : (contagem) | (índice de CLUT << 8) | (flag << 16) | (lado << 24)
a3 dos posicionad. : (contagem) | (base_idx      << 8) | (ot   << 16)
```

* **`base_idx`** indexa `base[] = (s16 x, s16 y)` em **`ctx+0xE4`, passo 4, 32 entradas**
  (zeradas no init em `0x8006DB34`, laço de `0x20`). Ou seja: **com a base em (0,0) — o
  estado de repouso — `dx,dy` do registro SÃO as coordenadas absolutas de tela**.
  As bases servem para as animações de abertura/deslize e para mover o cursor.
* **`ot`** indexa uma primitiva `DR_MODE` em `ctx+0x164 + fb*0x140 + ot*8` (40 camadas,
  `fb` = 0/1 do double-buffer em `*(u8*)0x800CC848`). Cada faixa de `ot` fixa a página de
  textura (`0x8006AEB8`–`0x8006AFFC`, `SetDrawMode` = `0x8008F734`):

| `ot` | tpage | decodificação (`GetTPage`) | atlas que aponta |
|---|---|---|---|
| 0..7 | `0x9B` | 8bpp, x=704, y=256, abr=0 | `STMAIN0U`, **pixels 128..255** |
| 8..15 | `0x9A` | 8bpp, x=640, y=256, abr=0 | `STMAIN0U` pixels 0..127 = **ícones de item** (v 72..191) |
| 16..23 | `0x3A` | 4bpp, x=640, y=256, **abr=1 (50%)** | `STMOJIU` (texto/cursor, semitransparente) |
| 24..31 | `0x97` | 8bpp, x=448, y=256, abr=0 | placa 112×72 de `ITEMG.PIX` |
| 32..39 | `0x17` | 4bpp, x=448, y=256, abr=0 | — |

* **CLUT**: `clut = GetClut(x, y)` com `y = (a3>>8 & 0xff) + 480` e
  `x = 0` (bit 16 de `a3` zero) ou `x = 304` (bit 16 setado → também liga `SetSemiTrans`).
  Os índices vêm de `ctx+0xd0..0xd8 = {4,5,6,0,8,0x0e,0,0x0a,9}`:
  `d0=4` → CLUT `(0,484)` = paleta 0 do STMAIN (molduras);
  `d1=5` → `(0,485)` = paleta 1 (**ícones de item**);
  `d2=6` → `(0,486)` = paleta 2 (**retrato da Jill**); `d2+1=7` → `(0,487)` (**retrato do Carlos**);
  `d3=0` → com x=304 → `(304,480)` = paleta 0 do STMOJI (texto).
  Renderizando as 4 CLUTs do `STMAIN0U` confirmei que só a paleta 2/3 deixa os retratos com
  cor correta — bate com `d2` e `d2+1` em `0x8006B3E4`/`0x8006B40C`.

* **Double-buffer:** cada registro ocupa **2 primitivas** consecutivas (`0x14` para SPRT,
  `0x10` para TILE, `0x28` para POLY_FT4) — uma por framebuffer. **No port, use uma só.**

---

## 3. Q1 — A GRADE DE SLOTS (a resposta principal)

### 3.1 Geometria

| # | valor | prova |
|---|---|---|
| Colunas | **2** | `col = sel & 1` em `0x80066808` e `0x80066898`/`0x800668A0` (`andi $v1,$v1,1`) |
| Passo de coluna | **40 px** | `x = ((col*4+col)<<3) = col*40` em `0x8006689C`–`0x800668B4` |
| Passo de linha | **30 px** | `row = sel>>1; y = ((row<<4)-row)<<1 = row*30` em `0x800668B8`–`0x800668CC` |
| Origem da célula 0 | **(224, 66)** | `dx,dy` de B[27] = `0x8009F9D4` |
| Tamanho da célula | **40 × 30** | B[28]/B[29] (`w=40 h=30`) e `LoadImage` 20 words × 30 linhas em `0x8006ABCC`/`0x8006ABD4` |
| Linhas visíveis | 4 desenhadas em bloco + 1 avulsa = **5** | B[27] é um único retângulo 80×120 (= 2×4 células) e B[28]/B[29] são a 5ª linha |

**Tabela final de células (espaço 320×240):**

| slot | col | lin | x,y do ícone | x,y da quantidade | U,V na VRAM do ícone |
|---|---|---|---|---|---|
| 0 | 0 | 0 | **224, 66** | 226, 84 | tpage `0x9A` u=0 v=72 |
| 1 | 1 | 0 | **264, 66** | 266, 84 | u=40 v=72 |
| 2 | 0 | 1 | **224, 96** | 226, 114 | u=0 v=102 |
| 3 | 1 | 1 | **264, 96** | 266, 114 | u=40 v=102 |
| 4 | 0 | 2 | **224, 126** | 226, 144 | u=0 v=132 |
| 5 | 1 | 2 | **264, 126** | 266, 144 | u=40 v=132 |
| 6 | 0 | 3 | **224, 156** | 226, 174 | u=0 v=162 |
| 7 | 1 | 3 | **264, 156** | 266, 174 | u=40 v=162 |
| 8 | 0 | 4 | **224, 186** | 226, 204 | u=80 v=72 |
| 9 | 1 | 4 | **264, 186** | 266, 204 | u=80 v=102 |
| (equipada) | — | — | **172, 37** | 174, 55 | u=80 v=132 (slot VRAM 10) |

A coluna "x,y da quantidade" é lida direto da tabela **`0x800A0080`** (`u16 x, u16 y`,
11 entradas) — não é derivada. Relação medida: quantidade = célula + **(2, 18)**.

Como o jogo desenha: **um único SPRT 80×120** (B[27], u=0 v=72) cobre os 8 primeiros slots
de uma vez (porque na VRAM eles formam um bloco 80×120 contíguo), e os slots 8 e 9 são dois
SPRT 40×30 separados (porque estão na 3ª coluna da VRAM). Sítio: `0x8006BAB8`
(`0x8006E8BC(ctx, 0x801AC398, 0x8009F9D4, a3 = ot<<16 | 0x0103)` → cnt=3, base_idx=1, ot=10).

### 3.2 Navegação (`0x8006676C`–`0x80066874`)

Entrada: `*(u16*)0x800CC838`.

```
CIMA   (0x1000):  if (sel >= -2)          sel -= 2
BAIXO  (0x4000):  if (sel <  count-2)     sel += 2      # count = *(u8*)(inv+0x12a)
ESQ    (0x8000):  if (sel & 1)            sel -= 1
DIR    (0x2000):  if (!(sel & 1))         sel += 1
```

* **`sel` = `ctx+0x1c` (s8)**. Não há paginação: o cursor só anda dentro de `0..count-1`.
* `sel` **pode ficar negativo (-1 e -2)**: são duas posições "acima da grade"
  (o teste é `sel < -2` → bloqueia). Quando `sel < 0` a rotina de posição do cursor
  **não atualiza** `base[0x0c]` (`bltz $v0` em `0x8006689C`) — o cursor sai da grade e
  quem desenha é outro caminho. **Não medi** o que fica nessas duas posições.
* Nas bordas não há wrap: o movimento simplesmente não acontece.
* Quando o movimento acontece, `0x800746C0(a0=4, 0,0,0)` é enfileirado (`0x8006688C`).
  Ver "EM ABERTO" — não resolvi o que esse id 4 produz.

---

## 4. Q2 — O ÍCONE e o "N" da quantidade

### 4.1 De onde vem o ícone da grade: `ETC/ITEMA.SLD`, **não** `ITEMG.PIX`

`0x8006AB68(a0 = slot_vram, a1 = item_id, a2 = base_do_SLD, a3 = scratch)`:

```
off  = *(u32*)(0x8009F678 + item_id*4)          # tabela de offsets, 1 u32 por item_id
descomprime(0x80010000)(a0 = a2 + off, a1 = a3) # a3 = 0x801B1000
rect = { x = *(u16*)(0x800A004C + slot_vram*4),
         y = *(u16*)(0x800A004C + slot_vram*4 + 2),
         w = 20 (palavras),  h = 30 }
LoadImage(rect, a3)                             # 0x8008B2AC
```

20 palavras × 30 linhas a 8bpp = **40 × 30 px = 1200 bytes**. Os deltas da tabela
`0x8009F678` ficam entre 372 e 720 bytes → é **comprimido** (razão ~0.4).
Descompressor: **`0x80010000`** (não decodifiquei o algoritmo — ver EM ABERTO).

Tabela **`0x800A004C`** (13 entradas, `u16 x, u16 y` em palavras de VRAM):

| slot VRAM | VRAM (x,y) | u,v na tpage `0x9A` | uso |
|---|---|---|---|
| 0..7 | (640/660, 328/358/388/418) | (0/40, 72/102/132/162) | slots 0..7 da grade |
| 8..11 | (680, 328/358/388/418) | (80, 72/102/132/162) | slots 8, 9, **10 = arma equipada**, 11 |
| 12 | (448, 328) | tpage `0x97`, (0, 72) | (não amarrei a um retângulo) |

`0x8006AE20(a0 = destino, a1 = origem)` = `MoveImage` (`0x8008B36C`) VRAM→VRAM de um
ícone 40×30 entre slots — é assim que o jogo "move" ícones sem redescomprimir.
`0x8006AD38(a0, a1)` usa `StoreImage` (`0x8008B30C`) para trocar dois ícones.

**Escala: 1:1.** O `w,h` do registro é igual ao tamanho na textura — não há escala nem recorte.

### 4.2 O número da quantidade — `draw_number` `0x8006C6D0`

`0x8006C6D0(a0 = ponteiro corrente de primitivas, a1 = valor, a2 = x | y<<16,
a3 = clut_idx | modo<<8 | ot<<16)`.

Modo (`a3>>8 & 0xff`) 1 = decimal de **3 dígitos** (divisões por 100 e por 10 com as
constantes mágicas `0x51EB851F` e `0x66666667`), gravando `-1` na posição do dígito quando
ele deve ser suprimido (zero à esquerda → não emite primitiva).

Emissor de glifo (`0x8006C910`–`0x8006C9A0`), por dígito `d`:

```
SPRT  len=4  code=0x64  rgb=(0x80,0x80,0x80)
x0 = x_corrente;  x_corrente += 8            # AVANÇO = 8 px
y0 = y
u0 = 4 + d*8                                 # atlas STMOJIU
v0 = 19
w  = 8 ;  h = 11
clut = GetClut(304, clut_idx + 480)          # paleta do STMOJIU
AddPrim(ctx+0x164 + fb*0x140 + ot*8, prim)
```

Confirmado no bitmap: renderizando `STMOJIU.TIM` a fileira `v = 19..29` é
`0 1 2 3 4 5 6 7 8 9 % O O`, com o `0` começando em `u ≈ 4`.

**Não há glifo "x" antes do número** — a tela mostra só o número (3 dígitos, 8 px cada,
24 px de largura total), começando em `célula + (2,18)`.

Cor do número: `clut_idx = *(u8*)(ctx+0xd3) + ((slot.flags >> 2) & 3) + 2`
(`0x8006C08C`–`0x8006C0A0`), ou seja **os bits 2–3 do `u16 flags` do slot escolhem a paleta
do número** (é assim que munição baixa muda de cor). `ctx+0xd3 = 0`, logo `clut_idx = 2..5`
→ CLUT `(304, 482..485)` do STMOJI. `ot` = `s5*2 + 2 = 18` → tpage `0x3A` (4bpp,
semitransparente).

Laço completo (`0x8006C040`–`0x8006C0D0`): `for i in 0..count-1` desenha a quantidade do
slot `i` na posição `0x800A0080[i] + (ctx+0xe8, ctx+0xea)`. Depois (`0x8006C0D4`), se
`inv[0x128] != 0xff`, desenha também a quantidade da arma equipada em `0x800A0080[10]`.

---

## 5. Q3 — O CURSOR

| item | valor | prova |
|---|---|---|
| Sprite | retângulo **vazado 40×30** do `STMOJIU` em **u=120, v=0** | rect B[146] = `0x8009FF68` (`u=120 v=0 w=40 h=30 dx=224 dy=66`); crop do atlas mostra 3 retângulos vazados em u=120/160/200 |
| Página / mistura | `ot = s5*2+1 = 17` → tpage **`0x3A`** (4bpp, x=640, **abr=1 → 50% aditivo/blend**) + `SetSemiTrans` | `0x8006C244`–`0x8006C254`; bit 16 de `a3` no montador `0x8006B4D8` |
| CLUT | `(304, 483)` = paleta 3 do STMOJI (`ctx+0xd3 + 3`) | `0x8006B4C0`–`0x8006B4D4` |
| Posição | `base[0x0c] + (224,66)`, `base[0x0c] = (col*40, row*30)` | `0x800668A4`–`0x800668CC` |
| Piscada | contador `ctx+0x22` sobe/desce **±2 por frame** entre **0 e 0x3F**; direção em `ctx+0x24` | `0x8006E290`–`0x8006E2F0` |
| Efeito da piscada | `r = g = b = (u8)(ctx+0x22 - 0x80)` → varre **128 → 191 → 128** | `0x8006B6D0`–`0x8006B6FC` (escreve `prim+4/5/6` de `0x801ACA00`, ou `0x801ACA14` se `fb=1`) |
| Ciclo | 0→63 em 32 frames + 63→0 em 32 frames = **64 frames** por ciclo, a 1 frame de `yield` | `yield(1)` em `0x8006E064` |

Quando `ctx+0x11 != 0` a cor volta a `0x80` chapado nos dois buffers (`0x8006B704`).

**Segundo marcador** (usado para combinar dois itens): sprite **u=160, v=0, 40×30**
(B[147] = `0x8009FF74`), prim `0x801ACA28`, base `0x0d` = `(ctx+0x1d & 1)*40, (ctx+0x1d>>1)*30`
(`0x80067FD0`–`0x80068000`), desenhado só se `ctx+0x18 & 0x02000000`, e pisca quando
`(*(u32*)(ctx+0x10) & 0x00FFFF00) == 0x00010700`.

**Terceiro cursor**: **u=200, v=0, 32×32** (B[148] = `0x8009FF80`, prim `0x801ACA50`),
pisca quando `(estado & 0x00FFFF00) == 0x00030500`; casa com a grade de células 32×32
(B[30..61]) — ver EM ABERTO.

---

## 6. Q4 — A ARMA EQUIPADA

Ela **não é marcada na grade**. Ela tem um quadro próprio:

* Moldura **"EQUIP" 64×64** desenhada em **(160, 16)** — B[5] = `0x8009F8CC` (`u=64 v=0`,
  tpage `0x9B` → pixels 192..255 do `STMAIN0U`). O texto "EQUIP" está batido no bitmap
  (confirmado visualmente no atlas).
* **Ícone 40×30 em (172, 37)** — B[68] = `0x8009FBC0` (`u=80 v=132`, tpage `0x9A`),
  ou seja **slot VRAM 10**, prim `0x801AC460`, sítio `0x8006BA7C`
  (`a3 = ot<<16 | 0x0101` → cnt=1, base_idx=1).
* **Quantidade em (174, 55)** = `0x800A0080[10]`.
* O ícone chega no slot VRAM 10 por `0x8006AE20(a0=10, a1=inv[0x128])` (`0x8006D8C8`), i.e.
  uma cópia VRAM→VRAM do ícone do slot `inv[0x128]`. Se `inv[0x128] == 0xFF`, nada é copiado
  e nada é desenhado.

### 6.1 CORREÇÃO ao modelo de inventário de `exe_items.md`

Estrutura em `0x800D2134`, **passo 320 (`0x140`) entre inventários**
(`0x8006ECB0`: `ptr = 0x800D2134 + n*320`, `n` = `*(u32*)0x800D23B8`):

```c
struct inv {                     // 320 bytes
    slot main[10];               // +0x000  (10*4)
    slot box[64];                // +0x028  (64*4)   <- 0x28 + 256 = 0x128, fecha exato
    u8   equipped_slot;          // +0x128  índice do slot da arma equipada, 0xFF = nenhuma
    u8   equipped_item_id;       // +0x129  item_id da arma equipada
    u8   visible_main_slots;     // +0x12a  8 ou 10 (quantos slots a grade mostra)
    ...
};                               // slot = { u8 id, u8 qtd, u16 flags }
```

* **`+0x128` NÃO é "cursor".** É índice de slot: `0x8006C0DC` faz
  `s1 = *(u8*)(inv+0x128); s2 = inv + s1*4` (indexa o array de slots) e usa
  `0x800A0080[10]` para a posição — o quadro EQUIP. O cursor de tela é **`ctx+0x1c`**,
  zerado a cada abertura em `0x8006DB0C`; não é persistido no inventário.
* **`+0x129` é um item_id**, não um slot: em `0x8006E1E4` ele é escrito como byte baixo de
  `*(u16*)(0x800D25xx+0x46)` e em seguida `0x80043EE4`/`0x80043BE4` (equipar arma) são
  chamados. Por analogia direta com `0x80064C2C` (`a1 = *(u8*)(inv + slot*4 + 0x28)` =
  id de um slot da caixa, passado como `item_id` ao descompressor `0x8006ABF8`).
* Os 64 slots da caixa ficam **na mesma struct**, em `+0x28` — não num array separado.
* `0x800D23B4` = **ponteiro** para o inventário ativo; `0x800D23B8` = índice (0 = jogador,
  1 = parceiro). `0x8006ECB0(a0 = char_id)`: `char_id < 8 → 0`, `char_id == 8 → 1`.

---

## 7. Q5 — O PAINEL DE STATUS (condição)

### 7.1 Cálculo — `0x8006E598` (limiares REAIS)

```c
u8 status_condition(void) {
    u16 fl = *(u16*)0x800CCC96;
    s16 hp = *(s16*)0x800CCC90;          // hp_max em 0x800CCC92
    if (fl & 0x100) return 5;            // VIRUS
    if (fl & 0x200) return 4;            // Poison
    if (hp >= 101)  return 0;            // Fine
    if (hp >=  41)  return 1;            // Caution
    if (hp >=  21)  return 2;            // Caution (2ª cor)
                    return 3;            // Danger
}
```
Endereços das instruções: `0x8006E5A0` (`lhu 0x255e`), `0x8006E5A4` (`lh 0x2558`),
`0x8006E5C0` (`slti 0x65`), `0x8006E5D0` (`slti 0x29`), `0x8006E5E0` (`slti 0x15`).
O resultado é gravado em **`ctx+0x34`** por `0x8006E280`.

### 7.2 Desenho da palavra — tabela `0x800A0004` = B[159..164]

`0x8006BA20`–`0x8006BA5C`: `prim = 0x801AC0C8 + cond*40`, `rect = 0x800A0004 + cond*12`,
`a3 = ((s5*2+2)<<16) | 1` → cnt=1, base_idx=0, `ot = 18` → tpage `0x3A` (STMOJI, 4bpp).

| cond | rect | u | v | w | h | x | y | palavra (lida no bitmap `STMOJIU`) |
|---|---|---|---|---|---|---|---|---|
| 0 | `0x800A0004` | 0 | 32 | 24 | 8 | **121** | **25** | **Fine** |
| 1 | `0x800A0010` | 24 | 32 | 40 | 8 | **113** | **25** | **Caution** |
| 2 | `0x800A001C` | 64 | 32 | 40 | 8 | **113** | **25** | **Caution** (2ª cor) |
| 3 | `0x800A0028` | 104 | 32 | 40 | 8 | **113** | **25** | **Danger** |
| 4 | `0x800A0034` | 144 | 32 | 32 | 8 | **115** | **25** | **Poison** |
| 5 | `0x800A0040` | 184 | 32 | 32 | 8 | **120** | **25** | **VIRUS** |

(As palavras foram lidas descomprimindo o `STMOJIU.TIM` e recortando exatamente esses
retângulos — não é inferência.)

### 7.3 O painel e o retrato

| elemento | rect | u,v (atlas) | w×h | x,y de tela | tpage | prova do sítio |
|---|---|---|---|---|---|---|
| Moldura 64×64 do retrato | B[0] `0x8009F890` | 0,0 | 64×64 | **8, 16** | `0x9B` | `0x8006B99C` (cnt=2, base 0, ot 3) |
| Painel "condition" 96×56 (rótulo + caixa arredondada + área verde do ECG) | B[1] `0x8009F89C` | 0,64 | 96×56 | **72, 20** | `0x9B` | mesmo sítio (2º registro) |
| Retrato **JILL** 40×56 | B[2] `0x8009F8A8` | 0,192 | 40×56 | **18, 22** | `0x9B`, CLUT `(0,486)` | `0x8006B3F0` / `0x8006B9CC` |
| Retrato **CARLOS** 40×56 | B[3] `0x8009F8B4` | 40,192 | 40×56 | **18, 22** | `0x9B`, CLUT `(0,487)` | `0x8006B418` / `0x8006B9E0` |
| Retrato #3 (vazio no `STMAIN0U`) | B[4] `0x8009F8C0` | 80,192 | 40×56 | **18, 22** | CLUT `(0,488)` | `0x8006B440` / `0x8006B9F4` |

Escolha do retrato: `*(u32*)0x800D23B8` (0 → B[2], 1 → B[3], 2 → B[4]) em
`0x8006B9A4`–`0x8006BA00`. Os rótulos "JILL"/"CARLOS" estão **dentro** do bitmap 40×56
(v 192..201 é o texto, v 204..247 é o rosto).

**ECG:** a faixa verde riscada está **batida no bitmap** de B[1] (região do atlas
`u 130..208, v 81..114`, i.e. offset `(2,17)` dentro do painel de (72,20)).
**NÃO achei nenhuma linha/onda animada**: não há chamada a `SetLineF2` (`0x8008F6E4`) em
`0x80063000..0x80073000`, e não há tabela de forma de onda por estado. A única coisa que
muda com a condição é a **palavra** (§7.2). Se existe animação de ECG no RE3, ela não sai
deste módulo — **NÃO MEDIDO**.

---

## 8. Q6 — "Nome/descrição" do item

**Não existe texto de nome nesta tela.** O que aparece é uma **placa 112×72** com o desenho
e o nome do item já rasterizados, vinda de `ETC/ITEMG.PIX`:

* Carga: `0x8006AC88(a0 = item_id)` → pedido de CD com `size = 0x2800` (10240 B),
  `lba = filetab[0x33].lba + item_id*5`, destino `*(u32*)(ctx+8)`.
  Isso **confirma** o fato já provado no repo (`ITEMG.PIX`, passo 10240, 112×72, índice = item_id).
* Sobe para VRAM em **(448, 256)** — `0x8009F4F8[0]`.
* Desenho: **B[66] = `0x8009FBA8`** (`u=0 v=0 w=112 h=72`) em **(56, 88)**, tpage `0x97`
  (`ot` da faixa 24..31), prim `0x801AC410`, sítio `0x8006BB5C`.

O `tools/re3_text.py` (nomes/exames do EXE) e `port/data/re3_messages.json` **não** alimentam
esta tela — são para as caixas de mensagem do jogo.

### 8.1 O submenu de ações (as palavras SÃO sprites de `STMOJIU`)

4 linhas: fundos 64×24 em **(155,80) (155,100) (155,120) (155,140)** = B[77..80]
(`0x8009FC2C..0x8009FC50`, `u=24 v=184`, tpage `0x9B`), rótulos **48×16** em
`x = 163`, `y = 84/104/124/144` (= fundo + (8,4)). Linha destacada = `ctx+0x1e` (0..3).

| rect | u,v | y | palavra (lida no bitmap) |
|---|---|---|---|
| B[152] `0x8009FFB0` | 0,56 | 84 | **EQUIP** |
| B[153] `0x8009FFBC` | 48,56 | 84 | **USE** |
| B[154] `0x8009FFC8` | 96,56 | 104 | **COMBINE** |
| B[155] `0x8009FFD4` | 144,56 | 104 | **PIECES** |
| B[156] `0x8009FFE0` | 192,56 | 124 | **CHECK** |
| B[157] `0x8009FFEC` | 112,40 | 144 | **AUTO** |
| B[158] `0x8009FFF8` | 160,40 | 144 | **MANUAL** |

Escolha da linha 0: `if (*(u8*)(0x800A0514 + item_id*4) == 1)` → **EQUIP**, senão **USE**
(`0x8006BE2C`–`0x8006BE64`). `0x800A0514` é uma tabela de 4 bytes por item_id
(**só o byte 0 eu decodifiquei**: 1 = "equipável").

O par de rótulos por linha (normal/destacado) usa POLY_FT4 de 8 px de altura em
`v = 184/192` (normal) e `v = 200/208` (destacado) — B[113..140], escolhidos por `ctx+0x1e`
em `0x8006BF1C`..`0x8006BFF0`. Ou seja **cada rótulo de 16 px é montado com duas tiras de 8 px**.

Molduras de janela 9-fatias (cantos 8×8, bordas 192×8 e 8×N): B[81..112], com 4 alturas
diferentes: `(8,80)-(216,168)`, `(8,80)-(216,192)`, `(8,192)-(216,224)`, `(8,168)-(216,224)`.

---

## 9. Q7 — Fundo / moldura: composição completa (modo 1)

Não há imagem de tela cheia. A moldura é montada com os retângulos abaixo. `base_idx` e `ot`
são os medidos; onde a coluna `a3` está `?` o valor é calculado em runtime e **não resolvi**.

| rect(s) | u,v | w×h | x,y | tipo | base/ot | o que é | sítio |
|---|---|---|---|---|---|---|---|
| B[0], B[1] | 0,0 / 0,64 | 64×64 / 96×56 | 8,16 / 72,20 | SPRT | 0 / 3 | moldura do retrato; painel "condition" | `0x8006B99C` |
| B[2..4] | 0/40/80,192 | 40×56 | 18,22 | SPRT | 0 / `s5\|4`=12 | retrato (Jill/Carlos/–) | `0x8006BA0C` |
| B[5..9] | 64,0 / 0,120 / 96,72 / 104,64 / 0,176 | 64×64, 88×56, 8×136, 8×144, 96×8 | 160,16 / 224,16 / 216,80 / 304,72 / 216,216 | SPRT | 1 / 3 | quadro "EQUIP"; painel superior direito; trilhos verticais em x=216 e x=304; barra inferior | `0x8006BA9C` (cnt=5) |
| B[24..26] | 92,120 / 92,124 / 92,128 | 4×4, 4×76, 4×4 | 216,80 / 216,84 / 216,160 | POLY_FT4 | 1 / 7 | barra de rolagem em x=216 (topo, corpo esticável, base) | `0x8006BAF4` (cnt=3) |
| B[27..29] | 0,72 / 80,72 / 80,102 | 80×120, 40×30, 40×30 | 224,66 / 224,186 / 264,186 | SPRT | 1 / `s5\|2`=10 | **os 10 ícones da grade** | `0x8006BAB8` (cnt=3) |
| B[62], B[63] | 28,0 / 42,0 | 12×12 | 26,130 / 186,130 | SPRT | ? | setas 12×12 (esq./dir.) do painel esquerdo | `0x8006BBE8` / `0x8006BC1C` |
| B[64], B[65] | — | 8×96 / 200×96 | 0,88 / 216,88 | **TILE rgb(8,8,8)** | 9 / 7 | painéis escuros de fundo | `0x8006BB8C` (cnt=2) |
| B[66] | 0,0 | 112×72 | 56,88 | SPRT | ? | **placa 112×72 do item (`ITEMG.PIX`)** | `0x8006BB5C` |
| B[68] | 80,132 | 40×30 | 172,37 | SPRT | 1 / 10 | ícone da arma equipada | `0x8006BA7C` |
| B[69..72] / B[73..76] | 0,208 / 72,220 / 112,176 / 112,192 | 72×48, 56×36, 16×16, 16×20 | 148,80… / 148,108… | SPRT | 3 / 6 | caixa do submenu (2 alturas, escolhidas por `ctx+0x44 & 0x10`) | `0x8006BD94` (cnt=4) |
| B[77..80] | 24,184 | 64×24 | 155,80/100/120/140 | SPRT | 4..7 / 4 | fundos das 4 linhas do submenu | `0x8006BDB4`.. |
| B[81..112] | ver §8.1 | 8×8 / 192×8 / 8×N | — | POLY_FT4 | 8..11 / 7 | molduras 9-fatias de janela | `0x8006BB14`, `0x8006BBAC`, `0x8006BCD4`, `0x8006BD30` |
| B[113..140] | 88, 184/192/200/208 | 38/80/56 × 8 | 224,44 / 224,24 / 159,84… | POLY_FT4 | 1,4..7 / 4,5 | tiras de texto (normal/destacado) | `0x8006BF40`.. `0x8006C208` |
| B[141..144] | 8,192 | 200×80/136/24/48 | 12,84 / 12,196 / 12,172 | POLY_FT4 | 8..11 / 7 | painéis grandes | `0x8006BB34`, `0x8006BCF4`, `0x8006BD50` |
| B[145] | — | 96×24 | 216,200 | **TILE rgb(8,8,8)** | 2 / 1 | painel escuro inferior direito | `0x8006C2E4` |
| B[146] | 120,0 | 40×30 | 224,66 | SPRT | **0x0c** / `s5*2+1`=17 | **cursor** | `0x8006C250` |
| B[147] | 160,0 | 40×30 | 224,66 | SPRT | **0x0d** / 17 | 2º marcador (combinar) | `0x8006C290` |
| B[148] | 200,0 | 32×32 | 16,88 | SPRT | ? | 3º cursor (grade 32×32) | `0x8006B4F4` (montagem) |
| B[10..16] | 112, 64/160/160/80/96/112 + 0,176 | 16×16 ×6 + 96×8 | 216..296, 184 + 216,200 | SPRT | 2 / 1 | fileira de 6 ícones 16×16 — **semântica NÃO identificada** | `0x8006C2C4`, só se `inv[0x12a] == 8` |
| B[17..23] | idem com v=128/144 | idem | idem | SPRT | ? | variante da fileira acima | — |
| B[30..61] | grade 4×8 de 32×32 no atlas | 32×32 | (16..144, 88..152) e (224..384, 88..152) | ? | ? | grade de 32 células 32×32 — **NÃO identificada** (x até 384 ⇒ rola por base) | `a2` calculado; não resolvi |

Observação importante: `0x8006C2C4` é guardado por `if (*(u8*)(inv+0x12a) == 8)` — quando a
grade só mostra 8 slots, a linha `y=184..200` fica livre e recebe a fileira de 6 ícones 16×16.
Com 10 slots, os slots 8 e 9 ocupam `y=186`. Isso amarra **capacidade 8 ↔ 5ª linha vazia**.

---

## 10. Q8 — Quantos slots o RE3 tem de verdade

* O array tem **10** slots principais (`inv+0x00`, 4 bytes cada) e o loop de upload de ícone
  em `0x8006D89C` roda exatamente **10** vezes.
* A tela desenha **até 10** (2 × 5) e o número efetivo é **`*(u8*)(inv+0x12a)`**, usado como
  limite tanto no laço de quantidades (`0x8006C0C8`) quanto no clamp de "baixo"
  (`0x800667C4`: `sel < count-2`). Os valores que o código trata explicitamente são
  **8** (`0x8006C2A4`: `if (count == 8)`) e implicitamente 10.
* **Não há paginação**: nenhum registro de página, nenhum offset de scroll na grade.
  A barra em x=216 (B[24..26]) pertence ao painel de mensagem/lista, não à grade.
* Existe uma segunda "grade" de 32 células 32×32 (B[30..61]) que **não** é o inventário
  principal (célula 32×32 ≠ 40×30) — ver EM ABERTO.

---

## 11. Mapa de campos do contexto `0x800E01C0`

| offset | tipo | significado | prova |
|---|---|---|---|
| `+0x04` | u8 | **modo** 0..5 (§1.2) | `0x8006E460`, `0x8006E35C` |
| `+0x08` | u32 | destino de leitura de CD (ITEMG/ITEMI) | `0x8006AAEC`, `0x8006AD70` |
| `+0x10` | u8 | **estado** (índice em `0x800A02F0`) | `0x8006E02C` |
| `+0x10` | u32 | lido inteiro para testes `& 0x00FFFF00` de piscada | `0x8006B730`, `0x8006B7C0` |
| `+0x11` | u8 | sub-estado (0 ⇒ cursor da grade pisca) | `0x8006B6A8` |
| `+0x14` | u32 | flags (bit `0x40000000` setado por `0x8006ECB0`) | `0x8006ED14` |
| `+0x18` | u32 | flags de desenho (§1.2) | `0x8006E38C`+ |
| `+0x1c` | s8 | **slot selecionado (cursor)** | `0x8006689C`, `0x80066798` |
| `+0x1d` | s8 | 2º slot selecionado | `0x80067FD0` |
| `+0x1e` | s8 | linha do submenu 0..3 | `0x8006BF1C` |
| `+0x22` | u16 | contador de piscada 0..0x3F | `0x8006E2A0` |
| `+0x24` | s16 | direção da piscada | `0x8006E2D8` |
| `+0x27` | u8 | task ativa (0 ⇒ sai do laço) | `0x8006E000` |
| `+0x28` | u8 | cache de `inv[0x129]` | `0x8006D92C`, `0x8006E1B8` |
| `+0x29` | u8 | id do personagem (`0x800CCC0E`) | `0x8006DB70` |
| `+0x34` | u8 | **condição 0..5** | `0x8006E280` |
| `+0x44` | u16 | flags de layout (bit `0x10` alterna alturas de caixa) | `0x8006BD58` |
| `+0xd0..0xd8` | u8[9] | índices de CLUT (`y = valor + 480`) = `{4,5,6,0,8,0x0e,0,0x0a,9}` | `0x8006D8E0`–`0x8006D914` |
| `+0xe4 + i*4` | s16,s16 | **base[i]** de posição, i = 0..31 | `0x8006DB34` (laço de 0x20), `0x8006E924` |
| `+0xe8/+0xea` | u16 | deslocamento global aplicado aos números | `0x8006C068` |
| `+0x114/0x116` | s16 | `base[0x0c]` = cursor | `0x800668B4/CC` |
| `+0x118/0x11a` | s16 | `base[0x0d]` = 2º marcador | `0x80067FFC/8000` |
| `+0x164 + fb*0x140 + ot*8` | DR_MODE | 40 camadas × 2 buffers | `0x8006AEB8`, `0x8006E984` |

Globais fora do ctx:

| endereço | tipo | significado |
|---|---|---|
| `0x800CC838` | u16 | botões (`0x1000` cima, `0x2000` dir., `0x4000` baixo, `0x8000` esq.) |
| `0x800CC848` | u8 | índice do framebuffer (0/1) |
| `0x800CC858` | u32[] | bitfield global (`bit 0x18` decide STMAIN0 vs 1/2/3) |
| `0x800CCBBC/BD` | u8,u8 | alocador de VRAM (tagX em unidades de 64 palavras, tagY de linhas de CLUT) |
| `0x800CCC0E` | u8 | id do personagem (8 = Carlos, 9 = Mikhail, 10 = Nicholai; <8 = Jill) |
| `0x800CCC90` | s16 | HP |
| `0x800CCC92` | s16 | HP máximo |
| `0x800CCC96` | u16 | flags de status (`0x100` vírus, `0x200` veneno) |
| `0x800D2134` | struct | inventário 0 (passo 320 até o inventário 1) |
| `0x800D23B4` | ptr | inventário ativo |
| `0x800D23B8` | u32 | índice do inventário ativo (0/1) — também escolhe o retrato |
| `0x8009F678` | u32[135] | offset em `ITEMA.SLD` por item_id |
| `0x8009F568` | u8[135] | byte de `flags` do pedido de CD por item (ITEMI) |
| `0x8009F5F0` | u8[135] | idem para ITEMG |
| `0x800A004C` | u16[13][2] | VRAM (x,y) dos 13 slots de ícone 40×30 |
| `0x800A0080` | u16[11][2] | tela (x,y) do número de quantidade por slot |
| `0x8009F4F8` | u16[8][2] | VRAM (x,y) dos 8 ícones da tela de caixa (x=448) |
| `0x800A0514` | u32[] | 4 bytes por item_id; byte 0 = 1 ⇒ item equipável |

---

## 12. Tabela A (`0x8009F2EC`) — telas FILE e caixa de itens

Para referência (não é o escopo desta rodada, mas os registros estão provados):

| # | addr | u,v | w×h | x,y | usada por |
|---|---|---|---|---|---|
| A[0] | `0x8009F2EC` | 0,0 | 128×168 | 96,72 | FILE (`0x80063E9C` monta, `0x80063FE4` posiciona) |
| A[1] | `0x8009F2F8` | 0,0 | 256×176 | 32,32 | FILE |
| A[2] | `0x8009F304` | 28,0 | 12×12 | 15,114 | FILE, seta esq. (base 0x14) |
| A[3] | `0x8009F310` | 42,0 | 12×12 | 290,114 | FILE, seta dir. (base 0x13) |
| A[4] | `0x8009F31C` | 56,0 | 27×10 | 290,114 | FILE (base 0x15) |
| A[5..19] | `0x8009F328`.. | — | — | — | caixa de itens (`0x8006511C` / `0x800654A8`) |

A caixa de itens repete a grade principal em **(224,66)** (A[9] `0x8009F3F4`, `u=0 v=72
80×120`) + slots 8/9 em (224,186)/(264,186) (A[10]/A[11]) + um **11º ícone em (221,24)**
(A[12] `0x8009F418`, `u=80 v=132` = slot VRAM 10) — o "item na mão". Os 8 slots visíveis da
caixa vêm de `0x8009F4F8` (VRAM x=448, y 256..495, passo 30) via
`0x8006ABF8(a0 = idx&7, a1 = item_id, …)`.

---

## 13. Como medir de novo

```bash
PYTHONIOENCODING=utf-8 python tools/status_layout.py rects    # as 2 tabelas de retangulo
PYTHONIOENCODING=utf-8 python tools/status_layout.py calls    # todos os sitios com a1/a2/a3
PYTHONIOENCODING=utf-8 python tools/status_layout.py slots    # 0x800A004C
PYTHONIOENCODING=utf-8 python tools/status_layout.py sld      # 0x8009F678
PYTHONIOENCODING=utf-8 python tools/status_layout.py json c:/tmp/status.json
```

```python
import sys; sys.path.insert(0,'tools')
from exe_parse import Exe
e = Exe('extracted/ntsc-u/SLUS_009.23')
e.disasm(0x8006e598, 28)     # condicao / limiares de HP
e.disasm(0x8006e600, 55)     # montador de SPRT (le u,v,w,h)
e.disasm(0x8006e8bc, 46)     # posicionador (le dx,dy + base[])
e.disasm(0x8006c6d0, 62)     # draw_number
e.disasm(0x8006ab68, 40)     # upload do icone 40x30
e.disasm(0x80066760, 50)     # navegacao
```

Folhas de referência já geradas (todas as CLUTs empilhadas, uma por faixa de 272 px / 72 px):

* [`img/menu_inventario/STMAIN0U_cluts.png`](img/menu_inventario/STMAIN0U_cluts.png) — 256×272, 4 paletas.
* [`img/menu_inventario/STMOJIU_cluts.png`](img/menu_inventario/STMOJIU_cluts.png) — 256×72, 9 paletas.

Para conferir as palavras/retângulos no bitmap (é assim que provei "Fine/Caution/Danger/
Poison/VIRUS" e "EQUIP/USE/COMBINE/PIECES/CHECK/AUTO/MANUAL"): descomprima
`ETC/STMOJIU.TIM` (4bpp, 256×72, 9 CLUTs em (304,480)) e recorte exatamente
`(u, v, w, h)` dos registros. `ETC/STMAIN0U.TIM` é 8bpp 256×272 com 4 CLUTs; a paleta 2 é a
do retrato da Jill e a 3 a do Carlos.

---

## 14. EM ABERTO (sem prova — não invente)

1. **Descompressor `0x80010000`** — usado para os ícones 40×30 de `ITEMA.SLD`. Não
   desmontei o algoritmo. Sem ele, os ícones da grade não saem do `.SLD`.
   *Alternativa prática para o port:* os ícones grandes 112×72 de `ITEMG.PIX` já estão
   extraídos; os 40×30 exigem esse decoder. **NÃO DECODIFICADO.**
2. **`ETC/ITEMI.PIX`** (274432 B = 134 × 2048): `0x8006AA84(a0)` lê **um setor de 2048 B**
   no setor `filetab[0x34].lba + a0`, i.e. 1 setor por item_id, para `*(u32*)(ctx+8)`.
   Formato do setor **NÃO DECODIFICADO** e não sei qual retângulo o consome.
3. **Grade de 32 células 32×32** (B[30..61], telas em `x 16..176` e `x 224..384`,
   `y 88/120/152`): o `a2` dessas chamadas é calculado em runtime e não resolvi qual estado
   as usa. Pode ser a tela de mapa ou a de arquivo. **NÃO IDENTIFICADA.**
4. **Fileira de 6 ícones 16×16** em `(216..296, 184)` (B[10..15] e a variante B[17..22]):
   coordenadas provadas, **semântica não identificada**. Recortando o `STMAIN0U` em
   `u=240..255` (tpage `0x9B`) aparecem fragmentos "R.P." / "A.D." e losangos.
5. **Posições `sel = -1` e `-2`** (acima da grade): a navegação permite, mas
   `base[0x0c]` não é atualizado nesse caso; quem desenha o cursor então **NÃO MEDIDO**.
6. **`0x800746C0(a0 = 4..9, 0, 0, 0)`** disparado ao mover o cursor / confirmar / cancelar.
   `menus.md §8.2` chama de "enqueue de sprite" (escreve `prim+0x1c/0x1e/0x1f` no buffer
   `0x800E10E4`); pelo padrão de uso parece **feedback de UI (som ou sprite curto)**, mas
   depende do compositor `0x800E0610`, que continua não decodificado. **NÃO RESOLVIDO.**
7. **ECG animado**: não existe nesta task (nenhum `SetLineF2`, nenhuma tabela de forma de
   onda). A faixa verde é parte do bitmap de B[1]. Se o jogo animar algo ali, vem de outro
   módulo. **NÃO MEDIDO.**
8. **Semântica exata dos bits `0x100`/`0x200` de `0x800CCC96`**: mapeei-os para as palavras
   **VIRUS** e **Poison** pelos sprites (`0x8006E598` → B[164]/B[163]); não rastreei quem os
   liga (candidatos: `0x80051DDC`, `0x80052BDC`, `0x80052D4C`, `0x8007927C`).
9. **`0x800A0514`**: só o byte 0 (1 = equipável). Os bytes 1..3 variam de forma regular
   (ids 6..9 têm byte 3 = 1,5,9,0x0d) — **NÃO DECODIFICADO**.
10. **`ctx+0x44`** (bit `0x10`) alterna entre duas alturas de caixa de submenu; não achei
    quem o seta. **NÃO MEDIDO.**
11. **`a3` de ~20 sítios de posicionamento** (coluna "base/ot" com `?` na §9): calculados em
    runtime a partir do estado. Coordenadas dos registros estão provadas; a **condição** que
    liga cada um, não.
12. **Registro `0x800CCBBC` vs. overlap de VRAM**: com `tagX = 0x1A` tanto o `STMAIN0U`
    (128 palavras × 272 linhas em `y=256`) quanto o `STMOJIU` vão para `x=640,y=256`. Isso é
    intencional (a área cinza do STMAIN existe para ser sobrescrita), mas as 16 últimas
    linhas do STMAIN (`y 512..527`) **passam do fim da VRAM** — não verifiquei o que o
    hardware faz nem se essas linhas são usadas por algum registro (o `v` máximo que vi é 224).
13. **Modos 0 e 5**: `0` e `1` compartilham o mesmo estado/desenho e `4`/`5` também; não
    descobri o que diferencia `0` de `1` nem `4` de `5`.

---

## 15. CORREÇÕES DA AUDITORIA (revisão adversarial independente)

Auditoria feita **remedindo do zero** no `extracted/ntsc-u/SLUS_009.23` (base `0x80010000`), sem
reusar `tools/status_layout.py`. Método: desassemblar os **consumidores** das tabelas (não só ler
as tabelas), decodificar os headers TIM byte a byte, renderizar os atlas e **implementar o
descompressor `0x80010000`** para conferir o tamanho real do ícone.

### 15.1 O que foi CONFIRMADO (remedido, bate exato)

| item | valor auditado | como remedi |
|---|---|---|
| task / ctx / handlers | `0x8006DFDC` / `0x800E01C0` / `0x800A02F0` com **14** entradas | disasm do laço; `0x800A02F0[14]` = `0x2B302C31` (texto), logo a tabela tem 14 |
| modo em `ctx+0x04`, despacho | `0x8006E34C`: `lbu 4(ctx)`, `sltiu < 6`, salto por `0x8001104C` | `0x8001104C = {E3C0,E3C0,E3B0,E3F8,E38C,E38C}` |
| estado inicial por modo | 0/1 -> 1, 2 -> 10, 3 -> 7, 4 -> 4, 5 -> 4 | `0x80011064` é tabela de **funções** (`0x8006E490..0x8006E4B0`), cada uma faz `sb <n>,0x10(ctx)`. Os números da nota estão certos; a descrição ("tabela de estado inicial") é imprecisa |
| formato do registro de 12 B | SPRT lê `u8@+0` -> `prim+0x0C`, `u8@+2` -> `+0x0D`, `u16@+4` -> `+0x10`, `u16@+6` -> `+0x12`; RGB `0x80`; CLUT em `+0x0E` = `(clut_idx+0x1E0)<<6` (com `0x13` na parte baixa ⇒ x=304 e `code |= 2` SemiTrans) | disasm `0x8006E600`–`0x8006E6D4` inteiro |
| posicionador | `prim+8 = base[b].x + u16@+8`, `prim+0xA = base[b].y + u16@+0xA`; `a3 = cnt + base<<8 + ot<<16`; passo de prim **0x28** (2 buffers) e `+0x14` se `fb != 0` | `0x8006E8BC`–`0x8006E978` |
| TILE builder | `len=3`, `code=0x60`, **rgb=(8,8,8)**, `w` de `+4`, `h` de `+6`, passo 0x10 | `0x8006E7D4`–`0x8006E844` |
| Tabela B | `0x8009F890`, **165 registros** (termina exatamente em `0x800A004C`) | `(0x800A004C-0x8009F890)/12 = 165`; B[165] já lê `(640,328,...)` = tabela de slots |
| **GRADE 2x5, célula 40x30, origem (224,66), passo +40/+30** | **confirmado** | B[27]=`(0,72,80,120,224,66)`, B[28]=`(80,72,40,30,224,186)`, B[29]=`(80,102,40,30,264,186)`; cursor `0x800668A4`: `x=((col*4+col)<<3)=col*40` -> `ctx+0x114`, `y=((row<<4)-row)<<1=row*30` -> `ctx+0x116`; e o offset quantidade-célula é **(2,18) nas 5 linhas** (84-66, 114-96, 144-126, 174-156, 204-186) |
| `0x800A0080` (11 pares) | `(226,84)(266,84)(226,114)(266,114)(226,144)(266,144)(226,174)(266,174)(226,204)(266,204)(174,55)` | leitura direta + laço `0x8006C044` |
| `0x800A004C` (13 pares, VRAM) | `(640,328)(660,328)(640,358)(660,358)(640,388)(660,388)(640,418)(660,418)(680,328)(680,358)(680,388)(680,418)(448,328)` | leitura + `0x8006ABAC`; casa 1:1 com os `u,v` dos registros na tpage `0x9A` (word = 640 + u/2) |
| ícone 40x30 8bpp de `ITEMA.SLD` | **confirmado com margem**: implementei o LZ de `0x80010000` e **todas as 134 entradas descomprimem para exatamente 1200 B** = 40x30 8bpp; renderizadas com a CLUT `(0,485)` (índice `ctx+0xD1` = 5) saem corretas (faca, pistola, shotgun, mapa...) | ver §15.4 |
| dígito da quantidade | `u0 = 4 + d*8`, `v0 = 0x13` (19), `w=8`, `h=0xB` (11), avanço 8 | `0x8006C940`–`0x8006C99C` (offsets `prim+0x0C/0x0D/0x10/0x12` conferidos) |
| cursor | B[146]=`(120,0,40,30,224,66)`, `cnt=1`, **base_idx=0x0C**, `ot = s5*2+1 = 17` (`s5=8` em `0x8006B6B4`) -> tpage `0x3A`; CLUT `ctx+0xD3+3 = 3` com bit 16 ⇒ `(304,483)` + SemiTrans | `0x8006B4C0`–`0x8006B4DC` e `0x8006C23C`–`0x8006C254`. No atlas o bbox de tinta em `u=120,v=0` é **exatamente (120,0)-(159,29)** = 40x30 |
| piscada | `ctx+0x22` +-2, clamp `0x3F`, `ctx+0x24` direção; `rgb = counter - 0x80` ⇒ **128..191**; ciclo ~**64 frames** | `0x8006E290`–`0x8006E2F0`, `0x8006B6D0`–`0x8006B700` |
| condição / limiares | VIRUS `fl&0x100` -> 5, Poison `fl&0x200` -> 4, `hp>=101` -> 0, `>=41` -> 1, `>=21` -> 2, senão 3 | disasm completo de `0x8006E598`; base `0x800CA738` ⇒ `lhu 0x255E` = `0x800CCC96`, `lh 0x2558` = `0x800CCC90` |
| palavras da condição | `0x800A0004 + cond*12` e `prim = 0x801AC0C8 + cond*40`; os 6 retângulos contêm tinta e **não se sobrepõem** no atlas: Fine (u 1..23), Caution (27..60), Caution2 (67..100), Danger (107..141), Poison (147..175), VIRUS (185..208) | `0x8006BA34`–`0x8006BA5C` + varredura de tinta no `STMOJIU` |
| rótulos do submenu | B[152..158] com `y` 84/84/104/104/124/144/144 e `x=163`; EQUIP/USE por `*(u8*)(0x800A0514+id*4)==1` (`s7` montado em `0x8006B98C`) | leitura + `0x8006BE2C`. Byte 0 == 1 exatamente para **id 1..20** |
| placa `ITEMG.PIX` | `size=0x2800`, `lba = filetab[0x33].lba + id*5`, B[66]=`(0,0,112,72,56,88)`, `ot=25` ⇒ tpage `0x97` | `0x8006AC88` e `0x8006BB5C` (`a3 = ((s4+s5)|1)<<16 + 0x802` ⇒ cnt=2, base=8, ot=25) |
| carga de VRAM | `tagX*64` (-1024 e `y=256` se `tagX >= 0x10`), CLUT `y = tagY+480`, `tagX += (w+63)>>6` | disasm `0x800784E0`–`0x800785A4`; `0x041A` -> (640,256)/CLUT y=484, `0x001A` -> (640,256)/CLUT y=480, `0x0817` -> (448,256)/CLUT y=488 |
| headers TIM | `STMAIN0U`: 8bpp, img 256x272, **4 CLUTs** (`DX=0 DY=480 w=256 h=4`); `STMOJIU`: 4bpp, img 256x72, **9 CLUTs** (`DX=304 DY=480 w=16 h=9`) | leitura byte a byte dos dois arquivos |
| `inv+0x128` / `inv+0x129` | **confirmado, com prova mais forte que a da nota** — ver §15.3 |
| `inv+0x12A` = 8 ou 10 | **confirmado, e achei o único escritor** — ver §15.3 |
| `tpage` por faixa de `ot` | 0-7 `0x9B`, 8-15 `0x9A`, 16-23 `0x3A`, 24-31 `0x97`, 32-39 `0x17` | 5 laços em `0x8006AEB8`–`0x8006AFCC`, gravando em `ctx+0x164+ot*8` e `ctx+0x2A4+ot*8` (`0x2A4-0x164 = 0x140`, confere) |
| espaço de tela 320x240 | consistente: o maior `dx+w` das duas tabelas é **312** (B[8]: 304+8) e o maior `dy+h` é **224** (B[9]: 216+8) — incompatível com 640x480 | varredura dos 207 registros das duas tabelas |

### 15.2 ERROS ENCONTRADOS (corrigidos aqui)

1. **Tabela A tem 42 registros, não 20.** `0x8009F2EC` .. `0x8009F4D8` (último = A[41]);
   em `0x8009F4E4` começa uma **tabela de ponteiros** (`0x8006446C, 0x800646F0, 0x80064E80,
   0x80065054, 0x800650BC`). `(0x8009F4E4 - 0x8009F2EC)/12 = 42` — o próprio texto da §12 se
   contradiz ("20 registros, até `0x8009F4E4`").
   Consequência: **os índices `A[...]` da §12 estão errados** (os endereços, não). Corrigindo:

   | §12 dizia | índice real | endereço | conteúdo |
   |---|---|---|---|
   | A[5..19] | A[5..41] | `0x8009F328`.. | caixa de itens |
   | A[9] | **A[22]** | `0x8009F3F4` | grade 80x120 em (224,66) |
   | A[10] / A[11] | **A[23] / A[24]** | `0x8009F400` / `0x8009F40C` | slots 8/9 em (224,186)/(264,186) |
   | A[12] | **A[25]** | `0x8009F418` | 11º ícone em (221,24) |
   | — | **A[37]** | `0x8009F4A8` | cursor `u=120 v=0` 40x30 em (224,66) da caixa |

2. **`0x8009F678` tem 134 entradas `u32`, não 135.** A tabela vai de `0x8009F678` a
   `0x8009F88C` e **termina exatamente onde começa a Tabela B** (`0x8009F890`):
   `(0x8009F890 - 0x8009F678)/4 = 134`. Ler o índice 134 devolve `B[0].u/v` (= 0) e o 135
   devolve `B[0].w/h` (= `0x00400040`). O jogo tem **134 item_ids (0..133)** — bate com
   `ITEMG.PIX` (1372160/10240 = 134) e com as 134 entradas que descomprimem em 1200 B.
   Mesma correção para `0x8009F568` e `0x8009F5F0` na §11: o vão entre elas é de **136 bytes**
   (134 itens + 2 de padding), não 135.

3. **Retrato: a tpage é `0x9A`, não `0x9B`** (§7.3, linhas de B[2]/B[3]/B[4]).
   O posicionador `0x8006BA04`–`0x8006BA10` usa `a3 = ((s5|4)<<16) + 1` com `s5 = 8` ⇒
   **`ot = 12`**, que cai na faixa 8..15 ⇒ tpage **`0x9A`** (8bpp, x = **640**). A §9 já traz o
   `ot = s5|4 = 12` correto — a §7.3 se contradiz. Prova independente no bitmap: renderizando
   `STMAIN0U` com a paleta 2, os retratos JILL/CARLOS estão em **`x 0..39` e `x 40..79`,
   `y 192..247`**, i.e. nos pixels 0..79 da imagem; só a página `x=640` alcança esses pixels
   com `u=0/40` (a página `0x9B`, x=704, começaria no pixel 128). As linhas 448..503 da VRAM
   não são sobrescritas por STMOJI/ícones, então o retrato sobrevive ali.

4. **`sel` chega a -4, não a -2.** O teste do CIMA é `slti $v0,$sel,-2` **antes** do
   decremento (`0x80066788`), logo com `sel = -2` ainda decrementa para **-4**. Alcançáveis:
   `-1` (CIMA a partir de 1), `-2`, `-3` (CIMA a partir de -1), `-4`. ESQ/DIR gravam o novo
   `sel` **antes** de checar `< -2` (`0x80066814`/`0x80066860`) — o teste posterior só decide
   se dispara `0x800746C0`. Ou seja: são **4** posições fora da grade, não 2. (Continua
   **NÃO MEDIDO** o que é desenhado nelas.)

5. **A amarração "capacidade 8 ⇒ 5ª linha livre" (§9/§10) NÃO se sustenta como está.**
   O `cnt` da grade é **constante 3** nos dois lados: builder `0x8006B3B4`
   (`ori $a3,$s0,3`, com `$s0 = ctx+0xD1 << 8`) e posicionador `0x8006BABC`
   (`ori $a3,$s0,0x103`). Logo B[27]+B[28]+B[29] — inclusive os slots 8 e 9 em `y=186` —
   são emitidos **sempre**, independente de `inv+0x12A`. E o ícone do "slot vazio"
   (`item_id 0` do `ITEMA.SLD`) **não é transparente**: são 1200 px com 3 índices
   (`0xE3/0xE4/0xE6`) formando um padrão diagonal visível. Portanto, com `count == 8`, a 5ª
   linha (`y 186..215`) e a fileira de 6 ícones 16x16 (`y 184..199`, B[10..16]) **coexistem e
   se sobrepõem** em `x 224..303` — a menos que `base[2]` (`ctx+0xEC`, a base usada por
   B[10..16] e B[145]) esteja deslocada; `base[2]` é escrita em `0x80066B64`, `0x80067450`,
   `0x8006A604`. **NÃO RESOLVIDO** — não medi quem/quando desloca `base[2]`. Trate o texto da
   §9/§10 sobre isso como hipótese, não como medida.

6. **Duas provas citadas não sustentam o número (o número está certo, a citação não):**
   * `ITEMG.PIX` em VRAM **(448,256)**: vem de `*(u16*)0x800CCBBC = 0x0817` em `0x8006AD14`
     (⇒ `x = 0x17*64 - 1024 = 448`, `y = 256`, CLUT `y = 8+480 = 488`), **não** de
     `0x8009F4F8[0]` — essa é a tabela dos ícones da caixa, que só por acaso começa em
     (448,256) (e, aliás, colide com a placa na VRAM: placa = words 448..503 x linhas
     256..327; ícones da caixa = words 448..467 x linhas 256..495).
   * **`hp_max = 0x800CCC92`**: as instruções citadas (`0x8006E5A0`/`0x8006E5A4`) leem apenas
     `flags` e `hp`. A prova real está na cura: `0x800679A4` `lh $a1,0x2558` +
     `0x800679A8`/`0x800679B8` `lh/lhu $v0,0x255A` + `0x800679C4` `sh $v0,0x2558`
     (clamp de `hp` em `hp_max`). O valor `0x800CCC92` está **correto**.

7. **Omissão na §9 (que se declara "composição completa")**: faltam as **abas** da tela,
   desenhadas por `0x8006BAD4` (`a3 = (18<<16) + 0x103` ⇒ cnt=3, base=1, `ot=18` ⇒ tpage
   `0x3A`, atlas `STMOJIU`):

   | rect | u,v | w x h | x,y de tela | palavra (lida no bitmap) |
   |---|---|---|---|---|
   | B[149] `0x8009FF8C` | 0,40 | 32x16 | **226,44** | **FILE** |
   | B[150] `0x8009FF98` | 72,40 | 32x16 | **268,44** | **MAP** |
   | B[151] `0x8009FFA4` | 32,40 | 40x16 | **247,24** | **EXIT** |

### 15.3 Reforços de prova (a nota estava certa, mas por analogia)

* **`inv+0x129` é o `item_id` da arma equipada — agora provado direto**, não por analogia:
  `0x80069B70`–`0x80069B88` faz
  `v1 = inv[0x128]; v1 = *(u8*)(inv + v1*4); inv[0x129] = v1`, isto é
  **`inv[0x129] = slot[inv[0x128]].id`**. E `0x8006CEE8`/`0x8006CEF4` (desequipar) grava
  `inv[0x129] = 0` e `inv[0x128] = 0xFF`. `0x8006AE20` também confirma que `+0x128` é índice
  de slot: os **dois** argumentos indexam `0x800A004C` (`MoveImage` de slot VRAM para slot
  VRAM), o que só faz sentido com 0..12.
* **`inv+0x12A` (slots visíveis): achei o único escritor do EXE** —
  `0x8004954C`/`0x80049550`: `addiu $v0,$zero,0xA` + `sb $v0,0x225E($v1)` com
  `$v1 = 0x800D0000` ⇒ grava **10** em `0x800D225E`. Não há nenhum outro `sb` para
  `+0x12A`/`0x225E` no EXE, o que confirma "8 por padrão (vem do save / estado inicial),
  10 depois do evento de expansão".

### 15.4 EM ABERTO #1 RESOLVIDO: o descompressor `0x80010000`

É um LZ77 simples (disasm `0x80010000`–`0x8001009C`):

```c
u32 n = *(u32*)src; src += 4;              // numero de TOKENS
while (n--) {
    s8 b = *src++;
    if (b < 0) {                            // literal
        int len = b & 0x7f;                 // copia em palavras de 4 B, avanca len
        copy_words(dst, src, len); src += len; dst += len;
    } else {                                // referencia
        u16 v = (b << 8) | *src++;
        int dist = v & 0x7ff;
        int len  = (v >> 11) + 2;
        const u8 *p = dst - dist - 4;       // atencao: -4
        copy_words(dst, p, len); dst += len;
    }
}
```

`copy_words` = laço `lwl/lwr` + `swl/swr` de 4 em 4 bytes enquanto `len > 0` (portanto pode
copiar até 3 bytes a mais, mas os ponteiros só avançam `len`; não há propagação byte a byte
em sobreposição — é cópia de palavra).

**Validação:** aplicado às 134 entradas de `0x8009F678` sobre `ETC/ITEMA.SLD` (74288 B),
**todas as 134 saídas têm exatamente 1200 bytes** = 40x30 px 8bpp, e renderizadas com a
CLUT 1 do `STMAIN0U` (`(0,485)`, índice `ctx+0xD1 = 5`) mostram os ícones certos. Isso fecha
de forma independente: a tabela de offsets, o tamanho 40x30 e a paleta dos ícones da grade.

### 15.5 Veredito da auditoria

**PARCIAL** — a tese central e todos os números de geometria que o port precisa
(grade 2x5 de 40x30 em (224,66) com passo 40/30, tabela de retângulos de 12 B, tabelas
`0x800A004C`/`0x800A0080`, cursor, dígitos, condição, ícone de `ITEMA.SLD`, placa `ITEMG.PIX`)
**se sustentam sob remedição independente**. Os erros são pontuais e estão corrigidos acima:
contagem/índices da Tabela A, 134 vs 135 entradas de `0x8009F678`, tpage do retrato,
alcance de `sel`, a inferência sobre a 5ª linha com capacidade 8, e duas citações de prova
que não cobriam o número (valores corretos).

---

## 16. Rodada de 2026-08-08 — quatro defeitos relatados pelo dono do repo

Os quatro vieram de jogar, não de ler código. Cada conserto tem o endereço que o justifica.

### 16.1 O cursor da grade continuava por cima da tela de ARQUIVO

**Sintoma:** usar um documento do inventário (o "livro vermelho") abria a tela de arquivo e o
quadro vermelho do cursor seguia piscando na grade de itens, por cima.

**O EXE não faz isso — duas portas, as duas em `0x8006c210`..`0x8006c22c`:**

```
8006c210  lw   $v0, 0x18($s3)        ; flags de desenho
8006c218  beqz $v0, ...              ; if (!(ctx+0x18 & 0x04000000)) nao emite
8006c224  lb   $v0, 0x1c($s3)        ; sel
8006c22c  bltz $v0, 0x8006c258       ; if (sel < 0)  NAO EMITE o cursor
8006c250  jal  0x8006e8bc            ; emite B146 = 0x8009FF68 (146*12 + 0x8009f890)
```

* pelo **botão ARQ.**: entrar no sub-estado 5 vem de `sel == -2` (`0x80066728`), e `sel` fica em
  −2 enquanto a tela está aberta → o `bltz` já barra o cursor;
* **USANDO um documento**: o `menu_init` troca para o **kind 3** (`0x8006dbd0`:
  `msg − 0x85 < 0x1f` → `ctx+0x04 = 3`), cuja rotina de desenho é OUTRA (`0x8006e3f8` na tabela
  `0x8001104c`, contra `0x8006e3c0` do kind 0): ela não monta a grade de itens.

No port isso virou `MenuStatus.cursor_visivel()` (consultável, e travado em `test_arquivo.gd`):
sem cursor quando a seleção está nos botões **ou** quando `arquivo.aberto`.

### 16.2 De-para índice negativo → botão: agora MEDIDO

A §5 declarava "**não medido**". Está medido, e o que o port fazia por palpite estava certo:

* UP faz `sel -= 2` (grade de 2 colunas, `0x80066780`..`0x80066798`), então da **coluna esquerda**
  sai `-2` e da **direita** `-1`;
* `sel == -1` → sub-estado **4** (`0x800666f0`), e o sub 4 (`0x80066adc`) põe `ctx+0x10 = 4` =
  **MAPA**;
* `sel == -2` → sub-estado **5** (`0x80066728`), e o sub 5 (`0x80066ca0`) põe `ctx+0x10 = 7` =
  **ARQUIVO**;
* `sel < -2` (`slti` em `0x80066738`) → **SAIR**.

Logo: coluna esquerda → ARQ., coluna direita → MAPA, um passo acima → SAIR.

### 16.3 Som de abrir ≠ som de fechar

Está em [`exe_audio.md §5.4`](exe_audio.md): abrir a tela = SE **6** (`0x80023db8` com
`ctx+0x04 = 0`), fechar = SE **5** (`0x80066744`/`0x8006675c` + `ctx+0x10++`), e o **id 9** —
que o port usava nos dois — é *entrar no MAPA/ARQUIVO*. Também estava tocando **dois** SE por
ESC (o 5 do `cancelar` mais o 9 do `alternar`).

### 16.4 O ECG em "blocão" e a roda do mouse

* ECG: ver [`menu_ecg.md §3`](menu_ecg.md) — a onda é poligonal e passou a ser desenhada com
  `draw_line` antialiasado, rasterizando em 1280×960 em vez de 32 retângulos de 1 px × escala 4.
* **Roda do mouse** (não avançava a página de EXAMINAR nem a de documento): era lida por
  **polling** (`Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP/DOWN)`). A roda em Godot é
  **evento** e nunca fica "pressionada", então a borda nunca acontecia. Passou para `_input` com
  `InputEventMouseButton`, acumulando em `Screen._rolagem` e sendo consumida pelo tick de 30 Hz.
  Verificado injetando eventos de roda na cena real: `port/dev/diag_roda.gd`.

---

## 17. USAR num documento — o que o EXE faz, e o desvio declarado do port

**Relato do dono:** *"files ainda no inventário mesmo após clicar em usar"* — as duas Instruções
do Jogo (`0x83`/`0x84`, que vêm no template de jogo novo `0x800a018c`) seguiam ocupando slot.

### 17.1 O que o EXE faz (MEDIDO)

**O USE da tela de status não libera slot de documento — não faz nada com ele.**

`0x800676b8` (subestado 6, comando USE/EQUIP) resolve a categoria no descritor
`0x800a0514 + id*4` e faz:

```
800676fc  lbu $v0, ($v1)          ; cat = descritor[id].cat
80067704  addiu $v1, $v0, -1
80067708  sltiu $v0, $v1, 6       ; (cat-1) < 6 ?
8006770c  beqz  $v0, 0x80067b50   ; NAO  -> 0x80067b50
80067714/1c/20/28                 ; SIM  -> tabela 0x80010e34[cat-1], jr

80067b50  addiu $v0, $zero, 3
80067b54  sb    $v0, 0x11($s1)    ; ctx+0x11 = 3  (fecha a lista de comandos)
80067b58  ...epilogo, jr $ra      ; e mais nada
```

Categorias conferidas no descritor (dump de `0x800a0514`): **`0x81`/`0x82`/`0x83`/`0x84` = cat 6**,
**`0x85..0xa3` = cat 7 (arquivo)**, **`0xa4..0xab` = cat 8 (mapa)**. Logo:

* **cat 7 e 8** (`cat-1 >= 6`) caem em `0x80067b50`: sem slot, sem tela, **sem SE**;
* **cat 6** (as duas Instruções) vão para `0x80067a20` pela tabela
  `0x80010e34 = {0x80067730, 0x8006779c, 0x800677bc, 0x80067a20, 0x80067a20, 0x80067a20}`. Lá:
  `flag_test(gs+0x2474, slot.id)` (`0x80078930`, o bitfield de "itens usáveis AQUI" que o script
  da sala mantém) — se falha, mensagem 7 ("não pode usar aqui", `0x80067ad0`); se passa, grava
  `gs+0x7812 = slot.id` (`0x80067a3c`) e faz `ctx+0x10++` (`0x80067ac8`), saindo da tela. Quem
  consumiria o item seria o **script**, não o menu.

**Achado negativo, por varredura do `.text` inteiro:** o idioma que libera um slot é
`sb zero,0(rX) / sb zero,1(rX) / sh zero,2(rX)` seguido de `MoveImage(célula, 0x0b)`
(`jal 0x8006ae20`), e ele aparece em **exatamente 9 sítios**:

| endereço | contexto |
|---|---|
| `0x800679e8` | cura, aplicação `0x80067934` (o F. Aid Box `0x2a` só decrementa, `0x80067a08`) |
| `0x80064a50` | kind 2 (baú) |
| `0x8006854c` `0x800685cc` `0x8006862c` `0x800687e4` `0x800688ac` `0x800688f8` `0x80068978` | combinação (`0x80068024`+) |

**Nenhum** no caminho de documento. (E o `0x8006d0a8` que o `exe_items.md` chama de "usar/consumir"
é o **decremento de quantidade** — não há um único `jal` para ele em todo o `.text`.)

Também vale registrar: a tela de LER ARQUIVO (kind 3) não toca no inventário. O `menu_init`
converte kind 1 → 3 quando a mensagem cai em `[0x85, 0xa3]` (`0x8006dbd0`), grava
`ctx+0xbc = msg - 0x85` e chama `flag_set(0x800d212c, doc)` (`0x8006dc00`) — só o bit de "lido".

### 17.2 O que o port faz (DESVIO DECLARADO)

**Confirmado pelo dono do repo, que conhece o jogo: usar um documento LIBERA o slot, como todo
consumível. Endereço NÃO LOCALIZADO** — pelo que medi acima, o EXE não faz isso em nenhum dos 9
sítios de liberação. Fica registrado como desvio consciente, não como invenção nem descuido.

`MenuStatus._usar`, para `Itens.eh_documento(id)` (cobre cat 6 **e** cat 7):

1. `GameState.marcar_arquivo_lido(id)` — guarda pelo item CANÔNICO (`doc + 0x85`), então `0x83`
   marca o documento 0 e `0x84` o 28;
2. `main_slots[cursor] = {id: 0, qtd: 0, flags: 0}` — **libera o slot** (e solta o `equipped` se
   por acidente apontasse para ele);
3. abre a tela de ARQUIVO na leitura daquele documento.

**O documento sai do inventário mas não sai do jogo:** a grade de documentos tem slot fixo por
`doc` e o que decide ícone × VAZIO é `arquivo_lido`, então ele continua listado e legível. Travado
em `test_arquivo.gd` (276 asserções): slot zerado, `item_count` cai 1, `find_by_id(0)` passa a ser
aquele slot, `arquivo_lido` continua true, `lido(0)` na grade e `ir_para_doc` ainda abre.

### 17.3 A trilha NÃO para com o inventário aberto

Outro relato: *"entrar no inventário pausa o game (trilha também)"*. Pausar o **mundo** está
certo — `task_suspend(0)` em `0x8006d97c` e `task_resume(0)` em `0x8006e248` são os dois únicos
sítios do `.text`, e no port isso é "não chamar `mundo.tick`". Parar a BGM não seria.

**Medido na cena real** (`godot --path port --script res://dev/diag_bgm_menu.gd`), abrindo a tela
pelo bit MENU do pad e deixando 180 quadros:

| amostra | `playing` | `stream_paused` | posição |
|---|---|---|---|
| mundo rodando | true | false | 0,865 s |
| mundo rodando (+1 quadro) | true | false | 0,877 s |
| menu aberto (0) | true | false | 0,940 s |
| menu aberto (60) | true | false | 1,753 s |
| menu aberto (120) | true | false | 2,490 s |
| menu aberto (fim, 180) | true | false | 3,222 s |

A posição andou **2,2814 s** em 180 quadros de menu aberto, `get_tree().paused = false` e
`Engine.time_scale = 1` em todas as amostras. **A trilha não para — não reproduzi o defeito.**
Também não há `parar_bgm`/`bgm_player`/`time_scale`/`paused` em nenhum arquivo da tela (guarda
estática no teste).

**O que EU achei de real nessa vizinhança, e que faz o jogo parecer travado:** engasgo por quadro
na tela de ARQUIVO. `MenuArquivo._nome_do_doc` relia e reparseava `data/re3_items.json` (104 KB)
**a cada quadro** — medido em **9,85 ms por parse** (60 parses = 590,9 ms). Efeito, com um
documento lido (é o que faz o nome ser desenhado):

| cena | antes | depois |
|---|---|---|
| mundo | 11,31 ms (88 fps) | 11,50 ms (87 fps) |
| status aberto | 13,76 ms | 14,42 ms |
| **arquivo aberto** | **19,69 ms (51 fps)** | **12,68 ms (79 fps)** |
| **documento aberto** | **18,72 ms (53 fps)** | **13,00 ms (77 fps)** |

Reproduz com `godot --path port --script res://dev/diag_fps_menu.gd`. Consertado com cache
estático do JSON; e, no mesmo espírito, a **placa** do item (448×288) passou a ter cache local em
`MenuStatus._placas`, porque o LRU do `AssetIO` tem só **24** entradas (`MAX_CACHE`) e a tela toca
em mais textura que isso por quadro — sem guardar a referência, a placa podia ser redecodificada
do disco quadro a quadro.
