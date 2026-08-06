# Backgrounds HD — Seamless HD Project (SHDP) + Classic REbirth

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `hd_bg`)
> - **Formato:** assets HD (WEBP 1280×960 = 4× o PS1) do Seamless HD Project, carregados pelo Classic REbirth
> - **Extensão/origem:** `…/Resident Evil 3/hires/` (GOG, **somente leitura**)
> - **Ferramenta:** [`tools/hd_match.py`](../../tools/hd_match.py), [`hd_copy.py`](../../tools/hd_copy.py)
> - **Decompilado:** **100%** (migração HD por conteúdo/NCC estabelecida)
> - **Feito:** estrutura da pasta `hires/`, naming PC (hash/`ROOMxxxx`), estratégia de casamento HD↔sala.
> - **Falta:** integração no protótipo (só R100 ligado). O **mapa autoritativo** sala→hash está em [hd_mapping.md](hd_mapping.md); ver também [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md).

> Fonte de **upgrade visual** para o remake: backgrounds pré-renderizados do RE3 em
> alta resolução (upscale + limpeza manual pela comunidade). Servem como referência/asset
> HD para casar com as salas do PS1 (`STAGE{n}` / `.BSS`).

## 1. Origem e contexto

- **Classic REbirth** (patch por *Gemini*): wrapper que roda o RE3 clássico de PC em Windows
  moderno. Injetado via `ddraw.dll` + plugin `bio3hd.asi`. Entre outras coisas, ele
  **substitui os backgrounds** originais por versões HD externas carregadas da pasta `hires/`.
- **Seamless HD Project (SHDP)**: pacote de fãs com os backgrounds/máscaras/UI pré-renderizados
  em alta resolução. Confirmado nesta instalação pelo manifesto do mod
  (`mod_BH3_Portuguese/manifest.txt` → `Title = RESIDENT EVIL 3 SHDP - Portuguese`).

**Instalação de referência (SOMENTE LEITURA):**
`C:\Program Files (x86)\GOG Galaxy\Games\Resident Evil 3`
Nunca modificar/mover/apagar nada lá; apenas ler e **copiar para fora** (nosso projeto).

## 2. Estrutura da pasta `hires/`

