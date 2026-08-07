# `PC_SYS.BIN` **não é** o menu de jogo — e onde o menu de jogo realmente está

**Alvo:** RE3 PS1 NTSC-U, `SLUS_009.23` (PS-X EXE, base `0x80010000`).
**Ferramentas novas desta rodada:** [`tools/exe_fn.py`](../../../tools/exe_fn.py),
[`tools/exe_struct.py`](../../../tools/exe_struct.py),
[`tools/menu_ingame.py`](../../../tools/menu_ingame.py).
**Herdado (não reverifiquei):** `menu_overlays.md` (formato/base dos overlays, tabela de arquivos
do CD `0x800946a4`, `cd_read_file` `0x80012818`).

> ## TL;DR — a premissa da tarefa estava errada
> 1. **`BIN/PC_SYS.BIN` é o TERMINAL DE COMPUTADOR do jogo** ("Umbrella Security System",
>    senha da sala de medicamentos do hospital: `ADRAVIL`/`SAFSPRIN`/`AQUACURE`), + o quadro de
>    avisos "NOTICE TO STARS PERSONNEL". `PC` = *Personal Computer*. Provado pelas 29 strings do
>    arquivo (§1) e pelos `flag_set` que ele faz. `menus.md §4` já classificava assim
>    ("12_pc_terminal") e está certo.
> 2. **Nenhum overlay é o menu de jogo.** O menu (status/inventário/mapa/arquivo) está **inteiro
>    no EXE principal**, na faixa `0x80063000..0x80075000`, e roda como **task 1**, entry
>    `0x8006dfdc`. Provado: só existe **1** referência a `0x8006dfdc` em todo o EXE
>    (`0x800235a4`/`0x800235ac`), e os assets de status (`STMAIN0U.TIM`, `STMOJIU.TIM`,
>    `ITEMA.SLD`) são carregados por `0x8006d720`, chamado do `game_init` (§4).
> 3. **O jogo PARA de verdade:** `menu_init` faz `task_suspend(0)` e `menu_exit` faz
>    `task_resume(0)` — e esses são os **únicos dois sítios** de suspend/resume do EXE (§7).
> 4. **O menu roda a 60 Hz** (`0x800d442c = 1`), enquanto o gameplay roda a **30 Hz**
>    (`0x800d442c = 2`). Isso muda TODAS as contagens de frame abaixo (§8).

---

## 1. `PC_SYS.BIN` — identidade provada

`python tools/overlay_parse.py PC_SYS --strings` (base `0x801c2000`, 16348 B, entry `0x801c2354`):

| offset | string |
|---|---|
| `+0x001c` | `NOTICE TO STARS PERSONNEL` |
| `+0x0048` | `Due to the emergency, the` |
| `+0x0064` | `key to the STARS Office has]been moved to the evidence]room.` |
| `+0x00a4` | `Today's password for the]safe is ` |
| `+0x00c8`.. | `\|20513\|0.` `\|20131\|0.` `\|24011\|0.` `\|24312\|0.` `****.` |
| `+0x012c` | `Umbrella Security System` |
| `+0x0148` | `First Class ]Medical Storage Room:] Security Authorization` |
| `+0x0184` | `Current Status: \|1Locked\|0` |
| `+0x01a0` | `Please enter password and ]then press the RETURN key.` |
| `+0x01d8` | `Enter Password:` |
| `+0x01e8`/`+0x01f0`/`+0x01fc` | `ADRAVIL` / `SAFSPRIN` / `AQUACURE` |
| `+0x0208` | `\|1ERROR...[020]ERROR...[020]` |
| `+0x0228` | `\|1Invalid password.]Please re-enter password and ]then press the RETURN key.\|0` |
| `+0x0278`/`+0x0290` | `Password: Confirmed` / `Room Access: Confirmed` |
| `+0x02a8` | `Deactivating lock. ]Please wait[010.[010.[010.` |
| `+0x02d8`/`+0x02f4` | `Current Status: Unlocked` / `System Status: Normal` |

`]` = quebra de linha, `[0NN]` = pausa de NN unidades, `|1`/`|0` = troca de cor — mesma
codificação de `re3_messages.json`.

Máquina de estados dele: `switch` em `*(u8*)0x800d1d26` (bound 5), tabela em `0x801c2004`,
`jr` em `0x801c2400`; 5 labels: `0x801c24c4, 0x801c2408, 0x801c241c, 0x801c2468, 0x801c247c`.
Não usa tabela de handler nem `cd_read_file` (desenha texto com a fonte já em VRAM).
Flags que mexe (via `flag_set`/`flag_test` `0x800788dc`/`0x80078930`):
banco `0x800d1fa0` bits `0x08`, `0x3b`, `0x3c`, `0xa3`, `0xa8`, `0xa9`, `0xaa`;
banco `0x800d20cc` bit `0x1b`. ESP disparados: `0x206`, `0x207`, `0x209`, `0x210` (§10).

**Conclusão:** é o terminal/quadro de senhas. Não é o menu, e **não existe overlay do menu**.

---

## 2. Onde o menu de jogo está — prova por asset

Índices na tabela global de arquivos do CD (`0x800946a4`, stride 8, ordem ISO; conferido contra
`os.path.getsize` dos arquivos extraídos):

| idx | arquivo | quem carrega (sítio de `jal 0x80012818`) |
|---|---|---|
| `0x1c` | `ETC/FILEGU.PIX` | `0x800637ac`, `0x800642a8` |
| `0x1d` | `ETC/FILEI.TIM` | `0x80063d64`, `0x80066cf4` |
| `0x32` | `ETC/ITEMA.SLD` | `0x8006d85c`, `0x8006da5c`, `0x8006ddf8` |
| `0x33` | `ETC/ITEMG.PIX` | `0x8006ad04` |
| `0x34` | `ETC/ITEMI.PIX` | `0x8006aa28`, `0x8006aaf0` |
| `0x3a` | `ETC/MAP_U.MAP` | `0x800714ac` |
| `0x58` | `ETC/STMAIN0U.TIM` | `0x8006d7f8` → dest `0x801b1500` |
| `0x60` | `ETC/STMOJIU.TIM` | `0x8006d82c` → dest `0x801b1500` |

Reproduzir: `python tools/exe_fn.py` + o laço de `Ana.jal[0x80012818]` com `Ana.args()`
(exemplo comentado em `tools/menu_ingame.py`).

`0x8006d720` (que carrega `STMAIN0U`+`STMOJIU`+`ITEMA.SLD`) é chamado de **`0x80024764`, dentro de
`0x800245a0` = `game_init`**, que por sua vez é chamado de `0x80023290` (o fluxo de jogo,
`0x80023268`). Ou seja: os gráficos do menu são carregados **uma vez ao entrar no jogo**,
não a cada abertura.

---

## 3. O contexto da tela — `ctx = 0x800e01c0`

Todos os handlers recebem `a0 = 0x800e01c0`. Campos medidos (offset, tamanho, escritores):

| off | tam | papel | prova |
|---|---|---|---|
| `+0x04` | u8 | **screen kind** (0..5) — qual tela | `switch` bound 6 em `0x8006dc84` (init), `0x8006e0c8` (exit), `0x8006e364` (draw), `0x8006e468` (estado 0) |
| `+0x06` | u8 | flag usada no exit p/ escolher `0x800d442e = 1` ou `2` | `0x8006e174` |
| `+0x08` | u32 | ponteiro corrente no buffer de gráficos (`0x801b1500` ou `0x801a1500`) | `0x8006dcc0`, `0x8006de14` (avança por `cd_read_file` ret) |
| `+0x10` | u8 | **estado** → tabela `0x800a02f0` (14 entradas) | `lbu 0x10($s0)` em `0x8006e02c` |
| `+0x11` | u8 | **subestado** → tabela `0x800a0100` (20) / `0x800a0500` (5) / `0x8009f4e4` (5) | `0x800665d4`, `0x8006f6d8`, `0x80064430` |
| `+0x12`,`+0x13` | u8 | sub-subestados / contadores dos subestados | 5 e 3 escritas |
| `+0x14` | u32 | flags persistentes entre aberturas (bit 30 = "recarregar `ITEMA.SLD`") | `0x8006da38` testa `0x40000000`; `0x8006dae4` limpa |
| `+0x18` | u32 | **bitfield de camadas a desenhar** (§9) | `0x8006e3c0`.. |
| `+0x1c` | s8 | **cursor do inventário** (0..count-1; `-1` e `-2` = duas entradas especiais) | `0x80066644`, `0x80066798`, `0x800667e0` |
| `+0x1c..+0x21` | u8[6] | zerados no init (cursor por página?) | laço `0x8006db08`, bound 6 |
| `+0x22` | s16 | **pulso de brilho do cursor**, vai-e-vem 0..0x3f, passo 2/frame | `0x8006e2a0`..`0x8006e2f0` |
| `+0x24` | s16 | direção do pulso (0 = subindo, 1 = descendo) | idem |
| `+0x27` | u8 | **"menu aberto"** — a task roda enquanto `!= 0` | set `0x8006db2c` (=1), clear `0x8006e580` (=0) |
| `+0x28` | u8 | arma equipada salva (`inv+0x129`) p/ detectar troca no exit | `0x8006db6c`, `0x8006e1c8` |
| `+0x29` | u8 | `*(u8*)0x800ccc0e` copiado | `0x8006db88` |
| `+0x2a` | u16 | `flags` do slot selecionado (`slot+2`) | `0x800666ac` |
| `+0x2e` | u8 | "restaurar cursor/arma salvos" (one-shot) | testado `0x8006d9ac`, limpo `0x8006d9bc` |
| `+0x2f`,`+0x30` | u8 | cursor / arma salvos (escritos em `inv+0x128`/`+0x129`) | `0x8006d9cc`, `0x8006d9dc` |
| `+0x32` | s16 | contador de rolagem, `+1` (ou `+3` se `ctx+0x18 & 0x00800000`), wrap `>=0x51 → -0x20` | `0x8006e308`..`0x8006e338` |
| `+0x34` | u8 | retorno de `0x8006e598` (estado do texto/mensagem) | `0x8006e280` |
| `+0x3a..+0x3d` | u8 | zerados no init | `0x8006db4c`.. |
| `+0xe4..+0x163` | u16[2][32] | zerados no init (posições animadas) | laço `0x8006db34`, bound 0x20, passo 4 |
| `+0xf0..+0x144` | s16 | **coordenadas do painel** (§9) | `0x8006dec4`.., `0x80066560`.. |
| `+0xab`,`+0xb8`,`+0xbc`,`+0xbd`,`+0xcb` | u8/u16 | `0xbc` = id do arquivo (FILE); `0xb8` = seletor de `0xab` | `0x8006dbfc`, `0x8006db8c` |

