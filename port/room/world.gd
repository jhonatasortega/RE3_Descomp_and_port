class_name World
extends RefCounted
## Mundo: as 169 salas ligadas pelas portas (P2-05 / P3-01 / P3-03).
##
## Sai da "sala única" do protótipo. A cadeia que o motor executa, e que aqui se reproduz:
##
##   AOT com `sce ∈ {1,13}` contém o personagem     `0x800505ac` (VM de colisão de AOT)
##     → produtor grava o descriptor                `0x80050d28` (gs+0x2154, flag 0x800c7960)
##       → door_handler lê chegada/stage/room        `0x800248e4`
##         → room-loader troca a sala                `0x800493ec` (fileid 0x8009dfd0[stage][room])
##
## O destino é **campo ESTÁTICO** do SCD (não runtime): `next_stage@+0x16` (mod 9),
## `next_room@+0x17`, chegada em `s16@+0xe/+0x10/+0x12/+0x14` para o `0x61`. O de-para
## índice→nome é `Rxyz` = dígitos hex — ver `docs/decomp/notes/door_handler.md`.
##
## Esta classe é LÓGICA: carrega sala, aplica chegada, mantém o estado do jogo. Quem desenha
## (present/screen.gd) ouve os sinais.

signal sala_trocada(de: String, para: String, porta: Aot)
## Cinemática de script começou/terminou. A APRESENTAÇÃO ouve isto (ver a nota em `_abrir_cena`:
## o fade do `0x46` e a moldura sem HUD são trabalho de quem desenha, não deste arquivo).
signal cena_iniciada(sala: String, func_id: int)
signal cena_terminada(sala: String, func_id: int)

var state: GameState
var room: RoomData
var vm: ScriptVM
var player: Player
var rvd := CameraRVD.Estado.new()
var camera := 0
var trocas := 0
var historico: Array[String] = []

# ═══════════════════════ CINEMÁTICAS DE SCRIPT (cena_r10d.md §6.2) ═══════════════════════
## A cinemática em curso, ou `null`. Enquanto ela vive, o `tick` NÃO lê o pad, NÃO roda o RVD e
## NÃO testa porta/item: quem manda é o script da sala (é o `task_suspend` do motor).
var cena: Cena
var cena_func := -1
## Gatilho `sce 5` que já disparou: bloqueia o re-disparo até o personagem sair da caixa
## (mesma ideia do `_ancora_porta`).
var _ancora_cena: Aot
## DÍVIDAS que a cena deixou registradas (chegada zerada, cena abandonada). O teste lê isto em
## vez de eu fingir que está tudo medido.
var cena_debitos: Array[String] = []

## Cinemáticas de script LIGADAS no jogo, por sala:
##   `entrada` = função que o INIT abre como thread (`0x04 evt_exec`; -1 = nenhuma)
##   `gatilhos` = funções que um AOT `sce 5` pode abrir quando o personagem pisa na caixa
##
## 🟡 **Lista DECLARADA, e curta de propósito.** As duas cenas do `R10D` são as únicas MEDIDAS
## (`docs/decomp/notes/cena_r10d.md`, teste `-- cena`): a de ENTRADA é a **função 7**, aberta
## pelo `04 ff 19 07` da função 5 do init, e a de SAÍDA é a **função 11**, que o AOT `sce 5`
## pede no payload. Medi que existem **135 gatilhos `sce 5` em 58 salas** (varredura com
## `executar(0)` nas 169); ligar todos faria o port rodar funções cujos opcodes ainda não têm
## semântica (§7 do doc) e prenderia o jogador numa cena que talvez nunca termine — algumas
## dessas caixas cobrem a sala inteira (`R30E` tem uma de 24980×24900). Então aqui entram as
## cenas PROVADAS e as outras 134 seguem inertes, exatamente como já estavam.
const CENAS_LIGADAS := {
	"R10D": {"entrada": 7, "gatilhos": [11]},
}
## Rede de segurança: 4000 quadros a 30 Hz ≈ 2 min 13 s. A cena de saída do `R10D` mede 834
## quadros e a de entrada 260, então isto só age se uma thread ficar presa num `while` esperando
## um bit que o port não acende. **Declarado** (é limite de port, não do motor).
const CENA_MAX_QUADROS := 4000

## Cache de salas já carregadas (o RDT é pequeno; o pesado são as imagens, que ficam no AssetIO)
var _cache: Dictionary = {}
## Porta em que o personagem aterrissou: bloqueia o re-disparo até ele sair da caixa.
var _ancora_porta: Aot


func _init(estado: GameState = null) -> void:
	state = estado if estado != null else GameState.new()
	player = Player.new()
	## O player precisa do estado para gastar munição no tiro e da lista de ALVOS para o
	## auto-lock da mira (`0x800445c8` varre os inimigos da sala).
	player.estado = state
	## Tocador de SFX do jogo (o de-para de som está provado; ver `docs/decomp/notes/exe_audio.md`)
	var laco := Engine.get_main_loop()
	if laco != null:
		var g_sfx: Node = (laco as SceneTree).root.get_node_or_null("/root/Game")
		if g_sfx != null:
			player.sfx = g_sfx.get("sfx") as Sfx
			## Banco `cat 0` do PERSONAGEM. O room-loader `0x800493ec` faz isto na carga
			## (`0x800495d0`: `0x8007809c(0, 2)` para a Jill) — sem esta linha o port tocava o
			## `C_00` (banco de MENU), que nem define metade dos ids de jogo.
			if player.sfx != null:
				player.sfx.definir_banco_area()
	player.alvos = func() -> Array:
		var fora: Array = []
		if vm == null:
			return fora
		for sp: Spawn in vm.spawns:
			if sp.pos != Vector3i.ZERO:
				fora.append(sp.pos)
		return fora


