class_name EspBrilho
extends Node2D
## Brilho ("cintilar") do item no chão: o efeito **ESP** do jogo, decodificado — não uma luz.
##
## ── O que o motor faz (provado) ──
## `0x800525c0` (passe per-frame dos objetos de sala): se `be_flg & 1` e o `iflags` do item tem
## bit 7, cria um efeito com `id = 0x0705 | ((iflags & 0x60) << 19)`, ancorado na matriz do objeto
## com deslocamento `(0, -90, 0)` — Y negativo é PARA CIMA no PS1, então **90 unidades acima**.
## Varrendo os 330 itens do jogo: **28 têm brilho e todos com variante 0** (`iflags & 0x60 == 0`),
## logo a paleta é sempre a mesma e não há escolha a fazer aqui.
##
## `0x0705` = banco de **tipo 0x05** do `ETC/CORE00.ESP`, **efeito 7**. Esse efeito NÃO desenha
## (`flags = 0x8800`: vivo + segue matriz, `draw=0 anim=0`): é um **CONTROLADOR**, handler `0x32`
## = `0x800217b4`, com dois estados em `slot+1` (desmontado instrução por instrução):
##
##   estado 0 (`0x800217e4`): cria o filho `id = 0x905` (mesmo banco, efeito 9) passando a matriz
##       do dono (`slot+0x38`) e a paleta em `((slot[0xb3] + 1) & 0xf) << 24`; sorteia o próximo
##       intervalo e zera o contador (`sh $zero, 0xb4`):
##           `a0 = tabela_de_bytes[rand()]`   (tabela em `0x80098728`)
##           `intervalo = (a0 % 50) + 40`  ->  `slot+0xb6`
##       (o módulo é `multu` por `0x51eb851f` + `mfhi >> 4` = ÷50, depois `- 50*q`; o `+40` é o
##        `addiu $a0, 0x28` em `0x80021878`)
##   estado 1 (`0x80021884`): `slot+0xb4 += 1`; quando passa de `slot+0xb6`, volta ao estado 0.
##
## **Por isso o brilho PISCA e não fica aceso**: ele reaparece a cada **40..89 quadros de 30 Hz**
## (1,3 s a 3,0 s; média 65,7 na tabela real).
##
## O filho `0x905` (efeito 9 do banco): `flags = 0xb803` (desenha, anima, segue a matriz do dono),
## `a_start = 14` → tabela A entradas 14..21 = **8 quadros de 1 tick cada**, 16×16 px, apontando
## B[11], B[12], B[11], B[10], B[11], B[13], B[11], B[10]; a entrada A22 tem `dur = 0`, que MATA o
## efeito. `tpage_or = 0x20` → `abr = 1` = **aditivo** (B+F). Pivô das entradas B = `(-8,-8)`,
## ou seja centrado.
##
## Sprites em `assets/ESP/t05_A{nn}_B{nn}_v0_16x16.png`, extraídos por `tools/esp_decode.py`.
##
## ── O que aqui é decisão do port, declarada ──
## • **Tamanho na tela:** o campo `size` da tabela A diz 16 (texels) e o quad NÃO é orientado pela
##   matriz (bit 9 de `flags` está apagado), ou seja é sprite de tela. Desenho 16 px do espaço
##   320×240 do PS1, escalados pelo fator do quadro do port (1280/320 = 4). O `esp_draw_all`
##   (`0x80022990`) não foi desmontado, então a projeção exata do tamanho **não está provada**.
## • **Ordem de desenho:** entra acima do 3D e ABAIXO dos recortes de oclusão, para móvel na
##   frente cobrir o brilho. No PS1 o efeito entra na Ordering Table com chave de profundidade —
##   a fidelidade fina disso é o item de oclusão, não este.
## • **Sorteio:** uso os 64 primeiros bytes REAIS da tabela `0x80098728` (abaixo), indexados por um
##   contador por item, em vez de um `rand()` do Godot: o dado é do jogo e fica determinístico.

## Quadros do filho `0x905`: (entrada A, entrada B) de A14..A21 — 1 tick cada, na ordem.
const QUADROS: Array[Vector2i] = [
	Vector2i(14, 11), Vector2i(15, 12), Vector2i(16, 11), Vector2i(17, 10),
	Vector2i(18, 11), Vector2i(19, 13), Vector2i(20, 11), Vector2i(21, 10),
]
const LADO_PS1 := 16                  ## `size` da tabela A das entradas A14..A21
const ALTURA_PS1 := 90                ## deslocamento `(0,-90,0)` do `0x800525c0`
const TELA_PS1_W := 320.0             ## o menu/HUD do jogo vive em 320×240 (provado no recomp)
const INTERVALO_BASE := 40            ## `addiu $a0, 0x28` em `0x80021878`
const INTERVALO_MOD := 50             ## divisor do módulo (`multu 0x51eb851f`, `mfhi >> 4`)

## PALETA. Em `esp_spawn` (`0x8001b57c`) a variante desloca o valor de CLUT: `clut + var*0x40`,
## e como `y = clut >> 6`, cada variante é **+1 linha de CLUT** na VRAM. O banco declara CLUT
## `0x7a11` → linha 488. E o handler `0x32` cria o filho com **variante + 1** (`0x80021804`:
## `lbu $a1,0xb3($s0)` · `addiu $a1,$a1,1` · `andi 0xf` · `<< 24`).
## Como TODOS os 28 itens com brilho têm variante 0, a faísca sai na variante **1** = linha 489,
## que é a paleta BRANCA (`#ffffff #eeeeee #e6e6e6 …`). A linha 488 (variante 0) é vermelho quase
## preto — foi o que apareceu na primeira tentativa, um borrão escuro em vez de faísca.
const VARIANTE := 1

