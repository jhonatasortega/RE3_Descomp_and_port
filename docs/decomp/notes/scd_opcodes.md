# Tabela de opcodes do SCD (RE3 PS1 NTSC-U) — tamanhos + evidência

> Fonte: restrição cruzada sobre as 169 salas (cada função do script fecha exatamente
> entre os limites da tabela de ponteiros u16, terminando em `evt_end` 0x01 + padding),
> re-validada. Integrada em `tools/scd_decode.py` (`CONFIRMADO`/`ALTA`/`UNCERTAIN`).
> Numeração confirmada = a mesma do reevengi RE3 (`aot_set`=0x63, `aot_reset`=0x65).

## ⭐ VM DO SCRIPT DE SALA — LOCALIZADO E VERIFICADO (round VM)

> O "elo faltante" foi encontrado no EXE por disassembly. Endereços de prova abaixo.
> Ferramenta: `tools/scd_decode.py` (constantes `VM_*` + `VM_SIZES` autoritativo).

- **Bytecode:** `offset_table[16]` do RDT (o SCD). O room-loader `0x800493ec` carrega o
  RDT e **RELOCA a offset_table** (soma a base do RDT a cada entrada em `s1+8..s1+0x60`),
  de modo que `offset_table[16]` vira **ponteiro absoluto** para o script. Base do RDT em
  global `0x800cc86c` (gs+0x2134).
- **Jump-table da VM = `0x8009e0f8`** (256 entradas u32). No boot da sala é **copiada para
  o scratchpad `0x1f800000`** (`memcpy` de `0x400` bytes em `0x80052a98`; fonte
  `0x800a0000-0x1f08 = 0x8009e0f8`).
- **Loop principal = `0x80052ba4`** · **DISPATCH = `0x80052c48`**:
  ```
  lw   $v0, 0x1c($s0)        ; PC do script (campo +0x1c do objeto de script)
  lbu  $v0, ($v0)            ; opcode (1 byte)
  sll  $v0, $v0, 2
  lui  $v1, 0x1f80 ; addu ; lw $v0,($v0) ; jalr $v0   ; a0 = objeto de script
  ```
  Retorno do handler: **1 = continua** (re-dispatch) · **2 = fim** (`evt_end` 0x01).
- **Init do PC (gosub/thread start) = `0x80052474`**:
  `PC(obj+0x1c) = script_base + func_offset[id]` (a `func_offset` é a tabela u16 no início
  do script; `script_base = RDT + offset_table[16]`). Bate 1:1 com o cabeçalho de
  ponteiros de função já documentado.
- **Cada handler lê seus operandos do PC e AVANÇA o PC por N bytes** → os tamanhos são
  lidos DIRETAMENTE dos handlers (não mais inferidos por restrição). Opcodes de controle
  (if/while/switch/gosub) escrevem o PC (desvio) em vez de avanço fixo.
- **Validação (round 100% — FECHAMENTO TOTAL):** com os tamanhos relidos byte-a-byte dos
  handlers, **4238/4238 = 100,00%** das funções fecham em `evt_end` e **ZERO** opcodes
  inválidos, nas 169 salas (era 99,95% / 97,1% / 63,6%). Os 5 tamanhos que faltavam
  (`0x3b`=3, `0x3c`=1, `0x24`=1, `0x2f`=1, `0x4b`=1) foram relidos do **epílogo** de cada
  handler (um único `sw PC,0x1c($obj)` + `addiu/addu +N`, um único `jr $ra` → avanço fixo
  incondicional). Detalhe no §"FECHAMENTO 100%" abaixo. Correção anterior: a **"porta de 62B"
  era o PAR `0x67`(22B) + `0x7f`(40B)**; `0x62`=40.

## ⭐⭐ FECHAMENTO 100% — espaço de opcodes + 7 correções + 0x14 resolvido

