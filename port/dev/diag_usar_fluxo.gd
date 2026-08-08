extends SceneTree
## Aperta USAR num documento pelo caminho real e reporta cada passo.
var _cena: Node
var _t := 0
var _fase := 0

func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)

func _process(_d: float) -> bool:
	_t += 1
	if _t < 6:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var pad: Object = g.get("pad")
	var menu: Object = _cena.get("menu")
	var arq: Object = _cena.get("menu_arquivo")
	if _fase == 0:
		var st: Object = g.get("state")
		print("[uf] state do jogo=%s · state do menu=%s · state do arquivo=%s"
			% [st, menu.get("_state"), arq.get("_state")])
		var slots: Array = st.get("main_slots")
		for i in slots.size():
			var d: Dictionary = slots[i]
			if int(d.get("id", 0)) != 0:
				print("[uf] slot %d = 0x%02x qtd=%s flags=%s" % [i, d.get("id"), d.get("qtd"),
					d.get("flags")])
		pad.call("set_mask", Pad.MENU)
		_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		for _k in 24:
			_cena.call("_on_tick", _t)
		_fase = 1
		return false
	# cursor no slot 2 (Instruções A) e abre o submenu
	menu.set("cursor", 2)
	print("[uf] confirmar na grade -> %s · sub=%s" % [menu.call("confirmar"),
		str(menu.get("sub_itens"))])
	menu.set("sub_sel", 0)
	print("[uf] confirmar USAR -> %s" % menu.call("confirmar"))
	print("[uf] arquivo aberto=%s lendo=%s docs=%d sel=%s"
		% [arq.get("aberto"), arq.get("lendo"), (arq.get("docs") as Array).size(), arq.get("sel")])
	print("[uf] lidos=%s" % str(g.get("state").get("arquivos_lidos")))
	return true