O inventário em si (já provado no repo) é: `0x800d23b8` = índice do personagem;
`0x800d23b4` = ponteiro para o bloco ativo; blocos em `0x800d2134`, **stride 320 B**
(`0x800246dc`: `v1 = idx*5*64 + gs+0x79fc`, `gs = 0x800ca738`, `gs+0x79fc = 0x800d2134`).
`+0x128` cursor, `+0x129` arma equipada, `+0x12a` count.

---

## 4. A task do menu — `0x8006dfdc` (task slot 1)

Sistema de tasks: tabela `0x800dcb90`, **3 slots**, stride `0x80`
(`0x8003201c`: `sll a0,7; addu 0x800dcb90`), ponteiro do slot corrente em `0x800dcd14`.
Campos: `+0x00` estado(u16), `+0x02` contador de espera(u16), `+0x08` entry, `+0x0c` contexto
salvo, `+0x14` pilha (`0x801ffb00`/`0x801ff400`/`0x801fed00`, `0x80031e30`..`0x80031e38`).
Escalonador `0x80031e5c`, chamado 1×/frame do laço principal `0x80028f38` (sítio `0x8002921c`).
API: `set_task_entry` `0x8003201c` (estado=2), `yield(n)` `0x8003203c` (estado=1, contador=n),
`task_stop` `0x80032070` (estado=0), `run_now` `0x80032110`, `task_suspend` `0x80032160`
(`estado |= 0x40`), `task_resume` `0x80032184` (`estado &= ~0x40`).
O escalonador só age em estado `2` (start), `1` (contagem) e `4`; qualquer valor com `0x40`
setado cai fora — **é assim que o suspend congela a task**.

Pseudocódigo exato da task do menu (`0x8006dfdc`, 41 instruções):

```c
void menu_task(void) {                        // 0x8006dfdc
    ctx = (Menu*)0x800e01c0;
    menu_init(ctx);                           // 0x8006dff8 -> 0x8006d948
    if (ctx->open /*+0x27*/ == 0) goto fim;
    handlers = (fn*)0x800a02f0;
    do {
        if (*(u8*)0x800d4434 != 1)            // 0x8006e01c: NAO esta em PAUSE(START)
            handlers[ctx->state /*+0x10*/](ctx);   // 0x8006e044
            anim(ctx);                             // 0x8006e04c -> 0x8006e268
        draw(ctx);                                 // 0x8006e054 -> 0x8006e34c
        nop_stub(ctx);                             // 0x8006e05c -> 0x80073e7c == `jr $ra` (vazio!)
        yield(1);                                  // 0x8006e064
    } while (ctx->open != 0);
fim:
    menu_exit(ctx);                           // 0x8006e07c -> 0x8006e0a4
    task_stop();                              // 0x8006e084 -> 0x80032070
}
```

> **`0x80073e7c` é um stub vazio no retail** (`jr $ra; nop`). A função de verdade é
> `0x80073e84`, chamada só do init do jogo (`0x80029844`).

### 4.1 Quem inicia a task

`0x800235a4`/`0x800235ac`: `set_task_entry(1, 0x8006dfdc)` seguido de `yield(1)`, dentro do
fluxo de jogo `0x80023268`, guardado por:

```asm
80023584  lw   $v1, 0x77f4($s0)        ; v1 = *(u32*)0x800d1f2c   (gs+0x77f4)
80023594  andi $v1, $v1, 0x200
80023598  beqz $v1, 0x800235dc         ; nao pediram menu -> segue
800235a0  addiu $a0, $zero, 1          ; task 1
800235a8  jal  0x8003201c              ; set_task_entry
800235ac  addiu $a1, $a1, -0x2024      ; a1 = 0x8006dfdc
800235b0  jal  0x8003203c ; a0=1       ; yield(1)  -> a task do menu roda ate acabar
...
800235d4  sw   $v0, 0x77f4($s0)        ; limpa o bit 0x200
```

**`0x800d1f2c` bit de máscara `0x200` (= banco 1, bit 22 na convenção `mask = 0x80000000>>bit`)
é o "pedido de abrir a tela do menu".** É a **única** entrada. Escritores do bit
(padrão `ori 0x200` + `sw` em `0x800d1f2c`), todos medidos:

| sítio | contexto | escreve `ctx+0x04` |
|---|---|---|
| `0x80023ca8` | `if (log_edge & 0x4000)` → **botão de MENU** | `0` em `0x80023cb0` |
| `0x80023cd8` | `if (raw_edge & 0x0001)` → **L2** | `4` em `0x80023cd0` |
| `0x8003b13c` | ação do jogador (fn `0x8003b080`) | `1` em `0x8003b128` |
| `0x80051198` | pegar item (fn `0x80050fe0`) | `1` em `0x80051174` |
| `0x80051268` | mensagem (fn `0x800511b0`) | (registrador) |
| `0x80051634` | fn `0x800514f0` | — |
| `0x80051ad4` | fn `0x8005190c` | (registrador) |
| `0x80057e54` | fn `0x80057cf8` | `0` em `0x80057e34` |
| `0x80058ca8` | fn `0x80058c24` | `4` em `0x80058c88` |
| — | fn `0x800513cc` | `2` em `0x800514cc` |

---

## 5. As 6 **telas** (`ctx+0x04` = screen kind)

Quatro tabelas de 6 entradas, todas indexadas por `ctx+0x04`, com `sltiu ..., 6` antes:

| kind | init (`0x8001100c`) | exit (`0x80011034`) | draw (`0x8001104c`) | estado inicial (`0x80011064`) |
|---|---|---|---|---|
| 0 | `0x8006df00` | `0x8006e140` | `0x8006e3c0` | **1** |
| 1 | `0x8006de64` | `0x8006e140` | `0x8006e3c0` | **1** |
| 2 | `0x8006dda0` | `0x8006e0f0` | `0x8006e3b0` | **10** |
| 3 | `0x8006dd50` | `0x8006e140` | `0x8006e3f8` | **7** |
| 4 | `0x8006dcac` | `0x8006e140` | `0x8006e38c` | **4** |
| 5 | `0x8006dcf4` | `0x8006e140` | `0x8006e38c` | **4** |

Identificação (com o grau de prova):

- **kind 0 = STATUS / INVENTÁRIO** — PROVADO: é o que o botão de menu seta (`0x80023cb0`),
  init `0x8006df00` monta as coords do painel e liga `ctx+0x18 |= 0x40000000|0x04000000`
  (camada `0x8006b66c` = painel de status), estado inicial 1 → 2 (dispatcher de 20 subestados).
- **kind 4 = MAPA** — PROVADO: setado pelo **L2** (`raw_edge & 0x0001`, `0x80023cb4`), estado
  inicial 4 = `0x8006ed98`, que chama `0x8006ee54 → 0x800713dc → cd_read_file(0x3a=MAP_U.MAP)`.
  Draw = `0x8006e38c` → `0x80070244` gated por `ctx+0x18 & 0x00200000`.
- **kind 1 = EXAMINAR / PEGAR ITEM (janela de descrição)** — FORTE: setado por
  `0x80051174` (código de pegar item) e `0x8003b128`; init `0x8006de64` recarrega
  `ITEMG.PIX` (`0x8006ac88`) e `ITEMI.PIX` (`0x8006a9ac`, `a0=0xc`); estado 1 põe
  subestado `0xb` (`0x80066550`) em vez de 0.
- **kind 3 = LER UM ARQUIVO (documento)** — PROVADO: `menu_init` converte kind 1 → 3 quando o
  id da mensagem cai em `[0x85, 0xa3]` (`0x8006dbd0`: `msg - 0x85 < 0x1f`), grava
  `ctx+0xbc = (msg + 0x7b) & 0xff` (= `msg - 0x85`, 0..0x1e) e faz
  `flag_set(0x800d212c, ctx+0xbc)` = "arquivo lido"; depois procura `ctx+0xbc` numa tabela
  `u16[30]` em `0x800a00b0` e incrementa o contador `*(u32*)(gs+0x79f8) = 0x800d2130`.
  Estado inicial 7 = `0x800636d4` (carrega `FILEGU.PIX`).
- **kind 5 = MENSAGEM comum** — PROVADO parcialmente: `menu_init` converte kind 1 → 5 quando
  `msg >= 0xa4` (`0x8006dc58`) e faz `flag_set(0x800d2124, msg)`. Init `0x8006dcf4` dispara
  ESP `9`. Estado inicial 4 (mesmo handler do mapa — o handler 4 tem sub-dispatcher próprio).
