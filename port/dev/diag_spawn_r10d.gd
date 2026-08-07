extends SceneTree
## Acha um ponto CAMINHÁVEL em R10D para o spawn de jogo novo (o usuário informou que é a
## primeira sala do jogo, com cinemática em R10D_2). Varre uma grade no nível 0 e reporta os
## pontos que o resolver aceita, com a câmera que o RVD escolhe em cada um.
func _initialize() -> void:
	var sala := OS.get_environment("SPAWN_SALA")
	if sala == "":
		sala = "R10D"
	var w := World.new()
	if not w.carregar(sala):
		print("[sp] %s nao carregou" % sala)
		quit(1)
		return
	var col := w.room.colisao
	print("[sp] %s: %d camaras · %d rects de colisao" % [sala, w.room.cameras.size(),
		col.rects.size() if col != null else 0])
	var cam0: RoomData.Camera = w.room.cameras[0]
	print("[sp] cam0 from=%s to=%s" % [cam0.from_ps1, cam0.to_ps1])
	# grade em volta do alvo da camera 0
	var alvo := cam0.to_ps1
	var achados := 0
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var x := alvo.x + dx * 800
			var z := alvo.z + dz * 800
			var y := col.floor_height(x, z, 0) if col != null else 0
			w.player.pos = Vector3i(x, y, z)
			# tenta andar nas 4 direcoes: se alguma anda, o ponto e livre
			var livre := false
			for ang: int in [0, 1024, 2048, 3072]:
				w.player.facing = ang
				var antes := w.player.pos
				var pad := Pad.new()
				pad.set_mask(Pad.FWD)
				w.tick(pad)
				if w.player.pos != antes:
					livre = true
				w.player.pos = Vector3i(x, y, z)
			if livre:
				achados += 1
				if achados <= 6:
					var c := CameraRVD.best_camera_for(w.room, x, z)
					print("[sp]   livre em (%d, %d, %d) · camera %d" % [x, y, z, c])
	print("[sp] %d pontos livres na grade" % achados)
	quit(0)
