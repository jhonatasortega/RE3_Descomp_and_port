# Descobertas — registro consolidado

> Índice vivo dos fatos **confirmados** da engenharia reversa. Docs detalhadas por formato
> em [`formatos/`](formatos/) (índice em [`README.md`](README.md)); progresso quantitativo
> na fonte de verdade [`decomp/progress.json`](decomp/progress.json).

## Disco / geral
- Imagem base: **NTSC-U** `Resident Evil 3 - Nemesis.bin`, raw CD **MODE2/2352**, ISO9660.
- **1.334 arquivos**, 14 pastas. Executável **`SLUS_009.23`** (via `SYSTEM.CNF`).
- Estrutura: `CD_DATA/{BIN, ETC, PLD, SOUND, STAGE1..7, VOICE, ZMOVIE}`.
- **`.DO1`–`.DO7` = PORTAS** (`DOOR00.DO1`…), animações de transição, 1 por stage.

## Imagens
- **`.TIM`** = formato padrão PS1 (4/8/16 bpp). 58 telas de `ETC/` → PNG. `PL00.PLD` = Jill.
- **`.BSS`** (backgrounds de sala) = contêiner de **slots de 64 KiB**; cada slot = 1 frame
  **MDEC / STR "BS v3"** (DCT estilo MPEG-1, **não** RLE/LZ). Header `+2=0x3800`, `+6=v3`.
  **169 arquivos → 2.109 backgrounds** 320×240. `tools/bss2png.py`.

## Salas (`.ARD`) → ver [formatos/ARD.md](formatos/ARD.md)
- Contêiner alinhado a **0x800**, **10 blocos**, tipos fixos `(5,5,5,5,6,6,6,6,0,2)`.
  Blocos 0–7 (tipos 5/6) = gráficos/VRAM (sprites de frente + máscaras). Bloco 9 (tipo 2) = extra.
- **Bloco 8 (tipo 0) = RDT** (lógica da sala): header 8B (`byte[1]=n_câmeras`) + **22 offsets**.
- **Câmeras (RID)** — struct de 32B: `flag, attr(FOV?), from[x,y,z], to[x,y,z], mask_data_ptr`.
  **2.105 câmeras** nas 169 salas (coords sãs). `tools/ard_parse.py` → `godot/data/STAGE{n}/*.json`.
- **Script SCD** em offset[16] (tabela de ponteiros de função). *Bytecode em decodificação.*

## Áudio / vídeo → ver [formatos/audio_video.md](formatos/audio_video.md)
- **XA streaming** (vozes/ambiente) e **FMV `.STR`** via **jPSXdec** (v2.0): 117 áudios WAV + 13
  vídeos AVI (320×160, 15 fps). Índice em `tools/re3.idx`.
- **Música = SEQUENCIADA, formato PROPRIETÁRIO Capcom** (não é SEQ/VAB padrão: sem magic
  `pQES`/`pBAV`). `.BGM` = N blocos de sequência (eventos estilo-MIDI, PPQN=48, running status)
  + banco de tons embutido; `.VB` = corpo PS-ADPCM dos instrumentos.
  - **6 sequências → MIDI** (`godot/assets/SOUND/BGM/*.mid`, `tools/bgm2midi.py`).
  - **VAB → SoundFont**: PS-ADPCM do `.VB` decodificado + banco de tons do `.BGM`
    (**32 presets, 46 samples**) → **`godot/assets/SOUND/BGM/re3.sf2`** (`tools/re3_sound.py`).
    Estrutura do tom (32 B): metade "meta" com assinatura `c0 00 c1 00 c2 00 c3 00`
    (prog@+4, vag@+6) + metade "attr" (center, shift, min, max); `center` pode ficar fora de `[min,max]`.
  - **6 faixas → WAV com instrumentos REAIS** via **fluidsynth** (`re3.sf2` + MIDI, 44.1 kHz
    estéreo, `-g 0.35`, **sem clipping**, RMS −16…−27 dBFS). Timbre autêntico do jogo, não GM.

## HD (upgrade visual) → ver [formatos/hd_mapping.md](formatos/hd_mapping.md)
- **Seamless HD Project** (GOG + Classic REbirth): backgrounds **`.webp` 1280×960 (4× PS1)**,
  máscaras **2048×2048**. Godot 4.7 lê webp nativo.
- **Mapa autoritativo via cache:** `hires\cache\ROOMxxxx.dat` = array `uint32` LE = `sala→hash`,
  em **tripletos `[background, mask0, mask1]` por câmera**. 99,7% de casamento.
- `godot/data/hd_map.json`: **170 salas, 1.521 câmeras, 1.232 backgrounds** + máscaras.
- ✅ **`stage_offset = 1` CONFIRMADO visualmente**: PC `ROOM0000` = PS1 `STAGE1/R100` (mesma
  sala — escritório S.T.A.R.S. — no HD 1280×960 e no PS1 320×240). Nomes espelham
  `R{stage}{room:02X}`. `tools/hd_copy.py` coloca o HD em `godot/assets/STAGE{n}/<sala>_<cam>.webp`
  e **remove o `.png` PS1** onde há HD (câmeras sem HD, ~600, mantêm o PS1).

## Ferramentas externas (em `tools/`, gitignored)
- **jPSXdec** v2.0 — extração de XA/STR (áudio/vídeo PS1). Índice em `tools/re3.idx`.
- **vgmstream-cli** — `tools/vgmstream/vgmstream-cli.exe` (tool geral de áudio de games).
- **fluidsynth** 2.5.6 — `tools/fluidsynth/fluidsynth-v2.5.6-win10-x64-cpp11/bin/fluidsynth.exe`
  (render SoundFont + MIDI → WAV, para a trilha).

## Pendências / em andamento (ver estado atual em [`decomp/progress.json`](decomp/progress.json))
- ✅ **SCD bytecode** — portas/gatilhos/itens/entidades posicionados ([formatos/scd_gameplay.md](formatos/scd_gameplay.md)).
  Pendem `sce_em_set` (inimigo) e destino de porta (precisam do handler no exe).
- ✅ **Modelos** `.PLD`/`.PLW` + animações → glTF (109/110). Inimigos (`R###.BIN`): malha empacotada pendente.
- ✅ **Trilha (BGM)** renderizada com SoundFont do VAB real (`re3.sf2` + fluidsynth). *ADSR/pitch aproximados.*
- ✅ **`stage_offset = 1`** PC↔PS1 (confirmado — ver acima).
- ✅ **Colisão** (RDT `offset_table[6]`) decodificada; máscaras (`mask_data_ptr`) parcial (oclusão por profundidade).
- 🟡 **Física / SM do player** no exe `SLUS_009.23` (root-motion, índice de anim ✅); **mira/IA** ⬜ não iniciado.