> Fonte: dump da jump-table `0x8009e0f8` (256 u32) + desassembly de TODOS os 144 handlers +
> re-medição de fechamento nas 169 salas. Integrado em `tools/scd_decode.py`
> (`OPCODE_SPACE`, `OPCODE_SEM`, `SCD_CLOSURE`, `VM_SIZES` corrigido).

1. **Espaço de opcodes = `0x00..0x8f` (144), PROVADO.** A jump-table só tem handler válido
   até `0x8f`; `0x90/0x91` = `0x00000000` (inválido) e `0xc0..0xf1` são a **tabela de bancos
   de flags `0x8009e3f8`** (=`0x8009e0f8`+`0xc0`*4) que fica logo depois e foi copiada junto
   no `memcpy` de `0x400` B. **NÃO existem opcodes ≥0x90** — fecha o antigo item aberto
   "opcodes ≥0x90 raros" (eram sintoma de DRIFT da varredura, não opcodes).
2. **Divergência do `0x14` RESOLVIDA → cabeçalho do switch = 4 bytes.** Handler `0x80053638`
   lê `var(u8)@+1`, `count(u16)@+2` e a **case-table começa em `+4`**. O **4B do reevengi está
   CORRETO**; o "6B" da prosa e o "2" do código estavam errados. Só corrigir `0x14=4` sobe o
   fechamento **97,07% → 99,10%**.
3. **7 tamanhos relidos dos handlers** (os que ainda divergiam): `0x03=4` (`0x80052e78` lê
   `+3`, par do `0x04`), `0x0e=5` (`0x80053228`, PC+5 no continue), `0x14=4` (switch),
   `0x2a=6` (`0x80058918` lê `+4/+5`), `0x31=6` (`0x80055944`), `0x32=6` (`0x800559a0`),
   `0x6e=4` (`0x800556e0`, `addiu +4`). Com os 7 → **4236/4238 = 99,95%**.
4. **FECHAMENTO 100% (4238/4238) — os "2 resíduos" eram DRIFT, não dado-embutido.**
   Os últimos 2 (`R123` func17, `R208` func0) NÃO eram dado-inline/opcode-raro: eram **drift**
   de varredura por **5 tamanhos ainda errados na tabela**, agora relidos do **epílogo** de
   cada handler (cada um: um único `lw PC,0x1c($obj)` + `addiu/addu +N` + `sw`, um único
   `jr $ra` → **avanço fixo incondicional**, verdade do binário):
   - **`0x3b`=3** (era 1) — handler `0x80057f84`, epílogo `0x80058604` (`addiu $v1,$v1,3`).
     Fecha **`R208` func0** (o "opcode raro cujo tamanho não seria isolável" era só tamanho
     errado; o handler é grande mas tem UM só writeback de PC).
   - **`0x3c`=1** (era 2) — handler `0x80057cf8`, epílogo `0x80057db0` (`addu $v1,$v1,$v0=1`).
     Fecha o drift de **`R123` func17**: o byte `0xd3`@+0x2ae que parecia "opcode inválido /
     dado inline" é **coord s16** dentro do operando de um `0x6a` AOT (16 B) — a varredura
     desincronizava por `0x3c=2` e reancorava em +0x2a1 (`47 04 01`+`6a`, idêntico ao `0x6a`
     limpo em +0x06b da MESMA função), terminando em `evt_end` (+0x338).
   - **`0x24`=1** (era 2) — handler `0x80058cd0`, epílogo `0x80058dac`. Fecha `R211` func44
     (`…24|01|00`: com `0x24`=1 o `01` é o `evt_end`).
   - **`0x2f`=1** (era 2) — handler `0x80055004`, epílogo `0x80055018`.
   - **`0x4b`=1** (era 2) — handler `0x80054628`, epílogo `0x800546ac`.
   (Os scans antigos erravam por só rastrear `addiu` — não `addu rt,rt,rN` — no epílogo, e por
   confundir `sw …,0x1c($sp)` [save de `$ra` na pilha] com o PC em `0x1c($obj)`.)
   **Resultado: 4238/4238 = 100% das funções fecham em `evt_end`, ZERO opcodes inválidos, nas
   169 salas.** Não há mais resíduo. Integrado em `tools/scd_decode.py` (`CONTROLE_VM`,
   `VM_SIZES`, `OPCODE_SEM`, `SCD_CLOSURE=(4238,4238)`).
