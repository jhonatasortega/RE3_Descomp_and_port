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
* ~~USE / COMBINE / CHECK~~ — **feito** (ver §10).
* **Base `base[2]` (`ctx+0xec`)** dos registros B28/B29 — a auditoria marcou como não medida, e
  por isso esses dois registros não são usados.
* **Cor do primitivo das placas.** As tiras no atlas são bandas chapadas (cinza no destacado,
  quase preta no normal); o azul que a captura mostra vem da cor do primitivo, que não foi
  decodificada. O port usa o azul do próprio jogo (`(8,0,80)`, a cor dominante do ícone de célula
  vazia) com a tira dando a diferença claro/escuro.


---

## 10. USE, COMBINE e TEXTO (feitos)

`port/core/itens.gd` carrega `data/re3_combinacoes.json` (gerado por `tools/exe_combine.py`) e
expõe as regras **como o EXE as tem**:

* **Descritor** (`0x800a0514`, 4 B/item): `cat` decide EQUIP vs USE (`0x8006be2c`). Antes eu
  usava "id 1..20", que era a consequência observada; agora é a causa. `max` é o empilhamento —
  é ele que dá a capacidade do pente na recarga (Hand Gun = 15).
* **Cura** (tabela `0x80010e4c`, 11 entradas por `id - 0x20`), aplicação em `0x80067934`:
  soma o HP, faz clamp em `maxHP` (`gs+0x255a`), limpa o bit `0x0200` (veneno) quando a entrada
  manda, e o item some — exceto a **F. Aid Box** (`0x2a`), que gasta 1. "Cheio" é `(u8)maxHP`
  porque o EXE lê com `lbu`. A **Erva vermelha sozinha não faz efeito** (o handler só mostra a
  mensagem 7) — é o tipo de detalhe que uma tabela inventada perderia.
* **Combinação**: `combine_find` (`0x8006a898`) é busca **linear e simétrica** nas 125 receitas.
  Ligados: `simples` (ervas) e `recarregar_arma` (enche até o `max` do descritor e desconta da
  munição). Declarados, não ligados: pólvora→munição (tem bônus por quantidade), upgrade de arma,
  troca de granada e munição infinita.
* **Player** ganhou `hp_max` (`gs+0x255a`) e `status` (`gs+0x255e`: `0x100` vírus, `0x200`
  veneno), que é o que a condição da tela lê ao vivo.

`port/present/texto.gd` desenha com a fonte do jogo: `ETC/TEXU.TIM` (4bpp, 1024×256, 60 CLUTs),
célula **14×14** em grade de 18 colunas, `cod = ASCII - 0x24`, e a **tabela de larguras
proporcionais** de `0x80098dd0` (`trim_left` + `advance` por glifo — `A` avança 14, `i` avança 10
com trim 4). Altura de linha 16, quebra por largura em pixels. Com isso a caixa de mensagem mostra
o **nome do item** e o **CHECK** mostra o texto de exame em português (`re3_items.json`).

Regressão: `port/dev/tests/test_itens.gd`, 39 asserts com o endereço de origem em cada um
(inclui "três `i` são mais estreitos que três `A`", que falha se alguém tratar a fonte como
monoespaçada).


---

## 11. Acentos e a FONTE HD (o texto que comia letras)

Dois problemas, um por causa do outro.

**1. Os acentos não estão na faixa ASCII.** O de-para do EXE é `cod = ASCII - 0x24`, válido só
para `0x24..0x7a`. Todo caractere acentuado caía fora e o desenho **pulava em silêncio** — em
PT-BR isso come letras ("Está" virava "Est"). Os glifos acentuados existem, nos códigos
`0x57..0xa0`, mas o EXE **não** guarda um mapa "unicode → código": ele recebe o texto já
codificado em bytes de glifo.

**2. A fonte do NTSC-U não tem acento.** O `ETC/TEXU.TIM` é a fonte US/JP; nos códigos altos ela
tem **kana**, não Latim acentuado. Provei com uma tira: os códigos que o mod chama de `ã`, `á`…
saem como katakana nesse atlas.

