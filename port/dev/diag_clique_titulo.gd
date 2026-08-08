extends SceneTree
## SONDA do MOUSE na tela de título — hover e clique, do evento até o filme.
##
## Por que ela existe: o dono relatou "escolher a dificuldade com o mouse não inicia o vídeo,
## com o teclado inicia". Chamar `Titulo.clicar()` na mão só prova a caixa de acerto; o que
## faltava provar é o CAMINHO: evento -> `Boot._input` -> `Boot.clique`/`Boot.pairar` ->
## `Titulo.clicar`/`Titulo.pairar` -> `escolheu_novo_jogo` -> passo `fmv`.
##
##     # caminho do EVENTO de verdade (precisa de janela; é o que o dono usa)
##     "$GODOT" --path port --rendering-driver opengl3 --audio-driver Dummy \
##         --script res://dev/diag_clique_titulo.gd
##     # sem janela: entra por `Boot.clique()`/`Boot.pairar()`, o mesmo destino do evento
##     "$GODOT" --path port --headless --audio-driver Dummy \
##         --script res://dev/diag_clique_titulo.gd
##
## ⚠ **Por que ela tem dois caminhos.** Com `--headless` o viewport raiz fica **64×64** e a
## janela **0×0** (medido: `root.size == (64, 64)`, `DisplayServer.window_get_size() == (0, 0)`),
## então o `stretch_transform` do modo `canvas_items` vale 0,05 e `Viewport.push_input` desloca
## a posição do evento para fora da tela: o evento chega, em outro lugar. Isso é artefato do
## headless, não do jogo — por isso, sem janela, a sonda entrega o ponto direto em
## `Boot.clique()`/`Boot.pairar()` (onde o `_input` desemboca) e o caminho do evento é conferido
## com janela.
##
## ⚠ Não usar `Input.parse_input_event`: ele ENFILEIRA o evento (efeito só no quadro seguinte) e,
## com `--headless`, não chegou a ser despachado. `Viewport.push_input` é síncrono.

var _cena: Node
var _quadros := 0
var _falhas := 0
var _tem_janela := false
var _sfx: Array[int] = []


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn")
	_cena = packed.instantiate()
	_cena.set("entrar_no_jogo", false)          ## não troca de cena: quero ver o passo `fmv`
	_cena.set("tocar_fmv", false)               ## sem .ogv o passo é atravessado; o log basta
	root.add_child(_cena)


func _titulo() -> Object:
	return _cena.get("titulo")


func _centro_viewport(i: int) -> Vector2:
	## Centro do ALVO DE CLIQUE do item `i`, em coordenada de viewport (é o que o evento leva).
	var tt: Object = _titulo()
	var caixa: Rect2 = tt.call("caixa_de_clique", i)
	return (tt as Node2D).get_global_transform() * caixa.get_center()


func _pairar_em(i: int) -> void:
	var pos := _centro_viewport(i)
	if not _tem_janela:
		print("[mouse] (sem janela) Boot.pairar%s -> %s" % [pos, _cena.call("pairar", pos)])
		return
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	root.push_input(mm)


func _clicar_em(i: int) -> void:
	var pos := _centro_viewport(i)
	if not _tem_janela:
		print("[mouse] (sem janela) Boot.clique%s -> %s" % [pos, _cena.call("clique", pos)])
		return
	var bt := InputEventMouseButton.new()
	bt.button_index = MOUSE_BUTTON_LEFT
	bt.position = pos
	bt.global_position = pos
	bt.pressed = true
	bt.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(bt)
	var solta := InputEventMouseButton.new()
	solta.button_index = MOUSE_BUTTON_LEFT
	solta.position = pos
	solta.pressed = false
	root.push_input(solta)


func _ver(cond: bool, msg: String) -> void:
	if not cond:
		_falhas += 1
	print("[mouse] %s %s" % ["OK  " if cond else "FALHA", msg])


func _process(_delta: float) -> bool:
	_quadros += 1
	match _quadros:
		1:
			_tem_janela = root.size == Vector2i(1280, 960)
			_cena.call("_ir_para_passo", "menu")
			var tt: Object = _titulo()
			(tt as Object).connect("pediu_sfx", func(id: int) -> void: _sfx.append(id))
			print("[mouse] janela=%s viewport=%s passo=%s fase=%d cursor=%d"
				% [_tem_janela, root.size, _cena.call("passo_atual"), tt.get("fase"),
					tt.get("cursor")])
			for i in 3:
				print("[mouse]   item %d tinta=%s alvo=%s centro_viewport=%s"
					% [i, tt.call("caixa_do_item", i), tt.call("caixa_de_clique", i),
						_centro_viewport(i)])
			## HOVER em CONFIG (item 2): destaca sem disparar nada.
			_pairar_em(2)
		2:
			_ver(int(_titulo().get("cursor")) == Titulo.Item.CONFIG,
				"pairar em CONFIG move o cursor para 2 (cursor=%d)" % int(_titulo().get("cursor")))
			_ver(String(_cena.call("passo_atual")) == "menu",
				"e NÃO dispara nada (passo=%s)" % _cena.call("passo_atual"))
			_ver(_sfx == [4], "o hover pede o SFX 4 de cursor, uma vez (%s)" % str(_sfx))
			## COMEÇAR JOGO **não** está selecionado (o cursor abre em LOAD GAME, `0x801945b4`):
			## é o caso que a regra de dois cliques deixava parado.
			_clicar_em(0)
		3:
			_ver(int(_titulo().get("fase")) == Titulo.Fase.DIFICULDADE,
				"UM clique em COMEÇAR JOGO sai do menu e abre a DIFICULDADE (fase=%d)"
					% int(_titulo().get("fase")))
			_ver(int(_titulo().get("cursor")) == Titulo.Item.NOVO_JOGO,
				"e o cursor foi para o item clicado")
			for i in 2:
				print("[mouse]   dif %d tinta=%s alvo=%s"
					% [i, _titulo().call("caixa_do_item", i),
						_titulo().call("caixa_de_clique", i)])
			## MODO FACIL (item 1) NÃO está selecionado — o caso exato que o dono viu travado.
			_clicar_em(1)
		4:
			print("[mouse] passo=%s fase=%d facil=%s" % [_cena.call("passo_atual"),
				int(_titulo().get("fase")), _cena.get("facil")])
			_ver(String(_cena.call("passo_atual")) in ["fmv", "jogo"],
				"UM clique em MODO FACIL dispara o filme (passo=%s)" % _cena.call("passo_atual"))
			_ver(bool(_cena.get("facil")), "e a dificuldade escolhida é FÁCIL (bit 0x100)")
			print("[mouse] %d falha(s)" % _falhas)
			quit(1 if _falhas > 0 else 0)
			return true
	return false
