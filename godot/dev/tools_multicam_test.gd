extends SceneTree
## Valida a troca de camera AUTOMATICA numa sala com MUITAS cameras (R101, 28 cams).
## Anda a Jill do "auto-zona" da camera 0 para a zona da camera 12 e confirma que a
## camera troca sozinha (0 -> 12). Salva screenshots inicial e final.

var _scene: Node
var _jill
var _f := 0
var _phase := 0
var _last := -1
var _log: Array = []

const START := Vector3(-15674, -258, -19978)   # zona propria da camera 0
const GOAL := Vector3(-23472, -258, -21690)    # interior da camera 12 (look-at dela)


func _initialize() -> void:
	var packed := load("res://scenes/game_room.tscn")
	_scene = packed.instantiate()
	_scene.room = "R101"
	_scene.stage = 1
	_scene.jill_start_ps1 = START
	get_root().add_child(_scene)


func _process(_delta: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	_jill = _scene.jill
	if _phase == 0:
		_last = _scene.cam_index
		_log.append("R101 inicio: cam=%d (esperado 0)" % _scene.cam_index)
		var img := get_root().get_texture().get_image()
		img.save_png("res://mc_1_start_cam%d.png" % _scene.cam_index)
		_phase = 1
		_f = 0
		return false
	if _phase == 1:
		var t: float = clampf(_f / 40.0, 0.0, 1.0)
		var ps1 := START.lerp(GOAL, t)
		_jill.global_position = _scene.ps1_to_godot(ps1)
		if _scene.cam_index != _last:
			_log.append("t=%.2f pos=(%d,%d) -> TROCA cam %d->%d" % [t, ps1.x, ps1.z, _last, _scene.cam_index])
			_last = _scene.cam_index
		if t >= 1.0:
			var img := get_root().get_texture().get_image()
			img.save_png("res://mc_2_end_cam%d.png" % _scene.cam_index)
			_phase = 2
		return false
	print("\n=== LOG R101 ===")
	for l in _log:
		print("  ", l)
	quit()
	return true
