extends RefCounted
## Valida a conversão de coordenadas (critério do item P0-06).
##
## Teste forte 1: ida-e-volta de 10.000 pontos em unidades PS1 sem perda.
## Teste forte 2: as 2105 câmeras reais do jogo projetam o próprio alvo (`to`) no centro da
## tela — o que prova, com o dado de sala, que a convenção de eixos está certa. Sem isso o
## cenário 2D e o 3D não se alinham (e é onde um port erra silenciosamente).

const DATA_DIR := "res://data"


func run(t: Object) -> bool:
	t.group("Coords")

	# --- escala ---
	t.near(Coords.WORLD_SCALE, 808.0, 0.001, "world_scale = 808 (2400 / 2.971)")
	t.near(Coords.len_to_godot(2400.0), 2.9703, 0.001, "2400 un PS1 = altura do personagem (~2.97)")

	# --- eixos: X preservado, Y e Z NEGADOS (dois eixos, para não trocar a mão do sistema) ---
	# Negar só o Y espelharia a cena: o PS1 é canhoto (Y para baixo) e o Godot é destro.
	# Medido na R100 com um eixo só: o fichário, que aparece à DIREITA no cenário, projetava
	# à esquerda da Jill. Com `(x,-y,-z)` ele projeta à direita, como no cenário.
	var g := Coords.to_godot(Vector3(808.0, 808.0, 808.0))
	t.near(g.x, 1.0, 1e-5, "X preservado")
	t.near(g.y, -1.0, 1e-5, "Y negado (PS1 é +Y para baixo)")
	t.near(g.z, -1.0, 1e-5, "Z negado (preserva a mão do sistema)")

	# --- ida e volta em 10.000 pontos ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731                      # semente fixa: teste determinístico
	var pior := 0
	for _i in 10000:
		var p := Vector3i(rng.randi_range(-30000, 30000), rng.randi_range(-4000, 4000),
			rng.randi_range(-30000, 30000))
		var volta := Coords.to_ps1_i(Coords.to_godot_i(p.x, p.y, p.z))
		pior = maxi(pior, (volta - p).abs().max_axis_index() if false else
			maxi(absi(volta.x - p.x), maxi(absi(volta.y - p.y), absi(volta.z - p.z))))
	t.eq(pior, 0, "ida-e-volta PS1->Godot->PS1 em 10.000 pontos (erro máximo em unidades)")

	# --- ângulo: ida e volta ---
	for a: int in [0, 512, 1024, 2048, 3072, 4095]:
		t.eq(Coords.ps1_angle_from_yaw(Coords.yaw_from_ps1_angle(a)), a,
			"ângulo PS1 -> yaw -> PS1 (%d)" % a)

	# --- TESTE FORTE: invariantes da conversão sobre as 2105 câmeras REAIS do jogo ---
	#
	# Nota metodológica: "a câmera projeta seu próprio alvo no centro da tela" NÃO serve como
	# teste de conversão — é tautológico, pois `look_at(alvo)` garante isso mesmo com os eixos
	# errados. Esse teste pertence à F1 (P1-04), com render de verdade sobre o background.
	# Aqui valem invariantes que um erro de eixo/escala QUEBRA na hora:
	#   1. sinal do Y: no PS1 (+Y para baixo) a câmera fica "acima" quando from.y < to.y;
	#      no Godot isso tem de virar from.y > to.y — para TODAS as câmeras.
	#   2. escala: a distância câmera->alvo em Godot × 808 tem de dar a distância em unidades PS1.
	var salas := _listar_salas()
	if salas.is_empty():
		t.check(false, "data/STAGE*/R*.json presentes (rode tools/build_assets.py --only rooms)")
		return false

	var n_cam := 0
	var y_invertido_errado := 0
	var pior_erro_dist := 0.0
	var acima := 0
	for caminho in salas:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(caminho))
		if not (raw is Dictionary) or not raw.has("rdt"):
			continue
		var rdt: Variant = raw["rdt"]
		if not (rdt is Dictionary) or not rdt.has("cameras"):
			continue
		for c: Dictionary in rdt["cameras"]:
			# from/to são ARRAYS [x,y,z] em unidades PS1 (ver tools/ard_parse.py)
			var f: Array = c["from"]
			var to: Array = c["to"]
			var fy := int(f[1])
			var ty := int(to[1])
			var pf := Coords.to_godot_i(int(f[0]), fy, int(f[2]))
			var pt := Coords.to_godot_i(int(to[0]), ty, int(to[2]))
			n_cam += 1
			if fy != ty and (fy < ty) != (pf.y > pt.y):
				y_invertido_errado += 1
			if fy < ty:
				acima += 1
			var d_ps1 := Vector3(float(int(f[0]) - int(to[0])), float(fy - ty),
				float(int(f[2]) - int(to[2]))).length()
			if d_ps1 > 1.0:
				var d_godot: float = pf.distance_to(pt) * Coords.WORLD_SCALE
				pior_erro_dist = maxf(pior_erro_dist, absf(d_godot - d_ps1) / d_ps1)

	t.check(n_cam > 2000, "câmeras lidas do dado real (esperado 2105)", "n = %d" % n_cam)
	t.eq(y_invertido_errado, 0,
		"inversão de Y consistente nas %d câmeras (PS1 +Y para baixo)" % n_cam)
	# (GDScript não tem %e no format — usar str() para valores muito pequenos)
	t.check(pior_erro_dist < 1e-4, "distância câmera->alvo preservada pela escala",
		"erro relativo máx = " + str(pior_erro_dist))
	# Sanidade do DADO (não da conversão): a maioria das câmeras do RE olha de cima para baixo.
	# MEDIDO: 1714 de 2105 = 81,4% — o limiar abaixo reflete a medição, não um chute
	# (as ~19% restantes são câmeras no nível do olho ou olhando de baixo, que existem).
	t.check(float(acima) / float(n_cam) > 0.75,
		"maioria das câmeras olha de cima (medido: 81,4 por cento)",
		"%.1f por cento (%d de %d)" % [100.0 * float(acima) / float(n_cam), acima, n_cam])

	# ── Rotação de 3 eixos do `0x7f` (convenção MEDIDA, ver Coords.basis_from_ps1_rot) ──
	# Trava o resultado da medição: `Rx·Ry·Rz` com `(+x, −y, −z)`. Se alguém "simplificar" para
	# um `rotation = Vector3(...)` do Godot (ordem YXZ) ou trocar sinal, estes casos acusam.
	var b0 := Coords.basis_from_ps1_rot(Vector3i.ZERO)
	t.check(b0.is_equal_approx(Basis.IDENTITY), "rotação nula é identidade")
	# 1024 unidades = 90°. Em Y, o sinal é INVERTIDO na conversão para o Godot:
	# um giro PS1 de +90° em Y leva +X para... -Z no PS1, que é +Z no Godot -> Basis(UP, -90°).
	var by := Coords.basis_from_ps1_rot(Vector3i(0, 1024, 0))
	t.check(by.is_equal_approx(Basis(Vector3.UP, deg_to_rad(-90.0))),
		"giro de 90 graus em Y inverte o sinal (medido)", "%s" % by)
	var bx := Coords.basis_from_ps1_rot(Vector3i(1024, 0, 0))
	t.check(bx.is_equal_approx(Basis(Vector3.RIGHT, deg_to_rad(90.0))),
		"giro em X mantém o sinal (é o eixo da conversão de mundo)", "%s" % bx)
	# ORDEM: com dois eixos, `Rx·Ry·Rz` != `Rz·Ry·Rx`. O caso da Chave do armazém da R100
	# (`rot(2048, 5120, 1024)`) é o que a medição usou para decidir.
	var chave := Coords.basis_from_ps1_rot(Vector3i(2048, 5120, 1024))
	var xyz := Basis(Vector3.RIGHT, deg_to_rad(180.0)) * Basis(Vector3.UP, deg_to_rad(-450.0)) \
		* Basis(Vector3.BACK, deg_to_rad(-90.0))
	t.check(chave.is_equal_approx(xyz), "ordem de composição é Rx·Ry·Rz (medida)", "%s" % chave)
	var zyx := Basis(Vector3.BACK, deg_to_rad(-90.0)) * Basis(Vector3.UP, deg_to_rad(-450.0)) \
		* Basis(Vector3.RIGHT, deg_to_rad(180.0))
	t.check(not chave.is_equal_approx(zyx), "a ordem inversa (Rz·Ry·Rx) daria outra base")

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true


func _listar_salas() -> Array[String]:
	var saida: Array[String] = []
	for st in range(1, 8):
		var dir_path := "%s/STAGE%d" % [DATA_DIR, st]
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			var nome := f.trim_suffix(".remap")
			if nome.begins_with("R") and nome.ends_with(".json") \
					and not nome.contains("_col") and not nome.contains("_scd"):
				saida.append("%s/%s" % [dir_path, nome])
	saida.sort()
	return saida
