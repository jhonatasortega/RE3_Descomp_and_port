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
## **1 = `A_xx`**, **2 = `R###.SND`** (sala), **4 = porta** (banco embutido em cada
## `STAGE*/DOORxx.DOn` — é o recurso que o loader `0x80012818` puxa com a string de
## depuração `"DOOR SOUND"` de `0x800103ac`).
##
## Quem carrega cada banco (medido nesta rodada — o carregador é `0x8007809c`, com
## `fileid = *(0x800110b0 + cat*4) + banco*2`):
##   • **cat 0** — room-loader `0x800493ec` em `0x800495d0`: `C_02` (Jill) ou `C_08`
##     (`*(gs+0x784e) >= 8`). É banco de **PERSONAGEM**.
##   • **cat 1** — `0x80043eb4`, com `a1 = lbu *(player+0x46)` = **ARMA EQUIPADA** (o mesmo
##     byte que indexa a jump-table por arma em `0x8009dcd4`). Ou seja `A_01..A_14` é banco
##     de **ARMA**, não de "área" como dizia o doc antigo. O de-para do índice é
##     **`w` -> `A_{w:02X}`** (fileid `0xda + w*2`; `A_01.VH` = fid `0xdc`, 384 B, conferido
##     contra o tamanho real do arquivo) — logo `w = 1` é a **FACA**.
##   • **cat 4** — loader de porta `0x8001644c`, `dtex = *(descriptor+0xc)`.
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
const PORTAS := "porta_banco.json"              ## sala -> índice de porta (Dtex_Type) por AOT
const SFX_DIR := "SOUND/SFX"
const VOZES := 8                                ## pool de players (o SPU do PS1 tem 24 vozes)
## Nome do banco de porta para um índice `Dtex_Type`. O `S1_` é histórico: os 76
## `STAGE*/DOORxx.DOn` são byte-idênticos nos 7 stages (medido em 76/76).
const NOME_BANCO_PORTA := "S1_DOOR%02X"
## Banco `cat 0` que o room-loader carrega para a Jill — MEDIDO (ver `definir_banco_area`).
const BANCO_JOGADOR := "C_02"
## Nome do banco `cat 1` para um índice de arma `w` (`player+0x46`) — ver `definir_banco_arma`.
const NOME_BANCO_ARMA := "A_%02X"
## `w` da FACA: é o único dos 20 bancos `A_` que **não** define o id 0 (o estouro).
const ARMA_FACA := 1
## `w` de partida do port enquanto o de-para **item -> `w`** não for medido (ver
## `tools/exe_aim_shoot.py`). `A_02` é o primeiro banco de arma de fogo. **DECLARADO**.
const ARMA_PADRAO := 2

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
var _banco_porta := ""                          ## banco da porta em uso (ver definir_banco_porta)
var _banco_arma := ""                           ## banco A_ da arma equipada (ver definir_banco_arma)
var _portas: Dictionary = {}                    ## sala -> [{aot, dtex, ...}] (porta_banco.json)
var _volume_db := 0.0
var _ultimo := ""                               ## último rel tocado (harness/teste)
var _reclamou: Dictionary = {}                  ## chave -> true (reclama UMA vez, sem spam)


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
	# Banco de porta por sala/AOT (opcional: sem ele a porta cai no banco padrão).
	var p: Variant = AssetIO.json(PORTAS)
	if p is Dictionary:
		var s: Variant = (p as Dictionary).get("salas")
		_portas = s if s is Dictionary else {}
	return true


func dtex_da_porta(room_id: String, aot: int) -> int:
	## Índice `Dtex_Type` da porta `aot` da sala, ou -1. É campo ESTÁTICO do SCD
	## (`descriptor+0xc`) e é o mesmo byte que o loader `0x8001644c` usa para achar o
	## `DOORxx.DOn` de onde vem o banco de som (`cat 4`).
	var v: Variant = _portas.get(room_id)
	if not (v is Array):
		return -1
	for e: Variant in v as Array:
		if e is Dictionary and int((e as Dictionary).get("aot", -1)) == aot:
			return int((e as Dictionary).get("dtex", -1))
	return -1


