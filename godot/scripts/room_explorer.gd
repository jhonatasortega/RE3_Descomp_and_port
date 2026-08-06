extends Node2D
## Explorador de sala data-driven: carrega uma sala REAL do RE3.
## Prefere o background HD (Seamless HD Project, 1280x960) e cai pro PS1 (320x240)
## quando o HD nao existe. Mostra os placements (ARD/SCD) na planta baixa.
##
## Controles:
##   Seta ESQUERDA / DIREITA  -> troca a camera fixa (e o background)
##   TAB                      -> alterna o overlay de planta baixa (top-down)

const TARGET := Vector2(1280, 960)   # resolucao alvo (HD nativa)

@export var stage: int = 1
@export var room: String = "R100"

var data: Dictionary = {}
var backgrounds: Array = []
var sources: Array = []
var cam_index: int = 0
var show_map: bool = false

@onready var bg: Sprite2D = $Background
@onready var info: Label = $UI/Info


func _ready() -> void:
	_load_room()
	_show_camera(0)


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
	var n := int(rdt.get("n_cameras", 0))
	backgrounds.clear()
	sources.clear()
	for i in n:
		var wp := "res://assets/STAGE%d/%s_%d.webp" % [stage, room, i]
		var pp := "res://assets/STAGE%d/%s_%d.png" % [stage, room, i]
		if ResourceLoader.exists(wp):
			backgrounds.append(load(wp))
			sources.append("HD")
		elif ResourceLoader.exists(pp):
			backgrounds.append(load(pp))
			sources.append("PS1")
		else:
			backgrounds.append(null)
			sources.append("--")


func _show_camera(i: int) -> void:
	var n := backgrounds.size()
	if n == 0:
		_update_info()
		return
	cam_index = (i + n) % n
	var tex: Texture2D = backgrounds[cam_index]
	bg.texture = tex
	bg.centered = false
	if tex != null:
		var ts := tex.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			bg.scale = Vector2(TARGET.x / ts.x, TARGET.y / ts.y)
	_update_info()
	queue_redraw()


func _update_info() -> void:
	var rdt: Dictionary = data.get("rdt", {})
	var sc: Dictionary = rdt.get("script", {})
	var doors: Array = sc.get("doors", [])
	var events: Array = sc.get("events", [])
	var ents: Array = sc.get("entities", [])
	var src: String = sources[cam_index] if cam_index < sources.size() else "?"
	info.text = "%s (STAGE%d)   fonte: %s\nCamera %d/%d\nPortas: %d | Triggers: %d | Entidades: %d\n[<- ->] camera    [TAB] planta baixa" % [
		room, stage, src, cam_index + 1, max(backgrounds.size(), 1),
		doors.size(), events.size(), ents.size(),
	]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_RIGHT:
				_show_camera(cam_index + 1)
			KEY_LEFT:
				_show_camera(cam_index - 1)
			KEY_TAB:
				show_map = not show_map
				bg.visible = not show_map
				queue_redraw()


func _draw() -> void:
	if not show_map:
		return
	var rdt: Dictionary = data.get("rdt", {})
	var sc: Dictionary = rdt.get("script", {})
	var cams: Array = rdt.get("cameras", [])
	var doors: Array = sc.get("doors", [])
	var events: Array = sc.get("events", [])
	var ents: Array = sc.get("entities", [])

	var pts: Array[Vector2] = []
	for c in cams:
		pts.append(Vector2(c["from"][0], c["from"][2]))
		pts.append(Vector2(c["to"][0], c["to"][2]))
	for d in doors:
		pts.append(Vector2(d["pos"][0], d["pos"][1]))
	for e in events:
		pts.append(Vector2(e["pos"][0], e["pos"][1]))
	for en in ents:
		pts.append(Vector2(en["pos"][0], en["pos"][1]))
	if pts.is_empty():
		return

	var min_x := pts[0].x
	var min_y := pts[0].y
	var max_x := pts[0].x
	var max_y := pts[0].y
	for p in pts:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	var span := maxf(maxf(max_x - min_x, max_y - min_y), 1.0)
	var s := 800.0 / span
	var origin := Vector2(min_x, min_y)
	var off := Vector2(120, 90)

	for c in cams:
		var a := (Vector2(c["from"][0], c["from"][2]) - origin) * s + off
		var b := (Vector2(c["to"][0], c["to"][2]) - origin) * s + off
		draw_line(a, b, Color.CYAN, 2.0)
		draw_circle(a, 7.0, Color.CYAN)
	for d in doors:
		draw_circle((Vector2(d["pos"][0], d["pos"][1]) - origin) * s + off, 7.0, Color.GREEN)
	for e in events:
		draw_circle((Vector2(e["pos"][0], e["pos"][1]) - origin) * s + off, 5.0, Color.YELLOW)
	for en in ents:
		draw_circle((Vector2(en["pos"][0], en["pos"][1]) - origin) * s + off, 7.0, Color.RED)