func carregar(room_id: String, com_cena := true) -> bool:
	## Carrega a sala, roda o script (que instala os AOT) e prepara colisão/câmera.
	##
	## `com_cena = false` só para o LOAD de save: recarregar a sala não deve reprisar a
	## cinemática de entrada dela.
	var r: RoomData = _cache.get(room_id)
	if r == null:
		r = RoomData.load_room(room_id)
		if not r.erros.is_empty():
			push_error("World: %s" % r.summary())
			return false
		_cache[room_id] = r
	room = r
	if room.colisao != null:
		room.colisao.reset_estado()      # o PS1 relê o RDT do CD; o 0x6e não persiste
	state.stage = r.stage
	state.room = ("0x%s" % room_id.substr(2, 2)).hex_to_int()

	# A colisão da sala nova passa a valer para o personagem.
	#   • `resolver` = o MOVIMENTO (`0x8004af04`): corrige a posição contra a caixa inflada
	#     pelo raio 450, com faixa de nível — é o que anda, desliza e para;
	#   • `trajeto` = o PREDICADO (`0x8004e830`, segmentos): linha de visão / "dá para ir de
	#     A a B" — usado por chegadas de porta e diagnóstico, não pelo andar.
	player.resolver = func(px: int, pz: int, nx: int, nz: int, nivel: int) -> Collision.Resolvido:
		if room.colisao != null:
			return room.colisao.resolver(px, pz, nx, nz, nivel)
		var vazio := Collision.Resolvido.new()
		vazio.x = nx
		vazio.z = nz
		return vazio
	player.walkable = func(x: int, z: int) -> bool:
		return room.trajeto_livre(x - 1, z - 1, x + 1, z + 1, player.pos.y)
	player.trajeto = func(ax: int, az: int, bx: int, bz: int) -> bool:
		return room.trajeto_livre(ax, az, bx, bz, player.pos.y)

	# Script da sala: SÓ A FUNÇÃO 0 roda na carga — como no motor. A f0 é o init, e ela mesma
	# faz `gosub` (0x19) condicionado a flags para as funções de setup do cenário corrente
	# (medido: 259 AOTs na f0 e ~493 gosubs dela para f2..f9, onde moram os outros 2546).
	#
	# A versão anterior executava TODAS as funções — funções de EVENTO inclusive. Foi inócuo
	# enquanto o 0x6e era NOP; quando ele passou a escrever na colisão, cada sala carregava com
	# os colliders no estado da ÚLTIMA função executada (portões fantasma, paredes invisíveis) —
	# 287 das 348 chamadas 0x6e estão em funções de evento. Era o "não consigo andar em nenhuma
	# sala" relatado.
	vm = ScriptVM.new()
	if vm.carregar_sala(room_id):
		vm.modo = ScriptVM.Modo.EXECUCAO
		vm.state = state
		vm.colisao = room.colisao
		vm.executar(0)
		if vm.colliders_mudados > 0:
			print("[world] %s: init mudou %d collider(s) (opcode 0x6e)" % [
				room_id, vm.colliders_mudados])
	historico.append(room_id)
	# O BANCO 4 é o de RASCUNHO da sala — as threads de uma cena se sincronizam por ele (o `0x81`
	# acende um bit dele na chegada do ator, `cena_r10d.md` §3.2) e o motor o ZERA na carga:
	# `0x80052350  sw $zero, 0x7888($s0)` (`gs+0x7888` = `0x800d1fc0` = entrada 4 da tabela de
	# bancos `0x8009e3f8`). Sem isto, um bit aceso numa cena anterior soltaria o `while (não
	# flag)` da próxima antes da hora.
	for bit in GameState.BITS_PER_BANK:
		state.flag_set(Cena.BANCO_RASCUNHO, bit, false)
	_fechar_cena(false)
	player.degraus = _degraus_da_sala()
	if player.degraus.size() > 0:
		print("[world] %s: %d degrau(s) de subir/descer na colisão" % [
			room_id, player.degraus.size()])
	if com_cena:
		_abrir_cena_de_entrada()
	return true


# ═══════════════ DEGRAUS: subir/descer é AÇÃO DO JOGADOR, e sai da COLISÃO ═══════════════
#
# ⚠ **Isto CORRIGE a conclusão de `port/script_vm/subir.gd` §5 e de `cena_r10d.md` §6** no que
# importa para o jogador. As duas afirmações continuam verdadeiras — *nenhum objeto `0x7f` do
# `R10D` é escalável* (os 3 têm `be_flg = 0x6001`, e **medi que nada mexe nisso em runtime**: são
# declarados UMA vez na função 4 e nenhuma das 49 funções escreve o membro `0x00` de um work que
# não seja o player) — mas **a conclusão que se tirou delas estava errada**: o que a Jill escala
# no `R10D` **não é um objeto de script, é a GEOMETRIA DE COLISÃO**, e por isso o agregador de
# `om` (`0x80036570`) nunca ia achá-la.
#
# O que o dado diz (medido em `port/dev/_tmp_r10d*.gd`, ver `cena_r10d.md` §10):
#
#   #7  forma 7  x[-6368..-4129] z[-15823..-10197]  base_y=0      topo=-1800  nível 0
#   #9  forma 8  x[-4128..-3328] z[-15823..-10197]  base_y=-1800  topo=-3600  nível 1
#   #8  forma 8  x[-7169..-6369] z[-15859..-10233]  base_y=-1800  topo=-3600  nível 1
#
# Os três se encaixam sem folga (`-7169..-6369 | -6368..-4129 | -4128..-3328`) e atravessam a
# viela INTEIRA em Z. Consequências, todas verificadas com o resolver do port:
#   • `#7` é uma PLATAFORMA de um nível (`topo == base_y - 1800`) e o `floor_height` do port já
#     devolve `-1800` dentro dela: o TOPO dela é piso do nível 1;
#   • a faixa de nível (`+0x0C..+0x0D`, ARD.md §3.8.1) faz `#7` colidir **só com quem está no
#     nível 0** — quem está em cima anda por ela;
#   • **a viela está SELADA no nível 0**: BFS na régua do resolver, do spawn e da posição da
#     captura do dono, alcança 2265 nós e **NÃO chega** na caixa do gatilho `sce 5`;
#   • as duas `forma 8` são os FLANCOS, ativas só no nível 1, e a de OESTE (`x[-7169..-6369]`)
#     cai **dentro** da caixa do gatilho (`x[-8585..-5285] z[-15000..-11300]`).
#
# ➜ O único caminho é **subir no nível 0 pelo flanco leste, atravessar o topo e DESCER no flanco
#   oeste — e a descida cai dentro da caixa**, que é exatamente o que o dono descreve.
#
# 🟡 **HIPÓTESE (não provada no EXE), com a evidência que a sustenta:** a assinatura
# "plataforma de um nível + registro `forma 8` encostado no nível de cima" é o marcador de
# degrau escalável. `forma 8` **nunca colide no predicado** (`0x8004f02c`: `jr $ra; move
# $v0,$zero`) e **não dá piso** (`floor_height` não a trata), mas responde no resolver junto de
# 1/5/7 (`0x8004c960`) — ou seja é um bloco que existe só para o MOVIMENTO. São **25 registros
# `forma 8` no jogo, todos com `bits = 0xfe48`**, e a assinatura completa aparece em **28
# registros / 14 salas** (contra 224 plataformas de um nível em 69 salas): `R10D`, `R101`/`R601`,
# `R106`/`R121`/`R621`, `R108`/`R122`/`R622`, `R20B`/`R70B`, `R40D`, **`R504`** e **`R510`** — e
# `R510 → R504` é justamente a porta que `door_handler.md` rotulou *one_way_fall, spawn
# scripted*. O que NÃO medi: o sítio do EXE que liga a rotina 9 por colisão (o caminho por `om`
# está provado em `subir.gd` §2 e não é este).


