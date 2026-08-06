extends SceneTree
## Montage/validacao das MALHAS DE ARMA extraidas do .PLW (arquivos *_WPN.glb).
## Renderiza cada arma (pose de descanso, camera ajustada pela AABB) numa grade,
## num UNICO launch (regra de ouro do godot/dev/README.md — nao relancar por item).
##
## Rodar (modo cena, opengl3 — headless NAO renderiza):
##   "<godot>" --path godot --rendering-driver opengl3 --script res://dev/tools_weapon_shot.gd
## Env:
##   DIR=res://assets/PLD  OUT=res://dev/weapon_montage.png  CELL=200  COLS=9  VIEW=side
##   ONLY=PL00W01_WPN,PL00W03_WPN   (lista opcional; so estes, sem _WPN.glb implicito)

var _dir := "res://assets/PLD"
var _out := "res://dev/weapon_montage.png"
var _cell := 200
var _cols := 9
var _view := "side"
var _settle := 4

var _files: Array = []
var _root3d: Node3D
var _cam: Camera3D
var _inst: Node = null
var _i := 0
var _wait := 0
var _montage: Image
var _rows := 1


func _initialize() -> void:
	if OS.has_environment("DIR"): _dir = OS.get_environment("DIR")
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	if OS.has_environment("CELL"): _cell = int(OS.get_environment("CELL"))
	if OS.has_environment("COLS"): _cols = int(OS.get_environment("COLS"))
	if OS.has_environment("VIEW"): _view = OS.get_environment("VIEW")

	var only: Array = []
	if OS.has_environment("ONLY"):
		for n in OS.get_environment("ONLY").split(","):
			only.append(n.strip_edges())

	var da := DirAccess.open(_dir)
	if da == null:
		push_error("dir invalido " + _dir); quit(1); return
	for f in da.get_files():
		if not f.ends_with("_WPN.glb"):
			continue
		var base := f.get_basename()
		if only.is_empty() or base in only:
			_files.append(_dir + "/" + f)
	_files.sort()
	if _files.is_empty():
		push_error("sem *_WPN.glb em " + _dir); quit(1); return
	_rows = int(ceil(float(_files.size()) / float(_cols)))
	_montage = Image.create(_cols * _cell, _rows * _cell, false, Image.FORMAT_RGB8)
	_montage.fill(Color(0.08, 0.08, 0.10))
	print("armas=", _files.size(), " grade=", _cols, "x", _rows)

	get_root().set_size(Vector2i(_cell, _cell))
	get_root().transparent_bg = false
	_root3d = Node3D.new()
	get_root().add_child(_root3d)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-30), deg_to_rad(40), 0)
	sun.light_energy = 1.6
	_root3d.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.65, 0.70)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_root3d.add_child(_cam)


func _process(_dt: float) -> bool:
	if _i >= _files.size():
		var err := _montage.save_png(_out)
		print("MONTAGE ", _out, " err=", err)
		quit()
		return true

	if _inst == null:
		var packed: PackedScene = load(_files[_i])
		if packed == null:
			print("SKIP (load falhou) ", _files[_i]); _i += 1; return false
		_inst = packed.instantiate()
		_root3d.add_child(_inst)
		_fit_camera()
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
	var cx := (_i % _cols) * _cell
	var cy := int(_i / _cols) * _cell
	_montage.blit_rect(img, Rect2i(0, 0, _cell, _cell), Vector2i(cx, cy))
	print("CELL ", _i, " ", _files[_i].get_file())

	_root3d.remove_child(_inst)
	_inst.queue_free()
	_inst = null
	_i += 1
	return false


func _fit_camera() -> void:
	var aabb := _combined_aabb(_inst)
	var ctr := aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.02)
	var dist: float = (radius / tan(deg_to_rad(_cam.fov * 0.5))) * 1.2
	var dir: Vector3
	match _view:
		"front": dir = Vector3(0, 0.05, 1).normalized()
		"top": dir = Vector3(0, 1, 0.05).normalized()
		_: dir = Vector3(1, 0.12, 0.35).normalized()
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
