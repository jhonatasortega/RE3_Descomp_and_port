extends Node2D
## Camada de APRESENTAÇÃO: background 2D + mundo 3D por cima, com modo de tela (P1-15).
##
## Estrutura (a mesma ideia do protótipo antigo, agora isolada da lógica):
##
##     Screen (Node2D)                    ← este script
##     ├── Background (Sprite2D)          background da câmera atual (HD 1280×960 ou PS1 4×)
##     └── Frame (SubViewportContainer)   compõe o 3D transparente por cima do 2D
##         └── World (SubViewport)        1280×960, transparent_bg
##             ├── Camera3D               montada pelo CameraRID
##             ├── Sun (DirectionalLight3D)
##             └── (personagens entram aqui)
##
## ── Modo de tela (decisão registrada no plano §2.1) ──
## O MUNDO é sempre 4:3 1280×960 — é a resolução dos 1316 backgrounds HD. O modo só decide
## o que a janela mostra:
##   • `4:3`  (padrão): emoldura (pillarbox) — 1:1 com o original;
##   • `16:9` (experimental): recorta para 1280×720, **perdendo 25% da altura**.
##
## O recorte é aplicado como deslocamento vertical da apresentação. Isso tem de ser propagado
## à origem de tela dos sprites de oclusão (P1-16), senão a oclusão desalinha 120 px.

enum ScreenMode { RATIO_4_3, RATIO_16_9 }

const WORLD_W := 1280
const WORLD_H := 960
const CROP_H := 720                        ## altura do recorte 16:9 (perde 240 px)

@export var screen_mode: ScreenMode = ScreenMode.RATIO_4_3
## SALA INICIAL. **R10D** é onde o jogo começa (informado pelo usuário, que conhece o jogo; a
## cinemática de abertura roda em `R10D_2`). Eu havia lido `INIT_TBL.DAT` nos offsets 590/592
## (onde `stage`/`room` cairiam, já que o arquivo vai para `0x800d1d28`) e obtive 0/0 = R100 —
## mas aquela região do arquivo é **toda zerada**, ou seja eu li padding, não campo. Não era
## evidência. R10D tem 13 câmeras, 49 funções de script e 13 backgrounds HD.
@export var room_id := "R10D"
@export var camera_index := 0
## Modelo do personagem (carregado em runtime, ver AssetIO.model). Vazio = não mostrar.
@export var actor_model := "PLD/PL00.glb"
## Posição inicial. O `y` é o NÍVEL do chão do bloco de colisão: 0 no térreo, e múltiplos de
## -1800 nos andares (é o mesmo valor que as portas mandam em `to_y`, medido em 453 chegadas).
## O -258 que estava aqui vinha do protótipo e levantava a Jill 258 un do chão.
## Posição de spawn em R10D, MEDIDA: varri uma grade no nível 0 em volta do alvo da câmera 0 e
## peguei um ponto que o resolver aceita nas 4 direções (99 pontos livres; ver
## `port/dev/diag_spawn_r10d.gd`). Não é a posição do jogo — essa vem da cinemática de abertura,
## que não foi implementada — e está declarada como escolha.
## Spawn de teste em **(9404, 0, -13317)**, na área da câmera 1 — ponto a que o usuário chegou
## ANDANDO, portanto chão válido. O anterior (11560, -16528) caía sobre o entulho da direita, que
## é área proibida e ainda sem colisão resolvida (as formas 2/3 do motor seguem aproximadas).
@export var actor_ps1 := Vector3i(9404, 0, -13317)
@export var actor_anim := "arm02"          ## idle ARMADO (em pé com a arma)
## Malha de arma a anexar no punho. **Vazio de propósito**: ver a nota em `_montar_arma`.
@export var weapon_model := ""
## Oclusão por atlas HD (P1-07). OVERLAY desenha todos os sprites (valida o mapeamento).
@export var occlusion_mode: Occlusion.Modo = Occlusion.Modo.PROFUNDIDADE
## Wireframe da colisão sobre o cenário — calibração de câmera/FOV (P1-04/P1-06).
@export var debug_collision := false
## Força um FOV (graus) em vez do derivado do attr — só para comparação A/B (P1-04).
@export var fov_override := 0.0

var background: Sprite2D
var frame: SubViewportContainer
var world: SubViewport
var esp: EspBrilho
var esp_sala: EspSala                   ## efeitos da sala (fogo/fumaça), pelo `off[17]` do RDT
var menu: MenuStatus
var menu_arquivo: MenuArquivo
var _mouse_antes := false               ## borda do botão esquerdo (clique = toque no menu)
var laser: MeshInstance3D               ## mira LASER (só no modo fácil)
var _arma_atual := -1                   ## item cuja malha está na mão
## Passos de roda acumulados desde o último tick (+ desce/avança, − sobe/volta). Ver `_scroll`.
var _rolagem := 0
const ROLAGEM_MAX := 3                  ## teto por tick, para um giro rápido não pular 10 páginas
var cam3d: Camera3D
var sun: DirectionalLight3D
var room: RoomData


var actor: Node3D                          ## nó "pé no chão" do personagem
var actor_mesh: Node3D
var actor_anim_player: AnimationPlayer
var mundo: World                           ## mundo lógico: sala + script + player + portas
var player: Player                         ## atalho para world.player
var _clipe_tocando := ""
var occlusion: Occlusion
var debug: DebugDraw
var debug_aot: DebugDraw


func _ready() -> void:
	_montar()
	carregar_sala(room_id)
	if actor_model != "":
		_montar_ator()
	_montar_spawns()
	aplicar_modo(screen_mode)
	_montar_hud()
	_montar_itens()
	if mundo != null:
		mundo.item_pego.connect(func(_id: int, _q: int) -> void: _montar_itens())
	# A apresentação OUVE o tick do jogo; não avança o mundo por conta própria.
	var g: Node = get_node_or_null("/root/Game")
	if g != null:
		g.tick.connect(_on_tick)
	else:
		push_warning("Screen: autoload Game ausente — a cena fica estática")


