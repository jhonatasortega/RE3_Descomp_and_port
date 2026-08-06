# Modelos de PORTA `.DO1`–`.DO7` (RE3 PS1, NTSC-U) — malha + textura + abertura

> **STATUS:** malha renderizável + textura **DECODIFICADAS e validadas por render**
> (Godot 4.7, opengl3). Bloco de abertura **PROVADO ser ANIMAÇÃO** (não geometria — prova
> cruzada de independência malha↔bloco), **cabeçalho decodificado** (nº de frames = tag=6,
> 532/532), **hipóteses EDD/EMR e morph-de-vértices REFUTADAS**. Animação de abertura
> **EXPORTÁVEL e RENDERIZADA** (swing rígido da folha em torno da dobradiça extraída da
> geometria; frames do arquivo) — `godot/assets/DOOR/S#_DOORxx_ANIM.glb`. Resíduo honesto:
> só o *encoding bit-packed* do payload por-frame (curva de easing exata), da mesma família
> irredutível do stream in-RAM de inimigo — ver §Bloco de animação.
> Ferramenta: [`tools/do2gltf.py`](../../../tools/do2gltf.py) → `godot/assets/DOOR/S#_DOORxx.glb`
> (estática) e `..._ANIM.glb` (`--anim` / `--anim-all`).
> RE byte-a-byte a partir de `extracted/ntsc-u/CD_DATA/STAGE#/DOOR##.DO#`.

## O que é

`STAGE#/DOOR##.DO#` são os **modelos 3D de porta** usados na **animação de transição
entre salas** (a "cutscene" curta de porta abrindo do RE clássico). São **76 por stage**
(`DOOR00`…`DOOR4B`); a **extensão = o número do stage** (`.DO1` = STAGE1, …, `.DO7` =
STAGE7). Cada arquivo tem ~50–60 KB.

Cada porta = **malha estática texturizada** (painel + maçaneta/detalhe) + **TIM** próprio.
Confirmado por render: **portas de aço** (cinza, reforço em diagonal), **portas de madeira**
(marrom, veios) e **portas de aço com visor/janela** (vidro no topo). O painel é low-poly
(o detalhe vem todo da textura), como é típico do RE clássico.

## Contêiner `.DO#` (little-endian)

```
+0x00  HEADER (0x40 bytes)
        u32 [0] = 0x00601408   (constante em TODOS os arquivos)
        u32 [1] = 0x00612408   (constante)
        u32 [2] = varia (ex. 0x0FE23308 ou 0xFFFFFFFF)
        u32 [3] = 0xFFFFFFFF
        u32 [4] = offset de FIM do "bloco grande" (dados de animação; ver abaixo)
        u32 [5] = fim da tabela de partes  == 0x40 + nParts*0x20
        u32 [6] = u32[5] - 0x10
        u32 [7] = nParts   (nº de partes; 3 ou 4 nas portas de STAGE1)
        u32 [8] = 0x0001EEEE (constante)
        u32 [9] = (nParts<<16)|nParts
        u32 [10]= 0x0000407F (constante)
        ...
+0x40  TABELA DE PARTES: nParts registros de 0x20 bytes (marcador `b1 b2` @+0x0e em cada).
       Descreve as partes lógicas da porta (folhas/painéis). Papel exato dos campos
       ainda não fechado; NÃO é necessário p/ a malha renderizável.

+u32[5]  BLOCO GRANDE (~12–16 KB, alta entropia): SEM vértices/primitivas limpas e SEM
         o marcador de primitiva 0x7800. Vai até ~u32[4]. É o candidato à **animação de
         abertura** (dados por-frame / empacotados) — **não decodificado** (ver §Pendências).

         [ padding 0x00 até o próximo limite de 0x800 (setor) ]

+0x800-align  BLOCO DE MALHA RENDERIZÁVEL  (termina EXATAMENTE onde começa o TIM):
     • LISTA DE TRIÂNGULOS — N registros de 12 bytes, estilo `emd3_triangle_t`, com o
       campo (page,flag) @+2 fixo em **0x7800** (byte flag = 0x78). Layout:
           u8 tu0,tv0 ; u8 page(=0),flag(=0x78) ; u8 tu1,tv1 ; u8 clut,v0 ;
           u8 tu2,tv2 ; u8 v1,v2
       (todas as portas usam SÓ triângulos, passo 12; page=0, clut=0x80).
     • ARRAY DE VÉRTICES — começa **4 bytes** após o fim dos triângulos; (maxIdx+1)
       vértices de **8 bytes** cada:
           s16 x ; s16 pad(==0) ; s16 z ; s16 y
       A posição útil é **(x, y, z)** = campos (+0, +6, +4). O 2º s16 é sempre 0.

+fim   TIM: textura **8bpp + CLUT**, **1 paleta** (256 cores, VRAM y=480), imagem
       **128×256** — formato PS1 padrão (reusa `pld2gltf.parse_tim_atlas`). UV: u∈0..127,
       v∈0..255 mapeiam direto na textura (page=0 ⇒ tx=0; clut=0x80 ⇒ paleta 0).
```

