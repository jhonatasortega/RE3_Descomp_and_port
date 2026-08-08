# Malha REAL da ARMA no `.PLW` (unidade `plw`)

> **STATUS** (fonte: [`../progress.json`](../progress.json) → unidade `plw`; formato em
> [`../../formatos/PLD.md`](../../formatos/PLD.md) §8) — **round de FECHAMENTO**
> - **Malha da arma:** decodificada como **malha própria** e exportada em
>   `godot/assets/PLD/<nome>_WPN.glb` (TIM própria da arma). **Provado** no Godot 4.7.
> - **Validação 84/84** (`find_anim_banks.py --validate-all`, §5): TODO `.PLW` tem banco
>   armado + MD1; **63** com arma separável (`_WPN.glb`), **21** sem slot (esperado).
> - **Multi-banco RESOLVIDO** (§5): cada `.PLW` tem **3 bancos** (0=corpo inteiro 15 ossos;
>   1=parcial 7 ossos; 2=parcial 9 ossos). Os "blocos aux" eram os bancos 1 e 2.
> - **DE-PARA de osso dos bancos parciais + overlay de MIRA/TIRO** (**§9**, round novo):
>   banco1 = **INFERIOR** (raiz + 2 pernas → ossos `0,9,10,11,12,13,14`), banco2 = **SUPERIOR**
>   (raiz + cabeça + 2 braços + pelve → ossos `0..8`). Casamento **exato** de `relpos` + cadeia
>   de pais, **igual nos 84 `.PLW`**. O **banco2 é a mira**: o punho direito sobe **895 unidades**
>   na seq0 e há **3 alturas** mantidas + **tiro/recuo**. Exportado como `mira00..mira07` no
>   `<PERSONAGEM>.glb`. **§9 CORRIGE** o §1 (blk1 não tem esqueleto) e o §5 (banco1 é inferior,
>   não superior) e marca 4 pontos **NÃO PROVADOS** (§9.6).
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
| 0 | 0x000008 | 1072 | **EDD do banco0** — animação ARMADA (18 seqs; ver `animacoes_player.md`) |
| 1 | 0x000438 | 30332 | **pool de poses do banco0** (15 ossos, 76 B/pose, 399 poses) — header de 8 B + pool; **NÃO tem esqueleto** (reusa o do `.PLD`), ver §9.2 |
| 2 | 0x007ab4 | 280 | **EDD do banco1** (parcial INFERIOR; idêntico ao blk5) — §9.3 |
| 3 | 0x007bcc | 3352 | **EMR + pool do banco1** (nb=7 = raiz + 2 pernas) — §9.3 |
| 4 | 0x0088e4 | 20 | aux pequeno (fim do pool do banco1) |
| 5 | 0x0088f8 | 280 | **EDD do banco2** (parcial SUPERIOR; byte-a-byte igual ao blk2) — §9.3 |
| 6 | 0x008a10 | 5412 | **EMR + pool do banco2** (nb=9 = raiz + cabeça + 2 braços + pelve) = a **MIRA** — §9.4 |
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
| 1 | blk2 | blk3 |  **7** | 40 (declarado; passo real 32 — §9.6) |  8 |  81 (declarado; 102 pelo EDD — §9.6) | **parcial INFERIOR** — raiz + 2 PERNAS (ossos `0,9..14`) |
| 2 | blk5 | blk6 |  **9** | 52 |  8 | 102 | **parcial SUPERIOR** — raiz + cabeça + 2 BRAÇOS + pelve (ossos `0..8`) = **a MIRA** |

(blk4, 20 B = pequeno header/link do banco 2.) Isso **fecha** a antiga incerteza "multi-banco
por arma": são **3 bancos** (1 de corpo inteiro + 2 parciais que juntos cobrem os 15 ossos).

> ⚠️ **CORREÇÕES desta tabela, feitas no §9** (o texto original está mantido acima para
> rastreabilidade): (a) o banco1 é **INFERIOR**, não "superior" — os ossos 9..14 são as PERNAS
> (§9.3); (b) a afirmação "o EXE seleciona o banco ativo em runtime
> (`player+0xf4/0xf8/0x100` = os 3 slots armados)" é **NÃO PROVADA** — a rotina de equipar arma
> (`0x80043be4`) preenche **só** `+0xf0/+0xf4` com o banco0 do `.PLW` (§9.6); (c) "parciais
> **aditivos**" também é impreciso: as poses são ângulos **absolutos**, então o overlay é
> **substituição** do subconjunto (§9.5). Ver [find_anim_banks.py](../../../tools/find_anim_banks.py)
> e [animacoes_player.md](../../formatos/animacoes_player.md).

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


---

