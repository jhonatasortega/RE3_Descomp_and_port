# Tabela de animações do PLAYER (RE3 PS1) — banco EDD do `PL00.PLD`

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `anim_player`, `plw`)
> - **Formato:** sistema de animação do player (bancos EDD/EMR, poses, seleção multi-banco por arma)
> - **Extensão/origem:** `PL00.PLD` (banco base, 22 seqs) + `PL00W00.PLW`..`W14` (bancos armados)
> - **Ferramenta:** [`tools/pld2gltf.py`](../../tools/pld2gltf.py) (`build_armed_clips`), [`find_anim_banks.py`](../../tools/find_anim_banks.py)
> - **Decompilado:** **100%** (`anim_player`) · `plw` fechado no lado decomp (ver [plw.md](../decomp/notes/plw.md))
> - **Feito:** as 22 seqs do PLD medidas/renderizadas; **locomoção real = banco0 do PLW** extraída e ligada (clipes `armNN`).
> - **Multi-banco RESOLVIDO:** cada `.PLW` tem **3 bancos** — bank0 (15 ossos, 76 B/pose, 18 seqs = corpo
>   inteiro/locomoção armada; é o dos `armNN`), bank1 (7 ossos, 8 seqs) e bank2 (9 ossos, 52 B, 8 seqs)
>   = overlays parciais. Validação `find_anim_banks.py --validate-all`: 84/84 PLW com banco + malha.
>   Ver [plw.md §5](../decomp/notes/plw.md).
> - ✅ **OVERLAY DE MIRA/TIRO extraído** (ver [plw.md §9](../decomp/notes/plw.md)): o **bank2** é a
>   mira. De-para de osso **provado** (`relpos` inteiro exato + cadeia de pais, igual nos 84 `.PLW`):
>   bank2 → ossos **`0..8`** (raiz + cabeça + 2 braços + pelve = **SUPERIOR**);
>   bank1 → ossos **`0,9,10,11,12,13,14`** (raiz + 2 pernas = **INFERIOR**).
>   Exportado como **`mira00..mira07`** no `<PERSONAGEM>.glb` (`pld2gltf.py::build_partial_clips`);
>   teste em [`port/dev/tests/test_anim_mira.gd`](../../port/dev/tests/test_anim_mira.gd), foto em
>   [`port/dev/shot_mira_overlay.gd`](../../port/dev/shot_mira_overlay.gd).
> - ⚠️ **CORREÇÃO:** a linha antiga *"os 3 slots armados do EXE (`player+0xf4/0xf8/0x100`) mapeiam
>   nesses 3 bancos"* é **NÃO PROVADA** — a rotina de equipar arma (`0x80043be4`) preenche **só**
>   `+0xf0/+0xf4` com o banco0 do `.PLW`. Detalhe e os outros 3 pontos abertos em
>   [plw.md §9.6](../decomp/notes/plw.md).
> - **Osso de anexo da arma:** `bone4` (punho direito), world-rest `(-32, 297, -435)` PS1 — dado de decomp; ligar no controller é vínculo.
> - **Falta (vínculo/gameplay, não decomp):** validar mira + "subir em item"; fixar o índice de tier por captura de save-state (ver [exe.md §4-B0/4-B.5](exe.md)).

> Referência das **22 sequências** do banco de animação embutido no `PL00.PLD` (Jill).
> Layout **universal**: todos os PLD de player (PL00..PL0A) têm as mesmas 22 (o índice `i`
> = a mesma ação em qualquer personagem). Dados cruzados de 3 fontes: **RE do EXE**
> (`SLUS_009.23`, `player+0xc8` = índice EDD), **root-motion** medido do PL00.PLD
> (frame-list, 30 fps) e **render** (Godot opengl3) + **captura no jogo** (GOG rodando).
> Dados-fonte em [`godot/data/anim_map.json`](../../godot/data/anim_map.json).

---

## ✅ RESOLVIDO — o ANDAR de gameplay NÃO está nestas 22 (está no PLW da arma)

O usuário estava **certo**. Provado por RE do EXE (`tools/find_anim_banks.py`): o player do
RE3 usa **banco MÚLTIPLO**. `player+0xc8` (índice) indexa um EDD cujo ponteiro-base é
**selecionado em runtime pela ARMA equipada** (`player+0xf4` = banco do `.PLW`). Como a Jill
anda **sempre com arma na mão**, o andar/correr/parada/ré de gameplay vem do **banco0 do
`PL00W00.PLW`** (handgun; corpo inteiro, 15 ossos, 18 seqs), **não** do `PL00.PLD`.

As 22 abaixo são o set **DESARMADO/base** + ações sempre-válidas (dano, pegar, idle-wait).

### Locomoção ARMADA real (`PL00W00.PLW` banco0) — retargetada como clipes `armNN`

| seq | clipe glb | ação | vel |
|----:|-----------|------|-----|
| 0 | `arm00` | **ANDAR frente** | ~78/f |
| 1 | `arm01` | **CORRER** | ~222/f |
| 2/5/8 | `arm02` | **PARADA/mira** (idle armado) | 0 |
| 9 | `arm09` | **RÉ** | ~68/f |

