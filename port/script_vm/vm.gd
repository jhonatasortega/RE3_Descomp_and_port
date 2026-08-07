class_name ScriptVM
extends RefCounted
## Intérprete do bytecode de sala (SCD) — o coração do port (F2 / P2-01, P2-02).
##
## É o que faz 169 salas de puzzles, portas, gatilhos e cenas funcionarem sem uma linha de
## lógica escrita à mão: o jogo original também é um intérprete deste bytecode. Um `if` em
## GDScript para abrir uma porta específica seria dívida; executar o script daquela sala é o
## port.
##
## ── A VM real, provada no EXE (docs/decomp/notes/scd_opcodes.md) ──
##   jump-table `0x8009e0f8` (256 entradas, copiada para o scratchpad) · loop `0x80052ba4`
##   dispatch `0x80052c48`:  PC em `obj+0x1c`; lê 1 byte; indexa a tabela; chama o handler
##   retorno do handler: **1 = continua** (re-dispatch) · **2 = fim** (`evt_end` 0x01)
##   init de função `0x80052474`: `PC = script_base + func_offset[id]`
##
## Espaço de opcodes = `0x00..0x8f` (144), **provado**: `0x90/0x91` são zero na jump-table e
## `0xc0..0xf1` é a tabela de bancos de flags que mora logo depois.
##
## Os TAMANHOS de cada opcode não são inventados aqui: vêm de `data/scd_opcodes.json`, gerado
## por `tools/scd_export.py` a partir de `tools/scd_decode.py` — que os leu byte a byte dos
## 144 handlers do EXE. Uma verdade só.
##
## Esta classe faz o **percurso e o controle de fluxo**. O efeito de cada opcode de gameplay
## (abrir porta, spawnar inimigo, tocar som) entra em `opcodes/` conforme as fases avançam;
## sem handler registrado, o opcode é um NOP que apenas avança o PC — o que já permite o gate
## P2-10 (percorrer as 4238 funções sem opcode desconhecido).

const OPCODES_PATH := "res://data/scd_opcodes.json"

## --- opcodes de controle (semântica provada; ver OPCODE_SEM em scd_decode.py) ---
const OP_NOP := 0x00
const OP_EVT_END := 0x01          ## fim/return: pop da pilha de chamada
const OP_EVT_EXEC := 0x02
const OP_IF := 0x06               ## if_begin/block: 4B, salto por u16 em +2
const OP_ELSE := 0x07             ## 4B
const OP_ENDIF := 0x08            ## 2B
const OP_SLEEP := 0x0A
const OP_FOR := 0x18              ## frame de laço: salta por s16 em +4
const OP_FOR_END := 0x19
const OP_WHILE := 0x1A
const OP_WHILE_END := 0x1B
const OP_SWITCH := 0x14           ## 4B: var(u8)@+1, count(u16)@+2, case-table em +4
const OP_CASE := 0x15
const OP_DEFAULT := 0x16
const OP_ESWITCH := 0x17
const OP_GOTO := 0x18
const OP_GOSUB := 0x1D
const OP_BREAK := 0x1C

enum Status { RODANDO, FIM, ERRO_OPCODE, ERRO_LIMITE, ERRO_PC }

enum Modo {
	LINEAR,      ## percorre byte a byte sem desviar (é o que o gate P2-10 mede)
	EXECUCAO,    ## desvia de verdade: if/check/gosub/yield (P2-02/P2-03)
}

## Tamanho por opcode (0..143), vindo do dado.
static var _sizes: PackedInt32Array = PackedInt32Array()
static var _nomes: Array[String] = []
static var _carregado := false

## Limite de passos por execução — rede de segurança contra laço infinito em dry-run.
const MAX_PASSOS := 200000