- **kind 2 = NÃO PROVADO.** Setado só por `0x800514cc` (fn `0x800513cc`, módulo de mensagem
  `0x80050d28..0x80051b40`). Init `0x8006dda0` usa buffer `0x801a1500` (não `0x801b1500`),
  faz `StoreImage(RECT{448,256,**64**,256}, 0x80194000)`, chama `0x8006511c`, carrega
  `ITEMA.SLD` e roda `0x8006abf8` para os índices `0x1e..0x22`. Draw = `0x800654a8`.
  Estados 10 → 11 (5 subestados em `0x8009f4e4`) → 12. Os subestados leem **L1/R1**
  (`raw_held & 0xc`, `rpt & 0x4`/`0x8`) e UP/DOWN (`raw_held & 0x5000`) e disparam ESP `0x215`.
  Hipótese (NÃO CONFIRMADA): baú de itens / lista paginada. **NÃO SEI.**

---

## 6. A árvore de estados

### 6.1 Nível 1 — `ctx+0x10`, tabela `0x800a02f0`, **14 entradas** (0..13)

Sem checagem de limite: `lbu 0x10($s0); sll 2; addu handlers; lw; jalr` (`0x8006e02c`).
A 15ª palavra (`0x800a0328`) é `0x2b302c31` (dado ASCII), logo o array tem 14.

| est. | fn | papel (prova) |
|---|---|---|
| 0 | `0x8006e424` | **espera a transição terminar** e escolhe o estado inicial. `if (0x8002a6bc(0) != 0) return; if (*(u32*)0x800e112c != 0) return;` depois `switch(kind)` → tabela `0x80011064` → `ctx+0x10 = 1/4/7/10` |
| 1 | `0x80066530` | monta o layout (kind 0) ou põe subestado `0xb` (kind 1); `ctx+0x10++` → 2 |
| 2 | `0x800665c8` | **dispatcher de subestado**: `subs[ctx+0x11](ctx)`, tabela `0x800a0100` (20) |
| 3 | `0x8006a888` | 4 instruções: `ctx+0x10 = 13; ctx+0x11 = 0` → **ir para o fechamento** |
| 4 | `0x8006ed98` | MAPA / mensagem: 589 instruções; chama `0x800713dc` (`MAP_U.MAP`) |
| 5 | `0x8006f6cc` | **dispatcher** dos subestados do mapa: tabela `0x800a0500` (5: `0x8006f708`, `0x8006fae4`, `0x8006fc68`, `0x8006feb0`, `0x8006ff48`) |
| 6 | `0x80070024` | lógica do mapa (ESP 5); vai para `2` (`0x800700f0`) ou `13` (`0x80070130`, `0x80070218`) |
| 7 | `0x800636d4` | ARQUIVO — lista: `cd_read_file(0x1c = FILEGU.PIX)`; `ctx+0x11 = 0`; `ctx+0x10++` → 8 |
| 8 | `0x80063850` | ARQUIVO — navegação da lista. Pad: `log_edge&0x2000`, `rpt&0x2000`, `raw_held&0x8000`, `raw_held&0x2000`. ESP `4`,`8`,`8`,`5`. `ctx+0x10++` → 9 |
| 9 | `0x80063cac` | ARQUIVO — página: `cd_read_file(0x1d = FILEI.TIM)`; volta a `2` (`0x80063d38`) ou fecha com `13` (`0x80063e70`) |
| 10 | `0x800643e4` | kind 2: `ctx+0x10++` (→11), `ctx+0x11=0`, zera `+0x22/+0x24/+0xcb`, `ctx+0x18 \|= 0x04000000\|0x20000000` |
| 11 | `0x80064424` | **dispatcher** dos 5 subestados de kind 2: tabela `0x8009f4e4` (`0x8006446c`, `0x800646f0`, `0x80064e80`, `0x80065054`, `0x800650bc`) |
| 12 | `0x80064460` | 3 instruções: `ctx+0x10 = 13` → fechamento |
| 13 | `0x8006e4cc` | **FECHAMENTO** (§8.3): dispara a transição de saída e, quando ela acaba, `ctx+0x27 = 0` |

### 6.2 Nível 2 — `ctx+0x11`, tabela `0x800a0100`, **20 entradas** (0..0x13)

(A 21ª palavra é `0x0120ff20`, dado.) Saída de `python tools/menu_ingame.py`:

| sub | fn | ESP disparados | pad lido | escreve |
|---|---|---|---|---|
| 0 | `0x80066604` | 6,7,9,9,5,4 | `raw_edge&0x20`, `log_edge&0x1000`/`&0x2000`, `rpt&0x1000/0x2000/0x4000/0x8000` | `+0x10`,`+0x11`,`+0x12`,`+0x13` |
| 1 | `0x800668e4` | — | — | `+0x11 = 2` |
| 2 | `0x80066920` | 4 | `log_edge&0x2000` | `+0x11 = 3` / var |
| 3 | `0x80066a90` | — | — | `+0x11 = 0` |
| 4 | `0x80066adc` | — | — | `+0x10 = 4` (→ MAPA), `+0x11 = 0` |
| 5 | `0x80066ca0` | 5,6,4,4 | `log_edge&0x2000`, `rpt&0x1000/0x2000/0x4000/0x8000` | `+0x10 = 7` (→ ARQUIVO), `cd 0x1d` |
| 6 | `0x800676b8` | 5 | — | `+0x11 = 0xa`/`3`, `+0x10` var |
| 7 | `0x80067b70` | — | — | — |
| 8 | `0x80069280` | 6,5 | — | `+0x11 = 0xd`/`0xc`/`0` |
| 9 | `0x8006954c` | — | — | `+0x11 = 3` |
| 0xa | `0x80069a6c` | — | — | `+0x11 = 3` |
| 0xb | `0x80069c3c` | 5, var | — | `+0x10` var — **entrada do kind 1 (examinar item)** |
| 0xc | `0x8006a234` | 6,6,5 | `log_edge&0x3000` (2×) | `+0x11 = 0` |
| 0xd | `0x8006a59c` | — | — | `+0x10 = 7`, `+0x11 = 0` |
| 0xe | `0x80067bac` | — | — | `+0x12` |
| 0xf | `0x80067c14` | 5,7,7,4 | `log_edge&0x2000`, `rpt&0x1000/0x2000/0x4000/0x8000` | `+0x11 = 3` |
| 0x10 | `0x80068a54` | — | — | (label dentro de `0x80068024`) |
| 0x11 | `0x80068bc0` | — | — | `+0x11 = 0xa`/`3` (7 sítios) |
| 0x12 | `0x80068ab4` | — | — | (label) |
| 0x13 | `0x80068b5c` | — | — | (label) |

**Nomes dos subestados: NÃO PROVADOS**, exceto 0 (grade do inventário), 4 (→ mapa),
5 (→ arquivo), 0xd (→ arquivo) e 0xb (entrada de kind 1). Não invento os outros.

### 6.3 Subestado 0 — a grade do inventário, decodificada instrução por instrução

`0x80066604` (`ctx+0x1c` = cursor, `inv = *(u32*)0x800d23b4`):

```c
confirm = (raw_edge & 0x0020) | (log_edge & 0x2000);      // 0x80066620..0x80066634
if (confirm) { ESP(5); ctx->state++; return; }             // 0x80066744 -> estado 3 -> 13
if (log_edge & 0x1000) {                                   // 0x80066638
    c = (s8)ctx->cursor;
    if (c >= 0) {
        slot = inv + c*4;                                  // 0x80066654 (slot de 4 B)
        if (slot->id != 0) { ESP(6); ctx->sub = 1; ctx->u8[0x1e] = 4;
                             ctx->layers &= ~0x20000000;
                             ctx->u16[0x2a] = *(u16*)(slot+2); }   // 0x80066674..0x800666ac
        else               { ESP(7); }                     // 0x800666b0 (slot vazio)
    }
    if (c == -1) { ESP(9); ctx->sub = 4; ctx->u8[0x12]=0; ctx->u8[0x13]=0; }  // 0x800666c4
    if (c == -2) { ESP(9); ctx->sub = 5; ctx->u8[0x12]=0; ctx->u8[0x13]=0;
                   ctx->s16[0x144] = -0xd8; }              // 0x800666f8
    if (c < -2)  return;
}
// navegacao (com auto-repeat, gs+0x2100)
moveu = 0;
if (rpt & 0x1000 /*UP*/    && c >= -2)                 { ctx->cursor -= 2; moveu = 1; }  // 0x8006676c
if (rpt & 0x4000 /*DOWN*/  && c < inv->count-2)        { ctx->cursor += 2; moveu = 1; }  // 0x800667a8
if (rpt & 0x8000 /*LEFT*/  && (c & 1))                 { ctx->cursor -= 1; moveu = 1; }  // 0x800667ec
if (rpt & 0x2000 /*RIGHT*/ && !(c & 1))                { ctx->cursor += 1; moveu = 1; }  // 0x80066834
if (moveu) ESP(4);                                                                       // 0x80066880
```

**A grade tem 2 colunas** (`cursor & 1` = coluna, `±2` = linha) e `count` vem de
`inv+0x12a` (`0x800667c4`). `cursor == -1` e `cursor == -2` são as **duas entradas abaixo/acima
da grade** (levam aos subestados 4 e 5, i.e. MAPA e ARQUIVO). Isso casa com a UI real do RE3
(inventário 2×N + duas linhas de menu), mas **quantas linhas visíveis e onde na tela: NÃO MEDIDO
aqui** (as coords estão em `ctx+0xf0..0x144`, §9).

---

## 7. A pausa — PROVADO por `task_suspend`/`task_resume`

```
0x8006d97c   jal 0x80032160   a0 = 0     ; menu_init  -> task_suspend(0)
0x8006e248   jal 0x80032184   a0 = 0     ; menu_exit  -> task_resume(0)
```

**São os únicos dois sítios de `0x80032160`/`0x80032184` em todo o `.text`** (varredura completa
de `jal`, `tools/exe_fn.py`). Portanto:

- **Enquanto o menu está aberto, a task 0 não roda.** A task 0 é a task raiz do jogo
  (`set_task_entry(0, 0x80029b94)` em `0x80029940`, único set para o slot 0 fora dos overlays;
  o fluxo de jogo `0x80023268` roda dentro dela). Tudo que depende do tick da task 0 — mundo,
  inimigos, SCD, timers de veneno — **congela**.
- O que **continua** rodando é o laço principal `0x80028f38`: leitura de pad (`0x80037fa0`,
  sítio `0x80029094`), escalonador (`0x8002921c`), animação de ESP/transição (`0x800741a0`,
  sítio `0x80029264`), `0x80011dc4`, `0x80029d08` e o flip (`0x80029294`).
- **Não achei nenhum contador de gameplay decrementado fora da task 0**, então a leitura é:
  o relógio de jogo para. **Confirmação por trace em emulador ainda não feita** (§13).

### 7.1 A PAUSA DO START é outra coisa (`0x800d4434`)

No laço principal, `0x80029144`:

```c
if (raw_edge & 0x0800 /*START*/) {
    if (*(s32*)(gs+0x246c) >= 0) { raw_edge ^= 0x0800; pause = 2; }
    else if (*(u8*)(pad_buf+0) == 0xff) pause = 1;
    *(u8*)0x800d4434 = pause;                 // 0x80029184
    0x8007745c(0); 0x8007745c(1); 0x8007745c(2);   // pausa audio por canal
    *(u8*)(gs+0x2488) = 1;
}
if (*(u8*)0x800d4434 != 0) { 0x8002a2b8(); ...; se START de novo: 0x80077554(0..2); pause = 0; }
0x80031e5c();   // escalonador roda mesmo pausado
```

E a task do menu **testa esse byte**: `if (*(u8*)0x800d4434 != 1)` (`0x8006e01c`) antes de rodar
`handlers[]` e `anim()`. Ou seja: com o menu aberto, apertar START congela a **lógica** do menu
mas o **desenho** (`0x8006e34c`) continua. `0x800d4434 == 2` não bloqueia o menu (só `== 1`).

---

## 8. Tempo: o menu roda a **60 Hz**, o jogo a **30 Hz**

O flip (`0x80029294`) espera assim:

```asm
800292e8  lbu $v1, 0x18c($s5)     ; s5 = 0x800d42a0  ->  divisor = *(u8*)0x800d442c
800292ec  lw  $v0, 0x454c($a0)    ; contador de vblank = *(u32*)0x800d454c
800292f4  sltu $v0, $v0, $v1
800292f8  bnez $v0, 0x800292ec    ; while (contador < divisor) ;
80029304  sw  $zero, 0x454c($v0)  ; contador = 0
80029308  jal 0x8008b664          ; DrawOTag
```

`0x800d442c` = **vblanks por frame lógico**. Valores medidos:

| valor | escrito em | contexto |
|---|---|---|
| **1** | `0x8006d9a8` | **`menu_init`** → menu a 60 Hz |
| **2** | `0x8006e24c` | **`menu_exit`** (no delay slot do `task_resume`) → volta a 30 Hz |
| 2 | `0x8002485c` | `game_init` |
| 1 | `0x800157c8`, `0x80023b3c` | outras telas |
| 2, 3 | `0x80024d1c`, `0x80024e48`, `0x80024f34` | transição de sala |

`0x800d454c` só é lido/zerado no `.text` — quem o incrementa é o callback de VBlank
(registrado via `0x80090588`), fora do `.text` analisável. **A afirmação "menu = 60 Hz" depende
de o VBlank ser 60 Hz NTSC**, o que é o caso do hardware; não medi o callback.

### 8.1 Auto-repeat do d-pad — **10 frames de espera, depois 1 a cada 7**

`menu_init` chama `0x80038634(a0 = 0xf00c, a1 = 0x060a)` em `0x8006d998`.

`0x80038634(mask, delays)` registra os bits para auto-repeat num bloco em `0x800de628`:

```c
void pad_repeat_cfg(u32 mask, u16 delays) {   // 0x80038634
    r = (u8*)0x800de628;
    *(u16*)(r+4) = delays;      // r[4] = delay inicial, r[5] = intervalo
    p = r + 8; i = 0; n = 0;
    while (mask) { if (mask & 1) { p[0] = i; p += 2; n++; } mask >>= 1; i++; }
    r[6] = n;
}
```

E o consumo, no fim de `0x80037fa0` (`0x80038558`..`0x80038600`):

```c
for (k = 0; k < r[6]; k++) {
    bit = r[8 + 2*k];  m = 1u << bit;  c = &r[9 + 2*k];
    if (raw_edge & m) { *c = r[4]; gs->pad_rpt /*+0x2100*/ |= m; }
    if (raw_held & m) { if (*c) (*c)--; else { *c = r[5]; gs->pad_rpt |= m; } }
}
```

Com `a1 = 0x060a`: `r[4] = 0x0a = 10`, `r[5] = 0x06 = 6`.
Traçando: dispara no frame 0 (borda), o contador cai 10→0 nos frames 1..9 (fica 0 no fim do 9),
frame 10 dispara e recarrega 6, frames 11..16 zeram, frame 17 dispara. Ou seja:
**disparo em 0, 10, 17, 24, 31, …** → **espera inicial 10 frames, repetição a cada 7 frames**
(a 60 Hz, ≈167 ms e ≈117 ms).

`a0 = 0xf00c` = `UP|RIGHT|DOWN|LEFT` (`0x1000|0x2000|0x4000|0x8000`) **+ `L1|R1`**
(`0x0004|0x0008`) — só esses 6 bits têm auto-repeat no menu. Para comparação, `TITLE.BIN`
chama `0x80038634(0x5000, 0x020a)` = só UP/DOWN, delay 10 / intervalo 2.

### 8.2 A animação de abertura — **6 frames**

Três palavras em `0x800e0610 + 0xb1c/0xb20/0xb24`:

| endereço | papel |
|---|---|
| `0x800e112c` | **tipo/atividade** da transição (0 = nenhuma) |
| `0x800e1130` | **nível**, 0..0x3fff |
| `0x800e1134` | **passo por frame**, com sinal |

`menu_init` (`0x8006da20`..`0x8006da34`): `tipo = 0x80; nivel = 0x3fff; passo = +0xb00`.
`h13` (`0x8006e538`..`0x8006e544`): `tipo = 0x80; nivel = 0; passo = -0xb00`.

O motor é `0x800741a0` (1×/frame, do laço principal), em `0x8007420c`:

```c
if (tipo == 0) skip;
if (passo >= 0) { if ((u32)passo < nivel) nivel -= passo; else { nivel = 0;      passo = 0; } }
else            { if (nivel < (u32)(passo + 0x3fff)) nivel -= passo; else { nivel = 0x3fff; passo = 0; } }
```

e as posições são interpoladas por `pos = (alvo * nivel) / 0x3fff`
(`0x800743d0`..`0x80074430`: `mult` pelo nível, `multu` pelo recíproco de `0x3fff`, `srl 13`).

`0x3fff / 0xb00 = 16383 / 2816` → sequência `16383, 13567, 10751, 7935, 5119, 2303, 0`:
**6 frames**. `0x800e112c` é zerado quando o nível chega a 0 (`0x800744e8`), e o **estado 0
espera exatamente isso** (`0x8006e450`: `if (*(u32*)0x800e112c != 0) return`). Logo:

> **Abrir: 6 frames de animação (a 60 Hz ≈ 100 ms) em que o menu ainda não aceita input.
> Fechar (estado 13, subestado 0→1): outros 6 frames, e só então `ctx+0x27 = 0`.**

### 8.3 `h13` — o fechamento, literal

```c
void h13(Menu* ctx) {                                  // 0x8006e4cc
    if (ctx->sub == 0) {
        0x8002a35c(0, 0, 2, 2, /*sp*/0, 0x00ffffff, 6);
        *(u32*)0x800e112c = 0x80;
        *(u32*)0x800e1130 = 0;
        *(u32*)0x800e1134 = -0xb00;
        ctx->sub++;                                     // -> 1
    } else if (ctx->sub == 1) {
        if ((0x8002a6bc(0) & 4) && *(u32*)0x800e112c == 0)
            ctx->open /*+0x27*/ = 0;                    // 0x8006e580 -> task sai do laco
    }
}
```

---

## 9. Fundo, VRAM e camadas

### 9.1 O menu **salva e restaura** um retângulo da VRAM

| momento | chamada | RECT (x, y, w, h) | RAM |
|---|---|---|---|
| `menu_init` kind 0,1,3,4,5 | `StoreImage` `0x8008b30c` (`0x8006dcdc`, `0x8006dd24`, `0x8006dd80`, `0x8006de94`, `0x8006df30`) | **(448, 256, 128, 256)** | `0x8019c000` |
| `menu_init` kind 2 | `StoreImage` (`0x8006ddd0`) | **(448, 256, 64, 256)** | `0x80194000` |
| `menu_exit` kind 0,1,3,4,5 (`0x8006e140`) | `LoadImage` `0x8008b2ac` (`0x8006e164`) | (448, 256, 128, 256) | `0x8019c000` |
| `menu_exit` kind 2 (`0x8006e0f0`) | `LoadImage` (`0x8006e114`) | (448, 256, 64, 256) | `0x80194000` |

Identificação de `0x8008b2ac` = **`LoadImage`** e `0x8008b30c` = **`StoreImage`**: as strings de
debug que cada uma passa a `0x8008b068` — `0x800117fc = "LoadImage"`,
`0x80011808 = "StoreImage"`; e usam campos diferentes do bloco de controle da libgpu
(`+0x20` vs `+0x1c`). Coordenadas em **espaço de VRAM 1024×512, 16 bpp** (não em espaço de
tela 320×240).

