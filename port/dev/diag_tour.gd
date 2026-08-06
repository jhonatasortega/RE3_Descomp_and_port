extends SceneTree
## Passeio de 500 ticks por sala (anda + gira 45° a cada 25 ticks): mede área visitada e
## travamentos (ticks parados apesar de W). É a simulação do "andar pelo mapa" do usuário.
func _initialize() -> void:
	for caso: Array in [["R100", -20400, 0, -20790], ["R101", -18808, -7200, -11475],
			["R11D", -5450, -3600, -26750], ["R200", -1625, 0, 12210]]:
		var w := World.new()
		if not w.carregar(caso[0]):
			print("[tour] %s NÃO CARREGOU" % caso[0])
			continue
		w.player.pos = Vector3i(int(caso[1]), int(caso[2]), int(caso[3]))
		w.player.facing = 0
		var pad := Pad.new()
		var parado := 0
		var pior_seq := 0
		var seq := 0
		var celulas := {}
		for i in 500:
			if i % 25 == 24:
				w.player.facing = PS1Math.wrap_angle(w.player.facing + 512)
			var antes := w.player.pos
			pad.set_mask(Pad.FWD)
			w.tick(pad)
			celulas[Vector2i(w.player.pos.x / 400, w.player.pos.z / 400)] = true
			if w.player.pos == antes:
				parado += 1
				seq += 1
				pior_seq = maxi(pior_seq, seq)
			else:
				seq = 0
		print("[tour] %s: %d células de 400un visitadas · %d/500 ticks parado · pior sequência %d · fim %s" % [
			caso[0], celulas.size(), parado, pior_seq, w.player.pos])
	quit(0)
