class_name Ecg
extends RefCounted
## ECG (os batimentos) do painel de condição da tela de status — RE3 PS1 NTSC-U `SLUS_009.23`.
##
## ── ONDE ELE ESTÁ NO EXE (provado) ──
## O ECG **existe** e é desenhado pela própria task de status, em `0x8006c484`, chamada no fim
## de `0x8006b66c` (a rotina que posiciona todas as primitivas da tela) por `jal` em `0x8006c33c`.
## Ele NÃO usa sprite nem tabela de tiles: são **32 primitivas GPU `LINE_F2` verticais**,
## uma por coluna de pixel, montadas em `0x8006e84c` (chamada de `0x8006b648`):
##
##     8006e84c  li  $t2, 0x20        # 32 colunas
##     8006e850  lui/ori $a1, 0x801af0e8   # buffer das primitivas
##     8006e85c  li  $t1, 3           # len = 3   (LINE_F2 = tag + rgb/code + xy0 + xy1)
##     8006e860  li  $t0, 0x40        # code = 0x40 = LINE_F2
##     8006e864  li  $a2, 0x80        # rgb inicial (128,128,128)
##     8006e880  ori $v0, $v0, 2      # code = 0x42 -> LINE_F2 **SEMI-TRANSPARENTE**
##
## São 32 colunas × 2 (buffer duplo) × 16 B = 1024 B, exatamente `0x801af0e8..0x801af4e8` —
## e `0x801af4e8` é onde começa o buffer de TILE (`0x8006b368`), o que fecha o tamanho.
##
## As 4 "evidências" de que a onda não estava nesta task caem todas:
##  1. `SetLineF2` **existe** (`0x8008f6f0`, e `SetLineF3` em `0x8008f710`) — só que ninguém a
##     chama: as primitivas são montadas INLINE (`li 0x40` + `sb` no offset +7), como aqui.
##  2. a **tabela de forma de onda existe**: ponteiros em `0x800a0174 + cond*4`, dados em
##     `0x800a0cbc`/`0x800a0d5c`/`0x800a0dfc`/`0x800a0e9c`/`0x800a0f3c` (160 B cada).
##  3. as listras horizontais estão batidas no bitmap **de propósito**: no `STMAIN0U.TIM` o
##     interior do gráfico é **índice 0 = TRANSPARENTE** (linhas y=84,85,87,88,… do atlas), e a
##     grade é 1 px verde-escuro a cada 3 px (índices 0xBF..0xC4 = (0,56,0)..(0,16,0)). O buraco
##     transparente é justamente onde estas linhas entram.
##  4. o pack HD não tem onda porque **não há textura de onda** para o pack substituir.
##
## ── GEOMETRIA (provada em `0x8006c484`) ──
##     s6 = base[0].x + 0x4b   (`0x8006c518`)   -> x = base.x + 75 + k
##     s4 = base[0].y + 0x25   (`0x8006c51c`)   -> y = base.y + 37 + onda[k].y
## `base[0]` é `ctx+0xe4`, zerado no init (`0x8006db34`/`0x8006db38`) → a tela é absoluta 320×240.
## `k = fase + i`, com o guarda `if (k < 0 || k >= 0x4a) continue` (`0x8006c550`/`0x8006c558`).
## Logo x ∈ [75, 148] e a onda vive em y ∈ [41, 64]. O interior transparente do painel B1
## (`(0,64,96,56,72,20)`) medido no atlas é x ∈ [76,148], y ∈ [39,66] — o gráfico inteiro.
##
## Cada coluna é UMA linha vertical: `x0 = x1` (`0x8006c5c4` e `0x8006c5d8` gravam o mesmo valor
## em +8 e +0xc), `y0 = 37 + onda[2k]` (+0xa) e `y1 = y0 + onda[2k+1]` (+0xe). Ou seja a tabela é
## um par **(deslocamento, altura)** por coluna, e altura 0 = 1 pixel.
##
## ── COR: rastro que apaga (provado em `0x8006c560`..`0x8006c5b0`) ──
##     r = base.r - delta.r * (n - 1 - i)      (idem g, b; `sb`, ou seja u8 com wrap)
## `base`/`delta` saem de `0x800a0150 + cond*6` (3 B de cor + 3 B de decaimento). i = n-1 é a
## CABEÇA (cor cheia) e i = 0 a cauda (quase preta) → varredura de osciloscópio com rastro de
## 32 px. As primitivas são `code 0x42` (semi-transparente) e a tpage da faixa é `0x9b`
## (`0x8006aec8`), cujo `abr = (0x9b>>5)&3 = 0` → **50% fundo + 50% frente**.
##
## ── CADÊNCIA (provada em `0x8006e268`, o tick da task) ──
##     if (ctx+0x18 & 0x00800000) fase += 3;          # `0x8006e310`, SEM wrap
##     else { fase += 1; if (fase >= 0x51) fase = -32; }   # `0x8006e31c`..`0x8006e338`
## E o tick inteiro é pulado quando `*(u16*)(ctx+0x10) == 0x205` (`0x8006e288`) → o ECG congela.
## No init `fase = 0` (`0x8006db78`). Ciclo normal: fase de **-32 a 80 = 113 quadros**.
## A task do menu roda a **60 Hz** (`0x800d442c = 1` no `menu_init`; ver
## `docs/decomp/notes/menu_pc_sys.md` §8) e o port roda a 30 Hz — por isso `QUADROS_POR_TICK = 2`:
## cada tick de 30 Hz executa DOIS quadros do original, o que mantém o período em ≈1,88 s.
##
## ── O "flash" da cura (`ctx+0x18 & 0x800000`) ──
## Usar item de cura faz `fase = -32`, `ctx+0x12 = 3` e `flags |= 0x800000` (`0x80067910`).
## Com o bit ligado o desenho troca: **n = 28** colunas (`0x8006c4e8`) e cada linha vai de
## `base.y+39` a `base.y+66` (`0x8006c5ec`/`0x8006c5f8`) — barras de altura CHEIA varrendo o
## painel. A fase anda +3 por quadro e o estado 3 do "usar item" (`0x80067934`) encerra quando
## `fase >= 0x51`: limpa o bit e volta `fase = -32`.
##
## ── ENGATE (já ligado em `menu_status.gd`) ──
##     var _ecg := Ecg.new()                     # membro de MenuStatus
##     func avancar():  ...;  _ecg.avancar()     # 1 tick de 30 Hz
##     func _draw():    ...;  _ecg.desenhar(self, cnd)      # DEPOIS do laço `for r in MOLDURA`
##     # ao usar item de cura:  _ecg.flash()     # (ainda não chamado por `_usar`)
##
## ── DESENHO EM RESOLUÇÃO DE TELA (conserto de 2026-08-08) ──
## O relato do dono do repo era "as linhas do ECG estão em SD, um blocão". Estava: eu emitia
## 32 `draw_rect` de **1 px de largura no espaço 320×240**, e como o nó do menu tem `scale = 4`
## cada um saía como um bloco de 4×4 px na tela, o que transformava toda subida/descida em
## escada. A onda, porém, é VETORIAL: a tabela é uma poligonal (ver `valores()`), então agora ela
## é desenhada com `draw_line` antialiasado entre os vértices — coordenadas FLOAT no mesmo espaço
## 320×240 (a geometria medida não muda) e rasterização depois da escala, isto é em 1280×960.
## As LISTRAS de fundo do gráfico já vinham em HD e continuam: elas são batidas no bitmap do
## painel B1, e o `menu_status.gd` desenha B1 do bloco `MENU/status/hd/chrome_9b.webp` (4× da
## metade direita do `STMAIN0U`). Conferido no arquivo: 10 listras verdes opacas de 2 px, com
## passo de 12 px, em `v = 332..442` do bloco — que é exatamente `GRADE_N = 10` e
## `GRADE_PASSO = 3` do SD multiplicados por 4. Não há par HD "das listras" para casar: elas não
## são asset separado.
##
## Nada aqui é chute: todo número tem endereço. O que é escolha do port está marcado
## "declarado" no comentário da constante (`ESPESSURA_SD` e a regra de `valores()`).

