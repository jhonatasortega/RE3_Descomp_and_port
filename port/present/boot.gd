class_name Boot
extends Node2D
## FLUXO DE ABERTURA do RE3, do primeiro quadro até cair na sala inicial.
##
##     aviso legal  ->  logo CAPCOM  ->  TÍTULO (navegável)  ->  dificuldade
##     ->  INIT_TBL.DAT  ->  FMV de abertura (com legenda PT-BR)  ->  jogo (R10D)
##
## Fonte: `docs/decomp/notes/menu_titulo.md` §1..§3 e `port/data/boot_flow.json`
## (gerado por `tools/boot_assets.py`, que é onde vivem os números e os endereços).
##
## ── A CADEIA REAL, para comparar ──
## `crt0 0x80011b80` -> `main 0x80028f38` -> `init 0x800297fc` -> tarefa de boot
## `0x80029b94`, que carrega `WARNING` (ovl 1) em `0x80029c94`, espera o aperto de mão pelo
## byte `*(u8*)0x800d4433` e então carrega `TITLE` (ovl 0) em `0x80029cd8`. O `WARNING` FICA
## RESIDENTE e é ele que faz o fade-out **depois** de o título estar carregado — é por isso
## que a transição aviso->título não tem corte. Aqui isso é uma lista de passos com o mesmo
## número de ticks: o resultado na tela é o mesmo e não há duas tarefas para sincronizar.
##
## ── UNIDADE DE TEMPO (o ponto delicado) ──
## O que o binário conta é **tick de tarefa = 1 retraço vertical**: o divisor
## `*(u8*)0x800d442c` vale **1** (gravado em `0x80029870` e regravado pelo TITLE em
## `0x8019412c`), e `yield(1)` = `0x8003203c(1)` espera 1 vsync. Em NTSC isso é
## **60000/1001 = 59,94 Hz**. O port roda o gameplay a 30 Hz (`Clock.HZ`), ou seja **2 ticks
## por quadro de jogo** — mas esta cena não depende do `Clock`: ela conta tempo real na taxa
## medida, o que preserva a DURAÇÃO (aviso = 300 ticks = 5,01 s; CAPCOM = 240 = 4,00 s;
## atrator = 900 = 15,02 s). A contradição "30 vs 60 Hz" registrada em `menu_titulo.md` §10.1
## continua ABERTA; aqui ela é resolvida por conversão, não reescrevendo o número medido.
##
## ── O FADE ──
## Reprodução de `0x8002a35c` (início) + `0x8002a49c` (por quadro): um TILE de tela cheia
## `0x62` (retângulo monocromático **semitransparente**), com a cor interpolada em inteiro
## (`c = c0 + (c1-c0)*t/T` por componente) e o modo de blend vindo do `abr` do `DR_MODE`:
## **`abr=1` = fundo + primitiva (aditivo)**, **`abr=2` = fundo − primitiva (subtrativo)**.
## Aqui são dois `ColorRect` de 1280×960 com `CanvasItemMaterial` em `BLEND_MODE_ADD` e
## `BLEND_MODE_SUB` — a mesma operação, não uma imitação com alpha.
##
## ── O que é ESCOLHA do port, declarada ──
## • **Ordem de composição dos dois slots de fade simultâneos.** Na entrada do título o
##   original tem o slot 1 segurando um retângulo preto E o slot 0 rampando branco aditivo
##   por 5 ticks (`0x80194b08` sub 1). Qual desenha primeiro está na Ordering Table, que eu
##   **não li**. Desenho SUB e depois ADD, o que dá "preto -> clarão branco de 5 ticks ->
##   preto -> fade-in de 60 ticks". A DURAÇÃO é medida; a aparência do clarão é minha leitura.
## • **Pular.** Medido só para o logo CAPCOM: `0x8019432c` testa `0x800cc834 & 0x800`. O
##   aviso legal NÃO tem leitura de pad no caminho do `entry` (§2), e o sítio do FMV não foi
##   medido. `pulo_livre` (ligado) é afordância do port: qualquer botão pula a etapa.
## • **A sala inicial R10D** e a posição de spawn vêm de `present/screen.gd` (informadas pelo
##   usuário / medidas por varredura). O `INIT_TBL.DAT` é carregado e CONFERIDO (2312 B +
##   sha1), mas seu layout **não foi decodificado**, então ele não decide nada ainda.
## • **BGM do título** = `SOUND/MAIN38.BGM` + `MAIN38.VB` (`0x801944dc`, rótulo de debug
##   "OPTION BGM" é resíduo). Aqui a trilha é PEDIDA por sinal (`pediu_bgm`) para não
##   colidir com o trabalho de som em curso — o `Audio` não é tocado deste arquivo.
##
## Uso:
##     godot --path port res://scenes/boot.tscn
## Para virar a cena principal, `project.godot` -> `run/main_scene` (ver o relatório).

