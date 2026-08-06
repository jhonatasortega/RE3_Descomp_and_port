# EMD/PLD — regra de skinning: objeto→osso e espaço dos vértices (RE3)

> Objetivo: substituir a heurística `_is_model_space`/`bone = nb-1` do `tools/emd2gltf.py`
> pela **regra real** com que o RE3 amarra cada objeto de malha ao osso. Fontes: (1) código
> **reevengi** (`pmandin/reevengi` + `reevengi-tools`, referência autoritativa do formato
> `emd3`), (2) medição byte-a-byte dos 69 `EM##.EMD` do port PC/GOG, (3) EXE `SLUS_009.23`
> (parcial — só localizei os clusters GTE), (4) o gabarito já provado do `.PLD` (PLD.md §4).
>
> **NÃO editei `emd2gltf.py`.** Só este documento. As recomendações de código estão em §7.

---

> ## ⚠ LEIA A §13 ANTES DE TUDO
> As §0–§12 concluem que o binding vértice→osso é irrecuperável do `.EMD` do PC e que só
> resta heurística. **Isso está ERRADO.** O dado está na seção **`dir[0]`** do próprio EMD
> (o `unknown0[0]` do reevengi), com bitmask de objetos multi-osso, tabela de coordenadas
> `-world[i]` e listas `[osso][nbatches][índices de vértice]`. Já está decodificado,
> validado e **aplicado** em `tools/emd2gltf.py`. As §0.2, §3, §6, §7.3, §7.4, §10.7,
> §11.3 e §12.4/§12.5 ficam **superadas** para os 41 EMD que têm a seção.

---

## 0. TL;DR (o que corrigir)

1. **Mapa objeto→osso é POSICIONAL 1:1 para os objetos `0..nb-1`: objeto `i` ⇔ osso `i`.**
   Não há tabela de mapeamento no arquivo. (Autoritativo: reevengi; prova local §2.)
2. **Objetos EXTRA (`i ≥ nb`) NÃO existem no formato canônico** (reevengi assume
   `nº objetos == nº ossos`). Nos EMD do RE3 que têm extras, eles **não são referenciados
   pela hierarquia do esqueleto** (a *child-list* da armadura só cita índices `< nb`) e
   **não têm ângulos de animação** (o passo de pose cobre só `nb` ossos). São peças
   acessórias (tampas de junta, espinhos, casaco). O bug atual (`bone = nb-1` para todo
   extra) empilha TODOS no último osso → mangla Nemesis/hunters/humanos-com-+1. Ver §3 e §7.
3. **A transformação vértice→mundo autoritativa é BONE-LOCAL com a MATRIZ COMPLETA do osso**
   (rotação acumulada + translação acumulada da cadeia pai→filho). NÃO é "somar um offset".
   Prova: reevengi (§4) + o zumbi `EM10` fecha em 0,000 exatamente com essa regra (§5).
4. **PORÉM o "model-space" NÃO é 100% mito:** ~metade do roster (sobretudo os **humanoides
   NPC EM50–EM71** e alguns insetoides/vermes) guarda **partes** em espaço-modelo absoluto,
   igual ao `.PLD` do player (PLD.md §4). O EMD **não tem flag por-objeto** que diga isso —
   logo o motor decide pelo **caminho de desenho** (personagem vs criatura), que eu **não
   isolei** no EXE. Um conversor stand-alone **não consegue eliminar 100% a heurística** só
   com o arquivo; dá pra torná-la muito mais robusta e ancorá-la na regra real (§6, §7).

---

## 1. Estruturas (reevengi — autoritativo)

Confirmado lendo o código-fonte real (o wiki do reevengi-tools está incompleto — as páginas
de formato retornam 404). Dois repositórios, branch `master`:
- `reevengi-tools/src/emd3.h`, `src/emd_common.h`, `src/emd2xml.c` — dumper (parser puro).
- `reevengi/src/g_re3/emd.c`, `src/r_common/render_skel.c` — **o viewer** (carrega + skina +
  desenha o esqueleto). É este que responde o mapeamento e o espaço dos vértices.

```c
/* reevengi-tools/src/emd3.h */
typedef struct { Uint32 length; Uint32 count; } emd3_model_header_t;   /* count = nº de OBJETOS de malha */
typedef struct {
    Uint32 vtx_offset; Uint32 nor_offset; Uint32 vtx_count;
    Uint32 tri_offset; Uint32 quad_offset; Uint16 tri_count; Uint16 quad_count;
} emd3_model_object_t;                                                  /* 24 B — SEM campo de osso */
/* índices de vértice em RE3 são u8 (v0,v1,v2[,v3]); em RE2 eram u16 */

/* reevengi-tools/src/emd_common.h — esqueleto compartilhado (não há emd3_skel_header) */
typedef struct { Uint16 relpos_len; Uint16 move_offset; Uint16 count; Uint16 move_size; } emd_skel_header_t;
typedef struct { Uint16 num_mesh; Uint16 offset; } emd_armature_header_t;  /* num_mesh = nº de FILHOS */
```

`count` (osso) e `move_size` (passo de pose) são exatamente o que o `emd2gltf` já lê em
`skel0+4` e `skel0+6`. O `emd3_model_object_t` de 24 B está **inteiramente contabilizado**
(5×u32 + 2×u16) — **não há byte sobrando para um índice de osso nem para uma flag de
espaço**. Verificado nos 69 EMD: o `u16` alto de cada campo é 0 (salvo a variante com flags
já tratada em `parse_emd_model`), e o array de objetos é **contíguo** (offsets sequenciais),
sem tabela de mapeamento antes/depois.

---

## 2. Mapa objeto→osso = POSICIONAL 1:1 (objeto i ⇔ osso i)

**Autoritativo (reevengi `g_re3/emd.c`, `emd_load_render_skel`, L205–357):** o laço percorre
`emd_mesh_header->num_objects` e, para o objeto `i`, faz:

```c
skeleton->addMesh(skeleton, mesh,
    emd_skel_relpos[i].x, emd_skel_relpos[i].y, emd_skel_relpos[i].z);  /* usa relpos do osso i */
```

→ o objeto `i` é guardado no **slot `i`** do esqueleto com a **posição relativa do osso `i`**.
Na animação, o mesmo índice indexa os ângulos (`getAnimAngles(this, num_mesh=i, …)`). Ou seja
**relpos, ângulos e malha compartilham UM índice** → `objeto i ⇔ osso i`, rígido, 1 malha por
osso. **A armadura (`num_mesh`+`offset`) NÃO mapeia malha↔osso — ela só codifica a hierarquia
pai→filho** (a lista de filhos é um array de bytes = índices de osso).

**Prova local (armadura dos EMD, `child pool`):** dump da *child-list* de cada osso mostra que
a soma de `num_mesh` == `nb-1` em TODOS os casos (uma árvore de `nb` nós tem `nb-1` arestas),
e **todos os índices de filho são `< nb`**. Ex.:

| EMD | nb | objs | soma(num_mesh) | índices de filho ≥ nb? |
|-----|---:|-----:|---------------:|:----------------------:|
| EM10 | 15 | 15 | 14 | não |
| EM50 | 15 | 16 | 14 | não |
| EM36 | 16 | 24 | 15 | **não** |
| EM38 (Nemesis) | 22 | 31 | 21 | **não** |
| EM22 (hunter) | 20 | 21 | 19 | não |

Logo a hierarquia **nunca alcança** os objetos extra. Confirma reevengi: o esqueleto desenhado
= exatamente os ossos `0..nb-1`, um objeto cada.

---

## 3. Objetos EXTRA (nº objetos > nº ossos)

27/69 EMD têm `objs > nb`. **Isto está FORA do formato canônico do reevengi** (que assume
`num_objects == count`; se exceder, `emd_skel_relpos[i]` lê fora do array e o objeto extra
**nunca é desenhado**, pois não está na hierarquia). Constatações locais:

- Os extras **não estão na hierarquia** (§2) e **não têm ângulos de pose**: o `move_size` cobre
  só `nb` ossos (ex.: EM36 `move_size=80` = 8 B header + 16 ossos × 3 × 12 bits = 72 B; os 8
  extras não têm canal). Então extras são **estáticos/acessórios**, não animados por osso próprio.
- Geometricamente são peças pequenas: tampas de junta, espinhos, tiras, casaco.
  - `PL00.PLD` (player, gabarito): 21 objs / 15 ossos → **6 extras**, todos com **centroide
    exatamente (0,0,0)** e 8 verts (pinos de junta). O `pld2gltf._extra_bone_map` os **ancora
    na raiz** (`{i:0}`) e permite descartá-los (`PLD_DROP_EXTRAS`) — ou seja, o próprio
    gabarito PS1 **NÃO tem o mapa real**; ele esconde os extras. **Não é fonte autoritativa
    para extras.**
  - `EM38` (Nemesis): 9 extras — obj23–26 centroide (0,0,0) 12 verts; obj27–30 com posição real.
  - `EM36`/`EM3A`: 8 extras — obj16–21 (6× 18 verts, centroide ~(0,799,0)); obj22 (78 v, ==obj2),
    obj23 (20 v, ==obj4).

**Conclusão sobre extras:** o arquivo EMD **não codifica** o osso-alvo dos extras. Quem sabe é
o **loader/draw do EXE** (não isolado). Para o conversor, ver a recomendação best-effort em §7.4.
O bug atual (`bone = nb-1`) é objetivamente errado — joga o casaco do Nemesis / o +1 dos humanos
todos no último osso.

---

## 4. Transformação vértice→mundo (BONE-LOCAL, matriz completa)

**Autoritativo (reevengi `r_common/render_skel.c`, `draw(this, num_parent)`, L186–221):**

```c
render.push_matrix();
render.translate(skel_mesh->x, skel_mesh->y, skel_mesh->z);   /* relpos do osso (relativo ao PAI) */
render.rotate(ang[0]*360/4096, 1,0,0);                        /* ângulos 12-bit do frame atual */
render.rotate(ang[1]*360/4096, 0,1,0);                        /* ordem X, depois Y, depois Z    */
render.rotate(ang[2]*360/4096, 0,0,1);
skel_mesh->mesh->draw(...);                                    /* vértices desenhados no frame LOCAL */
for (child ...) draw(this, child);                            /* filhos herdam a matriz (antes do pop) */
render.pop_matrix();
```

Regras que saem daí (e **batem com o `pld2gltf`/`gbind` já usado**):
- **Vértices são BONE-LOCAL** — entregues à malha SEM pré-transformar (emd.c L231). Ficam no
  referencial do próprio osso.
- **Composição pai→filho:** por osso, `T(relpos_i) · Rx · Ry · Rz`; empilhado (push/pop). A
  matriz global do osso `i` é o produto ao longo da cadeia raiz→…→i. Translações são
  **relativas ao pai** (== `relpos`). O `emd2gltf.gbind` já faz exatamente isso (FK com
  `node_translation` + `bind_rot` por quatérnio; `_mm`/`_mv`).
- **Colocação do modelo inteiro:** raiz = osso 0; o `getAnimPosition` só usa o **Y** (x=z=0) —
  igual ao "root in-place, só bob Y" do `build_emd_clips`.
- **Ângulos:** 12-bit, `4096 = 360°`, ordem **XYZ**. Idêntico ao PS1/PLD.

**Portanto a regra correta para os objetos `0..nb-1` é:**
`v_mundo = Gbind[i] · v_local` (matriz COMPLETA do osso i, com rotação da bind), e o skin do
glTF usa `inverseBind[i] = Gbind[i]⁻¹`. **Nada de "somar `world[i]`"** como caso especial — o
`emd2gltf.build_arrays` já faz isso no ramo `else` (`mv = R·v; pos = mv + t`). O ramo
`model_space` (só `v`) é o que precisa sair (ver §6).

---

## 5. Prova numérica (EM10 bone-local vs EM50/EM2E model-space)

Medi o pé (obj11, osso 11) sob a regra bone-local (matriz completa da bind, `Gbind`) vs deixar
o vértice cru (model-space). Escala glTF (`SCALE=0.001`, `y→-y`). Junta do tornozelo (bind) em
`tg[11].y`:

| EMD | tg[11].y (tornozelo) | pé cru (model-space) cen.y | pé bone-local+bind cen.y | veredito |
|-----|---------------------:|---------------------------:|-------------------------:|----------|
| **EM10** (zumbi) | −1,782 | **−0,133** (na origem/quadril) | **−1,915** (logo abaixo do tornozelo ✔) | **BONE-LOCAL** |
| EM50 (NPC humano) | −1,498 | **−1,674** (já no tornozelo ✔) | −2,896 (voa p/ baixo ✘) | **MODEL-SPACE** |
| EM51 (NPC humano) | −1,498 | −1,672 (no tornozelo ✔) | −2,895 (voa ✘) | **MODEL-SPACE** |
| EM2E | −1,782 | −1,861 (no tornozelo ✔) | −3,644 (voa ✘) | **MODEL-SPACE** |

- **EM10** (que fecha em 0,000): o pé cru está na **origem** (verts pequenos, relativos à junta)
  → **precisa** da matriz completa do osso p/ ir ao pé. Bone-local **puro**, como manda a spec.
- **EM50/EM2E**: o pé cru **já está** na posição do tornozelo (mesma esqueleto, mesma junta
  −1,5). Aplicar a matriz do osso **DUPLICA** a translação → o pé "voa". Verts em **espaço-modelo
  absoluto**, exatamente como o `.PLD` do player (PLD.md §4).

Full-body (todos os objs): EM2E cru = corpo coerente Y∈[−2,07 .. 1,22] (~3,3 alto); EM10 cru =
colapsado Y∈[−0,97 .. 0,82] (~1,8, membros empilhados na origem). Confirma: **EM10 = bone-local,
EM50/EM2E = model-space.** Mesmo esqueleto, mesma rest-pose (tg idêntico), **autoria diferente**.

> O `_is_model_space` atual dispara SÓ nos pés (obj11/14) da família humana (EM2E, EM50…) e em
> obj2 de EM34/EM36 — e em **NENHUM** objeto dos hunters EM22/EM24. Logo o "vão de ~0,16 no
> braço dos hunters" **NÃO vem do model-space** — vem da **bind-pose/costura rígida** (resíduo
> "a"), não deste eixo. Não adianta mexer no model-space para fechar o hunter.

---

## 6. Por que não dá pra "só usar a regra real" e zerar a heurística

> **⚠ Ver §10 (EXE decompilado).** A conclusão prática desta seção (o conversor precisa de dica
> externa) **continua válida**, mas o MOTIVO mudou: não são "dois paths de desenho"; é que o
> binding **osso-por-primitiva** do PS1 foi **descartado** pelo EMD *standalone* do PC. A
> hipótese "personagem model-space × criatura bone-local" está **REFUTADA** no binário (§10.0).

Tensão honesta entre as fontes:
- **reevengi** (autoritativo do formato) diz **tudo bone-local, uniforme, sem flag de espaço**.
  Mas o suporte a **RE3** no reevengi é **parcial/não-validado** (wiki de RE3 = 404). O viewer
  desenharia EM50 com a regra bone-local → o pé **voaria** (a matemática acima prova). Se o
  reevengi nunca testou um EM50, ele simplesmente **não cobre** esse caso.
- **Medição** prova que EM50/EM2E têm partes em model-space absoluto (§5), igual ao `.PLD`.
- **O EMD não tem flag por-objeto** (24 B contabilizados, armadura = hierarquia). Então o motor
  **não lê do arquivo** qual convenção usar — ele decide pelo **CAMINHO DE DESENHO**:
  hipótese forte = **personagens humanos (PLD do player + NPCs EM50–71) desenhados pelo path de
  personagem (model-space/pivô, PLD.md §4)** e **criaturas (zumbi, cão, hunter, aranha…)
  desenhadas pelo path de inimigo (bone-local, reevengi §4)**. Coerente com EM50–71 serem humanos
  autorados como o player.

**EXE (parcial):** localizei os clusters GTE — a **biblioteca GTE** (RotTrans/matrizes) em
`0x80088000–0x8008a200`, as **primitivas de transform de vetor** (`lwc2/swc2/mtc2` + cop2) em
`0x8007b000–0x8007ce00`, e os **clusters de desenho de alto nível** em `0x80026000–0x80029000`
e `0x8002c800–0x8002d600` (que chamam as primitivas). **NÃO decompilei** o laço por-objeto que
lê o struct de 24 B, então **não confirmei no binário** se há um branch de espaço por-objeto ou
dois paths de desenho. Isso fica como pendência (§8) — é o único jeito de **fechar 100%** e
eliminar de vez qualquer heurística.

**Consequência prática:** um conversor stand-alone (só o arquivo `.EMD`) **não tem como saber a
convenção sem uma dica externa**. Opções: (a) heurística robusta por-parte, ou (b) uma
**flag curada por-modelo** (bone-local vs model-space) numa tabela do projeto (ex.:
`sce_enemies.json`), derivada da classificação de §5. A (b) é a única forma de zerar a heurística.

---

## 7. Recomendação para `emd2gltf.build_arrays` (não apliquei — você aplica)

### 7.1 Objetos `0..nb-1`: manter 1:1 (`bone = i`) — já correto e autoritativo.

### 7.2 Ramo bone-local: manter EXATAMENTE como está (matriz completa)
`pos = R·cvt(v) + t` com `(R,t)=Gbind[i]`. É a regra real (§4). Zumbis/cão/aranha/hunter etc.

### 7.3 Model-space: NÃO eliminar cegamente — mas TORNAR PRINCIPIADO
O `_is_model_space` compara o centroide com `world[bone]` (acumulação **sem rotação**). Em mobs
com bind rotacionada (hunters, deimos, Nemesis) `world != tg` (a junta posada), então o teste é
**impreciso**. **Melhoria concreta:** comparar o centroide com a **junta POSADA da bind**
`tg[bone]` (que `build_arrays` já tem via `gbind`), não com `world[bone]`:

```
# dentro de build_arrays, já existem Rg,tg:
jx,jy,jz = tg[bone]                         # junta na BIND (com rotação), em espaço glTF
c = centroide(cvt(v) for v in vclean)       # centroide já em espaço glTF
jmag = |(jx,jy,jz)|
model_space = (jmag > 0.4) and |c - (jx,jy,jz)| < 0.30*jmag
if model_space:
    P_.append(cvt(v)); N_.append(cvtn(n))                    # espaço-modelo absoluto
else:
    P_.append(Rg[bone]·cvt(v) + tg[bone]); N_.append(Rg[bone]·cvtn(n))   # bone-local, matriz completa
```

Isso **reduz misfire** nos mobs de bind rotacionada e mantém o comportamento nos de 15 ossos.
(O `inverseBind = Gbind⁻¹` do `write_glb_emd` **já casa** com os dois ramos: no ramo model-space
o vértice fica cru e o `Gbind⁻¹·Gbind = I` no repouso; no bone-local idem. Não mudar o writer.)

**Melhor ainda (elimina a heurística):** classificar **por-modelo** uma vez (offline, com o teste
de §5 — corpo cru coerente ⇒ model-space; corpo cru colapsado ⇒ bone-local) e gravar a flag em
`godot/data/sce_enemies.json` (`emd_annotations[EMxx].vertex_space`). O `build_arrays` lê a flag
e aplica o ramo certo **para o modelo inteiro**, sem adivinhar por-parte. É a forma de ter regra
determinística sem o EXE. (A classificação por-parte de §5 é ruidosa para os 15-ossos humanos —
os braços em pose0 confundem centroide×world — então **classificar por-modelo é mais estável**.)

### 7.4 Objetos EXTRA (`i ≥ nb`): PARE de usar `bone = nb-1`
Eles não têm osso próprio no formato (§3). Best-effort determinístico, muito melhor que "tudo no
último osso":

1. Trate o extra como **model-space** (coloque `cvt(v)` cru — a maioria tem posição real no corpo).
2. **Vincule ao osso cuja junta posada `tg[b]` é a mais próxima** do centroide posado do extra:
   `bone_bind = argmin_b |centroide - tg[b]|`. Assim o espinho/tira/casaco segue a junta correta
   ao animar, em vez de orbitar preso ao pé.
3. Para extras de **centroide (0,0,0)** (tampas de junta tipo `PL00`), `argmin` cai na raiz/quadril
   — equivalente ao que o `pld2gltf` já faz (esconder na raiz). Aceitável; ou descarte-os
   (equivalente ao reevengi, que nunca os desenha) com um `EMD_DROP_EXTRAS`.

Resultado esperado: Nemesis (EM38), EM36/EM3A, hunters (EM22) e humanos-com-+1 deixam de manglar.

---

## 8. Incertezas (honesto)

> **⚠ SUPERADO PELA §10 (laço decompilado).** O laço de desenho por-objeto foi **decompilado**:
> há **UM só path** (não dois), a transformação é **uniformemente bone-local com matriz cheia**,
> e o binding vértice→osso é **por índice explícito na primitiva** (o EMD do PC perde isso). O
> "model-space" de §5 é **artefato da perda desse binding**, não um 2º caminho. Ver §10.

- ~~**NÃO fechei no EXE** o laço de desenho por-objeto (só localizei os clusters GTE, §6). Logo a
  existência de **dois paths de desenho** (personagem model-space vs criatura bone-local) é
  **hipótese forte, não provada no binário**.~~ **RESOLVIDO em §10: hipótese FALSA (um só path).** É a pendência que fecharia 100% a regra e removeria
  qualquer heurística. Caminho: seguir os chamadores de `0x8007b2fc/0x8007b518/0x8007b824`
  (primitivas de transform) subindo até o laço que lê `model+4` (count) e o struct de 24 B; e
  achar quem escolhe entre o path do player (`player+0x108/0xe8`) e o do inimigo (work-struct 0xD4).
- **Model-space por-parte vs por-modelo:** os pés dos humanos são model-space provados (§5); não
  verifiquei parte-a-parte se o humano é *inteiro* model-space ou misto. A classificação por-modelo
  de §7.3 (corpo cru coerente) é o teste mais robusto que tenho; a por-parte é ruidosa.
- **reevengi vs medição:** onde divergem (reevengi diz tudo bone-local; medição mostra model-space
  em humanos), a **medição** vence para os arquivos RE3 reais — reevengi tem RE3 parcial. Mas a
  regra bone-local de reevengi está **provada correta** para as criaturas (EM10=0,000) e é o
  **default** certo.

## 9. Endereços/fontes (índice)

- reevengi `g_re3/emd.c`: `emd_load_render_skel` L161–362 (addMesh c/ `relpos[i]` L352–357),
  `getChild` L364–398 (child-list = bytes de índice de osso), `getAnimPosition` L456–512 (só Y),
  `getAnimAngles` L514–587 (12-bit).
  `r_common/render_skel.c`: `draw` L186–221 (translate→rotX→rotY→rotZ→draw→recursão), `addMesh` L162–184.
  `reevengi-tools/src/emd3.h`, `src/emd_common.h` (structs); `src/emd2xml.c` `emd1AddArmature`
  L290–315, `emd3AddModel` L1112–1153 (loop de `count` inteiro; RE3 **não** tem o `>>1` do RE2 @L731).
- EXE `SLUS_009.23` (base `0x80010000`): GTE lib `0x80088000–0x8008a200`; primitivas de transform
  de vetor `0x8007b000–0x8007ce00` (`0x8007b2fc/518/824` = funções-folha chamadas 2×); clusters de
  desenho de alto nível `0x80026000–0x80029000`, `0x8002c800–0x8002d600`. Laço por-objeto: **não
  decompilado**.
- Gabarito PS1: `docs/formatos/PLD.md §4` (player = model-space, `inverseBind=T(-world)`);
  `tools/pld2gltf.py` `parse_emr`/`assemble`/`_extra_bone_map` (extras ancorados na raiz).
- Medições: `tools/emd2gltf.py` (`parse_emd_model`, `gbind`, `_is_model_space`) sobre
  `C:/tmp/re3pc_emd/EM##.EMD` (extraídos de `Rofs9.dat`).

---

## 10. Laço de desenho do EXE — **DECOMPILADO** (fecha a pendência de §6/§8)

> Feito estaticamente sobre `extracted/ntsc-u/SLUS_009.23` (base `0x80010000`) com capstone +
> um decodificador de COP2/GTE próprio (capstone **não** decodifica RTPS/RTPT/MVMVA nem
> `ctc2/lwc2/swc2` — foi preciso decodificar o opcode `0x12`/`0x32`/`0x3a` à mão). Todos os
> endereços abaixo foram lidos no binário; o disasm-chave está reproduzido.

### 10.0 TL;DR do que o EXE prova (revê §6 e §8)

