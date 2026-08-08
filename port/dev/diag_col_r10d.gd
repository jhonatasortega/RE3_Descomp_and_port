extends SceneTree
## Inventário da colisão de uma sala: quantos registros, quais estão ATIVOS (bit 0x40 do `+0x08`),
## a forma, o nível e o envelope de cada um. Serve para achar buraco de colisão.
## env: COL_SALA=R10D
func _initialize() -> void:
	var sala := OS.get_environment("COL_SALA")
	if sala == "":
		sala = "R10D"
	var w := World.new()
	if not w.carregar(sala):
		print("[cr] %s nao carregou" % sala)
		quit(1)
		return
	var col := w.room.colisao
	print("[cr] %s: %d registros · piso padrao %d" % [sala, col.rects.size(), col.piso_padrao])
	var ativos := 0
	var desligados := []
	for i in col.rects.size():
		var r: Collision.Rect = col.rects[i]
		var ativo := (r.bits & Collision.MASCARA_PLAYER) != 0
		if ativo:
			ativos += 1
		else:
			desligados.append(i)
		if i < 6 or not ativo:
			print("[cr]   %2d forma=%2d canto=%d bits=0x%04x mask=0x%04x nivel=%d topo=%d %s x[%d..%d] z[%d..%d]" % [
				i, r.bits & 0x0F, (r.bits >> 4) & 3, r.bits, r.mask, r.nivel, r.topo,
				"ATIVO" if ativo else "desligado", r.x0, r.x1, r.z0, r.z1])
	print("[cr] ativos para o player: %d de %d · desligados: %s" % [
		ativos, col.rects.size(), str(desligados)])
	# o script mexe em collider?
	print("[cr] o init mudou %d collider(s) (opcode 0x6e)" % w.vm.colliders_mudados)
	quit(0)
