extends SceneTree
## CAMINHO COMPLETO: cena real (game.tscn) + TECLADO DE VERDADE via Input.parse_input_event.
## Nada de mundo.tick direto: quem avança é o Clock do autoload Game, e o Pad lê
## Input.is_key_pressed — exatamente o que roda quando o usuário joga.
##
## Fases (cada uma ~45 ticks de gameplay): W · S · A(giro)+W · D(giro)+W · I aberto+W (telas)

var _cena: Node
var _fase := -1
var _tick0 := -1
var _p0 := Vector3i.ZERO
var _ligado := false
var _frames := 0

const FASES: Array = [
	["W", [KEY_W]],
	["S", [KEY_S]],
	["A+W", [KEY_A, KEY_W]],
	["D+W", [KEY_D, KEY_W]],
	["UP(seta)", [KEY_UP]],
]


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


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	var g: Node = get_root().get_node("/root/Game")
	var clock: Node = g.get("clock")
	var pad: Object = g.get("pad")
	var mundo: Object = _cena.get("mundo")
	var pl: Object = mundo.get("player")
	var telas: Object = _cena.get("telas")
	var frame: int = clock.get("frame")

	if _fase == -1:
		print("[full] inicio: sala=%s pos=%s facing=%s telas_aberta=%s frame=%d" % [
			mundo.get("room").get("room_id"), pl.get("pos"), pl.get("facing"),
			telas.call("aberta"), frame])
		_fase = 0
		_tick0 = frame
		_p0 = pl.get("pos")
		for k: int in FASES[0][1]:
			_tecla(k, true)
		return false

	if frame - _tick0 < 45:
		return false

	# fecha a fase corrente
	for k: int in FASES[_fase][1]:
		_tecla(k, false)
	var p: Vector3i = pl.get("pos")
	var d := absi(p.x - _p0.x) + absi(p.z - _p0.z)
	print("[full] fase %-8s: %s -> %s  (%d un em %d ticks)  mask_no_fim=0x%03x telas=%s sala=%s" % [
		FASES[_fase][0], _p0, p, d, frame - _tick0, pad.get("mask"),
		telas.call("aberta"), mundo.get("room").get("room_id")])
	_fase += 1
	if _fase >= FASES.size():
		print("[full] fim")
		return true
	# reseta posição para comparar fases iguais
	pl.set("pos", Vector3i(-21820, 0, -21899))
	pl.set("facing", 0)
	_p0 = pl.get("pos")
	_tick0 = frame
	for k: int in FASES[_fase][1]:
		_tecla(k, true)
	return false