1. **Existe UM só caminho de desenho** para TODOS os atores (player E inimigos): o laço de
   atores em `0x8002412c` desenha cada ator ativo da mesma forma. **A hipótese de "2 paths
   (personagem × criatura)" de §6 é FALSA no binário** — não há bifurcação personagem/criatura.
2. **A transformação de vértice é UNIFORMEMENTE BONE-LOCAL, com a MATRIZ COMPLETA do osso**
   (rotação acumulada + translação). Toda primitiva carrega os vértices para a tela via
   `R_ator × Mundo[osso]` no GTE (MVMVA/RTPT). **NÃO há ramo "model-space/posição absoluta"
   no código de desenho.** (Prova: §10.2–10.3.)
3. **O binding vértice→osso na malha in-RAM do PS1 é por ÍNDICE EXPLÍCITO, não posicional.**
   Cada grupo de primitivas começa com um **byte de índice de osso** e é terminado por `0xFF`;
   o motor busca `no[idx]+0x40` (matriz-mundo daquele osso) por grupo. Ou seja, uma malha pode
   referenciar VÁRIOS ossos. O "objeto i ⇔ osso i" (§2, reevengi) é o **caso comum**, não uma
   regra do formato in-RAM. Isto explica extras e partes multi-osso **sem** flag de espaço.
4. **A hierarquia é feita por PONTEIRO-DE-PAI, não por push/pop nem recursão.** Cada nó guarda
   um ponteiro para a matriz-mundo do pai (`no+0x6c`) e faz `Mundo[i] = Pai ∘ Local[i]`.

### 10.1 As duas varreduras da armadura (FK e DRAW) — endereços

O ator tem, em `ator+0x108`, um **array de nós de 188 bytes (0xBC)**; `ator+0x08` = **nº de nós
(= nº de ossos, `nb`)**. Há dois laços **idênticos em forma** (mesmo `count`, mesmo passo 0xBC):

| passo | função laço | por-nó | o que faz |
|---|---|---|---|
| **FK / pose** | `0x800251fc` | `0x800253f0` | escreve `no+0x40` = **matriz-MUNDO** do osso |
| **DRAW**      | `0x800254ac` | `0x80025610` | lê `no+0x40`, joga no GTE, desenha o objeto |

Cadeia de chamada do DRAW (topo→folha), toda confirmada por `jal`:
```
0x80023268  (dispatcher de frame; chama 0x800245a0 setup e depois…)
  └ 0x8002412c  laço de ATORES: p/ cada ator ativo em [ator_array]:
        lw a1, 0x108(ator)   ; a1 = array de nós (188 B) = a "armadura em RAM"
        lw a2, (ator)        ; a2 = flags do ator
        jal 0x80078ba4       ; LOD/cull por distância (NÃO é PushMatrix — 0x80078c5c eleva ao quadrado deltas)
        jal 0x80089084       ; SetLightMatrix (carrega L11..L33 no GTE, p/ normais)
     └ 0x800254ac  laço de NÓS (count = ator+8, passo 0xBC):
           lhu a2, 0xa2(no)  ; a2 = FLAGS POR-NÓ  (a decisão por-objeto vem daqui)
        └ 0x80025610  transforma+desenha UM nó:
              (compõe R e TR no GTE a partir de no+0x40; ver §10.2)
           └ 0x80025de8  despacha por tipo de primitiva (flags no+0xa2: 0x400/0x40/0x80/0x04)
              └ 0x8007a350 / 0x8007a490  desenha as primitivas de um objeto
                 └ 0x8007b2fc/518/824, 0x8007c434/91c  FOLHAS GTE (RTPT/NCCT/MVMVA)
```

### 10.2 Como a matriz por-osso é montada (FK) — `0x800253f0` (PROVA)

Layout do nó de 188 B (campos confirmados por uso):

| offset | tipo | papel |
|---|---|---|
| `+0x00` | u32 | flags do nó (bit0 = ativo/desenhar; bit4 = tem escala) |
| `+0x14` | matriz | **matriz LOCAL** do osso (5 words `R` empacotado `0x14..0x24` + trans `s16` em `0x28`) — vem da pose (RotMatrix dos ângulos 12-bit) |
| `+0x40` | matriz | **matriz-MUNDO** do osso (saída da FK): `R` em `0x40..0x50`, translação em `0x54` |
| `+0x6c` | ptr | **ponteiro p/ a matriz-mundo do PAI** (do nó pai; do osso-raiz aponta p/ a matriz-raiz do ator, `ator+0x20`) |
| `+0x9c..0xa0` | s16×3 | **escala** X,Y,Z (aplicada por ScaleMatrix se bit4) |
| `+0xa2` | u16 | **FLAGS DE DESENHO por-objeto** (ver §10.3) |
| `+0xa4` | ptr | ptr p/ estado do objeto (checa `*(*+0xa4)&9 == 8`) |
| `+0xa8` | ptr | ptr p/ os **dados da malha** do objeto (usado em `0x8007a350`) |

`0x800253f0` (per-nó FK), trecho central:
```
lw   a0, 0x6c(no)      ; a0 = ponteiro p/ matriz-MUNDO do PAI
addiu a1, no, 0x14     ; a1 = matriz LOCAL deste osso
andi v0, s2, 2         ; s2 = flags-de-nó passadas
bnez v0, +skip
jal  0x8002d4b0        ; a2 = no+0x40  ->  Mundo[i] = Pai ∘ Local[i]
```
`0x8002d4b0` é um **MulMatrix+ApplyVector**: seta `R+TR` do GTE a partir de `a0` (pai, 8 words),
faz `R_pai × R_local` (3× MVMVA `mx=R v=IR`) para a rotação e `R_pai × T_local + T_pai`
(MVMVA `mx=R v=V0 cv=TR`) para a translação, gravando a matriz composta em `a2` (`no+0x40`).
**Isto é exatamente `T(relpos)·R` acumulado pai→filho** — bate 1:1 com reevengi (§4) e com o
`gbind` do `emd2gltf`. A matriz-raiz do ator sai de `0x8008a0e4` (**RotMatrix**: tabela de seno
em `0x800a41b0`, índice `ang & 0x3ffc`) aplicado aos ângulos do ator em `ator+0x6c` → `ator+0x20`.
A ordem de rotação é a do **RotMatrix da libgte** (a mesma já validada visualmente como
`Rx·Ry·Rz`/XYZ 12-bit em `PLD.md §6`).

### 10.3 A decisão POR-OBJETO — `no+0xa2` só muda ILUMINAÇÃO/LOD, **não** o espaço (PROVA)

Em `0x80025610` o seletor de todos os ramos é `s2 = lhu no+0xa2` (as flags por-objeto). Os ramos:
```
andi v0, s2, 0x210 ; bnez -> pula o PRÉ-cálculo da matriz de LUZ (L11..L33), mas NÃO a posição
andi v0, s2, 0x1000; bnez -> variante que faz LOD (0x80078ba4) do sub-objeto e recompõe igual
andi v0, s2, 0x20  ; caminho de sub-lista alternativa (0x8002ba3c/0x8002c068)
andi v0, s2, 0x10  ; idem
```
Em **todos** os ramos, a POSIÇÃO do vértice é montada por `0x8002d4b0`/pelas primitivas usando a
**matriz completa** `no+0x40`. As diferenças de `0xa2` são: (a) montar ou não a matriz de LUZ nos
registradores `L` do GTE (para `NCCT`/normais), (b) escolher LOD, (c) subdividir polígono. **Nenhum
ramo troca o espaço de coordenadas do vértice.** Confirmado: `no+0xa2 |= 0xB` é setado pelos
*spawners* de sub-objeto roteirizado (`0x80043fb0/0x80043ff0/0x80044054` — flash de tiro/item na
mão) e `0xB` não casa nenhum dos bits acima → cai no caminho **default** (matriz cheia).

### 10.4 Binding por índice de osso na primitiva — `0x8007b518` (posição) e `0x8007b2fc` (luz)

As folhas GTE provam o binding por-índice. `0x8007b518` (transforma vértices/monta quads):
```
lui  s4, 0x800a ; addiu s4, s4, -0x76b0     ; s4 = &Matriz-RAIZ global (0x80098950)
lw ...(s4) ; ctc2 R11R12..R33               ; GTE R = matriz-raiz do ator (view∘placement)
lbu  v1, (a3)                               ; v1 = ÍNDICE DE OSSO do grupo (byte da lista a3)
sll ... ; li v0 = v1*188 ; lw v1, 0x108(s3) ; addu ; addiu v0, v1, 0x40  ; v0 = no[idx]+0x40
lhu (v0)/6/0xc ; mtc2 ; MVMVA mx=R v=IR     ; compõe R_raiz × Mundo[osso idx]
... transforma os vértices do grupo com essa matriz; grupos terminam em byte 0xFF ...
```
Idêntico em `0x8007b2fc` (que faz `NCCT` = normal→cor por grupo). Logo: **cada grupo de
primitivas nomeia seu osso**; o motor não assume "objeto i = osso i". `0x80098950`
(`0x800a-0x76b0`) = matriz-raiz global (view × colocação do ator) carregada em `R` por toda
primitiva; `0x80098990` (`0x800a-0x7670`) = matriz-pai usada na FK; `0x80098930`
(`0x800a-0x76d0`) = matriz de luz.

### 10.5 Objetos EXTRA (§3) à luz do EXE

- O array de nós tem `nb` entradas (`ator+8`). Geometria "extra" **não precisa** de nó próprio:
  ela é desenhada como grupo de primitivas de algum objeto, **nomeando o índice de osso** que
  quiser (§10.4). Por isso o EMD *standalone* do PC (reevengi, posicional `objeto i⇔osso i`)
  **perde** essa informação — o binding por-índice **só está na malha in-RAM do PS1**
  (as listas terminadas em `0xFF` dentro do `R###.BIN`, = as "tabelas de índice" de
  `enemy_mesh.md §3`, ainda não decodificadas para gltf).
- Sub-objetos roteirizados (item na mão, flash) entram em **slots de nó extras** (região
  `ator+0x108+0xf6c`) via `0x80043fb0/0x80043ff0/0x80044054`, com posição **hardcoded** e
  `no+0xa2 |= 0xB`. Esses não vêm do EMD.

### 10.6 Reconciliação HONESTA com a medição de §5 (model-space) e o que isto muda

O EXE prova que **o motor tem UMA regra**: matriz-mundo cheia por osso, vértice bone-local,
osso escolhido por índice na primitiva. Ele **não contradiz** a medição de §5 — **explica-a**:

- Para um vértice "parecer" em espaço-modelo absoluto (pé do EM50 já no tornozelo), basta que,
  **na malha do PS1**, aquele grupo esteja amarrado a um osso cuja matriz-mundo tem translação
  ~0 (perto da raiz), enquanto no EMD do PC (posicional) o mesmo pé é forçado no osso do pé
  (translação ≈ tornozelo) → ao aplicar a matriz cheia, **duplica** e "voa". Ou seja, o
  "model-space" é **artefato da perda do binding por-índice** ao usar o EMD posicional do PC,
  **não** um segundo caminho de render.
- **Consequência dura:** com **apenas** o `.EMD` *standalone* do PC (sem as listas de índice do
  PS1), **é impossível recuperar deterministicamente** qual osso cada parte usa. O EXE não
  entrega uma flag por-objeto porque **essa flag não existe** — existe um **índice de osso
  por-grupo**, que o arquivo do PC descartou. Portanto a §6 continua certa na prática (o
  conversor precisa de dica externa), mas pela razão correta.

### 10.7 Recomendação PRECISA para `emd2gltf` (não apliquei — você aplica)

1. **Manter o ramo bone-local com a MATRIZ COMPLETA** (`pos = R·v + t`, `(R,t)=Gbind[i]`) como
   regra **única e correta** (é literalmente o que o EXE faz: `R_raiz × Mundo[osso]`). Confirma §7.2.
