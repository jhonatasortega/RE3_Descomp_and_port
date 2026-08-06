extends RefCounted
## Valida a entrada como máscara + gravação/replay (parte do critério do item P0-09).
##
## O teste que interessa: gravar N ticks e reproduzir dá EXATAMENTE a mesma sequência. Sem
## isso não existe rota crítica automatizada (P3-07) nem suíte de regressão (P7-04).


func run(t: Object) -> bool:
	t.group("Pad")

	# --- bits provados no EXE (o resto é hipótese e está marcado como tal no código) ---
	t.eq(Pad.FWD, 0x01, "FRENTE = bit 0 (único provado por comportamento)")
	t.eq(Pad.AIM, 0x500, "MIRAR = 0x500 (bits 0x100 | 0x400)")
	t.eq(Pad.AIM_A | Pad.AIM_B, Pad.AIM, "os dois bits de mira somam a máscara")
	t.eq(Pad.HELD_UP | Pad.HELD_RIGHT | Pad.HELD_DOWN | Pad.HELD_LEFT, 0xF0,
		"layout 'pad segurado' (player+0x120): direções em 0x10..0x80")

	# --- consulta de bit e borda ---
	var p := Pad.new()
	p.set_mask(Pad.FWD)
	t.check(p.pressed(Pad.FWD), "bit apertado")
	t.check(p.just_pressed(Pad.FWD), "borda de subida no primeiro tick")
	p.set_mask(Pad.FWD)
	t.check(not p.just_pressed(Pad.FWD), "segurar não repete a borda de subida")
	p.set_mask(0)
	t.check(p.just_released(Pad.FWD), "borda de descida")
	t.check(not p.pressed(Pad.FWD), "solto")

	# --- combinação de bits ---
	p.set_mask(Pad.FWD | Pad.RUN)
	t.check(p.pressed(Pad.FWD) and p.pressed(Pad.RUN), "dois bits ao mesmo tempo")
	t.check(not p.pressed(Pad.BACK), "bit não apertado permanece falso")

	# --- gravação -> replay: a sequência tem de voltar idêntica ---
	var seq: Array[int] = [0, Pad.FWD, Pad.FWD, Pad.FWD | Pad.RUN, Pad.AIM, 0, Pad.BACK]
	var rec := Pad.new()
	rec.start_recording()
	for m in seq:
		rec.set_mask(m)
	var gravado := rec.stop_recording()
	t.eq(gravado.size(), seq.size(), "gravou um valor por tick")
	t.eq(Array(gravado), seq, "gravação idêntica à sequência aplicada")

	var rep := Pad.new()
	rep.load_replay(gravado)
	t.eq(rep.mode, Pad.Mode.REPLAY, "entra em modo replay")
	var lidos: Array[int] = []
	for _i in seq.size():
		lidos.append(rep.poll())
	t.eq(lidos, seq, "replay reproduz a sequência tick a tick")
	t.check(rep.replay_finished(), "replay termina no fim da lista")
	t.eq(rep.poll(), 0, "depois do fim, o pad fica em zero (não repete o último)")

	# --- ida e volta por arquivo (é assim que a rota crítica vai viver no repo) ---
	var caminho := "user://_test_replay.json"
	t.eq(rep.save_replay(caminho, gravado, "teste P0-09"), OK, "gravou o replay em arquivo")
	var lido := rep.read_replay(caminho)
	t.eq(Array(lido), seq, "replay lido do disco é idêntico ao gravado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(caminho))
	t.eq(Array(rep.read_replay("user://_nao_existe.json")), [],
		"replay ausente devolve vazio (e registra erro)")

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true
