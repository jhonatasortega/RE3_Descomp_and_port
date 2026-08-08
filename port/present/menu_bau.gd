class_name MenuBau
extends Node2D
## Tela do BAÚ DE ITENS (item box) do RE3 — `sce 9`, screen kind **2** da task do menu.
##
## ── COMO SE PROVOU QUE ESTA É A TELA DO BAÚ (e que o enum do port estava errado) ──
## 1. A tabela de despacho de AOT é `0x8009e0bc`, indexada pelo `sce`. Prova: o laço de AOT
##    faz `lbu $v0, ($s0)` + `jalr *(0x8009e0bc + sce*4)` em `0x80050a94..0x80050aac`, e o AOT
##    em RAM é `script_pc + 2` (`0x80055c74/78`), logo AOT+0 == byte +2 do opcode == `sce`.
## 2. `tabela[9] = 0x800514c4`. Esse handler tem 6 instruções e a que importa é
##    **`0x800514cc  sb $v0, 0x1c4($v1)` com `$v0 = 2`** → escreve **2** em `0x800e01c4`, que é
##    `ctx+0x04` = o *screen kind* da task do menu (ctx `0x800e01c0`, `menu_pc_sys.md §5`).
##    Ele também instala a rotina per-frame `gs+0x75e0 = 0x800514f0` (a animação de abrir).
## 3. `0x800514cc` é o **ÚNICO** escritor de kind 2 no EXE inteiro — varredura de todo
##    `sb/sh/sw ..., 0x1c4(reg)`: os outros escrevem 0 (`0x80023cb0`, `0x80057e34`),
##    4 (`0x80023cd0`), 1 (`0x8003b128`, `0x80051174`) ou variável (`0x8005123c`).
## 4. Os subestados do kind 2 (nível 1 estado 10→11, tabela `0x8009f4e4` de 5 entradas)
##    percorrem o **ITEM BOX**: `inv = *(gs+0x7c7c)` (`0x800644c0`, `0x80064760`, `0x80064c20`),
##    base `inv + 0x28` (`0x80064820  addiu $v0,$v0,0x28`), limite **64**
##    (`slti $v0,$v0,0x40` em `0x80064b88`, `0x80064bb0`, `0x80064d74`, `0x80064e38`) e índice
##    máximo 63 (`0x80064afc  addiu $v0,$zero,0x3f`). E `inv+0x28` × 64 slots é, por
##    `exe_items.md §2.1`, exatamente a caixa de itens (MAIN 10 em `+0x00`).
## 5. Contraprova pelo vizinho: `sce 8` (`0x80051388` → per-frame `0x800513cc`) faz
##    `find_by_id(0x81)` em `0x80051404`, e `0x81` = **Ink Ribbon** → `sce 8` é a MÁQUINA DE
##    ESCREVER. `sce 8` e `sce 9` aparecem nas MESMAS 16 salas (15 em comum; só R111 tem 8 sem
##    9, só R50B tem 9 sem 8) = máquina de escrever + baú lado a lado na sala de save. ✅
## 6. `sce 10`, que o enum herdado do RE2 chamava de "SCE_ITEMBOX", é outra coisa: `0x80051684`
##    liga `gs+0x2120 |= 0x2000` e o consumidor `0x80023fa8` chama
##    `load_overlay_task(1, 0x0c + u16@payload)` = overlay **RESULT/SELECT/STAFF_R/TITLE**
##    (`menu_overlays.md §4` e §7.1). São 5 gatilhos no jogo, nenhum é baú.
##
## ── O QUE ESTÁ MEDIDO NO BINÁRIO E ENTRA AQUI COMO FATO ──
## • Grade da MÃO: 2 colunas × 5 linhas, célula **40×30**, origem **(224,66)** (B27/B28/B29,
##   cursor B146 andando por `x = col*40, y = row*30` em `0x800668a4`).
## • Cursor: sprite B146 `(120,0,40,30)` do STMOJIU na paleta 3, com a piscada de `ctx+0x22`
##   (±2 com clamp em `0x3f`, `0x8006e290`..`0x8006e2f0`) — brilho 0,5..1,0.
## • Painel grande: **B142 = 200×136 em (12,84)**, o mesmo painel que o kind 3 (ARQUIVO) usa.
##   Reusar é o que o motor faz: kind 2 e kind 3 são telas da MESMA task, mesma moldura.
## • Paginação por **L1/R1**: os subestados do kind 2 leem `raw_held & 0xc` e repetem em
##   `rpt & 0x4` / `rpt & 0x8`, e UP/DOWN em `raw_held & 0x5000` (`menu_pc_sys.md §5`, kind 2).
## • Ícones 40×30 do `ETC/ITEMA.SLD` por `item_id`; célula vazia é o ícone `item_id 0`.
##
## ── O QUE É ESCOLHA DO PORT, DECLARADA (não medida) ──
## • **A grade do baú dentro do B142**: 5 colunas × 4 linhas de 40×30 = 200×120, origem
##   (12,92) (o painel tem 136 de altura; 120 centrados sobram 8 em cima e em baixo).
##   → 20 slots por página, **4 páginas** para os 64. O EXE não expõe o `x,y` dessas
##   primitivas (o sítio de desenho grava `u,v,clut,w,h` e não a posição), então isto é
##   geometria derivada de um painel PROVADO, não uma medida. **NÃO PROVADO.**
## • Os rótulos ("BAÚ", "MÃO", "SAIR") são texto desenhado com a fonte do jogo em PT-BR: os
##   originais são sprites do `STMOJIU`, e o atlas HD disponível só tem inglês e russo.
## • A ordem de desenho (um `Node2D` com `z_index` alto): no PS1 é a Ordering Table da task.

