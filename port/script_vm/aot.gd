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
## `0x63` (20 B) = gatilho AABB · `0x64` (28 B) = gatilho em quadrilátero · `0x65` = aot_reset.
##
## ── ITEM NO CHÃO: `0x67` **e** `0x68` (correção de rota) ──
## A tabela de opcodes chamava `0x67` de "door_aot_set". **Não é porta**: é o AOT de ITEM na
## versão de 2 pontos (22 B, handler `0x800574f4`), e o `0x68` é a de 4 pontos (30 B, handler
## `0x800576c4`) — mesmo payload, base diferente (+14 vs +22). São **330 itens em 103 salas**
## (316 do `0x67` + 14 do `0x68`); antes o port só via os 14.
##
## O 3D do item NÃO vem do `item_id`: o campo `om` do payload é um SLOT (0..31) que aponta ao
## mesmo tempo para o objeto de cenário do `0x7f` (posição/rotação, ver `objeto.gd`) e para o
## diretório de modelos do RDT (`offset_table[10]`, `nOmodel` registros de 8 B `{TIM, MD1}`).
##
## ── Layout comum da família aot_set ──
##     +1 aot_id · +2 sce · +3 **SAT** · +4 **nFloor** (0x80 = qualquer) · +5 super

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
var floor_id := 0                 ## `+4` nFloor: andar exigido (0x80 = qualquer)
var sat := 0                      ## `+3` SAT: máscara de quem dispara/como (item = 0x31)
var super_id := 0                 ## `+5` super (0 em todos os itens)
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
## Item no chão (`0x67`/`0x68`) — payload em +14 (2 pontos) ou +22 (4 pontos):
var item_id := 0
var item_qtd := 0                 ## u16 `payload+2` (era lido como u8)
var item_flag := 0                ## u16 `payload+4`: BIT de "já pego" — do DADO, não inventado
var item_om := 0                  ## u8 `payload+6`: slot do objeto/modelo; >= 32 = sem 3D
var item_flags := 0               ## u8 `payload+7`: bit 0 = anima ao pegar · bit 7 = brilho


func is_porta() -> bool:
	return sce == SCE_PORTA or sce == SCE_PORTA_13


func is_item() -> bool:
	## Item no chão: `0x67` (2 pontos) ou `0x68` (4 pontos) — os dois são `sce_item_aot_set`.
	return opcode == 0x67 or opcode == 0x68


func tem_modelo() -> bool:
	## `om >= 32` (128 e 255 nos dados) = o item não tem objeto 3D: só a área de coleta.
	return item_om < 32


func area_valida() -> bool:
	## Há AOT de item com área DEGENERADA no dado: `rect=(0,0,0,0)` (R208 aot 8, R300 aot 7,
	## R40F aot 3 …) ou `(0,0,1,1)` (R414 aot 5). Com o teste não-sinalizado do motor
	## (`(u32)(px - X) <= W`) isso só dispara com o pé exatamente em (0,0) — ou seja, o item
	## NÃO é coletável andando; ele é entregue por evento/script. Serve para não fingir uma
	## área de coleta nem desenhar o item na origem do mundo.
	if kind == Kind.QUAD:
		return quad.size() == 4 and (quad[0] != quad[1] or quad[1] != quad[2])
	return box.size.x > 1 and box.size.y > 1


func tem_brilho() -> bool:
	## Bit 7 do `iflags`: o motor cria um efeito ESP `0x0705` 90 unidades ACIMA do modelo
	## (`param = 0x28000000`, matriz do próprio objeto). São 28 itens no jogo.
	return (item_flags & 0x80) != 0


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
