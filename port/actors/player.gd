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

enum Acao { PARADO, ANDANDO, CORRENDO, RE, GIRANDO, QUICKTURN, MIRANDO, CENA, SUBINDO }

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
## ── RECUO: É CLIPE PRÓPRIO, e o tiro sai no QUADRO 0 ──
## Correção de uma premissa minha que estava errada nas três pernas (achado provado em
## `docs/decomp/notes/recuo_tiro.md`):
##   • no subestado de fogo, `0x8003f248..0x8003f268` faz `a1 = 0x00030001`,
##     `v0 = *(0x8009cd3d)*2 + a1` e `sw v0, 0xc8` → **seqs 1/3/5 do banco 2 do PLW**, 20 quadros
##     cada, UMA POR ALTURA de mira. Ou seja: o recuo é o clipe `mira01`/`mira03`/`mira05` — os
##     mesmos que eu havia rotulado de "rampas de transição";
##   • o tiro sai no **quadro 0** dele (`0x80040fac`: `lbu 0xc9` e `bnez → return`), não no meio;
##   • o `byte2 & 0x7f` do timing `0x8009cf28` (12 no handgun) é o quadro a partir do qual
##     **soltar a mira CORTA o recuo** (`0x8003f3dc`) — não é o quadro do disparo;
##   • `mira07` (32 quadros) é a **recarga** (`0x8003f554`), como o usuário reconheceu de olho.
const RECUO_QUADROS := 20                 ## os 20 quadros do clipe de recuo (medido)
var tiro_pendente := -1                   ## mantido só para o diag/HUD: -1 = sem tiro em curso
var recuo := 0                            ## quadros restantes do clipe de recuo
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
	##
	## ── AÇÃO 4 (roteirizada) vem ANTES de tudo ──
	## Numa cinemática de script o corpo não é do jogador: o motor põe `player+4 = (rotina<<8)|4`
	## e o script escreve a animação e a posição. Ver `_tick_cena`.
	if cena != null:
		if cena.viva():
			_tick_cena()
			return
		sair_da_cena()
	# ── ROTINA 9 (subir/descer degrau) em curso: ela dirige o corpo, o pad só a mantém ──
	if subir.ativo:
		_tick_degrau(pad)
		return
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
		## soltar a mira NO MEIO do recuo só corta depois do quadro de corte da arma
		if recuo > 0 and (RECUO_QUADROS - recuo) < quadro_do_corte():
			_tick_mira(pad)
			return
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

	# É aqui que r1/r2 decidem entrar na rotina 9 (`0x800397c0`: `player+4 = 0x901`).
	_detectar_degrau(frente or re)
	frame_da_acao += 1


func _set_acao(a: Acao) -> void:
	if acao != a:
		acao = a
		frame_da_acao = 0


# ═══════════════ ESTADO CENA — a AÇÃO 4 do motor, "roteirizada" (0x80056dc0) ═══════════════
# Durante uma cinemática de script quem dirige o corpo é a `Cena` (`port/script_vm/cena.gd`),
# que roda as threads do SCD da sala. No motor isso é `player+4 = (rotina << 8) | 4` — **ação
# 4** — com o índice de sequência do EDD escrito DIRETO em `player+0xc8`; não há detecção de
# contato nem gate de colisão (é o que permite a Jill subir na lixeira do `R10D`, onde nenhum
# objeto é escalável). Os quatro pontos da §6.1 de `docs/decomp/notes/cena_r10d.md`:
#
#   1. ENTRAR   `entrar_em_cena()` — o pad deixa de ser lido, a cena manda;
#   2. CLIPE    evento `anim` -> `cena_seq` (o `player+0xc8`) -> clipe `anim%02d`;
#   3. ANDAR    evento `ir` -> anda até (x,z) e chama **`cena.chegou(bit)`** na chegada, que é o
#               que acende o bit do banco 4 e solta o `while (não flag)` da thread (§3.2);
#   4. SAIR     `sair_da_cena()` — `player+4` volta a `1`, como faz a função 37.

