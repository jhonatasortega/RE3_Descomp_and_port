class_name VideoFmv
extends Node2D
## Tocador de FMV em HD com **legenda em PT-BR** sincronizada pela marcação do mod.
##
## ── O vídeo ──
## Os FMV vêm de `zmovie/*.mp4` da instalação do usuário: **1280×960, h264, 29,97 fps,
## áudio dublado em português** (`docs/formatos/localizacao_ptbr.md` §3). O Godot 4 só toca
## **Ogg Theora** nativamente, então `tools/video_ogv.py` transcodifica para
## `assets/ZMOVIE/<nome>.ogv` mantendo resolução e taxa — a decisão e o custo dos três
## caminhos possíveis estão no docstring daquele script.
##
## O `.ogv` é carregado de **fora do `.pck`** (`VideoStreamTheora.file` = caminho absoluto).
## Isso foi SONDADO, não suposto: `port/dev/diag_video.gd` mostra `playing=true` e a posição
## andando, inclusive em `--headless`. Sem isso o tocador teria de mudar de estratégia,
## porque `port/assets/` tem `.gdignore` (os assets são da Capcom e não são distribuídos).
##
## ── A legenda ──
## `port/data/legendas_fmv.json`, gerado por `tools/legendas_fmv.py` a partir de
## `mod_BH3_Portuguese/xml/prologue.xml` (abertura) e `epilogue.xml` (final). A marcação
## `{clear N}` / `{timed N}` / `{scroll N}` é do motor Classic REbirth — as oito diretivas
## estão PROVADAS como literais no `ddraw.dll` (`clear %d` em `+0x2fe180`, `timed %d` em
## `+0x2fe18c`, …); a SEMÂNTICA "segura N quadros e limpa" é leitura declarada, sustentada
## pela soma fechar dentro da duração do mp4. Ver o docstring da ferramenta.
##
## O texto é desenhado com a **fonte do jogo** (`present/texto.gd`, atlas HD europeu com os
## acentos), com a **sombra preta em (+1,+1)** — que é a convenção do próprio RE3 (os SPRT
## do ramo Mercenaries do `TITLE.BIN` fazem exatamente isso, `0x80194894`+).
##
## ── O que é ESCOLHA do port, declarada ──
## • **Posição da legenda na tela.** Não medi onde a versão de PC desenha o prólogo. Uso o
##   rodapé do espaço 320×240, centralizado, com margem de 24 px — nada disso é medida.
## • **Pular com botão.** O sítio que lê o pad durante o FMV não foi medido (o do logo CAPCOM
##   foi: `0x8019432c`, `0x800cc834 & 0x800`). Aqui pular é afordância do port.

const ESCALA := 4                              ## 1280/320 — o quadro do port é 4× o do PS1
const TELA := Vector2i(320, 240)
const CAMINHO_LEGENDAS := "res://data/legendas_fmv.json"
## Rodapé: `y` da PRIMEIRA linha quando há 2 linhas. Declarado (não medido).
const LEGENDA_Y := 200
const LEGENDA_MARGEM_X := 24
const COR_LEGENDA := Color(0.94, 0.94, 0.90)
const COR_SOMBRA := Color(0.0, 0.0, 0.0)

signal terminou()

var nome := ""
var player: VideoStreamPlayer
var legendas: Array = []                       ## cues do JSON, em ordem de tempo
var legendar := true
var pulavel := true
var _dados: Dictionary = {}
var _cue := -1
var _tocando := false


func _ready() -> void:
	scale = Vector2(ESCALA, ESCALA)
	z_index = 200
	carregar_dados()


func carregar_dados() -> bool:
	## Lê `data/legendas_fmv.json`. Sem ele o vídeo toca, só não legenda.
	if not FileAccess.file_exists(CAMINHO_LEGENDAS):
		push_warning("VideoFmv: %s ausente — rode `NOSTALGIA_OUT=port python "
			% CAMINHO_LEGENDAS + "tools/legendas_fmv.py`")
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_LEGENDAS))
	if not (raw is Dictionary):
		return false
	_dados = raw
	return true


