class_name Cena
extends RefCounted
## CENA DE MOTOR do script de sala — o escalonador de threads, o tempo, a câmera e os atores.
##
## É o que faltava para as duas cinemáticas do `R10D` (a sala onde o jogo começa) existirem no
## port: elas **não são FMV** (`R10D` não tem nenhum opcode `0x7a`) e **não são um arquivo
## `R10D_2`** (não existe). São duas FUNÇÕES do SCD rodando na VM de sala, com câmera, ator,
## espera e fade — e a segunda é também a **única saída da sala**.
##
## ══════════════════════════ 1. AS DUAS CENAS DO R10D (provado) ══════════════════════════
## O caminho de entrada, opcode por opcode, do carregamento da sala até a thread:
##
##   func 2  (init da sala)   `19 03` gosub 3 · `19 04` gosub 4 · **`19 05` gosub 5** · …
##   func 5  @+0x11e          **`04 ff 19 07`** = evt_exec(slot 0xff, **função 7**)
##                            `63 01 05 41 …  ff 00 19 0b 00 00` = AOT id 1, **sce 5**,
##                            caixa x[-8585..-5285] z[-14996..-11296], payload = evt_exec(
##                            slot 0xff, **função 11**)
##
## ➜ **CENA DE ENTRADA = função 7** (174 instruções), thread aberta no init da sala.
## ➜ **CENA DE SAÍDA  = função 11** (94 instruções), thread aberta pelo AOT `sce 5` quando a
##    Jill entra na caixa. O handler do `sce 5` é `0x800512bc` (jump-table de SCE `0x8009e0bc`):
##    lê `u16@+0` e `u8@+3` do payload e chama `0x80052478` = abre a thread.
##
## ══════════════════════ 2. A SAÍDA DA SALA É A CENA — opcode `0x66` ══════════════════════
## `R10D` declara UMA porta (`61 00 01 21 …`, func 3) com **caixa (0,0,0,0)** e chegada
## **(0,0,0)**: o jogador nunca pode tocá-la. Ela é disparada **pelo script**, no fim da
## função 11:
##
##     46 00 00 02 00 00 00 ff ff ff 30   fade abr=2 preto→branco em 48 ticks (= escurece)
##     09 / 0a 30 00                      espera 48 quadros
##     47 01 00                           work = player
##     40 1f 00 00                        player+0x12d = 0    (membro 0x1f)
##     40 26 c8 00                        player+0xcc  = 200  (membro 0x26 = HP)
##     **66 00**                          sce_aot_exec(AOT 0) -> handler de sce 1 = PORTA
##     19 25                              gosub 37 (devolve o controle)
##
## `0x66` = handler **`0x80055d7c`**: `aot = gs+0x2158[id]`; `0x800decb0 = aot`;
## `gs+0x2140` = work (ou o player); `jalr *(0x8009e0bc + aot[0]*4)` com `a0` = descriptor
## (`aot+0x14` se `aot[1] & 0x80`, senão `aot+0xc`); PC += 2. Como `aot[0]` é o **SCE type**, com
## `sce == 1` o alvo é o **produtor de porta `0x80050d28`** — a mesma cadeia
## `gs+0x2154`→`door_handler 0x800248e4`→`room-loader 0x800493ec` de qualquer porta.
##
## ⚠ **Isto CORRIGE `docs/decomp/notes/door_handler.md`**, que afirmava "não há warp por opcode
## de script". Há: é o `0x66`. Prova independente, por varredura das 169 salas: existem **120**
## opcodes `0x66` no jogo, **todos** apontando para um AOT declarado na mesma sala, e as
## **6 portas mão-única que a auditoria daquele doc rotulou "box ZERO (scripted/cutscene)" são
## exatamente as disparadas por `0x66`**: `R10D`f11→aot0, `R215`f18/20/21/23→aot3,
## `R30D`f39→aot0, `R50D`f20/f82→aot1, `R50F`f7→aot0, `R510`f34→aot1. O rótulo
## "`R10D→R101` placeholder_unused, porta com box+arrival ZERADOS (único no jogo)" muda de
## sentido: não é placeholder, é a **porta roteirizada da cena de saída**.
##
## ══════════════════════ 3. O "SUBIR NA LIXEIRA" É COREOGRAFIA DA CENA ══════════════════════
## O dono está certo que a Jill sobe — e `port/script_vm/subir.gd` também está certo que
## **nenhum objeto do R10D é escalável** (os 3 `0x7f` têm `be_flg = 0x6001`). As duas coisas
## convivem porque o subir do R10D **não passa pela rotina 9 nem pelo agregador
## `0x80036570`**: é o opcode **`0x80`** (`0x80056dc0`) escrevendo o índice de sequência
## DIRETO em `player+0xc8`, com `player+4 = (rotina<<8) | 4` — **ação 4 = roteirizada**.
## Dentro da função 11:
##
##   `19 0e` gosub 14  ->  `47 01 00` work=player · **`80 00 08 00` = SEQ 8** · espera 12
##   `19 0f` gosub 15  ->  `47 01 00` work=player · **`80 00 07 00` = SEQ 7** · espera 12
##
## e na thread 17 (que roda no meio da cena): `80 00 04 00` (SEQ 4) · `80 00 09 08` (SEQ 9) ·
## **10 quadros de translação MANUAL** (`42 10 09`/`20 00 00 10 46 00`/`41 09 10` =
## `player+0x34 += 70` e `player+0x3c += 40`, mais 10 quadros de `+5` em X) · `80 00 05 00`
## (SEQ 5) · **`80 00 06 00` = SEQ 6**.
##
## **SEQ 6 e SEQ 7 são exatamente o par de subir/descer** que `subir.gd` provou na rotina 9
## (`0x8003b39c` grava `0x00070006`, `0x8003b3c4` grava `0x00070007`) — a mesma animação, aqui
## acionada pelo script em vez do agregador de objetos. E os +700 X / +400 Z manuais são a
## SUBIDA em si: o script move o corpo à mão porque não há objeto escalável para o motor usar.
##
## ➜ Conclusão: a hipótese (c) da investigação. A `subir.gd` fica como está (é a rotina 9 de
##    verdade, para R210/R219/R315/R50D); o subir do R10D é ESTA cena.
##
## ══════════════════════════ 4. O QUE ESTA CLASSE FAZ E NÃO FAZ ══════════════════════════
## FAZ: o escalonador de threads (`0x04`/`0x03`), o tempo (`0x09`/`0x0a`, `0x02`), os laços
## (`0x0d`/`0x0f`, `0x10`/`0x11`), a câmera (`0x50`/`0x51`), o fade (`0x46`), os membros da
## entidade (`0x40`/`0x41`/`0x42`/`0x20`), o ator (`0x80`/`0x81`/`0x8f`) e a porta roteirizada
## (`0x66`). Grava uma LINHA DO TEMPO com o quadro de cada evento.
##
## NÃO FAZ (e está marcado onde): a velocidade real do `0x81` (a tabela por classe
## `0x8009e52c`/`0x8009e5cc` indexada por `w+0x4a` **não foi decodificada** — ver
## `VELOCIDADE_DECLARADA` e `chegou()`); a ORDEM do escalonador entre threads criadas no mesmo
## quadro; e a semântica dos campos de `0x55`/`0x56`/`0x77`/`0x78`/`0x82`/`0x88`/`0x8e`, que só
## são registrados crus.

