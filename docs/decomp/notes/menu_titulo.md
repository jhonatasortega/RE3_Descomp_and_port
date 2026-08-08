# Boot, tela de aviso, logo CAPCOM e MENU DE TÍTULO — RE3 PS1 NTSC-U

**Alvo:** `extracted/ntsc-u/SLUS_009.23` (PS-X EXE, base `0x80010000`, tsize `0xd3800`, entry `0x80011b80`)
+ `CD_DATA/BIN/WARNING.BIN`, `TITLE.BIN` e `CD_DATA/ETC/{WARNU,CAPCOM}.TIM`, `ETC/TITLEU.DAT`.

**Ferramentas usadas (todas rodadas de verdade):**
[`tools/exe_parse.py`](../../../tools/exe_parse.py), [`tools/overlay_parse.py`](../../../tools/overlay_parse.py),
[`tools/boot_flow.py`](../../../tools/boot_flow.py) *(novo)*, [`tools/title_sprites.py`](../../../tools/title_sprites.py) *(novo)*,
`tools/tim2png.py`, `tools/menu_extract.py`, `tools/re3_text.py`.

**Imagens geradas** (prova visual, em `docs/decomp/assets/boot/`):
`TITLE_normal_mock.png`, `TITLE_bit80_mock.png` (composição fiel do BG + SPRT nas coordenadas lidas do
binário), `TITLEU_atlas.png`, `CAPCOM.png`, `WARNU.png`, `DIEDEMO.png`, `CONTINUE.png`.

> ## ⚠ CORREÇÃO GRAVE a `docs/decomp/notes/menu_overlays.md`
>
> Aquela nota afirma **`ovl_id == file_index`**. **É FALSO.** A tabela de overlays
> `0x8009c944` NÃO está em ordem de índice de arquivo. Lendo os 24 registros
> (`python tools/boot_flow.py --ids`) e casando o campo `entry` com o overlay dono do prólogo:
>
> | ovl_id | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
> |---|---|---|---|---|---|---|---|---|---|
> | arquivo | TITLE | WARNING | MEM_CARD | DIEDEMO | OPTION | OPENING | SELECT | JILL_SEL | RESULT |
> | file_index | 0x0f | 0x10 | 0x06 | 0x00 | 0x09 | 0x08 | 0x0d | 0x04 | 0x0c |
>
> | ovl_id | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17..23 |
> |---|---|---|---|---|---|---|---|---|---|
> | arquivo | ENDING | EPILOG | STAFF_R | PC_SYS | LTSOUT | R214_OL | MUSICBOX | GEARBOX | salas |
> | file_index | 0x01 | 0x02 | 0x0e | 0x0a | 0x05 | 0x0b | 0x07 | 0x03 | 0x177.. |
>
> Consequência: **a §7 inteira de `menu_overlays.md` está com os overlays errados.**
> Tabela corrigida (`python tools/boot_flow.py --loads`):
>
> | sítio | modo | task | ovl | overlay | era escrito |
> |---|---|---|---|---|---|
> | `0x800232e4` | task | 1 | 3 | **DIEDEMO** | GEARBOX |
> | `0x800235f4` | task | 1 | 4 | **OPTION** | JILL_SEL |
> | `0x8002362c` | task | 1 | 2 | **MEM_CARD** | EPILOG |
> | `0x80024028` | task | 1 | 3 | **DIEDEMO** | GEARBOX |
> | `0x80024274` | run  | – | 9 | **ENDING** | OPTION |
> | `0x80024308` | task | 1 | 8 | **RESULT** | OPENING |
> | `0x80029c94` | task | 1 | 1 | **WARNING** | ENDING |
> | `0x80029cd8` | run  | – | 0 | **TITLE** | ENDING |
> | `0x8002a2a0` | task | 0 | 0 | **TITLE** | DIEDEMO |
> | `0x800792bc` | task | 1 | 2 | **MEM_CARD** | EPILOG |
> | TITLE `0x80195af4` | task | 1 | 2 | **MEM_CARD** | MEM_CARD ✓ |
> | TITLE `0x80195b14` | task | 1 | 10 | **EPILOG** | – |
> | TITLE `0x8019603c` | task | 1 | 6 | **SELECT** | MEM_CARD |
> | TITLE `0x801960d8` | task | 1 | 5 | **OPENING** | LTSOUT |
> | TITLE `0x801963f0` | task | 1 | 4 | **OPTION** | JILL_SEL |
> | TITLE `0x801965a8` | task | 1 | 8 | **RESULT** | OPENING |
> | TITLE `0x80196ec8` | task | 1 | 5 | **OPENING** | LTSOUT |
> | ENDING `0x801940d8` | task | 1 | 11 | **STAFF_R** | R214_OL |
> | ENDING `0x801940fc`/`412c`/`421c`/`43bc` | task | 1 | 8 | **RESULT** | OPENING |
> | ENDING `0x801941d4` | task | 1 | 7 | **JILL_SEL** | MUSICBOX |
> | ENDING `0x8019429c` | task | 1 | 2 | **MEM_CARD** | EPILOG |
>
> (A base/entry/`file_index` de cada `.BIN` em `menu_overlays.md` §4 continuam corretos —
> só a **chave `ovl_id`** do dict `OVERLAY_TABLE` de `tools/overlay_parse.py` está trocada
> por `file_index`. `boot_flow.overlay_ids()` lê a tabela certa do EXE.)

---

## 0. Espaço de tela e relógio (base para TODA coordenada desta nota)

**Resolução: 320 × 240, 15 bpp, duplo buffer vertical.** Provado em `0x800297fc` (init chamado
por `main`):

```
80029878  jal 0x8008f464   SetDefDrawEnv(0x800d42a0, x=0,   y=0,   w=0x140, h=0xf0)
80029890  jal 0x8008f464   SetDefDrawEnv(0x800d4360, x=0,   y=0xf0,w=0x140, h=0xf0)
800298a8  jal 0x8008f524   SetDefDispEnv(0x800d42fc, x=0, y=0xf0, w=0x140, ...)
800298c0  jal 0x8008f524   SetDefDispEnv(0x800d43bc, x=0, y=0,    w=0x140, ...)
```
`0x8008f464` grava `x@+0, y@+2, w@+4` (disasm `0x8008f49c`–`0x8008f4a4`); `h` = 5º argumento
(pilha `0x38($sp)` = `0xf0`). `0x8008f524` = `SetDefDispEnv` (mesmo layout).
→ **toda coordenada `x,y` desta nota é pixel de tela em 320×240, com origem no canto
superior-esquerdo, sem sinal.**

**Índice do framebuffer corrente:** `*(u8*)0x800cc848` (0 ou 1) — lido em `0x80194c90`.

**Relógio.** O laço de quadro é `0x80029294` (chamado por `main` em `0x8002927c`):

```
800292dc  jal 0x8008b000 (a0=0)          # DrawSync(0)
800292ec  lw  v0, 0x454c(0x800d0000)     # vsync_count  = *(u32*)0x800d454c
800292e8  lbu v1, 0x18c(0x800d42a0)      # divisor      = *(u8*)0x800d442c
800292f4  while (vsync_count < divisor) ;
80029304  *(u32*)0x800d454c = 0
```

`0x800d454c` é incrementado pelo callback de VSync `0x800101ac` (registrado por
`0x80080724(a0=0x800101ac)` em `0x80029858`, = `VSyncCallback`). O divisor vale **1** desde o
init (`0x80029870  sb $s2(=1), 0x18c($s0)`) e o TITLE regrava 1 (`0x8019412c`).

➜ **1 “tick” de tarefa (`yield(1)` = `0x8003203c(1)`) = 1 retraço vertical.**
Só uma outra função escreve nesse divisor: `0x80029728` grava **4**, e ela só roda quando
`*(u8*)0x800c703c != 0` (caminho de debug, `0x800292cc`).
**EM ABERTO:** o repo diz que o port usa 30 Hz. Eu **medi 1 vsync por tick (≈59.94 Hz)**; não
medi se o RE3 real perde quadros por carga de GPU. Não “corrigi” o número para 30.

**Fade / apagador de tela — `0x8002a35c`** (o motor de todas as transições desta nota):

```
0x8002a35c  fade_start(a0 = slot 0..3,
                       a1 = ?          -> byte rec+0x01   (NÃO DECODIFIQUEI)
                       a2 = flags      -> rec+0x00 = a2 | 1
                       a3 = abr        -> GetTPage(0, abr, 0, 0)  (modo de blend do GPU)
                       arg5 = RGB inicial (0x00BBGGRR? ver abaixo)
                       arg6 = RGB final
                       arg7 = T em ticks              -> rec+0x08 u16)
    rec = 0x800d443c + slot*0x44         (4 slots: 0x800d443c .. 0x800d4548)
    rec+0x02..04 = bytes de arg5 ; rec+0x05..07 = bytes de arg6
    rec+0x3c/0x3e/0x40/0x42 = x=0, y=0, w=0x140, h=0xf0   (0x8002a410..0x8002a434)
```

Atualizador por quadro `0x8002a49c` (disasm `0x8002a4d0`–`0x8002a60c`):
```
se !(rec[0] & 1) pula
se t == T:  rec[0] = (rec[0] & 2) ? (rec[0]|4) : 0 ;  cor = cor_final
senao:      t++ ; cor = c0 + (c1-c0)*t/T             (por componente, inteiro)
prim = TILE: word0 = 0x03000000 ; word1 = 0x62000000 | (B<<16)|(G<<8)|R
             xy = (rec.x, rec.y) ; wh = (rec.w, rec.h)
```
`0x62` = retângulo monocromático de tamanho variável **semitransparente** → o `abr` do
`DR_MODE` decide o blend: `abr=1` = `B+F` (aditivo), `abr=2` = `B−F` (subtrativo).

