# ECG do painel de condição (tela de status) — RE3 PS1 NTSC-U `SLUS_009.23`

> Onde a onda de batimento vive no binário, como ela é desenhada, e por que o port a desenhava
> em "blocão".
>
> Implementação: [`port/present/ecg.gd`](../../../port/present/ecg.gd) ·
> teste: `port/dev/tests/test_ecg.gd` (211 asserções) ·
> prova visual: `godot --rendering-driver opengl3 --path port --script res://dev/shot_ecg.gd`
> (salva `port/dev/_shot_ecg.png`).
> Layout da tela: [`menu_inventario.md`](menu_inventario.md) · task e estados:
> [`menu_pc_sys.md`](menu_pc_sys.md).

---

## 1. Onde está (PROVADO)

O ECG **não** é sprite nem tile: são **32 primitivas GPU `LINE_F2` verticais**, uma por coluna de
pixel, montadas em `0x8006e84c` (chamada de `0x8006b648`) e posicionadas em `0x8006c484`
(chamada de `0x8006c33c`, no fim de `0x8006b66c`).

```
8006e84c  li  $t2, 0x20              # 32 colunas
8006e850  lui/ori $a1, 0x801af0e8    # buffer das primitivas
8006e85c  li  $t1, 3                 # len = 3 (tag + rgb/code + xy0 + xy1)
8006e860  li  $t0, 0x40              # code 0x40 = LINE_F2
8006e864  li  $a2, 0x80              # rgb inicial
8006e880  ori $v0, $v0, 2            # code 0x42 = LINE_F2 SEMI-TRANSPARENTE
```

32 colunas × 2 (buffer duplo) × 16 B = 1024 B = `0x801af0e8..0x801af4e8`, e `0x801af4e8` é onde
começa o buffer de TILE (`0x8006b368`) — o tamanho fecha.

| Coisa | Endereço | Valor |
|---|---|---|
| nº de colunas | `0x8006c4e4` | `0x20` = 32 |
| nº de colunas no flash | `0x8006c4e8` | `0x1c` = 28 |
| x da coluna | `0x8006c518` | `base[0].x + 0x4b` → **75 + k** |
| y da coluna | `0x8006c51c` | `base[0].y + 0x25` → **37 + onda[2k]** |
| altura | `0x8006c5d8`/`+0xe` | `y1 = y0 + onda[2k+1]` |
| guarda da janela | `0x8006c550`/`0x8006c558` | `if (k < 0 \|\| k >= 0x4a) continue` |
| cor com rastro | `0x8006c560`..`0x8006c5b0` | `r = base.r − delta.r*(n−1−i)` (idem g,b, `sb`) |
| base/delta de cor | `0x800a0150 + cond*6` | 3 B de cor + 3 B de decaimento |
| ponteiro da onda | `0x800a0174 + cond*4` | 6 ponteiros → 5 tabelas de 160 B |
| tabelas | `0x800a0cbc` `0x800a0d5c` `0x800a0dfc` `0x800a0e9c` `0x800a0f3c` | POISON e VIRUS compartilham a última |
| cadência | `0x8006e310` / `0x8006e31c`..`0x8006e338` | `fase += 3` no flash · senão `+1` com wrap `>= 0x51` → `-32` |
| congela | `0x8006e288` | tick pulado quando `*(u16*)(ctx+0x10) == 0x205` |
| flash da cura | `0x80067910` / `0x8006c5ec` / `0x8006c5f8` | `fase = -32`, `flags \|= 0x800000`; barras de `base.y+39` a `base.y+66` |

`base[0]` é `ctx+0xe4`, zerado no init (`0x8006db34`), então a tela é absoluta 320×240:
x ∈ [75, 148] e a onda vive em y ∈ [41, 64]. O interior transparente do painel **B1**
(`(0,64,96,56,72,20)`) medido no `STMAIN0U.TIM` é x ∈ [76,148], y ∈ [39,66] — o gráfico inteiro.

Ciclo normal: fase de **−32 a 80 = 113 quadros**; a task do menu roda a 60 Hz
(`0x800d442c = 1`, `menu_pc_sys.md` §8) e o port a 30 Hz, daí `QUADROS_POR_TICK = 2` (≈1,88 s).

---

## 2. A tabela é uma POLIGONAL (achado desta rodada)

Cada coluna é um par `(y0, h)` e o EXE desenha o span **vertical** `[y0, y0+h]`. Lendo as 5
tabelas, os spans de colunas vizinhas **se encostam**: em `0x800a0cbc`,

