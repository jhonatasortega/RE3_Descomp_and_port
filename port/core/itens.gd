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
##
## ── COMBINAÇÃO: os 7 tipos, com o endereço do ramo que trata cada um ──
## O executor genérico é `0x80068024`, que salta pela tabela `0x80010e9c[kind]` (7 entradas).
## O campo que identifica o tipo é o **byte `+0` do registro de 8 B** (`kind`):
##
## | kind | ramo | n regs | o que faz |
## |---|---|---|---|
## | 0 `REC_RECARREGAR`      | `0x800684dc` | 31 | arma+munição / consolidar pilha |
## | 1 `REC_SIMPLES`         | `0x800685cc` | 28 | A+B → C com quantidade `n` |
## | 2 `REC_POLVORA_MUNICAO` | `0x8006860c` | 21 | Prensadora `0x82` + pólvora → munição |
## | 3 `REC_UPGRADE_ARMA`    | `0x800686ac` |  6 | arma ⇄ arma melhorada |
## | 4 `REC_TROCA_GRANADA`   | `0x80068854` | 12 | troca o tipo carregado no lança-granadas |
## | 5 `REC_POLVORA_GRANADA` | `0x800688d8` |  9 | pólvora + `0x18` → outro tipo de granada |
## | 6 `REC_MUNICAO_INFINITA`| `0x80068978` | 18 | arma + `0x6e` → munição infinita |
##
## Qual slot sobrevive (`0x800683ec`..`0x8006846c`): `swap = (slotA.id != rec.a) ? 1 :
## (slotA.id == rec.b)`; sobrevive o slot que contém **A** e o que contém **B** é zerado.
## Quando `rec.a == rec.b` (erva+erva) `swap = 1` e sobrevive o **2º selecionado**. Para os
## kinds 2 e 5 o pré-cálculo escolhe o `swap` na mão (o consumido é sempre a ferramenta / o
## `0x18`) — está em `_swap_da_receita`.
##
## ── NÍVEL DE MISTURA (o "Aumento do Nível de Mistura" das Instruções do Jogo B) ──
## **EXISTE no dado e está implementado.** É um contador `u16` por GRUPO de munição em
## `inv + 0x12c + grupo*2` (4 grupos → 8 bytes, logo depois de `+0x129` = arma equipada), e a
## tabela de bônus é `0x800a0bf4` (4 blocos × 5 registros de 4 B `{limiar, bônus em décimos}`;
## os 4 blocos são **idênticos**): `cnt<=2: +0%` · `<=5: +10%` · `<=10: +30%` · `<=20: +50%` ·
## `<=250: +70%`. Grupo por munição em `0x800a00ec`: `0x15`/`0x1e`→0 · `0x17`/`0x1f`→1 ·
## `0x16`→2 · `0x18`/`0x19`/`0x1a`/`0x1b`→3. Pré-cálculo em `0x80068080` (kind 2) e
## `0x80068264` (kind 5, que usa **sempre** o bloco/contador do grupo 3).
## O "7 vezes" do texto do jogo é o outro efeito do mesmo contador: em `0x80067d80` o jogo
## compara `cnt > 6` e, **só nos grupos 0 e 1** (os únicos com munição "E"), PERGUNTA se você
## quer a versão melhorada; se a resposta em `0x800d1f80` é 0 ele soma 8 ao ponteiro de receita
## (`0x80068b98`) e usa o **registro seguinte** do par — daí os 8 pares de chave repetida.
##
## ── A DOBRA NO MODO FÁCIL (era "NÃO PROVADO", agora está provado) ──
## `0x80068118`: `if flag_test(0x800cc858, bit 0x17) -> qty *= 2`. O banco 0 da tabela
## `0x8009e3f8` é `0x800cc858`, e o bitset (`0x80078930`) usa `word = banco + ((id>>5)*4)` e
## `bit = 0x80000000 >> (id & 0x1f)`. Para `id = 0x17 = 23`: word = `0x800cc858` e
## bit = `0x80000000 >> 23` = **`0x100`** — exatamente o bit que a tela de dificuldade grava em
## `0x80195dcc` (EASY) e limpa em `0x80195db8` (HARD). Logo **flag `0x17` do banco 0 = MODO
## FÁCIL**, e a munição criada com pólvora sai em dobro no fácil.

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
	var i := receita_indice(a, b)
	return _dados.get("receitas", [])[i] if i >= 0 else {}


