# As duas cinemáticas do `R10D` — e por que a sala não tinha saída

> **O que este doc fecha.** Três itens que estavam abertos ao mesmo tempo e são **um só
> problema**: (1) "faltam as cutscenes de entrada e saída do `R10D`"
> ([`boot_ptbr_hd.md`](boot_ptbr_hd.md) §8.7, §9.2, §9-15, §9-16), (2) "não consigo sair da
> primeira sala" e (3) "a Jill sobe na lixeira" ([`menu_bau.md`](menu_bau.md) §2/§3.3,
> [`subir.gd`](../../../port/script_vm/subir.gd)).
>
> **As três respostas são a mesma função de script.** A saída do `R10D` **é** a cinemática, e
> o subir está **dentro** dela.
>
> **Código:** [`port/script_vm/cena.gd`](../../../port/script_vm/cena.gd) (novo) +
> os opcodes de cena em [`port/script_vm/vm.gd`](../../../port/script_vm/vm.gd).
> **Teste:** `port/dev/tests/test_cena.gd` (108 asserts).
> **Sonda:** `port/dev/dump_cena.gd` (imprime a linha do tempo).
> **Tabela de opcodes:** `tools/scd_decode.py` (`OPCODE_SEM`) → `port/data/scd_opcodes.json`.

---

## 1. A resposta curta

| pergunta | resposta | onde está a prova |
|---|---|---|
| cutscene de ENTRADA | **função 7** do `R10D.scd`, thread aberta no init da sala | §2 |
| cutscene de SAÍDA | **função 11**, thread aberta pelo AOT `sce 5` | §2 |
| é FMV? | **não** — `R10D` não tem opcode `0x7a` (49 funções varridas) | `boot_ptbr_hd.md` §7.2 |
| existe `R10D_2`? | **não**; e não precisa: as duas cenas moram no mesmo SCD | §2 |
| como se sai da sala? | a função 11 dispara a porta **pelo opcode `0x66`** | §4 |
| a Jill sobe na lixeira? | **sim, e é o script que faz** — `0x80` + translação manual | §6 |
| existe objeto escalável no `R10D`? | **não**, e a conclusão de `subir.gd` continua certa | §6 |

---

## 2. O caminho, do carregamento da sala até as duas threads

`world.gd` roda `executar(0)` — que é o que o motor faz. O percurso é este, opcode por opcode:

```
func 0  @+0x062   5a 00 · 19 02 (gosub 2) · 04 05 19 29 (thread slot 5, func 41) · 01
func 2  @+0x070   19 03 (gosub 3) · 19 04 (gosub 4) · 19 05 (gosub 5) · 04 04 19 06 · 19 26 · …
func 3  @+0x082   61 00 01 21 00 00 …  = AOT 0, sce 1 = PORTA, caixa (0,0,0,0)
func 4  @+0x0a4   3× 0x7f = os objetos de cenário
func 5  @+0x11e   04 ff 19 07                       ➜ THREAD da função  7  (CENA DE ENTRADA)
                  63 01 05 41 00 00 77 de 68 c5 e4 0c 74 0e | ff 00 19 0b 00 00
                  = AOT 1, sce 5, caixa x[-8585..-5285] z[-15000..-11300],
                    payload = evt_exec(slot 0xff, função 11)  ➜ CENA DE SAÍDA
```

- `0x04` = `evt_exec` (`0x80052ea4`): `slot = byte@+1` (`0xff` = qualquer livre, 2..9),
  `função = byte@+3`. O PC inicial sai de `0x80052474`.
- `sce 5` = handler **`0x800512bc`** (jump-table de SCE `0x8009e0bc`): lê `u16@+0` (slot) e
  `u8@+3` (função) do payload e chama `0x80052478` — isto é, **tocar a caixa abre a thread**.
  Tem um gate no topo: `if (*(u32*)0x800ccba0 & 0x02000000) return;`.

➜ **A cena de entrada roda sozinha no load da sala. A de saída roda quando a Jill pisa na
caixa a oeste.** Não há terceira cena: são as duas que o dono descreveu.

### 2.1 Por que a função 7 é a de ENTRADA, e não outra das 5 candidatas

`boot_ptbr_hd.md` §8.7 listou 5 candidatas por tamanho (7, 13, 8, 11, 18) e disse "nomear qual
é a primeira exigiria rodar a VM". Rodada:

