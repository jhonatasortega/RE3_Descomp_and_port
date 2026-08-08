extends SceneTree
## Prova de ponta a ponta no JOGO: entra na sala inicial, atravessa a porta e reporta cada som
## pedido (banco de personagem, banco de arma, banco de porta) + a faixa de BGM de cada sala.
##
##     "$GODOT" --path port --rendering-driver opengl3 --script res://dev/diag_som_jogo.gd
##
## Sem `--headless` o driver de áudio é o real (WASAPI), então `playing` significa som saindo.

var _cena: Node
var _q := 0


func _initialize() -> void:
	_cena = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_cena)


func _process(_dt: float) -> bool:
	_q += 1
	if _q < 3:
		return false
	var g := root.get_node_or_null("Game")
	var s: Sfx = g.get("sfx") as Sfx
	var mundo: Object = _cena.get("mundo")
	print("banco_area=%s banco_arma=%s" % [s.banco_area(), s.banco_arma()])

	## R100/R10F/R601 = medidas (ALTA) · R400 = nome provado, render NAO_CASADO ·
	## R10D = sem WAV homônimo no PC, cai no fallback por STAGE · R11B = SEM_MAIN
	var salas: Array = ["R100", "R10F", "R601", "R400", "R10D", "R11B"]
	for id: String in salas:
		var info: Dictionary = (g.get("audio") as Audio).faixa_info(id)
		print("  BGM %s -> %-10s fonte=%-16s conf=%s" % [
			id, info.get("faixa", ""), info.get("fonte", ""), info.get("conf", "")])

	var portas: Array = mundo.get("vm").call("portas")
	print("portas na sala %s: %d" % [mundo.get("room").get("room_id"), portas.size()])
	for p: Aot in portas:
		var dt: int = s.dtex_da_porta(str(mundo.get("room").get("room_id")), p.id)
		var ok: bool = mundo.call("atravessar", p)
		print("  aot %d dtex %d -> %s · banco_porta=%s · som=%s" % [
			p.id, dt, ok, s.banco_porta(), s.ultimo_tocado()])
		break
	print("driver=%s" % AudioServer.get_driver_name())
	for c: Node in s.get_children():
		var ap := c as AudioStreamPlayer
		if ap != null and ap.playing:
			print("  %s tocando pos=%.3f" % [ap.name, ap.get_playback_position()])
	return true
