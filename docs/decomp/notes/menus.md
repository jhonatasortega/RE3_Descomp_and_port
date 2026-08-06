# Menus / telas de sistema (unidade `menus`)

> **STATUS** (fonte: `../progress.json` → unidade `menus`, hoje 0%)
> - **Formato:** overlays MIPS (`CD_DATA/BIN/*.BIN`) que carregam gráficos **TIM** externos de `CD_DATA/ETC/`.
> - **Ferramenta:** [`tools/menu_extract.py`](../../../tools/menu_extract.py) (Python puro; reusa `tim2png.py`).
> - **Saída:** `godot/assets/MENU/<tela>/*.png` (80 PNG) + `godot/assets/MENU/catalog.json`.
> - **HD (bônus):** 30 backgrounds HD casados por conteúdo (NCC) do Seamless HD Project → `godot/assets/MENU/<tela>/hd/*.webp`.
> - **Provado:** bytes→imagem (TITLE = "RESIDENT EVIL 3 NEMESIS", WARNING = aviso legal, DIEDEMO = "YOU DIED", CAPCOM logo, etc.).

## 1. Os `BIN/*.BIN` NÃO são os gráficos — são overlays de código

Ao contrário dos contêineres de sala `STAGE#/R###.BIN` (ver [`bin2gltf.py`](../../../tools/bin2gltf.py)),
os arquivos de menu em `CD_DATA/BIN/` são **overlays executáveis do PS1**. Layout:

```
+0x00  u32   N          número de ponteiros da tabela de dispatch
+0x04  u32[N]           ponteiros já relocados p/ a RAM (0x8018xxxx..0x801Cxxxx)
...                     código MIPS + strings de rótulo + relocação
```

Prova: `u32[0]` é pequeno (0x36–0x45) e **não** é o tamanho do arquivo; os campos seguintes são
endereços KUSEG do PS1 (`0x8019xxxx`, `0x801Cxxxx`); e há código MIPS reconhecível
(`27bde0.. = addiu sp,sp,-N`) além de strings como `MEMORY CARD BG`, `OMBG.TIM`, `DIEDEMO.TIM`.

O scan estrutural por TIM dentro dos BIN retorna **0** (os `10 00 00 00` são só instruções/constantes
do código — reprovam a validação de bloco CLUT/imagem). **Os gráficos de cada tela ficam em `CD_DATA/ETC/`**;
o overlay os referencia pelo **nome** (strings de rótulo no próprio código) e os envia p/ a VRAM.

## 2. Formato dos gráficos: TIM (padrão PS1), possivelmente concatenados

Os assets de ETC são **TIM** padrão (`10 00 00 00` + flag bpp + blocos CLUT/imagem). Validador
(`menu_extract.parse_tim`): magic + `flag & ~0x0B == 0`; se tem CLUT, `blen == 12 + ncol*npal*2`;
bloco de imagem `blen == 12 + iw*ih*2`. Isso descarta os falsos positivos do código.

- Arquivos de **153620 bytes** = um TIM 16bpp **320×240** de tela cheia (header 20 + 320·240·2).
- Os `*.DAT` (TITLEU, OPTIONU, STR_BG, STAFF_U, OPENING0/1, EPIS_U, OMBG_U) são **vários TIMs
  concatenados** (frames/camadas/páginas de VRAM). Ex.: `STAFF_U.DAT` = 13 TIMs; `OPTIONU.DAT` = 5.
- bpp por asset: full-screens de fundo em **16bpp**; atlas de objetos/fontes em **8bpp** (npal 1–4)
  ou **4bpp** (npal 1–2). Telas com múltiplas CLUTs = estados/idioma (renderizamos até 4 paletas).
- Sufixo `J`/`U` = idioma (JP / NTSC-U). Usamos os **`U`** para o alvo NTSC-U.

## 3. Uso da ferramenta