- é a **única** função aberta como thread pelo init (`func 5`, antes de qualquer gatilho);
- ela **termina em `cut_chg 0`** (`50 00`, @+0x1a2) — e a câmera 0 é exatamente a que o port já
  mostra ao entrar na sala (`boot_ptbr_hd.md` §6.1: HUD `câmera 1/13`);
- as outras 4 são chamadas por ela ou pela função 11 (13 e 8 são gosub/thread da 7; 11 é o
  gatilho; 18 é thread da 11).

---

## 3. Os opcodes de VM que faltavam (todos com o handler citado)

Nenhum destes existia no port. Estão implementados em `vm.gd` sob `Modo.CENA` — os modos
`LINEAR` e `EXECUCAO` continuam byte a byte iguais (asserção 7 do teste).

| op | nome | handler | o que faz |
|---|---|---|---|
| `0x09` | `sleep_init` | `0x8005304c` | empilha o contador com o **`u16` em PC+2** — que é o operando do `0x0a` seguinte (`lhu $v1,2($a2)`, `$a2` = PC velho) — e anda **1** |
| `0x0a` | `sleeping` | `0x80053094` | `--contador`; PC += 3 **só** no zero; **volta 2 nos dois casos** (`0x800530f0`) ⇒ `09 \| 0a NN NN` = **espera NN quadros** |
| `0x02` | `evt_next` | `0x80052e60` | PC += 1 e volta 2 = espera 1 quadro |
| `0x0d` | `for` | `0x80053184` | `count = u16@+4` (0 ⇒ salta `PC + s16@+2 + 6`, via `0x8005320c`); corpo `[PC+6, PC+6+len)` |
| `0x0f` | `next` | `0x800532e8` | `--contador`; volta ao início ou PC += 2 e desempilha; **volta 1** (não cede o quadro) |
| `0x10` | `while` | `0x80053364` | `cond_len = byte@+1`, avaliada por `0x80053550`; falso ⇒ PC = `PC+4+u16@+2` |
| `0x11` | `endwhile` | `0x80053420` | PC = o início guardado em `obj+0x20` (o próprio `0x10`) e desempilha |
| `0x47` | `work_set` | `0x8005441c` | escolhe `obj+0x154` na tabela `0x80010b60` por `byte@+1 - 1`; `byte@+2` é `s8` |
| `0x40` | `member_set` imed. | `0x80053b74` | membro `byte@+1` = `s16@+2` |
| `0x41` | `member_set` por var | `0x80053bc0` | membro `byte@+1` = `*(s16*)(0x800d1f46 + byte@+2·2)` — leitura **`lh`, assinada** |
| `0x42` | `member_get` p/ var | `0x80053c20` | `var[byte@+1]` = membro `byte@+2` (grava com `sh`) |
| `0x20` | var `op=` imediato | `0x800539b8` | `u16@+2` = (op no byte **baixo**, índice de var no **alto**); valor = `s16@+4`; tabela de ops `0x80010900` |
| `0x50` | `cut_chg` | `0x800548c8`→`0x800549c4` | câmera = `byte@+1 & 0x7f` → `gs+0x7842`; `gs+0x77f4 \|= 0x80 \| 0x400000`; guarda a anterior em `0x800e0175` |
| `0x51` | `cut_old` | `0x80054960` | volta à câmera de `0x800e0175` e apaga o bit `0x80` |
| `0x46` | `fade` | `0x80054384`→`0x8002a35c` | `abr = byte@+3`; `c0 = +6\|+5<<8\|+4<<16`; `c1 = +9\|+8<<8\|+7<<16`; `T = byte@+0xa` |
| `0x66` | **`sce_aot_exec`** | `0x80055d7c` | **§4** |
| `0x80` | anim/ação do work | `0x80056dc0` | `w+4 = (byte@+1<<8) \| 4` (**ação 4 = roteirizada**); `w+0xc9 = 0`; **`w+0xc8 = byte@+2` = SEQ do EDD**; `w+0x144 = byte@+3`; `w+0x46 \|= 0x100` |
| `0x81` | ir até (x,z) | `0x80056e5c` | rotina = `byte@+2`; **`w+0x146 = byte@+3` = o BIT do banco 4** aceso na chegada; `w+0xd4 = u16@+4` (X), `w+0xd6 = u16@+6` (Z) |
| `0x8f` | liga a entidade n | `0x800589fc` | `e = gs+0x265c[byte@+1 + 2]`; `e+0 = 1`; `e+4 = 0`; `e+0xd2 = 0` |

