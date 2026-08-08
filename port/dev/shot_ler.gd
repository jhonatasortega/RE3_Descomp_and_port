extends SceneTree
## Fotografa o LEITOR de arquivo em páginas seguidas, pelo caminho real (pad + _on_tick).
var _cena: Node
var _t := 0
var _fase := 0
var _pag := 0

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
		g.get("state").call("add_item", 0xa3, 1)
		g.get("state").call("marcar_arquivo_lido", 0xa3)      ## Jill's Diary
		pad.call("set_mask", Pad.MENU)
		_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		for _k in 24:
			_cena.call("_on_tick", _t)
		menu.set("selecao_botao", 1)
		menu.call("confirmar")
		arq.call("confirmar")                          ## entra no documento
		_fase = 1
		return false
	if _fase == 1:
		_cena.call("_on_tick", _t)                     ## desenha
		_fase = 2
		return false
	get_root().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_ler_%d.png" % _pag))
	print("[sl] _ler_%d.png · pagina=%s" % [_pag, arq.get("pagina")])
	_pag += 1
	if _pag >= 4:
		return true
	pad.call("set_mask", Pad.HELD_RIGHT)
	_cena.call("_on_tick", _t)
	pad.call("set_mask", 0)
	_fase = 1
	return false
