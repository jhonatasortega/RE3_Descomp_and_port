extends SceneTree
## Disseca o congelamento em R100 perto do círculo (rect 9, raio 3019): coloca o player
## um pouco antes do ponto onde o run real congelou e anda com W, logando cada tick.

func _initialize() -> void:
	var mundo := World.new()
	if not mundo.carregar("R100"):
		push_error("R100 não carregou")
		quit(1)
		return
	var pl := mundo.player
	var pad := Pad.new()
	pl.pos = Vector3i(-23171, 0, -26551)      # pos do run real em t=80 (antes do freeze)
	pl.facing = 0
	print("[frz] inicio %s" % [pl.pos])
	for i in 40:
		pad.set_mask(0x01)
		var antes := pl.pos
		mundo.tick(pad)
		var col := mundo.room.colisao
		var alvo := Vector3i(antes.x, antes.y, antes.z - 78)
		var r := col.resolver(antes.x, antes.z, alvo.x, alvo.z, 0)
		print("[frz] t=%02d %s -> %s  dbg=%s  (resolver manual: -> (%d,%d) emp=%s rej=%s)" % [
			i, antes, pl.pos, pl.colisor_dbg, r.x, r.z, r.empurrado, r.rejeitado])
		if i > 6 and pl.pos == antes and i % 5 != 0:
			continue
	quit(0)