func _degraus_da_sala() -> Array[Dictionary]:
	## Degraus da sala corrente: `{caixa, y_topo, y_base}` em unidades PS1.
	var saida: Array[Dictionary] = []
	if room == null or room.colisao == null:
		return saida
	var f8: Array[Collision.Rect] = []
	for r: Collision.Rect in room.colisao.rects:
		if r.forma == 8:
			f8.append(r)
	if f8.is_empty():
		return saida
	for r: Collision.Rect in room.colisao.rects:
		if r.topo != r.base_y - Collision.ALTURA_POR_NIVEL:
			continue                          ## não é plataforma de UM nível
		if r.forma != 1 and r.forma != 7 and r.forma != 5:
			continue
		if r.forma == 1 and (r.mask & 0x0F00) != 0:
			continue                          ## parede com arestas: o topo não é piso
		var tem := false
		for q: Collision.Rect in f8:
			if q.base_y != r.topo:
				continue                      ## o flanco tem de estar no nível de CIMA
			var toca_x := absi(q.x1 - r.x0) <= 5 or absi(q.x0 - r.x1) <= 5
			var toca_z := absi(q.z1 - r.z0) <= 5 or absi(q.z0 - r.z1) <= 5
			var sobre_x := mini(q.x1, r.x1) - maxi(q.x0, r.x0) > 0
			var sobre_z := mini(q.z1, r.z1) - maxi(q.z0, r.z0) > 0
			if (toca_x and sobre_z) or (toca_z and sobre_x):
				tem = true
				break
		if not tem:
			continue
		saida.append({"caixa": Rect2i(r.x0, r.z0, r.x1 - r.x0, r.z1 - r.z0),
			"y_topo": r.topo, "y_base": r.base_y})
	return saida


# ═════════════════════════ as três linhas da §6.2 de cena_r10d.md ═════════════════════════
# Era o que faltava para a Jill SAIR do R10D: a sala tem UMA porta e ela é impossível de tocar
# (caixa `(0,0,0,0)`) — quem a dispara é o opcode `0x66` no fim da **função 11**, a cinemática de
# saída, que o AOT `sce 5` abre quando o personagem pisa na caixa a oeste.


func _abrir_cena_de_entrada() -> void:
	## A cena de ENTRADA não tem gatilho: o INIT da sala a abre como thread. Prova, opcode por
	## opcode (`cena_r10d.md` §2): `func 0` faz `19 02` → `func 2` faz `19 05` → `func 5` começa
	## com **`04 ff 19 07`** = `evt_exec(slot 0xff, função 7)`. O port não roda `0x04` no modo de
	## CARGA (só a `Cena` abre thread), então quem sabe disso é a tabela `CENAS_LIGADAS`.
	var e: Dictionary = CENAS_LIGADAS.get(room.room_id, {})
	var fid := int(e.get("entrada", -1))
	if fid >= 0:
		_abrir_cena(fid, "thread do init (func 5: `04 ff 19 07`)")


## `nFloor = 0x80` no `+4` do AOT: "qualquer andar" (ver `Aot.floor_id`).
const ANDAR_QUALQUER := 0x80


func _gatilho_no_andar() -> Aot:
	## O gatilho `sce 5` que contém o personagem **E vale no andar dele**.
	##
	## ⭐ O `nFloor` (`+4` do `0x63`) é o ANDAR EXIGIDO, e o port o ignorava. No `R10D` ele é
	## **0** (`63 01 05 41 00 00 …`), isto é **só no nível 0** — e é isso que fecha o relato do
	## dono: andando EM CIMA da plataforma (nível 1) a caixa não dispara; ela dispara quando a
	## Jill **DESCE** no flanco oeste, que cai dentro dela. Sem este filtro a cena abria antes,
	## com o corpo ainda no telhado do obstáculo (medido: disparava em `x = -5300, y = -1800`).
	for a: Aot in vm.aots_de_sce(Aot.SCE_EVENTO):
		if not a.contem(player.pos.x, player.pos.z):
			continue
		if a.floor_id != ANDAR_QUALQUER and a.floor_id != player.nivel():
			continue
		return a
	return null


