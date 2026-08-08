class_name Sfx
extends Node
## Efeitos sonoros (SE) do RE3, pelo de-para **provado no binário**.
##
## ── Por que esta classe existe ──
## O `Audio` (core/audio.gd) sabe tocar um arquivo. Ele não sabe *qual* arquivo é o som de
## "confirmar". Quem responde isso é a **tabela de SE** que mora no início de cada
## `.VH`/`.SND` do disco, decodificada por `tools/exe_audio.py` para `data/re3_se.json`.
##
## ── O caminho do som no jogo original (endereços do SLUS_009.23) ──
##   `0x800746c0`  SE_pede(a0 = (b2<<16)|(cat<<8)|idx, a1 = ptr 16B, a2, a3)
##                 -> grava 32 B no anel `0x800e0de4`, ponteiro de escrita `0x800e10e4`
##   `0x800744e0`  consumidor: despacha por `0x800a1130` -> `0x80074770` (cat<5)
##   `0x80074770`  desc = *( *(0x800e0610 + cat*4) + idx*4 );  **-1 = descarta**
##   `0x800749a0`  aloca voz do SPU, volume/pan (`0x80075b90`, div 63, pan centro 0x40)
##   `0x8007eda8`  libspu `SpuSetKey` -> a voz soa
##
## `cat` **é o id do banco VAB** (a mesma função `0x800750e4` busca `cat` e o banco do
## descritor na tabela de 8 slots `0x800e0664`): **0 = `C_xx`** (jogador/UI/global),
## **1 = `A_xx`** (área), **2 = `R###.SND`** (sala).
##
## O descritor dá o índice do TOM (`byte1 >> 4`); o `vag` do tom é a amostra. Como
## `re3_sfx.py` descarta o VAG#1 (bloco mudo do SPU), **`vag k` => `<banco>_{k-2}.wav`**.
##
## ── O que é PROVADO e o que é DECLARADO ──
## Os 5 sons de menu (`4/5/6/7/9`) têm confiança **ALTA**. O resto está no JSON com
## `confianca = "DECLARADO"` e o call site que o justifica — `acao_confiavel()` deixa isso
## consultável em runtime, para nenhuma tela afirmar mais do que foi medido.
##
## Detalhe e resíduo: `docs/decomp/notes/exe_audio.md`.

const DADOS := "re3_se.json"
const SFX_DIR := "SOUND/SFX"
const VOZES := 8                                ## pool de players (o SPU do PS1 tem 24 vozes)

## Ações nomeadas com confiança ALTA — o que a UI pode usar sem ressalva.
const ACOES_MENU := ["menu_mover", "menu_cancelar", "menu_confirmar",
	"menu_invalido", "menu_abrir"]

var _dados: Dictionary = {}
var _acoes: Dictionary = {}
var _bancos: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _prox := 0
var _cache: Dictionary = {}                     ## rel -> AudioStreamWAV
var _banco_area := ""                           ## banco C_ da área atual (ver definir_banco_area)
var _volume_db := 0.0
var _ultimo := ""                               ## último rel tocado (harness/teste)


func _ready() -> void:
	name = "Sfx"
	process_mode = Node.PROCESS_MODE_ALWAYS      ## som de menu tem de soar com a árvore pausada
	_garantir_pool()
	carregar()


func _garantir_pool() -> void:
	## Pool preguiçoso: o harness de teste instancia o `Sfx` sem passar pelo `_ready`
	## (os testes são RefCounted, não cena). Sem isto, `tocar_arquivo` estouraria índice.
	if not _pool.is_empty():
		return
	for i in VOZES:
		var p := AudioStreamPlayer.new()
		p.name = "SE%d" % i
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


func carregar() -> bool:
	## Lê `data/re3_se.json` (gerado por `tools/exe_audio.py`). false se faltar.
	var d: Variant = AssetIO.json(DADOS)
	if not (d is Dictionary):
		push_warning("Sfx: data/%s ausente — rode `python tools/exe_audio.py` "
			% DADOS + "(com NOSTALGIA_OUT=port)")
		return false
	_dados = d
	var a: Variant = _dados.get("acoes")
	_acoes = a if a is Dictionary else {}
	var b: Variant = _dados.get("bancos")
	_bancos = b if b is Dictionary else {}
	return true


func pronto() -> bool:
	return not _acoes.is_empty()


# ───────────────────────────── API por ação ─────────────────────────────
func menu_mover() -> bool:
	## Cursor andou na lista. SE id 4 do banco `C_` (11 call sites de `0x800746c0`).
	return tocar_acao("menu_mover")


func menu_confirmar() -> bool:
	## Confirmou/entrou. SE id 6 (13 call sites, ex.: `0x80023d10`).
	return tocar_acao("menu_confirmar")


func menu_cancelar() -> bool:
	## Voltou/cancelou. SE id 5 — o mais chamado dos cinco (20 call sites).
	return tocar_acao("menu_cancelar")


func menu_invalido() -> bool:
	## Ação recusada (item que não combina, slot vazio). SE id 7 (5 call sites).
	return tocar_acao("menu_invalido")


func menu_abrir() -> bool:
	## Abriu o menu/arquivo. SE id 9 (5 call sites, ex.: `0x80023db8`).
	return tocar_acao("menu_abrir")