```
python tools/menu_extract.py scan  <arq.TIM|.DAT|.BIN>   # lista TIMs válidos
python tools/menu_extract.py dump  <arq> <outdir>        # extrai PNGs de 1 arquivo
python tools/menu_extract.py menu  [godot/assets/MENU]   # extrai TODAS as telas + catalog.json
python tools/menu_extract.py hdmatch [godot/assets/MENU] # (bônus) casa telas full-screen c/ hires do GOG
```

## 4. Catálogo BIN → tela → assets (NTSC-U)

Ligação obtida das **strings de código** de cada overlay (o rótulo do arquivo que ele carrega).

| Overlay (`BIN/`) | Tela | Assets `ETC/` | Render conferido |
|---|---|---|---|
| `TITLE.BIN` | 01_title | `TITLEU.DAT` (3 TIM), `CAPCOM.TIM` | "RESIDENT EVIL 3 / NEMESIS"; logo CAPCOM |
| `JILL_SEL.BIN` | 02_jill_select | `JILL_BGU.TIM`, `JILL_OBU.TIM` (2 pal) | beco/rua (fundo); sprites/painel |
| `SELECT.BIN` | 03_game_select | `SELE_BGU.TIM`, `SELE_OBU.TIM` (3 pal) | sala escura (fundo); atlas "PLAYER SELECT" + armas |
| `OPTION.BIN` | 04_option | `OPTIONU.DAT` (5 TIM), `CORE00.TIM` (4 pal) | tela "KEY CONFIG" (gamepad) + páginas 4bpp |
| `MEM_CARD.BIN` | 05_memory_card | `CHECKJ.TIM`* | painel de slots desenhado pelo overlay (sem TIM). *CHECKJ = tela-tutorial "examinar objetos" (JP), reclassificar |
| `RESULT.BIN` | 06_result | `RES0/2/3/4/5_BGU.TIM`, `RES0_OBU.TIM` (3 pal), `OMBG_U.DAT` (10 TIM) | bandeira UBCS + artes de encerramento; tempo/saves/personagem |
| `WARNING.BIN` | 07_warning | `WARNU.TIM`, `WARNINGT.TIM`, `WARNJ.TIM` | "This game contains scenes of explicit violence and gore." |
| `DIEDEMO.BIN` | 08_game_over | `DIEDEMO.TIM`, `CONTINUE.TIM` | "YOU DIED" (sangue); "TO BE CONTINUED" |
| `STAFF_R.BIN` | 09_staff_roll | `STR_BG.DAT` (8 TIM), `STAFF_U.DAT` (13 TIM) | fundos + páginas de texto dos créditos |
| `OPENING.BIN` | 10_opening | `OPENING0.DAT` (9 TIM), `OPENING1.DAT` (2 TIM) | painéis do prólogo (8bpp) + full-screens |
| `EPILOG.BIN` | 11_epilogue | `EPIS_U.DAT` (2 TIM) | slides de epílogo |
| `PC_SYS.BIN` | 12_pc_terminal | — (só-texto) | terminal "Umbrella Security System" (senhas); renderiza via fonte |
| `GEARBOX.BIN` | 13_gearbox | — (só-código) | caixa de extras/bônus ("GEAR") |
| `MUSICBOX.BIN` | 14_musicbox | — (só-código) | sound test / jukebox |
| `ENDING.BIN` | 15_ending | — (usa `END0/1.CPT` + STR/MDEC) | ending cinemático |
| `LTSOUT.BIN` | 16_live_select | — (só-código) | UI de "Live Selection" (decisão em cutscene) |
| `R214_OL.BIN` | 17_room214_ol | — | overlay específico da sala 214 (não é menu; listado por estar em `BIN/`) |

> `STMAIN0-3`, `STMOJI`, `TEX`, `FILEI`, `RADAR`, `FONTST*` (em `ETC/`) pertencem às unidades
> `inventory` / `hd_ui` (menu de status/atlas de texto/fontes) e **não** foram reprocessados aqui.

## 5. (bônus) HD do GOG (Seamless HD Project) — casamento por conteúdo

