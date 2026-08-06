extends SceneTree
## Renderiza um modelo PLD em 2 poses lado a lado: IDLE (anim00 frame 0, ereto)
## e um frame de ANDAR (anim de walk num frame do meio), p/ validar skinning:
## sem papel, sem fresta no joelho, membros integros.
##
## Rodar com:
##   godot --path godot --rendering-driver opengl3 --script res://tools_pose_shot.gd
## Env:
##   MODEL=res://assets/PLD/PL08.glb
##   OUT=res://anim_shots/val_PL08.png
##   IDLE=anim00   IDLE_F=0.0        (pose parada)
##   WALK=anim16   WALK_F=0.5        (frame de andar)
##   VIEW=front|side|iso

const PANEL := 512
const SETTLE := 4

var _model_path := "res://assets/PLD/PL08.glb"
var _out := "res://anim_shots/val.png"
var _view := "iso"
var _idle := "anim00"
var _idle_f := 0.0
var _walk := "anim16"
var _walk_f := 0.5

var _anim: AnimationPlayer
var _cam: Camera3D
var _root3d: Node3D
var _inst: Node
var _cam_ready := false
var _strip: Image
var _stage := 0            # 0=idle, 1=walk, 2=done
var _wait := 0
var _phase := 0


func _initialize() -> void:
	if OS.has_environment("MODEL"): _model_path = OS.get_environment("MODEL")
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("VIEW"): _view = OS.get_environment("VIEW")
	if OS.has_environment("IDLE"): _idle = OS.get_environment("IDLE")
	if OS.has_environment("IDLE_F"): _idle_f = float(OS.get_environment("IDLE_F"))
	if OS.has_environment("WALK"): _walk = OS.get_environment("WALK")
	if OS.has_environment("WALK_F"): _walk_f = float(OS.get_environment("WALK_F"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))

	get_root().set_size(Vector2i(PANEL, PANEL))
	get_root().transparent_bg = false
	_root3d = Node3D.new()
	get_root().add_child(_root3d)

	var packed: PackedScene = load(_model_path)
	if packed == null:
		push_error("falha ao carregar " + _model_path); quit(1); return
	_inst = packed.instantiate()
	_root3d.add_child(_inst)

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

	_cam = Camera3D.new()
	_cam.fov = 45.0
	_root3d.add_child(_cam)

	_anim = _find_anim(_inst)
	if _anim == null:
		push_error("sem AnimationPlayer"); quit(1); return
	print("ANIMS: ", _anim.get_animation_list())
	_strip = Image.create(PANEL * 2, PANEL, false, Image.FORMAT_RGB8)


func _setup_camera() -> void:
	var aabb := _combined_aabb(_inst)
	var ctr := aabb.get_center()
	var zf := 0.58
	if OS.has_environment("ZOOM"): zf = float(OS.get_environment("ZOOM"))
	var radius: float = aabb.size.length() * zf
	var dist: float = radius / tan(deg_to_rad(_cam.fov * 0.5))
	var dir: Vector3
	match _view:
		"front": dir = Vector3(0, 0, 1)
		"side":  dir = Vector3(1, 0, 0)
		_:       dir = Vector3(0.7, 0.12, 1).normalized()
	_cam.look_at_from_position(ctr + dir * dist, ctr, Vector3.UP)


func _apply_pose(an: String, frac: float) -> void:
	if not _anim.has_animation(an):
		push_warning("anim ausente: " + an); return
	var a := _anim.get_animation(an)
	_anim.play(an)
	_anim.seek(a.length * frac, true)
	_anim.pause()


func _process(_delta: float) -> bool:
	if not _cam_ready:
		_setup_camera()
		_cam_ready = true
		return false
	if _stage >= 2:
		var err := _strip.save_png(_out)
		print("VAL_SHOT saved=", _out, " err=", err)
		quit(); return true

	var an := _idle if _stage == 0 else _walk
	var frac := _idle_f if _stage == 0 else _walk_f

	if _phase == 0:
		_apply_pose(an, frac)
		_wait = SETTLE
		_phase = 1
		return false
	if _wait > 0:
		_wait -= 1
		_apply_pose(an, frac)
		return false

	var img := get_root().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	img.resize(PANEL, PANEL, Image.INTERPOLATE_BILINEAR)
	_strip.blit_rect(img, Rect2i(0, 0, PANEL, PANEL), Vector2i(PANEL * _stage, 0))
	print("PANEL ", _stage, " anim=", an, " frac=", frac)
	_stage += 1
	_phase = 0
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
