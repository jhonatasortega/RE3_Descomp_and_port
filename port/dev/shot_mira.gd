extends SceneTree
## Fotografa a MIRA: normal (sem laser) e fácil (com laser + auto-mira), com um alvo à frente.
## O pad entra em REPLAY segurando AIM — senão o pad real volta a zero entre os quadros e a mira cai.
var _cena: Node
var _t := 0
var _fase := 0

func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)

func _process(_d: float) -> bool:
	_t += 1
	if _t < 4:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var pad: Object = g.get("pad")
	var pl: Object = _cena.get("player")
	if _fase == 0:
		var p := pl.get("pos") as Vector3i
		var alvo := Vector3i(p.x + 700, p.y, p.z - 2200)
		pl.set("alvos", func() -> Array: return [alvo])
		var m := PackedInt32Array()
		m.resize(20000)
		m.fill(Pad.AIM)
		pad.call("load_replay", m)                 ## segura a mira em todos os quadros
		g.get("state").set("dificuldade", 1)       ## NORMAL
		for _k in 16:
			pad.call("poll")                       ## em REPLAY o mask só muda no poll
			_cena.call("_on_tick", _t)
		_fase = 1
		return false
	if _fase == 1:
		print("[mr] normal: sub=%s alvo=%s laser=%s facing=%s" % [pl.get("mira_sub"),
			pl.get("mira_alvo"), pl.call("mira_com_laser"), pl.get("facing")])
		get_root().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://_mira_normal.png"))
		g.get("state").set("dificuldade", 0)       ## FÁCIL
		for _k in 6:
			pad.call("poll")
			_cena.call("_on_tick", _t)
		_fase = 2
		return false
	if _fase == 2:
		pad.call("poll")
		_cena.call("_on_tick", _t)                 ## um quadro para o laser entrar na textura
		_fase = 3
		return false
	print("[mr] facil: sub=%s alvo=%s laser=%s facing=%s" % [pl.get("mira_sub"),
		pl.get("mira_alvo"), pl.call("mira_com_laser"), pl.get("facing")])
	get_root().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_mira_facil.png"))
	return true
