extends SceneTree
func _initialize() -> void:
	for rel: String in ["PLD/PL00.glb", "PLD/PL00W00.glb", "PLD/PL00W01.glb",
			"PLD/PL00W01_WPN.glb"]:
		var m := AssetIO.model(rel)
		if m == null:
			print("[gl] %s -> ausente" % rel)
			continue
		var ap := AssetIO.anim_player(m)
		var lista: PackedStringArray = ap.get_animation_list() if ap != null else PackedStringArray()
		var malhas := 0
		var pilha: Array[Node] = [m]
		while not pilha.is_empty():
			var n: Node = pilha.pop_back()
			if n is MeshInstance3D:
				malhas += 1
			for c in n.get_children():
				pilha.append(c)
		print("[gl] %-22s malhas=%d clipes=%d" % [rel, malhas, lista.size()])
		if lista.size() > 0:
			var s := ""
			for i in mini(lista.size(), 46):
				s += lista[i] + " "
			print("[gl]    %s" % s)
	quit(0)
