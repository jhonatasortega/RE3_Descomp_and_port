# Fluxo de abertura no port: telas em HD/PT-BR, legenda dos FMV e a cena `boot.tscn`

> **O que este doc é.** A parte de IMPLEMENTAÇÃO do fluxo de abertura, e a evidência NOVA
> que ela exigiu (as variantes de idioma do pack HD e a marcação de legenda do mod PT-BR).
> A engenharia reversa do fluxo em si — endereços, tempos, tabelas de sprite — está em
> [`menu_titulo.md`](menu_titulo.md) e **não é repetida aqui**: quando um número aparece,
> vem com o sítio.
>
> **Ferramentas** (todas rodadas de verdade): [`tools/boot_assets.py`](../../../tools/boot_assets.py),
> [`tools/legendas_fmv.py`](../../../tools/legendas_fmv.py),
> [`tools/video_ogv.py`](../../../tools/video_ogv.py), mais
> [`tools/boot_flow.py`](../../../tools/boot_flow.py) e
> [`tools/title_sprites.py`](../../../tools/title_sprites.py), que já existiam.
>
> **Código:** `port/present/boot.gd`, `port/present/titulo.gd`, `port/present/video.gd`,
> `port/present/prologo.gd`, `port/scenes/boot.tscn`.
> **Teste:** `port/dev/tests/test_boot.gd` (267 asserts).
> **Sondas:** `port/dev/diag_video.gd`, `port/dev/shot_boot.gd`.
>
> **§10 e §11 são da rodada mais recente:** o BUG do clique na dificuldade, o alinhamento pelo
> `title_mapping.xml`, o banco de SE do som do menu e — o maior — a **VINHETA**: o prólogo do
> `OPENING.BIN` é um **interpretador de 13 opcodes** rodando um **script de 80 bytes que mora
> no fim de `ETC/OPENING1.DAT`**. Com ele a linha do tempo do prólogo ficou medida, e a legenda
> `prologue.xml` mudou de dono (era do `opn.mp4`).
>
> **§7 e §8 são da rodada anterior:** a **tabela de filmes `0x8009ca64`** (o reprodutor de FMV do
> RE3 é uma tarefa do EXE, não um overlay) e as **sete correções** que o dono apontou depois
> de jogar a abertura — inclusive o vídeo que faltava antes do menu.

---

## 1. O que a cena faz

```
aviso legal (5,01 s)  ->  logo CAPCOM (4,00 s)  ->  FILME DE ATRAÇÃO roop (15,4 s)
   ->  TÍTULO navegável  ->  dificuldade  ->  ETC/INIT_TBL.DAT
   ->  VINHETA: prólogo narrado (55,56 s, legenda PT-BR)  ->  FMV opn (90,6 s)  ->  R10D
```

> **⚠ A VINHETA é NOVA (§11)** e é o item "falta a vinheta do jogo antes do próximo vídeo".
> `0x801960d8` cria a tarefa do `OPENING.BIN` (overlay 5) e só um tick depois, em
> `0x801960e8`, o TITLE chama `filme_prepara(0)` — por isso o prólogo vem ANTES do `opn`.
> **A legenda `prologue.xml` mudou de dono:** era desenhada sobre o `opn.ogv` e agora é do
> prólogo, com três medidas independentes sustentando a troca (§11.3).

> **⚠ O `filme roop` é NOVO nesta rodada** e é o "vídeo que faltava antes do menu".
> `0x801943a4` chama `filme_prepara(0xc)` no FIM do handler 0 do `TITLE.BIN` — depois do
> logo CAPCOM, depois do reset (`0x80194374`) e depois do pulo (`0x8019432c`) — e o código
> **espera o filme acabar** (`0x801943ac` gira em `0x800cc858 & 0x10000`). Detalhe em §7.

Tudo em **ticks de tarefa**, que é a unidade que o binário conta. Nada foi arredondado:

| passo | ticks | sítio | segundos a 59,94 Hz |
|---|---:|---|---:|
| `aviso_fade_in` | 30 | `0x80185480` `fade_start(T=0x1e)`, `abr=2` | 0,50 |
| `aviso_exibicao` | 240 | `0x801854a8` `s0=0xef` → 240 × `VSync(0)` | 4,00 |
| `aviso_fade_out` | 30 | `0x8018550c` | 0,50 |
| `capcom_para_branco` | 30 | `0x80194218` st0, `abr=1`, `0x000000→0xffffff` | 0,50 |
| `capcom_entra_logo` | 30 | `0x80194274` st2, `abr=1`, `0xffffff→0x000000` | 0,50 |
| `capcom_exibicao` | 120 | `0x8019427c` st4, contador `0x78` | 2,00 |
| `capcom_sai_logo` | 30 | `0x80194294` st6 | 0,50 |
| `capcom_para_preto` | 30 | `0x801942d4` st8 | 0,50 |
| `filme_atracao` | — | `0x801943a4` `filme_prepara(0xc)`; 231 quadros a 15 fps | 15,40 |
| `titulo_espera` | 6 | `0x80194b08` sub1 (`ctx+0x14` = 160, −30 por chamada) | 0,10 |
| `titulo_flash` | 5 | `0x80194b08` sub1, `fade(T=5)` `abr=1` | 0,08 |
| `titulo_fade_in` | 60 | `0x80194b08` sub2, `fade(T=0x3c)` `abr=2` | 1,00 |
| **até o menu** | **611** + o filme | | **10,19** + 15,40 |
| `atrator_timeout` | 900 | `0x8019454c` `*(u16*)(ctx+0x16) = 0x384` | 15,02 |

Conferido em execução real: `godot --path port --rendering-driver opengl3 --quit-after 2400
res://scenes/boot.tscn` imprime os 11 passos na ordem e nas durações acima e para no `menu`.

### 1.1 A unidade de tempo (resolvendo o item §10.1 de `menu_titulo.md` por conversão)

O divisor de quadro `*(u8*)0x800d442c` vale **1** (`0x80029870`, regravado pelo TITLE em
`0x8019412c`), então **1 tick = 1 retraço vertical = 60000/1001 Hz**. O port roda o gameplay a
30 Hz (`Clock.HZ`) → **2 ticks por quadro de jogo**. A cena de boot **não** usa o `Clock`: conta
tempo real na taxa medida, o que preserva a duração em segundos.

Isso NÃO fecha a contradição registrada no §10.1 — só evita reescrever o número medido. O que
**corrobora** a leitura de 59,94 Hz é o atrator: 900 ticks = **15,0 s**, que é um tempo de
atração plausível; a 30 Hz seriam 30 s.

### 1.2 O fade

`0x8002a35c` (início) + `0x8002a49c` (por quadro) montam um TILE `0x62` de tela cheia
(retângulo monocromático semitransparente) com a cor interpolada em inteiro,
`c = c0 + (c1−c0)·t/T` por componente, e o blend vem do `abr` do `DR_MODE`:
**`abr=1` = fundo + primitiva**, **`abr=2` = fundo − primitiva**.

No port são dois `ColorRect` de 1280×960 com `CanvasItemMaterial` em `BLEND_MODE_ADD` e
`BLEND_MODE_SUB` — a **mesma operação**, não uma imitação com alpha. Validado por render:
`_boot_aviso_fade_in.png` (t=15/30) mostra a imagem a meio caminho do preto, e
`_boot_capcom_entra_logo.png` (t=15/30) mostra o logo lavado para o branco.

**DECLARADO:** na entrada do título o original tem DOIS slots ativos ao mesmo tempo (slot 1
segurando preto subtrativo + slot 0 rampando branco aditivo por 5 ticks). Qual desenha primeiro
está na Ordering Table, que **eu não li**. O port desenha SUB e depois ADD → "preto → clarão de
5 ticks → preto → fade-in de 60 ticks". A **duração** é medida; a aparência do clarão é leitura.

---

## 2. ⚠ CORREÇÃO: o casamento HD do repo pegou a variante de IDIOMA errada

O pack HD instalado tem o **mesmo bloco em várias línguas**. O casamento por conteúdo que
gerou `port/assets/MENU/*/hd/` escolheu, para as telas de abertura, as variantes erradas:

| tela | o que o repo tinha | o que é | o certo (PT-BR) |
|---|---|---|---|
| título | `hires/bgd/18CC5627` | arte **japonesa**: "BIOHAZARD 3 LAST ESCAPE" | **`ED2C2D33`** "EDIÇÃO DEFINITIVA / RESIDENT EVIL 3 NEMESIS" |
| aviso legal | `hires/bgd/DC361616` | aviso em **russo** ("Внимание! Эта игра…") | **`4784F00D`** "ESSE JOGO CONTEM CENAS DE VIOLÊNCIA EXPLÍCITA E SANGUE" |
| logo CAPCOM | `hires/bgd/5E54FDD9` | ✅ já era o certo (é do conjunto PT) | `5E54FDD9` |
| título (Mercenários) | `hires/bgd/81AA5030` | ✅ já era o certo | `81AA5030` "OS MERCENARIOS / OPERAÇÃO MAD JACKAL" |

