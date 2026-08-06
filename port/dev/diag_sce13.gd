extends SceneTree
## Simula as 6 portas de CONTATO (sce==13): entra na caixa, confere a travessia única
## (sem ping-pong) e a chegada legal no destino.

const CASOS: Array = [
	["R114", Vector3i(-20408, 0, -7710)],   # centro da box -> R118
	["R118", Vector3i(4253, 0, 1002)],      # -> R114
	["R304", Vector3i(0, 0, 0)],            # box ZERADA -> R30A (só o ponto exato)
	["R30A", Vector3i(1981, 0, -93)],       # -> R304
	["R40C", Vector3i(5743, 0, -2436)],     # -> R40E
	["R40E", Vector3i(-26750, 0, -22248)],  # -> R40C
]


func _initialize() -> void:
	for caso: Array in CASOS:
		var mundo := World.new()
		if not mundo.carregar(caso[0]):
			print("[s13] %s NAO CARREGOU" % caso[0])
			continue
		mundo.player.pos = caso[1]
		var pad := Pad.new()
		var trocas: Array[String] = []
		mundo.sala_trocada.connect(func(de: String, para: String, _p: Aot) -> void:
			trocas.append("%s->%s" % [de, para]))
		for i in 31:
			pad.set_mask(0)
			mundo.tick(pad)
		var pos := mundo.player.pos
		var nivel := mundo.player.nivel()
		print("[s13] %s em %s: trocas=%s  pos_final=%s nivel=%d sala=%s" % [
			caso[0], caso[1], trocas, pos, nivel, mundo.room.room_id])
	quit(0)
