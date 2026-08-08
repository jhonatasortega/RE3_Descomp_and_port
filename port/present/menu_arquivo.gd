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
const LINHAS_GRADE := 3
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
const COR_SETA := Color8(0, 220, 0)      ## verde da seta, como na captura do jogo
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
	## ── A GRADE TEM SLOT FIXO POR DOCUMENTO ──
	## O usuário apontou duas coisas: no jogo os documentos têm posição fixa, e **o cursor anda pela
	## grade mesmo com slot vazio**. Então `docs` é a lista COMPLETA dos 31 documentos, na ordem do
	## `FILEGU` (que é a ordem do atlas `FILEI`, já confirmada pela semântica dos ícones), e o que
	## muda por documento é ter sido **LIDO** ou não: lido mostra o ícone, não lido mostra o `VAZIO`.
	## Só entra na leitura quem foi lido — pegar do chão conta, e os dois iniciais (`0x83`/`0x84`)
	## precisam de USAR.
	docs = (_dados.get("documentos", []) as Array).duplicate()
	sel = 0
	pagina = 0
	lendo = false
	aberto = true
	visible = true
	queue_redraw()


func lido(i: int) -> bool:
	## O documento do slot `i` já foi lido? (é o que decide ícone × VAZIO e se dá para abrir)
	if i < 0 or i >= docs.size() or _state == null:
		return false
	return _state.arquivo_lido(int((docs[i] as Dictionary).get("item_id", 0)))


func n_lidos() -> int:
	var n := 0
	for i in docs.size():
		if lido(i):
			n += 1
	return n


func ir_para_doc(doc: int) -> void:
	## Cursor no slot do documento e abre a LEITURA (é o que USAR faz).
	if doc < 0 or doc >= docs.size():
		return
	sel = doc
	lendo = true
	pagina = 0
	queue_redraw()


func ir_para_item(item_id: int) -> void:
	## Põe o cursor no documento daquele item e abre a LEITURA — é o que USAR num documento faz.
	for i in docs.size():
		if int((docs[i] as Dictionary).get("item_id", 0)) == item_id:
			sel = i
			lendo = true
			pagina = 0
			queue_redraw()
			return


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
	## Grade 5 colunas × 3 linhas (15 por página), como na captura do jogo.
	##   • **W/S** andam na LINHA, dentro da página;
	##   • **A/D** andam na COLUNA e, na borda, **VIRAM A PÁGINA** mantendo a linha — é o que a
	##     captura mostra: seta verde `▶` à direita na página 1 e `◀` à esquerda na página 2.
	if not aberto or lendo or docs.is_empty():
		return
	## Anda por SLOT, não por documento lido — a grade é fixa, então o cursor passa pelos vazios.
	var por_pagina := COLUNAS_GRADE * LINHAS_GRADE
	var pag := sel / por_pagina
	var idx := sel % por_pagina
	var col := idx % COLUNAS_GRADE
	var lin := idx / COLUNAS_GRADE
	if dy != 0:
		lin = clampi(lin + dy, 0, LINHAS_GRADE - 1)
	elif dx > 0:
		if col < COLUNAS_GRADE - 1:
			col += 1
		elif (pag + 1) * por_pagina < docs.size():
			pag += 1
			col = 0
		else:
			return
	elif dx < 0:
		if col > 0:
			col -= 1
		elif pag > 0:
			pag -= 1
			col = COLUNAS_GRADE - 1
		else:
			return
	sel = clampi(pag * por_pagina + lin * COLUNAS_GRADE + col, 0, docs.size() - 1)
	pagina = 0
	queue_redraw()


func n_paginas_grade() -> int:
	var por := COLUNAS_GRADE * LINHAS_GRADE
	return maxi(1, (docs.size() + por - 1) / por)


func pagina_grade() -> int:
	return sel / (COLUNAS_GRADE * LINHAS_GRADE)


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
	elif lido(sel):
		lendo = true
		pagina = 0
	else:
		ultima_acao = "slot vazio: documento ainda não foi lido"
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
	if docs.is_empty() or not lido(sel):
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
		## CENTRALIZADA em 320×240: a página PT/HD tem 256×192, então sobra 32 de cada lado e 24
		## em cima/embaixo. Antes eu desenhava em (32,32), colada no topo.
		var px := (320 - PAG_PT_W) / 2
		var py := (240 - PAG_PT_H) / 2
		draw_texture_rect(tex, Rect2(px, py, PAG_PT_W, PAG_PT_H), false)
		_setas_pagina(n, px, py, PAG_PT_H)
		Texto.desenhar(self, "%d/%d" % [pagina + 1, n], Vector2i(270, 224))
		return
	tex = AssetIO.texture(rel)
	if tex == null:
		Texto.desenhar(self, "pagina ausente", Vector2i(100, 110))
		return
	if pagina == 0:
		draw_texture_rect_region(tex, Rect2((320 - CAPA_W) / 2, (240 - CAPA_H) / 2,
			CAPA_W, CAPA_H), Rect2i(0, 0, CAPA_W, CAPA_H))
		_setas_pagina(n, (320 - CAPA_W) / 2, (240 - CAPA_H) / 2, CAPA_H)
	else:
		draw_texture_rect(tex, Rect2((320 - PAG_W) / 2, (240 - PAG_H) / 2, PAG_W, PAG_H), false)
		_setas_pagina(n, (320 - PAG_W) / 2, (240 - PAG_H) / 2, PAG_H)
	Texto.desenhar(self, "%d/%d" % [pagina + 1, n], Vector2i(270, 224))


func _setas_pagina(n: int, px: int, py: int, alt: int) -> void:
	## Setas VERDES ao lado da página, como na captura: `▶` (glifo 0x02 da fonte) à direita quando
	## há próxima e o mesmo glifo ESPELHADO à esquerda quando há anterior — a fonte não tem `◀`.
	var y := py + alt / 2 - 7
	if pagina + 1 < n:
		Texto.desenhar_seta(self, Texto.SETA_DIREITA, Vector2i(px + 264, y), COR_SETA)
	if pagina > 0:
		Texto.desenhar_seta(self, Texto.SETA_DIREITA, Vector2i(px - 18, y), COR_SETA, 1.0, true)


static var _itens_json: Dictionary = {}


func _nome_do_doc(doc: Dictionary) -> String:
	## ── POR QUE O CACHE (medido) ──
	## Esta função era chamada por `MenuStatus._desenhar_arquivo` **a cada quadro** e relia +
	## reparseava o `res://data/re3_items.json` (104 KB) toda vez. Medido: **9,85 ms por parse**
	## (60 parses = 590,9 ms), num orçamento de 16 ms de quadro. O efeito na tela de ARQUIVO, com
	## um documento lido (é o que faz o nome ser desenhado): **19,69 ms/quadro (51 fps)** contra
	## 12,68 ms sem o nome e 11,31 ms no mundo — ou seja o desenho do NOME custava ~7 ms sozinho.
	## Engasgo desse tamanho é o que faz o jogo parecer "pausado" e faz o áudio picar; era uma
	## das suspeitas do relato "entrar no inventário pausa o game". Agora o JSON é lido UMA vez.
	if _itens_json.is_empty():
		var raw: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/re3_items.json"))
		if raw is Dictionary:
			_itens_json = (raw as Dictionary).get("by_id", {})
	var id := int(doc.get("item_id", 0))
	var e: Variant = _itens_json.get("0x%02x" % id)
	if e is Dictionary:
		return String((e as Dictionary).get("name_pt",
			(e as Dictionary).get("name_en", "documento %d" % id)))
	return "documento %d" % id