Consulta de estado: **`0x8002a6bc(slot)` devolve `rec[0]`** (é `0x800d42a0 + slot*0x44 + 0x19c`,
e `0x800d42a0+0x19c == 0x800d443c`). Convenção usada pelas telas:
`rec[0] & 4` = “chegou no fim”; `rec[0] == 0` = “acabou e desligou”.

**Modo de fundo — `0x8002a338(a0, a1)`** (`0x8002a338`–`0x8002a358`):
grava `*(u8*)0x800d442d = a0`; se `a0 == 1` grava `a1` em `+0x74` e `+0x134` do bloco
`0x800d42a0`. Lido em `0x80029378` / `0x800295dc` do laço de quadro:
* **`a0 == 2`** → chama `0x80029e3c`, que faz o *blit* do BG de tela cheia a partir do
  staging `0x8019c000` (`lui $s0, 0x8019` em `0x80194394`). “Mostre a imagem carregada”.
* **`a0 == 1`** → monta um TILE com `SetTile`/`AddPrim` (`0x800295f0`/`0x80029604`) usando a cor
  `a1`. “Limpe a tela com essa cor”.

**Pad.** Base global `0x800ca738`. Quatro palavras (montadas em `0x80038534`–`0x80038564`:
`novo = (velho ^ atual) & atual`):

| endereço | tipo | conteúdo |
|---|---|---|
| `0x800cc830` | u16 | botões **mantidos** |
| `0x800cc834` | u16 | botões **recém-pressionados** (borda) |
| `0x800cc83c` | u32 | mantidos (palavra larga) |
| `0x800cc840` | u32 | recém-pressionados (palavra larga) |

Máscaras que as telas de título usam (medidas, **não** decodifiquei o layout completo do pad):
`0x800cc834 & 0x8000` = **CIMA**, `& 0x2000` = **BAIXO**, `& 0x0800` = botão de “pular/qualquer”;
`0x800cc840 & 0x1000` = **CONFIRMA**, `& 0x2000` = **CANCELA**.
**NÃO SEI** qual botão físico é cada bit (há remapeamento configurável em `0x80038568`+).

**SFX.** `0x800746c0(a0=id, 0,0,0)`. Ids usados no título: **4** = cursor moveu,
**5** = cancelar, **6** = confirmar. (Não abri a tabela de sons.)

---

## 1. A CADEIA DE BOOT, na ordem real

```
0x80011b80  crt0  (zera 0x800c9de8..0x800e34b0, monta gp/sp)  -> jal 0x80028f38
0x80028f38  main()
              jal 0x800297fc                # init de sistema (gráfico/som/tarefas)
              laço infinito a partir de 0x80028f7c:
                 se (0x800cc858 & 0x00200000) { 0x8002a1f8(); recomeça }   # RESET p/ título
                 ... 0x80031e5c = escalonador de tarefas ...
                 0x80029294 = fim de quadro (DrawSync + espera vsync + swap)
0x800297fc  init: 320x240 (§0) ; VSyncCallback ; e em 0x80029940:
              set_task_entry(0x8003201c)(task = 0, entry = 0x80029b94)
```

`0x80029b94` é **a tarefa de boot** (task 0). Passo a passo (disasm `0x80029b94`–`0x80029cfc`):

| # | endereço | ação |
|---|---|---|
| 1 | `0x80029bb4` | `0x8002a9ac()` — abre canais DMA (`0x80090314(0xf4000001, …)`) |
| 2 | `0x80029bd0` | `cd_read_file(0x63 = ETC/TEXU.TIM, dest = 0x8011a000, mode = 1, "TEX_TIM")` |
| 3 | `0x80029bec` | `*(u16*)0x800ccbbc = 0x1c` ; `0x800784e0(0x8011a000)` → sobe TEXU.TIM para a VRAM |
| 4 | `0x80029c04` | 2 × `SetSprt` em `0x800d4310`/`0x800d43d0`, `w/h = 0x00f00140` |
| 5 | `0x80029c30` | `*(u8*)0x800d442d = 1` (modo “limpar”), `*(u8*)0x800d4436 = 0` |
| 6 | `0x80029c34`+ | sonda cartão de memória: `0x80091350(0)`, `0x800916c8(0,1,2)` |
| 7 | `0x80029c68` | `0x8008b000(0)` = DrawSync, `0x8008af68(1)` |
| 8 | `0x80029c7c` | `0x8002a338(1, 0)` = limpa a tela com preto |
| 9 | `0x80029c94` | `*(u8*)0x800d4433 = 0` ; **`load_overlay_task(task 1, ovl 1 = WARNING)`** |
| 10 | `0x80029cac` | `while (*(u8*)0x800d4433 == 0) yield(1)` — espera o WARNING sinalizar |
| 11 | `0x80029cd8` | `*(u32*)0x800cc858 |= 0x20000000` ; **`load_overlay_run(ovl 0 = TITLE)`** |

`0x800784e0(tim)` = “sobe TIM para o próximo espaço livre de VRAM” (disasm `0x800784e0`–`0x800785e0`):
```
OpenTIM/ReadTIM -> TIM_IMAGE
pg   = *(u8*)0x800ccbbc          # alocador de PÁGINA de textura
prect->x = (pg < 0x10) ? pg*64 : pg*64 - 0x400
prect->y = (pg < 0x10) ? 0      : 0x100
LoadImage(prect, paddr) ;  *(u8*)0x800ccbbc += (prect->w + 0x3f) >> 6
se tem CLUT:  crect->y = 0x1e0 + *(u8*)0x800ccbbd ; LoadImage ; *(u8*)0x800ccbbd += crect->h
DrawSync(0)
```
Logo `0x800ccbbc` (u8) = **próxima tpage livre**, `0x800ccbbd` (u8) = **próxima linha de CLUT
contada a partir de y = 480**. TEXU.TIM com `pg = 0x1c` → VRAM **(768, 256)**, CLUT em y = 480.

### Contador de arquivo → nome
`ETC/TEXU.TIM` é o índice `0x63` (2° a 3° de `ETC/TEX*`), conferido por tamanho
(`133024 B` na tabela `0x800946a4` = tamanho real do arquivo). Idem `0x67 = ETC/TITLEU.DAT`
(340072), `0x11 = ETC/CAPCOM.TIM` (153620), `0x6b = ETC/WARNU.TIM` (153620),
`0x121 = SOUND/MAIN38.BGM` (2244), `0x122 = SOUND/MAIN38.VB` (226816),
`0x123 = SOUND/MAIN39.BGM` (2996), `0x124 = SOUND/MAIN39.VB` (211632),
`0x2f = ETC/INIT_SUB.DAT` (2312), `0x30 = ETC/INIT_TBL.DAT` (2312),
`0x41/0x42/0x43 = ETC/PDEMO00/01/02.DAT` (3620 cada).

---

## 2. `WARNING.BIN` — a tela de aviso legal

Base `0x80184000`, entry **`0x80185418`**, 5664 B (3 setores). Corpo linear, sem tabela de
handler. `ETC/WARNU.TIM` = 320×240 16 bpp (`docs/decomp/assets/boot/WARNU.png`).

```
80185418  entry:
8018543c    cd_read_file(0x6b = ETC/WARNU.TIM, dest = 0x8019c000, mode = 0, "Warning")
80185448    0x8002a338(a0 = 2, a1 = 0)                # modo 2: MOSTRA o BG carregado
80185470    *(u8*)0x800d4431 = 1
80185480    fade_start(slot 0, a1=1, a2=0, abr=2,
                       de 0x00ffffff  ->  0x00000000,  T = 0x1e = 30 ticks)
                                                       # subtrativo 255->0 = FADE-IN do preto
80185488    while (0x8002a6bc(0) != 0) yield(1)        # espera o fade acabar
801854a8    s0 = 0xef ;  do { VSync(0) } while (s0-- != 0)
                                                       # === 240 RETRAÇOS VERTICAIS DE ESPERA ===
801854c8    *(u8*)0x800d4433 = 1                       # avisa a tarefa de boot
801854d4    while (*(u8*)0x800d4433 != 2) yield(1)      # TITLE grava 2 quando está pronto
8018550c    fade_start(slot 0, a1=1, a2=0, abr=2,
                       de 0x00000000  ->  0x00ffffff,  T = 30)   # FADE-OUT p/ preto
80185514    while (0x8002a6bc(0) != 0) yield(1)
8018553c    0x8002a338(1, 0) ; *(u8*)0x800d4433 = 0
80185544    0x80032070()                               # para a tarefa
```

**Duração exata: 30 ticks de fade-in + 240 VSync de exibição + 30 ticks de fade-out**, mais o
tempo de leitura de `WARNU.TIM` (75 setores).
`0xf0 = 240` chamadas de `VSync(0)`: `s0` começa em `0xef`, o teste (`bnez v0`) usa o valor
**antes** do decremento, logo a chamada acontece para `s0 = 0xef … 0x00`.

> O WARNING **fica residente** em `0x80184000` durante o TITLE (que ocupa `0x80194000`) — é por
> isso que ele consegue fazer o fade-out **depois** de o título estar carregado. O aperto de mão
> é o byte `*(u8*)0x800d4433`: `0` = nada, `1` = “aviso exibido” (WARNING → boot),
> `2` = “título pronto” (TITLE → WARNING), `0` de novo = “fade-out terminou” (WARNING → TITLE).

**Existe uma segunda máquina de estados de 20 casos** dentro de `WARNING.BIN`
(`jr` em `0x801841a4`, limite 20, variável `*(u32*)0x801855c0`, tabela em `base+0` =
`0x80184000`). **Nada no caminho de boot a alcança** — `entry` não chega lá. **NÃO SEI** para que
serve; não use.

---

