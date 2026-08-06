extends SceneTree
## A/B do andar: código de HOJE vs "modo ONTEM", mesmo percurso de 500 ticks (rota do
## diag_tour: W segurado, +45° a cada 25 ticks), em lockstep — um World por variante.
##
## NÃO edita nenhum arquivo do port: o "ontem" é uma SUBCLASSE de Collision criada aqui
## (override de _responder_circulo / _responder_arestas) injetada em player.resolver,
## e re-injetada a cada sala_trocada (world.carregar reatribui o resolver).
##
## Variantes:
##   A            = código atual (resolver estoque, só embrulhado para capturar o Resolvido)
##   B_circ       = círculo com a resposta ANTIGA (clamp na superfície + rejeição 0x100),
##                  reconstruída da descrição em collision.gd:562-564 ("clamp + rejeição")
##   B_semarestas = formas 2/3/4/6 SEM resposta (antes da v2 de _responder_arestas)
##   B_ontem      = as duas juntas
##
## O que se compara, tick a tick: posição, moveu/não-moveu, quem respondeu (Resolvido.quem),
## rejeitado, sala. Divergências saem com o registro do collider culpado (forma/raw/mask/bits)
## para conferência contra port/data/STAGE*/R*_col.json.

const TICKS := 500
const ROOMS: Array = [
	["R100", -20400, 0, -20790],
	["R101", -18808, -7200, -11475],
	["R11D", -5450, -3600, -26750],
	["R200", -1625, 0, 12210],
]


class ColAB:
	extends Collision
	## Collision com os comportamentos de ONTEM ligáveis por flag.
	var circ_antigo := false
	var sem_arestas := false

	static func de(c: Collision, circ: bool, arestas: bool) -> ColAB:
		var n := ColAB.new()
		n.rects = c.rects                    # mesmos Rects (o resolver só lê)
		n.centro1 = c.centro1
		n.centro2 = c.centro2
		n.piso_padrao = c.piso_padrao
		n.circ_antigo = circ
		n.sem_arestas = arestas
		return n

	func _responder_arestas(r: Collision.Rect, res: Collision.Resolvido, prev_x: int,
			prev_z: int, rx: int, rz: int, girado: bool) -> bool:
		if sem_arestas:
			return false                     # ontem-antes-da-v2: 2/3/4/6 não empurravam
		return super._responder_arestas(r, res, prev_x, prev_z, rx, rz, girado)

	func _responder_circulo(r: Collision.Rect, res: Collision.Resolvido, prev_x: int,
			prev_z: int, rx: int) -> bool:
		if not circ_antigo:
			return super._responder_circulo(r, res, prev_x, prev_z, rx)
		# ONTEM (reconstruído de collision.gd:562-564): clamp do destino na superfície
		# inflada + rejeição quando a correção excede 2*rx — "esbarrão seco".
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
	var estoque := false                     # true = A (usa room.colisao como está)
	var w: World
	var ult: Array = [null]                  # último Resolvido capturado
	var trocas_log: Array = []               # [tick, de, para]
	var tick_atual: Array = [0]

	func preparar(sala: String, px: int, py: int, pz: int) -> bool:
		w = World.new()
		if not w.carregar(sala):
			return false
		w.player.pos = Vector3i(px, py, pz)
		w.player.facing = 0
		_injetar()
		w.sala_trocada.connect(func(de: String, para: String, _p: Aot) -> void:
			trocas_log.append([tick_atual[0], de, para])
			_injetar())
		return true

	func _injetar() -> void:
		## Embrulha o resolver (de hoje ou de ontem) para capturar o Resolvido de cada tick.
		var col: Collision = w.room.colisao
		if col == null:
			return
		var c: Collision = col if estoque else ColAB.de(col, circ, arestas)
		var cap := ult
		w.player.resolver = func(px: int, pz: int, nx: int, nz: int, nivel: int) -> Collision.Resolvido:
			var r := c.resolver(px, pz, nx, nz, nivel)
			cap[0] = r
			return r


func _rect_str(r: Collision.Rect) -> String:
	if r == null:
		return "-"
	return "forma%d raw[%d,%d,%d,%d] mask=0x%04x bits=0x%04x nivel=%d" % [
		r.forma, r.f0, r.f1, r.f2, r.f3, r.mask, r.bits, r.nivel]