const LARGURA := 1280
const ALTURA := 960
## Taxa de TICK medida (1 tick = 1 retraço vertical NTSC). Não é `Clock.HZ`.
const TAXA_TICK := 60000.0 / 1001.0
const CAMINHO_JSON := "res://data/boot_flow.json"
const CENA_JOGO := "res://scenes/game.tscn"
const INIT_TBL_BYTES := 2312                   ## tamanho na tabela de arquivos 0x800946a4
const INIT_TBL_SHA1 := "bffeebee91922ed9b7171c460d8aba52d0428117"

enum Blend { NENHUM, ADITIVO, SUBTRATIVO }

signal fase_mudou(nome: String)
signal pediu_bgm(faixa: String)                ## "main38" — o engate do som fica com o Audio
signal pediu_sfx(id: int)
signal terminou()                              ## acabou a abertura; o jogo pode entrar

## Se `false`, a cena não troca para `game.tscn` no fim (usado pelo teste e pelo diagnóstico).
@export var entrar_no_jogo := true
## Toca o FMV de abertura. Desligar dá o caminho curto título -> jogo.
@export var tocar_fmv := true
## Qualquer botão pula a etapa corrente (afordância do port; ver o cabeçalho).
@export var pulo_livre := true

var passos: Array[Dictionary] = []
var passo := 0
var ticks := 0                                 ## ticks dentro do passo corrente
var facil := false
var init_tbl_ok := false

var titulo: Titulo
var video: VideoFmv
var _d: Dictionary = {}
var _fundos: Dictionary = {}                   ## nome -> Texture2D
var _add: ColorRect
var _sub: ColorRect
var _acumulado := 0.0
var _pad_antes := 0
var _fim := false


func _ready() -> void:
	preparar()


func preparar() -> void:
	## Monta a cena e arma o 1º passo. Separado do `_ready` para o teste poder dirigir o
	## fluxo inteiro sem árvore de cena (é o que permite verificar "chega no jogo" headless).
	if not passos.is_empty():
		return
	_carregar()
	_montar()
	_aplicar_passo()


func _carregar() -> void:
	if FileAccess.file_exists(CAMINHO_JSON):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_JSON))
		if raw is Dictionary:
			_d = raw
	if _d.is_empty():
		push_warning("Boot: %s ausente — rode `NOSTALGIA_OUT=port python "
			% CAMINHO_JSON + "tools/boot_assets.py`")
	passos = construir_passos(_d)
	for n: String in ["aviso", "capcom", "titulo"]:
		_fundos[n] = AssetIO.texture("BOOT/%s.webp" % n)


