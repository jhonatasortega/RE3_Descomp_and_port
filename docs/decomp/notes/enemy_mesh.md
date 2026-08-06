# Malha dos inimigos do RE3 — formato e estado da RE

## ✅ RESOLVIDO via port de PC (GOG): zumbi exportado e renderizado

O `.EMD` embutido no `R###.BIN` do PS1 é **reempacotado in-RAM** (formato empacotado,
não decodificado — §4 abaixo). A **fonte limpa é o port de PC (GOG)**: os inimigos
estão como `.EMD` **standalone** (formato `emd3.h` do reevengi) dentro dos `Rofs*.dat`:
- `Rofs9.dat` = `ROOM/EMD` (69 EMD + 69 TIM) — inimigos principais.
- `Rofs10.dat` = `ROOM/EMD08` (31 EMD + 31 TIM).

Extração: `python tools/rofs_extract.py "<GOG>/Rofs9.dat" C:/tmp/re3pc_emd`.

**Zumbi macho = `EM10.EMD`** (confirmado: `EM10.TIM` tem 99872 bytes, idêntico ao
tamanho do blk6 de `R101.BIN` do PS1 — a mesma pele). Parse do modelo (dir[14]=`model`):
`count=15` objetos (=15 ossos, skinning rígido), **304 verts (8B, pad=0), 155 tris,
175 quads**. Vértices em espaço LOCAL do osso; UV/page/clutid por primitiva.

Pipeline (`tools/emd2gltf.py`):
1. Geometria do `.EMD` do PC (structs `emd3.h`).
2. Textura do `.TIM` (`parse_tim_atlas`); UV→atlas: `tx=(page>>6)&3` (passo 128 texels,
   8bpp), `pal=clutid&0x3F` (banda de paleta). **Essencial**: `page` usa bit 6, não os
   bits 0-3 — sem isso o `.glb` fica com "sal e pimenta" na textura.
3. Esqueleto+animação: o esqueleto do PC é ~idêntico ao EMR do PS1 (15 ossos, mesma
   ordem/hierarquia, `move_size=76`, `relpos_len=100`), então reusa-se o **EMR + 16
   anims já provados** do `R101.BIN` (PS1) via `pld2gltf.parse_emr`/`build_anim_clips`.
   Placement: obj i → osso i; `P = world[i] + vert_local`; skin `write_glb` do pld2gltf.

Resultado: `godot/assets/ENEMY/zumbi_macho.glb` (418 verts, 505 faces, 15 ossos, 16
anims, tex 384×768). **Renderizado no Godot (opengl3, `tools_anim_shot.gd`, frente+lado,
anim00)**: zumbi reconhecível (rosto morto, camisa ensanguentada, jeans rasgado),
skinning íntegro na animação.

Uso: `python tools/emd2gltf.py <EM##.EMD> <EM##.TIM> <saida.glb> [--ps1 <R###.BIN> <blk>]`

### Esqueleto + animação do PRÓPRIO EMD (autossuficiente) ✅

O `emd2gltf.py` agora **dispensa o `--ps1`**: usa o esqueleto/anim do próprio EMD, cujo
formato é idêntico ao PS1. Diretório `skel0`/`anim0` (bank 0):
- `emd_skel_header_t` @skel0: `{u16 relpos_len(=hier_off), u16 move_offset, u16 count(=nb),
  u16 move_size}`. relpos = `count`×`s16 x,y,z` em `skel0+8`; armadura (hierarquia) em
  `skel0+relpos_len` (`{u16 num_mesh, u16 offset}` por osso + lista de filhos u8).
- Poses (movimentos) em `skel0+move_offset` (`move_size` bytes cada): `s16 root x,y,z`,
  `s16 speed_y`, depois **ângulos de 12 bits** (3 por osso) — mesmo empacotamento do PS1.
- `anim0` = `emd3_anim_header_t[]` `{u16 count, u16 offset, u16 pad[2]}`; `n_seq =
  offset[0]/8`; frame u16: `low`=índice de movimento, `high`=flags. = mesmo EDD do PS1.

