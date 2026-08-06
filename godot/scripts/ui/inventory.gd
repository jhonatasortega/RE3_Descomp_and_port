extends CanvasLayer
## Inventario AUTENTICO do Resident Evil 3 (tela de STATUS em pausa).
##
## Reproduz a tela original: painel de status a esquerda (retrato da Jill,
## "condition" com ECG e estado FINE/CAUTION/DANGER, arma EQUIPada + municao) e
## a GRADE de itens 2x4 a direita, com icones HD reais. Ao selecionar um item
## abre o submenu USE / COMBINE / CHECK (e EQUIP para armas) e a linha de
## descricao embaixo. Suporta PT-BR / EN via LangManager.
##
## Assets (identificados por engenharia reversa de render, ver docs/godot_ui.md):
##   res://assets/UI/frame/*  -> pecas do frame metalico do RE3 (STMAIN0U.png)
##   res://assets/UI/text/*   -> palavras do atlas STMOJIU (Fine/Caution/... , verbos)
##   res://assets/UI/item/*   -> icones HD do Seamless HD Project (hires/item)
##   res://data/re3_items.json -> nomes/descricoes PT/EN + loadout inicial
##
## Abre/fecha com I ou TAB (ESC fecha). Pausa o jogo enquanto aberto.
## Registrar como autoload "Inventory" (scenes/ui/inventory.tscn).

const ITEMS_DB := "res://data/re3_items.json"
const FRAME_DIR := "res://assets/UI/frame/"
const TEXT_DIR := "res://assets/UI/text/"
const ITEM_DIR := "res://assets/UI/item/"

const S := 4.0                 # escala (RE3 nativo 320x240 -> 1280x960)
const GRID_COLS := 2
const GRID_ROWS := 4
const NAVY := Color(0.031, 0.0, 0.29)   # azul das caixas de item do RE3

enum Health { FINE, CAUTION, DANGER, POISON }
const COND_TEX := {
	Health.FINE:    "cond_fine",
	Health.CAUTION: "cond_caution",
	Health.DANGER:  "cond_danger",
	Health.POISON:  "cond_poison",
}
const COND_COLOR := {
	Health.FINE:    Color(0.25, 1.0, 0.35),
	Health.CAUTION: Color(1.0, 0.82, 0.15),
	Health.DANGER:  Color(1.0, 0.24, 0.20),
	Health.POISON:  Color(0.75, 0.35, 1.0),
}

var _db: Dictionary = {}
var _slots: Array = []
var _sel: int = 0
var _open: bool = false
var _in_submenu: bool = false
var _sub_index: int = 0
var _sub_actions: Array = []
var _combine_from: int = -1
var condition: int = Health.FINE
var _lang: String = "pt"

var _root: Control
var _slot_nodes: Array = []
var _cursor: Control
var _item_preview: TextureRect
var _equip_icon: TextureRect
var _equip_ammo: Label
var _cond_word: TextureRect
var _ecg: Control
var _name_lbl: Label
var _desc_lbl: Label
var _submenu: Control
var _sub_items: Array = []
var _sub_cursor: Control
var _toast: Label
var _toast_t: float = 0.0
var _ecg_phase: float = 0.0
var _slot_bg_tex: Texture2D


# ---------------------------------------------------------------- ciclo de vida
func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_slot_bg_tex = _tex(FRAME_DIR, "slot_bg")
	_lang = _detect_lang()
	_load_db()
	_build_ui()
	_refresh_all()
	var lm := get_node_or_null("/root/LangManager")
	if lm and lm.has_signal("lang_changed"):
		lm.lang_changed.connect(_on_lang_changed)


func _process(delta: float) -> void:
	if not _open:
		return
	_ecg_phase += delta * 70.0
	if _ecg:
		_ecg.queue_redraw()
	if _cursor:
		_cursor.queue_redraw()
	if _toast and _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


# ------------------------------------------------------------------- dados
func _detect_lang() -> String:
	var lm := get_node_or_null("/root/LangManager")
	if lm and "lang" in lm:
		return "pt" if String(lm.lang).begins_with("pt") else "en"
	return "pt"


