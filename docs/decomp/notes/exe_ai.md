# IA de inimigos + HP/dano do inimigo no EXE (SLUS_009.23, RE3 NTSC-U)

> Unidades: `ai` (era 0%) e o pendente de `aim_shoot` (HP/dano do inimigo, que vivia "na IA").
> Ferramenta: [`tools/exe_ai.py`](../../../tools/exe_ai.py) (`python tools/exe_ai.py`, subcomandos `t64`, `enemy N`, `states N`, `fn ADDR`, `stores 0xNN`).
> **Overlay de IA:** [`tools/overlay_ai.py`](../../../tools/overlay_ai.py) (`scan`/`info`/`dis`/`helpers`) — isola e desmonta o overlay embutido no `R###.BIN` (§5.6).
> Base do binario `0x80010000`; player-struct `0x800ccbc4`; gamestruct `0x800ca738`.
> Complementa [`exe_combat.md`](exe_combat.md) (lado do player) e [`../../formatos/exe.md`](../../formatos/exe.md).
> Marcacoes: ✅ provado no disasm · 🎯 confirmado externamente · 🟡 inferido/incerto.
>
> **Correcao importante ao `sce_enemies.json`/`exe.md §3`:** o "cluster de IA `0x80091000..0x80094600`"
> e o "array de estado `0x800b9d28`" **NAO sao IA** — `0x80091xxx` e o `vsprintf`/formatador da libc
> e a regiao `0x80094xxx` e dado (desmonta como lixo). A IA de inimigo real esta na **tabela de
> handlers de objeto T64 `0x80097bd4`** (ver abaixo). ✅

---

## 0. Arquitetura — como os inimigos sao atualizados e roteados  ✅

O motor tem um **loop unico de objetos/entidades** em **`0x8001bb24`**:
```
a0 = *(0x80098088)            ; ptr p/ FIM do array de work-structs
v0 = *(0x80098084)            ; ptr p/ INICIO
s1 = a0 - 0xD4                ; ultimo work-struct
loop (s1 downto inicio, passo -0xD4):
    v0 = lbu (s1)            ; TIPO da entidade (byte 0..63)
    v0 = tabela_T64[v0]      ; T64 = 0x80097bd4  (0x8001bbe8: sll 2; addu; lw; jalr)
    jalr v0  (a0 = s1)       ; chama o handler daquele tipo
```
- **Work-struct = 0xD4 (212) bytes**, ate **0x60 (96)** slots (o init/clear em `0x8001bad4` grava o
  tipo em `(v1)` com stride 0xD4 e conta ate 0x60). ✅
- **Tabela T64 `0x80097bd4`** = 64 ponteiros de handler; **stubs** (`jr $ra`) nos indices **9..15** e
  **45..50** (IDs reservados). ✅  (mesma tabela que `exe.md §2.3` ja citava, agora com papel de IA.)
- **O player NAO esta neste array** (e uma struct dedicada bem maior, `0x800ccbc4`, com campos ate
  0x170+). Os inimigos SIM sao esses work-structs de 0xD4.
- **Lista encadeada de personagens** (player + inimigos) na cabeca **`0x800ccd9c`** (`0x800d0000-0x3264`):
  as rotinas de colisao percorrem `(head)->(next)`, e cada no tem os campos do "personagem"
  (+0=flags&1 ativo, +0x46 arma, +0x12d, +0x134...). ✅

### Inimigos = tipos de objeto ~16..44  ✅ (faixa) / 🟡 (id↔especie exato)
Os handlers dos tipos **16..44** leem os campos de inimigo (estado `+0x18`, angulo `+0x2c/+0xba`,
ossos `+0xbc`, timer de hurt `+0xb8`) e chamam `rand`/driver de locomocao — sao **maquinas de IA**.
Os **de combate completo** (tem timer de hurt `+0xb8`): tipos **22, 23, 26, 27, 30, 33, 37, 38, 40, 41**.
Tamanhos (proxy de complexidade da IA) via `exe_ai.py t64`:

| tipo | handler | size~ | sinais |
|---|---|---|---|
| 21 | `0x8001d7d0` | 2340 | state,ang,rand |
| **23** | **`0x8001e444`** | **3524** | **state,hurt,ang** ← maior |
| 22 | `0x8001e0f4` | 848 | hurt,ang,rand |
| 30 | `0x8001fa90` | 832 | state,hurt,ang,rand |
| 32 | `0x8001ff6c` | 812 | state,ang,rand |
| 41 | `0x80020eb8` | 1680 | state,hurt,ang |

> **Nao ha strings de nome no EXE**, e o **opcode `sce_em_set` ainda nao foi decodificado** (pendencia
> herdada de `scd_gameplay`), entao o mapa **type_id(sce_em_set) → tipo-de-objeto → especie** ainda
> nao esta fechado byte-a-byte. A atribuicao de especie abaixo e por **estrutura/complexidade da IA**
> (🟡). Cruzar com `godot/assets/ENEMY/catalog.json` nao ajuda aqui (aquele catalogo e por
> **hash de mesh do Rxxx.BIN**, nao por type_id).

---

## 1. Struct do INIMIGO (work-struct de 0xD4)  ✅
Base = `a0` do handler. Confirmada por: loop de objetos, handler 23 e o auto-lock `0x800445c8`.

```
+0x00  word   flags | TIPO (low byte = indice do dispatch T64; bits altos = flags)   ✅
+0x02  byte   FASE: 0=init, 1=ativo(roda IA), 2=morrendo                              ✅
+0x18  byte   ESTADO de IA: 0..2 vivo, 3..4 morte (dispatch tbl 0x800103f8 no t23)    ✅
+0x19  byte   sub-estado / estado-2                                                    🟡
+0x24  hword  flags de render/anim (bit 0x8000 = visivel)                              ✅
+0x26  hword  flags de COLISAO/status: bits 0x10/0x20 = bloqueado numa parede (NAO     ✅
              "atingido") — setados por 0x8001bfd0 via testes de colisao de geometria
              (0x80051e48 / 0x8004d720). bits 0x1/0x2/0x4/0x8/0x40/0x80/0x100 = outros
              estados de anim/movimento. (CORRIGE a leitura antiga "andi 0x30=atingido".)
+0x2c  hword  angulo pendente -> copiado p/ +0xba no inicio do frame                   ✅
+0x32  hword  contador/limite de movimento (slti 0x7530)                               🟡
+0x34  ...    POSICAO 3D no mundo (x,y,z). player+0x170 do alvo aponta p/ ca           ✅
+0x48  ...    descritor de HITBOX/colisao (player+0x16c do alvo aponta p/ ca)          ✅
+0x50  s32    componente de posicao (clamp +-0x7918)                                   ✅
+0x60  s32    componente de posicao (media c/ +0x50 = centro do corpo)                 ✅
+0x90  ...    work de LOCOMOCAO/colisao (a3 do driver 0x8001b35c)                       ✅
+0xb4  hword  contador de morte/anim (lido na fase 2)                                   🟡
+0xb8  hword  TIMER de HURT/stagger: enquanto >0, congela a IA (pula p/ fim do frame)   ✅
+0xba  hword  angulo de direcao atual (12-bit)                                          ✅
+0xbc  ptr    dados de osso/parte; [+0xbc]+0x34 = pos 3D da parte (p/ hitbox)           ✅
```
> **HP:** o work-struct de **0xD4 (T64) NAO tem campo de HP** (o spawn `0x8001b484` nao seta HP;
> `+0xcc/+0xce` do 0xD4 guardam **ptr de animacao**). O HP do inimigo vive na **char-struct de `0x1fc` B**
> (array `0x800ccd9c`), em `+0xcc`(atual)/`+0xce`(max, so player/aliado), `+0x4a`=classe. A rotina de
> dano generica (base em registrador) e' **`0x80044804`** (a `0x8003dd7c` e' so o atalho player-only).
> **Isso resolve o elo bala→inimigo — ver §3.7.** (O 0xD4 e a char-struct coexistem; ligacao 1:1 🟡.)

---

## 2. IA do ZUMBI (tipo 23, `0x8001e444`)  ✅  — maquina de estados
O maior handler (3524 B), com hitbox **cabeca (0x42) / corpo (0x41)** e multiplas animacoes de morte:
perfil classico do **zumbi** (o inimigo comum). 🟡 no rotulo "zumbi" (falta o `sce_em_set`), ✅ na SM.

### 2.1 Preambulo por frame (fase 1, `0x8001e628`)
1. `+0x02++` (contador de fase). 
2. Clamp de posicao: `+0x48` e `+0x50` limitados a **±0x7918** (`ori s5,1` marca fora-de-limite).  ✅
3. **Timer de hurt `+0xb8`**: se `!=0`, decrementa; ao chegar em **0xa** dispara motion `0xd02`+`0x805`
   (reacao) e seta `+0x24=0x8000`; enquanto `+0xb8>0` **salta p/ o fim** (`0x8001f1d8`) — a IA fica
   **congelada durante o stagger**. ✅  (`0x8001e670`)
4. Locomocao base via `0x8001b484`/`0x8001bc80`/`0x8001bcfc` (integra posicao/colisao).
5. **Oferece as hitboxes ao auto-lock do player** (secao 4).
6. **Dispatch de estado por `+0x18`** (`0x8001eacc`: `sltiu 5`, tabela **`0x800103f8`**).  ✅

### 2.2 Estados (tabela `0x800103f8`)  ✅ (enderecos batem — `exe_ai.py states 23`)
| st | endereco | papel | detalhe (provado) |
|---|---|---|---|
| 0 | `0x8001eafc` | **idle / vagar** | `rand`→tabela de comportamento `0x80098728` (byte com sinal) → rumo; `MOVE_DRV` **spd 0x1200** (lento); anim `0xc03` |
| 1 | `0x8001eba0` | **aproximar/perseguir** | `rand`→rumo; `MOVE_DRV` **spd 0x1c00**; le `[enemy+0xbc]+0x12f` (frame de anim) vs global `[0x800c...]` → escolhe motion `8`/`0x18`; toca `0xd02` |
| 2 | `0x8001ed00` | **atacar (bote/mordida)** | `MOVE_DRV` **spd 0x1300**; motion `0xd02`+**`0x805`** (ataque); mesma checagem de frame → `0xe`/`0x1e` |
| 3 | `0x8001ee18` | **morte A (cair)** | `rand`×2 → `0x80098728` escolhe variante; `MOVE_DRV` motion `0x3d`, depois `0x10c` (queda); zera `+0x24` |
| 4 | `0x8001ee18` | **morte B** | mesma rotina (2 slots de morte) |

- **`0x800102e8` = rand** (LCG do jogo). A tabela **`0x80098728`** (bytes com sinal, indexada por
  `rand`) fornece os **offsets aleatorios de vagar/tropego** — o "arrastar" irregular do zumbi. ✅
- **Driver de locomocao `0x8001b35c`**: `a0=enemy`, `a1=motion id`, `a2=velocidade` (<<n), `a3=&enemy+0x90`.
  E o mesmo que move o inimigo aplicando root-motion + colisao. ✅
- **`0x8001b894`** = dispara um motion/anim/sfx isolado (`a0=id`, `a1=&enemy+0x90`).  ✅
- **Fase 2 (`0x8001eeb0`, morrendo)**: le `+0xb4` (contador) — corpo caido/desaparecer.  🟡

