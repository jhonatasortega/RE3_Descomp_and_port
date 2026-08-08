class_name Titulo
extends Node2D
## MENU DE TÍTULO do RE3 — navegável, em **HD e em PT-BR**. Recomp, não pastiche.
##
## Fonte de tudo que está aqui: `docs/decomp/notes/menu_titulo.md` §3 (`TITLE.BIN`, base
## `0x80194000`, entry `0x801940e8`) + `port/data/boot_flow.json`, gerado por
## `tools/boot_assets.py`.
##
## ── A máquina de estados do original ──
## `TITLE.BIN` roda 5 handlers (`0x801974c0`) sobre `*(u8*)0x80197508`. O que este arquivo
## reproduz é o **estado 3** (`0x80195564`), o título interativo, e a sub-máquina
## `0x801974d8` nos dois sub-estados que interessam ao boot:
##
##     sub 0  `0x80195634`  menu de 3 itens (NEW GAME / LOAD GAME / GAME CONFIG)
##     sub 1  `0x80195c68`  escolha de DIFICULDADE (2 itens) -> INIT_TBL -> OPENING
##
## Fatos medidos que a navegação obedece:
## • **3 itens, com wrap:** `0x801956c4` (`>= 3 -> 0`) e `0x801956dc` (`< 0 -> 2`).
## • **CIMA = `0x800cc834 & 0x8000`, BAIXO = `& 0x2000`** (`0x8019567c`/`0x801956a0`).
##   No RE3 o menu é HORIZONTAL na tela mas o pad que anda nele é o vertical — o port
##   aceita os dois eixos (afordância, não medida).
## • **CONFIRMA = `0x800cc840 & 0x1000` OU `0x800cc834 & 0x800`** (`0x80195724`).
## • **SFX:** 4 = cursor moveu, 5 = cancelar, 6 = confirmar (`0x800746c0`).
## • **Timeout do atrator = 900 ticks** (`0x8019454c`), REINICIADO a cada movimento de
##   cursor (`0x801956f4`).
## • **Cursor inicial = 1 (`LOAD GAME`)** — `0x801945b4`. Medido e contra-intuitivo; a
##   própria nota (§10.2) pede confirmação em emulador. Fica como o binário diz.
## • **Dificuldade: 2 itens**, cursor 0 = HARD, cursor 1 = EASY (`0x80195d04`), e a escolha
##   grava o bit `0x100` de `0x800cc858` (`0x80195dcc` liga = EASY, `0x80195db8` limpa).
## • **Pulso do item selecionado:** `ctx[0x0f] += 4` por tick e
##   `ctx[0x0e] = (s8)tab[ctx[0x0f]]/3 - 0x80`, com `tab` = a tabela seno de 256 bytes
##   assinados de `0x80098828`. Resultado: **86…170** com período de **64 ticks** — os 64
##   valores estão no JSON, lidos do EXE, não recalculados aqui.
## • **Selecionado = OPACO com rgb pulsante; não selecionado = SEMITRANSPARENTE com rgb 128**
##   (`0x80194d48`). No PS1 a primitiva faz `tex * rgb / 128`, então rgb 128 é neutro: aqui
##   isso é `modulate = rgb/128` (chega a 1,33 no pico, e é isso que faz o item "respirar").
##
## ── HD e PT-BR: de onde vem cada pixel ──
## • **Fundo:** `assets/BOOT/titulo.webp` = `hires/bgd/ED2C2D33.webp`, 1280×960 —
##   "EDIÇÃO DEFINITIVA / RESIDENT EVIL 3 NEMESIS". ⚠ O casamento HD anterior do repo
##   (`MENU/01_title/hd/...18CC5627`) pegou a variante **japonesa** ("BIOHAZARD 3 LAST
##   ESCAPE"); a variante PT foi achada pelo mesmo critério de `tools/memo_pt.py` (o pack
##   russo é de jan/2025, o PT-BR de jun/2025) e conferida a olho.
## • **Rótulos:** `assets/BOOT/atlas.webp` = `hires/misc/3776D4A3.webp`, **1024×1024 = 4× a
##   página de VRAM 256×256** do `TITLEU.DAT` TIM[2]. As linhas (`v`) do atlas PT coincidem
##   com as do atlas do PS1 nas faixas usadas, o que `mod_BH3_Portuguese/xml/
##   title_mapping.xml` confirma de forma independente.
## • **Posição de tela:** `x,y` do inicializador de `SPRT` `0x801945e4` — NEW GAME em
##   (68,193), LOAD GAME em (132,193), GAME CONFIG em (200,193), dificuldade em
##   (80,193)/(180,193).
##
## ── O que é ESCOLHA do port, declarada ──
## • **`NEW GAME` -> "COMEÇAR JOGO".** A célula que o PS1 usa (u=0,v=104) contém
##   "MODO ORIGINAL" no atlas PT (é o item do menu de 5 opções do PC). "COMEÇAR JOGO"
##   (u=0,v=144) é o rótulo do atlas cujo SENTIDO é o de NEW GAME. A célula 1:1 está no
##   JSON em `alt_celula` — trocar é uma linha.
## • **`GAME CONFIG` fica em INGLÊS**: o pacote PT-BR não traduziu essa linha do atlas.
##   Não há variante PT deste rótulo no pack. Não escalo o SD nem desenho texto no lugar.
## • **Dificuldade em PT** usa "MODO FACIL"/"MODO DIFICIL" (linha v=128 do atlas PT). A
##   célula 1:1 do PS1 (v=176) existe no atlas PT mas está em inglês ("EASY/HARD MODE").
## • **`PRESS ANY BUTTON` não tem contrapartida HD** (a versão de PC não usa essa tela) e o
##   **bloco de copyright de 2 linhas** do PS1 está vazio no atlas PT. Uso a linha única de
##   copyright de v=120, que existe. Isto está registrado, não disfarçado.
## • **Posição X dos rótulos (⚠ CORRIGIDO nesta rodada).** A regra antiga — centralizar
##   cada rótulo no centro do retângulo do `SPRT` original — deixava os itens com vãos
##   DESIGUAIS e a linha puxada para a esquerda, porque os rótulos PT têm largura
##   diferente: "COMEÇAR JOGO" tem 53 px de tinta contra os 48 da célula `NEW GAME`, e
##   "CONFIG" tem 28 contra os 60 de `GAME CONFIG`. Resultado medido daquela regra:
##   caixas [65,118] [131,184] [216,244] → vãos de **13 e 32 px** (o original tem 16 e 18)
##   e borda direita em 244 em vez de 260.
##   A regra NOVA usa duas âncoras MEDIDAS e uma escolha declarada:
##     · âncoras = borda esquerda do 1º `SPRT` e borda direita do último (`0x801945e4`:
##       68 e 200+60 = 260 no menu; 80 e 180+54 = 234 na dificuldade);
##     · **declarado:** os vãos entre os rótulos ficam IGUAIS.
##   `tools/boot_assets.py` calcula e grava `x_tela` em `rotulos_pt` do JSON — o número
##   não é recalculado aqui. Menu: 68 / 150 / 232 (vãos de 29). Dificuldade: 80 / 189.

