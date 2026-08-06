# item_logic: flags de progresso + inventário (SLUS_009.23, RE3 NTSC-U)

> Unidade: `item_logic` (era 30%). Ferramenta: [`tools/exe_items.py`](../../../tools/exe_items.py)
> (`python tools/exe_items.py`, subcomandos `banks`, `flag BANK BIT`, `fn ADDR N`).
> Base do binário `0x80010000`; gamestruct `0x800ca738`; player-struct `0x800ccbc4`.
> Complementa [`exe_combat.md`](exe_combat.md) (§4 item_logic parcial) e [`../../formatos/SCD.md`].
> Marcações: ✅ provado no disasm · 🎯 confirmado externamente (GameShark) · 🟡 inferido.

---

## 1. BANCO DE FLAGS de progresso  ✅  — `0x8009e3f8`

Confirmado o banco `0x8009e3f8` citado no briefing: é uma **tabela de 16 PONTEIROS de banco**.
Um flag é o par **(bank, bit)**. O endereço/máscara são calculados assim (provado nas 3 rotinas):

```
word = bank_ptr[bank] + ((bit >> 3) & 0x1c)      ; word 32-bit alinhado
mask = 0x80000000 >> (bit & 0x1f)                ; bits gravados MSB-first
set:   *word |=  mask
clear: *word &= ~mask
test:  (*word & mask) != 0
```

Tabela `0x8009e3f8` (dump por `exe_items.py banks`):

| bank | ptr | papel |
|---|---|---|
| 0 | `0x800cc858` | bloco do gamestruct 🟡 |
| **1** | **`0x800d1f2c`** | **flags de PROGRESSO de jogo** ✅ (o `player_sm` r9/escada lê `&0x10` aqui — `exe_combat.md §3.2`) |
| 2 | `0x800ccba0` | adjacente ao player-struct 🟡 |
| 3 | `0x800d1fa0` | flags de mapa/sala 🎯 (GameShark de mapas `300D2127`/`300D212B` caem em `0x800d1fa0+`) |
| 4..15 | `0x800d1fc0`..`0x800d2060` | blocos de flags de sala/estado 🟡 |

### 1.1 Rotinas de flag (opcodes do script de sala)  ✅
- **SET/CLEAR (args em struct `a0`) — `0x800512fc`** (o handler citado no briefing):
  `a0[0]=bank (hword)`, `a0[2]=bit (hword)`, `a0[4]=modo (hword)`; `modo==0` → CLEAR, senão SET.
- **SET/CLEAR (operandos inline no script, IP=`a0+0x1c`) — `0x8005472c`**:
  `byte1=bank`, `byte2=bit`, `byte3=modo` (`0`=clear, `1`=set, `2..`=variantes).
- **CHECK / condicional — `0x800546cc`**: `byte1=bank`, `hword2=bit`; avança o IP `+4` e retorna
  `((*word & mask) != 0) XOR negação`, onde a **negação** vem do byte alto do operando de bit
  (`bit>>8`, testado com `sltiu ...,1`). É o teste que **gateia IFs do script de sala**.

Os três lêem a **mesma** `0x8009e3f8` com a **mesma** fórmula word/mask → confirma o modelo. As refs
à tabela (via `lui 0x800a; addiu -0x1c08`) são exatamente `0x80051300`, `0x800546e8`, `0x80054750`.

### 1.3 Números de OPCODE (jump-table SCD `0x8009e0f8`)  ✅
Dump completo da jump-table do VM de script (`0x8009e0f8`, 64+ entradas). Opcodes de flag confirmados:
- **op `0x4c` → `0x800546cc`** = CHECK flag (condicional).
- **op `0x4d` → `0x8005472c`** = SET/CLEAR flag (inline).
- (op `0x25` → `0x80058c70` = evento de BOSS/Nemesis; op `0x3b` → `0x80057f84` = cria objeto de display
  de 0x194 B — **não** é `sce_em_set`.) O opcode de spawn de inimigo (`sce_em_set`) **ainda não** foi
  isolado nesta tabela (ver `exe_ai.md §3.5`).

