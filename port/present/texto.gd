class_name Texto
extends RefCounted
## Desenho de TEXTO com a fonte do jogo (P6-06). Recomp, não uma `Font` do Godot.
##
## Fonte: `docs/decomp/notes/menu_texto.md` + `data/re3_font.json` (gerado por
## `tools/menu_texto.py`, lido do `SLUS_009.23` e do `ETC/TEXU.TIM`).
##
## ── O atlas ──
## `ETC/TEXU.TIM`: 4bpp, **1024×256**, carregado na VRAM em (768,256), com **60 CLUTs** em
## (256,480). Cada glifo é uma célula de **14×14** numa grade de **18 colunas**:
##
##     cod = ASCII - 0x24        (para ASCII 0x24..0x7a; o espaço 0x20 vira cod 0)
##     u = (cod % 18) * 14
##     v = (cod / 18) * 14 + 28      (o +28 é a base do banco normal)
##
## ── A fonte é PROPORCIONAL ──
## Tabela em `0x80098dd0`, 87 entradas: cada glifo tem `trim_left` (quantos pixels pular à
## esquerda) e `advance` (quanto andar depois). Ex.: `A` avança 14, `i` avança 10 com trim 4,
## `.` avança 7 com trim 2. Ignorar isso dá texto com buracos — é o erro clássico de tratar
## fonte de RE como monoespaçada.
##
## Altura de linha: **16**.
##
## ── Cor ──
## A cor é a linha de CLUT (60 disponíveis). O port recebe o índice e usa o PNG correspondente
## em `assets/FONT/TEXU_clut_y{480+i}.png` — mesma ideia do STMOJIU na tela de status.

const CAMINHO := "res://data/re3_font.json"
const CELULA := 14
const COLUNAS := 18
const V_BASE := 28                     ## base do banco "normal" na grade
const ALTURA_LINHA := 16
const CLUT_BASE := 480

static var _dados: Dictionary = {}
static var _largura: Dictionary = {}   ## cod -> {trim_left, advance}
static var _carregado := false
static var _atlas: Dictionary = {}     ## índice de CLUT -> Texture2D


static func _carregar() -> void:
	if _carregado:
		return
	_carregado = true
	if not FileAccess.file_exists(CAMINHO):
		push_error("Texto: %s ausente — rode `python tools/menu_texto.py --font`" % CAMINHO)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
	if not (raw is Dictionary):
		return
	_dados = raw
	for e: Dictionary in (_dados.get("tabela_larguras", {}) as Dictionary).get("entradas", []):
		_largura[int(e.get("code", 0))] = {
			"trim": int(e.get("trim_left", 0)), "adv": int(e.get("advance", CELULA))}


static func atlas(clut := 0) -> Texture2D:
	_carregar()
	if _atlas.has(clut):
		return _atlas[clut]
	var tex := AssetIO.texture("FONT/TEXU_clut_y%d.png" % (CLUT_BASE + clut))
	_atlas[clut] = tex
	return tex


static func codigo(c: int) -> int:
	## `cod = ASCII - 0x24`, com o espaço (0x20) mapeado em 0. Fora da faixa devolve -1.
	if c == 0x20:
		return 0
	if c >= 0x24 and c <= 0x7A:
		return c - 0x24
	return -1


static func avanco(cod: int) -> int:
	_carregar()
	var d: Dictionary = _largura.get(cod, {})
	return int(d.get("adv", CELULA))


static func trim(cod: int) -> int:
	_carregar()
	var d: Dictionary = _largura.get(cod, {})
	return int(d.get("trim", 0))


static func largura(s: String) -> int:
	## Largura em pixels de tela (320×240) de uma linha, pela tabela proporcional.
	var w := 0
	for i in s.length():
		var cod := codigo(s.unicode_at(i))
		if cod >= 0:
			w += avanco(cod)
	return w


static func quebrar(s: String, largura_max: int) -> Array[String]:
	## Quebra em palavras respeitando a largura em pixels (o desenho do jogo quebra por
	## largura, não por número de caracteres).
	var linhas: Array[String] = []
	var atual := ""
	for palavra: String in s.split(" ", false):
		var teste := palavra if atual == "" else atual + " " + palavra
		if largura(teste) <= largura_max or atual == "":
			atual = teste
		else:
			linhas.append(atual)
			atual = palavra
	if atual != "":
		linhas.append(atual)
	return linhas


static func desenhar(ci: CanvasItem, s: String, onde: Vector2i, clut := 0,
		cor := Color.WHITE) -> int:
	## Desenha uma linha e devolve a largura usada. Coordenadas no espaço 320×240.
	var tex := atlas(clut)
	if tex == null:
		return 0
	var x := onde.x
	for i in s.length():
		var cod := codigo(s.unicode_at(i))
		if cod < 0:
			continue
		var u := (cod % COLUNAS) * CELULA
		var v := int(cod / COLUNAS) * CELULA + V_BASE
		var t := trim(cod)
		var a := avanco(cod)
		# `trim_left` pula pixels da célula; a largura desenhada é o avanço
		ci.draw_texture_rect_region(tex, Rect2(x, onde.y, a, CELULA),
			Rect2i(u + t, v, a, CELULA), cor)
		x += a
	return x - onde.x


static func desenhar_bloco(ci: CanvasItem, s: String, caixa: Rect2i, clut := 0,
		cor := Color.WHITE) -> int:
	## Desenha várias linhas dentro de uma caixa, quebrando por largura. Devolve quantas linhas.
	var linhas := quebrar(s, caixa.size.x)
	var y := caixa.position.y
	var n := 0
	for l: String in linhas:
		if y + CELULA > caixa.position.y + caixa.size.y:
			break
		desenhar(ci, l, Vector2i(caixa.position.x, y), clut, cor)
		y += ALTURA_LINHA
		n += 1
	return n
