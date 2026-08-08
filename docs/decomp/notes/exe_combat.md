# Combate do player no EXE — mira / tiro / dano + SM (SLUS_009.23, RE3 NTSC-U)

> Unidades: `aim_shoot` (era 0%), `player_sm` (era 45%), `item_logic` (era 20%).
> Ferramenta: [`tools/exe_combat.py`](../../../tools/exe_combat.py) (rode `python tools/exe_combat.py`).
> Tudo aqui é derivado dos **bytes reais** do `extracted/ntsc-u/SLUS_009.23` (base `0x80010000`).
> Pontos-chave foram **confirmados por códigos GameShark públicos da versão NTSC-U** (fontes no fim).
> Base do player-struct: **`0x800ccbc4`** (deref robusto `*(u32*)0x800ccd94`), como no `docs/formatos/exe.md`.
> Marcações: ✅ provado no binário · 🎯 confirmado externamente (GameShark) · 🟡 inferido/incerto.

---

## 0. CORREÇÃO IMPORTANTE ao `exe.md` — `player+0xcc` é HP, não "momentum"  🎯✅

O `exe.md §4.3` lista `player+0xcc` como "momentum" e o "speed-tier/motionType" como derivado dele.
Isso está **errado**. A GameShark de vida infinita da Jill (NTSC-U) é **`800CCC90 00C8`** →
grava `u16 = 0x00C8 (200)` em `0x800ccc90 = player_base(0x800ccbc4) + 0xCC`. Logo:

- **`player+0xcc` (u16) = HP atual** (0x800ccc90). Máx da Jill = **200 (0xC8)**.
- **`player+0xce` (u16) = HP máximo** (0x800ccc92) — provado pela função de cura (clamp).
- **`player+0xd2` (u16) = flags de condição**; **byte `player+0xd3`** (0x800ccc97) = **condição/status**
  (GameShark "always fine" `300CCC97 0004` → `0x04 = FINE`; bit `0x0800` do word 0xd2 cai em 0xd3 = crítico/morto).

E o `motionType` (var global `0x8009cd3c`) que indexa a tabela 3×3 de animações **NÃO é velocidade** —
é a **ZONA DE SAÚDE derivada do HP** (é o mecanismo do MANCAR). Prova em `T1 r1` (`0x800395b0`):
```
lh   $a0, 0xcc($s0)          ; a0 = HP
slti $v0, $a0, 0x65          ; HP < 101 ?
... sb 0/1, -0x32c4($v1)     ; motionType = 0 (>=101) senao 1
slti $v0, $a0, 0x15          ; HP < 21 ?
... sb 2, -0x32c4($v1)       ; motionType = 2  (<21)
```
→ **tier0 = FINE (HP≥101), tier1 = CAUTION (21..100), tier2 = DANGER (HP<21)**. A tabela 3×3
`0x8009cde0` (`{2,5,8}|{0,3,6}|{1,4,7}`) então escolhe a variante **saudável / ferida / mancando**
de idle / andar / ré. (Antes atribuído a "aceleração"; a fonte real é o HP.)

---

## 1. MIRA (aim)  ✅  — `aim_shoot`

### 1.1 Entrada no estado de mira
O roteador-mestre de input é **`T1 r1` = `0x8003957c`** (handler da rotina "andar", mas é onde
todas as transições de `player+5` acontecem). Os `sw val,4($player)` gravam **action E routine juntos**
(`0x00RRAA01`: byte+4=action=1, byte+5=routine). Trecho da mira (`0x80039714`/`0x80039760`):
```
andi $v0,$s1,0x100 / andi $v0,$s1,0x400   ; botao de MIRA (mask 0x500)
lbu  $v0,0x46($s0)                         ; weapon equipada != 0 ?
addiu $v0,zero,0x501  ; ->  routine 5   (levantar arma)
... se momentum/estado -> 0x20701 = routine 7 (mira direta)
```
- **Botão de mira = pad bits `0x100`/`0x400` (máscara `0x500`)** ✅. O nome físico (R1) é 🟡 —
  o remap do pad é feito no boot (o `exe.md §4-B.5` já avisa que a tabela estática não é confiável).
- Precisa de **arma equipada** (`player+0x46 != 0`).
- Fluxo: **rotina 5 (levantar arma / ready)** → **rotina 7 (mirar+atirar)**.

### 1.2 Rotina 5 — "ready/levantar arma" (`0x8003e2ac`)  ✅
Estado curto. Lê input, e quando pronto faz `sw 0x20701,4` (→ routine 7) e re-despacha via
`T2_anim` (`0x8009cda0`). Usa `rand` (`0x800102e8`) num sub-caso (variação).

