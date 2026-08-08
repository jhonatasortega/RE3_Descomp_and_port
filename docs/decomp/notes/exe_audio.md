# Motor de som do RE3 (PS1) — de-para PROVADO `id de SE` → amostra

> Engenharia reversa do **motor de efeitos sonoros** do `SLUS_009.23` (NTSC-U, base
> `0x80010000`) e do **arquivo de de-para** que liga o id de som usado pelo código à
> amostra tocada.
>
> Ferramenta: [`tools/exe_audio.py`](../../../tools/exe_audio.py) (`--verificar` roda as
> asserções; `--tabela <banco>` imprime uma tabela).
> Saída: `<out>/data/re3_se.json` + `<out>/data/sfx_map.json`.
> Consumo no port: [`port/core/sfx.gd`](../../../port/core/sfx.gd).
> Formato do banco VAB (corte/pitch/ADSR): [`sfx.md`](sfx.md).

---

## 0. Resumo — o que mudou nesta rodada

`sfx.md §8.3` declarava um **achado negativo**: *"um mapa `índice_SCD → WAV` byte-provado
NÃO é construível só do estático"*. Isso estava **errado na conclusão** (embora certo na
observação de que existe indireção de runtime).

O de-para **é um arquivo**, e o arquivo é o próprio **`.VH` / `.SND`** do banco: os
primeiros bytes de cada header de banco são uma **tabela indexada pelo id de SE**. O que é
resolvido em runtime é apenas *qual banco está carregado* em cada categoria.

Três correções de rumo estão na §6. A mais impactante: os opcodes SCD `0x57/0x58/0x59`,
que `sfx.md §8` documentava como filas de som, são **vibração do controle**.

**Rodada de 2026-08-08 (§11)** — o que mudou desde então:

| Assunto | Antes | Agora |
|---|---|---|
| Estouro da arma | `cat 0 / id 11`, DECLARADO | **`cat 1 / id 0`** do banco `A_{w}` da arma — MEDIDO, duas provas (§11.1) |
| `cat 1` | "ambiente de área" | **banco da ARMA equipada** (`w = player+0x46`) |
| Som de PASSO | "não identificado" | **NÃO PROVADO**, com o achado negativo medido (§11.2) |
| BGM sala → faixa | "NÃO MEDIDO" | **PROVADO byte-exato** nas 169 salas (§7) — a §7 antiga estava errada |
| Banco de sala (`cat 2`) | só `R000.SND` | os outros **168 estão embutidos nos `R###.ARD`** (§11.4) |

---

## 1. A cadeia do som no EXE

Todos os endereços são virtuais do `SLUS_009.23`. `SND_CTX` = `0x800e0610` (BSS: zerado no
arquivo, preenchido em runtime).

| Endereço | Papel | Como foi provado |
|---|---|---|
| `0x800746c0` | **`SE_pede(a0, a1, a2, a3)`** — enfileira um pedido de som | desmontagem (§2) |
| `0x800e0de4` | anel de pedidos: **24 slots de 32 B** (`SND_CTX+0x7d4`) | `0x8007450c`: `addiu s0, s3, 0x7d4` |
| `0x800e10e4` | ponteiro de escrita do anel (`SND_CTX+0xad4`) | `0x800746c8` (`lw`) / `0x80074764` (`sw`) |
| `0x800744e0` | **consumidor** (dentro do tick do motor) | §2.2 |
| `0x800a1130` | tabela de 2 handlers: `{0x80074770, 0x80074820}` | `0x80074534`: `lw v0,(v0)` + `jalr` |
| `0x80074770` | **resolve** o descritor (cat < 5) | §2.3 |
| `0x80074820` | resolve (cat ≥ 5) | mesma tabela, índice 1 |
| `0x800750e4` | **`busca_banco(a0)`**: 8 slots de 8 B em `0x800e0664`, chave `s16`; −1 se ausente | `0x800750f0..0x8007511c` |
| `0x800749a0` | aloca voz do SPU + volume/pan/pitch | `0x800749e0` lê o descritor; `0x80074bcc` chama o vol/pan |
| `0x80074cd0` | tom = `base_tons + índice*32` (`sizeof(VagAtr)` = 32) | `0x80074d30`: `sll v1, v1, 5` |
| `0x80075b90` | **volume/pan** (ver §2.4) | `0x80075b94..0x80075c28` |
| `0x8007f768` | libspu **`SpuSetVoiceAttr`** | `0x80075120` monta `{voice=a2, mask=3, volL=a0, volR=a1}` → `mask 3` = `VOLL\|VOLR` |
| `0x8007eda8` | libspu **`SpuSetKey(a0=on/off, a1=máscara de 24 vozes)`** | `a1 &= 0x00ffffff`; escreve KON em `+0x188/+0x18a` (`0x8007ee80`) e KOFF em `+0x18c/+0x18e` (`0x8007ef3c`) |
| `0x8007f518` | libspu **`SpuGetAllKeysStatus`** (`a1=0x17`, `a2=0x800e116c`) | `0x80074500`; `0x800749a0` usa esse array (`SND_CTX+0xb5c`) para achar voz livre |
| `0x800a1250` | ponteiro dos registradores do SPU (`0x1f801c00`) | `0x8007d1fc` + `lhu 0x1ae(v0)` = SPUSTAT `0x1f801dae` |

Chamadas de `SpuSetKey` de fora da libspu: `0x800745e8`, `0x80074628` (no tick, logo depois
de consumir o anel), `0x80075e50`, `0x80075eac`, `0x800760d4`, `0x8007753c`.

> **Nota honesta:** não há nenhum acesso direto a `0x1f801xxx`/`0xbf801xxx` no jogo — o SPU
> é tocado só pela libspu (`0x8007d178..0x80080254`, faixa achada pelos 109 usos de
> `*(0x800a1250)`). Foi isso que permitiu delimitar a biblioteca e separá-la do motor.

### 2.1 `SE_pede` — `0x800746c0`

```
a0 = (b2 << 16) | (cat << 8) | idx
a1 = ponteiro para 16 B de parâmetro (posição 3D quando != 0; os menus passam 0)
a2, a3 = parâmetros extras
```

Grava um registro de **32 bytes** no anel e avança o ponteiro em `0x20`:

| Offset no registro | Conteúdo | Instrução |
|---|---|---|
| `+0x08..+0x17` | 16 B copiados de `a1` (4 palavras) | `0x80074720..0x8007473c` |
| `+0x18` | `a3` (u16) | `0x80074754` |
| `+0x1a` | `a2` (u16) | `0x80074748` |
| `+0x1c` | **`idx`** = `a0 & 0xff` (u16) | `0x80074718` |
| `+0x1e` | `(a0 >> 16) & 0xff` (u8) | `0x80074700` |
| `+0x1f` | **`cat`** = `(a0 >> 8) & 0xff` (u8) | `0x8007470c` |

