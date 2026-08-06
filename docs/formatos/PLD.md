# Formato `.PLD` / `.PLW` — Modelos de personagem do RE3 (PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `pld`, `tim`, `plw`)
> - **Formato:** contêiner de personagem humano = MD1 (malha) + EMR (esqueleto) + EDD (anim) + TIM (textura); `.PLW` = arma (malha estática)
> - **Extensão/origem:** `CD_DATA/PLD/*.PLD` (27 humanos) e `*.PLW` (84 armas)
> - **Ferramenta:** [`tools/pld2gltf.py`](../../tools/pld2gltf.py), [`pld_hd_textures.py`](../../tools/pld_hd_textures.py) → `godot/assets/PLD/<nome>.glb`
> - **Decompilado:** **100%** (`pld`, `tim`) · **85%** (`plw`)
> - **Feito:** malha+UV+CLUT, esqueleto, skinning suave, 22 clipes por modelo, TIM (3 paletas) + texturas HD; 109/110 modelos exportados.
> - **Falta:** `PL06CH.PLD` (pool de vértices compartilhado); mesh da arma ainda estática. A **locomoção de gameplay** vem do banco EDD do **PLW** — ver [animacoes_player.md](animacoes_player.md) e [exe.md §4-B0](exe.md). Inimigos ficam no [enemy_bin.md](enemy_bin.md).

> Engenharia reversa feita byte-a-byte a partir de `extracted/ntsc-u/CD_DATA/PLD/*.PLD`.
> Conversor de referência: [`tools/pld2gltf.py`](../../tools/pld2gltf.py) (Python puro + numpy só p/ preview).
> Saída: `godot/assets/PLD/<nome>.glb` (malha + esqueleto + skin + animações + textura, tudo embutido).

O `.PLD` é o modelo de um **personagem jogável/NPC humano** (geometria + esqueleto +
animações + textura, num único arquivo). O `.PLW` é o modelo de uma **arma** que o
player segura — mesmo contêiner (com mais sub-blocos), mas **sem esqueleto próprio** (a
arma prende no osso da mão); é exportada como **malha estática** texturizada.

