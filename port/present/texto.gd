class_name Texto
extends RefCounted
## Desenho de TEXTO com a fonte do jogo (P6-06). Recomp, não uma `Font` do Godot.
##
## Fonte: `docs/decomp/notes/menu_texto.md` + `data/re3_font.json` (gerado por
## `tools/menu_texto.py`, lido do `SLUS_009.23` e do `ETC/TEXU.TIM`).
##
## ── O atlas ──
## `ETC/TEXU.TIM`: 4bpp, **1024×256**, carregado na VRAM em (768,256), com **60 CLUTs** em
## (256,480). Cada glifo é uma célula de **14×14** numa grade de **18 colunas**:
##
##     cod = ASCII - 0x24        (para ASCII 0x24..0x7a; o espaço 0x20 vira cod 0)
##     u = (cod % 18) * 14
##     v = (cod / 18) * 14 + 28      (o +28 é a base do banco normal)
##
## ── A fonte é PROPORCIONAL ──
## Tabela em `0x80098dd0`, 87 entradas: cada glifo tem `trim_left` (quantos pixels pular à
## esquerda) e `advance` (quanto andar depois). Ex.: `A` avança 14, `i` avança 10 com trim 4,
## `.` avança 7 com trim 2. Ignorar isso dá texto com buracos — é o erro clássico de tratar
## fonte de RE como monoespaçada.
##
## Altura de linha: **16**.
##
## ── Cor ──
## A cor é a linha de CLUT (60 disponíveis). O port recebe o índice e usa o PNG correspondente
## em `assets/FONT/TEXU_clut_y{480+i}.png` — mesma ideia do STMOJIU na tela de status.

const CAMINHO := "res://data/re3_font.json"
const CAMINHO_PT := "res://data/re3_font_pt.json"
## Atlas HD da fonte: `misc/AED42717` (1024×1024 = 4× a página de VRAM 256×256), copiado para
## `assets/FONT/hd_texu.webp`. É a fonte EUROPEIA do pack, a que tem os glifos acentuados.
const ATLAS_HD := "FONT/hd_texu.webp"
## Métrica MEDIDA do atlas HD (caixa de tinta por glifo, em unidades SD) — gerada por
## `port/dev/hd_fonte_metrica.gd`. Foi o que resolveu o texto sair espaçado: a métrica do EXE é
## do desenho SD (o `A` avança 14) e a do `encoding.xml` é de uma terceira fonte; a que vale para
## ESTE atlas é a que se mede nele (o `A` tem 8 px de tinta começando em x=2, avanço 9).
const CAMINHO_HD_METRICA := "res://data/re3_font_hd_metrica.json"
const CELULA := 14
const COLUNAS := 18
const V_BASE := 28                     ## base do banco "normal" na grade
const ALTURA_LINHA := 16
const CLUT_BASE := 480

static var _dados: Dictionary = {}
static var _largura: Dictionary = {}   ## cod -> {trim_left, advance}
static var _carregado := false
static var _atlas: Dictionary = {}     ## índice de CLUT -> Texture2D (SD, por paleta)
static var _hd: Texture2D = null       ## atlas HD (uma coloração só, sem paleta)
static var _hd_tentado := false
## `caractere -> código` da fonte HD, com os ACENTOS. Lido da folha auto-rotulada (ver
## `tools/font_pt.py` e `port/dev/hd_fonte_folha.gd`), porque o `encoding.xml` do mod mapeia
## para a fonte ALTERNATIVA dele (lá `0x58` é `ã`; neste atlas `0x58` é `ä`).
static var _mapa_hd: Dictionary = {}
static var _base_sem_acento: Dictionary = {}
## Métrica do glifo NA FONTE HD, por caractere: `{width, indent}` do `encoding.xml` do mod.
## O EXE tem a métrica do SD (`advance`/`trim_left` da tabela `0x80098dd0`), que é de OUTRO
## desenho: no SD o `A` avança 14 com trim 0, no HD ele mede 10 com indent 4. Usar a do SD no
## atlas HD deixa o texto espaçado — foi o que apareceu no primeiro teste.
static var _metrica_hd: Dictionary = {}
static var _tinta_hd: Dictionary = {}   ## cod -> {x, w, adv} medido no atlas HD