func _montar_spawns() -> void:
	## Instancia os personagens que o SCRIPT colocou na sala (P2-06).
	##
	## Limites honestos desta etapa: (a) sem IA — eles ficam na pose de repouso (a F5 dá
	## comportamento); (b) a espécie vem com CONFIANÇA declarada no dado, então alguns modelos
	## podem estar trocados e isso está registrado, não escondido; (c) spawns em posição (0,0,0)
	## são ignorados (93 no jogo: slots especiais, não colocação real).
	for n in spawn_nodes:
		n.queue_free()
	spawn_nodes.clear()
	if mundo == null or mundo.vm == null:
		return
	var n_ok := 0
	for sp: Spawn in mundo.vm.spawns:
		if sp.pos == Vector3i.ZERO:
			continue
		var rel := sp.modelo_rel()
		if rel == "" or not AssetIO.exists(rel):
			continue
		var m := AssetIO.model(rel)
		if m == null:
			continue
		var no := Node3D.new()
		no.name = "Spawn_%d_%02x" % [sp.slot, sp.classe]
		world.add_child(no)
		no.position = Coords.to_godot_i(sp.pos.x, sp.pos.y, sp.pos.z)
		no.rotation.y = Coords.yaw_from_ps1_angle(sp.dir)
		no.add_child(m)
		var ab := _aabb_de(m)
		m.position.y = -ab.position.y
		var ap := AssetIO.anim_player(m)
		if ap != null and ap.get_animation_list().size() > 0:
			var primeira: String = ap.get_animation_list()[0]
			ap.get_animation(primeira).loop_mode = Animation.LOOP_LINEAR
			ap.play(primeira)
		spawn_nodes.append(no)
		n_ok += 1
	if n_ok > 0:
		print("[screen] %d personagens instanciados pelo script (de %d spawns)" % [
			n_ok, mundo.vm.spawns.size()])


func _on_sala_trocada(de: String, para: String, porta: Aot) -> void:
	## A porta trocou a sala: recarrega cenário, oclusão e câmera de chegada.
	room = mundo.room
	room_id = para
	print("[screen] porta: %s -> %s (chegada %s, câmera %d)" % [
		de, para, mundo.player.pos, mundo.camera])
	var g1: Node = get_node_or_null("/root/Game")
	if g1 != null and g1.audio != null:
		g1.audio.tocar_bgm_da_sala(para)
	mostrar_camera(mundo.camera)
	_montar_itens()


func _on_tick(_frame: int) -> void:
	if mundo == null or mundo.room == null:
		return
	var pad: Pad = get_node("/root/Game").pad
	# ── MENU DE STATUS ──
	# No jogo, abrir o menu SUSPENDE a task do mundo (`task_suspend(0)` em `0x8006d97c`) e
	# retomá-la é o `task_resume(0)` de `0x8006e248` — os dois únicos sítios do EXE. Aqui isso é
	# "não chamar `mundo.tick`": o mundo congela no estado exato, que é o comportamento certo.
	## CLIQUE/TOQUE no menu: vem antes do `ACAO` porque o botão esquerdo do mouse também alimenta
	## esse bit. `menu.clicar` seleciona no 1º clique e confirma no 2º no mesmo lugar.
	## HOVER: passar o mouse por cima destaca o item (pedido do usuário). Só quando o ponteiro
	## MOVEU — com o mouse parado o cursor ficaria preso e o teclado não sairia do lugar.
	if menu != null and menu.aberto and (pad.mouse_dx != 0 or pad.mouse_dy != 0):
		if menu.pairar(_ponto_menu()):
			menu.queue_redraw()
	if menu != null and menu.aberto and _clique():
		if menu.clicar(_ponto_menu()) != "":
			menu.avancar()
			_atualizar_hud()
			return
	if menu_arquivo != null and menu_arquivo.aberto:
		menu.queue_redraw()               ## a moldura desenha a grade de documentos
		var rol := _scroll()
		if rol != 0:
			if menu_arquivo.lendo:
				menu_arquivo.virar_pagina(rol)     ## roda do mouse vira a página
			else:
				menu_arquivo.mover_grade(0, rol)
			_atualizar_hud()
			return
		if pad.just_pressed(Pad.ACAO):
			menu_arquivo.confirmar()
		elif pad.just_pressed(Pad.PAUSA) or pad.just_pressed(Pad.MENU):
			menu_arquivo.cancelar()
		## Navegação **WSAD** na tela de arquivo, nos dois modos:
		##   grade  → W/S andam na LINHA (5 documentos), A/D andam na COLUNA;
		##   leitura → W/A voltam página, S/D avançam.
		elif pad.just_pressed(Pad.FWD) or pad.just_pressed(Pad.HELD_UP):
			if menu_arquivo.lendo:
				menu_arquivo.virar_pagina(-1)
			else:
				menu_arquivo.mover_grade(0, -1)
		elif pad.just_pressed(Pad.BACK) or pad.just_pressed(Pad.HELD_DOWN):
			if menu_arquivo.lendo:
				menu_arquivo.virar_pagina(1)
			else:
				menu_arquivo.mover_grade(0, 1)
		elif pad.just_pressed(Pad.HELD_LEFT):
			if menu_arquivo.lendo:
				menu_arquivo.virar_pagina(-1)
			else:
				menu_arquivo.mover_grade(-1, 0)
		elif pad.just_pressed(Pad.HELD_RIGHT):
			if menu_arquivo.lendo:
				menu_arquivo.virar_pagina(1)
			else:
				menu_arquivo.mover_grade(1, 0)
		_atualizar_hud()
		return
	if menu != null and menu.aberto:
		var rol2 := _scroll()
		if rol2 != 0:
			menu.mover_cursor(0, rol2)             ## roda rola o texto de EXAMINAR / anda no menu
			menu.avancar()
			_atualizar_hud()
			return
		if pad.just_pressed(Pad.MENU):
			menu.alternar()                    ## I alterna
		elif pad.just_pressed(Pad.PAUSA):
			menu.cancelar()                    ## ESC só CANCELA (fecha submenu, senão a tela)
		elif pad.just_pressed(Pad.ACAO):
			var feito: String = menu.confirmar()   ## Enter/E seleciona
			if feito != "":
				print("[menu] %s" % feito)
		elif pad.just_pressed(Pad.HELD_UP) or pad.just_pressed(Pad.FWD):
			menu.mover_cursor(0, -1)
		elif pad.just_pressed(Pad.HELD_DOWN) or pad.just_pressed(Pad.BACK):
			menu.mover_cursor(0, 1)
		elif pad.just_pressed(Pad.HELD_LEFT):
			menu.mover_cursor(-1, 0)
		elif pad.just_pressed(Pad.HELD_RIGHT):
			menu.mover_cursor(1, 0)
		menu.avancar()
		_atualizar_hud()
		return
	if menu != null and pad.just_pressed(Pad.MENU):
		menu.alternar()
		return
	if pad.just_pressed(Pad.PAUSA):
		# ESC fora do status = MENU DE PAUSA, que ainda não foi extraído do binário. Não abro o
		# status no lugar dele (o usuário pediu explicitamente) e não invento uma tela.
		print("[screen] pausa (ESC): o menu de pausa ainda não foi extraído")
		return
	mundo.tick(pad)
	player = mundo.player
	# posição/orientação do nó a partir do estado em unidades PS1
	actor.position = Coords.to_godot_i(player.pos.x, player.pos.y, player.pos.z)
	actor.rotation.y = Coords.yaw_from_ps1_angle(player.facing)
	_tocar(player.clipe_atual())
	if occlusion != null:
		# a profundidade usa o TORSO (não os pés): é o que decide se o móvel cobre o corpo
		var torso := Vector3i(player.pos.x, player.pos.y - Player.ALTURA_PS1 / 2, player.pos.z)
		occlusion.atualizar_profundidade(room.camera(camera_index), torso)
	if mundo.camera != camera_index:
		mostrar_camera(mundo.camera)
	if esp_sala != null:
		## PROFUNDIDADE do fogo: as três chaves da Ordering Table do PS1 são comparáveis — máscara do
		## cenário = `depth` cru do RDT (`0x80048844`), personagem = `zona*1024 + SZ>>5`
		## (`0x80037d50`), efeito = `z>>5` (`0x80022de0`), e chave MENOR desenha depois, ou seja na
		## frente (`0x80029618`). Passando a sala, a câmera e a chave do personagem, o `EspSala`
		## decide sozinho o que fica na frente e o que fica atrás. Sem os 3 argumentos ele volta ao
		## comportamento antigo (tudo atrás do 3D), que era o meu paliativo.
		esp_sala.avancar(cam3d, room, camera_index, occlusion.char_key)
	if esp != null:
		esp.avancar(cam3d)                     ## o cintilar do item anda no tick de 30 Hz
	var gs2: Node = get_node_or_null("/root/Game")
	if gs2 != null and gs2.get("state") != null:
		_trocar_arma_na_mao(int(gs2.state.equipped_item_id()))
	_atualizar_laser()                         ## mira laser (modo fácil)
	_atualizar_hud()


