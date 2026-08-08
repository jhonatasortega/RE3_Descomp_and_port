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
## HP MÁXIMO e ESTADO, com os endereços do EXE que a tela de status lê:
##   `gs+0x2558` (s16) = HP atual · `gs+0x255a` (u16) = **HP máximo** · `gs+0x255e` = flags
## O `hp_max` é o que a tabela de cura usa ("cheio" = `(u8)maxHP`, `1/2` = `maxHP >> 1`), e as
## flags têm `0x0100` = VIRUS e `0x0200` = VENENO (`0x8006e598` decide a condição por elas).
var hp_max := 200
var status := 0                            ## bits de `gs+0x255e`


func envenenado_get() -> bool:
	return (status & 0x0200) != 0
var equipped_weapon := 0                  ## `player+0x46`; 0 = desarmada (sem mira)

## ── MIRA E TIRO (rotina 5 → rotina 7 do EXE) ──
## Fonte: `docs/decomp/notes/exe_combat.md` §1-2 (o `aim_shoot` está 100% decompilado lá) e as
## tabelas em `data/re3_aim_shoot.json` (`tools/exe_aim_shoot.py`).
##
## A rotina 7 (`0x8003a7d8`) tem SUB-ESTADO em `player+6`:
##   0 `0x8003a88c` levanta a arma (anim 13, toca SFX) → sub 1
##   1 `0x8003a8cc` interpola o pitch (`player+0xc0 -= 0x28`, clamp 0) → sub 2
##   2 `0x8003a90c` mira e faz AUTO-LOCK; pose 14/15/16 por tier (17 no tier 3) e
##     `player+0x6e = (tier << 9) + 0x800`
##   3 `0x8003adc0` segura e ATIRA; no fim volta para a rotina 5 (rearme)
## `T1 r7` é stub (`jr $ra`): **durante a mira o player não anda** — o facing fica travado.
enum Mira { LEVANTAR, PITCH, MIRANDO_ALVO, FOGO }
const MIRA_PITCH_PASSO := 0x28            ## `player+0xc0 -= 0x28` (sub 1)
const MIRA_ARCO := 0x1000                 ## clamp do arco do auto-lock (~90°)
const MIRA_ALCANCE := 3000                ## meia-extensão do descritor `0x80098064`
const MIRA_LARGURA := 1000                ## idem, largura
const MIRA_ALTURA := 1600                 ## idem, altura
## Sensibilidade do mouse na mira (**declarado**: escolha do port). 8 unidades de ângulo por
## pixel ≈ 512 px para uma volta completa (4096 unidades = 360°). `MIRA_MOUSE_ZONA` é a zona morta
## vertical em pixels antes de trocar a altura da mira.
const MIRA_MOUSE_GIRO := 8
const MIRA_MOUSE_ZONA := 30
var mira_mouse_y := 0
## ── PITCH CONTÍNUO, **SÓ NO MOUSE** (pedido do usuário) ──
## No pad o RE3 tem 3 posições em Y e ponto (o pitch do EXE é em degraus de `0x200`:
## `player+0x6e = (tier << 9) + 0x800`, `0x8003ac5c`). Com o MOUSE dá para mirar fino, então aqui
## existe um pitch contínuo em unidades de ângulo de 12 bits, que **só o mouse move**. A POSE
## continua sendo uma das três (cai na mais próxima) — o que fica contínuo é o ÂNGULO, e é ele que
## a mira laser desenha. **Declarado: extensão do port.**
const MIRA_PITCH_POR_PIXEL := 6           ## unidades de ângulo por pixel de mouse
const MIRA_PITCH_TETO := 0x500            ## ~44° para cima e para baixo
const MIRA_PITCH_ZONA := 0x150            ## acima disso a POSE troca para alta/baixa
const MIRA_PITCH_DEGRAU := 0x200          ## o degrau do EXE (`(tier << 9)`), usado pelo W/S
var mira_pitch_y := 0                     ## pitch contínuo do mouse (0 = horizontal)
## ── SÓ 3 PONTOS NO EIXO Y, E ISSO É DO JOGO ──
## O usuário observou que a mira vertical tem apenas 3 posições. É o que o dado tem e o que o EXE
## faz: o banco 2 do PLW traz **três** poses de hold (`mira02` médio, `mira04` alto, `mira06`
## baixo) e o pitch do EXE é **em degraus** — `player+0x6e = (tier << 9) + 0x800` (`0x8003ac5c`),
## ou seja passo de `0x200` ≈ 17,6°, com 4 tiers. Não existe mira livre em Y no RE3.
## (O banco também tem `mira01`/`mira03`/`mira05`, de 20 quadros, que são as TRANSIÇÕES entre os
## holds. Cheguei a tocá-las achando que resolvia um "salto" — o usuário esclareceu que não era
## isso, então desfiz: a troca de pose é direta, como no original.)
const LEVANTAR_QUADROS := 6               ## duração do sub 0 (declarado: não medi o nº de quadros)
var mira_sub: Mira = Mira.LEVANTAR
var mira_tier := 0                        ## 0..3 pela elevação do alvo (auto-lock)
## Lado da elevação: +1 alvo ACIMA, -1 ABAIXO, 0 na mesma altura. No PS1 o Y cresce para BAIXO,
## então "acima" é `p.y < pos.y`. O EXE tira a altura do part-id travado (`player+0xc7`), que exige
## hitbox de osso do inimigo; aqui vem da elevação. **Declarado.**
var mira_alto := 0
var mira_pitch := 0                       ## `player+0x6e` = (tier << 9) + 0x800 (sub 2)
## `player+0xc0` = OFFSET de mira, que o sub 1 interpola para 0 de 0x28 em 0x28. São campos
## DIFERENTES do pitch: o `+0xc0` sai da rotina do ponto do cano (`0x80018d34`) e eu havia
## juntado os dois, o que travava o sub 1 por 52 ticks. O valor INICIAL do `+0xc0` não foi
## medido — uso 3 passos (declarado).
var mira_offset := 0
const MIRA_OFFSET_INICIAL := 0x28 * 3
var mira_alvo := -1                       ## índice do spawn travado (`player+0x170`)
## ── DIFICULDADE E MIRA (pedido do usuário; **declarado: regra do port, não medida no EXE**) ──
##   FACIL   → mira LASER visível + AUTO-MIRA: o travamento gruda no inimigo e o tiro vai nele;
##   NORMAL  → sem laser, com travamento (é o comportamento do original);
##   DIFICIL → sem laser e **sem travar**: o tiro sai na direção em que o corpo está.
## O auto-lock do EXE (`0x800445c8` em laço por `0x8001e900`) não tem chave de dificuldade que eu
## tenha achado; a diferença por modo é opção do port.
enum Dificuldade { FACIL, NORMAL, DIFICIL }
var dificuldade: Dificuldade = Dificuldade.NORMAL


