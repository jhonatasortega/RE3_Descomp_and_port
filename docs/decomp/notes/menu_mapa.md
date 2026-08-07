# A TELA DE MAPA do RE3 (PS1 NTSC-U, `SLUS_009.23`) — sistema completo

**Alvo:** RE3 PS1 NTSC-U, `extracted/ntsc-u/SLUS_009.23`, base `0x80010000`, tsize `0xd3800`.
**Dados:** `extracted/ntsc-u/CD_DATA/ETC/MAP_U.MAP` (634 880 B) + `ETC/STMOJIU.TIM`.
**Ferramenta desta nota:** [`tools/map_screen.py`](../../../tools/map_screen.py)
(`python tools/map_screen.py`, `--json`, `--png`).
**Dados exportados:** `port/data/re3_map_screen.json` (tudo: paginas, secoes, registros de
primitiva, ancoras, tabelas do EXE).

> **A tela de mapa NAO esta em nenhum overlay `BIN/*.BIN`.** Ela e codigo do EXE principal,
> na faixa `0x8006e000..0x80074000`. `tools/exe_parse.Exe` desmonta direto, sem `overlay_parse`.

> **Espaco de coordenadas:** TODA coordenada de tela nesta nota esta em **320x240** (o
> framebuffer do RE3 PS1). Coordenadas de "pixel de mapa" sao um plano proprio, maior que a
> textura, com origem no canto superior-esquerdo e Y para baixo.

---

## 0. Resposta curta as 6 perguntas

1. **O desenho e IMAGEM** — um atlas 4bpp por area (`sec[2]` de cada pagina do `MAP_U.MAP`),
   **mas a tela nao e um PNG pronto**: e montada por **quads texturados**, um por comodo,
   com UV+posicao vindos de uma lista de registros de 12 bytes no proprio arquivo (§4).
   Uma unica pagina do PS1 nao e a tela; ela e o *atlas de recortes*.
2. **Salas visitadas** = bitmap `0x800d20dc`, 2 palavras de 32 bits por pagina, **1 bit por
   grupo** (§6). Escrito por `0x80071510(stage, room)` ao entrar na sala.
3. **Marcador do jogador**: sprite 8x8 embutido na propria pagina em `(u=dir*8, v=240..247)`,
   8 direcoes. Transformacao **mundo -> pixel de mapa** = ancora por grupo + **divisao por 450**
   (provada exaustivamente). Formula fechada em §5.
4. **9 paginas**, troca por seta/botao; rotulo vem de uma **tira TIM 256x40** dentro da propria
   pagina (`sec[3]`), nao do texto do EXE (§3.3, §7).
5. **Nao ha marcacao de item**. Ha 366 marcas 8x7 de **porta/passagem** (6 icones distintos),
   sempre `clut_row=4` (§4.2). Provado por varredura dos 793 registros.
6. Coordenadas de tela de tudo em §7, com o endereco de cada `sh`/`sb` no EXE.

---

## 1. De onde vem o arquivo — carregador `0x800713dc`

```
map_load_page(a0 = ctx, a1 = page)      // 0x800713dc
```

Ele NAO carrega o arquivo inteiro (634 KB nao cabem). Monta um pedido de CD a mao em
`0x800b9e10` e le **uma pagina**:

| campo | valor | prova |
|---|---|---|
| `req+0x28` (u16) = file index | `0x3a` | `sh` em `0x80071410` (`li v0,0x3a` em `0x8007140c`) |
| `req+0x14` (u32) = bytes a ler | `SIZES[page]` | `0x8007141c-0x8007142c`, tabela `0x800a03ac` |
| `req+0x20` (u32) = LBA | `lba(0x3a) + (sum(SIZES[0:page]) >> 11)` | `0x80071430-0x80071490`; le `0x800946a4+0x1d4/0x1d6` (= entrada `0x3a`, pois `0x1d0 = 0x3a*8`) |
| `req+0x2a` (u8) = flags | `FLAGS[page]`, tabela `0x800a03a0` | `0x80071488-0x800714a4` |
| chamada | `cd_read_file(a0=0x3a, a1=ctx->0xcc, a2=2, a3="MAP.MAP")` | `jal 0x80012818` em `0x800714ac` |

`a3` = `0x8001107c` = a string morta **`"MAP.MAP"`** — prova direta de qual asset e.
`ETC/MAP_U.MAP` = **file index `0x3a`** (`ETC/MAP_J.MAP` = `0x39`), confirmado batendo
`size` da tabela global `0x800946a4` (634 880) com o tamanho real do arquivo.

### 1.1 Tabelas de pagina no EXE

**`0x800a03ac`, `u32[9]` — tamanho de cada pagina (soma = 634 880 = tamanho do arquivo, exato):**

| pagina | area | tamanho | offset no arquivo | `FLAGS` (`0x800a03a0`) |
|---|---|---|---|---|
| 0 | UPTOWN         | `0x12000` | `0x000000` | `0x58` |
| 1 | DOWNTOWN       | `0x12800` | `0x012000` | `0x26` |
| 2 | CLOCK TOWER    | `0x0a000` | `0x024800` | `0x5a` |
| 3 | PARK           | `0x12000` | `0x02e800` | `0xeb` |
| 4 | DEAD FACTORY   | `0x12000` | `0x040800` | `0xd0` |
| 5 | POLICE STATION | `0x12000` | `0x052800` | `0x6c` |
| 6 | HOSPITAL       | `0x12000` | `0x064800` | `0x77` |
| 7 | UPTOWN (2)     | `0x12000` | `0x076800` | `0x72` |
| 8 | DOWNTOWN (2)   | `0x12800` | `0x088800` | `0xd6` |

`0x800a03d0` em diante **nao** e continuacao dessa tabela (e a tabela de setas, §7.4) — pare em
9 entradas. `FLAGS[]` e o byte copiado para `req+0x2a`; **o significado dele NAO esta provado**
(`menu_overlays.md` §2 tambem nao decodificou o byte de flags da tabela de arquivos).

### 1.2 Qual pagina e carregada

```
if (flag_get(0x800cc858, 0x18))  page = (ctx->0xab + 7) & 0xff;   // 0x8006ee2c..0x8006ee4c
else                             page =  ctx->0xab;
```
Ou seja: as paginas **7 e 8 sao as variantes "segunda passagem" de UPTOWN e DOWNTOWN**, escolhidas
por um bit de progresso. **`ctx->0xab` continua sendo 0/1** — toda a logica de revelacao usa a
area 0/1, so a *imagem* muda. (Bit 0x18 do banco `0x800cc858` — o que ele representa no roteiro
**NAO MEDIDO**.)

### 1.3 Fixups apos a leitura (`0x800714b4..0x800714f8`)

```
buf = ctx->0xcc;
ctx->0xb4 = buf + hdr.sec[1].off;                     // ponteiro para as ancoras
vram_cursor(0x800ccbbc) = 0x0a17;  tim_upload(buf + hdr.sec[2].off);   // 0x800784e0
vram_cursor(0x800ccbbc) = 0x1a18;  tim_upload(buf + hdr.sec[3].off);   // 0x8006ebec
```

`0x800ccbbc` (= gamestruct `0x800ca738` + `0x2484`) e um cursor de VRAM de 2 bytes:
`+0x2484 = texpage` (X em unidades de 64 px de 16 bits, Y=256 se `>= 0x10`), `+0x2485 = linha de
CLUT` (a CLUT vai para `y = 0x1e0 + linha`, `x = 304`). Provado em `0x80078500..0x800785c4`.

Resultado (VRAM 1024x512, 16 bpp):

| conteudo | texpage | VRAM | CLUTs |
|---|---|---|---|
| pagina do mapa (512x256 @4bpp = 128x256 palavras) | `0x17` e `0x18` | x 448..575, y 256..511 | 16, em `(304, 490..505)` |
| tira de rotulo (256x40 @4bpp = 64x40) | `0x18` | x 512..575, **y 472..511** | 1, em `(304, 506)` |

**A tira de rotulo sobrescreve o quadrante inferior-direito da pagina** (pixels de imagem
`x 256..511, y 216..255`). O `img_rect` da tira no arquivo e `(0, 216, 64, 40)` — o `y=216` do
proprio TIM e o que produz `256+216 = 472`. Confirmado nas 9 paginas.

---

## 2. O contexto da tela — `0x800e01c0`

Provado porque `0x800716a4`, `0x80071878`, `0x8007275c` e `0x80072d38` **hardcodam**
`lui v0,0x800e; addiu v0,v0,0x1c0` e leem os mesmos campos que o `a0` do init/desenho.