## Chave do WORK do player na `Cena`: `0x47 01 00` = tabela `0x80010b60` entrada 1
## (`*(0x800ccd94)` = o player) com `n = 0`.
const CENA_WORK_PLAYER := "1:0"
## Membro `0x0d` = `player+0x6e` = ÂNGULO (a cena gira o corpo por aqui: `41 0d …`).
const CENA_MEMBRO_ANGULO := 0x0D
## De-para SEQ do EDD -> clipe, o MESMO que `subir.gd` usa: `anim%02d` = as 22 sequências do
## banco embutido no `PL00.PLD`.
## 🟡 **DECLARADO, e com uma ressalva honesta**: a cena de saída do `R10D` pede as SEQ
## **8, 7, 4, 9, 5, 6 e 10** nessa ordem, e só o par **6/7** está PROVADO (`subir.gd` §3, pelos
## stores `0x8003b39c`/`0x8003b3c4`). As **SEQ 8 e 10 não estão nesse par** e
## `docs/formatos/animacoes_player.md` rotula as duas **por render, não por prova** (8 =
## "abaixar e apanhar", 10 = "correr"). Qual dos dois bancos o motor usa aqui — `animNN` do PLD
## ou `armNN` (banco 0 do PLW) — também segue em aberto, exatamente como em `subir.gd`.
const CENA_CLIPE_FMT := "anim%02d"
## Enquanto o `0x81` leva o corpo até um ponto, o script **não** manda SEQ: o opcode carrega uma
## ROTINA (`byte@+2`) e a tabela de animação por rotina não foi decodificada. O port toca o andar
## armado. **DECLARADO** (escolha do port, não medição).
const CENA_CLIPE_ANDAR := "arm00"

## Cinemática que está dirigindo o corpo, ou `null`. Instalada pelo `world.gd`.
var cena: Cena = null
## O `player+0xc8` que o `0x80` gravou (-1 = nenhum).
var cena_seq := -1
## O `byte@+1` do `0x80` / `byte@+2` do `0x81`: a ROTINA que o motor põe no byte alto de
## `player+4`. Guardado para diagnóstico — a tabela de animação por rotina não foi medida.
var cena_rotina := 0
## Destino do `0x81` (`w+0xd4`/`w+0xd6`) e o BIT do banco 4 a acender na chegada (`w+0x146`).
var cena_destino := Vector3i.ZERO
var cena_bit := -1
## Quantos `0x81` foram IGNORADOS por vir com destino (0,0) — ver `_consumir_eventos_da_cena`.
var cena_ir_ignorados := 0
var _cena_lidos := 0                      ## eventos da linha do tempo já consumidos
var _cena_espelho := Vector3i.ZERO        ## o que este tick escreveu na cena no quadro anterior
var _cena_espelho_ang := 0
var _cena_tem_espelho := false


func entrar_em_cena(c: Cena) -> void:
	cena = c
	cena_seq = -1
	cena_rotina = 0
	cena_bit = -1
	cena_destino = Vector3i.ZERO
	cena_ir_ignorados = 0
	_cena_lidos = 0
	_cena_tem_espelho = false
	_set_acao(Acao.CENA)


func sair_da_cena() -> void:
	## Fim da cena: `player+4 = 1` (a função 37 do `R10D` apaga os dois bits que a cena acendeu,
	## `4d 02 07 00` e `4d 01 1c 00`). O corpo volta ao repouso e o pad volta a valer.
	if cena == null:
		return
	cena = null
	cena_seq = -1
	cena_rotina = 0
	cena_bit = -1
	_cena_tem_espelho = false
	_set_acao(Acao.PARADO)


func em_cena() -> bool:
	return cena != null


