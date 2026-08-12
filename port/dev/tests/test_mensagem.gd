extends RefCounted
## CAIXA DE MENSAGEM: o dado das 169 salas, os índices que o binário usa e o comportamento da
## caixa (páginas, datilografia, seta, prompt SIM/NÃO).
##
## Por que cada bloco existe:
##
## 1. **A extração tem de fechar com o binário.** As mensagens de sala vivem em
##    `offset_table[13]` do RDT (provado em `0x8002fe34`: `lw $v1, 0x3c($v1)`), e o índice que o
##    AOT `sce 4` passa é `u16@payload+0`. Se o extrator mudar e um índice de AOT passar a
##    apontar para fora da lista da sala, o jogador vê caixa vazia — este teste pega isso antes.
## 2. **PT-BR sempre que existir** é regra do projeto. O mod cobre as 127 salas com seção MSG;
##    o teste trava a cobertura para que uma regressão do pipeline não faça o port cair no
##    inglês silenciosamente.
## 3. **Geometria**: as duas posições de caixa são medidas (`0x8002fdc4`+). Se alguém "arredondar"
##    para (32,184) o texto sai do lugar em relação ao original.
## 4. **A árvore de decisão da porta** (`0x80050d28`) é o caso mais fácil de errar: são 6 saídas
##    diferentes e duas delas leem a mensagem da SALA, não da pool. As âncoras `Key_Type 0x73`
##    (saída dos fundos) e `0x75` (chave S.T.A.R.S.) provam a fórmula `idx = key_type - 0x5F`.
## 5. **Texto não pode desaparecer**: em PT-BR as linhas são mais compridas que em inglês. O nó
##    pagina o excedente em vez de cortar — o teste confere que TODA mensagem cabe em páginas de
##    3 linhas e que a soma dos caracteres visíveis nunca é menor que a do texto do dado.


