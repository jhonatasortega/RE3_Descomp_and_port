class_name Occlusion
extends Node2D
## Oclusão por PRIORITY SPRITES (P1-07) — a REGRA REAL do motor, provada no EXE (2026-08-01).
##
## Não existe "teste de profundidade" no RE3: é painter's algorithm na ORDERING TABLE do PS1.
## A OT tem 1024 entradas por BANCO e N+1 bancos (N vem da seção 14 do RDT, 0..3):
##
##   • cada SPRITE de máscara entra na OT com chave = o `depth` CRU do RDT
##     (`0x80048844`: bank = depth>>10, entry = depth & 1023 — NÃO é depth*16 nem soma 30720;
##     o 30720/0x7800 é o CLUT do SPRT);
##   • o PERSONAGEM entra com bank = ZONA DE PRIORIDADE que contém o (x,z) dele
##     (`0x80037d50`, seção `offset_table[14]`; sem seção/zona → banco 0) e
##     entry = média dos SZ dos vértices >> 5, limitada a 1023 (`0x8002b86c`);
##     SZ = Z de câmera em unidades do mundo (matriz 1.12 unitária do LookAt `0x80078954`);
##   • ordem de desenho (`0x80029618`): bancos N..1, banco 0 POR ÚLTIMO; dentro de cada banco
##     a OT desce de 1023 a 0 → **CHAVE MENOR = desenhado depois = NA FRENTE**.
##
## Logo: sprite na frente do personagem ⟺ `depth < bank_do_personagem*1024 + min(SZ>>5,1023)`.
## O port guarda `z = depth*16` no JSON (unidade de mundo); aqui converte-se de volta
## (`depth = z/16`). APROXIMAÇÃO DECLARADA: o motor decide POR POLÍGONO do modelo (cada
## triângulo tem sua média de SZ); aqui a decisão é por personagem inteiro, com o SZ do
## torso — os casos "meio corpo atrás do balcão" ficam para a versão por-polígono.
##
## ── De onde vêm os pixels ──
## O recorte de primeiro plano é, por definição, o próprio cenário naquela posição de tela —
## os pixels saem do BACKGROUND HD no MESMO retângulo (`dx,dy,w,h` ×4). Limite declarado:
## blocos com alpha PARCIAL (grade, vão de escada) ficam opacos; a forma per-pixel vive no
## atlas do PS1, que não sabemos indexar (a escala do atlas HD é convenção do mod).

const TELA_ESCALA := 4.0            ## 320×240 (PS1) -> 1280×960
const OT_BANK := 1024               ## entradas por banco (`ClearOTagR(ot,1024)`, 0x80028ff0)

enum Modo {
	DESLIGADA,        ## nada é desenhado
	OVERLAY,          ## desenha TODOS os recortes (valida posição de tela contra o cenário)
	PROFUNDIDADE,     ## só os recortes à frente do personagem (comportamento do jogo)
}

@export var modo: Modo = Modo.PROFUNDIDADE
## Chave de OT do personagem (bank*1024 + entry), atualizada por tick.
var char_key := 0x7FFFFFFF
var _zonas: Array = []              ## zonas de prioridade da câmera atual (seção 14)

var _sprites: Array[Dictionary] = []      ## {rect: Rect2, key: int}
var _fonte: Texture2D                     ## background da câmera (de onde saem os pixels)
var _room_id := ""
var _cam := -1


func carregar(room: RoomData, cam_index: int) -> int:
	_sprites.clear()
	_room_id = room.room_id
	_cam = cam_index
	var c := room.camera(cam_index)
	if c == null:
		return 0
	_fonte = CameraRID.background(room.room_id, cam_index)
	_zonas = room.priority_zones_da_camera(cam_index)

	for g: Dictionary in c.mask_groups:
		for b: Dictionary in (g.get("blocks", []) as Array):
			var w := float(b.get("w", 0))
			var h := float(b.get("h", 0))
			if w <= 0.0 or h <= 0.0:
				continue
			_sprites.append({
				"rect": Rect2(float(b.get("dx", 0)) * TELA_ESCALA,
					float(b.get("dy", 0)) * TELA_ESCALA, w * TELA_ESCALA, h * TELA_ESCALA),
				# chave de OT = o depth CRU do RDT (o JSON guarda z = depth*16)
				"key": int(b.get("z", 0)) >> 4,
			})
	queue_redraw()
	return _sprites.size()


