extends SceneTree
## Da posição EXATA do print do usuário: W, S, A-giro e D-giro em cena real.
var _cena: Node
var _t := 0
var _fase := 0
var _p0 := Vector3i.ZERO
const FASES := ["W (frente)", "S (ré)", "giro A + W", "giro D + W"]
func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)
func _process(_d: float) -> bool:
	_t += 1
	if _t < 6:
		return false
	var mundo: Object = _cena.get("mundo")
	var pad: Object = _cena.get_node("/root/Game").get("pad")
	var pl: Object = mundo.get("player")
	if _t == 6:
		pl.set("pos", Vector3i(-21516, 0, -22004))
		pl.set("facing", 3706)
		_p0 = pl.get("pos")
	var tick_local := (_t - 6) % 30
	if tick_local < 29:
		var m := 0
		match _fase:
			0: m = 0x01                      # W
			1: m = 0x200                     # S
			2: m = 0x01 | 0x80               # W + A
			3: m = 0x01 | 0x20               # W + D
		pad.call("set_mask", m)
		mundo.call("tick", pad)
		return false
	var p: Vector3i = pl.get("pos")
	var d := absi(p.x - _p0.x) + absi(p.z - _p0.z)
	print("[dirs] %-12s: %s -> %s (%d un)" % [FASES[_fase], _p0, p, d])
	_fase += 1
	if _fase >= FASES.size():
		return true
	pl.set("pos", Vector3i(-21516, 0, -22004))
	pl.set("facing", 3706)
	_p0 = pl.get("pos")
	return false