## 9. Bancos PARCIAIS: DE-PARA de osso e o overlay de MIRA/TIRO  ✅

> Round da **animação de mira/tiro**. Ferramenta: [`pld2gltf.py`](../../../tools/pld2gltf.py)
> (`parse_emr_parcial`, `mapa_ossos_parcial`, `build_partial_clips`, `DEPARA_PARCIAL`).
> Tudo aqui é **medição** dos bytes de `extracted/ntsc-u/CD_DATA/PLD/*.PLW`; o que é leitura
> e não prova está marcado **DECLARADO** ou **NÃO PROVADO**.

### 9.1 Correção ao header do EMR — o campo 1 é o **offset do POOL** ✅

O header do EMR é `{u16 hierOff, u16 poolOff, u16 nBones, u16 frameSize}`. O `find_anim_banks.py`
chamava o campo 1 de `kfOff` sem dizer de quê; ele é o **offset do pool de poses** relativo ao
início da seção. Provado por dois lados:

- `PL00.PLD` blk1 = `[100, 176, 15, 76]` e o `parse_poses` **sempre** usou `POOL = emr+176`;
- o layout previsto bate **exato** nos três bancos:
  `hierOff = align4(8 + nb*6)` (header + `relpos`) e `poolOff = align4(hierOff + nb*4 + nb-1)`
  (+ tabela de filhos) → `nb=15`→(100,176) · `nb=9`→(64,108) · `nb=7`→(52,88).

### 9.2 Correção ao §1: o **banco0 do `.PLW` NÃO tem esqueleto** ✅

`PL00W00.PLW` blk1 = `[100, **8**, 15, 76]`: o `poolOff` é **8**, logo o pool começa
**imediatamente após o header de 8 bytes** e `8 + 399*76 = 30332` = **tamanho exato do bloco**.
Não há `relpos` nem hierarquia — o `hierOff=100` é cópia morta do PLD (aponta para dentro do
pool). Ou seja: o banco0 **reusa o esqueleto de 15 ossos do `.PLD`** (é por isso que o
`build_armed_clips` funciona aplicando as rotações direto). A linha do §1 que descreve o blk1
como "EMR + pool de poses (15 ossos)" está **corrigida aqui**: é **só header + pool**.

Os bancos **1 e 2**, ao contrário, **trazem `relpos` + hierarquia PRÓPRIOS** (poolOff 88 e 108)
— e é daí que sai o de-para.

### 9.3 DE-PARA DE OSSO — provado por `relpos` exato + cadeia de pais ✅

Método (`mapa_ossos_parcial`): cada osso não-raiz do banco parcial casa com **um único** osso do
esqueleto de 15 por **igualdade INTEIRA de `relpos`**; depois a **cadeia de pais** tem de fechar,
permitindo pular só ossos de **comprimento zero** (`relpos == (0,0,0)`) que não estejam no
subconjunto. Resultado (`PL00W00.PLW` vs `PL00.PLD`):

| banco | nb | osso do banco → osso do PLD15 | papel |
|---|---|---|---|
| **1** | 7 | `0→0`, `1→9`, `2→10`, `3→11`, `4→12`, `5→13`, `6→14` | **PARCIAL INFERIOR**: raiz + perna-D (9,10,11) + perna-E (12,13,14) |
| **2** | 9 | `0→0` … `8→8` (identidade) | **PARCIAL SUPERIOR**: raiz + cabeça(1) + braço-D(2,3,4) + braço-E(5,6,7) + pivô da pelve(8) |

Evidência crua (unidades PS1):

```
PLD15  relpos: b0(0,-1839,0) b1(-23,-667,0) b2(-43,-611,-305) b3(-2,484,-71) b4(13,424,-59)
               b5(-43,-611,305) b6(-2,484,71) b7(13,424,59) b8(0,0,0)
               b9(-27,213,-149) b10(-24,652,-10) b11(-13,872,-3)
               b12(-27,213,149) b13(-24,652,10) b14(-13,872,3)
banco2 relpos: (0,-1844,0) (-23,-667,0) (-43,-611,-305) (-2,484,-71) (13,424,-59)
               (-43,-611,305) (-2,484,71) (13,424,59) (0,0,0)      <- IDENTICO a b1..b8
       parent: [-1,0,0,2,3,0,5,6,0]                               <- IDENTICO a parent[0..8]
banco1 relpos: (0,-1839,0) (-27,213,-149) (-24,652,-10) (-13,872,-3)
               (-27,213,149) (-24,652,10) (-13,872,3)              <- IDENTICO a b9..b14
       parent: [-1,0,1,2,0,4,5]   (o osso 8 do PLD, de comprimento ZERO, e' COLAPSADO na raiz;
                                   por ser (0,0,0) o mundo nao muda: world[9] = (-27,213,-149)
                                   nos dois esqueletos)
```

