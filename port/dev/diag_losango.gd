extends SceneTree
func _initialize() -> void:
	var c := Collision.new()
	var r := Collision.Rect.new()
	r.f0 = -1000
	r.f1 = -1000
	r.f2 = 1000
	r.f3 = 1000
	r.forma = 4
	r.bits = 0xFE44
	r.mask = 0x0FFF
	c.rects.append(r)
	print("[lo] bits=0x%04x mask=0x%04x base_y=%d nivel=%d topo=%d"
		% [r.bits, r.mask, r.base_y, r.nivel, r.topo])
	for alvo: Vector2i in [Vector2i(-1150, 0), Vector2i(-400, -400), Vector2i(-100, 0)]:
		var res: Collision.Resolvido = c.resolver(-2000, -2000, alvo.x, alvo.y, 0, 200, 200)
		print("[lo] alvo %s -> (%d,%d) empurrado=%s rejeitado=%s"
			% [str(alvo), res.x, res.z, res.empurrado, res.rejeitado])
	quit(0)
