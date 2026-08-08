# Extração de áudio e vídeo (jPSXdec)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `video`, `sfx`, `bgm`, `vozes`)
> - **Formato:** XA (áudio streaming Mode 2 Form 2), STR (FMV), BGM (sequência Capcom + VAB), VAB (SFX)
> - **Extensão/origem:** `.XAS`, `.STR`, `.BGM`, `.VB`/`.VH` do disco NTSC-U (+ trilha GOG)
> - **Ferramenta:** jPSXdec v2.0, [`tools/re3_sound.py`](../../tools/re3_sound.py), [`re3_sfx.py`](../../tools/re3_sfx.py), [`bgm2midi.py`](../../tools/bgm2midi.py)
> - **Decompilado:** **100%** vídeo/vozes · **100%** RE do `.BGM` (SEQ+VAB) · **80%** SFX
> - **Feito:** 13 FMV → AVI; 104 vozes XA → WAV; RE do `.BGM` (SoundFont do VAB real); trilha completa via GOG (62 OGG).
> - **Falta:** de-para **sala → faixa de BGM** (ver [`../decomp/notes/exe_audio.md`](../decomp/notes/exe_audio.md) §7).
> - **FECHADO desde então:** a tabela de regiões `.VH` (corte/pitch) em [`../decomp/notes/sfx.md`](../decomp/notes/sfx.md),
>   e o **de-para `id de SE` → amostra** em [`../decomp/notes/exe_audio.md`](../decomp/notes/exe_audio.md) —
>   o mapa nome→amostra **não** é heurístico: sai da tabela gravada no início de cada `.VH`/`.SND`.
>   Uso no Godot: [`../godot_audio.md`](../godot_audio.md) (protótipo) e `port/core/sfx.gd` (port).

> Extração de **todo o áudio streaming (XA) e vídeo (STR/FMV)** do disco
> `rom/Resident Evil 3 - Nemesis.bin` (NTSC-U, raw MODE2/2352) usando **jPSXdec v2.0**.
> Estes streams usam setores **Mode 2 Form 2** e **não** são extraídos corretamente
> pelo `tools/extract_iso.py` — por isso o jPSXdec lê direto da imagem `.bin`.

## 1. Ferramenta e ambiente

| Item | Valor |
|---|---|
| Ferramenta | jPSXdec `v2.0` (PSX media decoder, non-commercial) |
| Runtime | Java 17 (Temurin 17.0.19) — comando `java` |
| Caminho do `.jar` | `C:/Users/Jhonatas Ortega/Downloads/7da9df97aa3615e70f3875e1db51c4b43f366dd61ef4dd61d9738aa33d6c4a8d6dba17d07214f98d/V8_Godot/tools/jpsxdec/jpsxdec_v2.0/jpsxdec.jar` |
| Imagem de origem | `rom/Resident Evil 3 - Nemesis.bin` (722.165.136 bytes, 307.043 setores) |
| Índice gerado | `tools/re3.idx` (444 KB, 3443 itens) |

> Sugestão: copiar `jpsxdec.jar` (+ `jpsxdec-lib.jar`) para `tools/jpsxdec/` no projeto
> para não depender do caminho em `Downloads/`.

## 2. Construção do índice

```bash
java -jar <caminho>/jpsxdec.jar -f "rom/Resident Evil 3 - Nemesis.bin" -x tools/re3.idx
```

Resultado: **3443 itens** identificados. O `.bin` foi reconhecido como
`BIN/CUE (2352 bytes/sector)`.

### Resumo do índice por tipo

| Tipo (`Type:`) | Qtde | Descrição | Coberto aqui? |
|---|---:|---|:---:|
| `Tim`   | 1959 | Texturas/imagens PS1 (TIM) | Não (ver pipeline de TIM) |
| `File`  | 1354 | Arquivos comuns do ISO | Não |
| `XA`    |  117 | Áudio ADPCM streaming (XA) | **Sim** |
| `Video` |   13 | Vídeos FMV (STR) | **Sim** |

Os **117** itens de áudio XA se dividem em:

- **104** = canais dos 7 contêineres `.XAS` (voz/ambiente streaming);
- **13** = faixas de áudio **embutidas** nos 13 vídeos `.STR` (áudio estéreo do FMV).
  Estas 13 **não** viram WAV avulso: são multiplexadas dentro do `.avi` de cada vídeo.

## 3. Áudio streaming (XA → WAV)

```bash
java -jar <caminho>/jpsxdec.jar -x tools/re3.idx -a audio -dir <saida>
```

- Formato padrão de saída: **WAV** (PCM). Extraiu **104 arquivos**.
- Propriedades dos canais `.XAS`: **mono, 37800 Hz, ADPCM 4-bit, sector stride 16**.
- Cada `.XAS` é um contêiner com múltiplos **canais** XA (clipes independentes
  multiplexados por canal de CD); o jPSXdec gera **1 WAV por canal**.

### Mapeamento origem → destino

| Origem no disco | Canais | Destino | Tamanho | Observação |
|---|---:|---|---:|---|
| `CD_DATA/VOICE/VOICES0.XAS`  | 8  | `godot/assets/VOICE/VOICES0/`  | 66 MB | Banco principal de fala (36 MB de origem) |
| `CD_DATA/VOICE/VOICEM0.XAS`  | 16 | `godot/assets/VOICE/VOICEM0/`  | 1,3 MB | Fala/ambiente do menu/global |
| `CD_DATA/STAGE1/VOICEM1.XAS` | 16 | `godot/assets/SOUND/STAGE1/`   | 13 MB | Streaming da fase 1 |
| `CD_DATA/STAGE2/VOICEM2.XAS` | 16 | `godot/assets/SOUND/STAGE2/`   | 31 MB | Streaming da fase 2 |
| `CD_DATA/STAGE3/VOICEM3.XAS` | 16 | `godot/assets/SOUND/STAGE3/`   | 16 MB | Streaming da fase 3 |
| `CD_DATA/STAGE4/VOICEM4.XAS` | 16 | `godot/assets/SOUND/STAGE4/`   | 7,1 MB | Streaming da fase 4 |
| `CD_DATA/STAGE5/VOICEM5.XAS` | 16 | `godot/assets/SOUND/STAGE5/`   | 28 MB | Streaming da fase 5 |

- **Renomeação:** `<NOME>.XAS[<n>].wav` → `<NOME>_ch<NN>.wav` (canal com 2 dígitos),
  para evitar colchetes em caminhos de recurso do Godot.
- **Critério de pastas:** espelha o disco. Os `.XAS` do diretório `VOICE/` do disco vão
  para `assets/VOICE/`; os `.XAS` streaming de cada `STAGE{n}/` vão para `assets/SOUND/STAGE{n}/`.

> **Nota de semântica (não confirmada byte-a-byte):** todos os streams acima têm nome
> `VOICE*` no disco. A separação `VOICE` vs `SOUND` aqui é **organizacional** (por diretório
> de origem no disco), não uma afirmação definitiva de "fala vs música". A validação do
> conteúdo exato de cada canal fica para a Fase 2.

## 4. Vídeos FMV (STR → AVI)

```bash
java -jar <caminho>/jpsxdec.jar -x tools/re3.idx -a video -dir <saida>
```

- Formato de saída: **AVI MJPG** (padrão `avi:mjpg`) com **áudio XA estéreo muxado**
  (37800 Hz, ADPCM 4-bit). Destino: `godot/assets/ZMOVIE/`.
- Todos os vídeos: **320×160**, **15 fps** (disc speed 2×).
- **Renomeação:** `<NOME>.STR[0].avi` → `<NOME>.avi`.

