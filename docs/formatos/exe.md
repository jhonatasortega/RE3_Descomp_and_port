# Executável `SLUS_009.23` — engenharia reversa (RE3 PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `player_sm`, `aim_shoot`, `ai`, `door_handler`, `item_logic`)
> - **Formato:** executável PS1 (MIPS R3000A, little-endian); desmontagem por capstone (sem Ghidra/radare2)
> - **Extensão/origem:** `SLUS_009.23` (868.352 B; base `0x80010000`)
> - **Ferramenta:** [`tools/exe_parse.py`](../../tools/exe_parse.py), [`exe_dispatch.py`](../../tools/exe_dispatch.py), [`exe_combat.py`](../../tools/exe_combat.py), [`exe_ai.py`](../../tools/exe_ai.py), [`exe_items.py`](../../tools/exe_items.py)
> - **Decompilado:** **100%** SM/anim do player (`player_sm`) · **100%** lógica de item (`item_logic`, core) · **100%** mira/tiro (`aim_shoot`) · **55%** IA · **0%** handler de porta (destino de sala)
> - **Feito:** header, física root-motion, índice de anim (`player+0xc8`), multi-banco EDD (PLW); **SM completa do player** (8 ações macro + 16 rotinas, incl. r10/r12/r15 e anim19/20 resolvidos); **HP/dano do player** (`+0xcc`, máx 200; dano `0x8003dd7c`); **mira/tiro** (pad `0x500`, auto-lock, hitscan `0x80044804`, geometria de altura `0x8003ac90`, timing `0x8009cf28`); **IA do zumbi** (T64, tipo 23); **item_logic** (flags `0x8009e3f8`, inventário, pegar/usar/combinar).
> - **Falta:** **handler de porta** (→ destino de sala, Fase B1), **HP/dano do inimigo** (data-driven, requer RAM-watch), Nemesis (`0x800e01c0`, evento scriptado). Ver [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md) e as notas em `../decomp/notes/` (`exe_combat.md`, `exe_ai.md`, `exe_items.md`).
> - **Correções aplicadas neste round:** `player+0xcc` = **HP** (não "momentum"); tier de anim 3×3 = **zona de saúde/mancar** (não velocidade); interpretador do SCD de sala = **`0x8009e0f8`** (o `0x8007688c` é a **VM de IA de entidade**); cluster `0x80091000` **não é IA** (é libc); anim19/20 = **em aberto** (mira vs dano). Detalhes abaixo.

> Desmontagem do executável do jogo (MIPS R3000A, little-endian) com **capstone**.
> Ferramentas: [`tools/exe_parse.py`](../../tools/exe_parse.py) (loader + xref + disasm)
> e [`tools/exe_dispatch.py`](../../tools/exe_dispatch.py) (acha tabelas de salto
> indexadas por propagação de constantes). Sem Ghidra/radare2 no ambiente. Tudo abaixo é
> derivado dos **bytes reais** do executável e cruzado com os dados de sala
> (`godot/data/STAGE*`) e com GameShark público (NTSC-U).

---

## 1. Cabeçalho PS1-EXE  ✅

Header de `0x800` bytes; código carrega logo depois em `base`.

| offset | campo | valor |
|---|---|---|
| +0x00 | magic | `"PS-X EXE"` |
| +0x10 | entry (pc) | **`0x80011b80`** |
| +0x14 | gp (r28) | `0x00000000` |
| +0x18 | **load addr / base** | **`0x80010000`** |
| +0x1C | **tamanho do texto** | **`0x000d3800`** (866.304 B) |
| +0x30 | sp/fp inicial | `0x801ffff0` |
| +0x4C | região | `"Sony Computer Entertainment Inc. for North America"` |

Invariante: `0x800 + tsize == tamanho do arquivo` (868.352 B) ✅.
**Mapeamento vaddr↔offset:** `file_off = vaddr - 0x80010000 + 0x800`.
O código válido vai de `0x80010000` a `0x800e3800` (`vend`).

### Como desmontar
`capstone.Cs(CS_ARCH_MIPS, CS_MODE_MIPS32 + CS_MODE_LITTLE_ENDIAN)`. O `.text`
**mistura código e dados** (jump tables e rodata no meio), então o `disasm` do
capstone para no primeiro word inválido — a varredura linear precisa **pular 4 bytes**
e continuar (`Exe.disasm_all()`). Isso rende ~200.233 instruções (2.166 `jr`,
243 `jalr`, 7.035 `lui`).

---

## 2. Tabelas SCE — o que são de fato  ✅ (correção importante)

A hipótese inicial (o `sat_type` dos *events* seria o item, e o `type` das *entities*
seria o inimigo) **não se confirma**. O que os campos realmente são:

### 2.1 `sat_type` (events, opcode 0x63/0x64) = **enum SCE de TRIGGER**  ✅ ALTA
É o byte `sce` (offset +2 do opcode). Mesmo enum do motor RE2/RE3. A distribuição real
nas 169 salas casa exatamente com o enum conhecido (ver `godot/data/sce_items.json`):

