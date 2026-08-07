extends SceneTree
## Folha AUTO-ROTULADA da fonte HD: cada célula aparece com o próprio número de código escrito
## embaixo, usando os dígitos DO PRÓPRIO ATLAS. Serve para ler o de-para real
## `caractere -> código` desta fonte, em vez de confiar no `encoding.xml` do mod (que é da fonte
## alternativa dele: lá `0x58` é `ã`, aqui é `ä`).
##
## Grade provada com a frase "ACAO...0159": célula **56**, **18 colunas**, `v = (cod/18)*56 + 112`.
##
## env: FOLHA_ARQ=AED42717 · FOLHA_DE=80 · FOLHA_ATE=160
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
const CELULA := 56
const COLUNAS := 18
const V_BASE := 112
const COD_DIGITO_0 := 12          ## '0' = 0x0c na tabela (confirmado na tira: 0,1,5,9 saíram certos)


func _initialize() -> void:
	var nome := OS.get_environment("FOLHA_ARQ")
	if nome == "":
		nome = "AED42717"
	var de := int(OS.get_environment("FOLHA_DE")) if OS.get_environment("FOLHA_DE") != "" else 80
	var ate := int(OS.get_environment("FOLHA_ATE")) if OS.get_environment("FOLHA_ATE") != "" else 160
	var img := Image.new()
	if img.load("%s/misc/%s.webp" % [HIRES, nome]) != OK:
		print("[ff] nao abriu %s" % nome)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var n := ate - de
	var por_linha := 10
	var linhas := int(ceil(float(n) / float(por_linha)))
	var cel_h := CELULA + 24                      ## célula + faixa do rótulo
	var folha := Image.create(por_linha * CELULA, linhas * cel_h, false, Image.FORMAT_RGBA8)
	folha.fill(Color(0.08, 0.08, 0.10))
	for i in n:
		var cod := de + i
		var cx := (i % por_linha) * CELULA
		var cy := int(i / por_linha) * cel_h
		var u := (cod % COLUNAS) * CELULA
		var v := int(cod / COLUNAS) * CELULA + V_BASE
		if u + CELULA <= img.get_width() and v + CELULA <= img.get_height():
			folha.blit_rect(img.get_region(Rect2i(u, v, CELULA, CELULA)),
				Rect2i(0, 0, CELULA, CELULA), Vector2i(cx, cy))
		# rótulo: o número do código, com os dígitos do próprio atlas, reduzidos
		var s := str(cod)
		var dx := cx
		for k in s.length():
			var d := s.unicode_at(k) - 48
			var du := ((COD_DIGITO_0 + d) % COLUNAS) * CELULA
			var dv := int((COD_DIGITO_0 + d) / COLUNAS) * CELULA + V_BASE
			var g := img.get_region(Rect2i(du, dv, CELULA, CELULA))
			g.resize(18, 18, Image.INTERPOLATE_LANCZOS)
			folha.blit_rect(g, Rect2i(0, 0, 18, 18), Vector2i(dx, cy + CELULA + 2))
			dx += 17
	var dir_out := ProjectSettings.globalize_path("res://_fonte")
	DirAccess.make_dir_recursive_absolute(dir_out)
	folha.save_png("%s/folha_%s_%d_%d.png" % [dir_out, nome, de, ate])
	print("[ff] folha de %s: códigos %d..%d -> _fonte/folha_%s_%d_%d.png" % [
		nome, de, ate, nome, de, ate])
	quit(0)
