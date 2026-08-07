# Overlays de tela `CD_DATA/BIN/*.BIN` — formato, carregador e mapa de chamadas

**Alvo:** RE3 PS1 NTSC-U, `SLUS_009.23` (PS-X EXE, base `0x80010000`, tsize `0xd3800`, entry `0x80011b80`).
**Ferramenta:** [`tools/overlay_parse.py`](../../../tools/overlay_parse.py) (`Overlay`, mesma interface de `exe_parse.Exe`).
**Escopo:** o formato dos 17 `BIN/*.BIN`, o endereço de carga de cada um, o carregador no EXE,
quem chama quem, e as funções compartilhadas do EXE que os overlays usam.
**Fora de escopo (não medi):** coordenadas de tela, tamanhos de grade, cores. Nada disso está aqui.

> **Correções a `menus.md`** (aquela nota tem afirmações erradas — ver §9): o cabeçalho não é
> `u32 N` + ponteiros de função; a tabela do início **não** é dispatch de funções; e
> `0x800788dc` **não** é helper de texto (é `flag_set`).

---

## 1. Formato do arquivo — imagem plana, sem cabeçalho e sem relocação

O arquivo é **copiado byte-a-byte** para um endereço fixo de RAM. Não há cabeçalho, não há
tabela de relocação, não há compressão:

```
arquivo[i]  ->  RAM[base + i]        para todo 0 <= i < tamanho
```

**Prova (3 sinais independentes):**

1. **Votação alvo-de-`jal` × início-de-função.** Todo `jal` para dentro da faixa
   `0x80180000..0x801e0000` tem de cair num início de função. Para cada alvo `t` e cada offset
   candidato `o` de início de função no arquivo, `base = t - o`; vencedor por votos, com a
   restrição dura de que **todos** os alvos caiam em `[base, base+tamanho)`.
   Reproduzir: `python tools/overlay_parse.py --all` → **17/17 resolvem sem ambiguidade**
   (ex.: `SELECT` 24/24 alvos, `MEM_CARD` 27/29, `TITLE` 11/11).
2. **A tabela de destinos no EXE** contém exatamente as mesmas 3 bases (§3).
3. **O ponto de entrada** de cada overlay (campo do registro no EXE, §3) cai num prólogo
   `addiu $sp, $sp, -N` **em exatamente um** dos 17 arquivos — matriz 17×17 com diagonal
   perfeita (§4). Se a base estivesse errada por 1 palavra isso não fecharia.

**Não existe tabela de relocação.** A cauda dos arquivos é código/zero, nunca uma tabela de
offsets (16 dos 17 terminam em `00 00 …`; `ENDING.BIN` termina no epílogo de função
`8fbf0014 8fb00010 03e00008 27bd0018`; `MUSICBOX.BIN` termina em dados `ffffc3b0 …`).
E não precisa existir: todos os ponteiros no arquivo já são absolutos e corretos para a base fixa.

### 1.1 Layout interno (não é um header formal — varia por arquivo)

```
+0x00  u32       constante pequena, 0x36..0x45, uma por arquivo (16 dos 17).
                 WARNING.BIN NÃO tem essa palavra. PAPEL NÃO PROVADO — ver §8.
+0x04  u32[N]    POOL DE TABELAS DE `switch` geradas pelo compilador: ponteiros
                 absolutos para LABELS DE CÓDIGO (não são funções — 0/…/0 prólogos).
                 Usadas por `jr $rX` após `sltiu` de limite. Tabelas consecutivas
                 são separadas por palavras 0x00000000 (alinhamento).
                 Em WARNING.BIN começa em +0x00.
...              dados: strings ASCII (rótulos de asset, format strings), tabelas de
                 glifo u16 (prefixos 0x82/0x89), descritores, TABELAS DE HANDLER
                 (ponteiros de FUNÇÃO por estado — essas ficam no fim, ver §6).
...              código MIPS R3000.
```

O **ponto de entrada não é o offset 0**: vem do registro do overlay no EXE (§3/§4).

---

## 2. Tabela global de arquivos do CD — `0x800946a4`

O EXE não guarda nome de arquivo (`grep` por `PC_SYS`/`TITLE`/`.BIN` no `.text` → **0 hits**).
Tudo é por **índice** numa tabela de 8 bytes por entrada em **`0x800946a4`**:

```
+0x00  u32  size   tamanho em bytes
+0x04  u16  lba_lo
+0x06  u8   lba_hi        LBA (setor) = lba_lo | (lba_hi << 16)   -- 24 bits
+0x07  u8   flags         NÃO DECODIFICADO (só sei que é copiado p/ req+0x2a)
```

**Prova do layout:** em `cd_read_file` (§3.2), `0x800128b4`–`0x800128e8`:
`addiu v0,v0,0x46a4` / `sll v1,s6,3` / `addu v1,v1,v0` / `lbu v0,7(v1)` → `sb v0,0x2a(s1)` /
`lw v0,(v1)` → `sw v0,0x14(s1)` / `lbu v0,6(v1)` + `lhu v1,4(v1)` / `sll v0,v0,0x10` /
`addu v0,v0,v1` → `sw v0,0x20(s1)`.

**Prova do conteúdo:** a tabela está na **ordem ISO** (diretórios alfabéticos, arquivos
alfabéticos dentro de cada um). Comparando `size` da tabela com o tamanho real dos arquivos
extraídos de `extracted/ntsc-u/CD_DATA/`: **as 485 primeiras entradas (0x000..0x1e4) batem
exatamente**; da 0x1e5 em diante há um deslocamento de 1 (a tabela lista um arquivo de
4 073 984 B que não temos extraído). Também `lba[i+1] - lba[i] == ceil(size[i]/2048)` em toda a
faixa conferida.

