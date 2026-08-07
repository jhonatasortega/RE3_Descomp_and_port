# Desenho de texto (fonte) e a tela de ARQUIVO — RE3 PS1 NTSC-U

**Alvo:** `extracted/ntsc-u/SLUS_009.23` (PS-X EXE, base `0x80010000`, tsize `0xd3800`).
Offset de arquivo = `vaddr - 0x80010000 + 0x800`.
**Ferramenta:** [`tools/menu_texto.py`](../../../tools/menu_texto.py) (docstring em pt-BR com o resumo do formato).
**Saídas:** `port/data/re3_font.json`, `port/data/re3_text_en.json`, `port/data/re3_file_screen.json`,
`port/assets/FONT/*.png` (40 PNG), `port/assets/FILE/*.png` (184 PNG).
**Espaço de tela:** todas as coordenadas deste documento são em **pixels de 320×240** (o
framebuffer de jogo; sprite full-screen `w=0x140, h=0xf0` montado em `0x80029bf8`/`0x80029bfc`).

> **Não repito** o que já está provado em `menu_overlays.md` (formato dos `BIN/*.BIN`, tabela de
> arquivos do CD `0x800946a4`, `cd_read_file 0x80012818`). Uso como âncora.

---

## 1. O atlas de fonte é `ETC/TEXU.TIM` — PROVADO

### 1.1 Quem carrega, para onde

```
0x80029b94  init_texto()
  0x80029bd0  jal cd_read_file(a0 = 0x63, a1 = 0x8011a000, a2 = 1, a3 = 0x800104cc)
                                                                       ^ "TEX_TIM"
  0x80029bec  sh $v0, -0x3444($v1)      # *(u16*)0x800ccbbc = 0x001c
  0x80029be8  jal 0x800784e0(a0 = 0x8011a000)      # upload TIM -> VRAM
```

`0x63` é o índice de **`ETC/TEXU.TIM`** na tabela global de arquivos do CD (`0x800946a4`,
stride 8). Conferido: `size` da tabela == tamanho real do arquivo para as **485 primeiras
entradas** (reprodução: `tools/menu_texto.py` usa a mesma tabela; a checagem em massa está em
`menu_overlays.md §2`). `ETC/TEXJ.TIM` é `0x62` (versão JP, mesmo tamanho).

### 1.2 O alocador de VRAM — `0x800784e0`

```
0x800784e0  upload_tim(a0 = ponteiro para o TIM em RAM)
  0x8008dbe4 OpenTIM(a0) ; 0x8008dbf4 ReadTIM(&tim)      -> TIM_IMAGE* em $v0
  pag  = *(u8*)0x800ccbbc                                # 0x800ca738 + 0x2484
  prect->x = pag*64 ;  se pag >= 0x10:  prect->x -= 1024      (0x80078510..0x80078524)
  prect->y = (pag >= 0x10) ? 256 : 0                          (0x80078528..0x8007853c)
  LoadImage(prect, paddr)                                     (0x8008b2ac)
  *(u8*)0x800ccbbc += ceil(prect->w / 64)                     (0x80078560..0x8007857c)
  se caddr != 0:
      crect->y = *(u8*)0x800ccbbd + 480                       (0x80078594..0x8007859c)
      LoadImage(crect, caddr)                                 # crect->x fica o do TIM
      *(u8*)0x800ccbbd += crect->h
```

- `0x800ccbbc` = u8 **próxima página de textura**
- `0x800ccbbd` = u8 **próxima linha de CLUT** (somada a 480)
- O `sh` de 16 bits em `0x800ccbbc` escreve **os dois** de uma vez (`0x041a` = página `0x1a`,
  CLUT `0x04`).

**TEXU: página `0x1c` = 28 → x = 28·64 − 1024 = 768, y = 256.**
`ETC/TEXU.TIM` (cabeçalho lido direto do arquivo): 4 bpp, bloco de pixels `(0,0) 256×256`
halfwords = **1024×256 px**; bloco de CLUT em VRAM **(256, 480) 32×30**.
→ na VRAM a fonte ocupa **x 768..1023, y 256..511** (4 páginas de textura: 12, 13, 14, 15) e o
CLUT fica em (256,480), 32 halfwords × 30 linhas = **60 CLUTs de 16 cores** (2 por linha).

**Confirmação independente:** `0x80031a48` monta 16×2 primitivas `DR_MODE` com
`GetTPage(tp=0, abr=0, x=0x300, y=0x100)` e `GetTPage(0,0,0x340,0x100)` —
`0x300 = 768` e `0x340 = 832` são exatamente as duas primeiras páginas da faixa da fonte,
e `tp = 0` = **4 bpp**. E `draw_string` chama `GetClut(0x100 = 256, 480+…)` — o `x = 256` do
CLUT do TEXU.

### 1.3 A grade de glifos — PROVADA por desmontagem

De `0x80031804`–`0x80031848` (caminho comum de todas as variantes):

```
0x80031808  multu $a2, $s4        # s4 = 0x38e38e39  (magia p/ dividir por 18)
0x80031820  mfhi  $t1
0x80031824  srl   $v1, $t1, 2     # v1 = cod / 18                 -> LINHA
0x80031828  sll   $v0, $v1, 3
0x8003182c  addu  $v0, $v0, $v1   # v0 = linha*9
0x80031830  sll   $v0, $v0, 1     # v0 = linha*18
0x80031834  subu  $a2, $a2, $v0   # a2 = cod - linha*18            -> COLUNA
0x8003183c  sll   $v0, $a2, 3
0x80031840  subu  $v0, $v0, $a2   # v0 = coluna*7
0x80031844  sll   $v0, $v0, 1     # v0 = coluna*14
0x8003184c  sb    $v0, -2($s3)    # prim.u0
```