func mira_com_laser() -> bool:
	return dificuldade == Dificuldade.FACIL


func mira_trava() -> bool:
	return dificuldade != Dificuldade.DIFICIL
var mira_quadro := 0                      ## quadro dentro da animação de mira
var tiro_pendente := -1                   ## quadro em que o tiro sai (do timing por arma)
var recuo := 0                            ## quadros de recuo/rearme
var municao_vazia := false                ## clique seco (sem munição)
## Alvos possíveis: Callable() -> Array[Vector3i] (posições dos inimigos, unidades PS1).
var alvos: Callable = Callable()
signal atirou(alvo: int, de: Vector3i, para: Vector3i)
signal mirou(alvo: int, tier: int)
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
		_tick_mira(pad)
		return
	if acao == Acao.MIRANDO:
		_sair_da_mira()

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
			## ── POSES DE MIRA: banco 2 do `.PLW`, exportado como `mira00..mira07` ──
			## O de-para de osso foi provado: o **banco 2 (9 ossos) = ossos 0..8 do PLD = SUPERIOR**
			## (raiz, cabeça, os dois braços, pelve) e o **banco 1 (7 ossos) = 0, 9..14 = pernas** —
			## o inverso do que a doc dizia. A aplicação é **substituição do subconjunto**, não
			## aditiva, e cada `miraNN` já vem sem trilha para `bone09..14` e sem translação de
			## raiz, então tocá-lo sozinho dá o efeito. Papel medido pela altura do punho direito:
			##   `mira00` 10 quadros = LEVANTAR (punho +291 → −598) · `mira02` = hold MÉDIA
			##   `mira04` = hold ALTA · `mira06` = hold BAIXA · `mira07` 32 quadros = TIRO + recuo
			## (o quadro do tiro do timing `0x8009cf28` — 12 no handgun — cai dentro desses 32).
			## Ver `docs/decomp/notes/plw.md` §9.
			## CORREÇÃO (achado do usuário): eu usava `mira07` como "tiro + recuo", rótulo que o
			## agente deduziu da altura do punho. **É a RECARGA** — 32 quadros, quase 1 s, é tempo
			## de recarregar, não de um tiro. E casa com o EXE: o tiro **não tem clipe próprio**,
			## ele sai num QUADRO DENTRO da animação de mira (a tabela `0x8009cf28` guarda esse
			## quadro: 12 no handgun). Então atirar MANTÉM a pose de mira.
			## `mira07` fica reservado para a recarga, quando ela existir.
			if mira_sub == Mira.LEVANTAR:
				return "mira00"
			if mira_alto > 0:
				return "mira04"
			if mira_alto < 0:
				return "mira06"
			return "mira02"
			## ── (histórico) POR QUE A POSE ERA O IDLE ARMADO ──
			## O EXE grava em `player+0xc8` os índices **13** (levantar), **14/15/16** (mira por
			## tier), **17** (tier 3) e **19/20** (promoção de alvo alto). Eu havia mapeado direto
			## para os clipes `arm13..arm17`, que são as **seqs 13..17 do BANCO 0** do `.PLW` — e o
			## banco 0 é o de LOCOMOÇÃO de corpo inteiro. Resultado: a Jill mirava **ajoelhada**
			## (o usuário apontou: "essa pose de mirar ajoelhada não é a padrão do game").
			##
			## As poses de mira estão nos **bancos 1 e 2** do `.PLW` (bank1 = 7 ossos/8 seqs,
			## bank2 = 9 ossos/8 seqs, os "overlays parciais de mira/gesto" —
			## `docs/formatos/animacoes_player.md` §9-11 e `decomp/notes/plw.md` §5), e os três
			## slots do EXE `player+0xf4/0xf8/0x100` são justamente os três bancos. O
			## `pld2gltf.py::build_armed_clips` **só extrai o banco 0**, então esses clipes ainda
			## não existem no `.glb`.
			## Até extrair os bancos 1/2 e compor o overlay, a mira usa o **idle armado**, que é a
			## pose de pé com a arma na mão — errado no braço, certo no corpo. Declarado.
			return "arm02"
		_:
			return "arm02"