## 3. `TITLE.BIN` — logo CAPCOM, título, menu, atrator

Base `0x80194000`, entry **`0x801940e8`**, 14248 B (7 setores).

### 3.1 Laço principal e contexto

```
801940e8  0x80038634(a0 = 0x5000, a1 = 0x20a)        # init de tela (não decodifiquei)
80194108  handlers = 0x801974c0                       # 5 entradas
80194114  ctx      = 0x80197508
8019411c  *(u16*)(ctx+0x16) = 0x12c (300)
80194128  *(u32*)ctx        = 0                        # estado 0
8019412c  *(u8*)0x800d442c  = 1                        # divisor de quadro = 1
80194130  laço:  f = handlers[*(u8*)ctx] ; f(ctx) ; 0x8003203c(1) ; volta
```

Tabela `0x801974c0` (5): `[0]=0x80194160 [1]=0x80194444 [2]=0x80194adc [3]=0x80195564 [4]=0x801954d0`.

**Campos do contexto `0x80197508` medidos** (todos u8 salvo indicação):

| off | endereço | conteúdo |
|---|---|---|
| `+0x00` | `0x80197508` | **estado** (índice em `0x801974c0`) |
| `+0x01` | `0x80197509` | **sub-estado** (índice em `0x801974d8`, 12 entradas) |
| `+0x02` | `0x8019750a` | estado do desenhador (índice em `0x80194044`, 10 entradas) |
| `+0x04` | `0x8019750c` | **cursor** (s8) |
| `+0x05` | `0x8019750d` | cursor do quadro anterior (s8) |
| `+0x09` | `0x80197511` | flag (posto em 1 ao fim do fade-in) |
| `+0x0a` | `0x80197512` | – |
| `+0x0c` | `0x80197514` | seletor de sub-máquina de fade em `0x80194b08` (0/2/3) |
| `+0x0d` | `0x80197515` | contador da animação de confirmação |
| `+0x0e` | `0x80197516` | **brilho pulsante do item selecionado** |
| `+0x0f` | `0x80197517` | fase do pulso |
| `+0x14` | `0x8019751c` | u16, contador auxiliar do fade |
| `+0x16` | `0x8019751e` | **u16 timeout do atrator** (300 no entry, 900 no handler 1) |
| `+0x18` | `0x80197520` | início do bloco de `SPRT` — **`0x144` bytes por framebuffer, 2 blocos** |

**Pulso do item selecionado** (`0x80195564`, handler 3):
```
ctx[0x0f] += 4
ctx[0x0e] = (s8)(*(u8*)(0x80098828 + ctx[0x0f])) / 3 - 0x80
```
`0x80098828` é uma **tabela seno de 256 bytes assinados, amplitude ±127** (lida do EXE;
`[3,6,9,…,127,127,…,-127,…,0]`, achatada nos picos). Como o valor volta como `u8`, a cor
`r=g=b` do item selecionado varia em **86 … 170** em torno do neutro 128, com período
`256/4 = 64 ticks`.

### 3.2 Estado 0 — logo CAPCOM (`0x80194160`)

Cabeçalho:
```
8019419c  *(u8*)0x800d4433 = 2      # “título pronto” -> libera o fade-out do WARNING
80194198  yield(1)
801941a4  se !(*(u32*)0x800cc858 & 0x20000000) vai p/ 0x80194374   # não veio do boot (reset)
801941c8  while (*(u8*)0x800d4433 != 0) yield(1)                    # espera o WARNING sumir
801941b4  st = 0    (registrador local; tabela de switch = 0x80194004, 10 casos)
```
Constantes do bloco: `s1 = 0x00ffffff`, `s3 = 0x1e (30)`.

| st | label | ação |
|---|---|---|
| 0 | `0x80194218` | `*(u8*)0x800e0dd0 = 2` ; `0x80197414()` = `cd_read_file(0x11 = ETC/CAPCOM.TIM, 0x8019c000, 0, "Capcom.tim")` ; `0x8002a338(1,0)` ; `fade(0, a1=0, a2=2, abr=1, 0x000000 → 0xffffff, 30)` |
| 1 | `0x80194258` | espera `fade_flags(0) & 4` |
| 2 | `0x80194274` | `0x8002a338(2,0)` (mostra CAPCOM) ; `fade(0, a1=0, a2=0, abr=1, 0xffffff → 0x000000, 30)` |
| 3 | `0x80194304` | espera `fade_flags(0) == 0` |
| 4 | `0x8019427c` | `0x801973e4()` = `cd_read_file(0x67 = ETC/TITLEU.DAT, dest 0x80130000, 0, "TITLE_DAT")` ; contador = `0x78 = 120` |
| 5 | `0x80194288` | decrementa o contador → **120 ticks de exibição** |
| 6 | `0x80194294` | `fade(0, a1=0, a2=2, abr=1, 0x000000 → 0xffffff, 30)` |
| 7 | `0x801942b8` | espera `fade_flags(0) & 4` |
| 8 | `0x801942d4` | `0x8002a338(1,0)` ; `fade(0, a1=0, a2=0, abr=1, 0xffffff → 0x000000, 30)` |
| 9 | `0x80194304` | espera `fade_flags(0) == 0` → sai |

**Por que aditivo e “para branco”:** `CAPCOM.TIM` é o logo azul/amarelo sobre **fundo branco**
(`docs/decomp/assets/boot/CAPCOM.png`). Com `abr = 1` (`B+F`), somar 0 = imagem intacta, somar
0xffffff = tela branca. A sequência é: preto → **branco** (30) → troca o modo de fundo para 2 e
**branco → logo** (30) → **120 ticks de logo** → **logo → branco** (30) → troca para modo 1
(preto) e **branco → preto** (30). O corte de imagem acontece exatamente no quadro em que a tela
está 100 % branca, então é invisível.

**Duração total da tela CAPCOM = 30 + 30 + 120 + 30 + 30 = 240 ticks** + o tempo de ler
`CAPCOM.TIM` (75 setores) no st0 e `TITLEU.DAT` (167 setores) no st4.

**Pular:** `0x8019432c` — se `*(u16*)0x800cc834 & 0x800`, faz `0x8002a338(1,0)`,
`0x8002a69c(0)`, `yield(2)`, e se `st < 5` garante o `cd_read_file` de `TITLEU.DAT`, então sai.

Saída do handler 0 (`0x801943e0`–`0x80194418`):
`*(u8*)0x800d4431 = 1` ; `fade(slot 1, a1=1, a2=2, abr=2, 0xffffff → 0xffffff, T=1)` — retângulo
**preto fixo** (`a2=2` faz o registro virar `flags|4` e continuar desenhando) ;
`*(u8*)ctx = 1`.

### 3.3 Estado 1 — carga do título (`0x80194444`)

```
80194470  *(u8*)0x800d442c = 1
80194488  fade(slot 1, a1=1, a2=2, abr=2, 0xffffff -> 0xffffff, T=1)      # tela preta
801944c0  0x8007809c(a0=0, a1 = (0x800cc858 & 0x80) ? 0xb : 1,
                     a2 = 0x801fbc00, a3 = 0x801c1814)                    # (som; não decodifiquei)
801944dc  cd_read_file(0x121 = SOUND/MAIN38.BGM, 0x801f7e00, 1, "OPTION BGM")
801944f0  0x800782f4(0, 0x38, 0x801f7e00)
80194514  0x8001245c(...) + 0x800783bc(5, ..., 0)                          # SOUND/MAIN38.VB (0x122)
8019453c  0x8002a338(1, 0) ; *(u8*)0x800d4431 = 1
8019454c  *(u16*)(ctx+0x16) = 0x384 = 900          # TIMEOUT DO ATRATOR
80194558  *(u32*)ctx = 2
80194554  0x801945e4(ctx)                          # monta os SPRT (§3.4)
80194564  ctx[0x0f] = 0 ; ctx[0x0e] = seno/3 - 0x80
8019459c  ctx[4] = ctx[5] = (0x800cc858 & 0x80) ? 0 : 1     # CURSOR INICIAL
801945bc  0x80197448()                             # sobe os gráficos do título (§3.4)
801945c8  0x8002a338(2, 0)                          # modo 2: mostra o BG do título
```

**BGM do título = `SOUND/MAIN38.BGM` + `SOUND/MAIN38.VB`** (o rótulo de debug `"OPTION BGM"`/
`"OPTIOIN VB"` é resíduo). `"OMAKE BGM"` = `SOUND/MAIN39.BGM`/`MAIN39.VB` (§3.7, Mercenaries).

`0x80197448()` (disasm `0x80197448`–`0x801974b0`):
```
se (0x800cc858 & 0x80)  memcpy(0x8019c000, 0x80155814, 0x25814)   # TIM[1] de TITLEU.DAT
senao                   memcpy(0x8019c000, 0x80130000, 0x25814)   # TIM[0] de TITLEU.DAT
*(u16*)0x800ccbbc = 0x1f05          # tpage = 5, linha de CLUT = 480 + 0x1f = 511
0x800784e0(0x8017b028)              # TIM[2] (atlas 4bpp) -> VRAM
```

**`ETC/TITLEU.DAT` = 3 TIMs concatenados** (`python tools/menu_extract.py scan …/TITLEU.DAT`):

| # | offset | endereço em RAM | formato | uso |
|---|---|---|---|---|
| 0 | `0x00000` | `0x80130000` | 320×240 16 bpp | **fundo “RESIDENT EVIL 3 NEMESIS”** |
| 1 | `0x25814` | `0x80155814` | 320×240 16 bpp | **fundo “THE MERCENARIES – OPERATION: MAD JACKAL”** |
| 2 | `0x4b028` | `0x8017b028` | 256×256 **4 bpp**, 1 CLUT de 16 cores | **atlas de texto** |