e a base de V (caminho normal, `0x80031784`+):

```
0x800317b4  sll   $v0, $v1, 3
0x800317b8  subu  $v0, $v0, $v1   # linha*7
0x800317bc  sll   $v0, $v0, 1     # linha*14
0x800317c0  addiu $v0, $v0, 0x1c  # + 28
0x800317c4  sb    $v0, -1($s3)    # prim.v0
```

e o tamanho da célula, `0x800317e0`–`0x800317ec`:

```
0x800317e0  lui $v0, 0xe ; ori $v0, 0xe   ->  0x000e000e
0x800317ec  sw  $v0, 2($s3)                # prim.w = 14, prim.h = 14
```

```
CÉLULA = 14 × 14 px      18 COLUNAS por linha
U = (cod % 18) * 14
V = (cod / 18) * 14 + 28        <- banco normal
```

`18 × 14 = 252 ≤ 256` (a largura de uma página de textura em 4 bpp). ✔
`0x38e38e39 = ceil(2^34 / 18)`; `mfhi(x·M) >> 2` = `x/18` para x ≤ 255. ✔

### 1.4 O de-para código → glifo

**A regra é `cod = ASCII − 0x24`** para ASCII `0x24..0x7A`, com o espaço (ASCII `0x20`)
mapeado para `cod = 0x00`. Prova dura: a função `0x80031970` recebe **ASCII** e indexa
*a mesma* tabela de larguras que `0x800319f8` indexa com o código cru:

```
0x80031974  addiu $v0, $zero, 0x20
0x80031978  beq   $a1, $v0, 0x800319c4   # ASCII espaço -> entrada 0 da tabela
0x8003197c  addiu $a3, $a1, -0x24        # índice = ASCII - 0x24
0x80031980  sltiu $v0, $a3, 0x57         # 0x57 entradas
```

Logo `'A'` (ASCII `0x41`) → índice `0x1D`; `'0'` (`0x30`) → `0x0C`; `'a'` (`0x61`) → `0x3D` —
que é exatamente o charset clássico da Capcom já usado por `tools/re3_text.py`.

**Verificação visual** (recorte célula-a-célula do atlas com a grade acima —
`port/assets/FONT/TEXU_charset_sheet.png`):

| cod | glifo | cod | glifo | cod | glifo |
|---|---|---|---|---|---|
| `00` | espaço | `16` | `:` | `37` | `+` |
| `01` | `.` | `17` | `、` | `38` | `/` |
| `02` | `▶` | `18` | `,` | `39` | `−` (traço) |
| `03` | `「` | `19` | `▲` | `3A` | `’` (apóstrofo) |
| `04` | `」` | `1A` | `!` | `3B` | `—` (travessão) |
| `05` | `(` | `1B` | `?` | `3C` | `·` |
| `06` | `)` | `1C` | `$` | `3D`–`56` | `a`–`z` |
| `07` | `『` | `1D`–`36` | `A`–`Z` | | |
| `08` | `』` | | | | |
| `09` | `“` | `0C`–`15` | `0`–`9` | | |
| `0A` | `”` | | | | |
| `0B` | `▼` | | | | |

Códigos `0x57`..`0xE9` **existem na mesma grade** (a partir de `0x57` são hiragana/katakana/
kanji — sobra da versão JP no atlas US). Não os mapeei glifo a glifo.

### 1.5 PROVA final: escrevendo palavras conhecidas

Renderizei bytes crus do EXE usando **só** a grade (18×14, V=28), a tabela de larguras e o
banco `0xEA` — sem nenhum ajuste manual:

- `0x8009bee5` = `27 4A 45 42 41 F7` → **“Knife”** ✔
- `0x8009befa` = `24 3D 4A 40 00 23 51 4A F7` → **“Hand Gun”** (com o `0x00` = espaço) ✔
- `0x8009c0ec` = `EA24 EA25 EA26 EA27 EA24 00 1F 3D 4E 40 F7` → **“S.T.A.R.S. Card”** ✔
  (as 5 primeiras são pares do banco `0xEA`, com `V = (cod/18)*14 − 46`)

### 1.6 Cores: as CLUTs da coluna x=256

`draw_string` só usa `GetClut(0x100, y)`, isto é **x = 256** (a primeira das duas CLUTs de
cada linha do bloco). Conteúdo real do bloco de CLUT do `TEXU.TIM` (cor 1 de cada, RGB555→888):

| `attr>>4` | CLUT y | cor |
|---|---|---|
| 0 | 480 | `#d8d8c8` branco/creme (normal) |
| 1 | 482 | `#00b828` **verde** (destaque de item) |
| 2 | 484 | `#980048` **magenta/rosa** |
| 3 | 486 | `#686868` **cinza** (desabilitado) |
| 4 | 488 | `#2050e8` **azul** |
| 5 | 490 | `#d8d8c8` branco/creme (igual a 0) |
| 6..15 | 492..510 | **tudo preto** — nesta coluna não há paleta (invisível) |

As paletas “reais” das linhas 491..509 estão na **coluna x=272**, não usada por `draw_string`.
Todas as 30 linhas × 2 colunas estão em `port/data/re3_font.json → cores_clut_coluna_256` e
exportadas como PNG em `port/assets/FONT/TEXU_clut_y{480..509}.png`.

### 1.7 `ETC/FONTST0U..FONTST7U.TIM` — NÃO SÃO USADOS pelo retail

