extends SceneTree
## Itens no cenário: varredura das 169 salas com o dado REAL (0x67 + 0x68 + 0x7f).
##
## Mede o que o recomp afirma: 330 itens em 103 salas (316 do `0x67`, 14 do `0x68`), quantos
## têm objeto de cenário (`om < 32` + `0x7f` do mesmo slot), a distância entre a posição do
## objeto e o centróide da área de coleta, e se a coleta pela SONDA de 620 funciona.
func _initialize() -> void:
	var salas: Array[String] = []
	for st in range(1, 8):
		var dir := DirAccess.open("res://data/STAGE%d" % st)
		if dir == null:
			continue
		for f: String in dir.get_files():
			if f.ends_with(".scd"):
				salas.append(f.get_basename())
	salas.sort()
	var n_salas := 0
	var n67 := 0
	var n68 := 0
	var com_obj := 0
	var sem_obj := 0
	var sem_modelo := 0
	var brilho := 0
	var coleta_ok := 0
	var coleta_falha := 0
	var dists: Array[int] = []
	var falhas: Array[String] = []
	for sala: String in salas:
		var w := World.new()
		if not w.carregar(sala):
			continue
		var lista := w.itens_no_chao()
		if lista.is_empty():
			continue
		n_salas += 1
		for a: Aot in lista:
			if a.opcode == 0x67:
				n67 += 1
			else:
				n68 += 1
			if a.tem_brilho():
				brilho += 1
			var c := _centro(a)
			var obj := w.objeto_do_item(a)
			if not a.tem_modelo():
				sem_modelo += 1
			elif obj == null:
				sem_obj += 1
			else:
				com_obj += 1
				var d := roundi(Vector2(obj.pos.x - c.x, obj.pos.z - c.y).length())
				dists.append(d)
				if d > 1500:
					print("[it] LONGE %s aot %d item 0x%02x om=%d · obj%s vs area(%d,%d) = %d" % [
						sala, a.id, a.item_id, a.item_om, obj.pos, c.x, c.y, d])
			# COLETA pela sonda: fica a 620 do centro da área, olhando para ela.
			var y := w.room.colisao.floor_height(c.x, c.y, 0) if w.room.colisao != null else 0
			var achou := false
			for passo in 16:
				var ang := passo * 256
				w.player.facing = ang
				w.player.pos = Vector3i(
					c.x - (PS1Math.rsin(ang) * World.SONDA_ACAO >> PS1Math.SHIFT), y,
					c.y + (PS1Math.rcos(ang) * World.SONDA_ACAO >> PS1Math.SHIFT))
				if w.pegar_item_sob_o_player() != null:
					achou = true
					break
			if achou:
				coleta_ok += 1
			else:
				coleta_falha += 1
				if falhas.size() < 12:
					falhas.append("%s aot %d item 0x%02x om=%d" % [sala, a.id, a.item_id, a.item_om])
	dists.sort()
	print("[it] %d salas com item · %d itens (0x67=%d 0x68=%d)" % [
		n_salas, n67 + n68, n67, n68])
	print("[it] objeto 0x7f: %d com · %d sem 0x7f do slot · %d sem modelo (om>=32) · %d com brilho" % [
		com_obj, sem_obj, sem_modelo, brilho])
	if not dists.is_empty():
		print("[it] distancia objeto<->centro da area: mediana %d · max %d" % [
			dists[dists.size() / 2], dists[-1]])
	print("[it] coleta pela sonda 620: %d OK · %d falharam" % [coleta_ok, coleta_falha])
	for f: String in falhas:
		print("[it]    falha: %s" % f)
	quit(0)


func _centro(a: Aot) -> Vector2i:
	if a.kind == Aot.Kind.QUAD and a.quad.size() == 4:
		var sx := 0
		var sz := 0
		for p: Vector2i in a.quad:
			sx += p.x
			sz += p.y
		return Vector2i(sx / 4, sz / 4)
	return Vector2i(a.box.position.x + a.box.size.x / 2, a.box.position.y + a.box.size.y / 2)
