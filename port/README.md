# `port/` — Port 1:1 do RE3 Nemesis para Godot 4

Projeto do **port fiel** (câmeras fixas, timing de 30 Hz do PS1) com os assets visuais em HD do
**Seamless HD Project**. Plano operacional e checklist:

- **Plano:** [`../docs/port/PLANO_MIGRACAO.md`](../docs/port/PLANO_MIGRACAO.md)
- **Progresso:** [`../docs/port/PROGRESSO.md`](../docs/port/PROGRESSO.md) (gerado por `python tools/port_progress.py`)
- **O que já foi decompilado:** [`../docs/decomp/PROGRESS.md`](../docs/decomp/PROGRESS.md)

> **Não confundir:** [`../godot/`](../godot/) é o protótipo antigo (referência/arquivo morto) e
> [`../v2/`](../v2/) é a linha 3D de câmera livre (independente, **não é tocada** por este port).

## Arquitetura (P0-08)

Um único autoload — **`Game`** ([core/game.gd](core/game.gd)) — dono do relógio, do estado e
da entrada. A ordem de update por tick é fixa e vive lá:

```
_physics_process (30 Hz)          project.godot: physics_ticks_per_second=30
		│                                        max_physics_steps_per_frame=1
		▼
   Clock.step()  ──emite──▶  Game._on_tick(frame)
								 │
								 ├─ 1. Pad.poll()        máscara de bits do tick (ou replay)
								 ├─ 2. GameState         flags (16 bancos), inventário, progresso
								 └─ 3. sinal Game.tick   quem ouve, nesta ordem:
										F1 actors/  → player_sm, combat
										F1 room/    → câmera (RVD), colisão, oclusão
										F2 script_vm/ → VM do SCD (AOT, flags, spawns)
										F5 actors/ai/ → IA por classe
										present/    → desenha (nunca decide nada)
```

Quem depende de quem: `core/` não conhece nada; `script_vm/` só conhece `core/`; `room/` e
`actors/` conhecem `core/` e são coordenados pelo `Game`; `present/` **só lê** estado e
desenha. Sistema não chama sistema por dentro — a coordenação é do `Game`.

| Módulo do núcleo | Papel | Provado por |
|---|---|---|
| [core/clock.gd](core/clock.gd) | 30 Hz fixo, tick contado (nunca `delta`) | `dev/tests/test_clock.gd` |
| [core/ps1_math.gd](core/ps1_math.gd) | ângulo de 12 bits + sin/cos da tabela do EXE | `test_ps1_math.gd` (4096 ângulos, erro 0) |
| [core/coords.gd](core/coords.gd) | PS1 (Y-down) ↔ Godot, `world_scale=808` | `test_coords.gd` (10k pontos + 2105 câmeras) |
| [core/game_state.gd](core/game_state.gd) | flags (fórmula word/mask do EXE), inventário, save | `test_game_state.gd` |
| [core/pad.gd](core/pad.gd) | entrada como máscara + gravação/replay | `test_pad.gd` |

## Controles (provisórios, P7-03 define os definitivos)

| Tecla | Ação | Nota |
|---|---|---|
| **W** | andar para frente | frente = -Z do nó; sinal fixado por teste de regressão |
| **S** | ré | sempre em velocidade de andar (o RE3 não corre para trás) |
| **A / D** | girar no lugar | D = horário visto de cima (**diminui** o ângulo PS1) |
| **Shift** | correr | só para frente |
| **S + Shift** | quick-turn de 180° | disparado na borda, 8 ticks |
| **E** (ou Enter) | **ação**: abre porta / pega item (encostar não basta, como no RE3) |
| **Espaço** | mirar | exige arma equipada (`player+0x46 != 0`) |
| **[** / **]** | trocar de câmera à mão | depuração |
| **F9** | alternar 4:3 ↔ 16:9 | o 16:9 corta 25% da altura |
| **F2** | teleportar para a próxima porta | afordância de teste: atravessa e troca de sala |
| **F3** | listar no console o que o script instalou | AOTs, portas e destinos da sala atual |

Rodar: `godot --path port` (ou `--rendering-driver opengl3` se a GPU reclamar).

## Regra de camada

`core/` e `script_vm/` **não referenciam nó visual nenhum** — é isso que permite rodar a VM do
script e a física em teste headless. Erro do protótipo antigo: lógica de sala e apresentação
moravam juntas em `room_game.gd`.

| Pasta | Papel | Fase |
|---|---|---|
| `core/` | Camada determinística: tick de 30 Hz, matemática PS1 (ângulo 4096 + sin/cos do jogo), coordenadas, flags globais, entidade | F0 |
| `script_vm/` | **VM do SCD**: dispatch dos 144 opcodes (`0x00..0x8f`), threads, AOT | F2 |
| `room/` | Runtime de sala: loader, câmera RID, troca por RVD, colisão, oclusão por atlas HD, portas | F1/F3 |
| `actors/` | Player (SM de 8 ações), combate (mira/hitscan/dano) e `ai/` (uma classe por arquivo) | F1/F4/F5 |
| `present/` | Apresentação: modo de tela **4:3** (padrão) ou **16:9** experimental (crop), pillarbox, tonemap | F1 |
| `meta/` | Menus, inventário, mapa, files, FMV, save | F6 |
| `dev/` | Harness: screenshot, test runner, gravação/replay de input | F0 |
| `assets/` | **GERADO** pelo pipeline a partir da sua cópia do jogo — **gitignored** | F0 |
| `data/` | **GERADO** pelo pipeline (JSON de sala, tabelas) — **gitignored** | F0 |

## Como montar

`assets/` e `data/` **não são versionados** (conteúdo da Capcom + assets de fãs do SHDP). Eles são
gerados pelos scripts de [`../tools/`](../tools/) a partir de:

1. sua imagem do disco PS1 **NTSC-U** (`SLUS_009.23`), e
2. sua instalação de PC/GOG com o **Seamless HD Project** (lida como **somente leitura**).

O item **P0-02** do plano cria a CLI única de build (`tools/build_assets.py --out port`); até lá o
pipeline canônico são os scripts individuais de `tools/` descritos em
[`../docs/formatos/README.md`](../docs/formatos/README.md).

## Rodar

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --path port --headless --import      # importar assets
"$GODOT" --path port                          # abrir/rodar
```

> `--headless` usa driver dummy e **não renderiza**: para screenshot use `--rendering-driver opengl3`.
