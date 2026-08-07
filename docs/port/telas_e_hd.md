# Telas de sistema no port + como casar os assets HD

Esta nota cobre **o que foi implementado no port** (tela de status/inventário e o brilho do
item) e, principalmente, **o método que resolveu o de-para dos assets HD** — que é reusável para
todas as outras telas (mapa, arquivo, título).

Fontes do recomp: [`../decomp/notes/menu_inventario.md`](../decomp/notes/menu_inventario.md)
(+ a §15, auditoria adversarial que remediu tudo do zero e corrigiu 8 erros),
[`menu_overlays.md`](../decomp/notes/menu_overlays.md), [`esp_efeitos.md`](../decomp/notes/esp_efeitos.md),
`tools/status_layout.py`, `tools/status_assets.py`.

---

## 1. Onde a tela de status vive (correção de rota)

**Não é overlay.** A crença anterior era que as telas estavam nos `CD_DATA/BIN/*.BIN`. Elas são
overlays MIPS, sim, mas o **menu de jogo não está em nenhum deles**: é uma **task do próprio EXE**
(entrada `0x8006dfdc`, contexto `0x800e01c0`). O `PC_SYS.BIN`, que parecia ser o menu, é o
**terminal de senhas** do hospital ("Umbrella Security System").

Consequências práticas: para o menu não há overlay a carregar, e a pausa é literal —
`task_suspend(0)` em `0x8006d97c` e `task_resume(0)` em `0x8006e248`, os **únicos dois sítios**
de suspend/resume do EXE. No port isso é "não chamar `mundo.tick`", e o teste confere que a
posição do personagem fica idêntica antes e depois de abrir.

## 2. O espaço de tela é 320×240

Provado por varredura das duas tabelas de retângulo: o maior `dx+w` é **312** e o maior `dy+h` é
**224**. Incompatível com 640×480. O port desenha nesse espaço e multiplica por **4** para o
quadro de 1280×960 — que é exatamente 4× também, então não há reamostragem.

## 3. A pegadinha da TPAGE (o que fez a moldura sair como blocos cinza)

O `u` de cada registro é relativo à **página de textura**, e a página muda por faixa de `ot`
(`0x8006aeb8`..`0x8006afcc`):

| `ot` | tpage | onde cai no `STMAIN0U` (8bpp, carregado em VRAM word 640) |
|---|---|---|
| 0–7 | `0x9B` | word 704 → **pixel 128** (metade direita) |
| 8–15 | `0x9A` | word 640 → pixel 0 |
| 16–23 | `0x3A` | **4bpp** — é o `STMOJIU`, não o `STMAIN0U` |
| 24–31 | `0x97` | `ITEMG.PIX` |

Duas consequências que custaram tentativa:

* a **moldura** (B0, B1, B5..B9, `ot` 3) precisa de **+128** no `u`; o **retrato** (B2, `ot` 12)
  não. Sem isso o retrato saía certo e a moldura saía como retângulos cinza lisos.
* o **cursor** (B146, `ot` 17) **não** vem do `STMAIN0U`: vem do `STMOJIU`. A prova está na CLUT
  medida — `(304,483)`, e `304` é o `DX` do bloco de CLUT do STMOJIU (o do STMAIN0U é `DX=0`).
  Desenhando do atlas errado aparecia um pedaço gigante da palavra "EQUIP" na primeira célula.

## 4. Célula vazia é um ÍCONE, não fundo de moldura

Tentei desenhar a grade com o registro B27 `(0,72,80,120,224,66)` e saiu faixas de metal.
B27..B29 **são os 10 ícones** (o `u/v` deles aponta para a área da VRAM onde o jogo sobe o ícone
de cada slot: `(640,328)` para o slot 0, `(660,328)` para o 1, …). E o "slot vazio" é o
**ícone `item_id 0` do `ITEMA.SLD`**, que não é transparente. Portanto o desenho da grade é um
laço uniforme de 10 slots, com `id = 0` quando livre.

## 5. Seleção: duas variantes de placa no dado

