extends SceneTree
func _initialize() -> void:
	var s := load("res://core/itens.gd")
	print("carregou: ", s)
	quit(0)
