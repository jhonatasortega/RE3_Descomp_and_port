# v2 — Remake 3D (mapa em 3D real)

Esta pasta é o **projeto da versão 2**: reconstruir os ambientes do RE3 em **3D real com
câmera livre**, substituindo os cenários 2D pré-renderizados por geometria 3D.

O projeto `../godot/` é a **v1 fiel** (background 2D + câmera fixa, estilo original). A **v2**
usa os mesmos dados extraídos, mas remonta o mundo em 3D.

## Estratégia: "câmera primeiro"

O jogo clássico é 2D pré-renderizado, mas foi **renderizado a partir de cenas 3D reais**. Nós
temos as **câmeras originais** (posição + alvo) no `.ARD`. Então:

1. Coloca-se cada câmera fixa no espaço 3D (transform real do jogo).
2. Projeta-se o **background HD** daquela câmera como *backdrop*.
3. Modela-se a geometria 3D até ela "encaixar" perfeitamente na foto, ângulo por ângulo.
4. Com todas as câmeras de uma sala, a geometria converge para o volume 3D correto.

## Insumos e como cada um ajuda o 3D

> Nºs e detalhes puxados de `../docs/formatos/*` e da fonte de verdade
> `../docs/decomp/progress.json`. Notas de modelagem por sistema em [`blueprints/`](blueprints/).
>
> **Estado da decompilação (progress.json): ~99% decompilado.** Todas as unidades de insumo da
> v2 estão em **100% decompilado**, exceto `enemy` (**85%** — malha in-RAM do PS1 é histórico;
> os modelos vêm limpos do EMD do GOG). O que resta é majoritariamente **vínculo** (integração no
> protótipo), não pesquisa de formato.

| Insumo | Origem | Uso no mapa 3D |
|---|---|---|
| **Câmeras** (pos/alvo) | `.ARD` → RID (**2.105** em 169 salas) | ✅ Rig 3D + **escala confirmada** (`world_scale=808`, Y p/ baixo). Na v2 viram **âncoras sugeridas** (câmera livre), não cortes fixos. Ver [blueprints/03](blueprints/03_cameras_e_rvd.md) |
| **Zonas de câmera (RVD)** | `.ARD` offset_table[8] (**4.585** entradas) | ✅ decodificado: faixas de histerese + **frustums** por câmera → limites/adjacência das salas. A métrica de enquadramento `\|ndc_x\|` (torso projetado) valida a escala/projeção |
| **Colisão** | RDT offset_table[6] | ✅ **decodificado** (`tools/rdt_collision.py`) → **blockout** de chão/paredes/móveis (retângulos XZ, `{sala}_col.json`) = esqueleto navegável 3D. Ver [blueprints/02](blueprints/02_colisao_blockout.md) |
| **Backgrounds HD** | Seamless HD (`hd_map.json`, `stage_offset=1` ✅) | Referência de **textura/iluminação** por câmera (1280×960 = 4× PS1) para modelar cada ângulo |
| **Mapas HD (plantas)** | `MAP_U.MAP` + `hires/map` | ✅ em `reconstruction/maps/` → **planta baixa macro** (layout das salas) p/ posicionar os volumes 3D |
| **Máscaras de profundidade / oclusão** | RDT `mask_data_ptr` + atlas HD 2048² | ✅ **formato 100% refeito** (desc. de grupo 8B; SQUARE 8B/RECT 12B; **Z per-sprite = `depth*16`**; `Σcount==n_masks` 1507/1507; 169 salas em `*_col.json`, 111.644 sprites). Na v2 a oclusão é **automática** (Z-buffer), mas o **Z per-sprite** dá profundidade real p/ posicionar/validar o 1º plano. Ver [blueprints/07](blueprints/07_iluminacao_texturas_oclusao.md) |
| **Portas / grafo de salas** | SCD → `room_graph.json` | ✅ **grafo AUDITADO: 453 portas** (era 447; +6 `sce==13`), **453/453 destinos resolvidos**, chegada 100% (`to_x/y/z/facing`); **296 arestas-sala** (279 recíprocas + 17 mão-única TODAS justificadas via `oneway_reason`). Só `sce∈{1,13}` troca de sala (provado). Ver [blueprints/04](blueprints/04_grafo_de_salas_portas.md) |
| **Modelos + animação** | `.PLD` (base) + `.PLW` (armado) | ✅ **PLD 100%** (rig limpo, `PL00≈0,002`) + malha+esqueleto (15 ossos)+skin+HD; **locomoção ARMADA multi-banco por arma** (3 bancos/arma; retargetada ao PLD). **Malha da arma decodificada** (63 `_WPN.glb`); anexo em `bone4`. Ver [blueprints/05](blueprints/05_personagens_e_animacao.md) |
| **Inimigos** | GOG `.EMD` (+ PS1 `R###.BIN`) | ✅ **69/69 EMD→`.glb`** (malha+UV+textura+esqueleto+anim); **rig fix** (`inverseBind=G_bind⁻¹` matou o splay; zumbi perfeito) com **resíduo em partes model-space** (hunters). IA: **12 overlays × 548 handlers** (`ai_overlays.json`). Espécie = anotação por confiança (sem mapa canônico estático). Ver [blueprints/06](blueprints/06_inimigos.md) |

