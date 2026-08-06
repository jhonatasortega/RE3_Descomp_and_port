extends Node
## AudioManager - gerenciador de audio do remake de RE3 (BGM por area + SFX).
##
## Autoload sugerido:  AudioManager="*res://scripts/audio/audio_manager.gd"
##
## API principal:
##   play_bgm(area: String, loop := true)   -> toca a BGM da area (crossfade suave)
##   play_bgm_track(track: String)          -> toca uma faixa especifica (nome do arquivo, sem .ogg)
##   stop_bgm(fade := 1.0)                   -> para a BGM com fade-out
##   play_sfx(name: String) -> AudioStreamPlayer  -> dispara um SFX one-shot
##   set_bgm_volume_db(db) / set_sfx_volume_db(db)
##
## Estilo RE3: uma BGM ambiente por sala/area; troca ao mudar de area (com crossfade).
## Gancho de gameplay (NAO acoplado aqui): quem entra numa sala deve chamar
##   AudioManager.play_bgm(<AREA>)  ao trocar de camera/sala. Ver docs/godot_audio.md.

const BGM_DIR := "res://assets/SOUND/BGM/gog/"      # faixas .ogg (fonte GOG)
const SFX_DIR := "res://assets/SOUND/SFX/"          # amostras .wav (VAB real)
const BGM_MAP_PATH := "res://scripts/audio/bgm_map.json"
const SFX_MAP_PATH := "res://scripts/audio/sfx_map.json"

const CROSSFADE_TIME := 1.2      # segundos de crossfade entre BGMs
const DEFAULT_BGM_DB := -6.0
const DEFAULT_SFX_DB := -3.0
const SILENCE_DB := -60.0
const SFX_VOICES := 8            # polifonia de SFX

var _bgm_map: Dictionary = {}
var _sfx_map: Dictionary = {}
var _bgm_db := DEFAULT_BGM_DB
var _sfx_db := DEFAULT_SFX_DB

var _bgm_players: Array[AudioStreamPlayer] = []   # dois players p/ crossfade
var _bgm_active := 0                               # indice do player que esta tocando
var _current_area := ""
var _current_track := ""
var _fade_tween: Tween

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0

var _stream_cache: Dictionary = {}                 # path -> AudioStream


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # audio segue tocando em pausa (menu)
	_bgm_map = _load_json(BGM_MAP_PATH)
	_sfx_map = _load_json(SFX_MAP_PATH)

	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = SILENCE_DB
		add_child(p)
		_bgm_players.append(p)

	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = _sfx_db
		add_child(p)
		_sfx_players.append(p)

	print("[AudioManager] pronto. areas=", _bgm_map.get("area_default", {}).size(),
		" sfx=", _sfx_map.get("sfx", {}).size())


# ---------------------------------------------------------------- BGM
## Toca a BGM associada a uma AREA (UPTOWN, DOWNTOWN, ...). Aplica crossfade.
func play_bgm(area: String, _loop := true) -> void:
	area = area.to_upper()
	if area == _current_area:
		return
	_current_area = area
	var track := _track_for_area(area)
	if track == "":
		push_warning("[AudioManager] sem BGM para area '%s'" % area)
		return
	play_bgm_track(track)


## Toca uma faixa BGM especifica pelo nome do arquivo (sem extensao).
func play_bgm_track(track: String) -> void:
	if track == _current_track and _bgm_players[_bgm_active].playing:
		return
	var stream := _load_stream(BGM_DIR + track + ".ogg")
	if stream == null:
		push_warning("[AudioManager] BGM nao encontrada: %s" % track)
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_current_track = track

	var old_i := _bgm_active
	var new_i := 1 - _bgm_active
	var np := _bgm_players[new_i]
	np.stream = stream
	np.volume_db = SILENCE_DB
	np.play()
	_bgm_active = new_i

	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(np, "volume_db", _bgm_db, CROSSFADE_TIME)
	var op := _bgm_players[old_i]
	if op.playing:
		_fade_tween.tween_property(op, "volume_db", SILENCE_DB, CROSSFADE_TIME)
		_fade_tween.chain().tween_callback(op.stop)
	print("[AudioManager] BGM -> ", track)


func stop_bgm(fade := 1.0) -> void:
	_current_area = ""
	_current_track = ""
	var p := _bgm_players[_bgm_active]
	if not p.playing:
		return
	if fade <= 0.0:
		p.stop()
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(p, "volume_db", SILENCE_DB, fade)
	_fade_tween.tween_callback(p.stop)


# ---------------------------------------------------------------- SFX
## Dispara um SFX one-shot pelo nome logico (door, gunshot, footstep, ...).
func play_sfx(name: String, pitch := 1.0) -> AudioStreamPlayer:
	var rel: String = _sfx_map.get("sfx", {}).get(name, "")
	if rel == "":
		push_warning("[AudioManager] SFX desconhecido: %s" % name)
		return null
	var stream := _load_stream(SFX_DIR + rel + ".wav")
	if stream == null:
		push_warning("[AudioManager] SFX nao encontrado: %s" % rel)
		return null
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = _sfx_db
	p.pitch_scale = pitch
	p.play()
	return p


# ---------------------------------------------------------------- volume
func set_bgm_volume_db(db: float) -> void:
	_bgm_db = db
	if _bgm_players[_bgm_active].playing:
		_bgm_players[_bgm_active].volume_db = db


func set_sfx_volume_db(db: float) -> void:
	_sfx_db = db
	for p in _sfx_players:
		p.volume_db = db


func is_bgm_playing() -> bool:
	return _bgm_players[_bgm_active].playing


func current_track() -> String:
	return _current_track


# ---------------------------------------------------------------- interno
func _track_for_area(area: String) -> String:
	var ad: Dictionary = _bgm_map.get("area_default", {})
	if ad.has(area):
		return ad[area]
	return _bgm_map.get("default", "")


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[AudioManager] JSON ausente: %s" % path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[AudioManager] JSON invalido: %s" % path)
		return {}
	return data


## Carrega um AudioStream sem depender do pipeline de import do editor
## (le os bytes e constroi o stream em runtime). Cache por caminho.
func _load_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var stream: AudioStream = null
	if path.get_extension().to_lower() == "ogg":
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	else:
		stream = _load_wav(path)
	if stream != null:
		_stream_cache[path] = stream
	return stream


## Parser minimo de RIFF/WAV PCM -> AudioStreamWAV (mono/estereo, 8/16-bit).
func _load_wav(path: String) -> AudioStreamWAV:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var buf := f.get_buffer(f.get_length())
	f.close()
	if buf.size() < 44 or buf.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := 1
	var rate := 22050
	var bits := 16
	var data := PackedByteArray()
	var pos := 12
	while pos + 8 <= buf.size():
		var cid := buf.slice(pos, pos + 4).get_string_from_ascii()
		var csz := buf.decode_u32(pos + 4)
		var body := pos + 8
		if cid == "fmt ":
			channels = buf.decode_u16(body + 2)
			rate = buf.decode_u32(body + 4)
			bits = buf.decode_u16(body + 14)
		elif cid == "data":
			data = buf.slice(body, min(body + csz, buf.size()))
		pos = body + csz + (csz & 1)
	if data.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.stereo = channels >= 2
	wav.data = data
	return wav
