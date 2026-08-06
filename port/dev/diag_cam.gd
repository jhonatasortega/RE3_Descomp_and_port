extends SceneTree
## Onde a câmera troca? (P1-05) — mede o PONTO da troca andando pela sala.
##
## O relato do usuário foi "a área de transição da câmera 2 está errada" e "parece testar em 2
## lugares". Este diagnóstico responde com números: para cada travessia, imprime a posição em
## que a câmera mudou e quantas trocas houve (flicker aparece como contagem alta).

const PASSO := 78          ## 1 tick andando


func _initialize() -> void:
	for caso: Array in [["R100", -20400, 0, -20790], ["R101", -18808, -7200, -11475],
			["R11D", -5450, -3600, -26750]]:
		var sala: String = caso[0]
		var room := RoomData.load_room(sala)
		print("\n=== %s: %d câmeras, %d zonas ===" % [sala, room.cameras.size(), room.rvd.size()])
		for i in room.rvd.size():
			var e := room.rvd[i]
			print("   zona %2d: %d->%d ativa=%s grupo=0x%02x%s" % [
				i, e.from_cam, e.to_cam, e.active, CameraRVD.flags_group(e.flags),
				"  (degenerada)" if e.degenerate else ""])
		# corrida de cada câmera (o que o motor realmente varre)
		for c in room.cameras.size():
			var ini := CameraRVD.inicio_da_corrida(room, c)
			var fim := ini
			while fim < room.rvd.size() and room.rvd[fim].from_cam == c:
				fim += 1
			print("   câmera %d varre as zonas %d..%d (%d zonas)" % [c, ini, fim - 1, fim - ini])
		for dir_i in 4:
			_travessia(room, Vector3i(int(caso[1]), int(caso[2]), int(caso[3])), dir_i * 1024)
	quit(0)


func _travessia(room: RoomData, ini: Vector3i, angulo: int) -> void:
	var st := CameraRVD.Estado.new()
	st.camera = 0
	var pos := ini
	var trocas: Array[String] = []
	for i in 80:
		var off := PS1Math.rotate_xz(0, -PASSO, angulo)
		var alvo := Vector3i(pos.x + off.x, pos.y, pos.z + off.y)
		if not room.trajeto_livre(pos.x, pos.z, alvo.x, alvo.z, pos.y):
			break
		pos = alvo
		var antes := st.camera
		var agora := CameraRVD.update(room, st, pos.x, pos.z)
		if agora != antes:
			trocas.append("%d->%d em (%d,%d) tick %d" % [antes, agora, pos.x, pos.z, i])
	print("   ângulo %4d: andou até (%d,%d) · %d trocas%s" % [
		angulo, pos.x, pos.z, trocas.size(),
		"" if trocas.is_empty() else "  " + " | ".join(trocas.slice(0, 6))])
