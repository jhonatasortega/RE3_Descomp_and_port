extends SceneTree
## Mira e tiro pelo caminho real: segura AIM (botão direito do mouse) e aperta ACAO (esquerdo).
func _initialize() -> void:
	var st := GameState.new()
	st.novo_jogo()
	var w := World.new(st)
	if not w.carregar("R10D"):
		print("[tr] falhou carregar")
		quit(1)
		return
	w.player.pos = Vector3i(11560, 0, -16413)
	var pad := Pad.new()
	w.player.atirou.connect(func(alvo: int, de: Vector3i, para: Vector3i) -> void:
		print("[tr]   >>> TIRO: alvo=%d de=%s para=%s municao=%d"
			% [alvo, str(de), str(para), st.equipped_qtd()]))
	w.player.mirou.connect(func(alvo: int, tier: int) -> void:
		print("[tr]   >>> travou alvo=%d tier=%d" % [alvo, tier]))
	print("[tr] arma equipada (item)=0x%02x · municao=%d · alvos na sala=%d"
		% [st.equipped_item_id(), st.equipped_qtd(), (w.player.alvos.call() as Array).size()])
	# 1) segura a mira por 12 ticks: passa por levantar -> pitch -> travar -> fogo
	for i in 12:
		pad.set_mask(Pad.AIM)
		w.tick(pad)
		print("[tr] t%-2d sub=%d acao=%d clipe=%s pitch=%d alvo=%d"
			% [i, w.player.mira_sub, w.player.acao, w.player.clipe_atual(),
			w.player.mira_pitch, w.player.mira_alvo])
	# 2) aperta o gatilho segurando a mira
	for i in 18:
		pad.set_mask(Pad.AIM | (Pad.ACAO if i == 0 else 0))
		w.tick(pad)
		if w.player.tiro_pendente >= 0:
			print("[tr] t%-2d tiro pendente no quadro %d (contando %d)"
				% [i, w.player.tiro_pendente, w.player.mira_quadro])
	print("[tr] municao depois do tiro=%d · recuo=%d" % [st.equipped_qtd(), w.player.recuo])
	# 3) sem munição = clique seco
	st.main_slots[st.equipped]["qtd"] = 0
	pad.set_mask(Pad.AIM)
	w.tick(pad)
	pad.set_mask(Pad.AIM | Pad.ACAO)
	w.tick(pad)
	print("[tr] municao 0 -> vazia=%s" % w.player.municao_vazia)
	quit(0)
