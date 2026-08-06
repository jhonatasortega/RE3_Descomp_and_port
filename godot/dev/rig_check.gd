extends Node
## Detector OBJETIVO de "parte descolada" (headless, sem render).
##
## Calcula a posição SKINADA de cada vértice em CPU (mesma conta do GPU:
##   v' = Σ w_i · (bone_global_pose[b_i] · bind_pose[b_i]) · v ),
## agrupa os vértices por OSSO dominante, e mede o VÃO entre a AABB de cada grupo
## e a AABB de todos os outros. Grupo separado de TODOS por um vão grande
## (relativo ao tamanho do corpo) = PARTE DESCOLADA.
##
## Roda em bind (rest) e em vários frames de anim. Imprime relatório e sai.
##   OUT no stdout. Env: GROUP (ENEMY|PLD), FRAMES ("rest,0,0.25,0.5,0.75"),
##   THRESH (fração do diagonal, default 0.12), LIST (paths específicos).
##
## RODAR (headless — é só matemática, não precisa de janela):
##   "<godot>" --headless --path godot res://scenes/rig_check.tscn --quit-after 2 (não; ele se fecha)

var _log: FileAccess


func _ready() -> void:
	_log = FileAccess.open("res://dev/rig_report.txt", FileAccess.WRITE)
	_run()
	if _log:
		_log.flush()
		_log.close()
	get_tree().quit()


func _p(s: String) -> void:
	print(s)
	if _log:
		_log.store_line(s)
		_log.flush()


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _run() -> void:
	var group := _env("GROUP", "ENEMY")
	var thresh := float(_env("THRESH", "0.12"))
	var stretch_thresh := float(_env("STRETCH", "0.55"))
	var frames_s := _env("FRAMES", "rest,0.0,0.5")
	var frames := frames_s.split(",")
	var list_env := _env("LIST", "")
	var paths: Array = []
	if list_env != "":
		for p in list_env.split(","):
			paths.append(p.strip_edges())
	else:
		paths = _scan("res://assets/" + group)

	_p("[rigcheck] %d modelos, thresh=%.2f×diag, frames=%s" % [paths.size(), thresh, frames_s])
	var suspects: Array = []
	for path in paths:
		var name: String = path.get_file().get_basename()
		var worst := 0.0
		var worst_detail := ""
		var model := _load_glb(path)
		if model == null:
			_p("[rigcheck] %-30s LOAD-FAIL" % name)
			continue
		add_child(model)
		var skel := _find_type(model, "Skeleton3D") as Skeleton3D
		var ap := _find_type(model, "AnimationPlayer") as AnimationPlayer
		var mi := _find_type(model, "MeshInstance3D") as MeshInstance3D
		if skel == null or mi == null or mi.mesh == null:
			_p("[rigcheck] %-30s (sem skel/mesh — %d ossos)" % [name, (skel.get_bone_count() if skel else 0)])
			model.queue_free()
			continue

		var prep := _prep(mi, skel)
		var worst_stretch := 0.0
		var stretch_detail := ""
		for fr in frames:
			_pose(ap, skel, fr.strip_edges())
			var g := _max_gap(prep, skel)
			if g.gap > worst:
				worst = g.gap
				worst_detail = "%s osso%d vão=%.2f" % [fr.strip_edges(), g.bone, g.gap]
			if g.stretch > worst_stretch:
				worst_stretch = g.stretch
				stretch_detail = "%s osso%d estica=%.2f" % [fr.strip_edges(), g.stretch_bone, g.stretch]
		var bad := worst >= thresh or worst_stretch >= stretch_thresh
		var tag := "  <<< PROBLEMA" if bad else ""
		_p("[rigcheck] %-30s vão=%.3f estica=%.3f  (%s | %s)%s" % [name, worst, worst_stretch, worst_detail, stretch_detail, tag])
		if bad:
			suspects.append({"name": name, "gap": worst, "detail": "vão %s / estica %s" % [worst_detail, stretch_detail]})
		model.queue_free()

	suspects.sort_custom(func(a, b): return a.gap > b.gap)
	_p("[rigcheck] ===== %d DESCOLADOS (>= %.2f) =====" % [suspects.size(), thresh])
	for s in suspects:
		_p("[rigcheck]   %-30s %.3f  %s" % [s.name, s.gap, s.detail])
	_p("[rigcheck] fim.")


