extends SceneTree
## SONDA do SOM da abertura: o que o `Boot` REALMENTE faz o `Audio`/`Sfx` tocar.
##
## O dono relatou "som do menu principal errado". Os sinais (`pediu_bgm`, `pediu_sfx`,
## `pediu_parar_bgm`) são fáceis de conferir com teste, mas o que faltava era ver o OUTRO LADO:
## qual arquivo o `Sfx` escolheu e qual `.ogg` o `Audio` pôs no player.
##
##     "$GODOT" --path port --headless --audio-driver Dummy \
##         --script res://dev/diag_som_boot.gd
##
## ⚠ A cena entra na árvore e a sonda espera o 1º quadro: num `SceneTree` o `_ready` só roda
## depois do `_initialize` (é ele que liga `pediu_bgm`/`pediu_sfx` no `Audio`/`Sfx`).

var _cena: Node
var _quadros := 0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn")
	_cena = packed.instantiate()
	_cena.set("entrar_no_jogo", false)
	_cena.set("tocar_fmv", false)
	root.add_child(_cena)


func _process(_delta: float) -> bool:
	_quadros += 1
	if _quadros < 2:
		return false                            ## deixa o `_ready` da cena rodar
	var g: Node = root.get_node_or_null("Game")
	var au: Object = g.get("audio") if g != null else null
	var sf: Object = g.get("sfx") if g != null else null
	print("[som] Game=%s audio=%s sfx=%s" % [g, au, sf])
	if au == null or sf == null:
		quit(1)
		return true
	print("[som] banco de area (cat 0) no boot, vazio = cai no padrao C_00: %s" % sf.get("_banco_area"))

	var tt: Object = _cena.get("titulo")
	_cena.call("_ir_para_passo", "titulo_espera")
	print("[som] passo=titulo_espera -> BGM = %s" % au.call("faixa_atual"))
	_cena.call("_ir_para_passo", "menu")
	tt.call("mover_cursor", 1)
	print("[som] mover cursor  -> SE = %s" % sf.call("ultimo_tocado"))
	tt.set("cursor", Titulo.Item.NOVO_JOGO)
	tt.call("confirmar")
	print("[som] confirmar     -> SE = %s" % sf.call("ultimo_tocado"))
	tt.call("cancelar")
	print("[som] cancelar      -> SE = %s" % sf.call("ultimo_tocado"))
	_cena.call("_ir_para_passo", "filme_atracao")
	print("[som] entrou no filme -> BGM = '%s' (vazia = parou)" % au.call("faixa_atual"))
	## a VINHETA: entrar no passo PARA a BGM e, no quadro 30, o script pede a narracao
	_cena.call("_ir_para_passo", "prologo")
	print("[som] entrou na vinheta -> BGM = '%s'" % au.call("faixa_atual"))
	var pr: Object = _cena.get("prologo")
	pr.call("avancar", 2 * 30)
	print("[som] vinheta quadro 30 -> BGM = %s (a narracao main06, sem laco)" % au.call("faixa_atual"))
	quit(0)
	return true