Como `relpos_len=100`, `move_size=76`, `count=15` batem com o EMR/EDD do PS1, reusa-se
`pld2gltf.parse_emr` + `build_anim_clips` direto nos offsets do EMD.

### Lote: 69 EMD → `.glb` (Rofs9 `ROOM/EMD`)

`python tools/emd2gltf.py batch C:/tmp/re3pc_emd godot/assets/ENEMY` — **69/69 exportados,
0 anomalias, 0 zero-face** (após o fix da variante com flags no u16 alto — ver EM2D abaixo).
UV `tx=(page>>6)&3`, `pal=clutid&0x3F`. Nomes incertos levam sufixo `_incerto` (o `?`
é inválido em nome de arquivo no Windows). NB: `batch` grava com nome genérico `em##` — os
assets curados (`zumbi_macho`, `cao_cerberus`, `em3e_helicoptero`…) foram (re)gerados por
`convert()` individual p/ preservar os nomes.

Render de identificação (UM único launch, sem editor):
`CELL=256 COLS=10 VIEW=front OUT=res://dev/_montage_front.png godot --path godot
--rendering-driver opengl3 --script res://dev/tools_enemy_montage.gd`
→ montage de TODOS os 69 num único processo (PNG temporário, apagar após usar). O stdout
imprime `CELL i <arquivo>` p/ mapear célula→EMD. (O harness sobrepõe o HUD do jogo em cada
célula; os modelos aparecem acima do HUD.)

O montage revelou **2 helicópteros = EM3E (civil, azul) e EM3F (militar, cinza)** — **NÃO**
em EM5#/EM6# como anotado antes, e **NÃO são vermes** (rótulo antigo `em3#_verme` corrigido).
Confirmação cruzada de contexto: as únicas salas com class `0x3e`/`0x3f` são **R50E/R50A
(STAGE5)** = área final do jogo, coerente com as cenas de helicóptero do RE3. Assets
renomeados p/ `em3e_helicoptero.glb`/`em3f_helicoptero.glb`. Os EM50–EM71 são todos humanos.

**Confirmados por render texturizado** (front): EM10 zumbi ✅, EM20 cão (Cerberus,
dóberman) ✅, EM21 corvo ✅, EM25 aranha (listrada) ✅, EM3E/EM3F helicópteros ✅; e por
categoria: EM22/EM23 hunters (bípede reptiliano), EM28/EM34/EM35 insectoides (drain deimos/
brain sucker), EM30/EM32/EM33 vermes (corpo alongado), EM38 bípede grande (Nemesis provável),
EM50–EM71 NPCs humanos.

> **Cobertura da anotação por render (69 EMD, ver `godot/data/sce_enemies.json` →
> `emd_annotations` + `_meta.cobertura_emd_render`):** ALTA=6 (8.7%), MEDIA=24, categoria
> (humano)=26, BAIXA=13. **ALTA+MEDIA=43.5%**; **categoria-ou-melhor=81.2%** (só 13/69 =
> 19% ficam sem categoria: fragmentos de 1–6 ossos + humanoides genéricos + EM2D).

### Ground-truth por TIM byte-idêntico (mesh embutida PS1 ↔ EM## do PC)
Casando o **skin embutido** no `R###.BIN` com os `EM##.TIM` do PC por **bytes idênticos**:
**35 salas** casam exatamente. A mesh `605afd27` (âncora do zumbi, R101) aparece texturizada
com `EM10`/`EM18`/`EM1B` = **variantes de zumbi** (um mesh, vários skins) → confirma
`605afd27 = família Zumbi` em 14 salas. Um mesmo tamanho de TIM (99872 B) hospeda 2 texturas
distintas (`EM10` vs `EM23`). Isso prova que a ligação **type/class ↔ mesh ↔ EM##/skin é m:n**
em todos os níveis — não há mapa canônico estático `type→EM##`. Mecanismo e endereços de prova
em [`sce_em_set.md §2.3`](sce_em_set.md) e `sce_enemies.json → _meta.linkage_investigation`.

