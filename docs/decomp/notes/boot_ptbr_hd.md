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
> `port/scenes/boot.tscn`. **Teste:** `port/dev/tests/test_boot.gd` (131 asserts).
> **Sondas:** `port/dev/diag_video.gd`, `port/dev/shot_boot.gd`.

---

## 1. O que a cena faz

```
aviso legal (5,01 s)  ->  logo CAPCOM (4,00 s)  ->  TÍTULO navegável
   ->  dificuldade  ->  ETC/INIT_TBL.DAT  ->  FMV opn (90,6 s, legenda PT-BR)  ->  R10D
```

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
| `titulo_espera` | 6 | `0x80194b08` sub1 (`ctx+0x14` = 160, −30 por chamada) | 0,10 |
| `titulo_flash` | 5 | `0x80194b08` sub1, `fade(T=5)` `abr=1` | 0,08 |
| `titulo_fade_in` | 60 | `0x80194b08` sub2, `fade(T=0x3c)` `abr=2` | 1,00 |
| **até o menu** | **611** | | **10,19** |
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
| `port/present/video.gd` | `VideoStreamPlayer` + legenda sincronizada |
| `port/scenes/boot.tscn` | a cena |
| `port/dev/tests/test_boot.gd` | 131 asserts |
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
```

---

## 7. EM ABERTO / NÃO MEDIDO nesta rodada

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
9. **A demo de atração (`PDEMO00/01/02.DAT`) não existe no port.** O original alterna demo
   jogável e FMV no timeout; o port só tem o FMV.
10. **Cursor inicial = 1 (`LOAD GAME`)** segue como o binário diz (`0x801945b4`) e segue
    contra-intuitivo — item §10.2 de `menu_titulo.md`, ainda sem confirmação em emulador.
11. **Mercenários:** os assets (fundo `81AA5030` e todos os rótulos PT do atlas: "COMEÇAR JOGO",
    "RESULT", "SAIR", "EXTRAS", "OS MERCENARIOS", "EPILOGOS", "ESCOLHA A ROUPA") já estão no
    JSON, mas o **ramo do bit `0x80` não foi implementado** — e quem SETA esse bit continua
    desconhecido (§10.3 de `menu_titulo.md`).