O pack HD tem a fonte **europeia**: `misc/AED42717` (1024×1024 = 4× a página de VRAM 256×256),
com `Ä ä Ö ö Ü ü ß Â â È è É é Ê ê Ï ï Î î Ô ô Ù ù Û û Ç ç Ñ ñ Ë ë Á á Í í Ó ó Ú ú À Ã ã à`.

### 11.1 Como achei o de-para (folha auto-rotulada)

O `encoding.xml` do mod PT **não serve**: ele mapeia para a fonte alternativa do próprio mod
(`ConfigAltFont = 1` no manifesto) — lá `0x58` é `ã`, neste atlas `0x58` é `ä`.

Solução: [`../../port/dev/hd_fonte_folha.gd`](../../port/dev/hd_fonte_folha.gd) gera uma folha em
que **cada célula sai com o próprio número de código escrito embaixo**, usando os dígitos do
próprio atlas. Aí é só ler. Resultado (o que interessa em PT-BR):

| glifo | cod | glifo | cod | glifo | cod |
|---|---|---|---|---|---|
| `Á` `á` | 138 · 139 | `É` `é` | 100 · 101 | `Ó` `ó` | 142 · 143 |
| `À` `à` | 156 · 160 | `Ê` `ê` | 102 · 103 | `Ô` `ô` | 108 · 109 |
| `Ã` `ã` | 158 · 159 | `Í` `í` | 140 · 141 | `Õ` `õ` | 128 · 129 |
| `Â` `â` | 96 · 97 | `Ç` `ç` | 114 · 115 | `Ú` `ú` | 144 · 145 |

O bloco kana começa em **161** — é o limite da varredura.

### 11.2 A métrica tem de vir do MESMO desenho

Primeira tentativa: atlas HD com a métrica do EXE (`A` avança 14) → texto espaçado. Segunda:
métrica do `encoding.xml` (`A` mede 10 com indent 4) → melhor, ainda espaçado. As duas são de
**outros desenhos de fonte**.

O certo é medir no atlas que se usa: [`hd_fonte_metrica.gd`](../../port/dev/hd_fonte_metrica.gd)
percorre as 160 células e grava a **caixa de tinta** de cada glifo em unidades SD
(`re3_font_hd_metrica.json`). Medido: `A` tem 8 px de tinta começando em x=2 (avanço 9), `i` tem
4 px em x=4 (avanço 5), `ç` 6 px em x=5. O único número escolhido é **1 px de espaço** entre
glifos; o resto é medido.

Regressão em `test_itens.gd`: os códigos dos acentos, "uma frase em PT-BR não perde letras" e
"`Está` é mais largo que `Est`" (se o acento não for desenhado, essa falha).


---

## 12. Tradução do menu e as cores de seleção

**As cores da seleção estavam erradas e o dado tinha a resposta.** Eu clareava o azul; na captura
do jogo a linha selecionada é **VERMELHA**. Medindo a região do cursor (`u=120..159, v=0..29`) nas
9 CLUTs do `STMOJIU`, as paletas são exatamente os estados:

| paleta | cor | é |
|---|---|---|
| 2 | `(0,128,0)` verde | 2º marcador (item de ORIGEM da combinação) |
| **3** | `(128,0,0)` **vermelho** | cursor da grade e **linha selecionada** |
| 5 | `(0,112,184)` azul | — |
| 6 | `(248,248,248)` branco | — |

Também: a placa passou a ser um **retângulo sólido** com essa cor, e não a banda do atlas
tingida. Motivo: no PS1 o primitivo faz `tex * rgb / 128`, e a banda é escura (20,20,19) — vezes
um azul escuro dá **preto**. A banda é chapada, então quem importa é a cor.