| EM## | glb | ident. | conf. | bones/verts/anims |
|---|---|---|---|---|
| EM10 | `zumbi_macho.glb` | Zumbi macho | ✅ (TIM=R101, render) | 15 / 418 / 8 |
| EM11–EM1F | `zumbi_em##.glb` | Zumbis (variantes) | ✅ categoria (humanoide) | 11–16 / ~330–610 |
| EM20 | `cao_cerberus.glb` | Cão zumbi (Cerberus) | ✅ render | 17 / 395 / 27 |
| EM21 | `corvo.glb` | Corvo | ✅ render | 10 / 134 / 10 |
| EM22, EM23 | `em2#_hunter_incerto.glb` | Hunter β/γ? | 🟡 (20-21 ossos, bípede) | 20–21 / ~740–1100 |
| EM24 | `em24_incerto.glb` | ? bípede | 🟡 | 20 / 686 |
| EM25 | `aranha.glb` | Aranha | ✅ render | 20 / 677 / 13 |
| EM26 | `em26_aranha_cria_incerto.glb` | Aranha cria? | 🟡 (1 osso, 18 v) | 1 / 18 / 0 |
| EM28 | `em28_drain_deimos_incerto.glb` | Drain Deimos / Brain Sucker | 🟡 render (insectoide) | 21 / 750 / 36 |
| EM2D | `em2d_incerto.glb` | **RESOLVIDO** (bug de parser, não corrupção); render não identifica | 🟡 BAIXA | 15 / 529 / 6 |
| EM30, EM33 | `em3#_verme_incerto.glb` | Verme (Grave Digger?) | 🟡 (17 ossos, 1121 v) | 17 / 1121 |
| EM32 | `em32_verme_incerto.glb` | Verme (Sliding Worm?) | 🟡 | 6 / 109 |
| EM3E, EM3F | `em3e_helicoptero.glb`, `em3f_helicoptero.glb` | **HELICÓPTERO** (veículo, render inequívoco) | ✅ | 5–8 / 365–915 |
| EM34, EM35 | `em3#_[brain_sucker/drain_deimos]_incerto.glb` | insectoide | 🟡 | 16 / ~980 |
| EM36, EM3A | `em3#_humano_incerto.glb` | humanoide (parcial na pose) | 🟡 | 16 / 1209 |
| EM38 | `em38_nemesis_incerto.glb` | Nemesis (forma?) | 🟡 render (bípede grande) | 22 / 1184 / 30 |
| EM27, EM37, EM39, EM3B, EM40 | `em##_incerto.glb` | pequenos/partes | 🟡 | 1–6 ossos |
| EM2C, EM2E, EM2F | `em2#_[humano]_incerto.glb` | humanoide | 🟡 | 15 / ~520–718 |
| EM50–EM71 | `em##_humano_incerto.glb` | NPCs humanos (Nicholai, Carlos, Mikhail, Brad…) | 🟡 categoria | 15–16 / ~520–1034 |

> Confiança: ✅ = confirmado (render/TIM); categoria ✅ = silhueta inequívoca mas nome
> específico não fechado; 🟡 = palpite por silhueta/convenção (sufixo `_incerto`).
> O roster do `evilresource.md` (zombie, dog, crow, drain deimos, brain sucker, grave
> digger, sliding worm, spiders, hunter β/γ, Nicholai, Nemesis) casa com as categorias
> vistas, mas o mapeamento 1:1 EM##↔nome-canônico não está publicado — daí os `_incerto`.

### EM2D — RESOLVIDO ✅ (era "corrompido"; na verdade era BUG DE PARSER, não corrupção)
O `EM2D.EMD` (19973 B) **não está corrompido no disco**. É uma **variante do formato com
FLAGS no u16 ALTO** de vários campos do `model_object`. O parser antigo lia `vtx_count`,
`vtx_off`, `nor_off`, `tri_off`, `quad_off` como `u32` cheio → em EM2D o u16 alto carrega
`0x1500`/`0x15..` (flag), gerando `vtx_count` gigante (ex.: `0x15000015`) e offsets fora do
arquivo, salvando só ~88 verts.