- `FONTST0U.TIM` (idx `0x1f`) contém **o mesmo atlas**, mesma grade 18×14 e **mesma base V=28**,
  em 256×256 4 bpp com 16 CLUTs (bloco `(0,480) 16×16`). Confirmei visualmente: as linhas de
  glifo começam em `y=28` e batem célula a célula com a página 0 do `TEXU`.
- `FONTST1U..7U.TIM` (idx `0x21`,`0x23`,`0x25`,`0x27`,`0x29`,`0x2b`,`0x2d`) têm o **cabeçalho
  inconsistente**: o bloco de pixels declara `w=64, h=256` (32768 B) mas carrega **131072 B**
  (4× isso). São 131136 B de arquivo. Não decodifiquei o layout real.
- **Nenhum** dos índices `0x1e`..`0x2d` é passado a `cd_read_file` — nem no EXE (varri todos os
  47 sítios de `jal 0x80012818` rastreando `a0`), nem em nenhum dos 17 `BIN/*.BIN`
  (`Overlay.call_args()`). Os rótulos de debug do EXE (`0x80010300`+) listam
  `STMAIN0..3.TIM`, `STMOJI.TIM`, `ITEMA.SLD`, `FILEG.PIX`, `FILEI.TIM`, `TEX_TIM`,
  `ITEMG.PIX`, `ITEMI.PIX`, `MAP.MAP`, `ICON_DATA` — e **não** há nenhum “FONTST”.
  → **Para o port: use `TEXU.TIM`. Os `FONTST*` são carga morta em NTSC-U.**
  (Escopo: não varri os overlays de sala em `STAGE#/`.)

---

## 2. As rotinas de desenho

### 2.1 `0x80031504 draw_string(a0 = x, a1 = y, a2 = const u8 *s, a3 = attr)`

Era a função “`0x80031504` ×62, não identificada” de `menu_overlays.md §9.3`.
**É o desenhador de string** — a mais chamada pelos overlays de menu.

```
attr bits 0..2 : índice do "head" de DR_MODE (camada de desenho)
                 head = 0x800d4590 + buf*128 + (attr&7)*16     (0x80031588..0x800315a8)
                 head+0 -> tpage 0x300 (VRAM x=768) ; head+8 -> tpage 0x340 (x=832)
attr bits 4..7 : cor. CLUT y = 480 | 2*(attr>>4)                (0x8003157c..0x80031584)
attr bit  8    : 1 = proporcional (usa a tabela de larguras)
                 0 = passo FIXO de 14 px                        (0x8003158c, sp+0x14)
```

Corpo (uma primitiva `SPRT` de 20 bytes por glifo):

```
s6   = *(u32*)0x800dba94                       # ponteiro do alocador de primitivas
lim  = 0x800d8890 + 12800 * (*(u8*)0x800cc848)  # 640 SPRT por buffer, 2 buffers
if (s6 >= lim) return                          # buffer cheio
s3   = s6 + 0xe
loop (rótulo 0x800315d0):
    c = *s
    if (c == 0x00)  -> avança a largura do espaço, sem desenhar   (0x800315d0 -> 0x8003186c)
    s7 = 14                                    # passo default
    if ((u8)(c - 0xEA) < 0x15) -> tabela de salto 0x80010688[c-0xEA]
    else -> glifo normal (0x80031784)
    ...
    prim+0x04 = 0x64808080                     # code = SPRT(0x64), rgb = 128,128,128
    prim+0x08 = x | (y << 16)
    prim+0x0c = u0 ; prim+0x0d = v0
    prim+0x0e = clut ; prim+0x10 = 0x000e000e  # w=14, h=14
    AddPrim(head, prim)                        # 0x8008f5c4
    s6 += 0x14 ; s3 += 0x14
    if (s6 >= lim) -> commit e sai
    x += s7 ; s++
    if (*s != 0xFE) volta ao loop
*(u32*)0x800dba94 = s6                         # 0x800318a4 (commit)
```

**Atenção (armadilha real):** o terminador do laço é **`0xFE`**. O código `0xF7` cai na entrada
`0x800106bc` da tabela = `0x800318ac`, que é o **epílogo sem o commit** de `0x800dba94`. Ou seja,
`draw_string` com uma string terminada em `0xF7` **não reserva** as primitivas que acabou de
enfileirar. Quem desenha nome de item usa a rotina dedicada (§2.2), que termina em `0xF7`
corretamente.

### 2.2 `0x8003114c draw_item_name(a0 = x, a1 = y, a2 = attr, a3 = item_id)`

Cópia de `draw_string` com duas diferenças, ambas lidas no binário:

```
0x800311ec  jal 0x800318dc          # get_item_name(a0 = item_id & 0xff)
0x800311f4  move $s0, $v0           # s0 = ponteiro do nome
0x80031208  addiu $v0, $zero, 0xf7
0x8003120c  beq   $v1, $v0, 0x800314cc      # terminador = 0xF7
```

### 2.3 `0x80030cb8 draw_message(a0 = ctx)` — caixa de mensagem

Mesmo laço de glifos, mas com **os códigos de controle implementados** (tabela em
`0x80010610`) e um cursor de “máquina de escrever”: `0x80030d74 beq $s0, *(u32*)(ctx+0x75d4)`
para o laço no ponteiro-limite.

Bloco de estado (ctx = `0x800d4590`; endereços absolutos):