**Por que o casamento errou:** o que muda entre as variantes é justamente o TEXTO, que ocupa boa
parte do quadro, então a correlação despenca. NCC em miniatura cinza (mesma métrica de
`tools/hd_match.py`): o vizinho mais próximo de `18CC5627` é `ED2C2D33` com **0,52** e o de
`DC361616` é `4784F00D` com **0,37** — longe dos 0,99 de um par verdadeiro. Um casador por
conteúdo não distingue idioma; ele escolhe por cenário.

**Como achei o conjunto PT-BR:** o mesmo critério que `tools/memo_pt.py` usa para as páginas de
documento — **mtime**. O pack russo é de **jan/2025**; o pacote "Edição Definitiva Dublado"
acrescentou os arquivos em **jun/2025**. Em `hires/bgd` são **34 de 1316** arquivos posteriores a
2025-05-23; montei a folha de contato dos 34 e li cada um. Além das telas acima, ali estão as
telas de epílogo, "MUITO OBRIGADO POR JOGAR", o ajuste de brilho e a tela de dicas — todas em PT.

> **Consequência para o resto do repo:** `port/assets/MENU/07_warning/hd/` tem DOIS arquivos
> (`WARNU_00…` e `WARNJ_00…`) apontando para o **mesmo** hash `DC361616`. Dois blocos SD
> distintos casando com um HD só é sintoma de casamento por cenário. Quem for revisar as outras
> telas de menu deve conferir a variante de idioma pelo mtime antes de confiar no par.

---

## 3. O atlas de rótulos do título em HD e em PT-BR

`ETC/TITLEU.DAT` TIM[2] é o atlas de texto do título: **256×256, 4 bpp, 1 CLUT de 16 cinzas**
(`menu_titulo.md` §3.3). A contrapartida HD é **`hires/misc/3776D4A3.webp`, 1024×1024 = 4× a
página de VRAM** — a mesma regra "HD = 4× SD" do resto do pack. Há também
`3776D4A3.psd` na pasta (o fonte do trabalho de tradução) e a variante **russa** `00E35CED`.

**As linhas (`v`) do atlas PT coincidem com as do atlas do PS1** nas faixas que interessam:
`v=104` (seleções), `v=120` (copyright), `v=128` (config/modo), `v=144` (mercenários),
`v=176` (EASY/HARD MODE). Isso é confirmado de forma **independente** por
`mod_BH3_Portuguese/xml/title_mapping.xml`, que é o mapa de recortes do próprio pacote PT-BR e
lista, entre outras: `heavy mode` em `u=192 v=128 w=62` e `light mode` em `u=128 v=128 w=56`,
que caem exatamente sobre "MODO DIFICIL" e "MODO FACIL" na imagem.

`title_mapping.xml` também corrobora POSIÇÃO DE TELA lida do binário: ele põe
`heavy mode` em `x=80 y=193` e `light mode` em `x=180 y=193`, os mesmos `x` dos sprites
`diff_HARD_MODE` (80,193) e `diff_EASY_MODE` (180,193) de `0x801945e4`. Duas fontes
independentes, mesmo número.

> **⚠ CORREÇÃO (§10.2): esses `x` são da CÉLULA, não da tinta.** O port desenhava a TINTA em
> `x=80` e este parágrafo dizia que isso "batia" com o `title_mapping.xml` — comparação
> errada. A célula `heavy mode` tem 62 px e a tinta dela começa 6 px adiante, então o pacote
> PT-BR põe a tinta em **86**, não em 80. O port está 6 px à esquerda desde a rodada
> passada; agora `tools/boot_assets.py` LÊ o XML e usa `x + tinta_x`.

### 3.1 De-para item do PS1 → recorte HD PT-BR

`w` é a **caixa de tinta medida** no próprio atlas (`python tools/boot_assets.py --medir`), não
a largura da célula. Posição de tela = o `x,y` do `SPRT` de `0x801945e4`, com o rótulo PT
**centralizado no centro do retângulo original** (escolha do port: as larguras diferem).

| item do PS1 (célula) | rótulo HD PT-BR | célula PT | tinta | equivale |
|---|---|---|---|---|
| `NEW GAME` (0,104,48) | **COMEÇAR JOGO** | 0,144,54 | x=0 w=53 | **declarado** |
| `LOAD GAME` (64,104,50) | **CARREG. JOGO** | 128,104,64 | x=5 w=53 | exato |
| `GAME CONFIG` (0,128,60) | **CONFIG** | 28,128,34 | x=2 w=28 | **declarado** |
| `HARD MODE` (56,176,56) | **MODO DIFICIL** | 192,128,62 | x=6 w=49 | exato |
| `EASY MODE` (0,176,54) | **MODO FACIL** | 128,128,56 | x=6 w=45 | exato |
| copyright 2 linhas (0,160,208×16) | © CAPCOM CO.,LTD.1999,2006 ALL RIGHTS RESERVED. | 0,120,226×8 | x=18 w=173 | **declarado** |

Os três "declarado", com o motivo:

1. **`NEW GAME` → "COMEÇAR JOGO".** A célula que o PS1 usa (`u=0 v=104`) contém
   **"MODO ORIGINAL"** no atlas PT — é o item do menu de 5 opções da versão de PC
   (`original game` / `arrange game` / `load game` / `special` / `configuration`). "COMEÇAR
   JOGO" (`u=0 v=144`, a célula que o PC usa para `game start`) é o rótulo do atlas cujo
   **sentido** é o de NEW GAME. A alternativa fiel-à-célula está em `alt_celula` no JSON.
2. **`GAME CONFIG` → só "CONFIG".** A célula `0,128,60` do atlas PT **mistura duas fontes**: o
   pacote redesenhou apenas "CONFIG" e deixou "GAME" no desenho original. Renderizado junto fica
   visivelmente quebrado (conferido em `port/_boot_menu.png` antes da correção). "CONFIG"
   sozinho é exatamente a célula que `title_mapping.xml` declara para `configuration`.
   **Não existe variante PT-BR de "GAME CONFIG" inteiro no pack.**
3. **Copyright.** O bloco de DUAS linhas que o PS1 usa (`0,160,208×16`) está **vazio** no atlas
   PT. A única linha de copyright disponível é a de `v=120`, e é a que o port desenha.

### 3.2 O que NÃO tem contrapartida em HD/PT-BR

- **`PRESS ANY BUTTON`** (célula do PS1 `0,0,168×12`): em `v=0` o atlas PT tem o copyright da
  Gold Edition. A versão de PC não usa essa tela. **Não escalei o SD** — o port simplesmente
  não desenha esse rótulo, e isso está registrado no JSON (`sem_hd_pt`).
- **`INFORMATION`, `RESULT`, `SAMPLE`, `EASY MODE`/`HARD MODE` (linha `v=176`)**: existem no
  atlas PT mas **em inglês** — o pacote não os traduziu.
- **O atlas do título não tem versão HD em inglês** entre os 14 blocos 1024² de `hires/misc`
  (só russo e português; os outros 12 são páginas de fonte em cores variadas).

### 3.3 Comportamento do item selecionado (medido, reproduzido)

`0x80194d48`: **selecionado = opaco com `rgb` pulsante; não selecionado = semitransparente com
`rgb` 128**. No PS1 a primitiva faz `tex · rgb / 128`, então 128 é neutro — no port isso é
`modulate = rgb/128` (chega a 1,33 no pico) e alpha 0,5 para o semitransparente.

O pulso (`0x80195564`): `ctx[0x0f] += 4` por tick e `ctx[0x0e] = (s8)tab[ctx[0x0f]]/3 − 0x80`,
com `tab` = a tabela seno de 256 bytes assinados de **`0x80098828`**. `tools/boot_assets.py`
**lê os 256 bytes do EXE** e emite os 64 valores do ciclo: amplitude `[−127, 127]`, resultado
**86…170**, período **64 ticks** — exatamente o que `menu_titulo.md` §3.1 afirma, agora
reproduzido em vez de citado.

---

## 4. Legenda dos FMV em PT-BR: a marcação do mod

Fonte: `mod_BH3_Portuguese/xml/prologue.xml` (abertura) e `epilogue.xml` (final), do pacote
PT-BR já aplicado na instalação. XML `<Strings><Text>…</Text></Strings>` com BOM UTF-8, um
`<Text>` por bloco de narração, com marcação de tempo **em quadros**.

### 4.1 O que está PROVADO

