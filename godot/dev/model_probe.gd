extends Node3D
## Harness NÃO-interativo de validação visual dos modelos (roda sozinho, salva PNG e sai).
##
## Renderiza um MONTAGE dos .glb de um grupo num FRAME ANIMADO (default: metade da anim00),
## cada modelo numa célula própria (SubViewport isolado), com o NOME e a razão de "explosão"
## do esqueleto (posed_bbox / rest_bbox) — >~2.0 = provável rig quebrado (membros soltos).
##
## RODAR (modo cena, opengl3, ver dev/README.md — NUNCA editor/headless p/ render):
##   OUT=res://dev/enemy_probe.png GROUP=ENEMY FRAME=0.5 COLS=6 \
##   "<godot>" --path godot --rendering-driver opengl3 res://scenes/model_probe.tscn
##
## Env: GROUP (ENEMY|PLD), FRAME (0..1), OUT (png), COLS, CELL, MAXN, ANIM (nome forçado).

func _ready() -> void:
	await get_tree().process_frame
	await _run()
	get_tree().quit()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _run() -> void:
	var group := _env("GROUP", "ENEMY")
	var frame_env := _env("FRAME", "0.5").to_lower()
	var rest_mode := frame_env == "rest" or frame_env == "bind"
	var frac := float(frame_env)
	var out := _env("OUT", "res://dev/%s_probe.png" % group.to_lower())
	var cols := int(_env("COLS", "6"))
	var cell := int(_env("CELL", "320"))
	var maxn := int(_env("MAXN", "999"))
	var force_anim := _env("ANIM", "")

	var list_env := _env("LIST", "")
	var paths: Array = []
	if list_env != "":
		for p in list_env.split(","):
			paths.append(p.strip_edges())
	else:
		paths = _scan("res://assets/" + group)
	if paths.size() > maxn:
		paths = paths.slice(0, maxn)
	if paths.is_empty():
		push_error("nenhum glb em assets/" + group)
		return

	var n := paths.size()
	var rows := int(ceil(float(n) / cols))
	var montage := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	montage.fill(Color(0.08, 0.09, 0.11))

	var report: Array = []
	for i in range(n):
		var res := await _render_one(paths[i], cell, frac, force_anim, rest_mode)
		var img: Image = res.img
		if img:
			montage.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
		report.append({"name": paths[i].get_file().get_basename(), "ratio": res.ratio, "bones": res.bones, "anim": res.anim})
		print("[probe] %-30s ratio=%.2f bones=%d anim=%s" % [paths[i].get_file(), res.ratio, res.bones, res.anim])

	var gout := ProjectSettings.globalize_path(out)
	montage.save_png(gout)
	# resumo dos suspeitos (ratio alto = provável rig quebrado)
	report.sort_custom(func(a, b): return a.ratio > b.ratio)
	print("[probe] === TOP suspeitos (ratio de explosao do esqueleto) ===")
	for r in report.slice(0, 12):
		print("[probe]   %-30s ratio=%.2f (bones=%d)" % [r.name, r.ratio, r.bones])
	print("[probe] montage salvo em: " + gout)


func _scan(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not da.current_is_dir() and f.to_lower().ends_with(".glb"):
			out.append(dir + "/" + f)
		f = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _render_one(path: String, cell: int, frac: float, force_anim: String, rest_mode: bool) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(cell, cell)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 1.0
	we.environment = e
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	vp.add_child(light)

	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 10000.0
	vp.add_child(cam)

	var ratio := 0.0
	var bones := 0
	var anim_name := "-"
	var model := _load_glb(path)
	if model:
		vp.add_child(model)
		var skel := _find_type(model, "Skeleton3D") as Skeleton3D
		var ap := _find_type(model, "AnimationPlayer") as AnimationPlayer
		if skel:
			bones = skel.get_bone_count()
		# mede bind-bbox do esqueleto
		var bind_sz := _skel_bbox(skel)
		# aplica pose: bind (rest) OU animada
		if rest_mode:
			if skel:
				for bi in range(skel.get_bone_count()):
					var r := skel.get_bone_rest(bi)
					skel.set_bone_pose_position(bi, r.origin)
					skel.set_bone_pose_rotation(bi, r.basis.get_rotation_quaternion())
					skel.set_bone_pose_scale(bi, r.basis.get_scale())
			anim_name = "REST"
		elif ap and ap.get_animation_list().size() > 0:
			var names := ap.get_animation_list()
			var an := force_anim if (force_anim != "" and ap.has_animation(force_anim)) else names[0]
			anim_name = an
			var a := ap.get_animation(an)
			ap.play(an)
			ap.seek(a.length * frac, true)
			ap.advance(0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		var posed_sz := _skel_bbox(skel)
		ratio = (posed_sz / bind_sz) if bind_sz > 0.001 else 1.0
		# enquadra pelo centro vivo
		_frame(cam, model, skel)
		# rotulo
		var lbl := Label3D.new()
		lbl.text = "%s\nb%d  r%.1f" % [path.get_file().get_basename(), bones, ratio]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color.RED if ratio > 2.0 else Color.WHITE
		lbl.pixel_size = 0.0016
		lbl.position = _live_center(model, skel) + Vector3(0, _frame_radius(model, skel) * 0.7, 0)
		vp.add_child(lbl)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return {"img": img, "ratio": ratio, "bones": bones, "anim": anim_name}


func _skel_bbox(skel: Skeleton3D) -> float:
	if skel == null or skel.get_bone_count() == 0:
		return 0.0
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for i in range(skel.get_bone_count()):
		var p := skel.get_bone_global_pose(i).origin
		mn = mn.min(p)
		mx = mx.max(p)
	return (mx - mn).length()


func _live_center(model: Node3D, skel: Skeleton3D) -> Vector3:
	if skel and skel.get_bone_count() > 0:
		var acc := Vector3.ZERO
		var st := skel.global_transform
		for i in range(skel.get_bone_count()):
			acc += (st * skel.get_bone_global_pose(i)).origin
		return acc / skel.get_bone_count()
	return model.global_transform.origin


func _frame_radius(model: Node3D, skel: Skeleton3D) -> float:
	var sz := _skel_bbox(skel)
	if sz <= 0.001:
		var aabb := _mesh_aabb(model)
		sz = aabb.size.length()
	return max(0.5, sz)


func _frame(cam: Camera3D, model: Node3D, skel: Skeleton3D) -> void:
	var c := _live_center(model, skel)
	var r := _frame_radius(model, skel) * 1.6
	var dir := Vector3(0.35, 0.15, 1.0).normalized()
	cam.global_position = c + dir * r
	cam.look_at(c, Vector3.UP)


func _mesh_aabb(model: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	var mis: Array = []
	_collect(model, "MeshInstance3D", mis)
	for mi in mis:
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			aabb = b; first = false
		else:
			aabb = aabb.merge(b)
	if first:
		return AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	return aabb


func _load_glb(res_path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(res_path), st)
	if err != OK:
		var packed = load(res_path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate()
		return null
	return doc.generate_scene(st) as Node3D


func _collect(n: Node, tn: String, out: Array) -> void:
	if n.is_class(tn):
		out.append(n)
	for c in n.get_children():
		_collect(c, tn, out)


func _find_type(root: Node, tn: String) -> Node:
	if root.is_class(tn):
		return root
	for c in root.get_children():
		var r := _find_type(c, tn)
		if r:
			return r
	return null
