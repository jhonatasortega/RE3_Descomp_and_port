class_name RoomData
extends RefCounted
## Sala carregada do dado decodificado — qualquer `R###`, sem nada hardcoded (P1-01).
##
## Lê os três JSON que o pipeline produz por sala e devolve estruturas tipadas, em
## **unidades PS1 inteiras** (a conversão para o Godot é da camada de apresentação):
##
##     data/STAGE{n}/R###.json       câmeras (RID), zonas RVD, script (portas/func_offsets)
##     data/STAGE{n}/R###_col.json   colisão (retângulos XZ) + layout das máscaras por câmera
##     data/STAGE{n}/R###_scd.json   gameplay do SCD: portas com destino, gatilhos, itens,
##                                   inimigos, mensagens, objetos
##
## O protótipo antigo era preso na R100; aqui o nome da sala é parâmetro e o teste carrega
## as **169**. Fontes: docs/formatos/ARD.md, scd_gameplay.md, decomp/notes/occlusion.md.

class Camera:
	extends RefCounted
	var index := 0
	var flag := 0
	var attr := 0                 ## 🟡 candidato a FOV: só 24 valores distintos em 2105 câmeras
	var from_ps1 := Vector3i.ZERO
	var to_ps1 := Vector3i.ZERO
	var mask_data_ptr := 0
	## Sprites de oclusão desta câmera (do `_col.json`), em coordenadas de TELA.
	var mask_groups: Array = []
	var n_masks := 0
	var z_base := 0


class RvdZone:
	extends RefCounted
	var flags := 0
	var from_cam := 0
	var to_cam := 0
	var quad: Array[Vector2i] = []   ## 4 vértices no plano XZ (unidades PS1)
	var degenerate := false
	var active := false
	var cam_group := 0


class CollisionRect:
	extends RefCounted
	var x0 := 0
	var z0 := 0
	var x1 := 0
	var z1 := 0
	var y := 0
	var h := 0
	var wall := false

	func contains(x: int, z: int, raio: int = 0) -> bool:
		return x >= x0 - raio and x <= x1 + raio and z >= z0 - raio and z <= z1 + raio

	func cruza_segmento(ax: int, az: int, bx: int, bz: int, raio: int = 0) -> bool:
		## O motor testa o TRAJETO, não o ponto (laço `0x8004e830`: `$s5` = origem, `$s6` =
		## destino). Sem isso, um passo grande ATRAVESSA a parede (tunneling) — e o passo aqui
		## é de 78 a 222 unidades por tick.
		var mnx := x0 - raio
		var mxx := x1 + raio
		var mnz := z0 - raio
		var mxz := z1 + raio
		# rejeição rápida por caixa envolvente do segmento
		if maxi(ax, bx) < mnx or mini(ax, bx) > mxx:
			return false
		if maxi(az, bz) < mnz or mini(az, bz) > mxz:
			return false
		# extremos dentro
		if (ax >= mnx and ax <= mxx and az >= mnz and az <= mxz):
			return true
		if (bx >= mnx and bx <= mxx and bz >= mnz and bz <= mxz):
			return true
		# teste de eixo separador (o segmento contra o retângulo)
		var dx := bx - ax
		var dz := bz - az
		var e1 := dz * (mnx - ax) - dx * (mnz - az)
		var e2 := dz * (mxx - ax) - dx * (mnz - az)
		var e3 := dz * (mxx - ax) - dx * (mxz - az)
		var e4 := dz * (mnx - ax) - dx * (mxz - az)
		var pos := 0
		var neg := 0
		for e in [e1, e2, e3, e4]:
			if e > 0:
				pos += 1
			elif e < 0:
				neg += 1
		return pos > 0 and neg > 0


class Door:
	extends RefCounted
	var sce := 0
	var aot := 0
	var box := Rect2i()            ## caixa de gatilho no plano XZ (unidades PS1)
	var to_room_id := ""           ## ex.: "R101" (destino ESTÁTICO, resolvido na decomp)
	var to_stage := 0
	var to_room := 0
	var to_pos := Vector3i.ZERO
	var to_facing := 0
	var to_camera := -1