As diretivas são do motor **Classic REbirth**. A lista completa está no `ddraw.dll` da
instalação como **oito formatos `printf`**, em offsets de arquivo consecutivos:

```
0x2fe138  "snd %d"      0x2fe140  "cut %d"     0x2fe150  "string %d"
0x2fe15c  "color %d"    0x2fe168  "scroll %d"  0x2fe174  "branch %d"
0x2fe180  "clear %d"    0x2fe18c  "timed %d"
```

(`Strings` em `0x2fd11c`, `Text` em `0x2a0b80`, `xml\prologue.xml` em `0x2fedd0`.)
Logo: **são essas oito, todas com um inteiro, com essa grafia.** Fato verificável.

### 4.2 O que é LEITURA (declarado)

A semântica **não** saiu do código de máquina. Lendo o texto como fluxo de tokens, a única
interpretação auto-consistente é:

| diretiva | leitura |
|---|---|
| `{scroll N}` | abre o bloco (N = 0 nos dois arquivos) |
| texto | acumula no buffer da tela; `\n` = quebra de linha |
| `{clear N}` | segura o buffer por **N quadros** e depois **limpa** |
| `{timed N}` | segura por **N quadros** e **encerra** o bloco (é sempre o último) |

Três coisas sustentam a leitura:

1. **Posição.** `{clear}` só aparece entre pedaços de texto e `{timed}` só no fim de cada
   `<Text>` — nos 4 blocos do prólogo e no 1 do epílogo, sem exceção.
2. **O primeiro `{clear}` vem depois de um `\n` sozinho** (`{scroll 0}\n{clear 34}`), isto é,
   sobre buffer VAZIO: 34 quadros de tela em branco = o atraso antes de a narração começar.
3. **A soma fecha dentro do vídeo.** Prólogo = **1414 quadros = 47,18 s a 29,97 fps** contra
   **90,624 s** de `opn.mp4` (medido por `ffprobe`). A 59,94 fps daria 23,6 s e sobrariam 67 s
   de vídeo sem legenda. Epílogo = 1431 quadros = 47,75 s contra 62,66 s de `enda.mp4`.

> **⚠ ALVO CORRIGIDO E IMPLEMENTADO (§11.3).** A conta acima ("cabe no `opn.mp4`") ficou
> obsoleta: `prologue.xml` legenda o **PRÓLOGO**, não o `opn`. O que fecha isso é o script do
> prólogo (§11): **4 blocos `<Text>` contra 4 trechos de narração**, **1414 quadros de
> marcação contra 1395 de espera (1,4 %)** e **a soma dos trechos = 46,55 s contra 46,567 s
> de `main06.ogg`**. `tools/legendas_fmv.py` agora grava as cues sob a chave `prologo` e
> `present/prologo.gd` as desenha; o `opn.ogv` toca sem legenda (ele é **dublado**).

**EM ABERTO:** o instante ABSOLUTO de cada bloco. Não há timestamp nos arquivos; a única leitura
disponível é **sequencial**, e é o que o port usa. `{snd}`, `{cut}`, `{string}`, `{color}` e
`{branch}` **não aparecem** nestes dois arquivos e **não** foram decodificados.

**Alvo do epílogo — declarado:** casei `epilogue.xml` com `enda` por duração (47,8 s de fala em
62,66 s). `endb.mp4` tem 62,70 s e serviria igual. **Não medi** qual dos dois finais o motor
legenda.

### 4.3 Trema onde deveria haver til (correção declarada)

O XML escreve `destruiçäo`, `näo`, `perdäo`, `operaçäo`, `situaçäo`, `entäo` — **trema no lugar
do til**. Não é escolha do tradutor: o `encoding.xml` do próprio mod tem `ã` (código `0x58`) e
`ä` (`0x9F`) como entradas SEPARADAS, e as palavras são português corrente com til. O port
corrige `ä→ã` / `Ä→Ã` e guarda o texto cru ao lado (`linhas_cru` no JSON). **DECLARADO:
correção do port sobre o dado do mod, não medição.**

### 4.4 Como a legenda é desenhada

Com a **fonte do jogo** (`present/texto.gd`, atlas HD europeu, os acentos funcionam), com a
**sombra preta em (+1,+1)** — que é a convenção do próprio RE3: os `SPRT` do ramo Mercenaries
de `TITLE.BIN` (`0x80194894`+) desenham cada rótulo duas vezes, a cópia em `rgb=0` deslocada
em (+1,+1). Cada `\n` do XML é uma linha; se estourar a largura, `Texto.quebrar` reparte por
palavra (é o que o desenho do jogo faz).

**DECLARADO:** a POSIÇÃO da legenda na tela. Não medi onde a versão de PC desenha o prólogo. O
port usa o rodapé do espaço 320×240, centralizado, com margem de 24 px.

---

## 5. Vídeo: por que Ogg Theora, e o custo

O `VideoStreamPlayer` do Godot 4 tem **um** backend embutido: **Theora**. Os três caminhos:

| caminho | custo |
|---|---|
| **(a) transcodificar mp4 → ogv** ✅ escolhido | Theora rende pior que H.264 e o `libtheora` do ffmpeg é **monothread**. **Medido:** `opn` (90,62 s, 2716 quadros, 1280×960) levou **~19 min** de encode (≈12× o tempo real) e saiu com **77 MB** contra 135 MB do mp4, em `-q:v 8`. Custo de pipeline, pago uma vez. |
| (b) GDExtension (ffmpeg/libvlc) | Sem perda, mas exige compilar e distribuir binário nativo por plataforma. Custo alto e recorrente. |
| (c) sequência de imagens + áudio separado | 2716 WebP de 1280×960 ≈ 400 MB só na abertura, mais sincronizar áudio à mão. Pior em tudo. |

Como o port já é 1280×960 e os mp4 do pacote PT-BR são **exatamente 1280×960 h264 29,97 fps**,
(a) mantém resolução, taxa e faixa de áudio **sem reescalar nada**.

**Sondado, não suposto:** `VideoStreamTheora.file` aceita **caminho absoluto**, então o `.ogv`
é lido de FORA do `.pck` — essencial, porque `port/assets/` tem `.gdignore` (política P7-06).
`port/dev/diag_video.gd` mostra `playing=true` e a posição andando, **inclusive em
`--headless`**.

### 5.1 Áudio: dublado em PT-BR (com uma ressalva honesta)

`docs/formatos/localizacao_ptbr.md` §3 registra que os 14 mp4 vêm do pacote "Edição Definitiva
Dublado" e são **upscalados e dublados em PT-BR**, e que **não há trilha EN** neles. Medi por
`ffprobe`: todos têm **1 faixa AAC estéreo 48 kHz** e a etiqueta de idioma do contêiner diz
`eng` nos 14 — **etiqueta ≠ conteúdo** (é o valor default do encoder MainConcept). As datas dos
arquivos (jun/2025) são as do conjunto PT. **Eu não tenho como OUVIR**: registro como
não verificado por audição. FMV em inglês exigiria o `.dat` do PC ou o `.STR` do PS1.

---

## 6. Onde ficou cada coisa

| arquivo | papel |
|---|---|
| `tools/boot_assets.py` | copia as 5 telas HD/PT + `INIT_TBL.DAT`; emite `data/boot_flow.json` (tempos, sprites, de-para de rótulo, tabela do pulso lida do EXE) |
| `tools/legendas_fmv.py` | decodifica `prologue.xml`/`epilogue.xml` → `data/legendas_fmv.json` |
| `tools/video_ogv.py` | mp4 → ogv com o ffmpeg do projeto; `--listar` inventaria |
| `port/present/boot.gd` | a máquina de passos, os dois slots de fade, o pulo, o `INIT_TBL`, a saída para o jogo |
| `port/present/titulo.gd` | menu navegável (3 itens + dificuldade), pulso, desenho HD/PT |
| `port/present/video.gd` | `VideoStreamPlayer` + legenda sincronizada (a legenda agora é do prólogo) |
| `port/present/prologo.gd` | a VINHETA: interpreta o script de `OPENING1.DAT` (§11) |
| `port/dev/diag_clique_titulo.gd` | sonda do mouse no título (hover + um clique), pelo evento |
| `port/dev/diag_som_boot.gd` | sonda do som: qual WAV/`.ogg` o `Sfx`/`Audio` escolheu |
| `port/scenes/boot.tscn` | a cena |
| `port/dev/tests/test_boot.gd` | 267 asserts |
| `port/dev/shot_boot.gd` | screenshot por fase (validação visual) |
| `port/dev/diag_video.gd` | sonda do `.ogv` fora do `.pck` |

### 6.1 Como reproduzir