## Banco de flags 4 = `0x800d1fc0` (tabela de bancos `0x8009e3f8`, entrada 4). É o banco de
## RASCUNHO da sala: zerado no load (`0x80052350  sw $zero, 0x7888($s0)`) e escrito só por
## `0x4c`/`0x4d` do script e pelo AOT `sce 6`. É por ele que as threads da cena se sincronizam.
const BANCO_RASCUNHO := 4

## Slots de thread. `0x04`/`0x03` com `byte@+1 == 0xff` pedem "qualquer livre" — o motor usa
## 2..9 (`0x8005242c`). O slot 0 é a thread principal da sala.
const SLOT_QUALQUER := 0xFF
const SLOT_LIVRE_MIN := 2
const SLOT_LIVRE_MAX := 9

## Velocidade do ator no `0x81`, em unidades PS1 por quadro. 🟡 **DECLARADA**: o `0x81` só grava
## o DESTINO (`w+0xd4`/`w+0xd6`) e a rotina; a velocidade sai da tabela por classe
## `0x8009e52c`/`0x8009e5cc` indexada por `w+0x4a`, que **eu não decodifiquei**. Uso o mesmo 78
## que `port/actors/player.gd` (`VEL_ANDAR`) já mede para o andar da Jill, para não haver dois
## números no port. Quem tiver o ator de verdade andando deve chamar `chegou(bit)` e ignorar
## esta simulação (`simular_movimento = false`).
const VELOCIDADE_DECLARADA := 78

## Tolerância de chegada: um passo. Também declarada, pelo mesmo motivo.
const TOLERANCIA_CHEGADA := VELOCIDADE_DECLARADA

