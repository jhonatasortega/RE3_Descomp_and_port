# Texto do RE3 — charset, tabelas de item e mensagens

> Ferramenta: [`tools/re3_text.py`](../../../tools/re3_text.py)
> Saídas: [`godot/data/re3_items.json`](../../../godot/data/re3_items.json),
> [`godot/data/re3_messages.json`](../../../godot/data/re3_messages.json)

O texto do RE3 **não é ASCII cru**: usa uma **fonte própria** com tabela de caracteres
indexada. Cada string é uma sequência de bytes onde cada byte é um índice de glifo.

## 1. Charset (byte → caractere)  — PROVADO

Fonte da tabela: `mod_BH3_Portuguese/encoding.xml` (GOG). É a tabela-base clássica da
Capcom (RE2/RE3), com os acentos PT/UE remapeados na faixa alta:

| faixa | conteúdo |
|------|----------|
| `0x00` | espaço |
| `0x0C`–`0x15` | dígitos `0`–`9` |
| `0x1D`–`0x36` | `A`–`Z` |
| `0x3D`–`0x56` | `a`–`z` |
| `0x57`–`0xA0` | acentuados (`Ã ã Õ õ … Á á É é …`) + símbolos |

Prova (byte → string), verificada contra o binário PS1 US `SLUS_009.23`:

```
0x27 0x2A 0x25 0x22 0x21           = "KNIFE"
0x23 0x4E 0x41 0x41 0x4A           = "Green"   (achado em 0x8C86C)
0x44 0x41 0x4E 0x3E                = "herb"    (achado em 0x8AD42)
item_id 0x15 → "H. Gun Bullets"    (casa com sce_item_names.json: 0x15 = Hand Gun Bullets ×30)
```

### Códigos de controle (no fluxo de texto do EXE)
| byte | significado |
|-----:|-------------|
| `0xFC` | nova linha (dentro da mesma caixa) |
| `0xFD` | nova página / limpar caixa (`{clear}`) |
| `0xFE` | fim de string (separador na tabela de exames) |
| `0xF7` | fim de string (separador na tabela de nomes) |
| `0xEA XX` | glifo especial; a sequência `EA48 EA49 EA4A EA4B EA48` = `S.T.A.R.S.` (full-width); `EA36` = `&` |

No **mod PT** (XML) os controles aparecem como tags textuais: `{clear 0}`, `{color 1}…{color 0}`,
`{branch 0}`, `{scroll 2}`, `{s}`, `\n`.

## 2. Tabelas de ITEM

Duas fontes independentes, **cruzadas** e concordantes:

### PT — `mod_BH3_Portuguese/xml/`
- `items_simple.xml` = **nomes**, array indexado: `índice = item_id` (índice 0 = vazio).
- `system.xml` = **exames**, array com 17 mensagens de sistema no início: `item_id = índice − 16`.

### EN — `extracted/ntsc-u/SLUS_009.23` (PS1 NTSC-U)
- **Nomes** @ `0x8C6E5`: entradas separadas por `0xF7`, começando em `Knife` (= item `0x01`).
- **Exames** @ `0x8A124`: entradas separadas por `0xFE`; `item_id = índice + 1`.

Âncoras que travam o alinhamento (EN e PT batem byte-a-byte):
`0x01` faca · `0x15` munição de pistola · `0x20` first aid spray · `0x21` erva verde · `0x2A` first aid box.

### Cobertura
- **193 IDs** (`0x01`–`0xC1`).
- **168** com **nome real** EN + PT (os outros 25 são `BOTU` = slots não usados, presentes no
  próprio binário retail).
- **TODOS os itens jogáveis** (`0x01`–`0x84`) com **exame real** EN + PT. Documentos, mapas e
  key-items alternativos (`0x85`–`0xC1`) têm **só nome**, sem exame de inventário em **nenhuma**
  das duas fontes.
  **PROVA (bytes) de que não falta nada:** a tabela de exames EN `@0x8A124` **termina em `0x84`** —
  os índices `0x85`/`0x86` são strings **vazias** (`0xFE 0xFE`) e o `0x87` é lixo/fim de tabela.
  O texto desses itens vive nos **RDT** (leitor de documento), não numa tabela de exame de item.

### 3ª fonte de confirmação de `item_id` — descritor de inventário do EXE `@0x800a0514`
Além de nomes EN × exames EN × PT, o `item_id` é confirmado pela **tabela de descritores** que a
lógica de inventário do EXE lê (`0x8006d0a8`/`0x80069cb8`), **4 bytes/id** em `0x800a0514`:
- `b0` = **classe**: `0x01` arma · `0x02` munição · `0x03` recuperação · `0x04` key-item ·
  `0x05` chave · `0x06` ferramenta · `0x07` documento · `0x08` mapa · `0x00` não-usado. As faixas
  batem **1:1** com os itens conhecidos.
- `b1` = **stack máx / capacidade**: `0x02` pistola=**15**, `0x04` escopeta=**7**, `0x05`/`0x06`
  magnum/lança-granadas=6, `0x2a` F.Aid Box=**3**, munição=250. Casa com os exames **e** com o
  `amount` do SCD (`0x04`→7, `0x15`→30).
- Gravado em `re3_items.json` → `by_id[*].inv_cat` / `inv_max` (todos os 193).

### Cross-check com o SCD (opcode `0x68` = `sce_item_aot_set`)
8 `item_id` observados no SCD das salas (campo +22) — **todos** batem com `by_id`:
`0x21` Green Herb, `0x41` Lighter Oil, `0x42` Lighter, `0x04` Shotgun (amount **7** = capacidade),
`0x15` H.Gun Bullets (amount **30**), `0x99` Fax H.Q., `0x9b` Photo A, `0xa0` Clock Tower Postcard.
(Obs.: o opcode `0x7d` = `sce_em_set` é de **inimigo**, não de item; item usa `0x68`.)