const ESCALA := 4                       ## 1280/320 — o quadro do port é 4× a tela do PS1
const CELULA := Vector2i(40, 30)

## MÃO (provado): 2×5 de 40×30 a partir de (224,66).
const MAO_ORIGEM := Vector2i(224, 66)
const MAO_COLUNAS := 2
const MAO_LINHAS := 5

## BAÚ (declarado, dentro do painel B142 provado): 5×4 de 40×30 a partir de (12,92).
const BAU_PAINEL := [12, 84, 200, 136]  ## B142 — 200×136 em (12,84)
const BAU_ORIGEM := Vector2i(12, 92)
const BAU_COLUNAS := 5
const BAU_LINHAS := 4
const BAU_POR_PAGINA := BAU_COLUNAS * BAU_LINHAS          ## 20
const BAU_SLOTS := 64                   ## ✅ limite 0x40 dos subestados do kind 2

## Molduras da tabela B reaproveitadas (u, v, w, h, dx, dy) — as mesmas do STATUS, porque é a
## mesma moldura da mesma task. B6 = a placa de cima; B7/B8/B9 = as bordas da coluna de itens.
const MOLDURA := [
	[0, 120, 88, 56, 224, 16],          ## B6  — placa de cima (aqui: SAIR)
	[96, 72, 8, 136, 216, 80],          ## B7  — borda esquerda da coluna da mão
	[104, 64, 8, 144, 304, 72],         ## B8  — borda direita
	[0, 176, 96, 8, 216, 216],          ## B9  — borda de baixo
]
const CURSOR := [120, 0, 40, 30, 224, 66]        ## B146
const U_TPAGE_9B := 128                 ## moldura sai da tpage 0x9B = +128 px no atlas SD

const QTD_OFFSET := Vector2i(2, 18)
const DIGITO_W := 8
const DIGITO_H := 11
const DIGITO_V := 19                    ## fileira `0 1 2 3 4 5 6 7 8 9 %` do STMOJIU
const DIGITO_U0 := 4
const QTD_ESCALA := 0.9
const ANIM_QUADROS := 6                 ## abertura/fechamento (`0x800741a0`)
const CURSOR_PASSO := 2                 ## `ctx+0x22` ±2
const CURSOR_TETO := 0x3F