### 1.3 Rotina 7 — MÁQUINA DE MIRA/TIRO (`0x8003a7d8`)  ✅
`T1 r7` (`0x8003a7d0`) é **stub** (`jr $ra`): durante a mira o player **NÃO** anda (facing travado).
Sub-estado em **`player+6`** (0..3), dispatch no topo da função:

| sub | endereço | o que faz | anim (`player+0xc8`) |
|---|---|---|---|
| 0 | `0x8003a88c` | **levanta a arma**; `player+6=1`; toca SFX (`0x800776b0`) | **13** (`0x3000d`) |
| 1 | `0x8003a8cc` | interpola **pitch de mira** `player+0xc0 -= 0x28` (clamp 0); avança anim | — |
| 2 | `0x8003a90c` | **mira/segura + AUTO-AIM** (calcula ângulo ao alvo) | **14** (`0x3000e`), 15..20 por altura |
| 3 | `0x8003adc0` | **hold + FOGO** (lê gatilho, recuo, facing p/ alvo) | (mantém) |

- **Auto-aim / rastreio do alvo (sub 2, `0x8003a90c`+):** lê o ponteiro do alvo `player+0x170`,
  pega a posição dele (`(v1)`, `8(v1)`), a posição do player (`player+0x34`=X, `player+0x3c`=Z) e
  calcula o ângulo via **`ratan2` = `0x8001808c`** (usa a sin-table). Guarda o yaw/pitch de mira em
  `player+0xd8`/`0xda`. Faz o **clamp do arco** em ±`0x1000` (12-bit; ~90°) — a mira só "gruda" se o
  alvo estiver dentro do arco.
- **Altura da mira:** `player+0xc7` (part-id atingido, low nibble) escolhe entre poses de mira
  15/16/17/19/20 (`0x8003ac90`: `andi 0xc7,0x20` → troca anim 15→19 / 16→20 e ajusta facing ±0x400).
  > ✅ **RESOLVIDO — anim 19/20 são poses de MIRA, NÃO dano/knockback (prova exaustiva).**
  > Varredura de **TODOS os 168 escritores de `player+0xc8`** no EXE: os **únicos** que gravam 19 (`0x13`) e
  > 20 (`0x14`) são **`0x8003acb8`** e **`0x8003accc`**, ambos DENTRO do seletor de altura da rotina 7
  > (`0x8003ac90`), gateados por `player+0xc7 & 0x20` (bit de altura do alvo travado pelo auto-lock).
  > O **dano/hurt do player** (ação macro **a3** `0x8003d9e0`) usa anims **4/5/9/10/11/12** (escritores
  > `0x8003d200`/`0x8003d52c`/`0x8003d630`/`0x8003d6ec`/`0x8003d72c`/`0x8003d910`/`0x8003d990`) — **nunca 19/20**.
  > *Reconciliação com o render:* a **seq 19/20 do `PL00.PLD`** (banco DESARMADO) medida em isolado parece
  > um tombo/knockback (root Z ±5648), mas o EXE **só seleciona índice 19/20 durante a mira** (exige arma
  > equipada → banco **PLW** ativo, ver `exe.md §4-B0`), então o clipe realmente exibido p/ 19/20 no gameplay
  > é a **pose de mira-alta do PLW**, não o clipe de tombo do PLD. **Fonte de verdade = EXE.**

### 1.6 GEOMETRIA da mira — altura/pitch (upper / straight / lower / auto)  ✅
Fecha o "10% de geometria" de `aim_shoot`. Na rotina 7 sub2 (aim), antes do seletor `0x8003ac90`:
```
0x8003ac48  addiu a0,zero,3
0x8003ac4c  beq   t1,a0,0x8003ac74   ; se aim_tier == 3 -> pose 0x11 (17), pitch alto especial
0x8003ac58  lbu   v0,0x20(v0)        ; senao: pose = stackTbl[aim_tier] & 0x7f  (14/15/16)
0x8003ac54  sll   v1,v1,9            ; pitch:
0x8003ac5c  addiu v1,v1,0x800        ; player+0x6e (facing/pitch) = (aim_tier<<9) + 0x800
0x8003ac60  sh    v1,0x6e(s0)
0x8003ac64  sb    a0,0x12d(s0)       ; municao/flash
0x8003ac70  sw    v0,0xc8(s0)        ; anim de mira (14/15/16)
```
- **`aim_tier` (0..3)** vem da **elevação relativa do alvo** (auto-lock; sub2 usa `ratan2 0x8001808c` p/ yaw e a
  altura do alvo p/ o tier). Define o **pitch** `player+0x6e = (tier<<9)+0x800` (passo de `0x200` = ~17.6°).
