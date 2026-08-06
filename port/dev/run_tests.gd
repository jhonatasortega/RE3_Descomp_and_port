extends SceneTree
## Test runner headless do port (P0-09).
##
## Roda todos os `res://dev/tests/test_*.gd` e devolve **exit code != 0** se algo falhar —
## é o que permite a suíte de regressão do P7-04 rodar em um comando.
##
##     godot --headless --path port --script res://dev/run_tests.gd
##     godot --headless --path port --script res://dev/run_tests.gd -- ps1_math   # filtra
##
## Cada teste é um script que estende RefCounted e implementa `func run(t: Tester) -> void`.
## `--headless` serve aqui (não há render); para screenshot use `--rendering-driver opengl3`.

const TESTS_DIR := "res://dev/tests"


class Tester:
	extends RefCounted
	var ok_count := 0
	var fail_count := 0
	var _group := ""

	func group(name: String) -> void:
		_group = name

	func check(cond: bool, name: String, detalhe: String = "") -> bool:
		if cond:
			ok_count += 1
		else:
			fail_count += 1
			print("    [FALHA] %s%s%s" % [
				("%s / " % _group) if _group != "" else "", name,
				("  ->  %s" % detalhe) if detalhe != "" else ""])
		return cond

	func eq(a: Variant, b: Variant, name: String, detalhe: String = "") -> bool:
		var d := "obtido=%s esperado=%s" % [a, b]
		if detalhe != "":
			d += "  (%s)" % detalhe
		return check(a == b, name, d)

	func near(a: float, b: float, tol: float, name: String) -> bool:
		return check(absf(a - b) <= tol, name, "obtido=%f esperado=%f tol=%f" % [a, b, tol])


func _initialize() -> void:
	var filtro := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filtro = args[0]

	var arquivos: Array[String] = []
	var d := DirAccess.open(TESTS_DIR)
	if d == null:
		print("sem pasta de testes: %s" % TESTS_DIR)
		quit(1)
		return
	for f in d.get_files():
		var nome := f.trim_suffix(".remap")          # exportado vira .gd.remap
		if nome.begins_with("test_") and nome.ends_with(".gd"):
			if filtro == "" or nome.contains(filtro):
				arquivos.append("%s/%s" % [TESTS_DIR, nome])
	arquivos.sort()

	var t := Tester.new()
	var t0 := Time.get_ticks_msec()
	for caminho in arquivos:
		var script: Variant = load(caminho)
		if script == null:
			print("  [FALHA] não carregou %s" % caminho)
			t.fail_count += 1
			continue
		var inst: Variant = script.new()
		print("== %s" % caminho.get_file())
		# `run()` DEVE devolver true na última linha. Um erro de script (argumento errado,
		# tipo inválido) aborta a função no meio e o Godot só imprime SCRIPT ERROR no log —
		# sem esta sentinela a suíte fecha VERDE tendo executado metade dos asserts.
		# Foi exatamente o que aconteceu em test_room_data.gd (t.eq com 4 argumentos).
		var completou: Variant = inst.run(t)
		if completou != true:
			t.fail_count += 1
			print("    [FALHA] %s ABORTOU no meio (run() não chegou ao fim) — procure "
				% caminho.get_file() + "'SCRIPT ERROR' no log acima")
	var ms := Time.get_ticks_msec() - t0

	print("\n%d testes ok, %d falhas, %d arquivos, %d ms" % [
		t.ok_count, t.fail_count, arquivos.size(), ms])
	print("RESULTADO: %s" % ("VERDE" if t.fail_count == 0 else "VERMELHO"))
	quit(1 if t.fail_count > 0 else 0)
