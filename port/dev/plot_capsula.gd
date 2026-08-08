extends SceneTree
## ANTES/DEPOIS das formas 2 e 3: a planta da colisão de uma sala com **só os registros
## forma 2/3**, pintando o que o resolvedor de fato EMPURRA.
##
## O que se mede: para cada célula da grade, o resolvedor é chamado PARADO (prev == candidato) e
## se ele corrigir a posição a célula é "bloqueada". Isso é a área de resposta real do collider.
##
##   • painel ESQUERDO  = modelo ANTIGO (reimplementado aqui, ver `_antigo_empurra`): a resposta
##     das formas 2/3 era "só a linha média", uma parede fina de ±raio em torno de um eixo;
##   • painel DIREITO   = modelo do EXE (`0x8004c57c`/`0x8004c6ec`): CÁPSULA — caixa cheia na
##     faixa do meio + um círculo de raio h em cada ponta.
##
## Vermelho = bloqueado; cinza = a caixa envolvente do registro (referência de onde o móvel está).
##
##     COL_SALA=R30B godot --path port --headless --script res://dev/plot_capsula.gd
##
## O PNG sai em `user://` (nunca na raiz do port) e o caminho absoluto é impresso.

const RAIO := Collision.RAIO_ATOR
const PASSO := 60                     ## resolução da grade, em unidades PS1


func _initialize() -> void:
	var sala := OS.get_environment("COL_SALA")
	if sala == "":
		sala = "R30B"
	var room := RoomData.load_room(sala)
	if room == null or room.colisao == null:
		print("[cap] sem colisão em %s" % sala)
		quit(1)
		return
	var todos: Collision = room.colisao
	# só os registros das formas 2/3 que o resolvedor do player enxerga
	var col := Collision.new()
	col.centro1 = todos.centro1
	col.centro2 = todos.centro2
	var alvos: Array[Collision.Rect] = []
	for r: Collision.Rect in todos.rects:
		if (r.forma == 2 or r.forma == 3) and (r.bits & Collision.MASCARA_RESOLVER) != 0:
			col.rects.append(r)
			alvos.append(r)
	if alvos.is_empty():
		print("[cap] %s não tem registro forma 2/3 ligado no resolvedor" % sala)
		quit(1)
		return

	var x0 := 1 << 30
	var x1 := -(1 << 30)
	var z0 := 1 << 30
	var z1 := -(1 << 30)
	for r: Collision.Rect in alvos:
		x0 = mini(x0, r.f0 - RAIO); x1 = maxi(x1, r.f2 + RAIO)
		z0 = mini(z0, r.f1 - RAIO); z1 = maxi(z1, r.f3 + RAIO)
	var nx := (x1 - x0) / PASSO + 1
	var nz := (z1 - z0) / PASSO + 1
	var img := Image.create(nx * 2 + 3, nz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.06, 0.09))
	for z in nz:
		img.set_pixel(nx, z, Color(0.35, 0.35, 0.4))
		img.set_pixel(nx + 1, z, Color(0.35, 0.35, 0.4))

	var n_antes := 0
	var n_depois := 0
	var n_grade := 0
	for iz in nz:
		for ix in nx:
			var wx := x0 + ix * PASSO
			var wz := z0 + iz * PASSO
			n_grade += 1
			# referência: dentro da caixa envolvente de algum registro
			var na_caixa := false
			for r: Collision.Rect in alvos:
				if wx >= r.f0 and wx <= r.f2 and wz >= r.f1 and wz <= r.f3:
					na_caixa = true
					break
			var antes := false
			for r: Collision.Rect in alvos:
				if _antigo_empurra(r, wx, wz):
					antes = true
					break
			var res: Collision.Resolvido = col.resolver(wx, wz, wx, wz, 0)
			var depois: bool = res.empurrado
			if antes:
				n_antes += 1
			if depois:
				n_depois += 1
			var fundo := Color(0.2, 0.2, 0.24) if na_caixa else Color(0.06, 0.06, 0.09)
			img.set_pixel(ix, iz, Color(0.95, 0.2, 0.2) if antes else fundo)
			img.set_pixel(nx + 2 + ix, iz, Color(0.2, 0.9, 0.35) if depois else fundo)

	var alvo := "user://capsula_%s.png" % sala
	img.save_png(alvo)
	print("[cap] %s · %d registros forma 2/3 (de %d) · grade %dx%d passo %d un"
		% [sala, alvos.size(), todos.rects.size(), nx, nz, PASSO])
	print("[cap] células que EMPURRAM:  antes (linha média) = %d  ·  depois (cápsula) = %d  ·  %.1fx"
		% [n_antes, n_depois, (float(n_depois) / maxf(1.0, float(n_antes)))])
	print("[cap] de %d células da grade: %.1f%% -> %.1f%% bloqueadas"
		% [n_grade, 100.0 * n_antes / n_grade, 100.0 * n_depois / n_grade])
	print("[cap] PNG: %s" % ProjectSettings.globalize_path(alvo))
	# por registro, para localizar o entulho que "voltou a existir"
	for i in alvos.size():
		var r: Collision.Rect = alvos[i]
		var span := (r.f3 - r.f1) if r.forma == 2 else (r.f2 - r.f0)
		print("[cap]  forma=%d x[%d..%d] z[%d..%d] h=%d (eixo longo %s)"
			% [r.forma, r.f0, r.f2, r.f1, r.f3, span >> 1, "X" if r.forma == 2 else "Z"])
	quit(0)


func _antigo_empurra(r: Collision.Rect, x: int, z: int) -> bool:
	## Modelo ANTIGO, reimplementado só para o painel da esquerda: uma parede fina na linha média
	## (em Z para a forma 2, em X para a forma 3), inflada pelo raio do ator, com o vão limitado
	## pela caixa. Era `_responder_arestas` antes desta mudança.
	var p := Vector2i(x, z)
	if (r.mask & Collision.BIT_ROTACIONADO) != 0:
		p = Collision.girar_para_rect(x, z, r)
	if r.forma == 2:
		var zm := (r.f1 + r.f3) / 2
		return p.x >= r.f0 - RAIO and p.x <= r.f2 + RAIO and absi(p.y - zm) <= RAIO
	var xm := (r.f0 + r.f2) / 2
	return p.y >= r.f1 - RAIO and p.y <= r.f3 + RAIO and absi(p.x - xm) <= RAIO
