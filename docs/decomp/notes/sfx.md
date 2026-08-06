# SFX do RE3 — layout do banco VAB (`.VH` + `.VB`) e extração precisa

> Engenharia reversa do header **`.VH`** dos bancos de SFX do RE3 (PS1), para cortar
> cada efeito nas **fronteiras exatas** e com o **pitch correto** — substituindo a
> separação grosseira por flags de fim que havia antes.
>
> Ferramentas: [`tools/vab.py`](../../../tools/vab.py) (parser) +
> [`tools/re3_sfx.py`](../../../tools/re3_sfx.py) (extrator).
> Saída: `godot/assets/SOUND/SFX/<banco>/<banco>_NN.wav` + `sfx_manifest.json`.

## 1. Fontes do formato

O RE3 usa uma **variante compacta do VAB da SONY** (PsyQ/libsnd). O banco é o par
clássico **VH (header) + VB (corpo)**, mas a Capcom **removeu o cabeçalho `pBAV`/`VABp`**
e o array de programas padrão — mantendo, porém, as duas estruturas que importam:
os **tons `VagAtr` de 32 bytes** e a **tabela de endereços VAG** (offsets das amostras).

Referências públicas do VAB usadas para confirmar o layout dos campos:
- Estrutura `VagAtr`/`ProgAtr`/`VabHdr` da libsnd (SONY PsyQ SDK): campos
  `prior, mode, vol, pan, center, shift, min, max, …, adsr1, adsr2, prog, vag`.
  Documentada na comunidade PSX (ex.: **psx-spx / “PlayStation Specifications”**,
  seção *SPU / VAG / VAB*; e a página *VAB* do **Sound Formats** da wiki do PSXDEV).
- PS-ADPCM (VAG): blocos de 16 B (`shift|predictor`, `flag`, 14 B de dados = 28
  amostras), filtros do SPU — o mesmo já usado em [`re3_sound.py`](../../../tools/re3_sound.py).

> Confirmação local: nenhum magic `pBAV`/`VABp` nos `.VH`; o layout abaixo foi provado
> **byte-a-byte** contra os `.VH`/`.VB` reais do disco NTSC-U
> (`extracted/ntsc-u/CD_DATA/SOUND`).

## 2. Inventário

| Grupo | Arquivos | Papel |
|---|---|---|
| `C_00`, `C_01` | par `.VH`+`.VB` | Banco **global** (ações do jogador: porta, tiro, passo, dano, menu) |
| `C_02`..`C_0D` | par `.VH`+`.VB` | SFX/ambiente por área |
| `A_01`..`A_14` | par `.VH`+`.VB` | SFX/ambiente por área |
| `R000.SND` + `R_000.VB` | par | “efeitos de sala” — **mesmo formato VAB** (header em `.SND`) |

`.VH` de 384–656 B; `.VB` de 23 KB a 255 KB.

## 3. Layout do `.VH`

O `.VH` é: `[header/atributos]` → `[tons VagAtr]` → `[tabela VAG]` (no fim).
As duas estruturas exploradas (tons e tabela VAG) são localizadas por assinatura e por
ancoragem no tamanho do `.VB` — **não** dependem de decodificar o header proprietário.

### 3.1 Tom = `VagAtr` (32 bytes) — idêntico ao SONY

| Offset | Tipo | Campo | Observação |
|---:|---|---|---|
| +0 | u8 | `prior` | prioridade |
| +1 | u8 | `mode` | |
| +2 | u8 | `vol` | volume |
| +3 | u8 | `pan` | |
| +4 | u8 | **`center`** | **nota-raiz (rootKey)** |
| +5 | u8 | **`shift`** | ajuste fino da raiz (`center += shift/128` semitom) |
| +6 | u8 | **`min`** | tecla mínima do range |
| +7 | u8 | **`max`** | tecla máxima do range — **nos SFX do RE3: `min == max`** |
| +8..+15 | 8×u8 | `vibW,vibT,porW,porT,pbmin,pbmax,resv1,resv2` | vibrato/portamento/pitch-bend |
| +16 | u16 | `adsr1` | envelope ADSR |
| +18 | u16 | `adsr2` | envelope ADSR |
| +20 | u16 | `prog` | programa do tom |
| +22 | u16 | **`vag`** | **índice 1-based na tabela VAG** (qual amostra tocar) |
| +24 | 4×u16 | `reserved[4]` | a Capcom grava o marcador fixo `c0 00 c1 00 c2 00 c3 00` |

