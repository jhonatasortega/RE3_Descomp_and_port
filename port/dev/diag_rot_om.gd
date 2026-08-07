extends SceneTree
## MEDE a convenção de rotação do objeto de sala (`0x7f`), sem chutar.
##
## O critério é do próprio jogo: muitos itens de chão são **quads PLANOS** (a chave da R100 tem
## AABB 123×0×61). Num plano, a normal tem de apontar para a CÂMERA QUE O ENQUADRA — senão o
## jogador veria o avesso, ou nada (plano de perfil). Então, para cada candidato de convenção,
## conta-se em quantos itens planos a normal fica virada para a câmera que enquadra o objeto.
##
## Candidatos: ordem de composição (Rz·Ry·Rx como o `RotMatrix` do PS1, e a inversa Rx·Ry·Rz) ×
## sinais dos três ângulos. A conversão de mundo do port é `(x,-y,-z)`, que é uma rotação de 180°
## em X; por conjugação, isso prevê sinais `(+x, -y, -z)` — o teste diz se a previsão se sustenta.
## A convenção que a medição elegeu (ver Coords.basis_from_ps1_rot): os itens que falham NELA são
## os que interessam — ou a heurística de câmera errou, ou o plano está virado no próprio dado.
const VENCEDORA := "XYZ +,-,-"

const CANDIDATOS := [
	["ZYX +,+,+", 0, 1, 1, 1], ["ZYX +,-,-", 0, 1, -1, -1],
	["ZYX -,+,+", 0, -1, 1, 1], ["ZYX -,-,-", 0, -1, -1, -1],
	["ZYX +,+,-", 0, 1, 1, -1], ["ZYX +,-,+", 0, 1, -1, 1],
	["XYZ +,+,+", 1, 1, 1, 1], ["XYZ +,-,-", 1, 1, -1, -1],
	["XYZ -,+,+", 1, -1, 1, 1], ["XYZ -,-,-", 1, -1, -1, -1],
	["XYZ +,+,-", 1, 1, 1, -1], ["XYZ +,-,+", 1, 1, -1, 1],
]


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
	var acertos := {}
	var testados := 0
	var planos := 0
	for c: Array in CANDIDATOS:
		acertos[c[0]] = 0
	for sala: String in salas:
		var w := World.new()
		if not w.carregar(sala):
			continue
		for a: Aot in w.itens_no_chao():
			var obj := w.objeto_do_item(a)
			if obj == null or not obj.posicionado() or not a.tem_modelo():
				continue
			var rel := "OMODEL/%s/om%d.glb" % [sala, a.item_om]
			if not AssetIO.exists(rel):
				continue
			var no := AssetIO.model(rel)
			if no == null:
				continue
			var dados := _plano_de(no)
			no.queue_free()
			if dados.is_empty():
				continue                       ## não é plano: a normal média não diz nada
			planos += 1
			# câmera que ENQUADRA o objeto: a que tem o objeto mais perto do eixo de visão
			var alvo := Coords.to_godot_i(obj.pos.x, obj.pos.y, obj.pos.z)
			var melhor := -1
			var melhor_dot := 0.55            ## ~57° do eixo: fora disso não está enquadrado
			for i in w.room.cameras.size():
				var cam: RoomData.Camera = w.room.cameras[i]
				var cp := Coords.to_godot_i(cam.from_ps1.x, cam.from_ps1.y, cam.from_ps1.z)
				var ct := Coords.to_godot_i(cam.to_ps1.x, cam.to_ps1.y, cam.to_ps1.z)
				if cp.distance_to(ct) < 0.001 or cp.distance_to(alvo) < 0.001:
					continue
				var eixo := (ct - cp).normalized()
				var para := (alvo - cp).normalized()
				var d := eixo.dot(para)
				if d > melhor_dot:
					melhor_dot = d
					melhor = i
			if melhor < 0:
				continue
			var cam2: RoomData.Camera = w.room.cameras[melhor]
			var para_camera := (Coords.to_godot_i(cam2.from_ps1.x, cam2.from_ps1.y,
				cam2.from_ps1.z) - alvo).normalized()
			testados += 1
			for c: Array in CANDIDATOS:
				var b := _base(obj.rot, int(c[1]), int(c[2]), int(c[3]), int(c[4]))
				var n := (b * (dados["normal"] as Vector3)).normalized()
				var dot := n.dot(para_camera)
				if dot > 0.0:
					acertos[c[0]] = int(acertos[c[0]]) + 1
				elif c[0] == VENCEDORA:
					print("[rot] DE COSTAS (%s) %s aot%d item0x%02x om=%d rot%s · dot=%.2f · cam %d" % [
						VENCEDORA, sala, a.id, a.item_id, a.item_om, obj.rot, dot, melhor])
	print("[rot] %d itens planos, %d com câmera que enquadra" % [planos, testados])
	var lista: Array = []
	for k: String in acertos:
		lista.append([int(acertos[k]), k])
	lista.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) > int(y[0]))
	for e: Array in lista:
		print("[rot]   %-12s normal virada para a câmera em %d/%d (%.0f%%)" % [
			e[1], e[0], testados, 100.0 * float(e[0]) / maxf(1.0, float(testados))])
	quit(0)


func _base(rot: Vector3i, ordem: int, sx: int, sy: int, sz: int) -> Basis:
	var rx := Coords.yaw_from_ps1_angle(rot.x * sx)
	var ry := Coords.yaw_from_ps1_angle(rot.y * sy)
	var rz := Coords.yaw_from_ps1_angle(rot.z * sz)
	var bx := Basis(Vector3.RIGHT, rx)
	var by := Basis(Vector3.UP, ry)
	var bz := Basis(Vector3.BACK, rz)
	return (bz * by * bx) if ordem == 0 else (bx * by * bz)


func _plano_de(n: Node) -> Dictionary:
	## Normal média (ponderada por área) e teste de planaridade: devolve {} se o modelo tem
	## volume (aí a normal média é ~0 e o critério não se aplica).
	var soma := Vector3.ZERO
	var area := 0.0
	var caixa := AABB()
	var primeiro := true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b := mi.get_aabb()
		if primeiro:
			caixa = b
			primeiro = false
		else:
			caixa = caixa.merge(b)
		var m := mi.mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				continue
			for t in range(0, idx.size() - 2, 3):
				var a := v[idx[t]]
				var b2 := v[idx[t + 1]]
				var c2 := v[idx[t + 2]]
				var cr := (b2 - a).cross(c2 - a)
				soma += cr
				area += cr.length()
	if area <= 0.0 or primeiro:
		return {}
	var espessura := mini(mini(int(caixa.size.x * Coords.WORLD_SCALE),
		int(caixa.size.y * Coords.WORLD_SCALE)), int(caixa.size.z * Coords.WORLD_SCALE))
	# plano = uma dimensão quase nula E as normais coerentes (|soma| ≈ area)
	if espessura > 30 or soma.length() < area * 0.8:
		return {}
	return {"normal": soma.normalized()}