| endereço | tipo | papel | prova |
|---|---|---|---|
| `0x800dbb6e` | u16 | **y do cursor** | `0x80030fb4`/`0x80030fc0` (`+= 0x10` no `0xFC`) |
| `0x800dbb70` | u16 | **x inicial da linha** | `0x80030fb8`; escrito em `0x8002fdc8` |
| `0x800dbb72` | u16 | **y base da caixa** | `0x80030fd8`/`0x80030fe4`; escrito em `0x8002fdd0` |
| `0x800dbb76` | u16 | flags (bits 0-2 camada, bit 8 proporcional) | `0x80030d4c`..`0x80030d68` |
| `0x800dbb5b` | u8 | item “corrente” para `{item:00}` | `0x80030f80` |
| `0x800dbb64` | u32 | limite do efeito de digitação | `0x80030d6c` |
| `0x800dba94` | u32 | ponteiro do alocador de primitivas | `0x80031550`, `0x800318a8` |
| `0x800d8890` | — | base do buffer de primitivas, **12800 B por buffer** | `0x80031520`, `0x8003155c` |
| `0x800cc848` | u8 | índice do buffer (0/1) | `0x8003151c` |

**Altura de linha = 16 px** — `0x80030fb4`: `y = *(u16*)(ctx+0x75de) + 0x10`.

Duas posições de caixa medidas em `0x8002fdc4`–`0x8002fdfc` (constantes imediatas):

| pool | x | y | sítio |
|---|---|---|---|
| A | **34** (`0x22`) | **185** (`0xb9`) | `0x8002fdc4`/`0x8002fdcc` |
| B | **14** (`0x0e`) | **173** (`0xad`) | `0x8002fdf0`/`0x8002fdf8` |

E o epílogo (`0x80031c78`+) desenha 3 linhas em `x=34, y=185`, `attr = 0x100`
(`0x80031cd8`–`0x80031ce0`), passo 2 na tabela A a partir do índice `0x38` ou `0x40`.

### 2.4 Avanço por caractere — `0x800319f8`

```
0x800319f8  advance(a0 = proporcional?, a1 = cod, a2 = &x) -> passo
    if (a0 == 0)          return 14
    if ((u32)cod >= 0x57) return 14
    b0 = (s8) tbl[cod*2 + 0]
    b1 = (s8) tbl[cod*2 + 1]
    *a2 -= b0            # o glifo é desenhado em (x - b0)
    return b0 + b1       # passo do cursor
```

**Tabela de larguras = `0x80098dd0`, 0x57 = 87 entradas de 2 bytes SIGNED**, indexada pelo
**código do charset**. A entrada `0x57` em diante já é lixo (valores 53/65, 79/−2, …) — o que
confirma o limite `0x57`. Variante `0x80031970` = mesma tabela, índice `ASCII − 0x24`
(e `ASCII 0x20` → entrada 0).

Valores completos em `port/data/re3_font.json → tabela_larguras`. Amostra (cod: b0, b1 → passo):

```
00 espaço 0, 8 -> 8      1D 'A'  0,14 -> 14     3D 'a'  2,10 -> 12
01 '.'    2, 5 -> 7      25 'I'  4, 7 -> 11     45 'i'  4, 6 -> 10
0C '0'    1,12 -> 13     29 'M'  0,15 -> 15     48 'l'  4, 6 -> 10
16 ':'    4, 7 -> 11     33 'W'  0,15 -> 15     49 'm'  0,14 -> 14
3A '’'    4, 7 -> 11     2D 'Q'  0,13 -> 13     53 'w'  0,14 -> 14
```

Todos os 10 dígitos têm `(1,12)` — **dígitos são monoespaçados** (13 px). Não há tabela de
kerning por *par*: só largura por caractere.

### 2.5 Códigos de controle

Tabela de salto em **`0x80010688`** (21 entradas, código `0xEA + i`) para `draw_string`, e em
**`0x80010610`** para `draw_message`. Semântica lida nos dois:

| byte | tam. | `draw_string` (`0x80031504`) | `draw_message` (`0x80030cb8`) |
|---|---|---|---|
| `0xEA XX` | 2 | glifo, tpage A, CLUT +0, `V = (XX/18)*14 − 46` | idem |
| `0xEB XX` | 2 | glifo, tpage **B**, CLUT +0, `V = (XX/18)*14 + 0` | idem |
| `0xEC XX` | 2 | glifo, tpage **B**, CLUT +0, `V = (XX/18)*14 − 60` | idem |
| `0xED XX` | 2 | glifo, tpage A, CLUT **+10**, `V = …+0` | idem |
| `0xEE XX` | 2 | glifo, tpage A, CLUT **+10**, `V = …−60` | idem |
| `0xEF XX` | 2 | glifo, tpage **B**, CLUT **+10**, `V = …+0` | idem |
| `0xF0 XX` | 2 | glifo, tpage **B**, CLUT **+10**, `V = …−60` | idem |
| `0xF1`,`0xF2`,`0xFB` | 1 | **não são controle** — caem no glifo normal com `cod` = o próprio byte | idem |
| `0xF3 XX`,`0xF4 XX`,`0xFA XX` | 2 | consome 2 bytes, sem desenho e sem avanço | idem (`0x80030fa8`) |
| `0xF5` | 1 | avança a largura de um espaço | idem (`0x80030f48`) |
| `0xF6` | 1 | **avança 7 px** (`0x80031778`: `x += 7`) | `s6 = 7` (`0x80030f58`) |
| `0xF7` | 1 | fim (epílogo **sem** commit) | **retorna** da inserção de nome: `s = salvo + 2` (`0x80030f5c`) |
| `0xF8 XX` | 2 | consome 2 bytes, nada | **insere o nome do item XX**; `XX==0` → item corrente `0x800dbb5b` (`0x80030f68`) |
| `0xF9 XX` | 2 | consome 2 bytes, nada | **cor = XX & 0x0F** → CLUT y = 480 + 2·cor (`0x80030f94`) |
| `0xFC` | 1 | consome 1 byte, sem avanço (ignora quebra) | **nova linha**: `y += 16`, `x = x inicial` (`0x80030fb0`) |
| `0xFD XX` | 2 | consome 2 bytes, nada | **nova página**: `y = y base da caixa` (`0x80030fd8`) |
| `0xFE` | 1 | **fim da string** (commit) | fim, `y = y base` (`0x80030fe8`) |