O atlas vai para **tpage 5 = VRAM (320, 0)**, 64×256 halfwords; a CLUT para **VRAM (0, 511)** →
`GetClut(0,511) = 511<<6 = 0x7fc0`, que é exatamente o `clut` gravado em todos os `SPRT`
(`s6 = 0x7fc0`, `0x801945fc`). O `DR_MODE` em `0x80194a8c` usa `tpage = 5`.
Como o atlas é 4 bpp, `u` e `v` do `SPRT` são **texels 0..255 medidos da origem da página**, isto
é, coincidem 1:1 com o pixel do PNG `docs/decomp/assets/boot/TITLEU_atlas.png`.
A CLUT é uma escala de cinza (`0,16,33,41,49,57,74,90,99,115,123,132,140,156,165,181`), índice 0
transparente — a cor final vem da modulação `r/g/b` do `SPRT` (128 = neutro).

### 3.4 Os `SPRT` do título — `0x801945e4`

Cada bloco chama `SetSprt` (EXE `0x8008f6b4`, `len=4 code=0x64`) e grava
`x0@+0x08, y0@+0x0a, u0@+0x0c, v0@+0x0d, clut@+0x0e, w@+0x10, h@+0x12`, `r/g/b @+0x04..06`.
Os slots ficam em `ctx+0x18 + fb*0x144 + off`, com `fb = *(u8*)0x800cc848` — **o bloco inteiro é
montado 2 vezes** (laço `0x80194628`…`0x80194aa4`, `sltiu v1, 2`).

Reproduzir (decodificação simbólica, não “no olho”): o script no fim desta nota (§9).

**Ramo comum**

| slot | x | y | u | v | w | h | rgb | conteúdo |
|---|---|---|---|---|---|---|---|---|
| `+0x50` | 60 | 213 | 0 | 160 | 208 | 16 | 128 | 2 linhas de copyright (`©CAPCOM CO.,LTD.1999` / `©CAPCOM U.S.A.,INC.1999 ALL RIGHTS RESERVED.`) |

**Ramo A — `*(u32*)0x800cc858 & 0x80 != 0` → THE MERCENARIES** (`0x80194684`…`0x80194890`)

| slot | x | y | u | v | w | h | rgb | rótulo |
|---|---|---|---|---|---|---|---|---|
| `+0x64` | 133 | 140 | 0 | 144 | 54 | 12 | 128 | **GAME START** |
| `+0x78` | 143 | 158 | 64 | 144 | 34 | 12 | 128 | **RESULT** |
| `+0x8c` | 130 | 176 | 0 | 128 | 60 | 12 | 128 | **GAME CONFIG** |
| `+0xa0` | 149 | 194 | 104 | 144 | 22 | 12 | 128 | **EXIT** |
| `+0xb4` | 134 | 141 | 0 | 144 | 54 | 12 | **0** | sombra de `+0x64` (+1,+1) |
| `+0xc8` | 144 | 159 | 64 | 144 | 34 | 12 | **0** | sombra de `+0x78` |
| `+0xdc` | 131 | 177 | 0 | 128 | 60 | 12 | **0** | sombra de `+0x8c` |
| `+0xf0` | 150 | 195 | 104 | 144 | 22 | 12 | **0** | sombra de `+0xa0` |

**Ramo B — bit `0x80` limpo → título normal** (`0x80194894`…`0x80194a7c`)

| slot | x | y | u | v | w | h | rótulo |
|---|---|---|---|---|---|---|---|
| `+0x64` | 68 | 193 | 0 | 104 | 48 | 12 | **NEW GAME** |
| `+0x78` | 132 | 193 | 64 | 104 | 50 | 12 | **LOAD GAME** |
| `+0x8c` | 200 | 193 | 0 | 128 | 60 | 12 | **GAME CONFIG** |
| `+0xa0` | 76 | 156 | 0 | 0 | 168 | 12 | **PRESS ANY BUTTON** |
| `+0xb4` | 80 | 193 | 0 | 128 | 60 | 12 | **GAME CONFIG** (submenu) |
| `+0xc8` | 180 | 193 | 64 | 128 | 62 | 12 | **INFORMATION** (submenu) |
| `+0xdc` | 80 | 193 | 56 | 176 | 56 | 12 | **HARD MODE** (dificuldade) |
| `+0xf0` | 180 | 193 | 0 | 176 | 54 | 12 | **EASY MODE** (dificuldade) |

Todos com `clut = 0x7fc0`, `rgb = 128,128,128`.

> **As três entradas do menu de título do RE3 US são `NEW GAME`, `LOAD GAME` e `GAME CONFIG`**
> — NÃO “OPTION”. O atlas tem a palavra “OPTION” (v=104, x131..164, largura 34) mas **nenhum
> `SPRT` a usa**. Verificação visual: `docs/decomp/assets/boot/TITLE_normal_mock.png` (composição
> do TIM[0] + estes 5 retângulos nas coordenadas acima) e `TITLE_bit80_mock.png`.

**Linhas úteis do atlas** (medidas por ocupação de pixel, `v` = linha, `x` = coluna, largura):

| v (12 px de altura) | conteúdo (x, largura) |
|---|---|
| 0 | `PRESS`(1,50) `ANY`(58,38) `BUTTON`(100,69) → bloco 0..168 |
| 16..47 | 3 linhas de copyright |
| 56 | fonte grande: `NEW`(1,39) `GAME`(48,51) `NORMAL`(104,74) `EASY`(201,46) |
| 72 | fonte grande: `LOAD`(0,46) `GAME`(50,51) `EXIT`(164,41) |
| 88 | fonte grande: `OPTION`(18,63) |
| 104 | `NEW GAME`(0,48) `LOAD GAME`(65,49) `OPTION`(131,34) |
| 120 | copyright (8 px de altura) |
| 128 | `GAME CONFIG`(0,60) `INFORMATION`(64,62) `LIGHT MODE`/`HEAVY MODE`(158..252) |
| 144 | `GAME START`(0,54) `RESULT`(64,33) `EXIT`(104,21) `SAMPLE`(128,34) |
| 160/168 | copyright ×2 (usadas juntas como um `SPRT` 208×16) |
| 176 | `EASY MODE`(0,54) `HARD MODE`(56,56) |

**Não usadas por nenhum `SPRT` de `TITLE.BIN`** (mas presentes no atlas): as linhas de fonte
grande v=56/72/88, `SAMPLE`, `LIGHT MODE`, `HEAVY MODE`, `OPTION` (v=104). **NÃO SEI** quem as usa.

### 3.5 Estado 2 — fade-in do título (`0x80194adc`)

`handler2(ctx)` = `0x80194b08(ctx)` (transição) + `0x80194c4c(ctx)` (desenho).

`0x80194b08` — máquina sobre `*(u8*)(ctx+1)`:

| sub | ação |
|---|---|
| 0 | `*(u16*)(ctx+0x14) = 0xa0 (160)` ; `ctx[0x0c] = 0` ; `ctx[1]++` e **cai** no caso 1 |
| 1 | `*(u16*)(ctx+0x14) -= 0x1e (30)`; enquanto o s16 for ≥ 0, espera → **6 chamadas**. Ao ficar negativo: `fade(slot 0, a1=0, a2=0, abr=1, 0x000000 → 0x00ffffff, T=5)` ; `*(u16*)(ctx+0x14)=0` ; `ctx[1]++` |
| 2 | espera `fade_flags(0) == 0`; então `fade(slot 1, a1=1, a2=0, abr=2, 0x00ffffff → 0x000000, T = 0x3c = 60)` = **fade-in do título em 60 ticks** ; `ctx[1]++` |
| 3 | espera `fade_flags(1) == 0`; então `ctx[0x0c]=1 ; ctx[9]=1 ; ctx[0x0a]=0 ; ctx[1]++ ; *(u32*)ctx = 3` |

### 3.6 Desenho do menu — `0x80194c4c` / `0x80194c8c`

```
0x80194c4c(ctx):  se (0x800cc858 & 0x80) 0x801952d8()   # Mercenaries
                  senao                  0x80194c8c(ctx)
```

`0x80194c8c` (título normal):
```
fb  = *(u8*)0x800cc848
s5  = ctx + 0x18 + fb*0x144            # (0x80194cbc..0x80194cd0: 324*fb + 0x18)
se (*(u8*)(ctx+0x0c) == 0) não desenha nada
brilho = *(u8*)(ctx+0x0e)
switch (*(u8*)(ctx+2))   # tabela 0x80194044, 10 casos:
   0 0x80194d48   1 0x80194e38   2 0x80194e4c   3 0x80194ef8   4 0x80194f08
   5 0x80194fe0   6 0x801950b4   7 0x801950c8   8 0x801951ac   9 0x801951bc
```

Caso 0 (menu parado, `0x80194d48`) — o que prova o mapeamento cursor↔item:
```
SetSemiTrans(s5+0x64, (cursor      ) != 0)
SetSemiTrans(s5+0x78, (cursor ^ 1  ) != 0)
SetSemiTrans(s5+0x8c, (cursor ^ 2  ) != 0)
rgb dos 3 = 128
se cursor==0 rgb(s5+0x64) = brilho ; se ==1 rgb(s5+0x78) ; se ==2 rgb(s5+0x8c)
AddPrim(*(u32*)0x800ca778 + 0xc, cada um)
```
→ **item selecionado = opaco + rgb pulsante; itens não selecionados = semitransparentes com
rgb 128.** Índice 0 = `NEW GAME`, 1 = `LOAD GAME`, 2 = `GAME CONFIG`.

Caso 1 (`0x80194e38`, animação de confirmação): `ctx[0x0d] = 5`; os 3 itens ficam
semitransparentes e `rgb = ctx[0x0d]*128/5` (multiplicação por `0x66666667` + `sra 1` = divisão
por 5, `0x80194e7c`–`0x80194ea4`).