var room_id := ""                  ## "R100"
var stage := 0
var cameras: Array[Camera] = []
var rvd: Array[RvdZone] = []
var rects: Array[CollisionRect] = []       ## caixas envolventes — desenho/compatibilidade
var colisao: Collision = null              ## o motor de colisão real (segmentos, P3-10)
## Seção 14 do RDT: zonas que dão o BANCO da Ordering Table por região do chão (oclusão).
var priority_zones: Dictionary = {}
var center := Vector2i.ZERO
var doors: Array[Door] = []
var triggers: Array = []           ## gatilhos do SCD (dados crus; a VM interpreta na F2)
var items: Array = []
var enemies: Array = []
var messages: Array = []
var func_offsets: Array = []       ## tabela de funções do script (entrada da VM, F2)
var erros: Array[String] = []      ## o que faltou/não bateu ao carregar (nunca silencioso)


static func stage_of(room_id_str: String) -> int:
	## "R100" -> 1 (o primeiro dígito hex do nome é o stage).
	return ("0x%s" % room_id_str.substr(1, 1)).hex_to_int() if room_id_str.length() >= 2 else 0


static func load_room(room_id_str: String) -> RoomData:
	var r := RoomData.new()
	r.room_id = room_id_str
	r.stage = stage_of(room_id_str)
	var base := "STAGE%d/%s" % [r.stage, room_id_str]

	var rdt: Variant = AssetIO.json("%s.json" % base)
	if not (rdt is Dictionary):
		r.erros.append("%s.json ausente ou inválido" % base)
		return r
	r._ler_rdt(rdt as Dictionary)
	r._ler_col(AssetIO.json("%s_col.json" % base))
	r._ler_scd(AssetIO.json("%s_scd.json" % base))
	return r


func _ler_rdt(d: Dictionary) -> void:
	var rdt: Variant = d.get("rdt")
	if not (rdt is Dictionary):
		erros.append("bloco rdt ausente")
		return
	var R: Dictionary = rdt

	for c: Dictionary in R.get("cameras", []):
		var cam := Camera.new()
		cam.index = int(c.get("index", cameras.size()))
		cam.flag = int(c.get("flag", 0))
		cam.attr = int(c.get("attr", 0))
		cam.from_ps1 = _vec3i(c.get("from"))
		cam.to_ps1 = _vec3i(c.get("to"))
		cam.mask_data_ptr = int(c.get("mask_data_ptr", 0))
		cameras.append(cam)

	var n_decl := int(R.get("n_cameras", cameras.size()))
	if n_decl != cameras.size():
		erros.append("n_cameras=%d mas veio %d câmera(s)" % [n_decl, cameras.size()])

	var rv: Variant = R.get("rvd")
	if rv is Dictionary:
		for e: Dictionary in (rv as Dictionary).get("entries", []):
			var z := RvdZone.new()
			z.flags = int(e.get("flags", 0))
			z.from_cam = int(e.get("from", 0))
			z.to_cam = int(e.get("to", 0))
			z.degenerate = bool(e.get("degenerate", false))
			z.active = bool(e.get("active", false))
			z.cam_group = int(e.get("cam_group", 0))
			for p: Array in e.get("quad", []):
				z.quad.append(Vector2i(int(p[0]), int(p[1])))
			rvd.append(z)

	var sc: Variant = R.get("script")
	if sc is Dictionary:
		func_offsets = (sc as Dictionary).get("func_offsets", [])


func _ler_col(d: Variant) -> void:
	if not (d is Dictionary):
		erros.append("_col.json ausente")
		return
	var col: Variant = (d as Dictionary).get("collision")
	if col is Dictionary:
		var C: Dictionary = col
		colisao = Collision.from_json(C)            ## o motor de verdade (segmentos)
		if not C.get("rects", []).is_empty() and not (C["rects"][0] as Dictionary).has("raw"):
			erros.append("_col.json antigo (sem campo `raw`): rode "
				+ "`NOSTALGIA_OUT=port python tools/rdt_collision.py`")
		var ctr: Array = C.get("center", [0, 0])
		if ctr.size() >= 2:
			center = Vector2i(int(ctr[0]), int(ctr[1]))
		for rc: Dictionary in C.get("rects", []):
			var q: Array = rc.get("rect", [])
			if q.size() < 4:
				continue
			var cr := CollisionRect.new()
			# o JSON já vem normalizado min->max (tools/rdt_collision.py)
			cr.x0 = int(q[0]); cr.z0 = int(q[1]); cr.x1 = int(q[2]); cr.z1 = int(q[3])
			cr.y = int(rc.get("y", 0))
			cr.h = int(rc.get("h", 0))
			cr.wall = bool(rc.get("wall", false))
			rects.append(cr)

	# zonas de prioridade (seção 14 do RDT): decidem o BANCO da OT do personagem (oclusão)
	var pz: Variant = (d as Dictionary).get("priority_zones")
	if pz is Dictionary:
		priority_zones = pz

	# máscaras de oclusão: uma entrada por câmera, na ordem das câmeras
	var cm: Variant = (d as Dictionary).get("cameras_masks")
	if cm is Array:
		var lista: Array = cm
		for i in mini(lista.size(), cameras.size()):
			var m: Variant = lista[i]
			if not (m is Dictionary):
				continue
			var M: Dictionary = m
			cameras[i].mask_groups = M.get("groups", [])
			cameras[i].n_masks = int(M.get("n_masks", 0))
			cameras[i].z_base = int(M.get("z_base", 0))
		if lista.size() != cameras.size():
			erros.append("cameras_masks=%d != câmeras=%d" % [lista.size(), cameras.size()])


