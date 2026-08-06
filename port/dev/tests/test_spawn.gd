extends RefCounted
## Personagens colocados pelo script (sce_em_set 0x7d) — item P2-06.
##
## Cruza com o extrator Python: `data/sce_enemies.json` diz **1136 spawns de inimigo + 80 NPCs
## em 137 salas**. Se a VM, executando o script, chegar à mesma ordem de grandeza e às mesmas
## classes, os dois lados concordam — e o port passa a povoar as salas pelo SCRIPT, não por
## lista externa.

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("Spawn")

	# --- layout do opcode ---
	t.eq(ScriptVM.size_of(0x7D), 24, "sce_em_set tem 24 bytes")

	# --- uma sala com inimigos conhecidos ---
	var salas := _listar_salas()
	var total := 0
	var salas_com := 0
	var classes := {}
	var com_modelo := 0
	var sem_anotacao := 0
	var conf_alta := 0
	var pos_zero := 0
	for id in salas:
		var v := ScriptVM.new()
		if not v.carregar_sala(id):
			continue
		v.modo = ScriptVM.Modo.EXECUCAO
		v.state = GameState.new()
		for fi in v.func_offsets.size():
			v.executar(fi)
		if not v.spawns.is_empty():
			salas_com += 1
		for sp: Spawn in v.spawns:
			total += 1
			classes[sp.classe] = true
			if sp.modelo_rel() != "":
				com_modelo += 1
				if not AssetIO.exists(sp.modelo_rel()):
					sem_anotacao += 1     # anotado mas sem arquivo -> problema de pipeline
			if sp.conf == "ALTA":
				conf_alta += 1
			if sp.pos == Vector3i.ZERO:
				pos_zero += 1

	print("    [spawn] %d personagens em %d salas · %d classes distintas · %d com modelo · %d conf ALTA · %d em pos zero"
		% [total, salas_com, classes.size(), com_modelo, conf_alta, pos_zero])
	t.check(total > 500, "o script coloca centenas de personagens", "%d" % total)
	t.check(salas_com > 80, "espalhados por muitas salas", "%d salas" % salas_com)
	t.check(classes.size() > 15, "várias classes distintas", "%d" % classes.size())
	t.eq(sem_anotacao, 0, "todo spawn com espécie anotada tem o .glb no lugar")
	t.check(com_modelo > total / 2, "a maioria dos spawns resolve um modelo",
		"%d de %d" % [com_modelo, total])

	# --- a espécie vem com confiança declarada, nunca inventada ---
	var sp2 := Spawn.new()
	sp2.classe = 0x10
	sp2.resolver_especie()
	t.eq(sp2.especie, "Zumbi (macho)", "classe 0x10 = zumbi macho (conf ALTA no dado)")
	t.eq(sp2.conf, "ALTA", "confiança vem do dado")
	t.eq(sp2.modelo_rel(), "ENEMY/em10.glb", "resolve o modelo EM10")
	var sp3 := Spawn.new()
	sp3.classe = 0xFE                       # classe inexistente
	sp3.resolver_especie()
	t.eq(sp3.conf, "NENHUMA", "classe sem anotação declara confiança NENHUMA")
	t.eq(sp3.modelo_rel(), "", "e não inventa modelo")

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
