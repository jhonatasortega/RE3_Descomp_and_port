extends SceneTree
## MEDE a métrica de cada glifo direto no atlas HD da fonte, em vez de interpretar os campos
## `width`/`indent` do mod. Para cada código, acha a caixa de TINTA dentro da célula de 56×56 e
## grava, em unidades SD (dividindo por 4): onde a tinta começa e quanto ela ocupa.
##
## Saída: `port/data/re3_font_hd_metrica.json` — `{cod: {x, w}}`, e é isso que o `Texto` usa para
## recortar e avançar. Avanço = largura da tinta + 1 px de espaço entre letras (o único número
## escolhido aqui; o resto é medido).
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
const ARQ := "AED42717"
const CELULA := 56
const COLUNAS := 18
const V_BASE := 112
const ESPACO := 1                    ## px SD entre glifos


func _initialize() -> void:
	var img := Image.new()
	if img.load("%s/misc/%s.webp" % [HIRES, ARQ]) != OK:
		print("[fm] nao abriu o atlas")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var metrica := {}
	var medidos := 0
	for cod in 161:                  ## 161 = onde começa o bloco kana (medido na folha)
		var u := (cod % COLUNAS) * CELULA
		var v := int(cod / COLUNAS) * CELULA + V_BASE
		if u + CELULA > img.get_width() or v + CELULA > img.get_height():
			continue
		var x0 := CELULA
		var x1 := -1
		for y in CELULA:
			for x in CELULA:
				var c := img.get_pixel(u + x, v + y)
				if c.a > 0.4 and c.v > 0.25:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		if x1 < 0:
			continue                 ## célula vazia
		# em unidades SD (o atlas é 4×), arredondando para fora
		var sx := int(floor(float(x0) / 4.0))
		var sw := int(ceil(float(x1 - x0 + 1) / 4.0))
		metrica[str(cod)] = {"x": sx, "w": sw, "adv": sw + ESPACO}
		medidos += 1
	var d := {
		"_fonte": "atlas HD misc/%s (1024x1024 = 4x a pagina 256x256)" % ARQ,
		"_metodo": "caixa de tinta medida por celula (56x56) e convertida para unidades SD; avanco = largura da tinta + 1 px. Nao usa width/indent do mod, que sao de outro desenho de fonte.",
		"celula_sd": 14, "colunas": COLUNAS, "v_base_sd": 28, "fator": 4,
		"n": medidos, "glifos": metrica,
	}
	var f := FileAccess.open("res://data/re3_font_hd_metrica.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	print("[fm] %d glifos medidos -> data/re3_font_hd_metrica.json" % medidos)
	for cod: int in [29, 61, 69, 115, 139, 12]:
		var m: Dictionary = metrica.get(str(cod), {})
		print("[fm]   cod %3d: x=%s w=%s adv=%s" % [cod, m.get("x"), m.get("w"), m.get("adv")])
	quit(0)