var vm: ScriptVM                       ## VM da sala (bytecode, AOTs, objetos)
var state: GameState
var vars: Array[int] = []              ## `0x800d1f46` — compartilhado por todas as threads
var threads: Dictionary = {}           ## slot -> ScriptVM
var pendentes: Array[Dictionary] = []  ## threads pedidas neste quadro (abrem no próximo)
var atores: Dictionary = {}            ## "id:n" -> {campos: {offset: valor}}
var quadro_atual := 0
var camera := -1
var camera_anterior := -1
var camera_presa := false              ## bit `0x80` de `gs+0x77f4` (`0x800548f0`)
var fade_ativo: Dictionary = {}
var eventos: Array[Dictionary] = []    ## linha do tempo: {quadro, tipo, ...}
var troca_de_sala: Dictionary = {}     ## pedido de porta do `0x66` (vazio = nenhum)
var simular_movimento := true          ## ver `VELOCIDADE_DECLARADA`
## Works que alguém de FORA dirige — o `world.gd` põe `"1:0"` aqui, porque quem anda com o corpo
## do player é o `player.gd` e é ele que chama `chegou(bit)`.
##
## ⚠ **Achado de 2026-08-08, e ele custou a cena de entrada do `R101`.** Antes isto era um único
## `simular_movimento = false`, que desligava a simulação de **todos** os atores. No `R10D` isso
## passou porque nenhuma thread espera o bit de uma entidade; no `R101` a função 3 faz
## `47 03 00` (work da ENTIDADE 0) · `81 00 09 01 …` · `10 04 08 00` / `4c 04 01 00` — um
## `while (não flag(4,1))` esperando a **entidade** chegar. Sem ninguém para andar com ela, a
## thread ficava presa e a cinemática só terminava pela rede de segurança dos 4000 quadros
## (medido: `cena função 3 abandonada em 4000 quadros`). O port não tem ator de entidade, então a
## `Cena` continua sendo quem move os works que **não** estão nesta lista — com a
## `VELOCIDADE_DECLARADA`, que já era declarada.
var atores_externos: Dictionary = {}
var max_quadros := 20000               ## rede de segurança
## Dívidas que a cena acumulou (esperas rompidas pelo freio de `while`, etc). O `world.gd` copia
## para `cena_debitos` — o teste cobra o registro em vez de eu fingir que está tudo medido.
var debitos: Array[String] = []


func iniciar(vm_sala: ScriptVM, func_id: int, gs: GameState = null) -> bool:
	## Abre a thread principal da cena na função `func_id`. `vm_sala` já deve ter o bytecode
	## carregado (e, se for o caso, os AOTs/objetos instalados pelo init da sala).
	vm = vm_sala
	state = gs if gs != null else (vm.state if vm.state != null else GameState.new())
	vm.state = state
	vars = []
	vars.resize(ScriptVM.N_VARS)
	for i in vars.size():
		vars[i] = 0
	threads = {}
	pendentes = []
	atores = {}
	eventos = []
	troca_de_sala = {}
	fade_ativo = {}
	debitos = []
	quadro_atual = 0
	camera = -1
	camera_anterior = -1
	camera_presa = false
	var t := _nova_thread(0, func_id)
	return t != null


func _nova_thread(slot_pedido: int, func_id: int) -> ScriptVM:
	var s := slot_pedido
	if s == SLOT_QUALQUER:
		s = -1
		for k in range(SLOT_LIVRE_MIN, SLOT_LIVRE_MAX + 1):
			if not threads.has(k):
				s = k
				break
		if s < 0:
			_evento("thread_sem_slot", {"func": func_id})
			return null
	var t := ScriptVM.new()
	# Compartilha o BYTECODE e o estado do mundo com a VM da sala (é uma thread, não uma cópia).
	t.bytes = vm.bytes
	t.func_offsets = vm.func_offsets
	t.state = state
	t.aots = vm.aots
	t.objetos = vm.objetos
	t.colisao = vm.colisao
	t.vars = vars
	t.cena = self
	t.slot = s
	t.modo = ScriptVM.Modo.CENA
	if not t.iniciar(func_id):
		_evento("thread_erro", {"func": func_id, "erro": t.erro})
		return null
	threads[s] = t
	_evento("thread", {"slot": s, "func": func_id})
	return t


func viva() -> bool:
	return not threads.is_empty() or not pendentes.is_empty()


# ═════════════════ ATALHOS PARA QUEM DIRIGE A SALA (`world.gd` não é meu) ═════════════════
# O que falta para a Jill SAIR do R10D no jogo são três linhas em `port/room/world.gd`:
#
#   1) por quadro, procurar o gatilho:      var g := Cena.gatilho_de_evento(vm, pos.x, pos.z)
#   2) quando aparecer, abrir a cena:       cena = Cena.abrir_evento(vm, g, state, pos, facing)
#   3) enquanto a cena viver, `cena.quadro()`; e quando ela pedir porta:
#                                           var p := cena.porta_pedida()
#                                           if p != null: atravessar(p)
#
# `atravessar()` já existe lá e já sabe carregar a sala e aplicar a chegada. ⚠ A chegada desta
# porta é (0,0,0) no dado (ver `aot_exec`), então o desencrave de chegada de `world.gd` vai
# entrar em ação — é o comportamento certo até o grupo do RVD estar medido.

