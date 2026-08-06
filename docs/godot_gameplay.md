# Gameplay Godot — primeira sala jogável (estilo RE clássico)

> **Guia do protótipo** (implementação v1). Formatos-fonte: [ARD/RDT](formatos/ARD.md)
> (câmeras/colisão/RVD), [PLD](formatos/PLD.md) e [animação](formatos/animacoes_player.md).
> Índice geral em [`README.md`](README.md); progresso em [`decomp/progress.json`](decomp/progress.json).

Fatia vertical: a **Jill 3D** anda sobre o **background HD 2D pré-renderizado** da
sala **R100** (STAGE1), com **câmera fixa** (ponto-fixo, no estilo do RE de PS1) e
**tank controls**.

## Arquitetura

`godot/scenes/game_room.tscn`:

```
RoomGame (Node2D)                 -> scripts/room_game.gd
├── Background (Sprite2D)         -> webp HD 1280x960, centered=false, escala p/ 1280x960
├── Viewport (SubViewportContainer, stretch=true, 1280x960)
│   └── SubViewport (transparent_bg=true, update_mode=ALWAYS, 1280x960)
│       ├── WorldEnvironment      -> ambient light (a Jill não tem luz do cenário)
│       ├── Camera3D (fov vertical, keep_aspect=KEEP_HEIGHT)
│       ├── Sun (DirectionalLight3D)
│       └── Jill (Node3D)         -> scripts/jill_controller.gd
│           └── Model (PL00.glb)
└── UI/Info (Label)
```

O **SubViewport transparente** é composto **por cima** do background pelo
`SubViewportContainer` (blita a textura do viewport preservando o alfa). Assim o 3D
da Jill aparece sobre o cenário 2D, e o cenário faz as vezes de "fundo".

## Conversão de coordenadas PS1 → Godot

O ARD/RDT (câmeras, portas) usa unidades PS1 com **Y para baixo**. A conversão é:

```gdscript
godot = Vector3(ps1.x, -ps1.y, ps1.z) / world_scale
```

- Inverte o **Y** (PS1 Y-down → Godot Y-up).
- Divide por `world_scale` para trazer a sala para uma escala em "metros" do Godot.

A `Camera3D` é montada a partir de `rdt.cameras[i]`:
`position = conv(from)`, e `look_at(conv(to), UP)`.

## Valores de calibração (validados por render real)

Todos são `@export` (ajustáveis no Inspector). Encontrados iterando com screenshots
reais (OpenGL3) até a Jill ficar **do tamanho certo, pisando no chão e com a
perspectiva batendo** com o background. Vale para as **duas** câmeras da R100.

| Parâmetro            | Valor              | Onde            | Racional |
|----------------------|--------------------|-----------------|----------|
| `world_scale`        | **808**            | room_game.gd    | `2400 / 2.971`. O PL00.glb tem **2.971 un** de altura no Godot; a física diz que um personagem tem **~2400 un PS1**. Dividir por 808 faz o modelo casar com as proporções PS1 → `model_scale = 1.0`. |
| `camera_fov`         | **55°** (vertical) | room_game.gd    | Perspectiva credível vs. background nas 2 câmeras. Calibrável 50–60. |
| `jill_start_ps1`     | **(-21820, -258, -21899)** | room_game.gd | Ponto de chão central visível pela câmera 0. |
| `model_scale`        | **1.0**            | jill_controller | Casado via `world_scale` (ver acima). |
| `foot_offset`        | **1.85**           | jill_controller | AABB `min_y` do modelo (pés). O mesh sobe `1.85 * model_scale` para os pés baterem na **origem** do node Jill; assim a origem da Jill = ponto de chão. |
| `model_yaw_offset_deg` | **180°**         | jill_controller | Alinha o "frente" visual do mesh ao `-Z` do node (base do movimento). |

### Sobre a altura do chão (Y)

O **Y do chão** da R100 ficou em **PS1 y ≈ -258** (→ Godot y ≈ +0.32). Importante:
esse valor **não** é o `entry.y` das portas do RDT (que fica em ~-1800/-2550 — outra
referência, provavelmente o "olho"/origem do teleporte). O chão foi achado por
render: em `y=0` a Jill afunda no piso; em `y≈-258` os pés assentam nas tiles.
Derivação coerente: a câmera 0 mira (`to.y`) em -1458 (~altura do peito de quem está
em pé), o que coloca o piso perto de y≈-258.

