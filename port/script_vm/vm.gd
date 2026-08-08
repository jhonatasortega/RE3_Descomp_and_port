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

enum Status { RODANDO, FIM, ERRO_OPCODE, ERRO_LIMITE, ERRO_PC, CEDEU }

enum Modo {
	LINEAR,      ## percorre byte a byte sem desviar (é o que o gate P2-10 mede)
	EXECUCAO,    ## desvia de verdade: if/check/gosub/yield (P2-02/P2-03)
	CENA,        ## EXECUCAO + tempo: sleep, laços, câmera, fade, ator, thread (ver cena.gd)
}

## ═════════════════════════ MEMBROS DA ENTIDADE (`0x40`/`0x41`/`0x42`) ═════════════════════════
## Tabelas de 43 entradas do EXE, uma por membro: `member_set` = `0x80010950`
## (despachada por `0x80053e10`, `sltiu $a1,0x2b`) e `member_get` = `0x80010a00`
## (despachada por `0x80053fac`). Cada entrada é UMA instrução de store/load num offset FIXO
## do struct de personagem — foi daí que esta tabela saiu, offset por offset, nas duas direções
## (as duas concordam em 43/43). `largura` negativa = leitura COM sinal (`lh`/`lb`).
##   membro: [offset no struct, largura em bytes (negativa = com sinal)]
const MEMBROS := {
	0x00: [0x000, 2], 0x01: [0x002, 2], 0x02: [0x004, 1], 0x03: [0x005, 1],
	0x04: [0x006, 1], 0x05: [0x007, 1], 0x06: [0x04A, 1], 0x07: [0x046, 2],
	0x08: [0x010, 4], 0x09: [0x034, 4], 0x0A: [0x038, 4], 0x0B: [0x03C, 4],
	0x0C: [0x06C, -2], 0x0D: [0x06E, -2], 0x0E: [0x070, -2], 0x0F: [0x009, -1],
	0x10: [0x0D2, 2], 0x11: [0x122, -2], 0x12: [0x0D4, -2], 0x13: [0x0D6, -2],
	0x14: [0x144, 2], 0x15: [0x148, -2], 0x16: [0x14A, -2], 0x17: [0x14C, -2],
	0x18: [0x14E, -2], 0x19: [0x0C0, 1], 0x1A: [0x0C0, -2], 0x1B: [0x0C2, -2],
	0x1C: [0x0C4, -2], 0x1D: [0x1CC, 2], 0x1E: [0x1CE, 2], 0x1F: [0x12D, 1],
	# 0x20..0x25 NÃO são campos da entidade: são os globais 0x800e0154..0x800e0168
	# (`lw` direto, sem `$a0`). Ficam fora desta tabela de propósito.
	0x26: [0x0CC, -2], 0x27: [0x00C, 1], 0x28: [0x12A, -2], 0x29: [0x12C, 1],
	0x2A: [0x00D, 1],
}
## Os 6 membros que são GLOBAIS e não campos de entidade (`0x80053f38`.. / `0x80054154`..).
const MEMBROS_GLOBAIS := {0x20: 0x800E0154, 0x21: 0x800E0158, 0x22: 0x800E015C,
	0x23: 0x800E0160, 0x24: 0x800E0164, 0x25: 0x800E0168}

## Operações do `0x20`/`0x21` — tabela `0x80010900` (12 entradas), despacho `0x80053a54`
## (`sltiu $a0,0xc`). Cada entrada é uma instrução aritmética sobre o u16 apontado por `$a1`.
enum Aritm { SOMA = 0, SUB = 1, MUL = 2, DIV = 3, MOD = 4, OU = 5, E = 6, XOR = 7, NAO = 8 }

## Vetor de VARIÁVEIS do script: `0x800d1f46`, u16 indexado (lido/escrito por `0x20`, `0x41`,
## `0x42`). É GLOBAL no motor — todas as threads da sala compartilham, e é por isso que a `Cena`
## instala o MESMO `Array` em todas elas.
const N_VARS := 64

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

