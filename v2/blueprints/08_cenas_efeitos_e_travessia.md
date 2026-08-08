# 08 — Cenas de motor, efeitos da sala e travessia vertical

> Nota **nova**, escrita a partir do que a fase do port 1:1 (`../../port/`) estabeleceu depois
> que os blueprints 01–07 foram fechados. Tudo aqui é **insumo direto para o mundo 3D**: o que
> muda a geometria, o que muda a navegação e o que muda a ordem de desenho.
>
> Fonte primária: `../../docs/decomp/notes/cena_r10d.md`, `esp_efeitos.md`, `recuo_tiro.md`,
> `exe_audio.md`, `plw.md`, e `../../docs/formatos/ARD.md`.

## 1. ⚠ Correção importante: a colisão **não é só retângulo**

O blueprint [02](02_colisao_blockout.md) trata a colisão como "retângulos XZ". Isso serve como
blockout grosso, mas **a forma de cada registro importa**, e a tabela de resposta do motor
(`0x8009dfec`, 16 ponteiros, lida por inteiro) diz que são geometrias diferentes:

| forma | geometria real | nº de registros | efeito no 3D |
|---|---|---:|---|
| 1 / 5 / 7 / 8 | caixa cheia | 3.147 + 3 + 16 + 25 | parede/móvel — o retângulo vale |
| 0 | **círculo inscrito** | 632 | coluna/pilar: modelar cilindro, não caixa |
| **4** | **losango** (`dx/hx + dz/hz < 1`) | 17 | obstáculo com faces em diagonal |
| 2 / 3 | **chanfro a 45°** (meio span de um eixo aplicado no outro) | 484 + 373 | quina cortada — muito comum em batente e mureta |
| 6 | **"L" de duas arestas** (canto por `bits & 0x30`) | 463 | quina de parede: só duas faces são sólidas |
| 9 / 10 | **rampa linear** (piso variável em Y) | 32 + 89 | escada/ladeira: o piso sobe, não é patamar |
| 11 / 12 | sem resposta no plano / cone radial | 3 + 5 | — |

Consequência prática: um blockout que extruda todos os 5.289 registros como caixa **fecha
passagens que no jogo são abertas** (foi exatamente o bug que a v1 teve: 0 % de área caminhável
na R101). Use a forma.

## 2. Travessia vertical: os "degraus" são **colisão**, não objeto

Há lugares onde o personagem **sobe e desce por ação própria** (o beco inicial, R10D, é um
deles). Isso **não** é objeto de cena nem animação roteirizada: a assinatura é geométrica —
uma **plataforma de 1 nível** (collider cujo topo é o piso do nível de cima) com um bloco de
**forma 8 encostado no nível superior**, que não colide no predicado mas responde no resolver.

- **28 registros em 14 salas** batem essa assinatura (contra 224 plataformas de 1 nível em 69
  salas — ou seja, a assinatura é seletiva).
- Entre elas **R504 e R510** (e `R510→R504` é a porta de queda de mão única do grafo).
- No 3D: esses pontos são **transições verticais navegáveis** — degrau/plataforma real, não
  parede. Precisam de geometria pisável em dois níveis.
- ⚠ A assinatura é **declarada** (hipótese com 28 casos coerentes), não o sítio do EXE que liga
  a ação pela colisão. Trate como forte, não como provado.

## 3. Cenas de motor: existem, e algumas **trocam de sala**

As cinemáticas de gameplay são **funções do script da sala** (não FMV): trocam câmera, movem
atores, esperam, dão fade. No R10D são duas — a de entrada abre no init da sala, a de saída é
disparada por um gatilho de área.

O que isso muda para a v2:

1. **Uma câmera pode ser "de cena", não de gameplay.** Das câmeras do RID, algumas só aparecem
   dentro de cinemática (no R10D a cena de saída usa uma sequência de 7 trocas). Ao montar as
   âncoras de câmera livre, elas **não** são pontos de jogo — são enquadramentos dirigidos.
2. **Existem portas que o jogador nunca toca.** O opcode `0x66` dispara o handler de um AOT já
   registrado: com AOT de porta, é o script que executa a troca de sala. Por isso **6 portas do
   grafo têm caixa `(0,0,0,0)`** — R10D, R215, R30D, R50D, R50F, R510. O blueprint
   [04](04_grafo_de_salas_portas.md) as rotula como *placeholder/unused*: **está errado**, elas
   são **disparadas por script** e são passagens reais.
3. **Gatilho tem filtro de andar.** O AOT traz o índice de piso (`nFloor`): o mesmo retângulo em
   XZ só vale num nível. Num mundo 3D com andares sobrepostos isso é obrigatório.
