# Sistema de EFEITOS (ESP) do RE3 e o "brilho" do item no chão

Alvo: **SLUS_009.23** (PS1 NTSC-U), base `0x80010000`. Tudo abaixo foi lido do binário
ou dos dados do CD; onde não consegui provar está escrito **NÃO SEI / NÃO MEDIDO**.

Ferramenta nova: **`tools/esp_decode.py`** (`scan`, `scan --room STAGE1/R101`,
`scan --all-rooms`, `dump <outdir>`). Saída já gerada em `port/assets/ESP/`
(664 PNG + `esp_core00.json` + 2 folhas de contato de prova).

---

## 0. TL;DR para quem vai implementar

O "brilho" que o jogador vê **não é uma luz**. É uma **faísca em estrela de 4 pontas,
16×16 px de textura, 8 quadros a 1 tick (30 Hz) cada = 0.267 s, aditiva**, que reaparece
em intervalo **aleatório de 40 a 89 ticks (1.33 s a 2.97 s)** na posição do item
**+90 unidades para cima**. Existem **4 paletas** (âmbar, branca, azul, vermelha),
escolhidas por 2 bits do byte `obj+0xc3`.

Cadeia: `esp_spawn(0x0705, ...)` cria um **efeito controlador INVISÍVEL** (handler `0x32`)
que fica parado junto do item; a cada N ticks ele chama `esp_spawn(0x0905, ...)` que cria a
**faísca visível** (handler `0x00` = no-op, só anima e morre).

Sprites prontos: `port/assets/ESP/t05_A{14..21}_B{10..13}_v{0..3}_16x16.png`
(sequência do efeito 9: A14→A21, ver §6). Folha de contato de prova:
`port/assets/ESP/_prova_t05_cintilar_item_4paletas.png`.

**Lacuna crítica (leia §9):** não achei, em nenhum dado do CD, quem liga o bit 7 de
`obj+0xc3`. Logo **não posso provar que essa rotina roda no jogo retail**, nem dizer
quais itens usam qual cor.

---

## 1. Onde vive o sistema

| coisa | endereço | prova |
|---|---|---|
| Array de efeitos vivos | `0x800ba8a8` .. `0x800bf754+0xd3`, **stride `0xd4` (212 B), 96 slots (`0x60`)** | `esp_init_core 0x8001b08c`: `v0=0x800ba8a8`; `+0x4f80`; laço `-0xd4` × `0x60` zerando `+0x24`. `esp_alloc 0x8001c254` varre de `0x800bf754` para baixo até `> 0x800ba7d4`. Laços em `0x8001bab4` e `0x80056448` usam `sltiu v0,t0,0x60` |
| Limites do array (globais) | `[0x80098084] = 0x800ba8a8` (início), `[0x80098088] = 0x800bf828` (fim exclusivo) | lidos em `0x8001bb2c/0x8001bb30`, valores literais no EXE |
| Tabela de bancos ESP (32 registros de 12 B) | `0x800ba728` .. `0x800ba8a8` | `esp_init_core` limpa `a0=0x800ba8a8`, `a1=a0-0x180` (`0x180/0xc = 32`); `esp_spawn 0x8001b4b0` varre `0x800ba728` até `+0x180` |
| — sub-tabela **CORE** (16 reg.) | `0x800ba728` | `esp_register` com `a2==0` → `t0 = 0x800ba728` (`0x8001b224`) |
| — sub-tabela **SALA** (16 reg.) | `0x800ba7e8` | `esp_register` com `a2!=0` → `t0 = 0x800ba7e8` (`0x8001b21c`); `esp_init_room 0x8001b148` limpa de `a0-0xc0` a `a0` |
| Tabela de 64 handlers de comportamento | `0x80097bd4`, 64 entradas (`0x00..0x3f`) | `esp_update_all 0x8001bb64`: `s2 = 0x80097bd4`; `fn = u32[s2 + slot[0]*4]`. Índice 64 já é lixo (`0x03e818c1`) |
| Heap de primitivas GPU (double-buffer) | `0x800bf830` (buf 0) e `0x800c3430` (buf 1), **15360 B = 384 × POLY_FT4(40 B)** cada; ponteiro corrente em `0x800c7030` | `esp_prim_reset 0x80023240`: `buf = 0x800bf830 + dbuf*15360`; teto no draw em `0x80022b8c` |
| Objetos de sala | `0x800cea60`, **stride `0x194` (404 B), 32 slots** | `0x80052194`: `s1 = 0x800ca738 + 0x4328`; laço `sw zero,(s1); sb zero,0xc3(s1); s1 += 0x194` × `0x20` |

### Registro da tabela de bancos (12 bytes)
```
+0x00 u32 data_ptr    ponteiro absoluto para o banco dentro do arquivo carregado
+0x04 u32 tbl_ptr     ponteiro absoluto para a tabela de EFEITOS do banco
+0x08 u8  type        byte de "tipo" do banco (chave de busca); 0xff = livre
+0x09..0x0b padding
```
Prova: `esp_register 0x8001b24c..0x8001b284` escreve `u32[t0]=v1` (+0),
`u8[t0+8]=tipo` (`sb v0,4(a2)` com `a2=t0+4`) e `u32[t0+4]=tbl` (`sw v1,(a2)`);
`t0 += 0xc` por iteração. `esp_spawn 0x8001b508` lê `s2 = u32[rec+4]`, `s0 = u32[rec+0]`.

---

## 2. `esp_spawn` — `0x8001b484`

Assinatura real (o32 MIPS; args 5+ na pilha do chamador em `sp+0x10`, `sp+0x14`, ...):

```c
// retorna ponteiro para o slot, ou -1
ESP* esp_spawn(u32 id,          // a0
               u32 param,       // a1
               MATRIX *mtx,     // a2  (32 B: 3x3 s16 + 3 s32) — do dono do efeito
               SVECTOR *ofs,    // a3  (3 s16) ou NULL — deslocamento local
               SVECTOR *rot);   // [sp+0x10] ou NULL — rotação inicial
```

Passo a passo (endereços):