## `rgb(8,8,8)` medido no montador de TILE (`0x8006e7d4`) e o azul do interior das janelas.
const COR_TILE := Color8(8, 8, 8)
const COR_AZUL := Color8(24, 32, 72)
const COR_JANELA := Color8(168, 176, 200)

enum Lado { BAU, MAO }

var aberto := false
var lado: Lado = Lado.MAO               ## a tela abre com o cursor na MÃO (é de lá que se guarda)
var cursor_mao := 0
var cursor_bau := 0                     ## índice ABSOLUTO no baú (0..63)
var pagina := 0
var sair_selecionado := false
var ultima_acao := ""

var _state: GameState = null
var _anim := 0
var _fechando := false
var _piscada := 0x80
var _piscada_sobe := true
var _pronto := false

var _chrome: Texture2D = null
var _chrome_hd: Texture2D = null
var _icones: Dictionary = {}
var _paletas: Dictionary = {}
var _paleta_fator: Dictionary = {}
var _itens_json: Dictionary = {}


func _init() -> void:
	name = "MenuBau"
	visible = false
	scale = Vector2(ESCALA, ESCALA)
	z_index = 100                       ## acima do mundo e dos recortes de oclusão


func carregar(state: GameState) -> bool:
	## Mesmos assets da tela de status (é a mesma moldura da mesma task). `false` = falta rodar
	## `python tools/status_assets.py --all`; nesse caso a tela NÃO abre em vez de inventar uma.
	_state = state
	_chrome_hd = AssetIO.texture("MENU/status/hd/chrome_9b.webp")
	_chrome = AssetIO.texture("MENU/status/stmain0u_p0.png")
	_pronto = _chrome != null or _chrome_hd != null
	return _pronto


func total_paginas() -> int:
	return (BAU_SLOTS + BAU_POR_PAGINA - 1) / BAU_POR_PAGINA


# ─────────────────────────────────── abrir / fechar ───────────────────────────────────

func abrir() -> bool:
	## Chamado quando o AOT de `sce 9` dispara com o botão de ação. Devolve `false` se os
	## assets faltam (a tela não abre e quem chamou decide o que dizer no HUD).
	if not _pronto or aberto:
		return aberto
	aberto = true
	visible = true
	_fechando = false
	_anim = ANIM_QUADROS
	lado = Lado.MAO
	sair_selecionado = false
	cursor_mao = 0
	cursor_bau = 0
	pagina = 0
	ultima_acao = ""
	queue_redraw()
	return true


func fechar() -> void:
	if not aberto or _fechando:
		return
	_fechando = true
	_anim = ANIM_QUADROS
	queue_redraw()


func avancar() -> void:
	## Um quadro: animação de cortina + piscada do cursor. Chamar do tick de 30 Hz.
	if not aberto:
		return
	if _anim > 0:
		_anim -= 1
		if _anim == 0 and _fechando:
			aberto = false
			_fechando = false
			visible = false
	# piscada: contador sobe e desce de 2 em 2 com clamp em 0x3f sobre a base 0x80
	if _piscada_sobe:
		_piscada += CURSOR_PASSO
		if _piscada >= 0x80 + CURSOR_TETO:
			_piscada_sobe = false
	else:
		_piscada -= CURSOR_PASSO
		if _piscada <= 0x80:
			_piscada_sobe = true
	queue_redraw()


func _t() -> float:
	## Fator da cortina: 1 = aberta.
	if _anim <= 0:
		return 1.0
	var f := float(ANIM_QUADROS - _anim) / float(ANIM_QUADROS)
	return f if not _fechando else 1.0 - f


# ─────────────────────────────────── navegação ───────────────────────────────────