Cada botão/linha tem a placa em **duas tiras de 8 px** e **duas variantes**:
`v = 200/208` (normal) e `v = 184/192` (destacado). Qual é qual está provado no sítio de desenho
(`0x8006bf40`+): ele carrega o registro base e, quando `lb $v1, 0x1e($s3)` (índice de seleção,
byte **sinalizado** em `ctx+0x1e`) bate com a linha, **soma `0x18` = 2 registros** — pulando de
`v=200` para `v=184`.

Cores por estado, medidas (não escolhidas):

* número da quantidade: `clut_idx = ctx+0xd3 + ((slot.flags >> 2) & 3) + 2` (`0x8006c08c`) →
  paleta **2..5** do STMOJIU. É assim que munição baixa muda de cor.
* cursor: paleta **3**; piscada = contador `ctx+0x22` ±2 com clamp `0x3f`, cor
  `contador - 0x80` → 128..191, **ciclo de 64 quadros**.

## 6. O arquivo de referência do mod (achado do usuário)

`mod_BH3_Portuguese/xml/status_mapping.xml` (311 linhas) é **a lista de desenho da tela**,
agrupada por sítio de chamada, no formato `<Entry x y w h u v/>`. Ela confirma
independentemente tudo que foi lido do binário — por exemplo `x=8 y=16 w=64 h=64 u=0 v=0` é o
B0, e os pares `u=88 v=200/208` / `v=184/192` são exatamente as placas normal/destacada.
**Use como validação cruzada** ao atacar as outras telas (`title_mapping.xml` faz o mesmo para o
título).

---

## 7. MÉTODO: casar os assets HD do Seamless (nomes de hash)

O pack HD nomeia por **hash do bloco de VRAM blitado**, não por asset, e o hash não é
reproduzível estaticamente (depende das coordenadas de blit do engine). O de-para completo
exigiria rodar o plugin com dump ligado. **Não é preciso**: dá para casar por conteúdo.

### 7.1 Todo asset HD é exatamente 4× o SD

Medido nas 6.900 imagens do pack. Isso dá a chave do de-para pelas dimensões:

| pasta | tamanho | é |
|---|---|---|
| `item/` (120) | 160×120 | os ícones 40×30 do `ITEMA.SLD` |
| `info/` (107) | 448×288 | as placas 112×72 do `ITEMG.PIX` |
| `memo/` (280) | 1024×768 | páginas de documento |
| `map/` (92) | 1024×1024 / 1024×864 | telas de mapa |
| `misc/` | 1024×288, 512×1024, 1024×1024… | fontes e blocos de UI |
| `bgd/` (1316) | 1280×960 | backgrounds |

Como é 4× exato, **o mesmo registro de 12 bytes serve para SD e HD**: só se multiplica o
retângulo de origem por 4. O destino (320×240) não muda.

### 7.2 Casar por conteúdo, com ATRIBUIÇÃO GLOBAL

Ferramenta: [`../../port/dev/hd_casar.gd`](../../port/dev/hd_casar.gd). Reduz o HD ao tamanho SD
e compara pixel a pixel (erro absoluto médio, só onde o SD é opaco).

**O detalhe que multiplica o resultado por 2:** não casar item por item. Percorrer os itens em
ordem, cada um levando o melhor HD ainda livre, é guloso na ordem errada — o item 3 leva o par do
item 90 e deixa 90 sem par. O certo é calcular **todos** os pares, ordenar do melhor para o pior
e ir fixando enquanto os dois lados estiverem livres:

| | item-por-item | atribuição global |
|---|---|---|
| ícones | 49 de 134 | **106 de 120** |
| placas | 96 de 134 | **106 de 107** |

Os casamentos conferidos ficam com erro **0,03..0,05** (ex.: item 001 = Faca →
`info/D43691FB`, que é uma faca em HD). O limiar de aceite é 0,12.

> Testei NCC de luminância esperando robustez ao redesenho e ficou **pior** (33/67) com limiar
> equivalente. O que faltava era a atribuição global, não a métrica.

### 7.3 Blocos de VRAM: como achei a moldura

