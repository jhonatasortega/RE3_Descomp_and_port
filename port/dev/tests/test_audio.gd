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

	# ── 1. os 35 bancos do disco entraram ──
	var bancos: Dictionary = d.get("bancos", {})
	t.eq(bancos.size(), 35, "35 bancos VAB (20 A_, 14 C_, R000) na tabela de SE")

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
	for nome: String in bancos:
		var b: Dictionary = bancos[nome]
		var n_tons := int(b.get("n_tons", 0))
		var se: Dictionary = b.get("se", {})
		for k: String in se:
			var info: Dictionary = se[k]
			n_desc += 1
			if int(info.get("tom", -1)) >= n_tons:
				fora += 1
			if not bool(info.get("dummy", false)) and str(info.get("wav", "")) == "":
				sem_wav += 1
	t.eq(n_desc, 278, "278 descritores de SE usados nos 35 bancos")
	t.eq(fora, 0, "nenhum descritor aponta tom fora do banco (byte1>>4 < n_tons)")
	t.eq(sem_wav, 0, "todo SE não-mudo resolve um WAV")

	# ── 6. API do Sfx ──
	t.group("Audio/Sfx API")
	var s := Sfx.new()
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
		# O vínculo real é BGM_ID -> sala e NÃO foi medido: nenhum opcode do SCD toca BGM
		# (varredura dos 144 handlers de 0x8009e0f8 não achou set-bgm). Enquanto isso o
		# mapa é por STAGE e está DECLARADO como provisório — o teste garante que a
		# ressalva continue no arquivo, para ninguém tratar isso como medido.
		var meta: Dictionary = m.get("_meta", {})
		t.check(str(meta.get("TODO", "")).contains("PROVISOR"),
			"bgm_map.json mantém a ressalva de que área->faixa é PROVISÓRIO (não medido)")
		t.check((m.get("room_override", {}) as Dictionary).is_empty(),
			"room_override segue vazio (o de-para sala->faixa não foi medido)")

		var a2 := Audio.new()
		var faixa := a2.faixa_para_sala("R100")
		t.eq(faixa, str(area.get("UPTOWN", "")),
			"R100 (stage 1) cai na faixa de UPTOWN pelo fallback por stage")
		a2.free()

	s.free()
	return true
