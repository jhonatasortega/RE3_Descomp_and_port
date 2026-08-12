class_name Mensagem
extends Node2D
## CAIXA DE MENSAGEM do jogo — o texto que aparece ao interagir com as caixas de ação (AOT),
## ao pegar item, ao usar uma porta trancada, ao subir escada, na máquina de escrever…
##
## É um sistema **dirigido por dado**: nada aqui é escrito caso a caso. Todo o texto vem de
## `data/mensagens.json` (gerado por `tools/mensagens.py`) — 1128 mensagens em 127 salas mais as
## duas pools lineares do EXE — e quem escolhe *qual* mensagem é o mesmo índice que o binário usa.
##
## ─────────────────────────────────────────────────────────────────────────────
## 1. O ABRIDOR DO JOGO — `0x8002fd30` (PROVADO)
## ─────────────────────────────────────────────────────────────────────────────
## O RE3 tem **um único** abridor de caixa de mensagem, com 30 sítios de `jal` no EXE:
##
##     0x8002fd30  abre_mensagem(a0, a1 = flags, a2 = índice, a3)
##
## `a1 & 0x3000` escolhe a POOL (`0x8002fd88`..`0x8002fdb4`), e cada pool tem a **sua** posição
## de caixa, lida como imediato:
##
##     0x0000  offs 0x80099654  texto 0x80098e88   caixa (34,185)   0x8002fdc4/0x8002fdcc
##     0x1000  offs 0x8009bdb4  texto 0x800996e4   caixa (14,173)   0x8002fdf0/0x8002fdf8
##     0x2000  offs = RDT+0x3c  (a seção MSG da SALA)  caixa (34,185)  0x8002fe20/0x8002fe2c
##
## `RDT + 0x3c` é `offset_table[13]` (a tabela começa em `RDT+0x08`, logo `(0x3c-8)/4 = 13`) —
## é aí que vive o texto **por sala**. Ver `docs/decomp/notes/messages.md §4` e o docstring de
## `tools/mensagens.py`.
##
## Quem dispara mensagem de sala:
##   • **AOT `sce == 4`** (`0x80051284`): índice = `u16@payload+0`, `a1 = u16@payload+2 | 0x2000`;
##   • **opcode `0x5B` do SCD** (`0x80054d74`): índice = `u8@+1`.
##
## ─────────────────────────────────────────────────────────────────────────────
## 2. GEOMETRIA E MÉTRICA
## ─────────────────────────────────────────────────────────────────────────────
## • **Posição da caixa**: as duas acima, MEDIDAS (imediatos de `0x8002fdc4`+).
## • **Altura de linha = 16 px**: `0x80030fb4` faz `y = *(u16*)(ctx+0x75de) + 0x10`.
## • **3 linhas por página**: o epílogo desenha 3 linhas em `x=34, y=185` com `attr = 0x100`
##   (`0x80031cd8`–`0x80031ce0`), e `185 + 3*16 = 233 ≤ 240`. Para a caixa de (14,173) o port usa
##   as mesmas 3 linhas — é também a altura da janela `B144` (200×48 em (12,172)) que a tela de
##   status usa para o mesmo texto. **DECLARADO** para a segunda caixa.
## • **Largura**: `320 − 2·x` (252 na caixa de 34, 292 na de 14). O jogo **não quebra por
##   largura** — ele quebra onde o dado tem `0xFC`; a quebra por pixel aqui é uma rede de
##   segurança para o PT-BR, que é mais comprido que o inglês. **DECLARADO.**
## • **Cor**: `attr>>4` é a linha de CLUT; `0x8003157c` faz `CLUT y = 480 | 2*(attr>>4)`. As
##   cores das 6 primeiras linhas estão MEDIDAS no `TEXU.TIM` (`menu_texto.md §1.6`) e são o
##   `CORES` abaixo. O `{c:1}` verde é o destaque de nome de item.
## • **Fonte**: `Texto` (atlas `ETC/TEXU.TIM` / o HD equivalente), célula 14×14 proporcional.
##
## ─────────────────────────────────────────────────────────────────────────────
## 3. MARCAÇÃO DO DADO (a que `tools/mensagens.py` grava)
## ─────────────────────────────────────────────────────────────────────────────
##     \n         nova linha              (0xFC)
##     {p}        nova PÁGINA             (0xFD xx)
##     {c:N}      cor N                   (0xF9 xx)
##     {i:NN}     nome do item NN em hex; {i:00} = "item corrente"   (0xF8 xx)
##     {sn}       prompt SIM/NÃO          (0xFB xx)
##     {op}       separador de OPÇÃO      (0xFE interno)
##     {s:NN}     efeito sonoro           (0xF3 xx)
##     {cam:NN}   troca de câmera         (0xF4 xx)
##     {t:NN}     temporização, sem efeito visual   (0xFA xx)
##
## ─────────────────────────────────────────────────────────────────────────────
## 4. O QUE ESTE NÓ *NÃO* FAZ
## ─────────────────────────────────────────────────────────────────────────────
## • Não desenha faixa/moldura atrás do texto: o EXE não monta primitiva de fundo nas duas
##   posições de caixa (só as `SPRT` de glifo). `fundo_visivel` existe para depuração e vem
##   **desligado**.
## • Não executa `{cam:NN}` (troca de câmera) nem toca `{s:NN}`: os dois são efeito colateral do
##   interpretador de mensagem do jogo, que **não foi decodificado**. Ficam expostos em
##   `camera_pedida()` / `sons_da_pagina()` para quem liga o mundo. **NÃO PROVADO.**
## • Não decide *quando* aparecer — isso é do `World`/`Player`/VM. Ver `mostrar_*` e o
##   relatório de ganchos.

