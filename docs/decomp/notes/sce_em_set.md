# `sce_em_set` — colocação + espécie de personagem/inimigo por sala (opcode SCD 0x7d)

> Fecha a pendência herdada de `scd_gameplay`/`exe_ai.md §5.3`/`sce_enemies.json`:
> **onde e qual inimigo spawna por sala**. Complementa o pipeline de inimigo
> (modelo ✅ `enemy_bin.md` + IA ✅ `exe_ai.md` + HP/dano ✅ `exe_ai.md §3.7` + **ESTE**).
> Ferramenta: [`tools/scd_enemies.py`](../../../tools/scd_enemies.py)
> (`python tools/scd_enemies.py`; `--dry` não grava).
> Marcações: ✅ provado no disasm/bytes · 🟡 inferido/incerto.

---

## 0. TL;DR
- O opcode SCD **`0x7d`** (handler **`0x80056a2c`**) = **spawn de personagem de combate**
  (o `sce_em_set` do RE3): aloca uma **char-struct de `0x1fc` B**, registra no array de
  personagens e copia **classe/type_id, arma, posição (x,y,z), direção e ids** do descritor
  lido do script. **Struct de 24 B decodificada byte-a-byte** (§1). ✅
- Extraídos **1136 spawns de inimigo + 1 boss + 80 NPCs** (dedup) em **137 salas** com
  inimigo, gravados em `godot/data/STAGE*/{sala}_scd.json` no campo **`enemies[]`**
  (doors/items/triggers/flags/messages preservados; o antigo 0x61/0x62 movido p/ `objects[]`).
- **Espécie = `class`(char+0x4a)** na numeração **EM##** (arquivos EMD do GOG, ver
  `enemy_mesh.md`). **Âncora**: sala R101 (zumbi) → class `0x10`; **EM10 = zumbi confirmado**
  (EM10.TIM == R101.BIN blk6). Demais espécies 🟡 (convenção não provada 1:1 no exe).
- **HP**: o descritor do 0x7d **NÃO tem campo de HP** (confirma `exe_ai.md §3.7`). Bônus da
  tarefa = **negativo** (nada novo; o HP segue via member-set do script, `0x80053f84`).

---

## 1. Struct on-disk do opcode 0x7d  ✅ (byte-a-byte no handler `0x80056a2c`)

**Tamanho = 24 (0x18) bytes.** Prova: no fim do handler, `0x80056d9c` faz
`v1 = obj+0x1c ; v1 += 0x18 ; obj+0x1c = v1` (avança o PC do script por 0x18). Bate com
`CONTROLE_VM[0x7d]=24` em `scd_decode.py`.

O descritor é o próprio PC do script: `0x80056a54/60` grava `*(0x800e0198) = obj+0x1c`.
Os campos são copiados p/ a char-struct recém-alocada (`a1`); offsets do descritor:

| off | tam | → char | significado | prova (site) |
|---|---|---|---|---|
| +0x00 | u8  | — | opcode `0x7d` | dispatch VM |
| +0x01 | u8  | — | **não lido pelo 0x7d** (sempre `0x00` nas 169 salas → invariante de assinatura) | — |
| +0x02 | s8  | slot | índice do char no array `gs+0x265c[slot]` (`-1` = sem count) | `0x80056b50` |
| +0x03 | u8  | +0x4a | **CLASSE / type_id** (= id de ESPÉCIE) | `0x80056c64` |
| +0x04 | u16 | +0x46 | **ARMA** (recebe `\|0x100`; bits `0x4000/0x8000` = flags) | `0x80056c78` |
| +0x06 | u16 | +0xd2 | flags de condição/status inicial | `0x80056c84` |
| +0x08 | u8  | +0x09 | id (também → char+0x122 e char+0x12e&7) | `0x80056cb8` |
| +0x09 | u8  | +0x12f | id (seleção de modelo, tabela `0x800e...+0x1498`) | `0x80056bb8` |
| +0x0a | u8  | +0x4b | id | `0x80056ca4` |
| +0x0b | u8  | +0x147 | **MODEL id** (checado vs `0xff` e via `0x80078930`); `0xff` = sem modelo dedicado de sala (NPC/PLD/spawn de mãe) | `0x80056c90` |
| +0x0c | s16 | +0x34/+0x40 | **POSIÇÃO X** | `0x80056c08` |
| +0x0e | s16 | +0x38/+0x42 | **POSIÇÃO Y** (altura) | `0x80056c20` |
| +0x10 | s16 | +0x3c/+0x44 | **POSIÇÃO Z** | `0x80056c38` |
| +0x12 | s16 | +0x6e | **DIREÇÃO / ângulo** (12-bit) | `0x80056c50` |
| +0x14 | u16 | +0xd8 | yaw de mira inicial | `0x80056d00` |
| +0x16 | u16 | +0xda | pitch de mira inicial | `0x80056d0c` |

