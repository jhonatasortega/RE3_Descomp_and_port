# room_graph — grafo de salas REAL (destino das portas) — RE3 PS1 NTSC-U

> Objetivo: montar o grafo sala↔sala (transições) para o game-loop. O **destino**
> das portas NÃO é campo estático do SCD (PROVADO — ver `door_handler.md`): é
> resolvido em RUNTIME. Este round resolve o que os DADOS provam por casamento
> espacial recíproco e deixa o resto como TODO honesto, mais rótulos de área do
> mapa da comunidade (citado) para contexto.

Gerado por `tools/room_graph_build.py`. Escreve em `godot/data/room_graph.json`
(arestas + nós) e em cada `godot/data/STAGE*/R*_scd.json` (portas).

> **ATUALIZAÇÃO (fechamento do domínio de porta):** o destino É campo estático do SCD
> (ver `door_handler.md`) — o texto abaixo, das seções "casamento espacial", é do round
> ANTIGO (quando líamos o opcode errado 0x67 e o destino "não fechava"). Mantemos por
> registro histórico do método espacial (não mais o caminho principal).
>
> **AUDITORIA FINAL (fecha o 100%):** o grafo tem **453/453 portas resolvidas** via
> de-para autoritativo `índice→fileid 0x8009dfd0→nome`. As portas são os AOTs com SCE
> type **∈ {1,13}** (opcodes `0x61`/`0x62`) — **sce==1** (porta normal, 447) **e sce==13**
> (porta condicional/scripted, 6; handler `0x80051cb0`; 3 pares recíprocos R114↔R118,
> R304↔R30A, R40C↔R40E). Antes só sce==1 era contado (447) → **corrigido p/ 453**.
> Reciprocidade **94,3%** (279/296 arestas-sala); as **17 mão-única** são TODAS
> justificadas (campo `oneway_reason` por aresta; tabela em `door_handler.md`) ⇒
> **reciprocidade EXPLICADA a 100%**, `mao_unica_nao_explicada = 0`. Nenhum erro de
> destino/parse encontrado na auditoria 1-a-1. Cobertura confirmada: varrendo TODOS os
> opcodes AOT, só `sce∈{1,13}` troca de sala; o room-loader `0x800493ec` só é chamado
> pelo cluster do door_handler (sem warp por script). Cada aresta agora tem `reciprocal`
> e (se false) `oneway_reason`.

## Campos gravados por porta/aresta
- `to_stage` (int), `to_room` (int, índice interno = hex do nome), `to_room_id` (str `Rxyz`)
- `dest_source`: `"recip"` (porta de volta B→A confirma) | `"scd_door"` (de-para do fileid,
  direção única) | `null` (índice fora da tabela / slot vazio — não ocorre hoje)
- `dest_conf`: confiança [0..1] (0.95 recíproco, 0.75 direção única)
- `dest_reason`: justificativa
- `arrival`/`to_x/y/z/facing`: chegada — **100% decodificada** (inalterada).

## Método (casamento espacial recíproco)
Numa porta A→B: o player toca o gatilho `box_A` (coords de A) e SURGE em B em
`arrival` (coords de B), rente à porta de volta B→A. Para o par recíproco
(dA em A, dB em B):

```
arrival(dA) ≈ box(dB)   (ambos no espaço de B)
arrival(dB) ≈ box(dA)   (ambos no espaço de A)
```

Distância = ponto→retângulo (`rectdist`). É **independente de frame global**:
cada comparação vive no espaço de UMA sala.

- **Tier `recip`** (conf 0.80–0.95): par mútuo same-stage — as DUAS direções batem.
  Recíproco POR CONSTRUÇÃO. Emparelhamento guloso único. 7 pares → **14 portas**.
- **Tier `inferido`** (conf 0.55): a chegada casa com UM ÚNICO `box` de sala
  same-stage (direção única, sem ambiguidade). **47 portas**. Não garante volta.