const CAMINHO := "res://data/mensagens.json"
const CAMINHO_ITENS := "res://data/re3_items.json"

## `320×240` é o espaço de tela do PS1; o quadro do port é 4× (1280×960).
const ESCALA := 4
const LINHAS := 3                       ## ✅ epílogo desenha 3 linhas em (34,185)
const ALTURA_LINHA := 16                ## ✅ 0x80030fb4: y += 0x10
const MARGEM_SETA := Vector2i(12, 3)    ## onde o ▼ fica, relativo ao canto da caixa

## Linhas de CLUT MEDIDAS no bloco de CLUT do `ETC/TEXU.TIM` (`menu_texto.md §1.6`, coluna
## x=256 — a única que `draw_string`/`draw_message` usam).
const CORES := {
	0: Color8(0xd8, 0xd8, 0xc8),        ## branco/creme (normal)
	1: Color8(0x00, 0xb8, 0x28),        ## verde — destaque de nome de item
	2: Color8(0x98, 0x00, 0x48),        ## magenta
	3: Color8(0x68, 0x68, 0x68),        ## cinza (desabilitado)
	4: Color8(0x20, 0x50, 0xe8),        ## azul
	5: Color8(0xd8, 0xd8, 0xc8),        ## igual a 0
}

## Caracteres revelados por tick de 30 Hz. O mesmo passo que a tela de status já usa
## (`MenuStatus.DATILO_POR_TICK`). **DECLARADO**: o limite de digitação do jogo é um ponteiro
## (`0x800dbb64`), não uma taxa em caracteres — a taxa não foi medida.
const DATILO_POR_TICK := 2

enum Caixa {
	PROMPT,      ## pool `a1 & 0x3000 == 0`      — caixa (34,185)
	SISTEMA,     ## pool `a1 & 0x3000 == 0x1000` — caixa (14,173)
	SALA,        ## pool `a1 & 0x3000 == 0x2000` — caixa (34,185), texto do RDT da sala
}

## Emitido ao FECHAR. `resposta` = -1 quando não havia prompt, 0 = primeira opção (SIM),
## 1 = segunda (NÃO)… — a ordem é a do dado (`{op}`).
signal fechou(resposta: int)
## Emitido quando a página vira, com a lista de `{s:NN}` daquela página (ver §4).
signal pagina_virou(pagina: int, sons: Array)

static var _dados: Dictionary = {}
static var _itens: Dictionary = {}
static var _carregado := false

var ativa := false
var caixa: Caixa = Caixa.PROMPT
## Item "corrente" para o `{i:00}` — é o `0x800dbb5b` do jogo (`0x80030f80`).
var item_corrente := 0
var fundo_visivel := false              ## ver §4: só para depuração
var ultima_origem := ""                 ## "R100[2]", "prompt[22]"… para log/teste

var _paginas: Array = []                ## Array[Dictionary] — ver `_analisar`
var _pagina := 0
var _datilo := 0
var _opcao := 0
var _resposta := -1
var _sfx: Object = null


