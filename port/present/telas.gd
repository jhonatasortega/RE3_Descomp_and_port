class_name Telas
extends CanvasLayer
## Telas de UI do port: INVENTÁRIO (I), MAPA (M), PAUSA (ESC) e MENU PRINCIPAL (P6-01/02/03).
##
## Por que uma camada só: as quatro telas compartilham a mesma regra — **pausam o gameplay**
## (o `Clock` para de emitir tick, então o mundo congela em 30 Hz determinístico) e desenham
## por cima do quadro 1280×960. Uma `CanvasLayer` acima do `Screen` resolve isso sem mexer na
## composição background+SubViewport.
##
## ── O que é DADO do jogo e o que é do port ──
## • Nomes/descrições dos itens vêm de `data/re3_items.json` (extraído do EXE + mod PT-BR);
##   o ícone HD vem de `hd_ui_map.json` quando existe (P6-05). Sem ícone, desenha o nome.
## • O grid do inventário do RE3 é 2 colunas × 4 linhas (8 slots) + o slot de arma equipada;
##   o `GameState` já guarda 8 slots de bolsa + 64 de baú (`exe_items.md`).
## • O MAPA usa as telas `MAP_U` já extraídas (`assets/MAP/`), uma por andar/área.
## • A ARTE do menu principal do original é FMV + telas do `ETC`; aqui o menu é do PORT
##   (texto sobre a tela de título extraída), declarado como não-1:1 até P6-01 fechar.

enum Tela { NENHUMA, INVENTARIO, MAPA, PAUSA, MENU_PRINCIPAL }

const COR_FUNDO := Color(0.02, 0.02, 0.04, 0.86)
const COR_BORDA := Color(0.55, 0.08, 0.08, 1.0)      ## vermelho RE
const COR_TEXTO := Color(0.92, 0.90, 0.86, 1.0)
const COR_SEL := Color(1.0, 0.85, 0.25, 1.0)
const LARGURA := 1280
const ALTURA := 960

signal fechou()
signal pediu_novo_jogo()
signal pediu_continuar()
signal pediu_sair()

var tela: Tela = Tela.NENHUMA
var state: GameState
var mundo: World
var sel := 0                                  ## item/opção selecionada
var _itens_db: Dictionary = {}                ## id -> {nome, descricao}
var _raiz: Control
var _titulo: Label
var _corpo: RichTextLabel
var _rodape: Label
var _fundo: ColorRect
var _mapa: TextureRect


func _ready() -> void:
	layer = 10
	_montar()
	visible = false
	_carregar_itens()


func _montar() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_raiz)
	_fundo = ColorRect.new()
	_fundo.color = COR_FUNDO
	_fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.add_child(_fundo)

	_mapa = TextureRect.new()
	_mapa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mapa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mapa.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mapa.visible = false
	_raiz.add_child(_mapa)

	_titulo = Label.new()
	_titulo.position = Vector2(90, 60)
	_titulo.add_theme_font_size_override("font_size", 44)
	_titulo.add_theme_color_override("font_color", COR_BORDA)
	_raiz.add_child(_titulo)

	_corpo = RichTextLabel.new()
	_corpo.bbcode_enabled = true
	_corpo.position = Vector2(90, 140)
	_corpo.size = Vector2(LARGURA - 180, ALTURA - 260)
	_corpo.add_theme_font_size_override("normal_font_size", 26)
	_corpo.add_theme_color_override("default_color", COR_TEXTO)
	_raiz.add_child(_corpo)

	_rodape = Label.new()
	_rodape.position = Vector2(90, ALTURA - 90)
	_rodape.add_theme_font_size_override("font_size", 22)
	_rodape.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_raiz.add_child(_rodape)


func _carregar_itens() -> void:
	var d: Variant = AssetIO.json("re3_items.json")
	if not (d is Dictionary):
		return
	# o JSON tem várias seções; aceita tanto {itens:{id:{...}}} quanto lista
	# `by_id` tem as chaves em hex ("0x21"); a lógica trabalha com o id numérico do AOT
	var fonte: Variant = (d as Dictionary).get("by_id", {})
	if fonte is Dictionary:
		for k: String in (fonte as Dictionary):
			_itens_db[k.hex_to_int()] = (fonte as Dictionary)[k]


