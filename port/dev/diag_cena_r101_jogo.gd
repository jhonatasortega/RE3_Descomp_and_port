extends SceneTree
## A cena de ENTRADA do R101 pelo CAMINHO REAL DO JOGO: `game.tscn` → `Clock` do autoload `Game`
## → `Screen._on_tick` → `World.tick`. Nada de chamar `World.tick` na mão.
##
##     godot --headless --audio-driver Dummy --path port \
##         --script res://dev/diag_cena_r101_jogo.gd
##
## É a verificação que o round anterior deixou escapar: uma cena podia "rodar" no harness e o
## dono não ver animação no jogo. Aqui se lê, por quadro, `AnimationPlayer.current_animation`,
## `mundo.camera`, `mundo.room.room_id` e `player.pos` — o que a tela mostra.
##
## Roteiro: deixa a abertura do `R10D` terminar · teleporta para dentro da caixa do gatilho
## `sce 5` (é o que a Jill faz descendo da lixeira) · a cena de saída dispara a porta · o `R101`
## carrega e abre a função 3 · mede a cinemática de entrada até ela devolver o controle.

## Ponto dentro da caixa do gatilho `sce 5` do `R10D` (x[-8585..-5285] z[-15000..-11300]).
const NO_GATILHO := Vector3i(-7000, 0, -13000)
const LIMITE := 60000

var _cena: Node
var _frames := 0
var _etapa := "aquece"
var _teleportou := false
var _clipes: Array[String] = []
var _cams: Array[int] = []
var _q_r101 := -1
var _pos_ini := Vector3i.ZERO
var _pos_fim := Vector3i.ZERO


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	if _frames > LIMITE:
		print("[r101] ABORTOU no limite de %d quadros de processo (etapa %s)" % [LIMITE, _etapa])
		return true
	var mundo: Object = _cena.get("mundo")
	if mundo == null:
		return false
	var pl: Object = mundo.get("player")
	var sala: String = str(mundo.get("room").get("room_id"))
	var cena: Object = mundo.get("cena")
	var cam: int = int(mundo.get("camera"))
	var ap: Object = _cena.get("actor_anim_player")
	var clipe := str(ap.get("current_animation")) if ap != null else ""

	# 1) espera a abertura do R10D terminar
	if not _teleportou:
		if cena != null:
			return false
		_teleportou = true
		_etapa = "andando para a caixa"
		pl.set("pos", NO_GATILHO)
		print("[r101] abertura do R10D terminou · sala=%s cam=%d clipe=%s" % [sala, cam, clipe])
		return false

	# 2) R10D: a cena de saída
	if sala == "R10D":
		return false

	# 3) chegou no R101
	if _q_r101 < 0:
		_q_r101 = 0
		_pos_ini = pl.get("pos")
		_etapa = "cinemática de entrada do R101"
		print("[r101] ★ entrou no R101 · pos=%s cam=%d cena_func=%s" % [
			_pos_ini, cam, mundo.get("cena_func")])
		if cena == null:
			print("[r101] ✗ o R101 NÃO abriu cinemática de entrada")
			return true
	_q_r101 += 1
	if not _cams.has(cam):
		_cams.append(cam)
	if clipe != "" and not _clipes.has(clipe):
		_clipes.append(clipe)
	if cena != null:
		return false
	_pos_fim = pl.get("pos")
	print("[r101] cinemática de entrada TERMINOU em %d quadros de processo" % _q_r101)
	print("[r101] câmeras vistas na tela: %s" % [_cams])
	print("[r101] clipes que o AnimationPlayer tocou: %s" % [_clipes])
	print("[r101] player: %s -> %s · cam final=%d · ação=%s" % [
		_pos_ini, _pos_fim, cam, pl.get("acao")])
	return true
