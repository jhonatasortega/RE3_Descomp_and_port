extends RefCounted
## BAÚ DE ITENS (item box): o `sce` provado, o gatilho pelo AOT e a transferência nos 2 sentidos.
##
## Por que cada bloco existe:
##
## 1. **`sce 9` é o baú, `sce 8` é a máquina de escrever** — o enum que o port herdou (do RE2)
##    dizia `9=SAVE` e `10=ITEMBOX`, e isso estava ERRADO. A prova está em
##    `port/script_vm/aot.gd` (tabela `0x8009e0bc`, `0x800514cc` grava screen kind 2, os
##    subestados do kind 2 varrem `inv+0x28` com limite 64, e `sce 8` procura o Ink Ribbon
##    `0x81`). Aqui se testa a **consequência no DADO**: `sce 8` e `sce 9` têm de aparecer nas
##    mesmas salas de save, com `sat 0x31` (exige o botão de ação). Se um dia a extração mudar
##    e isso deixar de valer, o teste fecha vermelho antes de o baú abrir na sala errada.
## 2. **Gatilho**: o baú só abre com o botão de ação e olhando para ele — `sat 0x31` tem o bit
##    `0x20` (ponto de sonda 620 à frente) e o bit `0x10` (passagem de ação). Encostar de lado
##    ou de costas NÃO pode abrir.
## 3. **Transferência**: a regra é a da janela de obter item (`0x80069cb8`) — empilha se cabe no
##    máximo do descritor (`0x800a0514[id].b1`), senão primeiro slot livre, senão FALHA e o item
##    fica onde estava. É o que impede munição de "sumir" ao guardar num baú quase cheio.

const SONDA := 620


