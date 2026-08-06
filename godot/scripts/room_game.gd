extends Node2D
## Primeira sala jogavel no estilo classico do RE:
##   Background HD 2D (pre-renderizado) + Jill 3D num SubViewport transparente
##   composto por cima, com camera fixa (ponto-fixo, do ARD/RDT).
##
## Etapa 2 (gameplay):
##   - TROCA DE CAMERA AUTOMATICA por ENQUADRAMENTO (cobertura + histerese; ver a
##     secao "SELECAO DE CAMERA" no fim deste arquivo e docs/godot_gameplay.md).
##   - COLISAO aproximada: area caminhavel = uniao dos quads de zona de camera
##     (formato real da sala) + bloqueios manuais (moveis). Ver docs/godot_gameplay.md.
##
## Conversao PS1 -> Godot:
##   godot = Vector3(ps1.x, -ps1.y, ps1.z) / world_scale
##   (PS1 usa Y para baixo; invertemos o Y. world_scale casa a escala do modelo.)

const TARGET := Vector2(1280, 960)

@export var stage: int = 1
@export var room: String = "R100"

# --- Calibracao (ver docs/godot_gameplay.md) ---
@export var world_scale: float = 808.0          ## unidades PS1 por unidade Godot (2400/2.971 ~= 808)
@export var camera_fov: float = 55.0            ## FOV vertical da Camera3D
@export var start_camera: int = 0               ## camera inicial (fallback se nenhuma zona cobrir o inicio)
## Posicao inicial da Jill em coords PS1 (mesma escala do ARD).
@export var jill_start_ps1: Vector3 = Vector3(-21820, -258, -21899)
@export var jill_start_facing_deg: float = 0.0

@export var auto_camera: bool = true            ## troca de camera automatica por ENQUADRAMENTO (ver secao SELECAO DE CAMERA)
@export var collision_enabled: bool = true      ## barra a Jill fora da area caminhavel
## Histerese temporal: apos trocar, ignora novas avaliacoes por N passos de fisica.
## Rede de seguranca contra jitter; a histerese PRINCIPAL e' espacial (cam_keep_ndc).
@export var switch_cooldown_frames: int = 6
# --- SELECAO DE CAMERA por enquadramento (ver secao e docs/godot_gameplay.md) -----
## Altura (un Godot) do ponto de prova acima dos pes da Jill (~torso). O criterio de
## enquadramento usa o TORSO, nao os pes, para nao penalizar o eixo vertical.
@export var frame_probe_height: float = 1.5
## MANTEM a camera atual enquanto |ndc_x| do ponto <= isto (0=centro, 1=borda).
## Histerese espacial: so troca quando a Jill chega perto da borda da camera atual.
@export var cam_keep_ndc: float = 0.9
## Uma camera so e' candidata a receber a troca se enquadrar com |ndc_x| <= isto.
@export var cam_cover_ndc: float = 1.1
## Portao vertical: descarta a camera se |ndc_y| do ponto passar disto (fora do frustum).
@export var cam_frame_ymax: float = 1.6
## Bloqueios manuais de mobilia (colisao aproximada), em coords PS1 [x0,z0,x1,z1].
## So usados como FALLBACK se a colisao real (offset_table[6]) nao carregar.
@export var manual_blockers: Array = []
## Raio (un PS1) da "casca" da Jill: cada retangulo de colisao e' inflado por este
## valor para ela PARAR na face do movel/parede, nao penetrar ate o centro.
@export var collider_radius: float = 380.0

# --- OCLUSAO (ver secao "OCLUSAO por HOLDOUT 3D" abaixo) --------------------
@export var occlusion_enabled: bool = true

var data: Dictionary = {}
var backgrounds: Array = []
var cameras: Array = []
var rvd: Array = []            # entradas RVD {from,to,quad,degenerate} (grafo de vizinhanca)
var room_quads: Array = []     # quads nao-degenerados (retido p/ compat.; nao usado na selecao)
var cam_neighbors: Dictionary = {}  # cam -> [cams vizinhas], grafo (nao-direcionado) do RVD
var room_min := Vector2.ZERO   # AABB da sala (x,z PS1) — limite caminhavel
var room_max := Vector2.ZERO
var have_bounds := false
var cam_index: int = 0
var _switch_cd: int = 0

