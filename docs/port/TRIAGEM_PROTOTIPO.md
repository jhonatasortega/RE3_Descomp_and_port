# Triagem do protótipo antigo (`godot/`) — item P0-10

> Veredito arquivo por arquivo: o que **MIGRA** para o `port/`, o que fica só como
> **REFERÊNCIA** (consultar e reescrever) e o que **MORRE** (não reproduzir).
> Plano: [`PLANO_MIGRACAO.md`](PLANO_MIGRACAO.md) · Tracker: [`PROGRESSO.md`](PROGRESSO.md)
>
> Regra da triagem: **aproximação declarada não migra como se fosse fiel**. Onde o protótipo
> resolveu por heurística (câmera, oclusão, velocidade), o port refaz pelo algoritmo do EXE —
> por isso vários itens bons são "REFERÊNCIA", não "MIGRA".

## Scripts

| Arquivo | Linhas | Veredito | Por quê |
|---|--:|---|---|
| `scripts/jill_controller.gd` | 236 | **MIGRA** (base) | Movimentação validada (tank controls, quick-turn 180 programático, deslize por eixo, clipes ARMADOS `arm00/01/02/09` do PLW). Traz correções que a doc não tem: `model_yaw_offset_deg=90` (verificado por render; `godot_gameplay.md` diz 180) e velocidades armadas 2.8/8.3 (PLW seq0/seq1 = 78/222 un/frame). **Trocar** velocidade escalar × `delta` por root-motion por pose em tick de 30 Hz (P1-10) e o input direto por `Pad` (P0-09). Alvo: `actors/player_sm.gd` |
| `scripts/audio/audio_manager.gd` | 241 | **MIGRA** | AudioManager por área + SFX; nunca chegou a ser ligado na cena (por isso o jogo era mudo). Alvo: `present/` ou `core/audio.gd` (P1-13) |
| `scripts/audio/bgm_map.json`, `sfx_map.json` | — | **MIGRA** (dado) | Mapas gerados pelo pipeline (`re3_sound.py`, `re3_sfx.py`) — passam a viver em `port/data` |
| `scripts/lang_manager.gd` | 81 | **MIGRA** | Seletor de idioma + tocar voz por nome de cena. Estender com as tabelas PT-BR do mod (P6-11) |
| `scripts/ui/inventory.gd` + `scenes/ui/inventory.tscn` | 754 | **MIGRA** | Melhor peça do protótipo: inventário fiel (grade 2×4, EQUIP/USE/COMBINE/CHECK, ECG, ícones HD). Alvo: `meta/` (P6-02). Ligar ao `GameState` real em vez de ler `sce_items.json` direto |
| `scripts/room_game.gd` | 655 | **REFERÊNCIA** | Faz o certo (carregar sala, colisão real, seleção de câmera, oclusão) mas **mistura lógica e apresentação** num só nó e é hardcoded na R100 — é a razão de não escalar. O port separa em `room/` + `present/`. Consultar as calibrações (`world_scale=808`, FOV, `collider_radius=380`) |
| `scripts/room_explorer.gd` | 150 | **REFERÊNCIA** | Navegador de salas para inspeção; o equivalente no port é o harness de `dev/` |
| `scripts/model_viewer.gd` | 683 | **REFERÊNCIA** | Visualizador de modelo/animação — vira ferramenta de `dev/` quando a F4 precisar (validar rig dos EMD, P4-03) |
| `scripts/room_viewer.gd` | 13 | **MORRE** | Cena de background + câmera fixa, do primeiro dia. Substituída pelo `room/` |
| `scripts/hud.gd` + `scenes/hud.tscn` | 179 | **MORRE** | **RE3 não tem HUD em gameplay** (unidade `hud` do tracker de decomp: "remover do protótipo"). Um HUD seria invenção, não port |
| `scripts/ui/hud.gd` + `scenes/ui/hud.tscn` | 268 | **MORRE** (como HUD) | Mesmo motivo. **Salvar** o ECG e as palavras FINE/CAUTION/DANGER/POISON: elas pertencem à tela de STATUS (inventário), não ao gameplay |
| `scripts/inventory.gd` + `scenes/inventory.tscn` | 187 | **MORRE** | Grade genérica, placeholder explícito, superada pela versão `ui/` |

## Cenas