```bash
# telas HD/PT-BR + tempos + de-para de rótulos + INIT_TBL.DAT
NOSTALGIA_OUT=port python tools/boot_assets.py --medir
NOSTALGIA_OUT=port python tools/boot_assets.py --verificar   # relê a tabela seno do EXE

# legendas (linha do tempo no console)
NOSTALGIA_OUT=port python tools/legendas_fmv.py --mostrar

# vídeo da abertura (leva ~20 min; --todos leva ~1 h)
NOSTALGIA_OUT=port python tools/video_ogv.py --listar
NOSTALGIA_OUT=port python tools/video_ogv.py --abertura

# ou tudo pelo build
python tools/build_assets.py --out port --only boot,fmv

# teste (filtro obrigatório: a suíte inteira leva ~7 min)
godot --path port --headless --script res://dev/run_tests.gd -- boot

# rodar a cena / capturar uma fase
godot --path port res://scenes/boot.tscn
BOOT_FASE=menu BOOT_CURSOR=0 godot --path port --rendering-driver opengl3 \
    --script res://dev/shot_boot.gd
BOOT_FASE=fmv BOOT_FMV_T=21 godot --path port --rendering-driver opengl3 \
    --script res://dev/shot_boot.gd
# prova a última perna: o boot TROCA para game.tscn e a captura sai dentro da R10D
BOOT_FASE=jogo BOOT_ENTRAR=1 godot --path port --rendering-driver opengl3 \
    --script res://dev/shot_boot.gd
```

Verificado assim: a captura de `BOOT_FASE=jogo BOOT_ENTRAR=1` sai com a HUD
`sala R10D  câmera 1/13 (attr 29623, fov 54.8)` e a Jill em `PS1(9404, 0, -13317)` —
ou seja, `boot.tscn` → `game.tscn` → sala inicial, sem passo intermediário manual.

---

## 7. O REPRODUTOR DE FMV — a tabela `0x8009ca64` (achado desta rodada)

Ponto de partida: **o `SLUS_009.23` não tem decodificador MDEC**. Varri os registradores
`0x1f801820`/`0x1f801824` nos dados e **todos** os 17 `lui rX, 0x1f80` do código (são
scratchpad `0x1f800000` e libgpu `0x1f801814`); nos 17 overlays, zero. Então o filme não é
tocado por nenhum `.BIN` — é uma **tarefa do EXE**:

| Endereço | Papel | Como se prova |
|---|---|---|
| `0x800321c4` | **`filme_prepara(a0 = índice)`** — o ÚNICO ponto de entrada | `0x800321f0` monta `rec = 0x8009ca64 + a0*0x18` (`sll 1; addu; sll 3` = ×24) |
| `0x80032478` | `0x800cc858 \|= 0x18000` | `lui a1,1; ori a1,0x8000` + `or`/`sw` |
| `0x800324a0` | tick do filme, no laço de quadro | `jal 0x800324a0` em `0x80029370` (único chamador) |
| `0x8009cbb4` | 3 handlers de estado `{0x800325a4, 0x800327a4, 0x80032ad4}` | `0x800324e8` `lw` indexado por `*(u8*)0x800dcd9c` |
| `0x80032638` | volume do filme | `lhu 0x12(ctx)` → `0x8003331c` |
| `0x80032644` | liga a entrada de **CD/XA no SPU a `0x7fff`** | `0x80074658(1)` → `SpuSetCommonAttr` `0x8007f198` |

A tabela começa **exatamente onde termina a de overlays** (`0x8009c944 + 24 × 12 =
0x8009ca64`) e tem **14 registros de 24 bytes**:

| off | tipo | conteúdo | prova |
|---|---|---|---|
| `+0x00` | u32 | **índice de arquivo do `.STR`** | os valores são `0x53a…0x546`, e na tabela de arquivos `0x800946a4` esses são os **únicos 13 registros com `flags = 0xff`**; os LBA batem 1:1 com o índice do jPSXdec (`tools/re3.idx`) |
| `+0x04` | u16 | **quadros a tocar** | é `(quadros do jPSXdec) − 5` em **13/13** vídeos |
| `+0x06` | u16 | `0x00ff` em 14/14 | **NÃO DECODIFICADO** |
| `+0x08` | u16 | `0x0900`/`0x0100`/`0x0000`/`0x09f0` → `ctx+0x24` | **NÃO DECODIFICADO** (`0x8003247c`) |
| `+0x0a` | u16 | `0x140` = **320** = largura | `0x8003239c` |
| `+0x0c`/`+0x0e` | u16 | **x = 0, y = 40** | `0x800323b8`/`0x800323c4`; e **40 + 160 + 40 = 240** — o quadro `320×160` do `.STR` centralizado na tela |
| `+0x10` | u16 | acréscimo de endereço do buffer | **NÃO DECODIFICADO** (`0x800322e8`) |
| `+0x12` | u16 | flags: bit `0x200` → buffer `0x80100000`, senão `0x80194000`; bit `0x008` → caminho extra de SPU | `0x80032204` / `0x8003222c` |
| `+0x14` | u16 | **volume 0…127** | `0x80032428`: `vol × *(s16*)0x800e0dda / 127` (magic `0x81020409`, `sra 6` → `2^38/127`) → `0x8003331c` |

### 7.1 Os 14 registros

| idx | `.STR` (PS1) | `.mp4` (pacote HD) | quadros | jPSXdec | vol | `+0x08` | buffer |
|---:|---|---|---:|---:|---:|---|---|
| 0 | `OPN` | `opn` | 1345 | 1350 | 127 | `0900` | `0x80100000` |
| 1..9 | `INS01`..`INS09` | `ins01`..`ins09` | 387…237 | −5 | 127/110 | `0100` | `0x80194000` |
| 10 | `ENDA` | `enda` | 808 | 813 | 127 | `0000` | `0x80100000` |
| 11 | `ENDB` | `endb` | 835 | 840 | 127 | `0000` | `0x80100000` |
| **12** | `ROOPNE` | **`roop`** | **231** | 236 | **90** | `0900` | `0x80100000` |
| 13 | `ROOPNE` | `roop` | **945** | 236 | 100 | `09f0` | `0x80100000` |

O registro **13 é o mesmo `ROOPNE` com 945 quadros = 63,0 s**, isto é ≈ 4 voltas de 231.
É o único cujo `+0x04` não é "jPSXdec − 5", e o único com `+0x08 = 0x09f0` — **leitura, não
medição**: parece o laço longo de atração. Quem o pede é `0x801964bc` (sub 6).

> **`snl` não existe no PS1.** O índice do jPSXdec lista **13** `.STR` em `CD_DATA/ZMOVIE/`
> (`ENDA`, `ENDB`, `INS01..INS09`, `OPN`, `ROOPNE`) e nenhum `SNL`. O `zmovie/snl.mp4`
> (3,31 s) do pacote de PC é extra — não entra no fluxo recompilado. O `ddraw.dll` do
> Classic REbirth tem o de-para de nomes `roop`/`roop_ne`, `enda`/`enda_ne`,
> `endb`/`endb_ne`, `ins06`/`ins06_ne` em `+0x2fe1a0`, o que confirma `roop ≡ ROOPNE`.

### 7.2 Quem pede cada filme

**Do `TITLE.BIN`** (4 sítios, `a0` constante recuperado por back-walk):

| sítio | idx | filme | quando |
|---|---:|---|---|
| `0x801943a4` | `0xc` | **`roop`** | fim do handler 0, **antes** do estado 1. Pulado só no Mercenaries (`0x8019439c` testa o bit `0x80`). `0x801943ac` espera o bit `0x10000` limpar |
| `0x801960e8` | `0` | `opn` | NEW GAME: depois da dificuldade + `INIT_TBL` + `load_overlay_task(1, ovl 5 = OPENING)` |
| `0x801964bc` | `0xd` | `roop` (945 q.) | sub 6 (`0x8019644c`), depois de um fade-out de 12 ticks |
| `0x80196ed8` | `0` | `opn` | sub 11 (`0x80196800`), depois de carregar o OPENING |

**Do `ENDING.BIN`:** `0x8019430c` e `0x80194354`.

**Do script de sala — opcode SCD `0x7a`:** handler `0x80055520`, **2 bytes**
(`0x80055538 lbu a0, 1(PC)` → `jal 0x800321c4` → `PC += 2`). Varredura das 129 salas:

| filme | sala e função |
|---|---|
| `INS01` | `STAGE1/R110` func 3 |
| `INS02` | `STAGE2/R217` funcs 6 e 14 |
| `INS03` | `STAGE1/R11C` func 2 |
| `INS04` | `STAGE2/R215` funcs 18, 20, 21 e 23 |
| `INS05` | `STAGE2/R215` func 52 |
| `INS06` | `STAGE3/R30D` func 8 |
| `INS07` | `STAGE4/R417` func 7 |
| `INS08` | `STAGE4/R415` func 9 |
| `INS09` | `STAGE5/R508` func 4 |