func usar_porta_da_sala(room_id: String, aot: int) -> bool:
	## Seleciona o banco da porta `aot` da sala e devolve true se achou.
	var dt := dtex_da_porta(room_id, aot)
	if dt < 0:
		return false
	definir_banco_porta(dt)
	return _banco_porta != ""


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
	## Disparo. **CORRIGIDO nesta rodada: o estouro da arma é `cat 1 / id 0`**, do banco `A_{w}`
	## da arma equipada — não o `cat 0 / id 11` que estava aqui antes.
	##
	## Duas provas independentes:
	##  1. **Tabela de 20 funções POR ARMA** em `0x8009ced8..0x8009cf24` (vizinha da tabela de
	##     timing `0x8009cf28` que o `Player.quadro_do_tiro()` já usa). Em CADA entrada o mesmo
	##     trecho aparece: `0x80044804` (HITSCAN, `a2 = lbu player+0x46`) → `0x80047860` →
	##     `0x8006d030(1)` → `SE_pede(cat 1, idx 0, a1 = *(player+0x108)+0x344)`. São ~20 dos
	##     155 `jal 0x800746c0` do EXE, todos com o MESMO id.
	##  2. **`A_01` é o único dos 20 bancos `A_` que NÃO define o id 0** (define 6..10). E `A_01`
	##     é o banco de `w = 1`, a FACA — arma que não estoura. 19/20 definem o id 0.
	##
	## O `cat 0 / id 11` (`0x8003ad6c`, dentro da rotina 7 = mira) **existe** e continua sendo o
	## fallback quando nenhum banco de arma foi declarado — mas o trecho dele mexe em
	## `player+0x6e` (pitch da mira) e num contador `u16 @0x800d1f96`, não no hitscan; o nome
	## dele segue DECLARADO.
	if _banco_arma != "":
		if tocar_id(1, 0, _banco_arma):
			return true
		_reclamar("arma:%s" % _banco_arma,
			"banco de arma '%s' não define o SE id 0 (é a faca?) — caindo no cat 0/id 11"
			% _banco_arma)
	return tocar_acao("tiro")


func definir_banco_arma(w: int) -> void:
	## Diz qual arma está equipada, pelo índice `w` = `player+0x46`. **MEDIDO**: `0x80043eb4`
	## chama o carregador de banco `0x8007809c(a0 = 1, a1 = lbu player+0x46)`, e em `0x8007809c`
	## `fileid = *(0x800110b0 + cat*4) + a1*2` com base `0xda` para o cat 1. Conferindo os
	## TAMANHOS da tabela de arquivos `0x800946a4` contra os arquivos reais:
	## `fid 0xdb` = 23600 B = `A_01.VB` e `fid 0xdc` = 384 B = `A_01.VH` → **`w` -> `A_{w:02X}`**.
	## (A nota antiga em `exe_audio.md §3.1`, que dizia `0xda = A_01.VH`, estava um arquivo
	## adiantada.)
	##
	## `w = 0` não é banco de arma nenhum (o fid `0xda` não é um `.VH` de `A_`); `w = 1` é a
	## FACA. O de-para **item do inventário -> `w`** continua NÃO MEDIDO.
	var nome := NOME_BANCO_ARMA % w
	if _bancos.has(nome):
		_banco_arma = nome
		return
	_banco_arma = ""
	if w > 0:
		_reclamar("banco_arma:%d" % w,
			"banco de arma w=%d ('%s') não existe no re3_se.json" % [w, nome])


func banco_arma() -> String:
	return _banco_arma


func impacto_ataque() -> bool:
	## SE id 0 (`0x8003d208`, vizinhança do "acerto conectado" `0x8003d14c`). DECLARADO.
	return tocar_acao("impacto_ataque")