- **Poses por tier:** tier 0/1/2 → anim **14/15/16** (via tabelinha no stack, `0x20($v0)`); tier 3 → anim **17**.
- **Promoção upper-aim:** `0x8003ac90` — se `player+0xc7 & 0x20` (alvo alto), **15→19 / 16→20** e ajusta
  facing **±0x400** (`0x8003ace8` +0x400 p/ pose15/19, `0x8003ad08` −0x400 p/ pose16/20).
- **É AUTO:** a altura é derivada do part-id travado (`0xc7`), sem input manual de up/down. As poses de mira
  têm root-motion ~0 (o player fica parado mirando) — coerente com "não são knockback".

### 1.4 AUTO-LOCK — varredura de inimigos e teste de arco  ✅ (o coração da "seleção de alvo")
Função de teste **`0x800445c8`**: recebe `a0`=hitbox, `a3`=**base do player** (`0x800ccbc4`). Ela:
1. Rotaciona a posição do alvo para o **espaço local da mira** (`0x8008a0e4` + transform GTE `0x80088774`).
2. Testa se o ponto cai na **caixa/arco** (meia-extensões em `s1+4`, lidas como `lh 0/2/4/6`).
3. Se dentro: grava **`player+0x16c` e `player+0x170` = ponteiros do alvo**, seta bit `0x80000000`
   em `(enemy)` (flag "estou travado/atingível") e **`player+0xc7` = part-id** (`s1+0xa`, ex. `0x41`/`0x42`).

O **loop sobre inimigos** que chama isso está em **`0x8001e900`** (e vizinhança): para cada entidade
inimiga `s4` (viva: `s4+0x18` em `[0,3)`), monta descritores de **partes do corpo** (part-ids `0x41`,`0x42`)
a partir dos ossos (`enemy+0xbc`) e chama `0x800445c8` até 4×, usando tabelas de arco/alcance por-arma
em `0x80098064`/`0x8009806c`. → **Sim: o jogo varre as entidades da sala e trava na parte que estiver
dentro do arco da mira** (auto-aim clássico do RE3). Outros chamadores: `0x8001e9f8`, `0x8001ea38`,
`0x8001ea64`, `0x80021240`, `0x80021274`.

### 1.5 Facing durante a mira
`T1 r7` é stub → sem input de andar. O facing é forçado ao alvo no fim do sub3 (`0x8003afc8`:
`lw 0x15c($s0)` = alvo; `jal 0x80018110` que gira `player+0x6e` em direção ao alvo). `player+0x6e`
= ângulo de direção 12-bit (o `exe.md` chama de `+0x74`; medições aqui mostram o giro em `+0x6e`).

---

## 2. TIRO / DANO  ✅ (player) / 🟡 (aplicação ao inimigo)

### 2.1 Disparo (rotina 7 sub 3, `0x8003adc0`)  ✅
- **Botão de fogo:** lido do **pad segurado global** `gamestruct+0x2104 = 0x800cc83c`, máscara **`0x500`**
  (mesmos bits 0x100/0x400 da mira). `gamestruct = 0x800d0000-0x58c8 = 0x800ca738`; `+0x2120` = pad
  "pressionado neste frame".
- **Debounce do gatilho:** `player+0xe3` (máquina 0→1→2→3→4 conforme o botão sobe/desce, contra a máscara 0x500).
- **Munição / flash:** `player+0x12d` (`andi 0x7f` = contador; bit `0x80` = flag de flash/recoil,
  decrementada no dispatcher `0x80038cbc`).
- **Recuo/tremor de tela:** `0x80048308` (acumula em `gamestruct+0x7860/+0x2118/+0x211a`; NÃO é dano).
- **Ponto de saída do cano:** `0x80018d34` calcula, a partir do esqueleto (anim `0xc8`/frame `0xc9` + EDD/EMR),
  o ponto 3D da mão/arma → escreve `player+0x124/0x126/0x128` (ponto) e `player+0xc0/0xc2/0xc4` (offset de mira).
