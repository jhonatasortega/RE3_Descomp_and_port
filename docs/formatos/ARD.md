# Formato `.ARD` — dados de sala do RE3 (PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `ard`, `cameras`, `rvd`, `colisao`, `oclusao`)
> - **Formato:** contêiner de sala alinhado a setor (0x800); 8 blocos de gráficos/VRAM + RDT (lógica) + máscara extra
> - **Extensão/origem:** `CD_DATA/STAGE1..7/*.ARD` (169 salas)
> - **Ferramenta:** [`tools/ard_parse.py`](../../tools/ard_parse.py), [`rdt_collision.py`](../../tools/rdt_collision.py), [`cameras_to_3d.py`](../../tools/cameras_to_3d.py) → `godot/data/STAGE{n}/<sala>.json`
> - **Decompilado:** **100%** contêiner/câmeras (2105)/colisão · **100%** RVD · **80%** oclusão (`mask_data_ptr`)
> - **Feito:** cabeçalho, tabela de blocos, RDT, câmeras (RID), colisão (SCA), zonas RVD (flags decifrados **+ consumidor per-frame `0x8002a84c` provado no EXE**, §3.5.1), layout do bloco de máscara. **Papéis dos offsets resolvidos** (reevengi): 0/1/2=áudio VAB, 6=colisão, 7=câmeras, 8=RVD, 9=iluminação (LIT), 16=SCD, 22=anim (RBJ).
> - **Falta:** decodificar o **atlas TIM** da máscara (no BSS) p/ oclusão pixel-exata (Fase B4 do [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md)); blocos de gráficos → PNG. O **script SCD** tem doc próprio: [SCD.md](SCD.md) (formato) e [scd_gameplay.md](scd_gameplay.md) (extração).

> Engenharia reversa feita byte-a-byte sobre as **169 salas** de
> `extracted/ntsc-u/CD_DATA/STAGE1..7/*.ARD`. Tudo abaixo marcado como
> **confirmado** foi validado nas 169 salas; o resto está marcado como
> *(provável)* ou *(a decodificar)*. Parser: [`tools/ard_parse.py`](../../tools/ard_parse.py).
> Saída JSON: `godot/data/STAGE{n}/<sala>.json`.

## Visão geral

O `.ARD` é um **contêiner alinhado ao setor de CD (0x800)**. Ele guarda 10 sub-blocos:
8 de **gráficos/VRAM** (texturas e máscaras de profundidade da sala) e o **RDT** — o
bloco com a lógica da sala (câmeras, colisão, modelos de objeto, script SCD com itens e
inimigos). O background em si **não** fica aqui — está no `.BSS` de mesmo nome.

Progresso do decode:

| Parte | Status |
|---|---|
| Cabeçalho do contêiner + tabela de blocos | ✅ **confirmado** |
| Classificação dos 10 blocos (tipos) | ✅ **confirmado** |
| Cabeçalho do RDT + tabela de offsets (22 ponteiros) | ✅ **confirmado** |
| **Lista de câmeras** (posição/alvo 3D) | ✅ **confirmado** (2105 câmeras) |
| Localização do **script SCD** | ✅ **confirmado** |
| **Zonas de troca de câmera (RVD)** — `offset_table[8]` | ✅ **decodificado** (from→to + quad; ver §3.5) |
| Máscaras de profundidade (oclusão) | 🟡 parcial (offsets mapeados) |
| **Bytecode SCD** (portas, triggers, entidades) | ✅ **parcial** → [SCD.md](SCD.md) |
| Imagens dos blocos de gráficos → PNG | ⬜ a decodificar |

Todos os números são **little-endian**. Coordenadas 3D são **inteiros com sinal em
ponto-fixo** (unidades do mundo do RE; sem escala aplicada aqui).

---

## 1. Cabeçalho do contêiner + tabela de blocos  ✅

```
+0x00  u32  file_size      // == tamanho do arquivo (confere nas 169 salas)
+0x04  u32  block_count    // == 10 em todas as salas
+0x08  block_entry[block_count]   // 8 bytes cada
```

Cada entrada da tabela (8 bytes):

```
+0x00  u32  length     // tamanho do bloco em bytes
+0x04  u16  flagA       // byte baixo = tipo do recurso; byte alto = variante (0x00/0x02)
+0x06  u16  flagB       // provável checksum/hash do conteúdo (blocos iguais → flagB igual)
```

**Layout dos dados:** logo após a tabela vêm os 10 blocos, **cada um alinhado a
0x800**, começando em `0x800` (setor 1). O padding entre blocos é sempre `0x00`, e o
último bloco termina exatamente no tamanho do arquivo.

```
offset(bloco 0)  = 0x800
offset(bloco i)  = round_up(offset(i-1) + length(i-1), 0x800)
```

Exemplo real — `STAGE1/R100.ARD` (387072 bytes):

```
0000  00 E8 05 00  0A 00 00 00   file_size=0x5E800  block_count=10
0008  A4 08 00 00  05 00 2B 07   bloco0: len=0x8A4  tipo=05 var=00  chk=0x072B
0010  20 4A 03 00  05 02 56 07   bloco1: len=0x34A20 tipo=05 var=02 chk=0x0756
...
0048  98 AA 01 00  00 00 BE 00   bloco8: len=0x1AA98 tipo=00 var=00  chk=0x00BE  (RDT)
0050  F0 9D 00 00  02 02 4C 00   bloco9: len=0x9DF0  tipo=02 var=02  chk=0x004C
```

## 2. Os 10 blocos  ✅

A sequência de **tipos** (byte baixo de `flagA`) é sempre a mesma nas 169 salas:

```
índice:  0  1  2  3  4  5  6  7  8  9
tipo:    5  5  5  5  6  6  6  6  0  2
```

| tipo | papel | detalhe |
|---|---|---|
| **0x05** (`graphics_a`) | Gráficos/VRAM — conjunto A | 4 blocos = 2 pares (descritor + payload). Ver §2.1 |
| **0x06** (`graphics_b`) | Gráficos/VRAM — conjunto B | idem, segundo conjunto |
| **0x00** (`rdt`) | **RDT — lógica da sala** | câmeras, colisão, objetos, script. **§3** |
| **0x02** (`mask_extra`) | Payload extra de máscara/sprite | binário denso (provável comprimido) |

- O **byte alto** de `flagA` (a "variante") é `0x00` para blocos "descritor/crus"
  (cabeçalhos e o RDT) e `0x02` para blocos de **payload** (imagem/dados densos,
  provavelmente comprimidos — começam com 16 bytes `0x00` seguidos de dados de alta
  entropia).
- O **RDT é sempre o bloco de índice 8** (tipo `0x00`).

### 2.1 Blocos de gráficos (tipos 5/6) 🟡

Os blocos "descritor" (variante `0x00`) começam com um cabeçalho de transferência para a
VRAM do PS1:

```
+0x00  u32  count/size
+0x04  u32  ?          (endereço/checksum)
+0x08  30 00 04 02     assinatura fixa
+0x0C  registros de 3–4 bytes: id de tpage/CLUT (0xC0..0xC7, 0xB0..0xB2) + coords de retângulo na VRAM
```

