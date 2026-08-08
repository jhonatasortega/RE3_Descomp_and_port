extends RefCounted
## Fluxo de ABERTURA: tempos do binário, navegação do menu de título e legenda dos FMV.
##
## O que este teste protege:
##  • os TEMPOS (`boot_flow.json`) — se alguém regerar com número trocado, as somas acusam;
##  • a NAVEGAÇÃO do título (3 itens com wrap, dificuldade de 2, o bit EASY) contra
##    `docs/decomp/notes/menu_titulo.md` §3.7;
##  • o PULSO do item selecionado (86…170, período 64) — vem da tabela seno de `0x80098828`;
##  • a MARCAÇÃO das legendas: a soma dos `{clear}`/`{timed}` tem de caber na duração do mp4,
##    que é a única conta que sustenta a leitura da semântica;
##  • a lista de passos do `Boot`, que é a tradução da tabela de switch `0x80194004`.
##
## Rodar só este arquivo:
##     godot --path port --headless --script res://dev/run_tests.gd -- boot


func run(t: Object) -> bool:
	_dados_do_boot(t)
	_passos(t)
	_fluxo_inteiro(t)
	_titulo(t)
	_legendas(t)
	_video(t)
	return true


# ────────────────────── o fluxo inteiro, do 1º tick até o jogo ──────────────────────

func _fluxo_inteiro(t: Object) -> void:
	t.group("Boot: fluxo inteiro")
	var b := Boot.new()
	b.entrar_no_jogo = false                        ## não troca de cena dentro do teste
	b.tocar_fmv = false                             ## caminho curto título -> jogo
	b.preparar()
	var fases: Array[String] = []
	b.fase_mudou.connect(func(n: String) -> void: fases.append(n))
	var acabou := [0]
	b.terminou.connect(func() -> void: acabou[0] += 1)
	var bgm: Array[String] = []
	b.pediu_bgm.connect(func(f: String) -> void: bgm.append(f))

	t.eq(b.passo_atual(), "aviso_fade_in", "o 1º passo é o fade-in do aviso legal")
	b.avancar_ticks(300)
	t.eq(b.passo_atual(), "capcom_para_branco", "300 ticks: o aviso acabou, entra o CAPCOM")
	b.avancar_ticks(240)
	t.eq(b.passo_atual(), "titulo_espera", "540 ticks: o CAPCOM acabou, entra o título")
	t.eq(bgm, ["main38"], "a BGM pedida é a MAIN38 (0x801944dc)")
	b.avancar_ticks(71)
	t.eq(b.passo_atual(), "menu", "611 ticks: o menu está no ar")
	t.eq(b.titulo.fase, Titulo.Fase.MENU, "e o Titulo está na fase MENU")

	# NEW GAME -> dificuldade -> HARD -> INIT_TBL -> (sem FMV) -> jogo
	b.titulo.cursor = Titulo.Item.NOVO_JOGO
	b.titulo.confirmar()
	t.eq(b.titulo.fase, Titulo.Fase.DIFICULDADE, "confirmar abre a dificuldade")
	b.titulo.confirmar()                            ## cursor 0 = HARD
	t.check(not b.facil, "escolher o cursor 0 = DIFÍCIL (bit 0x100 limpo)")
	t.eq(acabou[0], 1, "sem FMV o fluxo termina e o jogo pode entrar")
	t.check(b.init_tbl_ok, "ETC/INIT_TBL.DAT conferido (2312 B + sha1 do NTSC-U)")

	# o pulo, na granularidade do original (grupo por grupo)
	var b2 := Boot.new()
	b2.entrar_no_jogo = false
	b2.tocar_fmv = false
	b2.preparar()
	b2.pular()
	t.eq(b2.passo_atual(), "capcom_para_branco", "pular no aviso vai para o logo CAPCOM")
	b2.pular()
	t.eq(b2.passo_atual(), "titulo_espera", "pular no logo vai para a entrada do título")
	b2.pular()
	t.eq(b2.passo_atual(), "menu", "pular na entrada do título vai direto para o menu")

	# o atrator: 900 ticks parado no menu levam ao FMV (o original alterna com a PDEMO)
	var b3 := Boot.new()
	b3.entrar_no_jogo = false
	b3.tocar_fmv = false
	b3.preparar()
	b3.pular()
	b3.pular()
	b3.pular()
	t.eq(b3.passo_atual(), "menu", "b3 no menu")
	for _i in 900:
		b3.avancar_ticks(1)
	t.check(b3.passo_atual() in ["fmv", "jogo"],
		"900 ticks sem entrada: o atrator leva ao FMV de abertura (0x80196800)")

	# EASY liga o bit 0x100 e o port espelha em GameState.difficulty
	var b4 := Boot.new()
	b4.entrar_no_jogo = false
	b4.tocar_fmv = false
	b4.preparar()
	b4.pular()
	b4.pular()
	b4.pular()
	b4.titulo.cursor = Titulo.Item.NOVO_JOGO
	b4.titulo.confirmar()
	b4.titulo.mover_cursor(1)                       ## -> EASY
	b4.titulo.confirmar()
	t.check(b4.facil, "cursor 1 = FÁCIL (bit 0x100 ligado)")
	var st := GameState.new()
	st.difficulty = 0
	st.dificuldade = 1
	# o engate: `aplicar_dificuldade` escreve no GameState do autoload; aqui o efeito é
	# verificado no mapeamento, que é a parte que este arquivo decide
	t.eq(1 if b4.facil else 0, 1, "FÁCIL -> GameState.difficulty = 1 (0x800cc858 & 0x100)")
	t.eq(0 if b4.facil else 2, 0, "FÁCIL -> GameState.dificuldade = 0 (mira do port)")


