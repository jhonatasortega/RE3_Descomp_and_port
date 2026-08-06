extends SceneTree
## Diagnostico de ALINHAMENTO camera 3D <-> background 2D do game_room.
##
## Para CADA camera: posiciona a Jill no XZ do ALVO (look-at 'to') sobre o chao e
## renderiza o COMPOSTO (bg + Jill 3D). Como a camera OLHA para 'to', o XZ de 'to'
## projeta no CENTRO horizontal da tela -> a Jill deve aparecer centralizada. Se sair
## do centro, a projecao (fov/from/to) nao casa com o background daquela camera.
##
## Rodar:
##   godot --path godot --rendering-driver opengl3 --script res://dev/tools_cam_align.gd
## Saida: res://dev/cam_align_<i>.png

var _room: Node
var _n := 0
var _i := 0
var _wait := 0
var _phase := 0


func _initialize() -> void:
	get_root().set_size(Vector2i(1280, 960))
	var packed: PackedScene = load("res://scenes/game_room.tscn")
	_room = packed.instantiate()
	get_root().add_child(_room)


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 6:
		return false
	var cams: Array = _room.cameras
	if _n == 0:
		_n = cams.size()
	if _phase == 0:
		if _i >= _n:
			print("DONE")
			quit()
			return true
		# posiciona a Jill no XZ do alvo da camera i, sobre o chao
		var c: Dictionary = cams[_i]
		var to_a = c.get("to", [0, 0, 0])
		var ps1 := Vector3(float(to_a[0]), float(to_a[1]), float(to_a[2]))
		# chao: usa o Y de partida da sala (jill_start_ps1.y)
		ps1.y = _room.jill_start_ps1.y
		_room.jill.global_position = _room.ps1_to_godot(ps1)
		_room.auto_camera = false
		_room._show_camera(_i)
		_phase = 1
		_wait = 0
		return false
	else:
		# captura o composto (root = bg 2D + SubViewport 3D)
		var img := get_root().get_texture().get_image()
		var p := "res://dev/cam_align_%d.png" % _i
		img.save_png(ProjectSettings.globalize_path(p))
		print("SHOT cam", _i, " to_xz projetado deve estar no centro")
		_i += 1
		_phase = 0
		_wait = 0
		return false
