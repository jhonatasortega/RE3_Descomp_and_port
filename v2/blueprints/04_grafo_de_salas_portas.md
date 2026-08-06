# 04 · Grafo de salas / portas → conexões do mundo 3D

> Fonte: [`../../docs/decomp/notes/door_handler.md`](../../docs/decomp/notes/door_handler.md)
> (handler + destino), [`../../docs/decomp/notes/room_graph.md`](../../docs/decomp/notes/room_graph.md)
> (auditoria/reciprocidade) e [`../../docs/formatos/scd_gameplay.md`](../../docs/formatos/scd_gameplay.md).
> Ferramentas: `tools/scd_door_dest.py` + `tools/room_graph_build.py` → `godot/data/room_graph.json`.

## O que temos — grafo AUDITADO e FECHADO (100%)

A porta é o **AOT cujo SCE type (byte@+2) troca de sala** — SCE **∈ {1, 13}** — criado pelos
opcodes `0x61` (DOOR_AOT_SET, 32B) e `0x62` (DOOR_AOT_SET_4P, 40B). O destino (stage,room) é
**campo estático do SCD**, resolvido pelo de-para autoritativo do motor
`índice→fileid 0x8009dfd0[stage][room]→nome`:

- **453 portas** (era 447; a **auditoria** descobriu **6 `sce==13`** — porta condicional/scripted,
  handler `0x80051cb0` — que estavam sendo descartadas → 3 pares recíprocos `R114↔R118`,
  `R304↔R30A`, `R40C↔R40E`). Total corrigido **447 → 453**.
- **453/453 destinos resolvidos** (`to_stage`/`to_room`/`to_room_id`), **0 TODO**.
- **Todas com posição de CHEGADA** (`to_x, to_y, to_z, to_facing`) — decodificação 100%, inalterada.
- **296 arestas-sala** únicas (gêmeas coladas): **279 recíprocas (94,3%)** + **17 mão-única
  TODAS justificadas** (campo `oneway_reason` por aresta) ⇒ **reciprocidade EXPLICADA a 100%**,
  `mao_unica_nao_explicada = 0`. Motivos das 17: mercenaries (4), story_variant (3),
  story_progression_gate (2), endgame/boss (3), queda (1), layout (1), especial (1),
  variante-scripted (1), placeholder (1).
- **Cobertura PROVADA:** varrendo TODOS os opcodes AOT das 169 salas, só `sce∈{1,13}` troca de
  sala; o room-loader `0x800493ec` só é chamado pelo cluster do door_handler (**sem warp por
  script**). Nenhum erro de destino/parse na auditoria 1-a-1.

Exportado em `godot/data/room_graph.json`: **169 nós** (salas) + **453 arestas** (portas), cada
aresta com `arrival {x,y,z,facing}`, `to_stage/to_room/to_room_id`, `dest_source`, `dest_conf`
e — novo — **`reciprocal` (bool)** e (se `false`) **`oneway_reason`**.

## Como usar na v2

1. **Nós = salas**; posicioná-las no macro pela **planta HD** ([07](07_iluminacao_texturas_oclusao.md))
   e pelo centro da colisão ([02](02_colisao_blockout.md)).
2. **Arestas = portas com destino**: como o `to_stage/to_room` está **resolvido**, o grafo já é
   o **mapa de conexões do mundo 3D pronto** — sem montagem manual. Cada aresta é um **portal**
   entre duas salas.
3. **Spawn de transição pronto:** o **ponto/facing de chegada** dá **onde o jogador aparece** e
   **para onde olha** ao entrar; o destino dá **em qual sala** carregar. Basta encadear
   `porta → carrega sala destino → posiciona no arrival`.
4. **Direcionalidade fiel:** usar `reciprocal`/`oneway_reason` para modelar portas de mão-única
   (queda, gates de progressão, boss, Mercenaries) — não gerar volta onde o original não tem.
5. O script Blender já materializa as portas como caixas (`{sala}_Door_j`) a partir do JSON da sala.

> Também disponível no SCD: **738 gatilhos** (eventos/mensagens/save/dano…), **433 entidades**
> (modelos/NPCs) e **14 itens** (0x68) posicionados — insumos para povoar o mundo 3D
> (ver [scd_gameplay.md](../../docs/formatos/scd_gameplay.md)).