O `pld2gltf.py` (`build_armed_clips`) extrai o banco0 do PLW e o aplica ao esqueleto do PLD
(mesmos 15 ossos). O controller usa os `armNN` pra locomoção. Cada arma tem seu PLW → o andar muda
por arma equipada.

### Overlay de MIRA/TIRO (`PL00W00.PLW` banco2) — clipes `miraNN`

`build_partial_clips` extrai o **banco2** (parcial SUPERIOR, 9 ossos) e o retargeta para os ossos
`0..8` do esqueleto de 15. O `PL00.glb` passa a ter **48 clipes**: `anim00..21` + `arm00..17` +
`mira00..07`. Cada `miraNN` tem trilha de rotação **só** para `bone00..bone08` e **nenhuma**
translação de raiz → aplicar = **substituir** os ossos do subconjunto sobre o clipe de locomoção
(as pernas seguem no `armNN`). Alturas do punho direito medidas por FK (PS1, repouso `y=+297`,
`y` menor = mais alto):

| clipe | quadros | punho `y` | papel | EXE (`player+0xc8`) |
|---|---:|---:|---|---|
| `mira00` | 10 | +291 → **−598** | **LEVANTAR a arma** | 13 (rotina 7 sub0) |
| `mira01` | 20 | → −598 | rampa p/ mira média | — |
| `mira02` | **1** | **−598** | **HOLD mira MÉDIA** | 14 (`aim_tier` 0) |
| `mira03` | 20 | → −1027 | rampa p/ mira alta | — |
| `mira04` | **1** | **−1027** | **HOLD mira ALTA** | 15/19 (declarado) |
| `mira05` | 20 | → −115 | rampa p/ mira baixa | — |
| `mira06` | **1** | **−115** | **HOLD mira BAIXA** | 16/20 (declarado) |
| `mira07` | 32 | −591 (−716..−362) | **TIRO + recuo** | rotina 7 sub3 |

Controle: o `arm02` (parada/mira de corpo inteiro) mantém o punho em `y ≈ +270` — **na altura do
quadril**. O braço **só levanta** no banco2. O casamento índice-a-índice de `0xc8` (13..20) com a
seq do banco é **DECLARADO**, não provado ([plw.md §9.6](../decomp/notes/plw.md)).

---

## As 22 sequências

Colunas: **root** = deslocamento líquido `[X, Z]` em unidades PS1 · **un/f** = velocidade
média por frame (XZ) · **giro** = rotação líquida (graus) · **fr** = frames de jogo (30 fps).

| # | fr | root [X,Z] | un/f | giro | Papel provável | Confiança | Evidência |
|--:|---:|-----------:|-----:|-----:|----------------|-----------|-----------|
| 00 | 34 | [-1972, 0] | 60 | +2° | Ciclo de passada ereto (**NÃO é o andar de gameplay** — ver acima) | — | EXE r1→seq0; render; root -X |
| 01 | 119 | [304, -1366] | 12 | +69° | Clipe longo anda+gira (~4 s) — "DOWN" no EXE; identidade visual incerta | baixa | root; EXE routine DOWN |
| 02 | 21 | [-767, -139] | 39 | -59° | Gesto/settle com braços em pé | baixa | render (braços cruzando) |
| 03 | 22 | [467, 59] | 22 | +71° | Passo virando | média | root |
| 04 | 20 | [0, 0] | 0 | 0° | Gesto com braço estendido, in-place | baixa | render (braço à frente) |
| 05 | 25 | [268, 0] | 11 | +21° | Ajeitar bota / ajoelhar | média | render (ajoelha na bota) |
| 06 | 10 | [-328, 151] | 40 | +66° | Passo curto virando | média | root |
| 07 | 25 | [635, 5] | 26 | -2° | Postura dinâmica (+X) | baixa | root |
| 08 | 24 | [974, 0] | 42 | -9° | **Abaixar e apanhar/examinar no chão** | alta | render (curva até o chão) |
| 09 | 16 | [-336, 0] | 22 | +31° | **Agachar** (abaixa ao chão) | alta | render / PLD.md |
| 10 | 10 | [-2057, 0] | 229 | 0° | **CORRER pra frente** (sprint inclinado, braços bombeando) | alta | EXE r3→seq10; render; root -X 3.8× andar |
| 11 | 21 | [442, 0] | 22 | +2° | Passo/alcance (+X) | baixa | root |
| 12 | 30 | [-3554, 0] | 123 | +16° | Correr com curva / andar machucado | média | root; render curvado |
| 13 | 6 | [222, 0] | 44 | +10° | Pose **agachada estática** (joelhos ~104°) — não usar de idle | alta | medição de ossos |
| 14 | 13 | [-1915, 43] | 160 | -33° | Correr virando | média | root |
| 15 | 13 | [-58, -1618] | 135 | -16° | Passo **lateral/virar** (-Z), par com anim16 | média | root eixo Z |
| 16 | 13 | [-58, 1618] | 135 | +16° | Passo **lateral/virar** (+Z), espelho do anim15 | média | root eixo Z |
| 17 | 11 | [45, 19] | 5 | -42° | In-place com giro, avanço ~0 | baixa | root |
| 18 | 28 | [1445, -130] | 54 | -46° | Passo/impulso (+X) | baixa | root |
| 19 | 24 | [10, -5648] | 246 | -6° | ✅ **POSE DE MIRA (upper-aim alto)** — promoção da pose 15 quando `part-id 0xc7 & 0x20` | alta | EXE `sb19,0xc8` em `0x8003acb8` (rotina 7, seletor de altura `0x8003ac90`) |
| 20 | 24 | [10, 5648] | 246 | -6° | ✅ **POSE DE MIRA (upper-aim alto)** — promoção da pose 16, espelho do 19 | alta | EXE `sb20,0xc8` em `0x8003accc` (rotina 7) |
| 21 | 84 | [0, 0] | 0 | 0° | **IDLE-WAIT / fidget** "esperou demais" (em pé imóvel → mão ao queixo) | alta | EXE sub-estado 7 do idle (~8 s); pernas ~12° |