### 3.1 A tabela de MEMBROS — 43 entradas, lida nas DUAS direções

`member_set` = **`0x80010950`** (despacho `0x80053e10`, `sltiu $a1, 0x2b`) e `member_get` =
**`0x80010a00`** (despacho `0x80053fac`, idem). Cada entrada é **uma** instrução de store/load
num offset fixo do struct de personagem — as duas tabelas concordam em 43/43, o que é a
melhor validação possível (uma confere a outra). Está em `ScriptVM.MEMBROS`.

| membro | campo | membro | campo | membro | campo |
|---|---|---|---|---|---|
| `0x00` | `+0x00` u16 | `0x0b` | **`+0x3c` = Z** (s32) | `0x1a`.`0x1c` | `+0xc0`/`c2`/`c4` |
| `0x01` | `+0x02` u16 | `0x0c`.`0x0e` | `+0x6c`/`6e`/`70` | `0x1d`/`0x1e` | `+0x1cc`/`1ce` |
| `0x02`.`0x05` | `+0x04`..`+0x07` | `0x0d` | **`+0x6e` = ângulo** | `0x1f` | **`+0x12d`** u8 |
| `0x06` | `+0x4a` = classe | `0x0f` | `+0x09` s8 | `0x20`.`0x25` | **globais** `0x800e0154`..`0168` |
| `0x07` | `+0x46` u16 | `0x10`/`0x11` | `+0xd2`/`+0x122` | `0x26` | **`+0xcc` = HP** |
| `0x08` | `+0x10` u32 | `0x12`/`0x13` | `+0xd4`/`+0xd6` = destino | `0x27` | `+0x0c` u8 |
| `0x09` | **`+0x34` = X** (s32) | `0x14`.`0x18` | `+0x144`,`148`,`14a`,`14c`,`14e` | `0x28`/`0x29` | `+0x12a`/`+0x12c` |
| `0x0a` | **`+0x38` = Y** (s32) | `0x19` | `+0xc0` u8 | `0x2a` | `+0x0d` u8 |

> **⚠ Armadilha real, e ela custou uma depuração:** o `0x41` lê a var com **`lh`**
> (`0x80053bf0`), *assinado*. O vetor de vars (`0x800d1f46`) é de `u16`, então uma coordenada
> negativa que passa por var (é o que o script faz para somar: `0x42` → `0x20` → `0x41`) volta
> **positiva** se a leitura for feita sem sinal — e o ator sai andando para o outro lado do mapa.
> O port implementa `_var_get_s()` só por isso.

### 3.2 O banco 4 é o handshake entre as threads da cena

A tabela de bancos de flags `0x8009e3f8` tem em **[4] = `0x800d1fc0`** (= `gs+0x7888`). Esse
banco é **zerado no load da sala** (`0x80052350  sw $zero, 0x7888($s0)`) e — varredura do EXE
— **só três sítios usam a tabela de bancos**: `0x800512fc` (AOT `sce 6`), `0x800546cc` (`0x4c`)
e `0x8005472c` (`0x4d`). Isto é, do lado do script nada acende o bit 0 do banco 4; ele é
aceso **pelo motor**, e o sítio é:

```
0x800169ec  lbu $a1, 0x146($s0)          ; o byte que o 0x81 gravou
0x800169f0  jal 0x800788dc               ; set_bit(base, id)
0x800169f4  addiu $a0, $a0, 0x1fc0       ; base = 0x800d1fc0  = BANCO 4
```

(`0x800788dc`: `base[id>>5] |= 0x80000000 >> (id & 0x1f)` — o mesmo formato do `0x4d`.)
São **28 sítios** no EXE montando `0x800d1fc0`, todos no mesmo padrão, nas rotinas de
movimento de personagem (`0x80016xxx`, `0x80060xxx`, `0x80072xxx`).

➜ **`0x81 <?> <rotina> <bit> <x> <z>` = "vá até (x,z) e acenda o bit `bit` do banco 4 quando
chegar"**, e o `while (não flag)` do script é a espera. É a primitiva de sincronismo da cena
inteira: a função 11 abre 8 threads e espera cada uma pelo seu bit.

