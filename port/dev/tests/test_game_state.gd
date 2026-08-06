extends RefCounted
## Valida o estado global (critério do item P0-07).
##
## O que precisa estar certo, e por quê: a fórmula word/mask do EXE (senão flags "vizinhos"
## se sobrepõem e o progresso corrompe silenciosamente), a ordem MSB-first (senão o bit 0 e o
## bit 31 trocam de lugar), o efeito do `& 0x1c` (256 bits por banco, com volta) e o
## save/load sem perda.


func run(t: Object) -> bool:
	t.group("GameState")
	var g := GameState.new()

	# --- fórmula do EXE: word = ((bit >> 3) & 0x1c) / 4 ---
	t.eq(GameState.word_index(0, 0), 0, "bit 0 -> word 0")
	t.eq(GameState.word_index(0, 31), 0, "bit 31 ainda no word 0")
	t.eq(GameState.word_index(0, 32), 1, "bit 32 -> word 1")
	t.eq(GameState.word_index(0, 255), 7, "bit 255 -> word 7 (último do banco)")
	t.eq(GameState.word_index(1, 0), 8, "banco 1 começa no word 8")
	t.eq(GameState.word_index(15, 255), 127, "último word dos 16 bancos")

	# --- máscara MSB-first: 0x80000000 >> (bit & 0x1f) ---
	t.eq(GameState.bit_mask(0), 0x80000000, "bit 0 = bit MAIS significativo do word")
	t.eq(GameState.bit_mask(1), 0x40000000, "bit 1")
	t.eq(GameState.bit_mask(31), 0x1, "bit 31 = bit menos significativo")
	t.eq(GameState.bit_mask(32), 0x80000000, "bit 32 reinicia no MSB do word seguinte")

	# --- set / check / clear ---
	t.check(not g.flag_get(1, 5), "flag nasce desligado")
	g.flag_set(1, 5)
	t.check(g.flag_get(1, 5), "set liga")
	t.eq(g.flags_set_count(), 1, "exatamente 1 flag ligado no jogo todo")
	g.flag_clear(1, 5)
	t.check(not g.flag_get(1, 5), "clear desliga")
	t.eq(g.flags_set_count(), 0, "nenhum flag ligado depois do clear")

	# --- independência: ligar um flag não contamina o vizinho nem outro banco ---
	g.flag_set(1, 40)
	t.check(not g.flag_get(1, 39) and not g.flag_get(1, 41), "vizinhos intactos")
	t.check(not g.flag_get(0, 40) and not g.flag_get(2, 40), "outros bancos intactos")
	var todos_ok := true
	for b in GameState.N_BANKS:
		for bit in [0, 1, 31, 32, 63, 128, 255]:
			if b == 1 and bit == 40:
				continue
			if g.flag_get(b, bit):
				todos_ok = false
	t.check(todos_ok, "nenhum outro (banco,bit) amostrado foi afetado")

	# --- volta em 256 bits (efeito do & 0x1c) ---
	g.reset()
	g.flag_set(3, 0)
	t.check(g.flag_get(3, 256), "bit 256 dá a volta e cai no bit 0 (fórmula do EXE)")
	t.eq(g.flags_set_count(), 1, "a volta não cria um segundo flag")

	# --- atalho de progresso (banco 1) ---
	g.reset()
	g.progress_set(4)
	t.check(g.flag_get(GameState.BANK_PROGRESS, 4), "progress_set escreve no banco 1")
	t.eq(GameState.BANK_PROGRESS, 1, "banco de progresso = 1 (0x800d1f2c)")

	# --- variáveis de script (16 bits) ---
	g.var_set(7, 1234)
	t.eq(g.var_get(7), 1234, "variável guardada")
	g.var_set(7, 0x1FFFF)
	t.eq(g.var_get(7), 0xFFFF, "variável truncada em 16 bits")

	# --- inventário: 10 de mão / 64 na caixa, slot {id,qtd,flags} ---
	g.reset()
	t.eq(g.main_slots.size(), 10, "10 slots de mão (MAIN)")
	t.eq(g.box_slots.size(), 64, "64 slots na caixa (BOX)")
	t.eq(g.find_by_id(0), 0, "find_by_id(0) devolve o primeiro slot LIVRE")
	t.eq(g.add_item(0x15, 30), 0, "pegar munição de pistola vai para o slot 0")
	t.eq(g.add_item(0x02, 1), 1, "segundo item vai para o slot 1")
	t.eq(g.find_by_id(0x15), 0, "acha por id")
	t.eq(g.find_by_id(0x99), -1, "id ausente devolve -1")
	t.eq(g.find_by_id(0), 2, "primeiro livre agora é o slot 2")
	t.eq(g.item_count(), 2, "2 itens na mão")

	# --- consumir ---
	t.check(g.consume(0x15, 10), "consumir 10 de 30")
	t.eq(int(g.main_slots[0]["qtd"]), 20, "sobram 20")
	t.check(not g.consume(0x15, 99), "não consome mais do que tem")
	t.check(g.consume(0x15, 20), "consumir o resto")
	t.eq(int(g.main_slots[0]["id"]), 0, "slot é liberado quando a quantidade zera")

	# --- compactar preservando a ordem ---
	g.reset()
	g.add_item(1, 1)
	g.add_item(2, 1)
	g.add_item(3, 1)
	g.remove_slot(1)
	g.compact()
	t.eq([int(g.main_slots[0]["id"]), int(g.main_slots[1]["id"]), int(g.main_slots[2]["id"])],
		[1, 3, 0], "compact empurra para o começo mantendo a ordem")

	# --- loadout de novo jogo ---
	g.reset()
	g.load_loadout([{"id": 0x02, "qtd": 1}, {"id": 0x15, "qtd": 15}])
	t.eq(int(g.main_slots[0]["id"]), 0x02, "loadout: 1º item")
	t.eq(int(g.main_slots[1]["qtd"]), 15, "loadout: quantidade do 2º")
	t.eq(g.item_count(), 2, "loadout não deixa lixo nos outros slots")

	# --- save / load sem perda ---
	g.reset()
	for par: Array in [[0, 0], [1, 31], [1, 32], [7, 200], [15, 255]]:
		g.flag_set(par[0], par[1])
	g.var_set(3, 999)
	g.add_item(0x02, 1)
	g.add_item(0x15, 45)
	g.stage = 4
	g.room = 0x0B
	g.play_ticks = 54321
	g.save_count = 7
	g.equipped = 1

	var d := g.to_dict()
	var g2 := GameState.new()
	t.check(g2.from_dict(d), "from_dict aceita o save")
	t.eq(g2.flags_set_count(), 5, "os 5 flags voltaram")
	for par2: Array in [[0, 0], [1, 31], [1, 32], [7, 200], [15, 255]]:
		t.check(g2.flag_get(par2[0], par2[1]), "flag (%d,%d) preservado" % par2)
	t.eq(g2.var_get(3), 999, "variável preservada")
	t.eq(int(g2.main_slots[1]["qtd"]), 45, "inventário preservado")
	t.eq([g2.stage, g2.room, g2.play_ticks, g2.save_count, g2.equipped], [4, 11, 54321, 7, 1],
		"progresso preservado (stage, sala, tempo, saves, arma)")

	# --- ida e volta por ARQUIVO (é o que o save de verdade faz) ---
	var caminho := "user://_test_save.json"
	t.eq(g.save_to_file(caminho), OK, "gravou o arquivo de save")
	var g3 := GameState.new()
	t.check(g3.load_from_file(caminho), "leu o arquivo de save")
	t.eq(JSON.stringify(g3.to_dict()), JSON.stringify(g.to_dict()),
		"estado idêntico depois de gravar e ler do disco")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho))

	# --- save inválido não corrompe ---
	var g4 := GameState.new()
	t.check(not g4.from_dict({"versao": 99}), "recusa versão desconhecida")
	t.check(not g4.load_from_file("user://_nao_existe.json"), "arquivo ausente devolve false")

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true
