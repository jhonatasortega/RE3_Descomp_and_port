class_name AssetIO
extends RefCounted
## Carregamento de assets em RUNTIME, de fora do `.pck` (P1-02 / política P7-06).
##
## `port/assets/` tem `.gdignore`: o editor não importa nada de lá, **de propósito**. Dois
## motivos, na ordem de importância:
##
## 1. **Licença:** os assets são da Capcom / do Seamless HD Project e não podem ser
##    distribuídos. O build sai sem eles e o usuário os gera da própria cópia
##    (`python tools/build_assets.py --out port`). Logo o jogo tem de ler de DISCO.
## 2. **Prático:** são ~3.600 imagens + 2.236 máscaras 2048². Importar isso levava mais de
##    5 minutos e produzia cache descartável; sem importar, o projeto abre em 25 s.
##
## Consequência: nada de `load("res://assets/...")` no código do jogo — sempre por aqui.
##
## Cache: as texturas ficam num dicionário com limite por contagem. Uma câmera do RE3 usa
## 1 background (1280×960) + até 2 máscaras (2048²) — manter tudo na memória não escala
## (P3-04), então o cache é pequeno e explícito.

const ASSETS_DIR := "res://assets"
const MAX_CACHE := 24

static var _cache: Dictionary = {}
static var _ordem: Array[String] = []
static var _falhas: Dictionary = {}          ## caminho -> motivo (para relatório, sem spam)


static func path(rel: String) -> String:
	## Caminho absoluto de um asset relativo a `assets/` (ex.: "STAGE1/R100_0.webp").
	return ProjectSettings.globalize_path("%s/%s" % [ASSETS_DIR, rel])


static func exists(rel: String) -> bool:
	return FileAccess.file_exists(path(rel))


static func texture(rel: String) -> Texture2D:
	## Carrega (com cache) uma imagem de `assets/` como textura. null se não existir.
	if _cache.has(rel):
		return _cache[rel]
	var abs_path := path(rel)
	if not FileAccess.file_exists(abs_path):
		_falha(rel, "arquivo não existe")
		return null
	var img := Image.new()
	var err := img.load(abs_path)
	if err != OK:
		_falha(rel, "Image.load falhou (%d)" % err)
		return null
	var tex := ImageTexture.create_from_image(img)
	_guardar(rel, tex)
	return tex


static func image(rel: String) -> Image:
	## Imagem crua (sem cache) — para análise de pixel (auditoria de crop, P7-09).
	var abs_path := path(rel)
	if not FileAccess.file_exists(abs_path):
		_falha(rel, "arquivo não existe")
		return null
	var img := Image.new()
	return img if img.load(abs_path) == OK else null


static func _guardar(rel: String, tex: Texture2D) -> void:
	_cache[rel] = tex
	_ordem.append(rel)
	while _ordem.size() > MAX_CACHE:
		var velho: String = _ordem.pop_front()
		_cache.erase(velho)


static func clear_cache() -> void:
	_cache.clear()
	_ordem.clear()


static func cache_size() -> int:
	return _cache.size()


static func _falha(rel: String, motivo: String) -> void:
	if not _falhas.has(rel):
		_falhas[rel] = motivo
		push_warning("AssetIO: %s — %s" % [rel, motivo])


static func failures() -> Dictionary:
	## Tudo que faltou desde o início (para o verificador de assets do P0-03).
	return _falhas.duplicate()


static func model(rel: String) -> Node3D:
	## Carrega um `.glb` de `assets/` em RUNTIME (GLTFDocument), fora do `.pck`.
	##
	## Mesmo motivo das imagens: o modelo é asset da Capcom e não pode ser distribuído, então
	## não pode ser importado pelo editor. `generate_scene` devolve a árvore com Skeleton3D e
	## AnimationPlayer — os clipes do PLD/PLW (`arm00/01/02/09`, `animNN`) vêm com ela.
	##
	## Cada chamada gera uma instância NOVA (não há cache): o protótipo antigo tinha um bug
	## exatamente por reaproveitar instância salva na cena depois de regerar o `.glb`.
	var abs_path := path(rel)
	if not FileAccess.file_exists(abs_path):
		_falha(rel, "modelo não existe")
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(abs_path, st)
	if err != OK:
		_falha(rel, "GLTFDocument.append_from_file falhou (%d)" % err)
		return null
	var node: Node = doc.generate_scene(st)
	if node == null:
		_falha(rel, "generate_scene devolveu null")
		return null
	return node as Node3D


static func anim_player(n: Node) -> AnimationPlayer:
	## Acha o AnimationPlayer de um modelo carregado (a árvore do glTF varia por arquivo).
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := anim_player(c)
		if r != null:
			return r
	return null


static func json(rel: String) -> Variant:
	## Lê um JSON de `data/` (esses SÃO importados: são poucos e pequenos).
	var p := "res://data/%s" % rel
	if not FileAccess.file_exists(p):
		push_warning("AssetIO: data/%s não existe (rode tools/build_assets.py)" % rel)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(p))
