extends RefCounted
## Valida PS1Math contra o DADO extraído do EXE (critério do item P0-05).
##
## O teste forte é o último: os **4096** ângulos reconstruídos por simetria têm que bater com
## a tabela real do jogo. Se essa conta fecha, rotação/mira/giro do port partem da mesma
## base numérica do PS1 — não de uma aproximação em float.

const TABLE_PATH := "res://data/ps1_sincos.json"


func run(t: Object) -> bool:
	t.group("PS1Math")

	# --- unidades de ângulo (12 bits) ---
	t.eq(PS1Math.FULL_CIRCLE, 4096, "círculo completo = 4096 unidades")
	t.eq(PS1Math.HALF_CIRCLE, 2048, "meia volta = 2048")
	t.eq(PS1Math.wrap_angle(-1), 4095, "wrap de negativo (andi 0xfff)")
	t.eq(PS1Math.wrap_angle(4096), 0, "wrap de volta completa")
	t.eq(PS1Math.wrap_angle(5000), 904, "wrap acima de uma volta")

	# --- pontos cardeais da tabela ---
	t.eq(PS1Math.rsin(0), 0, "sin(0) = 0")
	t.eq(PS1Math.rsin(1024), 4096, "sin(90°) = 1.0 (4096)")
	t.eq(PS1Math.rsin(2048), 0, "sin(180°) = 0")
	t.eq(PS1Math.rsin(3072), -4096, "sin(270°) = -1.0")
	t.eq(PS1Math.rcos(0), 4096, "cos(0) = 1.0")
	t.eq(PS1Math.rcos(1024), 0, "cos(90°) = 0")
	t.eq(PS1Math.rcos(2048), -4096, "cos(180°) = -1.0")
	t.eq(PS1Math.rsin(512), 2896, "sin(45°) = 2896 (valor real da tabela)")

	# --- menor rotação (bit 0x800 do EXE) ---
	t.eq(PS1Math.angle_diff(0, 100), 100, "diferença curta positiva")
	t.eq(PS1Math.angle_diff(100, 0), -100, "diferença curta negativa")
	t.eq(PS1Math.angle_diff(0, 3000), -1096, "atravessa o zero pelo lado curto")
	t.eq(PS1Math.angle_diff(4000, 100), 196, "wrap na diferença")
	t.check(absi(PS1Math.angle_diff(0, 2048)) == 2048, "meia volta = 2048 em módulo")
	t.eq(PS1Math.angle_towards(0, 1000, 100), 100, "giro limitado por passo")
	t.eq(PS1Math.angle_towards(0, 50, 100), 50, "chega ao alvo quando o passo é maior")
	t.eq(PS1Math.angle_towards(0, 3000, 100), 3996, "gira pelo lado curto (negativo)")

	# --- rotação em ponto-fixo ---
	# Ângulo 0 = identidade. (Como o eixo "frente" do PS1 se mapeia no -Z do Godot é
	# assunto de Coords.YAW_OFFSET_DEG, e só se prova por render na F1 — não se inventa aqui.)
	t.eq(PS1Math.rotate_xz(1000, 0, 0), Vector2i(1000, 0), "rotação por 0 é identidade")
	t.eq(PS1Math.rotate_xz(0, 1000, 0), Vector2i(0, 1000), "rotação por 0 preserva Z")
	var r90 := PS1Math.rotate_xz(1000, 0, 1024)
	t.check(absi(r90.x) <= 1 and absi(absi(r90.y) - 1000) <= 1,
		"rotação por 90° troca os eixos (x->0, |z|=1000)", str(r90))
	t.eq(PS1Math.rotate_xz(1000, 0, 2048), Vector2i(-1000, 0), "rotação por 180° inverte")
	var rlen := PS1Math.rotate_xz(1000, 0, 700)
	var comp := sqrt(float(rlen.x * rlen.x + rlen.y * rlen.y))
	t.near(comp, 1000.0, 2.0, "rotação preserva o comprimento (tolerância de ponto-fixo)")

	# --- ângulo de um vetor (usado por mira/IA) ---
	t.eq(PS1Math.angle_of_xz(0, 1000), 0, "vetor +Z = ângulo 0")
	t.eq(PS1Math.angle_of_xz(1000, 0), 1024, "vetor +X = 90°")
	t.eq(PS1Math.angle_of_xz(0, -1000), 2048, "vetor -Z = 180°")

	# --- ida e volta com graus ---
	# 4096 passos não representam todo grau exatamente: o erro tem que ficar dentro de
	# meia unidade de ângulo (0,0439°). Exigir igualdade exata seria exigir do dado algo
	# que ele não tem.
	for d: int in [0, 45, 90, 180, 270, 359]:
		t.near(PS1Math.to_deg(PS1Math.from_deg(float(d))), float(d),
			PS1Math.DEG_PER_UNIT / 2.0, "grau -> unidade -> grau (%d°, tol meia unidade)" % d)
	for a: int in [0, 1, 512, 1024, 2048, 4095]:
		t.eq(PS1Math.from_deg(PS1Math.to_deg(a)), a, "unidade -> grau -> unidade (%d)" % a)

	# --- TESTE FORTE: os 4096 ângulos contra a tabela do EXE ---
	if not FileAccess.file_exists(TABLE_PATH):
		t.check(false, "data/ps1_sincos.json presente (rode tools/exe_sincos.py)")
		return false
	t.check(PS1Math.table_from_exe(), "tabela carregada do dado extraído do EXE")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
	var q: Array = raw["quarter_wave"]
	t.eq(q.size(), 1025, "quarto de onda com 1025 entradas")

	var pior := 0
	for a in 4096:
		var esperado: int = 0
		if a < 1024:
			esperado = int(q[a])
		elif a < 2048:
			esperado = int(q[2048 - a])
		elif a < 3072:
			esperado = -int(q[a - 2048])
		else:
			esperado = -int(q[4096 - a])
		pior = maxi(pior, absi(PS1Math.rsin(a) - esperado))
	t.eq(pior, 0, "os 4096 ângulos batem com a tabela do EXE (erro máximo)")

	# sin²+cos² ≈ 1.0 em ponto-fixo, nos 4096 ângulos
	var pior_norma := 0
	for a in 4096:
		var s := PS1Math.rsin(a)
		var c := PS1Math.rcos(a)
		pior_norma = maxi(pior_norma, absi(s * s + c * c - PS1Math.ONE * PS1Math.ONE))
	t.check(float(pior_norma) / float(PS1Math.ONE * PS1Math.ONE) < 0.001,
		"sin²+cos² dentro de 0,1% de 1.0 nos 4096 ângulos",
		"desvio relativo máx = %f" % (float(pior_norma) / float(PS1Math.ONE * PS1Math.ONE)))

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true