### 3.7 Estado 3 — título interativo (`0x80195564`)

```
80195564  ctx[0x0f] += 4 ; ctx[0x0e] = seno/3 - 0x80
801955d0  jalr handlers2[*(u8*)(ctx+1)]        # tabela 0x801974d8, 12 entradas
801955dc  0x80194c4c(ctx)                       # desenha
```

Tabela `0x801974d8`:

| sub | endereço | papel medido |
|---|---|---|
| 0 | `0x801955f4` | despachante: `(0x800cc858 & 0x80) ? 0x801957f0 : 0x80195634` — **entrada do menu** |
| 1 | `0x80195c68` | **NEW GAME**: escolha de dificuldade → `INIT_TBL.DAT` → OPENING (ou SELECT no Mercenaries) |
| 2 | `0x80195988` | **LOAD GAME**: MEM_CARD (e EPILOG) |
| 3 | `0x801961d4` | (mínimo) |
| 4 | `0x801961dc` | – |
| 5 | `0x80196378` | **GAME CONFIG**: carrega OPTION |
| 6 | `0x8019644c` | – |
| 7 | `0x80196528` | carrega RESULT |
| 8 | `0x8019662c` | – |
| 9 | `0x80196634` | – |
| 10 | `0x801966cc` | **atrator: demo jogável (PDEMO)** |
| 11 | `0x80196800` | **atrator: filme OPENING** |

#### Entrada do menu — `0x80195634` (título normal)

```
80195648  *(u16*)(ctx+0x16) -= 1
8019565c  se virou 0xffff:  ctx[1] = 0xa (10)  -> ATRATOR ; retorna
80195674  pad = *(u16*)0x800cc834
8019567c  se (pad & 0x2000) ctx[4]++              # BAIXO
801956a0  se (pad & 0x8000) ctx[4]--              # CIMA
801956c4  se (ctx[4] >= 3) ctx[4] = 0             # 3 itens, com wrap
801956dc  se (ctx[4] <  0) ctx[4] = 2
801956f4  se (ctx[4] != ctx[5]) { 0x800746c0(4,0,0,0) ; *(u16*)(ctx+0x16) = 0x384 ; ctx[0x0f]=0 }
80195718  ctx[5] = ctx[4]
80195724  se ((*(u32*)0x800cc840 & 0x1000) || (pad & 0x800)) {      # CONFIRMA
80195758     ctx[0x0f] = 0
                cursor 0 -> 0x8019578c : ctx[1]=1 ; ctx[2]=1 ; ctx[0x0c]=2 ;
                                         ctx[4]=0 ; ctx[5]=0 ; SFX 6
                cursor 1 -> 0x801957b4 : ctx[1]=2
                cursor 2 -> 0x801957c0 : ctx[1]=5 ; SFX 6
          }
```

* **Timeout do atrator = 900 ticks** (`0x384`), reiniciado a cada movimento de cursor.
  O `entry` põe 300 no `ctx+0x16`, mas o handler 1 sobrescreve com 900 antes de o menu rodar.
* **Cursor inicial = 1 (`LOAD GAME`)** no título normal e **0** no Mercenaries
  (`0x8019459c`–`0x801945b8`: `beqz` do bit `0x80` cai em `sb $s1(=1)`). Medido, mas
  contra-intuitivo — **confirme em emulador antes de copiar** (é a única coisa desta seção que
  eu não consegui checar por um segundo caminho).

#### NEW GAME e a DIFICULDADE — `0x80195c68`

```
80195c84  g = *(u32*)0x800cc858
80195c8c  se (g & 0x80) vai p/ 0x80195e1c            # Mercenaries: SEM escolha de dificuldade
80195c98  se (g & 0x20) { 0x80078fe8() ; vai p/ 0x80196054 com a0 = 0x30 }
80195cb4  pad = *(u16*)0x800cc834
             se (pad & 0x2000) ctx[4]++ ; se (pad & 0x8000) ctx[4]--
80195d04  se (ctx[4] >= 2) ctx[4] = 0 ;  se (ctx[4] < 0) ctx[4] = 1     # DOIS itens
80195d34  se (ctx[4] != ctx[5]) { SFX 4 ; *(u16*)(ctx+0x16)=900 ; ctx[0x0f]=0 }
80195d64  trig = *(u32*)0x800cc840
80195d6c  se ((trig & 0x1000) || (pad & 0x800)) {            # CONFIRMA
80195db0     cursor 0 ->  *(u32*)0x800cc858 &= ~0x100        #   HARD MODE
80195dc4     cursor 1 ->  *(u32*)0x800cc858 |=  0x100        #   EASY MODE
          } senao se (trig & 0x2000) {                        # CANCELA
80195dd8     se (ctx[2] == 5) { SFX 5 ; ctx[1]=0 ; ctx[4]=0 ; ctx[5]=0 ; ctx[2]++ }
          }
```

> ### `*(u32*)0x800cc858` bit `0x100` = **EASY MODE**. Quem escreve: `0x80195dcc` (liga) e
> `0x80195db8` (desliga), **dentro de `TITLE.BIN`**, na tela de dificuldade.
> Cursor 0 = `HARD MODE` (sprite `+0xdc`, em (80,193)); cursor 1 = `EASY MODE`
> (sprite `+0xf0`, em (180,193)). Consistente com a ordem dos slots, mas o mapeamento
> slot↔índice nos casos 6..9 da tabela `0x80194044` **eu não li** — marque como “forte”, não
> “provado”.

Continuação (`0x80195f74`+), com `a0 = 0x30` posto no *delay slot* de `0x80195f8c`:

```
80195f74  *(u32*)0x800cc858 |= 0x1000 ;  *(u8*)0x800d442e = 0
80195f8c  se (0x800cc858 & 0x80) {                       # === MERCENARIES ===
80195f94      0x80078fe8(a0 = 0x30)
80195fac      cd_read_file(0x2f = ETC/INIT_SUB.DAT, dest 0x800d1d28, 0, "INIT_SUB")
80195fd0      cd_read_file(0x123 = SOUND/MAIN39.BGM, 0x801f7e00, 0, "OMAKE BGM")
80195fe4      0x800782f4(0, 0x39, 0x801f7e00)   ;  SOUND/MAIN39.VB (0x124) via 0x8001245c
8019603c      load_overlay_task(1, ovl 6 = SELECT)        # escolha de personagem
          } senao {                                       # === JOGO NORMAL ===
80196068      cd_read_file(0x30 = ETC/INIT_TBL.DAT, dest 0x800d1d28, 0, "INIT_TBL")
801960d8      load_overlay_task(1, ovl 5 = OPENING)       # filme de abertura
          }
```

> **`ETC/INIT_TBL.DAT` (índice `0x30`, 2312 B) é lido para `0x800d1d28` ao começar um jogo novo**
> — é a tabela de estado inicial (o Mercenaries usa `ETC/INIT_SUB.DAT`, índice `0x2f`, mesmo
> tamanho, mesmo destino). `0x800d1d28 = 0x800ca738 + 0x75f0`. **Não decodifiquei o layout desses
> 2312 bytes.**

#### LOAD GAME — `0x80195988`

```
80195adc  *(u32*)0x800cc858 |= 0x00040000 ;  *(u8*)0x800cc84d = 0
80195af4  load_overlay_task(1, ovl 2 = MEM_CARD)   ; yield(1)
80195b04  se (*(u8*)0x800cc84d != 0)  load_overlay_task(1, ovl 10 = EPILOG) ; yield(1)
80195b54  senao se (0x800cc858 & 0x00040000) { limpa o bit ; volta ao menu }
```
Ou seja: MEM_CARD devolve em `*(u8*)0x800cc84d` (`0x800ca738+0x2115`) um código; se ≠ 0 o TITLE
carrega **`EPILOG.BIN`** em vez de entrar no jogo. **NÃO SEI** a semântica exata desse byte
(hipótese: “o jogador escolheu ver um arquivo de EPÍLOGO”). O caminho “save carregado → jogo”
não foi rastreado até o fim.

#### GAME CONFIG — `0x80196378`

```
801963b0  fade(...)                                  # transição
801963c0  espera fade_flags & 4
801963f0  load_overlay_task(1, ovl 4 = OPTION)
801963f8  yield(1)
80196434  *(u8*)ctx = ...
```

#### Atrator — `0x801966cc` (demo) e `0x80196800` (filme)

`0x801966cc`:
```
80196754  idx = *(u8*)0x800c79af                        # 0x800c7960 + 0x4f
80196764  a0 = *(u32*)(0x801974b4 + idx*4)              # tabela = { 0x41, 0x42, 0x43 }
80196768  cd_read_file(a0, dest = 0x80192000, 0, "Pdemo")
8019677c  *(u32*)0x800c79a8 = 0x80192000
80196790  *(u8*)0x800ccc0e = *(u8*)0x80192712            # (0x800ca738 + 0x24d6)
80196794  idx = (idx + 1) % 3                            # cicla os 3 demos
801967ac  cria tarefa com entry 0x80031bdc
```
→ **3 demos jogáveis, `ETC/PDEMO00.DAT` / `PDEMO01.DAT` / `PDEMO02.DAT` (índices `0x41`/`0x42`/
`0x43`, 3620 B cada), carregados em `0x80192000`, em rodízio.** Cada arquivo tem um byte em
`+0x712` que é copiado para o estado global.

`0x80196800` faz `INIT_SUB.DAT` (`0x80196d6c`) + `OMAKE BGM` (`0x80196d90`) + `INIT_TBL.DAT`
(`0x80196e00`) e `load_overlay_task(1, ovl 5 = OPENING)` (`0x80196ec8`).

