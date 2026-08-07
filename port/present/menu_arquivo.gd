class_name MenuArquivo
extends Node2D
## Tela de ARQUIVO (documentos) — P6-04.
##
## Fonte: `docs/decomp/notes/menu_texto.md` §4 + `data/re3_file_screen.json`
## (gerado por `tools/menu_texto.py --file`).
##
## ── O achado que simplifica tudo ──
## **O texto dos documentos é BITMAP pré-renderizado**, não texto desenhado com a fonte: o
## `ETC/FILEGU.PIX` traz **31 documentos em 183 páginas** de 128×256 (8bpp na capa, 4bpp nas
## páginas de texto). É por isso que existe um `FILEGJ`/`FILEGU` por idioma. Já extraídas em
## `assets/FILE/` (`capa_NNN.png` e `pag_NNN.png`).
##
## ── Tamanhos, medidos nos descritores de `0x8009f2ec` ──
##   capa:           128×**168** (a arte ocupa só as 168 primeiras linhas das 256)
##   página de texto: 256×**176** — exatamente a página
##   setas de virar:  12×12 (dois descritores, `u=12` e `u=28`)
## As páginas vão para a VRAM em (448,256) CLUT 490 (capa, tpage `0x97`) e (512,256) CLUT 491
## (texto, tpage `0x18`) — casa com as páginas 23 e 24 do alocador.
##
## ── O que NÃO foi medido (declarado) ──
## A POSIÇÃO de tela das primitivas não está nos descritores: `0x8006e600` escreve `u,v,clut,w,h`
## mas não o `x,y`, que vem de buffers de RAM inicializados em outro lugar. Então centralizo no
## espaço 320×240 (texto em (32,32), capa em (96,36)) — escolha do port, não medida.
## O de-para documento → célula do `FILEI.TIM` (grade 4×8 de 32×32, 32 células para 31 documentos)
## também não foi provado; uso `célula = doc`, que é o palpite óbvio e está declarado.

const CAMINHO := "res://data/re3_file_screen.json"
const CAPA_W := 128
const CAPA_H := 168
const PAG_W := 256
const PAG_H := 176
const ICONE := 32                        ## célula do FILEI (grade 4×8)
const ICONE_COLUNAS := 4
const ESCALA := 4

var aberto := false
var sel := 0                             ## documento selecionado na lista
var pagina := 0                           ## página aberta (0 = capa)
var lendo := false
var docs: Array = []                      ## documentos que o jogador tem
var ultima_acao := ""

var _dados: Dictionary = {}
var _icones: Texture2D = null
var _state: GameState = null


func _init() -> void:
	name = "MenuArquivo"
	visible = false
	scale = Vector2(ESCALA, ESCALA)
	z_index = 110                         ## acima da tela de status


func carregar(state: GameState) -> bool:
	_state = state
	if not FileAccess.file_exists(CAMINHO):
		push_error("MenuArquivo: %s ausente — rode `python tools/menu_texto.py --file`" % CAMINHO)
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
	if not (raw is Dictionary):
		return false
	_dados = raw
	_icones = AssetIO.texture("FILE/FILEI.png")
	return true


func abrir() -> void:
	## Monta a lista com os documentos QUE O JOGADOR TEM. O critério do jogo é o bit em
	## `0x800d212c` que o handler de "ler arquivo" acende (kind 3 do menu); o port ainda não
	## acompanha esse bit, então lista os documentos cujo ITEM está no inventário (categoria 7 =
	## arquivo no descritor). Declarado: é subconjunto do critério real, não invenção.
	docs = []
	var todos: Array = _dados.get("documentos", [])
	for d: Dictionary in todos:
		var item := int(d.get("item_id", 0))
		if _state != null and _state.find_by_id(item) >= 0:
			docs.append(d)
	if docs.is_empty():
		# sem documento no inventário, mostra todos (modo de inspeção) para a tela não ficar vazia
		docs = todos.duplicate()
		ultima_acao = "nenhum documento no inventário: listando todos (inspeção)"
	sel = 0
	pagina = 0
	lendo = false
	aberto = true
	visible = true
	queue_redraw()