Ou seja: **o menu não carrega background próprio**. Ele *empresta* a região de VRAM
`x∈[448,576)`, `y∈[256,512)` (65536 B), copia o conteúdo anterior para a RAM e devolve na saída.
Os gráficos dele (`STMAIN0U.TIM` etc.) já estão em `0x801b1500` desde o `game_init`.

### 9.2 Recarga de BG ao sair

`menu_exit` grava `0x800d442d = 2` (`0x8006e13c`/`0x8006e1a0`) e
`0x800d442e = ctx+0x06 ? 1 : 2` (`0x8006e130`/`0x8006e190`). No flip (`0x80029378`):
`if (*(u8*)0x800d442d == 2 && *(u8*)0x800d442e != 0) → 0x80029e3c`, que faz `cd_read_file`
(`0x80029f88`, `a2 = 2`). **Leitura:** ao fechar o menu o jogo re-lê o background da sala do CD.
Isso é coerente com o menu ter reaproveitado VRAM. **Não provei que o arquivo lido é o BG da
sala** (o `a0` vem de variável) — marcar como FORTE, não PROVADO.

### 9.3 `ctx+0x18` = camadas a desenhar

`draw(ctx)` = `0x8006e34c` → `switch(kind)` (tabela `0x8001104c`):

| kind | stub | condição | função de desenho |
|---|---|---|---|
| 0,1 | `0x8006e3c0` | `ctx+0x18 & 0x40000000` | `0x8006b66c` (painel de status/inventário) |
| | | `ctx+0x18 & 0x00200000` | `0x80070244` (mapa) |
| | | `ctx+0x18 & 0x00100000` | `0x80063fe4` (arquivo) |
| 2 | `0x8006e3b0` | — | `0x800654a8` |
| 3 | `0x8006e3f8` | `ctx+0x18 & 0x00100000` | `0x80063fe4` |
| 4,5 | `0x8006e38c` | `ctx+0x18 & 0x00200000` | `0x80070244` |

Outros bits vistos sendo setados: `0x20000000` (`0x800665a8`, limpo em `0x80066698`),
`0x04000000` (`0x8006df84`, `0x8006440c`), `0x00800000` (lido em `0x8006e2f8` → acelera o
contador `ctx+0x32` de 1 para 3 por frame), `0x00400000` (`0x800643f8`).

### 9.4 Coordenadas do painel — onde estão, mas **não medi o espaço**

`menu_init` kind 0 (`0x8006df00`) e o estado 1 (`0x80066530`) escrevem, como `s16`:

```
ctx+0xf0 = ctx+0xf4 = ctx+0xf8 = ctx+0xfc = ctx+0x100 = 0x48   (72)
ctx+0x104 = ctx+0x108 = ctx+0x11c = ctx+0x144 = -0xd8          (-216)
ctx+0x10e = 0x30                                               (48)
```
(kind 1, `0x8006de64`, difere: `ctx+0x104 = 0`, `ctx+0x11c = -0xd8`.)

`-0xd8 = -216` combinado com o "alvo × nível / 0x3fff" da §8.2 é claramente **posição de entrada
fora da tela** de um painel que desliza. **Mas eu NÃO medi em que espaço** (320×240 do PS1,
ou coordenadas locais do sprite, ou offset relativo ao centro). **NÃO MEDIDO** — quem for
implementar precisa fechar isso em `0x8006b66c`/`0x800741a0` antes de usar esses números.

---

## 10. Som — o que eu consegui provar e o que NÃO

**O módulo do menu (`0x80063000..0x80075000`) não chama NENHUMA das funções de SE do EXE**,
nem direta nem indiretamente até 3 níveis de profundidade. Alvos testados:
`0x80038678` (SE em loop), `0x80038704` (SE one-shot), `0x8003879c` (SE com pan),
`0x8002f2f8`, `0x8002f358`. Reproduzir: alcançabilidade reversa sobre o grafo de `jal`
(script em §12). Os 13 chamadores de `0x80038704` são todos de gameplay
(`0x8003b244`, `0x8003ca88`, `0x80042e34`, `0x80051b40`, …).

O que o menu **faz** para dar feedback é enfileirar um **ESP** com `0x800746c0`:

```c
void esp_push(u32 id, void* mtx, u16 a2, u16 a3) {     // 0x800746c0
    p = *(void**)0x800e10e4;                            // ponteiro livre da fila
    if (p == (void*)0x800e10e4) return;                 // fila cheia
    if ((*(u32*)0x800cc858 & 0x10000000) && ((id>>8)&0xff) >= 5) return;
    p[0x1e] = id >> 16;  p[0x1f] = (id >> 8) & 0xff;  *(u16*)(p+0x1c) = id & 0xff;
    memcpy(p+8, mtx, 16);  *(u16*)(p+0x1a) = a2;  *(u16*)(p+0x18) = a3;
    *(void**)0x800e10e4 = p + 0x20;                     // registros de 32 B
}
```

Ids `a0` disparados de dentro do menu (58 sítios, todos com `a1=a2=a3=0`), e a ação que os
precede quando eu conseguí ler o contexto:

| id | quando (sítio) | leitura |
|---|---|---|
| **4** | cursor do inventário se moveu (`0x80066880`, sub0); lista de arquivo (`0x800638f4`) | **mover cursor** |
| **5** | cancelar/sair (`0x8006675c` sub0; `0x80063c20`; `0x8006a514`; `0x8007021c`) | **cancelar/voltar** |
| **6** | selecionar item não-vazio (`0x8006669c` sub0); `0x8006a2b4`, `0x80069454` | **confirmar** |
| **7** | slot vazio (`0x800666bc` sub0); `0x80067e90`, `0x80067ebc` | **inválido/bloqueado** |
| **8** | `0x80063984`, `0x80063a2c` (só na lista de arquivo) | NÃO SEI |
| **9** | cursor `-1`/`-2` → abrir submenu (`0x800666f0`, `0x80066728`); `menu_init` kind 5 (`0x8006dd40`) | **abrir sub-tela** |
| `0x215` | kind 2 (`0x80064b2c`, `0x80064bc8`, `0x80064d1c`, `0x80064d90`) | NÃO SEI |
| `0x22b` | `0x8006f790` (mapa) | NÃO SEI |

E, fora do menu, o disparo que acompanha a abertura pelo botão: `0x80023d10` → `esp_push(6)`;
`0x80023db8` → `esp_push(9)`.

> **DECLARAÇÃO EXPLÍCITA: eu NÃO provei que esses ids são sons.** `0x800746c0` é a fila de ESP
> (efeitos), a mesma usada pelo brilho de item (`id = 0x0705 | …`, já documentado no repo).
> A correlação id→ação acima está provada (é o código); **id→SE (banco/VAG) NÃO ESTÁ**.
> Para fechar, é preciso desmontar o consumidor da fila (`0x800e10e4`, registros de 32 B,
> provável `0x800749a0`/`0x80074cd0`) e ver se ids pequenos (`< 0x100`) caem num
> `se_play`. **NÃO MEDIDO.**

---

## 11. O pad — layout provado, remap e semântica

### 11.1 A palavra RAW (`gs+0x20f8 = 0x800cc830`)

```asm
800381ec  lbu $v0, 0x20b2($s1)     ; buff[2] do libpad
800381f0  lbu $v1, 0x20b3($s1)     ; buff[3]
800381f4  sll $v0, $v0, 8
800381f8  nor $a0, $v1, $v0        ; ~(buff[3] | (buff[2]<<8))
800381fc  andi $a1, $a0, 0xffff
8003820c  sw  $a1, 0x20f8($s1)     ; RAW = 1 quando pressionado
```

Como `buff[2]` vai para o **byte alto** (o inverso da convenção `PAD_*` da libpad), o mapa de
bits do RE3 é **byteswapped**:

| bit | RE3 | | bit | RE3 |
|---|---|---|---|---|
| `0x0001` | L2 | | `0x0100` | SELECT |
| `0x0002` | R2 | | `0x0200` | L3 |
| `0x0004` | L1 | | `0x0400` | R3 |
| `0x0008` | R1 | | `0x0800` | **START** |
| `0x0010` | △ | | `0x1000` | **UP** |
| `0x0020` | ○ | | `0x2000` | **RIGHT** |
| `0x0040` | ✕ | | `0x4000` | **DOWN** |
| `0x0080` | □ | | `0x8000` | **LEFT** |

Checagens cruzadas que fecham: pausa = `raw_edge & 0x0800` = START (§7.1); auto-repeat
`0xf00c` = d-pad + L1/R1 (§8.1); `raw_held & 0x5000` = UP|DOWN (`0x80064bfc`);
`raw_held & 0xc` = L1|R1 (`0x80064c50`); e os 4 primeiros slots do remap são exatamente
`0x1000/0x2000/0x4000/0x8000` (§11.3).

### 11.2 As 5 palavras de pad em `gs = 0x800ca738`

| endereço | off | conteúdo | produzido em |
|---|---|---|---|
| `0x800cc830` | `+0x20f8` | **raw held** | `0x8003820c` |
| `0x800cc834` | `+0x20fc` | **raw edge** = `(prev_raw ^ raw) & raw` | `0x80038534`..`0x80038554` |
| `0x800cc838` | `+0x2100` | **raw com auto-repeat** (só os bits registrados, §8.1) | `0x800385a8`, `0x800385f0` |
| `0x800cc83c` | `+0x2104` | **lógico held** (pós-remap) | `0x8003842c`..`0x80038454` |
| `0x800cc840` | `+0x2108` | **lógico edge** = `(prev_log ^ log) & log` | `0x80038564` |
| `0x800cc844` | `+0x210c` | lógico do frame anterior | `0x80038430` |