const ESCALA := 4
const TELA := Vector2i(320, 240)
const CAMINHO_JSON := "res://data/boot_flow.json"
const ATLAS_ESCALA := 4                        ## o webp de rótulos é 4× a página SD

enum Fase { ENTRADA, MENU, DIFICULDADE, SAINDO }
enum Item { NOVO_JOGO, CARREGAR, CONFIG }

## Os 3 itens do título normal (`0x80194894`+) e os 2 da dificuldade, na ORDEM do cursor.
const ITENS_MENU: Array[String] = ["NEW_GAME", "LOAD_GAME", "GAME_CONFIG"]
const ITENS_DIFICULDADE: Array[String] = ["diff_HARD_MODE", "diff_EASY_MODE"]

signal escolheu_novo_jogo(facil: bool)
signal pediu_carregar()
signal pediu_config()
signal expirou()                               ## timeout do atrator (900 ticks)
signal pediu_sfx(id: int)                      ## 4 cursor · 5 cancelar · 6 confirmar

var fase: Fase = Fase.ENTRADA
var cursor := 1                                ## `0x801945b4`: começa em LOAD GAME
var cursor_dificuldade := 0                    ## 0 = HARD, 1 = EASY
var facil := false                             ## espelha o bit 0x100 de 0x800cc858
var ticks := 0                                 ## ticks nesta fase
var timeout := 900

