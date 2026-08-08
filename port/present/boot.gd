class_name Boot
extends Node2D
## FLUXO DE ABERTURA do RE3, do primeiro quadro até cair na sala inicial.
##
##     aviso legal  ->  logo CAPCOM  ->  FILME DE ATRAÇÃO (roop)  ->  TÍTULO (navegável)
##     ->  dificuldade  ->  INIT_TBL.DAT  ->  VINHETA (prólogo narrado)
##     ->  FMV de abertura (opn)  ->  jogo (R10D)
##
## ── O REPRODUTOR DE FMV: achado desta rodada ──
## O RE3 do PS1 **não tem MDEC no EXE nem nos 17 overlays** (varri `0x1f801820`/`0x1f801824`
## e todos os `lui 0x1f80`: só scratchpad e libgpu). O filme é uma TAREFA do EXE com uma
## tabela própria:
##
##   `0x800321c4  filme_prepara(a0 = índice)`  -> `rec = 0x8009ca64 + a0*0x18`
##   `0x800324a0  tick do filme`, chamado pelo laço de quadro em `0x80029370`
##   fim = o bit `0x10000` de `0x800cc858` limpar (`filme_prepara` liga `0x18000`)
##
## A tabela de `0x8009ca64` tem **14 registros de 24 B** e começa exatamente onde termina a
## de overlays (`0x8009c944 + 24*12`). O campo `+0x04` é o número de QUADROS e vale
## `jPSXdec − 5` em **13/13** vídeos; `+0x0a/+0x0e` = 320 e 40, e 40+160+40 = 240 (o quadro
## `320×160` do `.STR` centralizado). Os números estão em `boot_flow.json.filmes`.
##
## ── ⚠ DUAS CORREÇÕES ao que este arquivo dizia antes ──
## 1. **Faltava o filme antes do menu.** `0x801943a4` chama `filme_prepara(0xc)` no FIM do
##    handler 0, isto é DEPOIS do logo CAPCOM (ou do reset `0x80194374`, ou do pulo) e
##    ANTES do estado 1 — e o código ESPERA o filme acabar (`0x801943ac`). O registro 12 é
##    `ZMOVIE/ROOPNE.STR` (231 quadros, volume 90/127), que no pacote HD é `roop.mp4`.
##    Só é pulado no Mercenaries (`0x8019439c`, bit `0x80`).
## 2. **O atrator NÃO toca o FMV de abertura.** `0x8019566c` põe `ctx[1] = 0xa` = sub 10
##    (`0x801966cc`) = **demo jogável** (`PDEMO00/01/02.DAT`). O sub 11 (`0x80196800`), que
##    é quem carrega o OPENING e chama `filme_prepara(0)`, **não é alcançado pelo timeout**:
##    varri todas as escritas em `ctx+1` dentro do `TITLE.BIN` e nenhuma grava 11. O port
##    tocava `opn` no timeout — era o "vídeo começando antes de clicar". Agora o timeout
##    repete o filme de atração e volta ao título (**declarado**, porque o port não tem
##    reprodutor de PDEMO).
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
## • **A VINHETA (prólogo).** `0x801960d8` cria a tarefa do `OPENING.BIN` (overlay 5) e só um
##   tick depois `0x801960e8` chama `filme_prepara(0)` — por isso o passo `prologo` vem ANTES
##   do `fmv`. Quem toca é `present/prologo.gd`, interpretando o script de 80 bytes que mora no
##   fim de `ETC/OPENING1.DAT` (13 opcodes, tabela de handlers `0x801c2f70`). Detalhe e provas
##   em `docs/decomp/notes/boot_ptbr_hd.md` §11. **DECLARADO:** a ordem prólogo → filme vem da
##   ordem das chamadas + do relato do dono; não medi o escalonador entre as duas tarefas.
## • **Pular.** Medido só para o logo CAPCOM: `0x8019432c` testa `0x800cc834 & 0x800`. O
##   aviso legal NÃO tem leitura de pad no caminho do `entry` (§2), e o sítio do FMV não foi
##   medido. `pulo_livre` (ligado) é afordância do port: qualquer botão pula a etapa.
## • **A sala inicial R10D** e a posição de spawn vêm de `present/screen.gd` (informadas pelo
##   usuário / medidas por varredura). O `INIT_TBL.DAT` é carregado e CONFERIDO (2312 B +
##   sha1), mas seu layout **não foi decodificado**, então ele não decide nada ainda.
## • **BGM do título** = `SOUND/MAIN38.BGM` + `MAIN38.VB` (`0x801944dc`, o rótulo de debug
##   "OPTION BGM" **não** foi verificado de ouvido: o que está provado é o índice de arquivo
##   `0x121`). Ela é carregada no estado 1, isto é DEPOIS do filme de atração — e é por isso
##   que o port só pede a trilha no `titulo_espera`. Aqui a trilha é PEDIDA por sinal
##   (`pediu_bgm`/`pediu_parar_bgm`); o `Audio` não é tocado deste arquivo.
## • **Banco de SFX do título = `C_01`, não `C_00`.** `0x801944c0` chama
##   `0x8007809c(cat = 0, banco = 1)`, e `0x8007809c` resolve
##   `file_index = tab[cat] + banco*2` com a tabela de bases `0x800110b0`
##   (`cat 0 -> 0x104 = SOUND/C_00.VH`), logo banco 1 = `0x106 = SOUND/C_01.VH`. Os 5 WAV
##   de UI de `C_01` são BYTE-IDÊNTICOS aos de `C_00` (conferido nos arquivos extraídos),
##   então o som audível é o mesmo; o banco declarado é o que o binário carrega.
## • **Som durante o filme — declarado.** O port PARA a BGM ao entrar no filme e a devolve
##   depois. No binário, `filme_prepara` liga a entrada de CD/XA no SPU a `0x7fff`
##   (`0x80032644` -> `0x80074658(1)`) e ajusta o volume pelo campo `+0x14` do registro
##   (`0x80032428` -> `0x8003331c`); **eu NÃO localizei o sítio que para o SEQ da BGM**.
##   No caminho normal isso nem aparece: quando o filme de atração roda, a `MAIN38` ainda
##   não foi carregada.
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
## Banco de SE da tela de título — MEDIDO (`0x801944c0` -> `0x8007809c(cat = 0, banco = 1)`).
const BANCO_SE_TITULO := "C_01"
## BGM da tela de título — MEDIDA (`0x801944dc` lê o índice de arquivo `0x121` = `SOUND/MAIN38.BGM`
## e `0x800782f4(0, 0x38, …)` toca a sequência 0x38). Na instalação de PC o mesmo número é
## `SOUND/MAIN38.WAV`, que `tools/audio_gog.py` converte para `BGM/gog/main38.ogg` (20,25 s,
## medido com ffprobe) — três fontes independentes apontando o mesmo `0x38`.
const BGM_TITULO := "main38"

