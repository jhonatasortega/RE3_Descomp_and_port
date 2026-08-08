extends SceneTree
## Planta da colisão de uma sala: cada registro como retângulo, VERDE se passa o filtro do
## resolvedor (bit 0x4000) e VERMELHO se é rejeitado. Marca a posição do jogador em amarelo.
## env: COL_SALA (padrão R10D), COL_POS="x,z"
func _initialize() -> void:
	var sala := OS.get_environment("COL_SALA")
	if sala == "":
		sala = "R10D"
	var w := World.new()
	if not w.carregar(sala):
		quit(1)
		return
	var col: Collision = w.room.colisao
	# envelope de tudo
	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var z0 := 1 << 30
	var z1 := -(1 << 30)
	for r: Collision.Rect in col.rects:
		x0 = mini(x0, r.f0)
		x1 = maxi(x1, r.f2)
		z0 = mini(z0, r.f1)
		z1 = maxi(z1, r.f3)
	var larg := 900
	var esc := float(larg) / float(maxi(x1 - x0, z1 - z0) + 1)
	var img := Image.create(larg + 20, larg + 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.09))
	for i in col.rects.size():
		var r: Collision.Rect = col.rects[i]
		var passa := (r.bits & Collision.MASCARA_RESOLVER) != 0
		var cor := Color(0.1, 0.85, 0.3, 1) if passa else Color(0.95, 0.15, 0.15, 1)
		var ax := int((r.f0 - x0) * esc) + 10
		var az := int((r.f1 - z0) * esc) + 10
		var bx := int((r.f2 - x0) * esc) + 10
		var bz := int((r.f3 - z0) * esc) + 10
		for x in range(maxi(ax, 0), mini(bx + 1, img.get_width())):
			for e in [az, bz]:
				if e >= 0 and e < img.get_height():
					img.set_pixel(x, e, cor)
		for z in range(maxi(az, 0), mini(bz + 1, img.get_height())):
			for e in [ax, bx]:
				if e >= 0 and e < img.get_width():
					img.set_pixel(e, z, cor)
	var pos := OS.get_environment("COL_POS")
	if pos == "":
		pos = "17044,-13679"
	var pp: PackedStringArray = pos.split(",")
	var jx := int((int(pp[0]) - x0) * esc) + 10
	var jz := int((int(pp[1]) - z0) * esc) + 10
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			var x := jx + dx
			var z := jz + dz
			if x >= 0 and x < img.get_width() and z >= 0 and z < img.get_height():
				img.set_pixel(x, z, Color(1, 0.9, 0.1, 1))
	img.save_png(ProjectSettings.globalize_path("res://_plot_col_%s.png" % sala))
	print("[pc] %s: %d registros · x[%d..%d] z[%d..%d] · escala %.4f" % [sala, col.rects.size(),
		x0, x1, z0, z1, esc])
	var n_rej := 0
	for r: Collision.Rect in col.rects:
		if (r.bits & Collision.MASCARA_RESOLVER) == 0:
			n_rej += 1
	print("[pc] rejeitados pelo filtro: %d de %d" % [n_rej, col.rects.size()])
	quit(0)
