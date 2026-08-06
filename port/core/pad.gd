class_name Pad
extends RefCounted
## Controle como MÁSCARA DE BITS por tick, com gravação e replay (P0-09).
##
## Por que máscara e não `Input.is_action_pressed` direto na lógica: a máquina de estados do
## player do RE3 decide por bit de pad (`pad & 0x01`, `pad & 0x04`, `pad & 0x500`…), e o
## replay determinístico — base do harness de regressão (P7-04) e da rota crítica (P3-07) —
## exige que a entrada de um tick seja um VALOR gravável, não uma consulta ao teclado.
##
## ── Bits: o que está provado e o que não está ──
## O EXE tem DOIS layouts distintos (docs/formatos/exe.md §207-210, §336-339):
##
## 1. Pad das ROTINAS (global `0x800cc83c`, o que a SM lê):
##      `0x01` FRENTE ✅ (único provado por comportamento) · `0x04` correr 🟡
##      `0x200` DOWN/ré 🟡 · `0x500` (bits `0x100`+`0x400`) MIRAR ✅
## 2. Cópia "pad segurado" em `player+0x120`:
##      `0x10` ↑ · `0x20` → · `0x40` ↓ · `0x80` ← · `0x800` R1
##
## A doc é explícita: "Bits de pad ≠ FRENTE: só o bit0=FRENTE está provado por comportamento".
## Portanto os nomes abaixo do layout 1 marcados 🟡 são HIPÓTESE de leitura do disassembly e
## serão fixados na F1 (P1-11, validando tank controls contra o original). Não trato hipótese
## como fato: quem consome usa as constantes, e corrigir um bit aqui corrige o port todo.

## --- layout 1: pad das rotinas (o que a máquina de estados do player lê) ---
const FWD := 0x01          ## ✅ provado (rotina r1 = andar para frente)
const RUN := 0x04          ## 🟡 rotina r3 (correr)
const BACK := 0x200        ## 🟡 rotina r2/r6 (ré / giro de 180°)
const AIM := 0x500         ## ✅ bits 0x100 | 0x400 (entrar em mira; exige arma equipada)
const AIM_A := 0x100
const AIM_B := 0x400
## AÇÃO (usar/abrir/pegar). O bit real do pad ainda não foi isolado no EXE — no RE3 é o
## mesmo botão de confirmar. Declarado como provisório até P7-03 fixar o mapeamento.
const ACAO := 0x20000

## --- layout 2: cópia "pad segurado" (player+0x120) ---
const HELD_UP := 0x10
const HELD_RIGHT := 0x20
const HELD_DOWN := 0x40
const HELD_LEFT := 0x80
const HELD_R1 := 0x800

enum Mode { LIVE, REPLAY }

var mode: Mode = Mode.LIVE
var mask := 0                       ## máscara do tick atual
var prev_mask := 0                  ## máscara do tick anterior (para "acabou de apertar")
var recording := false

var _record: PackedInt32Array = PackedInt32Array()
var _replay: PackedInt32Array = PackedInt32Array()
var _replay_pos := 0

## Mapeamento tecla -> bit. Provisório e explícito: as teclas do protótipo antigo
## (WASD + Shift) enquanto o InputMap definitivo não entra (P7-03).
const KEYMAP := {
	KEY_W: FWD, KEY_UP: FWD,
	KEY_S: BACK, KEY_DOWN: BACK,
	KEY_SHIFT: RUN,
	KEY_A: HELD_LEFT, KEY_LEFT: HELD_LEFT,
	KEY_D: HELD_RIGHT, KEY_RIGHT: HELD_RIGHT,
	KEY_SPACE: AIM,
	KEY_E: ACAO, KEY_ENTER: ACAO,
}


func poll() -> int:
	## Chamado UMA vez por tick de gameplay (30 Hz). Devolve a máscara do tick.
	prev_mask = mask
	match mode:
		Mode.LIVE:
			mask = _read_live()
		Mode.REPLAY:
			mask = _replay[_replay_pos] if _replay_pos < _replay.size() else 0
			_replay_pos += 1
	if recording:
		_record.append(mask)
	return mask


func _read_live() -> int:
	var m := 0
	for tecla: int in KEYMAP:
		if Input.is_key_pressed(tecla as Key):
			m |= int(KEYMAP[tecla])
	return m


func set_mask(m: int) -> void:
	## Injeta uma máscara (harness/teste), respeitando a gravação.
	prev_mask = mask
	mask = m
	if recording:
		_record.append(mask)


func pressed(bit: int) -> bool:
	return (mask & bit) != 0


func just_pressed(bit: int) -> bool:
	return (mask & bit) != 0 and (prev_mask & bit) == 0


func just_released(bit: int) -> bool:
	return (mask & bit) == 0 and (prev_mask & bit) != 0


# ─────────────────────────────── gravação / replay ───────────────────────────────

func start_recording() -> void:
	_record = PackedInt32Array()
	recording = true


func stop_recording() -> PackedInt32Array:
	recording = false
	return _record


func load_replay(masks: PackedInt32Array) -> void:
	_replay = masks
	_replay_pos = 0
	mode = Mode.REPLAY


func replay_finished() -> bool:
	return mode == Mode.REPLAY and _replay_pos >= _replay.size()


func replay_length() -> int:
	return _replay.size()


func save_replay(caminho: String, masks: PackedInt32Array, nota := "") -> Error:
	var f := FileAccess.open(caminho, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({
		"versao": 1, "hz": Clock.HZ, "ticks": masks.size(), "nota": nota,
		"masks": Array(masks),
	}))
	return OK


func read_replay(caminho: String) -> PackedInt32Array:
	var saida := PackedInt32Array()
	if not FileAccess.file_exists(caminho):
		push_error("Pad: replay não encontrado: %s" % caminho)
		return saida
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(caminho))
	if not (raw is Dictionary):
		return saida
	var d: Dictionary = raw
	if int(d.get("hz", Clock.HZ)) != Clock.HZ:
		push_error("Pad: replay gravado a %s Hz, o jogo roda a %d Hz — o replay não vale."
			% [d.get("hz"), Clock.HZ])
		return saida
	for v: float in d.get("masks", []):
		saida.append(int(v))
	return saida