| Vídeo (`.STR`) | Frames | Duração aprox. | AVI | Provável conteúdo |
|---|---:|---:|---:|---|
| `OPN`    | 1350 | 90,0 s | 38 MB | Abertura |
| `ENDB`   |  840 | 56,0 s | 25 MB | Final B |
| `ENDA`   |  813 | 54,2 s | 24 MB | Final A |
| `INS06`  |  461 | 30,7 s | 11 MB | Cutscene |
| `INS04`  |  442 | 29,5 s | 12 MB | Cutscene |
| `INS01`  |  392 | 26,1 s | 11 MB | Cutscene |
| `INS07`  |  347 | 23,1 s | 11 MB | Cutscene |
| `INS03`  |  299 | 19,9 s | 8,4 MB | Cutscene |
| `INS08`  |  278 | 18,5 s | 7,0 MB | Cutscene |
| `INS09`  |  242 | 16,1 s | 7,2 MB | Cutscene |
| `ROOPNE` |  236 | 15,7 s | 5,9 MB | Abertura de sala |
| `INS02`  |  220 | 14,7 s | 6,0 MB | Cutscene |
| `INS05`  |  188 | 12,5 s | 5,1 MB | Cutscene |

Origem no disco: `CD_DATA/ZMOVIE/<NOME>.STR`.

## 5. Estrutura final da saída

```
godot/assets/
├── ZMOVIE/                 # 13 .avi (vídeo MJPG + áudio estéreo)  ~167 MB
│   ├── OPN.avi
│   ├── ENDA.avi
│   ├── ENDB.avi
│   ├── INS01.avi ... INS09.avi
│   └── ROOPNE.avi
├── VOICE/                  # 24 .wav                               ~67 MB
│   ├── VOICES0/  (8 wav)   # VOICES0_ch00..ch07.wav
│   └── VOICEM0/  (16 wav)  # VOICEM0_ch00..ch15.wav
└── SOUND/                  # 80 .wav                               ~94 MB
    ├── STAGE1/ (16 wav)    # VOICEM1_ch00..ch15.wav
    ├── STAGE2/ (16 wav)
    ├── STAGE3/ (16 wav)
    ├── STAGE4/ (16 wav)
    └── STAGE5/ (16 wav)
```

**Totais:** 13 vídeos (AVI) + 104 áudios (WAV) = **117 arquivos**, ~328 MB.

## 6. Importante: música sequenciada (BGM / VAB) NÃO sai do jPSXdec

A **trilha musical** do jogo **não** é áudio streaming — é **música sequenciada**:

- `CD_DATA/SOUND/*.BGM` — dados de sequência (SEQ-like);
- `CD_DATA/SOUND/*.VB` + `*.VH` — banco de samples VAB (corpo + cabeçalho);
- `CD_DATA/SOUND/*.VB`/`*.VH` `A_xx` e `C_xx` — bancos de SFX (VAB).

No índice esses arquivos aparecem como **`Type:File`** (não `XA`), logo o jPSXdec
**não os converte para WAV/OGG**. Eles já são extraíveis como arquivos comuns
(`tools/extract_iso.py`) e ficam em `CD_DATA/SOUND/` no disco.

> Nota (já refletida no [README](README.md)): `.BGM` **não** sai do jPSXdec nem do
> vgmstream — é sequência Capcom + banco VAB e precisa do pipeline próprio da seção 7.

## 7. Trilha sonora (BGM / SEQ + VAB) — engenharia reversa

A música do jogo usa um **formato sequenciado proprietário da Capcom** (NÃO é o
SEQ/VAB padrão do PSX). Confirmado por varredura: **nenhum** magic `pQES` (SEQ) ou
`pBAV` (VAB) em toda a pasta `SOUND/`.

### 7.1 Inventário (`extracted/ntsc-u/CD_DATA/SOUND/`)

| Arquivos | Qtde | Papel |
|---|---:|---|
| `MAIN33/38/39/3D.BGM`, `SUB_2A.BGM` | 5 | **Músicas** (sequência) |
| `<mesmo nome>.VB` (para cada BGM) | 5 | Corpo PS-ADPCM dos instrumentos (sem `.VH` — mapa de tons vai embutido no `.BGM`) |
| `A_00..A_14` `.VB`+`.VH` | 20 pares | Bancos de **SFX** (VAB) |
| `C_00..C_0D` `.VB`+`.VH` | 14 pares | Bancos de **SFX** (VAB) |
| `R000.SND` + `R_000.VB` | 1 | Efeitos de sala |

