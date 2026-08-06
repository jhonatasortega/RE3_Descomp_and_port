# Formato Rofs (`Rofs*.dat`) — RE3 PC classico

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `rofs`)
> - **Formato:** container empacotado da versão PC clássica (índice de 2 níveis + cripto XOR/LCG + LZ opcional)
> - **Extensão/origem:** `Rofs1.dat`..`Rofs15.dat` (instalação GOG/SourceNext, somente leitura)
> - **Ferramenta:** [`tools/rofs_extract.py`](../../tools/rofs_extract.py)
> - **Decompilado:** **100%**
> - **Feito:** contêiner, índice, descripto (LCG) e LZ revertidos; **vozes EN** (`Rofs14` = `DATA_A/VOICE`, 441 WAV) extraídas.
> - **Falta:** nada no formato. Uso downstream (ligar as vozes no protótipo) fica no [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md).

> Arquivos empacotados da versao PC classica de Resident Evil 3 (Eidos/Capcom 2000,
> reempacotado pela GOG/SourceNext). Ha `Rofs1.dat` ate `Rofs15.dat` na raiz do jogo.
> Cada `.dat` espelha **uma subarvore** do disco (ex.: `DATA/DOOR`, `DATA_A/VOICE`).
> Referencia de engenharia reversa: **reevengi-tools** (`rofs.c`, P. Mandin, GPLv2) —
> confirma bit-a-bit o que foi reconstruido aqui.

Ferramenta do projeto: [`tools/rofs_extract.py`](../../tools/rofs_extract.py).

---

## 1. Container

Todos os inteiros sao **little-endian**.

### 1.1 Cabecalho

| Off | Tipo | Campo | Observacao |
|----:|------|-------|-----------|
| 0x00 | u8[21] | cabecalho cru | 5 x u32 + 1 byte (constantes `03 00 00 00 01 00 00 00 04 00 00 00 00 01 01 00 00 04 00 00 00`) |
| 0x15 | asciiz | dir nivel 1 | ex.: `DATA`, `DATA_A` |
| +    | u32 | offset do indice | **em unidades de 8 bytes** → `byte = offset*8` |
| +    | u32 | length | tamanho do indice |
| +    | asciiz | dir nivel 2 | ex.: `VOICE`, `DOOR`, `PLD` |

O resto do bloco de 4096 bytes ate o indice e preenchido com zeros.

### 1.2 Indice de arquivos

Em `offset_dir2 * 8`:

| Tipo | Campo |
|------|-------|
| u32 | `num_files` |

Seguido de `num_files` entradas:

| Tipo | Campo | Observacao |
|------|-------|-----------|
| u32 | `offset` | **em unidades de 8 bytes** → `byte = offset*8` |
| u32 | `length` | tamanho bruto no container (informativo) |
| asciiz | `name` | nome 8.3 em MAIUSCULO (ex.: `M101A010.WAV`) |

As entradas do indice tem tamanho variavel (o nome termina em `\0`).

---

## 2. Arquivo (criptografado + opcionalmente compactado)

Cada arquivo apontado pelo indice **nao** e texto claro: comeca por um cabecalho de
cripto, seguido das chaves/tamanhos por bloco, seguido dos blocos criptografados.

### 2.1 Cabecalho de cripto (16 bytes)

| Off | Tipo | Campo | Observacao |
|----:|------|-------|-----------|
| 0x00 | u16 | `data_offset` | do inicio deste cabecalho ate os dados criptografados |
| 0x02 | u16 | `num_blocks` | numero de blocos (= numero de chaves) |
| 0x04 | u32 | `dec_length` | tamanho final descriptografado/descompactado |
| 0x08 | u8[8] | `ident` | `"NotComp"` ou `"Hi_Comp"`, **XOR `ident[7]`** |

Decodificar `ident`: `plain[i] = ident[i] ^ ident[7]` (o proprio `ident[7]` e a chave XOR
de 1 byte; vira `\0`). `"NotComp"` = so criptografado; `"Hi_Comp"` = criptografado **e**
compactado (LZ).

### 2.2 Tabelas por bloco

Logo apos os 16 bytes:

| Tipo | Campo |
|------|-------|
| u32[`num_blocks`] | `keys`   — chave de descriptografia de cada bloco |
| u32[`num_blocks`] | `lens`   — tamanho (criptografado) de cada bloco |

Os dados criptografados comecam em `header + data_offset` (normalmente logo apos as
tabelas). `sum(lens)` = tamanho bruto dos dados; para `NotComp`, `sum(lens) == dec_length`.

### 2.3 Descriptografia (XOR com keystream LCG)

Cada bloco e descriptografado com sua `key` via um LCG de 32 bits:

```
next_key(key):
    key = (key * 0x5d588b65 + 0x8000000b) & 0xffffffff
    return (key >> 24) & 0xff, key      # byte de saida, novo estado

decrypt(buf, key):
    xor = next_key();  idx = next_key() % 0x3f;  run = 0
    para cada byte b em buf:
        se run > base_array[idx]:        # troca de chave XOR
            idx = next_key() % 0x3f;  xor = next_key();  run = 0
        b ^= xor;  run += 1
```

`base_array[64]` e uma tabela de constantes u16 (ver `tools/rofs_extract.py`).
O comprimento de cada "run" com a mesma chave XOR e dado por `base_array[idx]`.

### 2.4 Descompactacao (`Hi_Comp`)

LZ simples com janela deslizante de 4096 bytes (`tmp4k`), inicializada com
`tmp[i*16 + j] = i`. O fluxo e lido bit a bit; cada token e:
- **literal** (bit de controle 0): copia 1 byte;
- **match** (bit 1): `length = (v2 & 0x0f) + 2`, `start = ((v2 >> 4) & 0xfff) | ((v & 0xff) << 4)`,
  copia `length` bytes da janela. Ver `depack_block()` no extrator.

O resultado final e um **WAV RIFF padrao**.

---

## 3. Onde estao as vozes

- **`Rofs14.dat`** contem `DATA_A/VOICE` com **441** arquivos `M*.WAV` (nomes de cena:
  `M101A010.WAV`, `M107B020.WAV`, `M11A_010.WAV`, `S001A130.WAV`, ...).
- Formato do audio apos descriptografar: **RIFF WAV, MS-ADPCM (WAVE_FORMAT_ADPCM 0x0002),
  4 bits, 22050 Hz**, majoritariamente **mono** (alguns clipes sao estereo).
- Os mesmos 441 nomes correspondem 1:1 ao override pt-BR solto em `DATA_A/VOICE/*.wav`
  (que a engine le direto do disco, sem passar pelo Rofs — por isso o mod pt-BR funciona
  colocando WAVs soltos ali).

Os outros `Rofs*.dat` seguem o mesmo container (ex.: `Rofs1=DATA/DOOR`, `Rofs2=DATA_A/ETC2`,
`Rofs6=DATA_A/PLD`).

---

## 4. Uso

```bash
# listar
python tools/rofs_extract.py "<jogo>/Rofs14.dat" --list

# extrair todos os arquivos (ja descriptografados/descompactados -> WAV)
python tools/rofs_extract.py "<jogo>/Rofs14.dat" <saida>

# converter as vozes para OGG (espelhando os nomes pt-BR, minusculo):
#   <saida>/M101A010.WAV  ->  godot/assets/VOICE/en/m101a010.ogg
ffmpeg -i M101A010.WAV -c:a libvorbis -q:a 5 m101a010.ogg
```