**PROVA de que é o formato, não corrupção:** mascarando os campos p/ o **u16 baixo**, os
`vtx_off` ficam **sequenciais e batem 15/15** com `vtx_count` na aritmética
(`vtx_off[i+1]-vtx_off[i] == vtx_count[i]*8` p/ TODOS os 15 objetos). A região de modelo de
**todos os 69 EMD tem <64 KB** (máx `model_len=28760`), logo todo offset/contagem interno
cabe em 16 bits → mascarar `0xFFFF` é **seguro para os 69** e no-op para os 65 sadios (u16
alto = 0). Idem `tri_count`/`quad_count`: são efetivamente `u8+u8_flag` (máx legítimo nos 69
= 232 < 256); valor `>0xFF` ⇒ byte alto é flag (ex.: EM25 obj19 `qc=0xFD35`→53). Invariante
estrutural usada: `tri_off==quad_off ⇔ 0 triângulos` (a lista de tri vem antes da de quad).

**Correção aplicada em `tools/emd2gltf.py::parse_emd_model`.** EMDs afetados pelas flags:
EM16, EM1E, EM25, EM2D. Resultado do EM2D: **529 verts, 362 faces, 15 ossos, 6 anims, tex
128×256** — íntegro. Asset: `godot/assets/ENEMY/em2d_incerto.glb` (o render, porém, mostra
uma **forma esparsa/angular não identificável** → espécie **BAIXA**). Os 68 demais seguem o
`emd3.h` padrão (agora com a máscara recuperando também EM16/EM1E/EM25 sem anomalias).

**Validação final:** `parse_emd_model` nos 69 EMD → **0 anomalias, 0 arquivos zero-face**;
export completo (`convert`) → **69/69 OK, 0 falhas**, todos com skel+skin+UV (anims em 61/69;
os 8 sem anim são partes/objetos de 1–8 ossos: EM26/EM37?/EM39/EM3B/EM40/EM3E/EM3F/EM64).

### 🐛→✅ FIX do skinning/animação (membros soltos + esqueleto explodindo)

**Sintoma:** na bind pose os inimigos pareciam OK, mas ao ANIMAR os membros ficavam
desconectados (cabeça flutua, braços soltos), e com o overlay de ossos ligado o
**próprio esqueleto explodia** (gizmos espalhados, a malha "voa"). Modelos de 15 ossos
(zumbi `EM10`, `EM2E`, `EM2D`) e de 1 osso pareciam OK; os demais quebravam.

**Causa-raiz (um único campo): o OFFSET e o PASSO do pool de poses estavam FIXOS.**
O `emd2gltf` reusava `pld2gltf.build_anim_clips`/`parse_poses`, que assumem o esqueleto
**humano do PLD**: pool de poses em `skel0 + 176` com passo **76 B/pose** *hard-coded*.
Isso só é verdade para **15 ossos**. O cabeçalho do `emd_skel_header_t` traz, por modelo,
o `move_offset` (`u16 @skel0+2`) e o `move_size`/`frame_size` (`u16 @skel0+6`), que
**variam com o nº de ossos**:

| nº ossos | ex. | `move_offset` | `frame_size` |
|---:|---|---:|---:|
| 10 (corvo) | EM21 | 120 | 56 |
| 15 (humano/zumbi) | EM10 | **176** | **76** |
| 16 | EM35 | 184 | 80 |
| 17 (cão) | EM20 | 196 | 88 |
| 20 (aranha/hunter) | EM25/EM22 | 228 | 100 |
| 21 (drain deimos) | EM28 | 240 | 104 |
| 22 (Nemesis) | EM38 | 256 | ... |

