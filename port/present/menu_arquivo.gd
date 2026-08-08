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
const COLUNAS_GRADE := 5                 ## a grade de documentos é 5×3 (MenuStatus.ARQ_COLUNAS)
## A página em HD **e em português** é 1024×768 = 4× de 256×**192** (o SD é 256×176: o conjunto PT
## foi tipografado de novo numa caixa um pouco mais alta). Desenho no mesmo topo do SD.
const PAG_PT_W := 256
const PAG_PT_H := 192

var aberto := false
var sel := 0                             ## documento selecionado na lista
var pagina := 0                           ## página aberta (0 = capa)
var lendo := false
var docs: Array = []                      ## documentos que o jogador tem
var ultima_acao := ""

var _dados: Dictionary = {}
var _icones: Texture2D = null
var _icone_fator := 1                    ## 4 quando o atlas é o HD
const CEL_VAZIO := 31                    ## última célula da grade 4×8 = o sprite "VAZIO"
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
	## ÍCONES EM HD **E EM PORTUGUÊS**: `misc/12124B01` (512×1024 = 4× o `FILEI.TIM` de 128×256),
	## par já confirmado no `hd_ui_map.json` (NCC 0,903) com a nota "HD em portugues
	## (mod_BH3_Portuguese: COMO JOGAR/VAZIO)". A grade é 4 colunas × 8 linhas; em HD a célula tem
	## **128×128**. A **última célula (índice 31) é o sprite "VAZIO"** — o papel cinza com a palavra
	## batida, que é o que o jogo desenha em slot livre (eu estava escrevendo "VAZIO" com a fonte).
	_icones = AssetIO.texture("FILE/FILEI_hd.webp")
	_icone_fator = 4
	if _icones == null:
		_icones = AssetIO.texture("FILE/FILEI.png")
		_icone_fator = 1
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


func mover_lista(d: int) -> void:
	## Anda um documento na lista (usado pelos diags e pelo movimento vertical da grade).
	if not aberto or lendo:
		return
	sel = posmod(sel + d, maxi(1, docs.size()))
	pagina = 0
	queue_redraw()


func mover_grade(dx: int, dy: int) -> void:
	## A grade é 5×3 (`MenuStatus.ARQ_COLUNAS/LINHAS`), então **A/D andam na coluna e W/S na
	## linha** — é a navegação WSAD que o usuário pediu; antes A/D não faziam nada na grade e só
	## W/S andavam, um documento por vez.
	if not aberto or lendo or docs.is_empty():
		return
	var passo := dx + dy * COLUNAS_GRADE
	sel = clampi(sel + passo, 0, docs.size() - 1)
	pagina = 0
	queue_redraw()


func virar_pagina(d: int) -> void:
	## Vira a página do documento aberto. Recebe A/D **e** W/S (WSAD), como pedido.
	if not aberto or not lendo:
		return
	var doc: Dictionary = docs[sel]
	var n := int(doc.get("n_pages", 1))
	pagina = clampi(pagina + d, 0, n - 1)
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
	## A LISTA não é desenhada aqui: no jogo a tela de arquivo é outro `screen kind` da MESMA task,
	## ou seja fica DENTRO da moldura do status (a captura do jogo mostra a grade de documentos no
	## painel alto, com o retrato e o EQUIP ainda visíveis). Quem desenha a grade é
	## `MenuStatus._desenhar_arquivo`. Aqui só sobra a PÁGINA aberta, que ocupa a tela.
	if not aberto or not lendo:
		return
	draw_rect(Rect2(0, 0, 320, 240), Color.BLACK)
	if docs.is_empty():
		return
	_desenhar_pagina(docs[sel])


func icone_do_doc(doc: Dictionary) -> Texture2D:
	return _icones


func regiao_do_doc(doc: Dictionary) -> Rect2i:
	## Célula do documento na grade 4×8. O de-para documento → célula não foi provado; uso
	## `célula = doc`, e o atlas HD confirma a ordem (a célula 0 é "COMO JOGAR", que é o
	## documento 0 = Game Instructions A).
	return regiao_da_celula(int(doc.get("doc", 0)))


func regiao_da_celula(cel: int) -> Rect2i:
	var lado := ICONE * _icone_fator
	return Rect2i((cel % ICONE_COLUNAS) * lado, int(cel / ICONE_COLUNAS) * lado, lado, lado)


func nome_do_doc(doc: Dictionary) -> String:
	return _nome_do_doc(doc)


func _desenhar_lista_antiga() -> void:
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
	## ── PÁGINA EM HD E EM PORTUGUÊS ──
	## O `hires/memo` do usuário são **dois** conjuntos de 1024×768: 137 arquivos de jan/2025 em
	## **russo** (o pack Seamless é russo — foi o que meu casamento por conteúdo pegou antes, e por
	## isso dava página trocada) e **143 de jun/2025 em PORTUGUÊS**, tipografados de novo. O de-para
	## está em `data/hd_memo_pt.json`, feito lendo as 143 páginas e casando com a página SD; ele se
	## fecha em três contas independentes (`tools/memo_pt.py` explica). As 9 páginas SD sem PT são 6
	## em branco + 3 rabichos de uma linha, e nessas cai no SD.
	var tex: Texture2D = null
	if pagina > 0:
		var tp2: Array = doc.get("text_pages", [])
		if pagina - 1 < tp2.size():
			tex = AssetIO.texture("FILE/pt/pag_%03d.webp" % int(tp2[pagina - 1]))
	if tex != null:
		draw_texture_rect(tex, Rect2(32, 32, PAG_PT_W, PAG_PT_H), false)
		Texto.desenhar(self, "%d/%d" % [pagina + 1, n], Vector2i(270, 220))
		return
	tex = AssetIO.texture(rel)
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