var _d: Dictionary = {}
var _sprites: Dictionary = {}
var _rotulos: Dictionary = {}
var _pulso: Array = []
var _pulso_i := 0
var _fundo: Texture2D
var _atlas: Texture2D
var _entrada_total := 0


func _ready() -> void:
	scale = Vector2(ESCALA, ESCALA)
	carregar()


func carregar() -> bool:
	## Lê as tabelas do JSON e as texturas HD. `false` = faltou dado (a tela não desenha,
	## mas a NAVEGAÇÃO continua funcionando — é o que permite testar headless).
	var ok := true
	if FileAccess.file_exists(CAMINHO_JSON):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_JSON))
		if raw is Dictionary:
			_d = raw
	if _d.is_empty():
		push_warning("Titulo: %s ausente — rode `NOSTALGIA_OUT=port python "
			% CAMINHO_JSON + "tools/boot_assets.py`")
		ok = false
	_sprites = _d.get("sprites_titulo", {})
	_rotulos = _d.get("rotulos_pt", {})
	_pulso = (_d.get("pulso", {}) as Dictionary).get("valores", [])
	var menu: Dictionary = _d.get("menu", {})
	cursor = int(menu.get("cursor_inicial", 1))
	timeout = int((_d.get("tempos", {}) as Dictionary).get("atrator_timeout", {}).get(
		"ticks", 900))
	_entrada_total = ticks_de("titulo_espera") + ticks_de("titulo_flash") \
		+ ticks_de("titulo_fade_in")
	_fundo = AssetIO.texture("BOOT/titulo.webp")
	_atlas = AssetIO.texture("BOOT/atlas.webp")
	if _fundo == null or _atlas == null:
		push_warning("Titulo: assets do título ausentes — rode `NOSTALGIA_OUT=port python "
			+ "tools/boot_assets.py`")
		ok = false
	return ok


func ticks_de(nome: String) -> int:
	var t: Dictionary = _d.get("tempos", {})
	var e: Variant = t.get(nome)
	return int((e as Dictionary).get("ticks", 0)) if e is Dictionary else 0


# ─────────────────────────────── navegação ───────────────────────────────

func avancar(n := 1) -> void:
	## Um tick de tarefa do PS1 (não um quadro do port — ver `boot.gd`).
	for _i in n:
		ticks += 1
		_pulso_i = (_pulso_i + 1) % maxi(_pulso.size(), 1)
		if fase == Fase.ENTRADA and ticks >= _entrada_total and _entrada_total > 0:
			fase = Fase.MENU
			ticks = 0
		elif fase == Fase.MENU and ticks >= timeout:
			expirou.emit()
			ticks = 0
	queue_redraw()