Como `BIN/` é o primeiro diretório, **os `BIN/*.BIN` são os índices `0x00`..`0x10`, em ordem
alfabética**. Índices úteis conferidos por tamanho:

| idx | arquivo | size | lba |
|---|---|---|---|
| `0x00` | `BIN/DIEDEMO.BIN` | 17116 | 25 |
| `0x10` | `BIN/WARNING.BIN` | 5664 | 117 |
| `0x11` | `ETC/CAPCOM.TIM` | 153620 | 123 |
| `0x15` | `ETC/CORE00.TIM` | 64480 | 357 |
| `0x16` | `ETC/DIEDEMO.TIM` | 49696 | 389 |
| `0x2f`/`0x30` | `ETC/INIT_SUB.DAT` / `ETC/INIT_TBL.DAT` | 2312 | 5433/5435 |
| `0x36`/`0x38` | `ETC/JILL_BGU.TIM` / `ETC/JILL_OBU.TIM` | 153620 / 66592 | 6355 / 6464 |
| `0x3c` | `ETC/OMBG_U.DAT` | 1556480 | 7877 |
| `0x3d`/`0x3e` | `ETC/OPENING0.DAT` / `ETC/OPENING1.DAT` | 457504 / 307322 | 8637 / 8861 |
| `0x40` | `ETC/OPTIONU.DAT` | 534528 | 9273 |
| `0x46`/`0x48` | `ETC/RES0_BGU.TIM` / `ETC/RES0_OBU.TIM` | 153620 / 99872 | 9619 / 9744 |
| `0x52`/`0x54` | `ETC/SELE_BGU.TIM` / `ETC/SELE_OBU.TIM` | 153620 / 99872 | — |
| `0x56` | `ETC/STAFF_U.DAT` | 406816 | — |
| `0x61` | `ETC/STR_BG.DAT` | 564000 | — |
| `0x67` | `ETC/TITLEU.DAT` | 340072 | — |
| `0x68` | `ETC/TYPE00.PIX` | **153600** | — |
| `0x6b` | `ETC/WARNU.TIM` | — | — |

Reproduzir: `python tools/overlay_parse.py X --filetable 200` (ou `cd_file_table()`).

> **`0x68` = 153600 bytes = 320·240·2 exato, SEM header TIM** — é um framebuffer cru.
> É o que `MEM_CARD.BIN` carrega com o rótulo `"MEMORY CARD BG"` (§5).

---

## 3. O carregador de overlay no EXE

### 3.1 Tabela de overlays — `0x8009c944`, registros de 12 bytes

```
+0x00  u32  file_index   índice na tabela de arquivos do CD (§2)
+0x04  u32  entry        endereço de entrada, JÁ em RAM (dentro do overlay)
+0x08  u32  *dest        PONTEIRO para a palavra que contém o endereço de destino
```

Tem **24 registros** (`0x8009c944`..`0x8009ca6b`): os 17 primeiros são os `BIN/*.BIN`,
os 7 seguintes são **overlays de sala** (`file_index` 0x177, 0x232, 0x2d2, 0x366, 0x3f5,
0x475, 0x4ef; `entry` `0x8011a004`, um deles `0x8011af14`; `dest` `0x80010324` → `0x8011a000`).

### 3.2 As duas funções de carga

```
0x80031f50   load_overlay_task(a0 = task_slot, a1 = ovl_id)
    rec = 0x8009c944 + ovl_id*12                      # sll a1,1; addu; sll 2  (=*12)
    cd_read_file(a0=rec->file_index, a1=*rec->dest, a2=0, a3=0x800106dc)
    set_task_entry(0x8003201c)(a0 = task_slot, a1 = rec->entry)

0x80031fc0   load_overlay_run(a0 = ovl_id)
    rec = 0x8009c944 + ovl_id*12
    cd_read_file(a0=rec->file_index, a1=*rec->dest, a2=0, a3=0x800106e4)
    run_now(0x80032110)(a0 = rec->entry)
```

```
0x80012818   cd_read_file(a0 = file_index, a1 = dest, a2 = mode, a3 = MORTO)
    req = 0x800b9e10                       # lui 0x800c; addiu -0x61f0
    req+0x2a  = filetab[idx].flags         # lbu 7(v1)
    req+0x14  = filetab[idx].size
    req+0x20  = filetab[idx].lba (24 bits)
    req+0x28  = file_index   (sh s6)
    req+0x40  = dest         (sw s7)
    req+0x24  = (size + 0x7ff) >> 11       # NÚMERO DE SETORES (2048 B)
    ...
```

**`a3` é morto**: é sobrescrito em `0x80012918` (`addiu $a3, $v0, -0x58c8`) sem ter sido lido.
Em compilação de debug era o **nome do arquivo**; os overlays continuam passando essa string,
e é exatamente por isso que dá para identificar cada asset (§5).

**Consequência para o port:** o jogo lê **setores inteiros**. `ceil(size/2048)*2048` bytes são
escritos em `dest`, ou seja até 2047 bytes **além** do fim do arquivo. Ex.: `DIEDEMO.BIN`
17116 B → 9 setores → 18432 B escritos em `0x80194000`.

### 3.3 Slots de destino — `0x8001031c` (19 palavras)

