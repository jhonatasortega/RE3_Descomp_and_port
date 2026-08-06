# Formato `MAP_x.MAP` — telas de mapa do menu (RE3 PS1) e de-para HD

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `maps`)
> - **Formato:** cabeçalho/diretório + sequência de blocos TIM 4bpp (16 CLUTs) — plantas da tela de mapa
> - **Extensão/origem:** `CD_DATA/ETC/MAP_U.MAP` (EN) e `MAP_J.MAP` (JP), 634880 B cada; HD em `hires/map/*.webp`
> - **Ferramenta:** [`tools/map_decode.py`](../../tools/map_decode.py) (+ `map_clut_match.py`, `map_hd_locate.py` para o de-para HD)
> - **Decompilado:** **100%** — 9 páginas + 9 tiras decodificadas (7 áreas distintas).
> - **Feito:** decode das plantas por CLUT; de-para HD por geometria (55/92 `.webp` casados).
> - **Falta:** stitch da tela final (coordenadas de blit) e escolha dos tiles HD PT — não bloqueante; sem tela de mapa no protótipo (ver [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md)).

> Fonte PS1: `extracted/ntsc-u/CD_DATA/ETC/MAP_U.MAP` (EN) e `MAP_J.MAP` (JP), 634880 bytes cada.
> Fonte HD: `hires/map/*.webp` (Seamless HD Project, 92 arquivos; GOG **somente leitura**).
> Ferramentas: `tools/map_decode.py`, `tools/map_clut_match.py`, `tools/map_hd_locate.py`.
> Saida: `godot/assets/MAP/` (PNG do PS1 + `.webp` HD casados + `map_depara.json`).

## 1. Visao geral

`MAP_x.MAP` guarda as **plantas das areas** exibidas na tela de MAPA do menu. O arquivo e
composto por um **cabecalho/diretorio** (metadados de layout) seguido de uma sequencia de
**blocos TIM** (formato padrao de imagem do PS1) concatenados. Cada area do jogo tem
**um par de blocos TIM**: a *pagina* (o desenho da planta) e uma *tira* (o rotulo com o nome).

`MAP_J` e `MAP_U` sao **identicos exceto pelas tiras de rotulo** (texto EN vs JP; 1a diferenca
em `0x50f81`, dentro de uma tira). As paginas (geometria) sao iguais nos dois.

## 2. Estrutura geral do arquivo

```
0x000000  Cabecalho / diretorio (ate 0x98c) — metadados da tela de mapa
0x00098c  Bloco TIM  #0  = pagina UPTOWN        (512x256, 4bpp, 16 CLUTs)
0x010bac  Bloco TIM  #1  = tira  UPTOWN         (256x40,  4bpp, 1 CLUT)   <- rotulo
0x012cf8  Bloco TIM  #2  = pagina DOWNTOWN      (512x256)
...        (par pagina+tira por area)
0x09947c  Bloco TIM  #17 = tira  DOWNTOWN (2)
```

Sao **18 blocos TIM = 9 paginas + 9 tiras**. As paginas usam VRAM `ix=0, iy=0`; as tiras
`ix=0, iy=216` (logo abaixo da area de desenho) — por isso alguns tiles HD tem 216 px de altura.

### 2.1. Cabecalho / diretorio (`0x00`..`0x98c`) — parcialmente decodificado

```
0x00  u32  = 4            (contador; provavelmente nº de "bancos"/paginas base)
0x04  u32  = 0x024        ponteiro -> tabela de pares (id, offset)
0x08  u32  = 0x788        ponteiro -> sub-tabela
0x0c  u32  = 0x7ac        ponteiro -> sub-tabela
0x10  u32  = 0x1e0        ponteiro
0x14  u32  = 0x98c        offset do 1º bloco de pixel (1º TIM)
0x18  u32  = 0x10220
0x1c  u32  = 0x10bac      offset (2º TIM / tira)
0x20  u32  = 0x1440
0x24  ...   tabela de pares  (packed_id:u32, offset:u32)
            packed_id = (grupo<<16)|contagem  (ex.: 0x00040001, 0x00050004)
            offset aponta p/ listas de primitivos de desenho (0x20c..0x788):
            registros curtos tipo (x,y,w,h) de comodos/marcadores, terminador `ff ff ff 00`.
```

O cabecalho e o **overlay vetorial** da tela de mapa (retangulos de comodos, marcadores de
item/porta, escala) desenhado por cima dos tiles TIM. Nao e necessario para extrair as
imagens das plantas — fica documentado como parcialmente revertido.

### 2.2. Bloco de pagina (planta)

TIM 4bpp (`flag=0x08`: bpp=0, has_clut=1) com **16 CLUTs de 16 cores**:

```
+0x00 u32 0x00000010   magic TIM
+0x04 u32 0x00000008   flag (4bpp + CLUT)
+0x08 bloco CLUT: len:u32, (x,y):u16, cw=16:u16, ch=16:u16, [16*16 cores BGR555]
+...  bloco imagem: len:u32, (ix,iy):u16, iw:u16, ih:u16, [pixels 4bpp]
      largura em pixels = iw*4  (iw=128 -> 512 px; iw=64 -> 256 px), altura = ih (256)
```

**Ponto-chave (CLUT = estado/andar):** no TIM, a cor `0x0000` da CLUT = **transparente**.
Como cada uma das 16 CLUTs tem **valores diferentes** nas suas entradas, cada CLUT deixa
**indices diferentes transparentes** — ou seja, **cada CLUT desenha um subconjunto de comodos**
(um andar, ou o estado "visitado/perigo/atual"). O plano completo (todos os comodos) so aparece
com o palette 0. Isso explica por que o HD tem **varios `.webp` por planta** (um por cor/andar).

