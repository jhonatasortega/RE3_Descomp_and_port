extends RefCounted
## SUBIR EM OBJETO (rotina 9 do player) + o EVENTO do R10D decodificado.
##
## Dois blocos, com propósitos diferentes:
##
## 1. **O AOT do R10D é um `evt_exec` para a função 11 — e NÃO é o "subir".** Isso precisa de
##    teste porque foi a hipótese de partida da tarefa: o único AOT da sala é `sce 5`
##    (SCE_EVENT, handler `0x800512bc`), cujo payload é `{u16 slot, _, 0x19, u8 func}`. Se
##    alguém mudar o parser do payload, o número da função muda em silêncio e a decodificação
##    do evento (registrada em `docs/decomp/notes/menu_bau.md`) deixa de valer.
## 2. **A máquina da rotina 9**: 6 quadros de contato para acender a flag (`0x800365c8`), a
##    entrada só por r1/r2 (`0x800397c0`), e as sequências **6** e **7** (`0x8003b39c` /
##    `0x8003b3c4`). É o que garante que o estado não entra sozinho (bug clássico: subir ao
##    encostar de lado) e não sai antes da animação.


func run(t: Object) -> bool:
	t.group("subir")

	# ───────────── 1. o AOT do R10D: sce 5 = evt_exec(func 11) ─────────────
	var vm := ScriptVM.new()
	t.check(vm.carregar_sala("R10D"), "R10D carrega")
	t.eq(vm.func_offsets.size(), 49, "o R10D.scd tem 49 funções")
	vm.modo = ScriptVM.Modo.EXECUCAO
	vm.state = GameState.new()
	# So a MONTAGEM da sala (funcoes 0..10). A funcao 11 e a propria cena, e a 1a coisa que ela
	# faz e `65 01` = **aot_reset do AOT 1** (offset 0x0624): a cena APAGA o gatilho que a
	# chamou -- e o que faz o evento acontecer UMA vez. Rodar as 49 funcoes em bloco (como o
	# test_aot faz) deixaria o AOT desativado e esconderia o gatilho.
	for fi in 11:
		vm.executar(fi)
	var eventos := vm.aots_de_sce(Aot.SCE_EVENTO)
	t.eq(eventos.size(), 1, "o R10D tem exatamente 1 AOT de evento")
	if eventos.is_empty():
		return true
	var ev: Aot = eventos[0]
	t.eq(ev.id, 1, "aot id 1")
	t.eq(ev.sce, 5, "sce 5 = SCE_EVENT (handler 0x800512bc)")
	t.eq(ev.sat, 0x41, "SAT 0x41 = automático na posição do CORPO (sem bit de ação)")
	t.check(not ev.exige_acao(), "não exige o botão de ação (sat & 0x10 apagado)")
	t.check(ev.usa_corpo(), "testa a posição do corpo (sat & 0x40)")
	t.check(not ev.usa_sonda(), "não usa o ponto de sonda")
	t.eq(ev.box, Rect2i(-8585, -15000, 3300, 3700), "a caixa do evento (bytes do SCD)")
	t.eq(Array(ev.payload), [255, 0, 25, 11, 0, 0], "payload cru = os 6 bytes de opcode+0x0e")
	t.eq(ev.evento_slot(), 255, "u16@+0 = 255 (0xff) = qualquer slot de thread livre")
	t.eq(ev.evento_func(), 11, "u8@+3 = 11 -> a thread roda a FUNÇÃO 11 do R10D.scd")
	t.check(ev.evento_func() < vm.func_offsets.size(), "a função 11 existe na tabela")

	# A captura do dono (x=-3678, z=-12960) está FORA da caixa do evento: o AOT não é o gatilho
	# do subir. É o fato que motivou toda a investigação — fica travado em teste.
	var captura := Vector3i(-3678, 0, -12960)
	t.check(not ev.contem(captura.x, captura.z),
		"a posição da captura NÃO está na caixa do evento (o AOT não é o 'subir')")
	t.check(captura.x > ev.box.position.x + ev.box.size.x,
		"a captura está a LESTE da caixa do evento")

	# A função 11 é uma CENA: tem gosub (0x19), yield (0x0a), som (0x55) e câmera (0x46), e
	# NENHUM opcode de animação de player (0x74/0x75/0x76) — o "subir" não sai daqui.
	var ops := _opcodes_da_funcao(vm, 11)
	t.check(ops.has(0x19), "func 11 tem gosub (0x19) — é uma cena com sub-rotinas")
	t.check(ops.has(0x0A), "func 11 tem yield (0x0a)")
	t.check(ops.has(0x55) or ops.has(0x56), "func 11 dispara som (0x55/0x56)")
	t.check(ops.has(0x46), "func 11 mexe na câmera (0x46)")
	t.check(not ops.has(0x74) and not ops.has(0x75) and not ops.has(0x76),
		"func 11 NÃO tem gatilho de animação (0x74/0x75/0x76)")
	t.check(ops.has(0x01), "func 11 termina em evt_end (0x01)")
	t.check(ops.has(0x65), "func 11 tem aot_reset (0x65) — ela apaga o próprio gatilho")
	# e o efeito real: rodar a função 11 desativa o AOT 1 (é o `65 01` em 0x0624)
	vm.executar(11)
	t.check(not ev.ativo, "depois da cena, o AOT do evento está DESATIVADO (dispara uma só vez)")
	t.eq(vm.aots_de_sce(Aot.SCE_EVENTO).size(), 0, "e não sobra evento ativo na sala")

	# ───────────── 2. os números provados da rotina 9 ─────────────
	t.eq(SubirObjeto.SEQ_SUBIR, 6, "seq 6 = subir (sw 0x00070006 em 0x8003b39c)")
	t.eq(SubirObjeto.SEQ_TOPO, 7, "seq 7 = topo (sw 0x00070007 em 0x8003b3c4)")
	t.eq(SubirObjeto.ROTINA_SUBIR, 9, "player+5 = 9 (rotina subir/descer)")
	t.eq(SubirObjeto.ACTION_ROUTINE_R9, 0x901, "player+4 = 0x901 (ação 1 | rotina 9)")
	t.eq(SubirObjeto.FRAMES_CONTATO, 6, "6 quadros de contato (sltiu $v0,$v0,6 em 0x800365c8)")
	t.eq(SubirObjeto.FLAG_SUBIR, 0x10, "bit 0x10 de 0x800d1f2c (aceso só em 0x800365fc)")
	t.eq(SubirObjeto.ROTINAS_VALIDAS, [1, 9] as Array[int],
		"a contagem só vive nas rotinas 1 e 9 (0x80036c88..9c)")
	t.eq(SubirObjeto.CLIPES[6], "anim06", "seq 6 -> clipe anim06 do PL00.glb")
	t.eq(SubirObjeto.CLIPES[7], "anim07", "seq 7 -> clipe anim07")

	# ───────── 2b. QUAL objeto é escalável: a porta ESTÁTICA de `be_flg` ─────────
	# `entry+0 = u16@+0x0c | 1` do opcode `0x7f` (`0x800565cc..0x800565d8`), e o agregador
	# `0x80036570` reprova quem tem o bit `0x4000` aceso (`0x8003659c`) ou o bit `0x100` apagado
	# (`0x800365a4`). Como os dois bits são dado do SCD, a lista de objetos escaláveis do jogo é
	# uma varredura — e é isso que este bloco trava, porque é o resultado que DERRUBA a hipótese
	# da "lixeira do R10D".
	t.eq(ObjetoSala.BE_ESCALAVEL, 0x100, "bit 0x100 exigido (0x800365a4 beqz)")
	t.eq(ObjetoSala.BE_NAO_ESCALAVEL, 0x4000, "bit 0x4000 proíbe (0x8003659c bnez)")
	var r10d_om := vm.objetos
	t.eq(r10d_om.size(), 3, "o R10D tem 3 objetos 0x7f")
	var r10d_escalaveis := 0
	for k in r10d_om:
		var o: ObjetoSala = r10d_om[k]
		t.eq(o.be_flg, 0x6001, "om %d do R10D tem be_flg 0x6001" % o.slot)
		if o.escalavel():
			r10d_escalaveis += 1
	t.eq(r10d_escalaveis, 0,
		"NENHUM objeto do R10D é escalável (0x6001 = bit 0x4000 aceso e 0x100 apagado)")

	# a varredura do jogo inteiro: 4 salas sobrevivem à montagem completa (R406 declara o objeto
	# escalável em UM ramo da função 17 e o reescreve com be_flg 0x0001 no fim, por isso não entra)
	var salas_com_ponto: Array[String] = []
	var por_sala: Dictionary = {}
	for id in _listar_salas():
		var v2 := ScriptVM.new()
		if not v2.carregar_sala(id):
			continue
		v2.modo = ScriptVM.Modo.EXECUCAO
		v2.state = GameState.new()
		for fi in v2.func_offsets.size():
			v2.executar(fi)
		var n := 0
		for k in v2.objetos:
			if (v2.objetos[k] as ObjetoSala).escalavel():
				n += 1
		if n > 0:
			salas_com_ponto.append(id)
			por_sala[id] = n
	t.eq(salas_com_ponto, ["R210", "R219", "R315", "R50D"] as Array[String],
		"as salas com objeto escalável do jogo")
	t.eq(por_sala, {"R210": 1, "R219": 1, "R315": 1, "R50D": 3},
		"quantos objetos escaláveis por sala")
	t.check(not salas_com_ponto.has("R10D"), "e o R10D NÃO está entre elas")

	# ───────────── 3. detector: 6 quadros, de frente, andando ─────────────
	var s := SubirObjeto.new()
	t.eq(s.carregar_sala("R10D"), 0, "R10D não instala nenhum ponto (não invento a lixeira)")
	t.eq(s.carregar_sala("R100"), 0, "R100 também não")
	t.eq(s.carregar_sala("R50D"), 3, "R50D instala 3 pontos (om 0/1/2, be_flg 0x0101)")
	t.eq(s.carregar_sala("R315"), 1, "R315 instala 1 ponto (om 7)")
	# e o ponto sai da POSIÇÃO do objeto, com raio declarado
	var p315: Dictionary = s.pontos[0]
	t.eq(p315["caixa"], Rect2i(-27589 - SubirObjeto.RAIO_DECLARADO,
		-23328 - SubirObjeto.RAIO_DECLARADO,
		SubirObjeto.RAIO_DECLARADO * 2, SubirObjeto.RAIO_DECLARADO * 2),
		"a caixa é o raio declarado em torno da posição do om")
	t.eq(p315["y_topo"], -SubirObjeto.ALTURA_DECLARADA,
		"e o topo é a altura declarada acima do Y do om (Y negativo = para cima)")

	# ponto sintético: caixa 1000×1000 na origem, o ator ao sul dela olhando ao norte
	s = SubirObjeto.new()
	s.adicionar_ponto(Rect2i(-500, -500, 1000, 1000), -3600, "teste")
	var pos := Vector3i(0, 0, 620)               ## sonda com facing 0 cai em z = 0
	t.eq(ScriptVM.sonda_de(pos, 0), Vector2i(0, 0), "a sonda de 620 cai no centro da caixa")
	t.check(s.ponto_em_frente(pos, 2048).is_empty(),
		"de costas (facing 2048) a sonda não acha o ponto")
	t.check(not s.ponto_em_frente(pos, 0).is_empty(), "de frente a sonda acha o ponto")

	# 5 quadros NÃO acendem; o 6º acende
	for i in 5:
		t.check(not s.detectar(pos, 0, 1, true), "quadro %d de contato ainda não acende" % (i + 1))
	t.check(s.detectar(pos, 0, 1, true), "o 6º quadro acende a flag")
	t.check(s.deve_entrar(1), "com a flag acesa, r1 (andar frente) entra na rotina 9")
	t.check(s.deve_entrar(2), "r2 (ré) também entra (0x80039b68)")
	t.check(not s.deve_entrar(0), "idle NÃO entra")
	t.check(not s.deve_entrar(3), "correr NÃO entra")
	t.check(not s.deve_entrar(7), "mirar NÃO entra")

	# soltar o movimento zera a contagem (o contato deixa de existir)
	t.check(not s.detectar(pos, 0, 1, false), "sem pedir movimento a flag apaga")
	t.eq(s.contato, 0, "e a contagem zera")
	# rotina inválida zera a contagem (0x80036ca0)
	for i in 5:
		s.detectar(pos, 0, 1, true)
	t.eq(s.contato, 5, "5 quadros acumulados")
	s.detectar(pos, 0, 3, true)
	t.eq(s.contato, 0, "entrar em CORRER (rotina 3) zera a contagem")
	# de costas nunca acende, nem com 20 quadros
	for i in 20:
		s.detectar(pos, 2048, 1, true)
	t.check(not s.flag, "de costas não acende nunca")

	# ───────────── 4. a máquina de subestados: 6 -> 7 -> volta ─────────────
	s = SubirObjeto.new()
	s.adicionar_ponto(Rect2i(-500, -500, 1000, 1000), -3600, "teste")
	for i in SubirObjeto.FRAMES_CONTATO:
		s.detectar(pos, 0, 1, true)
	t.check(s.flag, "flag acesa antes de iniciar")
	s.iniciar()
	t.check(s.ativo, "a rotina 9 está ativa")
	t.eq(s.sub, SubirObjeto.Sub.ENTRA, "começa no subestado 0")
	t.eq(s.clipe(), "", "no subestado 0/1 o clipe é o de ANDAR (não uma seq própria)")
	var vistos: Array[String] = []
	var impacto := 0
	var guard := 0
	while s.ativo and guard < 200:
		s.avancar(false)                         ## não segura direção: a máquina progride
		var c := s.clipe()
		if c != "" and not vistos.has(c):
			vistos.append(c)
		if s.sfx_pendente == SubirObjeto.SFX_IMPACTO:
			impacto += 1
		guard += 1
	t.check(guard < 200, "a máquina termina (não trava)", "%d quadros" % guard)
	t.eq(vistos, ["anim06", "anim07"] as Array[String],
		"a ordem dos clipes é anim06 (subir) e depois anim07 (topo)")
	t.eq(impacto, 1, "o SFX de impacto toca uma vez (sub 5, 0x8003b3e8)")
	t.eq(s.sub, SubirObjeto.Sub.SAI, "termina no subestado 7 (volta para on-foot)")
	t.check(not s.ativo, "e a rotina se desliga (player+4 = 1 em 0x8003b4e0)")

	# segurar a direção com a flag acesa PRENDE no topo (o `move` só avança quando solta)
	s = SubirObjeto.new()
	s.adicionar_ponto(Rect2i(-500, -500, 1000, 1000), -3600, "teste")
	for i in SubirObjeto.FRAMES_CONTATO:
		s.detectar(pos, 0, 1, true)
	s.iniciar()
	for i in 80:
		s.avancar(true)                          ## segurando, e a flag continua acesa
		s.flag = true
	t.eq(s.sub, SubirObjeto.Sub.NO_TOPO, "segurando a direção, fica no topo (0x8003b1cc..e8)")
	t.check(s.ativo, "e a rotina continua ativa")
	for i in 10:
		s.avancar(false)
	t.check(s.sub == SubirObjeto.Sub.TERMINANDO or s.sub == SubirObjeto.Sub.SAI
		or not s.ativo, "ao soltar, ela avança", SubirObjeto.Sub.keys()[s.sub])
	t.eq(s.y_destino(), -3600, "o destino em Y é o `topo` do ponto")

	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % st)
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.ends_with(".scd"):
				saida.append(nome.trim_suffix(".scd"))
	saida.sort()
	return saida


func _opcodes_da_funcao(vm: ScriptVM, fi: int) -> Dictionary:
	## Varredura linear pela tabela de tamanhos da VM (a mesma que fecha 4238/4238 funções).
	var saida: Dictionary = {}
	if fi < 0 or fi >= vm.func_offsets.size():
		return saida
	var ini := vm.func_offsets[fi]
	var fim := vm.func_offsets[fi + 1] if fi + 1 < vm.func_offsets.size() else vm.bytes.size()
	var i := ini
	while i < fim:
		var op := vm.u8(i)
		var sz := ScriptVM.size_of(op)
		if sz <= 0:
			break
		saida[op] = int(saida.get(op, 0)) + 1
		i += sz
	return saida