Lendo com `176/76` fixos em um modelo de N≠15 ossos, cada pose caía no **offset errado
com passo errado** → os `s16 root x,y,z` e os 45+ ângulos de 12 bits viravam **lixo**.
Prova (EM35, 16 ossos): a translação de raiz da pose lida a `+176/76` dava
`root.Y = +29440` (e outros ±20000) contra **0** no offset correto (`+184/80`) — como
`SCALE=0.001`, a malha era teletransportada **~29 unidades** (sendo o corpo de ~5.6),
frame a frame, além de girar os membros para ângulos aleatórios. Como as rotações são
limitadas a `[0,2π)`, a **diagonal do AABB** (invariante a translação) mal mudava — por
isso a bind pose enganava e o bug só aparecia ANIMANDO. (O `npose` também era
superestimado, deixando "entrar" sequências que apontavam para poses inexistentes.)

**Correção (`tools/emd2gltf.py::build_emd_clips` + `emd_emr_anims`):** decodificar os
clips lendo `move_offset` e `frame_size` do **cabeçalho do skel** (idêntico ao PS1),
mantendo o RESTO da matemática **exatamente igual ao gabarito** do `pld2gltf`
(ângulos XYZ 12-bit → `Rx·Ry·Rz`, quaternion conjugado por `diag(1,-1,-1)`, rotação
**relativa ao pai** via hierarquia de nós, `inverseBind = T(−world_global)`, 1 osso/vértice
por parte, root in-place mantendo só o bob Y, continuidade de hemisfério). `npose` agora
`= (pool_end − (skel0+move_offset)) / frame_size`, com `pool_end` = próximo offset do
diretório (== `anim1`). Para 15 ossos o resultado é **byte-idêntico** ao anterior
(`move_offset=176, fs=76`) — **zero regressão** no zumbi.

**Validação (numérica + render, 30/07):** harness próprio replica o skinning rígido do
glTF (FK + `inverseBind`) e mede o **maior valor absoluto de coordenada** skinada (pega o
"fly-away", que o AABB-diagonal não pega) no pior frame de todas as anims vs bind:

| modelo | ossos | fly-away ANTES | fly-away DEPOIS |
|---|---:|---:|---:|
| cao_cerberus | 17 | **21.9×** | 1.41× |
| corvo | 10 | **28.7×** | 1.10× |
| em22_hunter | 20 | **17.5×** | 1.43× |
| em28_drain_deimos | 21 | **13.2×** | 1.08× |
| em35_drain_deimos | 16 | **11.6×** | 1.02× |
| aranha | 20 | **10.7×** | 1.20× |
| zumbi/em2e/em2d | 15 | 1.00× | 1.00× (inalterado) |

Montage before/after (opengl3, frame animado no meio da 1ª anim): antes = partes
espalhadas/voando; depois = criatura coerente com os membros atados. **Re-exportados
69/69** preservando os nomes atuais dos arquivos.

### 🐛→✅ RESÍDUO (a): POSE DE REPOUSO (rest) ≠ BIND — hunters/deimos descolados PARADOS

Depois do fix acima, os mobs animavam, mas a validação VISUAL (`scenes/model_probe.tscn`,
`FRAME=rest`) mostrou que os de **20-21 ossos** (EM22/23/24/28 = hunters/deimos) ficavam
COERENTES animando mas ESPALHADOS na pose de repouso (não-animada).

**Causa-raiz:** o `pld2gltf.write_glb` grava o node de cada osso **só com translação**
(rotação = IDENTIDADE), assumindo que a BIND é a pose identidade — verdade só para o
humano (T-pose). Para estas criaturas a identidade é um "espalhado" incoerente; a bind
real é a **POSE 0** (1º frame da 1ª anim). Sem animação tocando, o glTF mostra o default
do node (identidade) → descolado.

**Correção (`write_glb_emd`, writer próprio do emd2gltf):** grava a **rotação de repouso
por osso = pose0**. Com a malha em bind-identidade (`P = vert+world`) e `inverseBind =
T(-world)`, no repouso `globalJoint = G0` (FK com pose0) e o vértice skinado = `G0·(P-world)
= G0·vert_local` = **pose0 coerente**. A animação (rotações absolutas por frame) fica
**matematicamente idêntica** (`Gt·vert_local`) — só o rest muda. Validado: EM22/23/24/28
coerentes em rest E animados.