func mover_cursor(dx: int, dy: int) -> void:
	if not aberto or _anim > 0:
		return
	if sair_selecionado:
		# de SAIR só se desce para a grade da mão (a placa fica em cima dela)
		if dy > 0:
			sair_selecionado = false
			lado = Lado.MAO
		elif dx < 0:
			sair_selecionado = false
			lado = Lado.BAU
		return
	if lado == Lado.MAO:
		var col := cursor_mao % MAO_COLUNAS
		var lin := cursor_mao / MAO_COLUNAS
		if dx < 0 and col == 0:
			lado = Lado.BAU                    ## sai pela esquerda → entra no baú
			cursor_bau = _clamp_bau(pagina * BAU_POR_PAGINA + lin * BAU_COLUNAS
				+ (BAU_COLUNAS - 1))
			return
		if dy < 0 and lin == 0:
			sair_selecionado = true             ## sobe da 1ª linha → placa SAIR
			return
		col = clampi(col + dx, 0, MAO_COLUNAS - 1)
		lin = clampi(lin + dy, 0, MAO_LINHAS - 1)
		cursor_mao = lin * MAO_COLUNAS + col
		return
	# lado == BAU
	var idx := cursor_bau - pagina * BAU_POR_PAGINA
	var bcol := idx % BAU_COLUNAS
	var blin := idx / BAU_COLUNAS
	if dx > 0 and bcol == BAU_COLUNAS - 1:
		lado = Lado.MAO                        ## sai pela direita → volta para a mão
		cursor_mao = clampi(blin, 0, MAO_LINHAS - 1) * MAO_COLUNAS
		return
	if dx < 0 and bcol == 0:
		mudar_pagina(-1)                       ## borda esquerda vira página (declarado)
		return
	if dy < 0 and blin == 0:
		sair_selecionado = true
		return
	if dy > 0 and blin == BAU_LINHAS - 1:
		mudar_pagina(1)
		return
	bcol = clampi(bcol + dx, 0, BAU_COLUNAS - 1)
	blin = clampi(blin + dy, 0, BAU_LINHAS - 1)
	cursor_bau = _clamp_bau(pagina * BAU_POR_PAGINA + blin * BAU_COLUNAS + bcol)


func mudar_pagina(d: int) -> void:
	## L1/R1 no original (`raw_held & 0xc`, repetição em `& 0x4`/`& 0x8`). Sem dar a volta:
	## o subestado clampa antes de redesenhar (não medi o wrap, então não invento).
	if not aberto:
		return
	var nova := clampi(pagina + d, 0, total_paginas() - 1)
	if nova == pagina:
		return
	pagina = nova
	var off := cursor_bau % BAU_POR_PAGINA
	cursor_bau = _clamp_bau(pagina * BAU_POR_PAGINA + off)
	lado = Lado.BAU
	sair_selecionado = false


func _clamp_bau(i: int) -> int:
	return clampi(i, 0, BAU_SLOTS - 1)


func cancelar() -> void:
	fechar()


# ─────────────────────────────────── transferência ───────────────────────────────────

func confirmar() -> String:
	## Botão de ação: transfere o slot sob o cursor para o outro lado, ou fecha se SAIR.
	## Devolve uma linha em PT-BR para o HUD ("" = nada aconteceu).
	if not aberto or _anim > 0 or _state == null:
		return ""
	if sair_selecionado:
		fechar()
		ultima_acao = "fechou o baú"
		return ultima_acao
	var de_box := lado == Lado.BAU
	var idx := cursor_bau if de_box else cursor_mao
	var id := _id_do_slot(idx, de_box)
	if id == 0:
		ultima_acao = "slot vazio"
		return ""
	var antes := _qtd_do_slot(idx, de_box)
	var r: GameState.Transf = _state.transferir(idx, de_box)
	var nome := _nome_do_item(id)
	match r:
		GameState.Transf.OK:
			ultima_acao = ("tirou %s do baú" % nome) if de_box else ("guardou %s" % nome)
		GameState.Transf.PARCIAL:
			var moveu := antes - _qtd_do_slot(idx, de_box)
			ultima_acao = "%s: transferiu %d (o resto não cabe)" % [nome, moveu]
		GameState.Transf.CHEIO:
			ultima_acao = "sem espaço " + ("no inventário" if de_box else "no baú")
			queue_redraw()
			return ""
		_:
			ultima_acao = "slot vazio"
			queue_redraw()
			return ""
	queue_redraw()
	return ultima_acao


