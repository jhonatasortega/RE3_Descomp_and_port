extends SceneTree
## Escada da R101: desce do nível -3600 (passarela) para o térreo sem flutuar?
func _initialize() -> void:
	var w := World.new()
	w.carregar("R101")
	# rampas da sala
	var rampas := 0
	for r in w.room.colisao.rects:
		if r.forma in [9, 10, 12]:
			rampas += 1
			print("[esc] rampa reg forma %d raw=%s base_y=%d topo=%d sentido=%d" % [
				r.forma, [r.f0, r.f1, r.f2, r.f3], r.base_y, r.topo, (r.bits >> 4) & 3])
	print("[esc] R101 tem %d rampas · piso_padrao=%d" % [rampas, w.room.colisao.piso_padrao])
	# floor_height ao longo de uma rampa: amostra o Y pelo caminho
	for r in w.room.colisao.rects:
		if r.forma != 10:
			continue
		var meio_z := (r.f1 + r.f3) / 2
		print("[esc] perfil da rampa (z=%d): " % meio_z)
		for i in 5:
			var x := r.f0 + (r.f2 - r.f0) * i / 4
			var h := w.room.colisao.floor_height(x, meio_z, r.base_y)
			print("      x=%6d -> y=%d" % [x, h])
		break
	# a chegada da R100 (-18808,-7200,-11475): o Y rederivado mantém -7200?
	var y0 := w.room.colisao.floor_height(-18808, -11475, -7200)
	print("[esc] chegada da R100: floor_height=(-18808,-11475,-7200) -> %d" % y0)
	quit(0)