# ══════════════════════════════════════════════════════════════════════════════════════════
# ⭐ O PADRÃO — uma cena roda POR DADO, sem código novo (pedido do dono, 2026-08-08)
#
# *"não dá para a gente ficar extraindo as cenas uma por uma, precisa de um padrão."* Este bloco
# é o padrão. Em vez de uma lista branca de salas escrita à mão, o port **audita o bytecode da
# cena** e decide: se ela só usa opcodes que o intérprete sabe atravessar, ela roda; se usa algo
# que faria a cena MENTIR ou PRENDER o jogador, ela não roda e o port diz qual opcode faltou.
# Assim a cobertura cresce sozinha conforme os opcodes entram.
#
# O critério tem TRÊS níveis, e a divisão saiu do censo (`tools/scd_cena_censo.py` →
# `port/data/cena_opcodes.json`, 169 salas varridas):
#
#  1. **IMPLEMENTADO** — semântica medida no EXE e executada aqui (`OPS_IMPLEMENTADOS`).
#  2. **INÓCUO** — o tamanho está na tabela (lida dos avanços de PC dos handlers) e o opcode
#     **não mexe no fluxo nem no sincronismo**: o intérprete anda o PC e conta. Não pode prender
#     nem corromper nada; no máximo a cena perde um efeito visual. É o caso de `0x82`, `0x5b`,
#     `0x77`, `0x70`… — a maioria do censo.
#  3. **BLOQUEANTE** (`OPS_BLOQUEANTES`) — os dois jeitos de a cena dar errado de verdade:
#     • **controle de fluxo não implementado**: o port andaria o PC em linha reta e executaria o
#       corpo de todos os ramos. `0x18`/`0x1a` (quadro de laço, `0x80053770`/`0x80053824`) e
#       `0x12`/`0x13` (`0x80053464`/`0x800534c8`) estão aqui. O `switch` (`0x14`/`0x15`/`0x16`/
#       `0x17`/`0x1b`) **saiu** desta lista neste round: está decodificado em `vm.gd`.
#     • **`0x7a` = FMV**: a cena tocaria um filme e o port pularia calado. 7 salas / 11 cenas.
#
# E há um quarto caso, que é o mais importante e **não** é uma lista: a **condição de `while`**.
# O `0x10` (`0x80053364`) avalia a condição despachando o opcode em `PC+4` (`0x80053550`) e usa o
# RETORNO como verdade. Se o port não sabe avaliar aquele opcode, `_avaliar_condicao()` devolve
# **falso** — e o laço sai na hora, isto é a cena **corre adiantada** em vez de esperar. Isso é
# mentir sobre o tempo, então uma cena cuja condição de `while` o port não avalia também não roda.
# Censo das condições de `while` em todo o jogo — são **seis** opcodes, e só isto:
#     0x4c 204 cenas (IMPLEMENTADO) · 0x43 50 · 0x4e 17 · 0x6c 4 · 0x1d 2 · 0x6d 1
# ➜ implementar `0x43` e `0x4e` como condição destrava 67 cenas. Está registrado, não feito.
const OPS_CONDICAO_IMPLEMENTADAS := {0x4C: true, 0x4E: true, 0x43: true}

## Opcodes com semântica MEDIDA e executada (`ScriptVM._passo_cena` + o `match` de EXECUÇÃO).
## Cada um tem o handler citado no arquivo onde é tratado.
const OPS_IMPLEMENTADOS := {
	# fluxo e tempo
	0x00: true, 0x01: true, 0x02: true, 0x06: true, 0x07: true, 0x08: true,
	0x09: true, 0x0A: true, 0x0D: true, 0x0F: true, 0x10: true, 0x11: true, 0x19: true,
	0x12: true, 0x13: true,                                           # do-while (novo)
	0x14: true, 0x15: true, 0x16: true, 0x17: true, 0x1B: true,       # switch (novo)
	0x03: true, 0x04: true,                                           # threads
	# variáveis e membros
	0x20: true, 0x40: true, 0x41: true, 0x42: true, 0x47: true,
	# flags e comparações
	0x4C: true, 0x4D: true, 0x4E: true, 0x43: true,
	# câmera e fade
	0x50: true, 0x51: true, 0x46: true,
	# ator
	0x80: true, 0x81: true, 0x8F: true,
	# cenário / AOT
	0x61: true, 0x62: true, 0x63: true, 0x64: true, 0x65: true, 0x66: true,
	0x67: true, 0x68: true, 0x6E: true, 0x7F: true,
	# personagem e som (registrados com os operandos crus)
	0x7D: true, 0x57: true, 0x58: true, 0x59: true,
}