func _procurar_gatilho_de_cena() -> void:
	## Um quadro de busca de gatilho: primeiro AOT `sce 5` ATIVO que contém o personagem. O
	## handler `0x800512bc` só faz `evt_exec` com o payload — "pisar na caixa" **é** "abrir a
	## thread" (`Aot.evento_func()`).
	if vm == null or room == null:
		return
	var g := _gatilho_no_andar()
	if g == null:
		_ancora_cena = null
		return
	if g == _ancora_cena:
		return                                   ## ainda dentro da caixa que já disparou
	_ancora_cena = g
	var fid := g.evento_func()
	var ligadas: Array = (CENAS_LIGADAS.get(room.room_id, {}) as Dictionary).get("gatilhos", [])
	if not ligadas.has(fid):
		print("[world] %s: gatilho sce 5 (AOT %d) pede a função %d — cena NÃO ligada (não medida)"
			% [room.room_id, g.id, fid])
		return
	_abrir_cena(fid, "gatilho sce 5 (AOT %d)" % g.id)


func _abrir_cena(func_id: int, motivo: String) -> bool:
	## Abre a cinemática e entrega o corpo a ela. O que ainda é da APRESENTAÇÃO e **não** dá para
	## fazer aqui (registrado em vez de editado, `port/present/screen.gd` não é meu):
	##   • o FADE do `0x46` (`cena.fade_ativo` traz `abr`, `c0`, `c1`, `T` e o `t` corrente) —
	##     é o relâmpago da rua na entrada e o escurecer de 48 ticks antes da porta;
	##   • esconder o HUD/menu enquanto `cena_iniciada`..`cena_terminada`.
	## A CÂMERA já funciona sem tocar em nada lá: o `screen.gd` compara `mundo.camera` com a
	## câmera montada todo tick, e este arquivo passa a escrever nela o `cut_chg` da cena.
	if vm == null:
		return false
	var c := Cena.new()
	if not c.iniciar(vm, func_id, state):
		push_warning("World: cena %s função %d não iniciou" % [room.room_id, func_id])
		return false
	## Quem ANDA é o `player.gd` (estado CENA): a `Cena` só simula o deslocamento do `0x81`
	## quando ninguém chama `chegou()` — ver `Cena.VELOCIDADE_DECLARADA`.
	c.simular_movimento = false
	c.por_ator(1, 0, player.pos, player.facing)
	cena = c
	cena_func = func_id
	player.entrar_em_cena(c)
	print("[world] %s: CENA função %d ligada — %s" % [room.room_id, func_id, motivo])
	cena_iniciada.emit(room.room_id, func_id)
	return true


func _fechar_cena(avisar := true) -> void:
	var fid := cena_func
	var viva := cena != null
	if viva and player != null and player.cena_ir_ignorados > 0:
		## O `0x81` com destino (0,0) — ver a nota em `Player._consumir_eventos_da_cena`.
		cena_debitos.append(
			"%s: cena função %d tem %d `0x81` com destino (0,0) — rotina do 0x81 não medida"
			% [room.room_id if room != null else "?", fid, player.cena_ir_ignorados])
	cena = null
	cena_func = -1
	_ancora_cena = null
	if player != null:
		## Fim da cena = `player+4` volta a `1`. É o que a função 37 faz (`4d 02 07 00` e
		## `4d 01 1c 00`, apagando os dois bits que a cena acendeu).
		player.sair_da_cena()
	if viva and avisar:
		cena_terminada.emit(room.room_id if room != null else "", fid)


func _quadro_de_cena(pad: Pad) -> void:
	## Um quadro de cinemática: a `Cena` roda as threads do script (tempo, laços, câmera, fade,
	## ator) e o `player.gd`, no estado `CENA`, consome os eventos `anim`/`ir` e devolve a chegada
	## por `cena.chegou(bit)`.
	## O corpo do port entra na cena ANTES das threads: o script mexe na posição de forma
	## relativa (`player+0x34 += 70`), então ele tem de ler o valor corrente, não o do quadro em
	## que a cena foi aberta.
	player.sincronizar_com_a_cena()
	cena.quadro()
	player.tick(pad)                             ## em CENA o pad é ignorado (a cena manda)
	# O Y continua sendo rederivado do piso todo quadro, como no jogo normal (`0x80033b88`).
	if room.colisao != null:
		player.pos.y = room.colisao.floor_height(player.pos.x, player.pos.z, player.pos.y)
	# `0x50 cut_chg` PRENDE a câmera (`gs+0x77f4 |= 0x80`, `0x800548f0`): durante a cena o RVD
	# não decide nada. Ao terminar, a câmera fica onde a cena deixou — no `R10D` a última é a
	# `cut_chg 0`, exatamente a que o port já usa ao entrar na sala.
	if cena.camera >= 0 and cena.camera < room.cameras.size():
		camera = cena.camera
		rvd.camera = camera
	# ★ A PORTA ROTEIRIZADA: `0x66 sce_aot_exec` disparou o AOT de porta. Sai pelo caminho normal.
	var p := cena.porta_pedida()
	if p != null:
		if bool(cena.troca_de_sala.get("chegada_zerada", false)):
			cena_debitos.append("%s: porta roteirizada (AOT %d) com chegada ZERADA no dado"
				% [room.room_id, p.id])
		_fechar_cena()
		if not atravessar(p):
			push_warning("World: a cena pediu a porta %d mas o destino não carregou" % p.id)
		return
	if not cena.viva():
		print("[world] %s: cena função %d terminou em %d quadros" % [
			room.room_id, cena_func, cena.quadro_atual])
		_fechar_cena()
		return
	if cena.quadro_atual >= CENA_MAX_QUADROS:
		cena_debitos.append("%s: cena função %d abandonada em %d quadros (rede de segurança)"
			% [room.room_id, cena_func, cena.quadro_atual])
		push_warning(cena_debitos[cena_debitos.size() - 1])
		_fechar_cena()