func _init() -> void:
	name = "Mensagem"
	z_index = 90                        ## acima do mundo, abaixo do menu de status
	## Mesma convenção do `MenuStatus`/`MenuBau`: o nó é escalado 4× e TODO o desenho aqui usa
	## coordenadas de 320×240 — as mesmas do binário.
	scale = Vector2(ESCALA, ESCALA)
	visible = false


# ───────────────────────────────── dado ─────────────────────────────────
static func _carregar() -> void:
	if _carregado:
		return
	_carregado = true
	if FileAccess.file_exists(CAMINHO):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
		if raw is Dictionary:
			_dados = raw
	else:
		push_error("Mensagem: %s ausente — rode `NOSTALGIA_OUT=port python tools/mensagens.py "
			% CAMINHO + "--build`")
	if FileAccess.file_exists(CAMINHO_ITENS):
		var ri: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_ITENS))
		if ri is Dictionary:
			_itens = (ri as Dictionary).get("by_id", {})


static func carregado() -> bool:
	_carregar()
	return not _dados.is_empty()


static func salas_com_mensagem() -> Array:
	_carregar()
	var k: Array = (_dados.get("salas", {}) as Dictionary).keys()
	k.sort()
	return k


static func n_da_sala(sala: String) -> int:
	_carregar()
	var v: Variant = (_dados.get("salas", {}) as Dictionary).get(sala)
	return (v as Array).size() if v is Array else 0


static func _pt_ou_en(e: Dictionary) -> String:
	## PT-BR sempre que existir; cai no EN só quando o mod não traduziu (regra do projeto).
	var pt := String(e.get("pt", ""))
	return pt if pt.strip_edges() != "" else String(e.get("en", ""))


static func texto_da_sala(sala: String, idx: int) -> String:
	## Mensagem `idx` da sala — o mesmo índice que o AOT `sce 4` (`u16@payload+0`) e o opcode
	## `0x5B` (`u8@+1`) passam em `a2`. `""` quando a sala não tem seção MSG ou o índice não existe.
	_carregar()
	var v: Variant = (_dados.get("salas", {}) as Dictionary).get(sala)
	if not (v is Array):
		return ""
	var a := v as Array
	if idx < 0 or idx >= a.size():
		return ""
	return _pt_ou_en(a[idx] as Dictionary)


static func _texto_pool(nome: String, idx: int) -> String:
	_carregar()
	var p: Variant = (_dados.get("pools", {}) as Dictionary).get(nome)
	if not (p is Dictionary):
		return ""
	var a: Variant = (p as Dictionary).get("msgs", [])
	if not (a is Array) or idx < 0 or idx >= (a as Array).size():
		return ""
	return _pt_ou_en((a as Array)[idx] as Dictionary)


static func texto_prompt(idx: int) -> String:
	## Pool `a1 & 0x3000 == 0` (`0x80098e88`): máquina de escrever, ervas, escada, PORTAS, epílogo.
	return _texto_pool("prompt", idx)


static func texto_sistema(idx: int) -> String:
	## Pool `a1 & 0x3000 == 0x1000` (`0x800996e4`): 16 mensagens de sistema + os exames de item
	## (`idx = 16 + item_id`).
	return _texto_pool("sistema", idx)


static func indice(nome: String, chave: String) -> int:
	## Os índices que o binário tem fixos, lidos do JSON (`porta`/`item`) em vez de repetidos aqui.
	_carregar()
	var g: Variant = _dados.get(nome)
	return int((g as Dictionary).get(chave, -1)) if g is Dictionary else -1


static func _sim_nao() -> Array:
	## A mini-pool `0x80098E80` (`"Yes" 0xFE "No" 0xFE`), em PT-BR pelo `card.xml` do mod.
	_carregar()
	var g: Variant = _dados.get("sim_nao")
	if g is Dictionary:
		var pt: Variant = (g as Dictionary).get("pt", [])
		if pt is Array and (pt as Array).size() == 2:
			return (pt as Array).duplicate()
	return ["Sim", "Não"]


static func nome_do_item(id: int) -> String:
	_carregar()
	var e: Variant = _itens.get("0x%02x" % id)
	if not (e is Dictionary):
		return ""
	var n := String((e as Dictionary).get("name_pt", ""))
	return n if n.strip_edges() != "" else String((e as Dictionary).get("name_en", ""))