func _initialize() -> void:
	var specs: Array = [
		["A", true, false, false],
		["B_circ", false, true, false],
		["B_semarestas", false, false, true],
		["B_ontem", false, true, true],
	]
	for caso: Array in ROOMS:
		var sala: String = caso[0]
		print("\n===== %s =====" % sala)
		var vs: Array = []
		var falhou := false
		for s: Array in specs:
			var v := Variante.new()
			v.nome = s[0]
			v.estoque = s[1]
			v.circ = s[2]
			v.arestas = s[3]
			if not v.preparar(sala, int(caso[1]), int(caso[2]), int(caso[3])):
				print("[ab] %s NÃO CARREGOU" % sala)
				falhou = true
				break
			vs.append(v)
		if falhou:
			continue

		# lockstep: mesmo input, mesmo giro forçado, um tick por variante por iteração
		var pad := Pad.new()
		var stats: Dictionary = {}           # nome -> {parado, pior, seq, celulas}
		var hist: Dictionary = {}            # nome -> Array por tick: [pos, moveu, quem_str, rej, sala]
		for v: Variante in vs:
			stats[v.nome] = {"parado": 0, "pior": 0, "seq": 0, "celulas": {}}
			hist[v.nome] = []
		for i in TICKS:
			pad.set_mask(Pad.FWD)
			for v: Variante in vs:
				v.tick_atual[0] = i
				if i % 25 == 24:
					v.w.player.facing = PS1Math.wrap_angle(v.w.player.facing + 512)
				var antes: Vector3i = v.w.player.pos
				v.ult[0] = null
				v.w.tick(pad)
				var pos: Vector3i = v.w.player.pos
				var moveu := pos != antes
				var res: Collision.Resolvido = v.ult[0]
				var quem := _rect_str(res.quem) if res != null and res.quem != null else "-"
				var rej: bool = res != null and res.rejeitado
				hist[v.nome].append([pos, moveu, quem, rej, v.w.room.room_id])
				var st: Dictionary = stats[v.nome]
				st["celulas"][Vector2i(pos.x / 400, pos.z / 400)] = true
				if not moveu:
					st["parado"] += 1
					st["seq"] += 1
					st["pior"] = maxi(int(st["pior"]), int(st["seq"]))
				else:
					st["seq"] = 0

		# ── resumo por variante ──
		for v: Variante in vs:
			var st: Dictionary = stats[v.nome]
			var fim: Array = hist[v.nome][TICKS - 1]
			print("[%s] %-13s células=%d parado=%d/%d pior_seq=%d fim=%s sala_fim=%s trocas=%s" % [
				sala, v.nome, st["celulas"].size(), st["parado"], TICKS, st["pior"],
				fim[0], fim[4], str(v.trocas_log) if not v.trocas_log.is_empty() else "0"])

		# ── A vs cada B: primeira divergência + episódios "um anda, o outro não" ──
		var ha: Array = hist["A"]
		for v: Variante in vs:
			if v.nome == "A":
				continue
			var hb: Array = hist[v.nome]
			var difs := 0
			var primeira := -1
			for i in TICKS:
				if ha[i][0] != hb[i][0]:
					difs += 1
					if primeira < 0:
						primeira = i
			if difs == 0:
				print("  A == %s em TODOS os %d ticks (posições idênticas)" % [v.nome, TICKS])
				continue
			print("  A != %s em %d/%d ticks; 1ª divergência no tick %d:" % [v.nome, difs, TICKS, primeira])
			print("    A : pos=%s moveu=%s rej=%s quem=%s sala=%s" % [
				ha[primeira][0], ha[primeira][1], ha[primeira][3], ha[primeira][2], ha[primeira][4]])
			print("    %s : pos=%s moveu=%s rej=%s quem=%s sala=%s" % [v.nome,
				hb[primeira][0], hb[primeira][1], hb[primeira][3], hb[primeira][2], hb[primeira][4]])
			var a_trava := 0
			var b_trava := 0
			var mostrados := 0
			for i in TICKS:
				var a_parado: bool = not ha[i][1]
				var b_parado: bool = not hb[i][1]
				if a_parado and not b_parado:
					a_trava += 1
					if mostrados < 6:
						print("    tick %d: A TRAVA (rej=%s quem=%s pos=%s) · %s anda (pos=%s)" % [
							i, ha[i][3], ha[i][2], ha[i][0], v.nome, hb[i][0]])
						mostrados += 1
				elif b_parado and not a_parado:
					b_trava += 1
					if mostrados < 6:
						print("    tick %d: %s TRAVA (rej=%s quem=%s pos=%s) · A anda (pos=%s)" % [
							i, v.nome, hb[i][3], hb[i][2], hb[i][0], ha[i][0]])
						mostrados += 1
			print("    total: A parado onde %s anda = %d ticks · %s parado onde A anda = %d ticks" % [
				v.nome, a_trava, v.nome, b_trava])
	quit(0)