func tiro() -> bool:
	## Disparo. SE id 11 do banco `C_` **de área** (`0x8003ad6c`: `lui a0,1; ori a0,a0,0xb`).
	## `C_00`/`C_01` (bancos de menu) não definem o id 11 — coerente com "não há tiro no
	## menu". O nome é DECLARADO: o par id->ação não foi confirmado por ouvido.
	return tocar_acao("tiro")


func impacto_ataque() -> bool:
	## SE id 0 (`0x8003d208`, vizinhança do "acerto conectado" `0x8003d14c`). DECLARADO.
	return tocar_acao("impacto_ataque")


# ───────────────────────────── API genérica ─────────────────────────────
func tocar_acao(acao: String) -> bool:
	## Toca uma ação nomeada do `re3_se.json`. false se o nome ou o WAV não existir.
	var a: Variant = _acoes.get(acao)
	if not (a is Dictionary):
		return false
	var rel: Variant = (a as Dictionary).get("wav_padrao")
	if not (rel is String) or rel == "":
		return false
	# Se a área definiu um banco `C_` e a ação é de cat 0, prefere o som daquela área —
	# é o que o original faz (o mesmo id toca amostra diferente por banco carregado).
	if _banco_area != "" and int((a as Dictionary).get("cat", -1)) == 0:
		var pb: Variant = (a as Dictionary).get("por_banco")
		if pb is Dictionary and (pb as Dictionary).has(_banco_area):
			rel = (pb as Dictionary)[_banco_area]
	return tocar_arquivo(rel as String)


func tocar_id(cat: int, id_se: int, banco := "") -> bool:
	## Toca por (cat, id) cru, como o original: resolve o descritor do banco.
	## `banco` vazio = banco da área (cat 0) ou o padrão do cat.
	var nome := banco if banco != "" else _banco_de(cat)
	if nome == "":
		return false
	var b: Variant = _bancos.get(nome)
	if not (b is Dictionary):
		return false
	var se: Variant = (b as Dictionary).get("se")
	if not (se is Dictionary):
		return false
	var e: Variant = (se as Dictionary).get(str(id_se))
	if not (e is Dictionary):
		return false                              ## descritor 0xffffffff = id sem som (o
		                                          ## original também descarta em 0x80074770)
	var rel: Variant = (e as Dictionary).get("wav")
	if not (rel is String) or rel == "":
		return false                              ## tom aponta o VAG mudo
	return tocar_arquivo(rel as String)


func tocar_arquivo(rel: String) -> bool:
	## `rel` relativo a `assets/SOUND/SFX/` (ex.: "C_00/C_00_02.wav").
	var s := _stream(rel)
	if s == null:
		return false
	_garantir_pool()
	var p := _pool[_prox]
	_prox = (_prox + 1) % _pool.size()
	p.stream = s
	p.volume_db = _volume_db
	p.play()
	_ultimo = rel
	return true


func definir_banco_area(nome: String) -> void:
	## Diz qual banco `C_xx` está "carregado" (o original troca por área). Vazio = padrão.
	## Enquanto o de-para área->banco não estiver medido, isto fica sob controle de quem
	## carrega a sala. **declarado: escolha do port, não medida.**
	_banco_area = nome if _bancos.has(nome) else ""


func banco_area() -> String:
	return _banco_area


func definir_volume_db(db: float) -> void:
	_volume_db = db


# ───────────────────────────── consulta ─────────────────────────────
func acao_id(acao: String) -> int:
	## id de SE da ação, ou -1.
	var a: Variant = _acoes.get(acao)
	return int((a as Dictionary).get("id", -1)) if a is Dictionary else -1


func acao_cat(acao: String) -> int:
	var a: Variant = _acoes.get(acao)
	return int((a as Dictionary).get("cat", -1)) if a is Dictionary else -1


func acao_wav(acao: String) -> String:
	var a: Variant = _acoes.get(acao)
	if not (a is Dictionary):
		return ""
	var rel: Variant = (a as Dictionary).get("wav_padrao")
	return rel as String if rel is String else ""


func acao_confiavel(acao: String) -> bool:
	## true só quando o de-para id->amostra tem confiança ALTA (os 5 sons de menu).
	## Serve para o port nunca AFIRMAR o que não mediu.
	var a: Variant = _acoes.get(acao)
	return a is Dictionary and str((a as Dictionary).get("confianca", "")) == "ALTA"


func acoes() -> Array:
	return _acoes.keys()


func banco_info(nome: String) -> Dictionary:
	var b: Variant = _bancos.get(nome)
	return b as Dictionary if b is Dictionary else {}


func ultimo_tocado() -> String:
	return _ultimo


# ───────────────────────────── interno ─────────────────────────────
func _banco_de(cat: int) -> String:
	if cat == 0 and _banco_area != "":
		return _banco_area
	var bp: Variant = _dados.get("banco_padrao")
	if bp is Dictionary and (bp as Dictionary).has(str(cat)):
		return str((bp as Dictionary)[str(cat)])
	return ""


func _stream(rel: String) -> AudioStream:
	## WAV de disco (o `assets/` não é importado pelo editor — ver AssetIO).
	if _cache.has(rel):
		return _cache[rel]
	var abs_path := AssetIO.path("%s/%s" % [SFX_DIR, rel])
	if not FileAccess.file_exists(abs_path):
		return null
	var s := AudioStreamWAV.load_from_file(abs_path)
	if s == null:
		return null
	_cache[rel] = s
	return s