func _load_db() -> void:
	_db = {}
	_slots.resize(GRID_COLS * GRID_ROWS)
	for i in _slots.size():
		_slots[i] = null
	if not FileAccess.file_exists(ITEMS_DB):
		push_warning("Inventory: %s ausente" % ITEMS_DB)
		return
	var f := FileAccess.open(ITEMS_DB, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Inventory: re3_items.json invalido")
		return
	_db = data.get("items", {})
	var loadout: Array = data.get("default_loadout", [])
	for i in mini(loadout.size(), _slots.size()):
		var e: Dictionary = loadout[i]
		_slots[i] = {
			"item": String(e.get("item", "")),
			"count": int(e.get("count", 1)),
			"ammo": int(e.get("ammo", -1)),
			"equipped": bool(e.get("equipped", false)),
		}


func _def(key: String) -> Dictionary:
	return _db.get(key, {})


func _iname(key: String) -> String:
	var d := _def(key)
	return String(d.get("name_pt" if _lang == "pt" else "name_en", key))


func _idesc(key: String) -> String:
	var d := _def(key)
	return String(d.get("desc_pt" if _lang == "pt" else "desc_en", ""))


func _icon_tex(key: String) -> Texture2D:
	var d := _def(key)
	var p := ITEM_DIR + String(d.get("icon", "")) + ".png"
	if ResourceLoader.exists(p):
		return load(p)
	return null


# --------------------------------------------------------------- construcao UI
func _tex(dir: String, name: String) -> Texture2D:
	var p := dir + name + ".png"
	return load(p) if ResourceLoader.exists(p) else null


func _px(v: float) -> float:
	return v * S


func _navy_bg(parent: Control, rect: Rect2) -> void:
	# fundo azul-marinho (mesmo gradiente do fundo dos icones HD) para casar as bordas.
	var tr := TextureRect.new()
	tr.texture = _slot_bg_tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = rect.position
	tr.size = rect.size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _slot_bg_tex == null:
		var cr := ColorRect.new()
		cr.color = NAVY
		cr.position = rect.position
		cr.size = rect.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cr)
		return
	parent.add_child(tr)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.05, 0.98)
	_root.add_child(bg)
	var top := ColorRect.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = _px(6)
	top.color = Color(0.10, 0.13, 0.18, 1.0)
	_root.add_child(top)

	# ---- Painel de status (esquerda) ----
	# item_box: previa grande do item selecionado (fundo navy dentro da moldura).
	var ibox := _add_frame("item_box", Vector2(8, 10), Vector2(60, 54))
	_navy_bg(ibox, Rect2(Vector2(_px(4), _px(11)), Vector2(_px(52), _px(41))))
	_item_preview = TextureRect.new()
	_item_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_preview.position = Vector2(_px(4), _px(11))
	_item_preview.size = Vector2(_px(52), _px(41))
	_item_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ibox.add_child(_item_preview)

	# equip_box: arma equipada + municao ("EQUIP" ja vem no frame).
	var ebox := _add_frame("equip_box", Vector2(72, 10), Vector2(52, 54))
	_navy_bg(ebox, Rect2(Vector2(_px(4), _px(13)), Vector2(_px(44), _px(31))))
	_equip_icon = TextureRect.new()
	_equip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_equip_icon.position = Vector2(_px(4), _px(13))
	_equip_icon.size = Vector2(_px(44), _px(31))
	_equip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebox.add_child(_equip_icon)
	_equip_ammo = _mk_label("", 24, Color(1, 1, 1))
	_equip_ammo.position = Vector2(_px(2), _px(43))
	_equip_ammo.size = Vector2(_px(46), _px(11))
	_equip_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ebox.add_child(_equip_ammo)

	# condition + ECG.
	var cbox := _add_frame("cond_ecg", Vector2(8, 70), Vector2(118, 46))
	_cond_word = TextureRect.new()
	_cond_word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cond_word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cond_word.position = Vector2(118.0 * S * (50.0 / 93.0), 46.0 * S * (2.0 / 58.0))
	_cond_word.size = Vector2(118.0 * S * (40.0 / 93.0), 46.0 * S * (13.0 / 58.0))
	_cond_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(_cond_word)
	_ecg = Control.new()
	_ecg.position = Vector2(118.0 * S * (4.0 / 93.0), 46.0 * S * (20.0 / 58.0))
	_ecg.size = Vector2(118.0 * S * (80.0 / 93.0), 46.0 * S * (32.0 / 58.0))
	_ecg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(_ecg)
	_ecg.draw.connect(_on_ecg_draw)

	# retrato da Jill.
	_add_frame("portrait_jill", Vector2(8, 120), Vector2(46, 74))

	var who := _mk_label("JILL", 24, Color(0.85, 0.9, 1.0))
	who.position = Vector2(_px(60), _px(126))
	who.size = Vector2(_px(70), _px(12))
	_root.add_child(who)

	# hint de teclas no canto superior direito (nao conflita com a descricao).
	var hint := _mk_label("", 18, Color(0.5, 0.58, 0.66))
	hint.position = Vector2(_px(150), _px(2))
	hint.size = Vector2(_px(162), _px(10))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.name = "Hint"
	_root.add_child(hint)

	# ---- Grade de itens (direita) ----
	var gx := 150.0
	var gy := 14.0
	var cw := 79.0
	var ch := 44.0
	for i in _slots.size():
		var col := i % GRID_COLS
		var row := int(i / GRID_COLS)
		var panel := Panel.new()
		panel.position = Vector2(_px(gx + col * cw), _px(gy + row * ch))
		panel.size = Vector2(_px(cw - 3), _px(ch - 3))
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = Color(0, 0, 0, 0)
		sb_n.border_color = Color(0.34, 0.38, 0.45)
		sb_n.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", sb_n)
		_root.add_child(panel)

		# fundo navy (casa com o fundo dos icones -> sem barras visiveis).
		_navy_bg(panel, Rect2(Vector2(_px(2), _px(2)), panel.size - Vector2(_px(4), _px(4))))

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = _px(2)
		icon.offset_top = _px(2)
		icon.offset_right = -_px(2)
		icon.offset_bottom = -_px(2)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)

		var qty := _mk_label("", 26, Color(0.9, 1.0, 0.9))
		qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.offset_left = -_px(34)
		qty.offset_top = -_px(17)
		qty.offset_right = -_px(3)
		qty.offset_bottom = -_px(1)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		panel.add_child(qty)

		_slot_nodes.append({"panel": panel, "icon": icon, "qty": qty})

	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cursor)
	_cursor.draw.connect(_on_cursor_draw)

	# ---- Barra de descricao (rodape) ----
	var dbar := Panel.new()
	dbar.position = Vector2(_px(8), _px(200))
	dbar.size = Vector2(_px(304), _px(34))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.09, 0.92)
	sb.border_color = Color(0.3, 0.34, 0.42)
	sb.set_border_width_all(2)
	dbar.add_theme_stylebox_override("panel", sb)
	dbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dbar)
	_name_lbl = _mk_label("", 28, Color(1.0, 0.95, 0.8))
	_name_lbl.position = Vector2(_px(6), _px(2))
	_name_lbl.size = Vector2(_px(292), _px(13))
	dbar.add_child(_name_lbl)
	_desc_lbl = _mk_label("", 20, Color(0.82, 0.86, 0.9))
	_desc_lbl.position = Vector2(_px(6), _px(16))
	_desc_lbl.size = Vector2(_px(292), _px(17))
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbar.add_child(_desc_lbl)

	# ---- Submenu de acoes ----
	_submenu = Control.new()
	_submenu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_submenu.visible = false
	_root.add_child(_submenu)

	# ---- Toast ----
	_toast = _mk_label("", 24, Color(1, 1, 0.6))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = _px(52)
	_toast.offset_left = -_px(150)
	_toast.offset_right = _px(150)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_root.add_child(_toast)


