extends SceneTree
## Valida a etapa 2 (gameplay) da game_room, renderizando de verdade (opengl3):
##   1. Camera inicial correta pela zona RVD.
##   2. Troca de camera AUTOMATICA ao mover a Jill de uma zona para outra.
##   3. Colisao aproximada (amostras de caminhavel + teste de parede por input).
## Salva screenshots e imprime um log das trocas de camera e da colisao.

var _scene: Node
var _jill
var _f := 0
var _phase := 0
var _last_cam := -1
var _log: Array = []
var _wall_x0 := 0.0
var _wall_positions: Array = []

const P0 := Vector3(-21820, -258, -21899)   # area da camera 0 (deposito)
const P1 := Vector3(-26094, -258, -19850)   # area da camera 1 (sala de save)


func _initialize() -> void:
	var packed := load("res://scenes/game_room.tscn")
	_scene = packed.instantiate()
	get_root().add_child(_scene)


func _shot(name: String) -> void:
	var img := get_root().get_texture().get_image()
	img.save_png("res://" + name)
	print("SHOT ", name, " cam=", _scene.cam_index)


func _process(_delta: float) -> bool:
	_f += 1
	if _f < 5:
		return false
	_jill = _scene.jill

	# Fase 0: estado inicial (deve ser camera da zona de P0)
	if _phase == 0:
		_last_cam = _scene.cam_index
		_log.append("inicio: cam=%d (esperado: zona de P0)" % _scene.cam_index)
		# amostras de colisao
		print("WALK P0(dentro)=", _scene._is_walkable_ps1(P0.x, P0.z))
		print("WALK fora(-40000,-40000)=", _scene._is_walkable_ps1(-40000, -40000))
		print("WALK blocker caixas(-29000,-27000)=", _scene._is_walkable_ps1(-29000, -27000))
		print("WALK P1(dentro)=", _scene._is_walkable_ps1(P1.x, P1.z))
		_shot("gp_1_start_cam%d.png" % _scene.cam_index)
		_phase = 1
		_f = 0
		return false

	# Fase 1: caminhar de P0 -> P1 (setando posicao direto p/ testar a troca de camera)
	if _phase == 1:
		var t: float = clampf(_f / 40.0, 0.0, 1.0)
		var ps1 := P0.lerp(P1, t)
		_jill.global_position = _scene.ps1_to_godot(ps1)
		if _scene.cam_index != _last_cam:
			_log.append("t=%.2f pos=(%d,%d) -> TROCA cam %d->%d" % [t, ps1.x, ps1.z, _last_cam, _scene.cam_index])
			_last_cam = _scene.cam_index
		if t >= 1.0:
			_shot("gp_2_end_cam%d.png" % _scene.cam_index)
			_phase = 2
			_f = 0
		return false

	# Fase 2: teste de PAREDE — exercita o MESMO codigo de colisao do jogo
	# (_apply_move + walkable_query), avancando em -X ate barrar.
	if _phase == 2:
		_jill.global_position = _scene.ps1_to_godot(P0)
		_jill.set_facing(90.0)   # forward = -X (rumo a parede esquerda)
		_wall_x0 = _jill.global_position.x * _scene.world_scale
		var step := Vector3(-0.05, 0, 0)   # ~40 un PS1 por passo
		for i in 320:
			var cur: Vector3 = _jill.global_position
			_jill.global_position = _jill._apply_move(cur, cur + step)
		var px: float = _jill.global_position.x * _scene.world_scale
		var pz: float = _jill.global_position.z * _scene.world_scale
		var walk: bool = _scene._is_walkable_ps1(px, pz)
		_log.append("parede: partiu de x=%d, avancou em -X e parou em x=%d (caminhavel=%s, borda respeitada=%s)" % [
			_wall_x0, px, walk, str(px > -32000)])
		_shot("gp_3_wall.png")
		_phase = 4
		_f = 0
		return false

	# Fim
	print("\n=== LOG GAMEPLAY ===")
	for l in _log:
		print("  ", l)
	quit()
	return true