`V` é gravado com `sb` (byte): valores negativos **dão a volta em 256** (ex.: banco `0xEA`,
`XX = 0x24` → linha 2 → `V = 28 − 46 = −18 → 238`, que é onde estão os glifos
`S.` `T.` `A.` `R.` no atlas — confirmado visualmente).

**Consequência para o port:** `draw_string` desenha **uma linha só** e ignora `0xFC`. Quem quebra
linha / pagina / troca cor é a caixa de mensagem (`0x80030cb8`). Não implemente a quebra dentro
do desenhador de string.

---

## 3. Tabelas de string no EXE

### 3.1 Nomes de item — `get_item_name` `0x800318dc`

```
0x800318dc  get_item_name(a0 = item_id) -> const u8 *
    d  = 0x800a0514 + (item_id & 0xff)*4      # descritor de 4 bytes
    b2 = d[2]
    if (b2 != 0 && flag_test(0x800d2048, b2))  item_id = (b2 - 0x55) & 0xff
    return 0x8009bee4 + *(u16*)(0x8009c7c0 + (item_id & 0xff)*2)
```

- **pool de nomes `0x8009bee4`**, terminador `0xF7`
- **tabela de offsets u16 `0x8009c7c0`**, índice = `item_id`, válida em `0x00`..`0xC1`
  (`0xC2` já cai no meio de outra string)
- **`descritor[2]` = bit de flag** no banco `0x800d2048`. Se o bit está setado, o nome
  mostrado passa a ser o do item `(b2 − 0x55) & 0xff` — é o mecanismo de **“item
  identificado”**. Isto **corrige/completa** `re3_text.py`, que não decodificava `b2`.
  Todos os 18 pares saem certos, o que fecha a prova:

  | item | `b2` | vira | item | `b2` | vira |
  |---|---|---|---|---|---|
  | `2B` Crank | `12` | `BD` Square Crank | `73` Warehouse Key | `05` | `B0` Backdoor Key |
  | `42` Lighter | `08` | `B3` Empty Lighter | `77` Clock T. Key | `13` | `BE` Bezel Key |
  | `44` Green Gem | `0A` | `B5` Emerald | `78` Clock T. Key | `14` | `BF` Winder Key |
  | `45` Blue Gem | `09` | `B4` Sapphire | `7B` Park Key | `15` | `C0` Main Gate Key |
  | `4F` Bronze Book | `10` | `BB` Book of Wisdom | `7C` Park Key | `0D` | `B8` Graveyard Key |
  | `50` Bronze Compass | `11` | `BC` Future Compass | `7D` Park Key | `16` | `C1` Rear Gate Key |
  | `5F` Rusted Crank | `0B` | `B6` Rust Hex Crank | `75` Emblem Key | `07` | `B2` (glifos `EA`) |

Gravado em `port/data/re3_text_en.json → item_names` (194 entradas, `raw` em hex + `alt_name_id`).

### 3.2 Duas pools de mensagem, com tabela de offsets — ACHADO NOVO

`re3_text.py` lia os exames por *varredura sequencial* a partir de `0x80099924`. O jogo usa
**tabelas de offset u16**, achadas em `0x8002fdd8`/`0x8002fdec` e `0x8002fe1c`/`0x8002fe04`:

| pool | tabela de offsets | base do texto | caixa (x,y) | conteúdo |
|---|---|---|---|---|
| **A** | `0x80099654` | `0x80098e88` | 34, 185 | 72 entradas: máquina de escrever, ervas, escadas, **portas trancadas**, epílogo |
| **B** | `0x8009bdb4` | `0x800996e4` | 14, 173 | 149 entradas úteis: **16 mensagens de sistema** (`0..15`), `16` vazia, `17..148` = **exames dos itens `0x01`..`0x84`** |

**Alinhamento provado:** entrada B[17] tem offset `0x240` → `0x800996e4 + 0x240 = 0x80099924`
= “Dagger knife for\nself—defense.” = exame do item `0x01`. Logo **`item_id = idx − 16`**, o
que confirma a regra `idx − 16` que `re3_text.py` já usava para o `system.xml` PT.
B[148] = offset `0x265c` = exame do item `0x84` (o último). B[149]/B[150] já são o começo da
própria tabela de offsets (`0x8009bdb4`) — **não são mensagens**.

Amostras (decodificadas pela ferramenta, `{...}` = código de controle):

```
A[ 0] 0x80098E88  '\nAn old typewriter.{page:00}I could save my progress \nif I had an {color:1}Ink Ribbon{color:0}.'
A[ 5] 0x80098F54  'You’ve used the \n{color:1}{item:00}{color:0}.'
A[22] 0x800991BE  '\nIt’s locked.{page:00}You’ll need the {color:1}{gEA:24}{gEA:25}{gEA:26}{gEA:27}{gEA:24} Key{color:0} \nto unlock it.'
A[40] 0x8009942A  'Farewell to my life. '                       <- epílogo
B[ 0] 0x800996E4  'Will you take\nthe {color:1}{item:00}{color:0}?{sp}{sp}{sp}{sp}{sp}{sp}{gFB} '
B[10] 0x80099861  'Shells still remain \nin the cartridge.\nReload unavailable.\n'
```