var bytes := PackedByteArray()     ## bytecode da sala inteira
var func_offsets: PackedInt32Array = PackedInt32Array()
var pc := 0
var status: Status = Status.FIM
var passos := 0
var call_stack: PackedInt32Array = PackedInt32Array()   ## pilha de chamada (gosub)
var loop_stack: PackedInt32Array = PackedInt32Array()   ## pilha de laço (obj+0x140)
var trace: Array[int] = []         ## opcodes visitados (para diff contra o disassembly)
var trace_on := false
var erro := ""
var modo: Modo = Modo.LINEAR
## Estado do jogo (flags/variáveis). Sem ele, CHECK/SET viram NOP e o fluxo cai no ramo falso.
var state: GameState
var block_stack: PackedInt32Array = PackedInt32Array()   ## obj+0x140: alvo do else/endif
## AOTs que o script instalou nesta execução (P2-04). Chave = id do AOT.
var aots: Dictionary = {}
## Objetos de cenário instalados pelo `0x7f` (`om_set`), por SLOT (0..31) — é o pool
## `gs+0x4328` do motor. É daqui que sai a POSIÇÃO e a ROTAÇÃO do 3D do item (ver objeto.gd).
var objetos: Dictionary = {}
## Personagens que o script colocou nesta execução (sce_em_set 0x7d) — P2-06.
var spawns: Array[Spawn] = []
## Disparos de som do script (P2-08): {op, id, loop, extra}. A fila real do motor é
## 32×10B (`0x800de648` loop / `0x800de798` one-shot); aqui guarda-se o disparo.
var sons: Array[Dictionary] = []
var flags_lidos := 0
var flags_escritos := 0
var desvios := 0
## Colisão da sala corrente — o opcode `0x6e` escreve nela (liga/desliga colliders).
var colisao: Collision = null
var colliders_mudados := 0


static func _carregar_tabela() -> void:
	if _carregado:
		return
	_sizes = PackedInt32Array()
	_sizes.resize(144)
	_nomes = []
	_nomes.resize(144)
	var raw: Variant = null
	if FileAccess.file_exists(OPCODES_PATH):
		raw = JSON.parse_string(FileAccess.get_file_as_string(OPCODES_PATH))
	if raw is Dictionary and (raw as Dictionary).has("opcodes"):
		var ops: Dictionary = (raw as Dictionary)["opcodes"]
		for k: String in ops:
			var i := int(k)
			if i < 0 or i >= 144:
				continue
			var e: Dictionary = ops[k]
			_sizes[i] = int(e.get("size", 0))
			_nomes[i] = str(e.get("nome", "?"))
		_carregado = true
	else:
		push_error("ScriptVM: %s ausente — rode `python tools/scd_export.py`" % OPCODES_PATH)


static func size_of(op: int) -> int:
	_carregar_tabela()
	return _sizes[op] if op >= 0 and op < 144 else 0


static func name_of(op: int) -> String:
	_carregar_tabela()
	return _nomes[op] if op >= 0 and op < 144 else "?"


static func opcode_valido(op: int) -> bool:
	## `0x00..0x8f` com tamanho conhecido. Fora disso não existe opcode (provado).
	return op >= 0 and op < 144 and size_of(op) > 0


func carregar_sala(room_id: String) -> bool:
	## Lê `data/STAGE{n}/R###.scd` e a tabela de funções (u16 no início do bytecode).
	var st := RoomData.stage_of(room_id)
	var caminho := "res://data/STAGE%d/%s.scd" % [st, room_id]
	if not FileAccess.file_exists(caminho):
		erro = "bytecode ausente: %s (rode tools/scd_export.py)" % caminho
		return false
	bytes = FileAccess.get_file_as_bytes(caminho)
	if bytes.size() < 2:
		erro = "bytecode vazio"
		return false
	# `func_offsets[0]` é o fim da própria tabela -> nº de funções = offset[0] / 2
	var n := u16(0) / 2
	func_offsets = PackedInt32Array()
	for i in n:
		var o := u16(i * 2)
		if o >= bytes.size():
			break
		func_offsets.append(o)
	return not func_offsets.is_empty()


func u8(i: int) -> int:
	return bytes[i] if i >= 0 and i < bytes.size() else 0


func u16(i: int) -> int:
	if i < 0 or i + 1 >= bytes.size():
		return 0
	return bytes[i] | (bytes[i + 1] << 8)


func s16(i: int) -> int:
	var v := u16(i)
	return v - 0x10000 if v & 0x8000 else v