func _tocar(clipe: String) -> void:
	if actor_anim_player == null or clipe == _clipe_tocando:
		return
	if not actor_anim_player.has_animation(clipe):
		return
	_clipe_tocando = clipe
	var a := actor_anim_player.get_animation(clipe)
	a.loop_mode = Animation.LOOP_LINEAR
	actor_anim_player.play(clipe)


func _montar_ator() -> void:
	## O nó `actor` é o PÉ (origem no chão); o mesh é filho, levantado por `foot_offset` para
	## os pés baterem na origem. Convenção herdada do protótipo (validada por render lá):
	##   foot_offset = 1.85 (AABB min_y do modelo) · mesh yaw = +90° (senão ela "anda de lado")
	actor = Node3D.new()
	actor.name = "Actor"
	world.add_child(actor)
	actor.position = Coords.to_godot_i(actor_ps1.x, actor_ps1.y, actor_ps1.z)

	# o personagem vive no World (lógica); aqui só se define onde ele começa
	player = mundo.player
	player.pos = actor_ps1
	player.carregar_root_motion()
	mundo.rvd.camera = CameraRVD.best_camera_for(room, actor_ps1.x, actor_ps1.z)
	mundo.camera = mundo.rvd.camera
	if mundo.camera != camera_index:
		mostrar_camera(mundo.camera)

	actor_mesh = AssetIO.model(actor_model)
	if actor_mesh == null:
		push_warning("Screen: modelo %s não carregou" % actor_model)
		return
	actor.add_child(actor_mesh)
	var aabb := _aabb_de(actor_mesh)
	actor_mesh.position.y = -aabb.position.y        ## levanta pelo min_y real do modelo
	actor_mesh.rotation.y = deg_to_rad(Coords.MESH_YAW_OFFSET_DEG)
	_anexar_arma()
	actor_anim_player = AssetIO.anim_player(actor_mesh)
	if actor_anim_player != null and actor_anim_player.has_animation(actor_anim):
		var a := actor_anim_player.get_animation(actor_anim)
		a.loop_mode = Animation.LOOP_LINEAR
		actor_anim_player.play(actor_anim)
	print("[screen] ator %s em PS1%s (godot %s) altura=%.2f un, anim=%s (%d clipes)" % [
		actor_model, actor_ps1, actor.position, aabb.size.y, actor_anim,
		actor_anim_player.get_animation_list().size() if actor_anim_player else 0])


func arma_da_mao(item_id: int) -> String:
	## Malha da arma do item equipado, ou "" se não houver.
	## ── DE-PARA MEDIDO (`port/dev/diag_armas.gd`, AABB em unidades PS1) ──
	## O número do `.PLW` é o **`item_id` da arma, em decimal**: `W01` 517×106×27 = faca (comprida,
	## fina, chata), `W02`/`W03` 163×370 = as duas pistolas (bate com o timing do EXE: 12 quadros
	## para w1 **e** w2), `W04` 135×**990** = escopeta, `W06..W09` 301×835 idênticas = os quatro
	## lança-granadas (itens `0x06..0x09`), `W10` = lança-rockets (item `0x0a` = **10** decimal, e
	## não "0A" — é o que fixa a base). `W00` não tem malha: é a arma pintada na pele.
	if item_id <= 0 or Itens.categoria(item_id) != Itens.CAT_ARMA:
		return ""
	var rel := "PLD/PL00W%02d_WPN.glb" % item_id
	return rel if AssetIO.exists(rel) else ""


func _trocar_arma_na_mao(item_id: int) -> void:
	## (Re)anexa a malha quando o item equipado muda. Sem isto a Jill andava de mão vazia mesmo com
	## a Hand Gun equipada — o `weapon_model` era fixo e vinha vazio.
	if _arma_atual == item_id:
		return
	_arma_atual = item_id
	var esq0 := _achar_skeleton(actor_mesh)
	if esq0 != null:
		var antigo := esq0.get_node_or_null("WeaponAttach")
		if antigo != null:
			antigo.free()
	weapon_model = arma_da_mao(item_id)
	if weapon_model != "":
		_anexar_arma()