func porta_abrir() -> bool:
	## Som da transição de porta. **O id é MEDIDO**: `cat 4 / id 1`.
	##
	## Dos 155 `jal 0x800746c0` do EXE, o único que cai na região de porta
	## (`0x80014000..0x80019000`) é `0x800161c4`, com `a0 = 0x401` → cat 4, id 1. Ele está no
	## estado 2 da máquina de estados da animação de porta (tabela de 3 funções `0x800979f0`
	## = `{0x80015498, 0x80015754, 0x80016150}`); os estados 0 e 1 **não pedem SE nenhum**.
	## O gatilho é a flag `0x2000` do `u16@+6` da entrada de animação (`0x800163ec` grava
	## `*(gs+0x240) = 1`, relido em `0x800161b4`).
	##
	## Ou seja: o motor toca **um só** som do banco de porta, e é o id 1. Que o momento seja
	## "abrir" e não "fechar" é interpretação — o NOME segue DECLARADO.
	return _tocar_porta("porta_abrir")


func porta_fechar() -> bool:
	## **NÃO EXISTE** no motor: só há UM pedido de cat 4 em todo o EXE (o id 1, em
	## `porta_abrir`). Mantido para não quebrar quem chamava; toca o mesmo som.
	return porta_abrir()


func porta_trancada() -> bool:
	## Porta trancada. É **cat 2 (banco de SALA)**, não o banco da porta: o produtor de porta
	## `0x80050d28` (jump-table de SCE `0x8009e0bc[1]`) pede `a0 = 0x216` em `0x80050ed8` /
	## `0x80050f14` no caminho "não tem a chave" e em `0x80050e10` quando `Key_Type == 0xff`.
	##
	## O port **não tem a amostra**: o único banco de sala no disco é `R000.SND` e a tabela de
	## SE dele é toda `0xffffffff`. Devolve false — sem inventar som de outro banco.
	return tocar_acao("porta_trancada")


func porta_destrancar() -> bool:
	## Destrancou com a chave: `cat 2 / id 0x25` (`0x80050e74`, caminho "tem a chave";
	## `Knock_Type != 0` usa o id 4). Mesma ressalva de amostra que `porta_trancada`.
	return tocar_acao("porta_destrancar")


func definir_banco_porta(porta: Variant) -> void:
	## Diz qual porta está sendo usada. Aceita:
	##   • o **índice** `Dtex_Type` (int 0..75) — é o que o SCD guarda e o que
	##     `data/porta_banco.json` publica por sala/AOT;
	##   • o nome do banco (`"S1_DOOR03"`, `"DOOR03"`).
	##
	## Cada `DOORxx.DOn` traz o próprio banco de som — é o que dá porta de madeira ≠ portão de
	## metal. Os 76 arquivos são **byte-idênticos nos 7 stages** (medido), então o índice basta:
	## o prefixo `S1_` do nome no `re3_se.json` é histórico, não semântico.
	## Vazio/inválido = cai no padrão do `re3_se.json`.
	var nome := ""
	if porta is int:
		nome = NOME_BANCO_PORTA % int(porta)
	elif porta is String:
		nome = porta as String
		if nome.begins_with("DOOR"):
			nome = "S1_" + nome
	_banco_porta = nome if _bancos.has(nome) else ""


func banco_porta() -> String:
	return _banco_porta


func _tocar_porta(acao: String) -> bool:
	if _banco_porta != "":
		var a: Variant = _acoes.get(acao)
		if a is Dictionary:
			var pb: Variant = (a as Dictionary).get("por_banco")
			if pb is Dictionary and (pb as Dictionary).has(_banco_porta):
				return tocar_arquivo(str((pb as Dictionary)[_banco_porta]))
	return tocar_acao(acao)


