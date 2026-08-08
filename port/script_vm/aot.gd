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

## ── A TABELA DE DESPACHO POR `sce` — `0x8009e0bc`, 15 entradas ✅ ──
## Provado em `0x80050ad4..0x80050b08` (e o gêmeo `0x8005065c..0x80050678`): o laço de AOT lê
## `lbu $v0, ($s0)` = **byte +0 do AOT em RAM** e faz `jalr *(0x8009e0bc + sce*4)`. E o AOT em
## RAM é `script_pc + 2` (`0x80055c74/78`: `v0 = obj+0x1c; v0 += 2; gs+0x2158[id] = v0`), logo
## **AOT+0 == byte +2 do opcode == `sce`**. O handler recebe `a0 = aot + 0xc` (payload; = byte
## +14 do `0x63`) ou `aot + 0x14` quando `sat & 0x80` (forma de 4 pontos).
##
##     sce  handler      papel (como foi provado)
##      0   0x80050d00   copia dois u16 p/ gs+0x780e/0x7810 (marca de AOT tocado)
##      1   0x80050d28   PORTA "normal" (produtor da troca de sala)
##      2   0x8005111c   ITEM: grava gs+0x21dc e abre a janela de obter (exe_items.md §2.3)
##      3   0x8005127c   `jr $ra` — NADA (slot morto)
##      4   0x80051284   MENSAGEM: `0x8002fd30(0, u16@+2|0x2000, u16@+0, u16@+4<<16)`
##      5   0x800512bc   EVENTO: inicia THREAD do script (ver `evento_func()`)
##      6   0x800512fc   FLAG set/clear (mesmo handler do opcode 0x4d — exe_items.md §1.1)
##      7   0x8005136c   escreve u16@+0 em `*(0x800cc878)+0xa`
##      8   0x80051388   **SAVE / MÁQUINA DE ESCREVER** — a rotina per-frame `0x800513cc`
##                       faz `find_by_id(0x81)` em `0x80051404`, e `0x81` = **Ink Ribbon**
##                       ("posso salvar meu progresso... com uma máquina de escrever")
##      9   0x800514c4   **BAÚ DE ITENS** — `0x800514cc` grava `2` em `0x800e01c4` = `ctx+0x04`
##                       (screen kind da task do menu, ctx `0x800e01c0`). É o ÚNICO escritor de
##                       kind 2 no EXE (varredura de todo `sb/sh/sw ..., 0x1c4(reg)`), e os
##                       subestados do kind 2 (tabela `0x8009f4e4`) percorrem `inv+0x28` com
##                       limite **64**: `0x80064820 addiu $v0,$v0,0x28`, `slti $v0,$v0,0x40`
##                       em `0x80064b88/0x80064bb0/0x80064d74/0x80064e38` e `addiu $v0,$zero,0x3f`
##                       em `0x80064afc` — que é EXATAMENTE o ITEM BOX (`inv+0x28`, 64 slots).
##     10   0x80051684   liga `gs+0x2120 |= 0x2000` e guarda o payload em `gs+0x21dc`; o
##                       consumidor `0x80023fa8` chama `load_overlay_task(1, 0x0c + u16@+0)` =
##                       overlay **RESULT/SELECT/STAFF_R/TITLE** (menu_overlays.md §4/§7.1)
##     11   0x800516a4   testa piso/AOT e `0x80078930` (bitmap de modelo carregado)
##     12   0x80051b40   **DANO**: `player+0xcc -= u16@+2` (`0x80051b9c..0x80051ba8`)
##     13   0x80051cb0   TRANSIÇÃO de sala: `gs+0x2154 = a0` e `0x800c7960 = 1`
##     14   0x80051d28   rotina per-frame `0x80051d60` com mensagens 7/8/9
##
## ⚠ **CORREÇÃO REGISTRADA**: o enum que o port herdou (`tools/scd_gameplay.py`,
## `port/data/sce_items.json`, `docs/formatos/exe.md §2.1`) é o do **RE2** e está ERRADO de 8 a
## 10: dizia `8=SCE_MOVE, 9=SCE_SAVE, 10=SCE_ITEMBOX`. No RE3 NTSC-U é `8=SAVE`, `9=BAÚ`,
## `10=overlay de fim`. Confirmação independente pelo DADO: `sce 8` e `sce 9` aparecem nas
## MESMAS 16 salas (15 em comum; só R111 tem 8 sem 9 e só R50B tem 9 sem 8) — máquina de
## escrever e baú lado a lado na sala de save.
const SCE_PORTA := 1
const SCE_PORTA_13 := 13
const SCE_ITEM := 2
const SCE_MENSAGEM := 4
const SCE_EVENTO := 5
const SCE_FLAG := 6
const SCE_SAVE := 8                ## ✅ máquina de escrever (procura Ink Ribbon 0x81)
const SCE_BAU := 9                 ## ✅ baú de itens (screen kind 2 → varre inv+0x28 × 64)
const SCE_FIM := 10                ## ✅ overlay RESULT/SELECT/STAFF_R/TITLE
const SCE_DANO := 12               ## ✅ dano por área
const SCE_TRANSICAO := 13
## Mantido só para não quebrar quem já usava o nome antigo. NÃO é "move": ver a tabela acima.
const SCE_MOVE := 8