- Fim do tiro: chama `0x800776b0` e transiciona (`sw 0x60501/0x80501,4` = volta pra ready/idle).
  > **⚠ CORREÇÃO (ver [`exe_audio.md`](exe_audio.md) §6.4):** a afirmação antiga — *"seleciona
  > seco/tiro/vazio por flags da arma em `(player+0xe4) & 0x200/0x400`"* — é **NÃO PROVADA**:
  > em `0x800776b0..0x80077b84` **não existe nenhum** `andi` com `0x200`/`0x400` nem leitura
  > de `+0xe4`. O que a rotina faz: `0x8001b484` (spawn de efeito/modelo, tabela
  > `0x800ba728`) **10×**, `0x8003879c` (**rampa de VIBRAÇÃO**, não som) **8×**, e **um**
  > pedido de SE em `0x80077b50` com `a0 = s5 | 0x10200` → **`cat = 2` = banco da SALA**,
  > `idx = s5 ∈ {0x17,0x18,0x1a,0x1b,0x2d, (retorno de 0x80077b84)&0x7f}`. Compatível com
  > **impacto/ricochete na sala**, não com o estouro da arma.
  >
  > O **estouro** é um SE de `cat 0` (banco `C_` do jogador), **id 11**, pedido em
  > `0x8003ad6c` (`lui a0,1; ori a0,a0,0xb` → `a0 = 0x1000b`, `a1 = player+0x34`) e também em
  > `0x8003cf10`. O nome "tiro" segue **DECLARADO** (o call site é provado; o par id→ação não
  > foi confirmado por ouvido). Sinal a favor: `C_00`/`C_01`, os bancos de **menu**, são os
  > únicos que **não** definem o id 11.

### 2.2 Como o disparo vira HIT — ✅ RESOLVIDO (corrige o "negativo" da 2ª passada)
> **A conclusão antiga estava ERRADA.** O tiro **APLICA** dano ao inimigo, e a rotina foi isolada.
> Ferramenta: `python tools/exe_ai.py dmg` (matriz completa) / `python tools/exe_combat.py` (resumo).

O disparo é resolvido pelo **handler de arma** (tabela `0x8009ce88[weapon]`; ex. handgun trampolim
`0x8003e494` → subcaso `0x8003e4d0`). No **frame de disparo** (arco de mira validado por `slt`), ele
calcula o ponto do cano (`0x8008a0e4`) e chama **DUAS rotinas de dano por VARREDURA**:
- **`0x80044804` (CONTACT_A)** e **`0x80047860` (CONTACT_B)** — a mesma dupla que o **inimigo** usa p/
  bater no player. Elas percorrem o **array de personagens** `0x800ccd9c .. *(0x800cce3c)`
  (gamestruct+0x2664..+0x2704), acham o char **mais próximo** cuja hitbox cai na linha de tiro e fazem
  **`char+0xcc -= dano`** (base em **registrador `$s2`**, não hardcoded no player → é a "irmã genérica"
  de `0x8003dd7c`). Sítios do `sh 0xcc`: `0x80044d4c`/`0x80044e0c`. Retornam o ptr do char atingido. ✅
- Args do handgun (`0x8003e7dc`): `a0`=ponto do cano, `a1 = *(0x8009dbb4 + player+0x4a*4)` (= `0x8009d934`),
  `a2 = player+0x46` (weapon id).

**Dano = `*(rowptrs[alvo+0x4a] + (weapon-1)*8) & 0x3ff`** (10 bits). Tabelas: **§2.4**. ✅

⚠ O que a 2ª passada errou: rastreou só o caminho `0x8003adc0→0x80027940` (que de fato só faz recuo/anim);
o dano vive no **handler de arma** (`0x8003e4d0`+), que a 2ª passada não abriu até o `jal 0x80044804`.
`player+0x16c/0x170` (alvo travado) continuam sendo só aim-assist — a mira aponta nos **ossos do 0xD4**
(auto-lock), mas o **HIT** é resolvido contra a **hitbox do char-struct** por varredura (dois sistemas).
(A nota sobre o cluster `0x80091000..` = libc continua válida.)

### 2.4 TABELA DE DANO arma-vs-inimigo  ✅ (isolada)
Encadeamento: `0x8009dbb4[postura]` (16 ptrs, todos → `0x8009d934`) → `0x8009d934 + (weapon-1)*0x20`
(descritor de ataque por arma: hitbox em `+0x0/2/c/e/10/16`, **`+0x1c` → `0x8009d874`**) →
**row-ptrs `0x8009d834[alvo+0x4a]`** (classe do alvo = 16..48) → registro de **8 B por arma**;
**dano = `word0 & 0x3ff`**, `hword+4 & 0x1f` = tipo de reação/parte.
- **Linha default `0x8009d0f4`** (tipos 16-31, 38-47) — dano por índice de arma (weapon-1):
  ```
  w1=10  w2=16  w3=16  w4=100  w5=600  w6=100  w7=110  w8=200
  w9=140 w10=800 w11=13 w12=50 w13=16 w14=8 w15=8 w16=100
  ```
