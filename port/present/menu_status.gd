class_name MenuStatus
extends Node2D
## Tela de STATUS/INVENTÁRIO do RE3 — recomp, não pastiche.
##
## Tudo aqui vem do binário. Fonte: `docs/decomp/notes/menu_inventario.md` (+ a §15, que é a
## auditoria adversarial que remediu do zero e corrigiu 8 erros), `tools/status_layout.py`
## (tabelas de retângulo lidas do EXE) e `tools/status_assets.py` (imagens com a paleta certa).
##
## ── Onde a tela vive ──
## NÃO é overlay de `BIN/*.BIN`: é uma **task do EXE** (entrada `0x8006dfdc`, contexto
## `0x800e01c0`). Ela monta primitivas do GPU a partir de tabelas de retângulo de 12 bytes:
## **tabela A** em `0x8009f2ec` (42 registros) e **tabela B** em `0x8009f890` (165), com o layout
##
##     +0 u16 u · +2 u16 v · +4 u16 w · +6 u16 h · +8 u16 dx · +10 u16 dy
##
## em **pixels de tela 320×240** (provado: o maior `dx+w` das duas tabelas é 312 e o maior
## `dy+h` é 224 — incompatível com 640×480). O port desenha nesse espaço e escala por 4 para o
## quadro de 1280×960.
##
## ── Imagens e PALETA (o detalhe que erra a tela toda) ──
## `ETC/STMAIN0U.TIM` (8bpp, 256×272, 4 CLUTs) tem a moldura e os retratos, mas em linhas de CLUT
## diferentes: **paleta 0 = moldura** (cinza/azul) e **paleta 2 = retratos** (JILL/CARLOS em
## `v 192..247`). `ETC/STMOJIU.TIM` (4bpp, 256×72, 9 CLUTs) tem as palavras e os dígitos.
## Os ícones 40×30 da grade vêm de `ETC/ITEMA.SLD`, comprimidos com o LZ de `0x80010000`,
## indexados por **item_id** (tabela de u32 em `0x8009f678`, 134 itens) e coloridos com a
## **CLUT (0,485)** = linha 1 do STMAIN0U depois do upload. As 134 entradas descomprimem para
## exatamente 1200 B = 40×30 — é o critério de aceite do descompressor.
##
## ── Geometria (medida, com os registros de onde saiu) ──
## Grade **2 colunas × 5 linhas**, célula **40×30**, origem **(224,66)**, passo +40/+30:
## B27 = `(0,72,80,120,224,66)` desenha as 4 primeiras linhas de uma vez, B28/B29 são os slots
## 8 e 9 em `y=186`. O cursor da grade é B146 = `(120,0,40,30,224,66)` e anda pela mesma célula
## (`0x800668a4`: `x = col*40`, `y = row*30`).
##
## Piscada do cursor (`0x8006e290`..`0x8006e2f0`): um contador sobe e desce de **2 em 2** com
## clamp em `0x3f`, e a cor do primitivo é `contador - 0x80` → **128..191**, ciclo de ~64 quadros.
## Aqui isso entra como modulação de brilho do sprite, que é o efeito visível.
##
## Condição (`0x8006e598`): VIRUS se `flags & 0x100`, Poison se `& 0x200`, senão por HP:
## `>= 101` FINE · `>= 41` CAUTION · `>= 21` CAUTION2 · resto DANGER. A palavra é um retângulo
## do STMOJIU (`0x800a0004 + cond*12`), todos em `dy=25`.
##
## ── O que aqui é ESCOLHA do port, declarada ──
## • A paleta do STMOJIU (palavras/dígitos): o índice real sai de `ctx+0xd3+n` e não foi
##   decodificado. Uso a **0**, que é a que casa com a captura do jogo (letra clara).
## • O ECG animado da condição e o painel de EQUIP com a porcentagem de munição ainda não
##   entraram — a moldura deles é desenhada, o conteúdo não. Está na lista, não fingido.
## • Ordem de desenho: um `Node2D` acima de tudo; no PS1 é a Ordering Table da própria task.

const ESCALA := 4                       ## 1280/320 — o quadro do port é 4× a tela do PS1
const CELULA := Vector2i(40, 30)
const GRADE_ORIGEM := Vector2i(224, 66)
const GRADE_COLUNAS := 2
const GRADE_LINHAS := 5
const QTD_OFFSET := Vector2i(2, 18)     ## deslocamento do dígito dentro da célula (medido)
const DIGITO_W := 8
const DIGITO_H := 11
const DIGITO_V := 19                    ## `v0 = 0x13` em `0x8006c940`
const DIGITO_U0 := 4                    ## `u0 = 4 + d*8`
const ANIM_QUADROS := 6                 ## abertura/fechamento (`0x800741a0`), 6 quadros
const CURSOR_PASSO := 2                 ## `ctx+0x22` ±2
const CURSOR_TETO := 0x3F               ## clamp

## ── TPAGE: por que a moldura precisa de +128 no `u` ──
## O `u` do registro é relativo à **página de textura**, e a página muda por faixa de `ot`
## (`0x8006aeb8`..`0x8006afcc`): `ot` 0-7 → tpage `0x9B`, 8-15 → `0x9A`, 16-23 → `0x3A`,
## 24-31 → `0x97`. O `STMAIN0U` é carregado na VRAM em `(640,256)` **em words**, e uma tpage
## avança 64 words: `0x9A` → word 640, `0x9B` → word 704. Em 8bpp cada word são 2 pixels, logo
## `0x9B` começa **128 pixels** adentro da mesma imagem. A moldura é emitida com `ot` 0-7
## (tpage `0x9B`) e o retrato com `ot = 12` (`0x9A`) — foi por isso que, sem esse deslocamento,
## o retrato saiu certo e a moldura saiu como blocos cinza (a metade esquerda do atlas é lisa).
const U_TPAGE_9B := 128

