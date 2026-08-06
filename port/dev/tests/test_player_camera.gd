extends RefCounted
## Movimento + colisão + troca de câmera pelo RVD (itens P1-05, P1-06, P1-09, P1-11).
##
## Tudo headless e determinístico: o pad é uma máscara injetada por tick, então "andar 30
## ticks para frente" é um teste, não uma sessão de jogo. Isso é o que vai sustentar a
## auditoria das 453 portas (P3-06) e a rota crítica (P3-07).


func run(t: Object) -> bool:
	t.group("Player/RVD")

	var room := RoomData.load_room("R100")
	t.eq(room.erros, [], "R100 carregada")

	# ── ponto-em-quad (a primitiva do consumidor RVD, 0x8001020c) ──
	# ATENÇÃO: o teste do EXE exige uma ORIENTAÇÃO. São 4 meias-retas com sinal fixo, saindo
	# dos cantos OPOSTOS q0 e q2 — quad na ordem contrária é REJEITADO, e isso não é bug: é o
	# que faz as faixas `A→B` e `B→A` não valerem ao mesmo tempo (a histerese da câmera).
	var q: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 100), Vector2i(100, 100),
		Vector2i(100, 0)]
	t.check(CameraRVD.point_in_quad(q, 50, 50), "centro está dentro do quad")
	t.check(not CameraRVD.point_in_quad(q, 150, 50), "fora à direita")
	t.check(not CameraRVD.point_in_quad(q, 50, -10), "fora acima")
	t.check(CameraRVD.point_in_quad(q, 0, 0), "vértice conta como dentro")
	var q_inv: Array[Vector2i] = [Vector2i(0, 0), Vector2i(100, 0), Vector2i(100, 100),
		Vector2i(0, 100)]
	t.check(not CameraRVD.point_in_quad(q_inv, 50, 50),
		"orientação contrária é REJEITADA (como no EXE)")

	# ── flags: bit de ativa e byte de grupo (provados no EXE) ──
	t.check(CameraRVD.flags_active(0x8001), "0x8001 é zona ativa")
	t.check(not CameraRVD.flags_active(0x8000), "0x8000 está desativada")
	t.check(not CameraRVD.flags_active(0x0100), "0x0100 está desativada")
	t.eq(CameraRVD.flags_group(0x8001), 0x80, "byte alto = grupo (0x80 = global)")
	t.check(CameraRVD.group_matches(0x8001, 0x05), "grupo global casa com qualquer seletor")
	t.check(CameraRVD.group_matches(0x0501, 0x05), "grupo específico casa com o igual")
	t.check(not CameraRVD.group_matches(0x0501, 0x06), "grupo específico não casa com outro")

	# ── travessia da R100: depósito -> escritório, ida e volta ──
	# O teste mede a POSIÇÃO onde a câmera troca, nos dois sentidos, e conta as trocas.
	# O bug clássico aqui é o flicker na fronteira (troca a cada frame) — o que a âncora
	# de histerese do EXE evita.
	var st := CameraRVD.Estado.new()
	st.camera = CameraRVD.best_camera_for(room, -21820, -21899)
	t.check(st.camera >= 0 and st.camera < room.cameras.size(), "câmera inicial válida",
		"cam=%d" % st.camera)

	var trocas_ida: Array[int] = []
	var cam_ant := st.camera
	for x in range(-21000, -26000, -100):
		var novo := CameraRVD.update(room, st, x, -21899)
		if novo != cam_ant:
			trocas_ida.append(x)
			cam_ant = novo
	var trocas_volta: Array[int] = []
	for x in range(-26000, -21000, 100):
		var novo := CameraRVD.update(room, st, x, -21899)
		if novo != cam_ant:
			trocas_volta.append(x)
			cam_ant = novo
	# ATENÇÃO: a versão anterior deste assert era `trocas <= 4`, que passa com ZERO trocas —
	# e foi assim que "a câmera nunca troca" passou batido até o usuário reportar em jogo.
	# Agora cobra as duas coisas: TEM de trocar, e não pode piscar.
	t.check(st.trocas >= 2, "a câmera TROCA na ida e na volta (não passa com zero)",
		"trocas=%d ida=%s volta=%s" % [st.trocas, trocas_ida, trocas_volta])
	t.check(st.trocas <= 6, "sem flicker (poucas trocas na travessia)",
		"trocas=%d" % st.trocas)
	t.check(not trocas_ida.is_empty() and not trocas_volta.is_empty(),
		"troca nos DOIS sentidos", "ida=%s volta=%s" % [trocas_ida, trocas_volta])

	# alcance: varrendo a sala, mais de uma câmera tem de ser alcançável
	var st2 := CameraRVD.Estado.new()
	st2.camera = 0
	var alcancadas := {}
	for x2 in range(-32000, 8000, 800):
		for z2 in range(-32000, 8000, 800):
			alcancadas[CameraRVD.update(room, st2, x2, z2)] = true
	t.eq(alcancadas.size(), room.cameras.size(),
		"varrendo a R100, as 2 câmeras são alcançadas", "%d" % alcancadas.size())

	# ── colisão: o raio para o personagem na FACE do móvel ──
	var p := Player.new()
	p.walkable = func(x: int, z: int) -> bool: return room.is_walkable(x, z, Player.RAIO_PS1)
	p.pos = Vector3i(-21820, -258, -21899)
	p.facing = 0
	t.check(p.walkable.call(p.pos.x, p.pos.z), "spawn é caminhável com o raio aplicado")

	# ── andar 30 ticks para frente: anda, e o deslocamento bate com a velocidade medida ──
	var pad := Pad.new()
	var inicio := p.pos
	for _i in 30:
		pad.set_mask(Pad.FWD)
		p.tick(pad)
	var andou := Vector2(float(p.pos.x - inicio.x), float(p.pos.z - inicio.z)).length()
	t.check(andou > 0.0, "andou para frente", "deslocamento = %.0f un" % andou)
	t.eq(p.acao, Player.Acao.ANDANDO, "ação = ANDANDO")
	t.eq(p.clipe_atual(), "arm00", "clipe do andar armado")
	# 30 ticks × 78 un/frame = 2340 un se não houver obstáculo; com colisão pode ser menos.
	t.check(andou <= 30.0 * float(Player.VEL_ANDAR) + 1.0,
		"não andou mais do que a velocidade permite", "%.0f un" % andou)

	# ── DIREÇÃO: a frente do MOVIMENTO é a frente do RENDER, em TODO ângulo ──
	# O render usa `rotation.y = to_deg(facing)`; o forward do nó em PS1 é
	# `(-sin(facing), +cos(facing))`. A convenção anterior ("frente é -Z com facing 0",
	# fixada por observação) era um ESPELHO em Z: coincidia com o render só em ±X — perto de
	# 0/2048 a Jill andava de costas (print do usuário: facing 3628, modelo olhando para a
	# câmera e o passo indo para o lado oposto).
	var pd := Player.new()
	pd.facing = 0
	var pad_d := Pad.new()
	pad_d.set_mask(Pad.FWD)
	pd.tick(pad_d)
	# Convenção FECHADA em jogo pelo usuário ("deu certo, só inverte o W e S"):
	# frente = (+sin(facing), -cos(facing)). Com facing 0 → -Z.
	t.check(pd.pos.z < 0, "com facing 0 a frente é -Z (validado em jogo)", "z=%d" % pd.pos.z)
	t.eq(pd.pos.x, 0, "e não desloca em X")
	var pd2 := Player.new()
	pd2.facing = 1024                      # 90°
	pd2.tick(pad_d)
	t.check(pd2.pos.x > 0, "com facing 90°, a frente vira +X em PS1", "x=%d" % pd2.pos.x)
	var pd3 := Player.new()
	pd3.facing = 0
	var pad_r := Pad.new()
	pad_r.set_mask(Pad.BACK)
	pd3.tick(pad_r)
	t.check(pd3.pos.z > 0, "a ré vai para o lado oposto", "z=%d" % pd3.pos.z)
	# a frente é a MESMA função contínua em qualquer ângulo (sem espelho por quadrante)
	for a in [300, 1500, 2600, 3628]:
		var passo := Vector2(float(PS1Math.rsin(a)), float(-PS1Math.rcos(a))) / 4096.0
		var fwd := Vector2(sin(deg_to_rad(PS1Math.to_deg(a))), -cos(deg_to_rad(PS1Math.to_deg(a))))
		t.check((passo - fwd).length() < 0.01, "passo contínuo em facing %d" % a)

	# ── SENTIDO DO GIRO (regressão do segundo bug reportado em jogo) ──
	# D (direita) tem de girar no sentido horário visto de cima, o que DIMINUI o facing —
	# porque a frente é -Z e yaw crescente no Godot gira anti-horário.
	var pg := Player.new()
	pg.facing = 0
	var pad_dir := Pad.new()
	pad_dir.set_mask(Pad.HELD_RIGHT)
	pg.tick(pad_dir)
	t.check(PS1Math.angle_diff(0, pg.facing) < 0,
		"D diminui o facing (fixado por observação em jogo)", "facing=%d" % pg.facing)
	var pg2 := Player.new()
	pg2.facing = 0
	var pad_esq := Pad.new()
	pad_esq.set_mask(Pad.HELD_LEFT)
	pg2.tick(pad_esq)
	t.check(PS1Math.angle_diff(0, pg2.facing) > 0,
		"A aumenta o facing", "facing=%d" % pg2.facing)
	# e o resultado combinado (conjunto VALIDADO em jogo: A/D corretos, W/S fechado depois):
	# D leva facing 0 → 3072, e com a frente `(+sin,-cos)` isso anda em -X.
	var pg3 := Player.new()
	pg3.facing = PS1Math.wrap_angle(-1024)     # D a partir de 0 = 3072
	pg3.tick(pad_d)
	t.check(pg3.pos.x < 0, "após D 90° a partir de 0, o passo vai para -X (conjunto validado)",
		"x=%d" % pg3.pos.x)

	# ── parado: sem input, não se move ──
	var parado_antes := p.pos
	for _i in 10:
		pad.set_mask(0)
		p.tick(pad)
	t.eq(p.pos, parado_antes, "sem input não há movimento")
	t.eq(p.acao, Player.Acao.PARADO, "ação = PARADO")
	t.eq(p.clipe_atual(), "arm02", "idle armado")

	# ── giro no lugar: muda o facing, não a posição ──
	var pos_antes := p.pos
	var face_antes := p.facing
	for _i in 10:
		pad.set_mask(Pad.HELD_RIGHT)
		p.tick(pad)
	t.eq(p.pos, pos_antes, "girar não translada")
	t.eq(PS1Math.angle_diff(face_antes, p.facing), -10 * Player.GIRO_POR_FRAME,
		"10 ticks de D = -390 unidades de ângulo")
	for _i in 10:
		pad.set_mask(Pad.HELD_LEFT)
		p.tick(pad)
	t.eq(p.facing, face_antes, "girar de volta retorna ao ângulo inicial")

	# ── quick-turn: 180° em 8 ticks, disparado na borda ré+correr ──
	var p2 := Player.new()
	p2.facing = 0
	var pad2 := Pad.new()
	for _i in 10:
		pad2.set_mask(Pad.BACK | Pad.RUN)
		p2.tick(pad2)
	t.eq(p2.facing, PS1Math.HALF_CIRCLE, "quick-turn completou 180° (2048 unidades)")
	t.eq(p2.quickturn_restante, 0, "quick-turn terminou")

	# ── ré é sempre velocidade de andar (o RE3 não corre para trás) ──
	var p3 := Player.new()
	p3.facing = 0
	var pad3 := Pad.new()
	var i3 := p3.pos
	for _i in 5:
		pad3.set_mask(Pad.BACK)          # sem RUN: não dispara quick-turn
		p3.tick(pad3)
	var re_dist := Vector2(float(p3.pos.x - i3.x), float(p3.pos.z - i3.z)).length()
	t.check(re_dist > 0.0 and re_dist <= 5.0 * float(Player.VEL_RE) + 1.0,
		"ré anda com a velocidade de ré", "%.0f un em 5 ticks" % re_dist)
	t.eq(p3.acao, Player.Acao.RE, "ação = RE")

	# ── colisão barra: andar contra a parede não atravessa ──
	var p4 := Player.new()
	p4.walkable = func(x: int, z: int) -> bool: return room.is_walkable(x, z, Player.RAIO_PS1)
	p4.pos = Vector3i(-21820, -258, -21899)
	p4.facing = PS1Math.from_deg(90.0)      # aponta para +X (rumo ao armário)
	var pad4 := Pad.new()
	for _i in 200:                           # 200 ticks: muito mais que a sala
		pad4.set_mask(Pad.FWD)
		p4.tick(pad4)
	t.check(p4.walkable.call(p4.pos.x, p4.pos.z),
		"depois de 200 ticks contra o cenário, a posição continua legal",
		"pos=%s" % p4.pos)

	# ── root motion: declara o que é tabela e o que é média ──
	p.carregar_root_motion()
	t.check(p.usando_tabela("anim00"), "clipe base anim00 tem tabela por frame (medida)")
	t.check(not p.usando_tabela("arm00"),
		"clipe ARMADO arm00 ainda NÃO tem tabela — usa a média medida (P1-10 parcial)")

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true