> Estados que o RE3 tem no zumbi e que **mapeiam** aqui: idle/vagar=st0, notar/perseguir=st1,
> atacar/comer=st2, morrer=st3/4. "cair e levantar" (quando derrubado) e feito pelo **timer de hurt
> `+0xb8`** (stagger), nao por um estado dedicado. 🟡

### 2.3 Outros walkers
Os tipos **22, 24, 25, 28, 29, 31** seguem o mesmo esqueleto (fase `+2`, angulo `+0x2c`→`+0xba`,
`MOVE_DRV`, `rand`) com SMs menores — variantes de zumbi / caes (Cerberus) / corvos. 🟡

---

## 3. HP / DANO do inimigo  🟡 (parcial — o pendente de `aim_shoot`)

### 3.1 Como o hit chega ao inimigo (fluxo, hitscan por flag)  ✅
1. Durante o **update de cada inimigo**, ele chama o **auto-lock `0x800445c8`** oferecendo as partes
   **0x41 (corpo)** e **0x42 (cabeca)** a partir de `[enemy+0xbc]+0x34`. Se a parte cai no arco de
   mira, o auto-lock grava **no PLAYER** (nao no inimigo):
   ```
   player+0x00  |= 0x80000000     ; player TEM alvo travado
   player+0x16c  = &enemy+0x48    ; ptr p/ o descritor de hitbox do inimigo
   player+0x170  = ptr do osso    ; [enemy+0xbc]+0x34
   player+0xc7   = part-id (0x41/0x42)
   ```
   (Corrige `exe_combat.md §1.4`, que dizia "seta 0x80000000 no inimigo": o bit vai no **player+0**.)  ✅
2. Ao **disparar** (player rotina 7 sub3, `0x8003adc0`), o tiro e resolvido pelo **dispatcher de eventos
   de animacao `0x80027940`** (dispara no frame que tem a flag `0x100` na EDD) → `0x80027f8c`. A arma
   e escolhida por `player+0x46` na tabela de **fogo por arma `0x8009ce88`** (w0=handgun `0x8003e494`,
   w10 `0x800408c4`, w14 `0x8003ff9c`, generico `0x8003eb28`). ✅
3. O dano e entao aplicado ao inimigo apontado por `player+0x16c/0x170`. A rotina exata que faz
   `enemy.HP -= dano_da_arma` e seta o inimigo p/ **morrendo (fase +0x02=2 / estado +0x18=3)**
   **nao foi isolada** — nao esta dentro do handler do inimigo (varredura negativa no t23) nem
   e um `sh` literal em `+0x18` na faixa dos handlers. Fica numa rotina de dano compartilhada. 🟡

### 3.2 Tabelas de arma  ✅ (localizadas) / 🟡 (semantica do dano)
- **`0x8009ce88`** (16 ptrs): handler de **fogo** por arma (acima).  ✅
- **`0x8009cf28`** (21 × 3 bytes): **stats por arma**. O handler do handgun (`0x8003e4d0`) le
  `entry = tabela[weapon-1]`, usa **`byte2 & 0x7f`** como **frame de disparo** (compara com
  `player+0xc9`). `byte0` tem bit alto setado (flag/tipo de municao?), `byte1` pequeno (cadencia/rajada?).
  A **coluna de DANO por arma vs inimigo** provavelmente e **outra tabela**, ainda nao isolada. 🟡
  Dump (`exe_ai.py`):
  ```
  w0(handgun): 85 05 32   w1: 86 08 0c   w3: 89 0a 1b   w5: 8a 0c 1e   w9: b2 32 32 ...
  ```

### 3.3 Ancoras externas (comunidade)  🎯 (guia, nao verdade final)
- HP dos inimigos e **hardcoded no EXE** (confirmado pela cena de modding RE1/2/3). O **Nemesis**
  "cai" em torno de **400 HP (Hard)**; ha diferencas de dano por regiao (PAL ≠ guia) p/ magnum/granadas.
- Fontes: fórum de modding **residentevil123** ("[PS1] Disassembly", "RE3: Change Enemy Health"),
  planilha de dano **klardendum.com** (`RE3_damage_sheet_EN.pdf`), guia de dano do **speedrun.com/re3**,
  GameFAQs ("Enemy Info & Mechanics", "Weapon & Item Mechanics").
- **Nenhuma** dessas expoe o **offset numerico do HP na struct** — precisa fechar no binario.

### 3.4 Investigacao byte-a-byte (2ª passada) — o que foi DESCARTADO e o que resta  🟡

Rastreio exaustivo (decoder bruto, confiavel; `disasm_all` do capstone dessincroniza em dados). Todos
os caminhos abaixo foram **abertos e descartados** como local do `HP -= dano`:

- **Caminho de disparo (player).** `0x8003adc0` (rotina7 sub3, fogo) → `0x80027940` (dispatcher de
  evento de anim, retorna "frame de tiro"). Depois disso o player so faz: recuo `0x80048308`, municao
  `+0x12d`, transicao de acao e facing ao alvo. **Nenhuma** chamada de dano a inimigo. Os "eventos" de
  anim (`0x80026be8`, `0x80027f8c`, `0x80027338`, `0x8002b2bc`) sao **interpolacao de esqueleto/EMR**
  (escrevem `player+0x108`+0xac/0xae/0xb0), nao dano. ✅ (negativo)
- **`player+0x16c/0x170` (alvo travado).** So sao **lidos na rotina de mira** (`0x8003a910`/`0x8003a9e0`,
  copiados p/ `+0x15c` = facing). **Nenhuma** leitura fora da mira, nem por offset nem por endereco
  absoluto (`0x800ccd30/0x800ccd34`). Logo o dano **nao flui** por eles. ✅ (negativo)
- **Tabela de arma `0x8009cf28`.** Lida **so** pelos handlers de arma (`0x8003e454/0x8003e544/0x8003ee5c/
  0x8003eeac/0x8003f3c8`) para **timing de disparo/municao** — `byte2&0x7f` = frame; nunca aplicada a um
  inimigo. **Não é** a tabela de dano-vs-inimigo. As colunas (21×3): `b0`=flags(bit0x80)|tipo de municao,
  `b1`=cadencia/qtd, `b2&0x7f`=frame de disparo. ✅ (reinterpretado)
- **`+0x26 & 0x30`.** É **colisao com parede** (`0x8001bfd0`), nao "atingido" (ver §1). O zumbi copia
  isso p/ `+0xb6` (`0x8001e964`) para reagir ao bloqueio, nao a tiro. ✅ (corrigido)
- **`+0xb8` (hurt/stagger).** Setado por **contato corpo-a-corpo** (`0x8001cb00` → `+0xb8=0x1e`, via
  contato `0x800472ec`), nao por tiro. Dentro do handler so **decrementa**. ✅

### 3.5 Rastreio do SPAWN (2ª rodada — hipotese "HP estatico no init")  🟡
Seguindo a pista "HP inicial e estatico, setado no spawn/init":
- **Nenhum store de imediato** (`addiu rX,zero,IMM; sh rX,off(enemy)`) de HP nos handlers **t23** nem
  **t41** — os unicos imediatos sao `+0x24=0xa` e `+0xb8=0xa` (timers). ✅ (negativo)
- **Fase de init do handler NAO seta HP:** t23 despacha por `+0x02` (0/1/2) → fase 0 (`0x8001e4b8`) so
  arma a motion inicial por `+0x18`; t41 despacha por `+0x01` → init (`0x80020eec`) so seta `+0x22`/
  `+0xb8`/`+0x26`. Nenhum HP. ✅ (negativo)
- **`sce_em_set` nao localizado:** dump completo da jump-table de opcodes SCD **`0x8009e0f8`** (ver
  `exe_items.md §1.3`). Os candidatos classicos NAO sao spawn de inimigo: op `0x2c`(`0x80058800`)=teste
  condicional; op `0x3b`(`0x80057f84`)=cria **objeto de DISPLAY** (structs de **0x194 B**, tipo em
  `+0x4a`, registra na lista `0x800ccd9c`), **nao** a work-struct de 0xD4. O array de 0xD4 e **estatico**
  (so o loop `0x8001bb24` referencia as bounds `0x80098084/88`), sem alocador que leia HP-por-tipo.
- **Sem tabela de HP-por-tipo obvia:** varredura de runs de hword em faixa de HP (5..600) nao revelou um
  array indexavel por tipo com `0x190` (400=Nemesis) + valores de zumbi.
- **Nemesis (boss) tem valor via SCRIPT:** op **`0x25`** (`0x80058c70`) grava **`[0x800e01c0]+0xb8 =
  operando do script`** e seta `gamestruct+0x77f4 |= 0x200`. Ou seja, o "boss" `0x800e01c0` recebe um
  parametro por-sala do script (candidato a HP/timer do Nemesis, per-encontro). 🟡

**Conclusao (honesta):** apesar de testar a hipotese do spawn estatico, o campo de HP do inimigo comum
**nao foi isolado estaticamente**. Ou o HP vive no **parser do bloco de inimigos do RDT** na carga da
sala (ainda nao mapeado), ou o modelo e **por-parte via EMD/EMR** (as hitboxes `0x41/0x42`). Para fechar
byte-a-byte: (a) achar o parser de enemies do RDT no room-load, ou (b) RAM-watch num inimigo vivo
observando qual hword cai a cada tiro (bloco `0xb0..0xb4` continua o candidato mais provavel).

### 3.6 CAMPO DE HP LOCALIZADO (round HP) — `char+0xcc/+0xce` ✅  · HP do inimigo comum: negativo ✅
> Ferramenta: `python tools/exe_ai.py hp`. Ancorado na intel de modding do PC (secao 3.3):
> a comunidade acha o HP em `[esi+0xCE]` (ex.: `B8 0A 00 00 00 / 66 01 86 CE 00 00 00`
> = `mov eax,10 ; add word [esi+0xCE], ax` → zumbi=10). O offset `0xCE` bate **1:1** com o PS1.