func _add_frame(name: String, vpos: Vector2, vsize: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _tex(FRAME_DIR, name)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = vpos * S
	tr.size = vsize * S
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tr)
	return tr


func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------- refresh
func _refresh_all() -> void:
	_refresh_grid()
	_refresh_status()
	_refresh_selection()
	var hint := _root.get_node_or_null("Hint") as Label
	if hint:
		if _lang == "pt":
			hint.text = "setas mover  Enter acao  Tab/Esc fechar  L idioma"
		else:
			hint.text = "arrows move  Enter action  Tab/Esc close  L lang"


func _refresh_grid() -> void:
	for i in _slot_nodes.size():
		var s = _slots[i]
		var icon: TextureRect = _slot_nodes[i]["icon"]
		var qty: Label = _slot_nodes[i]["qty"]
		if s == null:
			icon.texture = null
			qty.text = ""
			continue
		icon.texture = _icon_tex(s["item"])
		var d := _def(s["item"])
		var t := String(d.get("type", ""))
		if t == "weapon":
			qty.text = str(s["ammo"]) if int(s["ammo"]) >= 0 else ""
		elif int(s["count"]) > 1:
			qty.text = str(s["count"])
		else:
			qty.text = ""


func _refresh_status() -> void:
	_cond_word.texture = _tex(TEXT_DIR, String(COND_TEX[condition]))
	_cond_word.modulate = COND_COLOR[condition]
	var eq := _find_equipped()
	if eq >= 0:
		var s = _slots[eq]
		_equip_icon.texture = _icon_tex(s["item"])
		_equip_ammo.text = str(s["ammo"]) if int(s["ammo"]) >= 0 else ""
	else:
		_equip_icon.texture = null
		_equip_ammo.text = ""


