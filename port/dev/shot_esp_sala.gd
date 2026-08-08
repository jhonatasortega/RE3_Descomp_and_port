extends SceneTree
## Foto do FOGO da sala (`present/esp_sala.gd`) para conferência do dono.
##
## Engata o `EspSala` no SubViewport 3D do `screen.gd` **de fora** (o `screen.gd` não foi
## alterado: quem o edita é o dono do repo), carrega a sala, roda o relógio de 30 Hz e salva
## um PNG por câmera + um PNG por quadro do laço da chama.
##
##     GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
##     "$GODOT" --path port --rendering-driver opengl3 --script res://dev/shot_esp_sala.gd
##
## ⚠ NÃO usar `--headless`: o driver dummy não renderiza e o PNG sai vazio.
##
## Variáveis de ambiente:
##     ESP_SALA    sala (default R10D)
##     ESP_CAMS    câmeras a fotografar, separadas por vírgula (default 0,1)
##     ESP_TICKS   ticks de 30 Hz entre fotos (default 3)
##     ESP_QUADROS quantos quadros do laço fotografar por câmera (default 3)
##     ESP_THREADS 1 = inclui também os efeitos criados por thread do script
##     ESP_DIR     pasta de saída (default res://dev/_esp) — nunca a raiz do port
##     ESP_SEM_FOGO 1 = salva também o mesmo enquadramento SEM o fogo (para diff)

var _cena: Node
var _esp: EspSala
var _t := 0
var _fase := 0
var _cams: Array[int] = []
var _cam_i := 0
var _quadro := 0
var _dir := "res://dev/_esp"
var _ticks := 3
var _n_quadros := 3
var _sala := "R10D"
var _salvos := 0
var _semfogo := 0                    ## 0 = ainda com fogo · 1 = apagado · 2 = já salvo


func _initialize() -> void:
	_sala = _env("ESP_SALA", "R10D")
	_dir = _env("ESP_DIR", "res://dev/_esp")
	_ticks = int(_env("ESP_TICKS", "3"))
	_n_quadros = int(_env("ESP_QUADROS", "3"))
	for s in _env("ESP_CAMS", "0,1").split(","):
		if s.strip_edges() != "":
			_cams.append(int(s))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))

	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("room_id", _sala)
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)   ## a oclusão é outro item
	root.add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _fase == 0:
		if _t < 4:
			return false
		# ── engate: o EspSala mora DENTRO do SubViewport 3D do mundo ──
		var world: SubViewport = _cena.get("world")
		if world == null:
			print("[esp] screen.gd não expôs `world` — nada a fazer")
			return true
		_esp = EspSala.new()
		_esp.incluir_threads = _env("ESP_THREADS", "") != ""
		world.add_child(_esp)
		if not _cena.call("carregar_sala", _sala):
			print("[esp] %s não carregou" % _sala)
			return true
		var n: int = _esp.carregar(_sala)
		print("[esp] %s" % _esp.resumo())
		if n == 0:
			print("[esp] nenhum efeito para desenhar em %s" % _sala)
			return true
		for e_v: Variant in (_esp.efeitos as Array):
			var e: Object = e_v
			var m: QuadMesh = (e.get("no") as MeshInstance3D).mesh
			print("[esp]   banco 0x%02x ef 0x%02x var %d · f%d · pos %s · %d quadro(s) · "
				% [e.get("tipo"), e.get("efeito"), e.get("variante"), e.get("func_id"),
					e.get("pos"), (e.get("quadros") as Array).size()]
				+ "quad %.3f x %.3f un Godot (param_hi=0x%04x)"
					% [m.size.x, m.size.y, e.get("escala")])
		_fase = 1
		_t = 0
		return false

	if _fase == 1:
		# O tick do `screen.gd` devolve a câmera do RVD (a zona onde o player está); para
		# fotografar uma câmera escolhida é preciso segurar as duas pontas.
		var cam := _cams[_cam_i]
		var mundo: Object = _cena.get("mundo")
		if mundo != null:
			mundo.set("camera", cam)
		if int(_cena.get("camera_index")) != cam:
			_cena.call("mostrar_camera", cam)
			return false                        ## 1 tick para o background/projeção assentar
		if _t % _ticks != 0:
			_esp.avancar()
			return false
		_esp.avancar()
		if _quadro < _n_quadros:
			_salvar("%s_cam%d_q%d.png" % [_sala, cam, _quadro])
			_recortes(cam, _quadro)
			_quadro += 1
			return false
		if _env("ESP_SEM_FOGO", "") != "" and _semfogo == 0:
			_esp.visible = false
			_semfogo = 1
			return false                        ## o SubViewport só reflete no tick seguinte
		if _semfogo == 1:
			_salvar("%s_cam%d_SEMFOGO.png" % [_sala, cam])
			_esp.visible = true
			_semfogo = 2
			return false
		_quadro = 0
		_semfogo = 0
		_cam_i += 1
		if _cam_i >= _cams.size():
			print("[esp] fim: %d PNG em %s" % [_salvos, _dir])
			return true
		return false
	return true


func _recortes(cam: int, quadro: int) -> void:
	## Um recorte ampliado em volta de cada chama VISÍVEL — é onde se confere se ela caiu
	## no lugar do fogo do cenário e não num canto qualquer.
	var world: SubViewport = _cena.get("world")
	var c3d: Camera3D = _cena.get("cam3d")
	if world == null or c3d == null:
		return
	var img := root.get_texture().get_image()
	var i := 0
	for e_v: Variant in (_esp.efeitos as Array):
		var e: Object = e_v
		var no: MeshInstance3D = e.get("no")
		i += 1
		if no == null or c3d.is_position_behind(no.global_position):
			continue
		var p := c3d.unproject_position(no.global_position)
		var lado := 260
		var r := Rect2i(int(p.x) - lado / 2, int(p.y) - lado / 2, lado, lado)
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if r.size.x < 16 or r.size.y < 16:
			continue
		var corte := img.get_region(r)
		corte.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_NEAREST)
		var nome := "%s_cam%d_q%d_chama%d_t%02x.png" % [_sala, cam, quadro, i, e.get("tipo")]
		if corte.save_png(ProjectSettings.globalize_path("%s/%s" % [_dir, nome])) == OK:
			_salvos += 1
			print("[esp]   recorte %s em tela (%d,%d)" % [nome, int(p.x), int(p.y)])


func _salvar(nome: String) -> void:
	var img := root.get_texture().get_image()
	var caminho := ProjectSettings.globalize_path("%s/%s" % [_dir, nome])
	if img.save_png(caminho) == OK:
		_salvos += 1
		print("[esp] salvo %s (%dx%d)" % [caminho, img.get_width(), img.get_height()])
	else:
		print("[esp] ERRO ao salvar %s — rodou com --headless?" % nome)


func _env(nome: String, padrao: String) -> String:
	var v := OS.get_environment(nome)
	return v if v != "" else padrao