- **Linhas por-tipo (RESISTÊNCIAS)**: tipo32 `0x8009d194`, tipo33 `0x8009d234`, tipo34/36 `0x8009d2d4`,
  tipo35/40 `0x8009d374`, tipo37 `0x8009d414`, tipo48 `0x8009d4b4`. Ex.: **tipo48** é blindado
  (w5 magnum 600→**65**, w10 rocket 800→**350**, w4 granada 100→**42**); tipos 34/36 e 35/40 recebem
  **200** na arma w7 (vs 110 default = provável munição de granada dedicada). Matriz completa:
  `python tools/exe_ai.py dmg`.
- ⚠ Correção a §3.2 do `exe_ai.md`: `0x8009cf28` (21×3B) é **timing/munição** (frame de disparo), **não**
  dano — a tabela de dano-vs-inimigo é esta (`0x8009d834/0x8009d0f4`).

### 2.5 HITSCAN vs PROJÉTIL + timing de disparo/rearme  ✅ (fecha `aim_shoot`)
**Tabela de handler de disparo por arma `0x8009ce88` (16 ptrs):**
```
w0  -> 0x8003e494   FACA (melee/contato)
w1..w9, w11..w13, w15 -> 0x8003eb28   ARMA GENÉRICA (hitscan)
w10 -> 0x800408c4   ROCKET LAUNCHER (handler dedicado = projétil/AoE)
w14 -> 0x8003ff9c   GRANADA (handler dedicado = projétil/AoE)
```
- **HITSCAN (maioria das armas):** o handler genérico `0x8003eb28` chama a varredura **`0x80044804`**
  (+ `0x80047860`). `0x80044804` inicializa a distância mínima em **`0x7fffffff`** (`lui 0x7fff;ori 0xffff`),
  monta a matriz de transformação GTE (`0x800894a4`+`0x80089024`), **itera o array de personagens**
  `gs+0x2664..*(gs+0x2704)` (=`0x800ccd9c..`), acha o char **mais próximo** cuja hitbox cai na linha de tiro e
  aplica `char+0xcc -= dano` **no mesmo frame**. **Não** existe entidade-bala com velocidade nesse caminho →
  é **hitscan/raycast instantâneo**. (A "bala" visível é só flash/tracer; a resolução do acerto é geométrica.)
- **PROJÉTIL/AoE (rocket w10, granada w14):** handlers dedicados (`0x800408c4`/`0x8003ff9c`), fora da varredura
  hitscan — spawnam objeto/explosão (área). *(A física do projétil em si é da unidade de objetos T64, não do
  player.)*
- **Timing de disparo/rearme — `0x8009cf28` (21×3B, `byte2 & 0x7f` = frame do tiro dentro da anim de mira):**
  faca w0=**50**, handgun w1/w2=**12**, w3/w18=**27**, w4=**23**, magnum w5/w6/w7/w8=**30**, w9=**50**,
  rocket w10=**50**, w11=**8**, w12=**12**, w13/w14=**8**, w15=**11**, w16/w17=**14**, w19=**30**, w20=**32**
  (frames a 30 fps). O **recuo/tremor** é `0x80048308` (não é dano). Ao concluir o tiro a rotina 7 sub3
  transiciona `sw 0x60501/0x80501,4` → volta à **rotina 5 (ready)** = ciclo de **rearme**; flag de flash/recarga
  em `player+0x12d | 0x80`.

### 2.3 DANO AO PLAYER + estados FINE/CAUTION/DANGER  🎯✅
- **HP:** `u16 player+0xcc` (`0x800ccc90`), **máx `u16 player+0xce`** (`0x800ccc92`, =200).
- **Função de DANO ao player: `0x8003dd7c`** — `a0` = dano, `a1` = modo.
  ```
  lhu $v0,0xcc($a2)      ; HP  (a2 = player, via 0x800d0000-0x343c = 0x800ccbc4)
  subu $a0,$v0,$a0       ; HP - dano
  sh  $a0,0xcc($a2)
  ... se HP<0: sh zero,0xcc ; seta flags de morte em player+0xd2 (bit 0x800 -> byte 0xd3|0x08)
  ```
  Modo `a1`: casos de "matou / quase-matou" setam `player+0x12d|0x80` (flash) e rumble (`gamestruct+0x2120|0x20000`).