> ⚠️ **CORREÇÃO ao §5**: a tabela dizia "banco 1 = parcial **superior**". É o **contrário**.
> Pelo mundo de repouso (PS1: **y+ = para BAIXO**), os ossos 9..14 descem do quadril
> (y = 213 → 865 → 1737) = **PERNAS**; os ossos 1..7 sobem (y = −667 cabeça; ombro −611,
> cotovelo −127, punho +297) = **CABEÇA + BRAÇOS**. Logo **banco1 = INFERIOR, banco2 = SUPERIOR**,
> e é o **banco2** que carrega a mira.

**Validação nos 84 `.PLW`:** o de-para é **o mesmo nos 84** (`(0,9,10,11,12,13,14)` e
`(0,…,8)`), com casamento **exato** em 100% deles. Detalhe: os **21 `.PLW` de `PL0A`** trazem as
**proporções do rig de `PL08`/`PL09`** (o `relpos` deles não é o do `PL0A.PLD`), então o
casamento usa o `PL08.PLD` como referência — os **índices não mudam**. O `build_partial_clips`
faz esse fallback varrendo os `PL??.PLD` irmãos e **recusa exportar** se nenhum casar
(nunca chuta).

### 9.4 O banco2 É a mira: medição do punho direito ✅

Bancos 1 e 2 compartilham o **MESMO EDD** (blk2 e blk5 são byte-a-byte iguais em `PL00W00`:
mesmos `nframes`/`frameOff`/`poseStart` nas 8 seqs) → um único índice dirige as duas metades.
Estrutura do EDD e altura do **punho direito** (osso 4) por FK sobre as poses do banco2
(repouso do esqueleto = **y = +297**; y **menor** = **mais alto**):

| seq | quadros | poses | punho y | Δ vs repouso | leitura |
|---|---|---|---|---|---|
| 0 | 10 | 0..9 | **+291 → −598** | **−895** | **LEVANTAR a arma** |
| 1 | 20 | 10..29 | → −598 | −895 | rampa para a mira média |
| 2 | **1** | 10 | −598 | −895 | **HOLD mira MÉDIA** |
| 3 | 20 | 30..49 | → −1027 | −1324 | rampa para a mira alta |
| 4 | **1** | 30 | −1027 | −1324 | **HOLD mira ALTA** |
| 5 | 20 | 50..69 | → −115 | −412 | rampa para a mira baixa |
| 6 | **1** | 50 | −115 | −412 | **HOLD mira BAIXA** |
| 7 | 32 | 70..101 | −591 (min −716, máx −362) | −888 | **TIRO + recuo** (oscila em torno da mira média) |

Comparação de controle: **`banco0 seq2`** (parada/mira de corpo inteiro) mantém o punho em
**y ≈ +267..273**, i.e. **na altura do quadril** — o braço **só sobe** no banco2. Confirmado
visualmente em `port/dev/shot_mira_overlay.gd` (grade 6×2): a Jill sai dos braços ao lado do
corpo para os **dois braços estendidos à frente** (pose clássica de handgun do RE3), com três
inclinações distintas e o recuo do tiro.

**Casamento com o EXE** ([`exe_combat.md §1.3/§1.6`](exe_combat.md)): a rotina 7 escreve
`player+0xc8` = **13** (levantar) no sub-estado 0 e **14/15/16** conforme `aim_tier` 0/1/2
(**17** no tier 3), com `player+0x6e = (tier<<9)+0x800`. **Três** tiers ↔ **três** holds
(seq2/seq4/seq6) e um "levantar" ↔ seq0. O par (levantar + 3 alturas + tiro) é
**estruturalmente idêntico**; o casamento índice-a-índice de `0xc8` com o nº da seq fica
**DECLARADO** (ver §9.6).

### 9.5 Clipes exportados e como aplicar o overlay

`build_partial_clips` exporta o **banco2** do `PL00W00.PLW` para o `<PERSONAGEM>.glb` como
**`mira00..mira07`** (8 clipes; `PL00.glb` passa de 40 para **48** clipes:
22 `animNN` + 18 `armNN` + 8 `miraNN`). Cada `miraNN`:

- tem trilha de **rotação** só para **`bone00..bone08`** (os 9 ossos do de-para) — **nenhuma**
  para `bone09..bone14`;
- **não** tem trilha de translação de raiz (o overlay não deve disputar a posição do quadril
  com o clipe de locomoção).

