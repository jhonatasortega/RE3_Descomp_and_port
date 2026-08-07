extends SceneTree
## Prova da tela de ARQUIVO pelo caminho real: abre o menu (I), navega até ARQ., confirma, e
## salva a LISTA e uma PÁGINA aberta.
var _cena: Node
var _t := 0
var _fase := 0
var _nome := ""


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
	if arq == null:
		print("[ar] Screen.menu_arquivo é null")
		return true
	if _fase == 0:
		# dá alguns documentos ao jogador (categoria 7 = arquivo no descritor)
		var st: Object = g.get("state")
		var n := 0
		for d: Dictionary in (arq.get("_dados") as Dictionary).get("documentos", []):
			st.call("add_item", int(d.get("item_id", 0)), 1)
			n += 1
			if n >= 4:
				break
		print("[ar] %d documentos no inventário" % n)
		pad.call("set_mask", Pad.MENU)
		_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		for _k in 8:
			_cena.call("_on_tick", _t)
		# vai para os botões e escolhe ARQ.
		menu.call("mover_cursor", 0, -1)
		menu.set("selecao_botao", 1)
		var feito: String = menu.call("confirmar")
		print("[ar] ARQ. -> %s · aberto=%s · %d docs" % [feito, arq.get("aberto"),
			(arq.get("docs") as Array).size()])
		_fase = 1
		return false
	if _fase == 1:
		_cena.call("_on_tick", _t)
		_nome = "_shot_arquivo_lista.png"
		_fase = 2
		return false
	if _fase == 2:
		get_root().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://%s" % _nome))
		print("[ar] salvo %s" % _nome)
		# abre o documento e vira para a página de texto
		arq.call("confirmar")
		arq.call("mover", 1)
		_cena.call("_on_tick", _t)
		_nome = "_shot_arquivo_pagina.png"
		_fase = 3
		return false
	if _fase == 3:
		_cena.call("_on_tick", _t)
		_fase = 4
		return false
	get_root().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://%s" % _nome))
	print("[ar] salvo %s (pagina %s)" % [_nome, arq.get("pagina")])
	return true