### 7.2 Ferramenta

- **vgmstream-cli / VGMToolbox**: não encontrados (PATH, `Downloads/`, bundle do
  jPSXdec, `tools/`). O download automático foi **bloqueado pelo sandbox de rede**.
  Para instalar manualmente:
  ```bash
  curl -sL -o tools/vgmstream/vgmstream-win64.zip \
    https://github.com/vgmstream/vgmstream/releases/latest/download/vgmstream-win64.zip
  ```
- **Observação-chave:** o vgmstream é um tocador de **streams**, não um sequenciador.
  Mesmo instalado, ele **não** renderiza a sequência `.BGM`; no máximo tocaria o `.VB`
  como PS-ADPCM cru (as amostras de instrumento soltas, não a música).
- Criado no projeto: **`tools/bgm2midi.py`** — extrator (experimental) `.BGM` → MIDI.

### 7.3 Formato do `.BGM` (layout)

```
.BGM = [bloco de sequência] × N   +   [bloco de banco de tons embutido]
```

Cabeçalho de cada **bloco de sequência** (12 bytes) + fluxo de eventos:

| Offset | Tipo | Campo |
|---|---|---|
| +0 | u32 LE | Tamanho do bloco (inclui o cabeçalho) |
| +4 | u32 LE | Tempo em µs/semínima (`500000` = 120 BPM) |
| +8 | u16 LE | PPQN / divisão (observado **48**) |
| +10 | u8 | Numerador do compasso (**4**) |
| +11 | u8 | Denominador como potência de 2 (**2** → 4/4) |
| +12 | … | Eventos estilo-MIDI |

**Eventos:** status MIDI `Cn` (program change), `Bn` (control — `07`=volume, `0a`=pan),
`9n` (note on; note-off = velocity 0), com **running status**, **delta-time VLQ APÓS
cada evento** (delta "trailing"), encerrando em `FF 2F 00` (end of track). O bloco de
banco (mapa programa→amostra do `.VB`) vem logo após o último bloco de sequência — para
os `MAIN*`, que têm 1 bloco, isso coincide com o 1º u32 do arquivo.

### 7.4 Relação com o VAB (`.VB` / `.VH`)

- `.VB` = corpo **PS-ADPCM** (blocos de 16 bytes: 1 shift/predictor + 1 flag + 14 de
  dados; 1º bloco silencioso zerado — padrão do SPU).
- `.VH` (SFX `A_/C_`) = tabela compacta de tons/regiões (sem cabeçalho `pBAV`).
- Música (`MAIN*/SUB_2A`): o mapa de tons está **embutido no fim do `.BGM`**; os
  instrumentos ficam no `.VB` de mesmo nome.

### 7.5 O que foi convertido

`tools/bgm2midi.py` extraiu **6 sequências MIDI** dos 5 `.BGM`. Todos os blocos fecham
com End-Of-Track exatamente no limite do tamanho declarado → **parse validado
estruturalmente**.

| BGM | seqs | eventos | notes-on | ~BPM | Saída (`godot/assets/SOUND/BGM/`) |
|---|---:|---:|---:|---:|---|
| MAIN33 | 1 | 204 | 84 | 102 | `MAIN33_seq00.mid` |
| MAIN38 | 1 | 189 | 87 | 95 | `MAIN38_seq00.mid` |
| MAIN39 | 1 | 510 | 240 | 120 | `MAIN39_seq00.mid` |
| MAIN3D | 1 | 325 | 146 | 96 | `MAIN3D_seq00.mid` |
| SUB_2A | 2 | 13 / 9 | 5 / 3 | 120 | `SUB_2A_seq00.mid`, `SUB_2A_seq01.mid` |

Comando: `python tools/bgm2midi.py extracted/ntsc-u/CD_DATA/SOUND/MAIN33.BGM godot/assets/SOUND/BGM`

