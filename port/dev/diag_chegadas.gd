extends SceneTree
## Para CADA porta do jogo: atravessa de verdade (World.atravessar) e verifica que o player
## consegue andar (alguma das 4 direções move ≥39 un em 5 ticks). Cobre os 7 stages.
func _initialize() -> void:
	var salas: Array[String] = []
	for s in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % s)
		if d == null:
			continue
		for f in d.get_files():
			if f.length() == 9 and f.begins_with("R") and f.ends_with(".json"):
				salas.append(f.substr(0, 4))
	salas.sort()
	var total := 0
	var presas := 0
	var falha_travessia := 0
	var cross := 0
	var cross_ok := 0
	var cache := {}
	for sala in salas:
		var w: World = cache.get(sala)
		if w == null:
			w = World.new()
			if not w.carregar(sala):
				continue
			cache[sala] = w
		for porta: Aot in w.vm.portas():
			var destino := porta.to_room_id()
			if destino == "":
				continue
			total += 1
			var eh_cross := destino[1] != sala[1]
			if eh_cross:
				cross += 1
			var w2 := World.new()
			if not w2.carregar(sala):
				continue
			if not w2.atravessar(porta):
				falha_travessia += 1
				print("[chg] travessia FALHOU: %s -> %s" % [sala, destino])
				continue
			if eh_cross:
				cross_ok += 1
			# consegue andar?
			var pad := Pad.new()
			var p0 := w2.player.pos
			var moveu := false
			for dir_i in 4:
				w2.player.pos = p0
				w2.player.facing = dir_i * 1024
				for _t in 5:
					pad.set_mask(Pad.FWD)
					w2.tick(pad)
				if absi(w2.player.pos.x - p0.x) + absi(w2.player.pos.z - p0.z) >= 39:
					moveu = true
					break
			if not moveu:
				presas += 1
				print("[chg] PRESA após %s -> %s em %s" % [sala, destino, p0])
	print("[chg] TOTAL %d portas: %d travessias falharam, %d chegadas presas · cross-stage %d/%d ok" % [
		total, falha_travessia, presas, cross_ok, cross])
	quit(0)