Isto fecha o “**EN das mensagens de porta/sistema = TODO**” de `messages.md §3`: **as de porta
e de sistema estão sim numa tabela linear do EXE** (pools A e B). Só as mensagens *por sala*
continuam nos RDT.

> **Byte de cabeçalho:** `0x800303ec`/`0x80030764` leem `((*s >> 4) & 7)` do **primeiro byte**
> da mensagem e, se for 0, usam a mini-pool `0x80098e80` (`"Yes\xFE" "No\xFE"` — as opções do
> prompt sim/não); senão o texto começa em `s + 1`. Guardei o `raw` completo no JSON para não
> perder esse byte. **O significado do nibble (nº de linhas da caixa?) NÃO ESTÁ PROVADO.**

### 3.3 Rótulos de menu — **NÃO SÃO TEXTO, SÃO SPRITE** (achado importante)

Codifiquei `"FILE"`, `"MAP"`, `"EXIT"`, `"CHECK"`, `"COMBINE"`, `"USE"`, `"EQUIP"`, `"FINE"`,
`"CAUTION"`, `"DANGER"`, `"POISON"`, `"SAVE"`, `"YES"`, `"NO"` … (47 palavras) no charset RE3 e
procurei os bytes no EXE **e nos 17 `BIN/*.BIN`**. Resultado: praticamente **zero** ocorrências
(`MAP` em `0x8009bd0b`/`0x800a0375`, `NO` em `0x800a10b4`, `OK` em `0x80099848`,
`START`/`CONTINUE` só em `MEM_CARD.BIN` `+0x440a`/`+0x43bc`).

Os rótulos estão em **`ETC/STMOJIU.TIM`** (índice `0x60`, 256×72 px 4 bpp, 9 CLUTs em VRAM
`(304,480)`), carregado por:

```
0x8006d82c  cd_read_file(a0 = 0x60, a1 = 0x801b1500, a2 = 0, a3 = 0x80010fe0 = "STMOJI.TIM")
0x8006d83c  *(u16*)0x800ccbbc = 0x001a          # página 0x1a -> VRAM x=640, y=256 ; CLUT y=480
0x8006d840  jal 0x800784e0
```

Faixas medidas por *bounding box* de tinta no atlas (`port/assets/FONT/STMOJIU_clut_y480.png`):

| `v` | altura | conteúdo |
|---|---|---|
| 0 | 17 | setas `▲ ▼ ◀ ▶` (u0 w39) · **EXIT** grande (u43 w40) · 3 molduras vazias (u120 w112, v0 h40) |
| 20 | 11 | dígitos `0`–`9` + `%` + 2 símbolos (u5 w102) |
| 33 | 7 | **Fine** u1 · **Caution** u27 · **Caution** u67 · **Danger** u107 · **Poison** u147 · 6º não identificado u185 |
| 41 | 14 | **FILE** u2 · **EXIT** u26 · **MAP** u75 · **AUTO** u116 · **MANUAL** u160 |
| 56 | 15 | **EQUIP** u2 · **USE** u53 · **COMBINE** u96 · **PIECES** u153 · **CHECK** u194 |

> Os `u`/`w` por rótulo são **medidos no atlas** (dependem do limiar de separação que usei); a
> tabela `u/v/w/h` do próprio jogo **NÃO FOI LOCALIZADA**. Os `v`/altura das faixas são firmes.

Os outros atlas de UI (`STMAIN0..3U.TIM` idx `0x58`/`0x5a`/`0x5c`/`0x5e`, `ITEMI.PIX` idx `0x34`,
`ITEMG.PIX` idx `0x33`, `CORE00.TIM` idx `0x15`, `RADAR.TIM` idx `0x44`) são da tela de status /
mapa — fora do escopo desta nota.

---

## 4. A tela de ARQUIVO (documentos)

### 4.1 O texto dos documentos é BITMAP PRÉ-RENDERIZADO

`ETC/FILEGU.PIX` (índice `0x1c`, 4 814 848 B) é **183 TIMs concatenados**, sem cabeçalho de
container. A prova é aritmética e exata:

```
soma dos 183 u32 em 0x8009ef90  ==  4 814 848  ==  os.path.getsize('ETC/FILEGU.PIX')
```

Dois formatos de página:

| tipo | tamanho | TIM | px | CLUT |
|---|---|---|---|---|
| **capa** (1ª página de cada documento) | 34 816 B | 8 bpp | `128 × 256` | `(0,480) 256×1` |
| **texto** (demais páginas) | 24 576 B | 4 bpp | `256 × 176` | `(0,480) 32×2` (4 CLUTs) |

Renderizei todas as 183 (`port/assets/FILE/`): a capa é a **arte da capa do livro** e as páginas
de texto trazem **o texto já desenhado nos pixels** (`pag_002.png` = “GAME INSTRUCTIONS A”,
`pag_003.png` = corpo do texto). **A fonte do §1 não é usada na leitura de documento.**

### 4.2 As quatro tabelas

| endereço | tipo | n | papel | prova |
|---|---|---|---|---|
| `0x8009ef90` | u32 | 183 | tamanho de cada página; `offset = Σ anteriores` | `0x8006371c`+`0x80063740`; laço de soma `0x80063754`–`0x8006376c` |
| `0x8009eed8` | u8 | 183 | byte copiado para `req+0x2a` do pedido de CD | `0x80063790`–`0x800637a4` |
| `0x8009f26c` | u16 | 31 | **primeira página** do documento (1-based) | `0x800636e8`, `0x800641e8` |
| `0x8009f2ac` | u16 | 31 | **índice da última página** (0-based) → `n_páginas = v + 1` | `0x800638c4`, `0x800639b8`, `0x80063b78` |