func nome_do_item(id: int) -> String:
	var e: Variant = _itens_db.get(id)
	if e is Dictionary:
		var D: Dictionary = e
		for chave: String in ["name_pt", "name_en", "nome_pt", "nome"]:
			if D.has(chave) and str(D[chave]) != "":
				return str(D[chave])
	return "item 0x%02X" % id


func abrir(qual: Tela) -> void:
	tela = qual
	sel = 0
	visible = qual != Tela.NENHUMA
	_mapa.visible = false
	if _grid != null:
		_grid.visible = qual == Tela.INVENTARIO
	match qual:
		Tela.INVENTARIO:
			_desenhar_inventario()
		Tela.MAPA:
			_desenhar_mapa()
		Tela.PAUSA:
			_desenhar_pausa()
		Tela.MENU_PRINCIPAL:
			_desenhar_menu_principal()
		_:
			fechou.emit()


func fechar() -> void:
	abrir(Tela.NENHUMA)


func aberta() -> bool:
	return tela != Tela.NENHUMA


# ─────────────────────────────── inventário ───────────────────────────────
#
# ARTE REAL do jogo, não desenho meu:
#   • moldura/chrome: `ETC/STMAIN0U.png` (a tela de status do RE3: caixas de item, EQUIP,
#     barra de `condition`) — TIM 256×272 extraído do disco;
#   • ícones: `ETC/items/NNN.png`, extraídos de `ETC/ITEMG.PIX` por `tools/item_icons.py`
#     (134 TIMs 8bpp de 112×72, passo fixo 10240 B, cor 0 = transparente). **índice = item_id**,
#     validado visualmente em 11 itens de faixas diferentes;
#   • nomes/exames: `data/re3_items.json` (tabelas do EXE + mod PT-BR).
#
# Layout: grade 2×4 (8 caixas de item) + a caixa de arma equipada, como o original. As caixas
# do STMAIN são desenhadas do próprio TIM; os ícones entram dentro delas.

const GRID_COLS := 2
const GRID_ROWS := 4
## Caixa de item no STMAIN0U (px do TIM 256×272), medida na arte: a caixa vazia de 2 slots.
const CX_CAIXA := Rect2(129.0, 4.0, 60.0, 56.0)


func _desenhar_inventario() -> void:
	_titulo.text = ""
	_corpo.text = ""
	_rodape.text = ""
	_mapa.visible = false
	_montar_grid()
	if state == null:
		return
	var n := 0
	for i in GameState.MAIN_SLOTS:
		if int((state.main_slots[i] as Dictionary).get("id", 0)) != 0:
			n += 1
	var atual: Dictionary = state.main_slots[sel]
	var id := int(atual.get("id", 0))
	_nome.text = nome_do_item(id) if id != 0 else ""
	_exame.text = exame_do_item(id) if id != 0 else ""
	_rodape.text = "%d/%d itens · setas navegam · I/ESC fecha" % [n, GameState.MAIN_SLOTS]


var _grid: Control
var _nome: Label
var _exame: RichTextLabel
var _chrome: TextureRect
var _celulas: Array[TextureRect] = []
var _molduras: Array[Panel] = []