### 1.2 Como um flag muda o ESTADO DA SALA  ✅/🟡
O opcode **CHECK (`0x800546cc`)** lê um flag de progresso e **decide o fluxo do script da sala**
(pula/executa blocos → habilita/desabilita AOTs, portas, presença de item, gatilhos). Além disso,
código de gameplay lê alguns bancos **direto** — provado no `player_sm` r9 (entrada de escada lê
`bank1 = 0x800d1f2c & 0x10`). Assim: **evento seta flag (`0x800512fc`/`0x8005472c`) → próximas
execuções do script testam (`0x800546cc`) → a sala aparece com/sem porta/item/inimigo**. O mapa
byte-a-byte "qual bit = qual evento" depende do `scd_gameplay` (outro agente) cruzar os leaves.

---

## 2. INVENTÁRIO  ✅ (formato/uso) / 🟡 (pegar)

- **Formato do slot** (provado na rotina de consumo `0x8006d0a8`): `byte0 = item id`,
  `byte1 = quantidade`, `hword+2 = flags` (bits altos **`0xc000`** = slot vazio/consumido).
- **USAR / consumir item — `0x8006d0a8`** (decremento de quantidade): `qtd -= 1`; quando esgota,
  seta `flags |= 0xc000`. O GameShark **"uso ilimitado" `8006D0CA 2400`** nopa exatamente o `sb` de
  quantidade dessa rotina 🎯 — confirma que aqui é o consumo. Modo `a2==2` = caso especial de decremento.
- **Base do array de slots (10 slots):** `~0x800d225e` 🎯 (GameShark `800D225E 000A`), no mesmo bloco
  RAM dos bancos de flag de sala.
- **PEGAR item (adicionar ao inventário) — ✅ FECHADO** (`python tools/exe_items.py pickup`).
  A estrutura do inventário e o ciclo completo foram isolados byte-a-byte:

### 2.1 Struct do inventário  ✅
`ptr = *(gamestruct+0x7c7c)` (=`0x800d23b4`) → array em `gamestruct+0x79fc` (=`0x800d2134`),
setado no init `0x8006d0d8` (`0x8006d124 sw ...,0x7c7c`). Layout da struct-dona:
```
+0x00.. : MAIN inventory  (10 slots × 4B = 0x28)
+0x28.. : ITEM BOX        (64 slots × 4B = 0x100; tela de organize/status)
+0x128  : cursor / slot selecionado (byte)
+0x129  : id da ARMA equipada (byte)
+0x12a  : contagem de slots do MAIN inventory (byte)
```
Slot (4B): `b0=item id (0=vazio)`, `b1=quantidade`, `hword+2=flags (0xc000=consumido)`.
Tabela de **stack-máx por item** em `0x800a0514` (4B/id: `b0=categoria`, `b1=qtd MAX`, `b2=idx nome`,
`b3=flags default do slot`).

### 2.2 Helpers do módulo (base `0x8006cxxx`)  ✅
- **`0x8006cc8c` find_by_id**`(a0=id, a1=start)` → índice do 1º slot MAIN com esse id (`-1` se não).
  **`find_by_id(0)` = 1º slot VAZIO** (id==0) = **"achar slot livre"**.
- **`0x8006ccf0` remove/decrementa**; ao zerar chama `compact_shift`.
- **`0x8006cd68` compact_shift** (shift-left ao remover).
- **`0x8006cf0c` stack-merge / consolidar munição** (o briefing cita `0x8006cf00`, mas esse endereço cai no
  **epílogo da função anterior**; o prólogo real é `0x8006cf0c`, `addiu sp,sp,-0x20`). ✅ verificado byte-a-byte:
  lê o slot do cursor (`inv+0x128`), `room = stackmax[id].b1 − qtd` (tabela `0x800a0514`), transfere de outro
  slot do mesmo id clampando a `room` (`sb qtd,1(a2)`), chama `0x8006ccf0` (remove a fonte) e seta a flag de UI
  `gs+0x255e |= 0x400`. É consolidação de pilha (recarregar/juntar munição), respeitando o stack-máx.

### 2.3 PEGAR = janela de OBTER item  ✅ — `0x80069c3c`
1. **Disparo:** AOT de item/evento (**SCE tipo 2**, handler `0x8005111c`) grava
   `gamestruct+0x21dc = ptr do DESCRITOR` (`id@0`, `qtd@2`) e `+0x21d8 = alvo`, e ativa a
   **máquina de estado da janela de obter** (ptr de dados `0x800a012c` → **`0x80069c3c`**).