# ── Estado de CENA (só usado em `Modo.CENA`; ver `port/script_vm/cena.gd`) ──
## Dono do mundo compartilhado da cena (câmera, atores, fade, threads). `Cena`, mas declarado
## solto para não criar dependência circular de tipos.
var cena: Object = null
## Contadores de `sleep` do `0x09`/`0x0a`. No motor moram em `obj + 0xa0 + depth*8 + n*2`
## (`0x8005305c..0x80053090`), um por nível de aninhamento — aqui, uma pilha.
var sleeps: Array[int] = []
## Quadros de laço do `0x0d`(for)/`0x10`(while): `{tipo, inicio, fim, resta}`. No motor são
## `obj+0x20` (início) e `obj+0x60` (saída) indexados por profundidade e aninhamento.
var quadros_laco: Array[Dictionary] = []
## Objeto de trabalho corrente (`0x47`): `id` = entrada da tabela `0x80010b60`
## (1 = `*(0x800ccd94)` = player, 2 = `*(0x800ccd98)`, 3 = `gs+0x265c[n+2]`, 4 = `0x800ca700+…`)
## e `n` = o `s8` do operando. É o `obj+0x154` do motor.
var work_id := 1
var work_n := 0
## Vetor de variáveis `0x800d1f46` — instalado pela `Cena` (mesma instância em todas as threads).
var vars: Array[int] = []
## Slot de thread deste contexto (`0x04`/`0x03`): 0xff = "qualquer livre 2..9".
var slot := 0


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
	sleeps = []
	quadros_laco = []
	work_id = 1
	work_n = 0
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

	# ── Modo CENA: tempo, câmera, ator e thread (docs/decomp/notes/cena_r10d.md) ──
	# Fica ANTES do `match` de EXECUÇÃO e só intercepta os opcodes que a cena precisa; o resto
	# cai no caminho de sempre, byte a byte igual. Os modos LINEAR/EXECUCAO não mudam nada.
	if modo == Modo.CENA and _passo_cena(op):
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
			# entram em `opcodes/` nas próximas etapas (P2-04..P2-09); switch (0x14) e os quadros_laco
			# (0x0d/0x0e/0x18/0x1a/0x1b) seguem LINEARES até o layout da case-table/frame de
			# laço ser confirmado — declarado, não fingido.
			pc += size_of(op)


func s8(i: int) -> int:
	var v := u8(i)
	return v - 0x100 if v & 0x80 else v