Porta de prioridade em `0x800746d4`: se `*(0x800cc858) & 0x10000000` **e** `cat >= 5`, o
pedido é **descartado**.

### 2.2 Consumidor — `0x800744e0`

```
for (rec = SND_CTX+0x7d4; rec != *(SND_CTX+0xad4); rec += 0x20)
    handler = *(0x800a1130 + (rec[0x1f] < 5 ? 0 : 4));   // 0x80074524..0x80074534
    handler(rec);                                        // jalr em 0x8007453c
*(SND_CTX+0xad4) = SND_CTX+0x7d4;                        // zera o anel (0x80074558)
```

Antes do laço, `0x80074500` chama `SpuGetAllKeysStatus` para `SND_CTX+0xb5c`.

### 2.3 Resolve — `0x80074770`

```
cat = u8  @ rec+0x1f            // 0x80074794
idx = u16 @ rec+0x1c            // 0x80074798
desc = *( *(SND_CTX + cat*4) + idx*4 )       // 0x8007479c..0x800747b0
if (desc == -1) return;                       // 0x800747b8  <<< id sem som
if (busca_banco(cat) == -1) return;           // 0x800747c0
banco = (desc.byte0 & 0x0e) >> 1;             // 0x800747d0..0x800747e0
slot  = busca_banco(banco);  if (slot == -1) return;
compoe_voz(rec, u16 @ (SND_CTX + 0x54 + slot*8));   // 0x800747fc -> 0x800749a0
```

**`SND_CTX + cat*4`** (8 palavras) é o array de ponteiros para as tabelas de SE de cada
categoria, preenchido no load do banco.

### 2.4 Volume/pan — `0x80075b90`

```
0x80075b90(a0 = voz, a1 = vol, a2 = pan):
    voz+0x08 = vol;  voz+0x0a = vol
    if (pan <  0x40)  voz+0x08 = vol * pan          / 63
    if (pan >  0x40)  voz+0x0a = vol * (0x7f - pan) / 63
```

A divisão por 63 é o idioma de *magic number*: `mult` por `0x82082083`, `mfhi`, `addu` do
dividendo, `sra 5` e correção de sinal → multiplicador efetivo `2181570691 / 2^37 ≈ 1/63`
(`2^37/63 = 2181570690,03`). Os offsets `+0x08`/`+0x0a` são exatamente
`SpuVoiceAttr.volume.left/right`, o que casa com o `mask = 3` de `0x80075120`.

---

## 3. `cat` **é o id do banco VAB**

`0x80074770` procura **`cat`** e **`banco` do descritor** com a **mesma** função
(`0x800750e4`) na **mesma** tabela de 8 slots (`0x800e0664`). E, medindo os arquivos: todo
descritor dentro de um arquivo cita **um único** banco, sempre o do próprio arquivo.

| `cat` = banco | Arquivos | Entradas na tabela de SE | Papel |
|---:|---|---:|---|
| 0 | `C_00`..`C_0D` | 16 | **personagem / UI / global** |
| 1 | `A_01`..`A_14` | 32 | **ARMA equipada** (não "área" — ver §11.1) |
| 2 | `R###.SND` **+ o banco embutido em cada `R###.ARD`** | 48 | efeitos de **sala** — ver §11.4 |
| **4** | `STAGE*/DOOR??.DO1` (banco **embutido**) | 4 | **porta** — ver §4.4 |

### 3.1 Quem escolhe o banco: `0x8007809c(cat, banco)` — e a tela de TÍTULO usa **`C_01`**

Achado de ago/2025, que faltava para fechar "qual banco está em cada `cat`" na tela de menu.

`0x8007809c(a0 = cat, a1 = banco, a2 = dest, a3 = ?)` carrega o par `.VH`/`.VB` de um banco.
Ele copia 16 B de **`0x800110b0`** (`04 01 03 01 da 00 d9 00 00…`) para a pilha e lê u16 com
**passo 4**, então `file_index = tab[cat] + banco*2` (`0x8007817c sll s1,1` + `0x80078184
addu`). Conferido contra a tabela de arquivos `0x800946a4`:

```
cat 0 -> tab = 0x104 = SOUND/C_00.VH   (o .VB sai do par, 0x103)
cat 1 -> tab = 0x0da                   (base; o banco de `w` é 0x0da + w*2)
```

> **Correção de 2026-08-08 — `0x0da` NÃO é o `A_01.VH`.** Conferindo os **tamanhos** da tabela
> `0x800946a4` contra os arquivos reais: `fid 0xdb` = **23600 B** = `A_01.VB` e `fid 0xdc` =
> **384 B** = `A_01.VH`. Logo `fileid = 0xda + w*2` dá `A_01` em **`w = 1`**, e o de-para é
> **`w` → `A_{w:02X}`**. `w = 0` não é banco de arma nenhum. Isso é o que fecha a §11.1.

* **`TITLE.BIN` `0x801944c0`: `0x8007809c(0, (0x800cc858 & 0x80) ? 0xb : 1)`** → no título
  normal o `cat 0` recebe **`0x104 + 2 = 0x106 = SOUND/C_01.VH`**, isto é **`C_01`**; no
  Mercenaries, `C_0B`.
* **`TITLE.BIN` `0x801954d0` (handler 4, a demo de atração)**: `0x8007809c(0, {2, 8, 9, 0xa})`
  conforme `*(u8*)0x800ccc0e` — é o banco de **área** do jogador (`C_02`/`C_08`/`C_09`/`C_0A`).

Ressalva honesta: os 5 WAV de UI de `C_01` são **byte-idênticos** aos de `C_00` (comparei os
arquivos extraídos), logo o som **audivel** é o mesmo — o que muda é a declaração de qual
banco o binário carrega.

`C_00`/`C_01` são os bancos de **menu** (tabela de SE idêntica entre os dois);
`C_02`..`C_0D` são os bancos de **área** do jogador — e são os únicos que definem os ids de
jogo (tiro etc.).

---

## 4. Formato do banco (`.VH` / `.SND`) — o arquivo de de-para

```
offset 0                       hdr                  hdr+0x30            hdr + u32@hdr+0x08
   |                            |                      |                       |
   [ tabela de SE: N x u32 ]    [ header VAB: 0x30 B ]  [ tons: 32 B cada ]     [ tabela VAG ]
```

* **Tabela de SE** no offset **0**. `0xffffffff` = id não usado (o mesmo `-1` que
  `0x800747b8` descarta). **`N = hdr / 4`**.