---

## Mapeamento do EXE (máquina de estados do player)

`player+0xc8` (RAM `0x800ccc8c`) = índice de sequência atual (0..21). Máquina de estados:
`action(player+4)=1` on-foot → `routine(player+5)`: **0**=idle, **1**=frente(bit UP),
**2/6**=DOWN, **3**=corrida(botão). O idle é uma cadeia de sub-estados com timer (~8 s →
fidget anim21). Tabela 3×3 de sequências em `0x8009cde0` = `{02,05,08 | 00,03,06 | 01,04,07}`.
Detalhes e endereços em [`exe.md`](exe.md) seção 4-B e em [`anim_map.json`](../../godot/data/anim_map.json).

> ⚠️ **CORREÇÃO (round combate):** a **linha** da tabela 3×3 é escolhida pela **ZONA DE
> SAÚDE** (FINE/CAUTION/DANGER, derivada do **HP** em `player+0xcc`), **não** por "speed-tier /
> velocidade". É o mecanismo do **MANCAR**: em CAUTION/DANGER a Jill usa a variante ferida de
> idle/andar/ré. `player+0xcc` = **HP** (máx 200), não "momentum". Prova em `0x800395b0`
> (`slti HP,0x65` / `slti HP,0x15`) — ver [exe.md §4-B.2 e §4-C](exe.md).

> ✅ **RESOLVIDO — anim19/20 = poses de MIRA (upper-aim), NÃO dano.** Prova exaustiva (dump dos
> **168 escritores** de `player+0xc8`): os únicos que gravam 19/20 são `0x8003acb8`/`0x8003accc`,
> **dentro do seletor de altura da rotina 7** (`0x8003ac90`, gate `player+0xc7 & 0x20`) — promoção
> das poses 15→19 / 16→20. O **dano do player** é a ação macro **a3** (`0x8003d9e0`), que usa anims
> **4/5/9/10/11/12** — nunca 19/20. O render de "tombo" mediu a seq19/20 do **PL00.PLD** (banco
> DESARMADO) isolada; o EXE só seleciona 19/20 **com arma** (banco PLW). Ver [exe.md §4-B.4](exe.md).

> **✅ RESOLVIDO (era "hipótese sob teste"):** o `0xc8` indexa mesmo o EDD, mas o
> **ponteiro-base do EDD é selecionado em runtime pela arma equipada** (multi-banco).
> Com arma na mão, a base é o **PLW**, não o PL00.PLD — por isso `seq 0` na rotina de
> andar aponta para o andar-armado do PLW, e não para o `anim00` do PLD. Prova completa
> em [exe.md §4-B0](exe.md) (`find_anim_banks.py`).

---

## Estado do controller (`godot/scripts/jill_controller.gd`)

| Ação in-game | Clipe usado | Fonte |
|--------------|-------------|-------|
| Parado | `arm02` (idle armado, loop sutil) | PLW banco0 seq2 |
| Andar frente | `arm00` (andar armado) | PLW banco0 seq0 |
| Andar ré | `arm09` (ré armado, clipe dedicado) | PLW banco0 seq9 |
| Correr | `arm01` (correr armado) | PLW banco0 seq1 |
| Virar | `arm00` (stepping turn) | PLW banco0 seq0 |
| Mira (alto) | `anim19` / `anim20` (upper-aim, promoção de 15/16) | PL00.PLD / rotina 7 |
| (Dano) | ação macro a3 `0x8003d9e0` → anims 4/5/9-12 (a mapear no controller) | PL00.PLD (base) |

**Resolvido:** locomoção real = banco do PLW da arma. Render em Godot confirmou andar/correr/
parada corretos (skinning íntegro, rosto HD). Falta só validar o *feel* jogando a build.
