extends SceneTree
## Prova das AÇÕES do menu com os valores do EXE: USE (cura), COMBINE (ervas) e recarregar arma.
## Cada caso imprime o esperado (da tabela do binário) e o obtido.
func _initialize() -> void:
	var st := GameState.new()
	var pl := Player.new()
	print("[im] %d receitas carregadas do EXE" % Itens.n_receitas())

	# ── descritor: quem é arma (EQUIP) e quem é cura (USE) ──
	for id: int in [0x01, 0x03, 0x21, 0x20, 0x73]:
		print("[im] item 0x%02x: cat=%d equipavel=%s usavel=%s max=%d" % [
			id, Itens.categoria(id), Itens.equipavel(id), Itens.usavel(id), Itens.maximo(id)])

	# ── cura: os valores da tabela 0x80010e4c com maxHP = 200 ──
	print("[im] --- cura (maxHP=200) ---")
	for id: int in [0x20, 0x21, 0x22, 0x23, 0x24, 0x2A]:
		var e := Itens.cura_de(id, 200)
		print("[im]   0x%02x -> hp=%s veneno=%s gasta_um=%s valido=%s" % [
			id, e["hp"], e["veneno"], e["gasta_um"], e["valido"]])

	# ── condição pelos limiares provados ──
	print("[im] --- condicao ---")
	for hp: int in [200, 101, 100, 41, 40, 21, 20]:
		print("[im]   hp=%3d -> %d" % [hp, Itens.condicao(hp, 0)])
	print("[im]   veneno -> %d · virus -> %d" % [Itens.condicao(200, 0x200),
		Itens.condicao(200, 0x100)])

	# ── receitas: as ervas e a recarga ──
	print("[im] --- receitas ---")
	for par: Array in [[0x21, 0x21], [0x21, 0x22], [0x21, 0x23], [0x22, 0x24], [0x03, 0x15],
			[0x21, 0x73]]:
		var r := Itens.receita(int(par[0]), int(par[1]))
		if r.is_empty():
			print("[im]   0x%02x + 0x%02x -> NAO COMBINA" % [par[0], par[1]])
		else:
			print("[im]   0x%02x + 0x%02x -> tipo=%s c=0x%02x n=%d (%s + %s = %s)" % [
				par[0], par[1], r["kind_nome"], r["c"], r["n"],
				r["a_nome"], r["b_nome"], r["c_nome"]])
	# simetria: a busca do EXE é simétrica
	var ra := Itens.receita(0x21, 0x22)
	var rb := Itens.receita(0x22, 0x21)
	print("[im] simetrica: %s" % (not ra.is_empty() and ra.get("addr") == rb.get("addr")))

	# ── municao da arma ──
	print("[im] municao: Hand Gun(0x03) -> 0x%02x · Shotgun(0x04) -> 0x%02x" % [
		Itens.municao_da_arma(0x03), Itens.municao_da_arma(0x04)])
	quit(0)