O `0x4c` fecha o par: `0x800546cc` lê `a1 = u16@+2` = (**bit** no byte baixo, **negação** no
alto) e devolve `((banco[bit>>5] & mask) != 0) XOR (byte_alto == 0)`. Logo `4c 04 00 00`
significa "**não** flag(4,0)" — e `while (não flag) { yield }` = espera a chegada.

---

## 4. ⭐ `0x66` = `sce_aot_exec` — a PORTA ROTEIRIZADA (e a correção a `door_handler.md`)

`R10D` declara **uma** porta e ela é impossível de tocar:

```
func 3:  61 00 01 21 00 00 | 00 00 00 00 00 00 00 00 | 00 00 … | 00 01 00 00 00 02 00 00 00 00
         id=0  sce=1  sat=0x21   caixa x=0 z=0 w=0 d=0      chegada (0,0,0) dir 0
                                                            +0x16 stage=0 · +0x17 room=1
```

Quem a dispara é o **último ato da função 11**:

```
+0x0d8  46 00 00 02 00 00 00 ff ff ff 30    fade abr=2, preto→branco, T=0x30=48
+0x0e4  09 / 0a 30 00                       espera 48 quadros
+0x0e8  47 01 00                            work = player
+0x0ec  40 1f 00 00                         player+0x12d = 0
+0x0f0  40 26 c8 00                         player+0xcc  = 200   (HP: `char+0xcc -= dano`)
+0x0f4  66 00                            ★  sce_aot_exec(AOT 0)  = a PORTA
+0x0f6  19 25                               gosub 37 (devolve o controle ao jogador)
```

Handler `0x80055d7c`, byte a byte:

```
aot = *(u32*)(gs + 0x2158 + (byte@+1)*4)      ; o AOT registrado pelo 0x61
*(u32*)0x800decb0 = aot
a0 = (aot[1] & 0x80) ? aot + 0x14 : aot + 0x0c    ; descriptor (path 0x0c p/ o 0x61)
gs+0x2140 = (obj+0x154 == 1) ? gs+0x248c : obj+0x154      ; o ATOR do evento
jalr *(0x8009e0bc + aot[0]*4)                 ; aot[0] = SCE TYPE  ->  sce 1 = 0x80050d28
PC += 2
```

`0x8009e0bc[1]` é o **produtor de porta `0x80050d28`**, que grava `gs+0x2154 = descriptor` e
liga `0x800c7960` — dali segue a cadeia normal `door_handler 0x800248e4` → room-loader
`0x800493ec`. **Nada de especial: é a mesma porta, disparada por dentro.**

### 4.1 ⚠ Correção a [`door_handler.md`](door_handler.md)

Aquele doc afirma, no achado 2 da auditoria: *"**Não há outro mecanismo de troca de sala.** […]
o room-loader `0x800493ec` só é chamado pelo cluster do door_handler […] **não há warp por
opcode de script**"*. A primeira e a segunda frase continuam verdadeiras; **a terceira não**:
o script não chama o room-loader, mas chama o **produtor** que o aciona, via `0x66`.

E a prova não é o `R10D` isolado — é uma **coincidência que não pode ser acidente**. Varredura
das 169 salas: **120 opcodes `0x66`**, todos apontando para um AOT declarado na mesma sala. Os
que apontam para AOT `sce ∈ {1,13}` são:

| sala/função | AOT | o que `door_handler.md` já dizia daquela porta |
|---|---|---|
| `R10D` f11 | 0 | `R10D→R101` **placeholder_unused**, "box+arrival ZERADOS (único no jogo)" |
| `R215` f18/20/21/23 | 3 | `R215→R303`/`R305` story_progression_gate, "**box ZERO (cutscene)**" |
| `R30D` f39 | 0 | `R30D→R310` transient_variant_scripted, "sai por **box ZERO (scripted)**" |
| `R50D` f20/f82 | 1 | `R50D→R50F` endgame_boss_**scripted**, "box ZERO (cutscene)" |
| `R50F` f7 | 0 | `R50F→R50E` endgame_ending_**scripted** |
| `R510` f34 | 1 | `R510→R504` one_way_fall, "arrival ZERADO (**spawn scripted**)" |