Notas do handler:
- **Rewrite de classe (player-dependente):** se `gs+0x24d6 (& 0xff) < 8` e `desc[3] ∈ {0x5b,0x5f}`
  e `gs+0x24d6 >= 2`, então `desc[3] = gs+0x24d6 + 0x60` (`0x80056acc..0x80056afc`) — seleção do
  **modelo do player** (Jill/Carlos/costume). Não afeta inimigos (classe 16..44). ✅
- **Registro no array:** `gs+0x213c` (bump `0x1fc`/char), ponteiro em `gs+0x265c+slot*4`,
  fim do array em `gs+0x2704`, contador em `gs+0x2487`. Mesma char-struct de `exe_ai.md §3.7`.
- **Assinatura de extração** (robusta): `byte0==0x7d && byte1==0x00 && 0x08<=class<=0x78 &&
  |x|<32000 && |z|<32000`. Confere com o decode linear por função (`scd_decode`): 1202 em
  funcs limpas, `byte1` = `0x00` em 1202/1202.

---

## 2. type_id (classe) → ESPÉCIE  🟡 (âncora zumbi ✅)

`class` (char+0x4a) é o **type_id de combate**: indexa a **tabela de dano por-tipo** (16..48,
`exe_ai.md §3.7`) e a IA. O **nome** vem da convenção **EM##** dos EMD do port de PC (GOG),
identificados por render em [`enemy_mesh.md`](enemy_mesh.md). Hipótese: **class == número do
arquivo EM## (hex)**.

- **✅ ANCORADO:** R101 (sala de zumbi) usa `class 0x10`, e **EM10 = zumbi macho confirmado**
  (EM10.TIM idêntico ao blk6 de R101.BIN). Sanidade das demais bate com o local no jogo:
  cão `0x20` (ruas Uptown/Downtown), corvo `0x21`, aranha `0x25` (subterrâneos).
- **🟡 IMPORTANTE:** a convenção `class == EM##` **não** está provada 1:1 no exe (o `model_id`
  do descritor, `+0x0b`, é um **slot de modelo carregado por sala**, não o número EM##; varia
  por sala p/ a mesma classe). O `MODEL_TBL 0x800ba728` (`exe_ai.md`) é populado no room-load.
- **🟡 Espaço de id ≠ índice T64:** o `class` (char 0x1fc) vai a `0x71`, > 63 (T64 tem 64
  entradas). É um espaço **diferente** do índice T64 do work-struct 0xD4 (IA), cujos rótulos
  por-tamanho em `exe_ai.md §5.3` também são 🟡. Os dois pools coexistem (ligação 1:1 aberta).

### 2.1 Cruzamento com o CONTEXTO DE SALA (catalog.json) — RESÍDUO EXATO ✅ (honesto)

> Cruzei `class → salas → hash do mesh embutido no R###.BIN` (`godot/assets/ENEMY/catalog.json`,
> que agrupa as salas pelo hash do mesh de inimigo). Integrado em `sce_enemies.json`
> (`class_to_species[*].mesh_hashes/dominant_mesh/dominant_frac/mesh_species_hint`). Achados:

- **Âncora provada (única):** hash `605afd27` = mesh de `R101` = **EM10 = Zumbi** (EM10.TIM ==
  R101.BIN blk6). É o único hash ligado a uma espécie por prova byte-a-byte.