static func receita_indice(a: int, b: int) -> int:
	## O ÍNDICE da receita, não só o registro: a "pergunta normal/melhorada" do kind 2 é
	## implementada no EXE somando **8 bytes** ao ponteiro de receita (`0x80068b98`), isto é,
	## usando o REGISTRO SEGUINTE. Sem o índice não há como alcançar o 2º registro do par.
	_carregar()
	var lista: Array = _dados.get("receitas", [])
	for i in lista.size():
		var r: Dictionary = lista[i]
		var ra := int(r.get("a", -1))
		var rb := int(r.get("b", -1))
		if (ra == a and rb == b) or (ra == b and rb == a):
			return i
	return -1


static func receita_por_indice(i: int) -> Dictionary:
	_carregar()
	var lista: Array = _dados.get("receitas", [])
	return lista[i] if i >= 0 and i < lista.size() else {}


## ── NÍVEL DE MISTURA / BÔNUS DE PERÍCIA ──
const N_GRUPOS_MUNICAO := 4                  ## `inv+0x12c`..`+0x133`: 4 contadores u16
const FLAG_FACIL_BANCO := 0                  ## banco 0 da tabela `0x8009e3f8` = `0x800cc858`
const FLAG_FACIL_ID := 0x17                  ## bit `0x80000000 >> 23` = `0x100` (ver cabeçalho)
const MUNICAO_E := [0x1E, 0x1F]              ## as duas munições "melhoradas"
const ITEM_PRENSADORA := 0x82
const ITEM_GRANADA_NORMAL := 0x18
const ITEM_MUNICAO_INFINITA := 0x6E
const ITEM_MINE_THROWER := 0x0C
const ITEM_MINE_THROWER_E := 0x14


static func grupo_da_municao(municao_id: int) -> int:
	## `0x800a00ec` (2 B/registro, terminador `0xFF`). -1 = a munição não tem grupo de perícia.
	_carregar()
	for r: Dictionary in _dados.get("municao_para_grupo", []):
		if int(r.get("municao", -1)) == municao_id:
			return int(r.get("grupo", -1))
	return -1


static func bonus_decimos(grupo: int, cnt: int) -> int:
	## `bloco = 0x800a0bf4 + grupo*20`; `i = 0; while i < 4 and bloco[i].limiar < cnt: i++`.
	## O bônus sai em DÉCIMOS (0, 1, 3, 5, 7 = +0%, +10%, +30%, +50%, +70%).
	_carregar()
	var blocos: Array = _dados.get("bonus_polvora", [])
	if grupo < 0 or grupo >= blocos.size():
		return 0
	var bloco: Array = blocos[grupo]
	var i := 0
	while i < bloco.size() - 1 and int((bloco[i] as Dictionary).get("limiar", 0)) < cnt:
		i += 1
	return int((bloco[i] as Dictionary).get("bonus_decimos", 0))


static func _bonus_municao_e(bonus: int) -> int:
	## Remap `0x80010e7c[bonus]` quando o resultado é munição "E": os alvos são labels
	## (`0x80068140`→1, `0x80068148`→3, `0x80068150`→5, `0x80068154`→sem alteração), e o mapa
	## por índice é `0→1, 1→1, 2→(nada), 3→1, 4→(nada), 5→3, 6→(nada), 7→5`. Como o bônus cru só
	## vale 0/1/3/5/7, na prática a munição E ganha um bônus MENOR.
	match bonus:
		0, 1, 3:
			return 1
		5:
			return 3
		7:
			return 5
	return bonus


static func quantidade_polvora(base: int, resultado_id: int, cnt: int, facil: bool) -> int:
	## `0x80068080`: `qty = n + (n*bonus)/10`, arredondando para cima quando `(n*bonus)%10 >= 5`;
	## depois `qty *= 2` se o MODO FÁCIL estiver ligado (flag `0x17` do banco 0 — ver cabeçalho).
	var grupo := grupo_da_municao(resultado_id)
	var bonus := bonus_decimos(grupo, cnt)
	if MUNICAO_E.has(resultado_id):
		bonus = _bonus_municao_e(bonus)
	var bruto := base * bonus
	var qty := base + int(bruto / 10.0)
	if bruto % 10 >= 5:
		qty += 1
	if facil:
		qty *= 2
	return qty


