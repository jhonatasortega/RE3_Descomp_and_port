extends SceneTree
## Sonda: o `VideoStreamPlayer` do Godot 4 aceita um `.ogv` de FORA do `.pck`?
##
## Isso não é detalhe: `port/assets/` tem `.gdignore` (política P7-06 — os assets são da
## Capcom e não podem ser distribuídos), então nada de `load("res://assets/...")`. Se o
## `VideoStreamTheora` não abrir caminho absoluto, o tocador de FMV teria de mudar de
## estratégia. Esta sonda responde antes de escrever o tocador.
##
##     godot --path port --headless --script res://dev/diag_video.gd
##     godot --path port --rendering-driver opengl3 --script res://dev/diag_video.gd


func _initialize() -> void:
	var p := AssetIO.path("ZMOVIE/opn.ogv")
	print("caminho     : %s" % p)
	print("existe      : %s" % FileAccess.file_exists(p))
	print("classe      : %s" % ("VideoStreamTheora" if ClassDB.class_exists("VideoStreamTheora")
		else "AUSENTE"))
	if not FileAccess.file_exists(p):
		print("sem o .ogv — rode `NOSTALGIA_OUT=port python tools/video_ogv.py --abertura`")
		quit(0)
		return
	var vs := VideoStreamTheora.new()
	vs.file = p
	var vp := VideoStreamPlayer.new()
	vp.stream = vs
	vp.expand = true
	vp.size = Vector2(1280, 960)
	get_root().add_child(vp)
	await process_frame              ## `play()` exige o nó JÁ na árvore
	vp.play()
	print("play()      : playing=%s pos=%.3f" % [vp.is_playing(), vp.stream_position])
	var vt: Texture2D = vp.get_video_texture()
	print("textura     : %s" % ("%dx%d" % [vt.get_width(), vt.get_height()] if vt != null
		else "null"))
	# avança alguns quadros de motor para ver se a posição anda
	for _i in 30:
		await process_frame
	print("30 quadros  : playing=%s pos=%.3f" % [vp.is_playing(), vp.stream_position])
	var vt2: Texture2D = vp.get_video_texture()
	print("textura 2   : %s" % ("%dx%d" % [vt2.get_width(), vt2.get_height()] if vt2 != null
		else "null"))
	quit(0)