| endereço | o que faz |
|---|---|
| `0x8001b4b4`/`0x8001b4d0` | `key = id & 0xff`; varre os 32 registros procurando `rec.type == key`. Se nada casar usa o **último** registro (`0x8001b504`: `v1 -= 0xc`) |
| `0x8001b510` | `slot = esp_alloc()` (`0x8001c254`). Passe 1: primeiro slot com `u16[+0x24] == 0`. Passe 2: primeiro com `u16[+0x24] & 8`. Senão `-1`. Depois `bzero(slot, 0xd4)` via `0x80010150` |
| `0x8001b528` | `slot+0x28 = id` (u32) |
| `0x8001b530` | `slot+0x2c = param` (u32) → **`u16 slot+0x2c` = low, `u16 slot+0x2e` = high** |
| `0x8001b534` | se `ofs`: `slot+0x38/0x3c/0x40 = (s32)ofs->x/y/z` |
| `0x8001b564` | `memcpy(slot+0x70, mtx, 0x20)` — cópia da matriz do dono |
| `0x8001b560` | `slot+0xc0 = mtx` (guarda o ponteiro, para "seguir" o dono) |
| `0x8001b568` | `slot+0xbc = [0x800cc878]` (contexto/câmera — **NÃO IDENTIFICADO**) |
| `0x8001b56c` | **`slot+0xb3 = (id >> 24) & 0xf`** = índice de VARIANTE |
| `0x8001b588` | **`slot+0x44 = u32[bank+4] + variante*0x40`** → `{u16 clut, u16 tpage}` |
| `0x8001b580` | `slot+0xc4 = bank+8` = base da **tabela A** |
| `0x8001b5a4` | `slot+0xc8 = bank+8 + A*8` = base da **tabela B** |
| `0x8001b5a8` | se `rot`: `slot+0x68 = u32[rot]`, `slot+0x6c = s16[rot+4]` |
| `0x8001b5c0` | `e = (id >> 8) & 0xff`; `rec = tbl + u16[tbl + e*2]*4` |
| `0x8001b5d8` | `n_slots = u32[rec]`; `n_frames = u32[rec+4]`; `memcpy(slot+0x00, rec+8, 0x24)` |
| `0x8001b5f0` | `slot+0xcc = ponteiro do frame corrente` (**escrito e nunca lido** — varredura de todo o EXE por `lw/sw off=0xcc`: só `0x8001b5f0` e `0x8001b818` tocam esse campo) |
| `0x8001b600` | `slot+0x24 = u16[slot+0x04]` (flags do frame viram flags do slot) |
| `0x8001b60c` | `slot+0x46 \|= u16[slot+0x16]` → **OR no tpage** (é aqui que entra o modo de blend) |
| `0x8001b608` | `slot+0x6f = u8[slot+0x0f]` = entrada corrente da tabela A |
| `0x8001b630` | `slot+0x2b = u8[A[slot+0x6f] + 2]` = contador de duração do quadro |
| `0x8001b65c` | se `flags & 4`: calcula RGB a partir da iluminação (`0x80078f38` / `0x80078ba4`), com **clamp em `[0x60,0xa0]`** e `0x90` em overflow (`0x8001b6a8`); resultado em `slot+0xb0/0xb1/0xb2` |
| `0x8001b784` | senão: `slot+0xb0 = slot+0xb1 = slot+0xb2 = 0x80` (cinza neutro = "sem modulação") |
| `0x8001b7b4` | se `flags & 0x10`: `esp_slot_post(0x8001bfcc)` |
| `0x8001b7c8` | se `n_slots > 1`: aloca mais slots; `memcpy(novo+0x24, primeiro+0x24, 0xb0)`, avança `rec` por `n_frames*0x24` e lê o `n_frames` do slot seguinte. `novo+0xd0 = primeiro` (link para o pai) |

Variante "filho" — **`esp_spawn_child` `0x8001b35c`**:
`(a0 = slot_pai, a1 = id, a2 = param, a3 = mtx, [sp+0x10] = &ofs (3 × s32, lidos por
`lhu` com passo 4!), [sp+0x14] = &rot)`. Monta o `SVECTOR` local em `sp+0x18` e chama
`esp_spawn` em `0x8001b400`.

### Layout do slot ESP (212 B) — campos provados
```
+0x00 u8  handler       indice em 0x80097bd4        (copiado do frame record)
+0x01 u8  state         estado do handler
+0x02..0x03             (frame record)
+0x04 u16 flags0        copia crua do frame record; vira +0x24
+0x08 u16 scale_x       Q12 (0x1000 = 1.0)
+0x0a u16 scale_y       Q12
+0x0c..0x0e s8          aceleracao angular x,y,z    (usada por 0x8001bc80)
+0x0f u8  a_start       entrada inicial da tabela A
+0x10/0x12/0x14 u16     velocidade x,y,z
+0x16 u16 tpage_or      OR aplicado em +0x46
+0x24 u16 flags         bit15 = VIVO, bit13 = DESENHAR, bit12 = SEMI-TRANSPARENTE,
                        bit11 = seguir a matriz do dono, bit10, bit9 = quad orientado
                        pela matriz, bit7, bit4, bit1 = integrar fisica, bit0 = animar
+0x26 u16 events        bits de evento por frame (limpo o byte baixo a cada tick)
+0x28 u32 id
+0x2b u8  frame_timer   ticks restantes do quadro corrente
+0x2c u16 param_lo
+0x2e u16 param_hi      = ESCALA base do sprite (ver §5)
+0x30/0x32/0x34 s16     deslocamento acumulado pela integracao
+0x38/0x3c/0x40 s32     deslocamento local (o `ofs` do spawn)
+0x44 u16 clut          valor de CLUT do GPU
+0x46 u16 tpage         valor de tpage do GPU
+0x48/0x4c/0x50 s32     posicao de mundo (calculada)
+0x58/0x5c/0x60 s32     posicao anterior
+0x68 u32 / +0x6c u16   rotacao inicial (SVECTOR)
+0x6f u8  a_cur         entrada CORRENTE da tabela A
+0x70..0x8f MATRIX      matriz local (copia da do dono)
+0xb0/0xb1/0xb2 u8      R,G,B do POLY_FT4
+0xb3 u8  variante      (id>>24)&0xf
+0xb4 u16               timer do handler
+0xb6 s16               periodo do handler
+0xbc u32               contexto (de [0x800cc878])
+0xc0 MATRIX*           matriz do dono
+0xc4 void*             tabela A do banco
+0xc8 void*             tabela B do banco
+0xcc void*             frame record corrente (morto)
+0xd0 ESP*              slot pai (multi-slot)
```

---

## 3. Como o `id` é quebrado — e o que `(flags & 0x60) << 19` faz

```
id  = 0xVV_00_EE_TT
      TT = id & 0x0000ff  -> TIPO do banco   (chave de busca em rec.type)
      EE = id & 0x00ff00  -> INDICE do efeito (indexa a tabela u16 de efeitos)
      VV = id & 0x0f000000 -> VARIANTE (0..15), usada como (id>>24)&0xf
```
Provas: `0x8001b4b4` (`andi a0,s3,0xff`), `0x8001b4a4` (`srl fp,s3,8` → `andi 0xff`),
`0x8001b4dc` (`srl s6,s3,0x18` → `andi 0xf`).

O item usa `id = 0x0705 | ((flags & 0x60) << 19)` (`0x800525f4..0x800525fc`):
- `flags & 0x20` → `0x20 << 19 = 0x0100_0000` → bit 24
- `flags & 0x40` → `0x40 << 19 = 0x0200_0000` → bit 25

logo **`variante = (obj_flags >> 5) & 3`**, valores 0..3.

### O que a variante muda: **a PALETA (CLUT), nada mais**

`0x8001b588`: `slot+0x44 = u32[bank+4] + variante*0x40`.
`u32[bank+4]` é `{u16 clut, u16 tpage}`; o campo CLUT do GPU do PS1 é
`clut = (y << 6) | (x >> 4)`, então **`+0x40` = `+1` na linha Y da CLUT**.
Tamanho, animação, tempo e blend são idênticos entre as 4 variantes.

