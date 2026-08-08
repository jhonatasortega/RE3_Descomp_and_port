# Motor de som do RE3 (PS1) — de-para PROVADO `id de SE` → amostra

> Engenharia reversa do **motor de efeitos sonoros** do `SLUS_009.23` (NTSC-U, base
> `0x80010000`) e do **arquivo de de-para** que liga o id de som usado pelo código à
> amostra tocada.
>
> Ferramenta: [`tools/exe_audio.py`](../../../tools/exe_audio.py) (`--verificar` roda as
> 7756 asserções; `--tabela <banco>` imprime uma tabela; `--portas`/`--salas` extraem os
> bancos embutidos).
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
| **id 9 = "abrir menu"** | rótulo desta nota | **ERRADO**: 9 = entrar no MAPA/ARQUIVO; abrir o inventário é **6** e fechar é **5** (§5.4) |
| Banco de sala (`cat 2`) | só `R000.SND` | os outros **169 estão embutidos nos `R###.ARD`** e foram **EXTRAÍDOS** (§13): 1702 amostras |

**Rodada de 2026-08-08 (3ª) — §13: os 169 bancos de SALA extraídos.** Fecha os 26 pedidos de
`cat 2` que estavam mudos (porta trancada/destrancar/emperrada, baú, subir, ricochete, SE por
script). O que mudou de rótulo:

| Assunto | Antes | Agora |
|---|---|---|
| tabela de SE da sala | `offset_table[0]` do RDT (§11.4) | **`hdr − 48*4`** — provado por `0x80078384` e pela validação cruzada com o `Key_Type` do SCD (§13.2) |
| header VAB nas salas | achado em 168/169 (`R11B` falha) | **169/169**; a `R11B` só quebra a regra do `n_tons` (§13.3) |
| corpo PS-ADPCM da sala | não localizado | **o sub-bloco 9 do `.ARD`** (que `ARD.md` chama de `mask_extra`) — 169/169 + 1871/1871 VAG com flag de fim (§13.1) |
| `N` de ids de SE por `cat` | inferido do `hdr/4` | **tabela `0x800a0fe4` = `{16,32,48,32,4}`** (§13.1) |
| tamanho do header por versão | regularidade em 168/168 | **instrução**: `tons = hdr + 0x20 + versao*0x10` (`0x800783a4`) |
| `Key_Id` (`desc+0x0f`) | "id da chave" | **bit 7 = trancada · bits 0..5 = índice da flag de já-destrancada** (§13.6) |

**Rodada de 2026-08-08 (4ª) — §14: clique seco e recarga.**

| Assunto | Antes | Agora |
|---|---|---|
| id do mecanismo/recarga da arma | "vem de RAM, **não extraível** do estático" (§12.1) | **evento de som POR QUADRO** da frame-list do EDD do banco 2 do `.PLW` — extraído: 58 eventos, 31/31 conferindo com o `A_{w}.VH` (§14.2) |
| `player+0xe4` | "ponteiro para os props da arma" | **cursor da frame-list da animação** (`0x8001ae04`, `0x80026ca8`) |
| `cat 1 / id 1` | "arma: mecanismo do sub 1", DECLARADO | **CLIQUE SECO** — os 4 sítios são o ramo "a munição não está no inventário" (§14.4) |

**Rodada de 2026-08-08 (2ª) — §12: os 155 call sites varridos de uma vez.** Em vez de perseguir
som item a item, a lista inteira está fechada em `data/se_callsites.json` (155 linhas com função,
`cat`/`id`, `a1`, evento e confiança). O que mudou de rótulo:

| Assunto | Antes | Agora |
|---|---|---|
| `cat 0 / id 0` | `impacto_ataque` (o ataque do player conectou) | **DANO AO PLAYER** — anim 4; os ids 0..3 são as 4 variantes (§12.5.1) |
| `cat 0 / id 8` (`acao_8`) | "não sei" | **VIRAR PÁGINA do documento** — 2 sítios, um por direção (§12.5.4) |
| escolha do submenu do inventário | sempre id 6 | USE/EQUIP = **5**, CHECK = **6** (§12.5.2) |
| combinação | sempre id 6, antes do resultado | **6** se fecha, **7** se não (§12.5.3) |
| `acao_13` / `acao_14` | sem nome | `impacto_projetil` / `sala_entrada` (§12.5.5) |
| recarga da arma | "não identificada" | **localizada** (`0x8003f5e8`, subestado 4), mas o **id vem de RAM** (§12.1) |
| pegar item | "não identificado" | **`cat 0 / id 5`**, os 2 sítios de `0x80069c3c` (§12.3) |

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
| **5** | cancelar / voltar — **e FECHAR a tela de status** (§5.4) | 6 | 5 | `C_00/C_00_03.wav` |
| **6** | confirmar — **e ABRIR a tela de status** (§5.4) | 7 | 6 | `C_00/C_00_04.wav` |
| **7** | inválido | 8 | 2 | `C_00/C_00_00.wav` |
| **9** | entrar no MAPA / ARQUIVO (**não** é "abrir menu" — §5.4) | 12 | 3 | `C_00/C_00_01.wav` |

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

### 5.4 Abrir ≠ fechar a tela de status — e o id 9 **não** é "abrir menu" (2026-08-08)

O port tocava o **id 9** ao abrir *e* ao fechar o inventário (`MenuStatus.alternar`), porque esta
nota chamava o 9 de "abrir menu". O rótulo estava **errado**. Desmontando os 5 call sites do id 9
e o caminho de abertura/fechamento da task do menu (contexto `0x800e01c0`, ver
[`menu_pc_sys.md`](menu_pc_sys.md) §4-§6):

| evento | id | prova |
|---|---:|---|
| **ABRIR a tela de status** (botão de menu) | **6** | `0x80023c9c` `log_edge & 0x4000` → `0x800d1f2c \|= 0x200` e `ctx+0x04 = 0` (`0x80023cb0`). No mesmo quadro `0x80023d58` vê a flag e cai em `0x80023d60`, que arma a task (`0x800c7961 = 1`) e pede o SE em `0x80023db8`. O `a0` sai de `0x80023da4`: `bne ctx+0x04, 4` **TOMADO** (modo 0) ⇒ vale o delay slot `addiu a0, zero, 6` de `0x80023da8` |
| **ABRIR o MAPA** (L2, direto do jogo) | **9** | mesmo `jal` de `0x80023db8`, mas com `ctx+0x04 = 4` (`0x80023cd0`, `raw_edge & 1`) ⇒ o `bne` NÃO é tomado e vale `addiu a0, zero, 9` de `0x80023dac` |
| **FECHAR a tela de status** (cancelar) | **5** | `0x80066628`..`0x80066634`: `(raw_edge & 0x20) \| (log_edge & 0x2000)` desvia para `0x80066744` (`a0 = 5`), pede em `0x8006675c` e faz `ctx+0x10++` (`0x80066750`/`0x80066760`) → estado 3 (`0x8006a888`) → estado 13 = **fechamento** (`0x8006e4cc`) |
| **botão SAIR** da tela | **5** | mesmo bloco: `slti ctx+0x1c, -2` em `0x80066738` cai em `0x80066744` |
| **botão ARQ.** (cursor em `-2`) | **9** | `0x80066728`, junto com `ctx+0x11 = 5` (sub-estado 5 = ARQUIVO) |
| **botão MAPA** (cursor em `-1`) | **9** | `0x800666f0`, junto com `ctx+0x11 = 4` (sub-estado 4 = MAPA) |
| confirmar em slot **com** item | **6** | `0x8006669c` (o `lbu (s1)` de `0x80066660` é o id do slot) |
| confirmar em slot **vazio** | **7** | `0x800666bc` |
| 5º call site do id 9 | **9** | `0x8006dd40`, braço **5** da tabela de init `0x8001100c` (kind 5 = mensagem/mapa por item usado) — e `0x8006fdb4`, no sub-dispatcher do mapa |

Ou seja o id 9 é **"entrar em outra sub-tela"**, nunca "abrir/fechar o inventário". Resumo do
que o port passou a fazer (`port/core/sfx.gd`: `menu_status_abrir` = 6, `menu_fechar` = 5,
`menu_abrir` = 9 só para ARQ./MAPA):

* abrir inventário → 6 · fechar (ESC, SAIR) → 5 · ARQ./MAPA → 9 · slot com item → 6 ·
  slot vazio → 7 · mover cursor → 4.

**Efeito colateral corrigido:** `MenuStatus.cancelar()` tocava o id 5 e depois chamava
`alternar()`, que tocava o 9 — **dois SE no mesmo ESC**. Agora `alternar(false)` cala o segundo.

**De-para índice negativo → botão, que a nota do inventário declarava NÃO MEDIDO, também
fechou:** UP faz `sel -= 2` (grade de 2 colunas), então da coluna esquerda sai `-2` (ARQUIVO) e
da direita `-1` (MAPA); `sel < -2` é SAIR. Ver `menu_pc_sys.md` §6.2 (subs 4 e 5).