# ── Tabelas do EXE, copiadas byte a byte ────────────────────────────────────────────────────────

## `0x800a0150 + cond*6`: [r, g, b, dr, dg, db]. Índice = a condição de `0x8006e598`
## (0 FINE · 1 CAUTION · 2 CAUTION2 · 3 DANGER · 4 POISON · 5 VIRUS).
const COR := [
	[32, 255, 32, 1, 8, 1],             ## 0 FINE     — verde
	[255, 255, 32, 8, 8, 1],            ## 1 CAUTION  — amarelo
	[255, 128, 32, 8, 4, 1],            ## 2 CAUTION2 — laranja
	[255, 32, 32, 8, 1, 1],             ## 3 DANGER   — vermelho
	[255, 32, 255, 8, 1, 8],            ## 4 POISON   — magenta
	[255, 32, 255, 8, 1, 8],            ## 5 VIRUS    — magenta (mesma linha do POISON)
]

## `0x800a0174 + cond*4` → ponteiro. Os 6 ponteiros apontam para 5 tabelas: POISON e VIRUS
## compartilham `0x800a0f3c`.
const ONDA_ENDERECO := [0x800A0CBC, 0x800A0D5C, 0x800A0DFC, 0x800A0E9C, 0x800A0F3C, 0x800A0F3C]
const ONDA_POR_CONDICAO := [0, 1, 2, 3, 4, 4]

