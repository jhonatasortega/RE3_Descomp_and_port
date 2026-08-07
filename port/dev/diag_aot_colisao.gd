extends SceneTree
## Ligar o `0x67` (316 itens novos) pode ROUBAR o slot de uma porta: a tabela de AOT do motor
## tem 32 entradas indexadas por `aot_id`, e quem registra depois sobrescreve. Isto mede quantas
## portas deixaram de existir por isso — se for > 0, o port precisa da ordem exata do motor.
func _initialize() -> void:
	var salas: Array[String] = []
	for st in range(1, 8):
		var dir := DirAccess.open("res://data/STAGE%d" % st)
		if dir == null:
			continue
		for f: String in dir.get_files():
			if f.ends_with(".scd"):
				salas.append(f.get_basename())
	salas.sort()
	var n_salas := 0
	var portas := 0
	var itens := 0
	var conflitos := 0
	for sala: String in salas:
		var w := World.new()
		if not w.carregar(sala):
			continue
		n_salas += 1
		portas += w.vm.portas().size()
		itens += w.vm.itens().size()
		# reexecuta contando TODAS as instalações (não só a que sobrou), para ver sobreposição
		var ids_item := {}
		for a: Aot in w.vm.itens():
			ids_item[a.id] = true
		for a: Aot in w.vm.portas():
			if ids_item.has(a.id):
				conflitos += 1
				print("[aot] CONFLITO %s: aot %d é porta E item" % [sala, a.id])
	print("[aot] %d salas · %d portas · %d itens · %d conflitos de id" % [
		n_salas, portas, itens, conflitos])
	quit(0)