## Registros da moldura desenhados no modo STATUS: (u, v, w, h, dx, dy) da tabela B.
const MOLDURA := [
	[0, 0, 64, 64, 8, 16],              ## B0  — moldura do retrato
	[0, 64, 96, 56, 72, 20],            ## B1  — painel "condition" + ECG
	[64, 0, 64, 64, 160, 16],           ## B5  — painel EQUIP
	[0, 120, 88, 56, 224, 16],          ## B6  — EXIT / FILE / MAP
	[96, 72, 8, 136, 216, 80],          ## B7  — borda esquerda da coluna de itens
	[104, 64, 8, 144, 304, 72],         ## B8  — borda direita
	[0, 176, 96, 8, 216, 216],          ## B9  — borda de baixo
]
## ── O FUNDO DA CÉLULA NÃO É A MOLDURA ──
## Eu tentei desenhar a grade com B27 = `(0,72,80,120,224,66)` (+ B28/B29 na 5ª linha) e saiu
## faixas de moldura na parte de baixo: aquele retângulo não é o fundo das células.
## Quem é: o **ícone `item_id 0` do `ITEMA.SLD`** — a auditoria mediu que ele não é transparente
## (1200 px com um padrão próprio), ou seja **célula vazia é um ícone como qualquer outro**.
## Então o desenho da grade é uniforme: para cada um dos 10 slots, `itema/{id}.png`, com `id = 0`
## quando o slot está livre. B28/B29 continuam sem uso porque a base deles (`base[2]`,
## `ctx+0xec`) não foi medida — e isso está declarado, não preenchido com chute.
## ── BOTÕES EXIT / FILE / MAP: placa + rótulo, com variante NORMAL e DESTACADA ──
## A placa de cada botão são DUAS tiras de 8 px (topo e base) da tabela B, e cada botão tem
## **duas variantes**: `v = 200/208` e `v = 184/192`. Qual é qual está provado no sítio de desenho
## (`0x8006bf40`+): ele carrega o registro base e, quando `lb $v1, 0x1e($s3)` (o índice de
## seleção, um byte SINALIZADO em `ctx+0x1e`) bate com a linha, soma **`0x18` = 2 registros** —
## ou seja pula de `v=200` para `v=184`. Logo **`v=184/192` é o DESTACADO**.
##   EXIT  80×16 em (224,24): normal B121/B122 · destacado B123/B124
##   FILE  38×16 em (224,44): normal B113/B114 · destacado B115/B116
##   MAP   38×16 em (266,44): normal B117/B118 · destacado B119/B120
## Essas tiras vêm do STMAIN0U na tpage `0x9A` (ot 4/5), portanto **sem** o `+128`.
const PLACAS := [
	## [x, y, w, normal_v, destacado_v] — cada uma desenha 2 tiras de 8 px
	[224, 24, 80, 200, 184],            ## EXIT
	[224, 44, 38, 200, 184],            ## FILE
	[266, 44, 38, 200, 184],            ## MAP
]
const PLACA_U := 88

## Rótulos (STMOJIU), na ordem EXIT/FILE/MAP:
const BOTOES := [
	[32, 40, 40, 16, 247, 24],          ## B151 — EXIT
	[0, 40, 32, 16, 226, 44],           ## B149 — FILE
	[72, 40, 32, 16, 268, 44],          ## B150 — MAP
]

## Painéis sólidos (no jogo são TILE, sem textura): [x, y, w, h] — B64, B65, B145.
const PAINEIS := [[0, 88, 8, 96], [216, 88, 200, 96], [216, 200, 96, 24]]
## `rgb(8,8,8)` medido no montador de TILE (`0x8006e7d4`: `len=3, code=0x60, rgb=(8,8,8)`).
const COR_TILE := Color8(8, 8, 8)

## AZUL DO JOGO. `(8,0,80)` é a cor dominante do ícone de célula vazia do `ITEMA.SLD` (índice 228
## da paleta 1 do STMAIN0U) e a mais frequente do atlas — é o azul-marinho que a captura mostra
## nos painéis. **Declarado:** as tiras de placa no atlas são bandas CHAPADAS (cinza no destacado,
## quase preta no normal) e o azul da captura vem da cor do primitivo, que eu não decodifiquei.
## Uso o azul do próprio jogo, com a tira dando a diferença claro/escuro.
const COR_AZUL := Color8(8, 0, 80)
## Moldura das janelas grandes: cinza medido em `u=8, v=192` do atlas (134,132,134).
const COR_JANELA := Color8(134, 132, 134)
## ── SUBMENU DE COMANDO DO ITEM ──
## Caixa: B69 `(0,208,72,48,148,80)` (4 linhas) ou B70 `(72,220,56,36,148,128)` (menos linhas),
## escolhida por `ctx+0x44 & 0x10`. Fundo de cada linha: B77..B80 = `(24,184,64,24)` em
## `(155, 80/100/120/140)`. Placa de cada linha: as tiras de 56×8 em `x=159`, `y=84/104/124/144`,
## com o par normal (`v=200/208`) e destacado (`v=184/192`) — B125..B140.
## Rótulos (STMOJIU): B152 EQUIP `(0,56)` · B153 USE `(48,56)` · B154 COMBINE `(96,56)` ·
## B156 CHECK `(192,56)`, todos 48×16 em `x=163`. EQUIP ou USE sai de
## `*(u8*)(0x800a0514 + item_id*4) == 1` (byte 0 = "equipável"), medido: vale para os ids 1..20.
const SUB_CAIXA := [0, 208, 72, 48, 148, 80]
const SUB_LINHA_Y := [84, 104, 124]
const SUB_ROTULOS := {
	"EQUIP": [0, 56, 48, 16, 163, 0],
	"USE": [48, 56, 48, 16, 163, 0],
	"COMBINE": [96, 56, 48, 16, 163, 0],
	"CHECK": [192, 56, 48, 16, 163, 0],
}
const RETRATO := [0, 192, 40, 56, 18, 22]        ## B2 (JILL) — paleta 2
const CURSOR := [120, 0, 40, 30, 224, 66]        ## B146
const PLACA := [0, 0, 112, 72, 56, 88]           ## B66 — a placa grande do item (ITEMG.PIX)
## Palavras de condição: (u, v, w, h, dx, dy) de `0x800a0004 + cond*12`.
const CONDICAO := [
	[0, 32, 24, 8, 121, 25],            ## 0 FINE
	[24, 32, 40, 8, 113, 25],           ## 1 CAUTION
	[64, 32, 40, 8, 113, 25],           ## 2 CAUTION (amarelo)
	[104, 32, 40, 8, 113, 25],          ## 3 DANGER
	[144, 32, 32, 8, 115, 25],          ## 4 POISON
	[184, 32, 32, 8, 120, 25],          ## 5 VIRUS
]