O banco tipo `0x05` tem `clut = 0x7a11` → VRAM **(272, 488)**.
Confirmado contra `ETC/CORE00.TIM`, cujo bloco de CLUT é **(272, 480) 16×30** (4bpp,
`pmode = 0`) e o bloco de pixels **(896, 256) 128 words × 248** (= 512×248 px 4bpp).

As 4 paletas reais (16 cores, índice 0 = transparente; bit 15 = STP ligado nas outras):

| variante | CLUT | linha VRAM | rampa (RGB888) |
|---|---|---|---|
| 0 (`flags&0x60 == 0x00`) | `0x7a11` | y=488 | `080000 180000 290000 310800 521000 5a1000 731800 942000 ac2900 c52908 de5208 de6a00 de9c39 eebd39 eede52` → **âmbar/laranja** |
| 1 (`0x20`) | `0x7a51` | y=489 | `ffffff eeeeee e6e6e6 c5c5c5 acacac 949494 7b7b83 6a6a73 525262 4a4a52 39394a 292939 202029 101018 080810` → **branca/prata** |
| 2 (`0x40`) | `0x7a91` | y=490 | `ffffff dedeff c5c5ff a4a4ff 8383ff 6262ff 5252de 4141bd 3131a4 202083 10106a 080852 080839 000020 000010` → **azul** |
| 3 (`0x60`) | `0x7ad1` | y=491 | `ffffff f6dede eeb4b4 de8383 cd6a6a bd5252 ac3939 9c2020 831818 731818 5a0808 410000 200000 180000 100000` → **vermelha** |

Reproduzir: `python tools/esp_decode.py dump port/assets/ESP` →
`esp_core00.json` campo `cluts_por_linha_vram["488".."492"]`, e os PNG `..._v0..v3_...`.

> **ATENÇÃO — a FAÍSCA do item usa `variante + 1`.** O handler `0x32` monta o id do filho
> com `addiu a1,a1,1` em `0x80021804` (verificado na palavra crua: `0x24a50001`), logo as
> linhas de CLUT efetivas da faísca são **489..492**, não 488..491:
>
> | `obj+0xc3 & 0x60` | variante do pai | variante da faísca | CLUT | cor da faísca |
> |---|---|---|---|---|
> | `0x00` | 0 | 1 | y=489 (`0x7a51`) | **branca/prata** |
> | `0x20` | 1 | 2 | y=490 (`0x7a91`) | **azul** |
> | `0x40` | 2 | 3 | y=491 (`0x7ad1`) | **vermelha** |
> | `0x60` | 3 | 4 | y=492 (`0x7b11`) | **vermelho escuro** (`8b0000 7b0000 6a0000 5a0000 520000 4a0000 410000 390000 310000 290000 200000 180000 100000 080000 000000`) |
>
> A tabela 488..491 acima vale para os efeitos que usam a variante do próprio `id`
> (as CHAMAS do banco `0x05`: efeitos `0x00`,`0x02`,`0x03`,`0x04`,`0x05`,`0x0b`).

---

## 4. Formato do arquivo `ETC/CORE00.ESP` — **DECODIFICADO 100%**

Arquivo de **10336 B (`0x2860`)**, `file_index = 0x14` na tabela global do CD.
Carregado por `esp_init_core 0x8001b08c` em **`0x801fc200`**
(`cd_read_file(0x14, 0x801fc200, 0, "CORE00.ESP")`; o nome de debug está literal em
`0x800103dc` = `"CORE00.ESP"`).

```
+0x0000 : lista de TIPOS, 1 byte por banco, terminada em 0xff (máx. 16)
          CORE00: 00 05 01 02 03 04 ff ff ...   -> 6 bancos
fim-4, fim-8, ... : tabela de OFFSETS u32, LIDA DE TRÁS PARA FRENTE
          offset[i] = offset do banco i, relativo ao início do arquivo
          (0x8001b24c: `lw v1,(a1)` ; `addiu a1,a1,-4`)
          O chamador passa `a1 = base + ((size/4)*4) - 4` (0x8001b104..0x8001b12c)
```
CORE00: `offset = [0x0010, 0x0734, 0x0b34, 0x0e88, 0x139c, 0x25d0]`
(bytes em `+0x285c, +0x2858, +0x2854, +0x2850, +0x284c, +0x2848`; `+0x2844` = `0xffffffff`).

### Banco
```
+0x00 u16 A       nº de entradas da tabela A (quadros)
+0x02 u16 B       nº de entradas da tabela B (retângulos)
+0x04 u16 clut    valor de CLUT do GPU
+0x06 u16 tpage   valor de tpage do GPU
+0x08           tabela A: A × 8 bytes
+0x08+A*8       tabela B: B × 4 bytes
+0x08+A*8+B*4   tabela de EFEITOS
```
Fórmula de fechamento provada em `esp_register 0x8001b268..0x8001b280`:
`tbl = bank + (A*2 + B + 2)*4`, que é exatamente `bank + 8 + A*8 + B*4`.
`tools/esp_decode.py` faz `assert` disso e passa nos 6 bancos do CORE00 e nos 156
bancos de sala.

Cabeçalhos medidos:

| banco | tipo | offset | A | B | clut | tpage | VRAM tex | VRAM clut |
|---|---|---|---|---|---|---|---|---|
| 0 | `0x00` | `0x0010` | 36 | 32 | `0x7811` | `0x001e` | (896,256) 4bpp | (272,480) |
| 1 | `0x05` | `0x0734` | 29 | 19 | `0x7a11` | `0x001e` | (896,256) 4bpp | (272,488) |
| 2 | `0x01` | `0x0b34` | 25 | 24 | `0x7c11` | `0x001e` | (896,256) 4bpp | (272,496) |
| 3 | `0x02` | `0x0e88` | 25 | 21 | `0x7c91` | `0x001e` | (896,256) 4bpp | (272,498) |
| 4 | `0x03` | `0x139c` | 73 | 16 | `0x7e11` | `0x001f` | (960,256) 4bpp | (272,504) |
| 5 | `0x04` | `0x25d0` |  1 |  1 | `0x7f51` | `0x001f` | (960,256) 4bpp | (272,509) |

### Tabela A (8 bytes) — quadro de animação
```
+0x00 u8 b_index    entrada da tabela B (retângulo/sprite)
+0x01 u8 n_prims    nº de POLY_FT4 emitidos (avanço do heap: n_prims*40)
+0x02 u8 ctl_dur    0x00        = MATA o efeito
                    0x01..0xfd  = duração do quadro em TICKS de 30 Hz
                    0xfe        = congela no quadro anterior e para de animar
                    0xff        = volta para a entrada `b_index` (loop)
+0x03 u8 size       lado do sprite em pixels de textura (é sempre quadrado)
+0x04 u32           0 em todos os 6 bancos do CORE00
```
Provas: `esp_anim_step 0x8001c168` (`lbu v1,2(a1)` e o `switch` 0xfe/0x00/0xff);
`esp_draw_all 0x80022a6c` (`s4 = u8[A+1]`), `0x80022ac0` (`s7 = u8[A+0]`),
`0x80022abc` (`s6 = u8[A+3]`).