### 5.2 Ids de jogo — call site provado, **semântica DECLARADA**

Cada linha tem o call site medido; o **nome** é escolha do port até alguém ouvir.

| cat | id | call sites | nome no port | observação |
|---:|---:|---|---|---|
| 0 | 11 | `0x8003ad6c` (`lui a0,1; ori a0,a0,0xb`), `0x8003cf10` | `tiro` | `a1 = player+0x34` (posição). **`C_00`/`C_01` não definem o id 11** — só os `C_02..C_0D` de área. Coerente com "não há tiro no menu" |
| 0 | 0 | `0x8003d208` (`lui a0,1`) | `dano_player` (**era `impacto_ataque` — errado, §12.5.1**) | grava `player+0xc8 = 0x30004`, `player+6 = 1`; vizinho de `0x8003d14c` = "acerto conectado" (`exe_combat.md`) |
| 0 | 1 / 2 / 3 | `0x8003d560` / `0x8003d82c` / `0x8003dac8` | `dano_player_2/3/4` (§12.5.1) | 3 ids consecutivos, 1 call site cada, na mesma região de ação do jogador |
| 0 | 8 | `0x80063984` `0x80063a2c` | **`arquivo_pagina`** (virar página — §12.5.4) | `a1 = 0` → UI |
| 0 | 13 | `0x80045b10` `0x80045e68` `0x800465fc` | `impacto_projetil` (§12.5.5) | |
| 0 | 14 | `0x80077f40` | `sala_entrada` (§12.5.5) | `a1 = 0` → UI |
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
| **Qual id em abrir / fechar / ARQ. / MAPA / slot vazio** | fechado (§5.4) | **ALTA** (imediato no fluxo de cada caminho, com o endereço do `jal`) |
| **Porta**: banco `cat 4` embutido nos 76 `DOOR??.DO1` | fechado (§4.4) | **ALTA** no formato / **MÉDIA** no nome (qual id é abrir vs fechar não foi medido) |
| **Estouro da arma** = `cat 1 / id 0` do banco `A_{w}` | fechado (§11.1) | **ALTA** (tabela por arma `0x8009ced8` + `A_01` sem id 0) |
| De-para **item do inventário → `w`** (qual `A_xx` em cada arma) | **NÃO MEDIDO** — o port usa faca=1 / resto=2, DECLARADO | BAIXA |
| Nome das outras ações de jogo | **74 DECLARADO / 17 NÃO SEI** — tabela completa na §12.2 | — |
| Quem preenche `SND_CTX + cat*4` | fechado: `0x8007809c`, chamado por `0x800495d0` (cat 0 = personagem) e `0x80043eb4` (cat 1 = arma) | **ALTA** |
| **Som de PASSO** | **NÃO PROVADO** — 0 pedidos de SE nas 4 rotinas de locomoção do player, e não há segundo enfileirador (§11.2) | — |
| Pegar item | **`cat 0 / id 5`** (`0x80069ed0`, `0x80069fb0` em `0x80069c3c`) | ALTA no sítio |
| Recarga | sítio **PROVADO** (`0x8003f5e8`, subestado 4), mas o **id vem de `u16@*(player+0xe4)`, que é RAM** | — |
| `cat 3` = banco do INIMIGO (helpers `0x800775a0`/`0x80077618`), `cat 5/6/7` = ambiente | call sites achados, **banco de origem não localizado** | — |
| De-para **sala → faixa de BGM** | fechado (§7): sha1 dos 676 blocos de SEQ dos 169 `.ARD` × os nomes do `Rofs7.dat` do PC | **ALTA** no nome / **MÉDIA** no render (32 salas `NAO_CASADO`) |
| Banco de sala (`cat 2`) das 168 salas embutido no `.ARD` | localizado e validado (§11.4), **não extraído** | **ALTA** no layout |
| Idioma real das 370 vozes e do `MAIN07` | **inferido** (§8) | MÉDIA — falta ouvir |

---

## 10. Como reproduzir

