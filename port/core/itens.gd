class_name Itens
extends RefCounted
## Regras de ITEM lidas do EXE: descritor, combinação e cura (P6-02 / P4-08).
##
## Nada aqui é tabela escrita à mão: tudo vem de `data/re3_combinacoes.json`, gerado por
## `tools/exe_combine.py` direto do `SLUS_009.23`. Endereços de origem (no JSON, em `_meta`):
##
##     descritor_item      0x800a0514   4 B × 0xac
##     receitas            0x800a07c4   8 B/registro, terminador `rec[1] == 0xff`
##     combine_find        0x8006a898   busca LINEAR e SIMÉTRICA (a+b == b+a)
##     arma_para_municao   0x800a0bc4   4 B/registro
##     transformacao_item  0x800a0bb4   4 B/registro (Card Case -> S.T.A.R.S. Card etc.)
##     tabela de cura      0x80010e4c   11 entradas, indexada por `item_id - 0x20`
##
## ── Descritor (`0x800a0514`, 4 bytes por item) ──
## `+0 cat` (1 arma · 2 munição · 3 cura · 4 key_item · 5 chave · 6 ferramenta · 7 arquivo ·
## 8 mapa · 0 nenhum) · `+1 max` (empilhamento) · `+2 bit_check` · `+3 flags_default`.
## O `cat` é quem decide **EQUIP ou USE** no submenu (`0x8006be2c`) e o despacho do USE
## (`0x800676fc`) — antes eu usava a faixa "id 1..20", que era a consequência, não a causa.
##
## ── Cura (`0x80010e4c`, provado handler por handler) ──
## `maxHP = gs+0x255a`; "cheio" é `(u8)maxHP` (é `lbu` no EXE, o byte baixo). A aplicação
## (`0x80067934`) soma o HP, faz clamp em maxHP, e limpa o bit `0x0200` (veneno) quando a
## entrada manda. A F. Aid Box (`0x2a`) é a única que gasta 1 de quantidade em vez de sumir.

const CAMINHO := "res://data/re3_combinacoes.json"

## Categorias do descritor (byte 0).
const CAT_NENHUM := 0
const CAT_ARMA := 1
const CAT_MUNICAO := 2
const CAT_CURA := 3
const CAT_KEY_ITEM := 4
const CAT_CHAVE := 5
const CAT_FERRAMENTA := 6
const CAT_ARQUIVO := 7
const CAT_MAPA := 8

## Tipos de receita (byte 0 do registro de 8 B).
const REC_RECARREGAR := 0
const REC_SIMPLES := 1
const REC_POLVORA_MUNICAO := 2
const REC_UPGRADE_ARMA := 3
const REC_TROCA_GRANADA := 4
const REC_POLVORA_GRANADA := 5
const REC_MUNICAO_INFINITA := 6

## Cura por item, da tabela `0x80010e4c` (`item_id` → [quanto de HP, cura veneno]).
## `"cheio"` = `(u8)maxHP` · `"1/4"` = `maxHP/4` · `"1/2"` = `maxHP/2` · `"0"` = nada.
## O `0x23` (Red Herb) não cura sozinha: o handler só mostra a mensagem 7.
const CURA := {
	0x20: ["cheio", false],                  ## F. Aid Spray
	0x21: ["1/4", false],                    ## Green Herb
	0x22: ["0", true],                       ## Blue Herb — só antiveneno
	0x23: ["nada", false],                   ## Red Herb — sozinha não faz efeito
	0x24: ["1/2", false],                    ## Mixed (V+V)
	0x25: ["1/4", true],                     ## Mixed (V+Azul)
	0x26: ["cheio", false],                  ## Mixed (V+Vermelha)
	0x27: ["cheio", false],                  ## Mixed (V+V+V)
	0x28: ["1/2", true],                     ## Mixed (V+V+Azul)
	0x29: ["cheio", true],                   ## Mixed (V+Verm+Azul)
	0x2A: ["cheio", false],                  ## F. Aid Box — gasta 1 e não some
}
const ITEM_FAID_BOX := 0x2A
const CURA_QUADROS := 39                     ## animação: `ctx[0x32]` de -0x20 a 0x51, +3/frame