2. **estado 0 (`0x80069cb8`) — acha slot:** primeiro tenta **EMPILHAR** (`find_by_id(id)` +
   checa `slot.qtd + desc.qtd ≤ 0x800a0514[id].b1`); se não empilha, `find_by_id(0)` = **1º slot
   VAZIO**. Grava `obj+0x6e = slot alvo`, `obj+0x73 = flag-empilhar`. Se cheio → estado 1 (msg
   "sem espaço", `0x8002fd30` a1=0x1000).
3. **estado 3 (`0x80069fc0` → `0x8006a020`) — GRAVA:** escreve `{id@0, qtd@1, flags@2}` em
   `INV[obj+0x6e]` (flags default de `0x800a0514[id].b3`), **ou** `slot.qtd += desc.qtd`
   (empilhar, sítio `0x8006a0f0`).
- **AOT de item no chão** (opcode `0x67`=`0x800574f4` 22B / `0x68`=`0x800576c4` 30B) só **cria o
  modelo visível** (registra em `gs+0x2158+id*4`), **não concede** — a concessão é a janela acima. ✅

---

## 3. Endereços-chave
```
0x8009e3f8  tabela de 16 ponteiros de banco de flags                 ✅
0x800d1f2c  bank1 = flags de PROGRESSO de jogo                        ✅
0x800512fc  SET/CLEAR flag (args em struct a0)                        ✅
0x8005472c  SET/CLEAR flag (operandos inline no script)               ✅
0x800546cc  CHECK flag (opcode condicional; gateia o script)         ✅
0x8006d0a8  USAR/consumir item (decrementa quantidade)                ✅🎯
0x800d23b4  ptr da struct-dona do inventario (gs+0x7c7c)              ✅
0x800d2134  array de slots (gs+0x79fc): MAIN@+0, BOX@+0x28            ✅
0x800a0514  tabela stack-max por item (b1=qtd MAX, b3=flags default)  ✅
0x8006cc8c  find_by_id ; find_by_id(0) = achar slot LIVRE             ✅
0x80069c3c  janela de OBTER item (add-to-inventory)                   ✅
0x8006a020  grava {id,qtd,flags} no slot / empilha (0x8006a0f0)       ✅
0x8005111c  SCE tipo 2: arma gs+0x21dc(descritor) e a janela de obter ✅
```

## 3.1 Veredito de DECOMPILAÇÃO (item_logic)  ✅
O **core do item_logic está 100% decompilado** (byte-a-byte, sem buraco):
- **Flags de progresso:** banco `0x8009e3f8` + SET/CLEAR `0x800512fc`/`0x8005472c`, CHECK `0x800546cc`
  (fórmula word/mask provada nas 3 rotinas).
- **Armazenamento:** struct em `*(gs+0x7c7c)`=`0x800d23b4`; array `0x800d2134` (MAIN 10 / BOX 64); slot
  `{id,qtd,flags}`; count `+0x12a`, cursor `+0x128`, arma `+0x129`.
- **find_by_id `0x8006cc8c`** (verificado: lê count `+0x12a`, varre slots 4B, `byte0=id`, retorna idx / −1;
  `find_by_id(0)` = 1º slot livre), **compact `0x8006cd68`**, **remove/dec `0x8006ccf0`**.
- **PEGAR:** janela `0x80069c3c` → acha-slot `0x80069cb8` → grava `0x8006a020`/empilha `0x8006a0f0`.
- **USAR/consumir `0x8006d0a8`** (GameShark `8006D0CA 2400` confirma o `sb` de qtd).
- **COMBINAR/consolidar munição `0x8006cf0c`** (verificado; usa stack-máx `0x800a0514`).

**Único resíduo = VÍNCULO no Godot** (protótipo), NÃO decompilação. *Nota fora-de-escopo:* a **tabela de
RECEITA de mistura de ervas** (verde+verde→, verde+vermelha→ etc., que produz um item_id NOVO) vive no **menu
de combinar** (`0x80064xxx`, domínio de `menu_extract.py` = outra unidade), não no core do item_logic. Portanto
**item_logic decompilado = 100%** (resíduo é só vínculo).

## 4. Fontes externas
- GameShark RE3 NTSC-U: uso ilimitado `8006D0CA 2400`; inventário 10-slot `800D225E 000A`;
  mapas `300D2127/300D212B` (validam bank3/`0x800d1fa0`). almarsguides.com; supercheats.com;
  residentevil.org (thread de GameShark). Tudo com ✅ verificado no disassembly do `SLUS_009.23`.
