extends SceneTree
## Screenshot com o wireframe de colisão (VOLUMES) na posição do congelamento da R100.

var _cena: Node
var _frames := 0


func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	_cena.set("debug_collision", true)
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_frames += 1
	var mundo: Object = _cena.get("mundo")
	var pl: Object = mundo.get("player")
	if _frames == 5:
		pl.set("pos", Vector3i(-23217, 0, -26636))
	if _frames < 40:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png("user://overlay_freeze.png")
	print("[ov] pos=%s cam=%s shot salvo" % [pl.get("pos"), mundo.get("camera")])
	return true
