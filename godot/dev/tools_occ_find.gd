extends SceneTree
## Localizador rapido (sem render): imprime a posicao de TELA (px, 1280x960) da Jill para
## uma grade de posicoes PS1 na cam dada, para achar onde ela sobrepoe uma regiao de 1o
## plano. Tambem imprime a bbox das regioes de mascara (px 1280x960).
##   godot --path godot --rendering-driver opengl3 --script res://dev/tools_occ_find.gd

var _room: Node
var _wait := 0

func _initialize() -> void:
	get_root().set_size(Vector2i(1280, 960))
	_room = load("res://scenes/game_room.tscn").instantiate()
	var rm := OS.get_environment("OCC_ROOM")
	if rm != "":
		_room.room = rm
	get_root().add_child(_room)

func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 6:
		return false
	_room.auto_camera = false
	var cam := int(OS.get_environment("OCC_CAM")) if OS.get_environment("OCC_CAM") != "" else 0
	_room._show_camera(cam)
	var c3d: Camera3D = _room.cam3d
	var groups: Array = _room.cam_masks[cam] if cam < _room.cam_masks.size() else []
	var mnx := 9999.0; var mny := 9999.0; var mxx := -9999.0; var mxy := -9999.0
	for g in groups:
		for b in g.get("blocks", []):
			mnx = minf(mnx, float(b["dx"]) / 320.0 * 1280.0)
			mny = minf(mny, float(b["dy"]) / 240.0 * 960.0)
			mxx = maxf(mxx, float(b["dx"] + b["w"]) / 320.0 * 1280.0)
			mxy = maxf(mxy, float(b["dy"] + b["h"]) / 240.0 * 960.0)
	print("MASK bbox px (1280x960): (%d,%d)-(%d,%d)" % [mnx, mny, mxx, mxy])
	var y: float = _room.jill_start_ps1.y
	for zi in range(-30000, -16000, 2000):
		var line := "z=%6d:" % zi
		for xi in range(-31000, -16000, 2000):
			_room.jill.global_position = _room.ps1_to_godot(Vector3(xi, y, zi))
			if c3d.is_position_behind(_room.jill.global_position):
				line += " x%6d:OFF " % xi
			else:
				var sp := c3d.unproject_position(_room.jill.global_position)
				line += " x%6d:%4d,%4d" % [xi, int(sp.x), int(sp.y)]
		print(line)
	quit()
	return true