# Colisao real (offset_table[6] do RDT). Cada item: {rect:[x0,z0,x1,z1], wall:bool}.
var col_rects: Array = []
# Priority sprites do PS1 (camera.mask_data_ptr) decodificados (tools/rdt_collision.py).
# cam_masks[i] = [{depth, blocks:[{dx,dy,w,h,sx,sy,attr,special}]}] — as REGIOES de 1o
# plano na tela (espaco 320x240) que devem ser redesenhadas por cima da Jill quando ela
# esta atras. Alimenta a OCLUSAO por HOLDOUT (secao abaixo). Ver docs/formatos/ARD.md 3.7.
var cam_masks: Array = []
var cam_mask_depth: Array = []   # primary_depth (Z de ordenacao PS1) por camera

const BOUNDS_MARGIN := 350.0   # recuo (un PS1) pra Jill parar um pouco antes da parede

@onready var bg: Sprite2D = $Background
@onready var vpc: SubViewportContainer = $Viewport
@onready var cam3d: Camera3D = $Viewport/SubViewport/Camera3D
@onready var jill: Node3D = $Viewport/SubViewport/Jill
@onready var sun: DirectionalLight3D = $Viewport/SubViewport/Sun
@onready var world_env: WorldEnvironment = $Viewport/SubViewport/WorldEnvironment
@onready var info: Label = $UI/Info


func _ready() -> void:
	_load_room()
	_setup_occlusion()
	_setup_lighting()
	jill.global_position = ps1_to_godot(jill_start_ps1)
	jill.set_facing(jill_start_facing_deg)
	# a Jill consulta este validador antes de andar (colisao aproximada)
	if collision_enabled and jill.has_method("set_walkable_query"):
		jill.set_walkable_query(Callable(self, "is_walkable_godot"))
	# camera inicial: zona que contem o ponto de partida (senao, start_camera)
	var c0 := _camera_for_point(jill_start_ps1.x, jill_start_ps1.z)
	_show_camera(c0 if c0 >= 0 else start_camera)


func ps1_to_godot(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.y, v.z) / world_scale


