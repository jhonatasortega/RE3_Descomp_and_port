extends SceneTree
## Aperta as teclas DE VERDADE (pelo pad + `_on_tick`) dentro do leitor de arquivo e reporta a
## página a cada tecla. Pega bug de ROTEAMENTO, que a chamada direta de `virar_pagina` não pega.
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
		st.call("add_item", 0x93, 1)          ## Jill's Diary (doc14, 9 páginas)
		_tecla(pad, Pad.MENU)                  ## abre o menu
		for _k in 24:                          ## espera a animação de abertura (_anim > 0 barra o Enter)
			_cena.call("_on_tick", _t)
		menu.set("selecao_botao", 1)           ## ARQ.
		menu.call("confirmar")
		print("[le] arquivo aberto=%s docs=%d" % [arq.get("aberto"), (arq.get("docs") as Array).size()])
		# escolhe o Diário na grade e entra
		if not bool(arq.get("aberto")):
			return true
		var docs: Array = arq.get("docs")
		for i in docs.size():
			if int((docs[i] as Dictionary).get("item_id", 0)) == 0x93:
				arq.set("sel", i)
		var doc: Dictionary = (arq.get("docs") as Array)[int(arq.get("sel"))]
		print("[le] doc escolhido: doc%d n_pages=%d" % [doc.get("doc"), doc.get("n_pages")])
		_tecla(pad, Pad.ACAO)                ## confirma -> lendo
		print("[le] lendo=%s pagina=%s" % [arq.get("lendo"), arq.get("pagina")])
		_fase = 1
		return false
	# 6 apertos de D (direita) e depois W/S, pelo caminho real
	for nome: String in ["D", "D", "D", "D", "D", "D", "S", "W", "A"]:
		var bit := Pad.HELD_RIGHT
		if nome == "A":
			bit = Pad.HELD_LEFT
		elif nome == "S":
			bit = Pad.HELD_DOWN
		elif nome == "W":
			bit = Pad.HELD_UP
		_tecla(pad, bit)
		print("[le]   tecla %s -> pagina=%s lendo=%s sel=%s" % [nome, arq.get("pagina"),
			arq.get("lendo"), arq.get("sel")])
	return true

func _tecla(pad: Object, bit: int) -> void:
	pad.call("set_mask", bit)
	_cena.call("_on_tick", _t)
	pad.call("set_mask", 0)
	_cena.call("_on_tick", _t)