### 3.8 `0x800cc858` — os bits que eu medi

Registro global de 32 bits em `0x800cc858` (`= 0x800ca738 + 0x2120`).

| bit | onde é lido/escrito | significado medido |
|---|---|---|
| `0x00000020` | lido `0x80195c9c`, `0x8019607c`; posto `0x80024358`, `0x800383dc` | **NÃO SEI** (desvia a dificuldade) |
| `0x00000080` | lido `0x8019449c`, `0x8019459c`, `0x80194678`, `0x80194c58`, `0x801955fc`, `0x80195c8c`, `0x80197454` | **THE MERCENARIES / OPERATION: MAD JACKAL** |
| `0x00000100` | escrito `0x80195dcc` / `0x80195db8` | **EASY MODE** |
| `0x00000200` | lido `0x800232ac` | **NÃO SEI** (habilita o caminho de DIEDEMO) |
| `0x00001000` | posto `0x80195f80`; lido `0x800746e0` | “jogo iniciando” (filtra SFX) |
| `0x00004000` | posto `0x800792c0`; lido `0x80024274` | pediu tela de save/typewriter |
| `0x00040000` | posto/limpo `0x80195aec`/`0x80195b84` | tela de cartão de memória em curso |
| `0x00200000` | lido `0x800290a0` | **RESET: volta ao título** (`0x8002a1f8`) |
| `0x20000000` | posto `0x80029cd8`; lido `0x801941a8` | “o TITLE veio do boot (passou pelo WARNING)” |

**Quem SETA o bit `0x80` (Mercenaries) eu NÃO ACHEI.** Varri todos os `sw`/`sb`/`sh` para
`0x800cc858` no EXE e nos 17 overlays: só há **leituras**, mais a máscara
`0x800cc858 &= 0x80` em `0x80029ae0` (que faz o bit **sobreviver** ao reset de tela). Ou vem do
save do cartão, ou de um caminho que meu rastreador de constantes não pegou. **NÃO SEI.**

### 3.9 Reset para o título — `0x8002a1f8`

Chamado por `main` em `0x800290b0` quando `0x800cc858 & 0x00200000`:
```
8002a200  0x8003893c() ; 0x800522d8()
8002a228  DrawSync(0) ; VSync(0) ; ResetGraph(0)
8002a24c  ClearImage(rect{0,0,0x140,0x1e0}, 0,0,0)      # limpa VRAM y=0..480
8002a258  0x8002a338(1, 0)
8002a260  0x800320b8(0) ; (1) ; (2)                      # mata as tarefas 0,1,2
8002a278  0x80073fb0() ; 0x80029988()
8002a288  VSync(0)
8002a2a4  *(u32*)0x800cc830 = -1                          # “todos os botões mantidos”
8002a2a0  load_overlay_task(task 0, ovl 0 = TITLE)
```
Ou seja: no reset o TITLE **não** passa pelo WARNING nem pelo CAPCOM (bit `0x20000000` limpo →
handler 0 vai direto para `0x80194374`: `0x8002a338(1,0)` + `cd_read_file(TITLEU.DAT)`).
E o pad é preenchido com `-1` para o novo título não reagir ao botão que ainda está apertado.

---

## 4. `OPTION.BIN` (`GAME CONFIG`) — parcial

Base `0x801c2000`, entry `0x801c21b0`, 21412 B (11 setores).
Máquina: `jr` com limite 6 sobre `*(u8*)0x801c55a2`; tabelas de handler `0x801c5554` (12) e
`0x801c556c` (6), `jalr` em `0x801c24c4`/`0x801c2574`/`0x801c2598`.

Assets (rótulos de debug de `cd_read_file`):

| sítio | idx | destino | rótulo | arquivo |
|---|---|---|---|---|
| `0x801c312c` | `0x15` | `0x8019c000` | `CORE00_TIM` | `ETC/CORE00.TIM` (512×248) |
| `0x801c32e0` | `0x40` | `0x8019c000` | `Option.dat` | `ETC/OPTIONU.DAT` |
| `0x801c3448` | `0x40` | `0x8019c000` | `PaddN.tim` | `ETC/OPTIONU.DAT` |
| `0x801c4660` | `0x40` | `0x8019c000` | `Color.tim` | `ETC/OPTIONU.DAT` |

`ETC/OPTIONU.DAT` (534528 B) = **5 TIMs** (`python tools/menu_extract.py scan`):

| # | offset | formato | provável (pelos rótulos `PaddD/PaddN/Color`) |
|---|---|---|---|
| 0 | `0x00000` | 256×256 4 bpp, **2 CLUTs** | atlas de texto/ícones |
| 1 | `0x08060` | 256×256 4 bpp, **2 CLUTs** | atlas de texto/ícones |
| 2 | `0x10800` | 320×240 16 bpp | fundo (`PaddD` = *pad default*?) |
| 3 | `0x36800` | 320×240 16 bpp | fundo (`PaddN`) |
| 4 | `0x5c800` | 320×240 16 bpp | fundo (`Color`) |

O `.BIN` tem apenas 5 strings ASCII (só rótulos de arquivo) — os textos da tela estão nos
atlas 4 bpp, **não** em tabela de caracteres. **NÃO MEDI**: quais opções existem, seus valores,
posições na tela, nem onde são gravadas. A única pista concreta que colhi é o **remapeamento
configurável de botões** em `0x80038568`–`0x80038600` (percorre `*(u8*)(cfg+6)` entradas a partir
de `cfg+8`, `bit = 1 << tabela[i]`) — **onde `cfg` mora eu não determinei**.
Existem também `ETC/OPTIONJ.DAT` (JP) e a linha do atlas do título com `LIGHT MODE` / `HEAVY MODE`
que **nenhum `SPRT` de TITLE usa** — candidata a ser da OPTION. **Não provado.**

---

## 5. `MEM_CARD.BIN` (LOAD/SAVE) — textos e nomes de arquivo provados

Base `0x801c2000`, entry `0x801c20ac`, 24148 B (12 setores).
Tabelas de handler: `0x801c6878` (40) e `0x801c68c8` (20), `jalr` em `0x801c2178`/`0x801c2204`.
Fundo: `cd_read_file(0x68 = ETC/TYPE00.PIX, 0x8019c000, "MEMORY CARD BG")` em `0x801c2570`
— 153600 B = **320·240·2 cru, sem header TIM** (framebuffer direto).

**Nomes de arquivo do save no cartão PS1** (strings ASCII no overlay):

| endereço | string | uso |
|---|---|---|
| `0x801c2014` | `BASLUS-00923*` | padrão de busca (`firstfile`) |
| `0x801c2038` | `BASLUS-0092300` | nome-base |
| `0x801c2048` | `%2d%c` | formato do sufixo |
| `0x801c2058` | `BASLUS-00923` | prefixo |

**Textos da tela.** Estão na fonte própria do RE3 (charset de `tools/re3_text.py`:
`0x00=' '`, dígitos a partir de `0x0c`, `'A'=0x1d`, `'a'=0x3d`; `0xfe` = fim de string), na
faixa `0x801c6200`–`0x801c6760`. Decodificados (reproduzir com o script do §9):

```
0x801c6240  Do not save the game.
0x801c625a  Do not load the game.
0x801c6271  Memory card 1
0x801c6280  Memory card 2
0x801c628f  No
0x801c6293  Which memory card will
0x801c62ab  you save the game to?
0x801c62c2  Which memory card will
0x801c62db  you load the game from?
0x801c62f4  Checking memory cards...
0x801c630e  Overwrite?
0x801c631a  Yes
0x801c631f  No
0x801c6323  This card is not formatted.
0x801c6340  Format the memory card.
0x801c6359  Do not format the
0x801c636d  memory card.
0x801c637b  Use a memory card.
0x801c638f  Do not use a memory card.
0x801c63aa  Loading data...
0x801c63bb  CONTINUE                 <- rótulo de TIPO de save
0x801c63c5  Are you sure you want to
0x801c63e0  exit without saving?
0x801c63f6  THE MERCENARIES          <- rótulo de TIPO de save
0x801c6407  RESTART                  <- rótulo de TIPO de save
0x801c6410  Saving data...
0x801c6420  Do not pull out the cards.
0x801c643c  Which data will you load?
0x801c6457  When you load this data,
0x801c6471  select RESTART to use the
0x801c648c  items you've purchased.
0x801c64a9  Formatting failed.
0x801c64bd  Access error.
0x801c64cc  The memory card is full.
0x801c64e6  There is no data to load.
0x801c6501  Memory card is not inserted.
0x801c651f  Saving failed.
0x801c652f  Loading failed.
0x801c6540  EPILOGUE                 <- rótulo de TIPO de save
0x801c654c  This card is not formatted.
0x801c657d  Jill                     <- nome do personagem
0x801c65b9  Warehouse                <- início da tabela de LOCAIS
0x801c65c4  Alley
0x801c65cb  Hall
0x801c65d1  Dark Room
0x801c65dc  Shopping Dist.
0x801c65ec  Chapel
0x801c65f4  Living Room
0x801c6601  Park
0x801c6607  Hospital
0x801c6611  Graveyard
0x801c661c  Resting Room
0x801c662a  Monitor Room
0x801c6638  Parking Lot
0x801c6645  Machinery Room
0x801c66e1  Next Game
0x801c66ec  ???
0x801c66f1  "/00]00"  (e 10 cópias "/00]XX")   <- gabarito de HORA de jogo
0x801c6749  No data
0x801c6752  Other data
```