| offset | tipo | papel | prova |
|---|---|---|---|
| `+0x10` | u8 | contador de estado | `0x8006edd4` |
| `+0x11..0x13` | u8 | proximo estado / submodo | `0x8006edc4`, `0x8006f80c` |
| `+0x22` | u16 | contador de pulso do marcador | zerado `0x8006f698`; usado `0x80070290` |
| `+0x24` | s16 | fase de piscar das setas | `0x800709cc` |
| `+0x7c/0x80` | s32 | **scroll atual X / Y** (o que o desenho usa) | `0x8006f0bc`, `0x8006f0f0` |
| `+0x84/0x88` | s32 | scroll alvo X / Y (interpolado) | `0x8006f970`, `0x8006fb68` |
| `+0x94/0x98` | s32 | **offset base da pagina** (= `sub[1].scroll_x/y`) | `0x8006ee90`, `0x8006eea4` |
| `+0x9c/0xa0` | s32 | limite = `0x94+320` / `0x98+224` | `0x8006f6a4..0x8006f6b0` |
| `+0xa4` | s32 | **zoom em porcento** (100 ou 50) | `0x8006eecc` (`0x64`), `0x8006ef34` (`0x32`) |
| `+0xa8` | u8 | modo "sem andares" | `0x8006ef30` |
| `+0xa9` | u8 | desenhar setas? | `0x8006ee80`, `0x8007085c` |
| `+0xaa` | u8 | area **exibida** | `0x8006ed70` |
| `+0xab` | u8 | area **corrente** (do jogador) | `0x8006ed54` |
| `+0xac` | u8 | **grupo** corrente (do jogador) | `0x8006ed64` |
| `+0xad` | u8 | `sub[1].tem_andares` | `0x8006ee78` |
| `+0xae` | s8 | andar exibido | `0x8006ef18`, `0x8006f848` |
| `+0xaf` | s8 | andar do jogador | `0x8006ef74` |
| `+0xb0` | u8 | `sub[1].n_andares` | `0x8006ee84` |
| `+0xb4` | u32 | ponteiro para `sec[1]` da pagina carregada | `0x800714c8` |
| `+0xb8` | u16 | sub-tela (1 -> area 0; 2 -> area 4) | `0x8006db8c..0x8006dbb4` |
| `+0xba` | u8 | pedir recarga da pagina | `0x8006edb0`, `0x8006ee14` |
| `+0xcc` | u32 | buffer da pagina (= `ctx->8`) | `0x80071408` |
| `+0x404`, `+0x424` | — | vetores de 4 e 2 entradas de 8 B, zerados no init | `0x8006f638`, `0x8006f664` |

Globais externos usados:

| endereco | papel | prova |
|---|---|---|
| `0x800d1f76` (s16) | **stage atual** | `0x8006ed4c`; confirma `door_handler.md` |
| `0x800d1f78` (s16) | **sala atual** | `0x8006ed58`; confirma `door_handler.md` |
| `0x800cabf8` (s32) | **X do jogador** (gamestruct `+0x24c0`) | escrito em `0x8002498c` a partir de `*(0x800ca738+0x2154)`; lido `0x8006f000` |
| `0x800cabfc` (s32) | Y do jogador (`+0x24c4`) | `0x800249a4` |
| `0x800cac00` (s32) | **Z do jogador** (`+0x24c8`) | `0x800249c0`; lido `0x8006f004` |
| `0x800cac32` (u16) | **angulo Y do jogador** (4096 = volta) | `0x800249cc`; lido `0x8006f128` |
| `0x800cc848` (u8) | indice do framebuffer (escolhe o par de primitivas) | `0x800702c0`, `0x800707b4` |
| `0x800cc840` (u32) | botoes **mantidos** | `0x8006f7a0` |
| `0x800cc834` / `0x800cc838` | botoes de **borda** | `0x8006f7a4` / `0x8006f87c` |
| `0x800e0278` (u16) | modo/cenario (1 ou 2) — **qual e qual NAO MEDIDO** | `0x8006f718`, `0x80071994` |

---

## 3. Formato do `MAP_x.MAP`

### 3.1 Pagina = tabela de 4 secoes

```
+0x00  u32 n            // sempre 4 nas 9 paginas
+0x04  {u32 off; u32 size} sec[n]     // off relativo ao inicio da PAGINA
```
`sec[k].off + sec[k].size == sec[k+1].off` nas 9 paginas (contiguo), e `sec[0].off == 0x24`
(= tamanho do cabecalho). Reproduzir: `python tools/map_screen.py` imprime `fecha=True`.

O carregador usa `hdr[3]` (= `sec[1].off`, offset `+0x0c`), `hdr[5]` (= `sec[2].off`, `+0x14`) e
`hdr[7]` (= `sec[3].off`, `+0x1c`) — ver §1.3.

### 3.2 `sec[0]` — geometria (grupos e registros de primitiva)

```
+0x00  u32 n_grupos
+0x04  {u32 off; u16 n1; u16 n2} grupo[n_grupos]     // off relativo a sec[0]
...    em sec[0]+off: (n1 + n2) registros de 12 bytes, lista A primeiro
```
Prova de layout: `0x800702a0-0x800702c4` (`sp+0x14 = *(u32*)sec0` = n_grupos;
`sp+0x10 = sec0+4` avanca 8 por grupo; `sp+0x30 = sec0+0xa` -> `u16@-2` = n1, `u16@0` = n2)
e o ponteiro de registro `s5` avanca `0xc` por iteracao (`0x800704d8`, `0x800705d0`).
**Verificacao aritmetica: `4 + 8*n_grupos + 12*sum(n1+n2) == sec[0].size` nas 9 paginas.**

### 3.3 `sec[1]` — ancoras / scroll / ligacoes

```
+0x00  u32 sub[8]        // offsets relativos a sec[1]; nao usados = 0
sub[0]: {s16 px_x, s16 px_y, s16 w_x, s16 w_z} x N, terminador ff ff ff ff ff ff ff ff
        ANCORA por grupo (§5). Indexada por ctx->0xac (stride 8: 0x8006f010).
sub[1]: {s16 scroll_x, s16 scroll_y, u8 tem_andares, u8 n_andares, u32 0}
        Lido em 0x8006ee64..0x8006eea4 (offset +4 -> ctx->0xad, +5 -> ctx->0xb0,
        s16@0 -> ctx->0x94, s16@2 -> ctx->0x98).
sub[2]: {u8 a, u8 b, u16 c} x N, terminador ff ff ff 00. Registros em PARES que
        compartilham `c`. NAO ACHEI o leitor -> papel NAO PROVADO (§10).
sub[3]: {u8 grupo, u8 idx_reg, u8 bit, u8 sel} x N, term. 0xff  -> condicao da LISTA A
sub[4]: idem                                                     -> condicao da LISTA B
```
`sub[3]` e lido por `0x800718e4` (`lw a3, 0xc(sec1)`), `sub[4]` pelo analogo em `0x80072d38`.

### 3.4 `sec[2]` / `sec[3]` — os TIMs

| | `sec[2]` (atlas do desenho) | `sec[3]` (tira de rotulo) |
|---|---|---|
| bpp | 4 | 4 |
| tamanho | 512x256 (Clock Tower: 256x256) | 256x40 |
| `img_rect` | `(0,0,128,256)` / `(0,0,64,256)` | `(0,216,64,40)` |
| CLUTs | **16**, `clut_rect = (304,0,16,16)` | 1, `(304,0,16,1)` |
| bytes | `0x10220` (`0x8220` na Clock Tower) | `0x1440` |

**`MAP_J.MAP` vs `MAP_U.MAP`: as 4 secoes sao IDENTICAS em 8 das 9 paginas.** So difere
`sec[3]` da pagina 4 (DEAD FACTORY). Isso significa que a tira de rotulo **nao** e uma
traducao por idioma — os nomes de area na tira estao em alfabeto latino nas duas versoes.

### 3.5 Semantica das 16 CLUTs (medida em `MAP_U.MAP` pagina 5)

Os dados de pixel usam so 2 bits uteis por texel; **as CLUTs 0..7 leem `idx & 3` e as CLUTs
8..15 leem `idx >> 2`** — ou seja o atlas guarda DUAS camadas de 2 bits no mesmo nibble, e o
campo `misc` bit0 do registro escolhe qual (§4.1). Cores (indice 0 = transparente):

