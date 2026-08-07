class_name GameState
extends RefCounted
## Estado global do jogo: bancos de flags, variáveis de script, inventário e progresso (P0-07).
##
## É a base do save (P3-05) e de TODA progressão: se o modelo de flags estiver errado, o
## script de sala abre a porta errada, o puzzle não fecha e o bug aparece 30 salas depois.
## Por isso aqui se reproduz a FÓRMULA do EXE, não uma abstração conveniente.
##
## ── Bancos de flags (provado em 3 rotinas do EXE; docs/decomp/notes/exe_items.md §1) ──
## `0x8009e3f8` é uma tabela de **16 ponteiros de banco**. Um flag é o par `(bank, bit)`:
##
##     word = bank_ptr[bank] + ((bit >> 3) & 0x1c)     ; word de 32 bits
##     mask = 0x80000000 >> (bit & 0x1f)               ; bits gravados MSB-first
##     set: *word |= mask · clear: *word &= ~mask · check: *word & mask
##
## Duas consequências do `& 0x1c` que NÃO são detalhe: o offset de word satura em `0x1c`
## (7 words) → cada banco tem **8 words = 256 bits**, e índices de bit acima disso
## **dão a volta** (bit 256 == bit 0). Isso é comportamento do jogo, não limitação nossa.
## Banco 1 (`0x800d1f2c`) = flags de PROGRESSO (o `player_sm` lê `&0x10` daqui).
##
## Opcodes do SCD: `0x4c` = CHECK (gateia o script), `0x4d` = SET/CLEAR.
##
## ── Inventário (docs/decomp/notes/exe_items.md) ──
## Array `0x800d2134`: **MAIN 10 slots / BOX 64 slots**, slot de 4 bytes `{id, qtd, flags16}`.
## `count` em `+0x12a`, `cursor` em `+0x128`, arma equipada em `+0x129`.
## `find_by_id(0)` devolve o primeiro slot LIVRE (usado pelo "pegar item").

const N_BANKS := 16
const BITS_PER_BANK := 256                 ## consequência do `& 0x1c` (8 words de 32 bits)
const WORDS_PER_BANK := BITS_PER_BANK / 32
const BANK_PROGRESS := 1                    ## `0x800d1f2c` — flags de progresso de jogo

## Banco de flags de "item já pego". NÃO é escolha do port: o ponteiro que os handlers
## `0x800574f4`/`0x800576c4` usam é `0x800d2008`, que é exatamente a **entrada 7** da tabela
## de bancos `0x8009e3f8` — a mesma que o `CHECK 0x4c` do script consulta. Ou seja: pegar um
## item acende um bit que o script da sala pode ler, e isso é progressão real (portas que só
## abrem depois de pegar a chave). Usar um banco inventado (era 5) quebraria esse elo.
## O BIT vem do dado (u16 `payload+4` do `0x67`/`0x68`).
const BANCO_ITENS := 7
## Segundo banco de item (`0x800d2028` = entrada 8): o handler escolhe este quando
## `*(0x800d1f76) >= 2` e o bit 0x80 das flags globais está apagado — é o Cenário B. O port
## fica no A até ter seleção de cenário (P6-07); registrado para não parecer esquecimento.
const BANCO_ITENS_B := 8

const MAIN_SLOTS := 10
const BOX_SLOTS := 64
const N_VARS := 256                         ## variáveis de script (o switch usa var u8)

## Flags: 16 bancos × 8 words. Guardado como Array[int] (int de 64 bits do GDScript) para
## que a máscara `0x80000000` não estoure o sinal de um int32.
var _flags: Array[int] = []
var _vars: Array[int] = []

var main_slots: Array[Dictionary] = []      ## inventário de mão (10)
var box_slots: Array[Dictionary] = []       ## caixa de itens (64)
var cursor := 0                             ## `+0x128`
var equipped := 0                           ## `+0x129` — índice do slot da arma equipada

var stage := 1                              ## `0x800d1f76`
var room := 0                               ## `0x800d1f78`
var difficulty := 0                         ## 0 = normal/hard, 1 = easy (P6-07)
var play_ticks := 0                         ## tempo de jogo em ticks de 30 Hz (nunca em s)
var save_count := 0


func _init() -> void:
	reset()