func legendas_de(qual: String) -> Array:
	## As cues de um vídeo (lista vazia se não houver legenda para ele).
	var vids: Dictionary = _dados.get("videos", {})
	var v: Variant = vids.get(qual)
	if not (v is Dictionary):
		return []
	return (v as Dictionary).get("legendas", [])


static func cue_em(cues: Array, segundos: float) -> int:
	## Índice da cue que cobre `segundos`, ou -1. As cues são contíguas e ordenadas:
	## `[inicio, inicio + duração)`. Busca linear — são 17 no maior caso.
	for i in cues.size():
		var c: Dictionary = cues[i]
		var t0 := float(c.get("segundo_inicio", 0.0))
		var t1 := t0 + float(c.get("segundos", 0.0))
		if segundos >= t0 and segundos < t1:
			return i
	return -1


static func linhas_de(cues: Array, i: int) -> Array:
	if i < 0 or i >= cues.size():
		return []
	var c: Dictionary = cues[i]
	var out: Array = []
	for l: Variant in c.get("linhas", []):
		if String(l).strip_edges() != "":
			out.append(String(l))
	return out


func linhas_atuais() -> Array:
	return linhas_de(legendas, _cue)


func caminho_do_video(qual: String) -> String:
	return AssetIO.path("ZMOVIE/%s.ogv" % qual)


func existe(qual: String) -> bool:
	return FileAccess.file_exists(caminho_do_video(qual))


func tocar(qual: String) -> bool:
	## Começa o vídeo. `false` = não há `.ogv` (o chamador deve seguir sem FMV).
	nome = qual
	legendas = legendas_de(qual) if legendar else []
	_cue = -1
	var p := caminho_do_video(qual)
	if not FileAccess.file_exists(p):
		push_warning("VideoFmv: %s não existe — rode `NOSTALGIA_OUT=port python "
			% p + "tools/video_ogv.py --abertura`")
		return false
	if player == null:
		player = VideoStreamPlayer.new()
		player.name = "Stream"
		player.expand = true
		player.size = Vector2(TELA.x, TELA.y)     ## o nó tem escala 4 -> 1280×960
		player.audio_track = 0
		# O filho desenha DEPOIS do `_draw()` do pai — sem isto o vídeo cobre a legenda
		# (foi exatamente o que aconteceu na 1ª captura: FMV certo, legenda invisível).
		player.show_behind_parent = true
		add_child(player)
	var vs := VideoStreamTheora.new()
	vs.file = p
	player.stream = vs
	# `play()` exige o nó JÁ dentro da árvore (sonda `diag_video.gd`).
	if player.is_inside_tree():
		player.play()
	_tocando = true
	print("[fmv] %s (%d legendas)" % [qual, legendas.size()])
	return true


func pular() -> void:
	## Afordância do port (o sítio do pad durante o FMV não foi medido).
	if not _tocando:
		return
	if player != null:
		player.stop()
	_fim()


func tocando() -> bool:
	return _tocando


func posicao() -> float:
	return player.stream_position if player != null else 0.0


func _fim() -> void:
	_tocando = false
	_cue = -1
	queue_redraw()
	terminou.emit()


func _process(_delta: float) -> void:
	if not _tocando:
		return
	if player != null and not player.is_playing():
		_fim()
		return
	var novo := cue_em(legendas, posicao())
	if novo != _cue:
		_cue = novo
		queue_redraw()


func _draw() -> void:
	if not _tocando:
		return
	var linhas := linhas_atuais()
	if linhas.is_empty():
		return
	var largura_max := TELA.x - 2 * LEGENDA_MARGEM_X
	# Cada linha da marcação (`\n` do XML) é uma linha da tela; se estourar a largura, o
	# `Texto.quebrar` reparte por PALAVRA (é o que o desenho do jogo faz).
	var finais: Array[String] = []
	for l: Variant in linhas:
		for q: String in Texto.quebrar(String(l), largura_max):
			finais.append(q)
	var y := LEGENDA_Y - (finais.size() - 1) * Texto.ALTURA_LINHA
	for l: String in finais:
		var x := (TELA.x - Texto.largura(l)) / 2
		Texto.desenhar(self, l, Vector2i(x + 1, y + 1), 0, COR_SOMBRA)
		Texto.desenhar(self, l, Vector2i(x, y), 0, COR_LEGENDA)
		y += Texto.ALTURA_LINHA