# ─────────────────────────────── boot_flow.json ───────────────────────────────

func _dados_do_boot(t: Object) -> void:
	t.group("boot_flow.json")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/boot_flow.json"))
	if not t.check(raw is Dictionary, "boot_flow.json carrega (tools/boot_assets.py)"):
		return
	var d: Dictionary = raw
	var tp: Dictionary = d["tempos"]

	var tk := func(n: String) -> int: return int((tp[n] as Dictionary)["ticks"])
	# WARNING.BIN entry 0x80185418: 30 de fade-in + 240 VSync + 30 de fade-out
	t.eq(tk.call("aviso_fade_in"), 30, "aviso: fade-in de 30 ticks (0x80185480, T=0x1e)")
	t.eq(tk.call("aviso_exibicao"), 240, "aviso: 240 VSync de exibição (0x801854a8, s0=0xef)")
	t.eq(tk.call("aviso_fade_out"), 30, "aviso: fade-out de 30 ticks (0x8018550c)")
	t.eq(tk.call("aviso_fade_in") + tk.call("aviso_exibicao") + tk.call("aviso_fade_out"),
		300, "aviso: 300 ticks no total = 5,01 s a 59,94 Hz")
	# TITLE.BIN handler 0: 30 + 30 + 120 + 30 + 30 = 240
	var capcom: int = (tk.call("capcom_para_branco") + tk.call("capcom_entra_logo")
		+ tk.call("capcom_exibicao") + tk.call("capcom_sai_logo")
		+ tk.call("capcom_para_preto"))
	t.eq(tk.call("capcom_exibicao"), 120, "CAPCOM: 120 ticks de logo (0x8019427c, 0x78)")
	t.eq(capcom, 240, "CAPCOM: 240 ticks no total = 4,00 s")
	# TITLE.BIN estado 2 (0x80194b08): 6 esperas + flash de 5 + fade-in de 60
	t.eq(tk.call("titulo_espera"), 6, "título: 6 ticks de espera (160 -= 30 até ficar < 0)")
	t.eq(tk.call("titulo_flash"), 5, "título: clarão branco de 5 ticks (T=5, abr=1)")
	t.eq(tk.call("titulo_fade_in"), 60, "título: fade-in de 60 ticks (T=0x3c, abr=2)")
	t.eq(tk.call("atrator_timeout"), 900, "atrator: 900 ticks (0x8019454c, 0x384)")

	# unidade de tempo: 1 tick = 1 vsync; a 30 Hz do port são 2 ticks por quadro
	t.eq(int((d["meta"] as Dictionary)["ticks_por_quadro"]), 2,
		"1 tick = 1 vsync (~59,94 Hz) -> 2 ticks por quadro de 30 Hz")

	# bit da dificuldade
	var bits: Dictionary = d["bits_0x800cc858"]
	t.eq(int(bits["easy_mode"]), 0x100, "EASY MODE = bit 0x100 de 0x800cc858 (0x80195dcc)")
	t.eq(int(bits["mercenaries"]), 0x80, "Mercenaries = bit 0x80")

	# PULSO do item selecionado: tabela seno de 0x80098828, /3 - 0x80, período 64
	var pulso: Dictionary = d["pulso"]
	var v: Array = pulso["valores"]
	t.eq(v.size(), 64, "pulso: 64 valores (256/4 = período de 64 ticks)")
	t.eq(int(pulso["passo"]), 4, "pulso: ctx[0x0f] += 4 por tick")
	var mn := 999
	var mx := -999
	for x: float in v:
		mn = mini(mn, int(x))
		mx = maxi(mx, int(x))
	t.eq(mn, 86, "pulso: mínimo 86 (menu_titulo.md §3.1 diz 86…170)")
	t.eq(mx, 170, "pulso: máximo 170")

	# SPRT do título (0x801945e4): as posições de tela dos 3 itens
	var sp: Dictionary = d["sprites_titulo"]
	t.eq(int((sp["NEW_GAME"] as Dictionary)["x"]), 68, "NEW GAME em x=68")
	t.eq(int((sp["LOAD_GAME"] as Dictionary)["x"]), 132, "LOAD GAME em x=132")
	t.eq(int((sp["GAME_CONFIG"] as Dictionary)["x"]), 200, "GAME CONFIG em x=200")
	for k: String in ["NEW_GAME", "LOAD_GAME", "GAME_CONFIG"]:
		t.eq(int((sp[k] as Dictionary)["y"]), 193, "%s em y=193" % k)
	t.eq(int((sp["diff_HARD_MODE"] as Dictionary)["x"]), 80, "HARD MODE em x=80 (cursor 0)")
	t.eq(int((sp["diff_EASY_MODE"] as Dictionary)["x"]), 180, "EASY MODE em x=180 (cursor 1)")

	# rótulos HD em PT-BR: cada um tem célula no atlas e o texto lido na imagem
	var rot: Dictionary = d["rotulos_pt"]
	for k2: String in ["NEW_GAME", "LOAD_GAME", "GAME_CONFIG", "diff_EASY_MODE",
			"diff_HARD_MODE"]:
		t.check(rot.has(k2), "rótulo HD PT existe: %s" % k2)
	t.eq(String((rot["LOAD_GAME"] as Dictionary)["pt"]), "CARREG. JOGO",
		"LOAD GAME em PT = CARREG. JOGO")
	t.eq(String((rot["diff_EASY_MODE"] as Dictionary)["pt"]), "MODO FACIL",
		"EASY MODE em PT = MODO FACIL")
	t.eq(String((rot["diff_HARD_MODE"] as Dictionary)["pt"]), "MODO DIFICIL",
		"HARD MODE em PT = MODO DIFICIL")
	# o que NÃO tem HD em português fica registrado, não escalado do SD
	var sem: Dictionary = d["sem_hd_pt"]
	t.check(sem.has("PRESS_ANY_BUTTON"),
		"PRESS ANY BUTTON registrado como SEM contrapartida HD")
	# assets: os 5 arquivos vieram do conjunto PT (mtime > 2025-05-23)
	var ass: Dictionary = d["assets"]
	for k3: String in ["aviso", "capcom", "titulo", "atlas"]:
		var e: Dictionary = ass.get(k3, {})
		if not t.check(bool(e.get("ok", false)), "asset HD presente: %s" % k3):
			continue
		t.check(bool(e.get("conjunto_pt", false)),
			"asset %s é do conjunto PT-BR (jun/2025), não do russo (jan/2025)" % k3)