- **`null` + TODO**: nem recíproco nem único → runtime ou transição inter-stage.

## Achados que sustentam o método (novos, verificáveis nos dados)
1. **Frames de coordenadas compartilhados por área.** A chegada de uma porta casa
   *exatamente* (dist 0) com `box` de várias salas — inclusive de outros stages.
   Containment da chegada dentro da colisão same-stage é ambíguo em **473/481**
   portas. ⇒ posição sozinha NÃO desambigua; só o `box` da porta-de-volta resolve.
2. **Salas gêmeas entre stages** (`_meta.twin_families`, **43 famílias** por
   fingerprint de colisão idêntico). Regra da comunidade confirmada: **R6xx=R1xx,
   R7xx=R2xx** (Mercenaries reusa Downtown/Uptown); há gêmeas intra-jogo também
   (ex. `R102=R11D`, `R300=R310`, `R20C=R215`). Por isso o match *cross-stage*
   exato é quase sempre **contaminação de gêmeo**, não conexão real → só casamos
   **same-stage**. Transições reais entre stages/áreas ficam como TODO.

## Cobertura (ATUAL — destino estático do SCD, pós-auditoria)
| métrica | valor |
|---|---|
| arestas (portas) | **453** (447 `sce1` + 6 `sce13`) |
| **resolvidas total** | **453 (100%)** |
| recíprocas (por porta) | 436 |
| mão-única (por porta) | 17 — **todas justificadas** (`oneway_reason`) |
| abertas (TODO) | **0** |
| cross-stage | 17 |
| arestas-sala únicas (gêmeas coladas) | 296 |
| recíprocas (arestas-sala) | 279 (**94,3%**) |
| mão-única (arestas-sala) | 17 (**0 não-explicada**) |
| **reciprocidade EXPLICADA** | **100%** |

Motivos de mão-única (contagem): mercenaries (4), story_variant (3),
story_progression_gate (2), endgame/boss (3), one_way_fall (1),
one_way_layout (1), one_way_special (1), transient_variant_scripted (1),
placeholder_unused (1). Tabela com prova por aresta em `door_handler.md`.

### Cobertura (round ANTIGO — método espacial, histórico)
| métrica | valor |
|---|---|
| arestas (portas) | 481 |
| resolvidas total | 61 (12.7%) |
| recíprocas | 14 (38.9%) |

Reciprocidade honesta: as **14 `recip`** são recíprocas por construção (100% do
subconjunto); as `inferido` são de direção única (sem volta garantida), o que puxa
a reciprocidade global das arestas-sala para 38.9%. Não fabricamos volta.

## Por que não fechou mais (honesto)
- O destino não sai do SCD por encoding estático (provado; `door_handler.md`).
- O sinal espacial satura: frames compartilhados tornam posição ambígua; a
  extração de `box` cobre só 240/481 portas; muitos pares same-stage têm apenas
  um lado com `box`. Reciprocidade de matching ampla fica em ~40–57% (não confiável
  para afirmar aresta). Preferimos **subclamar** a fabricar.

## Fontes (mapa da comunidade — externo, NÃO-oficial)
Rótulos de área/descrição nos nós (`node.area`/`node.desc`, `area_source`) vêm de
fóruns de fãs — tratar como CONTEXTO, não fato verificado:
- Resident Evil 1 2 3 Modding Forum — "Resident Evil 3 Complete RDT info" e
  "RDT Information and Places!!": https://www.tapatalk.com/groups/residentevil123
- Mapas por área (Uptown/Downtown/RPD/Clock Tower/Hospital/Park/Factory):
  https://www.evilresource.com/resident-evil-3-nemesis/maps
- Wiki Resident Evil (nomes de salas): https://residentevil.fandom.com

Nota: evilresource/wiki usam NOMES de salas; não há tabela pública legível por
máquina `Rxyz`↔nome↔adjacência completa. Por isso não derivamos arestas do mapa
(risco de fabricar) — só rotulamos os `Rxyz` que a comunidade nomeou explicitamente.