func clicar(p: Vector2) -> String:
	## Clique/toque: 1º clique só move o cursor, 2º no mesmo lugar confirma (igual ao status).
	if not aberto or _anim > 0:
		return ""
	var pt := Vector2i(int(p.x), int(p.y))
	var c := _celula_mao(pt)
	if c >= 0:
		if lado == Lado.MAO and cursor_mao == c and not sair_selecionado:
			return confirmar()
		lado = Lado.MAO
		sair_selecionado = false
		cursor_mao = c
		queue_redraw()
		return ""
	c = _celula_bau(pt)
	if c >= 0:
		if lado == Lado.BAU and cursor_bau == c and not sair_selecionado:
			return confirmar()
		lado = Lado.BAU
		sair_selecionado = false
		cursor_bau = c
		queue_redraw()
		return ""
	var r := Rect2i(int(MOLDURA[0][4]), int(MOLDURA[0][5]) + 8, int(MOLDURA[0][2]), 16)
	if r.has_point(pt):
		if sair_selecionado:
			return confirmar()
		sair_selecionado = true
		queue_redraw()
	return ""


func _celula_mao(p: Vector2i) -> int:
	var r := Rect2i(MAO_ORIGEM, Vector2i(MAO_COLUNAS * CELULA.x, MAO_LINHAS * CELULA.y))
	if not r.has_point(p):
		return -1
	var col := (p.x - MAO_ORIGEM.x) / CELULA.x
	var lin := (p.y - MAO_ORIGEM.y) / CELULA.y
	return lin * MAO_COLUNAS + col


func _celula_bau(p: Vector2i) -> int:
	var r := Rect2i(BAU_ORIGEM, Vector2i(BAU_COLUNAS * CELULA.x, BAU_LINHAS * CELULA.y))
	if not r.has_point(p):
		return -1
	var col := (p.x - BAU_ORIGEM.x) / CELULA.x
	var lin := (p.y - BAU_ORIGEM.y) / CELULA.y
	return _clamp_bau(pagina * BAU_POR_PAGINA + lin * BAU_COLUNAS + col)


func _id_do_slot(idx: int, box: bool) -> int:
	var s: Array[Dictionary] = _state.box_slots if box else _state.main_slots
	return int(s[idx].get("id", 0)) if idx >= 0 and idx < s.size() else 0


func _qtd_do_slot(idx: int, box: bool) -> int:
	var s: Array[Dictionary] = _state.box_slots if box else _state.main_slots
	return int(s[idx].get("qtd", 0)) if idx >= 0 and idx < s.size() else 0


# ─────────────────────────────────── desenho ───────────────────────────────────

func _draw() -> void:
	if not aberto or _state == null:
		return
	var t := _t()
	if t <= 0.0:
		return
	# Fundo: os dois painéis sólidos (no jogo são TILE sem textura).
	_caixa(Rect2(0, 56, 320, 176), COR_TILE, t)
	_janela(Rect2(float(BAU_PAINEL[0]), float(BAU_PAINEL[1]),
		float(BAU_PAINEL[2]), float(BAU_PAINEL[3])), t)
	for r: Array in MOLDURA:
		_moldura(r, t)
	_desenhar_grade(t, false)
	_desenhar_grade(t, true)
	_desenhar_rotulos(t)
	_desenhar_cursor(t)