func _montar_grid() -> void:
	if _grid == null:
		_grid = Control.new()
		_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
		_raiz.add_child(_grid)
		# chrome do jogo ao fundo, escalado 4× (256×272 -> 1024×1088, recortado na altura)
		# PAINEL DE STATUS do jogo (EQUIP + condition), à direita, na proporção do TIM.
		# COLUNA DE STATUS do TIM (x 128..256): EQUIP, `condition`, caixas. O bloco cinza à
		# esquerda do TIM é onde o original desenha o personagem 3D — fora do recorte.
		# `AtlasTexture` porque `region_enabled` é de Sprite2D, não de TextureRect.
		_chrome = TextureRect.new()
		var base := AssetIO.texture("ETC/STMAIN0U.png")
		if base != null:
			var at := AtlasTexture.new()
			at.atlas = base
			at.region = Rect2(128.0, 0.0, 128.0, 272.0)
			_chrome.texture = at
		_chrome.position = Vector2(840.0, 40.0)
		_chrome.scale = Vector2(3.3, 3.3)
		_chrome.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_grid.add_child(_chrome)
		_nome = Label.new()
		_nome.position = Vector2(150, 730)
		_nome.add_theme_font_size_override("font_size", 36)
		_nome.add_theme_color_override("font_color", COR_TEXTO)
		_grid.add_child(_nome)
		_exame = RichTextLabel.new()
		_exame.position = Vector2(150, 785)
		_exame.size = Vector2(470, 150)
		_exame.add_theme_font_size_override("normal_font_size", 22)
		_exame.add_theme_color_override("default_color", Color(0.8, 0.8, 0.75))
		_grid.add_child(_exame)
		for i in GameState.MAIN_SLOTS:
			var m := Panel.new()
			var est := StyleBoxFlat.new()
			est.bg_color = Color(0.06, 0.07, 0.10, 0.75)
			est.border_color = COR_BORDA
			est.set_border_width_all(2)
			m.add_theme_stylebox_override("panel", est)
			_grid.add_child(m)
			_molduras.append(m)
			var c := TextureRect.new()
			c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_grid.add_child(c)
			_celulas.append(c)
	_grid.visible = true
	# posiciona a grade 2×4 (as duas últimas linhas dos 10 slots ficam na 5ª/6ª fileira)
	var largura := 200.0
	var altura := 122.0
	var x0 := 150.0
	var y0 := 90.0
	for i in GameState.MAIN_SLOTS:
		var col := i % GRID_COLS
		var lin := i / GRID_COLS
		var pos := Vector2(x0 + float(col) * (largura + 16.0), y0 + float(lin) * (altura + 12.0))
		_molduras[i].position = pos
		_molduras[i].size = Vector2(largura, altura)
		var est: StyleBoxFlat = _molduras[i].get_theme_stylebox("panel")
		est.border_color = COR_SEL if i == sel else COR_BORDA
		est.set_border_width_all(4 if i == sel else 2)
		_celulas[i].position = pos + Vector2(8, 8)
		_celulas[i].size = Vector2(largura - 16.0, altura - 16.0)
		var id := int((state.main_slots[i] as Dictionary).get("id", 0)) if state != null else 0
		_celulas[i].texture = icone_do_item(id)
		_celulas[i].visible = id != 0


func icone_do_item(id: int) -> Texture2D:
	## Ícone extraído do `ITEMG.PIX` — índice = item_id.
	if id <= 0:
		return null
	if _icones.has(id):
		return _icones[id]
	var t := AssetIO.texture("ETC/items/%03d.png" % id)
	_icones[id] = t
	return t


var _icones: Dictionary = {}


func exame_do_item(id: int) -> String:
	var e: Variant = _itens_db.get(id)
	if e is Dictionary:
		for chave: String in ["exam_pt", "desc_pt", "exam_en", "desc_en"]:
			if (e as Dictionary).has(chave):
				return str((e as Dictionary)[chave])
	return ""


# ─────────────────────────────── mapa ───────────────────────────────

func _desenhar_mapa() -> void:
	_titulo.text = "MAPA"
	var stage := state.stage if state != null else 1
	# `assets/MAP/` tem as telas do MAP_U por índice; tenta a do stage atual e cai para a 0.
	var tex: Texture2D = _tex_do_mapa(stage)
	if tex != null:
		_mapa.texture = tex
		_mapa.visible = true
		_corpo.text = ""
	else:
		_corpo.text = "Sem tela de mapa em assets/MAP/ (rode a etapa `maps` do build_assets)."
	var sala := mundo.room.room_id if mundo != null and mundo.room != null else "-"
	_rodape.text = "sala %s · stage %d · M/ESC fecha" % [sala, stage]


# ─────────────────────────────── pausa ───────────────────────────────

const OPC_PAUSA: Array[String] = ["Continuar", "Salvar", "Carregar", "Menu principal"]


