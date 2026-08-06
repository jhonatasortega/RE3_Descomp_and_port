# Oclusão — máscaras de profundidade (priority sprites) do RE3 — **FORMATO 100% FECHADO**

> Dono: RE de formatos/rendering (RE3). Fonte de verdade: bytes das 169 salas
> (`extracted/ntsc-u/CD_DATA/STAGE*/*.ARD`, seção RDT), formato RE3 da wiki
> `reevengi-tools` (`.RDT (Resident Evil 3)` → herda `.RDT (Resident Evil 2/1)`),
> e validação por reconstrução visual (backgrounds HD + atlas HD `godot/assets/MASK`).
> Ferramenta: [`tools/rdt_collision.py`](../../../tools/rdt_collision.py) `decode_masks`
> → `godot/data/STAGE{n}/{sala}_col.json` → consumido por `godot/scripts/room_game.gd`.
>
> **NÃO edita `docs/formatos/ARD.md`** (fechado por outro agente); a correção da §3.7 do
> ARD.md está proposta ao fim deste doc.

---

## 0. Resumo (o que era 80% e o que fecha em 100%)

A oclusão do RE3 é o sistema de **priority sprites** do PS1: para cada câmera, uma lista
de sprites recorta o **1º plano** do cenário e o redesenha **por cima** do personagem
quando ele está atrás. Isso é **independente da colisão** (um cano oclui sem colidir;
uma caixa no chão colide sem ocluir).

O que estava **errado/incompleto** na decodificação anterior (o "80%"):
1. **Cabeçalho de grupo lido como 4 bytes** `(count, depth)` e o resto tratado como
   "lista plana" porque "além do grupo 0 não era inline". → Na verdade o descritor de
   grupo tem **8 bytes** e há **N descritores** cujos `count` **somam** `n_masks`.
2. **Discriminador de tamanho errado** (`byte +2 == 0` → 12B). O `byte +2` é o `dst_x`
   (pode ser 0 legitimamente), o que criava blocos de 12B **falsos** e desalinhava.
   O discriminador correto é **`byte +6 == 0`**.
3. **Ordem dos campos trocada**: lia `attr`/`w`/`sx`/`sy`/`dx`/`dy` de posições erradas.
   A ordem real é `sx, sy, dx, dy, depth(u16), size`. O antigo `attr` (bytes +0/+1) era
   na verdade `sx|sy<<8`; o "Z" real é o `depth` em **+4**.
4. **Z de tela não resolvido** (usava `depth0=30720` constante). O Z real é **per-sprite**
   (`depth*16`) e o `add_x/add_y` do grupo desloca o sprite na tela.

Fechado agora (provado, §2–§4): estrutura de cabeçalho, descritores de grupo, os **dois**
tipos de bloco (8B/12B) e o **discriminador**, a **ordem dos campos**, o **Z per-sprite**,
o mapeamento **fonte(atlas)→tela** (`add_x/add_y` somados; `sx,sy` no atlas) e a
**reconstrução completa** por câmera de todas as salas.

---

## 1. Onde vive

Cada câmera (RID, 32 bytes — ARD.md §3.3) tem em **`+0x1C` `u32 mask_data_ptr`**: offset,
dentro do RDT, do bloco de máscara **daquela** câmera. `mask_data_ptr == 0` ou cabeçalho
`0xFFFF` ⇒ câmera **sem máscara** (nada de 1º plano). Contadores do header do RDT:
`+0 nSprite`, `+7 nSprite_max` (ARD.md §3.1) contam esses sprites.

---

## 2. Layout binário (little-endian) — **CONFIRMADO byte-a-byte**

```
@mask_data_ptr:
  +0x00  u16  n_offsets     // nº de GRUPOS de máscara (0xFFFF = SEM máscara)
  +0x02  u16  n_masks       // nº total de sprites

  n_offsets DESCRITORES de grupo, 8 bytes cada:
    +0x00  u16  count       // nº de sprites deste grupo
    +0x02  u16  z_base      // = 30720 (0x7800) CONSTANTE em 100% dos grupos (Z-base do OT)
    +0x04  u16  add_x       // deslocamento de TELA (px) somado ao dst de CADA sprite do grupo
    +0x06  u16  add_y

  n_masks SPRITES, em ORDEM de grupo (os `count` do grupo g consomem os próximos count sprites).
  Tamanho por DISCRIMINADOR = byte +6:
    SQUARE (8 bytes) — quando byte +6 != 0:
      +0x00  u8   src_x      // origem no ATLAS de máscara (VRAM PS1 / godot/assets/MASK)
      +0x01  u8   src_y
      +0x02  u8   dst_x      // canto do sprite na TELA (px, espaço 320x240)
      +0x03  u8   dst_y
      +0x04  u16  depth      // Z/16 (RE1: "distância/16"); Z real = depth*16
      +0x06  u8   size       // largura E altura (w = h = size), em px; != 0
      +0x07  u8   0
    RECT (12 bytes) — quando byte +6 == 0:
      +0x00  u8   src_x
      +0x01  u8   src_y
      +0x02  u8   dst_x
      +0x03  u8   dst_y
      +0x04  u16  depth
      +0x06  u16  0          // marcador de "rect" (é o que o discriminador testa)
      +0x08  u16  w          // largura explícita (px)
      +0x0A  u16  h          // altura explícita (px)
```