enum Blend { NENHUM, ADITIVO, SUBTRATIVO }

signal fase_mudou(nome: String)
signal pediu_bgm(faixa: String)                ## "main38" — o engate do som fica com o Audio
signal pediu_parar_bgm()                       ## silêncio ao entrar no filme (ver cabeçalho)
## Narração do PRÓLOGO (`main06`). Separada do `pediu_bgm` por um motivo prático: ela **não
## pode entrar em laço** — tem 46,57 s e o prólogo dura 55,56 s, então em laço ela recomeçaria
## nos últimos 9 s. O `Audio.tocar_faixa` repete por padrão.
signal pediu_narracao(faixa: String)
signal pediu_sfx(id: int)
signal terminou()                              ## acabou a abertura; o jogo pode entrar

## Se `false`, a cena não troca para `game.tscn` no fim (usado pelo teste e pelo diagnóstico).
@export var entrar_no_jogo := true
## Toca os FMV (atração e abertura). Desligar dá o caminho curto título -> jogo.
@export var tocar_fmv := true
## Toca a VINHETA (o prólogo narrado) entre a dificuldade e o FMV de abertura.
@export var tocar_vinheta := true
## Qualquer botão pula a etapa corrente (afordância do port; ver o cabeçalho).
@export var pulo_livre := true

var passos: Array[Dictionary] = []
var passo := 0
var ticks := 0                                 ## ticks dentro do passo corrente
var facil := false
var init_tbl_ok := false
## Para onde ir quando o filme corrente acabar. É o que separa o filme de ATRAÇÃO
## (volta ao título) do FMV de ABERTURA (segue para o jogo).
var depois_do_filme := ""