O bloco de **payload** pareado (variante `0x02`, ex.: 215584 bytes em R100) contém a
imagem em si (sprites de primeiro plano e **máscaras de profundidade** que se sobrepõem
ao background do `.BSS`). Alguns pares são apenas **placeholders** de 116/112 bytes
(conteúdo idêntico entre salas — mesmo `flagB`), provavelmente slots não usados
(variação por personagem/cenário). Decodificar essas imagens para PNG fica para depois.

---

## 3. RDT — bloco de lógica da sala (índice 8, tipo 0x00)  ✅

### 3.1 Cabeçalho do RDT

```
+0x00  u8   nSprite     // nº de sprites de máscara de prioridade (oclusão)  ✅ (reevengi)
+0x01  u8   nCut        // número de câmeras  ✅ confirmado (1..32)
+0x02  u8   nOmodel     // nº de modelos de objeto da sala  ✅ (reevengi)
+0x03  u8   nItem       // nº de itens  ✅ (reevengi)
+0x04  u8   0
+0x05  u8   0
+0x06  u8   Reverb_lv   // nível de reverb de áudio da sala  ✅ (reevengi)
+0x07  u8   nSprite_max // máximo de sprites de máscara  ✅ (reevengi)
+0x08  u32  offset_table[22]   // ponteiros para as seções, relativos ao início do RDT
```
> ✅ **Papéis do header resolvidos** cruzando com a wiki `reevengi-tools` (`.RDT` RE3) e
> validando nos bytes das 169 salas (antes marcados "?"). Ver `../decomp/notes/sala_logica.md §1`.

### 3.2 Tabela de offsets (22 ponteiros)  ✅ estrutura / 🟡 papéis

A tabela tem 22 entradas u32 (offsets dentro do RDT; `0` = seção ausente). A frequência
de uso (em 169 salas) e os papéis conhecidos:

Papéis cruzados com a wiki `reevengi-tools` (`.RDT` RE3) — resolve os "🟡" antigos:

| índice | uso | papel |
|---|---|---|
| **0, 1, 2** | 169 | **ÁUDIO da sala** ✅ — `pVb0`/`pVh0`/`pVh1` (banco VAB + headers VH) |
| 3, 4, 5 | 0 | sempre ausentes |
| **6** | 169 | **COLISÃO (SCA)** ✅ — retângulos de parede+móvel (§3.6) |
| **7** | 169 | **câmeras (RID)** ✅ — sempre aponta para `0x60` |
| **8** | 169 | **RVD — zonas de troca de câmera** ✅ (from→to + quad; §3.5) |
| **9** | 169 | **ILUMINAÇÃO (LIT)** ✅ (reevengi) — resolve o antigo "piso/luz" |
| 10..15 | 169 | modelos/texturas/mensagens (`pMD2`/MSG/TIM) *(por-índice a confirmar)* |
| **16** | 169 | **script SCD** ✅ (Main+Sub ambos aqui) |
| 17–21 | ~167 | seções tardias *(a confirmar)* |
| **22** | var | **animação (RBJ)** ✅ (reevengi) — ausente se a sala não tem anim |

> Fonte: `github.com/pmandin/reevengi-tools/wiki/.RDT-(Resident-Evil-3)` + validação nos bytes.
> Detalhes em `../decomp/notes/sala_logica.md §1`.

### 3.3 Câmeras (RID) — **totalmente decodificado**  ✅

Apontadas por `offset_table[7]` (sempre `0x60`, logo após a tabela). São `n_cameras`
structs de **32 bytes**:

```
+0x00  u16  flag       // quase sempre 0; às vezes 1
+0x02  u16  attr       // provável FOV/projeção (24 valores distintos no jogo todo)
+0x04  s32  from_x     // posição da câmera (ponto-fixo)
+0x08  s32  from_y
+0x0C  s32  from_z
+0x10  s32  to_x       // alvo / ponto que a câmera olha
+0x14  s32  to_y
+0x18  s32  to_z
+0x1C  u32  mask_data_ptr  // offset (no RDT) da máscara de profundidade desta câmera
```

Validação: **2105 câmeras** em 169 salas, todas com coordenadas sãs
(|coord| ≤ 44388). Exemplo (`R100`, câmera 0):
`from=(-23364,-4788,-24156) to=(-20790,-1458,-20394) attr=29623`.

### 3.4 Script SCD  ✅ localizado + gameplay parcial → [SCD.md](SCD.md)

Apontado por `offset_table[16]`. Começa com uma **tabela de ponteiros de função**
(`+0x00 u16 tbl_size`, depois `func_offset[]`), seguida do **bytecode**. Ex.: `R100` tem
9 funções; `R104`, 23.

**Itens, inimigos, portas e eventos** no RE3 **não** têm tabela estática: são posicionados
por **opcodes dentro do SCD**. Já decodificado e exportado no JSON (`rdt.script`):
**481 portas** (todas com posição de chegada), **738 gatilhos** (0x63/0x64), **433
entidades** (0x61/0x62) e **14 itens** auto-pega (0x68), todos com posição. O **formato**
do bytecode está em [SCD.md](SCD.md); a **extração de gameplay** (com estes totais) em
[scd_gameplay.md](scd_gameplay.md).

### 3.5 RVD — zonas de troca de câmera  ✅

Apontadas por `offset_table[8]` (começa logo após as câmeras). Lista de structs de
**20 bytes**, terminada por `0xFFFF`:

```
+0x00  u16  flags        // controle (0x8001, 0x0100, 0x8000, …); 0xFFFF = fim da lista
+0x02  u8   from_cam     // câmera de ORIGEM (você está nela)
+0x03  u8   to_cam       // câmera de DESTINO
+0x04  s16[8]            // 4 pontos (x,z) do quadrilátero, no plano do chão
```

Exportado em `rdt.rvd` (`{count, entries:[{flags,from,to,quad,degenerate}]}`) pelo
`ard_parse.parse_rvd`.

#### Semântica (engenharia reversa sobre as 169 salas / 4585 entradas)

- Cada entrada é uma **zona direcional** `from → to` no plano do chão.
- **`degenerate`** = o quad tem alguma coord `±32768`: o quad se estende ao
  **infinito/frustum**. **Não é** a "cobertura própria" da câmera — **427/456**
  entradas degeneradas têm `from ≠ to`. É só um gatilho de quad ilimitado.
- As zonas `from ≠ to` (degeneradas ou não) são **faixas/regiões direcionais de
  troca**. Elas costumam vir em **pares opostos** (`A→B` e `B→A`) ligeiramente
  **deslocados**, formando uma **zona morta de histerese** na fronteira entre duas
  câmeras. **Não cobrem a área toda** da câmera de destino — cobrem só a *borda*.
  Por isso disparar a troca ao **entrar** na faixa joga o personagem para a **beira**
  da tela da câmera nova (bug "pula pra beira", observado e corrigido no remake).
- As zonas `from == to` (142 não-deg + 29 deg) são regiões onde a câmera atual
  **se mantém** (auto-alvo / "não trocar aqui").