| linha | cor 1 | cor 2 | cor 3 | uso |
|---|---|---|---|---|
| 0 | `#004210` | `#009c4a` | `#5a5a5a` | comodo normal (verde) |
| 1 | `#002100` | `#004210` | `#424242` | comodo escurecido |
| 2 | `#310000` | `#8c0000` | `#5a5a5a` | **comodo onde o jogador esta** (vermelho) |
| 3 | `#18315a` | `#294a84` | `#426bad` | marcador do jogador (azul) |
| 4 | `#8c8c8c` | `#b51829` | `#c6ad00` | porta/passagem (dourado) |
| 5 | `#004210` | — | `#5a5a5a` | (cor 2 transparente) |
| 6 | `#8c8c8c` | `#b51829` | `#ff2929` | porta realcada (vermelho vivo) |
| 7 | `#313131` | `#390094` | `#949494` | conjunto fixo (`clut_row==7` desliga realce) |
| 8..15 | iguais a 0..7 | | | mesma cor, plano de bits alto |

---

## 4. O emissor de quads — `0x8007116c`

```
map_emit_quad(a0 = ctx, a1 = *POLY_FT4, a2 = *rec12, a3 = modo)
```

### 4.1 Registro de 12 bytes

| off | tipo | campo |
|---|---|---|
| `+0x00` | u8 | `u0` |
| `+0x01` | u8 | `v0` |
| `+0x02` | u8 | `u1` (inclusivo; o emissor usa `u1+1`) |
| `+0x03` | u8 | `v1` (inclusivo) |
| `+0x04` | s16 | `x` em pixel de mapa |
| `+0x06` | s16 | `y` em pixel de mapa |
| `+0x08` | u8 | `clut_row` (0..7); **se == 7, `modo` e forcado a 0** (`0x800711ac`) |
| `+0x09` | u8 | `misc`: bit0 -> `+8` na linha de CLUT; `>>1` -> `+N` na texpage X |
| `+0x0a` | u16 | **sempre 0 nos 793 registros das 9 paginas** — nao lido pelo emissor |

Codigo (`0x800711a4..0x800713a8`):

```
w  = rec.u1 - rec.u0 + 1
h  = rec.v1 - rec.v0 + 1
mx = rec.x + ctx->0x94
my = rec.y + ctx->0x98
sx = ctx->0x7c - ctx->0x94 + 160      // 0xa0
sy = ctx->0x80 - ctx->0x98 + 120      // 0x78
Z  = ctx->0xa4                        // 100 ou 50
x0 = (mx*Z)/100 + sx ;  x1 = ((mx+w)*Z)/100 + sx      // divisao TRUNCADA (magico 0x51eb851f>>5)
y0 = (my*Z)/100 + sy ;  y1 = ((my+h)*Z)/100 + sy
POLY_FT4: (x0,y0) (x1,y0) (x0,y1) (x1,y1)
          uv: (u0,v0) (u1+1,v0) (u0,v1+1) (u1+1,v1+1)
          rgb = 0x80,0x80,0x80
          clut  @+0x0e = (((modo + rec.clut_row + (rec.misc&1)*8 + 0x1ea) << 6) | 0x13) & 0xffff
          tpage @+0x16 = 0x10 | (((rec.misc >> 1) + 7) & 0xf)
```
`0x1ea` = 490 = a linha de CLUT base na VRAM (§1.3, coincide exatamente). `0x13` -> CLUT em
`x = 0x13*16 = 304` (§1.3). `tpage 0x10|7 = 0x17` e `0x10|8 = 0x18` -> as duas metades da
pagina de 512 px (cada texpage cobre 256 texels a 4bpp).

### 4.2 O que ha nas duas listas (medido nos 793 registros das 9 paginas)

| | LISTA A (`n1`) — 427 registros | LISTA B (`n2`) — 366 registros |
|---|---|---|
| `v0` | sempre `< 240` (recortes do atlas) | sempre `248` |
| tamanho | variavel, ate 254x162 | **sempre 8x7** (4 excecoes 8x5 / 6x7) |
| `clut_row` | 0 (302x), 1 (103x), 7 (19x), 4 (2x), 2 (1x) | **4 em 100%** |
| `misc` | 0,1,2,3 | **0 em 100%** |
| `modo` recebido | `0x8007275c(...)` -> 0/2 | `(0x800738cc(...) != 0) << 1` -> 0 ou 2 |
| papel | corpo do comodo | **porta / passagem / escada** |

**Os 6 icones da lista B** vivem na propria pagina, em `v = 248..254`:
`u=0` barra vertical, `u=8` barra horizontal, `u=16` diagonal `\`, `u=24` diagonal `/`,
`u=32` barra vertical alta, `u=40` barra horizontal larga. Renderizados amarelos pela CLUT 4.
**Nao existe marca de item nem de "porta trancada" separada** — o unico realce e o `modo=2`
(CLUT 6, vermelho vivo) devolvido por `0x800738cc`.

### 4.3 Pool de primitivas

O desenho e **duplicado por framebuffer**: as primitivas vem em pares com passo = tamanho da
primitiva, e o par ativo e escolhido por `0x800cc848` (`0x800702c0`, `0x800707b4`).

| conteudo | inicio (buf 0 / buf 1) | passo do par | qtd |
|---|---|---|---|
| quads de comodo/porta (POLY_FT4) | `0x801ac000` / `0x801ac028` | `0x50` | **200** slots (`(0x801afe80-0x801ac000)/0x50`) |
| marcador do jogador (POLY_FT4) | `0x801afe80` / `0x801afea8` | `0x50` | 1 |
| 4 setas (POLY_FT4) | `0x801afed0` + `i*0x50` | `0x50` | 4 |
| linha horizontal (LINE_F2) | `0x801b0010` / `0x801b0020` | `0x10` | 1 |
| linha vertical (LINE_F2) | `0x801b0030` / `0x801b0040` | `0x10` | 1 |
| 38 linhas cinza `rgb(32,32,32)` (LINE_F2) | `0x801b0050` + `i*0x20` | `0x10` | 38 (uso **NAO MEDIDO**) |
| 7 SPRT de rotulo/bussola/regua | `0x801b0510` .. `0x801b05ec` | `0x14` | §7.3 |
| 4 SPRT de rotulo de andar | `0x801b0600` + `i*0x28` | `0x14` | 4 |
| TILE `rgb(64,64,64)` | `0x801b06a0` / `0x801b06b0` | `0x10` | 1 (uso **NAO MEDIDO**) |

Cada bloco termina exatamente onde o proximo comeca (`0x801b0050 + 76*0x10 = 0x801b0510`;
`0x801b0600 + 8*0x14 = 0x801b06a0`) — o que valida a leitura inteira do init.
O maximo de registros por pagina e 184 (DOWNTOWN), abaixo dos 200 slots.

---

## 5. O MARCADOR DO JOGADOR — o coracao da tela

### 5.1 O sprite

8 direcoes, **embutidas na propria pagina do mapa**, em `u = 0..63`, `v = 240..247`
(8 tiles de 8x8). O init escreve `v0=v1=0xf0` e `v2=v3=0xf8` (`0x8006f130..0x8006f13c`) e:

```
u0 = ((*(u16*)0x800cac32 + 0x100) >> 6) & 0x38 ;  u1 = u0 + 8      // 0x8006f128..0x8006f164
```
`0x800cac32` = angulo Y do jogador (4096 = volta completa). `+0x100` = meio setor (4096/8/2 =
256), `>>6 & 0x38` = setor*8. **Verificado visualmente**: os 8 glifos existem nessa regiao da
pagina (`tools/map_screen.py --png`, recortar `(0,240)-(64,248)`).
CLUT = `0x7b53` -> linha 493 = `490+3` = **CLUT 3 (azul)** (`0x8006f144`).
O RGB e pulsante: `0x40 + 2*ctx->0x22` nos tres canais (`0x80070290`, `0x80070800`).

### 5.2 Mundo -> pixel de mapa (a transformacao por grupo)

`anc = sec[1].sub[0][ctx->0xac]` (stride 8, `0x8006f008..0x8006f018` e `0x80070658..0x80070668`):

```
mx = anc.px_x + (Xjogador - anc.w_x) / 450
my = anc.px_y - (Zjogador - anc.w_z) / 450
```

**O divisor 450 esta PROVADO**: o codigo faz `mult n, 0x91a2b3c5` / `mfhi` / `+n` / `sra 8` /
`- (n>>31)` (em `0x8006f098..0x8006f0b4` e `0x800706e8..0x80070740`). Rodei
`f(n) == trunc(n/450)` para **todo n de -2 000 000 a +2 000 000: zero divergencias**.
(A magica `0x51eb851f >> 5` usada depois e `/100`, verificada do mesmo jeito.)

Atencao aos **sinais**: em X soma, em Y **subtrai** (`subu v0, v0, a0` em `0x8006f0ec` e
`subu t3, v1, v0` em `0x80070748`). O mundo do PS1 tem Y para baixo, mas aqui o par usado e
(X, Z) e o mapa tem Z crescendo para o topo da tela.

### 5.3 Pixel de mapa -> tela

`0x800706dc..0x800707d8`. Com `O94 = ctx->0x94`, `O98 = ctx->0x98`, `S = ctx->0x7c/0x80`,
`Z = ctx->0xa4`:

```
X = ((mx + O94) * Z)/100 - O94 + ctx->0x7c
Y = ((my + O98) * Z)/100 - O98 + ctx->0x80
quad do marcador = (X+0x9c, Y+0x74) .. (X+0xa4, Y+0x7c)      // 156/116 .. 164/124
```
Isso e **algebricamente identico** a formula dos quads de comodo (§4.1): o centro do marcador
cai em `(X+160, Y+120)`. Verifiquei fechando o circulo: se o jogador esta exatamente na ancora
do grupo, `ctx->0x7c = -anc.px_x`, `ctx->0x80 = -anc.px_y` (formula de `0x8006f0bc/0x8006f0f0`),
logo `X = Y = 0` e o quad fica `(156,116)-(164,124)` = **8x8 centrado em (160,120)**, o centro
exato da tela 320x240. Em modo "seguir", o jogador esta sempre no centro.

### 5.4 Quando o marcador aparece

```
mostra = (ctx->0xab == ctx->0xaa);                       // 0x80070608..0x80070624
if (ctx->0xad && ctx->0xaf != ctx->0xae) mostra = 0;     // andar exibido != andar do jogador
```

### 5.5 Correcoes de posicao codificadas no EXE

Duas salas tem gambiarra de coordenada antes da conversao (aparecem DUAS vezes, em
`0x8006f01c..0x8006f088` e `0x8007066c..0x800706d8`, identicas):

```
if (stage==1 && sala==0x0f && Xjog >= -0x2276)  Xjog += 0x251d;
if (stage==3 && sala==0x15 && Xjog >=  0x320 )  Xjog -= 0x2328;
```

### 5.6 Ancoras (exemplo completo: pagina 5, POLICE STATION, 11 grupos)

| grupo | `px_x` | `px_y` | `w_x` | `w_z` |
|---|---|---|---|---|
| 0 | 309 | 282 | 11496 | -16944 |
| 1 | 294 | 250 | -23036 | -19679 |
| 2 | 285 | 212 | -6670 | -10000 |
| 3 | 243 | 206 | -25118 | -26330 |
| 4 | 266 | 205 | -25456 | -24424 |
| 5 | 211 | 203 | -25638 | -24917 |
| 6 | 230 | 178 | -21908 | -8806 |
| 7 | 286 | 184 | -15282 | -15140 |
| 8 | 287 | 168 | 7041 | 1086 |
| 9 | 234 | 253 | -14547 | -25651 |
| 10 | 215 | 227 | -25895 | -16905 |

As 9 paginas inteiras estao em `port/data/re3_map_screen.json` (`paginas[p].ancoras`).
**A ancora e por GRUPO, nao global** — nao existe "escala por area", cada comodo tem seu
proprio deslocamento de mundo. Numero de ancoras por pagina:
`41, 28, 13, 23, 18, 11, 12, 41, 28`.

> **Cuidado (pagina 0/1/7/8):** `n_grupos` (65/78) e MAIOR que o numero de ancoras (41/28).
> Grupos acima do ultimo com ancora existem no desenho mas nunca sao a posicao do jogador.
> Alem disso o bitmap de visitados tem so 64 bits por pagina (§6) — grupos >= 64 **aliasam**
> na palavra da pagina seguinte. Nao "consertei" isso; e o que o binario faz.

---

## 6. Salas visitadas — o bitmap `0x800d20dc`

### 6.1 Quem escreve — `0x80071510(a0 = stage, a1 = sala)`

Chamado de `0x8004986c`, no fim da rotina de carga de sala.

```
// pre-revelacoes codificadas (bits soltos, antes de qualquer conversao):
if (stage==0 && sala==0x10) *(u32*)0x800d20dc |= 0x80000000 >> (0x10 & 0x1f);  // pag0 grp16
if (stage==1 && sala==0x00) *(u32*)0x800d20e4 |= 0x80000000 >> 0;              // pag1 grp0
if (stage==1 && sala==0x01) *(u32*)0x800d20e0 |= 0x00010000;                   // pag0 grp47
if (stage==3 && sala==0x15) *(u32*)0x800d20f4 |= 0x80000000 >> (0x15 & 0x1f);  // pag3 grp21

