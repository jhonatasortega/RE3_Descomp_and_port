extends Node3D
class_name JillController
## Controlador da Jill 3D no estilo classico do RE (tank controls).
##
## A Jill vive dentro do SubViewport 3D. O node raiz deste script E o "pe" da
## personagem (a origem no chao). O modelo (PL00.glb) e um filho, deslocado pra
## cima para que os pes coincidam com a origem.
##
## Tank controls (anim resolvida por root-motion do PL00.PLD, ver anim_map.json):
##   CIMA  -> anda pra frente na direcao atual (anim00, root -X ~60/f)
##   BAIXO -> anda pra tras (anim00 invertida; clipe dedicado = anim11)
##   ESQ/DIR -> gira a Jill no lugar (anim15/anim16, passo lateral in-place)
##   Shift -> corre/trota pra frente (anim10, root -X ~228/f)
##   Segurar tras/frente + nada = parado (anim00 pausada no frame 0)
##
## Calibracao exposta como exports (ver docs/godot_gameplay.md).

# --- Calibracao de escala/orientacao do modelo ---
@export var model_scale: float = 1.0            ## escala do PL00.glb (1.0 casa com PS1 usando world_scale=808)
@export var model_yaw_offset_deg: float = 90.0 ## gira SO o mesh p/ alinhar o "frente" visual ao -Z do node (VERIFICADO por tools_orient_test: camera olhando -Z ve as COSTAS com yaw=90; 180/0 davam PERFIL => "anda de lado")
@export var foot_offset: float = 1.85           ## quanto o mesh sobe p/ os pes baterem na origem (AABB min_y)
@export var model_path: String = "res://assets/PLD/PL00.glb"  ## instanciado FRESCO em runtime (evita a instancia velha salva na cena, que quebrava so no jogo)

# --- Calibracao de movimento (unidades Godot = ~PS1/808) ---
@export var turn_speed_deg: float = 110.0       ## giro em graus/seg (PS1 ~3.4 deg/frame @30fps ~= 102 deg/s)
@export var quickturn_speed_deg: float = 720.0  ## quick-turn (RE): 180 graus em ~0.25s (ré+correr)
@export var walk_speed: float = 2.8             ## andar ARMADO: PS1 ~78 un/frame (PL00W00 seq0) @30fps /808 ~= 2.9 un/s
@export var run_speed: float = 8.3              ## correr ARMADO: PS1 ~222 un/frame (PL00W00 seq1) @30fps /808 ~= 8.24 un/s

# --- Estado ---
var facing_deg: float = 0.0                     ## direcao atual (graus, Y-up)
var _anim: AnimationPlayer
var _model: Node3D
var _current_anim: String = ""
var _static_pose: bool = false                  ## true quando segurando uma pose (idle pausado)
var _quickturn_remaining: float = 0.0           ## graus restantes do quick-turn 180 em curso
var _qt_prev: bool = false                       ## estado anterior do input de quick-turn (deteccao de borda)
## Validador de colisao (opcional): Callable(pos: Vector3) -> bool. Definido pela
## room_game; quando presente, a Jill so anda para posicoes "caminhaveis".
var _walkable_query: Callable = Callable()