| endereço da palavra | valor (destino) | uso |
|---|---|---|
| `0x8001031c` | **`0x80194000`** | slot de **boot**: `DIEDEMO`, `ENDING`, `TITLE` |
| `0x80010320` | **`0x80184000`** | slot do **`WARNING`** |
| `0x80010324` | **`0x8011a000`** | slot de overlay de **SALA** (registros 17..23) |
| `0x80010328` | **`0x801c2000`** | slot **in-game**: os outros 13 `BIN/*.BIN` |
| `0x8001032c` | `0x800b9de8` | (outro alvo; não investigado) |
| `0x80010330`..`0x80010364` | `0x80200000` (e `0x80700e30` em `0x80010350`) | sentinelas / dev |

Os 4 destinos são alinhados a 4 KiB — é o critério de desempate #2 em `resolve_base`.

Nenhuma instrução do EXE forma o endereço `0x8001031c` por `lui/addiu`; a tabela é alcançada
só pelo campo `+0x08` dos registros de overlay (palavras `0x8001031c`/`0x80010320`/`0x80010324`/
`0x80010328` aparecem como dado em `0x8009c944`+).

### 3.4 Tabela de buffers de staging — `0x80010380`

Copiada para a pilha em `0x800130dc`..`0x8001310c` (7 palavras):
`0x00000000, 0x80100000, 0x8010d000, 0x801fb600, 0x00000000, 0x801f7e00, 0x801f2600`.

Confirmado pelo uso real (`a1` de `cd_read_file` nos overlays, §5):
`0x801f7e00` = buffer **BGM principal**; `0x801f2600` = buffer **BGM secundário**;
`0x80100000` = staging de atlas de objetos (`*_OBU.TIM`, `*.DAT`).

E o mais importante para o mapa de memória:

```
0x8019c000 + 153620 = 0x801c1814
```

`0x8019c000` é o staging de **BG full-screen 320×240** (todo `*_BGU.TIM`/`CAPCOM`/`WARNU`
de 153620 B vai para lá) e ele **termina exatamente onde o EXE começa a usar `0x801c1814`**
(lido em `0x80013fd4`, `0x800143e8`, `0x800297a4`, `0x80014ab4`…), logo abaixo do slot
in-game `0x801c2000`. Coincidência exata → é o layout real.

Checagem de não-sobreposição: `0x80184000`+3 setores = `0x80185800` < `0x80194000`;
`0x80194000`+7 setores (`TITLE`) = `0x80197800` < `0x8019c000`; `0x801c2000`+12 setores
(`MEM_CARD`, o maior) = `0x801c8000`.

---

## 4. Os 17 overlays — identidade PROVADA

`ovl_id == file_index` (a tabela do CD está em ordem alfabética e `BIN/` é o 1º diretório).
A identidade de cada registro foi provada pela **matriz 17×17**: para cada `entry` da tabela,
qual arquivo (com a base do slot correspondente) tem um prólogo `addiu $sp,$sp,-N` naquele
offset. **Diagonal perfeita — um X por linha e por coluna.** Reproduzir: script em §10.

| id | arquivo | base | entry | off entry | setores | tab. `switch` no início | 1ª tabela de handler |
|---|---|---|---|---|---|---|---|
| `0x00` | DIEDEMO  | `0x80194000` | `0x80194010` | +0x010 | 9 | — | `0x80198208` ×9 |
| `0x01` | ENDING   | `0x80194000` | `0x80194004` | +0x004 | 1 | — | — |
| `0x02` | EPILOG   | `0x801c2000` | `0x801c204c` | +0x04c | 2 | — | `0x801c2bcc` ×4 |
| `0x03` | GEARBOX  | `0x801c2000` | `0x801c2008` | +0x008 | 2 | — | — |
| `0x04` | JILL_SEL | `0x801c2000` | `0x801c2050` | +0x050 | 4 | 11 (5+NULL+5) | `0x801c3468` ×3 |
| `0x05` | LTSOUT   | `0x801c2000` | `0x801c2018` | +0x018 | 2 | 5 | — |
| `0x06` | MEM_CARD | `0x801c2000` | `0x801c20ac` | +0x0ac | 12 | — | `0x801c6878` ×40 |
| `0x07` | MUSICBOX | `0x801c2000` | `0x801c2030` | +0x030 | 2 | 11 (5+NULL+5) | — |
| `0x08` | OPENING  | `0x801c2000` | `0x801c2024` | +0x024 | 3 | — | `0x801c2f70` ×13 |
| `0x09` | OPTION   | `0x801c2000` | `0x801c21b0` | +0x1b0 | 11 | 6 | `0x801c5554` ×12 |
| `0x0a` | PC_SYS   | `0x801c2000` | `0x801c2354` | +0x354 | 8 | 5 | — |
| `0x0b` | R214_OL  | `0x801c2000` | `0x801c2020` | +0x020 | 2 | 7 | — |
| `0x0c` | RESULT   | `0x801c2000` | `0x801c21ec` | +0x1ec | 11 | — | `0x801c69bc` ×9 |
| `0x0d` | SELECT   | `0x801c2000` | `0x801c2094` | +0x094 | 10 | 17 (5+N+5+N+5) | `0x801c5ccc` ×10 |
| `0x0e` | STAFF_R  | `0x801c2000` | `0x801c206c` | +0x06c | 6 | — | `0x801c4050` ×3 |
| `0x0f` | TITLE    | `0x80194000` | `0x801940e8` | +0x0e8 | 7 | 10 | `0x801974c0` ×5 |
| `0x10` | WARNING  | `0x80184000` | `0x80185418` | +0x1418 | 3 | 20 | — |