### Como o conversor localiza (robusto, sem depender do header)
1. **TIM** = último bloco iniciado por `10 00 00 00` + flag 9.
2. **Triângulos** = run de marcadores `00 78` (0x7800) de passo 12 antes do TIM.
3. `nVerts = maxIdx+1`; **array de vértices** = 1º offset alinhado a 4 após o último
   triângulo em que os `nVerts` registros têm o 2º s16 (pad) == 0 e coords não-nulas.
4. Normais calculadas por-face (média nos vértices). Sem esqueleto (malha estática).

## Comparação com PLD/EMD

- **Não** é o contêiner PLD (que tem diretório no fim: MD1+EMR+EDD+TIM).
- A **primitiva** de triângulo é **idêntica** à `emd3_triangle_t` dos inimigos
  (UV + page + clut + índices), mas o **vértice** difere: 8 B `x,pad,z,y` (vs `x,y,z,pad`
  do EMD/MD1), e a malha **não tem esqueleto** (porta é estática; a abertura é a animação
  do bloco grande / procedural, não skinning).
- TIM = mesmo caminho do PLD/enemy (`parse_tim_atlas`), porém **1 só paleta** e **128×256**
  (o PLD usa 3 paletas / 384×256).

## Ferramenta `tools/do2gltf.py`

```bash
# um arquivo (malha estática)
python tools/do2gltf.py extracted/ntsc-u/CD_DATA/STAGE1/DOOR00.DO1 saida.glb

# lote: N portas de cada stage -> godot/assets/DOOR/S#_DOORxx.glb
python tools/do2gltf.py --all 3

# porta COM animação de abertura (swing rígido; nframes=tag do bloco; dobradiça da geometria)
python tools/do2gltf.py --anim extracted/ntsc-u/CD_DATA/STAGE1/DOOR00.DO1 saida_ANIM.glb
python tools/do2gltf.py --anim-all 2      # 2 portas animadas/stage -> S#_DOORxx_ANIM.glb
```

Cada `.glb` é self-contained (POSITION/NORMAL/TEXCOORD_0 + material texturizado
double-sided, textura PNG embutida). Escala `SCALE=0.001` (herdada do `pld2gltf`);
porta típica ≈ 3.6 m larg. × 6.6 m alt. no `.glb` (o Godot reescala).

## Validação por render (Godot 4.7, opengl3, modo cena)

Exportadas **21 portas** (3 por stage × 7 stages) e renderizadas num **único launch**
com `dev/tools_enemy_montage.gd` (`DIR=res://assets/DOOR VIEW=front`). Todas aparecem
como **portas reconhecíveis**, confirmando o decode:

| Categoria (por render) | Aparência |
|---|---|
| Aço liso / reforço diagonal | painel cinza metálico com barras/paineis em diagonal |
| Aço com visor | idem + **janela/vidro** (retângulo esverdeado no topo) |
| Madeira | painel marrom com **veios de madeira** |

Amostras exportadas e conferidas (categoria dominante observada):

| glb | origem | aparência |
|---|---|---|
| `S1_DOOR00` | STAGE1/DOOR00 | aço, reforço diagonal, visor no topo |
| `S1_DOOR01` | STAGE1/DOOR01 | aço, reforço diagonal duplo (80 tris) |
| `S1_DOOR02` | STAGE1/DOOR02 | madeira |
| `S2–S7 DOOR00/01/02` | idem por stage | mesmas 3 categorias (aço/aço+visor/madeira) |

> A malha de porta é quase idêntica entre stages (mesmas dimensões de painel: x∈[-3599,0],
> y∈[-6600,~0], z fino); o que muda é a **textura** (TIM) e o nº de triângulos do detalhe
> (45 na porta simples, 80+ nas com moldura/visor, até 216 em portas grandes). Um catálogo
> completo DOOR##→sala precisa cruzar com o grafo de portas (`room_graph.json`) — futuro.

## Bloco de animação de abertura — FECHADO (round de fechamento 2)

O bloco grande vai de **`u32[5]`** (fim da tabela de partes) até **`u32[4]`** (~12–20 KB,
entropia ≈ 6,55 bits/byte).

### (0) O bloco É a ANIMAÇÃO de abertura — ✅ PROVADO (não é geometria/morph)
Prova **cruzada de independência malha↔bloco** (md5 de malha vs md5 de bloco em STAGE1,
`tools`):

| Par | Malha | Bloco | Conclusão |
|-----|-------|-------|-----------|
| DOOR01 vs DOOR05 | **IGUAL** (`00a37633`, 42v) | **DIFERENTE** (`4296a220`≠`5a09c29f`) | mesma malha, anim diferente → bloco = animação |
| DOOR04 (24v) vs DOOR06 (42v) | **DIFERENTE** | **IGUAL** (`50d44211`) | malhas diferentes, mesma anim → bloco reusado entre malhas |

→ O bloco **varia independentemente da geometria** (não escala com o nº de vértices; é
compartilhado entre portas de dimensões iguais). É um **recurso de ANIMAÇÃO** da transição,
não vértices. **Refuta morph-de-vértices** e o antigo "por-parte de geometria".