## As 5 tabelas, 160 B cada = 80 pares (deslocamento_y, altura). Só os índices 0..73 são
## alcançáveis (guarda `k < 0x4a`); o resto do bloco vai junto para o dado ficar idêntico ao ROM.
const ONDA_HEX := [
	"0f000f000f000f000f000f000f000f000f000f000f000f000f000e000d000c000c000d020f03120214001004080805030400050308070f04130518031b001902150410050e020d000e02100313001300120010020e020d000c000d000e010f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f00",
	"0f000f000f000f000f000f000f000f000f000f000f000f000e000d000c000c000e000d020f03120214001004080806020500060208050d020f00100414021600150010050f000e000e000d000d000e000f000f000f000e000e000e000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f00",
	"0f000f000f000f000f000f000f000f000f000f000f000f001000100011001100110010000f000e000e000e000f000f000f000e000b030a0009000a040d031003130014001300120010020e020d000c000c000c000d000e000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f00",
	"0f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000e000e000d000d000e000f000f000f0010001102110011000e030a0409000a020c030f0010001000100010000f000e000d000d000e000e000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f00",
	"0f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000e010d010c010c010d020f03120214011004080805030401050308070f04130518021a0119010f0a0e010f011002120111010a0709010a020c0410011101120112011201110110010f010f010f010f010f010c030a0209010a0610031301130111020f000f000f000f000f000f000f000f000f000f000f000f000f000f000f00",
]

# ── Geometria e cadência ────────────────────────────────────────────────────────────────────────

const N_COLUNAS := 32                   ## `0x8006c4e4`: fp = 0x20
const N_COLUNAS_FLASH := 28             ## `0x8006c4e8`: fp = 0x1c quando `flags & 0x800000`
const X_ORIGEM := 75                    ## `0x8006c518`: base[0].x + 0x4b
const Y_ORIGEM := 37                    ## `0x8006c51c`: base[0].y + 0x25
const K_LIMITE := 0x4A                  ## `0x8006c554`: guarda `k < 0x4a` (74 colunas)
const FLASH_Y0 := 39                    ## `0x8006c5ec`: base.y + 0x25 + 2
const FLASH_Y1 := 66                    ## `0x8006c5f8`: base.y + 0x25 + 0x1d
const FASE_INICIO := -32                ## `0x8006e334`: -0x20
const FASE_FIM := 0x51                  ## `0x8006e32c`: wrap quando `fase >= 0x51`
const PASSO := 1                        ## `0x8006e31c`
const PASSO_FLASH := 3                  ## `0x8006e310`
const ALFA_SEMITRANS := 0.5             ## code 0x42 + tpage 0x9b (abr = 0) → 50% fundo/50% frente

## ── ESPESSURA DA LINHA (o conserto do "blocão") ──
## O primitivo do PS1 é `LINE_F2` com `x0 == x1`: **1 pixel de 320×240** de largura. O port
## desenha nesse mesmo espaço com `scale = 4`, então 1 px virava um quadrado de 4×4 na tela —
## foi isso que o dono do repo viu como blocos. A onda, porém, é VETORIAL (a tabela é uma
## poligonal: ver `valores()`), então dá para desenhá-la como linha de verdade e deixar o
## rasterizador da tela resolver em 1280×960.
## `1.0` = exatamente a espessura do original (1 px de 320×240 = 4 px de tela), que é a
## proporção fiel. É o único número deste arquivo que é ESCOLHA e não medida — está aqui para
## poder afinar (0.5 = 2 px de tela, traço mais fino/HD).
const ESPESSURA_SD := 1.0