func _sair_da_mira() -> void:
	## Soltar o botão de mira volta ao repouso e RESETA o sub-estado (o EXE volta pela rotina 1).
	mira_sub = Mira.LEVANTAR
	mira_quadro = 0
	tiro_pendente = -1
	mira_alvo = -1
	mira_mouse_y = 0
	mira_pitch_y = 0
	municao_vazia = false
	_set_acao(Acao.PARADO)


func _tick_mira(pad: Pad) -> void:
	## Rotina 7 do EXE, sub-estado em `player+6`. O `T1 r7` é stub, ou seja **o player não ANDA**
	## mirando — mas GIRAR mirando é o que o jogo faz (e o usuário cobrou: "não consigo manter a
	## mira com wsad"). Então: A/D giram no lugar, W/S escolhem a altura da mira (alta/baixa) quando
	## não há alvo travado. **Declarado**: o giro durante a mira não foi medido no EXE (lá o facing é
	## forçado ao alvo no fim do sub 3, `0x8003afc8`).
	_set_acao(Acao.MIRANDO)
	var esq_m := pad.pressed(Pad.HELD_LEFT)
	var dir_m := pad.pressed(Pad.HELD_RIGHT)
	if esq_m != dir_m:
		facing = PS1Math.wrap_angle(facing + (GIRO_POR_FRAME if esq_m else -GIRO_POR_FRAME))
	## MIRA COM O MOUSE (pedido do usuário; extensão do port — o pad do PS1 é digital):
	## o movimento HORIZONTAL do ponteiro gira o corpo e o VERTICAL escolhe a altura da mira.
	## O giro por tick é limitado a 3× o giro normal para o ponteiro não teleportar a Jill.
	if pad.mouse_dx != 0:
		var giro := clampi(-pad.mouse_dx * MIRA_MOUSE_GIRO, -GIRO_POR_FRAME * 3,
			GIRO_POR_FRAME * 3)
		facing = PS1Math.wrap_angle(facing + giro)
	if pad.mouse_dy != 0 and mira_alvo < 0:
		## ponteiro para BAIXO (dy > 0) abaixa a mira: pitch NEGATIVO
		mira_pitch_y = clampi(mira_pitch_y - pad.mouse_dy * MIRA_PITCH_POR_PIXEL,
			-MIRA_PITCH_TETO, MIRA_PITCH_TETO)
		mira_mouse_y = -mira_pitch_y / MIRA_PITCH_POR_PIXEL    ## espelho em pixels, para o HUD
		if mira_pitch_y > MIRA_PITCH_ZONA:
			mira_alto = 1                      ## pose ALTA
		elif mira_pitch_y < -MIRA_PITCH_ZONA:
			mira_alto = -1                     ## pose BAIXA
		else:
			mira_alto = 0
	if mira_alvo < 0:
		if pad.pressed(Pad.FWD):
			mira_alto = 1                      ## W = mira ALTA
			mira_pitch_y = MIRA_PITCH_DEGRAU   ## no pad o pitch é em DEGRAU, como no EXE
		elif pad.pressed(Pad.BACK):
			mira_alto = -1                     ## S = mira BAIXA
			mira_pitch_y = -MIRA_PITCH_DEGRAU
		elif pad.just_released(Pad.FWD) or pad.just_released(Pad.BACK):
			mira_alto = 0
	mira_quadro += 1
	if recuo > 0:
		recuo -= 1
	match mira_sub:
		Mira.LEVANTAR:
			# sub 0: levanta a arma (anim 13) e passa para a interpolação do offset
			if mira_quadro >= LEVANTAR_QUADROS:
				mira_sub = Mira.PITCH
				mira_quadro = 0
				mira_offset = MIRA_OFFSET_INICIAL
		Mira.PITCH:
			# sub 1: `player+0xc0 -= 0x28` com clamp em 0 (`0x8003a8cc`)
			mira_offset = maxi(0, mira_offset - MIRA_PITCH_PASSO)
			if mira_offset == 0:
				mira_sub = Mira.MIRANDO_ALVO
				mira_quadro = 0
		Mira.MIRANDO_ALVO:
			# sub 2: AUTO-LOCK — varre os alvos, trava no que está no arco e define o tier
			mira_alvo = _travar_alvo()
			mira_pitch = (mira_tier << 9) + 0x800        ## `player+0x6e = (tier<<9)+0x800`
			mirou.emit(mira_alvo, mira_tier)
			mira_sub = Mira.FOGO
			mira_quadro = 0
		Mira.FOGO:
			# sub 3: segura mirando e ATIRA no gatilho
			mira_alvo = _travar_alvo()                    ## o alvo é reavaliado enquanto segura
			if mira_alvo >= 0 and dificuldade == Dificuldade.FACIL:
				_girar_para_alvo(mira_alvo)               ## AUTO-MIRA: o corpo vira para o alvo
			if tiro_pendente >= 0:
				if mira_quadro >= tiro_pendente:
					_resolver_tiro()
				return
			if (pad.just_pressed(Pad.TIRO) or pad.just_pressed(Pad.ACAO)) and recuo == 0:
				_puxar_gatilho()


