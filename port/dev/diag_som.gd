extends SceneTree
## Diagnóstico do SFX no JOGO DE VERDADE — "por que o som do tiro não sai" (P7-02).
##
##     GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
##     "$GODOT" --path port --headless --audio-driver Dummy --script res://dev/diag_som.gd
##
## ⚠ O autoload `Game` só existe A PARTIR do 1º quadro (com `--script`, o `_initialize`
##    roda ANTES dos autoloads — foi o que me fez ver `Game.sfx = false` na primeira
##    tentativa). Por isso a checagem acontece no `_process`, não no `_initialize`.
##
## Responde, em ordem:
##   1. o autoload `Game` tem `sfx`, e o `Sfx` leu o `data/re3_se.json`?
##   2. para cada ação: qual WAV, existe no disco, o stream carrega, e o pool toca?
##   3. o `screen.gd` monta o `World` e o `World` injeta o `Sfx` no `Player`?

const ACOES := ["menu_mover", "menu_confirmar", "tiro", "impacto_ataque", "porta_abrir"]

var _cena: Node
var _quadros := 0


func _initialize() -> void:
	_cena = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_cena)


func _process(_dt: float) -> bool:
	_quadros += 1
	if _quadros < 3:
		return false
	var g := root.get_node_or_null("Game")
	print("autoload Game: ", g != null)
	var s: Sfx = g.get("sfx") as Sfx if g != null else null
	print("Game.sfx: ", s != null, " · pronto(): ", s.pronto() if s != null else false,
		" · banco_area='", s.banco_area() if s != null else "", "'")
	if s == null:
		return true
	for banco: String in ["", Sfx.BANCO_JOGADOR]:
		s.definir_banco_area(banco)
		print("\n=== banco_area = '%s' ===" % s.banco_area())
		for a: String in ACOES:
			var rel := s.acao_wav(a)
			var abs_path := AssetIO.path("SOUND/SFX/%s" % rel)
			var existe := FileAccess.file_exists(abs_path)
			var st: AudioStreamWAV = null
			if existe:
				st = AudioStreamWAV.load_from_file(abs_path)
			var ok := s.tocar_acao(a)
			print("%-16s cat %2d id %3d wav=%-26s existe=%s stream=%s len=%.3fs tocou=%s ult=%s" % [
				a, s.acao_cat(a), s.acao_id(a), rel, existe, st != null,
				st.get_length() if st != null else 0.0, ok, s.ultimo_tocado()])

	print("\n=== caminho do som do tiro ===")
	var mundo: Object = _cena.get("mundo")
	print("screen.mundo: ", mundo != null)
	if mundo != null:
		var pl: Object = mundo.get("player")
		print("mundo.player: ", pl != null,
			" · player.sfx: ", (pl.get("sfx") != null) if pl != null else false)
	var w := World.new()
	print("World.new().player.sfx (injeção direta): ", w.player.sfx != null)

	print("\n=== tiro SIMULADO (mira -> gatilho), com o Sfx do Game ===")
	s.definir_banco_area()
	var st2 := GameState.new()
	st2.novo_jogo()
	var pl2 := Player.new()
	pl2.estado = st2
	pl2.sfx = s
	pl2.equipped_weapon = st2.equipped_item_id()
	var pad := Pad.new()
	var antes := s.ultimo_tocado()
	for q in 40:
		pad.set_mask(Pad.AIM)
		pl2.tick(pad)
	print("apos 40 ticks de mira: acao=%d mira_sub=%d" % [pl2.acao, pl2.mira_sub])
	pad.set_mask(Pad.AIM | Pad.TIRO)
	pl2.tick(pad)
	for q in 20:
		pad.set_mask(Pad.AIM)
		pl2.tick(pad)
	print("municao %d->%d · ultimo SFX: '%s' (antes '%s')" % [
		15, st2.equipped_qtd(), s.ultimo_tocado(), antes])

	print("\n=== tiro pelo CAMINHO REAL (Game.pad -> Game.advance -> screen -> mundo) ===")
	var gpad: Pad = g.get("pad") as Pad
	var gst: GameState = g.get("state") as GameState
	print("Game.state: arma=0x%02x qtd=%d" % [gst.equipped_item_id(), gst.equipped_qtd()])
	var plr: Object = mundo.get("player") if mundo != null else null
	var ult0 := s.ultimo_tocado()
	## ⚠ `Game._on_tick` chama `pad.poll()` ANTES do tick, e no modo LIVE isso sobrescreve
	##   qualquer `set_mask`. Para dirigir o jogo de fora só serve o modo REPLAY.
	var fita := PackedInt32Array()
	for q in 45:
		fita.append(Pad.AIM)
	fita.append(Pad.AIM | Pad.TIRO)
	for q in 25:
		fita.append(Pad.AIM)
	gpad.load_replay(fita)
	for q in 46:
		g.call("advance", 1)
	print("apos 45 ticks de AIM: acao=%s equipped_weapon=%s mira_sub=%s" % [
		plr.get("acao"), plr.get("equipped_weapon"), plr.get("mira_sub")])
	for q in 25:
		g.call("advance", 1)
	print("municao final=%d · ultimo SFX='%s' (antes '%s')" % [
		gst.equipped_qtd(), s.ultimo_tocado(), ult0])

	print("\n=== estado do pool e do mixer (rode SEM --audio-driver Dummy para valer) ===")
	print("driver=%s · mix_rate=%.0f · Master vol=%.1f dB mute=%s" % [
		AudioServer.get_driver_name(), AudioServer.get_mix_rate(),
		AudioServer.get_bus_volume_db(0), AudioServer.is_bus_mute(0)])
	for c: Node in s.get_children():
		var ap := c as AudioStreamPlayer
		if ap == null:
			continue
		print("  %s playing=%s pos=%.3f vol=%.1f stream=%s" % [ap.name, ap.playing,
			ap.get_playback_position(), ap.volume_db,
			ap.stream.resource_name if ap.stream != null else "<nulo>"])
	return true
