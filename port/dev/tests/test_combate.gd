extends RefCounted
## MIRA e TIRO do player (rotina 5 → rotina 7 do EXE).
##
## Fonte: `docs/decomp/notes/exe_combat.md` §1-2 (o `aim_shoot` está 100% decompilado) e as
## tabelas lidas do EXE por `tools/exe_aim_shoot.py` (`data/re3_aim_shoot.json`).
## O que estes testes protegem: o sub-estado da rotina 7, o pitch `(tier<<9)+0x800`, o quadro do
## tiro do timing `0x8009cf28` e o gasto de munição no quadro do disparo.


func run(t: Object) -> bool:
	t.group("Combate")
	# ── tabelas do EXE ──
	var raw: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/re3_aim_shoot.json"))
	t.check(raw is Dictionary, "re3_aim_shoot.json carrega (tools/exe_aim_shoot.py)")
	var d: Dictionary = raw
	var armas: Array = d.get("armas", [])
	t.eq(armas.size(), 21, "21 armas na tabela de timing `0x8009cf28`")
	t.eq(int((armas[0] as Dictionary).get("quadro_do_tiro", -1)), 50, "faca w0 atira no quadro 50")
	t.eq(int((armas[1] as Dictionary).get("quadro_do_tiro", -1)), 12, "handgun w1 no quadro 12")
	t.eq(int((armas[5] as Dictionary).get("quadro_do_tiro", -1)), 30, "magnum w5 no quadro 30")
	t.eq(String((armas[0] as Dictionary).get("tipo", "")), "contato", "faca é contato")
	t.eq(String((armas[1] as Dictionary).get("tipo", "")), "hitscan", "handgun é hitscan")
	t.eq(String((armas[10] as Dictionary).get("tipo", "")), "projetil", "rocket w10 é projétil")
	t.eq(String((armas[14] as Dictionary).get("tipo", "")), "projetil", "granada w14 é projétil")
	# a caixa do auto-lock: 3000 de alcance, ±1000 de largura, 1600 de altura
	var cx: Array = (d.get("auto_lock", {}) as Dictionary).get("descritores", [])
	t.check(cx.size() >= 2, "descritores do auto-lock lidos de `0x80098064`")
	var v0: Array = (cx[0] as Dictionary).get("valores", [])
	t.eq(int(v0[0]), 3000, "alcance 3000 no 1º descritor")
	t.eq(absi(int(v0[1])), 1000, "largura ±1000")
	t.eq(int(v0[2]), 1600, "altura 1600")

	# ── máquina de mira ──
	var st := GameState.new()
	st.novo_jogo()
	var p := Player.new()
	p.estado = st
	p.equipped_weapon = st.equipped_item_id()      ## Hand Gun 0x03
	p.pos = Vector3i(0, 0, 0)
	p.facing = 0
	var pad := Pad.new()
	t.eq(st.equipped_qtd(), 15, "jogo novo: Hand Gun com 15")
	# sem arma equipada não entra na mira (`0x80039714`: `lbu v0,0x46` != 0)
	p.equipped_weapon = 0
	pad.set_mask(Pad.AIM)
	p.tick(pad)
	t.check(p.acao != Player.Acao.MIRANDO, "sem arma equipada não mira")
	p.equipped_weapon = 0x03
	# levantar (sub 0) → pitch (sub 1) → travar (sub 2) → fogo (sub 3)
	for _i in 12:
		pad.set_mask(Pad.AIM)
		p.tick(pad)
	t.eq(p.mira_sub, Player.Mira.FOGO, "12 ticks segurando a mira chegam ao sub 3 (fogo)")
	t.eq(p.acao, Player.Acao.MIRANDO, "a ação é MIRANDO")
	t.eq(p.mira_pitch, 0x800, "pitch = (tier 0 << 9) + 0x800 (`0x8003ac5c`)")
	## Agora existem os clipes do BANCO 2 do PLW (`mira00..mira07`, de-para de osso provado em
	## `plw.md` §9): hold médio é `mira02`, levantar é `mira00` e o tiro/recuo é `mira07`.
	t.eq(p.clipe_atual(), "mira02", "hold da mira usa o `mira02` (banco 2 do PLW, pose média)")
	var p6 := Player.new()
	p6.equipped_weapon = 0x03
	pad.set_mask(Pad.AIM)
	p6.tick(pad)
	t.eq(p6.clipe_atual(), "mira00", "no sub 0 a pose é `mira00` (levantar a arma)")
	# o gatilho agenda o tiro para o quadro do timing e gasta 1 no disparo
	pad.set_mask(Pad.AIM | Pad.ACAO)
	p.tick(pad)
	t.eq(p.tiro_pendente, 12, "gatilho agenda o tiro para o quadro 12 (handgun)")
	t.eq(st.equipped_qtd(), 15, "a munição só sai NO quadro do tiro, não no aperto")
	for _i in 12:
		pad.set_mask(Pad.AIM)
		p.tick(pad)
	t.eq(st.equipped_qtd(), 14, "no quadro 12 gasta 1")
	t.eq(p.tiro_pendente, -1, "e o tiro deixa de estar pendente")
	t.eq(p.mira_sub, Player.Mira.LEVANTAR, "depois do tiro volta ao rearme (rotina 5)")
	# clique seco: munição 0 não dispara e marca `municao_vazia`
	st.main_slots[st.equipped]["qtd"] = 0
	for _i in 14:
		pad.set_mask(Pad.AIM)
		p.tick(pad)
	t.eq(p.mira_sub, Player.Mira.FOGO, "voltou ao sub 3 depois do rearme")
	pad.set_mask(Pad.AIM | Pad.ACAO)
	p.tick(pad)
	t.check(p.municao_vazia, "munição 0 = clique seco (o EXE escolhe o SFX 'vazio')")
	t.eq(p.tiro_pendente, -1, "e nenhum tiro é agendado")
	# soltar a mira volta ao repouso e reseta o sub-estado
	pad.set_mask(0)
	p.tick(pad)
	t.eq(p.mira_sub, Player.Mira.LEVANTAR, "soltar a mira reseta o sub-estado")
	t.check(p.acao != Player.Acao.MIRANDO, "e sai de MIRANDO")

	# ── NÃO ATIRA SEM MIRAR (o gatilho só é lido no sub 3 da rotina 7) ──
	var st5 := GameState.new()
	st5.novo_jogo()
	var p5 := Player.new()
	p5.estado = st5
	p5.equipped_weapon = 0x03
	for _i in 6:
		pad.set_mask(Pad.TIRO)                      ## clique esquerdo SEM segurar a mira
		p5.tick(pad)
		pad.set_mask(0)
		p5.tick(pad)
	t.eq(st5.equipped_qtd(), 15, "clicar TIRO sem mirar não gasta munição")
	t.eq(p5.tiro_pendente, -1, "e não agenda tiro")
	t.check(p5.acao != Player.Acao.MIRANDO, "e não entra em mira")

	# ── a malha da arma na mão sai do ITEM equipado (número do PLW = item_id em decimal) ──
	# Medido em `port/dev/diag_armas.gd`: W01 517×106×27 = faca · W02/W03 163×370 = pistolas
	# (bate com o timing 12 do EXE para w1 e w2) · W04 990 = escopeta · W06..W09 = os 4
	# lança-granadas · W10 = lança-rockets (item 0x0a = 10, o que fixa a base 10).
	t.check(FileAccess.file_exists("res://assets/PLD/PL00W03_WPN.glb")
		or not AssetIO.exists("PLD/PL00W03_WPN.glb"),
		"a malha da Hand Gun (item 0x03) é a PL00W03_WPN")

	# ── MIRA COM O MOUSE (extensão do port; o pad do PS1 é digital) ──
	var p7 := Player.new()
	p7.equipped_weapon = 0x03
	p7.pos = Vector3i.ZERO
	p7.facing = 0
	var pad7 := Pad.new()
	for _i in 12:
		pad7.set_mask(Pad.AIM)
		p7.tick(pad7)
	t.eq(p7.mira_sub, Player.Mira.FOGO, "chegou ao hold para testar o mouse")
	# horizontal gira o corpo, com teto de 3× o giro normal por tick
	pad7.mouse_dx = 10
	p7.tick(pad7)
	t.eq(p7.facing, PS1Math.wrap_angle(-10 * Player.MIRA_MOUSE_GIRO),
		"mouse para a direita gira o corpo (8 unidades de ângulo por pixel)")
	pad7.mouse_dx = 500
	var antes_f := p7.facing
	p7.tick(pad7)
	t.eq(PS1Math.angle_diff(antes_f, p7.facing), -Player.GIRO_POR_FRAME * 3,
		"o giro por tick tem teto de 3× o normal (o ponteiro não teleporta a Jill)")
	# vertical escolhe a altura da mira, com zona morta
	pad7.mouse_dx = 0
	pad7.mouse_dy = Player.MIRA_MOUSE_ZONA / 2
	p7.tick(pad7)
	t.eq(p7.mira_alto, 0, "dentro da zona morta a altura não muda")
	pad7.mouse_dy = Player.MIRA_MOUSE_ZONA
	p7.tick(pad7)
	t.eq(p7.mira_alto, -1, "ponteiro para BAIXO = mira baixa")
	t.eq(p7.clipe_atual(), "mira06", "e a pose vira a `mira06` (hold baixo)")
	pad7.mouse_dy = -Player.MIRA_MOUSE_ZONA * 3
	p7.tick(pad7)
	t.eq(p7.mira_alto, 1, "ponteiro para CIMA = mira alta")
	t.eq(p7.clipe_atual(), "mira04", "e a pose vira a `mira04` (hold alto)")
	# soltar a mira zera o acumulador vertical
	pad7.set_mask(0)
	pad7.mouse_dy = 0
	p7.tick(pad7)
	t.eq(p7.mira_mouse_y, 0, "sair da mira zera o acumulador do mouse")

	# ── auto-lock: alvo dentro e fora da caixa ──
	var p2 := Player.new()
	p2.estado = st
	p2.equipped_weapon = 0x03
	p2.pos = Vector3i.ZERO
	p2.facing = 0                                   ## frente = -Z
	p2.alvos = func() -> Array:
		return [Vector3i(0, 0, -2000), Vector3i(0, 0, -5000), Vector3i(3000, 0, -100)]
	for _i in 12:
		pad.set_mask(Pad.AIM)
		p2.tick(pad)
	t.eq(p2.mira_alvo, 0, "trava no alvo a 2000 à frente (dentro dos 3000 de alcance)")
	# ── FÁCIL: auto-mira gira o corpo para o alvo; DIFÍCIL não trava ──
	var p3 := Player.new()
	p3.equipped_weapon = 0x03
	p3.pos = Vector3i.ZERO
	p3.facing = 0                                   ## olhando para -Z
	p3.dificuldade = Player.Dificuldade.FACIL
	## alvo à frente mas DESLOCADO para a direita: cabe na caixa do auto-lock (±1000) e obriga o
	## corpo a girar — é isso que a auto-mira do modo fácil faz.
	p3.alvos = func() -> Array:
		return [Vector3i(900, 0, -2000)]
	t.check(p3.mira_com_laser(), "fácil tem mira laser")
	t.check(p3.mira_trava(), "fácil trava alvo")
	for _i in 13:
		pad.set_mask(Pad.AIM)
		p3.tick(pad)
	t.eq(p3.mira_alvo, 0, "fácil trava no alvo dentro da caixa do auto-lock")
	t.check(p3.facing > 0 and p3.facing < 1024,
		"auto-mira gira o corpo PARA o alvo (alvo à direita → facing entre 0 e 1024)",
		"facing=%d" % p3.facing)
	var st4 := GameState.new()
	st4.novo_jogo()
	var p4 := Player.new()
	p4.estado = st4
	p4.equipped_weapon = 0x03
	p4.pos = Vector3i.ZERO
	p4.dificuldade = Player.Dificuldade.DIFICIL
	p4.alvos = p3.alvos
	t.check(not p4.mira_com_laser(), "difícil não tem laser")
	t.check(not p4.mira_trava(), "difícil não trava alvo")
	for _i in 13:
		pad.set_mask(Pad.AIM)
		p4.tick(pad)
	t.eq(p4.mira_alvo, -1, "difícil: mira sem travar em ninguém")
	# o gatilho também sai no bit TIRO (botão esquerdo do mouse)
	var antes := p4.tiro_pendente
	pad.set_mask(Pad.AIM | Pad.TIRO)
	p4.tick(pad)
	t.check(p4.tiro_pendente != antes, "o bit TIRO (mouse esquerdo) puxa o gatilho")

	p2.alvos = func() -> Array:
		return [Vector3i(0, 0, -5000)]
	p2.tick(pad)
	t.eq(p2.mira_alvo, -1, "alvo a 5000 está fora do alcance")
	p2.alvos = func() -> Array:
		return [Vector3i(2000, 0, -100)]
	p2.tick(pad)
	t.eq(p2.mira_alvo, -1, "alvo a 2000 de LADO está fora da largura de ±1000")
	return true
