extends SceneTree
## Screenshot de uma FASE do fluxo de abertura — validação visual do `boot.tscn`.
##
## Sem isso não há como afirmar que a tela de título está certa: "tocou o passo" é log,
## "a palavra CARREG. JOGO está em (x,y) e o item selecionado está mais claro" é imagem.
##
##     GODOT="C:/.../godot.windows.opt.tools.64.exe"
##     BOOT_FASE=menu "$GODOT" --path port --rendering-driver opengl3 \
##         --script res://dev/shot_boot.gd
##
## ⚠ NÃO usar `--headless`: o driver dummy não renderiza (a imagem sai vazia).
## ⚠ O `_ready()` da cena só roda no PRIMEIRO quadro — `_initialize` de um SceneTree
##    acontece antes disso. Por isso a fase é forçada no quadro 1, não no `_initialize`
##    (foi o que fazia `passo_atual()` devolver "fim" e `titulo` vir nulo).
##
## Variáveis:
##     BOOT_FASE     passo a capturar: aviso_exibicao | capcom_exibicao | capcom_entra_logo |
##                   titulo_flash | titulo_fade_in | menu | dificuldade   (default: menu)
##     BOOT_CURSOR   cursor do menu (0 NEW GAME · 1 LOAD GAME · 2 GAME CONFIG)
##     BOOT_TICKS    ticks a avançar DENTRO do passo (para pegar o meio de um fade)
##     BOOT_OUT      PNG de saída (default res://_boot_<fase>.png)
##     BOOT_FMV_T    com BOOT_FASE=fmv: segundo do vídeo a capturar (testa a legenda)

var _cena: Node
var _saida := ""
var _fase := "menu"
var _quadros := 0
var _armado := false


func _initialize() -> void:
	_fase = _env("BOOT_FASE", "menu")
	_saida = _env("BOOT_OUT", "res://_boot_%s.png" % _fase)
	var packed: PackedScene = load("res://scenes/boot.tscn")
	_cena = packed.instantiate()
	_cena.set("entrar_no_jogo", false)
	_cena.set("tocar_fmv", _fase == "fmv")
	root.add_child(_cena)


func _armar() -> void:
	if _fase == "dificuldade":
		_cena.call("_ir_para_passo", "menu")
		var tt: Object = _cena.get("titulo")
		tt.set("fase", Titulo.Fase.DIFICULDADE)
	else:
		_cena.call("_ir_para_passo", _fase)
	var cur := _env("BOOT_CURSOR", "")
	if cur != "":
		var t2: Object = _cena.get("titulo")
		t2.set("cursor", int(cur))
		t2.set("fase", Titulo.Fase.MENU)
	var n := int(_env("BOOT_TICKS", "0"))
	if n > 0:
		_cena.call("avancar_ticks", n)
	print("[boot-shot] fase=%s passo=%s ticks=%d -> %s"
		% [_fase, _cena.call("passo_atual"), n, _saida])


func _posicionar_fmv() -> void:
	## Salta o vídeo para `BOOT_FMV_T` e força a cue da legenda daquele instante.
	var t := float(_env("BOOT_FMV_T", "0"))
	if t <= 0.0:
		return
	var v: Object = _cena.get("video")
	var p: VideoStreamPlayer = v.get("player")
	if p == null:
		return
	p.stream_position = t
	var cues: Array = v.get("legendas")
	print("[boot-shot] fmv t=%.2fs cue=%d linhas=%s"
		% [t, VideoFmv.cue_em(cues, t), VideoFmv.linhas_de(cues, VideoFmv.cue_em(cues, t))])


func _process(_delta: float) -> bool:
	_quadros += 1
	if not _armado:
		_armado = true
		_armar()
		return false
	if _fase == "fmv":
		# o vídeo precisa de alguns quadros para decodificar antes de valer a captura
		if _quadros == 3:
			_posicionar_fmv()
		if _quadros < 20:
			return false
	else:
		# congela o passo: sem isso o `_process` do Boot faria a fase andar antes do clique
		_cena.set("process_mode", Node.PROCESS_MODE_DISABLED)
	if _quadros < 8:                             ## deixa o webp carregar e compor
		return false
	var img := root.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(_saida)
	var err := img.save_png(abs_path)
	print("[boot-shot] %s %s (%dx%d)" % ["salvo" if err == OK else "ERRO ao salvar",
		abs_path, img.get_width(), img.get_height()])
	quit(0 if err == OK else 1)
	return true


func _env(nome: String, padrao: String) -> String:
	var v := OS.get_environment(nome)
	return v if v != "" else padrao
