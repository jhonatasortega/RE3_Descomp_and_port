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
## ── De-para SALA → faixa: o que está PROVADO (correção de 2026-08-08) ──
## O `bgm_map.json` gerado por `tools/audio_gog.py --mapa` já traz o bloco **`salas`** com as
## **169 salas**, e o vínculo sala → **nome da BGM do PS1** é BYTE-EXATO: cada `R###.ARD`
## embute 4 pares (SEQ+VH, VB) nos sub-blocos de tipo `0x05` (MAIN) e `0x06` (SUB), e o sha1 de
## cada bloco casa com um `DATA/SOUND/<nome>.BGM` NOMEADO do `Rofs7.dat` do PC em **676/676**
## blocos (169 × 4), 0 falhas, 98 nomes distintos.
##
## O que continua aberto é só o **RENDER**: a faixa tocável é o WAV do PC de MESMO nome, aceito
## quando a duração da sequência do PS1 casa (`conf` ALTA ≤ 1,5 % · MEDIA ≤ 20 %). Em 32 salas o
## WAV homônimo é outra peça (`NAO_CASADO`) e em 4 não há bloco MAIN (`SEM_MAIN`).
##
## Por isso `faixa_para_sala` passou a ler o `salas` (169) em vez de só o `room_override` (133):
## a versão anterior mandava 36 salas para o fallback por STAGE — e o fallback do PARK
## (`main2a`) **não existe como .ogg** (o PC guarda a faixa partida em `main2a_0`/`_1`), ou seja
## o parque ficava MUDO. Era o "não colocou as trilhas corretamente".

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
	return faixa_info(room_id).get("faixa", "")


func faixa_info(room_id: String) -> Dictionary:
	## Faixa da sala + de onde ela veio. Ordem de precedência:
	##   1. `room_override[sala]`   — correção à mão (é o que o mapa publica para ALTA/MEDIA)
	##   2. `salas[sala].faixa`     — MEDIDO (sha1 do bloco do ARD × nome do Rofs7 do PC)
	##   3. `salas[sala].ps1`       — o NOME do PS1 está provado, o render homônimo é
	##                               `NAO_CASADO`; é melhor tocar a peça de nome certo do que
	##                               cair no stage. Marcado `nome_provado`.
	##   4. área do STAGE           — fallback PROVISÓRIO (`_meta.TODO` do mapa)
	##   5. `default`
	## Devolve `{faixa, fonte, conf}`; `faixa` vazia = não há ogg para nenhuma das opções.
	carregar_mapa()
	if _mapa.is_empty():
		return {"faixa": "", "fonte": "sem_mapa", "conf": ""}
	var over: Variant = _mapa.get("room_override")
	if over is Dictionary and (over as Dictionary).has(room_id):
		var f0 := _resolver_faixa(str((over as Dictionary)[room_id]))
		if f0 != "":
			return {"faixa": f0, "fonte": "room_override", "conf": _conf_da_sala(room_id)}
	var s: Variant = _mapa.get("salas")
	if s is Dictionary and (s as Dictionary).has(room_id):
		var e: Dictionary = (s as Dictionary)[room_id]
		var f1 := _resolver_faixa(str(e.get("faixa", "")))
		if f1 != "":
			return {"faixa": f1, "fonte": "salas", "conf": str(e.get("conf", ""))}
		var f2 := _resolver_faixa(str(e.get("ps1", "")).to_lower())
		if f2 != "":
			return {"faixa": f2, "fonte": "nome_provado", "conf": str(e.get("conf", ""))}
	var area := str(AREA_POR_STAGE.get(RoomData.stage_of(room_id), ""))
	var ad: Variant = _mapa.get("area_default")
	if ad is Dictionary and (ad as Dictionary).has(area):
		var f3 := _resolver_faixa(str((ad as Dictionary)[area]))
		if f3 != "":
			return {"faixa": f3, "fonte": "area_provisoria", "conf": "PROVISORIO"}
	return {"faixa": _resolver_faixa(str(_mapa.get("default", ""))),
		"fonte": "default", "conf": "PROVISORIO"}


func _conf_da_sala(room_id: String) -> String:
	var s: Variant = _mapa.get("salas")
	if s is Dictionary and (s as Dictionary).has(room_id):
		return str(((s as Dictionary)[room_id] as Dictionary).get("conf", ""))
	return ""


func _resolver_faixa(nome: String) -> String:
	## Resolve o nome do mapa para um ogg que EXISTE no disco. As faixas multiparte do PC
	## (`main2a_0`/`main2a_1`, `main30_0..main30_c`) não têm o arquivo de nome "puro" — sem esta
	## resolução `main2a` simplesmente não tocava. Sufixo escolhido: **`_0`** (a primeira parte),
	## que é **DECLARADO** — qual parte é intro e qual é loop não foi medido.
	if nome == "":
		return ""
	if AssetIO.exists("%s/%s.ogg" % [BGM_DIR, nome]):
		return nome
	if AssetIO.exists("%s/%s_0.ogg" % [BGM_DIR, nome]):
		return "%s_0" % nome
	return ""


func tocar_bgm_da_sala(room_id: String) -> void:
	var info := faixa_info(room_id)
	var faixa := str(info.get("faixa", ""))
	if faixa == "":
		push_warning("Audio: %s sem faixa em data/bgm_map.json (rode tools/audio_gog.py --mapa)"
			% room_id)
		return
	if faixa == _faixa_atual:
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
	print("[audio] %s -> faixa '%s' (fonte=%s conf=%s)" % [
		room_id, faixa, info.get("fonte", ""), info.get("conf", "")])


func tocar_faixa(faixa: String, loop := true) -> bool:
	## Toca uma faixa PELO NOME (sem passar pelo de-para de sala). É o que a abertura precisa: o
	## boot pede `main38` direto, e o de-para sala → faixa não vale ali.
	if faixa == "" or faixa == _faixa_atual:
		return faixa != ""
	var s2 := _carregar_ogg("%s/%s.ogg" % [BGM_DIR, faixa])
	if s2 == null:
		return false
	if s2 is AudioStreamOggVorbis:
		(s2 as AudioStreamOggVorbis).loop = loop
	_faixa_atual = faixa
	bgm_player.stream = s2
	bgm_player.play()
	return true


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