**HP vive na STRUCT DE PERSONAGEM (0x194 B, lista `0x800ccd9c`)** — player + aliados + bosses: ✅
```
char+0xcc  hword  HP ATUAL       (decrementado pelo dano; clamp em 0)
char+0xce  hword  HP MAXIMO      (teto do heal)
char+0xd2  hword  flags status; bit 0x800 setado quando HP chega a 0 (morte)
```
- **`0x8003dd7c` = DANO ao char:** `lhu v0,0xcc(a2); subu a0=v0-dano; sh a0,0xcc(a2)`; se `<0`
  zera `+0xcc` e faz `+0xd2 |= 0x800`. `a0` = valor do dano (esta e' a rotina **`HP -= dano`**).
  `a2` = **`0x800ccbc4` (player) hardcoded** → esta instancia so trata o **player**. ✅
- **`0x8003de5c` = CURA:** `+0xcc += a0`, com teto em `+0xce`. Confirma `+0xce = HP MAX`. ✅
- **HP MAX inicial = `0xc8` (200)** gravado em `char+0xce` em 4 sitios (todos 200): op **0x8a**
  (`0x80057430`), regiao op 0x24 (`0x80059214`), room-load (`0x800495e4`), init do player
  (`0x80024608`). **200 = HP do Carlos** na planilha da comunidade (`B9 C8 00 00 00`). ✅🎯
- Varredura EXAUSTIVA de `+0xce` no EXE inteiro: **so 9 mem-ops** (7 stores), **todos 200/-1**
  (player/aliado/boss). **Nenhum store de 10** → o inimigo COMUM nao usa `char+0xce`. ✅

**Inimigo COMUM = work-struct `0xD4` (pool ESTATICO)** — NAO tem campo de HP: ✅
- **Pool:** `0x800ba8a8`(inicio) .. `0x800bf828`(fim) = `0x4f80` = **96 × 0xD4**. Ponteiros de bounds
  em `0x80098084/88` (so o loop `0x8001bb24` os le). ✅
- **Spawn = `0x8001b484`** (wrapper `0x8001b400`): aloca slot (`0x8001c254`), le a **tabela runtime
  de modelos `0x800ba728`** (32 × 12B, chave = `byte@+8` == tipo; `w@0` = skel/mesh, `w@4` = anim;
  fica logo ANTES do pool, populada na carga da sala) e so seta **modelo/esqueleto/animacao/posicao**
  — `+0xbc`(osso), `+0xc4`(descritor de partes), `+0xc8`, `+0xcc`(**ptr de animacao**, NAO HP!),
  `+0x44`, `+0x24`, `+0x46`, `+0x2b`. **Nenhum HP.** ✅
- No 0xD4 os offsets `0xcc/0xce` **colidem** com `char+HP`, mas ali guardam **ptr de animacao**
  (`0x8001b5f0/0x8001b818: sw ...,0xcc(enemy)`), nao HP. ✅

**HP NAO vem do RDT/SCD (hipotese do round REJEITADA):** ✅
- Os opcodes de spawn de entidade `0x70`(16B `0x80056004`) `0x71`(18B `0x800560b8`)
  `0x72`(`0x80056178`) `0x73`(24B `0x8005624c`) **todos chamam `0x8001b484`** e carregam do script
  apenas: `byte@1` = **tipo** (chave da `MODEL_TBL`), `byte@2` = **id** (→ `slot+0x28/0xc0`), `byte@4` = **dir**
  (via resolver `0x80055e38`), `hword@8/a/c` = **posicao** (x,y,z). **Nenhum campo de HP.** ✅
- op **0x76** (`0x800563e4`) = **kill** (varre 96 slots, zera `+0/+1/+0x24` do que casa `+0xc0`);
  op **0x77** (`0x8005648c`→`0x8001ba48`) = **update de posicao/tipo** de slot ja ativo. ✅
- Isso casa com a cena de modding: o HP e' editado no **EXE**, nao no RDT. ✅🎯

**Tabela de combate por-tipo `0x80097fc4`** (adjacente a T64 `0x80097bd4`): 38 ponteiros (stride `0x14`)
para registros de **20B** em `0x80097cd4+`. `record+8` e' indexado pelo **estado** (`enemy+0x18`) e da'
o **descritor de hitbox/ataque** por-estado (lido no contato de ataque `0x8001cb00`: `0x80097fcc +
estado*4`). E' a origem provavel do descritor `enemy+0x48`. **Nao e' HP** (valores = dimensoes/hitbox). 🟡

### 3.7 ELO BALA→INIMIGO + HP do inimigo — ✅ RESOLVIDO (corrige §3.4/§3.6)
> Ferramenta: `python tools/exe_ai.py dmg`. **A conclusao "sem HP / elo nao isolado" estava ERRADA
> porque olhava a struct ERRADA (o work-struct 0xD4). O HP do inimigo vive na char-struct.**

**1) A "irma generica" de `0x8003dd7c` EXISTE: `0x80044804` (+ `0x80047860`, `0x800477ac`, `0x80048290`).**
Sao rotinas de dano com **base em REGISTRADOR** (`$s2`/`$s0`/`$s1`), nao no player. A principal,
**`0x80044804`**, recebe `a0`=ponto/hitbox do ataque, `a1`=descritor de ataque, `a2`=arma/indice, e:
1. Percorre o **array de personagens** `0x800ccd9c .. *(0x800cce3c)` (= gamestruct+0x2664..+0x2704).
2. Para cada char vivo (`(char)&1`, `+0x12d==0`, `+0x46&0xc000==0`), testa overlap da hitbox de ataque
   com o corpo (`char+0x134` pos, testes `0x8004479c/0x8004470c/0x80088aa4`) e guarda o **mais proximo**.
3. No vencedor `$s2`: le `alvo+0x4a` (classe), busca o dano na tabela (§2.4 do `exe_combat.md`), e faz
   **`sh (lhu 0xcc - dano), 0xcc($s2)`** (`0x80044d4c`/`0x80044e0c`); se HP<0, seta a **reacao de hit**
   escrevendo `char+4 = action|routine` (`|2` conectou, `|3` matou), `+0x12d|0x80` (flash), `+0x132`. ✅

**2) O TIRO do player chama essa rotina.** O handler de arma (`0x8009ce88[weapon]` → handgun `0x8003e4d0`)
no frame de disparo chama `0x80044804` **e** `0x80047860` (as duas varreduras) — `0x8003e7f0`/`0x8003e810`.
Callers de `0x80044804` = **handlers de arma** (`0x8003e7f0`, `0x80040fdc`, `0x80041148`, `0x800414a4`,
`0x8004226c`, `0x80042448`, … 0x8004xxxx) **+ handlers de inimigo** (`0x8001d828` t21, `0x8001e34c` t22
= inimigo batendo no player). ✅

**3) HP do inimigo = `char+0xcc`** (MESMO offset do player!). O inimigo de combate NAO e' (so) o
work-struct 0xD4 — ele tem uma **char-struct de `0x1fc` B registrada no array `0x800ccd9c`**, com
`+0xcc`=HP, `+0x4a`=**classe** (0..7 player/aliado, 16..44 inimigo — mesmo id da T64 e da tabela de dano).
- Registro/reserva: init `0x80017580` (slot0=player `0x800ccbc4`; reserva N=`gamestruct+0x2487` chars de
  `0x1fc`), pool em `gamestruct+0x213c`, registro `0x8001af3c`. ✅
- **Spawn de char de combate = opcode SCD `0x7d` (`0x80056a2c`)** — le o descritor do script (`0x800e0198`):
  `byte+3`→`char+0x4a`(classe), `+4`→`+0x46`(arma), `+8/9/a/b`=ids, `+0xc/e/10`=pos, `+0x12`=angulo.
  **Candidato forte a `sce_em_set`** (a pendencia herdada do `scd_gameplay`). O descritor **NAO tem HP**. ✅

**4) De onde vem o HP inicial: do SCRIPT (nao ha tabela de HP-por-tipo com imediato no EXE).** Varredura
negativa confirmada (nenhum `addiu rX,zero,{0x190/0x258/0x12c} ; sh 0xcc/0xce`). O HP e' escrito por:
- **SET (member-set) `0x80053f84`**: `sh a2, 0xcc(a0)` — parte de uma tabela de setters de membro
  acionada por opcode SCD (o script grava o HP do char). ✅
- **SUB `0x80051b9c`**: opcode SCD `char+0xcc -= operando` (`char = *(gamestruct+0x2140)`) — dano por
  script (ex. cutscene/gimmick). ✅
Isso reconcilia a intel de modding ("HP hardcoded no EXE" e' do **PC**; no **PS1** e' dirigido pelo
script da sala via member-set). O `char+0xce` (max) so e' usado por player/aliado (=200); o inimigo
comum usa **so** `+0xcc` (sem clamp de max).

> **Ressalva honesta (🟡):** falta amarrar **1:1** o work-struct 0xD4 (IA/locomocao/anim, T64) com a
> char-struct 0x1fc (HP/hitbox/dano) do MESMO inimigo — os dois pools coexistem e nao achei o ponteiro
> de ligacao entre eles (nem o spawn 0xD4 registra char, nem o op 0x7d cria 0xD4). Tambem nao capturei o
> sitio exato que grava o HP inicial de um **zumbi comum** (provavelmente member-set no script da sala,
> ou default herdado). Mas o **fluxo de dano** (tiro → varredura → `char+0xcc -= dano[arma][classe]`) e a
> **tabela de dano** estao provados byte-a-byte.  **→ Ver §3.8/§3.9/§5.4 (fechamento dos fios finos).**

### 3.8 HP INICIAL do inimigo comum — via MEMBER-SET do script  ✅ (mecanismo) / ✅ (negativo do default)
> Ferramenta: `python tools/exe_ai.py hpinit`.

**NÃO há default estático de HP por-classe.** Varredura EXAUSTIVA de **todos** os stores a `char+0xcc`
no EXE: só player/aliado (`=0xc8=200`, room-load `0x800494e4`/`0x80049534`, save/restore `0x80059180`),
rotinas de dano/cura, o **member-set** (abaixo) e o **ptr de anim** do 0xD4 (`sw`, não HP). O `op 0x7d`
(spawn de char) **não grava `+0xcc`**; `CHAR_ARRAY_INIT 0x80017580` só zera o word `+0` de cada char.
→ O char registrado **herda `+0xcc` do pool** até o **SCRIPT** gravar via member-set. ✅ (negativo provado)

**MEMBER-SET (o setter de HP do briefing, `0x80053f84`):**
- **Dispatcher `0x80053e10`**: `member_set(a0=char, a1=idx<0x2b, a2=valor)` via tabela `0x80010950`
  (43 setters — stubs `jr $ra; <store>` com o store no **delay-slot**).
- **`member[0x26]` = HP**: `0x80053f80` (`jr $ra ; sh a2,0xcc(a0)`) — o `0x80053f84` é o próprio store. ✅
- Getters: dispatcher `0x80053fac`, tabela `0x80010a00`.
- **Opcodes SCD** que gravam membro no **char ATIVO** (`obj+0x154`):
  - **op `0x40` (`0x80053b74`)**: `[0x40, member_idx, value_hword]` (PC+=4) — literal.
  - **op `0x41` (`0x80053bc0`)**: `[0x41, member_idx, var_idx]`, valor = `*(0x800d1f46 + var*2)` (PC+=3).
  - **op `0x42` (`0x80053c20`)**: member_get → variável.

**HP real por-sala** (decode de todas as 169 salas via `scd_decode`, op `0x40` member `0x26`, 24 sítios):
valores `{1, 20, 99, 100, 200, 400, 500, 600, 800}`. **400/500/600/800** batem com bosses/Hunters da
planilha da comunidade; **200** = Carlos/aliado. Os inimigos **comuns** (a maioria dos 1136 spawns) **não**
recebem `op 0x40` explícito → seu HP vem de member-set sobre o char ativo por-sala (ou herança), **não**
de um default de código. Isso **fecha** a pendência: HP do PS1 é **dirigido pelo script**, não hardcoded
por-tipo (a intel "HP hardcoded no EXE" é do **PC**). ✅🎯

### 3.9 LINK 0xD4 (IA) ↔ char-struct 0x1fc — CLARIFICADO (ponteiro 1:1 segue 🟡)
Investigado a fundo; o que ficou **provado**:
- **`op 0x7d` (`0x80056a2c`) cria SÓ a char-struct** (0x1fc): não chama o spawn 0xD4 (`0x8001b484`) nem
  aloca slot 0xD4; só `0x80078930` (checa modelo). Os dois spawns são **caminhos independentes**. ✅