* O header VAB é localizado pelo **magic `0x0001eeee` gravado em `hdr+0x10`** — presente em
  **35/35** arquivos. É o que dá o `hdr` e, por consequência, o `N`.

| Campo | Tipo | Significado | Confere? |
|---|---|---|---|
| `hdr+0x00` | u32 | tamanho do `.VB` | **35/35** contra o arquivo real |
| `hdr+0x04` | u32 | tamanho total do bloco (header+tons+tabela VAG) | `hdr + isso == len(arquivo)` |
| `hdr+0x08` | u32 | offset da tabela VAG, relativo a `hdr` | **35/35**: `0x30 + 32*n_tons` |
| `hdr+0x14` | u16 | **nº de tons** | **35/35** contra `vab.parse_tones` |
| `hdr+0x16` | u16 | nº de VAGs | |
| `hdr+0x18` | u8 | volume mestre (`0x7f` em todos) | |
| `hdr+0x19` | u8 | pan mestre (`0x40` em todos) | |
| `hdr+0x30` | — | tons `VagAtr` de 32 B (layout em [`sfx.md §3.1`](sfx.md)) | |

### 4.1 Descritor de SE (u32 little-endian)

| Campo | Bits | Significado | Onde é lido |
|---|---|---|---|
| `byte0` bits 1–3 | `(b0 & 0x0e) >> 1` | **id do banco VAB** | `0x800747d8` |
| `byte1` bits 4–7 | `b1 >> 4` | **índice do TOM** no banco | `0x80074d30` (`<< 5` = ×32) |
| `byte2` bit 7 | `b2 & 0x80` | 1 = aloca voz dinamicamente · 0 = voz fixa | `0x800749e8` |
| `byte2` bits 0–4 | `b2 & 0x1f` | voz/grupo base | `0x800749f8` |
| `byte3` bit 0 | `b3 & 1` | flag | `0x80074a08` |
| `byte1` bits 0–3 | `{3, 5}` observados | **NÃO PROVADO** | — |
| `byte3` bits 1–7 | `{0x00,0x01,0x03,0x07,0x0f,0x1f}` observados | **NÃO PROVADO** (parece volume/máscara) | — |

Observado: os bancos `C_` usam `byte2 bit7 = 1` (voz dinâmica) e os `A_`/`R` usam `0` (voz
fixa) — coerente com "som de jogador é polifônico, drone de área fica na mesma voz".

### 4.2 Do descritor até o WAV

```
desc  ->  tom = tons[ b1 >> 4 ]  ->  amostra = tom.vag   (VagAtr+0x16, 1-based)
```

O **VAG#1** é o bloco mudo padrão do SPU e é descartado por `re3_sfx.py`, que numera os WAV
por posição entre as amostras reais. Logo:

```
vag k   =>   assets/SOUND/SFX/<banco>/<banco>_{k-2:02d}.wav
```

Tons cujo `vag == 1` são **placeholders mudos** (o motor toca, mas o waveform é silêncio).

### 4.4 Banco de PORTA — embutido em `DOOR??.DO1` (`cat 4`)

Achado desta rodada, seguindo a string de depuração **`"DOOR SOUND"`** em `0x800103ac`
(vizinha de `"DOOR TEXTURE"` em `0x80010398`), usada em `0x80016534` como `a3` do loader
`0x80012818` — que recebe `a0 = 0x801fc100` (destino em RAM) e uma entrada de LBA/tamanho
da tabela `0x800946a4`.

**Todo `STAGE*/DOOR??.DO1` embute um banco VAB completo**, com o mesmo magic
`0x0001eeee`. Provado em **76/76** arquivos:

```
[tabela de SE: 4 x u32]  [header VAB @0x10]  [tons @0x40]  [tabela VAG]  [corpo PS-ADPCM]  [modelo…]
```

- `hdr` = **`0x10`** → a tabela de SE tem **4 entradas** (ids 0..3);
- **o corpo PS-ADPCM começa em `hdr + u32@hdr+0x04`** (logo depois do bloco do header) e tem
  `u32@hdr+0x00` bytes. Prova: com essa base, **todo** VAG da tabela termina num bloco com
  flag de fim (bit0) — em 76/76 bancos. E os marcadores de mudo do SPU caem exatamente nos
  fins de VAG (em `DOOR00`: `0xf0`, `0x1600`, `0x2db0`, `0x41f0`, cujos deltas — 5392, 6064,
  5184 — reproduzem as durações da tabela VAG `[0, 6, 680, 1438, 2086]`);
- os descritores usam **banco 4** em 76/76 → **`cat 4` é o banco de porta**. Casa com o
  único call site de `cat 4` no EXE: **`0x800161c4`** (`a0 = 0x401` → cat 4, id 1), na região
  de setup/animação de porta.

**A tabela de SE das portas é um TEMPLATE.** Só existem **3 padrões distintos** nas 76, e os
ids 0 e 1 são **byte-idênticos em todas**:

| Padrão | Ocorrências |
|---|---:|
| `00601408`, `00612408`, `ffffffff`, `ffffffff` | 72 |
| `00601408`, `00612408`, `0fe23408`, `07e34408` | 3 |
| `00601408`, `00612408`, `0fe23308`, `ffffffff` | 1 |

Consequência medida: **12 dos 159** descritores apontam um tom **fora** do próprio banco —
são as 12 portas que só têm 2 tons e mantiveram o id 1 (que aponta o tom 2) herdado do
template. É **inconsistência do dado original**, não do formato (nos 278 descritores dos
bancos do disco isso acontece **0 vezes**). A ferramenta marca `invalido` e segue, em vez de
inventar outro layout de campo para forçar o encaixe.

O **id 0 é o único válido nas 76 portas** — por isso é tratado como o som principal.
`porta_abrir = 0` / `porta_fechar = 1` / `porta_trancada = 2` é **ordem DECLARADA**: qual id
é abrir e qual é fechar **não foi medido**.

Extrair: `NOSTALGIA_OUT=port python tools/exe_audio.py --portas` → **147 WAV** em
`assets/SOUND/SFX/S<stage>_DOOR<xx>/`. É o que dá porta de madeira ≠ portão de metal.

### 4.3 Validação (`python tools/exe_audio.py --verificar`)

**1345 asserções, 0 falhas.** As que sustentam o de-para:

- `hdr+0x00 == len(.VB)` em 35/35 bancos do disco;
- `hdr+0x14 == nº de tons achados pelo marcador `c0 00 c1 00 c2 00 c3 00`` em 35/35;
- **ler os tons e a tabela VAG por OFFSET dá o mesmo resultado que achá-los por
  assinatura/varredura**, em 35/35 — é isso que autoriza usar o offset nos `DOOR*.DO1`,
  onde o marcador `reserved[4]` não serve (parte dos tons não o tem, e o resto do arquivo
  — modelo/textura — produz falsos positivos);