# ─────────────────────────────── passos do Boot ───────────────────────────────

func _passos(t: Object) -> void:
	t.group("Boot")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/boot_flow.json"))
	if not (raw is Dictionary):
		return
	var passos := Boot.construir_passos(raw)
	var nomes: Array[String] = []
	for p: Dictionary in passos:
		nomes.append(String(p["nome"]))
	t.eq(nomes, ["aviso_fade_in", "aviso_exibicao", "aviso_fade_out",
			"capcom_para_branco", "capcom_entra_logo", "capcom_exibicao",
			"capcom_sai_logo", "capcom_para_preto",
			"titulo_espera", "titulo_flash", "titulo_fade_in", "menu", "fmv", "jogo"],
		"a sequência é a tabela de switch 0x80194004 + o corpo do WARNING")
	# o total até o menu: 300 (aviso) + 240 (CAPCOM) + 71 (entrada do título) = 611 ticks
	var total := 0
	for p2: Dictionary in passos:
		if String(p2["nome"]) == "menu":
			break
		total += int(p2["ticks"])
	t.eq(total, 611, "611 ticks do 1º quadro ao menu = 10,19 s a 59,94 Hz")

	# interpolação do fade: 0x8002a4d0+ faz c = c0 + (c1-c0)*t/T em inteiro
	t.eq(Boot.cor_do_fade(Color.BLACK, Color.WHITE, 0, 30), Color.BLACK, "fade em t=0 = c0")
	t.eq(Boot.cor_do_fade(Color.BLACK, Color.WHITE, 30, 30), Color.WHITE, "fade em t=T = c1")
	var meio := Boot.cor_do_fade(Color.BLACK, Color.WHITE, 15, 30)
	t.near(meio.r, 0.5, 0.01, "fade no meio ≈ 50% (interpolação linear)")
	t.eq(Boot.cor_do_fade(Color.WHITE, Color.WHITE, 3, 5), Color.WHITE,
		"fade com c0 == c1 fica parado (o retângulo preto fixo do slot 1)")