var aberto := false
var cursor := 0                         ## `inv+0x128`
var _anim := 0                          ## quadros restantes da abertura/fechamento
var _fechando := false
var _piscada := 0x80
var _piscada_sobe := true
var _state: GameState = null

var _chrome: Texture2D = null           ## stmain0u paleta 0 (SD)
var _chrome_hd: Texture2D = null        ## bloco HD da metade direita (tpage 0x9B)
var _retratos: Texture2D = null         ## stmain0u paleta 2
var _palavras: Texture2D = null         ## STMOJIU — HD (1024x288) ou o PNG do PS1
var _palavras_fator := 1                ## 4 quando o atlas é o HD
var _icones: Dictionary = {}            ## item_id -> Texture2D (itema/NNN.png)
var _paletas: Dictionary = {}           ## índice de CLUT -> atlas SD do STMOJIU naquela paleta
## Botão destacado: -1 = nenhum · 0 EXIT · 1 FILE · 2 MAP.
var selecao_botao := -1
## Submenu do item: vazio = fechado. Guarda os rótulos na ordem em que aparecem.
var sub_itens: Array[String] = []
var sub_sel := 0
## Última ação do menu, para o HUD/log dizer o que aconteceu (e para o teste conferir).
var ultima_acao := ""
## Slot que espera o segundo item da COMBINAÇÃO (-1 = não está combinando). No jogo é o
## 2º marcador (B147, `u=160`), desenhado enquanto `ctx+0x18 & 0x02000000`.
var combinar_de := -1
## Texto na caixa de mensagem (vazio = mostra só o nome do item selecionado).
var mensagem := ""
static var _itens_json: Dictionary = {}
var _pronto := false


func _init() -> void:
	name = "MenuStatus"
	visible = false
	scale = Vector2(ESCALA, ESCALA)
	# ACIMA DE TUDO. Sem isto os RECORTES DE OCLUSÃO da câmera (que são desenhados depois na
	# árvore) aparecem por cima do menu — foi o que o usuário viu: a máquina de escrever e a mesa
	# da R100 cobrindo a tela de status. No PS1 o menu é uma task própria que desenha depois do
	# mundo, então ficar por cima é o comportamento certo, não um truque.
	z_index = 100


func carregar(state: GameState) -> bool:
	## Carrega os assets. `false` = falta rodar `python tools/status_assets.py --all`, e então a
	## tela não abre (em vez de aparecer uma caixa inventada).
	_state = state
	## MOLDURA EM HD: `hd/chrome_9b.webp` (512×1024) é o bloco de VRAM que o pack Seamless usa no
	## lugar da metade DIREITA do `STMAIN0U` — exatamente a região da tpage `0x9B`, que é de onde a
	## moldura sai. Casado por conteúdo (`port/dev/hd_casar.gd`): erro **0,0355** na posição
	## **(128,0)**, o mesmo nível dos casamentos confirmados das placas. Como ele COMEÇA em x=128,
	## o `u` do registro entra direto (sem o `+128`), só multiplicado por 4.
	## ⚠ O pack HD é o RUSSO: os rótulos batidos no bitmap saem em russo ("ОРУЖИЕ" no lugar de
	## EQUIP, "Состояние" no lugar de condition). É o material que existe; trocar para SD é uma
	## linha (`_chrome_fator = 1`).
	_chrome_hd = AssetIO.texture("MENU/status/hd/chrome_9b.webp")
	_chrome = AssetIO.texture("MENU/status/stmain0u_p0.png")
	_retratos = AssetIO.texture("MENU/status/stmain0u_p2.png")
	# PALAVRAS EM HD: `ETC/STMOJIU.webp` é 1024×288 = 4× o TIM do PS1 (256×72), e o par está
	# confirmado no `hd_ui_map.json` (`misc/8AAF0EE6`, método "conhecido/validado"). Cai para o
	# PNG do PS1 só se o HD não estiver instalado.
	_palavras = AssetIO.texture("ETC/STMOJIU.webp")
	_palavras_fator = 4
	if _palavras == null:
		_palavras = AssetIO.texture("MENU/status/stmojiu_p0.png")
		_palavras_fator = 1
	_pronto = _chrome != null and _retratos != null and _palavras != null
	return _pronto


func alternar() -> void:
	## Botão de menu: abre com animação de 6 quadros, fecha com outros 6.
	if not _pronto:
		return
	if aberto and not _fechando:
		_fechando = true
		_anim = ANIM_QUADROS
	elif not aberto:
		aberto = true
		visible = true
		_fechando = false
		_anim = ANIM_QUADROS
		cursor = _state.cursor if _state != null else 0


