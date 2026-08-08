extends RefCounted
## Colisão de TRAJETO: as formas do motor, o filtro de altura e as invariantes globais (P3-10).
##
## O que estes testes protegem: o port já teve DUAS vezes um modelo de colisão errado (ponto
## dentro de caixa cheia, e depois caixa cheia com raio). Os dois passavam num "teste" que só
## olhava se o spawn era livre. Aqui as afirmações são as do EXE:
##   • cruzar um segmento bloqueia; estar dentro da envolvente não;
##   • cada forma tem a lista de segmentos que a função correspondente da tabela `0x8009e088`
##     constrói;
##   • o filtro de altura desliga o collider dos outros níveis;
##   • invariante de jogo nas 169 salas: TODA chegada de porta consegue dar o primeiro passo.


func _rect(f0: int, f1: int, f2: int, f3: int, forma: int, mask := 0xFFFF) -> Collision.Rect:
	var r := Collision.Rect.new()
	r.f0 = f0; r.f1 = f1; r.f2 = f2; r.f3 = f3
	r.forma = forma
	r.bits = 0xFE40 | forma
	r.mask = mask
	r.base_y = 0
	r.topo = -1800
	r.envolve()
	return r


func run(t: Object) -> bool:
	t.group("Colisão")
	# ── interseção segmento × segmento (o `0x8004ef74` da GTE) ──
	t.check(Collision.segmentos_cruzam(0, 0, 100, 0, 50, -50, 50, 50), "cruz em X: cruza")
	t.check(not Collision.segmentos_cruzam(0, 0, 40, 0, 50, -50, 50, 50),
		"segmento que para antes: não cruza")
	t.check(not Collision.segmentos_cruzam(0, 0, 100, 0, 0, 10, 100, 10), "paralelos: não cruzam")
	t.check(not Collision.segmentos_cruzam(0, 0, 100, 0, 100, 0, 100, 50),
		"tocar a ponta não conta (o EXE trata sinal 0 como mesmo lado)")

	# ── forma 1/7: as duas diagonais ──
	var r1 := _rect(-1000, -1000, 1000, 1000, 1)
	t.eq(r1.segmentos().size(), 2, "forma 1 tem 2 segmentos (as diagonais)")
	t.check(Collision.new().bloqueia(r1, -2000, 0, 2000, 0),
		"forma 1: atravessar pelo meio cruza as diagonais")
	t.check(not Collision.new().bloqueia(r1, -2000, -1500, 2000, -1500),
		"forma 1: passar por fora não bloqueia")
	t.check(not Collision.new().bloqueia(r1, -990, -990, -900, -900),
		"forma 1: raspar o canto NÃO bloqueia — é a aproximação do próprio jogo")

	# ── forma 6: L de duas arestas, canto por `bits & 0x30` ──
	var cantos := {}
	for c in 4:
		var r6 := _rect(-1000, -1000, 1000, 1000, 6)
		r6.bits = 0xFE00 | (c << 4) | 6
		var segs := r6.segmentos()
		t.eq(segs.size(), 2, "forma 6 canto %d: 2 arestas" % c)
		cantos[str(segs)] = true
	t.eq(cantos.size(), 4, "os 4 valores de `bits & 0x30` dão 4 Ls DIFERENTES")

	# ── formas 9/10: arestas mascaráveis por `mask` bits 8..11 ──
	t.eq(_rect(0, 0, 100, 100, 9, 0x0F00).segmentos().size(), 4, "forma 9 com 4 bits: 4 arestas")
	t.eq(_rect(0, 0, 100, 100, 9, 0x0100).segmentos().size(), 1, "forma 9 com 1 bit: 1 aresta")
	t.eq(_rect(0, 0, 100, 100, 9, 0x0000).segmentos().size(), 0, "forma 9 sem bits: nada")

	# ── formas 8/11/12: `return 0` no EXE ──
	for f in [8, 11, 12]:
		t.eq(_rect(-1000, -1000, 1000, 1000, f).segmentos().size(), 0,
			"forma %d não tem segmento (return 0)" % f)

	# ── forma 4: LOSANGO (resposta `0x8004bb4c`) ──
	# Tabela `0x8009dfec` lida do EXE: forma 4 → `0x8004bb4c`, que classifica o ponto em quadrante
	# e testa `dx/hx + dz/hz < 1` (o losango), empurrando na PERPENDICULAR da aresta. Antes eu
	# respondia forma 4 como "linhas médias" e a área do losango ficava ANDÁVEL — era o buraco de
	# colisão do R10D (registro 32, forma 4, cobrindo onde a Jill nasce).
	var cl := Collision.new()
	## máscara SEM `0x1000` (esse bit é "collider girado 45°" e mudaria a geometria do teste)
	var r4 := _rect(-1000, -1000, 1000, 1000, 4, 0x0FFF)
	cl.rects.append(r4)
	var res4: Collision.Resolvido = cl.resolver(0, -2000, 0, -900, 0, 200, 200)
	t.check(res4.empurrado, "forma 4: entrar pelo topo do losango empurra")
	t.check(res4.z <= -900, "forma 4: o empurrão é para FORA (z não avança)")
	var canto: Collision.Resolvido = cl.resolver(1100, 1100, 900, 900, 0, 200, 200)
	t.check(not canto.empurrado,
		"forma 4: a QUINA da caixa fica livre — é losango, não caixa cheia")
	# entrada RASA pela ponta esquerda do losango (hx = hz = 1200 com o raio 200)
	var meio: Collision.Resolvido = cl.resolver(-2000, 0, -1150, 0, 0, 200, 200)
	t.check(meio.empurrado and meio.x < -1150, "forma 4: pela ponta empurra de volta")
	# a mordida diagonal empurra nos DOIS eixos (`sw` em +0x08 e +0x10 do EXE)
	var diag: Collision.Resolvido = cl.resolver(-900, -900, -400, -400, 0, 200, 200)
	t.check(diag.empurrado and diag.x < -400 and diag.z < -400,
		"forma 4: na diagonal corrige x E z (projeção perpendicular)")
	# a QUINA da caixa está FORA do losango (700/1200 + 700/1200 > 1), então não responde
	t.check(not cl.resolver(-1200, -1200, -700, -700, 0, 200, 200).empurrado,
		"forma 4: dx/hx + dz/hz > 1 é fora — a quina não empurra")
	# passo que exigiria mais de 400 de correção é REJEITADO (`slti 0x191` do EXE)
	var fundo: Collision.Resolvido = cl.resolver(-2000, 0, -100, 0, 0, 200, 200)
	t.check(fundo.rejeitado, "forma 4: correção > 400 rejeita o passo em vez de teleportar")

	# ── formas 2 e 3: CÁPSULA (respostas `0x8004c57c` e `0x8004c6ec`) ──
	# As duas são DESPACHANTES: classificam o ponto pelo eixo LONGO em 4 códigos e delegam para
	# `0x8004c960` (caixa cheia, faixa do meio) ou `0x8004c408` (círculo de raio h nas pontas),
	# com h = meio span TRANSVERSAL. Antes o port respondia "só a linha média" — uma parede de 1
	# unidade — e o volume inteiro do móvel ficava andável: 484 registros forma 2 + 373 forma 3.
	# Geometria deste caso: h = (500-(-500))/2 = 500, lo = f0+h = -1500, hi = f2-h = 1500;
	# pontas em (-1500,0) e (1500,0), alcance h+raio = 700.
	var cl2 := Collision.new()
	cl2.rects.append(_rect(-2000, -500, 2000, 500, 2, 0x0FFF))
	var p2a: Collision.Resolvido = cl2.resolver(2150, 0, 2150, 0, 0, 200, 200)
	t.check(p2a.empurrado and p2a.x == 2200 and p2a.z == 0 and not p2a.rejeitado,
		"forma 2: a PONTA empurra radialmente (2150,0) -> 2200 = f2+raio")
	t.check(not cl2.resolver(2150, 650, 2150, 650, 0, 200, 200).empurrado,
		"forma 2: a QUINA da caixa inflada fica livre — a ponta é CÍRCULO, não caixa")
	var p2d: Collision.Resolvido = cl2.resolver(1924, 424, 1924, 424, 0, 200, 200)
	t.check(p2d.empurrado and p2d.x - 1924 == 72 and p2d.z - 424 == 72,
		"forma 2: na diagonal da ponta corrige x E z ((dx±8)·pen/d em cada eixo)")
	t.check(cl2.resolver(2199, 0, 2199, 0, 0, 200, 200).empurrado,
		"forma 2: a ponta alcança exatamente f2+raio (2199 ainda empurra)")
	# ESTE é o buraco que a mudança fecha: o modelo antigo (linha média ±raio) deixava passar
	# tudo com |z| > 200; a faixa do meio é CAIXA CHEIA, então o volume inteiro bloqueia.
	t.check(cl2.resolver(0, 400, 0, 400, 0, 200, 200).empurrado,
		"forma 2: dentro do VOLUME (0,400) empurra — o modelo 'linha média' deixava andar")
	var p2p: Collision.Resolvido = cl2.resolver(0, -1200, 0, -600, 0, 200, 200)
	t.check(p2p.empurrado and p2p.z == -701 and not p2p.rejeitado,
		"forma 2: a faixa do meio clampa na face inflada (z = f1-raio-1), como `0x8004c960`")
	# limite de 400 (`0x8004cc68`, o teto do caso-DENTRO): partir de dentro rejeita o passo
	t.check(cl2.resolver(0, 0, 100, 0, 0, 200, 200).rejeitado,
		"forma 2: fuga > 400 no caso-dentro REJEITA o passo (`slti 0x191` de `0x8004cc68`)")

	# forma 3 = espelho exato (eixo longo em Z, h do span de X)
	var cl3 := Collision.new()
	cl3.rects.append(_rect(-500, -2000, 500, 2000, 3, 0x0FFF))
	var p3a: Collision.Resolvido = cl3.resolver(0, 2150, 0, 2150, 0, 200, 200)
	t.check(p3a.empurrado and p3a.z == 2200 and p3a.x == 0,
		"forma 3: a PONTA em +Z empurra radialmente (z -> f3+raio)")
	t.check(not cl3.resolver(650, 2150, 650, 2150, 0, 200, 200).empurrado,
		"forma 3: a quina da caixa inflada fica livre")
	var p3d: Collision.Resolvido = cl3.resolver(424, 1924, 424, 1924, 0, 200, 200)
	t.check(p3d.empurrado and p3d.x - 424 == 72 and p3d.z - 1924 == 72,
		"forma 3: na diagonal da ponta corrige x E z")
	t.check(cl3.resolver(400, 0, 400, 0, 0, 200, 200).empurrado,
		"forma 3: dentro do VOLUME (400,0) empurra")

	# A resposta RADIAL não tem teto: NÃO existe `slti 0x191` em `0x8004c408`..`0x8004c578`.
	# Aqui a ponta tem raio 4000 e o empurrão sai com 4698 un — e o passo NÃO é rejeitado.
	var clr := Collision.new()
	clr.rects.append(_rect(-5000, -4000, 5000, 4000, 2, 0x0FFF))
	var pr: Collision.Resolvido = clr.resolver(1100, 0, 1100, 0, 0, 450, 450)
	t.check(pr.empurrado and not pr.rejeitado and pr.x - 1100 == 4698 and pr.z == -348,
		"radial `0x8004c408` não tem teto de rejeição (empurra 4698 un sem acender 0x100)")

	# Quirk provado: se o span TRANSVERSAL for maior que o longo, lo > hi e a faixa do meio some.
	# O EXE cai no código 1 e sai por `0x8004c628` SEM empurrar, devolvendo v0 = 1 (o `sltiu` de
	# `0x8004c614`). Nenhum dos 857 registros forma 2/3 das 169 salas está nesse caso.
	var clq := Collision.new()
	clq.rects.append(_rect(-500, -2000, 500, 2000, 2, 0x0FFF))
	var pq: Collision.Resolvido = clq.resolver(0, 0, 0, 0, 0, 450, 450)
	t.check(pq.empurrado and pq.x == 0 and pq.z == 0,
		"forma 2 degenerada (span Z > span X): código 1 responde mas NÃO move")

	# ── forma 5: a tabela diz `0x8004c960`, a MESMA de 1/7/8 = caixa cheia ──
	var cl5 := Collision.new()
	cl5.rects.append(_rect(-1000, -1000, 1000, 1000, 5, 0x0FFF))
	t.check(cl5.resolver(0, -2000, 0, -900, 0, 200, 200).empurrado,
		"forma 5 empurra como caixa (eu tratava como 'sem resposta')")

	# ── forma 0: círculo inscrito ──
	var r0 := _rect(-500, -500, 500, 500, 0)
	t.eq(r0.raio(), 500, "raio do círculo = metade da largura")
	t.eq(r0.centro(), Vector2i(0, 0), "centro do círculo = centro da caixa")
	var c := Collision.new()
	t.check(c.bloqueia(r0, -2000, 0, 2000, 0), "círculo: atravessar pelo centro bloqueia")
	t.check(not c.bloqueia(r0, -2000, -1500, 2000, -1500), "círculo: passar longe não bloqueia")
	t.check(c.bloqueia(r0, -2000, 0, 0, 0), "círculo: parar dentro bloqueia")

	# ── filtro de altura (`lb +0x0c` × -1800 = base, `lh +0x0e` = topo) ──
	# O collider vale para o nível em que `topo <= y <= base_y`. É esse filtro que desliga o
	# mobiliário do térreo quando o personagem está numa passarela, e vice-versa.
	var col := Collision.new()
	var baixo := _rect(-1000, -1000, 1000, 1000, 1)      ## térreo: base 0, topo -1800
	col.rects.append(baixo)
	var alto := _rect(-1000, 2000, 1000, 4000, 1)
	alto.base_y = -3600                                   ## passarela: de -3600 a -5400
	alto.topo = -5400
	col.rects.append(alto)
	t.check(not col.trajeto_livre(-2000, 0, 2000, 0, 0), "no térreo o collider do térreo barra")
	t.check(col.trajeto_livre(-2000, 3000, 2000, 3000, 0),
		"no térreo o collider da passarela não existe")
	t.check(not col.trajeto_livre(-2000, 3000, 2000, 3000, -3600),
		"em -3600 o collider da passarela barra")
	t.check(col.trajeto_livre(-2000, 0, 2000, 0, -3600),
		"em -3600 o collider do térreo (topo -1800) está desligado")

	# ── filtro 1: máscara do chamador (`bits & 0x40` para o movimento do player) ──
	var col2 := Collision.new()
	var desligado := _rect(-1000, -1000, 1000, 1000, 1)
	desligado.bits = 0xDE01                               ## sem o bit 0x40 (visto no dado real)
	col2.rects.append(desligado)
	t.check(col2.trajeto_livre(-2000, 0, 2000, 0, 0),
		"collider sem o bit 0x40 não barra o player (é o estado que o script liga)")

	# ── quadrante: 2 centros, bits 0..3 e 4..7 ──
	var c1 := Vector2i(0, 0)
	var c2 := Vector2i(1000, 1000)
	t.eq(Collision.quadrante(-10, -10, c1, c1), 0x08 | 0x80,
		"canto (menor x, menor z) com centros iguais: bit 3 nos dois nibbles")
	t.check(Collision.quadrante(500, 500, c1, c2) != Collision.quadrante(-500, -500, c1, c2),
		"quadrantes diferentes dão códigos diferentes")

	# ── R100: comportamento de jogo ──
	var room := RoomData.load_room("R100")
	t.check(room.colisao != null, "R100 tem bloco de colisão")
	# andando 40 ticks em cada direção a partir da chegada, ela SEMPRE se move e SEMPRE para
	# dentro da sala (o modelo antigo travava na chegada ou vazava para fora do cenário)
	var chegada := Vector3i(-20400, 0, -20790)
	for dir_i in 4:
		var w := World.new()
		t.check(w.carregar("R100"), "R100 carrega")
		w.player.pos = chegada
		w.player.facing = dir_i * 1024
		var pad := Pad.new()
		for _i in 40:
			pad.set_mask(Pad.FWD)
			w.tick(pad)
		var d := Vector2(float(w.player.pos.x - chegada.x), float(w.player.pos.z - chegada.z))
		# Em +X a face INFLADA da parede leste (f0 - raio 450) fica a só ~146 un da chegada —
		# por isso o limite é 100, não 500. O que importa é: mexeu (não travou) e parou dentro.
		t.check(d.length() > 100.0, "facing %d: andou (não travou na chegada)"
			% (dir_i * 1024))
		t.check(absi(w.player.pos.x) < 32000 and absi(w.player.pos.z) < 32000,
			"facing %d: terminou dentro do espaço da sala" % (dir_i * 1024))

	# ── INVARIANTE: toda chegada de porta consegue dar o primeiro passo ──
	# Era 51% com o modelo de caixa cheia; com o modelo do motor tem de ser 100%.
	# ESCOPO DECLARADO: aqui só as portas dos stages 1 e 2 (é o que a suíte aguenta em tempo —
	# carregar as 169 salas leva ~3 min por causa do `_col.json` com as máscaras). O varrido
	# COMPLETO das 453 chegadas está em `dev/diag_col.gd`, que roda sob demanda.
	var salas := _salas().filter(func(s: String) -> bool: return s[1] == "1" or s[1] == "2")
	var total := 0
	var presos: Array[String] = []
	var cache := {}
	for sala: String in salas:
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
				if dest.colisao == null:
					continue
				cache[d.to_room_id] = dest
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
	t.check(total > 100, "mediu mais de 100 chegadas nos stages 1-2 (mediu %d)" % total)
	t.check(presos.is_empty(), "toda chegada dá o primeiro passo (%d presas: %s)"
		% [presos.size(), ", ".join(presos.slice(0, 5))])
	print("    [colisão] %d chegadas medidas, %d presas" % [total, presos.size()])

	# ── INVARIANTE de jogo das cápsulas: o VOLUME do móvel bloqueia ──
	# Ponto de prova por registro: no eixo longo o centro da caixa, no transversal a 3/4 do span —
	# isto é, a `span/4` da linha média. Nos registros com span transversal > 4×raio esse ponto
	# está FORA da faixa que o modelo antigo ("só a linha média, ±raio") cobria, então ele mede
	# exatamente o entulho que não tinha colisão. Com a cápsula tem de ser 100%.
	var largos := 0
	var vazando: Array[String] = []
	for sala: String in cache.keys():
		var r: RoomData = cache[sala]
		if r == null or r.colisao == null:
			continue
		var col_s: Collision = r.colisao
		for i in col_s.rects.size():
			var rc: Collision.Rect = col_s.rects[i]
			if rc.forma != 2 and rc.forma != 3:
				continue
			if (rc.bits & Collision.MASCARA_RESOLVER) == 0:
				continue
			var transv := (rc.f3 - rc.f1) if rc.forma == 2 else (rc.f2 - rc.f0)
			if transv <= 4 * Collision.RAIO_ATOR:
				continue                                   # a linha média já cobria: não mede nada
			largos += 1
			var px := rc.f0 + (rc.f2 - rc.f0) / 2
			var pz := rc.f1 + (rc.f3 - rc.f1) / 2
			if rc.forma == 2:
				pz = rc.f1 + transv * 3 / 4
			else:
				px = rc.f0 + transv * 3 / 4
			var q := Vector2i(px, pz)
			if (rc.mask & Collision.BIT_ROTACIONADO) != 0:
				q = Collision.girar_para_mundo(px, pz, rc)  # o ponto vive no mundo, não no rect
			var so := Collision.new()                      # 1 registro só: isola a forma
			so.centro1 = col_s.centro1
			so.centro2 = col_s.centro2
			so.rects.append(rc)
			if not so.resolver(q.x, q.y, q.x, q.y, rc.base_y / -Collision.ALTURA_POR_NIVEL).empurrado:
				vazando.append("%s#%d forma%d" % [sala, i, rc.forma])
	t.check(largos > 50, "mediu mais de 50 registros forma 2/3 largos (mediu %d)" % largos)
	t.check(vazando.is_empty(), "todo volume de cápsula bloqueia (%d vazando: %s)"
		% [vazando.size(), ", ".join(vazando.slice(0, 6))])
	print("    [colisão] %d registros forma 2/3 largos, %d vazando" % [largos, vazando.size()])
	return true


func _salas() -> Array[String]:
	var out: Array[String] = []
	for s in range(1, 8):
		var dir := DirAccess.open("res://data/STAGE%d" % s)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.length() == 9 and f.ends_with(".json") and f.begins_with("R"):
				out.append(f.substr(0, 4))
	out.sort()
	return out