func _puxar_gatilho() -> void:
	## Gatilho: `player+0xe3` é a máquina de debounce do EXE; aqui a borda do botão basta, porque
	## o `Pad.just_pressed` já é borda.
	##
	## CORREÇÃO: eu havia escrito que o EXE escolhe o SFX "seco/tiro/vazio" pelos bits
	## `0x200`/`0x400` de `player+0xe4` — isso veio da minha nota em `exe_combat.md` e **não se
	## sustenta**: não existe esse `andi` nem leitura de `+0xe4` em `0x800776b0`. O som do TIRO é
	## `cat 0 / id 11`, pedido em `0x8003ad6c` (medido na varredura de áudio, ver
	## `docs/decomp/notes/exe_audio.md`). Clique seco sem munição segue sendo comportamento do
	## port, declarado.
	var st := _estado()
	var qtd := int(st.equipped_qtd()) if st != null else 0
	if qtd <= 0:
		municao_vazia = true
		recuo = 8
		return
	municao_vazia = false
	tiro_pendente = quadro_do_tiro()
	mira_quadro = 0


func quadro_do_tiro() -> int:
	## Quadro em que o tiro sai, do timing `0x8009cf28` (`byte2 & 0x7f`). O de-para
	## **item → índice de arma `w`** não foi achado no EXE (ver `tools/exe_aim_shoot.py`), então:
	## faca = w0 (50 quadros) e o resto = w1 (12, o do handgun). Declarado.
	var st := _estado()
	var id := int(st.equipped_item_id()) if st != null else 0
	return 50 if id == 0x01 else 12