## Pipeline

1. **Organizar por sala** → `reconstruction/STAGE{n}/<sala>/` com `cameras.json` (rig) +
   os backgrounds HD por câmera (`../tools/v2_rooms.py`).
2. **Cena Godot 3D por sala:** câmeras posicionadas + backdrop HD projetado.
3. **Blockout da colisão** → geometria base navegável.
4. **Modelagem** batendo com os backgrounds HD em cada ângulo.
5. **Câmera livre + iluminação + oclusão** (das máscaras).

## Estrutura

```
v2/
├─ README.md
├─ tools/              # ✅ pipeline de dados (ver tools/README.md)
│  ├─ consolidate_rooms.py   # junta tudo por sala -> room.src.json
│  ├─ extract_lights.py      # bloco LIT do RDT   -> lights.json (🟡 parcial)
│  └─ solve_layout.py        # portas -> pose de cada sala -> stage_layout.json
├─ editor/             # ✅ editor 3D web (three.js) — ver editor/README.md
├─ reconstruction/     # dados derivados p/ 3D
│  ├─ maps/               # ✅ plantas HD (planta baixa macro) + PS1 + map_depara.json
│  ├─ STAGE1..7/
│  │  ├─ stage_layout.json  # GERADO: pose de cada sala no stage
│  │  └─ stage_edits.json   # EDITADO: poses ajustadas à mão (sobrepõe o gerado)
│  └─ STAGE1..7/<sala>/
│     ├─ cameras.json      # rig de câmeras (pos/alvo/forward) + HD por câmera
│     ├─ room.src.json     # GERADO: colisão + câmeras + portas + gameplay + luzes
│     ├─ lights.json       # GERADO: pontos de luz (🟡 decodificação parcial)
│     ├─ room3d.json       # EDITADO: geometria ajustada, aberturas
│     └─ <sala>_<cam>.webp # background HD (referência de modelagem)
├─ blueprints/         # ✅ notas de reconstrução por SISTEMA (versionável) — herança da decomp
└─ godot3d/            # (futuro) projeto Godot 3D da v2
```

> **Regra do pipeline:** o *gerado* e o *editado* nunca compartilham arquivo. Rodar os
> scripts de novo jamais destrói ajuste manual. Detalhes em [`tools/README.md`](tools/README.md).

### Layout do stage — RESOLVIDO

O RE3 **não tem espaço mundial** (cada sala usa o range inteiro de `s16` localmente; cruas,
99% das salas do STAGE1 se sobrepõem). `tools/solve_layout.py` deduz a pose de cada sala
tratando cada porta recíproca como uma restrição — as duas pontas descrevem o mesmo umbral.

Descoberta: **6 dos 7 stages resolvem com rotação zero** — as salas compartilham os eixos,
só a origem muda (offset mediano de 32 m). Erro de fechamento de 0,05 m (STAGE5) a 5,7 m
(STAGE6); o STAGE7 fecha como componente único.

### Como cruzar os insumos por sala (receita de reconstrução 3D)