static func municao_devolvida(arma_id: int) -> int:
	## `0x80010f24[id - 2]` (cauda `ctx[0x64] == 7`): que munição volta ao inventário quando se
	## faz downgrade de uma arma com MUNIÇÃO INFINITA que ainda tem balas dentro.
	## `0x02`/`0x03`→`0x15` · `0x04`→`0x17` · `0x11`/`0x12`→`0x1e` · `0x13`→`0x1f`.
	match arma_id:
		0x02, 0x03:
			return 0x15
		0x04:
			return 0x17
		0x11, 0x12:
			return 0x1E
		0x13:
			return 0x1F
	return 0


static func _vazio() -> Dictionary:
	return {"id": 0, "qtd": 0, "flags": 0}


static func _flags_de(item_id: int) -> int:
	_carregar()
	var d: Dictionary = _descritor.get(item_id, {})
	return int(d.get("flags", 0))


static func _infinita(slot: Dictionary) -> bool:
	## `(slot.flags & 3) == 3` = munição infinita (`0x800684dc`, `0x8006858c`, `0x800690a8`).
	return (int(slot.get("flags", 0)) & 3) == 3


static func _swap_da_receita(r: Dictionary, id_a: int) -> bool:
	## `0x800683ec`: `swap = (slotA.id != rec.a) ? 1 : (slotA.id == rec.b)`. `true` = sobrevive o
	## slot B (o 2º selecionado).
	var ra := int(r.get("a", -1))
	var rb := int(r.get("b", -1))
	if id_a != ra:
		return true
	return id_a == rb