map_room_to_page_group(&stage, &sala);            // 0x80073ccc, vira (pagina, grupo)

palavra = 0x800d20dc + 4*(pagina*2 + (grupo >> 5));
*palavra |= 0x80000000 >> (grupo & 0x1f);         // MSB primeiro dentro da palavra
flag_set(0x800d2128, pagina);                     // 0x800788dc
```

* **`0x800d20dc`** = `u32[18]`: **2 palavras (64 bits) por pagina**, page-major.
  `bit(grupo) = 0x80000000 >> (grupo & 0x1f)` — **MSB primeiro**, nao LSB.
* **`0x800d2128`** = banco de flags "pagina/area ja visitada" (bit = numero da pagina).
* **`0x800d2124`** = banco de flags "**mapa desta area obtido**" (bit = numero da area);
  lido em `0x80070350` e `0x800718ec`. Nao achei quem o escreve (§10).

### 6.2 Quem le — `0x80071668(a0 = area, a1 = grupo)`

Exatamente o mesmo endereco/mascara, devolvendo `palavra & bit`. E o unico leitor do bitmap.

### 6.3 Portao no laco de desenho (`0x80070348..0x800703b8`)

```
for (grupo = 0; grupo < n_grupos; grupo++) {
    if (flag_get(0x800d2124, ctx->0xab)) {              // TEM o mapa da area
        if (ctx->0xab == 4 && 0x0b <= grupo && grupo <= 0x0f)
            if (!visitado(area, grupo)) continue;       // DEAD FACTORY 0x0b..0x0f exige visita
        // resto: revelado sem visitar
    } else {                                            // NAO tem o mapa
        if (grupo >= 0x30) continue;                    // grupos >= 48 nunca aparecem
        if (!visitado(area, grupo)) continue;
    }
    if (!gate_grupo(area, grupo)) continue;             // 0x800716a4
    ... desenha lista A e lista B ...
}
```

Uma regra concreta de `gate_grupo` (`0x800716a4`) que PROVEI (`0x800716f4..0x8007172c`):

```
if (area == 0 && (u8)(grupo - 0x11) < 0x0a) return 0;   // pagina 0, grupos 0x11..0x1a: nunca
```
Coerente: as salas `R111..R11A` (stage 0, salas `0x11..0x1a`) sao remapeadas para a pagina 5,
logo esses grupos da pagina 0 sao vestigiais.

### 6.4 `map_room_to_page_group` — `0x80073ccc(u8 *stage, u8 *sala)`

Converte **no lugar** `(stage, sala)` em `(pagina, grupo)`:

```
// 1) casos especiais dependentes de mundo/flag (retornam na hora)
if (stage==1 && sala==0x0f && *(s32*)0x800cabf8 >= -0x2276)      { *sala = 0x10; return; }
if (stage==3 && sala==0x15 && *(s32*)0x800cabf8 >=  0x320 )      { *sala = 0x11; return; }
if (stage==4 && sala==0x02 && flag_get(0x800d1fc0, 0x1f))        { *sala = 0x11; return; }
if (stage==2 && sala==0x17 && *(s32*)0x800cac00 >= -0x2c24
                           && !flag_get(0x800d1fa0, 0xc8))       { *sala = 2;    return; }
// 2) SEGUNDA PASSAGEM: stages 5..8 usam o mapa dos stages 0..3
if (stage >= 5) stage -= 5;
// 3) busca linear na tabela 0x800a0430 {u8 stage, u8 sala, u8 pagina, u8 grupo}, term 0xff
//    NAO da break no acerto: continua comparando com os valores JA sobrescritos.
for (r = 0x800a0430; r[0] != 0xff; r += 4)
    if (r[0] == *stage && r[1] == *sala) { *stage = r[2]; *sala = r[3]; }
