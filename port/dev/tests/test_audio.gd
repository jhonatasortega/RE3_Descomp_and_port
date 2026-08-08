extends RefCounted
## Som do jogo: de-para PROVADO id de SE -> amostra, e a trilha por sala.
##
## O que este teste defende: **nenhum som do port é escolhido "de ouvido por heurística"**.
## O alvo de cada ação nomeada sai da tabela de SE que mora no início do `.VH`/`.SND` do
## disco, decodificada por `tools/exe_audio.py`. Antes desta rodada o `sfx_map.json` vinha
## de heurística de duração e estava **errado** (`menu_move` apontava `C_00_01`, que é o
## som do id 9 = abrir; o de mover cursor é o `C_00_02`).
##
## Cadeia provada no `SLUS_009.23` (base 0x80010000), ver `docs/decomp/notes/exe_audio.md`:
##   `0x800746c0` SE_pede(a0 = (b2<<16)|(cat<<8)|idx)  -> anel `0x800e0de4`
##   `0x800744e0` consumidor -> tabela `0x800a1130` -> `0x80074770` (cat<5)
##   `0x80074770` desc = *( *(0x800e0610 + cat*4) + idx*4 );  -1 = descarta
##   `0x800749a0` aloca voz -> `0x80075b90` vol/pan (div 63) -> `0x8007eda8` SpuSetKey
##
## Rodar só este arquivo:
##   godot --headless --path port --script res://dev/run_tests.gd -- audio

const SFX_DIR := "SOUND/SFX"

## De-para dos 5 sons de menu, banco `C_00`. Confiança ALTA.
## id -> [índice do tom no banco, vag, wav]
const MENU_ESPERADO := {
	4: [5, 4, "C_00/C_00_02.wav"],      # mover cursor   (11 call sites de 0x800746c0)
	5: [6, 5, "C_00/C_00_03.wav"],      # cancelar/voltar (20 call sites — o mais usado)
	6: [7, 6, "C_00/C_00_04.wav"],      # confirmar      (13 call sites, ex. 0x80023d10)
	7: [8, 2, "C_00/C_00_00.wav"],      # inválido       (5 call sites)
	9: [12, 3, "C_00/C_00_01.wav"],     # abrir menu     (5 call sites, ex. 0x80023db8)
}


