class_name Prologo
extends Node2D
## PRÓLOGO do RE3 — a "vinheta" narrada que vem depois de escolher a dificuldade e ANTES do
## FMV de abertura. Era o que faltava: o port ia da dificuldade direto para o vídeo.
##
## ── O achado: o prólogo é um SCRIPT, e o script está no arquivo de imagem ──
## `BIN/OPENING.BIN` (overlay 5, base **0x801c2000**) **não é tocador de vídeo** — é um
## interpretador de **13 opcodes** (tabela de handlers em `0x801c2f70`). O programa que ele
## roda são **80 bytes no fim de `ETC/OPENING1.DAT`** (offset `0x4b02a` de `0x4b07a`):
##
##     0x801c21a0  lui v1,0x8014 ; ori v1,0xb02a      -> PC = 0x8014b02a
##     0x801c21b8  sw  v1, 0x244(ctx = 0x801c3048)
##     0x801c2084  v0 = *(u8*)PC ; jalr *(0x801c2f70 + v0*4)     (o despachante)
##
## e `OPENING1.DAT` é lido em `0x80100000` (`0x801c2284`), logo `0x8014b02a` é o offset
## `0x4b02a` do arquivo. `tools/boot_assets.py` lê esses 80 bytes do arquivo do usuário e
## emite o programa decodificado em `boot_flow.json.prologo` — nada aqui é digitado à mão.
##
## Opcodes que o programa usa (todos com sítio no `boot_flow.json`): `0x0c` divisor de quadro,
## `0x07` rotina de desenho, `0x0a` pede recurso, `0x03`+`0x04` timer/espera, `0x08`/`0x09`
## fade in/out, `0x0b` trecho de narração (XA), `0x06` imagem de fundo, `0x05` espera o som,
## `0x02`/`0x01` fim.
##
## ── A linha do tempo MEDIDA (1665 quadros de 29,97 Hz = 55,56 s) ──
## | quadro | o que o script manda |
## |---:|---|
## | 0 | divisor 1, rotina de desenho 0, pede recurso 0, espera 30 |
## | 30 | fade-in 60, **narração trecho 0**, espera 260 |
## | 290 | fade-out 60, espera 60 |
## | 350 | **imagem 0** (Umbrella sobre a rua), fade-in 60, **trecho 1**, espera 215 |
## | 565 | fade-out 60, espera 60 |
## | 625 | divisor 2, rotina 1, fade-in 60, **trecho 2**, espera 600 |
## | 1225 | fade-out 60, espera 60 |
## | 1285 | divisor 1, **imagem 1** (Jill no apartamento), fade-in 60, **trecho 3**, espera 320 |
## | 1605 | fade-out 60, espera 60 |
## | 1665 | espera o fim do som e ENCERRA |
##
## Os números do script estão em **quadros de 29,97 Hz**: o `op 3` DOBRA o valor quando o
## divisor de quadro (`*(u8*)0x800d442c`) vale 1 (`0x801c2b9c`: `lh` + `sll 1`), e o `op 0x0c`
## troca o divisor entre 1 e 2 no meio do prólogo. Aqui 1 quadro = **2 ticks** do `boot.gd`.
##
## ── A narração e a legenda: MEDIDAS, e corrigem um alvo errado do port ──
## Os **4** trechos de XA (`op 0x0b`, args 0..3) duram **260, 215, 600 e 320** quadros = 1395
## no total = **46,55 s** a 29,97. A narração `BGM/gog/main06.ogg` tem **46,567 s** (ffprobe):
## 0,03 % de diferença. E `mod_BH3_Portuguese/xml/prologue.xml` tem **4 blocos** `<Text>` com
## **1414** quadros de marcação — 1,4 % dos 1395.
##
## ➜ Logo `prologue.xml` legenda **o prólogo**, e não o `opn.mp4` (que tem 90,6 s e é
## **dublado** em PT-BR). O port desenhava a legenda em cima do FMV; agora ela é daqui, e
## `tools/legendas_fmv.py` grava as cues sob a chave `prologo`.
##
## ── O que é ESCOLHA do port, declarada ──
## • **As duas primeiras partes ficam sem foto.** Além das 2 imagens de tela cheia de
##   `OPENING1.DAT` (que o `op 6` instala e que este arquivo desenha), o init do overlay sobe
##   **9 TIM de `OPENING0.DAT`** para a VRAM (`0x801c2224`/`0x801c225c`) e as três rotinas por
##   quadro que o `op 7` escolhe (`0x801c2488`, `0x801c2618`, `0x801c2788`) as desenham COM
##   PANORÂMICA. Essas rotinas **não foram decodificadas**: qual foto entra em cada instante e
##   como ela se move não está medido. Em vez de inventar foto e movimento, o port deixa a tela
##   preta com a legenda até o `op 6` (quadro 350) e, daí em diante, desenha as imagens
##   MEDIDAS. É 11,7 s de 55,6 s.
## • **A narração é tocada CORRIDA.** O original toca 4 trechos de XA com 60 quadros de fade
##   entre eles; o `Audio` do port não tem busca (`tocar_faixa` começa do zero), então a
##   `main06` toca de uma vez a partir do 1º trecho. A legenda usa o MESMO relógio da narração
##   (não o do script), então texto e voz continuam casados; o que desanda em relação ao
##   original é a foto, que segue o script.
## • **O fade** é o mesmo mecanismo do `boot.gd`: `ColorRect` 1280×960 com
##   `CanvasItemMaterial` em `BLEND_MODE_SUB`, que é a operação `abr=2` do PS1
##   (fundo − primitiva) usada pelos `op 8`/`op 9` (`0x8002a35c` com `0xffffff`/`0x000000`).
## • **Pular** é medido: `0x801c2120` testa `*(u16*)0x800cc834 & 0x900`, ou seja o prólogo é
##   pulável no original. Aqui qualquer botão pula (o `boot.gd` roteia).