**Fecha exatamente:** `start[i] + last[i] + 1 == start[i+1]` para todo `i`, e
`start[30] + last[30] = 175 + 8 = 183` = a última página. E os tamanhos `34816` caem
**exatamente** nas páginas `start[i]` (1, 11, 17, 25, 28, 34, 40, 46, 53, 59, 66, 70, 77, 81, 88,
97, 102, 108, 115, 122, 127, 130, 135, 140, 145, 148, 152, 157, 162, 171, 175) — as capas.

**31 documentos ⇔ itens `0x85`..`0xA3`** (classe `0x07` = documento no descritor
`0x800a0514`): `doc = item_id − 0x85`. Confirmado pelo conteúdo: doc 0 → item `0x85`
“Game Instructions A” → `pag_002.png` = “GAME INSTRUCTIONS A”.

### 4.3 Leitura parcial do CD

`0x800636d4 abre_documento(a0 = ctx)` monta o pedido **à mão** e usa `mode = 2`:

```
pag  = *(u16*)(0x8009f26c + ctx[0xbc]*2)          # ctx+0xbc = índice do documento
req  = 0x800b9e10
req+0x28 = 0x1c                                   # índice do arquivo
req+0x14 = tam[pag-1]                             # 0x8009ef90
req+0x20 = lba(filetab[0x1c]) + (Σ tam[0..pag-2]) >> 11
req+0x2a = flag[pag-1]                            # 0x8009eed8
0x800637ac  jal cd_read_file(a0 = 0x1c, a1 = ctx[8], a2 = 2, a3 = "FILEG.PIX")
0x800637c0  *(u16*)0x800ccbbc = 0x0a17 ; jal 0x8006ebec(a0 = ctx[8])     # sobe a CAPA
0x800637d0  jal 0x800641d0(a0 = ctx, a1 = ctx[0xbc], a2 = ctx[0xbd])     # sobe a PÁGINA
```

Isto explica o `mode` (`a2`) de `cd_read_file` que ficou aberto em `menu_overlays.md §11`:
**`mode = 2` = usar o bloco de pedido já preenchido** (leitura parcial), em vez de recarregar
`size`/`lba` da tabela de arquivos.

`0x800641d0` faz o mesmo para a página de texto e sobe com
`*(u16*)0x800ccbbc = 0x0b18` + `0x800784e0` (`0x800642b8`/`0x800642bc`).

`0x8006ebec` é uma variante de `0x800784e0` que **soma** `prect->y` do TIM em vez de
sobrescrever, e **não avança** os alocadores.

### 4.4 VRAM e primitivas

| o quê | página | VRAM (x,y) | CLUT y | tpage usado no desenho |
|---|---|---|---|---|
| capa (8 bpp) | `0x17` = 23 | **448, 256** | 490 | **`0x97`** = 8 bpp, x=448, y=256 |
| página de texto (4 bpp) | `0x18` = 24 | **512, 256** | 491 | **`0x18`** = 4 bpp, x=512, y=256 |

Os quatro `SetDrawMode` estão em `0x80063ec0`/`0x80063ed4` (`a3 = 0x97`) e
`0x80063ee8`/`0x80063efc` (`a3 = 0x18`). Decodificação: `0x97` → `x = (0x97&0xf)*64 = 448`,
`y = ((0x97>>4)&1)*256 = 256`, `tp = (0x97>>7)&3 = 1` (8 bpp). `0x18` → `x = 512`, `y = 256`,
`tp = 0` (4 bpp). **Casa exatamente com as páginas 23 e 24 do alocador.** ✔

`0x80063e9c desenha_tela_arquivo(a0 = ctx)` faz 5 chamadas a
`0x8006e600(a0 = ctx /*morto*/, a1 = buffer de prims, a2 = descritor, a3 = empacotado)`:

```
a3 bits 0..7   = quantidade de descritores
a3 bits 8..15  = linha de CLUT (CLUT y = 480 + valor)
a3 bits 16..23 != 0 -> SetSemiTrans + CLUT x = 304 (em vez de 0)

descritor de 12 bytes:  +0 u8 u0 · +2 u8 v0 · +4 u16 w · +6 u16 h
(0x8006e65c..0x8006e680; +8/+10 NÃO são lidos por esta rotina)
gera DUAS SPRT idênticas de 0x14 B por descritor (uma por framebuffer)
```

| descritor | u | v | w | h | buffer | CLUT |
|---|---|---|---|---|---|---|
| `0x8009f2ec` | 0 | 0 | **128** | **168** | `0x801ada90` | `ctx[0xd7]` |
| `0x8009f2f8` | 0 | 0 | **256** | **176** | `0x801adab8` | `ctx[0xd7]+1` |
| `0x8009f310` | 12 | 0 | 12 | 12 | `0x801adae0` | `ctx[0xd3]+2`, semitrans |
| `0x8009f304` | 28 | 0 | 12 | 12 | `0x801adb08` | `ctx[0xd3]+2`, semitrans |
| `0x8009f31c` | 56 | 0 | 27 | 10 | `0x801adb80` | `ctx[0xd3]`, semitrans |

`256×176` = **exatamente** a página de texto. `128×168` = a capa (128 de largura exata; só as
168 primeiras das 256 linhas são desenhadas — e de fato a arte da capa ocupa só o topo).

**As posições de tela (x,y) das primitivas NÃO estão nesses descritores**: `0x8006e600`
escreve `prim+0x0c..0x13` (u,v,clut,w,h) mas **não** `prim+0x08` (x,y). O x,y vem dos buffers
`0x801ada90`+, que são RAM inicializada em outro lugar. **NÃO MEDIDO** — ver §6.