### 🐛→✅ RESÍDUO (b): CABEÇA/MÃOS/PÉS descolados (partes MODEL-SPACE) + vértices "espeto"

Visual (`FRAME=rest` e frames animados) revelou EM2E/EM34 com **cabeça/pés descolados em
TODOS os frames**. Causa: igual ao `.PLD` (PLD.md §4), a maioria das partes é bone-local
(`+world`), mas **algumas PARTES-FOLHA são autoradas em MODELO ABSOLUTO** — ex.: os PÉS
do EM2E têm raw verts com Y≈1860 == world Y 1844 (bytes conferem). Somar `world` nelas as
DUPLICA → pé voa pra baixo/cabeça pra cima. **Correção (`_is_model_space` em `build_arrays`):**
detecta partes cujo centroide já coincide com o `world` do osso (`|centroide-world| <
0.30·|world|`, com `|world|>400`) e **NÃO** soma offset. Conservador (só dispara quando o
centroide praticamente coincide com o osso) → NO-OP nos bone-local legítimos. Validado:
EM2E/EM34 com cabeça/mãos/pés ATADOS em rest e animados.

**Vértices "espeto" (flung):** EM2C e EM2D (incerto/BAIXA) têm no ARQUIVO vértices
genuinamente anômalos (ex.: EM2C obj4 v13 Y=1321 no meio de uma parte de ~±300; bytes
conferem, não é misread), que viram espinhos. **`_declaw_outliers`** solda ao vizinho
mais próximo os vértices ISOLADOS (NN > max(6× o NN mediano da parte, 500)) — robusto
por parte, NO-OP nas malhas legitimamente esparsas (helicópteros EM3E/EM3F, vermes,
validado nos 69). Fecha EM2D e os poucos espetos de EM36/EM3A.

### Validação VISUAL (obrigatória, `scenes/model_probe.tscn`, opengl3)

Montagens dos 69 em `FRAME=rest` e frames animados (0.25/0.4/0.5/0.75) inspecionadas:
- **Fecharam:** os ~40 NPCs humanos (EM50–EM71, EM2E/EM2F/EM34/EM36…) andam com cabeça/
  membros atados; hunters/deimos (EM22/23/24/28), cão, aranha, corvo, Nemesis, vermes e
  os 2 helicópteros coerentes em rest E animados; zumbis (EM10–EM1F) inalterados.
- **Resíduos honestos (2 modelos incerto/BAIXA):** **EM2C** — corpo monta e conecta, mas
  resta 1 espeto de vértices anômalos AGRUPADOS (obj1/obj4) que heurística segura não
  remove sem arriscar os helicópteros; **EM3A** — 1 peça-extra solta em certas poses (tem
  8 objetos de malha além dos 16 ossos, presos grosseiramente ao último osso; o EM36, de
  geometria idêntica, monta OK — é a pose0 do EM3A que balança a extra). Não são
  regressões deste round; são limitações de dados-fonte/mapa parte→osso desses 2 oddballs.

---

# (Histórico) Malha no `R###.BIN` do PS1 — formato in-RAM (não resolvido)

> Notas de trabalho (agente de malha). Alvo: geometria do **zumbi macho** em
> `STAGE1/R101.BIN` blk0 (modelo, tag `0x80a70000`). Container/EMR/EDD/TIM já
> estavam decodificados; aqui foca-se **só na malha (sec2/sec3/sec4/sec5)**.

## 1. Pesquisa do formato (fontes)

O modelo de personagem/inimigo do RE clássico é o **EMD** (não o `MD1`/PLD do
player). O EMD é um contêiner com diretório; a geometria é do tipo **TMD** da Sony
(vértices/normais em arrays separados + primitivas com UV/CLUT/tpage). Skinning é
**rígido** (1 objeto de malha por osso; vértices em espaço LOCAL do osso, sem pesos).

Fontes:
- `pmandin/reevengi-tools` — código C com as **structs exatas do RE3**
  (`src/emd3.h`, `src/emd_common.h`, parser em `src/emd2xml.c :: emd3AddModel`).