# --- Mapeamento de animacao — LOCOMOCAO ARMADA (a real de gameplay) ---
# DESCOBERTA-CHAVE (o usuario estava certo: o andar NAO esta nas 22 do PL00.PLD):
# o RE3 usa banco MULTIPLO. player+0xc8 indexa um EDD cujo base e' SELECIONADO pela ARMA
# equipada (player+0xf4 = banco do PLW). A Jill anda SEMPRE com arma -> o andar/correr/
# parada/re de gameplay vem do BANCO0 do PLW (PL00W00.PLW, handgun), NAO do PLD.
# O pld2gltf agora retargeta esse banco ao esqueleto do PLD como clipes "armNN":
#   arm00 = ANDAR frente | arm01 = CORRER | arm02 = PARADA/mira (idle armado) | arm09 = RE
# As 22 "animNN" do PLD sao o set DESARMADO/base + acoes sempre-validas (dano anim19/20,
# pegar anim08, idle-wait anim21). Ver docs/formatos/exe.md sec.4-B0 e find_anim_banks.py.
const ANIM_IDLE := "arm02"           # PARADO: idle ARMADO (em pe segurando a arma; loop sutil, sem marcha/fidget)
const IDLE_FRAC := 0.0               # (legado) fracao p/ pose estatica; nao usado com arm02 em loop
const ANIM_WALK := "arm00"           # ANDAR pra frente ARMADO (~78 un/frame; ciclo de passada limpo)
const ANIM_WALK_BACK := "arm09"      # ANDAR pra TRAS ARMADO (clipe dedicado, ~68 un/frame -X)
const ANIM_RUN := "arm01"            # CORRER pra frente ARMADO (~222 un/frame)
const ANIM_TURN := "arm00"           # virar no lugar: passada do andar armado (stepping turn)
const ANIM_HURT := "anim19"          # DANO: tomba/jogada longe (par espelhado anim19/anim20)
const ANIM_PICKUP := "anim08"        # abaixar e pegar/examinar no chao
const ANIM_CROUCH := "anim09"        # agachar


func _ready() -> void:
	# Instancia o modelo FRESCO em runtime. A instancia salva em game_room.tscn ("Model")
	# ficava DESATUALIZADA apos regenerar o PL00.glb -> mesh quebrado SO no jogo (o modelo
	# isolado, carregado fresco, funcionava). Liberamos a antiga e usamos a atual.
	var saved := get_node_or_null("Model")
	if saved:
		saved.free()
	var packed: PackedScene = load(model_path)
	if packed:
		_model = packed.instantiate()
		_model.name = "Model"
		add_child(_model)
	if _model == null:
		# fallback: primeiro filho Node3D
		for c in get_children():
			if c is Node3D:
				_model = c
				break
	if _model:
		_model.scale = Vector3.ONE * model_scale
		_model.position.y = foot_offset * model_scale
		_model.rotation.y = deg_to_rad(model_yaw_offset_deg)
		_anim = _find_anim_player(_model)
	rotation.y = deg_to_rad(facing_deg)
	_play(ANIM_IDLE)


func set_facing(deg: float) -> void:
	facing_deg = deg
	rotation.y = deg_to_rad(facing_deg)


func set_walkable_query(q: Callable) -> void:
	_walkable_query = q


## Resolve o deslocamento contra a colisao com deslize por eixo (X depois Z),
## para a Jill escorregar na parede em vez de travar. Sem query -> livre.
func _apply_move(from: Vector3, to: Vector3) -> Vector3:
	if not _walkable_query.is_valid():
		return to
	if _walkable_query.call(to):
		return to
	var slide_x := Vector3(to.x, from.y, from.z)
	if _walkable_query.call(slide_x):
		return slide_x
	var slide_z := Vector3(from.x, from.y, to.z)
	if _walkable_query.call(slide_z):
		return slide_z
	return from


func _physics_process(delta: float) -> void:
	# Tank controls em WASD -> traduzidos para (move, turn, running) e aplicados
	# por apply_input (a MESMA rotina usada pelo harness de validacao).
	#   W=frente, S=re, A=gira esquerda, D=gira direita, Shift=corre.
	var turn := 0.0
	if Input.is_key_pressed(KEY_A):
		turn -= 1.0   # A = girar para a ESQUERDA
	if Input.is_key_pressed(KEY_D):
		turn += 1.0   # D = girar para a DIREITA
	var move := 0.0
	if Input.is_key_pressed(KEY_W):
		move += 1.0   # W = andar para FRENTE
	if Input.is_key_pressed(KEY_S):
		move -= 1.0   # S = andar para TRAS
	var running := Input.is_key_pressed(KEY_SHIFT)
	apply_input(move, turn, running, delta)