func _desenhar_grade(t: float, box: bool) -> void:
	var n := BAU_POR_PAGINA if box else MAO_COLUNAS * MAO_LINHAS
	for i in n:
		var idx := (pagina * BAU_POR_PAGINA + i) if box else i
		var id := _id_do_slot(idx, box)
		var p := _pos_celula(i, box)
		var tex := _icone(id)
		if tex != null:
			var destino := Rect2(float(p.x), float(p.y), float(CELULA.x), float(CELULA.y))
			if t < 1.0:
				destino.position.y = 120.0 + (destino.position.y - 120.0) * t
				destino.size.y *= t
			draw_texture_rect(tex, destino, false)
		# QUANTIDADE: o EXE só desenha o número quando o MODO (bits 0-1 de `slot+2`) != 0
		# (`0x8006c0a0` → `draw_number 0x8006c6d0`, e modo 0 pula o desenho). Mesma regra aqui.
		var s: Array[Dictionary] = _state.box_slots if box else _state.main_slots
		if idx < s.size():
			var fl := int(s[idx].get("flags", 0))
			if (fl & 3) != 0:
				_desenhar_qtd(int(s[idx].get("qtd", 0)), p + QTD_OFFSET, t, 2 + ((fl >> 2) & 3))


func _pos_celula(i: int, box: bool) -> Vector2i:
	if box:
		return BAU_ORIGEM + Vector2i((i % BAU_COLUNAS) * CELULA.x, (i / BAU_COLUNAS) * CELULA.y)
	return MAO_ORIGEM + Vector2i((i % MAO_COLUNAS) * CELULA.x, (i / MAO_COLUNAS) * CELULA.y)


func _desenhar_cursor(t: float) -> void:
	var r := CURSOR.duplicate()
	if sair_selecionado:
		r[2] = MOLDURA[0][2]
		r[3] = 16
		r[4] = MOLDURA[0][4]
		r[5] = int(MOLDURA[0][5]) + 8
	elif lado == Lado.MAO:
		var p := _pos_celula(cursor_mao, false)
		r[4] = p.x
		r[5] = p.y
	else:
		var p2 := _pos_celula(cursor_bau - pagina * BAU_POR_PAGINA, true)
		r[4] = p2.x
		r[5] = p2.y
	var b := 0.5 + 0.5 * float(_piscada - 0x80) / float(CURSOR_TETO)
	# O cursor vem do STMOJIU na paleta 3 (CLUT medida em (304,483) = vermelho), não do STMAIN0U.
	var tex := _atlas_paleta(3)
	if tex != null:
		_blit(tex, r, t, Color(b, b, b, 1.0), 0, _fator_paleta(3))
	else:
		var d := Rect2(float(r[4]), float(r[5]), float(r[2]), float(r[3]))
		draw_rect(d, Color(1.0, b * 0.4, b * 0.4, t), false, 1.0)


func _desenhar_rotulos(t: float) -> void:
	## Rótulos em PT-BR com a fonte do jogo (os originais são sprites do STMOJIU, e o atlas HD
	## disponível só existe em inglês/russo).
	var c := Color(1, 1, 1, t)
	Texto.desenhar(self, "SAIR", Vector2i(int(MOLDURA[0][4]) + 24, int(MOLDURA[0][5]) + 8), 0, c)
	Texto.desenhar(self, "BAU", Vector2i(BAU_ORIGEM.x, BAU_PAINEL[1] - 14), 0, c)
	Texto.desenhar(self, "%d/%d" % [pagina + 1, total_paginas()],
		Vector2i(BAU_ORIGEM.x + BAU_COLUNAS * CELULA.x - 40, BAU_PAINEL[1] - 14), 0, c)
	# nome do item sob o cursor (o original mostra numa placa; aqui é uma linha no rodapé)
	var id := _id_do_slot(cursor_bau if lado == Lado.BAU else cursor_mao, lado == Lado.BAU)
	if id != 0 and not sair_selecionado:
		Texto.desenhar(self, _nome_do_item(id), Vector2i(BAU_ORIGEM.x, 226), 0, c)


func _moldura(r: Array, t: float) -> void:
	if _chrome_hd != null:
		_blit(_chrome_hd, r, t, Color.WHITE, 0, 4)
	else:
		_blit(_chrome, r, t, Color.WHITE, U_TPAGE_9B)