- Wiki `pmandin/reevengi-tools` — `.EMD (Resident Evil 2 PC)` (structs de triângulo/quad/UV).
- `justsolve.archiveteam.org` — `EMD (Resident Evil 1997)`.
- Repos de visualizadores: `LeonamMiiller/rE2MD`, `MeganGrass/bioclone-remake`.

### Structs do RE3 (reevengi `emd3.h`) — formato do EMD **standalone**

```c
emd3_model_header_t { u32 length; u32 count; }              // count = nº de objetos (≈ por osso)
emd3_model_object_t {                                        // 24 bytes; offsets relativos a &model_obj[0]
    u32 vtx_offset; u32 nor_offset; u32 vtx_count;
    u32 tri_offset; u32 quad_offset; u16 tri_count; u16 quad_count;
}
// vertices e normais: emd_vertex4_t = { s16 x,y,z; s16 pad } (8 bytes)
emd3_triangle_t {   // 12 bytes
    u8 tu0,tv0; u8 page,dummy0; u8 tu1,tv1; u8 clutid,v0; u8 tu2,tv2; u8 v1,v2;
}
emd3_quad_t {       // 16 bytes
    u8 tu0,tv0; u8 page,dummy0; u8 tu1,tv1; u8 clutid,dummy1;
    u8 tu2,tv2; u8 v0,v1; u8 tu3,tv3; u8 v2,v3;
}
```

**IMPORTANTE:** o modelo embutido no `R###.BIN` **NÃO** é um EMD standalone. O
diretório do sub-contêiner tem 8 entradas; o `emd3_directory_t` tem 15. O loader de
sala do RE3 **reempacota** a malha num formato in-RAM próprio (abaixo). Não há em
lugar nenhum do bloco um array de vértices `emd_vertex4_t` (8B com pad==0) — varredura
confirmou (só runs minúsculos de 8/15/26 verts em sec1/3/7, que são pose/relpos).

## 2. Container do modelo — 8 seções (✅ confirmado)

| Sec | Tam (R101 blk0) | Constante entre salas? | Papel |
|----:|----:|:--:|---|
| 0 | 31872 | não | EMR + poses A (esqueleto 15 ossos, fs=76) |
| 1 | 1072 | não | EDD A (animações) |
| **2** | **22576** | **sim** | **malha: payload (16 objetos, 432 registros de 52B)** |
| **3** | **996** | **sim** | **malha: TABELA de objetos de sec2** |
| **4** | **3548** | **sim** | **malha: payload (4 objetos, 108 registros de 32B)** |
| **5** | **252** | **sim** | **malha: TABELA de objetos de sec4** |
| 6 | 26552 | não | EMR + poses B |
| 7 | 1008 | não | EDD B |

Verificado por diff entre `R101` e `R103` (mesmo zumbi): sec2/3/4/5 **byte-idênticas**
(geometria constante); sec0/1/6/7 diferem (conjuntos de animação por sala). Isso prova
que sec2..5 são a MALHA.

## 3. Tabelas de objetos sec3 / sec5 (✅ decodificado)

Cada tabela é um array de registros de **8 bytes** seguido de uma lista de índices:

```
registro (8B): { u16 count ; u16 off_idx ; u16 off_elem ; u16 pad(=0) }
  count     = nº de elementos do objeto (nº de vértices)
  off_idx   = offset (bytes) p/ a lista de índices do objeto; passo = 2*count
  off_elem  = índice acumulado do 1º elemento no array de payload; passo = count
n_objetos = off_idx[0] / 8        (a tabela termina onde a lista de índices começa)
```

Resultados (auto-consistentes, casam EXATAMENTE com o tamanho do payload):
- **sec3** → `n=16` objetos, counts `[34,34,20,20]×4`, soma = **432**
  → `sec2 = 112 (obj0) + 432*52` = 22576 ✔
- **sec5** → `n=4` objetos, counts `[34,34,20,20]`, soma = **108**
  → `sec4 = 92 (obj0) + 108*32` = 3548 ✔