- **PROVA de que `class`↔espécie NÃO é 100% determinável estaticamente** (fecha a pendência honesta):
  1. **`model_id` (desc+0x0b = o SLOT de mesh REAL) é INSTÁVEL por `class`** — ex.: `class 0x10`
     (zumbi) usa `model_id` **25..186** conforme a sala; NPCs (`class ≥0x50`) usam **sempre 0xff**.
     Logo o `model_id` é um **índice de slot carregado por sala**, não nomeia espécie.
  2. **`class`↔mesh é MUITOS-para-MUITOS por sala:** várias classes coexistem numa sala de 1 mesh
     (a sala do zumbi `605afd27` hospeda 0x10, 0x1e, 0x34…), e uma classe aparece em salas de meshes
     diferentes. **Até a classe-âncora `0x10` concentra só ~0,25** no mesh do zumbi (`dominant_frac`).
  3. Conclusão: a **espécie só se resolve em RUNTIME** (qual mesh a sala carregou no slot `model_id`).
     O **máximo bound estático** = o `dominant_mesh` da classe + a convenção `EM##`.
- **Máximo defensável entregue:** `sce_enemies.json` agora traz, por classe, o **perfil de mesh de
  sala** (`mesh_hashes`, `dominant_mesh`, `dominant_frac`) e o `mesh_species_hint` só quando há
  concentração real (`frac ≥ 0.4`) sobre o hash provado. A convenção `class == EM##` segue como
  nomeação (19/62 ALTA/MEDIA), agora **com o contexto de sala como checagem de consistência** —
  não como prova. O resíduo é o mapa canônico `EM##↔espécie` que **não existe estaticamente no EXE**
  (nem tabela de nomes, nem link `class→model_id` fixo).

### Mapa (resumo; tabela completa em `godot/data/sce_enemies.json`)
| class | espécie | conf | salas | placements |
|---|---|---|---|---|
| `0x10` | Zumbi (macho) | **ALTA** | 14 | 59 |
| `0x11`–`0x1f` | Zumbi (variantes) | MEDIA | — | ~500 |
| `0x20` | Cão zumbi (Cerberus) | MEDIA | 17 | 53 |
| `0x21` | Corvo | MEDIA | 9 | 98 |
| `0x22`/`0x23` | Hunter β / γ | BAIXA | 17/11 | 50/34 |
| `0x25` | Aranha gigante | MEDIA | 5 | 15 |
| `0x26` | Aranha (cria/pequena) | BAIXA | 5 | 21 |
| `0x28` | Drain Deimos | BAIXA | 9 | 27 |
| `0x30`/`0x33` | Verme (Grave Digger?) — EM30/EM33 alongados no render | BAIXA | — | — |
| `0x32` | Verme (Sliding Worm?) — EM32 alongado | BAIXA | 7 | 54 |
| `0x34`/`0x35` | Insectoide (Drain Deimos / Brain Sucker) — EM34/EM35 render | BAIXA | — | — |
| `0x3e`/`0x3f` | **HELICÓPTERO / veículo** (EM3E/EM3F = helicóptero no render ✅; salas R50E/R50A STAGE5) — **corrigido** (era "verme") | BAIXA (class-link) | 1/1 | 1/1 |
| `0x34` | **ubíquo (37 salas) — a confirmar** (não parece criatura rara) | BAIXA | 37 | 91 |
| `0x38` | Nemesis (?) — 1 sala (R50D), `model_id=0xff` | BAIXA | 1 | 1 |
| `0x50`–`0x71` | NPCs humanos (Nicholai/Carlos/Mikhail/Brad…) | categoria | — | 80 |
| `0x00`–`0x07` | Player/aliado (campo `actors[]`, não `enemies[]`) | — | — | — |

> ⚠ `0x34` em **37 salas** (e vários spawns em `(0,0,0)` = template de evento) contradiz uma
> criatura específica rara → rótulo **neutralizado** ("a confirmar"). Nemesis via `0x7d` é raro
> porque o **chase** do Nemesis é dirigido pelo **evento de boss** (opcode `0x25`, struct
> `0x800e01c0`; `exe_ai.md §5.2`), não por char-spawn.

### 2.2 CAMADA DE ANOTAÇÃO por EMD (`emd_annotations` em `sce_enemies.json`) ✅ (honesto)

A nomeação de espécie é uma **CAMADA DE ANOTAÇÃO** sobre o dado — **não** prova. A extração
do `0x7d` é 100% byte-a-byte (`class`, arma, pos, dir, ids); a espécie **por-nome** não é.
Anotei os **69 EMD** (arquivos do port PC/GOG) por (a) render texturizado front (montage de
1 launch, `tools_enemy_montage.gd`), (b) roster canônico RE3, (c) nº ossos/verts/anims +
contexto de sala. Confiança do render por EMD (campo `render_conf` em `emd_annotations`):

