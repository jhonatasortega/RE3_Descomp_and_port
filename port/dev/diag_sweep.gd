extends SceneTree
## Varredura GERAL de colisão com o resolver real: em cada sala, grade de células no nível da
## chegada; célula "presa" = as 4 direções falham (rejeitado ou correção anula o passo).
## Imprime a fração presa e os registros culpados mais frequentes.
const CASOS := [
	["R100", -20400, 0, -20790], ["R101", -18808, -7200, -11475], ["R104", 22767, 0, -16964],
	["R200", -1625, 0, 12210], ["R201", 2990, -16200, -20761], ["R202", 0, 0, 0],
	["R300", 0, 0, 0], ["R301", 0, 0, 0], ["R400", 0, 0, 0], ["R500", 0, 0, 0],
	["R600", 0, 0, 0], ["R700", 0, 0, 0],
]


func _initialize() -> void:
	for caso: Array in CASOS:
		var sala: String = caso[0]
		var room := RoomData.load_room(sala)
		if room.colisao == null or room.erros.size() > 0:
			print("[swp] %s: sem colisão/erros" % sala)
			continue
		var col := room.colisao
		# nível: da chegada declarada, senão 0
		var y0: int = int(caso[2])
		var nivel := y0 / -1800
		# envelope
		var mnx := 32000
		var mxx := -32000
		var mnz := 32000
		var mxz := -32000
		for r in col.rects:
			mnx = mini(mnx, mini(r.f0, r.f2)); mxx = maxi(mxx, maxi(r.f0, r.f2))
			mnz = mini(mnz, mini(r.f1, r.f3)); mxz = maxi(mxz, maxi(r.f1, r.f3))
		var presas := 0
		var livres := 0
		var culpados := {}
		var passo := 400
		for gx in range(mnx + 400, mxx - 400, passo):
			for gz in range(mnz + 400, mxz - 400, passo):
				# só células onde dá para ESTAR: piso válido no nível E fora de qualquer
				# caixa inflada (o resolver parado não mexe nem rejeita)
				var h := col.floor_height(gx, gz, y0)
				if h != y0:
					continue
				var parado := col.resolver(gx, gz, gx, gz, nivel)
				if parado.empurrado or parado.rejeitado:
					continue
				var ok := 0
				var quem: Collision.Rect = null
				for d in 4:
					var dx: int = [78, -78, 0, 0][d]
					var dz: int = [0, 0, 78, -78][d]
					var res := col.resolver(gx, gz, gx + dx, gz + dz, nivel)
					if res.rejeitado:
						quem = res.quem
						continue
					if absi(res.x - gx) + absi(res.z - gz) >= 39:
						ok += 1
					elif res.quem != null:
						quem = res.quem
				if ok == 0:
					presas += 1
					if quem != null:
						var chave := "forma%d raw=[%d,%d,%d,%d]" % [quem.forma, quem.f0, quem.f1, quem.f2, quem.f3]
						culpados[chave] = int(culpados.get(chave, 0)) + 1
				else:
					livres += 1
		var frac := 100.0 * float(presas) / float(maxi(1, presas + livres))
		print("[swp] %-5s nível %2d: %4d livres, %4d presas (%.0f%%)" % [sala, nivel, livres, presas, frac])
		var pares := []
		for k in culpados:
			pares.append([culpados[k], k])
		pares.sort()
		pares.reverse()
		for p in pares.slice(0, 3):
			print("        culpado ×%d: %s" % [p[0], p[1]])
	quit(0)
