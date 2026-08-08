extends SceneTree
## Diagnóstico VISUAL do overlay de MIRA (`miraNN` = banco parcial nb=9 do `.PLW`).
##
## Monta a Jill do `PL00.glb` e fotografa uma grade de poses para conferir A OLHO que o
## BRAÇO LEVANTA e que as pernas ficam com o clipe de locomoção — o overlay só troca os
## ossos 0..8 (ver `docs/decomp/notes/plw.md` §9).
##
## Grade (linha de cima: base = `arm02`, idle armado; linha de baixo: base = `arm00`, andando):
##   1. base pura (referência: braço ABAIXADO)
##   2. `mira00` no fim  -> arma LEVANTADA
##   3. `mira02`         -> mira MÉDIA (aim_tier 0 -> pose 14 do EXE)
##   4. `mira04`         -> mira ALTA
##   5. `mira06`         -> mira BAIXA
##   6. `mira07` a 35%   -> TIRO / recuo
## Na linha de baixo as PERNAS têm de continuar no passo do `arm00` enquanto o braço mira —
## é a prova visual de que o clipe parcial não mexe em `bone09..bone14`.
##
##     "<godot>" --path port --rendering-driver opengl3 --script res://dev/shot_mira_overlay.gd
##     CELL=384 "<godot>" ... (célula maior)
##
## Saída: `port/dev/_mira_overlay.png` (o `.gitignore` cobre `port/dev/*.png`).

const GLB := "PLD/PL00.glb"
const SAIDA := "res://dev/_mira_overlay.png"
const OSSOS_SUP := [0, 1, 2, 3, 4, 5, 6, 7, 8]   ## de-para provado do banco parcial nb=9
const COLS := 6

## base, frac_base, overlay, frac_overlay, rótulo
const CELULAS := [
	["arm02", 0.0, "", 0.0, "arm02 puro (braco ABAIXADO)"],
	["arm02", 0.0, "mira00", 1.0, "mira00 fim = LEVANTOU a arma"],
	["arm02", 0.0, "mira02", 0.0, "mira02 = mira MEDIA (tier 0)"],
	["arm02", 0.0, "mira04", 0.0, "mira04 = mira ALTA"],
	["arm02", 0.0, "mira06", 0.0, "mira06 = mira BAIXA"],
	["arm02", 0.0, "mira07", 0.35, "mira07 = TIRO / recuo"],
	["arm00", 0.4, "", 0.0, "arm00 andando (sem overlay)"],
	["arm00", 0.4, "mira00", 1.0, "arm00 + mira00"],
	["arm00", 0.4, "mira02", 0.0, "arm00 + mira MEDIA"],
	["arm00", 0.4, "mira04", 0.0, "arm00 + mira ALTA"],
	["arm00", 0.4, "mira06", 0.0, "arm00 + mira BAIXA"],
	["arm00", 0.4, "mira07", 0.35, "arm00 + TIRO"],
]

var _cell := 320
var _i := 0
var _sub := 0
var _warm := 0
var _view: SubViewport
var _folha: Image
var _falhou := false


func _initialize() -> void:
	if OS.get_environment("CELL") != "":
		_cell = maxi(96, int(OS.get_environment("CELL")))
	_view = SubViewport.new()
	_view.size = Vector2i(_cell, _cell)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_view)
	var luz := DirectionalLight3D.new()
	luz.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(-35.0), 0.0)
	luz.light_energy = 1.6
	_view.add_child(luz)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 0.8
	amb.environment = env
	_view.add_child(amb)
	var cam := Camera3D.new()
	## o modelo tem o quadril na ORIGEM: pés em y≈-1.74, topo da cabeça em y≈+0.95
	## (SCALE=0.001, eixo glTF (x,-y,-z)). Nas poses de mira a mão sobe ACIMA da cabeça,
	## então o enquadramento tem de sobrar em cima.
	cam.position = Vector3(0.0, -0.35, 5.4)
	cam.fov = 40.0
	_view.add_child(cam)
	var linhas := int(ceil(float(CELULAS.size()) / COLS))
	_folha = Image.create(_cell * COLS, _cell * linhas, false, Image.FORMAT_RGBA8)
	_folha.fill(Color(0.06, 0.06, 0.08))
	print("[ov] grade %dx%d, celula %dpx" % [COLS, linhas, _cell])