5. **Semântica dos 144 opcodes nomeada** em `OPCODE_SEM` (nome + evidência; `?` = inferido
   pelo call-target, sem `?` = provado no handler). Famílias: fluxo/thread (`0x00-0x04`),
   if/block (`0x06-0x08`), for/while (`0x0d-0x13`,`0x18`,`0x1a`), switch (`0x14-0x17`,`0x1b`),
   gosub (`0x19`), message/janela (`0x2d-0x2f`,`0x5e`), work-var/calc (`0x30-0x32`,`0x40-0x45`),
   inventário/item (`0x36`,`0x3c`,`0x3e`,`0x5f`,`0x6b`), som (`0x55`,`0x57-0x59`,`0x83`,`0x8a`),
   spawn (`0x60`,`0x70-0x73`,`0x7d`), motion (`0x74-0x76`), AOT (`0x61-0x6f`), porta (`0x7f`),
   map (`0x7b`), boss/Nemesis (`0x25`).

### Handlers notáveis (endereço = `*(0x8009e0f8 + op*4)`)
`0x06`→`0x800512fc` (**flag check/set** — MESMO handler do banco de flags `0x8009e3f8`) ·
`0x61`→`0x80055b5c` entidade 32B · `0x62`→`0x80055bbc` entidade 40B ·
`0x63`→`0x80055c34` `sce_aot_set` 20B · `0x64`→`0x80055c94` `aot_4p` 28B ·
`0x67`→`0x800574f4` `door_aot_set` 22B (registra AOT em `gs+0x2158[slot]`) ·
`0x68`→`0x800576c4` `item_aot_set` 30B · `0x7b`→`0x80055568` **map data** (escreve u16 em
`gs+0x7c84[stage][id]`) · `0x7f`→`0x80056510` **door dest/arrival** 40B.

## Correções de arquitetura (confirmadas)

- **`0x8007688c`** = VM de **IA de entidade/inimigo** (não é o script de sala). ✔ confirmado.
- **`0x8009e0bc` / dispatch `0x80050aac`** = **VM de EVENTO/AOT per-frame** (itera a lista
  de AOTs em `gs+0x2158`, dispatch por `SCE type`; opcodes compactos, `0x67`→+6). É a que
  **consome** os AOTs criados pelo script de sala e dispara a troca (seta `gs+0x2154` e a
  flag `0x800c7960`). NÃO é o interpretador de bytecode do SCD — este é o `0x8009e0f8`.

## Tamanhos (bytes, inclui o opcode)

**CONFIRMADO** (âncoras; funções só-de-âncora fecham 144/146):
`00=1 01=1 02=1 04=2 06=4 09=4 0D=6 10=4 12=4 19=2 1E=4 2A=6 40=4 41=4 47=4 48=10 49=4
4C=4 4D=4 50=2 54=4 57=6 58=6 59=8 61=32 62=32 63=20 64=28 65=10 67=62 68=30 70=16 71=18
77=12 78=6 7B=6 7D=24 82=10`
> Correção: `0x67`=**62** (o parser antigo tinha 24, só o head) e `0x68`=**30** (item).

**ALTA** (interseção única por restrição, sem contradição nas 169 salas):
`05=1 07=3 08=1 0C=1 0E=2 0F=1 11=1 13=5 14=6 15=1 16=3 17=1 18=8 1A=2 1B=3 1D=3 1F=3 20=1
21=4 22=1 24=2 25=5 26=7 28=2 2B=45 30=4 32=6 34=12 35=12 37=22 3A=8 3D=9 3E=2 42=10 43=6
44=3 46=13 4E=6 53=6 55=8 56=8 5A=2 5B=6 5C=1 60=10 66=1 6C=2 6E=4 72=1 73=24 74=2 75=2
7A=4 7E=1 7F=28 80=4 81=8 83=4 84=4 87=1 88=4 89=2 8C=2 8E=4`