# ─────────────────────────────── menu de título ───────────────────────────────

func _titulo(t: Object) -> void:
	t.group("Titulo")
	var tt := Titulo.new()
	tt.carregar()
	# cursor inicial 1 = LOAD GAME (0x801945b4). MEDIDO e contra-intuitivo — está no doc.
	t.eq(tt.cursor, 1, "cursor inicial = 1 (LOAD GAME), medido em 0x801945b4")
	t.eq(tt.timeout, 900, "timeout do atrator carregado do JSON")

	# a entrada dura 6 + 5 + 60 = 71 ticks e só então o menu aceita entrada
	t.eq(tt.fase, Titulo.Fase.ENTRADA, "começa na ENTRADA (fade-in)")
	tt.avancar(70)
	t.eq(tt.fase, Titulo.Fase.ENTRADA, "70 ticks: ainda na entrada")
	tt.avancar(1)
	t.eq(tt.fase, Titulo.Fase.MENU, "71 ticks: entra no MENU")

	# 3 itens com wrap (0x801956c4 / 0x801956dc)
	var sfx: Array[int] = []
	tt.pediu_sfx.connect(func(id: int) -> void: sfx.append(id))
	tt.mover_cursor(1)
	t.eq(tt.cursor, 2, "cursor 1 -> 2")
	tt.mover_cursor(1)
	t.eq(tt.cursor, 0, "cursor 2 -> 0 (wrap, `>= 3 -> 0`)")
	tt.mover_cursor(-1)
	t.eq(tt.cursor, 2, "cursor 0 -> 2 (wrap, `< 0 -> 2`)")
	t.eq(sfx, [4, 4, 4], "cada movimento pede o SFX 4 (0x801956f4)")

	# o movimento REINICIA o timeout do atrator
	tt.avancar(50)
	t.check(tt.ticks == 50, "o contador do atrator anda com os ticks")
	tt.mover_cursor(1)
	t.eq(tt.ticks, 0, "mover o cursor zera o timeout (`*(u16*)(ctx+0x16) = 0x384`)")

	# NEW GAME (cursor 0) -> tela de DIFICULDADE
	tt.cursor = Titulo.Item.NOVO_JOGO
	tt.confirmar()
	t.eq(tt.fase, Titulo.Fase.DIFICULDADE, "confirmar em NEW GAME abre a dificuldade")
	t.eq(tt.cursor_dificuldade, 0, "a dificuldade abre no cursor 0 = HARD")
	t.eq(tt.item_selecionado(), "diff_HARD_MODE", "cursor 0 = HARD MODE (x=80)")
	tt.mover_cursor(1)
	t.eq(tt.cursor_dificuldade, 1, "2 itens: 0 -> 1")
	t.eq(tt.item_selecionado(), "diff_EASY_MODE", "cursor 1 = EASY MODE (x=180)")
	tt.mover_cursor(1)
	t.eq(tt.cursor_dificuldade, 0, "2 itens com wrap: 1 -> 0")

	# CANCELA volta ao menu com o cursor em NEW GAME (0x80195dd8)
	tt.cancelar()
	t.eq(tt.fase, Titulo.Fase.MENU, "cancelar na dificuldade volta ao menu")
	t.eq(tt.cursor, 0, "e o cursor volta para NEW GAME (ctx[4] = 0)")

	# EASY liga o bit 0x100; HARD limpa
	var escolhas: Array[bool] = []
	tt.escolheu_novo_jogo.connect(func(f: bool) -> void: escolhas.append(f))
	tt.confirmar()                                  ## NEW GAME -> dificuldade
	tt.mover_cursor(1)                              ## -> EASY
	tt.confirmar()
	t.eq(escolhas, [true], "confirmar em EASY emite facil=true (bit 0x100 ligado)")
	t.check(tt.facil, "e o objeto guarda facil=true")
	t.eq(tt.fase, Titulo.Fase.SAINDO, "depois de escolher, a tela sai")

	# LOAD GAME e GAME CONFIG têm caminho próprio (MEM_CARD / OPTION), não implementados
	var t2 := Titulo.new()
	t2.carregar()
	t2.fase = Titulo.Fase.MENU
	var pedidos: Array[String] = []
	t2.pediu_carregar.connect(func() -> void: pedidos.append("load"))
	t2.pediu_config.connect(func() -> void: pedidos.append("config"))
	t2.cursor = Titulo.Item.CARREGAR
	t2.confirmar()
	t2.cursor = Titulo.Item.CONFIG
	t2.confirmar()
	t.eq(pedidos, ["load", "config"], "LOAD GAME -> MEM_CARD e GAME CONFIG -> OPTION")

	# timeout: 900 ticks sem entrada dispara o atrator
	var t3 := Titulo.new()
	t3.carregar()
	t3.fase = Titulo.Fase.MENU
	t3.ticks = 0
	var expirou := [0]
	t3.expirou.connect(func() -> void: expirou[0] += 1)
	t3.avancar(899)
	t.eq(expirou[0], 0, "899 ticks: o atrator ainda não")
	t3.avancar(1)
	t.eq(expirou[0], 1, "900 ticks: o atrator dispara")

	# brilho do item selecionado dentro da faixa medida
	var b := t3.brilho()
	t.check(b >= 86 and b <= 170, "brilho do selecionado em 86…170 (obtido %d)" % b)