| sce | nome | count | | sce | nome | count |
|---|---|---|---|---|---|---|
| 4 | SCE_MESSAGE | 393 | | 9 | SCE_SAVE | 16 |
| 5 | SCE_EVENT | 229 | | 10 | SCE_ITEMBOX | 5 |
| 6 | SCE_FLAG_CHG | 42 | | 11 | SCE_DAMAGE | 8 |
| 7 | SCE_WATER | 9 | | 12 | SCE_STATUS | 9 |
| 8 | SCE_MOVE | 16 | | 14 | SCE_WINDOWS | 5 |

Não aparecem `SCE_DOOR`(1)/`SCE_ITEM`(2) porque **porta usa opcode dedicado 0x67** e
**item usa opcode dedicado** (não o 0x63). → **o item_id das salas ainda não está
extraído**; falta varrer o opcode de item.

### 2.2 `type` (entities, opcode 0x61/0x62) = **índice de modelo de objeto/NPC**  ✅ ALTA
Não é enemy_id: aparece em 165/169 salas e o `type` inclui valores de flag
(`0xF0`, `0xF8`). São modelos posicionados (objetos/NPCs), não a lista de inimigos.

### 2.3 Dispatcher de objeto/tarefa `T64` @ **`0x80097bd4`**  ✅
Tabela de **64 ponteiros de handler**. Referenciada em `0x8001bb64` e `0x8001d034`.
O laço principal de objetos itera work-structs de **`0xD4` (212) bytes** e faz:
```
lbu  $v0, ($s1)        ; rotina/tipo = 1º byte do objeto (0..63)
sll  $v0, $v0, 2
addu $v0, $v0, $s2     ; s2 = 0x80097bd4
lw   $v0, ($v0)
jalr $v0               ; chama handler; $a0 = work-struct
```
Vários slots são stubs `jr $ra` (tipos não usados): idx 0, idx 9..15, 45..50 — padrão
típico de tabela com IDs reservados. O **item-em-mundo é um desses tipos de objeto**.

### 2.4 Opcode de ITEM `0x68` (sce_item_aot_set)  ✅ ACHADO (round 2)
O item no mundo usa o opcode **`0x68`** (logo depois da porta `0x67`), estrutura de
**~30 bytes** = header 6B + 4 pontos (quadrilátero) + payload de item:
```
68 [aot] 02 [sat=31] [floor] 00  [4 pontos s16 = 16B]  [item_id:u16][amount:u16][idB:u16][flags:2]
```
`item_id` no **offset +22** (confirmado por consistência em salas duplicadas: R104=R11F,
R108=R122). **14 itens reais** extraídos em 7 salas (`tools/scd_items.py` → `rdt.script.items`
+ `godot/data/sce_items.json`). Ex.: `id=0x15 x30` (**Hand Gun Bullets**, ver §2.7),
`id=0x04 x7`.
> ⚠️ `0x68` é **minoria** (zonas de item/munição auto-pega). A maioria dos itens visíveis
> são **modelos de objeto** (entities `0x61/0x62`) apanhados via **evento de script** — o
> `item_id` desses está na lógica do evento, ainda não extraído.

