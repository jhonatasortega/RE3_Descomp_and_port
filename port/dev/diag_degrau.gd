extends SceneTree
## A ROTINA 9 (subir/descer o degrau) quadro a quadro: subestado, clipe, posição e SFX.
##
##     godot --headless --audio-driver Dummy --path port --script res://dev/diag_degrau.gd
##     DEGRAU_SOLTA=1 godot ... (solta o "frente" assim que a rotina 9 começa)
##
## Sobe do spawn do `R10D` andando para OESTE, como o dono faz. `DEGRAU_SOLTA` isola o efeito do
## "segurar a direção" no subestado `NO_TOPO` (`0x8003b1c4`: o `move` só avança quando a direção
## NÃO está segurada **ou** a flag `0x800d1f2c & 0x10` caiu — e essa flag é RECALCULADA todo
## quadro no motor, `0x800364f8`).

const SPAWN := Vector3i(9404, 0, -13317)
const OESTE := 3072


func _initialize() -> void:
	var solta := OS.get_environment("DEGRAU_SOLTA") != ""
	var w := World.new()
	if not w.carregar("R10D"):
		print("R10D não carregou")
		quit(1)
		return
	var pad := Pad.new()
	while w.cena != null:
		pad.set_mask(0)
		w.tick(pad)
	w.player.pos = SPAWN
	w.player.facing = OESTE
	print("degraus da sala: %d" % w.player.degraus.size())
	var visto: Array[String] = []
	var q_ini := -1
	for i in 600:
		pad.set_mask(0 if (solta and w.player.subindo()) else Pad.FWD)
		w.tick(pad)
		if not w.player.subindo():
			if q_ini >= 0:
				print("q%4d  ROTINA 9 TERMINOU · pos=%s ação=%s" % [
					i, w.player.pos, w.player.acao])
				break
			continue
		if q_ini < 0:
			q_ini = i
			print("q%4d  ROTINA 9 COMEÇOU · pos=%s descendo=%s" % [
				i, w.player.pos, w.player._degrau_descendo])
		var linha := "q%4d  sub=%-14s clipe=%-7s pos=%s" % [
			i, SubirObjeto.Sub.keys()[w.player.subir.sub], w.player.clipe_do_degrau(),
			w.player.pos]
		if w.player.subir.sfx_pendente != 0:
			linha += "  SFX 0x%x" % w.player.subir.sfx_pendente
		print(linha)
		if not visto.has(w.player.clipe_do_degrau()):
			visto.append(w.player.clipe_do_degrau())
	print("clipes: %s · flag=%s · ativo=%s" % [visto, w.player.subir.flag, w.player.subir.ativo])
	quit(0)