func sincronizar_com_a_cena() -> void:
	## Instala a posição/ângulo do port no ator da cena **antes** de as threads rodarem, e guarda
	## o espelho. É obrigatório porque o script mexe na posição de forma RELATIVA (`0x42` →
	## `0x20` → `0x41`, isto é `player+0x34 += k`): se a cena tiver sido aberta antes de o spawn
	## ser aplicado — é o caso da cinemática de ENTRADA, que abre na carga da sala — o `+=` do
	## primeiro quadro sairia de uma posição velha e o corpo apareceria no lugar errado.
	if cena == null:
		return
	cena.por_ator(1, 0, pos, facing)
	_cena_espelho = pos
	_cena_espelho_ang = facing
	_cena_tem_espelho = true


func _tick_cena() -> void:
	if acao != Acao.CENA:
		_set_acao(Acao.CENA)
	# 1) POSIÇÃO/ÂNGULO que o SCRIPT escreveu à mão nos membros (`0x40`/`0x41` sobre `0x09`/`0x0b`
	#    /`0x0d`). É assim que a subida do `R10D` acontece: 10 quadros de `+70` em X e `+40` em Z,
	#    mais 10 de `+5` em X — `cena_r10d.md` §6.3. Só se aceita o valor da cena quando ele MUDOU
	#    em relação ao que este tick escreveu no quadro anterior; senão o dono da posição continua
	#    sendo o port (a cena de entrada, por exemplo, é aberta na carga da sala, antes de o spawn
	#    ser aplicado — sem esta guarda o corpo saltaria para a posição velha).
	var p: Vector3i = cena.ator_pos(1, 0)
	if _cena_tem_espelho and (p.x != _cena_espelho.x or p.z != _cena_espelho.z):
		pos.x = p.x
		pos.z = p.z
	var ang: int = cena.membro_get(1, 0, CENA_MEMBRO_ANGULO)
	if _cena_tem_espelho and ang != _cena_espelho_ang:
		facing = PS1Math.wrap_angle(ang)
	# 2) eventos novos da linha do tempo (só os do WORK do player)
	_consumir_eventos_da_cena()
	# 3) o deslocamento do `0x81`
	if cena_bit >= 0:
		_andar_na_cena()
	# 4) devolve o corpo para a cena: as threads leem X/Z/ângulo por `member_get` para decidir o
	#    que já aconteceu. E guarda o espelho para a comparação do próximo quadro.
	cena.por_ator(1, 0, pos, facing)
	_cena_espelho = pos
	_cena_espelho_ang = facing
	_cena_tem_espelho = true
	frame_da_acao += 1


func _consumir_eventos_da_cena() -> void:
	var evs: Array[Dictionary] = cena.eventos
	while _cena_lidos < evs.size():
		var e: Dictionary = evs[_cena_lidos]
		_cena_lidos += 1
		if str(e.get("work", "")) != CENA_WORK_PLAYER:
			continue                          ## `anim`/`ir` de outro ator (as 5 entidades da rua)
		match str(e.get("tipo", "")):
			"anim":
				cena_seq = int(e.get("seq", -1))
				cena_rotina = int(e.get("rotina", 0))
				frame_da_acao = 0
			"ir":
				# NÃO cancela um `ir` anterior por causa de um `anim`: no motor o `0x80` só
				# escreve `+0xc8`/`+4`, o destino do `0x81` (`+0xd4`/`+0xd6`) continua lá.
				var dx := int(e.get("x", 0))
				var dz := int(e.get("z", 0))
				if dx == 0 and dz == 0:
					## ⚠ **ACHADO DO ENGATE** (não estava no doc): o `0x81` que a cena de ENTRADA
					## do `R10D` manda para o player no quadro 218 vem com destino **(0,0)** e
					## `rotina 6` — campo ZERADO, o mesmo padrão da chegada da porta roteirizada.
					## Andar até (0,0) arrasta a Jill ~1500 unidades para FORA do beco (medido no
					## engate). A ROTINA do `0x81` (`byte@+2`, jump-table `0x80010be8`) **não foi
					## decodificada**, então aqui o port não anda e não acende o bit: só conta.
					## Nenhuma thread da entrada espera por esse bit — a cena fecha nos mesmos
					## 260 quadros com ou sem ele (medido).
					cena_ir_ignorados += 1
					continue
				cena_rotina = int(e.get("rotina", 0))
				cena_bit = int(e.get("bit", 0))
				cena_destino = Vector3i(dx, pos.y, dz)
				frame_da_acao = 0