- tons terminam exatamente onde `hdr+0x08` aponta a tabela VAG, e a tabela vai de `0` a
  `len(.VB)/8`, em 35/35;
- **`b1 >> 4 < n_tons` em 278/278** descritores usados dos bancos do disco — o campo tem 4
  bits e o banco mais rico tem exatamente **16** tons, ou seja o campo está *justo*, sem
  folga;
- todo `tom.vag` cai dentro da tabela VAG;
- cada arquivo cita **um único** banco nos seus descritores;
- portas: 76 bancos, todos com 4 ids e banco 4; **todo VAG termina em flag de fim** com a
  base `hdr+total`; 3 padrões de tabela; 159 descritores com exatamente 12 inválidos; id 0
  válido em 76/76.

---

## 5. De-para das ações

### 5.1 Sons de menu — confiança **ALTA**

Banco `C_00` (idêntico em `C_01`):

| id | ação | tom | vag | WAV |
|---:|---|---:|---:|---|
| **4** | mover cursor | 5 | 4 | `C_00/C_00_02.wav` |
| **5** | cancelar / voltar | 6 | 5 | `C_00/C_00_03.wav` |
| **6** | confirmar | 7 | 6 | `C_00/C_00_04.wav` |
| **7** | inválido | 8 | 2 | `C_00/C_00_00.wav` |
| **9** | abrir menu | 12 | 3 | `C_00/C_00_01.wav` |

Por que é ALTA — quatro evidências independentes que convergem:

1. **Comportamento** observado no jogo pelo dono do repo (id → ação).
2. **Call sites**: os 155 `jal 0x800746c0` do EXE, com `a0` constante em 125 deles. Os ids
   4/5/6/7/9 são chamados **sempre com `a1 = 0`** (sem posição 3D — é UI) e **todos** os
   call sites caem em código de menu. A frequência bate com a semântica: id 5
   (cancelar/voltar, existe em toda tela) tem **20** call sites, id 6 (confirmar) **13**,
   id 4 (mover cursor) **11**, ids 7 e 9 **5** cada.
3. **Compartilhamento**: os descritores dos ids 4/5/6/7 são **byte-idênticos em 13 dos 14**
   bancos `C_` (`0x3fe05300`, `0x3fe06300`, `0x3fe07300`, `0x3fe08300`) — som de UI é
   global. `C_0C` é a **única** exceção: não define o id 4 e usa outros tons nos 5/6/7.
4. **Cruzamento com `sfx.md §9.1`**, que por um caminho totalmente diferente (hash MD5 do
   PCM) achou **5 amostras byte-idênticas nos 13 bancos `C_`** e as chamou de
   *"núcleo global do jogador"*: são exatamente os WAV **`_00`.. `_04`** de `C_00` — os
   **mesmos 5** deste de-para.

Exemplo de call sites (a0 constante recuperado por back-walk do imediato):

| id | call sites |
|---:|---|
| 4 | `0x8003054c` `0x800308f8` `0x800638f4` `0x80064684` `0x8006688c` `0x80066a78` `0x800670f4` `0x800672b0` … (11) |
| 5 | `0x800304e0` `0x8003088c` `0x80063c20` `0x80063e74` `0x80064538` `0x80064740` `0x800650f4` `0x8006675c` … (20) |
| 6 | `0x80023d10` `0x80064500` `0x80064aa4` `0x8006669c` `0x80066f00` `0x80069454` `0x8006a2b4` `0x8006a340` … (13) |
| 7 | `0x800666bc` `0x80067e90` `0x80067ebc` `0x800687b0` `0x8006fdd0` |
| 9 | `0x80023db8` `0x800666f0` `0x80066728` `0x8006dd40` `0x8006fdb4` |

> Erro corrigido no caminho: a pista original dizia que `0x800746c0` "mapeia AÇÃO → id de
> som". Ela mapeia, mas os **valores** `4/5/6/7/9` não vêm de nenhuma tabela em
> `0x800746c0` — são **imediatos no fluxo de instruções** de cada tela (`addiu a0, zero, 5`
> etc.). A tabela que traduz id → amostra é a do `.VH` (§4).

### 5.2 Ids de jogo — call site provado, **semântica DECLARADA**

Cada linha tem o call site medido; o **nome** é escolha do port até alguém ouvir.

| cat | id | call sites | nome no port | observação |
|---:|---:|---|---|---|
| 0 | 11 | `0x8003ad6c` (`lui a0,1; ori a0,a0,0xb`), `0x8003cf10` | `tiro` | `a1 = player+0x34` (posição). **`C_00`/`C_01` não definem o id 11** — só os `C_02..C_0D` de área. Coerente com "não há tiro no menu" |
| 0 | 0 | `0x8003d208` (`lui a0,1`) | `impacto_ataque` | grava `player+0xc8 = 0x30004`, `player+6 = 1`; vizinho de `0x8003d14c` = "acerto conectado" (`exe_combat.md`) |
| 0 | 1 / 2 / 3 | `0x8003d560` / `0x8003d82c` / `0x8003dac8` | `acao_1/2/3` | 3 ids consecutivos, 1 call site cada, na mesma região de ação do jogador |
| 0 | 8 | `0x80063984` `0x80063a2c` | `acao_8` | `a1 = 0` → UI |
| 0 | 13 | `0x80045b10` `0x80045e68` `0x800465fc` | `acao_13` | |
| 0 | 14 | `0x80077f40` | `acao_14` | `a1 = 0` → UI |
| 0 | 15 | `0x800485e4` | `acao_15` | `a1 = 0` → UI; nenhum banco `C_` define o id 15 nos arquivos do disco extraído |

Distribuição completa dos 125 call sites com `a0` constante, por `(cat, idx)`, está no
`_meta` do `re3_se.json` e sai de `tools/exe_audio.py`.

### 5.3 Opcodes SCD que pedem SE

Varredura dos **144 handlers** da jump-table `0x8009e0f8`, procurando `jal 0x800746c0`:

| Opcode | Handler | Call site |
|---:|---|---|
| `0x77` | `0x80055038` | `0x80055164` |
| `0x78` | `0x8005518c` | `0x800553d0` |

Os opcodes `0x24` e `0x70..0x73` chamam `0x8001b484` — que **não** é som: é o spawn de
efeito/modelo, indexando `MODEL_TBL` `0x800ba728` (o mesmo rótulo que `scd_decode.py` já
usa no `0x60`).

**Nenhum** dos 144 handlers toca BGM — não existe opcode de "set bgm" no SCD do RE3. Isso
mantem o de-para **sala → faixa** em aberto (§7).

---

## 6. Correções (o que estava errado nos docs anteriores)

