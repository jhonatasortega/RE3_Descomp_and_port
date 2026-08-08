extends SceneTree
## COBERTURA DAS CENAS pelo critério de dado (`Cena.auditar()`), nas 169 salas.
##
##     godot --headless --audio-driver Dummy --path port \
##         --script res://dev/diag_cena_cobertura.gd
##     COBERTURA_DETALHE=1 ... (lista cena por cena)
##
## Diferente do censo em Python (`tools/scd_cena_censo.py`, que é estático), aqui as cenas são as
## que o jogo REALMENTE abriria: roda `executar(0)` em cada sala e coleta
##   • as cenas de ENTRADA — `vm.threads_pedidas` (os `0x04` que o init executou de verdade);
##   • as cenas de GATILHO — o payload dos AOT `sce 5` que o init REGISTROU.
## Depois audita cada uma e mede quantas passam. É a métrica de "quantas cenas rodam".


func _initialize() -> void:
	var detalhe := OS.get_environment("COBERTURA_DETALHE") != ""
	var salas := _salas()
	var n_entrada := 0
	var n_gatilho := 0
	var ok_entrada := 0
	var ok_gatilho := 0
	var motivos: Dictionary = {}
	var faltando: Dictionary = {}
	var salas_com_cena: Dictionary = {}
	var salas_ok: Dictionary = {}
	for sala: String in salas:
		var vm := ScriptVM.new()
		if not vm.carregar_sala(sala):
			continue
		vm.state = GameState.new()
		vm.modo = ScriptVM.Modo.EXECUCAO
		vm.executar(0)
		var lista: Array[Dictionary] = []
		for p: Dictionary in vm.threads_pedidas:
			lista.append({"func": int(p["func"]), "tipo": "entrada"})
		for a: Aot in vm.aots_de_sce(Aot.SCE_EVENTO):
			var f := a.evento_func()
			if f >= 0:
				lista.append({"func": f, "tipo": "gatilho"})
		for c: Dictionary in lista:
			var tipo: String = c["tipo"]
			var fid: int = c["func"]
			if tipo == "entrada":
				n_entrada += 1
			else:
				n_gatilho += 1
			salas_com_cena[sala] = true
			var a2 := Cena.auditar(vm, fid)
			if bool(a2["ok"]):
				if tipo == "entrada":
					ok_entrada += 1
				else:
					ok_gatilho += 1
				salas_ok[sala] = true
				if detalhe:
					print("  OK    %s func %-3d %-8s %d funcs · %d opcodes inócuos" % [
						sala, fid, tipo, (a2["funcs"] as Array).size(),
						(a2["inocuos"] as Dictionary).size()])
			else:
				var chave := ""
				for k: int in (a2["bloqueantes"] as Dictionary):
					chave += "0x%02x " % k
					faltando[k] = int(faltando.get(k, 0)) + 1
				for k2: int in (a2["condicoes"] as Dictionary):
					chave += "while:0x%02x " % k2
					faltando[k2] = int(faltando.get(k2, 0)) + 1
				motivos[chave] = int(motivos.get(chave, 0)) + 1
				if detalhe:
					print("  NAO   %s func %-3d %-8s %s" % [sala, fid, tipo, str(a2["motivo"])])

	var n := n_entrada + n_gatilho
	var ok := ok_entrada + ok_gatilho
	print("\n══════════ COBERTURA DAS CENAS (critério `Cena.auditar()`) ══════════")
	print("cenas de ENTRADA : %4d   rodam %4d  (%.0f%%)" % [
		n_entrada, ok_entrada, 100.0 * ok_entrada / maxf(1.0, float(n_entrada))])
	print("cenas de GATILHO : %4d   rodam %4d  (%.0f%%)" % [
		n_gatilho, ok_gatilho, 100.0 * ok_gatilho / maxf(1.0, float(n_gatilho))])
	print("TOTAL            : %4d   rodam %4d  (%.0f%%)" % [
		n, ok, 100.0 * ok / maxf(1.0, float(n))])
	print("salas com cena   : %4d   com pelo menos uma rodando: %d" % [
		salas_com_cena.size(), salas_ok.size()])
	print("\nO QUE FALTA (opcode -> quantas cenas ele bloqueia):")
	var ks := faltando.keys()
	ks.sort_custom(func(x: int, y: int) -> bool: return int(faltando[x]) > int(faltando[y]))
	for k: int in ks:
		print("  0x%02x  %4d cenas   %s" % [k, int(faltando[k]), ScriptVM.name_of(k)])
	print("\nMOTIVOS agrupados:")
	var ms := motivos.keys()
	ms.sort_custom(func(x: String, y: String) -> bool: return int(motivos[x]) > int(motivos[y]))
	for m: String in ms:
		print("  %4d x  %s" % [int(motivos[m]), m])
	quit(0)


func _salas() -> Array[String]:
	var fora: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % st)
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.ends_with(".scd"):
				var id := nome.trim_suffix(".scd").to_upper()
				if not fora.has(id):
					fora.append(id)
	fora.sort()
	return fora