- **Função de CURA: `0x8003de5c`** — `HP += a0`; **clampa a `player+0xce` (máx)** (`lh 0xce; slt`).
- **Byte de condição `player+0xd3`** (`0x800ccc97`): `0x04 = FINE` (GameShark). Zerado no init do player
  (`0x8006d910`, spawn em `0x8006d8c0`).
- **Zonas de ANIMAÇÃO (mancar), via HP → motionType (§0):** FINE `HP≥101`, CAUTION `21..100`, DANGER `<21`.
- **ECG / classificador de condição: `~0x80038080`** (roda todo frame). Normaliza o HP para 0..0xff e
  seta flags de banda em `gamestruct+0x20f8`: `0x1000` (<0x30 → vermelho/danger), `0x8000` (<0x50 → caution),
  `0x2000` (≥0xb1), `0x4000` (≥0xd1 → verde/fine). Limiares `0x30/0x50/0xb1/0xd1/0xff` sobre o valor escalado.

---

## 3. MÁQUINA DE ESTADOS DO PLAYER (completa)  ✅  — `player_sm`

### 3.1 Ações macro — tabela `0x8009cd40`, índice `player+4`
| a | endereço | papel | dispatch interno |
|---|---|---|---|
| 0 | `0x80038e50` | idle-macro | — |
| 1 | `0x80039020` | **on-foot** (locomoção/mira/tiro) | 2× por `player+5`: `T1_move 0x8009cd60`, `T2_anim 0x8009cda0` |
| 2 | `0x8003d14c` | **acerto/hit conectado** (target = `&enemy+0x34`) | — |
| 3 | `0x8003d9e0` | **DANO/reação** | por `player+5` via tabela `0x8009ce80` |
| 4 | `0x800601f0` | **evento / objeto especial** (campos +0x144/+0x14c) | por `player+5` via tabela `0x8009ee44` |
| 5 | `0x8003dc14` | arma postura B | por `player+0x4a` via tabela RAM `0x800cc920` (runtime) |
| 6 | `0x8003dc80` | arma postura C | por `player+0x4a` via tabela RAM `0x800cca20` (runtime) |
| 7 | `0x8003dcdc` | **empurrar/mover objeto** (`player+0x160`) | por `player+5` |

O dispatcher da SM é **`0x80038c7c`**: `idx = player+4`, tabela `0x8009cd40`, `a1=player+0xe8`,
`a2=player+0xec` (banco EDD default). Depois roda a cadeia de pós-processo
`0x80045094 → 0x80045950 → 0x80040d40 → 0x80040ddc → 0x80040e80` (colisão/integração).

### 3.2 Rotinas (`player+5`) da ação on-foot
| r | move / anim | comportamento | input (pad lógico `s1`) | anim (`0xc8`) |
|---|---|---|---|---|
| 0 | `910c`/`9294` | **idle/parado** (sub-estados via jump-table `0x80010750`; fidgets via rand) | — | {2,5,8}/zona; fidget 11/12; wait 21 |
| 1 | `957c`/`97dc` | **andar FRENTE** + **roteador-mestre** de transições | `0x1`=frente | {0,3,6}/zona |
| 2 | `9924`/`9b84` | **ré / giro-DOWN** | `0x200`=ré | {1,4,7}/zona |
| 3 | `9ccc`/`9f08` | **CORRER** frente | `0x4`=correr | 9(parado)/10(mov) |
| 4 | `a398`/`a574` | variante de frente | `0xa` | {0,3,6} |
| 5 | `e2a4`/`e2ac` | **levantar arma / ready** → r7 | (via r1) | — |
| 6 | `a664`/`a688` | **giro-180 / quick-turn** | — | {1,4,7} |
| 7 | `a7d0`/`a7d8` | **MIRAR + ATIRAR** (T1 stub; sub-estados em `player+6`) | mask `0x500`=mira/fogo | 13/14/15..20 |
| 8 | `b078`/`b080` | curto (volta action1) | — | 5 |
| 9 | `b1c4`/`b244` | **subir/descer** (entrada por flag global `&0x10` em `0x800d1f2c`) | `0x10` | 6/7 |
| 10 | `b4fc`/`b784` | ação empurrar/mover (roteador secundário; `&0xff`) | vários | — |
| 11 | `c738`/`c740` | transição → seta `player+5=0xc` | — | 0 |
| 12 | `ca80`/`ca88` | ação (anim 1/2/3) | — | 1/2/3 |
| 13 | `ce98`/`cea0` | ação (anim 18); seta `action=0x60501` | — | 18 |
| 14 | `b9fc`/`bca4` | ação (anim 9/10) | — | 9/10 |
| 15 | `bf28`/`c104` | ação | — | — |