### Tabela B (4 bytes) — retângulo do sprite na tpage
```
+0x00 u8 u     coluna na tpage, em pixels de 4bpp (0..255)
+0x01 u8 v     linha na tpage (0..255)
+0x02 s8 ox    pivô X (típico -size/2)
+0x03 s8 oy    pivô Y
```
Prova: `0x80023054` (`lb v0,2(t2)`) e `0x80023064` (`lb v0,3(t2)`) — **SIGNED**;
`0x800230e4/0x800230e8` (`lbu` de `+1` e `+0` para o UV do POLY_FT4).

### Tabela de efeitos
```
u16 idx[]      indexada por (id>>8)&0xff. idx[e] == 0 => efeito inexistente.
registro = tbl + idx[e]*4:
   u32 n_slots
   n_slots vezes:
      u32 n_frames
      n_frames × 36 bytes de frame record
```
Prova: `esp_spawn 0x8001b5c0..0x8001b5e8` e o laço multi-slot `0x8001b7ec` (`s2 += s4*0x24`).

**Validação forte:** o último registro do banco tipo `0x05` termina em `0x0b30`, e o
banco seguinte começa em `0x0b34` — 4 bytes de padding, zero sobreposição. Mesmo
comportamento nos 6 bancos.

### Frame record (36 = `0x24` bytes)
Copiado inteiro para `slot+0x00..0x23`. Campos provados: ver §2 (layout do slot,
offsets `0x00` a `0x16`). Os bytes `0x18..0x23` são 0 em todos os frames do CORE00.

---

## 5. Como o efeito é DESENHADO — `esp_draw_all 0x80022990`

Roda uma vez por frame (chamado de `0x800241b8`), varrendo os 96 slots **de cima para
baixo** (`s1` de `0x800bf754` decrementando `0xd4` até `0x800ba8a8`).

Pré-requisitos por slot (`0x80022a64`): **`(slot+0x24 & 0xa000) == 0xa000`** —
bit 15 (vivo) **E** bit 13 (desenhar). Depois `0x8001020c` (teste de visibilidade /
clip) e `s4 = u8[A+1] != 0`.

Duas rotas, escolhidas por **`slot+0x24 & 0x200`**:

**A) `bit9 = 1` → quad ORIENTADO PELA MATRIZ (`0x80022fa8`)**
`pos = slot+0x38..0x40 (s32) + slot+0x30..0x34 (s16)`; `RotMatrix(slot+0x68)`
(`0x800894e4`), `MulMatrix` com `slot+0x70` e com a matriz de view `0x80098990`
(`0x8002d4b0` × 2); carrega no GTE (`ctc2 $0..$7`) e faz `RTPS` + `RTPT` nos 4 cantos
do quad montado no plano XY local. **Não é billboard**: o quad gira com o objeto.

**B) `bit9 = 0` → BILLBOARD de tela (`0x80022ccc`)**
`RTPS` só do centro (`slot+0x48/0x4c/0x50`), matriz = só a de view (`0x80098990`,
recarregada em `0x80022be4`); os 4 cantos são montados em **espaço de tela** a partir
do resultado. Clip: `|sx| < 1023` e `|sy| < 1023` (`0x80022d80..0x80022da8`), rejeita se
`z >> 9 == 0` (isto é, `z < 512`), satura `z` em `0x7fff`.

### Tamanho
```
esc  = u16[slot+0x2e] * (fov >> 4)            ; 0x80022fc0..0x80022fcc / 0x80022d20
sx   = (esc * u16[slot+0x08]) >> 12           ; 0x80022fd8, 0x80022ff0
sy   = (esc * u16[slot+0x0a]) >> 12           ; 0x80022fe8, 0x80023018
w_px = (size * sx) >> 12                      ; size = u8[A+3]
h_px = (size * sy) >> 12
x0   = (B.ox * sx) >> 12   ;  y0 = (B.oy * sy) >> 12
x1   = x0 + w_px           ;  y1 = y0 + h_px
```
Na rota B há divisão de perspectiva explícita: `t0 = size * u16[slot+0x2e] * fov;
tamanho_tela = t0 / (z << 4)` (`0x80022d30..0x80022e4c`).

`fov` = `u16[room_base + cam_idx*32 + 0x62] >> 7` (`0x800229e4..0x80022a0c`), onde
`room_base = [0x800cc86c]` e `cam_idx = s16[0x800d1f7a]`. Como a tabela de câmeras do
RDT fica **exatamente em `+0x60`** (índice 7 da offset-table = `0x60` nas 169 salas,
verificado), isso é **`u16` em `camera[cam] + 0x02`**, um Q9.7. Valores reais medidos:
`0x73b7`→231, `0x912d`→290, `0x80b2`→257, `0x83b1`→263, `0x7b34`→246, `0x7636`→236,
`0x683c`→208, `0x9e58`→316. O mesmo campo é lido por outro desenhador de sprite em
`0x80046f4c` com o mesmo `>>7`. **Que esse campo seja exatamente o `h` de
`SetGeomScreen` do GTE: NÃO PROVADO.**

### Primitiva e blend
É um **`POLY_FT4`** (quad texturizado, 10 words = 40 B, tag length = 9):
```
+0x00 tag       (OT[i] & 0x00ffffff) | 0x09000000     ; 0x80022df4..0x80022e08
+0x04 rgbc      r = slot+0xb0, g = +0xb1, b = +0xb2, code = 0x2c ou 0x2e
+0x08 xy0
+0x0c u0,v0,clut   clut = u16[slot+0x44]
+0x10 xy1
+0x14 u1,v1,tpage  tpage = u16[slot+0x46];  u1 = u0 + size-1
+0x18 xy2
+0x1c u2,v2        v2 = v0 + size-1
+0x20 xy3
+0x24 u3,v3
```
Provas do UV: `0x80023100..0x80023128`. Prova do `rgbc`: `0x8002312c` (`lw v0,0xb0(t3)`
→ `sw v0,4(t1)`) e `0x8002313c` (`sb s0,7(t1)`, com `s0` = `0x2c` ou `0x2e`).

**O `code`** vem de `slot+0x24 & 0x1000` (`0x80022aa8`):
- bit12 = 0 → `code = 0x2c` = POLY_FT4 **opaco** (ABE = 0)
- bit12 = 1 → `code = 0x2e` = POLY_FT4 **semi-transparente** (ABE = 1)

**O MODO de semi-transparência (ABR)** são os bits 5-6 do `tpage`:
`tpage_final = tpage_do_banco | u16[frame+0x16]`.
- `0x00` → ABR 0 = `0.5*fundo + 0.5*frente`
- `0x20` → ABR 1 = **`fundo + frente` (ADITIVO)**
- `0x40` → ABR 2 = `fundo - frente` (subtrativo)
- `0x60` → ABR 3 = `fundo + frente/4`

Nos bancos do CORE00 o tpage base é `0x001e`/`0x001f` (ABR = 0). O `tpage_or` do frame
record é que decide. Medido: **o cintilar do item (efeito 9 do banco 5) tem
`tpage_or = 0x0020` → ADITIVO**. Efeitos `0x0f`/`0x11` do banco 0 usam `0x0060` (ABR 3).

