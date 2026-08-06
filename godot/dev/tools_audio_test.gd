extends SceneTree
## Harness de verificacao do AudioManager (BGM por area + SFX).
## Nao precisa de render; roda headless (driver de audio dummy tambem serve:
## confirma que os streams CARREGAM e entram em estado 'playing').
##
## Rodar:
##   godot --headless --path godot --script res://dev/tools_audio_test.gd
##
## Verifica: carga do bgm_map/sfx_map, play_bgm(area), crossfade entre areas,
## e play_sfx(nome) para os SFX principais.

const AM_SCRIPT := "res://scripts/audio/audio_manager.gd"

var _am: Node
var _frame := 0
var _steps: Array = []
var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("=== AUDIO TEST ===")
	_am = load(AM_SCRIPT).new()
	_am.name = "AudioManager"
	get_root().add_child(_am)
	# roteiro: [frame_alvo, Callable]
	_steps = [
		[5,   func(): _bgm("UPTOWN")],
		[15,  func(): _sfx("gunshot")],
		[20,  func(): _sfx("door")],
		[25,  func(): _sfx("item_get")],
		[30,  func(): _sfx("footstep")],
		[35,  func(): _sfx("hurt")],
		[40,  func(): _sfx("menu_move")],
		[45,  func(): _sfx("menu_confirm")],
		[60,  func(): _bgm("DOWNTOWN")],   # troca de area -> crossfade
		[90,  func(): _bgm_check_crossfade()],
		[100, func(): _finish()],
	]


func _process(_delta: float) -> bool:
	_frame += 1
	while not _steps.is_empty() and _frame >= _steps[0][0]:
		var step = _steps.pop_front()
		step[1].call()
	return false


func _bgm(area: String) -> void:
	_am.play_bgm(area)
	var ok: bool = _am.is_bgm_playing()
	_report("play_bgm(%s) -> track='%s' playing=%s" % [area, _am.current_track(), ok], ok)


func _bgm_check_crossfade() -> void:
	var t: String = _am.current_track()
	var ok: bool = _am.is_bgm_playing() and t != ""
	_report("apos crossfade: track='%s' playing=%s" % [t, ok], ok)


func _sfx(name: String) -> void:
	var p = _am.play_sfx(name)
	var ok: bool = p != null and p.playing
	_report("play_sfx(%s) -> %s" % [name, "OK" if ok else "FALHOU"], ok)


func _report(msg: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	print(("[ OK ] " if ok else "[FALHA] "), msg)


func _finish() -> void:
	print("=== RESULTADO: %d OK, %d FALHA ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
