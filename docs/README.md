# Documentação — RE3 Nemesis (PS1 NTSC-U) · índice mestre

> Mapa de toda a documentação do projeto. **Base:** disco **NTSC-U** (`SLUS_009.23`),
> raw CD MODE2/2352. A **fonte única de verdade do progresso** é
> [`decomp/progress.json`](decomp/progress.json) (regenerada em [`decomp/PROGRESS.md`](decomp/PROGRESS.md)).

## 1. Tracker de decomp (fonte de verdade — só leitura)
| Doc | Papel |
|---|---|
| [`decomp/progress.json`](decomp/progress.json) | **Fonte de verdade:** % por unidade (decompilado/vinculado), pesos, notas. |
| [`decomp/PROGRESS.md`](decomp/PROGRESS.md) | Visão gerada do tracker (onde estamos). Não editar à mão. |
| [`decomp/PLANO_ACAO.md`](decomp/PLANO_ACAO.md) | Plano de ação decomp-first (fases A–E). Companheiro do tracker. |

## 2. Formatos de arquivo (RE dirigida)
Índice completo com STATUS por formato em **[`formatos/README.md`](formatos/README.md)**.
Cada doc de formato abre com um bloco STATUS puxado do `progress.json`.

- Disco: [rofs](formatos/rofs.md)
- Gráficos: [BSS](formatos/BSS.md) · [map](formatos/map.md) · [HD backgrounds](formatos/hd_seamless.md) / [mapeamento HD](formatos/hd_mapping.md) · [HD UI](formatos/hd_ui.md)
- Modelos: [PLD/PLW](formatos/PLD.md) · [animação do player](formatos/animacoes_player.md) · [inimigos R###.BIN](formatos/enemy_bin.md)
- Sala/lógica: [ARD/RDT](formatos/ARD.md) · [SCD (formato)](formatos/SCD.md) · [SCD (gameplay)](formatos/scd_gameplay.md)
- Áudio/vídeo: [audio_video](formatos/audio_video.md)
- Executável: [exe (SLUS_009.23)](formatos/exe.md)

## 2b. PORT 1:1 para Godot (linha de trabalho ATUAL) ← FOCO
Reinicialização do port **fiel ao PS1** (câmeras fixas, timing de 30 Hz) com os **assets HD do
Seamless HD Project**, em projeto novo **`port/`** (o `godot/` antigo vira referência).
| Doc | Papel |
|---|---|
| [`port/PLANO_MIGRACAO.md`](port/PLANO_MIGRACAO.md) | **Plano operacional** do port: decisões, arquitetura, 8 fases com gates, metodologia de validação, riscos/limites. |
| [`port/port_progress.json`](port/port_progress.json) | **Fonte de verdade** do port: 78 itens com `impl`/`valid`, peso, critério de validação. |
| [`port/PROGRESSO.md`](port/PROGRESSO.md) | Checklist gerado (`python tools/port_progress.py`). Não editar à mão. |

> As **Fases C/D** do [`decomp/PLANO_ACAO.md`](decomp/PLANO_ACAO.md) (restaurar/ampliar o
> protótipo em `godot/`) estão **superseded** por este port. A Fase E (v2 3D, `../v2/`) segue
> independente e **não é tocada** por esta linha.

## 3. Guias do protótipo Godot (implementação da v1 — histórico/referência)
Como os assets/dados decodificados são usados na fatia vertical jogável.
| Doc | Cobre | Formato-fonte |
|---|---|---|
| [`godot_gameplay.md`](godot_gameplay.md) | Sala jogável, câmera fixa+seleção por enquadramento, colisão, oclusão | [ARD.md](formatos/ARD.md) |
| [`godot_audio.md`](godot_audio.md) | AudioManager (BGM por área + SFX) | [audio_video.md](formatos/audio_video.md) |
| [`godot_ui.md`](godot_ui.md) | HUD + inventário fiel + seletor de idioma | [PLD.md](formatos/PLD.md), [scd_gameplay.md](formatos/scd_gameplay.md) |

## 3b. Remake 3D — v2 (câmera livre)
A **[Fase E](decomp/PLANO_ACAO.md)** vive fora de `docs/`, em [`../v2/`](../v2/README.md):
reconstrução 3D real por sala, herdando as descobertas da decomp. Notas por sistema em
[`../v2/blueprints/`](../v2/blueprints/README.md) (coordenadas/escala, colisão→blockout,
câmeras+RVD, grafo de salas, personagens, inimigos, iluminação/oclusão).

## 4. Referências externas
| Doc | Papel |
|---|---|
| [`referencias/evilresource.md`](referencias/evilresource.md) | Roster de **nomes** (65 itens, 41 armas, 15 inimigos) — dá nome aos IDs extraídos (mapeamento hex↔nome ainda **a confirmar**). |

## 5. Inventário / estratégia / histórico
| Doc | Papel | Observação |
|---|---|---|
| [`inventario.md`](inventario.md) | Estrutura do disco extraído (1334 arquivos, pastas) | Unidade `iso` (100%). |
| [`plano.md`](plano.md) | **Estratégia macro** original (fases 0–4, v2 3D) | Mantido como visão de longo prazo; o plano operacional é o [`decomp/PLANO_ACAO.md`](decomp/PLANO_ACAO.md). |
| [`progresso.md`](progresso.md) | **Log histórico** da Fase 0–2 | **Superseded** pelo tracker (`decomp/`); mantido como registro. Números antigos podem estar defasados. |
| [`descobertas.md`](descobertas.md) | Índice vivo dos fatos confirmados da RE | Complementa os docs de formato. |

## Convenções
- **pt-BR**; little-endian; ponto-fixo com sinal; PS1 **+Y para baixo**.
- Marcadores: **✅** confirmado · **🟡** parcial/a confirmar · **⬜** não iniciado.
- Não editar `decomp/` à mão (fonte de verdade do coordenador). Não distribuir assets da Capcom.
