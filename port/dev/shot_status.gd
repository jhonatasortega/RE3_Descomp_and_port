extends SceneTree
## Render da tela de STATUS/INVENTÁRIO para conferir contra a captura do jogo original.
## Põe itens conhecidos no inventário (para a grade ter conteúdo) e salva `_shot_status.png`.
var _cena: Node
var _t := 0
var _menu: Node2D
var _salvo := false


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _t == 5:
		var g: Node = _cena.get_node_or_null("/root/Game")
		var st: GameState = g.get("state") if g != null else GameState.new()
		# inventário parecido com o da captura de referência: fuzil, isqueiro, munição, dois
		# documentos, kit, chave e dois frascos
		var carga := [[0x0f, 1], [0x41, 1], [0x18, 30], [0x85, 1], [0x86, 1],
			[0x14, 3], [0x73, 1], [0x22, 1], [0x21, 1], [0x23, 1]]
		for par: Array in carga:
			st.add_item(int(par[0]), int(par[1]))
		_menu = MenuStatus.new()
		if not _menu.carregar(st):
			print("[st] assets ausentes — rode: python tools/status_assets.py --all")
			return true
		_cena.add_child(_menu)
		_menu.alternar()
		print("[st] menu aberto · %d itens no inventário" % st.item_count())
		return false
	if _t < 6 or _salvo:
		return _salvo and _t > 40
	# deixa a animação de 6 quadros terminar e a piscada andar
	if _t < 30:
		_menu.avancar()
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://_shot_status.png"))
	# recorte só da tela do menu (320x240 escalado 4x = o quadro inteiro)
	print("[st] salvo _shot_status.png · cursor=%d condicao=%d" % [
		_menu.get("cursor"), _menu.call("condicao")])
	_salvo = true
	return false