## pré-extrai vértices + influências (bone,weight) + bind poses por osso
func _prep(mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	# bind poses (inverse-bind) por índice de OSSO
	var binds: Array = []
	binds.resize(skel.get_bone_count())
	var skin: Skin = mi.skin
	if skin:
		for i in range(skin.get_bind_count()):
			var b := skin.get_bind_bone(i)
			if b < 0:
				b = i
			if b < binds.size():
				binds[b] = skin.get_bind_pose(i)
	for i in range(binds.size()):
		if binds[i] == null:
			binds[i] = skel.get_bone_global_rest(i).affine_inverse()
	return {"verts": verts, "bones": bones, "weights": weights, "binds": binds}


## posiciona o esqueleto: "rest" = bind pose; senão frac de anim00
func _pose(ap: AnimationPlayer, skel: Skeleton3D, fr: String) -> void:
	if fr == "rest" or fr == "bind":
		if ap:
			ap.stop()
		for i in range(skel.get_bone_count()):
			var r := skel.get_bone_rest(i)
			skel.set_bone_pose_position(i, r.origin)
			skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
			skel.set_bone_pose_scale(i, r.basis.get_scale())
		return
	if ap and ap.get_animation_list().size() > 0:
		var an := ap.get_animation_list()[0]
		var a := ap.get_animation(an)
		ap.play(an)
		ap.seek(a.length * float(fr), true)
		ap.advance(0.0)


## calcula skin em CPU, agrupa por osso dominante, retorna o maior vão relativo
func _max_gap(prep: Dictionary, skel: Skeleton3D) -> Dictionary:
	var verts: PackedVector3Array = prep.verts
	var bones: PackedInt32Array = prep.bones
	var weights: PackedFloat32Array = prep.weights
	var binds: Array = prep.binds
	var nb := skel.get_bone_count()
	# matriz de skin por osso = global_pose · bind
	var sk: Array = []
	sk.resize(nb)
	for i in range(nb):
		sk[i] = skel.get_bone_global_pose(i) * binds[i]
	# AABB por osso dominante
	var mins: Array = []
	var maxs: Array = []
	var has: Array = []
	mins.resize(nb); maxs.resize(nb); has.resize(nb)
	for i in range(nb):
		has[i] = false
	var total := AABB()
	var first_total := true
	var n := verts.size()
	for vi in range(n):
		# osso dominante
		var best_b := 0
		var best_w := -1.0
		var v := verts[vi]
		for k in range(4):
			var idx := vi * 4 + k
			if idx >= bones.size():
				break
			var w := weights[idx]
			if w > best_w:
				best_w = w
				best_b = bones[idx]
		if best_b < 0 or best_b >= nb:
			continue
		# posição skinada (só o osso dominante — suficiente p/ centro de parte)
		var p: Vector3 = sk[best_b] * v
		if not has[best_b]:
			mins[best_b] = p; maxs[best_b] = p; has[best_b] = true
		else:
			mins[best_b] = (mins[best_b] as Vector3).min(p)
			maxs[best_b] = (maxs[best_b] as Vector3).max(p)
		if first_total:
			total = AABB(p, Vector3.ZERO); first_total = false
		else:
			total = total.expand(p)
	var diag: float = max(0.001, total.size.length())
	# para cada grupo: (1) vão mínimo até a UNIÃO dos outros; (2) esticão (diagonal do próprio grupo)
	var worst_gap := 0.0
	var worst_bone := -1
	var worst_stretch := 0.0
	var stretch_bone := -1
	var worst_off := 0.0
	var off_bone := -1
	for i in range(nb):
		if not has[i]:
			continue
		var sz_i: Vector3 = (maxs[i] as Vector3) - (mins[i] as Vector3)
		var stretch := sz_i.length() / diag
		if stretch > worst_stretch:
			worst_stretch = stretch
			stretch_bone = i
		# distancia do CENTRO da parte ate o proprio OSSO (o que o usuario ve:
		# "malha nao esta junto do bone"). Numa malha bone-local sã, centro~perto do osso.
		var ci: Vector3 = ((mins[i] as Vector3) + (maxs[i] as Vector3)) * 0.5
		var bo: Vector3 = skel.get_bone_global_pose(i).origin
		var off := ci.distance_to(bo) / diag
		if off > worst_off:
			worst_off = off
			off_bone = i
		# vão até a parte do OSSO-PAI (a junta real) — pega membro solto mesmo que
		# ele sobreponha outra parte em projeção
		var par := skel.get_bone_parent(i)
		if par >= 0 and has[par]:
			var ai := AABB(mins[i], sz_i)
			var apar := AABB(mins[par], (maxs[par] as Vector3) - (mins[par] as Vector3))
			var jgap := _aabb_gap(ai, apar)
			if jgap > worst_gap:
				worst_gap = jgap
				worst_bone = i
	return {"gap": worst_gap / diag, "bone": worst_bone, "stretch": worst_stretch,
			"stretch_bone": stretch_bone, "off": worst_off, "off_bone": off_bone}


## distância entre duas AABB (0 se sobrepõem/tocam)
func _aabb_gap(a: AABB, b: AABB) -> float:
	var d := Vector3.ZERO
	for ax in range(3):
		var amin := a.position[ax]
		var amax := a.position[ax] + a.size[ax]
		var bmin := b.position[ax]
		var bmax := b.position[ax] + b.size[ax]
		if amax < bmin:
			d[ax] = bmin - amax
		elif bmax < amin:
			d[ax] = amin - bmax
		else:
			d[ax] = 0.0
	return d.length()


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


func _load_glb(res_path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(res_path), st) != OK:
		return null
	return doc.generate_scene(st) as Node3D


func _find_type(root: Node, tn: String) -> Node:
	if root.is_class(tn):
		return root
	for c in root.get_children():
		var r := _find_type(c, tn)
		if r:
			return r
	return null
