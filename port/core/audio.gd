class_name Audio
extends Node
## Som do jogo: trilha por área + SFX + voz (P1-13, base do P7-02).
##
## No protótipo antigo o AudioManager existia mas **nunca foi ligado na cena** — o jogo era
## mudo. Aqui o som entra pelo mesmo caminho que tudo no port: dado gerado pelo pipeline e
## consumido em runtime, de fora do `.pck` (`assets/` tem `.gdignore`).
##
## ── Fontes (geradas por `tools/audio_gog.py`) ──
##   `assets/SOUND/BGM/gog/<faixa>.ogg`   125 faixas (DATA_A/SOUND do PC, PCM 22 kHz -> Ogg)
##   `assets/VOICE/ptbr/<cena>.ogg`       441 vozes dubladas (DATA_A/VOICE)
##   `assets/SOUND/SFX/<banco>/*.wav`     267 SFX cortados dos bancos VAB do PS1
##
## O mapa área→faixa vem de `data/bgm_map.json` (o mesmo que o protótipo usava). Ele traz um
## `TODO` honesto: os pares área→faixa são **provisórios** — quem confirma é ouvir contra o
## original (P7-02). O port não inventa: usa o mapa e diz no log qual faixa escolheu.

const BGM_DIR := "SOUND/BGM/gog"
const VOICE_DIR := "VOICE/ptbr"

var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer

var _mapa: Dictionary = {}
var _faixa_atual := ""
## Área por prefixo de sala (stage). Enquanto o mapa por sala não estiver completo, o stage
## decide — é a aproximação declarada do `bgm_map.json`, não uma invenção nova.
const AREA_POR_STAGE := {
	1: "UPTOWN", 2: "DOWNTOWN", 3: "CLOCK_TOWER", 4: "PARK",
	5: "DEAD_FACTORY", 6: "POLICE_STATION", 7: "HOSPITAL",
}


func _ready() -> void:
	name = "Audio"
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM"
	bgm_player.bus = "Master"
	add_child(bgm_player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SFX"
	add_child(sfx_player)
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "Voice"
	add_child(voice_player)
	carregar_mapa()


func carregar_mapa() -> bool:
	## Lê `data/bgm_map.json`. Separado do `_ready` porque o harness de teste usa o `Audio`
	## sem cena (testes são RefCounted) — sem isto o mapa ficava vazio e `faixa_para_sala`
	## devolvia "" silenciosamente, escondendo regressão do de-para sala->faixa.
	if not _mapa.is_empty():
		return true
	var m: Variant = AssetIO.json("bgm_map.json")
	if m is Dictionary:
		_mapa = m
		return true
	push_warning("Audio: data/bgm_map.json ausente — a trilha vai cair no default")
	return false


func faixa_para_sala(room_id: String) -> String:
	## Escolhe a faixa: override por sala > área do stage > default do mapa.
	carregar_mapa()
	if _mapa.is_empty():
		return ""
	var over: Variant = _mapa.get("room_override")
	if over is Dictionary and (over as Dictionary).has(room_id):
		return str((over as Dictionary)[room_id])
	var area := str(AREA_POR_STAGE.get(RoomData.stage_of(room_id), ""))
	var ad: Variant = _mapa.get("area_default")
	if ad is Dictionary and (ad as Dictionary).has(area):
		return str((ad as Dictionary)[area])
	return str(_mapa.get("default", ""))


func tocar_bgm_da_sala(room_id: String) -> void:
	var faixa := faixa_para_sala(room_id)
	if faixa == "" or faixa == _faixa_atual:
		return
	var rel := "%s/%s.ogg" % [BGM_DIR, faixa]
	var s := _carregar_ogg(rel)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true      ## a trilha de sala é em loop
	_faixa_atual = faixa
	bgm_player.stream = s
	bgm_player.play()
	print("[audio] %s -> faixa '%s' (%s)" % [room_id, faixa, rel])


func parar_bgm() -> void:
	bgm_player.stop()
	_faixa_atual = ""


func tocar_voz(cena: String) -> bool:
	var s := _carregar_ogg("%s/%s.ogg" % [VOICE_DIR, cena])
	if s == null:
		return false
	voice_player.stream = s
	voice_player.play()
	return true


func tocar_sfx(rel: String) -> bool:
	## `rel` relativo a `assets/` (ex.: "SOUND/SFX/A_01/A_01_00.wav").
	var abs_path := AssetIO.path(rel)
	if not FileAccess.file_exists(abs_path):
		return false
	var s: AudioStream = null
	if rel.ends_with(".wav"):
		s = AudioStreamWAV.load_from_file(abs_path)
	else:
		s = _carregar_ogg(rel)
	if s == null:
		return false
	sfx_player.stream = s
	sfx_player.play()
	return true


func _carregar_ogg(rel: String) -> AudioStream:
	## Ogg de disco, em runtime (o `assets/` não é importado pelo editor — ver AssetIO).
	var abs_path := AssetIO.path(rel)
	if not FileAccess.file_exists(abs_path):
		push_warning("Audio: %s não existe (rode tools/audio_gog.py)" % rel)
		return null
	return AudioStreamOggVorbis.load_from_file(abs_path)


func faixa_atual() -> String:
	return _faixa_atual