func _anexar_arma() -> void:
	## Anexa a malha da arma no OSSO DO PUNHO DIREITO (P1-08).
	##
	## Fatos do decomp (docs/decomp/notes/plw.md §6): o osso de anexo é o `bone04` — cadeia FK
	## `0 -> 2 -> 3 -> 4` = raiz -> ombro direito -> cotovelo -> punho —, e a Jill segura a arma
	## na destra. Dos 84 PLW, **63 têm malha separável** (`*_WPN.glb`) e **21 não têm slot**:
	## as pistolas W00 e as armas de PL09/PL0A são PINTADAS na pele do modelo, então para elas
	## não há nada a anexar (não é bug, é o dado).
	## ── POR QUE A ARMA NÃO APARECE NA MÃO (medido, 2026-08-08) ──
	## O usuário apontou: "não mostra arma equipada na mão". Duas coisas somadas:
	## 1. O modelo do ator é o **`PL00.glb`**, que é a malha do `.PLD` = Jill **DESARMADA**. Para a
	##    pistola W00 a arma é **pintada na pele** (a nota abaixo, dos 84 PLW: 63 têm malha
	##    separável e 21 não têm slot), e essa malha com a arma é o **`PL00W00.glb`** — que tem
	##    malha e **zero clipes** (as animações vivem no `PL00.glb`). Então o conserto é TROCAR a
	##    malha do ator pela da arma equipada e transplantar as animações, não anexar nada.
	## 2. Para as armas COM malha separável (`*_WPN.glb`, W01 em diante) o anexo funciona — testei
	##    e o log confirma "anexada em bone04 (osso 4/15)" —, mas a malha está em **espaço de
	##    MODELO** (AABB medida: origem em `x = -0,538`, tamanho `0,64`), então sem aplicar a
	##    inversa do rest do osso a arma fica FLUTUANDO longe da mão. Por isso `weapon_model` está
	##    vazio: prefiro sem arma a arma solta no ar.
	if weapon_model == "":
		return
	var esq := _achar_skeleton(actor_mesh)
	if esq == null:
		push_warning("Screen: sem Skeleton3D no modelo — arma não anexada")
		return
	var idx := esq.find_bone("bone04")
	if idx < 0:
		push_warning("Screen: osso bone04 não encontrado (ossos: %d)" % esq.get_bone_count())
		return
	var arma := AssetIO.model(weapon_model)
	if arma == null:
		return
	var att := BoneAttachment3D.new()
	att.name = "WeaponAttach"
	esq.add_child(att)
	att.bone_name = "bone04"
	att.add_child(arma)
	# A malha do PLW é autorada em espaço do MODELO (as mesmas coordenadas do corpo), não em
	# espaço do osso: o world-rest do bone04 é (-32, 297, -435) un PS1. Anexar direto aplicaria
	# a pose do osso DUAS vezes. Compensa-se com a inversa do rest global do osso — assim, na
	# pose de repouso a arma fica onde foi autorada e passa a seguir o punho quando ele se move.
	# Sem transformação extra: os vértices do PLW são gravados CRUS pelo exportador
	# (`P_.append(objs[oi]["verts"][vl])` em pld2gltf.extract_weapon) e no formato do RE eles
	# são BONE-LOCAL — então a pose corrente do osso já os leva ao lugar. PENDÊNCIA MEDIDA:
	# a arma cai no punho, mas orientada para DENTRO do corpo (a malha se estende 0,54 un no
	# -X do espaço do osso). O PLW tem 1 só objeto com arma (23 prims) + mão (17) juntas, e o
	# rest do `bone04` do PLD não tem a mesma orientação do espaço de osso do PLW. Corrigir
	# é tarefa do EXPORTADOR (aplicar o rest do próprio PLW ao exportar `_WPN.glb`), não de
	# ajuste às cegas aqui. Ver P1-08 no tracker.
	var rest_global := _rest_global(esq, idx)
	var ab := _aabb_de(arma)
	print("[screen] arma %s anexada em bone04 (osso %d/%d); AABB da malha=%s; rest global=%s" % [
		weapon_model, idx, esq.get_bone_count(), ab, rest_global.origin])


static func _rest_global(esq: Skeleton3D, idx: int) -> Transform3D:
	## Rest GLOBAL do osso (acumula a cadeia até a raiz). `get_bone_global_rest` existe em
	## versões recentes, mas acumular à mão funciona em qualquer uma e deixa explícito.
	var t := Transform3D.IDENTITY
	var i := idx
	while i >= 0:
		t = esq.get_bone_rest(i) * t
		i = esq.get_bone_parent(i)
	return t


static func _achar_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _achar_skeleton(c)
		if r != null:
			return r
	return null


static func _aabb_de(n: Node) -> AABB:
	## AABB do modelo inteiro (o glTF vem com vários MeshInstance3D).
	var total := AABB()
	var primeiro := true
	for m in _todos_mesh(n):
		var b: AABB = m.get_aabb()
		b.position += m.position
		if primeiro:
			total = b
			primeiro = false
		else:
			total = total.merge(b)
	return total


static func _todos_mesh(n: Node) -> Array[MeshInstance3D]:
	var saida: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		saida.append(n)
	for c in n.get_children():
		saida.append_array(_todos_mesh(c))
	return saida


