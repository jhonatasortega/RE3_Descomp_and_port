# 01 · Coordenadas e escala (RESOLVIDO)

> Fonte: [`../../docs/godot_gameplay.md`](../../docs/godot_gameplay.md) (calibração validada
> por render), [`../../docs/formatos/PLD.md §4`](../../docs/formatos/PLD.md),
> [`../../docs/formatos/exe.md §4`](../../docs/formatos/exe.md) (física root-motion).

## Fatos

- **Unidades:** o mundo do RE3 usa **ponto-fixo com sinal** (unidades PS1). Câmeras, colisão,
  portas e poses estão todas nessa mesma escala.
- **Eixo vertical:** o PS1 usa **+Y para BAIXO**.
- **Escala:** **`world_scale = 808`** unidades PS1 por unidade Godot. Derivado de `2400 / 2.971`
  (personagem ≈ 2400 un PS1; o `PL00.glb` tem 2,971 un de altura no Godot) e **validado por
  render** (Jill do tamanho certo, pés no chão, perspectiva batendo nas 2 câmeras da R100).

## Conversões (usar sempre)

```
Godot (Y-up):    godot   = Vector3(x, -y,  z) / 808     # inverte só o Y
Blender (Z-up):  blender = Vector3(x,  z, -y) / 808     # Y-down → Z-up
```

- Câmera: `position = conv(from)`, `look_at(conv(to))`.
- **Chão da sala** ≠ `entry.y` das portas. Na R100 o chão real ficou em PS1 `y ≈ -258`
  (achado por render); os `entry.y` das portas (~-1800/-2550) são outra referência (olho/teleporte).
- **Ângulos:** 12 bits, **4096 = 360°** (0,0879°/unidade); meia-volta/quick-turn = 2048.

## Velocidades (root-motion medido)

Gameplay a **~30 fps** (NTSC 60 Hz / 2). Movimento real do RE3 é **root-motion por pose**
(não constante escalar) — vetores em `godot/data/physics.json` (`velocidades.*.motion_por_pose_xyz`).
Valores do **banco armado** (PLW, o que se vê em jogo):

| Ação | un/frame | ≈ un/s Godot |
|---|---|---|
| Andar (PLW seq0) | ~78 | ~2,9 |
| Correr (PLW seq1) | ~222 | ~8,2 |
| Ré (PLW seq9) | ~68 | ~2,5 |

> Para a v2: usar **root-motion real** (não velocidade escalar) desde o começo — a v1 usava
> escalar como simplificação. Ver [05_personagens_e_animacao](05_personagens_e_animacao.md).