2. **NÃO existe flag de "espaço" no dado** — pare de procurá-la. O que o motor tem é
   **índice de osso por-primitiva**. Duas saídas determinísticas, em ordem de preferência:
   - **(A, elimina a heurística) Recuperar o binding real do PS1:** decodificar as **listas de
     índice de osso terminadas em `0xFF`** da malha in-RAM do `R###.BIN`
     (`enemy_mesh.md §3`, seções sec3/sec5 — as "tabelas de objetos"), casar o `R###.BIN` ↔
     `EM##` por TIM byte-idêntico (já feito, `enemy_mesh.md`), e usar esse mapa
     **primitiva→osso** no lugar do `objeto i⇒osso i`. É o único jeito 100%: dá o osso EXATO
     de cada face, incl. extras e partes model-space, sem adivinhar.
   - **(B, heurística ancorada) Se ficar só no EMD do PC:** manter a flag curada por-modelo
     (`sce_enemies.json → emd_annotations[EMxx].vertex_space`) OU o teste de §7.3 comparando o
     centróide com a junta **posada** `tg[bone]`. Isso é o melhor possível sem (A).
3. **Extras (`i≥nb`):** o EXE confirma que eles **não têm osso posicional** — são grupos que
   nomeiam um osso por-primitiva. Sem (A), o best-effort de §7.4 (amarrar à junta posada mais
   próxima) segue sendo a melhor aproximação; `bone=nb-1` continua objetivamente errado.
4. **Ordem de rotação / bind:** confirmada `T(relpos)·Rx·Ry·Rz` acumulada pai→filho (RotMatrix
   da libgte `0x8008a0e4`), idêntica ao que `gbind`/`build_emd_clips` já fazem. Nada a mudar aí.

### 10.8 Incertezas remanescentes (honesto)

- **Não** dumpei o passo pose→`no+0x14` (12-bit → matriz local) como função isolada; inferi que
  é o mesmo RotMatrix (`0x8008a0e4`) da raiz aplicado por osso, coerente com o pool de poses já
  decodificado (`PLD.md §6`). A FK (concatenação pai∘local) e a raiz **estão** provadas.
- A **granularidade** exata do binding por-índice (por-vértice vs por-grupo-de-primitivas) é
  "por grupo terminado em `0xFF`"; um grupo pode ter N vértices. Não medi a distribuição real de
  índices numa malha (exigiria decodificar a malha in-RAM do PS1 — passo (A) acima).
- `0x80098950` (matriz-raiz global) é lida por toda primitiva mas o *hi/lo scan* automático não
  achou o escritor (dessincroniza em regiões de dado); pela semântica é a matriz view×colocação
  setada por ator antes do desenho. Não afeta as conclusões.

### 10.9 Endereços novos (índice)
- DRAW: dispatcher `0x80023268`; laço de atores `0x8002412c` (dentro de `0x80023268`);
  laço de nós `0x800254ac`; transform+draw por-nó `0x80025610`; despacho de primitiva por-objeto
  `0x80025de8`; desenho de primitivas `0x8007a350`/`0x8007a490`; folhas GTE
  `0x8007b2fc`(NCCT/luz)/`0x8007b518`(quad pos)/`0x8007b824`, `0x8007c434`/`0x8007c91c`.
- FK: laço `0x800251fc`; per-nó `0x800253f0`; MulMatrix+ApplyVec `0x8002d4b0`;
  RotMatrix `0x8008a0e4` (tabela seno `0x800a41b0`); SetLightMatrix `0x80089084`;
  ScaleMatrix `0x80088ee4`; LOD/dist `0x80078ba4`(+`0x80078c5c`/`0x80078f38`).
- Struct de nó (188 B) @ `ator+0x108`; `nb` @ `ator+8`; matriz-raiz do ator @ `ator+0x20`
  (ângulos @ `ator+0x6c`); spawners de sub-objeto `0x80043fb0/0x80043ff0/0x80044054` (`no+0xa2|=0xB`).
- Globais GTE: raiz/view `0x80098950`, pai(FK) `0x80098990`, luz `0x80098930`.
- Ferramenta desta análise: decodificador COP2/GTE ad-hoc (não versionado; capstone 5.0.7 não
  decodifica RTPS/RTPT/MVMVA/ctc2/lwc2/swc2). Reproduzível via `tools/exe_parse.py` + o decoder.

---

## 11. Tentativa de decodificar a MALHA EMPACOTADA do PS1 no `R###.BIN` — **VERDICTO: a estrutura que o EXE lê NÃO está no `R###.BIN`; é MONTADA no load** (fecha a alavanca do §10.7-A)

> Feito estaticamente sobre `SLUS_009.23` (decoder COP2/GTE em `C:/tmp/re3gte.py`) + `R101.BIN`
> (zumbi EM10). Objetivo: seguir a rotina de leitura (`0x8007a350`/`0x8007b518`, §10.4) até o
> LAYOUT exato da estrutura de primitivas, achá-la no `R###.BIN` e extrair o índice-de-osso.
> **Resultado honesto: a rotina de leitura foi 100% decodificada, MAS ela lê uma estrutura
> in-RAM que o loader CONSTRÓI no carregamento — ela NÃO existe byte-a-byte no `R###.BIN`.**
> O `R###.BIN` guarda a geometria num ENCODING EMPACOTADO diferente (os registros de 52 B/32 B
> de `enemy_mesh.md §4`, que continuam NÃO decodificados). Ter o código de leitura **não basta**:
> falta o UNPACKER (não localizado) ou quebrar o encoding empacotado (mesma parede do §4).

### 11.1 O LAYOUT EXATO da estrutura in-RAM (decodificado — 3 folhas + o loader)

Cadeia: `0x80025de8` (despacho) → `0x8007a350` (desenha 1 objeto) → folhas
`0x8007b2fc/0x8007b518/0x8007b824`. E o **loader** `0x8007a2d4` (quem escreve `no+0xa8`).

**(a) O "mesh-block" e o binding objeto→osso por BITMASK — `0x8007a2d4` (PROVA):**
```
8007a2d4  addiu a3, a1, 8        ; a3 = &headers[0]  (a1 = ponteiro do mesh-block)
8007a2dc  lhu   v0, 4(a1)        ; v0 = vtxoff (u16 @ mesh+4)
8007a2e0  lw    t0, 0x108(a0)    ; t0 = array de nós (ator+0x108)
8007a2e8  sw    (a1+v0), 0x11c(a0) ; ator+0x11c = mesh + vtxoff = ARRAY DE VÉRTICES
8007a2ec  lw    a0, (a1)         ; a0 = BITMASK (u32 @ mesh+0)
8007a2f0  lhu   a1, 6(a1)        ; a1 = count (u16 @ mesh+6)
  ... por bit do bitmask (a2 = índice do nó, v1 = &no[a2], passo 0xBC): ...
8007a30c  andi  v0, a0, 1
8007a310  beqz  -> pula
8007a31c  sw    a3, 0xa8(v1)     ; no[a2]+0xa8 = header atual  (MESH do objeto)
8007a320  addiu a3, a3, 8        ; próximo header (8 B)
8007a328  ori   no+0xa2 |= 0x10  ; marca "tem malha"
8007a32c  srl   a0, a0, 1        ; próximo bit
8007a330  addiu v1, v1, 0xbc     ; próximo nó
8007a334  bnez  a0 -> loop ; a2++ (delay)
```
→ **O objeto→osso é POSICIONAL por BITMASK:** o m-ésimo bit setado do bitmask amarra o
m-ésimo header de 8 B ao **nó daquele bit**. Cada objeto = um header `{u32 f0, u32 f1}` (8 B).
`ator+0x11c` = array de vértices = `mesh + u16@(mesh+4)`.

**Layout do "mesh-block" (in-RAM):**
| off | tipo | papel |
|---|---|---|
| +0 | u32 | **bitmask** — quais nós têm malha (popcount = nº de objetos) |
| +4 | u16 | **vtxoff** — offset (rel. ao mesh-block) do array de vértices |
| +6 | u16 | count (nº de iterações do laço) |
| +8 | `{u32 f0,u32 f1}[]` | 1 header de 8 B por bit setado (na ordem dos bits) |

**(b) O header de 8 B → 3 listas de grupos — `0x8007a350` (PROVA):**
```
8007a390  lw s3, 0xa8(s5)    ; s3 = header do objeto (= no+0xa8)
8007a398  lw s1, (s3)        ; s1 = f0
8007a3c4  s0 = s3 + (s1 & 0xffff)   ; lista A = header + f0.low16   -> 0x8007b2fc
8007a3f8  s1 = s1 >> 16
8007a40c  s0 = s3 + s1              ; lista B = header + f0.high16  -> 0x8007b518
8007a42c  s1 = lw 4(s3)     ; f1
8007a444  s0 = s3 + s1              ; lista C = header + f1         -> 0x8007b824
```
→ os offsets das 3 listas de primitiva são **relativos ao próprio header de 8 B**.

**(c) A lista de grupos com ÍNDICE DE OSSO por grupo — `0x8007b518` (PROVA, confirma §10.4):**
```
8007b588  lbu v1, (a3)              ; v1 = ÍNDICE DE OSSO do grupo
8007b590..5a8  v0 = v1*188 ; lw 0x108(s3) ; v0 = &no[idx]      ; addiu v0,+0x40
           -> monta R_raiz × Mundo[osso idx] no GTE (MVMVA sf=1 v=3 cv=3)
8007b69c  t6 = lbu (a3+1)           ; count de primitivas do grupo
          a3 += 2
8007b6a8  t5=lbu(a3) ; t4=lbu(a3+1) ; t3=lbu(a3+2)  ; 3 ÍNDICES DE VÉRTICE (bytes)
8007b6b4  a0 = t8 + t5*8            ; VÉRTICE = base t8, PASSO 8 BYTES (s16 x,y,z,pad)
8007b6cc  lwc2 ... ; NCCT           ; transforma/ilumina
          a3 += 3 ; t6-- (loop no count)
8007b768  beq (byte), 0xff          ; 0xFF = marcador (fim de lista/no-color)
```
→ **A malha in-RAM que o EXE percorre é:** um array de **vértices de 8 B** (`s16 x,y,z,pad`,
base `ator+0x11c`) + listas de grupos `[osso:u8][count:u8][ (v0,v1,v2):u8×3 × count ] …`
com `0xFF` de marcador. **É este o binding por-primitiva que o EMD do PC descartou.**

### 11.2 A prova de que essa estrutura **NÃO está no `R###.BIN`** (é montada no load)

O modelo do inimigo em `R101.BIN` é o **bloco 0** (tag `0x80a70000`, `nb=15`; o "bloco 6" do
enunciado é a TIM/pele de 99872 B = `EM10.TIM`). O bloco tem 8 seções (`bin2gltf model`):
sec0/sec6 = EMR+poses (esqueleto, `relpos_len=100, nb=15, fs=76` — cabeçalho lido byte-a-byte),
sec1/sec7 = EDD, **sec2/sec3/sec4/sec5 = geometria** (constantes entre salas). Três provas de
que a estrutura in-RAM do §11.1 **não existe verbatim** no bloco:

1. **Não há array de vértices de 8 B.** A leitura (`0x8007b518`) exige um array `s16 x,y,z,pad`
   de passo 8 indexável por bytes. Varredura de TODO o bloco 0 (e bloco 1) por qualquer corrida
   ≥80 de registros de 8 B com `|x|,|y|,|z|<2000`: **nenhuma** que case os 304 vértices do
   `EM10.EMD` (PC), nem verbatim (0 de 40 vértices achados como padrão de 6 B), nem como corrida
   longa. Confirma a nota de `enemy_mesh.md §1` ("não há array `emd_vertex4_t` no bloco").
2. **Nenhuma seção começa com o bitmask do §11.1.** Para `nb=15`/16 objetos o mesh-block+0 seria
   um `u32` com ~15 bits setados. sec0=`0x00000001`, sec2=`0x00010000` (1 bit), sec3=`0x00800022`
   (3 bits), sec6=`0x00000004`. Nenhuma seção abre como o mesh-block.
3. **sec2 É geometria, mas EMPACOTADA.** O "obj0" de sec2 é **limpo** (9 vértices `s16 x,y,z` de
   6 B: `(0,-1844,0),(-43,-611,-305),(-2,484,-71)…` = corpo real do zumbi + 2 quads com UV e
   índices). Mas o obj0 tem só 112 B; o RESTO de sec2 = **432 registros de 52 B** agrupados pela
   tabela sec3 em 16 objetos (`counts=[34,34,20,20]×4`, soma 432; `sec2 = 112 + 432·52` exato).
   Esses 52 B **não** são o `[osso][count][idx]`+vértice-8B do §11.1: são registros de tamanho
   fixo com colunas `s16` bit-packed (col0 = contador que sobe ~+32/reg; col ≈ Y perto da raiz;
   colunas com `±4096`/valores de 16 bits "aleatórios" = normais/posição empacotadas). **Idem
   `enemy_mesh.md §4` — continua NÃO decodificado.**

