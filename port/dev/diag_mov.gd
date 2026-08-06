extends SceneTree
## Movimento com o RESOLVER (0x8004af04): anda nas 4 direções, tenta entrar no armário,
## anda de ré, e mede o root motion baked dos clipes (candidato ao "deslizando").
func _initialize() -> void:
	var w := World.new()
	w.carregar("R100")
	var pad := Pad.new()
	# 1) 4 direções a partir da chegada
	for dir_i in 4:
		w.player.pos = Vector3i(-20400, 0, -20790)
		w.player.facing = dir_i * 1024
		for _i in 60:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		print("[mov] facing %4d: %s" % [dir_i * 1024, w.player.pos])
	# 2) tentar entrar no armário (reg6: x -21065..-17759, z -27660..-21772) vindo do chão
	w.player.pos = Vector3i(-19500, 0, -20200)
	w.player.facing = 0            # frente = -Z (em direção ao armário)
	for _i in 60:
		pad.set_mask(Pad.FWD)
		w.tick(pad)
	var dentro := w.player.pos.x >= -21065 and w.player.pos.x <= -17759 \
		and w.player.pos.z >= -27660 and w.player.pos.z <= -21772
	print("[mov] rumo ao armário: parou em %s · DENTRO do armário: %s (face inflada z=-21322)"
		% [w.player.pos, dentro])
	# 3) ré a partir de ponto LEGAL (fora de qualquer caixa inflada): tem de ir para trás
	# e parar na face da mesa (círculo reg12, alcance z ≈ -20797)
	w.player.pos = Vector3i(-24000, 0, -22500)
	w.player.facing = 0
	var z0 := w.player.pos.z
	for _i in 40:
		pad.set_mask(Pad.BACK)
		w.tick(pad)
	print("[mov] ré 40 ticks facing 0: z %d -> %d (%s)" % [z0, w.player.pos.z,
		"TRÁS ok" if w.player.pos.z > z0 else "ERRADO: não andou para trás"])
	# 3b) ré TANGENCIANDO o círculo: não pode ser empurrada para frente
	w.player.pos = Vector3i(-25900, 0, -22500)
	w.player.facing = 0
	var z1 := w.player.pos.z
	for _i in 30:
		pad.set_mask(Pad.BACK)
		w.tick(pad)
	print("[mov] ré tangenciando a mesa: z %d -> %d (%s)" % [z1, w.player.pos.z,
		"deslizou TRÁS ok" if w.player.pos.z > z1 else "ERRADO: presa/empurrada para frente"])
	# 3c) QUINAS: aproxima em diagonal da quina do armário — não pode congelar nem ser sugada
	for caso: Array in [[-22200, -20600, 3584], [-22200, -22400, 2560], [-20000, -20500, 512]]:
		w.player.pos = Vector3i(int(caso[0]), 0, int(caso[1]))
		w.player.facing = int(caso[2])
		var p0 := w.player.pos
		for _i in 50:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		var moveu := Vector2(float(w.player.pos.x - p0.x), float(w.player.pos.z - p0.z)).length()
		print("[mov] quina de %s facing %d: moveu %.0f un -> %s" % [p0, caso[2], moveu, w.player.pos])
	# 3d) VOLTA na sala: 8 direções × 45 ticks a partir do spawn — nenhuma pode congelar em <100 un
	var livres := 0
	for dir8 in 8:
		w.player.pos = Vector3i(-21820, 0, -21899)
		w.player.facing = dir8 * 512
		for _i in 45:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		var d8 := Vector2(float(w.player.pos.x + 21820), float(w.player.pos.z + 21899)).length()
		if d8 > 100.0:
			livres += 1
		else:
			print("[mov]   CONGELOU em facing %d (moveu %.0f)" % [dir8 * 512, d8])
	print("[mov] volta do spawn: %d/8 direções andam" % livres)
	# 4) root motion baked nos clipes do GLB (mesh desliza?)
	var m := AssetIO.model("PLD/PL00.glb")
	if m != null:
		var ap := AssetIO.anim_player(m)
		if ap != null:
			for nome in ["arm00", "arm01", "arm09"]:
				if not ap.has_animation(nome):
					continue
				var a := ap.get_animation(nome)
				var relatorio := ""
				for ti in a.get_track_count():
					if a.track_get_type(ti) != Animation.TYPE_POSITION_3D:
						continue
					var path := str(a.track_get_path(ti))
					var n_keys := a.track_get_key_count(ti)
					if n_keys < 2:
						continue
					var p0: Vector3 = a.track_get_key_value(ti, 0)
					var p1: Vector3 = a.track_get_key_value(ti, n_keys - 1)
					var d := (p1 - p0).length()
					if d > 0.05:
						relatorio += "  %s Δ=%.2f" % [path.get_slice(":", 1), d]
				print("[mov] %s: tracks de posição com deslocamento >0.05:%s" % [
					nome, relatorio if relatorio != "" else " nenhuma"])
	quit(0)