func run(t: Object) -> bool:
	t.group("mensagem")

	# ─────────────── 1. o dado existe e fecha com o censo da ferramenta ───────────────
	t.check(Mensagem.carregado(), "data/mensagens.json presente",
		"rode `NOSTALGIA_OUT=port python tools/mensagens.py --build`")
	if not Mensagem.carregado():
		return true
	var salas := Mensagem.salas_com_mensagem()
	t.eq(salas.size(), 127, "127 salas têm seção MSG (offset_table[13])")
	var total := 0
	for s: String in salas:
		total += Mensagem.n_da_sala(s)
	t.eq(total, 1128, "1128 mensagens de sala")

	# ─────────────── 2. PT-BR: cobertura e acentuação ───────────────
	var com_trema := 0
	var com_texto := 0
	var vazias := 0
	var com_til := 0
	for s: String in salas:
		for i in Mensagem.n_da_sala(s):
			var pt := Mensagem.texto_da_sala(s, i)
			if _sem_tags(pt).strip_edges() == "":
				vazias += 1                        # entrada vazia no próprio dado do jogo
				continue
			com_texto += 1
			if pt.contains("ä") or pt.contains("ö"):
				com_trema += 1
			if pt.contains("ã") or pt.contains("õ"):
				com_til += 1
	t.eq(com_trema, 0, "nenhum 'ä'/'ö' sobrou (o mod usa trema onde o PT-BR quer til)")
	t.check(com_til > 100, "o til chegou no texto (a normalização rodou)", "%d msgs" % com_til)
	t.eq(com_texto, 932, "932 mensagens de sala com texto de verdade")
	t.eq(vazias, 196, "196 entradas sem nada a mostrar (191 vazias no dado + 5 de sobra JP)")

	# âncoras de conteúdo: se o alinhamento sala↔XML escorregar, estas duas quebram
	t.check(Mensagem.texto_da_sala("R100", 0).contains("mapa"),
		"R100[0] é o mapa da área", Mensagem.texto_da_sala("R100", 0))
	t.check(Mensagem.texto_da_sala("R110", 0).contains("Brad"),
		"R110[0] é o Brad Vickers", Mensagem.texto_da_sala("R110", 0))

	# ─────────────── 3. as pools do EXE ───────────────
	t.check(Mensagem.texto_prompt(4).contains("nada"),
		"prompt[4] = 'Não tem mais nada' (0x800516a4, sce 11)", Mensagem.texto_prompt(4))
	t.check(Mensagem.texto_prompt(20).to_lower().contains("fundos"),
		"prompt[20] = saída dos fundos (âncora do key_type 0x73)", Mensagem.texto_prompt(20))
	t.check(Mensagem.texto_prompt(22).contains("S.T.A.R.S."),
		"prompt[22] = chave S.T.A.R.S. (âncora do key_type 0x75)", Mensagem.texto_prompt(22))
	t.check(Mensagem.texto_prompt(10).to_lower().contains("subir"),
		"prompt[10] = 'Quer subir?' (escada, 0x80050f68)", Mensagem.texto_prompt(10))
	t.check(Mensagem.texto_sistema(6).contains("{i:00}"),
		"sistema[6] = 'Você pegou: {item}' (0x8006a1d8)", Mensagem.texto_sistema(6))
	t.check(Mensagem.texto_sistema(0).contains("{sn}"),
		"sistema[0] = 'quer pegar?' com prompt SIM/NÃO", Mensagem.texto_sistema(0))
	# exame de item: sistema[16 + item_id] (0x80069380)
	var base := Mensagem.indice("item", "exame_base")
	t.eq(base, 16, "exame de item = sistema[16 + item_id]")
	t.check(Mensagem.texto_sistema(base + 0x01).to_lower().contains("faca"),
		"sistema[17] = exame da Faca (item 0x01)", Mensagem.texto_sistema(base + 1))

	# ─────────────── 4. a árvore de decisão da PORTA (0x80050d28) ───────────────
	# key_id sem o bit 0x80 -> porta não é trancada, nenhuma mensagem
	t.check(Mensagem.mensagem_de_porta(0x75, 0x00, 0x00, 0, false).is_empty(),
		"porta sem o bit 0x80 do key_id não mostra mensagem")
	# escada: bit 0x40 do campo +0x11, campo +0x0d == 4 sobe
	var esc := Mensagem.mensagem_de_porta(0, 0, 0x40, 4, false)
	t.eq(int(esc.get("idx", -1)), 10, "escada para CIMA = prompt[10]")
	t.eq(int(Mensagem.mensagem_de_porta(0, 0, 0x40, 0, false).get("idx", -1)), 11,
		"escada para BAIXO = prompt[11]")
	t.eq(int(Mensagem.mensagem_de_porta(0xFE, 0x80, 0, 0, false).get("idx", -1)), 17,
		"Key_Type 0xFE = prompt[17] (0x80050de8)")
	t.eq(int(Mensagem.mensagem_de_porta(0xFF, 0x80, 0, 0, false).get("idx", -1)), 18,
		"Key_Type 0xFF = prompt[18] (0x80050e24)")
	t.eq(int(Mensagem.mensagem_de_porta(0x75, 0x80, 0, 0, true).get("idx", -1)), 5,
		"com a chave = prompt[5] 'Você usou: {item}' (0x80050e44)")
	t.eq(int(Mensagem.mensagem_de_porta(0x75, 0x80, 0, 0, false).get("idx", -1)), 22,
		"sem a chave, Key_Type 0x75 = prompt[22] (0x75 - 0x5F)")
	t.eq(int(Mensagem.mensagem_de_porta(0x73, 0x80, 0, 0, false).get("idx", -1)), 20,
		"sem a chave, Key_Type 0x73 = prompt[20] (saída dos fundos)")
	var sala_msg := Mensagem.mensagem_de_porta(0x75, 0x80, 0x83, 0, false)
	t.eq(int(sala_msg.get("caixa", -1)), Mensagem.Caixa.SALA,
		"campo+0x11 com bit 0x80 -> mensagem DA SALA (a1=0x2000 em 0x80050ee4)")
	t.eq(int(sala_msg.get("idx", -1)), 3, "índice = campo+0x11 & 0x0F")

	# ─── 4b. as 453 portas do SCD, e a correlação STAGE ↔ texto (prova independente) ───
	# Se a fórmula `key_type - 0x5F` estivesse errada, o texto não bateria com o cenário.
	var ancoras := {
		# sala      : trecho que a mensagem de porta trancada tem de conter
		"R101": "fundos",       # armazém: a saída dos fundos (Key_Type 0x73 = Warehouse Key)
		"R119": "S.T.A.R.S.",   # delegacia: a porta do escritório da S.T.A.R.S. (0x75)
		"R301": "relógio",      # torre do relógio (0x78)
		"R400": "parque",       # parque Raccoon (0x7b)
		"R500": "TRATAMENTO",   # usina de tratamento (0x7e)
		"R106": "boutique",     # centro: a boutique (0x80)
	}
	for sala: String in ancoras:
		var achou := false
		var visto := ""
		for e: Dictionary in _portas(sala):
			var m := Mensagem.mensagem_de_porta(int(e.get("key_type", 0)), int(e.get("key_id", 0)),
				int(e.get("campo_11", 0)), int(e.get("door_type", 0)), false)
			if m.is_empty() or int(m.get("caixa", -1)) != Mensagem.Caixa.PROMPT:
				continue
			var txt := Mensagem.texto_prompt(int(m["idx"]))
			visto += txt + " | "
			if txt.contains(ancoras[sala]):
				achou = true
		t.check(achou, "%s: porta trancada fala de '%s'" % [sala, ancoras[sala]], visto)
	var portas := 0
	var com_msg := 0
	for sala: String in Mensagem.salas_com_porta():
		for e: Dictionary in _portas(sala):
			portas += 1
			if String(e.get("caixa", "")) != "":
				com_msg += 1
	t.eq(portas, 453, "as 453 portas do SCD estão no dado de mensagem")
	t.eq(com_msg, 62, "62 portas mostram mensagem (20 escadas + 42 trancadas)")

	# ─────────────── 5. todo AOT `sce 4` aponta para uma mensagem que EXISTE ───────────────
	var aots := 0
	var fora := 0
	var em_sala_sem_msg := 0
	var faltando: Array[String] = []
	for id: String in _listar_salas():
		var scd: Variant = AssetIO.json("STAGE%d/%s_scd.json" % [RoomData.stage_of(id), id])
		if not (scd is Dictionary):
			continue
		var n := Mensagem.n_da_sala(id)
		for m: Dictionary in (scd as Dictionary).get("messages", []):
			var d: Array = m.get("data", [])
			if d.size() < 2:
				continue
			var idx := int(d[0]) | (int(d[1]) << 8)
			aots += 1
			if n == 0:
				em_sala_sem_msg += 1
			elif idx >= n:
				fora += 1
				if faltando.size() < 12:
					faltando.append("%s aot idx=%d de %d" % [id, idx, n])
	t.check(aots > 200, "achei os AOT de mensagem no dump do SCD", "%d" % aots)
	t.eq(fora, 0, "nenhum AOT sce 4 aponta para além da lista da sala", str(faltando))
	t.eq(em_sala_sem_msg, 0, "nenhum AOT sce 4 em sala sem seção MSG")

	# ─────────────── 6. geometria MEDIDA ───────────────
	var cx := Mensagem.new()
	t.eq(cx.posicao_da_caixa(Mensagem.Caixa.PROMPT), Vector2i(34, 185),
		"caixa da pool 0 em (34,185) — 0x8002fdc4/0x8002fdcc")
	t.eq(cx.posicao_da_caixa(Mensagem.Caixa.SALA), Vector2i(34, 185),
		"mensagem de sala usa a mesma caixa (0x8002fe20/0x8002fe2c)")
	t.eq(cx.posicao_da_caixa(Mensagem.Caixa.SISTEMA), Vector2i(14, 173),
		"caixa da pool 1 em (14,173) — 0x8002fdf0/0x8002fdf8")
	t.eq(Mensagem.ALTURA_LINHA, 16, "altura de linha 16 (0x80030fb4: y += 0x10)")
	t.eq(Mensagem.LINHAS, 3, "3 linhas por página (epílogo em 0x80031cd8)")

	# ─────────────── 7. a caixa: páginas, datilografia, seta, prompt ───────────────
	t.check(cx.mostrar_da_sala("R110", 0), "abriu a mensagem R110[0]")
	t.check(cx.total_paginas() >= 2, "R110[0] tem {p} -> mais de uma página",
		"%d páginas" % cx.total_paginas())
	t.eq(cx.pagina(), 0, "abre na página 0")
	# o botão de ação primeiro PULA a datilografia, e só depois vira a página
	t.check(cx.acao(), "1º ação = pula a datilografia")
	t.eq(cx.pagina(), 0, "ainda na página 0 depois de pular a datilografia")
	t.check(cx.acao(), "2º ação = vira a página")
	t.eq(cx.pagina(), 1, "virou para a página 1")
	while cx.ativa:
		cx.acao()
		cx.acao()
	t.check(not cx.ativa, "a caixa fecha na última página")

	# prompt SIM/NÃO com opções vindas do dado ({op} de R110[1])
	t.check(cx.mostrar_da_sala("R110", 1), "abriu R110[1] (prompt de 2 opções)")
	cx.acao()                                  # pula a datilografia
	t.check(cx.esperando_resposta(), "R110[1] espera resposta ({sn} no dado)")
	t.check(cx.mover(1), "o direcional troca a opção")
	t.eq(cx.opcao_atual(), 1, "opção 1 selecionada")
	cx.acao()
	t.eq(cx.resposta(), 1, "a resposta sai como o índice da opção")

	# mensagem inexistente não abre caixa vazia
	t.check(not cx.mostrar_da_sala("R10D", 0), "sala sem seção MSG não abre caixa")
	t.check(not cx.mostrar_da_sala("R100", 99), "índice fora da lista não abre caixa")

	# ─────────────── 8. nada de texto perdido: tudo cabe em páginas de 3 linhas ───────────────
	var perdidas: Array[String] = []
	var maior_pag := 0
	var testadas := 0
	for s: String in salas:
		for i in Mensagem.n_da_sala(s):
			var txt := Mensagem.texto_da_sala(s, i)
			if txt.strip_edges() == "":
				continue
			if not cx.mostrar(txt, Mensagem.Caixa.SALA):
				continue
			testadas += 1
			maior_pag = maxi(maior_pag, cx.total_paginas())
			var visivel := 0
			for _p in cx.total_paginas():
				visivel += cx._chars_da_pagina()
				cx.acao()
				cx.acao()
			# o dado sem tags/quebras tem de caber no que a caixa mostra (a quebra por palavra
			# insere/retira espaços, então a comparação é por caracteres NÃO-brancos)
			var cru := _sem_tags(txt).replace(" ", "").replace("\n", "").length()
			if visivel + 2 < cru and perdidas.size() < 12:
				perdidas.append("%s[%d] %d de %d" % [s, i, visivel, cru])
	t.check(testadas > 800, "paginei as mensagens de sala", "%d" % testadas)
	t.eq(perdidas.size(), 0, "nenhuma mensagem perde texto na paginação", str(perdidas))
	t.check(maior_pag <= 8, "nenhuma mensagem estoura 8 páginas", "maior=%d" % maior_pag)

	cx.free()
	return true


func _portas(sala: String) -> Array:
	var v: Variant = Mensagem.portas_da_sala(sala)
	return v if v is Array else []


func _sem_tags(s: String) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		if s[i] == "{":
			var f := s.find("}", i)
			if f < 0:
				break
			i = f + 1
			continue
		out += s[i]
		i += 1
	return out


func _listar_salas() -> Array[String]:
	var out: Array[String] = []
	var g: Variant = AssetIO.json("room_graph.json")
	if g is Dictionary and (g as Dictionary).has("rooms"):
		for k: String in ((g as Dictionary)["rooms"] as Dictionary):
			out.append(k)
	if out.is_empty():
		for st in range(1, 8):
			var d := DirAccess.open("res://data/STAGE%d" % st)
			if d == null:
				continue
			for f in d.get_files():
				if f.ends_with("_scd.json"):
					out.append(f.trim_suffix("_scd.json"))
	out.sort()
	return out
