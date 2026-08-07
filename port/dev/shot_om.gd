extends SceneTree
## Render ISOLADO de modelos de objeto de sala (`assets/OMODEL/<sala>/om<N>.glb`): prova que a
## malha decodificada existe, tem escala de item e textura. Grade de 1000 unidades PS1 no piso
## para dar referência de tamanho.
##
## env: OM_LISTA="R104:1,R104:4,R108:4" · OM_ROT="640,512,0" (opcional, em unidades PS1)
var _t := 0


func _initialize() -> void:
	var lista := OS.get_environment("OM_LISTA")
	if lista == "":
		lista = "R104:1,R104:4,R108:4"
	var raiz := Node3D.new()
	get_root().add_child(raiz)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	luz.light_energy = 1.4
	raiz.add_child(luz)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.8
	amb.environment = env
	raiz.add_child(amb)

	var passo := Coords.len_to_godot(1000.0)          ## 1000 unidades PS1 entre modelos
	var i := 0
	for item: String in lista.split(","):
		var par := item.strip_edges().split(":")
		if par.size() != 2:
			continue
		var rel := "OMODEL/%s/om%s.glb" % [par[0], par[1]]
		if not AssetIO.exists(rel):
			print("[om] %s nao existe" % rel)
			continue
		var no := AssetIO.model(rel)
		if no == null:
			print("[om] %s nao carregou" % rel)
			continue
		raiz.add_child(no)
		no.position = Vector3(i * passo, 0.0, 0.0)
		var rot := OS.get_environment("OM_ROT")
		if rot != "":
			var e := rot.split(",")
			no.basis = Coords.basis_from_ps1_rot(Vector3i(int(e[0]), int(e[1]), int(e[2])))
		var caixa := _aabb(no)
		print("[om] %s: AABB %s un PS1 (base y=%d)" % [rel,
			(caixa.size * Coords.WORLD_SCALE).round(),
			roundi(caixa.position.y * Coords.WORLD_SCALE)])
		# piso de referência sob o modelo (1000x1000 unidades PS1)
		var piso := MeshInstance3D.new()
		var plano := PlaneMesh.new()
		plano.size = Vector2(passo * 0.9, passo * 0.9)
		piso.mesh = plano
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.27, 0.3)
		piso.material_override = mat
		raiz.add_child(piso)
		piso.position = Vector3(i * passo, 0.0, 0.0)
		i += 1
	var cam := Camera3D.new()
	raiz.add_child(cam)
	var centro := Vector3(maxf(0.0, (i - 1)) * passo * 0.5, Coords.len_to_godot(250.0), 0.0)
	cam.look_at_from_position(
		centro + Vector3(0.0, Coords.len_to_godot(700.0), passo * maxf(1.4, i * 0.9)),
		centro, Vector3.UP)
	cam.fov = 45.0
	cam.make_current()


func _aabb(n: Node) -> AABB:
	var caixa := AABB()
	var primeiro := true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b := mi.get_aabb()
		b.position += mi.position
		if primeiro:
			caixa = b
			primeiro = false
		else:
			caixa = caixa.merge(b)
	return caixa


func _process(_d: float) -> bool:
	_t += 1
	if _t < 4:
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shot_om.png"))
	print("[om] salvo _shot_om.png")
	return true
