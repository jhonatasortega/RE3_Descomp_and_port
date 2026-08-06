extends CanvasLayer
## HUD in-game estilo Resident Evil classico.
## - "Eletrocardiograma" (linha de batimento animada) no canto da tela.
## - Estado de saude FINE / CAUTION / DANGER (verde / amarelo / vermelho).
##   Por ora o estado e um placeholder (FINE); use set_state() para mudar.
## - Indicador de idioma de voz + tecla L para ciclar (via LangManager).
##
## Registrado como AUTOLOAD (scenes/hud.tscn) -> aparece sobre qualquer cena
## sem precisar editar game_room.tscn / room_game.gd.

enum Health { FINE, CAUTION, DANGER }

const STATE_INFO := {
	Health.FINE:    {"label": "FINE",    "color": Color(0.2, 1.0, 0.35)},
	Health.CAUTION: {"label": "CAUTION", "color": Color(1.0, 0.82, 0.15)},
	Health.DANGER:  {"label": "DANGER",  "color": Color(1.0, 0.2, 0.2)},
}

# Idioma de demonstracao: cena de voz tocada ao trocar de idioma (existe em en e ptbr).
const DEMO_VOICE := "m101a010"

var state: int = Health.FINE
var _phase: float = 0.0          # avanco horizontal da varredura do ECG
var _beat_time: float = 0.0      # tempo desde o ultimo pico
var _ecg: Control
var _state_label: Label
var _lang_label: Label
var _toast: Label
var _toast_time: float = 0.0


func _ready() -> void:
	layer = 20
	_ecg = get_node_or_null("Root/StatusBox/VBox/EcgView")
	_state_label = get_node_or_null("Root/StatusBox/VBox/StateLabel")
	_lang_label = get_node_or_null("Root/LangBox/LangLabel")
	_toast = get_node_or_null("Root/Toast")
	if _ecg:
		_ecg.draw.connect(_on_ecg_draw)
	_refresh_state()
	_refresh_lang()
	if _toast:
		_toast.visible = false
	# Reflete trocas de idioma feitas por outros lugares.
	if Engine.has_singleton("LangManager") or get_node_or_null("/root/LangManager"):
		var lm := get_node_or_null("/root/LangManager")
		if lm and lm.has_signal("lang_changed"):
			lm.lang_changed.connect(_on_lang_changed)


func _process(delta: float) -> void:
	_phase += delta * 90.0        # velocidade da varredura (px/s)
	_beat_time += delta
	var period := _state_period()
	if _beat_time >= period:
		_beat_time = 0.0
	if _ecg:
		_ecg.queue_redraw()
	if _toast and _toast.visible:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
		if _toast_time <= 0.0:
			_toast.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_cycle_language()


# ---------------------------------------------------------------- API publica
func set_state(new_state: int) -> void:
	state = clampi(new_state, Health.FINE, Health.DANGER)
	_refresh_state()


# --------------------------------------------------------------------- idioma
func _cycle_language() -> void:
	var lm := get_node_or_null("/root/LangManager")
	if lm == null:
		_show_toast("LangManager ausente")
		return
	var new_lang: String = lm.toggle_lang()
	_show_toast("Voz: %s" % new_lang.to_upper())
	# Demonstra a nova voz (se a faixa existir).
	if lm.has_method("play_voice"):
		lm.play_voice(DEMO_VOICE)


func _on_lang_changed(_new_lang: String) -> void:
	_refresh_lang()


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
	_toast_time = 1.6


# ---------------------------------------------------------------- estado/ECG
func _refresh_state() -> void:
	var info: Dictionary = STATE_INFO[state]
	if _state_label:
		_state_label.text = info["label"]
		_state_label.add_theme_color_override("font_color", info["color"])


func _state_period() -> float:
	# Batimento mais rapido quanto pior o estado.
	match state:
		Health.DANGER:  return 0.55
		Health.CAUTION: return 0.85
		_:              return 1.15


func _on_ecg_draw() -> void:
	if _ecg == null:
		return
	var size := _ecg.size
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var col: Color = STATE_INFO[state]["color"]
	var mid := size.y * 0.5

	# Trilho de fundo (grade escura).
	_ecg.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55), true)
	_ecg.draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(col, 0.18), 1.0)

	# Constroi a forma de onda do batimento ao longo da largura.
	var pts := PackedVector2Array()
	var step := 2.0
	var period := _state_period()
	var x := 0.0
	while x <= size.x:
		# progresso 0..1 do batimento nessa coluna (com varredura _phase).
		var t: float = fmod((x + _phase) / size.x + _beat_time / period, 1.0)
		pts.push_back(Vector2(x, mid - _ecg_wave(t) * (size.y * 0.42)))
		x += step

	if pts.size() >= 2:
		_ecg.draw_polyline(pts, col, 2.0, true)
	# Ponto brilhante na "cabeca" da varredura.
	var head_x: float = fmod(_phase, size.x)
	var ht: float = fmod(head_x / size.x + _beat_time / period, 1.0)
	var head := Vector2(head_x, mid - _ecg_wave(ht) * (size.y * 0.42))
	_ecg.draw_circle(head, 2.5, Color(1, 1, 1, 0.9))


## Forma de onda de um batimento cardiaco (P-QRS-T simplificado). Retorna -1..1.
func _ecg_wave(t: float) -> float:
	# t: 0..1 dentro de um ciclo.
	if t < 0.10:
		return 0.18 * sin(t / 0.10 * PI)          # onda P
	elif t < 0.16:
		return -0.15 * ((t - 0.10) / 0.06)         # queda Q
	elif t < 0.20:
		return 1.0 * ((t - 0.16) / 0.04)           # pico R (subida)
	elif t < 0.26:
		return 1.0 - 1.35 * ((t - 0.20) / 0.06)    # R->S (descida)
	elif t < 0.30:
		return -0.35 + 0.35 * ((t - 0.26) / 0.04)  # volta ao zero
	elif t < 0.48:
		return 0.28 * sin((t - 0.30) / 0.18 * PI)  # onda T
	else:
		return 0.0                                  # linha de base