## Controles (tank controls — WASD)

| Tecla        | Ação |
|--------------|------|
| **W / S**    | anda para frente / trás na direção atual (`anim00`) |
| **A / D**    | gira a Jill à esquerda / direita (`anim03`) |
| Shift        | correr (`anim10`) |
| `[` / `]`    | troca a câmera manualmente (desliga o auto até reiniciar) |

As teclas são lidas direto (`Input.is_key_pressed(KEY_W/…)`) em `jill_controller.gd`;
não dependem do InputMap.

> ⚠ **Nota (clipes):** os nomes `anim00`/`anim03`/`anim10` acima são do banco **base**. O
> controller foi migrado para os clipes **armados** (`armNN`, do PLW equipado) — a locomoção
> real de gameplay vem do PLW, não das 22 do PLD. Ver [formatos/animacoes_player.md](formatos/animacoes_player.md).

Movimento é **velocidade escalar por frame** (simplificação do root-motion real do
RE3). Constantes derivadas de `data/physics.json` (30 fps de gameplay):

- `walk_speed = 2.2` un/s  (PS1 ~60 un/frame · 30 / 808)
- `run_speed  = 8.5` un/s  (PS1 ~229 un/frame · 30 / 808)
- `turn_speed_deg = 110`/s (PS1 ~3.4°/frame · 30)

> Nota: o RE3 real usa **root-motion por pose** (vetores em `physics.json →
> velocidades.*.motion_por_pose_xyz`). Aqui usamos velocidade escalar para uma
> primeira fatia jogável; migrar para root-motion de verdade é um passo futuro.

## Etapa 2 — Seleção de câmera automática (por ENQUADRAMENTO)

Vale para as **1000+ transições** do jogo (169 salas, ida e volta). Formato bruto do
RVD e a semântica descoberta: [`docs/formatos/ARD.md §3.5`](formatos/ARD.md). Aqui está
**como o remake escolhe a câmera por posição**.

### O bug que motivou o sistema ("pula pra beira")

O código antigo tratava as zonas RVD (`from → to`) como **gatilho de borda**: disparava
a troca no instante em que a Jill **entrava** na faixa. Só que, no RE3, essas faixas
não-degeneradas são **fronteiras de histerese coladas na borda de cobertura da câmera de
destino** (ver ARD.md §3.5). Entrar nelas = aparecer na **beira** da câmera nova. Na
**R100**, indo do depósito (cam0) ao escritório (cam1), a troca caía em `x≈-22500` com a
Jill **grudada na borda direita**, em cima do alçapão — confirmado por render.

### O algoritmo geral (init == runtime)

Em vez de gatilho de borda, medimos **diretamente o enquadramento** por projeção e
usamos o RVD só como **grafo de vizinhança** (transições autorizadas). Assim não
dependemos do significado fino do `flags` e a regra vale para qualquer nº de câmeras.

- **Custo de enquadramento** `_cam_frame_cost(cam, P)`: projeta o **torso** da Jill
  (pés + `frame_probe_height`) na câmera → `|ndc_x|` (0 = centralizada, 1 = na borda).
  `INF` se atrás da câmera ou fora do frustum vertical (`|ndc_y| > cam_frame_ymax`).
  Como cada câmera **olha para seu `to`**, esse custo mede o desvio horizontal da Jill
  em relação ao eixo da câmera → a de **menor custo é a que melhor a enquadra**
  (validado: as **2105 câmeras** projetam seu próprio `to` em `ndc_x ≈ 0`).
- **Histerese espacial** (`_update_camera_auto`): **mantém** a câmera atual enquanto
  `_cam_frame_cost(atual) ≤ cam_keep_ndc` (`0.9`). Só troca quando a Jill **sai** do
  enquadramento da câmera atual.
- **Escolha do destino** (`_best_camera`): entre os **vizinhos RVD** da atual (+ ela
  mesma) que enquadrem (`≤ cam_cover_ndc`), pega o de menor custo; se nenhum servir
  (ou no init), cai para a **melhor câmera global**. O grafo evita saltos para câmeras
  que enxergam "através de parede".