**Conclusão do §11.2:** o loader de sala **desempacota** sec2/sec4 (registros de 52/32 B) +
o EMR para MONTAR, em RAM de trabalho, o mesh-block do §11.1 (bitmask + headers de 8 B +
listas `[osso][count][idx]` + array de vértices de 8 B). O caminho de load confirma o esquema:
`0x80038aac` copia o bloco (memcpy `0x800100a4`, **sem descompressão**) de uma região raw para a
de trabalho e liga `ator+0x14`=esqueleto, `ator+0x108`=array de nós (188 B/nó, alocado no fim),
e o mesh-block via `0x8007a2d4`. Ou seja: a estrutura de primitivas **é montada em runtime**,
exatamente o cenário que o enunciado pediu para PROVAR caso ocorresse.

### 11.3 VERDICTO honesto (o que dá e o que NÃO dá)

- ✅ **Decodificado 100%:** a rotina de leitura e o binding real. O binding vértice→osso do PS1
  tem DOIS níveis: (i) **objeto→nó por bitmask** (posicional: m-ésimo objeto → nó do m-ésimo
  bit) e (ii) **índice-de-osso por-grupo** dentro do objeto (`lbu (a3)`, permite multi-osso numa
  mesma malha). O nível (ii) é a informação que o EMD do PC perde. **§10.4 confirmado e detalhado.**
- ❌ **NÃO recuperado:** o índice-de-osso por-vértice a partir do `R###.BIN`, porque a estrutura
  que carrega esse índice (as listas `[osso][count][idx]`) **é construída no load**, não está no
  arquivo. Para lê-la faltaria: (a) o **UNPACKER** (a função que transforma os registros de 52/32 B
  em vértices de 8 B + listas de grupo) — **não localizada** estaticamente (não há laço de passo 52
  óbvio; a alocação/escrita ocorre em região de dado que dessincroniza o disasm linear); OU
  (b) **quebrar o encoding empacotado** dos registros de 52/32 B — a mesma parede de `enemy_mesh.md
  §4`, que caracterizei mais (col0=contador, Y-near-root explícito, resto bit-packed) mas **não
  quebrei**. Sem (a) ou (b), o EM10 não pôde ser validado (obj i→osso i) a partir do PS1, e os
  hunters (EM22…) ficam bloqueados.
- ⚖️ **Não é "irrecuperável por compressão":** a geometria ESTÁ no arquivo (obj0 de sec2 tem
  vértices reais; sec2/sec4 são constantes por-inimigo = a malha). Não há LZ/descompressão no
  caminho de load (é memcpy puro). O bloqueio é o **encoding empacotado por-registro** + o
  **unpacker não localizado**, não compressão. Então é *decodável em princípio*, mas **exige
  crackear os registros de 52/32 B** — o código de leitura (§11.1) sozinho **não** entrega isso,
  porque lê o produto DESEMPACOTADO, não o arquivo.
- 🚫 **Não fabriquei** `godot/data/emd_bone_index.json` nem toquei em `emd2gltf.py`: sem dado real
  extraído, qualquer mapa seria invenção. O melhor determinístico continua sendo o §10.7-B
  (flag curada por-modelo / junta posada) até o unpacker ou o encoding de 52/32 B ser quebrado.

### 11.4 Próximo passo concreto (para quem retomar)
Atacar o **unpacker**, não a leitura. Pistas: (1) o mesh-block montado tem `bitmask+headers+verts`;
procurar a função que ESCREVE vértices de 8 B (`sh;sh;sh` em laço) e/ou lê a tabela sec3
(`{u16 count,u16 off_idx(passo 2·count),u16 off_elem}`) — ela consome sec2/sec4 e produz o
mesh-block. (2) Alternativa: decodificar 1 registro de 52 B como primitiva GTE (a coluna Y-near-root
e as colunas `±4096` sugerem `SVECTOR pos` + `SVECTOR normal` empacotados) e casar com os
vértices limpos do obj0 para deduzir o bit-packing. (3) Cross-check: extrair o MESMO zumbi como
`.EMD` standalone da **ISO do PS1** (`reevengi-tools iso_search`, formato `emd3.h`, verts de 8 B
limpos) e casar contagens com sec2/sec3 para inferir a transformação. Ferramentas desta rodada:
`C:/tmp/re3gte.py` (disasm+COP2), `C:/tmp/{desc,sec_analyze,rec52,vscan2}.py` (scratch, não versionados).

### 11.5 Endereços (índice do §11)
- Loader do mesh-block (escreve `no+0xa8`, binding objeto→nó por bitmask): **`0x8007a2d4`**
  (chamado de `0x8001371c/0x80014df4/0x80015058/0x80038c08`).
- Desenha 1 objeto (lê header de 8 B em `no+0xa8`, despacha p/ as 3 folhas): `0x8007a350`.
- Folha com índice-de-osso por-grupo + vértices de 8 B: `0x8007b518` (idem `0x8007b2fc`/`0x8007b824`).
- Load/relocate do modelo (memcpy puro, sem unpack visível aqui): `0x80038aac`
  (raw `0x801bd5e0` → trabalho `0x801d5c00`; `nb` e mesh via descritor = diretório de 8 seções).
- `R101.BIN`: modelo = **bloco 0** (não o 6, que é a TIM). Geometria empacotada = sec2 (52 B/reg)
  + sec4 (32 B/reg), tabelas sec3/sec5 — ver `enemy_mesh.md §3-4`.
  > ⚠ **CORRIGIDO EM §12:** o "bloco 0" (empacotado 52/32 B) é o **modelo do JOGADOR** (Jill/
  > parceiro), **não** o inimigo. O **zumbi EM10 = bloco 7** do `R101.BIN`, um **EMD emd3 STANDALONE
  > byte-idêntico ao `EM10.EMD` do PC**. O §11.2 varreu só os blocos 0 e 1 (jogador) → por isso
  > "não achou" o array de vértices de 8 B: ele está no **bloco 7**, intacto. Ver §12.

---

## 12. FECHAMENTO — o "unpacker" **não existe para inimigos**: a malha de inimigo é um **EMD emd3 STANDALONE no `R###.BIN`, byte-idêntico ao do PC** (refuta §10/§11)

> Feito estaticamente sobre `SLUS_009.23` (`C:/tmp/re3gte.py`) + `R101/R402/R40E.BIN` e os
> `EM##.EMD` do PC. **Todos os achados abaixo são byte-a-byte / disasm — nada inferido.**
> Este § **corrige um erro de identificação de bloco** que sustentava toda a "parede" de §10/§11.

### 12.0 TL;DR (revê §10, §11 e `enemy_mesh.md §4`)

1. **A malha de inimigo NÃO é empacotada. Ela é um EMD `emd3` STANDALONE, guardado VERBATIM
   num bloco do `R###.BIN`, BYTE-IDÊNTICO ao `EM##.EMD` do port de PC.** Provado para EM10
   (zumbi), EM24 e EM22 (hunter). Logo **não há "unpacker" a procurar** — a geometria já está
   totalmente decodificada (é o mesmo formato que o `emd2gltf.py` já lê).
2. **O formato EMPACOTADO de 52/32 B (§4/§11) é o modelo do JOGADOR/personagem** (`R101.BIN`
   blocos 0 e 1, tags `0x80a70000`/`0x818a0000`, destino RAM-principal), **não** o inimigo. O
   §11.2 varreu **só os blocos 0 e 1** (por isso "não achou" o array de 8 B — está no bloco 7).
3. **O binding vértice→osso do inimigo é POSICIONAL (`objeto i ⇔ osso i`, 1 osso por objeto),
   idêntico PS1↔PC.** **Não há índice-de-osso por-grupo/por-vértice na malha de inimigo.** O
   `[osso][count][idx]` por-grupo de §10.4/§11.1 (a folha `0x8007b518`) é do **caminho do
   JOGADOR** (formato empacotado dos blocos 0/1), **mal-atribuído ao inimigo** em §10/§11.
4. **Consequência dura:** não existe informação de osso "mais rica" a recuperar dos inimigos — o
   dado do PS1 **é** o dado do PC. O único buraco real são os **objetos EXTRA** (`i≥nb`), que o
   emd3 (PS1 **e** PC) **não amarra a osso nenhum** → **irrecuperável do arquivo** (decisão de
   engine, em código). O best-effort de §7.4 continua sendo a resposta honesta para extras.
5. **Não gravei `emd_bone_index.json`:** o mapa vértice→osso do inimigo **é** o posicional que o
   `emd2gltf` **já aplica** — um JSON posicional seria redundante (zero informação nova), e
   preencher extras por heurística seria invenção (proibido). Ver §12.5.

### 12.1 PROVA byte-a-byte: EM10 = `R101.BIN` bloco 7 = `EM10.EMD` do PC

Mapa de blocos do `R101.BIN` (`bin2gltf info`):

| blk | foff | size | tag | papel (ESTE §) |
|----:|---|---:|---|---|
| 0 | 0x000800 | 87916 | `0x80a70000` | **JOGADOR** (empacotado 52/32B, nb15) |
| 1 | 0x016000 | 36176 | `0x818a0000` | **JOGADOR/parceiro** (empacotado, nb15, **mesmo esqueleto do blk0**) |
| 6 | 0x04e800 | 99872 | `0x10b70100` | **TIM** = `EM10.TIM` (99872 B) |
| **7** | **0x067000** | **144964** | **`0x10ee0000`** | **ZUMBI EM10 = EMD `emd3` (== `EM10.EMD` do PC)** |
| 8/9, 10/11 | … | … | `0x54../0x59..` | mais pares TIM+EMD de inimigo |

- **`R101.BIN[0x67000 : 0x67000+144964]` == `EM10.EMD` do PC**: **1 único byte difere** em
  144964 (`@0x1fb78`, região de anim/pad, fora de model/skel/geometria). Tamanho difere de 1 B.
- **Os 304 vértices** (8 B `s16 x,y,z,pad`, `pad==0`) do EM10 estão **contíguos e verbatim** em
  `R101.BIN @0x89308` (= blk7 + `0x22308`), casando **304/304** com o `EM10.EMD` do PC (obj0..14,
  counts `[43,88,13,14,18,13,14,18,15,18,8,8,18,8,8]`). Parse do blk7 direto: `objs=15 nb=15
  304 verts, 0 anomalias` — **EM10 reproduzido 1:1 a partir do PS1** (identidade de bytes é a
  prova mais forte possível).
- **O esqueleto (relpos) do blk7 (zumbi) `(0,-1995,0),(-43,-646,0)…` ≠ o dos blk0/blk1
  `(0,-1839,0),(-23,-667,0)…`.** blk0 e blk1 têm relpos **idêntico entre si** e **diferente de
  todo inimigo** → são os dois modelos de **personagem jogável** (mesmo rig). **blk0 NÃO é o
  zumbi.** (Os "verts limpos de sec2" de §11.2 — `(0,-1844,0),(-43,-611,-305)` — eram na verdade
  o **relpos do EMR do jogador**, lido como se fossem vértices.)

### 12.2 Multi-osso confirmado POSICIONAL (EM24 e o hunter EM22)

- **EM24** = `R40E.BIN` blk12 (103596 B) **byte-idêntico** ao `EM24.EMD` do PC (103597; 1 B).
  `objs=20 nb=20` (sem extras), posicional.
- **EM22 (hunter)** = `R402.BIN` blk10 (achado em **16 salas**: R402/404/405/408/409/40A/40C/40F/
  417/504/507/61E/621/702/710/711). A **geometria** (todos os 21 arrays de vértice por-objeto,
  435 verts) é **byte-idêntica ao `EM22.EMD` do PC**; só os **bancos de anim/esqueleto diferem
  por sala** (14873 B de diff, TODOS antes de `model@63560`). `objs=21 nb=20` → **1 extra**
  (obj20, 3 verts). O extra **não tem osso** no emd3 (nem no PS1 nem no PC).

**Portanto, em single-osso, multi-osso limpo e multi-osso-com-extra, a malha de inimigo do PS1 é
o mesmo emd3 posicional do PC.** Não existe binding por-grupo/por-vértice de inimigo a recuperar.

### 12.3 Por que o caminho `0x8007a2d4`/`0x8007b518` (§10/§11) é do JOGADOR, não do inimigo