func run(t: Object) -> bool:
	t.group("baú")

	# ───────────────── 1. o `sce` do baú, e o do save ─────────────────
	t.eq(Aot.SCE_BAU, 9, "sce 9 = BAÚ (0x800514c4 -> screen kind 2 -> inv+0x28 x64)")
	t.eq(Aot.SCE_SAVE, 8, "sce 8 = SAVE (0x800513cc -> find_by_id(0x81) = Ink Ribbon)")
	t.eq(Aot.SCE_FIM, 10, "sce 10 = overlay de fim (0x0c + n = RESULT/SELECT/STAFF_R/TITLE)")
	t.eq(Aot.SCE_DANO, 12, "sce 12 = dano (player+0xcc -= u16@+2)")

	var salas := _listar_salas()
	t.check(salas.size() > 100, "achei os JSON de sala", "%d salas" % salas.size())
	var com_bau: Array[String] = []
	var com_save: Array[String] = []
	var sat_bau: Dictionary = {}
	var sat_save: Dictionary = {}
	var bau_sem_area := 0
	for id in salas:
		var scd: Variant = AssetIO.json("STAGE%d/%s_scd.json" % [RoomData.stage_of(id), id])
		if not (scd is Dictionary):
			continue
		for tr: Dictionary in (scd as Dictionary).get("triggers", []):
			var sce := int(tr.get("sce", -1))
			# o exportador grava o byte +3 (o SAT) no campo chamado "floor" — ver a correção
			# registrada em docs/decomp/notes/menu_bau.md; o andar de verdade é o byte +4.
			var sat := int(tr.get("floor", 0))
			if sce == Aot.SCE_BAU:
				if not com_bau.has(id):
					com_bau.append(id)
				sat_bau[sat] = int(sat_bau.get(sat, 0)) + 1
				var b: Dictionary = tr.get("box", {})
				if int(b.get("w", 0)) <= 1 or int(b.get("d", 0)) <= 1:
					bau_sem_area += 1
			elif sce == Aot.SCE_SAVE:
				if not com_save.has(id):
					com_save.append(id)
				sat_save[sat] = int(sat_save.get(sat, 0)) + 1
	t.eq(com_bau.size(), 16, "16 salas com baú (uma por sala de save)", str(com_bau))
	t.eq(com_save.size(), 16, "16 salas com máquina de escrever", str(com_save))
	t.eq(sat_bau, {0x31: 16}, "todo baú tem SAT 0x31 = ação + ponto de sonda")
	t.eq(sat_save, {0x31: 16}, "todo save tem SAT 0x31 (mesmo gatilho)")
	t.eq(bau_sem_area, 0, "todo baú tem área de gatilho de verdade (nenhum degenerado)")
	# baú e save moram juntos: 15 das 16 salas têm os dois
	var juntos := 0
	for id in com_bau:
		if com_save.has(id):
			juntos += 1
	t.eq(juntos, 15, "15 salas têm baú E máquina de escrever (R50B só baú, R111 só save)")

	# ───────────────── 2. gatilho: AOT + sonda de 620 + botão de ação ─────────────────
	# A sala de referência é a **R100** — a 1ª sala de save do jogo, e a caixa abaixo é o que a VM
	# monta rodando as 9 funções do `R100.scd` (medido em `port/dev/diag_bau.gd`, que faz a mesma
	# varredura nas 16 salas e acha 1 baú em cada). Não use uma sala de cabeça: `R11B` nem existe
	# na lista, e `R111` é a única sala com máquina de escrever SEM baú.
	var vm := ScriptVM.new()
	var gs := GameState.new()
	t.check(vm.carregar_sala("R100"), "R100 carrega (1ª sala de save do jogo)")
	vm.modo = ScriptVM.Modo.EXECUCAO
	vm.state = gs
	for fi in vm.func_offsets.size():
		vm.executar(fi)
	var baus := vm.baus()
	t.eq(baus.size(), 1, "a VM instalou 1 baú na R100", "%d AOTs na sala" % vm.aots.size())
	if baus.is_empty():
		return true
	var b0: Aot = baus[0]
	t.eq(b0.id, 2, "o baú da R100 é o AOT 2")
	t.eq(b0.sce, Aot.SCE_BAU, "o AOT é sce 9")
	t.eq(b0.sat, 0x31, "SAT 0x31")
	t.check(b0.exige_acao(), "exige o botão de ação (sat & 0x10)")
	t.check(b0.usa_sonda(), "testa o ponto de sonda (sat & 0x20)")
	t.check(not b0.usa_corpo(), "NÃO testa a posição do corpo (sat & 0x40 apagado)")
	t.eq(b0.kind, Aot.Kind.BOX, "área em AABB (opcode 0x63)")
	t.eq(b0.box, Rect2i(-28902, -23031, 1940, 2530), "a caixa do baú da R100 (bytes do SCD)")
	# e o baú CONTINUA montado depois das 9 funções: nenhum `aot_reset 0x65` o apaga
	t.check(b0.ativo, "o baú fica ativo depois de toda a montagem da sala")

	# centro da caixa; o jogador fica 620+ ao SUL dela e olha para o norte (facing 0)
	var cx := b0.box.position.x + b0.box.size.x / 2
	var cz := b0.box.position.y + b0.box.size.y / 2
	var pos := Vector3i(cx, 0, cz + b0.box.size.y / 2 + 300)
	# facing 0 = -Z (a sonda é `pos + (rsin, -rcos) * 620`, ver ScriptVM.sonda_de)
	var s := ScriptVM.sonda_de(pos, 0)
	t.eq(s, Vector2i(pos.x, pos.z - SONDA), "a sonda fica 620 unidades à frente com facing 0")
	t.check(vm.bau_de_acao(pos, 0) != null, "olhando para o baú, o gatilho pega")
	t.check(vm.bau_de_acao(pos, 2048) == null, "de costas (facing 2048 = +Z) NÃO pega")
	var longe := Vector3i(cx, 0, cz + 20000)
	t.check(vm.bau_de_acao(longe, 0) == null, "longe não pega")
	# corpo DENTRO da caixa mas de costas: não pega, porque `sat 0x31` não tem o bit de corpo.
	# O ponto tem de ficar na borda SUL de dentro (`z = fim - 10`): a caixa do baú da R100 tem
	# 2530 de profundidade, então do CENTRO a sonda de 620 para +Z ainda cai dentro dela e o
	# teste não provaria nada. Da borda, a sonda sai da caixa e só o corpo está dentro.
	var borda := Vector3i(cx, 0, b0.box.position.y + b0.box.size.y - 10)
	t.check(b0.contem(borda.x, borda.z), "a borda escolhida está DENTRO da caixa")
	t.check(not b0.contem(ScriptVM.sonda_de(borda, 2048).x, ScriptVM.sonda_de(borda, 2048).y),
		"e a sonda de costas dali sai da caixa")
	t.check(vm.bau_de_acao(borda, 2048) == null,
		"corpo dentro da caixa mas de costas não abre (sat sem o bit 0x40)")
	# AOT desativado (aot_reset 0x65) não dispara
	b0.ativo = false
	t.check(vm.bau_de_acao(pos, 0) == null, "baú desativado não dispara")
	b0.ativo = true

	# ───────────────── 3. transferência mão -> baú ─────────────────
	gs.reset()
	# Hand Gun (0x03, arma, max 1) + Hand Gun Bullets (0x15) para exercitar os dois caminhos
	t.eq(gs.add_item(0x03, 15, 0x0001), 0, "arma no slot 0 da mão")
	t.eq(gs.add_item(0x15, 30, 0x0001), 1, "munição no slot 1 da mão")
	gs.equipped = 0
	t.eq(gs.transferir(0, false), GameState.Transf.OK, "guardar a arma no baú")
	t.eq(gs.main_slots[0]["id"], 0, "o slot 0 da mão ficou vazio")
	t.eq(gs.box_slots[0]["id"], 0x03, "a arma foi para o slot 0 do baú")
	t.eq(gs.box_slots[0]["qtd"], 15, "com a munição carregada dela")
	t.eq(gs.equipped, -1, "guardar a arma EQUIPADA desequipa (senão o id vira o do vizinho)")
	t.eq(gs.equipped_item_id(), 0, "e o id equipado passa a ser 0")

	# ───────────────── 4. transferência baú -> mão ─────────────────
	t.eq(gs.transferir(0, true), GameState.Transf.OK, "tirar a arma do baú")
	t.eq(gs.box_slots[0]["id"], 0, "o slot do baú ficou vazio")
	t.eq(gs.find_by_id(0x03), 0, "a arma voltou para o 1º slot livre da mão")

	# ───────────────── 5. EMPILHAR respeitando o máximo do descritor ─────────────────
	# Duas coisas diferentes que o mesmo `transferir` tem de fazer, e a ORDEM importa
	# (`exe_items.md §2.3`): 1º tenta empilhar num slot do mesmo item; só se não sobrar espaço
	# procura slot LIVRE. Para exercitar o "não cabe" é obrigatório encher o resto do baú — com
	# 63 slots vazios o certo é a transferência ir para um slot livre, e não falhar.
	var max_bala := gs.maximo_do_item(0x15)
	t.check(max_bala > 1, "Hand Gun Bullets empilha", "max = %d" % max_bala)
	gs.reset()
	gs.add_item(0x15, 30, 0x0001)                      ## mão: 30 balas
	for i in range(1, 64):                             ## baú lotado, menos o slot 0
		gs.box_slots[i] = {"id": 0x41, "qtd": 1, "flags": 0}
	gs.box_slots[0] = {"id": 0x15, "qtd": max_bala - 10, "flags": 0x0001}
	t.eq(gs.transferir(0, false), GameState.Transf.PARCIAL,
		"só cabem 10 no baú -> transferência PARCIAL")
	t.eq(gs.box_slots[0]["qtd"], max_bala, "o baú fica no máximo exato do descritor")
	t.eq(gs.main_slots[0]["qtd"], 20, "as 20 que não cabem FICAM na mão")
	t.eq(gs.transferir(0, false), GameState.Transf.CHEIO,
		"com a pilha no máximo e sem slot livre, a operação falha")
	t.eq(gs.main_slots[0]["qtd"], 20, "e nada é perdido")

	# empilhar até caber tudo -> OK e o slot de origem some
	gs.box_slots[0]["qtd"] = max_bala - 50
	t.eq(gs.transferir(0, false), GameState.Transf.OK, "cabendo tudo, é OK")
	t.eq(gs.main_slots[0]["id"], 0, "o slot da mão foi liberado")
	t.eq(gs.box_slots[0]["qtd"], max_bala - 30, "e o baú somou as 20")

	# com o baú NÃO lotado, a pilha cheia não é impedimento: vai para o 1º slot livre
	gs.reset()
	gs.add_item(0x15, 30, 0x0001)
	gs.box_slots[0] = {"id": 0x15, "qtd": max_bala, "flags": 0x0001}
	t.eq(gs.transferir(0, false), GameState.Transf.OK,
		"pilha no máximo mas com slot livre -> vai para o slot livre")
	t.eq(gs.box_slots[0]["qtd"], max_bala, "a pilha cheia não muda")
	t.eq(gs.box_slots[1], {"id": 0x15, "qtd": 30, "flags": 0x0001},
		"e as 30 abrem uma segunda pilha no slot 1")

	# ───────────────── 6. baú CHEIO (64 slots) e slot vazio ─────────────────
	gs.reset()
	t.eq(gs.box_slots.size(), 64, "o baú tem 64 slots (limite 0x40 do kind 2)")
	for i in 64:
		gs.box_slots[i] = {"id": 0x41, "qtd": 1, "flags": 0}      ## Lighter Oil, não empilha aqui
	gs.add_item(0x03, 15, 0x0001)
	t.check(not gs.pode_transferir(0, false), "pode_transferir diz não com o baú cheio")
	t.eq(gs.transferir(0, false), GameState.Transf.CHEIO, "e a transferência recusa")
	t.eq(gs.main_slots[0]["id"], 0x03, "a arma continua na mão")
	t.eq(gs.transferir(5, false), GameState.Transf.VAZIO, "slot vazio não transfere")
	t.eq(gs.transferir(-1, false), GameState.Transf.VAZIO, "índice inválido não quebra")
	t.eq(gs.transferir(999, true), GameState.Transf.VAZIO, "índice fora do baú não quebra")

	# ───────────────── 7. mão CHEIA ao tirar do baú ─────────────────
	gs.reset()
	for i in 10:
		gs.main_slots[i] = {"id": 0x41, "qtd": 1, "flags": 0}
	gs.box_slots[0] = {"id": 0x03, "qtd": 15, "flags": 0x0001}
	t.eq(gs.transferir(0, true), GameState.Transf.CHEIO, "mão cheia recusa a retirada")
	t.eq(gs.box_slots[0]["id"], 0x03, "e o item continua no baú")

	# ───────────────── 8. o save leva a transferência (P3-05) ─────────────────
	gs.reset()
	gs.add_item(0x15, 30, 0x0001)
	gs.transferir(0, false)
	var d := gs.to_dict()
	var g2 := GameState.new()
	t.check(g2.from_dict(d), "save/load do estado com o baú preenchido")
	t.eq(g2.box_slots[0]["id"], 0x15, "o item guardado sobrevive ao save")
	t.eq(g2.box_slots[0]["qtd"], 30, "com a quantidade certa (inteiro, não float do JSON)")
	t.check(typeof(g2.box_slots[0]["qtd"]) == TYPE_INT, "quantidade normalizada para inteiro")

	# ───────────────── 9. a TELA: navegação e paginação (sem depender de asset) ─────────────────
	var tela := MenuBau.new()
	tela.carregar(gs)
	t.eq(tela.total_paginas(), 4, "64 slots / 20 por página = 4 páginas")
	t.eq(MenuBau.BAU_SLOTS, 64, "a tela conhece os 64 slots")
	t.check(not tela.aberto, "a tela nasce fechada")
	# a navegação não depende dos PNG; forço o estado aberto para testar a lógica de cursor
	tela.aberto = true
	tela._anim = 0
	tela.lado = MenuBau.Lado.MAO
	tela.cursor_mao = 0
	tela.mover_cursor(1, 0)
	t.eq(tela.cursor_mao, 1, "direita anda na coluna da mão")
	tela.mover_cursor(0, 1)
	t.eq(tela.cursor_mao, 3, "baixo anda uma linha (2 colunas)")
	tela.mover_cursor(-1, 0)
	t.eq(tela.cursor_mao, 2, "esquerda volta")
	tela.mover_cursor(-1, 0)
	t.eq(tela.lado, MenuBau.Lado.BAU, "esquerda na 1ª coluna atravessa para o baú")
	tela.mudar_pagina(1)
	t.eq(tela.pagina, 1, "L1/R1 vira a página")
	t.check(tela.cursor_bau >= 20 and tela.cursor_bau < 40,
		"o cursor do baú acompanha a página", str(tela.cursor_bau))
	tela.mudar_pagina(99)
	t.eq(tela.pagina, 3, "a página satura na última (sem dar a volta)")
	tela.mudar_pagina(-99)
	t.eq(tela.pagina, 0, "e na primeira")
	# confirmar transfere de verdade
	gs.reset()
	gs.add_item(0x15, 30, 0x0001)
	tela.lado = MenuBau.Lado.MAO
	tela.cursor_mao = 0
	tela.sair_selecionado = false
	var msg := tela.confirmar()
	t.check(msg != "", "confirmar na mão devolve uma linha para o HUD", msg)
	t.eq(gs.box_slots[0]["id"], 0x15, "e o item foi para o baú")
	tela.lado = MenuBau.Lado.BAU
	tela.cursor_bau = 0
	tela.confirmar()
	t.eq(gs.main_slots[0]["id"], 0x15, "e volta para a mão pelo lado do baú")
	tela.sair_selecionado = true
	tela.confirmar()
	t.check(tela._fechando, "SAIR fecha a tela")

	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("res://data/STAGE%d" % st)
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.ends_with("_scd.json"):
				saida.append(nome.trim_suffix("_scd.json"))
	saida.sort()
	return saida