func _load_room() -> void:
	var path := "res://data/STAGE%d/%s.json" % [stage, room]
	if not FileAccess.file_exists(path):
		push_error("Sala nao encontrada: " + path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON invalido: " + path)
		data = {}
		return
	var rdt: Dictionary = data.get("rdt", {})
	cameras = rdt.get("cameras", [])
	var rvd_dict = rdt.get("rvd", null)
	rvd = (rvd_dict.get("entries", []) if rvd_dict is Dictionary else [])
	room_quads.clear()
	cam_neighbors.clear()
	for e in rvd:
		if not (e is Dictionary):
			continue
		if not bool(e.get("degenerate", false)):
			room_quads.append(e)
		# grafo de vizinhanca: as entradas RVD (from->to) dizem quais cameras sao
		# adjacentes (transicao AUTORIZADA pelo designer). Nao-direcionado e inclui
		# ate as degeneradas: elas tambem indicam parentesco entre cameras.
		var a := int(e.get("from", -1))
		var b := int(e.get("to", -1))
		if a >= 0 and b >= 0 and a != b:
			if not cam_neighbors.has(a):
				cam_neighbors[a] = []
			if not cam_neighbors.has(b):
				cam_neighbors[b] = []
			if not cam_neighbors[a].has(b):
				cam_neighbors[a].append(b)
			if not cam_neighbors[b].has(a):
				cam_neighbors[b].append(a)
	_compute_bounds(rdt)
	var n := int(rdt.get("n_cameras", cameras.size()))
	backgrounds.clear()
	for i in n:
		var wp := "res://assets/STAGE%d/%s_%d.webp" % [stage, room, i]
		var pp := "res://assets/STAGE%d/%s_%d.png" % [stage, room, i]
		if ResourceLoader.exists(wp):
			backgrounds.append(load(wp))
		elif ResourceLoader.exists(pp):
			backgrounds.append(load(pp))
		else:
			backgrounds.append(null)
	_load_collision()


## Colisao real + layout das mascaras, decodificados do RDT (tools/rdt_collision.py):
## godot/data/STAGE{n}/{sala}_col.json.
func _load_collision() -> void:
	col_rects.clear()
	cam_masks.clear()
	var path := "res://data/STAGE%d/%s_col.json" % [stage, room]
	if not FileAccess.file_exists(path):
		push_warning("Sem colisao decodificada: " + path + " (usando fallback AABB+manual_blockers)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var cd = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(cd) != TYPE_DICTIONARY:
		return
	var col = cd.get("collision", null)
	if col is Dictionary:
		for r in col.get("rects", []):
			if r is Dictionary and r.get("rect", null) is Array:
				col_rects.append({"rect": r["rect"], "wall": bool(r.get("wall", false))})
	for cm in cd.get("cameras_masks", []):
		var groups: Array = []
		if cm is Dictionary:
			for g in cm.get("groups", []):
				groups.append({"depth": int(g.get("depth", 0)), "blocks": g.get("blocks", [])})
		cam_masks.append(groups)
	# primary_depth por camera (do 1o grupo) — profundidade do 1o plano p/ oclusao.
	cam_mask_depth.clear()
	for cm in cd.get("cameras_masks", []):
		cam_mask_depth.append(int(cm.get("primary_depth", 30720)) if cm is Dictionary else 0)


func _physics_process(_delta: float) -> void:
	if auto_camera:
		_update_camera_auto()
	_update_occlusion()
	_update_info()


# --- SELECAO DE CAMERA por ENQUADRAMENTO (COBERTURA + HISTERESE) -------------
## Ver secao "SELECAO DE CAMERA" (fim do arquivo) e docs/godot_gameplay.md.
##
## Por que NAO usamos as zonas RVD como gatilho de borda: no RE3 as zonas nao-deg
## sao FAIXAS DIRECIONAIS de histerese (from->to), estreitas e coladas na FRONTEIRA
## de cobertura da camera de destino. Disparar a troca ao ENTRAR na faixa joga a Jill
## para a BEIRA da tela da camera nova (bug "pula pra beira" na R100). Em vez disso,
## medimos DIRETAMENTE o enquadramento: mantemos a camera atual enquanto ela enquadra
## bem a Jill (|ndc_x| <= cam_keep_ndc) e so trocamos para a que a enquadra melhor.
## Isso e' GERAL (qualquer N de cameras), BIDIRECIONAL e sem flicker. O RVD ainda e'
## usado como GRAFO de vizinhanca (transicoes autorizadas). init == runtime.
func _update_camera_auto() -> void:
	if _switch_cd > 0:
		_switch_cd -= 1
		return
	var p := jill.global_position + Vector3(0.0, frame_probe_height, 0.0)
	# HISTERESE espacial: mantem a camera atual enquanto ela ainda enquadra a Jill.
	if _cam_frame_cost(cam_index, p) <= cam_keep_ndc:
		return
	var nw := _best_camera(p, cam_index)
	if nw >= 0 and nw != cam_index:
		_show_camera(nw)
		_switch_cd = switch_cooldown_frames


## Camera inicial de um ponto (coords PS1 x,z no chao): melhor enquadramento GLOBAL.
## Mesma metrica do runtime (init == runtime), sem camera de preferencia.
func _camera_for_point(px: float, pz: float) -> int:
	var p := ps1_to_godot(Vector3(px, jill_start_ps1.y, pz)) + Vector3(0.0, frame_probe_height, 0.0)
	return _best_camera(p, -1)


## Custo de ENQUADRAMENTO HORIZONTAL de um ponto (coords Godot) na camera i:
## |ndc_x| da projecao (0 = centralizado, 1 = borda da tela). INF se o ponto esta
## ATRAS da camera ou fora do frustum vertical (|ndc_y| > cam_frame_ymax). Como cada
## camera OLHA para seu `to`, o ndc_x mede o desvio angular horizontal da Jill em
## relacao ao eixo da camera -> a camera de menor custo e' a que melhor a enquadra.
## Projecao replicada da Camera3D (fov vertical, keep_aspect=KEEP_HEIGHT, 4:3).
func _cam_frame_cost(i: int, p: Vector3) -> float:
	if i < 0 or i >= cameras.size():
		return INF
	var c: Dictionary = cameras[i]
	var from_v := ps1_to_godot(_arr_to_vec(c.get("from", [0, 0, 0])))
	var to_v := ps1_to_godot(_arr_to_vec(c.get("to", [0, 0, 0])))
	var fwd := to_v - from_v
	if fwd.length() < 0.0001:
		return INF
	fwd = fwd.normalized()
	var up0 := Vector3.UP
	if absf(fwd.dot(up0)) > 0.999:
		up0 = Vector3(0.0, 0.0, 1.0)   # camera quase vertical: troca o up de referencia
	var right := fwd.cross(up0).normalized()
	var up := right.cross(fwd)
	var rel := p - from_v
	var cz := rel.dot(fwd)
	if cz <= 0.001:
		return INF                      # atras da camera
	var f := 1.0 / tan(deg_to_rad(camera_fov) * 0.5)
	var aspect := TARGET.x / TARGET.y
	var ndc_x: float = (rel.dot(right) / cz) * (f / aspect)
	var ndc_y: float = (rel.dot(up) / cz) * f
	if absf(ndc_y) > cam_frame_ymax:
		return INF                      # fora do frustum vertical
	return absf(ndc_x)


## Melhor camera para um ponto (coords Godot). Se prefer >= 0, restringe as candidatas
## aos VIZINHOS RVD de prefer (+ ele mesmo) que enquadrem (custo <= cam_cover_ndc) e
## devolve a de menor custo -> honra as transicoes autorizadas e evita "saltos" para
## cameras que enxergam atraves de parede. Se nenhuma vizinha servir (ou prefer < 0,
## caso do init/salas sem grafo), cai para a MELHOR camera GLOBAL.
func _best_camera(p: Vector3, prefer: int) -> int:
	var best := -1
	var best_cost := INF
	if prefer >= 0:
		var cands: Array = [prefer]
		for nb in cam_neighbors.get(prefer, []):
			cands.append(int(nb))
		for c in cands:
			var cost := _cam_frame_cost(c, p)
			if cost <= cam_cover_ndc and cost < best_cost:
				best_cost = cost
				best = c
		if best >= 0:
			return best
	for c in cameras.size():
		var cost := _cam_frame_cost(c, p)
		if cost < best_cost:
			best_cost = cost
			best = c
	return best


# --- COLISAO APROXIMADA -----------------------------------------------------
## Bounds da sala (AABB) a partir das coords das zonas RVD (ignorando os clamps
## +-32768) + posicoes de portas/itens/entidades. Da o limite de "parede" sem
## os buracos que a uniao de quads teria; a mobilia entra como bloqueios manuais.
func _compute_bounds(rdt: Dictionary) -> void:
	var xs: Array = []
	var zs: Array = []
	for e in rvd:
		if not (e is Dictionary):
			continue
		for p in e.get("quad", []):
			if p is Array and p.size() >= 2:
				var x := float(p[0]); var z := float(p[1])
				if abs(x) < 32000 and abs(z) < 32000:
					xs.append(x); zs.append(z)
	var sc: Dictionary = rdt.get("script", {})
	for grp in [sc.get("doors", []), sc.get("events", []), sc.get("entities", [])]:
		for it in grp:
			var pos = it.get("pos", null) if it is Dictionary else null
			if pos is Array and pos.size() >= 2:
				xs.append(float(pos[0])); zs.append(float(pos[1]))
	if xs.size() >= 2:
		room_min = Vector2(xs.min() + BOUNDS_MARGIN, zs.min() + BOUNDS_MARGIN)
		room_max = Vector2(xs.max() - BOUNDS_MARGIN, zs.max() - BOUNDS_MARGIN)
		have_bounds = room_max.x > room_min.x and room_max.y > room_min.y


## Recebe posicao em unidades Godot; caminhavel = dentro do AABB da sala E fora
## de todos os bloqueios manuais de mobilia.
func is_walkable_godot(pos: Vector3) -> bool:
	return _is_walkable_ps1(pos.x * world_scale, pos.z * world_scale)


func _is_walkable_ps1(px: float, pz: float) -> bool:
	# Limite externo: AABB da sala (mantido como rede de seguranca).
	if have_bounds:
		if px < room_min.x or px > room_max.x or pz < room_min.y or pz > room_max.y:
			return false
	# Colisao REAL: barra dentro de cada retangulo (parede/movel), inflado pelo raio
	# da Jill para ela parar na FACE do objeto. Ver tools/rdt_collision.py.
	if not col_rects.is_empty():
		var r := collider_radius
		for c in col_rects:
			var q = c.get("rect")
			if q is Array and q.size() >= 4:
				if px >= float(q[0]) - r and px <= float(q[2]) + r \
						and pz >= float(q[1]) - r and pz <= float(q[3]) + r:
					return false
		return true
	# Fallback (sem colisao decodificada): bloqueios manuais.
	for b in manual_blockers:
		if b is Array and b.size() >= 4:
			if px >= float(b[0]) and px <= float(b[2]) and pz >= float(b[1]) and pz <= float(b[3]):
				return false
	return true


# --- OCLUSAO por PRIORITY MASKS REAIS (HOLDOUT alinhado a tela) --------------
## Objetivo: as partes do CENARIO que ficam NA FRENTE da Jill (canos, corrimoes, quinas
## de movel em 1o plano, caixa de fusiveis...) devem ESCONDER as partes dela que passam
## por tras. NO PS1 isso e' o sistema de "priority sprites": pedacos do cenario sao
## REDESENHADOS por cima do personagem quando ele esta mais fundo que o pedaco.
##
## FONTE (nao a colisao!): as REGIOES de 1o plano vem das mascaras REAIS do jogo,
## decodificadas de camera.mask_data_ptr (tools/rdt_collision.py -> cam_masks). Cada
## sprite tem {dx,dy,w,h} na TELA (espaco 320x240) e um `depth` (Z de ordenacao PS1) por
## grupo. Isso e' INDEPENDENTE da COLISAO (col_rects): um cano oclui sem colidir; uma
## caixa no chao colide sem ocluir. Ver docs/formatos/ARD.md 3.7 e docs/godot_gameplay.md.
##
## TECNICA (evolucao do holdout): para a camera atual, criamos um QUAD alinhado a TELA por
## sprite, FILHO da Camera3D, posicionado no espaco da camera a uma DISTANCIA (occ) que
## corresponde ao depth do 1o plano, cobrindo exatamente o retangulo (dx,dy,w,h) da tela.
## O quad e' opaco (escreve profundidade) e amostra o BACKGROUND HD (via SCREEN_UV) — logo
## fica visualmente identico a foto. Onde a Jill esta ATRAS do plano (profundidade maior),
## o teste de profundidade da GPU descarta os pixels dela e o cenario reaparece por cima:
## oclusao PIXEL-EXATA (por fragmento da Jill), recortada pela regiao REAL da mascara.
##
## PROFUNDIDADE: o numero `depth` do PS1 nao esta na mesma unidade que o Z-de-camera do
## Godot; convertemos com occ_depth_scale (distancia da camera, un Godot) e CALIBRAMOS por
## render (ver dev/tools_occlusion_val.gd). Um plano por camera (primary_depth). O `attr`
## por-sprite (perto vs longe) fica guardado p/ camadas futuras.

const HOLDOUT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;
uniform sampler2D bg_tex : source_color, filter_nearest;
uniform float flip_y = 0.0;
uniform float debug_tint = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	if (flip_y > 0.5) uv.y = 1.0 - uv.y;
	vec3 bg = texture(bg_tex, uv).rgb;
	ALBEDO = mix(bg, vec3(1.0, 0.0, 0.0), debug_tint);
}
"""

## Distancia (un Godot, espaco de camera) do PLANO de 1o plano = primary_depth * escala.
## Calibrado por render (dev/tools_occlusion_val.gd). primary_depth tipico = 30720.
@export var occ_depth_scale: float = 0.000196   ## ~= 6.0 un Godot p/ depth 30720
@export var occ_depth_min: float = 0.35          ## distancia minima do plano (evita clip)
@export var occluder_flip_y: bool = false        ## inverte V ao amostrar o background
@export var occluder_debug: bool = false         ## pinta os quads de vermelho (calibracao)
var _holdout_mat: ShaderMaterial
var _occ_holder: Node3D
var _occ_screen := Vector2(320.0, 240.0)         ## espaco de tela das coords dx,dy


func _setup_occlusion() -> void:
	var sh := Shader.new()
	sh.code = HOLDOUT_SHADER
	_holdout_mat = ShaderMaterial.new()
	_holdout_mat.shader = sh
	_holdout_mat.set_shader_parameter("flip_y", 1.0 if occluder_flip_y else 0.0)
	# Os quads vivem no espaco da CAMERA (screen-aligned): filhos da Camera3D.
	_occ_holder = Node3D.new()
	_occ_holder.name = "Occluders"
	cam3d.add_child(_occ_holder)
	_build_occluders_for_cam(cam_index)


## Converte um retangulo de tela (px em espaco 320x240) para um quad no espaco LOCAL da
## camera, a distancia `dist` (un Godot) do plano da camera. Usa a projecao da Camera3D
## (fov vertical, keep_aspect=HEIGHT, aspecto de TARGET) — casa com o enquadramento do bg.
func _screen_rect_to_quad(dx: float, dy: float, w: float, h: float, dist: float) -> Array:
	var t := tan(deg_to_rad(camera_fov) * 0.5)
	var aspect := TARGET.x / TARGET.y
	var half_h := dist * t
	var half_w := half_h * aspect
	# centro do retangulo em px -> NDC [-1,1] (y para cima)
	var cx_px := dx + w * 0.5
	var cy_px := dy + h * 0.5
	var nx := (cx_px / _occ_screen.x) * 2.0 - 1.0
	var ny := 1.0 - (cy_px / _occ_screen.y) * 2.0
	var pos := Vector3(nx * half_w, ny * half_h, -dist)
	var size := Vector2((w / _occ_screen.x) * 2.0 * half_w, (h / _occ_screen.y) * 2.0 * half_h)
	return [pos, size]


## Cria um QUAD de holdout por SPRITE de mascara da camera `ci` (regioes REAIS de 1o plano).
func _build_occluders_for_cam(ci: int) -> void:
	if _occ_holder == null:
		return
	for c in _occ_holder.get_children():
		c.queue_free()
	if ci < 0 or ci >= cam_masks.size():
		return
	var groups: Array = cam_masks[ci]
	for g in groups:
		var depth := int(g.get("depth", 30720))
		var dist: float = maxf(occ_depth_min, float(depth) * occ_depth_scale)
		for b in g.get("blocks", []):
			if not (b is Dictionary):
				continue
			var w := float(b.get("w", 8))
			var h := float(b.get("h", 8))
			if w < 1.0 or h < 1.0:
				continue
			var r := _screen_rect_to_quad(float(b.get("dx", 0)), float(b.get("dy", 0)), w, h, dist)
			var pos: Vector3 = r[0]
			var size: Vector2 = r[1]
			var mi := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = size
			mi.mesh = quad
			mi.material_override = _holdout_mat
			mi.position = pos               # local a Camera3D: face +Z aponta p/ camera
			mi.extra_cull_margin = 16.0
			_occ_holder.add_child(mi)


func _update_occlusion() -> void:
	if _occ_holder == null:
		return
	_occ_holder.visible = occlusion_enabled
	if _holdout_mat:
		_holdout_mat.set_shader_parameter("flip_y", 1.0 if occluder_flip_y else 0.0)
		_holdout_mat.set_shader_parameter("debug_tint", 1.0 if occluder_debug else 0.0)


## Aponta os quads de oclusao para o background da camera atual.
func _occ_set_background(tex: Texture2D) -> void:
	if _holdout_mat and tex:
		_holdout_mat.set_shader_parameter("bg_tex", tex)


# --- ILUMINACAO: casar a Jill 3D com a foto pre-renderizada ------------------
## Problema: a Jill (iluminada pela DirectionalLight3D + ambiente do SubViewport) parecia
## "colada" por cima, com luz que nao batia com a foto. Solucao: por CAMERA, derivamos a
## luz do PROPRIO background — amostramos a cor/brilho medios da foto e ajustamos o
## AMBIENTE (cor+energia) e o SOL (energia+leve tinta) para que a Jill receba a mesma
## dominante de cor e o mesmo nivel de exposicao do cenario. A DIRECAO do sol e' calibravel
## por sala (exports) porque nao da p/ recuperar a direcao 3D de forma robusta da foto 2D.
## Tudo exposto em exports (calibragem manual) + modo automatico. Ver docs/godot_gameplay.md.

@export var light_auto: bool = true              ## deriva cor/energia da foto por camera
@export var light_ambient_energy: float = 1.0    ## multiplica a energia do ambiente derivada
@export var light_sun_energy: float = 0.9        ## energia base do sol (direcional)
@export var light_sun_tint: float = 0.5          ## 0=sol branco, 1=sol na cor media da foto
## Direcao do sol (graus): yaw em torno de Y, pitch p/ baixo. Calibravel por sala.
@export var light_sun_yaw_deg: float = 40.0
@export var light_sun_pitch_deg: float = 45.0
@export var light_exposure: float = 1.0          ## multiplicador global de exposicao da Jill
var _env: Environment


func _setup_lighting() -> void:
	if world_env:
		_env = world_env.environment
	_apply_sun_direction()


## Orienta o sol pelos angulos calibraveis (yaw/pitch), no espaco do SubViewport.
func _apply_sun_direction() -> void:
	if sun == null:
		return
	var b := Basis.IDENTITY
	b = b.rotated(Vector3.UP, deg_to_rad(light_sun_yaw_deg))
	b = b.rotated(b.x, deg_to_rad(light_sun_pitch_deg))
	sun.global_transform = Transform3D(b, sun.global_transform.origin)


## Amostra a cor/brilho medios do background da camera e ajusta ambiente+sol para casar.
func _apply_lighting_for_bg(tex: Texture2D) -> void:
	_apply_sun_direction()
	if not light_auto or tex == null or _env == null:
		if sun:
			sun.light_energy = light_sun_energy
		return
	var img := tex.get_image()
	if img == null:
		return
	# media barata: reduz a foto a 16x12 e faz a media (ignora canal alfa).
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.resize(16, 12, Image.INTERPOLATE_BILINEAR)
	var acc := Vector3.ZERO
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			acc += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return
	acc /= float(n)
	var avg := Color(acc.x, acc.y, acc.z)
	var lum: float = clampf(acc.x * 0.299 + acc.y * 0.587 + acc.z * 0.114, 0.02, 1.0)
	# AMBIENTE: cor = dominante da foto (normalizada p/ nao escurecer demais); energia ~ brilho.
	var norm: float = maxf(maxf(acc.x, acc.y), maxf(acc.z, 0.001))
	_env.ambient_light_color = Color(acc.x / norm, acc.y / norm, acc.z / norm)
	_env.ambient_light_energy = clampf(1.0 + lum * 1.4, 0.6, 2.2) * light_ambient_energy * light_exposure
	# SOL: energia proporcional ao brilho; cor levemente puxada p/ a dominante da foto.
	if sun:
		sun.light_energy = light_sun_energy * clampf(0.5 + lum, 0.5, 1.6) * light_exposure
		sun.light_color = Color(1, 1, 1).lerp(avg, light_sun_tint)


# --- Geometria --------------------------------------------------------------
## Ponto-em-quadrilatero (ray casting) no plano X,Z. quad = [[x,z] x4].
func _point_in_quad(px: float, pz: float, quad) -> bool:
	if not (quad is Array) or quad.size() < 3:
		return false
	var inside := false
	var n: int = quad.size()
	var j: int = n - 1
	for i in n:
		var xi: float = float(quad[i][0])
		var zi: float = float(quad[i][1])
		var xj: float = float(quad[j][0])
		var zj: float = float(quad[j][1])
		if ((zi > pz) != (zj > pz)):
			var denom: float = (zj - zi) if (zj - zi) != 0.0 else 0.000001
			var t: float = (xj - xi) * (pz - zi) / denom + xi
			if px < t:
				inside = not inside
		j = i
	return inside


func _show_camera(i: int) -> void:
	var n := backgrounds.size()
	if n == 0:
		return
	cam_index = (i + n) % n
	var tex: Texture2D = backgrounds[cam_index]
	bg.texture = tex
	bg.centered = false
	if tex != null:
		var ts := tex.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			bg.scale = Vector2(TARGET.x / ts.x, TARGET.y / ts.y)
	if cam_index < cameras.size():
		var c: Dictionary = cameras[cam_index]
		var from_v := _arr_to_vec(c.get("from", [0, 0, 0]))
		var to_v := _arr_to_vec(c.get("to", [0, 0, 0]))
		cam3d.global_position = ps1_to_godot(from_v)
		cam3d.fov = camera_fov
		var target := ps1_to_godot(to_v)
		if cam3d.global_position.distance_to(target) > 0.001:
			cam3d.look_at(target, Vector3.UP)
	_occ_set_background(tex)          # os quads de oclusao amostram o cenario da camera atual
	_build_occluders_for_cam(cam_index)  # regioes de 1o plano REAIS desta camera (mask_data_ptr)
	_apply_lighting_for_bg(tex)       # casa a luz da Jill com a foto desta camera
	_update_occlusion()
	_update_info()


func _arr_to_vec(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


func _update_info() -> void:
	info.text = "%s (STAGE%d)  cam %d/%d  auto=%s  col=%s\n[W/S] andar   [A/D] girar   [Shift] correr   [ [ / ] ] camera manual" % [
		room, stage, cam_index + 1, max(backgrounds.size(), 1),
		"on" if auto_camera else "off", "on" if collision_enabled else "off",
	]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_BRACKETRIGHT:
				auto_camera = false
				_show_camera(cam_index + 1)
			KEY_BRACKETLEFT:
				auto_camera = false
				_show_camera(cam_index - 1)


# ============================================================================
# SELECAO DE CAMERA (para as 1000+ transicoes do jogo) — visao geral
# ============================================================================
# PROBLEMA que isto resolve: no estilo classico do RE, ao trocar de camera a Jill
# "pulava pra beira da tela" por um trecho (bug confirmado na R100). Causa: o codigo
# antigo tratava as zonas RVD (from->to) como GATILHO DE BORDA — disparava a troca no
# instante em que a Jill ENTRAVA na faixa. Mas, no RE3, essas faixas nao-degeneradas
# sao FRONTEIRAS DE HISTERESE, coladas na BORDA de cobertura da camera de destino;
# entrar nelas = aparecer na beira da camera nova.
#
# SEMANTICA REAL do RVD (engenharia reversa sobre as 169 salas, 4585 entradas):
#   - Cada entrada: {flags:u16, from:u8, to:u8, quad:4 pontos XZ}.
#   - `degenerate` = o quad tem coords +-32768 (estende ao "infinito"/frustum). NAO e'
#     a cobertura propria da camera: 427/456 entradas degeneradas tem from != to.
#   - As entradas from!=to (deg ou nao) sao FAIXAS/REGIOES DIRECIONAIS de troca; vem
#     em pares opostos (0->1 e 1->0) deslocados -> criam uma "zona morta" de histerese
#     entre as duas cameras. NAO cobrem a area toda da camera, so a fronteira.
#   - `flags`: 89% valem 0x8001. O bit baixo 0x0001 = "ativa" (grupo 0x**01 domina); o
#     byte alto (0x00,0x01,0x02,...) parece id de corte/prioridade. A `degenerate` NAO
#     vem do flag (vem das coords). Para a SELECAO nao dependemos do significado fino
#     do flag — usamos o RVD apenas como GRAFO de vizinhanca (quais cameras se tocam).
#
# ALGORITMO GERAL (init == runtime; ver _update_camera_auto / _camera_for_point):
#   Metrica de enquadramento: projeta-se o TORSO da Jill (pes + frame_probe_height) na
#   camera i; custo = |ndc_x| (0 = centralizada, 1 = borda). INF se atras ou fora do
#   frustum vertical. Como cada camera OLHA para seu `to`, essa metrica mede direto o
#   quao bem a camera enquadra a Jill (validado: as 2105 cameras projetam seu `to` em
#   ndc_x ~ 0).
#     1. HISTERESE: se a camera atual ainda enquadra (custo <= cam_keep_ndc), MANTEM.
#     2. Senao, troca para a de MENOR custo entre os VIZINHOS RVD (custo<=cam_cover_ndc);
#        se nenhum vizinho serve, cai para a melhor camera GLOBAL.
#     3. init: melhor camera global para o ponto de partida (sem preferencia).
#   Propriedades: BIDIRECIONAL (a troca so ocorre quando a Jill sai do enquadramento da
#   camera atual, e a camera nova ja a enquadra bem -> nunca "na beira"); sem flicker
#   (a zona morta entre cam_keep_ndc e a borda + switch_cooldown_frames); GERAL para
#   qualquer N de cameras e para as duas direcoes de qualquer travessia.