**As seis portas que a auditoria teve de rotular "scripted/cutscene" sem saber o mecanismo são
exatamente as seis disparadas por `0x66`.** O rótulo `placeholder_unused` do `R10D` está errado:
não é placeholder — é a porta da cena de saída, e é a **única** saída da sala.
(Nem toda porta de `0x66` tem caixa zerada: em `R215` e `R510` a mesma porta também é tocável.
As zeradas são `R10D`, `R30D`, `R50D`, `R50F`.)

### 4.2 O que ficou EM ABERTO na saída — a chegada

A chegada da porta do `R10D` é **(0,0,0) facing 0** no dado, e **(0,0,0) não é ponto válido em
`R101`**: as outras duas portas que entram lá chegam em `(-18808,-7200,-11475)` e
`(-4434,-3600,-27933)`. Conferi que **nem `R101` nem `R504`** (o outro caso de chegada zerada)
posicionam o player por `0x40` membro `0x09/0x0a/0x0b`. O `door_handler` também lê
`descriptor+0xb` = **grupo do RVD** (`gs+0x2495`), que é o candidato óbvio — e **eu não medi o
RVD**. Então o port entrega `pos` e `grupo` como estão, marcados com `chegada_zerada = true`, e
quem monta a sala decide. **Não inventei coordenada.**

---

## 5. A linha do tempo das duas cenas (medida na VM, não estimada)

`godot --headless --path port --script res://dev/dump_cena.gd`. Quadros de **script** (o
`Clock.HZ` do port é 30).

### 5.1 Entrada — função 7, **260 quadros ≈ 8,7 s**

```
q   2  cut_chg 11                      (50 0b)
q  62  cut_chg 12                      60 quadros depois  (09 | 0a 3c 00)
q 122  cut_chg 10                      60 quadros depois
q 124  thread func 40 + fade abr=1 preto→branco T=4      ← o RELÂMPAGO
q 128  thread func 8 · fade abr=1 branco→preto T=16 · anim SEQ 20
q 130  threads func 9 e func 10
q 182  anim SEQ 5
q 259  cut_chg 0                       ← a câmera em que o port já nasce
q 260  fim
```

A função 40 é o relâmpago da rua: dois `0x46` aditivos (4 ticks para o branco, 16 de volta) com
**12 rajadas de `0x70`** (sprites de efeito) entre `evt_next`. O `esp_efeitos.md` já registra o
fogo do `R10D` — este é o outro lado da mesma iluminação.

### 5.2 Saída — função 11, **834 quadros ≈ 27,8 s**

```
q  11  cut_chg 4
q  12  anim do PLAYER: SEQ 8           (19 0e -> func 14: 80 00 08 00)
q  24  cut_chg 5     · liga 5 entidades (8f) e manda todas para (-11975,-15078)
q  56  cut_chg 4
q  57  anim do PLAYER: SEQ 7           (19 0f -> func 15: 80 00 07 00)
q  69  cut_chg 6     · idem, 5 entidades
q 101  cut_chg 7     · liga 8 entidades
q 104  8 threads: 27, 28, 17, 18, 29, 30, 31 (+35 depois) e o player vai a (-14070,-13753)
q 408  o player CHEGA (bit 0 do banco 4)
q 409  SEQ 4 · q 493 SEQ 9 · q 513 SEQ 5 · q 548 SEQ 6      ← a SUBIDA (§6)
q 580  cut_chg 8
q 621  cut_chg 9
q 622  o player vai a (-18724,-12992)   (func 20)
q 638  as 5 entidades saem para x = -32000 (func 35)
q 692  o player chega · SEQ 10 · gira 5×0x100 · player+0x12d |= 0x80
q 736  o player sai andando para x = -32000  (func 21)
q 786  FADE abr=2, T=48
q 834  ★ PORTA -> stage 0 / sala 1 = R101
```

Os `cut_chg` e os `sleep` são **exatos** (saem do bytecode). Os instantes de CHEGADA são
**declarados** — dependem da velocidade do `0x81`, que não decodifiquei (§7).

---

## 6. O SUBIR — é coreografia da cena, e as duas conclusões anteriores estão certas

O dono insistiu que a Jill sobe na lixeira; `subir.gd` provou que **nenhum objeto do `R10D` é
escalável** (os 3 `0x7f` têm `be_flg = 0x6001`: bit `0x4000` aceso e `0x100` apagado, reprovando
nos dois testes de `0x80036570`). **As duas coisas são verdade ao mesmo tempo**, porque o subir
do `R10D` não passa pela rotina 9 nem pelo agregador de objetos:

1. **A animação vem do script.** `0x80` (`0x80056dc0`) grava o índice de sequência **direto** em
   `player+0xc8` e põe `player+4 = (rotina<<8) | 4` — **ação 4, a ação roteirizada**. Não há
   detecção de contato, não há 6 quadros, não há flag `0x10` de `gs+0x77f4`.
2. **As sequências são as MESMAS.** A função 14 toca **SEQ 8** e a 15 toca **SEQ 7**; a thread 17
   toca **SEQ 4 → SEQ 9 → SEQ 5 → SEQ 6**. E `subir.gd` provou, por `0x8003b39c`
   (`sw 0x00070006, 0xc8`) e `0x8003b3c4` (`sw 0x00070007, 0xc8`), que **subir/descer em objeto
   = SEQ 6 e SEQ 7**. É a mesma animação, acionada por outro caminho.
3. **A translação é MANUAL.** Entre a SEQ 9 e a SEQ 5, a thread 17 faz:

   ```
   0d 00 24 00 0a 00                    for 10 vezes
     47 01 00                           work = player
     42 10 09 / 20 00 00 10 46 00 / 41 09 10     player+0x34 (X) += 0x46 = 70
     42 10 0b / 20 00 00 10 28 00 / 41 0b 10     player+0x3c (Z) += 0x28 = 40
     02                                 cede o quadro
   0f 00
   0d 00 12 00 0a 00                    for 10 vezes
     42 10 09 / 20 00 00 10 05 00 / 41 09 10     player+0x34 (X) += 5
     02
   0f 00
   ```

   **+750 em X e +400 em Z em 20 quadros, escritos à mão pelo script.** É exatamente o que se
   faz quando não há objeto escalável para o motor usar: a cena carrega o corpo.
4. **E o script mexe no gate de colisão do subir.** No fim da função 20, `42 10 1f` /
   `20 00 05 10 80 00` / `41 1f 10` = **`player+0x12d |= 0x80`**; e no fim da função 11,
   `40 1f 00 00` = **`player+0x12d = 0`**. Esse `+0x12d` é um dos quatro campos que
   `subir.gd` §2d já tinha isolado no laço de colisão (`0x8003510c`) — o campo que decide se o
   corpo é empurrado para fora do obstáculo. A cena o usa para atravessar o cenário na saída.

➜ **Hipótese (c) da investigação: o subir é parte da cutscene.** Nada a corrigir em
`subir.gd`: ele continua sendo a rotina 9 de verdade, e as salas onde ela mostra algo continuam
sendo `R210`, `R219`, `R315` e `R50D`.

### 6.1 O que o `player.gd` (que não é meu) precisa ganhar

Um estado **`CENA`** para a **ação 4**, dirigido de fora, com quatro pontos:

1. **Entrar:** quando `Cena` estiver viva, `player.gd` não lê o pad — a `Cena` manda.
   Ela expõe, por quadro: `ator_pos(1, 0)` (posição), e os eventos `anim`, `ir` e `chegou`.
2. **Clipe:** o evento `anim` traz `seq` = o índice do EDD que o motor grava em `player+0xc8`.
   O de-para para o `PL00.glb` é o mesmo que `subir.gd` usa (`anim%02d` / `arm%02d`).
   As sequências que a cena de saída pede são **8, 7, 4, 9, 5, 6 e 10** (nessa ordem).
   ⚠ A 8 e a 10 não estão no par de `subir.gd`; `animacoes_player.md` rotula a 8 e a 10 por
   render, não por prova — vale revisar com esta cena rodando.
3. **Andar até um ponto:** o evento `ir` traz `x`, `z` e o `bit`. Quando o teu movimento chegar,
   chame **`cena.chegou(bit)`** — é o que solta a próxima etapa (§3.2). Enquanto ninguém chamar,
   a `Cena` simula com `VELOCIDADE_DECLARADA = 78` (o teu `VEL_ANDAR`) e avisa que é declarado.
4. **Sair:** quando `cena.viva()` virar `false`, `player+4` volta a `1` (é o que a função 37
   faz: `4d 02 07 00` e `4d 01 1c 00`, apagando os dois bits que a cena acendeu).

