extends SceneTree
## VALIDACAO REAL do movimento da Jill (tank controls) — NAO e' frame estatico.
##
## Monta uma cena 3D controlada (camera 3/4 fixa + marcadores de eixo) com o MESMO
## node/So script do jogo (jill_controller.gd + PL00.glb) e SIMULA input roteirizado
## por MUITOS frames, chamando jill.apply_input(move,turn,running,DT) — a MESMA
## rotina do teclado. A cada frame LOGA:
##   - posicao do NODE da Jill (jill.global_position)
##   - posicao GLOBAL do QUADRIL (osso raiz do Skeleton3D) -> revela se o mesh
##     desliza DENTRO do node (root-motion residual)
##   - facing (graus)
## e renderiza um PNG a cada ~10 frames (sequencia).
##
## Roteiro: [30 sem input]->[60 W]->[30 A]->[30 D]->[60 S]->[30 sem input].
##
## Rodar: godot --path godot --rendering-driver opengl3 --script res://tools_move_val.gd
## Saida: res://move_val/seq_####.png  + log no stdout.

const DT := 1.0 / 30.0
const OUT := "res://move_val"
const IMG := 480

# fase: [nome, nframes, move, turn, running]
var _script := [
	["idle0", 30, 0.0, 0.0, false],
	["W",     60, 1.0, 0.0, false],
	["A",     30, 0.0, -1.0, false],
	["D",     30, 0.0, 1.0, false],
	["S",     60, -1.0, 0.0, false],
	["idle1", 30, 0.0, 0.0, false],
]

var _jill: Node3D
var _skel: Skeleton3D
var _cam: Camera3D
var _root3d: Node3D
var _frame := 0
var _phase_idx := 0
var _phase_frame := 0
var _warm := 0
var _log: Array = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().set_size(Vector2i(IMG, IMG))
	get_root().transparent_bg = false

	_root3d = Node3D.new()
	get_root().add_child(_root3d)

	# Ambiente/luz
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(40), 0)
	sun.light_energy = 1.3
	_root3d.add_child(sun)

	# Marcadores de eixo (mundo): X+ VERMELHO, Z+ AZUL, origem BRANCA.
	_add_marker(Vector3(1.2, 0.1, 0.0), Color(1, 0.15, 0.15))   # X+ vermelho
	_add_marker(Vector3(0.0, 0.1, 1.2), Color(0.2, 0.35, 1.0))  # Z+ azul
	_add_marker(Vector3(0.0, 0.02, 0.0), Color(1, 1, 1), 0.12)  # origem branca (chao)
	# grade simples no chao
	_add_ground()

	# Jill: replica a estrutura da cena (Node3D 'Jill' + filho 'Model' = PL00.glb)
	_jill = Node3D.new()
	_jill.name = "Jill"
	_jill.set_script(load("res://scripts/jill_controller.gd"))
	var packed: PackedScene = load("res://assets/PLD/PL00.glb")
	var model := packed.instantiate()
	model.name = "Model"
	_jill.add_child(model)
	_root3d.add_child(_jill)   # dispara _ready do controller (acha Model/anim, idle)

	# IMPORTANTE: o _ready do controller pode RE-INSTANCIAR o Model (libera o antigo),
	# entao buscamos o Skeleton na subarvore ATUAL do _jill (senao lemos um freed stale).
	_skel = _find_skel(_jill)
	if _skel == null:
		push_error("Skeleton3D nao encontrado no PL00.glb")
	else:
		print("skel encontrado: ", _skel.get_path())

	# Camera 3/4 fixa olhando a origem (onde a Jill comeca)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_root3d.add_child(_cam)
	# mira no meio do percurso (a Jill anda de z=0 ate z~-4.4) p/ manter tudo enquadrado
	_cam.look_at_from_position(Vector3(6.0, 4.2, 6.0), Vector3(0, 1.0, -2.2), Vector3.UP)

	print("=== MOVE VAL === cam=", _cam.global_position, " (X+ vermelho, Z+ azul)")
	print("hdr: frame phase move turn | node(x,z) | hip(x,z) | facing_deg | anim")


func _add_marker(pos: Vector3, col: Color, s := 0.18) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s, s)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	_root3d.add_child(mi)


func _add_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.26)
	mi.material_override = m
	mi.position = Vector3(0, 0, 0)
	_root3d.add_child(mi)


func _hip_world() -> Vector3:
	if _skel == null:
		return Vector3.ZERO
	var pose := _skel.get_bone_global_pose(0)
	return _skel.global_transform * pose.origin


func _process(_delta: float) -> bool:
	# aquece alguns frames p/ o render assentar antes de comecar o roteiro
	if _warm < 4:
		_warm += 1
		return false

	if _phase_idx >= _script.size():
		_finish()
		return true

	var ph = _script[_phase_idx]
	var name: String = ph[0]
	var nfr: int = ph[1]
	var mv: float = ph[2]
	var tn: float = ph[3]
	var rn: bool = ph[4]

	# aplica UM passo com dt fixo (mesma rotina do teclado)
	_jill.apply_input(mv, tn, rn, DT)

	var np: Vector3 = _jill.global_position
	var hp: Vector3 = _hip_world()
	var cur_anim: String = _jill._current_anim
	_log.append("%03d %-5s mv=%+.0f tn=%+.0f | node(%+.4f,%+.4f) | hip(%+.4f,%+.4f) | face=%+8.2f | %s" % [
		_frame, name, mv, tn, np.x, np.z, hp.x, hp.z, _jill.facing_deg, cur_anim])

	# render da sequencia a cada 10 frames
	if _frame % 10 == 0:
		var img := get_root().get_texture().get_image()
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		img.save_png("%s/seq_%04d_%s.png" % [OUT, _frame, name])

	_frame += 1
	_phase_frame += 1
	if _phase_frame >= nfr:
		_phase_frame = 0
		_phase_idx += 1
	return false


func _finish() -> void:
	print("--- LOG (por frame) ---")
	for l in _log:
		print(l)
	# resumo por fase: delta de node e hip
	print("--- RESUMO ---")
	quit()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D and n.is_inside_tree():
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r:
			return r
	return null
