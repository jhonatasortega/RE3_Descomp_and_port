extends SceneTree
## Diagnóstico da PROFUNDIDADE do fogo da sala, câmera por câmera (sem render).
##
## Responde com número, não com impressão:
##   1. de qual câmera cada chama do `0x70` aparece no quadro (1280×960) e em que retângulo;
##   2. qual a chave de Ordering Table dela e a do personagem — quem fica na frente;
##   3. quantos recortes de máscara do cenário ficam NA FRENTE daquela chama (`cobre`), que
##      é o que a esconde quando ela cai atrás de uma quina/batente. `cobre=0` num lugar em
##      que a chama parece "colada na parede" significa que aquela câmera não tem priority
##      sprite ali — no PS1 é igual, porque não existe z-buffer.
## Imprime também, para cada câmera, um ponto de chão de onde a Jill a ativa (é o que se
## passa em `ESP_JILL` para o `shot_esp_sala.gd` fotografar aquela câmera).
##
##     godot --headless --path port --script res://dev/diag_esp_prof.gd
##     ESP_SALA=R10D ESP_JILL=9404,-13317 godot --headless --path port --script ...

const W := 1280
const H := 960


var _t := 0


func _process(_d: float) -> bool:
	# Os nós criados aqui só ficam DENTRO da árvore depois da primeira iteração; sem esperar,
	# `Camera3D.look_at`/`unproject_position` reclamam ("Node not inside tree").
	_t += 1
	if _t < 3:
		return false
	_varrer()
	return true


func _varrer() -> void:
	var sala := OS.get_environment("ESP_SALA")
	if sala == "":
		sala = "R10D"
	var jill := Vector3i(9404, 0, -13317)
	var jenv := OS.get_environment("ESP_JILL")
	if jenv != "":
		var p := jenv.split(",")
		if p.size() == 2:
			jill = Vector3i(int(p[0]), 0, int(p[1]))

	var room := RoomData.load_room(sala)
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	root.add_child(vp)
	var cam3d := Camera3D.new()
	vp.add_child(cam3d)

	var esp := EspSala.new()
	root.add_child(esp)
	var n := esp.carregar(sala)
	print("%s: %d chama(s) · Jill em %s" % [sala, n, jill])
	if n == 0:
		return

	var occ := Occlusion.new()
	root.add_child(occ)
	for i in room.cameras.size():
		var c := room.camera(i)
		CameraRID.apply(cam3d, c)
		occ.carregar(room, i)
		occ.atualizar_profundidade(c, jill)
		esp.avancar(cam3d, room, i, occ.char_key)
		var linhas: Array[String] = []
		for e_v: Variant in (esp.efeitos as Array):
			var e: Object = e_v
			var no: Sprite2D = e.get("no")
			if no == null or not no.visible:
				continue
			var r: Rect2 = e.get("rect_tela")
			if not r.intersects(Rect2(0, 0, W, H)):
				continue
			var pos: Vector3i = e.get("pos")
			var cobre := 0
			for m_v: Variant in (esp.get("_mascaras") as Array):
				var m: Dictionary = m_v
				if int(m["chave"]) < int(e.get("chave")) and (m["rect"] as Rect2).intersects(r):
					cobre += 1
			linhas.append("t%02x %s chave=%d %s tela=(%d,%d) %dx%d cobre=%d" % [
				e.get("tipo"), pos, e.get("chave"),
				"FRENTE" if e.get("na_frente") else "atrás",
				int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y), cobre])
		print("câmera %2d/%d attr=%d · chave da Jill=%d · %d máscara(s) · %d chama(s) no quadro"
			% [i, room.cameras.size(), c.attr, occ.char_key, occ.sprite_count(),
				linhas.size()]
			+ " · Jill vê esta câmera de %s" % _ponto_da_camera(room, i))
		for l in linhas:
			print("     %s" % l)


func _ponto_da_camera(room: RoomData, i: int) -> String:
	## Centro da zona de PERMANÊNCIA (`from == to`) do RVD que ativa a câmera `i` — é o que
	## `CameraRVD.best_camera_for` responde, logo é o que se passa em `ESP_JILL`. "-" quando
	## a câmera só é alcançada por corte de porta (sem zona de permanência ativa).
	for e in room.rvd:
		if e.from_cam != i or e.to_cam != i or e.quad.size() != 4:
			continue
		if not CameraRVD.flags_active(e.flags):
			continue
		var sx := 0
		var sz := 0
		for p: Vector2i in e.quad:
			sx += p.x
			sz += p.y
		return "(%d, %d)" % [sx / 4, sz / 4]
	return "-"
