# v2/tools — pipeline de dados da reconstrução 3D

Ferramentas que transformam os dados extraídos do jogo em **arquivos autocontidos por
sala**, prontos para o editor 3D. Tudo aqui é **gerado**: pode rodar de novo a qualquer
momento sem perder trabalho manual (ver [Camadas](#camadas-de-dados)).

## Ordem de execução

```bash
python v2/tools/extract_lights.py        # 1. luzes do bloco LIT      -> lights.json
python v2/tools/consolidate_rooms.py     # 2. junta tudo por sala     -> room.src.json
python v2/tools/solve_layout.py          # 3. resolve o mapa do stage -> stage_layout.json
python v2/tools/build_geometry.py        # 4. paredes + vãos          -> room.geom.json
python v2/tools/coverage.py --json       # 5. quanto as fotos cobrem  -> coverage.json
cd v2/editor && npm install && npm start # 6. editor em localhost:5173
```

O passo 1 vem antes do 2 porque o consolidador embute o resultado das luzes; o 4
depende do 2.

## `build_geometry.py` — de colisão para arquitetura

Os rects `wall` (11% do total) são as paredes de verdade: viram segmentos com
espessura (o lado menor do rect), altura e linha de centro. Cada porta do grafo
recorta um **vão** na parede que ela atravessa. Os rects `prop` NÃO viram
geometria — são volumes de bloqueio de altura cheia (em R100 todos com os 5,0 m de
pé-direito, um deles com 12 × 5 m); como caixa sólida eles entulham a sala.

Resultado: **668 paredes e 231 dos 453 vãos de porta** nas 168 salas. As outras
222 portas ficam em salas onde não há rect `wall` no local — precisam de parede
modelada à mão.

## `coverage.py` — o teto do que dá para automatizar

Amostra pontos no chão e nas paredes e testa se alguma câmera do RID os enxerga
(dentro do frustum e de frente). Ponto que nenhuma câmera vê **nunca foi
fotografado** — nenhum truque de projeção inventa aquele pixel.

| Stage | Cobertura média | Pior sala | Melhor |
|---|---|---|---|
| 1 | 61,3% | R117 = 18% | R108 = 100% |
| 2 | 64,3% | R21B = 14% | R214 = 92% |
| 3 | 59,3% | R30E = 33% | R317 = 84% |
| 4 | 60,7% | R40E = 32% | R40F = 74% |
| 5 | 64,5% | R50B = 28% | R510 = 96% |
| 6 | 53,6% | R61E = 11% | R622 = 92% |
| 7 | 57,5% | R71B = 14% | R703 = 83% |

**~40% das superfícies precisam de textura autoral, não de extração.** É o número
que define o esforço real da v2 — e o motivo de a projeção, vista de fora do cone
de uma câmera, virar aquelas cunhas esticadas.

## Camadas de dados

A regra que faz o projeto ser retomável: **o gerado e o editado nunca moram no mesmo
arquivo.** Regerar as camadas 1–2 jamais destrói a camada 3.

| # | Arquivo | Quem escreve | Papel |
|---|---|---|---|
| 1 | `STAGE{n}/{sala}/room.src.json` | `consolidate_rooms.py` | dado do jogo normalizado |
| 1 | `STAGE{n}/{sala}/lights.json` | `extract_lights.py` | pontos de luz (🟡 parcial) |
| 2 | `STAGE{n}/stage_layout.json` | `solve_layout.py` | pose calculada de cada sala |
| 3 | `STAGE{n}/stage_edits.json` | **editor** | pose ajustada à mão (sobrepõe a 2) |
| 3 | `STAGE{n}/{sala}/room3d.json` | **editor** | geometria ajustada, aberturas |

## `consolidate_rooms.py`

Junta, por sala, o que estava espalhado em `godot/data/` e `v2/reconstruction/`:

- **colisão** (`{sala}_col.json`) — retângulos XZ com `y` (piso) e `h` (**altura**, ver
  abaixo), separando `edge` de `sentinel`;
- **câmeras** (`cameras.json` + RID do RDT) — posição, alvo, `attr` e o background HD;
- **portas** (`room_graph.json`) — com as **duas pontas** de cada porta, que é o que
  alimenta o solver de layout;
- **gameplay** (`{sala}_scd.json`) — o de-para do original: gatilhos, mensagens, flags,
  itens, inimigos e objetos, todos com `box`/`quad` em coordenadas locais da sala.

Cobertura nas 169 salas: **738 gatilhos · 397 mensagens · 42 flags · 14 itens ·
1.217 inimigos · 433 objetos**.

### Duas correções na leitura da colisão (medidas, não supostas)

**`h` é ALTURA, não a coordenada do topo.** Nos 5.289 retângulos: lido como altura, a
mediana é 4,9 m e o máximo 10,1 m, sem nenhum negativo; lido como topo (`|h-y|`), o máximo
vai a 50,6 m. Como o Y do PS1 aponta para baixo, o topo é `y - h`.

**Encostar no limite `s16` não faz do retângulo um descarte.** O critério antigo (qualquer
canto ≥ 31900) marcava 5% dos retângulos como sentinela — mas aí caíam **paredes externas
legítimas**: em `R100`, 2 das 4 paredes da moldura da sala tocam `-32000` e sumiam do
blockout, e a sala deixava de parecer uma sala. Agora `edge` (encosta no limite, continua
sendo geometria) é separado de `sentinel` (atravessa mais de 68 m num eixo, aí sim é
placeholder) — e sentinela de verdade são só **0,6%**.

Com isso, `R100` fecha certo: 4 paredes + 10 móveis, 18,6 × 18,2 m, pé-direito 5,0 m —
exatamente o que [`blueprints/02`](../blueprints/02_colisao_blockout.md) descreve.

## `solve_layout.py` — como o mapa do stage é montado

O RE3 **não tem espaço mundial**: cada sala usa o range inteiro de `s16` localmente
(plotadas cruas, 99% das salas do STAGE1 se sobrepõem). A pose de cada sala precisa ser
deduzida.

**A restrição que resolve:** cada porta recíproca A↔B dá dois pontos que descrevem o
mesmo umbral físico, um em cada sistema local (`arrival_here` em A, `arrival_there` em B).
Atravessar a porta não teleporta, então esses pontos coincidem no mundo.

O script enumera as convenções possíveis (sinal do ângulo, fase da meia-volta, qual ponto
ancora a translação, com e sem snap ortogonal) e **deixa o fechamento de ciclo do grafo
escolher** — nenhuma delas está documentada, então o dado decide. Depois: árvore geradora
por BFS para a pose inicial, e relaxação Gauss-Seidel para espalhar o erro pelas portas
redundantes em vez de acumulá-lo na última aresta.

**Resultado medido:** 6 dos 7 stages escolhem `rot_mode=zero` — ou seja, **as salas do RE3
compartilham os eixos; o que muda entre elas é só a origem** (offset mediano de 32 m).
Só o STAGE4 prefere rotação derivada do `facing` com snap de 90°.

| Stage | Salas | Restrições | Erro de fechamento | Componentes |
|---|---|---|---|---|
| 1 | 38 | 108 | 3,74 m | 37 + 1 |
| 2 | 28 | 79 | 2,35 m | 27 + 1 |
| 3 | 24 | 59 | 0,40 m | 15 + 8 + 1 |
| 4 | 23 | 50 | 0,37 m | 12 + 11 |
| 5 | 17 | 33 | **0,05 m** | 14 + 1 + 1 + 1 |
| 6 | 15 | 32 | 5,72 m | 14 + 1 |
| 7 | 24 | 55 | 2,11 m | **24 (inteiro)** |

O layout é **um bom palpite, não verdade absoluta**. Salas isoladas (componentes de
tamanho 1) não têm porta recíproca que as ancore e caem na origem — precisam ser
posicionadas à mão no editor. O `stage_layout.json` traz `suspect_doors` e o relatório
de sobreposição para guiar a revisão.

## `extract_lights.py` — 🟡 parcial, leia antes de usar

Decodifica `offset_table[9]` do RDT (papel "LIT"). Layout deduzido aqui: header de 4 B,
uma entrada `(n_lights, offset)` por câmera, e registros de 12 B
`(id, pad, x, y, z, brightness)` — com as **posições relativas à câmera**, não à sala
(60% caem dentro do AABB estrito assim, contra 4% se lidas como absolutas).

**Onde isso ainda não fecha:** o layout bate bem em parte das salas (R101 tem ids
decrescentes, posições coerentes, `brightness` sempre múltiplo de 100), mas em R11A os
mesmos 12 bytes dão `(0,0,1,248,3,1)`, que não é posição nenhuma. Falta um discriminador.
Por isso cada luz carrega `plausible` e cada sala um `confidence`, e só o que passa na
sanidade entra em `lights`. **Rendimento atual: 54 pontos de luz confiáveis nas 169 salas** —
não é um sistema de iluminação completo, é um ponto de partida.

A **cor** não foi identificada: nenhum campo se comporta como RGB. Assumir âmbar noturno.

## Convenções de coordenada

```
world_scale = 808 unidades PS1 por metro
PS1 → three.js/Godot :  (x, -y, z) / 808      (o Y do PS1 aponta para BAIXO)
PS1 → Blender (Z-up) :  (x, z, -y) / 808
ângulo (facing)      :  4096 = 360°
```