> As MIDIs de 7.5 têm notas/tempo corretos, porém timbre genérico. A seção 7.6 substitui
> os instrumentos pelos **REAIS do jogo** (SoundFont montado a partir do VAB).

### 7.6 SoundFont do VAB real + render (CONCLUÍDO)

**Ferramentas (100% offline):** `tools/re3_sound.py` (decodifica o VAB e monta o `.sf2`) +
**fluidsynth 2.5.6** (`tools/fluidsynth/fluidsynth-v2.5.6-win10-x64-cpp11/bin/fluidsynth.exe`).
`tools/vgmstream/vgmstream-cli.exe` está disponível (não foi necessário no render).

**Passo 1 — Decodificar `.VB` (PS-ADPCM → PCM):** blocos de 16 B (byte0 = shift/predictor,
byte1 = flag, 14 B de dados → 28 amostras), filtros padrão do SPU. As **fronteiras** de cada
amostra vêm da **tabela VAG** no header do banco: `u32[2]` = offset da tabela; entradas `u16`
= offsets cumulativos em unidades de 8 B. Loop pelos flags (`0x06` início / `0x03` fim, ou
presença de `0x02` = sustain).

**Passo 2 — Banco de tons (embutido no `.BGM`):** cada tom = 32 B, com metade "meta"
(assinatura fixa `c0 00 c1 00 c2 00 c3 00` no offset +8; `prog` u16 @+4, `vag` u16 @+6) e
metade "attr" (`prior, mode, vol, pan, center, shift, min, max`). A ordem interna das metades
varia por música (o parser testa as duas e escolhe a de maior validade). Slots com `vag=0`
são padding. **`center` (nota-raiz) pode ficar fora de `[min,max]`** (ex.: kits de percussão) —
não se exige que contenha.

**Passo 3 — Montar `re3.sf2`:** um instrumento por programa; cada tom vira uma zona
(keyRange = `min..max`, rootKey = `center`, sampleModes = loop, fine ≈ `shift`, pan/atenuação
de `pan`/`vol`). Numeração **global de programa no bank 0** (dispensa bank-select no fluidsynth).
Saída: **`godot/assets/SOUND/BGM/re3.sf2`** — 3,6 MB, **46 samples, 32 presets/instrumentos**.
Manifesto: `re3_sf2_manifest.json`.

| BGM | amostras | programas | prog. global | observação |
|---|---:|---:|---|---|
| MAIN33 | 12 | 7 | 0–6 | |
| MAIN38 | 11 | 4 | 7–10 | prog 2/3 = kits (1 sample por tecla) |
| MAIN39 | 10 | 9 | 11–19 | |
| MAIN3D | 11 | 10 | 20–29 | usa **canal 9** → remapeado p/ 15 |
| SUB_2A | 2 | 2 | 30–31 | |

**Passo 4 — MIDIs de render:** `tools/re3_sound.py` regrava as MIDIs em
`godot/assets/SOUND/BGM/*.mid` com os programas na numeração global e **remapeia o canal 9**
(percussão do GM no fluidsynth) para um canal livre quando usado (MAIN3D).

**Passo 5 — Render (fluidsynth):**
```bash
FS=tools/fluidsynth/fluidsynth-v2.5.6-win10-x64-cpp11/bin/fluidsynth.exe
"$FS" -niq -g 0.35 -r 44100 -F <nome>.wav godot/assets/SOUND/BGM/re3.sf2 <nome>.mid
```
`-g 0.35` = maior ganho sem clipping na faixa mais alta (MAIN3D).

Reproduzir tudo: `python tools/re3_sound.py build` (gera `re3.sf2` + as 6 MIDIs) e depois
o `fluidsynth` acima para cada `*_seq*.mid`.

### 7.7 Resultado e validação (6 WAV, 44.1 kHz estéreo, `-g 0.35`)