## Investigação da pista `offset_table[10]` / `RDT+0x30` (disassembly) — REFUTADA

O coordenador levantou a hipótese de que `offset_table[10]` (=`RDT+0x30`) seria a
tabela ESTÁTICA de destino, indexada pelo door-index. Rastreei o disassembly do
EXE (`extracted/ntsc-u/SLUS_009.23`, via `tools/exe_parse.py`) e **a indireção
existe, mas NÃO leva ao destino** — leva ao gráfico de abertura da porta:

- **Consumidor `door_handler 0x800248e4`** (confirmado byte-a-byte):
  `$s0 = 0x800ca738` (gs). `lw $a1,0x2154($s0)` ⇒ descriptor `*(0x800cc88c)`.
  Lê `+0..+6`=X/Y/Z/facing, **`+8`=stage** (`multu 0x38e38e39` = ÷9), **`+9`=room**
  (→ grava `current_room 0x800d1f78`). Confirma `door_handler.md`.
- **A indireção citada** aparece em `0x8005671c` (dentro do handler do opcode
  `0x7f`, `0x80056510`): `a0 = *(gs+0x2134)` (RDT atual), `v1 = *(a0+0x30)` =
  **offset_table[10]**, `v0 = v1 + door_index*8`, `a1 = *(v0+4)`. Ou seja o bloco
  10 É indexado pelo door-index — a estrutura da pista está certa.
- **MAS o conteúdo do bloco 10 é GRÁFICO DE PORTA, não destino** (decodificado das
  169 salas): cada entry de 8B = `(p0, p1)`, ponteiros dentro do RDT.
  `p0` → registro `10 00 00 00 09 00 …` seguido de **vértices 3D** (malha da porta);
  `p1` → registro `18 00 00 00 10 00 14 00 …` seguido de **retângulo de sprite**
  (x,y,w,h) — a animação de abrir a porta. Em R100 as portas 2–6 **compartilham o
  mesmo `p0`** (mesma malha) → não pode ser destino per-porta.
  ⇒ **`offset_table[10]` = tabela de gráfico/animação de abertura de porta.**
  (Corrige o "luz/objeto?" de `ARD.md §3.2`.)
- **Produtor do descriptor** `0x80050d28`: seta `flag-troca 0x800c7960=1` e
  `gs+0x2154 = $s1` (o door-struct). Não há `jal` direto para ele — é chamado por
  **callback/ponteiro** (evento de colisão com o gatilho), não por caminho estático.
- **Teste de reciprocidade decisivo:** o `0x7f`-handler faz `struct+9 = opcode@+8`
  e o `door_handler` lê `descriptor+9` como room. Tratando **`byte@+8` do `0x7f`
  como índice interno de sala same-stage** (via tabela de fileids `0x8009dfd0`):
  reciprocidade = **6%** (e nenhum outro byte `+6..+10` passa de ~6%). Se fosse
  campo estático de destino, seria ~alto. ⇒ o valor consumido é **sobrescrito/
  resolvido em runtime** antes do handler ler. **Confirma: destino NÃO é estático.**

Conclusão honesta: a pista foi verificada até o fim no disassembly; `offset_table[10]`
não é a tabela de destino (é gráfico de porta). O par (stage,room) é materializado em
runtime. Ferramenta de checagem: `/tmp` scripts descartáveis + `tools/exe_parse.py`.

## Rastreamento do PRODUTOR do descriptor (2ª rodada) — destino NÃO é estático (prova byte-a-byte)

Rastreei o produtor do descriptor `gs+0x2154` que o `door_handler` consome (+8=stage,
+9=room), seguindo os `lw/lhu/lbu` até a origem:

- **Escritores de `gs+0x2154`:** `0x80050fb4`, `0x800510ec` (`= *(gs+0x21dc)`),
  `0x80051d10`. Todos setam o descriptor = um **door-struct** e ligam a flag-troca
  `0x800c7960=1`. O produtor é chamado por **callback do evento de colisão** (ponteiro
  de estado em `gs+0x75dc`), não por `jal` estático.
