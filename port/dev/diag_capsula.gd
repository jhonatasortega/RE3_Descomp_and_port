extends SceneTree
## Cápsula (formas 2/3) em bancada: imprime a geometria derivada e o empurrão em pontos-chave,
## para conferir contra o disassembly de `0x8004c57c` / `0x8004c6ec` / `0x8004c408`.
func _initialize() -> void:
	for caso: Array in [
			[2, -2000, -500, 2000, 500, 200],
			[3, -500, -2000, 500, 2000, 200],
			[2, -6000, -1000, 6000, 1000, 450],
			[2, -5000, -4000, 5000, 4000, 450],
			[2, -500, -2000, 500, 2000, 450]]:
		var forma := int(caso[0])
		var c := Collision.new()
		var r := Collision.Rect.new()
		r.f0 = int(caso[1]); r.f1 = int(caso[2]); r.f2 = int(caso[3]); r.f3 = int(caso[4])
		r.forma = forma
		r.bits = 0xFE40 | forma
		r.mask = 0x0FFF
		r.topo = -1800
		r.envolve()
		c.rects.append(r)
		var raio := int(caso[5])
		var span := (r.f3 - r.f1) if forma == 2 else (r.f2 - r.f0)
		var h := span >> 1
		var lo := (r.f0 if forma == 2 else r.f1) + h
		var hi := (r.f2 if forma == 2 else r.f3) - h
		print("\n[cp] forma=%d x[%d..%d] z[%d..%d] raio=%d · h=%d lo=%d hi=%d alcance=%d"
			% [forma, r.f0, r.f2, r.f1, r.f3, raio, h, lo, hi, h + raio])
		print("[cp]    ponta lo=(%d,%d) ponta hi=(%d,%d)" % [
			r.f0 + h, r.f1 + h,
			(r.f2 - span + h) if forma == 2 else (r.f0 + h),
			(r.f1 + h) if forma == 2 else (r.f3 - span + h)])
		var pts: Array = []
		if forma == 2:
			pts = [Vector2i(0, 0), Vector2i(0, 400), Vector2i(2150, 0), Vector2i(2150, 650),
				Vector2i(1924, 424), Vector2i(1100, 0), Vector2i(-2150, -650)]
		else:
			pts = [Vector2i(0, 0), Vector2i(400, 0), Vector2i(0, 2150), Vector2i(650, 2150),
				Vector2i(424, 1924), Vector2i(0, 1100), Vector2i(-650, -2150)]
		for p: Vector2i in pts:
			var res: Collision.Resolvido = c.resolver(p.x, p.y, p.x, p.y, 0, raio, raio)
			print("[cp]  parado %-14s -> (%6d,%6d) d=(%+5d,%+5d) empurrado=%s rejeitado=%s"
				% [str(p), res.x, res.z, res.x - p.x, res.z - p.y, res.empurrado, res.rejeitado])
		# um passo real: de fora para dentro
		var mv: Array = [[Vector2i(0, -1200), Vector2i(0, -600)], [Vector2i(0, 0), Vector2i(100, 0)]]
		for m: Array in mv:
			var a: Vector2i = m[0]
			var b: Vector2i = m[1]
			var res2: Collision.Resolvido = c.resolver(a.x, a.y, b.x, b.y, 0, raio, raio)
			print("[cp]  passo %s->%s -> (%d,%d) empurrado=%s rejeitado=%s"
				% [str(a), str(b), res2.x, res2.z, res2.empurrado, res2.rejeitado])
	quit(0)