static var _dados: Dictionary = {}
static var _descritor: Dictionary = {}       ## item_id -> {cat, max, bit_check, flags}
static var _carregado := false


static func _carregar() -> void:
	if _carregado:
		return
	_carregado = true
	if not FileAccess.file_exists(CAMINHO):
		push_error("Itens: %s ausente — rode `python tools/exe_combine.py --json`" % CAMINHO)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
	if not (raw is Dictionary):
		push_error("Itens: %s inválido" % CAMINHO)
		return
	_dados = raw
	for d: Dictionary in _dados.get("descritor_item", []):
		_descritor[int(d.get("id", 0))] = {
			"cat": int(d.get("cat", 0)), "max": int(d.get("max", 0)),
			"bit_check": int(d.get("bit_check", 0)), "flags": int(d.get("flags_default", 0))}


static func categoria(item_id: int) -> int:
	_carregar()
	var d: Dictionary = _descritor.get(item_id, {})
	return int(d.get("cat", CAT_NENHUM))


static func maximo(item_id: int) -> int:
	## Empilhamento máximo do item (byte 1 do descritor).
	_carregar()
	var d: Dictionary = _descritor.get(item_id, {})
	return int(d.get("max", 0))


static func equipavel(item_id: int) -> bool:
	## O submenu mostra EQUIP em vez de USE quando o item é ARMA (`cat == 1`, `0x8006be2c`).
	return categoria(item_id) == CAT_ARMA


static func usavel(item_id: int) -> bool:
	## USE só faz efeito em item de CURA nesta etapa (o dispatch `0x800676fc` também trata
	## arquivo/mapa, que dependem das telas de FILE/MAP).
	return categoria(item_id) == CAT_CURA


static func receita(a: int, b: int) -> Dictionary:
	## `combine_find` (`0x8006a898`): busca LINEAR e SIMÉTRICA. Devolve {} se não há receita.
	_carregar()
	for r: Dictionary in _dados.get("receitas", []):
		var ra := int(r.get("a", -1))
		var rb := int(r.get("b", -1))
		if (ra == a and rb == b) or (ra == b and rb == a):
			return r
	return {}


static func municao_da_arma(arma_id: int) -> int:
	## `arma_para_municao` (`0x800a0bc4`, busca em `0x8006a95c`). 0 = não achou.
	_carregar()
	for r: Dictionary in _dados.get("arma_para_municao", []):
		if int(r.get("arma", -1)) == arma_id:
			return int(r.get("municao", 0))
	return 0


static func cura_de(item_id: int, hp_max: int) -> Dictionary:
	## Quanto o item cura, com o `maxHP` do jogo. `{hp, veneno, gasta_um, valido}`.
	if not CURA.has(item_id):
		return {"valido": false, "hp": 0, "veneno": false, "gasta_um": false}
	var e: Array = CURA[item_id]
	var quanto := 0
	match String(e[0]):
		"cheio":
			quanto = hp_max & 0xFF          ## `lbu` no EXE: é o byte BAIXO de maxHP
		"1/2":
			quanto = hp_max >> 1
		"1/4":
			quanto = hp_max >> 2
		_:
			quanto = 0
	return {"valido": String(e[0]) != "nada", "hp": quanto, "veneno": bool(e[1]),
		"gasta_um": item_id == ITEM_FAID_BOX}


static func condicao(hp: int, flags: int) -> int:
	## `0x8006e598`: VIRUS `& 0x100` → 5 · POISON `& 0x200` → 4 · `hp >= 101` → 0 (FINE) ·
	## `>= 41` → 1 · `>= 21` → 2 · resto → 3 (DANGER).
	if flags & 0x100:
		return 5
	if flags & 0x200:
		return 4
	if hp >= 101:
		return 0
	if hp >= 41:
		return 1
	if hp >= 21:
		return 2
	return 3


static func n_receitas() -> int:
	_carregar()
	return (_dados.get("receitas", []) as Array).size()