- **Câmera inicial** = melhor enquadramento global do ponto de partida — **mesma
  métrica** do runtime (`_camera_for_point` chama `_best_camera(P, -1)`).
- `switch_cooldown_frames = 6`: rede de segurança temporal contra jitter (a histerese
  principal é espacial, não temporal).

**Propriedades**: como só se troca quando a Jill sai do quadro da câmera atual **e** a
nova já a enquadra bem, ela **nunca aparece na beira** no corte; a zona morta entre
`cam_keep_ndc` e a borda dá **histerese** (sem flicker) em **ambas as direções**.

### Validação por render (`dev/tools_cam_walk.gd`, ida E volta)

- **R100** (2 câmeras), travessia depósito↔escritório em `z=-21899`:
  - **IDA** (cam0→): mantém cam0 até `x≈-24000` e troca para cam1 em `x=-24500`, com a
    Jill enquadrada a `|ndc_x|≈0.34` (**bem no quadro**, não na beira).
  - **VOLTA** (cam1→): mantém cam1 até `x≈-21500` e troca para cam0 em `x=-21000`
    (`|ndc_x|≈0.15`, centralizada).
  - **2 trocas totais**, **zero flicker**, folga de histerese de ~3500 un. No ponto
    onde o código **antigo** trocava (`x=-22500`) a Jill agora ainda está na cam0, bem
    enquadrada (antes: colada na borda direita, sobre o alçapão).
- **R10E** (5 câmeras), corredor em X: travessia limpa cam0↔cam1, 2 trocas totais,
  **sem flicker**, histerese de ~8000 un; enquadramento bom no corte.

Rodar (não usar `--headless`, que usa driver dummy):
```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --path godot --rendering-driver opengl3 --script res://dev/tools_cam_walk.gd
# env: WALK_ROOM, WALK_AXIS=x|z, WALK_FROM, WALK_TO, WALK_FIXED, WALK_Y, WALK_STEPS
```

## Etapa 3 — Colisão REAL de móveis (decodificada) ✅

O bloco de **colisão** do RDT foi decodificado: é o **`offset_table[6]`** (antes marcado
"geometria/objeto"). Formato (ver `tools/rdt_collision.py` e `docs/formatos/ARD.md §3.6`):

```
+0x00  u32  count          // nº de registros, INCLUINDO o cabeçalho (registro 0)
+0x04  s16  center_x, center_z   // ponto de referência (≈ centro da sala), repetido
+0x0C  s16  0, 0
depois, (count-1) registros de 16 bytes:
+0x00  s16  x0, z0         // 1º canto do retângulo (plano do chão, unidades PS1)
+0x04  s16  x1, z1         // canto oposto
+0x08  s16  y              // altura do chão do collider
+0x0A  s16  h              // altura/topo (≈ pé-direito; é colisão de altura cheia)
+0x0C  s16  t0, t1         // tipo/normal (parede vs. móvel)
```

Validado na **R100** (`count=15` → 14 retângulos): os **4 primeiros** são as **paredes**
(a moldura da sala) e os **10 seguintes** são os **móveis** (2 pilhas de caixa, o
armário/balcão de fichário, prateleiras). Exportado por sala em
`godot/data/STAGE{n}/{sala}_col.json` (`collision.rects[]`, cada um com
`rect:[x0,z0,x1,z1]` já normalizado min→max e `wall:bool`). Rodar em todas as salas:
`python tools/rdt_collision.py`.

### Uso no jogo (`room_game.gd`)

- `_load_collision()` lê o `_col.json`; `_is_walkable_ps1` **barra a Jill dentro de
  qualquer retângulo**, inflado por `collider_radius = 380` un (a "casca" da Jill, para
  ela parar na **face** do móvel/parede, não penetrar até o centro). O **AABB** da sala
  continua como rede de segurança externa.
- `jill_controller._apply_move` faz **deslize por eixo** (tenta X, depois Z) → ela
  escorrega na parede em vez de travar. A `room_game` injeta o validador via
  `jill.set_walkable_query(...)`.
- `manual_blockers` viraram **fallback** (só usados se o `_col.json` não carregar).

