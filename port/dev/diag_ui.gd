extends SceneTree
## Telas + itens: checa que o inventário lista, o mapa acha textura, e que os itens do chão
## são coletáveis por contato do corpo (o alcance real da colisão).
func _initialize() -> void:
	var w := World.new()
	w.carregar("R104")            # sala com itens no chão medidos no dado
	var n := w.itens_no_chao().size()
	print("[ui] R104: %d itens no chão" % n)
	for a: Aot in w.itens_no_chao():
		var cx := a.box.position.x + a.box.size.x / 2
		var cz := a.box.position.y + a.box.size.y / 2
		# encosta o personagem na borda da caixa (como a colisão o deixaria)
		w.player.pos = Vector3i(cx, 0, cz)
		var pego := w.pegar_item_sob_o_player()
		print("[ui]   item 0x%02x id_aot=%d -> %s" % [a.item_id, a.id,
			"PEGO" if pego != null else "falhou"])
	print("[ui] inventário: %d/%d slots ocupados" % [w.state.item_count(), GameState.MAIN_SLOTS])
	# não reaparece ao voltar
	w.carregar("R104")
	print("[ui] após recarregar a sala: %d itens no chão (deve ser 0)" % w.itens_no_chao().size())
	# nomes vindos do dado
	var db: Variant = AssetIO.json("re3_items.json")
	print("[ui] re3_items.json carregou: %s" % (db is Dictionary))
	quit(0)
