extends SceneTree
## Reproduz o LAÇO do resolver com prints por rect, no ponto fixo do congelamento da R100.

func _initialize() -> void:
	var mundo := World.new()
	if not mundo.carregar("R100"):
		quit(1)
		return
	var col := mundo.room.colisao
	var px := -23217
	var pz := -26636
	var nx := px
	var nz := pz - 78
	print("[f2] prev=(%d,%d) cand=(%d,%d) nivel=0" % [px, pz, nx, nz])
	var res := Collision.Resolvido.new()
	res.x = nx
	res.z = nz
	var i := -1
	for r: Collision.Rect in col.rects:
		i += 1
		if (r.bits & Collision.MASCARA_RESOLVER) == 0:
			continue
		var nivel_lo := r.base_y / -Collision.ALTURA_POR_NIVEL
		if 0 < nivel_lo or r.nivel < 0:
			continue
		var codigo := Collision.quadrante(res.x, res.z, col.centro1, col.centro2)
		if (r.mask & codigo) != codigo:
			continue
		var girado := (r.mask & Collision.BIT_ROTACIONADO) != 0
		var atual := Vector2i(res.x, res.z)
		if girado:
			atual = Collision.girar_para_rect(res.x, res.z, r)
		if atual.x + 450 - r.f0 < 0 or atual.x + 450 - r.f0 >= (r.f2 + 900 - r.f0):
			continue
		if atual.y + 450 - r.f1 < 0 or atual.y + 450 - r.f1 >= (r.f3 + 900 - r.f1):
			continue
		var antes := Vector2i(res.x, res.z)
		var respondeu: bool = col._responder(r, res, px, pz, 450, 450, girado)
		print("[f2] rect %2d forma=%d raw=[%d,%d,%d,%d] respondeu=%s: (%d,%d) -> (%d,%d) rej=%s" % [
			i, r.forma, r.f0, r.f1, r.f2, r.f3, respondeu, antes.x, antes.y, res.x, res.z,
			res.rejeitado])
	print("[f2] final: (%d,%d)" % [res.x, res.z])
	quit(0)