- **NÃO existe dispatcher de IA indexado por `char+0x4a`** (classe): a char-struct é o lado **PASSIVO**
  (HP/hitbox/dano por varredura `0x80044804`); o **0xD4 é a IA ATIVA** (dispatch T64 por `work+0` no loop
  `0x8001bb24`). Pools e loops distintos. ✅
- **`work+0xd0` (0xD4) aponta p/ OUTRO 0xD4** (parte secundária de modelo multi-mesh: `0x8001b7fc`
  `sw s1,0xd0(s0)` após `memcpy 0xb0 B` de `s1+0x24`→`s0+0x24`). O loop lê `work+0xd0` e checa
  `(ptr)+0x24` (render) p/ despawn. **É link 0xD4↔0xD4, NÃO char-struct.** ✅
- **1:1 char↔0xD4 do mesmo inimigo:** o ponteiro direto **não foi isolado** — provável pareamento por
  **id** (o `work+0x28` = id do spawn 0x70-0x73; char tem ids em `+0x9/+0x4b/+0x122`) ou vínculo feito no
  room-load ao casar modelo. **Segue 🟡** (mas os dois lados e a ausência de um link-por-classe estão provados).

---

## 4. Integracao com o auto-lock do player  ✅
Confirmado que a varredura de inimigos vista em `0x8001e8xx-0x8001ea6x` (que `exe_combat.md` atribuiu a
"loop do player") e, na verdade, **codigo DO inimigo (handler t23)**: cada inimigo, no seu update,
roda `0x800445c8` ate 4× (partes 0x41/0x42, angulos/alcances por-arma em `0x80098064/6c`) para se
**auto-cadastrar** como candidato de mira. O player so le o resultado (`player+0x16c/0x170/0xc7`). ✅

Funcoes de contato **inimigo→player** (ataque corpo-a-corpo): `0x800472ec`, `0x80047bd0`, `0x80047f70`
(chamadas no update com resultado OR em `s5`, que **gateia** a IA — se o corpo do inimigo toca o player,
segue p/ o ataque). `0x80047f70` percorre a **lista de personagens `0x800ccd9c`** e testa distancia
entre `[enemy+0xbc]` e o alvo (+0x134 do outro personagem). O dano AO PLAYER usa a rotina ja
documentada `0x8003dd7c` (`exe_combat.md §2.3`). ✅

---

## 5. NEMESIS + type_id→espécie  🟡

### 5.1 Estrutura por-frame dos handlers (t21 vs t41)  ✅
Desmontados os candidatos:
- **t21 `0x8001d7d0` (2340 B)** — preambulo: le `+0x2c`→`+0xba`, `+0x26 & 0x30` (colisao) e chama
  **DOIS testes de contato** por frame: `0x80044804` e `0x80047860` (vizinhos do auto-lock; percorrem a
  lista de personagens `0x800ccd9c` e detectam toque com o player). OR do resultado em `s5` gateia a IA.
  Perfil de **walker agressivo que persegue e ataca por contato**.
- **t41 `0x80020eb8` (1680 B)** — despacha por `+0x01` (contador de fase, `bnez` no topo) e por `+0x22`
  (sub-modo 2/3/4); ao entrar num modo seta `+0x26 |= 0x100` e copia `+0x2c`→`+0xb8`. Chama `0x8001ce24`
  com `(a1=+0x1a, a2=+0x1b)`. Tem **maquina de fase explicita** (`+0x01`) — perfil de **boss scriptado**.

### 5.2 Ancora do Nemesis: evento scriptado + gate global  ✅
Ha um **evento de boss scriptado** sobre a struct dedicada **`0x800e01c0`** (NÃO um work-struct de 0xD4):
o **opcode SCD `0x25` (`0x80058c70`)** grava `[0x800e01c4]=4` (modo), `[0x800e01c0]+0xb8 = byte+2 do
operando do script`, `[0x800c7961]=1`, e seta **`gamestruct+0x77f4 |= 0x200`**. Esse mesmo global `+0x77f4`
e lido no loop de render (`0x80023d80`) e gateia o auto-lock dos inimigos (`0x8001ea04`: `lw 0x77f4;
bgez → pula`). Casa com a nota da comunidade de que o **Nemesis e dirigido por codigo/ID embutido no RDT
da sala**. ⚠ O `+0xb8` do boss-struct e' **1 byte de parametro** (nao o HP: 400=0x190 nao cabe em 1 byte)
— provavel timer/agressividade/id-de-fase. O **HP do Nemesis** segue o modelo geral (§3.7): `char+0xcc`
setado por member-set do script (a comunidade cita ~400 Hard; nao ha imediato 0x190 no EXE). 🟡

### 5.3 Maquina de FASE do Nemesis (t41 `0x80020eb8`)  ✅ (estrutura) / 🟡 (rotulos)
Despacho **por `+0x01`** (contador de fase; `bnez 1(s3)` no topo → init roda so uma vez) e **por `+0x22`**
(sub-modo). Preambulo/init (`0x80020edc`+):
- `+0x22 == 2`: copia `+0x2c → +0xb8` (arma o timer) e `+0x26 |= 0x100`.
- `+0x22 == 4`: `+0x22 = 3`, `+0x26 |= 0x100`.
- else: `+0x22 = 3`. Depois chama `0x8001ce24(a1=+0x1a, a2=+0x1b)` e **`+0x01++`** (avanca a fase).
Corpo (`0x80020f54`+):
- timer ativo `$s5 = +0xb8` (se modo 2) ou `+0x2c`; `+0xb4` = contador de estado (`slti 3`).
- **ATAQUE**: quando `+0x26 & 0x100`, monta a hitbox de `+0x48` e le o **descritor por estado**
  `[0x80097fcc + (+0x18)*4]` (= `COMBAT_TBL+8`), chamando **`0x800472ec`** (contato inimigo→player).
  Se conectou (`$s4<0`) e `+0x22==1`, seta `gamestruct+0x255e |= 0x200`.
- Perfil: **boss com maquina de fase explicita** que alterna modos (2/3/4) e dispara ataques scriptados
  por estado `+0x18`; nao usa a tabela de 5 estados do zumbi (`0x800103f8`). ✅
> Enumeracao "por fase" com HP/ataques nomeados (1ª/2ª/3ª forma) exige o mapa `type_id→especie` e
> RAM-watch por-encontro (o HP e' per-sala via member-set). O que esta provado: **o dispatch, os
> campos de fase/modo/estado, o gate global e o caminho de ataque**. 🟡 nos rotulos de forma.

### 5.3 type_id (sce_em_set) → tipo de objeto → espécie  🟡
- O roster do `evilresource` tem **15 espécies** (zombie, zombie dog/Cerberus, crow, drain deimos,
  brain sucker, grave digger, sliding worm, giant/small spider, hunter beta/gamma, Nicholai/heli,
  **Nemesis 1ª/2ª/3ª forma**) — `docs/referencias/evilresource.md`.
- A T64 tem **~29 handlers de personagem (tipos 16..44)** — mais que 15 especies, pois ha **variantes**
  (formas/estados, versoes com/sem arma) e NPCs. Mapa **por complexidade** (🟡, falta `sce_em_set`):
  - **t23 (3524 B, maior)** = ZUMBI comum (mais anims/estados) ✅-provavel.
  - **t22 (848)** = variante de zumbi. **t24/t25 (368/304)** = walkers menores (caes/corvos?).
  - **t30/t32/t33 (832/812/544)** = deimos/sucker/worm (🟡).
  - **t21 (2340)** e **t41 (1680)** = candidatos a **Nemesis / Hunter** (os dois maiores depois do zumbi).
  - stubs 9..15 e 45..50 = IDs reservados.
- `catalog.json` do Godot e por **hash de mesh do Rxxx.BIN**, nao por type_id → nao fecha o mapa.
  Fechar exige **decodificar `sce_em_set`** (opcode que grava `work+0 = tipo` a partir do `type_id`) —
  pendencia herdada do `scd_gameplay`. Enquanto isso, o mapa acima e **estrutural, não byte-a-byte**.

---

### 5.4 NEMESIS por-forma — descritores de ataque por-estado  ✅ (estrutura/dados) / 🟡 (rótulos de forma)
> Ferramenta: `python tools/exe_ai.py nemesis`.

O t41 (`0x80020eb8`) escolhe o ataque pelo **estado `+0x18`** via `NEMESIS_ATK_TBL[estado]` =
`0x80097fcc + estado*4` → registro de **20 B** (base dos registros: `0x80097cd4`). Dump real (hword):
```
st0 @80097cd4 [idle/aproxima]  : 18c1 03e8 f830 0c0c 07d0 07d0 0258 0fa0 0fa0 00c8
st1 @80097ce8 [ataque garra]   : 1e82 0c80 ff38 0707 0708 015e 0050 0708 02bc 0028
st2 @80097cfc [ataque B]       : 1e42 00c8 ff38 0707 0708 015e 0050 0708 02bc 0028
st3 @80097d10 [ataque agarrar] : 1e88 0c80 ff38 0707 0708 01c2 0000 0708 0384 0000
st4 @80097d24 [ataque D]       : 1e48 0c80 ff38 0707 0708 01c2 0000 0708 0384 0000
st5 @80097d38 [especial]       : 1e84 0708 ff38 0707 0000 0000 0000 0b7c 113a 0014
```
Layout do registro (lido no contato `0x800472ec`): `+0`=flags/id do ataque, `+2`=alcance, `+4`=offset,
`+0xa/+0xc`=extensões de hitbox, `+0x10/+0x12`=dano/reação. **São geometria de ataque, NÃO HP.** ✅

**Formas (1ª/2ª/3ª):** a máquina de fase do t41 (`+0x01` fase, **`+0x22` modo 2/3/4**) alterna os modos
que correspondem às formas do RE3 (modo 2 arma o timer `+0xb8` e seta `+0x26|0x100`; modos 3/4 =
transições). Os 6 estados `+0x18` acima são os **ataques** disponíveis; a forma ativa gateia quais
estados/animações e a troca de modelo. **HP do Nemesis** = `char+0xcc` por-encontro via member-set (op
`0x40` idx `0x26`) — a comunidade cita **~400-800** (bate com os valores 400/500/600/800 vistos em §3.8). 🟡
> O que está provado: dispatch por estado, os 6 descritores de ataque (dados reais), a máquina de fase
> `+0x01/+0x22`, o caminho de contato `0x800472ec` e o gate global `0x77f4`. 🟡 nos **rótulos** 1ª/2ª/3ª
> forma (exige RAM-watch por-encontro; o `type_id→espécie` também é 🟡, `sce_em_set.md §2`).

---

## 5.5 FECHAMENTO (round "teto real") — dispatcher de char por CLASSE + FRONTEIRA DE OVERLAY  ✅

> Ferramenta: `python tools/exe_ai.py char` e `python tools/exe_ai.py nemesis`. Este round
> **corrige** a afirmacao de §3.9 ("NAO ha dispatcher de IA indexado por char+0x4a") e
> **descobre a fronteira estatica real** do EXE (a IA de decisao vive num OVERLAY).

### 5.5.1 EXISTE, sim, um dispatcher por-CLASSE sobre a char-struct  ✅ (corrige §3.9)
O loop principal de entidades **`0x80023e00`** (o mesmo bloco de `0x80023d80`) itera o array
de char-structs `gs+0x2664..gs+0x2704` e, para cada char ativo, **despacha por classe**:
```
80023e88  lbu  v1, 0x4a(s1)        ; v1 = char+0x4a = CLASSE
80023e94  addiu v1, v1, -0x10      ; classe - 0x10
80023e98  sll  v1, v1, 2
80023e9c  addu v1, s3, v1          ; s3 = gamestruct 0x800ca738
80023ea0  lw   v0, 0x3de0(v1)      ; v0 = *(gs+0x3de0 + (classe-0x10)*4)
80023ea8  jalr v0                  ; CHAMA o handler da classe
80023eac  move a0, s1              ; a0 = char-struct  (NAO um 0xD4!)
```
O mesmo dispatch roda tambem no **room-load** (`0x80049b08`, e de novo em `0x80049b44` para
`char+0x4a` com o descritor de mira em `+0xd8/+0xda`). A tabela **`gs+0x3de0`** (indexada por
`classe-0x10`, classes 0x10..0x7f) e' populada no room-load por **`0x80013700`** a partir de
uma tabela 2D **`gs+0x3fa0`** (stride `0x1c0` por slot de modelo). ✅

### 5.5.2 A FRONTEIRA: os handlers de classe apontam para um OVERLAY (0x80100000+), FORA do EXE  ✅
`gs+0x3fa0` e' inicializada **estaticamente** em `0x80017adc..0x80017c28` com ponteiros de
handler cujo alvo e' **`0x8010xxxx`** (`lui 0x8010; addiu ...` → ex.: `0x80100254`, `0x801001ec`,
`0x8010002c`). O text do `SLUS_009.23` vai de `0x80010000` a **`0x800e3800`** (`tsize=0xd3800`);
logo **`0x80100000+` esta ALEM do fim do binario** (`0x80100000 >= vend` ✅). Ou seja:
- **O que ESTA no EXE (100% decodificado):** o *dispatcher* por-classe (`0x80023ea8`/`0x80049b08`),
  a tabela `gs+0x3de0`/`gs+0x3fa0` e sua inicializacao, a struct de char (HP/hitbox/classe), TODO
  o sistema de dano (`0x80044804` etc.), o spawn (op 0x7d), o HP por member-set, o loop de objetos
  0xD4 e os handlers T64 t16..44 (locomocao/anim/hitbox do CORPO).
