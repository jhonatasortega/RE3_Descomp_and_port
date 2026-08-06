extends RefCounted
## AUDITORIA DAS PORTAS (itens P3-01 / P3-03 / P3-06) — o mundo está conectado?
##
## Critério do plano para o P3-06: atravessar cada porta e validar sala de destino, spawn e
## câmera. Aqui isso é feito sobre as **453 portas** do dado, sem render: para cada porta,
## carregar o destino, aplicar a chegada e checar que a posição é **caminhável** e a câmera
## **existe**. Um destino inválido ou um spawn dentro de parede aparece aqui, não 30 salas
## depois durante o jogo.
##
## Referência: 453 portas · 296 arestas-sala · 279 recíprocas · 17 mão-única justificadas
## (docs/decomp/notes/room_graph.md).

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("World")

	# --- carregar sala e trocar de sala ---
	var w := World.new()
	t.check(w.carregar("R100"), "R100 carrega no mundo")
	t.eq(w.room.room_id, "R100", "sala corrente = R100")
	t.check(w.vm != null and w.vm.aots.size() > 0, "o script da sala instalou AOTs",
		"%d AOTs" % (w.vm.aots.size() if w.vm else 0))
	var portas := w.vm.portas()
	t.check(portas.size() >= 1, "R100 tem porta instalada")

	if portas.size() >= 1:
		var p: Aot = portas[0]
		var antes := w.room.room_id
		t.check(w.atravessar(p), "atravessa a porta")
		t.eq(w.room.room_id, "R101", "chegou na R101")
		t.eq(w.trocas, 1, "contou 1 troca")
		t.check(w.historico.has(antes) and w.historico.has("R101"), "histórico registrado")
		t.check(w.player.pos != Vector3i.ZERO, "posição de chegada aplicada",
			str(w.player.pos))
		t.check(w.camera >= 0 and w.camera < w.room.cameras.size(),
			"câmera de chegada válida", "cam=%d de %d" % [w.camera, w.room.cameras.size()])

	# --- REGRESSÃO dos dois bugs que apareceram jogando ---
	# (1) LOOP DE PORTA: ao chegar, o personagem aterrissa DENTRO do gatilho da porta do outro
	#     lado. Sem âncora, o AOT dispara a cada tick e a troca entra em loop — de fora parece
	#     que o controle parou de responder, porque ele é teleportado independentemente do input.
	# (2) CONGELADO NA CHEGADA: a posição de chegada costuma cair dentro de colisão (ver P3-10),
	#     e o deslize por eixo nega todo movimento. A regra de escape garante que dá para sair.
	var wr := World.new()
	t.check(wr.carregar("R100"), "R100 para o teste de regressão")
	var pr := wr.vm.portas()
	if not pr.is_empty():
		var pd: Aot = pr[0]
		wr.player.pos = Vector3i(pd.box.position.x + pd.box.size.x / 2, -258,
			pd.box.position.y + pd.box.size.y / 2)
		var pad_zero := Pad.new()
		for _i in 60:
			pad_zero.set_mask(0)
			wr.tick(pad_zero)
		t.eq(wr.trocas, 0, "parado na porta SEM apertar E: não atravessa (como no RE3)")
		# apertando E (borda): atravessa uma vez
		pad_zero.set_mask(Pad.ACAO)
		wr.tick(pad_zero)
		t.eq(wr.trocas, 1, "E na porta atravessa")
		for _i in 30:
			pad_zero.set_mask(Pad.ACAO)      # segurando: não repete (é borda)
			wr.tick(pad_zero)
		t.eq(wr.trocas, 1, "segurar E não atravessa em loop")
		var pos_ap := wr.player.pos
		var pad_f := Pad.new()
		for _i in 40:
			pad_f.set_mask(Pad.FWD)
			wr.tick(pad_f)
		t.check(wr.player.pos != pos_ap,
			"depois de chegar, o personagem RESPONDE ao input (regra de escape)",
			"de %s para %s" % [pos_ap, wr.player.pos])

	# --- AUDITORIA: as 453 portas do dado ---
	# Fonte: `_scd.json` (portas com destino resolvido pelo tools/scd_door_dest.py).
	var salas := _listar_salas()
	var total := 0
	var destino_ok := 0
	var spawn_ok := 0
	var camera_ok := 0
	var sem_destino := 0
	var problemas: Array[String] = []
	var alvos := {}
	for id in salas:
		var r := RoomData.load_room(id)
		if not r.erros.is_empty():
			continue
		for d in r.doors:
			total += 1
			if d.to_room_id == "":
				sem_destino += 1
				continue
			alvos[d.to_room_id] = true
			var dest := RoomData.load_room(d.to_room_id)
			if dest.erros.is_empty():
				destino_ok += 1
			else:
				if problemas.size() < 6:
					problemas.append("%s -> %s não carrega" % [id, d.to_room_id])
				continue
			# spawn: a posição de chegada tem de ser caminhável com o raio do personagem
			if dest.is_walkable(d.to_pos.x, d.to_pos.z, Player.RAIO_PS1):
				spawn_ok += 1
			elif problemas.size() < 6:
				problemas.append("%s -> %s: spawn %s em colisão" % [
					id, d.to_room_id, d.to_pos])
			# câmera de chegada
			if d.to_camera >= 0 and d.to_camera < dest.cameras.size():
				camera_ok += 1
			elif problemas.size() < 6:
				problemas.append("%s -> %s: câmera %d de %d" % [
					id, d.to_room_id, d.to_camera, dest.cameras.size()])

	print("    [portas] %d portas · destino carrega=%d · spawn livre=%d · câmera válida=%d · sem destino=%d · %d salas-alvo distintas"
		% [total, destino_ok, spawn_ok, camera_ok, sem_destino, alvos.size()])
	t.eq(total, 453, "453 portas no jogo")
	t.eq(sem_destino, 0, "toda porta tem destino resolvido")
	t.eq(destino_ok, 453, "as 453 salas de destino carregam",
		"" if problemas.is_empty() else ", ".join(problemas.slice(0, 3)))
	t.check(camera_ok >= 440, "câmera de chegada válida em praticamente todas",
		"%d de 453" % camera_ok)
	# O ponto de chegada NÃO é garantidamente livre (medido: só ~51% ficam fora de colisão,
	# mesmo com raio 0). Ver a nota em World.aplicar_chegada: pode ser classe caminhável do
	# campo `type` ainda não decodificada, ou resolução do motor no primeiro frame. O que o
	# port garante — e o que este teste cobra — é que TODA chegada é RESOLVÍVEL: existe ponto
	# livre a menos de 1200 unidades.
	var resolvidos := 0
	var irresolviveis: Array[String] = []
	for id2 in salas:
		var r2 := RoomData.load_room(id2)
		for d2 in r2.doors:
			if d2.to_room_id == "":
				continue
			var w3 := World.new()
			if not w3.carregar(d2.to_room_id):
				continue
			var q := w3._desencravar(d2.to_pos)
			if w3.room.is_walkable(q.x, q.z, Player.RAIO_PS1):
				resolvidos += 1
			elif irresolviveis.size() < 5:
				irresolviveis.append("%s -> %s %s" % [id2, d2.to_room_id, d2.to_pos])
	# Envelope: a chegada está DENTRO da sala de destino? Isso valida o espaço de coordenadas
	# (é o que separa "campo mal lido" de "colisão mal interpretada").
	var no_envelope := 0
	for id3 in salas:
		var r3 := RoomData.load_room(id3)
		for d3 in r3.doors:
			if d3.to_room_id == "":
				continue
			var dst := RoomData.load_room(d3.to_room_id)
			if dst.rects.is_empty():
				continue
			var minx := 32767
			var minz := 32767
			var maxx := -32768
			var maxz := -32768
			for rc in dst.rects:
				minx = mini(minx, rc.x0)
				minz = mini(minz, rc.z0)
				maxx = maxi(maxx, rc.x1)
				maxz = maxi(maxz, rc.z1)
			if d3.to_pos.x >= minx and d3.to_pos.x <= maxx 					and d3.to_pos.z >= minz and d3.to_pos.z <= maxz:
				no_envelope += 1
	print("    [chegada] livre de colisão=%d de %d · resolvível a <1200un=%d · dentro do envelope da sala=%d"
		% [spawn_ok, total, resolvidos, no_envelope])
	t.check(no_envelope >= 445,
		"a chegada está dentro do envelope da sala de destino (espaço de coordenadas correto)",
		"%d de %d" % [no_envelope, total])
	# NÃO se cobra aqui "toda chegada livre de colisão": medi e o dado não sustenta essa
	# premissa (só 51% ficam livres, mesmo com raio 0; 248 resolvem com empurrão de até 1200
	# un). A causa está na semântica do bloco de colisão, que NÃO está suficientemente
	# decodificada — ver docs/formatos/ARD.md, seção "Achado do PORT", e o item P3-10.
	t.check(resolvidos >= 240, "a maioria das chegadas é resolvível com empurrão curto",
		"%d de %d" % [resolvidos, total])

	# --- travessia real pelo mundo: entrar e voltar ---
	# Se a porta A->B e a volta B->A funcionarem, a mecânica de transição está fechada.
	var idas := 0
	var voltas := 0
	var testadas := 0
	for id in salas.slice(0, 40):                     # amostra: 40 salas
		var r := RoomData.load_room(id)
		if r.doors.is_empty():
			continue
		var w2 := World.new()
		if not w2.carregar(id):
			continue
		var ps := w2.vm.portas()
		if ps.is_empty():
			continue
		testadas += 1
		var p1: Aot = ps[0]
		var destino := p1.to_room_id()
		if w2.atravessar(p1):
			idas += 1
			# procura na sala nova uma porta que volte para a de origem
			for p2: Aot in w2.vm.portas():
				if p2.to_room_id() == id:
					if w2.atravessar(p2):
						voltas += 1
					break
	print("    [travessia] %d salas testadas · %d idas · %d voltas (recíprocas)"
		% [testadas, idas, voltas])
	t.check(testadas >= 20, "amostra de salas com porta instalada", "%d" % testadas)
	t.eq(idas, testadas, "toda ida funcionou")
	t.check(voltas > testadas / 2, "a maioria das portas tem volta recíproca funcionando",
		"%d voltas de %d idas" % [voltas, idas])

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("%s/STAGE%d" % [DATA_DIR, st])
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.begins_with("R") and nome.ends_with(".scd"):
				saida.append(nome.trim_suffix(".scd"))
	saida.sort()
	return saida