```
**Default (nao esta na tabela): `pagina = stage`, `grupo = numero da sala`.**
Conferi que nenhum dos 49 registros produz encadeamento acidental — mas o `for` sem `break`
e um comportamento real do binario, replique-o.

**Tabela `0x800a0430` completa (49 registros)** — tambem em
`port/data/re3_map_screen.json/exe/remap_sala`:

| stage,sala | -> pag,grp | | stage,sala | -> pag,grp | | stage,sala | -> pag,grp |
|---|---|---|---|---|---|---|---|
| 0,`0x10` | 5,0 | | 0,`0x1f` | 0,4 | | 2,`0x11` | 2,5 |
| 0,`0x11` | 5,1 | | 0,`0x20` | 0,5 | | 2,`0x12` | 2,6 |
| 0,`0x12` | 5,2 | | 0,`0x21` | 0,6 | | 2,`0x13` | 2,7 |
| 0,`0x13` | 5,3 | | 0,`0x22` | 0,8 | | 2,`0x14` | 2,8 |
| 0,`0x14` | 5,4 | | 0,`0x23` | 0,9 | | 2,`0x15` | 2,9 |
| 0,`0x15` | 5,5 | | 0,`0x24` | 0,10 | | 2,`0x16` | 2,4 |
| 0,`0x16` | 5,6 | | 1,`0x00` | 0,38 | | 2,`0x17` | 2,1 |
| 0,`0x17` | 5,7 | | 1,`0x15` | 1,12 | | 3,`0x17` | 3,0 |
| 0,`0x18` | 5,8 | | 1,`0x17` | 1,14 | | 3,`0x02` | 6,2 |
| 0,`0x19` | 5,9 | | 1,`0x18` | 0,39 | | 3,`0x03` | 6,3 |
| 0,`0x1a` | 5,10 | | 1,`0x19` | 1,16 | | 3,`0x04` | 6,4 |
| 0,`0x25` | 5,0 | | 1,`0x1a` | 0,40 | | 3,`0x05` | 6,5 |
| 0,`0x1d` | 0,2 | | 2,`0x0d` | 2,3 | | 3,`0x06` | 6,6 |
| 0,`0x1e` | 0,3 | | 2,`0x0e` | 2,4 | | 3,`0x07` | 6,7 |
| | | | 2,`0x0f` | 2,1 | | 3,`0x08` | 6,8 |
| | | | 2,`0x10` | 2,0 | | 3,`0x09` | 6,9 |
| | | | | | | 3,`0x0a` | 6,10 |
| | | | | | | 3,`0x0b` | 6,11 |
| | | | | | | 4,`0x10` | 3,22 |

Consequencias importantes: **POLICE STATION (pagina 5) sao as salas `R110..R11A` do stage 0** e
**HOSPITAL (pagina 6) sao as salas `R402..R40B` do stage 3** — nao existem "stage 5/6"
proprios para elas.

### 6.5 Condicao por registro (`sub[3]` / `sub[4]`)

`0x80071878(area, grupo, idx)` para a lista A (analogo `0x80072d38` para a lista B):

```
if (flag_get(0x800d2124, area)) goto excecoes_por_area;    // tem o mapa -> pula a tabela
for (r = sec1 + sub[3]; (s8)r[0] != -1; r += 4)
    if (r[0] == grupo && r[1] == idx) {
        if (r[3] != 0) { if (!flag_get(0x800d1fa0, r[2])) return 0; }
        else           { if (!flag_get(0x800d20cc, r[2])) return 0; }
    }