> Os 13 do slot `0x801c2000` **não coexistem**: são trocados em runtime, um por vez, no mesmo
> buffer. Igualmente `DIEDEMO`/`ENDING`/`TITLE` compartilham `0x80194000`.

### 4.1 O `switch` do início — como confirmar o N

`WARNING`, exemplo completo e sem ambiguidade (`0x80184170`+):

```
lui  $v1, 0x8018
lw   $v1, 0x55c0($v1)      # estado = *(u32*)0x801855c0   (variável DENTRO do overlay)
sltiu $v0, $v1, 0x14       # bound = 20 == número de entradas da tabela
beqz $v0, 0x80184a78       # default
sll  $v0, $v1, 2
lui  $at, 0x8018
addu $at, $at, $v0
lw   $v0, 0x4000($at)      # tabela = 0x80184000 = base+0
jr   $v0                   # goto label
```

`PC_SYS` idem com `tabela = 0x801c2004` (`addiu $v0,$v0,0x2004` em `0x801c23ec`), `jr` em
`0x801c2400`, bound 5, variável `0x800d1d26` (**no EXE**, não no overlay).

Reproduzir: `python tools/overlay_parse.py WARNING --states`.
`PC_SYS` conferido à mão em `0x801c23d0`: `lui $v0,0x800d; lbu $v1,0x1d26($v0); sltiu $v0,$v1,5`
→ estado é um **u8** em `0x800d1d26`.

Medidos (bound / variável de estado): `WARNING` 20 / `0x801855c0`; `PC_SYS` 5 / `0x800d1d26`;
`OPTION` 6 / `0x801c55a2`; `R214_OL` 7 / `0x801c2c81`; `LTSOUT` 5 / `0x801c2b48`;
`JILL_SEL` 5 / `0x801c3490`; `MUSICBOX` 5 / `0x800cc914`.
`SELECT` bound 5 mas a variável saiu ruído → **NÃO MEDIDO**. `TITLE` não casa com esse padrão.

---

## 5. Que asset cada overlay carrega — PROVADO por `cd_read_file`

Rastreando as constantes de `a0..a3` em cada `jal 0x80012818` (o rótulo de debug em `a3`
resolve a ambiguidade quando `a0` vem de variável).
Reproduzir: `python tools/overlay_parse.py RESULT --calls`.

| overlay | sítio | `a0` idx | `a1` destino | rótulo (`a3`) | arquivo |
|---|---|---|---|---|---|
| DIEDEMO | `0x80197f74` | 0x16 | `0x8019c000` | `DIEDEMO.TIM` | `ETC/DIEDEMO.TIM` |
| EPILOG | `0x801c20b8` | 0x11f | `0x801f7e00` | `EPILOG BGM` | `SOUND/MAIN33.BGM` |
| EPILOG | `0x801c2128` | 0x1a | `0x80100000` | `EPIS.TIM` | `ETC/EPIS_U.DAT` |
| EPILOG | `0x801c2b34` | 0x3c | — | `OMBG.TIM` | `ETC/OMBG_U.DAT` |
| JILL_SEL | `0x801c28b4` | var | — | `PLD` | (modelo do jogador) |
| JILL_SEL | `0x801c2ac4` | var | — | `WEP DATA` | (arma) |
| JILL_SEL | `0x801c2e10` | 0x36 | `0x8019c000` | `Jill BG` | `ETC/JILL_BGU.TIM` |
| JILL_SEL | `0x801c2e28` | 0x38 | `0x80100000` | `JIll` | `ETC/JILL_OBU.TIM` |
| **MEM_CARD** | `0x801c2570` | **0x68** | `0x8019c000` | **`MEMORY CARD BG`** | **`ETC/TYPE00.PIX`** (153600 B = 320×240×2 cru) |
| OPENING | `0x801c2204` | 0x3d | `0x80100000` | `OPENING0_DAT` | `ETC/OPENING0.DAT` |
| OPENING | `0x801c2284` | 0x3e | `0x80100000` | `OPENING1_DAT` | `ETC/OPENING1.DAT` |
| OPTION | `0x801c312c` | 0x15 | `0x8019c000` | `CORE00_TIM` | `ETC/CORE00.TIM` |
| OPTION | `0x801c32e0` | 0x40 | `0x8019c000` | `Option.dat` | `ETC/OPTIONU.DAT` |
| OPTION | `0x801c3448` | 0x40 | `0x8019c000` | `PaddN.tim` | `ETC/OPTIONU.DAT` |
| OPTION | `0x801c4660` | 0x40 | `0x8019c000` | `Color.tim` | `ETC/OPTIONU.DAT` |
| RESULT | `0x801c21d4` | 0x3c | — | `OMBG.TIM` | `ETC/OMBG_U.DAT` |
| RESULT | `0x801c32b0`/`4144`/`5340` | 0x46 | `0x8019c000` | `RESULT BG` | `ETC/RES0_BGU.TIM` |
| RESULT | `0x801c5888` | 0x50 | `0x8019c000` | `RESULT BG` | `ETC/RES5_BGU.TIM` |
| RESULT | `0x801c5b10` | 0x4e | `0x8019c000` | `RESULT BG` | `ETC/RES4_BGU.TIM` |
| RESULT | `…32c8/415c/5358/58a0/5b28` | 0x48 | `0x80100000` | `RESULT` | `ETC/RES0_OBU.TIM` |
| RESULT | `0x801c37a8`/`4a80` | 0x125 | `0x801f7e00` | `RESULT BGM` | `SOUND/MAIN3D.BGM` |
| RESULT | `0x801c56cc` | 0x129 | `0x801f2600` | `RESULT BGM` | `SOUND/SUB_2A.BGM` |
| RESULT | `0x801c5c20` | 0x11f | `0x801f7e00` | `RESULT BGM` | `SOUND/MAIN33.BGM` |
| SELECT | `0x801c3884` / `3b40` | var | — | `PLD` / `WEP DATA` | (modelo/arma) |
| SELECT | `0x801c4790` | 0x52 | `0x8019c000` | `Select BG` | `ETC/SELE_BGU.TIM` |
| SELECT | `0x801c47a8` | 0x54 | `0x80100000` | `Select` | `ETC/SELE_OBU.TIM` |
| STAFF_R | `0x801c2154` | 0x61 | `0x801064e0` | `STR_BG_DAT` | `ETC/STR_BG.DAT` |
| STAFF_R | `0x801c2174` | 0x56 | `0x80100000` | `STAFF_U_DAT` | `ETC/STAFF_U.DAT` |
| TITLE | `0x801944dc` | 0x121 | `0x801f7e00` | `OPTION BGM` | `SOUND/MAIN38.BGM` |
| TITLE | `0x80195fac` / `96d6c` | 0x2f | `0x800d1d28` | `INIT_SUB` | `ETC/INIT_SUB.DAT` |
| TITLE | `0x80195fd0` / `96d90` | 0x123 | `0x801f7e00` | `OMAKE BGM` | `SOUND/MAIN39.BGM` |
| TITLE | `0x80196068` / `96e00` | var | `0x800d1d28` | `INIT_TBL` | `ETC/INIT_TBL.DAT` (idx 0x30) |
| TITLE | `0x80196768` | var | `0x80192000` | `Pdemo` | `ETC/PDEMO0?.DAT` |
| TITLE | `0x801973fc` | 0x67 | `0x80130000` | `TITLE_DAT` | `ETC/TITLEU.DAT` |
| TITLE | `0x80197430` | 0x11 | `0x8019c000` | `Capcom.tim` | `ETC/CAPCOM.TIM` |
| WARNING | `0x8018543c` | 0x6b | `0x8019c000` | `Warning` | `ETC/WARNU.TIM` |