## O menu do PS1 roda a 60 Hz e o port a 30 Hz (`menu_pc_sys.md` §8): 2 quadros do original por
## tick do port. Ponha 1 aqui para ver o ECG na metade da velocidade.
const QUADROS_POR_TICK := 2

## Retângulo do interior do gráfico, MEDIDO no `STMAIN0U.TIM` (não é do código): a região de
## índice 0 do painel B1 é u∈[4,76] v∈[19,46] locais → tela x∈[76,148] y∈[39,66], com a grade em
## 1 px verde-escuro a cada 3 px de v (v = 19,22,…,46). Serve só para o teste e para diagnóstico.
const AREA := Rect2i(76, 39, 73, 28)
const GRADE_PASSO := 3
const GRADE_N := 10

# ── Estado ──────────────────────────────────────────────────────────────────────────────────────

var fase := 0                            ## `ctx+0x32` (s16); init em 0 (`0x8006db78`)
var em_flash := false                    ## `ctx+0x18 & 0x00800000`

static var _ondas: Array[PackedByteArray] = []
static var _valores: Array[PackedInt32Array] = []


static func onda(indice: int) -> PackedByteArray:
	## A tabela de `ONDA_ENDERECO[...]` como bytes. `indice` é 0..4 (o de `ONDA_POR_CONDICAO`).
	if _ondas.is_empty():
		for h: String in ONDA_HEX:
			_ondas.append(h.hex_decode())
	return _ondas[clampi(indice, 0, _ondas.size() - 1)]


static func onda_da_condicao(cond: int) -> PackedByteArray:
	return onda(int(ONDA_POR_CONDICAO[clampi(cond, 0, ONDA_POR_CONDICAO.size() - 1)]))


static func valores(indice: int) -> PackedInt32Array:
	## A tabela como **poligonal**: um valor de `y` (deslocamento, sem o `Y_ORIGEM`) por coluna.
	##
	## ── POR QUE A TABELA É UMA POLIGONAL (medido no dado) ──
	## Cada coluna é um par `(y0, h)` e o EXE desenha o segmento VERTICAL `[y0, y0+h]`
	## (`0x8006c5c4`..`0x8006c5d8`). Lendo as 5 tabelas, os spans de colunas vizinhas **se
	## encostam**: em `0x800a0cbc`, k=20 é `(0x14,0)` = 20..20, k=21 é `(0x10,4)` = 16..20,
	## k=22 é `(0x08,8)` = 8..16, k=23 é `(0x05,3)` = 5..8 — 20, 16, 8, 5 é o valor da onda, e
	## cada `h` é o |Δ| até o vizinho. Ou seja o span vertical de uma coluna é a PROJEÇÃO do
	## segmento que liga o valor da coluna anterior ao da coluna atual: a "linha grossa" do PS1 é
	## o traço diagonal colapsado num pixel de largura.
	##
	## Regra usada para recuperar o valor (DECLARADA — é reconstrução, não campo do dado):
	##     a    = clamp(v[k-1], y0, y0+h)
	##     v[k] = y0  se  |y0 - a| > |y0+h - a|,  senão  y0+h
	## isto é, o extremo do span mais LONGE de onde a onda estava (com o valor anterior trazido
	## para dentro do span antes de comparar). Semente `v[-1] = y0[0]` — as 5 tabelas começam com
	## 12 a 19 colunas de `(0x0f, 0)` (a linha de base 15), então a semente não muda nada.
	##
	## ── O QUANTO ISSO É EXATO (medido, `test_ecg.gd`) ──
	## Reprojetando a poligonal de volta em spans, nas 370 colunas alcançáveis (5 tabelas × 74):
	## **298 batem byte a byte**, 69 erram **1 px** e 3 erram 2 px, sempre no extremo distante.
	## A diferença é do DADO, não da regra: em `0x800a0cbc` k=13 o span é `(0x0e,0)` = 14..14 vindo
	## de 15 — o autor escreveu `h = 0` numa descida de 1 px, e não `h = 1`; no k=21 da mesma
	## tabela, uma descida de 4 px traz `h = 4`, ou seja incluindo o ponto de partida. As duas
	## convenções convivem na mesma tabela, então NÃO existe regra exata para as 370.
	## Os LIMITES não se movem: o `y` da poligonal fica em [4, 27] = tela [41, 64], exatamente o
	## mesmo intervalo dos spans, logo a onda continua inteira dentro do buraco do painel.
	if _valores.is_empty():
		for i in ONDA_HEX.size():
			var w := onda(i)
			var n := w.size() / 2
			var v := PackedInt32Array()
			v.resize(n)
			var ant := int(w[0])
			for k in n:
				var y0 := int(w[k * 2])
				var y1 := y0 + int(w[k * 2 + 1])
				var a := clampi(ant, y0, y1)
				var atual := y0 if absi(y0 - a) > absi(y1 - a) else y1
				v[k] = atual
				ant = atual
			_valores.append(v)
	return _valores[clampi(indice, 0, _valores.size() - 1)]


