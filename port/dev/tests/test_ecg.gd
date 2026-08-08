extends RefCounted
## ECG do painel de condição da tela de status (`port/present/ecg.gd`).
##
## O que este teste protege: cada número de `Ecg` saiu de um endereço do `SLUS_009.23` e está
## citado no comentário da constante. Os asserts abaixo travam justamente o que foi PROVADO:
##
##  * a tabela de forma de onda (`0x800a0cbc`+) tem 80 pares e a linha de base é 15;
##  * a onda inteira cabe no buraco TRANSPARENTE do painel B1 medido no `STMAIN0U.TIM`
##    (x∈[76,148] y∈[39,66]) — se alguém mexer em `X_ORIGEM`/`Y_ORIGEM` isso quebra;
##  * o guarda `k < 0x4a` de `0x8006c550`/`0x8006c558` (janela que entra pela esquerda e sai
##    pela direita, e 8 quadros de painel vazio no fim do ciclo);
##  * o gradiente do rastro de `0x8006c560` (cabeça = cor cheia, cauda ≈ preta);
##  * o ciclo de 113 quadros de `0x8006e31c`..`0x8006e338`;
##  * o flash da cura de `0x80067910`/`0x8006c4e8`: 28 colunas de altura cheia, `fase += 3`,
##    e o encerramento em `fase >= 0x51` de `0x80067934`.

const PERIODO := 113                       ## fase de -32 a 80, `0x8006e334` + `0x8006e32c`


