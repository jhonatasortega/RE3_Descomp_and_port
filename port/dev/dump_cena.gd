extends SceneTree
## Sonda das CENAS DE MOTOR de uma sala: roda a função na `Cena` e imprime a linha do tempo.
##
##     godot --headless --path port --script res://dev/dump_cena.gd            # R10D, entrada+saída
##     CENA_SALA=R10D CENA_FUNC=11 godot --headless --path port \
##         --script res://dev/dump_cena.gd
##
## `CENA_FUNC` vazio = roda as duas cenas do R10D (7 = entrada, 11 = saída).


func _initialize() -> void:
	var sala := OS.get_environment("CENA_SALA")
	if sala == "":
		sala = "R10D"
	var funcs: Array[int] = []
	var f := OS.get_environment("CENA_FUNC")
	if f != "":
		funcs.append(int(f))
	else:
		funcs = [7, 11]

	for fid: int in funcs:
		print("\n══════════ %s  função %d ══════════" % [sala, fid])
		var vm := ScriptVM.new()
		if not vm.carregar_sala(sala):
			print("  ERRO: %s" % vm.erro)
			continue
		var gs := GameState.new()
		vm.state = gs
		vm.modo = ScriptVM.Modo.EXECUCAO
		vm.executar(0)                      # init da sala: instala AOTs e objetos
		print("  init: %d AOTs, %d objetos" % [vm.aots.size(), vm.objetos.size()])
		for k in vm.aots:
			var a: Aot = vm.aots[k]
			print("   aot %d sce=%d %s" % [k, a.sce, a.resumo() if a.has_method("resumo") else ""])

		var cena := Cena.new()
		cena.iniciar(vm, fid, gs)
		# A Jill no spawn medido da abertura (docs/decomp/notes/boot_ptbr_hd.md §6.1).
		cena.por_ator(1, 0, Vector3i(9404, 0, -13317), 0)
		var q := cena.rodar(4000)
		print("  quadros: %d   eventos: %d" % [q, cena.eventos.size()])
		print("  câmeras: %s" % [cena.cameras()])
		print("  seqs de animação: %s" % [cena.seqs()])
		if not cena.troca_de_sala.is_empty():
			print("  TROCA DE SALA: %s" % [cena.troca_de_sala])
		print(cena.linha_do_tempo())
	quit(0)