## Opcodes que IMPEDEM a cena de rodar (nível 3 acima).
## ⚠ O `0x18` está aqui por MEDIÇÃO, não por preguiça — e o achado é arquitetural.
## `0x80053770` faz `PC += s16@+4` (delay slot `0x800537b8  sw $a1, 0x1c($a0)`), isto é um SALTO
## RELATIVO. Varri os 344 `0x18` do jogo: **217 têm deslocamento NEGATIVO** = aresta de volta, ou
## seja **laço infinito por desenho**. O exemplo canônico é a função 41 do `R10D`
## (`04 05 19 29` no init): dois `0x30` e um `evt_next` por quadro e `18 ff ff 00 d7 ff` voltando
## 41 bytes — é a **thread de AMBIENTE da rua**, que no motor roda para sempre EM PARALELO ao
## gameplay. O port hoje só sabe rodar cena como coisa que SUSPENDE o jogo (`World.cena`), então
## abrir uma dessas como "cena" congelaria o jogador até a rede de segurança.
## ➜ Falta um modelo de **thread concorrente** (thread de ambiente vs. cinemática), não o opcode.
const OPS_BLOQUEANTES := {
	0x18: "salto relativo `0x80053770` (`PC += s16@+4`); 217 dos 344 voltam = laço infinito de "
		+ "thread de AMBIENTE, que o port não sabe rodar em paralelo ao gameplay",
	0x1A: "fim de quadro de laço `0x80053824` — par do `0x18`",
	0x1C: "`0x800538c8` — controle de fluxo não decodificado",
	0x7A: "FMV (`0x8009e0f8[0x7a]`) — o port pularia o filme calado",
}


static func _alvos_de_chamada(vm_sala: ScriptVM, func_id: int) -> Array[int]:
	## Funções que `func_id` chama: `0x19` (gosub, `0x800537bc`) e `0x03`/`0x04` (thread).
	## Percurso LINEAR pelo corpo da função — o mesmo do censo, e é o certo aqui: interessa tudo
	## que a cena PODE executar, não só o ramo desta partida.
	var fora: Array[int] = []
	for e: Dictionary in _instrucoes(vm_sala, func_id):
		var op: int = e["op"]
		var p: int = e["pc"]
		if op == 0x19:
			fora.append(vm_sala.u8(p + 1))
		elif op == 0x03 or op == 0x04:
			fora.append(vm_sala.u8(p + 3))
	return fora


static func _instrucoes(vm_sala: ScriptVM, func_id: int) -> Array[Dictionary]:
	## Decode LINEAR do corpo de uma função: de `func_offsets[func_id]` até o `0x01` (evt_end) ou
	## o início da função seguinte. Devolve `[{pc, op}]`.
	var fora: Array[Dictionary] = []
	if vm_sala == null or func_id < 0 or func_id >= vm_sala.func_offsets.size():
		return fora
	var ini: int = vm_sala.func_offsets[func_id]
	var fim: int = vm_sala.bytes.size()
	for o: int in vm_sala.func_offsets:
		if o > ini and o < fim:
			fim = o
	var p := ini
	while p < fim:
		var op := vm_sala.u8(p)
		if not ScriptVM.opcode_valido(op):
			break
		fora.append({"pc": p, "op": op})
		if op == 0x01:
			break
		var sz := ScriptVM.size_of(op)
		if sz <= 0:
			break
		p += sz
	return fora


static func auditar(vm_sala: ScriptVM, func_id: int) -> Dictionary:
	## ⭐ "Esta cena pode rodar?" — a resposta vem do BYTECODE, não de tabela de sala.
	##
	## Devolve `{ok, funcs, opcodes, bloqueantes, condicoes, inocuos, motivo}`:
	##   `funcs`       = fechamento de chamadas a partir de `func_id` (gosub + thread)
	##   `bloqueantes` = opcodes de `OPS_BLOQUEANTES` encontrados
	##   `condicoes`   = opcodes usados como condição de `while` que o port NÃO avalia
	##   `inocuos`     = opcodes sem semântica que o intérprete só atravessa (informativo)
	var vistos: Dictionary = {}
	var funcs: Array[int] = []
	var pilha: Array[int] = [func_id]
	var opcodes: Dictionary = {}
	var bloq: Dictionary = {}
	var cond: Dictionary = {}
	var inocuos: Dictionary = {}
	while not pilha.is_empty():
		var f: int = pilha.pop_back()
		if vistos.has(f):
			continue
		vistos[f] = true
		funcs.append(f)
		var insns := _instrucoes(vm_sala, f)
		for i in insns.size():
			var op: int = insns[i]["op"]
			opcodes[op] = int(opcodes.get(op, 0)) + 1
			if OPS_BLOQUEANTES.has(op):
				bloq[op] = OPS_BLOQUEANTES[op]
			elif not OPS_IMPLEMENTADOS.has(op):
				inocuos[op] = int(inocuos.get(op, 0)) + 1
			if op == 0x10 and i + 1 < insns.size():
				var c: int = insns[i + 1]["op"]
				if not OPS_CONDICAO_IMPLEMENTADAS.has(c):
					cond[c] = int(cond.get(c, 0)) + 1
			if op == 0x19 or op == 0x03 or op == 0x04:
				var alvo: int = vm_sala.u8(int(insns[i]["pc"]) + (1 if op == 0x19 else 3))
				if not vistos.has(alvo):
					pilha.append(alvo)
	funcs.sort()
	var motivo := ""
	if not bloq.is_empty():
		var partes: Array[String] = []
		for k: int in bloq:
			partes.append("0x%02x (%s)" % [k, bloq[k]])
		motivo = "opcode bloqueante: " + ", ".join(partes)
	elif not cond.is_empty():
		var partes2: Array[String] = []
		for k: int in cond:
			partes2.append("0x%02x" % k)
		motivo = "condição de `while` que o port não avalia: " + ", ".join(partes2)
	return {"ok": motivo == "", "motivo": motivo, "funcs": funcs, "opcodes": opcodes,
		"bloqueantes": bloq, "condicoes": cond, "inocuos": inocuos}