func run(t: Object) -> bool:
	t.group("ECG / tabelas")
	# ── as 5 tabelas de onda (0x800a0cbc, 0d5c, 0dfc, 0e9c, 0f3c), 160 B = 80 pares ──
	t.eq(Ecg.ONDA_HEX.size(), 5, "5 tabelas de onda (POISON e VIRUS compartilham a 5ª)")
	t.eq(Ecg.ONDA_ENDERECO.size(), 6, "6 ponteiros em 0x800a0174 (um por condição)")
	t.eq(Ecg.ONDA_ENDERECO[4], Ecg.ONDA_ENDERECO[5],
		"POISON e VIRUS apontam para a mesma onda (0x800a0f3c)")
	t.eq(Ecg.COR.size(), 6, "6 linhas de cor em 0x800a0150")
	for i in 5:
		var w := Ecg.onda(i)
		t.eq(w.size(), 160, "onda %d tem 160 bytes (80 pares)" % i)
		t.eq(int(w[0]), 15, "onda %d começa na linha de base y=15" % i)
		t.eq(int(w[1]), 0, "onda %d começa com altura 0 (1 px)" % i)
		t.eq(int(w[(Ecg.K_LIMITE - 1) * 2]), 15,
			"onda %d termina na linha de base na última coluna alcançável (k=73)" % i)

	# ── a onda inteira cabe no interior TRANSPARENTE do painel B1 ──
	t.group("ECG / geometria")
	t.eq(Ecg.AREA, Rect2i(76, 39, 73, 28), "interior do gráfico medido no atlas: 73×28 em (76,39)")
	t.eq(Ecg.GRADE_N * Ecg.GRADE_PASSO - Ecg.GRADE_PASSO + 1, Ecg.AREA.size.y,
		"10 linhas de grade de 3 em 3 preenchem as 28 linhas do interior")
	var ymin := 999
	var ymax := -999
	for i in 5:
		var w := Ecg.onda(i)
		for k in Ecg.K_LIMITE:
			var y0 := Ecg.Y_ORIGEM + int(w[k * 2])
			var y1 := y0 + int(w[k * 2 + 1])
			ymin = mini(ymin, y0)
			ymax = maxi(ymax, y1)
	t.eq(ymin, 41, "o pico mais alto das 5 ondas fica em y=41 (37 + 4)")
	t.eq(ymax, 64, "o vale mais fundo fica em y=64 (37 + 27)")
	t.check(ymin >= Ecg.AREA.position.y and ymax <= Ecg.AREA.end.y - 1,
		"as 5 ondas cabem inteiras no buraco transparente do painel")
	t.eq(Ecg.X_ORIGEM + Ecg.K_LIMITE - 1, 148,
		"a última coluna cai em x=148, a borda direita do interior")
	t.eq(Ecg.Y_ORIGEM + 15, 52, "a linha de base (y=15) cai em 52, o meio do gráfico")

	# ── o flash usa exatamente a altura do interior ──
	t.eq(Ecg.FLASH_Y0, Ecg.AREA.position.y, "flash: topo = topo do interior (39)")
	t.eq(Ecg.FLASH_Y1, Ecg.AREA.end.y - 1, "flash: base = última linha de grade (66)")

	# ── a janela deslizante e o guarda k < 0x4a ──
	t.group("ECG / janela")
	var e := Ecg.new()
	e.reiniciar()
	t.eq(e.fase, 0, "init: fase = 0 (0x8006db78)")
	t.eq(e.n_colunas(), 32, "32 colunas fora do flash (0x8006c4e4)")
	t.eq(e.segmentos(0).size(), 32, "fase 0 desenha as 32 colunas")
	e.fase = Ecg.FASE_INICIO
	t.eq(e.segmentos(0).size(), 0, "fase -32: nada visível (a janela ainda está fora à esquerda)")
	e.fase = -31
	t.eq(e.segmentos(0).size(), 1, "fase -31: entra a primeira coluna")
	t.eq(int(e.segmentos(0)[0]["x"]), 75, "e ela é x=75 (k=0)")
	e.fase = 42
	t.eq(e.segmentos(0).size(), 32, "fase 42: última em que as 32 colunas cabem (42+31 = 73)")
	e.fase = 43
	t.eq(e.segmentos(0).size(), 31, "fase 43: a cabeça já saiu pela direita")
	e.fase = 73
	t.eq(e.segmentos(0).size(), 1, "fase 73: só a cauda ainda dentro")
	t.eq(int(e.segmentos(0)[0]["x"]), 148, "e ela é x=148 (k=73)")
	e.fase = 74
	t.eq(e.segmentos(0).size(), 0, "fase 74: painel vazio até o fim do ciclo")
	var vazios := 0
	for f in range(Ecg.FASE_INICIO, Ecg.FASE_FIM):
		e.fase = f
		if e.segmentos(0).is_empty():
			vazios += 1
	t.eq(vazios, 8, "8 dos 113 quadros do ciclo têm o painel vazio (fase -32 e 74..80)")

	# ── gradiente do rastro (0x8006c560): cabeça cheia, cauda quase preta ──
	t.group("ECG / cor")
	e.fase = 0
	var segs := e.segmentos(0)
	var cabeca: Color = segs[segs.size() - 1]["cor"]
	var cauda: Color = segs[0]["cor"]
	t.eq(cabeca, Color8(32, 255, 32), "FINE: a cabeça (i = n-1) usa a cor cheia de 0x800a0150")
	t.eq(cauda, Color8(1, 7, 1), "FINE: a cauda (i = 0) é base - delta*31 = (1,7,1)")
	e.fase = 0
	var segs3 := e.segmentos(3)
	t.eq(Color(segs3[segs3.size() - 1]["cor"]), Color8(255, 32, 32),
		"DANGER: cabeça vermelha (255,32,32)")
	# nenhum canal estoura o u8 em nenhuma condição (é o que faz o `sb` do EXE ficar exato)
	for cond in 6:
		var c: Array = Ecg.COR[cond]
		for canal in 3:
			t.check(int(c[canal]) - int(c[canal + 3]) * (Ecg.N_COLUNAS - 1) >= 0,
				"cond %d canal %d: base - delta*31 não fica negativo" % [cond, canal])
	t.eq(Ecg.ALFA_SEMITRANS, 0.5, "code 0x42 + tpage 0x9b (abr=0) = 50% fundo + 50% frente")

	# ── cadência: 113 quadros por ciclo, 2 quadros por tick de 30 Hz ──
	t.group("ECG / cadência")
	t.eq(Ecg.QUADROS_POR_TICK, 2, "menu do PS1 a 60 Hz / port a 30 Hz = 2 quadros por tick")
	var e2 := Ecg.new()
	e2.fase = Ecg.FASE_INICIO
	var passos := 0
	while true:
		e2._quadro()
		passos += 1
		if e2.fase == Ecg.FASE_INICIO or passos > 500:
			break
	t.eq(passos, PERIODO, "o ciclo normal fecha em 113 quadros (-32..80)")
	t.near(float(PERIODO) / 60.0, 1.883, 0.01, "113 quadros a 60 Hz ≈ 1,88 s")
	var e3 := Ecg.new()
	e3.fase = 0
	e3.avancar()
	t.eq(e3.fase, 2, "um tick de 30 Hz anda 2 quadros")

	# ── a onda como POLIGONAL (o desenho em resolução de tela) ──
	t.group("ECG / poligonal")
	t.eq(Ecg.valores(0).size(), 80, "a poligonal tem um vértice por par da tabela (80)")
	t.eq(int(Ecg.valores(0)[0]), 15, "o primeiro vértice é a linha de base 15")
	t.eq(int(Ecg.valores(0)[Ecg.K_LIMITE - 1]), 15, "e a última coluna alcançável volta para 15")
	t.eq(Ecg.valores_da_condicao(4), Ecg.valores_da_condicao(5),
		"POISON e VIRUS compartilham a poligonal (mesma tabela 0x800a0f3c)")
	## REPROJEÇÃO: o segmento entre dois vértices tem de cobrir o span `(y0, y0+h)` do EXE. Nas
	## 370 colunas alcançáveis, 298 batem exato; o resto erra 1 px (69) ou 2 px (3) porque as
	## tabelas do jogo misturam duas convenções de `h` (ver o comentário de `Ecg.valores`).
	## Este teste TRAVA esses números: se alguém mexer na regra de reconstrução, ele acusa.
	var exatas := 0
	var erro1 := 0
	var pior := 0
	var vmin := 999
	var vmax := -999
	for i in 5:
		var w2 := Ecg.onda(i)
		var v2 := Ecg.valores(i)
		for k in Ecg.K_LIMITE:
			var y0b := int(w2[k * 2])
			var y1b := y0b + int(w2[k * 2 + 1])
			var a := int(v2[k - 1]) if k > 0 else int(w2[0])
			var b := int(v2[k])
			var d := maxi(absi(mini(a, b) - y0b), absi(maxi(a, b) - y1b))
			if d == 0:
				exatas += 1
			elif d == 1:
				erro1 += 1
			pior = maxi(pior, d)
			vmin = mini(vmin, b)
			vmax = maxi(vmax, b)
	t.eq(exatas + erro1 + 3, 370, "370 colunas alcançáveis (5 tabelas × 74)")
	t.eq(exatas, 298, "298 colunas reprojetam o span do EXE byte a byte")
	t.eq(erro1, 69, "69 erram 1 px (o `h` da descida de 1 px do dado original)")
	t.eq(pior, 2, "e o pior caso é 2 px, nunca mais")
	t.eq(Ecg.Y_ORIGEM + vmin, 41, "a poligonal tem o mesmo topo dos spans (y=41)")
	t.eq(Ecg.Y_ORIGEM + vmax, 64, "e o mesmo fundo (y=64) — segue dentro do painel")
	var ep := Ecg.new()
	ep.fase = 0
	t.eq(ep.pontos(0).size(), 32, "fase 0: 32 vértices, um por coluna visível")
	t.eq(Vector2(ep.pontos(0)[0]["p"]).x, 75.0, "o primeiro vértice cai em x=75 (k=0)")
	t.eq(Color(ep.pontos(0)[31]["cor"]), Color8(32, 255, 32),
		"a cabeça da poligonal usa a cor cheia, como em `segmentos`")
	ep.fase = -31
	t.eq(ep.pontos(0).size(), 1, "fase -31: um vértice só (sem segmento a desenhar)")
	ep.fase = Ecg.FASE_INICIO
	t.eq(ep.pontos(0).size(), 0, "fase -32: nenhum vértice, igual a `segmentos`")
	for f2 in range(Ecg.FASE_INICIO, Ecg.FASE_FIM):
		ep.fase = f2
		t.check(ep.pontos(0).size() == ep.segmentos(0).size(),
			"fase %d: a janela da poligonal é a mesma dos spans" % f2)
	t.eq(Ecg.ESPESSURA_SD, 1.0, "espessura = 1 px de 320×240 = 4 px de tela (proporcional)")

	# ── flash da cura ──
	t.group("ECG / flash da cura")
	var e4 := Ecg.new()
	e4.flash()
	t.check(e4.em_flash, "flash() liga o bit 0x800000 (0x80067910)")
	t.eq(e4.fase, Ecg.FASE_INICIO, "e reinicia a fase em -32")
	t.eq(e4.n_colunas(), 28, "no flash são 28 colunas (0x8006c4e8)")
	e4.fase = 0
	var fs := e4.segmentos(0)
	t.eq(fs.size(), 28, "as 28 colunas do flash aparecem em fase 0")
	t.eq(int(fs[0]["y0"]), 39, "flash: y0 = 39 em toda coluna (0x8006c5ec)")
	t.eq(int(fs[0]["y1"]), 66, "flash: y1 = 66 em toda coluna (0x8006c5f8)")
	t.eq(int(fs[0]["x"]), 75, "flash: a coluna k=0 também é x=75")
	var e5 := Ecg.new()
	e5.flash()
	var q := 0
	while e5.em_flash and q < 200:
		e5._quadro()
		q += 1
	## -32 + 3k >= 81 -> k = 38 quadros ainda em flash; o 39º é o quadro em que o handler
	## `0x80067934` encerra (fase = -32, bit limpo) e o tick `0x8006e31c` já soma o +1 normal,
	## porque na task o handler roda ANTES do tick (`0x8006e044` e depois `0x8006e04c`).
	t.eq(q, 39, "o flash dura 39 quadros (38 de varredura + o quadro que encerra)")
	t.near(float(q) / 60.0, 0.65, 0.01, "39 quadros a 60 Hz ≈ 0,65 s")
	t.eq(e5.fase, Ecg.FASE_INICIO + Ecg.PASSO,
		"ao encerrar, fase = -32 (0x8006797c) + o +1 do tick do mesmo quadro")
	t.check(not e5.em_flash, "e limpa o bit (0x8006796c)")
	return true
