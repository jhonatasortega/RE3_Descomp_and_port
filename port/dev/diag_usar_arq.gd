extends SceneTree
func _initialize() -> void:
	for id: int in [0x83, 0x84, 0x85, 0xa1, 0xa3]:
		print("[ua] item 0x%02x cat=%d max=%d equip=%s" % [id, Itens.categoria(id),
			Itens.maximo(id), Itens.equipavel(id)])
	print("[ua] CAT_ARQUIVO = %d" % Itens.CAT_ARQUIVO)
	quit(0)