O remap (`0x80038434`..`0x80038464`):
```c
gs->log_prev = gs->log_held;  gs->log_held = 0;
for (i = 0; i < 16; i++) if (gs->raw_held & ((u16*)0x8009cc7c)[i]) gs->log_held |= (1u << i);
```

### 11.3 A tabela de remap `0x8009cc7c` (16 × u16) e as 3 alternativas

Só existe **um** acesso a ela no EXE: o `lhu` de leitura em `0x80038434`. Quem escreve é o
overlay `OPTION` (não verifiquei lá). Conteúdo do EXE virgem:

| log bit | máscara lógica | raw @`0x8009cc7c` | botão | @`+0x20` | @`+0x40` | @`+0x60` |
|---|---|---|---|---|---|---|
| 0 | `0x0001` | `0x1000` | UP | `0x1000` | `0x1000` | `0x1000` |
| 1 | `0x0002` | `0x2000` | RIGHT | `0x2000` | `0x2000` | `0x2000` |
| 2 | `0x0004` | `0x4000` | DOWN | `0x4000` | `0x4000` | `0x4000` |
| 3 | `0x0008` | `0x8000` | LEFT | `0x8000` | `0x8000` | `0x8000` |
| 4 | `0x0010` | `0x1000` | UP | `0x1000` | `0x1000` | `0x1000` |
| 5 | `0x0020` | `0x4000` | DOWN | `0x4000` | `0x4000` | `0x4000` |
| 6 | `0x0040` | `0x00a0` | ○ ou □ | `0x0040` ✕ | `0x0040` | `0x0040` |
| 7 | `0x0080` | `0x00a0` | ○ ou □ | `0x0040` ✕ | `0x0040` | `0x0040` |
| 8 | `0x0100` | `0x0008` | **R1** (mira) | `0x0008` | `0x0008` | `0x0008` |
| 9 | `0x0200` | `0x0040` | ✕ | `0x0080` □ | `0x0080` | `0x0080` |
| 10 | `0x0400` | `0x0002` | **R2** (mira) | `0x0002` | `0x0002` | `0x0002` |
| 11 | `0x0800` | `0x0004` | L1 | `0x0004` | `0x0004` | `0x0004` |
| 12 | `0x1000` | `0x00a0` | ○ ou □ | `0x0040` ✕ | `0x0040` | `0x0040` |
| 13 | `0x2000` | `0x0040` | ✕ | `0x0010` △ | `0x0090` △\|□ | `0x0010` |
| 14 | `0x4000` | `0x0010` | **△** | `0x0020` ○ | `0x0020` | `0x0020` |
| 15 | `0x8000` | `0x0000` | — | `0x0000` | `0x0000` | `0x0000` |

A máscara `0x500` (= log 0x100|0x400) confirmada como MIRA em `exe_combat.md` bate: R1 ou R2.

### 11.4 Semântica lógica no menu (independente de config)

| bit lógico | uso medido |
|---|---|
| `0x4000` | **abrir a tela de status** (`0x80023c9c`, `log_edge & 0x4000` → pedido) — default = △ |
| `0x1000` | **selecionar/entrar** (`0x80066638` sub0; `0x8006a324`/`0x8006a4f8` usam `0x3000`) |
| `0x2000` | **cancelar/sair** (`0x8006662c` sub0, `0x80063898` h8, `0x8006f7a0` mapa) — default = ✕ |
| `0x0020` (**RAW**, ○) | alternativa de cancelar, lida direto do raw: `raw_edge & 0x20` em `0x80066628`, `0x80064484`, `0x80066620` |
| raw `0x0001` (L2) | **abrir o mapa** direto do gameplay (`0x80023cbc`) |
| raw `0x0800` (START) | pausa global (§7.1) |
| raw `0x0100` (SELECT) | outro caminho no fluxo de jogo (`0x80023ce4`) → `esp_push(6)` e `0x800cc858 \|= 0x00100000`. **Não investiguei o que essa tela é.** |
| `rpt 0x1000/0x2000/0x4000/0x8000` | navegar (UP/RIGHT/DOWN/LEFT com auto-repeat) |
| raw `0x0004`/`0x0008` (L1/R1) | paginar em kind 2 e no mapa (`0x80064c50`, `0x80064bfc`) |

> **Atenção ao implementar:** o "cancelar" do inventário é testado **antes** do "entrar"
> (`bnez` em `0x80066634` com o `andi 0x1000` no delay slot). Com o remap virgem, o bit lógico
> `0x1000` inclui ○ (`0x00a0`), e ○ também satisfaz o `raw_edge & 0x20` do cancelar — logo o
> cancelar ganha. Com os presets `+0x20/+0x40/+0x60` (log `0x1000 ← 0x0040 = ✕`,
> log `0x2000 ← 0x0010/0x0020`) a coisa fica coerente. **Qual bloco é o default efetivo em
> runtime eu NÃO PROVEI** (depende do `OPTION`/save). É a primeira coisa a fechar antes de
> mapear botões no port.

---

## 12. Como medir de novo

```bash
# funcoes, callers, args constantes
PYTHONIOENCODING=utf-8 python tools/exe_fn.py                 # so conta as funcoes
PYTHONIOENCODING=utf-8 python tools/menu_ingame.py            # tabela de estados/subestados

# overlay PC_SYS
python tools/overlay_parse.py PC_SYS --info --strings --states --calls
```

```python
# quem chama X, e com que argumentos constantes
import sys; sys.path.insert(0,'tools')
from exe_fn import Ana
a = Ana()
for s in a.jal[0x80012818]:                       # cd_read_file
    print(hex(s), hex(a.fn_of(s)), {k: hex(v) for k, v in a.args(s).items()})

# quem toca um endereco global (com $a0 semeado = ctx)
from exe_struct import scan_fn
for fn in a.starts:
    for ad, m, reg, ea, br, d in scan_fn(a, fn, seed={'$a0': 0x800e01c0}):
        if ea == 0x800e01e7: print(hex(ad), m, hex(fn))

# alcancabilidade reversa (usado para o "menu nao toca SE")
import collections
callers = collections.defaultdict(set)
for ad, m, o in a.ins:
    if m == 'jal': callers[int(o.strip(), 0)].add(a.fn_of(ad))
lvl = {t: 0 for t in (0x80038678, 0x80038704, 0x8003879c, 0x8002f2f8, 0x8002f358)}
front = set(lvl)
for d in (1, 2, 3):
    nf = set()
    for t in front:
        for c in callers[t]:
            if c not in lvl: lvl[c] = d; nf.add(c)
    front = nf
print([hex(f) for f in lvl if f and 0x80063000 <= f < 0x80075000])   # -> []
```

**Cuidado com `tools/exe_fn.py`:** `fn_of()` usa o último prólogo `addiu $sp,$sp,-N` antes do
endereço. Funções-folha sem prólogo (ex.: `0x800643e4`, `0x8006a888`, `0x80064460`) são
atribuídas à função anterior. Sempre confira com `Ana.dump()`. E `scan_fn(..., seed={'$a0':ctx})`
só é válido para funções que **realmente** recebem o ctx em `a0` — a lista de 40 dessas está
na §"funcoes com a0=ctx" produzida pelo ponto-fixo em `tools/menu_ingame.py`.

---

## 13. EM ABERTO / NÃO MEDIDO

1. **`ctx+0x04 == 2` (kind 2): que tela é.** Único escritor `0x800514cc` (fn `0x800513cc`, módulo
   de mensagem). Usa `0x801a1500`, RECT de 64 px de largura, `ITEMA.SLD`, 5 subestados em
   `0x8009f4e4`, paginação L1/R1, ESP `0x215`. Hipótese não testada: baú de itens. **NÃO SEI.**
2. **Nomes dos 20 subestados** de `0x800a0100` (só 0, 4, 5, 0xb, 0xd têm papel provado) e dos
   5 subestados do mapa (`0x800a0500`). Só medi ESP/pad/escritas de estado, não o desenho.
3. **Ids de ESP → SE.** Provei id↔ação, não id↔som. Falta desmontar o consumidor da fila
   (`0x800e10e4`). Ver §10. Sem isso, **não use "id 4 = beep de cursor" como fato.**
4. **Coordenadas de tela.** `ctx+0xf0..0x144` (`0x48`, `-0xd8`, `0x30`) existem e são
   interpoladas pelo nível da transição, mas **em que espaço** (320×240? local do sprite?)
   **NÃO MEDIDO**. Nada de layout de grade, tamanho de célula, cor ou CLUT foi medido aqui.
5. **Quantas linhas/slots visíveis** na grade do inventário. Só provei 2 colunas
   (`cursor & 1`) e `count = inv+0x12a`.
6. **60 Hz do menu**: provei `0x800d442c = 1` no init e `= 2` no exit, e que o flip espera
   `0x800d454c >= 0x800d442c`. **Não** achei o incremento de `0x800d454c` (é no callback de
   VBlank, fora do `.text`); a leitura "1 vblank = 1/60 s" é do hardware, não medida.
7. **Recarga de BG ao sair** (§9.2): `0x800d442d = 2` + `0x800d442e != 0` → `0x80029e3c`, que
   faz `cd_read_file` com `a0` de variável. **Não provei que é o BG da sala.**
8. **A afirmação "o relógio de gameplay para"**: provei que a task 0 é suspensa e que ela é a
   task raiz do jogo. Não varri *todos* os contadores para garantir que nenhum é decrementado
   pelo laço principal ou por `0x800741a0`/`0x80011dc4`/`0x80029d08`. Verificação por trace em
   emulador **não feita**.
9. **`raw_edge & 0x0100` (SELECT) em `0x80023ce4`** liga `0x800cc858 |= 0x00100000`, que segundo
   `menu_overlays.md §7.1` carrega o overlay `JILL_SEL`. Não faz sentido in-game; **não
   investiguei.**