**Tradução.** Os rótulos `EXIT/FILE/MAP` e `EQUIP/USE/COMBINE/CHECK` são **sprites** do `STMOJIU`
(B149..B158), e o pack HD só tem esse atlas em **inglês e russo** — varri os 14 blocos `1024×288`
e as outras variantes são o mesmo inglês em paletas diferentes. O mod PT também não os traduziu
(o XML dele não tem esses rótulos). Então o port **desenha como texto** com a fonte do jogo:
`SAIR / ARQ. / MAPA` e `EQUIPAR / USAR / COMBINAR / EXAMINAR`. É desvio declarado do original.
`ARQ.` é abreviado porque a placa tem **38 px** no dado e "ARQUIVO" mede ~56.

**Bônus do caminho:** a fórmula `cod = ASCII - 0x24` **só vale para letra e dígito**. Para
pontuação ela erra — `.` é o código **1** (a tabela lista `00=espaço 01=. 02=▶ …`), e a fórmula
daria 10. Por isso o `Texto` consulta a tabela explícita primeiro e usa a fórmula como queda.

---

## 13. Tela de ARQUIVO (documentos)

`port/present/menu_arquivo.gd`, aberta pelo botão `ARQ.`.

O achado que simplifica: **o texto dos documentos é bitmap pré-renderizado**, não texto desenhado
— `ETC/FILEGU.PIX` tem **31 documentos em 183 páginas** de 128×256 (é por isso que existe um
`FILEG` por idioma). Tamanhos medidos nos descritores de `0x8009f2ec`: capa **128×168** (a arte só
ocupa as 168 primeiras das 256 linhas), página de texto **256×176**, setas de virar 12×12.
Os ícones da lista são o `ETC/FILEI.TIM`, uma grade **4×8 de 32×32** (32 células para 31
documentos).

Declarado, não medido: a **posição de tela** das primitivas não está nos descritores
(`0x8006e600` escreve `u,v,clut,w,h` mas não o `x,y`, que vem de buffers de RAM) — centralizo no
espaço 320×240. E o de-para documento → célula do `FILEI` (uso `célula = doc`).

O critério de "tenho este documento" no jogo é um bit em `0x800d212c` que o handler de leitura
acende; o port lista os documentos cujo ITEM está no inventário (categoria 7 = arquivo), que é
subconjunto do critério real.

**Em aberto:** as páginas em PT. O pack tem `memo/` com **280 imagens 1024×768** — que é 4× de
**256×192**, e não de 128×256, ou seja o HD redesenhou as páginas em outro formato. Casar essas
280 com os 183 slots é o próximo passo (o método da §7 se aplica).


---

## 14. Retrato HD, condição em PT, rolagem e a carga de jogo novo

**Retrato em HD.** O bloco da metade DIREITA do `STMAIN0U` (§7.3) não cobre o retrato, que fica em
`u=0..79, v=192..247`. Varrendo os blocos por tamanho: os dois retratos lado a lado formam um
bloco de **80×56**, cujo 4× é **320×224** — e o pack tem 13 arquivos assim. O certo é
`misc/71C8F6F0` (erro 0,179; alto porque o HD é um render novo, mas a imagem traz o rótulo "JILL"
e o rosto em alta). Antes o retrato era 40×56 esticado 4×, e o usuário viu na hora.

**Condição em português.** A palavra (`Fine`/`Caution`/`Danger`/`Poison`/`VIRUS`) também é sprite
do `STMOJIU`, e o atlas HD só existe em inglês e russo. Vai como texto: **BEM / CUIDADO / PERIGO /
VENENO / VIRUS**, nas cores do jogo (verde, amarelo, laranja, vermelho, roxo).

**Rolagem do texto de exame.** Cima/baixo com a mensagem aberta ROLAM o texto em vez de trocar de
ícone, e aparece um `>` quando ainda há linha abaixo. Conferido: um texto de 6 linhas rola 0→1→3,
volta para 2 e para em 4 (não passa do fim).

**Carga de JOGO NOVO — provada byte a byte.** A rotina `0x8006d0d8` copia o template estático de
`0x800a018c` para o array de inventário, e a arma equipada é o **primeiro item**:

```
03 0f 0100   82 fa 0000   83 01 0000   84 01 0000   ff ff ff ff
Hand Gun 15  Reload. 250  Game Inst.A  Game Inst.B  terminador
```

Ou seja **o jogo começa com os dois arquivos de instrução no inventário** — era o que faltava para
a tela de ARQUIVO não nascer vazia. `GameState.novo_jogo()` faz isso.

**A sala inicial.** `ETC/INIT_TBL.DAT` (2312 B) é o estado de jogo novo e vai para `0x800d1d28`;
como `stage` e `room` moram em `0x800d1f76`/`0x800d1f78`, eles caem nos offsets **590/592** do
arquivo — e valem **0 e 0**, que na convenção do port é **R100**. Então o armazém é a primeira
sala JOGÁVEL; o que falta antes dela é o fluxo de boot (WARNING → CAPCOM → TÍTULO → dificuldade →
`INIT_TBL` → OPENING), que está documentado em `menu_titulo.md` e não foi implementado.


---

## 15. Números em HD, páginas em russo e a sala inicial (correções)

**Os números ESTÃO em HD.** Eu tinha escrito que o atlas HD "tem coloração única" e por isso o
número (que muda de cor por estado do slot, paletas 2..5) precisava do SD. **Errado**: o pack tem
**um bloco `1024×288` por paleta**, e o casamento por conteúdo acha qual é qual com folga —
comparando cada `stmojiu_pN.png` contra os 14 blocos:

| paleta | bloco HD | erro | 2º colocado |
|---|---|---|---|
| 2 | `71C342F4` | 0,034 | 0,238 |
| 3 | `869E4EB0` | 0,028 | 0,221 |
| 4 | `15C630A1` | 0,032 | — |
| 5 | `AED1AF39` | 0,032 | — |

Então dá HD **com a cor certa**: o `250` da ferramenta de recarga e o `15` da pistola saem nítidos
e verdes.

**Páginas de documento: fica o SD, e o motivo é medido.** O pack tem `memo/` com 280 imagens
1024×768 (4× de **256×192** — o HD redesenhou a página em paisagem, e não 4× de 128×256). Tentei
casar por conteúdo normalizando as duas em 32×32 (`port/dev/hd_memo.gd`): fechou 137 de 183, mas o
resultado é **inconfiável** — a `pag_002`, que é "GAME INSTRUCTIONS A", casou com uma tabela de
pólvora. E as páginas HD estão em **RUSSO** (o pack Seamless é o russo), então nem seriam ganho num
port PT. Removi os arquivos casados em vez de mostrar página errada.

**Virar página é ESQUERDA/DIREITA.** Estava em cima/baixo. Agora: W/S (ou ↑/↓) andam na lista de
documentos, A/D viram a página do documento aberto.

**A sala inicial é R10D, não R100 — e minha "medição" anterior não valia.** Eu havia lido
`INIT_TBL.DAT` nos offsets 590/592 (onde `stage`/`room` cairiam, já que o arquivo é carregado em
`0x800d1d28`) e obtido 0/0 = R100. Mas aquela região do arquivo é **toda zerada**: eu li padding e
tratei como campo. Não era evidência. O usuário corrigiu: o jogo começa em **R10D**, com a
cinemática de abertura em `R10D_2`. R10D tem 13 câmeras, 49 funções de script e 13 backgrounds HD.
A posição de spawn do port foi medida por varredura (99 pontos que o resolver aceita nas 4
direções; `port/dev/diag_spawn_r10d.gd`) — **não** é a posição do jogo, que vem da cinemática.


---

## 16. A tela de ARQUIVO fica DENTRO da moldura — e por que PT não existe em bitmap

**Onde a tela vive.** A captura do jogo (mandada pelo usuário) mostra o arquivo com o retrato, a
condição e o EQUIP ainda visíveis: ela é outro `screen kind` da MESMA task, então a moldura
continua e o que muda é o painel grande, que passa a ser o **B142** (200×136 em (12,84), o painel
alto) com uma grade de documentos. Refeito assim: a grade é desenhada por
`MenuStatus._desenhar_arquivo` e o `MenuArquivo` virou só dados/navegação.

