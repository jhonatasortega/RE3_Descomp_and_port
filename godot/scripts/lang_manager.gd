extends Node
## LangManager — Autoload (singleton).
## Gerencia o idioma da VOZ (en / ptbr) e toca as falas de cena.
## As faixas ficam em res://assets/VOICE/<lang>/<nome_cena>.ogg
## (441 .ogg em cada idioma, mesmos nomes de arquivo).
##
## Uso:
##   LangManager.set_lang("ptbr")
##   LangManager.toggle_lang()
##   LangManager.play_voice("m101a010")   # toca a fala do idioma atual

signal lang_changed(new_lang: String)
signal voice_played(scene_name: String, lang: String, ok: bool)

const VOICE_BASE := "res://assets/VOICE/"
const LANGS := ["en", "ptbr"]

var lang: String = "en"
var _player: AudioStreamPlayer


func _ready() -> void:
	# AudioStreamPlayer proprio do singleton — toca sobre qualquer cena.
	_player = AudioStreamPlayer.new()
	_player.name = "VoicePlayer"
	_player.bus = "Master"
	add_child(_player)


## Define o idioma atual. Retorna true se valido.
func set_lang(new_lang: String) -> bool:
	if not LANGS.has(new_lang):
		push_warning("LangManager: idioma invalido '%s'" % new_lang)
		return false
	if new_lang == lang:
		return true
	lang = new_lang
	lang_changed.emit(lang)
	return true


## Alterna ciclicamente entre os idiomas disponiveis. Retorna o novo idioma.
func toggle_lang() -> String:
	var idx := LANGS.find(lang)
	idx = (idx + 1) % LANGS.size()
	set_lang(LANGS[idx])
	return lang


## Caminho da faixa de voz para o idioma atual (ou informado).
func voice_path(scene_name: String, use_lang: String = "") -> String:
	var l := use_lang if use_lang != "" else lang
	var n := scene_name.trim_suffix(".ogg")
	return "%s%s/%s.ogg" % [VOICE_BASE, l, n]


## Existe faixa para essa cena no idioma atual?
func has_voice(scene_name: String) -> bool:
	return ResourceLoader.exists(voice_path(scene_name))


## Toca a fala 'scene_name' no idioma atual. Retorna true se tocou.
func play_voice(scene_name: String) -> bool:
	var path := voice_path(scene_name)
	if not ResourceLoader.exists(path):
		push_warning("LangManager: voz nao encontrada: %s" % path)
		voice_played.emit(scene_name, lang, false)
		return false
	var stream := load(path)
	if stream == null:
		voice_played.emit(scene_name, lang, false)
		return false
	_player.stream = stream
	_player.play()
	voice_played.emit(scene_name, lang, true)
	return true


func stop_voice() -> void:
	if _player:
		_player.stop()
