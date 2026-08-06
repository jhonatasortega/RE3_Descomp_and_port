extends SceneTree
## VERIFICACAO HOSTIL do caminho completo (teclado real via Input.parse_input_event).
## Cenarios: W normal · ESC no meio do passo (pausa) com W segurado · fechar pausa e seguir ·
## todas as teclas juntas (W+S+A+D+SHIFT) · I (inventario) no meio do passo · fechar e seguir.

var _cena: Node
var _fase := -1
var _tick0 := -1
var _p0 := Vector3i.ZERO
var _frames := 0

# [nome, teclas_a_apertar(hold), teclas_toggle(press+release), ticks, resetar_pos]
const FASES: Array = [
	["W-normal",        [KEY_W], [],           20, true],
	["ESC-abre(W held)",[KEY_W], [KEY_ESCAPE], 20, false],
	["ESC-fecha(W held)",[KEY_W],[KEY_ESCAPE], 20, false],
	["solta-W",         [],      [],            2, false],
	["todas-juntas",    [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SHIFT], [], 20, true],
	["solta-todas",     [],      [],            2, false],
	["W-de-novo",       [KEY_W], [],           15, true],
	["I-abre(W held)",  [KEY_W], [KEY_I],      15, false],
	["I-fecha(W held)", [KEY_W], [KEY_I],      20, false],
]

var _seguradas: Array = []


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


func _comecar_fase(pl: Object, frame: int) -> void:
	var f: Array = FASES[_fase]
	if f[4]:
		pl.set("pos", Vector3i(-21820, 0, -21899))
		pl.set("facing", 0)
	# solta o que nao esta mais na lista de hold
	for k: int in _seguradas.duplicate():
		if not (f[1] as Array).has(k):
			_tecla(k, false)
			_seguradas.erase(k)
	for k: int in f[1]:
		if not _seguradas.has(k):
			_tecla(k, true)
			_seguradas.append(k)
	for k: int in f[2]:
		_tecla(k, true)
		_tecla(k, false)
	_tick0 = frame
	_p0 = pl.get("pos")


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
		_fase = 0
		_comecar_fase(pl, frame)
		return false

	if frame - _tick0 < (FASES[_fase][3] as int):
		return false

	var p: Vector3i = pl.get("pos")
	var d := absi(p.x - _p0.x) + absi(p.z - _p0.z)
	print("[hostil] %-18s: %s -> %s  (%d un em %d ticks)  mask=0x%03x telas=%s frame=%d" % [
		FASES[_fase][0], _p0, p, d, frame - _tick0, pad.get("mask"),
		telas.call("aberta"), frame])
	_fase += 1
	if _fase >= FASES.size():
		for k: int in _seguradas:
			_tecla(k, false)
		print("[hostil] fim")
		return true
	_comecar_fase(pl, frame)
	return false