Medidas da grade **lidas da captura** (a posição das primitivas dessa tela não está nos
descritores — `0x8006e600` grava `u,v,clut,w,h` e não o `x,y`): **5 colunas × 3 linhas**, célula
**32×28** a partir de **(50,97)**, cursor vermelho, célula vazia com a palavra "VAZIO" e o nome do
documento na faixa de baixo. Declarado: lido de referência, não medido no binário.

**Por que os documentos não ficam em português.** Persegui isso até o fim:

1. Os `Rofs*.dat` do jogo instalado **foram modificados** (2025-04-04), então parecia que o mod
   tinha patcheado as texturas. Extraí (`tools/rofs_extract.py`): `Rofs3 = DATA/ETC` (21 arquivos)
   e `Rofs4 = DATA_J/ETC2` (41), que tem `FILEGJ.PIX`, `STMOJIJ.TIM`, `STMAIN0J..3J`.
2. Renderizei: **são os originais JAPONESES**. O `STMOJIJ` tem 装備/使用/組合せ (EQUIP/USE/COMBINE) e a
   página do `FILEGJ` diz プレイマニュアル ("Manual de jogo").
3. Ou seja **o mod não troca textura**: ele traduz DESENHANDO TEXTO (plugin + as tabelas em
   `xml/`, com `ConfigAltFont = 1` no manifesto). É exatamente a abordagem que o port já usa.

Consequência: **página de documento em PT não existe como imagem** — nem no PS1 (`FILEGU` é
inglês), nem no PC (`FILEGJ` é japonês), nem no HD (`memo/` é russo). Para ter documento em
português é preciso o CORPUS de texto traduzido e desenhá-lo com a fonte; nos XML do mod há texto
de sala, item, prompt e menu, mas **não** os documentos. Fica registrado como a dependência real.

Detalhe engraçado do caminho: o mod escreve "Näo", "Saläo", "Opçöes" — usando `ä`/`ö` no lugar de
`ã`/`õ`, porque a fonte alternativa dele não tem os glifos com til. O port usa os glifos certos
(`ã` = 159, `õ` = 129 no atlas HD), então fica **melhor** que o mod nesse ponto.


---

## 17. Ícones do arquivo em HD **e em português** (o par já estava mapeado)

A grade de documentos que eu tinha feito estava errada em três coisas, e o usuário comparou com o
original: o painel é **preto** (não azul), o `VAZIO` é um **sprite** (não a palavra escrita com a
fonte) e a seta de página é um **triângulo verde à direita**.

O que resolveu: o `hd_ui_map.json` **já tinha o par** `FILEI → misc/12124B01`
(NCC 0,903), com a nota *"HD em portugues (mod_BH3_Portuguese: COMO JOGAR/VAZIO)"* — eu não tinha
olhado. É o atlas de ícones de documento em **512×1024** (4× o `FILEI.TIM` de 128×256), grade
**4 colunas × 8 linhas** de células de **128×128** em HD, com os rótulos em português batidos na
arte ("COMO JOGAR", "Diário", "Ficha") e a **última célula (índice 31) sendo o `VAZIO`**.

Ou seja: para os documentos existe PT **em bitmap** — só não existe para as PÁGINAS internas
(§16). A ordem `célula = doc` ganhou confirmação de brinde: a célula 0 é "COMO JOGAR", que é o
documento 0 = *Game Instructions A*.

Fluxo, também apontado pelo usuário: no modo EXAMINAR o ESC **volta ao menu** em vez de fechar a
tela (ele desfaz um passo por vez: exame → combinação → submenu → tela), e ao SAIR nada fica
selecionado — botão, submenu, combinação e texto são zerados, então reabrir começa limpo na grade.
Conferido em `port/dev/diag_fluxo_menu.gd`.
