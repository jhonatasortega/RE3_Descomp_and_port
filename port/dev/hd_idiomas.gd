extends SceneTree
## Lista TODOS os blocos HD que casam com a metade direita do `STMAIN0U` (posição 128,0),
## ordenados por erro. O pack Seamless traz o mesmo bloco em VÁRIOS IDIOMAS (o `hd_ui_map.json`
## já registrava isso no RADAR: `RADAR` e `RADAR@pt` têm a mesma geometria e hash diferente),
## então os primeiros colocados são as variantes de idioma — e é entre elas que está a de
## português. Converte os melhores para PNG em `port/_hd_cand/` para inspeção visual.
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"


func _initialize() -> void:
	var sd := AssetIO.image("MENU/status/stmain0u_p0.png")
	sd.convert(Image.FORMAT_RGBA8)
	var alvo := sd.get_region(Rect2i(128, 0, 128, 256))
	var d := DirAccess.open("%s/misc" % HIRES)
	var lista := []
	for f: String in d.get_files():
		if not f.ends_with(".webp"):
			continue
		var img := Image.new()
		if img.load("%s/misc/%s" % [HIRES, f]) != OK:
			continue
		if img.get_width() != 512 or img.get_height() != 1024:
			continue
		img.resize(128, 256, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		lista.append([_erro(alvo, img), f.get_basename()])
	lista.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	print("[id] %d blocos 512x1024 · os 8 melhores contra (128,0):" % lista.size())
	var dir_out := ProjectSettings.globalize_path("res://_hd_cand")
	DirAccess.make_dir_recursive_absolute(dir_out)
	for i in mini(8, lista.size()):
		var e: float = lista[i][0]
		var nome: String = lista[i][1]
		print("[id]   %d. %s  erro=%.4f" % [i + 1, nome, e])
		var img2 := Image.new()
		if img2.load("%s/misc/%s.webp" % [HIRES, nome]) == OK:
			img2.save_png("%s/%d_%s.png" % [dir_out, i + 1, nome])
	quit(0)


func _erro(a: Image, b: Image) -> float:
	var soma := 0.0
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			if ca.a < 0.5:
				continue
			var cb := b.get_pixel(x, y)
			soma += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return 1e9 if n == 0 else soma / float(n * 3)
