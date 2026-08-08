extends SceneTree
func _initialize() -> void:
	var m := MenuStatus.new()
	var st := GameState.new()
	st.novo_jogo()
	m.carregar(st)
	m.alternar()
	for _k in 8: m.avancar()
	# EXAMINAR: abre submenu, escolhe CHECK
	m.confirmar()
	m.sub_sel = 2
	m.confirmar()
	print("[fx] examinando: mensagem tem %d chars" % m.mensagem.length())
	m.cancelar()
	print("[fx] ESC no examinar -> aberto=%s mensagem=%d (deve ser aberto e 0)" % [m.aberto, m.mensagem.length()])
	m.cancelar()
	for _k in 8: m.avancar()            ## o fechamento leva 6 quadros
	print("[fx] ESC de novo + 8 quadros -> aberto=%s (deve ser false)" % m.aberto)
	m.alternar()
	for _k in 8: m.avancar()
	print("[fx] reabriu: botao=%d submenu=%d combinar=%d msg=%d (tudo limpo?)" % [
		m.selecao_botao, m.sub_itens.size(), m.combinar_de, m.mensagem.length()])
	quit(0)