func avancar() -> void:
	## Um tick de 30 Hz da tela (o menu real roda a 60 Hz; ver "escolhas" no topo).
	if not aberto:
		return
	if _anim > 0:
		_anim -= 1
		if _anim == 0 and _fechando:
			aberto = false
			visible = false
			_fechando = false
	# piscada do cursor: sobe/desce de 2 em 2 com clamp em 0x3f
	if _piscada_sobe:
		_piscada += CURSOR_PASSO
		if _piscada >= 0x80 + CURSOR_TETO:
			_piscada = 0x80 + CURSOR_TETO
			_piscada_sobe = false
	else:
		_piscada -= CURSOR_PASSO
		if _piscada <= 0x80:
			_piscada = 0x80
			_piscada_sobe = true
	queue_redraw()


func mover_cursor(dx: int, dy: int) -> void:
	## Navegação. Na grade é `col ± 1` / `lin ± 1` (`0x80066788`+, o cursor de tela é
	## `x = col*40, y = lin*30`). Subindo da primeira linha sai da grade: o jogo permite o índice
	## de seleção chegar a **-1..-4** (a auditoria corrigiu o alcance: o teste `slti < -2` roda
	## ANTES do decremento, então -4 é alcançável) e são essas posições que dão nos botões
	## EXIT/FILE/MAP. **O de-para de qual índice negativo é qual botão NÃO foi medido**; aqui:
	## -1 = FILE/MAP (pela coluna) e -2 = EXIT. É escolha do port, declarada.
	if not aberto or _anim > 0:
		return
	if not sub_itens.is_empty():
		if dy != 0:
			sub_sel = posmod(sub_sel + dy, sub_itens.size())
			queue_redraw()
		return
	if selecao_botao >= 0:
		# está nos botões
		if dy > 0:
			selecao_botao = -1                  ## volta para a grade
		elif dy < 0 and selecao_botao != 0:
			selecao_botao = 0                   ## FILE/MAP -> EXIT
		elif dx != 0 and selecao_botao != 0:
			selecao_botao = 1 if selecao_botao == 2 else 2
		elif dx != 0 and selecao_botao == 0:
			pass                                 ## EXIT ocupa a linha toda
		queue_redraw()
		return
	mensagem = ""
	var col := cursor % GRADE_COLUNAS
	var lin := cursor / GRADE_COLUNAS
	if dy < 0 and lin == 0:
		selecao_botao = 1 if col == 0 else 2     ## sai da grade para FILE (esq) ou MAP (dir)
		queue_redraw()
		return
	col = clampi(col + dx, 0, GRADE_COLUNAS - 1)
	lin = clampi(lin + dy, 0, GRADE_LINHAS - 1)
	cursor = lin * GRADE_COLUNAS + col
	if _state != null:
		_state.cursor = cursor
	queue_redraw()


func condicao() -> int:
	## `Itens.condicao` = a função `0x8006e598` do EXE, com o HP e as flags AO VIVO do player.
	var pl := _player()
	if pl == null:
		return 0
	return Itens.condicao(pl.hp, pl.status)


func _hp() -> int:
	var g := get_node_or_null("/root/Game")
	if g != null and g.get("mundo") != null and g.mundo.player != null:
		return g.mundo.player.hp
	return 200


func _draw() -> void:
	if not _pronto or not aberto:
		return
	# a animação de abertura é uma cortina vertical (o menu cresce em 6 quadros); enquanto ela
	# corre, desenha-se a tela recortada verticalmente no centro.
	var t := 1.0
	if _anim > 0:
		var passo := float(ANIM_QUADROS - _anim + 1) / float(ANIM_QUADROS)
		t = passo if not _fechando else 1.0 - passo
	if t <= 0.01:
		return
	# Fundo PRETO opaco: é o que a captura do jogo mostra (a tela de status não deixa o cenário
	# aparecer). O EXE não desenha background próprio aqui — ele só salva/restaura a região da
	# VRAM que vai sobrescrever (`StoreImage`/`LoadImage` no init/exit) —, então a evidência do
	# preto é a captura, e está declarado como tal.
	draw_rect(Rect2(0, 0, 320, 240), Color(0, 0, 0, t))
	# painéis escuros de fundo: no jogo são **TILE com rgb(8,8,8)** (retângulo sólido, sem
	# textura) — B64 `(0,88,8,96)`, B65 `(216,88,200,96)` e B145 `(216,200,96,24)`
	# (`0x8006bb8c` cnt=2 e `0x8006c2e4`). O B65 passa de 320 em x; o PS1 recorta na área de
	# desenho, então aqui também se recorta.
	for p: Array in PAINEIS:
		_caixa(Rect2(p[0], p[1], p[2], p[3]), COR_TILE, t)
	# as duas janelas grandes: a da placa do item e a da mensagem (B141 e B144, POLY_FT4 de
	# moldura 9-fatias). Ver COR_JANELA para o que é medido e o que é aproximação.
	_janela(Rect2(12, 84, 200, 80), t)
	_janela(Rect2(12, 172, 200, 48), t)
	for r: Array in MOLDURA:
		_moldura(r, t)
	_blit(_retratos, RETRATO, t)
	_blit(_palavras, CONDICAO[condicao()], t, Color.WHITE, 0, _palavras_fator)
	_desenhar_botoes(t)
	_desenhar_equipada(t)
	_desenhar_placa(t)
	_desenhar_itens(t)
	_desenhar_cursor(t)
	_desenhar_mensagem(t)
	_desenhar_submenu(t)