| WAV | duração | MIDI (~) | RMS | pico | clip |
|---|---:|---:|---:|---:|---:|
| `MAIN33_seq00.wav` | 35,3 s | 33,0 s | −18,7 dBFS | 22306 | 0 |
| `MAIN38_seq00.wav` | 22,6 s | 20,3 s | −24,5 dBFS | 13255 | 0 |
| `MAIN39_seq00.wav` | 34,4 s | 32,0 s | −20,4 dBFS | 20223 | 0 |
| `MAIN3D_seq00.wav` | 22,3 s | 20,1 s | −16,4 dBFS | 30171 | 0 |
| `SUB_2A_seq00.wav` |  6,0 s |  4,0 s | −23,8 dBFS | 18597 | 0 |
| `SUB_2A_seq01.wav` |  6,0 s |  4,0 s | −26,7 dBFS | 18306 | 0 |

Todas **não-silenciosas** (RMS > 0), **sem clipping** (pico < 32768), e a duração ≈ MIDI + ~2 s
de cauda (release/nota final) — consistente. Tocam com os **instrumentos reais do RE3**
(PS-ADPCM do VAB), **não** General MIDI. Total ~22 MB de WAV.

> **Limitações (honestidade):** a afinação fina (`shift`) e os **envelopes ADSR** são
> aproximados (não decodifiquei o ADSR do SPU byte-a-byte — uso ataque rápido + release curto).
> Recomenda-se **validação audível** e comparação com gravação do emulador via
> `CD_DATA/BIN/MUSICBOX.BIN`. A semântica das 2 sub-músicas do `SUB_2A` fica a confirmar.

## 8. Como reproduzir

1. Índice: `java -jar jpsxdec.jar -f "rom/Resident Evil 3 - Nemesis.bin" -x tools/re3.idx`
2. Vídeo:  `java -jar jpsxdec.jar -x tools/re3.idx -a video -dir <stage>`
3. Áudio:  `java -jar jpsxdec.jar -x tools/re3.idx -a audio -dir <stage>`
4. Reorganizar de `<stage>/CD_DATA/...` para `godot/assets/{ZMOVIE,VOICE,SOUND}/`
   com a renomeação descrita (canais `_chNN`, remoção de `.STR[0]`/`.XAS[n]`).

Opções úteis do jPSXdec:
- `-a <video|audio|image|file>` — extrai todos os itens de um tipo.
- `-i <#|id>` — extrai um item específico (ex.: `-i 3435` = `OPN.STR`).
- `-dir <pasta>` — pasta-base de saída (recria a árvore `CD_DATA/...`).
- `-vidfmt avi:mjpg|avi:rgb|...` — formato de vídeo (`avi:rgb` = sem perdas, porém enorme).
- `-audfmt wav|aif|au` — formato de áudio (padrão `wav`).
- `-noaud` — não multiplexar áudio no vídeo.

## 9. BGM tocável no Godot — fonte GOG (trilha completa) + SFX do VAB

A extração PS1 (seção 7) rendeu apenas **5 `.BGM`** presentes no disco (o jogo faz
streaming da BGM por área, então o disco extraído só tinha o subconjunto carregado).
Para a trilha **completa e autêntica**, usei o port de PC (GOG), que já traz **cada
faixa decodificada com os instrumentos reais** em WAV.

> GOG é **somente leitura**. Nada foi escrito lá; só copiei/converti para fora.

### 9.1 BGM (música) — GOG → OGG

- **Fonte:** `C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/DATA_A/SOUND/MAIN*.WAV`
  (60 slots `MAIN00..MAIN3D`, alguns multipartes `_0/_1/...`). Estéreo, **22050 Hz**,
  loops de ~20–66 s. São os `MAIN##.BGM` (sequência PS1) já renderizados pelo port.
- **Conversão (ffmpeg do projeto):**
  ```bash
  FF=tools/ffmpeg/ffmpeg-master-latest-win64-gpl/bin/ffmpeg.exe
  "$FF" -i <src>/MAIN2C.wav -c:a libvorbis -q:a 5 -ar 22050 godot/assets/SOUND/BGM/gog/main2c.ogg
  ```
- **Saída:** `godot/assets/SOUND/BGM/gog/*.ogg` — **62 faixas, ~17 MB**. Nomes em minúsculo
  (`main00.ogg` … `main3d.ogg`, `main30_0.ogg`, …).