func novo_jogo() -> void:
	## Carga inicial de JOGO NOVO, **provada byte a byte**: a rotina `0x8006d0d8` copia o template
	## estático de `0x800a018c` para o array de inventário `0x800d2134`, e a arma equipada é o
	## PRIMEIRO item (`0x800d225d`). Bytes do template (HARD, o principal da Jill):
	##
	##     03 0f 0100   82 fa 0000   83 01 0000   84 01 0000   ff ff ff ff
	##     Hand Gun 15  Reload. 250  Game Inst.A  Game Inst.B  terminador
	##
	## Ou seja o jogo começa com os DOIS ARQUIVOS DE INSTRUÇÃO no inventário — é por isso que a
	## tela de ARQUIVO não nasce vazia. Entrada = 4 B `{id, qtd, flags16 LE}`.
	## (EASY é o template `s5=1`; Mercenaries são `s5=2` por personagem. Ver
	## `re3_items.json.newgame_loadout_templates`, extraído do EXE.)
	reset()
	var carga := [[0x03, 15, 0x0001], [0x82, 250, 0x0000], [0x83, 1, 0x0000], [0x84, 1, 0x0000]]
	for i in carga.size():
		main_slots[i] = {"id": int(carga[i][0]), "qtd": int(carga[i][1]),
			"flags": int(carga[i][2])}
	equipped = 0                       ## a arma equipada é o primeiro item do template
	stage = 1
	room = 0                           ## `INIT_TBL.DAT` traz stage 0 / room 0 = R100


func equipped_item_id() -> int:
	## `item_id` da arma equipada. No EXE há DOIS campos: `inv+0x128` guarda o SLOT equipado
	## (0xff = nenhum) e `inv+0x129` guarda o `item_id` dele — o segundo é cache do primeiro
	## (`docs/decomp/notes/menu_inventario.md` §6). O port guarda só o slot (`equipped`) e deriva
	## o id, que é equivalente e evita dois campos podendo divergir.
	if equipped < 0 or equipped >= main_slots.size():
		return 0
	return int(main_slots[equipped].get("id", 0))


func equipped_qtd() -> int:
	## Munição/quantidade da arma equipada — é o número que a tela de status mostra no painel
	## EQUIP, em (174,55) (`0x800a0080[10]`, desenhado só se `inv+0x128 != 0xff`).
	if equipped < 0 or equipped >= main_slots.size():
		return 0
	return int(main_slots[equipped].get("qtd", 0))


func reset() -> void:
	_flags = []
	_flags.resize(N_BANKS * WORDS_PER_BANK)
	_flags.fill(0)
	_vars = []
	_vars.resize(N_VARS)
	_vars.fill(0)
	main_slots = []
	for _i in MAIN_SLOTS:
		main_slots.append(_empty_slot())
	box_slots = []
	for _i in BOX_SLOTS:
		box_slots.append(_empty_slot())
	cursor = 0
	equipped = 0
	stage = 1
	room = 0
	play_ticks = 0
	save_count = 0


static func _empty_slot() -> Dictionary:
	return {"id": 0, "qtd": 0, "flags": 0}


static func _slot_from(v: Variant) -> Dictionary:
	## Normaliza um slot vindo de JSON (valores como float) para inteiros.
	if not (v is Dictionary):
		return _empty_slot()
	var d: Dictionary = v
	return {"id": int(d.get("id", 0)), "qtd": int(d.get("qtd", 0)),
		"flags": int(d.get("flags", 0))}


# ───────────────────────────────────── flags ─────────────────────────────────────

static func word_index(bank: int, bit: int) -> int:
	## Índice do word de 32 bits, pela fórmula do EXE: `((bit >> 3) & 0x1c) / 4`.
	return bank * WORDS_PER_BANK + (((bit >> 3) & 0x1C) >> 2)


static func bit_mask(bit: int) -> int:
	## `0x80000000 >> (bit & 0x1f)` — MSB-first dentro do word (não LSB-first).
	return 0x80000000 >> (bit & 0x1F)


func flag_get(bank: int, bit: int) -> bool:
	if bank < 0 or bank >= N_BANKS:
		push_error("GameState: banco de flag inválido: %d (0..%d)" % [bank, N_BANKS - 1])
		return false
	return (_flags[word_index(bank, bit)] & bit_mask(bit)) != 0


func flag_set(bank: int, bit: int, valor: bool = true) -> void:
	if bank < 0 or bank >= N_BANKS:
		push_error("GameState: banco de flag inválido: %d" % bank)
		return
	var i := word_index(bank, bit)
	if valor:
		_flags[i] = _flags[i] | bit_mask(bit)
	else:
		_flags[i] = _flags[i] & ~bit_mask(bit)


func flag_clear(bank: int, bit: int) -> void:
	flag_set(bank, bit, false)


func flag_toggle(bank: int, bit: int) -> bool:
	var novo := not flag_get(bank, bit)
	flag_set(bank, bit, novo)
	return novo


func progress_get(bit: int) -> bool:
	return flag_get(BANK_PROGRESS, bit)


func progress_set(bit: int, valor: bool = true) -> void:
	flag_set(BANK_PROGRESS, bit, valor)


func flags_set_count() -> int:
	## Quantos flags estão ligados (diagnóstico/regressão de save).
	var n := 0
	for w in _flags:
		var v: int = w & 0xFFFFFFFF
		while v != 0:
			n += 1
			v &= v - 1
	return n


# ─────────────────────────────── variáveis de script ───────────────────────────────

func var_get(idx: int) -> int:
	return _vars[idx & (N_VARS - 1)]


