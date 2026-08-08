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
