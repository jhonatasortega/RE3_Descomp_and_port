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
	a.abrir()
	t.eq(a.docs.size(), 0,
		"jogo novo tem as Instruções A/B no inventário mas NENHUM documento no arquivo")
	st.marcar_arquivo_lido(0x85)
	a.abrir()
	t.eq(a.docs.size(), 1, "depois de ler as Instruções A, ela aparece")
	st.marcar_arquivo_lido(0x21)
	a.abrir()
	t.eq(a.docs.size(), 1, "marcar uma ERVA não cria documento (só categoria 7)")
	for id in [0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
			0x90, 0x91, 0x92, 0x93, 0x94, 0x95]:
		st.marcar_arquivo_lido(id)
	a.abrir()
	t.eq(a.docs.size(), 17, "17 documentos lidos entram na lista")
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
	t.eq(a.n_paginas_grade(), 2, "17 documentos = 2 páginas de 15")
	a.sel = 0
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
	return true
