extends SceneTree
## Diagnóstico do "SUBIR EM OBJETO" (rotina 9): varre TODAS as salas, monta cada uma na VM e
## lista os objetos `0x7f` que passam na porta estática do motor (`ObjetoSala.escalavel()` —
## `be_flg & 0x100` aceso e `& 0x4000` apagado, sítios `0x800365a4` e `0x8003659c`).
##
##     godot --headless --audio-driver Dummy --path port --script res://dev/diag_subir.gd
##
## Serve para responder, com dado e não com palpite, "em que salas do jogo a Jill sobe em cima de
## alguma coisa?" — e para mostrar que o **R10D não é uma delas** (os 3 objetos dele têm
## `be_flg = 0x6001`: reprovam nos dois bits).


func _initialize() -> void:
	var salas := _listar_salas()
	var total_om := 0
	var com_ponto: Array[String] = []
	var hist: Dictionary = {}
	for id in salas:
		var vm := ScriptVM.new()
		if not vm.carregar_sala(id):
			continue
		vm.modo = ScriptVM.Modo.EXECUCAO
		vm.state = GameState.new()
		for fi in vm.func_offsets.size():
			vm.executar(fi)
		var linha := ""
		for k in vm.objetos:
			var o: ObjetoSala = vm.objetos[k]
			total_om += 1
			hist[o.be_flg] = int(hist.get(o.be_flg, 0)) + 1
			if o.escalavel():
				linha += "\n    om %d be_flg=0x%04x pos=%s rot=%s" % [o.slot, o.be_flg, o.pos, o.rot]
		if linha != "":
			com_ponto.append(id)
			print("%s:%s" % [id, linha])
		if id == "R10D":
			print("R10D (a sala da 'lixeira') — os 3 objetos dela:")
			for k in vm.objetos:
				var o: ObjetoSala = vm.objetos[k]
				print("    om %d be_flg=0x%04x escalavel=%s  (0x100=%d 0x4000=%d) pos=%s" % [
					o.slot, o.be_flg, o.escalavel(),
					1 if o.be_flg & ObjetoSala.BE_ESCALAVEL else 0,
					1 if o.be_flg & ObjetoSala.BE_NAO_ESCALAVEL else 0, o.pos])

	print("\n%d salas, %d objetos 0x7f vivos, %d salas com objeto escalável: %s" % [
		salas.size(), total_om, com_ponto.size(), str(com_ponto)])
	var chaves := hist.keys()
	chaves.sort()
	var h := ""
	for c in chaves:
		h += " 0x%04x×%d" % [c, hist[c]]
	print("be_flg observados:%s" % h)

	# e o que o SubirObjeto instala por sala (é o que o player.gd vai consumir)
	for id in com_ponto:
		var s := SubirObjeto.new()
		var n := s.carregar_sala(id)
		print("SubirObjeto.carregar_sala(%s) -> %d ponto(s)" % [id, n])
		for p: Dictionary in s.pontos:
			print("    caixa=%s y_topo=%d  %s" % [p["caixa"], p["y_topo"], p["nota"]])
	print("SubirObjeto.carregar_sala(R10D) -> %d" % SubirObjeto.new().carregar_sala("R10D"))
	quit(0)


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % st)
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.ends_with(".scd"):
				saida.append(nome.trim_suffix(".scd"))
	saida.sort()
	return saida