func _resolver_tiro() -> void:
	## Sai o tiro: gasta 1 de munição, aplica o HITSCAN e entra em recuo/rearme.
	##
	## HITSCAN (`0x80044804`, via o handler genérico `0x8003eb28`): o EXE inicia a distância
	## mínima em `0x7fffffff`, itera o array de personagens e aplica `char+0xcc -= dano` **no
	## mesmo quadro** — não existe entidade-bala. Aqui o alvo travado pelo auto-lock é o alvo do
	## tiro, e o dano NÃO é aplicado porque **o port ainda não tem entidade de inimigo com HP**:
	## o sinal `atirou` leva o alvo para quem quiser tratar. Declarado, não fingido.
	var st := _estado()
	if st != null:
		st.gastar_municao_equipada(1)
	## SOM DO TIRO: `cat 0 / id 11`, pedido em `0x8003ad6c` (de-para provado em
	## `docs/decomp/notes/exe_audio.md`). O tocador é o `Game.sfx`; o player só diz QUANDO.
	if sfx != null:
		sfx.tiro()
	var de := pos
	var para := pos + Vector3i(
		PS1Math.rsin(facing) * MIRA_ALCANCE >> PS1Math.SHIFT, 0,
		-PS1Math.rcos(facing) * MIRA_ALCANCE >> PS1Math.SHIFT)
	atirou.emit(mira_alvo, de, para)
	tiro_pendente = -1
	mira_quadro = 0
	recuo = 10                                    ## rearme: o EXE volta para a rotina 5
	mira_sub = Mira.LEVANTAR


