extends SceneTree
## Validacao IN-GAME: carrega game_room.tscn (fundo 2D + Jill 3D no SubViewport),
## forca a Jill a tocar um clipe (ANIM) num frame do meio e salva PNG do resultado
## composto (o que o jogador ve). Confirma a caminhada normal + membros atados.
##
## Rodar: godot --path godot --rendering-driver opengl3 --script res://tools_walk_val.gd
## Env: ANIM=anim00  SEEK=0.5  OUT=res://val_ingame/anim00.png

var _scene: Node
var _anim: AnimationPlayer
var _frames := 0
var _name := "anim00"
var _seek := 0.5
var _out := "res://val_ingame/walk.png"


func _initialize() -> void:
	if OS.has_environment("ANIM"): _name = OS.get_environment("ANIM")
	if OS.has_environment("SEEK"): _seek = float(OS.get_environment("SEEK"))
	if OS.has_environment("OUT"): _out = OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
	var packed: PackedScene = load("res://scenes/game_room.tscn")
	_scene = packed.instantiate()
	get_root().add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		var jill: Node = _scene.get_node("Viewport/SubViewport/Jill")
		_anim = _find_anim(jill)
		if _anim and _anim.has_animation(_name):
			var a := _anim.get_animation(_name)
			a.loop_mode = Animation.LOOP_LINEAR
			_anim.play(_name)
			_anim.seek(a.length * _seek, true)
			_anim.pause()
	if _frames == 16:
		if _anim and _anim.has_animation(_name):
			_anim.seek(_anim.get_animation(_name).length * _seek, true)
	if _frames == 24:
		var img := get_root().get_texture().get_image()
		var err := img.save_png(_out)
		print("VAL ", _name, " seek=", _seek, " err=", err, " -> ", _out)
		quit()
		return true
	return false


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r: return r
	return null
