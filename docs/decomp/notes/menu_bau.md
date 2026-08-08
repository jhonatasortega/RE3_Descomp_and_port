# Baú de itens (`sce 9`) e "subir em objeto" (rotina 9)

Duas coisas de gameplay que compartilham o mesmo caminho de investigação (a tabela de despacho de
AOT e a máquina de estados do player). Tudo aqui é lido do `SLUS_009.23` (NTSC-U) e do bytecode em
`port/data/STAGE*/R*.scd`. O que **não** é medido está marcado "declarado" ou "NÃO PROVADO".

Código do port: `port/script_vm/aot.gd`, `port/script_vm/subir.gd`, `port/script_vm/objeto.gd`,
`port/present/menu_bau.gd`, `port/core/game_state.gd`.
Testes: `port/dev/tests/test_bau.gd`, `port/dev/tests/test_subir.gd`.
Diagnósticos: `port/dev/diag_bau.gd`, `port/dev/diag_subir.gd`.

---

## 1. `sce 9` é o BAÚ — e o enum herdado do RE2 estava errado ✅

A tabela de despacho de AOT é `0x8009e0bc`, indexada pelo `sce`, e o AOT em RAM é `script_pc + 2`
(`0x80055c74/78`), logo `AOT+0 == byte +2 do opcode == sce`. Lida do binário, a tabela é:

| `sce` | handler | papel |
|---|---|---|
| 8 | `0x80051388` | **máquina de escrever** — a rotina per-frame `0x800513cc` faz `find_by_id(0x81)` em `0x80051404`, e `0x81` = Ink Ribbon |
| 9 | `0x800514c4` | **BAÚ DE ITENS** |
| 10 | `0x80051684` | overlay de fim (`load_overlay_task(1, 0x0c + n)` = RESULT/SELECT/STAFF_R/TITLE) |

O handler do baú tem 8 instruções e as duas que importam:

```
800514c4  lui   $v1, 0x800e
800514c8  addiu $v0, $zero, 2
800514cc  sb    $v0, 0x1c4($v1)      ; 0x800e01c4 = ctx+0x04 = screen kind da task do menu = 2
800514d0  lui   $v1, 0x800d
800514d4  addiu $v1, $v1, -0x58c8    ; $v1 = gs = 0x800ca738
800514d8  lui   $v0, 0x8005
800514dc  addiu $v0, $v0, 0x14f0
800514e0  sw    $v0, 0x75e0($v1)     ; rotina per-frame = 0x800514f0 (a animação de abrir)
```

`0x800514cc` é o **único** escritor de kind 2 no EXE (varredura de todo `sb/sh/sw ..., 0x1c4(reg)`:
os outros escrevem 0, 1, 4 ou variável). E os subestados do kind 2 (tabela `0x8009f4e4`) percorrem
`inv + 0x28` com limite **64** (`0x80064820  addiu $v0,$v0,0x28`; `slti $v0,$v0,0x40` em
`0x80064b88`, `0x80064bb0`, `0x80064d74`, `0x80064e38`; `addiu $v0,$zero,0x3f` em `0x80064afc`), que
por `exe_items.md §2.1` é exatamente a caixa de itens (MAIN 10 em `+0x00`, BOX 64 em `+0x28`).

Confirmação independente pelo DADO: `sce 8` e `sce 9` aparecem nas **mesmas 16 salas** (15 em
comum; só `R111` tem 8 sem 9, só `R50B` tem 9 sem 8) — máquina de escrever e baú lado a lado na
sala de save, como no jogo.

### 1.1 As 16 salas com baú, medidas

**`port/dev/diag_bau.gd`** monta cada sala na VM (roda todas as funções) e acha **1 AOT de baú em
cada uma das 16**, sempre com `SAT 0x31`, sempre `box`:

| sala | aot | caixa (x, z, w, d) |
|---|---|---|
| R100 | 2 | -28902, -23031, 1940, 2530 |
| R10C | 1 | -23842, -23331, 2410, 1750 |
| R117 | 2 | -15742, -22111, 1940, 1910 |
| R216 | 1 | -23842, -23331, 2410, 1750 |
| R21B | 4 | 14020, 15000, 1600, 2300 |
| R300 | 1 | -15056, -8285, 1870, 2470 |
| R306 | 2 | -26662, -26771, 2350, 1530 |
| R30C | 7 | -19380, -9200, 2700, 800 |
| R310 | 1 | -15056, -8285, 1870, 2470 |
| R312 | 2 | -26662, -26771, 2350, 1530 |
| R401 | 1 | -17919, -26556, 1680, 2240 |
| R403 | 3 | -19812, -19031, 2200, 2380 |
| R413 | 3 | -24441, -24963, 1940, 2530 |
| R501 | 2 | -29002, -24711, 1720, 2460 |
| R505 | 3 | -27722, -20651, 2350, 1640 |
| R50B | 7 | -24882, -17068, 1800, 2210 |

Nenhum `aot_reset` (`0x65`) apaga o baú durante a montagem — os 16 ficam ativos no fim.
A sala de referência do teste é a **R100** (a 1ª sala de save do jogo).

> ⚠ Armadilha registrada: o exportador grava o byte `+3` (o **SAT**) no campo chamado `"floor"`
> do `_scd.json`; o andar de verdade é o byte `+4`. Por isso `floor: 49` = `0x31` = SAT.

### 1.2 Gatilho

`SAT 0x31` = `0x01` (dispara para o player) + `0x10` (**exige o pedido de AÇÃO**) + `0x20` (testa o
**ponto de sonda**, 620 unidades à frente — `0x800505c8  addiu $v0,$zero,0x26c`). O bit `0x40`
(posição do corpo) está APAGADO: encostar de lado ou de costas não abre o baú, é preciso estar de
frente. Isso está travado em teste (`test_bau.gd` bloco 2), com o cuidado de escolher o ponto na
**borda** da caixa — a caixa da R100 tem 2530 de profundidade, então do centro a sonda de 620 ainda
cai dentro dela e o teste não provaria nada.

### 1.3 Transferência

A regra não é inventada: é a da janela de OBTER item (`exe_items.md §2.3`, estado 0 =
`0x80069cb8`), na ordem:

1. **empilhar** — `find_by_id(id)` no destino, aceito só se `qtd + n <= 0x800a0514[id].b1` (o
   máximo por item do descritor);
2. senão **primeiro slot livre** (`find_by_id(0)`);
3. senão **falha** e o item fica onde estava.

Divergência declarada do port: quando o destino tem o mesmo item mas só cabe PARTE, o port move o
que cabe e deixa o resto na origem (`Transf.PARCIAL`) — é o comportamento do stack-merge
`0x8006cf0c`, que clampa em `room = max - qtd`; o "obter" do EXE simplesmente recusa. Sem isso,
mover 60 balas para um baú com 200/250 travaria em vez de mover 50.

Guardar a arma **equipada** desequipa (no EXE a arma equipada é o slot `inv+0x129`, e o baú não é
slot de equipar) — senão `equipped_item_id()` passaria a apontar para o que entrasse no lugar.

### 1.4 A tela

Provado: grade da MÃO 2×5 de 40×30 em (224,66); cursor B146 `(120,0,40,30)` do STMOJIU na paleta 3
com a piscada de `ctx+0x22` (±2, clamp `0x3f`); painel grande B142 = 200×136 em (12,84) — o mesmo
do kind 3 (ARQUIVO), porque kind 2 e kind 3 são telas da MESMA task; paginação por L1/R1
(`raw_held & 0xc`).

**Declarado, NÃO PROVADO**: a grade do baú DENTRO do B142 (5×4 de 40×30 a partir de (12,92), 20
slots por página, 4 páginas para 64). O sítio de desenho do EXE grava `u,v,clut,w,h` e não a
posição, então isto é geometria derivada de um painel provado. Os rótulos ("BAÚ", "MÃO", "SAIR")
são texto em PT-BR com a fonte do jogo: os originais são sprites do `STMOJIU` e o atlas HD
disponível só tem inglês e russo.