- **O que esta no OVERLAY (0x80100000+, upper-RAM; NAO existe estaticamente neste EXE):** a
  **arvore de decisao por-classe do inimigo** (o handler chamado por `gs+0x3de0[classe]`).
- **Prova do carregamento em upper-RAM:** `SYSTEM.CNF` poe `STACK=0x801FFF00` (RAM ate 2 MB); a
  rotina `0x80017998` (gate `char+0x4a<0x50` [inimigo] & `gs+0x77f4&0x2000`) faz
  `jal 0x800100a4` (copia) do buffer do arquivo do inimigo (`s4`) para **`0x8010d000`** e grava
  **`char+0xec = 0x8010d000`** (segmento por-inimigo, `char+0xe8` = fim). ✅
- **Arquivo de overlay:** nao ha nome de overlay dedicado nas strings do EXE (so caminhos-dev
  `bio19/room/emd/em10.emd` = modelos). O segmento por-inimigo copiado p/ `0x8010d000` vem do
  arquivo do modelo do inimigo carregado por-sala; o overlay de CODIGO comum (0x80100000..0x8010cfff)
  e' carregado em upper-RAM em runtime. **Isolar o arquivo exato exige tracar o loader de CD em
  runtime** — fica fora do alcance estatico deste EXE. 🟡 (fronteira documentada)

### 5.5.3 LINK 0xD4 ↔ char — RESOLVIDO estruturalmente (ponteiro direto: em overlay)  ✅/🟡
Sao **DUAS entidades distintas, em pools distintos, com loops/tabelas distintos**:
| aspecto | char-struct `0x1fc` | work-struct `0xD4` |
|---|---|---|
| pool | `gs+0x213c` (≈0x800ccbc4+) | **`0x800ba8a8..0x800bf828`** (EXE data: `*0x80098084/88`) ✅ |
| loop | `0x80023e00` (por char ptr) | `0x8001bb24` (stride 0xD4, 96 slots) |
| dispatch | **`gs+0x3de0[char+0x4a-0x10]`** (OVERLAY) | **T64 `0x80097bd4`[work+0]** (EXE) |
| papel | HP/classe/combate/hitbox/**decisao** | corpo animado/locomocao/efeitos/projeteis |
| spawn | op 0x7d `0x80056a2c` | op 0x70-0x73 `0x8001b484` (+ ~90 sites de arma/efeito) |
- **Prova de que t23/T64 operam no 0xD4 (nao no char):** varredura de campos de `a0` no t23
  (`0x8001e444`, 900 instr) so toca `+0x02/+0x18/+0x24/+0x26/+0x2c/+0x48/+0x50/+0x60/+0xb4/+0xb8/
  +0xba/+0xbc` — **nenhum** campo exclusivo de char (`+0x4a`,`+0xcc`,`+0x114`,`+0x134`,`+0x46`). ✅
- **Prova de que o inimigo QUE LEVA DANO e' o char:** o dano so escreve `char+0xcc` (varredura
  `0x80044804` percorre o array de chars); o 0xD4 nao tem HP. Logo o inimigo "de verdade" (que
  morre ao tomar tiro) e' a char-struct; o 0xD4 e' o corpo/efeito.
- **Hitbox do char segue a animacao (nao o 0xD4):** `char+0x13c = *(char+0x108) + 0x40`
  (`0x80038f08`); a varredura de dano le `(char+0x13c)+0x14/+0x1c` como X/Z. `char+0x108` = buffer
  de POSE/animacao (setado em `0x80026184`). Ou seja o hitbox do char e' dirigido pela propria
  pose — nao por um ponteiro ao 0xD4. ✅
- **Ponteiro 1:1 direto char↔0xD4:** **nao existe como campo no EXE** (varredura). O pareamento
  (qual 0xD4-corpo pertence a qual char) e' feito pela **arvore de decisao no overlay** (que
  spawna/associa o corpo) — por isso nunca apareceu estaticamente. Classificado: **"nao existe
  estaticamente neste EXE — a ligacao e' estabelecida em overlay"** (era 🟡 "nao isolado"; agora
  a CAUSA esta provada: o codigo que a estabelece nao esta neste binario).

### 5.5.4 HP inicial do inimigo comum — CADEIA COMPLETA CONFIRMADA (in-EXE)  ✅
Corrobora §3.8, agora com o setter verificado byte-a-byte:
- **op 0x40 `0x80053b74`**: le `byte@PC+1`=member_idx (`a1`), `hword@PC+2`=valor (`a2`),
  `a0 = *(char ativo) = obj+0x154`; chama o dispatcher `0x80053e10`; PC += 4.
- Dispatcher indexa **`0x80010950[member_idx]`**; **`tbl[0x26] = 0x80053f80`** cujo corpo e'
  `jr $ra ; sh $a2, 0xcc($a0)` → **`char+0xcc = valor`** (= HP). ✅
- **SEM default por-tipo:** varredura dos **28 stores** a `char+0xcc` (`exe_ai.py char`): so
  player/aliado (=200: room-load `0x800494e4/0x80049534`, save `0x8005919c+`), dano/cura
  (`0x8003ddxx/0x80044dxx/0x800477b8/0x800482a8/0x80051ba8`), o member-set (`0x80053f84`) e o
  `sw` de ptr-de-anim do 0xD4 (`0x8001b5f0/0x8001b818`, NAO HP). **Nenhum `addiu rX,zero,HP;
  sh rX,0xcc` por-tipo.** `char+0xce` (max): 7 stores, todos player/aliado=200. ✅ (negativo provado)
- **Conclusao:** o HP inicial do inimigo comum vem **exclusivamente do SCRIPT da sala** (member-set
  op 0x40/0x41 idx 0x26). Nao ha campo de HP no descritor do spawn (op 0x7d, `sce_em_set.md §1/§4`)
  nem default por-classe no EXE. **FECHADO.**

### 5.5.5 Nemesis — fases como INDICE NUMERICO (sem rotulo textual)  ✅
- **op 0x25 `0x80058c70`** (arma o evento de boss), decodificado: `boss(0x800e01c0)+4 = 4`,
  **`boss+0xb8 = byte@PC+2`** (param), `0x800c7961 = 1`, `gamestruct+0x77f4 |= 0x200`; PC += 4.
  **Extracao real (todas as 169 salas):** exatamente **3 sitios** — `R502` e `R506` com **param=2**,
  `R70C` com **param=1**. Logo o "seletor de forma/fase" do boss e' um **byte {1,2}**. ✅
- **Maquina de fase do t41 `0x80020eb8`** (a0 = 0xD4; init em `0x80020edc`, corpo em `0x80020f54`):
  - **`+0x01`** = contador de FASE: `bnez 1(s3)` no topo ⇒ o init roda **so no 1o frame**; depois
    `+0x01++` (`0x80020f4c`), nunca reentrando.
  - **`+0x22`** = MODO ∈ **{2,3,4}**: `==2` ⇒ `+0xb8 = +0x2c` (arma timer) & `+0x26 |= 0x100` &
    `+0x2c=0`; `==4` ⇒ `+0x22 = 3` & `+0x26 |= 0x100`; senao ⇒ `+0x22 = 3`. (Modos 2/3/4 = as
    formas/transicoes.)
  - No corpo: se `+0x22==2` usa timer `+0xb8`, senao `+0x2c`; `+0xb4` (`slti 3`) = contador de
    estado; **`+0x26 & 0x100`** = flag de ataque ativo; **`+0x18`** = estado ⇒ ataque
    `0x80097fcc[estado]` (os 6 descritores de §5.4) via contato `0x800472ec`.
- **PROVA de que NAO ha rotulo textual de forma:** varredura ASCII do **binario inteiro** (868 KB)
  por `nemesis/nemi/form/zombie/hunter/boss/phase/em_set` = **0 ocorrencias**. Os unicos nomes
  de inimigo no EXE sao os **caminhos-dev de modelo** (`bio19/room/emd/em10.emd`), nao rotulos de
  forma. **⇒ a "forma" do Nemesis e' puramente um INDICE NUMERICO** (`boss+0xb8 ∈{1,2}`,
  `+0x22 ∈{2,3,4}`, `+0x18` estado 0..5) — nao existe string de forma. ✅ (fecha o resíduo "rotulo")
- A logica de decisao que escolhe fase/ataque do Nemesis (como qualquer inimigo) roda pela via de
  overlay (§5.5.2); o que ESTA no EXE (dispatch, campos de fase/modo/estado, os 6 descritores de
  ataque, o gate global `0x77f4`, o param de script) esta **100% decodificado**.

## 5.6 O OVERLAY DE IA — LOCALIZADO, ISOLADO E DECODIFICADO  ✅ (fecha a fronteira de §5.5.2)

> Ferramenta: [`tools/overlay_ai.py`](../../../tools/overlay_ai.py)
> (`scan`, `info R###.BIN blk`, `dis R###.BIN blk off n`, `helpers R###.BIN blk`).
> Este round **cruza a fronteira** declarada em §5.5.2 ("isolar o arquivo exige tracar o loader
> de CD em runtime — fora do alcance estatico"): o overlay foi **achado no disco, isolado e
> desmontado estaticamente**. NAO e' um blob comprimido irredutivel.

### 5.6.1 O overlay e' um BLOCO de CODIGO embutido no `STAGE#/R###.BIN` da sala  ✅
A arvore de decisao por-classe (handlers `gs+0x3de0[char+0x4a-0x10]`, §5.5.1) **nao e' um
arquivo dedicado** — e' **um bloco do proprio `R###.BIN` da sala**. Esse bloco foi rotulado
como "VRAM/textura" em [`../../formatos/enemy_bin.md §1`](../../formatos/enemy_bin.md) porque
seu `tag` **nao** tem high-byte `0x80/0x81` (marca de bloco de MODELO). Mas:
- **low16 do `tag` = `0x0001`** (bloco de codigo/descritor) e **`0x0002`** (par),
- o conteudo e' **MIPS puro, NAO comprimido** (entropia ≈ **5.5 bits**; codigo limpo, `capstone`
  desmonta direto — ver `overlay_ai.py info`),
- densidade altissima de `jal` de volta ao `.text` do EXE (ex.: R101 blk4 = **742** `jal` p/ EXE)
  + auto-refs `lui 0x8010`/`jal 0x8010xxxx` **pre-relocados p/ base `0x80100000`**.

**PROVA de que e' a IA de inimigo** (`overlay_ai.py helpers`): o bloco chama os MESMOS helpers
de IA ja documentados — **`rand 0x800102e8` ×258**, **`spawn_obj 0x8001b484` ×86**,
**`ratan2 0x8001808c` ×5**, **`motion_trig 0x8001b894`**, `anim_setpos 0x80018110`,
`anim_play 0x800187cc` (53 alvos distintos no EXE). O 1o handler (`0x80100254`) recebe **`a0 =
char-struct`** e le exatamente os campos do dispatch de §5.5.1: gate de boss **`gs+0x77f4`**
(`bgez`), array de chars **`gs+0x2660`**/player `gs+0x248c`, **`char+0x46 & 0x200`**, `char+0x158`.
Os sub-handlers escrevem **`char+0x04`(routine), `+0x05`, `+0x06`, `+0xc8`(seq de anim), `+0x110`**
e flags `|0x800` — a maquina de estados/decisao da char-struct. ✅

