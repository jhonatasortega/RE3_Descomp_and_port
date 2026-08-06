extends RefCounted
## Carrega as 169 SALAS e confere contra os totais que a decomp já provou (item P1-01).
##
## Este é o teste que o protótipo antigo nunca pôde fazer: ele era preso na R100. Se o loader
## atravessa as 169 salas batendo 2105 câmeras / 5289 retângulos / 453 portas, o resto da F1
## pode assumir que qualquer sala carrega.
##
## Totais de referência (docs/decomp/PROGRESS.md e a saída do pipeline):
##   169 salas · 2105 câmeras · 5289 retângulos de colisão · 453 portas · 1507 câmeras com máscara

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("RoomData")

	# --- caso conhecido: R100 (escritório S.T.A.R.S.), a sala do protótipo ---
	var r100 := RoomData.load_room("R100")
	t.eq(r100.erros, [], "R100 carrega sem erro")
	t.eq(r100.stage, 1, "stage extraído do nome (R100 -> 1)")
	t.eq(r100.cameras.size(), 2, "R100 tem 2 câmeras")
	t.eq(r100.rects.size(), 14, "R100 tem 14 retângulos (4 paredes + 10 móveis)")
	t.eq(r100.rects.filter(func(x: RoomData.CollisionRect) -> bool: return x.wall).size(), 4,
		"os 4 primeiros são as paredes da sala")
	t.eq(r100.rvd.size(), 4, "R100 tem 4 zonas RVD")
	t.eq(r100.cameras[0].from_ps1, Vector3i(-23364, -4788, -24156), "posição da câmera 0")
	t.eq(r100.cameras[0].to_ps1, Vector3i(-20790, -1458, -20394), "alvo da câmera 0")
	t.eq(r100.cameras[0].attr, 29623, "attr da câmera 0 (valor mais comum do jogo)")
	t.eq(r100.cameras[0].n_masks, 77, "77 sprites de oclusão na câmera 0")
	t.eq(r100.doors.size(), 1, "R100 tem 1 porta no SCD")
	t.eq(r100.doors[0].to_room_id, "R101", "a porta leva à R101 (destino estático)")

	# --- colisão: modelo de SEGMENTOS (o do motor), não caixa cheia ---
	# Estar DENTRO da envolvente de um collider não bloqueia nada; o que bloqueia é CRUZAR
	# um dos segmentos da forma. Os três asserts anteriores testavam o modelo errado (raio +
	# caixa cheia) — e é justamente esse modelo que deixava a R101 com 0% de sala caminhável.
	t.check(r100.colisao != null, "R100 carregou o bloco de colisão em `colisao`")
	t.eq(r100.colisao.rects.size(), 14, "14 registros de colisão")
	t.check(r100.trajeto_livre(-20400, -20790, -20400 + 78, -20790, 0),
		"da chegada da porta dá para dar um passo")
	var alvo := r100.colisao.rects[5]
	var c5 := alvo.centro()
	# Um passo de 1 un perto da BORDA (longe do cruzamento das diagonais) é livre: o motor
	# testa cruzamento, não contenção. No CENTRO não vale — o centro é exatamente onde as duas
	# diagonais se cruzam, então lá qualquer passo cruza (foi o meu primeiro assert, errado).
	var borda_z := alvo.z0 + (alvo.z1 - alvo.z0) / 10
	t.check(r100.trajeto_livre(c5.x, borda_z, c5.x + 1, borda_z + 1, 0),
		"passo de 1 un DENTRO do collider, fora das diagonais, é livre")
	# atravessar o collider de ponta a ponta CRUZA os segmentos dele -> barrado
	t.check(not r100.trajeto_livre(alvo.x0 - 500, c5.y, alvo.x1 + 500, c5.y, 0),
		"atravessar o collider de lado a lado é barrado")

	# --- porta por posição ---
	var d0 := r100.doors[0]
	t.check(r100.door_at(d0.box.position.x + 10, d0.box.position.y + 10) != null,
		"door_at acha a porta dentro da caixa de gatilho")
	t.check(r100.door_at(999999, 999999) == null, "door_at devolve null fora de qualquer porta")

	# --- TESTE FORTE: as 169 salas ---
	var salas := _listar_salas()
	t.eq(salas.size(), 169, "169 salas em data/STAGE*/")

	var n_cam := 0
	var n_rect := 0
	var n_door := 0
	var n_rvd := 0
	var n_trig := 0
	var n_mask_cams := 0
	var com_erro: Array[String] = []
	var destino_vazio := 0
	var attrs := {}
	for id in salas:
		var r := RoomData.load_room(id)
		if not r.erros.is_empty():
			com_erro.append("%s: %s" % [id, ", ".join(r.erros)])
		n_cam += r.cameras.size()
		n_rect += r.rects.size()
		n_door += r.doors.size()
		n_rvd += r.rvd.size()
		n_trig += r.triggers.size()
		for c in r.cameras:
			attrs[c.attr] = true
			if c.n_masks > 0:
				n_mask_cams += 1
		for d in r.doors:
			if d.to_room_id == "":
				destino_vazio += 1

	t.eq(com_erro.size(), 0, "nenhuma sala com erro de carga",
		"" if com_erro.is_empty() else ", ".join(com_erro.slice(0, 3)))
	t.eq(n_cam, 2105, "2105 câmeras no total")
	t.eq(n_rect, 5289, "5289 retângulos de colisão no total")
	t.eq(n_door, 453, "453 portas no total")
	t.eq(destino_vazio, 0, "toda porta tem sala de destino resolvida")
	t.check(n_rvd > 1000, "zonas RVD carregadas", "n = %d" % n_rvd)
	t.check(n_trig > 500, "gatilhos carregados", "n = %d" % n_trig)
	t.eq(n_mask_cams, 1507, "1507 câmeras têm sprites de oclusão")

	# --- o que isso revela sobre o FOV por câmera (P1-04) ---
	t.eq(attrs.size(), 24, "o campo attr tem só 24 valores distintos nas 2105 câmeras")

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
			if nome.begins_with("R") and nome.ends_with(".json") \
					and not nome.contains("_col") and not nome.contains("_scd"):
				saida.append(nome.trim_suffix(".json"))
	saida.sort()
	return saida