### 1.5 Correção de fundo achada aqui: **50 bancos de flags, não 16**

Rodar as salas de save fez o `CHECK 0x4c` gritar `banco de flag inválido: 39/47/48`. A tabela
`0x8009e3f8` tem **50** ponteiros, não 16 — lidos do binário, as 50 entradas são RAM válida
(`0x800cc858`, `0x800d1f2c`, `0x800ccba0`, `0x800d1fa0`, `0x800d1fc0`, `0x800d1fc8`, `0x800d1fe8`,
`0x800d2008`, `0x800d2028`, `0x800d20cc`, depois `0x800d204c..0x800d20c8` de 4 em 4, e no fim
`0x800cc854`, `0x800dbb58`, `0x800ccbac`, `0x800d20d4`, `0x800d2048`, `0x800d258c`, `0x800d25ac`,
`0x800d1f30`) e a **entrada 50 é `0x5b2a5a59`**, que não é endereço — a tabela acaba ali. Bate com o
que `scd_opcodes.md` já dizia ("tabela de 50 ponteiros para bancos de flags"). Com 16, todo `if` de
script que usasse os bancos 39/47/48 virava `false` em silêncio. Corrigido em
`GameState.N_BANKS = 50`.

🟡 Divergência declarada: os bancos do EXE **não têm tamanho uniforme** (os ponteiros 11..41 estão a
4 bytes um do outro = 1 word cada; os 3..10 a `0x20` = 8 words). O port aloca 8 words para todos —
superconjunto seguro, porque o `& 0x1c` do EXE satura o índice de word em 7; o único efeito é que
bits altos de um banco pequeno não transbordam para o vizinho como transbordariam no PS1.

---

## 2. O AOT do R10D é `evt_exec(func 11)` — e **não** é o "subir" ✅

O `R10D.scd` tem 49 funções e **um** AOT, na função 5, offset `0x0122`:

```
63 01 05 41 00 00 | 77 de 68 c5 e4 0c 74 0e | ff 00 19 0b 00 00
op aot sce sat fl -  x=-8585 z=-15000 w=3300 d=3700   payload
```

`sce 5` → handler `0x800512bc`, lido inteiro:

```
800512c4  lw   $v0, 0x800ccba0        ; se & 0x02000000 -> return
800512dc  lhu  $a0, ($a1)             ; u16@payload+0 = 0x00ff = 255  (slot de thread: qualquer livre)
800512e0  lbu  $a1, 3($a1)            ; u8@payload+3  = 11            (índice da função)
800512e4  jal  0x80052478             ; -> 0x8005242c: PC = script_base + u16[func]
```

Ou seja o payload é o MESMO descritor do opcode `0x04` (`evt_exec`): **thread livre + função 11**.
Nada de animação, nada de player.

A **função 11** (offset 1570 do bytecode, 250 B) é uma CENA: `65 aot_reset`, `4d` flag set,
`19 0d/0e/0f/16..19/1a/20..25` (gosubs), `0a` yields, `55/56` som, `46` câmera, `40` var,
`04 ff 19 xx` (novas threads), `10/11` while/break, `01` no fim — e **nenhum** opcode de animação
de player (`0x74`/`0x75`/`0x76`). A primeira coisa que ela faz é `65 01` (offset `0x0624`): a cena
**apaga o próprio gatilho**, que é o que faz o evento acontecer uma só vez.

Além disso a caixa `x[-8585..-5285] z[-15000..-11300]` **não contém** a posição da captura do dono
(`x=-3678, z=-12960`, que fica a LESTE dela). Os dois fatos estão travados em `test_subir.gd`.

---

## 3. "SUBIR EM OBJETO" = rotina 9, e o objeto escalável **sai do dado estático** ✅

### 3.1 A cadeia, sítio por sítio

