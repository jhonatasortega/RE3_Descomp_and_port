# Formato `.BSS` — Backgrounds pré-renderizados (RE3 PS1)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `bss`)
> - **Formato:** contêiner de backgrounds 320×240 comprimidos em MDEC / STR "BS v3" (DCT estilo MPEG-1, só I-frames)
> - **Extensão/origem:** `CD_DATA/STAGE1..7/*.BSS` (169 arquivos, 2109 backgrounds)
> - **Ferramenta:** [`tools/bss2png.py`](../../tools/bss2png.py) → `godot/assets/STAGE{n}/<nome>_<idx>.png`
> - **Decompilado:** **100%** — formato totalmente revertido e verificado visualmente.
> - **Feito:** decode do bitstream VLC + emulação MDEC (IDCT/dequant/YCbCr→RGB); lote de 2109 PNGs.
> - **Falta:** nada no formato. No protótipo Godot só R100 está ligado (integração é decisão do [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md)). As **máscaras de profundidade** ficam no RDT — ver [ARD.md](ARD.md), não aqui.

Os `.BSS` guardam os **cenários pré-renderizados 320×240** de cada sala — um por
ângulo de câmera. São o "cenário" que, na v2 3D, será substituído por ambiente 3D real.

- **169 arquivos** (`STAGE1..7`), **2109 backgrounds** no total.
- Cada arquivo é um **contêiner**: N backgrounds, um por "slot" de **64 KiB** (`0x10000`).
- Tamanho do arquivo = `N × 64 KiB`. O menor tem 64 KiB (1 background); os maiores chegam a
  dezenas de slots (ex.: `R101.BSS` tem 32).
- Cada background está **comprimido no formato MDEC / STR "BS v3"** da PlayStation
  (DCT estilo MPEG-1, só I-frames). **Não é RLE/LZ** como se supunha inicialmente.

## 1. Estrutura do contêiner

```
Arquivo .BSS = [ slot 0 ][ slot 1 ] ... [ slot N-1 ]     cada slot = 0x10000 (64 KiB)

Slot = [ frame MDEC comprimido ][ padding 0x00 até 64 KiB ]
```

O frame comprimido costuma ocupar só ~20–50 KiB do slot; o resto é preenchido com zeros
(o slot fixo de 64 KiB serve para o jogo carregar cada background por seek direto no CD).

Exemplo real — `STAGE1/R10C.BSS` (64 KiB, 1 slot):
- dados não-nulos: offset `0x000000` a `0x00539E` (~21 KiB), depois só `0x00`.

## 2. Cabeçalho do slot (8 bytes)

É **idêntico ao cabeçalho de um frame de vídeo STR "demultiplexado"** da PlayStation.
Todos os campos são little-endian:

| Offset | Tipo | Campo | Valor observado |
|---|---|---|---|
| `+0` | u16 | Nº de blocos de 32 bits p/ os MDEC codes (tam. comprimido) | varia (ex. `0x3EC0`) |
| `+2` | u16 | **Magic `0x3800`** (constante do formato STR) | `0x3800` em **todos** os 2109 slots |
| `+4` | u16 | Escala de quantização (`qscale`) do frame | `2` (1509×), `1` (391×), `3` (204×), `4` (5×) |
| `+6` | u16 | Versão do bitstream | **`3`** em **todos** os slots (RE3 usa BS v3) |

Dump de exemplo (`R10C.BSS`, offset 0):
```
C0 3E | 00 38 | 02 00 | 03 00   →  codes=0x3EC0, magic=0x3800, qscale=2, versão=3
```

O bitstream comprimido começa no **offset +8** do slot.

## 3. O que é MDEC / BS v3

O MDEC ("Macroblock Decoder") é o chip da PS1 que decodifica imagens estilo JPEG/MPEG-1.
Os backgrounds do RE2/RE3 são frames I (intra) alimentados nesse chip. Duas etapas:

1. **Descompressão VLC (Huffman)** do bitstream → sequência de coeficientes DCT (run/level).
2. **Emulação do MDEC**: para cada bloco 8×8 → un-zig-zag → dequantização → IDCT →
   junção dos 6 blocos do macrobloco (4:2:0) → conversão YCbCr → RGB.