**`R10D` não tem nenhum opcode `0x7a`** (as 49 funções varridas). Consequência para o item
"cutscene in-game" (§8.7): a cinemática da sala inicial **não é FMV**.

---

## 8. ⚠ SETE COISAS QUE ESTAVAM ERRADAS (e o que foi feito)

O dono testou a abertura e apontou sete problemas. O que cada um era, de verdade:

### 8.1 Faltava o vídeo antes do menu — **CORRIGIDO**

Era o `ROOPNE`/`roop`, registro 12 (§7.2). O port ganhou o passo `filme_atracao` entre
`capcom_para_preto` e `titulo_espera`, e `tools/video_ogv.py roop` gerou o `.ogv`
(15,5 s → 9,7 MB em 151 s de encode). Confirmado por render: a captura de
`BOOT_FASE=filme_atracao BOOT_FMV_T=8` sai com o Nemesis, não com preto.

### 8.2 O som do menu — **banco corrigido, BGM confirmada**

`0x801944c0` chama `0x8007809c(a0 = 0, a1 = (0x800cc858 & 0x80) ? 0xb : 1)`. E
`0x8007809c(cat, banco)` resolve `file_index = tab[cat] + banco*2` com a tabela de bases
`0x800110b0` (`04 01 03 01 da 00 d9 00`, passo 4). Conferido contra a tabela de arquivos:

```
cat 0 -> 0x104 = SOUND/C_00.VH   =>  banco 1 -> 0x106 = SOUND/C_01.VH   ✔
cat 1 -> 0x0da = SOUND/A_01.VH   (o `.VB` sai do par: 0x103 / 0x0d9)
```

➜ **a tela de título usa o banco `C_01`, não o `C_00`** (e o Mercenaries usa `C_0B`).
Ressalva honesta: os 5 WAV de UI de `C_01` são **byte-idênticos** aos de `C_00` (comparei os
arquivos extraídos), então o som **audível** é o mesmo — o que muda é a declaração.

**BGM = `main38`, confirmado no índice de arquivo.** `0x801944dc` é
`cd_read_file(0x121, 0x801f7e00, 1, "OPTION BGM")` e `0x121` **é** `SOUND/MAIN38.BGM` na
tabela de arquivos (`MAIN38.VB` = `0x122`). O rótulo de depuração "OPTION BGM" continua
sendo só um rótulo — **eu não consigo conferir de ouvido**. E ela é carregada no estado 1,
ou seja **depois** do filme de atração: é por isso que o port pede a trilha no
`titulo_espera` e não antes.

### 8.3 Itens do menu descentralizados — **CORRIGIDO**

A regra antiga ("centralizar cada rótulo PT no centro do retângulo do `SPRT` original")
produzia, com as larguras medidas no atlas HD:

| item | tinta PT | caixa antiga | caixa nova |
|---|---:|---|---|
| COMEÇAR JOGO | 53 | `[65, 118]` | `[68, 121]` |
| CARREG. JOGO | 53 | `[131, 184]` | `[150, 203]` |
| CONFIG | 28 | `[216, 244]` | `[232, 260]` |

Vãos: **13 e 32 px** antes, **29 e 29** agora. A borda direita volta de 244 para 260.

A regra nova tem **duas âncoras medidas e uma escolha declarada**:

* âncoras = a borda esquerda do 1º `SPRT` e a borda direita do último (`0x801945e4`:
  **68** e **200 + 60 = 260** no menu; **80** e **180 + 54 = 234** na dificuldade);
* **declarado:** os vãos entre os rótulos ficam **iguais**.

`tools/boot_assets.py:layout_rotulos()` calcula e grava `x_tela` em `rotulos_pt`;
`titulo.gd` só lê. Na dificuldade o resultado é `MODO DIFICIL` em x=80 — o **mesmo** x que
`title_mapping.xml` declara para `heavy mode`, o que é uma segunda fonte concordando.

### 8.4 O FMV do NEW GAME começava antes de clicar — **CORRIGIDO, e a causa era o atrator**

O disparo por `escolheu_novo_jogo` já estava no lugar certo. O que tocava o `opn` sem
clique era **o atrator**: o port mandava o timeout de 900 ticks para o FMV.

No original o timeout vai para o **sub 10** (`0x8019566c` grava `ctx[1] = 0xa`), que é a
**demo jogável**: `ETC/PDEMO00/01/02.DAT` (índices `0x41`/`0x42`/`0x43`, 3620 B cada) em
rodízio por `*(u8*)0x800c79af`, carregados em `0x80192000`, tarefa `0x80031bdc`; no fim ele
põe `*(u8*)ctx = 4` (`0x801967e4`) e o handler 4 (`0x801954d0`) carrega o banco de SE da
área e entrega ao jogo. O **sub 11** (`0x80196800`) — o que carrega o OPENING e chama
`filme_prepara(0)` — **não é alcançado pelo timeout**: varri **todas** as escritas em
`ctx+1` dentro do `TITLE.BIN` e nenhuma grava 11.

**DECLARADO:** sem reprodutor de PDEMO, o port repete o **filme de atração** e volta ao
título. O que ele não faz mais é tocar o `opn` — esse é do NEW GAME.

### 8.5 O som do menu continuava durante o vídeo — **CORRIGIDO (declarado)**

`boot.gd` emite `pediu_parar_bgm` ao entrar em qualquer filme e volta a pedir `main38`
quando o fluxo retorna ao título. **DECLARADO:** no binário, `filme_prepara` liga a entrada
de CD/XA no SPU a `0x7fff` (`0x80032644` → `0x80074658(1)`) e ajusta o volume pelo campo
`+0x14`, mas **eu não localizei o sítio que para o SEQ da BGM**. No caminho normal isso nem
aparece: quando o `roop` roda, a `MAIN38` ainda não foi carregada.

### 8.6 Faltava a cutscene depois do vídeo do menu — **IDENTIFICADA, não implementada**

⚠ **Correção grave a este doc e ao `video.gd`:** `OPENING.BIN` (ovl 5) **não é o tocador do
filme** — é um **slideshow de imagens paradas**, o prólogo do RE3. Provas:

* as duas únicas strings do overlay são `OPENING0_DAT` e `OPENING1_DAT`
  (`0x801c2204`/`0x801c2284`: `cd_read_file(0x3d/0x3e, 0x80100000, 0, …)`);
* `ETC/OPENING0.DAT` (457 504 B) = **9 TIM de 8 bpp** (256×256, 128×256, 256×256, 256×240,
  192×240, 256×240, 192×240, 192×192, 192×192) e `ETC/OPENING1.DAT` (307 322 B) = **2 TIM de
  320×240 16 bpp**. Renderizados: `OPENING1[0]` é o **logo da Umbrella sobre uma rua de
  Raccoon City** e `OPENING1[1]` é a **Jill carregando a arma no apartamento**;
* `0x801c22a0` monta **2 × 10 `SPRT`** (`SetSprt 0x8008f6b4`, `GetClut`, `GetTPage`) — é
  desenho de sprite, não blit de vídeo;
* `0x801c2eb4` chama `0x8002fd30(a0 = 0x00b90022, a1 = 0x3000)` = **início de stream de
  áudio (XA)** — a narração do prólogo;
* o overlay sai quando `*(u16*)0x800cc834 & 0x900` (`0x801c2120`), isto é é **pulável**.

Contrapartida HD achada por NCC em miniatura cinza contra os 1316 `hires/bgd`:
**`bgd/CB8189B6.webp` = 0,9998** para a Jill (par verdadeiro) e **`bgd/B6306D2E.webp` =
0,9449** para a rua com a Umbrella. As 9 imagens de 8 bpp casam mal (0,38…0,79) porque são
**recortes** de fotos maiores que o original faz panorâmica — o HD tem a foto inteira.

**Correção da atribuição das legendas.** Este doc (§4.2) dizia que `prologue.xml` legenda o
`opn.mp4`, com a justificativa "a soma cabe no vídeo" (47,18 s de fala em 90,62 s — sobram
43 s sem legenda). O `exe_audio.md` §8, por um caminho independente, mediu um encaixe muito
mais apertado: **`prologue.xml` = 1414 quadros = 47,13 s contra `MAIN06` 46,86 s (0,58 %)** e
**`epilogue.xml` = 1431 = 47,70 s contra `MAIN07` 47,696 s (0,06 %)**. `MAIN06`/`MAIN07`
**não existem no disco do PS1** (lá só há `MAIN33/38/39/3D`) — são a narração de prólogo e
epílogo que a versão de PC guarda como WAV e o PS1 toca por XA. Fecha com o
`0x8002fd30` do `OPENING.BIN`. Some-se que `opn.mp4` **é dublado** e `MAIN06` **não é**
(`localizacao_ptbr.md` §3): o pacote legendou justamente o que ficou em inglês.