- **`flags`** (distribuição nas 169 salas): `0x8001` domina (**89%**, 4087). O
  **bit baixo `0x0001`** = "**zona ativa**"; entradas `0x**00` (`0x8000`, `0x0100`,
  `0x0000`, …) = desativadas. O **byte alto** = **id de grupo espacial** (`0x80` =
  grupo global/wildcard dominante; `0x01..0x1f` = sub-grupos). A `degenerate` **não**
  vem do flag (vem das coords). Estes dois papéis (bit0=ativa, byte-alto=grupo) foram
  **PROVADOS no código** — ver §3.5.1.

#### 3.5.1 Consumidor per-frame do RVD — **LOCALIZADO E PROVADO no EXE**  ✅

> Fecha o antigo resíduo ("a função consumidora per-frame do RVD não foi localizável
> estaticamente"). A rotina existe e é isolável: **`0x8002a84c`** (SLUS_009.23, base
> `0x80010000`). Não aparecia nos xrefs por stride porque lê o RDT via load **absoluto**
> (`lui 0x800d; lw -0x3794(..)` = `0x800cc86c` = `gs+0x2134`), não via `lw 0x2134(gs)`.

Cada frame, `0x8002a84c` (chamada de `0x80023b84` a0=0 e `0x80024abc` a0=1 — update de
sala; o `a0` faz a histerese em 2 fases: detectar vs. commitar, `0x8002a8ec`):

| passo | endereço | instrução (prova) |
|---|---|---|
| **RVD ptr** = `*(0x800cc86c)+0x28` (offset_table[8]) | `0x8002a968` (finder) | `lw $v0,-0x3794($..)` · `lw $v1,0x28($v0)` |
| **stride 0x14** (entradas de 20 B) | `0x8002a87c` / `0x8002a8d4` | `addiu $s1,$a0,0x14` |
| **histerese**: ancora na entrada ativa atual `gs+0x2148` | `0x8002a874` | `lw $a0,0x2148($s2)` |
| **`from_cam`(+2) == câmera atual** `gs+0x2486` | `0x8002a880`/`0x8002a888` | `lbu $v1,2($s1)` · `bne $v1,$v0` |
| **BIT0 / zona ativa** (byte baixo dos flags, +0) | `0x8002a894`/`0x8002a89c` | `lbu $v0,($s1)` · `beqz $v0` → pula se low==0 |
| **BYTE-ALTO = grupo** (flags +1) | `0x8002a8a4`/`0x8ac`/`0x8bc` | `lb $v1,-1($s0)` · `beq $v1,-0x80` (0x80=global) OU `bne $v1,gs+0x2495` |
| **ponto-em-quad** (player vs 4 pontos) | `0x8001020c` | `a0`=player `gs+0x24c0`(X@+0,Z@+8), `a1`=entry; quad em +4/+6,+8/+0xa,+0xc/+0xe,+0x10/+0x12; 4 testes de sinal de produto vetorial |
| **`to_cam`(+3)** → commit | `0x8002a8fc` → `0x8002a938` | `lbu $a0,3($s1)`; seta `gs+0x2486` e `gs+0x2148` |

O commit dispara a máquina de estados de fade `0x8005190c`, que copia `gs+0x7846`(alvo)→
**`gs+0x7842` = índice de câmera CORRENTE** (usado pelo render/GTE em `0x80074fd0` e
`0x80029edc`: `lh cur,0x7842; sll cur,5` → indexa `camera[cur]` em `rdt+0x24`). O opcode
SCD do handler `0x80054a68` (avança PC+3) **remapeia** `from`/`to` no RVD em runtime
(puzzles) — corrobora o layout. Player X/Z em `gs+0x24c0/+0x24c8` (escritos em
`0x8002498c/0x800249c0`).

> **Nota honesta:** o teste de "zona ativa" no código é `byte_baixo(flags) != 0` (não um
> `& 1` literal); como os flags reais só têm byte baixo `0x00`/`0x01`, isso **coincide**
> com bit0. O byte-alto é comparado com `0x80` (grupo global) OU com o seletor de grupo
> corrente `gs+0x2495`. O **remake** continua escolhendo a câmera por enquadramento +
> grafo de vizinhança (equivalente, sem flicker), independente deste bit-test — que agora
> está **provado**, não apenas inferido por clustering.

Exemplo (`R100`, 2 câmeras, todas as 4 entradas `0x8001`): `0→0` (deg, mantém cam0),
`0→1` (faixa), `1→0` (deg) e `1→0` (faixa). As duas faixas `0→1` e `1→0` são o par de
histerese entre o depósito (cam0) e o escritório (cam1).

#### Algoritmo GERAL de seleção de câmera (usado no remake)

As faixas RVD, se usadas como **gatilho de borda**, enquadram mal no corte (§ acima).
O remake seleciona a câmera **por enquadramento** (medido por projeção), usando o RVD
como grafo de adjacência. É **geral** (qualquer nº de câmeras), **bidirecional** e sem
flicker; **`init == runtime`** (mesma métrica). Validado por render (R100 ida/volta e
R10E, 5 câmeras).

```
# custo de enquadramento de um PONTO (torso do personagem) na câmera c:
frame_cost(c, P):
    projeta P com a câmera c (from→to, fov vertical, aspecto 4:3)
    se P está ATRÁS da câmera        -> +INFINITO
    se |ndc_y| > YMAX (fora do frustum vertical) -> +INFINITO
    retorna |ndc_x|          # 0 = centralizado na tela, 1 = na borda
    # nota: como cada câmera OLHA para seu 'to', |ndc_x| = desvio angular
    # horizontal do personagem -> a de menor custo é a que melhor o enquadra
    # (validado: as 2105 câmeras projetam seu próprio 'to' em ndc_x ≈ 0).

neighbors(c):  # grafo NÃO-direcionado do RVD (from≠to), pré-computado por sala
    { d : existe entrada RVD from=c,to=d ou from=d,to=c }

select(P, atual):                 # atual = -1 no init
    # 1) HISTERESE: mantém a câmera atual enquanto ela ainda enquadra bem
    se atual >= 0 e frame_cost(atual, P) <= KEEP:   return atual
    # 2) troca para a melhor VIZINHA que enquadre; senão, melhor GLOBAL
    cands = neighbors(atual) ∪ {atual}
    melhor = argmin_{c in cands, frame_cost(c,P) <= COVER} frame_cost(c, P)
    se melhor existe:            return melhor
    return argmin_{todas c} frame_cost(c, P)        # fallback (init / sem grafo)

# params (remake): KEEP=0.9, COVER=1.1, YMAX=1.6, fov=55°.
# só se troca quando o personagem SAI do enquadramento da câmera atual, e a nova
# já o enquadra bem -> nunca aparece "na beira". Histerese = KEEP<borda + cooldown.
```

Implementação: [`docs/godot_gameplay.md`](../godot_gameplay.md) e
`godot/scripts/room_game.gd` (seção "SELECAO DE CAMERA").

### 3.6 Colisão (SCA) — **decodificado**  ✅

Apontada por `offset_table[6]`. Cabeçalho de 16 bytes + `count-1` retângulos de 16 bytes:

```
+0x00  u32  count          // nº de registros, INCLUINDO o cabeçalho (registro 0)
+0x04  s16  center_x, center_z   // ponto de referência (≈ centro da sala), repetido
+0x0C  s16  0, 0
por retângulo (16 bytes):
+0x00  s16  x0, z0         // 1º canto (plano do chão, unidades PS1)
+0x04  s16  x1, z1         // canto oposto  → AABB = [min,max] dos dois cantos
+0x08  s16  y              // altura do chão do collider
+0x0A  s16  h              // altura/topo (≈ pé-direito; colisão de altura cheia)
+0x0C  s16  t0, t1         // tipo/normal (parede vs. móvel)
```

**Validado por render na R100** (`count=15` → 14 retângulos): os **4 primeiros** são as
**paredes** (moldura da sala), os **10 seguintes** são os **móveis** (pilhas de caixa,
armário, prateleiras). Cada retângulo projeta exatamente sobre o objeto no background.
Parser: [`tools/rdt_collision.py`](../../tools/rdt_collision.py) → `{sala}_col.json`.

### 3.7 Máscaras de profundidade (priority sprites) — **layout fechado** 🟡 (80%)

Cada câmera aponta uma lista de máscara em `mask_data_ptr` (§3.3). É o sistema de
"priority sprites" do PS1 (o cenário à frente do personagem é redesenhado por cima).
Layout verificado nos bytes reais (169 salas, **111.644 blocos**; `tools/rdt_collision.py`
`decode_masks`):

```
cabeçalho @mask_data_ptr:  u16 n_groups, u16 n_masks
grupo 0:                   u16 count, u16 depth0
depois: n_masks blocos (LISTA PLANA), 8 OU 12 bytes:
  bloco 8 B  (quando byte +2 != 0):
    +0 u16 pri        // Z de ordenação POR-SPRITE (0..~45240) — é o "depth comparável"
    +2 u8  w          // largura em px (múltiplo de 8)
    +3 u8  (0 usual; às vezes altura em px)
    +4 u8  sx, +5 u8 sy   // ORIGEM no atlas de máscara (VRAM PS1), em px
    +6 u8  dx, +7 u8 dy   // canto na TELA, em PIXELS (múltiplos de 8)
  bloco 12 B (quando byte +2 == 0):  sprite com tamanho explícito
    +0 u16 pri, +2 0, +3 0, +4 u8 w2, +6 u8 h2, +8 u8 sx,sy, +10 u8 dx,dy
```

**Correções (round oclusão):**
- **O bloco de 12 B é MAIORIA** (83.579/111.644 ≈ **75 %**), não exceção.
- **`dx,dy` e `sx,sy` são PIXELS** (0..255, múltiplos de 8) — **não** "grade de 8 px".
- **`depth0` do grupo 0 = 30720 (0x7800) CONSTANTE** em todas as 1507 câmeras → não é Z
  por-sala (provável Z-base/near do OT do PS1). O **Z real de ordenação é o `pri`** de cada
  bloco (não o `depth0`).
- A subdivisão além do grupo 0 **não é inline** `(count,depth)` — ler como **lista plana**.

Falta só **decodificar o atlas de origem** `(sx,sy)`: ele fica na **máscara TIM dentro do
`.BSS`** da sala (reevengi `bsssld2tim -re3` descomprime). Com o atlas + `(sx,sy,w,h)→(dx,dy)`
por bloco e `pri` como Z, a oclusão fica pixel-exata. Por ora o remake usa **profundidade**
(caixas 3D sobre a colisão) — equivalente e robusta. Ver `../decomp/notes/sala_logica.md §3`.

---

## 4. Invariantes confirmadas (169/169 salas)

- `file_size` do cabeçalho == tamanho do arquivo.
- `block_count` == 10; vetor de tipos == `(5,5,5,5,6,6,6,6,0,2)`.
- Blocos alinhados a `0x800`; último termina no tamanho do arquivo; padding = `0x00`.
- RDT no índice 8; `offset_table[7]` == `0x60` (início das câmeras).
- `offset_table[16]` aponta para um script SCD válido (tabela de ponteiros coerente).
- Total: 2105 câmeras, todas com coordenadas plausíveis.

## 5. O que falta

1. **Bytecode SCD** — posicionamento (portas/gatilhos/itens/entidades) **já extraído**
   (ver [scd_gameplay.md](scd_gameplay.md)). Pendem: **sala-destino da porta** e o
   **opcode de spawn de inimigo** (`sce_em_set`) — precisam do handler no exe
   ([exe.md](exe.md); Fase B1 do [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md)).
2. ✅ ~~Papéis dos offsets~~ **RESOLVIDO** (reevengi + validação): 0/1/2=áudio VAB,
   6=colisão, 7=câmeras, 8=RVD, 9=iluminação (LIT), 16=SCD, 22=anim (RBJ). Restam só
   10..15 (modelos/textura/mensagens) por-índice.
3. **Máscara de profundidade — atlas TIM**: o layout do bloco está fechado (§3.7); falta só
   **decodificar o atlas TIM no `.BSS`** (`bsssld2tim -re3`) para casar `(sx,sy)`→tela e ter
   oclusão pixel-exata.
4. **Blocos de gráficos (tipos 5/6/2) → PNG**: descomprimir/decodificar os sprites e
   máscaras de VRAM.

---

## Achado do PORT (2026-07-31) — a semântica POR RETÂNGULO da colisão não está fechada

> Registrado ao implementar a transição de sala do port (itens P3-01/P3-03). O **formato**
> (contêiner, contagem, retângulos) está certo — o que não está resolvido é **qual retângulo
> bloqueia o personagem**.

### O que motivou a investigação

Auditando as **453 portas**: 453/453 salas de destino carregam e 453/453 câmeras de chegada são
válidas, mas se todo retângulo do bloco de colisão for tratado como obstáculo, **só 216 das 453
posições de chegada ficam livres**. Com raio 0 (sem inflar pela casca do personagem) sobem para
apenas 51% — ou seja, **não é folga de soleira**.

### Medições

1. **O espaço de coordenadas está certo:** **449 de 451** chegadas caem dentro do envelope
   (AABB) da sala de **destino**. Só 2 fogem (`R510→R504` com chegada (0,0) e `R706→R316`).
   Logo o problema não é ler o campo errado nem a sala errada.
2. **Onde caem as chegadas encravadas:** 188 dentro de retângulo marcado como *móvel*
   (`wall=false`) e 35 dentro de *parede*.
3. **`y` e `h` não discriminam:** na **R100** — a sala cuja colisão foi validada por render no
   protótipo — **todos os 14 retângulos** têm `y ≈ -447` e `h` entre 3891 e 4044. Se `y` fosse o
   chão do collider e `h` a altura do móvel, a pilha de caixas e o fichário não teriam a mesma
   altura da parede.
4. **`type[1]` parece nível, não normal:** os valores observados são **todos múltiplos de 300**
   (`-300, -600, -900, -1800, -3600, -3900, -5400, -7200, -28800`), com `-28800` dominando as
   paredes. Isso tem cara de altura/nível, não de vetor normal.
5. **Altura como filtro não fecha:** ignorar retângulos com `h` abaixo de um limiar sobe as
   chegadas livres de 51% para no máximo **80%** (limiar 4000) — sem um ponto de corte natural.
6. **Bits 0 e 1 de `type[0]`** aparecem enriquecidos nos retângulos que contêm chegada
   (36% vs 13% e 25% vs 5%), mas **não são exclusivos** — não servem como bit de "piso".