➜ **O que um slot mostra:** tipo do save (`CONTINUE` / `RESTART` / `THE MERCENARIES` /
`EPILOGUE` / `Next Game` / `???`), nome do personagem (`Jill`, e 11 posições em branco reservadas
antes dela), nome do local (14 nomes) e um campo de tempo no gabarito `"/00]00"`
(`'/'` e `']'` são glifos do charset — **não decodifiquei** quais; o `%2d%c` ASCII sugere
`h:mm`). **NÃO MEDI**: coordenadas de tela de nada disso, nem o layout binário do save do PS1
(bloco de 8 KB), nem o contador de saves.

---

## 6. `DIEDEMO.BIN` (morte) e `CONTINUE` — parcial

Base `0x80194000` (mesmo slot do TITLE), entry `0x80194010`, 17116 B → termina em `0x801982dc`
(**9 setores**, o carregador escreve até `0x80198800`).
Único asset: `cd_read_file(0x16 = ETC/DIEDEMO.TIM, 0x8019c000, 0, "DIEDEMO.TIM")` em `0x80197f74`.
`ETC/DIEDEMO.TIM` = **256×192** (`docs/decomp/assets/boot/DIEDEMO.png`) — note que **não** é
320×240.

Tabelas de handler: `0x80198208` (9), `0x80198228` (1), `0x8019824c` (4);
`jalr` em `0x80194128`, `0x80195314`, `0x80196414`.

Início (`0x80194010`–`0x801940b0`), com `s1 = 0x80198268` e `s2 = 0x801a0000`
(logo `-0x7dfc($s2)` = `0x80198204`, dentro do próprio overlay):
```
8019403c  *(u32*)0x801982a8 = 0 ; *(u32*)0x8019826c = 0
80194044  se (*(u32*)0x80198204 == 0) vai p/ 0x801940d0
8019405c  se (*(u16*)0x800cc834 & 0x100) ...                    # botão (borda)
80194084  fade(slot 0, a1=0, a2=2, abr=2, 0x000000 -> 0xffffffff, T = 0x20 = 32)
80194094  se (0x800cc858 & 0x200) { *(u32*)0x80198204 = 0 ; ... }
801940a8  se (0x800d1f2c & 0x20) ...                            # flag de progresso (banco 1)
```

**Quem carrega DIEDEMO** (`ovl 3`): dois sítios, ambos na função `0x80023268` do EXE:

```
800232b0  se (0x800cc858 & 0x200) {
800232c0     se (*(s16*)0x800c79ba != 0x10) { *(u16*)0x800c79ba += 1 ; sai }
800232d0     se (0x800d1f2c & 0x20) sai                  # flag de progresso (banco 1, §exe_items)
800232e4     load_overlay_task(task 1, ovl 3 = DIEDEMO)
800232ec     *(u8*)0x800dbb58 = 0
800232fc     *(s16*)0x800c79ba = -0x7530 (-30000)
80023308     0x800cc858 |= 0x40
          }
80024028  load_overlay_task(task 1, ovl 3 = DIEDEMO)     # segundo sítio
80024044  0x800cc858 = (0x800cc858 & ~0x00020000) | 0x40
```

`*(s16*)0x800c79ba` é um contador que precisa chegar a **16** antes de a tela aparecer, e depois
é jogado para **−30000**. **NÃO SEI** o que ele conta.

**`ETC/CONTINUE.TIM` (índice `0x13`, 320×240)** existe
(`docs/decomp/assets/boot/CONTINUE.png`) mas **nenhum `cd_read_file` com `a0` constante `0x13`
aparece no EXE nem nos 17 overlays** — a varredura de `--assets` (§9) não achou. Ou o índice vem
de variável, ou a tela de CONTINUE é montada de outra forma. **NÃO SEI.**
**NÃO MEDI**: os 9 estados de DIEDEMO, as opções (CONTINUE / LOAD GAME / EXIT), coordenadas,
nem os tempos.

---

## 7. `SELECT.BIN` e `JILL_SEL.BIN` — o que eles são de fato

**`SELECT.BIN` (`ovl 6`) = seleção de PERSONAGEM d’O Mercenários**, não de dificuldade.
Base `0x801c2000`, entry `0x801c2094`, 20056 B. Assets: `ETC/SELE_BGU.TIM` (`0x52` →
`0x8019c000`) e `ETC/SELE_OBU.TIM` (`0x54` → `0x80100000`), mais `PLD` (modelo) e `WEP DATA`
(arma) com índice variável. Strings (ASCII, `0x801c56e8`+) — os *loadouts*:

```
NICHOLAI]      [007SIGPRO SP2009] [005KNIFE] [005Blue Herb] [005First Aid Spray] x3
CARLOS]        [007M4A1] [005EAGLE 6.0] [005Hand Gun Bullets] [005Mixed Herb] x3
MIKHAIL]       [007BENELLI M3S] [005M629C] [005ROCKET LAUNCHER]
               [005Shotgun Shells] [005Magnum Bullets] [005Mixed Herb]
Chris Redfield] [007Beretta-M92FS.] [005Remington M1100.] [005Rocket Launcher]
               [005Ink Ribbon] [005F.Aid Spray]
```
O prefixo `[00N` é código de controle da fonte (`N` = tamanho/cor); `]` = fim de linha.
O 4º *loadout* (`Chris Redfield`) **não sei** se é usado.

**`JILL_SEL.BIN` (`ovl 7`) = seleção de ROUPA da Jill.** Base `0x801c2000`, entry `0x801c2050`,
7664 B. Assets: `ETC/JILL_BGU.TIM` (`0x36` → `0x8019c000`) e `ETC/JILL_OBU.TIM` (`0x38` →
`0x80100000`), mais `PLD`/`WEP DATA` com índice variável. Só 2 strings ASCII. `switch` de 5 casos
sobre `*(u8*)0x801c3490`; tabela de handler `0x801c3468` (3).
Carregado por `0x800235f4`?→**não**: por `ENDING.BIN` em `0x801941d4`
(`load_overlay_task(1, ovl 7)`), i.e. o fluxo pós-ending.
**NÃO MEDI**: quantas roupas, coordenadas, o que grava.

**`PC_SYS.BIN` (`ovl 12`) não é menu**: é o terminal de computador do jogo (senhas
`ADRAVIL`/`SAFSPRIN`/`AQUACURE`, textos “Umbrella Security System”, “NOTICE TO STARS PERSONNEL”).

---

## 8. RESUMO EXECUTÁVEL DO FLUXO (para o implementador)

```
crt0 0x80011b80 -> main 0x80028f38 -> init 0x800297fc -> task0 = 0x80029b94
  |
  +-- carrega ETC/TEXU.TIM em VRAM (768,256)
  +-- WARNING (ovl 1)  : WARNU.TIM 320x240  | fade-in 30 | ESPERA 240 VSync | fade-out 30
  +-- 0x800cc858 |= 0x20000000
  +-- TITLE (ovl 0), estado 0:
  |      CAPCOM.TIM 320x240 | preto->branco 30 | branco->logo 30 | 120 ticks
  |                         | logo->branco 30 | branco->preto 30
  |      (pular: 0x800cc834 & 0x800)
  |      carrega ETC/TITLEU.DAT em 0x80130000
  +-- TITLE estado 1: BGM MAIN38 ; monta SPRT ; timeout = 900 ticks
  +-- TITLE estado 2: espera 6 ticks | flash branco 5 | fade-in 60
  +-- TITLE estado 3: MENU  ->  cursor 0/1/2 =  NEW GAME | LOAD GAME | GAME CONFIG
         cursor 0 -> DIFICULDADE (HARD MODE x=80 / EASY MODE x=180, y=193)
                     0x800cc858 bit 0x100 = EASY
                     -> ETC/INIT_TBL.DAT em 0x800d1d28 -> OPENING (ovl 5) -> jogo
         cursor 1 -> MEM_CARD (ovl 2)  [-> EPILOG (ovl 10) se 0x800cc84d != 0]
         cursor 2 -> OPTION (ovl 4)
         timeout 900 -> sub 10: PDEMO00/01/02.DAT em 0x80192000 (rodízio)
                     ou sub 11: OPENING (ovl 5)
  |
  +-- (0x800cc858 & 0x80) troca TUDO para THE MERCENARIES:
         BG = TIM[1] de TITLEU.DAT, BGM = MAIN39, menu vertical de 4 itens
         GAME START (133,140) / RESULT (143,158) / GAME CONFIG (130,176) / EXIT (149,194)
         cada um com sombra preta em (+1,+1) ; NEW GAME -> INIT_SUB.DAT -> SELECT (ovl 6)
  |
  +-- reset: 0x800cc858 & 0x200000 -> 0x8002a1f8 -> TITLE em task 0 (sem WARNING/CAPCOM)
```

---

## 9. COMO MEDIR DE NOVO

```bash
# tabela de overlays CORRIGIDA + todos os sitios de carga (EXE + 17 overlays)
PYTHONIOENCODING=utf-8 python tools/boot_flow.py --ids
PYTHONIOENCODING=utf-8 python tools/boot_flow.py --loads

# recorta os SPRT do titulo do atlas de TITLEU.DAT (gera os PNG desta nota)
PYTHONIOENCODING=utf-8 python tools/title_sprites.py docs/decomp/assets/boot

# imagens de tela cheia
PYTHONIOENCODING=utf-8 python tools/tim2png.py docs/decomp/assets/boot \
  extracted/ntsc-u/CD_DATA/ETC/{CAPCOM,WARNU,DIEDEMO,CONTINUE,CORE00}.TIM

# TIMs dentro dos .DAT
PYTHONIOENCODING=utf-8 python tools/menu_extract.py scan extracted/ntsc-u/CD_DATA/ETC/TITLEU.DAT
PYTHONIOENCODING=utf-8 python tools/menu_extract.py scan extracted/ntsc-u/CD_DATA/ETC/OPTIONU.DAT
```

Decodificação simbólica dos `SPRT` (o que gerou a tabela do §3.4 — **não** foi leitura “no olho”):