- **Construtor dos campos do descriptor = `0x80056778`** (dentro do handler `0x7f`,
  `$s5`=opcode `0x7f`): escreve
  `desc+8 = (0x7f@+3) & 0x1f` (stage) e `desc+9 = (0x7f@+6_u16) >> 12` (room),
  `desc+0xa/+0xb` de `0x7f@+5/+7`. Em seguida chama as rotinas de **automap**
  `0x80035f2c` / `0x80036234` (grid índice→célula, `0x80036120`).
- **PROVA (dump das 481 portas):** os bytes `0x7f@+2..+7` são **TODOS ZERO** em 100%
  das portas ⇒ `stage=0, room=0`. O construtor lê zeros. **O opcode NÃO carrega o
  destino.** (Confirma o "seletor sempre 0" do `door_handler.md`, agora estendido a
  todos os campos de destino.)
- **`0x67` (trigger, 22B):** `+1`=aot, `+2`=sce, `+3`=sat, `+6/+8`=x/z do gatilho,
  `+10/+12`=**w/d do gatilho** (não stage/room). `gs+0x2158[aot_id] = &(0x67 +2)` é o
  **registro de colisão do AOT**, não o destino.
- **Sem tabela global:** `0x80098970` (default do banco 0 do seletor) = `{0x1000,0}`
  trivial; junto do fileid `0x8009dfd0` (9 ponteiros de stage) **não há** tabela
  paralela de destino por (stage,room,aot).
- **Reciprocidade de TODA hipótese estática** (varredura de todos os offsets do `0x7f`
  como (stage,room), **cross-stage e com gêmeas colapsadas** — atendendo ao ponto 3):
  **máx. 4%** (pares) / 15% (byte `+1`=door_index same-stage, artefato de correlação).
  Se um byte fosse o destino, seria ~alto. **Não é.**

**Conclusão honesta e definitiva:** o par (stage,room) de destino **não existe** como
campo estático no SCD/RDT nem em tabela do EXE indexada por porta. Os bytes de destino
do opcode são zero; o valor consumido pelo `door_handler` é materializado em **runtime**
(estado do motor / salas vizinhas carregadas + posição de chegada). A reciprocidade
baixa (≤15%) **não** é artefato de teste (testei cross-stage + gêmeas) — é a ausência do
dado estático. Isso encerra, com evidência, a hipótese de "fonte estática por porta".

**Fallback (recomendado, autorizado):** ancorar o grafo de conexões da comunidade aos
`Rxyz` via `godot/data/hd_map.json` (sala↔câmera↔background HD): casar as imagens dos
mapas por área (evilresource) com os backgrounds catalogados ⇒ nome↔`Rxyz` ⇒ arestas
`source="map"`, validando com as 14 `recip`. Requer correspondência nome↔`Rxyz` (não há
tabela pública legível por máquina; a comunidade nomeou ~24 salas — ver `AREA_LABELS`).
É um esforço de casamento de imagens/dados, escopo próprio; não feito aqui p/ não fabricar.

## Próximos passos para fechar o grafo
1. **Ancorar o mapa da comunidade nos `Rxyz`** usando os HD backgrounds já
   catalogados (`godot/data/hd_map.json`, que casa sala↔câmera↔imagem) + as fotos
   de cada área do evilresource ⇒ nome↔`Rxyz` ⇒ adjacências (source=`"map"`).
2. **Trace do runtime** (rota definitiva): seguir `door_handler 0x800248e4` →
   descriptor `*(0x800cc88c)+8/+9` e a tabela de fileids `0x8009dfd0` para
   materializar (stage,room) por door-index. Ver `door_handler.md`.
3. Cruzar (1)/(2) com as **14 arestas `recip`** deste round como âncoras de validação.