static func combinar(slots: Array, ia: int, ib: int, ctx := {}) -> Dictionary:
	## RESOLVEDOR ÚNICO da combinação, com **todos os 7 kinds** ligados. Não muda nada: devolve
	## o que mudaria, para o chamador aplicar (é o que deixa isto testável sem tela).
	##
	## `ctx` (tudo opcional): `facil` (bool, espelha `GameState.difficulty == 1`) ·
	## `niveis` (Array de 4 u16, o contador de `inv+0x12c`) · `melhorada` (bool, a resposta da
	## pergunta do kind 2 — `resposta == 0` no EXE) · `bonus_arma_infinita` (bool, a flag
	## `flag_test(0x800d1f30, 9)` que dá munição infinita à EAGLE/M37 recém-montada) ·
	## `mine_thrower_liberado` (bool, o retorno de `0x8004575c`, que não foi decompilado).
	##
	## Devolve `{ok, kind, motivo, mensagem, mudancas, niveis, sobrevive, consumido, qtd,
	## pergunta, estourou_pilha}`. `mudancas` = `{índice de slot: novo conteúdo}`.
	## `mensagem` é o id do jogo (2/3 arma cheia · 8 arma precisa estar vazia · 9 e 0xa do Mine
	## Thrower), ou -1.
	_carregar()
	var facil := bool(ctx.get("facil", false))
	var niveis: Array = []
	for i in N_GRUPOS_MUNICAO:
		var v: Array = ctx.get("niveis", [])
		niveis.append(int(v[i]) if i < v.size() else 0)
	var falha := func(motivo: String, msg := -1) -> Dictionary:
		return {"ok": false, "kind": -1, "motivo": motivo, "mensagem": msg,
			"mudancas": {}, "niveis": niveis, "sobrevive": -1, "consumido": -1,
			"qtd": 0, "pergunta": false, "estourou_pilha": false}
	if ia == ib or ia < 0 or ib < 0 or ia >= slots.size() or ib >= slots.size():
		return falha.call("slot inválido")
	var sa: Dictionary = slots[ia]
	var sb: Dictionary = slots[ib]
	var id_a := int(sa.get("id", 0))
	var id_b := int(sb.get("id", 0))
	if id_a == 0 or id_b == 0:
		return falha.call("slot vazio")
	var idx := receita_indice(id_a, id_b)
	if idx < 0:
		## COMBINAÇÃO INVÁLIDA: nada é consumido (`mudancas` vazio). Era o furo do relato do
		## dono — Prensadora + pólvora caía aqui porque o kind 2 não estava ligado.
		return falha.call("não combina")
	var r := receita_por_indice(idx)
	var kind := int(r.get("kind", -1))
	var swap := _swap_da_receita(r, id_a)
	var i_vive := ib if swap else ia
	var i_morre := ia if swap else ib
	var res := {"ok": true, "kind": kind, "motivo": r.get("kind_nome", ""), "mensagem": -1,
		"mudancas": {}, "niveis": niveis, "sobrevive": i_vive, "consumido": i_morre,
		"qtd": 0, "pergunta": false, "estourou_pilha": false}
	var c := int(r.get("c", 0))
	var n := int(r.get("n", 0))

	match kind:
		REC_RECARREGAR:
			## `0x800684dc`. Caso especial do Mine Thrower (`0x80067dcc`) vem ANTES do executor.
			if int(r.get("a", -1)) == ITEM_MINE_THROWER:
				var mt: Dictionary = slots[ia] if id_a == ITEM_MINE_THROWER else slots[ib]
				if int(mt.get("qtd", 0)) != 0:
					return falha.call("o lança-minas não precisa de mais nada", 0x0A)
				if not bool(ctx.get("mine_thrower_liberado", true)):
					return falha.call("não pode trocar o lança-minas agora", 9)
			var arma: Dictionary = (slots[i_vive] as Dictionary).duplicate()
			var mun: Dictionary = (slots[i_morre] as Dictionary).duplicate()
			if _infinita(arma):
				arma["qtd"] = 0
			var cap := maximo(int(arma.get("id", 0)))
			if int(arma.get("qtd", 0)) >= cap:
				var msg := 2 if categoria(int(arma.get("id", 0))) == CAT_ARMA else 3
				return falha.call("já está cheio", msg)
			var espaco := cap - int(arma.get("qtd", 0))
			var passa := int(mun.get("qtd", 0))
			if espaco >= passa:
				res["mudancas"][i_morre] = _vazio()
			else:
				passa = espaco
				if not _infinita(mun):
					mun["qtd"] = int(mun.get("qtd", 0)) - passa
				res["mudancas"][i_morre] = mun
			arma["qtd"] = int(arma.get("qtd", 0)) + passa
			res["mudancas"][i_vive] = arma
			res["qtd"] = passa
		REC_SIMPLES:
			## `0x80068d14`: id/qtd/flags saem do REGISTRO e do descritor — nada arredondado aqui.
			var flags := _flags_de(c)
			if bool(ctx.get("bonus_arma_infinita", false)) and (c == 0x0D or c == 0x10):
				flags |= 3                    ## `flag_test(0x800d1f30, 9)` + EAGLE/M37
			res["mudancas"][i_vive] = {"id": c, "qtd": maxi(1, n), "flags": flags}
			res["mudancas"][i_morre] = _vazio()
			res["qtd"] = maxi(1, n)
		REC_POLVORA_MUNICAO:
			## `0x8006860c` + pré-cálculo `0x80068080`. O consumido é SEMPRE a Prensadora.
			var i_tool := ia if id_a == ITEM_PRENSADORA else ib
			var i_polv := ib if i_tool == ia else ia
			var grupo := grupo_da_municao(c)
			var cnt := int(niveis[grupo]) if grupo >= 0 and grupo < niveis.size() else 0
			## A PERGUNTA (`0x80067d80`): só grupos 0/1 e só depois de 6 lotes. `melhorada` = a
			## resposta 0, que soma 8 ao ponteiro de receita = o registro SEGUINTE do par.
			var pode_perguntar := (grupo == 0 or grupo == 1) and cnt > 6
			res["pergunta"] = pode_perguntar
			if pode_perguntar and bool(ctx.get("melhorada", false)):
				var alt := receita_por_indice(idx + 1)
				if int(alt.get("a", -1)) == int(r.get("a", -1)) \
						and int(alt.get("b", -1)) == int(r.get("b", -1)):
					r = alt
					c = int(r.get("c", 0))
					n = int(r.get("n", 0))
					grupo = grupo_da_municao(c)
					cnt = int(niveis[grupo]) if grupo >= 0 and grupo < niveis.size() else 0
			var qty := quantidade_polvora(n, c, cnt, facil)
			var tool: Dictionary = (slots[i_tool] as Dictionary).duplicate()
			if int(tool.get("qtd", 0)) <= 1:
				res["mudancas"][i_tool] = _vazio()          ## `ctx[0x64] = 3`
			else:
				tool["qtd"] = int(tool.get("qtd", 0)) - 1    ## `ctx[0x64] = 4`
				res["mudancas"][i_tool] = tool
			res["mudancas"][i_polv] = {"id": c, "qtd": qty, "flags": _flags_de(c)}
			res["sobrevive"] = i_polv
			res["consumido"] = i_tool
			res["qtd"] = qty
			if grupo >= 0 and grupo < niveis.size():
				niveis[grupo] = cnt + 1
			## O EXE **NÃO** faz clamp em `maximo` aqui (`s2->qty = ctx[0x65]`, `0x80068f30`).
			## Na prática não estoura: o maior `n` é 60, o maior bônus é +70% e o fácil dobra →
			## 204, contra `max = 250` da munição. Sinalizado, não corrigido à revelia.
			res["estourou_pilha"] = qty > maximo(c)
		REC_UPGRADE_ARMA:
			## `0x800686ac`: exige a arma VAZIA, exceto quando ela tem munição infinita.
			var arma2: Dictionary = (slots[i_vive] as Dictionary).duplicate()
			var mun2: Dictionary = (slots[i_morre] as Dictionary).duplicate()
			var dentro := int(arma2.get("qtd", 0))
			if not _infinita(arma2):
				if dentro != 0:
					return falha.call("a arma precisa estar vazia", 8)
				## arma vazia: transferência igual à do kind 0 e depois vira `rec.c`
				var cap2 := maximo(c)
				var passa2 := mini(cap2, int(mun2.get("qtd", 0)))
				if int(mun2.get("qtd", 0)) > passa2:
					mun2["qtd"] = int(mun2.get("qtd", 0)) - passa2
					res["mudancas"][i_morre] = mun2
				else:
					res["mudancas"][i_morre] = _vazio()
				res["mudancas"][i_vive] = {"id": c, "qtd": passa2,
					"flags": (int(arma2.get("flags", 0)) & 0xFF00) | _flags_de(c)}
				res["qtd"] = passa2
			else:
				## `ctx[0x64] = 7`, cauda `0x800691a0`: o slot CONSUMIDO recebe a munição antiga
				## (`0x80010f24`) com a quantidade que estava DENTRO da arma.
				var volta := municao_devolvida(int(arma2.get("id", 0)))
				if volta != 0 and dentro != 0:
					res["mudancas"][i_morre] = {"id": volta, "qtd": dentro,
						"flags": _flags_de(volta)}
				else:
					res["mudancas"][i_morre] = _vazio()
				res["mudancas"][i_vive] = {"id": c, "qtd": int(mun2.get("qtd", 0)),
					"flags": (int(arma2.get("flags", 0)) & 0xFF00) | _flags_de(c)}
				res["qtd"] = dentro
		REC_TROCA_GRANADA:
			## `0x80068854`. `n` = o item_id da munição ANTIGA, que volta ao inventário com a
			## quantidade que estava carregada (cauda `0x800691a0`, `ctx[0x64] = 5`).
			var lanc: Dictionary = (slots[i_vive] as Dictionary).duplicate()
			var nova: Dictionary = (slots[i_morre] as Dictionary).duplicate()
			var carregado := int(lanc.get("qtd", 0))
			if carregado == 0:
				## "carrega direto" (`ctx[0x64] = 1`): só troca a variante e leva a munição nova
				var capg := maximo(c)
				var passag := mini(capg, int(nova.get("qtd", 0)))
				if int(nova.get("qtd", 0)) > passag:
					nova["qtd"] = int(nova.get("qtd", 0)) - passag
					res["mudancas"][i_morre] = nova
				else:
					res["mudancas"][i_morre] = _vazio()
				res["mudancas"][i_vive] = {"id": c, "qtd": passag,
					"flags": (int(lanc.get("flags", 0)) & 0xFF00) | _flags_de(c)}
				res["qtd"] = passag
			else:
				res["mudancas"][i_morre] = {"id": n, "qtd": carregado, "flags": _flags_de(n)}
				res["mudancas"][i_vive] = {"id": c, "qtd": int(nova.get("qtd", 0)),
					"flags": (int(lanc.get("flags", 0)) & 0xFF00) | _flags_de(c)}
				res["qtd"] = int(nova.get("qtd", 0))
		REC_POLVORA_GRANADA:
			## `0x800688d8` + pré-cálculo `0x80068264`: usa SEMPRE o bloco/contador do grupo 3 e
			## consome **6** unidades de `0x18`; com menos de 7 o slot esvazia e a quantidade sai
			## proporcional (`qty * rounds / 6`).
			var i_gr := ia if id_a == ITEM_GRANADA_NORMAL else ib
			var i_pol := ib if i_gr == ia else ia
			var cnt3 := int(niveis[3])
			var qty5 := quantidade_polvora(n, c, cnt3, facil)
			var rounds := int((slots[i_gr] as Dictionary).get("qtd", 0))
			var gr: Dictionary = (slots[i_gr] as Dictionary).duplicate()
			if rounds >= 7:
				gr["qtd"] = rounds - 6
				res["mudancas"][i_gr] = gr
			else:
				res["mudancas"][i_gr] = _vazio()
				qty5 = int(qty5 * rounds / 6.0)          ## `0x2aaaaaab` = 1/6
			res["mudancas"][i_pol] = {"id": c, "qtd": qty5, "flags": _flags_de(c)}
			res["sobrevive"] = i_pol
			res["consumido"] = i_gr
			res["qtd"] = qty5
			niveis[3] = cnt3 + 1
			res["estourou_pilha"] = qty5 > maximo(c)
		REC_MUNICAO_INFINITA:
			## `0x80069040`: `s2->flags |= 3`, e o Mine Thrower `0x0c` vira `0x14` com `flags = 7`.
			var i_arma := ia if id_b == ITEM_MUNICAO_INFINITA else ib
			var i_inf := ib if i_arma == ia else ia
			var arma3: Dictionary = (slots[i_arma] as Dictionary).duplicate()
			if int(arma3.get("id", 0)) == ITEM_MINE_THROWER:
				arma3["id"] = ITEM_MINE_THROWER_E
				arma3["flags"] = 7
			else:
				arma3["flags"] = int(arma3.get("flags", 0)) | 3
			res["mudancas"][i_arma] = arma3
			res["mudancas"][i_inf] = _vazio()
			res["sobrevive"] = i_arma
			res["consumido"] = i_inf
			res["qtd"] = int(arma3.get("qtd", 0))
		_:
			return falha.call("kind %d desconhecido" % kind)
	res["niveis"] = niveis
	return res


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