**INCERTO** (best-fit; faixa não colapsou — podem estar errados; coocorrem sempre com
outros desconhecidos):
`03≈2 0A≈3 0B≈1 1C≈2 23≈2 27≈1 29≈1 2C≈1 2D≈1 2E≈39 2F≈1 31≈3 33≈8 36≈6 38≈9 39≈1 3B≈1
3C≈1 3F≈6 45≈1 4A≈18 4B≈2 4F≈50 51≈2 52≈1 5D≈4 5E≈6 5F≈22 69≈10 6A≈16 6B≈18 6D≈2 6F≈5
76≈3 79≈3 7C≈6 85≈3 86≈4 8A≈2 8B≈1 8D≈1 8F≈4`

### Validação de fechamento (169 salas)
| tabela | funções que fecham | % |
|---|---|---|
| só CONFIRMADO (antigo) | 1303 | 30,8 |
| CONFIRMADO+ALTA (antigo) | 2691 | 63,6 |
| +INCERTO (antigo) | 3119 | 73,7 |
| **`VM_SIZES` (lido dos handlers da VM 0x8009e0f8)** | **4114 / 4238** | **97,1** |

Os tamanhos agora vêm dos AVANÇOS de PC dos handlers (verdade do binário), não de
restrição. O ~3% restante que não fecha vem dos opcodes de CONTROLE (switch/if com desvio
calculado, que a varredura linear não segue) e de alguns opcodes ≥0x90 raros.

## Semântica

- **Posicionamento (confirmado):** `0x63` sce_aot_set (trigger caixa 20B), `0x64`
  aot_set_4p (28B), `0x67` door_aot_set (62B), `0x68` item_aot_set (30B), `0x61/0x62`
  entidade/modelo (32B).
- **Controle de fluxo (confirmado nos handlers):** `0x00` nop, `0x01` evt_end/return,
  `0x02` evt_next, `0x06` **if_begin/block** (u16 block_length), `0x0D` for, `0x10`
  ewhile/while, `0x12` do-while, `0x19` gosub, `0x14` **switch (4B)**, `0x15` case.
  **DIVERGÊNCIA `0x14` RESOLVIDA:** handler `0x80053638` lê `var@+1`+`count(u16)@+2`, case-table
  em `+4` → **cabeçalho = 4B (reevengi está certo)**; corrigido no código (era 2).
- **Agora COM os handlers da VM** (0x8009e0f8), nomes com base no que cada leaf faz:
  - **CORREÇÃO:** `0x06` (4B, handler `0x80052f94`) = **if_begin/block**: empilha
    `(PC+4 + u16@+2)` na pilha de loop `obj+0x140` (fim do bloco). **NÃO é "flag check/set"**
    — o `0x800512fc`/banco `0x8009e3f8` são a lógica de flag do EXE (item_logic), acessada
    por AOT `sce==6` (SCE_FLAG_CHG), não por este opcode. A extração de flags de sala segue
    correta (ancorada em `sce==6`), independente disto.
  - `0x67` (22B) = **door_aot_set** (trigger): registra o AOT da porta em `gs+0x2158[slot]`
    (dados em `PC+2`). `0x7f` (40B) = **par de chegada/dest** da porta (ver abaixo).
  - `0x7b` (6B) = **map data** (escreve `u16@+4` em `gs+0x7c84` indexado por stage/`byte@+3`).
  - `0x61/0x62` entidade, `0x63` sce_aot_set, `0x64` aot_4p, `0x65`, `0x68` item — confirmados
    pelos handlers (tamanhos batem). Demais leaves mapeados por endereço em `scd_decode.py`.

