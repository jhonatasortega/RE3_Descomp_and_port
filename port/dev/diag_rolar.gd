extends SceneTree
func _initialize() -> void:
	var m := MenuStatus.new()
	var st := GameState.new()
	st.novo_jogo()
	m.carregar(st)
	m.alternar()
	for _k in 8:
		m.avancar()                     ## deixa a animação de abertura terminar (6 quadros)
	m.cursor = 3
	m.mensagem = "Um dos itens usados para fazer municoes. Ela pode ser combinada com a ferramenta de recarga ou com outra polvora para fazer municao diferente."
	m.mensagem_linha = 0
	print("[rl] linhas do texto: %d" % Texto.quebrar(m.mensagem, 184).size())
	m.mover_cursor(0, 1)
	print("[rl] depois de BAIXO: linha=%d (cursor segue %d)" % [m.mensagem_linha, m.cursor])
	m.mover_cursor(0, 1)
	m.mover_cursor(0, 1)
	print("[rl] mais dois BAIXO: linha=%d" % m.mensagem_linha)
	m.mover_cursor(0, -1)
	print("[rl] um CIMA: linha=%d" % m.mensagem_linha)
	for _i in 20:
		m.mover_cursor(0, 1)
	print("[rl] no fim: linha=%d (nao passa do limite)" % m.mensagem_linha)
	quit(0)