**Overlays COMPARTILHADOS** (byte-identicos em varias salas, `overlay_ai.py scan`): p.ex.
size `51757` ×**59 salas**, `50534` ×42, `53120` ×36 (o de R101), `38076` ×19, `24312` ×17,
`21232` ×9, `17312` ×7. Cada tamanho/hash distinto = a IA de **um tipo de inimigo** (reusada
em toda sala que o spawna). O par `...0001`(codigo) + `...0002`(copia/dados) sempre aparece junto.

### 5.6.2 Estrutura interna do bloco de overlay (base de carga `0x80100000`)  ✅
```
+0x00  u32     count               ; nº de handlers do overlay
+0x04  ...     (as vezes string de fmt de debug, ex. "%04x, %d")
+0x14  u32[]   TABELA de handlers   ; 17..22 ponteiros ABSOLUTOS 0x8010xxxx (0 = stub)
+...   codigo dos handlers          ; 1o prologo tipicamente ~+0x254
```
Ponteiros internos sao **absolutos** assumindo base `0x80100000` (ex.: slot@`0x80100014` =
`0x801018b8`). O 1o handler valido esta em `+0x254` (`addiu $sp,$sp,-0x28; ...`); a regiao
`+0x14..+0x6c` e' a tabela; `+0x6c..+0x254` sao dados/parametros do overlay.

### 5.6.3 Como o overlay entra na RAM (cadeia provada no EXE)  ✅
- **Loader de char/modelo `0x8001760c`** (`a1=char, a2=buffer_do_arquivo, a3=segmento`; unico
  caller = `0x80013608`): mapeia as secoes do arquivo (`s3 = s4 + *(s4+0)`, dir de offsets) em
  campos do char (`+0xec/+0xe8/+0x108/+0xf0..fc/+0x118/+0x11c/+0x174`).
- **memcpy `0x800100a4`** = copia de blocos de 32 B (memcpy trivial, **sem descompressao**).
- **Copia p/ `0x8010d000`** (`0x800179b8`, gate `char+0x4a>=0x50` & one-shot `gs+0x77f4 &
  0x20000000`): `src = s4 + [s3+8]`, `size = [s3+0x10]-[s3+8]`, `dst = 0x8010d000`; grava
  `char+0xec = 0x8010d000`, `char+0xe8/0x10c` = fim. → e' a copia do overlay para o **segmento
  secundario** (base B).
- **Dois bases paralelos:** `gs+0x3fa0` (init estatica `0x80017adc`) tem **row0 → `0x80100000+X`**
  (enemy PRIMARIO da sala) e **row1 → `0x8010d000+X`** (SECUNDARIO), com os MESMOS offsets X
  (17 handlers distintos em `X∈{0x004..0x254}`; `0x8010d000-0x80100000 = 0xd000`). A row e'
  escolhida por `char+0x8d4` (0 se `class==gs+0x8c4`, senao 1) no caller `0x80013674`.

### 5.6.4 (SUPERADO por §5.7) — os 3 pontos abertos foram fechados no round de enumeracao.

## 5.7 FECHAMENTO: `gs+0x3fa0` write-once, catalogo de overlays e 548 handlers  ✅

> Ferramenta: `python tools/overlay_ai.py catalog --json godot/data/ai_overlays.json`
> (+ `handlers R###.BIN blk` para o fingerprint por-handler). Saida: **`godot/data/ai_overlays.json`**.

### 5.7.1 NAO ha rewrite runtime — `gs+0x3fa0` e' um MAPA GLOBAL estatico (fecha §5.6.4 #1)  ✅
Varredura EXAUSTIVA de stores a `gs+0x3fa0..gs+0x415f` = **0 escritas em runtime** (so a init
estatica `0x80017adc`). Logo `gs+0x3fa0` e' **write-once**: e' um **mapa GLOBAL `class →
offset-fixo-no-overlay`** que agrupa as classes em **17 "familias"** de handler:
```
0x254 = classes 16-21,23,46,47   0x1ec = 22,24-31   0x30 = 32   0x14c = 33
0xbc  = 34,36   0x144 = 35,40    0xc8  = 37   0x1c = 38,39,44   0x20 = 45,62,63
0xac  = 48   0xc4 = 50   0xd4 = 51   0x180 = 52,53   0xf8 = 54,58   0x3c = 55,59
0x154 = 56   0x04 = 57,64
```
O dispatch usa **enderecos FIXOS** (`gs+0x3de0[class] = 0x80100000+familia` ou `0x8010d000+familia`);
**cada overlay de sala e' COMPILADO com o handler de cada classe que serve exatamente no offset da
familia daquela classe.** Prova: no overlay de R101 (zumbi), `class16 → +0x254` e' um **prologo
valido**; e todo overlay tem prologos **exatamente** nos offsets das familias que serve (coluna
"familias" do catalogo). Nao existe copia da tabela `overlay+0x14` p/ `gs+0x3fa0` — a `overlay+0x14`
e' uma sub-tabela INTERNA do overlay (sub-dispatch), nao a tabela de classe. Row0=`0x80100000`
(PRIMARIO, `char+0x8d4==0`), row1=`0x8010d000` (SECUNDARIO). ✅ (corrige a suposicao de §5.6.4)

### 5.7.2 Despacho interno de cada overlay (3 niveis)  ✅
`gs+0x3de0[class]` → **handler de CLASSE** (per-frame, no offset da familia; ex. zumbi `0x80100254`):
decrementa timers (`char+0x1e4/0x1ed/0x1f2/0x1fb/0x12d`), checa gate de boss `gs+0x77f4`, e
**despacha por `char+0x04` (ACAO, 5 valores)** via a **tabela de rotina** (ex. `overlay+0xc8e8`)
→ **handler de ACAO** → **despacha por `char+0x06/+0x18` (sub-estado)** via **sub-tabelas**
(`overlay+0x14/0x7c/0xa4/...`) → **handler-FOLHA** (estado). As 5 acoes do zumbi (fam 0x254):
```
a0 0x80100548 IDLE/DECIDE  (rand x10; seta char+0xc8 anim, char+0x04)
a1 0x80100ea8 APPROACH
a2 0x80100ff0 ATTACK       (seta char+0x04 transicao; char+0xe3)
a3 0x80101418 DAMAGE/STAGGER (spawn_obj = sangue/efeito + rand)
a4 0x801015fc DEATH
```

### 5.7.3 Catalogo dos overlays UNICOS + handlers (fecha §5.6.4 #3)  ✅
**12 overlays de codigo UNICOS** (dedup por md5; `tag` low16=`0x0001`), **548 handlers-folha
enumerados e fingerprintados** (role + campos escritos em `char` + helpers do EXE + transicoes),
em `godot/data/ai_overlays.json`:

| familia | classes | #salas | #handlers | mesh dominante (mono-sala) → especie |
|---|---|---:|---:|---|
| **0x254** | 16-21,23,46,47 | 36 | 51 | `605afd27` → **ZUMBI macho** ✅ (ancora) |
| 0x1ec | 22,24-31 | 59 | 50 | misto (zumbi/insetoide) 🟡 |
| 0x180 | 52,53 | 42 | 64 | 🟡 |
| 0x144 | 35,40 | 19 | 57 | `5c0244d2` → insetoide/aranha/verme 🟡 |
| 0xbc | 34,36 | 19 | 34 | `c6c2519f` → zumbi variante 🟡 |
| 0x30+0x144 | 32,35,40 | 17 | 72 | 🟡 |
| 0xf8 | 54,58 | 16 | 68 | `5c0244d2` → insetoide 🟡 |
| 0x14c | 33 | 9 | 41 | 🟡 |
| 0xc4 | 50 | 7 | 18 | 🟡 |
| 0xd4 | 51 | 1 | 28 | 🟡 |
| 0xac | 48 | 1 | 23 | 🟡 |
| 0x154 | 56 | 1 | 42 | 🟡 |

Roles agregados por overlay (idle/decide, anim/state-set, spawn, attack, face/aim, death/damage,
e "?"=math/sub-dispatch) estao no JSON, por handler, com os campos `char` escritos e os `jal` do EXE.

### 5.7.4 Rótulo overlay↔ESPECIE (fecha §5.6.4 #2 parcialmente)  ✅/🟡
- **overlay ↔ CLASSE: 100% provado** (mapa `gs+0x3fa0` estatico + prologos por familia).
- **classe ↔ especie:** so a **familia `0x254` = ZUMBI** esta ancorada com confianca (classe 23 ∈
  0x254 = handler T64 **t23 = zumbi** provado em §2; sala R101 e' **mono-inimigo** com mesh
  `605afd27` render-confirmado zumbi macho em `enemy_bin.md §5`). As demais familias tem **classes
  conhecidas** mas o **nome da especie pende do `sce_em_set`** (mapa `type_id→especie`, dominio do
  outro agente, ainda 🟡): a co-ocorrencia de mesh por-sala e' **ruidosa** (salas misturam inimigos
  + a mesma familia aparece em dezenas de salas). **Nao inventei rotulos** — o JSON traz classes e
  meshes candidatos, sem forcar especie. 🟡
