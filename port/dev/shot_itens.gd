extends SceneTree
## Render POR ITEM: prova visual de que a MALHA REAL do jogo (OMODEL) entra na cena, na posição
## e rotação do `0x7f`. Põe a Jill em cima do item e deixa o RVD escolher a câmera — que é a
## mesma que o jogador veria ao chegar lá.
##
## env: ITEM_SALAS="R104,R108" (padrão abaixo) · salva `_shot_item_<sala>_a<aot>.png`.
var _cena: Node
var _t := 0
var _fila: Array = []       ## [[sala, aot_id], ...]
var _i := 0
var _salas: Array[String] = []
var _s := 0


func _initialize() -> void:
	var env := OS.get_environment("ITEM_SALAS")
	for s: String in (env if env != "" else "R104,R108,R414").split(","):
		_salas.append(s.strip_edges())
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)


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
	# fase 1: carrega a sala e monta a fila de itens dela
	if _fila.is_empty():
		if _s >= _salas.size():
			return true
		var sala := _salas[_s]
		_s += 1
		if not _cena.call("carregar_sala", sala):
			print("[shot] %s nao carregou" % sala)
			return false
		var mundo: Object = _cena.get("mundo")
		for a: Object in mundo.call("itens_no_chao"):
			_fila.append([sala, a])
		_i = 0
		print("[shot] %s: %d item(ns) na fila" % [sala, _fila.size()])
		return false
	# fase 2: um item por frame par
	if _t % 6 != 0:
		return false
	if _i >= _fila.size():
		_fila.clear()
		return false
	var par: Array = _fila[_i]
	_i += 1
	var sala: String = par[0]
	var a: Object = par[1]
	var mundo: Object = _cena.get("mundo")
	var obj: Object = mundo.call("objeto_do_item", a)
	if obj == null or not obj.call("posicionado"):
		print("[shot] %s aot%d item0x%02x om=%d: sem objeto posicionado (nada a ver)" % [
			sala, a.get("id"), a.get("item_id"), a.get("item_om")])
		return false
	var p: Vector3i = obj.get("pos")
	# a Jill EM CIMA do item: assim a câmera escolhida pelo RVD é a que enquadra o item
	var player: Object = mundo.get("player")
	player.set("pos", Vector3i(p.x, p.y, p.z))
	mundo.call("tick", _cena.get_node("/root/Game").get("pad"))
	_cena.call("_montar_itens")
	_cena.call("_on_tick", _t)
	# tamanho da malha em unidades PS1: um item de chão deve ter algumas centenas
	for n: Node3D in _cena.get("itens_nodes"):
		if not n.name.ends_with("om%d" % a.get("item_om")):
			continue
		var caixa := _aabb(n)
		print("[shot]   malha %s: AABB %s un PS1 · base y=%s" % [n.name,
			(caixa.size * Coords.WORLD_SCALE).round(),
			roundi(caixa.position.y * Coords.WORLD_SCALE)])
	if OS.get_environment("ITEM_PERTO") != "":
		# câmera de perto, dentro do MESMO SubViewport onde os itens vivem (`screen.world`)
		var vp: SubViewport = _cena.get("world")
		var cam := Camera3D.new()
		vp.add_child(cam)
		var alvo := Coords.to_godot_i(p.x, p.y, p.z)
		cam.position = alvo + Vector3(0.9, 0.7, 0.9)
		cam.look_at(alvo)
		cam.fov = 40.0
		cam.make_current()
	var img := get_root().get_texture().get_image()
	var nome := "_shot_item_%s_a%d.png" % [sala, a.get("id")]
	img.save_png(ProjectSettings.globalize_path("res://%s" % nome))
	print("[shot] %s · aot%d item0x%02x om=%d obj%s rot%s · cam %d -> %s" % [
		sala, a.get("id"), a.get("item_id"), a.get("item_om"), p, obj.get("rot"),
		mundo.get("camera"), nome])
	return false