func _girar_para_alvo(i: int) -> void:
	## No FÁCIL o corpo gira para o alvo travado. O EXE faz isso no fim do sub 3
	## (`0x8003afc8`: pega `player+0x15c` e chama `0x80018110`, que gira `player+0x6e` para o
	## alvo); aqui o giro é imediato, o que é a "auto-mira" pedida.
	if not alvos.is_valid():
		return
	var lista: Array = alvos.call()
	if i < 0 or i >= lista.size():
		return
	var p: Vector3i = lista[i]
	## Sinal: `facing = 0` aponta para **-Z** (a frente do jogo), e `angle_of_xz` é `atan2(x, z)`
	## — então o Z entra NEGADO. Sem isso a auto-mira girava 180° (medido: alvo em -Z dava 2048).
	facing = PS1Math.angle_of_xz(p.x - pos.x, -(p.z - pos.z))


func _travar_alvo() -> int:
	## AUTO-LOCK (`0x800445c8` chamado em laço por `0x8001e900`): rotaciona o alvo para o espaço
	## local da mira e testa a caixa de meia-extensões do descritor `0x80098064`
	## (3000 de alcance, ±1000 de largura, 1600 de altura), com clamp de arco de ±0x1000.
	## Devolve o índice do alvo mais PRÓXIMO dentro da caixa, ou -1.
	## NÃO zera `mira_alto` aqui: sem alvo travado a altura é ESCOLHA do jogador (W/S ou o mouse),
	## e zerar todo tick apagava essa escolha — era o que fazia a mira do mouse não subir/descer.
	mira_tier = 0
	if not mira_trava():
		return -1                          ## DIFÍCIL: não gruda em ninguém
	if not alvos.is_valid():
		return -1
	var lista: Array = alvos.call()
	var melhor := -1
	var melhor_d := 1 << 30
	for i in lista.size():
		var p: Vector3i = lista[i]
		var dx := p.x - pos.x
		var dz := p.z - pos.z
		# para o espaço local da mira: adiante = -Z rodado por `facing`
		var sin_f := PS1Math.rsin(facing)
		var cos_f := PS1Math.rcos(facing)
		var frente := (-dz * cos_f + dx * sin_f) >> PS1Math.SHIFT
		var lado := (dx * cos_f + dz * sin_f) >> PS1Math.SHIFT
		if frente < 0 or frente > MIRA_ALCANCE:
			continue
		if absi(lado) > MIRA_LARGURA:
			continue
		var dy := absi(p.y - pos.y)
		if dy > MIRA_ALTURA:
			continue
		var d := frente * frente + lado * lado
		if d < melhor_d:
			melhor_d = d
			melhor = i
			# TIER pela ELEVAÇÃO do alvo: 0 = na mesma altura ... 3 = bem acima/abaixo.
			# O EXE tira o tier do part-id travado (`player+0xc7`), que exige hitbox de osso —
			# o port não tem osso de inimigo ainda, então derivo da altura. **Declarado.**
			mira_tier = clampi(int(dy / 400), 0, 3)
			## LADO da elevação: no PS1 o Y cresce para BAIXO, então alvo ACIMA é `p.y < pos.y`.
			var acima := 1 if p.y < pos.y else (-1 if p.y > pos.y else 0)
			mira_alto = acima if mira_tier > 0 else 0
	return melhor


## O `GameState` vem injetado pela sala (o player não conhece a árvore de cena). `null` = teste
## isolado, e aí o tiro roda sem gastar munição.
var estado: GameState = null
## Tocador de efeitos (`Game.sfx`), injetado pela sala. `null` = teste isolado, sem som.
var sfx: Sfx = null


func _estado() -> GameState:
	return estado


func health_zone() -> int:
	## Zona de saúde (0 = FINE ... 2 = DANGER) — o tier de animação do EXE sai daqui
	## (tabela 3×3 em `0x8009cde0`). HP máximo 200.
	if hp > 130:
		return 0
	return 1 if hp > 60 else 2