func _moldura(r: Array, t: float, cor := Color.WHITE) -> void:
	## Desenha um registro da MOLDURA. Em HD o bloco já começa no x=128 do atlas SD, então o `u`
	## do registro vale direto ×4; em SD é preciso somar o `+128` da tpage `0x9B`.
	if _chrome_hd != null:
		_blit(_chrome_hd, r, t, cor, 0, 4)
	else:
		_blit(_chrome, r, t, cor, U_TPAGE_9B)


func _blit(tex: Texture2D, r: Array, t: float, cor := Color.WHITE, du := 0, fator := 1) -> void:
	## `fator` = escala da IMAGEM FONTE em relação ao SD. O pack HD do Seamless é **exatamente 4×**
	## do PS1 em todos os assets conferidos, então o mesmo registro de 12 bytes serve para os dois:
	## multiplica-se só o retângulo de origem, e o destino (320×240) não muda.
	if tex == null:
		return
	var origem := Rect2i((int(r[0]) + du) * fator, int(r[1]) * fator,
		int(r[2]) * fator, int(r[3]) * fator)
	var destino := Rect2(float(r[4]), float(r[5]), float(r[2]), float(r[3]))
	if t < 1.0:
		# cortina: encolhe verticalmente em torno do centro da tela
		var meio := 120.0
		destino.position.y = meio + (destino.position.y - meio) * t
		destino.size.y *= t
	draw_texture_rect_region(tex, destino, origem, cor)


func _desenhar_mensagem(t: float) -> void:
	## Caixa de mensagem (B144, 200×48 em (12,172)): NOME do item selecionado e, depois do CHECK,
	## o texto de EXAME. Fonte do jogo (`Texto`, atlas `ETC/TEXU.TIM`, célula 14×14 proporcional).
	## O texto vem de `data/re3_items.json` (extraído do EXE + mod PT), campo `name_pt`/`exam_pt`.
	if t < 1.0 or _state == null:
		return
	var id := int(_state.main_slots[cursor].get("id", 0)) if cursor < _state.main_slots.size() else 0
	if id == 0:
		return
	var caixa := Rect2i(20, 178, 184, 38)
	if mensagem != "":
		Texto.desenhar_bloco(self, mensagem, caixa)
		return
	Texto.desenhar(self, _nome_do_item(id), Vector2i(caixa.position.x, caixa.position.y))


func _nome_do_item(id: int) -> String:
	var e := _dado_do_item(id)
	return String(e.get("name_pt", e.get("name_en", "item 0x%02x" % id)))


func _dado_do_item(id: int) -> Dictionary:
	if _itens_json.is_empty():
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/re3_items.json"))
		if raw is Dictionary:
			_itens_json = (raw as Dictionary).get("by_id", {})
	var e: Variant = _itens_json.get("0x%02x" % id)
	return e if e is Dictionary else {}


func _desenhar_submenu(t: float) -> void:
	if sub_itens.is_empty():
		return
	# A caixa do jogo tem DUAS alturas fixas (B69 72×48 e B70 56×36, escolhidas por
	# `ctx+0x44 & 0x10`) e nenhuma delas cabe 3 linhas de 20 px — o jogo monta o resto com a
	# moldura de 9 fatias (B81..B112), cuja altura é calculada em runtime e a nota não resolveu.
	# Então aqui a caixa é DESENHADA no tamanho das linhas, com as cores medidas: interior azul
	# do jogo e borda cinza do atlas. Declarado: tamanho calculado, cores medidas.
	var alt := 20 * sub_itens.size() + 8
	_caixa(Rect2(153, 78, 68, alt), COR_AZUL, t)
	var d := Rect2(153, 78, 68, alt)
	if t < 1.0:
		d.position.y = 120.0 + (d.position.y - 120.0) * t
		d.size.y *= t
	draw_rect(d, Color(COR_JANELA.r, COR_JANELA.g, COR_JANELA.b, t), false, 2.0)
	for i in sub_itens.size():
		var y: int = SUB_LINHA_Y[i] if i < SUB_LINHA_Y.size() else SUB_LINHA_Y[-1] + 20 * i
		var destacado := i == sub_sel
		var v := 184 if destacado else 200
		var brilho := 2.6 if destacado else 1.0
		var cor := Color(clampf(COR_AZUL.r * brilho, 0.0, 1.0),
			clampf(COR_AZUL.g * brilho + (0.10 if destacado else 0.0), 0.0, 1.0),
			clampf(COR_AZUL.b * brilho, 0.0, 1.0))
		_moldura([PLACA_U, v, 56, 8, 159, y], t, cor)
		_moldura([PLACA_U, v + 8, 56, 8, 159, y + 8], t, cor)
		var rot: Array = SUB_ROTULOS[sub_itens[i]].duplicate()
		rot[5] = y
		_blit(_palavras, rot, t, Color.WHITE, 0, _palavras_fator)