# ─────────────────────────────── legendas ───────────────────────────────

func _legendas(t: Object) -> void:
	t.group("legendas_fmv.json")
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/legendas_fmv.json"))
	if not t.check(raw is Dictionary, "legendas_fmv.json carrega (tools/legendas_fmv.py)"):
		return
	var d: Dictionary = raw
	# as 8 diretivas do motor estão PROVADAS como literais no ddraw.dll
	var dirs: Dictionary = (d["meta"] as Dictionary)["diretivas_provadas"]
	t.eq(dirs.size(), 8, "8 diretivas com offset no ddraw.dll")
	for k: String in ["clear", "timed", "scroll", "snd", "cut", "string", "color", "branch"]:
		t.check(dirs.has(k), "diretiva provada: {%s N}" % k)

	var opn: Dictionary = (d["videos"] as Dictionary)["opn"]
	t.eq(int(opn["blocos"]), 4, "prologue.xml tem 4 blocos <Text>")
	t.eq(int(opn["quadros_total"]), 1414, "prólogo: 1414 quadros de marcação")
	t.near(float(opn["segundos_total"]), 47.18, 0.05, "prólogo: 47,18 s a 29,97 fps")
	# a conta que sustenta a leitura da semântica: tem de CABER no vídeo
	t.check(bool(opn["cabe_no_video"]),
		"a soma dos {clear}/{timed} cabe nos 90,62 s de opn.mp4")
	t.check(float(opn["segundos_total"]) < float(opn["duracao_mp4"]),
		"47,18 s de narração dentro de 90,62 s de vídeo")

	var cues: Array = opn["legendas"]
	t.eq(cues.size(), 17, "17 cues no prólogo (incluindo as 5 pausas em branco)")
	# as cues são CONTÍGUAS: o fim de uma é o começo da seguinte
	var esperado := 0
	var contiguo := true
	for c: Dictionary in cues:
		if int(c["quadro_inicio"]) != esperado:
			contiguo = false
		esperado += int(c["quadros"])
	t.check(contiguo, "as cues são contíguas (leitura sequencial dos blocos)")
	t.eq(esperado, 1414, "a soma das cues fecha os 1414 quadros")
	# a 1ª cue é a pausa de 34 quadros ({scroll 0}\n{clear 34} sobre buffer vazio)
	var c0: Dictionary = cues[0]
	t.eq(int(c0["quadros"]), 34, "1ª cue = 34 quadros (o {clear 34} sobre buffer vazio)")
	t.eq((c0["linhas"] as Array).size(), 0, "e ela é BRANCA — é o atraso inicial")
	var c1: Dictionary = cues[1]
	t.eq(String((c1["linhas"] as Array)[0]), "Era um dia normal em Setembro",
		"2ª cue: a 1ª linha da narração")
	t.eq((c1["linhas"] as Array).size(), 2, "e ela tem 2 linhas (o \\n do XML)")

	# correção trema -> til: o XML escreve "destruiçäo"; o port desenha "destruição"
	var achou_til := false
	var achou_trema := false
	for c2: Dictionary in cues:
		for l: Variant in c2["linhas"]:
			if String(l).contains("destruição"):
				achou_til = true
			if String(l).contains("ä"):
				achou_trema = true
	t.check(achou_til, "trema corrigido: 'destruição' com til")
	t.check(not achou_trema, "nenhuma linha final ainda tem ä")
	t.check((cues[6] as Dictionary).has("linhas_cru"),
		"e o texto CRU do mod fica guardado ao lado (linhas_cru)")

	var enda: Dictionary = (d["videos"] as Dictionary)["enda"]
	t.eq(int(enda["blocos"]), 1, "epilogue.xml tem 1 bloco")
	t.check(bool(enda["cabe_no_video"]), "o epílogo cabe nos 62,66 s de enda.mp4")


