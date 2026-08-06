extends SceneTree
## diag_real: joga o JOGO REAL por 40 s com TECLADO INJETADO (Input.parse_input_event).
##
## Diferença crucial para shot_walk/diag_tour: aqui NINGUÉM chama mundo.tick() na mão.
## O caminho é o do usuário: Clock._process (30 Hz) -> Game._on_tick -> pad.poll()
## (Input.is_key_pressed) -> Screen._on_tick -> mundo.tick(pad). Só se injeta o teclado.
##
## Saída: análise da série de posições (parado com tecla, teleporte, oscilação,
## congelamento, pad.mask vs teclas) + 6 screenshots _diag_real_N.png na raiz do projeto.

const TICKS_TOTAL := 1200            ## 40 s a 30 Hz
const TICKS_POR_FASE := 60           ## ~2 s por combinação de teclas
const SHOTS := [100, 300, 500, 700, 900, 1100]

## fases: listas de keycodes segurados (W frente, S ré, A/D giro, SHIFT correr)
var FASES: Array = [
	[KEY_W], [KEY_W], [KEY_W, KEY_A], [KEY_W], [KEY_W, KEY_D],
	[KEY_S], [KEY_W], [KEY_A], [KEY_W, KEY_SHIFT], [KEY_W],
	[KEY_D], [KEY_W], [KEY_W, KEY_A], [KEY_S], [KEY_W],
	[KEY_W, KEY_D], [KEY_W, KEY_SHIFT], [KEY_W], [KEY_W, KEY_A], [KEY_W],
]

const BIT_POR_TECLA := {
	KEY_W: 0x01, KEY_S: 0x200, KEY_SHIFT: 0x04, KEY_A: 0x80, KEY_D: 0x20,
}

var _cena: Node
var _game: Node
var _frames := 0                     ## frames de RENDER desde o boot
var _comecou := false
var _tick_n := 0                     ## ticks de gameplay observados desde o começo do teste
var _teclas_down: Array = []         ## keycodes atualmente "pressionados"
var _fase_atual := -1
var _shot_i := 0
var _shot_pendente := false
var _fim := false
var _t0_ms := 0

## série por tick: [frame, pos(Vector3i), facing, mask, esperado, fase, sala, telas_aberta]
var _serie: Array = []
var _ts_ticks: Array = []            ## Time.get_ticks_msec() de cada tick observado
var _trocas_de_sala: Array = []      ## [tick, de, para]
var _amostras_pad: Array = []        ## strings "tick N: teclas [...] esperado 0x.. mask 0x.."


func _initialize() -> void:
	var cena: PackedScene = load("res://scenes/game.tscn")
	_cena = cena.instantiate()
	get_root().add_child(_cena)
	print("[real] cena instanciada; aguardando estabilizar...")


func _process(_d: float) -> bool:
	_frames += 1
	if _fim:
		return true
	if not _comecou:
		if _frames < 20:
			return false
		_game = get_root().get_node_or_null("Game")
		var mundo: Object = _cena.get("mundo")
		if _game == null or mundo == null:
			print("[real] FALHA: Game=%s mundo=%s" % [_game, mundo])
			return true
		# conecta DEPOIS do Screen: este handler roda após Screen._on_tick -> pos pós-movimento
		_game.connect("tick", _on_tick_jogo)
		mundo.connect("sala_trocada", _on_sala)
		if OS.get_environment("DIAG_HUD_OFF") == "1":
			var hud: Object = _cena.get("hud")
			if hud != null:
				hud.set("visible", false)
			print("[real] A/B: HUD desligada (sem _atualizar_hud, sem erro de formato)")
		_t0_ms = Time.get_ticks_msec()
		_comecou = true
		var pl: Object = mundo.get("player")
		print("[real] começo: sala %s pos %s facing %s clock.frame=%d" % [
			mundo.get("room").get("room_id"), pl.get("pos"), pl.get("facing"),
			_game.get("clock").get("frame")])
		return false

	# aplica o conjunto de teclas da fase corrente (injeção de TECLADO de verdade)
	var fase: int = mini(_tick_n / TICKS_POR_FASE, FASES.size() - 1)
	if fase != _fase_atual:
		_fase_atual = fase
		_aplicar_teclas(FASES[fase])
	if _shot_pendente and OS.get_environment("DIAG_NO_SHOTS") == "1":
		_shot_pendente = false
		_shot_i += 1
	if _shot_pendente:
		_shot_pendente = false
		var img := get_root().get_texture().get_image()
		var alvo := "res://_diag_real_%d.png" % _shot_i
		img.save_png(ProjectSettings.globalize_path(alvo))
		print("[real] shot %d (tick %d): %s" % [_shot_i, _tick_n, ProjectSettings.globalize_path(alvo)])
		_shot_i += 1
	if _tick_n >= TICKS_TOTAL:
		_aplicar_teclas([])
		Input.flush_buffered_events()
		_analisar()
		_fim = true
		return true
	return false


