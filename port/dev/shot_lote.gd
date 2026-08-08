extends SceneTree
## Fotografa, pelo caminho real: (0) menu na grade, (1) submenu aberto, (2) exame no meio da
## datilografia, (3) exame completo com a seta, (4) grade de arquivo pagina 1, (5) pagina 2.
var _cena: Node
var _t := 0
var _fase := 0

func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)

func _salvar(n: int) -> void:
	get_root().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_lote_%d.png" % n))
	print("[lt] _lote_%d.png" % n)

func _process(_d: float) -> bool:
	_t += 1
	if _t < 6:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var pad: Object = g.get("pad")
	var menu: Object = _cena.get("menu")
	var arq: Object = _cena.get("menu_arquivo")
	match _fase:
		0:
			for id: int in [0xa3, 0x86, 0x87, 0x88]:
				g.get("state").call("add_item", id, 1)
			pad.call("set_mask", Pad.MENU)
			_cena.call("_on_tick", _t)
			pad.call("set_mask", 0)
			for _k in 24:
				_cena.call("_on_tick", _t)
			_fase = 1
		1:
			_salvar(0)
			menu.call("confirmar")             ## abre o submenu do slot 0
			_cena.call("_on_tick", _t)
			_fase = 2
		2:
			_salvar(1)
			menu.set("sub_sel", 2)             ## EXAMINAR
			menu.call("confirmar")
			for _k in 4:
				_cena.call("_on_tick", _t)     ## deixa a datilografia no meio
			_fase = 3
		3:
			_salvar(2)
			for _k in 40:
				_cena.call("_on_tick", _t)     ## completa
			_fase = 4
		4:
			_salvar(3)
			menu.call("cancelar")
			menu.set("selecao_botao", 1)
			menu.call("confirmar")             ## ARQ.
			_cena.call("_on_tick", _t)
			_fase = 5
		5:
			_salvar(4)
			for _k in 5:
				arq.call("mover_grade", 1, 0)  ## anda ate virar a pagina
			_cena.call("_on_tick", _t)
			_fase = 6
		6:
			_salvar(5)
			print("[lt] pagina da grade=%s sel=%s" % [arq.call("pagina_grade"), arq.get("sel")])
			return true
	return false