func confirmar() -> String:
	## Enter/ação. Devolve o que aconteceu (também fica em `ultima_acao`).
	if not aberto or _anim > 0:
		return ""
	if combinar_de >= 0:
		var feito := _combinar(combinar_de, cursor)
		combinar_de = -1
		queue_redraw()
		ultima_acao = feito
		return feito
	if not sub_itens.is_empty():
		var escolha := sub_itens[sub_sel]
		sub_itens.clear()
		queue_redraw()
		match escolha:
			"EQUIP":
				if _state != null:
					_state.equipped = cursor      ## `inv+0x128` = slot equipado
				ultima_acao = "equipou o slot %d" % cursor
			"USE":
				ultima_acao = _usar()
			"COMBINE":
				# entra no modo de escolher o SEGUNDO item (no jogo é o 2º marcador, B147)
				combinar_de = cursor
				ultima_acao = "escolha o item para combinar"
			"CHECK":
				var idc := int(_state.main_slots[cursor].get("id", 0)) if _state != null else 0
				var e := _dado_do_item(idc)
				mensagem = String(e.get("exam_pt", e.get("exam_en", "")))
				ultima_acao = "examinou: %s" % mensagem.substr(0, 40)
		return ultima_acao
	if selecao_botao == 0:
		alternar()                                ## EXIT fecha
		ultima_acao = "EXIT"
		return ultima_acao
	if selecao_botao == 1:
		ultima_acao = "FILE: a tela de arquivo ainda não foi ligada (183 páginas já extraídas)"
		return ultima_acao
	if selecao_botao == 2:
		ultima_acao = "MAP: a tela de mapa ainda não foi ligada"
		return ultima_acao
	# está na grade: abre o submenu do item, se houver item
	if _state == null:
		return ""
	var id := int(_state.main_slots[cursor].get("id", 0)) if cursor < _state.main_slots.size() else 0
	if id == 0:
		ultima_acao = "slot vazio"
		return ultima_acao
	sub_itens = []
	sub_itens.append("EQUIP" if _equipavel(id) else "USE")
	sub_itens.append("COMBINE")
	sub_itens.append("CHECK")
	sub_sel = 0
	queue_redraw()
	ultima_acao = "submenu do item 0x%02x" % id
	return ultima_acao


func _usar() -> String:
	## USE em item de CURA, com os valores da tabela `0x80010e4c` e a aplicação de `0x80067934`:
	## soma o HP, faz clamp em maxHP, limpa o bit de veneno quando a entrada manda, e o item
	## SOME — exceto a F. Aid Box (`0x2a`), que gasta 1 de quantidade.
	if _state == null or cursor >= _state.main_slots.size():
		return "sem item"
	var slot: Dictionary = _state.main_slots[cursor]
	var id := int(slot.get("id", 0))
	var pl := _player()
	if pl == null:
		return "sem personagem"
	var efeito: Dictionary = Itens.cura_de(id, int(pl.hp_max))
	if not bool(efeito.get("valido", false)):
		return "esse item não faz efeito sozinho"      ## é o caso da Erva vermelha (mensagem 7)
	var antes: int = pl.hp
	var teto: int = pl.hp_max
	pl.hp = mini(antes + int(efeito["hp"]), teto)
	if bool(efeito["veneno"]):
		pl.status = pl.status & ~0x0200      ## `gs[0x255e] &= ~0x0200` (0x80067934)
	if bool(efeito["gasta_um"]):
		slot["qtd"] = maxi(0, int(slot.get("qtd", 1)) - 1)
		if int(slot["qtd"]) == 0:
			_state.main_slots[cursor] = {"id": 0, "qtd": 0, "flags": 0}
	else:
		_state.main_slots[cursor] = {"id": 0, "qtd": 0, "flags": 0}
	queue_redraw()
	return "curou %d -> %d de HP%s" % [antes, pl.hp,
		" e o veneno" if bool(efeito["veneno"]) else ""]


func _combinar(slot_a: int, slot_b: int) -> String:
	## `combine_find` (`0x8006a898`): busca LINEAR e SIMÉTRICA na tabela de 125 receitas.
	## Os tipos de receita estão em `Itens` (recarregar arma, simples, pólvora → munição,
	## upgrade de arma, troca de granada, pólvora → granada, munição infinita).
	if _state == null or slot_a == slot_b:
		return "combinação cancelada"
	var a: Dictionary = _state.main_slots[slot_a]
	var b: Dictionary = _state.main_slots[slot_b]
	var ida := int(a.get("id", 0))
	var idb := int(b.get("id", 0))
	if ida == 0 or idb == 0:
		return "slot vazio"
	var r := Itens.receita(ida, idb)
	if r.is_empty():
		return "não combina"
	var tipo := int(r.get("kind", -1))
	var c := int(r.get("c", 0))
	var n := int(r.get("n", 0))
	match tipo:
		Itens.REC_SIMPLES:
			# a + b -> c, gastando um de cada (ervas)
			_state.main_slots[slot_a] = {"id": c, "qtd": maxi(1, n), "flags": 0}
			_state.main_slots[slot_b] = {"id": 0, "qtd": 0, "flags": 0}
			queue_redraw()
			return "combinou -> item 0x%02x" % c
		Itens.REC_RECARREGAR:
			# arma + munição: enche a arma até o `max` do descritor e desconta da munição
			var arma_slot := slot_a if Itens.categoria(ida) == Itens.CAT_ARMA else slot_b
			var mun_slot := slot_b if arma_slot == slot_a else slot_a
			var arma: Dictionary = _state.main_slots[arma_slot]
			var mun: Dictionary = _state.main_slots[mun_slot]
			var cap := Itens.maximo(int(arma["id"]))
			var falta := maxi(0, cap - int(arma.get("qtd", 0)))
			var passa := mini(falta, int(mun.get("qtd", 0)))
			if passa <= 0:
				return "a arma já está cheia"
			arma["qtd"] = int(arma.get("qtd", 0)) + passa
			mun["qtd"] = int(mun.get("qtd", 0)) - passa
			if int(mun["qtd"]) == 0:
				_state.main_slots[mun_slot] = {"id": 0, "qtd": 0, "flags": 0}
			queue_redraw()
			return "recarregou %d (arma com %d)" % [passa, int(arma["qtd"])]
		_:
			# pólvora, upgrade, granada e munição infinita têm regras próprias (bônus por
			# quantidade, grupo de munição, troca de tipo) que ainda não foram ligadas.
			return "receita do tipo %s ainda não ligada" % r.get("kind_nome", tipo)


