extends SceneTree
## DIAGNÓSTICO: a TRILHA para quando o inventário abre?
##
## Relato do dono: "entrar no inventário pausa o game (trilha também)". Pausar o MUNDO está certo
## (`task_suspend(0)` em `0x8006d97c`; no port é "não chamar `mundo.tick`"). Parar a BGM não: no
## PS1 ela é SPU/CD e roda fora da task do mundo.
##
## Este script mede, na cena real: `bgm_player.playing`, `stream_paused` e a POSIÇÃO de leitura,
## antes e depois de abrir a tela de status. Se a posição não anda, a trilha parou.
##
## godot --path port --script res://dev/diag_bgm_menu.gd

var _cena: Node
var _t := 0
var _fase := 0
var _pos: Array[float] = []
var _espera := 0


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)


func _linha(rot: String, bgm: AudioStreamPlayer) -> void:
	print("[bgm] %-22s playing=%s pausado=%s pos=%.3f  paused(arvore)=%s time_scale=%.2f" % [
		rot, str(bgm.playing), str(bgm.stream_paused), bgm.get_playback_position(),
		str(get_root().get_tree().paused), Engine.time_scale])
	_pos.append(bgm.get_playback_position())


func _process(_d: float) -> bool:
	_t += 1
	if _t < 30:
		return false
	var g: Node = _cena.get_node_or_null("/root/Game")
	var au: Object = g.get("audio")
	var bgm: AudioStreamPlayer = au.get("bgm_player")
	var menu: Object = _cena.get("menu")
	match _fase:
		0:
			_linha("mundo rodando", bgm)
			_fase = 1
		1:
			_linha("mundo rodando (+1)", bgm)
			## Abre pelo PAD, como o jogador: o bit MENU entra no `Screen._on_tick`.
			var pad: Object = g.get("pad")
			pad.call("set_mask", Pad.MENU)
			_cena.call("_on_tick", _t)
			pad.call("set_mask", 0)
			print("[bgm] --- tela de status ABERTA pelo pad (aberto=%s) ---" % str(menu.get("aberto")))
			_espera = 180                             ## ~3 s de menu aberto
			_fase = 2
		2:
			## amostra a cada 60 quadros para pegar uma parada TARDIA, não só a do quadro seguinte
			if _espera % 60 == 0:
				_linha("menu aberto (%d)" % (180 - _espera), bgm)
			_espera -= 1
			if _espera > 0:
				return false
			_linha("menu aberto (fim)", bgm)
			print("[bgm] faixa=%s" % str(g.get("audio").call("faixa_atual")))
			var andou_fora := _pos[1] - _pos[0]
			var andou_menu := _pos[_pos.size() - 1] - _pos[2]
			print("[bgm] avanço FORA do menu: %.4f s (1 quadro) · DENTRO: %.4f s (180 quadros)" % [
				andou_fora, andou_menu])
			if andou_menu <= 0.01:
				print("[bgm] CONFIRMADO: a trilha PAROU com o menu aberto")
			else:
				print("[bgm] a trilha CONTINUA tocando com o menu aberto (correto)")
			return true
	return false