static func _carregar() -> void:
	if _carregado:
		return
	_carregado = true
	if not FileAccess.file_exists(CAMINHO):
		push_error("Texto: %s ausente — rode `python tools/menu_texto.py --font`" % CAMINHO)
		return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO))
	if not (raw is Dictionary):
		return
	_dados = raw
	for e: Dictionary in (_dados.get("tabela_larguras", {}) as Dictionary).get("entradas", []):
		_largura[int(e.get("code", 0))] = {
			"trim": int(e.get("trim_left", 0)), "adv": int(e.get("advance", CELULA))}
	if FileAccess.file_exists(CAMINHO_HD_METRICA):
		var rm: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(CAMINHO_HD_METRICA))
		if rm is Dictionary:
			_tinta_hd = (rm as Dictionary).get("glifos", {})
	if FileAccess.file_exists(CAMINHO_PT):
		var rp: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAMINHO_PT))
		if rp is Dictionary:
			_mapa_hd = (rp as Dictionary).get("char_para_codigo_hd", {})
			_base_sem_acento = (rp as Dictionary).get("base_sem_acento", {})
			for e: Dictionary in (rp as Dictionary).get("entradas", []):
				pass
			for e: Dictionary in (rp as Dictionary).get("entradas", []):
				var ch := String(e.get("char", ""))
				if ch == "" or _metrica_hd.has(ch):
					continue
				var w: Variant = e.get("width")
				var ind: Variant = e.get("indent")
				if w == null:
					continue
				_metrica_hd[ch] = {"adv": int(w), "trim": int(ind) if ind != null else 0}


static func atlas(clut := 0) -> Texture2D:
	_carregar()
	if _atlas.has(clut):
		return _atlas[clut]
	var tex := AssetIO.texture("FONT/TEXU_clut_y%d.png" % (CLUT_BASE + clut))
	_atlas[clut] = tex
	return tex


static func codigo(c: int) -> int:
	## `cod = ASCII - 0x24`, com o espaço (0x20) em 0. **Acentos**: fora da faixa ASCII, procura no
	## mapa da fonte HD (`Á`=138, `ç`=115, `ã`=159, `à`=160, `ê`=103, `õ`=129…). Antes eu devolvia
	## -1 e o caractere era SILENCIOSAMENTE PULADO — era o que comia as letras acentuadas.
	if c == 0x20:
		return 0
	if c >= 0x24 and c <= 0x7A:
		return c - 0x24
	_carregar()
	var ch := String.chr(c)
	if _mapa_hd.has(ch):
		return int(_mapa_hd[ch])
	return -1


static func codigo_do_char(ch: String) -> int:
	return codigo(ch.unicode_at(0)) if ch.length() > 0 else -1


static func _cod_metrica(cod: int) -> int:
	## Código a usar para LARGURA. Os acentuados estão acima de `0x56`, onde a tabela do EXE
	## termina, então usa-se a métrica do caractere BASE (`á` mede como `a`, `Ç` como `C`).
	## Declarado: escolha do port, não medida — o EXE não tem tabela para esses códigos.
	if _largura.has(cod):
		return cod
	for ch: String in _mapa_hd:
		if int(_mapa_hd[ch]) != cod:
			continue
		var base: String = String(_base_sem_acento.get(ch, ""))
		if base != "":
			return codigo(base.unicode_at(0))
		break
	return cod


static func avanco(cod: int) -> int:
	_carregar()
	var d: Dictionary = _largura.get(_cod_metrica(cod), {})
	return int(d.get("adv", CELULA))


static func trim(cod: int) -> int:
	_carregar()
	var d: Dictionary = _largura.get(_cod_metrica(cod), {})
	return int(d.get("trim", 0))