func _player() -> Object:
	var g := get_node_or_null("/root/Game")
	if g != null and g.get("mundo") != null:
		return g.mundo.player
	return null


func cancelar() -> void:
	## ESC dentro do menu: cancela a combinação, senão fecha o submenu, senão fecha a tela.
	if combinar_de >= 0:
		combinar_de = -1
		queue_redraw()
		return
	if not sub_itens.is_empty():
		sub_itens.clear()
		queue_redraw()
		return
	alternar()


func _equipavel(item_id: int) -> bool:
	## Agora lê o DESCRITOR de verdade (`0x800a0514`, byte 0 = categoria): `cat == 1` é arma.
	## Antes eu usava a faixa "id 1..20", que era a consequência observada, não a causa.
	return Itens.equipavel(item_id)


func _caixa(r: Rect2, cor: Color, t: float) -> void:
	## Retângulo sólido no espaço 320×240, com o recorte da tela (o PS1 recorta na área de
	## desenho — o painel B65 passa de x=320 no dado).
	var d := r
	if t < 1.0:
		d.position.y = 120.0 + (d.position.y - 120.0) * t
		d.size.y *= t
	d = d.intersection(Rect2(0, 0, 320, 240))
	if d.size.x > 0.0 and d.size.y > 0.0:
		draw_rect(d, Color(cor.r, cor.g, cor.b, t))


func _janela(r: Rect2, t: float) -> void:
	## Janela grande (B141 = placa do item, B144 = mensagem): interior azul + moldura clara.
	## No jogo é uma moldura de 9 fatias (B81..B112) mais o preenchimento; aqui é interior + borda
	## de 2 px com as cores medidas do atlas. É aproximação DECLARADA da moldura, não das medidas:
	## posição e tamanho são os registros reais.
	_caixa(r, COR_AZUL, t)
	var d := r
	if t < 1.0:
		d.position.y = 120.0 + (d.position.y - 120.0) * t
		d.size.y *= t
	draw_rect(d, Color(COR_JANELA.r, COR_JANELA.g, COR_JANELA.b, t), false, 2.0)


func _desenhar_botoes(t: float) -> void:
	## Placa + rótulo de EXIT/FILE/MAP. O botão selecionado usa a variante DESTACADA (v=184/192).
	## `selecao_botao` = -1 nenhum · 0 EXIT · 1 FILE · 2 MAP (o índice do jogo é `ctx+0x1e`, e o
	## de-para dele para estes três botões não foi medido — ver `mover_cursor`).
	for i in PLACAS.size():
		var p: Array = PLACAS[i]
		var destacado := i == selecao_botao
		var v: int = int(p[4]) if destacado else int(p[3])
		var brilho := 2.6 if destacado else 1.0    ## a tira do destacado é ~4x mais clara
		var cor := Color(clampf(COR_AZUL.r * brilho, 0.0, 1.0),
			clampf(COR_AZUL.g * brilho + (0.10 if destacado else 0.0), 0.0, 1.0),
			clampf(COR_AZUL.b * brilho, 0.0, 1.0))
		# duas tiras de 8 px, como no dado
		_moldura([PLACA_U, v, int(p[2]), 8, int(p[0]), int(p[1])], t, cor)
		_moldura([PLACA_U, v + 8, int(p[2]), 8, int(p[0]), int(p[1]) + 8], t, cor)
	for r: Array in BOTOES:
		_blit(_palavras, r, t, Color.WHITE, 0, _palavras_fator)


func _desenhar_equipada(t: float) -> void:
	## Painel EQUIP: ícone 40×30 da arma equipada em **(172,37)** (B68 = `(80,132,40,30,172,37)`,
	## `0x8006ba7c`) e a quantidade dela em **(174,55)** (`0x800a0080[10]`, `0x8006c0d4`).
	## `inv+0x128` = slot equipado (0xff = nenhum) e `inv+0x129` = o item_id dele.
	if _state == null:
		return
	var id := _state.equipped_item_id()
	if id == 0:
		return
	var tex := _icone(id)
	if tex != null:
		var d := Rect2(172.0, 37.0, 40.0, 30.0)
		if t < 1.0:
			d.position.y = 120.0 + (d.position.y - 120.0) * t
			d.size.y *= t
		draw_texture_rect(tex, d, false)
	var qtd := _state.equipped_qtd()
	if qtd > 0:
		_desenhar_qtd(qtd, Vector2i(174, 55), t, 2)


func _desenhar_placa(t: float) -> void:
	## A PLACA grande do item selecionado: B66 = `(0,0,112,72,56,88)`, e a imagem é a página do
	## `ETC/ITEMG.PIX` do item (`lba = filetab[0x33].lba + id*5`, `size = 0x2800`, 112×72,
	## índice = item_id). Já extraída em `assets/ETC/items/NNN.png`.
	if _state == null:
		return
	var slot: Dictionary = _state.main_slots[cursor] if cursor < _state.main_slots.size() else {}
	var id := int(slot.get("id", 0))
	if id == 0:
		return
	# HD primeiro (`hd/plate/NNN.webp` = 448×288, 4× a placa do PS1), SD como queda. O de-para
	# saiu de casamento por CONTEÚDO (`port/dev/hd_casar.gd`): 96 das 134 placas, com o 2º
	# colocado ao menos 8% pior. Como a imagem é desenhada inteira no retângulo de destino, o
	# 4× não exige conta nenhuma aqui.
	# `exists` antes de `texture`: pedir um HD que não existe faria o AssetIO logar aviso a cada
	# quadro (só 96 das 134 placas têm par HD), e aviso repetido some no meio do log.
	var rel_hd := "MENU/status/hd/plate/%03d.webp" % id
	var tex := AssetIO.texture(rel_hd) if AssetIO.exists(rel_hd) else 		AssetIO.texture("ETC/items/%03d.png" % id)
	if tex == null:
		return
	var destino := Rect2(float(PLACA[4]), float(PLACA[5]), float(PLACA[2]), float(PLACA[3]))
	if t < 1.0:
		destino.position.y = 120.0 + (destino.position.y - 120.0) * t
		destino.size.y *= t
	draw_texture_rect(tex, destino, false)