10. **Qual bloco de key-config está ativo em runtime** (§11.3/§11.4). Depende do `OPTION` e do
    save. Antes de mapear botões no port, isso precisa ser fechado.
11. **`0x8006e598`** (retorno gravado em `ctx+0x34`): lê `gs+0x255e`/`gs+0x2558`
    (`0x800ccc96`/`0x800ccc90`) e devolve 5 quando o bit `0x100` está setado. Papel não fechado.
12. **`ctx+0x14` bit 30** ("recarregar `ITEMA.SLD`"): quem o liga fora do menu não foi rastreado.
13. **`0x8002a35c` / `0x8002a6bc` / `0x8002a338`**: usadas no init/exit e no gate do estado 0
    e do estado 13 (`0x8002a6bc(0) & 4`). São o pipeline de sprite/prim do array
    `0x800d443c + a0*0x44` (herdado de `menu_overlays.md §9.1`, **não reverifiquei**).


---

# CORRECOES DA AUDITORIA

Revisao adversarial independente (remedida do zero com `tools/exe_parse.py` sobre
`extracted/ntsc-u/SLUS_009.23` e leitura direta de `BIN/PC_SYS.BIN`). O texto acima **nao foi
apagado**; o que esta errado esta listado aqui.

**Veredito: PARCIAL.** A tese central (`PC_SYS.BIN` = terminal de senhas; o menu de jogo esta no
EXE como task 1, entry `0x8006dfdc`, ctx `0x800e01c0`) esta **CONFIRMADA**, e 26 de 28 numeros
remedidos batem instrucao por instrucao. Ha **um erro de endereco com impacto direto no
mapeamento de botoes** (secao A/B) e tres imprecisoes de redacao (C, D, E).

## A. ERRADO - a tabela de remap do pad **nao** e `0x8009cc7c`

O paragrafo 11.3 e o campo "Tabela de remap logico (key config ativa)" afirmam base `0x8009cc7c`,
com prova `lui 0x800a + addiu -0x3384 em 0x800381b8/0x800381bc`. **O imediato em `0x800381bc` e
`-0x3364`, nao `-0x3384`:**

```asm
800381b8  lui   $v0, 0x800a
800381bc  addiu $v0, $v0, -0x3364      ; = 0x8009cc9c  (NAO 0x8009cc7c)
800381c0  lbu   $v1, 0x195($a0)        ; a0 = 0x800d42a0 -> cfg = *(u8*)0x800d4435
800381c8  sll   $v1, $v1, 5            ; cfg * 0x20
800381cc  addu  $s0, $v1, $v0          ; $s0 = 0x8009cc9c + cfg*0x20
...
80038434  lhu   $v0, ($s0)             ; laco de 16 bits do remap
```

**Valor certo: a tabela ativa e `0x8009cc9c + cfg*0x20`, com `cfg = *(u8*)0x800d4435`.**
(Escritores de `cfg`: `0x800383c4` e `0x80024c30`; valor inicial no arquivo do EXE = **0**.)

O array de 4 blocos de 16 x u16 realmente **comeca** em `0x8009cc7c`, mas o codigo so alcanca
`0x8009cc7c` por **outro** sitio, `0x800383f8` (`addiu $s0, $v0, -0x3384`), num ramo guardado por
`*(u8*)0x800c79ae != 0` que **tambem sobrescreve a palavra raw do pad** (`sh $v1, -0x37d0($v0)`
= `0x800cc830`) a partir de um buffer gravado - ou seja, e o caminho de **input gravado/demo**,
que usa uma key-config fixa. Varredura completa: `$s0` e escrito exatamente 2 vezes entre
`0x800381cc` e o laco em `0x80038434` - `0x800381cc` (normal) e `0x800383f8` (demo).
Portanto **"unico acesso no EXE e leitura" tambem esta errado** (sao 2 sitios hi/lo, mais 2
escritores do indice `cfg`).

## B. ERRADO, por consequencia de A - botao default que abre a tela de status

O campo "Botao que ABRE a tela de status: bit logico 0x4000 (default = Triangulo), prova:
`0x8009cc7c[14] = 0x0010`" esta errado. Com `cfg = 0` (default do EXE), a tabela e `0x8009cc9c`:

| bit logico | mascara | raw @`0x8009cc9c` (cfg=0, **default real**) | botao | valor que a nota dizia (`0x8009cc7c`) |
|---|---|---|---|---|
| 12 | `0x1000` = entrar/selecionar | `0x0040` | **Cruz** | `0x00a0` (Circulo\|Quadrado) |
| 13 | `0x2000` = cancelar/sair | `0x0010` | **Triangulo** | `0x0040` (Cruz) |
| 14 | `0x4000` = **abrir status** | `0x0020` | **Circulo** | `0x0010` (Triangulo) |

Blocos medidos (base `0x8009cc9c`, stride `0x20`):

```
cfg=0  0x8009cc9c  1000 2000 4000 8000 1000 4000 0040 0040 0008 0080 0002 0004 0040 0010 0020 0000
cfg=1  0x8009ccbc  1000 2000 4000 8000 1000 4000 0040 0040 0008 0080 0002 0004 0040 0090 0020 0000
cfg=2  0x8009ccdc  1000 2000 4000 8000 1000 4000 0040 0040 0008 0080 0002 0004 0040 0010 0020 0000
demo   0x8009cc7c  1000 2000 4000 8000 1000 4000 00a0 00a0 0008 0040 0002 0004 00a0 0040 0010 0000
```

`0x8009ccfc` **nao** e um 4o bloco de config: e outro dado (`0x800de648`, `0x800de798`, ...).

**Isso fecha parcialmente o item 10 do paragrafo 13:** o bloco default efetivo do EXE virgem e
`0x8009cc9c` (cfg=0). Abrir o inventario = **Circulo**; cancelar = **Triangulo**; entrar = **Cruz**.

## C. IMPRECISO, por consequencia de A - o "conflito do Circulo" de 11.4 nao existe no default

O aviso "com o remap virgem, o bit logico `0x1000` inclui Circulo (`0x00a0`), e Circulo tambem
satisfaz o `raw_edge & 0x20` do cancelar - logo o cancelar ganha" e artefato de ter lido o bloco
errado. Com `cfg=0`, `log 0x1000 = 0x0040` (so Cruz) e nao ha conflito. O que existe e coerencia:
Circulo abre a tela (`log_edge & 0x4000`) e Circulo tambem fecha (`raw_edge & 0x20` em
`0x80066620`).

## D. IMPRECISO - "o menu nao chama nenhuma funcao de SE"

A alcancabilidade reversa e **reproduzivel** para os 5 alvos que a nota testou
(`0x80038678`, `0x80038704`, `0x8003879c`, `0x8002f2f8`, `0x8002f358`): nenhuma funcao em
`0x80063000..0x80075000` os alcanca em <= 4 niveis (remedi com grafo de `jal` completo, 88 funcoes
alcancaveis, intersecao vazia). **Mas a frase "o modulo do menu (`0x80063000..0x80075000`) nao
chama NENHUMA funcao de SE" e falsa para essa faixa**, porque dentro dela ha 3 chamadas ao modulo
de audio:

| sitio | alvo | o que o alvo faz |
|---|---|---|
| `0x80073fb8` | `0x80077414` | laco `i=0..2` chamando `0x800773c4` |
| `0x80074594` | `0x800772a0` | escreve struct de canal |
| `0x8007489c` | `0x800773c4` | le `0xd8(canal)` |

`0x800772a0`/`0x800773c4` indexam structs em `0x800e06bc + i*0x15c`, **3 canais**, e sao irmas de
`0x8007745c`/`0x80077554` (as que a propria nota identifica como pausa/retomada de audio por canal
no paragrafo 7.1). Esses 3 sitios pertencem ao motor compartilhado de ESP/BGM que roda do laco
principal (`0x800741a0` em `0x80029264`), **nao** ao grafo da task do menu - entao a conclusao do
paragrafo 10 ("o feedback do menu e ESP; id -> SE NAO PROVADO") continua valida. Mas a faixa
`0x80063000..0x80075000` **nao** e "o modulo do menu", e `0x8007489c -> 0x800773c4` e justamente
o fio a puxar para fechar o item 3 do paragrafo 13.

## E. IMPRECISO - rotulo no pseudocodigo de 6.3

O pseudocodigo chama de `confirm` o teste `(raw_edge & 0x0020) | (log_edge & 0x2000)`. Ele e
**CANCELAR**: dispara ESP `5` e faz `ctx+0x10++` (2 -> 3 -> `h3` -> estado 13 = fechamento). O campo
"Confirmar / cancelar / entrar no inventario" da lista de numeros esta correto; so o rotulo do
pseudocodigo engana.

## F. Numeros remedidos e CONFIRMADOS (28 checagens)

Todos verificados desmontando do zero, por caminho proprio quando possivel.

- **`PC_SYS.BIN`**: base `0x801c2000`, entry `0x801c2354`, 16348 B; as **29 strings batem offset a
  offset** (lidas com regex direto no arquivo, sem `overlay_parse`); estado
  `lbu 0x1d26($v0=0x800d0000)` = `0x800d1d26` com `sltiu ..., 5` em `0x801c23dc`; tabela em
  `base+4 = 0x801c2004` = `[0x801c24c4, 0x801c2408, 0x801c241c, 0x801c2468, 0x801c247c]`;
  `jr $v0` em `0x801c2400`.
- **Task do menu**: entry `0x8006dfdc`; **referencia unica** confirmada por dois metodos
  (varredura de imediatos `-0x2024`/`0xdfdc` -> so `0x800235ac`; varredura de **palavras de dado**
  iguais a `0x8006dfdc` em todo o arquivo -> **zero**). Laco de 41 instrucoes identico ao
  pseudocodigo do paragrafo 4.
