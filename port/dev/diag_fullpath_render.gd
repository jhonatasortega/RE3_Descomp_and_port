extends SceneTree
## Igual ao diag_fullpath.gd, mas COM render: injeta W de verdade, deixa o Clock avançar,
## e salva screenshots em user:// para inspecionar o visual (modelo, câmera, HUD).

var _cena: Node
var _frames := 0
var _tick0 := -1
var _p0 := Vector3i.ZERO
var _shots := 0


func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)


func _tecla(k: Key, pressionada: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressionada
	Input.parse_input_event(e)


func _shot(nome: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("user://fullr_%s.png" % nome)
	print("[fullr] shot %s" % nome)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	var g: Node = get_root().get_node("/root/Game")
	var clock: Node = g.get("clock")
	var mundo: Object = _cena.get("mundo")
	var pl: Object = mundo.get("player")
	var frame: int = clock.get("frame")
	if _tick0 < 0:
		_tick0 = frame
		_p0 = pl.get("pos")
		print("[fullr] inicio pos=%s facing=%s frame=%d" % [_p0, pl.get("facing"), frame])
		_tecla(KEY_W, true)
		_shot("00_inicio")
		return false
	var t := frame - _tick0
	if t >= 15 and _shots == 0:
		_shots = 1
		_shot("01_w15")
		print("[fullr] t=15 pos=%s" % [pl.get("pos")])
	if t >= 40 and _shots == 1:
		_shots = 2
		_shot("02_w40")
		print("[fullr] t=40 pos=%s cam=%s" % [pl.get("pos"), mundo.get("camera")])
	if t >= 70:
		_tecla(KEY_W, false)
		var p: Vector3i = pl.get("pos")
		var d := absi(p.x - _p0.x) + absi(p.z - _p0.z)
		_shot("03_fim")
		print("[fullr] fim: %s -> %s (%d un em %d ticks)" % [_p0, p, d, t])
		return true
	return false