- **`0x800100a4` é `memcpy` puro** (copia blocos de 32 B + resto byte-a-byte; **sem
  descompressão** — disassemblado). Não há unpacker aí.
- **`0x80038aac`** (o "loader/relocate" de §11.5) processa o **ator-jogador** (buffer fixo em
  `base+0x248c`), carregando um modelo empacotado com **descritor de 5 campos**
  `{sec0=EMR→ator+0xec, sec1=EDD→+0xe8, sec2=esqueleto→+0x14, sec3=MESH(→0x8007a2d4), sec4=TIM}`
  de `0x801bd5e0`→`0x801d5c00`. O **mesh-block empacotado (bitmask+headers+8B) está VERBATIM** no
  arquivo do jogador; `0x8007a2d4` **só religa ponteiros** (não desempacota geometria). É chamado
  de `0x800493ec` (state-machine de load do jogador, chaveada pelo id de personagem em `+0x4a`,
  limiar `0x50`).
- **`0x8001760c`** (chamado de `0x80013608`, outro chamador de `0x8007a2d4` via `0x8001371c`) lê
  um descritor de **~14 campos** que inclui **slots de anexo `+0x180/0x184/0x188/0x18c`
  (arma/item na mão)** e `+0x1b4/0x11c/0x118/0xf0..0xfc` — **inequivocamente o JOGADOR**.
- Os demais chamadores (`0x80014df4/0x80015058`) são **laços genéricos** que religam
  `ator+0x11c` de **todo ator que TENHA** um mesh-block empacotado válido (`*(ator+0x11c)!=0`).
  O **inimigo (emd3) não tem** esse mesh-block empacotado → não passa por essa folha.
- A folha `0x8007b518` com `lbu (a3) = índice-de-osso por-grupo` (§10.4/§11.1) opera sobre o
  **mesh-block empacotado do jogador** (blocos 0/1). O emd3 do inimigo (blk7) **não tem** bitmask
  nem headers de 8 B nem listas `[osso][count][idx]` — é `emd3_model_object` (24 B) + `emd3_tri`
  (12 B)/`emd3_quad` (16 B), que o `emd2gltf` lê como posicional. Logo **essa folha nunca desenha
  inimigo**. A afirmação de §10.0/§10.4 ("um só path; binding por-índice para TODOS") vale para o
  **jogador/personagens**, e foi **generalizada por engano** aos inimigos.

### 12.4 O que REALMENTE é irrecuperável (e por quê) — só os EXTRAS

O emd3 (PS1 **idêntico** ao PC) **não codifica** o osso dos objetos extra (`i≥nb`): eles estão
**fora da hierarquia da armadura** (§2/§3) e sem canal de pose. Como o dado do PS1 **é** o dado do
PC, **não há de onde tirar** o osso do extra a partir do arquivo — é uma decisão do **código de
desenho** da engine (provavelmente por-modelo, hardcoded, análoga ao `_extra_bone_map` do
`pld2gltf`). Isso **não é uma parede de encoding** (a geometria está toda limpa); é **ausência de
dado** no formato. **Best-effort de §7.4** (amarrar à junta posada `tg[b]` mais próxima) segue
sendo a aproximação honesta. Ex.: EM22 obj20, EM38 (Nemesis) obj23–30, EM36/EM3A obj16–23.

### 12.5 Deliverable — **NÃO** gravei `emd_bone_index.json` (justificativa honesta)

O mapa vértice→osso do inimigo **é posicional** (`objeto i → osso i`, 1 osso/objeto), que o
`emd2gltf.build_arrays` **já computa e aplica** (§7.1). Um JSON posicional seria **100%
redundante** (nenhuma informação nova) e o "índice-de-osso real por-vértice para multi-osso" que a
tarefa pedia **não existe** (não há variação de osso dentro de um objeto — refutado em §12.2).
Preencher os extras por heurística e rotular de "osso real" seria **invenção** (a tarefa proíbe).
**Recomendação:** manter o binding posicional do `emd2gltf` (é o ground-truth, validado 1:1 no
EM10) + §7.4 para extras. Se quiser um dump explícito posicional como artefato, é trivial gerar,
mas é operacionalmente um no-op para o `emd2gltf`.

### 12.6 Endereços/fatos novos (índice do §12)
- Malha de inimigo EM10 = **`R101.BIN` bloco 7** (`0x067000`, 144964 B, tag `0x10ee0000`) =
  `EM10.EMD` do PC (1 B de diff). Vértices @ `R101+0x89308` (blk7+`0x22308`), 8 B, `pad=0`, ×304.
- Jogador/personagem (empacotado 52/32 B) = **blocos 0/1** (`0x80a70000`/`0x818a0000`), esqueleto
  `(0,-1839,0)…` (≠ zumbi). Mesh-block empacotado do jogador = **sec3** do bloco (via `0x80038aac`,
  descritor de 5 campos), desenhado por `0x8007a2d4`/`0x8007b518` (**caminho do jogador**).
- `0x800100a4` = **memcpy puro** (confirmado por disasm). `0x800784e0` = **upload de TIM**
  (LoadImage `0x8008b2ac`, coords de frame-buffer `+0x2484/0x2485`) — **não** é unpacker.
- Multi-osso posicional: EM24 = `R40E.BIN` blk12 (== PC); EM22 hunter = `R402.BIN` blk10 (+15
  salas), geometria == PC (`objs=21 nb=20`, 1 extra).
- Ferramentas: `C:/tmp/re3gte.py` (disasm+COP2), `C:/tmp/{xref2,callers,vscan3,vscan4,find22b}.py`
  (scratch, não versionados). Parse de EMD: `tools/emd2gltf.py`; blocos: `tools/bin2gltf.py`.

---

## 13. **ACHADO: o binding por-vértice SEMPRE ESTEVE NO ARQUIVO — seção `dir[0]`** (refuta §10.7, §11.3 e §12.4/§12.5)

> Feito byte-a-byte sobre os 69 `EM##.EMD` do PC (`extracted/pc/rofs9`), validado
> geometricamente contra o EMR e visualmente na Godot. **Aplicado** em `tools/emd2gltf.py`.
>
> §10–12 procuraram o índice-de-osso por-primitiva na **malha** (`model`) e no PS1
> (`R###.BIN`), concluíram "não existe / é decisão de engine" e recomendaram heurística.
> **A informação está numa OUTRA seção do mesmo arquivo**: a entrada **`dir[0]`**, que o
> `emd3_directory_t` do reevengi chama de `unknown0[0]` e que o `emd2gltf` nunca lia.
> Não é heurística, não é o PS1, não é o EXE: é dado explícito do `.EMD` do PC.

### 13.0 TL;DR

1. **`dir[0]` existe em 41 dos 69 EMD — exatamente os modelos cujos membros descolavam.**
   Os 28 sem a seção (zumbi EM10/EM12/EM14–EM1F, cão, corvo, aranha, helicóptero…) são os
   que já fechavam em vão 0,000 com o mapa posicional. A correlação é 100%.
2. A seção traz **(a) uma bitmask dos objetos multi-osso, (b) a TABELA DE COORDENADAS
   `-world[i]` (translação do inverse bind) e (c) listas `[osso][nbatches][índices de
   vértice]`** — isto é, **o osso de CADA VÉRTICE**, que §12.5 afirmou não existir.
3. A união dos índices de cada objeto cobre **exatamente** `range(vtx_count)`: validado em
   **221/235** objetos marcados (os 14 restantes têm 3ª/4ª lista que o parser ainda corta —
   EM30/EM33/EM5F/EM40).
4. **Convenção de espaço resolvida sem adivinhar:** nos objetos DA bitmask os vértices estão
   em **espaço-modelo absoluto** (medido: 607 grupos a favor × 16 contra); fora da bitmask são
   **bone-local** 1:1. A heurística `_is_model_space` concorda com a bitmask em **377/377**
   objetos fora dela — ou seja, a bitmask **é** a resposta que ela tentava adivinhar.
5. O "model-space" de §5 e a "perda do binding" de §10.6/§12.4 eram **o mesmo fenômeno**:
   objeto que abrange vários ossos. O arquivo diz quais são e quais vértices vão em qual osso.

### 13.1 Layout de `dir[0]` (offsets relativos ao início da seção, little-endian)

| off | tipo | papel |
|---|---|---|
| `+0` | u32 | **bitmask de OBJETOS** com binding explícito (multi-osso). `popcount == u16@6` |
| `+4` | u16 | **`coord_off`** — offset da tabela de coordenadas |
| `+6` | u16 | nº de entradas (== popcount da bitmask) |
| `+8` | `8 B × nent` | 1 entrada por bit setado, **na ordem dos bits**. Até 4 `u16` = offsets **AUTO-RELATIVOS** (relativos ao endereço da própria entrada: `abs = sec+8+8k+valor`); `0` = ausente |
| `+coord_off` | `nb × s16[3]` | **`-world[i]`** = relpos ACUMULADO negado = translação do **inverse bind**. Idêntico ao EMR em **41/41** arquivos |
| listas | `[u8 osso][u8 nbatches][3·nbatches u8 idx]` … `0xFF` | `nbatches = ceil(n/3)` (o GTE do PS1 transforma 3 verts por `RTPT`); o slot sobrando repete o último índice **ou** é `0xFF`. `0xFF` como 1º byte de grupo = fim da lista |

O `nbatches = ceil(n/3)` é a assinatura que fecha o formato: `[00][07]` = 21 slots para 20
vértices + 1 repetido; `[03][08]` = 24 slots para 24 vértices exatos; `[0e][02]` = 6 slots
para 4 vértices + `ff ff`. Confere nos 1020 grupos lidos.

### 13.2 Prova geométrica (o dado é anatomicamente correto)

Cada grupo cai **entre a sua junta e a junta seguinte** — o padrão exato de um skin rígido:

| modelo | objeto | como era (posicional) | o que a tabela diz |
|---|---|---|---|
| **EM50** (humano) | obj8, 97 v | tudo no **osso 8** (quadril) → as PERNAS não seguiam fêmur/joelho | ossos 0/8/**9**/**10**/**12**/**13**; grupo do 9 em y=584 (junta 9=103, junta 10=863 ✔), grupo do 10 em y=1241 (junta 10=863, junta 11=1702 ✔) |
| **EM22** (hunter) | obj1, 96 v | tudo no **osso 1** (tronco) → o BRAÇO ficava colado no peito | ossos 1/2/**3**/**4**; grupo do 4 em (772,−561) ≈ junta 4 (592,−636) ✔ |
| **EM24** | obj0, 110 v | tudo no **osso 0** | 9 ossos: 0/1/2/3/4/5/8/14/17 |
| **EM37** (tentáculo) | obj0+obj3, 25 v cada | 1 osso por objeto | obj0 → 0/1/2 (y 86/609/1303 p/ juntas 0/313/930 ✔), obj3 → 2/3/4/5 (y 1530/2002/2649/3145 p/ juntas 930/1660/2338/2937 ✔) |

`obj1/obj2/obj4/obj5` de EM37/EM39/EM3B são **3 vértices em (0,0,0)** — marcadores
degenerados; a geometria real está só em obj0 e obj3, que a tabela reparte pela cadeia toda.

### 13.3 O que mudou em `tools/emd2gltf.py`

- `parse_u0_skin(d, nb, objs)` — novo; devolve `mask`, `inv_world` e `obj_bones[obj][vidx] = [ossos]`.
- `build_arrays(..., skin_tbl=)` — atribuição **(D) `tabela-dir0`**, que **não entra no torneio
  de vão** (o vão é PROXY; o dado tem autoridade sobre ele). Os 28 EMD sem a seção seguem no
  torneio A/B/C de antes, intactos.
- Espaço do vértice: `model_space = True` se o objeto está na bitmask, `False` caso contrário —
  **em todos os EMD, inclusive os 28 sem a seção** (`_is_model_space` saiu de uso; ver §13.6-a,
  ela punha a cabeça do zumbi dentro do peito).
- **Costura:** 12,9% dos vértices são citados em 2+ grupos (as juntas). Padrão = **RÍGIDO no
  primeiro osso** (leitura fiel: o PS1 não tem peso, desenha o vértice 1× por grupo).
  `EMD_SEAM_BLEND=1` divide 50/50 entre ossos pai/filho — junta lisa, mas deforma o objeto.
  ⚠ `dev/rig_check.gd` usa **só o osso dominante** (L181), logo é **cego** ao blend: não
  meça o blend com ele.