Nota: sec2 = **4×** o conjunto de sec4 (432 = 4×108; 16 obj = 4×4 obj). Os 16 objetos de
sec2 ≈ 15 ossos (+1) → coerente com skinning rígido (1 malha por osso). Provável:
sec4 = malha base / LOD baixo (4 partes), sec2 = malha detalhada por osso (16 partes),
ou sec4 = vértices e sec2 = primitivas — **não resolvido**.

## 4. Payload sec2 (52B/reg) e sec4 (32B/reg) — ⛔ ENCODING NÃO RESOLVIDO

Cada seção começa com um **obj0 "limpo"** decodificável:
- header 12B `{u16 f0, u16 f1, u16 A=fim_dos_verts, u16 B, u16 nVerts, u16 C}`,
  depois `nVerts` vértices de **6 bytes** (`s16 x,y,z`, sem pad), depois UVs e índices.
- sec2 obj0: nVerts=9, 2 quads. Verts limpos e simétricos em Z, ex.:
  `(-43,-611,-305)` e `(-43,-611,305)`. sec4 obj0: nVerts=7.

Depois do obj0 vem o **stream de registros de tamanho fixo** (52B em sec2, 32B em sec4),
indexado pelas tabelas. Aqui a decodificação **emperrou**: os registros NÃO mapeiam
para `(x,y,z)` plano por nenhuma combinação de colunas s16 testada.

Análise coluna-a-coluna (s16) de sec4 (32B, 108 reg), registro 0 =
`[30, -1810, 0,0, 73, 0,0, 4243, -4096, 1023, 700, -4408, -554, -3385, -920, 553]`:
- **col0** = contador que sobe ~+32/reg (30,62,94,126…) e atinge o MESMO máximo (~2160)
  em sec2 (432 reg) e sec4 (108 reg) — logo é um **valor/arco compartilhado**, não índice.
- **col1** ≈ Y perto da raiz (-1810…), varia suave.
- **col8** = `-4096` no reg0 (=-1.0 em 1.12) → cheira a componente de **normal**, mas a
  magnitude do triple candidato não fecha unitária nos registros seguintes.
- várias colunas têm valores "aleatórios" de 16 bits (±32000) intercalados com colunas
  suaves → indício de **bit-packing** (normal/GTE empacotado) misturado a coords planas.

Testes de nuvem de pontos (frente/lado), inclusive coloridos por objeto (para ver
clusters locais de osso) e escolhendo colunas de "faixa corporal" (span 300–3000):
**nenhuma combinação produziu silhueta humanoide**. As colunas suaves individualmente
formam curvas coerentes por objeto (limbos vistos de perfil em col8..col10), mas sem
transform de osso e sem o encoding de posição correto não fecham num corpo.

### Hipóteses para o próximo passo
1. **Bit-packing PS1/GTE**: a posição pode estar empacotada (ex.: 3× ~11 bits, ou
   `s16` escalados) e/ou a normal num único `u32`. Tentar desempacotar por bits.
2. **Registros são PRIMITIVAS, não vértices**: 52B ≈ quad com 4 verts + normais + UV
   inline (formato RE1997 `emd_triangle_t` tem tudo inline). Nesse caso os vértices
   reais estariam na lista `off_idx` das tabelas (passo 2×count) — investigar essa lista
   (em sec3/sec5, região após a tabela; em sec3 ocupa 128..~992, ~2B por vértice).
3. **Comparar com ground-truth**: extrair o mesmo zumbi como `.EMD` standalone da ISO
   do RE3 PS1 via `reevengi-tools iso_search` (formato `emd3.h`, verts de 8B, limpo),
   renderizar, e casar contagens/valores para deduzir a transformação in-RAM.

## 5. Ferramenta

`tools/bin2gltf.py mesh <R###.BIN> <blk>` — decodifica container + tabelas sec3/sec5,
lista objetos e faz dump do obj0 limpo de sec2/sec4. (O stream empacotado fica marcado
como pendente conforme §4.)