```bash
# tabela de SE de um banco
python tools/exe_audio.py --tabela C_00
python tools/exe_audio.py --tabela A_02      # banco de ARMA: o id 0 é o estouro (§11.1)

# 7756 asserções que sustentam o de-para
python tools/exe_audio.py --verificar

# os 155 `jal 0x800746c0`: tabela completa (função, cat/idx, a1, evento, confiança) — §12
python tools/exe_audio.py --callsites
NOSTALGIA_OUT=port python tools/exe_audio.py --callsites --json   # + data/se_callsites.json

# extrai os WAV dos 76 bancos de porta (147 amostras)
NOSTALGIA_OUT=port python tools/exe_audio.py --portas

# extrai os WAV dos 169 bancos de SALA (1702 amostras) — §13
NOSTALGIA_OUT=port python tools/exe_audio.py --salas
python tools/exe_audio.py --tabela R101         # a tabela de 48 ids de uma sala

# SE de mecanismo/recarga da arma: os eventos por QUADRO do .PLW (58 nas 21 armas) — §14
python tools/exe_audio.py --armas

# gera data/re3_se.json (280 bancos) + data/sfx_map.json no destino do port
NOSTALGIA_OUT=port python tools/exe_audio.py

# mapa sala -> faixa de BGM (169 salas, prova por sha1 dos blocos do ARD) — §7
python tools/audio_gog.py --mapa

# teste do port (190 asserções) — SEMPRE com filtro, a suíte inteira leva ~7 min
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

> ⚠ **Três afirmações desta seção estavam ERRADAS e foram corrigidas na §13** (a rodada que
> extraiu os bancos). Ficam aqui riscadas porque o erro é instrutivo:
> 1. a tabela de SE **não** começa em `off[0]` — começa em `hdr − 48*4`, e o header fica
>    `pad` bytes (8..28) depois de `off[1]`, então as duas janelas de `0xC0` são diferentes;
> 2. o header VAB é achado em **169/169**, não 168/169 — a `R11B` tem header, versão 2;
> 3. "os descritores citam mais de um banco" era consequência do erro (1): com a base certa,
>    **2184 dos 2209** descritores citam o banco 2, e os 25 restantes vêm de 3 salas só.

- `off[1] − off[0] == 0xC0` em **169/169** — o que é verdade, e foi justamente o que fez a
  base errada parecer certa.
- O header VAB é achado pelo magic `0xeeee` em `hdr+0x10`, com `hdr+0x18 = 0x7f` (volume) e
  `hdr+0x19 = 0x40` (pan): **169/169**.
- **O `u16` alto do magic é a VERSÃO do VAB**, e ela muda o tamanho do header:
  `0x0001eeee` → header **0x30** (94 salas, e os 35 bancos do disco) · `0x0002eeee` →
  header **0x40** (75 salas). Isso deixou de ser estatística: `0x800783a4..0x800783b0`
  calcula literalmente `tons = hdr + 0x20 + versao*0x10` (§13.1).

Consequência prática: **extrair os 169 bancos de sala é possível** — e foi feito na §13.

---

## 12. Rodada de 2026-08-08 (2ª) — **os 155 call sites, varridos de uma vez**

> Por que esta seção existe: o dono do repo estava pedindo som **item a item** (o último foi o
> de virar página do documento). Isso é falha de método. Como o anel `0x800e0de4` **só** é
> escrito por `0x800746c0` e **só** é lido/zerado por `0x800744e0` (§2), **todo** som do jogo
> passa por um dos 155 `jal`. Então a lista fechada responde a todas as perguntas de uma vez.

Ferramenta: **`python tools/exe_audio.py --callsites [--json]`**. O JSON versionável é
**`data/se_callsites.json`** (155 linhas: `jal`, função envolvente, `cat`/`id`, a instrução que
produziu o `a0`, se o `a1` é 0 (UI) ou posição 3D, o evento e a confiança). O `--verificar`
passou a checar a tabela (**1937 asserções, 0 falhas**).

### 12.1 Placar

| | n |
|---|---:|
| call sites de `0x800746c0` | **155** |
| com `a0` constante (imediato recuperado por back-walk) | 129 |
| com `a0` **dinâmico** (id vem de dado/argumento) | 26 |
| funções distintas que pedem SE | 86 |
| **evento PROVADO** (cat/id *e* evento saem da desmontagem) | **64** |
| **evento DECLARADO** (cat/id medido, nome é escolha nossa) | **74** |
| **NÃO SEI** (cat/id medido, evento não identificado) | **17** |

Três sítios têm o `a0` **constante mas fora do bloco**: o back-walk linear pega a instrução do
bloco vizinho, e o valor certo está no *delay slot* do desvio que entra no bloco do `jal`. Os
três foram fechados enumerando **todos** os predecessores (`A0_POR_PREDECESSOR` na ferramenta):
`0x800517d0` (a0 = `0x228`), `0x80068a10` (a0 = 6, **7 predecessores, todos com 6**) e
`0x80069fb0` (a0 = 5).

Um achado de forma que aparece 11 vezes: o **som de MECANISMO da arma** não tem id fixo —

```
v0 = u16 @ *(player+0xe4)        ; props da ARMA (RAM)
if ((v0 & 0xf000) == 0) pula
a0 = 0x10100 | ((v0 >> 12) - 1)  ; cat 1, id = nibble alto - 1
```

Não existe **nenhum** `sw` para `+0xe4` no `.text`. A conclusão que estava aqui — *"o de-para
arma → nibble não é extraível do estático"* — está **ERRADA e foi corrigida na §14**:
`player+0xe4` não guarda props, é o **cursor da frame-list do EDD do banco 2 do `.PLW`**
(escrito por `0x8001ae04`/`0x8001ae20` e `0x80026ca8`/`0x80026cc0`), e o nibble é um **evento de
som por quadro de animação** — dado do disco. Um dos 11 é `0x8003f5e8`, dentro do subestado
**4 = RECARGA** (`recuo_tiro.md` §linha 50), e agora *o id dela também está medido*.

### 12.2 A tabela (agrupada por evento; as 155 linhas estão no JSON)

| evento | `cat`/`id` | n | call sites (`jal`) | função | conf |
|---|---|---:|---|---|---|
| porta: transição (o único cat 4 do EXE) | `4/1` | 1 | `0x800161c4` | `0x80016150` | PROVADO |
| objeto: SE empacotado em u8@obj+0x19 | `?/u8@obj+0x19` | 3 | `0x8001c3e0` `0x8001c440` `0x8001c578` | `0x8001c38c` `0x8001c49c` | PROVADO |
| objeto: SE de sala com idx = u16@obj+0x22 | `2/u16@obj+0x22` · `2/u16@obj+0x22 + (rand & 1)` | 2 | `0x8001c838` `0x8001c864` | `0x8001c5bc` | PROVADO |
| inimigo t21: som de ação | `1/14` · `1/15` · `1/16` · `1/17` · `2/42` · `3/20` | 6 | `0x8001d464` `0x8001db0c` `0x8001dc64` `0x8001dce4` `0x8001dec8` `0x8001dfec` | `0x8001d210` `0x8001d7d0` | DECLARADO |
| inimigo t22: som de ação | `1/10` | 1 | `0x8001e3ec` | `0x8001e0f4` | DECLARADO |
| zumbi: som de ação | `2/14 ou 30` · `3/8 ou 24` | 2 | `0x8001ec4c` `0x8001edb8` | `0x8001e444` | DECLARADO |
| **não identificado** — função de ator alcançada por tabela | `2/19` | 1 | `0x80021cdc` | `0x8002198c` | NAO_SEI |
| abrir a tela de STATUS (id 6) | `0/6` | 1 | `0x80023d10` | `0x80023268` | PROVADO |
| abrir a tela de STATUS (id 6, ctx+0x04 == 0) OU entrar no MAPA (id 9, ctx+0x04 == 4) | `0/9` | 1 | `0x80023db8` | `0x80023268` | PROVADO |
| **não identificado** — região de DRAW/ator (emd_skinning.md §linha 362) | `2/46` | 1 | `0x80024f04` | `0x80024ce8` | NAO_SEI |
| **não identificado** — chamada por 0x80024ce8 (DRAW/ator) | `2/46` | 2 | `0x80025038` `0x800250f0` | `0x80024f74` `0x800250cc` | NAO_SEI |
| SE pedido pelo SCRIPT: cat 2, idx = próximo byte do stream | `2/byte do stream` | 1 | `0x80030010` | `0x8002fee8` | PROVADO |
| caixa de mensagem: avançar (4) / fechar (5) | `0/4` · `0/5` | 4 | `0x800304e0` `0x8003054c` `0x8003088c` `0x800308f8` | `0x800303ec` `0x80030764` | DECLARADO |
| **não identificado** — chamada por 0x80036d5c/0x80036f10/0x80036f40 | `2/19` · `2/2` | 2 | `0x80036934` `0x80036b8c` | `0x800366ec` | NAO_SEI |
| mira: sub 2 -> 3 (mexe em player+0x6e e no contador u16 0x800d1f96) | `0/11` | 1 | `0x8003ad6c` | `0x8003a7d8` | NAO_SEI |
| subir: início do movimento (grava +0xc8=6/+0xc9=0/+0xca=7 e vibra) | `2/0` | 1 | `0x8003b224` | `0x8003b1c4` | PROVADO |
| subir: impacto (sub 5 com +0xc9 == 1) | `2/44` | 1 | `0x8003b3e8` | `0x8003b244` | DECLARADO |
| player AGARRADO: voz (anim 18 + gs+0x785e++) | `0/11` | 1 | `0x8003cf10` | `0x8003cea0` | DECLARADO |
| mordida do inimigo que agarrou (cat 3, id 3 ou 19 pelo tipo) | `3/3 ou 19` | 1 | `0x8003d114` | `0x8003cea0` | DECLARADO |
| dano ao player | `0/0` | 1 | `0x8003d208` | `0x8003d1a8` | PROVADO |
| dano ao player (variante) | `0/1` · `0/1 ou 2` · `0/2` · `0/3` | 4 | `0x8003d354` `0x8003d560` `0x8003d82c` `0x8003dac8` | `0x8003d2d8` `0x8003d4c0` `0x8003d780` `0x8003da3c` | PROVADO |
| arma: som de mecanismo | `1/6` · `1/8` · `1/9` | 4 | `0x8003e750` `0x8003e82c` `0x8003e8f0` `0x8003e934` | `0x8003e4d0` | DECLARADO |
| arma: mecanismo do sub 1 | `1/1` | 1 | `0x8003f190` | `0x8003ef08` | DECLARADO |
| RECARGA da arma | `1/(u16@*(player+0xe4) >> 12) - 1` | 1 | `0x8003f5e8` | `0x8003f520` | PROVADO |
| arma: mecanismo do sub 8 | `1/1` | 1 | `0x8003fd90` | `0x8003fb78` | DECLARADO |
| arma: mecanismo | `1/1` | 2 | `0x8004029c` `0x8004070c` | `0x8003ffd8` `0x800402f4` | DECLARADO |
| arma: mecanismo (id dinâmico) | `1/(u16@*(player+0xe4) >> 12) - 1` | 1 | `0x8004082c` | `0x80040764` | DECLARADO |
| **não identificado** — subestado de arma (ids 18/19) | `1/18` · `1/19` | 3 | `0x8004097c` `0x80040bc0` `0x80040c5c` | `0x80040900` | NAO_SEI |
| facada (A_01 define só os ids 6..10) | `1/(u16@*(player+0xe4) >> 12) - 1` | 1 | `0x80040f78` | `0x80040f34` | DECLARADO |
| ESTOURO da arma (cat 1 / id 0) | `1/0` | 17 | `0x80041018` `0x80041184` `0x8004161c` `0x80041904` `0x80041ab8` `0x80041c6c` `0x80041e20` `0x80041fd8` `0x800422a0` `0x800424bc` `0x800426e8` `0x80042a7c` `0x80042b9c` `0x80042edc` `0x800433b0` `0x80043584` `0x80043a40` | `0x80040f90` `0x800410f8` `0x80041594` `0x800418cc` `0x80041a80` `0x80041c34` `0x80041de8` `0x80041f9c` `0x800421f8` `0x80042474` `0x80042660` `0x800427d8` `0x80042ae4` `0x80042e34` `0x80043328` `0x800434f8` `0x800439f8` | PROVADO |
| arma: som de mecanismo (id = nibble dos props em RAM) | `1/(u16@*(player+0xe4) >> 12) - 1` | 7 | `0x800414e0` `0x80041a14` `0x80041bc8` `0x80041d7c` `0x80041f30` `0x80043244` `0x80043928` | `0x800410f8` `0x800418cc` `0x80041a80` `0x80041c34` `0x80041de8` `0x80042e34` `0x800434f8` | DECLARADO |
| **não identificado** — chamada por 0x80038d34 (exe_combat.md §linha 268) | `1/4` | 1 | `0x800451d4` | `0x80045094` | NAO_SEI |
| **não identificado** — vizinha de 0x80045094 (projétil) | `1/4` | 1 | `0x80045440` | `0x800452e8` | NAO_SEI |
| impacto do projétil | `0/13` | 3 | `0x80045b10` `0x80045e68` `0x800465fc` | `0x80045950` | DECLARADO |
| **não identificado** — chamada por 0x8002378c, dentro do fluxo de jogo 0x80023268 | `0/15` | 1 | `0x800485e4` | `0x80048520` | NAO_SEI |
| porta: BLOQUEADA (Key_Type == 0xfe) + mensagem 0x11 | `2/38` | 1 | `0x80050dd8` | `0x80050d28` | PROVADO |
| porta: TRANCADA para sempre (Key_Type == 0xff) + mensagem 0x12 | `2/22` | 1 | `0x80050e10` | `0x80050d28` | PROVADO |
| porta: DESTRANCAR com a chave | `2/37` | 1 | `0x80050e74` | `0x80050d28` | PROVADO |
| porta: TRANCADA — não tem a chave | `2/22` | 1 | `0x80050ed8` | `0x80050d28` | PROVADO |
| porta: TRANCADA — não tem a chave (2º ramo) | `2/22` | 1 | `0x80050f14` | `0x80050d28` | PROVADO |
| baú: abrir a caixa de itens | `2/20` | 1 | `0x80051578` | `0x800514f0` | DECLARADO |
| sce 11: a0 = 0x228 vem do delay slot do bnez de 0x8005175c | `2/40` | 1 | `0x800517d0` | `0x800516a4` | NAO_SEI |
| SE por script: cat/idx nos operandos | `?/operandos do opcode 0x77` | 1 | `0x80055164` | `0x80055038` | PROVADO |
| ambiente por script: cat = arg + 5, idx 0 | `?/0` | 1 | `0x800553d0` | `0x8005518c` | PROVADO |
| arquivo: confirmar já na última página (ctx+0xbd >= páginas-1) -> sub 4 | `0/4` | 1 | `0x800638f4` | `0x80063850` | PROVADO |
| arquivo: VIRAR PÁGINA para trás (ctx+0xbd -= 1, ctx+0xc6 = 2) | `0/8` | 1 | `0x80063984` | `0x80063850` | PROVADO |
| arquivo: VIRAR PÁGINA para frente (ctx+0xbd += 1, ctx+0xc6 = -2) | `0/8` | 1 | `0x80063a2c` | `0x80063850` | PROVADO |
| arquivo: sair da leitura | `0/5` | 1 | `0x80063c20` | `0x80063850` | PROVADO |
| arquivo: fechar a tela (estado 9 -> 13) | `0/5` | 1 | `0x80063e74` | `0x80063cac` | DECLARADO |
| baú: confirmar / cancelar / mover | `0/4` · `0/5` · `0/6` | 3 | `0x80064500` `0x80064538` `0x80064684` | `0x8006446c` | DECLARADO |
| baú: cancelar | `0/5` | 2 | `0x80064740` `0x800650f4` | `0x800646f0` `0x800650c4` | DECLARADO |
| baú: confirmar | `0/6` | 1 | `0x80064aa4` | `0x800646f0` | DECLARADO |
| baú: transferir item (cat 2 / id 0x15) | `2/21` | 4 | `0x80064b2c` `0x80064bc8` `0x80064d1c` `0x80064d90` | `0x800646f0` | DECLARADO |
| inventário: confirmar em slot COM item | `0/6` | 1 | `0x8006669c` | `0x80066604` | PROVADO |
| inventário: confirmar em slot VAZIO | `0/7` | 1 | `0x800666bc` | `0x80066604` | PROVADO |
| inventário: botão MAPA (ctx+0x1c == -1 -> sub 4) | `0/9` | 1 | `0x800666f0` | `0x80066604` | PROVADO |
| inventário: botão ARQ. (ctx+0x1c == -2 -> sub 5) | `0/9` | 1 | `0x80066728` | `0x80066604` | PROVADO |
| inventário: FECHAR (cancelar ou botão SAIR) | `0/5` | 1 | `0x8006675c` | `0x80066604` | PROVADO |
| inventário: mover o cursor da grade | `0/4` | 1 | `0x8006688c` | `0x80066604` | PROVADO |
| comandos: mover | `0/4` | 1 | `0x80066a78` | `0x80066920` | DECLARADO |
| arquivo: entrar / mover / cancelar | `0/4` · `0/5` · `0/6` | 4 | `0x80066e44` `0x80066f00` `0x800670f4` `0x800672b0` | `0x80066ca0` | DECLARADO |
| equipar/usar: confirma e sai (comando 0) | `0/5` | 1 | `0x80067b40` | `0x800676b8` | PROVADO |
| combinar: mover / recusado / cancelar | `0/4` · `0/5` · `0/7` | 4 | `0x80067c90` `0x80067e90` `0x80067ebc` `0x80067fc8` | `0x80067c14` | PROVADO |
| combinar: receita NÃO fecha | `0/7` | 1 | `0x800687b0` | `0x80068024` | PROVADO |
| combinar: DEU (7 predecessores, todos com a0 = 6) | `0/6` | 1 | `0x80068a10` | `0x80068024` | PROVADO |
| combinar: cancelar | `0/5` | 2 | `0x80068a88` `0x80068b44` | `0x80068a5c` `0x80068abc` | DECLARADO |
| examinar: entra no texto de exame | `0/6` | 1 | `0x80069454` | `0x80069280` | PROVADO |
| examinar: sair do texto de exame | `0/5` | 1 | `0x80069470` | `0x80069280` | DECLARADO |
| item PEGO (janela de obter) | `0/5` | 1 | `0x80069ed0` | `0x80069c3c` | PROVADO |
| item PEGO — a0 vem do delay slot do beq de 0x80069eb8 (a0 = 5) | `0/5` | 1 | `0x80069fb0` | `0x80069c3c` | PROVADO |
| confirmar / cancelar | `0/5` · `0/6` | 3 | `0x8006a2b4` `0x8006a340` `0x8006a514` | `0x8006a234` | DECLARADO |
| entrar em sub-tela (id 9) | `0/9` | 1 | `0x8006dd40` | `0x8006d948` | PROVADO |
| mapa: navegar | `0/5` · `0/6` · `2/43` | 8 | `0x8006f790` `0x8006f7d8` `0x8006f814` `0x8006f86c` `0x8006f8bc` `0x8006f914` `0x8006f954` `0x8006f988` | `0x8006f708` | DECLARADO |
| mapa: navegar/sair | `0/4` · `0/5` · `0/7` · `0/9` | 5 | `0x8006fd58` `0x8006fdb4` `0x8006fdd0` `0x8006fdf8` `0x8006fe44` | `0x8006fc68` | DECLARADO |
| mapa: sair | `0/5` | 1 | `0x8007021c` | `0x80070024` | DECLARADO |
| inimigo: SE por id (cat 3) | `3/a2 (+0x10 quando o tipo casa)` · `3/a3 (+0x10 quando o tipo casa)` | 2 | `0x80077600` `0x80077698` | `0x800775a0` `0x80077618` | PROVADO |
| impacto/ricochete de bala na sala (cat 2, idx = base + a0) | `2/s5` | 1 | `0x80077b50` | `0x800776b0` | PROVADO |
| entrada de sala / ambiente global | `0/14` | 1 | `0x80077f40` | `0x80077ed4` | DECLARADO |
| **não identificado** — ligador de ambiente cat 5/6/7 (idx 0), sob os bits 1/2/4 de um byte de estado | `5/0` · `6/0` · `7/0` | 3 | `0x80078004` `0x80078048` `0x8007807c` | `0x80077f60` | NAO_SEI |

### 12.3 O que foi LIGADO no port nesta rodada

Todos com o call site no comentário do código.

| evento | ação do `Sfx` | `cat`/`id` | onde o port dispara |
|---|---|---|---|
| **virar página do documento** | `arquivo_pagina()` | 0/8 | `MenuArquivo.virar_pagina` (só quando a página muda de fato — o EXE também checa a borda antes de pedir) |
| mover na grade de documentos | `menu_mover()` | 0/4 | `MenuArquivo.mover_grade` / `mover_lista` |
| abrir a leitura de um documento | `menu_confirmar()` | 0/6 | `MenuArquivo.confirmar` |
| documento não lido | `menu_invalido()` | 0/7 | `MenuArquivo.confirmar` |
| sair da leitura / fechar | `menu_cancelar()` | 0/5 | `MenuArquivo.confirmar` / `cancelar` |
| **item pego** | `item_pego()` | 0/5 | `World.usar` (quando `pegar_item_sob_o_player` devolve o AOT) |
| **combinar: deu** | `combinar_ok()` | 0/6 | `MenuStatus.confirmar` (agora **depois** de saber o resultado) |
| **combinar: não fecha** | `combinar_erro()` | 0/7 | idem |
| **equipar / usar** | `equipar()` | 0/5 | `MenuStatus.confirmar`, escolha `EQUIP`/`USE` do submenu |
| **examinar (CHECK)** | `examinar()` | 0/6 | `MenuStatus.confirmar`, escolha `CHECK` |
| **dano ao player** (4 variantes) | `dano_player(0..3)` | 0/0..3 | API pronta; o gatilho vive no `player.gd` (§12.4) |
| agarrado pelo inimigo | `agarrado()` | 0/11 | API pronta, sem gatilho ainda |
| porta bloqueada | `porta_emperrada()` | 2/38 | API pronta (sem amostra) |
| subir / descer | `subir()` / `subir_impacto()` | 2/0 · 2/44 | API pronta; `subir.sfx_pendente` já existe em `script_vm/subir.gd` |
| baú | `bau_abrir()` / `bau_mover()` | 2/20 · 2/21 | API pronta, sem tela de baú no port |
| impacto de projétil | `impacto_projetil()` | 0/13 | API pronta |
| entrada de sala | `sala_entrada()` | 0/14 | API pronta |
| caixa de mensagem | `mensagem_avanca()` / `mensagem_fecha()` | 0/4 · 0/5 | API pronta |

**Detalhe que quase fez o som novo sair mudo:** `C_00`/`C_01` — os bancos de **menu** — **não
definem o id 8**. Quem define são os `C_02..C_0D`, que é o banco de `cat 0` que o jogo carrega
em sala (`0x800495d0`). O `re3_se.json` resolve isso pelo `banco_declarado` (cai no `C_02`), e o
`World` chama `definir_banco_area()` no `_init`.

### 12.4 O que NÃO tem gatilho no port — o mapa do que falta

Duas categorias diferentes, e vale não confundir.

**(a) Falta a AMOSTRA (`cat 2` = banco de SALA).** ✅ **RESOLVIDO na §13** — os 169 bancos
foram extraídos (1702 amostras) e os 26 pedidos abaixo passaram a soar. A lista fica como
índice do que foi ligado; a coluna "quantas salas definem o id" está na §13.4.

| evento | `cat`/`id` | call site |
|---|---|---|
| porta TRANCADA (sem chave / `Key_Type == 0xff`) | 2/22 | `0x80050e10` `0x80050ed8` `0x80050f14` |
| porta DESTRANCAR com a chave | 2/37 | `0x80050e74` |
| porta BLOQUEADA (`Key_Type == 0xfe`) | 2/38 | `0x80050dd8` |
| subir/descer + impacto | 2/0 · 2/44 | `0x8003b224` `0x8003b3e8` |
| baú: abrir · transferir | 2/20 · 2/21 | `0x80051578` · 4 sítios em `0x800646f0` |
| impacto/ricochete de bala na sala | 2/`s5` | `0x80077b50` |
| SE pedido pelo script (byte do stream) | 2/byte | `0x80030010` |
| objeto do cenário (tipo 5/6) | 2/`u16@obj+0x22` | `0x8001c838` `0x8001c864` |
| mapa / inimigos / atores (ids 2, 19, 40, 42, 43, 46) | 2/… | `0x80021cdc` `0x80024f04` `0x80025038` `0x800250f0` `0x80036934` `0x80036b8c` `0x8001db0c` `0x8001edb8` `0x8006f790` `0x800517d0` |

**(b) Falta o EVENTO no port** (o código do jogo ainda não faz isso). É a lista do que
implementar, e cada linha já vem com o id certo:

| evento que falta no port | `cat`/`id` | call site |
|---|---|---|
| **porta trancada / destrancar** — o port não tem lógica de `Key_Type`/chave em `atravessar` | 2/22 · 2/37 | `0x80050ed8` · `0x80050e74` |
| **recarga da arma** — ✅ id RESOLVIDO na §14 (evento de quadro do `.PLW`); falta o gatilho | 1/`nibble` | `0x8003f5e8` (subestado 4) |
| **clique seco (sem bala)** — ✅ id RESOLVIDO na §14 (`cat 1 / id 1`); falta o gatilho | 1/1 | `0x8003f190` `0x8003fd90` `0x8004029c` `0x8004070c` |
| mecanismo da arma (ferrolho, engate, faca) — ids `nibble` resolvidos na §14; os 18/19 seguem NÃO IDENTIFICADOS | 1/6, 1/8, 1/9, 1/18, 1/19, `nibble` | `0x8003e750` `0x8003e82c` `0x8003e8f0` `0x8003e934` `0x8004097c` `0x80040bc0` `0x80040c5c` + 11 dinâmicos |
| **vozes/ações de inimigo** (`cat 3`, banco **não localizado**) | 3/3, 3/8, 3/19, 3/20, 3/24, 3/`arg` | `0x8001d464` `0x8001ec4c` `0x8003d114` `0x80077600` `0x80077698` |
| **dano ao player** (a API existe, o gatilho não) | 0/0..3 | `0x8003d208` `0x8003d354` `0x8003d560` `0x8003d82c` `0x8003dac8` |
| agarrado pelo inimigo | 0/11 | `0x8003cf10` |
| tela de MAPA (o port não tem) | 0/4,5,6,7,9 | 14 sítios em `0x8006f708` `0x8006fc68` `0x80070024` |
| tela do BAÚ (o port não tem) | 0/4,5,6 | 6 sítios em `0x8006446c` `0x800646f0` `0x800650c4` |
| caixa de mensagem do script | 0/4 · 0/5 | `0x8003054c` `0x800308f8` · `0x800304e0` `0x8003088c` |
| ambiente por script (`cat 5/6/7`) | 5/0 · 6/0 · 7/0 | `0x80078004` `0x80078048` `0x8007807c` + o opcode `0x78` (`0x800553d0`) |
| SE por script (opcode `0x77`; cat e id vêm do bytecode) | ?/? | `0x80055164` |

E o **gancho que falta em `port/actors/player.gd`** (não é meu arquivo). Em `player.gd:603` o
`if subir.sfx_pendente != 0 and sfx != null:` tem um `pass`. O corpo certo é:

```gdscript
if subir.sfx_pendente == SubirObjeto.SFX_INICIO:
    sfx.subir()            # cat 2 / id 0  (0x8003b224)