static func atlas_hd() -> Texture2D:
	## Atlas HD (4×). `null` = não instalado, e aí o desenho cai no SD por paleta.
	if not _hd_tentado:
		_hd_tentado = true
		if AssetIO.exists(ATLAS_HD):
			_hd = AssetIO.texture(ATLAS_HD)
	return _hd


static func metrica(ch: String, hd: bool) -> Dictionary:
	## `{adv, trim, w}` do caractere. Em **HD** usa a caixa de tinta MEDIDA no próprio atlas; em
	## **SD** usa a tabela do EXE (`advance`/`trim_left`). São desenhos diferentes, com métricas
	## diferentes — misturar as duas é o que deixava o texto espaçado.
	_carregar()
	var cod := codigo_do_char(ch)
	if cod < 0:
		return {"adv": 0, "trim": 0, "w": 0}
	if hd and _tinta_hd.has(str(cod)):
		var m: Dictionary = _tinta_hd[str(cod)]
		return {"adv": int(m["adv"]), "trim": int(m["x"]), "w": int(m["w"])}
	var a := avanco(cod)
	return {"adv": a, "trim": trim(cod), "w": a}


static func largura(s: String, hd := true) -> int:
	## Largura em pixels de tela (320×240) de uma linha, pela tabela proporcional.
	var w := 0
	var usa_hd := hd and atlas_hd() != null
	for i in s.length():
		var ch := s[i]
		if codigo_do_char(ch) < 0:
			continue
		w += int(metrica(ch, usa_hd)["adv"])
	return w


static func quebrar(s: String, largura_max: int) -> Array[String]:
	## Quebra em palavras respeitando a largura em pixels (o desenho do jogo quebra por
	## largura, não por número de caracteres).
	var linhas: Array[String] = []
	var atual := ""
	for palavra: String in s.split(" ", false):
		var teste := palavra if atual == "" else atual + " " + palavra
		if largura(teste) <= largura_max or atual == "":
			atual = teste
		else:
			linhas.append(atual)
			atual = palavra
	if atual != "":
		linhas.append(atual)
	return linhas


static func desenhar(ci: CanvasItem, s: String, onde: Vector2i, clut := 0,
		cor := Color.WHITE) -> int:
	## Desenha uma linha e devolve a largura usada. Coordenadas no espaço 320×240.
	# HD primeiro: é a fonte EUROPEIA do pack, a única com os glifos acentuados. O SD (TEXU do
	# NTSC-U) não tem acento nenhum, então em PT-BR ele sempre comeria letras.
	var tex := atlas_hd()
	var fator := 4
	if tex == null:
		tex = atlas(clut)
		fator = 1
	if tex == null:
		return 0
	var x := onde.x
	for i in s.length():
		var ch := s[i]
		var cod := codigo_do_char(ch)
		if cod < 0:
			continue
		var u := (cod % COLUNAS) * CELULA
		var v := int(cod / COLUNAS) * CELULA + V_BASE
		var m := metrica(ch, fator == 4)
		var t := int(m["trim"])
		var a := int(m["adv"])
		var w := int(m.get("w", a))
		# recorta só a TINTA (largura `w` a partir de `trim`) e anda o avanço
		ci.draw_texture_rect_region(tex, Rect2(x, onde.y, w, CELULA),
			Rect2i((u + t) * fator, v * fator, w * fator, CELULA * fator), cor)
		x += a
	return x - onde.x


static func desenhar_bloco(ci: CanvasItem, s: String, caixa: Rect2i, clut := 0,
		cor := Color.WHITE) -> int:
	## Desenha várias linhas dentro de uma caixa, quebrando por largura. Devolve quantas linhas.
	var linhas := quebrar(s, caixa.size.x)
	var y := caixa.position.y
	var n := 0
	for l: String in linhas:
		if y + CELULA > caixa.position.y + caixa.size.y:
			break
		desenhar(ci, l, Vector2i(caixa.position.x, y), clut, cor)
		y += ALTURA_LINHA
		n += 1
	return n