# ═══════════════════════════════════════════════════════════════════════════════════════════
# OPCODES DE CENA — cada `case` cita o handler do EXE de onde a semântica saiu
# (jump-table `0x8009e0f8`, dispatch `0x80052c48`). Devolve `true` se tratou o opcode.
# ═══════════════════════════════════════════════════════════════════════════════════════════
func _passo_cena(op: int) -> bool:
	match op:
		0x02:
			# evt_next (`0x80052e60`): PC += 1 e RETORNA 2 = fim do tick. É o "espera 1 quadro".
			pc += 1
			status = Status.CEDEU
			return true

		0x09:
			# sleep_init (`0x8005304c`): empilha o contador com o **u16 em PC+2** — que é o
			# operando do `0x0a` seguinte (`lhu $v1,2($a2)` com `$a2` = PC velho) — e PC += 1.
			sleeps.append(u16(pc + 2))
			pc += 1
			return true

		0x0A:
			# sleeping (`0x80053094`): decrementa o contador do topo; se ainda != 0 o PC NÃO
			# anda (o handler volta 2 e o mesmo `0x0a` re-despacha no próximo quadro); ao chegar
			# a 0, PC += 3 e desempilha. **Volta 2 nos DOIS casos** (`0x800530f0`), logo
			# `09 | 0a 01 00` gasta exatamente 1 quadro.
			if sleeps.is_empty():
				pc += 3
				status = Status.CEDEU
				return true
			var n := sleeps[sleeps.size() - 1] - 1
			if n > 0:
				sleeps[sleeps.size() - 1] = n
			else:
				sleeps.remove_at(sleeps.size() - 1)
				pc += 3
			status = Status.CEDEU
			return true

		0x0D:
			# for (`0x80053184`): `0d ?? <len s16@+2> <count u16@+4>`. `count == 0` salta o laço
			# inteiro (`0x8005320c`: PC = PC + s16@+2 + 6). Senão empilha o quadro com
			# início = PC+6 e saída = PC+6+len (`0x800531e8`/`0x800531ec`).
			var flen := s16(pc + 2)
			var cnt := u16(pc + 4)
			if cnt == 0:
				pc += 6 + flen
				return true
			pc += 6
			quadros_laco.append({"tipo": "for", "inicio": pc, "fim": pc + flen, "resta": cnt})
			return true

		0x0F:
			# next (`0x800532e8`): decrementa o contador; != 0 volta ao início, == 0 sai
			# (PC += 2) e desempilha. Retorna 1 — NÃO cede o quadro (quem cede é o `0x02`
			# dentro do corpo).
			if quadros_laco.is_empty():
				pc += 2
				return true
			var f: Dictionary = quadros_laco[quadros_laco.size() - 1]
			f["resta"] = int(f["resta"]) - 1
			if int(f["resta"]) != 0:
				pc = int(f["inicio"])
			else:
				quadros_laco.remove_at(quadros_laco.size() - 1)
				pc += 2
			return true

		0x10:
			# while (`0x80053364`): `10 <cond_len> <len u16@+2>`. Guarda o PC do PRÓPRIO `0x10`
			# como início (`sw $a1,0x20($s0)`), a saída em PC+4+len, e avalia a condição pelo
			# `0x80053550` — que DESPACHA o opcode de check em PC+4 (ele mesmo anda o PC).
			# Condição != 0 → entra no corpo; == 0 → PC = saída (`0x800533ec`).
			var inicio := pc
			var wlen := u16(pc + 2)
			var saida := pc + 4 + wlen
			pc += 4
			var cond := _avaliar_condicao()
			if cond:
				quadros_laco.append({"tipo": "while", "inicio": inicio, "fim": saida, "resta": 0})
			else:
				pc = saida
			return true

		0x11:
			# endwhile (`0x80053420`): PC = início guardado (o próprio `0x10`) e desempilha —
			# o `0x10` reavalia a condição e reempilha. Não cede o quadro.
			if not quadros_laco.is_empty() and str(quadros_laco[quadros_laco.size() - 1]["tipo"]) == "while":
				pc = int(quadros_laco[quadros_laco.size() - 1]["inicio"])
				quadros_laco.remove_at(quadros_laco.size() - 1)
			else:
				pc += 2
			return true

		0x47:
			# work_set (`0x8005441c`): zera `obj+0x158..0x16c` e escolhe o objeto de trabalho
			# (`obj+0x154`) na tabela `0x80010b60` por `byte@+1 - 1`; `byte@+2` é `s8`.
			work_id = u8(pc + 1)
			work_n = s8(pc + 2)
			pc += 3
			return true

		0x40:
			# member_set imediato (`0x80053b74` → `0x80053e10`): membro = `byte@+1`,
			# valor = `s16@+2`.
			_membro_set(u8(pc + 1), s16(pc + 2))
			pc += 4
			return true

		0x41:
			# member_set por VAR (`0x80053bc0`): membro = `byte@+1`, valor = `var[byte@+2]`.
			# ⚠ A leitura é **`lh`** (`0x80053bf0  lh $a2, ($v1)`) — ASSINADA. Sem isso a
			# coordenada de um ator (que passa por var no `+=` do script) volta positiva e o
			# ator anda para o outro lado do mapa.
			_membro_set(u8(pc + 1), _var_get_s(u8(pc + 2)))
			pc += 3
			return true

		0x42:
			# member_get para VAR (`0x80053c20` → `0x80053fac`): `var[byte@+1] = membro byte@+2`.
			_var_set(u8(pc + 1), _membro_get(u8(pc + 2)))
			pc += 3
			return true

		0x20:
			# aritmética em VAR (`0x800539b8` → `0x80053a54`): `u16@+2` = (op no byte BAIXO,
			# índice de var no byte ALTO); valor = `s16@+4`.
			var opr := u8(pc + 2)
			var vi := u8(pc + 3)
			# `lh` (assinado) só nas entradas 2 (`mult`) e 3 (`divu` sobre `lh`) da tabela
			# `0x80010900`; as outras leem com `lhu`. Para soma/sub dá no mesmo módulo 2^16.
			var a := _var_get_s(vi) if (opr == Aritm.MUL or opr == Aritm.DIV) else _var_get(vi)
			_var_set(vi, _aritmetica(opr, a, s16(pc + 4)))
			pc += 6
			return true

		0x50:
			# cut_chg (`0x800548c8` → `0x800549c4`): câmera = `byte@+1 & 0x7f`; acende
			# `gs+0x77f4 |= 0x80` (câmera presa pelo script) e `|= 0x400000`. O bit `0x80` do
			# operando ainda zera `0x800d442e` e liga `0x800e01c6`.
			if cena != null:
				cena.call("cut_chg", u8(pc + 1) & 0x7F, (u8(pc + 1) & 0x80) != 0)
			pc += 2
			return true

		0x51:
			# cut_old (`0x80054960`): volta à câmera anterior guardada em `0x800e0175` e apaga o
			# bit `0x80` de `gs+0x77f4`.
			if cena != null:
				cena.call("cut_old")
			pc += 1
			return true

		0x46:
			# fade (`0x80054384` → `0x8002a35c`, o mesmo fade do boot): 11 B.
			#   a0 = byte@+1 · a2 = byte@+2 · a3 = **abr** = byte@+3
			#   c0 = byte@+6 | byte@+5<<8 | byte@+4<<16   (cor inicial, BGR→RGB)
			#   c1 = byte@+9 | byte@+8<<8 | byte@+7<<16   (cor final)
			#   T  = byte@+0xa (ticks)
			if cena != null:
				cena.call("fade", u8(pc + 1), u8(pc + 2), u8(pc + 3),
					u8(pc + 6) | (u8(pc + 5) << 8) | (u8(pc + 4) << 16),
					u8(pc + 9) | (u8(pc + 8) << 8) | (u8(pc + 7) << 16),
					u8(pc + 10))
			pc += 11
			return true

		0x66:
			# sce_aot_exec (`0x80055d7c`): DISPARA o AOT de id `byte@+1` na hora —
			# `aot = gs+0x2158[id]`, `0x800decb0 = aot`, `gs+0x2140` = work (ou o player quando
			# `obj+0x154 == 1`), e `jalr *(0x8009e0bc + sce*4)` com `a0` = descriptor
			# (`aot+0x14` se `aot[1] & 0x80`, senão `aot+0xc`). É por AQUI que o script troca de
			# sala: com `sce == 1` o handler é o produtor de porta `0x80050d28`.
			var aid := u8(pc + 1)
			if cena != null:
				cena.call("aot_exec", aid)
			pc += 2
			return true

		0x03, 0x04:
			# evt_exec (`0x80052e78` / `0x80052ea4`): abre uma THREAD — `slot = byte@+1`
			# (0xff = qualquer livre) e `função = byte@+3`; o PC inicial sai de `0x80052474`.
			if cena != null:
				cena.call("abrir_thread", u8(pc + 1), u8(pc + 3))
			pc += 4
			return true

		0x80:
			# anim/ação do work (`0x80056dc0`): `w+4 = (byte@+1 << 8) | 4` (ação 4 = roteirizada,
			# rotina = byte@+1), `w+0xc9 = 0`, **`w+0xc8 = byte@+2` = índice de SEQUÊNCIA do EDD**,
			# `w+0x144 = byte@+3`, `w+0x46 |= 0x100`.
			if cena != null:
				cena.call("ator_anim", work_id, work_n, u8(pc + 1), u8(pc + 2), u8(pc + 3))
			pc += 4
			return true

		0x81:
			# ir até (x,z) (`0x80056e5c`): `w+4 = (byte@+2 << 8) | 4` (rotina = byte@+2),
			# **`w+0x146 = byte@+3` = o BIT do banco 4 que o motor acende quando chega**
			# (`0x800169f0`: `0x800788dc(0x800d1fc0, w+0x146)`), `w+0xd4 = u16@+4` (X destino),
			# `w+0xd6 = u16@+6` (Z destino), copiados em `w+0x14c/0x14e`.
			if cena != null:
				cena.call("ator_ir", work_id, work_n, u8(pc + 2), u8(pc + 3),
					s16(pc + 4), s16(pc + 6))
			pc += 8
			return true

		0x8F:
			# liga a entidade n (`0x800589fc`): `e = gs+0x265c[(byte@+1)+2]`, `e+0 = 1`,
			# `e+4 = 0`, `e+0xd2 = 0` — é o "kick" que faz o ator entrar em cena.
			if cena != null:
				cena.call("ator_ativa", u8(pc + 1))
			pc += 2
			return true

		0x55, 0x56:
			# som posicional (`0x80054bc0`/`0x80054c28` → `0x80034124`). 8 B cada. O port
			# registra o disparo com os operandos CRUS: a semântica dos campos não foi medida.
			sons.append({"op": op, "bruto": bytes.slice(pc, pc + 8),
				"x": s16(pc + 2), "y": s16(pc + 4), "z": s16(pc + 6)})
			pc += size_of(op)
			return true
	return false


