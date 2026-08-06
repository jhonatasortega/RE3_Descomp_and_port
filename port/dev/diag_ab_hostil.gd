extends SceneTree
## VERIFICAÇÃO HOSTIL do diag_ab: mesma técnica (A vs "modo ontem" em lockstep, monkeypatch
## em runtime, nada do port editado), mas rota bem mais agressiva para tentar QUEBRAR a
## equivalência: CORRER (RUN) o tempo todo, giro de +160 a cada 5 ticks, flip de 180° a cada
## 97 ticks, fases de RÉ (BACK), 800 ticks, e duas salas a mais: R114 (porta sce==13) e
## R10C (armários = círculos/formas problemáticas), com spawn via _desencravar do centro.

const TICKS := 800
const ROOMS: Array = [
	["R100", -20400, 0, -20790, false],
	["R101", -18808, -7200, -11475, false],
	["R11D", -5450, -3600, -26750, false],
	["R200", -1625, 0, 12210, false],
	["R114", -19500, 0, -17000, true],   # true = desencravar o spawn
	["R10C", 0, 0, 0, true],
]


class ColAB:
	extends Collision
	var circ_antigo := false
	var sem_arestas := false

	static func de(c: Collision, circ: bool, arestas: bool) -> ColAB:
		var n := ColAB.new()
		n.rects = c.rects
		n.centro1 = c.centro1
		n.centro2 = c.centro2
		n.piso_padrao = c.piso_padrao
		n.circ_antigo = circ
		n.sem_arestas = arestas
		return n

	func _responder_arestas(r: Collision.Rect, res: Collision.Resolvido, prev_x: int,
			prev_z: int, rx: int, rz: int, girado: bool) -> bool:
		if sem_arestas:
			return false
		return super._responder_arestas(r, res, prev_x, prev_z, rx, rz, girado)

	func _responder_circulo(r: Collision.Rect, res: Collision.Resolvido, prev_x: int,
			prev_z: int, rx: int) -> bool:
		if not circ_antigo:
			return super._responder_circulo(r, res, prev_x, prev_z, rx)
		var raio_c := r.raio()
		if raio_c <= 0:
			return false
		var cx := r.f0 + raio_c
		var cz := r.f1 + raio_c
		var dx := res.x - cx
		var dz := res.z - cz
		var dist := int(sqrt(float(dx * dx + dz * dz)))
		var pen := (raio_c + rx) - dist
		if pen <= 0:
			return false
		if dist == 0:
			res.rejeitado = true
			return true
		var alvo_x := cx + dx * (raio_c + rx + 1) / dist
		var alvo_z := cz + dz * (raio_c + rx + 1) / dist
		var corr_x := alvo_x - res.x
		var corr_z := alvo_z - res.z
		if absi(corr_x) > 2 * rx or absi(corr_z) > 2 * rx:
			res.rejeitado = true
			return true
		_aplicar(res, corr_x, corr_z, false)
		return true


class Variante:
	extends RefCounted
	var nome := ""
	var circ := false
	var arestas := false
	var estoque := false
	var w: World
	var trocas_log: Array = []
	var tick_atual: Array = [0]

	func preparar(sala: String, px: int, py: int, pz: int, desenc: bool) -> bool:
		w = World.new()
		if not w.carregar(sala):
			return false
		var p := Vector3i(px, py, pz)
		if desenc:
			p = w._desencravar(p)
		w.player.pos = p
		w.player.facing = 0
		_injetar()
		w.sala_trocada.connect(func(de: String, para: String, _p) -> void:
			trocas_log.append([tick_atual[0], de, para])
			_injetar())
		return true

	func _injetar() -> void:
		var col: Collision = w.room.colisao
		if col == null:
			return
		if estoque:
			return                            # A usa o resolver estoque intocado
		var c := ColAB.de(col, circ, arestas)
		w.player.resolver = func(px: int, pz: int, nx: int, nz: int, nivel: int) -> Collision.Resolvido:
			return c.resolver(px, pz, nx, nz, nivel)


