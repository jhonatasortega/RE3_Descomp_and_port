class_name Aot
extends RefCounted
## AOT — as "áreas de interesse" que o script instala na sala (P2-04 / P2-05).
##
## AOT (*Area Of Trigger*) é o mecanismo pelo qual o RE conecta o mundo: porta, gatilho de
## evento, item no chão, mensagem de exame — tudo é uma caixa (ou quadrilátero) no plano do
## chão que o script REGISTRA e o motor testa a cada frame contra a posição do personagem.
##
## ── Como o motor faz (docs/decomp/notes/door_handler.md) ──
##   driver per-frame `0x80050b58` → VM de colisão de AOT `0x800505ac`
##     AABB  `0x800101c8` · QUAD `0x8001020c` (4 testes de sinal de produto vetorial)
##   se DENTRO: grava `player+0xc` = id do AOT e despacha **por SCE**:
##     `jalr *(0x8009e0bc + sce*4)`, a0 = descriptor
##   `sce == 1` → produtor `0x80050d28`: grava `gs+0x2154` = descriptor e `0x800c7960` = 1
##     (flag de troca) → `door_handler 0x800248e4` → room-loader `0x800493ec`
##
## ── Layout on-disk (o que o port lê do bytecode) ──
## `0x61` **32 B** e `0x62` **40 B** (4 pontos) — `sce@+2`, `aot@+1`, `floor@+3`,
## caixa em `s16@+6/+8` (x,z) e `+10/+12` (w,d). Quando `sce ∈ {1, 13}` **é PORTA**, e o
## destino é campo ESTÁTICO:
##
##     0x61: next_stage @+0x16 · next_room @+0x17 · cut @+0x18 · chegada s16@+0xe/+0x10/+0x12/+0x14
##     0x62: next_stage @+0x1e · next_room @+0x1f · cut @+0x20 · chegada s16@+0x16/+0x18/+0x1a/+0x1c
##
## `next_room` é **índice interno** na tabela de fileids (`0x8009dfd0[stage]`), e o de-para
## provado é `índice = dígitos hex do nome` (`Rxyz` → `int(yz, 16)`).
##
## `0x63` (20 B) = gatilho AABB · `0x64` (28 B) = gatilho em quadrilátero ·
## `0x68` (30 B) = item no chão (`item_id@+22`, `amount@+24`) · `0x65` = aot_reset.

enum Kind { BOX, QUAD }

## SCE conhecidos que interessam ao gameplay (byte +2 do opcode).
const SCE_PORTA := 1
const SCE_PORTA_13 := 13
const SCE_ITEM := 2
const SCE_MENSAGEM := 4
const SCE_FLAG := 6
const SCE_MOVE := 8

var id := 0                       ## id do AOT (byte +1) — o motor grava em `player+0xc`
var sce := 0
var kind: Kind = Kind.BOX
var floor_id := 0
var box := Rect2i()               ## quando BOX: x, z, w, d em unidades PS1
var quad: Array[Vector2i] = []    ## quando QUAD: 4 pontos no plano XZ
var opcode := 0
var ativo := true
## Só quando é porta (`sce ∈ {1,13}`): destino ESTÁTICO lido do descriptor.
var to_stage := -1
var to_room := -1
var to_pos := Vector3i.ZERO
var to_facing := 0
var to_cut := -1
## Seletor de GRUPO de câmera do RVD (`gs+0x2495`): byte `+0xb` do descriptor.
## Provado em `0x800249d8`: `lbu $v0, 0xb($a1)` -> `sb $v0, 0x2495($s0)`. A doc do
## door_handler chamava esse byte de "flag/needs_key-ish" — é o grupo de câmera.
var to_grupo := 0
## Item no chão (`0x68`).
var item_id := 0
var item_qtd := 0


func is_porta() -> bool:
	return sce == SCE_PORTA or sce == SCE_PORTA_13


func is_item() -> bool:
	## Item no chão: opcode `0x68` (`sce_item_aot_set`), com `item_id@+22` e `amount@+24`.
	return opcode == 0x68


func contem(x: int, z: int) -> bool:
	## Teste do motor: AABB (`0x800101c8`) ou ponto-em-quad (`0x8001020c`).
	if not ativo:
		return false
	if kind == Kind.QUAD:
		return CameraRVD.point_in_quad(quad, x, z)
	return x >= box.position.x and x <= box.position.x + box.size.x \
		and z >= box.position.y and z <= box.position.y + box.size.y


func encosta(x: int, z: int, raio: int) -> bool:
	## O CORPO (círculo de raio `raio`) encosta na caixa? = ponto dentro da caixa inflada.
	## É o alcance de interação: a colisão te para a `raio` da face, então "corpo encostado"
	## é o mais perto que se chega — nem exige entrar na caixa (o ponto do pé não entra em
	## 294/453 portas), nem abre de longe (o erro da sonda de 600).
	if not ativo:
		return false
	if kind == Kind.QUAD:
		# aproximação para quads: testa o ponto e 4 pontos do círculo
		if CameraRVD.point_in_quad(quad, x, z):
			return true
		for d: Array in [[raio, 0], [-raio, 0], [0, raio], [0, -raio]]:
			if CameraRVD.point_in_quad(quad, x + d[0], z + d[1]):
				return true
		return false
	return x >= box.position.x - raio and x <= box.position.x + box.size.x + raio \
		and z >= box.position.y - raio and z <= box.position.y + box.size.y + raio


func to_room_id() -> String:
	## Nome da sala de destino: `R` + stage(1 hex) + room(2 hex).
	## O `next_room` on-disk já é o índice cujo de-para é o próprio nome em hex.
	if to_stage < 0 or to_room < 0:
		return ""
	return "R%X%02X" % [to_stage + 1, to_room]


func resumo() -> String:
	var onde := "quad" if kind == Kind.QUAD else "box %s" % box
	var dest := "" if not is_porta() else "  -> %s pos%s dir=%d cut=%d" % [
		to_room_id(), to_pos, to_facing, to_cut]
	return "AOT %d sce=%d (op 0x%02x) %s%s" % [id, sce, opcode, onde, dest]