func _find_equipped() -> int:
	for i in _slots.size():
		if _slots[i] != null and bool(_slots[i].get("equipped", false)):
			return i
	return -1


func _refresh_selection() -> void:
	for i in _slot_nodes.size():
		var panel: Panel = _slot_nodes[i]["panel"]
		var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = Color(0.34, 0.38, 0.45)
	if _cursor:
		_cursor.queue_redraw()
	var s = _slots[_sel]
	if s == null:
		_item_preview.texture = null
		_name_lbl.text = ""
		_desc_lbl.text = ""
	else:
		_item_preview.texture = _icon_tex(s["item"])
		_name_lbl.text = _iname(s["item"])
		_desc_lbl.text = _idesc(s["item"])


func _on_cursor_draw() -> void:
	if _slot_nodes.is_empty():
		return
	var panel: Panel = _slot_nodes[_sel]["panel"]
	var r := Rect2(panel.position, panel.size)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 130.0)
	var col := Color(1.0, 0.88, 0.30, pulse)
	if _combine_from == _sel:
		col = Color(0.4, 0.8, 1.0, 1.0)
	_cursor.draw_rect(r.grow(1.0), col, false, 4.0)


func _on_ecg_draw() -> void:
	var sz := _ecg.size
	if sz.x <= 1 or sz.y <= 1:
		return
	var col: Color = COND_COLOR[condition]
	var mid := sz.y * 0.5
	var pts := PackedVector2Array()
	var period := 1.1
	match condition:
		Health.DANGER: period = 0.55
		Health.CAUTION: period = 0.8
		Health.POISON: period = 0.7
	var x := 0.0
	while x <= sz.x:
		var t: float = fmod((x + _ecg_phase) / sz.x, 1.0)
		pts.push_back(Vector2(x, mid - _ecg_wave(t) * (sz.y * 0.42)))
		x += 2.0
	if pts.size() >= 2:
		_ecg.draw_polyline(pts, col, 2.0, true)


