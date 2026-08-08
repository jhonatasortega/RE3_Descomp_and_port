# A cena de ENTRADA do `R101` — e o `0x4c` que a mantinha escondida

> **O pedido do dono, literal:** *"no fim da cena final, ao ir para a próxima sala, tem uma cena
> de entrada"*. Tem: ao chegar no `R101` vindo do `R10D`, o init da sala abre a **função 3** do
> `R101.scd` como thread, e ela é uma cinemática de **1362 quadros ≈ 45 s** — a mais longa que o
> port roda hoje. Antes deste round o port chegava no `R101` e caía direto em gameplay.
>
> **Código:** [`port/room/world.gd`](../../../port/room/world.gd) (`CENAS_LIGADAS`,
> `_abrir_cena_de_entrada`, `_chegada_emprestada`) ·
> [`port/script_vm/vm.gd`](../../../port/script_vm/vm.gd) (`0x4c` corrigido, `threads_pedidas`) ·
> [`port/script_vm/cena.gd`](../../../port/script_vm/cena.gd) (`atores_externos`).
> **Sondas:** `port/dev/diag_cena_r101.gd` (bytecode → linha do tempo) e
> `port/dev/diag_cena_r101_jogo.gd` (**pelo caminho real**: `game.tscn` → `Clock` → `Screen._on_tick`
> → `World.tick`, lendo o `AnimationPlayer` por quadro).
> **Teste:** `port/dev/tests/test_cena_r101.gd`, no filtro `-- cena`.
>
> O mecanismo de cena em si está em [`cena_r10d.md`](cena_r10d.md); este doc só cobre o que é novo.

---

## 1. A resposta curta

| pergunta | resposta | prova |
|---|---|---|
| qual é a cena de entrada do `R101`? | **função 3** (337 instruções) | §2 |
| quem a dispara? | o **init**, `func 0 @+0x0246` = `04 ff 19 03` | §2 |
| roda sempre? | **não** — só na 1ª visita, gate `4c 03 0b 00` + `4d 03 0b 01` | §2 |
| é FMV? | **não** — nenhum `0x7a` no `R101` | varredura de `scd_decode.py` |
| quanto dura? | **1362 quadros ≈ 45 s** no caminho do jogo (1565 no harness) | §4 |
| ela posiciona o player? | **não em X/Z**; declara o **ANDAR** (`40 0f 02 00`) | §3 |
| quita o débito da chegada zerada? | **não**, mas o **estreita** — ver §3 | §3 |

---

## 2. ⭐ O `0x4c` estava com a POLARIDADE INVERTIDA (e isso valia para as 169 salas)

O `04 ff 19 03` da função 0 mora dentro de um `if` de flag:

```
func 0 @+0x01d4  06 00 76 00              if_begin, else em +0x024e
       @+0x01d8  4c 03 0b 00              CHECK banco 3 bit 0x0b
       …          7d/7f/7f …              o cenário da 1ª visita
       @+0x0246  04 ff 19 03           ★  evt_exec(slot 0xff, FUNÇÃO 3)
```

e o **primeiro ato da função 3** é `4d 03 0b 01` — acender essa mesma flag. Só fecha de um jeito:
`4c 03 0b 00` tem de significar **"a flag AINDA NÃO subiu"**. O handler confirma, instrução por
instrução (`0x800546cc`):

```
800546d8  lhu   $a1, 2($v0)      ; a1 = u16@+2
800546fc  andi  $a2, $a1, 0x1f   ; bit dentro da palavra
8005470c  sra   $a1, $a1, 8      ; a1 = BYTE ALTO
80054718  sltiu $a1, $a1, 1      ; a1 = (byte alto == 0)
80054720  sltu  $v0, $zero, $v0  ; v0 = (palavra & mask) != 0
80054724  jr    $ra
80054728  xor   $v0, $v0, $a1    ; ★ resultado = flag XOR (byte alto == 0)
```

➜ **byte alto 0 ⇒ condição NEGADA; byte alto != 0 ⇒ condição direta.** O port fazia o contrário
(`negar = byte alto != 0`), isto é **trocava o ramo de todo `if` de flag de todo init de sala**.
O `_avaliar_condicao()` do `while`, no mesmo arquivo, já estava certo — as duas discordavam entre si.