Diferença **v2 vs v3** (RE3 é **v3**):
- **v2**: coeficiente DC gravado direto, 10 bits com sinal.
- **v3**: coeficiente DC **diferencial e comprimido com Huffman** (como o MPEG-1), com
  precisão de 8 bits (por isso o DC é multiplicado por 4 na decodificação).

> É o mesmo motivo pelo qual `reevengi-tools` exige a flag `-re3` (o padrão dessa
> ferramenta é RE2). A diferença prática RE2↔RE3 é justamente a versão do bitstream.

## 4. Leitura de bits

O bitstream é lido em **palavras de 16 bits little-endian**, e dentro de cada palavra os
bits são consumidos **do mais significativo (bit 15) para o menos significativo (bit 0)**.

```
palavra = data[i] | (data[i+1] << 8)      # little-endian
bits consumidos: bit15, bit14, ..., bit0  # depois vai p/ a próxima palavra
```

## 5. Macroblocos

- Imagem 320×240 = **20 × 15 = 300 macroblocos** de 16×16 px.
- Ordem **por coluna**: começa no topo-esquerdo, desce a coluna inteira (15 macroblocos),
  vai para a próxima coluna à direita, e assim por diante.
  - `mb_col = idx // 15`, `mb_row = idx % 15`.
- Cada macrobloco = **6 blocos 8×8 nesta ordem**: `Cr, Cb, Y1, Y2, Y3, Y4`
  (⚠️ **Cr antes de Cb**). Os Y formam o quadrado 16×16 de luma:
  `Y1`=sup-esq, `Y2`=sup-dir, `Y3`=inf-esq, `Y4`=inf-dir. Cr/Cb são a croma 4:2:0
  (1 valor por bloco 2×2 de luma).

Cada bloco = 1 coeficiente DC + N coeficientes AC + código `END_OF_BLOCK`.

## 6. Coeficiente DC (v3, diferencial + Huffman)

DC relativo ao bloco anterior **do mesmo componente**: `Cr` relativo ao `Cr` anterior,
`Cb` ao `Cb` anterior, e `Y1..Y4` a uma cadeia única de luma (Y1 do macrobloco relativo ao
Y4 do macrobloco anterior). Inicia em 0 no começo do frame.

Tabela **Chroma** (Cr, Cb) — prefixo VLC → nº de bits do DC:

| Prefixo | bits DC | Prefixo | bits DC |
|---|---|---|---|
| `11111110` | 8 | `110` | 3 |
| `1111110` | 7 | `10` | 2 |
| `111110` | 6 | `01` | 1 |
| `11110` | 5 | `00` | 0 |
| `1110` | 4 | | |

Tabela **Luma** (Y1..Y4):

| Prefixo | bits DC | Prefixo | bits DC |
|---|---|---|---|
| `1111110` | 8 | `101` | 3 |
| `111110` | 7 | `01` | 2 |
| `11110` | 6 | `00` | 1 |
| `1110` | 5 | `100` | 0 |
| `110` | 4 | | |

Após o prefixo, se `bits DC == 0` o diferencial é 0. Senão lê-se 1 **bit de sinal** + `(bits-1)`
bits de magnitude:
```
sign = read(1); mag = read(bits-1)
if sign == 1: diff =  mag + 2^(bits-1)      # positivo
else:         diff =  mag - (2^bits - 1)    # negativo
diff *= 4                                    # v3: sobe precisão 8→10 bits
DC = DC_anterior + diff
```

## 7. Coeficientes AC (VLC padrão MPEG-1)

São **111 códigos** run/level (idênticos à tabela de coeficientes DCT do MPEG-1), cada um
seguido de 1 bit de sinal `s`. Exemplos:

| Código (+`s`) | zeros (run) | nível |
|---|---|---|
| `11`+s | 0 | 1 |
| `011`+s | 1 | 1 |
| `0100`+s | 0 | 2 |
| `0101`+s | 2 | 1 |
| … | … | … |

Códigos especiais (sem bit de sinal):
- **`10`** → `END_OF_BLOCK` (fim do bloco).
- **`000001`** → **escape**: seguido de 6 bits (run, sem sinal) + 10 bits (nível, com sinal).

A tabela completa das 111 entradas está embutida em `tools/bss2png.py` (`AC_VLC`),
extraída da referência jPSXdec e validada como código de prefixo livre de ambiguidade.