excecoes_por_area: ...                                     // ver §10
```
Conteudo medido (so 3 paginas usam):

| pag | `sub[3]` (lista A) | `sub[4]` (lista B) |
|---|---|---|
| 0 | `(4,1,27,1) (4,2,27,1) (4,3,27,1)` | `(4,3,27,1) (4,4,27,17)` |
| 1 | `(20,1,94,1) (20,2,95,1) (20,3,96,1) (16,1,64,1) (8,2,159,1)` | `(20,1,94,1) (20,2,94,17) (20,3,95,1) (20,4,95,17) (20,5,96,1) (20,6,96,17) (20,7,96,17) (16,1,64,1) (16,2,64,17) (8,1,159,1) (8,2,159,17)` |
| 4 | `(0,1,234,1)` | `(0,4,234,1) (0,5,234,17) (0,3,234,17)` |
| 2,3,5,6,7,8 | vazio | vazio |

`sel` observado so vale 1 ou 17 (`0x11`); o codigo apenas testa `!= 0`, ou seja **na pratica
sempre o banco `0x800d1fa0`**. Para que serve o bit `0x10` do `sel`: **NAO MEDIDO**.

### 6.6 Cor do comodo (realce)

`0x8007275c(area, grupo, idx)` devolve o `modo` da lista A. Cauda (`0x80072a9c..0x80072ac4`):

```
if (ctx->0xab != ctx->0xaa) return 0;
return (grupo == ctx->0xac) ? 2 : 0;     // o comodo do jogador vira CLUT+2 = VERMELHO
```
`0x80072aec(area, grupo, idx)`, se != 0, faz o quad usar o RGB pulsante `0x40+2*ctx->0x22`
(`0x80070448..0x80070458`). Para a lista B, `0x800738cc` != 0 -> `modo = 2` (CLUT 6) e pulso.

---

## 7. Coordenadas de tela (todas em 320x240)

### 7.1 Zoom e scroll

* `ctx->0xa4` = **100** quando `sub[1].tem_andares != 0` (interiores: Clock Tower, Dead
  Factory, Police Station, Hospital) e **50** quando `== 0` (Uptown, Downtown, Park)
  — `0x8006eecc` / `0x8006ef34`.
* Scroll inicial ao trocar de pagina = `sub[1].scroll_x/scroll_y`
  (`0x8006eea8..0x8006eec0`). Valores medidos:

| pag | area | `scroll_x` | `scroll_y` | `tem_andares` | `n_andares` |
|---|---|---|---|---|---|
| 0 | UPTOWN | -360 | -240 | 0 | 0 |
| 1 | DOWNTOWN | -300 | -190 | 0 | 0 |
| 2 | CLOCK TOWER | -380 | -240 | 1 | 3 |
| 3 | PARK | -380 | -256 | 0 | 0 |
| 4 | DEAD FACTORY | -395 | -240 | 1 | 2 |
| 5 | POLICE STATION | -315 | -226 | 1 | 2 |
| 6 | HOSPITAL | -198 | -307 | 1 | 3 |
| 7 | UPTOWN (2) | -360 | -240 | 0 | 0 |
| 8 | DOWNTOWN (2) | -300 | -190 | 0 | 0 |

* Limites: `ctx->0x9c = ctx->0x94 + 320`, `ctx->0xa0 = ctx->0x98 + 224` (`0x8006f6a4`).

### 7.2 Marcador do jogador

Quad 8x8 em `(X+156, Y+116)..(X+164, Y+124)`; centro `(X+160, Y+120)` (§5.3).
`sh` em `0x800707dc..0x800707fc`.

### 7.3 SPRTs de rotulo/bussola/regua — todos vindos de `sec[3]` (a tira 256x40)

O `u` do SPRT e em texels 4bpp dentro da texpage `0x18`; `v` = `216 + linha_da_tira`.
**Verifiquei visualmente cada recorte** (`tools/map_screen.py --png` + recorte).

| prim | tela (x,y) | tam | uv na texpage | = na tira (x, y) | conteudo confirmado |
|---|---|---|---|---|---|
| `0x801b0510` | (280, 16) | 26x40 | (0, 216) | (0, 0) | **bussola N/S** |
| `0x801b0538` | (180, 208) | 72x15 | (32, 232) | (32, 16) | regua "0 5 10 15" (zoom 100) |
| `0x801b0560` | (252, 214) | 72x9 | (32, 247) | (32, 31) | escala "**[m] 1:610**" |
| `0x801b0588` | (180, 208) | 72x15 | (104, 232) | (104, 16) | regua "0 10 20 30" (zoom 50) |
| `0x801b05b0` | (252, 214) | 72x9 | (104, 247) | (104, 31) | escala "**[m] 1:1220**" |
| `0x801b05d8` | (16, 16) | 144x16 | (32, 216) | (32, 0) | **nome da area** ("POLICE STATION") |
| `0x801b0600` / `0614` | (176, 16) | 38x16 | (176, 216) | (176, 0) | rotulo de andar 0 ("1F") |
| `0x801b0628` / `063c` | (176, 16) | 38x16 | (216, 216) | (216, 0) | rotulo de andar 1 ("2F") |
| `0x801b0650` / `0664` | (176, 16) | 38x16 | (176, 232) | (176, 16) | rotulo de andar 2 (vazio na pag.5) |
| `0x801b0678` / `068c` | (176, 16) | 38x16 | (216, 232) | (216, 16) | rotulo de andar 3 (vazio na pag.5) |

CLUT de todos: `0x7e93` -> `(304, 506)` = a CLUT unica da tira. `rgb = 0x80` (`0x8006f2d0`..).
`1:610` vs `1:1220` = exatamente 2x, o que casa com zoom 100 vs 50.
Endereços dos `sh`/`sb`: bloco em `0x8006f29c..0x8006f5dc`.

> **Os rotulos NAO vem do texto do EXE.** Existem sim 10 strings codificadas em `0x800a0328`
> (indice u16 em `0x800a038c`): `UPTOWN`, `DOWNTOWN`, `CLOCK TOWER`, `PARK`, `DEAD FACTORY`,
> `POLICE STATION`, `HOSPITAL`, `MAP SELECT`, `▷` (glifo `0x02`), `no map` — mas quem as usa
> **NAO ESTA PROVADO** (provavelmente a tela de escolha de mapa / o item de mapa). Decodifiquei
> com o charset de `tools/re3_text.py`.

### 7.4 As 4 setas — `ETC/STMOJIU.TIM`

`0x800a03d0`: **2 estados x 4 setas x 12 bytes** = 96 B (termina exatamente em `0x800a0430`).
Endereco do registro = `0x800a03d0 + seta*12 + estado*48`
(`a3 += 0xc` por seta em `0x80070ae0`; `v1 = a3 + estado*48` em `0x800709dc`).
Layout: `{u16 u0, u16 v0, u16 u1, u16 v1, s16 cx, s16 cy}`.
Quad = `(cx-7, cy-6) .. (cx+6, cy+6)` = **14x13 centrado em (cx,cy)**
(`0x800709f4..0x80070a20`), o que casa com `u1-u0+1 = 14`, `v1-v0+1 = 13`.

| seta | uv | estado 0 (cx,cy) | estado 1 (cx,cy) |
|---|---|---|---|
| 0 (cima) | (0,0)-(13,12) | (161, 32) | (161, 31) |
| 1 (baixo) | (14,0)-(27,12) | (161, 208) | (161, 209) |
| 2 (esquerda) | (28,0)-(41,12) | (32, 121) | (31, 121) |
| 3 (direita) | (42,0)-(55,12) | (288, 121) | (289, 121) |

O estado 1 desloca a seta 1 px **para fora** (animacao). Escolha:
`estado = 1 e rgb = 100` se a seta esta no limite de scroll; senao `estado = ctx->0x24` e
`rgb = 128` (`0x800709b4..0x800709dc`).

**Fonte grafica PROVADA:** texpage `0x1a` + CLUT `0x7893` -> `(304, 482)`.
`ETC/STMOJIU.TIM` (file index `0x60`) e 4bpp 256x72 com **9 CLUTs em `(304, 480..488)`**, e e
carregado exatamente nessa texpage com cursor de CLUT 0 em `0x8006d844`
(`sh 0x001a` -> `0x800ccbbc`) — logo `482` = **CLUT indice 2 do STMOJIU**. Renderizei
`(0,0)-(56,13)` com a CLUT 2: **4 triangulos verdes** (cima, baixo, esquerda, direita).

### 7.5 Primitivas cujo uso eu NAO medi

* `0x801b0010` LINE_F2 `(0,120)-(320,120)` (`0x8006f174..0x8006f1c0`).
* `0x801b0030` LINE_F2 `(160,0)-(160,240)` (`0x8006f1c4..0x8006f210`).
* 38x LINE_F2 `rgb(32,32,32)` a partir de `0x801b0050` (`0x8006f260..0x8006f298`) — so o
  cabecalho e montado no init; XY vem de outro lugar que **nao localizei**.
* TILE `rgb(64,64,64)` em `0x801b06a0` (`0x8006f5f0..0x8006f630`).

---

## 8. Andares e troca de pagina (entrada)

Leitura de botao em `0x8006f780..0x8006f930` (a funcao de estado `0x8006f708`).
`0x800746c0` **NAO** e leitura de pad — e disparo de SFX (`a0` = id: `0x22b`, `5`, `6`).

| condicao | acao |
|---|---|
| `(mantidos & 0x2000) \|\| (borda@0x800cc834 & 1)` | sair da tela (SFX 5) |
| `borda@0x800cc834 & 0x108` | estado 2 (SFX 6) |
| `ctx->0xad && (mantidos & 0x1000)` | `ctx->0xae++`, volta a 0 quando `>= ctx->0xb0` (SFX 6) |
| `ctx->0xad && (borda@0x800cc838 & 0x4000)` | `ctx->0xae--` |
| no modo de rolagem: `0x1000` / `0x4000` | mexe `ctx->0x80` (Y) |
| no modo de rolagem: `0x8000` / `0x2000` | mexe `ctx->0x7c` (X) |

**Qual botao fisico e cada mascara: NAO MEDIDO.** O que esta provado e o pareamento
(`0x1000`/`0x4000` = eixo vertical, `0x8000`/`0x2000` = eixo horizontal) porque o codigo os usa
para mexer Y e X respectivamente. Nao localizei a funcao que normaliza o pad para
`0x800cc834/38/40`.

Numero de andares por pagina = `sub[1].n_andares` (tabela em §7.1): Clock Tower 3,
Dead Factory 2, Police Station 2, Hospital 3, resto 0.

---

## 9. Pseudocodigo do desenho (`0x80070244`)

```c
void map_draw(Ctx *ctx) {              // ctx == 0x800e01c0
    u8  pulso = ctx->u16_22 * 2 + 0x40;
    u8 *buf   = ctx->buf;              // +0xcc
    Sec0 *s0  = buf + hdr(buf).sec[1 /*sec0*/].off;
    POLY_FT4 *p = (*(u8*)0x800cc848) ? 0x801ac028 : 0x801ac000;   // passo 0x50

    for (u32 g = 0; g < s0->n_grupos; g++) {
        bool tem_mapa = flag_get(0x800d2124, ctx->area);
        if (tem_mapa) {
            if (ctx->area == 4 && g - 0x0b < 5 && !visitado(ctx->area, g)) continue;
        } else {
            if (g >= 0x30) continue;
            if (!visitado(ctx->area, g)) continue;                 // 0x80071668
        }
        if (!gate_grupo(ctx->area, g)) continue;                    // 0x800716a4
        Rec12 *r = (u8*)s0 + s0->grupo[g].off;
        for (u16 i = 0; i < s0->grupo[g].n1; i++, r++) {            // LISTA A
            if (!cond_A(ctx->area, g, i)) continue;                 // 0x80071878
            u8 modo = modo_A(ctx->area, g, i);                      // 0x8007275c -> 0 ou 2
            emit_quad(ctx, p, r, modo);                             // 0x8007116c
            if (pulso_A(ctx->area, g, i)) p->r = p->g = p->b = pulso;  // 0x80072aec
            addPrim(); p = (u8*)p + 0x50;
        }
        for (u16 i = 0; i < s0->grupo[g].n2; i++, r++) {            // LISTA B
            if (!cond_B(ctx->area, g, i)) continue;                 // 0x80072d38
            bool hl = modo_B(ctx->area, g, i);                      // 0x800738cc
            emit_quad(ctx, p, r, hl ? 2 : 0);
            if (hl) p->r = p->g = p->b = pulso;
            addPrim(); p = (u8*)p + 0x50;
        }
    }
    // marcador
    if (ctx->area == ctx->area_exibida && (!ctx->tem_andares || ctx->andar == ctx->andar_jog)) {
        s32 X = ctx->px, Z = ctx->pz;                     // 0x800cabf8 / 0x800cac00
        aplica_correcoes(&X, &Z);                          // §5.5
        Anc *a = &sec1->sub0[ctx->grupo];
        s32 mx = a->px_x + (X - a->w_x) / 450;
        s32 my = a->px_y - (Z - a->w_z) / 450;
        s32 sx = ((mx + ctx->o94) * ctx->zoom) / 100 - ctx->o94 + ctx->scroll_x;
        s32 sy = ((my + ctx->o98) * ctx->zoom) / 100 - ctx->o98 + ctx->scroll_y;
        quad_8x8(sx + 156, sy + 116);                      // centro (sx+160, sy+120)
    }
    if (ctx->desenha_setas) for (int i = 0; i < 4; i++) seta(i);
}
```

---

## 10. EM ABERTO (nao provado / nao medido)

1. **`sec[1].sub[2]`** — os pares `{u8 a, u8 b, u16 c}` que compartilham `c`
   (2 a 25 por pagina). **Nao achei o leitor.** Meu chute (nao use) e ligacao entre grupos.
   Onde procurar: qualquer `lw` de `0x8(ctx->0xb4)` na faixa `0x8006e000..0x80074000`.
2. **A logica de excecao por area** dentro de `0x800716a4`, `0x80071878`, `0x80072d38`,
   `0x8007275c`, `0x80072aec`, `0x800738cc` (~78 chamadas de `flag_get`, ~2 KB de codigo cada).
   Provei o *mecanismo* e a cauda de `0x800716a4`/`0x8007275c`, e os bancos usados:
   `0x800cc858` (11x), `0x800d1fa0` (5x), `0x800d20cc` (5x), `0x800d1fc0` (4x), `0x800d2028`,
   `0x800d1fc8`, `0x800d2124`, `0x800d2128`, `0x800d258c`, `0x800d79ec`.
   **A transcricao exaustiva (area, grupo, indice) -> (banco, bit) NAO foi feita.**
3. **Quem escreve `0x800d2124`** (mapa obtido por area). O item de mapa existe (classe `0x08`
   em `exe_items.md`) mas nao liguei o item -> bit.
4. **Nomes de botao** das mascaras `0x1000/0x2000/0x4000/0x8000/0x0001/0x0108` (§8).
5. **`0x800e0278`** (1 ou 2): nao ha nenhum store no `.text` do EXE. Nao sei se e
   Jill/Mercenarios ou outra coisa.
6. **Quem usa as 10 strings de `0x800a0328`** (`MAP SELECT`, `no map`, nomes de area).
7. **As 38 linhas `rgb(32,32,32)`** de `0x801b0050`, a linha horizontal `y=120`, a vertical
   `x=160` e o TILE `0x801b06a0`: cabecalhos montados no init, **XY nao localizado**.
8. **`FLAGS[]` (`0x800a03a0`)** — byte por pagina copiado para `req+0x2a`. Significado
   desconhecido (o mesmo byte da tabela de arquivos tambem esta sem decodificar em
   `menu_overlays.md`).
9. **Byte `+0x0a..0x0b` do registro de 12 bytes**: zero em todos os 793 registros e nao lido
   pelo emissor. Pode ser padding ou um campo morto. Nao classifiquei.
10. **`ctx->0xb8`** (1 -> area 0, 2 -> area 4): nao descobri qual sub-tela usa isso.
11. **Grupos >= 64** nas paginas 0/1/7/8 aliasam no bitmap de visitados (§5.6). Nao investiguei
    se o jogo evita isso por construcao ou se e bug latente.
12. Nao medi **tempo/curva de interpolacao** do scroll (`0x84/0x88` -> `0x7c/0x80`) nem o
    periodo do pulso `ctx->0x22`.

---

## 11. Como remedir tudo

```bash
# estrutura do arquivo + tabelas do EXE (imprime "fecha=True" nas 9 paginas)
PYTHONIOENCODING=utf-8 python tools/map_screen.py
PYTHONIOENCODING=utf-8 python tools/map_screen.py --json port/data/re3_map_screen.json
PYTHONIOENCODING=utf-8 python tools/map_screen.py --png /tmp/mappng   # 9x16 CLUTs + 9 tiras