E o dispatch fecha o resto: `0x80052c78` re-despacha com retorno 1 e, com retorno **0**
(`0x80052ca4`), desempilha `obj+0x140` e escreve o alvo no PC = o `else` do `0x06`.

### 2.1 Três confirmações independentes da correção

1. **Item de chão.** `R101 func 0 @+0x00d8` = `4c 07 1f 00` (byte alto 0) e o `0x67` seguinte
   declara o item com `payload+4 = 0x1f`. Banco 7 é o de itens pegos (`GameState.BANCO_ITENS`).
   Só faz sentido como "**ainda não** peguei" → instala o item.
2. **O oposto, na mesma sala.** `R101 func 15 @+0x002e` = `4c 07 1f 01` (byte alto 1) e o ramo
   verdadeiro faz `65 0c` (aot_reset) + re-spawn: "o item **já** foi pego".
3. **`R102`.** O gatilho `sce 5` do `R102` (`func 7 @+0x0036`) mora atrás de `4c 03 4a 01` (byte
   alto 1 = direta): **numa partida nova ele não existe**. O port antigo o instalava, e o
   `test_cena_world.gd` cobrava esse artefato.

### 2.2 O alcance da correção, medido

Suíte inteira depois do conserto: **5 asserts mudaram de valor**, todos explicados por dado
(`test_subir.gd` §2/§3 e `test_world.gd`). Nada mais. As 453 travessias do `-- world` seguem verdes.

- **`R406` entrou** na lista de salas com objeto escalável: `func 17` = `if (4c 03 75 00)`
  (negado) → ramo com `om 0` em `(-23690, 900, -25131)` e `be_flg = 0x0100`.
- **`R315` saiu**: `func 13` = `if (4c 03 7e 01)` (direta) e `func 0 @+0x000c` acende `3/0x7e`
  antes do `19 0d` → vale o ramo de `be_flg = 0x8000`. 🟡 Com um asterisco: esse `4d` está dentro
  de `if (4e …)` e o **`0x4e` é condição que o port não avalia** (entra por omissão). Quando o
  `0x4e` for medido, o `R315` pode voltar.

### 2.3 A cena passou a ser DESCOBERTA, não configurada

O `0x03`/`0x04` (`evt_exec`) no modo de CARGA agora **registra** o pedido em
`ScriptVM.threads_pedidas` (o PC anda os mesmos 4 bytes; nada mais mudou). Como a lista já passou
pelos `if`/`0x4c` do init, ela é a resposta certa **para esta partida**:

```
R101 — init (executar(0))
  13 AOTs · 3 objetos · 6 flags lidos
  THREADS que o init pediu (0x04 evt_exec): [{ "slot": 255, "func": 3 }]
```

Um único pedido, e é a cena. `World._abrir_cena_de_entrada()` cruza essa lista com
`CENAS_LIGADAS` — que continua sendo o **freio** (só roda o que está medido) — e imprime o que
ignorou. No `R10D` a lista traz `{255, 7}` (a cena) e `{5, 41}` (a thread de ambiente da rua, §7-6
de `cena_r10d.md`), e só a 7 é autorizada.

---

## 3. A CHEGADA — o débito não foi quitado, mas foi ESTREITADO

`cena_r10d.md` §4.2/§9.2-5: a porta roteirizada `R10D → R101` vem com **caixa `(0,0,0,0)` e
chegada `(0,0,0)`** (a única do jogo), e o port **empresta** a chegada de outra porta que entra no
`R101`, etiquetando a dívida. A pergunta deste round era se a cena de entrada quita isso.

**Não quita.** Varri as 19 funções do `R101`: **nenhum `0x40`/`0x41` nos membros `0x09`/`0x0b`
(X/Z) do work `1:0`**. A cena não escreve posição absoluta do player em nenhum momento — o mesmo
padrão do `R10D`.

**Mas ela declara o ANDAR**, e isso é medição nova:

```
func 3 @+0x0048  47 01 00        work = PLAYER (tabela 0x80010b60 entrada 1, n=0)
       @+0x005c  40 0f 02 00  ★  membro 0x0f = player+0x09 = 2
```

`player+0x09` é o byte que o passe de piso grava com `-Y/1800` e que o RVD usa como grupo
(`gs+0x2495` = `0x800CCBCD`, já registrado em `world.gd`). **Nível 2 ⇒ y = −3600.** E as duas
coordenadas que a cena dá ao player pelo `0x81` ficam nessa mesma região:

```
func 3 @+0x0142  81 00 04 01 4a de d6 93   ir até (-8630, -27690)
       @+0x014e  81 00 04 01 0d cb e6 a6   ir até (-13555, -22810)
```

Das três portas medidas que entram no `R101`, os `to_y` são:

| origem | chegada | nível |
|---|---|---|
| `R100` | `(-18808, -7200, -11475)` cam 6 | 4 |
| `R102` | `(-4434, -3600, -27933)` cam 7 | **2** |
| `R11D` | `(-4345, -3600, -28176)` cam 7 | **2** |

O empréstimo era feito por **ordem alfabética da sala de origem**, o que dava o `R100` — nível 4,
a ~16 mil unidades de onde a coreografia começa. Agora `_chegada_emprestada()` filtra primeiro
pelo andar que a cena declara e sobra o `R102`: **`(-4434, −3600, −27933)`**, câmera 7 — a mesma
vizinhança do primeiro `0x81`.

🟡 Continua **DECLARADO**: é ponto medido de *outra* porta. O mecanismo real da chegada zerada
(grupo do RVD, `descriptor+0xb`) **segue não medido**, e a dívida segue registrada em
`world.cena_debitos`.

---

## 4. A linha do tempo (medida, e pelos DOIS caminhos)

### 4.1 No harness (`diag_cena_r101.gd`) — 1565 quadros

```
q    0  thread slot 0 func 3            · q 2 thread slot 2 func 11 (o fade de 1 tick em laço)
q   55  fade abr=2 branco→preto T=40    · cut_chg 24
q   56  player SEQ 25
q   85  cut_chg 10 · player SEQ 2 (rotina 2) · entidade 0 SEQ 2
q  276  player SEQ 22
q  288  cut_chg 25 · q 294 player -> (-8630,-27690) · q 339 player -> (-13555,-22810)
q  389  cut_chg 26 · thread func 5 (entidade)
q  638  o player CHEGA (bit 1 do banco 4)
q  652  thread func 6 · cut_chg 25 · q 821/823 cut_chg 26/27
q  824  threads func 7 e 8 · a ENTIDADE vai a (-4290,-17550)
q 1058  a entidade chega · q 1059 cut_chg 21 · q 1092 cut_chg 19
q 1102  entidade -> (2048,96) · q 1343 chega · q 1399 -> (3968,100) · q 1423 chega
q 1452  thread func 9 · q 1475 cut_chg 17 · q 1495 cut_chg 10
q 1565  thread func 13 (devolve o controle: `4d 02 07 00` / `4d 01 1c 00` no fim da 3)
```

Câmeras: `24 → 10 → 25 → 26 → 25 → 26 → 27 → 21 → 19 → 17 → 10`.

### 4.2 ⭐ Pelo caminho REAL do jogo (`diag_cena_r101_jogo.gd`) — 1362 quadros

Este é o teste que faltou no round anterior: `game.tscn` → `Clock` do autoload `Game` →
`Screen._on_tick` → `World.tick`, com o `AnimationPlayer` lido a cada quadro.

```
[world] R10D: CENA função 7 ligada · terminou em 260 quadros
[world] R10D: CENA função 11 ligada — gatilho sce 5 (AOT 1)
[world] R101: CENA função 3 ligada — thread do init (`04 ff 19 03`)
[r101] ★ entrou no R101 · pos=(-4434,-3600,-27933) cam=7 cena_func=3
[world] R101: cena função 3 terminou em 1362 quadros
[r101] câmeras vistas na tela: [7, 24, 10, 25, 26, 27, 21, 19, 17]
[r101] clipes que o AnimationPlayer tocou: [arm02, anim02, arm00, anim19, anim16, anim17, anim01]
[r101] player: (-4434,-3600,-27933) -> (-13555,-1800,-22810) · cam final=10 · ação=0
```