else:
    sfx.subir_impacto()    # cat 2 / id 44 (0x8003b3e8)
```

E o **dano**: onde o `player.gd` aplica dano (o equivalente da região
`0x8003cea0..0x8003dac8`), chamar `sfx.dano_player(0..3)` — as 4 variantes já resolvem amostra
do `C_02`.

### 12.5 Erros corrigidos nesta rodada (registrados, como sempre)

1. **`cat 0 / id 0` NÃO é "impacto do ataque do player" — é o player TOMANDO dano.** A §5.2
   chamava o id 0 de `impacto_ataque` porque `0x8003d208` é vizinho de `0x8003d14c`
   ("acerto conectado"). Mas os 5 pedidos de `cat 0 / ids 0..3` estão nas funções
   `0x8003d1a8`, `0x8003d2d8`, `0x8003d4c0`, `0x8003d780` e `0x8003da3c`, e
   `exe_combat.md` §1.3 já havia medido **por exaustão** (168 escritores de `player+0xc8`)
   que as anims de *hurt* são 4/5/9/10/11/12, com escritores `0x8003d200`, `0x8003d52c`,
   `0x8003d630`, `0x8003d6ec`, `0x8003d72c`, `0x8003d910` e `0x8003d990` — **todos dentro
   dessas mesmas funções**. `0x8003d1a8` grava anim **4**. Renomeado para `dano_player` + 3
   variantes (`acao_1/2/3` eram elas).
2. **O som da escolha do submenu do inventário não é sempre o id 6.** O port tocava
   `menu_confirmar` (6) para `EQUIP`, `USE`, `COMBINE` e `CHECK`. Medido: o executor do
   comando 0 (USE/EQUIP, `0x800676b8`) pede **id 5** (`0x80067b40`, o único SE daquela
   função), e o comando 2 (CHECK, `0x80069280`) pede **id 6** (`0x80069454`).
3. **A combinação tem dois sons e o port tocava o de sucesso antes de saber o resultado.**
   Medido: **id 6** em `0x80068a10` quando a receita fecha, **id 7** em `0x800687b0` quando não.
4. **`acao_8` era "não sei" e é o VIRAR PÁGINA.** Os dois únicos call sites do id 8 no EXE são
   `0x80063984` (para trás) e `0x80063a2c` (para frente), no estado 8 da task do menu, cada um
   com a checagem de borda contra a tabela de páginas por documento `0x8009f2ac`.
5. **`acao_13`/`acao_14` ganharam nome com base em quem chama**: id 13 é `impacto_projetil`
   (as 3 chamadas estão em `0x80045950`, a colisão de projétil) e id 14 é `sala_entrada`
   (`0x80077ed4` é chamada por `0x800495fc`, **dentro do room-loader** `0x800493ec`).
6. **O caminho da porta trancada agora está inteiro** (a §5 só tinha o id 0x16):
   `Key_Type == 0xfe` → id 38 (`0x80050dd8`, mensagem `0x11`), `Key_Type == 0xff` → id 22
   (`0x80050e10`, mensagem `0x12`), com a chave → id 37 (`0x80050e74`), sem a chave → id 22
   (`0x80050ed8`/`0x80050f14`).

### 12.6 Resíduo honesto desta rodada

* **17 sítios seguem `NÃO SEI`** (o `--verificar` fixa esse número, então se alguém identificar
  um, o teste acusa): `0x80021cdc`, `0x80024f04`, `0x80025038`, `0x800250f0`, `0x80036934`,
  `0x80036b8c`, `0x8003ad6c`, `0x8004097c`, `0x80040bc0`, `0x80040c5c`, `0x800451d4`,
  `0x80045440`, `0x800485e4`, `0x800517d0`, `0x80078004`, `0x80078048`, `0x8007807c`.
* **`cat 3` = banco do INIMIGO** (5 pedidos): o `cat` está provado pelos dois *helpers*
  `0x800775a0`/`0x80077618`, mas **de qual arquivo vem o banco continua não localizado**.
* **`cat 1` é pedido por IA de inimigo** (`0x8001d7d0` pede ids 14..17, `0x8001e0f4` pede 10).
  Isso é estranho para um banco que a §11.1 provou ser da **ARMA equipada** — ou o inimigo usa
  o banco da arma, ou existe outro carregador de `cat 1` que não foi achado. **Em aberto.**
* **Extrair os 168 bancos de sala dos `R###.ARD`** segue sendo o passo que desbloqueia mais som
  de uma vez (26 pedidos de `cat 2`): porta trancada, baú, subir, ricochete e o SE por script.
  O layout está validado (§11.4); a extração **não foi feita**.