func atualizar_profundidade(cam: RoomData.Camera, pos_ps1: Vector3i) -> void:
	## Chave de OT do personagem: bank (zona de prioridade no chão) ×1024 + SZ>>5.
	var eixo := Vector3(float(cam.to_ps1.x - cam.from_ps1.x),
		float(cam.to_ps1.y - cam.from_ps1.y), float(cam.to_ps1.z - cam.from_ps1.z))
	if eixo.length_squared() == 0.0:
		return
	eixo = eixo.normalized()
	var v := Vector3(float(pos_ps1.x - cam.from_ps1.x), float(pos_ps1.y - cam.from_ps1.y),
		float(pos_ps1.z - cam.from_ps1.z))
	var sz := clampi(int(v.dot(eixo)), 0, 32767)           # SZ clampado (0x8002d630)
	var nova := _bank_do_ponto(pos_ps1.x, pos_ps1.z) * OT_BANK + mini(sz >> 5, OT_BANK - 1)
	if nova != char_key:
		char_key = nova
		if modo == Modo.PROFUNDIDADE:
			queue_redraw()


func _bank_do_ponto(x: int, z: int) -> int:
	## `0x80037d50`: primeira zona (na ordem do arquivo) que contém o ponto decide o banco;
	## flags bit1 = ignorar; sem seção ou sem zona → banco 0.
	for zona: Dictionary in _zonas:
		if (int(zona.get("flags", 0)) & 0x02) != 0:
			continue
		if zona.has("rect"):
			var r: Array = zona["rect"]
			var dx := x - int(r[0])
			var dz := z - int(r[1])
			if dx >= 0 and dx <= int(r[2]) and dz >= 0 and dz <= int(r[3]):
				return int(zona.get("bank", 0))
		elif zona.has("quad"):
			var q: Array[Vector2i] = []
			for p: Array in zona["quad"]:
				q.append(Vector2i(int(p[0]), int(p[1])))
			if CameraRVD.point_in_quad(q, x, z):
				return int(zona.get("bank", 0))
	return 0


func _draw() -> void:
	if modo == Modo.DESLIGADA or _sprites.is_empty() or _fonte == null:
		return
	# O background pode ser HD (1280×960) ou PS1 (320×240): a região-fonte é o mesmo
	# retângulo em proporção, então basta escalar pelo tamanho real da textura.
	var k := Vector2(float(_fonte.get_width()) / 1280.0, float(_fonte.get_height()) / 960.0)
	for s in _sprites:
		if modo == Modo.PROFUNDIDADE and int(s["key"]) >= char_key:
			continue                      ## chave maior/igual: atrás do personagem
		var r: Rect2 = s["rect"]
		var src := Rect2(r.position * k, r.size * k)
		draw_texture_rect_region(_fonte, r, src)


func desenhados() -> int:
	## Quantos recortes passam no teste agora (diagnóstico/calibração).
	if modo == Modo.OVERLAY:
		return _sprites.size()
	if modo == Modo.DESLIGADA:
		return 0
	var n := 0
	for s in _sprites:
		if int(s["key"]) < char_key:
			n += 1
	return n


func info() -> String:
	return "%s cam %d: %d recortes (%d na frente), fonte=%s, modo=%s, char_key=%d (bank %d)" % [
		_room_id, _cam, _sprites.size(), desenhados(),
		"%dx%d" % [_fonte.get_width(), _fonte.get_height()] if _fonte else "-",
		["DESLIGADA", "OVERLAY", "PROFUNDIDADE"][modo], char_key, char_key / OT_BANK]


func z_range() -> Vector2:
	if _sprites.is_empty():
		return Vector2.ZERO
	var lo := INF
	var hi := -INF
	for s in _sprites:
		lo = minf(lo, float(s["key"]))
		hi = maxf(hi, float(s["key"]))
	return Vector2(lo, hi)


func sprite_count() -> int:
	return _sprites.size()