**Anima, troca de câmera e devolve o controle.** A diferença 1565 → 1362 é o `0x81`: no harness a
`Cena` simula o deslocamento; no jogo quem anda é o `player.gd` (mais rápido que a
`VELOCIDADE_DECLARADA` na primeira perna).

### 4.3 ⚠ ACHADO — a cena travava no jogo por causa de um `0x81` de ENTIDADE

Na primeira ligação a cinemática **não terminava**: `cena função 3 abandonada em 4000 quadros
(rede de segurança)`. Causa:

```
func 3 @+0x0290  47 03 00                  work = ENTIDADE 0
       @+0x0294  81 00 09 01 3e ef 72 bb    ir até (-4290,-17550), bit 1
       @+0x029c  10 04 08 00 / 4c 04 01 00  while (NÃO flag(4,1)) { yield }
```

O `world.gd` punha `cena.simular_movimento = false` porque quem anda com o **player** é o
`player.gd`. Só que isso desligava a simulação de **todos** os atores — e a função 3 espera a
**entidade** chegar. No `R10D` passou batido (nenhuma thread lá espera bit de entidade).

Conserto: `Cena.atores_externos` — o `world.gd` marca só `"1:0"` (o player) como dirigido de fora,
e a `Cena` volta a mover os outros works com a `VELOCIDADE_DECLARADA` (que já era declarada). É a
diferença entre 4000-e-desiste e 1362-e-termina.

---

## 5. O que NÃO está ligado no `R101`

Os **dois gatilhos `sce 5`** da sala, os dois com `nFloor = 1`:

```
aot 11  caixa x[-8400..-6600] z[-13760..-9360]   -> função 12
aot 12  caixa x[-26660..-24660] z[-11340..-9540] -> função 15
```

Ficam inertes (`CENAS_LIGADAS["R101"].gatilhos == []`), e nenhum dos dois é necessário para
progredir: a função 12 só faz `0x81` com rotinas não decodificadas, e o `66 07` da função 15
dispara o **AOT 7**, que é `sce 2` — **não é porta**. O port imprime qual função ignorou.

---

## 6. EM ABERTO depois deste round

1. **A chegada da porta roteirizada** segue emprestada (§3). O que falta é o grupo do RVD
   (`descriptor+0xb`).
2. **Opcodes que a função 3 usa e o port só anda o PC**: `0x82` (10 B, e é o mais frequente da
   cena — handler `0x8005709c`: escreve modos em `w+0x120` pela jump-table `0x80010c68` e
   `s16@+2/+4/+6/+8` em `w+0x164`/`w+0x166`…, é a interpolação de pose/rumo), `0x79`
   (`0x800554c8` → `0x80011df4`, e acende `gs+0x77f4 |= 0x20`), `0x5b` (`0x80054d74` →
   `0x8002fd30`, forte candidato a FALA/legenda: 11 disparos na cena, ids 7..0x11), `0x0b`/`0x0c`
   (`0x800530f8`/`0x8005312c` — o `0x0c` testa `0x800d1f2c & 0x20`, tem cara de **pular
   cinemática**), `0x77`, `0x78`, `0x87`, `0x89`, `0x52`, `0x53`, `0x22`.
3. **As SEQ que a cena pede e o banco não tem.** Ela manda `SEQ 22, 24, 25` no player, e o banco
   `animNN` do `PL00.PLD` só vai até **21**: a apresentação não toca clipe nesses trechos (o
   `screen.gd` checa `has_animation`). Ou o índice é de outro banco (PLW), ou o de-para
   `anim%02d` está errado para cena. **NÃO PROVADO.**
4. **`0x4e`** continua sem semântica, e ele decide o `R315` (§2.2).
5. **Fade e som da cena** seguem só registrados (`cena.fade_ativo`, `vm.sons`) — é
   `port/present/screen.gd`, que não é deste round.