---

## 13. Rodada de 2026-08-08 (3ª) — **os 169 bancos de SALA (`cat 2`) extraídos**

> Era o item de maior retorno em aberto: **26 dos 155** pedidos de SE são de `cat 2` (banco da
> sala) e nenhum podia soar, porque o único banco de sala no disco é o `R000.SND` — cuja tabela
> é toda `0xffffffff`. Os outros **169** moram dentro dos `R???.ARD`.
>
> Ferramentas: `python tools/exe_audio.py --salas` (extrai) · `--tabela R101` (inspeciona) ·
> `--verificar` (**7756 asserções, 0 falhas** — eram 1937).

### 13.0 Placar

| | n |
|---|---:|
| bancos de sala extraídos | **169/169** (não 168 — ver §13.3) |
| amostras (WAV) | **1702** |
| descritores de SE usados | **2209** |
| … citando o banco 2 (o próprio) | 2184 |
| … citando OUTRO banco (não resolvem para amostra desta sala) | 25 (3 salas) |
| … com tom fora da faixa | 1 (`R708` id 24) |
| … apontando o VAG mudo do SPU (placeholder silencioso) | 56 |
| VAGs cujo último bloco tem flag de fim | **1871/1871** |
| pedidos de `cat 2` que passaram a soar | **26/26** (ver §13.5) |