var titulo: Titulo
var video: VideoFmv
var prologo: Prologo
var _d: Dictionary = {}
var _fundos: Dictionary = {}                   ## nome -> Texture2D
var _add: ColorRect
var _sub: ColorRect
var _acumulado := 0.0
var _pad_antes := 0
var _fim := false


func _ligar_som() -> void:
	## ENGATE que o agente do boot deixou para mim: os sinais `pediu_bgm`/`pediu_sfx` do fluxo de
	## abertura agora caem no `Audio`/`Sfx` do jogo. Os ids de SFX são os provados em `0x800746c0`
	## (4 cursor, 5 cancelar, 6 confirmar) e o de-para id → amostra está em
	## `docs/decomp/notes/exe_audio.md`.
	var laco := Engine.get_main_loop()
	if laco == null:
		return
	var g: Node = (laco as SceneTree).root.get_node_or_null("/root/Game")
	if g == null:
		return
	var au: Object = g.get("audio")
	var sf: Object = g.get("sfx")
	if au != null:
		pediu_bgm.connect(func(faixa: String) -> void: au.call("tocar_faixa", faixa))
		## O boot JÁ emitia `pediu_parar_bgm` ao entrar no filme; eu tinha ligado só o `pediu_bgm`,
		## e era por isso que a música do menu continuava tocando por cima do vídeo.
		pediu_parar_bgm.connect(func() -> void: au.call("parar_bgm"))
		pediu_narracao.connect(func(faixa: String) -> void:
			au.call("tocar_faixa", faixa, false))      ## loop = false: ver o sinal
	if sf != null:
		## ⚠ **BANCO EXPLÍCITO `C_01`** (correção desta rodada; o dono: "som do menu principal
		## errado"). `tocar_id(0, id)` sem banco cai no `banco_padrao` do `re3_se.json`, que é
		## `C_00` — e, pior, passaria a usar o banco de PERSONAGEM (`C_02`/`C_08`) se uma sala
		## já tivesse sido carregada, porque `Sfx._banco_de(0)` prefere `_banco_area`. O banco
		## da tela de título é MEDIDO: `0x801944c0` chama `0x8007809c(cat = 0, banco = 1)` e
		## `file_index = tab[cat] + banco*2` com a tabela de bases `0x800110b0` dá
		## `0x104 + 2 = 0x106 = SOUND/C_01.VH`. Conferido aqui que os 5 WAV de UI de `C_01` são
		## **byte-idênticos** aos de `C_00` (`cmp` nos 5 pares): o som audível é o mesmo, o que
		## muda é passar a tocar o banco que o binário carrega, em qualquer ordem de cena.
		pediu_sfx.connect(func(id: int) -> void: sf.call("tocar_id", 0, id, BANCO_SE_TITULO))


