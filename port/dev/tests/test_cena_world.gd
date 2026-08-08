extends RefCounted
## AS CENAS DO R10D **LIGADAS NO JOGO** — o engate de `cena.gd` no `world.gd`/`player.gd`.
##
## `test_cena.gd` prova as duas cinemáticas dentro da `Cena` (108 asserts). Este arquivo prova a
## outra metade: que elas rodam pelo caminho do JOGO — `World.tick(pad)` — e que é assim que a
## Jill finalmente **sai da primeira sala**, que era o problema relatado ("não consigo sair da
## primeira sala"). Receita em `docs/decomp/notes/cena_r10d.md` §6.1 (player) e §6.2 (world).
##
##     godot --headless --audio-driver Dummy --path port \
##         --script res://dev/run_tests.gd -- cena

const SALA := "R10D"
const FUNC_ENTRADA := 7
const FUNC_SAIDA := 11
## Spawn medido da abertura (`boot_ptbr_hd.md` §6.1) — o mesmo que `screen.gd` usa.
const SPAWN := Vector3i(9404, 0, -13317)
## Um ponto DENTRO da caixa do gatilho `sce 5` (x[-8585..-5285] z[-15000..-11300]).
const NO_GATILHO := Vector3i(-7000, 0, -13000)


func _mundo() -> World:
	var w := World.new()
	if not w.carregar(SALA):
		return null
	w.player.pos = SPAWN                     ## é o que o `screen.gd` faz depois de carregar
	w.player.facing = 0
	return w