- **`ctx = 0x800e01c0`** (`addiu $s0, 0x800e0000, 0x1c0` em `0x8006dfe8`); `+0x27` testado em
  `0x8006e000`/`0x8006e06c`, zerado em `0x8006e580`; `+0x10` lido em `0x8006e02c`.
- **Tabelas (conteudo integral conferido, nao so o tamanho):** `0x800a02f0` = 14 ponteiros
  validos, 15a palavra `0x2b302c31`; `0x800a0100` = 20 validos, 21a `0x0120ff20`;
  `0x800a0500` = 5 validos, 6a `0x00000000`; `0x8009f4e4` = 5 validos, 6a `0x010001c0`.
  As 4 tabelas de 6 (`0x8001100c`/`0x80011034`/`0x8001104c`/`0x80011064`) batem entrada por
  entrada com o paragrafo 5.
- **Estados iniciais** `0->1, 1->1, 2->0xa, 3->7, 4->4, 5->4`: desmontei os 5 labels
  (`0x8006e490`=4, `0x8006e498`=4, `0x8006e4a0`=7, `0x8006e4a8`=0xa, `0x8006e4b0`=1) e o
  `sb $v0, 0x10($s0)` comum em `0x8006e4b4`.
- **`0x80073e7c` = `jr $ra; nop`**; unico chamador `0x8006e05c`; a real (`0x80073e84`) tem
  chamador unico `0x80029844`.
- **Pausa**: `jal 0x80032160` em `0x8006d97c` com `a0=$zero` (`0x8006d954`) e `jal 0x80032184` em
  `0x8006e248` com `a0=$zero` (`0x8006e23c`) - **unicos sitios em todo o `.text`** (varredura de
  todos os `jal`). `0x80032160` = `tbl[a0*0x80+4] |= 0x40`, tabela `0x800e0000-0x3470 = 0x800dcb90`.
- **`0x800d442c`**: `sb 1` em `0x8006d9a8` (menu_init) e `sb 2` em `0x8006e24c` (delay slot do
  `task_resume`); flip espera em `0x800292e8`-`0x800292f8` (`lbu 0x18c($s5=0x800d42a0)`,
  `lw 0x454c($a0=0x800d0000)`, `sltu`, `bnez`) e zera `0x800d454c` em `0x80029304`.
  Valor inicial no arquivo = 0.
- **Pausa do START `0x800d4434`**: `andi $v0, $v1, 0x800` em `0x8002914c` sobre
  `lhu 0x20fc($s2)`; `sb $v0, 0x194($s3=0x800d42a0)` em `0x80029184`; menu testa `!= 1` em
  `0x8006e01c`/`0x8006e024` e pula direto para `draw` (`0x8006e054`), **sem** rodar handler nem
  anim. Confirma tambem que so `== 1` bloqueia.
- **Animacao = 6 frames em cada sentido**, remedida nos dois sentidos:
  `0x800e112c/0x800e1130/0x800e1134` (= `0x800e0610 + 0xb1c/0xb20/0xb24`);
  init `0x80/0x3fff/+0xb00` (`0x8006da20/28/34`), h13 `0x80/0/-0xb00` (`0x8006e538/40/44`);
  motor `0x8007420c`-`0x80074270` (chamador unico `0x80029264`);
  zerar `0xb1c` quando `nivel==0 || nivel==0x3fff` em `0x800744d0`-`0x800744e8`.
  Abrir: `16383->13567->10751->7935->5119->2303->0` = 6. Fechar:
  `0->2816->5632->8448->11264->14080->16383` = 6.
- **Auto-repeat 10 / a cada 7**: `ori $a0,$zero,0xf00c` (`0x8006d994`) + `a1=0x60a` (`0x8006d99c`);
  `0x80038634` grava `sh $a1, 4($a3=0x800de628)` -> `r[4]=0x0a`, `r[5]=0x06`, e `sb $a2, 6($a3)`;
  consumo `0x80038578`-`0x800385f0`: os dois `if` sao **sequenciais** (borda e held no mesmo
  frame), logo frame 0 dispara e ja decrementa 10->9; disparos em **0, 10, 17, 24, ...**. Confere.
- **Layout raw do pad**: `0x800381ec`-`0x8003820c` identico ao reportado
  (`nor(buff[3], buff[2]<<8)` -> `0x800cc830`), e as 5 palavras `0x800cc830/34/38/3c/40`
  confirmadas.
- **Abrir**: `lw gs+0x2108` + `andi 0x4000` (`0x80023c94`/`0x80023c9c`) -> `0x800d1f2c |= 0x200`
  (`0x80023ca8`) e `sb $zero, 0x1c4(0x800e0000)` (`0x80023cb0`). **Mapa**: `lhu gs+0x20fc` +
  `andi 1` (`0x80023cb4`/`0x80023cbc`) -> `ctx+0x04 = 4` (`0x80023cd0`). Bit limpo com
  `and -0x201` em `0x800235d0`/`0x800235d4`.
- **Grade 2 colunas**: desmontei `0x80066604`-`0x80066890` inteiro. UP `rpt&0x1000` -> `-2` com
  porta `cursor >= -2` (`slti -2`); DOWN `rpt&0x4000` -> `+2` com `cursor < inv[0x12a]-2`
  (`lbu 0x12a`, `addiu -2`, `slt`); LEFT `rpt&0x8000` -> `-1` se `(cursor & 1)`; RIGHT
  `rpt&0x2000` -> `+1` se `!(cursor & 1)`; `moveu` -> ESP `4` (`jal` em `0x8006688c`, `a0=4` em
  `0x80066880`). As 4 leituras usam a palavra de **repeat** `gs+0x2100 = 0x800cc838` (as duas
  ultimas via `lhu -0x37c8($v0=0x800d0000)`, mesmo endereco).
- **Cursor `-1` -> sub 4 e `-2` -> sub 5, ESP 9**: `0x800666c4`-`0x8006672c`, incluindo
  `sh -0xd8, 0x144($s0)` no caso `-2`.
- **Inventario**: `0x800246dc`-`0x800246fc` literal - `lw 0x7c80($s1)` (`s1=0x800ca738` ->
  `0x800d23b8`), `v1 = (v0*4+v0)<<6` = `*320`, `+ (s1+0x79fc = 0x800d2134)`,
  `sw 0x7c7c($s1) = 0x800d23b4`. Stride 320 confirmado.
- **VRAM**: RECT `(0x1c0, 0x100, 0x80, 0x100)` = **(448, 256, 128, 256)** montado no stack e
  `a1 = 0x8019c000`, conferido em `0x8006dcac` (kind 4) e `0x8006dcf4` (kind 5), e o `LoadImage`
  espelho em `0x8006e140`-`0x8006e164`; kind 2 usa `w=0x40` e `0x80194000` (`0x8006dda0`,
  `0x8006e0f0`). `0x8008b2ac`/`0x8008b30c` passam `0x800117fc`/`0x80011808` a `0x8008b068`, e li as
  strings: `"LoadImage"` / `"StoreImage"`. Espaco = VRAM 1024x512, **nao** 320x240. Confere.
- **`esp_push` `0x800746c0`**: ponteiro livre `0xad4($t0=0x800e0610)` = `0x800e10e4`;
  `p[0x1e]=id>>16`, `p[0x1f]=(id>>8)&0xff`, `*(u16*)(p+0x1c)=id&0xff`; 16 B de `a1`;
  `addiu $v0, $v0, 0x20` em `0x80074760` -> **registros de 32 B**. Guarda
  `(*(u32*)0x800cc858 & 0x10000000) && ((id>>8)&0xff) >= 5 -> return` confirmada
  (`sltiu ...,5` + `beqz` para o epilogo `0x80074768`).
- **Indices de asset do CD - confirmados por caminho INDEPENDENTE.** Em vez de repetir a varredura
  de `cd_read_file`, li a primeira `u32` de cada entrada da tabela `0x800946a4` (stride 8) e
  comparei com o tamanho real do arquivo extraido. **8/8 exatos:**

  | idx | `u32` @ `0x800946a4+idx*8` | arquivo | `getsize` |
  |---|---|---|---|
  | `0x1c` | `0x497800` | `ETC/FILEGU.PIX` | 4814848 |
  | `0x1d` | `0x8220` | `ETC/FILEI.TIM` | 33312 |
  | `0x32` | `0x12230` | `ETC/ITEMA.SLD` | 74288 |
  | `0x33` | `0x14f000` | `ETC/ITEMG.PIX` | 1372160 |
  | `0x34` | `0x43000` | `ETC/ITEMI.PIX` | 274432 |
  | `0x3a` | `0x9b000` | `ETC/MAP_U.MAP` | 634880 |
  | `0x58` | `0x11820` | `ETC/STMAIN0U.TIM` | 71712 |
  | `0x60` | `0x2540` | `ETC/STMOJIU.TIM` | 9536 |

  E os sitios: `0x8006d7f8` (`a0=0x58`, `a1=0x801b1500`), `0x8006d82c` (`a0=0x60`,
  `a1=0x801b1500`). Os 13 sitios de `cd_read_file` na faixa `0x80063000..0x80075000` sao
  exatamente os listados.
- **`0x8006d720` e chamado de um unico lugar**, `0x80024764`; `0x800245a0` (game_init) de
  `0x80023290`. Confere com o paragrafo 2.

## G. Lacunas que a nota declarou e que eu NAO fechei (continuam abertas)

Nao medi e nao invento: coordenadas de tela / espaco das coords `ctx+0xf0..0x144`; numero de
linhas/slots visiveis da grade; identidade do kind 2; nomes dos 20 subestados; id de ESP -> SE;
incremento de `0x800d454c` (callback de VBlank, fora do `.text`); recarga de BG ao sair.
As declaracoes "NAO SEI / NAO MEDIDO" da nota original estao corretas e devem ser mantidas.
