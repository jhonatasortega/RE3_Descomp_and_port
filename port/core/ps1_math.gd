class_name PS1Math
extends RefCounted
## Matemática do PS1 — ângulo INTEIRO de 12 bits e seno/cosseno pela tabela do jogo (P0-05).
##
## O RE3 não tem FPU: ângulo é `0..4095` (4096 = 360°, máscara `0xfff`) e seno vem de uma
## tabela de QUARTO DE ONDA no EXE (`0x800a3310`, 1025 × s16, amplitude 4096). Usar float
## aqui seria trocar o dado por aproximação — o ângulo inteiro é a verdade, e a conversão
## para radianos só acontece na hora de DESENHAR.
##
## Evidência: `andi ang,0xfff` e bit `0x800` (menor rotação) no controlador do player
## (`0x8001a248..0x8001a5b0`). Tabela extraída por `tools/exe_sincos.py` (que prova, no dado,
## que ela é exatamente `round(4096*sin(i*PI/2/1024))` — erro 0 nas 1025 entradas).
##
## Fontes: docs/formatos/exe.md · data/physics.json (`angle_units`, `sin_cos_table`)

const FULL_CIRCLE := 4096          ## 360° em unidades de ângulo do PS1
const HALF_CIRCLE := 2048          ## 180°
const QUARTER := 1024              ## 90° — tamanho do quarto de onda tabelado
const ANGLE_MASK := 0xFFF          ## `andi ang,0xfff` do EXE
const SIGN_BIT := 0x800            ## bit de "menor rotação" do EXE
const ONE := 4096                  ## 1.0 em ponto-fixo (12 bits) — amplitude da tabela
const SHIFT := 12                  ## deslocamento correspondente a ONE
const DEG_PER_UNIT := 360.0 / float(FULL_CIRCLE)
const TABLE_PATH := "res://data/ps1_sincos.json"

static var _quarter: PackedInt32Array = PackedInt32Array()
static var _from_exe := false      ## true = tabela lida do dado extraído do EXE


static func _ensure_table() -> void:
	if _quarter.size() == QUARTER + 1:
		return
	var t := PackedInt32Array()
	if FileAccess.file_exists(TABLE_PATH):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		if raw is Dictionary and raw.has("quarter_wave"):
			for v: float in raw["quarter_wave"]:
				t.append(int(v))
			_from_exe = true
	if t.size() != QUARTER + 1:
		# Fallback IDÊNTICO ao dado: tools/exe_sincos.py prova erro 0 contra a tabela do EXE.
		# Não é aproximação silenciosa — só evita travar quando data/ não foi gerado ainda.
		t = PackedInt32Array()
		for i in QUARTER + 1:
			t.append(int(round(float(ONE) * sin(float(i) * PI / 2.0 / float(QUARTER)))))
		_from_exe = false
		push_warning("PS1Math: %s ausente; usando tabela calculada (equivalente, ver tools/exe_sincos.py)"
			% TABLE_PATH)
	_quarter = t


static func table_from_exe() -> bool:
	## Se false, a tabela veio do cálculo equivalente e não do EXE extraído.
	_ensure_table()
	return _from_exe


static func wrap_angle(a: int) -> int:
	## Normaliza para `0..4095` (equivalente ao `andi 0xfff`, inclusive para negativos).
	return a & ANGLE_MASK


static func rsin(a: int) -> int:
	## sin(a) em ponto-fixo (escala 4096), reconstruído por simetria como o EXE faz.
	_ensure_table()
	a = wrap_angle(a)
	if a < QUARTER:
		return _quarter[a]
	if a < HALF_CIRCLE:
		return _quarter[HALF_CIRCLE - a]
	if a < HALF_CIRCLE + QUARTER:
		return -_quarter[a - HALF_CIRCLE]
	return -_quarter[FULL_CIRCLE - a]


static func rcos(a: int) -> int:
	## cos(a) = sin(a + 90°).
	return rsin(a + QUARTER)


static func rotate_xz(x: int, z: int, ang: int) -> Vector2i:
	## Rotaciona (x,z) por `ang` no plano do chão, em ponto-fixo (>> 12 no fim).
	## Usada no root-motion: `pos += rotate(pose_motion, facing)` (physics.json/integracao).
	var s := rsin(ang)
	var c := rcos(ang)
	return Vector2i((x * c + z * s) >> SHIFT, (-x * s + z * c) >> SHIFT)


static func angle_diff(from_a: int, to_a: int) -> int:
	## Menor diferença assinada `from -> to`, em `-2048..2047` (bit 0x800 do EXE).
	var d := (to_a - from_a) & ANGLE_MASK
	if d & SIGN_BIT:
		d -= FULL_CIRCLE
	return d


static func angle_towards(from_a: int, to_a: int, max_step: int) -> int:
	## Gira no máximo `max_step` unidades na direção de `to_a` (para o giro por frame).
	var d := angle_diff(from_a, to_a)
	if absi(d) <= max_step:
		return wrap_angle(to_a)
	return wrap_angle(from_a + (max_step if d > 0 else -max_step))


static func angle_of_xz(x: int, z: int) -> int:
	## Ângulo PS1 do vetor (x,z) — usado por mira/IA para "virar para o alvo".
	return wrap_angle(int(round(atan2(float(x), float(z)) * float(FULL_CIRCLE) / TAU)))


static func to_deg(a: int) -> float:
	return float(wrap_angle(a)) * DEG_PER_UNIT


static func to_rad(a: int) -> float:
	return float(wrap_angle(a)) * TAU / float(FULL_CIRCLE)


static func from_deg(d: float) -> int:
	return wrap_angle(int(round(d / DEG_PER_UNIT)))


static func fx_to_float(v: int) -> float:
	## Ponto-fixo (escala 4096) -> float. Só para desenhar/depurar.
	return float(v) / float(ONE)
