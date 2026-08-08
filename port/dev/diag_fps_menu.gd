extends SceneTree
## DIAGNÓSTICO: quanto custa cada quadro com o mundo, com a tela de STATUS e com a de ARQUIVO.
##
## O relato "entrar no inventário pausa o game (trilha também)" NÃO é a BGM parando
## (`dev/diag_bgm_menu.gd` mede que ela continua): a suspeita é ENGASGO — trabalho pesado por
## quadro no desenho da tela, que trava a imagem e faz o áudio picar.
##
## godot --path port --script res://dev/diag_fps_menu.gd

var _cena: Node
var _t := 0
var _fase := 0
var _t0 := 0
var _n := 0
var _soma := 0.0
var _pior := 0.0


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)


func _medir(d: float) -> void:
	_n += 1
	_soma += d
	_pior = maxf(_pior, d)


func _relatar(rot: String) -> void:
	print("[fps] %-16s %d quadros · medio %.2f ms (%.0f fps) · pior %.2f ms" % [
		rot, _n, _soma / float(_n) * 1000.0, float(_n) / _soma, _pior * 1000.0])
	_n = 0
	_soma = 0.0
	_pior = 0.0


func _process(d: float) -> bool:
	_t += 1
	if _t < 40:
		return false
	var menu: Object = _cena.get("menu")
	var arq: Object = _cena.get("menu_arquivo")
	match _fase:
		0:
			_medir(d)
			if _n >= 60:
				_relatar("mundo")
				menu.call("alternar")
				_fase = 1
		1:
			_medir(d)
			if _n >= 60:
				_relatar("status aberto")
				## marca um documento como LIDO: sem isso `_desenhar_arquivo` nem chama
				## `nome_do_doc`, e o custo do nome (que é o que se quer medir) fica escondido
				var g: Node = _cena.get_node_or_null("/root/Game")
				(g.get("state") as Object).call("marcar_arquivo_lido", 0x85)
				menu.set("selecao_botao", 1)
				menu.call("confirmar")
				_fase = 2
		2:
			_medir(d)
			if _n >= 60:
				_relatar("arquivo aberto")
				arq.call("ir_para_doc", 0)
				_fase = 3
		3:
			_medir(d)
			if _n >= 60:
				_relatar("documento aberto")
				return true
	return false