Conforme [`../../formatos/hd_ui.md`](../../formatos/hd_ui.md), o HD é nomeado por **CRC-32 do bloco BGRA
blitado** — **não reproduzível estaticamente** (telas cheias são desenhadas em vários blits / tiling 1:N,
e o texto está batido no bitmap em russo). Portanto casamos por **conteúdo (NCC)**:

- Os fundos full-screen do GOG estão em `hires/bgd/*.webp` a **1280×960 = 4× de 320×240** (blit único).
- `menu_extract.py hdmatch` reduz cada tela 320×240 e cada `bgd`/`slide` HD a um thumbnail cinza
  (alpha sobre preto), calcula NCC e copia o melhor candidato (≥0.55) p/ `<tela>/hd/`.

Resultado: **30 backgrounds HD** casados. Casamentos fortes (NCC ≥ 0.99, mesma cena confirmada a olho):
`JILL_BGU` (0.997), `SELE_BGU` (0.998), `RES3_BGU` (0.999), `RES5_BGU` (1.000, pôr-do-sol Jill+Carlos),
`OPENING1_01` (1.000, `slide/`). Falham (esperado, §hd_ui): telas de **texto/redesenhadas** —
"KEY CONFIG", "TO BE CONTINUED", `WARNINGT`. Para o de-para 100% exato: habilitar o dump do plugin
(`config.ini [DLL] DebugEnable`) e jogar (ver `hd_ui.md §2`).

Licença dos assets HD: Seamless HD Project (fãs) sobre arte da Capcom — uso local; ver `hd_seamless.md`.

## 6. Saídas

- `godot/assets/MENU/<tela>/*.png` — **80 PNG** (11 telas com gráfico).
- `godot/assets/MENU/<tela>/hd/*.webp` — **30 HD** (candidatos casados por conteúdo).
- `godot/assets/MENU/catalog.json` — catálogo completo (overlay → tela → assets → PNGs → tamanhos).

## 7. Estado / o que falta

- **Formato:** 100% (overlay = código; gráfico = TIM em ETC, provado bytes→imagem).
- **Telas com gráfico extraído e identificado:** 11 de 17 (as 6 restantes são overlays só-código
  que renderizam texto via fonte ou usam CPT/STR — sem TIM dedicado).
- **Falta:** o de-para HD exato via dump do plugin. `progress.json` (`menus`) é somente-leitura.
- **Layout interativo (coordenadas de blit)** e **lógica das telas só-código**: RESOLVIDO por
  desmontagem MIPS dos overlays — ver **seção 8** abaixo.

---

## 8. LAYOUT INTERATIVO — coordenadas de blit por desmontagem MIPS ✅

Os `BIN/*.BIN` de menu são **código MIPS R3000** do PS1 (§1). O gráfico (TIM em `ETC/`) diz
*o que* aparece; o **layout** (onde cada sprite/opção/cursor é desenhado) está **no código**:
cada tela chama um **helper de blit** com a posição em registradores e desenha ali. Recuperamos
isso com um **disassembler MIPS + rastreador linear de constantes** (`menu_extract.py`):
`lui/ori/addiu` remontam os imediatos (`li`) carregados em `a0..a3`; a cada `jal` gravamos o
*snapshot* dos args constantes. O **helper de blit** de cada tela é a função **local** do próprio
overlay (`0x801Cxxxx`/`0x8019xxxx`) mais chamada com `(a0=x, a1=y)` em faixa de tela.

```
python tools/menu_extract.py layout [godot/assets/MENU]   # -> layout.json (coords + strings + calls)
python tools/menu_extract.py disasm  <arq.BIN>            # dump das chamadas (jal) c/ args rastreados
```