### Ordenação
`OT_index = z >> 5` (`0x80022de0`), com `z` saturado em `0x7fff` → OT de 1024 entradas.
A primitiva é inserida no início da lista daquele bucket. Base da OT = arg em `sp+0x44`
de `0x80022ccc` (**não rastreada até a origem**).

### Tradução para Godot 4
- **1 `QuadMesh` por sprite** com `StandardMaterial3D`: `billboard_mode = BILLBOARD_ENABLED`
  quando `flags & 0x200 == 0`; `BILLBOARD_DISABLED` + orientação pela matriz do dono
  quando `flags & 0x200 != 0`.
- `blend_mode`: `BLEND_MODE_ADD` para ABR 1, `BLEND_MODE_MIX` com alpha 0.5 para ABR 0,
  `BLEND_MODE_SUB` para ABR 2. `shading_mode = SHADING_MODE_UNSHADED`,
  `cull_mode = CULL_DISABLED`, `depth_draw_mode = DEPTH_DRAW_DISABLED`,
  `transparency = TRANSPARENCY_ALPHA` (índice 0 da CLUT = transparente).
- `albedo_color` = `Color(slot.b0/128, slot.b1/128, slot.b2/128)`: o PS1 modula
  `cor_textura * rgb / 128`, e o neutro é `0x80` (não `0xff`).
- **Tamanho**: o par `(sx, sy)` acima está em pixels de tela de 320×240 na rota B. Para
  a rota A o quad é em unidades de mundo: `meia_largura = (size * sx >> 12)` na mesma
  escala do resto do mundo PS1, logo divide por `808` como o resto (`Coords`).
  **Para o cintilar do item eu NÃO MEDI a escala final** porque depende de `fov` da
  câmera da sala e de `param_hi` (§7) — a fórmula está acima, os números vêm em runtime.
- **Taxa**: `ctl_dur` é em ticks de 30 Hz. O port já tem relógio de 30 Hz — avance
  1 índice da tabela A quando o contador chegar a 0.

---

## 6. A cadeia do BRILHO DO ITEM — passo a passo

### 6.1 O gatilho (`0x80052588`, **NÃO é per-frame**)
```c
void spawn_item_glows(void) {                     // 0x80052588
  room = *(void**)0x800cc86c;
  n    = u8[room + 2];                            // nº de objetos da sala
  obj  = (char*)0x800cea60;                       // stride 0x194
  for (i = 0; i < n; i++, obj += 0x194) {
    if (!(u32[obj] & 1)) continue;                // be_flg bit 0
    f = u8[obj + 0xc3];
    if (!(f & 0x80)) continue;                    // bit 7 = "brilha"
    SVECTOR ofs = { 0, -90, 0 };                  // sp+0x18/0x1a/0x1c; Y- = PARA CIMA
    esp_spawn(0x0705 | ((f & 0x60) << 19),        // id
              0x28000000,                         // param
              obj + 0x20,                         // matriz do objeto
              &ofs,
              NULL);                              // sw zero,0x10(sp)
  }
}
```
**Correção importante ao que estava anotado antes:** essa rotina **não roda todo frame**.
Único chamador: `0x80052b00`, dentro de `0x80052a94`, que é chamado de `0x80049790` —
a sequência de **CARREGAMENTO DE SALA**, logo depois de `esp_init_room` (`0x80049714`) e
de rodar o script de init (`jal 0x80052ba4` em `0x80052af8`). Então: **um controlador
por objeto brilhante, criado uma vez na entrada da sala, e que vive até a sala trocar.**

`param = 0x28000000` → `slot+0x2c = 0x0000`, **`slot+0x2e = 0x2800` (10240)** = escala base.

### 6.2 O controlador — banco `0x05`, efeito `0x07`, handler `0x32` (`0x800217b4`)
Frame record em `CORE00.ESP+0x0a54` (36 B):
`32 00 00 00 | 00 88 00 00 | 00 00 00 00 | 00 00 00 00 | 00×20`
- `handler = 0x32`, `flags = 0x8800` → **bit15 vivo + bit11 seguir matriz**, e
  **SEM bit13** → o controlador **nunca é desenhado**. `scale = 0`, `a_start = 0`.

```c
void h32_item_glow(ESP *s) {                      // 0x800217b4
  if (s->state == 0) {                            // 0x800217e4
     esp_spawn_child(s,
        0x0905 | (((s->variante + 1) & 0xf) << 24),   // 0x80021804..0x80021818
        (s->param_hi << 16) | s->param_lo,            // = 0x28000000
        s->owner_mtx,                                 // slot+0xc0
        &s->ofs /* slot+0x38, 3 × s32 */, 0);
     r = u8[0x80098728 + rand()];                 // tabela de 256 bytes no EXE
     s->timer  = 0;                               // slot+0xb4
     s->period = (r % 50) + 40;                   // slot+0xb6  -> 40..89 ticks
     s->state  = 1;
  } else if (s->state == 1) {                     // 0x80021884
     if ((s16)s->period < (s16)++s->timer) s->state = 0;
  }
}
```
`r % 50`: magia `0x51eb851f` (`multu`, `mfhi`, `>>4` = `/50`), depois `r - 50*(r/50)`
via `((v*3)<<3 + v)<<1 = 50*v` (`0x8002185c..0x80021874`).
Tabela de bytes pseudo-aleatórios em `0x80098728`
(`15 67 2c c0 13 af 09 f9 63 bd 0c 80 17 45 5c 70 ...`).

**Período: 40 a 89 ticks a 30 Hz = 1.333 s a 2.967 s.**

> Nota: o filho recebe `variante + 1`, não `variante` — `addiu a1,a1,1` em `0x80021804`
> (palavra crua `0x24a50001`, conferida). Ver a tabela de cores da faísca em §3.

### 6.3 A faísca — banco `0x05`, efeito `0x09`, handler `0x00` (no-op `0x8001c384`)
Frame record em `CORE00.ESP+0x0aac`:
`00 00 00 00 | 03 b8 00 00 | 00 10 00 10 | 00 00 00 0e | 00 00 00 00 | 00 00 20 00 | 00×12`
- `handler = 0x00` = `jr ra` (não faz nada)
- `flags = 0xb803`: bit15 vivo, bit13 **desenhar**, bit12 **semi-transparente**,
  bit11 seguir a matriz do item, bit1 integrar física, bit0 **animar**
- `scale_x = scale_y = 0x1000` (1.0)
- `a_start = 0x0e` (14)
- **`tpage_or = 0x0020` → tpage `0x001e | 0x0020 = 0x003e` → ABR 1 = ADITIVO**
- velocidade/aceleração = 0 → não se move; só segue o item

Animação (percorrendo a tabela A do banco 5 como `esp_anim_step`):

