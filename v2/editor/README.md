# v2/editor — editor 3D de stage

App web que importa uma pasta `STAGE{n}` e monta o cenário 3D navegável, para ajustar
posições e (adiante) desenhar portas e janelas.

```bash
cd v2/editor
npm install      # só three.js
npm start        # http://localhost:5173
```

Sem bundler: o browser carrega ES modules direto e o three.js sai de `node_modules` por
importmap. Editou um arquivo em `src/`? F5 basta.

## O que já faz

- carrega qualquer um dos 7 stages e monta o blockout de todas as salas (piso, paredes,
  móveis) posicionadas pelo `stage_layout.json`;
- desenha as portas, as **ligações do grafo** entre as duas pontas de cada porta, os
  frustums das câmeras originais, os gatilhos do jogo, itens/inimigos e os pontos de luz —
  cada um numa camada que liga e desliga;
- navega em órbita ou voando (WASD/QE) para validar a navegabilidade;
- ajusta a pose de cada sala arrastando (**G**) ou pelos campos do inspetor, e **salva no
  disco** em `stage_edits.json` — sem nunca tocar nos arquivos gerados;
- mostra a qualidade do layout (erro de fechamento, componentes, sobreposição, portas
  suspeitas) para você saber onde o solver provavelmente errou;
- **modo câmera** (duplo clique numa sala): põe o observador na câmera original do jogo e
  projeta o background pré-renderizado sobre a geometria — ver abaixo.

## Entrar na sala — textura nas paredes, chão e teto

Duplo clique numa sala (ou `C`) entra nela. `[` e `]` trocam a câmera de referência, `V`
alterna o modo **andar**, `Esc` sai.

Três peças fazem isso funcionar:

**1. Casca da sala.** Os retângulos de colisão são barreiras soltas — não fecham um cômodo,
e sem superfície não há onde projetar a foto. A casca é uma caixa vista por dentro
(`BackSide`) com chão, teto e as 4 paredes do perímetro, dimensionada pelo **AABB do bloco
de colisão do RDT** e com pé-direito igual à **mediana** das alturas dos colliders (usar o
rect mais alto levava o teto de `R103` a 40 m; a mediana dá 4,8 m). É aproximação: sala em
L vira retângulo, e é aí que entra o ajuste manual.

**2. Projeção multi-câmera** ([src/projection.js](src/projection.js)). Uma câmera só enxerga
uma fatia do cômodo, então projetar a dela sozinha deixa quase tudo cinza. Agora **todas** as
câmeras da sala projetam ao mesmo tempo (até 12) e cada fragmento escolhe a que melhor o vê:

```
score = dot(normal, direção até o projetor) / distância²
```

ganha quem olha a superfície mais de frente e mais de perto. Como WebGL não deixa indexar
array de sampler com índice variável, o laço é **desenrolado ao gerar o shader** — um bloco
por câmera.

**3. Modo andar** (`V`). Primeira pessoa com pointer lock: mouse olha, `WASD` anda no plano,
`QE` ajusta a altura. O olho fica no **piso da sala + 1,6 m**, que é o que dá escala humana
ao cômodo. Sem colisão ainda — atravessa parede.

Controles no painel:

| | |
|---|---|
| **Todas as câmeras** | liga a projeção multi-câmera (desligado = só a câmera atual) |
| **Projetar na malha** | a foto vestindo os volumes |
| **Foto de fundo** | a foto num plano à distância do alvo, dimensionado pelo FOV |
| **Isolar sala** | esconde as outras salas |
| **Travar na câmera** | congela no ponto de vista original do jogo |

**FOV é ajustável de propósito.** Ainda não sabemos o FOV por câmera: o campo `attr` do RID
tem 24 valores distintos e provavelmente o codifica, mas não foi decodificado. A v1 usa 55°
e o script Blender do projeto usa 58,5°. Achar no slider o valor que encaixa cada foto — e
correlacionar com o `attr` mostrado no painel — é o caminho prático para fechar essa questão.

**Limites conhecidos:**

- a projeção **não testa oclusão** — a foto atravessa a geometria e pinta também o que
  estaria escondido atrás de uma parede. Mitigado descartando as faces que dão as costas ao
  projetor; resolver de verdade exige um shadow map por projetor;
- **o teto quase nunca recebe textura**: as câmeras do RE3 olham para baixo, então não há
  foto de teto para projetar;
- salas com mais de 12 câmeras usam só as 12 primeiras (limite de unidades de textura).

## Controles

| | |
|---|---|
| botão esquerdo / direito / scroll | orbitar / pan / zoom |
| `WASD` `QE` (`Shift` acelera) | voar pelo cenário |
| clique | selecionar sala |
| **duplo clique** / `C` | entrar pelas câmeras originais, com a foto projetada |
| `[` `]` | câmera anterior / próxima (no modo câmera) |
| `G` | agarrar e arrastar a sala no plano (`Ctrl` = passo de 1 m) |
| `F` | focar a sala selecionada |
| `Esc` | sair do modo câmera / cancelar arraste / soltar seleção |

## Arquitetura

```
server.mjs     HTTP: serve o app, os dados e grava as edições
               (escrita barrada fora de v2/reconstruction)
src/store.js   3 camadas de dados + persistência; nada de three.js aqui
src/scene.js   three.js: cena, câmera, órbita/voo, picking
src/blockout.js  dados -> geometria (um Group por sala)
src/projection.js  modo câmera: projective texture mapping do background HD
src/ui.js      painel: stage, camadas, lista, inspetor, modo câmera
src/main.js    cola tudo
```

`store.js` é a peça que importa: a **pose efetiva** de uma sala é `edição manual → solver
→ origem`, nessa ordem. Por isso regerar o layout nunca apaga um ajuste seu.

## Ainda não implementado

- **aberturas** (portas/janelas recortadas nas paredes) — o schema já existe em
  `room3d.json` (`openings[]`) e o inspetor já lista, mas falta desenhar na malha e
  aplicar a booleana;
- **bake** da projeção num atlas por sala (hoje a projeção é em tempo real, por câmera),
  com relatório de faces sem cobertura nenhuma;
- oclusão da projeção (shadow map do projetor);
- export do stage montado para glTF/Godot.