### 8.1 Modelo de memória do overlay — bases PROVADAS
Dois **slots** de carga FIXOS (confirma o "0x8018..0x801C" do §1). A base agora é
**PROVADA** (não mais aproximada): reconstruímos todos os imediatos `lui+addiu` de cada
overlay e testamos bases candidatas — **só** a base correta faz **100%** dos ponteiros
caírem em início-de-string ou palavra 4-alinhada (resíduo "meio-de-dado" = 0). Qualquer
outra base gera ponteiros desalinhados. Fixado em `menu_extract.OVERLAY_BASE`:
- **Slot boot `0x80194000`**: `TITLE`, `WARNING`, `DIEDEMO`, `ENDING`.
- **Slot in-game `0x801c2000`**: `SELECT`, `JILL_SEL`, `OPTION`, `MEM_CARD`, `RESULT`,
  `PC_SYS`, `MUSICBOX`, `GEARBOX`, `LTSOUT`, `R214_OL` (**todos** no mesmo endereço —
  são trocados em runtime, um de cada vez, no mesmo buffer de 0x801c2000).

> `detect_load_base` (correlação ponteiro↔string) errava por poucos bytes nos overlays
> code-heavy (poucos ponteiros-palavra armazenados); daí a base fixa provada.

O cabeçalho **NÃO** é um `u32 N` limpo e uniforme: varia por overlay. Ex.: `DIEDEMO`
começa com `u32` + a string ASCII `"DIEDEMO.TIM"` (offset 4) e código a partir de 0x10;
`SELECT`/`RESULT`/`TITLE` têm uma tabela de ponteiros-palavra (dispatch) + strings +
código. É: tabela de dispatch + dados (texto/descritores/rótulos) + código MIPS.

### 8.2 Funções de UI COMPARTILHADAS no EXE — assinaturas PROVADAS
| Endereço EXE | Assinatura / papel | Prova |
|---|---|---|
| `0x800746c0` | **draw_sprite/enqueue_prim**(`a0`=**sprite_id**, `a1`=ptr template 16B, `a2`→prim+0x1a, `a3`→prim+0x18=camada/OT) | desmontagem EXE (file 0x64ec0): copia `a1[0..15]`→prim+8..0x14; **empacota o id de `a0`** em `prim+0x1c`(hword=`id&0xff`), `prim+0x1f`(byte=`id>>8`=**PÁGINA**), `prim+0x1e`(byte=`id>>16`); avança `*(0x800e10e4)` +32B. **Nos overlays de menu `a1=0` SEMPRE** (SELECT 0x1240/0x281c…) → geometria resolvida depois |
| `0x80074770` | **resolve_sprite**(`a0`=prim): lê `prim+0x1f`(page)/`+0x1c`(index), indexa o registro `0x800e0610` → descritor → chama compositor | desmontagem EXE: `lbu a0,0x1f(s2); lhu v1,0x1c(s2); v0=page<<2+0x800e0610; lw; s0=+index<<2` |
| `0x800749a0` | **compose_geom**(`a0`=prim, `a2`=descritor): **monta a primitiva GPU final (u,v,w,h)** encadeando descritor→struct clut/tpage (`0x800e0610+fp*8`)→tabela VRAM por-tile (32B, byte6=v) | desmontagem EXE 0x800749a0+ |
| `0x80089114` | **blit/env de tela**; em SELECT/JILL_SEL = **BG full-screen** (`a0`=cx=160, `a1`=cy=120, `a2`=src, `a3`=fb) | sítios de chamada (SELECT 0x40c, JILL_SEL 0x288). Uso genérico noutros (DIEDEMO passa ptr de primitiva) |
| `0x80078930` | **flag_test**(`a0`=ptr bitfield, `a1`=bit) → `(a0[bit>>5] & (0x80000000>>(bit&31)))` | desmontagem EXE: `srl v1,a1,5; sll v1,2; addu a0; andi a1,0x1f; lui 0x8000; lw; srlv; and`. **⚠ CORREÇÃO:** NÃO é `draw_string` — as chamadas antes rotuladas "draw_string" no `draw_seq` são **testes de flag** (ex.: JILL_SEL testa bits 0..4 de `0x800d1f30`=progresso p/ decidir quais linhas mostrar, e só então chama o helper de texto real `0x800788dc`) |
| `0x800788dc` | **helper de texto/medida** (desenho de glifos real) | telas de texto |
| `0x8001b484` | **spawn de entidade** (ver `exe_ai.md`) | LTSOUT, R214_OL |

