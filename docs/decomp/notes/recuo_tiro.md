# O RECUO DO TIRO — existe, e é um clipe de animação próprio

> **Veredito**: o recuo existe como **clipe dedicado**, não é procedural. O disparo roda as
> **sequências 1 / 3 / 5 do banco 2 do `.PLW`** (20 quadros cada, uma por altura de mira) — que o
> `pld2gltf.py` exporta como **`mira01` / `mira03` / `mira05`**. O recuo É esse clipe: sobe e volta
> em 20 quadros. Terminado o clipe, o motor volta ao *hold* de 1 quadro.

Conferência automática: **`python tools/exe_recuo.py`** reconfere no `SLUS_009.23`, palavra de
instrução por palavra de instrução, cada sítio deste documento e sai com código != 0 se o binário
não casar. Estava verde quando isto foi escrito.

---

## 0. Duas correções de rota

**(a) "O EXE não tem clipe de tiro; o disparo sai num quadro DENTRO da animação de mira (tabela
`0x8009cf28`, `byte2 & 0x7f` = 12 no handgun)" — ERRADO.** O disparo tem clipe próprio (§3), o
tiro sai no **quadro 0** dele (`0x80040fac  lbu 0xc9 ; bnez → return`), e os três bytes de
`0x8009cf28` são **limiares de corte**, não o quadro do disparo (§6).

**(b) `mira01` / `mira03` / `mira05` não são "rampas de 20 quadros entre as poses".** São os três
clipes de **fogo + recuo**, um por altura. O par por altura é `(fogo, hold) = (1,2) (3,4) (5,6)`.

**(c) A máquina de mira/tiro do gameplay é a ROTINA 5, não a 7.** Em `0x80039738` o `bgez $v1,
0x80039760` tem `sw $v0, 4($s0)` no **delay slot** — o write de `0x501` (ação 5 | rotina 1… ver
nota) roda nos dois ramos. A rotina 7 (`sw 0x00020701`, `0x8003975c` / `0x800397a8`) só sobrescreve
quando `$v1 < 0`, isto é, quando o **bit 31 de `player+0`** está aceso **e** `player+0xcc >= 0x15`.
O mesmo padrão em `0x80039788` / `0x800397a8`. `docs/decomp/notes/exe_combat.md §1.3` fala da
rotina 7 como "mira" — isso fica em xeque (§7).

---

## 1. A cadeia de despacho

| endereço | o que faz |
|---|---|
| `0x8003973c`, `0x80039788` | `sw ..., 4($player)` no delay slot do `bgez` → **rotina 5 é o caminho sempre tomado** |
| `0x8003975c`, `0x800397a8` | `sw 0x00020701` = rotina 7, só atrás do `bgez` (bit 31 de `player+0`) |
| `0x8003e3fc`, `0x8003e414` | rotina 5 lê `a3 = gs+0x2104` (pad) e chama `0x8009ce88[player+0x46 - 1]`; handler genérico = `0x8003eb28` |
| `0x8003eb34`, `0x8003eb38` | `lbu 6($a0)` e índice em `0x800a0000 - 0x2fd0 = 0x8009d030` — despacha por `player+6` |

São **4** tabelas de subestado, contíguas de `0x2c` em `0x2c` (= exatamente **11** ponteiros cada):

```
0x8009d004  faca                       0x8009d030  generica (handgun e cia)
0x8009d05c  variante 3                 0x8009d088  variante 4
```

Subestados da tabela genérica: `0` `0x8003eb64` levantar · `1` `0x8003ef08` hold/aim ·
`2` `0x8003f208` **FOGO** · `3` `0x8003f414` baixar arma · `4` `0x8003f520` recarga ·
`5` `0x8003f6b0` trocar alvo · `6`/`7` `0x8003fa38` · `8` `0x8003fb78` · `9` `0x8003fde8` ·
`10` `0x8003fe88`.

---

## 2. O banco animado é o **banco 2** do `.PLW` ✅

Equipar arma (`0x80043be4`) copia o diretório do `.PLW` para:

| campo do diretório | destino | banco |
|---|---|---|
| `+0x04` | `player+0xf0` | banco **0** (corpo inteiro, `armNN`) |
| `+0x08` → `0x80043d64` | `gs+0x260c` | banco **1** (pernas) |
| `+0x0c` → `0x80043d74` | `gs+0x2610` | banco **1** |
| `+0x14` → `0x80043d94` | `gs+0x2614` | banco **2** (tronco/braços) |
| `+0x18` → `0x80043da4` | `gs+0x2618` | banco **2** |

