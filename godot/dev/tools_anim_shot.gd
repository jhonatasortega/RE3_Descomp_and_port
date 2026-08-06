extends SceneTree
## Harness p/ renderizar CADA animacao do PL00.glb em 3 frames (inicio/meio/fim)
## num contact-sheet horizontal, revelando a POSTURA e o MOVIMENTO (walk/limp/aim...).
##
## Rodar com:
##   godot --path godot --rendering-driver opengl3 --script res://tools_anim_shot.gd
## (headless NAO renderiza: usa driver dummy.)
##
## Saida: res://anim_shots/<anim>.png  (3 paineis lado a lado)
## Env: MODEL=res://assets/PLD/PL00.glb  OUT=res://anim_shots  VIEW=front|side|iso

const PANEL := 384
const SETTLE := 3            # frames de render antes de capturar
const FRACS := [0.15, 0.5, 0.85]

var _model_path := "res://assets/PLD/PL00.glb"
var _outdir := "res://anim_shots"
var _view := "iso"

var _anim: AnimationPlayer
var _names: Array = []
var _cam: Camera3D
var _root3d: Node3D

var _ai := 0                 # indice da animacao atual
var _fi := 0                 # indice do frame (0..2)
var _wait := 0
var _strip: Image
var _phase := 0              # 0=setup pose, 1=esperando render
var _inst: Node
var _cam_ready := false


func _initialize() -> void:
	if OS.has_environment("MODEL"): _model_path = OS.get_environment("MODEL")
	if OS.has_environment("OUT"): _outdir = OS.get_environment("OUT")
	if OS.has_environment("VIEW"): _view = OS.get_environment("VIEW")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_outdir))

	get_root().set_size(Vector2i(PANEL, PANEL))
	get_root().transparent_bg = false

	_root3d = Node3D.new()
	get_root().add_child(_root3d)

	var packed: PackedScene = load(_model_path)
	if packed == null:
		push_error("falha ao carregar " + _model_path); quit(1); return
	_inst = packed.instantiate()
	_root3d.add_child(_inst)

	# luz
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	sun.light_energy = 1.4
	_root3d.add_child(sun)
	var amb := DirectionalLight3D.new()
	amb.rotation = Vector3(deg_to_rad(30), deg_to_rad(-150), 0)
	amb.light_energy = 0.6
	_root3d.add_child(amb)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.16, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)

	# camera criada aqui, mas posicionada no 1o _process (nodes ja no tree)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_root3d.add_child(_cam)

	_anim = _find_anim(_inst)
	if _anim == null:
		push_error("sem AnimationPlayer"); quit(1); return
	_names = _anim.get_animation_list()
	_names.sort()
	if OS.has_environment("ONLY"):
		var keep := OS.get_environment("ONLY").split(",")
		var filt: Array = []
		for n in _names:
			if keep.has(n): filt.append(n)
		_names = filt
	print("ANIMS(", _names.size(), "): ", _names)
	_new_strip()


func _setup_camera() -> void:
	# camera FIXA (independente do modelo) p/ comparar variantes: CAM_CTR="x,y,z" CAM_DIST=n
	if OS.has_environment("CAM_CTR"):
		var pc := OS.get_environment("CAM_CTR").split(",")
		var ctr0 := Vector3(float(pc[0]), float(pc[1]), float(pc[2]))
		var dist0 := float(OS.get_environment("CAM_DIST")) if OS.has_environment("CAM_DIST") else 4.2
		var dir0: Vector3
		match _view:
			"front": dir0 = Vector3(0, 0, 1)
			"side":  dir0 = Vector3(1, 0, 0)
			_:       dir0 = Vector3(0.7, 0.12, 1).normalized()
		_cam.look_at_from_position(ctr0 + dir0 * dist0, ctr0, Vector3.UP)
		print("CAM(fixed) ctr=", ctr0, " dist=", dist0)
		return
	var aabb := _combined_aabb(_inst)
	var ctr := aabb.get_center()
	var zf := 0.55
	if OS.has_environment("ZOOM"): zf = float(OS.get_environment("ZOOM"))
	var radius: float = aabb.size.length() * zf
	var dist: float = radius / tan(deg_to_rad(_cam.fov * 0.5))
	var dir: Vector3
	match _view:
		"front": dir = Vector3(0, 0, 1)
		"side":  dir = Vector3(1, 0, 0)
		_:       dir = Vector3(0.7, 0.12, 1).normalized()   # iso 3/4
	_cam.look_at_from_position(ctr + dir * dist, ctr, Vector3.UP)
	print("CAM aabb=", aabb, " ctr=", ctr, " dist=", dist)


func _new_strip() -> void:
	_strip = Image.create(PANEL * FRACS.size(), PANEL, false, Image.FORMAT_RGB8)


func _process(_delta: float) -> bool:
	if not _cam_ready:
		_setup_camera()
		_cam_ready = true
		return false
	if _ai >= _names.size():
		print("DONE"); quit(); return true
	var name: String = _names[_ai]

	if _phase == 0:
		if not OS.has_environment("REST"):
			var a := _anim.get_animation(name)
			var t: float = a.length * float(FRACS[_fi])
			_anim.play(name)
			_anim.seek(t, true)
			_anim.pause()
		_wait = SETTLE
		_phase = 1
		return false

	# phase 1: aguarda o render assentar
	if _wait > 0:
		_wait -= 1
		if not OS.has_environment("REST"):
			# re-seek p/ garantir a pose (pause pode nao segurar em alguns builds)
			var a := _anim.get_animation(name)
			_anim.seek(a.length * float(FRACS[_fi]), true)
		return false

	# captura painel (a janela pode renderizar em resolucao diferente -> redimensiona)
	var img := get_root().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	img.resize(PANEL, PANEL, Image.INTERPOLATE_BILINEAR)
	_strip.blit_rect(img, Rect2i(0, 0, PANEL, PANEL), Vector2i(PANEL * _fi, 0))

	_fi += 1
	_phase = 0
	if _fi >= FRACS.size():
		var out := "%s/%s.png" % [_outdir, name]
		var err := _strip.save_png(out)
		print("SHOT ", name, " len=", _anim.get_animation(name).length, " err=", err)
		_fi = 0
		_ai += 1
		_new_strip()
	return false


func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var has := false
	for c in _all_nodes(n):
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb()
			a = (c as Node3D).global_transform * a
			if not has:
				out = a; has = true
			else:
				out = out.merge(a)
	if not has:
		out = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return out


func _all_nodes(n: Node) -> Array:
	var r := [n]
	for c in n.get_children():
		r += _all_nodes(c)
	return r


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r: return r
	return null
