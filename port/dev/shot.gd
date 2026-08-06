extends SceneTree
## Harness de screenshot (P0-09) — carrega uma cena, deixa renderizar N ticks e salva PNG.
##
## Sem isso não existe validação visual: os gates da F1 (P1-14), da oclusão (P1-07) e do
## modo de tela (P1-15) são comparações de imagem contra o original.
##
##     GODOT="C:/.../godot.windows.opt.tools.64.exe"
##     "$GODOT" --path port --rendering-driver opengl3 --script res://dev/shot.gd
##
## ⚠ NÃO usar `--headless` aqui: o driver dummy não renderiza (a imagem sai vazia).
## Overrides por variável de ambiente (padrão herdado de godot/dev/tools_shot.gd):
##     SHOT_SCENE  cena a instanciar     (default res://scenes/game.tscn)
##     SHOT_OUT    PNG de saída          (default res://_shot.png)
##     SHOT_TICKS  ticks antes do clique (default 8)
##     SHOT_REPLAY replay de Pad a aplicar antes do clique (arquivo .json)

var _ticks_alvo := 8
var _ticks := 0
var _cena: Node
var _saida := "res://_shot.png"


func _initialize() -> void:
	var cena_path := _env("SHOT_SCENE", "res://scenes/game.tscn")
	_saida = _env("SHOT_OUT", "res://_shot.png")
	_ticks_alvo = int(_env("SHOT_TICKS", "8"))

	if not ResourceLoader.exists(cena_path):
		print("[shot] cena não encontrada: %s" % cena_path)
		print("[shot] (esperado nesta fase: a cena de jogo entra na F1 — P1-15)")
		quit(1)
		return
	var packed: PackedScene = load(cena_path)
	_cena = packed.instantiate()
	# Overrides de cena (usados pelos testes visuais): sem ator, modo de oclusão, sala/câmera.
	if _env("SHOT_NO_ACTOR", "") != "":
		_cena.set("actor_model", "")
	var occ := _env("SHOT_OCC", "")
	if occ != "":
		_cena.set("occlusion_mode", int(occ))
	var sala := _env("SHOT_ROOM", "")
	if sala != "":
		_cena.set("room_id", sala)
	var arma := _env("SHOT_WEAPON", "")
	if arma != "":
		_cena.set("weapon_model", arma)
	var fovf := _env("SHOT_FOV", "")
	if fovf != "":
		_cena.set("fov_override", float(fovf))
	if _env("SHOT_DEBUG", "") != "":
		_cena.set("debug_collision", true)
	var ps := _env("SHOT_POS", "")
	if ps != "":
		var partes := ps.split(",")
		if partes.size() == 3:
			_cena.set("actor_ps1", Vector3i(int(partes[0]), int(partes[1]), int(partes[2])))
	var an := _env("SHOT_ANIM", "")
	if an != "":
		_cena.set("actor_anim", an)
	var gy := _env("SHOT_GRADE", "")
	if gy != "":
		_cena.set("grade_y", int(gy))
		_cena.call_deferred("_grade_chao")
	if _env("SHOT_AOT", "") != "":
		_cena.call_deferred("_alternar_aots")
	var cam := _env("SHOT_CAM", "")
	if cam != "":
		_cena.set("camera_index", int(cam))
	root.add_child(_cena)

	if _env("SHOT_DOOR", "") != "":
		# vai até a porta e deixa o tick atravessar: prova a transição de sala no render real
		_cena.call_deferred("_ir_para_porta")
	var replay := _env("SHOT_REPLAY", "")
	if replay != "" and Engine.has_singleton("Game"):
		var g: Variant = Engine.get_singleton("Game")
		g.pad.load_replay(g.pad.read_replay(replay))
		print("[shot] replay carregado: %s (%d ticks)" % [replay, g.pad.replay_length()])
	print("[shot] cena=%s ticks=%d -> %s" % [cena_path, _ticks_alvo, _saida])


func _process(_delta: float) -> bool:
	_ticks += 1
	if _ticks < _ticks_alvo:
		return false
	var img := root.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(_saida)
	var err := img.save_png(abs_path)
	if err == OK:
		print("[shot] salvo %s (%dx%d)" % [abs_path, img.get_width(), img.get_height()])
	else:
		print("[shot] ERRO ao salvar (%d) — rodou com --headless? o driver dummy não renderiza" % err)
	quit(0 if err == OK else 1)
	return true


func _env(nome: String, padrao: String) -> String:
	var v := OS.get_environment(nome)
	return v if v != "" else padrao