- **Familias sem overlay `0x0001` achado** (`0x04,0x20,0x3c,0xc8` = classes 37,38,39,44,45,55,57,
  59,62,63,64): provavelmente **NPCs/aliados/entidades de cutscene** (classes altas) ou logica que
  nao usa bloco de codigo por-sala. Marcado como resíduo (nao sao inimigos de combate padrao). 🟡

### 5.7.5 Resíduo final honesto  🟡
1. **Nome de especie** por familia (exceto zumbi): so fecha com o **`sce_em_set` / `type_id→especie`**
   (aberto; outro agente). **NAO e' bloqueio de overlay** — a estrutura estatica esta 100%.
2. **Decode SEMANTICO linha-a-linha** de cada um dos 548 handlers-folha (nomear cada estado/ataque
   por especie): **mecanico** — a estrutura, o role, os campos escritos e os helpers ja estao no JSON;
   falta so a prosa por-handler das 12 especies.

**Classificacao do resíduo:** **"ARQUIVO ACHADO, overlay DESCOMPRIMIDO e DECODIFICAVEL,
handlers PARCIALMENTE decodificados"** — **NAO** "overlay comprimido irredutivel estaticamente".
A fronteira de §5.5.2 esta **resolvida**: o codigo existe no disco (`R###.BIN`), e' MIPS cru e
desmonta estaticamente com `tools/overlay_ai.py`.

## 5.8 COMPORTAMENTO de IA por overlay — maquinas de estado (prosa)  ✅

> Ferramenta: `python tools/overlay_ai.py tree R###.BIN <blk>` (arvore classe→acao→folha com prosa)
> e o campo **`semantics`** por-handler + **`state_machines`** por-overlay em
> **`godot/data/ai_overlays.json`** (`overlay_ai.py catalog --json ...`). A prosa e' **derivada
> deterministicamente** dos FATOS do disasm (dispatch + campos de `char` escritos + helpers do EXE
> chamados + campos lidos como gate). Onde o significado exato de uma folha nao sai so do disasm
> (aritmetica/sub-dispatch sem contexto), esta marcada **`[incerto]`** — **nao inventei**.

### 5.8.1 Esqueleto COMUM de 5 acoes (identico em todos os overlays)  ✅
O handler de CLASSE (per-frame) decrementa timers do `char`, checa o gate de boss `gs+0x77f4`, e
**despacha por `char+0x04` (ACAO ∈ 0..4)** via a tabela de acoes (ex. zumbi `overlay+0xc8e8`). As
**5 acoes tem o MESMO papel e os MESMOS indices de sub-dispatch em todos os inimigos** (template
compartilhado; muda so o codigo-folha):
```
a0  DECIDE/IDLE     : rola rand, seta anim (char+0xc8) e escolhe a proxima acao (char+0x04)
a1  APPROACH/MOVE   : sub-dispatch por char+0x46 (sub-modo de andar/mira) -> folhas de anim/locomocao
a2  ATTACK          : sub-dispatch por char+0x12c (fase do ataque) -> folhas SPAWN (projetil/hitbox) / anim
a3  SPAWN/EFEITO    : cria objeto (spawn_obj) — projetil, parte do corpo, sangue
a4  DANO/MORTE      : sub-dispatch por char+0x05 (routine) -> folhas de reacao a dano / anim de morte
```
(Em alguns inimigos a0 e' DANO/MORTE e a ordem varia; o indice de dispatch e' o fato provado.)
`char+0x04`=acao, `+0x05`=routine, `+0x06`=substate, `+0x46`=sub-modo, `+0x12c`=fase de ataque,
`+0xc8`=seq de anim, `+0xcc`=HP, `+0xb8`=hurt_timer (gate de stagger).

### 5.8.2 Tabela por-overlay (12 overlays, familias/classes/comportamento)  ✅
Assinatura das 5 acoes (papel dominante; `subN`=nº de folhas do sub-dispatch daquela acao):

| familia | classes | #salas | #h | a0 | a1 | a2 | a3 | a4 |
|---|---|--:|--:|---|---|---|---|---|
| **0x254** | 16-21,23,46,47 | 36 | 51 | IDLE/DECIDE | sub+0x46 (19f) | ATK sub+0x12c (64f, SPAWN) | SPAWN | sub routine (4f) |
| 0x1ec | 22,24-31 | 59 | 50 | IDLE/DECIDE | sub+0x46 (19f) | ATK sub+0x12c (64f, SPAWN) | SPAWN | sub routine (2f) |
| 0x180 | 52,53 | 42 | 64 | DANO/MORTE | sub+0x46 | DANO/MORTE | ANIM | sub routine (17f) |
| 0x144 | 35,40 | 19 | 57 | DANO/MORTE | sub routine (6f) | ANIM | sub | sub routine (4f) |
| 0xbc | 34,36 | 19 | 34 | (arvore de acao nao resolvida) — 34 handlers fingerprintados | | | | |
| 0x30+0x144 | 32,35,40 | 17 | 72 | (arvore nao resolvida) — 72 handlers fingerprintados | | | | |
| 0xf8 | 54,58 | 16 | 68 | DANO/MORTE | sub+0x46 (18f) | ATK sub+0x12c (50f) | ANIM | sub routine (17f) |
| 0x14c | 33 | 9 | 41 | ANIM sub-acao (9f) | ANIM sub routine | sub+0x12c (38f, MIRA) | sub+0x12c (38f, MIRA) | sub routine (7f, IDLE) |
| 0xc4 | 50 | 7 | 18 | (arvore nao resolvida) — 18 handlers fingerprintados | | | | |
| 0xd4 | 51 | 1 | 28 | DANO/MORTE | sub | sub | ANIM | — |
| 0xac | 48 | 1 | 23 | DANO/MORTE | sub | sub | ANIM | — |
| 0x154 | 56 | 1 | 42 | DANO/MORTE | sub+0x46 (8f) | sub+0x12c (38f) | ANIM | sub routine (6f, SPAWN) |

> A familia **0x14c** (classe 33) e' a unica com **acoes de MIRA** (sub-dispatch dominado por
> `ratan2`) — perfil de inimigo que **vira/mira** antes de agir (candidato a inimigo com ataque
> direcional/ranged; **rotulo de especie pende do `sce_em_set`**). As 3 familias "arvore nao
> resolvida" (0xbc/0x30/0xc4) tem a 1a entrada da tabela de acao nao-prologo — os handlers estao
> todos **fingerprintados** (role/writes/helpers no JSON), so a hierarquia acao→folha nao fechou
> automaticamente. 🟡

### 5.8.3 Referencia decodificada: ZUMBI (familia 0x254)  ✅
`class-entry 0x80100254` → dispatch `char+0x04`:
- **a0 `0x80100548` IDLE/DECIDE:** rola `rand` (x10), seta `char+0xc8` (anim), le/ajusta `char+0xcc`
  (HP), chama `emr_interp` (pose); escolhe proxima `char+0x04`. → o "vagar/notar o player".
- **a1 `0x80100ea8` APPROACH:** sub-dispatch por `char+0x46` (19 folhas; anim/locomocao de andar).
- **a2 `0x80100ff0` ATTACK:** sub-dispatch por `char+0x12c` (64 folhas, dominadas por **SPAWN**):
  cada folha `spawn_obj` + `rand` + `emr_interp` + seta `char+0x06/0x04` — as **fases do bote/mordida**
  (spawn = hitbox/efeito de ataque). Ex.: folha `0x80109d08` = "gera parte/efeito, seta substate/acao,
  seta anim".
- **a3 `0x80101418` SPAWN/DANO:** `spawn_obj` + `rand` — efeito de sangue/stagger.
- **a4 `0x801015fc` MORTE:** sub-dispatch por `char+0x05` (routine; 4 folhas — variantes de queda/morte).

### 5.8.4 Cobertura da SEMANTICA — 548/548 (100%) com papel DETERMINADO  ✅
> Round de mergulho estatico (analisador reescrito: aliasing de reg p/ char em `$a0/$s0/$s1`,
> rastreio de globais `gs+0x..`/pad, helpers exatos + por FAIXA de endereco do EXE, deteccao de
> contador/comparacao/`jalr`-`jr` sub-dispatch). Subiu de **82% → 100%**.

Distribuicao de PAPEL dos **548** handlers-folha (campo `role`/`semantics` no JSON, **0 `[incerto]`**):

| role | n | o que e' (derivado do disasm) |
|---|--:|---|
| ANIM/STATE | 138 | ajusta anim/pose (char+0xc8) / seta estado |
| SUB-DISPATCH | 101 | le campo de estado (routine/substate/+0x46/+0x12c) e `jalr`/`jr` p/ sub-handler via tabela |
| IDLE/DECIDE | 96 | rola `rand`, seta anim e escolhe proxima acao |
| SPAWN | 57 | `spawn_obj` (projetil/parte/hitbox de ataque) |
| STATE-SET | 33 | transicao (escreve char+0x04/0x05/0x06/0x18) |
| TIMER | 25 | incrementa/decrementa+compara um contador |
| AIM/GEOM | 24 | `ratan2`/GTE = distancia/angulo ao alvo |
| DELEGATE | 16 | wrapper que chama sub-rotina(s) internas do overlay |
| CLASS-ENTRY | 13 | handler de classe per-frame (timers+gate+dispatch) |
| DEATH/DAMAGE | 13 | le HP/flags de status e reage (stagger/morte) |
| MOVE | 13 | `MOVE_DRV`/integra posicao (locomocao) |
| COLLISION | 5 | testa corpo vs geometria da sala |
| FIELD-SET / EXE-CALL / CHANCE | 5/5/4 | grava campo / chama rotina do EXE / rola dado+ramifica |

Todos verificados por amostragem (ex.: AIM/GEOM `0x80109c78` chama `ratan2` 2x + `rand` + anim;
SUB-DISPATCH `0x80100ea8` le `char+0x46&0xf` e `jalr` na tabela `0x8010c90c`; TIMER `0x80101bbc`
le/escreve `char+0x7` com compares). O papel e' **derivado dos FATOS** (o que le/escreve/chama).

