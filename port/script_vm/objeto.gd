class_name ObjetoSala
extends RefCounted
## Objeto de cenário instalado pelo opcode `0x7f` (`om_set`, 40 B) — P2-07.
##
## É a peça que faltava para o item no chão ter LUGAR e MALHA. O AOT (`0x67`/`0x68`) só diz
## "aqui é uma área de coleta"; quem existe no mundo 3D é o **objeto de sala**, e o AOT o
## referencia por um índice de slot (0..31).
##
## ── Handler `0x80056510` (provado instrução por instrução) ──
## Instancia `pool[slot]` (struct de 404 B em `gs+0x4328`) e preenche:
##
##     +1  u8  slot     índice no pool E no diretório de modelos do RDT (`offset_table[10]`)
##     +2  u8  tipo     -> entry+74 (itens: sempre 0)
##     +3  u8  fx       bit6/bit5 criam efeito extra (itens: 0)
##     +8  u8  floor    -> entry+9 (nível do piso)
##     +9  u8  mode     (mode & 0xC0) escolhe a fonte de animação (itens: 0)
##     +11 u8  visbit   255 = sem checagem; senão `bit_get(0x800d20d4, visbit)` ABORTA o setup
##     +12 u16 be_flg   entry+0 = be_flg | 1  — **bit 0 = VISÍVEL** (itens: 0x6000 -> 0x6001)
##     +14 s16 attr     entry+16; se bit 5 (32) estiver aceso, LIMPA o bit 0 de entry+0
##     +16 s16 X,Y,Z    entry+52/+56/+60 — posição de mundo (Y negativo = para CIMA)
##     +22 s16 RX,RY,RZ entry+108/+110/+112 — rotação de 12 bits (4096 = 360°)
##
## `entry+32` recebe a MATRIZ 3x3 = `RotMatrix(rot)`. **Não existe campo de escala** e não
## existe giro por frame: o item no chão é estático (o brilho é um efeito separado, ver
## `Aot.item_flags` bit 7).
##
## O desenho (loop `0x80036510`) só acontece se `be_flg & 1`; o handler do item apaga esse
## bit (`be_flg = 0x80000000`) quando a flag "já pego" está ligada.

var slot := 0
var tipo := 0
var fx := 0
var floor_id := 0
var modo := 0
var visbit := 255
var be_flg := 0
var attr := 0
var pos := Vector3i.ZERO           ## unidades PS1, no mesmo espaço do player
var rot := Vector3i.ZERO           ## 4096 = 360°


## Posição de "estacionado fora do mundo". Não é heurística: `pos = (-32000,-32000,-32000)`
## está LITERAL no bytecode de 6 objetos de item (R203 f3, R204 f14, R308 f3, R40A f5, R414 f3
## …), sempre com `be_flg=0x6000 attr=16 visbit=255` — o mesmo molde dos outros. É o objeto que
## o script instala AGORA e move para o lugar DEPOIS (item que cai/aparece por evento). Desenhar
## em -32000 põe o item a 40 metros do cenário; desenhar no centro da área de coleta inventa uma
## posição. Então não se desenha até o evento mover.
const PARQUEADO := -32000


func posicionado() -> bool:
	return pos.x > PARQUEADO or pos.y > PARQUEADO or pos.z > PARQUEADO


func visivel() -> bool:
	## `be_flg & 1` — o bit que o loop de desenho testa. `attr & 32` o apaga no setup.
	return (be_flg & 1) != 0 and (attr & 32) == 0


func resumo() -> String:
	return "om %d pos%s rot%s floor=%d be_flg=0x%04x%s" % [
		slot, pos, rot, floor_id, be_flg, "" if visivel() else " (oculto)"]
