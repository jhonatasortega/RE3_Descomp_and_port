extends Node
## Autoload `Game` — dono do relógio, do estado e da entrada (P0-08).
##
## É o ÚNICO singleton da camada de núcleo. Existe para responder a uma pergunta só:
## "quem avança o mundo, e com qual entrada?". Ordem de update por tick, fixa:
##
##     pad.poll()  ->  sinal `tick`  ->  (F1) player/câmera  ->  (F2) VM do script  ->  (F5) IA
##
## Regra de dependência (o erro do protótipo antigo foi não ter uma): `core/` e `script_vm/`
## não conhecem nó visual; quem desenha ouve `Game.tick` e lê o estado. Nada de sistema
## chamando sistema por dentro — a coordenação é aqui.
##
## Diagrama e papel de cada pasta: port/README.md

signal tick(frame: int)              ## um por tick de gameplay (30 Hz), depois do pad
signal state_reset

var clock: Clock
var state: GameState
var pad: Pad
var audio: Audio


func _ready() -> void:
	name = "Game"
	state = GameState.new()
	pad = Pad.new()
	clock = Clock.new()
	clock.name = "Clock"
	add_child(clock)
	audio = Audio.new()
	add_child(audio)
	clock.ticked.connect(_on_tick)
	print("[Game] pronto — %d Hz, ângulo de %d unidades, tabela sin/cos do EXE: %s"
		% [Clock.HZ, PS1Math.FULL_CIRCLE, "sim" if PS1Math.table_from_exe() else "calculada"])


func _on_tick(frame: int) -> void:
	pad.poll()
	state.play_ticks = frame
	tick.emit(frame)


func new_game(loadout: Array = []) -> void:
	## Começa um jogo novo: zera o estado e aplica o template de inventário (P6-07).
	state.reset()
	if not loadout.is_empty():
		state.load_loadout(loadout)
	clock.reset()
	state_reset.emit()


func advance(n: int = 1) -> void:
	## Avança n ticks manualmente (harness headless; o jogo normal avança via _physics_process).
	clock.step_n(n)
