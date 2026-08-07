extends SceneTree
## Prova da FONTE HD: monta uma tira com os glifos de uma frase, recortados do candidato HD pela
## grade calculada. Se a tira LER a frase (com acento), a grade e o de-para estao certos.
##
## Grade esperada: o SD tem célula 14×14 em 18 colunas com `v = (cod/18)*14 + 28`; a página de
## VRAM é 256×256, logo o HD (4×) é 1024×1024 com célula **56** e base **112**.
##
## env: FONTE_FRASE="AÇÃO ção" · FONTE_ARQ=<hash> (senão testa todos os 1024×1024 de misc/)
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
const CELULA := 56
const COLUNAS := 18
const V_BASE := 112


func _initialize() -> void:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/re3_font_pt.json"))
	var mapa: Dictionary = (raw as Dictionary)["char_para_codigo"]
	var frase := OS.get_environment("FONTE_FRASE")
	if frase == "":
		frase = "ACAOçãáéíóú0159"
	var codigos: Array[int] = []
	for i in frase.length():
		var c := frase[i]
		if mapa.has(c):
			codigos.append(int(mapa[c]))
	print("[fo] frase %s -> codigos %s" % [frase, codigos])

	var alvo := OS.get_environment("FONTE_ARQ")
	var arquivos: Array[String] = []
	if alvo != "":
		arquivos.append(alvo)
	else:
		var d := DirAccess.open("%s/misc" % HIRES)
		for f: String in d.get_files():
			if not f.ends_with(".webp"):
				continue
			var im := Image.new()
			if im.load("%s/misc/%s" % [HIRES, f]) != OK:
				continue
			if im.get_width() == 1024 and im.get_height() == 1024:
				arquivos.append(f.get_basename())
	print("[fo] %d candidato(s) 1024x1024" % arquivos.size())
	var dir_out := ProjectSettings.globalize_path("res://_fonte")
	DirAccess.make_dir_recursive_absolute(dir_out)
	for nome: String in arquivos:
		var img := Image.new()
		if img.load("%s/misc/%s.webp" % [HIRES, nome]) != OK:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var tira := Image.create(CELULA * codigos.size(), CELULA, false, Image.FORMAT_RGBA8)
		tira.fill(Color(0.1, 0.1, 0.12))
		var i := 0
		var tinta := 0
		for cod: int in codigos:
			var u := (cod % COLUNAS) * CELULA
			var v := int(cod / COLUNAS) * CELULA + V_BASE
			if u + CELULA > 1024 or v + CELULA > 1024:
				i += 1
				continue
			var cel := img.get_region(Rect2i(u, v, CELULA, CELULA))
			for y in CELULA:
				for x in CELULA:
					if cel.get_pixel(x, y).a > 0.5 and cel.get_pixel(x, y).v > 0.35:
						tinta += 1
			tira.blit_rect(cel, Rect2i(0, 0, CELULA, CELULA), Vector2i(i * CELULA, 0))
			i += 1
		tira.save_png("%s/%s_tinta%d.png" % [dir_out, nome, tinta])
		print("[fo]   %s: tinta=%d" % [nome, tinta])
	quit(0)
