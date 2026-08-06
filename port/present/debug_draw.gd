class_name DebugDraw
extends MeshInstance3D
## Wireframe da colisão da sala no espaço 3D — ferramenta de calibração (P1-04/P1-06).
##
## Serve para uma pergunta que só o render responde: **a câmera e o FOV estão certos?**
## Os retângulos de colisão são a planta real da sala (paredes e móveis). Se a projeção 3D
## estiver correta, o wireframe **coincide** com as paredes e móveis do cenário
## pré-renderizado. Se o FOV estiver errado, o desenho abre ou fecha em relação ao cenário —
## o erro fica óbvio nas bordas da sala.
##
## Usado em `dev/shot.gd` via `SHOT_DEBUG=1`.

const COR_PAREDE := Color(1.0, 0.25, 0.25, 1.0)
const COR_MOVEL := Color(0.25, 1.0, 0.4, 1.0)
const COR_INATIVO := Color(0.15, 0.45, 0.2, 1.0)   ## collider desligado (andar/estado)
const COR_PISO := Color(0.3, 0.6, 1.0, 1.0)
const COR_PORTA := Color(0.2, 0.9, 1.0, 1.0)     ## AOT de porta
const COR_ITEM := Color(1.0, 0.9, 0.2, 1.0)      ## AOT de item
const COR_TRIGGER := Color(1.0, 0.4, 1.0, 1.0)   ## outros AOT (gatilhos)


enum Modo {
	SEGMENTOS,      ## o que o motor testa: as linhas de cada forma (só os colliders ATIVOS)
	VOLUMES,        ## as linhas + a extrusão até o `topo` real: dá para casar com o cenário
	TUDO,           ## idem, incluindo os colliders DESLIGADOS (outro andar / estado do script)
}

## Cores por categoria (mesma legenda que a HUD imprime).
const COR_ENVELOPE := Color(1.0, 0.2, 0.2, 1.0)     ## moldura da sala (nível 15, topo -28800)
const COR_OBJETO := Color(0.25, 1.0, 0.4, 1.0)      ## móvel/obstáculo comum
const COR_CIRCULO := Color(1.0, 0.85, 0.2, 1.0)     ## forma 0 (círculo: pilar, barril)
const COR_GIRADO := Color(1.0, 0.5, 0.1, 1.0)       ## collider girado 45° (`mask & 0x1000`)
const COR_DESLIGADO := Color(0.35, 0.35, 0.42, 1.0) ## fora do nível ou desligado pelo script


func desenhar_modo(room: RoomData, y_player: int, modo: Modo) -> Dictionary:
	## Inspetor de colisão em cena (pedido do usuário: "mostrar zonas de colisão, objetos,
	## parede... visualmente"). Devolve a contagem por categoria, para a HUD mostrar a legenda.
	var contagem := {"envelope": 0, "objeto": 0, "circulo": 0, "girado": 0, "desligado": 0}
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	material_override = mat
	if room.colisao == null:
		return contagem
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for r in room.colisao.rects:
		var ativo := (r.bits & Collision.MASCARA_PLAYER) != 0 and r.forma != 0x0B \
			and r.topo <= y_player and r.base_y >= y_player
		if not ativo:
			contagem["desligado"] += 1
			if modo != Modo.TUDO:
				continue
		var girado := (r.mask & Collision.BIT_ROTACIONADO) != 0
		var cor := COR_DESLIGADO
		if ativo:
			if girado:
				cor = COR_GIRADO
				contagem["girado"] += 1
			elif r.forma == 0:
				cor = COR_CIRCULO
				contagem["circulo"] += 1
			elif r.nivel == 15:
				cor = COR_ENVELOPE
				contagem["envelope"] += 1
			else:
				cor = COR_OBJETO
				contagem["objeto"] += 1
		# ALTURA REAL: da base (`-1800 × +0x0c`) até o topo (`+0x0e`). O envelope da sala vai a
		# -28800, o que no render sobe fora do quadro — corta em 4000 un para não virar sopa.
		var y_base := r.base_y
		var y_topo := maxi(r.topo, y_base - 4000) if modo != Modo.SEGMENTOS else y_base
		if r.forma == 0:
			var c := r.centro()
			if girado:
				c = Collision.girar_para_mundo(c.x, c.y, r)
			_circulo(im, c, r.raio(), y_base, cor)
			if modo != Modo.SEGMENTOS:
				_circulo(im, c, r.raio(), y_topo, cor)
			continue
		for s: Array in r.segmentos():
			var a := Vector2i(s[0], s[1])
			var b := Vector2i(s[2], s[3])
			if girado:
				a = Collision.girar_para_mundo(a.x, a.y, r)
				b = Collision.girar_para_mundo(b.x, b.y, r)
			_linha(im, a, b, y_base, cor)
			if modo != Modo.SEGMENTOS:
				_linha(im, a, b, y_topo, cor)
				_linha(im, a, a, y_base, cor, y_topo)
				_linha(im, b, b, y_base, cor, y_topo)
	im.surface_end()
	mesh = im
	return contagem


