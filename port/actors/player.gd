class_name Player
extends RefCounted
## Jill: estado e movimento em unidades PS1, por TICK de 30 Hz (P1-09/P1-10/P1-11).
##
## Migrado do `godot/scripts/jill_controller.gd` (movimentação validada no protótipo), com
## três mudanças que o port exige:
##
##   1. **Sem `delta`**: tudo por tick de 30 Hz. As constantes da decomp são por-frame.
##   2. **Unidades PS1 inteiras** e ângulo de 12 bits (`PS1Math`) — nada de float na lógica.
##   3. **Entrada por `Pad`** (máscara de bits), o que permite replay determinístico.
##
## O nó visual não vive aqui: esta classe é lógica pura (roda headless no teste). Quem desenha
## lê `pos`/`facing` e converte com `Coords`.
##
## ── Root motion: o que é dado e o que ainda é aproximação (P1-10) ──
## O RE3 move o personagem pelo vetor de movimento DA POSE (`pose_entry+0x54`), não por
## velocidade constante. Para os clipes BASE existe medição por frame em `anim_map.json`
## (`timing_e_loop.andar_frente.root_delta_por_frame_world_dx`, 34 frames; `correr_frente`,
## 10 frames). Mas a locomoção de gameplay usa os clipes ARMADOS (`arm00/01/09`, do PLW da
## arma equipada) e **o vetor por-frame dos armados não está extraído** — o que existe é a
## média medida (78 un/frame andando, 222 correndo, 68 de ré).
##
## Então: quando há tabela por-frame, usa-se a tabela; quando não há, usa-se a média por
## frame e o item **fica marcado como parcial**. Nada de fingir fidelidade: `usando_tabela()`
## diz qual caminho está ativo.

const ALTURA_PS1 := 2400                  ## altura do personagem (base do world_scale=808)
## "Casca" do personagem: **NÃO EXISTE no motor** — mantida em 0 só porque testes antigos a
## citam. O laço `0x8004e830` testa o TRAJETO contra os SEGMENTOS da forma do collider (ver
## `room/collision.gd` e ARD.md §3.6) e não infla nada; quem escolhe origem e destino do teste
## é o chamador. O 380 do protótipo era calibração a olho: numa porta de ~1000 unidades ele
## fechava a passagem pelos dois lados, e era isso que travava o andar pelo mapa.
const RAIO_PS1 := 0

## Médias MEDIDAS por frame (unidades PS1), dos bancos ARMADOS do PLW equipado.
const VEL_ANDAR := 78
const VEL_CORRER := 222
const VEL_RE := 68
## Giro medido: 3,386°/frame (anim03) -> em unidades de 12 bits: 3.386/0.087890625 ≈ 38,5
const GIRO_POR_FRAME := 39
## Quick-turn do RE clássico: 180° em ~0,25 s = ~8 ticks -> 2048/8 = 256 unidades por tick
const QUICKTURN_POR_FRAME := 256

enum Acao { PARADO, ANDANDO, CORRENDO, RE, GIRANDO, QUICKTURN, MIRANDO }

var pos := Vector3i.ZERO                  ## unidades PS1 (y = chão)
var facing := 0                           ## ângulo PS1 de 12 bits
var acao: Acao = Acao.PARADO
var hp := 200                             ## `player+0xcc`, máximo 200
var equipped_weapon := 0                  ## `player+0x46`; 0 = desarmada (sem mira)
var frame_da_acao := 0                    ## ticks na ação atual (indexa a tabela de pose)
var quickturn_restante := 0
var _qt_armado := false                   ## borda do gatilho de quick-turn

## Consulta de caminhabilidade: Callable(x:int, z:int) -> bool. Injetada pela sala.
var walkable: Callable = Callable()
## Consulta de TRAJETO: Callable(ax,az,bx,bz) -> bool. É o teste do motor (segmento, não
## ponto). Sem ela, um passo de 78..222 unidades atravessa parede.
var trajeto: Callable = Callable()

## Tabela de root motion por clipe: nome -> Array[int] de deslocamento por frame (un PS1).
var root_por_frame: Dictionary = {}


func usando_tabela(clipe: String) -> bool:
	return root_por_frame.has(clipe)