# ── PORTA: a árvore de decisão de `0x80050d28`, resolvida em DADO ──
static func mensagem_de_porta(key_type: int, key_id: int, campo_11: int, campo_0d: int,
		tem_chave: bool) -> Dictionary:
	## Devolve `{caixa, idx}` — ou `{}` quando a porta não mostra mensagem nenhuma.
	##
	## A ordem é a de `0x80050d28` (ver `tools/mensagens.py §2`):
	##   `key_id & 0x80 == 0`  -> porta livre, sem mensagem                 (`0x80050d80`)
	##   `campo_11 & 0x40`     -> ESCADA: prompt 10 (sobe, `campo_0d == 4`) / 11 (desce)
	##   `key_type == 0xFE`    -> prompt 17    · `== 0xFF` -> prompt 18
	##   tem a chave           -> prompt 5 ("Você usou: {item}")
	##   não tem, `campo_11 & 0x80` -> mensagem DA SALA, índice `campo_11 & 0x0F`
	##   não tem, senão        -> prompt `key_type - 0x5F`
	_carregar()
	if (campo_11 & 0x40) != 0:
		return {"caixa": Caixa.PROMPT,
			"idx": indice("porta", "escada_sobe" if campo_0d == 4 else "escada_desce")}
	if (key_id & 0x80) == 0:
		return {}
	if key_type == 0xFE:
		return {"caixa": Caixa.PROMPT, "idx": indice("porta", "key_type_fe")}
	if key_type == 0xFF:
		return {"caixa": Caixa.PROMPT, "idx": indice("porta", "key_type_ff")}
	if tem_chave:
		return {"caixa": Caixa.PROMPT, "idx": indice("porta", "usou_a_chave")}
	if (campo_11 & 0x80) != 0:
		return {"caixa": Caixa.SALA, "idx": campo_11 & 0x0F}
	var base := indice("porta", "base_key_type")
	var i := key_type - base
	if i < 0:
		## QUIRK: 10 portas têm `Key_Id & 0x80` com `Key_Type == 0`. No motor `0x8006cc8c(0)` é
		## "achar slot VAZIO" e devolve >= 0 quase sempre, então o jogo cai no ramo "tem a chave"
		## e mostra `prompt[5]` = "Você usou: ." com nome de item VAZIO. Aqui não mostro nada.
		## **DECLARADO** (o texto do jogo nesse caso é lixo).
		return {}
	return {"caixa": Caixa.PROMPT, "idx": i}


static func salas_com_porta() -> Array:
	_carregar()
	var k: Array = (_dados.get("portas", {}) as Dictionary).keys()
	k.sort()
	return k


static func portas_da_sala(sala: String) -> Array:
	## Todas as portas que o SCD daquela sala registra, na ordem em que ele as registra.
	_carregar()
	var v: Variant = (_dados.get("portas", {}) as Dictionary).get(sala)
	return v as Array if v is Array else []


static func porta_da_sala(sala: String, aot: int) -> Dictionary:
	## O descritor de trancamento daquela porta, lido de `data/mensagens.json → portas` (extraído
	## do SCD por `tools/mensagens.py`): `{aot, door_type, knock, key_id, key_type, campo_11,
	## caixa, idx}`. Quando o SCD registra DUAS portas no mesmo AOT (R203, R508), vale a ÚLTIMA —
	## é o slot que o `SCE_DOOR_AOT_SET` deixa instalado.
	_carregar()
	var v: Variant = (_dados.get("portas", {}) as Dictionary).get(sala)
	if not (v is Array):
		return {}
	var achado: Dictionary = {}
	for e: Variant in v as Array:
		if e is Dictionary and int((e as Dictionary).get("aot", -1)) == aot:
			achado = e as Dictionary
	return achado


# ───────────────────────────── apresentação ─────────────────────────────
func ligar_sfx(sfx: Object) -> void:
	## O `Sfx` do jogo (`core/sfx.gd`). Sem ele a caixa funciona muda.
	_sfx = sfx


func mostrar(texto: String, qual: Caixa = Caixa.PROMPT, origem := "") -> bool:
	## Abre a caixa com um texto já na marcação do §3. `false` = nada a mostrar.
	if texto.strip_edges() == "":
		return false
	_paginas = _analisar(texto, _largura_max(qual))
	if _paginas.is_empty():
		return false
	caixa = qual
	ultima_origem = origem
	_pagina = 0
	_datilo = 0
	_opcao = 0
	_resposta = -1
	ativa = true
	visible = true
	pagina_virou.emit(0, sons_da_pagina())
	queue_redraw()
	return true


