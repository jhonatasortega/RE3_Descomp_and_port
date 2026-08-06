# De-para HD da UI (ETC / itens / memos / mapa)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `hd_ui`)
> - **Formato:** de-para entre a UI SD (TIM do PS1) e o HD do Seamless HD Project, nomeado por **CRC-32(BGRA do bloco blitado)**
> - **Extensão/origem:** `hires/<cat>/<HASH>.webp` (GOG, somente leitura) ↔ `godot/assets/ETC/*.png`
> - **Ferramenta:** [`tools/etc_hd_match.py`](../../tools/etc_hd_match.py), `hd_masks.py` → `godot/data/hd_ui_map.json`
> - **Decompilado:** **100%** (`hd_ui`); alimenta o inventário (unidade `inventory`, 85%)
> - **Feito:** RE do algoritmo de hash (CRC-32 zlib no `bio3hd.asi`); casamento por NCC; ícones/frames HD migrados e usados no inventário fiel.
> - **Falta:** de-para 100% exato exige habilitar o dump do plugin e jogar (§2); tiling 1:N de telas cheias. Backgrounds usam o método de [hd_mapping.md](hd_mapping.md).

> Como casar as imagens de UI do jogo (`godot/assets/ETC/*.png`, decodificadas dos TIM do PS1)
> com as versoes HD do **Seamless HD Project** em `hires/<cat>/<HASH>.webp` (GOG, SOMENTE LEITURA).
> Complementa [`hd_mapping.md`](hd_mapping.md) (backgrounds, que usam o cache `ROOMxxxx.dat`).
> **Para a UI NAO existe cache** — o hash e calculado em runtime.

## 1. O algoritmo de hash (engenharia reversa do `bio3hd.asi`)

O Classic REbirth (plugin `bio3hd.asi`, ~17 KB, x86) carrega o HD por hash. Reversado:

- **Funcao de hash:** VA `0x10002280`. E um **CRC-32 padrao (zlib)**:
  polinomio refletido `0xEDB88320`, `init=0xFFFFFFFF`, `xorout=0xFFFFFFFF`,
  tabela de 256 entradas em VA `0x10001d60` (a entrada 128 = `0xEDB88320`, confirmada no binario).
- **Entrada do hash:** o buffer **BGRA (4 bytes/pixel)** do **sub-retangulo que o engine vai blitar**.
  O handler (VA `0x10002870`) recebe `(ptr, x, y, stride, w, h, ...)`, calcula
  `ptr + (y*stride + x)*4` e faz CRC de `w*4` bytes por linha, avancando `stride*4` entre linhas.
- **Lookup:** `sprintf("hires\\%s\\%08X.webp", categoria, hash)`. Categorias (tabela em `0x1000116c`):
  `memo, misc, effect, effect0, skin, door, item, info, skin0, slide` (+ `bgd`, `mask0/1` para cenario).
- **Dump:** o mesmo plugin sabe **gravar** `dump\\<cat>\\<HASH>.webp` (buffer BGRA, `WebPEncodeLosslessBGRA`).

Ou seja: **nome do `.webp` = CRC-32(BGRA do bloco blitado)**. Isso vale tanto para backgrounds
(cujo hash tambem aparece no cache) quanto para a UI.

## 2. Por que o hash NAO e reproduzivel estaticamente aqui

Tentar reproduzir os hashes a partir dos nossos TIM **falhou (0 acertos em ~4.900 hashes)**, por 3 motivos:

1. **A unidade de hash e o BLOCO blitado, nao o TIM inteiro.** Telas cheias (320x240) e paginas de
   VRAM (256x256) sao desenhadas em **varios** blits -> **varios** `.webp` (tiling 1:N). Sem as
   coordenadas de blit do engine, nao da pra recompor o bloco exato que foi hasheado.
2. **Idioma batido no bitmap.** Os assets do Seamless HD foram gerados de um **PC russo**
   (o RADAR HD tem `УГРОЗА/ОПАСНО/ПОИСК`). Onde ha texto no bitmap, os pixels divergem do nosso
   TIM (JP/EN) -> CRC diferente. (O pack tambem traz variantes de outros idiomas, ver §4.)
3. **O HD e REDESENHADO, nao upscale nearest 4x.** Downscale de um `.webp` HD **nao** recupera o
   buffer SD, entao nem da pra calibrar o formato BGRA por engenharia reversa dos proprios `.webp`.