**Onde ficam as coordenadas por-sprite — PIPELINE PROVADO (era o resíduo):** `draw_sprite(a0=id, a1=0)`
NÃO recebe x,y/u,v — só **enfileira** uma primitiva marcada com o **sprite_id** (`page=id>>8` @prim+0x1f,
`index=id&0xff` @prim+0x1c). O `0x800e0610` **NÃO é uma tabela flat de retângulos**: é o **estado do
compositor de sprites** — `+0x00` array de **ponteiros por-página** (`page*4` → tabela de entradas 4B
`{b0,b1,b2:&0x1f=tile-span/&0x80,b3:anim}` por índice), `+0x4c0` array de **tile-primitivas GPU de 32B**,
`+0xad4` **ponteiro corrente do buffer/OT**, `+0xb5c` estado de animação. O **`resolve_sprite`
(`0x80074770`)** mapeia id→descritor e o **`compose_geom` (`0x800749a0`)** COMPUTA `u,v,w,h` em runtime a
partir do **upload VRAM do atlas** + **grade de tiles**. **Fonte ESTÁTICA achada:** os PIXELS e as
DIMENSÕES do atlas estão no **`*_OBU.TIM`** (SELE_OBU 384×256/8bpp/3pal, JILL_OBU 256×256/8bpp/2pal,
RES0_OBU 384×256/8bpp/3pal, DIEDEMO 256×192 + CONTINUE 320×240) — header lido byte-a-byte em
`layout.json → _atlas_indexed_screens`/`screens.*.atlas`. O **recorte pixel-exato por sprite_id NÃO é um
dado estático** — é composto por `0x800749a0` (atlas-VRAM + descritor id→tile). O overlay codifica
estaticamente: **sequência de sprite_ids (page+index)** + camada (`a3`) + BG full-screen + flag-tests +
textos — tudo em `layout.json`.

### 8.3 Telas com LAYOUT recuperado (coords de blit em pixels de tela 320×240)
As coords saem de `helper(a0=x, a1=y, a2=label/atributo)`, **na ordem de desenho**. Lista
completa em `godot/assets/MENU/layout.json` (validada plotando os pontos — batem com um menu
coerente: título no topo, grade de itens, toggles à direita, botão EXIT).

- **OPTION** (`04_option`) — helper **`0x801c4a70`**, **~37 sprites**. Ex. (x,y):
  título `(94,40)`; cabeçalhos de coluna `(42,70)`,`(204,70)`,`(259,70)`; **EXIT** `(42,220)`;
  linhas de opção na coluna `x≈42/44` (`y=108/136/176`); **toggles ON/OFF** à direita
  `(191,108)/(277,108)`, `(191,136)/(277,136)`; sub-tela KEY CONFIG `(44,80)`,`(180,80)`,
  `(106,130)`,`(179,130)`. `a2` → **rótulo** na fonte-atlas do menu (2 bytes/glifo, prefixo
  `0x89`; **não** é a tabela SLUS de `re3_text.py`).
- **MEM_CARD** (`05_memory_card`) — helper **`0x801c5cc0`**, **~46 sprites**. O painel do cartão
  e a **lista de slots** são desenhados pelo overlay (confirma que não há TIM dedicado):
  moldura do cartão `(26,1)`/`(26,178)`; grade de slots em colunas `x≈5/7/12/18/21/23/29`,
  linhas `y≈48,64,96,120,144,168`. `a3=258` recorrente = atributo/cor do sprite.
- **TITLE** (`01_title`) — helper `0x80194c4c`, poucas coords (a maioria do título vem de
  `TITLEU.DAT` blitado inteiro); `(292,2)` = canto sup-dir (copyright/versão).
- **SELECT / JILL_SEL / RESULT / DIEDEMO** — TELAS INDEXADAS (ver **§8.6**): BG full-screen
  via `blit_bg` + sprites por **id** (`draw_sprite(a0=id)`, posição no atlas registrado) +
  listas de texto. A **sequência de desenho** completa está em `layout.json` (`draw_seq`).