### 4.5 Ícones da lista — `ETC/FILEI.TIM`

Índice `0x1d`, 128×256 px 8 bpp, CLUT `(0,480) 256×1`. Carregado em `0x80063d64` e `0x80066cf4`
(rótulos `"FILEI.TIM"` em `0x80010df0` e `0x80010dfc`). Renderizado
(`port/assets/FILE/FILEI.png`): é uma **grade 4 × 8 de células de 32 × 32** com as miniaturas dos
livros/documentos → **32 células para 31 documentos**. Não achei a tabela que mapeia
documento → célula (provavelmente `célula = doc`, mas **NÃO PROVEI**).

---

## 5. Como medir de novo

```bash
# tudo (fonte + texto + tela de arquivo)
PYTHONIOENCODING=utf-8 python tools/menu_texto.py --all

# só imprimir as duas pools de mensagem decodificadas
PYTHONIOENCODING=utf-8 python tools/menu_texto.py --dump-msg

# desmontagem das rotinas-chave
python -c "import sys;sys.path.insert(0,'tools');from exe_parse import Exe;\
Exe('extracted/ntsc-u/SLUS_009.23').disasm(0x80031504,130)"      # draw_string
python -c "... .disasm(0x800319f8,20)"                            # advance
python -c "... .disasm(0x800318dc,26)"                            # get_item_name
python -c "... .disasm(0x800784e0,40)"                            # alocador de VRAM
python -c "... .disasm(0x800636d4,50)"                            # abre_documento
python -c "... .disasm(0x8006e600,45)"                            # sprite por descritor
```

Prova visual da grade (gera as palavras “Knife”, “Hand Gun”, “S.T.A.R.S. Card” a partir dos bytes
crus, usando só a grade 18×14 + `0x80098dd0`): o script está reproduzido em `§1.5`; o caminho
mecânico é `port/assets/FONT/TEXU_charset_sheet.png` (recorte de `0x00`..`0x56` em ordem de
código — se a grade estivesse errada a folha sairia embaralhada).

---

## 6. EM ABERTO

- **Posição de tela (x,y) dos sprites da tela de ARQUIVO.** `0x8006e600` não escreve `prim+8`;
  o x,y está nos buffers de primitiva `0x801ada90`/`0x801adab8`/`0x801adae0`/`0x801adb08`/
  `0x801adb80` (RAM), inicializados por código que não localizei. **NÃO MEDIDO.**
- **Como o jogo sabe quais documentos o jogador tem.** Achei o índice do documento corrente
  (`ctx+0xbc`) e o da página (`ctx+0xbd`), mas **não** o bitmap/lista de posse. Varri as funções
  `0x80063198`..`0x80067c14` procurando `flag_test`/`flag_set` e referências a
  `0x800d1f00..0x800d2400`: só apareceram `0x800d212c` (bit 30, `0x80066eb4`) e o `flag_set`
  de coleta de item (`0x80063dc0`, bancos 7 `0x800d2008` / 8 `0x800d2028`).
  **NÃO PROVADO.** Pista: os 16 bancos de flag estão em `0x8009e3f8` (banco 3 = `0x800d1fa0`,
  banco 9 = `0x800d20cc` — nenhum verificado para documentos).
- **Mapeamento documento → célula de `FILEI.TIM`.** Provável `célula = doc` (32 células, 31
  documentos), mas a tabela não foi achada. **NÃO PROVADO.**
- **Byte `flags` por página em `0x8009eed8`** (copiado para `req+0x2a`): mesmo mistério do
  `filetab[i].flags` de `menu_overlays.md §11`. Testei relação com LBA, com o tamanho e com o
  1º byte da página — nenhuma bate. **NÃO SEI.**
- **Nibble de cabeçalho da mensagem** (`(*s >> 4) & 7` em `0x800303ec`/`0x80030764`): número de
  linhas da caixa? tipo de caixa? Só sei que 0 → usa a mini-pool `0x80098e80` (`Yes`/`No`).
  **NÃO PROVADO.**
- **Glifos `0x57`..`0xE9`** do atlas: existem na grade, são kana/kanji. **Não mapeados.**
- **`FONTST1U..7U.TIM`**: cabeçalho TIM inconsistente (declara 32 768 B de pixels, tem
  131 072 B). Não decodifiquei o layout. Como **nada os carrega**, deixei de lado.
- **Onde `0x800ccbbd` (linha de CLUT) é zerado** entre telas: não rastreei. Assumi que `TEXU`
  é carregado com o alocador em 0 (é o que faz a CLUT cair em y=480, o valor que `draw_string`
  tem *hardcoded* como `0x1e0`) — isto é consistente, mas a ordem de carga não foi verificada.
- **`STMAIN0U.TIM` na VRAM**: `0x8006d80c` grava página `0x1a` (x=640, y=256) e o TIM tem
  `h=272`, o que passaria de `y=512`. Não investiguei (é tela de status, fora do escopo) —
  **suspeito de que minha leitura do alocador esteja incompleta para esse caso.**
- **`0x8002fee8` / `0x800303ec` / `0x80030764`**: são mais três variantes do desenhador
  (uma delas chama `get_item_name` em `0x8003007c`). Caracterizei só as entradas; **não
  decodifiquei os laços.**
- **Nenhuma coordenada de tela dos menus** (grade de inventário, posição da lista de arquivos,
  etc.) foi medida aqui. As únicas coordenadas provadas são as duas posições de caixa de
  mensagem (34,185) e (14,173) e as dimensões de sprite do §4.4.