### 6.1 `sfx.md §8` — os opcodes `0x57/0x58/0x59` **não são som, são VIBRAÇÃO**

`sfx.md §8.1` dizia que `0x80038678`/`0x80038704`/`0x8003879c` empurravam um "id de SE" em
"filas de SE". São as **duas filas de motor do DualShock**:

| Fila | Endereço | Motor |
|---|---|---|
| pequeno (on/off) | `0x800de648` | `0x80038678(dur = u16@+2, atraso = u16@+4)` |
| grande (nível fixo) | `0x800de798` | `0x80038704(dur = u16@+2, nível = u8@+1, atraso = u16@+4)` |
| grande (rampa linear) | `0x800de798` | `0x8003879c(dur = u16@+4, ini = u8@+2, fim = u8@+3, atraso = u16@+6)` |

Slot de **10 bytes**: `+0` ativo · `+1` nível atual · `+2` atraso · `+4` duração ·
`+6` passo · `+8` acumulador em ponto fixo `<<7`.

Tick em **`0x800389a0`**: enquanto `atraso` > 0 decrementa e sai; senão decrementa
`duração` (zerando `+0` no fim), faz `acumulador += passo` e `nível = acumulador >> 7`;
devolve o **máximo** de `nível` entre os 32 slots.

O resultado vai para os **2 bytes** em `0x800c79c8` e é entregue ao controle por
**`PadSetAct`** — o stub `0x80091710`, chamado em `0x80038074` com `a0 = 0`,
`a1 = 0x800c79c8`, `a2 = 2`. `0x80029e3c` também consome e zera esses 2 bytes.

O que denuncia: `0x8003879c` faz `passo = ((fim - ini) << 7) / dur` — **dividir pelo
"id"** não faz sentido; interpolar um nível ao longo de `dur` ticks, sim.

Já corrigido em `tools/scd_decode.py` (e portanto no `data/scd_opcodes.json` regerado).

### 6.2 `menus.md §8.2` — `0x800746c0` **não** é enqueue de sprite

`menus.md` documentava `0x800746c0` / `0x80074770` / `0x800749a0` como
`draw_sprite` / `resolve_sprite` / `compose_geom` da GPU, com `0x800e0610` sendo o "estado
do compositor". A cadeia termina em **`SpuSetVoiceAttr` / `SpuSetKey`** (§1), e
`0x800749a0` chama o cálculo de **volume/pan com pan de centro `0x40` e divisão por 63**
(§2.4) — não há geometria nenhuma nesse caminho.

`menu_comandos.md:66` e `menu_mapa.md:657/916`, que diziam "`0x800746c0` = SFX", estavam
**certos**.

`0x800e0610` é um **contexto de sistema compartilhado**: os campos `+0x7d4`/`+0xad4`
(anel de SE), `+0x14`/`+0x18`/`+0x54` (bancos) e `+0xb5c` (status de voz do SPU) são de
som; outros campos do mesmo bloco (ex.: `+0xb1c/+0xb20/+0xb24`, citados em
`menu_pc_sys.md:446`) são de outro subsistema. Foi essa mistura que enganou a leitura
anterior.

### 6.3 `sfx.md §8.3` — o link estático **existe**

O achado negativo ("não é construível só do estático") vale só para o *bytecode do SCD*:
lá o id é lógico. Mas o de-para `id → tom → vag` está gravado no **`.VH`/`.SND`**, que é
dado estático do disco. O que sobra de runtime é **qual banco** está em cada `cat`.

### 6.4 `exe_combat.md` — `0x800776b0` e os bits `0x200/0x400`

O doc afirma que `0x800776b0` *"seleciona entre seco/tiro/vazio pelos bits `0x200`/`0x400`
de `(player+0xe4)`"*. **NÃO PROVADO**: em `0x800776b0..0x80077b84` não existe **nenhum**
`andi` com `0x200`/`0x400` nem qualquer leitura de `+0xe4`.

O que a rotina realmente faz:

- chama `0x8001b484` (spawn de efeito/modelo) **10 vezes**;
- chama `0x8003879c` (**rampa de vibração**, §6.1) **8 vezes**;
- pede **um** SE, em `0x80077b50`, com `a0 = s5 | 0x10200` → **`cat = 2` (banco de SALA)**,
  `idx = s5`, e `a1 = &sp+0x18` preenchido com `s4+0x54/0x58/0x5c` (posição).
  `s5 = base + a0_entrada`, com `base ∈ {0x17, 0x1a, retorno_de_0x80077b84 & 0x7f}` ou
  `0x2d`, e `a0_entrada ∈ {0, 1}`.

`cat = 2` = banco da sala, e os ids `0x17..0x2d` caem na faixa dos 48 ids de `R###.SND`.
Isso é compatível com **impacto/ricochete de bala na sala**, não com o estouro da arma. O
estouro é o `cat 0 / id 11` da §5.2.

---

## 7. Trilha (BGM) — **o de-para sala → faixa ESTÁ MEDIDO** (correção de 2026-08-08)

- A trilha tocável do port vem do **PC/GOG**: `DATA_A/SOUND/*.WAV` → 125 Ogg em
  `assets/SOUND/BGM/gog/` (`tools/audio_gog.py`). São as `MAIN##.BGM` do PS1 já
  renderizadas com os instrumentos reais — **é a melhor fonte disponível** e é HD no
  sentido que importa (22 kHz PCM em vez de sequência aproximada). Ver
  [`audio_video.md §9.1`](../../formatos/audio_video.md).

> **O texto anterior desta seção estava ERRADO.** Ele dizia que o de-para sala → faixa
> continuava "NÃO MEDIDO" e que `room_override` estava vazio. Não está: o
> `tools/audio_gog.py --mapa` **já fechou o vínculo por outro caminho** e o `bgm_map.json`
> publica os dois blocos (`salas` com as 169 e `room_override` com 133). O erro veio de
> procurar o vínculo só no EXE/SCD.

**O que é PROVADO** (`bgm_map.json._meta.PROVA`): cada `R###.ARD` embute **4 pares
(SEQ+VH, VB)** nos sub-blocos de tipo `0x05` (MAIN) e `0x06` (SUB), e o **sha1** de cada
bloco casa com um `DATA/SOUND/<nome>.BGM` **nomeado** do `Rofs7.dat` do PC em **676/676**
blocos (169 salas × 4), **0 falhas**, 98 nomes distintos. Ou seja: **sala → nome da BGM do
PS1 é byte-exato**, e o vínculo nunca esteve no bytecode — está no **próprio arquivo da
sala**, que é dado estático (o mesmo padrão da §6.3).

**O que continua aberto é o RENDER**, não o vínculo: a faixa tocável é o WAV do PC de
**mesmo nome**, aceito quando a duração da sequência do PS1 casa.