### 13.1 Onde mora cada peça — e as duas provas que vêm do EXE, não de estatística

**A tabela `0x800a0fe4` = `{16, 32, 48, 32, 4, 0, 0, 0}` diz quantos ids de SE cada `cat` tem.**
É lida dentro de `0x8007836c(a0 = cat, a1 = base do banco)`, o registrador de banco VAB:

```
0x80078380  sw   $a1, ($v0)              ; *(0x800e0610 + cat*4) = a1  -> a TABELA DE SE
0x80078384  lui  $v0, 0x800a
0x80078388  addiu $v0, $v0, 0xfe4        ; 0x800a0fe4
0x8007838c  addu $a0, $a0, $v0
0x80078390  lbu  $v0, ($a0)              ; N = *(0x800a0fe4 + cat)
0x80078398  sll  $v0, $v0, 2
0x8007839c  addu $a1, $a1, $v0           ; hdr = a1 + N*4
0x800783a0  sw   $a1, 0x14($a2)          ; SND_CTX + cat*8 + 0x14 = header VAB
0x800783a4  lhu  $v0, 0x12($a1)          ; hdr+0x12 = u16 ALTO do magic = a VERSAO
0x800783a8  addiu $a1, $a1, 0x20
0x800783ac  sll  $v0, $v0, 4             ; versao * 16
0x800783b0  addu $a1, $a1, $v0           ; tons = hdr + 0x20 + versao*0x10
0x800783b8  sw   $a1, 0x18($a2)
```

Duas consequências que valem para **todos** os bancos (disco, porta e sala):

1. **`tabela_de_SE = hdr − N*4`.** Nos arquivos do disco a tabela começa no offset 0, e por
   isso `hdr == N*4` (`C_` = `0x40`, `A_` = `0x80`, `R000` = `0xC0`, `DOORxx` = `0x10`) — o
   `hdr/4` que a §4 usava é caso particular, não a regra.
2. **O tamanho do header é `0x20 + versao*0x10`.** A §11.4 tinha isso como regularidade
   observada em 168/168; `0x800783a4..0x800783b0` é a conta literal do motor.

Com isso, o banco da sala fica assim:

```
RDT:   ... [pad 8..28 B] [tabela de SE: 48 x u32]  [header VAB]  [tons]  [tabela VAG] ...
                          ^ hdr - 0xC0             ^ hdr
            ^ offset_table[0]     ^ offset_table[1] = hdr - pad

.ARD:  sub-bloco 9 (tipo 0x02) = o corpo PS-ADPCM (.VB) do banco
```

**O corpo é o sub-bloco 9 do contêiner** — o que [`ARD.md §2`](../../formatos/ARD.md) rotula
`mask_extra` / "payload extra de máscara". Duas medidas, as duas em 169/169:

* `len(sub-bloco 9) == u32@hdr+0x00` (o tamanho do `.VB` declarado no header VAB);
* com essa base, **todo** VAG da tabela termina num bloco cujo byte de flag tem o bit 0 (fim):
  **1871/1871**. E o VAG#1 mede 48 B (3 blocos) nas 169 — o mesmo bloco mudo padrão do SPU
  dos bancos do disco.

### 13.2 A base da tabela de SE: o erro da §11.4 e como o SCD o desmentiu

A §11.4 dizia "`off[0]` = tabela de SE de 48 ids", porque `off[1] − off[0] == 0xC0` em 169/169.
Mas o header não fica em `off[1]`: fica em `off[1] + pad`, com `pad` de **8, 12, 16, 20, 24 ou
28** bytes (medido nas 169). Ou seja existem **duas** janelas de `0xC0` deslocadas entre si, e a
aritmética do motor (§13.1) escolhe a que **termina em `hdr`**.

A prova independente veio do **SCD**, cruzando dois dados que nunca se falaram:
`0x80050dd8` pede `cat 2 / id 38` exatamente quando a porta tem `Key_Type == 0xfe`. Então, se a
base estiver certa, toda sala que registra uma porta dessas tem de definir o id 38 no seu banco:

| base da tabela | salas com porta `0xfe` **sem** o id 38 | salas com o id 38 **sem** porta `0xfe` |
|---|---:|---:|
| `off[0]` (§11.4) | **9 de 9** | 27 |
| **`hdr − 0xC0`** (correta) | **0 de 9** | 2 |

Idem para o id 22 (`Key_Type == 0xff` / sem a chave): com a base certa, **7 das 8** salas com
porta `0xff` definem o id 22 — a exceção é a `R20B`, cuja porta "nunca abre" simplesmente não
tem SE no original. As duas asserções estão no `--verificar`, junto com a contra-prova (o
`9 de 9` da base errada), para o erro não voltar.

Sanidade de bônus, do mesmo tipo: os ids **20/21** (abrir e mexer na CAIXA DE ITENS) aparecem em
**20** e **19** salas — e a `R100`, que é sala de baú, é uma delas.

### 13.3 A `R11B` não é exceção de header (e o que ela realmente tem)

A §11.4 dizia "header VAB achado em 168/169 (só `R11B` falha)". **Achado em 169/169.** A `R11B`
tem header **versão 2**; o que ela quebra é só a regra `u32@hdr+0x08 == tam_header + 32*n_tons`
(vale **960**, esperado **928** = `0x40 + 27*32`) — é um slot de tom sobrando. Como a tabela VAG
é lida pelo **offset** `hdr + u32@hdr+0x08`, isso não afeta nada. Dois resíduos ficam
registrados nela: é a única sala com essa folga e o único descritor do jogo com `vag == 0`
(id 5, tom 13).

Contagem por versão de header: **94** salas na versão 1 (`0x0001eeee`) e **75** na versão 2
(`0x0002eeee`) — 169. A §11.4 dizia 94 + 74 = 168 por conta da `R11B`.

### 13.4 Os 25 descritores que citam OUTRO banco

Nos 35 bancos do disco cada arquivo cita **um** banco só (§4.3). Nas salas, **3** fogem:

| sala | ids | banco citado | leitura |
|---|---|---:|---|
| `R30C` | 1..12 | **6** | 12 entradas com índice de tom sequencial → é um banco de **ambiente** carregado em `cat 6` |
| `R50D` | 4, 5, 14..17, 32..35, 38, 39 | **5** | idem, em `cat 5` |
| `R509` | 13 | **3** | banco de INIMIGO |

Isso corrobora, pelo dado, os `cat 5/6/7` que o §12.2 só tinha pelo código (`0x80078004`/
`0x80078048`/`0x8007807c`, e o opcode `0x78` em `0x800553d0` com `cat = arg + 5`). A ferramenta
marca `banco_externo` e **não** publica WAV para eles: o índice de tom vale no array de tons do
**outro** banco, que não é este arquivo — inventar amostra aqui seria tocar som errado.

