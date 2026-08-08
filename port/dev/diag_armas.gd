extends SceneTree
## Mede a malha de cada `PL00W{nn}_WPN.glb` (tamanho da AABB e nº de vértices) para identificar
## qual arma é qual sem depender de olhar: faca é comprida e fina, pistola é curta, escopeta longa.
func _initialize() -> void:
	for i in 12:
		var rel := "PLD/PL00W%02d_WPN.glb" % i
		if not AssetIO.exists(rel):
			print("[ar] W%02d  (sem malha separada)" % i)
			continue
		var m := AssetIO.model(rel)
		if m == null:
			continue
		var ab := AABB()
		var n := 0
		var pilha: Array[Node] = [m]
		while not pilha.is_empty():
			var no: Node = pilha.pop_back()
			if no is MeshInstance3D:
				var mi := no as MeshInstance3D
				var a := mi.get_aabb()
				ab = a if n == 0 else ab.merge(a)
				n += mi.mesh.get_surface_count()
			for c in no.get_children():
				pilha.append(c)
		var t := ab.size * Coords.WORLD_SCALE      ## em unidades PS1
		print("[ar] W%02d  %6.0f x %6.0f x %6.0f un PS1  (maior lado %.0f)"
			% [i, t.x, t.y, t.z, maxf(maxf(t.x, t.y), t.z)])
	quit(0)