Overlays **sem nenhuma** chamada a `cd_read_file` e **sem nenhuma string ASCII**:
`ENDING`, `GEARBOX`, `LTSOUT`, `MUSICBOX`, `PC_SYS`, `R214_OL`.
Para esses a identidade funcional **não está provada por asset** — só por perfil de chamadas.
(`PC_SYS` tem 29 strings, mas nenhum `cd_read_file`: renderiza texto próprio.)

---

## 6. Laço principal de tela: `handlers[estado](ctx)` + yield

`TITLE`, entry `0x801940e8` — é o padrão de todas as telas com tabela de handler:

```
0x801940e8  addiu sp,-0x20
0x801940fc  jal 0x80038634 (a0=0x5000, a1=0x20a)     # init da tela
0x80194108  addiu $s1, 0x8019<<16, 0x74c0            # s1 = handlers = 0x801974c0
0x80194114  ...  0x80197508                          # ctx da tela
0x8019411c  sh 0x12c, 0x16(ctx)                      # (300)
0x80194130  lbu $v0, 0x7508($s0)                     # estado = *(u8*)ctx
0x80194138  sll  $v0, 2
0x8019413c  addu $v0, $s1
0x80194140  lw   $v0, ($v0)                          # f = handlers[estado]
0x80194148  jalr $v0                                 # f(ctx)
0x8019414c  addiu $a0, $s0, 0x7508
0x80194150  jal 0x8003203c (a0=1)                    # yield 1 frame
0x80194158  j 0x80194130                             # loop infinito
```

Tabelas de handler achadas (`python tools/overlay_parse.py X --handlers`; todas dentro do
próprio overlay, entradas são prólogos de função de verdade):

| overlay | `jalr` | tabela | n |
|---|---|---|---|
| TITLE | `0x80194148` / `0x801955d0` | `0x801974c0` / `0x801974d8` | 5 / 12 |
| DIEDEMO | `0x80194128` / `0x80195314` / `0x80196414` | `0x80198208` / `0x80198228` / `0x8019824c` | 9 / 1 / 4 |
| SELECT | `0x801c20dc` / `0x801c2914` | `0x801c5ccc` / `0x801c5ce4` | 10 / 4 |
| MEM_CARD | `0x801c2178` / `0x801c2204` | `0x801c6878` / `0x801c68c8` | 40 / 20 |
| OPTION | `0x801c24c4` / `0x801c2574` / `0x801c2598` | `0x801c5554` / `0x801c5554` / `0x801c556c` | 12 / 12 / 6 |
| RESULT | `0x801c2234` … `0x801c5b84` (7 sítios) | `0x801c69bc`, `69d4`, `6bb4`, `6d14`, `6d20`, `6d48`, `6d54` | 9,3,3,6,3,6,3 |
| STAFF_R | `0x801c20ec` … `0x801c2b64` | `0x801c4050`, `40a0`, `40b0`, `40bc` | 3,6,2,4 |
| OPENING | `0x801c20a4` | `0x801c2f70` | 13 |
| JILL_SEL | `0x801c2088` | `0x801c3468` | 3 |
| EPILOG | `0x801c2318` | `0x801c2bcc` | 4 |

