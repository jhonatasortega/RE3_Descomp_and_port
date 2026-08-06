extends SceneTree
## Valida a OCLUSAO por priority masks reais (room_game.gd) e o casamento de luz.
## Posiciona a Jill em coords PS1 e renderiza a mesma cena em 3 variantes:
##   _dbg  -> quads de oclusao pintados de vermelho (mostra as REGIOES de 1o plano na tela)
##   _off  -> oclusao desligada (ANTES: cenario NAO oculta a Jill)
##   _on   -> oclusao ligada   (DEPOIS: 1o plano oculta a Jill quando ela esta atras)
##
## Rodar (opengl3):
##   godot --path godot --rendering-driver opengl3 --script res://dev/tools_occlusion_val.gd
## Env:
##   OCC_ROOM=R100  OCC_CAM=0  OCC_X=-24000 OCC_Z=-20000  OCC_SCALE=0.000196
##   OCC_TAG=fusebox  (prefixo dos PNGs)  OCC_FACE=0
## Saida: res://dev/occ_<tag>_{dbg,off,on}.png

var _room: Node
var _phase := 0
var _wait := 0
var _tag := "occ"


func _envf(name: String, dflt: float) -> float:
	var s := OS.get_environment(name)
	return float(s) if s != "" else dflt


func _initialize() -> void:
	get_root().set_size(Vector2i(1280, 960))
	_room = load("res://scenes/game_room.tscn").instantiate()
	var rm := OS.get_environment("OCC_ROOM")
	if rm != "":
		_room.room = rm
	get_root().add_child(_room)
	_tag = OS.get_environment("OCC_TAG")
	if _tag == "":
		_tag = "occ"
	var sc := OS.get_environment("OCC_SCALE")
	if sc != "":
		_room.occ_depth_scale = float(sc)
	_room.auto_camera = false
	_room.collision_enabled = false


func _place() -> void:
	var x := _envf("OCC_X", _room.jill_start_ps1.x)
	var z := _envf("OCC_Z", _room.jill_start_ps1.z)
	var y := _envf("OCC_Y", _room.jill_start_ps1.y)
	_room.jill.global_position = _room.ps1_to_godot(Vector3(x, y, z))
	_room.jill.set_facing(_envf("OCC_FACE", 0.0))
	var cam := int(_envf("OCC_CAM", 0.0))
	_room._show_camera(cam)


func _snap(name: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://dev/occ_%s_%s.png" % [_tag, name]))
	print("saved occ_%s_%s.png  cam=%d" % [_tag, name, _room.cam_index])


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	match _phase:
		0:
			_place()
			_room.occlusion_enabled = true
			_room.occluder_debug = true
			_room._update_occlusion()
		1:
			_snap("dbg")
			_room.occluder_debug = false
			_room.occlusion_enabled = false
			_room._update_occlusion()
		2:
			_snap("off")
			_room.occlusion_enabled = true
			_room._update_occlusion()
		3:
			_snap("on")
		_:
			quit()
			return true
	_phase += 1
	return false
