extends SceneTree
## A chegada da R100->R101 responde ao input? (o teste falhou; medir POR QUE)
func _initialize() -> void:
	var w := World.new()
	w.carregar("R101")
	var p := Vector3i(-18808, -7200, -11475)
	w.player.pos = p
	var nivel := p.y / -1800
	var col := w.room.colisao
	var r0 := col.resolver(p.x, p.z, p.x, p.z, nivel)
	print("[chg] parado: empurrado=%s rejeitado=%s -> (%d,%d) quem=%s" % [
		r0.empurrado, r0.rejeitado, r0.x, r0.z,
		("forma%d raw=[%d,%d,%d,%d]" % [r0.quem.forma, r0.quem.f0, r0.quem.f1, r0.quem.f2, r0.quem.f3]) if r0.quem else "-"])
	for d8 in 8:
		var ang := d8 * 512
		var dx := (PS1Math.rsin(ang) * 78) >> PS1Math.SHIFT
		var dz := (-PS1Math.rcos(ang) * 78) >> PS1Math.SHIFT
		var r := col.resolver(p.x, p.z, p.x + dx, p.z + dz, nivel)
		print("[chg] ang %4d passo(%4d,%4d): rej=%s -> (%d,%d) delta=(%d,%d) quem=%s" % [
			ang, dx, dz, r.rejeitado, r.x, r.z, r.x - p.x, r.z - p.z,
			("forma%d" % r.quem.forma) if r.quem else "-"])
	print("[chg] piso aqui: %d (nível %d)" % [col.floor_height(p.x, p.z, p.y), nivel])
	quit(0)