### 13.5 Quantas salas definem cada id que o port usa

O silêncio agora é o silêncio do original: quando o descritor é `0xffffffff`, `0x80074770`
descarta, e `Sfx.se_de_sala()` devolve `false` sem reclamar.

| ação do `Sfx` | `cat`/`id` | call site | salas que definem | com amostra real |
|---|---|---|---:|---:|
| `porta_trancada()` | 2/22 | `0x80050e10` `0x80050ed8` `0x80050f14` | 34 | **33** |
| `porta_destrancar()` | 2/37 | `0x80050e74` | 25 | **24** |
| `porta_emperrada()` | 2/38 | `0x80050dd8` | 10 | **9** |
| `porta_trancada(knock)` / `porta_destrancar(knock)` | 2/5 · 2/4 | `0x80050ec8` · `0x80050e64` | — | — |
| `bau_abrir()` | 2/20 | `0x80051578` | 20 | **20** |
| `bau_mover()` | 2/21 | 4 sítios em `0x800646f0` | 19 | **19** |
| `subir()` | 2/0 | `0x8003b224` | 21 | **9** |
| `subir_impacto()` | 2/44 | `0x8003b3e8` | 5 | **5** |
| `mapa_navegar()` | 2/43 | `0x8006f790` | 2 | 2 |
| `se_de_inimigo_na_sala(42)` | 2/42 | `0x8001db0c` | 14 | 14 |
| `se_de_inimigo_na_sala(14/30)` | 2/14 · 2/30 | `0x8001edb8` | 10 · 167 | 10 · 167 |
| `se_de_sala(19)` / `(2)` / `(40)` / `(46)` — **NÃO IDENTIFICADOS** | 2/19 · 2/2 · 2/40 · 2/46 | `0x80021cdc` `0x80036934` · `0x80036b8c` · `0x800517d0` · `0x80024f04` `0x80025038` `0x800250f0` | 36 · 75 · 9 · 13 | idem |
| `ricochete(base, v)` | 2/`base+a0` | `0x80077b50` | bases `{0x17, 0x1a, 0x2d}` | — |
| `se_do_script(idx)` | 2/`byte do stream` | `0x80030010` | qualquer id | — |
| `se_de_objeto(idx, alt)` | 2/`u16@obj+0x22` | `0x8001c838` `0x8001c864` | qualquer id | — |

A diferença entre as duas últimas colunas são os **56 descritores que apontam o VAG mudo** —
placeholders silenciosos do dado original (o motor toca, o waveform é silêncio). O `subir` é o
caso extremo: 21 salas definem o id 0 e 12 delas apontam o mudo.

### 13.6 `Key_Id` não é só o id da chave — o bit 0x80 é o "trancada"

Achado ao reproduzir o produtor de porta `0x80050d28` (o SCE 1 da jump-table `0x8009e0bc`), que
é quem roda quando o personagem USA uma porta:

```
0x80050d74  lbu  $a1, 0xf($s1)          ; Key_Id  (SCE_DOOR_AOT_SET, descriptor+0x0f)
0x80050d7c  andi $v0, $a1, 0x80
0x80050d80  beqz $v0, 0x80050f3c        ; bit 0x80 APAGADO -> porta LIVRE, nenhum SE
0x80050dac  jal  0x80078930($a0 = gs+0x7994, $a1 = Key_Id & 0x3f)
0x80050db4  bnez $v0, 0x80050f3c        ; flag ja marcada -> ja destrancada, nenhum SE
0x80050dbc  lbu  $s0, 0x10($s1)         ; Key_Type
            == 0xfe -> SE 2/38 (0x80050dd8) + mensagem 0x11
            == 0xff -> SE 2/22 (0x80050e10) + mensagem 0x12
0x80050e28  jal  0x8006cc8c($a0 = Key_Type)   ; procura a CHAVE no inventario; < 0 = nao tem
   TEM:    mensagem 5; $a0 = (u8@desc+0x0e ? 0x204 : 0x225)  -> SE (0x80050e74)
           instala 0x80050fe0 em gs+0x75dc e MARCA a flag (0x800788dc)
   NAO:    $a0 = (u8@desc+0x0e ? 0x205 : 0x216)              -> SE (0x80050ed8 / 0x80050f14)
```

Logo, em `descriptor+0x0f`: **bit 7 = "esta porta é trancada"** e **bits 0..5 = índice da flag**
de "já destrancada" (o mesmo par `0x80078930` testa / `0x800788dc` marca, sobre `gs+0x7994`).
Quem é a chave é o `Key_Type` (`+0x10`). E o `Knock_Type` (`+0x0e`, ≠ 0 em 4 das 453 portas)
troca o par de ids: **4/5** em vez de **37/22**.

O port reproduz a árvore inteira em `Sfx.porta_usada(sala, aot, tem_chave, ja_destrancada)`,
que toca o SE e devolve `LIVRE / DESTRANCOU / TRANCADA / EMPERRADA / NUNCA_ABRE`. O `Sfx` não
guarda estado de porta (isso é do jogo) — daí os dois booleanos.

### 13.7 Quem seleciona o banco da sala no port

`Sfx.definir_banco_sala("R101")`. O gancho está em **`Audio.tocar_bgm_da_sala()`**
(`Audio.banco_de_sfx_da_sala`), que é o que a troca de sala já chama: no original o room-loader
`0x800493ec` carrega o banco de personagem (`cat 0`, `0x800495d0`) e o da sala no mesmo caminho,
então casar os dois no port é fiel e não exige gancho novo em `world.gd`.

### 13.8 O que ainda precisa de gancho fora do território de áudio

Os 26 pedidos têm de-para e API; **o gatilho de 3 deles vive em arquivo que não é do áudio**:

| pedido | onde o gancho falta | chamada exata |
|---|---|---|
| porta trancada / destrancar / emperrada | `port/room/world.gd`, em `atravessar()` antes de `carregar(destino)` | `var r := sfx.porta_usada(de, porta.id, tem_a_chave, ja_destrancada)`; se `r != Sfx.Porta.LIVRE` e `r != Sfx.Porta.DESTRANCOU`, **não** atravessa (as mensagens são `0x11`/`0x12`) |
| subir / impacto | `port/actors/player.gd:603` (o `pass` do `if subir.sfx_pendente != 0`) | `sfx.subir()` se `subir.sfx_pendente == SubirObjeto.SFX_INICIO`, senão `sfx.subir_impacto()` |
| SE por script (opcodes `0xEA..0xFE`) | `port/script_vm/vm.gd` | `sfx.se_do_script(byte_do_stream)` |
| ricochete de bala | `port/actors/player.gd` (colisão de projétil) | `sfx.ricochete(base)` — a base é do dado, não do `Sfx` |
| baú | `port/present/menu_bau.gd` | `sfx.bau_abrir()` ao abrir a tela · `sfx.bau_mover()` na transferência |

### 13.9 Resíduo honesto desta rodada

* **Quem registra o banco da sala em RAM não foi localizado.** `0x8007836c` (o registrador de
  banco) só é chamado 5 vezes, e a única com `cat 2` é `0x8007935c`, que passa o endereço FIXO
  `0x80101000` depois de carregar os fileids `0x127`/`0x128` (= `R000.SND` / `R_000.VB`). Ou
  seja: o **default** `R000` está localizado; **como o banco embutido no `.ARD` chega àquele
  buffer não foi achado no estático**. Não afeta o layout (provado pela aritmética de
  `0x8007836c` + as medidas em 169/169), mas é pergunta em aberto.
* **Qual `base` de `0x800776b0` vale em qual superfície** (ricochete) segue NÃO MEDIDO — o port
  exige a base de quem chama.
* **`cat 3` (banco do INIMIGO) continua sem arquivo localizado.** O `N` dele é 32
  (`0x800a0fe4[3]`), o que é dado novo, mas não diz de onde vem.
* **O som de PASSO continua NÃO PROVADO** (§11.2). O que esta rodada acrescenta é que agora dá
  para procurá-lo **no dado**: os ids 29/30/31 aparecem em 167 das 169 salas e os 26/27/28 em
  135 — cheiro de ambiente por sala, não de passada, mas é a primeira vez que a pergunta pode
  ser feita ao banco em vez de ao código.
* **`ARD.md §2` segue com o rótulo errado** do sub-bloco 9 (`mask_extra`). A correção está
  registrada aqui e no `_meta.CORRECOES` do `re3_se.json`; o arquivo não foi editado porque
  está sendo mexido em outra frente.

---

## 14. Rodada de 2026-08-08 (4ª) — **clique seco e recarga**: o id do mecanismo da arma É extraível

