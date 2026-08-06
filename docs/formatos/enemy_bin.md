# Formato `STAGE#/R###.BIN` — modelos de inimigo/objeto do RE3 (PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `enemy`)
> - **Formato:** modelo de inimigo = **EMD** (contêiner Sony TMD: esqueleto+anim+malha+textura). No PS1 é embutido/**reempacotado in-RAM** no `R###.BIN` por sala; no PC (GOG) é **EMD standalone**.
> - **Extensão/origem:** PS1 `CD_DATA/STAGE1..7/R###.BIN` (122 salas) · **PC/GOG** `Rofs9.dat`=`ROOM/EMD` (69 EMD+TIM) e `Rofs10.dat`=`ROOM/EMD08` (31)
> - **Ferramenta:** [`tools/emd2gltf.py`](../../tools/emd2gltf.py) (EMD do GOG → glb) · [`bin2gltf.py`](../../tools/bin2gltf.py) (contêiner PS1) → `godot/assets/ENEMY/`
> - **Decompilado:** **95%**
> - **Feito:** ✅ **69/69 EMD → `.glb`** (assets/ENEMY), autossuficiente (esqueleto/anim/malha/textura do próprio EMD). Montagem VERIFICADA por render: zumbi, cão (Cerberus), corvo, aranha, insectoide, Nemesis-provável, 2 helicópteros, humanos. **19 nomes confiantes + ~49 palpites** (`_incerto`).
> - **Falta:** mapa **EM##↔nome-canônico** (não é público) e o **`type_id(sce_em_set)`↔espécie** (em aberto no exe); `EM2D.EMD` corrompido (layout divergente). Detalhes/roster em [`../decomp/notes/enemy_mesh.md`](../decomp/notes/enemy_mesh.md); IA em [exe.md §3](exe.md).

> ⭐ **RESOLVIDO (round EMD).** A malha dos inimigos foi **destravada pelo port de PC (GOG)**:
> os inimigos estão lá como **`.EMD` standalone** (formato `emd3.h` do reevengi), limpos e
> decodificáveis. O `emd2gltf.py` exportou **69/69** para `godot/assets/ENEMY/*.glb`. O
> `.EMD` embutido no `R###.BIN` do PS1 é **reempacotado in-RAM** (formato próprio, não
> decodificado — §4 abaixo, mantido como histórico), mas isso **deixou de ser bloqueante**:
> o modelo limpo vem do GOG e o esqueleto/anim são idênticos aos do PS1.
>
> **Onde estão os inimigos**: os `.PLD` são só humanos (ver [PLD.md](PLD.md)). Zumbis,
> cães, aranhas, Nemesis etc. são carregados **por sala** (no PS1, embutidos no `R###.BIN`).

## Estado da RE

| Parte | Status |
|---|---|
| **EMD standalone do GOG → `.glb`** (esqueleto+anim+malha+textura) | ✅ **69/69 exportados** (`emd2gltf.py`) |
| Contêiner `R###.BIN` do PS1 (manifesto de blocos) | ✅ **decodificado** (validado em 122 salas) |
| Classificação bloco **modelo** (RAM) vs **textura** (VRAM) | ✅ decodificado |
| Sub-contêiner do modelo (diretório de 8 seções) | ✅ decodificado |
| **EMR** (esqueleto) / **EDD** (anim) / **TIM** (pele) | ✅ OK — 15 ossos, 16 clips, 8bpp+CLUT |
| Identificação por **render** | ✅ zumbi/cão/corvo/aranha/insectoide/Nemesis-provável + 2 helicópteros |
| **Malha do PS1 `R###.BIN`** (formato in-RAM) | 🟡 **não decodificada** (histórico §4) — **não mais bloqueante** (usa-se o EMD do GOG) |
| Mapa **EM##↔nome-canônico** / `type_id`↔espécie | 🟡 em aberto (não público; falta `sce_em_set`) |

Todos os números são little-endian.

---

## 1. Contêiner `R###.BIN`  ✅

O arquivo é uma **lista de carregamento**: o loader do RE3 copia cada bloco ou para a
**RAM** (modelos) ou para a **VRAM** (texturas). Cabeçalho:

```
+0x00  u32  file_size       // == tamanho do arquivo (confere nas 122 salas com modelo)
+0x04  u32  block_count      // 6..18 (varia por sala)
+0x08  BlockEntry[block_count]     // 8 bytes cada
```

`BlockEntry` (8 bytes):

```
+0x00  u32  size             // tamanho do bloco em bytes
+0x04  u32  tag              // destino no engine (ver abaixo)
```

**Layout dos dados:** logo após a tabela vêm os blocos, **cada um alinhado a 0x800**,
começando no setor 1 (`0x800`). O último bloco (com alinhamento) termina no EOF:

```
offset(bloco 0) = 0x800
offset(bloco i) = round_up(offset(i-1) + size(i-1), 0x800)
```

### O campo `tag`

- `(tag >> 24) in {0x80, 0x81}` → **bloco de MODELO** (destino RAM principal do PS1).
  Ex.: `0x80a70000`, `0x818a0000`. O nº de blocos-modelo = nº de modelos dinâmicos
  carregados naquela sala (0 em salas vazias/save; 1–2 em salas de combate).
- caso contrário → **bloco de VRAM** (textura). O `tag` codifica a posição de upload
  na framebuffer da GPU. Alguns blocos VRAM são **TIM** completos (começam com
  `10 00 00 00`), outros são pixels crus / contêineres de fundo+máscara.

Exemplo real — `STAGE1/R101.BIN` (849920 bytes, 12 blocos):

```
blk0  size= 87916  tag=0x80a70000  MODELO   (zumbi: esqueleto+anim A+B, malha)
blk1  size= 36176  tag=0x818a0000  MODELO   (mesma malha, anim reduzida)
blk2  size=   752  tag=0x09060003  vram
blk3  size= 84256  tag=0x093e0203  vram     (fundo/CLUT)
blk4  size= 53120  tag=0x10710001  vram
blk5  size= 53120  tag=0x106c0002  vram
blk6  size= 99872  tag=0x10b70100  vram     TIM 384x768 3pal -> PELE DO ZUMBI
blk7  size=144964  tag=0x10ee0000  vram
blk8  size= 66592  tag=0x549f0100  vram     TIM 256x512 2pal -> humano (NPC)
blk9  size= 72724  tag=0x54950000  vram
blk10 size= 66592  tag=0x59710100  vram     TIM 256x512 2pal
blk11 size= 72512  tag=0x59f30000  vram
```

---

## 2. Sub-contêiner do bloco de MODELO  ✅

Cada bloco-modelo é, ele mesmo, um contêiner com **diretório no FIM** (mesma ideia do
PLD, com um cabeçalho de 8 bytes na frente):

```
+0x00  u32  dir_off          // aponta p/ o diretório (perto do fim)
+0x04  u32  ngroups          // contagem lógica de grupos (ex.: 4)
+0x08  ...  seções ...
dir_off: u32 nSecoes(=8) ; u32 off1 .. off7    // off0 implícito = 0x08
```

Validação: `dir_off + nSecoes*4 == tamanho_do_bloco`.

### As 8 seções (modelo "completo", ex.: zumbi de R101 blk0)

| Sec | Papel | Observação |
|----:|-------|------------|
| 0 | **EMR + pool de poses A** | esqueleto de 15 ossos, `fs=76` (idêntico ao humano do PLD) |
| 1 | **EDD A** | banco de sequências de animação A |
| 2 | **MALHA (parte 1)** | geometria — **constante** entre variantes da mesma criatura |
| 3 | aux (colisão/sombra?) | pequeno; constante |
| 4 | **MALHA (parte 2)** | geometria; constante |
| 5 | aux | pequeno; constante |
| 6 | **EMR + pool de poses B** | 2º banco (anim de dano/morte); esqueleto igual |
| 7 | **EDD B** | banco de sequências B |

- As seções **0,1,6,7 variam** por sala (conjunto de animações carregado); as seções
  **2,3,4,5 são constantes** (a geometria da criatura não muda). Por isso o catálogo
  (§5) deduplica criaturas por **hash das seções 2+4**.
- O EMR está em `sec+0x0c` (há um `u32` de prefixo em `+0x00` da seção). Reusar
  `pld2gltf.parse_emr` a partir daí funciona.
- **Cuidado**: os cabeçalhos das seções de MALHA (2 e 4) *parecem* EMR pelo heurístico
  (`u16@+4` cai em faixa de nº de ossos), mas **não são** esqueleto — são cabeçalho de
  objeto de malha. O esqueleto real são as seções 0 e 6.

Modelos **menores** (ex.: `R108` blk0, 12 KB) têm só 2 seções (EMR+EDD) e **nenhuma
malha própria** — provável instância que reaproveita geometria de outro bloco, ou
criatura muito simples. Esses casos ainda não foram totalmente classificados.

---

## 3. EMR / EDD / TIM — reuso do pipeline PLD  ✅

- **EMR**: `nBones=15`, `hier_off=100`, `kf_off=176`, `frame_size=76` — **iguais** aos
  personagens humanos. `pld2gltf.parse_emr(b, sec_off+0x0c, sec_end)` decodifica.
  Testado no zumbi de `R101` blk0 sec0: hierarquia `parent=[-1,0,0,2,3,0,5,6,0,8,9,10,8,12,13]`
  (raiz no quadril, cadeia de coluna + 2 braços + 2 pernas — humanoide válido),
  `root_offset=(0,-1839,0)`.
- **EDD**: mesmo formato (registros de 8B + frame-list + pool de poses de 76B, ângulos
  de 12 bits). `pld2gltf.build_anim_clips(b, emr, 0x0c, 0x7c88, 0x7c88, 0x80b8)` extraiu
  **16 clips** (anim00=50 frames, anim01=15, …) a partir de **417 poses** no pool. ✅
  A 2ª dupla (sec6/sec7) é um 2º banco de animações (dano/morte).
- **TIM**: os blocos VRAM que começam com `10 00 00 00` são TIMs 8bpp+CLUT (com 2–3
  paletas empilhadas). `pld2gltf.parse_tim_atlas` decodifica direto.
  - `tools/bin2gltf.py tims <R###.BIN> <outdir>` exporta todos → PNG.

---

## 4. MALHA do PS1 `R###.BIN` — formato in-RAM (HISTÓRICO, não resolvido / não mais bloqueante) 🟡

> ⚠️ **Superado pelo caminho do GOG.** Esta seção documenta a tentativa de decodificar a
> malha **direto do `R###.BIN` do PS1** (reempacotada in-RAM). Ela **não fechou**, mas
> **deixou de ser necessária**: o modelo limpo vem do **EMD standalone do GOG**
> (`emd2gltf.py`, 69/69 exportados — ver topo e [`../decomp/notes/enemy_mesh.md`](../decomp/notes/enemy_mesh.md)),
> cujo esqueleto/anim são idênticos aos do PS1. Mantido como registro técnico.

A geometria das criaturas **não** usa o `MD1` do PLD (que tem `u32` de self-length +
tabela de objetos de 24B + vértices de 8B). Aqui:

- Não há assinatura de self-length; o invariante `nor_off == vtx_off + vcnt*8` do MD1
  **não ocorre**.
- **Vértices têm 6 bytes** (`s16 x, y, z`, **sem** o `pad` do PLD).
- A malha é **objeto-a-objeto** (provável 1 objeto por osso), cada objeto:

```
Cabeçalho do objeto (12 bytes):
  u16 flag0
  u16 flag1 / tpage
  u16 uv_ofs      // offset (rel. ao objeto) do bloco de UV/primitivas
  u16 next_ofs    // offset p/ o próximo objeto
  u16 nVerts
  u16 ?
Vértices:  nVerts x (s16 x, s16 y, s16 z)     // logo após o cabeçalho, em +0x0c
Bloco de UV/primitivas @ uv_ofs:
  contadores + pares (u,v) por vértice + lista de índices de vértice
```

Invariante confirmado do cabeçalho: `uv_ofs == 0x0c + vtx_bytes` e `vtx_bytes ≈ nVerts*6`.

Exemplo decodificado — `R101` blk0 sec4, **objeto 0** (`nVerts=7`, `uv_ofs=0x34`):
vértices `(0,-1839,0) (-27,213,-149) (-24,652,-10) (-13,872,-3) (-27,213,149)
(-24,652,10) (-13,872,3)` — note a **simetria em Z** (`±149/±10/±3`), típica de uma
parte simétrica do corpo. UVs `v≈28..34`, índices `01 04 02 03 05 06`. Em sec2 o
objeto 0 tem `nVerts=9` e é análogo.

**BLOQUEIO ATUAL — estado detalhado do decode da geometria:**

Cada seção de malha tem **apenas 1 objeto** no formato limpo (obj0, no início); o
**grosso** vem depois num **stream de registros de 32 bytes**. Fatos confirmados:

- **Não existe** array de vértices clássico (s16 x,y,z,pad de 8B) em lugar nenhum do
  bloco — varredura por runs longos só acha dados de pose/anim (que também têm valores
  pequenos). Logo a geometria **não** é MD1.
- O stream é composto de **registros de 32 bytes** (em sec4: 7 registros contíguos em
  `+0x64..+0x124`; note que obj0 também tinha 7 vértices). Cada registro começa com
  `u32 N` (0..255) seguido de 3 bytes nulos — por isso aparecem como "marcadores".
- Análise coluna-a-coluna dos 16 `s16` de cada registro de 32B (7 registros de sec4)
  mostra **várias colunas variando suavemente** entre registros vizinhos:
  - col `i4` (byte +0x08): -4096, -1536, 0, 256, 512, 256, 256 — inclui **-4096 = -1.0**
    → forte candidato a **componente de NORMAL** (÷4096).
  - col `i5`: 1023 → 9136 (cresce monotônico).
  - col `i6/i7`: descem/sobem suaves (~±200/passo) — mais normais.
  - cols `i12,i13,i14` (bytes +0x18,+0x1a,+0x1c): `(62,-1852,0) (94,-1906,-1)
    (126,-1959,-3) … (250,-2195,-9)` — **triplet que varia suavemente**, Y na altura do
    corpo → candidato a **POSIÇÃO** (possivelmente cumulativa/delta). Mas ao extrair só
    esse triplet de todos os registros 32B, a nuvem de pontos (45 pts) **não** formou
    silhueta humanoide — então ou a posição é cumulativa, ou o campo certo é outro, ou
    os registros 32B misturam tipos (vértice vs primitiva).
- Em **sec2** (22 KB) há também **super-registros de 52 bytes** (`0x34`) que começam com
  `N=15` (= nº de ossos!) e trazem um valor que **incrementa de +32** (61,93,125,156,…)
  — cheira a **tabela por-osso** (grupo de vértices por osso, típico de malha *skinned*).

**Próximo passo concreto p/ fechar:** decodificar 1 registro de 32B campo-a-campo com
verificação por RENDER — hipótese principal: `[u32 flags/count][s16 nx,ny,nz][s16 x,y,z
posição][s16 u,v / cor]`, com a posição possivelmente **relativa ao osso** (somar o
`world[bone]` do EMR). Renderizar nuvem de pontos frente+lado a cada tentativa até bater
a silhueta; só então montar faces via a tabela de índices (região `+0x280+` em sec4, com
contadores crescentes 1,3,5,7,9,…). Depois amarrar UVs à VRAM (blocos §1) e exportar.

Tudo o mais do pipeline (esqueleto + 16 animações + textura de pele) **já funciona** e
foi verificado; a **geometria é o único item pendente** para gerar o `.glb`.

---

## 5. Catálogo inimigo → sala  (1ª passada)

Deduplicação por **hash das seções de malha (2+4)** de cada bloco-modelo. Identificação
por **render das TIMs** (`tools/bin2gltf.py tims`). Dados completos em
`godot/assets/ENEMY/catalog.json`.

| Hash malha | Salas | Stages | Identificação (por render) |
|---|---:|---|---|
| `605afd27` | 17 | 1(6) 2(3) 3(2) 4(3) 5(3) | **Zumbi macho** — confirmado (R101 blk6: rosto morto, sangue, jeans) |
| `c6c2519f` | 12 | 6(8) 7(4) | **Zumbi** (variante, mais anim) — confirmado (R601 blk5) |
| `5c0244d2` | 10 | 3(2) 4(1) 5(4) 6(1) 7(2) | Criatura orgânica/insetóide (provável **aranha** ou verme) — a confirmar por render de malha |
| `bec9c954` | 5 | 1(5) | a identificar |
| `e284b7c2` | 4 | 1(3) 4(1) | a identificar |
| `34b71bd2` | 3 | 6 7 | a identificar |
| `8d4757e0` | 2 | 1 | a identificar |
| `182209de` | 2 | 4 6 | a identificar |
| (50 hashes distintas no total; 42 aparecem em 1 sala só) | | | |

Salas **sem** modelo dinâmico (loja/save/transição), 29 no total, por stage:
S1=4, S2=6, S3=4, S4=4, S5=3, S6=2, S7=6.

> Observação: alguns hashes com 1 sala e os modelos "menores" (§2) podem ser a **mesma**
> criatura com conjunto de animações diferente (o hash cobre só seções 2+4). A
> identificação definitiva de cada criatura depende de renderizar a **malha** (§4).

---

## 6. Uso da ferramenta

```bash
# manifesto + classificação de blocos de uma sala
python tools/bin2gltf.py info  extracted/ntsc-u/CD_DATA/STAGE1/R101.BIN

# dump do sub-contêiner de um bloco-modelo
python tools/bin2gltf.py model extracted/ntsc-u/CD_DATA/STAGE1/R101.BIN 0

# exporta as TIMs embutidas -> PNG (identificação visual)
python tools/bin2gltf.py tims  extracted/ntsc-u/CD_DATA/STAGE1/R101.BIN _out
```

Caminho canônico (modelo limpo, via GOG):
```bash
# extrai os EMD standalone do port de PC
python tools/rofs_extract.py "<GOG>/Rofs9.dat" C:/tmp/re3pc_emd
# lote: 69 EMD -> godot/assets/ENEMY/*.glb (esqueleto/anim/malha/textura do próprio EMD)
python tools/emd2gltf.py batch C:/tmp/re3pc_emd godot/assets/ENEMY
```

## 7. Próximos passos

1. ✅ ~~Fechar o decoder da malha do PS1~~ — **contornado** pelo EMD do GOG (69/69 exportados).
2. Fechar o mapa **EM##↔nome-canônico** (por render + roster; não é público) e o
   **`type_id(sce_em_set)`↔espécie** — depende do opcode `sce_em_set` no exe ([exe.md §3](exe.md)).
3. Investigar `EM2D.EMD` (layout divergente / corrompido).
4. **IA dos inimigos** (dispatch T64 `0x80097bd4`, **zumbi = tipo 23**): ver [exe.md §3](exe.md)
   e [`../decomp/notes/exe_ai.md`](../decomp/notes/exe_ai.md).
