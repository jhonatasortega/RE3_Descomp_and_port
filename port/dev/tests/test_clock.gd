extends RefCounted
## Valida o relógio de gameplay (critério do item P0-04).
##
## O ponto do teste: o passo de jogo é CONTADO, nunca medido em segundos de parede. Um replay
## de N ticks tem que dar exatamente o mesmo estado independentemente do FPS de render — é o
## que sustenta as constantes por-frame da decomp (velocidade, giro, recuo, timing de tiro).


func run(t: Object) -> bool:
	t.group("Clock")

	t.eq(Clock.HZ, 30, "gameplay a 30 Hz (PS1 NTSC: 60 Hz de vídeo, lógica a 30)")
	t.near(Clock.DT, 1.0 / 30.0, 1e-9, "DT = 1/30")
	t.eq(Clock.MAX_CATCHUP, 8, "recuperação limitada a 8 passos por quadro")

	var c := Clock.new()

	# --- contagem de ticks ---
	t.eq(c.frame, 0, "começa no tick 0")
	c.step()
	t.eq(c.frame, 1, "step() avança 1 tick")
	c.step_n(29)
	t.eq(c.frame, 30, "30 ticks")
	t.near(c.seconds(), 1.0, 1e-6, "30 ticks = 1,0 s de jogo")
	t.eq(c.frames_for(1.133), 34, "1,133 s = 34 frames (ciclo de andar do anim00)")
	t.eq(c.frames_for(2.0), 60, "2 s = 60 ticks")

	# --- sinal emitido por tick ---
	var recebidos: Array[int] = []
	c.ticked.connect(func(n: int) -> void: recebidos.append(n))
	c.step_n(3)
	t.eq(recebidos, [31, 32, 33], "sinal ticked emitido uma vez por tick, em ordem")

	# --- pausa não avança o mundo ---
	c.paused = true
	var antes := c.frame
	c._process(Clock.DT)
	t.eq(c.frame, antes, "pausado: nenhum tick avança")
	c.paused = false
	c._process(Clock.DT)
	t.eq(c.frame, antes + 1, "despausado: um quadro de 1/30 s = 1 tick")

	# --- determinismo: mesmo nº de ticks => mesmo estado, com qualquer 'delta' ---
	# Determinismo com acumulador: o MESMO tempo real dá o MESMO número de ticks, seja em
	# poucos quadros grandes ou em muitos quadros pequenos. É isso que desacopla do render.
	var a := Clock.new()
	var b := Clock.new()
	for _i in 30:
		a._process(1.0 / 30.0)                # 30 quadros de 1/30 s = 1,0 s
	for _i in 300:
		b._process(1.0 / 300.0)               # 300 quadros de 1/300 s = 1,0 s
	t.eq(a.frame, b.frame, "1 segundo de tempo real dá o mesmo nº de ticks em qualquer FPS")
	t.eq(a.frame, 30, "e esse número é 30 (o passo é sempre 1/30)")
	# quadro longo (engasgo): recupera até MAX_CATCHUP, sem pular tempo indefinidamente
	var d := Clock.new()
	d._process(1.0)                            # um quadro de 1 s inteiro
	t.eq(d.frame, Clock.MAX_CATCHUP, "engasgo de 1 s recupera no máximo MAX_CATCHUP ticks")

	c.reset()
	t.eq(c.frame, 0, "reset volta ao tick 0")
	a.free()
	b.free()
	c.free()

	# sentinela do runner: se um erro abortar a função antes daqui, a suíte acusa.
	return true
