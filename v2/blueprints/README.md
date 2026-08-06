# Blueprints da v2 — notas de reconstrução 3D por sistema

Cada nota destila o que a **decompilação de conteúdo** (RE dirigida) já descobriu e traduz
para **como usar na reconstrução 3D real** (câmera livre). Fonte primária: os docs de formato
em [`../../docs/formatos/`](../../docs/formatos/) e a fonte de verdade
[`../../docs/decomp/progress.json`](../../docs/decomp/progress.json) (só leitura).

A v2 é a **[Fase E](../../docs/decomp/PLANO_ACAO.md)** do plano de ação.

| # | Nota | Cobre | Estado |
|---|---|---|---|
| 01 | [coordenadas_e_escala](01_coordenadas_e_escala.md) | `world_scale=808`, PS1 Y-down, conversão Godot/Blender | ✅ resolvido |
| 02 | [colisao_blockout](02_colisao_blockout.md) | Retângulos XZ do RDT → blockout 3D navegável | ✅ resolvido |
| 03 | [cameras_e_rvd](03_cameras_e_rvd.md) | Câmeras RID + zonas RVD → âncoras/volume/adjacência | ✅ (FOV por câmera a confirmar) |
| 04 | [grafo_de_salas_portas](04_grafo_de_salas_portas.md) | 453 portas + destino + chegada → conexões do mundo 3D | ✅ resolvido (453/453 destinos) |
| 05 | [personagens_e_animacao](05_personagens_e_animacao.md) | PLD 100% + PLW multi-banco (locomoção armada) | ✅ (mesh de arma decodificada) |
| 06 | [inimigos](06_inimigos.md) | 69 EMD→glb (malha+UV+tex+anim); IA 12 overlays | ✅ (resíduo rig em model-space) |
| 07 | [iluminacao_texturas_oclusao](07_iluminacao_texturas_oclusao.md) | Backgrounds/plantas HD; oclusão 100% (Z per-sprite) | ✅ oclusão fechada |

## Princípio da v2 ("câmera primeiro")

Os cenários 2D do RE3 foram renderizados de **cenas 3D reais**. Temos as **câmeras originais**
(pos+alvo) e a **colisão real** → dá para reconstruir o volume 3D encaixando a geometria nas
fotos HD, ângulo por ângulo, com a escala já calibrada. Na v2 as câmeras deixam de ser cortes
fixos e viram **âncoras**; a oclusão 2D vira **Z-buffer automático**.