func _desenhar_pausa() -> void:
	_titulo.text = "PAUSA"
	var linhas: Array[String] = []
	for i in OPC_PAUSA.size():
		linhas.append("%s%s" % ["[color=#ffd83f]> [/color]" if i == sel else "   ", OPC_PAUSA[i]])
	_corpo.text = "\n\n".join(linhas)
	var sala := mundo.room.room_id if mundo != null and mundo.room != null else "-"
	_rodape.text = "sala %s · saves: %d · ↑↓ move · E/Enter confirma · ESC volta" % [
		sala, state.save_count if state != null else 0]


# ─────────────────────────────── menu principal ───────────────────────────────

const OPC_MENU: Array[String] = ["Novo jogo", "Continuar", "Sair"]


func _desenhar_menu_principal() -> void:
	_titulo.text = "RESIDENT EVIL 3: NEMESIS"
	_fundo.color = Color(0.0, 0.0, 0.0, 1.0)
	# tela de título do jogo, se a etapa `menus` já extraiu
	var t: Texture2D = _tex_titulo()
	if t != null:
		_mapa.texture = t
		_mapa.visible = true
	var linhas: Array[String] = []
	for i in OPC_MENU.size():
		linhas.append("%s%s" % ["[color=#ffd83f]> [/color]" if i == sel else "   ", OPC_MENU[i]])
	_corpo.text = "\n\n".join(linhas)
	_rodape.text = "↑↓ move · E/Enter confirma   (port 1:1 — arte do menu original é P6-01)"


func _tex_do_mapa(stage: int) -> Texture2D:
	## Telas do `MAP_U` extraídas em `assets/MAP/`: `PS1_<n>_<AREA>.png` e as HD
	## `HD_<AREA>_*.webp`. Preferência: HD da área do stage, senão a PS1 do índice.
	var dir := DirAccess.open(AssetIO.path("MAP"))
	if dir == null:
		return null
	var ps1 := ""
	var hd := ""
	var area := ""
	for f in dir.get_files():
		if f.begins_with("PS1_%d_" % stage):
			ps1 = f
			area = f.trim_prefix("PS1_%d_" % stage).trim_suffix(".png")
	for f in dir.get_files():
		if area != "" and f.begins_with("HD_%s_" % area) and hd == "":
			hd = f
	var escolha := hd if hd != "" else ps1
	return AssetIO.texture("MAP/%s" % escolha) if escolha != "" else null


func _tex_titulo() -> Texture2D:
	## Tela de título extraída pela etapa `menus`: `assets/MENU/01_title/`.
	for rel: String in ["MENU/01_title/TITLEU_00_320x240.png",
			"MENU/01_title/TITLEU_01_320x240.png", "MENU/01_title/CAPCOM_00_320x240.png"]:
		if AssetIO.exists(rel):
			var t := AssetIO.texture(rel)
			if t != null:
				return t
	return null


# ─────────────────────────────── entrada ───────────────────────────────

func mover_sel(passo: int) -> void:
	var n := 1
	match tela:
		Tela.INVENTARIO:
			n = GameState.MAIN_SLOTS
		Tela.PAUSA:
			n = OPC_PAUSA.size()
		Tela.MENU_PRINCIPAL:
			n = OPC_MENU.size()
	sel = (sel + passo + n) % n
	abrir(tela)                              ## redesenha mantendo a tela


func confirmar() -> void:
	match tela:
		Tela.PAUSA:
			match sel:
				0:
					fechar()
				1:
					if mundo != null:
						mundo.salvar("user://save0.json")
						_rodape.text = "salvo em user://save0.json"
				2:
					if mundo != null and FileAccess.file_exists("user://save0.json"):
						mundo.carregar_save("user://save0.json")
						fechar()
				3:
					abrir(Tela.MENU_PRINCIPAL)
		Tela.MENU_PRINCIPAL:
			match sel:
				0:
					pediu_novo_jogo.emit()
					fechar()
				1:
					pediu_continuar.emit()
					fechar()
				2:
					pediu_sair.emit()
		Tela.INVENTARIO:
			pass                             ## usar/combinar item: P6-04
