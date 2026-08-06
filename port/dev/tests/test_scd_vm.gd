extends RefCounted
## GATE DA FASE 2 (item P2-10): percorrer as **4238 funções** de script das 169 salas.
##
## Critério do plano: 0 opcode desconhecido e 100% das funções fechando em `evt_end`. É o
## equivalente, no port, ao fechamento que a decomp provou em Python — se a VM do GDScript
## percorre o mesmo bytecode com o mesmo resultado, ela está lendo o script como o jogo lê.
##
## Números de referência (docs/decomp/notes/scd_opcodes.md): 4238/4238 funções fecham em
## `evt_end`; espaço de opcodes `0x00..0x8f`; nenhum opcode >= 0x90 existe.

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("ScriptVM")

	# --- tabela de opcodes: veio do dado, não de números escritos à mão ---
	t.check(FileAccess.file_exists(ScriptVM.OPCODES_PATH),
		"data/scd_opcodes.json presente (tools/scd_export.py)")
	t.eq(ScriptVM.size_of(0x01), 1, "evt_end tem 1 byte")
	t.eq(ScriptVM.size_of(0x06), 4, "if_begin tem 4 bytes")
	t.eq(ScriptVM.size_of(0x14), 4, "switch tem 4 bytes (a divergência 6B/2B foi resolvida)")
	t.eq(ScriptVM.size_of(0x61), 32, "aot_set (0x61) tem 32 bytes")
	t.eq(ScriptVM.size_of(0x62), 40, "0x62 tem 40 bytes")
	t.eq(ScriptVM.size_of(0x7d), 24, "sce_em_set (0x7d) tem 24 bytes")
	t.eq(ScriptVM.name_of(0x01), "evt_end/return", "nome do opcode vem do dado")
	t.check(ScriptVM.opcode_valido(0x8f), "0x8f é o último opcode válido")
	t.check(not ScriptVM.opcode_valido(0x90), "0x90 NÃO existe (provado no EXE)")
	t.check(not ScriptVM.opcode_valido(0xC0), "0xc0 é tabela de flags, não opcode")

	# --- uma sala conhecida ---
	var vm := ScriptVM.new()
	t.check(vm.carregar_sala("R100"), "bytecode da R100 carrega", vm.erro)
	t.eq(vm.func_offsets.size(), 9, "R100 tem 9 funções de script")
	t.eq(vm.func_offsets[0], 18, "a tabela de funções termina em 18 (9 × u16)")
	t.eq(vm.executar(0), ScriptVM.Status.FIM, "função 0 da R100 fecha em evt_end")

	# --- TESTE FORTE: as 4238 funções das 169 salas ---
	var salas := _listar_salas()
	t.eq(salas.size(), 169, "169 salas")

	var n_func := 0
	var fecharam := 0
	var falhas: Array[String] = []
	var opcodes_vistos := {}
	var passos_total := 0
	for id in salas:
		var v := ScriptVM.new()
		if not v.carregar_sala(id):
			falhas.append("%s: %s" % [id, v.erro])
			continue
		v.trace_on = true
		for fi in v.func_offsets.size():
			n_func += 1
			var st := v.executar(fi)
			passos_total += v.passos
			for op in v.trace:
				opcodes_vistos[op] = true
			if st == ScriptVM.Status.FIM:
				fecharam += 1
			elif falhas.size() < 6:
				falhas.append("%s f%d: %s" % [id, fi, v.erro])

	t.eq(n_func, 4238, "4238 funções de script (o número que a decomp provou)")
	t.eq(fecharam, 4238, "TODAS as 4238 fecham em evt_end",
		"" if falhas.is_empty() else ", ".join(falhas.slice(0, 4)))
	t.eq(falhas.size(), 0, "nenhuma falha de percurso")
	t.check(passos_total > 100000, "o percurso executou o bytecode de verdade",
		"%d passos" % passos_total)

	# --- DIFF CONTRA O PYTHON: a outra metade do critério do P2-10 ---
	# `data/scd_hist.json` traz a contagem de opcodes por sala segundo o decodificador
	# Python (tools/scd_decode.py). Duas implementações independentes lendo o mesmo bytecode
	# têm de produzir a MESMA contagem — se divergirem, uma das duas lê o script errado.
	var hj: Variant = AssetIO.json("scd_hist.json")
	t.check(hj is Dictionary, "data/scd_hist.json presente (lado Python do diff)")
	if hj is Dictionary:
		var por_sala: Dictionary = (hj as Dictionary)["por_sala"]
		var salas_conferidas := 0
		var divergentes: Array[String] = []
		var instr_total := 0
		for id in salas:
			if not por_sala.has(id):
				continue
			var esperado: Dictionary = por_sala[id]
			var v := ScriptVM.new()
			if not v.carregar_sala(id):
				continue
			v.trace_on = true
			var obtido := {}
			for fi in v.func_offsets.size():
				v.executar(fi)
				for op in v.trace:
					obtido[str(op)] = int(obtido.get(str(op), 0)) + 1
			salas_conferidas += 1
			for k: String in esperado:
				instr_total += int(esperado[k])
				if int(obtido.get(k, 0)) != int(esperado[k]):
					if divergentes.size() < 5:
						divergentes.append("%s op%s: port=%d python=%d" % [
							id, k, int(obtido.get(k, 0)), int(esperado[k])])
			for k2: String in obtido:
				if not esperado.has(k2) and divergentes.size() < 5:
					divergentes.append("%s op%s só no port (%d)" % [id, k2, int(obtido[k2])])
		t.eq(salas_conferidas, 169, "169 salas conferidas contra o Python")
		t.eq(divergentes.size(), 0,
			"contagem de opcodes IDÊNTICA à do decodificador Python nas 169 salas",
			"" if divergentes.is_empty() else ", ".join(divergentes))
		t.eq(instr_total, 125384, "125384 instruções de script no jogo todo")

	# --- cobertura: quais opcodes o jogo realmente usa ---
	t.check(opcodes_vistos.size() > 60, "o jogo usa dezenas de opcodes distintos",
		"%d opcodes distintos vistos" % opcodes_vistos.size())
	var invalidos := 0
	for op: int in opcodes_vistos:
		if not ScriptVM.opcode_valido(op):
			invalidos += 1
	t.eq(invalidos, 0, "nenhum opcode visitado está fora do espaço 0x00..0x8f")

	# --- MODO EXECUÇÃO: o desvio de fluxo acontece de verdade? (P2-02 / P2-03) ---
	# A prova não é "rodou sem travar": é que o MESMO script com estados de flag DIFERENTES
	# toma caminhos diferentes. Se o CHECK (0x4c) não estivesse gateando o IF, os dois
	# percursos seriam idênticos e a VM só pareceria funcionar.
	var zerado := GameState.new()
	var cheio := GameState.new()
	for b in GameState.N_BANKS:
		for bit in 256:
			cheio.flag_set(b, bit)

	var difs := 0
	var ok_zerado := 0
	var ok_cheio := 0
	var total := 0
	var leituras := 0
	var escritas := 0
	var erros_exec: Array[String] = []
	for id in salas:
		var a := ScriptVM.new()
		var b2 := ScriptVM.new()
		if not a.carregar_sala(id) or not b2.carregar_sala(id):
			continue
		a.modo = ScriptVM.Modo.EXECUCAO
		b2.modo = ScriptVM.Modo.EXECUCAO
		a.state = zerado
		b2.state = cheio
		for fi in a.func_offsets.size():
			total += 1
			var sa := a.executar(fi)
			var sb := b2.executar(fi)
			leituras += a.flags_lidos
			escritas += a.flags_escritos
			if sa == ScriptVM.Status.FIM:
				ok_zerado += 1
			elif erros_exec.size() < 4:
				erros_exec.append("%s f%d (zerado): %s" % [id, fi, a.erro])
			if sb == ScriptVM.Status.FIM:
				ok_cheio += 1
			elif erros_exec.size() < 4:
				erros_exec.append("%s f%d (cheio): %s" % [id, fi, b2.erro])
			if a.passos != b2.passos:
				difs += 1

	print("    [exec] %d funções · %d leituras de flag · %d escritas · %d tomaram caminho diferente"
		% [total, leituras, escritas, difs])
	t.eq(total, 4238, "as 4238 funções também rodam em modo EXECUÇÃO")
	t.eq(erros_exec.size(), 0, "nenhum erro de PC/opcode/laço em modo execução",
		"" if erros_exec.is_empty() else ", ".join(erros_exec))
	t.eq(ok_zerado, 4238, "todas terminam com as flags ZERADAS")
	t.eq(ok_cheio, 4238, "todas terminam com as flags TODAS LIGADAS")
	t.check(leituras > 500, "o script consulta flags (CHECK 0x4c)", "%d leituras" % leituras)
	t.check(escritas > 100, "o script escreve flags (SET 0x4d)", "%d escritas" % escritas)
	t.check(difs > 100,
		"o estado das flags MUDA o caminho executado (prova de que o desvio funciona)",
		"%d funções de %d tomaram caminhos diferentes" % [difs, total])

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