### Porta 0x7f (destino) — encoding investigado, achado NEGATIVO honesto
Handler `0x80056510`: lê `byte@+9` como seletor (`&0xC0`=banco/stage, `&0x3F`=sala) e
`to_x/y/z` em `s16@+0x10/+0x12/+0x14` (chegada; marcador `ff 00 60 10 00` em `+0xb`).
Monta struct runtime em `0x800cea60 + (byte@+1)*0x194`; `struct+0x78` = ptr da sala-destino
(bancos: `0x00`→tabela global `0x80098970`, `0x40`→`gs+0x24ac`, `0x80`→`gs+0x265c[room]`,
`0xC0`→struct local same-stage). O consumidor `door_handler 0x800248e4` lê `descriptor
(gs+0x2154)+8`(=stage `mod 9`)/`+9`(=room, índice interno da tabela de fileids).
**PORÉM**: nos 653 opcodes `0x7f` reais, `byte@+9` é **sempre 0** (banco default). Busca
EXAUSTIVA de reciprocidade sobre TODOS os opcodes/offsets satura em ~15% limpo. Logo o
par (stage,room) destino **NÃO é campo estático do SCD** — é resolvido em runtime (indireção
por door-index + estado do motor). `tools/scd_door_dest.py` documenta e mede isto.

## Flags de progresso (achado do EXE)

- Tabela de **50 ponteiros para bancos de flags** em **`0x8009e3f8`** (ex.: `0x800cc858,
  0x800d1f2c, 0x800ccba0, 0x800d1fa0, ...`).
- Handler **set/check flag** em **`0x800512fc`**: indexa a tabela por id u16, `bit =
  0x80000000 >> (id & 0x1f)`, byte em `(id>>3)&0x1c` — bitset clássico de progresso.
- No `_scd.json` as flags de sala já saem como triggers `SCE_FLAG_CHG` (sce==6) em `flags[]`
  e mensagens em `messages[]` (sce==4). A extração de flags a nível de bytecode (set/check
  dentro das funções) depende de nomear os opcodes de flag do VM de sala (pendente).

---

## Achado do PORT (2026-07-31) — base do salto do `0x07` (else/endif)

> Registrado ao implementar a VM em GDScript (`port/script_vm/vm.gd`, itens P2-01/P2-02).

A prosa desta doc diz, para os dois opcodes de bloco:

- `0x06` if_begin: **push `(PC + 4 + u16@+2)`** na pilha de bloco (`obj+0x140`)
- `0x07` else/endif: pop `0x140`; **`PC += u16@+2`**

Ao portar, li o `0x07` por analogia com o `0x06` (isto é, `PC += 4 + u16@+2`). **Está errado.**
Com o `+4` extra, **87 das 4238 funções** aterrissam fora de instrução — o percurso cai no meio
de um operando e o próximo byte lido não é opcode (ex.: `R101` f0 → `0xf3` no PC 4590).

Com a leitura literal (**base = PC, sem o +4**), as **4238/4238** funções terminam em `evt_end`
em modo de execução, tanto com todas as flags zeradas quanto com todas ligadas.

Ou seja: o `0x06` soma o próprio tamanho ao empilhar o alvo, e o `0x07` **não** — o
deslocamento dele já é relativo ao início da instrução. Vale a pena manter isso explícito
porque a assimetria entre os dois é exatamente o tipo de detalhe que passa por leitura casual.

### Como o port valida o desvio (não só "rodou sem travar")

Rodar o script e não travar **não** prova que o `if` funciona: se o CHECK (`0x4c`) não gateasse
nada, o percurso seria sempre o mesmo e ainda assim terminaria. O teste
(`port/dev/tests/test_scd_vm.gd`) executa as 4238 funções **duas vezes** — com todas as flags
zeradas e com todas ligadas — e mede a diferença:

| medida | valor |
|---|--:|
| funções executadas | 4238 |
| leituras de flag (`0x4c` CHECK) | **2678** |
| escritas de flag (`0x4d` SET/CLEAR) | **2349** |
| funções que tomaram **caminho diferente** conforme as flags | **558** |

558 funções mudando de caminho é a prova de que o gateamento por flag está ativo, e não um
intérprete que apenas anda em linha reta.
