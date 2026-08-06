extends Node3D
class_name ModelViewer
## Visualizador 3D interativo para VALIDAR integridade dos modelos (inimigos + personagens).
##
## Verifica de olho: malha, skinning, esqueleto (bones), UV/textura e animações.
## Carrega os .glb em RUNTIME via GLTFDocument (funciona mesmo em glb ainda NAO importado
## pela Godot), varrendo assets/ENEMY e assets/PLD.
##
## COMO RODAR (modo cena, sem editor — ver godot/dev/README.md):
##   "<godot>" --path godot --rendering-driver opengl3 res://scenes/model_viewer.tscn
##
## CONTROLES:
##   Arrastar mouse ESQ ....... orbitar
##   Scroll ................... zoom
##   Arrastar mouse DIR/MEIO .. pan
##   [ / ] ou botoes .......... modelo anterior / proximo
##   , / . ou botoes .......... animacao anterior / proxima
##   Espaco ................... play/pause da animacao
##   - / = .................... velocidade da animacao
##   B ........................ mostrar/ocultar OSSOS (skeleton)
##   T ........................ ciclar textura: texturizado -> branco -> wireframe
##   G ........................ grade de chao
##   A ........................ auto-rotacao on/off
##   R ........................ resetar camera
##   Esc ...................... sair

const DIRS := ["res://assets/ENEMY", "res://assets/PLD"]

# --- estado da lista ---
var _models: Array = []          # [{path,name,group}]
var _idx: int = -1

# --- nodes de cena ---
var _pivot: Node3D               # onde o modelo carregado e' pendurado
var _model_root: Node3D          # o glb instanciado atual
var _anim: AnimationPlayer
var _skel: Skeleton3D
var _cam: Camera3D
var _grid: MeshInstance3D
var _bones_draw: MeshInstance3D

# --- camera orbital ---
var _target: Vector3 = Vector3.ZERO
var _radius: float = 3.0
var _yaw: float = 0.6
var _pitch: float = 0.35
var _panning: bool = false
var _orbiting: bool = false
var _follow: bool = true          # camera segue o centro VIVO do modelo (anula root-motion visualmente)
var _pan_offset: Vector3 = Vector3.ZERO

# --- opcoes ---
var _auto_rotate: bool = false
var _bones_visible: bool = false
var _tex_mode: int = 0            # 0=texturizado 1=branco 2=wireframe
var _anim_names: PackedStringArray = PackedStringArray()
var _anim_idx: int = -1
var _anim_speed: float = 1.0
var _paused: bool = false

# --- UI ---
var _lbl_info: RichTextLabel
var _lbl_warn: RichTextLabel
var _opt_model: OptionButton
var _opt_anim: OptionButton
var _lbl_status: Label


func _ready() -> void:
	_build_world()
	_build_ui()
	_scan_models()
	if _models.is_empty():
		_lbl_warn.text = "[color=red]Nenhum .glb encontrado em assets/ENEMY ou assets/PLD[/color]"
	else:
		_load_index(0)          # carrega o MODELO primeiro (garantido)
	_hide_game_hud()            # esconder autoloads por ULTIMO (nao pode abortar o load)


# ---------------------------------------------------------------- mundo 3D
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.45, 0.5)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -40, 0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.5
	add_child(fill)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.near = 0.01
	_cam.far = 5000.0
	add_child(_cam)

	_pivot = Node3D.new()
	add_child(_pivot)

	_grid = _make_grid(10.0, 20)
	_grid.visible = false
	add_child(_grid)

	_bones_draw = MeshInstance3D.new()
	_bones_draw.mesh = ImmediateMesh.new()
	_bones_draw.material_override = _line_mat(Color(0.2, 1.0, 0.4))
	_bones_draw.visible = false
	add_child(_bones_draw)


func _make_grid(size: float, divs: int) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := _line_mat(Color(0.3, 0.3, 0.35))
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var step := size / divs
	var half := size * 0.5
	for i in range(divs + 1):
		var p := -half + i * step
		im.surface_add_vertex(Vector3(p, 0, -half))
		im.surface_add_vertex(Vector3(p, 0, half))
		im.surface_add_vertex(Vector3(-half, 0, p))
		im.surface_add_vertex(Vector3(half, 0, p))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi


func _line_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.vertex_color_use_as_albedo = false
	return m


# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)

	# painel de info (topo-esquerda)
	var info_panel := PanelContainer.new()
	info_panel.position = Vector2(8, 8)
	info_panel.custom_minimum_size = Vector2(360, 0)
	cl.add_child(info_panel)
	var vb := VBoxContainer.new()
	info_panel.add_child(vb)
	_lbl_info = RichTextLabel.new()
	_lbl_info.bbcode_enabled = true
	_lbl_info.fit_content = true
	_lbl_info.custom_minimum_size = Vector2(344, 0)
	_lbl_info.scroll_active = false
	vb.add_child(_lbl_info)
	_lbl_warn = RichTextLabel.new()
	_lbl_warn.bbcode_enabled = true
	_lbl_warn.fit_content = true
	_lbl_warn.custom_minimum_size = Vector2(344, 0)
	_lbl_warn.scroll_active = false
	vb.add_child(_lbl_warn)

	# barra de controle (rodape)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -40
	bar.offset_left = 8
	bar.offset_right = -8
	bar.offset_bottom = -8
	bar.add_theme_constant_override("separation", 6)
	cl.add_child(bar)

	var b_prev := Button.new(); b_prev.text = "◀ Modelo [["
	b_prev.pressed.connect(func(): _step_model(-1))
	bar.add_child(b_prev)
	_opt_model = OptionButton.new()
	_opt_model.custom_minimum_size = Vector2(240, 0)
	_opt_model.item_selected.connect(func(i): _load_index(i))
	bar.add_child(_opt_model)
	var b_next := Button.new(); b_next.text = "] Modelo ▶"
	b_next.pressed.connect(func(): _step_model(1))
	bar.add_child(b_next)

	var sep := VSeparator.new(); bar.add_child(sep)

	var b_pa := Button.new(); b_pa.text = "◀ Anim ,"
	b_pa.pressed.connect(func(): _step_anim(-1))
	bar.add_child(b_pa)
	_opt_anim = OptionButton.new()
	_opt_anim.custom_minimum_size = Vector2(160, 0)
	_opt_anim.item_selected.connect(func(i): _play_anim(i))
	bar.add_child(_opt_anim)
	var b_na := Button.new(); b_na.text = ". Anim ▶"
	b_na.pressed.connect(func(): _step_anim(1))
	bar.add_child(b_na)

	var b_pause := Button.new(); b_pause.text = "⏯ (Espaço)"
	b_pause.pressed.connect(_toggle_pause)
	bar.add_child(b_pause)
	var b_bones := Button.new(); b_bones.text = "Ossos (B)"
	b_bones.pressed.connect(_toggle_bones)
	bar.add_child(b_bones)
	var b_tex := Button.new(); b_tex.text = "Textura (T)"
	b_tex.pressed.connect(_cycle_tex)
	bar.add_child(b_tex)

	_lbl_status = Label.new()
	_lbl_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lbl_status.offset_left = -320
	_lbl_status.offset_top = 10
	_lbl_status.offset_right = -10
	_lbl_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.add_child(_lbl_status)


# ---------------------------------------------------------------- lista de modelos
func _scan_models() -> void:
	_models.clear()
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var group: String = d.get_file()
		var files: Array = []
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if not da.current_is_dir() and f.to_lower().ends_with(".glb"):
				files.append(f)
			f = da.get_next()
		da.list_dir_end()
		files.sort()
		for name in files:
			_models.append({"path": d + "/" + name, "name": name.get_basename(), "group": group})
	# popula o dropdown
	_opt_model.clear()
	for m in _models:
		_opt_model.add_item("%s / %s" % [m.group, m.name])


