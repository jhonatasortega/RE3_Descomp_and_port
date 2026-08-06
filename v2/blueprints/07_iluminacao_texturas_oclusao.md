# 07 · Iluminação, texturas HD e oclusão

> Fonte: [`../../docs/formatos/hd_seamless.md`](../../docs/formatos/hd_seamless.md),
> [`../../docs/formatos/hd_mapping.md`](../../docs/formatos/hd_mapping.md),
> [`../../docs/formatos/BSS.md`](../../docs/formatos/BSS.md),
> [`../../docs/formatos/map.md`](../../docs/formatos/map.md).

## Backgrounds HD como referência de modelagem/iluminação

- **Seamless HD** (`hires/bgd`): backgrounds **1280×960 = 4× o PS1** (320×240), por câmera.
- Mapa autoritativo **sala→hash** via cache `ROOMxxxx.dat` (`godot/data/hd_map.json`);
  **`stage_offset = 1` confirmado** (PC `ROOM0000` = PS1 `STAGE1/R100`). 170 salas, 1.521 câmeras.
- **Uso na v2:** cada background HD é a **foto exata** do ângulo de uma câmera → é o gabarito
  para (a) **modelar a geometria** até "encaixar" e (b) **calibrar a iluminação** (direção/cor
  da luz que produziu aquele render). Os `.BSS` PS1 (2.109, decodificados) servem de fallback
  onde não há HD.

## Plantas HD (layout macro)

- `MAP_U.MAP` (9 páginas, 7 áreas) + `hires/map` → plantas baixas em
  [`../reconstruction/maps/`](../reconstruction/maps/) (`PS1_*.png`, `HD_*_x*.webp`,
  `map_depara.json`). **Uso:** posicionar os **volumes das salas** no macro antes de detalhar.

## Máscaras de profundidade — FORMATO 100% FECHADO (refeito)

> Fonte: [`../../docs/decomp/notes/occlusion.md`](../../docs/decomp/notes/occlusion.md).
> Ferramenta: `tools/rdt_collision.py::decode_masks` → `godot/data/STAGE{n}/{sala}_col.json`.

No PS1/v1 a oclusão (personagem atrás do cenário) é um **truque 2D**: "priority sprites"
(`mask_data_ptr` no RDT, atlas HD 2048²) que recortam o 1º plano e o redesenham por cima do
personagem — **independente da colisão** (um cano oclui sem colidir).

A decodificação foi **refeita 100%** (o formato antigo, ~80%, tinha os **campos trocados**):

- **Cabeçalho** = `n_offsets` (grupos) + `n_masks` (sprites totais), seguido de uma **tabela de
  descritores de grupo de 8B** `(count, z_base=0x7800, add_x, add_y)`.
- Cada sprite é **SQUARE (8B)** ou **RECT (12B)**, discriminado pelo **byte +6**; ordem real dos
  campos = `src_x, src_y, dst_x, dst_y, u16 depth, size/…`.
- **Posição de tela** = `(dst_x+add_x, dst_y+add_y)`; **Z per-sprite = `depth*16`** (era um
  `depth0` constante errado).
- **Validado:** `Σ count == n_masks` em **1507/1507 câmeras** com máscara (169 salas); atlas por
  recall = 1.0; overlay no background HD casa com os móveis de 1º plano. **169 salas regeneradas**
  em `{sala}_col.json` (**111.644 sprites**; 76,8% RECT, 23,2% SQUARE; Z per-sprite 48…49.136).

## Como a oclusão informa profundidade/Z na v2

- **A oclusão em si vira AUTOMÁTICA pelo Z-buffer** (geometria 3D real): o cenário esconde
  naturalmente o que está atrás — não é preciso holdout nem atlas para renderizar.
- **Mas o Z per-sprite agora é dado quantitativo útil:** cada sprite de 1º plano carrega uma
  **profundidade real** (`depth*16`, mesma família do `z_base=30720`). Isso serve para (a)
  **posicionar em profundidade** os móveis/canos de 1º plano ao modelar cada ângulo (a que
  distância da câmera está o objeto que oclui), e (b) **validar** a geometria 3D — o objeto
  modelado deve ocluir o personagem no mesmo Z que o sprite original.
- `room_game.gd` (v1) consome o `{sala}_col.json` como holdout por retângulo; na v2 os mesmos
  `dx,dy,w,h` + `z` viram **referência de silhueta e profundidade** do 1º plano. (Vínculo v1:
  recalibrar `occ_depth_scale` para o Z per-sprite.)

## Resumo do que a v2 herda aqui

| Insumo | Papel na v2 |
|---|---|
| Background HD por câmera | Gabarito de modelagem + calibração de luz |
| Atlas TIM / máscara HD (`godot/assets/MASK/`) | Silhueta pixel-exata do 1º plano (recall=1.0) |
| `.BSS` PS1 decodificado | Fallback onde falta HD |
| Planta HD (`reconstruction/maps/`) | Layout macro das salas |
| Oclusão (`{sala}_col.json`, Z per-sprite) | Profundidade real do 1º plano p/ posicionar/validar (render é Z-buffer) |
