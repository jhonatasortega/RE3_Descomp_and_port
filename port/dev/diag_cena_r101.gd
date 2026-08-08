extends SceneTree
## Sonda da CENA DE ENTRADA de uma sala: descobre, pelo próprio init, quais THREADS o script
## pede (`0x04 evt_exec`) e roda a função escolhida na `Cena`, imprimindo a linha do tempo.
##
##     godot --headless --path port --script res://dev/diag_cena_r101.gd
##     CENA_SALA=R101 CENA_FUNC=3 godot --headless --path port \
##         --script res://dev/diag_cena_r101.gd
##
## É o método que fechou o `R10D` (`docs/decomp/notes/cena_r10d.md` §2), agora automático: em vez
## de ler o bytecode à mão, o `ScriptVM` em `Modo.EXECUCAO` REGISTRA os `0x04` que o init executa
## (`vm.threads_pedidas`) — o que respeita os `if`/`0x4c` de flag e portanto diz qual é a cena de
## PRIMEIRA VISITA.


func _initialize() -> void:
	var sala := OS.get_environment("CENA_SALA")
	if sala == "":
		sala = "R101"
	var gs := GameState.new()
	var vm := ScriptVM.new()
	if not vm.carregar_sala(sala):
		print("ERRO: %s" % vm.erro)
		quit(1)
		return
	vm.state = gs
	vm.modo = ScriptVM.Modo.EXECUCAO
	vm.executar(0)
	print("══════════ %s — init (executar(0)) ══════════" % sala)
	print("  %d AOTs · %d objetos · %d flags lidos" % [
		vm.aots.size(), vm.objetos.size(), vm.flags_lidos])
	print("  THREADS que o init pediu (0x04 evt_exec): %s" % [vm.threads_pedidas])
	for k in vm.aots:
		var a: Aot = vm.aots[k]
		if a.sce == Aot.SCE_EVENTO:
			print("  gatilho sce 5: aot %d nFloor=0x%02x caixa=%s -> função %d" % [
				k, a.floor_id, a.box, a.evento_func()])

	var funcs: Array[int] = []
	var f := OS.get_environment("CENA_FUNC")
	if f != "":
		funcs.append(int(f))
	else:
		for p: Dictionary in vm.threads_pedidas:
			funcs.append(int(p["func"]))
	for fid: int in funcs:
		print("\n══════════ %s  função %d ══════════" % [sala, fid])
		var vm2 := ScriptVM.new()
		vm2.carregar_sala(sala)
		vm2.state = GameState.new()
		vm2.modo = ScriptVM.Modo.EXECUCAO
		vm2.executar(0)
		var cena := Cena.new()
		cena.iniciar(vm2, fid, vm2.state)
		var q := cena.rodar(4000)
		print("  quadros: %d   eventos: %d" % [q, cena.eventos.size()])
		print("  câmeras: %s" % [cena.cameras()])
		print("  seqs de animação: %s" % [cena.seqs()])
		if not cena.troca_de_sala.is_empty():
			print("  TROCA DE SALA: %s" % [cena.troca_de_sala])
		print("  posição do player no fim: %s" % [cena.ator_pos(1, 0)])
		print(cena.linha_do_tempo())
	quit(0)