Todo o pipeline de arma anima com `gs+0x2614`/`gs+0x2618` (`0x8003f344`, `0x8003f56c`,
`0x8003ef98`, `0x8003ee10`, `0x8003fae8`) e, em paralelo, `0x80079690(gs+0x248c, gs+0x2610,
gs+0x260c, …)` = banco 1 (pernas). `0x800796ac`/`0x800796e8` indexam por `player+0x1a0`/`+0x1a1`,
que é o par (seq, quadro) do banco 1 — e **todo** `sw ..., 0xc8` do pipeline é duplicado em
`+0x1a0`, logo os dois bancos parciais tocam a MESMA seq/quadro. Isso fecha a composição
tronco+pernas e confirma o §9.6 de `plw.md`.

Medição do asset (`tools/find_anim_banks.py` em `PL00W00.PLW`): banco 2, `EDD @ 0x88f8`, `nseq = 8`,
`seq0 = 10` quadros, **`seq1/3/5 = 20`**, `seq2/4/6 = 1`, `seq7 = 32`. Casa 1:1 com o EXE.

---

## 3. O clipe de recuo, sítio por sítio ✅

**Subestado 2 (FOGO)** — `0x8003f248`..`0x8003f268`:

```
8003f248  lui   $a1, 3
8003f24c  ori   $a1, $a1, 1          ; $a1 = 0x00030001
8003f250  lui   $a0, 0x800a
8003f254  lbu   $v0, -0x32c3($a0)    ; $v0 = *(0x8009cd3d) = ALTURA de mira (0/1/2)
8003f258  addiu $v1, $zero, 1
8003f25c  sb    $v1, 7($s0)          ; player+7 = 1 (tranca "já comecei este clipe")
8003f260  sll   $v0, $v0, 1
8003f264  addu  $v0, $v0, $a1        ; 0x00030001 + altura*2
8003f268  sw    $v0, 0xc8($s0)       ; +0xc8 = seq 1|3|5 · +0xc9 = 0 (quadro) · +0xca = 3   ★
```

espelhado em `+0x1a0` em `0x8003f27c` (o banco das pernas).

**Avanço e saída** — `0x8003f344`: `jal 0x80026be8(player, gs+0x2618, gs+0x2614, 0x400)`; quando o
retorno é ≠ 0 (o clipe acabou), `0x8003f354  sh 1, 6($s0)` grava de uma vez `player+6 = 1` (volta
ao **hold**) e `player+7 = 0` (solta a tranca).

**Os outros subestados, para contraste:**

| subestado | endereço do `sw` | `+0xc8` | seq | clipe | quadros |
|---|---|---|---|---|---|
| 0 levantar | `0x8003ebbc` | `0x00070000` | 0 | `mira00` | 10 |
| 1 hold | `0x8003ef6c` | `0x00070002 + altura*2` | 2 / 4 / 6 | `mira02/04/06` | 1 |
| **2 fogo+recuo** | **`0x8003f268`** | **`0x00030001 + altura*2`** | **1 / 3 / 5** | **`mira01/03/05`** | **20** |
| 3 baixar | `0x8003f458` | `0x00070000` | 0 | `mira00` **ao contrário** | 10 |
| 4 recarga | `0x8003f554` | `0x00070007` | 7 | `mira07` | 32 |

O "ao contrário" do subestado 3 é medido: `0x8003f48c  lui $a3, 1` monta um `a3` com a metade
**ALTA** ≠ 0, e é isso que liga o playback reverso no motor (`0x80026c24`..`0x80026c4c`: índice
`= (nframes - frame)*2 - 2`). Compare com o subestado 2, que passa `a3 = 0x400` puro
(`0x8003f348  addiu $a3, $zero, 0x400`) — metade alta zero, playback normal.

`0x8003f554` também **prova** o reconhecimento visual do dono: `mira07` (32 quadros) é a
**recarga**, e não "tiro + recuo" como o port rotulava.

---

## 4. Não existe recuo procedural (prova por eliminação) ✅

* **Nenhum retrocesso de quadro.** Varredura de todos os stores em `player+0xc9` (o quadro):
  **nenhum** no intervalo `0x8003e000`..`0x80044000`. O contador só é tocado pelo motor de
  animação (`0x800271c8`..`0x800271ec`: `+0xc9 += 1`, dá a volta em 0 e **retorna 1** no fim).
* **O disparo não empurra o corpo.** Varredura de stores em `player+0xc0/0xc2/0xc4` (o vetor de
  impulso local, integrado por `0x80017df0` em `player+0x34/+0x3c` com decay 3/4 por quadro em
  `0x8003e50`..`0x8003e60`): no pipeline de arma **todas** as escritas são **zero** —
  `0x8003e5f8`, `0x8003eca0`, `0x8003f358`, `0x8003f464`, `0x8003faa4`, `0x8003fc30`,
  `0x8003fc94`, `0x8003fec8`, `0x8003ff3c`, `0x80040c58`. Impulso ≠ 0 só no **dano**
  (`0x8003d53c` = `-0x320`, `0x8003d804` = `+0x190`).