func _andar_na_cena() -> void:
	## O `0x81` (`0x80056e5c`) grava só DESTINO e rotina; a velocidade sai de uma tabela por
	## classe (`0x8009e52c`/`0x8009e5cc`, indexada por `w+0x4a`) que **não foi decodificada**.
	## 🟡 Uso `VEL_ANDAR` (78) — o mesmo número de `Cena.VELOCIDADE_DECLARADA`, para não haver
	## dois no port. **Sem colisão**: a cena carrega o corpo por cima do cenário (ela até apaga o
	## gate `player+0x12d`, §6.4), então aqui não passa pelo `_mover`.
	var dx := cena_destino.x - pos.x
	var dz := cena_destino.z - pos.z
	var d := int(sqrt(float(dx * dx + dz * dz)))
	if d <= VEL_ANDAR:
		pos.x = cena_destino.x
		pos.z = cena_destino.z
		var bit := cena_bit
		cena_bit = -1
		## O que o motor faz na chegada: `0x800169f0  jal 0x800788dc` com `a0 = 0x800d1fc0`
		## (banco 4) e `a1 = w+0x146` — acende o bit e solta o `while (não flag)` da thread.
		cena.chegou(bit)
		return
	## O corpo olha para onde anda. **DECLARADO**: o `0x81` tem uma rotina de giro que eu não
	## decodifiquei. `facing = 0` aponta para -Z, então o Z entra NEGADO em `angle_of_xz`.
	facing = PS1Math.angle_of_xz(dx, -dz)
	pos.x += dx * VEL_ANDAR / d
	pos.z += dz * VEL_ANDAR / d


# ══════════ DEGRAU — SUBIR e DESCER são AÇÕES DO JOGADOR (a rotina 9 de verdade) ══════════
#
# O dono está certo, e a conclusão de `subir.gd` §5 ("não existe subir no R10D") vinha de olhar
# no lugar errado: o que se escala ali **não é objeto `0x7f`, é a GEOMETRIA DE COLISÃO** — uma
# plataforma de um nível com um registro `forma 8` encostado no nível de cima. A dedução, os
# endereços e os números estão em `World._degraus_da_sala()` e em `cena_r10d.md` §10. E é a
# **DESCIDA no flanco oeste que cai dentro da caixa do AOT `sce 5`** — ou seja é ela que dispara
# a cutscene de saída, exatamente como o dono descreveu.
#
# O que é PROVADO aqui: a máquina de estados e as animações são as da rotina 9
# (`port/script_vm/subir.gd`: `0x8003b244`, tabela de 8 subestados `0x800107d0`, **SEQ 6** em
# `0x8003b39c` e **SEQ 7** em `0x8003b3c4`) e os 6 quadros de contato (`0x800365c8`).
# 🟡 O que é DECLARADO: (a) o gatilho — o sítio do EXE que liga a rotina 9 a partir da COLISÃO
# não foi achado (o caminho por `om` está provado e não é este), então aqui o gatilho é
# geométrico: 6 quadros andando com a sonda de ação (620 un) sobre o degrau; (b) a TRANSLAÇÃO —
# o motor move o corpo pelo root motion da pose, e o port interpola em linha reta do pé ao
# destino ao longo dos subestados de movimento.
## Meia-passada além da sonda: é o quanto o corpo entra no topo do degrau. Declarado.
const DEGRAU_ENTRADA := 300

## Degraus da sala corrente (`{caixa: Rect2i, y_topo: int, y_base: int}`), postos pelo `world.gd`.
var degraus: Array[Dictionary] = []
## A máquina de estados da rotina 9 (arquivo de outro agente, usado sem alterar).
var subir := SubirObjeto.new()
var _degrau: Dictionary = {}
var _degrau_descendo := false
var _degrau_de := Vector3i.ZERO
var _degrau_para := Vector3i.ZERO
var _degrau_contato := 0
var _degrau_q := 0
signal subiu(de: Vector3i, para: Vector3i, descendo: bool)


