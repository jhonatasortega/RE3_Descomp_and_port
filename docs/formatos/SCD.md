# Formato `SCD` — bytecode de eventos da sala (RE3 PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidade `scd`)
> - **Formato:** bytecode de eventos dentro do RDT (bloco 8 do `.ARD`, `offset_table[16]`); opcodes de tamanho fixo
> - **Extensão/origem:** seção SCD do RDT das 169 salas
> - **Ferramenta:** [`tools/scd_decode.py`](../../tools/scd_decode.py) (formato); extração em [scd_gameplay.md](scd_gameplay.md)
> - **Decompilado:** **90%**
> - **Feito:** cabeçalho de script; **VM do script LOCALIZADA e VERIFICADA** (jump-table `0x8009e0f8`); **tamanhos de opcode lidos dos handlers** (`VM_SIZES`) → **100% (4238/4238)** das funções fecham em `evt_end`, zero opcodes inválidos (era 63,6% → 97,1% → 99,95%); opcodes-chave nomeados pelos leaves.
> - **Falta:** nomear os leaves menores e alguns opcodes de controle raros (≥0x90) — ver [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md).
> - **Correções deste round:** interpretador = **`0x8009e0f8`** (o `0x8007688c` é a **VM de IA de entidade**; `0x8009e0bc` a de evento/AOT); a "porta de 62B" = **par `0x67`(22B) + `0x7f`(40B)**; `0x62`=**40** (era 32); `0x64`=28.
>
> **Papel deste doc = FORMATO** (cabeçalho de script + tamanhos de opcode + interpretador).
> Para a **extração de gameplay** (portas/itens/inimigos/gatilhos, IDs, destino, JSONs)
> ver [scd_gameplay.md](scd_gameplay.md). Contêiner da sala em [ARD.md](ARD.md); RE do
> executável em [exe.md](exe.md).

Tudo abaixo foi derivado **dos bytes reais** das 169 salas (não copiado cru da doc de RE2).

---

## 1. Cabeçalho do script (tabela de ponteiros de função)  ✅

O script começa com uma tabela de **offsets u16** (relativos ao início do script), uma
por função/rotina:

```
+0x00  u16  tbl_size            // tamanho da tabela em bytes; nº de funções = tbl_size/2
+0x02  u16  func_offset[...]    // offset de cada função
```

A 1ª entrada (`tbl_size`) marca onde a tabela termina e a 1ª função começa. As funções
são **contíguas** (o fim de uma é o início da seguinte) e terminam com `evt_end` (0x01),
em geral seguido de um `nop` (0x00) de alinhamento. Ex.: `R100` tem 9 funções; `R104`, 23.
A função "main" costuma ser uma série de `gosub` (0x19) chamando as demais.

## 2. Bytecode: opcodes de tamanho fixo  ✅ (VM localizada)

Cada instrução = **1 byte de opcode + N-1 bytes de operando**, com N fixo por opcode.

> ✅ **A VM do script de sala foi LOCALIZADA** (não é mais inferência por restrição). O
> interpretador é a **jump-table `0x8009e0f8`** (256 entradas u32; copiada p/ o scratchpad
> `0x1f800000` no boot da sala — loop `0x80052ba4`, dispatch `0x80052c48`, PC em `obj+0x1c`).
> Cada handler **avança o PC pelo seu tamanho** → os tamanhos vêm dos **handlers** (verdade do
> binário), integrados em `tools/scd_decode.py` (`VM_SIZES`). Com isso **4238/4238 = 100,00%**
> das funções das 169 salas fecham exatamente em `evt_end`, com **ZERO opcodes inválidos**
> (era 97,1% e depois 99,95% por restrição). O fechamento total veio de reler do **epílogo**
> dos handlers os 5 últimos tamanhos errados: `0x3b`=3, `0x3c`=1, `0x24`=1, `0x2f`=1, `0x4b`=1
> (ver [`../decomp/notes/scd_opcodes.md`](../decomp/notes/scd_opcodes.md) §"FECHAMENTO 100%").
> **Não** confundir: `0x8007688c` = **VM de IA de entidade**; `0x8009e0bc`/`0x80050aac` = **VM
> de evento/AOT per-frame**. Ver [exe.md — Interpretador SCD](exe.md) e `../decomp/notes/scd_opcodes.md`.