## Raio de busca (unidades PS1) ao desencravar uma chegada que cai dentro de colisão.
const BUSCA_CHEGADA := 3000
const BUSCA_PASSO := 100


func aplicar_chegada(porta: Aot) -> void:
	## `door_handler 0x800248e4`: grava posição/direção de chegada e a câmera do corte.
	##
	## ── O `y` da chegada é o NÍVEL do chão, e é usado como está (achado de 2026-07-31) ──
	## A nota antiga dizia que esse `y` "é outra referência, não a posição do pé", porque só 51%
	## das chegadas caíam fora de colisão e o valor não batia com o -258 herdado do protótipo.
	## As duas coisas estavam erradas pelo mesmo motivo: a colisão era lida como caixa cheia.
	## Medido agora: os `to_y` são exatamente os níveis do collider (0, -1800, -3600, -5400…,
	## múltiplos de 1800 — 293 chegadas em 0), e com o modelo de SEGMENTOS as **453 chegadas
	## conseguem dar o primeiro passo**. Ou seja: `to_y` é o piso, e o -258 do protótipo é que
	## levantava a Jill do chão (o "flutuando" relatado).
	if porta == null:
		return
	var emp: Dictionary = {}
	if porta.to_pos != Vector3i.ZERO:
		player.pos = _desencravar(porta.to_pos)
	elif porta.box.size == Vector2i.ZERO:
		# ── PORTA ROTEIRIZADA com chegada ZERADA: chegada EMPRESTADA e etiquetada ──
		# Caixa `(0,0,0,0)` **e** chegada `(0,0,0)` é a assinatura da porta que só o script
		# dispara (`0x66`, `cena_r10d.md` §4): 1 porta no jogo inteiro, `R10D → R101`. Aqui a
		# posição de chegada NÃO existe no dado, e `(0,0,0)` não é ponto válido no `R101`.
		# 🟡 O mecanismo real **não foi medido** — o candidato é o GRUPO DO RVD
		# (`descriptor+0xb` → `gs+0x2495`, §4.2 do doc) e ninguém decodificou o RVD desse lado.
		# Para o jogo não travar sem inventar coordenada, o port EMPRESTA a chegada de outra
		# porta que entra na MESMA sala: é um ponto **medido** (está em `data/room_graph.json`,
		# gerado do SCD), só não é o desta porta. Fica registrado em `cena_debitos`.
		emp = _chegada_emprestada(porta.to_room_id())
		if emp.is_empty():
			player.pos = _desencravar(player.pos)
		else:
			player.pos = _desencravar(emp["pos"])
			cena_debitos.append(
				"chegada DECLARADA em %s: emprestada da porta %s (%s) — a desta porta é (0,0,0)"
				% [porta.to_room_id(), emp["src"], emp["pos"]])
			push_warning("World: %s" % cena_debitos[cena_debitos.size() - 1])
	else:
		# porta "mantém posição" (to_pos zerado — elevador/escada no mesmo ponto): a posição
		# atual pode ser ilegal na sala NOVA; desencrava do mesmo jeito
		player.pos = _desencravar(player.pos)
	player.facing = PS1Math.wrap_angle(int(emp["facing"]) if emp.has("facing")
		else porta.to_facing)
	## Com a chegada emprestada, a CÂMERA vem emprestada junto (a `to_cut` desta porta é 0, que é
	## o valor de campo zerado — mostrar a câmera 0 com o corpo na área de outra câmera deixaria a
	## Jill fora de quadro). No quadro seguinte o RVD reassume normalmente.
	var cut: int = int(emp["cam"]) if emp.has("cam") else porta.to_cut
	camera = cut if cut >= 0 and cut < room.cameras.size() else 0
	rvd = CameraRVD.Estado.new()
	rvd.camera = camera
	# Carga de sala também ancora/exclui a supressora da câmera de chegada (`0x80049728`).
	CameraRVD.matar_supressora(room, rvd, camera)
	# O grupo de câmera vem do descriptor da porta (+0xb). Sem isso, as zonas RVD de grupo
	# específico (0..31) são todas rejeitadas e a câmera simplesmente não troca — foi o que o
	# usuário viu na R101, cujas zonas da câmera 0 usam grupos 0x01 e 0x04.
	rvd.grupo = porta.to_grupo


## Grafo de portas do jogo (`tools/room_graph_build.py` + `tools/scd_door_dest.py`): 453 arestas
## com caixa, chegada e câmera. É de onde sai a chegada EMPRESTADA da porta roteirizada.
static var _grafo: Variant = null


static func _chegada_emprestada(destino: String) -> Dictionary:
	## Chegada MEDIDA de outra porta que entra em `destino` — a de menor sala de origem, para ser
	## determinístico. 🟡 **DECLARADA como substituta**: é um ponto que o jogo comprovadamente usa
	## para entrar nessa sala, mas **não é** a chegada da porta roteirizada (que vem `(0,0,0)`).
	## Devolve `{}` quando não há de quem emprestar.
	if destino == "":
		return {}
	if _grafo == null:
		_grafo = AssetIO.json("room_graph.json")
	if not (_grafo is Dictionary):
		return {}
	var candidatas: Array[Dictionary] = []
	for e: Variant in (_grafo as Dictionary).get("edges", []):
		if not (e is Dictionary):
			continue
		var E: Dictionary = e
		if str(E.get("to_room_id", "")) != destino:
			continue
		var a: Dictionary = E.get("arrival", {})
		if int(a.get("x", 0)) == 0 and int(a.get("z", 0)) == 0:
			continue                             ## outra chegada zerada não serve de referência
		candidatas.append({
			"src": str(E.get("src", "")),
			"pos": Vector3i(int(a.get("x", 0)), int(a.get("y", 0)), int(a.get("z", 0))),
			"facing": int(a.get("facing", 0)),
			"cam": int(E.get("to_camera", 0))})
	if candidatas.is_empty():
		return {}
	candidatas.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return str(x["src"]) < str(y["src"]))
	return candidatas[0]


