extends RefCounted
## AS DUAS CINEMÁTICAS DO R10D (`port/script_vm/cena.gd`) e os opcodes de VM que elas exigiram.
##
## Cada número aqui foi lido do bytecode de `R10D.ARD` ou do handler citado no EXE
## (`SLUS_009.23`, jump-table `0x8009e0f8`). Detalhe em `docs/decomp/notes/cena_r10d.md`.
##
##     godot --headless --path port --script res://dev/run_tests.gd -- cena

const SALA := "R10D"
const FUNC_ENTRADA := 7
const FUNC_SAIDA := 11


func _sala() -> ScriptVM:
	## Sala carregada e INICIADA: `executar(0)` é o que `world.gd` faz e é o que instala os
	## AOTs (func 3 = porta, func 5 = evento) e os 3 objetos (func 4).
	var vm := ScriptVM.new()
	if not vm.carregar_sala(SALA):
		return null
	vm.state = GameState.new()
	vm.modo = ScriptVM.Modo.EXECUCAO
	vm.executar(0)
	return vm


func _cena(func_id: int) -> Cena:
	var vm := _sala()
	if vm == null:
		return null
	var c := Cena.new()
	c.iniciar(vm, func_id, vm.state)
	# A Jill no spawn medido da abertura (`boot_ptbr_hd.md` §6.1).
	c.por_ator(1, 0, Vector3i(9404, 0, -13317), 0)
	c.rodar(4000)
	return c