**a) Laço per-frame de objetos** — `0x8003650c..0x8003654c`: percorre o pool de **32** entradas de
404 B a partir de `gs+0x4328` (= `0x800cea60`) com passo `0x194`, até o ponteiro de fim guardado em
`gs+0x75a8` (`lw $v0, 0x75a8($s1)`; `(0x75a8-0x4328)/0x194 = 32`) e despacha por `lbu 4($s0)` na
tabela `0x8009cc64` (6 entradas válidas). O handler do `0x7f` (`0x80056510`) monta a entrada
exatamente em `gs + 0x4328 + slot*0x194` e `0x8003580c  sw $zero, 4($s1)` zera o seletor — logo
objeto de cenário cai sempre na **entrada 0 = `0x80036c60`**.

**b) Detector de contato** — `0x80036c60`:

```
80036c74  lw   $v0, ($s0)          ; entry+0 & 1 (visível) -> senão return
80036c88  lbu  $v1, 0x2491($a0)    ; rotina do player; se != 1 e != 9 -> entry+0xc0 = 0
80036ca4  lhu  $v0, 0xae($s0) ; andi 0x10   ; \ porta de RUNTIME
80036cb8  lhu  $v0, 0xba($s0) ; andi 0x8000 ; /
80036ccc  lw   0x800dd4ac ; +1                ; conta quantos objetos em contato
80036cf0  ...  if (player+9 == entry+9) 0x800dd4b0 = entry    ; mesmo piso
```

**c) 6 quadros de contato → acende a flag** — `0x80036570`, chamada uma vez por quadro em
`0x80036550`, logo depois do laço:

```
8003657c  if (*0x800dd4ac != 1) return
8003658c  obj = *0x800dd4b0 ; if (!obj) return
80036594  lw   $v1, ($obj)         ; entry+0 = be_flg
8003659c  andi 0x4000 ; bnez -> return      ; bit 0x4000 ACESO  = NÃO escalável
800365a4  andi 0x100  ; beqz -> return      ; bit 0x100 APAGADO = NÃO escalável
800365c8  if (++entry+0xc0 < 6) { restaura X/Z ; return }
800365dc  if (entry+0xae & 0x20) { entry+0xc0 = 0 ; restaura X/Z ; return }
800365fc  ori $v0,$v0,0x10 ; sw 0x77f4($gs)  ; gs+0x77f4 (= 0x800d1f2c) |= 0x10   ★
```

`0x800365fc` é o **único** sítio que acende esse bit, e ele é APAGADO no começo de todo quadro em
`0x800364f8..0x80036508` (`addiu $v1,$zero,-0x11; and; sw`) junto com `0x800dd4ac`/`0x800dd4b0` — a
flag é RECALCULADA por quadro, não é estado persistente.

**d) A flag entra na rotina 9** — no fim de r1 (andar para frente) e de r2 (ré):

```
800397b0  lw    $v0, 0x1f2c($v0)
800397b8  andi  $v0, $v0, 0x10
800397c0  addiu $v0, $zero, 0x901
800397c4  sw    $v0, 4($s0)        ; player+4 = ação 1 | rotina 9   ★
80039b58..80039b6c                 ; idêntico em r2
```

**e) O outro consumidor da flag: a COLISÃO.** No laço entidade↔entidade, o caminho que EMPURRA o
personagem para fora do obstáculo (`0x80035130`: `entry+0x2e |= 0x100`) é **pulado** quando
coincidem `entry+2 == 0` (`0x800350e0`), o obstáculo tem o bit `0x100` (`0x800350ec  andi $a3,0x100`,
`$a3` = flags do outro corpo), `gs+0x77f4 & 0x10` aceso (`0x800350f8`), `player+0x12d == 0`
(`0x8003510c`) e `(player+0xba & 0x7fff) == 0` (`0x8003511c`). Isto é: **a flag desliga a parede
daquele obstáculo** — é por isso que a animação consegue levar a Jill para cima em vez de esbarrar.
Repare que é o **mesmo bit `0x100`** do `be_flg` de 3.2.

### 3.2 O achado: `be_flg` marca o objeto escalável, e é DADO ESTÁTICO ✅