func _ecg_wave(t: float) -> float:
	if t < 0.10:
		return 0.18 * sin(t / 0.10 * PI)
	elif t < 0.16:
		return -0.15 * ((t - 0.10) / 0.06)
	elif t < 0.20:
		return 1.0 * ((t - 0.16) / 0.04)
	elif t < 0.26:
		return 1.0 - 1.35 * ((t - 0.20) / 0.06)
	elif t < 0.30:
		return -0.35 + 0.35 * ((t - 0.26) / 0.04)
	elif t < 0.48:
		return 0.28 * sin((t - 0.30) / 0.18 * PI)
	return 0.0


# ------------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.keycode
	if not _open:
		if k == KEY_I or k == KEY_TAB:
			set_open(true)
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	if k == KEY_L:
		_toggle_lang()
		return
	if _in_submenu:
		_submenu_input(k)
		return
	match k:
		KEY_I, KEY_TAB, KEY_ESCAPE:
			set_open(false)
		KEY_LEFT, KEY_A:
			_move_sel(-1, 0)
		KEY_RIGHT, KEY_D:
			_move_sel(1, 0)
		KEY_UP, KEY_W:
			_move_sel(0, -1)
		KEY_DOWN, KEY_S:
			_move_sel(0, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate_selection()


func _move_sel(dx: int, dy: int) -> void:
	var col := _sel % GRID_COLS
	var row := int(_sel / GRID_COLS)
	col = clampi(col + dx, 0, GRID_COLS - 1)
	row = clampi(row + dy, 0, GRID_ROWS - 1)
	_sel = row * GRID_COLS + col
	_refresh_selection()


func _activate_selection() -> void:
	if _slots[_sel] == null:
		return
	if _combine_from >= 0:
		_do_combine(_combine_from, _sel)
		_combine_from = -1
		_refresh_all()
		return
	_open_submenu()


# ------------------------------------------------------------------- submenu
func _open_submenu() -> void:
	var s = _slots[_sel]
	if s == null:
		return
	var d := _def(s["item"])
	var t := String(d.get("type", ""))
	_sub_actions = []
	if t == "weapon":
		_sub_actions.append("equip")
	if t == "recovery":
		_sub_actions.append("use")
	_sub_actions.append("combine")
	_sub_actions.append("check")
	_in_submenu = true
	_sub_index = 0
	_build_submenu()


func _build_submenu() -> void:
	for c in _submenu.get_children():
		c.queue_free()
	_sub_items = []
	var panel := _slot_nodes[_sel]["panel"] as Panel
	var base := panel.position + Vector2(panel.size.x + _px(6), 0)
	if base.x > _px(276):
		base.x = panel.position.x - _px(66)
	var bg := Panel.new()
	bg.position = base
	bg.size = Vector2(_px(66), _px(15 * _sub_actions.size() + 6))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.97)
	sb.border_color = Color(0.55, 0.6, 0.68)
	sb.set_border_width_all(2)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_submenu.add_child(bg)
	for i in _sub_actions.size():
		var tr := TextureRect.new()
		tr.texture = _tex(TEXT_DIR, "verb_" + String(_sub_actions[i]))
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.position = Vector2(_px(12), _px(4 + i * 15))
		tr.size = Vector2(_px(50), _px(13))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(tr)
		_sub_items.append(tr)
	_sub_cursor = Control.new()
	_sub_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_sub_cursor)
	_sub_cursor.draw.connect(_on_subcursor_draw)
	_submenu.visible = true
	_refresh_submenu()


func _refresh_submenu() -> void:
	for i in _sub_items.size():
		(_sub_items[i] as TextureRect).modulate = Color(1, 1, 1) if i == _sub_index else Color(0.5, 0.53, 0.58)
	if _sub_cursor:
		_sub_cursor.queue_redraw()


func _on_subcursor_draw() -> void:
	if _sub_items.is_empty():
		return
	var tr := _sub_items[_sub_index] as TextureRect
	var pt := tr.position + Vector2(-_px(4), tr.size.y * 0.5)
	var col := Color(1.0, 0.9, 0.35)
	_sub_cursor.draw_colored_polygon(PackedVector2Array([
		pt, pt + Vector2(-_px(6), -_px(5)), pt + Vector2(-_px(6), _px(5))
	]), col)


