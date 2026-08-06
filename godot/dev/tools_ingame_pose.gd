extends SceneTree
## Renderiza candidatos a IDLE-em-pe (anim,frac) com o xform do jogo (rot90,posY),
## seek+pause no frame indicado, camera 3/4 de nivel. Salva 1 PNG por candidato.
## Rodar: godot --path godot --rendering-driver opengl3 --script res://tools_ingame_pose.gd

const OUT := "res://move_val"
# [nome_arquivo, anim, frac]
var _cases := [
	["c_anim07_f0", "anim07", 0.0],
	["c_anim05_f0", "anim05", 0.0],
	["c_anim03_f20", "anim03", 0.92],
	["c_anim12_f29", "anim12", 0.97],
	["c_anim00_f0", "anim00", 0.0],
	["c_anim13_f0", "anim13", 0.0],
]
var _root3d: Node3D
var _cam: Camera3D
var _ci := -1
var _warm := 0
var _inst: Node
var _anim: AnimationPlayer


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().set_size(Vector2i(420, 620))
	_root3d = Node3D.new(); get_root().add_child(_root3d)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12,0.13,0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7,0.7,0.75); env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new(); we.environment = env; _root3d.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation = Vector3(deg_to_rad(-35),deg_to_rad(25),0)
	sun.light_energy = 1.2; _root3d.add_child(sun)
	_cam = Camera3D.new(); _cam.fov = 42.0; _root3d.add_child(_cam)
	# 3/4 de nivel, ligeiramente acima (parecido com jogo mas sem foreshortening extremo)
	_cam.look_at_from_position(Vector3(2.6,2.6,4.6), Vector3(0,1.6,0), Vector3.UP)


func _next_case() -> void:
	if _inst: _inst.queue_free(); _inst = null
	_ci += 1
	if _ci >= _cases.size():
		print("DONE"); quit(); return
	var packed: PackedScene = load("res://assets/PLD/PL00.glb")
	_inst = packed.instantiate()
	_inst.rotation.y = deg_to_rad(90.0)
	_inst.position.y = 1.85
	_root3d.add_child(_inst)
	_anim = _find(_inst)
	var an: String = _cases[_ci][1]
	var fr: float = _cases[_ci][2]
	if _anim and _anim.has_animation(an):
		var a := _anim.get_animation(an)
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(an)
		_anim.seek(a.length * fr, true)
		_anim.pause()
	_warm = 0


func _process(_delta: float) -> bool:
	if _ci < 0:
		_next_case(); return false
	_warm += 1
	if _warm < 30:
		return false
	var img := get_root().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGB8: img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [OUT, _cases[_ci][0]])
	print("CASE ", _cases[_ci][0])
	_next_case()
	return false


func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find(c)
		if r: return r
	return null