func iniciar(func_id: int) -> bool:
	## `0x80052474`: PC = script_base + func_offset[id].
	if func_id < 0 or func_id >= func_offsets.size():
		erro = "função %d não existe (há %d)" % [func_id, func_offsets.size()]
		status = Status.ERRO_PC
		return false
	pc = func_offsets[func_id]
	status = Status.RODANDO
	passos = 0
	call_stack = PackedInt32Array()
	loop_stack = PackedInt32Array()
	block_stack = PackedInt32Array()
	flags_lidos = 0
	flags_escritos = 0
	desvios = 0
	trace.clear()
	erro = ""
	return true


func executar(func_id: int) -> Status:
	## Percorre a função até `evt_end`. Sem handler de gameplay registrado, cada opcode é um
	## NOP que só avança o PC — é o modo do gate P2-10 (percurso das 4238 funções).
	if not iniciar(func_id):
		return status
	while status == Status.RODANDO:
		passo()
	return status


func passo() -> void:
	if pc < 0 or pc >= bytes.size():
		erro = "PC fora do bytecode: %d (tamanho %d)" % [pc, bytes.size()]
		status = Status.ERRO_PC
		return
	passos += 1
	if passos > MAX_PASSOS:
		erro = "excedeu %d passos (laço infinito?)" % MAX_PASSOS
		status = Status.ERRO_LIMITE
		return

	var op := u8(pc)
	if not opcode_valido(op):
		erro = "opcode inválido 0x%02x no PC %d" % [op, pc]
		status = Status.ERRO_OPCODE
		return
	if trace_on:
		trace.append(op)

	if modo == Modo.LINEAR:
		# Percurso LINEAR: um `if` executa o corpo em vez de pular, o que faz VISITAR todo o
		# código da função. É o que o gate P2-10 mede (nenhum byte fora dos opcodes conhecidos).
		if op == OP_EVT_END:
			_retornar()
		else:
			pc += size_of(op)
		return

	# ── Modo EXECUÇÃO: a semântica provada dos opcodes de controle ──
	# (docs/decomp/notes/scd_opcodes.md · exe_items.md §1.1)
	match op:
		OP_EVT_END:                       # 0x01: pop da pilha de chamada
			_retornar()

		0x02, 0x0A:                       # evt_next / evt_yield: handler retorna 2 = fim do tick
			pc += size_of(op)
			status = Status.FIM

		OP_IF:                            # 0x06 if_begin: empilha (PC+4+u16@+2) = alvo do else
			block_stack.append(pc + 4 + u16(pc + 2))
			pc += 4

		0x07:                             # else/endif: pop do bloco e salta por u16@+2
			if not block_stack.is_empty():
				block_stack.remove_at(block_stack.size() - 1)
			pc += u16(pc + 2)          # doc: "PC += u16@+2" (base = PC)
			desvios += 1

		0x08:                             # end-block: só desempilha
			if not block_stack.is_empty():
				block_stack.remove_at(block_stack.size() - 1)
			pc += 2

		0x19:                             # gosub: PC = func_offset[byte+1], retorno empilhado
			var fid := u8(pc + 1)
			if fid < func_offsets.size():
				call_stack.append(pc + 2)
				pc = func_offsets[fid]
				desvios += 1
			else:
				pc += 2

		0x4C:                             # CHECK flag: gateia o IF
			# byte1 = banco · u16@+2 = bit, com o BYTE ALTO = negação
			# (`0x800546cc`: retorna ((word & mask) != 0) XOR negação, IP += 4)
			var bank := u8(pc + 1)
			var operando := u16(pc + 2)
			var bit := operando & 0xFF
			var negar := (operando >> 8) != 0
			var ligado := state.flag_get(bank, bit) if state != null else false
			flags_lidos += 1
			if (ligado != negar):
				pc += 4                   # condição verdadeira: entra no bloco
			else:
				_falhar_condicao()        # falsa: pula para o alvo empilhado pelo if_begin

		0x4D:                             # SET/CLEAR flag inline
			# byte1 = banco · byte2 = bit · byte3 = modo (0 = clear, 1 = set, 2+ = variantes)
			if state != null:
				var b := u8(pc + 1)
				var bi := u8(pc + 2)
				var m := u8(pc + 3)
				state.flag_set(b, bi, m != 0)
				flags_escritos += 1
			pc += 4

		0x61, 0x62:                       # aot_set / door_aot_set_4p: instala AOT (e PORTA)
			_registrar_aot(op)
			pc += size_of(op)

		0x63, 0x64:                       # sce_aot_set (AABB) / sce_aot_set_4p (quad)
			_registrar_aot(op)
			pc += size_of(op)

		0x65:                             # aot_reset: desativa o AOT de mesmo id
			var rid := u8(pc + 1)
			if aots.has(rid):
				(aots[rid] as Aot).ativo = false
			pc += size_of(op)

		0x67, 0x68:                       # sce_item_aot_set: item no chão (2 pontos / 4 pontos)
			# `0x67` NÃO é porta (a tabela de opcodes o chamava "door_aot_set"): é o MESMO
			# handler de item na versão AABB — `0x800574f4` (22 B) contra `0x800576c4` (30 B),
			# byte a byte o mesmo payload em offset diferente. São 316 dos 330 itens do jogo.
			_registrar_aot(op)
			pc += size_of(op)

		0x7F:                             # om_set: objeto de cenário (o 3D do item vem daqui)
			var o := ObjetoSala.new()
			o.slot = u8(pc + 1)
			o.tipo = u8(pc + 2)
			o.fx = u8(pc + 3)
			o.floor_id = u8(pc + 8)
			o.modo = u8(pc + 9)
			o.visbit = u8(pc + 11)
			o.be_flg = u16(pc + 12)
			o.attr = s16(pc + 14)
			o.pos = Vector3i(s16(pc + 16), s16(pc + 18), s16(pc + 20))
			o.rot = Vector3i(s16(pc + 22), s16(pc + 24), s16(pc + 26))
			# `entry+0 = be_flg | 1`: o bit 0 (VISÍVEL) é sempre ligado no setup.
			o.be_flg |= 1
			objetos[o.slot] = o
			pc += size_of(op)

		0x6E:                             # sce_col_chg: liga/desliga UM collider (P3-10)
			# Handler `0x800556e0`, 4 bytes: [6e][idx u8][valor u16 LE]. Preserva os 6 bits
			# baixos de `+0x08` do registro (forma+canto) e grava os 10 bits altos do operando
			# (o ESTADO — o bit 0x40 é o que o movimento do player consulta). O `idx` mapeia
			# DIRETO em `rects[idx]` do `_col.json` (provado: registro 0 = cabeçalho nos dois).
			# 348 chamadas em 69 salas: portões que abrem, grades que caem, fachadas.
			# Bounds-check obrigatório: R50E func 30 escreve idx=13 numa sala de 13 rects
			# (overrun real do jogo — no PS1 escreve 16 B além do bloco e ninguém lê).
			if colisao != null:
				var ci := u8(pc + 1)
				var valor := u16(pc + 2)
				if ci < colisao.rects.size():
					var reg: Collision.Rect = colisao.rects[ci]
					reg.bits = (reg.bits & 0x3F) | (valor & 0xFFC0)
					colliders_mudados += 1
			pc += 4

		0x57:                             # SE em LOOP: id = u16@+2 (fila 0x800de648)
			sons.append({"op": op, "id": u16(pc + 2), "loop": true,
				"extra": u16(pc + 4)})
			pc += size_of(op)

		0x58:                             # SE one-shot: id = u16@+2, canal = u8@+1
			sons.append({"op": op, "id": u16(pc + 2), "loop": false,
				"canal": u8(pc + 1), "extra": u16(pc + 4)})
			pc += size_of(op)

		0x59:                             # SE one-shot com pan/pitch: id = u16@+4
			sons.append({"op": op, "id": u16(pc + 4), "loop": false,
				"a": u8(pc + 2), "b": u8(pc + 3), "extra": u16(pc + 6)})
			pc += size_of(op)

		0x7D:                             # sce_em_set: coloca personagem (inimigo/NPC)
			var sp := Spawn.new()
			sp.slot = u8(pc + 2)
			if sp.slot > 127:
				sp.slot -= 256            # s8
			sp.classe = u8(pc + 3)
			sp.arma = u16(pc + 4)
			sp.status = u16(pc + 6)
			sp.model_id = u8(pc + 0x0B)
			sp.pos = Vector3i(s16(pc + 0x0C), s16(pc + 0x0E), s16(pc + 0x10))
			sp.dir = s16(pc + 0x12)
			sp.aim_yaw = u16(pc + 0x14)
			sp.aim_pitch = u16(pc + 0x16)
			sp.resolver_especie()
			spawns.append(sp)
			pc += size_of(op)

		_:
			# Demais opcodes: avançam pelo tamanho da tabela. Os de gameplay (AOT, spawn, som)
			# entram em `opcodes/` nas próximas etapas (P2-04..P2-09); switch (0x14) e os laços
			# (0x0d/0x0e/0x18/0x1a/0x1b) seguem LINEARES até o layout da case-table/frame de
			# laço ser confirmado — declarado, não fingido.
			pc += size_of(op)