Todos os assets HD ficam em `…\Resident Evil 3\hires\`. Cada subpasta espelha uma categoria
de asset do engine. Formato **quase 100% `.webp`** (WEBP), com 2 `.psd` soltos (fontes de arte).

| Subpasta   | Nº arq. | Conteúdo                                             | Resolução típica            |
|------------|--------:|------------------------------------------------------|-----------------------------|
| **`bgd`**  |   1316  | **Backgrounds de sala** (o cenário) — asset principal | **1280×960** (WEBP)         |
| **`mask0`**|    943  | **Máscaras de profundidade** (oclusão do 1º plano)    | 2048×2048 (WEBP lossless)   |
| **`mask1`**|    818  | Máscaras de profundidade (2º conjunto)                | 2048×2048 (WEBP lossless)   |
| `door`     |     64  | Animações/telas de transição de porta                 | 512×1024 e 1024×1024        |
| `map`      |     92  | Mapas do jogo                                         | 1024×1024 e 1024×864        |
| `item`     |    120  | Ícones de item / inventário                           | 160×120                     |
| `effect`   |    343  | Efeitos visuais                                       | variável                    |
| `effect0`  |     48  | Efeitos visuais (variante)                            | variável                    |
| `skin`     |    497  | UI / HUD                                              | variável                    |
| `skin0`    |    130  | UI / HUD (variante)                                   | variável                    |
| `memo`     |    280  | Documentos/arquivos lidos no jogo (files)             | variável                    |
| `slide`    |     34  | Telas de slide / ending                               | variável                    |
| `info`     |    108  | Telas de informação                                   | variável                    |
| `misc`     |    122  | Diversos (+2 `.psd` de fonte de arte)                 | variável                    |
| `cache`    |    170  | **Cache de runtime** `ROOMxxxx.dat` (gerado ao jogar) | binário                     |

> Total: ~2.535 imagens WEBP. Os backgrounds (`bgd`) são o que interessa primeiro; as
> **máscaras** (`mask0/mask1`) são igualmente valiosas — são o equivalente HD das máscaras de
> profundidade que hoje extraímos do `.RDT`/`.ARD` (ver `docs/plano.md`, Fase 2a).

### Formato/resolução dos backgrounds
- **1280×960 px** = exatamente **4× a resolução original do PS1** (320×240). Confirmado HD:
  bordas limpas, texturas detalhadas, sem *pixelation* de PS1.
- WEBP em três variantes de container: `VP8X` (extended, maioria), `VP8` (lossy) e alguns
  `VP8L` (lossless). Alguns têm canal **alpha** (RGBA) — usado para composição.
- Proporção 4:3 preservada (mesma do jogo original).

## 3. Nomenclatura do PC (naming)

Dois esquemas coexistem — **importante**, o naming do PC é **diferente** do PS1:

### (a) Backgrounds/máscaras/itens → **hash hexadecimal de 8 dígitos**
Ex.: `bgd/7D33EB30.webp`, `mask0/0042DD3F.webp`, `item/…`.
- Nome = `XXXXXXXX.webp`, onde `XXXXXXXX` é um **hash de 32 bits** (8 chars hex).
- O Classic REbirth, ao carregar um background original, calcula esse hash a partir dos
  **bytes do background original** e procura `hires/bgd/<HASH>.webp`. Ou seja, **o nome NÃO
  identifica a sala diretamente** — é um hash do conteúdo original. Sem uma tabela auxiliar,
  o hash sozinho não diz "STAGE X / sala Y / câmera Z".

### (b) Cache de sala → **`ROOM` + `S` + `RR` + `P`**
Ex.: `cache/ROOM1000.dat`, `ROOM11B0.dat`, `ROOM5240.dat`, `ROOMFFFF.dat`.
Este é o **esquema de ID de sala do engine RE** (mesmo dos arquivos `.RDT` do PC):

```
ROOM S RR P .dat
     │ │  └─ P  = player/variante (1 hex) — sempre 0 no RE3 (só Jill)
     │ └──── RR = número da sala   (2 hex)
     └────── S  = stage/estágio    (1 hex)