**Posição de TELA final** de cada sprite = **`(dst_x + add_x, dst_y + add_y)`**, tamanho
`(w, h)`. **Z per-sprite** (ordenação; menor = mais perto) = **`depth * 16`**.

> Isto é a estrutura `rdt_masks_t` + `rdt_mask_offset_t` (8B) + `rdt_square_mask_t`/
> `rdt_rect_mask_t` da reevengi, com a **ordem de campos do RE1/RE2** (`src` antes de `dst`;
> `depth` em +4). A regra "12B se byte 7 == 0" do RE1 vira, no RE3, "**12B se byte +6 == 0**"
> (no square do RE3 o `size` está em +6 e o +7 é o pad zero, então o discriminador migra p/ +6).

### Exemplo real — `STAGE1/R100`, câmera 1 (`mask_data_ptr = 0x4C0`)

```
0x4C0: 04 00 62 00           n_offsets=4  n_masks=98
0x4C4: 23 00 00 78 D0 00 80 00   grupo0: count=35 z_base=0x7800 add=(208,128)
0x4CC: 02 00 00 78 00 01 A0 00   grupo1: count=2  z_base=0x7800 add=(256,160)
0x4D4: 32 00 00 78 00 00 A0 00   grupo2: count=50 z_base=0x7800 add=(0,160)
0x4DC: 0B 00 00 78 00 00 B0 00   grupo3: count=11 z_base=0x7800 add=(0,176)   (35+2+50+11=98 ✓)
0x4E4: 18 68 10 00 A8 00 08 00   sprite: SQUARE src=(24,104) dst=(16,0) depth=0x0068=104 size=8
       ...                        → tela=(16+208,0+128)=(224,128) 8x8, Z=104*16=1664
```

---

## 3. Provas (bytes → região)

1. **Invariante de cabeçalho (o mais forte):** em **1507/1507 câmeras** com máscara (169
   salas), `Σ descritor.count == n_masks`. Nenhuma exceção. Prova que o descritor é de 8
   bytes e que os grupos particionam a lista de sprites.
2. **Terminação limpa / sem overrun:** parseando exatamente `n_masks` sprites com o
   discriminador `byte +6`, **0 câmeras** ultrapassam a próxima seção do RDT; a R100 cam0
   termina **exatamente** no início da cam1 (0x200→0x4C0, 704 bytes = 55×8 + 22×12).
3. **Tile-runs coerentes:** dentro de um objeto, sprites 8×8 marcham `dst_x` contíguo
   (48,56,64…) com `depth` constante e `src_x` marchando no atlas — só faz sentido com a
   ordem de campos acima (o discriminador/ordem antigos produziam `depth` e `w` sem sentido).
4. **Atlas (src) confirmado vs máscara HD** (`godot/assets/MASK/STAGE1/R100_0_m0.webp`):
   **100% do alpha do atlas HD cai dentro das regiões `(src_x,src_y,w,h)` decodificadas**
   (recall = 1.0; escala horizontal 8×, atlas de 256 px de página). Confirma que `src_x,src_y`
   indexam o atlas de máscara.
5. **Tela (dst+add) confirmada vs BACKGROUND HD** (`godot/assets/STAGE1/R100_{0,1}.webp`):
   sobrepondo as regiões de tela sobre a foto, elas cobrem **exatamente** os móveis de 1º
   plano — R100 cam0: o balcão/mesa do canto inferior-direito (e **não** os canos/caixa de
   fusíveis da parede ao fundo); cam1: o carrinho (inferior-esquerdo) + balcão e corrimão
   diagonal (direita). Confirma o `add_x/add_y` somado e que oclusão ≠ colisão.

### Estatística global (169 salas)

| item | valor |
|---|---|
| câmeras totais | 2105 |
| câmeras COM máscara | 1507 |
| câmeras SEM máscara (`n_offsets=0xFFFF` ou `n_masks=0`) | 598 |
| sprites (máscaras) totais | 111.644 |
| RECT (12B) | 85.748 (76,8%) |
| SQUARE (8B) | 25.896 (23,2%) |
| `z_base` distintos | **1** (sempre 30720) |
| `Σcount == n_masks` | **1507/1507 (100%)** |
| Z per-sprite (`depth*16`) | 48 … 49.136 |

---

## 4. Saída para o remake (`{sala}_col.json`)