- `EMD_SKIN=heur` reproduz o comportamento anterior (torneio A/B/C), para medir antes/depois.

### 13.4 Resultado medido — ⚠ NÚMEROS SUPERADOS PELA §13.7

> Esta medição é da 1ª rodada, quando a bind ainda era a pose0 e a heurística de espaço ainda
> rodava nos EMD sem `dir[0]`. As "pioras" listadas aqui (em37/em3b 0,359, em39, em5f)
> **foram resolvidas** em §13.6. Use a tabela da §13.7 como resultado.

| família | vão antes | vão depois |
|---|---|---|
| humano (15 ossos) | 0,038 | **0,032** |
| hunter (20/21) | 0,059 | **0,050** |
| nemesis (22) | 0,130 | **0,085** |
| verme (17) | 0,067 | **0,027** |
| zumbi (11/15) | 0,000 | **0,000** (sem regressão — não têm a seção) |

Maiores ganhos: `em59` 0,223→**0,001**, `em54` 0,226→**0,017**, `em24` 0,129→**0,050**,
`em30`/`em33` 0,073→0,013, `em36` 0,073→0,015, `em34` 0,057→0,009.

**Honesto — onde o número PIOROU:** `em37`/`em3b` 0,012→0,359, `em39` 0,130→0,198,
`em5f` 0,020→0,140. É **artefato da métrica**: o vão mede a distância da AABB do grupo à
AABB da UNIÃO dos outros; com grupos mais finos e corretos, a ponta de um tentáculo que
chicoteia sai da caixa e é contada como "descolada". No render (`dev/tools_rig_ab.gd`,
grade modelo × fração de animação) o em37 da tabela é uma cadeia CONECTADA que dobra,
enquanto o da heurística aparece como 2–3 bastões SOLTOS. `em37/em39/em3b` continuam
`incerto` e fora do escopo deste §.

**Validação visual** (`dev/tools_rig_ab.gd`, humanos em 4 frações de caminhada): antes as
pernas eram um bloco rígido e os **sapatos flutuavam soltos no chão**; depois o corpo anda
com pernas e pés presos. É exatamente o defeito relatado.

### 13.5 Pistas ainda ABERTAS achadas de raspão (não investigadas)

- **`dir[13]` é um SEGUNDO bloco de malha** (header `emd3_model_header_t` válido: o 1º u32 é o
  próprio tamanho, o 2º a contagem de objetos), presente em ~15 EMD e nunca lido:
  EM10 (8 objs), EM13 (15 objs = cópia da principal com **obj1/cabeça diferente**),
  EM16 (19), EM19 (**31**), EM1A (22), EM1B (24), EM1F (26), EM17 (10), EM23/EM1C (1),
  EM34/EM35 (2). Nos de 11 ossos vêm em GRUPOS (ex.: EM16 = 8+5+5+1 objetos) — cara de
  **variantes de dano/desmembramento** (corpo sem braços, cabeça solta). Vale conferir se são
  os modelos de zumbi decapitado.
- **`dir[9..12]` nos NPC EM50–EM71**: dois pares EDD+EMR extras completos —
  `dir[10]` = EMR de **7 ossos** (`hier_off=52 move_off=88 nb=7 move_size=40`, relpos = raiz +
  2 pernas de 3) e `dir[12]` = EMR de **9 ossos** (raiz + tronco + 2 braços + cabeça). São os
  bancos de animação **parciais** (inferior / superior) do personagem. Nos inimigos não-humanos
  essas entradas estão vazias (4 bytes).
- `skel2` (`dir[7]`) é **15 ossos / fs=76** em quase todo inimigo, inclusive cão e aranha —
  esqueleto HUMANO embutido no EMD da criatura. Não investiguei para quê.

### 13.6 Segunda rodada — validação NA CENA e três correções que faltavam

A validação visual em `res://scenes/model_viewer.tscn` (que o vão do `rig_check` NÃO pegava)
expôs três defeitos independentes. Todos corrigidos e medidos.

**(a) A heurística de espaço punha a CABEÇA DO ZUMBI DENTRO DO PEITO.**
`model_space = tmag>0.4 and dc<cmag` disparava falso no obj1 (a cabeça) de EM10 e de toda a
família de zumbi: centroide da cabeça `(0.16, 0.32)` vs junta posada `(0.15, 0.63)` →
`dc=0.31 < |cen|=0.35` → "model-space" → a cabeça ficava em y=0.32, e o torso está em y=0.40.
Idem as CANELAS dos zumbis de 11 ossos (EM16/EM19/EM1C/EM1E obj8 e obj10, y=−0.73 em vez de
−1.66). **O vão do `rig_check` é cego a isso: peça sobreposta não gera vão** — por isso o
EM10 marcava 0,000 com a cabeça dentro do próprio tronco.
Correção: `model_space` passou a ser **exatamente** "o objeto está na bitmask do `dir[0]`".
Se o EMD não tem a seção, nenhum objeto é model-space. `_is_model_space` não é mais usada.
Depois: cabeça em y=0,96 (acima do torso), canelas em −1,66/−1,58 (abaixo do joelho).

**(b) A BIND tinha de ser TRANSLAÇÃO PURA, não a pose0.**
O conversor gravava a rotação de repouso = pose0 (`gbind(emr, bind_rot)`), herdado de §8.
Mas a tabela de coordenadas do `dir[0]` é `-world[i]` **sem rotação nenhuma** ⇒ o inverse bind
da engine é `T(-world)` e a bind é `T(+world)` com rotação identidade. Com a bind rotacionada,
a malha em espaço-modelo era "des-posada" por uma matriz errada: no visualizador o esqueleto
aparecia num lugar e a peça noutro (visível a olho nos tentáculos EM37/EM39/EM3B).
A conta que fecha com o PS1: `G_b(t) · T(-world_b) · (v + world_b) = M_b · v`, com
`M_b = T(relpos)·R` acumulado — exatamente o laço de FK do EXE (§10.2).
Efeito no `tear` (crescimento da bbox do objeto ao animar, 1,00 = rígido perfeito):

| | EM37 | EM39 | EM23 | EM28 | EM50 |
|---|---|---|---|---|---|
| bind = pose0 | 3,46 | 4,22 | 1,52 | 1,47 | 1,28 |
| bind = translação | **1,13** | **1,11** | **1,12** | **1,09** | **1,19** |

`EMD_BIND=pose0` volta ao antigo.

**(c) A 3ª lista de cada entrada é a lista de COSTURA (formato B).**
As listas 0 e 1 são `[osso][nbatches][idx]` (formato A). A 3ª/4ª é outra coisa: registros de
**8 bytes** `[u8 ossoA][u8 ossoB] + 3 × ([u8 idx][u8 peso])`, terminados por `0xFF`. São os
vértices da junta, com DOIS ossos nomeados explicitamente. Sem ler isso, ~6% dos vértices dos
objetos multi-osso ficavam órfãos e caíam na âncora. Prova: os vértices que "faltavam" no obj8
do EM5F (66, 78, 80, 83) estão exatamente lá, como `0x42, 0x4e, 0x50, 0x53`.
Cobertura completa: **94% → 97,5%** (236/242 objetos).
O 2º byte de cada par (`0x20`, `0x60`, `0x74`, `0x21`, `0x0d`…) tem cara de **peso**
(`0x20/128 = 0,25`, `0x60/128 = 0,75`) mas **não confirmei** — hoje é ignorado e o vértice fica
rígido no `ossoA`. Se alguém quiser fechar isso, é o próximo fio.

**Fallback limitado:** os 6 objetos que seguem sem cobertura (EM40 obj0 — cujo 1º grupo tem
`nbat=0` e não decodifica; e 5 objetos do EM64, que tem `anims=0`) usam o osso **mais próximo
entre os que a tabela já usa naquele objeto** — nunca a âncora, nunca um osso de fora do
conjunto real.

### 13.7 Resultado final (rig_check, 69 modelos, threshold 0,12)

| família | n | vão (antes → depois) | estica (antes → depois) |
|---|---|---|---|
| zumbi | 16 | 0,000 → 0,000 | 0,516 → **0,410** |
| humano | 28 | 0,038 → **0,026** | 0,416 → 0,440 |
| hunter | 2 | 0,059 → **0,028** | 0,452 → **0,417** |
| nemesis | 1 | 0,130 → **0,010** | 0,500 → **0,396** |
| verme | 3 | 0,067 → **0,027** | 0,302 → 0,311 |
| outros | 19 | 0,034 → **0,025** | 0,645 → **0,577** |
| **TOTAL** | **69** | **0,0311 → 0,0193** | **0,4998 → 0,4639** |

**Modelos acima do limiar: 5 → 1** (só `em5f`, 0,143, e o grupo culpado é de objetos de
**3 vértices** — marcadores degenerados, não malha visível).

Confirmado na cena: zumbis com cabeça no lugar; humanos andando com pernas, mãos e botas
presas; EM23/EM28 voltaram a ser criaturas coerentes (eram uma estrela de membros radiais);
EM37/EM39/EM3B viraram vermes contínuos (eram bastões soltos); hunter EM22 íntegro.

### 13.8 O que continua ABERTO

- **Objetos EXTRA (`i ≥ nb`)**: a bitmask do `dir[0]` só cobre `bit < nb`, então os extras
  seguem sem osso no dado — é a ausência real de §12.4. Afeta principalmente o **Nemesis
  (EM38)**, cujos obj23–26 são tampas de junta de centroide exatamente (0,0,0) (vão para o
  osso 0, dentro do corpo) e obj27–30 são o casaco. Hoje: model-space + junta mais próxima.
- **EM40**: o 1º grupo da lista tem `nbat=0` e não decodifica (0/72 vértices). A soma dos
  outros grupos fecha 72/72 exatos, então o dado está lá — falta descobrir o header desse
  primeiro grupo (bytes `00 00` onde se esperava `[osso][nbat]`).
- **EM64**: `anims=0` (nenhuma sequência EDD válida) + 5 objetos com cobertura parcial.
- **Peso da lista de costura** (item (c) acima).
- `estica` (esticão) segue alto em corvo (0,77), heli EM3E (0,87), EM26/EM40 (1,00),
  EM27 (0,95) — **modelos SEM `dir[0]`**, portanto fora do alcance desta correção. É outro
  defeito, provavelmente de animação/EDD, não de binding.

### 13.9 Terceira rodada — objetos EXTRA (`i ≥ nb`): a ARMA NA MÃO

Defeito relatado: "os que têm item/arma na mão hoje está no meio das pernas".

Causa: todo extra era tratado como **model-space** + osso da junta mais próxima do centroide.
A arma do EM50 tem centroide `(50, 196, 9) mm` — em espaço-modelo isso é o **quadril**, e a
junta mais próxima do quadril é a raiz. Resultado: a arma dentro das pernas.

O extra **não tem osso no formato** (a bitmask do `dir[0]` só cobre `bit < nb`) — é a ausência
real de dado da §12.4. Mas dá para decidir por geometria, com dois testes medidos:

**(1) espaço** — no eixo de maior extensão do extra, onde cai a origem local?
`t = (0 − min) / (max − min)`:

| | t | leitura |
|---|---|---|
| arma EM50 | 0,00 | **ponta** → bone-local (pendurada na junta) |
| rifle EM51/5C/5E | 0,15 | **ponta** → bone-local |
| espinhos EM36/3A (6×) | 0,06 | **ponta** → bone-local |
| tentáculo EM38 obj22 | 0,06 | **ponta** → bone-local |
| obj17 do EM34 / EM35 | 0,53 / 0,59 | **meio** → model-space (peça de corpo de 1,9 m) |
| casaco EM38 obj28/29 | 1,55 / 1,40 | origem fora → model-space |
| tampas de junta EM38 obj23–26 | 0,50 | **meio** → model-space |