| Arquivo | Veredito | Por quê |
|---|---|---|
| `scenes/game_room.tscn` | **REFERÊNCIA** | A estrutura (Sprite2D de fundo + SubViewport transparente com o 3D por cima) é a ideia certa e vale copiar; o port a reconstrói em `present/` com o modo de tela parametrizado (P1-15) |
| `scenes/ui/inventory.tscn` | **MIGRA** | Junto com o script |
| `scenes/room_viewer.tscn`, `hud.tscn`, `inventory.tscn` | **MORRE** | Ver scripts correspondentes |
| `scenes/model_viewer.tscn`, `model_probe.tscn`, `rig_check.tscn`, `room_explorer.tscn` | **REFERÊNCIA** | Ferramentas de inspeção; renascem em `dev/` sob demanda |

## Harnesses de `godot/dev/` (20 arquivos)

| Arquivo | Veredito | Por quê |
|---|---|---|
| `tools_shot.gd` | **MIGRA** (padrão) | Screenshot com override por variável de ambiente: é o padrão que o `port/dev/shot.gd` adota |
| `tools_cam_walk.gd`, `tools_multicam_test.gd` | **MIGRA** (adaptado) | Travessia ida/volta medindo troca de câmera — vira o teste do P1-05, mas comparando com o **RVD** e não com a heurística de enquadramento |
| `tools_collision_val.gd`, `tools_move_val.gd`, `tools_walk_val.gd` | **MIGRA** (adaptado) | Viram testes automáticos da F1 (colisão/movimento), agora com replay de `Pad` |
| `tools_occlusion_val.gd`, `tools_occ_find.gd` | **REFERÊNCIA** | A oclusão do port é por atlas HD, não por caixa de profundidade — o método de validação (comparar pixel ocluído) continua valendo (P1-07) |
| `tools_orient_test.gd` | **REFERÊNCIA** ⚠ | **Fonte do `model_yaw_offset_deg=90`** verificado por render. Guardar: é a única prova dessa orientação |
| `tools_anim_shot.gd`, `tools_pose_shot.gd`, `tools_ingame_pose.gd`, `tools_weapon_shot.gd`, `tools_enemy_montage.gd`, `rig_check.gd`, `model_probe.gd` | **REFERÊNCIA** | Ferramentas de modelo/animação; úteis na F4, inclusive para o rig manual dos ~8-10 EMD (P4-03) |
| `tools_audio_test.gd`, `tools_inv_shot.gd`, `tools_gameplay_test.gd`, `tools_cam_align.gd` | **REFERÊNCIA** | Cenários de validação pontual, reescrever quando o sistema equivalente existir no port |

## Aproximações que NÃO migram (o ponto central da triagem)

| Aproximação do protótipo | O que o port faz | Item |
|---|---|---|
| Câmera escolhida por "melhor enquadramento" (projeção do torso, histerese em `ndc_x`) | Algoritmo do EXE: zonas **RVD** (stride `0x14`, ponto-em-quad, histerese em 2 fases) | P1-05 |
| Oclusão por **caixa 3D** de profundidade sobre a colisão | **Atlas de priority sprites** HD (`mask0/mask1` + `mask_data_ptr`, Z por sprite) | P1-07 |
| Velocidade escalar (`speed × delta`) | **Root-motion por pose** em tick fixo de 30 Hz | P1-10 |
| FOV global de 55° | FOV **por câmera** (campo `attr` do RID) | P1-04 |
| `collider_radius = 380` calibrado a olho | Raio real do EXE | P1-06 |
| Eventos de sala em GDScript | **VM do SCD** executando o script da sala | F2 |

## Dados (`godot/data/`)

Todos os 519 JSON são **regenerados** pelo pipeline no `port/data` — exceto as **6 sementes**
que nenhum script produz (`physics`, `anim_map`, `ai_overlays`, `sce_items`, `hd_ui_map`,
`re3_items`), copiadas com aviso até a dívida **P0-11** fechar.

## Assets (`godot/assets/`)

Regenerados no `port/assets` (5638 arquivos, verificados contra o manifesto). Pastas ainda
pendentes por depender de ferramenta externa ou curadoria manual: `VOICE`, `ZMOVIE`,
`SOUND/STAGE*`, `SOUND/BGM/*.ogg` e `UI` — todas declaradas como etapas **manuais** em
`tools/build_assets.py --list`.