- **Por que OGG:** menor que WAV, importa nativamente no Godot e o `AudioManager`
  carrega via `AudioStreamOggVorbis.load_from_buffer()` (independe do passo de import).

> As 6 WAV renderizadas na seção 7.7 (SoundFont do VAB) continuam válidas como prova de
> engenharia reversa do `.BGM`, mas para o jogo usamos as do GOG (trilha inteira, sem
> aproximação de ADSR/pitch).

### 9.2 SFX interativos — VAB (`.VB`) → WAV

Os SFX do jogador (porta, tiro, passo, dano, menu) são tocados **ao vivo pelo SPU** a
partir dos bancos VAB `C_##`/`A_##`; **não** existem como WAV avulso no port. Extraí as
amostras individuais direto do `.VB`:

- **Ferramenta:** `tools/re3_sfx.py` — decodifica o `.VB` (PS-ADPCM, mesmos filtros de
  `re3_sound.py`) e **separa as amostras pelos flags de fim** do formato (byte1 do bloco
  de 16 B: `0x01` end, `0x03` end+loop, `0x07` end+mute). Descarta o bloco-zero silencioso.
  ```bash
  python tools/re3_sfx.py --all        # todos os A_/C_ presentes
  python tools/re3_sfx.py C_00 C_01    # bancos especificos
  ```
- **Saída:** `godot/assets/SOUND/SFX/<banco>/<banco>_NN.wav` (mono, 22050 Hz) —
  **298 amostras / 34 bancos, ~6,9 MB**. `C_00`/`C_01` = banco global (ações do jogador);
  `C_02..C_0D` e `A_01..A_14` = SFX/ambiente por área.
- **Limitação (honestidade):** a separação por flags é **grosseira** — o corte fino por
  amostra vive na tabela de regiões do `.VH` (formato compacto Capcom, 4 B/entrada, **sem**
  `pBAV` nem tabela clássica de tamanhos VAG, ainda não decodificada). A **afinação por
  região** do `.VH` também não é aplicada → pode haver leve desvio de pitch. A identificação
  "índice → porta/tiro/passo" **exige validação por ouvido** (ver `docs/godot_audio.md`).

> **Atualização — esta limitação foi resolvida em duas etapas:**
> 1. Corte exato + pitch por tom: [`../decomp/notes/sfx.md`](../decomp/notes/sfx.md) (tabela VAG do `.VH`);
>    a extração passou de 298 amostras com corte grosseiro para **267 com fronteira exata**.
> 2. **De-para `id de SE` → amostra:** [`../decomp/notes/exe_audio.md`](../decomp/notes/exe_audio.md).
>    A tabela que liga id → tom → `vag` está nos **primeiros bytes do próprio `.VH`/`.SND`**
>    (`N = hdr/4` entradas de u32, `0xffffffff` = id vazio; `hdr` achado pelo magic
>    `0x0001eeee` em `hdr+0x10`). Os **5 sons de menu** (mover/cancelar/confirmar/inválido/
>    abrir) ficaram com confiança **ALTA** e são exatamente os WAV `_00`..`_04` de `C_00` —
>    o mesmo "núcleo global" que o `sfx_map.json` já tinha achado por hash de PCM.
>    Gerar: `NOSTALGIA_OUT=port python tools/exe_audio.py`.
>    As ações de **jogo** (porta/passo/item/recarga) seguem **sem nome provado**.

### 9.3 Formato tocável confirmado no Godot

Verificado por harness headless (`godot/dev/tools_audio_test.gd`, seção do
`docs/godot_audio.md`): **`.ogg` (Vorbis) e `.wav` (PCM 16-bit)** carregam e entram em
estado `playing`. O `AudioManager` carrega em runtime (`load_from_buffer` p/ OGG; parser
RIFF próprio p/ WAV), então **dispensa `.import`** para funcionar — inclusive headless.
Evitar `.mp4`/contêineres de vídeo para áudio; usar OGG (BGM) e WAV (SFX one-shot).