| A | B | u,v na tpage | tamanho | dur |
|---|---|---|---|---|
| 14 | 11 | (176,128) | 16×16 | 1 tick |
| 15 | 12 | (192,128) | 16×16 | 1 |
| 16 | 11 | (176,128) | 16×16 | 1 |
| 17 | 10 | (160,128) | 16×16 | 1 |
| 18 | 11 | (176,128) | 16×16 | 1 |
| 19 | 13 | (208,128) | 16×16 | 1 |
| 20 | 11 | (176,128) | 16×16 | 1 |
| 21 | 10 | (160,128) | 16×16 | 1 |
| 22 | — | `ctl_dur = 0x00` | — | **MORRE** |

**8 quadros × 1 tick = 8/30 s = 0.267 s.** Pivô de todos: `ox = oy = -8` (centrado).
`n_prims = 1` em todos → 1 POLY_FT4.

Sprites (a estrela de 4 pontas, tamanhos 10/11/12/13 = pequena/média/grande/maior):
`port/assets/ESP/t05_A14_B11_v*_16x16.png` etc., e a folha
`port/assets/ESP/_prova_t05_cintilar_item_4paletas.png` (4 linhas = 4 paletas).

### 6.4 Onde a faísca aparece
`ofs = (0, -90, 0)` do controlador é repassado ao filho (`slot+0x38..0x40`). No PS1
`Y` negativo é **para cima**, logo a faísca nasce **90 unidades acima da origem do
objeto**. Com o divisor `808` do port (`Coords`), isso é `90/808 ≈ 0.111` unidade Godot
acima do item.

---

## 7. Bloco ESP da SALA (RDT) — resposta ao item 5

O item **NÃO** usa o ESP da sala: usa o banco tipo `0x05` do `CORE00.ESP`.
`esp_spawn` varre os 32 registros começando pelo CORE (`0x800ba728`), então o CORE
sempre ganha em caso de empate de tipo.

Mas a sala **tem** bloco ESP, e o port vai precisar dele. `esp_init_room 0x8001b148`
(chamado de `0x80049714`, no load da sala) lê do header do RDT:

| offset no header | índice na offset-table (22 ponteiros a partir de `+0x08`) | conteúdo |
|---|---|---|
| `+0x4c` | **17** | dados ESP (mesmo formato do CORE00: lista de tipos + bancos) |
| `+0x50` | **18** | ponteiro para a **ÚLTIMA palavra** da tabela de offsets (lida decrescendo) |
| `+0x54` | **19** | lista de blocos de VRAM: `u32 n; u32 off[n];` cada `off` → `{u16 x, u16 y, u16 w, u16 h, dados...}`, subido por `LoadImage` (`0x8008b2ac`) |

Prova: `0x8001b1b4` (`lw a0,0x4c(a1)`), `0x8001b1cc` (se `u32[a0] == -1` → sem ESP),
`0x8001b1d4` (`lw a1,0x50(a1)`), `0x8001b1e8` (`lw a0,0x54(v0)` → `0x8001b2a4`).
Todos os 22 ponteiros de `+0x08` a `+0x5c` são relocados somando a base do RDT no load
(`0x8004963c..0x80049660`), e o laço termina em `+0x60` — que é justamente onde começa a
tabela de câmeras (índice 7 = `0x60` em **169/169** salas).

Medido nas 169 salas: **156 têm ESP de sala**, 13 não (`off[17] == 0` ou `u32 == -1`).
Exemplo `STAGE1/R101`: `off17 = 0x96b8` (tipos `08 09 15 18`), `off18 = 0xa048`,
`off19 = 0xa3e4` (2 blocos; o primeiro é uma CLUT `16×9` em VRAM **(288,480)** — logo ao
lado das CLUTs do CORE00 em (272,480)).

Rodar: `python tools/esp_decode.py scan --room STAGE1/R101` e
`python tools/esp_decode.py scan --all-rooms`.

---

## 8. Mapa do terreno: os outros efeitos (item 6)

`esp_update_all 0x8001bb24` roda todos os frames:
```
para cada slot de 0x800bf828-0xd4 descendo até [0x80098084]:
   se (slot+0x24 & 0x8000) == 0: pula
   se slot+0xd0 (pai) != NULL e pai->flags == 0: mata o slot   (0x8001bbcc)
   se slot+0x00 != 0: handlers[slot+0x00](slot)                (0x8001bbf8)
   slot+0x26 &= 0xff00                                          (0x8001bc14)
   se (slot+0x24 & 2): integra fisica (0x8001bc80), esp_slot_init (0x8001bcfc),
                       esp_slot_post (0x8001bfcc)
   se (slot+0x24 & 1): esp_anim_step (0x8001c168)
```
`0x8001bc80` = integração: `rot(+0x30..0x34) += vel(+0x10..0x14)`;
`vel += acel(s8 +0x0c..0x0e)`.

Chamadas a `esp_spawn`/`esp_spawn_child`: **332 pontos**. Recuperei o `id` constante em
214 deles (varredura de materialização de `$a0`). Ids (24 bits, sem a variante):

| id | tipo/banco | efeito | nº de sítios | onde (região do EXE) |
|---|---|---|---|---|
| `0x000001` | `0x01` (CORE) | 0 | 23 | `0x8003d5b0..0x80043ba0` (armas/impacto) |
| `0x000801` | `0x01` | 8 | 26 | idem |
| `0x000a01` | `0x01` | 10 | 12 | idem |
| `0x000901`/`0x000b01` | `0x01` | 9/11 | 6/4 | idem |
| `0x000003` | `0x03` (CORE) | 0 | 35 | `0x8004xxxx`, `0x8005fxxx`, `0x80061xxx` |
| `0x000603`/`0x001b03` | `0x03` | 6/27 | 12/18 | idem |
| `0x000703`/`0x000503`/`0x001103`/`0x001503`/`0x002303`/`0x002503`/`0x002903` | `0x03` | vários | 1..6 | idem |
| `0x000002`..`0x000c02` | `0x02` (CORE) | 0..12 | 1..5 | `0x8001e2b0`, `0x80027780`, `0x80036xxx` |
| `0x000705` | `0x05` (CORE) | 7 | **1** (`0x80052618`) | **brilho do item** |
| `0x000805` | `0x05` | 8 | 2 | `0x800585fc`, `0x80058f44` |
| `0x00000c`/`0x00030c` | `0x0c` (SALA) | 0/3 | 1/1 | — |
| `0x00020e` | `0x0e` (SALA) | 2 | 3 | — |
| `0x00061c`/`0x00071c`/`0x00161c` | `0x1c` (SALA) | 6/7/22 | 12/2/7 | — |
| `0x000a27`/`0x000c27` | `0x27` (SALA) | 10/12 | 2/2 | — |
| `0x01022a` | `0x2a` (SALA) | 2 | 1 | — |
| `0x001900` | `0x00` (CORE) | 25 | 1 | — |

**Bancos tipo `0x00`..`0x05` = `CORE00.ESP`; tipos `>= 0x08` = ESP da sala.**
Censo dos tipos de banco de sala nas 156 salas com ESP: `0x08` (111 salas),
`0x09` (120), `0x18` (104), `0x15` (39), `0x0c` (34), `0x1a` (26), `0x0e`/`0x1c` (23),
`0x22` (22), `0x0f`/`0x1e` (20), `0x16` (19), `0x25` (16) ... até `0x44`.