# ---------------------------------------------------------------- carga do modelo
func _load_index(i: int) -> void:
	if i < 0 or i >= _models.size():
		return
	_idx = i
	_opt_model.select(i)
	var entry: Dictionary = _models[i]

	# limpa o anterior
	if _model_root and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null
	_anim = null
	_skel = null
	_anim_names = PackedStringArray()
	_anim_idx = -1

	var scene := _load_glb_runtime(entry.path)
	if scene == null:
		_lbl_info.text = "[b]%s[/b]\n[color=red]FALHA ao carregar o glb[/color]" % entry.name
		_lbl_warn.text = ""
		return
	_model_root = scene
	_pivot.add_child(_model_root)

	_anim = _find_node(_model_root, "AnimationPlayer") as AnimationPlayer
	_skel = _find_type(_model_root, "Skeleton3D") as Skeleton3D

	# lista de animacoes
	_opt_anim.clear()
	if _anim:
		_anim_names = _anim.get_animation_list()
		for a in _anim_names:
			_opt_anim.add_item(a)
	if _anim_names.size() > 0:
		_play_anim(0)        # comeca ANIMANDO = pose REAL do jogo (o get_bone_rest cru
		                     # e' uma pose que o jogo NUNCA usa e engana p/ inimigos).
		                     # Tecla 0 volta pro rest cru; Espaco pausa.
	else:
		_opt_anim.add_item("(sem animação)")

	_apply_tex_mode()
	_frame_camera()
	_update_info(entry)


func _load_glb_runtime(res_path: String) -> Node3D:
	var abs_path := ProjectSettings.globalize_path(res_path)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(abs_path, st)
	if err != OK:
		# fallback: recurso importado
		var packed = load(res_path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate()
		return null
	var node := doc.generate_scene(st)
	return node as Node3D


# ---------------------------------------------------------------- enquadramento
func _model_aabb() -> AABB:
	var aabb := AABB()
	var first := true
	for mi in _all_mesh_instances():
		if mi.mesh == null:
			continue
		var local: Transform3D = _model_root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = local * mi.get_aabb()
		if first:
			aabb = b
			first = false
		else:
			aabb = aabb.merge(b)
	if first:
		aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return aabb


func _frame_camera() -> void:
	var aabb := _model_aabb()
	_target = _model_root.global_transform * aabb.get_center()
	var sz := aabb.size.length()
	_radius = max(0.5, sz * 1.4)
	_yaw = 0.6
	_pitch = 0.30
	_pan_offset = Vector3.ZERO
	_follow = true
	_update_camera()


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.5, 1.5)
	_radius = clampf(_radius, 0.05, 20000.0)
	var dir := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw))
	_cam.global_position = _target + dir * _radius
	_cam.look_at(_target, Vector3.UP)


# ---------------------------------------------------------------- animacao
func _play_anim(i: int) -> void:
	if _anim == null or i < 0 or i >= _anim_names.size():
		return
	_anim_idx = i
	_opt_anim.select(i)
	_anim.play(_anim_names[i])
	_anim.speed_scale = _anim_speed
	# tenta em loop pra validacao visual
	var a := _anim.get_animation(_anim_names[i])
	if a:
		a.loop_mode = Animation.LOOP_LINEAR
	_paused = false


func _step_anim(d: int) -> void:
	if _anim_names.size() == 0:
		return
	_play_anim((_anim_idx + d + _anim_names.size()) % _anim_names.size())


func _step_model(d: int) -> void:
	if _models.size() == 0:
		return
	_load_index((_idx + d + _models.size()) % _models.size())


func _toggle_pause() -> void:
	if _anim == null or _anim_names.size() == 0:
		return
	if not _anim.is_playing():
		_play_anim(_anim_idx if _anim_idx >= 0 else 0)   # sai da bind pose e anima
	else:
		_set_paused(not _paused)


func _set_paused(p: bool) -> void:
	_paused = p
	if _anim:
		_anim.speed_scale = 0.0 if p else _anim_speed


func _apply_rest_pose() -> void:
	# forca a BIND POSE (rest): isola "malha ok" de "skinning/anim quebrado".
	# em rest o skinning devolve a malha original mesmo com peso errado — se aqui
	# estiver ok e ao animar rasgar, o defeito e' de PESO/osso (emd2gltf), nao da malha.
	if _anim:
		_anim.stop()
	if _skel:
		for i in range(_skel.get_bone_count()):
			var r := _skel.get_bone_rest(i)
			_skel.set_bone_pose_position(i, r.origin)
			_skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
			_skel.set_bone_pose_scale(i, r.basis.get_scale())
	_paused = true


func _toggle_bones() -> void:
	_bones_visible = not _bones_visible
	_bones_draw.visible = _bones_visible


func _cycle_tex() -> void:
	_tex_mode = (_tex_mode + 1) % 3
	_apply_tex_mode()


