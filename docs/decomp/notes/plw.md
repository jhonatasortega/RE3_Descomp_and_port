# Malha REAL da ARMA no `.PLW` (unidade `plw`)

> **STATUS** (fonte: [`../progress.json`](../progress.json) → unidade `plw`; formato em
> [`../../formatos/PLD.md`](../../formatos/PLD.md) §8) — **round de FECHAMENTO**
> - **Malha da arma:** decodificada como **malha própria** e exportada em
>   `godot/assets/PLD/<nome>_WPN.glb` (TIM própria da arma). **Provado** no Godot 4.7.
> - **Validação 84/84** (`find_anim_banks.py --validate-all`, §5): TODO `.PLW` tem banco
>   armado + MD1; **63** com arma separável (`_WPN.glb`), **21** sem slot (esperado).
> - **Multi-banco RESOLVIDO** (§5): cada `.PLW` tem **3 bancos** (0=corpo inteiro 15 ossos;
>   1=parcial 7 ossos; 2=parcial 9 ossos). Os "blocos aux" eram os bancos 1 e 2.
> - **Osso de anexo** (§6): `bone4` (punho direito), world-rest `(-32, 297, -435)` — dado de
>   decomp; ligar no controller é **vínculo**.
> - **`PL06CH.PLD`** (§7): identificado = variante CH (cutscene/dano) de PL06; contêiner
>   decodificado; MD1 usa sub-formato de **pool compartilhado** (único dos 110) — documentado,
>   não exportado (redundante com o `PL06.PLD` já exportado).

---

## 1. Onde está a arma dentro do `.PLW`

O contêiner `.PLW` tem **9 sub-blocos** (vs 5 do `.PLD`). Papéis (por conteúdo — `PL00W00`):

| Bloco | Off (W00) | Tam | Papel |
|------:|----------:|----:|-------|
| 0 | 0x000008 | 1072 | **EDD** — banco de animação ARMADA (18 seqs; ver `animacoes_player.md`) |
| 1 | 0x000438 | 30332 | **EMR** + pool de poses (15 ossos, 76 B/pose) |
| 2 | 0x007ab4 | 280 | mini-banco/tabela (aux) |
| 3 | 0x007bcc | 3352 | aux (EMR-like nb=7) |
| 4 | 0x0088e4 | 20 | aux pequeno |
| 5 | 0x0088f8 | 280 | mini-banco/tabela (aux) |
| 6 | 0x008a10 | 5412 | aux (EMR-like nb=9) |
| 7 | 0x009f34 | 776 | **MD1 — MALHA** (self-length `u32[0]==tam`) ← **mão + ARMA** |
| 8 | 0x00a23c | 2336 | **TIM própria da arma** (8bpp+CLUT, **56×32**, VRAM img (512,0) / CLUT (256,480)) |

O **único** bloco com assinatura MD1 (`u32[0]==tamanho`) é o **7**. Ele contém **1–2 objetos**
que **misturam** primitivas da **MÃO** e da **ARMA** na mesma malha (a Jill anda sempre com a
arma na mão).

## 2. Como separar ARMA de MÃO (por região de textura)

As primitivas do MD1 **não** apontam para a VRAM da TIM da arma (512,0). Elas amostram o
**atlas de PELE do PLD** (as prims usam `CLUT y=480/481` = paletas 0/1, `tpage x=0/1`). A divisão:

- **MÃO** → amostra a **pele** (regiões normais do atlas do personagem).
- **ARMA** → amostra o **"SLOT" da arma**: um retângulo **quase-BRANCO** no atlas do PLD (banda
  da **paleta 1**, canto inferior-central; ex. `PL00`: atlas x≈`[200,254]`, y≈`[480,510]`). Em
  jogo esse slot é **sobrescrito** (blit) pela TIM própria da arma (56×32) — por isso o
  antigo `composite_weapon_tim` colava a TIM ali.

Logo **a geometria da arma = as primitivas cujos cantos amostram esse branco** (critério:
maioria dos cantos com RGB > 200 no atlas do PLD; `_prim_samples_white`). Confirmado por render:
para `PL00W01` (faca) e `PL00W03` (arma de fogo) as prims brancas formam a lâmina/o corpo; o
`PL00W00` (handgun) **não tem slot** (0 prims brancas → só o punho, arma "pintada" na pele).