### Caminho para o de-para 100% exato (recomendado)
**Habilitar o dump do plugin e jogar.** Em `config.ini [DLL]` ha `DebugEnable=0`; com o dump ligado
o `bio3hd.asi` grava `dump/<cat>/<HASH>.webp` = **o SD original ja nomeado pelo hash**. Dai:
`dump<->hires` casa pelo **nome** (hash exato) e `dump<->PS1` casa por **conteudo** (mesma imagem SD,
sem o problema de idioma/redesenho). Isso resolve tudo, inclusive itens/memos/mapa. Precisa de escrita
na pasta do jogo (a instalacao GOG e somente-leitura aqui) e de rodar o jogo.

## 3. Fallback que funcionou: content-match por NCC (com filtro de aspecto)

Corrigido o matcher ingenuo (`etc_hd_match.py`, que fazia squash 64x64 e achava so 2):
- **thumbnail preservando aspecto** + **pre-filtro por razao de aspecto** (|Aspecto_HD - Aspecto_PS1| < 6%),
  o que e um discriminador forte (o HD e 4x exato do SD),
- **alpha do HD composto sobre preto** (varios `.webp` tem transparencia real, ex.: RADAR),
- NCC em grade 96x96.

Funciona bem para assets desenhados em **um unico blit** (paginas/atlas de VRAM). Falha (NCC baixo)
para telas cheias tiladas — coerente com §2.1.

## 4. Pares casados e validados (Read visual)

| PS1 (ETC) | HD `.webp` | Metodo | Validacao |
|---|---|---|---|
| `RADAR` | `misc/74038984` (704x256) | conhecido | mesmo circulo/mira; **texto RUSSO** |
| `RADAR` (PT) | `misc/EC1A694B` (704x256) | variante de idioma | mesma geometria; **texto PORTUGUES** (CUIDADO/PERIGO/PROCURA) |
| `STMOJIU` | `misc/8AAF0EE6` | conhecido | atlas de texto de menu |
| `STMOJIJ` | `misc/869E4EB0` | NCC 0.714 | mesmo atlas (setas/EXIT/0-9%/Fine-Caution-Danger-Poison/verbos) |
| `FILEI` | `misc/12124B01` (512x1024) | NCC 0.903 | atlas de icones de arquivos; **HD em PORTUGUES** (COMO JOGAR/VAZIO) |

**Aplicados** (webp copiado para `godot/assets/ETC/`, `.png` removido): `RADAR`, `STMOJIU`,
`STMOJIJ`, `FILEI` (via convencao do `hd_copy.py`).

> Obs.: `RADAR.webp` aplicado = `74038984` (russo, conforme par conhecido). Para o remake **PT**
> o correto e `EC1A694B` (portugues) — trocar se quiser o idioma coerente com `mod_BH3_Portuguese`.

## 5. O 1:N (tiling / variantes)

Um asset de ETC pode corresponder a **varios** `.webp`, por 3 razoes distintas:
- **IDIOMA** (texto batido no bitmap): ex. RADAR = `74038984` (ru) e `EC1A694B` (pt); cada idioma
  tem hash proprio. O jogo carrega o que casa com sua config de lingua.
- **PALETA (CLUT)**: um TIM pode ter varias CLUTs (ex.: `RADAR.TIM` tem 2 — verde e vermelho, para
  estados do jogo). Cada render de paleta e um bitmap distinto -> hash/`.webp` distinto.
- **BLOCOS DE VRAM (tiles)**: telas cheias / paginas 256x256 sao desenhadas em varios blits. Os
  `.webp` HD sao ~4x do bloco SD (ex.: `1024x1024`=256x256, `512x1024`=128x256, `1024x160`=256x40).
  Montar a imagem completa exige **stitch** dos tiles na grade — o layout depende do engine (ver §2).

## 6. Arquivos gerados
- `godot/data/hd_ui_map.json` — de-para (confirmados + variantes + candidatos + notas do hash/tiling).
- Assets aplicados em `godot/assets/ETC/*.webp`.

## 7. Licenca
Assets do **Seamless HD Project** (fas) sobre arte da **Capcom**. Uso pessoal/local ok; distribuicao
exige aval dos autores + Capcom. Ver [`hd_seamless.md`](hd_seamless.md).
