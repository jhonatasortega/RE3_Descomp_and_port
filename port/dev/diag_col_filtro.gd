extends SceneTree
## Para a posição da Jill em R10D, diz qual FILTRO do resolvedor rejeita cada registro que
## envolve o ponto. Cada filtro traz o endereço do EXE de onde saiu.
func _initialize() -> void:
	var w := World.new()
	if not w.carregar("R10D"):
		print("[cf] falhou carregar R10D")
		quit(1)
		return
	var col: Collision = w.room.colisao
	var px := 17044
	var pz := -13679
	print("[cf] R10D · %d registros · jill=(%d,%d) · centro1=%s centro2=%s"
		% [col.rects.size(), px, pz, str(col.centro1), str(col.centro2)])
	var cod := col.quadrante(px, pz, col.centro1, col.centro2)
	print("[cf] quadrante do ponto = 0x%02x" % cod)
	for i in col.rects.size():
		var r: Collision.Rect = col.rects[i]
		var envolve := px >= r.f0 - 300 and px <= r.f2 + 300 and pz >= r.f1 - 300 and pz <= r.f3 + 300
		if not envolve:
			continue
		var por := []
		if (r.bits & Collision.MASCARA_RESOLVER) == 0:
			por.append("bits&0x4000=0 (0x8004b038)")
		var nivel_lo := r.base_y / -Collision.ALTURA_POR_NIVEL
		if 0 < nivel_lo or r.nivel < 0:
			por.append("nivel [%d..%d] (0x8004b054)" % [nivel_lo, r.nivel])
		if (r.mask & cod) != cod:
			por.append("quadrante mask=0x%04x cod=0x%02x (0x8004b020)" % [r.mask, cod])
		print("[cf]  %2d forma=%2d bits=0x%04x mask=0x%04x base_y=%5d nivel=%d x[%d..%d] z[%d..%d] %s"
			% [i, r.forma, r.bits, r.mask, r.base_y, r.nivel, r.f0, r.f2, r.f1, r.f3,
			("REJEITADO: " + ", ".join(por)) if not por.is_empty() else "PASSA"])
	# e o teste real: o resolvedor empurra?
	for d: Vector2i in [Vector2i(0, -400), Vector2i(400, 0), Vector2i(0, 400), Vector2i(-400, 0)]:
		var res: Collision.Resolvido = col.resolver(px, pz, px + d.x, pz + d.y, 0)
		print("[cf] andar %s -> (%d,%d) empurrado=%s" % [str(d), res.x, res.z, res.empurrado])
	quit(0)