## 3. Extração / uso (`pld2gltf.py`)

Reusa os decoders existentes (`parse_md1`, `parse_tim_atlas`, `write_glb_static`,
`render_preview`). Novas funções: `_load_pld_atlas_for`, `_prim_samples_white`,
`split_weapon_prims`, `extract_weapon`.

```bash
# uma arma -> _WPN.glb (+ preview opcional)
python tools/pld2gltf.py --weapon extracted/ntsc-u/CD_DATA/PLD/PL00W01.PLW saida_WPN.glb --preview p.png
# todas -> godot/assets/PLD/<nome>_WPN.glb
python tools/pld2gltf.py --weapons-all godot/assets/PLD
```

**Textura da arma.** As UVs das prims de arma (que no atlas do PLD apontam para o slot branco)
são **remapeadas** para dentro da TIM própria: `uv_arma = (atlas_xy − slot_min) / slot_dim`. O
`.glb` sai texturizado com a **TIM da arma** (decodificada com a CLUT dela) — sem depender da
pele. Coordenadas/escala mantêm o espaço do `.PLW` (o mesh fica onde a arma está em relação à
mão), `SCALE=0.001`, eixo glTF `(x,-y,-z)`.

## 4. Resultado e validação

- **63 armas** exportadas (`_WPN.glb`); **21** sem slot (armas embutidas na pele, ex. handguns
  `*W00`, e outras variantes) — reportadas, não são erro. 0 falhas.
- **Provado no Godot 4.7** (`godot/dev/tools_weapon_shot.gd`, opengl3, modo cena, 1 launch →
  montage): as malhas saem como **armas 3D reais** com textura própria — `PL00W01` = **faca de
  combate** (lâmina + guarda + cabo), `PL00W03` = **arma de fogo** (corpo + detalhe); o conjunto
  cobre facas, pistolas, escopetas/rifles (cano longo), lança-granadas.

```
"<godot>" --path godot --rendering-driver opengl3 --script res://dev/tools_weapon_shot.gd
#   ONLY=PL00W01_WPN,PL00W03_WPN COLS=2 CELL=320 VIEW=side   (subconjunto)
#   (sem ONLY) -> montage de todas as *_WPN.glb
```

## 5. Validação COMPLETA (84/84) — `find_anim_banks.py --validate-all`

Rodada de fechamento: varredura de **TODOS os 84 `.PLW`** (`PL00/PL08/PL09/PL0A` × `W00..W14`):

```
== VALIDACAO plw: 84 arquivos .PLW ==
  com banco de animacao armado : 84/84
  com malha MD1 (mao+arma)     : 84/84
  com slot de arma (separavel) : 63  -> 63 _WPN.glb exportados
  sem slot (arma na pele/punho): 21  (esperado, nao e' erro)
  bancos por arma (histograma) : {3: 84}     <- TODO PLW tem 3 bancos
```

- **84/84** têm banco de animação armado **e** malha MD1. 0 falhas.
- **63** têm arma separável → 63 `_WPN.glb` (bate com a rodada anterior); **21 sem slot**
  (handguns `*W00` de todos os personagens + armas estendidas de `PL09/PL0A` que pintam a
  arma na pele) — **esperado**, não é erro. Lista exata no output da tool.

### Multi-banco por arma — RESOLVIDO (3 bancos por `.PLW`)

