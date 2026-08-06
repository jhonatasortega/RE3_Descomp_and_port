extends SceneTree
## Reproduz o relato: (-22161,-21741) facing 3628, W pressionado. Quem barra?
func _initialize() -> void:
	var w := World.new()
	w.carregar("R100")
	var pad := Pad.new()
	# 1) andar para frente do ponto exato do relato
	w.player.pos = Vector3i(-22161, 0, -21741)
	w.player.facing = 3628
	var p0 := w.player.pos
	for i in 30:
		var antes := w.player.pos
		pad.set_mask(Pad.FWD)
		w.tick(pad)
		if w.player.pos == antes and i < 3:
			print("[spot] tick %d: NÃO MOVEU de %s" % [i, antes])
	print("[spot] facing 3628: %s -> %s (moveu %.0f un)" % [p0, w.player.pos,
		Vector2(float(w.player.pos.x - p0.x), float(w.player.pos.z - p0.z)).length()])
	# 2) diagnóstico do resolver no primeiro passo
	var passo := PS1Math.rotate_xz(0, -78, 3628)
	print("[spot] passo de 1 tick = (%d, %d)" % [passo.x, passo.y])
	var res := w.room.colisao.resolver(p0.x, p0.z, p0.x + passo.x, p0.z + passo.y, 0)
	print("[spot] resolver: (%d,%d) -> (%d,%d) empurrado=%s rejeitado=%s quem=%s" % [
		p0.x + passo.x, p0.z + passo.y, res.x, res.z, res.empurrado, res.rejeitado,
		("reg raw=%s forma=%d mask=%04x" % [
			[res.quem.f0, res.quem.f1, res.quem.f2, res.quem.f3], res.quem.forma, res.quem.mask])
			if res.quem != null else "-"])
	# 3) as 8 direções a partir do ponto: quais andam?
	for d8 in 8:
		w.player.pos = Vector3i(-22161, 0, -21741)
		w.player.facing = d8 * 512
		for _i in 10:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		var dd := Vector2(float(w.player.pos.x + 22161), float(w.player.pos.z + 21741)).length()
		print("[spot] facing %4d: moveu %4.0f -> %s" % [d8 * 512, dd, w.player.pos])
	# 4) ALINHAMENTO render x movimento: para cada facing, o passo tem de apontar para onde
	# o modelo olha: forward_ps1 = (-sin, +cos)
	var pior := 0.0
	for a in [0, 512, 1024, 2048, 3072, 3628]:
		var passo2 := Vector2((-PS1Math.rsin(a) * 78.0) / 4096.0, (PS1Math.rcos(a) * 78.0) / 4096.0)
		var fwd := Vector2(-sin(deg_to_rad(PS1Math.to_deg(a))), cos(deg_to_rad(PS1Math.to_deg(a)))) * 78.0
		pior = maxf(pior, (passo2 - fwd).length())
	print("[spot] alinhamento passo x forward do render: erro máximo %.2f un (tem de ser <2)" % pior)
	quit(0)
