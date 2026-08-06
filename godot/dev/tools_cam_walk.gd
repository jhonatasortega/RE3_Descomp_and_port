extends SceneTree
## Simula a Jill CAMINHANDO atravessando a fronteira de camera (IDA e VOLTA) e
## renderiza o composto em cada ponto, com a auto-camera (por ENQUADRAMENTO) decidindo.
## Revela se, ao transitar, ela aparece na BEIRA da tela (bug "pula pra beira") ou
## fica razoavelmente enquadrada no corte, e se ha flicker.
##
## Rodar: godot --path godot --rendering-driver opengl3 --script res://dev/tools_cam_walk.gd
## Saida: res://dev/walk_<fase>_<k>_cam<i>.png  + log "pt ... -> cam ..."
##
## Env opcional:
##   WALK_ROOM=R100         sala (default: a do game_room.tscn)
##   WALK_AXIS=x|z          eixo de caminhada (default x)
##   WALK_FROM / WALK_TO    limites PS1 no eixo (default -20000 .. -28000)
##   WALK_FIXED=-21899      coord PS1 do outro eixo (default = jill_start no eixo fixo)
##   WALK_STEPS=17          nº de pontos por fase

var _room: Node
var _pts: Array = []
var _k := 0
var _wait := 0
var _phase := 0
var _leg := 0            # 0 = ida, 1 = volta
var _prev_cam := -999
var _switches := 0


func _initialize() -> void:
	get_root().set_size(Vector2i(1280, 960))
	_room = load("res://scenes/game_room.tscn").instantiate()
	var rm := OS.get_environment("WALK_ROOM")
	if rm != "":
		_room.room = rm
	get_root().add_child(_room)
	var axis := OS.get_environment("WALK_AXIS")
	if axis == "":
		axis = "x"
	var a0 := _envf("WALK_FROM", -20000.0)
	var a1 := _envf("WALK_TO", -28000.0)
	var steps := int(_envf("WALK_STEPS", 17.0))
	var start: Vector3 = _room.jill_start_ps1
	var y: float = _envf("WALK_Y", start.y)
	var fixed_default: float = start.z if axis == "x" else start.x
	var fixed: float = _envf("WALK_FIXED", fixed_default)
	for i in range(steps):
		var t: float = float(i) / float(max(steps - 1, 1))
		var v: float = lerp(a0, a1, t)
		_pts.append(Vector3(v, y, fixed) if axis == "x" else Vector3(fixed, y, v))


func _envf(name: String, dflt: float) -> float:
	var s := OS.get_environment(name)
	return float(s) if s != "" else dflt


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 5:
		return false
	if _phase == 0:
		if _k >= _pts.size():
			if _leg == 0:
				# inicia a VOLTA: mesmos pontos ao contrario, MANTENDO a camera atual
				_pts.reverse()
				_leg = 1
				_k = 0
				_prev_cam = -999
				print("--- VOLTA ---")
			else:
				print("DONE  trocas_totais=", _switches)
				quit()
				return true
		var pt: Vector3 = _pts[_k]
		_room.jill.global_position = _room.ps1_to_godot(pt)
		_room._switch_cd = 0
		_room.auto_camera = true
		_room._update_camera_auto()
		if _prev_cam != -999 and _room.cam_index != _prev_cam:
			_switches += 1
		_prev_cam = _room.cam_index
		_phase = 1
		_wait = 0
		return false
	else:
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(
			"res://dev/walk_%d_%02d_cam%d.png" % [_leg, _k, _room.cam_index]))
		var pt: Vector3 = _pts[_k]
		print("leg ", _leg, " pt ", _k, " axis=(", int(pt.x), ",", int(pt.z), ") -> cam ", _room.cam_index)
		_k += 1
		_phase = 0
		_wait = 0
		return false