func subindo() -> bool:
	## O `world.gd` consulta isto para NÃO rederivar o Y do piso durante a subida.
	return subir.ativo


static func _em_caixa(c: Rect2i, x: int, z: int) -> bool:
	return x >= c.position.x and x <= c.position.x + c.size.x \
		and z >= c.position.y and z <= c.position.y + c.size.y


func _detectar_degrau(andando: bool) -> void:
	## O detector (`0x80036c60` + `0x80036570`): 6 quadros de contato **andando** e com a sonda
	## de ação sobre o degrau. Fora disso a contagem zera, como no motor (`0x80036ca0`).
	if subir.ativo or degraus.is_empty() or not andando or acao == Acao.MIRANDO:
		_degrau_contato = 0
		_degrau = {}
		return
	var s := ScriptVM.sonda_de(pos, facing)
	var achado: Dictionary = {}
	var descendo := false
	for g: Dictionary in degraus:
		var c: Rect2i = g["caixa"]
		var corpo_dentro := _em_caixa(c, pos.x, pos.z)
		var sonda_dentro := _em_caixa(c, s.x, s.y)
		if not corpo_dentro and sonda_dentro and pos.y == int(g["y_base"]):
			achado = g                       ## SUBIR: no chão, de frente para a plataforma
			descendo = false
			break
		if corpo_dentro and not sonda_dentro and pos.y == int(g["y_topo"]):
			achado = g                       ## DESCER: em cima, de frente para fora
			descendo = true
			break
	if achado.is_empty():
		_degrau_contato = 0
		_degrau = {}
		return
	if not _degrau.is_empty() and achado != _degrau:
		_degrau_contato = 0
	_degrau = achado
	_degrau_descendo = descendo
	_degrau_contato += 1
	if _degrau_contato < SubirObjeto.FRAMES_CONTATO:
		return
	# `0x800397c4`: `player+4 = 0x901` — entra na rotina 9.
	_degrau_contato = 0
	_degrau_de = pos
	var y_dest: int = int(_degrau["y_base"]) if descendo else int(_degrau["y_topo"])
	var alvo := ScriptVM.sonda_de(pos, facing)
	var frente := Vector2i((PS1Math.rsin(facing) * DEGRAU_ENTRADA) >> PS1Math.SHIFT,
		(-PS1Math.rcos(facing) * DEGRAU_ENTRADA) >> PS1Math.SHIFT)
	_degrau_para = Vector3i(alvo.x + frente.x, y_dest, alvo.y + frente.y)
	_degrau_q = 0
	subir.iniciar()
	_set_acao(Acao.SUBINDO)


## Quadros de MOVIMENTO da rotina 9: os subestados SUBINDO (SEQ 6, 10 quadros) e NO_TOPO
## (SEQ 7, 25) — os números são os de `SubirObjeto.QUADROS_SUB`, medidos nos clipes.
const DEGRAU_QUADROS := 35