# desmontagem (base 0x80010000)
PYTHONIOENCODING=utf-8 python -c "import sys;sys.path.insert(0,'tools');\
from exe_parse import Exe;e=Exe('extracted/ntsc-u/SLUS_009.23');e.disasm(0x800713dc,60)"
```

Checagens que devem fechar (usei todas):

* `sum(0x800a03ac[0..8]) == 634880 == os.path.getsize(MAP_U.MAP)`
* por pagina: `4 + 8*n_grupos + 12*sum(n1+n2) == sec[0].size`
* por pagina: `sec[k].off + sec[k].size == sec[k+1].off`, `sec[0].off == 0x24`
* `f(n) = ((hi(n * (s32)0x91a2b3c5) + n) >> 8) - (n>>31)` == `trunc(n/450)` para todo
  `n` em `[-2e6, 2e6]`
* `0x800a03d0 + 8*12 == 0x800a0430` (fim da tabela de setas = inicio do remap)
* `0x801b0050 + 76*0x10 == 0x801b0510` e `0x801b0600 + 8*0x14 == 0x801b06a0`
* `(0x801afe80 - 0x801ac000) / 0x50 == 200`
* os 8 glifos de direcao existem em `(0..63, 240..247)` de toda pagina
* `sec[3].img_rect.y == 216` e `216 + 256 == 472` (VRAM da tira)

---

## 12. CORRECOES DA AUDITORIA (revisao adversarial independente)

Tudo abaixo foi **remedido do zero** por um segundo agente, sem reusar `tools/map_screen.py`
(parse proprio do `MAP_U.MAP`, desmontagem propria com `tools/exe_parse.py`, renderizacao propria
dos recortes de TIM). O texto acima **nao foi apagado**; esta secao lista o que confirma, o que
corrige e o que acrescenta.

### 12.1 ERRO 1 (impacta implementacao): `ctx->0xaa` e `ctx->0xab` estao INVERTIDOS

A tabela da §2 diz `+0xaa = area exibida` e `+0xab = area corrente (do jogador)`. E o contrario:

* **`+0xab` = area EXIBIDA** (a pagina que e carregada e desenhada).
  Unica escrita "dinamica": `0x8007000c` — `ctx->0xab = tabela_0x800a04f8[ctx->0xbb]` junto com
  `ctx->0xba = 1` (pedir recarga da pagina). Tambem forcada em `0x8006dbb0/0x8006dbb4`
  (sub-tela `ctx->0xb8`) e usada como argumento de `map_load_page` em `0x8006ee3c/0x8006ee50`.
* **`+0xaa` = area DO JOGADOR** (constante durante a tela). Unica escrita: `0x8006ed70`, do
  `map_room_to_page_group(stage_atual, sala_atual)` — exatamente a prova que a propria nota cita.
* No init as duas nascem iguais (`0x8006ed54` e `0x8006ed70` usam a mesma fonte), o que e por que
  a troca passou batido.

**Consequencia real:** no laco de desenho (§6.3, §9) `flag_get(0x800d2124, ctx->0xab)` e
`visitado(ctx->0xab, g)` usam a area **EXIBIDA**, nao a do jogador. Quem implementar o
pseudocodigo da §9 com "area = area do jogador" vai revelar/esconder os comodos errados assim que
o jogador folhear outra area com as setas esquerda/direita. As comparacoes `0xab == 0xaa`
(marcador §5.4, comodo vermelho §6.6) sao simetricas e nao mudam.

### 12.2 ERRO 2: o 4o caso especial de `0x80073ccc` NAO retorna

A §6.4 escreve `if (stage==2 && sala==0x17 && ...) { *sala = 2; return; }`. O binario faz
`sb $s2, ($s0)` em `0x80073dd8` e **cai** em `0x80073ddc`, seguindo para o ajuste `stage -= 5` e
para a busca linear na tabela. Os tres primeiros casos (`0x80073d18`, `0x80073d88`) tem `j` de
retorno; o quarto nao. Resultado final e o mesmo (nao existe registro `(2,0x02)` na tabela
`0x800a0430`), mas o fluxo correto e "cai atraves".

### 12.3 ERRO 3: contagem de excecoes de tamanho da LISTA B

§4.2 diz "sempre 8x7 (4 excecoes 8x5 / 6x7)". Medido nos 366 registros: **360 de 8x7,
4 de 8x5 (`v1=252`) e 2 de 6x7 (`u=33..38`) = 6 excecoes**, nao 4.

### 12.4 ERRO 4: os `u0` da LISTA B nao sao todos multiplos de 8

§4.2 diz "6 icones em `u=0,8,16,24,32,40`". As colunas-base estao certas, mas **41 dos 366
registros usam `base+1`**. Retangulos `(u0,v0,u1,v1)` distintos, com contagem:

| `u0,v0,u1,v1` | n | | `u0,v0,u1,v1` | n |
|---|---|---|---|---|
| `0,248,7,254` | 105 | | `24,248,31,254` | 16 |
| `1,248,8,254` | 36 | | `32,248,39,252` | 4 |
| `8,248,15,254` | 148 | | `32,248,39,254` | 18 |
| `9,248,16,254` | 1 | | `33,248,38,254` | 2 |
| `16,248,23,254` | 12 | | `40,248,47,254` | 22 |
| `17,248,24,254` | 2 | | | |

Ou seja: **use o `u0` literal do registro**, nao "encaixe no icone mais proximo".

### 12.5 ERRO 5 (cosmetico): "7 SPRT" na tabela de pool da §4.3

Sao **6 SPRT** (bussola, regua x2, escala x2, nome da area), cada uma em par de framebuffer:
12 primitivas de `0x14` de `0x801b0510` a `0x801b05ec`, e `0x801b0510 + 12*0x14 = 0x801b0600`
(inicio dos rotulos de andar). A tabela da §7.3 ja lista as 6 corretamente; e so o "7" do
resumo. Contagem dos lacos do init: 2 (linha H) / 2 (linha V) / 8 (setas, passo `0x28`) /
`0x4c`=76 (linhas cinza) / 2 por SPRT / 4x2 (andares) / 2 (TILE).

### 12.6 LACUNA PREENCHIDA: `ctx->0xbb` e a tabela de selecao de area `0x800a04f8`

Nao estava na §2. `ctx->0xbb` e o **indice na lista de areas selecionaveis**:
`u8[7]` em **`0x800a04f8` = `{0, 5, 1, 2, 6, 3, 4}`** = UPTOWN, POLICE STATION, DOWNTOWN,
CLOCK TOWER, HOSPITAL, PARK, DEAD FACTORY (**a ordem cronologica do jogo**).
Zerada em `0x8006ed44`; `--` em `0x8006fe0c` com wrap para 6 em `0x8006fe20` (prova de que sao 7
entradas); `++` em `0x8006fe58`; consumida em `0x8006ffec..0x8007000c`. `0x800a04f8+7` e padding:
`0x800a0500` ja e a tabela de ponteiros de estado (`0x8006f708`, ...).

### 12.7 Corroboracoes independentes (nao eram provas da nota original)

1. **`file index 0x3a` = `ETC/MAP_U.MAP` provado sem usar o tamanho.** A entrada da tabela
   `0x800946a4` e `{u32 size; u24 lba; u8 flags}`; entrada `0x3a` -> `size=634880`, **`lba=6807`**.
   Em `tools/re3.idx` (indice jPSXdec da ISO) o setor **6807 e exatamente `CD_DATA/ETC/MAP_U.MAP`**
   (e 6497 = `MAP_J.MAP` = indice `0x39`). Pelo mesmo metodo: `0x60` -> lba 11336 = `STMOJIU.TIM`,
   `0x44` -> lba 9540 = `RADAR.TIM`. Os tres indices de arquivo da nota estao certos.
2. **O bitmap de visitados tem 18 palavras, exatamente.** `0x800d20dc + 0x48 = 0x800d2124`
   (banco "mapa obtido") e `+0x4c = 0x800d2128` (banco "area visitada"). Os dois bancos ficam
   colados no fim do array de `9*2 = 18` palavras — confirma o layout de 2 palavras por pagina
   por adjacencia de simbolos, alem da aritmetica de `0x80071614`.
3. **Divisor 450 e unico.** `f(n) = ((hi(n*(s32)0x91a2b3c5) + n) >> 8) - (n>>31)` bate com
   `trunc(n/450)` em todo `n` de -2e6 a +2e6 (0 divergencias) e **falha** para 448, 449, 451 e 452.
4. **Mapeamento pagina -> area confirmado por PIXEL, nao por suposicao.** Renderizando a tira
   `sec[3]` de cada pagina e recortando `(32,0) 144x16` (o `uv` que o init da §7.3 manda para a
   SPRT do nome da area), le-se, na ordem das 9 paginas: `UPTOWN`, `DOWNTOWN`, `CLOCK TOWER`,
   `PARK`, `DEAD FACTORY`, `POLICE STATION`, `HOSPITAL`, `UPTOWN`, `DOWNTOWN`. Idem
   `(32,16) 72x15` = "0 5 10 15" / `(32,31)` = "[m] 1:610" e `(104,16)` = "0 10 20 30" /
   `(104,31)` = "[m] 1:1220".
5. **Rotulos de andar de TODAS as paginas com andar** (a nota so tinha a pagina 5):
   CLOCK TOWER = `1F`, `2F`, `3F`; DEAD FACTORY = `1F`, `2F`; POLICE STATION = `1F`, `2F`;
   **HOSPITAL = `B3`, `1F`, `4F`** (nao e `1F/2F/3F`). Sempre nas 4 celulas
   `(176,216) (216,216) (176,232) (216,232)` da tira, na ordem andar 0,1,2,3.
6. **Sprite do marcador e CLUT 3.** Renderizando `(0,240)-(64,248)` do atlas `sec[2]` com a
   CLUT 3 (`idx & 3`): **8 setas azuis em 8 direcoes**, uma por celula de 8x8. O `0x7b53` do
   `sh` em `0x8006f144` de fato aponta para a paleta azul.
7. **Setas de rolagem.** Render de `STMOJIU.TIM` `(0,0)-(56,13)` com a CLUT indice 2:
   **4 triangulos verdes** na ordem **cima, baixo, esquerda, direita**, casando com os `uv`
   `0-13 / 14-27 / 28-41 / 42-55` da tabela `0x800a03d0` e com os centros
   `(161,32) (161,208) (32,121) (288,121)`.
8. **O detalhe mais fragil da nota esta CERTO e e critico:** existem DOIS uploaders de TIM.
   O generico `0x800784e0` **sobrescreve** `prect->y` com `0` ou `256` (`0x80078538`:
   `sll v0,8` -> `sh v0,2(v1)`), o que jogaria a tira de rotulo para a VRAM `y=256`. A tira usa
   o uploader proprio da tela de mapa, `0x8006ebec`, que **soma** `0x100` ao `y` do arquivo
   (`0x8006ec4c`: `addiu v1,v1,0x100`), preservando o `216` -> **VRAM y = 472**. Quem portar
   precisa dessa distincao, senao os rotulos ficam em cima do atlas.
9. Confirmados tambem (medidos de novo, sem divergencia): `sum(sizes)=634880`; identidade
   `4+8n+12*sum == sec[0].size` nas 9 paginas; contiguidade das secoes e `sec[0].off=0x24`;
   `427 + 366 = 793` registros; `clut_row` da lista A = `{0:302, 1:103, 7:19, 4:2, 2:1}`;
   `misc` da lista A em `{0,1,2,3}`; `+0xa` = 0 nos 793; `n_grupos` = 65,78,13,23,18,11,12,65,78;
   ancoras = 41,28,13,23,18,11,12,41,28 e os 11 valores da pagina 5; `scroll_x/scroll_y` e
   `tem_andares/n_andares` das 9 paginas; `sub[3]`/`sub[4]` das paginas 0, 1 e 4 byte a byte;
   os 49 registros de `0x800a0430`; as 96 B de `0x800a03d0`; `MAP_J` vs `MAP_U` diferindo **so**
   em `sec[3]` da pagina 4; `sec[2]` 4bpp 512x256 (256x256 na Clock Tower) com `clut_rect
   (304,0,16,16)`; `sec[3]` 4bpp 256x40 `img_rect (0,216,64,40)`; as 16 CLUTs com semantica
   `idx&3` (linhas 0-7) / `idx>>2` (linhas 8-15); emissor `0x8007116c` inteiro (inclusive
   `clut_row==7 -> modo=0`, `tpage = 0x10|((misc>>1)+7)&0xf`, `clut = ((modo+clut_row+
   (misc&1)*8+0x1ea)<<6)|0x13`, `sx=+0xa0`, `sy=+0x78`); quad do marcador `(X+0x9c,Y+0x74)..
   (X+0xa4,Y+0x7c)`; `u = ((ang+0x100)>>6)&0x38`; enderecos globais `0x800cabf8/0x800cac00/
   0x800cac32/0x800d1f76/0x800d1f78/0x800cc848/0x800cc840/0x800cc834`; as 2 gambiarras de
   coordenada (§5.5); pre-revelacoes de `0x80071510` (incluindo `pag0 grp47` do `lui a0,1`);
   unico chamador `0x8004986c`; `gate_grupo` area 0 grupos `0x11..0x1a`; cauda de `0x8007275c`;
   bancos `0x800d1fa0` (sel!=0) e `0x800d20cc` (sel==0) em `0x80071878`; zoom `100`/`50`;
   limites `+320`/`+224`; pool `0x801ac000`/`0x801ac028` passo `0x50`; maximo de 184 registros
   por pagina; `ctx = 0x800e01c0` hardcodado em `0x800716b8`, `0x800718a8`, `0x8007277c`;
   `0x800746c0` = SFX (a0 = 5, 6, 4) e nao leitura de pad; as 10 strings de `0x800a0328`.

### 12.8 Observacao sobre as cores da §3.5

Os hex da §3.5 usam a conversao `round(v5 * 255/31)` (`#004210`); um port que use `v5 << 3`
vai obter `#004010`. **Os valores de 15 bits do CD sao os mesmos** — nao e divergencia, mas a
nota deveria dizer qual conversao usou.

### 12.9 Veredito da auditoria

**PARCIAL.** A tese central se sustenta com folga: das ~30 grandezas que remedi do zero, todas
bateram, incluindo as de maior risco (divisor 450, centro `(160,120)`, `(156,116)-(164,124)` do
marcador, indices de arquivo, tabela de setas, remap de sala, enderecamento do bitmap, coordenadas
das SPRT). Os erros sao: a **inversao `0xaa`/`0xab`** (a unica com risco real de bug no port), o
`return` a mais na §6.4 e tres erros de contagem/redacao (§12.3, §12.4, §12.5). Nada aqui veio de
RE2, de wiki ou de suposicao.