func mostrar_da_sala(sala: String, idx: int) -> bool:
	## O caminho do AOT `sce 4` e do opcode `0x5B`.
	return mostrar(texto_da_sala(sala, idx), Caixa.SALA, "%s[%d]" % [sala, idx])


func mostrar_prompt(idx: int, item := -1) -> bool:
	if item >= 0:
		item_corrente = item
	return mostrar(texto_prompt(idx), Caixa.PROMPT, "prompt[%d]" % idx)


func mostrar_sistema(idx: int, item := -1) -> bool:
	if item >= 0:
		item_corrente = item
	return mostrar(texto_sistema(idx), Caixa.SISTEMA, "sistema[%d]" % idx)


func mostrar_item_pego(item_id: int) -> bool:
	## `0x8006a1d8`: dentro de `0x8006a020` (o sítio que grava `{id,qtd,flags}` no slot) o jogo
	## chama `abre_mensagem(a1 = 0x1000, a2 = 6)` = **sistema[6]** = "Você pegou: {item}.",
	## com o item corrente. É a mensagem de PEGAR ITEM.
	return mostrar_sistema(indice("item", "pegou"), item_id)


func mostrar_sem_espaco() -> bool:
	## `0x80069dfc`: `a1 = 0x1000, a2 = 1` = "Você não pode carregar mais itens."
	return mostrar_sistema(indice("item", "sem_espaco"))


func mostrar_quer_pegar(item_id: int) -> bool:
	## `sistema[0]` = "Você quer pegar: {item}?" + prompt SIM/NÃO.
	return mostrar_sistema(indice("item", "quer_pegar"), item_id)


func mostrar_exame_de_item(item_id: int) -> bool:
	## `0x80069380` (`a1 = 0x1100`): o exame é `sistema[16 + item_id]`.
	return mostrar_sistema(indice("item", "exame_base") + item_id, item_id)


func mostrar_nada_aqui() -> bool:
	## `0x800516a4` (handler do `sce 11`): `prompt[4]` = "Não tem mais nada."
	return mostrar_prompt(indice("item", "nada_aqui"))


func mostrar_de_porta(key_type: int, key_id: int, campo_11: int, campo_0d: int,
		tem_chave: bool, sala := "") -> bool:
	var m := mensagem_de_porta(key_type, key_id, campo_11, campo_0d, tem_chave)
	if m.is_empty():
		return false
	var q: Caixa = m["caixa"]
	if q == Caixa.SALA:
		return mostrar_da_sala(sala, int(m["idx"]))
	return mostrar_prompt(int(m["idx"]))


func mostrar_da_porta_da_sala(sala: String, aot: int, tem_chave := false,
		item_da_chave := -1) -> bool:
	## **É ESTE O GANCHO DE PORTA**: uma linha no `World.atravessar`, ao lado do
	## `Sfx.porta_usada(sala, aot, tem_chave, ja_destrancada)` que já existe. Todo o resto
	## (trancamento, tipo de chave, escada, mensagem da sala) vem do dado.
	var d := porta_da_sala(sala, aot)
	if d.is_empty():
		return false
	if item_da_chave >= 0:
		item_corrente = item_da_chave
	elif tem_chave:
		item_corrente = int(d.get("key_type", 0))
	return mostrar_de_porta(int(d.get("key_type", 0)), int(d.get("key_id", 0)),
		int(d.get("campo_11", 0)), int(d.get("door_type", 0)), tem_chave, sala)


func fechar() -> void:
	if not ativa:
		return
	ativa = false
	visible = false
	if _sfx != null and _sfx.has_method("mensagem_fecha"):
		_sfx.call("mensagem_fecha")
	fechou.emit(_resposta)
	queue_redraw()


# ── entrada ──
func avancar() -> void:
	## Um tick de 30 Hz: anda a máquina de escrever.
	if not ativa:
		return
	var n := _chars_da_pagina()
	if _datilo < n:
		_datilo = mini(_datilo + DATILO_POR_TICK, n)
		queue_redraw()


func acao() -> bool:
	## Botão de AÇÃO. Primeiro toque **pula a datilografia**; depois vira a página; na última
	## página fecha. Devolve `true` se consumiu o botão (o mundo não deve reagir a ele).
	if not ativa:
		return false
	var n := _chars_da_pagina()
	if _datilo < n:
		_datilo = n
		queue_redraw()
		return true
	if esperando_resposta():
		_resposta = _opcao
	if _pagina + 1 < _paginas.size():
		_pagina += 1
		_datilo = 0
		if _sfx != null and _sfx.has_method("mensagem_avanca"):
			_sfx.call("mensagem_avanca")
		pagina_virou.emit(_pagina, sons_da_pagina())
		queue_redraw()
		return true
	fechar()
	return true