func _desencravar(p: Vector3i) -> Vector3i:
	## A chegada tem de ser legal para o RESOLVER (o movimento), não para o predicado.
	##
	## Medido: 76 das 453 chegadas caem DENTRO de alguma caixa inflada pelo raio 450, e em 34
	## delas o escape passa do teto (flag 0x100) — o resolver rejeita TODO movimento e o
	## personagem nasce preso ("problema de colisão em diversas cenas": era ao entrar por
	## certas portas). A versão anterior validava com `trajeto_livre` (segmentos, sem raio),
	## que dizia "está tudo bem".
	##
	## Ordem: (1) se o resolver parado só EMPURRA, aceita a posição empurrada (é o que o motor
	## faz no 1º frame); (2) se REJEITA, procura em anéis o ponto mais próximo onde o resolver
	## parado fica limpo.
	if room.colisao == null:
		return p
	var nivel := p.y / -Collision.ALTURA_POR_NIVEL
	var r0 := room.colisao.resolver(p.x, p.z, p.x, p.z, nivel)
	if not r0.rejeitado:
		if r0.empurrado:
			return Vector3i(r0.x, p.y, r0.z)
		return p
	var raio := BUSCA_PASSO
	while raio <= BUSCA_CHEGADA:
		# 16 direções por anel: suficiente e determinístico (nada de aleatório)
		for dir_i in 16:
			var ang := dir_i * 256                    # 16 × 22,5° em unidades de 12 bits
			var off := PS1Math.rotate_xz(0, raio, ang)
			var q := Vector3i(p.x + off.x, p.y, p.z + off.y)
			var rq := room.colisao.resolver(q.x, q.z, q.x, q.z, nivel)
			if not rq.rejeitado and not rq.empurrado:
				push_warning("World: chegada %s encravada em %s; empurrada %d un para %s"
					% [room.room_id, p, raio, q])
				return q
		raio += BUSCA_PASSO
	push_warning("World: chegada %s em %s encravada e sem saída em %d un"
		% [room.room_id, p, BUSCA_CHEGADA])
	return p


func _chegada_livre(p: Vector3i) -> bool:
	## "Consegue existir e se mexer aqui?" — na régua do RESOLVER.
	if room.colisao == null:
		return true
	var nivel := p.y / -Collision.ALTURA_POR_NIVEL
	return not room.colisao.resolver(p.x, p.z, p.x, p.z, nivel).rejeitado


func chegada_encravada(porta: Aot) -> bool:
	## Diagnóstico: a chegada desta porta precisou ser desencravada?
	if porta == null or porta.to_pos == Vector3i.ZERO:
		return false
	return not _chegada_livre(porta.to_pos)


func porta_sob_o_player() -> Aot:
	## Teste per-frame: o personagem está dentro de um AOT de porta?
	##
	## ÂNCORA (mesma ideia do RVD): ao chegar numa sala, o personagem aterrissa **dentro** do
	## gatilho da porta correspondente do outro lado. Sem memória, o AOT dispara no tick
	## seguinte e a troca fica em loop — de fora parece que "o controle não funciona", porque a
	## personagem é teleportada a cada frame independentemente do input. Então a porta que
	## acabou de ser usada só volta a valer depois que o personagem SAIR da caixa dela.
	if vm == null:
		return null
	if _ancora_porta != null:
		if _ancora_porta.contem(player.pos.x, player.pos.z):
			return null                       ## ainda dentro do gatilho de chegada: ignora
		_ancora_porta = null                  ## saiu: a porta volta a valer
	# ALCANCE: contato do corpo (caixa inflada pelo raio 450) OU sonda À FRENTE até 600 —
	# as constantes do código de interação do player (`0x80045fc0..0x80046040`). MEDIDO no
	# dado por que as duas são necessárias: as caixas de porta ficam tipicamente a 454–551 un
	# do ponto onde a colisão te para (R113: 492/551 · R115: 454/468) — 4 a 100 un além do
	# contato. A sonda é DIRECIONAL (só o que está na tua frente), então não "abre de longe".
	var a := vm.aot_em_raio(player.pos.x, player.pos.z, Collision.RAIO_ATOR)
	if a != null and a.is_porta():
		return a
	for dist: int in [200, 400, 600]:
		var px: int = player.pos.x + ((PS1Math.rsin(player.facing) * dist) >> PS1Math.SHIFT)
		var pz: int = player.pos.z + ((-PS1Math.rcos(player.facing) * dist) >> PS1Math.SHIFT)
		var s := vm.aot_em(px, pz)
		if s != null and s.is_porta():
			return s
	return null


func atravessar(porta: Aot) -> bool:
	## Executa a troca de sala. Devolve false se o destino não existir.
	if porta == null:
		return false
	var destino := porta.to_room_id()
	if destino == "":
		return false
	var de := room.room_id if room != null else ""
	## SOM DA PORTA, antes de trocar a sala: o banco vem do `DOORxx.DOn` daquela porta
	## (`cat 4`, banco embutido — é o que dá porta de madeira != portão de metal). O índice
	## `Dtex_Type` é campo ESTÁTICO do SCD e está em `data/porta_banco.json` por sala/AOT.
	## O id é MEDIDO (`0x800161c4`: `a0 = 0x401` = cat 4 / id 1); que o momento seja "abrir" e
	## não "fechar" segue DECLARADO (ver `Sfx.porta_abrir`).
	_som_da_porta(de, porta)
	if not carregar(destino):
		return false
	aplicar_chegada(porta)
	trocas += 1
	# ancora: qualquer porta da sala nova que contenha o ponto de chegada
	_ancora_porta = null
	if vm != null:
		for p2: Aot in vm.portas():
			if p2.contem(player.pos.x, player.pos.z):
				_ancora_porta = p2
				break
	sala_trocada.emit(de, destino, porta)
	return true