func _avaliar_condicao() -> bool:
	## `0x80053550`: despacha o opcode de check que está no PC (ele mesmo anda o PC) e usa o
	## VALOR DE RETORNO do handler como condição. O port cobre o `0x4c` (CHECK de flag,
	## `0x800546cc`), que é o único que a cena do R10D usa; qualquer outro é tratado como
	## FALSO e registrado, em vez de fingir um valor.
	var op := u8(pc)
	if op == 0x4C:
		# `0x800546cc`: banco = byte@+1; `a1 = u16@+2` = (bit no byte BAIXO, NEGAÇÃO no ALTO);
		# resultado = ((banco[bit>>5] & (0x80000000 >> (bit&0x1f))) != 0) XOR (byte alto == 0).
		var banco := u8(pc + 1)
		var bit := u8(pc + 2)
		var alto := u8(pc + 3)
		pc += 4
		flags_lidos += 1
		var ligado := state.flag_get(banco, bit) if state != null else false
		return ligado != (alto == 0)
	# opcode de condição não coberto: anda o PC e devolve falso (declarado, não inventado)
	erro = "condição com opcode 0x%02x não implementada (PC %d)" % [op, pc]
	pc += size_of(op)
	return false


func _var_get(i: int) -> int:
	## Leitura `lhu` (sem sinal) — o vetor `0x800d1f46` é de u16.
	if i < 0 or i >= vars.size():
		return 0
	return vars[i]