func _tick_degrau(pad: Pad) -> void:
	if acao != Acao.SUBINDO:
		_set_acao(Acao.SUBINDO)
	var sub := subir.avancar(pad.pressed(Pad.FWD) or pad.pressed(Pad.BACK))
	if sub >= SubirObjeto.Sub.INICIA_SUBIDA and sub <= SubirObjeto.Sub.TERMINANDO:
		_degrau_q = mini(_degrau_q + 1, DEGRAU_QUADROS)
		pos = Vector3i(
			_degrau_de.x + (_degrau_para.x - _degrau_de.x) * _degrau_q / DEGRAU_QUADROS,
			_degrau_de.y + (_degrau_para.y - _degrau_de.y) * _degrau_q / DEGRAU_QUADROS,
			_degrau_de.z + (_degrau_para.z - _degrau_de.z) * _degrau_q / DEGRAU_QUADROS)
	if subir.sfx_pendente != 0 and sfx != null:
		## Os dois ids são MEDIDOS: `0x8003b224` = início da subida (`SubirObjeto.SFX_INICIO`) e
		## `0x8003b3e8` = impacto do pé no topo (`SFX_IMPACTO`, quando `player+0xc9 == 1`). O `Sfx`
		## já resolve o banco dos dois (varredura dos 155 pedidos de SE — ver
		## `docs/decomp/notes/exe_audio.md` §12), então aqui é só dizer QUANDO.
		if subir.sfx_pendente == SubirObjeto.SFX_IMPACTO:
			sfx.subir_impacto()
		else:
			sfx.subir()
	frame_da_acao += 1
	if not subir.ativo:
		pos = _degrau_para
		_degrau = {}
		_degrau_q = 0
		subiu.emit(_degrau_de, _degrau_para, _degrau_descendo)
		_set_acao(Acao.PARADO)


func clipe_do_degrau() -> String:
	var c := subir.clipe()
	return c if c != "" else "arm00"


func clipe_da_cena() -> String:
	## Clipe do quadro corrente de cinemática. Ver `CENA_CLIPE_FMT` para o que é declarado aqui.
	if cena_bit >= 0:
		return CENA_CLIPE_ANDAR
	if cena_seq < 0:
		return "arm02"                        ## sem SEQ ainda: idle armado
	return CENA_CLIPE_FMT % cena_seq


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
		Acao.CENA:
			## AÇÃO 4: quem escolhe o clipe é o script (`0x80` -> `player+0xc8`).
			return clipe_da_cena()
		Acao.SUBINDO:
			## ROTINA 9: SEQ 6 -> SEQ 7 (`anim06`/`anim07`), o par provado em `subir.gd`.
			return clipe_do_degrau()
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
			if recuo > 0:
				## RECUO, uma seq por altura de mira (seqs 1/3/5 do banco 2)
				if mira_alto > 0:
					return "mira03"
				return "mira05" if mira_alto < 0 else "mira01"
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
	recuo = 0
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
			if recuo > 0:
				recuo -= 1
				if recuo == 0:
					tiro_pendente = -1
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
	## o tiro sai NO QUADRO 0 do recuo: resolve agora e toca o clipe
	tiro_pendente = 0
	mira_quadro = 0
	recuo = RECUO_QUADROS
	_resolver_tiro()


func quadro_do_corte() -> int:
	## Quadro do recuo a partir do qual **soltar a mira corta** o clipe (`0x8003f3dc`), do timing
	## `0x8009cf28` (`byte2 & 0x7f`). Eu chamava isso de "quadro do tiro" — estava errado, o tiro
	## sai no quadro 0. O de-para **item → índice de arma `w`** segue não achado, então faca = w0
	## (50) e o resto = w1 (12, handgun). Declarado.
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
	## SOM DO TIRO. **Correção**: eu havia escrito `cat 0 / id 11`; o estouro da arma é
	## **`cat 1 / id 0`, do banco `A_{w}` da arma equipada** — provado por dois caminhos
	## independentes (a tabela de 20 funções por arma `0x8009ced8..0x8009cf24` pede `cat 1 / idx 0`
	## em TODAS as entradas, logo depois do hitscan; e `A_01`, o banco da FACA, é o único dos 20
	## que não define o id 0). Ver `docs/decomp/notes/exe_audio.md`. Quem resolve o banco é o
	## `Sfx`/`world`; o player só diz QUANDO.
	if sfx != null:
		sfx.tiro()
	var de := pos
	var para := pos + Vector3i(
		PS1Math.rsin(facing) * MIRA_ALCANCE >> PS1Math.SHIFT, 0,
		-PS1Math.rcos(facing) * MIRA_ALCANCE >> PS1Math.SHIFT)
	atirou.emit(mira_alvo, de, para)


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