func mover_cursor(passo: int) -> void:
	if passo == 0:
		return
	match fase:
		Fase.MENU:
			var n := ITENS_MENU.size()          ## 3 — `0x801956c4` / `0x801956dc`
			var novo := (cursor + passo + n) % n
			if novo != cursor:
				cursor = novo
				pediu_sfx.emit(4)               ## SFX de cursor (`0x801956f4`)
				ticks = 0                       ## reinicia o timeout do atrator
				_pulso_i = 0                    ## `ctx[0x0f] = 0` no mesmo sítio
		Fase.DIFICULDADE:
			var nd := ITENS_DIFICULDADE.size()  ## 2 — `0x80195d04`
			var novo_d := (cursor_dificuldade + passo + nd) % nd
			if novo_d != cursor_dificuldade:
				cursor_dificuldade = novo_d
				pediu_sfx.emit(4)
				ticks = 0
				_pulso_i = 0
	queue_redraw()


func confirmar() -> void:
	match fase:
		Fase.MENU:
			pediu_sfx.emit(6)                   ## `0x8019578c` / `0x801957c0`
			match cursor:
				Item.NOVO_JOGO:
					fase = Fase.DIFICULDADE
					cursor_dificuldade = 0
					ticks = 0
					_pulso_i = 0
				Item.CARREGAR:
					pediu_carregar.emit()
				Item.CONFIG:
					pediu_config.emit()
		Fase.DIFICULDADE:
			# `0x80195db8` limpa e `0x80195dcc` liga o bit 0x100 (EASY) de 0x800cc858
			facil = cursor_dificuldade == 1
			fase = Fase.SAINDO
			pediu_sfx.emit(6)
			escolheu_novo_jogo.emit(facil)
	queue_redraw()


func cancelar() -> void:
	## `0x80195dd8`: CANCELA na tela de dificuldade volta ao menu (com SFX 5).
	if fase == Fase.DIFICULDADE:
		fase = Fase.MENU
		cursor = Item.NOVO_JOGO             ## `ctx[4] = 0 ; ctx[5] = 0` no mesmo sítio
		ticks = 0
		pediu_sfx.emit(5)
		queue_redraw()


func item_selecionado() -> String:
	if fase == Fase.DIFICULDADE:
		return ITENS_DIFICULDADE[clampi(cursor_dificuldade, 0, ITENS_DIFICULDADE.size() - 1)]
	return ITENS_MENU[clampi(cursor, 0, ITENS_MENU.size() - 1)]


func brilho() -> int:
	## O valor de `ctx[0x0e]` neste tick (86…170). 128 = neutro quando não há tabela.
	if _pulso.is_empty():
		return 128
	return int(_pulso[_pulso_i % _pulso.size()])


# ─────────────────────────────── desenho ───────────────────────────────

func _draw() -> void:
	if _fundo == null:
		return
	# o fundo HD é 1280×960 e o nó tem escala 4 -> desenhar em 320×240 dá 1:1 na tela
	draw_texture_rect(_fundo, Rect2(0, 0, TELA.x, TELA.y), false)
	if fase == Fase.ENTRADA:
		return                                  ## o fade é do `boot.gd`, não daqui
	if _atlas == null:
		return
	_rotulo("copyright", "copyright", 1.0, false)
	var b := float(brilho()) / 128.0
	if fase == Fase.DIFICULDADE:
		for i in ITENS_DIFICULDADE.size():
			var nome: String = ITENS_DIFICULDADE[i]
			var sel := i == cursor_dificuldade
			_rotulo(nome, nome, b if sel else 1.0, not sel)
		return
	for i in ITENS_MENU.size():
		var chave: String = ITENS_MENU[i]
		var sel2 := i == cursor
		_rotulo(chave, chave, b if sel2 else 1.0, not sel2)