### Consequência

A leitura atual (`+0x0c s16 t0,t1 // tipo/normal (parede vs. móvel)`) é **parcial**. Há pelo
menos uma classe de retângulo que **não bloqueia** (piso, zona, degrau ou limite de setor) e o
discriminador ainda não foi identificado. Enquanto isso:

- o port trata todo retângulo como obstáculo (conservador) e **desencrava** a chegada
  procurando o ponto livre mais próximo — decisão **declarada** do port, não comportamento
  provado do motor (`port/room/world.gd`, `aplicar_chegada`);
- a colisão continua correta onde foi validada por render (R100: ela para na face do fichário);
- o item **P3-10** do tracker cobra fechar isso, porque afeta fidelidade de colisão (P1-06) e
  spawn de chegada (P3-03).

O caminho mais promissor é desassemblar o consumidor da colisão no EXE (o mesmo método que
fechou o RVD e o door_handler) em vez de continuar inferindo por estatística.

### Evidência adicional sobre `type[1]` (mesma investigação)

- Os valores de `type[1]` são **todos múltiplos de 300** e as **4 paredes da R100 têm todas
  `-28800`** — um valor que se repete em 1097 retângulos no jogo e parece **sentinela de
  parede**, não um nível.
- Nos retângulos que contêm chegada de porta, `type[1]` **coincide exatamente** com o `y` da
  chegada em vários casos (`-7200`, `-3600`), o que sugere **nível/andar**.
- Mas a correlação **não se sustenta no geral**: só **134 das 453** chegadas (30%) têm `to_y`
  igual a algum nível `type[1]` existente na sala de destino.
- Filtrar por "mesmo nível" (`|to_y - type[1]| <= 300`) sobe as chegadas livres de 51% para
  **77%** — melhor, mas longe de fechar, e **contradiz o controle da R100**: o móvel validado
  por render (o fichário, `rect6`, face em `x = -21065`) tem `type[1] = -1800`, enquanto o piso
  medido no render é `y ≈ -258`. Ou o Y de colisão do personagem não é o do pé, ou `type[1]`
  não é nível.
- Curiosidade coerente com a primeira hipótese: a documentação já registrava que o `entry.y`
  das portas da R100 fica **~-1800/-2550** — o mesmo valor do `type[1]` dos móveis daquela sala.

**Conclusão metodológica:** as pistas apontam para "nível/andar + sentinela de parede", mas
nenhuma combinação testada fecha os dois controles ao mesmo tempo (chegadas livres **e** o
fichário da R100 bloqueando). Parar de inferir por estatística e ir ao **consumidor da colisão
no EXE** — foi o que resolveu o RVD (`0x8002a84c`) e o door_handler (`0x800248e4`).

### RESOLVIDO EM PARTE (2026-07-31) — o campo `+8` NÃO é `y`: é tipo + ESTADO mutável

> Achado por disassembly do EXE, seguindo o método que fechou o RVD e o door_handler. Corrige
> a leitura publicada do registro de colisão.

**Como foi achado.** O consumidor foi localizado varrendo o stream de instruções por
`lw rt, 0xC86C(rs)` (load absoluto de `0x800cc86c` = base do RDT — `find_hi_lo_refs` não acha
porque não é par `lui/addiu`). Dos 21 loads da base do RDT, **4** leem `+0x20`
(= `offset_table[6]`, a colisão): `0x800228e0`, `0x8003428c`, `0x8004d6bc`, `0x800556e8`.

**O handler `0x800556e0` é o opcode de script `0x6e`** (confirmado na jump-table
`0x8009e0f8`). Ele faz:

```
lw   $a2, 0x1c($a0)      ; PC do script (é um handler de opcode)
lw   $v1, -0x3794($v1)   ; base do RDT
lbu  $v0, 1($a2)         ; operando byte 1 = ÍNDICE do retângulo
lw   $a1, 0x20($v1)      ; bloco de colisão
addiu $v0, $v0, 1        ; +1  -> o registro 0 é o CABEÇALHO
sll  $v0, $v0, 4         ; ×16 -> registros de 16 bytes
addu $a1, $a1, $v0
lhu  $v1, 8($a1)         ; campo em +8 do retângulo
lhu  $v0, 2($a2)         ; operando hword em +2
andi $v1, $v1, 0x3f      ; PRESERVA os 6 bits baixos
andi $v0, $v0, 0xffc0    ; PEGA os 10 bits altos do operando
or   $v1, $v1, $v0
sh   $v1, 8($a1)         ; grava de volta
```

Ou seja, o campo em **`+8`** — que `tools/rdt_collision.py` documenta como
`s16 y // altura do chão do collider` — é na verdade um **bitfield**:

| bits | papel |
|---|---|
| **0..5** (6 bits) | **tipo/classe** do collider — preservado pelo opcode |
| **6..15** (10 bits) | **ESTADO**, que o script GRAVA em runtime (opcode `0x6e`) |

Isso explica de uma vez três coisas que não fechavam:

1. **Por que na R100 todos os 14 retângulos têm "y ≈ -447":** `-447 = 0xFE41` → tipo `1`,
   estado `0x3F9`. Não é altura; é o par (tipo 1, estado padrão) repetido.
2. **Por que nenhuma regra estática decide caminhabilidade:** a colisão **tem estado de
   runtime**. O script liga e desliga colliders (portão que abre, caixa que se empurra,
   grade que cai). Uma sala "fotografada" no bytecode não diz o que está ativo no momento em
   que o jogador chega.
3. **Por que 49% das chegadas de porta parecem bloqueadas:** muitos colliders provavelmente
   estão **desativados** naquele momento do jogo.

**Distribuição medida:** 22 valores distintos de tipo (6 bits), dominados por `1` (3147
retângulos), depois `0` (632), `2` (484), `3` (373), `6` (126), `54` (125), `38` (110),
`22` (102). O estado é dominado por `1017` (0x3F9) em 3956 retângulos.

**O que ainda falta (P3-10):** a semântica de cada valor de tipo (provável formato de forma
do SCA: retângulo, triângulo, rampa, escada…) e de cada bit de estado. O caminho é o mesmo:
desassemblar `0x8004d6b8` (helper de quadrante/AABB sobre o cabeçalho da colisão, chamado de
7 lugares, incluindo `0x8004db64`/`0x8004e8ec` do código de movimento) e os outros dois
consumidores (`0x800228e0`, `0x8003428c`).

**Consequência para o `tools/rdt_collision.py`:** renomear o campo `y` para `tipo_estado` (ou
emitir `tipo` e `estado` separados) e **não** usá-lo como altura. O campo `h` em `+0x0a` segue
sem confirmação independente.

### Laço de colisão do EXE — `0x8004e830` (achado do port, 2026-07-31)

Não é teste de PONTO: é **teste de trajeto**. `$s5`/`$s6` são os pontos de ORIGEM e DESTINO do
movimento (x em `+0`, z em `+8`), e o laço percorre os registros de 16 B filtrando antes de
testar:

| ordem | teste | efeito |
|---|---|---|
| 1 | `+8 & máscara_do_chamador` (`a2`) | não casa → **pula** o retângulo |
| 2 | `+8 & 0x0f` = **tipo/forma**; `== 0x0b` | → **pula** |
| 3 | `+0x0a & quadrante` (helper `0x8004d6b8`) | fora → **pula** |
| 4 | `+0x0a & 0x1000` | escolhe a **forma**: com o bit = teste diagonal/rotacionado (`0x8004e970`, aritmética `(dx−dz)`), sem o bit = eixo-alinhado (`0x8004ea7c`) |

O helper de quadrante roda **duas vezes** (origem e destino) e, se os quadrantes diferem,
devolve `0xff` (considera todos). O cabeçalho do bloco tem **dois centros**, que podem ser
DIFERENTES (R101: `(-19000,-23530)` e `(-10500,-15030)`) — a doc dizia "repetido", o que só
vale para salas como a R100.

Máscaras vistas nos 13 chamadores: `a2 = 0x40` com `a3 = 1` (movimento do player,
`0x8003f970`/`0x800448d8`) e `a2 = 0x2000` com `a3 = 5` (`0x80021fd8`). `a3` vira `$s7` e é
testado bit a bit (`andi 4`, `andi 2`) — flags de intenção do chamador.

**Medido:** implementar os filtros 1–3 sobre teste de PONTO sobe as chegadas livres de 51% para
apenas 54%. Ou seja, o que falta não é o filtro: é o **teste de trajeto com as duas formas**.
Escolher a máscara que maximiza a métrica (`0x08` daria 447/453, `0x80` daria 452/453) seria
ajustar ao resultado, não reproduzir o motor — por isso **não** foi feito.

### §3.6 — Colisão FECHADA: o collider é uma LISTA DE SEGMENTOS (2026-08-01)

Este é o achado que corrige de uma vez a colisão, a Jill flutuando e as "chegadas encravadas".
Tudo o que a doc dizia antes partia de uma premissa errada: **o registro de 16 B não é uma
caixa sólida**. Cada registro descreve uma FORMA feita de segmentos de reta, e o teste do motor
é "o segmento de MOVIMENTO cruza algum segmento da forma?".

**Medida que prova a premissa errada:** tratando os registros como caixas cheias, a R101 fica
com **0% da área caminhável** (os 75 registros cobrem a sala inteira) e só **51%** das 453
chegadas de porta ficam fora de colisão. Com o modelo de segmentos: **450/450 chegadas
conseguem dar o primeiro passo (100%)**.

#### Cabeçalho (16 B)

| off | tipo | papel |
|---|---|---|
| `+0x00` | s16 | `count` (inclui o cabeçalho como registro 0) |
| `+0x04` | s16×2 | **centro 1** (broadphase de quadrante) |
| `+0x08` | s16×2 | **centro 2** — pode ser DIFERENTE do 1 (R101: `(-19000,-23530)` e `(-10500,-15030)`) |

#### Registro (16 B)

| off | tipo | papel |
|---|---|---|
| `+0x00` | s16×2 | `f0,f1` — par de coordenadas 1 (**ordem crua**; normalizar min/max destrói o dado) |
| `+0x04` | s16×2 | `f2,f3` — par de coordenadas 2 |
| `+0x08` | u16 | bits 0‑3 **FORMA** · bits 4‑5 **canto** (forma 6) · bits 6‑15 **ESTADO** (script, opcode `0x6e`) |
| `+0x0A` | u16 | bits 0‑7 **quadrante** · bits 8‑11 **arestas** (formas 9/10) · bit 12 **rotação 45°** |
| `+0x0C` | s8 | **base** do collider: `Y_base = -1800 × valor` |
| `+0x0D` | s8 | nível/andar (informativo; `15` nas 4 paredes da sala) |
| `+0x0E` | s16 | **topo** do collider em Y |

#### Laço `0x8004e830` — ordem exata

1. `bits & a2` == 0 → **pula**. `a2 = 0x40` no movimento do player (`0x8003f970`, `0x800448d8`);
   `0x2000` em `0x80021fd8`. Como `0x40` está na faixa de ESTADO, é o script que liga/desliga
   collider (portão que abre, grade que cai).
2. `bits & 0x0f == 0x0b` → **pula**.
3. `mask & quadrante` == 0 → **pula**. O quadrante (`0x8004d6b8`) é
   `1 << (sinal_x + 2·sinal_z)` para o centro 1 (bits 0‑3) e o mesmo `<< 4` para o centro 2.
   Origem e destino são calculados; **quadrantes diferentes → código `0xff`** (considera todos).
4. `mask & 0x1000` → transforma o TRAJETO para o referencial girado 45° em torno de `(f0,f1)`:
   `x' = (dx-dz)·181/256`, `z' = (dx+dz)·181/256` (181/256 = 1/√2). 437 dos 5289 registros.
5. AABB do segmento de movimento contra a envolvente (broadphase do próprio EXE).
6. ALTURA (só quando `a3 & 1`, que é o caso do player): pula se `topo > maxY` ou
   `Y_base < minY`. Ou seja, o collider vale onde **`topo ≤ y ≤ Y_base`**.
7. FORMA (narrowphase): tabela de 16 ponteiros em **`0x8009e088`**.

#### As 16 formas (tabela `0x8009e088`)

| forma | função | n | segmentos |
|---|---|---|---|
| 0 | `0x8004f098` | 632 | **círculo** inscrito: raio `(f2-f0)/2`, centro no meio. Bloqueia se o trajeto cruza o **diâmetro perpendicular ao movimento** ou se o **destino** está dentro (usa `sqrt` em `0x80087ff4`). |
| 1, 7 | `0x8004f3c8` | 3163 | as **duas diagonais**: `(f0,f3)-(f2,f1)` e `(f0,f1)-(f2,f3)`. Consequência real: **raspar um canto não colide** — aproximação do próprio jogo. |
| 2 | `0x8004f498` | 484 | linha média em Z + 2 diagonais deslocadas de `(f3-f1)/2` em X |
| 3 | `0x8004f5b4` | 373 | linha média em X + 2 diagonais deslocadas de `(f2-f0)/2` em Z |
| 4 | `0x8004f6cc` | 17 | cruz "+" das duas linhas médias |
| 5 | `0x8004f034` | 3 | uma diagonal `(f0,f1)-(f2,f3)` |
| 6 | `0x8004f7a8` | 463 | **"L" de 2 arestas**; o canto vem de `bits & 0x30` — e é por isso que os tipos observados são exatamente **6, 22, 38 e 54**. A 3ª diagonal devolve `2`, e o chamador do player **descarta o 2** (`0x8004ec58`). |
| 9, 10 | `0x8004f258` | 121 | retângulo com as **4 arestas mascaráveis**: `0x100`=x0, `0x200`=z1, `0x400`=x1, `0x800`=z0 |
| 8, 11, 12 | `0x8004f02c` | 33 | `jr $ra; move $v0,$zero` — **nunca colide** |
| 13, 14, 15 | `0x80050d00`, `0x80050d28`, `0x8005111c` | 0 | não aparecem no dado das 169 salas |

#### Interseção: `0x8004ef74` (GTE)

