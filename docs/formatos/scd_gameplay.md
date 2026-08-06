# SCD — Lógica de gameplay por sala (RE3 PS1, NTSC-U)

> **STATUS** (fonte: [`../decomp/progress.json`](../decomp/progress.json) → unidades `scd`, `door_dest`, `sce_ids`)
> - **Formato:** catálogo de gameplay extraído do bytecode SCD (portas/gatilhos/itens/entidades + grafo de salas)
> - **Extensão/origem:** seção SCD do RDT das 169 salas
> - **Ferramenta:** [`tools/scd_gameplay.py`](../../tools/scd_gameplay.py), [`scd_doors.py`](../../tools/scd_doors.py), [`scd_items.py`](../../tools/scd_items.py) → `godot/data/STAGE{n}/{sala}_scd.json` + `room_graph.json`
> - **Decompilado:** **90%** SCD · **85%** IDs SCE (itens nomeados) · **50%** destino de porta
> - **Feito:** 481 portas (todas com chegada), 738 gatilhos, 433 entidades, 14 itens (0x68) posicionados; `room_graph.json`; **grafo: 61/481 arestas resolvidas** (14 recíprocas + 47 inferidas); **193 IDs de item nomeados**.
> - **Falta:** **sala-destino** das 420 portas restantes (é **runtime** — provado; precisa do handler `0x800248e4` no exe) e **espécie do inimigo** (`sce_em_set`, em aberto); `item_id` dos itens-objeto; `facing`/`state`. Fase B do [`../decomp/PLANO_ACAO.md`](../decomp/PLANO_ACAO.md).
> - **Correções deste round:** porta = **par `0x67`(22B) + `0x7f`(40B)** (não "1 opcode de 62B"); itens **`0x2A`=First Aid Box, `0x20`=Spray, `0x0A`=Rocket Launcher** (charset decodificado); interpretador do SCD = **`0x8009e0f8`** (o `0x8007688c` é a VM de IA de entidade).
>
> **Papel deste doc = EXTRAÇÃO/GAMEPLAY.** Para o **formato do bytecode** (cabeçalho de
> script, tamanhos de opcode) ver [SCD.md](SCD.md). Contêiner em [ARD.md](ARD.md); RE do
> executável em [exe.md](exe.md); nomes de item/inimigo em [../referencias/evilresource.md](../referencias/evilresource.md).

> O **SCD** é o bytecode de eventos de cada sala, dentro do RDT (bloco 8 do `.ARD`,
> `offset_table[16]`). É onde o RE3 posiciona **portas, gatilhos de área, itens,
> inimigos/modelos e eventos** — não há tabela estática. Esta doc é o **catálogo de
> gameplay**: tabela de opcodes (com evidência do executável `SLUS_009.23`), tipos de
> item/inimigo e o formato dos `godot/data/STAGE{n}/{sala}_scd.json` + `room_graph.json`.
>
> Fonte da extração: [`tools/scd_gameplay.py`](../../tools/scd_gameplay.py). Ver também
> [SCD.md](SCD.md) (estrutura do script) e [exe.md](exe.md) (reversa do executável).

Status geral: **posicionamento (portas/gatilhos/itens/entidades) extraído das 169 salas;
posição de CHEGADA das portas 100%; grafo de salas parcial (61/481 por casamento espacial);
sala-DESTINO e espécie do inimigo são resolvidos em RUNTIME (não são campos crus — PROVADO)
— ver seções marcadas 🟡.**

---

## 1. Como o SCD é executado (evidência do EXE)

O RDT tem uma tabela de 22 offsets em `rdt+0x08`; `offset_table[16]` = início do script.
O script começa com uma **tabela de ponteiros de função** (u16 `tbl_size` + N offsets); as
funções são contíguas e terminam em `evt_end` (0x01). A "main" costuma ser uma cadeia de
`gosub` chamando as demais. (Confirmado em SCD.md.)

