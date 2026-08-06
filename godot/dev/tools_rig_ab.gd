extends SceneTree
## Grade de validacao de SKINNING: N modelos (colunas) x M fracoes de animacao (linhas),
## num UNICO launch. Serve p/ comparar builds do conversor (ex.: heuristica vs tabela
## dir[0]) olhando membro por membro em POSES DIFERENTES — o rest engana.
##
## Rodar:
##   godot --path godot --rendering-driver opengl3 --script res://dev/tools_rig_ab.gd
## Env:
##   LIST=em24_incerto,em37_incerto,...   (nomes em assets/ENEMY, sem .glb)
##   FRACS=0.0,0.25,0.5,0.75              (fracao do comprimento da 1a animacao)
##   OUT=res://dev/ab.png  CELL=260  VIEW=front|side  ANIM=<nome> (default: 1a)

var _names: Array = []
var _fracs: Array = []
var _out := "res://dev/ab.png"
var _cell := 260
var _view := "front"
var _anim_name := ""
var _settle := 3

var _root3d: Node3D
var _cam: Camera3D
var _inst: Node = null
var _ap: AnimationPlayer = null
var _i := 0          # indice do modelo (coluna)
var _j := 0          # indice da fracao (linha)
var _wait := 0
var _grid: Image


func _initialize() -> void:
	var lst := OS.get_environment("LIST")
	if lst == "":
		push_error("defina LIST"); quit(1); return
	for n in lst.split(","):
		if n.strip_edges() != "":
			_names.append(n.strip_edges())
	var fr := OS.get_environment("FRACS")
	if fr == "":
		fr = "0.0,0.25,0.5,0.75"
	for f in fr.split(","):
		_fracs.append(float(f))
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("CELL"): _cell = int(OS.get_environment("CELL"))
	if OS.has_environment("VIEW"): _view = OS.get_environment("VIEW")
	if OS.has_environment("ANIM"): _anim_name = OS.get_environment("ANIM")

	_grid = Image.create(_names.size() * _cell, _fracs.size() * _cell, false, Image.FORMAT_RGB8)
	_grid.fill(Color(0.07, 0.07, 0.09))
	print("modelos=", _names.size(), " fracoes=", _fracs.size())

	get_root().set_size(Vector2i(_cell, _cell))
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(35), 0)
	sun.light_energy = 1.5
	_root3d.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_root3d.add_child(_cam)
	_hide_hud()


## os autoloads de gameplay (HUD/inventario) aparecem em qualquer cena e sujam o shot
func _hide_hud() -> void:
	for nm in ["HUD", "Inventory", "LangManager"]:
		var n := get_root().get_node_or_null(nm)
		if n != null:
			_hide_tree(n)


func _hide_tree(n: Node) -> void:
	if "visible" in n:
		n.set("visible", false)
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_hide_tree(c)


func _process(_dt: float) -> bool:
	if _i >= _names.size():
		print("GRID ", _out, " err=", _grid.save_png(_out))
		quit()
		return true

	if _inst == null:
		var packed: PackedScene = load("res://assets/ENEMY/%s.glb" % _names[_i])
		if packed == null:
			print("SKIP ", _names[_i]); _i += 1; return false
		_inst = packed.instantiate()
		_root3d.add_child(_inst)
		_ap = _find_ap(_inst)
		# camera fixa pelo REST do modelo (nao segue a anim: assim o descolamento
		# aparece como deslocamento na imagem, em vez de ser reenquadrado)
		_fit_camera()
		_j = 0
		_seek()
		_wait = _settle
		return false

	if _wait > 0:
		_wait -= 1
		return false

	var img := get_root().get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	if img.get_width() != _cell or img.get_height() != _cell:
		img.resize(_cell, _cell, Image.INTERPOLATE_BILINEAR)
	_grid.blit_rect(img, Rect2i(0, 0, _cell, _cell), Vector2i(_i * _cell, _j * _cell))
	print("CELL ", _names[_i], " frac=", _fracs[_j])

	_j += 1
	if _j < _fracs.size():
		_seek()
		_wait = _settle
		return false

	_root3d.remove_child(_inst)
	_inst.queue_free()
	_inst = null
	_i += 1
	return false


func _seek() -> void:
	if _ap == null:
		return
	var nm := _anim_name
	if nm == "" or not _ap.has_animation(nm):
		var l := _ap.get_animation_list()
		if l.is_empty():
			return
		nm = l[0]
	var a := _ap.get_animation(nm)
	_ap.play(nm)
	_ap.seek(a.length * float(_fracs[_j]), true)
	_ap.pause()


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null


func _fit_camera() -> void:
	var aabb := _combined_aabb(_inst)
	var ctr := aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.1)
	var dist: float = (radius / tan(deg_to_rad(_cam.fov * 0.5))) * 1.25
	var dir: Vector3
	match _view:
		"side": dir = Vector3(1, 0, 0.15).normalized()
		_: dir = Vector3(0, 0.05, 1).normalized()
	_cam.look_at_from_position(ctr + dir * dist, ctr, Vector3.UP)


func _combined_aabb(n: Node) -> AABB:
	var out := AABB()
	var has := false
	for c in _all(n):
		if c is VisualInstance3D:
			var a: AABB = (c as VisualInstance3D).get_aabb()
			a = (c as Node3D).global_transform * a
			if not has: out = a; has = true
			else: out = out.merge(a)
	if not has: out = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return out


func _all(n: Node) -> Array:
	var r := [n]
	for c in n.get_children():
		r += _all(c)
	return r