### 6.2 O que falta em `world.gd` (que também não é meu) — três linhas

```gdscript
# 1) por quadro, procurar o gatilho de evento
var g := Cena.gatilho_de_evento(vm, player.pos.x, player.pos.z)
# 2) quando aparecer, abrir a cena
if g != null and cena == null:
    cena = Cena.abrir_evento(vm, g, state, player.pos, player.facing)
# 3) enquanto ela viver, tocar; e quando pedir porta, atravessar
if cena != null:
    cena.quadro()
    var p := cena.porta_pedida()
    if p != null:
        atravessar(p)      # já existe; a chegada zerada cai no desencrave de world.gd
```

O mesmo vale para a cena de ENTRADA, que não tem gatilho: basta
`Cena.new().iniciar(vm, 7, state)` logo depois do `executar(0)` do load.

---

## 7. EM ABERTO (o que eu NÃO medi)

1. **A velocidade do `0x81`.** O opcode grava destino e rotina; a velocidade sai de uma tabela
   por classe (`0x8009e52c`/`0x8009e5cc`, indexada por `w+0x4a`, alcançada pela jump-table
   `0x80010be8` de `0x80056e5c`) que **não decodifiquei**. `Cena.VELOCIDADE_DECLARADA = 78`
   é o `VEL_ANDAR` que o port já mede, para não haver dois números. Consequência: os instantes
   de chegada da §5.2 são declarados, não medidos.
2. **A chegada da porta roteirizada** (§4.2): grupo do RVD não medido.
3. **A ORDEM do escalonador** entre threads criadas no mesmo quadro. O motor percorre a lista
   de tarefas uma vez por quadro (`0x80052ba4`); uma thread de slot maior poderia rodar já no
   quadro da criação. Não medi a lista, então no port toda thread nova começa no quadro
   **seguinte** — um atraso de 1 quadro por thread, visível na linha do tempo.
4. **Opcodes que a cena usa e continuam com semântica desconhecida** — o port anda o PC e não
   finge nada: `0x05` (`0x80052f50`, limpa um byte numa tabela de `0x800e0ce8`), `0x52`, `0x77`
   (12 B, tem x/y/z), `0x78`, `0x82`, `0x83`, `0x84`, `0x88`, `0x8e`, `0x76`, `0x1e`, `0x4e`,
   `0x70` (o sprite de efeito; `esp_efeitos.md` cobre o dado, não o opcode).
5. **`0x55`/`0x56`** (som posicional, `0x80034124`): o port registra o disparo com os operandos
   crus. Qual campo é id de SE e qual é posição **não** está medido — não liguei som na cena.
6. **A função 41** (`04 05 19 29`, thread de slot 5 aberta pelo init) é um laço infinito
   (`18 ff ff 00 d7 ff`) de `0x30`/`0x32` com coordenadas fixas `(17000, -7500)`. Parece o
   ambiente da rua (chuva/som), mas **não medi** — a `Cena` não a roda.
7. **O gate do `sce 5`** (`*(u32*)0x800ccba0 & 0x02000000`): sei que existe e que a cena acende
   e apaga o bit **7** do mesmo banco (`4d 02 07 01` / `4d 02 07 00`, máscara `0x01000000`).
   Bit 6 vs bit 7 — **não** conferi quem acende o `0x02000000`.

---

## 8. Como reproduzir

```bash
# a linha do tempo das duas cenas
godot --headless --path port --script res://dev/dump_cena.gd
CENA_SALA=R10D CENA_FUNC=11 godot --headless --path port --script res://dev/dump_cena.gd

# o teste (filtro obrigatório)
godot --headless --path port --script res://dev/run_tests.gd -- cena     # 108 asserts
godot --headless --path port --script res://dev/run_tests.gd -- subir    #  82, seguem verdes
godot --headless --path port --script res://dev/run_tests.gd -- scd_vm   #  33

# a tabela de opcodes (nomes novos do 0x09/0x0a/0x0d/0x0f/0x10/0x11/0x20/0x40..0x42/
# 0x46/0x47/0x50/0x51/0x66/0x80/0x81/0x8f)
NOSTALGIA_OUT=port python tools/scd_export.py

# o disassembly cru de uma função (o que gerou este doc)
python tools/scd_decode.py extracted/ntsc-u/CD_DATA/STAGE1/R10D.ARD
```
