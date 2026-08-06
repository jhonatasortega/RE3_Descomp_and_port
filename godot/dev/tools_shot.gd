extends SceneTree
## Harness de screenshot/calibracao: instancia game_room.tscn, deixa renderizar
## alguns frames e salva um PNG do viewport raiz.
## Rodar com: --rendering-driver opengl3 (headless usa driver dummy, nao renderiza).
##
## Overrides por variavel de ambiente (para iterar calibracao sem editar arquivos):
##   SHOT_OUT   caminho de saida (default res://_shot.png)
##   JILL_PS1   "x,y,z" posicao da Jill em coords PS1
##   JILL_FACE  facing em graus
##   FOV        FOV vertical da camera
##   WSCALE     world_scale
##   FOOT       foot_offset do modelo
##   CAM        indice de camera

var _frames := 0
var _scene: Node


func _initialize() -> void:
	var packed := load("res://scenes/game_room.tscn")
	if packed == null:
		push_error("Falha ao carregar game_room.tscn")
		quit(1)
		return
	_scene = packed.instantiate()
	# aplica overrides ANTES de add_child para que _ready use os valores
	if OS.has_environment("WSCALE"):
		_scene.world_scale = float(OS.get_environment("WSCALE"))
	if OS.has_environment("FOV"):
		_scene.camera_fov = float(OS.get_environment("FOV"))
	if OS.has_environment("CAM"):
		_scene.start_camera = int(OS.get_environment("CAM"))
	if OS.has_environment("JILL_PS1"):
		_scene.jill_start_ps1 = _parse_vec(OS.get_environment("JILL_PS1"))
	if OS.has_environment("JILL_FACE"):
		_scene.jill_start_facing_deg = float(OS.get_environment("JILL_FACE"))
	# --- calibracao da OCLUSAO (holdout 3D) ---
	if OS.has_environment("OCC"):
		_scene.occlusion_enabled = OS.get_environment("OCC") != "0"
	if OS.has_environment("OCC_H"):
		_scene.occluder_height = float(OS.get_environment("OCC_H"))
	if OS.has_environment("FLOORY"):
		_scene.floor_y_godot = float(OS.get_environment("FLOORY"))
	if OS.has_environment("FLIPY"):
		_scene.occluder_flip_y = OS.get_environment("FLIPY") != "0"
	if OS.has_environment("DBG"):
		_scene.occluder_debug = OS.get_environment("DBG") != "0"
	if OS.has_environment("ROOM"):
		_scene.room = OS.get_environment("ROOM")
	var jill := _scene.get_node("Viewport/SubViewport/Jill")
	if OS.has_environment("FOOT"):
		jill.foot_offset = float(OS.get_environment("FOOT"))
	get_root().add_child(_scene)
	# (a camera e' congelada em _process, DEPOIS que _ready da cena rodar — num
	#  SceneTree --script o _ready da cena e' adiado para o 1o frame.)
	# Ao forcar uma ANIM, desliga o tank-control da Jill: sem input ele voltaria a
	# _play_static(idle) todo physics-frame e sobrescreveria a pose forcada.
	if OS.has_environment("ANIM"):
		jill.set_physics_process(false)


func _parse_vec(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() >= 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ZERO


func _parse_vec2(s: String) -> Vector2:
	var p := s.split(",")
	if p.size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


func _process(_delta: float) -> bool:
	_frames += 1
	# Congela a camera para validacao (apos o _ready da cena, no 1o frame).
	if _frames == 2:
		if OS.has_environment("AUTO"):
			_scene.auto_camera = OS.get_environment("AUTO") != "0"
		if OS.has_environment("FORCE_CAM"):
			_scene.auto_camera = false
			_scene._show_camera(int(OS.get_environment("FORCE_CAM")))
	# Forca uma animacao especifica (ANIM) num frame (SEEK 0..1) direto no
	# AnimationPlayer da Jill do JOGO — valida a pose real in-game (andar/correr/parado).
	if _frames >= 20 and OS.has_environment("ANIM"):
		# Re-aplica a pose TODO frame (pause nao segura neste build; mesmo truque do
		# tools_anim_shot.gd). speed_scale=0 impede o clipe de avancar sozinho.
		var jill = _scene.jill
		var ap: AnimationPlayer = jill._anim
		var an := OS.get_environment("ANIM")
		if ap and ap.has_animation(an):
			var frac := float(OS.get_environment("SEEK")) if OS.has_environment("SEEK") else 0.5
			ap.play(an)
			ap.speed_scale = 0.0
			ap.seek(ap.get_animation(an).length * frac, true)
	elif _frames == 20 and OS.has_environment("SEEK"):
		var jill = _scene.jill
		var ap: AnimationPlayer = jill._anim
		if ap and ap.has_animation(jill._current_anim):
			ap.seek(ap.get_animation(jill._current_anim).length * float(OS.get_environment("SEEK")), true)
			ap.pause()
	if _frames == 30:
		var out := "res://_shot.png"
		if OS.has_environment("SHOT_OUT"):
			out = OS.get_environment("SHOT_OUT")
		var img := get_root().get_texture().get_image()
		var err := img.save_png(out)
		print("SHOT saved=", out, " err=", err, " jill=", _scene.jill.global_position, " cam=", _scene.cam3d.global_position, " fov=", _scene.camera_fov)
		# --- DIAGNOSTICO: qual animacao esta REALMENTE tocando in-game? ---
		var jill = _scene.jill
		var ap: AnimationPlayer = jill._anim
		if ap == null:
			print("DIAG: _anim == NULL !!")
		else:
			print("DIAG _current_anim(ctrl)=", jill._current_anim,
				" | AP.current_animation=", ap.current_animation,
				" | AP.autoplay=", ap.autoplay,
				" | is_playing=", ap.is_playing(),
				" | speed_scale=", ap.speed_scale,
				" | list=", ap.get_animation_list())
			print("DIAG model_yaw=", jill.model_yaw_offset_deg, " foot=", jill.foot_offset, " scale=", jill.model_scale, " model_pos=", jill._model.position if jill._model else "nil")
		quit()
		return true
	return false
