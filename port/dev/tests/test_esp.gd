extends RefCounted
## Efeitos ESP **da sala** — o fogo do cenário (`port/present/esp_sala.gd`).
##
## Cada assert aqui é um número LIDO do CD ou do EXE, não um valor escolhido:
##   • os ids de ESP da sala vêm de `RDT off[17]` (`tools/rdt_esp.py`);
##   • os bancos, quadros e ticks vêm de `RDT off[17]/off[18]` (`tools/esp_decode.py`);
##   • as instâncias e as POSIÇÕES vêm do opcode SCD `0x70` (handler `0x80056004`), com
##     âncora `0` = matriz identidade de translação zero em `0x80098970`;
##   • os quadros em HD vêm de `tools/esp_decode.py hd` (`port/data/esp_hd_map.json`).
## Se qualquer um mudar, isto fica VERMELHO em vez de o fogo sumir em silêncio.
##
##     godot --headless --path port --script res://dev/run_tests.gd -- esp
##
## ⚠ Este arquivo já esteve em quarentena por PENDURAR a suíte. A causa era a varredura das
## 156 salas chamando `EspSala.carregar()` (cada chamada abre PNG e monta nó). Regra desta
## suíte: `carregar()` no MÁXIMO em `SALAS_CARREGADAS`; o resto é conferência do JSON, que
## é aritmética de dicionário e roda em milissegundos.

const ARQ := "esp_sala.json"
const ARQ_HD := "esp_hd_map.json"
## Quantas salas podem passar por `carregar()` na varredura (a que custa I/O).
const SALAS_CARREGADAS := 6


static func ints(a: Variant) -> Array[int]:
	## O `JSON.parse_string` do Godot devolve todo número como float — comparar
	## `[8.0, 9.0]` com `[8, 9]` falha. Converte antes de comparar.
	var out: Array[int] = []
	for x: Variant in (a as Array):
		out.append(int(x))
	return out