Tamanhos **CONFIRMADOS** (lidos dos handlers da VM; bytes, incluindo o opcode):

| op | tam | op | tam | op | tam | op | tam |
|---|---|---|---|---|---|---|---|
| 00 nop | 1 | 19 gosub | 2 | 4D | 4 | 65 aot_reset | 10 |
| 01 evt_end | 1 | 1E | 4 | 4C | 4 | **67 door_aot** | **22** |
| 02 evt_next | 1 | 2A | 6 | 50 | 2 | **68 item_aot** | 30 |
| 04 | 2 | 40 | 4 | 54 | 4 | 70 | 16 |
| 06 flag/if | 4 | 41 | 4 | 57 | 6 | 71 | 18 |
| 09 | 4 | 47 | 4 | 58 | 6 | 77 | 12 |
| 0D for | 6 | 48 | 10 | 59 | 8 | 78 | 6 |
| 10 ewhile | 4 | 49 | 4 | **61 entidade** | 32 | **7B map** | 6 |
| 12 | 4 | **63 aot_set** | 20 | **62 entidade** | 40 | **7D** | 24 |
| 14 switch | 6 | **64 aot_4p** | 28 | **7F door dest** | 40 | 82 | 10 |

> **Correções (round VM):** `0x67`=**22** (era 24 — só o head; a porta "de 62B" é o **par**
> `0x67`+`0x7f`, §3.1); `0x62`=**40** (era 32); `0x7f`=**40** (destino/chegada da porta).
> Opcodes nomeados pelos leaves: `0x06`=flag check/set (handler `0x800512fc`),
> `0x7b`=map data, `0x67`=door_aot_set, `0x68`=item_aot_set. `0x14`/switch = 6B (o
> reevengi dá 4B — **divergência menor**; adotado 6 por fechar melhor o corpus). Alguns
> opcodes de controle ≥0x90 raros ainda em aberto (não afetam a extração, que ancora em
> assinaturas). Lista completa em `../decomp/notes/scd_opcodes.md`.

## 3. Opcodes de posicionamento (gameplay)  ✅

Todos compartilham o padrão `[opcode][aot_id][sat/tipo][floor][..][x:s16][z:s16]...`,
com coordenadas em **ponto-fixo com sinal** (mesma escala das câmeras). São localizados
por assinatura (bytes fixos em offsets fixos) e validados por faixa de coordenada.

### 3.1 Porta = PAR de opcodes `0x67` + `0x7f` (22 + 40 = 62 bytes)  ✅
> **Correção (round VM).** A "porta de 62 bytes" **não é um opcode só** — é o **par**:
> **`0x67`** (`door_aot_set`, **22 B**, handler `0x800574f4` — registra o gatilho AOT) **+**
> **`0x7f`** (**40 B**, handler `0x80056510` — destino/chegada). Por isso o parser antigo,
> que lia "62B a partir do 0x67", pegava os dois de uma vez. O espaçamento de 62B entre
> `0x67` consecutivos (ex.: `R100` func6 = 4 portas) é o par completo.

> O **layout byte-a-byte canônico** da porta (marcador de chegada e a posição de chegada) e a
> extração (**481 portas**, todas com chegada) estão em **[scd_gameplay.md §2.1](scd_gameplay.md)**.
> O **destino de sala** é **runtime** (provado que não é campo estático) — precisa do handler
> `0x800248e4` no [exe.md §2.6](exe.md). Não duplicar aqui.

### 3.2 Trigger de área — `sce_aot_set` (0x63, 20 bytes)  ✅
```
63 [aot:u8][sat_type:u8][floor:u8] 00 [x:s16][z:s16][w:s16][d:s16] [data: 6 bytes]
```
`sat_type` = **tipo do trigger** = enum SCE (evento, mensagem, item, flag, save, dano, …);
tabela e distribuição real nas 169 salas em [scd_gameplay.md §4.3](scd_gameplay.md) e
[exe.md §2.1](exe.md). O `data` (6 bytes) carrega os parâmetros do trigger (ex.: id do
evento). **738 gatilhos** no total. Também há `sce_aot_set_4p` (**0x64, 28 bytes**):
trigger em **4 pontos** (quadrilátero) em vez de caixa.