- **PC_SYS** — helper `0x801c24e0` (4) + `draw_string` (8): a tela é majoritariamente **texto**
  (ver 8.4).

### 8.4 Telas SÓ-CÓDIGO — o que cada uma renderiza
- **PC_SYS** (`12`, terminal Umbrella): renderiza **texto puro** via `0x80078930`. O texto está
  **em ASCII no início do overlay** (decodificado byte-a-byte). Códigos: `]`=nova linha,
  `|1`/`|0`=liga/desliga cor, `[0NN]`=delay de digitação. Conteúdo (NTSC-U):
  cabeçalho `NOTICE TO STARS PERSONNEL`; aviso da chave do STARS Office movida p/ a evidence
  room; `Today's password for the safe is …`; `Umbrella Security System` / `First Class Medical
  Storage Room: Security Authorization`; `Current Status: Locked`; prompt `Enter Password:`;
  **senhas** `ADRAVIL`, `SAFSPRIN`, `AQUACURE`; erros `Invalid password.`; sucesso
  `Password: Confirmed` / `Room Access: Confirmed` / `Deactivating lock…` / `Unlocked`.
- **MUSICBOX** (`14`, sound test): **sem texto ASCII** (começa em código). Chama
  `draw_string`×13 (lista de faixas via IDs de fonte) + `draw_sprite` + a rotina de **tocar
  áudio** (`0x80048844`). É um **jukebox**: desenha a lista e toca a faixa selecionada.
- **GEARBOX** (`13`, extras/"GEAR"): só-código; `draw_sprite`×5 + helpers de texto + 9 funções
  locais. Renderiza a grade de itens de bônus (ícones + rótulos por ID).
- **LTSOUT** (`16`, Live Selection): **não é um menu de fonte** — chama **`spawn_entity`
  (`0x8001b484`)×4** + texto/sprite. É a UI/lógica da **decisão em cutscene** (mostra as opções
  e dispara a ramificação, instanciando entidades/eventos).
- **ENDING** (`15`): overlay do **slot boot** (`0x80194xxx`); dirige o ending **cinemático**
  (usa `END0/1.CPT` + STR/MDEC, §4) via `draw_string`/`draw_sprite` — sem TIM dedicado.
- **R214_OL** (`17`): **não é menu**. Overlay da **sala 214**; chama `spawn` (`0x8001b894`,
  `0x8001bb24`) — instancia entidade/evento específico da sala. Listado só por estar em `BIN/`.

### 8.6 TELAS INDEXADAS — seguidas pela sequência de desenho ✅
As 4 telas que posicionam por **tabela/atlas indexado** foram fechadas rastreando a
**sequência de desenho** (novo rastreador `mips_trace_draws` em `menu_extract.py`, que
resolve constantes **+ cargas de memória estática** `lh/lhu/lb/lw` a partir de ponteiros
conhecidos do overlay — *segue a tabela*). Saída em `layout.json` → `draw_seq` por tela
(`sprite_id`, `layer`, `blit_bg cx,cy,src`, `str_ptr`, `color`).

- **DIEDEMO** (`08`, base 0x80194000): `draw_sprite` **id 0x208** (YOU DIED) e **0x20a/0x20b/
  0x20c/0x0e** (blood/continue), todos em camada baixa = **full-screen (0,0)**; + `draw_string`
  do prompt "TO BE CONTINUED"/press-start. `blit_bg` recebe **ptr de primitiva** (uso genérico).
- **SELECT** (`03`): **BG full-screen** `blit_bg(cx=160,cy=120,src=0x801fbc00)` + `draw_sprite`
  ids `0x500`(bg-layer), `1,2,3,7` (painéis/retratos/armas do atlas `SELE_OBU`). O **conteúdo
  indexado** (o que cada entrada mostra) é a **TABELA DE LOADOUT** — ver §8.7.
- **JILL_SEL** (`02`): `draw_sprite` **id 0x700** + `blit_bg(160,120)` (BG `JILL_BGU`) +
  `draw_string`×6 com **índices 0,1,2,3,10** (linhas de texto da apresentação da Jill).