static func construir_passos(d: Dictionary) -> Array[Dictionary]:
	## A sequência, com a duração LIDA do JSON (que a leu do binário). Cada passo diz qual
	## fundo está no ar e qual fade está rodando — é a tradução direta da tabela de switch
	## `0x80194004` (CAPCOM) e do corpo de `WARNING.BIN`.
	var t: Dictionary = d.get("tempos", {})
	var f := func(nome: String) -> int:
		var e: Variant = t.get(nome)
		return int((e as Dictionary).get("ticks", 0)) if e is Dictionary else 0
	var P: Array[Dictionary] = [
		# ── WARNING.BIN (entry 0x80185418): fade-in, 240 VSync, fade-out ──
		{"nome": "aviso_fade_in", "ticks": f.call("aviso_fade_in"), "fundo": "aviso",
			"blend": Blend.SUBTRATIVO, "c0": Color.WHITE, "c1": Color.BLACK},
		{"nome": "aviso_exibicao", "ticks": f.call("aviso_exibicao"), "fundo": "aviso",
			"blend": Blend.NENHUM},
		{"nome": "aviso_fade_out", "ticks": f.call("aviso_fade_out"), "fundo": "aviso",
			"blend": Blend.SUBTRATIVO, "c0": Color.BLACK, "c1": Color.WHITE},
		# ── TITLE.BIN handler 0 (0x80194160), switch 0x80194004: o logo CAPCOM ──
		{"nome": "capcom_para_branco", "ticks": f.call("capcom_para_branco"), "fundo": "",
			"blend": Blend.ADITIVO, "c0": Color.BLACK, "c1": Color.WHITE},
		{"nome": "capcom_entra_logo", "ticks": f.call("capcom_entra_logo"), "fundo": "capcom",
			"blend": Blend.ADITIVO, "c0": Color.WHITE, "c1": Color.BLACK},
		{"nome": "capcom_exibicao", "ticks": f.call("capcom_exibicao"), "fundo": "capcom",
			"blend": Blend.NENHUM},
		{"nome": "capcom_sai_logo", "ticks": f.call("capcom_sai_logo"), "fundo": "capcom",
			"blend": Blend.ADITIVO, "c0": Color.BLACK, "c1": Color.WHITE},
		{"nome": "capcom_para_preto", "ticks": f.call("capcom_para_preto"), "fundo": "",
			"blend": Blend.ADITIVO, "c0": Color.WHITE, "c1": Color.BLACK},
		# ── TITLE.BIN estado 2 (0x80194b08): a entrada do título ──
		{"nome": "titulo_espera", "ticks": f.call("titulo_espera"), "fundo": "titulo",
			"blend": Blend.SUBTRATIVO, "c0": Color.WHITE, "c1": Color.WHITE},
		{"nome": "titulo_flash", "ticks": f.call("titulo_flash"), "fundo": "titulo",
			"blend": Blend.SUBTRATIVO, "c0": Color.WHITE, "c1": Color.WHITE,
			"add_c0": Color.BLACK, "add_c1": Color.WHITE},
		{"nome": "titulo_fade_in", "ticks": f.call("titulo_fade_in"), "fundo": "titulo",
			"blend": Blend.SUBTRATIVO, "c0": Color.WHITE, "c1": Color.BLACK},
		# ── TITLE.BIN estado 3 (0x80195564): o menu. Sem duração fixa. ──
		{"nome": "menu", "ticks": 0, "fundo": "titulo", "blend": Blend.NENHUM},
		{"nome": "fmv", "ticks": 0, "fundo": "", "blend": Blend.NENHUM},
		{"nome": "jogo", "ticks": 0, "fundo": "", "blend": Blend.NENHUM},
	]
	return P


func _montar() -> void:
	titulo = Titulo.new()
	titulo.name = "Titulo"
	titulo.visible = false
	add_child(titulo)
	titulo.escolheu_novo_jogo.connect(_on_novo_jogo)
	titulo.pediu_carregar.connect(_on_pediu_carregar)
	titulo.pediu_config.connect(_on_pediu_config)
	titulo.expirou.connect(_on_expirou)
	titulo.pediu_sfx.connect(func(id: int) -> void: pediu_sfx.emit(id))

	video = VideoFmv.new()
	video.name = "Fmv"
	video.visible = false
	add_child(video)
	video.terminou.connect(_on_fmv_terminou)

	# Os dois slots de fade. `BLEND_MODE_ADD`/`SUB` são as MESMAS operações do `abr` do PS1.
	_sub = _rect_fade(Blend.SUBTRATIVO)
	_add = _rect_fade(Blend.ADITIVO)