### 3.3 Entidade posicionada — 0x61 / 0x62 (32 bytes)  🟡
```
61 00 01 21 [flag] 00 [x:s16][z:s16] [...vários s16...] 00 00 [index:u8][type:u8] ...
```
Entidade com **posição + `type`** (0..18). **433 instâncias em 165/169 salas** — como
quase toda sala tem, é mais provável que sejam **modelos de objeto/NPC** do que inimigos
(salas seguras não teriam inimigos). O `type` está exportado para classificação futura.
A opcode dedicada de **inimigo** (`sce_em_set`) ainda **não foi confirmada** — candidatos
descartados: 0x71 (chega a 178 ocorrências numa sala → é efeito/animação, não inimigo).

> Semântica do `type_id` (é **slot de modelo**, não espécie) e como o remake resolve a
> espécie cruzando com o `R###.BIN`: [scd_gameplay.md §4.1](scd_gameplay.md) +
> [enemy_bin.md](enemy_bin.md).

## 4. Saída no JSON e totais

Os campos exportados (`doors / events / entities / items`), o schema dos
`godot/data/STAGE{n}/{sala}_scd.json` + `room_graph.json` e os **totais atuais**
(**481 portas · 738 gatilhos · 433 entidades · 14 itens** em 169 salas) estão em
[scd_gameplay.md §5–§6](scd_gameplay.md). Não duplicar aqui.

> ⚠ **Corrigido:** versões anteriores deste doc citavam "269/280 portas" e "732 triggers".
> Esses números eram de rodadas antigas (varredura só por `0x67`); a extração atual, ancorada
> no marcador de chegada, dá **481 portas** e **738 gatilhos** (ver scd_gameplay.md).

### 3.4 Item no mundo — `sce_item_aot_set` (0x68, ~32 bytes)  ✅ (round 2)
Descoberto por eng. reversa do exe (ver [exe.md](exe.md) §2.4). Mesmo cabeçalho da porta
(`68 [aot] 02 [sat] [floor] 00`) + **4 pontos** (quadrilátero) + payload:
```
68 [aot] 02 31 [floor] 00  [x0,z0,x1,z1,x2,z2,x3,z3 : s16]  [item_id:u16][amount:u16][idB:u16][fl:2]
```
`item_id` no offset **+22**, `amount` em **+24**. **14 itens reais** em 7 salas
(`tools/scd_items.py` → `rdt.script.items`). É **minoria**: a maioria dos itens visíveis
são modelos de objeto (entities 0x61/0x62) apanhados por evento.

> **Correção:** o `sat_type` dos *events* (0x63/0x64) é o **enum SCE de trigger**
> (4=MESSAGE, 5=EVENT, 6=FLAG_CHG, 8=MOVE, 9=SAVE, 10=ITEMBOX, 11=DAMAGE, 12=STATUS,
> 14=WINDOWS), **não** item_id. Ver `godot/data/sce_items.json`. As entities 0x61/0x62 com
> `byte3==0x21` (433) são modelos de objeto/NPC; os "0x61" com `byte3==0x00` eram
> **falsos positivos** (dados de destino da porta, marcador `ff 00 60 10 00`).

## 6. O que falta (próxima fase)

**Do formato (este doc):**
- ✅ **Fechamento de função = 100% (4238/4238)** com os tamanhos lidos dos handlers (§2). Não
  há opcodes ≥0x90 (espaço provado = `0x00..0x8f`). Resta apenas **nomear a semântica fina dos
  leaves menores** (rotulagem), que não afeta o fechamento nem a extração de gameplay.

**Da extração/gameplay (em [scd_gameplay.md](scd_gameplay.md) + Fase B do
[`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md)):** opcode de spawn de inimigo
(`sce_em_set`), `item_id` dos itens-modelo (evento) e **destino das portas** (runtime;
handler `0x800248e4` no exe).
