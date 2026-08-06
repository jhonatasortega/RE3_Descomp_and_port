extends SceneTree
## Qual offset de ângulo do DADO deixa mais chegadas de porta ANDÁVEIS para frente?
## Critério de jogo (o que o usuário sente): ao chegar, apertar W tem de fazer ela entrar
## na sala. Mede as 453 chegadas com o resolver real, para 4 offsets.
func _initialize() -> void:
	var salas: Array[String] = []
	for s in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % s)
		if d == null:
			continue
		for f in d.get_files():
			if f.length() == 9 and f.begins_with("R") and f.ends_with(".json"):
				salas.append(f.substr(0, 4))
	salas.sort()
	var cache := {}
	var chegadas: Array = []
	for sala in salas:
		var r: RoomData = cache.get(sala)
		if r == null:
			r = RoomData.load_room(sala)
			cache[sala] = r
		for d in r.doors:
			if d.to_room_id == "" or d.to_pos == Vector3i.ZERO:
				continue
			var dest: RoomData = cache.get(d.to_room_id)
			if dest == null:
				dest = RoomData.load_room(d.to_room_id)
				cache[d.to_room_id] = dest
			if dest.colisao == null:
				continue
			chegadas.append([dest, d.to_pos, d.to_facing])
	for off in [0, -1024, 1024, 2048]:
		var anda := 0
		var soma := 0
		for c: Array in chegadas:
			var dest: RoomData = c[0]
			var p: Vector3i = c[1]
			var ang := PS1Math.wrap_angle(int(c[2]) + off)
			var nivel := p.y / -1800
			var total := 0
			var pos := Vector2i(p.x, p.z)
			for _t in 12:
				var dx := (PS1Math.rsin(ang) * 78) >> PS1Math.SHIFT
				var dz := (-PS1Math.rcos(ang) * 78) >> PS1Math.SHIFT
				var res := dest.colisao.resolver(pos.x, pos.y, pos.x + dx, pos.y + dz, nivel)
				if res.rejeitado:
					break
				var d2 := absi(res.x - pos.x) + absi(res.z - pos.y)
				pos = Vector2i(res.x, res.z)
				if d2 < 20:
					break
				total += d2
			soma += total
			if total >= 300:
				anda += 1
		print("[fac] offset %+5d: %d/%d chegadas andam >=300un para frente · avanço médio %d un" % [
			off, anda, chegadas.size(), soma / maxi(1, chegadas.size())])
	quit(0)