## Aplica um passo de tank-control. Chamado tanto por _physics_process (teclado)
## quanto pelo harness de validacao (input roteirizado) -> a validacao exercita
## EXATAMENTE o codigo do jogo. Zero input => zero movimento e zero giro.
##   move:  +1 frente, -1 re, 0 parado
##   turn:  +1 gira p/ direita (horario visto de cima), -1 p/ esquerda
##   running: usa run_speed e anim de corrida
func apply_input(move: float, turn: float, running: bool, delta: float) -> void:
	# --- Quick-turn 180 (RE classico): segurar RE (move<0) + CORRER dispara um giro
	# rapido de 180 no lugar. Disparado na BORDA (uma vez por aperto); durante o giro
	# ignora translacao/outras anims. Nenhum clipe faz o 180 sozinho -> giro programatico
	# (como no jogo real), tocando o passo armado (arm00) enquanto roda. ---
	var qt_input := running and move < 0.0
	if qt_input and not _qt_prev and _quickturn_remaining <= 0.0:
		_quickturn_remaining = 180.0
	_qt_prev = qt_input
	if _quickturn_remaining > 0.0:
		var step := minf(quickturn_speed_deg * delta, _quickturn_remaining)
		facing_deg += step
		rotation.y = deg_to_rad(facing_deg)
		_quickturn_remaining -= step
		_play(ANIM_TURN)
		if _anim:
			_anim.speed_scale = 1.0
		return

	# --- Giro no proprio eixo (roda o NODE; o quadril fica fixo no XZ do node) ---
	if not is_zero_approx(turn):
		# turn>0 (D) => girar p/ direita = SENTIDO HORARIO visto de cima.
		# Em Godot (Y-up), rotacao.y positiva e anti-horaria vista de cima,
		# entao horario = -angulo.
		facing_deg -= turn * turn_speed_deg * delta
		rotation.y = deg_to_rad(facing_deg)

	# --- Deslocamento (velocidade escalar por frame; animacao e' IN-PLACE) ---
	# RE3 NAO tem "correr pra tras": correr so vale pra FRENTE (move>0). A re' e sempre
	# velocidade de andar, mesmo com Shift segurado (inclusive apos o quick-turn).
	var speed := run_speed if (running and move > 0.0) else walk_speed
	# A frente VISUAL do mesh esta no -Z do node. Andar p/ frente (move>0) segue
	# -basis.z -> casa com a direcao para onde ela olha.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if not is_zero_approx(move):
		var desired := global_position + forward * speed * move * delta
		global_position = _apply_move(global_position, desired)

	# --- Animacao (clipes ARMADOS dedicados p/ cada direcao; sem inverter velocidade) ---
	if not is_zero_approx(move):
		var target: String
		if move > 0.0:
			target = ANIM_RUN if running else ANIM_WALK   # frente: arm00/arm01
		else:
			target = ANIM_WALK_BACK                        # re: clipe dedicado arm09
		_play(target)
		if _anim:
			_anim.speed_scale = 1.0
	elif not is_zero_approx(turn):
		# girar no lugar: passada do andar armado (stepping turn)
		_play(ANIM_TURN)
		if _anim:
			_anim.speed_scale = signf(turn)
	else:
		# parado: idle ARMADO (arm02) em loop — em pe segurando a arma, sem marcha/fidget
		_play(ANIM_IDLE)


func _play(anim: String) -> void:
	if _anim == null:
		return
	if _current_anim == anim and _anim.is_playing() and not _static_pose:
		return
	_current_anim = anim
	_static_pose = false
	if _anim.has_animation(anim):
		var a := _anim.get_animation(anim)
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.speed_scale = 1.0
		_anim.play(anim)


## Segura uma POSE estatica (seek + pause) — usada no idle p/ ficar EM PE parada
## sem marchar no lugar. Idempotente.
func _play_static(anim: String, frac: float) -> void:
	if _anim == null:
		return
	if _current_anim == anim and _static_pose:
		return
	_current_anim = anim
	_static_pose = true
	if _anim.has_animation(anim):
		var a := _anim.get_animation(anim)
		_anim.speed_scale = 1.0
		_anim.play(anim)
		_anim.seek(a.length * frac, true)
		_anim.pause()


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r:
			return r
	return null
