extends SceneTree
## Prova do caminho REAL do jogo: aperta **I** no pad e o menu tem de abrir, o mundo tem de
## congelar, e apertar I de novo tem de fechar. Salva `_shot_menu_i.png` com o menu aberto.
var _cena: Node
var _t := 0
var _pos_antes := Vector3i.ZERO
var _fase := 0


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _t < 6:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var pad: Object = g.get("pad")
	var mundo: Object = _cena.get("mundo")
	var menu: Object = _cena.get("menu")
	if menu == null:
		print("[mi] Screen.menu é null — o menu não foi criado")
		return true
	if _fase == 0:
		# ANDA primeiro (como o usuário fez: pos z mudou de -21899 para ~-21151) e só então abre
		pad.call("set_mask", Pad.FWD)
		for _k in 30:
			_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		print("[mi] depois de andar: pos=%s" % mundo.get("player").get("pos"))
		# põe itens no inventário para a grade não estar vazia
		var st: Object = g.get("state")
		for par: Array in [[0x0f, 1], [0x18, 30], [0x21, 1], [0x73, 1]]:
			st.call("add_item", int(par[0]), int(par[1]))
		print("[mi] texturas: chrome=%s retratos=%s palavras=%s fator=%s" % [
			_tam(menu.get("_chrome")), _tam(menu.get("_retratos")),
			_tam(menu.get("_palavras")), menu.get("_palavras_fator")])
		for id: int in [0x0f, 0x18, 0x21, 0x73, 0]:
			var tx: Texture2D = menu.call("_icone", id)
			print("[mi]   icone 0x%02x -> %s" % [id, _tam(tx)])
		_pos_antes = mundo.get("player").get("pos")
		pad.call("set_mask", Pad.MENU)                  ## aperta I
		_cena.call("_on_tick", _t)
		print("[mi] apertei I -> aberto=%s" % menu.get("aberto"))
		_fase = 1
		return false
	if _fase == 1:
		pad.call("set_mask", 0)                         ## solta
		for _k in 10:
			_cena.call("_on_tick", _t)                  ## deixa a animação de 6 quadros correr
		var depois: Vector3i = mundo.get("player").get("pos")
		print("[mi] aberto=%s · mundo congelado=%s (pos %s -> %s)" % [
			menu.get("aberto"), depois == _pos_antes, _pos_antes, depois])
		_fase = 2
		return false
	if _fase == 2:
		# ENTER no item selecionado: tem de abrir o submenu (EQUIP/USE + COMBINE + CHECK)
		pad.call("set_mask", Pad.ACAO)
		_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		_cena.call("_on_tick", _t)
		print("[mi] Enter no item -> %s · submenu=%s" % [
			menu.get("ultima_acao"), menu.get("sub_itens")])
		_fase = 3
		return false
	if _fase == 3:
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://_shot_menu_i.png"))
		print("[mi] salvo _shot_menu_i.png")
		pad.call("set_mask", Pad.MENU)                  ## aperta I de novo
		_cena.call("_on_tick", _t)
		pad.call("set_mask", 0)
		for _k in 8:
			_cena.call("_on_tick", _t)
		print("[mi] apertei I de novo -> aberto=%s (deve ser false)" % menu.get("aberto"))
		return true
	return false
	return false


func _tam(t: Object) -> String:
	if t == null:
		return "NULA"
	return "%s" % (t as Texture2D).get_size()