static func valores_da_condicao(cond: int) -> PackedInt32Array:
	return valores(int(ONDA_POR_CONDICAO[clampi(cond, 0, ONDA_POR_CONDICAO.size() - 1)]))


func reiniciar() -> void:
	## `0x8006db34`..`0x8006db78`: base[0] = (0,0), `fase = 0`, `flags = 0`.
	fase = 0
	em_flash = false


func flash() -> void:
	## `0x80067910`: usar item de cura → `fase = -32`, `flags |= 0x800000`.
	fase = FASE_INICIO
	em_flash = true


func avancar() -> void:
	## Um tick de 30 Hz do port = `QUADROS_POR_TICK` quadros do original.
	for _i in QUADROS_POR_TICK:
		_quadro()


func _quadro() -> void:
	## Um quadro do original. A ordem é a da task (`0x8006dfdc`): primeiro o handler do estado
	## (que é quem encerra o flash, `0x80067934`), depois o tick (`0x8006e268`).
	if em_flash and fase >= FASE_FIM:
		em_flash = false                 ## `0x8006796c`: flags &= ~0x800000
		fase = FASE_INICIO               ## `0x8006797c`: fase = -32
	if em_flash:
		fase += PASSO_FLASH              ## `0x8006e310`: SEM wrap (quem encerra é o handler)
		return
	fase += PASSO
	if fase >= FASE_FIM:
		fase = FASE_INICIO


func n_colunas() -> int:
	return N_COLUNAS_FLASH if em_flash else N_COLUNAS


func segmentos(cond: int, origem := Vector2i.ZERO) -> Array:
	## O laço de `0x8006c53c`..`0x8006c69c` sem GPU: devolve os segmentos visíveis como
	## `[{ x, y0, y1, cor: Color8 }, …]`, do rastro (i=0) para a cabeça (i=n-1).
	## `origem` é `base[0]` (`ctx+0xe4`), que no jogo é (0,0).
	var n := n_colunas()
	var c: Array = COR[clampi(cond, 0, COR.size() - 1)]
	var w := onda_da_condicao(cond)
	var fora: Array = []
	for i in n:
		var k := fase + i
		if k < 0 or k >= K_LIMITE:
			continue                      ## `0x8006c550` / `0x8006c558`
		var y0: int
		var y1: int
		if em_flash:
			y0 = origem.y + FLASH_Y0
			y1 = origem.y + FLASH_Y1
		else:
			y0 = origem.y + Y_ORIGEM + int(w[k * 2])
			y1 = y0 + int(w[k * 2 + 1])
		var f := n - 1 - i                ## `0x8006c564`: (n - i) - 1
		fora.append({
			"x": origem.x + X_ORIGEM + k,
			"y0": y0,
			"y1": y1,
			## `sb` de `base - delta*f` → u8 com wrap. Com as 6 linhas de `0x800a0150` o produto
			## nunca passa da base, então o wrap não dispara; fica exato de propósito.
			"cor": Color8(int(c[0] - c[3] * f) & 0xFF,
				int(c[1] - c[4] * f) & 0xFF,
				int(c[2] - c[5] * f) & 0xFF),
		})
	return fora


