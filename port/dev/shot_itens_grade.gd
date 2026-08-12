extends SceneTree
## Prova visual do DE-PARA DO ÍCONE DA GRADE e da COMBINAÇÃO pólvora + Prensadora.
##
## Por que existe: o dono relatou a **Fita de tinta `0x81`** aparecendo na grade com o ícone da
## caixa de munição de escopeta (`0x17`), enquanto a placa grande ao lado mostrava a arte certa.
## A causa era o casamento dos `.webp` HD; agora o de-para é por hash exato
## (`tools/hd_match.py hash`). Esta captura coloca justamente os itens envolvidos, na ordem, para
## conferir ícone pequeno × placa grande no mesmo quadro.
##
##     godot --path port --rendering-driver opengl3 --audio-driver Dummy \
##         --script res://dev/shot_itens_grade.gd
##
## Sem `--headless` de propósito: sem render não há textura para capturar. A imagem sai em
## `dev/_shots/`, nunca na raiz do `port/`.
##
## `GRADE_CURSOR=n` escolhe o slot selecionado (a placa grande é a do slot sob o cursor), então
## dá para varrer os 10 itens sem editar o script.
const CARGA := [
	[0x81, 3],       ## Fita de tinta      — o item do relato
	[0x17, 15],      ## Cartuchos de escopeta — o ícone que aparecia errado no 0x81
	[0x82, 3],       ## Prensadora
	[0x61, 1],       ## Pólvora A
	[0x62, 1],       ## Pólvora B
	[0x63, 1],       ## Pólvora C
	[0x03, 15],      ## Pistola
	[0x04, 7],       ## Escopeta
	[0x21, 1],       ## Erva verde
	[0x20, 1],       ## Spray medicinal
]

var _cena: Node
var _menu: Node2D
var _t := 0
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
		## Escreve os slots DIRETO: `add_item` empilha no que o loadout inicial já pôs, e a grade
		## desta prova precisa dos 10 itens exatos e na ordem.
		for i in CARGA.size():
			st.main_slots[i] = {"id": int(CARGA[i][0]), "qtd": int(CARGA[i][1]), "flags": 0}
		_menu = MenuStatus.new()
		if not _menu.carregar(st):
			print("[ig] assets ausentes — rode: python tools/status_assets.py --all")
			return true
		_cena.add_child(_menu)
		_menu.alternar()
		var cur := int(OS.get_environment("GRADE_CURSOR"))
		_menu.set("cursor", clampi(cur, 0, 9))
		print("[ig] grade: %s" % [CARGA.map(func(p: Array) -> String: return "0x%02x" % p[0])])
		print("[ig] cursor no slot %d (a placa grande é a dele)" % clampi(cur, 0, 9))
		return false
	if _t < 30:
		if _menu != null:
			_menu.avancar()
		return false
	if not _salvo:
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://dev/_shots/_itens_grade.png"))
		print("[ig] salvo dev/_shots/_itens_grade.png")
		## COMBINAÇÃO: Prensadora (slot 2) + Pólvora A (slot 3) -> Balas de pistola.
		_menu.set("combinar_de", 2)
		_menu.set("cursor", 3)
		print("[ig] combinar -> %s" % _menu.call("confirmar"))
		var st2: GameState = _menu.get("_state")
		for i in 4:
			var s: Dictionary = st2.main_slots[i]
			print("[ig]   slot %d: id=0x%02x qtd=%d" % [i, int(s["id"]), int(s["qtd"])])
		_salvo = true
		return false
	if _t < 60:
		_menu.avancar()
		return false
	var img2 := get_root().get_texture().get_image()
	img2.save_png(ProjectSettings.globalize_path("res://dev/_shots/_itens_combinado.png"))
	print("[ig] salvo dev/_shots/_itens_combinado.png")
	return true