**Conteúdo visual medido (só o que eu extraí e olhei):**
- banco `0x05`, B0..B9 (40×40, 10 quadros em loop, `ox=-20, oy=-28`) = **CHAMA/FOGO**
  (efeitos `0x00`,`0x02`,`0x03`,`0x04`,`0x05`,`0x0b`; handlers `0x05` e `0x1e`).
  Ver `port/assets/ESP/_prova_t05_chama_40px.png`. O `oy = -28` (≠ `-size/2 = -20`)
  põe o pivô abaixo do centro — a chama sobe da base.
- banco `0x05`, B10..B13 (16×16) = **estrela de 4 pontas / faísca** (efeitos `0x09`, `0x0a`).
- banco `0x05`, B14..B18 (16×16, efeito `0x0a`, `mtxquad=1`) — extraído, **não classifiquei**.
- bancos `0x00`..`0x04`: extraí os 664 PNG mas **NÃO classifiquei** o que é sangue,
  fumaça, água, respingo. Os PNG estão em `port/assets/ESP/t00_*` .. `t04_*`.

**A que evento cada id responde: NÃO MAPEADO.** Só sei a região do EXE de cada sítio
de chamada. Os 118 sítios com `id` em registrador (não-constante) precisam de análise
de fluxo.

---

## 9. EM ABERTO / NÃO SEI

1. **QUEM LIGA O BIT 7 DE `obj+0xc3`? NÃO ENCONTREI.** Isto derruba a afirmação
   anterior de que "28 itens do jogo têm esse bit" — eu **não consegui reproduzir esse
   número** e não a uso como verdade. O que medi:
   - Varri TODO o EXE por qualquer store que toque `obj+0xc3` (`sb off=0xc3`,
     `sh off=0xc2`, `sw off=0xc0`, e qualquer `addiu` com imediato `0xc3`). Só existem
     dois: `0x80016370` (grava `u8 payload[3]`) e `0x800521d0` (zera no load da sala).
   - `0x80016370` está no handler do **opcode SCD `0x60`** (`0x80016334`, entrada
     `0x8009e278` da jump-table `0x8009e0f8` → `(0x8009e278-0x8009e0f8)/4 = 0x60`).
   - Varri os scripts SCD das **169 salas** com `tools/scd_decode.py`
     (4238 funções, 125384 opcodes, 0 falhas de decodificação, cobertura até
     `fim_do_bloco - 1` na maioria das salas): **opcode `0x60` aparece ZERO vezes**.
     Idem para o opcode `0x44` (`calc`/`member_set`, `0x80053d34`, que escreveria
     `obj+0xc2` via o membro 27 da tabela de thunks `0x80010ab0`/`0x80010950`).
   - Conclusão honesta: **com os dados do CD NTSC-U, `obj+0xc3` fica 0 e o efeito
     `0x0705` nunca é criado.** Ou (a) o brilho é código morto no retail, ou (b) existe
     um caminho de escrita que eu não achei. **NÃO SEI qual.**
2. **Semântica de `obj+0xc3`: flags ou id de modelo/tipo?** `0x80015dec` compara
   `u8[obj+0xc3]` com `u16[[0x800ba6f8]+0x226] - 0x64`, o que sugere um **id**, não um
   campo de flags. Se for id, "bit 7" e "bits 5-6" são bits do id — e a leitura de
   "variante de cor" continua válida mecanicamente, mas o mapa item→cor muda de sentido.
   **NÃO RESOLVIDO.**
3. **Quais itens brilham e em qual cor: NÃO MEDIDO.** Depende de (1).
4. `slot+0xbc` (de `[0x800cc878]`) e `slot+0x54` (de `[slot+0xbc]+0x38`): não sei o que são.
5. Base da **ordering table** passada a `0x80022ccc` (`sp+0x44`): não rastreada.
6. Se `camera[cam]+0x02 >> 7` é exatamente o `h` de `SetGeomScreen`: **não provado**
   (só provei que é o mesmo campo usado por dois desenhadores de sprite).
7. `esp_slot_init 0x8001bcfc` e `esp_slot_post 0x8001bfcc` estão apenas parcialmente
   lidos (a parte de projeção/sombra e o teste de `flags & 0x80` contra `0x80051e48`).
8. Handlers `0x01`..`0x3f` (exceto `0x00` = no-op e `0x32` = brilho do item): **não lidos**.
   São eles que dão o movimento de sangue/fumaça/água.
9. A tabela A dos bancos tem `u32` em `+0x04` sempre 0 no CORE00 — não sei se algum ESP
   de sala usa. `tools/esp_decode.py` expõe como `tail`.
10. O número de efeitos por banco: eu **inferi** o fim do array `u16 idx[]` (paro quando
    o primeiro registro não-nulo começaria antes do cursor). Não achei contagem
    explícita no binário. Funciona nos 6 bancos do CORE00 e nos 156 de sala sem
    disparar `assert`, mas **não é prova formal**.
11. **Correção a `docs/decomp/notes/scd_opcodes.md`:** a descrição do opcode `0x60` diz
    "indexa MODEL_TBL 0x800ba728". O handler `0x80016334` indexa **`0x800ba700`**
    (`lui 0x800c; addiu -0x5900`), que é uma tabela de 10 ponteiros de entidade;
    `0x800ba728` é a **tabela de bancos ESP**. Corrigir lá (não editei arquivo de outro agente).

---

## 10. PROFUNDIDADE do efeito de sala — a ordem de desenho (2026-08-08)

