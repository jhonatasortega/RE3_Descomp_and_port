extends SceneTree
## Render após andar: mostra para ONDE o modelo aponta versus para onde ELA SE MOVE.
var _cena: Node
var _t := 0
func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)
func _process(_d: float) -> bool:
	_t += 1
	if _t < 6:
		return false
	var mundo: Object = _cena.get("mundo")
	if _t == 6:
		print("[walk] antes: %s facing %s" % [mundo.get("player").get("pos"), mundo.get("player").get("facing")])
	if _t >= 6 and _t < 26:
		var pad: Object = _cena.get_node("/root/Game").get("pad")
		pad.call("set_mask", 0x01)      # FWD
		mundo.call("tick", pad)
		var p: Object = mundo.get("player")
		var scr: Node = _cena
		scr.call("_on_tick", _t)  # atualiza o visual
		return false
	if _t == 26:
		var p2: Object = mundo.get("player")
		print("[walk] depois: %s facing %s" % [p2.get("pos"), p2.get("facing")])
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://_shot_walk.png"))
		print("[walk] salvo _shot_walk.png")
		return true
	return false
