extends RefCounted
## Tela de ARQUIVO: o índice de documentos, o de-para das páginas em HD/PT-BR e a navegação WSAD.
## O que este teste protege: o de-para `hd_memo_pt.json` foi feito LENDO as 143 páginas do pack e
## casando com a página SD; se alguém regerar o JSON com o pack mudado, as contas aqui acusam.


func run(t: Object) -> bool:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/re3_file_screen.json"))
	t.check(raw is Dictionary, "re3_file_screen.json carrega")
	var tela: Dictionary = raw
	var docs: Array = tela.get("documentos", [])
	var paginas: Array = tela.get("paginas", [])
	t.eq(docs.size(), 31, "31 documentos no FILEGU.PIX")
	t.eq(paginas.size(), 183, "183 páginas no FILEGU.PIX")

	# cada documento é capa + N páginas de texto, e `n_pages` conta a capa
	var total_texto := 0
	for d: Dictionary in docs:
		var tp: Array = d.get("text_pages", [])
		total_texto += tp.size()
		t.eq(int(d.get("n_pages", 0)), tp.size() + 1,
			"doc%d: n_pages = capa + %d páginas" % [int(d.get("doc", -1)), tp.size()])
	t.eq(total_texto, 152, "152 páginas de texto (as outras 31 são capas)")

	# ── de-para HD/PT (`data/hd_memo_pt.json`, de `tools/memo_pt.py`) ──
	var raw2: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/hd_memo_pt.json"))
	t.check(raw2 is Dictionary, "hd_memo_pt.json carrega")
	var pt: Dictionary = raw2
	var mapa: Dictionary = pt.get("paginas", {})
	t.eq(mapa.size(), 143, "143 páginas em HD e português (o resto do pack `memo` é russo)")
	var sem: Dictionary = pt.get("sem_pt", {})
	t.eq(sem.size(), 9, "9 páginas SD sem PT: 6 em branco + 3 rabichos de uma linha")
	t.eq(mapa.size() + sem.size(), total_texto,
		"143 + 9 = 152: todas as páginas de texto estão explicadas")
	# nenhum arquivo HD serve duas páginas
	var usados := {}
	for k: String in mapa:
		var v := String(mapa[k])
		t.check(not usados.has(v), "arquivo %s usado uma vez só" % v)
		usados[v] = true
	# o Diário da Jill (doc30) é o caso que fecha 1:1 e foi conferido frase a frase
	for d2: Dictionary in docs:
		if int(d2.get("doc", -1)) != 30:
			continue
		for p: float in d2.get("text_pages", []):
			t.check(mapa.has("%d" % int(p)),
				"Diário da Jill: página %d tem versão PT" % int(p))

	# ── navegação: WSAD na grade (5 colunas) e no leitor ──
	var st := GameState.new()
	st.novo_jogo()
	var a := MenuArquivo.new()
	a.carregar(st)
	# ── REGRA: só entra na lista o documento LIDO (pegar do chão conta; os dois iniciais precisam
	# de USAR). Antes bastava estar no inventário, e as Instruções A/B apareciam sem ter sido abertas.
	## A grade tem SLOT FIXO: são sempre os 31 documentos (o cursor anda por cima dos vazios, como
	## o usuário pediu); o que muda é ter sido lido.
	a.abrir()
	t.eq(a.docs.size(), 31, "a grade é fixa: 31 slots sempre")
	t.eq(a.n_lidos(), 0, "jogo novo tem as Instruções A/B no inventário mas NADA lido")
	t.check(not a.lido(0), "slot 0 (Instruções A) começa não lido")
	## Os dois itens iniciais são `0x83`/`0x84` (categoria **6**), e é por isso que USAR neles não
	## fazia nada: o de-para é 0x83 → doc 0 e 0x84 → doc 28.
	t.eq(Itens.doc_do_item(0x83), 0, "item 0x83 (Game Inst. A) é o documento 0")
	t.eq(Itens.doc_do_item(0x84), 28, "item 0x84 (Game Inst. B) é o documento 28")
	t.eq(Itens.doc_do_item(0x85), 0, "item 0x85 também é o documento 0 (`doc + 0x85`)")
	t.eq(Itens.doc_do_item(0xa3), 30, "item 0xa3 é o documento 30")
	t.eq(Itens.doc_do_item(0x21), -1, "erva não é documento")
	st.marcar_arquivo_lido(0x83)               ## USAR nas Instruções A
	a.abrir()
	t.eq(a.n_lidos(), 1, "depois de ler as Instruções A, ela conta")
	t.check(a.lido(0), "e o slot 0 fica lido")
	st.marcar_arquivo_lido(0x21)
	t.eq(a.n_lidos(), 1, "marcar uma ERVA não cria documento")
	for id in [0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
			0x90, 0x91, 0x92, 0x93, 0x94, 0x95]:
		st.marcar_arquivo_lido(id)
	a.abrir()
	t.eq(a.n_lidos(), 17, "17 documentos lidos")
	# confirmar em slot NÃO lido não entra na leitura
	a.sel = 30
	a.confirmar()
	t.check(not a.lendo, "Enter em slot não lido não abre nada")
	a.sel = 0
	t.check(a.aberto, "abrir() liga a tela")
	t.eq(a.sel, 0, "abre no primeiro documento")
	a.mover_grade(1, 0)
	t.eq(a.sel, 1, "D anda uma COLUNA (antes A/D não faziam nada na grade)")
	a.mover_grade(0, 1)
	t.eq(a.sel, 1 + MenuArquivo.COLUNAS_GRADE, "S anda uma LINHA (5 documentos)")
	a.mover_grade(-1, 0)
	t.eq(a.sel, MenuArquivo.COLUNAS_GRADE, "A volta uma coluna")
	# borda direita VIRA A PÁGINA mantendo a linha (é o que as capturas do jogo mostram)
	a.sel = 4                                  ## última coluna da 1ª linha
	a.mover_grade(1, 0)
	t.eq(a.pagina_grade(), 1, "D na última coluna vai para a página 2")
	t.eq(a.sel, 15, "e cai na PRIMEIRA coluna da mesma linha")
	a.mover_grade(-1, 0)
	t.eq(a.pagina_grade(), 0, "A na primeira coluna volta para a página 1")
	t.eq(a.sel, 4, "de volta na última coluna da mesma linha")
	t.eq(a.n_paginas_grade(), 3, "31 slots = 3 páginas de 15")
	a.sel = 0
	a.confirmar()
	t.check(a.lendo, "Enter entra no documento")
	var doc: Dictionary = a.docs[0]
	var n := int(doc.get("n_pages", 1))
	for _i in n + 3:
		a.virar_pagina(1)
	t.eq(a.pagina, n - 1, "virar até o fim para na última página (sem estourar)")
	for _i in n + 3:
		a.virar_pagina(-1)
	t.eq(a.pagina, 0, "voltar até o começo para na capa")
	a.mover_grade(1, 0)
	t.eq(a.pagina, 0, "no modo LEITURA a grade não se move")
	a.cancelar()
	t.check(a.aberto and not a.lendo, "ESC sai da leitura e fica na grade")
	a.cancelar()
	t.check(not a.aberto, "ESC de novo fecha a tela")

	# ── SOM DE ABRIR ≠ SOM DE FECHAR (defeito relatado; os dois usavam o id 9) ──
	## Ids medidos no `SLUS_009.23`:
	##   abrir a tela de status = **6** (`0x80023db8` com `ctx+0x04 = 0`; o `bne ..., 4` de
	##   `0x80023da4` é tomado e vale o `a0 = 6` do delay slot);
	##   fechar = **5** (`0x80066744`/`0x8006675c`, seguido do `ctx+0x10++` de `0x80066760`);
	##   id **9** = entrar no MAPA/ARQUIVO, não abrir o inventário.
	t.group("ARQUIVO / som de abrir e fechar")
	var sfx := Sfx.new()
	t.check(sfx.carregar(), "re3_se.json carrega")
	t.eq(sfx.acao_id("menu_confirmar"), 6, "abrir a tela de status = SE id 6 (0x80023db8)")
	t.eq(sfx.acao_id("menu_cancelar"), 5, "fechar a tela de status = SE id 5 (0x8006675c)")
	t.eq(sfx.acao_id("menu_abrir"), 9, "id 9 = entrar no MAPA/ARQUIVO (0x800666f0/0x80066728)")
	t.check(sfx.acao_wav("menu_cancelar") != sfx.acao_wav("menu_confirmar"),
		"e as AMOSTRAS são diferentes: fechar não soa como abrir")
	t.check(sfx.menu_status_abrir(), "menu_status_abrir() resolve uma amostra")
	var wav_abrir := sfx.ultimo_tocado()
	t.check(sfx.menu_fechar(), "menu_fechar() resolve uma amostra")
	t.check(sfx.ultimo_tocado() != wav_abrir,
		"abrir e fechar tocam WAV diferentes (%s vs %s)" % [wav_abrir, sfx.ultimo_tocado()])
	t.eq(sfx.ultimo_tocado(), sfx.acao_wav("menu_cancelar"),
		"fechar toca a amostra do id 5")

	# ── CURSOR DA GRADE COM O ARQUIVO POR CIMA (defeito relatado) ──
	## `0x8006c22c` (`bltz ctx+0x1c`) não emite o cursor quando a seleção é negativa — e ela é -2
	## enquanto o sub-estado 5 (ARQUIVO) está ativo. Pelo caminho de USAR um documento o jogo troca
	## para o kind 3, que tem outra rotina de desenho (`0x8006e3f8`) e não monta a grade.
	t.group("ARQUIVO / cursor da grade")
	var m := MenuStatus.new()
	m.arquivo = a
	a.fechar()
	m.selecao_botao = -1
	t.check(m.cursor_visivel(), "grade sem arquivo aberto: o cursor aparece")
	m.selecao_botao = 1
	t.check(not m.cursor_visivel(), "seleção nos botões: não aparece (ctx+0x1c < 0)")
	m.selecao_botao = -1
	a.abrir()
	t.check(not m.cursor_visivel(),
		"tela de arquivo por cima: o cursor da grade NÃO é desenhado")
	a.fechar()
	t.check(m.cursor_visivel(), "e volta a aparecer quando o arquivo fecha")

	# ── USAR num documento LIBERA O SLOT (relato do dono) ──
	## O que o EXE faz está medido e é OUTRO: `0x800676b8` faz `sltiu (cat-1), 6` (`0x80067708`) e,
	## com `cat >= 7`, o `beqz` de `0x8006770c` cai em `0x80067b50` = só `ctx+0x11 = 3` — o USE de
	## documento não mexe em slot. E o idioma que libera slot
	## (`sb zero,0 / sb zero,1 / sh zero,2` + MoveImage) existe em exatamente 9 sítios do `.text`
	## (`0x800679e8` cura, `0x80064a50` baú, 7 na combinação), **nenhum** no caminho de documento.
	## Liberar é **comportamento confirmado pelo dono do repo (observação de jogo), endereço não
	## localizado** — desvio declarado.
	t.group("ARQUIVO / usar documento libera o slot")
	var st2 := GameState.new()
	st2.novo_jogo()
	var a2 := MenuArquivo.new()
	a2.carregar(st2)
	var m2 := MenuStatus.new()
	m2.set("_state", st2)
	m2.arquivo = a2
	## Carga de jogo novo (`0x800a018c`): Hand Gun, Reloading Tool e as **duas Instruções**
	## (`0x83` no slot 2, `0x84` no slot 3) — as duas são categoria **6** no descritor `0x800a0514`.
	t.eq(int(st2.main_slots[2].get("id", 0)), 0x83, "slot 2 do jogo novo = Instruções A (0x83)")
	t.eq(int(st2.main_slots[3].get("id", 0)), 0x84, "slot 3 do jogo novo = Instruções B (0x84)")
	t.check(Itens.eh_documento(0x83) and Itens.eh_documento(0x84),
		"eh_documento cobre as duas faixas (cat 6 inicial e cat 7 de 0x85..0xa3)")
	var ocupados_antes := st2.item_count()
	t.check(not st2.arquivo_lido(0x83), "as Instruções A começam NÃO lidas")
	m2.cursor = 2
	var r2 := String(m2.call("_usar"))
	t.check(r2.begins_with("leu o documento"), "USAR na Instrução A lê o documento (%s)" % r2)
	t.eq(int(st2.main_slots[2].get("id", 0)), 0, "e o SLOT 2 fica vazio (id = 0)")
	t.eq(int(st2.main_slots[2].get("qtd", 0)), 0, "quantidade zerada")
	t.eq(int(st2.main_slots[2].get("flags", 0)), 0, "flags zeradas (slot livre de verdade)")
	t.eq(st2.item_count(), ocupados_antes - 1, "um slot ocupado a menos que antes")
	t.eq(st2.find_by_id(0), 2, "o 1º slot livre passa a ser o 2 (o que o documento ocupava)")
	## O CONHECIMENTO fica: o documento continua na tela de ARQUIVO, no slot fixo dele.
	t.check(st2.arquivo_lido(0x83), "o documento continua LIDO depois de sair do inventário")
	t.check(st2.arquivo_lido(0x85),
		"e lido pelo item canônico (0x83 -> doc 0 -> 0x85), como marcar_arquivo_lido guarda")
	a2.abrir()
	t.eq(a2.docs.size(), 31, "a grade de documentos continua com os 31 slots fixos")
	t.check(a2.lido(0), "o documento 0 aparece LIDO na grade de arquivo")
	t.eq(a2.n_lidos(), 1, "e é o único lido")
	a2.ir_para_doc(0)
	t.check(a2.lendo, "dá para ABRIR a leitura dele mesmo sem o item no inventário")
	## a Instrução B (0x84 -> doc 28) segue o mesmo caminho, e é o outro extremo do de-para
	m2.cursor = 3
	m2.call("_usar")
	t.eq(int(st2.main_slots[3].get("id", 0)), 0, "USAR na Instrução B também libera o slot")
	t.check(st2.arquivo_lido(0x84), "e ela fica lida (doc 28)")
	t.eq(st2.item_count(), ocupados_antes - 2, "dois slots livres a mais que no início")
	## um documento da faixa CAT 7 (0x85..0xa3), o caso comum
	st2.add_item(0x8a, 1)
	var onde := st2.find_by_id(0x8a)
	m2.cursor = onde
	m2.call("_usar")
	t.eq(int(st2.main_slots[onde].get("id", 0)), 0, "documento de cat 7 (0x8a) também libera o slot")
	t.check(st2.arquivo_lido(0x8a), "e fica lido")
	## item que NÃO é documento não pode ser afetado por esta regra
	m2.cursor = 0
	t.eq(int(st2.main_slots[0].get("id", 0)), 0x03, "slot 0 continua com a Hand Gun")
	m2.free()
	a2.free()

	# ── A TRILHA NÃO PARA COM O INVENTÁRIO ABERTO ──
	## Relato do dono: "entrar no inventário pausa o game (trilha também)". Pausar o MUNDO está
	## certo — no EXE abrir a tela faz `task_suspend(0)` (`0x8006d97c`) e fechar faz
	## `task_resume(0)` (`0x8006e248`), os dois únicos sítios do `.text`; no port isso é "não chamar
	## `mundo.tick`". Parar a BGM não: no PS1 ela é SPU/CD e roda fora da task do mundo.
	##
	## **MEDIDO na cena real** (`godot --path port --script res://dev/diag_bgm_menu.gd`): abrindo a
	## tela pelo bit MENU do pad e deixando 180 quadros, `bgm_player.playing = true`,
	## `stream_paused = false` e a posição de leitura anda **2,2814 s** (contra 0,0232 s em 1 quadro
	## fora do menu) — a trilha **NÃO para**. `get_tree().paused = false` e `Engine.time_scale = 1`
	## em todas as amostras. Não reproduzi o defeito.
	##
	## O que este teste protege é o CAMINHO: nenhum arquivo da tela pode mexer na BGM nem pausar a
	## árvore. É guarda estática porque no harness (RefCounted, fora da árvore) `play()` não roda.
	t.group("ARQUIVO / a trilha continua tocando")
	for rel: String in ["res://present/menu_status.gd", "res://present/menu_arquivo.gd",
			"res://present/ecg.gd"]:
		var src := FileAccess.get_file_as_string(rel)
		t.check(src != "", "%s carrega" % rel)
		for proibido: String in ["parar_bgm", "bgm_player", "pediu_parar_bgm",
				"time_scale", "get_tree().paused"]:
			t.check(not src.contains(proibido),
				"%s não usa `%s` (a tela não mexe na trilha)" % [rel.get_file(), proibido])
	## O `screen.gd` toca em `bgm_player` de propósito, mas só no ciclador de faixa F5/F6
	## (`_ciclar_trilha`), que é ferramenta de diagnóstico — e em nenhum caminho de menu.
	var src_scr := FileAccess.get_file_as_string("res://present/screen.gd")
	t.check(not src_scr.contains("parar_bgm"), "screen.gd não chama parar_bgm em lugar nenhum")
	t.check(not src_scr.contains("time_scale") and not src_scr.contains("get_tree().paused"),
		"screen.gd não pausa a árvore nem mexe no time_scale")
	var i_ciclar := src_scr.find("func _ciclar_trilha")
	t.check(i_ciclar > 0, "screen.gd tem o ciclador de faixa F5/F6")
	t.check(src_scr.find("bgm_player") > i_ciclar,
		"e o único uso de bgm_player está DENTRO dele (não no caminho do menu)")
	## `free()` explícito: `MenuStatus`/`MenuArquivo`/`Sfx` são Nodes criados FORA da árvore (o
	## harness é `RefCounted`), então ninguém os coleta e o motor reclama de vazamento no fim.
	m.free()
	sfx.free()
	a.free()
	return true