func run(t) -> bool:
	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("1. a sala instala DUAS coisas: a porta roteirizada e o gatilho da cena")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var vm := _sala()
	if not t.check(vm != null, "R10D carrega"):
		return false
	t.eq(vm.func_offsets.size(), 49, "R10D tem 49 funções de script")
	t.eq(vm.aots.size(), 2, "R10D tem exatamente 2 AOTs")
	t.eq(vm.objetos.size(), 3, "R10D tem 3 objetos 0x7f")

	var porta: Aot = vm.aots.get(0)
	if t.check(porta != null, "AOT 0 existe"):
		t.eq(porta.sce, 1, "AOT 0 é PORTA (sce 1)")
		t.eq(porta.opcode, 0x61, "declarada por 0x61 (32 B)")
		# Caixa (0,0,0,0): o jogador NÃO pode tocá-la — é disparada pelo script (0x66).
		t.eq(porta.box, Rect2i(0, 0, 0, 0), "caixa da porta é DEGENERADA (0,0,0,0)")
		t.eq(porta.to_stage, 0, "destino: exe-stage 0")
		t.eq(porta.to_room, 1, "destino: índice interno 1")
		t.eq(porta.to_room_id(), "R101", "destino: R101")
		t.eq(porta.to_pos, Vector3i(0, 0, 0), "chegada ZERADA no dado (ver doc §5)")

	var evento: Aot = vm.aots.get(1)
	if t.check(evento != null, "AOT 1 existe"):
		t.eq(evento.sce, 5, "AOT 1 é EVENTO (sce 5, handler 0x800512bc)")
		t.eq(evento.opcode, 0x63, "declarado por 0x63 (20 B)")
		t.eq(evento.box, Rect2i(-8585, -15000, 3300, 3700), "caixa do gatilho de saída")
		# payload = o descritor de `evt_exec`: slot 0xff (qualquer livre) e FUNÇÃO 11.
		t.eq(evento.payload.size(), 6, "payload de 6 bytes")
		t.eq(evento.payload[0], 0xFF, "payload: slot 0xff = qualquer thread livre")
		t.eq(evento.payload[3], FUNC_SAIDA, "payload: função 11 = a cena de SAÍDA")

	# A cena de ENTRADA é aberta pela própria func 5, com `04 ff 19 07`.
	var f5: int = vm.func_offsets[5]
	t.eq(vm.u8(f5), 0x04, "func 5 começa com evt_exec (0x04)")
	t.eq(vm.u8(f5 + 1), 0xFF, "evt_exec: slot 0xff")
	t.eq(vm.u8(f5 + 3), FUNC_ENTRADA, "evt_exec: função 7 = a cena de ENTRADA")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("2. cena de ENTRADA = função 7 (thread aberta no init da sala)")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var e := _cena(FUNC_ENTRADA)
	if t.check(e != null, "a cena de entrada roda"):
		t.eq(e.cameras(), [11, 12, 10, 10, 0] as Array[int],
			"cut_chg: 11 -> 12 -> 10 -> 10 -> 0 (opcode 0x50, handler 0x800548c8)")
		var cams := e.eventos_de("camera")
		# Os intervalos são os `09 | 0a 3c 00` = sleep 60 do bytecode (handlers 0x8005304c /
		# 0x80053094): 0x3c = 60 quadros entre a câmera 11, a 12 e a 10.
		t.eq(int(cams[1]["quadro"]) - int(cams[0]["quadro"]), 60, "11 -> 12: sleep 0x3c = 60")
		t.eq(int(cams[2]["quadro"]) - int(cams[1]["quadro"]), 60, "12 -> 10: sleep 0x3c = 60")
		t.eq(e.camera, 0, "a cena termina na CÂMERA 0 — a mesma em que o port já nasce")
		# O clarão: func 40 (thread) faz fade ADITIVO preto->branco em 4 ticks e branco->preto
		# em 16. É o relâmpago da rua (opcode 0x46, handler 0x80054384 -> 0x8002a35c).
		var fades := e.eventos_de("fade")
		t.eq(fades.size(), 2, "a entrada tem 2 fades (o relâmpago da func 40)")
		if fades.size() == 2:
			t.eq(int(fades[0]["abr"]), 1, "1º fade: abr=1 (fundo + primitiva = clareia)")
			t.eq(int(fades[0]["c0"]), 0x000000, "1º fade: de preto")
			t.eq(int(fades[0]["c1"]), 0xFFFFFF, "1º fade: para branco")
			t.eq(int(fades[0]["T"]), 4, "1º fade: 4 ticks")
			t.eq(int(fades[1]["c0"]), 0xFFFFFF, "2º fade: de branco")
			t.eq(int(fades[1]["c1"]), 0x000000, "2º fade: para preto")
			t.eq(int(fades[1]["T"]), 16, "2º fade: 16 ticks")
		t.eq(e.seqs(), [20, 5] as Array[int], "animações da entrada: SEQ 20 e SEQ 5 (func 8)")
		t.eq(e.quadro_atual, 260, "a cena de entrada dura 260 quadros de script")
		t.check(e.troca_de_sala.is_empty(), "a entrada NÃO troca de sala")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("3. cena de SAÍDA = função 11, e é ela que tira a Jill da sala (opcode 0x66)")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var s := _cena(FUNC_SAIDA)
	if t.check(s != null, "a cena de saída roda"):
		t.eq(s.cameras(), [4, 5, 4, 6, 7, 8, 9] as Array[int],
			"cut_chg: 4 -> 5 -> 4 -> 6 -> 7 -> 8 -> 9")
		# O FIM da função 11, byte a byte:
		#   46 00 00 02 00 00 00 ff ff ff 30   fade abr=2 preto->branco, T=0x30 = 48
		#   09 / 0a 30 00                      espera 48 quadros
		#   47 01 00 / 40 1f 00 00 / 40 26 c8 00
		#   66 00                              sce_aot_exec(0) = a PORTA
		var fades := s.eventos_de("fade")
		t.eq(fades.size(), 1, "a saída tem UM fade")
		if fades.size() == 1:
			t.eq(int(fades[0]["abr"]), 2, "fade final: abr=2 (fundo - primitiva = escurece)")
			t.eq(int(fades[0]["c1"]), 0xFFFFFF, "fade final: rampa até branco subtrativo")
			t.eq(int(fades[0]["T"]), 48, "fade final: 0x30 = 48 ticks")
		var portas := s.eventos_de("porta")
		t.eq(portas.size(), 1, "a saída dispara UMA porta")
		if portas.size() == 1 and fades.size() == 1:
			t.eq(int(portas[0]["quadro"]) - int(fades[0]["quadro"]), 48,
				"a porta é disparada 48 quadros depois do fade (o `0a 30 00`)")
			t.eq(int(portas[0]["stage"]), 0, "porta: exe-stage 0")
			t.eq(int(portas[0]["room"]), 1, "porta: sala 1 = R101")
			t.eq(int(portas[0]["aot"]), 0, "porta: é o AOT 0, o de caixa degenerada")
			t.eq(int(portas[0]["sce"]), 1, "porta: sce 1 = produtor 0x80050d28")
			t.check(bool(portas[0]["chegada_zerada"]),
				"a chegada vem ZERADA (item aberto: precisa do grupo do RVD)")
		t.check(not s.troca_de_sala.is_empty(), "a cena de saída PEDE troca de sala")
		t.eq(str(s.troca_de_sala.get("room", -1)), "1", "pedido de troca: sala 1")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("4. o SUBIR do R10D é coreografia da cena, não a rotina 9")
	# ═══════════════════════════════════════════════════════════════════════════════════
	if s != null:
		var seqs := s.seqs()
		# `19 0e` gosub 14 -> `80 00 08 00` = SEQ 8 ; `19 0f` gosub 15 -> `80 00 07 00` = SEQ 7.
		# E a thread 17 faz SEQ 4 -> SEQ 9 -> SEQ 5 -> SEQ 6.
		t.eq(seqs[0], 8, "1ª animação da saída: SEQ 8 (func 14, `80 00 08 00`)")
		t.eq(seqs[1], 7, "2ª animação da saída: SEQ 7 (func 15, `80 00 07 00`)")
		t.check(seqs.has(SubirObjeto.SEQ_SUBIR),
			"a cena toca a SEQ %d — a MESMA que a rotina 9 usa para subir" % SubirObjeto.SEQ_SUBIR)
		t.check(seqs.has(SubirObjeto.SEQ_TOPO),
			"a cena toca a SEQ %d — a MESMA que a rotina 9 usa no topo" % SubirObjeto.SEQ_TOPO)
		# A ação é a 4 (roteirizada): `0x80056dc0` grava `w+4 = (rotina << 8) | 4`.
		var anims := s.eventos_de("anim")
		t.check(anims.size() > 0, "há animações roteirizadas")
		# E a subida em si é MANUAL: a thread 17 soma 70 em X e 40 em Z por 10 quadros
		# (`42 10 09` / `20 00 00 10 46 00` / `41 09 10`), mais 10 quadros de +5 em X.
		var subiu := false
		for ev: Dictionary in s.eventos_de("chegou"):
			if int(ev["bit"]) == 0:
				subiu = true
		t.check(subiu, "o `0x81` da thread 17 chega ao destino e acende o bit 0 do banco 4")

		# E a conclusão negativa de `subir.gd` CONTINUA valendo — as duas convivem.
		var su := SubirObjeto.new()
		t.eq(su.carregar_sala(SALA), 0,
			"nenhum objeto 0x7f do R10D é escalável (be_flg 0x6001) — segue verdade")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("5. opcode 0x66 = sce_aot_exec — o mecanismo de porta ROTEIRIZADA")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# As 6 portas mão-única que `door_handler.md` rotulou "box ZERO (scripted/cutscene)" são
	# EXATAMENTE as disparadas por `0x66`. Aqui a checagem roda dentro do port: em cada sala,
	# todo `0x66` aponta para um AOT declarado, e nas 6 o AOT é `sce 1`.
	var esperado := {"R10D": 0, "R215": 3, "R30D": 0, "R50D": 1, "R50F": 0, "R510": 1}
	for sala: String in esperado:
		var v := ScriptVM.new()
		if not t.check(v.carregar_sala(sala), "%s carrega" % sala):
			continue
		v.state = GameState.new()
		v.modo = ScriptVM.Modo.EXECUCAO
		for fi in v.func_offsets.size():
			v.executar(fi)
		var ids := _ids_de_66(v)
		var alvo: int = esperado[sala]
		t.check(ids.has(alvo), "%s tem 0x66 apontando para o AOT %d" % [sala, alvo],
			"ids vistos: %s" % [ids])
		var a: Aot = v.aots.get(alvo)
		if t.check(a != null, "%s: AOT %d foi declarado" % [sala, alvo]):
			t.check(a.sce == 1 or a.sce == 13,
				"%s: o AOT %d disparado por 0x66 é PORTA (sce %d)" % [sala, alvo, a.sce])
			# NÃO exijo caixa degenerada: em `R215` e `R510` a MESMA porta tem caixa de
			# verdade E é disparada pelo script (uso duplo). Zeradas são R10D/R30D/R50D/R50F.
			if sala in ["R10D", "R30D", "R50D", "R50F"]:
				t.eq(a.box.size, Vector2i(0, 0),
					"%s: caixa degenerada — SÓ o script dispara essa porta" % sala)

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("6. as tabelas de membro/aritmética saíram do EXE, não de suposição")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# `member_set` = 0x80010950 e `member_get` = 0x80010a00, 43 entradas cada
	# (`sltiu $a1, 0x2b` nos dois despachos). 6 delas são globais, 37 são campos.
	t.eq(ScriptVM.MEMBROS.size() + ScriptVM.MEMBROS_GLOBAIS.size(), 43,
		"43 membros (0x2b) entre campos e globais")
	t.eq(ScriptVM.MEMBROS[0x09], [0x34, 4] as Array, "membro 0x09 = X (`sw 0x34`)")
	t.eq(ScriptVM.MEMBROS[0x0A], [0x38, 4] as Array, "membro 0x0a = Y (`sw 0x38`)")
	t.eq(ScriptVM.MEMBROS[0x0B], [0x3C, 4] as Array, "membro 0x0b = Z (`sw 0x3c`)")
	t.eq(ScriptVM.MEMBROS[0x0D], [0x6E, -2] as Array, "membro 0x0d = ângulo (`sh 0x6e`/`lh`)")
	t.eq(ScriptVM.MEMBROS[0x1F], [0x12D, 1] as Array, "membro 0x1f = +0x12d (`sb`)")
	t.eq(ScriptVM.MEMBROS[0x26], [0xCC, -2] as Array, "membro 0x26 = +0xcc (HP)")
	t.check(not ScriptVM.MEMBROS.has(0x20), "0x20..0x25 NÃO são campos de entidade")
	t.eq(ScriptVM.MEMBROS_GLOBAIS[0x20], 0x800E0154, "membro 0x20 = global 0x800e0154")

	# O fim da cena de saída também MEXE em dois membros do player, e os dois estão medidos:
	#   `40 1f 00 00`  -> player+0x12d = 0    (o mesmo campo do gate de colisão do subir)
	#   `40 26 c8 00`  -> player+0xcc  = 200  (HP: `char+0xcc -= dano`, exe_combat.md)
	if s != null:
		var campos: Dictionary = s._ator(1, 0)["campos"]
		t.eq(int(campos.get(0x12D, -1)), 0, "no fim da cena: player+0x12d = 0")
		t.eq(int(campos.get(0xCC, -1)), 200, "no fim da cena: player+0xcc = 200 (HP)")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("7. modo CENA não mexe nos modos antigos")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var l := ScriptVM.new()
	l.carregar_sala(SALA)
	l.modo = ScriptVM.Modo.LINEAR
	var todas_ok := true
	for fi in l.func_offsets.size():
		if l.executar(fi) != ScriptVM.Status.FIM:
			todas_ok = false
	t.check(todas_ok, "as 49 funções do R10D ainda fecham em modo LINEAR")
	var x := ScriptVM.new()
	x.carregar_sala(SALA)
	x.state = GameState.new()
	x.modo = ScriptVM.Modo.EXECUCAO
	t.eq(x.executar(0), ScriptVM.Status.FIM, "func 0 ainda fecha em modo EXECUÇÃO")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("8. o caminho de verdade: pisar na caixa -> cena -> porta")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var v2 := _sala()
	# Um ponto DENTRO da caixa do gatilho (-8585..-5285 em x, -15000..-11300 em z).
	t.check(Cena.gatilho_de_evento(v2, -7000, -13000) != null,
		"pisar em (-7000,-13000) acha o gatilho sce 5")
	t.check(Cena.gatilho_de_evento(v2, 9404, -13317) == null,
		"o spawn da abertura (9404,-13317) está FORA do gatilho")
	var g := Cena.gatilho_de_evento(v2, -7000, -13000)
	t.eq(g.evento_func(), FUNC_SAIDA, "o gatilho pede a função 11")
	t.eq(g.evento_slot(), 255, "o gatilho pede slot 0xff (qualquer livre)")
	var c2 := Cena.abrir_evento(v2, g, v2.state, Vector3i(-7000, 0, -13000), 0)
	if t.check(c2 != null, "abrir_evento monta a cena"):
		c2.rodar(4000)
		var p := c2.porta_pedida()
		if t.check(p != null, "a cena entrega o Aot da porta para world.atravessar()"):
			t.eq(p.to_room_id(), "R101", "e essa porta leva a R101")
	return true


func _ids_de_66(v: ScriptVM) -> Array[int]:
	## Varredura linear pelos tamanhos da tabela: junta os ids de todo `0x66` da sala.
	var saida: Array[int] = []
	for fi in v.func_offsets.size():
		var pc: int = v.func_offsets[fi]
		var fim: int = v.func_offsets[fi + 1] if fi + 1 < v.func_offsets.size() else v.bytes.size()
		var guarda := 0
		while pc < fim and guarda < 20000:
			guarda += 1
			var op := v.u8(pc)
			if not ScriptVM.opcode_valido(op):
				break
			if op == 0x66 and not saida.has(v.u8(pc + 1)):
				saida.append(v.u8(pc + 1))
			if op == 0x01:
				break
			pc += ScriptVM.size_of(op)
	return saida