`WARNING`, `PC_SYS`, `GEARBOX`, `MUSICBOX`, `LTSOUT`, `R214_OL`, `ENDING` **não** usam
tabela de handler: usam o `switch`/`jr` do §4.1 direto.

---

## 7. Grafo de chamadas — quem carrega qual overlay

### 7.1 A partir do EXE

O EXE pede telas via **bits de `0x800cc858`** (= `0x800ca738 + 0x2120`, sendo
`0x800ca738 = lui 0x800d; addiu -0x58c8`, o registro-base global). Os 12 sítios:

| sítio | função | chamada | overlay | guarda medida |
|---|---|---|---|---|
| `0x800232e4` | `0x80023268` | task | `0x03` GEARBOX | `0x800d1f2c & 0x20 == 0` (flag de progresso) |
| `0x800235f4` | `0x80023268` | task | `0x04` JILL_SEL | `0x800cc858 & 0x00100000` |
| `0x8002362c` | `0x80023268` | task | `0x02` EPILOG | `0x800cc858 & 0x00080000` |
| `0x80023fc8` | `0x80023268` | task | `0x0c + n` → RESULT/SELECT/STAFF_R | `0x800cc858 & 0x2000`; `n = *(u16*)*(0x800cc914)` |
| `0x80024028` | `0x80023268` | task | `0x03` GEARBOX | `*(s16*)0x800d1f7a == *(u8*)0x800ccbbe` |
| `0x80024274` | `0x80023268` | **run** | `0x09` OPTION | `0x800cc858 & 0x4000` |
| `0x80024308` | `0x80023268` | task | `0x08` OPENING | — |
| `0x80029c94` | `0x80029b94` | task | `0x01` ENDING | — |
| `0x80029cd8` | `0x80029b94` | **run** | `0x01` ENDING | — |
| `0x8002a2a0` | `0x8002a1f8` | task(slot 0) | `0x00` DIEDEMO | — (caminho de game over) |
| `0x800498b4` | `0x80049898` | task(slot 2) | `0x11 + *(s16*)0x800d1f76` | **overlay de SALA** (registros 17..23) |
| `0x800792bc` | `0x800791f0` | task | `0x02` EPILOG | seta `0x800cc858 \|= 0x4000` |

`0x80023268` é o fluxo de boot/título (contém 7 dos 12 sítios).

### 7.2 A partir de outros overlays

| origem | sítio | overlay carregado |
|---|---|---|
| TITLE | `0x80195af4` | `0x02` EPILOG |
| TITLE | `0x80195b14` | `0x0a` PC_SYS |
| TITLE | `0x8019603c` | `0x06` MEM_CARD |
| TITLE | `0x801960d8` | `0x05` LTSOUT |
| TITLE | `0x801963f0` | `0x04` JILL_SEL |
| TITLE | `0x801965a8` | `0x08` OPENING |
| TITLE | `0x80196ec8` | `0x05` LTSOUT |
| ENDING | `0x801940d8` | `0x0b` R214_OL |
| ENDING | `0x801940fc` / `8019412c` / `8019421c` / `801943bc` | `0x08` OPENING |
| ENDING | `0x801941d4` | `0x07` MUSICBOX |
| ENDING | `0x8019429c` | `0x02` EPILOG |

**`ENDING.BIN` (1080 B) é um DESPACHANTE, não uma tela.** Seu corpo (`0x8019409c`+) testa
bits 0,1,2,3,4,5,0xa de `0x800d1f30` com `flag_test` (`0x80078930`) e, conforme o resultado,
carrega `R214_OL`/`OPENING`/`MUSICBOX`/`EPILOG`. É o fluxo pós-ending / desbloqueio de bônus.
(`0x800d1f30` = banco de flags 1, palavra 1 — o mesmo banco de progresso já provado no repo.)

Nenhum overlay do slot `0x801c2000` chama `load_overlay` (só `ENDING` e `TITLE`, ambos do
slot de boot, chamam) — coerente com o fato de que carregar sobrescreveria a si mesmo.

---

## 8. A palavra em `+0x00` (0x36..0x45) — NÃO PROVADO

| arquivo | `u32` @+0 | | arquivo | `u32` @+0 |
|---|---|---|---|---|
| TITLE | `0x36` | | R214_OL | `0x3e` |
| DIEDEMO | `0x37` | | MUSICBOX | `0x3f` |
| ENDING | `0x38` | | GEARBOX | `0x40` |
| MEM_CARD | `0x39` | | SELECT | `0x41` |
| OPTION | `0x3a` | | JILL_SEL | `0x42` |
| OPENING | `0x3b` | | RESULT | `0x43` |
| PC_SYS | `0x3c` | | EPILOG | `0x44` |
| LTSOUT | `0x3d` | | STAFF_R | `0x45` |
| | | | **WARNING** | **não tem** |

Fatos: são 16 valores **distintos e consecutivos**; **nenhuma** instrução (nem no overlay, nem
no EXE) lê `base+0` — varri todas as instruções de load/store com endereço efetivo constante
nos 17 arquivos e no `.text` do EXE, resultado zero. **Não é** o índice do arquivo no CD
(o overlay é `0x00`..`0x10`), **não é** o índice do primeiro asset que ele carrega
(DIEDEMO tem `0x37` mas `DIEDEMO.TIM` é `0x16`), **não é** contagem de nada
(TITLE tem `0x36`=54 e só 10 entradas de tabela).
Hipóteses não testadas: número de módulo do build; id de tela de um menu de debug.
**Deixe como NÃO SEI.** Não use esse número para nada.

---