> Notas: (a) o **dano/knockback do player** é a **ação a3** (`0x8003d9e0`, sub-tabela `0x8009ce80`) — não
> uma rotina de `player+5`. (b) r9 = subir/descer (escada/degrau, entrada por flag global — lê `bank1`
> de flags `0x800d1f2c & 0x10`, ver `exe_items.md §1`). (c) r5/r6/r7 = todo o pipeline de arma
> (ready → mira → tiro).
>
> **(d) r10/r12/r15 FECHADOS 100%** ✅ (desmontagem completa + prova de alcançabilidade + índice de anim).
> NÃO são scripts opacos. As DUAS metades (move `T1` e anim `T2`) de cada um foram desmontadas:
>
> **r10 — andar-para-FRENTE COM arma/mira integrada.**
> - `move` (**`0x8003b4fc`**) = roteador de locomoção: pad `s1` bit `0x1`→andar(`0x101`), `0xa`→r4(`0x401`),
>   `0x4`→r14(`0xe01`), `0x200`→ré(`0x201`)/r6(`0x601`); gate `player+0xae & 0x40`; giro `0x6e`±(turn-rate
>   de `0x8009cd3c`); avanço de frame (÷30, `multu 0xf0f0f0f1`); máscara de mira `0x100`/`0x400` c/ arma
>   equipada (`0x46`) e HP≥`0x15` → ready(`0x501`)/aim(`0x20701`).
> - `anim` (**`0x8003b784`**) = driver de mira/fogo por sub-estado `player+6`: ponto do cano `0x80018d34`,
>   SFX de tiro `0x800776b0`, flash `gs+0x75e8|=4`, recuo `0x80027940`. Escreve `player+0xc8` (em `0x8003b910`)
>   = **linha {0,3,6}** da tabela 3×3 `0x8009cde0` (offset **+3**, por zona de saúde) `| 0x0007<<16`.
> - **Alcançado por:** r1 (roteador-mestre) em **`0x800396a0`** (após `0x8003c390 & 0x1000` → `0x20a01`/`0xa01`)
>   e r14 em **`0x8003ba74`**. (Provado por busca de escritores de `sw ...,4($player)` c/ routine=10.)
>
> **r15 — ré/DOWN COM arma/mira integrada (evento scriptado).**
> - `move` (**`0x8003bf28`**) = irmão de r10 p/ contexto de ré: testa `0x201/0xa/4/1/2/8` e mira `0x100`/`0x400`
>   → andar(`0x101`)/correr(`0x301`)/ready(`0x501`)/mira(`0x20701`); chama `0x8003c5b0`.
> - `anim` (**`0x8003c104`**) = mesmo driver de mira/fogo; escreve `player+0xc8` (em `0x8003c2a4`) = **linha {1,4,7}**
>   da tabela 3×3 (offset **+6**, por zona de saúde) `| 0x0007<<16`.
> - **Alcançado por:** r2/ré em **`0x80039a4c`** E por **5 sítios da VM de script de sala/eventos**
>   (`0x8005a9fc`, `0x8005aa50`, `0x8005b334`, `0x8005ba2c`, `0x8005c354`). Gatilho de evento típico
>   (`0x8005a9fc`): `if (gs+0x75ea & 3)` → `sw 0xf01,4` (routine 15). Logo r15 = mira/andar em **contexto de
>   evento** disparado pelo bytecode da sala.
>
> **r12 — animação scriptada de evento (anim 1/2/3).**
> - `move` (**`0x8003ca80`**) = **stub** (`jr $ra; nop`, 2 instruções — confirmado).
> - `anim` (**`0x8003ca88`**) = ação de animação scriptada; escreve `player+0xc8` = **anim1** (`0x70001`
>   @`0x8003cadc`) / **anim3** (`0x8003cbbc`) / **anim2** (`0x8003cd70`) / **anim1** (`0x8003cd78`); passos com
>   SFX `0x800776b0`, recuo `0x80027940`, e chamadas de evento `0x80034124`/`0x8004d720`/`0x80038678`/
>   `0x80038704`/`0x8003e088`; zera `+0x5/+0x6/+0x7` e limpa gate `gs+0x77f4 & ~0x100` no fim (`0x8003ce6c`).
> - **Alcançado por:** r11 em **`0x8003c8a4`** (confirma "r11 seta player+5=0xc") E pela **ação macro a4**
>   (evento/objeto especial, `0x80060ad8`/`0x80060b6c`, gate bit `&4`). Nenhum escritor via constante fora
>   desses (busca exaustiva de `sb ...,5` / `sw ...,4` com routine=12).
>
> Ferramentas de prova: dump de todos os 168 escritores de `player+0xc8` e dos escritores de
> `action|routine` (`sw/sh ...,4`) por propagação de constante sobre `disasm_all()`.