## ── DOCUMENTO A PARTIR DO ITEM ──
## O nome do documento na tela de arquivo sai de **`item = doc + 0x85`** (provado em `0x8006bcb8`:
## `addiu a3, s0, 0x85` alimentando o desenhador de string com o índice do documento em `s0`), e o
## descritor confirma a faixa: `0x85..0xa3` são os 31 documentos, todos categoria **7**.
##
## Os DOIS itens que o jogo novo dá são outros: **`0x83` "Game Inst. A"** e **`0x84` "Game Inst. B"**,
## ambos categoria **6** — é por isso que USAR neles não fazia nada (meu teste era `categoria == 7`).
## O de-para deles para o documento NÃO está no descritor (os bytes 2 e 3 são 0 nos dois) e não há
## comparação com `0x83`/`0x84` na faixa dos menus, então uso o pareamento óbvio pelo ícone e pelo
## nome — livro AZUL = Instruções A = doc 0 (item 0x85) e livro VERMELHO = Instruções B = doc 28
## (item 0xa1), os dois "COMO JOGAR" do atlas `FILEI`. **Declarado: inferido, não medido.**
const ITEM_DOC_BASE := 0x85
const DOC_DE_ITEM_ESPECIAL := {0x83: 0, 0x84: 28}


static func doc_do_item(id: int) -> int:
	## Índice do documento (0..30) desse item, ou -1 se o item não é documento.
	if DOC_DE_ITEM_ESPECIAL.has(id):
		return int(DOC_DE_ITEM_ESPECIAL[id])
	if categoria(id) == CAT_ARQUIVO:
		return id - ITEM_DOC_BASE
	return -1


