# 03 · Câmeras (RID) + zonas RVD → âncoras e volume da sala

> Fonte: [`../../docs/formatos/ARD.md §3.3 (câmeras) e §3.5 (RVD)`](../../docs/formatos/ARD.md).
> Ferramentas: `tools/ard_parse.py`, `tools/cameras_to_3d.py`.

## Câmeras (RID) — 2.105 no jogo

Struct de 32 B por câmera (`offset_table[7]`, sempre em `0x60`), `n_cameras` por sala:

```
u16 flag · u16 attr (FOV/projeção?) · s32 from_x,y,z (posição) · s32 to_x,y,z (alvo) · u32 mask_data_ptr
```

- **Todas as 2.105** têm coordenadas sãs (|coord| ≤ 44388) e projetam o próprio `to` em
  `ndc_x ≈ 0` (confirma a calibração de escala/projeção).
- **Na v2 (câmera livre):** as câmeras deixam de ser cortes fixos e viram **âncoras
  sugeridas** — pontos de vista "cinematográficos" e, sobretudo, **referência de modelagem**
  (é o ângulo exato de cada background HD; ver [07](07_iluminacao_texturas_oclusao.md)).

### FOV — a confirmar (importante para o encaixe)

O campo `attr` tem **24 valores distintos** no jogo → provável **FOV/projeção por câmera**.
Hoje: v1 usa **55°** vertical (global); o script Blender usa **58,5°** (do `attr` comum 3456).
**Decodificar `attr → FOV` por câmera** fecharia o encaixe da geometria na foto em todos os
ângulos (hoje há erro residual onde o `attr` foge do comum).

## Zonas RVD — 4.585 entradas

`offset_table[8]`; structs de 20 B terminadas por `0xFFFF`: `flags · from_cam · to_cam ·
s16[8] (4 pontos do quadrilátero no chão)`.

- Cada entrada é uma **zona direcional `from → to`**. Pares opostos (`A→B`/`B→A`) deslocados
  formam a **histerese** de troca na fronteira entre duas câmeras.
- `degenerate` (coord ±32768) = quad que se estende ao **frustum/infinito**.
- **Na v2:** o RVD é o **grafo de adjacência** entre câmeras/regiões (quais se tocam) e
  delimita o **volume coberto** de cada sub-área. Útil para:
  - definir **limites da sala** e transições de sub-região sem cortes;
  - portar o **algoritmo de seleção por enquadramento** (métrica `|ndc_x|` do torso projetado,
    histerese `KEEP=0.9`/`COVER=1.1`) caso se queira um **modo "câmera clássica"** opcional.

> A semântica fina dos `flags` (bit `0x0001` = zona ativa; byte alto = id/prioridade) **não é
> necessária**: usa-se o RVD só como grafo de vizinhança, robusto a bits não decifrados.