static func primeira_camera(vm_sala: ScriptVM, func_id: int) -> int:
	## Primeiro `0x50 cut_chg` da cena, lido do bytecode. `-1` se ela não troca de câmera.
	##
	## Serve para a CHEGADA de uma porta roteirizada: o descriptor dela é 32 bytes de ZERO
	## (`to_cut = 0` é campo vazio, não câmera 0), e a cena de entrada prende a câmera no primeiro
	## `cut_chg` de qualquer jeito (`0x800548f0` acende o bit `0x80` de `gs+0x77f4`). Então a
	## câmera da cena é DADO, e emprestar câmera de outra porta não é.
	for e: Dictionary in _instrucoes(vm_sala, func_id):
		if int(e["op"]) == 0x50:
			return vm_sala.u8(int(e["pc"]) + 1) & 0x7F
	return -1


static func gatilho_de_evento(vm_sala: ScriptVM, x: int, z: int) -> Aot:
	## Primeiro AOT `sce 5` ATIVO que contém o ponto. É o gatilho da cena: o handler
	## `0x800512bc` só faz `evt_exec` com o payload, então "tocar a caixa" = "abrir a thread".
	## (O handler ainda tem um gate no topo: `if (*(u32*)0x800ccba0 & 0x02000000) return;` —
	## banco 2, o mesmo que a cena acende/apaga em `4d 02 07 01`/`4d 02 07 00`.)
	if vm_sala == null:
		return null
	for a: Aot in vm_sala.aots_de_sce(Aot.SCE_EVENTO):
		if a.contem(x, z):
			return a
	return null


static func abrir_evento(vm_sala: ScriptVM, gatilho: Aot, gs: GameState,
		pos := Vector3i.ZERO, facing := 0) -> Cena:
	## Abre a cena que o gatilho `sce 5` pede (`Aot.evento_func()`), já com o ator 1 (o player)
	## na posição informada. Devolve `null` se o gatilho não for evento.
	if gatilho == null or gatilho.sce != Aot.SCE_EVENTO:
		return null
	var fid := gatilho.evento_func()
	if fid < 0:
		return null
	var c := Cena.new()
	if not c.iniciar(vm_sala, fid, gs):
		return null
	c.por_ator(1, 0, pos, facing)
	return c


func porta_pedida() -> Aot:
	## O `Aot` que o `0x66` disparou, pronto para `world.atravessar()`. Vazio = nenhum.
	if troca_de_sala.is_empty() or vm == null:
		return null
	return vm.aots.get(int(troca_de_sala.get("aot", -1)))


func quadro() -> void:
	## Um quadro de motor: abre as threads pedidas no quadro anterior, roda cada thread até ela
	## ceder (`0x02`/`0x0a` devolvem 2 no motor) e depois anda os atores.
	##
	## 🟡 **DECLARADO — a ORDEM.** O motor percorre a lista de tarefas de script uma vez por
	## quadro (`0x80052ba4`) e uma thread criada com slot MAIOR que o da criadora ainda rodaria
	## no mesmo quadro. Eu não medi a lista, então aqui toda thread nova começa no quadro
	## SEGUINTE, em ordem de slot. O efeito é um atraso de 1 quadro por thread — visível na
	## linha do tempo, não inventado.
	quadro_atual += 1
	if quadro_atual > max_quadros:
		return
	for p: Dictionary in pendentes:
		_nova_thread(int(p["slot"]), int(p["func"]))
	pendentes = []

	var slots := threads.keys()
	slots.sort()
	for s: int in slots:
		if not threads.has(s):
			continue
		var t: ScriptVM = threads[s]
		t.status = ScriptVM.Status.RODANDO
		while t.status == ScriptVM.Status.RODANDO:
			t.passo()
		if t.status != ScriptVM.Status.CEDEU:
			if t.status != ScriptVM.Status.FIM:
				_evento("thread_erro", {"slot": s, "erro": t.erro,
					"status": ScriptVM.Status.keys()[t.status]})
			threads.erase(s)
			_evento("thread_fim", {"slot": s})

	if simular_movimento:
		_andar_atores()
	if not fade_ativo.is_empty():
		fade_ativo["t"] = int(fade_ativo["t"]) + 1
		if int(fade_ativo["t"]) >= int(fade_ativo["T"]):
			fade_ativo = {}


func rodar(limite := 6000) -> int:
	## Roda a cena até acabar (ou até `limite` quadros). Devolve o nº de quadros gastos.
	while viva() and quadro_atual < limite:
		quadro()
	return quadro_atual


