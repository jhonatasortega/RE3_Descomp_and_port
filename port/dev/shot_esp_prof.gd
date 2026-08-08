extends SceneTree
## Prova VISUAL da profundidade do fogo, em bancada (sem o `game.tscn`).
##
## Por que bancada: no jogo a câmera é escolhida pelo RVD a partir da posição da Jill, e para
## fotografar uma câmera ESCOLHIDA seria preciso mexer no `screen.gd` (não é meu território).
## Aqui monto a MESMA pilha de apresentação que o `screen.gd` monta — background 2D, o
## `SubViewportContainer` do 3D por cima, o `EspSala` ANTES dele, e o `Occlusion` por cima de
## tudo — e mando a câmera na mão.
##
## Salva, por câmera: `_semfogo` (só cenário), `_sem_prof` (fogo sem profundidade, como
## estava) e `_com_prof` (fogo com profundidade). A diferença entre os dois últimos são
## exatamente os pixels que os recortes do cenário passaram a cobrir.
##
##     GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
##     ESP_CAMS=0,10 "$GODOT" --path port --rendering-driver opengl3 --script res://dev/shot_esp_prof.gd
##
## ⚠ NÃO usar `--headless` (o driver dummy não renderiza).
##
##     ESP_SALA   sala (default R10D)
##     ESP_CAMS   câmeras (default 0)
##     ESP_DIR    saída (default res://dev/_esp)
##     ESP_JILL   "x,z" do personagem que dá a chave de OT (default 9404,-13317)

const W := 1280
const H := 960

var _dir := "res://dev/_esp"
var _sala := "R10D"
var _cams: Array[int] = []
var _jill := Vector3i(9404, 0, -13317)
var _room: RoomData
var _bg: Sprite2D
var _frame: SubViewportContainer
var _vp: SubViewport
var _cam3d: Camera3D
var _esp: EspSala
var _occ: Occlusion
var _t := 0
var _passo := 0
var _cam_i := 0
var _salvos := 0


func _initialize() -> void:
	_sala = _env("ESP_SALA", "R10D")
	_dir = _env("ESP_DIR", "res://dev/_esp")
	for s in _env("ESP_CAMS", "0").split(","):
		if s.strip_edges() != "":
			_cams.append(int(s))
	var j := _env("ESP_JILL", "").split(",")
	if j.size() == 2:
		_jill = Vector3i(int(j[0]), 0, int(j[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))

	_room = RoomData.load_room(_sala)
	var raiz := Node2D.new()
	raiz.name = "Bancada"
	root.add_child(raiz)

	_bg = Sprite2D.new()
	_bg.centered = false
	raiz.add_child(_bg)

	_esp = EspSala.new()
	raiz.add_child(_esp)                      ## ANTES do 3D: é a camada de trás

	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_frame = SubViewportContainer.new()
	_frame.stretch = true
	_frame.size = Vector2(W, H)
	_frame.add_child(_vp)
	raiz.add_child(_frame)
	_cam3d = Camera3D.new()
	_vp.add_child(_cam3d)

	_occ = Occlusion.new()
	_occ.modo = Occlusion.Modo.PROFUNDIDADE
	raiz.add_child(_occ)

	print("[prof] %s · %d câmera(s) · Jill em %s" % [_sala, _cams.size(), _jill])


func _process(_d: float) -> bool:
	_t += 1
	if _t < 3:
		return false
	if _cam_i >= _cams.size():
		print("[prof] fim: %d PNG em %s" % [_salvos, _dir])
		return true
	var cam := _cams[_cam_i]
	match _passo:
		0:
			_montar_camera(cam)
			_esp.carregar(_sala)
			_esp.visible = false
			_passo = 1
		1:
			_salvar("%s_cam%d_semfogo.png" % [_sala, cam])
			_esp.visible = true
			_esp.profundidade = false
			_passar(cam)
			_passo = 2
		2:
			_salvar("%s_cam%d_sem_prof.png" % [_sala, cam])
			# `reprojetar` NÃO avança a animação: as duas fotos ficam no MESMO quadro da
			# chama, então a diferença entre elas é só o efeito da profundidade.
			_esp.profundidade = true
			_esp.reprojetar(_cam3d)
			_passo = 3
		3:
			_salvar("%s_cam%d_com_prof.png" % [_sala, cam])
			print("[prof] cam %d · chave da Jill=%d · %d chama(s) · cobertura %s · %s" % [
				cam, _occ.char_key, _esp.efeitos.size(),
				_esp.recortes_de_cobertura(), _occ.info()])
			_passo = 0
			_cam_i += 1
	return false


func _montar_camera(cam: int) -> void:
	var c := _room.camera(cam)
	CameraRID.apply(_cam3d, c)
	var tex := CameraRID.background(_sala, cam)
	_bg.texture = tex
	if tex != null:
		_bg.scale = Vector2(float(W) / float(tex.get_width()),
			float(H) / float(tex.get_height()))
	_occ.carregar(_room, cam)
	_occ.atualizar_profundidade(c, _jill)


func _passar(cam: int) -> void:
	## 4 ticks para a chama sair do quadro 0 (o laço tem 10 quadros de 1 tick).
	for i in 4:
		_esp.avancar(_cam3d, _room, cam, _occ.char_key)


func _salvar(nome: String) -> void:
	var img := root.get_texture().get_image()
	if img.save_png(ProjectSettings.globalize_path("%s/%s" % [_dir, nome])) == OK:
		_salvos += 1
		print("[prof] salvo %s (%dx%d)" % [nome, img.get_width(), img.get_height()])
	else:
		print("[prof] ERRO ao salvar %s — rodou com --headless?" % nome)


func _env(nome: String, padrao: String) -> String:
	var v := OS.get_environment(nome)
	return v if v != "" else padrao