func _process(_d: float) -> bool:
	_warm += 1
	if _warm < 4:
		return false                                  ## deixa o render subir
	if _i >= CELULAS.size():
		## grade de separadores p/ ficar claro onde uma célula termina
		var linhas2 := int(ceil(float(CELULAS.size()) / COLS))
		for cx in range(1, COLS):
			for y in _folha.get_height():
				_folha.set_pixel(cx * _cell, y, Color(0.35, 0.35, 0.42))
		for cy in range(1, linhas2):
			for x in _folha.get_width():
				_folha.set_pixel(x, cy * _cell, Color(0.35, 0.35, 0.42))
		var abs_path := ProjectSettings.globalize_path(SAIDA)
		_folha.save_png(abs_path)
		print("[ov] -> %s" % abs_path)
		print("[ov] confira: colunas 2..6 com o BRACO/ARMA levantado; na linha de baixo as")
		print("[ov]          PERNAS seguem no passo do arm00 (overlay so troca %s)" % [OSSOS_SUP])
		return true
	var c: Array = CELULAS[_i]
	if _sub == 0:
		if not _montar(String(c[0]), float(c[1]), String(c[2]), float(c[3])):
			_falhou = true
			return true
		_sub = 1
		return false
	## quadro seguinte: a textura do SubViewport já tem a pose
	var tex := _view.get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			_folha.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i((_i % COLS) * _cell, (_i / COLS) * _cell))
	print("[ov] %2d  base=%-6s(%.2f) overlay=%-7s(%.2f)  %s" % [_i, c[0], c[1], c[2], c[3], c[4]])
	_i += 1
	_sub = 0
	return false


func _montar(base: String, fb: float, overlay: String, fo: float) -> bool:
	## Troca o modelo do SubViewport e aplica a pose combinada.
	for c in _view.get_children():
		if c is Node3D and not (c is Camera3D or c is DirectionalLight3D):
			_view.remove_child(c)
			c.queue_free()
	var modelo := AssetIO.model(GLB)
	if modelo == null:
		push_error("shot_mira_overlay: %s ausente (tools/build_assets.py --out port --only pld)" % GLB)
		return false
	var ap := AssetIO.anim_player(modelo)
	var esq := _skeleton(modelo)
	if ap == null or esq == null:
		push_error("shot_mira_overlay: %s sem AnimationPlayer/Skeleton3D" % GLB)
		return false
	## OVERLAY POR SUBSTITUIÇÃO: o clipe de base posa os 15 ossos; o clipe parcial
	## SOBRESCREVE os 9 do de-para. É o que o `.glb` já expressa (o clipe parcial não tem
	## trilha para `bone09..bone14`), aqui só reproduzimos isso à mão para a foto.
	var a_base: Animation = ap.get_animation(base)
	var a_ov: Animation = null if overlay == "" else ap.get_animation(overlay)
	for b in esq.get_bone_count():
		var q := _rot(esq, a_base, b, fb)
		if a_ov != null and OSSOS_SUP.has(b):
			q = _rot(esq, a_ov, b, fo)
		esq.set_bone_pose_rotation(b, q)
	## 3/4 (padrão) ou de perfil (`VISTA=lado`): é o ângulo em que o braço levantado aparece.
	var yaw := -90.0 if OS.get_environment("VISTA") == "lado" else -40.0
	modelo.rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)
	_view.add_child(modelo)
	return true


func _rot(esq: Skeleton3D, a: Animation, osso: int, frac: float) -> Quaternion:
	var rest := esq.get_bone_rest(osso).basis.get_rotation_quaternion()
	if a == null:
		return rest
	var alvo := esq.get_bone_name(osso)
	for k in a.get_track_count():
		if a.track_get_type(k) != Animation.TYPE_ROTATION_3D:
			continue
		if String(a.track_get_path(k)).get_slice(":", 1) == alvo:
			return a.rotation_track_interpolate(k, a.length * clampf(frac, 0.0, 1.0))
	return rest


func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skeleton(c)
		if r != null:
			return r
	return null