| `conf` | Salas | Critério |
|---|---:|---|
| ALTA | 78 | erro de duração ≤ 1,5 % |
| MEDIA | 55 | ≤ 20 % |
| NAO_CASADO | 32 | o nome do PS1 está provado, mas o WAV homônimo do PC é outra peça (ou não existe) |
| SEM_MAIN | 4 | a sala não tem bloco MAIN (`R11B`, `R409`, `R40A`, `R414`) |

Casamentos de sanidade (todos `ALTA`): **`R100` → `main07`** (0,02 % de erro),
**`R10F` → `main32`** (0,01 %) — e `main32` é exatamente a chave `context.SAVE` do mapa,
isto é a sala de save toca o tema de save —, **`R200` → `main01`** (0,4 %),
**`R112` → `main0a`** (0,4 %).

**Consequência no port** (`port/core/audio.gd`): `faixa_para_sala` passou a ler o bloco
`salas` (169) em vez de só o `room_override` (133), com precedência
`room_override > salas.faixa > salas.ps1 (nome provado) > área do STAGE`. Resultado medido
em `test_audio.gd`: **169/169 salas com faixa e o `.ogg` dela existindo no disco**, sendo
**151 pela cadeia medida** e só **18** ainda no fallback por STAGE (14 porque o
`DATA_A/SOUND` do PC não tem WAV daquele nome + as 4 `SEM_MAIN`).

**Um bug que isso corrigiu:** `area_default.PARK = "main2a"` e **não existe
`main2a.ogg`** — o PC guarda a faixa partida em `main2a_0`/`main2a_1`. Como 36 salas caíam
no fallback por STAGE, o **PARK inteiro ficava mudo**. `audio.gd` agora resolve o sufixo
`_0` das faixas multipartes (qual parte é intro e qual é loop é **DECLARADO**, não medido).

- Nota que continua válida: **nenhum dos 144 handlers de opcode do SCD toca BGM** (§5.3) —
  o vínculo é pelo conteúdo do ARD, não por instrução.

---

## 8. Voz / narração PT-BR (medido na instalação de PC)

Método: sem poder ouvir, o idioma foi decidido por **correlação de envelope RMS** contra o
inglês retail extraído dos `Rofs*.dat` (`tools/rofs_extract.py`). Calibração: arquivo
idêntico = `1,0000`; mesma tomada recodificada = `0,96–0,99`; tomada **diferente** = `< 0,90`.

| Conjunto | Nº | Idioma | Como se sabe |
|---|---:|---|---|
| `DATA_A/VOICE` (lote 2025) | **370** | **PT-BR** (inferido forte) | áudio **é outra gravação** (corr < 0,80 contra o EN do `Rofs14.dat`) — **PROVADO**. Que a outra gravação seja PT-BR é **inferência** (o pacote instalado é o `mod_BH3_Portuguese`); **não há metadado de idioma** em nenhum dos 441 WAV |
| `DATA_A/VOICE` (lote 2021) | **71** | **inglês** — PROVADO | corr ≥ 0,95 com o `Rofs14.dat`, mesma tomada reamostrada a 37800 Hz |
| `DATA_A/SOUND/MAIN07.wav` | 1 | **narração do EPÍLOGO, dublada** | corr `0,4797` contra o EN → áudio trocado |
| `DATA_A/SOUND/MAIN06.wav` | 1 | narração do PRÓLOGO, **NÃO dublada** | mtime de 2022 (lote Seamless HD), não 2025 |
| `zmovie/*.mp4` | 14 | **10 com áudio trocado**, 4 iguais ao EN | `ins03` (0,9817), `ins05` (0,9908), `ins09` (0,9735) e `roop` (0,9597) **não** foram dublados |

**De-para faixa → evento provado:**

- **Voz:** o nome é `m<id-de-sala><letra-de-cena><NNN>.wav`. **35 dos 37** prefixos batem
  1:1 com uma sala real (`m101→R101`, `m11a→R11A`, `m50a→R50A`, …), conferido contra os 129
  `mod_BH3_Portuguese/xml/rdt/R###.xml`. Os 2 restantes (`s000`, `s001`) não são sala.
- **`MAIN07` = epílogo, casado por duração:** os marcadores de `epilogue.xml` somam
  **1431 quadros = 47,700 s a 30 fps**; `MAIN07` mede **47,696 s** (Rofs) / **47,729 s**
  (solto) → erro **0,06 %**. Em 1132 WAV medidos, só `MAIN06`/`MAIN07` chegam a menos de
  1,5 s desse alvo. `prologue.xml` soma **1414 quadros = 47,133 s** vs `MAIN06` 46,860 s
  (0,58 %).

> **Onde a narração do PRÓLOGO toca (ago/2025):** no **`OPENING.BIN`** (ovl 5), que **não**
> é tocador de FMV — é o slideshow de imagens paradas do prólogo (`ETC/OPENING0.DAT` +
> `OPENING1.DAT`) e chama `0x8002fd30(0x00b90022, 0x3000)` = início de stream de áudio.
> `MAIN06`/`MAIN07` **não existem no disco do PS1** (lá só há `MAIN33/38/39/3D`): a narração
> vem por XA e a versão de PC a guarda como WAV. Isso **reforça** o casamento por duração
> acima e **contradiz** `boot_ptbr_hd.md` §4.2, que atribuía `prologue.xml` ao `opn.mp4`
> (0,58 % de erro contra `MAIN06` vs 43 s de vídeo sem legenda). Ver
> [`boot_ptbr_hd.md`](boot_ptbr_hd.md) §8.6.

**Marcação de tempo dos XML PT-BR:** `{clear NN}` / `{timed NN}`, **`NN` em QUADROS a
30 fps** (provado numericamente acima); `{scroll N}` **não** é tempo. `prologue.xml`: 4
blocos `<Text>`, 13 `{clear}` + 4 `{timed}`. `epilogue.xml`: 1 bloco, 13 `{clear}` +
1 `{timed}`. Os arquivos são UTF-8 **com BOM** e usam `ä`/`ö` no lugar de `ã`/`õ`
(remapeamento da fonte do jogo): `destruiçäo`, `perdäo`, `operaçäo`.

> **Aberto (só o ouvido fecha):** confirmar que os 370 do lote 2025 e o `MAIN07` estão de
> fato em português. Comando: `ffplay -autoexit "<GOG>/DATA_A/SOUND/MAIN07.wav"`.

---

## 9. Resíduo honesto