const ESCALA := 4
const TELA := Vector2i(320, 240)
const LARGURA := 1280
const ALTURA := 960
const CAMINHO_JSON := "res://data/boot_flow.json"
const CAMINHO_LEGENDAS := "res://data/legendas_fmv.json"
## 1 quadro do script (29,97 Hz) = 2 ticks de tarefa (59,94 Hz) — ver `boot.gd`
const TICKS_POR_QUADRO := 2
const FPS := 30000.0 / 1001.0
## Faixa da narração: MEDIDA por duração contra a soma dos trechos de XA (ver o cabeçalho).
const NARRACAO := "main06"

signal terminou()
signal pediu_narracao(faixa: String)

var quadro := 0.0                              ## quadro de 29,97 Hz dentro do prólogo
var total := 0                                 ## 1665, lido do script
var imagem := -1                               ## índice da imagem no ar (-1 = nenhuma)
var legendas: Array = []

var _script: Array = []
var _prox := 0                                 ## próximo opcode a executar
var _ticks := 0
var _fade_ini := 0.0                           ## quadro em que o fade corrente começou
var _fade_dur := 0.0
var _fade_para_preto := false                  ## true = fade-out (a tela vai escurecendo)
var _fade_k := 1.0                             ## 0 = imagem limpa, 1 = preto
var _quadro_narracao := -1.0                   ## quadro em que a narração começou
var _fim := false
var _sub: ColorRect
var _texturas: Array[Texture2D] = []
var _cue := -1


func _ready() -> void:
	scale = Vector2(ESCALA, ESCALA)
	carregar()


func carregar() -> bool:
	## Lê o script decodificado, as legendas e as 2 imagens em HD. `false` = faltou dado.
	var ok := true
	var d: Dictionary = {}
	if FileAccess.file_exists(CAMINHO_JSON):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_JSON))
		if raw is Dictionary:
			d = raw
	var p: Variant = d.get("prologo")
	if p is Dictionary and bool((p as Dictionary).get("ok", false)):
		_script = (p as Dictionary).get("script", [])
		total = int((p as Dictionary).get("quadros_total", 0))
	else:
		push_warning("Prologo: boot_flow.json sem o script do prólogo — rode "
			+ "`NOSTALGIA_OUT=port python tools/boot_assets.py`")
		ok = false
	if FileAccess.file_exists(CAMINHO_LEGENDAS):
		var rl: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_LEGENDAS))
		if rl is Dictionary:
			var v: Variant = ((rl as Dictionary).get("videos", {}) as Dictionary).get("prologo")
			if v is Dictionary:
				legendas = (v as Dictionary).get("legendas", [])
	_texturas = []
	for i in 2:
		var tex := AssetIO.texture("BOOT/prologo%d.webp" % i)
		if tex == null:
			ok = false
		_texturas.append(tex)
	if _sub == null:
		_sub = ColorRect.new()
		_sub.name = "FadeSub"
		_sub.size = Vector2(LARGURA, ALTURA)
		_sub.color = Color.BLACK
		_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sub.z_index = 300
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
		_sub.material = m
		add_child(_sub)
	return ok