```
k=20 (0x14,0) = 20..20     k=21 (0x10,4) = 16..20     k=22 (0x08,8) = 8..16     k=23 (0x05,3) = 5..8
```

isto é 20, 16, 8, 5 — o **valor** da onda — e cada `h` é o |Δ| até o vizinho. Ou seja: o span
vertical de uma coluna é a **projeção** do segmento que liga o valor da coluna anterior ao da
atual. A "linha grossa" do PS1 é o traço diagonal **colapsado num pixel de largura**, que é o que
uma GPU sem antialiasing pode fazer.

Regra usada para recuperar o valor (**DECLARADA** — é reconstrução, não campo do dado):

```
a    = clamp(v[k-1], y0, y0+h)
v[k] = y0   se |y0 − a| > |y0+h − a|,   senão   y0+h        # o extremo mais LONGE
v[-1] = y0[0]                                               # semente: a linha de base 15
```

**O quanto é exato (medido, travado em `test_ecg.gd`):** reprojetando a poligonal de volta em
spans, nas **370** colunas alcançáveis (5 tabelas × 74), **298 batem byte a byte**, 69 erram
**1 px** e 3 erram 2 px, sempre no extremo distante. A diferença é do **dado**, não da regra: em
`0x800a0cbc` o k=13 é `(0x0e,0)` = 14..14 vindo de 15 (descida de 1 px com `h = 0`, excluindo o
ponto de partida), enquanto o k=21 é `(0x10,4)` = 16..20 (descida de 4 px com `h = 4`, incluindo).
As duas convenções convivem na mesma tabela, então **não existe regra exata para as 370** — é
dado feito à mão. Os limites não se movem: o `y` da poligonal fica em [4, 27] = tela [41, 64],
exatamente o intervalo dos spans, logo a onda continua inteira dentro do buraco do painel.

---

## 3. O defeito relatado: "as linhas do ECG estão em SD, um blocão"

**Causa:** o port emitia 32 `draw_rect` de **1 px de largura no espaço 320×240**, transcrevendo o
`LINE_F2` ao pé da letra. Como o nó do menu tem `scale = 4` (1280/320), cada retângulo saía como
um bloco de 4×4 px e toda subida/descida virava escada de 4 px.

**Conserto:** desenhar a POLIGONAL da §2 com `draw_line(..., antialiased = true)` entre os
vértices. As coordenadas continuam no espaço 320×240 — **a geometria medida não muda** — mas são
FLOAT, e a rasterização acontece **depois** da escala, ou seja em 1280×960. Espessura em
`Ecg.ESPESSURA_SD = 1.0` (= 1 px de 320×240 = 4 px de tela, a proporção fiel; é o único número do
arquivo que é escolha e não medida).

O **flash da cura** continua com retângulo: lá o EXE desenha barras de altura CHEIA
(`0x8006c5ec`/`0x8006c5f8`), que não são onda nenhuma.

### 3.1 As LISTRAS de fundo já vinham em HD

As listras horizontais do gráfico **não são asset separado**: são batidas no bitmap do painel B1,
com o interior do gráfico em índice 0 = TRANSPARENTE e a grade em 1 px verde-escuro a cada 3 px
(índices `0xBF..0xC4` = (0,56,0)..(0,16,0) do `STMAIN0U.TIM`). Como `menu_status.gd` desenha B1 do
bloco **`MENU/status/hd/chrome_9b.webp`** (512×1024 = 4× da metade direita do `STMAIN0U`, a região
da tpage `0x9B`), elas já saem em HD.

Conferido no próprio arquivo (`PIL`, coluna x=60 do bloco): **10 faixas verdes opacas de 2 px**,
com passo de **12 px**, em `v = 332/344/356/368/380/392/404/416/428/440` — exatamente
`GRADE_N = 10` e `GRADE_PASSO = 3` do SD multiplicados por 4. Não há par HD "das listras" para
procurar no `hd_ui_map.json`; a única coisa que faltava em resolução de tela era a onda.

---

## 4. Resíduo honesto

| Aspecto | Status |
|---|---|
| Geometria, cores, cadência, flash | **PROVADO** (endereços na §1) |
| Tabela = poligonal | **PROVADO** no dado; a regra de reconstrução do vértice é **DECLARADA**, com o erro medido (298/370 exatas) |
| `ESPESSURA_SD` | **ESCOLHA** do port (1 px de 320×240) |
| `Ecg.flash()` ligado ao uso de item de cura | **NÃO LIGADO** — `MenuStatus._usar` cura o HP mas não chama `flash()` |
| Onda no CONGELAMENTO (`ctx+0x10 == 0x205`) | não reproduzido: o port não tem esse estado |
