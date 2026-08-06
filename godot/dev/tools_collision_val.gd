extends SceneTree
## Valida a COLISAO REAL de moveis (offset_table[6] do RDT) da R100, renderizando
## de verdade (opengl3). Dirige a Jill com o MESMO codigo do jogo (apply_input +
## walkable_query) contra os moveis e confirma que ela PARA na face do objeto, sem
## atravessar. Salva screenshots (antes/depois) e um log das trajetorias.
##
## Rodar:
##   GODOT --path godot --rendering-driver opengl3 --script res://tools_collision_val.gd

var _scene
var _jill
var _f := 0


func _initialize() -> void:
	var packed := load("res://scenes/game_room.tscn")
	_scene = packed.instantiate()
	get_root().add_child(_scene)


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("c:/tmp/val/" + name)


## Anda a Jill em linha reta (facing dado) por ate `steps` passos de fisica ou ate
## barrar. Devolve o ponto PS1 final. Usa apply_input -> exercita a colisao do jogo.
func _walk(start_ps1: Vector3, facing_deg: float, running: bool, steps: int) -> Vector3:
	_jill.global_position = _scene.ps1_to_godot(start_ps1)
	_jill.set_facing(facing_deg)
	var last: Vector3 = _jill.global_position
	var stuck := 0
	for i in steps:
		_jill.apply_input(1.0, 0.0, running, 1.0 / 30.0)
		if _jill.global_position.distance_to(last) < 0.0005:
			stuck += 1
			if stuck > 6:
				break
		else:
			stuck = 0
		last = _jill.global_position
	return Vector3(_jill.global_position.x * _scene.world_scale, 0,
			_jill.global_position.z * _scene.world_scale)


func _process(_delta: float) -> bool:
	_f += 1
	if _f < 6:
		return false
	_jill = _scene.jill
	_scene.auto_camera = false
	_scene._show_camera(0)

	print("=== COLISAO R100 (moveis reais, offset_table[6]) ===")
	print("rects de colisao carregados: ", _scene.col_rects.size(),
		" (0 = fallback; esperado 14)")

	# Amostras de caminhavel: dentro de um movel deve dar FALSE; chao livre TRUE.
	print("livre no start(-21820,-21899) = ", _scene._is_walkable_ps1(-21820, -21899))
	print("dentro do armario(-19000,-24000) = ", _scene._is_walkable_ps1(-19000, -24000))
	print("dentro das caixas(-29000,-30000) = ", _scene._is_walkable_ps1(-29000, -30000))

	# facing: 0=>-Z, 90=>-X, 180=>+Z, 270=>+X. Anda a partir do start caminhavel.
	var start := Vector3(-21820, -258, -21899)
	var dirs := {"+X(armario)": 270.0, "-X(esq)": 90.0, "+Z(fundo)": 180.0, "-Z(frente)": 0.0}
	for k in dirs:
		var e := _walk(start, dirs[k], false, 500)
		var d := start.distance_to(Vector3(e.x, -258, e.z))
		print("ANDAR %s: (%d,%d) -> parou (%d,%d)  andou=%d un  caminhavel_no_ponto=%s"
			% [k, start.x, start.z, e.x, e.z, d, _scene._is_walkable_ps1(e.x, e.z)])
	# render: parada contra o ARMARIO (a mais proxima/visivel na cam0)
	_walk(start, 270.0, false, 500)
	_jill.apply_input(0, 0, false, 0.033)
	_shot("col_stop_cabinet.png")

	quit()
	return true