func _var_get_s(i: int) -> int:
	## Leitura `lh` (com sinal).
	var v := _var_get(i)
	return v - 0x10000 if v & 0x8000 else v


func _var_set(i: int, v: int) -> void:
	if i < 0:
		return
	while vars.size() <= i:
		vars.append(0)
	vars[i] = v & 0xFFFF


func _aritmetica(opr: int, a: int, b: int) -> int:
	## Tabela `0x80010900` (12 entradas), despacho `0x80053a54`. Só as 9 usadas pelas salas.
	match opr:
		Aritm.SOMA: return a + b
		Aritm.SUB: return a - b
		Aritm.MUL: return a * b
		Aritm.DIV: return a / b if b != 0 else 0
		Aritm.MOD: return a % b if b != 0 else 0
		Aritm.OU: return a | b
		Aritm.E: return a & b
		Aritm.XOR: return a ^ b
		Aritm.NAO: return ~a
	return a


func _membro_set(membro: int, valor: int) -> void:
	if cena != null:
		cena.call("membro_set", work_id, work_n, membro, valor)


func _membro_get(membro: int) -> int:
	if cena != null:
		return int(cena.call("membro_get", work_id, work_n, membro))
	return 0


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

	# PAYLOAD (os 6 bytes que o handler `0x8009e0bc[sce]` recebe em `a0`). O laço da VM de AOT
	# escolhe a base pelo bit `0x80` do `sat` (`0x80050a88 andi $v0,$v0,0x80`): `aot+0x14` quando
	# aceso, `aot+0xc` quando apagado — e `aot = opcode + 2`, logo `opcode+0x16` ou `opcode+0x0e`.
	var pbase := (pc + 0x16) if (a.sat & Aot.SAT_QUAD) != 0 else (pc + 0x0E)
	var plen := mini(6, maxi(0, bytes.size() - pbase))
	a.payload = bytes.slice(pbase, pbase + plen)

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


func aots_de_sce(sce: int) -> Array[Aot]:
	## Todos os AOTs ATIVOS de um tipo `sce` (o índice da tabela `0x8009e0bc`).
	var saida: Array[Aot] = []
	for k in aots:
		var a: Aot = aots[k]
		if a.sce == sce and a.ativo:
			saida.append(a)
	return saida


func baus() -> Array[Aot]:
	return aots_de_sce(Aot.SCE_BAU)


## Distância do ponto de sonda: `0x26c` = 620, lido em `0x800505c8` (o laço roda
## `rotate(0x26c, 0, char+0x6e)` por `0x80078690` e testa esse ponto, não o corpo).
const SONDA := 620


static func sonda_de(pos: Vector3i, facing: int) -> Vector2i:
	## Ponto testado pelos AOTs com `sat & 0x20`: 620 unidades à FRENTE do personagem.
	return Vector2i(
		pos.x + (PS1Math.rsin(facing) * SONDA >> PS1Math.SHIFT),
		pos.z - (PS1Math.rcos(facing) * SONDA >> PS1Math.SHIFT))


func aot_de_acao(sce: int, pos: Vector3i, facing: int) -> Aot:
	## AOT do tipo `sce` que o botão de AÇÃO dispararia agora — a mesma ordem do motor:
	## exige `sat & 0x10` (a passagem de ação) e usa corpo/sonda conforme `sat & 0x40`/`0x20`.
	## É o gatilho do BAÚ (`sce 9`, `sat 0x31` nos 16 do jogo) e da MÁQUINA DE ESCREVER (`sce 8`).
	var sonda := sonda_de(pos, facing)
	var corpo := Vector2i(pos.x, pos.z)
	for a: Aot in aots_de_sce(sce):
		if a.exige_acao() and a.disparado(corpo, sonda):
			return a
	return null


func bau_de_acao(pos: Vector3i, facing: int) -> Aot:
	## Atalho do gatilho do baú: `sce 9`. Devolve `null` se não há baú ao alcance.
	return aot_de_acao(Aot.SCE_BAU, pos, facing)


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