func _apply_tex_mode() -> void:
	# wireframe global via viewport
	RenderingServer.set_debug_generate_wireframes(_tex_mode == 2)
	var vp := get_viewport()
	vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if _tex_mode == 2 else Viewport.DEBUG_DRAW_DISABLED
	for mi in _all_mesh_instances():
		if _tex_mode == 1:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.8, 0.8, 0.82)
			mi.material_override = m
		else:
			mi.material_override = null


# ---------------------------------------------------------------- info/diagnostico
func _update_info(entry: Dictionary) -> void:
	var mis := _all_mesh_instances()
	var meshes := mis.size()
	var surfaces := 0
	var verts := 0
	var tris := 0
	var textures := {}
	var warns: Array = []
	var no_uv := 0
	var no_mat := 0
	for mi in mis:
		if mi.mesh == null:
			continue
		var mesh: Mesh = mi.mesh
		for s in range(mesh.get_surface_count()):
			surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(s)
			var varr = arrays[Mesh.ARRAY_VERTEX]
			if varr:
				verts += varr.size()
			var iarr = arrays[Mesh.ARRAY_INDEX]
			if iarr:
				tris += iarr.size() / 3
			elif varr:
				tris += varr.size() / 3
			if arrays[Mesh.ARRAY_TEX_UV] == null:
				no_uv += 1
			var mat: Material = mi.get_active_material(s)
			if mat == null:
				no_mat += 1
			elif mat is BaseMaterial3D:
				var t = (mat as BaseMaterial3D).albedo_texture
				if t:
					textures[t.get_rid()] = t

	var bones := 0
	if _skel:
		bones = _skel.get_bone_count()

	# monta info
	var s := "[b]%s[/b]  [color=#888](%s)[/color]\n" % [entry.name, entry.group]
	s += "malha: %d mesh · %d surf · %d verts · ~%d tris\n" % [meshes, surfaces, verts, tris]
	s += "ossos (Skeleton3D): %d\n" % bones
	s += "texturas únicas: %d" % textures.size()
	var first := true
	for t in textures.values():
		if t is Texture2D:
			s += ("  " if first else " ,") + "%dx%d" % [t.get_width(), t.get_height()]
			first = false
	s += "\n"
	s += "animações: %d" % _anim_names.size()
	if _anim and _anim_names.size() > 0:
		s += "  [%s]" % ", ".join(_anim_names)
	_lbl_info.text = s

	# avisos
	if meshes == 0:
		warns.append("SEM MALHA")
	if verts == 0:
		warns.append("0 vértices")
	if bones == 0:
		warns.append("SEM esqueleto")
	if _anim_names.size() == 0:
		warns.append("SEM animação")
	if no_uv > 0:
		warns.append("%d surf sem UV" % no_uv)
	if no_mat > 0:
		warns.append("%d surf sem material" % no_mat)
	if textures.is_empty():
		warns.append("SEM textura")
	if warns.is_empty():
		_lbl_warn.text = "[color=#4f4]✓ íntegro (malha+skin+UV+tex+anim)[/color]"
	else:
		_lbl_warn.text = "[color=#fc4]⚠ " + "  ·  ".join(warns) + "[/color]"


# ---------------------------------------------------------------- ossos (draw)
func _draw_bones() -> void:
	var im := _bones_draw.mesh as ImmediateMesh
	im.clear_surfaces()
	if _skel == null or not _bones_visible:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES, _bones_draw.material_override)
	var st := _skel.global_transform
	for i in range(_skel.get_bone_count()):
		var gp := st * _skel.get_bone_global_pose(i)
		var p := gp.origin
		var parent := _skel.get_bone_parent(i)
		if parent >= 0:
			var pp := (st * _skel.get_bone_global_pose(parent)).origin
			im.surface_add_vertex(pp)
			im.surface_add_vertex(p)
		# cruz no joint
		var c := 0.02 * _radius
		im.surface_add_vertex(p - Vector3(c, 0, 0)); im.surface_add_vertex(p + Vector3(c, 0, 0))
		im.surface_add_vertex(p - Vector3(0, c, 0)); im.surface_add_vertex(p + Vector3(0, c, 0))
		im.surface_add_vertex(p - Vector3(0, 0, c)); im.surface_add_vertex(p + Vector3(0, 0, c))
	im.surface_end()


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if _auto_rotate:
		_yaw += delta * 0.6
	if _follow and _model_root and is_instance_valid(_model_root):
		_target = _live_center() + _pan_offset
	if _follow or _auto_rotate:
		_update_camera()
	if _bones_visible:
		_draw_bones()
	var st := ""
	if _anim and _anim_names.size() > 0 and _anim_idx >= 0:
		var a := _anim.get_animation(_anim_names[_anim_idx])
		var len_s := (a.length if a else 0.0)
		var tag := ""
		if not _anim.is_playing():
			tag = "  [REST/bind — Espaço p/ animar]"
		elif _paused:
			tag = "  (pausado)"
		st += "anim: %s  %.2fs  x%.2f%s\n" % [_anim_names[_anim_idx], len_s, _anim_speed, tag]
	st += "modelo %d/%d" % [_idx + 1, _models.size()]
	_lbl_status.text = st


