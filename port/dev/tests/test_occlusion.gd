extends RefCounted
## Oclusão por priority sprites (item P1-07).
##
## A prova FORTE deste item não é um assert: é o teste de pixel feito por render — desenhar os
## 77 recortes da R100 câmera 0 sobre o background, sem personagem, e comparar com o background
## puro dá **0 pixel de diferença**. Se algum retângulo estivesse deslocado, apareceria como
## remendo. (Comando em docs/decomp/notes/occlusion.md, seção "Achado do PORT".)
##
## Aqui ficam as invariantes que dão para conferir headless: contagem de recortes por câmera
## contra o `n_masks` do dado, e o comportamento do teste de profundidade.

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("Occlusion")

	var room := RoomData.load_room("R100")
	var occ := Occlusion.new()
	var n := occ.carregar(room, 0)
	t.eq(n, 77, "R100 câmera 0 monta os 77 recortes")
	t.eq(occ.sprite_count(), room.camera(0).n_masks,
		"nº de recortes montados == n_masks do dado")
	# chave dos recortes = depth CRU do RDT (o JSON tem z = depth*16 → 2368/16 = 148)
	t.eq(occ.z_range(), Vector2(148.0, 148.0),
		"os 77 recortes desta câmera compartilham a chave de OT 148")

	# --- regra da OT: chave do sprite < chave do personagem = sprite na frente ---
	occ.modo = Occlusion.Modo.PROFUNDIDADE
	occ.char_key = 0
	t.eq(occ.desenhados(), 0, "personagem com chave 0 (na frente de tudo): nada cobre")
	occ.char_key = 149
	t.eq(occ.desenhados(), 77, "personagem com chave 149: os 77 recortes (chave 148) cobrem")
	occ.char_key = 148
	t.eq(occ.desenhados(), 0, "empate de chave: sprite NÃO cobre (OT desce de 1023 a 0)")
	occ.modo = Occlusion.Modo.OVERLAY
	t.eq(occ.desenhados(), 77, "modo OVERLAY ignora a chave (valida posição)")
	occ.modo = Occlusion.Modo.DESLIGADA
	t.eq(occ.desenhados(), 0, "modo DESLIGADA não desenha nada")

	# --- a chave cresce ao afastar da câmera (SZ>>5) e o banco default é 0 ---
	occ.modo = Occlusion.Modo.PROFUNDIDADE
	var cam := room.camera(0)
	occ.atualizar_profundidade(cam, cam.from_ps1)
	var d0: int = occ.char_key
	occ.atualizar_profundidade(cam, cam.to_ps1)
	var d1: int = occ.char_key
	t.check(d1 > d0, "chave cresce da posição da câmera para o alvo", "de %d para %d" % [d0, d1])
	t.check(d0 <= 1, "na posição da câmera a chave é ~0 (banco 0)", "%d" % d0)
	# R100 não tem seção 14 → banco sempre 0; salas com seção têm zonas coerentes
	t.eq(room.priority_zones_da_camera(0).size(), 0, "R100 sem zonas de prioridade (banco 0)")
	var r217 := RoomData.load_room("R217")
	var tem_zona := false
	for ci in r217.cameras.size():
		if r217.priority_zones_da_camera(ci).size() > 0:
			tem_zona = true
	t.check(tem_zona, "R217 tem zonas de prioridade (seção 14) em alguma câmera")

	# --- as 1507 câmeras com máscara montam todos os 111644 recortes ---
	# (sem carregar textura: percorre o dado, que é o que importa aqui)
	var salas := _listar_salas()
	var cams_com := 0
	var blocos := 0
	var soma_bate := 0
	var soma_erra := 0
	for id in salas:
		var r := RoomData.load_room(id)
		for c in r.cameras:
			var n_blocos := 0
			for g: Dictionary in c.mask_groups:
				n_blocos += (g.get("blocks", []) as Array).size()
			if n_blocos == 0:
				continue
			cams_com += 1
			blocos += n_blocos
			if n_blocos == c.n_masks:
				soma_bate += 1
			else:
				soma_erra += 1
	t.eq(cams_com, 1507, "1507 câmeras têm recortes de oclusão")
	t.eq(blocos, 111644, "111644 recortes no jogo todo")
	t.eq(soma_erra, 0, "em toda câmera, Σ blocos == n_masks declarado")

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