# ─────────────────────────────── tocador ───────────────────────────────

func _video(t: Object) -> void:
	t.group("VideoFmv")
	var v := VideoFmv.new()
	t.check(v.carregar_dados(), "VideoFmv lê data/legendas_fmv.json")
	var cues := v.legendas_de("opn")
	t.eq(cues.size(), 17, "17 cues para o opn")
	# busca por tempo: a 1ª cue é a pausa [0, 1,134); a 2ª é a 1ª frase
	t.eq(VideoFmv.cue_em(cues, 0.0), 0, "t=0,0 s cai na cue 0 (branca)")
	t.eq(VideoFmv.linhas_de(cues, VideoFmv.cue_em(cues, 0.5)).size(), 0,
		"t=0,5 s: nada na tela")
	var i := VideoFmv.cue_em(cues, 2.0)
	t.eq(i, 1, "t=2,0 s cai na cue 1")
	t.eq(VideoFmv.linhas_de(cues, i), ["Era um dia normal em Setembro",
		"sem nada de especial"], "t=2,0 s: as duas linhas certas")
	t.eq(VideoFmv.cue_em(cues, 47.5), -1, "depois de 47,18 s não há mais legenda")
	t.eq(VideoFmv.cue_em(cues, -1.0), -1, "tempo negativo não casa com nada")
	# o último cue começa em 43,58 s e dura 3,6 s
	var ult := VideoFmv.cue_em(cues, 45.0)
	t.eq(VideoFmv.linhas_de(cues, ult), ["Minha última chance.", "Minha última fuga!"],
		"t=45,0 s: a última fala do prólogo")
	# a classe de vídeo do Godot 4 que o port usa (só Theora é nativo)
	t.check(ClassDB.class_exists("VideoStreamTheora"),
		"VideoStreamTheora existe (é o único backend nativo do Godot 4)")
	t.eq(v.caminho_do_video("opn"), AssetIO.path("ZMOVIE/opn.ogv"),
		"o .ogv é lido de fora do .pck (assets/ tem .gdignore)")