func _submenu_input(k: int) -> void:
	match k:
		KEY_UP, KEY_W:
			_sub_index = (_sub_index - 1 + _sub_actions.size()) % _sub_actions.size()
			_refresh_submenu()
		KEY_DOWN, KEY_S:
			_sub_index = (_sub_index + 1) % _sub_actions.size()
			_refresh_submenu()
		KEY_ESCAPE, KEY_BACKSPACE:
			_close_submenu()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm_action(String(_sub_actions[_sub_index]))


func _close_submenu() -> void:
	_in_submenu = false
	_submenu.visible = false


func _confirm_action(action: String) -> void:
	var s = _slots[_sel]
	match action:
		"check":
			_desc_lbl.text = _idesc(s["item"])
			_show_toast(("Examinar: " if _lang == "pt" else "Examine: ") + _iname(s["item"]))
			_close_submenu()
		"equip":
			for i in _slots.size():
				if _slots[i] != null:
					_slots[i]["equipped"] = false
			s["equipped"] = true
			_refresh_status()
			_show_toast(("Equipado: " if _lang == "pt" else "Equipped: ") + _iname(s["item"]))
			_close_submenu()
		"use":
			_show_toast(("Usar (placeholder): " if _lang == "pt" else "Use (placeholder): ") + _iname(s["item"]))
			_close_submenu()
		"combine":
			_combine_from = _sel
			_close_submenu()
			_show_toast("Combinar com... (selecione outro item)" if _lang == "pt" else "Combine with... (pick another item)")
			_refresh_selection()


func _do_combine(a: int, b: int) -> void:
	if a == b:
		return
	var ka := String(_slots[a]["item"])
	var kb := String(_slots[b]["item"])
	var res := _herb_combine(ka, kb)
	if res != "":
		_slots[a] = {"item": res, "count": 1, "ammo": -1, "equipped": false}
		_slots[b] = null
		_show_toast(("Combinado -> " if _lang == "pt" else "Combined -> ") + _iname(res))
	else:
		_show_toast("Nao e possivel combinar" if _lang == "pt" else "Cannot combine")


func _herb_combine(a: String, b: String) -> String:
	var set := [a, b]
	set.sort()
	var key := "|".join(set)
	var table := {
		"green_herb|green_herb": "mixed_herb_gg",
		"green_herb|red_herb": "mixed_herb_gr",
		"blue_herb|green_herb": "mixed_herb_gb",
		"green_herb|mixed_herb_gb": "mixed_herb_grb",
		"blue_herb|mixed_herb_gr": "mixed_herb_grb",
	}
	return String(table.get(key, ""))


# ------------------------------------------------------------------- API
func set_open(v: bool) -> void:
	_open = v
	visible = v
	get_tree().paused = v
	if v:
		_in_submenu = false
		_combine_from = -1
		if _submenu:
			_submenu.visible = false
		_refresh_all()


func toggle() -> void:
	set_open(not _open)


func is_open() -> bool:
	return _open


func set_condition(c: int) -> void:
	condition = clampi(c, Health.FINE, Health.POISON)
	_refresh_status()


## Info da arma equipada para o HUD in-game: {name, ammo, icon} ou vazio.
func get_equipped_info() -> Dictionary:
	var eq := _find_equipped()
	if eq < 0:
		return {}
	var s = _slots[eq]
	return {
		"name": _iname(s["item"]),
		"ammo": int(s["ammo"]),
		"icon": _icon_tex(s["item"]),
	}


func _show_toast(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 1.8


# ------------------------------------------------------------------- idioma
func _toggle_lang() -> void:
	var lm := get_node_or_null("/root/LangManager")
	if lm and lm.has_method("toggle_lang"):
		lm.toggle_lang()
	else:
		_lang = "en" if _lang == "pt" else "pt"
		_refresh_all()


func _on_lang_changed(new_lang: String) -> void:
	_lang = "pt" if String(new_lang).begins_with("pt") else "en"
	_refresh_all()