### 2.6 Porta = PAR de opcodes `0x67` + `0x7f`  ✅ (correção: não é "1 opcode de 62B")
> **Correção (round VM).** A "porta de 62 bytes" **não é um opcode só** — é o **par**
> `0x67` (**22 B**, gatilho/`door_aot_set`, handler `0x800574f4`) **+** `0x7f` (**40 B**,
> destino/chegada, handler `0x80056510`) = 62. Os handlers da VM de sala (§ "Interpretador
> SCD") dão os tamanhos exatos. A extração atual, ancorada no marcador de chegada, dá
> **481 portas** (todas com posição de chegada) → `room_graph.json`. Ver
> [scd_gameplay.md §2.1](scd_gameplay.md) e [SCD.md §2](SCD.md).

- **CHEGADA (100% ✅):** o handler `0x800248e4` lê o descriptor de porta e grava a posição
  de spawn. Campos on-disk: `to_x/y/z/facing`. Confirmado nas 481 portas.
- **DESTINO (stage/room) 🟡 — provado que NÃO é campo estático do SCD.** O `0x7f` lê
  `byte@+9` como seletor de banco/sala, mas nos **653** opcodes `0x7f` reais esse byte é
  **sempre 0** (banco default) → o par (stage,room) é **resolvido em runtime**
  (indireção por door-index + estado do motor), não copiado do bytecode. Busca exaustiva de
  reciprocidade satura em ~15%. O caminho definitivo é o **handler de porta**
  (`0x800248e4`) + tabela de fileids `0x8009dfd0[stage][room]` + loader `0x800493ec`
  (ver nota `../decomp/notes/door_handler.md`).

### 2.7 Itens — correções de nome (charset decodificado)  ✅
O texto do RE3 usa **fonte própria** (byte→glifo), agora decodificada (`tools/re3_text.py` →
`godot/data/re3_items.json`; **193 IDs**, 168 com nome, 115 com exame). Correções ao que
antes eram palpites:
- **`0x2A` = First Aid Box** (NÃO "First Aid Spray"); **`0x20` = First Aid Spray**;
  **`0x0A` = Rocket Launcher**; **`0x15` = Hand Gun Bullets** (×30 casa com o `amount` do SCD);
  `0x01` = Knife, `0x21` = Green Herb, `0x41` = Lighter Oil, `0x42` = Lighter.
- Detalhes/âncoras de alinhamento em `../decomp/notes/messages.md`.

### Interpretador SCD — CORREÇÃO de arquitetura  ✅
> **Correção (round VM).** Havia **três** VMs confundidas. O **interpretador do bytecode do
> SCD de sala** é a **jump-table `0x8009e0f8`** (256 entradas u32, copiada p/ o scratchpad
> `0x1f800000` no boot da sala; loop `0x80052ba4`, dispatch `0x80052c48`, PC em `obj+0x1c`;
> init de thread em `0x80052474`). **NÃO** é o `0x8007688c` (que é a **VM de IA de
> entidade/inimigo**) nem o `0x8009e0bc`/`0x80050aac` (**VM de evento/AOT per-frame**, que
> consome os AOTs criados pelo script e dispara a troca de sala via `gs+0x2154`/flag
> `0x800c7960`). O antigo "`0x80090xxx` = `vsprintf` da libc" segue correto (não é VM).

Cada handler lê seus operandos do PC e **avança o PC por N bytes** → os tamanhos vêm dos
avanços dos handlers (verdade do binário), integrados em `tools/scd_decode.py` (`VM_SIZES`).
Com isso **97,1%** das funções das 169 salas fecham exatamente em `evt_end` (era 63,6%).
Tabela completa em [SCD.md §2](SCD.md) e `../decomp/notes/scd_opcodes.md`.

### 2.5 Modelos de arma (cross-reference de item)
`CD_DATA/PLD/PL00W00.PLW..PL00W14.PLW` = **21 modelos** (`0x00..0x14`). Confirma a
quantidade de armas equipáveis; o `weapon_model_id` é subconjunto/renumeração do
`item_id` (não idênticos). Gráficos de item: `ETC/ITEMI.PIX`, `ITEMG.PIX`, `ITEMA.SLD`.

> **Saídas:** `godot/data/sce_items.json` (enum SCE + lista item_id de referência +
> pendências) e `godot/data/sce_enemies.json` (dist. de type + evidências de IA +
> roster). Os nomes item/inimigo vêm de conhecimento público do RE3 (o executável
> **não tem strings ASCII** de nomes — usa fonte própria), com nível de confiança
> marcado por entrada.

---

## 3. IA de inimigo — dispatch por objeto (T64)  ✅ (correção importante)  → `../decomp/notes/exe_ai.md`

> ⚠ **CORREÇÃO ao texto anterior:** o "cluster de IA `0x80091000..0x80094600`" e o "array de
> estado `0x800b9d28`" **NÃO são IA** — `0x80091xxx` é o `vsprintf`/formatador da libc e
> `0x80094xxx` é dado. A IA real está na **tabela de handlers de objeto T64 `0x80097bd4`**.

- **Loop único de objetos = `0x8001bb24`:** itera work-structs de **0xD4 (212) bytes** (até
  96 slots; bounds em `0x80098084/88`), lê o **tipo** no byte 0 e chama
  `T64[tipo]` (`0x80097bd4`, 64 ponteiros; stubs `jr $ra` nos índices 9..15 e 45..50). O
  **player não** está neste array (struct dedicada em `0x800ccbc4`).
- **Zumbi = tipo 23** (handler `0x8001e444`, o maior — 3524 B): máquina de 5 estados
  (tabela `0x800103f8`): 0 idle/vagar · 1 perseguir · 2 atacar · 3/4 morte. Hitboxes
  **corpo `0x41` / cabeça `0x42`**; `rand` = `0x800102e8`; driver de locomoção `0x8001b35c`.
- **Struct do inimigo (0xD4):** `+0x02` fase (0 init/1 ativo/2 morrendo), `+0x18` estado de IA,
  `+0xb8` timer de **stagger/hurt** (congela a IA), `+0xba` ângulo, `+0xbc` ossos/hitbox,
  `+0x34` posição 3D.
- **HP/dano do inimigo 🟡:** o `HP -= dano` **não** está no handler do inimigo nem no caminho
  de disparo do player (varredura negativa) — é **data-driven pela EMD/EMR** (partes de hitbox
  que o inimigo oferece ao auto-lock `0x800445c8`); fechar exige **RAM-watch** (candidato: hword
  em `+0xb0..+0xb4`). Tabelas de arma: **fogo** `0x8009ce88` (16 ptrs), **stats/timing**
  `0x8009cf28` (21×3B) — a coluna de dano-vs-inimigo é outra, ainda não isolada.
- **Nemesis 🟡:** dirigido por **evento scriptado** sobre struct dedicada `0x800e01c0` (não é
  work-struct de 0xD4), armado pelo opcode SCD `0x80058c70` e gateado pelo global
  `gs+0x77f4 | 0x200`. Candidatos de handler comum: t21 `0x8001d7d0`, t41 `0x80020eb8`.
- **type_id → espécie 🟡:** ainda **em aberto** (falta decodificar `sce_em_set`); o mapa
  tipo-de-objeto→espécie é **estrutural** (por complexidade da IA), não byte-a-byte. Ver
  [scd_gameplay.md §4.1](scd_gameplay.md) e [enemy_bin.md](enemy_bin.md).

---

## 4. Física / movimento do player  ✅ (round 4)  → `godot/data/physics.json`

**Achado central:** o movimento do RE3 é **root-motion** (dirigido por animação). **Não há
constante escalar de velocidade no exe** — o deslocamento por frame vem de **vetores de
movimento por POSE**, guardados na tabela de poses do personagem (carregada de `PL00.PLD`),
rotacionados pela direção atual e somados à posição no mundo.

### 4.1 Sistema de ângulo  ✅ ALTA
- **12 bits: `4096 = 360°`** (0.0879°/unidade). Meia-volta = `2048`. Confirmado por
  `andi ang,0xfff` e o bit de menor-rotação `andi ...,0x800` no controlador
  (`0x8001a248..0x8001a5b0`, que faz o *smoothing* de giro tank-control).

### 4.2 Tabela seno/cosseno  ✅ ALTA
- **`0x800a3310`** (file `0x93b10`): **quarto de onda**, **1025 × s16** (índices 0..1024 =
  0°..90°), amplitude **4096** (ponto-fixo 12b). *(não é círculo completo)*
- `rsin(a)` por simetria: `[0,1024)→T[a]`, `[1024,2048)→T[2048-a]`, `[2048,3072)→-T[a-2048]`,
  `[3072,4096)→-T[4096-a]`; `rcos(a)=rsin(a+1024)`.
- Usada pela lib GTE (matrizes de rotação) em `0x80088000+`.

### 4.3 Integração (root-motion)  ✅ estrutural
```
pos_mundo += rotate(pose_motion_vec, facing_angle)   // rotação via matriz do modelo (sin table)
```
- **Função de controle do player:** `0x8001a248` (lê pad, escolhe pose, aplica motion).
- **Struct do player:** `+0x74` ângulo de direção; `+0x108` ponteiro da **tabela de poses**
  (stride **`0xbc`=188** por pose; **motion em `pose+0x54..0x60`**; param de giro em `+0x62`);
  `+0x114` estado 2º; `+0x120` **pad segurado** (`0x10`↑ `0x20`→ `0x40`↓ `0x80`← `0x800`R1);
  `+0x121` pose/rotina atual; `+0x164/166/168` contadores de interpolação.
- **Setter da tabela de poses:** `0x80026184` (`sw a1,0x108(a0)`; `a1` vem do parse de `PL00.PLD`).

> **Nota de reconciliação de offsets:** o **mapa autoritativo e consolidado** do player-struct
> (base **`0x800ccbc4`**: `+0x04` action, `+0x05` routine, `+0x6e` ângulo de direção, `+0xc8`
> anim, `+0xc9` frame, `+0xcc` HP, `+0xce` HP máx, `+0xd3` condição, `+0x46` arma, `+0x4a`
> postura, `+0x16c/0x170` alvo) está em `../decomp/notes/exe_combat.md §5`. Os offsets acima
> (`+0x74`, `+0x108`, `+0x120`, `+0x121`) são de uma leitura anterior por outra base/framing —
> onde divergirem (ex.: direção `+0x74` vs `+0x6e`), **o mapa do exe_combat.md é o autoritativo**.

### 4.4 Unidades e velocidades
- **Escala do mundo (medida dos ARDs):** span de sala mediana **X≈19150, Z≈15250** unidades
  (124 salas); caixas de porta ~900–2560 un. **FPS de gameplay ≈ 30** (NTSC 60Hz / 2).
- **Velocidades escalares = ESTIMATIVA** (os valores reais são root-motion em `PL00.PLD`,
  campo `pose+0x54`). Estimativas: andar ~90 un/frame (~2700 un/s), ré ~metade, giro
  ~100 un-ângulo/frame. Quick-turn = 2048.
  > ⚠ **Corrigido:** a afirmação anterior "um único jog (sem botão de correr)" foi
  > **refutada** — há **andar** (rotina r1, bit UP) e **correr** (rotina r3, `pad & 0x04`)
  > distintos na SM (ver §4-B.2). O andar = `anim00`/PLW-seq0, correr = `anim10`/PLW-seq1.

> Pendência: extrair os vetores `pose+0x54` reais de `PL00.PLD` (poses de andar/virar) p/
> substituir as estimativas; confirmar passo de física 30 vs 60 fps.

---

## 4-B0. CORREÇÃO CRÍTICA (round 6): o player usa MÚLTIPLOS bancos EDD — a locomoção ARMADA vem do PLW, não das 22 do PLD  ✅

> Ferramentas: [`tools/find_anim_banks.py`](../../tools/find_anim_banks.py) (mede o
> root-motion dos bancos EDD de qualquer PLD/PLW e marca andar/correr).
> **Esta seção corrige o pressuposto de 4-B/4-B.1** ("`player+0xc8` é 1:1 com `animNN`
> **do PLD**"). O índice `0xc8` é real, mas o **ponteiro-base do EDD que ele indexa é
> SELECIONADO em runtime** entre vários slots do player-struct — nem sempre é o PL00.PLD.

### O sistema é MULTI-BANCO
`player+0xc8` (seq) `<<3` indexa o EDD apontado por **`a2`** na função de tocar animação
`0x80018ec8` (`s3=a2`). O caller (`0x800168b8`) escolhe `a2` entre **quatro pares
(pose,EDD)** do player-struct conforme **arma/postura** (`player+0x4a` e bit `0x80` de
`player+0x150`):

| par (pose / EDD) | quando | ORIGEM dos dados |
|---|---|---|
| **`0xe8` / `0xec`** (default) | desarmado / arma guardada | **PL00.PLD** (as 22 seqs + 531 poses) |
| `0xf0` / **`0xf4`** | arma equipada (postura A) | **PLW da arma equipada** |
| `0xf8` / **`0xfc`** | arma equipada (postura B) | PLW |
| `0x100` / **`0x104`** | arma equipada (postura C) | PLW / composto |

- **Banco default = PL00.PLD.** No spawn da Jill, `0x80038aac` faz
  `fileid = tabela[0x8009cd10][char]` (char 0 → **fileid 108 = PL00.PLD**, casa por
  tamanho exato **159116**), carrega via `0x80012818` e faz
  `sw (base+dir[0]),0xec` / `sw (base+dir[1]),0xe8` → 0xec = **EDD do PLD**, 0xe8 = pool EMR.
  A tabela `0x8009cd10` é **personagem→PLD** (108=PL00, 131=PL01, …, 145=PL08/Carlos,
  168=PL09, 191=PL0A, 218=PL0F — todos casam por tamanho).
- **Bancos armados = PLW.** Ao **equipar arma** (`0x80043be4`):
  `lbu 0x4a(char); lbu 0x46(weapon); fileid = weaponBase[char](0x8009dcb4) + weapon;`
  `jal 0x80012818` (carrega o **PLW**); `sw (base+dir[0]),0xf4`; `sw (base+dir[1]),0xf0`.
  Confirmado por tamanho exato: weapon0→fileid110→**PL00W00.PLW**(43904),
  1→**PL00W01**(44608), 3→**PL00W03**(44560), 5→**PL00W05**(48028).

### Cada PLW carrega um banco de CORPO INTEIRO (andar/correr segurando a arma)
`PL00W00.PLW` (handgun) tem, entre seus 9 sub-blocos, **3 pares EDD+EMR**. O **banco0**
(EDD@0x8, EMR@0x438) é **corpo inteiro**: `nBones=15`, `frameSize=76`, **18 seqs**,
**399 poses**. Root-motion medido (`find_anim_banks.py`):

| seq | nf | net(x,z) | ~un/frame | papel |
|----|----|----|----|----|
| **0** | 30 | (+2277, 0) | ~76 | **ANDAR frente** (loopável) |
| **1** | 20 | (+4437, 0) | ~222 | **CORRER frente** |
| 3 | 34 | (+2121, 0) | ~62 | andar (variante/tier) |
| 4 | 20 | (+4022, 0) | ~201 | correr (variante) |
| 2/5/8 | — | (0,0) | 0 | parado/mira |
| 9 | 30 | (−2051, 0) | ~68 | ré / giro |

Bancos 1 e 2 do PLW são **parciais** (7 e 9 ossos) — overlays de tronco/mira sobrepostos.

### Veredito
- **A percepção do usuário está correta:** na jogabilidade a Jill está sempre com uma
  arma na mão, então o **ciclo de ANDAR/CORRER que se vê vem do banco do PLW equipado**
  (ex.: `PL00W00.PLW` seq0=andar/seq1=correr), **NÃO das 22 seqs do PL00.PLD**.
- As **22 do PL00.PLD** são o set BASE/desarmado (usado no banco default 0xec) + ações
  que valem sempre (dano `anim19/20`, apanhar `anim08`, idle-wait `anim21`). O
  `anim00` do PLD (~58/f, −X) é o andar-base **desarmado** — parecido, mas é OUTRO clipe.
- Pendência p/ 100%: ler `player+0x150`(bit0x80)/`0x4a`/`0xc8` num save-state andando
  **com arma** p/ fixar qual índice do banco-PLW o seletor usa em cada tier.

---

## 4-B. Índice de animação do player — MAPA AUTORITATIVO do EXE  ✅ (round 5)

> ⚠️ **Ver 4-B0 (round 6): esta seção descreve só o banco DEFAULT (desarmado = PL00.PLD).**
> Corrige o mapa por *root-motion/render* (que era heurístico). Aqui a fonte é o
> **código** (`tools/exe_player_anim.py`). Campo-chave descoberto: **`player+0xc8` = índice
> de sequência EDD atual (0..21), 1:1 com `animNN` do PLD.**

### 4-B.1 Prova de `player+0xc8` = índice EDD  ✅ ALTA
Função de tocar animação **`0x80018ec8`**:
```
lbu  $v0, 0xc8($player)     ; sequência atual (0..21)
sll  $v0, $v0, 3            ; *8  = tamanho do registro EDD
addu $v1, $edd_base, $v0    ; &EDD[seq]
lhu  nframes,     0($v1)    ; registro EDD = {u16 nframes, u16 frameOffset, u32 poseStart}
lhu  frameOffset, 2($v1)
lbu  frame, 0xc9($player)   ; frame atual dentro da sequência
... percorre a frame-list em edd_base+frameOffset (2 B/frame)
```
Bate EXATAMENTE com o layout EDD de `PLD.md §6`. Logo `0xc8`=animNN, `0xc9`=frame.

### 4-B.2 Máquina de estados de locomoção (Jill)  ✅ ALTA
Think da Jill **`0x80038c7c`** → dispatch **`player+4`** (ação macro; 1 = on-foot) via
tabela **`0x8009cd40`**. A ação 1 (**`0x80039020`**) faz **dois** dispatches por
**`player+5`** (rotina 0..15): **`T1_move`=`0x8009cd60`** (lê o pad) e
**`T2_anim`=`0x8009cda0`** (escreve `player+0xc8`).

`T2_anim` puxa a sequência de uma **tabela 3×3 em `0x8009cde0`** (`02 05 08 | 00 03 06 | 01 04 07`),
indexada pelo `motionType` (var `0x8009cd3c`).

> ⚠️ **CORREÇÃO (round combate):** o `motionType` que escolhe a linha da tabela 3×3 **NÃO é
> "speed-tier / velocidade"** — é a **ZONA DE SAÚDE derivada do HP** (é o mecanismo do
> **MANCAR**). E **`player+0xcc` é o HP** (não "momentum"). Prova em `T1 r1` (`0x800395b0`):
> `lh a0,0xcc; slti ...,0x65` (HP<101?) e `slti ...,0x15` (HP<21?) → grava `motionType`:
> **tier0 = FINE (HP≥101) · tier1 = CAUTION (21..100) · tier2 = DANGER (HP<21)**. A tabela 3×3
> escolhe a variante **saudável / ferida / mancando** de idle/andar/ré. (HP máx 200; ver §4-C.)

| rotina | offset na tabela | anim por zona FINE/CAUTION/DANGER | entrada (pad) | papel |
|---|---|---|---|---|
| **r0 idle**   | 0 | **2/5/8** → base `anim02` | — (estado default) | **parado** (fidget anim05/anim08; wait especial `anim21` em `0x800394fc`) |
| **r1 frente** | 3 | **0/3/6** → base `anim00` | `pad & 0x01` (UP) | **andar pra FRENTE** (variante mancando em DANGER) |
| **r3 corrida**| — | `anim09`(parado)/`anim10`(mov.) | `pad & 0x04` | **CORRER pra frente** |
| **r2/r6 DOWN**| 6 | **1/4/7** → base `anim01` | `pad & 0x200` (DOWN) | ré / giro-180 |
| r4 | 3 | 0/3/6 (== r1) | `pad & 0x0a` | variante de frente |

> **Prova da direção:** `T1 r1` (**`0x8003957c`**) mantém a rotina 1 enquanto `(a1 & 1)`;
> ao soltar, faz `sw 1,4($player)` → volta a idle. Logo **bit 0 = FRENTE**. `T1 r3`
> (`0x80039ccc`) mantém enquanto `(a1 & 4)`. Correr = `anim10`, root-motion `net(-2057,0)` =
> **mesmo eixo −X** do andar `anim00` → corrida **pra frente** (não é dano).

### 4-B.3 Sistema paralelo (genérico) e tabelas por-arma  ✅
Há um 2º dispatcher (update `0x80016600` → `player+5` → tabela **`0x80097aa0`**, 22 rotinas
r0..r21). As rotinas r6/r7/r8/r9 puxam a sequência de **tabelas indexadas por `player+0x4a`
(estado de arma/postura)** em `0x800979f0`/`0x80097a18`/`0x80097a40`/`0x80097a68`
(`seq = tabela[0x4a] & 0x3f`, bit 0x40 = direção reversa, bit 0x80 = seletor de canal).
`0x4a<8` vs `≥8` troca parâmetros de giro (`0x80038e70`). O integrador tank-control
**`0x8001a248`** só APLICA o motion da pose (`pose+0x54..0x64`) segundo `player+0x120`
(0x10=frente, 0x40=ré, 0x80=esq, 0x20=dir); **não** seleciona a sequência.

### 4-B.4 Veredito sobre as 3 hipóteses do usuário
- ❌ **`anim00` = ré de cutscene** → **REFUTADO**. `anim00` = **andar pra FRENTE de gameplay**
  (rotina r1, mantida pelo bit UP; base tier).
- ❌ **`anim10` = dano/knockback** → **REFUTADO**. `anim10` = **CORRER pra frente** (rotina r3,
  input `& 4`; root −X).
- ✅ **`anim19`/`anim20` = poses de MIRA (upper-aim) — RESOLVIDO (era EM ABERTO).** Varredura de **todos os
  168 escritores de `player+0xc8`**: os **únicos** stores de 19/20 são `0x8003acb8`/`0x8003accc`, **dentro da
  rotina 7 (aim)**, no seletor de altura (`andi 0xc7,0x20` → 15→19 / 16→20, facing ±0x400). O **dano/knockback
  do player** vive na **ação macro a3** (`0x8003d9e0`) e usa anims **4/5/9/10/11/12** (`0x8003d200..0x8003d990`),
  **nunca 19/20**. O render que mostrava "tombo no ar" mediu a **seq 19/20 do PL00.PLD** (banco desarmado) em
  isolado; mas o EXE só seleciona 19/20 com **arma equipada** (banco PLW ativo, §4-B0), então o clipe exibido é a
  **mira-alta do PLW**. Prova completa em `../decomp/notes/exe_combat.md §1.3/§1.6`. **Fonte de verdade = EXE.**
- 🟡 **`anim21` = fidget/“esperou demais”** → **PLAUSÍVEL/CONFIRMADO como idle-wait**:
  `anim21` é setado no **sub-estado 7 do idle** (`0x800394fc`: `sw 0x000f0015,0xc8` = seq 0x15).
  O idle **base** porém é `anim02` (r0, tier0), com progressão de fidget `anim05→anim08`.

### 4-B.5 Ambiguidades / o que falta
- **Linhas da tabela 3×3 = ZONA DE SAÚDE** (FINE/CAUTION/DANGER, derivada do HP em
  `player+0xcc`) — **corrigido** (era "walk vs run / momentum"; ver §4-B.2 e §4-C). É o
  mecanismo do **mancar**: `anim03`/`anim06` são as variantes ferida/mancando de `anim00`.
- **Bits de pad ≠ FRENTE**: só o bit0=FRENTE está provado por comportamento. `bit2`(corrida),
  `bit9`(DOWN), `bit1/3`(r4) inferidos (a tabela de remap em `0x8009cc7c` no EXE estático não é
  confiável — é sobrescrita pela config do controle no boot).
- **Captura que fecharia**: save-state do emulador (a) parada, (b) andando pra frente, (c)
  correndo, (d) apertando ré — lendo **`player+0xc8`** em cada um confirma o mapa byte-a-byte.

---

## 4-C. HP / condição do player (FINE/CAUTION/DANGER)  ✅  → `../decomp/notes/exe_combat.md`
> Confirmado por GameShark NTSC-U + disassembly. Base do player-struct = **`0x800ccbc4`**.
- **`player+0xcc` (u16) = HP atual** (`0x800ccc90`; vida infinita GS `800CCC90 00C8` → **máx 200**).
- **`player+0xce` (u16) = HP máximo**; **`player+0xd3` = byte de condição** (`0x04 = FINE`;
  GS "always fine" `300CCC97 0004`).
- **Dano ao player = `0x8003dd7c`** (`HP -= a0`; morte seta flags em `+0xd2`/`+0xd3`).
  **Cura = `0x8003de5c`** (clampa a `+0xce`). Classificador ECG/condição `~0x80038080`
  (limiares `0x30/0x50/0xb1/0xd1` sobre o HP escalado).
- As **zonas de saúde alimentam a tabela 3×3 de anim** (§4-B.2) → mancar em DANGER.

## 5. Mira / tiro / dano do player  ✅ (100%, `aim_shoot`)  → `../decomp/notes/exe_combat.md §1-2`
> Confirmado por disassembly + GameShark. **Fechado do lado do player**: entrada em mira, auto-lock,
> **geometria de altura/pitch** (`0x8003ac90`: tier→`0x6e=(tier<<9)+0x800`, poses 14-17/19-20),
> **hitscan** (`0x80044804` varre chars, dist-mín `0x7fffffff`; rocket/granada = handlers dedicados
> `0x800408c4`/`0x8003ff9c`), **timing de disparo/rearme** (`0x8009cf28`). O **HP/dano do inimigo** vive na
> IA (§3) — é da unidade `ai`, não de `aim_shoot`.
- **Entrar em mira:** botão = pad máscara **`0x500`** (bits `0x100`/`0x400`); exige arma
  equipada (`player+0x46 != 0`). Fluxo: rotina **5** (levantar arma) → rotina **7** (mira+tiro).
- **Rotina 7 = `0x8003a7d8`** (durante a mira o player **não anda**, facing travado):
  sub-estado em `player+6` (0 levantar → 1 pitch → 2 mira+**auto-aim** → 3 hold+**fogo**).
  Ângulo ao alvo via `ratan2 = 0x8001808c`; clamp do arco ±`0x1000` (~90°).
- **AUTO-LOCK = `0x800445c8`:** cada inimigo, no seu update, oferece as **partes de hitbox
  `0x41` (corpo) / `0x42` (cabeça)**; se caírem no arco, grava **no player**:
  `+0x16c/+0x170` (ptr do alvo) e `+0xc7` (part-id).
- **Disparo (sub 3, `0x8003adc0`):** gatilho lido do pad global (`0x800cc83c`, máscara `0x500`);
  munição/flash em `player+0x12d`; ponto do cano em `+0x124/126/128`; recuo `0x80048308`.
- **Tabelas de arma:** **fogo por arma** `0x8009ce88` (16 ptrs); **stats/timing** `0x8009cf28`
  (21×3B: `byte2&0x7f` = frame de disparo). A **coluna de dano-vs-inimigo é outra** (não isolada).
- ⚠️ **Pendência (o hit no inimigo):** o `HP_inimigo -= dano` **não** está no caminho estático
  do disparo — é **data-driven pela EMD/EMR** (partes de hitbox). Fechar exige RAM-watch. Ver
  §3 e `../decomp/notes/exe_ai.md §3`.

---

## 6. Método de busca de tabelas (reprodutível)

1. `Exe.find_pointer_tables()` — corridas de u32 na faixa `[base, vend)` = jump tables
   candidatas (67 achadas; a maior tem 280 entradas @`0x8009e7dc`).
2. `exe_dispatch.py` — propagação de constantes p/ classificar `jr/jalr`:
   **INDEXED** (`base+idx*4`, jump table real) vs **PTRVAR** (ponteiro de função global,
   máquina de estados). 17 dispatches indexados; 130 via ponteiro-variável.
3. `Exe.find_hi_lo_refs(addr)` / varredura de refs por região — quem carrega/indexa cada
   tabela, e com qual campo (revela o significado: item/objeto/estado).

---

## 7. O que falta (prioridades)

1. **Handler de porta → destino de sala** (`0x800248e4` + tabela `0x8009dfd0[stage][room]`):
   fechar o (stage,room)-destino via **trace runtime** (o destino não é campo estático — provado).
   Destrava todas as transições. Ver `../decomp/notes/door_handler.md`.
2. **HP/dano do inimigo** (hword no bloco `+0xb0..+0xb4` do work-struct de 0xD4, via RAM-watch)
   + a **coluna de dano por arma**. Ver `../decomp/notes/exe_ai.md §3`.
3. **`sce_em_set`** (opcode de spawn de inimigo) → fecha `type_id → espécie` (hoje em aberto).
4. ~~**Resto da SM do player** (rotinas r10/r12/r15 scriptadas)~~ **✅ FECHADO** — ver
   [`../decomp/notes/exe_combat.md §3.2 nota (d)`](../decomp/notes/exe_combat.md). r10=andar-c/-mira
   (`0x8003b4fc`/`0x8003b784`, alcançado por r1 `0x800396a0`/r14 `0x8003ba74`), r15=ré-c/-mira em evento
   (`0x8003bf28`/`0x8003c104`, alcançado por r2 `0x80039a4c` + 5 sítios de script `0x8005a9fc..0x8005c354`),
   r12=anim scriptada 1/2/3 (`0x8003ca80` stub/`0x8003ca88`, alcançado por r11 `0x8003c8a4` + ação a4
   `0x80060ad8`). Falta só a **máquina do Nemesis** (`0x800e01c0`, evento scriptado).
5. ~~**anim19/20** — resolver a divergência mira vs dano~~ **✅ RESOLVIDO** — anim19/20 são **poses de MIRA**
   (upper-aim), únicos escritores `0x8003acb8`/`0x8003accc` na rotina 7; o dano do player usa a3 (anims
   4/5/9/10/11/12). Prova em [`../decomp/notes/exe_combat.md §1.3/§1.6`](../decomp/notes/exe_combat.md).