func _blit(tex: Texture2D, r: Array, t: float, cor := Color.WHITE, du := 0, fator := 1,
		destino_tam := Vector2i.ZERO) -> void:
	if tex == null:
		return
	var origem := Rect2i((int(r[0]) + du) * fator, int(r[1]) * fator,
		int(r[2]) * fator, int(r[3]) * fator)
	var destino := Rect2(float(r[4]), float(r[5]),
		float(destino_tam.x) if destino_tam.x > 0 else float(r[2]),
		float(destino_tam.y) if destino_tam.y > 0 else float(r[3]))
	if t < 1.0:
		destino.position.y = 120.0 + (destino.position.y - 120.0) * t
		destino.size.y *= t
	draw_texture_rect_region(tex, destino, origem, cor)


func _caixa(r: Rect2, cor: Color, t: float) -> void:
	var d := r
	if t < 1.0:
		d.position.y = 120.0 + (d.position.y - 120.0) * t
		d.size.y *= t
	d = d.intersection(Rect2(0, 0, 320, 240))
	if d.size.x > 0.0 and d.size.y > 0.0:
		draw_rect(d, Color(cor.r, cor.g, cor.b, t))


func _janela(r: Rect2, t: float) -> void:
	_caixa(r, COR_AZUL, t)
	var d := r
	if t < 1.0:
		d.position.y = 120.0 + (d.position.y - 120.0) * t
		d.size.y *= t
	draw_rect(d, Color(COR_JANELA.r, COR_JANELA.g, COR_JANELA.b, t), false, 2.0)


func _desenhar_qtd(qtd: int, onde: Vector2i, t: float, paleta := 2) -> void:
	var tex := _atlas_paleta(paleta)
	if tex == null:
		return
	var fat := _fator_paleta(paleta)
	var s := str(qtd)
	var dw := int(round(DIGITO_W * QTD_ESCALA))
	var dh := int(round(DIGITO_H * QTD_ESCALA))
	var x := onde.x
	for k in s.length():
		var d := s.unicode_at(k) - 48
		if d < 0 or d > 9:
			continue
		_blit(tex, [DIGITO_U0 + d * DIGITO_W, DIGITO_V, DIGITO_W, DIGITO_H, x, onde.y],
			t, Color.WHITE, 0, fat, Vector2i(dw, dh))
		x += dw


func _atlas_paleta(i: int) -> Texture2D:
	if _paletas.has(i):
		return _paletas[i]
	var rel_hd := "MENU/status/hd/stmojiu_p%d.webp" % i
	var tex: Texture2D = AssetIO.texture(rel_hd) if AssetIO.exists(rel_hd) \
		else AssetIO.texture("MENU/status/stmojiu_p%d.png" % i)
	_paletas[i] = tex
	_paleta_fator[i] = 4 if AssetIO.exists(rel_hd) else 1
	return tex


func _fator_paleta(i: int) -> int:
	if not _paletas.has(i):
		_atlas_paleta(i)
	return int(_paleta_fator.get(i, 1))


func _icone(item_id: int) -> Texture2D:
	if _icones.has(item_id):
		return _icones[item_id]
	var rel_hd := "MENU/status/hd/itema/%03d.webp" % item_id
	var tex := AssetIO.texture(rel_hd) if AssetIO.exists(rel_hd) \
		else AssetIO.texture("MENU/status/itema/%03d.png" % item_id)
	_icones[item_id] = tex
	return tex


func _nome_do_item(id: int) -> String:
	if _itens_json.is_empty():
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/re3_items.json"))
		if raw is Dictionary:
			_itens_json = (raw as Dictionary).get("by_id", {})
	var e: Variant = _itens_json.get("0x%02x" % id)
	var d: Dictionary = e if e is Dictionary else {}
	return String(d.get("name_pt", d.get("name_en", "item 0x%02x" % id)))


func resumo() -> String:
	return "baú: aberto=%s lado=%s pag=%d/%d mão=%d baú=%d ocupados(mão=%d baú=%d)" % [
		aberto, Lado.keys()[lado], pagina + 1, total_paginas(), cursor_mao, cursor_bau,
		_state.item_count(false) if _state else 0, _state.item_count(true) if _state else 0]
