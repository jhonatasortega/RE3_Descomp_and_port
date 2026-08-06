extends SceneTree
## TESTE DETERMINISTICO de orientacao do mesh: camera olhando ao longo do -Z do
## NODE (de +Z para -Z). Renderiza o PL00 com model_yaw_offset = 0/90/180/270 e
## salva 4 PNGs. O offset CERTO e aquele em que a camera (olhando -Z) ve as COSTAS
## da Jill -> assim forward=-basis.z move na direcao que ela olha.
##
## Rodar: godot --path godot --rendering-driver opengl3 --script res://tools_orient_test.gd

const OUT := "res://move_val"
var _offsets := [0.0, 90.0, 180.0, 270.0]
var _root3d: Node3D
var _model: Node3D
var _cam: Camera3D
var _anim: AnimationPlayer
var _i := -1
var _warm := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().set_size(Vector2i(480, 640))
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new(); we.environment = env
	_root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(20), 0)
	sun.light_energy = 1.2
	_root3d.add_child(sun)

	var packed: PackedScene = load("res://assets/PLD/PL00.glb")
	_model = packed.instantiate()
	_root3d.add_child(_model)
	_anim = _find_anim(_model)
	if _anim and _anim.has_animation("anim00"):
		_anim.play("anim00"); _anim.seek(0.0, true); _anim.pause()

	# Camera em +Z olhando para -Z (ao longo do -Z do node)
	_cam = Camera3D.new(); _cam.fov = 45.0
	_root3d.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 1.1, 4.6), Vector3(0, 1.1, -1), Vector3.UP)
	print("=== ORIENT TEST === camera em +Z olhando -Z; offset certo = mostra as COSTAS")


func _process(_delta: float) -> bool:
	if _warm < 3:
		_warm += 1
		return false
	if _i >= 0:
		var img := get_root().get_texture().get_image()
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		img.save_png("%s/orient_%03d.png" % [OUT, int(_offsets[_i])])
		print("saved offset=", _offsets[_i])
	_i += 1
	if _i >= _offsets.size():
		print("DONE"); quit(); return true
	_model.rotation.y = deg_to_rad(_offsets[_i])
	_warm = 0
	return false


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r: return r
	return null