O marcador em `reserved[4]` é o que permite **localizar os tons** com segurança
(`vh.find(b"\xc0\x00\xc1\x00\xc2\x00\xc3\x00")` → o `VagAtr` começa 24 B antes).

**Prova (C_00.VH, 1º tom @ byte 112):**
```
attr  00 00 64 00 42 39 3c 3c   -> prior0 mode0 vol100 pan0 center66 shift57 min60 max60
resv  00 00 00 00 00 00 b1 b2
meta  ff 80 c0 1f 00 00 07 00   -> adsr1=0x80ff adsr2=0x1fc0 prog=0 vag=7
sig   c0 00 c1 00 c2 00 c3 00   <- marcador reserved[4]
```

### 3.2 Tabela VAG (fronteiras das amostras)

Array de `u16` no **fim** do `.VH`. Cada valor é um **offset cumulativo no `.VB` em
unidades de 8 bytes**. Começa em `0` (VAG#0) e termina exatamente em `len(.VB)/8`.
A amostra `vag k` (1-based) ocupa **`[tab[k-1]*8, tab[k]*8)`** no `.VB`.

- **VAG#1 = bloco *dummy*/mudo padrão do SPU** — sempre `[0, 48)` (3 blocos), com
  `flag 0x07` e dados `0x77` (mute). **É descartado** na extração. Os SFX reais são
  `vag 2..N`. Tons que apontam para `vag=1` são placeholders mudos (55 no total).

**Localização robusta (sem parsear o header):** achar o último `u16 == len(.VB)/8` e
caminhar para trás enquanto os valores forem estritamente decrescentes e `> 0`,
incluindo o `0` inicial.

**Prova (C_00):** `.VB` = 206480 B → `/8 = 25810`.
```
tabela = [0, 6, 90, 540, 688, 1084, 1504, 11716, 21928, 25810]
         VAG#1=[0,48) dummy | VAG#2=[48,720) | ... | VAG#9=[175424,206480)
```

## 4. Pitch por tom

No SPU, tocar a nota **`center`** reproduz a amostra a **44100 Hz** (pitch 1.0). Cada
semitom abaixo reduz a taxa por `2^(-1/12)` (temperamento igual — aproximação padrão
de `SsUtKeyToPitch`). Como **todos** os tons de SFX têm `min == max`, a tecla tocada é
fixa e o pitch fica **totalmente determinado pelo `.VH`**:

```
rate = 44100 * 2 ^ ( (key - center - shift/128) / 12 )     , key = min (== max)
```

A taxa vira o **sample-rate do WAV** (sem reamostrar o PCM). Distribuição das 267
amostras: 117 a 22050 Hz, 54 a ~15,2 kHz, 17 a 11025 Hz, 5 a 44100 Hz (tons com
`key == center`), etc. Amostras “órfãs” (sem tom; 4 no total) recebem 22050 Hz e são
marcadas `orphan` no manifesto.

## 5. Prova de que as fronteiras estão corretas

1. **Todas** as 298 regiões (264 reais + 34 dummies) **terminam num bloco com flag de
   fim ADPCM** (`0x01`/`0x03`/`0x07`) e são **alinhadas a 16 B**. (298/298 OK.)
2. **Cada amostra real contém exatamente UM flag de fim interno** além do final
   (264 regiões, 264 flags internos). Esse flag interno (tipicamente `0x03` = fim de
   loop) era exatamente onde a **separação antiga por flags fragmentava** a amostra em
   duas peças → fronteiras e afinação imprecisas. A tabela VAG corta no lugar certo.

## 6. Resultado

- **267 SFX** extraídos (**264** dos 34 bancos `A_/C_` + **3** de `R000`), com
  **fronteiras exatas** (tabela VAG) e **pitch por tom** (`center`/`shift`/`key`).
  Antes: **298** amostras com corte grosseiro e pitch fixo em 22050 Hz.
- Todos os WAVs não-silenciosos; 1 `.VB` dummy descartado por banco.
- Saída: `godot/assets/SOUND/SFX/<banco>/<banco>_NN.wav` + `sfx_manifest.json`
  (`vag`, `vb_start/vb_end`, `blocks`, `rate`, `center`, `key`, `shift`, `prog`,
  `orphan`).

Reproduzir: `python tools/re3_sfx.py --all`

## 7. Loop e ADSR — decodificados (fecha o "opcional")

`tools/vab.py` agora decodifica **byte-a-byte** os dois campos que faltavam; `re3_sfx.py`
os emite por SFX no manifesto (`loop`, `adsr`) e no mapa (§9).

### 7.1 Loop (marcadores PS-ADPCM) — `vab.analyze_loop`

O byte de flag (byte1 de cada bloco de 16 B) do SPU tem 3 bits:

| Bit | Máscara | Significado |
|---|---|---|
| 0 | `0x01` | **End** — fim; o SPU salta para o loop-address |
| 1 | `0x02` | **Repeat** — ao chegar no End, faz LOOP (sem este bit: release/para) |
| 2 | `0x04` | **Loop-Start** — marca o endereço de retorno do loop |

Emitimos `loop_start_block/pcm` (1º bloco com bit2), `terminal_block/flag` (último com
bit0) e `repeat` (bit1 no terminal).

> **Achado (honestidade):** nos **267/267** SFX estes marcadores são **UNIFORMES** —
> `loop_start = bloco 1` e `terminal_flag = 0x07` (End+Repeat+LoopStart) em todos. Ou seja,
> são **convenção de autoria da Capcom**, **não** um sinal per-SFX de "loopa vs one-shot".
> Quem decide se o som sustenta é a **fila de SE do runtime** (opcode SCD `0x57` = fila de
> loop; `0x58/0x59` = one-shot — ver §8), não o waveform. Por isso os WAVs continuam
> gravados como one-shot; os campos de loop são emitidos como **verdade do binário**.

### 7.2 ADSR (`VagAtr.adsr1/adsr2`) — `vab.decode_adsr`

Layout do SPU (psx-spx / `SsUtSetVoiceAttr`), provado no exemplo de C_00 (§3.1):

| Campo | Bits | Fonte |
|---|---|---|
| `attack_mode` | adsr1 bit15 | 0=linear, 1=exp |
| `attack_shift` | adsr1 bit10-14 | 0..31 (rápido..lento) |
| `attack_step` | adsr1 bit8-9 | 0..3 → +7,+6,+5,+4 |
| `decay_shift` | adsr1 bit4-7 | 0..15 |
| `sustain_level` | adsr1 bit0-3 | nível = `(Sl+1)*0x800` |
| `sustain_mode/dir/shift/step` | adsr2 bit15/14/8-12/6-7 | |
| `release_mode/shift` | adsr2 bit5 / bit0-4 | |

Emitimos os campos crus + um descritor qualitativo (`attack_speed`, `release_speed`:
shift≤2 = instantâneo). **Não** convertemos para ms (o tempo exato exige simular o
contador de 32 bits do SPU + tabela de rates; seria estimativa, não prova).

> **Achado (honestidade):** ADSR é **quase constante** no dataset — `adsr1 = 0x80ff` em
> **263/267** (ataque instantâneo, sustain cheio) e `adsr2 = 0x1fc0` em **246/267** (13 com
> `0x5fc0` = sustain *decrease*/fade). Logo o ADSR **também carrega pouco sinal semântico
> per-SFX**: caracteriza o conjunto como **one-shot de ataque instantâneo**, coerente com
> a §7.1. Decodificado e emitido; o `re3_sound.py` (SF2 da BGM) pode passar a usar estes
> campos no lugar do ataque/release fixos.

### 7.3 Limitações remanescentes

- **Pitch absoluto:** assume SPU a 44100 Hz na nota-raiz e tecla = `min` (`min==max`).
- **Nome semântico exato** (porta vs tiro vs passo de um SFX ambíguo): **só decidível
  ouvindo** — ver §8 (por quê, estaticamente) e §9 (o que dá para afirmar sem áudio).

## 8. Opcodes de som do SCD — layout + estatísticas + achado NEGATIVO honesto

> Fonte: disassembly (capstone via `tools/exe_parse.py`) dos handlers da jump-table
> `0x8009e0f8` + varredura das **169 salas** (`tools/scd_decode.py`). Handlers de som:
> `0x55`→`0x80054bc0`, `0x56`→`0x80054c28`, `0x57`→`0x80054c58`, `0x58`→`0x80054ca4`,
> `0x59`→`0x80054cf4` (os endereços `0x8003xxxx` do `OPCODE_SEM` são os *call-targets*).

### 8.1 Operandos (lidos do PC = `obj+0x1c`; provado no handler)

| Op | Tam | Operandos | Chama | Fila de SE |
|---|---|---|---|---|
| `0x55` | 8B | `s16@+2/+4/+6` = **x,y,z** (posição 3D) → `obj+0x154`+0x34.. | `0x80034124` | atualiza posição do som ativo (NÃO seleciona id) |
| `0x56` | 2B... | `s16@+2/+4/+6` → `obj+0x154`+0x6c | — | idem (parâmetro 3D) |
| `0x57` | 6B | `a0=u16@+2` (**id SE**), `a1=u16@+4` | `0x80038678` | fila **LOOP** `0x800de648` (32×10B) |
| `0x58` | 6B | `a0=u16@+2` (**id SE**), `a1=u8@+1`, `a2=u16@+4` | `0x80038704` | fila **one-shot** `0x800de798` |
| `0x59` | 8B | `a0=u16@+4` (**id SE**), `a1=u8@+2`, `a2=u8@+3`, `a3=u16@+6` (o handler faz `div (a2-a1)*128 / id` → pan/pitch) | `0x8003879c` | fila one-shot |

Cada fila tem 32 slots de 10 B: `+0` ativo, `+1` flag/pan, `+2` param, `+4` **id**, `+6/+8`
pitch/pan (`0x59`).

### 8.2 Estatística de ids nas 169 salas (prova de USO)

`0x57` (loop) usa **14** ids distintos, concentrados em **1..8** (id1=196×, id2=137×,
id3=139×, id4=85×…). `0x58` usa **45** ids, `0x59` usa **53** ids, ambos com cauda longa
(até 250). Total de **1528** disparos de SE (`0x57/58/59`) + **1060** de `0x55` (posição) +
**490** de `0x56`. Os ids são **inteiros pequenos e densos** (1,2,3,…) → **índices lógicos**,
não offsets.

### 8.3 Achado NEGATIVO (honesto): NÃO há link estático `id → vag`

O id do SCD é um **id LÓGICO de SE**, empurrado numa **fila de SE de runtime** e resolvido
**em tempo de execução** contra o **banco VAB carregado na sala** (C_global + A_/C_ da área).
Não é um índice `vag` de um banco específico gravado no bytecode. Consequências:

- O **mesmo id** (ex.: id1) toca amostras **diferentes** conforme a sala/banco carregado —
  exatamente como o destino de porta (`0x7f`) que também é resolvido em runtime (ver
  `scd_opcodes.md`). É a **mesma classe** de resultado negativo honesto.
- Logo **um mapa `índice_SCD → WAV` byte-provado NÃO é construível** só do estático. O que
  liga id→(banco,vag) é a tabela de SE montada no load do VAB (indireção de runtime).

Por isso o **nome exato** de ação de um SFX (porta vs tiro vs passo) fica em **MÉDIA/BAIXA**
— é o resíduo que só o **áudio** (ou um trace de emulador) fecha. O que segue (§9) é o que
dá para afirmar **sem ouvir**, com prova.

## 9. Mapa semântico índice→ação (ESTÁTICO) — `sfx_map.json`

`python tools/re3_sfx.py --map` → `godot/assets/SOUND/SFX/sfx_map.json`. Cada SFX recebe
**papel** (ALTA), **classe de envelope** (ALTA, medida), **pitch/ADSR/loop** e uma
**ação provável** (inferência, MÉDIA/BAIXA).

### 9.1 Papel por compartilhamento entre bancos (ALTA — prova byte-a-byte)

Hash MD5 do **PCM cru** de cada amostra → agrupa as byte-idênticas. Resultado (267 reais →
**100** únicas por bytes):

- **`nucleo_global_jogador`** (ALTA): as amostras **idx 00-04** são **byte-idênticas nos 13
  bancos `C_00..C_0C`** → sempre carregadas = **sons de ação do jogador/UI** (5 sons).
- **`comum_multi_area`** (3..12 bancos) e **`comum_par_area`** (2): sons comuns a grupos de
  áreas irmãs (ex.: `A_02/A_03/A_05/…` compartilham 7-8 amostras de ambiente).
- **`unico_area`** (60 amostras): PCM único → específico da área/situação.

Histograma de compartilhamento: `{1:60, 2:12, 3:3, 4:5, 5:6, 6:5, 7:3, 8:1, 13:5}`.

### 9.2 Classe de envelope (ALTA — medida do PCM)

`dur_s`, `peak_pos`, `tail_ratio` → `curtissimo` (<0,13s), `transiente` (curto, pico cedo,
cauda baixa), `medio_com_cauda`, `longo_sustentado` (≥1,5s). Distribuição de duração:
mediana 0,387s; 32 <0,13s; 25 ≥1,5s.

### 9.3 Ação provável (INFERÊNCIA — MÉDIA/BAIXA, nunca "provada")

Combinando papel + envelope + banco (regras em `re3_sfx.build_map`):

- núcleo global + curtíssimo/transiente → *"ação pontual do jogador (passo/manuseio/impacto)"*
  — **MÉDIA**.
- núcleo global + médio com cauda → *"ação do jogador com cauda (porta/mecanismo/arma)"* —
  **MÉDIA**.
- banco de área + longo sustentado → *"ambiente/drone de área"* — **MÉDIA**.
- demais → **BAIXA** ("indeterminado sem áudio").

**Cobertura:** papel em confiança **ALTA = 267/267 (100%)**; ação provável **MÉDIA = 90**,
**BAIXA = 177**. O `role`/envelope/pitch/ADSR/loop são todos byte-provados; a ação exata é o
resíduo BAIXA que exige áudio.

## 10. Resíduo honesto (classificado)

| Aspecto | Status | Confiança |
|---|---|---|
| Corte/fronteiras (tabela VAG) | fechado (§5) | ALTA (byte) |
| Pitch por tom (center/shift/key) | fechado (§4) | ALTA (byte) |
| **Loop** (marcadores ADPCM) | **decodificado + emitido** (§7.1) | ALTA (byte); sinal per-SFX ~nulo (uniforme) |
| **ADSR** (adsr1/adsr2) | **decodificado + emitido** (§7.2) | ALTA (byte); sinal per-SFX ~nulo (uniforme) |
| **Papel** (global/área/único) | **`sfx_map.json`** (§9.1) | **ALTA (byte, 267/267)** |
| **Envelope/duração** | **`sfx_map.json`** (§9.2) | ALTA (medida) |
| Opcodes de som do SCD (layout + uso) | mapeado (§8) | ALTA (disassembly + 169 salas) |
| **Nome exato de ação** (porta/tiro/passo) | **INFERIDO** (§9.3) | MÉDIA (90) / **BAIXA (177)** — só o **áudio** fecha |
| Link estático `id_SCD → vag` | **inexistente** (§8.3) | resolvido em runtime (achado negativo, como destino de porta) |