| Aspecto | Status | Confiança |
|---|---|---|
| Cadeia `SE_pede` → `SpuSetKey` | fechada (§1, §2) | **ALTA** (disassembly) |
| Tabela de SE no `.VH`/`.SND` (offset 0, `N = hdr/4`, −1 = vazio) | fechada (§4) | **ALTA** (35/35 + 278/278) |
| Descritor: banco (`b0` bits1-3) e tom (`b1` bits4-7) | fechado (§4.1) | **ALTA** |
| Descritor: `b1` bits0-3 e `b3` bits1-7 | **NÃO PROVADO** | — |
| `cat` == id de banco VAB | fechado (§3) | **ALTA** |
| De-para dos 5 sons de menu | fechado (§5.1) | **ALTA** (4 evidências independentes) |
| **Porta**: banco `cat 4` embutido nos 76 `DOOR??.DO1` | fechado (§4.4) | **ALTA** no formato / **MÉDIA** no nome (qual id é abrir vs fechar não foi medido) |
| **Estouro da arma** = `cat 1 / id 0` do banco `A_{w}` | fechado (§11.1) | **ALTA** (tabela por arma `0x8009ced8` + `A_01` sem id 0) |
| De-para **item do inventário → `w`** (qual `A_xx` em cada arma) | **NÃO MEDIDO** — o port usa faca=1 / resto=2, DECLARADO | BAIXA |
| Nome das outras ações de jogo (item, recarga) | **DECLARADO** — call site provado, semântica não | BAIXA |
| Quem preenche `SND_CTX + cat*4` | fechado: `0x8007809c`, chamado por `0x800495d0` (cat 0 = personagem) e `0x80043eb4` (cat 1 = arma) | **ALTA** |
| **Som de PASSO** | **NÃO PROVADO** — 0 pedidos de SE nas 4 rotinas de locomoção do player, e não há segundo enfileirador (§11.2) | — |
| Pegar item / recarga | **não identificados** | — |
| `cat 3`, `cat 5`, `cat 6`, `cat 7` | call sites achados (`0x80078004`/`0x80078048`/`0x8007807c` para 5/6/7), banco de origem **não localizado** | — |
| De-para **sala → faixa de BGM** | fechado (§7): sha1 dos 676 blocos de SEQ dos 169 `.ARD` × os nomes do `Rofs7.dat` do PC | **ALTA** no nome / **MÉDIA** no render (32 salas `NAO_CASADO`) |
| Banco de sala (`cat 2`) das 168 salas embutido no `.ARD` | localizado e validado (§11.4), **não extraído** | **ALTA** no layout |
| Idioma real das 370 vozes e do `MAIN07` | **inferido** (§8) | MÉDIA — falta ouvir |

---

## 10. Como reproduzir

```bash
# tabela de SE de um banco
python tools/exe_audio.py --tabela C_00
python tools/exe_audio.py --tabela A_02      # banco de ARMA: o id 0 é o estouro (§11.1)

# 1898 asserções que sustentam o de-para
python tools/exe_audio.py --verificar

# os 155 `jal 0x800746c0` com (cat, idx) + o achado negativo do PASSO (§11.1 / §11.2)
python tools/exe_audio.py --callsites

# extrai os WAV dos 76 bancos de porta (147 amostras)
NOSTALGIA_OUT=port python tools/exe_audio.py --portas

# gera data/re3_se.json (111 bancos) + data/sfx_map.json no destino do port
NOSTALGIA_OUT=port python tools/exe_audio.py

# mapa sala -> faixa de BGM (169 salas, prova por sha1 dos blocos do ARD) — §7
python tools/audio_gog.py --mapa

# teste do port (97 asserções) — SEMPRE com filtro, a suíte inteira leva ~7 min
GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --path port --headless --audio-driver Dummy --script res://dev/run_tests.gd -- audio

# diagnóstico "por que o som X não sai" no jogo de verdade (§11.1)
"$GODOT" --path port --headless --script res://dev/diag_som.gd
```


---

## 11. Rodada de 2026-08-08 — tiro, passo e porta

Ferramenta nova: **`python tools/exe_audio.py --callsites`**, que imprime os **155
`jal 0x800746c0`** com `(cat, idx)` recuperado por back-walk do imediato. É a evidência
reproduzível de tudo nesta seção. Diagnóstico do lado do port:
**`port/dev/diag_som.gd`**.

### 11.1 O ESTOURO da arma é `cat 1 / id 0` — e `cat 1` é banco de ARMA

O port pedia `cat 0 / id 11` (§5.2). Esse pedido **existe**, mas não é o estouro.

**Duas provas independentes:**

1. **Tabela de 20 funções POR ARMA** em `0x8009ced8..0x8009cf24` — vizinha imediata da
   tabela de **timing** `0x8009cf28` que o port já usa. Ela é indexada por **`w − 1`**, com
   `w = player+0x46`:

   ```
   0x8003ea1c:  lbu v1, 0x46(s3)       ; w
                addiu v0, -0x3128      ; 0x8009ced8
                addiu v1, v1, -1       ; w - 1
                sll v1, v1, 2 ; addu ; lw v0,(v1) ; jalr v0
   ```

   Em **cada** entrada aparece o mesmo trecho:

   ```
   0x80044804(hitscan, a2 = lbu player+0x46)  ->  0x80047860  ->  0x8006d030(1)
   ->  SE_pede(a0 = 0x10100, a1 = *(player+0x108) + 0x344)     ; cat 1, idx 0
   ```

   São **17 dos 155** call sites, todos com o **mesmo** id (`0x80041018`, `0x80041184`,
   `0x8004161c`, `0x80041904`, `0x80041ab8`, `0x80041c6c`, `0x80041e20`, `0x80041fd8`,
   `0x800422a0`, `0x800424bc`, `0x800426e8`, `0x80042a7c`, `0x80042b9c`, `0x80042edc`,
   `0x800433b0`, `0x80043584`, `0x80043a40`).

2. **`A_01` é o ÚNICO dos 20 bancos `A_` que não define o id 0.** Ele define `6,7,8,9,10`;
   os outros 19 definem o id 0. E `A_01` é o banco de `w = 1` — a **FACA**, que não estoura.
   A entrada 0 da tabela por arma (`0x80040f34`, `w = 1`) é também a única que **não** pede
   SE de tiro.

   > Isso resolve de quebra a base do índice: `Player.quadro_do_corte()` já usava
   > "faca = linha 0, resto = linha 1" na tabela de timing (stride 3, índice `w − 1`, lida em
   > `0x8003e454`). Ou seja **`w = 1` é a faca e `w = 2` é a pistola**, coerente nas duas
   > tabelas e no dado dos bancos.

Quem carrega o banco: `0x80043eb4` → `0x8007809c(a0 = 1, a1 = lbu player+0x46)`, com
`fileid = 0xda + w*2`. Ver a correção de base na §3.1.