# ---------------------------------------------------------------- input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_radius *= 0.9; _update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_radius *= 1.1; _update_camera()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * 0.01
			_pitch += mm.relative.y * 0.01
			_update_camera()
		elif _panning:
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			var k := _radius * 0.0015
			_pan_offset += (-right * mm.relative.x + up * mm.relative.y) * k
			_update_camera()
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		match (ev as InputEventKey).keycode:
			KEY_BRACKETLEFT, KEY_LEFT: _step_model(-1)
			KEY_BRACKETRIGHT, KEY_RIGHT: _step_model(1)
			KEY_COMMA: _step_anim(-1)
			KEY_PERIOD: _step_anim(1)
			KEY_SPACE: _toggle_pause()
			KEY_B: _toggle_bones()
			KEY_T: _cycle_tex()
			KEY_G: _grid.visible = not _grid.visible
			KEY_A: _auto_rotate = not _auto_rotate
			KEY_F: _follow = not _follow
			KEY_0, KEY_KP_0: _apply_rest_pose()
			KEY_R: _frame_camera()
			KEY_EQUAL: _anim_speed = min(4.0, _anim_speed + 0.25); _refresh_speed()
			KEY_MINUS: _anim_speed = max(0.0, _anim_speed - 0.25); _refresh_speed()
			KEY_ESCAPE: get_tree().quit()


func _refresh_speed() -> void:
	if _anim and not _paused:
		_anim.speed_scale = _anim_speed


# ---------------------------------------------------------------- helpers de árvore
func _all_mesh_instances() -> Array:
	var out: Array = []
	if _model_root:
		_collect(_model_root, "MeshInstance3D", out)
	return out


func _collect(n: Node, type_name: String, out: Array) -> void:
	if n.is_class(type_name):
		out.append(n)
	for c in n.get_children():
		_collect(c, type_name, out)


func _find_node(root: Node, nm: String) -> Node:
	if root.name == nm:
		return root
	for c in root.get_children():
		var r := _find_node(c, nm)
		if r:
			return r
	return null


func _find_type(root: Node, type_name: String) -> Node:
	if root.is_class(type_name):
		return root
	for c in root.get_children():
		var r := _find_type(c, type_name)
		if r:
			return r
	return null


# centro VIVO do modelo em world-space (anula root-motion visualmente):
# com esqueleto = media das poses globais dos ossos; senao = centro do AABB de malha no mundo.
func _live_center() -> Vector3:
	if _skel and _skel.get_bone_count() > 0:
		var acc := Vector3.ZERO
		var st := _skel.global_transform
		var n := _skel.get_bone_count()
		for i in range(n):
			acc += (st * _skel.get_bone_global_pose(i)).origin
		return acc / n
	var aabb := AABB()
	var first := true
	for mi in _all_mesh_instances():
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			aabb = b; first = false
		else:
			aabb = aabb.merge(b)
	if first:
		return _model_root.global_transform.origin if _model_root else Vector3.ZERO
	return aabb.get_center()


# esconde os autoloads de gameplay (HUD de vida + EQUIP/inventario) — RE3 nao tem HUD;
# eles aparecem em toda cena por serem autoload, poluindo o visualizador.
func _hide_game_hud() -> void:
	for nm in ["HUD", "Inventory", "LangManager"]:
		var n := get_node_or_null("/root/" + nm)
		if n:
			_hide_tree(n)


func _hide_tree(n: Node) -> void:
	if "visible" in n:
		n.set("visible", false)
	n.set_process(false)
	n.set_physics_process(false)
	for c in n.get_children():
		_hide_tree(c)