Resultado: **109 de 110 modelos convertidos** (25 `.PLD` com esqueleto+animação +
84 `.PLW` estáticos; só o `PL06CH.PLD` falha — ver [pendências](#9-status-e-pendências)).

**Todos os 27 `.PLD` são humanos** (Jill, Carlos, mercenários UBCS, civis). **Não há
zumbis/Nemesis na pasta PLD** — ver [seção Inimigos](#inimigos-onde-estão).

---

## 1. Contêiner

```
offset 0x00 : u32 dirOffset      // aponta p/ o diretório, que fica NO FIM do arquivo
offset 0x04 : u32 dirCount       // nº de sub-blocos (sempre 5 nos PLD de personagem)
...
[ sub-blocos, em sequência ]
...
dirOffset   : u32 offset[dirCount]   // tabela de offsets absolutos dos sub-blocos
```

Validação: `dirOffset + dirCount*4 == tamanho_do_arquivo` (o diretório termina exatamente no EOF).

Para o `PL00.PLD` (Jill, 159.116 bytes) o diretório tem 5 entradas:

| Idx | Offset | Tamanho | Papel |
|----:|-------:|--------:|-------|
| 0 | 0x000008 | 1.368 | **EDD** — tabela de sequências de animação |
| 1 | 0x000560 | 40.532 | **EMR** — esqueleto + *pool* de keyframes |
| 2 | 0x00A3B4 | 16.536 | **MD1** — malha (geometria) |
| 3 | 0x00E44C | 780 | bloco auxiliar (colisão/sombra? *a confirmar*) |
| 4 | 0x00E758 | 99.872 | **TIM** — textura embutida |

A **ordem** é consistente em todos os arquivos; ainda assim o conversor identifica cada
bloco por **conteúdo** (mais robusto):

- **TIM**: primeiro byte `0x10` + flag válido.
- **MD1**: primeiro `u32` == tamanho do próprio bloco (self-length).
- **EMR**: `u16` em `+4` (nº de ossos) entre 1 e 64 e offset de hierarquia dentro do bloco.
- **EDD**: o bloco restante.

> Os `.PLD` terminados em `CH` (ex.: `PL00CH.PLD`) são o mesmo personagem com **menos
> animações** (bloco EDD/EMR bem menor) — provavelmente variantes de dano/cutscene.

---

## 2. MD1 — Geometria

```
u32 length          // tamanho do bloco (== tamanho da seção)
u32 nObjects        // nº de "objetos" (partes). Ex.: 21 na Jill
Object objects[nObjects]     // 24 bytes cada; offsets relativos a (blocoInicio + 8)
... dados de vértices/normais/primitivas ...
```

### Objeto (24 bytes)

```
u32 vtx_offset      // s32! pode ser negativo em variantes (ver PL06CH)
u32 nor_offset
u32 vtx_count       // nº de vértices (= nº de normais)
u32 tri_offset      // triângulos
u32 quad_offset     // quads
u16 tri_count
u16 quad_count
```

- **Vértice** = 8 bytes: `s16 x, y, z, pad`. Ponto-fixo (unidades PS1).
- **Normal** = 8 bytes: `s16 x, y, z, pad` (÷4096 p/ normalizar).

### Primitiva de triângulo (12 bytes) — estilo *packet* do GPU do PS1

```
[0] u   [1] v          // UV do vértice 0
[2..3] u16 CLUT        // id da paleta na VRAM
[4] u   [5] v          // UV do vértice 1
[6] tpage              // página de textura (1 byte)
[7] índice do vértice 0
[8] u   [9] v          // UV do vértice 2
[10] índice do vértice 1
[11] índice do vértice 2
```

### Primitiva de quad (16 bytes)

```
[0]u [1]v  [2..3]CLUT  [4]u [5]v  [6..7]tpage(u16)  [8]u [9]v
[10]vi0 [11]vi1  [12]u [13]v  [14]vi2 [15]vi3
```

Cada quad vira 2 triângulos: `(0,1,2)` e `(1,3,2)`. Os índices são **locais ao objeto**
(indexam o `vtx_offset` daquele objeto).

### CLUT / tpage / paleta

- `paleta = (CLUT >> 6) - 480` → 0, 1 ou 2 (ver TIM). Também vale `paleta = tpage & 0x0F`.
- `u` fica sempre em 0..127; o **X real na VRAM** = `paleta*64 + u`.
- **A paleta é por-primitiva** (um mesmo objeto pode misturar paletas 0 e 1).

---

## 3. EMR — Esqueleto (armadura)

```
u16 hier_offset     // offset da hierarquia (relativo ao início do EMR)
u16 (keyframe_off)  // = 176; início do pool de keyframes (fim do EMR)
u16 nBones          // 15 nos humanos
u16 frame_size      // bytes por keyframe de animação (= 76)
RelPos relpos[nBones]           // logo após o header (offset +8): s16 x,y,z (6 bytes cada)
... (2 bytes de padding) ...
Hier  hier[nBones]  @ hier_offset   // { u16 nFilhos; u16 offListaFilhos }  (4 bytes cada)
u8    childPool[...]                // listas de filhos (índices de osso, 1 byte cada)
```

- `relpos[i]` = **translação do osso i relativa ao pai** (ponto-fixo).
- A hierarquia dá, por osso, a lista de filhos → daí deduzimos o **pai** de cada osso.

Esqueleto humano dos PLD (15 ossos) — pais decodificados de `PL00`:

```
parent = [-1, 0, 0, 2, 3, 0, 5, 6, 0, 8, 9, 10, 8, 12, 13]

0  raiz/quadril        8  pélvis
1  tronco+cabeça       9,10,11   perna direita  (coxa, canela, pé)
2,3,4  braço direito   12,13,14  perna esquerda
5,6,7  braço esquerdo
```

A simetria esquerda/direita nas contagens de vértices e no `relpos` (z espelhado)
confirma o mapeamento **objeto i → osso i**. Não há osso dedicado de cabeça (ela faz
parte do objeto do tronco).

> **Offset global da raiz.** `relpos[0]` (ex.: `(0,-1839,0)`) **não** é a posição do osso
> na malha — é um deslocamento global de posicionamento no mundo. No *bind pose* a raiz
> é colocada na **origem** (senão a malha e o esqueleto ficam desalinhados). Com isso as
> juntas acumuladas batem com a malha (ex.: junta do pé ≈ y+1737, igual ao pé da malha).

---

## 4. Espaço de coordenadas dos vértices (importante!)

A **maioria** dos objetos do MD1 já está em **espaço-modelo absoluto** (pose neutra):
renderizando os vértices *como estão* o corpo sai coerente (barra da saia encosta na
bota). **Porém há exceção:** as **MÃOS** (e os conectores degenerados de 3 vértices)
estão em **espaço-de-osso** (centradas na origem), pois são pontos de encaixe da arma.
Se tratadas como absolutas, as mãos aparecem **dentro do corpo** (no centro, Z≈0) —
era o *bug 3* reportado.

O conversor **detecta** partes em espaço-de-osso (centroide perto da origem enquanto o
osso está longe: `|centroide| < 0,5·|osso_mundo|` e `|osso_mundo|>200`) e as traz para
o espaço-modelo somando a posição de descanso do osso. Assim a mão volta para o lado do
corpo (Z≈±425) e o pipeline de skinning fica **uniforme** para todos os objetos.

Consequência para o *skinning*:

- Vértice fica no espaço-modelo; é atribuído 100% ao **osso do seu objeto** (`obj i → osso i`).
- `inverseBind[j] = translate(-posDescanso_mundo[j])` (leva o vértice p/ o espaço do osso).
- Nós do esqueleto usam `relpos` como translação (raiz = 0). No repouso,
  `jointGlobal · inverseBind = I` → a malha aparece exatamente na pose neutra.
- Na animação, o osso rotaciona em torno da **junta correta** (posição de descanso).

Eixos: PS1 usa **+Y para baixo**. O glTF é Y-up destro → convertemos
`(x, y, z) → (x, -y, -z)` e escalamos por `SCALE = 0.001` (personagem ≈ 2,4–3,0 m; o
Godot pode reescalar).

---

## 5. TIM — Textura embutida

Formato TIM padrão do PS1 (reaproveita a lógica de [`tools/tim2png.py`](../../tools/tim2png.py)):

- **8 bpp + CLUT**, imagem de **384×256** pixels.
- **3 paletas** (CLUTs) de 256 cores, na VRAM em Y = 480/481/482.
- Partes diferentes do corpo usam paletas diferentes (pele, roupa, botas...).

Como o mesmo pixel indexado recebe **cores diferentes** conforme a paleta, o conversor
gera um **atlas vertical** de **384×768** (uma cópia decodificada por paleta, empilhadas):

```
UV_no_atlas = ( tpage_x*128 + u ,  paleta*256 + v )  / (384, 768)
```

> **⚠ tpage em 8bpp = 128 texels por unidade.** O X da página de textura (`tpage & 0x0F`)
> é medido em unidades de **64 halfwords** da VRAM; em **8bpp cada halfword = 2 texels**,
> logo `x_base = tpage_x*128` (e **não** `*64`). Foi a causa-raiz do *bug 1*: o **rosto**
> fica na coluna central da textura (x≈128–256) e só era alcançado com o passo de 128.
> Com `*64` a cabeça amostrava a região errada e saía embaralhada.

`paleta = (CLUT>>6) - 480` seleciona a banda vertical; `tpage_x` seleciona a coluna.
Resultado: rosto, topo azul, saia preta, botas marrons e pele corretos (validado em
Jill, Carlos, e demais personagens).

---

## 6. Animação (EDD + pool de keyframes)

### Pool de keyframes (poses)

Fica **logo após o EMR**, dentro da seção 1, começando no offset `keyframe_off` (176).
Número de poses = `(tamanho_da_seção1 - 176) / 76` (exato; ex.: **531** poses na Jill).

Cada **keyframe = 76 bytes**:

```
[0..5]  s16 root x, y, z      // translação da raiz (root motion) do frame
[6..7]  s16 flag/pad
[8..]   45 ângulos de 12 bits // 15 ossos × (X,Y,Z), empacotados little-endian
```

- Ângulo (0..4095) → radianos: `ang/4096 * 2π`.
- Rotação **local** do osso = `Rx · Ry · Rz` (ordem **XYZ**, validada visualmente:
  a pose 0 da Jill é um passo de caminhada limpo).
- Transformada local do osso no frame = `T(relpos) · R(ângulos)`.

### EDD — RE COMPLETA (UM banco de sequências + frame-list) ✅

A seção EDD (1368 B no `PL00`) tem **dois pedaços contíguos**:

**1) Tabela de sequências — N registros de 8 bytes** `{ u16 nframes, u16 frameOffset, u32 poseStart }`:

- `poseStart` (o `u32`) = **índice absoluto** (no pool de 76 B) da 1ª pose da sequência.
- `frameOffset` = **offset em bytes, a partir do início do EDD**, para dentro da frame-list.
- `nframes` = **número de frames de JOGO** da sequência (gameplay a **30 fps**).

**2) Frame-list** — começa em `EDD + min(frameOffset)`; **2 bytes por frame**:

```
frame_entry (u16):  byte BAIXO = índice de pose RELATIVO a poseStart
                    byte ALTO  = flags de evento (som de passo, etc.)
```

**Quantas sequências (N)?** *Não há campo de contagem.* A tabela termina exatamente onde
a frame-list começa; como toda `frameOffset` aponta **para** a frame-list, o **menor
`frameOffset`** é o início dela → `N = min(frameOffset) / 8`. No `PL00`: `min = 176` → **N = 22**
sequências (`anim00..anim21`). A prova é o **encadeamento exato**: a região de frames de
cada registro termina onde começa a do seguinte, e a última (`anim21`) termina em 1362 ≈
fim do EDD (1368, com 6 B de padding). **Todas as 531 poses** do pool são cobertas pelas
22 sequências (poses 0..447 + 447..531).

> **NÃO existe "2º banco".** O que parecia um 2º banco a partir do "registro 22" eram os
> **bytes da frame-list** sendo lidos como registros de 8 B. Há **um único banco** de 22
> sequências. (Confirmado: todos os índices de pose da frame-list caem em `[0, npose)`.)

**As 22 sequências são exportadas** (`pld2gltf.build_anim_clips` segue a frame-list: 1
keyframe glTF por frame de jogo, com holds/reuso). Antes só saíam **19** — a extração
antiga (`range(poseStart, poseStart_seguinte)`) **derrubava 3**:

| Clipe | Por que faltava | O que é (render opengl3) |
|-------|-----------------|--------------------------|
| `anim06` | `poseStart == poseStart` do `anim07` → parecia "tamanho zero" | passo curto **virando** (reusa poses de anim07) |
| `anim08` | `poseStart == poseStart` do `anim09` → parecia "tamanho zero" | **abaixar e apanhar/examinar** no chão |
| `anim21` | última sequência: sem "próximo registro" p/ deduzir o `pend` | **IDLE** de espera (mão ao queixo), 84 fr = 2.77 s, loop perfeito |

Seguir a frame-list também dá a **duração EXATA** de cada clipe (holds incluídos):
`anim00` = 34 fr = **1.133 s** (1:1, flags de passo nos frames 5 e 22 = 2 toques de pé,
loop natural); `anim01` = 119 fr = **3.93 s** (60 poses com hold). Dados em
`godot/data/anim_map.json` e `physics.json`.

### Andar pra frente e Correr — IDENTIFICADOS por render ✅

> **⚠ CORREÇÃO (ver [animacoes_player.md](animacoes_player.md) e [exe.md §4-B0](exe.md)):**
> `anim00`/`anim10` abaixo são o andar/correr do banco **DESARMADO/base** (banco default
> `0xec` = este PLD). Na jogabilidade a Jill está **sempre com arma na mão**, então o
> andar/correr que se vê vem do banco EDD do **PLW equipado** (`PL00W00.PLW` seq0/seq1),
> **não** destas 22. As 22 seguem válidas como set base + ações sempre-válidas
> (apanhar `anim08`, idle-wait `anim21`; `anim19/20` = **em aberto**, dano-vs-mira — ver
> [animacoes_player.md](animacoes_player.md) e [exe.md §4-B.4](exe.md)).

Root-motion medido via frame-list (playback real 30 fps) + **render lateral/frontal**
(`tools_anim_shot.gd`, opengl3), sobre as 22 sequências:

- **ANDAR PRA FRENTE (base/desarmado) = `anim00`** — ciclo de passada **ereto** (render frontal: tronco
  reto, passada limpa, botas coladas). `net(-1972,0,0)` em 34 fr = **~60 un/frame** no
  eixo **-X**, giro ~0, **loop perfeito** (loopErr 0.03).
- **CORRER = `anim10`** — **sprint inclinado** pra frente, braços dobrados bombeando
  (render). `net(-2057,0,0)` em 10 fr = **~229 un/frame**, mesmo eixo **-X** do andar,
  giro 0. Razão correr/andar = **3.8×** (== `run_speed`/`walk_speed`).

O eixo **-X** é a FRENTE (andar e correr avançam nele). `anim12` (-3554, 123/f) é uma
corrida **com curva** (giro +16°); `anim14`/`anim16`/`anim15` são passos **laterais/giro**
(eixo Z). O `anim21` recuperado é o **idle** real (recomendado no lugar de congelar
`anim00#f0`).

### Como o glTF é montado

Para cada clipe, exporta-se um `animation` com, por osso, um canal de **rotação**
(quaternion por pose) + um canal de **translação** na raiz (root motion). O quaternion é
convertido do espaço PS1 p/ o glTF conjugando por `diag(1,-1,-1)` (nega as componentes
y,z). Tempo entre poses = 1/30 s (aproximação; a temporização exata do jogo depende do
frame-list ainda por decodificar).

---

## 7. Inimigos: onde estão?

Investigação da pasta e do disco:

- **Os 27 `.PLD` são todos humanos** (players/NPCs). Identificados por render:
  Jill (`PL00/01/07` e variação de traje em `PL02`), trajes alternativos
  (`PL03` azul, `PL04` branco), Carlos (`PL08`), soldados UBCS / militares
  (`PL09`, `PL0A`), civis/mercenários de jaqueta (`PL0B/0C/0E`). `PL0D.PLD` é um
  *stub* de 8 bytes. `PL0F` tem geometria+esqueleto ok, textura anômala (ruído).
- **`.DO1`–`.DO7`** (76 por STAGE) são modelos de **porta** (`DOOR00…`) das transições.
- **Zumbis, cães, Nemesis, Hunters etc. NÃO estão em PLD.** Eles são carregados
  **por sala**, embutidos nos contêineres **`STAGE#/R###.BIN`** (cada um começa com o
  próprio tamanho como header e contém ~25 TIMs embutidos, incluindo texturas 8bpp+CLUT
  de criatura, além da geometria). Decodificar os modelos de inimigo a partir dos
  `R###.BIN` é o próximo passo (provável mesmo MD1/EMR/EDD deste doc).

---

## 8. Uso do conversor

```bash
# um arquivo (com preview PNG opcional: vistas frente|lado, texturizado)
python tools/pld2gltf.py extracted/ntsc-u/CD_DATA/PLD/PL00.PLD saida.glb --preview preview.png

# todos → godot/assets/PLD/<nome>.glb
python tools/pld2gltf.py --all
```

Para incluir as armas `.PLW` (malha estática):

```bash
python tools/pld2gltf.py --all --plw
```

Cada `.glb` é **self-contained**: geometria, normais, UV, esqueleto (skin com
`inverseBindMatrices`), animações e a textura PNG — tudo no buffer binário. Importa
nativo no Godot 4 (validado: `godot --headless --path godot --import` importa os modelos
como `PackedScene` sem erros).

> **Contêiner do `.PLW`:** 9 sub-blocos (vs 5 do PLD) = **1 malha (MD1) + 1 TIM + 3 BANCOS de
> animação** (não "1 banco + auxiliares"). Bancos: **0** (blk0/1: 15 ossos, 76 B/pose, 18 seqs
> = corpo inteiro/locomoção armada), **1** (blk2/3: 7 ossos, 40 B, 8 seqs) e **2** (blk5/6: 9
> ossos, 52 B, 8 seqs) = overlays parciais (mira/gesto). Validação 84/84 e detalhe em
> [plw.md §5](../decomp/notes/plw.md). O MD1 e o TIM são identificados por conteúdo (self-length
> e `10 00 00 00`); os EMR parciais (7/9 ossos) não batem o esqueleto de 15 → o caminho de
> **malha estática** é usado p/ a geometria da arma.
>
> **Textura do `.PLW` = PELE (do PLD) + TIM da arma.** A geometria do `.PLW` é a
> **mão/braço** que segura a arma. As UVs da MÃO apontam para a região de pele do PLD;
> as UVs da ARMA apontam para um "slot" na VRAM (região quase-branca no atlas do PLD)
> que, em jogo, é **sobrescrito pela TIM da arma** (56×32). O conversor: (1) texturiza
> com o atlas do **PLD correspondente** (`PL00W03` → `PL00.PLD`) — mão vira pele; (2)
> **sobrepõe a TIM da arma** na caixa onde a geometria da arma amostra branco (≈ o
> tamanho da TIM). Resultado: mão com pele + faca/pistola com a textura certa (*bug 2*).

---

## 9. Rodada de refinamento (4 bugs corrigidos)

Após teste no Godot, 4 problemas foram identificados, corrigidos e **confirmados
visualmente** (renderizador próprio + import no Godot 4.7):

| # | Bug | Causa raiz | Correção | Confirmação |
|---|-----|-----------|----------|-------------|
| 1 | Textura da **cabeça** embaralhada | `tpage_x` em **8bpp** vale **128 texels/unidade**, não 64. O rosto está na coluna central (x≈128–256) e só era alcançado com passo 128 | `atlas_x = tpage_x*128 + u` (rastreado por-primitiva) | Rosto de Jill/Carlos/PL09 correto (olhos, nariz, boca, cabelo) |
| 2 | **Mão** do `.PLW` com textura da arma | A geometria da mão usa UVs da **pele do PLD**; a TIM da arma nem é endereçada | Texturizar `.PLW` com o **atlas do PLD** correspondente | Mão renderiza com pele + dedos |
| 3 | **Mãos dentro do corpo** | Mãos (`obj4/obj7`) estão em **espaço-de-osso** (Z≈0), não absoluto | Detectar partes em espaço-de-osso e somar a pose de descanso do osso | Mãos vão para Z≈±425 (laterais) |
| 4 | **Animações** com partes soltas | Consequência do bug 3: mãos na origem "voavam" ao animar | Idem bug 3 (bind das mãos correto) | Ciclo de caminhada limpo, sem partes soltas |

Todos os fixes são **gerais** (não específicos do PL00): validados em `PL00` (Jill),
`PL08` (Carlos), `PL02`, `PL09` etc.

---

## 9-B. Rodada de refinamento 2 — detachment REAL na animação (validado no Godot)

O *bug 4* da rodada 1 estava **mal diagnosticado**. O renderizador estático não pega o
problema: só o **Godot animando** (interpolando entre keyframes) revela que **membros de
extremidade se soltam** (ex.: `PL00` anim09 → a mão voa; `PL05CH` anim01). Método de
validação correto (implementado): renderizar o `.glb` no **Godot 4.7 real** (headless
não renderiza — usa driver dummy; rodar **com `--rendering-driver opengl3`** num script
`SceneTree` que instancia o `.glb`, toca a animação, dá `seek` num **frame do MEIO** e
salva PNG via `viewport.get_texture().get_image().save_png()`).

**Causa raiz real do detachment.** O modelo tem a geometria **repartida por osso de
forma grosseira**: p.ex. o **braço inteiro** (`obj2`, do ombro ao punho, Y −643..305)
está **100% no osso do OMBRO** (`bone2`); a mão (`obj4`) está no osso do PUNHO
(`bone4`). Com *skinning rígido* (1 vértice = 1 osso), quando o cotovelo/punho giram, a
ponta do braço (presa ao ombro) e a mão (presa ao punho) **se separam**. Verificado: as
poses globais dos ossos batem exatamente com o Godot (a hierarquia/interpolação está
certa) — o problema é o **vínculo vértice→osso**.

**Correção — skinning SUAVE por vértice.** Em vez de 1 osso por objeto, cada vértice
recebe **pesos (`WEIGHTS_0`) para os ossos mais próximos DENTRO DA CADEIA do seu objeto**
(ancestrais + descendentes), por `1/dist²` (até 4 ossos, `JOINTS_0`). Assim a ponta do
braço (`obj2`) segue o punho igual à mão, o joelho/bota acompanha a coxa, e **nada se
separa**. `inverseBind[c] = T(−pos_descanso[c])` por osso; no repouso a soma dá a malha
neutra. Confirmado no **Godot 4.7** (frames do meio de `anim00` caminhada e `anim09`
agachamento): membros **atados**, sem partes voando.

> Nota: o Godot já corrige o hemisfério do quaternion no `slerp`, então a
> continuidade de hemisfério (também aplicada no export) **não** era a causa; a causa
> era o binding rígido.

## 9-D. Envelope local por membro — botas/antebraços que NÃO seguiam o osso

Sintoma (vista LATERAL do andar/correr): a **bota flutuava abaixo da canela** e o
**antebraço ficava pra trás** ao dobrar. Causa raiz: a geometria é **grosseiramente
repartida** e vários elos são **conectores vazios** (3 verts, sem objeto próprio), então
a parte distal fica *assada* dentro do objeto do elo pai:

- `obj8` (pelve) = pelve **+ as duas coxas** → as coxas devem seguir `bone9/bone12`.
- `obj10/obj13` (canela) = canela **+ bota/pé** → a bota/pé deve seguir `bone11/bone14`
  (o **tornozelo**); a canela segue `bone10/bone13` (o **joelho**).
- `obj2/obj5` (braço inteiro) = braço **+ antebraço** → antebraço segue `bone3/bone6`
  (**cotovelo**), a ponta segue `bone4/bone7` (**punho**); a mão (`obj4/obj7`) → punho.

O round anterior prendia as extremidades ao **ancestral substancial** (mão→ombro,
bota→pelve) só p/ "não sumir" — mas isso as prendia a um osso **alto demais**, então
elas **não dobravam** na junta local (o "mesh não respeita o bone").

**Correção (`assemble` em `pld2gltf.py`): envelope LOCAL de membro.** Para cada objeto
montamos os ossos candidatos = osso-raiz + **descendentes** cuja geometria está assada
aqui (desce enquanto o osso for **não-substancial**; para ao topar um osso com objeto
próprio) + o **pai FK** (p/ selar a junta do topo). Cada osso vira um **segmento de reta**
(do seu `world` ao `world` do 1º filho, extrapolado se for ponta). Cada vértice pesa nos
**2 ossos com segmento mais próximo** (`1/dist^POWER`, POWER≈5). Como os segmentos de um
membro só ficam equidistantes **perto da junta**, o blend é automaticamente uma **faixa
fina** na dobra e **rígido** fora dela — sela **joelho, tornozelo, cotovelo, punho,
quadril, pescoço** sem o amassamento "papel" do blend global (poucos candidatos, todos do
mesmo membro). Mapa objeto→osso resultante (Jill `PL00`, primário por vértice): coxas em
`9/12`, canelas em `10/13`, botas/pés em `11/14`, antebraços em `3/6`, mãos em `4/7`.
Validado no **Godot 4.7** (vista lateral, `anim16`/`anim10`/`anim00`): botas e antebraços
**colados e dobrando** na junta, sem fresta nem lag. Ajuste por env:
`PLD_ENV_POWER`, `PLD_ENV_EPS`, `PLD_ENV_MINW`, `PLD_ENV_JOINT_MIN`; `PLD_NO_JOINT_BLEND`
volta ao rígido puro.

## 9-C. Vetores de movimento por pose (root-motion) — `godot/data/physics.json`

A tabela de poses (seção EMR, offset +176, poses de **76 B**) guarda o **root** em
`pose+0x00` (`s16 x,y,z`) — é o **vetor de movimento** que em RAM (struct de 188 B em
`player+0x108`) aparece em `pose+0x54`. O **facing/giro** vem do **ângulo Y do osso 0**
(`pose+8`, ângulo idx 1, 12 bits). Extraído de `PL00.PLD` (sobrescreve as estimativas):

| Movimento | Anim | un/frame (média) | pico | giro °/frame |
|---|---|---|---|---|
| Andar frente | anim00 | ~60 | 69 | ~0 |
| Correr frente | anim10 | ~229 | 375 | ~0 |
| Giro | anim03 | ~22 | — | ~3,4 |

Os vetores por-pose completos estão em `velocidades.*.motion_por_pose_xyz`.

---

## 10. Status e pendências

**Feito e validado:**
- Contêiner, MD1 (geometria + UV + CLUT/tpage), EMR (esqueleto + pose de descanso), TIM
  (atlas 3 paletas). Malha texturizada **visualmente correta**, incl. **rosto** e **mãos**.
- **Skinning SUAVE por vértice** (seção 9-B): animações sem membros soltos —
  **confirmado no Godot 4.7 real** (frames do meio de caminhada e agachamento).
- Animação: pool de 531 poses (ângulos 12-bit, ordem XYZ); **22 clipes** por modelo
  (`anim00..anim21`) — RE completa do EDD (um banco de 22 sequências + frame-list; ver
  seção 6). **Andar frente = anim00, correr = anim10, idle = anim21** (render opengl3).
- `.PLW`: mão com **pele** do PLD + arma com a **TIM própria** composta (faca/pistola ok).
- **Root-motion medido** de `PL00.PLD` → `godot/data/physics.json` (seção 9-C).
- **109 de 110** modelos convertidos (25 `.PLD` + 84 `.PLW`) e importados no Godot 4.7
  sem erro (`PackedScene`).

**Pendências / limitações conhecidas:**
- `PL06CH.PLD` (1 arquivo): **IDENTIFICADO** = variante **CH (cutscene/dano)** do personagem
  `PL06` (banco de anim reduzido: EDD=220 B, EMR=5800 B). Contêiner PLD de 5 blocos decodificado.
  É o **único** dos 110 modelos cujo **MD1 usa pool de vértices compartilhado**: os 21 objetos
  têm `vtxOff=norOff=-9636` idênticos e o struct de 24 B traz `{primStart, primEnd, primCount}`
  (consecutivos entre objetos, `(end-start)/count == 12.0` exato). O stream de 12 B **não** é o
  `emd3_triangle` padrão (sem `0x7800`, índices degenerados) → semântica exige RE do loader MD1
  no EXE. **Não exportado**: é redundante com o `PL06.PLD` (já exportado). Detalhe em
  [plw.md §7](../decomp/notes/plw.md).
- `PL0F`: textura com conteúdo anômalo (ruído) — modelo especial/não usado?
- ~~Temporização exata / 2º banco~~ **RESOLVIDO**: a frame-list dá o mapeamento
  frame→pose exato (holds/reuso) e não há 2º banco (é um único banco de 22 sequências).
  As 22 são exportadas com duração exata (ver seção 6).
- Bloco auxiliar (seção 3, 780 B) não identificado (hipótese: colisão/sombra).
- Modelos de **inimigos** (em `R###.BIN`) ainda não extraídos.

---

## 11. Texturas HD (Seamless / GOG) — `tools/pld_hd_textures.py`

O projeto **Seamless HD** (na instalação GOG, `.../Resident Evil 3/hires`, **somente
leitura**) traz versões HD das texturas do jogo em `.webp`:
- **`hires/skin0`** (129) = **personagens** (majoritariamente **rostos**), 512×1024.
- **`hires/skin`** (497) = **misto** — personagem + cenário/objeto (ink ribbon, gavetas…);
  usar limiar mais alto para evitar falso-positivo de cenário.

Cada `.webp` de **512×1024** é um **bloco PS1 de 128×256 em 4×**. A textura embutida no
PLD (384×256, 3 paletas) só usa os **blocos diagonais** do atlas (banda k, coluna k):
**col0=corpo (pal0)**, **col1=rosto (pal1)**, **col2=detalhes (pal2)** — cada coluna
casada com um `.webp`.

**Método (mesmo NCC do `hd_match.py` dos backgrounds):** reduz cada bloco (128×256,
decodificado com a sua paleta) e cada `.webp` a um thumbnail cinza 64×128 (aspecto 1:2)
e correlaciona (NCC). Limiar **skin0 ≥ 0.85**, **skin ≥ 0.93**. Casou → coloca a HD
(512×1024) no bloco do atlas em 4×; não casou → mantém o PS1 em 4×. O GLB é reconstruído
com o atlas HD (`pld2gltf.convert(hd_atlas=...)`); **as UVs continuam válidas** (são
normalizadas pelas dims lógicas do PS1 — 384×768 — então a imagem HD, múltiplo inteiro,
mapeia sem mudança).

```bash
python tools/pld_hd_textures.py PL00           # dry-run (só reporta match)
python tools/pld_hd_textures.py --all --apply  # reconstrói godot/assets/PLD/*.glb com HD
```

**Resultado:** **19/27 modelos** ganharam ≥1 bloco HD (**23 blocos** no total). Quase
todos casam o **ROSTO** (NCC ~0.87–0.94); **Carlos (`PL08`)** casa **corpo (0.970) +
rosto** e **`PL09`** casa **rosto + detalhes (0.998)**. O **corpo da Jill** (`PL00`) NÃO
tem HD casável (só o rosto). Validado no **Godot 4.7 real**: rosto da Jill nitidíssimo
(olhos/cabelo HD) com o **skinning suave preservado** (caminhada sem membros soltos);
Carlos inteiro em HD. Import sem erros.

> Limitações: o corpo de vários personagens (incl. Jill) não tem HD no set → fica em PS1.
> As **armas `.PLW`** ainda usam a pele PS1 do PLD (a mão não recebeu HD — refino futuro).
> `hires/skin` mistura cenário: por isso o limiar 0.93 lá (falsos ~0.3, verdadeiros ~0.95+).