func _som_da_porta(sala: String, porta: Aot) -> void:
	## Seleciona o banco `cat 4` da porta e toca o som. `sala` é a sala de ORIGEM (o AOT que
	## disparou é dela). Sem `Dtex_Type` para o par sala/AOT, cai no banco padrão do
	## `re3_se.json` em vez de ficar mudo.
	if player == null or player.sfx == null or porta == null:
		return
	if not player.sfx.usar_porta_da_sala(sala, porta.id):
		player.sfx.definir_banco_porta("")          ## banco padrão do re3_se.json
	player.sfx.porta_abrir()


## Item da FACA — é o único par item->arma que o port tem provado (o `Player.quadro_do_corte()`
## já o usa para escolher a linha `w-1 = 0` da tabela de timing `0x8009cf28`).
const ITEM_FACA := 0x01


func _banco_da_arma(item_id: int) -> void:
	## Diz ao `Sfx` qual banco `cat 1` (`A_{w}`) está carregado — é dele que sai o ESTOURO da arma
	## (`cat 1 / id 0`, ver `Sfx.tiro`). O motor faz isto no equipar (`0x80043eb4` →
	## `0x8007809c(1, lbu player+0x46)`).
	##
	## O de-para completo **item -> `w`** continua NÃO MEDIDO (`tools/exe_aim_shoot.py`). O que
	## está amarrado é a mesma aproximação DECLARADA que o `Player.quadro_do_corte()` já usa, e que
	## as tabelas do EXE confirmam nos dois extremos: as tabelas por arma são indexadas por
	## **`w - 1`** (`0x8003ea1c` para a de funções `0x8009ced8`, `0x8003e454` para a de timing
	## `0x8009cf28`, stride 3), a linha 0 (`w = 1`) é a que **não** pede SE de tiro e o `A_01` é o
	## único dos 20 bancos `A_` sem o id 0 → **`w = 1` é a FACA, `w = 2` é a pistola**.
	if player == null or player.sfx == null:
		return
	if item_id == ITEM_FACA:
		player.sfx.definir_banco_arma(Sfx.ARMA_FACA)
	elif Itens.categoria(item_id) == Itens.CAT_ARMA:
		player.sfx.definir_banco_arma(Sfx.ARMA_PADRAO)
	else:
		player.sfx.definir_banco_arma(0)             ## sem arma: sem banco de `cat 1`


signal item_pego(item_id: int, qtd: int)

## Última ação tentada, para o HUD dizer o que aconteceu.
var ultima_acao := ""


func tick(pad: Pad) -> void:
	## Um passo do mundo: personagem → câmera (RVD) → AÇÃO (porta/item).
	##
	## Porta e item exigem o BOTÃO DE AÇÃO, como no RE3 — encostar não basta. Antes eu
	## atravessava só por estar dentro do AOT, o que também causava troca em loop.
	## `player+0x46` = ARMA EQUIPADA, e a mira exige `!= 0` (`0x80039714`: `lbu v0,0x46`). O port
	## guarda aqui o **item id** da arma equipada — o índice `w` do EXE não tem tabela achada
	## (ver `tools/exe_aim_shoot.py`), e para o teste de "tem arma" o id serve igual.
	##
	## ── CINEMÁTICA DE SCRIPT primeiro (as três linhas da §6.2 de `cena_r10d.md`) ──
	## Enquanto uma cena vive, o mundo é dela: nada de pad, nada de RVD, nada de porta/item. É o
	## equivalente ao `task_suspend` que o motor faz com a task do jogo.
	if cena == null:
		_procurar_gatilho_de_cena()
	if cena != null:
		_quadro_de_cena(pad)
		return
	var eq := state.equipped_item_id()
	player.equipped_weapon = eq if Itens.categoria(eq) == Itens.CAT_ARMA else 0
	_banco_da_arma(eq)
	player.dificuldade = state.dificuldade as Player.Dificuldade
	player.tick(pad)
	# O Y NÃO é integrado: é rederivado do piso todo frame (`0x80033b88` → `floor_height`
	# `0x8004d720` → grava em `entity+0x38`). É o que faz descer escada/rampa — sem isto a
	# Jill descia flutuando no Y do andar de cima (relato do usuário).
	# ⚠ EXCEÇÃO: durante a rotina 9 (subir/descer degrau) quem manda no Y é a própria ação — o
	# corpo está NO AR entre dois níveis e o piso puxaria de volta a cada quadro.
	if room.colisao != null and not player.subindo():
		player.pos.y = room.colisao.floor_height(player.pos.x, player.pos.z, player.pos.y)
	# O "grupo" das zonas RVD (`gs+0x2495`) é o NÍVEL DO PISO do player: `gs+0x2495` =
	# `0x800CCBCD` = player`+0x09`, que o passe de piso grava com `-Y/1800` todo frame. O byte
	# `+0xb` da porta é só o valor INICIAL (o nível da chegada). Congelar o grupo no valor da
	# porta era o que impedia a câmera de trocar ao descer a escada da R101 (as zonas do andar
	# de baixo têm grupo = o nível de lá).
	rvd.grupo = player.nivel()
	camera = CameraRVD.update(room, rvd, player.pos.x, player.pos.z)
	## MIRANDO, o botão de ação é o GATILHO (rotina 7 sub 3), não o "usar": sem esta guarda o
	## mesmo clique atirava e abria a porta/pegava item no mesmo quadro.
	if pad.just_pressed(Pad.ACAO) and player.acao != Player.Acao.MIRANDO:
		usar()


func usar() -> bool:
	## Botão de ação: pega item se houver, senão atravessa porta se houver.
	var it := pegar_item_sob_o_player()
	if it != null:
		ultima_acao = "pegou item 0x%02x x%d" % [it.item_id, maxi(1, it.item_qtd)]
		item_pego.emit(it.item_id, maxi(1, it.item_qtd))
		return true
	var p := porta_sob_o_player()
	if p != null:
		var destino := p.to_room_id()
		if atravessar(p):
			ultima_acao = "porta -> %s" % destino
			return true
		ultima_acao = "porta sem destino válido"
		return false
	ultima_acao = "nada aqui"
	return false