func cancelar() -> bool:
	## Botão de CANCELAR: fecha a caixa. Num prompt SIM/NÃO responde a ÚLTIMA opção.
	if not ativa:
		return false
	if esperando_resposta():
		_resposta = maxi(0, _opcoes().size() - 1)
	fechar()
	return true


func mover(dy: int) -> bool:
	## Direcional. Num prompt SIM/NÃO troca a opção; fora dele, para baixo pula a datilografia
	## (é o que a tela de status já faz em `MenuStatus.avancar`).
	if not ativa:
		return false
	if esperando_resposta():
		var ops := _opcoes()
		if ops.size() > 1 and dy != 0:
			_opcao = posmod(_opcao + dy, ops.size())
			queue_redraw()
			return true
	if dy > 0:
		var n := _chars_da_pagina()
		if _datilo < n:
			_datilo = n
			queue_redraw()
			return true
	return false


func esperando_resposta() -> bool:
	## A página corrente tem prompt SIM/NÃO (`{sn}`) e o texto já apareceu todo.
	if not ativa or _pagina >= _paginas.size():
		return false
	return bool((_paginas[_pagina] as Dictionary).get("prompt", false)) \
		and _datilo >= _chars_da_pagina()


func opcao_atual() -> int:
	return _opcao


func resposta() -> int:
	return _resposta


func sons_da_pagina() -> Array:
	## Os `{s:NN}` da página corrente. Ver §4: NÃO são tocados por este nó.
	if _pagina >= _paginas.size():
		return []
	return (_paginas[_pagina] as Dictionary).get("sons", [])


func camera_pedida() -> int:
	## O `{cam:NN}` da página corrente, ou -1. Ver §4: NÃO é executado por este nó.
	if _pagina >= _paginas.size():
		return -1
	return int((_paginas[_pagina] as Dictionary).get("cam", -1))


func pagina() -> int:
	return _pagina


func total_paginas() -> int:
	return _paginas.size()


func posicao_da_caixa(qual := caixa) -> Vector2i:
	## ✅ imediatos de `0x8002fdc4`/`0x8002fdcc` e `0x8002fdf0`/`0x8002fdf8`.
	return Vector2i(14, 173) if qual == Caixa.SISTEMA else Vector2i(34, 185)


func _largura_max(qual: Caixa) -> int:
	return 320 - 2 * posicao_da_caixa(qual).x


# ───────────────────────────── o interpretador ─────────────────────────────
func _opcoes() -> Array:
	if _pagina >= _paginas.size():
		return []
	return (_paginas[_pagina] as Dictionary).get("opcoes", [])


func _chars_da_pagina() -> int:
	if _pagina >= _paginas.size():
		return 0
	return int((_paginas[_pagina] as Dictionary).get("chars", 0))


func _expandir(texto: String) -> String:
	## Troca `{i:NN}` pelo nome do item (`{i:00}` = item corrente, o `0x800dbb5b` do jogo).
	var fora := ""
	var i := 0
	while i < texto.length():
		if texto[i] == "{":
			var f := texto.find("}", i)
			if f < 0:
				fora += texto.substr(i)
				break
			var tag := texto.substr(i + 1, f - i - 1)
			if tag.begins_with("i:"):
				var id := tag.substr(2).hex_to_int()
				fora += nome_do_item(item_corrente if id == 0 else id)
			else:
				fora += "{%s}" % tag
			i = f + 1
		else:
			fora += texto[i]
			i += 1
	return fora


func _analisar(texto: String, largura: int) -> Array:
	## `texto` (marcação do §3) -> lista de PÁGINAS, cada uma
	## `{linhas: [[{t, c}]], chars: int, prompt: bool, opcoes: [String], sons: [int], cam: int}`.
	##
	## Quebra em 3 passos: (1) `{p}` separa páginas do DADO; (2) dentro da página os pedaços
	## coloridos são quebrados por largura em linhas; (3) se sobrar mais de `LINHAS` linhas, o
	## excedente vira PÁGINA NOVA — o jogo não faz isso (ele confia no `0xFC` do dado), mas em
	## PT-BR o texto é mais comprido e sem isto a última linha desapareceria. **DECLARADO.**
	var paginas: Array = []
	for bruto: String in _expandir(texto).split("{p}"):
		var pg := _analisar_pagina(bruto, largura)
		if pg.is_empty():
			continue
		for p: Dictionary in pg:
			paginas.append(p)
	return paginas