Limiar: bone-local se `t ∈ [−0,15; 1,15]` e `min(|t|, |1−t|) < 0,25`.
(Tratar TODO extra como bone-local punha o obj17 do EM34 atravessado no corpo — a "barra
listrada" vertical que aparecia no visualizador.)

**(2) osso** — o extra bone-local vai no osso que faz a peça **ENCOSTAR na malha do corpo**.
Medido no EM50: osso 4 (mão esq.) a **0 mm** e osso 7 (mão dir.) a 21 mm da malha, contra
**≥ 24 mm** em todos os outros ossos. No EM51: 8 mm e 13 mm. Ou seja, a geometria aponta
"mão" sem ambiguidade. **ESQUERDA × DIREITA é irrecuperável do arquivo** (o corpo é simétrico
e o empate fica em poucos mm) — fica com o menor índice, e isto está assumido, não provado.

Resultado: EM50 pistola na mão, EM51/5C/5E rifle na mão, EM5D lançador (peça de 1755 mm) —
confirmado no render. No `rig_check` o **esticão** caiu em 10 modelos (em50 0,483→0,354;
em51 0,588→0,450; em36 0,602→0,451; zumbi_em17 0,461→0,383) e **subiu só no EM38**
(0,396→0,613), o único com 9 extras.

### 13.10 Placar consolidado (rig_check, 69 modelos, threshold 0,12)

| | antes (heurística) | §13.1–13.5 (tabela) | + bind translação (§13.6) | + extras (§13.9) |
|---|---|---|---|---|
| modelos descolados (>0,12) | 5 | 4 | **1** | **1** |
| vão médio | 0,0311 | 0,0346 | 0,0193 | **0,0196** |
| vão máximo | 0,226 | 0,359 | 0,143 | **0,143** |
| esticão médio | 0,4998 | 0,5070 | 0,4639 | **0,4496** |

### 13.11 Ainda ABERTO (estado honesto)

1. **`obj17` do EM34/EM35** — 72 verts, laje de 1,9 m, `page=[0,64] clut=[128,129]` (as mesmas
   do corpo). Sem osso no dado; hoje fica em model-space na posição autorada e ainda aparece
   como uma faixa vertical junto ao corpo no visualizador. **Não resolvido.**
2. **`em5f`** vão 0,143 (o único acima do limiar): o grupo culpado é de objetos de **3 vértices**
   (marcadores degenerados), não malha visível.
3. **EM40** — o 1º grupo da lista do `dir[0]` tem `nbat=0` e não decodifica (0/72 vértices);
   os outros grupos somam 72/72 exatos, então o dado está lá.
4. **EM64** — `anims=0` (nenhuma sequência EDD válida) + 5 objetos com cobertura parcial.
5. **EM38 (Nemesis)** — esticão subiu com a mudança dos extras (0,396→0,613). 9 extras, nenhum
   com osso no dado. É o pior caso do buraco da §12.4.
6. **`em28`** (drain deimos) e **`zumbi_em11`** — reportados como suspeitos no visualizador;
   a tabela cobre 100% dos objetos marcados nos dois e as arestas longas medidas são
   compatíveis com o tamanho real das peças (canela de 0,7 m no em11). **Não diagnostiquei
   causa** — pode ser a malha original ou a animação, não o binding.
7. **peso da lista de costura** (2º byte de cada par, §13.6-c) — ignorado.
8. `estica` alto em corvo (0,77), heli EM3E (0,87), EM26/EM40 (1,00), EM27 (0,95): **sem
   `dir[0]`**, fora do alcance desta correção.

---

## 14. NEMESIS (EM34 / EM35 / EM38) — estado, e a arma na mão

> **Identificação corrigida:** `em34_brain_sucker_incerto` e `em35_drain_deimos_incerto`
> **são o NEMESIS com o lança-rockets** (forma 1, sobretudo). `em38_nemesis_incerto` é a
> forma de tentáculos. Os nomes `_incerto` do catálogo estão errados nesses dois.

### 14.1 O corpo do EM38 está CORRETO (verificado osso por osso)

22 ossos, 31 objetos. **14 dos 22 ossos são marcadores de 3 vértices sem geometria** — toda a
malha vive em 8 objetos multi-osso, e a tabela do `dir[0]` cobre **os 22 ossos**, com cada
grupo caindo entre a sua junta e a próxima:

| objeto | ossos | conferência (y do grupo vs y da junta) |
|---|---|---|
| obj4 (braço-tentáculo esq., 4 segmentos) | 4/5/6/7/8 | 646/818/2092/3216/4371 vs −1192/255/1530/2655/3779 ✔ |
| obj16 (perna dir.) | 12/16/17/18/19 | 697/1223/2492/3780/5073 vs 82/610/1750/2964/4130 ✔ |
| obj13 (perna esq.) | 13/14/15 | 991/2514/3641 vs 610/1749/2963 ✔ |
| obj9 (braço dir.) | 9/10/11 | 807/544/1662 vs −1259/−232/761 ✔ |
| obj0, obj2, obj12, obj20 | 0/1, 1/2/3, 0/1/12/16/20/21, 20/21 | ✔ |

Vão: **0,130 → 0,010**.

### 14.2 Extras: espaço por `r = |centroide| / maior extensão`

Testado nos **42 extras dos 69 EMD**, separa sem exceção:

- `r < 1` → a peça **atravessa a própria origem** ⇒ **BONE-LOCAL** (pendurada na junta).
  Armas (0,09–0,55), espinhos do EM36 (0,34), tampas de junta do EM38 (0,00).
- `r ≥ 1` → a peça está **inteira deslocada** da origem ⇒ **MODEL-SPACE** (posição autorada).
  Só o casaco/tocos do Nemesis: **EM38 obj27–30, r = 1,65 / 1,68 / 1,69 / 2,01**.

Tratar tudo como model-space punha a **arma no meio do corpo**; tratar tudo como bone-local
deslocava o casaco do Nemesis do peito para o quadril.

### 14.3 A arma vai na MÃO ESQUERDA

**Classificador de arma** (peça densa, com tamanho e alongada): `verts ≥ 30`, `extensão máxima
> 300 mm` e `máxima ≥ 1,7 × a do meio`. Varrido nos 42 extras, seleciona **exatamente as
armas e nada mais**:

| | verts | extensões (mm) | alongamento |
|---|---|---|---|
| bazuca EM34 / EM35 obj17 | 72 | 357×561×1904 / 500×715×2547 | 3,39 / 3,56 |
| rifle EM51 / 5C / 5E | 98 | 159×487×1449 | 2,98 |
| lançador EM5D | 54 | 366×634×1755 | 2,77 |
| pistola EM50 / 52 / 53 / 56 | 38 | 153×228×414 | 1,71–1,96 |

Fica de fora: tampa de junta (alng 1,00), espinho fino de 18 verts (17–23), tocos do
Nemesis (1,0–1,2).

**Qual osso:** as MÃOS saem da hierarquia — ossos-**folha**, fora da linha central
(`|z|` grande) e **acima** dos pés (`+Y` é para baixo). No EM34 dá ossos **5 (z=−536)** e
**8 (z=+536)**.

**Qual lado:** a orientação foi medida pela geometria do PÉ (o pé se estende para a frente):
`+X` em EM34, EM50 e EM10, consistente. Com frente `+X` e cima `−Y` (EMD), a **esquerda do
personagem é EMD `z > 0`** → **osso 8** no EM34/EM35, **osso 7** no EM50–EM5E.
⚠ **Esquerda × direita NÃO está no arquivo** (o corpo é simétrico); a escolha da esquerda vem
da referência do jogo (o Nemesis carrega o lança-rockets na mão esquerda), não do dado.
Antes desta regra o score de penetração escolhia osso **11 (canela) no EM34 e 3 (ombro) no
EM35** — inconsistente entre gêmeos, prova de que o score sozinho é instável.

### 14.4 Onde o Nemesis ainda não está 100%

- **EM38 `obj22`** — haste fina de 18 verts, **3118 mm**, alongamento 18,6, na linha central
  (`x=z=0`, y de −181 a 2937). Não classifica como arma (poucos verts) e vai, por penetração,
  no **osso 1 (peito)**. É o que mantém o esticão em 0,600 (o grupo do osso 1 fica com uma
  diagonal longa). Tem cara de tentáculo retrátil, mas **o osso não está no dado**.
- **EM38 `obj23–26`** — 4 tampas de junta idênticas (12 verts, centroide exatamente (0,0,0)).
  Vão todas para o **osso 20**. São 4 peças para 4 juntas diferentes e **não há como saber
  quais** — ficam empilhadas.
- **EM35** esticão 0,636 → 0,670: a bazuca de 2547 mm na mão alonga o grupo daquele osso.
  É consequência esperada de pôr a arma na mão, não defeito de binding.

### 14.5 Resultado

| | vão | esticão |
|---|---|---|
| em34 | 0,057 → **0,017** | 0,653 → **0,517** |
| em35 | 0,053 → **0,018** | 0,636 → 0,670 |
| em38 | 0,130 → **0,010** | 0,500 → 0,600 |

Conferido no render: bazuca na mão esquerda em EM34 e EM35 (visível na fração 0,4 da
animação), casaco no peito, corpo coerente; EM38 lê como a criatura de tentáculos.

### 14.6 Outros achados desta rodada (fora do Nemesis)

- **EM28 "falta uma perna" — está no ARQUIVO.** Os ossos **6 e 7 não recebem geometria
  nenhuma** (nem objeto próprio, nem grupo na tabela), enquanto os espelhos 3 e 4 recebem:
  `obj2` = 54 verts cobrindo 3 ossos, o espelho `obj5` = **18 verts** cobrindo 1. A cadeia de
  `vtx_off` do EM28 é **sequencial sem uma única lacuna** (`fim == próximo` nos 21 objetos),
  logo `vc=18` é leitura correta. Assimetria real do dado, não do conversor.
- **EM11 "sem antebraço" — está no ARQUIVO.** `obj3` e `obj6` têm 16 vértices e
  `tri_off == quad_off` com `tc=0, qc=0`: nenhuma primitiva. Os vértices existem e nada os
  referencia.
- **EM2C cabeça/mão "estourada"** — vértices anômalos no arquivo (obj1 tem verts em `x=1534`,
  `z=1416` com mediana de distância 191). `_declaw_outliers` **não dispara** porque os
  anômalos estão em CLUSTER e se protegem no teste de vizinho-mais-próximo. Consertável
  trocando o critério por mediana robusta (MAD) sobre a distância ao centroide.
- **EM5D "arma muito grande"** — a peça tem 1755 mm num corpo cuja junta mais baixa está a
  1703 mm, ou seja, a arma é do tamanho da pessoa. **É a geometria do arquivo** (54 verts,
  offsets sequenciais); ou o objeto não é o lançador, ou a escala do modelo é essa mesma.
- **`PL00W*` / `PL08W*` "mão dentro da arma"** — outro pipeline (`tools/pld2gltf.py`, modelos
  estáticos de arma+mão, `ossos: 0`). Intocado por tudo o que está neste §. Note que
  `PL00W10`, `PL00W0E` e `PL00W0F` estão certos e `06/07/08/09/0B/0C/14` não — tem cara de
  offset de encaixe por arma, não de erro global.

### 14.7 EXTRA que é VARIANTE de uma peça do corpo → não desenhar ("cabeça no braço")

`EM36`/`EM3A` mostravam uma **segunda cabeça pendurada no braço**. Causa: `obj22` é uma
VARIANTE do `obj2` (a cabeça) — 78 verts em ambos, bbox `428x438x310` contra `430x442x310`,
diferença de **0,9%**. Não é cópia byte-a-byte (é outro estado de dano), então a engine
desenha **uma OU outra**, nunca as duas. Idem `obj23` ≈ `obj4` (20 verts, difere 0,4%).

Regra: extra com a **mesma contagem de vértices** e bbox igual a **< 5%** de alguma peça do
corpo é variante → **não emitida**. Varrido nos 69 EMD, pega **exatamente 4 casos**
(EM36 e EM3A, obj22 e obj23) e nada mais. EM36/EM3A caíram de 1209 para 1036 vértices;
esticão **0,602 → 0,483**.

### 14.8 EM5D "arma muito grande" — é o dado, medido

`obj15`: 54 verts, bbox **634 x 1755 x 366 mm**. Verificações:
- cadeia de `vtx_off` do EM5D **sequencial e sem lacuna** nos 16 objetos; `fim = 12664` contra
  `model_len = 16696` → **não estoura** o bloco. `vc=54` é leitura correta.
- **sem outliers**: distância ao centroide min 130 / p50 588 / p90 860 / max 1036 — dispersão
  uniforme. Removendo os 6 vértices mais distantes a bbox só cai de 1755 para 1348 mm.

Ou seja, a peça tem 1,75 m num corpo cuja junta mais baixa está a 1,70 m. **É a geometria do
arquivo.** Ou o `obj15` não é o lançador, ou a arte do PS1 é assim mesmo. Não há o que
corrigir no conversor sem inventar escala.