`mtc2` carrega SXY0/SXY1/SXY2 e a **GTE op `0x06` = NCLIP** devolve em MAC0 o produto vetorial.
São 4 NCLIP: A e B contra a reta CD, e C e D contra a reta AB — o teste de "straddle" clássico.
O sinal é comparado com `xor` + `bgez`, o que trata **zero como mesmo lado**: colinear ou
tocando a ponta **não** conta como cruzar.

#### Duas correções colaterais que caem daqui

1. **O `y` de chegada da porta é o PISO.** Os `to_y` das 453 portas são exatamente os níveis
   (`0`, `-1800`, `-3600`, … múltiplos de 1800; 293 chegadas em `0`). A nota antiga — "esse `y`
   é outra referência, não a posição do pé" — estava errada pelo mesmo motivo. O `-258` que o
   protótipo usava como piso **levantava a Jill 258 un do chão** (o "flutuando" relatado).
2. **Não existe raio de personagem no teste.** O motor não infla nada: quem escolhe o ponto de
   origem/destino é o chamador. O `collider_radius = 380` herdado do protótipo era invenção.

**O que continua aberto:** a semântica dos bits 6‑15 de `+0x08` (só o `0x40` está provado, por
ser o que o movimento do player consulta) e a resposta de colisão do motor
(`0x8004fe70` / `0x8005003c`, o "empurra para fora" — o port desliza por eixo, que é
aproximação declarada).

### §3.7 — O MOVIMENTO não usa o laço de segmentos: resolver `0x8004af04` (2026-08-01)

Correção importante sobre a §3.6: o laço `0x8004e830` é um **PREDICADO** (linha de visão,
"dá para ir de A a B" — 13 chamadores, todos booleanos). O que move o personagem é o
**resolver `0x8004af04`**, que percorre TODOS os registros e **corrige a posição** (não há
break — um tick pode deslizar em vários colliders):

| passo | teste | endereço |
|---|---|---|
| 1 | `+0x0A & mask == mask` (quadrante da posição candidata) | `0x8004b020` |
| 2 | `+0x08 & flags_chamador` (player = `0x40`) | `0x8004b038` |
| 3 | **faixa de NÍVEL**: `+0x0C ≤ nivel_ator ≤ +0x0D` | `0x8004b054/68` |
| 4 | broadphase: ponto candidato dentro da caixa CHEIA **inflada pelo raio** (Minkowski, unsigned) | `0x8004b120/30` |
| 5 | resposta por forma (tabela `0x8009dfec`) — grava a posição corrigida no ator | `0x8004b154` |

- **Existe raio, sim** — só não em `0x8004e830`. Vem de `ator+0x1A/+0x1C`; o ator do player
  inicializa com **450/450** (`0x80033538`).
- **`+0x0C/+0x0D` são FAIXA DE NÍVEL** no resolver (paredes: 0..15 = sempre; móveis do térreo:
  0..0) — e `-1800×(+0x0C)`/`+0x0E` são base/topo em Y no predicado. Os dois usos coexistem
  no EXE.
- Resposta das formas 1/5/7/8 (`0x8004c960`): **clamp por eixo na face inflada, escolhido pelo
  lado de ONDE SE VINHA** (a posição do tick anterior). O deslize nasce daí: andando em
  diagonal contra parede alinhada em X, só o X é corrigido. Correção > 2×raio → flag `0x100`
  e o chamador **restaura a posição** (parada seca).
- Caso "já estava dentro" (`0x8004c85c`): escapa pela face CONTRA o movimento (ou a mais
  próxima, se parado), com teto de 400 (`0x8004cc68`); acima disso rejeita sem mover.
- `0x8004fe70`/`0x8005003c` **não são resposta**: são a confirmação VERTICAL do predicado
  (retângulo nos planos X-Y e Z-Y; não escrevem nada fora da pilha). E as formas ≥9 nunca
  bloqueiam o predicado do player (os bits `0x20` de `0x8004f928`/`0x8004fbd4` são inversos):
  são rampas — o Y é tratado por `0x8004d720` (floor height) e `0x8004ce2c`.

**Opcode SCD `0x6e`** (handler `0x800556e0`, 4 B: `[6e][idx u8][valor u16]`): grava os 10 bits
altos de `+0x08` do registro `idx` (preserva forma+canto). 348 chamadas em 69 salas (221
desligam, 127 ligam). `idx` mapeia 1:1 em `rects[idx]` do `_col.json`. Bounds-check: R50E
func 30 escreve `idx=13` numa sala de 13 registros (overrun real do jogo).

Implementação no port: `port/room/collision.gd` (`resolver()` + `Resolvido`), consumo em
`actors/player.gd::_mover`, opcode em `script_vm/vm.gd` (0x6E), reset por visita em
`Collision.reset_estado()` (o PS1 relê o RDT do CD a cada porta). Aproximações declaradas:
resposta radial para a forma 0 (a real é `0x8004c408`, não desassemblada) e "menor fuga" no
caso-dentro (bloco `0x8004ccb0` lido em estrutura).

#### §3.7.1 — Correções do veredito adversarial (2026-08-02)

O revisor da §3.7 confirmou a tese central instrução por instrução, mas refutou detalhes que
estavam ERRADOS na primeira implementação do port — e um deles quebrou o jogo inteiro:

1. **A máscara do resolver é `0x4000`, aplicada a `+0x08`** (`0x8004b034/38`; chamador
   `0x8003543c` passa `a2 = 0x4000`). O argumento comparado com `+0x0A` é o CÓDIGO DE
   QUADRANTE (retorno de `0x8004d6b8`, exigidos os dois bits). O port usava 0x40 (que é a
   máscara do PREDICADO `0x8004e830`).
2. **Só a função 0 do SCD roda na carga da sala.** A f0 é o init e faz `gosub` condicionado a
   flags para as funções de setup (f2..f9). Executar TODAS as funções — o que o port fazia —
   era inócuo enquanto o `0x6e` era NOP; com o `0x6e` implementado, cada sala carregava com os
   colliders no estado da última função de EVENTO executada (287 das 348 chamadas 0x6e estão
   em funções de evento) → portões fantasma e paredes invisíveis em 69 salas.
3. A escolha da face na resposta (`0x8004cb1c`) usa o sinal do MOVIMENTO; na aproximação de
   canto isso rejeitava o passo (congelamento nas quinas). O port escolhe pelo LADO DE ONDE SE
   VINHA (sinal de `u`/`v` da posição anterior) — equivalente na travessia, correto no canto.
4. Forma 5 não usa a resposta de caixa: desvia antes do AABB para `0x8004b874`
   (distância a segmento, raio dobrado — só 3 registros no jogo; aproximação declarada).
5. No `cruza()` (`0x8004ef74`), `MAC0 == 0` agrupa com o lado POSITIVO (`bgez`) — a regra não
   é simétrica ("tocar a ponta não cruza" vale só de um lado).
6. A flag `0x100` é consumida em `0x800339f8` (restauração em `0x80033a04..1c`), não em
   `0x80035480`.

### §3.8 — Piso, rampas e o segredo do "grupo" do RVD (2026-08-02)

**O Y do personagem não é integrado: é rederivado do piso todo frame.** O laço `0x80033b88`
consulta `floor_height` (`0x8004d720`) e grava em `entity+0x38`, junto com `entity+0x122`
(piso) e **`entity+0x09` (nível = −Y/1800)**. Andar só muda X/Z.

