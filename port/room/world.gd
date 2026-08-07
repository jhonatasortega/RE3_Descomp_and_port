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

var state: GameState
var room: RoomData
var vm: ScriptVM
var player: Player
var rvd := CameraRVD.Estado.new()
var camera := 0
var trocas := 0
var historico: Array[String] = []

## Cache de salas já carregadas (o RDT é pequeno; o pesado são as imagens, que ficam no AssetIO)
var _cache: Dictionary = {}
## Porta em que o personagem aterrissou: bloqueia o re-disparo até ele sair da caixa.
var _ancora_porta: Aot


func _init(estado: GameState = null) -> void:
	state = estado if estado != null else GameState.new()
	player = Player.new()


func carregar(room_id: String) -> bool:
	## Carrega a sala, roda o script (que instala os AOT) e prepara colisão/câmera.
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
	return true


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
	if porta.to_pos != Vector3i.ZERO:
		player.pos = _desencravar(porta.to_pos)
	else:
		# porta "mantém posição" (to_pos zerado — elevador/escada no mesmo ponto): a posição
		# atual pode ser ilegal na sala NOVA; desencrava do mesmo jeito
		player.pos = _desencravar(player.pos)
	player.facing = PS1Math.wrap_angle(porta.to_facing)
	camera = porta.to_cut if porta.to_cut >= 0 and porta.to_cut < room.cameras.size() else 0
	rvd = CameraRVD.Estado.new()
	rvd.camera = camera
	# Carga de sala também ancora/exclui a supressora da câmera de chegada (`0x80049728`).
	CameraRVD.matar_supressora(room, rvd, camera)
	# O grupo de câmera vem do descriptor da porta (+0xb). Sem isso, as zonas RVD de grupo
	# específico (0..31) são todas rejeitadas e a câmera simplesmente não troca — foi o que o
	# usuário viu na R101, cujas zonas da câmera 0 usam grupos 0x01 e 0x04.
	rvd.grupo = porta.to_grupo


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


signal item_pego(item_id: int, qtd: int)

## Última ação tentada, para o HUD dizer o que aconteceu.
var ultima_acao := ""


func tick(pad: Pad) -> void:
	## Um passo do mundo: personagem → câmera (RVD) → AÇÃO (porta/item).
	##
	## Porta e item exigem o BOTÃO DE AÇÃO, como no RE3 — encostar não basta. Antes eu
	## atravessava só por estar dentro do AOT, o que também causava troca em loop.
	player.tick(pad)
	# O Y NÃO é integrado: é rederivado do piso todo frame (`0x80033b88` → `floor_height`
	# `0x8004d720` → grava em `entity+0x38`). É o que faz descer escada/rampa — sem isto a
	# Jill descia flutuando no Y do andar de cima (relato do usuário).
	if room.colisao != null:
		player.pos.y = room.colisao.floor_height(player.pos.x, player.pos.z, player.pos.y)
	# O "grupo" das zonas RVD (`gs+0x2495`) é o NÍVEL DO PISO do player: `gs+0x2495` =
	# `0x800CCBCD` = player`+0x09`, que o passe de piso grava com `-Y/1800` todo frame. O byte
	# `+0xb` da porta é só o valor INICIAL (o nível da chegada). Congelar o grupo no valor da
	# porta era o que impedia a câmera de trocar ao descer a escada da R101 (as zonas do andar
	# de baixo têm grupo = o nível de lá).
	rvd.grupo = player.nivel()
	camera = CameraRVD.update(room, rvd, player.pos.x, player.pos.z)
	if pad.just_pressed(Pad.ACAO):
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
	if sala == "" or not carregar(sala):
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
