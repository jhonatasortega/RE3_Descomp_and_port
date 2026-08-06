extends SceneTree
## Por que o W "solta" no run com render? Loga mask, Input.is_key_pressed e pos a cada 10 ticks.

var _cena: Node
var _frames := 0
var _tick0 := -1
var _ultimo := -1


func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var g: Node = get_root().get_node("/root/Game")
	var clock: Node = g.get("clock")
	var pad: Object = g.get("pad")
	var mundo: Object = _cena.get("mundo")
	var pl: Object = mundo.get("player")
	var frame: int = clock.get("frame")
	if _tick0 < 0:
		_tick0 = frame
		var e := InputEventKey.new()
		e.keycode = KEY_W
		e.physical_keycode = KEY_W
		e.pressed = true
		Input.parse_input_event(e)
		return false
	var t := frame - _tick0
	if t / 10 != _ultimo:
		_ultimo = t / 10
		print("[mask] t=%3d mask=0x%03x isW=%s pos=%s cam=%s foco=%s" % [
			t, pad.get("mask"), Input.is_key_pressed(KEY_W), pl.get("pos"),
			mundo.get("camera"),
			get_root().has_focus()])
	if t >= 120:
		return true
	return false