func _aplicar_teclas(novas: Array) -> void:
	for k: int in _teclas_down:
		if not novas.has(k):
			_evento(k, false)
	for k: int in novas:
		if not _teclas_down.has(k):
			_evento(k, true)
	_teclas_down = novas.duplicate()
	Input.flush_buffered_events()


func _evento(keycode: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode as Key
	e.physical_keycode = keycode as Key
	e.pressed = pressed
	e.echo = false
	Input.parse_input_event(e)


func _esperado() -> int:
	var m := 0
	for k: int in _teclas_down:
		m |= int(BIT_POR_TECLA.get(k, 0))
	return m


func _on_tick_jogo(frame: int) -> void:
	if not _comecou or _fim:
		return
	_tick_n += 1
	var mundo: Object = _cena.get("mundo")
	var pl: Object = mundo.get("player")
	var telas: Object = _cena.get("telas")
	var aberta: bool = telas != null and bool(telas.call("aberta"))
	var mask: int = _game.get("pad").get("mask")
	_serie.append([frame, pl.get("pos"), pl.get("facing"), mask, _esperado(),
		_fase_atual, mundo.get("room").get("room_id"), aberta])
	_ts_ticks.append(Time.get_ticks_msec())
	if _tick_n % TICKS_POR_FASE == 5:      ## 5 ticks após a troca (a injeção assenta)
		_amostras_pad.append("tick %4d fase %2d teclas %-16s esperado 0x%03x mask 0x%03x %s" % [
			_tick_n, _fase_atual, _nomes(_teclas_down), _esperado(), mask,
			"OK" if mask == _esperado() else "<<< DIVERGE"])
	if _shot_i < SHOTS.size() and _tick_n == int(SHOTS[_shot_i]):
		_shot_pendente = true


func _on_sala(de: String, para: String, _porta: Object) -> void:
	_trocas_de_sala.append([_tick_n, de, para])


static func _nomes(teclas: Array) -> String:
	var n: Array = []
	for k: int in teclas:
		n.append(OS.get_keycode_string(k as Key))
	return "+".join(n) if n.size() > 0 else "(nada)"


func _analisar() -> void:
	var dt_ms := Time.get_ticks_msec() - _t0_ms
	print("\n========== ANÁLISE (%d ticks registrados em %.1f s de parede; %.1f ticks/s) ==========" % [
		_serie.size(), dt_ms / 1000.0, _serie.size() / maxf(0.001, dt_ms / 1000.0)])
	# saúde do relógio: quanto tempo real ele viu e quantos ticks deu
	var clock: Object = _game.get("clock")
	var soma_delta: float = clock.get("soma_delta")
	var chamadas: int = clock.get("chamadas")
	print("clock: frame=%d · soma_delta=%.1f s (esperado %d ticks) · chamadas(_process)=%d (fps médio %.1f)" % [
		clock.get("frame"), soma_delta, int(soma_delta * 30.0), chamadas,
		chamadas / maxf(0.001, soma_delta)])
	# lacunas entre ticks (> 267 ms = estouro do MAX_CATCHUP -> ticks descartados)
	var lacunas := 0
	var maior_lacuna := 0
	for gi in range(1, _ts_ticks.size()):
		var gap: int = int(_ts_ticks[gi]) - int(_ts_ticks[gi - 1])
		if gap > 267:
			lacunas += 1
		maior_lacuna = maxi(maior_lacuna, gap)
	print("lacunas entre ticks >267 ms: %d · maior lacuna: %d ms" % [lacunas, maior_lacuna])

	var parados_mov := 0                   ## dist 0 com FWD/BACK na máscara REAL
	var parados_por_tecla: Dictionary = {}
	var teleportes: Array = []
	var oscilacoes: Array = []
	var congelamentos: Array = []
	var mask_diverge := 0
	var mask_diverge_ex: Array = []
	var telas_abertas := 0
	var dist_total := 0.0

	var run_ini := -1                      ## início da sequência de pos idêntica com W
	var delta_ant := Vector2.ZERO
	var mask_ant := -1
	var troca_ticks: Dictionary = {}
	for t: Array in _trocas_de_sala:
		troca_ticks[int(t[0])] = true
		troca_ticks[int(t[0]) + 1] = true

	for i in range(1, _serie.size()):
		var a: Array = _serie[i - 1]
		var b: Array = _serie[i]
		var pa: Vector3i = a[1]
		var pb: Vector3i = b[1]
		var mask: int = b[3]
		var esperado: int = b[4]
		var d := Vector2(float(pb.x - pa.x), float(pb.z - pa.z))
		var dist := d.length()
		dist_total += dist
		if bool(b[7]):
			telas_abertas += 1
		# 1) parado com tecla de movimento (pela máscara REAL que o Pad leu)
		if dist == 0.0 and (mask & 0x201) != 0 and not troca_ticks.has(i):
			parados_mov += 1
			var chave := "FWD" if (mask & 0x01) != 0 else "BACK"
			if (mask & 0xA0) != 0:
				chave += "+GIRO"
			parados_por_tecla[chave] = int(parados_por_tecla.get(chave, 0)) + 1
		# 2) teleporte
		if dist > 250.0:
			if troca_ticks.has(i):
				pass                       ## porta: teleporte legítimo, listado à parte
			else:
				teleportes.append("tick %d: %s -> %s (%.0f un) mask 0x%03x sala %s" % [
					i, pa, pb, dist, mask, b[6]])
		# 3) oscilação: reversão de direção sem troca de máscara
		if dist > 10.0 and delta_ant.length() > 10.0 and mask == mask_ant \
				and d.dot(delta_ant) < 0.0 and not troca_ticks.has(i):
			oscilacoes.append("tick %d: delta %s -> %s mask 0x%03x" % [i, delta_ant, d, mask])
		# 4) congelamento: pos idêntica > 60 ticks com FWD
		if pa == pb and (mask & 0x01) != 0:
			if run_ini < 0:
				run_ini = i
		else:
			if run_ini >= 0 and i - run_ini > 60:
				congelamentos.append("ticks %d..%d (%d ticks) em %s sala %s" % [
					run_ini, i, i - run_ini, pa, a[6]])
			run_ini = -1
		# 5) máscara diverge das teclas injetadas. Janela de assentamento de 10 ticks após a
		# troca de fase: a injeção acontece 1x por FRAME renderizado, e com catchup até 8
		# ticks rodam entre dois frames — nesses ticks a máscara ainda é a da fase anterior.
		if mask != esperado and (_tick_n_of(i) % TICKS_POR_FASE) > 10:
			mask_diverge += 1
			if mask_diverge_ex.size() < 8:
				mask_diverge_ex.append("tick %d (fase %d, off %d): esperado 0x%03x mask 0x%03x" % [
					i, int(b[5]), _tick_n_of(i) % TICKS_POR_FASE, esperado, mask])
		delta_ant = d
		mask_ant = mask
	if run_ini >= 0 and _serie.size() - run_ini > 60:
		var a2: Array = _serie[run_ini]
		congelamentos.append("ticks %d..fim (%d ticks) em %s sala %s" % [
			run_ini, _serie.size() - run_ini, a2[1], a2[6]])

	var p_ini: Vector3i = (_serie[0] as Array)[1]
	var p_fim: Vector3i = (_serie[_serie.size() - 1] as Array)[1]
	print("posição: início %s -> fim %s · distância percorrida (soma) %.0f un" % [p_ini, p_fim, dist_total])
	print("trocas de sala: %d %s" % [_trocas_de_sala.size(), _trocas_de_sala])
	print("ticks com tela de UI aberta: %d" % telas_abertas)
	print("\n[1] ticks PARADOS com tecla de movimento: %d de %d (%s)" % [
		parados_mov, _serie.size(), parados_por_tecla])
	print("[2] TELEPORTES (>250 un/tick, fora de porta): %d" % teleportes.size())
	for s: String in teleportes.slice(0, 10):
		print("    %s" % s)
	print("[3] OSCILAÇÕES (reversão sem troca de tecla): %d" % oscilacoes.size())
	for s: String in oscilacoes.slice(0, 10):
		print("    %s" % s)
	print("[4] CONGELAMENTOS (>60 ticks parado com W): %d" % congelamentos.size())
	for s: String in congelamentos:
		print("    %s" % s)
	print("[5] pad.mask vs teclas injetadas: %d divergência(s)" % mask_diverge)
	for s: String in mask_diverge_ex:
		print("    %s" % s)
	print("\namostras de pad por fase:")
	for s: String in _amostras_pad:
		print("    %s" % s)
	# posições a cada 100 ticks para leitura humana
	print("\ntrajetória (a cada 100 ticks):")
	var i2 := 0
	while i2 < _serie.size():
		var r: Array = _serie[i2]
		print("    tick %4d sala %s pos %s facing %5d mask 0x%03x" % [i2, r[6], r[1], r[2], r[3]])
		i2 += 100
	var veredito := "LISO"
	if congelamentos.size() > 0 or teleportes.size() > 3 or mask_diverge > 20 \
			or parados_mov > _serie.size() / 3:
		veredito = "PROBLEMA REPRODUZIDO"
	print("\n[real] VEREDITO: %s" % veredito)


func _tick_n_of(i: int) -> int:
	return i + 1
