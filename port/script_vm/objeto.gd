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


## ── Bits de `be_flg` que marcam o objeto como **ESCALÁVEL** (subir em cima) ✅ ──
## O `be_flg` não é só "visível". Ele é o `entry+0` do struct de 404 B, e o agregador do
## "subir em objeto" (`0x80036570`, chamado uma vez por quadro em `0x80036550`, logo depois do
## laço de objetos) usa DOIS bits dele como porta de entrada, lidos direto de `entry+0`:
##
##     0x80036594  lw   $v1, ($a0)          ; $a0 = o objeto em contato (`*0x800dd4b0`)
##     0x8003659c  andi $v0, $v1, 0x4000
##     0x800365a0  bnez $v0, 0x80036638     ; bit 0x4000 ACESO  -> desiste
##     0x800365a4  andi $v0, $v1, 0x100
##     0x800365a8  beqz $v0, 0x80036638     ; bit 0x100 APAGADO -> desiste
##     ... 6 quadros de contato ...  0x800365fc  ori $v0, $v0, 0x10 ; gs+0x77f4 |= 0x10
##
## e esse bit `0x10` de `gs+0x77f4` (= `0x800d1f2c`) é o ÚNICO gatilho da **rotina 9**
## (subir/descer): r1/r2 o leem em `0x800397b0`/`0x80039b58` e escrevem `player+4 = 0x901`.
##
## Como `entry+0 = u16@+0x0c | 1` (`0x800565cc..0x800565d8`), **os dois bits são DADO ESTÁTICO
## do SCD** — dá para dizer quais objetos do jogo são escaláveis sem rodar o jogo. Varredura dos
## **674** opcodes `0x7f` do jogo: só **11 declarações** (7 objetos distintos, em **R210, R219,
## R315, R406 e R50D**) passam, com `be_flg` `0x0101` ou `0x0301`; os outros 663 caem no
## `0x6001` (558×), `0x0001`, `0x6011`, `0x8001` etc. Ver `docs/decomp/notes/menu_bau.md §3`.
const BE_NAO_ESCALAVEL := 0x4000        ## `0x8003659c` — aceso reprova
const BE_ESCALAVEL := 0x0100            ## `0x800365a4` — apagado reprova


func escalavel() -> bool:
	## O objeto passa na porta ESTÁTICA do "subir em cima" (`0x80036594..0x800365a8`).
	## ⚠ É condição **necessária, não suficiente**: `0x80036c60` ainda exige, no MESMO quadro,
	## `entry+0xae & 0x10` e `entry+0xba & 0x8000`, e esses dois são de RUNTIME — o handler do
	## `0x7f` (`0x80056510`, lido inteiro) **não escreve `+0xae` nem `+0xba`**, e a varredura de
	## todo `sb/sh` com offset literal `0xae`/`0xba` no EXE não achou nenhum escritor no caminho
	## de objeto de cenário (os que existem são do player em `0x8004b7c4`, do menu em
	## `0x8006exxx` e de personagens em `0x8001dxxx`). Também não há `sw` para `+0xac`/`+0xb8`
	## que os cubra de raspão. **De onde vêm continua NÃO PROVADO** — pode ser cópia em bloco de
	## dado do RDT. Para o port isso não muda a resposta prática: a porta estática já é decisiva.
	return (be_flg & BE_ESCALAVEL) != 0 and (be_flg & BE_NAO_ESCALAVEL) == 0


func resumo() -> String:
	return "om %d pos%s rot%s floor=%d be_flg=0x%04x%s" % [
		slot, pos, rot, floor_id, be_flg, "" if visivel() else " (oculto)"]
