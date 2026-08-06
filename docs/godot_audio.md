# Áudio no Godot — AudioManager (BGM + SFX)

> **Guia do protótipo** (implementação v1). Formato-fonte / extração dos assets:
> [formatos/audio_video.md](formatos/audio_video.md). Índice em [`README.md`](README.md).

Gerenciador de trilha sonora e efeitos do remake de RE3. Estilo RE3: **uma BGM ambiente
por sala/área**, que troca (com crossfade) ao mudar de área; SFX one-shot para as ações
principais.

- **Script:** `godot/scripts/audio/audio_manager.gd` (autoload — ver §5)
- **Dados:** `godot/scripts/audio/bgm_map.json` (BGM→área) e `sfx_map.json` (nome→arquivo)
- **Assets:** BGM em `res://assets/SOUND/BGM/gog/*.ogg` (62 faixas, GOG);
  SFX em `res://assets/SOUND/SFX/<banco>/<banco>_NN.wav` (298 amostras, VAB real)
- **Teste:** `godot/dev/tools_audio_test.gd` (headless, 10 checks)

Detalhes de extração/conversão dos assets: `docs/formatos/audio_video.md` §9.

## 1. API

```gdscript
AudioManager.play_bgm(area: String, loop := true)   # BGM da área (UPTOWN, DOWNTOWN, ...)
AudioManager.play_bgm_track(track: String)          # faixa específica (ex.: "main2c")
AudioManager.stop_bgm(fade := 1.0)                  # fade-out e para
AudioManager.play_sfx(name: String, pitch := 1.0)   # one-shot (door, gunshot, ...)
AudioManager.set_bgm_volume_db(db)
AudioManager.set_sfx_volume_db(db)
AudioManager.is_bgm_playing() -> bool
AudioManager.current_track()  -> String
```

- **Crossfade:** ao chamar `play_bgm`/`play_bgm_track` com faixa diferente, faz crossfade
  de `CROSSFADE_TIME` (1,2 s) entre dois `AudioStreamPlayer` internos. Chamar com a **mesma
  área/faixa** que já toca é no-op (não reinicia).
- **Polifonia de SFX:** pool de 8 `AudioStreamPlayer` (round-robin).
- **Carga runtime, sem depender de import:** OGG via `AudioStreamOggVorbis.load_from_buffer()`,
  WAV via parser RIFF próprio → `AudioStreamWAV`. Funciona headless e sem `.import`.
- **`PROCESS_MODE_ALWAYS`:** o áudio continua tocando com a árvore pausada (menu/inventário).
- Usa o bus **`Master`** (não cria bus novo; volumes são por `volume_db` dos players).

## 2. Mapa BGM → área (`bgm_map.json`)

Áreas do jogo (de `godot/assets/MAP/map_depara.json`): **UPTOWN, DOWNTOWN, CLOCK_TOWER,
PARK, DEAD_FACTORY, POLICE_STATION, HOSPITAL**.

| Área | Faixa (provisória) |
|---|---|
| UPTOWN | `main2c` |
| DOWNTOWN | `main17` |
| CLOCK_TOWER | `main19` |
| PARK | `main1a` |
| DEAD_FACTORY | `main18` |
| POLICE_STATION | `main1d` |
| HOSPITAL | `main2d` |

Contextos especiais em `context`: `TITLE`, `SAVE`/`SAVE_ALT`, `DANGER`, `NEMESIS`,
`GAMEOVER`, `ITEM_GET_JINGLE`.

> **TODO (confiança BAIXA):** os pares área→faixa são **provisórios**. No RE3 o vínculo
> real é **BGM_ID → sala**, definido nos scripts **SCD/RDT** (instrução de "set bgm"), não
> por área. Quando o grafo de salas com `bgm_id` for decodificado (outro agente / decode do
> handler no executável), preencher `bgm_map.room_override` com `id_sala → track` (o
> `AudioManager` já tem o campo, hoje vazio) e validar por ouvido. A chave do `AudioManager`
> hoje é a **área** (`play_bgm(area)`), como fallback por STAGE/área pedido.