func _ler_scd(d: Variant) -> void:
	if not (d is Dictionary):
		erros.append("_scd.json ausente")
		return
	var S: Dictionary = d
	for dd: Dictionary in S.get("doors", []):
		var dr := Door.new()
		dr.sce = int(dd.get("sce", 0))
		dr.aot = int(dd.get("aot", 0))
		var b: Variant = dd.get("box")
		if b is Dictionary:
			var B: Dictionary = b
			dr.box = Rect2i(int(B.get("x", 0)), int(B.get("z", 0)),
				int(B.get("w", 0)), int(B.get("d", 0)))
		dr.to_room_id = str(dd.get("to_room_id", ""))
		dr.to_stage = int(dd.get("to_stage", 0))
		dr.to_room = int(dd.get("to_room", 0))
		dr.to_pos = Vector3i(int(dd.get("to_x", 0)), int(dd.get("to_y", 0)),
			int(dd.get("to_z", 0)))
		dr.to_facing = int(dd.get("to_facing", 0))
		dr.to_camera = int(dd.get("to_camera", -1))
		doors.append(dr)
	triggers = S.get("triggers", [])
	items = S.get("items", [])
	enemies = S.get("enemies", [])
	messages = S.get("messages", [])


static func _vec3i(v: Variant) -> Vector3i:
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return Vector3i.ZERO


# ───────────────────────────── consultas de gameplay ─────────────────────────────

func trajeto_livre(ax: int, az: int, bx: int, bz: int, y: int = 0) -> bool:
	## O teste do motor: o trajeto cruza algum SEGMENTO de collider? (`Collision`, P3-10.)
	## O parâmetro `raio` anterior não existe: o EXE não infla nada — quem passa raio é o
	## chamador, escolhendo o ponto de origem/destino do teste.
	if colisao != null:
		return colisao.trajeto_livre(ax, az, bx, bz, y)
	return true


func is_walkable(x: int, z: int, _raio: int = 0) -> bool:
	## "Posição legal" não é uma pergunta que o motor faça: a colisão do RE3 é de TRAJETO.
	## Mantido para diagnóstico/spawn: testa um trajeto curtíssimo em torno do ponto, que é
	## o que mais se aproxima de "estou em cima de um collider".
	if colisao == null:
		return true
	return colisao.trajeto_livre(x - 1, z - 1, x + 1, z + 1)


func door_at(x: int, z: int) -> Door:
	for d in doors:
		if d.box.has_point(Vector2i(x, z)):
			return d
	return null


func camera(i: int) -> Camera:
	return cameras[i] if i >= 0 and i < cameras.size() else null


func priority_zones_da_camera(i: int) -> Array:
	## Zonas de prioridade (banco de OT) da câmera `i`. Vazio = tudo no banco 0.
	var cams: Variant = priority_zones.get("cameras", [])
	if cams is Array and i >= 0 and i < (cams as Array).size():
		var z: Variant = (cams as Array)[i]
		if z is Array:
			return z
	return []


func summary() -> String:
	return "%s: %d câmeras, %d zonas RVD, %d retângulos (%d paredes), %d portas, %d gatilhos, %d funções de script%s" % [
		room_id, cameras.size(), rvd.size(), rects.size(),
		rects.filter(func(r: CollisionRect) -> bool: return r.wall).size(),
		doors.size(), triggers.size(), func_offsets.size(),
		"" if erros.is_empty() else "  ERROS: %s" % ", ".join(erros)]