func carregar_root_motion() -> void:
	## Lê `anim_map.json` -> deslocamento por frame dos clipes que têm medição.
	var d: Variant = AssetIO.json("anim_map.json")
	if not (d is Dictionary):
		return
	var t: Variant = (d as Dictionary).get("timing_e_loop")
	if not (t is Dictionary):
		return
	for chave: String in (t as Dictionary):
		var e: Variant = (t as Dictionary)[chave]
		if not (e is Dictionary):
			continue
		var E: Dictionary = e
		var clipe := str(E.get("anim", ""))
		var arr: Variant = E.get("root_delta_por_frame_world_dx")
		if clipe != "" and arr is Array and (arr as Array).size() > 0:
			var v: Array[int] = []
			for x: float in arr:
				v.append(absi(int(x)))          ## módulo: a direção vem do facing
			root_por_frame[clipe] = v


func velocidade_do_tick(clipe: String, media: int) -> int:
	## Deslocamento deste tick: da tabela por-frame quando existe, senão a média medida.
	if root_por_frame.has(clipe):
		var v: Array = root_por_frame[clipe]
		return int(v[frame_da_acao % v.size()])
	return media


func tick(pad: Pad) -> void:
	## Um passo de gameplay (30 Hz). Tank controls: frente/ré andam na direção atual,
	## esquerda/direita GIRAM no lugar, correr só vale para frente.
	var frente := pad.pressed(Pad.FWD)
	var re := pad.pressed(Pad.BACK)
	var correr := pad.pressed(Pad.RUN)
	var esq := pad.pressed(Pad.HELD_LEFT)
	var dir := pad.pressed(Pad.HELD_RIGHT)
	var mirar := pad.pressed(Pad.AIM) and equipped_weapon != 0

	# --- quick-turn 180°: SÓ na borda do RÉ com o correr JÁ segurado ---
	#
	# A condição anterior ("ré e correr juntos", qualquer ordem) disparava a meia-volta quando
	# se andava de RÉ e se tocava o SHIFT — e uma meia-volta acidental é exatamente "aperto
	# para frente e ele vai para trás" (o relato do usuário: os controles pareciam inverter
	# "em alguns momentos"). Com a borda no RÉ, andar de ré e apertar correr não vira mais.
	# Provisório até P7-03 fixar o mapeamento contra o original.
	var qt_input := pad.just_pressed(Pad.BACK) and correr
	if qt_input and not _qt_armado and quickturn_restante <= 0:
		quickturn_restante = PS1Math.HALF_CIRCLE
	_qt_armado = re and correr
	if quickturn_restante > 0:
		var passo := mini(QUICKTURN_POR_FRAME, quickturn_restante)
		facing = PS1Math.wrap_angle(facing + passo)
		quickturn_restante -= passo
		_set_acao(Acao.QUICKTURN)
		return

	if mirar:
		_set_acao(Acao.MIRANDO)
		return

	# --- giro no próprio eixo ---
	#
	# SINAL (corrigido por observação em jogo, 2026-07-31): girar à DIREITA **diminui** o
	# `facing`. Motivo: a frente é -Z e, no Godot (Y-up), yaw crescente gira no sentido
	# ANTI-horário visto de cima — então somar ao facing viraria para a esquerda. Vendo de
	# cima com X à direita e Z para baixo na tela, o horário leva -Z (frente) para +X
	# (direita), o que corresponde a facing 3072 (270°), isto é, 0 - 1024.
	if esq != dir:
		facing = PS1Math.wrap_angle(facing + (GIRO_POR_FRAME if esq else -GIRO_POR_FRAME))
		if not frente and not re:
			_set_acao(Acao.GIRANDO)

	# --- translação ---
	if frente or re:
		var nova_acao: Acao = Acao.ANDANDO
		var clipe := "arm00"
		var media := VEL_ANDAR
		if re:
			nova_acao = Acao.RE
			clipe = "arm09"
			media = VEL_RE
		elif correr:
			nova_acao = Acao.CORRENDO
			clipe = "arm01"
			media = VEL_CORRER
		_set_acao(nova_acao)
		var d := velocidade_do_tick(clipe, media)
		if re:
			d = -d
		# FRENTE = para onde o MODELO olha, em todos os ângulos: `(+sin(facing), -cos(facing))`.
		#
		# Histórico dos sinais (cada um validado EM JOGO pelo usuário, que é o critério):
		#   • `rotate_xz(0,-d,facing)` = `(-sin,-cos)` — ESPELHO em X do correto: coincidia em
		#     N/S e invertia em ±X... na prática andava de costas perto de 0/2048 (print:
		#     facing 3628, modelo para um lado, passo para o outro);
		#   • `(-sin,+cos)` (1ª correção) — alinhou os eixos mas 180° oposto: W ia para trás;
		#   • `(+sin,-cos)` (atual) — "deu certo, só inverte o W e S" → invertido, fechado.
		# A dedução pelo yaw do nó não decide sozinha porque o mesh tem offset próprio de -90°
		# (`Coords.MESH_YAW_OFFSET_DEG`); quem fecha o conjunto é o teste em jogo.
		var passo := Vector2i((PS1Math.rsin(facing) * d) >> PS1Math.SHIFT,
			(-PS1Math.rcos(facing) * d) >> PS1Math.SHIFT)
		_mover(passo.x, passo.y)
	else:
		if esq == dir:
			_set_acao(Acao.PARADO)
		# O resolver roda TODO tick no motor, não só quando se anda. Com movimento nulo, o
		# caso "dentro" escapa pela face MAIS PRÓXIMA (`0x8004c8b8`, `(mx|mz)==0`) — é o que
		# desencrava suavemente uma posição dentro de caixa inflada (chegada de porta, estado
		# herdado). Sem isto, parado ninguém corrige, e ao andar o escape "contra o movimento"
		# pode exceder o teto e congelar.
		_mover(0, 0)

	frame_da_acao += 1


