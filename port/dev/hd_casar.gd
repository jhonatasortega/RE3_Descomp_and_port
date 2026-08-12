extends SceneTree
## ⚠ **OBSOLETO PARA `itema` E `placa` — NÃO RODE SEM `HD_SO_MOLDURA=1`.**
## Este script reescreve `data/hd_status_map.json` inteiro pelo método de SEMELHANÇA DE COR, e
## foi ele que trocou os ícones da grade (a Fita de tinta `0x81` ficou com o `.webp` dos
## Cartuchos de escopeta `0x17`). Dois furos: limiar 0.12 **sem margem**, e atribuição global
## **injetiva** — que é falsa no dado, porque vários `item_id` compartilham o mesmo bitmap de
## ícone. O de-para de ícone e placa agora é EXATO, por hash:
##
##     python tools/hd_match.py hash --apply
##
## O que ainda só existe aqui é a MOLDURA (bloco de VRAM, `HD_SO_MOLDURA=1`), que não tem hash
## reproduzível porque o bloco blitado depende das coordenadas do engine.
##
## Casa os assets HD do Seamless (nomes de HASH) com os do PS1 que o port já extraiu, POR
## CONTEÚDO — sem chute e sem depender do dump do plugin.
##
## Como: todo asset HD conferido é **exatamente 4×** o SD (medido nas 5 categorias). Então
## reduz-se o HD para o tamanho SD e compara-se pixel a pixel com o candidato. A métrica é a
## média do erro absoluto por canal (0 = igual); o HD é REDESENHADO à mão, então não dá 0 — o que
## vale é a MARGEM entre o melhor e o segundo colocado.
##
## Categorias (dimensões medidas em `hires/`):
##   item/  160×120  -> os 134 ícones 40×30 do `ITEMA.SLD`      (`MENU/status/itema/NNN.png`)
##   info/  448×288  -> as placas 112×72 do `ITEMG.PIX`         (`ETC/items/NNN.png`)
##   misc/ 1024×1024 -> candidatos à moldura `STMAIN0U`         (`MENU/status/stmain0u_p*.png`)
##
## Saída: `port/data/hd_status_map.json` + os arquivos copiados para
## `port/assets/MENU/status/hd/` com nome já resolvido (`itema/NNN.webp`, `plate/NNN.webp`,
## `chrome_p0.webp`), que é o que a tela consome.
const HIRES := "C:/Program Files (x86)/GOG Galaxy/Games/Resident Evil 3/hires"