func _linha(im: ImmediateMesh, a: Vector2i, b: Vector2i, y: int, cor: Color,
		y2: int = 0x7FFFFFFF) -> void:
	var yb := y if y2 == 0x7FFFFFFF else y2
	im.surface_set_color(cor)
	im.surface_add_vertex(Coords.to_godot_i(a.x, y, a.y))
	im.surface_set_color(cor)
	im.surface_add_vertex(Coords.to_godot_i(b.x, yb, b.y))


func desenhar(room: RoomData, y_player: int = 0) -> void:
	## Desenha a colisão COMO O MOTOR A VÊ: os SEGMENTOS de cada forma, não caixas.
	##
	## Antes isto desenhava a caixa envolvente de cada registro, o que dava a impressão errada
	## (parecia que a sala inteira era sólida). Cada collider é uma lista de segmentos
	## (`Collision.Rect.segmentos`), e o que bloqueia é CRUZAR um segmento.
	##
	## Cor: vermelho = ativo para o player neste `y` (passou máscara `0x40` e altura);
	## verde-escuro = existe mas está desligado agora (outro andar ou estado do script).
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true                     ## queremos ver o wireframe inteiro
	material_override = mat

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	if room.colisao != null:
		for r in room.colisao.rects:
			var ativo := (r.bits & Collision.MASCARA_PLAYER) != 0 \
				and r.forma != 0x0B and r.topo <= y_player and r.base_y >= y_player
			var cor := COR_PAREDE if ativo else COR_INATIVO
			var y := maxi(r.topo, y_player - 1800)
			var girado := (r.mask & Collision.BIT_ROTACIONADO) != 0
			if r.forma == 0:
				var c := r.centro()
				if girado:
					c = Collision.girar_para_mundo(c.x, c.y, r)
				_circulo(im, c, r.raio(), y, cor)
				continue
			for s: Array in r.segmentos():
				# Colliders girados 45°: desenha no MUNDO (inversa da rotação que o motor aplica
				# ao trajeto). Sem isso o desenho mostra o retângulo cru, num lugar diferente do
				# que barra de fato — e o wireframe passa a mentir justamente onde mais importa.
				var a := Vector2i(s[0], s[1])
				var b := Vector2i(s[2], s[3])
				if girado:
					a = Collision.girar_para_mundo(a.x, a.y, r)
					b = Collision.girar_para_mundo(b.x, b.y, r)
				im.surface_set_color(cor)
				im.surface_add_vertex(Coords.to_godot_i(a.x, y_player, a.y))
				im.surface_set_color(cor)
				im.surface_add_vertex(Coords.to_godot_i(b.x, y_player, b.y))
				# aresta vertical até o topo, para o segmento virar "parede" no render
				for p: Vector2i in [a, b]:
					im.surface_set_color(cor)
					im.surface_add_vertex(Coords.to_godot_i(p.x, y_player, p.y))
					im.surface_set_color(cor)
					im.surface_add_vertex(Coords.to_godot_i(p.x, y, p.y))
	else:
		for r in room.rects:                     ## dado antigo: cai para a envolvente
			_caixa(im, r.x0, r.z0, r.x1, r.z1, y_player, y_player - 2500, COR_MOVEL)
	im.surface_end()
	mesh = im