**Semântica de aplicação = SUBSTITUIÇÃO do subconjunto, não aditivo.** Motivo (formato): as
poses do banco parcial são **ângulos de Euler ABSOLUTOS de 12 bits por osso** (mesma codificação
das poses do banco0) e o EMR parcial traz o **repouso idêntico** ao subconjunto do PLD — logo
cada valor é a rotação local **completa** daquele osso, não um delta. Receita:

1. toque o clipe de locomoção (`arm00`/`arm02`/`arm09`…) nos 15 ossos;
2. sobrescreva a rotação de `bone00..bone08` com o `miraNN` da vez.

Em Godot, tocar o `miraNN` sozinho num `AnimationPlayer` já produz esse efeito (sem trilha, o
osso mantém o que o clipe de baixo escreveu); com `AnimationTree` use um nó que **não** normalize
pesos por trilha ausente. ⚠️ **`bone00` (quadril) está nos DOIS bancos parciais** — se algum dia
o banco1 entrar, decida quem manda no `bone00`.

### 9.6 O que ficou ABERTO (marcado, não escondido)

- **NÃO PROVADO — layout das poses do banco1 (pernas).** O header declara `frameSize=40`, mas o
  pool tem **3264 bytes** e o EDD compartilhado referencia a pose **101** → precisaria de 102
  poses (102×40 = 4080 > 3264). Duas medições independentes dizem que o **passo real é 32**:
  (a) com passo 32 a translação de raiz é **suave** e igual à do banco2 (±1 unidade em 102 poses),
  com passo 40 é ruído; (b) o 4º halfword do header da pose é **exatamente 8×** o do banco2
  (razão medida 7.954–8.005, média 7.989 em 102 poses). Só que `32 − 8` (header) = **24 bytes =
  192 bits**, e 7 ossos × 3 ângulos × 12 bits = **252 bits** — **não cabe**. Varredura de
  layouts (bits ∈ {8,9,10,12} × offset de bit × subconjunto de eixos × com/sem raiz) **não achou**
  decodificação que ponha os pés em posição plausível. Por isso o banco1 **não é exportado**.
  Para a mira isso **não faz falta**: as pernas ficam com o `arm02` (parada/mira), que é o que o
  jogo mostra.
- **NÃO PROVADO — como o EXE endereça os bancos 1/2.** O §5 afirmava que "o EXE seleciona o banco
  ativo em runtime (`player+0xf4/0xf8/0x100` = os 3 slots armados)". Isso **não se sustenta**: a
  rotina de **equipar arma** (`0x80043be4`) lê a tabela de diretório do `.PLW` e preenche **só**
  `player+0xf4 = ents[0]` (EDD do banco0) e `player+0xf0 = ents[1]` (pool do banco0) —
  `+0xf8/+0xfc` e `+0x100/+0x104` **não são escritos ali**. Quem escreve esses pares é outro
  carregador (`0x800176b4..0x800176f0`, de um contêiner de ≥15 blocos, `ents[4..7]`), não o
  `.PLW`. O seletor `0x800168b8` escolhe o par por `player+0x150 & 0x7f`
  (0→`+0x100/+0x104`, 1→default `+0xe8/+0xec`, 2→`+0xf0/+0xf4`, 3→`+0xf8/+0xfc`, habilitado pelo
  bit `0x80`) e, no sub-estado 0, faz `player+0xc8 = player+0x152 | 0x00070000` — é um helper
  genérico "toque a seq N do banco B", cujos únicos escritores não-zero de `+0x150/+0x152` estão
  na **VM de script de sala** (`0x80056e3c`). Conclusão: **o caminho pelo qual os bancos parciais
  do `.PLW` chegam ao avaliador de pose não está isolado** — fica como pendência de decomp.
- **DECLARADO** — o mapa `0xc8` 13..20 ↔ seq 0..7 do banco parcial. A favor: são **8 valores** e o
  banco tem **8 seqs**; a forma (levantar + 3 alturas + tiro) casa; `0xc8=19/20` (promoção
  "alvo alto") **não existe** no banco0, que só tem 18 seqs. Contra: `nseq` do banco parcial
  **varia por arma** (8 na maioria; 11 em `*W0F`; 5 em `*W0B`; 9 em `*W0C`/`*W14`), então não pode
  ser um "−13" universal. Não confirmado no binário.
- **NÃO PROVADO** — o byte alto da frame-list dos bancos parciais (valores `0x40 0x42 0x44 0x50
  0x62 0x80`). **Não** é o quadro do tiro: a tabela `0x8009cf28` diz handgun=12/magnum=30/faca=50
  e as posições medidas dos flags (ex. `PL00W00` seq7: quadros 7 e 23; `PL00W05`: 12 e 28) **não**
  batem com a arma correspondente. Segue como "flags de evento" sem significado provado.