* **Nenhum handler de disparo mexe em posição ou facing.** Varredura de stores em
  `+0x34`/`+0x3c`/`+0x6e` nos 17 handlers de `0x8009ced8[w-1]` (`0x80040f34`..`0x800439f8`): só
  `($sp)`, salvamento de registrador.
* **`0x80048308` (tremor de TELA) não está no caminho de tiro da rotina 5.** Chamadores:
  `0x8003adb8`, `0x8003aed8`, `0x8003af6c` (rotina 7), `0x8003cf94`, `0x8003cfe4`, `0x80058c44`.

---

## 5. O que realmente acompanha o disparo (quadro 0 do clipe)

| endereço | efeito |
|---|---|
| `0x80040fac` | `lbu 0xc9 ; bnez → return` — **o tiro sai no quadro 0** do clipe de recuo |
| `0x80040fdc`, `0x80040ff8` | hitscan `0x80044804` + `0x80047860` |
| `0x80041000` | consome munição |
| `0x80041018` | SFX do tiro |
| `0x80041030` | `gs+0x75e8 |= 1` (flash) |
| `0x80041070`, `0x800410a0`, `0x800410c8` | três `0x8001b484` = fogacho, fumaça, estojo |
| `0x8003e230` (de `0x80041034`) | **recuo de VIBRAÇÃO do controle**, por arma |

O recuo de vibração vem da tabela **`0x8009cf90`, 6 bytes por arma** (índice `weapon-2`) e vira
`0x80038678(b0,0)`, `0x80038704(b1,b2,0)`, `0x8003879c(b5,b3,b4,b1)`; consumido em `0x80038140`/
`0x80038154` (`0x800389a0`) e escrito nos dois motores do pad em `0x80038168`/`0x8003816c`.
Handgun (`w2`) = `03 05 fa 00 00 00`. (Que `0x800c79c8` e `s3+1` sejam os dois motores do DualShock
é **declarado** — a leitura de `0x80038168`..`0x8003818c` com `0x40`/`0xff` é forte, o nome não foi
provado até o driver.)

---

## 6. Papel real dos 3 bytes de `0x8009cf28` (correção)

A tabela tem **20** entradas (w1..w20), terminando em `0x8009cf63` — em `0x8009cf64` começa outra
tabela de 1 byte por arma. Os três bytes são **limiares de quadro**:

| byte | lido em | o que faz |
|---|---|---|
| `byte0 & 0x7f` | `0x8003ee70` | levantando: se `> player+0xc9` e `pad & 0x20` → `player+6 = 1`, `0x8009cd3d = 2` |
| `byte1 & 0x7f` | `0x8003eec0` | idem com `pad & 0x10` → `0x8009cd3d = 1` |
| `byte2 & 0x7f` | `0x8003f3dc` (fogo), `0x8003e558` (faca) | se soltou a mira (`!(pad & 0x500)`) **e** quadro > byte2 → `player+6 = 1`: **é onde o recuo pode ser CORTADO** |
| **bit 7 do `byte0`** | `0x8003e454` (`srl a2,7`) | vira `a2` de `0x80019318(player, 0, bit)`, que escolhe o nó de referência (offset `564*a2 + 0x814` em `player+0x108`) e faz correção de posição pelo osso (`0x80019420`..`0x80019450`: `player+0x34/+0x3c -= delta`). **Nada a ver com recuo.** |

Handgun (w2): `b0 = 0x86` (6, bit7=1), `b1 = 0x08` (8), `b2 = 0x0c` (**12** de 20 quadros). Ou seja
o "12" que o port usava como "o quadro do tiro" é na verdade **o quadro a partir do qual soltar o
botão corta o recuo**.

Tabela vizinha `0x8009cf64 + (weapon-1)`, 1 byte: `& 0x7f` = taxa de giro durante a mira
(`0x8003f1bc` `-=`, `0x8003f1e8` `+=`); **bit 7** = pula o cálculo do ponto do cano (`0x8003f30c`,
`0x8003f3a0`) — aceso na faca (`0xb0`).

---

## 7. Bônus: os órfãos `arm13..arm17` do banco 0 têm dono

Os subestados **8 / 9 / 10** (`0x8003fb78`, `0x8003fde8`, `0x8003fe88` — idênticos nas 4 tabelas de
arma) animam com `player+0xf0`/`+0xf4` = **banco 0** do PLW via `0x80027940`, escrevendo as
sequências **13, 14, 15, 16, 17** (`0x8003fbe8`, `0x8003fe1c`, `0x8003fe74`, `0x8003febc`,
`0x8003ff30`, `0x8003fc2c`, `0x8003fc80`), com munição (`0x8003fd1c`), recarga (`0x8003fd60`) e SFX
(`0x8003fd90`). São os clipes `arm13..arm17` = a variante de **mira/tiro/recarga de corpo inteiro**.
Entrada provada a partir da rotina 7: `0x8003af10` (`sw 0x80501, 4` → rotina 5 subestado **8**,
quando `player+0xc8 ∈ {19,20}`) e `0x8003aee8` (`sw 0x60501` → subestado 6).