O handler do `0x7f` faz `entry+0 = (u16@+0x0c) | 1` (`0x800565cc..0x800565d8`). Como `0x80036570`
usa os bits `0x100` e `0x4000` desse mesmo `entry+0`, **a lista dos objetos escaláveis do jogo é uma
varredura do bytecode**. Varredura dos **674** opcodes `0x7f` do jogo: passam **11 declarações /
7 objetos distintos** em **5 salas**, todos com `be_flg` `0x0101` ou `0x0301`:

| sala | função | slot | `be_flg` | posição (x, y, z) |
|---|---|---|---|---|
| R210 | 0 | 5 | 0x0301 | -14000, 0, -20975 |
| R210 | 0 | 5 | 0x0301 | -21720, 0, -21035 |
| R219 | 0 | 3 | 0x0301 | -21720, 0, -21035 |
| R315 | 13 | 7 | 0x0101 | -27589, 0, -23328 |
| R406 | 17 | 0 | 0x0101 | -23690, 900, -25131 (declarado 4×) |
| R50D | 17 | 0 | 0x0101 | -18946, 0, -15456 |
| R50D | 17 | 1 | 0x0101 | -7974, 0, -8467 |
| R50D | 17 | 2 | 0x0101 | 102, 0, -24937 |

Distribuição completa de `be_flg` nos 674: `0x6001`×558, `0x0001`×31, `0x6011`×29, `0x8001`×28,
`0x0101`×8, `0xe001`×7, `0x4001`×4, `0x6041`×3, `0x0301`×3, `0xa001`×3.

Montando as 169 salas na VM (que é o que o port faz de verdade), sobram **4 salas**: R210, R219,
R315 e R50D (com 3). O R406 declara o objeto escalável num RAMO da função 17 e reescreve o mesmo
slot 0 com `be_flg = 0x0001` no fim da função — quem roda todas as funções em ordem vê o último.

### 3.3 Conclusão sobre o R10D: **não existe lixeira escalável lá** (negativa provada)

O R10D tem 3 objetos `0x7f` (função 4, slots 0/1/2) e **os três têm `be_flg = 0x6001`**: bit
`0x4000` aceso E bit `0x100` apagado, reprovando nos dois testes de `0x80036570`. Somando:

* nenhum objeto do R10D é escalável pelo critério do próprio motor;
* nenhum deles fica perto da captura do dono (`x=-3678, z=-12960`) — eles estão em
  `(11844,-180,-9306)`, `(15408,-180,-9306)` e `(-14550,0,-12625)`;
* o único AOT da sala é uma cena (§2), e a caixa dele nem contém a posição da captura.

Logo o port **não inventa** o ponto: `SubirObjeto.carregar_sala("R10D")` devolve 0. Quem quiser
forçar usa `adicionar_ponto()` explicitamente.

### 3.4 A animação: sequências 6 e 7 ✅

r9 é o par `move 0x8003b1c4` + `anim 0x8003b244`. O `anim` despacha por `player+6` numa tabela de
**8** subestados em `0x800107d0`, e os `player+0xc8` que ele escreve são:

```
8003b38c  lui $v1,7 ; ori $v1,6 ; sb 3,6($s0) ; sw $v1,0xc8($s0)   -> SEQ 6  (sub 2)
8003b3b4  lui $v1,7 ; ori $v1,7 ; sb 5,6($s0) ; sw $v1,0xc8($s0)   -> SEQ 7  (sub 4)
8003b20c  sb 6,0xc8 ; sb 0,0xc9 ; sb 7,0xca                        -> o mesmo 0x00070006 (r9 move)
```

(o `+0xca = 7` é a constante `0x0007<<16` que TODA a máquina escreve junto do índice — não é um
terceiro índice de animação.)

Subestados de `player+6` na rotina 9, um a um:

| sub | endereço | o que faz |
|---|---|---|
| 0 | `0x8003b294` | `sub = 1`, anim = linha do ANDAR (`0x8009cde0 + 3`), `gs+0x77f4 |= 0x100` |
| 1 | `0x8003b2d8` | andar/alinhar (`0x800776b0`, `0x80027940` com `a3=0x200`); `0x6e & 0x3e0 == 0` → `sub = 2` |
| 2 | `0x8003b38c` | `sub = 3` e **SEQ 6** |
| 3 | `0x8003b3a0` | avança a SEQ 6 |
| 4 | `0x8003b3b4` | `sub = 5` e **SEQ 7** |
| 5 | `0x8003b3c8` | roda a SEQ 7; se `player+0xc9 == 1` toca SFX `0x1022c` (`0x800746c0`) e a vibração (`0x80038678(2,0)`, `0x80038704(3,0x96,0)`, `0x8003879c(0x14,0x96,0,3)`) = o impacto de pousar |
| 6 | `0x8003b494` | avança com `a3 = 0x10200` e soma o retorno em `player+6` |
| 7 | `0x8003b4c4` | `gs+0x77f4 &= ~0x100` e `player+4 = 1` → volta para on-foot |

O `move` só age no `sub == 5`: se o pad de direção está SEGURADO **e** a flag `0x10` continua
acesa, ele NÃO avança (o "segurar para continuar"); senão põe `sub = 6` com SFX `0x10200`
(`0x8003b224`).

> ⚠ **Correção a `docs/formatos/animacoes_player.md`**: a tabela das 22 seqs rotula a 06 como
> "Passo curto virando" (confiança média) e a 07 como "Postura dinâmica (+X)" (baixa), ambos por
> render. O papel real das duas está provado aqui: são o par **subir/descer em objeto** da rotina 9.
> A pendência "validar 'subir em item'" do STATUS daquele doc fecha.

🟡 **NÃO PROVADO qual banco de EDD**: o dispatcher `0x80038c7c` passa `a1 = player+0xe8`,
`a2 = player+0xec` (o banco default) e r9 repassa os dois a `0x80027940` sem trocar de ponteiro;
como a base é escolhida em runtime pela arma equipada, com arma na mão o índice 6/7 cai no PLW. O
port usa `anim06`/`anim07` por padrão (`SubirObjeto.CLIPES`), trocável numa linha para
`arm06`/`arm07`.

### 3.5 O que continua NÃO PROVADO

* **De onde vêm `entry+0xae & 0x10` e `entry+0xba & 0x8000`** (a porta de RUNTIME de
  `0x80036c60`). O handler do `0x7f` (`0x80056510`, lido inteiro) escreve `entry+0`, `+9`, `+0xd`,
  `+0x10`, `+0x14`, `+0x34/38/3c` (X/Y/Z), `+0x46`, `+0x4a`, `+0x6c/6e/70` (rotação), `+0x78`,
  `+0x9a/9c/9e`, `+0xa4/a6/a8`, `+0xc2` (id de modelo) e `+0xc8` — **não** escreve `+0xae` nem
  `+0xba`; nem o `0x80035790` que ele chama. A varredura de todo `sb`/`sh` com offset literal
  `0xae`/`0xba` no EXE só acha escritores do player (`0x8004b7c4`, `|= 0x480`), do menu
  (`0x8006exxx`) e de personagens (`0x8001dxxx`), e não há `sw` para `+0xac`/`+0xb8` que os cubra
  de raspão. Pode ser cópia em bloco de dado do RDT. **Limitação da varredura**: ela só vê offsets
  literais; um `addiu base` seguido de `sh` com offset pequeno escaparia.
  Para a pergunta prática isso não muda nada: a porta ESTÁTICA já é decisiva e já exclui o R10D.
* **A extensão e a altura do objeto escalável.** O descritor de 40 B do `0x7f` tem posição e
  rotação, **não tem escala nem caixa**; a extensão real vem da malha MD1 do RDT
  (`offset_table[10]`) e a altura do topo, do piso de destino. No port as duas são constantes
  declaradas (`SubirObjeto.RAIO_DECLARADO = 620`, igual à sonda de ação do motor, e
  `ALTURA_DECLARADA = 1800`).