func _montar() -> void:
	background = Sprite2D.new()
	background.name = "Background"
	background.centered = false
	add_child(background)

	world = SubViewport.new()
	world.name = "World"
	world.size = Vector2i(WORLD_W, WORLD_H)
	world.transparent_bg = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	frame = SubViewportContainer.new()
	frame.name = "Frame"
	frame.stretch = true
	frame.size = Vector2(WORLD_W, WORLD_H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(world)
	add_child(frame)

	cam3d = Camera3D.new()
	cam3d.name = "Camera3D"
	world.add_child(cam3d)

	# Brilho dos itens (efeito ESP): entra ACIMA do 3D e ABAIXO dos recortes de oclusão, para
	# móvel na frente cobrir o cintilar. Ver esp_brilho.gd para o que é provado e o que é escolha.
	## EFEITOS DA SALA (fogo, fumaça, faísca) — `EspSala`, alimentado pela tabela de ids de ESP do
	## RDT (`off[17]`, provada em `tools/rdt_esp.py`). Fica na mesma altura do brilho de item.
	esp_sala = EspSala.new()
	add_child(esp_sala)
	## ORDEM DE DESENHO: irmãos de `Node2D` desenham na ordem da ÁRVORE, e o mundo 3D vive no
	## `frame` (`SubViewportContainer`). Os efeitos da sala tinham sido adicionados DEPOIS dele e
	## por isso o fogo saía na frente da Jill e das colunas (relato: "fogo está na layer errada").
	## Movendo o nó para antes do `frame`, o 3D passa a desenhar POR CIMA do fogo, que é o certo
	## para chama de fundo. (O correto completo é usar a oclusão HD por profundidade, como o
	## cenário faz; isso fica anotado como o passo seguinte.)
	if frame != null:
		move_child(esp_sala, frame.get_index())
	esp = EspBrilho.new()
	add_child(esp)
	if not esp.carregar(WORLD_W):
		push_warning("Screen: sprites do brilho ausentes — rode "
			+ "`python tools/esp_decode.py dump port/assets/ESP`")

	# Tela de STATUS/INVENTÁRIO (I ou ESC). Entra por último no `_montar` para ficar ACIMA de
	# tudo — no PS1 ela é uma task própria que desenha depois do mundo.
	menu = MenuStatus.new()
	add_child(menu)
	var g_menu: Node = get_node_or_null("/root/Game")
	if not menu.carregar(g_menu.state if g_menu != null else null):
		push_warning("Screen: assets do menu ausentes — rode "
			+ "`python tools/status_assets.py --all`")

	# Tela de ARQUIVO (documentos), aberta pelo botão ARQ. do menu de status.
	menu_arquivo = MenuArquivo.new()
	add_child(menu_arquivo)
	menu_arquivo.carregar(g_menu.state if g_menu != null else null)
	menu.arquivo = menu_arquivo          ## a tela de arquivo desenha DENTRO da moldura do status
	# Carga de JOGO NOVO (provada em 0x8006d0d8): sem isso o inventário nasce vazio e a tela de
	# arquivo não tem os dois "Game Inst." que o jogo dá de saída.
	if g_menu != null and g_menu.state != null and g_menu.state.item_count() == 0:
		g_menu.state.novo_jogo()

	# Oclusão: recortes 2D do cenário desenhados POR CIMA do viewport 3D — é a ordem que
	# reproduz os priority sprites do PS1 (o 3D já está compondo sobre o background).
	occlusion = Occlusion.new()
	occlusion.name = "Occlusion"
	occlusion.modo = occlusion_mode
	add_child(occlusion)

	# Luz simples: o cenário é pré-renderizado, então o 3D só precisa não ficar preto.
	# O casamento de tom por câmera é item separado (P1-12).
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.0
	world.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR   ## o background 2D não passa por tonemap
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	world.add_child(we)


func carregar_sala(id: String) -> bool:
	if mundo == null:
		mundo = World.new(get_node("/root/Game").state if has_node("/root/Game") else null)
		mundo.sala_trocada.connect(_on_sala_trocada)
	if not mundo.carregar(id):
		return false
	room = mundo.room
	## efeitos da sala (fogo/fumaça): a lista vem do `off[17]` do RDT daquela sala
	if esp_sala != null:
		var n_ef := esp_sala.carregar(id)
		if n_ef > 0:
			print("[screen] %d efeitos de ESP na sala %s" % [n_ef, id])
	player = mundo.player
	room_id = id
	var g0: Node = get_node_or_null("/root/Game")
	if g0 != null and g0.audio != null:
		g0.audio.tocar_bgm_da_sala(id)
	mostrar_camera(mini(camera_index, room.cameras.size() - 1))
	print("[screen] %s" % room.summary())
	return true


func mostrar_camera(i: int) -> void:
	var c := room.camera(i)
	if c == null:
		push_error("Screen: câmera %d não existe em %s" % [i, room_id])
		return
	camera_index = i
	var tex := CameraRID.background(room_id, i)
	if tex == null:
		push_warning("Screen: sem background para %s câmera %d" % [room_id, i])
	background.texture = tex
	if tex != null:
		# O PS1 é 320×240; o HD é 1280×960. Nos dois casos o quadro do mundo é 1280×960.
		background.scale = Vector2(float(WORLD_W) / float(tex.get_width()),
			float(WORLD_H) / float(tex.get_height()))
	CameraRID.apply(cam3d, c)
	if fov_override > 0.0:
		cam3d.fov = fov_override
	if debug_collision and debug == null:
		debug = DebugDraw.new()
		debug.name = "DebugCollision"
		world.add_child(debug)
		# VOLUMES: mostra a altura real do collider (base -> topo), que é o que permite casar
		# com o cenário. F8 cicla os modos em jogo.
		_modo_colisao = DebugDraw.Modo.VOLUMES
		debug.desenhar_modo(room, player.pos.y, DebugDraw.Modo.VOLUMES)
	if occlusion != null:
		var n := occlusion.carregar(room, i)
		print("[screen] oclusão: %s (Z dos sprites: %s)" % [occlusion.info(), occlusion.z_range()])
		if n == 0 and c.n_masks > 0:
			push_warning("Screen: câmera %d declara %d máscaras mas 0 sprite montado" % [i, c.n_masks])
	print("[screen] câmera %d/%d attr=%d fov=%.1f%s bg=%s" % [
		i, room.cameras.size(), c.attr, cam3d.fov,
		"" if CameraRID.is_calibrated(c.attr) else " (FOV não calibrado)",
		CameraRID.background_rel(room_id, i)])


func aplicar_modo(m: ScreenMode) -> void:
	screen_mode = m
	var altura := WORLD_H if m == ScreenMode.RATIO_4_3 else CROP_H
	# Deslocamento vertical do recorte: metade do que se perde (corta em cima e embaixo).
	var dy := -float(WORLD_H - altura) * 0.5
	position = Vector2(0.0, dy)
	# A janela mantém a proporção do modo; `keep` no project.godot gera o pillarbox no 4:3.
	var w := get_window()
	if w != null:
		w.content_scale_size = Vector2i(WORLD_W, altura)
	print("[screen] modo %s -> %dx%d (deslocamento y=%.0f)" % [
		"4:3" if m == ScreenMode.RATIO_4_3 else "16:9 (experimental, corta 25%)",
		WORLD_W, altura, dy])


var _porta_atual := 0
var hud: Label
var _faixas: Array[String] = []
var _faixa_i := 0
var spawn_nodes: Array[Node3D] = []


func _ir_para_porta() -> void:
	## F2: teleporta o personagem para o centro da caixa de gatilho da próxima porta.
	## Afordância de TESTE (não é mecânica do jogo): achar a porta andando numa sala
	## desconhecida é chato, e a transição é o que interessa verificar.
	if mundo == null or mundo.vm == null:
		return
	var ps := mundo.vm.portas()
	if ps.is_empty():
		print("[screen] esta sala não tem porta instalada pelo script")
		return
	_porta_atual = _porta_atual % ps.size()
	var p: Aot = ps[_porta_atual]
	_porta_atual += 1
	var alvo := Vector3i.ZERO
	if p.kind == Aot.Kind.BOX:
		alvo = Vector3i(p.box.position.x + p.box.size.x / 2, mundo.player.pos.y,
			p.box.position.y + p.box.size.y / 2)
	elif p.quad.size() == 4:
		var cx := 0
		var cz := 0
		for v in p.quad:
			cx += v.x
			cz += v.y
		alvo = Vector3i(cx / 4, mundo.player.pos.y, cz / 4)
	mundo.player.pos = alvo
	print("[screen] F2 -> porta %d/%d: %s" % [_porta_atual, ps.size(), p.resumo()])


func _montar_hud() -> void:
	## Overlay de diagnóstico (F1). Existe porque "não anda" é sintoma, não medida: com isto
	## dá para ver na hora se o pad está chegando, se a posição muda e qual câmera está ativa.
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_color_override("font_color", Color(1, 1, 0.6))
	hud.add_theme_font_size_override("font_size", 18)
	cl.add_child(hud)


func _atualizar_laser() -> void:
	## MIRA LASER do modo FÁCIL (pedido do usuário; **não existe no original** — a regra de
	## dificuldade está declarada em `Player.Dificuldade`). É um FEIXE fino (caixa esticada) do peito
	## da Jill até o alvo travado, ou até o alcance do auto-lock (3000 un, do descritor
	## `0x80098064`) quando não há alvo. Caixa e não linha porque a linha de 1 px do `ImmediateMesh`
	## não aparecia na captura.
	if player == null or world == null:
		return
	if laser == null:
		laser = MeshInstance3D.new()
		laser.name = "MiraLaser"
		var bm := BoxMesh.new()
		bm.size = Vector3(0.012, 0.012, 1.0)       ## 1 un de comprimento; a escala estica no Z
		laser.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.12, 0.12)
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.disable_receive_shadows = true
		m.no_depth_test = false
		laser.material_override = m
		world.add_child(laser)
	var mostrar: bool = player.acao == Player.Acao.MIRANDO and player.mira_com_laser()
	laser.visible = mostrar
	if not mostrar:
		return
	## A MIRA SAI DA ARMA (o usuário cobrou: saía do peito). O EXE calcula o ponto do cano a partir
	## do esqueleto em `0x80018d34` e grava em `player+0x124/0x126/0x128`; aqui uso a posição GLOBAL
	## do anexo da arma (`WeaponAttach` no `bone04`, o punho direito), que é o mesmo ponto na prática,
	## e caio na altura do peito só se a arma não estiver anexada.
	var origem := Coords.to_godot_i(player.pos.x, player.pos.y, player.pos.z)
	origem.y += float(Player.ALTURA_PS1) * 0.75 / Coords.WORLD_SCALE
	var esq_arma := _achar_skeleton(actor_mesh)
	if esq_arma != null:
		var att2: Node3D = esq_arma.get_node_or_null("WeaponAttach") as Node3D
		if att2 != null:
			origem = att2.global_position
	var destino_ps1 := player.pos + Vector3i(
		PS1Math.rsin(player.facing) * Player.MIRA_ALCANCE >> PS1Math.SHIFT, 0,
		-PS1Math.rcos(player.facing) * Player.MIRA_ALCANCE >> PS1Math.SHIFT)
	if player.mira_alvo >= 0 and player.alvos.is_valid():
		var lista: Array = player.alvos.call()
		if player.mira_alvo < lista.size():
			destino_ps1 = lista[player.mira_alvo]
	var destino := Coords.to_godot_i(destino_ps1.x, player.pos.y, destino_ps1.z)
	destino.y = origem.y
	## INCLINAÇÃO: o laser tem de subir/descer com a mira (o usuário notou que ele saía reto).
	## O pitch está em unidades de ângulo de 12 bits (`player.mira_pitch_y`), então a subida é
	## `sen(pitch) × alcance` — usando a MESMA tabela de seno do jogo (`PS1Math.rsin`, fixo em
	## 4096 = 1,0). Com alvo travado o destino é o próprio alvo e a inclinação sai dele.
	if player.mira_alvo < 0 and player.mira_pitch_y != 0:
		var comp_ps1 := float(Player.MIRA_ALCANCE)
		var subida := float(PS1Math.rsin(player.mira_pitch_y)) / 4096.0 * comp_ps1
		destino.y = origem.y + subida / Coords.WORLD_SCALE
	var dir := destino - origem
	var comp := dir.length()
	if comp < 0.01:
		laser.visible = false
		return
	laser.position = origem + dir * 0.5
	laser.scale = Vector3(1.0, 1.0, comp)
	laser.look_at(destino, Vector3.UP)