### 2.3. Bloco de tira (rotulo)

TIM 4bpp 256x40, 1 CLUT. Contem o **nome da area** renderizado (fonte). E o unico ponto
onde `MAP_U` (EN) difere de `MAP_J` (JP).

## 3. As 9 paginas (ordem no arquivo)

| # bloco | offset | area (rotulo lido da tira) | dim SD | obs |
|---|---|---|---|---|
| 0  | `0x00098c` | **UPTOWN**          | 512x256 | rótulo "UPTOWN"; texto embutido "IN CITY AREA 1", WAREHOUSE/BAR |
| 2  | `0x012cf8` | **DOWNTOWN**        | 512x256 | SUB STATION / NEWS PAPER OFFICE / PARKING |
| 4  | `0x024b74` | **CLOCK TOWER 1F/2F/3F** | 256x256 | pagina de 256 (1 tile) |
| 6  | `0x02ed1c` | **PARK**            | 512x256 | patio pentagonal + jardim |
| 8  | `0x040d04` | **DEAD FACTORY 1F/2F** | 512x256 | fabrica/laboratorio |
| 10 | `0x052ab4` | **POLICE STATION 1F/2F** | 512x256 | RPD |
| 12 | `0x064ad8` | **HOSPITAL B3/1F/4F** | 512x256 | multi-andar (cores por andar) |
| 14 | `0x077088` | **UPTOWN (2)**      | 512x256 | geometria **identica** ao bloco 0 (NCC 1.00) |
| 16 | `0x08925c` | **DOWNTOWN (2)**    | 512x256 | geometria **identica** ao bloco 2 (NCC 1.00) |

**7 areas distintas.** Os blocos 14/16 sao **duplicatas geometricas** de UPTOWN/DOWNTOWN
(mesmo desenho, muda so o estado/overlay — provavelmente 2ª metade do jogo / rota alternativa).

## 4. De-para HD (`hires/map`)

O HD do Seamless veio de um **PC russo** e e **redesenhado** (texto em russo, ex.: `ПАРКОВКА`,
`ПОД СТАНЦИЯ`), entao **nao da pra reproduzir o CRC-32 do blit** (ver `hd_ui.md`). Casamento por
**geometria**, independente de cor/idioma:

- **PS1:** mascara de comodos = pixels **nao-transparentes** por CLUT (§2.2).
- **HD:** mascara = pixels que diferem do **fundo** (cor de canto dominante; preto/branco/cinza).
- **NCC deslizante vetorizado** da mascara HD (downscale 4x -> bloco SD 256) sobre cada
  `(pagina, CLUT)`; acha `(pagina, CLUT, dx, dy, ncc)`. Cada pagina 512 = 2 tiles HD de 256
  (`dx=0` esquerda, `dx=256` direita). 1:N por cor/andar/tile.

Ferramenta principal: **`tools/map_clut_match.py`** (per-CLUT). `tools/map_hd_locate.py` faz a
versao por palette-0 (mais simples, mas perde os variantes multi-andar).

### Resultado

- **92 `.webp` HD**, **55 casados** com NCC ≥ 0.80 (51 deles ≥ 0.90).
- **10 representantes** (1 por area/tile distinto) copiados p/ `godot/assets/MAP/` como
  `HD_<AREA>_x<dx>_<HASH>.webp`.
- ~8 `.webp` na faixa 0.63–0.78 = variantes de **preenchimento parcial** (estado) das mesmas
  plantas (candidatos; nao aplicados).
- ~29 `.webp` < 0.6 = **paineis de legenda/indice/escala** (icones/texto), sem planta -> sem par.

### Validacao visual (Read lado a lado)

Confirmado que sao a **mesma planta** (geometria identica; muda so a cor do estado):

| PS1 | HD | conferido |
|---|---|---|
| UPTOWN x0 | `1DC55D69` | comodos do warehouse, marcador "BAR" e sala "S" batem |
| DOWNTOWN x256 | `8568B9FD` | grandes salas/estacionamento da regiao direita batem |
| HOSPITAL x0 | `0D804E54` | sala grande + corredor e fileira de salas inferiores batem |
| PARK x256 | `44CED087` | corredor em L + sala do patio batem (HD em contorno) |
| POLICE x0 | `5DF8367A` | layout do RPD, salas "S" batem |
| CLOCK x0 | `1C82E86B` | hall diagonal + marcadores de legenda batem |

## 5. Arquivos gerados

- `godot/assets/MAP/PS1_<n>_<AREA>.png` — as 9 paginas decodificadas (palette 0 = plano completo).
- `godot/assets/MAP/HD_<AREA>_x<dx>_<HASH>.webp` — 10 tiles HD representativos casados.
- `godot/assets/MAP/map_depara.json` — de-para completo: paginas, representantes, e o resultado
  por hash (`area, page, clut, dx, dy, ncc, ok`).

## 6. Pendencias / notas

- **Stitch da tela final:** cada pagina 512x256 e blitada em tiles; a tela de menu (320x240)
  compoe tiles + overlay vetorial do cabecalho (§2.1). Reproduzir o layout exato exige
  decodificar as coordenadas de blit do engine (nao feito; nao e necessario para ter as plantas).
- **De-para 100% exato:** habilitar o dump do `bio3hd.asi` e jogar daria o par por hash
  (ver `hd_ui.md §2`), mas exige escrita na pasta do jogo (aqui somente-leitura).
- **Idioma:** para o remake PT, preferir os tiles HD PT quando existirem (o pack tem variantes de
  idioma); os representantes atuais podem estar em RU/EN.

## 7. Licenca

Assets do **Seamless HD Project** sobre arte da **Capcom**. Uso pessoal/local ok; distribuicao
exige aval dos autores + Capcom (ver `hd_seamless.md`).
