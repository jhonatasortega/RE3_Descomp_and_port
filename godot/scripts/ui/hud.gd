extends CanvasLayer
## HUD in-game estilo Resident Evil 3.
## - Canto inferior esquerdo: display "condition" com ECG animado + estado
##   FINE / CAUTION / DANGER / POISON (palavra autentica do atlas STMOJIU, tintada).
## - Canto inferior direito: arma EQUIPada (icone HD) + municao, lida do autoload
##   Inventory (get_equipped_info()).
## - Canto superior direito: indicador de idioma da voz + tecla L (via LangManager).
##
## Construido em codigo. Registrar como autoload "HUD" (scenes/ui/hud.tscn).

const FRAME_DIR := "res://assets/UI/frame/"
const TEXT_DIR := "res://assets/UI/text/"

enum Health { FINE, CAUTION, DANGER, POISON }
const COND_TEX := {
	Health.FINE: "cond_fine", Health.CAUTION: "cond_caution",
	Health.DANGER: "cond_danger", Health.POISON: "cond_poison",
}
const COND_COLOR := {
	Health.FINE:    Color(0.25, 1.0, 0.35),
	Health.CAUTION: Color(1.0, 0.82, 0.15),
	Health.DANGER:  Color(1.0, 0.24, 0.20),
	Health.POISON:  Color(0.75, 0.35, 1.0),
}
const DEMO_VOICE := "m101a010"

var state: int = Health.FINE
var _phase: float = 0.0
var _ecg: Control
var _cond_word: TextureRect
var _weapon_icon: TextureRect
var _weapon_ammo: Label
var _lang_label: Label
var _toast: Label
var _toast_t: float = 0.0
var _root: Control


func _ready() -> void:
	layer = 20
	_build_ui()
	_refresh_state()
	_refresh_lang()
	_refresh_weapon()
	var lm := get_node_or_null("/root/LangManager")
	if lm and lm.has_signal("lang_changed"):
		lm.lang_changed.connect(func(_l): _refresh_lang())


func _process(delta: float) -> void:
	_phase += delta * 80.0
	if _ecg:
		_ecg.queue_redraw()
	_refresh_weapon()
	if _toast and _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.5, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	# esconde o HUD enquanto o inventario esta aberto.
	var inv := get_node_or_null("/root/Inventory")
	if inv and inv.has_method("is_open"):
		_root.visible = not inv.is_open()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_cycle_language()


func _tex(dir: String, name: String) -> Texture2D:
	var p := dir + name + ".png"
	return load(p) if ResourceLoader.exists(p) else null


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# ---- condition + ECG (inferior esquerdo) ----
	var cbox := TextureRect.new()
	cbox.texture = _tex(FRAME_DIR, "cond_ecg")
	cbox.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cbox.stretch_mode = TextureRect.STRETCH_SCALE
	cbox.position = Vector2(28, 780)
	cbox.size = Vector2(93 * 3, 58 * 3)
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(cbox)
	_cond_word = TextureRect.new()
	_cond_word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cond_word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cond_word.position = Vector2(93 * 3 * (50.0 / 93.0), 58 * 3 * (2.0 / 58.0))
	_cond_word.size = Vector2(93 * 3 * (40.0 / 93.0), 58 * 3 * (13.0 / 58.0))
	_cond_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(_cond_word)
	_ecg = Control.new()
	_ecg.position = Vector2(93 * 3 * (4.0 / 93.0), 58 * 3 * (20.0 / 58.0))
	_ecg.size = Vector2(93 * 3 * (80.0 / 93.0), 58 * 3 * (32.0 / 58.0))
	_ecg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(_ecg)
	_ecg.draw.connect(_on_ecg_draw)

	# ---- arma equipada (inferior direito) ----
	var ebox := TextureRect.new()
	ebox.texture = _tex(FRAME_DIR, "equip_box")
	ebox.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ebox.stretch_mode = TextureRect.STRETCH_SCALE
	ebox.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ebox.offset_left = -54 * 3 - 28
	ebox.offset_top = -61 * 3 - 24
	ebox.offset_right = -28
	ebox.offset_bottom = -24
	ebox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(ebox)
	var navy := TextureRect.new()
	navy.texture = _tex(FRAME_DIR, "slot_bg")
	navy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	navy.stretch_mode = TextureRect.STRETCH_SCALE
	navy.position = Vector2(4 * 3, 13 * 3)
	navy.size = Vector2(44 * 3, 31 * 3)
	navy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebox.add_child(navy)
	_weapon_icon = TextureRect.new()
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.position = Vector2(4 * 3, 13 * 3)
	_weapon_icon.size = Vector2(44 * 3, 31 * 3)
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ebox.add_child(_weapon_icon)
	_weapon_ammo = _mk_label("", 22, Color(1, 1, 1))
	_weapon_ammo.position = Vector2(2 * 3, 44 * 3)
	_weapon_ammo.size = Vector2(46 * 3, 12 * 3)
	_weapon_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ebox.add_child(_weapon_ammo)

	# ---- idioma (superior direito) ----
	_lang_label = _mk_label("", 20, Color(0.75, 0.85, 1.0))
	_lang_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lang_label.offset_left = -260
	_lang_label.offset_top = 16
	_lang_label.offset_right = -20
	_lang_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_lang_label)

	_toast = _mk_label("", 22, Color(1, 1, 0.6))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 48
	_toast.offset_left = -200
	_toast.offset_right = 200
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	_root.add_child(_toast)