func _ready() -> void:
	_ligar_som()
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
		# ── fim do handler 0 (0x801943a4): filme_prepara(0xc) = ZMOVIE/ROOPNE = `roop` ──
		# Sem duração fixa: quem sai deste passo é o fim do vídeo (no original, o bit
		# 0x10000 de 0x800cc858 limpando — `0x801943ac`).
		{"nome": "filme_atracao", "ticks": 0, "fundo": "", "blend": Blend.NENHUM},
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
		# ── a VINHETA (prólogo) — `0x801960d8 load_overlay_task(1, ovl 5 = OPENING)` ──
		# Vem DEPOIS da dificuldade + `INIT_TBL` e ANTES do FMV: no original a tarefa do
		# OPENING é criada em `0x801960d8` e só um tick depois (`0x801960e0` yield) o TITLE
		# chama `filme_prepara(0)` em `0x801960e8`. Quem toca o prólogo é
		# `present/prologo.gd`, que interpreta o script de 80 bytes de `ETC/OPENING1.DAT`.
		# Sem duração fixa aqui: quem sai deste passo é o fim do script (1665 quadros).
		{"nome": "prologo", "ticks": 0, "fundo": "", "blend": Blend.NENHUM},
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

	# A VINHETA narrada (o prólogo do OPENING.BIN). O script dela vem do arquivo do usuário,
	# decodificado por `tools/boot_assets.py` — ver `present/prologo.gd`.
	prologo = Prologo.new()
	prologo.name = "Prologo"
	prologo.visible = false
	add_child(prologo)
	prologo.terminou.connect(_on_prologo_terminou)
	prologo.pediu_narracao.connect(func(faixa: String) -> void: pediu_narracao.emit(faixa))

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
	video.visible = em_filme()
	prologo.visible = passo_atual() == "prologo"
	queue_redraw()
	fase_mudou.emit(passo_atual())
	print("[boot] %-18s %4d ticks (%.2f s)" % [passo_atual(), int(p.get("ticks", 0)),
		float(p.get("ticks", 0)) / TAXA_TICK])
	match passo_atual():
		"filme_atracao":
			# `0x801943a4` filme_prepara(0xc) -> registro 12 = ZMOVIE/ROOPNE.STR (`roop`).
			_tocar_filme("roop", "titulo_espera")
		"titulo_espera":
			pediu_bgm.emit(BGM_TITULO)          ## `0x801944dc` SOUND/MAIN38.BGM (estado 1)
		"menu":
			titulo.fase = Titulo.Fase.MENU
			titulo.ticks = 0
		"prologo":
			# A vinheta: `0x801960d8 load_overlay_task(1, ovl 5 = OPENING)`, criada ANTES de
			# `filme_prepara(0)` (que só vem em `0x801960e8`, um tick depois). A narração
			# (`main06`) é pedida pelo próprio `Prologo` no 1º trecho de XA do script.
			pediu_parar_bgm.emit()
			prologo.comecar()
			if not tocar_vinheta or prologo.total <= 0:
				_ir_para_passo("fmv")
		"fmv":
			# `0x801960e8` filme_prepara(0) -> registro 0 = ZMOVIE/OPN.STR (`opn`).
			_tocar_filme("opn", "jogo")
		"jogo":
			_ir_para_o_jogo()
	_atualizar_fade()


func em_filme() -> bool:
	return passo_atual() in ["filme_atracao", "fmv"]


func _tocar_filme(qual: String, destino: String) -> void:
	## Entra num filme. Para a BGM (ver o cabeçalho: escolha do port) e guarda para onde ir
	## quando ele acabar. Se não houver `.ogv`, segue direto para o destino — sem inventar
	## tela e sem travar o fluxo.
	depois_do_filme = destino
	pediu_parar_bgm.emit()
	if not tocar_fmv or not video.tocar(qual):
		_ir_para_passo(destino)


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
			# `0x8019432c` sai do switch do CAPCOM, mas o filme de atração vem DEPOIS do
			# switch (`0x801943a4`) — logo pular o logo cai no filme, não no título.
			_ir_para_passo("filme_atracao")
		"filme_atracao", "fmv":
			video.pular()
		"prologo":
			# `0x801c2120` testa `0x800cc834 & 0x900`: o prólogo é pulável no original
			prologo.pular()
		"titulo_espera", "titulo_flash", "titulo_fade_in":
			_ir_para_passo("menu")


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


func _input(e: InputEvent) -> void:
	## CLIQUE / TOQUE na tela de título — por EVENTO, não por polling.
	##
	## ⚠ **CORREÇÃO desta rodada** (o dono: "escolher a dificuldade com o mouse não inicia o
	## vídeo; com o teclado funciona"). A causa principal era a regra de dois cliques do
	## `Titulo.clicar` (corrigida lá). Ler por EVENTO em vez de por borda de
	## `Input.is_mouse_button_pressed` conserta o resto:
	##  • **clique perdido:** solta-e-aperta dentro do MESMO quadro não gera borda nenhuma;
	##  • **posição:** vem DO PRÓPRIO EVENTO, sem consultar o ponteiro do sistema — o que
	##    também torna o caminho testável sem janela (a sonda `diag_clique_titulo.gd` roda
	##    headless);
	##  • o mesmo caminho atende `InputEventScreenTouch`, que é o toque do celular.
	##
	## O 2º aperto de um DUPLO CLIQUE (`double_click`) é IGNORADO de propósito: agora um clique
	## já confirma, então o 2º cairia na tela seguinte — um duplo clique em COMEÇAR JOGO
	## escolheria a dificuldade sem o dono ver a tela.
	if titulo == null or not titulo.visible:
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			if clique(mb.position):
				get_viewport().set_input_as_handled()
	elif e is InputEventScreenTouch:
		var st := e as InputEventScreenTouch
		if st.pressed and clique(st.position):
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		## HOVER (pedido do usuário): passar o mouse por cima já deixa o item em evidência.
		## O gatilho é o evento de MOVIMENTO, então a regra "só quando o ponteiro moveu" — que no
		## menu do jogo precisa do `pad.mouse_dx/dy` — aqui é automática: mouse parado não gera
		## evento, e o cursor não fica preso para quem navega pelo teclado.
		pairar((e as InputEventMouseMotion).position)


