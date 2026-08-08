extends SceneTree
## Render da tela do BAÚ DE ITENS (`sce 9`, screen kind 2) para conferir contra o jogo original.
## Enche a mão e o baú com itens conhecidos, abre a tela e salva `dev/_shot_bau.png`.
##
##     godot --path port --rendering-driver opengl3 --audio-driver Dummy \
##         --script res://dev/shot_bau.gd
##
## Não usa `--headless` de propósito: sem render não há textura para capturar.
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
		# MÃO: arma, munição, cura, chave (é de lá que se guarda)
		for par: Array in [[0x03, 15], [0x15, 30], [0x14, 3], [0x41, 1], [0x22, 1]]:
			st.add_item(int(par[0]), int(par[1]), 0x0001)
		# BAÚ: algo em cada página, para a paginação aparecer na captura
		for i in [0, 1, 2, 7, 19, 20, 33, 40, 63]:
			st.box_slots[i] = {"id": 0x15 if i % 2 == 0 else 0x0f, "qtd": 50 + i, "flags": 0x0001}
		_menu = MenuBau.new()
		if not _menu.carregar(st):
			print("[bau] assets ausentes — rode: python tools/status_assets.py --all")
			return true
		_cena.add_child(_menu)
		_menu.call("abrir")
		print("[bau] %s" % _menu.call("resumo"))
		return false
	if _t < 6 or _salvo:
		return _salvo and _t > 40
	if _t < 30:
		_menu.call("avancar")          ## deixa a cortina de 6 quadros e a piscada andarem
		return false
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://dev/_shot_bau.png"))
	print("[bau] salvo dev/_shot_bau.png · %s" % _menu.call("resumo"))
	_salvo = true
	return false