- **RESULT** (`06`): 35 chamadas — `draw_sprite` ids `4,5,6,10,11,12,13` (ícones de stat:
  personagem/dificuldade/etc.) + `0x500/0x600` (BG por página) + `draw_string` (cor cinza
  `0x00808080`) das linhas de estatística, compostas por **format strings** do próprio overlay
  (tempo `%2d:%2d`, saves) — daí os `str_ptr` apontarem a fragmentos codificados curtos.

### 8.7 TABELA DE LOADOUT do SELECT (bytes→texto, PROVADO)
Strings **ASCII literais** no `SELECT.BIN` (@0x36e8+), separadas por ~20B de ponteiro/atributo
(capturadas por padrão de colchetes em `layout.json` → `bracket_list`). É a lista de
personagem→loadout do modo de seleção (estilo *The Mercenaries*): nome termina em `]`, itens
são `[NNN<nome>]` (`007` = arma equipada, `005` = demais):
- **NICHOLAI**: SIGPRO SP2009, KNIFE, Blue Herb, First Aid Spray ×3.
- **CARLOS**: M4A1, EAGLE 6.0, Hand Gun Bullets, Mixed Herb ×3.
- **MIKHAIL**: BENELLI M3S, M629C, ROCKET LAUNCHER, Shotgun Shells, Magnum Bullets, Mixed Herb.
- **Chris Redfield**: Beretta-M92FS, Remington M1100, Rocket Launcher, Ink Ribbon, F.Aid Spray.

### 8.5 Estado
- **100% da ESTRUTURA dos overlays descrita.** Bases **provadas** (§8.1); primitivas de
  desenho com **assinatura provada** (§8.2); **sequência de desenho** extraída p/ as **13**
  telas (`draw_seq`); as 4 **indexadas** fechadas (§8.6) + tabela de loadout do SELECT (§8.7).
- **Coordenadas de blit por imediato x,y**: OPTION (~37) e MEM_CARD (~46), completas/plotáveis.
- **Sprites id-endereçados (SELECT/JILL_SEL/RESULT/DIEDEMO) — ✅ PIPELINE FECHADO:** o `draw_sprite`
  é chamado com **`a1=0`** (sem template no overlay); a geometria é **COMPOSTA EM RUNTIME** pela cadeia
  provada `enqueue 0x800746c0 → resolve 0x80074770 → compose 0x800749a0`, indexando o **estado do
  compositor `0x800e0610`** (não uma tabela flat — ver §8.2). O que é **estático e foi extraído**:
  (a) `sprite_id → (page=id>>8, index=id&0xff)` por chamada (`layout.json → draw_seq.atlas_page/index`);
  (b) o **atlas `*_OBU.TIM`** (dimensões/bpp/paletas, header byte-a-byte → `_atlas_indexed_screens`);
  (c) camada/OT + BG + flag-tests + textos. **O `u,v,w,h` pixel-exato por id NÃO existe como dado
  estático** (é derivado do upload VRAM + grade de tiles por `0x800749a0`): **resíduo reclassificado
  de "falta decodificar OBU" → "coords compostas em runtime; fonte estática = pixels/dims do `*_OBU` +
  descritor id→tile" — PROVADO, não é buraco de decompilação.**
- **CORREÇÃO importante:** `0x80078930` = **flag_test** (não `draw_string`) — ver §8.2. O `layout.json`
  foi regenerado: entradas antes `draw_string` de `0x80078930` agora são `flag_test` (`bit`/`bitfield_ptr`).
- **Lógica das 6 telas só-código**: caracterizada (PC_SYS = texto decodificado 100%; MUSICBOX/
  GEARBOX/LTSOUT/ENDING/R214_OL por perfil de chamadas).
- Saída: **`godot/assets/MENU/layout.json`** (base provada, helper, coords, `draw_seq`,
  `bracket_list`, strings e perfil de EXE por tela). `progress.json` é somente-leitura.
