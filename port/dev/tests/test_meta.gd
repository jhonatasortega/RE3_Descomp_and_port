extends RefCounted
## Save/load, itens no chão e disparos de som (itens P3-05, P2-07, P2-08).

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("Save/Itens/Som")

	# ── SAVE/LOAD (P3-05): o que o save precisa preservar é o CONTEÚDO, não o formato do PS1 ──
	var w := World.new()
	t.check(w.carregar("R100"), "R100 carrega")
	w.player.pos = Vector3i(-21820, -258, -21899)
	w.player.facing = 1024
	w.player.hp = 137
	w.player.equipped_weapon = 2
	w.state.add_item(0x02, 1)
	w.state.add_item(0x15, 45)
	w.state.progress_set(9)
	w.camera = 1
	var caminho := "user://_test_world_save.json"
	t.eq(w.salvar(caminho), OK, "gravou o save")

	var w2 := World.new()
	t.check(w2.carregar_save(caminho), "leu o save")
	t.eq(w2.room.room_id, "R100", "voltou na mesma sala")
	t.eq(w2.player.pos, Vector3i(-21820, -258, -21899), "posição preservada")
	t.eq(w2.player.facing, 1024, "ângulo preservado")
	t.eq(w2.player.hp, 137, "HP preservado")
	t.eq(w2.player.equipped_weapon, 2, "arma equipada preservada")
	t.eq(w2.camera, 1, "câmera preservada")
	t.check(w2.state.progress_get(9), "flag de progresso preservada")
	t.eq(w2.state.find_by_id(0x15), 1, "inventário preservado")
	t.check(w2.state.save_count >= 1, "contador de saves subiu")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho))
	var w3 := World.new()
	t.check(not w3.carregar_save("user://_nao_existe.json"), "save ausente devolve false")

	# ── ITENS NO CHÃO (P2-07) ──
	var salas := _listar_salas()
	var total_itens := 0
	var salas_com := 0
	var ids := {}
	var n67 := 0
	var n68 := 0
	var sce_errado := 0
	for id in salas:
		var v := ScriptVM.new()
		if not v.carregar_sala(id):
			continue
		v.modo = ScriptVM.Modo.EXECUCAO
		v.state = GameState.new()
		for fi in v.func_offsets.size():
			v.executar(fi)
		var it := v.itens()
		if not it.is_empty():
			salas_com += 1
		for a: Aot in it:
			total_itens += 1
			ids[a.item_id] = true
			if a.opcode == 0x67:
				n67 += 1
			else:
				n68 += 1
			if a.sce != Aot.SCE_ITEM:
				sce_errado += 1
	print("    [itens] %d itens no chão em %d salas · %d ids distintos (0x67=%d 0x68=%d)" % [
		total_itens, salas_com, ids.size(), n67, n68])
	# **Os dois opcodes são item.** O `0x67` (2 pontos, 22 B, handler `0x800574f4`) estava
	# rotulado "door_aot_set" e não era instalado: por isso o port via só os 14 do `0x68`.
	# No dado há 330 itens em 103 salas; aqui saem 291 porque a tabela de AOT tem 32 slots e
	# um `aot_id` reinstalado em outra função SOBREPÕE o anterior (é o que o motor faz) — e a
	# VM ainda não percorre todos os caminhos de evento.
	t.check(total_itens > 250, "itens no chão do 0x67 + 0x68", "%d" % total_itens)
	t.check(n67 > 200 and n68 == 14, "os dois opcodes de item aparecem",
		"0x67=%d 0x68=%d" % [n67, n68])
	t.eq(sce_errado, 0, "todo AOT de item tem sce == 2")
	t.check(ids.size() >= 5, "vários ids de item distintos", "%d" % ids.size())

	# pegar: entra no inventário e o AOT desativa
	var wi := World.new()
	var achou := false
	for id2 in salas:
		if not wi.carregar(id2):
			continue
		var it2 := wi.vm.itens()
		if it2.is_empty():
			continue
		var a2: Aot = it2[0]
		# O `0x68` é um QUAD de 4 pontos (handler `0x800576c4`) — a caixa está vazia. O centro
		# é o centróide do quad, e o Y é o piso do nível (`floor_height`), não o -258 herdado.
		var sx := 0
		var sz := 0
		for pq: Vector2i in a2.quad:
			sx += pq.x
			sz += pq.y
		var cx: int = sx / 4 if a2.quad.size() == 4 else a2.box.position.x + a2.box.size.x / 2
		var cz: int = sz / 4 if a2.quad.size() == 4 else a2.box.position.y + a2.box.size.y / 2
		var cy: int = wi.room.colisao.floor_height(cx, cz, 0) if wi.room.colisao != null else 0
		wi.player.pos = Vector3i(cx, cy, cz)
		var antes := wi.state.item_count()
		var pad_e := Pad.new()
		pad_e.set_mask(Pad.ACAO)
		wi.tick(pad_e)                       # E = pega
		var pego := wi.state.item_count() > antes
		if pego:
			t.eq(wi.state.item_count(), antes + 1, "E pega o item e ele entra no inventário (%s)" % id2)
			var depois := wi.state.item_count()
			pad_e.set_mask(0)
			wi.tick(pad_e)
			pad_e.set_mask(Pad.ACAO)
			wi.tick(pad_e)
			t.eq(wi.state.item_count(), depois, "não dá para pegar duas vezes")
			achou = true
			break
	t.check(achou, "achou uma sala com item pegável para testar")

	# ── DISPAROS DE SOM (P2-08) ──
	# Referência: 1528 disparos nas 169 salas (docs/decomp/notes/sfx.md §8).
	var total_som := 0
	var por_op := {}
	var ids_loop := {}
	for id3 in salas:
		var v3 := ScriptVM.new()
		if not v3.carregar_sala(id3):
			continue
		v3.modo = ScriptVM.Modo.EXECUCAO
		v3.state = GameState.new()
		for fi in v3.func_offsets.size():
			v3.executar(fi)
		for sd: Dictionary in v3.sons:
			total_som += 1
			var o := int(sd["op"])
			por_op[o] = int(por_op.get(o, 0)) + 1
			if bool(sd["loop"]):
				ids_loop[int(sd["id"])] = true
	print("    [som] %d disparos · por opcode %s · %d ids distintos em loop" % [
		total_som, por_op, ids_loop.size()])
	t.check(total_som > 800, "o script dispara centenas de sons", "%d" % total_som)
	t.check(por_op.has(0x57), "há disparos em LOOP (0x57)")
	t.check(por_op.has(0x58) or por_op.has(0x59), "há disparos one-shot (0x58/0x59)")
	t.check(ids_loop.size() <= 20,
		"os ids de loop são poucos (a doc mede 14, concentrados em 1..8)",
		"%d ids" % ids_loop.size())

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