func _scroll() -> int:
	## Roda do mouse: **+1 desce/avança, -1 sobe/volta**. Pedido do usuário para o texto de exame e
	## para a página do documento.
	##
	## ── POR QUE NÃO FUNCIONAVA (e o conserto) ──
	## Estava lido por POLLING, com `Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP/DOWN)`,
	## copiando a receita do clique. A roda em Godot **não é um botão que fica pressionado**: ela
	## chega como `InputEventMouseButton` com `pressed = true` e nunca solta, então
	## `is_mouse_button_pressed` devolve `false` em todo quadro e a borda nunca acontecia — o
	## `rol` era sempre 0. Agora o evento é acumulado em `_input` (`_rolagem`) e o tick só
	## CONSOME o acumulado, o que mantém a lógica no tick de 30 Hz.
	var d := clampi(_rolagem, -ROLAGEM_MAX, ROLAGEM_MAX)
	_rolagem = 0
	return d


func _input(e: InputEvent) -> void:
	## A RODA DO MOUSE vive aqui, não no polling do tick: é evento puro (ver `_scroll`).
	## `_input` e não `_unhandled_input` porque o `Frame` (`SubViewportContainer`) repassa o evento
	## para o `SubViewport` do mundo 3D, e daí ele pode não voltar como "não tratado".
	if not (e is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = e
	if not mb.pressed:
		return                                    ## a roda também emite o "solta"; conta uma vez
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_rolagem += 1
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_rolagem -= 1


func _clique() -> bool:
	## Borda de subida do botão esquerdo (ou do toque). Guarda o estado entre ticks.
	var agora := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var subiu := agora and not _mouse_antes
	_mouse_antes = agora
	return subiu


func _ponto_menu() -> Vector2:
	## Ponteiro no espaço 320×240 do menu (o nó tem escala 4).
	if menu == null:
		return Vector2(-1, -1)
	return menu.to_local(menu.get_global_mouse_position())


func _atualizar_hud() -> void:
	if hud == null or not hud.visible or mundo == null or mundo.player == null:
		return
	var g: Node = get_node_or_null("/root/Game")
	var m := 0
	if g != null and g.pad != null:
		m = g.pad.mask
	var teclas := ""
	if m & Pad.FWD:
		teclas += "W "
	if m & Pad.BACK:
		teclas += "S "
	if m & Pad.HELD_LEFT:
		teclas += "A "
	if m & Pad.HELD_RIGHT:
		teclas += "D "
	if m & Pad.RUN:
		teclas += "SHIFT "
	if m & Pad.AIM:
		teclas += "MIRA "
	if m & Pad.TIRO:
		teclas += "TIRO "
	## Estado da mira no HUD: é o que diz, numa captura, se o bit do mouse chegou e em que
	## sub-estado da rotina 7 o player está.
	var pl: Player = mundo.player
	var mira := "mira: arma=0x%02x sub=%d alvo=%d recuo=%d %s" % [pl.equipped_weapon,
		pl.mira_sub, pl.mira_alvo, pl.recuo,
		["FACIL", "NORMAL", "DIFICIL"][clampi(int(pl.dificuldade), 0, 2)]]
	hud.text = ("sala %s  câmera %d/%d (attr %d, fov %.1f)
"
		+ "pos PS1 %s  ângulo %d  ação %d  clipe %s
"
		+ "pad 0x%03x [%s]  tick %d  fps %d
"
		+ "trilha %s   %s
"
		+ "%s
"
		+ "E ação · F1 hud · F2 porta · F3 listar · F4 gatilhos · F7 grade · F10 colisão · F5/F6 trilha · [ ] câmera · F9 tela") % [
		room_id, camera_index, room.cameras.size(),
		room.camera(camera_index).attr if room.camera(camera_index) else 0, cam3d.fov,
		mundo.player.pos, mundo.player.facing, mundo.player.acao,
		mundo.player.clipe_atual(), m, teclas,
		g.clock.frame if g != null and g.clock != null else 0,
		Engine.get_frames_per_second(),
		g.audio.faixa_atual() if g != null and g.audio != null else "-",
		_dica_acao(), mira]


func _dica_acao() -> String:
	## Diz se há algo sob o personagem e o resultado da última ação (E).
	if mundo == null:
		return ""
	var alvo := ""
	var it := mundo.vm.itens() if mundo.vm != null else []
	for a: Aot in it:
		if a.contem(mundo.player.pos.x, mundo.player.pos.z):
			alvo = "[E] pegar item 0x%02x" % a.item_id
			break
	if alvo == "":
		var p := mundo.porta_sob_o_player()
		if p != null:
			alvo = "[E] porta -> %s" % p.to_room_id()
	if alvo == "" and mundo.ultima_acao != "":
		alvo = "(" + mundo.ultima_acao + ")"
	return alvo


func _ciclar_trilha(passo: int) -> void:
	## F5/F6: percorre as 125 faixas convertidas e mostra o nome. O mapa área→faixa do
	## `bgm_map.json` é declaradamente PROVISÓRIO — a forma honesta de fixá-lo é ouvir e
	## anotar, e é isso que estas teclas permitem.
	var g: Node = get_node_or_null("/root/Game")
	if g == null or g.audio == null:
		return
	if _faixas.is_empty():
		var d := DirAccess.open("res://assets/SOUND/BGM/gog")
		if d == null:
			# assets/ tem .gdignore, então DirAccess por res:// não lista: usa o caminho real
			d = DirAccess.open(AssetIO.path("SOUND/BGM/gog"))
		if d != null:
			for f in d.get_files():
				if f.ends_with(".ogg"):
					_faixas.append(f.trim_suffix(".ogg"))
			_faixas.sort()
	if _faixas.is_empty():
		print("[screen] nenhuma faixa em assets/SOUND/BGM/gog (rode tools/audio_gog.py)")
		return
	_faixa_i = (_faixa_i + passo + _faixas.size()) % _faixas.size()
	var nome := _faixas[_faixa_i]
	var st := AudioStreamOggVorbis.load_from_file(AssetIO.path("SOUND/BGM/gog/%s.ogg" % nome))
	if st != null:
		st.loop = true
		g.audio.bgm_player.stream = st
		g.audio.bgm_player.play()
		g.audio._faixa_atual = nome
		print("[screen] trilha %d/%d: '%s'  (anote esta se for a certa da %s)" % [
			_faixa_i + 1, _faixas.size(), nome, room_id])


var grade: DebugDraw
@export var grade_y := 0


func _grade_chao() -> void:
	## F7: grade no chão em `grade_y`. Serve para calibrar o Y do piso por render.
	if grade == null:
		grade = DebugDraw.new()
		grade.name = "GradeChao"
		world.add_child(grade)
	grade.desenhar_grade(room, grade_y)
	grade.visible = true
	print("[screen] grade no chão em y=%d (sala %s, câmera %d)" % [grade_y, room_id, camera_index])


var _modo_colisao := -1        ## -1 = desligado; senão o índice de DebugDraw.Modo


func _ciclar_colisao() -> void:
	## F8: inspetor de colisão em cena. Cicla desligado → segmentos → volumes → tudo.
	##
	## Existe porque olhar coordenada não resolve a pergunta que importa: **o collider está onde
	## o cenário mostra?** As cores separam as categorias que o dado distingue, e a contagem sai
	## na HUD e no console.
	if debug == null:
		debug = DebugDraw.new()
		debug.name = "DebugCollision"
		world.add_child(debug)
	_modo_colisao += 1
	if _modo_colisao > DebugDraw.Modo.TUDO:
		_modo_colisao = -1
	if _modo_colisao < 0:
		debug.visible = false
		print("[screen] colisão: desligada")
		return
	debug.visible = true
	var c := debug.desenhar_modo(room, player.pos.y, _modo_colisao as DebugDraw.Modo)
	var nomes := ["segmentos (o que o motor testa)", "volumes (altura real do collider)",
		"tudo (inclui os desligados)"]
	print("[screen] colisão · modo %s · nível y=%d" % [nomes[_modo_colisao], player.pos.y])
	print("   vermelho=moldura da sala %d · verde=objeto %d · amarelo=círculo %d · laranja=girado 45° %d · cinza=desligado %d" % [
		c["envelope"], c["objeto"], c["circulo"], c["girado"], c["desligado"]])


func _alternar_aots() -> void:
	## F4: mostra/esconde as caixas de gatilho (porta ciano, item amarelo, resto magenta)
	## e o wireframe da colisão (parede vermelha, móvel verde).
	if debug_aot == null:
		debug_aot = DebugDraw.new()
		debug_aot.name = "DebugAOT"
		world.add_child(debug_aot)
		debug_aot.desenhar_aots(mundo.vm)
		if debug == null:
			debug = DebugDraw.new()
			debug.name = "DebugCollision"
			world.add_child(debug)
			debug.desenhar(room, player.pos.y)
		print("[screen] AOTs: %s" % mundo.resumo())
		for k in mundo.vm.aots:
			var a: Aot = mundo.vm.aots[k]
			print("   %s" % a.resumo())
	else:
		debug_aot.visible = not debug_aot.visible
		if debug != null:
			debug.visible = debug_aot.visible


func _listar_portas() -> void:
	## F3: lista no console o que o script instalou nesta sala.
	if mundo == null or mundo.vm == null:
		return
	print("[screen] %s" % mundo.resumo())
	for p: Aot in mundo.vm.portas():
		print("   %s" % p.resumo())


func crop_offset_y() -> int:
	## Quanto a apresentação está deslocada em Y. **Quem desenha em coordenada de TELA**
	## (sprites de oclusão, P1-16; UI, P6-10) precisa somar isto.
	return 0 if screen_mode == ScreenMode.RATIO_4_3 else (WORLD_H - CROP_H) / 2


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		match (e as InputEventKey).keycode:
			KEY_BRACKETRIGHT:
				mostrar_camera((camera_index + 1) % room.cameras.size())
			KEY_BRACKETLEFT:
				mostrar_camera((camera_index - 1 + room.cameras.size()) % room.cameras.size())
			KEY_F1:
				if hud != null:
					hud.visible = not hud.visible
			KEY_F2:
				_ir_para_porta()
			KEY_F5:
				_ciclar_trilha(-1)
			KEY_F6:
				_ciclar_trilha(1)
			KEY_F3:
				_listar_portas()
			KEY_F4:
				_alternar_aots()
			KEY_F7:
				_grade_chao()
			KEY_F10:
				_ciclar_colisao()
			KEY_F9:
				aplicar_modo(ScreenMode.RATIO_4_3 if screen_mode == ScreenMode.RATIO_16_9
					else ScreenMode.RATIO_16_9)

# ─────────────────────────────── itens no cenário ───────────────────────────────

var itens_nodes: Array[Node3D] = []


func _montar_itens() -> void:
	## Coloca em cena os itens que ainda estão no chão (P2-07).
	##
	## POSIÇÃO/ROTAÇÃO: do **objeto de cenário** (`0x7f`) cujo slot é o `om` do payload do item
	## — `pos` s16 em `+16/+18/+20` e `rot` s16 em `+22/+24/+26` (4096 = 360°). É o mesmo dado
	## que o motor usa para montar a matriz do objeto, então o item fica exatamente onde e como
	## o jogo põe: em cima da mesa, na prateleira, deitado na mão do cadáver. A área de coleta
	## do AOT NÃO é a posição do objeto (mediana de 336 unidades de distância entre as duas).
	## Sem `0x7f` correspondente (ou `om >= 32`, itens sem 3D), cai no centróide da área com o
	## Y do `floor_height` — é o melhor que existe nesse caso, e fica declarado.
	##
	## VISUAL: a MALHA DO JOGO, `assets/OMODEL/<sala>/om<N>.glb` — o slot `om` do item indexa o
	## diretório `offset_table[10]` do RDT (`nOmodel` registros de 8 B `{TIM, MD1}`, formato MD1
	## igual ao dos inimigos), exportado por `tools/omodel2gltf.py` (712 modelos, 0 falhas).
	## Só cai no marcador dourado quando o slot não tem malha (`om >= 32`, 30 itens) — aí não há
	## o que desenhar no dado, e um marcador é honesto.
	##
	## O item é ESTÁTICO: no jogo não gira. O que se move é o efeito ESP `0x0705` que o motor
	## cria 90 unidades ACIMA do objeto quando `item_flags & 0x80` (24 itens) — aqui isso é uma
	## luz, até o sistema de ESP existir (P5-xx).
	for n in itens_nodes:
		n.queue_free()
	itens_nodes.clear()
	if mundo == null or mundo.room == null:
		return
	var sem_lugar := 0
	var brilhos: Array[Vector3i] = []
	for a: Aot in mundo.itens_no_chao():
		var obj := mundo.objeto_do_item(a)
		var p := Vector3i.ZERO
		var base := Basis.IDENTITY
		if obj != null and obj.posicionado():
			p = obj.pos
			# TRÊS eixos, na convenção MEDIDA (`Coords.basis_from_ps1_rot`): há item com giro em
			# X e Z (a Chave do armazém da R100 é um quad plano com `rot(2048,5120,1024)`), e com
			# só o Y ela ficava de perfil — um risco preto em vez de uma chave na tábua.
			base = Coords.basis_from_ps1_rot(obj.rot)
		elif obj == null and a.area_valida():
			var c := _centro_do_aot(a)
			var y := mundo.player.pos.y
			if mundo.room.colisao != null:
				y = mundo.room.colisao.floor_height(c.x, c.y, mundo.player.pos.y)
			p = Vector3i(c.x, y, c.y)
		else:
			# Objeto parqueado em -32000 (entra por evento) ou área degenerada: não há lugar
			# no dado. Não se inventa um — o item continua existindo e coletável pela regra do
			# motor, só não é desenhado.
			sem_lugar += 1
			continue
		var no := _malha_do_item(a)
		no.name = "Item_%d_0x%02x_om%d" % [a.id, a.item_id, a.item_om]
		world.add_child(no)
		no.transform = Transform3D(base, Coords.to_godot_i(p.x, p.y, p.z))
		if a.tem_brilho():
			brilhos.append(p)                  ## `iflags & 0x80` — o cintilar do ESP (esp_brilho.gd)
		itens_nodes.append(no)
	if esp != null:
		esp.definir_fontes(brilhos)
	if not itens_nodes.is_empty() or sem_lugar > 0:
		print("[screen] %s: %d item(ns) no chão%s" % [room_id, itens_nodes.size(),
			"" if sem_lugar == 0 else " (+%d sem posição no dado)" % sem_lugar])


func _malha_do_item(a: Aot) -> Node3D:
	## A malha do jogo para o slot `om` da sala. Sem malha no dado (`om >= 32`) ou sem o `.glb`
	## exportado, devolve o marcador dourado — declarado, não fingido de item.
	if a.tem_modelo():
		# a sala é a do MUNDO, não a do `room_id` do nó: numa troca de sala o visual só se
		# atualiza depois, e buscar o modelo na sala antiga traz a malha errada.
		var sala := mundo.room.room_id if mundo != null and mundo.room != null else room_id
		var rel := "OMODEL/%s/om%d.glb" % [sala, a.item_om]
		if AssetIO.exists(rel):
			var m := AssetIO.model(rel)
			if m != null:
				_sem_luz(m)
				return m
	var no := MeshInstance3D.new()
	var prisma := PrismMesh.new()
	prisma.size = Vector3(0.30, 0.42, 0.30)
	no.mesh = prisma
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.86, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.12)
	mat.emission_energy_multiplier = 1.8
	no.material_override = mat
	no.position.y = 0.26
	return no