func _rect_fade(qual: Blend) -> ColorRect:
	var r := ColorRect.new()
	r.name = "FadeSub" if qual == Blend.SUBTRATIVO else "FadeAdd"
	r.size = Vector2(LARGURA, ALTURA)
	r.color = Color(0, 0, 0, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 300 if qual == Blend.SUBTRATIVO else 301
	var m := CanvasItemMaterial.new()
	m.blend_mode = (CanvasItemMaterial.BLEND_MODE_SUB if qual == Blend.SUBTRATIVO
		else CanvasItemMaterial.BLEND_MODE_ADD)
	r.material = m
	r.visible = false
	add_child(r)
	return r


# ─────────────────────────────── relógio e passos ───────────────────────────────

func passo_atual() -> String:
	return String(passos[passo]["nome"]) if passo < passos.size() else "fim"


func _aplicar_passo() -> void:
	ticks = 0
	var p: Dictionary = passos[passo]
	titulo.visible = String(p.get("fundo", "")) == "titulo"
	video.visible = passo_atual() == "fmv"
	queue_redraw()
	fase_mudou.emit(passo_atual())
	print("[boot] %-18s %4d ticks (%.2f s)" % [passo_atual(), int(p.get("ticks", 0)),
		float(p.get("ticks", 0)) / TAXA_TICK])
	match passo_atual():
		"titulo_espera":
			pediu_bgm.emit("main38")            ## `0x801944dc` SOUND/MAIN38.BGM
		"menu":
			titulo.fase = Titulo.Fase.MENU
			titulo.ticks = 0
		"fmv":
			if not tocar_fmv or not video.tocar("opn"):
				_ir_para_o_jogo()
		"jogo":
			_ir_para_o_jogo()
	_atualizar_fade()


func avancar_ticks(n := 1) -> void:
	## Avança `n` ticks de tarefa. É por aqui que o teste dirige a cena (sem render).
	for _i in n:
		if passo >= passos.size() or _fim:
			break
		var dur := int((passos[passo] as Dictionary).get("ticks", 0))
		if dur <= 0:
			# Passo sem duração fixa (menu / FMV / jogo): quem sai dele é um EVENTO, não o
			# relógio. No menu o tick ainda tem de andar — é o que faz o pulso do item
			# selecionado respirar e o timeout do atrator contar.
			if passo_atual() == "menu":
				titulo.avancar(1)
			continue
		ticks += 1
		if ticks >= dur:
			passo += 1
			if passo < passos.size():
				_aplicar_passo()
	_atualizar_fade()


func pular() -> void:
	## Pula o GRUPO corrente, na granularidade do original: no aviso vai para o logo, no logo
	## vai para a entrada do título, na entrada do título vai para o menu, no FMV corta o FMV.
	match passo_atual():
		"aviso_fade_in", "aviso_exibicao", "aviso_fade_out":
			_ir_para_passo("capcom_para_branco")
		"capcom_para_branco", "capcom_entra_logo", "capcom_exibicao", \
		"capcom_sai_logo", "capcom_para_preto":
			_ir_para_passo("titulo_espera")
		"titulo_espera", "titulo_flash", "titulo_fade_in":
			_ir_para_passo("menu")
		"fmv":
			video.pular()


func _ir_para_passo(nome: String) -> void:
	for i in passos.size():
		if String(passos[i]["nome"]) == nome:
			passo = i
			_aplicar_passo()
			return


func _atualizar_fade() -> void:
	if passo >= passos.size():
		return
	var p: Dictionary = passos[passo]
	var dur := int(p.get("ticks", 0))
	var b: int = int(p.get("blend", Blend.NENHUM))
	_sub.visible = false
	_add.visible = false
	if b == Blend.NENHUM:
		return
	var c := cor_do_fade(p.get("c0", Color.BLACK), p.get("c1", Color.BLACK), ticks, dur)
	if b == Blend.SUBTRATIVO:
		_sub.visible = true
		_sub.color = c
	else:
		_add.visible = true
		_add.color = c
	if p.has("add_c0"):
		_add.visible = true
		_add.color = cor_do_fade(p["add_c0"], p["add_c1"], ticks, dur)


static func cor_do_fade(c0: Color, c1: Color, t: int, T: int) -> Color:
	## `0x8002a4d0`+: `c = c0 + (c1-c0)*t/T`, por componente, em INTEIRO de 8 bits.
	if T <= 0:
		return c1
	var tt := clampi(t, 0, T)
	var f := func(a: float, b: float) -> float:
		var ia := int(round(a * 255.0))
		var ib := int(round(b * 255.0))
		return float(ia + (ib - ia) * tt / T) / 255.0
	return Color(f.call(c0.r, c1.r), f.call(c0.g, c1.g), f.call(c0.b, c1.b), 1.0)


# ─────────────────────────────── laço real ───────────────────────────────

func _process(delta: float) -> void:
	if _fim:
		return
	_ler_pad()
	_acumulado += delta * TAXA_TICK
	var n := int(_acumulado)
	if n > 0:
		_acumulado -= float(n)
		avancar_ticks(mini(n, 8))               ## trava contra travada de quadro
	_atualizar_fade()


func _ler_pad() -> void:
	var g: Node = _game()
	var m := 0
	if g != null and g.get("pad") != null:
		var pad: Pad = g.pad
		pad.poll()
		m = pad.mask
	else:
		# sem o autoload (ou com ele quebrado) o boot ainda tem de andar: lê o teclado
		for tecla: int in Pad.KEYMAP:
			if Input.is_key_pressed(tecla as Key):
				m |= int(Pad.KEYMAP[tecla])
	var novo := m & ~_pad_antes
	_pad_antes = m
	if novo == 0:
		return
	if passo_atual() == "menu":
		if novo & (Pad.HELD_RIGHT | Pad.BACK):
			titulo.mover_cursor(1)
		elif novo & (Pad.HELD_LEFT | Pad.FWD):
			titulo.mover_cursor(-1)
		elif novo & Pad.ACAO:
			titulo.confirmar()
		elif novo & Pad.PAUSA:
			titulo.cancelar()
		return
	if pulo_livre or (novo & Pad.ACAO) != 0:
		pular()


# ─────────────────────────────── saídas do título ───────────────────────────────

func _on_novo_jogo(eh_facil: bool) -> void:
	facil = eh_facil
	init_tbl_ok = carregar_init_tbl()
	aplicar_dificuldade(eh_facil)
	var g: Node = _game()
	if g != null and g.has_method("new_game"):
		g.new_game()                            ## template do EXE (0x800a018c)
	print("[boot] jogo novo: %s · INIT_TBL %s" % [
		"FÁCIL (bit 0x100 ligado)" if eh_facil else "DIFÍCIL (bit 0x100 limpo)",
		"conferido" if init_tbl_ok else "AUSENTE/divergente"])
	_ir_para_passo("fmv")


func aplicar_dificuldade(eh_facil: bool) -> void:
	## ENGATE com `core/game_state.gd` (que eu não edito): o campo `difficulty` já existe lá
	## com a semântica do binário (0 = normal/hard, 1 = easy, bit `0x100` de `0x800cc858`).
	## `dificuldade` é o campo separado que o `Player` usa para a mira — regra do port.
	var g: Node = _game()
	if g == null or g.get("state") == null:
		return
	var st: GameState = g.state
	st.difficulty = 1 if eh_facil else 0
	st.dificuldade = 0 if eh_facil else 2


func carregar_init_tbl() -> bool:
	## Carrega `ETC/INIT_TBL.DAT` como o TITLE faz em `0x80196068`
	## (`cd_read_file(0x30, dest 0x800d1d28, 0, "INIT_TBL")`) e CONFERE o arquivo.
	##
	## O layout dos 2312 bytes **não foi decodificado** (`menu_titulo.md` §10.13), então o
	## conteúdo não alimenta nada: o inventário de jogo novo continua vindo do template do
	## EXE. O que esta função prova é que o arquivo certo está no lugar certo.
	var p := AssetIO.path("BOOT/INIT_TBL.DAT")
	if not FileAccess.file_exists(p):
		push_warning("Boot: BOOT/INIT_TBL.DAT ausente — rode `NOSTALGIA_OUT=port python "
			+ "tools/boot_assets.py`")
		return false
	var b := FileAccess.get_file_as_bytes(p)
	if b.size() != INIT_TBL_BYTES:
		push_warning("Boot: INIT_TBL.DAT tem %d bytes, esperado %d" % [
			b.size(), INIT_TBL_BYTES])
		return false
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(b)
	var sha := ctx.finish().hex_encode()
	if sha != INIT_TBL_SHA1:
		push_warning("Boot: INIT_TBL.DAT com sha1 %s (esperado %s) — cópia diferente do "
			% [sha, INIT_TBL_SHA1] + "NTSC-U que este port mede")
		return false
	return true


func _on_pediu_carregar() -> void:
	## `0x80195988`: LOAD GAME carrega `MEM_CARD` (ovl 2). A tela de cartão de memória do
	## RE3 não foi implementada (`menu_titulo.md` §5 tem os textos, ZERO coordenada), então
	## aqui isso é um aviso — não uma tela inventada.
	print("[boot] LOAD GAME: a tela de cartão de memória (MEM_CARD.BIN) não foi extraída")


func _on_pediu_config() -> void:
	## `0x80196378`: GAME CONFIG carrega `OPTION` (ovl 4). §4 da nota: nenhuma opção, valor
	## ou coordenada medida. Não invento a tela.
	print("[boot] GAME CONFIG: OPTION.BIN não foi medido (nenhuma opção/coordenada)")


func _on_expirou() -> void:
	## Timeout de 900 ticks. O original alterna demo jogável (`PDEMO00/01/02.DAT`, ovl
	## nenhum: tarefa `0x80031bdc`) e o FMV de abertura (`0x80196800` -> ovl 5). O port só
	## tem o segundo caminho — a demo depende do reprodutor de PDEMO, que não existe.
	print("[boot] atrator (900 ticks sem entrada): tocando o FMV de abertura")
	_ir_para_passo("fmv")


func _on_fmv_terminou() -> void:
	_ir_para_passo("jogo")


func _ir_para_o_jogo() -> void:
	if _fim:
		return
	_fim = true
	terminou.emit()
	if not entrar_no_jogo:
		return
	print("[boot] entrando no jogo (%s)" % CENA_JOGO)
	get_tree().change_scene_to_file(CENA_JOGO)


func _game() -> Node:
	## O autoload `Game`, ou `null`. Precisa do guarda de árvore: o teste dirige o `Boot`
	## FORA da árvore de cena (é assim que ele verifica o caminho até o jogo headless), e
	## `get_node_or_null("/root/…")` fora da árvore é erro, não `null`.
	return get_node_or_null("/root/Game") if is_inside_tree() else null


# ─────────────────────────────── desenho ───────────────────────────────

func _draw() -> void:
	## O fundo de tela cheia do passo. Os HD são exatamente 1280×960, então é 1:1.
	## Fundo vazio = o "modo 1" do PS1 (`0x8002a338(1,0)`): limpa a tela com preto.
	if passo >= passos.size():
		return
	var nome := String((passos[passo] as Dictionary).get("fundo", ""))
	if nome == "" or nome == "titulo":
		if nome == "":
			draw_rect(Rect2(0, 0, LARGURA, ALTURA), Color.BLACK)
		return
	var tex: Texture2D = _fundos.get(nome)
	if tex == null:
		draw_rect(Rect2(0, 0, LARGURA, ALTURA), Color.BLACK)
		return
	draw_texture_rect(tex, Rect2(0, 0, LARGURA, ALTURA), false)