```python
import sys, re; sys.path.insert(0, 'tools')
from overlay_parse import Overlay
o = Overlay('TITLE')
FLD = {8:'x', 0xa:'y', 0xc:'u', 0xd:'v', 0xe:'clut', 0x10:'w', 0x12:'h', 4:'r', 5:'g', 6:'b'}
regs, cur, recs = {}, None, []
for a, m, op, _ in o.disasm(0x801945e4, 0x140, show=False):
    if a >= 0x80194adc: break
    ops = [x.strip() for x in op.split(',')] if op else []
    if m == 'lui'  and len(ops) == 2: regs[ops[0]] = int(ops[1], 0) << 16
    elif m == 'addiu' and len(ops) == 3:
        v = int(ops[2], 0); v -= 0x10000 if v >= 0x8000 else 0
        b = 0 if ops[1] == '$zero' else regs.get(ops[1])
        regs[ops[0]] = None if b is None else b + v
        if ops[0] == '$s3' and ops[1] == '$s5': cur = {'off': v}; recs.append((a, cur))
    elif m == 'move' and len(ops) == 2:
        regs[ops[0]] = 0 if ops[1] == '$zero' else regs.get(ops[1])
    elif m in ('sh', 'sb') and '(' in op:
        mm = re.match(r'(\$\w+), (-?\w+)\((\$\w+)\)', op)
        if mm and mm.group(3) == '$s3' and cur is not None:
            src = mm.group(1)
            cur[FLD.get(int(mm.group(2), 0))] = 0 if src == '$zero' else regs.get(src)
    elif ops and ops[0].startswith('$') and m not in ('sh','sb','sw','jal','jalr','j','jr'):
        regs[ops[0]] = None
for a, r in recs: print('%08x +0x%02x %s' % (a, r['off'], r))
```

Textos do `MEM_CARD` na fonte do RE3:

```python
import sys; sys.path.insert(0, 'tools')
from overlay_parse import Overlay
import re3_text
cs = re3_text.load_charset()          # 0x00=' ', digitos ~0x0c, 'A'=0x1d, 'a'=0x3d
o, cur = Overlay('MEM_CARD'), bytearray()
b = o.bytes_at(0x801c6200, 0x680)
for i, x in enumerate(b):
    if x == 0xfe:
        print('%08x  %s' % (0x801c6200 + i - len(cur),
              ''.join(cs.get(c, '{%02x}' % c) for c in cur))); cur = bytearray()
    else: cur.append(x)
```

---

## 10. EM ABERTO / NÃO MEDIDO

1. **Unidade de tempo.** Medi `divisor = *(u8*)0x800d442c = 1` → 1 tick = 1 retraço vertical
   (≈59.94 Hz). O port do repo usa 30 Hz. **Não resolvi a contradição** e não converti nenhum
   número: os tempos desta nota estão em **ticks de tarefa** (`yield`), exceto os 240 do WARNING
   que são **`VSync(0)` cru**.
2. **Cursor inicial do título = 1 (`LOAD GAME`).** Medido em `0x801945b4`, mas contra-intuitivo.
   Único item desta nota que eu recomendo confirmar em emulador.
3. **Quem seta `0x800cc858 & 0x80` (Mercenaries).** Nenhuma escrita no EXE nem nos 17 overlays.
   Só a máscara de sobrevivência `&= 0x80` em `0x80029ae0`. **NÃO SEI.**
4. **`0x800cc858` bits `0x20` e `0x200`.** Desviam a dificuldade e o DIEDEMO. Significado **NÃO SEI**.
5. **`a1` de `0x8002a35c`** (vai para `rec+0x01`): sempre 0 ou 1 ou 7 nos sítios que li.
   **NÃO DECODIFIQUEI.**
6. **Ordem dos bytes de cor** em `arg5`/`arg6` de `0x8002a35c`: gravo `b0→rec+2, b1→rec+3,
   b2→rec+4` e o prim monta `(rec+4)<<16 | (rec+3)<<8 | (rec+2)`. Como todos os valores usados são
   `0x000000` ou `0x00ffffff` (cinzas), **não consegui distinguir R de B**. Para cores não-cinzas,
   MEÇA.
7. **Layout do pad.** Sei as máscaras usadas (`0x8000` cima, `0x2000` baixo, `0x800` “qualquer”,
   `0x1000` confirma, `0x2000` cancela na palavra larga) mas **não** o botão físico de cada bit,
   nem a tabela de remapeamento (`0x80038568`+).
8. **`OPTION.BIN`**: nenhuma opção, valor, coordenada ou local de armazenamento medido. Só os
   assets e a forma da máquina de estados.
9. **`MEM_CARD.BIN`**: tenho todos os textos e os nomes de arquivo, mas **zero coordenada de
   tela** e **zero** do layout binário do save do PS1.
10. **`DIEDEMO.BIN`**: 9 estados não lidos; opções de CONTINUE não medidas; e
    `ETC/CONTINUE.TIM` **não tem carregador com índice constante** em nenhum dos 18 módulos.
11. **`JILL_SEL.BIN`**: quantas roupas, coordenadas, e o que grava — **não medido**.
12. **`0x80038634(0x5000, 0x20a)`** (init de tela chamado por TITLE/entry) e
    `0x8007809c` / `0x800782f4` / `0x800783bc` / `0x8001245c` (cadeia de som): **não decodificados**.
13. **`ETC/INIT_TBL.DAT` / `ETC/INIT_SUB.DAT`** (2312 B cada, carregados em `0x800d1d28`):
    é o estado inicial de jogo novo, mas **não abri o formato**.
14. **A máquina de 20 estados dentro de `WARNING.BIN`** (`0x801841a4`, var `0x801855c0`):
    inalcançável pelo `entry`. **NÃO SEI** para que serve.
15. **Linhas do atlas do título sem consumidor** (`v=56/72/88` fonte grande, `SAMPLE`,
    `LIGHT MODE`, `HEAVY MODE`, `OPTION` em `v=104`): **NÃO SEI** quem as desenha.
16. **`*(u8*)0x800cc84d`** (retorno do MEM_CARD que faz o TITLE carregar `EPILOG`): semântica
    **NÃO SEI**.
17. **`*(u8*)0x800e0dd0 = 2`** antes de carregar CAPCOM.TIM, e `*(u8*)0x800d4431 = 1`:
    papel **não decodificado**.

---

## 11. IMPLEMENTADO no port → [`boot_ptbr_hd.md`](boot_ptbr_hd.md)

O fluxo desta nota está **implementado e rodando** em `port/scenes/boot.tscn`
(`present/boot.gd`, `titulo.gd`, `video.gd`), com teste em `port/dev/tests/test_boot.gd`.
O doc de implementação é [`boot_ptbr_hd.md`](boot_ptbr_hd.md); o que ele acrescenta de
**evidência nova** a esta nota:

* **§1.1 — a unidade de tempo (item §10.1 acima).** Não foi resolvida, mas foi **corroborada**:
  a 59,94 Hz o timeout do atrator de 900 ticks dá **15,0 s**, que é um tempo de atração
  plausível; a 30 Hz daria 30 s. O port converte (2 ticks por quadro de 30 Hz) em vez de
  reescrever o número medido.
* **§2 — ⚠ o casamento HD do repo pegou a variante de IDIOMA errada para estas telas.**
  `port/assets/MENU/01_title/hd/…18CC5627` é a arte **japonesa** ("BIOHAZARD 3 LAST ESCAPE") e
  `MENU/07_warning/hd/…DC361616` está em **russo**. As variantes em PORTUGUÊS são
  `hires/bgd/ED2C2D33` (título) e `hires/bgd/4784F00D` (aviso), achadas pelo critério de mtime
  de `tools/memo_pt.py` (pack russo = jan/2025, pacote PT-BR = jun/2025). O mesmo hash
  `DC361616` estava servindo DOIS blocos SD (`WARNU` e `WARNJ`) — sintoma de casamento por
  cenário, não por conteúdo do texto.
* **§3 — o atlas de rótulos do título existe em HD e em PT-BR:** `hires/misc/3776D4A3.webp`,
  1024×1024 = 4× a página de VRAM do TIM[2] de `TITLEU.DAT`. As linhas `v` coincidem com as
  desta nota, e `mod_BH3_Portuguese/xml/title_mapping.xml` **confirma de forma independente**
  tanto os `v` do atlas quanto os `x,y` de tela que o §3.4 mediu (`heavy mode` em `x=80 y=193`,
  `light mode` em `x=180 y=193`). Rótulos disponíveis: `CARREG. JOGO`, `MODO FACIL`,
  `MODO DIFICIL`, `COMEÇAR JOGO`, `SAIR`, `EXTRAS`, `OS MERCENARIOS`, `EPILOGOS`,
  `ESCOLHA A ROUPA`. **`PRESS ANY BUTTON` não tem contrapartida HD** (a versão de PC não usa
  essa tela) e o bloco de copyright de 2 linhas (`v=160`) está **vazio** no atlas PT.
* **§3.3 — o pulso do §3.1 foi REPRODUZIDO**, não só citado: `tools/boot_assets.py` lê os 256
  bytes assinados de `0x80098828` do EXE e emite os 64 valores do ciclo — amplitude
  `[−127, 127]`, resultado **86…170**, período **64 ticks**, exatamente como esta nota afirma.
* **§4 — a legenda dos FMV em PT-BR.** As **oito diretivas** do motor Classic REbirth estão
  provadas como literais no `ddraw.dll` da instalação (`clear %d` em `+0x2fe180`, `timed %d` em
  `+0x2fe18c`, …); a semântica "segura N quadros e limpa" é leitura declarada, sustentada pela
  soma fechar dentro da duração medida do mp4 (prólogo: 1414 quadros = 47,18 s em 90,62 s).