O fogo do `R10D` já aparecia no jogo, mas **na frente de tudo** (relato do dono: "o fogo está
na layer errada", e depois "uma chama na parede, na altura do peito"). Os dois sintomas têm a
mesma causa: **falta de ordem de desenho**. E a ordem, no RE3, não é z-buffer:

| quem | chave de Ordering Table | prova |
|---|---|---|
| sprite de máscara do cenário (priority sprite) | `depth` CRU do RDT | `0x80048844` (`bank = depth>>10`, `entry = depth & 1023`) |
| personagem | `zona_de_prioridade(x,z) * 1024 + min(SZ>>5, 1023)` | `0x80037d50` (seção 14 do RDT) + `0x8002b86c` |
| **efeito ESP** | `OT_index = z >> 5`, `z` saturado em `0x7fff` | `0x80022de0` |

`SZ` e o `z` do ESP são a MESMA grandeza: o Z de câmera em unidades de mundo (matriz 1.12
unitária do `LookAt` em `0x80078954`). Ordem de varredura da OT (`0x80029618`): bancos `N..1`
e o banco `0` por último, cada um de `1023` para `0` → **chave MENOR = desenhado depois = NA
FRENTE**. Logo as três chaves são comparáveis com `<`.

**O que continua NÃO PROVADO:** o BANCO de OT em que `esp_draw_all` insere. A base da tabela
chega em `sp+0x44` de `0x80022ccc` e não foi rastreada até a origem (lacuna 5 da §9). O port
declara: usa a **mesma zona de prioridade do ponto do efeito** que o motor usa para o
personagem — é regra de lugar, não de entidade, e evita o viés de fixar banco `0` (que faria
toda chama vencer um personagem em zona de banco ≥ 1).

O que o port faz com isso (`port/present/esp_sala.gd`): duas camadas de desenho, escolhidas
por chama e por tick — atrás do `SubViewportContainer` do 3D quando `chave >= chave_do
personagem`, e num `CanvasLayer` próprio (acima do 3D e da oclusão) quando é menor. Nas duas,
o nó redesenha por conta própria os recortes do cenário com chave menor que a da chama (os
pixels vêm do background HD, como em `port/room/occlusion.gd`).

Medido no `R10D` com a Jill no spawn `(9404, 0, -13317)` (`port/dev/diag_esp_prof.gd`):

| câmera | chave da Jill | chamas no quadro | recortes que cobrem chama |
|---|---|---|---|
| 0 | 147 | 8 (chaves 219..358 → todas atrás) | 12 |
| 1 | 145 | 1 (chave 134 → **na frente**) | 0 |
| 10 | 145 | 8 (uma com chave 142, na frente) | 27 |
| 4, 5, 6 | 409..447 | 0..4 | 0 (essas câmeras não têm priority sprite) |

**A "chama na parede" era isto:** a instância `(10523, 0, -9979)` (a menor, `param_hi = 0x1000`
= 768 unidades de largura) projeta, na câmera 0, em `(38, 619)` — em cima do pedestal de pedra
da esquerda. O `y` dela é **`0` no dado do opcode `0x70`** (medido; as 8 chamas do `R10D` têm
`y = 0`), ou seja **não havia Y para corrigir**: ela está no chão, atrás do pilar, e sem ordem
de desenho era pintada SOBRE o pilar. Com a regra da OT o pilar (priority sprite de chave
menor) a cobre e ela desaparece dessa câmera — e continua visível da câmera 1, onde o cenário
tem a mesma chama pintada no background. Prova visual: `port/dev/_esp/_prova_profundidade.png`
(esquerda sem profundidade, direita com; embaixo a câmera 10).

Limite declarado, herdado da oclusão: o recorte de máscara é um RETÂNGULO opaco (a forma
per-pixel vive no atlas do PS1, que o port não sabe indexar), então onde o bloco cobre fundo
vazio a chama ganha um "mordido" de canto reto. É o mesmo limite que o `occlusion.gd` já
declara para o personagem.

---

## 11. QUADROS EM HD do pack (Seamless HD Project) — de-para provado (2026-08-08)

Os quadros de ESP em SD são 24×24 a 48×48 texels; esticados 4× no quadro do port viram
blocões. O pack HD do PC tem `hires/effect` (343 arquivos) e `hires/effect0` (48), **todos
1024×1024 RGBA**. O de-para foi fechado por conteúdo, e é barato porque a geometria é
conhecida:

* `1024 = 4 × 256`, e **256×256 é exatamente uma TPAGE de 4bpp** do PS1 (64 halfwords × 256
  linhas). Cada arquivo é uma página inteira, **já colorida** (a CLUT foi aplicada);
* logo o sprite que a tabela B põe em `(u, v)` da tpage está em `(u*4, v*4)` do `.webp`, com
  lado `size*4`. **Não há busca de posição** — só a escolha do arquivo.

Critério (`tools/esp_decode.py hd`):
1. **FORMA** — NCC de `luminância × alfa` nos pixels dos quadros que a sala realmente usa.
   Medido no `R10D`: verdadeiro **0,9992** (banco `0x24`) e **0,9986** (`0x26`); primeiro
   reprovado **0,763** e **0,503**. É separação de ordem de grandeza, não de calibração fina.
2. **COR** — entre os empatados na forma (a mesma página aparece em vários arquivos, um por
   linha de CLUT em uso), o menor RMS de cor contra o sprite SD **daquela variante**. No
   `R10D` isso é o que separa `effect/D51197D9` (paleta da linha 488, banco `0x24`) de
   `effect/156E5DED` (linha 490, banco `0x26`): RMS 7,2 e 8,5 contra 10,6/15,1 do trocado.

**Não há atribuição global (Hungarian) aqui, de propósito:** o pareamento não é 1:1 — uma
página HD serve MUITAS salas (as 156 com ESP compartilham páginas de efeito), então unicidade
seria uma restrição falsa. O que substitui a atribuição global é o vínculo geométrico
`(u,v) × 4`, que torna cada par decidível sozinho com folga medida. (A atribuição global é a
ferramenta certa quando o vínculo geométrico não existe — é o caso dos memos/UI, ver
`tools/hd_map_build.py` e `port/data/hd_ui_map.json`.)

Saída: `assets/ESP/sala/<SALA>/hd/t{tipo}_A{a}_B{b}_v{var}_{px}x{px}.png` (px = `size*4`) e o
mapa `port/data/esp_hd_map.json` com NCC, RMS, IoU de alfa e o NCC do primeiro reprovado —
ou seja, a folga fica registrada par por par. `esp_sala.gd` prefere o HD e cai no SD sozinho.

> Cuidado com as variantes por data do pack (o conjunto de janeiro/2025 é RUSSO e o de junho é
> PT-BR): aqui **não se aplica**, porque efeito não tem texto. O critério de idioma
> (`tools/memo_pt.py`) vale para `memo`/`misc`/UI.

---

## 12. Como medir de novo

```bash
# desassemblar (o exe_parse trava em instruções COP2/GTE; use um passo-a-passo)
PYTHONIOENCODING=utf-8 python -c "
import sys; sys.path.insert(0,'tools'); from exe_parse import Exe
e=Exe('extracted/ntsc-u/SLUS_009.23')
for l in e.disasm(0x8001b484,120): print(l)"

# formato do ESP
PYTHONIOENCODING=utf-8 python tools/esp_decode.py scan
PYTHONIOENCODING=utf-8 python tools/esp_decode.py scan --room STAGE1/R101
PYTHONIOENCODING=utf-8 python tools/esp_decode.py scan --all-rooms
PYTHONIOENCODING=utf-8 python tools/esp_decode.py dump port/assets/ESP

# xrefs / callers
PYTHONIOENCODING=utf-8 python tools/esp_scan_helper.py xref 0x800ba728 0x800ba8a8
PYTHONIOENCODING=utf-8 python tools/esp_scan_helper.py jal 0x8001b484

# quadros do ESP da SALA (SD) e o de-para HD (§11)
PYTHONIOENCODING=utf-8 python tools/esp_decode.py dump port/assets/ESP --all-rooms
PYTHONIOENCODING=utf-8 python tools/esp_decode.py hd --room STAGE1/R10D
PYTHONIOENCODING=utf-8 python tools/esp_decode.py hd            # as 156 salas com ESP

# profundidade no port (§10): números e foto
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path port --script res://dev/diag_esp_prof.gd
ESP_CAMS=0,10 "$GODOT" --path port --rendering-driver opengl3 \
    --script res://dev/shot_esp_prof.gd          # NÃO usar --headless (não renderiza)
"$GODOT" --headless --path port --script res://dev/run_tests.gd -- esp
```
