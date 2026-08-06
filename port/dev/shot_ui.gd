extends SceneTree
## Screenshot das TELAS (inventário com itens, mapa, menu principal).
var _cena: Node
var _t := 0
var _fase := 0
const SAIDAS := ["res://_ui_inventario.png", "res://_ui_mapa.png", "res://_ui_menu.png"]
func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)
func _process(_d: float) -> bool:
	_t += 1
	if _t < 8:
		return false
	var telas: Node = _cena.get("telas")
	var mundo: Object = _cena.get("mundo")
	if telas == null:
		print("[shot_ui] sem telas"); return true
	if _t == 8:
		# põe itens no inventário para a tela não sair vazia
		var st: Object = mundo.get("state")
		for par in [[0x01, 1], [0x03, 1], [0x21, 2], [0x41, 1], [0x60, 1], [0x33, 1]]:
			st.call("add_item", par[0], par[1])
		telas.call("abrir", 1)      # INVENTARIO
		return false
	if _t == 12:
		_salvar(0)
		telas.call("abrir", 2)      # MAPA
		return false
	if _t == 16:
		_salvar(1)
		telas.call("abrir", 4)      # MENU_PRINCIPAL
		return false
	if _t == 20:
		_salvar(2)
		print("[shot_ui] 3 telas salvas")
		return true
	return false
func _salvar(i: int) -> void:
	var img := get_root().get_texture().get_image()
	var abs_path: String = ProjectSettings.globalize_path(SAIDAS[i])
	img.save_png(abs_path)
	print("[shot_ui] %s" % abs_path)
