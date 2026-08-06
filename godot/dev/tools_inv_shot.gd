extends SceneTree
## Harness de screenshot do INVENTARIO / HUD novos (godot/scenes/ui/*).
## Como o autoload ainda aponta pro placeholder, este harness troca em RUNTIME:
## remove /root/Inventory e /root/HUD e instancia as cenas ui/ com os mesmos nomes.
## Rodar com: --rendering-driver opengl3  (NAO --headless).
## Env:
##   SHOT_OUT  saida (default res://_inv_shot.png)
##   COND      0=FINE 1=CAUTION 2=DANGER 3=POISON
##   SEL       indice do slot selecionado
##   SUBMENU   1 -> abre o submenu de acoes
##   LANG      pt|en
##   CLOSED    1 -> nao abre inventario (captura so o HUD in-game)

var _frames := 0
var _scene: Node
var _inv: Node
var _hud: Node


func _initialize() -> void:
	for n in ["Inventory", "HUD"]:
		var old := get_root().get_node_or_null(n)
		if old:
			old.name = n + "_old"
			old.queue_free()
	var inv_ps := load("res://scenes/ui/inventory.tscn")
	if inv_ps:
		_inv = inv_ps.instantiate()
		_inv.name = "Inventory"
		get_root().add_child(_inv)
	var hud_ps := load("res://scenes/ui/hud.tscn")
	if hud_ps:
		_hud = hud_ps.instantiate()
		_hud.name = "HUD"
		get_root().add_child(_hud)
	var packed := load("res://scenes/game_room.tscn")
	if packed:
		_scene = packed.instantiate()
		get_root().add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 6:
		var lm := get_root().get_node_or_null("LangManager")
		if lm and OS.has_environment("LANG"):
			lm.set_lang("ptbr" if OS.get_environment("LANG") == "pt" else "en")
		var cond := int(OS.get_environment("COND")) if OS.has_environment("COND") else 0
		if _hud and _hud.has_method("set_state"):
			_hud.set_state(cond)
		if _inv:
			if OS.has_environment("SEL"):
				_inv._sel = int(OS.get_environment("SEL"))
			_inv.set_condition(cond)
			if not OS.has_environment("CLOSED"):
				_inv.set_open(true)
			if OS.has_environment("SUBMENU"):
				_inv._open_submenu()
	if _frames == 40:
		var out := "res://_inv_shot.png"
		if OS.has_environment("SHOT_OUT"):
			out = OS.get_environment("SHOT_OUT")
		var img := get_root().get_texture().get_image()
		var err := img.save_png(out)
		print("INV SHOT saved=", out, " err=", err)
		quit()
		return true
	return false