func _desenhar_itens(t: float) -> void:
	if _state == null:
		return
	for i in GRADE_COLUNAS * GRADE_LINHAS:
		var slot: Dictionary = _state.main_slots[i] if i < _state.main_slots.size() else {}
		var id := int(slot.get("id", 0))   ## 0 = livre, e o ícone 0 é o padrão de célula vazia
		var col := i % GRADE_COLUNAS
		var lin := i / GRADE_COLUNAS
		var p := GRADE_ORIGEM + Vector2i(col * CELULA.x, lin * CELULA.y)
		var tex := _icone(id)
		if tex != null:
			var destino := Rect2(float(p.x), float(p.y), float(CELULA.x), float(CELULA.y))
			if t < 1.0:
				destino.position.y = 120.0 + (destino.position.y - 120.0) * t
				destino.size.y *= t
			draw_texture_rect(tex, destino, false)
		var qtd := int(slot.get("qtd", 0))
		if qtd > 1:
			var fl := int(slot.get("flags", 0))
			_desenhar_qtd(qtd, p + QTD_OFFSET, t, 2 + ((fl >> 2) & 3))


func _desenhar_qtd(qtd: int, onde: Vector2i, t: float, paleta := 2) -> void:
	## Dígitos do STMOJIU: `u0 = 4 + d*8`, `v0 = 19`, 8×11, avanço 8 (`0x8006c940`), e a fileira
	## `v = 19..29` do atlas é `0 1 2 3 4 5 6 7 8 9 %`.
	##
	## COR: `clut_idx = ctx+0xd3 + ((slot.flags >> 2) & 3) + 2` (`0x8006c08c`), com `ctx+0xd3 = 0`
	## → paleta **2..5** do STMOJIU. É assim que munição baixa muda de cor. Por isso o número usa
	## o atlas SD por paleta (`stmojiu_pN.png`): o atlas HD tem uma coloração só, batida.
	## Não há glifo "x" antes do número (medido) — só os dígitos.
	var tex := _atlas_paleta(paleta)
	var s := str(qtd)
	var x := onde.x
	for k in s.length():
		var d := s.unicode_at(k) - 48
		if d < 0 or d > 9:
			continue
		_blit(tex, [DIGITO_U0 + d * DIGITO_W, DIGITO_V, DIGITO_W, DIGITO_H, x, onde.y], t)
		x += DIGITO_W


func _desenhar_cursor(t: float) -> void:
	if selecao_botao >= 0:
		return                                   ## a seleção está nos botões, não na grade
	var col := cursor % GRADE_COLUNAS
	var lin := cursor / GRADE_COLUNAS
	var r := CURSOR.duplicate()
	r[4] = GRADE_ORIGEM.x + col * CELULA.x
	r[5] = GRADE_ORIGEM.y + lin * CELULA.y
	# `rgb = contador - 0x80` -> 0..0x3f sobre 0x80 de base: aqui vira brilho 0.5..1.0
	var b := 0.5 + 0.5 * float(_piscada - 0x80) / float(CURSOR_TETO)
	# O cursor vem do **STMOJIU**, não do STMAIN0U. Prova: a auditoria mediu a CLUT dele em
	# `(304,483)` — e `304` é exatamente o `DX` do bloco de CLUT do STMOJIU (`DX=304 DY=480 w=16
	# h=9`), enquanto o STMAIN0U tem `DX=0`. Bate também com o `ot = 17` → tpage `0x3A`, que é
	# **4bpp** (`tp = 0`), o formato do STMOJIU (o STMAIN0U é 8bpp). Desenhar do STMAIN0U punha um
	# pedaço da palavra "EQUIP" gigante na primeira célula — foi o "F" que apareceu no teste.
	## CLUT medida: `(304,483)` = **paleta 3** do STMOJIU (`ctx+0xd3 + 3`). Sprite: retângulo
	## VAZADO 40×30 (o crop do atlas mostra três deles em u=120/160/200).
	_blit(_atlas_paleta(3), r, t, Color(b, b, b, 0.5))  ## SemiTrans do PS1 = B/2+F/2 (50%)


func _atlas_paleta(i: int) -> Texture2D:
	## STMOJIU na linha de CLUT `i` (SD). O jogo troca de CLUT por elemento — cursor na 3, número
	## na 2..5 —, e o atlas HD tem coloração única, então quem precisa de paleta usa o SD.
	if _paletas.has(i):
		return _paletas[i]
	var tex := AssetIO.texture("MENU/status/stmojiu_p%d.png" % i)
	_paletas[i] = tex
	return tex


func _icone(item_id: int) -> Texture2D:
	if _icones.has(item_id):
		return _icones[item_id]
	## HD primeiro (`hd/itema/NNN.webp` = 160×120), SD como queda. Casados por conteúdo: 49 dos
	## 134 — os ícones pequenos são muito redesenhados no pack HD, então a margem só fecha em 49.
	## Os outros continuam no SD, e isso fica visível na tela em vez de escondido.
	var rel_hd := "MENU/status/hd/itema/%03d.webp" % item_id
	var tex := AssetIO.texture(rel_hd) if AssetIO.exists(rel_hd) else 		AssetIO.texture("MENU/status/itema/%03d.png" % item_id)
	_icones[item_id] = tex
	return tex