**Validação (render real, `tools_collision_val.gd`)**: partindo do spawn
`(-21820,-21899)`, a Jill anda em **+X** e **PARA após só 355 un** na face do armário
(`x≈-21464`, face do móvel em `-21065` menos o raio) — antes atravessaria até a parede
distante. Nas 4 direções ela para sempre numa face de móvel/parede; amostras dentro de
um móvel dão `caminhável=false`.

## Etapa 3 — Oclusão (personagem atrás do cenário) ✅

Objetivo: os móveis que ficam **na frente** da Jill devem **esconder** as partes dela que
passam por trás. Implementado por **profundidade (holdout 3D)**, alimentado pela mesma
geometria de colisão decodificada:

- Para cada **móvel** (retângulos não-parede) é criada uma **caixa 3D invisível** no
  SubViewport, na planta do móvel (altura `occluder_height = 1.3` un, calibrada por
  render). A caixa é **opaca (escreve profundidade)** mas seu shader **amostra o
  background** por `SCREEN_UV` (`filter_nearest`) → fica visualmente idêntica ao cenário.
- Quando a Jill passa **atrás** da caixa, o **teste de profundidade** descarta os pixels
  dela ali e o cenário reaparece por cima: **oclusão correta por pixel**, automática
  (quando ela está **na frente**, ela desenha por cima — sem oclusão). A caixa aponta
  para o background da câmera atual em `_show_camera` (troca junto com a câmera).

**Validação (render real)**: com a Jill encostada no armário, o braço/mão que passa atrás
da bandeja e do fichário **some** (ocluído); no chão aberto, à frente do móvel, ela
aparece **inteira**. Ver `tools_shot.gd` (env `OCC`, `OCC_H`, `FORCE_CAM`, `DBG`).

> **Sobre a máscara HD** (`assets/MASK/…_m0.webp`): são um **atlas de "priority sprites"**
> do PS1 (não alinhado à tela); o posicionamento vive em `camera.mask_data_ptr`, também
> decodificado (`tools/rdt_collision.py` → `cameras_masks`, blocos `dx,dy,w,depth`). Como
> o mapeamento atlas→tela por-objeto ficou **parcial**, a oclusão usa a via de
> **profundidade** (equivalente e robusta) sobre a geometria real de colisão. Migrar para
> o atlas HD (silhueta 2D exata) é um passo futuro.

## Harness de calibração / validação (SceneTree, opengl3)

O `--headless` usa driver dummy e **não** renderiza — use `--rendering-driver opengl3`.

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
PROJ="c:/Users/Jhonatas Ortega/Documents/Projetos/Nostalgia/godot"
"$GODOT" --path "$PROJ" --rendering-driver opengl3 --script res://tools_shot.gd            # 1 screenshot
"$GODOT" --path "$PROJ" --rendering-driver opengl3 --script res://tools_gameplay_test.gd   # R100: câmera+colisão
"$GODOT" --path "$PROJ" --rendering-driver opengl3 --script res://tools_multicam_test.gd   # R101: multi-câmera
```

`tools_shot.gd` aceita overrides por variável de ambiente:
`SHOT_OUT`, `JILL_PS1="x,y,z"`, `JILL_FACE`, `FOV`, `WSCALE`, `FOOT`, `CAM`.

## O que falta afinar

- ~~**Colisão real (SCA)**~~ ✅ decodificada (`offset_table[6]`) — paredes + móveis por sala.
- ~~**Oclusão**~~ ✅ implementada por profundidade (holdout 3D) sobre a colisão real.
- **Oclusão via atlas HD**: usar `mask_data_ptr` + `assets/MASK/…_m0.webp` para silhueta
  2D exata (hoje: caixas de profundidade, altura calibrada). Falta o mapeamento
  atlas→tela por-objeto do priority-sprite.
- **Root-motion real** por pose (em vez de velocidade escalar), usando `physics.json`.
- **FOV por câmera** (hoje 55° global) e casamento do tom de luz por câmera.
- **Tonemap**: as caixas de oclusão passam pelo tonemap ACES do SubViewport (o
  background 2D não); com `occluder_height` baixo o descasamento é imperceptível, mas
  caixas muito altas deixam um "fantasma" fraco na parede.
