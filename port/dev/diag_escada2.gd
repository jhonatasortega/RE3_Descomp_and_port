extends SceneTree
## Desce a rampa da R101 e verifica: Y desce, nível muda, e a CÂMERA troca junto.
func _initialize() -> void:
	var w := World.new()
	w.carregar("R101")
	w.player.pos = Vector3i(-28000, -7200, -22400)   # topo da rampa (nível 4)
	w.player.facing = 0                               # frente = -Z (desce a rampa)
	w.rvd.camera = 4
	w.camera = 4
	CameraRVD.matar_supressora(w.room, w.rvd, 4)   # entrada em câmera exclui a supressora
	var pad := Pad.new()
	var trocas: Array[String] = []
	for i in 70:
		var cam_antes := w.camera
		pad.set_mask(Pad.FWD)
		w.tick(pad)
		if w.camera != cam_antes:
			trocas.append("cam %d->%d em %s (nível %d)" % [
				cam_antes, w.camera, w.player.pos, w.player.nivel()])
		if i % 14 == 0:
			print("[esc2] tick %2d: pos=%s nível=%d grupo=%d câmera=%d" % [
				i, w.player.pos, w.player.nivel(), w.rvd.grupo, w.camera])
	print("[esc2] trocas de câmera na descida: %d  %s" % [trocas.size(), " | ".join(trocas)])
	quit(0)