---

## 4. item_logic  🟡 → ver [`exe_items.md`](exe_items.md) (banco de flags `0x8009e3f8` fechado)
> **Atualização:** o sistema de **flags de progresso** e o **formato do inventário** foram fechados em
> [`exe_items.md`](exe_items.md): banco `0x8009e3f8` (16 ptrs; `bank1=0x800d1f2c`=progresso),
> SET/CLEAR `0x800512fc`/`0x8005472c`, CHECK `0x800546cc`, uso/consumo de item `0x8006d0a8`.
> Falta só o "pegar item" (add-to-inventory). Endereços úteis originais abaixo:

Acesso é por ponteiro-base + offset (não `lui` absoluto), por isso `find_hi_lo_refs` não os pega.
- **Inventário (10 slots):** base `~0x800d225e` (GS "10-slot" `800D225E 000A`).
- **Uso ilimitado de item:** patch em `0x8006d0ca` (`8006D0CA 2400` = `nop` no decremento) → o
  **decremento de quantidade de item** vive perto de `0x8006d0ca`.
- **Flags de mapa/progresso:** `~0x800d2127..0x800d212e` (GS de mapas); epílogos `0x800d1f3e`.
- **Init do player-struct:** `0x8006d8c0` (zera condição `+0xd3`, action `+4`, e escreve config
  `+0xd0..+0xd8`; `player+0x28 = char id`).
- Cruzar com `godot/data/sce_items.json` e o opcode `0x68` (`sce_item_aot_set`) já documentados.

---

## 5. Mapa de offsets do player-struct (consolidado)
Base `0x800ccbc4`. ✅=provado, 🎯=GameShark, 🟡=inferido.
```
+0x04 action (macro)        ✅   +0xc9 frame                 ✅
+0x05 routine               ✅   +0xcc HP  (u16)         🎯✅  (0x800ccc90, max 200)
+0x06 sub-estado (r7/idle)  ✅   +0xce HP max (u16)          ✅  (0x800ccc92)
+0x28 char id               ✅   +0xd2 flags de condicao(u16)✅
+0x34 pos X (s32)           ✅   +0xd3 byte de condicao      🎯  (0x800ccc97, 0x04=FINE)
+0x3c pos Z (s32)           ✅   +0xe3 debounce do gatilho   ✅
+0x46 weapon equipada       ✅   +0xe4 ptr props da arma     🟡
+0x4a estado/postura arma   ✅   +0x12d municao/flag flash   ✅
+0x6e angulo de direcao 12b ✅   +0x132 flags               ✅
+0xc0 pitch/offset de mira  ✅   +0x15c ptr alvo (facing)    ✅
+0xc7 part-id atingido      ✅   +0x160 ptr objeto (empurrar)✅
+0xc8 indice de anim (0..21)✅   +0x16c/+0x170 ptr do ALVO   ✅  (=&enemy+0x34)
+0xd8/+0xda yaw/pitch mira  ✅   +0x124/126/128 ponto do cano✅
+0xe8/ec EDD/EMR default    ✅   +0xf0/f4, +0xf8/fc bancos PLW (postura) ✅
```

---

## 6. Fontes externas (guia, não verdade final — o binário é a verdade)
- GameShark RE3 Nemesis NTSC-U: vida infinita Jill `800CCC90 00C8`; always fine `300CCC97 0004`;
  inventário 10-slot `800D225E 000A`; uso ilimitado `8006D0CA 2400`; mapas `300D2127/300D212B`.
  - almarsguides.com/retro/walkthroughs/ps1/games/residentevil3nemesis/gameshark
  - supercheats.com/playstation/residentevil3nemesiscodes.htm
  - residentevil.org/threads/resident-evil-3-nemesis-gameshark-codes.7062
- Fórum de modding (offsets/disassembly RE1/2/3): tapatalk residentevil123 ("Memory Offset List",
  "PS1 Disassembly"). Nomes reais de função vêm do `MAIN.SYM` do protótipo Bio2.
- Todos os endereços/offsets acima foram **verificados no disassembly** do `SLUS_009.23`.