# ═══════════════════════════════ chamadas vindas da VM ═══════════════════════════════

func while_estourado(slot_thread: int, pc_while: int, giros: int) -> void:
	## O FREIO de `while` do `ScriptVM` agiu: a espera foi rompida pelo port, não pelo script.
	## Fica na linha do tempo e em `debitos` — é dívida declarada, não sucesso.
	var d := "thread %d: `while` em PC %d rompido depois de %d voltas (espera que o port não sabe satisfazer)" % [slot_thread, pc_while, giros]
	if not debitos.has(d):
		debitos.append(d)
	_evento("while_estourado", {"slot": slot_thread, "pc": pc_while, "giros": giros})


func abrir_thread(slot_pedido: int, func_id: int) -> void:
	pendentes.append({"slot": slot_pedido, "func": func_id})


func cut_chg(cam: int, bit_extra: bool) -> void:
	camera_anterior = camera
	camera = cam
	camera_presa = true
	_evento("camera", {"cam": cam, "anterior": camera_anterior, "bit80": bit_extra})


func cut_old() -> void:
	var v := camera_anterior
	camera_anterior = camera
	camera = v
	camera_presa = false
	_evento("camera_volta", {"cam": camera})


func fade(a0: int, a2: int, abr: int, c0: int, c1: int, T: int) -> void:
	fade_ativo = {"abr": abr, "c0": c0, "c1": c1, "T": T, "t": 0, "a0": a0, "a2": a2}
	_evento("fade", {"abr": abr, "c0": c0, "c1": c1, "T": T})


func ator_anim(id: int, n: int, rotina: int, seq: int, fl: int) -> void:
	var a := _ator(id, n)
	a["campos"][0x0C8] = seq            ## `player+0xc8` = índice de SEQUÊNCIA do EDD
	a["campos"][0x0C9] = 0
	a["campos"][0x004] = (rotina << 8) | 4   ## ação 4 = roteirizada, rotina = byte@+1
	a["campos"][0x144] = fl
	_evento("anim", {"work": _chave(id, n), "seq": seq, "rotina": rotina, "flags": fl})


func ator_ir(id: int, n: int, rotina: int, bit: int, x: int, z: int) -> void:
	var a := _ator(id, n)
	a["campos"][0x004] = (rotina << 8) | 4
	a["campos"][0x146] = bit            ## bit do banco 4 que o motor acende na chegada
	a["campos"][0x0D4] = x
	a["campos"][0x0D6] = z
	a["indo"] = true
	_evento("ir", {"work": _chave(id, n), "rotina": rotina, "bit": bit, "x": x, "z": z})


func ator_ativa(n: int) -> void:
	var a := _ator(3, n)
	a["campos"][0x000] = 1
	a["ativo"] = true
	_evento("ativa", {"work": _chave(3, n)})


func aot_exec(aid: int) -> void:
	## `0x66` — dispara o SCE do AOT `aid` na hora. Com `sce == 1` (ou 13) isso é uma TROCA DE
	## SALA: o produtor `0x80050d28` grava `gs+0x2154 = descriptor` e liga `0x800c7960`, e o
	## `door_handler 0x800248e4` lê a chegada em `descriptor+0/+2/+4/+6` e o destino em `+8`/`+9`.
	if not vm.aots.has(aid):
		_evento("aot_exec_ausente", {"id": aid})
		return
	var a: Aot = vm.aots[aid]
	if a.sce == 1 or a.sce == 13:
		# ⚠ A CHEGADA da porta roteirizada do R10D é **(0,0,0) facing 0** no dado — e (0,0,0)
		# NÃO é ponto válido no R101 (as outras duas portas que entram lá chegam em
		# (-18808,-7200,-11475) e (-4434,-3600,-27933)). O `door_handler 0x800248e4` também lê
		# `descriptor+0xb` = GRUPO do RVD (`gs+0x2495`) — que é por onde a posição deve vir
		# quando a chegada é zero. **Eu não medi o RVD**: o port entrega `pos` e `grupo` como
		# estão e quem monta a sala decide, em vez de eu inventar uma coordenada.
		troca_de_sala = {
			"stage": a.to_stage, "room": a.to_room, "cut": a.to_cut, "grupo": a.to_grupo,
			"pos": a.to_pos, "facing": a.to_facing, "aot": aid, "sce": a.sce,
			"chegada_zerada": a.to_pos == Vector3i.ZERO}
		_evento("porta", troca_de_sala)
	else:
		_evento("aot_exec", {"id": aid, "sce": a.sce})