## 9. Funções compartilhadas do EXE que os overlays chamam

Histograma real (`Overlay.exe_calls()` nos 17 arquivos). "×N" = número de sítios de `jal`.

### 9.1 Identificadas com assinatura lida no binário

| endereço | ×N | overlays | assinatura / papel | prova |
|---|---|---|---|---|
| `0x800746c0` | 138 | 13 | **enqueue de sprite** (`a0`=sprite_id, `a1`=template, `a2`,`a3`) | ver `menus.md §8.2` (não reverifiquei aqui) |
| `0x8003203c` | 97 | **17** | **`yield(a0)`**: `blk=*(0x800dcd14); blk->u16[1]=a0; blk->u16[0]=1; 0x80090374(0xff000000)` | disasm `0x8003203c` |
| `0x8008f5c4` | 96 | 13 | **`AddPrim(a0=ot, a1=prim)`** (libgpu): `*a1 = (*a1 & 0xff000000)\|(*a0 & 0x00ffffff)` … | disasm `0x8008f5c4` |
| `0x8002a35c` | 91 | 12 | setup de sprite/prim no array `0x800d443c + a0*0x44` (`sll4+addu+sll2` = ×68) | disasm `0x8002a374`.. |
| `0x80078930` | 66 | 11 | **`flag_test(a0=banco, a1=bit)`** → `banco[bit>>5] & (0x80000000>>(bit&31))` | disasm |
| `0x800788dc` | 31 | 9 | **`flag_set(a0, a1)`** → `banco[bit>>5] \|= 0x80000000>>(bit&31)` | disasm `0x800788dc`–`0x80078900` |
| `0x80078904` | 12 | 5 | **`flag_clear(a0, a1)`** (mesmo com `nor`) | disasm `0x80078904`–`0x80078928` |
| `0x80012818` | 47 | 11 | **`cd_read_file`** (§3.2) | disasm |
| `0x8002a6bc` | 54 | 9 | `read_byte(0x800d42a0 + a0*0x44 + 0x19c)` — consulta de estado do sprite | disasm |
| `0x8003201c` | — | — | `set_task_entry(a0=task, a1=entry)`: `tbl[a0*0x80+8]=entry; tbl[a0*0x80+4]=2`, `tbl=0x800dcb90` | disasm |
| `0x80032070` | 21 | 16 | como `0x8003203c` mas `blk->u16[0]=0` (yield/stop de task) | disasm |
| `0x80032160` | 18 | 13 | `task_suspend(a0)`: `tbl[a0*0x80+4] \|= 0x40` | disasm |
| `0x80032184` | 18 | 13 | `task_resume(a0)`: `tbl[a0*0x80+4] &= ~0x40` | disasm |
| `0x8002f2f8` | 23 | 5 | escreve `0x800d4590+0x75c9` (u8) e `+0x75e4` (u16) — pedido de som/BGM | disasm |
| `0x8002f358` | 48 | 3 | empacota `(a0&0xffff)\|(a1<<16)` + `*(u16*)0x800dbb74 \| 0x8000` → `0x8002f440` | disasm |
| `0x8001b484` | 7 | 3 | spawn de entidade (ver `exe_ai.md`) | — |

### 9.2 Biblioteca PSY-Q (libgpu) — identificadas por `len`/`code` da primitiva

| endereço | ×N | função |
|---|---|---|
| `0x8008f564` | 7 | **`GetTPage(tp,abr,x,y)`** — `((tp&3)<<7)\|((abr&3)<<5)\|((y&0x100)>>4)\|…` |
| `0x8008f5a4` | 13 | **`GetClut(x,y)`** — `(y<<6)\|((x>>4)&0x3f)` |
| `0x8008f5c4` | 96 | **`AddPrim(ot,p)`** |
| `0x8008f604` | 28 | **`SetSemiTrans(p,abe)`** — bit 1 do byte 7 |
| `0x8008f644` | — | **`SetPolyFT4(p)`** — `len=9, code=0x2c` |
| `0x8008f684` | — | **`SetPolyGT4(p)`** — `len=0xc, code=0x3c` |
| `0x8008f6b4` | 35 | **`SetSprt(p)`** — `len=4, code=0x64` |
| `0x8008f6e4` | — | **`SetLineF2(p)`** — `len=3, code=0x40` |
| `0x8008f734` | 19 | `DR_MODE` / `SetDrawMode` — `len=1`, tag `0xe1000200` |
| `0x8008f804` | 7 | `DR_MODE` de 2 palavras — `len=2`, tag `0xe1000200` |

### 9.3 Não identificadas (só o contador; NÃO SEI o que fazem)

`0x80031504` ×62 (LTSOUT, MEM_CARD) · `0x8008f6b4`… já acima ·
`0x800784e0` ×23 (usa `0x8008dbe4`/`0x8008dbf4`) · `0x8002a338` ×26 ·
`0x800102e8` ×14 · `0x80090334` ×14 (só MEM_CARD — provável libmcrd) ·
`0x800100a4` ×12 · `0x8001012c` ×12 · `0x8002fd30` ×12 · `0x80080484` ×10 ·
`0x8008b000` ×10 · `0x8001b894` ×8 · `0x80038704` ×7 · `0x80038634` ×7 ·
`0x80037c38` ×7 · `0x800378c8` ×7 · `0x8002a938` ×7 · `0x8008b2ac` ×7 ·
`0x8008f804` ×7 · `0x800876c4` ×7 · `0x8001245c` ×8 · `0x800782f4` ×8 · `0x800783bc` ×8.