`decode_masks` reagrupa os sprites por **profundidade per-sprite** e emite o formato que
`room_game.gd` consome direto (um quad de holdout por sprite; `depth` → distância do quad):

```json
"cameras_masks": [
  {
    "offset_in_rdt": 1216,
    "n_offsets": 4,          // nº de grupos NATIVOS do RDT
    "n_masks": 98,
    "parsed_masks": 98,      // == n_masks (sanidade)
    "z_base": 30720,         // constante do OT
    "primary_depth": 2000,   // plano mais À FRENTE (menor Z per-sprite)
    "groups": [              // 1 grupo por profundidade per-sprite, do MAIS PERTO ao mais LONGE
      { "depth": 2000, "count": 2,
        "blocks": [ { "dx": 224, "dy": 128, "w": 8, "h": 8, "sx": 24, "sy": 104, "z": 2000 }, ... ] },
      ...
    ]
  },
  null,   // câmera sem máscara
  ...
]
```

- `dx,dy` = canto na **TELA 320×240** (`add_x/add_y` **já somado**). `w,h` = tamanho em px.
- `sx,sy` = origem no **atlas de máscara** (`godot/assets/MASK/STAGE{n}/{sala}_{cam}_m*.webp`),
  para oclusão pixel-exata (amostrar `sx,sy,w,h` do atlas e blitar em `dx,dy`).
- `z` (= `depth*16`) = Z de ordenação **per-sprite** (menor = mais perto da câmera). Está na
  **mesma família de unidade** que `z_base=30720` (o 30720 fica ~no meio da faixa 48..49136).
- `groups[].depth` = o `z` daquele bucket. `room_game.gd` faz `dist = depth * occ_depth_scale`
  por grupo — agora com o Z **per-sprite** (recalibrar `occ_depth_scale` para a nova escala:
  a antiga usava o 30720 fixo; a nova usa `depth*16` ~ centenas..dezenas-de-milhar).

---

## 5. Atlas de máscara (fonte) — `godot/assets/MASK/`

`{sala}_{cam}_m{0,1}.webp` (2048×2048 RGBA) = o **atlas de máscara HD** daquela câmera
(páginas `m0`/`m1`). `src_x,src_y,w,h` (espaço de página 256 px, escala HD ≈ 8× no eixo x)
indexam esse atlas. Validado: recall = 1.0 do alpha do atlas sob as regiões `src`
decodificadas (R100 cam0). Com atlas + `(src→dst)` + `z`, a oclusão é **pixel-exata**; o
remake pode usar o holdout por retângulo (atual) ou blitar o recorte do atlas.

---

## 6. Resíduos honestos (não infla)

- `add_x/add_y` dos descritores: **aplicado** (dst final = dst+add) — validado por overlay no
  background (R100) e por "cabe em 320×240" reaproveitando as bordas exatas (p95 = 320/240).
  A wiki chama de "dst a ser somado"; confirma. Único ponto não-provado ao **nível de disasm**
  do EXE (mas provado por render nas duas câmeras da R100 e consistente nas 1507).
- `z_base` (o `+2` do descritor) é **sempre** 30720; tratamos como Z-base/near do OT (constante
  do motor), não como profundidade útil. Byte `+7` do square e `+6..+7` (u16 zero) do rect são
  pad/marcador — sem outro papel observado.
- A escala VERTICAL exata do atlas HD (`m0/m1`) é convenção do pacote de assets HD, não do
  RDT; irrelevante para o formato (a escala horizontal 8× e o recall=1.0 já ancoram `src`).

---

## 7. Proposta ao dono do `progress.json` / `ARD.md` (§3.7)

- `oclusao`: **80 → 100** (decompilado). Formato 100% fechado e validado (1507/1507 câmeras;
  atlas por recall=1.0; tela por overlay no background). `vinculado` pode subir quando
  `room_game.gd` recalibrar `occ_depth_scale` para o Z per-sprite.
- Correção do ARD.md §3.7 (o texto atual tem os campos trocados): descritor de grupo é **8B**
  `(count, z_base=0x7800, add_x, add_y)`; `Σcount==n_masks`; discriminador é **byte +6**;
  ordem do bloco = `src_x, src_y, dst_x, dst_y, u16 depth, size/…`; tela = `dst+add`;
  Z per-sprite = `depth*16`. O antigo "`pri`/`attr` = +0/+1" era `src_x|src_y<<8` (não o Z).
</content>
</invoke>

---

## Achado do PORT (2026-07-31) — o atlas HD **não** é indexável por `sx,sy` em 8×

> Registrado durante o item **P1-07** do port (`port/room/occlusion.gd`). Não altera o formato
> do RDT (que está certo); corrige a expectativa sobre o **atlas de máscara HD**.

