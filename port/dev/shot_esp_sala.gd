extends SceneTree
## Foto do FOGO da sala (`present/esp_sala.gd`) para conferência do dono.
##
## O `screen.gd` já monta o `EspSala` (é dono do repo que edita aquele arquivo). Este script
## usa o nó que a cena montou e chama, a cada tick, a versão COM PROFUNDIDADE do `avancar`:
##
##     esp_sala.avancar(cam3d, room, camera_index, occlusion.char_key)
##
## que é exatamente a linha que o `screen.gd` precisa passar a usar (hoje ele chama
## `esp_sala.avancar(cam3d)`, sem os três últimos argumentos). Ou seja: esta foto mostra o
## resultado ANTES de mexer no `screen.gd`, e é a prova de que a linha nova funciona.
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
##     ESP_QUADROS quantos quadros do laço fotografar por câmera (default 2)
##     ESP_THREADS 1 = inclui também os efeitos criados por thread do script
##     ESP_PROF    0 = DESLIGA a profundidade (tudo atrás do 3D) — comparação A/B
##     ESP_DIR     pasta de saída (default res://dev/_esp) — nunca a raiz do port
##     ESP_SEM_FOGO 1 = salva também o mesmo enquadramento SEM o fogo (para diff)
##     ESP_JILL    "x,z" para mover a Jill (a chave de OT dela decide a camada da chama)

var _cena: Node
var _esp: EspSala
var _t := 0
var _fase := 0
var _cams: Array[int] = []
var _cam_i := 0
var _quadro := 0
var _dir := "res://dev/_esp"
var _ticks := 3
var _n_quadros := 2
var _sala := "R10D"
var _salvos := 0
var _semfogo := 0                    ## 0 = ainda com fogo · 1 = apagado · 2 = já salvo


func _initialize() -> void:
	_sala = _env("ESP_SALA", "R10D")
	_dir = _env("ESP_DIR", "res://dev/_esp")
	_ticks = int(_env("ESP_TICKS", "3"))
	_n_quadros = int(_env("ESP_QUADROS", "2"))
	for s in _env("ESP_CAMS", "0,1").split(","):
		if s.strip_edges() != "":
			_cams.append(int(s))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))

	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("room_id", _sala)
	root.add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _fase == 0:
		if _t < 4:
			return false
		_esp = _cena.get("esp_sala")
		if _esp == null:
			print("[esp] screen.gd não expôs `esp_sala` — nada a fazer")
			return true
		_esp.incluir_threads = _env("ESP_THREADS", "") != ""
		_esp.profundidade = _env("ESP_PROF", "1") != "0"
		if not _cena.call("carregar_sala", _sala):
			print("[esp] %s não carregou" % _sala)
			return true
		var jill := _env("ESP_JILL", "")
		if jill != "":
			var p := jill.split(",")
			var pl: Object = _cena.get("player")
			if p.size() == 2 and pl != null:
				pl.set("pos", Vector3i(int(p[0]), 0, int(p[1])))
		print("[esp] %s" % _esp.resumo())
		if _esp.efeitos.is_empty():
			print("[esp] nenhum efeito para desenhar em %s" % _sala)
			return true
		for e_v: Variant in (_esp.efeitos as Array):
			var e: Object = e_v
			print("[esp]   banco 0x%02x ef 0x%02x var %d · f%d · pos %s · %d quadro(s) · "
				% [e.get("tipo"), e.get("efeito"), e.get("variante"), e.get("func_id"),
					e.get("pos"), (e.get("quadros") as Array).size()]
				+ "%s · %.0f un PS1 de largura (param_hi=0x%04x)"
					% ["HD 4x" if e.get("hd") else "SD", e.call("larg_ps1"),
						e.get("escala")])
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
		_avancar_com_profundidade()
		if _t % _ticks != 0:
			return false
		if _quadro < _n_quadros:
			_salvar("%s_cam%d_q%d.png" % [_sala, cam, _quadro])
			_relatar(cam, _quadro)
			_quadro += 1
			return false
		if _env("ESP_SEM_FOGO", "") != "" and _semfogo == 0:
			_esp.visible = false
			_semfogo = 1
			return false                        ## o quadro só reflete no tick seguinte
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


func _avancar_com_profundidade() -> void:
	## A LINHA NOVA do `screen.gd`, aplicada de fora.
	var cam3d: Camera3D = _cena.get("cam3d")
	var room: RoomData = _cena.get("room")
	var occ: Occlusion = _cena.get("occlusion")
	var idx := int(_cena.get("camera_index"))
	_esp.avancar(cam3d, room, idx, occ.char_key if occ != null else EspSala.CHAVE_INDEFINIDA)


func _relatar(cam: int, quadro: int) -> void:
	## Uma linha por chama: chave de OT, camada e posição de tela — é onde se confere se a
	## profundidade decidiu o que os olhos veem.
	var occ: Occlusion = _cena.get("occlusion")
	print("[esp] cam %d quadro %d · chave do personagem = %d · recortes de cobertura %s" % [
		cam, quadro, _esp.chave_personagem, _esp.recortes_de_cobertura()])
	if occ != null:
		print("[esp]   oclusão: %s" % occ.info())
	for e_v: Variant in (_esp.efeitos as Array):
		var e: Object = e_v
		var no: Sprite2D = e.get("no")
		print("[esp]   t%02x pos %s chave=%d %s tela=%s %s" % [
			e.get("tipo"), e.get("pos"), e.get("chave"),
			"FRENTE" if e.get("na_frente") else "atrás",
			no.position if no != null else Vector2.ZERO,
			"visível" if no != null and no.visible else "fora de tela"])


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