Continuam **sem dono identificado**: `arm03`, `arm04`, `arm05`, `arm08`, `arm10`, `arm11`, `arm12`
(e `arm06`/`arm07` já são o subir/descer da rotina 9 — ver `menu_bau.md §3.4`).

---

## 8. NÃO PROVADO (explícito)

* **Quem acende o bit 31 de `player+0`**, o único gate de entrada na rotina 7. Todos os 18 sítios
  de `sw 0x20701`/`0x701` estão atrás de um `bgez`; a varredura de `lui 0x8000` + `or`/`and` não
  achou nenhum *setter* de `player+0`, só quem **limpa** (`0x8003f0e0`). Portanto **não está
  provado que a rotina 7 é alcançável** no NTSC-U.
* **Consequência**: a reconciliação de `exe_combat.md §1.3` está em xeque. `0x80038b30`/
  `0x80038b48` mostram que `player+0xe8`/`+0xec` recebem o EDD/EMR do **`PL00.PLD`** (base
  `0x801d5c00`), e é esse par que o dispatcher passa à rotina 7 — se ela rodar, as seqs 19/20 são
  as do PLD (as que mediram root Z ±5648), não poses de mira do PLW. E o conjunto de comportamentos
  da rotina 7 (anim 13→14/15/16/17, promoção 19/20 com facing ±0x400, tremor de tela, saída para a
  rotina 5 subestado 6/8) **sugere esquiva/dodge** em vez de mira — isso é **hipótese**, não prova.
* O de-para `0x8009cd3d ∈ {0,1,2}` → altura (média / alta / baixa) é **declarado**: o valor vem dos
  bits de pad `0x4`/`0x1` em `0x8003f028`/`0x8003f04c`; a correspondência com "alta"/"baixa" vem do
  casamento com as alturas de punho já medidas em `animacoes_player.md`, não do binário.
* Papel exato de `player+0xca` (o byte 2 do word gravado em `+0xc8`): é lido em `0x80027adc`,
  `0x8003faf0` e `0x8003e43c` e multiplica o argumento de deslocamento; o clipe de fogo usa **3** e
  os outros usam **7**. Semântica **não determinada**.

---

## 9. O que ligar no `port/actors/player.gd` (não é meu arquivo)

O port hoje tem `var recuo := 0` como contador de 8..10 quadros **sem clipe**
(`player.gd:137, 435, 484, 522`). O certo, com os números acima:

1. **Subestado, não contador.** `player+6` é a máquina: `0` levantar → `1` hold → `2` fogo →
   volta a `1`. O `recuo` deixa de ser um contador de "trava do gatilho" e passa a ser
   "o subestado 2 está rodando".
2. **No disparo** (hoje `_tiro()` em `player.gd:501`): em vez de `recuo = 10`, entrar no subestado
   2 e tocar o clipe **`mira01`** (altura média), **`mira03`** (alta) ou **`mira05`** (baixa),
   pelo mesmo `mira_tier` que já escolhe `mira02`/`mira04`/`mira06` no hold. 20 quadros a 30 Hz.
3. **Efeitos no quadro 0 do clipe** (não no meio dele): hitscan, munição, SFX, flash
   (`gs+0x75e8 |= 1`) e os três efeitos ESP (fogacho, fumaça, estojo).
4. **Fim do clipe** → voltar ao hold do MESMO tier (`mira02/04/06`), zerando a tranca.
5. **Corte antecipado**: se o jogador soltar a mira e o quadro corrente já passou de
   `byte2 & 0x7f` da arma (handgun = 12), cortar e ir para o hold — é o `0x8003f3dc`.
6. **Baixar a arma** = `mira00` **em reverso**, não um clipe novo.
7. **Recarga** = `mira07` (32 quadros), subestado 4 — o port hoje não tem estado de recarga.
8. **Vibração**: `0x8009cf90[weapon-2]`, 6 bytes; handgun = `03 05 fa 00 00 00`. É o único "recuo"
   que sai do personagem para o jogador além do clipe.
9. Rótulos a corrigir nos testes que não são meus: `port/dev/tests/test_anim_mira.gd:107` e
   `port/dev/tests/test_combate.gd:58` ainda chamam `mira07` de "TIRO/recuo" — é a **recarga**;
   e `port/dev/shot_mira_overlay.gd:35` tem a mesma legenda.