func _analisar_pagina(bruto: String, largura: int) -> Array:
	var cor := 0
	var sons: Array = []
	var cam := -1
	var prompt := false
	var opcoes: Array = []
	## `pedacos` = sequência de `{t, c}` e marcas de nova linha (`{nl: true}`).
	var pedacos: Array = []
	var atual := ""
	var i := 0
	var corpo := bruto
	## `{sn}` abre a LISTA DE OPÇÕES: tudo que vem depois dele (na própria entrada e nas partes
	## separadas por `{op}`) é opção, não corpo. É o caso do R110[1] no dado — `{sn}` e em
	## seguida "Lutar com monstro." `0xFE` "Entrar na delegacia." `0xFE`.
	## Quando não há texto de opção nenhum (o caso comum: "Você quer pegar: X?{sn}"), as opções
	## são a mini-pool `Yes`/`No` de `0x80098E80` — em PT-BR "Sim"/"Não".
	if corpo.contains("{sn}"):
		prompt = true
		var partes := corpo.split("{op}")
		var cabeca := String(partes[0])
		var f := cabeca.find("{sn}")
		corpo = cabeca.substr(0, f)
		var resto := _limpar(cabeca.substr(f + 4))
		if resto != "":
			opcoes.append(resto)
		for k in range(1, partes.size()):
			var o := _limpar(String(partes[k]))
			if o != "":
				opcoes.append(o)
		if opcoes.is_empty():
			opcoes = _sim_nao()
	elif corpo.contains("{op}"):
		corpo = String(corpo.split("{op}")[0])
	while i < corpo.length():
		var ch := corpo[i]
		if ch == "{":
			var f := corpo.find("}", i)
			if f < 0:
				break
			var tag := corpo.substr(i + 1, f - i - 1)
			if atual != "":
				pedacos.append({"t": atual, "c": cor})
				atual = ""
			if tag.begins_with("c:"):
				cor = tag.substr(2).to_int()
			elif tag.begins_with("s:"):
				sons.append(tag.substr(2).hex_to_int())
			elif tag.begins_with("cam:"):
				cam = tag.substr(4).hex_to_int()
			elif tag == "sn":
				prompt = true
			i = f + 1
			continue
		if ch == "\n":
			if atual != "":
				pedacos.append({"t": atual, "c": cor})
				atual = ""
			pedacos.append({"nl": true})
			i += 1
			continue
		atual += ch
		i += 1
	if atual != "":
		pedacos.append({"t": atual, "c": cor})

	var linhas := _quebrar(pedacos, largura)
	# tira linhas vazias no fim (o dado tem muito `\n` de sobra)
	while linhas.size() > 0 and _texto_da_linha(linhas[linhas.size() - 1]).strip_edges() == "":
		linhas.remove_at(linhas.size() - 1)
	if linhas.is_empty() and opcoes.is_empty():
		return []
	## As opções ficam SEMPRE na última página, juntas — nunca cortadas ao meio. Por isso o
	## corpo é paginado com `LINHAS - nº de opções` linhas por página.
	var por_pagina := maxi(1, LINHAS - opcoes.size()) if opcoes.size() > 0 else LINHAS
	var saida: Array = []
	var k := 0
	while k < linhas.size() or (saida.is_empty() and opcoes.size() > 0):
		var bloco: Array = linhas.slice(k, mini(k + por_pagina, linhas.size()))
		var ultima := k + por_pagina >= linhas.size()
		if ultima and opcoes.size() > 0:
			for o: String in opcoes:
				bloco.append([{"t": o, "c": 0}])
		var n := 0
		for l: Array in bloco:
			n += _texto_da_linha(l).length()
		saida.append({
			"linhas": bloco, "chars": n,
			"prompt": prompt and ultima,
			"opcoes": opcoes if ultima else [],
			"sons": sons if k == 0 else [], "cam": cam if k == 0 else -1,
		})
		k += por_pagina
	return saida


func _limpar(s: String) -> String:
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
	return out.replace("\n", " ").strip_edges()


func _texto_da_linha(linha: Array) -> String:
	var s := ""
	for p: Dictionary in linha:
		s += String(p.get("t", ""))
	return s