func comecar() -> void:
	## Rearma o prólogo do zero (o `boot.gd` chama ao entrar no passo).
	quadro = 0.0
	_ticks = 0
	_prox = 0
	imagem = -1
	_cue = -1
	_fim = false
	_quadro_narracao = -1.0
	# a tela entra PRETA: o script só clareia no 1º `op 8` (fade-in), no quadro 30
	_fade_k = 1.0
	_fade_dur = 0.0
	queue_redraw()


func avancar(ticks := 1) -> void:
	## Avança `ticks` ticks de tarefa (59,94 Hz). Quem conta o tempo é o `boot.gd`.
	if _fim:
		return
	_ticks += ticks
	quadro = float(_ticks) / float(TICKS_POR_QUADRO)
	while _prox < _script.size():
		var e: Dictionary = _script[_prox]
		if float(e.get("quadro", 0)) > quadro:
			break
		_aplicar(e)
		_prox += 1
	_atualizar_fade()
	if total > 0 and quadro >= float(total) and not _fim:
		_encerrar()
	queue_redraw()


func _aplicar(e: Dictionary) -> void:
	## Executa um opcode do script. Só os que TÊM efeito visível/audível no port; os outros
	## (divisor de quadro, rotina de desenho, pede recurso) ficam registrados no JSON.
	match int(e.get("op", -1)):
		0x06:                                   ## imagem de fundo (0x801c2c4c)
			imagem = int(e.get("arg", -1))
		0x08:                                   ## fade-in (0x801c2d0c): 0xffffff -> 0x000000
			_fade_ini = float(e.get("quadro", 0))
			_fade_dur = float(e.get("arg", 0))
			_fade_para_preto = false
		0x09:                                   ## fade-out (0x801c2d8c): 0x000000 -> 0xffffff
			_fade_ini = float(e.get("quadro", 0))
			_fade_dur = float(e.get("arg", 0))
			_fade_para_preto = true
		0x0B:                                   ## trecho de narração (0x801c2e70, XA)
			if _quadro_narracao < 0.0:
				_quadro_narracao = float(e.get("quadro", 0))
				pediu_narracao.emit(NARRACAO)
		0x01, 0x02:                             ## fim do script
			_encerrar()


func _atualizar_fade() -> void:
	if _fade_dur > 0.0:
		var t := clampf((quadro - _fade_ini) / _fade_dur, 0.0, 1.0)
		_fade_k = t if _fade_para_preto else 1.0 - t
	if _sub != null:
		# `abr=2` do PS1 = fundo − primitiva: subtrair cinza `k` escurece linearmente
		_sub.color = Color(_fade_k, _fade_k, _fade_k, 1.0)
		_sub.visible = _fade_k > 0.0


func quadro_da_legenda() -> float:
	## A legenda usa o relógio da NARRAÇÃO (o 1º trecho de XA), não o do script — é o que
	## mantém texto e voz casados mesmo com a narração tocando corrida (ver o cabeçalho).
	if _quadro_narracao < 0.0:
		return -1.0
	return quadro - _quadro_narracao


func linhas_atuais() -> Array:
	var q := quadro_da_legenda()
	if q < 0.0:
		return []
	return VideoFmv.linhas_de(legendas, VideoFmv.cue_em(legendas, q / FPS))


func pular() -> void:
	## `0x801c2120` testa `*(u16*)0x800cc834 & 0x900`: o prólogo é pulável no original.
	_encerrar()


func _encerrar() -> void:
	if _fim:
		return
	_fim = true
	terminou.emit()


func terminou_ja() -> bool:
	return _fim


func _draw() -> void:
	## A imagem de fundo é 1280×960 e o nó tem escala 4 → desenhar em 320×240 dá 1:1.
	draw_rect(Rect2(0, 0, TELA.x, TELA.y), Color.BLACK)
	if imagem >= 0 and imagem < _texturas.size() and _texturas[imagem] != null:
		draw_texture_rect(_texturas[imagem], Rect2(0, 0, TELA.x, TELA.y), false)
	VideoFmv.desenhar_legenda(self, linhas_atuais())