1. **Planta HD** (`reconstruction/maps/`) → posiciona os VOLUMES das salas no macro (onde cada sala fica).
2. **Colisão** (RDT `offset_table[6]`, `tools/rdt_collision.py`) → retângulos XZ de chão/parede/móvel = **blockout** exato de cada sala (as posições reais, em unidades PS1).
3. **Câmeras + zonas RVD** (`.ARD`) → âncoras/frustums; validam a escala (a métrica `|ndc_x|` projeta o alvo em ~0).
4. **Backgrounds HD** por câmera → modelar a geometria até "encaixar" na foto, ângulo por ângulo.
5. **Modelos+animação** (PLD base + PLW armado) → personagens/inimigos no mundo. Oclusão vira **automática** (Z-buffer 3D real).

## Calibração — RESOLVIDA (herdada da v1)

- ✅ **Escala:** `world_scale = 808` unidades PS1 por unidade Godot (validado: Jill ≈ 2,4 m; o alvo das câmeras projeta em `ndc_x≈0`). `godot = ps1 / 808`. Detalhes em [blueprints/01](blueprints/01_coordenadas_e_escala.md).
- ✅ **Sistema de coordenadas:** PS1 é **Y para baixo**; conversão `godot = Vector3(x, -y, z) / 808` (inverte só o Y). Usada em toda a v1 (`room_game.gd`). No Blender (Z-up): `(x, z, -y)/808`.
- ✅ **Locomoção:** velocidades reais medidas do PLW armado (andar ~78 un/f → 2,8 u/s; correr ~222 → 8,3). Ver `godot/data/anim_map.json` e [blueprints/05](blueprints/05_personagens_e_animacao.md).
- ✅ **`stage_offset = 1`** (PC 0–6 ↔ PS1 STAGE1–7) **confirmado** (PC `ROOM0000` = PS1 `STAGE1/R100`).

**A confirmar:** **FOV por câmera.** A v1 usa **55°** (vertical, global); o script Blender usa **58,5°** (do `attr` mais comum, 3456). O campo `attr` da câmera (RID) tem **24 valores distintos** → provável FOV/projeção **por câmera** — decodificar `attr → FOV` fecharia o encaixe da foto em todos os ângulos. Ver [ARD.md §3.3](../docs/formatos/ARD.md).

## Descobertas herdadas da decomp (cross-links)

Este `v2/` herda tudo da RE dirigida. Fontes (só leitura):

- **Índice de formatos:** [`../docs/formatos/README.md`](../docs/formatos/README.md) · **tracker:** [`../docs/decomp/progress.json`](../docs/decomp/progress.json)
- **Plano — a v2 é a [Fase E](../docs/decomp/PLANO_ACAO.md)** (reconstrução 3D por sala: colisão + frustums + plantas HD como blueprint).
- Notas de modelagem por sistema: **[`blueprints/`](blueprints/)**.

| Sistema | Doc de formato | Blueprint v2 |
|---|---|---|
| Coordenadas/escala | [godot_gameplay.md](../docs/godot_gameplay.md) | [01](blueprints/01_coordenadas_e_escala.md) |
| Colisão (blockout) | [ARD.md §3.6](../docs/formatos/ARD.md) | [02](blueprints/02_colisao_blockout.md) |
| Câmeras + RVD | [ARD.md §3.3/§3.5](../docs/formatos/ARD.md) | [03](blueprints/03_cameras_e_rvd.md) |
| Grafo de salas/portas | [scd_gameplay.md](../docs/formatos/scd_gameplay.md) | [04](blueprints/04_grafo_de_salas_portas.md) |
| Personagens + animação | [PLD.md](../docs/formatos/PLD.md), [animacoes_player.md](../docs/formatos/animacoes_player.md) | [05](blueprints/05_personagens_e_animacao.md) |
| Inimigos | [enemy_bin.md](../docs/formatos/enemy_bin.md) | [06](blueprints/06_inimigos.md) |
| Iluminação/texturas/oclusão | [hd_seamless.md](../docs/formatos/hd_seamless.md), [BSS.md](../docs/formatos/BSS.md) | [07](blueprints/07_iluminacao_texturas_oclusao.md) |