### Loadout inicial — ✅ FECHADO (rotina de novo-jogo decodificada byte-a-byte)
A rotina de **NOVO JOGO** que popula o inventário inicial é **`0x8006d0d8`** (não `0x80069c3c`,
que é só o *primitivo* de conceder-1-item / janela de obter). Ela **zera** o array
`0x800d2134` (gs+0x79fc; MAIN 10 slots @+0, BOX 64 @+0x28) e **copia um TEMPLATE ESTÁTICO**
de `0x800a018c+`. **PROVA (disasm):**
- loop de escrita `0x8006d304+`: `slot.b0=tmpl[0]=id`, `slot.b1=tmpl[1]=qtd`,
  `slot.hword+2=tmpl[2..3]=flags16(LE)`. **Entrada = 4 bytes `{id, qtd, flags16}`**, lista
  terminada em **`FFFFFFFF`** (`lb; beq -1`).
- **equip inicial** `0x800d225d` (gs+0x7b25) = id do **1º item** do template (`0x8006d5a8`).
- **modo `s5`** via jump-table `@0x80010f9c` (5 entradas). `s5<2` = jogo principal da Jill e
  **anexa armas-bônus de pós-zeramento** gated em `gs+0x77f8` (bit6→`0x0a` R.Launcher, bit7→`0x0b`
  Gatling, bit8→`0x0f` A.Rifle, qtd `0xff`=infinito) — prova de que é o caminho retail da Jill.
- `s5=2` = **The Mercenaries** (char por `gs+0x24d6`: 8=Carlos, 9=Mikhail, 0xA=Nicholai).

Templates extraídos (bytes) em `re3_items.json → newgame_loadout_templates`; a Jill principal
(s5=0) em `default_loadout_jill`:
- **s5=0 (Jill/HARD) @0x800a018c** `030f0100 82fa0000 83010000 84010000 ff…` =
  Hand Gun(0x03)×15 [equip] + Reloading Tool×250 + Game Inst. A/B (0x83/0x84 só na 1ª jogada,
  gate flag `0x800d1f3e`).
- **s5=1 (Jill/EASY) @0x800a01b4** = Assault Rifle(0x0f)×100 + Reloading Tool + Game Inst. A/B +
  F.Aid Box×3; **BOX @0x800a0298** (magnum/escopeta/pistola/munições/Ink Ribbon/Faca).
- **s5=2 mercenários** (RETAIL-verificado, byte-idêntico ao `SELECT.BIN @0x36e8`):
  Nicholai `020f0100 01010000 22010000 20010000×3` = SIGPRO+Faca+Blue Herb+F.Aid Spray×3;
  Mikhail `04070100 05060100 0a080100 17150d00 16120d00 29010000`; Carlos `0f641600 0d0f0100 …`.

> **HONESTIDADE:** os templates de modo-Jill (s5=0/1/3/4) trazem itens de dev/debug
> (Reloading Tool×250, Game Inst. A/B, Blue Gem, arsenal completo). O clássico **"Faca + Pistola"**
> **NÃO existe como tabela estática discreta** no SLUS — varredura do EXE inteiro acha a **Faca
> (0x01)** só nos templates de **NICHOLAI** e do **item-box**. A Faca é a arma corpo-a-corpo
> permanente; o equip inicial é a pistola (1º item). **Nada inventado.**
- `default_loadout` (protótipo `inventory.gd`) mantido só p/ compat de UI.

### Achados / correções para `sce_item_names.json`
- **`0x2A` NÃO é "First Aid Spray"** — é o **First Aid Box** (exame: "guarda até 3 sprays").
  O **First Aid Spray** real é **`0x20`** (exame: "restaura completamente a vitalidade").
- `0x0A` = **Rocket Launcher** (exame "M66 Rocket Launcher"; nome EN "R. Launcher").
  O `items_simple.xml` PT rotula `0x0A` como "Lança granadas" — provável erro do mod;
  a autoridade (exame + nome EN + sce) é Rocket Launcher.
- `0x02`/`0x03`: quirk dos dados originais — `0x02` tem **nome** "Merc's Handgun/Pistola de
  mercenário" mas **exame** "SIGPRO SP2009"; `0x03` tem nome "Hand Gun/Pistola" mas exame
  "M92F Custom … made for S.T.A.R.S.". Fiel ao jogo.
- IDs observados no SCD (opcode `0x68`) agora nomeados: `0x41`=Lighter Oil, `0x42`=Lighter,
  `0x99`=Fax from the H.Q., `0x9B`=Photo A, `0xA0`=Clock Tower Postcard, `0x21`=Green Herb.

## 3. MENSAGENS (`re3_messages.json`)

- `system_pt` — 17 mensagens de sistema (pegar/combinar/recarregar…), de `system.xml`.
- `prompt_pt` — mensagens de porta/ação (trancada, "quer subir?", etc.), de `prompt.xml`.
- `rooms_pt` — mensagens por sala (`R100`…`R###`), de `xml/rdt/R###.xml`. A **ordem do array
  de cada sala = índice de mensagem** referenciado pelo SCD daquela sala.

**PT completo** (do mod). **EN das mensagens de sala/porta = TODO**: está nos RDT do jogo base
(não numa tabela linear do EXE como os itens); extrair numa próxima passada. **Não inventar.**

> Nota: `godot/data/*_scd.json` e `room_graph.json` são de outro agente — este pipeline só
> **lê** os RDT do mod e grava em `re3_messages.json`, sem tocar naqueles.
