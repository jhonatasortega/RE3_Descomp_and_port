extends SceneTree
## Por que a arma não aparece: reporta cada etapa do anexo no punho.
var _cena: Node
var _t := 0

func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)

func _process(_d: float) -> bool:
	_t += 1
	if _t < 5:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var st: Object = g.get("state")
	_cena.call("_on_tick", _t)
	print("[am] item equipado=0x%02x · caminho=%s" % [st.call("equipped_item_id"),
		_cena.call("arma_da_mao", st.call("equipped_item_id"))])
	print("[am] weapon_model=%s · _arma_atual=%s" % [_cena.get("weapon_model"),
		_cena.get("_arma_atual")])
	var malha: Node = _cena.get("actor_mesh")
	print("[am] actor_mesh=%s" % malha)
	var esq: Node = null
	var pilha: Array[Node] = []
	if malha != null:
		pilha.append(malha)
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		if n is Skeleton3D:
			esq = n
			break
		for c in n.get_children():
			pilha.append(c)
	print("[am] skeleton=%s ossos=%s" % [esq, (esq as Skeleton3D).get_bone_count() if esq else -1])
	if esq != null:
		var att: Node = esq.get_node_or_null("WeaponAttach")
		print("[am] WeaponAttach=%s" % att)
		if att != null:
			var a3 := att as BoneAttachment3D
			print("[am]   osso=%s visivel=%s pos_global=%s filhos=%d"
				% [a3.bone_name, a3.visible, a3.global_position, a3.get_child_count()])
			for c in a3.get_children():
				var mi := c as Node3D
				print("[am]   filho %s visivel=%s pos=%s escala=%s"
					% [mi.name, mi.visible, mi.global_position, mi.scale])
	return true