### 9.4 CORREÇÕES a `docs/decomp/notes/menus.md`

1. **`0x800788dc` NÃO é "helper de texto/medida (desenho de glifos real)"** — é
   **`flag_set(banco, bit)`**. `menus.md §8.2` está errado. O trio real é
   `0x800788dc` set / `0x80078904` clear / `0x80078930` test.
2. **A tabela no início do arquivo não é "dispatch de ponteiros de função"** — é o
   **pool de tabelas de `switch`** do compilador, apontando para *labels de código*
   (0 prólogos em todas as 100 entradas somadas). As tabelas de *função* por estado
   existem, mas ficam **no fim** do overlay (§6).
3. **Não existe `u32 N` de contagem em `+0x00`** — §1.1 e §8.
4. **`MEM_CARD` não usa `CHECKJ.TIM`**: usa `ETC/TYPE00.PIX` (idx `0x68`, 153600 B,
   framebuffer cru 320×240×16bpp), rótulo `"MEMORY CARD BG"` (§5).
5. **`ENDING.BIN` não é uma tela de ending** — é o despachante pós-ending (§7.2).
6. As bases (`0x80194000` / `0x801c2000`) coincidem com o que `menus.md §8.1` afirmava;
   agora estão provadas por 3 caminhos independentes, e falta **`0x80184000` (WARNING)**
   que `menus.md` não tinha.

---

## 10. Como medir de novo

```bash
# base + entry dos 17, com placar de votos
PYTHONIOENCODING=utf-8 python tools/overlay_parse.py --all

# por overlay
python tools/overlay_parse.py PC_SYS --info
python tools/overlay_parse.py PC_SYS --dispatch      # tabela de switch do inicio
python tools/overlay_parse.py PC_SYS --states        # jr + bound + var de estado
python tools/overlay_parse.py TITLE  --handlers      # tabelas de handler por estado
python tools/overlay_parse.py RESULT --calls         # jal p/ o EXE c/ args rastreados
python tools/overlay_parse.py PC_SYS --strings
python tools/overlay_parse.py PC_SYS --disasm 0x801c2354 60
python tools/overlay_parse.py X      --filetable 200 # tabela de arquivos do CD
```

Matriz de identidade 17×17 (a prova do §4):

```python
import sys, struct; sys.path.insert(0, 'tools')
from overlay_parse import all_overlays, OVERLAY_TABLE, DEST_SLOTS
for o in all_overlays():
    row = ''
    for k, (nm, fi, entry, dp, ra) in sorted(OVERLAY_TABLE.items()):
        b = DEST_SLOTS[dp]; off = entry - b; m = '.'
        if b == o.base and 0 <= off < o.size - 4:
            w = struct.unpack_from('<I', o.text, off)[0]
            m = 'X' if (w >> 16) == 0x27bd and (w & 0x8000) else '-'
        row += m
    print('%-10s %s' % (o.name, row))     # tem de sair diagonal
```

---

## 11. EM ABERTO

- **Palavra em `+0x00` (0x36..0x45)**: papel desconhecido, ninguém lê. §8. **NÃO SEI.**
- **Byte `flags` (`+0x07`) da tabela de arquivos do CD** (`0x800946a4`): é copiado para
  `req+0x2a` em `cd_read_file`, mas **não decodifiquei** o que o driver de CD faz com ele.
  Testei XOR e soma dos bytes do arquivo — não bate. **NÃO SEI.**
- **`a2` (`mode`) de `cd_read_file`**: os overlays passam 0, 1 ou 2; `cd_read_file` compara
  contra `<2`, `<4`, `<6`, `==4` em `0x80012860`–`0x800128b0`, e valores >=2 caem em
  `s2 -= 2`. **Semântica não fechada.**
- **`0x8001032c` = `0x800b9de8`** — 5º slot de destino; não achei quem usa.
- **Identidade funcional de `GEARBOX` (0x03), `MUSICBOX` (0x07), `LTSOUT` (0x05),
  `R214_OL` (0x0b)**: zero asset, zero string. `GEARBOX` é carregado **duas vezes pelo fluxo
  de boot** (`0x800232e4`, `0x80024028`), o que **não** combina com "tela de extras/GEAR" que
  `menus.md` supõe. **NÃO PROVADO** — precisa de trace em emulador.
- **Variável de estado de `SELECT` e `TITLE`**: `states()` não resolveu (`TITLE` usa outro
  padrão; `SELECT` deu ruído). **NÃO MEDIDO.**
- **Overlays de sala** (registros 17..23 em `0x8009c944`, slot `0x8011a000`,
  `file_index` 0x177/0x232/0x2d2/0x366/0x3f5/0x475/0x4ef): não estão em `BIN/` — estão nos
  `STAGE#/`. Não os mapeei para arquivos. Selecionados por
  `0x11 + *(s16*)0x800d1f76` em `0x800498b4`.
- **`0x800746c0` / `0x80074770` / `0x800749a0`** (pipeline de sprite): reaproveitei a
  descrição de `menus.md §8.2` **sem reverificar** nesta rodada. Trate como herdado, não como
  provado por mim.
- **Bits de `0x800cc858`**: mapeei 5 dos que levam a overlay (0x20/0x80000/0x100000/0x2000/
  0x4000). O restante do bitfield não foi enumerado.
- **Nenhuma coordenada de tela foi medida aqui.** Se você precisa de layout, é o `layout.json`
  do `menu_extract.py` — e desconfie dele até reverificar, porque a nota-mãe tem os erros do §9.4.