static func item_do_doc(doc: int) -> int:
	return ITEM_DOC_BASE + doc


static func eh_documento(id: int) -> bool:
	return doc_do_item(id) >= 0


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


## ══════════════════════════════════════════════════════════════════════════════════════════
## ITEM NO CHÃO NO MODO FÁCIL — a regra da FITA DE TINTA, provada no EXE
## ══════════════════════════════════════════════════════════════════════════════════════════
## O dono disse "a fita de tinta só existe no modo difícil". **É verdade e está no binário.**
## Os dois handlers que colocam item no mundo — `0x800574f4` (opcode SCD `0x67`, 2 pontos) e
## `0x800576c4` (opcode `0x68`, 4 pontos) — têm o MESMO bloco, e é o único lugar do EXE em que
## `0x800cc858` é lido com `andi 0x100` (varredura das 10 referências ao offset):
##
##     800575ac  lw    v0, 0x800cc858
##     800575b4  andi  v0, v0, 0x100        ; MODO FÁCIL?
##     800575b8  beqz  v0, 0x800575fc       ; não é fácil -> pula o bloco todo
##     800575bc  addiu v0, zero, 0x81       ; (delay slot) 0x81 = FITA DE TINTA
##     800575c0  lbu   s3, 0xe(s0)          ; item_id do opcode (`0x67` +0x0e · `0x68` +0x16)
##     800575c8  bne   s3, v0, 0x800575e0
##     800575d4  jal   0x800788dc           ; flag_set(banco, flag do item) = "JÁ FOI PEGO"
##     800575e0  sltiu v0, v0, 0xb          ; item_id - 0x15 < 0xb  -> faixa de MUNIÇÃO
##     800575f4  sll   v0, v0, 1            ; DOBRA a quantidade
##
## `0x800788dc` é `flag_set(a0 = banco, a1 = id)` (`banco[(id>>5)*4] |= 0x80000000>>(id&0x1f)`);
## `0x80078904` é o clear e `0x80078930` é o get. Logo depois o handler chama o **get** da mesma
## flag e, como ela acabou de ser ligada, cai no ramo `0x80057610` que faz `sb zero, ($v0)` —
## **zera o byte do AOT**, isto é, o item não é instalado. Em uma frase: no MODO FÁCIL o jogo
## marca a fita de tinta como "já pega" antes de instalar o AOT, e ela não aparece.
## As 17 colocações de fita de tinta do jogo (todas `0x67`, `amount = 3`) estão nas salas
## R100, R105, R116, R117, R11B, R120, R210, R219, R21B, R307, R30C, R313, R401, R403, R414,
## R501 e R505 — os quartos de máquina de escrever. **Nenhuma** delas tem teste de dificuldade
## no bytecode (conferido no `.scd`): a regra é do handler, não do script.
##
## BRINDE do mesmo bloco: no MODO FÁCIL a munição colocada no chão vem em **dobro** — a faixa
## `0x15..0x1f` (11 ids, `sltiu 0xb`) tem a quantidade deslocada 1 bit à esquerda. É a mesma
## regra do bônus de pólvora (flag `0x17` do banco 0 = o mesmo bit `0x100`).
##
## ⚠ QUEM LIGA ISTO NA CENA. Os handlers `0x67`/`0x68` vivem em `port/script_vm/vm.gd` e
## `port/script_vm/aot.gd`, que **não são deste território**. A regra fica aqui como função pura
## e testada; a chamada dela na instalação do AOT é do agente de cenas.
const ITEM_FITA_TINTA := 0x81
const MUNICAO_PRIMEIRA := 0x15               ## início da faixa dobrada no fácil
const MUNICAO_N := 0x0B                      ## `sltiu v0, v0, 0xb` -> 0x15..0x1f


static func item_no_chao(item_id: int, qtd: int, facil: bool) -> Dictionary:
	## O que os handlers `0x800574f4`/`0x800576c4` fazem com um item colocado por script.
	## Devolve `{colocar, qtd, motivo}`. `colocar == false` = o AOT não é instalado.
	if not facil:
		return {"colocar": true, "qtd": qtd, "motivo": ""}
	if item_id == ITEM_FITA_TINTA:
		return {"colocar": false, "qtd": qtd,
			"motivo": "fita de tinta não existe no modo fácil (0x800575b4)"}
	if item_id >= MUNICAO_PRIMEIRA and item_id < MUNICAO_PRIMEIRA + MUNICAO_N:
		return {"colocar": true, "qtd": qtd << 1,
			"motivo": "munição em dobro no modo fácil (0x800575f4)"}
	return {"colocar": true, "qtd": qtd, "motivo": ""}