**O que sobra em aberto:** o de-para **item do inventário → `w`** continua NÃO MEDIDO
(`tools/exe_aim_shoot.py`); o `world.gd` amarra `faca → w 1` e "qualquer outra arma → `w 2`",
DECLARADO, a mesma aproximação que o `quadro_do_corte()` já fazia.

**E por que o dono não ouvia o tiro?** Não era arquivo faltando: `C_02/C_02_11.wav` está no
disco (6372 B, 14343 Hz, pico 32369) e o caminho inteiro funcionava — medido de ponta a ponta
com o driver **WASAPI** em `diag_som.gd` (`Game.sfx` → `World` → `Player._resolver_tiro` →
pool → `playing = true`). O que soava era a amostra **errada** (o `id 11` do banco de
personagem, no lugar do estouro da arma). Mesmo assim o `Sfx` passou a **reclamar com o
caminho absoluto** quando a amostra falta ou não carrega, em vez de devolver `false` calado.

### 11.2 Som de PASSO — **NÃO PROVADO**

O relatório anterior dizia "não identificado"; agora há o **achado negativo medido**.

As 16 macro-ações do player vivem na tabela `0x8009cda0` (indexada por `player+5`); as
quatro primeiras são a locomoção. Cruzando os intervalos com os 155 call sites
(`--callsites` imprime isso):

| rotina | intervalo | pedidos de SE |
|---:|---|---:|
| 0 (idle) | `0x80039294..0x800397dc` | **0** |
| 1 (frente) | `0x800397dc..0x80039b84` | **0** |
| 2 (ré) | `0x80039b84..0x80039f08` | **0** |
| 3 (correr) | `0x80039f08..0x8003a574` | **0** |

Também descartado:

- **Não existe segundo enfileirador.** O anel `0x800e0de4` só é escrito por `0x800746c0`
  (§2.1) e só é lido/zerado por `0x800744e0` — então todo som do jogo passa pelos 155 call
  sites. Se o passo não está lá, não é um SE pedido por código de locomoção.
- **Nenhuma string** de depuração de passo/piso: varrendo o `.text` inteiro por
  `foot|step|walk|floor|sound|snd|vab|bgm`, só existem `"DOOR SOUND"` (`0x800103ac`),
  `"Vab Header"` (`0x800110c0`) e `"Vab Body"` (`0x800110cc`).
- **`cat 5/6/7` não servem**: `0x80078004`/`0x80078048`/`0x8007807c` pedem sempre `idx 0`,
  com `a1 = 0` (sem posição 3D) e sob os bits 1/2/4 de um byte de estado — não é som
  posicional de ator.
- **Os pedidos de `cat 2` que ficam na região do player não são passo**: `0x8003b224`
  (`cat 2 / id 0`) está em `0x8003b1c4`, que antes do SE grava `+0xc8 = 6`, `+0xc9 = 0`,
  `+0xca = 7` e depois chama a vibração `0x8003893c` — é uma **ação única** (subir/pular),
  não um evento cíclico de passada.

**Pista mais forte para a próxima rodada** (não fechada aqui): o interpretador de bytecode
`0x8002fee0`, cujos opcodes `0xEA..0xFE` (jump-table `0x80010508`, 21 entradas) leem um
**byte de stream** e o transformam em `SE_pede(cat 2, idx = byte)` (`0x80030010`). E, no
lado dos objetos, `0x8001c38c` toca um SE cujo `(cat, idx)` vem **empacotado em um byte**
(`u8 @ obj+0x19`: bits 6-7 = `cat`, bits 0-5 = `idx`), disparado por flags de
`u16 @ obj+0x26`. Um id de SE guardado em **1 byte dentro de dados** é exatamente a forma
de um evento por quadro de animação — mas ligar isso ao EDD do player **não foi medido**.

### 11.3 Porta e área — ligados no `world.gd`

- **carga**: `World._init` chama `Sfx.definir_banco_area()` (= `C_02`, MEDIDO em
  `0x800495d0`). Sem isso o port resolvia os ids de jogo no `C_00`, que é o banco de MENU.
- **troca de sala**: `World.atravessar` chama `_som_da_porta(sala_de_origem, aot)`, que
  seleciona o banco `cat 4` pelo `Dtex_Type` daquele par sala/AOT
  (`data/porta_banco.json`, 453 portas em 167 salas) e toca `porta_abrir()` (id **1**,
  MEDIDO em `0x800161c4`). Sem `Dtex_Type` cai no banco padrão, não no silêncio.
- **arma**: `World.tick` chama `Sfx.definir_banco_arma(w)`. O `w` é DECLARADO (§11.1).

Continua **não medido**: qual id do banco de porta é *abrir* e qual é *fechar* — o motor só
toca **um** (o id 1), então a pergunta pode não ter resposta no dado.

### 11.4 Achado colateral: **cada `R###.ARD` embute o banco `cat 2` da sala**

Explica por que só existe `R000.SND` no disco: os outros 168 bancos de sala moram **dentro
do arquivo da sala**. Medido nos 169 `.ARD` (mesmo método da §4.4, offsets do RDT da
[`ARD.md §3.2`](../../formatos/ARD.md), onde `off[0..2]` já estavam rotulados "áudio VAB"):

- **`off[0]` = tabela de SE de 48 ids** (`u32`, `0xffffffff` = vazio) — o mesmo `N = 48` do
  `R000.SND`. Confirmado por `off[1] − off[0] == 0xC0` em **169/169**.
- **`off[1]` = fim da tabela**; o header VAB vem logo depois, com 8 a 28 bytes de
  alinhamento. Achado pelo magic `0xeeee` em `hdr+0x10`, com `hdr+0x18 = 0x7f` (volume) e
  `hdr+0x19 = 0x40` (pan): **168/169** (só `R11B` falha — é uma das 4 salas `SEM_MAIN`).
- **O `u16` alto do magic é a VERSÃO do VAB**, e ela muda o tamanho do header:
  `0x0001eeee` → header **0x30** (94 salas, e os 35 bancos do disco) · `0x0002eeee` →
  header **0x40** (74 salas). Prova: `u32@hdr+0x08 == tam_header + 32*n_tons` em 168/168
  com essa regra (com 0x30 fixo, as 74 falhavam por exatamente 0x10).
- Os descritores dessas tabelas citam **mais de um banco** (`606` de banco 2, mas também
  0, 1, 3, 4, 5, 6, 7) — diferente dos bancos do disco, onde cada arquivo cita um só (§4.3).

Consequência prática: **extrair os 168 bancos de sala é possível** e é o caminho natural
para fechar `porta_trancada`/`porta_destrancar`/`porta_emperrada` (§5, hoje sem amostra) e
para procurar o passo no dado em vez de no código. **Não foi extraído nesta rodada.**