func fechar() -> void:
	aberto = false
	visible = false
	queue_redraw()


func mover(d: int) -> void:
	if not aberto:
		return
	if lendo:
		var doc: Dictionary = docs[sel]
		var n := int(doc.get("n_pages", 1))
		pagina = clampi(pagina + d, 0, n - 1)
	else:
		sel = posmod(sel + d, maxi(1, docs.size()))
		pagina = 0
	queue_redraw()


func confirmar() -> void:
	if not aberto:
		return
	if lendo:
		fechar()
	else:
		lendo = true
		pagina = 0
	queue_redraw()


func cancelar() -> void:
	if lendo:
		lendo = false
		queue_redraw()
	else:
		fechar()


func _draw() -> void:
	if not aberto:
		return
	draw_rect(Rect2(0, 0, 320, 240), Color.BLACK)
	if docs.is_empty():
		Texto.desenhar(self, "SEM ARQUIVOS", Vector2i(110, 110))
		return
	var doc: Dictionary = docs[sel]
	if lendo:
		_desenhar_pagina(doc)
	else:
		_desenhar_lista()


func _desenhar_lista() -> void:
	## Lista: ícone 32×32 do `FILEI` + nome do documento (do `re3_items.json`, em PT).
	Texto.desenhar(self, "ARQUIVO", Vector2i(20, 14))
	var y := 34
	for i in docs.size():
		var doc: Dictionary = docs[i]
		var cel := int(doc.get("doc", i))
		if _icones != null:
			var u := (cel % ICONE_COLUNAS) * ICONE
			var v := int(cel / ICONE_COLUNAS) * ICONE
			draw_texture_rect_region(_icones, Rect2(24, y, 24, 24),
				Rect2i(u, v, ICONE, ICONE))
		var nome := _nome_do_doc(doc)
		Texto.desenhar(self, nome, Vector2i(54, y + 5),
			0, Color.WHITE if i == sel else Color(0.62, 0.62, 0.7))
		if i == sel:
			draw_rect(Rect2(20, y - 2, 280, 28), Color8(128, 0, 0), false, 1.0)
		y += 30
		if y > 210:
			break


func _desenhar_pagina(doc: Dictionary) -> void:
	## Página 0 = capa (128×168), demais = página de texto (256×176). Os números de página vêm
	## do índice (`cover_page` e `text_pages`), que saiu da tabela do EXE.
	var n := int(doc.get("n_pages", 1))
	var rel := ""
	if pagina == 0:
		rel = "FILE/capa_%03d.png" % int(doc.get("cover_page", 1))
	else:
		var tp: Array = doc.get("text_pages", [])
		var idx := pagina - 1
		if idx < tp.size():
			rel = "FILE/pag_%03d.png" % int(tp[idx])
	var tex := AssetIO.texture(rel)
	if tex == null:
		Texto.desenhar(self, "pagina ausente", Vector2i(100, 110))
		return
	if pagina == 0:
		draw_texture_rect_region(tex, Rect2(96, 36, CAPA_W, CAPA_H),
			Rect2i(0, 0, CAPA_W, CAPA_H))
	else:
		draw_texture_rect(tex, Rect2(32, 32, PAG_W, PAG_H), false)
	Texto.desenhar(self, "%d/%d" % [pagina + 1, n], Vector2i(270, 220))


func _nome_do_doc(doc: Dictionary) -> String:
	var id := int(doc.get("item_id", 0))
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/re3_items.json"))
	if raw is Dictionary:
		var e: Variant = ((raw as Dictionary).get("by_id", {}) as Dictionary).get("0x%02x" % id)
		if e is Dictionary:
			return String((e as Dictionary).get("name_pt",
				(e as Dictionary).get("name_en", "documento %d" % id)))
	return "documento %d" % id
