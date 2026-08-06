extends RefCounted
## AOT instalados pela VM vs. portas extraídas pelo Python (itens P2-04 / P2-05).
##
## Este teste vale por dois motivos:
##
## 1. **Cruza duas fontes independentes.** O extrator Python (`tools/scd_gameplay.py` /
##    `scd_door_dest.py`) acha os AOT por VARREDURA com heurística (testa se `byte+3` está num
##    conjunto de valores plausíveis, etc.), porque não executa o script. A VM do port não
##    precisa de heurística: ela conhece a fronteira real de cada instrução. Se as duas chegam
##    às mesmas portas, os dois lados estão certos.
## 2. É o que sustenta a F3: sem AOT de porta com destino, não há mundo conectado.
##
## Referência: 453 portas nas 169 salas (docs/decomp/notes/door_handler.md).

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("AOT")

	# --- offsets e semântica ---
	t.eq(Aot.SCE_PORTA, 1, "sce 1 = porta")
	t.eq(Aot.SCE_PORTA_13, 13, "sce 13 = porta (handler 0x80051cb0)")
	var a := Aot.new()
	a.kind = Aot.Kind.BOX
	a.box = Rect2i(-100, -200, 50, 80)
	t.check(a.contem(-80, -180), "AABB contém ponto interno")
	t.check(not a.contem(-200, -180), "AABB rejeita ponto fora")
	a.ativo = false
	t.check(not a.contem(-80, -180), "AOT desativado (aot_reset) não dispara")

	# --- a R100 tem 1 porta, para a R101 (dado conhecido) ---
	var vm := ScriptVM.new()
	t.check(vm.carregar_sala("R100"), "R100 carrega")
	vm.modo = ScriptVM.Modo.EXECUCAO
	vm.state = GameState.new()
	for fi in vm.func_offsets.size():
		vm.executar(fi)
	var portas := vm.portas()
	t.check(portas.size() >= 1, "a VM instalou pelo menos 1 porta na R100",
		"%d portas, %d AOTs" % [portas.size(), vm.aots.size()])
	if portas.size() > 0:
		var p0: Aot = portas[0]
		t.eq(p0.to_room_id(), "R101", "a porta da R100 leva à R101 (destino estático)")
		t.check(p0.to_pos != Vector3i.ZERO, "a porta tem posição de chegada", str(p0.to_pos))

	# --- TESTE CRUZADO: VM vs extrator Python, nas 169 salas ---
	var salas := _listar_salas()
	var total_vm := 0
	var total_py := 0
	var casaram := 0
	var so_vm := 0
	var so_py := 0
	var exemplos: Array[String] = []
	var salas_ok := 0
	for id in salas:
		var scd: Variant = AssetIO.json("STAGE%d/%s_scd.json" % [RoomData.stage_of(id), id])
		if not (scd is Dictionary):
			continue
		var py_doors: Array = (scd as Dictionary).get("doors", [])
		var esperado := {}
		for d: Dictionary in py_doors:
			esperado[str(d.get("to_room_id", ""))] = true
		total_py += py_doors.size()

		var v := ScriptVM.new()
		if not v.carregar_sala(id):
			continue
		v.modo = ScriptVM.Modo.EXECUCAO
		v.state = GameState.new()
		for fi in v.func_offsets.size():
			v.executar(fi)
		var vp := v.portas()
		total_vm += vp.size()
		var obtido := {}
		for p: Aot in vp:
			obtido[p.to_room_id()] = true
		salas_ok += 1
		for k: String in esperado:
			if obtido.has(k):
				casaram += 1
			else:
				so_py += 1
				if exemplos.size() < 5:
					exemplos.append("%s: Python achou %s, a VM não" % [id, k])
		for k2: String in obtido:
			if not esperado.has(k2):
				so_vm += 1
				if exemplos.size() < 5:
					exemplos.append("%s: a VM achou %s, Python não" % [id, k2])

	print("    [aot] %d salas · portas: VM=%d Python=%d · destinos casados=%d só-VM=%d só-Python=%d"
		% [salas_ok, total_vm, total_py, casaram, so_vm, so_py])
	t.eq(salas_ok, 169, "169 salas processadas")
	t.check(total_py >= 450, "o extrator Python tem ~453 portas", "%d" % total_py)
	t.check(total_vm >= 400, "a VM instala portas em número comparável", "%d" % total_vm)
	t.check(float(casaram) / float(maxi(1, casaram + so_py)) > 0.9,
		"mais de 90% dos destinos do Python são reproduzidos pela VM",
		"casaram=%d só-Python=%d  %s" % [casaram, so_py, ", ".join(exemplos.slice(0, 3))])

	# --- POR QUE a VM acha menos portas que a varredura? (hipótese medida) ---
	# A varredura Python é ESTÁTICA: acha toda porta escrita no bytecode, inclusive as que
	# vivem atrás de um `if`. A VM instala só as dos caminhos que EXECUTA — o que é o
	# comportamento do jogo (a sala aparece com ou sem aquela porta conforme o progresso).
	# Se a hipótese estiver certa, executar também com as flags LIGADAS revela portas novas,
	# e a UNIÃO dos dois estados se aproxima do total estático.
	var cheio := GameState.new()
	for b in GameState.N_BANKS:
		for bit in 256:
			cheio.flag_set(b, bit)

	var uniao := 0
	var so_zerado := 0
	var so_cheio := 0
	for id in salas:
		var z := ScriptVM.new()
		var c := ScriptVM.new()
		if not z.carregar_sala(id) or not c.carregar_sala(id):
			continue
		z.modo = ScriptVM.Modo.EXECUCAO
		c.modo = ScriptVM.Modo.EXECUCAO
		z.state = GameState.new()
		c.state = cheio
		for fi in z.func_offsets.size():
			z.executar(fi)
			c.executar(fi)
		var sz := {}
		for p: Aot in z.portas():
			sz[p.to_room_id()] = true
		var sc := {}
		for p2: Aot in c.portas():
			sc[p2.to_room_id()] = true
		var u := {}
		for k: String in sz:
			u[k] = true
			if not sc.has(k):
				so_zerado += 1
		for k2: String in sc:
			u[k2] = true
			if not sz.has(k2):
				so_cheio += 1
		uniao += u.size()

	print("    [aot] união dos 2 estados de flag: %d destinos (só-zerado=%d só-ligado=%d)"
		% [uniao, so_zerado, so_cheio])
	t.check(so_cheio > 0,
		"ligar as flags REVELA portas que estavam atrás de condicional (explica a diferença)",
		"%d destinos aparecem só com flags ligadas" % so_cheio)
	t.check(uniao > casaram,
		"a união dos estados cobre mais destinos que um estado só",
		"união=%d vs um estado=%d" % [uniao, casaram])

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("%s/STAGE%d" % [DATA_DIR, st])
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.begins_with("R") and nome.ends_with(".scd"):
				saida.append(nome.trim_suffix(".scd"))
	saida.sort()
	return saida