func run(t: Object) -> bool:
	t.group("Audio/SE")

	var dados: Variant = AssetIO.json("re3_se.json")
	if not t.check(dados is Dictionary, "data/re3_se.json existe "
			+ "(gere com `NOSTALGIA_OUT=port python tools/exe_audio.py`)"):
		return true
	var d: Dictionary = dados

	# ── 1. os bancos entraram: 35 do disco + 76 de porta ──
	var bancos: Dictionary = d.get("bancos", {})
	t.eq(bancos.size(), 111, "111 bancos: 35 do disco (20 A_, 14 C_, R000) + 76 de porta")
	var n_porta := 0
	for nome: String in bancos:
		if nome.contains("_DOOR"):
			n_porta += 1
	t.eq(n_porta, 76, "76 bancos de porta (todo STAGE*/DOORxx.DO1 embute um banco VAB)")

	# ── 2. formato do banco: tabela de SE = hdr/4 (magic 0x0001eeee em hdr+0x10) ──
	t.eq(int((bancos.get("C_00", {}) as Dictionary).get("n_se", -1)), 16,
		"C_00: 16 ids de SE (header VAB em 0x40 -> tabela de 0x40/4 entradas)")
	t.eq(int((bancos.get("A_01", {}) as Dictionary).get("n_se", -1)), 32,
		"A_01: 32 ids de SE (header VAB em 0x80)")
	t.eq(int((bancos.get("R000", {}) as Dictionary).get("n_se", -1)), 48,
		"R000.SND: 48 ids de SE (header VAB em 0xc0)")

	# `cat` do pedido == id de banco VAB (a mesma fn 0x800750e4 busca os dois)
	t.eq(int((bancos.get("C_00", {}) as Dictionary).get("banco", -1)), 0,
		"C_xx = banco 0 (jogador/UI/global) — descritor byte0 bits1-3")
	t.eq(int((bancos.get("A_01", {}) as Dictionary).get("banco", -1)), 1,
		"A_xx = banco 1 (área)")
	t.eq(int((bancos.get("R000", {}) as Dictionary).get("banco", -1)), 2,
		"R000.SND = banco 2 (sala)")

	# `.VB` de C_00 tem 206480 B e 9 VAGs (tabela VAG do .VH, ver sfx.md §3.2)
	t.eq(int((bancos.get("C_00", {}) as Dictionary).get("vb_bytes", -1)), 206480,
		"C_00.VB = 206480 B (= hdr+0x00 do header VAB)")
	t.eq(int((bancos.get("C_00", {}) as Dictionary).get("n_vags", -1)), 9,
		"C_00: 9 VAGs (o VAG#1 é o bloco mudo do SPU e não gera WAV)")
	t.eq(int((bancos.get("C_00", {}) as Dictionary).get("n_tons", -1)), 14,
		"C_00: 14 tons VagAtr (= hdr+0x14)")

	# ── 3. o de-para id -> tom -> vag -> WAV dos 5 sons de menu ──
	var se_c00: Dictionary = (bancos.get("C_00", {}) as Dictionary).get("se", {})
	for id_se: int in MENU_ESPERADO:
		var esp: Array = MENU_ESPERADO[id_se]
		var e: Variant = se_c00.get(str(id_se))
		if not t.check(e is Dictionary, "C_00 define o id de SE %d" % id_se):
			continue
		var info: Dictionary = e
		t.eq(int(info.get("tom", -1)), int(esp[0]),
			"C_00 id %d -> tom %d (descritor byte1>>4, lido em 0x80074cd0)" % [id_se, esp[0]])
		t.eq(int(info.get("vag", -1)), int(esp[1]),
			"C_00 id %d -> vag %d (VagAtr+0x16)" % [id_se, esp[1]])
		t.eq(str(info.get("wav", "")), str(esp[2]),
			"C_00 id %d -> %s (vag k => <banco>_{k-2}.wav)" % [id_se, esp[2]])

	# os 5 sons de UI são amostras DISTINTAS (critério de aceite do de-para)
	var wavs_menu: Dictionary = {}
	for id_se: int in MENU_ESPERADO:
		wavs_menu[str((MENU_ESPERADO[id_se] as Array)[2])] = true
	t.eq(wavs_menu.size(), 5, "os 5 sons de menu são 5 amostras DIFERENTES")

	# cruzamento independente: são exatamente os WAV 00..04 de C_00 — as MESMAS 5 amostras
	# que sfx.md §9.1 achou byte-idênticas nos 13 bancos C_ ("núcleo global do jogador").
	var esperados_00_04: Array[String] = []
	for i in 5:
		esperados_00_04.append("C_00/C_00_%02d.wav" % i)
	var achados: Array = wavs_menu.keys()
	achados.sort()
	t.eq(achados, esperados_00_04,
		"os 5 sons de UI são os WAV 00..04 de C_00 (bate com o 'núcleo global' de sfx.md §9.1)")

	# ── 4. o id de UI é o MESMO em 13 dos 14 bancos C_ (C_0C é a exceção medida) ──
	var iguais := 0
	var c0c_difere := false
	for nome: String in bancos:
		if not nome.begins_with("C_"):
			continue
		var se: Dictionary = (bancos[nome] as Dictionary).get("se", {})
		var e4: Variant = se.get("4")
		if e4 is Dictionary and str((e4 as Dictionary).get("desc", "")) == "0x3fe05300":
			iguais += 1
		elif nome == "C_0C":
			c0c_difere = true
	t.eq(iguais, 13, "id 4 (mover cursor) tem o mesmo descritor 0x3fe05300 em 13 bancos C_")
	t.check(c0c_difere, "C_0C é a única exceção: não define o id 4 (medido, não suposto)")

	# ── 5. todo descritor aponta um tom que existe (278/278 no verificador do tool) ──
	var n_desc := 0
	var fora := 0
	var sem_wav := 0
	var n_desc_porta := 0
	var inval_porta := 0
	for nome: String in bancos:
		var b: Dictionary = bancos[nome]
		var n_tons := int(b.get("n_tons", 0))
		var se: Dictionary = b.get("se", {})
		var eh_porta := nome.contains("_DOOR")
		for k: String in se:
			var info: Dictionary = se[k]
			if eh_porta:
				n_desc_porta += 1
				if info.has("invalido"):
					inval_porta += 1
				continue
			n_desc += 1
			if int(info.get("tom", -1)) >= n_tons:
				fora += 1
			if not bool(info.get("dummy", false)) and str(info.get("wav", "")) == "":
				sem_wav += 1
	t.eq(n_desc, 278, "278 descritores de SE usados nos 35 bancos do disco")
	t.eq(fora, 0, "nenhum descritor aponta tom fora do banco (byte1>>4 < n_tons)")
	t.eq(sem_wav, 0, "todo SE não-mudo resolve um WAV")

	# ── 5b. bancos de porta (cat 4) ──
	t.group("Audio/porta")
	t.eq(n_desc_porta, 159, "159 descritores nos 76 bancos de porta")
	# a tabela de SE das portas é um TEMPLATE: os ids 0/1 são byte-idênticos nas 76, mas 12
	# portas só têm 2 tons — aí o id 1 fica pendurado. Inconsistência do dado ORIGINAL.
	t.eq(inval_porta, 12,
		"12 descritores de porta apontam tom fora do próprio banco (sobra do template)")
	var d00: Dictionary = bancos.get("S1_DOOR00", {})
	t.eq(int(d00.get("banco", -1)), 4, "banco de porta = cat 4 (descritor byte0 bits1-3)")
	t.eq(int(d00.get("n_se", -1)), 4, "banco de porta tem 4 ids de SE (tabela em 0x00..0x0f)")
	t.eq(int(d00.get("vb_bytes", -1)), 16688,
		"S1_DOOR00: corpo PS-ADPCM de 16688 B embutido (hdr+0x00), começa em hdr+total")
	var se_d00: Dictionary = d00.get("se", {})
	t.eq(str((se_d00.get("0", {}) as Dictionary).get("desc", "")), "0x00601408",
		"id 0 do banco de porta = 0x00601408 (idêntico nas 76 portas)")
	t.eq(str((se_d00.get("1", {}) as Dictionary).get("desc", "")), "0x00612408",
		"id 1 do banco de porta = 0x00612408 (idêntico nas 76 portas)")

	# ── 6. API do Sfx ──
	t.group("Audio/Sfx API")
	var s := Sfx.new()
	## O pool de `AudioStreamPlayer` só toca DENTRO da árvore ("Playback can only happen when a
	## node is inside the scene tree"); sem isto os testes que chamam `tiro()`/`tocar_acao()`
	## enchiam o log de erro do motor mesmo passando.
	var laco := Engine.get_main_loop() as SceneTree
	if laco != null:
		laco.root.add_child(s)
	t.check(s.carregar(), "Sfx.carregar() lê data/re3_se.json")
	t.check(s.pronto(), "Sfx pronto")

	t.eq(s.acao_id("menu_mover"), 4, "menu_mover = SE id 4")
	t.eq(s.acao_id("menu_cancelar"), 5, "menu_cancelar = SE id 5")
	t.eq(s.acao_id("menu_confirmar"), 6, "menu_confirmar = SE id 6")
	t.eq(s.acao_id("menu_invalido"), 7, "menu_invalido = SE id 7")
	t.eq(s.acao_id("menu_abrir"), 9, "menu_abrir = SE id 9")
	t.eq(s.acao_id("tiro"), 11, "tiro = SE id 11 (0x8003ad6c: lui a0,1; ori a0,a0,0xb)")
	t.eq(s.acao_cat("menu_mover"), 0, "som de menu vem do banco 0 (C_xx)")
	t.eq(s.acao_id("nao_existe"), -1, "ação inexistente devolve -1")

	# honestidade em runtime: só os 5 de menu são ALTA
	for a: String in Sfx.ACOES_MENU:
		t.check(s.acao_confiavel(a), "%s tem confiança ALTA (de-para provado)" % a)
	t.check(not s.acao_confiavel("tiro"),
		"tiro NÃO é marcado confiável (nome DECLARADO, call site provado)")

	t.eq(s.acao_wav("menu_mover"), "C_00/C_00_02.wav", "menu_mover -> C_00_02.wav")

	# resolução crua por (cat, id), como o original
	t.eq(s.tocar_id(0, 1023), false, "id de SE inexistente não toca (0x80074770 descarta -1)")
	t.eq(s.tocar_id(9, 4), false, "cat sem banco carregado não toca")

	# banco de área: o MESMO id toca amostra diferente por banco (indireção do original)
	s.definir_banco_area("C_05")
	t.eq(s.banco_area(), "C_05", "definir_banco_area aceita um banco que existe")
	s.definir_banco_area("NAO_EXISTE")
	t.eq(s.banco_area(), "", "definir_banco_area ignora banco inexistente")

	# porta: cada DOORxx.DO1 tem o próprio som (madeira != portão de metal)
	# id 1, não 0: o único `jal 0x800746c0` da região de porta é `0x800161c4` com `a0 = 0x401`.
	t.eq(s.acao_id("porta_abrir"), 1, "porta_abrir = SE id 1 do banco de porta (0x800161c4)")
	t.eq(s.acao_cat("porta_abrir"), 4, "porta vem do cat 4 (banco embutido no .DO1)")
	t.check(not s.acao_confiavel("porta_abrir"),
		"porta_abrir NÃO é ALTA (qual id é abrir vs fechar não foi medido)")
	s.definir_banco_porta("S1_DOOR03")
	t.eq(s.banco_porta(), "S1_DOOR03", "definir_banco_porta aceita porta existente")
	s.definir_banco_porta("S9_DOOR99")
	t.eq(s.banco_porta(), "", "definir_banco_porta ignora porta inexistente")

	# ── 6.1 TIRO: o estouro é `cat 1 / id 0` do banco A_{w} da arma ──
	# Prova 1: a tabela de 20 funções POR ARMA `0x8009ced8` (indexada por `w-1`, ver
	# `0x8003ea1c`) pede `cat 1 / id 0` em cada entrada, logo depois do hitscan `0x80044804`.
	# Prova 2: `A_01` (w=1, a FACA) é o ÚNICO dos 20 bancos `A_` que não define o id 0.
	t.group("Audio/tiro")
	var com_id0: Array[String] = []
	var sem_id0: Array[String] = []
	for i in range(1, 21):
		var nome := Sfx.NOME_BANCO_ARMA % i
		var info := s.banco_info(nome)
		if info.is_empty():
			continue
		var tab: Dictionary = info.get("se", {})
		if tab.has("0"):
			com_id0.append(nome)
		else:
			sem_id0.append(nome)
	t.eq(com_id0.size() + sem_id0.size(), 20, "os 20 bancos de arma A_01..A_14 estão no JSON")
	t.eq(sem_id0, ["A_01"] as Array[String],
		"A_01 (w=1, a FACA) é o único banco de arma sem o id 0 — 19/20 definem o estouro")

	s.definir_banco_arma(Sfx.ARMA_PADRAO)
	t.eq(s.banco_arma(), "A_02", "definir_banco_arma(2) -> A_02 (fileid 0xda + 2*2 = 0xde)")
	var wav_tiro := str((s.banco_info("A_02").get("se", {}) as Dictionary).get("0", {}).get("wav", ""))
	t.check(AssetIO.exists("%s/%s" % [SFX_DIR, wav_tiro]),
		"a amostra do tiro (%s) está no disco" % wav_tiro)
	t.check(s.tiro(), "Sfx.tiro() toca com o banco de arma carregado")
	t.eq(s.ultimo_tocado(), wav_tiro, "o tiro sai do banco da ARMA, não do C_ de personagem")

	s.definir_banco_arma(Sfx.ARMA_FACA)
	t.eq(s.banco_arma(), "A_01", "definir_banco_arma(1) -> A_01 (faca)")
	t.check(s.tiro(), "com a faca (A_01, sem id 0) o tiro cai no fallback cat 0 / id 11")
	s.definir_banco_arma(0)
	t.eq(s.banco_arma(), "", "w = 0 não é banco de arma (o fid 0xda não é um .VH de A_)")

	# ── 7. os WAV existem em disco e carregam ──
	t.group("Audio/assets")
	var faltando: Array[String] = []
	for a: String in Sfx.ACOES_MENU:
		var rel := s.acao_wav(a)
		if rel == "" or not AssetIO.exists("%s/%s" % [SFX_DIR, rel]):
			faltando.append("%s(%s)" % [a, rel])
	t.eq(faltando, [] as Array[String],
		"os 5 WAV de menu existem em assets/SOUND/SFX (rode tools/re3_sfx.py)")

	if faltando.is_empty():
		var caminho := AssetIO.path("%s/%s" % [SFX_DIR, s.acao_wav("menu_confirmar")])
		var w := AudioStreamWAV.load_from_file(caminho)
		t.check(w != null, "AudioStreamWAV.load_from_file carrega o WAV de confirmar")
		if w != null:
			t.check(w.get_length() > 0.0, "o WAV de confirmar não é vazio (%.3f s)"
				% w.get_length())
			# taxa vem do TOM, não é fixa: tom 7 de C_00 tem center=84 shift=57 key=66
			# -> 44100 * 2^((66 - 84 - 57/128)/12) = 15196 Hz (sfx.md §4)
			t.eq(w.mix_rate, 15196,
				"C_00_04 a 15196 Hz (tom 7: center=84 shift=57 key=66)")

	# ── 8. trilha (BGM): mapa por sala ──
	t.group("Audio/BGM")
	var bgm: Variant = AssetIO.json("bgm_map.json")
	if t.check(bgm is Dictionary, "data/bgm_map.json existe"):
		var m: Dictionary = bgm
		var area: Dictionary = m.get("area_default", {})
		t.eq(area.size(), 7, "7 áreas no mapa área->faixa")
		# `area_default` (por STAGE) segue PROVISÓRIO — é só o FALLBACK. O teste garante que a
		# ressalva continue no arquivo, para ninguém tratar o fallback como medido.
		var meta: Dictionary = m.get("_meta", {})
		t.check(str(meta.get("TODO", "")).contains("PROVISOR"),
			"bgm_map.json mantém a ressalva de que área->faixa é PROVISÓRIO (é só fallback)")
		# O que é MEDIDO: sala -> NOME da BGM do PS1, byte-exato (sha1 dos 676 blocos de
		# SEQ dos 169 ARD × os nomes do Rofs7.dat do PC). Vive no bloco `salas`.
		var salas: Dictionary = m.get("salas", {})
		t.eq(salas.size(), 169, "o mapa cobre as 169 salas (bloco `salas`)")
		t.check(str(meta.get("PROVA", "")).contains("676/676"),
			"bgm_map.json guarda a prova byte-exata (676/676 blocos)")

		var a2 := Audio.new()
		# Três salas conhecidas, todas `conf: ALTA` (erro de duração < 0,5 %):
		#   R100 = a rua da abertura · R10F = sala de save (tema de save) · R200 = Downtown
		t.eq(a2.faixa_para_sala("R100"), "main07", "R100 -> main07 (medido, ALTA)")
		t.eq(a2.faixa_para_sala("R10F"), "main32",
			"R10F -> main32, o MESMO da chave `context.SAVE` (sala de save)")
		t.eq(a2.faixa_para_sala("R200"), "main01", "R200 -> main01 (medido, ALTA)")
		t.eq(str(a2.faixa_info("R100").get("conf", "")), "ALTA", "R100 tem confiança ALTA")
		# Cobertura: NENHUMA das 169 salas pode ficar muda, e a faixa escolhida tem de EXISTIR
		# no disco. Era aqui que o PARK falhava: `area_default` manda `main2a`, e o PC só tem a
		# faixa partida (`main2a_0`/`_1`) — sem a resolução de multiparte o parque era mudo.
		var mudas: Array[String] = []
		var por_fonte: Dictionary = {}
		for sala: String in salas:
			var info := a2.faixa_info(sala)
			var f := str(info.get("faixa", ""))
			if f == "" or not AssetIO.exists("%s/%s.ogg" % [Audio.BGM_DIR, f]):
				mudas.append(sala)
			var fo := str(info.get("fonte", ""))
			por_fonte[fo] = int(por_fonte.get(fo, 0)) + 1
		t.eq(mudas.size(), 0, "as 169 salas têm faixa e o .ogg dela existe (mudas: %s)"
			% str(mudas.slice(0, 6)))
		t.eq(int(por_fonte.get("area_provisoria", 0)) + int(por_fonte.get("default", 0)), 18,
			"só 18 salas ainda caem no fallback por STAGE (14 sem WAV no PC + 4 sem bloco MAIN)")
		t.check(a2.faixa_para_sala("R400").begins_with("main2a"),
			"R400 (PARK) resolve a faixa multiparte main2a_0 em vez de ficar muda")
		a2.free()

	if s.get_parent() != null:
		s.get_parent().remove_child(s)
	s.free()
	return true
