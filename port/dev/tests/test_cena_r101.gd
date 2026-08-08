extends RefCounted
## A CENA DE ENTRADA DO `R101` — o pedido do dono: *"no fim da cena final, ao ir para a próxima
## sala, tem uma cena de entrada"*.
##
## Cobre as três coisas que este round provou (`docs/decomp/notes/cena_r101.md`):
##   1. a cena é a **função 3**, e quem diz isso é o INIT (`vm.threads_pedidas`), não uma tabela;
##   2. o `0x4c` do `ScriptVM` estava com a POLARIDADE INVERTIDA — é isso que a escondia;
##   3. ela roda **uma vez só** (gate `4c 03 0b 00` / `4d 03 0b 01`) e TERMINA pelo caminho do jogo.
##
##     godot --headless --audio-driver Dummy --path port \
##         --script res://dev/run_tests.gd -- cena

const SALA := "R101"
const FUNC_ENTRADA := 3
## O gate da 1ª visita: banco 3, bit 0x0b (`4c 03 0b 00` na func 0, `4d 03 0b 01` na func 3).
const BANCO_JA_RODOU := 3
const BIT_JA_RODOU := 0x0B


func run(t) -> bool:
	var pad := Pad.new()
	pad.set_mask(0)

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("1. o `0x4c` = flag XOR (byte alto == 0) — `0x800546cc`, e é o que escondia a cena")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# `0x800546cc`: `sra $a1,8` (byte alto) · `sltiu $a1,$a1,1` (== 0?) · `xor $v0,$v0,$a1`.
	# Logo: byte alto 0 ⇒ NEGADO ; byte alto != 0 ⇒ direto. Monto os dois casos à mão, num
	# bytecode sintético, para a asserção não depender de nenhuma sala.
	#
	#   tabela de funções (1 função, offset 2) · if_begin(else = +4 adiante) · 4c · 4d marcador
	var gs := GameState.new()
	for alto: int in [0x00, 0x01]:
		for aceso: bool in [false, true]:
			var vm := ScriptVM.new()
			# [02 00] tabela · 06 00 09 00 · 4c 05 20 <alto> · 4d 06 01 01 (marcador VERDADEIRO)
			# · 01 · else: 4d 06 02 01 (marcador FALSO) · 01
			# O alvo do `else` é `PC + 4 + u16@+2` = 2 + 4 + 9 = índice 15 = o 2º `4d`.
			vm.bytes = PackedByteArray([
				0x02, 0x00,
				0x06, 0x00, 0x09, 0x00,
				0x4C, 0x05, 0x20, alto,
				0x4D, 0x06, 0x01, 0x01,
				0x01,
				0x4D, 0x06, 0x02, 0x01,
				0x01])
			vm.func_offsets = PackedInt32Array([2])
			gs.reset()
			gs.flag_set(5, 0x20, aceso)
			vm.state = gs
			vm.modo = ScriptVM.Modo.EXECUCAO
			vm.executar(0)
			var verdadeiro := gs.flag_get(6, 1)
			var esperado := aceso != (alto == 0)
			t.eq(verdadeiro, esperado,
				"4c 05 20 %02x com a flag %s: condição %s" % [
					alto, "acesa" if aceso else "apagada", esperado])
			t.eq(gs.flag_get(6, 2), not esperado, "  e o outro ramo NÃO rodou")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("2. o INIT do R101 pede UMA thread, e é a função 3")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var vm2 := ScriptVM.new()
	if not t.check(vm2.carregar_sala(SALA), "o bytecode do R101 carrega"):
		return false
	vm2.state = GameState.new()
	vm2.modo = ScriptVM.Modo.EXECUCAO
	vm2.executar(0)
	t.eq(vm2.threads_pedidas.size(), 1, "o init pede exatamente 1 thread (`0x04 evt_exec`)")
	if vm2.threads_pedidas.size() == 1:
		var p: Dictionary = vm2.threads_pedidas[0]
		t.eq(int(p["func"]), FUNC_ENTRADA, "e é a FUNÇÃO 3 (`04 ff 19 03`, func 0 @+0x0246)")
		t.eq(int(p["slot"]), 0xFF, "no slot 0xff (qualquer livre, 2..9)")
	# ── o gate da 1ª visita ──
	var vm3 := ScriptVM.new()
	vm3.carregar_sala(SALA)
	var gs3 := GameState.new()
	gs3.flag_set(BANCO_JA_RODOU, BIT_JA_RODOU, true)     ## "a cena já rodou"
	vm3.state = gs3
	vm3.modo = ScriptVM.Modo.EXECUCAO
	vm3.executar(0)
	var pediu_3 := false
	for p3: Dictionary in vm3.threads_pedidas:
		if int(p3["func"]) == FUNC_ENTRADA:
			pediu_3 = true
	t.check(not pediu_3,
		"com a flag 3/0x0b ACESA o init NÃO pede a função 3 (a cena não reprisa)")

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("3. a cena roda, ANIMA e termina — e é ela mesma que acende a flag de 'já rodou'")
	# ═══════════════════════════════════════════════════════════════════════════════════
	var w := World.new()
	if not t.check(w.carregar(SALA), "R101 carrega no mundo"):
		return false
	if not t.check(w.cena != null, "carregar(R101) abre a cinemática de entrada"):
		return false
	t.eq(w.cena_func, FUNC_ENTRADA, "e ela é a FUNÇÃO 3")
	t.eq(w.player.acao, Player.Acao.CENA, "o player entra no estado CENA (ação 4)")
	## Na chegada MEDIDA (a emprestada do `R102`, §3 do doc): é dali que a coreografia parte, e é
	## o que o caminho real do jogo entrega quando se vem do `R10D`.
	w.player.pos = Vector3i(-4434, -3600, -27933)
	w.player.facing = 3136
	pad.set_mask(0)
	w.tick(pad)
	t.check(w.state.flag_get(BANCO_JA_RODOU, BIT_JA_RODOU),
		"no 1º quadro a função 3 já fez `4d 03 0b 01` (acendeu a flag de 'já rodou')")

	var cams: Array[int] = []
	var seqs: Array[int] = []
	var q := 0
	while w.cena != null and q < World.CENA_MAX_QUADROS + 10:
		var a_cam := w.camera
		var a_seq := w.player.cena_seq
		pad.set_mask(0)
		w.tick(pad)
		q += 1
		if w.camera != a_cam:
			cams.append(w.camera)
		if w.player.cena_seq != a_seq and w.player.cena_seq >= 0:
			seqs.append(w.player.cena_seq)
	t.check(q < World.CENA_MAX_QUADROS,
		"★ a cena TERMINA (não cai na rede de segurança)", "%d quadros" % q)
	## O número EXATO depende de quanto o corpo anda no `0x81` (a rotina do `0x81` não foi
	## decodificada, `cena_r10d.md` §7-1), então aqui se cobra a ORDEM DE GRANDEZA. O valor medido
	## pelo caminho real do jogo (`R10D -> R101`, `port/dev/diag_cena_r101_jogo.gd`) é **1362**
	## quadros ≈ 45 s, e o `test_cena_world.gd` cobra esse trajeto inteiro.
	t.check(q > 1200 and q < 1800, "e dura ~1300-1800 quadros (~45-60 s a 30 Hz)", "%d" % q)
	## 🟡 DÍVIDA REGISTRADA: a função 13 (a que devolve o controle) faz
	## `10 06 0a 00` / `4e 00 1a 05 09 00` = `while (var[26] != 9)`, e `var[26]` é escrita pelo
	## MOTOR, não pelo script — o port rompe essa espera pelo freio de `while` de `ScriptVM`.
	t.check(", ".join(w.cena_debitos).contains("`while`"),
		"e a espera que o port não sabe satisfazer fica registrada como dívida",
		", ".join(w.cena_debitos))
	t.eq(cams, [24, 10, 25, 26, 25, 26, 27, 21, 19, 17, 10] as Array[int],
		"as câmeras da cena chegam ao `world.camera`, na ordem do bytecode")
	t.check(seqs.size() >= 10, "e o player recebe as SEQ do `0x80` (mais de 10 trocas)",
		str(seqs))
	# 🟡 A cena pede SEQ 22/24/25 e o banco `animNN` do PL00.PLD só vai até 21 — a apresentação
	# não toca clipe nesses trechos. Fica cobrado como DÍVIDA CONHECIDA, não como sucesso.
	var fora_do_banco: Array[int] = []
	for s: int in seqs:
		if s > 21 and not fora_do_banco.has(s):
			fora_do_banco.append(s)
	fora_do_banco.sort()
	t.eq(fora_do_banco, [22, 24, 25] as Array[int],
		"DÍVIDA: a cena pede SEQ 22/24/25 e o banco `anim%02d` do PL00.PLD para em 21")
	t.eq(w.player.acao, Player.Acao.PARADO, "o controle volta para o jogador no fim")
	t.check(not w.player.em_cena(), "player.em_cena() = false depois da cena")

	# --- e o pad volta a valer ---
	var antes := w.player.pos
	for _i in 20:
		pad.set_mask(Pad.FWD)
		w.tick(pad)
	t.check(w.player.pos != antes, "depois da cena o PAD move o personagem",
		"de %s para %s" % [antes, w.player.pos])

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("4. `Cena.atores_externos`: quem espera bit de ENTIDADE não pode ficar preso")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# A função 3 tem `47 03 00` · `81 00 09 01 …` · `while (NÃO flag(4,1))` — espera a ENTIDADE
	# chegar. Com o antigo `simular_movimento = false` (que desligava TODOS os atores) a cena
	# morria na rede de segurança dos 4000 quadros.
	var w2 := World.new()
	w2.carregar(SALA)
	if t.check(w2.cena != null, "a cena abriu"):
		t.eq(w2.cena.atores_externos, {Player.CENA_WORK_PLAYER: true},
			"só o work do PLAYER é dirigido de fora; as entidades ficam com a `Cena`")
		t.check(w2.cena.simular_movimento,
			"e a simulação de deslocamento segue LIGADA para os outros works")
	# A prova pelo avesso: desligando tudo, a mesma cena NÃO termina.
	var vmx := ScriptVM.new()
	vmx.carregar_sala(SALA)
	var gsx := GameState.new()
	vmx.state = gsx
	vmx.modo = ScriptVM.Modo.EXECUCAO
	vmx.executar(0)
	var cx := Cena.new()
	cx.iniciar(vmx, FUNC_ENTRADA, gsx)
	cx.simular_movimento = false
	var qx := cx.rodar(World.CENA_MAX_QUADROS)
	t.check(cx.viva(),
		"com NENHUM ator simulado a cena fica presa no `while (não flag(4,1))`",
		"%d quadros e ainda viva" % qx)

	# ═══════════════════════════════════════════════════════════════════════════════════
	t.group("5. a cena NÃO posiciona o player em X/Z — ela declara o ANDAR (nível 2)")
	# ═══════════════════════════════════════════════════════════════════════════════════
	# Varredura das 19 funções: nenhum `0x40`/`0x41` nos membros 0x09 (X) ou 0x0b (Z) do work 1:0.
	# O que existe é `40 0f 02 00` (+0x005c da func 3) = `player+0x09 = 2` = nível 2 ⇒ y = -3600.
	t.eq(World._nivel_da_cena_de_entrada(SALA), 2,
		"`CENAS_METADADOS[R101].chegada_nivel` = 2, o que o `40 0f 02 00` declara")
	var emp := World._chegada_emprestada(SALA, 2)
	if t.check(not emp.is_empty(), "há chegada MEDIDA nesse andar para emprestar"):
		t.eq(str(emp["src"]), "R102", "e é a da porta R102 -> R101")
		t.eq(emp["pos"], Vector3i(-4434, -3600, -27933), "no nível 2 (y = -3600)")
	t.eq(int((World._chegada_emprestada(SALA)["pos"] as Vector3i).y), -7200,
		"sem o critério de andar sairia a do R100, que é nível 4 — o empréstimo antigo")
	return true
