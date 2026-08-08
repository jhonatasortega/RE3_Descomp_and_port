extends SceneTree
## Diagnóstico do banco de som DA SALA (`cat 2`) no jogo de verdade.
##
##     GODOT="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
##     "$GODOT" --path port --headless --audio-driver Dummy --script res://dev/diag_som_sala.gd
##     "$GODOT" --path port --script res://dev/diag_som_sala.gd     # com WASAPI, para OUVIR
##
## Por que existe: os 26 pedidos de `cat 2` do EXE (porta trancada/destrancar/emperrada, baú,
## subir, ricochete, SE por script) resolviam no `R000`, cuja tabela de SE é toda `0xffffffff`
## — ou seja silêncio. Depois de `tools/exe_audio.py --salas` eles têm amostra, e este
## diagnóstico responde, em ordem:
##   1. o `Sfx` conhece os 169 bancos de sala?
##   2. a troca de sala seleciona o banco (o gancho é `Audio.tocar_bgm_da_sala`)?
##   3. para cada pedido de `cat 2`: qual WAV, existe, o stream carrega, e o pool tocou?
##   4. quais salas do jogo definem cada id (o silêncio nas outras é o do original)?
##
## Detalhe e provas: `docs/decomp/notes/exe_audio.md §13`.
##
## ⚠ O autoload `Game` só existe A PARTIR do 1º quadro (com `--script` o `_initialize` roda
##    antes dos autoloads) — daí a checagem viver no `_process`.

## Os pedidos de `cat 2` com id constante, na ordem de prioridade do dono do repo.
const PEDIDOS := [
	["porta_trancada", Sfx.SE_PORTA_TRANCADA, "0x80050e10/0x80050ed8/0x80050f14"],
	["porta_destrancar", Sfx.SE_PORTA_DESTRANCAR, "0x80050e74"],
	["porta_emperrada", Sfx.SE_PORTA_EMPERRADA, "0x80050dd8"],
	["porta_trancada(knock)", Sfx.SE_PORTA_TRANCADA_KNOCK, "0x80050ec8"],
	["porta_destrancar(knock)", Sfx.SE_PORTA_DESTRANCAR_KNOCK, "0x80050e64"],
	["bau_abrir", Sfx.SE_BAU_ABRIR, "0x80051578"],
	["bau_mover", Sfx.SE_BAU_MOVER, "0x80064b2c"],
	["subir", Sfx.SE_SUBIR, "0x8003b224"],
	["subir_impacto", Sfx.SE_SUBIR_IMPACTO, "0x8003b3e8"],
	["mapa_navegar", Sfx.SE_MAPA_NAVEGAR, "0x8006f790"],
	["inimigo_t21", Sfx.SE_INIMIGO_T21, "0x8001db0c"],
	["zumbi", Sfx.SE_ZUMBI, "0x8001edb8"],
	["zumbi_alt", Sfx.SE_ZUMBI_ALT, "0x8001edb8"],
	["ator_19 (NAO SEI)", Sfx.SE_ATOR_19, "0x80021cdc/0x80036934"],
	["ator_2 (NAO SEI)", Sfx.SE_ATOR_2, "0x80036b8c"],
	["sce11_40 (NAO SEI)", Sfx.SE_SCE11_40, "0x800517d0"],
	["draw_46 (NAO SEI)", Sfx.SE_DRAW_46, "0x80024f04/0x80025038/0x800250f0"],
]

## Salas de amostragem: R101 (trancada+destrancar), R105 (emperrada), R100 (baú), R201 (subir).
const SALAS := ["R101", "R105", "R100", "R201"]

var _quadros := 0