func _quebrar(pedacos: Array, largura: int) -> Array:
	## Quebra os pedaços coloridos em linhas de até `largura` px, pela métrica proporcional da
	## fonte (`Texto.largura`) — a mesma coisa que `Texto.quebrar` faz, mas preservando a COR de
	## cada trecho (um `{c:1}` no meio da frase não pode virar linha nova).
	var linhas: Array = []
	var linha: Array = []
	var w := 0
	for p: Dictionary in pedacos:
		if bool(p.get("nl", false)):
			linhas.append(linha)
			linha = []
			w = 0
			continue
		var cor := int(p.get("c", 0))
		var palavras := String(p.get("t", "")).split(" ")
		for j in palavras.size():
			var palavra := String(palavras[j])
			var com_espaco := palavra if (j == 0 and linha.is_empty()) else " " + palavra
			var lw := Texto.largura(com_espaco)
			if w + lw > largura and not linha.is_empty():
				linhas.append(linha)
				linha = []
				w = 0
				com_espaco = palavra
				lw = Texto.largura(palavra)
			if com_espaco == "":
				continue
			if linha.size() > 0 and int((linha[linha.size() - 1] as Dictionary).get("c", 0)) == cor:
				(linha[linha.size() - 1] as Dictionary)["t"] = \
					String((linha[linha.size() - 1] as Dictionary)["t"]) + com_espaco
			else:
				linha.append({"t": com_espaco, "c": cor})
			w += lw
	linhas.append(linha)
	return linhas


# ───────────────────────────── desenho ─────────────────────────────
func _draw() -> void:
	desenhar(self)


func desenhar(ci: CanvasItem, deslocamento := Vector2i.ZERO) -> void:
	## Desenha a caixa em QUALQUER `CanvasItem`, em coordenadas de 320×240 (`deslocamento` move
	## tudo junto). É o que o `port/dev/shot_mensagem.gd` usa para montar a tira de prova, e o que
	## permite ao `Screen` desenhar a caixa dentro de outra camada em vez de um nó próprio.
	if not ativa or _pagina >= _paginas.size():
		return
	var pg := _paginas[_pagina] as Dictionary
	var org := posicao_da_caixa() + deslocamento
	var larg := _largura_max(caixa)
	if fundo_visivel:
		ci.draw_rect(Rect2(org.x - 2, org.y - 2, larg + 4, LINHAS * ALTURA_LINHA + 3),
			Color(0, 0, 0, 0.55), true)
	var restante := _datilo
	var y := org.y
	var linhas: Array = pg.get("linhas", [])
	var ops: Array = pg.get("opcoes", [])
	var i_linha := 0
	for linha: Array in linhas:
		var x := org.x
		# a OPÇÃO selecionada do prompt ganha o ▶ e a cor de destaque
		var e_opcao := ops.size() > 0 and i_linha >= linhas.size() - ops.size()
		var selecionada := e_opcao and esperando_resposta() \
			and (i_linha - (linhas.size() - ops.size())) == _opcao
		if selecionada:
			Texto.desenhar_seta(ci, Texto.SETA_DIREITA, Vector2i(x - 12, y), CORES[1])
		for p: Dictionary in linha:
			var t := String(p.get("t", ""))
			if restante <= 0:
				break
			if t.length() > restante:
				t = t.substr(0, restante)
			restante -= t.length()
			var cor: Color = CORES[1] if selecionada else CORES.get(int(p.get("c", 0)), CORES[0])
			x += Texto.desenhar(ci, t, Vector2i(x, y), 0, cor)
		y += ALTURA_LINHA
		i_linha += 1
	# ▼ = "há mais texto" (o glifo 0x0B da própria fonte, não um sprite de fora)
	if _datilo >= _chars_da_pagina() and _pagina + 1 < _paginas.size():
		Texto.desenhar_seta(ci, Texto.SETA_BAIXO,
			Vector2i(org.x + larg - MARGEM_SETA.x,
				org.y + LINHAS * ALTURA_LINHA - MARGEM_SETA.y), CORES[0])


func resumo() -> String:
	if not ativa:
		return "mensagem: fechada"
	return "mensagem %s  pág %d/%d  %d/%d chars%s" % [
		ultima_origem, _pagina + 1, _paginas.size(), _datilo, _chars_da_pagina(),
		("  prompt op=%d" % _opcao) if esperando_resposta() else ""]
