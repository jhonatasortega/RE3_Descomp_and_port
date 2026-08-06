extends SceneTree
## Contraprova do diag_real: os pontos onde o JOGO REAL parou com W seguram também no
## mundo.tick DIRETO (mesma sala, pos, facing)? Se sim, é colisão legítima (mesma nos dois
## caminhos); se o direto ANDAR, a divergência real-vs-isolado está achada.
func _initialize() -> void:
	var w := World.new()
	w.carregar("R100")
	var pad := Pad.new()
	# [ponto, facing, rótulo]
	var casos: Array = [
		[Vector3i(-23217, 0, -26636), 0, "congelamento ticks 993..1080 (W, rumo -Z)"],
		[Vector3i(-23217, 0, -26636), 0, "mesmo ponto, W+SHIFT"],
		[Vector3i(-23600, 0, -20784), 2340, "parada da fase 9 (tick 600)"],
	]
	var i := 0
	for caso: Array in casos:
		w.player.pos = caso[0]
		w.player.facing = int(caso[1])
		var p0: Vector3i = w.player.pos
		var m := Pad.FWD | Pad.RUN if i == 1 else Pad.FWD
		for _t in 60:
			pad.set_mask(m)
			w.tick(pad)
		var d := absi(w.player.pos.x - p0.x) + absi(w.player.pos.z - p0.z)
		print("[iso] %-40s: %s -> %s (%d un) %s" % [caso[2], p0, w.player.pos, d,
			"PAROU IGUAL ao jogo real" if d < 50 else "ANDOU (diverge do jogo real!)"])
		i += 1
	quit()