func salvar(caminho: String) -> Error:
	## Save (P3-05): estado global + onde o jogador está. O conteúdo é o que importa — o
	## formato é do port (não é preciso ser compatível com o `.sav` do PS1).
	state.save_count += 1                  # conta ANTES de serializar, senão o save guarda o valor antigo
	var d := state.to_dict()
	d["_mundo"] = {
		"sala": room.room_id if room != null else "",
		"pos": [player.pos.x, player.pos.y, player.pos.z],
		"facing": player.facing,
		"camera": camera,
		"grupo": rvd.grupo,
		"hp": player.hp,
		"arma": player.equipped_weapon,
		"trocas": trocas,
		"historico": historico.duplicate(),
	}
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d))
	return OK


func carregar_save(caminho: String) -> bool:
	if not FileAccess.file_exists(caminho):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(caminho))
	if not (raw is Dictionary):
		return false
	var d: Dictionary = raw
	if not state.from_dict(d):
		return false
	var m: Variant = d.get("_mundo")
	if not (m is Dictionary):
		return false
	var M: Dictionary = m
	var sala := str(M.get("sala", ""))
	if sala == "" or not carregar(sala, false):     ## load de save não reprisa a cinemática
		return false
	var p: Array = M.get("pos", [0, 0, 0])
	if p.size() >= 3:
		player.pos = Vector3i(int(p[0]), int(p[1]), int(p[2]))
	player.facing = int(M.get("facing", 0))
	player.hp = int(M.get("hp", 200))
	player.equipped_weapon = int(M.get("arma", 0))
	camera = int(M.get("camera", 0))
	rvd = CameraRVD.Estado.new()
	rvd.camera = camera
	rvd.grupo = int(M.get("grupo", CameraRVD.GRUPO_GLOBAL))
	trocas = int(M.get("trocas", 0))
	_ancora_porta = null
	return true


## Distância do PONTO DE SONDA à frente do ator, no teste de AOT de ação (`0x800505ac`):
## o motor não testa a posição do personagem, testa `pos + frente * 620`. É por isso que
## se pega o item de frente e não em cima dele — e é 620, não o raio 450 do corpo.
const SONDA_ACAO := 620


func pegar_item_sob_o_player() -> Aot:
	## Item no chão (P2-07): entra no inventário e o AOT é desativado.
	##
	## ALCANCE = o PONTO DE SONDA do motor (620 unidades à frente), testado dentro do quad
	## (`0x68`) ou do rect (`0x67`). O `SAT 0x31` dos itens tem o bit 4, e o passe que carrega
	## esse bit (`aot_check(player, 1, 16)`) só roda quando o bit 23 de `0x800d1f2c` está aceso
	## — o pedido de AÇÃO. Ou seja: item exige botão, olhando para ele. (Antes eu inflava a
	## caixa pelo raio do corpo, o que pegava item de costas e de lado.)
	if vm == null:
		return null
	var sonda := player.pos + Vector3i(
		PS1Math.rsin(player.facing) * SONDA_ACAO >> PS1Math.SHIFT, 0,
		-PS1Math.rcos(player.facing) * SONDA_ACAO >> PS1Math.SHIFT)
	for a: Aot in vm.itens():
		if a.contem(sonda.x, sonda.z) or a.contem(player.pos.x, player.pos.z):
			if state.add_item(a.item_id, maxi(1, a.item_qtd)) >= 0:
				## PEGAR um documento já o coloca no arquivo (o jogo abre a página na hora)
				state.marcar_arquivo_lido(a.item_id)
				a.ativo = false
				_marcar_pego(a)
				return a
			return null                      ## inventário cheio: o item FICA no chão
	return null


func _marcar_pego(a: Aot) -> void:
	## O BIT vem do dado: `payload+4` do `0x67`/`0x68` — o mesmo que os handlers
	## `0x800574f4`/`0x800576c4` passam a `SetBit 0x800788dc` ao pegar e a `TestBit 0x80078930`
	## ao reinstalar o AOT. O banco é o 7, o MESMO do `CHECK 0x4c` (ver GameState.BANCO_ITENS).
	## (Antes eu usava um bit inventado a partir de sala+aot. Os bits reais medidos nos 14
	## itens do jogo vão de 11 a 125, e a MESMA erva na R104 e na R11F compartilha o bit —
	## as duas salas são o mesmo cenário em cenários diferentes, e o jogo lembra nas duas.)
	if a.item_flag > 0:
		state.flag_set(GameState.BANCO_ITENS, a.item_flag, true)


func itens_no_chao() -> Array[Aot]:
	## Itens que ainda estão no chão desta sala: os AOT de item ativos que não foram pegos.
	## É o que a apresentação usa para colocar os objetos na cena.
	var saida: Array[Aot] = []
	if vm == null:
		return saida
	for a: Aot in vm.itens():
		if not a.ativo:
			continue
		if a.item_flag > 0 and state.flag_get(GameState.BANCO_ITENS, a.item_flag):
			a.ativo = false
			continue
		saida.append(a)
	return saida


func objeto_do_item(a: Aot) -> ObjetoSala:
	## O 3D do item: o slot `om` do payload aponta para o objeto instalado pelo `0x7f`, que é
	## quem tem POSIÇÃO e ROTAÇÃO de verdade (a área de coleta é só a área). `null` quando o
	## item não tem modelo (`om >= 32`) ou quando o `0x7f` do slot não rodou nesta execução.
	if vm == null or not a.tem_modelo():
		return null
	if not vm.objetos.has(a.item_om):
		return null
	return vm.objetos[a.item_om] as ObjetoSala


func resumo() -> String:
	return "%s cam %d · player %s facing %d · %d AOTs (%d portas) · %d trocas" % [
		room.room_id if room else "-", camera, player.pos, player.facing,
		vm.aots.size() if vm else 0, vm.portas().size() if vm else 0, trocas]
