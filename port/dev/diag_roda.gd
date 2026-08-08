extends SceneTree
## DIAGNÓSTICO da RODA DO MOUSE no menu (defeito relatado: "a roda não avança a página de
## EXAMINAR nem a de ler documento").
##
## Por que existe: a roda em Godot é EVENTO, não estado. O `screen.gd` lia por polling com
## `Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP/DOWN)`, que devolve `false` sempre — a
## borda nunca acontecia e `rol` era 0 em todo tick. Este script injeta eventos de roda de
## verdade (`Input.parse_input_event`) na cena do jogo e imprime o que a página fez, para a
## correção não depender de "eu acho que agora vai".
##
## godot --rendering-driver opengl3 --path port --script res://dev/diag_roda.gd

const CENA := "res://scenes/game.tscn"

var _t := 0
var _scr: Node = null
var _fase := 0
var _espera := 0                     ## quadros a esperar antes da próxima fase
var _pag_antes := 0
var _linha_antes := 0
var _falhas := 0


func _initialize() -> void:
	var ps: PackedScene = load(CENA)
	if ps == null:
		print("[roda] não carregou %s" % CENA)
		quit(1)
		return
	get_root().add_child(ps.instantiate())


func _roda(passos: int) -> void:
	## Um "clique" de roda = evento pressionado + evento solto, como o motor entrega.
	for _i in absi(passos):
		for apertado in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_WHEEL_DOWN if passos > 0 else MOUSE_BUTTON_WHEEL_UP
			e.pressed = apertado
			e.position = Vector2(640, 480)
			Input.parse_input_event(e)
	Input.flush_buffered_events()


func _process(_d: float) -> bool:
	_t += 1
	if _t < 20:
		return false
	## O menu roda no tick de 30 Hz do `Game` e a abertura leva 6 quadros de animação
	## (`MenuStatus.ANIM_QUADROS`), durante os quais `confirmar()` é ignorado. Então cada fase
	## espera quadros de render suficientes para os ticks acontecerem.
	if _espera > 0:
		_espera -= 1
		return false
	if _scr == null:
		_scr = get_root().get_child(get_root().get_child_count() - 1)
		if _scr == null or _scr.get("menu") == null:
			print("[roda] a cena não tem `menu` — abortando")
			return true
	var menu: Object = _scr.get("menu")
	var arq: Object = _scr.get("menu_arquivo")
	match _fase:
		0:
			menu.call("alternar")                     ## abre o inventário
			_espera = 30
			_fase = 1
		1:
			## EXAMINAR: procura o primeiro slot cujo item tenha texto de exame no `re3_items.json`
			for slot in 10:
				menu.set("cursor", slot)
				menu.call("confirmar")                ## abre o submenu do item
				if (menu.get("sub_itens") as Array).is_empty():
					continue
				menu.set("sub_sel", 2)                ## CHECK
				menu.call("confirmar")
				if String(menu.get("mensagem")) != "":
					print("[roda] EXAMINAR no slot %d" % slot)
					break
				menu.call("cancelar")
			_linha_antes = int(menu.get("mensagem_linha"))
			print("[roda] EXAMINAR aberto: %d caracteres, linha %d" % [
				String(menu.get("mensagem")).length(), _linha_antes])
			_roda(3)                                  ## rola para baixo
			_espera = 10
			_fase = 2
		2:
			## O 1º lote de roda é consumido PULANDO a máquina de escrever (é o que o direcional
			## para baixo faz no jogo: `mover_cursor` com `dy > 0` e `_datilo < len` retorna ali).
			## Então o teste real é o SEGUNDO lote.
			print("[roda] 1º lote: datilo pulado? %s (linha %d)" % [
				str(int(menu.get("_datilo")) >= String(menu.get("mensagem")).length()),
				int(menu.get("mensagem_linha"))])
			_roda(1)
			_espera = 10
			_fase = 21
		21:
			var linha := int(menu.get("mensagem_linha"))
			print("[roda] 2º lote de roda: linha %d (antes %d)" % [linha, _linha_antes])
			if linha == _linha_antes:
				print("[roda] FALHOU: a roda não rolou o texto de EXAMINAR")
				_falhas += 1
			menu.call("cancelar")                     ## sai do EXAMINAR
			arq.call("abrir")
			arq.call("ir_para_doc", 0)                ## entra na leitura do documento 0
			_pag_antes = int(arq.get("pagina"))
			print("[roda] documento aberto na página %d (lendo=%s)" % [
				_pag_antes, str(arq.get("lendo"))])
			_roda(1)
			_espera = 10
			_fase = 3
		3:
			var pag := int(arq.get("pagina"))
			print("[roda] depois de 1 passo de roda: página %d (antes %d)" % [pag, _pag_antes])
			if pag == _pag_antes:
				print("[roda] FALHOU: a roda não virou a página do documento")
				_falhas += 1
			_roda(-1)
			_espera = 10
			_fase = 4
		4:
			print("[roda] roda para cima: página %d (esperado %d)" % [
				int(arq.get("pagina")), _pag_antes])
			if int(arq.get("pagina")) != _pag_antes:
				print("[roda] FALHOU: a roda para cima não voltou a página")
				_falhas += 1
			print("[roda] RESULTADO: %s" % ("VERDE" if _falhas == 0 else "%d falha(s)" % _falhas))
			return true
	return false