func membro_set(id: int, n: int, membro: int, valor: int) -> void:
	if ScriptVM.MEMBROS_GLOBAIS.has(membro):
		_evento("global_set", {"addr": ScriptVM.MEMBROS_GLOBAIS[membro], "valor": valor})
		return
	if not ScriptVM.MEMBROS.has(membro):
		return
	var off: int = ScriptVM.MEMBROS[membro][0]
	var largura: int = ScriptVM.MEMBROS[membro][1]
	# Reproduz o PAR store/load do motor: o `member_set` grava com `sw`/`sh`/`sb` e o
	# `member_get` relê com `lw`/`lh`/`lhu`/`lb`/`lbu` — logo o campo TRUNCA na largura e o
	# sinal é o da instrução de leitura (largura negativa na tabela = `lh`/`lb`).
	var bits: int = absi(largura) * 8
	var v := valor
	if bits < 32:
		v = valor & ((1 << bits) - 1)
		if largura < 0 and (v & (1 << (bits - 1))) != 0:
			v -= 1 << bits
	_ator(id, n)["campos"][off] = v


func membro_get(id: int, n: int, membro: int) -> int:
	if not ScriptVM.MEMBROS.has(membro):
		return 0
	var off: int = ScriptVM.MEMBROS[membro][0]
	var campos: Dictionary = _ator(id, n)["campos"]
	return int(campos.get(off, 0))


# ═══════════════════════════════ atores e movimento ═══════════════════════════════

static func _chave(id: int, n: int) -> String:
	return "%d:%d" % [id, n]


func _ator(id: int, n: int) -> Dictionary:
	var k := _chave(id, n)
	if not atores.has(k):
		atores[k] = {"campos": {}, "indo": false, "ativo": false, "id": id, "n": n}
	return atores[k]


func ator_pos(id: int, n: int) -> Vector3i:
	## Posição em coordenadas PS1: membros 0x09/0x0a/0x0b = `w+0x34`/`+0x38`/`+0x3c`.
	var c: Dictionary = _ator(id, n)["campos"]
	return Vector3i(int(c.get(0x34, 0)), int(c.get(0x38, 0)), int(c.get(0x3C, 0)))


func por_ator(id: int, n: int, pos: Vector3i, facing := 0) -> void:
	## Instala a posição/ângulo de um ator (o player, tipicamente) antes de rodar a cena.
	var c: Dictionary = _ator(id, n)["campos"]
	c[0x34] = pos.x
	c[0x38] = pos.y
	c[0x3C] = pos.z
	c[0x6E] = facing


func chegou(bit: int) -> void:
	## O que o motor faz quando o ator termina o deslocamento do `0x81`:
	## `0x800169f0  jal 0x800788dc` com `a0 = 0x800d1fc0` (banco 4) e `a1 = w+0x146` —
	## isto é, ACENDE o bit do banco de rascunho que o `0x81` guardou. É o que solta o
	## `while (não flag)` da thread. Chame isto quando o ator de verdade chegar.
	if state != null:
		state.flag_set(BANCO_RASCUNHO, bit, true)
	_evento("chegou", {"bit": bit})


func _andar_atores() -> void:
	for k: String in atores:
		if atores_externos.has(k):
			continue                          ## quem dirige este ator é o `player.gd`
		var a: Dictionary = atores[k]
		if not bool(a.get("indo", false)):
			continue
		var c: Dictionary = a["campos"]
		var x := int(c.get(0x34, 0))
		var z := int(c.get(0x3C, 0))
		var dx := int(c.get(0x0D4, 0)) - x
		var dz := int(c.get(0x0D6, 0)) - z
		var d := int(sqrt(float(dx * dx + dz * dz)))
		if d <= TOLERANCIA_CHEGADA:
			c[0x34] = int(c.get(0x0D4, 0))
			c[0x3C] = int(c.get(0x0D6, 0))
			a["indo"] = false
			chegou(int(c.get(0x146, 0)))
			continue
		c[0x34] = x + dx * VELOCIDADE_DECLARADA / d
		c[0x3C] = z + dz * VELOCIDADE_DECLARADA / d


# ═══════════════════════════════ linha do tempo ═══════════════════════════════

func _evento(tipo: String, dados: Dictionary) -> void:
	var e := dados.duplicate()
	e["quadro"] = quadro_atual
	e["tipo"] = tipo
	eventos.append(e)


func eventos_de(tipo: String) -> Array[Dictionary]:
	var saida: Array[Dictionary] = []
	for e: Dictionary in eventos:
		if str(e["tipo"]) == tipo:
			saida.append(e)
	return saida


func cameras() -> Array[int]:
	var saida: Array[int] = []
	for e: Dictionary in eventos_de("camera"):
		saida.append(int(e["cam"]))
	return saida


func seqs() -> Array[int]:
	var saida: Array[int] = []
	for e: Dictionary in eventos_de("anim"):
		saida.append(int(e["seq"]))
	return saida


func linha_do_tempo() -> String:
	var linhas: Array[String] = []
	for e: Dictionary in eventos:
		var d := ""
		for k: String in e:
			if k == "quadro" or k == "tipo":
				continue
			d += " %s=%s" % [k, e[k]]
		linhas.append("q%5d  %-18s%s" % [int(e["quadro"]), str(e["tipo"]), d])
	return "\n".join(linhas)