func _circulo(im: ImmediateMesh, c: Vector2i, raio: int, y_topo: int, cor: Color,
		lados: int = 16) -> void:
	## Forma 0 do motor: círculo inscrito na caixa (raio = largura/2).
	var ant := Vector2i(c.x + raio, c.y)
	for i in range(1, lados + 1):
		var a := TAU * float(i) / float(lados)
		var p := Vector2i(c.x + int(cos(a) * raio), c.y + int(sin(a) * raio))
		im.surface_set_color(cor)
		im.surface_add_vertex(Coords.to_godot_i(ant.x, y_topo, ant.y))
		im.surface_set_color(cor)
		im.surface_add_vertex(Coords.to_godot_i(p.x, y_topo, p.y))
		ant = p


func desenhar_grade(room: RoomData, chao_y: int = 0, passo: int = 1000) -> void:
	## Grade no plano do chão, em Y fixo. Se ela assenta nas lajotas do cenário, o Y do chão e
	## a projeção estão certos; se flutua, o problema é o Y (não o offset do pé do personagem).
	var mnx := 32767
	var mxx := -32768
	var mnz := 32767
	var mxz := -32768
	for r in room.rects:
		mnx = mini(mnx, r.x0); mxx = maxi(mxx, r.x1)
		mnz = mini(mnz, r.z0); mxz = maxi(mxz, r.z1)
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x := mnx
	while x <= mxx:
		im.surface_set_color(COR_PISO)
		im.surface_add_vertex(Coords.to_godot_i(x, chao_y, mnz))
		im.surface_set_color(COR_PISO)
		im.surface_add_vertex(Coords.to_godot_i(x, chao_y, mxz))
		x += passo
	var z := mnz
	while z <= mxz:
		im.surface_set_color(COR_PISO)
		im.surface_add_vertex(Coords.to_godot_i(mnx, chao_y, z))
		im.surface_set_color(COR_PISO)
		im.surface_add_vertex(Coords.to_godot_i(mxx, chao_y, z))
		z += passo
	im.surface_end()
	mesh = im


func desenhar_aots(vm: ScriptVM, chao_y: int = 0) -> void:
	## Desenha as CAIXAS DE GATILHO que o script instalou: porta, item e demais AOT.
	## Serve para responder "a caixa da porta está onde a porta aparece?" olhando, em vez de
	## deduzir de coordenadas.
	if vm == null:
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	material_override = mat
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in vm.aots:
		var a: Aot = vm.aots[k]
		var cor := COR_TRIGGER
		if a.is_porta():
			cor = COR_PORTA
		elif a.is_item():
			cor = COR_ITEM
		if a.kind == Aot.Kind.BOX:
			_caixa(im, a.box.position.x, a.box.position.y,
				a.box.position.x + a.box.size.x, a.box.position.y + a.box.size.y,
				chao_y, chao_y - 2000, cor)
		elif a.quad.size() == 4:
			for i in 4:
				var p1: Vector2i = a.quad[i]
				var p2: Vector2i = a.quad[(i + 1) % 4]
				for yy in [chao_y, chao_y - 2000]:
					im.surface_set_color(cor)
					im.surface_add_vertex(Coords.to_godot_i(p1.x, yy, p1.y))
					im.surface_set_color(cor)
					im.surface_add_vertex(Coords.to_godot_i(p2.x, yy, p2.y))
	im.surface_end()
	mesh = im


func _caixa(im: ImmediateMesh, x0: int, z0: int, x1: int, z1: int, y_base: int, y_topo: int,
		cor: Color) -> void:
	var b := Coords.to_godot_i(x0, y_base, z0)
	var c := Coords.to_godot_i(x1, y_base, z0)
	var d := Coords.to_godot_i(x1, y_base, z1)
	var e := Coords.to_godot_i(x0, y_base, z1)
	var B := Coords.to_godot_i(x0, y_topo, z0)
	var C := Coords.to_godot_i(x1, y_topo, z0)
	var D := Coords.to_godot_i(x1, y_topo, z1)
	var E := Coords.to_godot_i(x0, y_topo, z1)
	for par: Array in [[b, c], [c, d], [d, e], [e, b],      # base
			[B, C], [C, D], [D, E], [E, B],                  # topo
			[b, B], [c, C], [d, D], [e, E]]:                 # arestas verticais
		im.surface_set_color(cor)
		im.surface_add_vertex(par[0])
		im.surface_set_color(cor)
		im.surface_add_vertex(par[1])