func caixa_do_item(i: int) -> Rect2:
	## Retângulo de tela (320×240) do item `i` do menu — a MESMA geometria do desenho: `x_tela`/
	## `y_tela` do JSON (âncoras de `0x801945e4`) e a caixa de TINTA medida no atlas HD.
	var itens: Array[String] = ITENS_DIFICULDADE if fase == Fase.DIFICULDADE else ITENS_MENU
	if i < 0 or i >= itens.size():
		return Rect2()
	var ro: Variant = _rotulos.get(itens[i])
	var sp: Variant = _sprites.get(itens[i])
	if not (ro is Dictionary):
		return Rect2()
	var r: Dictionary = ro
	var w := int(r.get("w", 0))
	var tw := int(r.get("tinta_w", w))
	if tw <= 0:
		tw = w
	var h := int(r.get("h", 0))
	var x := int(r.get("x_tela", 0))
	var y := int(r.get("y_tela", 0))
	if x == 0 and sp is Dictionary:
		x = int((sp as Dictionary).get("x", 0))
	if y == 0 and sp is Dictionary:
		y = int((sp as Dictionary).get("y", 0))
	## folga de 3 px em volta: o alvo de clique/toque não pode ser do tamanho exato da tinta
	return Rect2(float(x - 3), float(y - 3), float(tw + 6), float(h + 6))


func clicar(p: Vector2) -> String:
	## CLIQUE/TOQUE na tela de título (pedido do usuário; serve para o port de celular também).
	## Regra igual à do inventário: o 1º clique SELECIONA o item sob o ponteiro, e o 2º clique no
	## MESMO item CONFIRMA.
	if fase != Fase.MENU and fase != Fase.DIFICULDADE:
		return ""
	var itens: Array[String] = ITENS_DIFICULDADE if fase == Fase.DIFICULDADE else ITENS_MENU
	for i in itens.size():
		if not caixa_do_item(i).has_point(p):
			continue
		var atual := cursor_dificuldade if fase == Fase.DIFICULDADE else cursor
		if i == atual:
			confirmar()
			return "confirmou %s" % itens[i]
		if fase == Fase.DIFICULDADE:
			cursor_dificuldade = i
		else:
			cursor = i
		pediu_sfx.emit(4)                       ## SFX de cursor (`0x801956f4`)
		ticks = 0                               ## reinicia o timeout do atrator
		_pulso_i = 0
		queue_redraw()
		return "selecionou %s" % itens[i]
	return ""


func _rotulo(chave_sprite: String, chave_rotulo: String, mod: float,
		semitransparente: bool) -> void:
	## Desenha um rótulo do atlas HD na posição do `SPRT` do PS1.
	##
	## `mod` reproduz `tex * rgb / 128` do PS1 (128 -> 1,0). `semitransparente` é o
	## `SetSemiTrans` de `0x80194d48`: no PS1 é 0,5·fundo + 0,5·primitiva, aqui alpha 0,5.
	var sp: Variant = _sprites.get(chave_sprite)
	var ro: Variant = _rotulos.get(chave_rotulo)
	if not (sp is Dictionary) or not (ro is Dictionary):
		return
	var s: Dictionary = sp
	var r: Dictionary = ro
	var u := int(r.get("u", 0))
	var v := int(r.get("v", 0))
	var w := int(r.get("w", 0))
	var h := int(r.get("h", 0))
	# usa a caixa de TINTA medida no atlas (evita o bloco vazio da célula à esquerda)
	var tx := int(r.get("tinta_x", 0))
	var tw := int(r.get("tinta_w", w))
	if tw <= 0:
		tw = w
	# `x_tela` vem de `tools/boot_assets.py` (âncoras de `0x801945e4` + vãos iguais). Sem
	# ele — JSON antigo — cai na regra velha, para não desenhar em cima de nada.
	var x := int(r.get("x_tela", int(s.get("x", 0)) + (int(s.get("w", tw)) - tw) / 2))
	var y := int(r.get("y_tela", int(s.get("y", 0))))
	var cor := Color(mod, mod, mod, 0.5 if semitransparente else 1.0)
	draw_texture_rect_region(_atlas, Rect2(x, y, tw, h),
		Rect2i((u + tx) * ATLAS_ESCALA, v * ATLAS_ESCALA, tw * ATLAS_ESCALA,
			h * ATLAS_ESCALA), cor)