## ── Bits do `sat` (byte +3), lidos do laço `0x800505ac` ──
## `0x01`/`0x02` = máscara de QUEM dispara (`a1` do laço: 1 = player, 2 = outros personagens;
## `0x80050758 and $v0,$v1,$a3`). `0x10` = **exige o pedido de AÇÃO**: o laço roda duas vezes,
## com `s6 = 0x10` e com `s6 = 0`, e `0x80050760/64` só aceita o AOT cujo `sat & 0x10 == s6`;
## a passagem `s6 = 0x10` só acontece quando `gs+0x77f4 & 0x00800000` está aceso
## (`0x80050bc4..0x80050bdc`). `0x20` = testa o PONTO DE SONDA 620 unidades à frente
## (`0x800505c8 addiu $v0,$zero,0x26c` + rotação por `char+0x6e`, `0x80078690`); `0x40` = testa
## a POSIÇÃO DO CORPO (`char+0x34/0x3c`); `0x80` = área em 4 pontos (payload em `+0x14`).
## Distribuição real nos 738 gatilhos: `0x31` (ação+sonda) e `0x41` (automático no corpo)
## cobrem tudo menos 6 casos — e casa com o jogo: save/baú/mensagem = `0x31`, flag/dano = `0x41`.
const SAT_ATOR_PLAYER := 0x01
const SAT_ACAO := 0x10
const SAT_SONDA := 0x20
const SAT_CORPO := 0x40
const SAT_QUAD := 0x80

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
## PAYLOAD cru do AOT (os 6 bytes que o handler recebe em `a0`): `opcode+0x0e` na forma de 2
## pontos e `opcode+0x16` quando `sat & 0x80`. É o que `sce 4` (mensagem), `sce 5` (evento),
## `sce 10` (overlay) e `sce 12` (dano) leem. Vazio quando o opcode não foi lido pela VM.
var payload: PackedByteArray = PackedByteArray()


func is_porta() -> bool:
	return sce == SCE_PORTA or sce == SCE_PORTA_13


func is_bau() -> bool:
	## Baú de itens (`sce 9`, handler `0x800514c4`). Ver a tabela de despacho no topo.
	return sce == SCE_BAU


func is_save() -> bool:
	## Máquina de escrever (`sce 8`, handler `0x80051388` → `0x800513cc` procura `0x81`).
	return sce == SCE_SAVE


func exige_acao() -> bool:
	## `sat & 0x10`: o AOT só é despachado na passagem que depende do pedido de AÇÃO.
	return (sat & SAT_ACAO) != 0


func usa_sonda() -> bool:
	return (sat & SAT_SONDA) != 0


func usa_corpo() -> bool:
	return (sat & SAT_CORPO) != 0


func disparado(corpo: Vector2i, sonda: Vector2i) -> bool:
	## Réplica da ordem do laço `0x800505ac`: primeiro o teste do CORPO (`sat & 0x40`,
	## `0x800509d4`), e só se ele falhar o teste da SONDA (`sat & 0x20`, `0x80050a24`).
	## Um AOT sem nenhum dos dois bits NUNCA dispara (o laço cai no `skip` em `0x80050a24`).
	if not ativo:
		return false
	if usa_corpo() and contem(corpo.x, corpo.y):
		return true
	if usa_sonda() and contem(sonda.x, sonda.y):
		return true
	return false


func evento_func() -> int:
	## `sce 5` (SCE_EVENT, handler `0x800512bc`): o payload é o MESMO descritor do opcode `0x04`
	## (`evt_exec`) — `u16@+0` = slot de thread (`0xff`/255 = qualquer livre de 2..9) e
	## `u8@+3` = **índice da função** do script da sala. Sítios: `0x800512dc lhu $a0,($a1)` e
	## `0x800512e0 lbu $a1,3($a1)` → `0x80052478`, que em `0x8005242c` faz
	## `PC = script_base + u16[func]` (`a2 = *(0x800e0144)`, `a1 = *(u16*)(a2 + func*2)`).
	## Devolve -1 quando o AOT não é evento ou o payload não foi lido.
	if sce != SCE_EVENTO or payload.size() < 4:
		return -1
	return payload[3]


func evento_slot() -> int:
	## `u16@+0` do payload: slot de thread pedido (255 = "qualquer livre", 2..9 no motor).
	if sce != SCE_EVENTO or payload.size() < 2:
		return -1
	return payload[0] | (payload[1] << 8)


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