func run(t: Object) -> bool:
	t.group("EspSala")

	var raw: Variant = AssetIO.json(ARQ)
	if not (raw is Dictionary) or not (raw as Dictionary).has("salas"):
		t.check(false, "data/%s existe" % ARQ,
			"rode `python tools/esp_decode.py dump port/assets/ESP --all-rooms`")
		return true
	var salas: Dictionary = (raw as Dictionary)["salas"]
	t.eq(salas.size(), 156, "156 salas têm bloco de ESP no RDT (off[17] != 0 e != -1)")

	# ── 1. R10D: os ids de ESP declarados no RDT ──────────────────────────────────────
	t.check(salas.has("R10D"), "R10D está no dado de ESP")
	var r10d: Dictionary = salas["R10D"]
	t.eq(ints(r10d["tipos"]), [0x08, 0x09, 0x18, 0x0C, 0x24, 0x26] as Array[int],
		"R10D declara 6 bancos de ESP: 08 09 18 0c 24 26")
	# a tabela de ids do RDT (rdt_esp.json) tem de dizer o MESMO — dois caminhos, um dado
	var rdt: Variant = AssetIO.json("rdt_esp.json")
	if rdt is Dictionary and (rdt as Dictionary).has("salas"):
		var reg: Dictionary = ((rdt as Dictionary)["salas"] as Dictionary).get("R10D", {})
		t.eq(ints(reg.get("esp_ids", [])), ints(r10d["tipos"]),
			"off[17] (rdt_esp.json) e a lista de tipos do banco batem")

	# ── 2. os bancos de FOGO: 0x24 e 0x26 ────────────────────────────────────────────
	var bancos: Dictionary = r10d["bancos"]
	for tipo: int in [0x24, 0x26]:
		var b: Dictionary = bancos[str(tipo)]
		t.eq(b["A"], 11, "banco 0x%02x: 11 entradas na tabela A" % tipo)
		t.eq(b["B"], 10, "banco 0x%02x: 10 retângulos na tabela B" % tipo)
		t.eq(ints(b["tpage_vram"]), [832, 0] as Array[int],
			"banco 0x%02x: tpage 0x000d = VRAM (832,0)" % tipo)
		var ef: Dictionary = (b["efeitos"] as Dictionary)["0"]
		t.eq(ef["n_slots"], 1, "banco 0x%02x efeito 0: 1 slot" % tipo)
		var fr: Dictionary = (ef["slots"] as Array)[0]
		t.eq(fr["handler"], 0x00, "banco 0x%02x efeito 0: handler 0x00 (no-op)" % tipo)
		t.eq(fr["flags"], 0xB803, "banco 0x%02x efeito 0: flags 0xb803" % tipo)
		t.check(fr["desenha"], "banco 0x%02x efeito 0 DESENHA (bit 13)" % tipo)
		t.eq(fr["tpage_or"], 0x20, "banco 0x%02x efeito 0: tpage_or 0x20" % tipo)
		t.check(fr["aditivo"], "banco 0x%02x efeito 0 é ADITIVO (abr 1 = B+F)" % tipo)
		t.eq(fr["escala_x"], 4096, "banco 0x%02x: escala_x = 0x1000 (1.0)" % tipo)
		var anim: Dictionary = fr["anim"]
		var q: Array = anim["quadros"]
		t.eq(q.size(), 10, "banco 0x%02x: 10 quadros de chama" % tipo)
		t.eq(anim["fim"], "loop", "banco 0x%02x: a 11ª entrada da tabela A é 0xff = LAÇO" % tipo)
		t.eq(anim["loop_para"], 0, "banco 0x%02x: o laço volta para a entrada A0" % tipo)
		t.eq(anim["ticks_total"], 10,
			"banco 0x%02x: 10 quadros × 1 tick = 10 ticks (0,333 s a 30 Hz)" % tipo)
		var tamanhos: Array[int] = []
		var ticks: Array[int] = []
		for x: Variant in q:
			tamanhos.append(int((x as Dictionary)["px"]))
			ticks.append(int((x as Dictionary)["ticks"]))
		t.eq(tamanhos, [48, 48, 48, 48, 48, 48, 48, 48, 48, 48],
			"banco 0x%02x: todos os quadros 48×48 texels" % tipo)
		t.eq(ticks, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
			"banco 0x%02x: 1 tick por quadro" % tipo)
	# o pivô é o que põe a chama EM PÉ no chão: oy = -size (base no ponto âncora)
	var q24: Dictionary = ((((bancos["36"] as Dictionary)["efeitos"] as Dictionary)["0"]
		as Dictionary)["slots"] as Array)[0]["anim"]["quadros"][0]
	t.eq(int(q24["oy"]), -48, "banco 0x24: pivô oy = -48 = a BASE da chama no ponto âncora")
	t.eq(int(q24["ox"]), -24, "banco 0x24: pivô ox = -24 = centrado na horizontal")
	var q26: Dictionary = ((((bancos["38"] as Dictionary)["efeitos"] as Dictionary)["0"]
		as Dictionary)["slots"] as Array)[0]["anim"]["quadros"][0]
	t.eq(int(q26["oy"]), -42, "banco 0x26: pivô oy = -42 (base 6 px abaixo da âncora)")
	# CLUTs diferentes = as duas chamas têm cor própria (clut>>6 = linha da VRAM)
	t.eq(ints((bancos["36"] as Dictionary)["clut_vram"]), [288, 488] as Array[int],
		"banco 0x24: CLUT em (288,488)")
	t.eq(ints((bancos["38"] as Dictionary)["clut_vram"]), [288, 490] as Array[int],
		"banco 0x26: CLUT em (288,490)")

	# ── 3. as instâncias do opcode 0x70 no R10D ──────────────────────────────────────
	var inst: Array = r10d["instancias"]
	t.eq(inst.size(), 29, "R10D executa 29 vezes o opcode 0x70 no script")
	var init_n := 0
	var ancora_zero := 0
	var fogo: Array[Dictionary] = []
	for x_v: Variant in inst:
		var x: Dictionary = x_v
		if int(x["ancora_tipo"]) == 0 and int(x["ancora_indice"]) == 0:
			ancora_zero += 1
		if str(x["alcance"]) == "init":
			init_n += 1
		if str(x["alcance"]) == "init" and int(x["tipo"]) in [0x24, 0x26]:
			fogo.append(x)
	t.eq(ancora_zero, 29, "as 29 instâncias usam âncora (0,0) = matriz identidade")
	t.eq(init_n, 12, "12 rodam na ENTRADA da sala (f0 → gosub f2 → gosub f38)")
	t.eq(fogo.size(), 8, "8 dessas 12 são CHAMA (bancos 0x24/0x26)")
	for x: Dictionary in fogo:
		t.eq(int(x["func"]), 38, "chama criada na função 38 do SCD")
		t.eq(int(x["bloco"]), 0, "chama criada em bloco INCONDICIONAL (sem `if` aberto)")
		# O Y das 8 é ZERO no dado do opcode: nenhuma chama do R10D é "de parede". O que
		# fazia uma delas parecer colada na parede na altura do peito era a falta de
		# profundidade (§ camada), não um Y errado.
		t.eq(int((x["pos"] as Array)[1]), 0, "chama no nível y = 0 (o chão do R10D)")
		t.eq(int(x["efeito"]), 0, "chama = efeito 0x00 do banco")
		t.eq(int(x["variante"]), 0, "chama na variante 0 (linha de CLUT do próprio banco)")

	# ── 4. o nó de apresentação monta as 8 chamas ────────────────────────────────────
	var esp := EspSala.new()
	t.check(esp.dados_carregados(), "EspSala lê data/%s" % ARQ)
	t.eq(esp.salas_conhecidas(), 156, "EspSala vê as 156 salas")
	var n := esp.carregar("R10D")
	t.eq(n, 8, "EspSala monta 8 efeitos no R10D (as chamas)")
	t.eq(esp.n_puladas_thread, 17, "17 instâncias são de thread (não provadas na entrada)")
	t.eq(esp.n_puladas_sem_banco, 4,
		"4 instâncias pedem o banco 0x03 do CORE00 (controlador, não desenha)")
	t.eq(esp.vivos(), 8, "as 8 nascem vivas")

	# tamanho de mundo pela fórmula provada em 0x80022ccc:
	#   largura_ps1 = size * param_hi * escala_x / (256 * 4096)
	# 1ª chama do R10D: size 48, param_hi 0x2040 (8256), escala_x 0x1000
	var e0: Object = (esp.efeitos as Array)[0]
	t.eq(e0.get("tipo"), 0x26, "a 1ª chama montada é a 1ª do script: banco 0x26")
	t.eq(e0.get("escala"), 0x2040, "1ª chama: param_hi = 0x2040")
	t.eq(e0.get("pos"), Vector3i(16187, 0, -10637), "1ª chama em (16187, 0, -10637)")
	var larg_ps1 := 48.0 * 8256.0 * 4096.0 / 1048576.0
	t.near(larg_ps1, 1548.0, 0.5, "1ª chama: 1548 unidades PS1 de largura")
	t.near(e0.call("larg_ps1"), larg_ps1, 0.01,
		"o nó calcula a mesma largura de mundo da fórmula do EXE")
	var no0: Sprite2D = e0.get("no")
	t.check(no0 != null, "a chama é um Sprite2D 2D sobre o quadro (não billboard no 3D)")
	t.check(not no0.centered, "pivô no CANTO: o `ofs` da tabela B é do canto, não do centro")
	var mat: CanvasItemMaterial = no0.material
	t.eq(mat.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "material ADITIVO (abr 1)")

	# ── 5. QUADROS EM HD: 4× o SD, casados por conteúdo ──────────────────────────────
	var hd: Variant = AssetIO.json(ARQ_HD)
	if hd is Dictionary and ((hd as Dictionary)["salas"] as Dictionary).has("R10D"):
		var bhd: Dictionary = (((hd as Dictionary)["salas"] as Dictionary)["R10D"]
			as Dictionary)["bancos"]
		for tipo: int in [0x24, 0x26]:
			var par: Dictionary = (bhd[str(tipo)] as Dictionary)["v0"]
			t.check(float(par["ncc"]) >= 0.99,
				"banco 0x%02x v0: par HD com NCC >= 0,99 (%s)" % [tipo, par["webp"]],
				"ncc=%s" % par["ncc"])
			t.check(float(par["ncc_do_1o_reprovado"]) < 0.9,
				"banco 0x%02x v0: o 1º reprovado fica abaixo de 0,9 (folga do casamento)"
					% tipo, "ncc=%s" % par["ncc_do_1o_reprovado"])
			t.eq(int(par["quadros"]), 10, "banco 0x%02x v0: 10 quadros recortados em HD" % tipo)
		t.eq(esp.n_quadros_hd, 80, "as 8 chamas × 10 quadros usam o asset HD")
		t.check(e0.get("hd"), "a 1ª chama está em HD")
		t.eq((e0.get("texturas") as Array)[0].get_width(), 48 * 4,
			"quadro HD = 192 px = 4× os 48 texels do PS1")
	else:
		t.check(false, "data/%s tem R10D" % ARQ_HD,
			"rode `python tools/esp_decode.py hd --room STAGE1/R10D`")

	# ── 6. a cadência: 10 quadros de 1 tick, em laço ─────────────────────────────────
	var vistos: Array[int] = []
	for i in 25:
		vistos.append(int(e0.get("indice")))
		esp.avancar(null)
	t.eq(vistos.slice(0, 10), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
		"os 10 quadros passam um por tick")
	t.eq(vistos.slice(10, 20), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
		"depois do 10º o laço volta ao quadro 0")
	t.eq(esp.vivos(), 8, "nenhuma chama morre (é laço, não sequência que acaba)")
	t.eq((e0.get("desloc") as Vector3i), Vector3i.ZERO,
		"a chama não se move: vel e acc do frame record são zero")

	# ── 7. PROFUNDIDADE: a chave de OT do efeito é a MESMA do personagem ─────────────
	# O motor não tem z-buffer: quem entra na Ordering Table com chave MENOR fica na FRENTE
	# (`0x80029618`). O efeito entra com `z >> 5` (`0x80022de0`) e o personagem com
	# `zona*1024 + SZ>>5` (`0x80037d50` + `0x8002b86c`) — este bloco prova que as duas
	# contas dão o MESMO número para o MESMO ponto, comparando com o `occlusion.gd`, que é
	# a implementação independente da regra do cenário.
	var room := RoomData.load_room("R10D")
	if t.check(room.cameras.size() == 13, "R10D tem 13 câmeras",
			"%d" % room.cameras.size()):
		var occ := Occlusion.new()
		var n_masc := occ.carregar(room, 0)
		esp.avancar(null, room, 0, EspSala.CHAVE_LONGE)
		t.eq((esp.get("_mascaras") as Array).size(), n_masc,
			"EspSala vê os mesmos %d recortes de máscara que o Occlusion na câmera 0"
				% n_masc)
		var alvo := Vector3i(16187, 0, -10637)          ## a 1ª chama
		occ.atualizar_profundidade(room.camera(0), alvo)
		t.eq(esp.chave_ot(alvo, null), occ.char_key,
			"a chave de OT do efeito e a do personagem no MESMO ponto são iguais")
		# ordem: quanto mais LONGE da câmera, MAIOR a chave (é a definição de `z >> 5`)
		var perto := esp.chave_ot(Vector3i(14493, 0, -8854), null)
		var longe := esp.chave_ot(Vector3i(15693, 0, -14854), null)
		t.check(perto != longe, "duas chamas em Z diferente têm chaves diferentes",
			"perto=%d longe=%d" % [perto, longe])
		var c := room.camera(0)
		var d_perto := Vector3(float(14493 - c.from_ps1.x), 0.0,
			float(-8854 - c.from_ps1.z)).length()
		var d_longe := Vector3(float(15693 - c.from_ps1.x), 0.0,
			float(-14854 - c.from_ps1.z)).length()
		t.eq(perto < longe, d_perto < d_longe,
			"a chave cresce com a distância à câmera (mais perto = fica na frente)")
		# a decisão de camada é uma comparação de inteiros; aqui se prova o efeito dela na
		# árvore (o sprite muda de camada de desenho, que é o que o `screen.gd` compõe)
		esp._por_na_camada(e0, true)
		t.eq(no0.get_parent().name, StringName("Sprites"),
			"chave menor que a do personagem → sprite vai para a camada da FRENTE")
		esp._por_na_camada(e0, false)
		t.eq(no0.get_parent().name, StringName("Atras"),
			"chave maior/igual → sprite volta para a camada de TRÁS (o 3D cobre)")
		occ.free()

	# ── 8. varredura das 156 salas: coerência do dado (SEM abrir asset) ──────────────
	var n_com_inst := 0
	var n_inst := 0
	var n_ancora_outra := 0
	var pior := ""
	for id: String in salas:
		var s: Dictionary = salas[id]
		var lista: Array = s["instancias"]
		if not lista.is_empty():
			n_com_inst += 1
		for x_v: Variant in lista:
			var x: Dictionary = x_v
			n_inst += 1
			if int(x["ancora_tipo"]) != 0:
				n_ancora_outra += 1
		for k: String in (s["bancos"] as Dictionary):
			var b: Dictionary = (s["bancos"] as Dictionary)[k]
			if int(b["A"]) <= 0 or int(b["B"]) <= 0:
				pior = "%s banco %s" % [id, k]
	t.eq(pior, "", "nenhum banco de sala com tabela A ou B vazia")
	t.check(n_com_inst >= 60, "pelo menos 60 salas criam efeito por script",
		"%d salas, %d instâncias" % [n_com_inst, n_inst])
	t.check(n_inst > 900, "há mais de 900 instâncias de 0x70 no jogo", "%d" % n_inst)
	t.check(n_ancora_outra > 0,
		"existem instâncias ancoradas em entidade (âncora != 0) — não posicionáveis aqui",
		"%d de %d" % [n_ancora_outra, n_inst])

	# ── 9. as primeiras salas com efeito montam sem erro (I/O limitado) ──────────────
	# Só `SALAS_CARREGADAS` salas: `carregar()` abre PNG e monta nó, e é o que pendurava
	# esta suíte quando rodava nas 156.
	var carregadas := 0
	var total_efeitos := 0
	for id: String in salas:
		if carregadas >= SALAS_CARREGADAS:
			break
		if (salas[id] as Dictionary)["instancias"].is_empty():
			continue
		total_efeitos += esp.carregar(id)
		carregadas += 1
	t.eq(carregadas, SALAS_CARREGADAS,
		"%d salas com instância passam por carregar() sem erro" % SALAS_CARREGADAS)
	t.check(total_efeitos >= 0, "nenhuma sala carregada devolve efeito negativo",
		"%d efeitos somados" % total_efeitos)

	# ── 10. sala sem 0x70: o nó não inventa efeito ───────────────────────────────────
	var vazia := ""
	for id: String in salas:
		if (salas[id] as Dictionary)["instancias"].is_empty():
			vazia = id
			break
	if vazia != "":
		t.eq(esp.carregar(vazia), 0,
			"%s tem banco de ESP mas nenhum 0x70: 0 efeito, sem placeholder" % vazia)
	t.eq(esp.carregar("R000"), 0, "sala inexistente: 0 efeito, sem erro")
	esp.limpar()
	esp.free()
	return true