func run(t) -> bool:
	var pad := Pad.new()
	pad.set_mask(0)

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("1. a cena de ENTRADA roda no load da sala e devolve o controle na câmera 0")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var w := _mundo()
	if not t.check(w != null, "R10D carrega no mundo"):
		return false
	if not t.check(w.cena != null, "carregar(R10D) abre a cinemática de entrada"):
		return false
	t.eq(w.cena_func, FUNC_ENTRADA, "e a cena de entrada é a FUNÇÃO 7 (thread do init)")
	t.eq(w.player.acao, Player.Acao.CENA, "o player entra no estado CENA (ação 4)")
	t.check(w.player.em_cena(), "player.em_cena() = true")

	var cams: Array[int] = []
	var seqs: Array[int] = []
	var quadros := 0
	var passo_entrada := 0                   ## quadros com o passo manual do script
	while w.cena != null and quadros < 1000:
		var antes_cam := w.camera
		var antes_seq := w.player.cena_seq
		var antes_pos := w.player.pos
		pad.set_mask(0)
		w.tick(pad)
		quadros += 1
		if w.camera != antes_cam:
			cams.append(w.camera)
		if w.player.cena_seq != antes_seq and w.player.cena_seq >= 0:
			seqs.append(w.player.cena_seq)
		var d := w.player.pos - antes_pos
		if d.x == 22 and d.z == -98:
			passo_entrada += 1
	t.check(quadros < 1000, "a cena de entrada TERMINA (não prende o jogador)",
		"%d quadros" % quadros)
	t.eq(cams, [11, 12, 10, 0] as Array[int],
		"as câmeras da entrada chegam ao `world.camera`: 11 -> 12 -> 10 -> 0")
	t.eq(w.camera, 0, "controle devolvido na CÂMERA 0 — a mesma em que o port nasce")
	t.eq(w.rvd.camera, 0, "e o RVD retoma dessa câmera")
	t.eq(w.player.acao, Player.Acao.PARADO, "o player sai do estado CENA (`player+4 = 1`)")
	t.check(not w.player.em_cena(), "player.em_cena() = false depois da cena")
	t.eq(quadros, 260, "a entrada dura os mesmos 260 quadros que o bytecode mede")
	t.eq(w.trocas, 0, "a entrada não troca de sala")
	# ── A entrada MOVE a Jill, e é o script que a move ──
	# A thread da função 8 escreve `player+0x34 += 22` e `player+0x3c -= 98` por 20 quadros
	# (a partir do quadro 128, junto com a SEQ 20). É translação MANUAL, igual à da subida.
	t.eq(passo_entrada, 20, "20 quadros de passo manual (+22 em X, -98 em Z) do script")
	# A posição FINAL não se cobra em número fechado: o `SPAWN` é ponto DECLARADO do port (não é
	# de onde o jogo começa a cena), e no quadro em que a cena morre o tick normal já roda um
	# `_mover(0,0)` — o desencrave do resolver. O que se cobra é que o corpo tenha andado e que
	# ele seja legal (a asserção de input abaixo).
	t.check(w.player.pos != SPAWN, "a cena ANDA com o corpo (quem move é o script)",
		str(w.player.pos))
	# ⚠ ACHADO DO ENGATE: no quadro 218 a entrada manda um `0x81` para o player com destino
	# **(0,0)** (rotina 6). O port NÃO anda até lá — ver a nota em
	# `Player._consumir_eventos_da_cena` — e registra a dívida.
	t.check(", ".join(w.cena_debitos).contains("destino (0,0)"),
		"a dívida do `0x81` com destino (0,0) está registrada",
		", ".join(w.cena_debitos))

	# --- e o pad volta a valer (é o "devolve o controle") ---
	var antes := w.player.pos
	for _i in 20:
		pad.set_mask(Pad.FWD)
		w.tick(pad)
	t.check(w.player.pos != antes, "depois da cena o PAD volta a mover o personagem",
		"de %s para %s" % [antes, w.player.pos])

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("2. pisar na caixa do AOT sce 5 abre a cena de SAÍDA e ela troca para R101")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var w2 := _mundo()
	# passa a cena de entrada (ela não tem gatilho e roda sozinha)
	while w2.cena != null:
		pad.set_mask(0)
		w2.tick(pad)
	t.eq(w2.room.room_id, SALA, "ainda em R10D depois da entrada")

	# agora pisa na caixa do gatilho
	w2.player.pos = NO_GATILHO
	pad.set_mask(0)
	w2.tick(pad)
	if not t.check(w2.cena != null, "pisar em %s abre a cena de saída" % NO_GATILHO):
		return false
	t.eq(w2.cena_func, FUNC_SAIDA, "e a cena de saída é a FUNÇÃO 11")

	var seqs2: Array[int] = []
	var cams2: Array[int] = []
	var q2 := 0
	var passo_manual := 0          ## quadros com o `+70` em X e `+40` em Z (a SUBIDA)
	var passo_curto := 0           ## quadros com o `+5` em X (o segundo `for` da thread 17)
	var chegou_bit0 := false
	while w2.room.room_id == SALA and q2 < 3000:
		var a_seq := w2.player.cena_seq
		var a_cam := w2.camera
		var a_pos := w2.player.pos
		pad.set_mask(0)
		w2.tick(pad)
		q2 += 1
		if w2.cena != null:
			if w2.player.cena_seq != a_seq and w2.player.cena_seq >= 0:
				seqs2.append(w2.player.cena_seq)
			if w2.camera != a_cam:
				cams2.append(w2.camera)
			var d := w2.player.pos - a_pos
			if d.x == 70 and d.z == 40:
				passo_manual += 1
			elif d.x == 5 and d.z == 0:
				passo_curto += 1
			if w2.state.flag_get(Cena.BANCO_RASCUNHO, 0):
				chegou_bit0 = true
	t.check(q2 < 3000, "a cena de saída termina", "%d quadros" % q2)
	t.eq(w2.room.room_id, "R101", "★ a cena TROCOU DE SALA: R10D -> R101 (opcode 0x66)")
	t.eq(w2.trocas, 1, "contou 1 troca de sala")
	t.check(w2.cena == null, "a cena foi fechada ao atravessar")
	t.check(not w2.player.em_cena(), "e o controle voltou para o jogador")
	t.eq(cams2, [4, 5, 4, 6, 7, 8, 9] as Array[int],
		"as câmeras da saída chegam ao `world.camera`: 4 -> 5 -> 4 -> 6 -> 7 -> 8 -> 9")
	# As sequências que a cena pede, na ordem (doc §6.1). ⚠ 8 e 10 são DECLARADAS: não estão no
	# par provado de `subir.gd` (6/7) e `animacoes_player.md` as rotula por render.
	t.eq(seqs2, [8, 7, 4, 9, 5, 6, 10] as Array[int],
		"o player consome as SEQ 8, 7, 4, 9, 5, 6 e 10 nessa ordem (`0x80` -> `player+0xc8`)")
	# ── O SUBIR NA LIXEIRA, medido pelo deslocamento do corpo no jogo ──
	# A thread 17 escreve `player+0x34 += 70` e `player+0x3c += 40` por 10 quadros
	# (`42 10 09` / `20 00 00 10 46 00` / `41 09 10`), e depois 10 quadros de `+5` em X. Como
	# nesses quadros o player não tem `0x81` pendente, o deslocamento é EXATAMENTE o do script.
	t.eq(passo_manual, 10, "a SUBIDA: 10 quadros de +70 em X e +40 em Z escritos pelo script")
	t.eq(passo_curto, 10, "e os 10 quadros de +5 em X que fecham o movimento")
	# O `0x81` + `chegou(bit)`: o bit 0 do BANCO 4 é o handshake que solta o `while (não flag)`.
	# (A troca de sala ZERA o banco 4, como o motor faz na carga — por isso se olha durante.)
	t.check(chegou_bit0,
		"o player acendeu o bit 0 do banco 4 ao chegar (o que solta a thread, §3.2)")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("3. a chegada é DECLARADA e a dívida fica registrada (não inventei coordenada)")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# A porta roteirizada tem chegada (0,0,0) no dado e (0,0,0) NÃO é ponto válido no R101 — o
	# mecanismo real (grupo do RVD, `descriptor+0xb`) não foi medido (`cena_r10d.md` §4.2).
	var deb := ", ".join(w2.cena_debitos)
	t.check(deb.contains("chegada ZERADA"), "a dívida da chegada zerada está registrada", deb)
	t.check(deb.contains("chegada DECLARADA em R101"),
		"e a chegada usada está etiquetada como DECLARADA/emprestada", deb)
	t.check(w2.player.pos != Vector3i.ZERO, "o corpo NÃO ficou em (0,0,0)",
		str(w2.player.pos))
	# O ponto emprestado é MEDIDO: é a chegada de outra porta que entra no R101 (R100 -> R101).
	var emp := World._chegada_emprestada("R101")
	t.check(not emp.is_empty(), "há de quem emprestar a chegada em R101")
	if not emp.is_empty():
		t.eq(str(emp["src"]), "R100", "a chegada emprestada vem da porta R100 -> R101")
		t.eq(emp["pos"], Vector3i(-18808, -7200, -11475),
			"e é o ponto MEDIDO daquela porta (data/room_graph.json)")
	# E o personagem consegue se mover na chegada (senão o jogo travaria do outro lado).
	var pos_ap := w2.player.pos
	for _i in 30:
		pad.set_mask(Pad.FWD)
		w2.tick(pad)
	t.check(w2.player.pos != pos_ap, "na chegada em R101 o personagem RESPONDE ao input",
		"de %s para %s" % [pos_ap, w2.player.pos])

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("4. as outras 134 caixas `sce 5` do jogo seguem INERTES (regressão)")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# Medido: 135 gatilhos `sce 5` em 58 salas. Só as duas funções do R10D estão medidas, então
	# só elas estão ligadas — as outras não podem abrir cena nenhuma (§7 do doc: há opcodes de
	# cena sem semântica; uma thread presa num `while` prenderia o jogador para sempre).
	t.eq(World.CENAS_LIGADAS.size(), 1, "uma única sala com cena ligada")
	t.check(World.CENAS_LIGADAS.has(SALA), "e é o R10D")
	var w3 := World.new()
	if t.check(w3.carregar("R102"), "R102 carrega (tem gatilho sce 5 na função 10)"):
		t.check(w3.cena == null, "R102 NÃO abre cinemática na carga")
		var g := Cena.gatilho_de_evento(w3.vm, -11500, -27600)
		if t.check(g != null, "e o gatilho sce 5 do R102 existe e contém o ponto"):
			w3.player.pos = Vector3i(-11500, 0, -27600)
			pad.set_mask(0)
			w3.tick(pad)
			t.check(w3.cena == null,
				"pisar nele NÃO abre cena (função %d não medida)" % g.evento_func())

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("6. o DEGRAU: subir e descer são AÇÕES DO JOGADOR, e é a descida que abre a cena")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# ⚠ Isto corrige a conclusão que se tirou de `subir.gd` §5. O que a Jill escala no R10D não é
	# objeto `0x7f` (nenhum é escalável, e MEDI que nada mexe no `be_flg` em runtime) — é a
	# GEOMETRIA DE COLISÃO: a plataforma de um nível `x[-6368..-4129] z[-15823..-10197]`
	# (`base_y=0 topo=-1800`) com os dois flancos `forma 8` no nível de cima. Ver
	# `World._degraus_da_sala()` e `cena_r10d.md` §10.
	var wd := _mundo()
	t.eq(wd.player.degraus.size(), 2, "R10D declara 2 degraus (a plataforma vem em 2 registros)")
	if wd.player.degraus.size() > 0:
		var g0: Dictionary = wd.player.degraus[0]
		t.eq(g0["caixa"], Rect2i(-6368, -15823, 2239, 5626), "a caixa do degrau é a medida")
		t.eq(int(g0["y_base"]), 0, "base do degrau: nível 0")
		t.eq(int(g0["y_topo"]), -1800, "topo do degrau: nível 1 (é o que o floor_height dá lá)")
	# ── A VIELA ESTÁ SELADA NO NÍVEL 0: sem o degrau, andar para oeste PARA na plataforma ──
	var wsem := _mundo()
	while wsem.cena != null:
		pad.set_mask(0)
		wsem.tick(pad)
	wsem.player.degraus = []                      ## desliga o degrau de propósito
	wsem.player.pos = Vector3i(9404, 0, -13317)
	wsem.player.facing = 3072                     ## oeste (facing 0 = -Z, logo -X = 3072)
	for _i in 400:
		pad.set_mask(Pad.FWD)
		wsem.tick(pad)
	t.check(wsem.player.pos.x > -6368,
		"SEM o degrau, andar para oeste esbarra na plataforma e a caixa fica inalcançável",
		str(wsem.player.pos))
	t.check(wsem.cena == null, "e por isso a cena de saída nunca dispara")
	# ── COM o degrau: do spawn, andando para oeste, ela sobe ──
	while wd.cena != null:
		pad.set_mask(0)
		wd.tick(pad)
	wd.player.pos = Vector3i(9404, 0, -13317)
	wd.player.facing = 3072
	var q_subiu := -1
	var clipes: Array[String] = []
	for i in 400:
		pad.set_mask(Pad.FWD)
		wd.tick(pad)
		if wd.player.acao == Player.Acao.SUBINDO:
			if q_subiu < 0:
				q_subiu = i
			var c := wd.player.clipe_atual()
			if not clipes.has(c):
				clipes.append(c)
		elif q_subiu >= 0:
			break
	t.check(q_subiu > 0, "do spawn, andando para OESTE ela chega ao degrau e SOBE",
		"quadro %d" % q_subiu)
	t.check(clipes.has("anim06") and clipes.has("anim07"),
		"a subida toca o par PROVADO SEQ 6 / SEQ 7 (`anim06`/`anim07`)", str(clipes))
	t.eq(wd.player.pos.y, -1800, "e termina no nível 1, em cima da plataforma",
		str(wd.player.pos))
	t.check(wd.player.pos.x < -4129 and wd.player.pos.x > -6368,
		"com o corpo DENTRO da caixa do degrau (em cima dela)", str(wd.player.pos))
	# ── e seguir para oeste em cima dela leva à cena de saída e a R101 ──
	var q2b := 0
	while wd.room.room_id == "R10D" and q2b < 1500:
		pad.set_mask(Pad.FWD)
		wd.tick(pad)
		q2b += 1
	t.eq(wd.room.room_id, "R101",
		"★ subir + seguir a oeste abre a cena de saída e leva a R101 — a sala tem saída A PÉ")

	# ── nFloor: a caixa NÃO vale em cima da plataforma; vale quando ela DESCE ──
	# O `+4` do `0x63` é o ANDAR EXIGIDO (`Aot.floor_id`; `0x80` = qualquer) e no R10D é **0**
	# (`63 01 05 41 00 00 …`). O port ignorava esse campo e a cena abria com a Jill ainda no
	# telhado do obstáculo (medido: disparava em x=-5300, y=-1800). É o que o dono descreve:
	# **é a DESCIDA que aciona**.
	var wnf := _mundo()
	var gnf := Cena.gatilho_de_evento(wnf.vm, -7000, -13000)
	if t.check(gnf != null, "o gatilho sce 5 do R10D existe"):
		t.eq(gnf.floor_id, 0, "nFloor do gatilho = 0 (só vale no nível 0)")
	while wnf.cena != null:
		pad.set_mask(0)
		wnf.tick(pad)
	# em cima da plataforma, DENTRO da caixa em x/z, mas no nível 1: não pode disparar
	wnf.player.pos = Vector3i(-5500, -1800, -13000)
	wnf.player.facing = 0
	pad.set_mask(0)
	wnf.tick(pad)
	t.check(wnf.cena == null,
		"em cima da plataforma (nível 1) a caixa NÃO dispara, mesmo com x/z dentro dela")
	# o mesmo x/z no nível 0: dispara
	wnf.player.pos = Vector3i(-5500, 0, -13000)
	pad.set_mask(0)
	wnf.tick(pad)
	t.check(wnf.cena != null, "no nível 0, o mesmo ponto dispara a cena de saída")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("7. a DESCIDA também é ação (mesmo par de animação), e o degrau é raro no jogo")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var wde := _mundo()
	while wde.cena != null:
		pad.set_mask(0)
		wde.tick(pad)
	# em cima da plataforma, olhando para LESTE (facing 1024): o flanco leste NÃO é a caixa do
	# gatilho (ela vai só até x = -5285), então dá para medir a descida isolada.
	wde.player.pos = Vector3i(-4500, -1800, -13000)
	wde.player.facing = 1024
	var desceu := false
	var clipes_d: Array[String] = []
	for _i in 200:
		pad.set_mask(Pad.FWD)
		wde.tick(pad)
		if wde.player.acao == Player.Acao.SUBINDO:
			desceu = true
			var cd := wde.player.clipe_atual()
			if not clipes_d.has(cd):
				clipes_d.append(cd)
		elif desceu:
			break
	t.check(desceu, "em cima da plataforma, andar para fora entra na rotina 9 (DESCER)")
	t.check(clipes_d.has("anim06") and clipes_d.has("anim07"),
		"a descida usa o MESMO par SEQ 6 / SEQ 7 (`subir.gd`: são subir E descer)", str(clipes_d))
	t.eq(wde.player.pos.y, 0, "e o corpo termina no nível 0", str(wde.player.pos))
	# A assinatura do degrau é RARA: 25 registros `forma 8` no jogo; a assinatura completa
	# (plataforma de 1 nível + `forma 8` encostado no nível de cima) dá 28 registros em 14 salas.
	# Entre elas R504 e R510 — e `R510 -> R504` é a porta "one_way_fall / spawn scripted".
	var esperado_deg := {"R10D": 2, "R504": 4, "R510": 1, "R100": 0, "R102": 0}
	for sala: String in esperado_deg:
		var wx := World.new()
		if not wx.carregar(sala):
			continue
		t.eq(wx.player.degraus.size(), int(esperado_deg[sala]),
			"%s: %d degrau(s)" % [sala, int(esperado_deg[sala])])

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("5. sala sem gatilho: o tick normal não mudou")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var w4 := World.new()
	if t.check(w4.carregar("R100"), "R100 carrega"):
		t.check(w4.cena == null, "R100 não tem cinemática ligada")
		var p0 := w4.player.pos
		for _i in 20:
			pad.set_mask(Pad.FWD)
			w4.tick(pad)
		t.check(w4.player.pos != p0 or w4.player.acao == Player.Acao.ANDANDO,
			"o andar normal continua funcionando")
	return true
