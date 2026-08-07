extends SceneTree
## Casa as **280 imagens `memo/` (1024×768)** do pack HD com as **183 páginas + 31 capas** do
## `FILEGU.PIX` já extraídas em `assets/FILE/`.
##
## O problema: as páginas SD são **128×256** (retrato) e as HD são 1024×768, que é 4× de
## **256×192** (paisagem) — o HD REDESENHOU a página em outro formato, então não dá para comparar
## na proporção. Solução: normalizar as duas para a MESMA caixa (192×192) e comparar o padrão de
## TINTA (o texto é o mesmo), com atribuição global como nas placas.
##
## Saída: `port/data/hd_memo_map.json` + os arquivos copiados como
## `assets/FILE/hd/pag_NNN.webp` / `capa_NNN.webp`.
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"
## 32×32 é o suficiente: o que se compara é o PADRÃO de tinta (onde há texto e onde há papel), e
## a 192×192 as 60 mil comparações estouravam o tempo. Depois do casamento a imagem usada é a
## original, em resolução cheia.
const CAIXA := 32


func _initialize() -> void:
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/re3_file_screen.json"))
	var paginas: Array = (raw as Dictionary).get("paginas", [])
	# --- carrega os HD normalizados ---
	var d := DirAccess.open("%s/memo" % HIRES)
	if d == null:
		print("[me] pasta memo ausente")
		quit(1)
		return
	var hd := {}
	for f: String in d.get_files():
		if not f.ends_with(".webp"):
			continue
		var img := Image.new()
		if img.load("%s/memo/%s" % [HIRES, f]) != OK:
			continue
		img.resize(CAIXA, CAIXA, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		hd[f.get_basename()] = img
	print("[me] %d imagens memo normalizadas em %dx%d" % [hd.size(), CAIXA, CAIXA])
	# --- carrega os SD normalizados ---
	var sd := {}
	for p: Dictionary in paginas:
		var n := int(p.get("page", 0))
		for pre: String in ["pag", "capa"]:
			var rel := "FILE/%s_%03d.png" % [pre, n]
			if not AssetIO.exists(rel):
				continue
			var im := AssetIO.image(rel)
			if im == null:
				continue
			im.convert(Image.FORMAT_RGBA8)
			im.resize(CAIXA, CAIXA, Image.INTERPOLATE_LANCZOS)
			sd["%s_%03d" % [pre, n]] = im
	print("[me] %d páginas SD normalizadas" % sd.size())
	# --- todos os pares, ordenados, atribuição global ---
	var pares := []
	for k: String in sd:
		for h: String in hd:
			pares.append([_erro(sd[k], hd[h]), k, h])
	pares.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var mapa := {}
	var usados := {}
	var n_ok := 0
	for par: Array in pares:
		var e: float = par[0]
		var k: String = par[1]
		var h: String = par[2]
		if e > 0.22:                       ## limiar frouxo: o HD é redesenho, não upscale
			break
		if mapa.has(k) or usados.has(h):
			continue
		usados[h] = true
		mapa[k] = {"webp": "memo/%s" % h, "erro": snappedf(e, 0.0001)}
		var b := FileAccess.get_file_as_bytes("%s/memo/%s.webp" % [HIRES, h])
		if not b.is_empty():
			var destino := AssetIO.path("FILE/hd/%s.webp" % k)
			DirAccess.make_dir_recursive_absolute(destino.get_base_dir())
			var f2 := FileAccess.open(destino, FileAccess.WRITE)
			if f2 != null:
				f2.store_buffer(b)
		n_ok += 1
	print("[me] %d páginas casadas de %d (limiar 0,22)" % [n_ok, sd.size()])
	var fj := FileAccess.open("res://data/hd_memo_map.json", FileAccess.WRITE)
	fj.store_string(JSON.stringify({"n": n_ok, "mapa": mapa}, " "))
	quit(0)


func _erro(a: Image, b: Image) -> float:
	## Erro absoluto médio da LUMINÂNCIA (o texto é o mesmo; a cor do papel muda no redesenho).
	var soma := 0.0
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			soma += absf(ca.v - cb.v)
			n += 1
	return 1e9 if n == 0 else soma / float(n)
