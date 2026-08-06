extends RefCounted
## Cobertura de background por câmera (critério do item P1-02).
##
## Toda uma das 2105 câmeras precisa resolver UMA imagem. O mod HD cobre 1232 backgrounds em
## 170 salas visitadas; o resto usa o PS1 320×240. Se alguma câmera ficar sem imagem, o jogo
## mostra tela preta naquele ângulo — e é o tipo de furo que só aparece quando se joga a sala.
##
## O teste também QUANTIFICA HD vs SD: esse número é o que decide o item aberto do plano
## (upscalar o SD, casar por pHash ou jogar as salas faltantes no PC para regerar o cache).

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("Backgrounds")

	var salas := _listar_salas()
	t.eq(salas.size(), 169, "169 salas")

	var n_cam := 0
	var hd := 0
	var sd := 0
	var sem := 0
	var sem_exemplos: Array[String] = []
	var salas_so_sd: Array[String] = []
	for id in salas:
		var r := RoomData.load_room(id)
		var sd_na_sala := 0
		for c in r.cameras:
			n_cam += 1
			var rel := CameraRID.background_rel(id, c.index)
			if rel == "":
				sem += 1
				if sem_exemplos.size() < 5:
					sem_exemplos.append("%s cam %d" % [id, c.index])
			elif rel.ends_with(".webp"):
				hd += 1
			else:
				sd += 1
				sd_na_sala += 1
		if sd_na_sala == r.cameras.size() and r.cameras.size() > 0:
			salas_so_sd.append(id)

	t.eq(n_cam, 2105, "2105 câmeras")
	t.eq(sem, 0, "nenhuma câmera sem background",
		"" if sem_exemplos.is_empty() else ", ".join(sem_exemplos))
	t.check(hd > 1400, "cobertura HD (esperado ~1508 de 2105)", "HD=%d SD=%d" % [hd, sd])
	t.eq(hd + sd, 2105, "HD + SD cobre todas as câmeras")
	# Diagnóstico para o item aberto do plano: quantas salas ficaram 100% em SD.
	t.check(salas_so_sd.size() < 40, "salas inteiramente sem HD",
		"%d salas: %s" % [salas_so_sd.size(), ", ".join(salas_so_sd.slice(0, 8))])

	# --- a textura realmente carrega de disco (não é só o caminho existir) ---
	var tex := CameraRID.background("R100", 0)
	t.check(tex != null, "background da R100 câmera 0 carrega")
	if tex != null:
		t.eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(1280, 960),
			"HD é 1280x960 (4x o PS1)")
	var sem_tex := AssetIO.texture("STAGE1/NAO_EXISTE.webp")
	t.check(sem_tex == null, "asset ausente devolve null (e registra a falha)")
	t.check(AssetIO.failures().has("STAGE1/NAO_EXISTE.webp"), "a falha fica registrada")

	# --- FOV por câmera: `attr` DECIFRADO (P1-04) ---
	# attr = distância de projeção × 128; FOV_vertical = 2·atan(120/h).
	t.near(CameraRID.projection_distance(29623), 231.4, 0.1,
		"h = attr/128 (231,4 para o attr mais comum)")
	t.near(CameraRID.fov_for(29623), 54.81, 0.02,
		"attr 29623 (43% das câmeras) -> 54,81° = o 55° calibrado à mão no protótipo")
	t.near(CameraRID.fov_for(37165), 44.91, 0.02, "attr 37165 (23%) -> 45°")
	t.near(CameraRID.fov_for(32946), 49.99, 0.02, "attr 32946 (22%) -> 50°")
	t.check(CameraRID.is_calibrated(29623), "todo attr válido tem FOV derivado do dado")
	t.eq(CameraRID.fov_for(0), CameraRID.FOV_DEFAULT, "attr zerado cai no default")

	# TESTE FORTE do decifrado: os 24 valores de attr do jogo dão graus INTEIROS.
	# É isso que descarta coincidência (2000 amostras aleatórias dão desvio médio 0,25 e
	# nenhuma chega perto disto).
	var attrs := {}
	for id in salas:
		for c in RoomData.load_room(id).cameras:
			attrs[c.attr] = true
	t.eq(attrs.size(), 24, "24 valores distintos de attr")
	var pior_desvio := 0.0
	var soma := 0.0
	for a: int in attrs:
		var f := CameraRID.fov_for(a)
		var d: float = absf(f - roundf(f))
		pior_desvio = maxf(pior_desvio, d)
		soma += d
	t.check(pior_desvio < 0.5, "todo attr dá FOV a menos de 0,5° de um grau inteiro",
		"pior desvio = %.3f°" % pior_desvio)
	t.check(soma / float(attrs.size()) < 0.15,
		"desvio MÉDIO abaixo de 0,15° (aleatório daria 0,25)",
		"média = %.3f°" % (soma / float(attrs.size())))

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var d := DirAccess.open("%s/STAGE%d" % [DATA_DIR, st])
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.begins_with("R") and nome.ends_with(".json") \
					and not nome.contains("_col") and not nome.contains("_scd"):
				saida.append(nome.trim_suffix(".json"))
	saida.sort()
	return saida
