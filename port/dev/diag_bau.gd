extends SceneTree
## Diagnóstico do gatilho do BAÚ (`sce 9`): para cada uma das 16 salas de save, monta a sala na
## VM e diz quantos AOTs de baú ficam ATIVOS, com a caixa e o SAT lidos do bytecode.
##
##     godot --headless --audio-driver Dummy --path port --script res://dev/diag_bau.gd
##
## Existe porque o teste do baú precisa de UMA sala de referência cuja caixa seja um FATO do
## bytecode. A sala tem de ser escolhida por medição, não por chute: o `sce 9` pode ser instalado
## por uma função tardia ou apagado por um `aot_reset` da própria montagem.

const SALAS := ["R100", "R10C", "R117", "R216", "R21B", "R300", "R306", "R30C", "R310",
	"R312", "R401", "R403", "R413", "R501", "R505", "R50B"]


func _initialize() -> void:
	for id in SALAS:
		var vm := ScriptVM.new()
		if not vm.carregar_sala(id):
			print("%s: NÃO CARREGA (%s)" % [id, vm.erro])
			continue
		vm.modo = ScriptVM.Modo.EXECUCAO
		vm.state = GameState.new()
		var nf := vm.func_offsets.size()
		for fi in nf:
			vm.executar(fi)
		var b := vm.baus()
		var s := vm.aots_de_sce(Aot.SCE_SAVE)
		var linha := "%s: funcs=%2d aots=%2d bau=%d save=%d" % [id, nf, vm.aots.size(),
			b.size(), s.size()]
		for a: Aot in b:
			linha += "\n    baú id=%d sat=0x%02x kind=%s box=%s piso=%d" % [
				a.id, a.sat, Aot.Kind.keys()[a.kind], a.box, a.floor_id]
		print(linha)
	quit(0)