func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- API publica
func set_state(new_state: int) -> void:
	state = clampi(new_state, Health.FINE, Health.POISON)
	_refresh_state()


func _refresh_state() -> void:
	if _cond_word:
		_cond_word.texture = _tex(TEXT_DIR, String(COND_TEX[state]))
		_cond_word.modulate = COND_COLOR[state]


func _refresh_weapon() -> void:
	if _weapon_icon == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and inv.has_method("get_equipped_info"):
		var info: Dictionary = inv.get_equipped_info()
		if not info.is_empty():
			_weapon_icon.texture = info.get("icon")
			var ammo := int(info.get("ammo", -1))
			_weapon_ammo.text = str(ammo) if ammo >= 0 else ""
			return
	_weapon_icon.texture = null
	_weapon_ammo.text = ""


# ---------------------------------------------------------------------- idioma
func _cycle_language() -> void:
	var lm := get_node_or_null("/root/LangManager")
	if lm == null:
		_show_toast("LangManager ausente")
		return
	var new_lang: String = lm.toggle_lang()
	_show_toast("Voz: %s" % new_lang.to_upper())
	if lm.has_method("play_voice"):
		lm.play_voice(DEMO_VOICE)


func _refresh_lang() -> void:
	if _lang_label == null:
		return
	var lm := get_node_or_null("/root/LangManager")
	var l := "en"
	if lm:
		l = lm.lang
	_lang_label.text = "VOICE: %s   [L]" % l.to_upper()


func _show_toast(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 1.6


# ------------------------------------------------------------------- ECG draw
func _on_ecg_draw() -> void:
	if _ecg == null:
		return
	var sz := _ecg.size
	if sz.x <= 1 or sz.y <= 1:
		return
	var col: Color = COND_COLOR[state]
	var mid := sz.y * 0.5
	_ecg.draw_line(Vector2(0, mid), Vector2(sz.x, mid), Color(col, 0.18), 1.0)
	var pts := PackedVector2Array()
	var period := _state_period()
	var x := 0.0
	while x <= sz.x:
		var t: float = fmod((x + _phase) / sz.x, 1.0)
		pts.push_back(Vector2(x, mid - _ecg_wave(t) * (sz.y * 0.42)))
		x += 2.0
	if pts.size() >= 2:
		_ecg.draw_polyline(pts, col, 2.0, true)


func _state_period() -> float:
	match state:
		Health.DANGER: return 0.55
		Health.CAUTION: return 0.85
		Health.POISON: return 0.7
		_: return 1.15


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