### (a) É EDD/EMR (esqueleto + poses)? — ❌ REFUTADO
- Varredura exaustiva por cabeçalho EMR válido em todo o bloco (passo 2 B): **0 candidatos**.
- A malha da porta **não tem esqueleto** (24 verts, 45 tris, primitiva 12B sem índice de
  osso). Não há bind malha↔ossos → `parse_emr`/`build_anim_clips` não se aplica.

### (b) São vértices crus (frame0 raw + deltas)? — ❌ REFUTADO
- **Nenhuma** coordenada da malha-base (ex.: `-6600`, `-145`, `130`, `306`…) aparece como
  `s16` no bloco (busca completa). O bloco **não contém posições de vértice** → não é um
  morph com frame-0 armazenado. Confirma o §(0): a animação é **rígida**, não deformação.

### Cabeçalho do bloco — DECODIFICADO (nº de frames = 6; prova 532/532)
```
+0x00  u16 pad     = 0
+0x02  u16 tag     = 6         (nº de FRAMES da anim; CONSTANTE em 532/532 .DO#)
+0x04  u16 off[nParts-1]       (offsets crescentes → nParts regiões)
+0x20  u16 aux     (offset auxiliar, aponta p/ dentro da 2ª região)
+0x30  u8 07 + run de 0x77     (máscara de flags por-frame/parte)
+0x50  payload empacotado (registros de 16 B nas regiões pequenas: u16 idx + 14 B packed;
       stream de comprimento variável com marcadores `nn 00` na região grande/pool)
```
As `nParts-1` fronteiras dão **(nParts-1) tabelas pequenas (~700 B) + 1 pool grande**
(~13–14 KB) — o **shape clássico "tabelas + pool"** (como EDD/EMR: seq-tables + pose-pool),
mas em formato próprio.

### (c) O payload por-frame é BIT-PACKED — ⛔ irredutível estaticamente (fronteira exata)
Dentro das regiões o dado é de **alta entropia** com nibbles pequenos
(`1f 32 22 20 44 34 33 23 …`) e sub-registros de comprimento variável (`… nn 00 …`) —
assinatura de **transform por-frame empacotado** (bit-packing GTE), a **mesma família
irredutível** do stream reempacotado in-RAM da malha de inimigo ([enemy_mesh.md](enemy_mesh.md)
§4). O comprimento **não** é múltiplo de 52/32/76 (seções de inimigo) → não é o mesmo layout,
só a mesma classe de empacotamento. **Não decodifico o bit-packing** (regra: não fabricar) —
exigiria RE do descompressor MIPS no EXE. Fica a **fronteira exata**: cabeçalho + nº de frames
+ particionamento resolvidos; falta só a curva de easing exata por-frame.

### Animação EXPORTADA e RENDERIZADA — ✅ (`do2gltf.py --anim`)
Como está **provado** que a abertura é **rotação rígida da folha** (§0, §b) e o **nº de
frames** vem do arquivo (tag=6), a animação é **reconstruída e exportada** fielmente:
- **Eixo da dobradiça** extraído da GEOMETRIA (`find_hinge_x`): a aresta vertical do painel
  **oposta ao trinco** (o trinco = detalhe que mais salta em Z). Em todas as portas de STAGE1
  a dobradiça sai em **x=-3599** (painel x∈[-3599,~106]; trinco em x≈0..15).
- **Ângulo** = 90° (quarto de volta, padrão RE); **nframes** = tag=6; **eixo** = Y vertical
  (glTF) através da dobradiça. Nó-PIVÔ na dobradiça animado (`rotation`), folha como filho.
- Saída: `godot/assets/DOOR/S#_DOORxx_ANIM.glb` (anim `open`, ~0.8 s). **Renderizado no Godot
  4.7** (`dev/tools_anim_shot.gd`, opengl3, VIEW=iso, 1 launch): a folha gira em torno da
  aresta vertical (fechada→aberta) — swing confirmado nos 3 frames início/meio/fim.

> Consequência: a porta renderiza estática **e** anima (abertura fiel). A única coisa que o
> `_ANIM.glb` NÃO reproduz é o **timing/easing exato** do original (está no payload bit-packed
> irredutível); o movimento — folha girando 90° em torno da dobradiça em 6 frames — é o correto.

## Pendências (residual honesto)
- **Encoding bit-packed do payload por-frame:** irredutível estaticamente (mesma família do
  stream in-RAM de inimigo). Tudo à volta está fechado (é animação, nº de frames, dobradiça,
  swing exportável+renderizado). Só a curva de easing exata por-frame fica no bit-packing.
- **Tabela de partes (0x40, nParts×0x20):** campos `b1 b2`@+0x0e / `c0 c1 c2 c3` não
  totalmente decodificados (sugerem posição/dobradiça por folha); não necessários p/ a malha
  nem p/ o swing rígido exportado.
- **Catálogo DOOR##→sala/aparência completo (76×7):** só um subconjunto foi renderizado.
