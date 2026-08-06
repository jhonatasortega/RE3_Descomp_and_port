extends CanvasLayer
## Inventario em grade estilo Resident Evil.
## Abre/fecha com I ou TAB. Populado a partir de:
##   - godot/data/sce_items.json  -> "itens_observados.por_sala" (item_id + amount reais
##     extraidos do SCD, opcode 0x68) e "item_id_ref" (item_id -> nome).
## Como as salas (data/STAGE*/R*.json) ainda nao tem o campo rdt.script.items
## anotado, a fonte confiavel de itens e o proprio sce_items.json.
##
## Icones: placeholders (retangulo colorido por categoria + nome + quantidade).
##
## Registrado como AUTOLOAD (scenes/inventory.tscn) -> abre sobre qualquer cena
## sem editar game_room.tscn / room_game.gd.

const ITEMS_JSON := "res://data/sce_items.json"
const COLUMNS := 4

# Cor do placeholder por categoria.
const CAT_COLOR := {
	"arma":   Color(0.62, 0.20, 0.20),
	"ammo":   Color(0.72, 0.55, 0.16),
	"none":   Color(0.25, 0.25, 0.28),
	"item":   Color(0.20, 0.42, 0.55),
}

var _grid: GridContainer
var _title: Label
var _hint: Label
var _items: Array = []          # [{id, name, cat, amount}]
var _open: bool = false


func _ready() -> void:
	layer = 25
	visible = false
	_grid = get_node_or_null("Root/Panel/Margin/VBox/Grid")
	_title = get_node_or_null("Root/Panel/Margin/VBox/Title")
	_hint = get_node_or_null("Root/Panel/Margin/VBox/Hint")
	if _grid:
		_grid.columns = COLUMNS
	_load_items()
	_build_grid()
	if _title:
		_title.text = "INVENTORY  (%d)" % _items.size()
	if _hint:
		_hint.text = "[I] / [TAB] fechar     [L] trocar idioma da voz"


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I or event.keycode == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _open:
			set_open(false)


func toggle() -> void:
	set_open(not _open)


func set_open(v: bool) -> void:
	_open = v
	visible = v


# --------------------------------------------------------------- carregamento
func _load_items() -> void:
	_items.clear()
	if not FileAccess.file_exists(ITEMS_JSON):
		push_warning("Inventory: %s nao encontrado" % ITEMS_JSON)
		return
	var f := FileAccess.open(ITEMS_JSON, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Inventory: sce_items.json invalido")
		return

	var ref: Dictionary = data.get("item_id_ref", {})
	var observed: Dictionary = data.get("itens_observados", {}).get("por_sala", {})

	# Agrega (item_id -> amount total) somando todas as salas observadas.
	var agg := {}      # id_hex(String) -> total amount
	for room in observed.keys():
		for entry in observed[room]:
			# entry = ["0x21", 1]
			if typeof(entry) != TYPE_ARRAY or entry.size() < 2:
				continue
			var id_hex := String(entry[0]).to_lower()
			var amount := int(entry[1])
			agg[id_hex] = int(agg.get(id_hex, 0)) + amount

	# Monta a lista final ordenada por item_id.
	var ids := agg.keys()
	ids.sort()
	for id_hex in ids:
		_items.append({
			"id": id_hex,
			"name": _name_for(id_hex, ref),
			"cat": _cat_for(id_hex, ref),
			"amount": int(agg[id_hex]),
		})


func _name_for(id_hex: String, ref: Dictionary) -> String:
	# ref usa chaves tipo "0x21" (maiuscula no digito? na verdade "0x04").
	var name := _lookup_ref(id_hex, ref, "nome")
	if name != "":
		return name
	return "Item %s" % id_hex.to_upper()


func _cat_for(id_hex: String, ref: Dictionary) -> String:
	var cat := _lookup_ref(id_hex, ref, "cat")
	if cat != "":
		return cat
	# Heuristica do proprio sce_items.json: amount>1 => municao (tratado no build).
	return "item"


func _lookup_ref(id_hex: String, ref: Dictionary, field: String) -> String:
	# Tenta variacoes de caixa: "0x21", "0x21".upper -> "0X21".
	for key in [id_hex, id_hex.to_upper(), "0x" + id_hex.substr(2).to_upper()]:
		if ref.has(key) and typeof(ref[key]) == TYPE_DICTIONARY:
			return String(ref[key].get(field, ""))
	return ""


# ----------------------------------------------------------------- construcao
func _build_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	if _items.is_empty():
		var empty := Label.new()
		empty.text = "(sem itens)"
		_grid.add_child(empty)
		return
	for it in _items:
		_grid.add_child(_make_cell(it))


func _make_cell(it: Dictionary) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(150, 74)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.9)
	sb.border_color = Color(0.35, 0.35, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	cell.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	cell.add_child(hb)

	# Icone placeholder: retangulo colorido por categoria.
	var cat: String = it["cat"]
	if cat == "arma" and it["amount"] > 1:
		cat = "ammo"          # arma "empilhavel" e municao dessa arma
	var icon := ColorRect.new()
	icon.color = CAT_COLOR.get(cat, CAT_COLOR["item"])
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = String(it["name"])
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(name_lbl)

	var qty_lbl := Label.new()
	qty_lbl.text = "%s   x%d" % [String(it["id"]).to_upper(), int(it["amount"])]
	qty_lbl.add_theme_font_size_override("font_size", 11)
	qty_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	vb.add_child(qty_lbl)

	return cell