func _set_acao(a: Acao) -> void:
	if acao != a:
		acao = a
		frame_da_acao = 0


## Resolver de colisão da sala (Collision.resolver). Injetado pelo World ao trocar de sala.
var resolver: Callable = Callable()


func _mover(dx: int, dz: int) -> void:
	## O algoritmo do MOTOR (`0x8004af04`, ver ARD.md §3.7): aplica o passo INTEIRO e deixa a
	## resposta de colisão CORRIGIR a posição — clamp por eixo na face do collider inflado pelo
	## raio (450), escolhido pelo lado de onde se vinha. O deslize nasce daí: andando em
	## diagonal contra uma parede alinhada em X, só o X é corrigido e o Z sobrevive.
	##
	## Duas versões anteriores erraram para lados opostos e o usuário sentiu as duas:
	##   • deslize por tentativa (X, depois Z): escorrega em direções para onde não se anda;
	##   • tudo-ou-nada com o laço `0x8004e830`: para seco em tudo ("esbarra em todo lugar") e
	##     deixa ENTRAR nos móveis pelo canto (as diagonais não fecham a caixa) — foi assim que
	##     a Jill subiu no armário da R100. Aquele laço é um PREDICADO (linha de visão), não o
	##     movimento.
	var alvo := Vector3i(pos.x + dx, pos.y, pos.z + dz)
	if resolver.is_valid():
		var r: Collision.Resolvido = resolver.call(pos.x, pos.z, alvo.x, alvo.z, nivel())
		if r.rejeitado:
			return                                   # flags 0x100: o chamador cancela o passo
		pos = Vector3i(r.x, pos.y, r.z)
		return
	if _livre(alvo.x, alvo.z):
		pos = alvo


func nivel() -> int:
	## Andar do personagem: o Y do RE3 é o nível do piso em múltiplos de -1800 (0 = térreo).
	return pos.y / -Collision.ALTURA_POR_NIVEL


func _pode(x: int, z: int) -> bool:
	return walkable.call(x, z) if walkable.is_valid() else true


func _livre(x: int, z: int) -> bool:
	## Prefere o teste de TRAJETO (o do motor); cai no de ponto se a sala não o fornecer.
	if trajeto.is_valid():
		return trajeto.call(pos.x, pos.z, x, z)
	return _pode(x, z)


func clipe_atual() -> String:
	## Clipe de animação da ação atual (bancos ARMADOS: a Jill anda sempre com arma).
	match acao:
		Acao.ANDANDO:
			return "arm00"
		Acao.CORRENDO:
			return "arm01"
		Acao.RE:
			return "arm09"
		Acao.GIRANDO, Acao.QUICKTURN:
			return "arm00"
		Acao.MIRANDO:
			return "arm02"
		_:
			return "arm02"


func health_zone() -> int:
	## Zona de saúde (0 = FINE ... 2 = DANGER) — o tier de animação do EXE sai daqui
	## (tabela 3×3 em `0x8009cde0`). HP máximo 200.
	if hp > 130:
		return 0
	return 1 if hp > 60 else 2