## Primeiros 64 bytes da tabela de sorteio do EXE em `0x80098728` (lidos do binário).
const TABELA_RAND: Array[int] = [
	21, 103, 44, 192, 19, 175, 9, 249, 99, 189, 12, 128, 23, 69, 92, 112,
	196, 86, 22, 11, 3, 218, 166, 46, 66, 140, 206, 30, 110, 116, 255, 89,
	34, 208, 14, 180, 104, 35, 172, 238, 210, 65, 33, 222, 236, 194, 161, 29,
	109, 36, 188, 126, 250, 147, 234, 16, 43, 64, 84, 38, 244, 133, 54, 96,
]

class Fonte:
	extends RefCounted
	## Um item com brilho: a âncora no mundo e o estado da máquina do handler `0x32`.
	var mundo := Vector3i.ZERO         ## posição do OBJETO (o +90 é aplicado no desenho)
	var estado := 1                    ## 0 = criar o cintilar · 1 = esperando (como slot+1)
	var contador := 0                  ## slot+0xb4
	var intervalo := 0                 ## slot+0xb6
	var quadro := -1                   ## índice em QUADROS enquanto o filho está vivo (-1 = morto)
	var sorteios := 0                  ## por onde anda na TABELA_RAND
	var no: Sprite2D = null

var fontes: Array[Fonte] = []
var _texturas: Array[Texture2D] = []
var _escala := 4.0


func _init() -> void:
	name = "EspBrilho"


func carregar(largura_do_quadro: int) -> bool:
	## Carrega os 8 quadros do cintilar. Devolve false se os assets não foram gerados
	## (`python tools/esp_decode.py dump port/assets/ESP`) — e então o brilho simplesmente não
	## aparece, em vez de virar um retângulo inventado.
	_escala = float(largura_do_quadro) / TELA_PS1_W
	_texturas.clear()
	for q: Vector2i in QUADROS:
		var rel := "ESP/t05_A%02d_B%02d_v%d_%dx%d.png" % [q.x, q.y, VARIANTE, LADO_PS1, LADO_PS1]
		var tex := AssetIO.texture(rel)
		if tex == null:
			_texturas.clear()
			return false
		_texturas.append(tex)
	return true


func definir_fontes(posicoes: Array[Vector3i]) -> void:
	## Troca a lista de itens com brilho (chamado quando a sala/os itens mudam).
	for f: Fonte in fontes:
		if f.no != null:
			f.no.queue_free()
	fontes.clear()
	if _texturas.is_empty():
		return
	var i := 0
	for p: Vector3i in posicoes:
		var f := Fonte.new()
		f.mundo = p
		# escalona o instante do primeiro cintilar pela ordem do item: no jogo cada efeito nasce
		# com seu próprio sorteio, então dois itens da mesma sala não piscam juntos.
		f.sorteios = i
		f.intervalo = _sortear(f)
		f.no = Sprite2D.new()
		f.no.name = "Cintilar_%d" % i
		f.no.centered = true                     ## pivô (-8,-8) das entradas B = centrado
		f.no.scale = Vector2(_escala, _escala)
		f.no.visible = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD    ## `abr = 1` (B+F)
		f.no.material = mat
		add_child(f.no)
		fontes.append(f)
		i += 1


func avancar(cam: Camera3D) -> void:
	## Um tick de 30 Hz: roda a máquina de estados e reposiciona os sprites.
	if _texturas.is_empty() or cam == null:
		return
	for f: Fonte in fontes:
		var nasceu := false
		# ── o CONTROLADOR (handler `0x32`), que conta independente do filho ──
		if f.estado == 0:
			f.quadro = 0                         ## nasce o filho `0x905` JÁ no quadro 0
			nasceu = true
			f.contador = 0
			f.intervalo = _sortear(f)
			f.estado = 1
		else:
			f.contador += 1
			if f.contador > f.intervalo:
				f.estado = 0
		# ── o FILHO: 8 quadros de 1 tick; a entrada A22 tem `dur = 0` e mata o efeito ──
		if f.quadro >= 0 and not nasceu:
			f.quadro += 1
			if f.quadro >= QUADROS.size():
				f.quadro = -1
		_desenhar(f, cam)


func _desenhar(f: Fonte, cam: Camera3D) -> void:
	if f.no == null:
		return
	var vivo := f.quadro >= 0 and f.quadro < QUADROS.size()
	if not vivo:
		f.no.visible = false
		return
	var alvo := Coords.to_godot_i(f.mundo.x, f.mundo.y - ALTURA_PS1, f.mundo.z)
	if cam.is_position_behind(alvo):
		f.no.visible = false
		return
	f.no.texture = _texturas[f.quadro]
	f.no.position = cam.unproject_position(alvo)
	f.no.visible = true


func _sortear(f: Fonte) -> int:
	## `intervalo = (tabela[rand()] % 50) + 40` — o sorteio do handler `0x32`.
	var b: int = TABELA_RAND[f.sorteios % TABELA_RAND.size()]
	f.sorteios += 1
	return (b % INTERVALO_MOD) + INTERVALO_BASE