func ponto_do_titulo(pos_viewport: Vector2) -> Vector2:
	## Converte coordenada de VIEWPORT para o espaço 320×240 do nó do título (que tem escala 4).
	var ct := Transform2D()
	if is_inside_tree():
		ct = get_viewport().get_canvas_transform()
	return titulo.to_local(ct.affine_inverse() * pos_viewport)


func clique(pos_viewport: Vector2) -> bool:
	## Roteia um clique/toque em coordenada de VIEWPORT para o título. Separado do `_input`
	## para o teste poder chamar sem fabricar evento (e para a sonda `diag_clique_titulo.gd`).
	if titulo == null or not titulo.visible:
		return false
	var pt := ponto_do_titulo(pos_viewport)
	var r: String = titulo.clicar(pt)
	if r != "":
		print("[boot] clique em (%.0f, %.0f) -> %s" % [pt.x, pt.y, r])
	return r != ""


func pairar(pos_viewport: Vector2) -> bool:
	## Roteia o MOVIMENTO do ponteiro para o hover do título.
	if titulo == null or not titulo.visible:
		return false
	return titulo.pairar(ponto_do_titulo(pos_viewport))


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
	## PULO da etapa: **só teclado** (Enter/Espaço/E). O usuário pediu para tirar o pulo no mouse —
	## clicar durante o filme pulava a abertura sem querer. Os bits do mouse (`TIRO` no esquerdo e
	## `AIM` no direito) ficam de fora, e o `pulo_livre` deixa de valer para eles.
	var teclas_pulo := Pad.ACAO | Pad.AIM_A | Pad.AIM_B
	var so_mouse := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) 		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if so_mouse and (novo & ~(Pad.TIRO | Pad.AIM)) == 0:
		return                                  ## foi só clique: não pula
	if (novo & teclas_pulo) != 0 or (pulo_livre and (novo & ~(Pad.TIRO | Pad.AIM)) != 0):
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
	## Timeout de 900 ticks (`0x8019454c`). ⚠ CORREÇÃO: o original vai para o sub 10
	## (`0x8019566c` grava `ctx[1] = 0xa`), que é a **demo jogável** — `ETC/PDEMO00/01/02.DAT`
	## (índices `0x41`/`0x42`/`0x43`) em rodízio por `*(u8*)0x800c79af`, carregados em
	## `0x80192000`, tarefa `0x80031bdc`. O sub 11 (`0x80196800`), que carrega o OPENING e
	## chama `filme_prepara(0)`, NÃO é alcançado pelo timeout: nenhuma escrita em `ctx+1` do
	## `TITLE.BIN` grava 11.
	##
	## **DECLARADO:** sem reprodutor de PDEMO, o port repete o filme de ATRAÇÃO e volta ao
	## título. O que ele NÃO faz mais é tocar o `opn` — esse é do NEW GAME.
	print("[boot] atrator (900 ticks sem entrada): repetindo o filme de atração (roop). "
		+ "O original roda a demo jogável PDEMO — não implementada.")
	titulo.fase = Titulo.Fase.ENTRADA
	titulo.ticks = 0
	_ir_para_passo("filme_atracao")


func _on_prologo_terminou() -> void:
	## O script do prólogo acabou (ou foi pulado): segue para o FMV de abertura, que é o que o
	## TITLE faz em `0x801960e8` depois de criar a tarefa do OPENING.
	if passo_atual() == "prologo":
		_ir_para_passo("fmv")


func _on_fmv_terminou() -> void:
	## Quem decide o destino é `depois_do_filme` (o filme de atração volta ao título; o
	## `opn` segue para o jogo). Devolve a BGM quando volta para o título.
	var destino := depois_do_filme if depois_do_filme != "" else "jogo"
	depois_do_filme = ""
	_ir_para_passo(destino)


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