➜ **`prologue.xml` legenda o PRÓLOGO (slideshow + narração `main06`), não o `opn.mp4`.**
**✅ FEITO na rodada seguinte (§11):** o slideshow foi implementado, a legenda mudou de dono e
a atribuição deixou de ser "casamento por duração" — virou medida, porque o SCRIPT do prólogo
tem exatamente 4 trechos de narração para os 4 blocos do XML.

**Por que não implementei o slideshow:** faltam a linha do tempo e o movimento. O
despachante é `0x801c2084` sobre `*(u8*)0x8014b02a` (um byte dentro do próprio
`OPENING1.DAT` carregado) com 4 estados em `0x801c2f70`, e as fotos são **panoramizadas**.
Sem medir isso, qualquer duração e qualquer pan seriam invenção.

> **⚠ DUAS CORREÇÕES a este parágrafo, e a linha do tempo agora está MEDIDA (§11).**
> 1. `0x801c2f70` tem **13** entradas, não 4: é a tabela de handlers de um **interpretador de
>    opcodes**, e `*(u8*)0x8014b02a` não é "um estado" — é o **PC de um script de 80 bytes**
>    que mora no fim de `ETC/OPENING1.DAT`.
> 2. Decodificado o script, a linha do tempo inteira (1665 quadros = 55,56 s), os fades, as
>    duas imagens e os 4 trechos de narração são medidos. O que continua não decodificado é
>    só a **panorâmica** (as 3 rotinas por quadro do `op 7`) e **qual das 9 fotos de
>    `OPENING0.DAT`** entra em cada instante — 11,7 s dos 55,6 s.

### 8.7 A cutscene in-game de R10D — **INVESTIGADA: não é FMV**

`R10D.ARD` tem **49 funções de script** e **nenhum opcode `0x7a`** (§7.2) — logo a
cinemática de abertura da sala é **de motor** (script + câmera + animação), como o dono
suspeitava. Não existe arquivo `R10D_2` em nenhum `STAGE*` do disco (só `R10D.ARD/.BIN/
.BSS`) e o `.ARD` traz **um** SCD, então "`R10D_2`" **não é uma variante de arquivo**;
continua sendo informação do usuário, não medida.

Candidatas pelo tamanho e pela mistura de opcodes (as funções longas com `0x47` seguido de
`0x42`/`0x20`/`0x41` — o padrão de "põe entidade em x,y,z" — e com `0x55`/`0x56`/`0x80`/
`0x88`/`0x8e`/`0x8f`): **func 7 (174 instruções), func 13 (99), func 8 (102), func 11 (94),
func 18 (94)**. Nomear qual delas é "a primeira cutscene" exigiria rodar a VM — **não medi**.

---

## 9. EM ABERTO / NÃO MEDIDO nesta rodada

1. **`ETC/INIT_TBL.DAT` (2312 B) continua fechado.** O port carrega e CONFERE o arquivo
   (tamanho + `sha1 bffeebee91922ed9b7171c460d8aba52d0428117`; 419 bytes não-zero), mas o
   layout **não foi decodificado** — o inventário de jogo novo continua vindo do template do
   EXE (`0x800a018c`, já em `GameState.novo_jogo`). Consequência: **a sala e a posição iniciais
   NÃO saem do INIT_TBL**; R10D é informação do usuário e a posição de spawn é a varredura
   registrada em `present/screen.gd`.
2. **Ordem de composição dos dois slots de fade** na entrada do título (§1.2).
3. **Posição de tela da legenda** do prólogo na versão de PC (§4.4).
4. **Instante absoluto de cada bloco de legenda** (§4.2) — só a leitura sequencial.
5. **Qual final o `epilogue.xml` legenda** (`enda` vs `endb`) (§4.2).
6. **Áudio dos mp4 não verificado por audição** (§5.1).
7. **Sítio do pad durante o FMV.** Só o do logo CAPCOM foi medido (`0x8019432c`,
   `0x800cc834 & 0x800`). O aviso legal não lê pad no caminho do `entry`. O `pulo_livre` do port
   é afordância declarada.
8. **`LOAD GAME` e `GAME CONFIG` não abrem tela.** `MEM_CARD.BIN` tem os textos e **zero
   coordenada** (`menu_titulo.md` §5); `OPTION.BIN` não tem **nenhuma** opção medida (§4). O
   port imprime o motivo em vez de inventar a tela.
9. **A demo de atração (`PDEMO00/01/02.DAT`) não existe no port.** ⚠ **Corrigido o texto
   anterior**, que dizia "o original ALTERNA demo jogável e FMV no timeout": o timeout vai
   **só** para a demo (§8.4). O port repete o filme de atração — declarado.
9.1 ~~**O prólogo (slideshow do `OPENING.BIN`) não está no port**~~ — **✅ FEITO (§11)**: o
   script de 80 bytes foi decodificado e o prólogo é o passo `prologo` do `boot.gd`. Continua
   em aberto **só a panorâmica**: as 3 rotinas por quadro do `op 7` (`0x801c2488`,
   `0x801c2618`, `0x801c2788`) e qual das 9 fotos de `OPENING0.DAT` entra em cada instante —
   11,7 s dos 55,6 s do prólogo ficam preto com legenda.
9.2 **A cinemática de motor de `R10D` não está no port** (§8.7): 5 funções candidatas, mas
   qual é a cutscene exige rodar a VM de script.
9.3 ~~**`prologue.xml` está desenhado sobre o `opn.ogv`**~~ — **✅ FEITO (§11.3)**: a legenda
   é do prólogo, e a atribuição virou medida (4 blocos ↔ 4 trechos de narração; 1414 contra
   1395 quadros; 46,55 s contra os 46,567 s de `main06.ogg`).
9.4 **Campos `+0x06`, `+0x08` e `+0x10`** do registro de filme (§7) — não decodificados. E o
   `+0x04 = 945` do registro 13 é leitura ("laço longo"), não medição.
10. **Cursor inicial = 1 (`LOAD GAME`)** segue como o binário diz (`0x801945b4`) e segue
    contra-intuitivo — item §10.2 de `menu_titulo.md`, ainda sem confirmação em emulador.
11. **Mercenários:** os assets (fundo `81AA5030` e todos os rótulos PT do atlas: "COMEÇAR JOGO",
    "RESULT", "SAIR", "EXTRAS", "OS MERCENARIOS", "EPILOGOS", "ESCOLHA A ROUPA") já estão no
    JSON, mas o **ramo do bit `0x80` não foi implementado** — e quem SETA esse bit continua
    desconhecido (§10.3 de `menu_titulo.md`).
12. **A PANORÂMICA do prólogo** (§11.4): as 3 rotinas por quadro e a escolha das 9 fotos de
    `OPENING0.DAT`. É o único pedaço da vinheta que o port não mostra.
13. **Precedência entre a tarefa do OPENING e a do filme** (§11.4): `0x801960d8` cria uma e
    `0x801960e8` prepara a outra, e as duas usam `0x80100000`. A ORDEM na tela (prólogo antes
    do filme) veio do relato do dono + da ordem das chamadas, **não de medição do escalonador**.
14. **Os campos do `op 0x0b`** do script do prólogo: a tabela `0x801c2f68` (offsets u16) e a
    estrutura `0x801c2f3c` — é onde deve estar o de-para trecho → posição no XA.
15. **A "cutscene depois do vídeo do menu"** que o dono pediu continua **não identificada**.
    O que está medido do caminho pós-`opn` é: `0x801960f0` espera o bit `0x10000`, faz um fade
    (`0x8002a35c`) e chama `0x8006d0d8`; nenhum `filme_prepara` a mais e nenhum opcode `0x7a`
    em `R10D` (§7.2). Se ela existir, é cena de MOTOR, como a de §8.7.
16. **`R10D_2`** (§8.7): o dono afirma que `R10D` tem 2 cutscenes e que a primeira roda em
    `R10D_2`. Não existe arquivo com esse nome em nenhum `STAGE*` (só `R10D.ARD/.BIN/.BSS`) e
    o `.ARD` traz **um** SCD com 49 funções. Continua **informação do usuário, não medida** —
    e as 5 funções candidatas por tamanho/mistura de opcodes seguem listadas em §8.7.

---

## 10. ⚠ O DONO JOGOU DE NOVO: mouse, som e alinhamento

### 10.1 BUG: escolher a dificuldade com o MOUSE não iniciava o vídeo — **CORRIGIDO**

Foi o item que mais incomodou, e não era onde parecia. Comecei descartando as suspeitas por
medição, não por leitura de código:

| suspeita | como testei | resultado |
|---|---|---|
| a rota do sinal (clique → `escolheu_novo_jogo` → passo `fmv`) | `port/dev/diag_clique_titulo.gd` empurrando evento de mouse de verdade | **funcionava** — o filme disparava |
| a caixa de acerto estar fora do rótulo | render de `BOOT_FASE=dificuldade` + medição da tinta no PNG | a tinta desenhada e a caixa **coincidem por construção** (as duas usam `x_tela`/`tinta_w`) |
| a posição do ponteiro | ida-e-volta viewport → `to_local` na sonda com janela | caía **dentro** da caixa |

O que estava errado eram **duas coisas de comportamento**:

1. **A regra era de DOIS cliques** (1º destaca, 2º confirma — a regra do inventário, pensada
   para toque). A tela de dificuldade abre com o cursor em `MODO DIFICIL` (`0x80195d04`),
   então quem clicava em `MODO FACIL` via **só o rótulo acender**: escolheu a dificuldade e
   nada aconteceu. Agora **um clique seleciona E confirma** (`Titulo.clicar`), no menu e na
   dificuldade.
2. **O alvo era a caixa de TINTA** — 55×19 no espaço 320×240, e "CONFIG" tem 28 px de tinta.
   Agora `Titulo.caixa_de_clique` reparte a LINHA INTEIRA entre os itens (cada um vale até o
   meio-caminho do vizinho, com 8 px de sobra nas pontas e em Y): nenhum pixel morto.
   **Afordância do port, declarada** — o PS1 não tem ponteiro, não há o que copiar.

Além disso o clique deixou de ser lido por **polling** (`Input.is_mouse_button_pressed` uma
vez por quadro, em `_ler_pad`) e passou a vir do **evento** (`Boot._input`). Três ganhos:
solta-e-aperta no mesmo quadro não se perde mais; a posição vem do próprio evento, sem
consultar o ponteiro do sistema; e `InputEventScreenTouch` (celular) entra pelo mesmo caminho.
O 2º aperto de um duplo clique é **ignorado** de propósito — com um clique confirmando, ele
cairia na tela seguinte e escolheria a dificuldade sem o dono ver a tela.

**HOVER (pedido novo):** `Titulo.pairar(p)` destaca o item sob o ponteiro **sem confirmar**,
com o SFX 4 de cursor e reiniciando o timeout do atrator — o mesmo que o binário faz quando o
cursor anda (`0x801956f4`). O gatilho é o `InputEventMouseMotion`, então a regra "só quando o
ponteiro moveu" (que no menu do jogo precisa do `pad.mouse_dx/dy`) aqui sai de graça: mouse
parado não gera evento e não prende o cursor de quem joga no teclado.

### 10.2 Itens do menu descentralizados — o menu já estava certo; a DIFICULDADE não

Medi no render, não no código. `port/dev/_boot_menu.png`, faixa `y=770..828`, tinta acima do
fundo:

| rótulo | tinta medida no PNG (320) | vão até o próximo |
|---|---|---:|
| COMEÇAR JOGO | 68,75 … 120,75 | **30,25** |
| CARREG. JOGO | 151,00 … 202,50 | **30,25** |
| CONFIG | 232,75 … 259,75 | — |

Vãos **iguais** e a linha ocupando 68,75…259,75, que é a faixa das âncoras do `SPRT`
(`0x801945e4`: 68 e 200+60 = 260). Margem 68,75 à esquerda e 60,25 à direita — a assimetria é
**do original** (68 e 60). Nada a corrigir aqui.

O erro estava na **tela de dificuldade e no copyright**, e apareceu quando li o
`title_mapping.xml` INTEIRO em vez de só as células:

```
<Map x="80"  y="193" w="62" h="13" u="192" v="128"/> <!-- heavy mode -->
<Map x="180" y="193" w="56" h="13" u="128" v="128"/> <!-- light mode -->
<Map x="60"  y="217" w="226" h="8" u="0"   v="120"/> <!-- regular (copyright) -->
```

O `x,y` é de onde vai a **CÉLULA**, e a tinta dentro dela começa em `tinta_x` (6, 6 e 18):

| rótulo | o port desenhava | o pacote manda | erro |
|---|---:|---:|---:|
| MODO DIFICIL | 80 | **86** | 6 px |
| MODO FACIL | 189 | **186** | 3 px |
| copyright (y) | 213 | **217** | 4 px |

E o `y=217` do copyright não é arbitrário: **213 + (16 − 8)/2**, isto é a linha PT de 8 px
CENTRADA no bloco de duas linhas (16 px) que o PS1 usa. Duas fontes, mesmo número — é o que
autoriza usar o XML como posição, e não como palpite.

`tools/boot_assets.py` agora **lê o arquivo** (`ler_title_mapping`), **confere** que
`u,v,w,h` do XML batem com a célula gravada no de-para (bate em **6 de 6**) e usa `x + tinta_x`
para a dificuldade e para o copyright. Para os 3 itens do menu o XML **não serve**: os `x` dele
(8, 88, 158, 231, 282) são da linha de **cinco** itens da versão de PC (`original game`,
`arrange game`, `load game`, `special`, `configuration`), tela que o PS1 não tem — ali continua
valendo a regra de vãos iguais entre as âncoras medidas (declarada).

### 10.3 Som do menu — o banco estava certo no doc e ERRADO no código

O de-para já estava provado em [`exe_audio.md`](exe_audio.md) §5.1 (4 mover, 5 cancelar,
6 confirmar; amostras `C_00_02/03/04`) e o banco medido é o **`C_01`** (§8.2). Só que o
`boot.gd` chamava `Sfx.tocar_id(0, id)` **sem o banco**, e `Sfx._banco_de(0)` devolve
`_banco_area` se uma sala já tiver sido carregada, senão o `banco_padrao` do JSON, que é
`C_00`. Sondei com `port/dev/diag_som_boot.gd`:

```
[som] banco de area (cat 0) no boot, vazio = cai no padrao C_00:
[som] mover cursor  -> SE = C_00/C_00_02.wav      (antes)
[som] mover cursor  -> SE = C_01/C_01_02.wav      (depois)
```

Agora o banco vai explícito. **Ressalva honesta mantida:** conferi com `cmp` que os 5 WAV de
UI de `C_01` são **byte-idênticos** aos de `C_00`, então o som audível não mudou — o que mudou
é o port passar a tocar o banco que o binário carrega, em qualquer ordem de cena.

**A BGM é a `main38`, e agora com uma terceira fonte.** Além do índice de arquivo (`0x121` =
`SOUND/MAIN38.BGM`, lido em `0x801944dc`) e da chamada que toca a sequência
(`0x800782f4(0, 0x38, …)`), a instalação de PC tem `SOUND/MAIN38.WAV` — o **mesmo número no
mesmo lugar** — que `tools/audio_gog.py` converte para `BGM/gog/main38.ogg`, **20,25 s**
(ffprobe), duração de tema de tela de título. O que continua sem verificação é o **ouvido**.

**Engate que sobrou (não é meu arquivo):** os descritores de SE trazem `tom_vol` — 55 para o
id 4 (cursor), 85 para o 5 e 90 para o 6, de 127 — e `core/sfx.gd` toca tudo no mesmo volume.
Se o som de menu ainda soar forte, é isso: falta o `tom_vol` no `tocar_id`.

---

## 11. A VINHETA: o prólogo é um SCRIPT, e o script está dentro do arquivo de imagem

`BIN/OPENING.BIN` (overlay 5, base **0x801c2000**, 4756 B) **não é tocador de nada**: é um
**interpretador de 13 opcodes**. O programa que ele roda são **80 bytes no fim de
`ETC/OPENING1.DAT`** — o arquivo de imagem.

```
0x801c2024  entry -> 0x801c2160 (init) -> laço do despachante
0x801c21a0  lui v1,0x8014 ; ori v1,0xb02a          -> PC = 0x8014b02a
0x801c21b8  sw  v1, 0x244(ctx = 0x801c3048)
0x801c2084  v0 = *(u8*)PC ; v0 <<= 2 ; jalr *(0x801c2f70 + v0)   <- despachante
0x801c21e4  cd_read_file(0x3d = OPENING0.DAT, 0x80100000) ; 9 TIM -> VRAM (0x800784e0)
            cd_read_file(0x3e = OPENING1.DAT, 0x80100000)
```

`OPENING1.DAT` é lido em `0x80100000`, logo `0x8014b02a` é o **offset `0x4b02a`** do arquivo,
que tem `0x4b07a` bytes: os 80 bytes finais. O arquivo é **2 TIM de 320×240 16 bpp**
(`0x0` e `0x25814`, blocos de 153 612 B = 12 + 320·240·2) e o script vem depois. Os 80 bytes,
lidos do disco do usuário por `tools/boot_assets.py`:

```
0c 01 07 00 0a 00 03 04 1e 00 08 3c 0b 00 03 04 04 01 09 3c 03 04 3c 00
06 00 08 3c 0b 01 03 04 d7 00 09 3c 03 04 3c 00 0c 02 07 01 08 3c 0b 02
03 04 58 02 09 3c 03 04 3c 00 0c 01 06 01 08 3c 0b 03 03 04 40 01 09 3c
03 04 3c 00 05 02 01 00
```

### 11.1 Os 13 opcodes (cada um com o handler que o prova)

| op | nome | bytes | handler | o que faz |
|---:|---|---:|---|---|
| `00` | nop | 1 | `0x801c2b38` | PC += 1; devolve 1 |
| `01` | fim | 2 | `0x801c2b50` | devolve 0 |
| `02` | encerra | 1 | `0x801c2b68` | devolve 2 → o laço sai (`0x801c20b4`) |
| `03` | timer | 1 | `0x801c2b80` | `ctx+0x248` = u16 em PC+2, **DOBRADO se o divisor de quadro `*(u8*)0x800d442c` == 1** |
| `04` | espera | 3 | `0x801c2bd4` | decrementa `ctx+0x248` e devolve 0 até zerar; então PC += 3 |
| `05` | espera_som | 1 | `0x801c2c04` | segura enquanto `0x800d1f2c & 0x20` ou `!(0x800dbb58 & 0x80)` |
| `06` | imagem | 2 | `0x801c2c4c` | copia `0x25814` B (uma imagem inteira) de `*(0x801c2f0c + arg*4)` para `0x8019c000` |
| `07` | rotina de desenho | 2 | `0x801c2cbc` | `ctx+4 = arg` → escolhe `0x801c2488` / `0x801c2618` / `0x801c2788` |
| `08` | fade-in | 2 | `0x801c2d0c` | `0x8002a35c(abr=2, 0xffffff→0x000000, T = arg)` |
| `09` | fade-out | 2 | `0x801c2d8c` | `0x8002a35c(abr=2, 0x000000→0xffffff, T = arg)` |
| `0a` | pede recurso | 2 | `0x801c2e0c` | `0x80011df4(3, arg + 0x13)` e liga `0x800d1f2c & 0x20` |
| `0b` | narração (XA) | 2 | `0x801c2e70` | `0x8002fd30(0x00b90022, 0x3000, 0x801c2f3c + *(u16*)(0x801c2f68 + arg*2), 0)` |
| `0c` | divisor de quadro | 2 | `0x801c2ee0` | `*(u8*)0x800d442c = arg` (1 = 59,94 Hz, 2 = 29,97) |

**A unidade é quadro de 29,97 Hz.** O `op 3` dobra o valor quando o divisor vale 1
(`0x801c2b9c`: `lh` + `sll 1`) e o `op 0x0c` troca o divisor entre 1 e 2 no meio do prólogo —
as duas coisas juntas dizem que o autor escreveu tudo em quadros de 30 Hz e o motor converte
para ticks de vsync. No port, 1 quadro = **2 ticks** do `boot.gd`.

### 11.2 A linha do tempo (1665 quadros = 55,56 s)

| quadro | script | na tela |
|---:|---|---|
| 0 | `0c 01` `07 00` `0a 00` espera 30 | preto |
| 30 | fade-in 60, **narração 0**, espera 260 | fotos de `OPENING0` com panorâmica (**não decodificado**) |
| 290 | fade-out 60, espera 60 | — |
| 350 | **`06 00`**, fade-in 60, **narração 1**, espera 215 | Umbrella sobre a rua de Raccoon City |
| 565 | fade-out 60, espera 60 | — |
| 625 | `0c 02` `07 01`, fade-in 60, **narração 2**, espera 600 | mesma imagem, outra rotina de desenho |
| 1225 | fade-out 60, espera 60 | — |
| 1285 | `0c 01` **`06 01`**, fade-in 60, **narração 3**, espera 320 | Jill carregando a arma no apartamento |
| 1605 | fade-out 60, espera 60 | — |
| 1665 | `05 02` `01 00` | espera o som acabar e ENCERRA |

As duas imagens do `op 6` são `OPENING1.DAT` TIM[0] e TIM[1]. Decodifiquei os dois TIM e
comparei a olho com os HD de §8.6: **TIM[0] = `bgd/B6306D2E.webp`** (a rua com a Umbrella) e
**TIM[1] = `bgd/CB8189B6.webp`** (a Jill), na mesma ordem. É essa a contrapartida em HD que o
port desenha (`assets/BOOT/prologo0.webp` e `prologo1.webp`).

### 11.3 A narração e a legenda: três medidas, e a legenda muda de dono

Os **4** trechos de `op 0x0b` duram o que a espera seguinte diz: **260, 215, 600 e 320**
quadros = **1395** = **46,55 s** a 29,97 Hz.

| medida | valor | contra | diferença |
|---|---:|---|---:|
| soma dos 4 trechos de narração | 1395 quadros (46,55 s) | `BGM/gog/main06.ogg` = 46,567 s (ffprobe) | **0,03 %** |
| blocos `<Text>` de `prologue.xml` | 4 | trechos de `op 0x0b` | **igual** |
| quadros de marcação de `prologue.xml` | 1414 | 1395 de espera | **1,4 %** |
| pausa em branco do XML (cue 4) | 284…329 | fade-out + espera do script (290…350) | cai no mesmo lugar |

➜ **`prologue.xml` legenda o prólogo.** O `opn.mp4` tem 90,62 s e é **dublado** em PT-BR
(`localizacao_ptbr.md` §3): o pacote legendou justamente o que ficou em inglês, que é a
narração `main06`. `tools/legendas_fmv.py` grava as cues sob a chave **`prologo`**, e o
`opn.ogv` passa a tocar **sem** legenda.

### 11.4 O que o port faz, e o que é escolha declarada

`port/present/prologo.gd` interpreta o script vindo de `boot_flow.json.prologo` (nenhum número
digitado à mão: `tools/boot_assets.py` lê os 80 bytes do arquivo do usuário), desenha as duas
imagens em HD, roda os fades com o mesmo `ColorRect` + `BLEND_MODE_SUB` que reproduz o `abr=2`
do PS1, pede a narração no 1º trecho e desenha a legenda com a fonte do jogo. É pulável, o que
é **medido**: `0x801c2120` testa `*(u16*)0x800cc834 & 0x900`.

Três coisas são **declaradas**, e nenhuma é invenção de número:

1. **Os primeiros 11,7 s ficam sem foto.** As 9 fotos de `OPENING0.DAT` vão para a VRAM no
   init (`0x801c2224`, `0x801c225c`) e são desenhadas **com panorâmica** pelas três rotinas
   por quadro que o `op 7` escolhe (`0x801c2488`, `0x801c2618`, `0x801c2788`) — que eu **não
   decodifiquei**. Qual foto entra em cada instante também não. Em vez de inventar foto e
   movimento, o port deixa preto com a legenda até o `op 6` (quadro 350). São 11,7 s de 55,6.
2. **A narração toca corrida.** O original toca 4 trechos com 60 quadros de fade entre eles;
   o `Audio` do port não tem busca, então a `main06` toca de uma vez a partir do 1º trecho. A
   legenda usa o **relógio da narração** (não o do script), então texto e voz ficam casados; o
   que desanda em relação ao original é a troca de foto, que segue o script.
3. **A ordem prólogo → filme.** `0x801960d8` cria a tarefa do OPENING e `0x801960e8` chama
   `filme_prepara(0)` um tick depois; o TITLE então espera **o filme** (`0x801960f0`, bit
   `0x10000`) e não a tarefa do prólogo. Como os dois usam `0x80100000` como buffer, eles não
   podem estar no ar ao mesmo tempo — e o dono descreve a vinheta ANTES do vídeo. O port faz
   prólogo e depois filme. **Não medi o mecanismo de precedência entre as duas tarefas.**

### 11.5 Como conferir

```bash
NOSTALGIA_OUT=port python tools/boot_assets.py            # copia prologo0/1 + decodifica o script
NOSTALGIA_OUT=port python tools/legendas_fmv.py --mostrar  # a legenda agora e' do `prologo`
BOOT_FASE=prologo BOOT_QUADRO=1350 godot --path port --rendering-driver opengl3 \
    --script res://dev/shot_boot.gd      # captura a vinheta no quadro pedido
godot --path port --headless --audio-driver Dummy --script res://dev/diag_som_boot.gd
godot --path port --rendering-driver opengl3 --audio-driver Dummy \
    --script res://dev/diag_clique_titulo.gd   # hover + um clique, pelo evento de verdade
```