4. **Escala do que falta:** foram medidos **135 gatilhos de evento em 58 salas**. Só os do R10D
   estão implementados no port, e **de propósito**: rodar função sem semântica de opcode conhecida
   prende o jogador (há caixas cobrindo a sala inteira). Ou seja: **cenas NÃO estão 100 %** — o
   mecanismo está, o conteúdo por sala não.

## 4. Efeitos da sala (fogo, fumaça, faísca) — em HD e com profundidade

- Cada sala declara **até 8 ids de efeito** numa tabela do próprio arquivo de sala
  (`off[17]`): **156 salas** têm efeito. No beco inicial são 6 bancos / 8 instâncias.
- Os quadros de sprite têm par **HD** no pack: **71 salas, 154 pares, 1.386 quadros**, casados
  por vínculo geométrico (o arquivo HD é 4× uma página de textura, então o sprite em `(u,v)`
  está em `(u·4, v·4)`) — NCC ≥ 0,963, e 2 bancos sem par ficam em SD.
- **Profundidade:** as três chaves da Ordering Table são comparáveis — cenário usa a
  profundidade crua do arquivo, personagem usa `zona·1024 + SZ>>5`, efeito usa `z>>5`, e chave
  menor desenha na frente. Na v2 o Z-buffer resolve sozinho, mas **essas chaves dão a posição em
  profundidade de cada efeito**, o que serve para colocar a chama no lugar certo em 3D e para
  validar o 1º plano.
- Instâncias vêm com **`y = 0`** no dado (as 8 do beco, por exemplo): a altura da chama é do
  próprio sprite, não do campo.

## 5. Animação: os três bancos do `.PLW` (de-para de osso resolvido)

Fecha uma lacuna do blueprint [05](05_personagens_e_animacao.md): os bancos parciais têm
hierarquia própria, e o de-para para o esqueleto de 15 ossos é **exato e igual nos 84 `.PLW`**:

| banco | ossos | mapeia em | papel |
|---|---:|---|---|
| 0 | 15 | todos | corpo inteiro: andar, correr, ré, parada |
| 1 | 7 | `0, 9..14` | **inferior** (as duas pernas) |
| 2 | 9 | `0..8` | **superior** — é a MIRA e o RECUO |

- A aplicação é **substituição do subconjunto**, não blend aditivo.
- No banco 2: levantar a arma, três *holds* de mira (média/alta/baixa), **três clipes de recuo**
  (um por altura) e a **recarga**. O disparo acontece no primeiro quadro do recuo.
- A mira vertical tem **3 posições e ponto** — o pitch do motor é em degraus. Num remake com
  câmera livre isso vira decisão de design: manter os 3 (fiel) ou interpolar (o port 1:1 já
  interpola **só no mouse**, e isso está etiquetado como extensão).
- ⚠ O banco 1 (pernas) **não está exportado**: o passo do pool de poses não fecha com a
  contagem de ossos. Para a v2 isso importa se você quiser sobrepor mira e locomoção.
- **Malha da arma:** o número do `.PLW` é o **id do item, em decimal** (faca 01, pistolas 02/03,
  escopeta 04, lança-granadas 06–09, lança-rockets 10). O anexo é no osso do punho direito.

## 6. Áudio como insumo de mundo

- **Trilha por sala: 169/169 medidas** (casamento por hash dos blocos de sequência contra os
  nomes do PC). Serve para ambientar cada volume 3D desde o primeiro dia.
- **Cada arquivo de sala embute o banco de som dela** (tabela de 48 ids, cabeçalho encontrado em
  168/169). É a fonte de porta trancada, ricochete, baú e som disparado por script.
- **Todo som do jogo passa por uma única função**, com **155 pontos de chamada** mapeados: 64
  com evento provado, 74 medidos com nome declarado, 17 sem identificação. A tabela é o mapa de
  quais eventos de mundo precisam existir.

## 7. O que a v2 herda de graça, e o que não herda

**Herda:** escala, câmeras, colisão (com as formas acima), grafo de portas, itens no chão (330
em 103 salas, com a marca de brilho), objetos de cena (712 modelos exportados, com a convenção
de rotação medida), inimigos, trilha, efeitos, animação de personagem.

**Não herda:**
- a **posição inicial** do personagem em sala com cena de abertura não está no script — vem de
  fora e segue **não localizada**;
- o **ponto de chegada** das portas disparadas por script vem zerado no dado (o port empresta de
  outra porta e marca como débito);
- **conteúdo** de cutscene por sala (o mecanismo está, as 134 outras cenas não foram lidas);
- **inimigo não tem vida/dano** no port ainda: o tiro resolve o alvo e não aplica dano.
