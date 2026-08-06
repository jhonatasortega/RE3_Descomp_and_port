# Formatos de arquivo do RE3 Nemesis (PS1, NTSC-U) — índice mestre

> Documentação de **decompilação de conteúdo** (formatos/assets/lógica) do RE3 Nemesis
> PS1 NTSC-U (executável **`SLUS_009.23`**). Cada doc abaixo abre com um bloco **STATUS**
> cujo `Decompilado: NN%` vem da fonte única de verdade
> [`../decomp/progress.json`](../decomp/progress.json) (regenerada em
> [`../decomp/PROGRESS.md`](../decomp/PROGRESS.md)). O "a fazer" de cada formato aponta
> para [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md).
>
> **Regra:** os `%` e as notas de status **não** são editados aqui — só espelham o tracker.
> Se um número parecer errado, o ajuste é no `progress.json` (que é do coordenador).

## Índice por categoria

### Disco & Containers
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| `Rofs*.dat` | [rofs.md](rofs.md) | `tools/rofs_extract.py` | 100% | Container PC/GOG (índice de 2 níveis + cripto XOR/LCG + LZ); traz as vozes EN. |

> A extração do ISO PS1 (ISO9660 MODE2, `list_iso.py`/`extract_iso.py`, 100%) é
> documentada em [`../inventario.md`](../inventario.md), fora desta pasta.

### Gráficos / Cenário
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| `.BSS` | [BSS.md](BSS.md) | `tools/bss2png.py` | 100% | Backgrounds pré-renderizados 320×240 da sala (MDEC / STR "BS v3"). |
| `MAP_x.MAP` | [map.md](map.md) | `tools/map_decode.py` | 100% | Plantas da tela de mapa do menu (TIM 4bpp, 16 CLUTs) + de-para HD. |
| Backgrounds HD | [hd_seamless.md](hd_seamless.md) · [hd_mapping.md](hd_mapping.md) | `tools/hd_match.py`, `hd_copy.py` | 100% | Backgrounds/máscaras HD (Seamless HD Project) + mapa autoritativo sala→hash. |
| UI HD (de-para) | [hd_ui.md](hd_ui.md) | `tools/etc_hd_match.py` | — | Hash CRC-32 do blit; casamento de UI/itens/memos/mapa HD (sem unidade no tracker). |

### Modelos & Animação
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| `.PLD` / `.PLW` | [PLD.md](PLD.md) | `tools/pld2gltf.py`, `pld_hd_textures.py` | 100% (PLD/TIM) · 85% (PLW) | Modelos de personagem humano (malha+esqueleto+skin+anim+textura → glTF); armas. |
| Animação do player | [animacoes_player.md](animacoes_player.md) | `tools/pld2gltf.py`, `find_anim_banks.py` | 100% (anim) · 85% (PLW) | Bancos EDD do player; locomoção de gameplay vem do **PLW** da arma equipada. |
| Modelos de inimigo (EMD) | [enemy_bin.md](enemy_bin.md) | `tools/emd2gltf.py`, `bin2gltf.py` | 95% | 69/69 EMD (GOG) → glb; malha do `R###.BIN` do PS1 contornada. |

### Sala / Lógica (RDT / ARD)
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| `.ARD` / RDT | [ARD.md](ARD.md) | `tools/ard_parse.py`, `rdt_collision.py`, `cameras_to_3d.py` | 100% (contêiner/câmeras/colisão) · 98% (RVD) · 80% (oclusão) | Contêiner de sala: câmeras, colisão, zonas RVD, máscaras de profundidade, script. |
| SCD — **formato** | [SCD.md](SCD.md) | `tools/scd_decode.py` | 90% | Bytecode de eventos: cabeçalho de script + tamanhos de opcode (VM `0x8009e0f8`). |
| SCD — **gameplay** | [scd_gameplay.md](scd_gameplay.md) | `tools/scd_gameplay.py`, `scd_doors.py`, `scd_items.py` | 90% (SCD) · 50% (destino de porta) · 85% (IDs SCE) | Extração de portas/itens/inimigos/gatilhos + `room_graph.json`. |

### Áudio / Vídeo
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| XA / STR / BGM / SFX | [audio_video.md](audio_video.md) | jPSXdec, `tools/re3_sound.py`, `re3_sfx.py`, `bgm2midi.py` | 100% (vídeo/vozes/BGM-RE) · 80% (SFX) | Vídeos FMV, vozes XA e RE da trilha sequenciada (SEQ + VAB). |

### EXE / Código
| Formato | Arquivo | Ferramenta | Decomp. | O que é |
|---|---|---|---:|---|
| `SLUS_009.23` | [exe.md](exe.md) | `tools/exe_parse.py`, `exe_combat.py`, `exe_ai.py`, `exe_items.py` | 90% (SM do player) · 65% (mira/tiro) · 55% (IA) · 0% (handler de porta) | RE do executável PS1: física, HP/dano, mira/auto-lock, IA do zumbi (T64), flags. |

## Convenções

- **Little-endian** em todos os formatos; coordenadas 3D em **ponto-fixo com sinal**
  (unidades do mundo do RE, sem escala aplicada nos docs).
- **PS1 usa +Y para baixo**; a conversão para glTF (Y-up) é `(x,y,z) → (x,-y,-z)`.
- Marcadores de confiança nos docs: **✅** confirmado (validado por dado/render) ·
  **🟡** parcial / a confirmar · **⬜** não iniciado.
- Cross-links: cada doc referencia os relacionados e o `PLANO_ACAO.md` no que está "a fazer".

## Streaming (Mode 2 Form 2) — usar jPSXdec

`.STR`, `.XAS` (e o áudio muxado dos FMV) usam setores **Mode 2 Form 2** (2324 B úteis).
O extrator Python (`tools/extract_iso.py`) **não** os extrai corretamente — use **jPSXdec**
(ver [audio_video.md](audio_video.md)). A **trilha `.BGM` NÃO sai do jPSXdec** (é sequência
Capcom + banco VAB) — pipeline próprio em [audio_video.md §7](audio_video.md).