`floor_height` (variante do personagem, tabela `0x8009e054`): parte do **piso padrão da sala**
(cabeçalho SCA `+0x0E`; 0 em 154/169) e fica com o **menor Y** entre os registros com bit de
piso (`+0x08 & 0x8000`), base no pé ou abaixo, contendo o ponto:
- forma 1 = patamar plano no `topo` (excluídos os com arestas, `+0x0A & 0x0F00`);
- formas 9/10 = **rampa linear** de `−1800×base` a `topo+1800`, sentido em `bits & 0x30`,
  clampada nas pontas (`0x8004e10c`);
- forma 12 = cone radial (centro `topo`, borda `−1800×base`);
- demais formas devolvem o padrão (stubs).
A seção SCA tem ainda um **grid de broadphase 16×16** após os registros (u16[256] + listas u8
terminadas em 0xFF; célula = `((x+32768)>>12) + ((z+32768)>>12)*16`), validado em 169/169.

**E o achado que destrava a câmera:** `gs+0x2495` — o "seletor de grupo" do consumidor RVD —
é `0x800CCBCD` = **`player+0x09` = o NÍVEL do piso**. O byte `+0xb` do descriptor de porta é
só o valor inicial (o nível da chegada). Ou seja: **o grupo das zonas RVD é o ANDAR** — na
R101 os grupos {1,2,3,4} são exatamente os níveis de piso {(-1800),(-3600),(-5400),(-7200)},
e descer a escada muda o nível → muda o grupo → as zonas do andar de baixo passam a valer.
Medido no port: descendo a rampa da R101, a câmera troca 4→3 na zona `4→3` (grupo 3) assim
que o nível vira 3.

**Interação (porta/item):** o ponto do pé não alcança muitas caixas de AOT (com o raio 450,
294/453 portas ficam fora do alcance do ponto). O código de interação do player
(`0x80045fc0..0x80046040`) sonda ADIANTE com distâncias 200/400/600 — o port testa o AOT no
pé e nas três sondas à frente.

#### §3.8.1 — EM ABERTO: o que exatamente vai em `player+0x09`? (2026-08-02, em investigação)

Sintomas em jogo depois do "grupo = nível" (relato do usuário, com prints):
- **R200** (rua, tudo Y=0): a câmera fica presa na 11 andando pela rua — se o grupo fosse só
  `-Y/1800`, numa sala plana ele é 0 para sempre, e as zonas com grupo 1..N nunca valem;
- **R201** (garagem, chegada Y=-16200 → `-Y/1800` = 9): W não anda em certos pontos — o
  filtro de nível do resolver (`+0x0C ≤ nivel ≤ +0x0D`) com nivel 9 pode estar
  ligando/desligando os registros errados.

Hipóteses concorrentes para a escrita de `entity+0x09` (o passe de piso, `0x8004b7e8`):
- **H1** `nivel = -Y/1800` (a leitura da frente de pesquisa; funciona na R101 porque os
  andares coincidem com os grupos);
- **H2** `nivel = campo +0x0D do REGISTRO DE PISO pisado` — um ÍNDICE de área/zona de
  autoria, não uma função do Y. Unificaria: na R101 os +0x0D das plataformas coincidem com
  os andares; na R200 os pisos planos podem ter +0x0D = 0,1,2 marcando ÁREAS da rua (grupos
  das zonas RVD); e explicaria os "73 registros onde nivel != f(topo)" e por que o resolver
  compara `nivel_ator` com a FAIXA `+0x0C..+0x0D` dos registros.

Decisão pendente do desassembly de `0x8004b7e8`/`0x8004d720` (quem produz o valor gravado) e
da medição R200/R201. Até lá o port usa H1 — que resolve escada mas quebra os dois sintomas
acima.

#### §3.8.1 — RESOLVIDO (2026-08-04): H1 provada, e as duas regressões fechadas

- **`entity+0x09 = -trunc(y_piso/1800)`** — divisão por constante mágica `0x91A2B3C5` sobre o
  **retorno de `floor_height`** (o Y do piso resolvido, não o Y da entidade). H2 refutada por
  off-by-one em todos os casos medidos (o `+0x0D` do piso plano é `nível_da_superfície − 1`).
- **`+0x0C..+0x0D` é a FAIXA DE NÍVEIS em que o registro é colisor ativo** — plataforma com
  superfície no nível L tem `+0x0D = L−1` (colide com quem está ABAIXO; quem está em cima
  anda por ela). Isso explica os "73 registros onde nivel != f(topo)".
- **R200**: zero registros de piso e 30/30 zonas RVD com grupo `0x80` — a câmera presa não
  era grupo: era o consumidor. A mecânica que faltava: **entrar numa câmera tira de jogo a
  primeira zona da corrida dela** — no fade (`0x8005182c` commit + `0x80051864` DESTRÓI o
  quad da zona ancorada, reescrevendo-o para −32700..−32600) e na carga de sala
  (`0x80049728` commit com a câmera de chegada). Regra declarada do port: corrida de UMA
  zona não perde nada (senão as câmeras 8..11 da R200 ficam sem saída) e zonas `from==to`
  nunca commitam — a semântica exata desse canto fica para o emulador (P1-14).
- **Resposta por forma no resolver** (a regressão "colisão geral"): formas 6/2/3/4 respondem
  SÓ nas arestas (mureta/L), não como caixa cheia — 17 chegadas de porta nasciam presas
  dentro de envolventes forma 6. Medido após o ajuste: **403 portas atravessadas de ponta a
  ponta, 0 chegadas presas reais, cross-stage 17/17**.

#### §3.8.2 — Ângulo de chegada: o dado JÁ está na convenção do port (2026-08-05)

Registro de uma medição ERRADA e da certa, para não se repetir:

- **Proxy enviesado (descartado):** "a personagem chega de costas para a parede mais próxima".
  Deu 44% de acerto com offset −1024 contra 24% com 0 — e é viés puro: a chegada nasce no VÃO
  da porta, então o segmento de colisão mais próximo é o BATENTE lateral, o que produz ±90° de
  graça.
- **Critério de jogo (o que vale):** as 450 chegadas com o resolver real, "apertar W entra na
  sala". Offset **0**: 440/450 andam ≥300 un (avanço médio 931 un). −1024: 334. +1024: 309.
  2048: 419. Conclusão: **`to_facing` não se converte**.
- Os "90° à esquerda" vistos em jogo eram do **MESH** (`Coords.MESH_YAW_OFFSET_DEG`, −90 →
  −180), não do ângulo lógico — a locomoção já seguia o `facing` correto.

**Porta de escada (`sce == 13`, 6 no jogo)** dispara por CONTATO, sem botão — é a escada do
saguão (R114 → R118) e afins; as 447 `sce == 1` seguem exigindo ação.

**Alcance da interação:** contato do corpo (caixa do AOT inflada pelo raio 450) **ou** sonda
direcional à frente (200/400/600, as constantes de `0x80045fc0..0x80046040`). Medido: as caixas
de porta ficam a 454–551 un do ponto onde a colisão para o personagem, ou seja, logo além do
contato — só o contato não bastava, e só a sonda abria de longe.
