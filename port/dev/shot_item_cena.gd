extends SceneTree
## Render do item NA CENA pelo caminho normal: sala carregada, ator ao lado do item, câmera
## escolhida pelo RVD (`best_camera_for`). Salva `_shot_cena_<sala>_a<aot>.png`.
##
## env: CENA_SALA=R108 · CENA_AOT=<id> (padrão: o primeiro item com objeto posicionado)
var _cena: Node
var _t := 0
var _feito := false
var _nome := ""
var _proj := Vector2.ZERO
var _espera := 0


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	# os recortes de máscara podem cobrir o item e o personagem (é o bug de camada de máscara,
	# separado disto) — para CONFERIR o item, desliga a oclusão.
	if OS.get_environment("CENA_MASCARA") == "":
		_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _t < 5:
		return false
	if _feito:
		_espera += 1
		if _espera < 3:
			return false
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://%s" % _nome))
		print("[cena] salvo %s" % _nome)
		# recorte ampliado 4x em volta do item: é onde se vê se a malha casa com o cenário
		var lado := 160
		var r := Rect2i(int(_proj.x) - lado / 2, int(_proj.y) - lado / 2, lado, lado)
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if r.size.x > 8 and r.size.y > 8:
			var corte := img.get_region(r)
			corte.resize(r.size.x * 4, r.size.y * 4, Image.INTERPOLATE_NEAREST)
			var nz := _nome.replace(".png", "_zoom.png")
			corte.save_png(ProjectSettings.globalize_path("res://%s" % nz))
			print("[cena] salvo %s (recorte %s ampliado 4x)" % [nz, r])
		return true
	var sala := OS.get_environment("CENA_SALA")
	if sala == "":
		sala = "R108"
	if not _cena.call("carregar_sala", sala):
		print("[cena] %s nao carregou" % sala)
		return true
	var mundo: Object = _cena.get("mundo")
	var escolhido: Object = null
	var alvo := OS.get_environment("CENA_AOT")
	for a: Object in mundo.call("itens_no_chao"):
		var obj: Object = mundo.call("objeto_do_item", a)
		if obj == null or not obj.call("posicionado"):
			continue
		if alvo != "" and str(a.get("id")) != alvo:
			continue
		escolhido = a
		break
	if escolhido == null:
		print("[cena] %s nao tem item com objeto posicionado" % sala)
		return true
	var obj: Object = mundo.call("objeto_do_item", escolhido)
	var p: Vector3i = obj.get("pos")
	# ator 900 unidades ao lado (não dentro do móvel) e no piso do lugar
	var px := p.x + 900
	var pz := p.z + 900
	var col: Object = mundo.get("room").get("colisao")
	var py: int = col.call("floor_height", px, pz, p.y) if col != null else p.y
	var player: Object = mundo.get("player")
	player.set("pos", Vector3i(px, py, pz))
	player.set("facing", 0)
	# escolhe a câmera que REALMENTE enquadra o item: projeta o ponto com a Camera3D montada
	# pelo CameraRID e testa se cai dentro da tela. `best_camera_for` responde outra pergunta
	# (a zona do RVD onde o jogador está), e para conferir visual isso não serve.
	var room: Object = mundo.get("room")
	var n_cams: int = (room.get("cameras") as Array).size()
	var alvo3d := Coords.to_godot_i(p.x, p.y, p.z)
	var cam := -1
	for i in n_cams:
		_cena.call("mostrar_camera", i)
		var c3d: Camera3D = _cena.get("cam3d")
		if c3d.is_position_behind(alvo3d):
			continue
		var s := c3d.unproject_position(alvo3d)
		if s.x > 40.0 and s.x < 1240.0 and s.y > 60.0 and s.y < 900.0:
			cam = i
			break
	if cam < 0:
		print("[cena] nenhuma das %d câmeras enquadra o item" % n_cams)
		cam = 0
	mundo.get("rvd").set("camera", cam)
	mundo.set("camera", cam)
	_cena.call("mostrar_camera", cam)
	_cena.call("_montar_itens")
	_cena.call("_on_tick", _t)
	# o `_on_tick` roda o mundo, e o RVD volta a escolher a câmera pela ZONA onde o player está
	# — que não é a que enquadra o item. Congela o relógio e refaz a câmera escolhida.
	var g: Node = _cena.get_node_or_null("/root/Game")
	if g != null and g.get("clock") != null:
		(g.get("clock") as Object).set("paused", true)
	_cena.call("mostrar_camera", cam)
	# o ator tapa itens pequenos (a chave na parede da R100) — esconde para conferir o item
	if OS.get_environment("CENA_ATOR") == "":
		var ac: Node3D = _cena.get("actor")
		if ac != null:
			ac.visible = false
	# guarda a projeção do item para recortar/ampliar o PNG depois
	var c3d: Camera3D = _cena.get("cam3d")
	_proj = c3d.unproject_position(alvo3d)
	print("[cena] projeção do item na tela: %s" % _proj.round())
	var nodes: Array = _cena.get("itens_nodes")
	print("[cena] %s aot%d item0x%02x om=%d obj%s rot%s · ator(%d,%d,%d) · cam %d · %d nó(s)" % [
		sala, escolhido.get("id"), escolhido.get("item_id"), escolhido.get("item_om"), p,
		obj.get("rot"), px, py, pz, cam, nodes.size()])
	# o PNG só pode ser lido no frame SEGUINTE: `get_texture()` devolve o último frame JÁ
	# renderizado, então salvar aqui grava a sala anterior (foi o que aconteceu na 1ª tentativa).
	_nome = "_shot_cena_%s_a%d.png" % [sala, escolhido.get("id")]
	_feito = true
	return false