func _registrar_aot(op: int) -> void:
	## Lê o AOT do bytecode nos offsets PROVADOS (ver port/script_vm/aot.gd) e o instala.
	## Nada de heurística de varredura: a VM conhece a fronteira real da instrução, então
	## não precisa "adivinhar" se um byte é opcode ou operando.
	var a := Aot.new()
	a.opcode = op
	a.id = u8(pc + 1)
	a.sce = u8(pc + 2)
	# Layout comum da família aot_set: `+3 SAT` (máscara de quem/como dispara) e `+4 nFloor`
	# (0x80 = qualquer andar). Antes o port lia `+3` como andar — era o SAT (0x31 em 328 dos
	# 330 itens), e o andar ficava sempre igual.
	a.sat = u8(pc + 3)
	a.floor_id = u8(pc + 4)
	a.super_id = u8(pc + 5)

	if op == 0x64:                                  # gatilho em 4 pontos
		a.kind = Aot.Kind.QUAD
		for k in 4:
			a.quad.append(Vector2i(s16(pc + 6 + 4 * k), s16(pc + 8 + 4 * k)))
	elif op == 0x62:                                # porta em 4 pontos
		a.kind = Aot.Kind.QUAD
		for k in 4:
			a.quad.append(Vector2i(s16(pc + 6 + 4 * k), s16(pc + 8 + 4 * k)))
	elif op == 0x68:
		# ITEM no chão: a área é um **QUAD de 4 pontos** (+6..+21), como o `0x64` — não duas
		# esquinas. Provado no handler `0x800576c4` (PC += 30) e conferido byte a byte nos 14
		# itens do jogo: na R104 aot 4 os 8 s16 são exatamente o quad
		# (-8424,-17139) (-7710,-16350) (-6844,-16939) (-7565,-17883) que o exportador emite.
		# A leitura anterior (dois cantos) fazia a área de coleta ser só o primeiro trecho.
		a.kind = Aot.Kind.QUAD
		for k in 4:
			a.quad.append(Vector2i(s16(pc + 6 + 4 * k), s16(pc + 8 + 4 * k)))
	else:                                           # 0x61 / 0x63: AABB por (x,z,w,d)
		a.kind = Aot.Kind.BOX
		a.box = Rect2i(s16(pc + 6), s16(pc + 8), s16(pc + 10), s16(pc + 12))

	if op == 0x61 and a.is_porta():
		a.to_pos = Vector3i(s16(pc + 0x0E), s16(pc + 0x10), s16(pc + 0x12))
		a.to_facing = s16(pc + 0x14)
		a.to_stage = u8(pc + 0x16) % 9              # o handler aplica mod 9
		a.to_room = u8(pc + 0x17)
		a.to_cut = u8(pc + 0x18)
		a.to_grupo = u8(pc + 0x19)      # descriptor +0xb -> gs+0x2495 (grupo do RVD)
	elif op == 0x62 and a.is_porta():
		a.to_pos = Vector3i(s16(pc + 0x16), s16(pc + 0x18), s16(pc + 0x1A))
		a.to_facing = s16(pc + 0x1C)
		a.to_stage = u8(pc + 0x1E) % 9
		a.to_room = u8(pc + 0x1F)
		a.to_cut = u8(pc + 0x20)
		a.to_grupo = u8(pc + 0x21)      # idem para o 0x62
	elif op == 0x67 or op == 0x68:
		# PAYLOAD DE ITEM — idêntico nos dois opcodes, só muda a base: depois da geometria.
		#   `0x67` (22 B): rect em +6..+13 → payload em **+14**  (handler `0x800574f4`)
		#   `0x68` (30 B): quad em +6..+21 → payload em **+22**  (handler `0x800576c4`)
		#     +0 u8  item_id      · +1 u8 = 0 em 330/330
		#     +2 u16 amount       (dificuldade FÁCIL dobra se 21 <= item_id <= 31)
		#     +4 u16 flag_id      BIT de "já pego" — passado a `TestBit`/`SetBit`
		#     +6 u8  om           SLOT do objeto de cenário (`0x7f`) e do modelo no RDT;
		#                         >= 32 (128/255 nos dados) = item SEM modelo 3D
		#     +7 u8  iflags       bit 0 = coleta com animação · **bit 7 = tem brilho (ESP)**
		var p := 14 if op == 0x67 else 22
		a.item_id = u8(pc + p)
		a.item_qtd = u16(pc + p + 2)
		a.item_flag = u16(pc + p + 4)
		a.item_om = u8(pc + p + 6)
		a.item_flags = u8(pc + p + 7)
		# DIFICULDADE FÁCIL dobra munição: `sltiu (item_id-21) < 11` + flag global 0x100 →
		# `amount <<= 1` (`0x800577c8..d4`). Não aplicado aqui porque o port ainda não tem o
		# seletor de dificuldade (P3-06); fica registrado para quando tiver.
		if op == 0x68:
			a.sat |= 0x80                      ## o handler do 4-pontos acende esse bit
		if state != null and a.item_flag > 0 and state.flag_get(GameState.BANCO_ITENS, a.item_flag):
			# Item já pego: o handler zera o `sce` do descriptor (AOT morto) e apaga o objeto
			# de cenário (`pool[om].be_flg = 0x80000000`) — o item desaparece do chão.
			a.ativo = false
			if objetos.has(a.item_om):
				(objetos[a.item_om] as ObjetoSala).be_flg = 0

	aots[a.id] = a


