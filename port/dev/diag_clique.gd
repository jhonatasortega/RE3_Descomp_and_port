extends SceneTree
## Clique no menu: 1º seleciona, 2º confirma (regra de toque, pensando no celular).
func _initialize() -> void:
	var st := GameState.new()
	st.novo_jogo()
	var m := MenuStatus.new()
	get_root().add_child(m)
	m.carregar(st)
	m.alternar()
	m._anim = 0
	print("[cl] aberto=%s" % m.aberto)
	print("[cl] clique no slot 1 (celula da direita, linha 0) -> %s · cursor=%d"
		% [m.clicar(Vector2(224 + 60, 66 + 15)), m.cursor])
	print("[cl] clique de novo no mesmo -> %s · sub=%s"
		% [m.clicar(Vector2(224 + 60, 66 + 15)), str(m.sub_itens)])
	print("[cl] clique em EXAMINAR -> %s"
		% m.clicar(Vector2(159 + 28, MenuStatus.SUB_LINHA_Y[2] + 8)))
	print("[cl] clique de novo em EXAMINAR -> %s" % m.clicar(
		Vector2(159 + 28, MenuStatus.SUB_LINHA_Y[2] + 8)))
	print("[cl] mensagem=%s" % m.mensagem.substr(0, 40))
	m.mensagem = ""
	print("[cl] clique no botao ARQ. -> %s · botao=%d"
		% [m.clicar(Vector2(224 + 10, 44 + 8)), m.selecao_botao])
	## HOVER: passar por cima destaca sem confirmar
	m.sub_itens.clear()
	m.selecao_botao = -1
	m.cursor = 0
	print("[cl] pairar no slot 3 -> mudou=%s cursor=%d sub=%s"
		% [m.pairar(Vector2(224 + 20, 66 + 45)), m.cursor, str(m.sub_itens)])
	print("[cl] pairar no botao SAIR -> mudou=%s botao=%d"
		% [m.pairar(Vector2(224 + 40, 24 + 8)), m.selecao_botao])
	print("[cl] pairar no mesmo lugar de novo -> mudou=%s (nao repete)"
		% m.pairar(Vector2(224 + 40, 24 + 8)))
	quit(0)