A moldura (256×272) **não existe** como arquivo HD — não há nenhuma imagem 1024×1088 no pack.
Mas o plugin substitui por **bloco de VRAM**, então ela está fatiada: um bloco `512×1024`
(= 4× de 128×256) casou na posição **(128,0)** do `STMAIN0U` com erro **0,0355** — exatamente a
região da tpage `0x9B`, de onde a moldura sai.

### 7.4 Variantes de IDIOMA

O mesmo bloco existe em vários idiomas, com hashes diferentes (o `hd_ui_map.json` já registrava
isso em `RADAR` vs `RADAR@pt`). Ordenando os candidatos pelo erro na mesma posição, as variantes
aparecem no topo: 1º `E45B0400` (russo: "ОРУЖИЕ", "Состояние"), 2º **`62EE7AF8` (latino:
"EQUIPADO", "STATUS")** — é este que o port usa. Ferramenta:
[`../../port/dev/hd_idiomas.gd`](../../port/dev/hd_idiomas.gd).

---

## 8. Assets: como gerar

```bash
python tools/status_assets.py --all        # STMAIN0U (4 paletas), STMOJIU (9), 134 ícones do SLD
python tools/esp_decode.py dump port/assets/ESP    # sprites de efeito (o brilho do item)
python tools/menu_texto.py --file          # 183 páginas de documento + 31 capas
python tools/omodel2gltf.py --all --out port/assets/OMODEL   # 712 objetos 3D de sala
NOSTALGIA_OUT=port python tools/scd_export.py               # bytecode + tabela de opcodes
```

O descompressor do `ITEMA.SLD` é o LZ de `0x80010000`; o critério de aceite é **as 134 entradas
descomprimirem para exatamente 1200 bytes** (40×30 8bpp) — se alguma não der, o descompressor
está errado.

---

## 9. O que está implementado e o que NÃO está (declarado)

**Implementado, com a medida de onde saiu:** moldura, retrato, palavra da condição (ao vivo, pelo
HP: `>=101` FINE, `>=41`, `>=21`, senão DANGER; VIRUS/Poison por flags), botões EXIT/FILE/MAP com
placa normal/destacada, grade 2×5 (célula 40×30 em (224,66), passo +40/+30), ícones por `item_id`,
dígito da quantidade com a cor pelo estado do slot, placa grande do `ITEMG`, painel EQUIP (ícone
em (172,37) + quantidade em (174,55)), cursor com a piscada de 64 quadros, submenu do item
(EQUIP/USE por "equipável", COMBINE, CHECK), abertura/fechamento em 6 quadros, pausa do mundo.

**Não implementado, com o motivo:**

* **Onda do ECG.** Quatro evidências de que não está nesta task: (a) **zero** chamadas a
  `SetLineF2` no EXE inteiro; (b) nenhuma tabela de forma de onda na faixa `0x80063000..0x80073000`;
  (c) as listras verdes estão batidas no bitmap do B1; (d) o bloco **HD** também vem sem onda.
  Próximo passo: procurar `TILE` em série (onda feita de barras) ou `POLY_G` com tabela de Y.
* **Som do menu.** O de-para *ação → id* está provado (`0x800746c0`: 4 mover, 5 cancelar,
  6 confirmar, 7 inválido, 9 abrir sub-tela); **id → amostra não**. As amostras estão nos bancos
  `SOUND/A_xx`. Sem esse elo, escolher som seria de ouvido.
* **Telas de FILE e MAP.** Os dados já estão extraídos (183 páginas + 31 capas em
  `port/assets/FILE/`, `re3_map_screen.json` com o divisor 450 e o bitmap de visitados).
* **USE / COMBINE / CHECK.** As 125 receitas estão em `port/data/re3_combinacoes.json`; o CHECK
  depende de desenho de texto (frente da fonte).
* **Base `base[2]` (`ctx+0xec`)** dos registros B28/B29 — a auditoria marcou como não medida, e
  por isso esses dois registros não são usados.
* **Cor do primitivo das placas.** As tiras no atlas são bandas chapadas (cinza no destacado,
  quase preta no normal); o azul que a captura mostra vem da cor do primitivo, que não foi
  decodificada. O port usa o azul do próprio jogo (`(8,0,80)`, a cor dominante do ícone de célula
  vazia) com a tira dando a diferença claro/escuro.