func _process(_dt: float) -> bool:
	_quadros += 1
	if _quadros < 3:
		return false
	var g := root.get_node_or_null("Game")
	var s: Sfx = g.get("sfx") as Sfx if g != null else null
	var a: Audio = g.get("audio") as Audio if g != null else null
	print("autoload Game=%s  Sfx=%s pronto=%s  Audio=%s"
		% [g != null, s != null, s.pronto() if s != null else false, a != null])
	if s == null:
		return true

	# 1. os 169 bancos de sala entraram no re3_se.json?
	var n_sala := 0
	var ids_por_sala: Dictionary = {}            ## id -> nº de salas que o definem
	for nome: String in s.acoes():
		break
	var dados: Variant = AssetIO.json(Sfx.DADOS)
	if dados is Dictionary:
		var bancos: Dictionary = (dados as Dictionary).get("bancos", {})
		for nome: String in bancos:
			if not (nome.begins_with("R") and nome != "R000"):
				continue
			n_sala += 1
			for k: String in ((bancos[nome] as Dictionary).get("se", {}) as Dictionary):
				var e: Dictionary = ((bancos[nome] as Dictionary)["se"] as Dictionary)[k]
				if e.has("banco_externo") or e.has("invalido") or bool(e.get("dummy", false)):
					continue
				ids_por_sala[int(k)] = int(ids_por_sala.get(int(k), 0)) + 1
	print("bancos de SALA no re3_se.json: %d (esperado 169)" % n_sala)

	# 2. o gancho: quem troca a BGM da sala também troca o banco de SFX
	if a != null:
		a.banco_de_sfx_da_sala("R10D")
		print("Audio.banco_de_sfx_da_sala('R10D') -> Sfx.banco_sala()='%s'" % s.banco_sala())

	# 3. cada pedido, em cada sala de amostragem
	for sala: String in SALAS:
		print("\n=== banco de sala = %s ===" % sala)
		if not s.definir_banco_sala(sala):
			print("  (banco ausente — rode `NOSTALGIA_OUT=port python tools/exe_audio.py --salas`)")
			continue
		for p: Array in PEDIDOS:
			var nome: String = p[0]
			var id_se: int = p[1]
			var rel := _wav_de(dados, sala, id_se)
			var abs_path := AssetIO.path("SOUND/SFX/%s" % rel) if rel != "" else ""
			var existe := rel != "" and FileAccess.file_exists(abs_path)
			var st: AudioStreamWAV = AudioStreamWAV.load_from_file(abs_path) if existe else null
			var tocou := s.se_de_sala(id_se)
			print("  %-24s id %2d  wav=%-20s existe=%s stream=%s %6.3fs %5dHz tocou=%s (%s)" % [
				nome, id_se, rel if rel != "" else "(sem descritor)", existe, st != null,
				st.get_length() if st != null else 0.0, st.mix_rate if st != null else 0,
				tocou, p[2]])

	# 4. quantas das 169 salas definem cada id (o resto é mudo TAMBÉM no original)
	print("\n=== quantas salas definem cada id de cat 2 (com amostra real) ===")
	var linha := ""
	for id_se in 48:
		linha += "%2d:%-4d" % [id_se, int(ids_por_sala.get(id_se, 0))]
		if id_se % 8 == 7:
			print("  " + linha)
			linha = ""

	# 5. a árvore de decisão da porta (0x80050d28), nas portas reais do SCD
	print("\n=== porta_usada() nas portas trancadas do jogo ===")
	var portas: Variant = AssetIO.json("porta_banco.json")
	if portas is Dictionary:
		var por_desfecho: Dictionary = {}
		var mudas: Array[String] = []
		for sala: String in ((portas as Dictionary).get("salas", {}) as Dictionary):
			for pv: Variant in ((portas as Dictionary)["salas"] as Dictionary)[sala]:
				var pd: Dictionary = pv
				if (int(pd.get("key_id", 0)) & 0x80) == 0:
					continue
				s.definir_banco_sala(sala)
				var r := s.porta_usada(sala, int(pd.get("aot", -1)))
				var chave := "%d" % r
				por_desfecho[chave] = int(por_desfecho.get(chave, 0)) + 1
				## Qual id o ramo pediu (não dá para inferir por `ultimo_tocado`: dois pedidos
				## seguidos da MESMA amostra não mudam o campo).
				var kt := int(pd.get("key_type", 0))
				var knock := int(pd.get("knock", 0))
				var id_esperado := Sfx.SE_PORTA_TRANCADA
				if kt == 0xFE:
					id_esperado = Sfx.SE_PORTA_EMPERRADA
				elif kt != 0xFF and knock != 0:
					id_esperado = Sfx.SE_PORTA_TRANCADA_KNOCK
				if r != Sfx.Porta.LIVRE and _wav_de(dados, sala, id_esperado) == "":
					mudas.append("%s/aot%d(id %d)" % [sala, int(pd.get("aot", -1)), id_esperado])
		print("  desfechos (0=LIVRE 1=DESTRANCOU 2=TRANCADA 3=EMPERRADA 4=NUNCA_ABRE): ",
			por_desfecho)
		print("  portas trancadas cujo banco de sala NÃO tem a amostra (%d): %s"
			% [mudas.size(), str(mudas.slice(0, 10))])
	return true


func _wav_de(dados: Variant, sala: String, id_se: int) -> String:
	if not (dados is Dictionary):
		return ""
	var b: Variant = ((dados as Dictionary).get("bancos", {}) as Dictionary).get(sala)
	if not (b is Dictionary):
		return ""
	var e: Variant = ((b as Dictionary).get("se", {}) as Dictionary).get(str(id_se))
	if not (e is Dictionary):
		return ""
	var rel: Variant = (e as Dictionary).get("wav")
	return rel as String if rel is String else ""
