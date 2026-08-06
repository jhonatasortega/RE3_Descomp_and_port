# Log de progresso

> **Papel: LOG HISTÓRICO** (Fase 0–2 do início do projeto). **Superseded** pela fonte de
> verdade [`decomp/progress.json`](decomp/progress.json) / [`decomp/PROGRESS.md`](decomp/PROGRESS.md).
> Mantido como registro; **alguns números aqui estão defasados** (corrigidos abaixo onde
> crítico). Índice em [`README.md`](README.md).

## Fase 0 — Setup e extração

- ✅ **Inventário do disco** (`tools/list_iso.py`) — ISO9660 de imagem raw PS1 (MODE2/2352).
- ✅ **Extração NTSC-U** (`tools/extract_iso.py`) → `extracted/ntsc-u/` — 1.334 arquivos.
  - 20 arquivos de streaming pulados (7 `.XAS` vozes + 13 `.STR` vídeos) → jPSXdec depois.
- ✅ **Executável confirmado:** `SLUS_009.23` (via `SYSTEM.CNF`). Alvo do Ghidra.

## Fatos confirmados

- **Base principal:** NTSC-U (`Resident Evil 3 - Nemesis.bin`), 60 Hz, exe `SLUS_009.23`.
- **`.DO1`–`.DO7` = PORTAS** (`DOOR00.DO1`…) — animações de transição entre salas, 1 por stage.
- **`PL00.PLD` = Jill**, `PL00W00..09.PLW` = armas dela.
- **`.TIM` = formato padrão PS1**, decodifica direto (4/8/16 bpp).

## Fase 1 — Assets (em andamento)

- ✅ **Decoder TIM→PNG** (`tools/tim2png.py`, Python puro via `zlib`).
  - **58 imagens** de `ETC/` decodificadas → `godot/assets/ETC/*.png` (0 erros).
  - **Descoberta:** alguns backgrounds de cena já estão como `.TIM` em `ETC/`.
- ✅ **Backgrounds `.BSS`** (`tools/bss2png.py`) → `godot/assets/STAGE{n}/*.png`.
  - **Formato:** contêiner de slots de 64 KiB; cada slot = 1 frame **MDEC / STR "BS v3"**
    (DCT estilo MPEG-1, não RLE/LZ). Header `+2 = 0x3800`, `+6 = versão 3`. Ver [BSS.md](formatos/BSS.md).
  - **169 arquivos → 2109 backgrounds** 320×240. Verificação visual OK (cenários nítidos do RE3).
- 🔄 **Áudio/vídeo** (jPSXdec) — agente em andamento.
- 🔄 **Texturas HD** (Seamless HD Project / GOG) — agente em andamento.
- ⬜ **Modelos `.PLD`/`.PLW`** → glTF (próximo).

## Fase 2 — Dados

- 🔄 **Salas `.ARD`** → JSON — agente em andamento.

## Fase 3 — Godot

- ✅ **Projeto montado** em `godot/`, estrutura espelhando o disco (`assets/ETC,STAGE1..7,
  PLD,SOUND,VOICE,ZMOVIE` + `data/STAGE1..7`).
- ✅ **Verificado:** importa limpo no **Godot 4.7** (editor em pt-BR). Cena `room_viewer.tscn`
  com background + câmera fixa (estilo RE clássico).

## Fase 2 — RE de dados de sala (em andamento)

- ✅ **Formato `.ARD` mapeado** (`tools/ard_parse.py`) → [`docs/formatos/ARD.md`](formatos/ARD.md).
  Validado nas **169 salas**. Contêiner alinhado a setor (0x800) com 10 sub-blocos.
  - ✅ **Cabeçalho + tabela de blocos** (tipos sempre `5,5,5,5,6,6,6,6,0,2`).
  - ✅ **RDT** (bloco 8): cabeçalho + tabela de 22 offsets.
  - ✅ **Câmeras (RID)** — **2105 câmeras** decodificadas (posição/alvo 3D em ponto-fixo).
  - ✅ **Script SCD** (offset[16]) → [`docs/formatos/SCD.md`](formatos/SCD.md).
    - ✅ Tabela de ponteiros de função + **tamanhos de opcode derivados dos bytes reais**.
    - ✅ **Gameplay extraído** (números atualizados): **481 portas** (todas com chegada),
      **738 gatilhos** (0x63/0x64), **433 entidades** (0x61/0x62) e **14 itens** (0x68) —
      todos com posição. Ver [formatos/scd_gameplay.md](formatos/scd_gameplay.md).
    - ⬜ IDs exatos de item/inimigo e destino das portas (precisa do handler no exe).
  - ⬜ Blocos de gráficos (tipos 5/6/2) = texturas/máscaras da VRAM → PNG (a decodificar).
- ✅ **Saída JSON:** `godot/data/STAGE{n}/<sala>.json` (169 arquivos).

## Ferramentas do projeto (Python puro, sem deps)

| Script | Função |
|---|---|
| `tools/list_iso.py` | Lista o sistema de arquivos da imagem PS1 |
| `tools/extract_iso.py` | Extrai os arquivos (Form 1) da imagem |
| `tools/tim2png.py` | Decodifica TIM → PNG |
| `tools/ard_parse.py` | Parseia salas `.ARD` → JSON (câmeras, blocos, script) |
