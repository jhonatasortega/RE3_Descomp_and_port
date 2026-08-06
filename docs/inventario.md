# Inventário do disco RE3 (estrutura real)

> **STATUS** (fonte: [`decomp/progress.json`](decomp/progress.json) → unidade `iso`, 100%).
> Índice mestre em [`README.md`](README.md). Gerado com `tools/list_iso.py`.
>
> ⚠️ **Corrigido:** a **base do projeto é NTSC-U** (`SLUS_009.23`), **não** PAL. O executável
> **não** é `SLES_025.29` (esse é o exe PAL, só referência) e o mapa é `MAP_U.MAP` (EN),
> não `MAP_E.MAP`. São só nomes de arquivo — nenhum conteúdo protegido é versionado.

- **Total:** **1.334 arquivos**, 14 pastas, ~619 MB de dados (extração NTSC-U).
- **Raiz:** `SYSTEM.CNF` (boot), **`SLUS_009.23`** (executável NTSC-U — ver [formatos/exe.md](formatos/exe.md)), `ZNULL.DAT` (padding ~37 MB).

## Pastas

```
/CD_DATA
├─ BIN/      181x .BIN   → telas/UI (TITLE, OPTION, OPENING, ENDING, RESULT, ...)
├─ ETC/      diversos    → logos (.TIM), itens (ITEMG/ITEMI.PIX), mapa (MAP_U.MAP/MAP_J.MAP), FILE*
├─ PLD/      27x .PLD    → modelos de personagens (todos HUMANOS: players/NPCs) → docs/formatos/PLD.md
│            84x .PLW    → modelos de armas do player
├─ SOUND/    .VB/.VH     → bancos de SFX (VAB); .BGM música
├─ STAGE1..7 .ARD (169) → dados de sala: script/eventos/objetos/itens/spawns
│            .BSS (169) → backgrounds pré-renderizados da sala
│            .DO1..DO7  → objetos/modelos de sala (78 cada — a confirmar)
├─ VOICE/    vozes
└─ ZMOVIE/   .STR (13)  → vídeos FMV (cutscenes)
```

## Extensões (contagem)

| Ext | Qtd | Significado (a confirmar) |
|---|---|---|
| BIN | 181 | Telas de UI empacotadas |
| ARD | 169 | **Sala**: script/eventos/objetos/itens |
| BSS | 169 | **Background** pré-renderizado da sala |
| PLW | 84 | Modelo de arma do player |
| DO1–DO7 | 78 cada | Objetos/modelos de sala (?) |
| VB / VH | 41 / 34 | Banco de SFX (VAB: VH=header, VB=corpo) |
| PLD | 27 | Modelo de personagem (HUMANO: player/NPC). Inimigos NÃO ficam aqui — estão embutidos em `STAGE#/R###.BIN` por sala. Ver `docs/formatos/PLD.md` |
| TIM | 24 | Textura/imagem PS1 |
| DAT | 19 | Dados diversos |
| STR | 13 | Vídeo FMV |
| XAS | 7 | Áudio em streaming (XA) |
| BGM | 6 | Música |
| PIX | 4 | Gráficos de item/inventário |
| MAP | 2 | Mapa do jogo (`MAP_U.MAP` EN + `MAP_J.MAP` JP) → [formatos/map.md](formatos/map.md) |
| ESP/SLD/SND/CNF | 1 cada | Diversos / config |

## Chave: pareamento ARD ↔ BSS

169 `.ARD` e 169 `.BSS` (contagens iguais) ⇒ cada sala tem um par
**lógica (ARD) + background (BSS)**. Esse é o núcleo da RE dirigida — destrava
eventos, itens, câmeras e colisão por sala.