| conf | nº EMD | quais |
|---|---|---|
| **ALTA** | 6 (8.7%) | EM10 zumbi (byte-prova), EM20 cão, EM21 corvo, EM25 aranha, **EM3E/EM3F helicópteros** |
| MEDIA | 24 | EM11–EM1F zumbis, EM22/EM23 hunters, EM28/EM34/EM35 insectoides, EM30/EM32/EM33 vermes, EM38 Nemesis(?) |
| categoria (humano) | 26 | EM50–EM71 (é NPC humano sem dúvida; **qual** humano não fecha) |
| BAIXA | 13 (19%) | fragmentos 1–6 ossos (EM26/EM27/EM37/EM39/EM3B/EM40) + humanoides genéricos (EM24/EM2C/EM2E/EM2F/EM36/EM3A) + **EM2D** |

**ALTA+MEDIA = 43.5%**; **categoria-ou-melhor = 81.2%** (só 19% ficam sem categoria).

- **Ligação `class → EMD` = CONVENÇÃO `class == EM##` (hex)**, provada só na âncora
  `0x10 ↔ EM10`. Logo a confiança da *espécie por class* é o **mínimo** entre (render do EMD)
  e (convenção class↔EMD). Por isso `class_to_species[*].conf` continua conservador mesmo
  quando o EMD tem render ALTA — o link é o elo fraco.
- **`class_to_species[*].emd_annotation`** cruza cada class com a anotação do EMD de mesmo nº.
- **RESÍDUO HONESTO (inevitável):** o mapa canônico `EM##↔espécie` **não existe estaticamente
  no EXE** (sem tabela de nomes; §2.1) e **não está publicado 1:1** (busca web jul/2026: só o
  esquema EMD do RE1 é público, numeração diferente; para RE3 as wikis listam o *roster* de
  espécies, não o nº do arquivo). Assim, os 19% BAIXA e a distinção fina (Hunter β vs γ, qual
  NPC) são resíduo **da fonte**, não do nosso trabalho — a espécie fina só resolve em runtime.
- **Correções deste round:** EM3E/EM3F = **helicópteros** (não vermes; render + salas STAGE5);
  **EM2D** deixou de ser "corrompido" (bug de parser em `emd2gltf.py`, ver `enemy_mesh.md`) e
  exporta íntegro — mas o render não identifica a espécie (BAIXA).

### 2.3 Reabertura do linkage: existe TABELA ESTÁTICA `type→EM##` no EXE?  → **NÃO** (provado em 3 níveis)

> Hipótese testada (o usuário): "os inimigos têm tags/ids — deve haver tabela estática
> `type(char+0x4a) → fileid EM##`, análoga à de portas `0x8009dfd0[stage][room]`". Investiguei
> o EXE `SLUS_009.23` (base `0x80010000`, capstone), o `R###.BIN` e a ARD. **Resultado: não existe.**

1. **EXE não tem tabela de NOMES por type.** As **únicas** strings de modelo no EXE são
   `bio19/room/emd/em10.tim` (@file `0x88300`/vaddr `0x80097b00`), `.../em10.emd`
   (`0x88328`/`0x80097b28`), `.../emd08/em10.emd` (`0x88350`/`0x80097b50`). Só **"em10"** — não
   há `%02X`/`%d` nem uma string por type — e **nenhuma** é referenciada por ponteiro u32 no EXE
   ⇒ **leftovers de dev, mortos**. Não há construção de nome de arquivo por type.
2. **O spawn escolhe o modelo por SLOT, não por type.** No handler `0x80056a2c`, o modelo vem de
   `desc+0x0b` (**model_id**), checado contra um **BITMAP de modelos carregados** em `gs+0x7890`
   via `0x80078930` (bit-test `word[model_id>>5] & (1<<(model_id&0x1f))`); se o bit não está
   setado, o spawn é **abortado** (`0x80056aa8`→`0x80056d94`). O `type` (`desc+0x03`) só vai p/
   `char+0x4a` (AI/dano) — **não deriva arquivo**. `model_id` é um índice de modelo carregado por sala.
