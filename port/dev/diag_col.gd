extends SceneTree
## Diagnóstico da colisão de TRAJETO (P3-10): quanto da sala se ALCANÇA a pé?
##
## A métrica antiga ("pontos livres") não vale para este motor: a colisão do RE3 é por
## SEGMENTO, e estar dentro da caixa de um collider não bloqueia nada. A pergunta certa é a
## de jogo: **a partir da chegada da porta, quanto do mapa dá para andar?** — inundação com
## o passo real (78 un/tick andando) e o `y` do nível.


## Chegadas REAIS (a porta que ENTRA na sala está na sala VIZINHA, não nesta — `to_pos` do
## descriptor é a posição no DESTINO). Extraídas do `_scd.json` das 169 salas.
const CHEGADAS := [
	["R100", -20400, 0, -20790],       ## vinda da R101
	["R101", -18808, -7200, -11475],   ## vinda da R100
	["R104", 22767, 0, -16964],        ## vinda da R103
	["R10F", -14377, 0, -19894],       ## vinda da R106
	["R11D", -5450, -3600, -26750],    ## vinda da R101 (a do print do usuário)
	["R200", -1625, 0, 12210],         ## vinda da R201
	["R217", 13587, 0, -23840],        ## vinda da R208
]


func _initialize() -> void:
	for caso: Array in CHEGADAS:
		var sala: String = caso[0]
		var origem := Vector2i(int(caso[1]), int(caso[3]))
		var y: int = int(caso[2])
		var room := RoomData.load_room(sala)
		if room.colisao == null:
			print("[col] %s SEM bloco de colisão" % sala)
			continue
		var ativos := 0
		for r in room.colisao.rects:
			if (r.bits & Collision.MASCARA_PLAYER) != 0 and r.forma != 0x0B \
					and r.topo <= y and r.base_y >= y:
				ativos += 1
		var celulas := _inundar(room, origem, y)
		print("[col] %s chegada=(%d,%d,%d) %3d de %3d colliders ativos · alcança %d células" % [
			sala, origem.x, y, origem.y, ativos, room.colisao.rects.size(), celulas])

	# andar 40 ticks a partir da chegada da R100 e ver onde para
	var w := World.new()
	w.carregar("R100")
	var chegada := Vector3i(-20400, 0, -20790)     ## chegada da R101 -> R100
	w.player.facing = 0
	var pad := Pad.new()
	for volta in 4:
		w.player.pos = chegada
		w.player.facing = volta * 1024
		var i0 := w.player.pos
		for _i in 40:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		var dd := Vector2(float(w.player.pos.x - i0.x), float(w.player.pos.z - i0.z)).length()
		print("[col] R100 andando 40 ticks com facing=%4d: %s -> %s (%.0f un de %d possíveis)" % [
			volta * 1024, i0, w.player.pos, dd, 40 * 78])
	_varrer_chegadas()
	quit(0)


func _varrer_chegadas() -> void:
	## Varrido COMPLETO: as 453 chegadas de porta do jogo conseguem dar o primeiro passo?
	## (invariante do modelo de colisão; a suíte só cobre os stages 1-2 por tempo)
	var cache := {}
	var total := 0
	var presos: Array[String] = []
	for s in range(1, 8):
		var dir := DirAccess.open("res://data/STAGE%d" % s)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.length() != 9 or not f.ends_with(".json") or not f.begins_with("R"):
				continue
			var sala := f.substr(0, 4)
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
				total += 1
				var deu := false
				for ang in [0, 1024, 2048, 3072]:
					var off := PS1Math.rotate_xz(0, 78, ang)
					if dest.trajeto_livre(d.to_pos.x, d.to_pos.z,
							d.to_pos.x + off.x, d.to_pos.z + off.y, d.to_pos.y):
						deu = true
						break
				if not deu:
					presos.append("%s->%s %s" % [sala, d.to_room_id, d.to_pos])
	print("[col] chegadas com primeiro passo livre: %d/%d (%.0f%%)%s" % [
		total - presos.size(), total,
		100.0 * float(total - presos.size()) / float(maxi(1, total)),
		"" if presos.is_empty() else "  PRESAS: " + ", ".join(presos.slice(0, 8))])


func _inundar(room: RoomData, origem: Vector2i, y: int, passo: int = 200,
		limite: int = 40000) -> int:
	var vistos := {Vector2i.ZERO: true}
	var fila: Array[Vector2i] = [Vector2i.ZERO]
	var n := 0
	while not fila.is_empty() and n < limite:
		var g: Vector2i = fila.pop_back()
		n += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ng := g + d
			if vistos.has(ng):
				continue
			var a := origem + g * passo
			var b := origem + ng * passo
			if absi(b.x) > 32000 or absi(b.y) > 32000:
				continue
			if room.trajeto_livre(a.x, a.y, b.x, b.y, y):
				vistos[ng] = true
				fila.append(ng)
	return vistos.size()