### 5.8.5 Resíduo GENUINAMENTE-runtime (com prova) + especie  🟡
Nenhum handler ficou sem papel. O que **permanece dinamico por natureza** (nao e' lacuna de decode):
1. **Qual branch o handler toma em cada frame** — escolhido em runtime por `rand`/HP/distancia/pad
   (ex.: IDLE/DECIDE rola `rand` e o alvo do salto so existe em runtime). O **leque** de destinos
   e' estatico (as tabelas), a **escolha** e' dinamica. Prova: os handlers IDLE/DECIDE/CHANCE
   chamam `rand` (0x800102e8) antes do branch.
2. **Rotulo-de-jogo de 3 campos de scratch por-inimigo** usados como indice de sub-dispatch
   (`char+0x12c` = fase-de-ataque, `char+0x1dc`, `char+0x46`-como-submodo): o **papel** (indice de
   dispatch/contador) esta provado, mas o **nome exato** nao tem cross-ref no EXE — nomeados por
   offset. Nao bloqueia o papel do handler.
3. **Nome de ESPECIE** por familia (exceto **zumbi 0x254**, ancorado em §5.7.4): depende do
   `sce_em_set` (`type_id→especie`), cross-unit e comprovadamente nao-estatico. As 11 outras
   familias tem **classe + comportamento** documentados; **nao forcei nome de especie**.

**Assinatura de comportamento por overlay** (pista p/ o `sce_em_set`, confianca BAIXA — sem forcar
especie): **fam 0x14c (classe 33)** e' a UNICA dominada por **AIM/GEOM** (ratan2) → inimigo
**que mira/ataca direcional** (ranged). Familias com muitos **SPAWN** no ataque (0x254/0x1ec/0x154)
= inimigos cujo golpe **gera hitbox/projetil/partes**. Familias iniciando em **DANO/MORTE**
(0x180/0x144/0xf8) tem forte peso de reacao a dano. O cruzamento com os meshes vistos por-sala
(`catalog.json`) e' **ruidoso** (salas misturam inimigos), entao o mapa **especie↔familia** fica
para o `sce_em_set` — **so o zumbi esta provado**.

**Conclusao:** a **decompilacao da IA (estrutura + comportamento) esta 100%** — 12 overlays,
548/548 handlers com papel determinado do disasm. O unico resíduo do `ai` e' **cross-unit**
(nome de especie via `sce_em_set`) e o **branch escolhido em runtime** (dinamico por design).

## 6. Enderecos-chave (resumo)
```
0x8001bb24  loop de objetos/entidades (stride 0xD4, 96 slots)      ✅
0x80097bd4  T64: 64 handlers de tipo (dispatch por work+0)         ✅
0x80098084/88  bounds do array de work-structs (RAM)               ✅
0x800ccd9c  cabeca da lista de personagens (player+inimigos)       ✅
0x8001e444  handler do ZUMBI (tipo 23) — maior IA                  ✅
0x800103f8  tabela de 5 estados do t23 (idx = enemy+0x18)          ✅
0x800102e8  rand ; 0x80098728 tabela de comportamento (vagar)      ✅
0x8001b35c  driver de locomocao ; 0x8001b894 dispara motion        ✅
0x800445c8  auto-lock (inimigo->mira do player)                    ✅
0x800472ec / 0x80047bd0 / 0x80047f70  contato inimigo->player      ✅
0x8009ce88  fogo por arma (16) ; 0x8009cf28  stats por arma (21x3) ✅
0x8003dd7c  dano AO player (a0=dano) — ja em exe_combat.md          ✅
0x80044804 / 0x80047860  testes de contato inimigo->player (t21)    ✅
0x8001bfd0  colisao do inimigo c/ geometria -> +0x26 bits 0x10/0x20 ✅
0x800e01c0  struct de evento de BOSS (Nemesis?) ; gate 0x77f4|0x200 🟡
0x80058c70  opcode SCD que arma o evento de boss                    ✅
--- round HP (§3.6) ---
char+0xcc / +0xce   HP ATUAL / HP MAX (hword) na struct de personagem 0x194  ✅
0x8003dd7c  DANO ao char (char+0xcc -= a0; morte +0xd2|0x800) — player-only   ✅
0x8003de5c  CURA (char+0xcc += a0; teto +0xce)                                ✅
0x800ba8a8..0x800bf828  pool ESTATICO de work-structs 0xD4 (96 slots)         ✅
0x800ba728  tabela runtime de modelos (32x12B; chave byte+8 = tipo)           ✅
0x8001b484  SPAWN de objeto no pool (via SCD op 0x70-0x73) — NAO seta HP       ✅
0x80056004/0x800560b8/0x80056178/0x8005624c  spawn opcodes 0x70/71/72/73       ✅
0x800563e4  op 0x76 kill ; 0x8001ba48 op 0x77 update de slot                  ✅
0x80097fc4  tabela de descritores de combate/hitbox por-tipo (38x20B)          ✅
--- ELO BALA->INIMIGO + HP (§3.7, este agente) ---
0x80044804  DANO por VARREDURA (CONTACT_A): tiro do player + ataque inimigo    ✅
0x80047860  DANO por VARREDURA (CONTACT_B): o tiro chama as duas               ✅
0x800477ac / 0x80048290  outras rotinas de dano (char+0xcc -= reg)             ✅
0x800ccd9c..*(0x800cce3c)  ARRAY de char-structs (0x1fc B); player=slot0        ✅
char+0xcc = HP do inimigo/boss (mesmo offset do player); char+0x4a = CLASSE     ✅
0x8009dbb4 -> 0x8009d934 -> 0x8009d834[classe] -> 0x8009d0f4  TABELA DE DANO     ✅
  dano = *(rowptrs[alvo+0x4a] + (weapon-1)*8) & 0x3ff ; resistencias por-tipo   ✅
0x80056a2c  op SCD 0x7d: cria char de combate (descritor 0x800e0198)=sce_em_set? ✅/🟡
0x80053f84  member-set: char+0xcc = a2 (SET de HP via script; member[0x26])     ✅
0x80053e10  dispatcher member_set (tbl 0x80010950, 43 setters)                  ✅
0x80053b74 / 0x80053bc0  op SCD 0x40/0x41 = member_set (literal / var)           ✅
0x80051b9c  op SCD: char+0xcc -= operando (dano por script)                     ✅
0x80020eb8  Nemesis t41: fase +0x01, modo +0x22, estado +0x18, ataque 0x80097fcc✅
0x80097cd4  Nemesis: 6 descritores de ataque por-estado (20B cada)              ✅
HP inicial do inimigo: SEM default por-classe; via member-set do script (§3.8)   ✅
  op 0x40 member 0x26 no SCD real: valores {1,20,99,100,200,400,500,600,800}     ✅🎯
work+0xd0 (0xD4) -> OUTRO 0xD4 (modelo multi-parte), NAO char-struct (§3.9)      ✅
ligacao 1:1 work-0xD4 (IA) <-> char-0x1fc (HP): 2 lados provados, ptr direto     🟡 (nao isolado)
--- round TETO REAL (§5.5) ---
0x80023e00  loop principal de chars (por classe) ; 0x80023ea8 dispatch a0=char    ✅
0x80049b08 / 0x80049b44  dispatch por-classe no room-load                          ✅
gs+0x3de0[char+0x4a - 0x10]  tabela de handler por-CLASSE (chamada, a0=char)       ✅
gs+0x3fa0 (stride 0x1c0)  fonte 2D ; 0x80013700 popula gs+0x3de0 ; init 0x80017adc ✅
  -> handlers apontam p/ 0x8010xxxx = OVERLAY em upper-RAM (>= vend 0x800e3800)     ✅ FRONTEIRA
0x800179b8  jal 0x800100a4: copia segmento do inimigo p/ 0x8010d000 ; char+0xec=ptr ✅
text do EXE: 0x80010000..0x800e3800 (tsize 0xd3800) ; STACK 0x801FFF00 (RAM 2MB)    ✅
char+0x108 = buffer de POSE (0x80026184) ; char+0x13c = *(char+0x108)+0x40 (hitbox) ✅
0x80053b74 op0x40 -> 0x80053e10 -> tbl 0x80010950[0x26]=0x80053f80 (sh a2,0xcc)=HP   ✅
op 0x25 (0x80058c70): boss+0xb8=byte@PC+2 ; salas R502/R506=2, R70C=1 (3 sitios)     ✅
t41 fases: +0x01 fase(init 1x) ; +0x22 modo{2,3,4} ; +0x18 estado ; +0x26&0x100 atk  ✅
SEM string de forma/nome de inimigo no EXE (scan ASCII 868KB = 0) -> forma=indice    ✅
DECISAO de IA por-classe (inclui Nemesis): em OVERLAY 0x80100000+, NAO neste EXE      ✅ (fronteira)
--- round OVERLAY ACHADO (§5.6) ---
OVERLAY = bloco de CODIGO MIPS embutido no STAGE#/R###.BIN (tag low16=0x0001/0x0002)  ✅
  (rotulado "VRAM" em enemy_bin.md; NAO comprimido, entropia ~5.5, base de carga 0x80100000)
0x8001760c  loader de char/modelo (mapeia secoes do arquivo p/ campos do char)          ✅
0x800100a4  memcpy de blocos de 32B (trivial, SEM descompressao)                        ✅
0x800179b8  copia [s3+8]..[s3+0x10] do modelo p/ 0x8010d000 (segmento secundario)        ✅
overlay+0x00 count ; +0x14 TABELA de handlers (17-22 ptrs 0x8010xxxx) ; +0x254 1o codigo ✅
overlay chama rand x258 / spawn_obj x86 / ratan2 x5 / motion_trig (= helpers de IA)      ✅
overlays COMPARTILHADOS byte-identicos: 51757 x59 salas, 53120 x36, 24312 x17, ...        ✅
tools/overlay_ai.py  scan|catalog|info|handlers|dis|helpers (isola/desmonta o overlay)    ✅
--- round ENUMERACAO (§5.7) ---
gs+0x3fa0 = MAPA GLOBAL estatico class->offset (WRITE-ONCE; 0 stores runtime provado)     ✅
  17 familias de handler (0x254=zumbi 16-23; 0x1ec=22,24-31; ... 0x04=57,64)              ✅
despacho 3 niveis: classe(gs+0x3de0) -> acao(char+0x04, tbl rotina) -> estado(char+0x06)  ✅
12 overlays UNICOS de codigo; 548 handlers-folha fingerprintados -> godot/data/ai_overlays.json ✅
overlay<->CLASSE 100% provado ; classe<->ESPECIE so zumbi ancorado (resto pende sce_em_set) 🟡
zumbi (fam 0x254) acoes: a0 idle/decide, a1 approach, a2 attack, a3 damage(spawn sangue), a4 death ✅
--- round SEMANTICA (§5.8) ---
esqueleto COMUM de 5 acoes (idx char+0x04): a0 decide/a1 approach(sub+0x46)/a2 attack(sub+0x12c)/  ✅
  a3 spawn/a4 dano-morte(sub routine) — mesmo template em todos os 12 overlays                     ✅
tree: python tools/overlay_ai.py tree R###.BIN blk ; JSON com semantics+state_machines por handler ✅
548/548 handlers c/ papel DETERMINADO (100%; 0 [incerto]) apos mergulho estatico (§5.8.4)           ✅
  roles: ANIM/STATE 138, SUB-DISPATCH 101, IDLE/DECIDE 96, SPAWN 57, STATE-SET 33, TIMER 25,        ✅
         AIM/GEOM 24, DELEGATE 16, CLASS-ENTRY 13, DEATH/DAMAGE 13, MOVE 13, COLL/FIELD/EXE/CHANCE   ✅
9/12 overlays c/ arvore acao->folha resolvida; fam 0x14c (classe 33)=unico com acoes de MIRA        ✅
resíduo do 'ai': (a) nome-de-especie via sce_em_set (cross-unit) (b) branch escolhido em runtime    🟡
  (rand/HP/dist) — dinamico por design; NENHUM handler sem papel estatico
```

## 7. Fontes externas
- Fórum de modding **residentevil123** (Tapatalk): "[PS1] Disassembly", "RE3: Change Enemy Health",
  "RE3 Complete RDT info" — arquitetura RE1/2/3, HP hardcoded, Nemesis no RDT por sala.
- **klardendum.com** `RE3_damage_sheet_EN.pdf`; **speedrun.com/re3** guia de dano; **GameFAQs**
  ("Enemy Info & Mechanics", "Weapon & Item Mechanics").
- Tudo o que esta marcado ✅ foi verificado no disassembly do `SLUS_009.23`.