func aot_em(x: int, z: int) -> Aot:
	## Teste per-frame do motor: primeiro AOT ativo que contém o ponto (`0x800505ac`).
	for k in aots:
		var a: Aot = aots[k]
		if a.contem(x, z):
			return a
	return null


func aot_em_raio(x: int, z: int, raio: int) -> Aot:
	## Interação por CONTATO DO CORPO: primeiro AOT cuja caixa encosta no círculo do
	## personagem. Prefere quem CONTÉM o ponto (desempate a favor do mais próximo).
	var toque: Aot = null
	for k in aots:
		var a: Aot = aots[k]
		if a.contem(x, z):
			return a
		if toque == null and a.encosta(x, z, raio):
			toque = a
	return toque


func itens() -> Array[Aot]:
	var saida: Array[Aot] = []
	for k in aots:
		var a: Aot = aots[k]
		if a.is_item():
			saida.append(a)
	return saida


func portas() -> Array[Aot]:
	var saida: Array[Aot] = []
	for k in aots:
		var a: Aot = aots[k]
		if a.is_porta():
			saida.append(a)
	return saida


func _retornar() -> void:
	if call_stack.is_empty():
		status = Status.FIM
	else:
		pc = call_stack[call_stack.size() - 1]
		call_stack.remove_at(call_stack.size() - 1)


func _falhar_condicao() -> void:
	## Condição falsa: o fluxo salta para o alvo que o `if_begin` empilhou (0x140).
	if block_stack.is_empty():
		pc += 4                           # sem bloco aberto: segue em frente
		return
	pc = block_stack[block_stack.size() - 1]
	block_stack.remove_at(block_stack.size() - 1)
	desvios += 1


func resumo() -> String:
	return "PC=%d passos=%d desvios=%d flags(lidos=%d escritos=%d) status=%s%s" % [
		pc, passos, desvios, flags_lidos, flags_escritos, Status.keys()[status],
		"" if erro == "" else "  erro: " + erro]