func _initialize() -> void:
	## TRAVA: sem `HD_SO_MOLDURA=1` este script sobrescreveria `itema`/`placa` com o método
	## errado. Quem precisa desses dois usa `python tools/hd_match.py hash --apply`.
	if OS.get_environment("HD_SO_MOLDURA") == "":
		print("[hd] OBSOLETO para itema/placa. Use `python tools/hd_match.py hash --apply`.")
		print("[hd] Para recasar SÓ a moldura: HD_SO_MOLDURA=1 godot ... --script res://dev/hd_casar.gd")
		quit(1)
		return
	## PRESERVA o que não é desta ferramenta: `itema`/`placa` vêm do casamento por hash.
	var saida := {}
	var atual: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/hd_status_map.json"))
	if atual is Dictionary:
		saida = atual
	saida["moldura"] = _casar_moldura()
	saida["moldura_por_bloco"] = _casar_moldura_por_bloco()
	var f := FileAccess.open("res://data/hd_status_map.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(saida, "  "))
	print("[hd] escrito data/hd_status_map.json (só a moldura)")
	quit(0)


func _carregar_hd(caminho: String, alvo: Vector2i) -> Image:
	var img := Image.new()
	if img.load(caminho) != OK:
		return null
	img.resize(alvo.x, alvo.y, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _erro(a: Image, b: Image) -> float:
	## Erro absoluto médio só onde o SD tem pixel opaco (o fundo transparente do SD não conta).
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


func _ncc(a: Image, b: Image) -> float:
	## Correlação cruzada normalizada da LUMINÂNCIA: 1 = idêntico, 0 = sem relação.
	##
	## Por que trocar o erro absoluto por isto nos ícones: o HD é REDESENHADO (outra iluminação,
	## outro contraste, às vezes outro ângulo), e o erro absoluto de cor pune isso — só 49 dos 134
	## ícones passavam. A NCC compara o PADRÃO (o desenho), não o brilho: ela é invariante a
	## deslocamento e escala de intensidade, que é exatamente o que muda no redesenho.
	var n := 0
	var sa := 0.0
	var sb := 0.0
	var la: Array[float] = []
	var lb: Array[float] = []
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var va := ca.r * 0.299 + ca.g * 0.587 + ca.b * 0.114
			var vb := cb.r * 0.299 + cb.g * 0.587 + cb.b * 0.114
			la.append(va)
			lb.append(vb)
			sa += va
			sb += vb
			n += 1
	if n == 0:
		return 0.0
	var ma := sa / float(n)
	var mb := sb / float(n)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		var x1 := la[i] - ma
		var x2 := lb[i] - mb
		num += x1 * x2
		da += x1 * x1
		db += x2 * x2
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)


func _casar_categoria(cat: String, dir_sd: String, n_sd: int, tam: Vector2i,
		saida_sub: String) -> Dictionary:
	# carrega os HD reduzidos
	var d := DirAccess.open("%s/%s" % [HIRES, cat])
	if d == null:
		print("[hd] pasta %s ausente" % cat)
		return {}
	var hd := {}
	for f: String in d.get_files():
		if not f.ends_with(".webp"):
			continue
		var img := _carregar_hd("%s/%s/%s" % [HIRES, cat, f], tam)
		if img != null:
			hd[f.get_basename()] = img
	print("[hd] %s: %d candidatos reduzidos para %s" % [cat, hd.size(), tam])
	# ── ATRIBUIÇÃO GLOBAL (não item-por-item) ──
	# Antes eu percorria os itens em ordem e cada um levava o melhor HD ainda livre. Isso é
	# guloso NA ORDEM ERRADA: o item 3 podia levar o HD do item 90 e deixar 90 sem par (era o
	# motivo de só 49 dos 134 ícones casarem). Agora: calcula TODOS os pares, ordena do melhor
	# para o pior e vai fixando enquanto os dois lados estiverem livres — o par mais confiável
	# do conjunto decide primeiro.
	var sds := {}
	for i in n_sd:
		var rel := "%s/%03d.png" % [dir_sd, i]
		var sd := AssetIO.image(rel)
		if sd == null:
			continue
		sd.convert(Image.FORMAT_RGBA8)
		if sd.get_width() != tam.x or sd.get_height() != tam.y:
			sd.resize(tam.x, tam.y, Image.INTERPOLATE_LANCZOS)
		sds[i] = sd
	var pares_todos := []
	for i: int in sds:
		for k: String in hd:
			pares_todos.append([_erro(sds[i], hd[k]), i, k])
	pares_todos.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var mapa := {}
	var usados := {}
	var pares := 0
	for p2: Array in pares_todos:
		var e: float = p2[0]
		var i2: int = p2[1]
		var k2: String = p2[2]
		if e > 0.12:                             ## os casamentos conferidos deram 0,03..0,05
			break
		if mapa.has("%03d" % i2) or usados.has(k2):
			continue
		usados[k2] = true
		mapa["%03d" % i2] = {"webp": "%s/%s" % [cat, k2], "erro": snappedf(e, 0.0001)}
		_copiar("%s/%s/%s.webp" % [HIRES, cat, k2],
			"MENU/status/hd/%s/%03d.webp" % [saida_sub, i2])
		pares += 1
	print("[hd] %s: %d pares aceitos de %d SD" % [cat, pares, n_sd])
	return mapa


func _casar_moldura_por_bloco() -> Dictionary:
	## O plugin HD substitui por **bloco de VRAM**, não por arquivo: a moldura pode estar fatiada.
	## Então cada candidato de tamanho "4× de um pedaço" é testado contra TODAS as posições
	## alinhadas do `STMAIN0U`. Tamanhos que existem no pack e são pedaços plausíveis:
	##   512×1024  -> 128×256 SD   ·   1024×160 -> 256×40 SD   ·   1024×288 -> 256×72 SD
	var sd := AssetIO.image("MENU/status/stmain0u_p0.png")
	if sd == null:
		return {}
	sd.convert(Image.FORMAT_RGBA8)
	var melhores := []
	for par: Array in [[512, 1024, 128, 256], [1024, 160, 256, 40]]:
		var hw: int = par[0]
		var hh: int = par[1]
		var sw: int = par[2]
		var sh: int = par[3]
		var d := DirAccess.open("%s/misc" % HIRES)
		if d == null:
			continue
		var n := 0
		var melhor := {"erro": 1e9}
		for f: String in d.get_files():
			if not f.ends_with(".webp"):
				continue
			var img := Image.new()
			if img.load("%s/misc/%s" % [HIRES, f]) != OK:
				continue
			if img.get_width() != hw or img.get_height() != hh:
				continue
			n += 1
			img.resize(sw, sh, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGBA8)
			for x in range(0, 257 - sw, 32):
				for y in range(0, 273 - sh, 8):
					var rec := sd.get_region(Rect2i(x, y, sw, sh))
					var e := _erro(rec, img)
					if e < float(melhor["erro"]):
						melhor = {"erro": e, "webp": "misc/%s" % f.get_basename(),
							"pos": [x, y], "tam": [sw, sh]}
		if n > 0:
			print("[hd] bloco %dx%d: %d candidatos · melhor erro=%.4f em %s" % [
				hw, hh, n, melhor["erro"], melhor.get("pos", [])])
			melhores.append(melhor)
	# aceita só erro baixo de verdade (as placas casadas ficaram em 0.03..0.05)
	var bons := []
	for m: Dictionary in melhores:
		if float(m["erro"]) < 0.10:
			bons.append(m)
	return {"candidatos": melhores, "aceitos": bons}


func _casar_moldura() -> Dictionary:
	## A moldura do PS1 é 256×272, mas o bloco de VRAM que o HD substitui é a PÁGINA de 256×256 —
	## por isso os candidatos são 1024×1024. Compara-se só os 256×256 de cima.
	var d := DirAccess.open("%s/misc" % HIRES)
	if d == null:
		return {}
	var sd := AssetIO.image("MENU/status/stmain0u_p0.png")
	if sd == null:
		return {}
	sd.convert(Image.FORMAT_RGBA8)
	var sd256 := sd.get_region(Rect2i(0, 0, 256, 256))
	var melhor := ""
	var e1 := 1e9
	var e2 := 1e9
	var n := 0
	for f: String in d.get_files():
		if not f.ends_with(".webp"):
			continue
		var img := Image.new()
		if img.load("%s/misc/%s" % [HIRES, f]) != OK:
			continue
		if img.get_width() != 1024 or img.get_height() != 1024:
			continue
		n += 1
		img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		var e := _erro(sd256, img)
		if e < e1:
			e2 = e1
			e1 = e
			melhor = f.get_basename()
		elif e < e2:
			e2 = e
	print("[hd] moldura: %d candidatos 1024x1024 · melhor=%s erro=%.4f (2o=%.4f)" % [
		n, melhor, e1, e2])
	if melhor == "":
		return {}
	_copiar("%s/misc/%s.webp" % [HIRES, melhor], "MENU/status/hd/chrome_p0.webp")
	return {"webp": "misc/%s" % melhor, "erro": snappedf(e1, 0.0001),
		"margem": snappedf((e2 - e1) / maxf(e1, 0.0001), 0.001)}


func _copiar(de: String, para_rel: String) -> void:
	var destino := AssetIO.path(para_rel)
	DirAccess.make_dir_recursive_absolute(destino.get_base_dir())
	var b := FileAccess.get_file_as_bytes(de)
	if b.is_empty():
		return
	var f := FileAccess.open(destino, FileAccess.WRITE)
	if f != null:
		f.store_buffer(b)