Medi o bounding box do canal alpha dos atlas HD da R100 e comparei com o alcance das regiões
`src` (`sx+w`, `sy+h`) daquela câmera:

| página | bbox do alpha | `src` máx | escala implicada |
|---|---|---|---|
| cam 0 · `m0` | x[3, 2037] y[3, 157] | x 256, y 48 | x ≈ **7,96** · y ≈ **3,27** |
| cam 1 · `m0` | x[3, 2037] y[3, 277] | x 256, y 112 | x ≈ **7,96** · y ≈ **2,47** |
| cam 0 · `m1` | x[3, 573] y[3, 69] | x 256, y 48 | x ≈ **2,24** · y ≈ **1,44** |
| cam 1 · `m1` | x[3, 1293] y[3, 69] | x 256, y 112 | x ≈ **5,05** · y ≈ **0,62** |

A escala horizontal fecha em 8× **só no `m0`**; a vertical **varia por câmera** e o `m1` não
fecha em nenhum eixo. Conclusão: o atlas HD usa o **empacotamento do próprio mod**, não as
coordenadas de VRAM do PS1 escaladas.

**Sobre o "recall = 1.0" que validava o mapeamento:** é um teste fraco. A união das regiões
`src` em 8× cobre a faixa inteira onde o alpha existe, então recall 1.0 sai de graça — ele
prova que o alpha está *dentro* da união, não que cada sprite está no lugar certo.

### Como o port resolveu (sem depender do atlas)

O recorte de primeiro plano é, por definição, **o próprio cenário naquela posição de tela**.
Então os pixels saem do **background HD no MESMO retângulo** (`dx,dy,w,h` ×4) — redesenhar o
pedaço do cenário sobre o personagem dá o efeito de oclusão com a silhueta real (a
granularidade vem da quantidade de blocos pequenos: 77 blocos de 8×8 só na câmera 0 da R100).

**Validação (forte):** renderizar os 77 recortes sobre o background, sem personagem, e
comparar com o background puro → **0 pixel de diferença** (bbox de diferença vazio). Se algum
retângulo estivesse deslocado, apareceria como remendo.

**Limite declarado:** blocos com alpha PARCIAL (vão de escada, grade) ficam opacos, porque a
forma per-pixel vive no atlas que não sabemos indexar. Fechar isso exige extrair o atlas de
máscara do **PS1** (blocos de gráficos tipo 5/6 do ARD, ainda não decodificados) ou descobrir
o de-para do empacotamento HD.

**Pendência de calibração:** o teste de profundidade (`Z do sprite` vs profundidade do
personagem) precisa do fator de conversão. A R100 câmera 0 é **degenerada** para isso: os 77
sprites compartilham `Z = 2368`, então ou todos cobrem ou nenhum cobre. Calibrar exige uma
câmera com múltiplos grupos de profundidade.

## A REGRA DE DECISÃO — fechada no EXE (2026-08-02)

Não há comparação de profundidade: é **painter's algorithm na Ordering Table**. Provado:

- OT com **1024 entradas por banco** e N+1 bancos; N = u16 no início da seção
  `offset_table[14]` do RDT (78/169 salas têm; N ∈ {0..3}) — alocador `0x80037e80`.
- **Sprite de máscara**: entra na OT com `bank = depth>>10`, `entry = depth & 1023`
  (`0x80048844`) — a chave é o **depth CRU** do RDT. Nada de `depth*16`; o 30720 (0x7800) é o
  CLUT do SPRT (`0x8004876c`). Gate de grupo: bitmask de 32 u32 em `gs+0x7914` (default tudo
  ligado), testada por `0x80078930`.
- **Personagem**: `bank` = zona de prioridade da seção 14 que contém o (x,z)
  (`0x80037d50`; RECT 12B testado unsigned `0x800101c8`, QUAD 20B via `0x8001020c`;
  flags bit1 = ignorar; sem zona → banco 0). `entry` = média dos SZ dos vértices `>> 5`
  (tri: `(341×ΣSZ)>>12>>3` ≈ média>>5; quad: `ΣSZ>>7` exato — `0x8002b6fc/0x8002b86c`),
  SZ = Z de câmera em unidades de mundo (matriz 1.12 unitária, `0x80078954`), clamp 32767.
- **Ordem de desenho** (`0x80029618`): bancos N..1, banco 0 por último; `DrawOTag(&ot[1023])`
  desce até 0 ⇒ **chave menor = desenhado depois = NA FRENTE**.
- Decisão: `sprite_na_frente ⟺ depth < bank_char*1024 + min(SZ>>5, 1023)`.

Implementação no port: `tools/rdt_collision.py::decode_priority_zones` (seção 14 →
`priority_zones` no `_col.json`), `port/room/occlusion.gd` (chave de OT por sprite e por
personagem). Aproximação declarada: decisão por PERSONAGEM (SZ do torso), não por polígono.