> O §12.1 registrou um achado negativo: *"o de-para arma → nibble **não é extraível do
> estático**"*, porque o id do som de mecanismo sai de `u16 @ *(player+0xe4)` e **não existe
> nenhum `sw` para `+0xe4`** no `.text`. A primeira metade está certa; a conclusão estava
> **errada**.
>
> Ferramenta: `python tools/exe_audio.py --armas`. Dado versionado:
> `re3_se.json.eventos_arma` (58 eventos nas 21 armas).

### 14.1 `player+0xe4` não guarda "props da arma" — é o CURSOR DA ANIMAÇÃO

Quem escreve `+0xe4` são **4 sítios**, todos no avançador de animação:

```
0x8001ae04 / 0x8001ae20   sw $v1, 0xe4($a0)     ; caminha a lista pelo bit 0x100 de cada u16
0x80026ca8 / 0x80026cc0   sw $s0, 0xe4($s1)     ; dentro de 0x80026be8
```

`0x80026be8` é exatamente a rotina que **todos** os subestados da arma chamam, com
`a1 = gs+0x2618` e `a2 = gs+0x2614` — que são o **banco 2 do `.PLW` da arma equipada**
(`recuo_tiro.md §2`). E `0x8001adc0` mostra o formato: uma lista de `u16` em que o **bit
`0x100`** marca continuação, isto é a **frame-list do EDD** (`pld2gltf.parse_edd`: "2 bytes por
frame, pose no byte baixo + flags no alto").

Logo o trecho que o §12.1 chamava de "props em RAM" é, na verdade, **o quadro corrente da
animação**:

```
0x8003f5b0  lw   $v0, 0xe4($s0)      ; cursor da frame-list
0x8003f5b8  lhu  $v0, ($v0)          ; o u16 daquele QUADRO
0x8003f5c0  andi $v0, $v0, 0xf000    ; nibble alto = evento de som (0 = quadro mudo)
0x8003f5d0  srl  $v0, $v0, 0xc
0x8003f5d4  addiu $v0, $v0, -1       ; id = nibble - 1
0x8003f5d8  or   $a0, $v0, 0x10100   ; cat 1
0x8003f5e8  jal  0x800746c0
```

**É um evento de som por quadro de animação** — exatamente a forma que a §11.2 apontou como
"pista mais forte" para o som de passo. E, porque a frame-list é dado do `.PLW`, **o id é
extraível do disco**.

### 14.2 Prova cruzada: 31/31

`tools/exe_audio.py --armas` lê o banco 2 (o de 9 ossos, `plw.md §9.4`) de cada
`PLD/PL00W{w:02X}.PLW`, varre a frame-list de cada sequência e emite `(seq, quadro, id)`.

**Todos os 31 ids de evento das 20 armas reais estão definidos no `A_{w}.VH` daquela arma.**
O único "furo" é `w = 0` (desarmado), que não tem `A_00` no disco. Dois casos que fecham o
argumento:

* **`w = 1` (a FACA)** usa **só o id 7** — e `A_01` é o único banco `A_` que define
  exatamente `{6,7,8,9,10}`. É a mesma peça que provou o estouro em `cat 1 / id 0` (§11.1),
  agora usada na direção oposta.
* **`w = 2` (a pistola)** usa os ids **3** e **5**, e `A_02` define `{0..5}`.

### 14.3 A tabela (58 eventos)

| `w` | banco | sequência/quadro → `cat 1 / id` |
|---:|---|---|
| 0 | — | seq7 f7→3 · f23→5 *(sem `A_00` no disco)* |
| 1 | `A_01` | seq1 f6→7 · seq3 f6→7 · seq5 f6→7 **(a facada)** |
| 2 | `A_02` | **seq7 f7→3 · f23→5 (RECARGA da pistola)** |
| 3 | `A_03` | seq7 f7→3 · f23→5 |
| 4 | `A_04` | seq1 f21→4 · seq3 f22→4 · seq5 f21→4 · seq7 f28→3 |
| 5 | `A_05` | seq7 f12→3 · f28→5 |
| 6..9 | `A_06`..`A_09` | seq1 f14→3 f25→4 · seq3 f13→3 f26→4 · seq5 f13→3 f27→4 (**bombeamento**) |
| 10, 11, 12, 20 | — | **nenhum** evento de quadro |
| 13 | `A_0D` | seq7 f1→3 · f8→5 |
| 14 | `A_0E` | seq7 f5→3 · f20→5 |
| 15 | `A_0F` | **seq10** f5→3 · f22→5 — o banco 2 dela tem 11 seqs; a recarga **não** é a seq 7 |
| 16 | `A_10` | seq1 f10→4 · seq3 f9→4 · seq5 f9→4 · seq7 f18→3 f28→3 |
| 17, 18 | `A_11`, `A_12` | seq7 f7→3 · f23→5 |
| 19 | `A_13` | seq1 f21→4 · seq3 f20→4 · seq5 f21→4 · seq7 f28→3 |

Rótulos de sequência **medidos**: **7 = RECARGA** (`0x8003f554` grava
`player+0xc8 = 0x00070007` no subestado 4, e `recuo_tiro.md §linha 110` já media 32 quadros =
`mira07`) e **1/3/5 = as três variantes de FOGO**. O resto do banco 2 **não tem rótulo medido**.

### 14.4 CLIQUE SECO = `cat 1 / id 1` (o ramo "sem bala")

Os **4** sítios de `cat 1 / id 1` do EXE são o MESMO idioma, em 4 subestados de arma —
`0x8003f190` (sub 1 = mira/hold, `0x8003ef08`), `0x8003fd90` (sub 8 = mira de corpo inteiro,
`0x8003fb78`), `0x8004029c` (`0x8003ffd8`) e `0x8004070c` (`0x800402f4`):

```
if (*(gs+0x2108) & 0x40) {                        ; pedido de RECARREGAR
    if (0x8006cf0c(0) == -1)  SE cat 1 / id 1     ; a munição NÃO está no inventário
    else                      player+6 = 4 (ou 10)  ; TEM -> subestado de RECARGA
}
```

`0x8006cf0c(a0 = 0)` é a **consulta** de munição (`exe_items.md §144` já a tinha como
"consolidar munição"): com `a0 = 0` ela não consolida nada — devolve **`0`** quando
`0x8006cc8c` **acha** o item de munição no inventário (sai pelo `beqz` de `0x8006cf84`) e
**`-1`** quando não acha (`0x8006cf7c`). Logo o SE sai **só** no ramo sem bala.

Sanidade: os únicos dois bancos de arma que **não** definem o id 1 são `A_01` (a FACA, que não
recarrega) e `A_0B` (que também não tem evento de quadro nenhum).

Nome `arma_vazia` / "clique seco" é **DECLARADO**; o ramo é **MEDIDO**.

### 14.5 O que foi ligado no port

| ação do `Sfx` | de onde sai o id | onde o gatilho precisa entrar |
|---|---|---|
| `arma_vazia()` | `cat 1 / id 1` fixo, do banco `A_{w}` | `player.gd`: onde o port já sabe `municao_vazia`, no momento em que o jogador pede tiro/recarga sem bala |
| `recarregar(quadro = -1)` | evento de quadro da **seq de recarga** (7, ou 10 na `w = 15`) | `player.gd`: no subestado de recarga, a cada quadro — `sfx.recarregar(quadro_da_anim)`. Com `quadro = -1` toca o primeiro evento (aproximação para quem ainda não anima quadro a quadro) |
| `arma_evento(seq, quadro)` | o evento exato daquele quadro | `player.gd`: uma linha no avanço de animação da arma — é o que o motor faz (`0x80026be8` → `0x8003f5e8`) |
| `eventos_da_arma(seq)` | consulta | para o gancho saber em quais quadros há som |

`arma_mecanismo(idx)` continua existindo (pedido cru por id), mas **não reclama mais** de "id
não medido": o id agora tem fonte.

### 14.6 Resíduo honesto desta rodada

* **A `w = 15` tem a recarga na seq 10, não na 7** — o banco 2 dela declara 11 sequências. O
  `Sfx.seq_de_recarga()` cai na maior sequência com evento quando a 7 não tem, o que é
  **DECLARADO**. Qual arma é `w = 15` não está medido (o de-para **item → `w`** segue aberto,
  `tools/exe_aim_shoot.py`).
* **4 armas (`w` 10, 11, 12 e 20) não têm evento de som em quadro nenhum.** Elas têm banco
  `A_` com ids (ex.: `A_0B` define `{0, 2, 18, 19}`), então o som delas vem por outro caminho —
  provavelmente os sítios `cat 1 / ids 18/19` de `0x80040900`, que seguem **NÃO IDENTIFICADOS**
  (§12.6).
* **Os rótulos das outras sequências do banco 2** (0, 2, 4, 6, 8...) não foram medidos; só
  7 = recarga e 1/3/5 = fogo.
* **O bit `0x40` de `gs+0x2108`** é tratado como "pedido de recarregar" porque é o gatilho dos
  4 sítios e o ramo alternativo entra no subestado de recarga. **Qual botão físico é** não foi
  medido (`gs+0x2104` é o pad; `+0x2108` é o registrador vizinho).