func var_set(idx: int, valor: int) -> void:
	_vars[idx & (N_VARS - 1)] = valor & 0xFFFF     ## variáveis do SCD são de 16 bits


# ───────────────────────────────────── inventário ─────────────────────────────────

func _slots(box: bool) -> Array[Dictionary]:
	return box_slots if box else main_slots


func find_by_id(item_id: int, box: bool = false) -> int:
	## Réplica de `find_by_id 0x8006cc8c`: varre os slots comparando o byte 0 (id).
	## `find_by_id(0)` devolve o primeiro slot LIVRE (é assim que o "pegar item" acha vaga).
	var s := _slots(box)
	for i in s.size():
		if int(s[i]["id"]) == item_id:
			return i
	return -1


func add_item(item_id: int, qtd: int = 1, flags: int = 0, box: bool = false) -> int:
	## Coloca o item no 1º slot livre. Devolve o índice, ou -1 se estiver cheio.
	var i := find_by_id(0, box)
	if i < 0:
		return -1
	_slots(box)[i] = {"id": item_id, "qtd": qtd, "flags": flags}
	return i


func remove_slot(idx: int, box: bool = false) -> void:
	_slots(box)[idx] = _empty_slot()


func consume(item_id: int, qtd: int = 1, box: bool = false) -> bool:
	## `USAR/consumir 0x8006d0a8`: decrementa a quantidade e libera o slot ao zerar.
	var i := find_by_id(item_id, box)
	if i < 0:
		return false
	var s := _slots(box)
	var slot: Dictionary = s[i]
	if int(slot["qtd"]) < qtd:
		return false
	slot["qtd"] = int(slot["qtd"]) - qtd
	if int(slot["qtd"]) <= 0:
		s[i] = _empty_slot()
	else:
		s[i] = slot
	return true


func compact(box: bool = false) -> void:
	## `compact 0x8006cd68`: empurra os slots ocupados para o começo, preservando a ordem.
	var s := _slots(box)
	var cheios: Array[Dictionary] = []
	for slot in s:
		if int(slot["id"]) != 0:
			cheios.append(slot)
	for i in s.size():
		s[i] = cheios[i] if i < cheios.size() else _empty_slot()


func item_count(box: bool = false) -> int:
	var n := 0
	for slot in _slots(box):
		if int(slot["id"]) != 0:
			n += 1
	return n


func load_loadout(entradas: Array) -> void:
	## Aplica um template de novo jogo (`re3_items.json` → `newgame_loadout_templates`):
	## entradas `{id, qtd, flags}` copiadas para os slots de mão, na ordem (rotina 0x8006d0d8).
	for i in MAIN_SLOTS:
		main_slots[i] = _empty_slot()
	var i2 := 0
	for e: Dictionary in entradas:
		if i2 >= MAIN_SLOTS:
			break
		main_slots[i2] = {"id": int(e.get("id", 0)), "qtd": int(e.get("qtd", e.get("amount", 1))),
			"flags": int(e.get("flags", 0))}
		i2 += 1


# ─────────────────────────────────── serialização ───────────────────────────────────

func to_dict() -> Dictionary:
	return {
		"versao": 1,
		"flags": _flags.duplicate(),
		"vars": _vars.duplicate(),
		"main": main_slots.duplicate(true),
		"box": box_slots.duplicate(true),
		"cursor": cursor, "equipped": equipped,
		"stage": stage, "room": room,
		"difficulty": difficulty, "play_ticks": play_ticks, "save_count": save_count,
	}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("versao", 0)) != 1:
		push_error("GameState: versão de save incompatível: %s" % d.get("versao"))
		return false
	reset()
	var fl: Array = d.get("flags", [])
	for i in mini(fl.size(), _flags.size()):
		_flags[i] = int(fl[i])
	var vr: Array = d.get("vars", [])
	for i in mini(vr.size(), _vars.size()):
		_vars[i] = int(vr[i])
	# Slots precisam ser NORMALIZADOS: JSON não tem inteiro, então o parser devolve float
	# (`"id": 2.0`). Copiar o dicionário cru contaminaria o estado com floats depois de todo
	# load — id de item e quantidade são inteiros por definição.
	var mn: Array = d.get("main", [])
	for i in mini(mn.size(), main_slots.size()):
		main_slots[i] = _slot_from(mn[i])
	var bx: Array = d.get("box", [])
	for i in mini(bx.size(), box_slots.size()):
		box_slots[i] = _slot_from(bx[i])
	cursor = int(d.get("cursor", 0))
	equipped = int(d.get("equipped", 0))
	stage = int(d.get("stage", 1))
	room = int(d.get("room", 0))
	difficulty = int(d.get("difficulty", 0))
	play_ticks = int(d.get("play_ticks", 0))
	save_count = int(d.get("save_count", 0))
	return true


func save_to_file(caminho: String) -> Error:
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


func load_from_file(caminho: String) -> bool:
	if not FileAccess.file_exists(caminho):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(caminho))
	return from_dict(raw) if raw is Dictionary else false