func _sem_luz(no: Node) -> void:
	## Desenha a malha do item SEM iluminação da cena.
	##
	## Por que: o objeto de sala é iluminado no PS1 pelo bloco **LIT** (`offset_table[9]`), que o
	## port ainda não implementa. Com a "luz simples" genérica daqui (um sol fixo + ambiente), a
	## Chave do armazém da R100 — um quad plano na parede, com a normal virada para a câmera e
	## portanto de costas para o sol — saía **preta**. Ela só parecia certa antes porque tinha um
	## OmniLight colado nela, que era o placeholder do brilho: ao trocar o placeholder pelo ESP
	## real, a malha ficou preta e o problema apareceu.
	##
	## Sem luz, a textura aparece como foi autorada — que é o mesmo tratamento do background
	## pré-renderizado. É DECLARADAMENTE provisório: o certo é o LIT da sala (item separado).
	for c: Node in no.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				var m2: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
				m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mi.set_surface_override_material(s, m2)


func _centro_do_aot(a: Aot) -> Vector2i:
	if a.kind == Aot.Kind.QUAD and a.quad.size() == 4:
		var sx := 0
		var sz := 0
		for p: Vector2i in a.quad:
			sx += p.x
			sz += p.y
		return Vector2i(sx / 4, sz / 4)
	return Vector2i(a.box.position.x + a.box.size.x / 2, a.box.position.y + a.box.size.y / 2)


## (Não existe `_girar_itens`: o item no chão do RE3 é ESTÁTICO. A rotação vem do `0x7f` e é
## fixa; quem chama atenção é o efeito ESP de brilho, não um giro. Girar era licença do
## placeholder — saiu junto com ele.)