Montagem da lista de 64 coeficientes:
```
lista[0] = DC
i = 0
repita:
    (run, nível) = próximo código AC       # ou EOB → termina
    i += 1 + run
    lista[i] = nível
```

## 8. Reconstrução do bloco (emulação MDEC)

1. **Un-zig-zag**: `F[lin][col] = lista[ ZIGZAG[lin][col] ]` (zig-zag padrão MPEG-1/JPEG).
2. **Dequantização** com a tabela do PSX (= MPEG-1 intra, mas `[0,0] = 2` em vez de 8):
   - DC: `deq[0][0] = F[0][0] * 2`
   - AC: `deq[l][c] = 2 * F[l][c] * qscale * QUANT[l][c] / 16`
3. **IDCT 8×8** separável: `spatial = Aᵀ · deq · A`, com
   `A[k][n] = c(k)·cos((2n+1)·k·π/16)`, `c(0)=√(1/8)`, `c(k>0)=0.5`.
4. **Junção 4:2:0**: monta luma 16×16 (Y1..Y4), faz upsample 2× de Cr/Cb, aplica
   *level shift* de **+128** no Y.
5. **YCbCr → RGB** (equações do MDEC, levemente diferentes do JFIF):
   ```
   R = Y + 1.402·Cr
   G = Y - 0.3437·Cb - 0.7143·Cr
   B = Y + 1.772·Cb          (com clamp 0..255)
   ```

## 9. Uso da ferramenta

```bash
# 1 arquivo (gera 1 PNG por slot em godot/assets/STAGE{n}/):
python tools/bss2png.py extracted/ntsc-u/CD_DATA/STAGE1/R10C.BSS

# vários arquivos:
python tools/bss2png.py extracted/ntsc-u/CD_DATA/STAGE1/*.BSS

# raiz de saída customizada:
python tools/bss2png.py --out /caminho/saida arquivo.BSS
```

Saída: `godot/assets/STAGE{n}/<nome>_<idx>.png` (ex.: `R100_0.png`, `R100_1.png`, …).
Depende de **numpy** (para o IDCT vetorizado) e reutiliza `write_png` de `tim2png.py`.
Desempenho: ~0,25 s por background; o lote completo (2109) leva ~11 min.

## 10. Verificação

Decodificados e conferidos visualmente (via leitura do PNG): `R10C` (sala escura com
monitor/caixas/barril), `R100` (escritório estilo S.T.A.R.S. com arquivos/mesa),
`R413` (interior de cabana de madeira). Todas as imagens saem **coerentes e nítidas** —
cenários inequívocos do RE3. ✅

## 11. Máscaras de profundidade (fora deste arquivo)

Estes `.BSS` contêm **apenas os backgrounds** (um frame MDEC por slot, sem TIM anexado —
a varredura não achou magic TIM `10 00 00 00` dentro dos slots). As **máscaras de
prioridade/profundidade** (que fazem o personagem 3D passar atrás de objetos do cenário)
**não estão aqui** — no RE3 elas ficam nos dados de sala (`.ARD`/RDT). Documentar a máscara
é trabalho separado (ver [ARD.md](ARD.md)) e necessário para a composição correta na v2.

## 12. Referências

- **jPSXdec** — `PlayStation1_STR_format.txt` (m35/jpsxdec): especificação completa do
  bitstream STR v2/v3, tabelas VLC (DC luma/croma e os 111 códigos AC), quantização e IDCT.
- **psx-spx / nocash** — "Macroblock Decoder (MDEC)" e "CDROM File Video BS Compression
  Versions": confirma v3 = v2 + DC comprimido por Huffman.
- **reevengi-tools** (pmandin) — wiki `.BSS` e ferramenta `bss2bmp`/`bsssld2tim -re3`:
  confirma alinhamento de 64 KiB (RE2/RE3) e a diferença de algoritmo RE2 (padrão) vs RE3.

## 13. Próximos passos

- [ ] Rodar o lote completo → 2109 PNGs em `godot/assets/STAGE{n}/`.
- [ ] Mapear `R<stage><sala>` → nome/uso da sala (cruzar com `.ARD`).
- [ ] Extrair as **máscaras de profundidade** do `.ARD`/RDT e alinhar aos backgrounds.
- [ ] Avaliar backgrounds HD (Dreamcast / Seamless HD) como fonte alternativa de maior resolução.