func _initialize() -> void:
	var specs: Array = [
		["A", true, false, false],
		["B_circ", false, true, false],
		["B_semarestas", false, false, true],
		["B_ontem", false, true, true],
	]
	for caso: Array in ROOMS:
		var sala: String = caso[0]
		print("\n===== %s (hostil) =====" % sala)
		var vs: Array = []
		var falhou := false
		for s: Array in specs:
			var v := Variante.new()
			v.nome = s[0]
			v.estoque = s[1]
			v.circ = s[2]
			v.arestas = s[3]
			if not v.preparar(sala, int(caso[1]), int(caso[2]), int(caso[3]), bool(caso[4])):
				print("[hostil] %s NÃO CARREGOU" % sala)
				falhou = true
				break
			vs.append(v)
		if falhou:
			continue

		var pad := Pad.new()
		var stats: Dictionary = {}
		var hist: Dictionary = {}
		for v: Variante in vs:
			stats[v.nome] = {"parado": 0, "pior": 0, "seq": 0, "celulas": {}}
			hist[v.nome] = []
		for i in TICKS:
			# rota hostil, determinística e IGUAL para todas as variantes
			var mask := Pad.FWD | Pad.RUN
			if i % 50 < 10:
				mask = Pad.BACK                  # fases de ré
			pad.set_mask(mask)
			for v: Variante in vs:
				v.tick_atual[0] = i
				if i % 5 == 4:
					v.w.player.facing = PS1Math.wrap_angle(v.w.player.facing + 160)
				if i % 97 == 96:
					v.w.player.facing = PS1Math.wrap_angle(v.w.player.facing + 2048)
				var antes: Vector3i = v.w.player.pos
				var sala_antes: String = v.w.room.room_id
				v.w.tick(pad)
				var pos: Vector3i = v.w.player.pos
				var moveu := pos != antes or v.w.room.room_id != sala_antes
				hist[v.nome].append([pos, moveu, v.w.room.room_id])
				var st: Dictionary = stats[v.nome]
				st["celulas"][Vector2i(pos.x / 400, pos.z / 400)] = true
				if not moveu:
					st["parado"] += 1
					st["seq"] += 1
					st["pior"] = maxi(int(st["pior"]), int(st["seq"]))
				else:
					st["seq"] = 0

		for v: Variante in vs:
			var st: Dictionary = stats[v.nome]
			var fim: Array = hist[v.nome][TICKS - 1]
			print("[%s] %-13s células=%d parado=%d/%d pior_seq=%d fim=%s sala_fim=%s trocas=%s" % [
				sala, v.nome, st["celulas"].size(), st["parado"], TICKS, st["pior"],
				fim[0], fim[2], str(v.trocas_log) if not v.trocas_log.is_empty() else "0"])

		var ha: Array = hist["A"]
		for v: Variante in vs:
			if v.nome == "A":
				continue
			var hb: Array = hist[v.nome]
			var difs := 0
			var primeira := -1
			var a_trava := 0
			var b_trava := 0
			var max_d := 0
			for i in TICKS:
				var pa: Vector3i = ha[i][0]
				var pb: Vector3i = hb[i][0]
				if pa != pb:
					difs += 1
					if primeira < 0:
						primeira = i
					if ha[i][2] == hb[i][2]:
						max_d = maxi(max_d, maxi(absi(pa.x - pb.x), absi(pa.z - pb.z)))
				var a_parado: bool = not ha[i][1]
				var b_parado: bool = not hb[i][1]
				if a_parado and not b_parado:
					a_trava += 1
					if a_trava <= 4:
						print("    tick %d: A TRAVA pos=%s · %s anda pos=%s" % [i, pa, v.nome, pb])
				elif b_parado and not a_parado:
					b_trava += 1
			if difs == 0:
				print("  A == %s em TODOS os %d ticks" % [v.nome, TICKS])
			else:
				print("  A != %s em %d/%d ticks (1ª no tick %d, dif máx na mesma sala = %d un) · A trava/%s anda = %d · %s trava/A anda = %d" % [
					v.nome, difs, TICKS, primeira, max_d, v.nome, a_trava, v.nome, b_trava])
	quit(0)