func pontos(cond: int, origem := Vector2i.ZERO) -> Array:
	## A onda como POLIGONAL: `[{ p: Vector2, cor: Color8 }, …]` da cauda (i=0) para a cabeça
	## (i = n-1), com um vértice por coluna visível. Mesma janela e mesmo guarda de `segmentos`
	## (`k = fase + i`, `0 <= k < 0x4a` de `0x8006c550`/`0x8006c558`), mesma origem (75,37) e mesmo
	## rastro de cor de `0x8006c560`. O que muda é a REPRESENTAÇÃO: vértice em vez de span, para
	## desenhar linha de verdade na resolução da tela (ver `ESPESSURA_SD`).
	##
	## Não vale no flash (`ctx+0x18 & 0x800000`): lá o EXE desenha barras de altura CHEIA
	## (`0x8006c5ec`/`0x8006c5f8`), que não são onda nenhuma — `desenhar` continua usando
	## `segmentos` nesse caso.
	var n := n_colunas()
	var c: Array = COR[clampi(cond, 0, COR.size() - 1)]
	var v := valores_da_condicao(cond)
	var fora: Array = []
	for i in n:
		var k := fase + i
		if k < 0 or k >= K_LIMITE:
			continue
		var f := n - 1 - i                    ## `0x8006c564`: (n - i) - 1
		fora.append({
			"p": Vector2(float(origem.x + X_ORIGEM + k), float(origem.y + Y_ORIGEM + v[k])),
			"cor": Color8(int(c[0] - c[3] * f) & 0xFF,
				int(c[1] - c[4] * f) & 0xFF,
				int(c[2] - c[5] * f) & 0xFF),
		})
	return fora


func desenhar(alvo: CanvasItem, cond: int, alfa := 1.0, origem := Vector2i.ZERO) -> void:
	## Desenha no espaço 320×240 do `alvo` (o mesmo em que `menu_status.gd` desenha).
	## Chamar DEPOIS do painel B1 — no PS1 o painel entra com `ot = 3` (`0x8006b99c`) e o ECG com
	## `ot = 1` (`0x8006c654`), e a Ordering Table desenha o índice menor por cima.
	##
	## ── RESOLUÇÃO DE TELA ──
	## Antes eram 32 `draw_rect` de 1 px de largura no espaço 320×240; com a escala 4 do nó, cada
	## um saía como um bloco de 4 px e a onda ficava em escada. Agora são segmentos de reta entre
	## os vértices da poligonal (`pontos`), com `antialiased = true`: as coordenadas continuam em
	## 320×240 (a geometria MEDIDA não muda), mas são FLOAT e a rasterização acontece depois da
	## escala, ou seja em 1280×960. A espessura vem de `ESPESSURA_SD`.
	if alfa <= 0.0:
		return
	if em_flash:
		## FLASH da cura: barras de altura cheia, 1 px de largura — é retângulo no original
		## (`0x8006c5ec`/`0x8006c5f8`) e continua retângulo aqui.
		for s: Dictionary in segmentos(cond, origem):
			var cf: Color = s["cor"]
			cf.a = ALFA_SEMITRANS * alfa
			var fy0: int = s["y0"]
			var fy1: int = s["y1"]
			alvo.draw_rect(Rect2(float(s["x"]), float(mini(fy0, fy1)),
				1.0, float(absi(fy1 - fy0) + 1)), cf)
		return
	var ps := pontos(cond, origem)
	if ps.size() < 2:
		## uma coluna só (a onda entrando ou saindo da janela): sem segmento, marca o pixel — é o
		## que o `LINE_F2` de altura 0 do original desenha.
		if ps.size() == 1:
			var c1: Color = ps[0]["cor"]
			c1.a = ALFA_SEMITRANS * alfa
			var p1: Vector2 = ps[0]["p"]
			alvo.draw_rect(Rect2(p1.x, p1.y, 1.0, 1.0), c1)
		return
	for i in range(1, ps.size()):
		## A COR é a da coluna de destino (índice `i`), como no original: cada primitivo do PS1
		## leva a cor do seu `i`, e o segmento i é a projeção da coluna i.
		var cor: Color = ps[i]["cor"]
		cor.a = ALFA_SEMITRANS * alfa
		alvo.draw_line(ps[i - 1]["p"], ps[i]["p"], cor, ESPESSURA_SD, true)