**Interpretador.** ✅ **CORREÇÃO (round VM):** o interpretador do **bytecode do SCD de sala**
é a **jump-table `0x8009e0f8`** (256 entradas u32, copiada p/ o scratchpad `0x1f800000` no
boot; loop `0x80052ba4`, dispatch `0x80052c48`, PC em `obj+0x1c`; init de thread `0x80052474`).
Cada handler lê seus operandos e **avança o PC pelo seu tamanho** (`VM_SIZES` em
`scd_decode.py`; 97,1% das funções fecham). **Não** confundir com:
- **`0x8007688c`** = **VM de IA de entidade/inimigo** (o que este doc antes chamava de "o
  interpretador do SCD" — corrigido);
- **`0x8009e0bc`/`0x80050aac`** = **VM de evento/AOT per-frame** (consome os AOTs criados pelo
  script e dispara a troca de sala via `gs+0x2154`/flag `0x800c7960`);
- `0x80090xxx` = `vsprintf` da libc (não é VM).

Ver [SCD.md §2](SCD.md), [exe.md — Interpretador SCD](exe.md) e `../decomp/notes/scd_opcodes.md`.

**Handlers dos opcodes de posicionamento** (jump-table `0x8009e0f8`): `0x63`→`0x80055c34`
(`sce_aot_set`, 20B), `0x64`→`0x80055c94` (aot_4p, 28B), `0x67`→`0x800574f4` (`door_aot_set`,
22B, registra o AOT em `gs+0x2158[slot]`), `0x68`→`0x800576c4` (`item_aot_set`, 30B),
`0x7f`→`0x80056510` (destino/chegada da porta, 40B), `0x06`→`0x800512fc` (flag check/set).

---

## 2. Tabela de opcodes de posicionamento (gameplay)

Todos localizados por **assinatura de bytes fixos** (robusto a opcodes de fluxo não
mapeados) e validados por **faixa de coordenada** (mesma escala das câmeras). Coordenadas
em ponto-fixo com sinal (s16).

| op | nome | tam | evidência | conf. |
|---|---|---|---|---|
| **0x67** | `door_aot_set` (porta — gatilho) | **22 B** | handler `0x800574f4`; forma **par** com `0x7f` (22+40=62) | **ALTA** |
| **0x7f** | destino/chegada da porta | **40 B** | handler `0x80056510`; carrega `to_x/y/z/facing` | **ALTA** |
| **0x63** | `sce_aot_set` (gatilho AABB) | 20 B | handler `0x80055c34` | **ALTA** |
| **0x64** | `sce_aot_set_4p` (gatilho quadrilátero) | 28 B | handler `0x80055c94`, 4 pontos | ALTA |
| **0x68** | `sce_item_aot_set` (item no chão) | 30 B | handler `0x800576c4`; `item_id@+22`, `amount@+24` | MÉDIA |
| **0x61 / 0x62** | entidade posicionada (modelo/NPC/inimigo) | **32 / 40 B** | `type@+24`, `pos@+6/+8` | ALTA (é modelo) / 🟡 (é inimigo?) |

> **Correção (round VM):** os tamanhos agora vêm dos **handlers da VM `0x8009e0f8`**
> (`VM_SIZES`), não de restrição empírica. A "porta de 62B" = **par `0x67`(22) + `0x7f`(40)**;
> `0x62`=**40** (era 32). Tabela completa em [SCD.md §2](SCD.md). O desassemblador SCD
> (if/while/switch) está quase completo (97,1% das funções fecham); a extração de gameplay
> abaixo continua ancorada em **assinatura** (robusta), independente disso.

### 2.1 Struct da PORTA — par `0x67` (22B, gatilho) + `0x7f` (40B, destino/chegada)

Do alinhamento das portas do `R100` (par de 62 B), coluna a coluna. O byte `+22 = 0x7f` é o
**início do 2º opcode** (não uma "constante de tail"):
```
--- opcode 0x67 (door_aot_set, 22 B): gatilho ---
+0   u8   opcode = 0x67
+1   u8   aot_id
+2   u8   = 0x02            (constante; marcador SCE_DOOR)
+3   u8   sat = 0x31        (máscara de partição/piso)
+4   u8   floor
+5   u8   = 0x00
+6   s16  x     +8 s16 z    caixa de gatilho (canto)
+10  s16  w     +12 s16 d   tamanho da caixa
+14..+21          bloco de destino (pequeno; seletor `byte@+9` do 0x7f é SEMPRE 0 → §3)
+20/+23  = seq             índice sequencial da porta na sala
--- opcode 0x7f (destino/chegada, 40 B) começa em +22 ---
+22  u8   = 0x7f            OPCODE (handler 0x80056510)
+24..+32  zeros (reservado)
+33  u8   = 0xff  +34 var  +35 0x60 +36 0x10 +37 0x00   marcador de chegada
+38  s16  to_x  +40 s16 to_y  +42 s16 to_z  +44 s16 to_facing   ✅ POSIÇÃO DE CHEGADA
+46  s16  ?  +48 s16 ?        (offset fino/anim)
```
**Achado-chave de extração:** o **head** (opcode+AABB+destino) é de **tamanho variável**
entre salas (nem toda porta é opcode 0x67 com head de 35 B), mas o **tail é fixo**:
`0x7f` está sempre em `marcador-13` (**100 % das 481 portas**). Por isso a extração
robusta **ancora no marcador de chegada** `ff [x] 60 10 00`:
- `m` = posição do byte `0x60`; exige `byte[m-13]==0x7f` (anti-falso-positivo);
- **chegada** = `s16` em `m+3, m+5, m+7, m+9` → `(to_x, to_y, to_z, to_facing)` — **sempre confiável**;
- **AABB** do gatilho = `m-29..m-23` quando o head é o do 0x67 (**~50 %**); senão `null`.

Resultado: **481 portas em 118 salas** (2,85/sala), **todas com chegada**; 240 com AABB.
A varredura antiga só-por-0x67 pegava 254 (76 salas ficavam sem porta).

---

## 3. 🟡 Destino da porta (`to_stage` / `to_room`) — RUNTIME (parcial: 61/481)

**PROVADO que o destino NÃO é campo estático do SCD.** O opcode `0x7f` (handler
`0x80056510`) lê `byte@+9` como seletor de banco/sala, mas nos **653** opcodes `0x7f` reais
esse byte é **SEMPRE 0** (banco default). Busca **exaustiva** de reciprocidade sobre todos os
offsets/encodings satura em **~15 %**. Logo o (stage,room)-destino é **resolvido em RUNTIME**
(indireção por door-index + estado do motor), não copiado do bytecode. O caminho definitivo é
o **handler de porta `0x800248e4`** + tabela de fileids `0x8009dfd0[stage][room]` + loader
`0x800493ec` (ver [exe.md §2.6](exe.md) e `../decomp/notes/door_handler.md`).

**O que já se resolveu (casamento espacial recíproco, `room_graph_build.py`):** a **chegada**
de A→B (100% decodificada) deve cair sobre o **gatilho** da porta de volta B→A. Isso resolve:
- **14 portas** `recip` (par mútuo same-stage — recíproco por construção, conf 0,80–0,95);
- **47 portas** `inferido` (chegada casa 1 único gatilho same-stage, conf 0,55);
- **total 61/481 (12,7 %)**; **420 abertas** (frames de coordenada compartilhados por área
  tornam a posição ambígua; muitas portas têm só um lado com AABB).

**Salas GÊMEAS entre stages** (`_meta.twin_families`, 43 famílias por fingerprint de colisão):
regra da comunidade confirmada **`R6xx = R1xx`, `R7xx = R2xx`** (Mercenaries reusa Downtown/
Uptown); há gêmeas intra-jogo (`R102=R11D`, `R300=R310`…). Por isso só casamos **same-stage**
(match cross-stage é quase sempre contaminação de gêmeo).

**Disponível para o remake:** posição de **chegada + facing** em 100 % das portas
(`room_graph.json → arrival`); os campos `to_stage/to_room/to_room_id` + `dest_source`
(`recip`/`inferido`/`null`) + `dest_conf` já saem preenchidos onde resolvido.

> Validação R100: 6 portas, todas com chegada plausível (coords na faixa da sala), 1 save
> point (SCE_SAVE), 0 itens auto-pega — coerente com uma sala-hub/segura do início do RE3.
> Sem uma tabela de nomes de sala no EXE, a identidade exata de cada `Rxyz` não é afirmável
> byte-a-byte (confiança MÉDIA na plausibilidade; ALTA nas coordenadas).

---

## 4. Inimigos e itens — o que o SCD dá (e o que não dá)

### 4.1 🟡 Inimigos: `type_id` é SLOT DE MODELO, não espécie
As entidades `0x61/0x62` (433 no total, em 165/169 salas) carregam `type_id` (0..27 +
flags 0xF0/0xF8). **Não é o id da espécie:**
- `R101` tem **3 zumbis** (macho, confirmado por render em `enemy_bin.md`) mas os três são
  `type_id=0`; e `type_id=0` é ubíquo (**157×**, inclusive em salas seguras).
- A **espécie do inimigo é definida pelo modelo embutido no `R###.BIN` da sala** (ver
  [enemy_bin.md](enemy_bin.md): "zumbis, cães, aranhas, Nemesis são carregados por sala").

**Como o remake resolve a espécie:** posição/slot vêm do SCD (`enemies[]`); a **espécie/
modelo** vem do inimigo carregado por sala (no PS1, `R###.BIN`; modelos limpos exportados do
**EMD do GOG**, **69 `.glb`** em `godot/assets/ENEMY/` — ver [enemy_bin.md](enemy_bin.md)).
Confiança: posição ALTA; "é inimigo vs NPC/objeto" e espécie por type_id **BAIXA** (o campo é
slot, não espécie). `facing`/`state` ainda não isolados.

> **Nomes (roster):** o RE3 tem **15 tipos** de inimigo (zombie, zombie dog, crow, drain
> deimos, brain sucker, grave digger, sliding worm, giant/small spider, hunter β/γ, Nicholai,
> Nemesis 1ª/2ª/3ª forma) — ver [../referencias/evilresource.md](../referencias/evilresource.md).
> O **mapeamento `type_id`/`EM##` → nome-canônico é "a confirmar"** (não é público). O
> **`sce_em_set`** (opcode que grava a espécie a partir do `type_id`) ainda **não foi
> decodificado** — pendência no exe. **IA:** o zumbi é o **tipo 23** do dispatch T64
> (`0x80097bd4`); ver [exe.md §3](exe.md) e `../decomp/notes/exe_ai.md`.

### 4.2 Itens no chão (`0x68`) — MINORIA
Só **14 itens reais** em 7 salas via `0x68` (zonas de item/munição auto-pega). A **maioria
dos itens visíveis** são modelos-objeto apanhados por **evento de script** — o `item_id`
desses vive na lógica do evento, ainda não extraído. `item_id@+22`, `amount@+24`.

> **Nomes de item — RESOLVIDO (charset decodificado):** o texto do RE3 usa fonte própria
> (byte→glifo), agora decodificada (`tools/re3_text.py` → `godot/data/re3_items.json`): **193
> IDs**, 168 com nome, 115 com exame (EN do EXE `@0x8C6E5`/`@0x8A124` + PT do mod GOG).
> **Correções ao roster antigo:** `0x2A` = **First Aid Box** (NÃO "Spray"); `0x20` =
> **First Aid Spray**; `0x0A` = **Rocket Launcher**; `0x15` = **Hand Gun Bullets** (×30 casa
> com o `amount` do SCD — **confirmado**); `0x01`=Knife, `0x04`=Shotgun (Benelli M3S),
> `0x21`=Green Herb, `0x41`=Lighter Oil, `0x42`=Lighter, `0x99`=Fax H.Q., `0x9b`=Photo A,
> `0xa0`=Clock Tower Postcard. Detalhes/âncoras em `../decomp/notes/messages.md`. Roster
> completo (65 itens/41 armas) em [../referencias/evilresource.md](../referencias/evilresource.md).

### 4.3 Gatilhos (`0x63/0x64`) — enum SCE (byte +2)
| sce | nome | | sce | nome | | sce | nome |
|---|---|---|---|---|---|---|---|
| 1 | SCE_DOOR* | | 6 | SCE_FLAG_CHG | | 10 | SCE_ITEMBOX |
| 2 | SCE_ITEM* | | 7 | SCE_WATER | | 11 | SCE_DAMAGE |
| 4 | SCE_MESSAGE | | 8 | SCE_MOVE | | 12 | SCE_STATUS |
| 5 | SCE_EVENT | | 9 | SCE_SAVE | | 14 | SCE_WINDOWS |

\* DOOR/ITEM usam opcodes dedicados (0x67 / 0x68), não aparecem como sce de 0x63.
Distribuição real nas 169 salas em [exe.md §2.1](exe.md). **738 gatilhos** no total.

---

## 5. Formato dos arquivos gerados

### `godot/data/STAGE{n}/{sala}_scd.json`
```jsonc
{
  "_meta": { "sala","stage","room","aviso_destino","aviso_inimigos" },
  "doors": [{
     "aot", "opcode", "seq",
     "box": {"x","z","w","d"} | null,      // gatilho na sala de ORIGEM (best-effort)
     "aot_quad": [[x,z]x4] | null,
     "to_stage","to_room","to_room_id",     // 🟡 runtime; preenchido em 61/481 (recip/inferido)
     "dest_source": "recip|inferido|null", "dest_conf": 0.0,
     "to_x","to_y","to_z","to_facing",      // ✅ posicao de CHEGADA (sempre)
     "needs_key": null,
     "dest_raw": [bytes] | null             // candidatos de destino (bloco +14..+21 do 0x67)
  }],
  "enemies": [{ "type_id","x","z","facing":null,"state":null,"opcode","index","flag" }],
  "items":   [{ "type_id","amount","x","z","aot","quad","type_id_alt" }],
  "triggers":[{ "aot","sce","event","kind":"box|quad","quad","box?","data" }],
  "flags":   [ ...triggers sce==6 (FLAG_CHG)... ],
  "messages":[ ...triggers sce==4 (MESSAGE)... ]
}
```

### `godot/data/room_graph.json`
```jsonc
{
  "_meta": { "nos":169, "arestas":481, "arestas_com_chegada":481,
             "resolvidas":61, "twin_families":43, "destino_status": "runtime (parcial)" },
  "nodes": [{ "id":"R100","stage","room","area?","n_doors","n_enemies","n_items","n_triggers" }],
  "edges": [{ "src":"R100","aot","box","seq",
              "to_stage","to_room","to_room_id",        // 🟡 61/481 (recip/inferido)
              "dest_source","dest_conf","dest_reason",
              "arrival": {"x","y","z","facing"},        // ✅
              "dest_raw": [...] | null }]
}
```

---

## 6. Totais e o que falta

- **169 salas** · **481 portas** (todas com chegada; 240 com AABB; **61 com destino**) ·
  **433 entidades** · **14 itens (0x68)** · **738 gatilhos**. 51 salas sem porta =
  dead-ends/cutscene/duplicatas (ex.: R104=R11F). 43 famílias de **salas gêmeas** (R6xx=R1xx).
- **Falta (próxima fase):** (1) **sala-destino** das 420 portas restantes — via **trace
  runtime** (handler `0x800248e4` + tabela `0x8009dfd0`; é runtime, não campo estático) ou
  ancorando o mapa da comunidade nos `Rxyz` (por `hd_map.json`); (2) **espécie do inimigo** —
  `sce_em_set` no exe + cruzar com os `.glb` do GOG ([enemy_bin.md](enemy_bin.md)); (3)
  `item_id` dos itens-objeto (evento); (4) `facing`/`state` do inimigo; (5) nomear os leaves
  menores do VM p/ flags de progresso/puzzles.