# ───────────────────────────── API genérica ─────────────────────────────
func tocar_acao(acao: String) -> bool:
	## Toca uma ação nomeada do `re3_se.json`. false se o nome ou o WAV não existir — e
	## **RECLAMA ALTO** nos dois casos (era aqui que o som do tiro sumiria em silêncio).
	var a: Variant = _acoes.get(acao)
	if not (a is Dictionary):
		_reclamar("acao:%s" % acao,
			"ação '%s' não existe no data/%s — rode `NOSTALGIA_OUT=port python tools/exe_audio.py`"
			% [acao, DADOS])
		return false
	var rel: Variant = (a as Dictionary).get("wav_padrao")
	if not (rel is String) or rel == "":
		_reclamar("acao_sem_wav:%s" % acao,
			"ação '%s' (cat %d / id %d) existe mas não tem amostra: o tom aponta o VAG mudo ou o "
			% [acao, acao_cat(acao), acao_id(acao)]
			+ "banco não está no disco extraído")
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
	## Fora da árvore (harness de teste: os testes são `RefCounted`, não cena) o `play()` do motor
	## só produz `ERROR: Playback can only happen when a node is inside the scene tree`. O de-para
	## já foi resolvido aqui, que é o que o teste mede — então só o `play()` é pulado.
	if p.is_inside_tree():
		p.play()
	_ultimo = rel
	return true


func definir_banco_area(nome := BANCO_JOGADOR) -> void:
	## Diz qual banco `C_xx` (cat 0) está carregado. **Agora é MEDIDO**, e o que ele seleciona
	## é o PERSONAGEM, não a área:
	##
	## O room-loader `0x800493ec` chama o carregador de banco `0x8007809c` em `0x800495d0`
	## com `a0 = 0` (cat 0) e `a1 = 8` quando `*(gs+0x784e) >= 8`, senão `a1 = 2`
	## (`0x800494f0` / `0x800495a4`). Em `0x8007809c`, `a1` é o **número do banco**:
	## `fileid = *(0x800110b0 + cat*4) + a1*2`, e `0x800110b0` = `{0x104, 0x103, 0xda, 0xd9}`
	## → `C_xx.VH = 0x104 + xx*2`, `A_xx.VH = 0xda + xx*2`. Os dois intervalos são contíguos
	## e não se sobrepõem (`A_01`=0xdc … `A_14`=0x102, `C_00`=0x104 … `C_0D`=0x11e), o que
	## confere com a ordem dos arquivos no disco.
	##
	## Logo: **`C_02` = banco do jogador (Jill)** e `C_08` = o outro conjunto (`>= 8`, os
	## Mercenaries têm PLD/PLW próprios). O port só joga com a Jill → `C_02`.
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
	##
	## Reclama COM O CAMINHO quando o arquivo falta ou não carrega. Sem isto, "o som não sai" e
	## "a amostra não foi extraída" ficam indistinguíveis do lado de quem joga — foi exatamente
	## a dúvida do dono do repo sobre o tiro.
	if _cache.has(rel):
		return _cache[rel]
	var abs_path := AssetIO.path("%s/%s" % [SFX_DIR, rel])
	if not FileAccess.file_exists(abs_path):
		_reclamar("falta:%s" % rel,
			"amostra AUSENTE: %s — rode `NOSTALGIA_OUT=port python tools/re3_sfx.py --all` " % abs_path
			+ "(bancos do disco) e `... tools/exe_audio.py --portas` (bancos de porta)")
		return null
	var s := AudioStreamWAV.load_from_file(abs_path)
	if s == null:
		_reclamar("ilegivel:%s" % rel,
			"AudioStreamWAV.load_from_file falhou em %s (WAV corrompido?)" % abs_path)
		return null
	_cache[rel] = s
	return s


func _reclamar(chave: String, msg: String) -> void:
	## Um aviso por chave: o pedido de SE acontece a 30 Hz e um `push_warning` por quadro
	## afogaria o log (e esconderia justamente o aviso que importa).
	if _reclamou.has(chave):
		return
	_reclamou[chave] = true
	push_warning("Sfx: %s" % msg)
	print("[sfx] AVISO: %s" % msg)