Os 9 sub-blocos são **1 malha + 1 TIM + 3 BANCOS de animação** (não "banco + auxiliares
opacos"). Os blocos antes rotulados "aux/mini-banco" (2,3,5,6) são os **bancos 1 e 2**:

| Banco | EDD | EMR | nBones | frameSize | nseq | npose | Papel |
|------:|----:|----:|:------:|:---------:|:----:|:-----:|-------|
| 0 | blk0 | blk1 | **15** | 76 | 18 | 399 | **corpo inteiro** — locomoção armada (seq0=andar, seq1=correr, seq2=mira, seq9=ré). É o banco dos clips `armNN` do `PL00.glb`. |
| 1 | blk2 | blk3 |  **7** | 40 |  8 |  81 | **parcial superior** (7 ossos) — overlay de mira/gesto |
| 2 | blk5 | blk6 |  **9** | 52 |  8 | 102 | **parcial** (9 ossos) — overlay |

(blk4, 20 B = pequeno header/link do banco 2.) O EXE seleciona o banco ativo em runtime
(`player+0xf4/0xf8/0x100` = os 3 slots armados) — ver [find_anim_banks.py](../../../tools/find_anim_banks.py)
e [animacoes_player.md](../../formatos/animacoes_player.md). Isso **fecha** a antiga incerteza
"multi-banco por arma": são **3 bancos** (1 de corpo inteiro + 2 parciais aditivos).

## 6. Osso de ANEXO da arma (dado de decomp p/ o controller)

O ponto de anexo é **decomp** (o offset vem do PLD/PLW); *ligar no controller é vínculo*.
Extraído do esqueleto do `PL00.PLD` (EMR, `parse_emr`):

- **`bone4` = PUNHO DIREITO** (cadeia FK `0→2→3→4` = raiz→ombro-D→cotovelo-D→punho-D). Jill
  segura a arma na **destra** → é o osso de anexo.
- **World-rest de `bone4` = `(-32, 297, -435)`** unidades PS1 (× `SCALE`=0.001 → metros; eixo
  glTF `(x,-y,-z)`). `bone7` = punho esquerdo, espelho `(-32, 297, +435)`.
- A **geometria da arma no `.PLW` já vem em espaço do osso do punho** (obj4/bone4; ver
  [PLD.md §4](../../formatos/PLD.md)). Logo o controller só precisa **parentar o `_WPN.glb`
  ao `bone4`** — sem offset extra além do rest acima.

## 7. `PL06CH.PLD` — o que é (identificado + contêiner decodificado)

`PL06CH` é a **variante "CH" do personagem PL06** (mesmo esqueleto humano de 15 ossos). As
variantes `CH` são **cutscene/dano** (banco de animação **reduzido**): `PL06CH` tem EDD=220 B
e EMR=5800 B vs. PL06 (EDD=1368, EMR=40532). Contêiner = **PLD padrão de 5 blocos** (EDD, EMR,
MD1, aux, TIM), validado (`dirOff+dirCount*4==size`). O `PL06.PLD` (personagem "cheio") **já
está exportado**; `PL06CH` é **conteúdo redundante** (mesmo personagem, menos anims).

**Por que o parser não o exporta — fronteira exata.** É o **único** dos 110 modelos cujo MD1
usa um **sub-formato de pool compartilhado**:
- Todos os 21 objetos têm `vtxOff = norOff = -9636` **idênticos** (pool único global) e o
  struct de 24 B tem os campos `{primStart, primEnd, primCount}` no lugar de
  `{triOff, quadOff, tri/quad count}` → **primStart/primEnd são consecutivos** entre objetos
  (obj0.end == obj1.start …) e **`(primEnd-primStart)/primCount == 12.0` exato** nos 21
  objetos (registros de 12 B).
- O **stream de primitivas de 12 B NÃO é o `emd3_triangle` padrão** (sem marcador `0x7800`,
  índices degenerados sob a leitura padrão) e o **pool de vértices** logo após não tem o
  `pad==0` limpo (912/1538 com pad≠0). Ou seja, a semântica exata do sub-formato exigiria RE
  do loader MD1 no EXE. Como é **1 arquivo redundante** com o `PL06.PLD` já exportado, fica
  **documentado como sub-formato identificado** e não é exportado (custo alto, valor nulo).

## 8. Pendências

- **`*W00` (handguns) e 20 variantes sem slot**: a arma não tem geometria separável no MD1 (é
  representada pela textura na pele/pelo punho). Não exportadas como `_WPN` (esperado; 21 no total).
- A malha da arma é **estática** (sem esqueleto próprio; prende ao **`bone4`** — §6). Ligar no
  controller é **vínculo** (protótipo), não decomp; `godot/scripts/` é somente-leitura aqui.
- Slot detectado por **branco no atlas**: robusto p/ PL00/PL08/PL09/PL0A.
- **`PL06CH.PLD`**: sub-formato MD1 de pool compartilhado (§7) — identificado; não exportado
  (redundante com `PL06.PLD`; semântica das primitivas exigiria RE do loader no EXE).