```

Stages observados no cache: **0,1,2,3,4,5,6** (+ `FFFF` = global/especial). Contagem de salas
por stage (aprox., não contíguas): st0≈0x00–0x25, st1≈00–1B, st2≈00–17, st3≈00–17,
st4≈00–10, st5 esparso até 24, st6≈00–1B.

> ⚠️ Os `ROOMxxxx.dat` são **cache de runtime** do Classic REbirth (datas de modificação =
> última sessão de jogo; só existem para salas já visitadas). O conteúdo é binário opaco
> (blocos de 16 bytes) e **não** lista os nomes-hash dos `bgd/` de forma trivial. Servem como
> **lista de salas existentes no PC**, não como mapa sala→background pronto.

## 4. Estratégia de mapeamento (PC HD ↔ PS1 STAGE/room/câmera)

O objetivo é, para cada background HD, saber a qual **sala do PS1 e qual câmera** ele pertence,
para injetar o HD no lugar do `.BSS` decodificado. Como os `bgd/` são nomeados por hash, há
dois caminhos:

### Método A — Casamento por conteúdo (recomendado, robusto)
Independe de quebrar o hash ou de conhecer o naming interno. Passos:
1. Decodificar cada background PS1 `.BSS` → RGB 320×240 (pipeline da Fase 1).
2. Reduzir cada HD `bgd/*.webp` de 1280×960 → 320×240 (fator 4, `LANCZOS`).
3. Comparar cada HD reduzido contra todos os `.BSS` por **perceptual hash (pHash/dHash)** e
   desempatar com **SSIM/MSE** na região central (ignorar bordas, que o SHDP às vezes
   estende/limpa). Melhor match acima de um limiar = par confirmado.
4. Gerar tabela `hash_HD → (STAGE{n}, room, câmera)`. Revisar visualmente os matches fracos.

*Prós:* não exige RE do hash nem do formato Rofs; valida a correspondência **visualmente**.
*Contras:* custo O(N×M); cuidado com salas que reusam o mesmo cenário em câmeras diferentes.

### Método B — Estrutural/autoritativo (se quisermos tabela exata)
1. Extrair os **backgrounds originais de PC** dos arquivos `Rofs*.dat` (arquivos do engine PC),
   que são indexados por sala no esquema `ROOM S RR P`.
2. Replicar o **hash do Classic REbirth** sobre cada background original de PC → obter
   `hash → (S,RR,P,câmera)` de forma exata (o mesmo hash que nomeia os `bgd/*.webp`).
3. Mapear `ROOM S RR P` (PC) → `STAGE{n}/room` (PS1). O ID de sala é essencialmente **1:1**
   entre PC e PS1 (mesmo engine); **falta confirmar apenas o offset do stage** — o cache do PC
   usa stage nibble **0–6**, enquanto o disco PS1 organiza em pastas **STAGE1–7**. Verificar se
   `stage_PC == STAGE_PS1` direto ou se há deslocamento de 1 (tarefa do agente que está
   levantando o naming do PS1).

*Prós:* tabela exata, sem comparar imagem. *Contras:* exige RE do formato `Rofs` e do algoritmo
de hash do Classic REbirth (não documentado aqui).

### Recomendação
Começar pelo **Método A** (rápido de prototipar, valida visualmente e já entrega HD utilizável
na fatia vertical da Fase 3). Migrar/complementar com o **Método B** só se precisarmos de uma
tabela 100% determinística. Em ambos, **as máscaras `mask0/mask1` seguem o mesmo esquema de
hash** e podem ser casadas pelo mesmo pipeline (útil para substituir a máscara de profundidade
por uma versão HD 2048²).

### Correspondências óbvias já observadas
- Naming de sala do PC = `ROOM` + stage(1) + room(2) + player(1); mapeia direto para
  `STAGE{n}/room{RR}` do PS1 (pendente só o offset de stage).
- HD `bgd` 1280×960 = 4× o `.BSS` 320×240 → basta reduzir 4× para comparar/alinhar (sem crop).

## 5. Amostras copiadas para o projeto

Copiadas 5 amostras (somente cópia; a instalação segue intacta) para:
`godot/assets_hd/`

| Arquivo            | Resolução | Modo | Cena (confirmada via leitura visual)                       |
|--------------------|-----------|------|------------------------------------------------------------|
| `7D33EB30.webp`    | 1280×960  | RGB  | Beco/corredor com parede rompida por raízes, luzes fluor.  |
| `43CD0B47.webp`    | 1280×960  | RGB  | Interior industrial com painéis/monitores                  |
| `15753EA5.webp`    | 1280×960  | RGBA | Corredor de metrô/instalação, portas duplas, luzes vermelhas |
| `B3CD424B.webp`    | 1280×960  | RGB  | (amostra de variedade)                                     |
| `E33FECA9.webp`    | 1280×960  | RGB  | (amostra de variedade)                                     |

Godot 4 importa WEBP nativamente; não é preciso converter para PNG (mas dá para gerar PNG com
Pillow, disponível no ambiente).

## 6. Licença / uso

- O **Seamless HD Project** e o **Classic REbirth** são trabalhos de **fãs**, não oficiais.
  Os backgrounds derivam de arte da **Capcom** (RE3 Nemesis).
- **Uso pessoal/local** (o próprio usuário, com sua cópia legítima do jogo): ok como referência
  e para o remake pessoal.
- **Distribuição** (embutir esses HD em qualquer release do nosso projeto) **exige autorização**
  dos autores do SHDP/Classic REbirth **e** da Capcom. Não redistribuir.
- Alinhado com a política do projeto (`docs/plano.md`): *"Não distribuir assets — o pipeline
  assume que o usuário final traz a própria cópia/ISO"*. Aqui, idem: o usuário traz sua própria
  instalação com o SHDP. Tratamos `hires/` como fonte **externa somente-leitura**.