## 3. Mapa de SFX (`sfx_map.json`)

Nomes lógicos → arquivo (relativo a `res://assets/SOUND/SFX/`, sem extensão; o manager
tenta `.wav`):

| Nome | Alvo (provisório) |
|---|---|
| `menu_move` | `C_00/C_00_01` |
| `menu_confirm` | `C_00/C_00_03` |
| `footstep` | `C_00/C_00_04` |
| `gunshot` | `C_00/C_00_05` |
| `item_get` | `C_00/C_00_02` |
| `door` | `C_00/C_00_06` |
| `hurt` | `C_00/C_00_08` |

> **TODO (confiança BAIXA):** os alvos foram escolhidos por **heurística de duração**, sem
> validação audível. `C_00`/`C_01` = banco global do jogador (o correto para essas ações);
> corrigir os índices ouvindo as amostras. Obs.: o **item get** do RE3 é, na verdade, um
> jingle de BGM (ver `context.ITEM_GET_JINGLE`) — aqui há também um SFX curto como opção.
> A biblioteca completa (298 amostras, 34 bancos) está em `assets/SOUND/SFX/` para escolha.

## 4. Gancho na cena jogável (NÃO implementado aqui)

`godot/scripts/room_game.gd` é mantido por **outro agente** e **não** foi editado. Para
ligar o áudio ao gameplay, adicionar lá (ou em quem controla a troca de sala/câmera):

```gdscript
# ao ENTRAR numa sala / trocar de área (ex.: no _show_camera ou no load da sala):
AudioManager.play_bgm(area_da_sala)   # area_da_sala: "UPTOWN"/"DOWNTOWN"/... (map_depara)

# nas ações do jogador:
AudioManager.play_sfx("footstep")     # passo
AudioManager.play_sfx("gunshot")      # tiro
AudioManager.play_sfx("door")         # abrir porta / transição de sala
AudioManager.play_sfx("item_get")     # pegar item
AudioManager.play_sfx("hurt")         # dano

# no menu/inventário:
AudioManager.play_sfx("menu_move")    # navegar
AudioManager.play_sfx("menu_confirm") # confirmar
```

Como derivar `area_da_sala`: a sala tem `stage`/`room` (ver `godot/data/map_graph.json`) e
o `map_depara.json` associa página→área; enquanto não houver o mapa exato sala→área,
mapear por STAGE (STAGE1≈UPTOWN, etc.) e refinar depois.

## 5. Autoload a registrar

Adicionar em `godot/project.godot`, seção `[autoload]`:

```
AudioManager="*res://scripts/audio/audio_manager.gd"
```

(Não editei `project.godot` — consolidação dos autoloads é feita à parte para evitar
conflito entre agentes.)

## 6. Verificação (headless)

```bash
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path godot --script res://dev/tools_audio_test.gd
```

Resultado atual: **10 OK, 0 FALHA** — `play_bgm(UPTOWN)` carrega e toca (`main2c`),
crossfade para `DOWNTOWN` (`main17`), e os 7 SFX (`gunshot`, `door`, `item_get`,
`footstep`, `hurt`, `menu_move`, `menu_confirm`) disparam. Confirma que **`.ogg` e `.wav`**
carregam e entram em `playing` (headless usa driver de áudio dummy: valida a carga e o
estado, não a saída sonora — para ouvir, rodar sem `--headless`).
```
=== AUDIO TEST ===
[AudioManager] pronto. areas=7 sfx=7
[AudioManager] BGM -> main2c
[ OK ] play_bgm(UPTOWN) -> track='main2c' playing=true
... (7 SFX OK) ...
[AudioManager] BGM -> main17
[ OK ] play_bgm(DOWNTOWN) -> track='main17' playing=true
=== RESULTADO: 10 OK, 0 FALHA ===
```