3. **O room-load não carrega por type.** O loader de modelo (`0x800137f0`+, chama `0x800150b0`)
   **itera a tabela de blocos do `R###.BIN`** (stride 8: `size@0`, `tag@4`) e carrega cada bloco
   pelo **tag = endereço de RAM** (`0x80xx0000` p/ modelo). O tag é destino de carga, **não** id de
   type. A `MODEL_TBL 0x800ba728` (chave = type) é **RUNTIME**, populada no room-load. A ARD (SCD)
   posiciona por opcode, sem tabela `type→modelo`.

**Confirmação empírica (todos os ids estáveis são m:n):** o PS1 embute só **1-2 meshes de inimigo
por sala** (limite de RAM) e reusa em todos os spawns. `model_id→mesh` = 83/189 único; `class→mesh`
= 15/47 — **ambos contaminados** (a mesh única da sala serve várias classes/model_ids). Por
**TIM byte-idêntico** (ground truth) 35 salas casam o skin de inimigo com um `EM##.TIM` do PC: a
mesh `605afd27` aparece com os TIM `EM10`/`EM18`/`EM1B` ⇒ `605afd27` = **família ZUMBI** (vários
skins, um mesh); e um mesmo tamanho de TIM (99872) tem 2 texturas distintas (`EM10` vs `EM23`).

**Conclusão honesta:** a intuição do usuário está certa quanto a **existirem ids estáveis** (o
`type`=`char+0x4a` para IA/dano; a identidade de mesh/TIM), mas **não há tabela estática canônica
`type→EM##`/espécie** — o vínculo espécie↔modelo é feito em **room-load** a partir dos blocos
embutidos no `R###.BIN` (sem type-tag). O melhor bound estático = **mesh embutida por sala**
(byte-casável a `EM##` via TIM) **+ classe dominante**. A confiança **não** foi elevada a ALTA por
convenção porque **não há tabela que a sustente**; a única âncora byte-provada segue sendo a
**família Zumbi** (`605afd27`, 14 salas por TIM byte-idêntico). Detalhes/endereços em
`sce_enemies.json → _meta.linkage_investigation`.

---

## 3. Formato do `enemies[]` gravado
Por spawn (dedup por `(class,x,y,z,dir,weapon)`; `occurrences` = nº de declarações — branches de
cenário Jill/Carlos/dificuldade):
```json
{ "class":16, "class_hex":"0x10", "species":"Zumbi (macho)", "species_conf":"ALTA",
  "kind":"enemy", "x":-26040,"y":-1800,"z":-14630, "dir":448,
  "weapon":0, "slot":0, "model_id":25, "status_flags":0,
  "ids":[..], "aim":[..], "occurrences":1, "opcode":125, "raw":"7d00..." }
```
`kind ∈ {enemy, boss, npc}`. `actors[]` = player/aliado (class < 0x10). `objects[]` = antigo
0x61/0x62 (modelos de objeto posicionados, preservado).

---

## 4. HP inicial do inimigo (bônus da tarefa)  — negativo ✅
O descritor do `0x7d` **não** carrega HP (nenhum campo copiado p/ `char+0xcc`). Confirma
`exe_ai.md §3.7`: HP do inimigo/boss = `char+0xcc`, setado por **script** (member-set
`0x80053f84` / sub `0x80051b9c`), não pelo spawn. `desc+6 → char+0xd2` = flags de status
(não HP); `desc+0x14/0x16 → char+0xd8/0xda` = mira. **Sem tabela de HP-por-tipo no descritor.**

---

## 5. Endereços-chave
```
0x80056a2c  handler do opcode SCD 0x7d (sce_em_set / spawn de char de combate)  ✅
0x800e0198  ptr do descritor (= obj+0x1c, PC do script)                          ✅
0x80056d9c  avanço do PC += 0x18 (prova do tamanho = 24 B)                        ✅
0x80056acc  rewrite de classe player-dependente (desc[3] 0x5b/0x5f -> modelo)     ✅
0x80078930  checa se o MODEL id (desc+0xb) está carregado                          ✅
char+0x4a   CLASSE/type_id (= id de espécie) ; char+0x46 arma ; char+0x6e dir      ✅
char+0x34/38/3c  posição X/Y/Z ; char+0xcc HP (setado por script, não pelo 0x7d)   ✅
```
