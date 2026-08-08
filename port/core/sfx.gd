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
## **1 = `A_xx`**, **2 = banco da SALA**, **4 = porta** (banco embutido em cada
## `STAGE*/DOORxx.DOn` — é o recurso que o loader `0x80012818` puxa com a string de
## depuração `"DOOR SOUND"` de `0x800103ac`).
##
## Quantos ids cada `cat` tem é a tabela `0x800a0fe4` = `{16, 32, 48, 32, 4}`, lida em
## `0x80078390`: **`cat 2` tem 48 ids**.
##
## ── O banco de SALA (`cat 2`) — extraído nesta rodada ──
## Era o buraco que deixava 26 dos 155 pedidos de SE mudos. O único banco de sala no disco é
## `R000.SND` (tabela toda `0xffffffff`); os outros **169 estão EMBUTIDOS nos `R???.ARD`**:
## tabela de 48 ids + header VAB no RDT, e o **corpo PS-ADPCM é o sub-bloco 9 do contêiner**
## (`len(bloco 9) == u32@hdr+0x00` em 169/169, e com essa base os 1871 VAG terminam todos em
## flag de fim). `tools/exe_audio.py --salas` extrai **1702 amostras**.
## Quem diz ao `Sfx` qual sala está carregada é `definir_banco_sala()` — o `Audio` chama isso
## no mesmo lugar em que troca a BGM da sala, que é o equivalente do room-loader
## `0x800493ec` do original.
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
## `cat 1 / id 1` = CLIQUE SECO (pediu recarga sem bala) — ver `arma_vazia()`.
const SE_ARMA_VAZIA := 1
## Sequência da animação de RECARGA no banco 2 do `.PLW` — ver `seq_de_recarga()`.
const SEQ_RECARGA_PADRAO := 7

## Ações nomeadas com confiança ALTA — o que a UI pode usar sem ressalva.
const ACOES_MENU := ["menu_mover", "menu_cancelar", "menu_confirmar",
	"menu_invalido", "menu_abrir"]

## ── ids de `cat 2` (banco de SALA) que o EXE pede, por call site ──
## Os 26 `jal 0x800746c0` de `cat 2` estão em `data/se_callsites.json`. Os que têm id
## constante ficam aqui, para nenhum número ser digitado duas vezes.
const SE_SUBIR := 0                 ## 0x8003b224 — início do subir/descer (macro-ação 9)
const SE_BAU_ABRIR := 20            ## 0x80051578 — abrir a caixa de itens
const SE_BAU_MOVER := 21            ## 4 sítios em 0x800646f0 — transferir item
const SE_PORTA_TRANCADA := 22       ## 0x80050e10 / 0x80050ed8 / 0x80050f14
const SE_PORTA_DESTRANCAR := 37     ## 0x80050e74 (Knock_Type == 0)
const SE_PORTA_EMPERRADA := 38      ## 0x80050dd8 (Key_Type == 0xfe)
const SE_PORTA_DESTRANCAR_KNOCK := 4    ## 0x80050e74 com Knock_Type != 0 (4 das 453 portas)
const SE_PORTA_TRANCADA_KNOCK := 5      ## 0x80050ed8 / 0x80050f14 com Knock_Type != 0
const SE_SUBIR_IMPACTO := 44        ## 0x8003b3e8 — impacto ao terminar de subir
const SE_MAPA_NAVEGAR := 43         ## 0x8006f790 — navegação da tela de MAPA
const SE_INIMIGO_T21 := 42          ## 0x8001db0c — IA do inimigo tipo 21
const SE_ZUMBI := 14                ## 0x8001edb8 — `14 ou 30` pelo estado do zumbi
const SE_ZUMBI_ALT := 30
const SE_ATOR_19 := 19              ## 0x80021cdc e 0x80036934 — NÃO IDENTIFICADO
const SE_ATOR_2 := 2                ## 0x80036b8c — NÃO IDENTIFICADO
const SE_SCE11_40 := 40             ## 0x800517d0 — NÃO IDENTIFICADO
const SE_DRAW_46 := 46              ## 0x80024f04 / 0x80025038 / 0x800250f0 — NÃO IDENTIFICADO

## Resultado de `porta_usada()` — reproduz os 4 desfechos de `0x80050d28`.
enum Porta {
	LIVRE,          ## a porta não é trancada (bit 0x80 de Key_Id apagado) — sem SE aqui
	DESTRANCOU,     ## tinha a chave: id 37 (ou 4 se Knock_Type != 0) + mensagem 5
	TRANCADA,       ## não tem a chave: id 22 (ou 5) + mensagem
	EMPERRADA,      ## Key_Type == 0xfe: id 38 + mensagem 0x11
	NUNCA_ABRE,     ## Key_Type == 0xff: id 22 + mensagem 0x12
}

var _dados: Dictionary = {}
var _acoes: Dictionary = {}
var _bancos: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _prox := 0
var _cache: Dictionary = {}                     ## rel -> AudioStreamWAV
var _banco_area := ""                           ## banco C_ da área atual (ver definir_banco_area)
var _banco_porta := ""                          ## banco da porta em uso (ver definir_banco_porta)
var _banco_arma := ""                           ## banco A_ da arma equipada (ver definir_banco_arma)
var _banco_sala := ""                           ## banco cat 2 da sala atual (ver definir_banco_sala)
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
	## **CORRIGIDO nesta rodada: o id 9 NÃO é "abrir a tela de status".** Ele é *entrar em outra
	## SUB-TELA* — mapa ou arquivo. Os 5 call sites, todos medidos:
	##   • `0x80023db8` com `a0 = 9` **só quando `*(u8*)0x800e01c4 (ctx+0x04) == 4`**, que é o
	##     modo MAPA (setado pelo L2 em `0x80023cd0`; ver `menu_pc_sys.md §5`). Quando o modo é
	##     0 (= a tela de STATUS, setada pelo botão de menu em `0x80023cb0`) o **mesmo** `jal`
	##     recebe `a0 = 6` — o `bne ctx+0x04, 4` de `0x80023da4` escolhe entre os dois com o
	##     imediato no delay slot (`addiu a0, zero, 6` em `0x80023da8`).
	##   • `0x800666f0` (cursor da grade em `ctx+0x1c == -1` → sub-estado 4 = MAPA) e
	##     `0x80066728` (`ctx+0x1c == -2` → sub-estado 5 = ARQUIVO), no handler da grade
	##     `0x80066604`.
	##   • `0x8006dd40`, no braço 5 da tabela de init `0x8001100c` (kind 5 = mensagem/mapa por
	##     item usado).
	##   • `0x8006fdb4`, no sub-dispatcher do mapa.
	## Ou seja: use isto para ARQ./MAPA, **não** para abrir/fechar o inventário.
	return tocar_acao("menu_abrir")


func menu_status_abrir() -> bool:
	## Abrir a tela de STATUS/INVENTÁRIO pelo botão de menu: **SE id 6** (o mesmo do "confirmar").
	##
	## MEDIDO: `0x80023c9c` testa `log_edge & 0x4000` (botão de menu), liga `0x800d1f2c |= 0x200`
	## e grava `ctx+0x04 = 0` (`0x80023cb0`). Ainda no mesmo quadro, `0x80023d58` vê a flag `0x200`
	## e cai em `0x80023d60`, que arma a task (`0x800c7961 = 1`, `0x800d1f2c |= 0x100`) e pede o SE
	## em `0x80023db8` — com `a0 = 6`, porque `ctx+0x04` é 0 e o `bne ..., 4` de `0x80023da4` é
	## TOMADO (delay slot `addiu a0, zero, 6`). O `a0 = 9` de `0x80023dac` só roda no modo 4.
	return tocar_acao("menu_confirmar")


func menu_fechar() -> bool:
	## FECHAR a tela de status: **SE id 5** (o de cancelar) — e é por isso que fechar soa
	## diferente de abrir, sem precisar de id próprio.
	##
	## MEDIDO no handler da grade (`0x80066604`, sub-estado 0 da tabela `0x800a0100`): o teste
	## `(raw_edge & 0x0020) | (log_edge & 0x2000)` em `0x80066628`..`0x80066634` desvia para
	## `0x80066744`, que carrega `a0 = 5`, pede o SE em `0x8006675c` e **incrementa `ctx+0x10`**
	## em `0x80066750`/`0x80066760` — o estado 2 vira 3, cujo handler (`0x8006a888`) põe
	## `ctx+0x10 = 13` = o FECHAMENTO (`0x8006e4cc`).
	##
	## O botão SAIR cai no MESMO código: com `ctx+0x1c < -2` (`slti` em `0x80066738`) o fluxo
	## desce para `0x80066744`. Logo os dois caminhos de fechar usam o id 5, e **nenhum** usa o 9.
	return tocar_acao("menu_cancelar")


func tiro() -> bool:
	## Disparo. **CORRIGIDO nesta rodada: o estouro da arma é `cat 1 / id 0`**, do banco `A_{w}`
	## da arma equipada — não o `cat 0 / id 11` que estava aqui antes.
	##
	## Duas provas independentes:
	##  1. **Tabela de 20 funções POR ARMA** em `0x8009ced8..0x8009cf24` (vizinha da tabela de
	##     timing `0x8009cf28` que o `Player.quadro_do_corte()` já usa). Em CADA entrada o mesmo
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


func dano_player(variante := 0) -> bool:
	## O player TOMOU dano. **Isto era `impacto_ataque` e o rótulo estava ERRADO** (dizia "o
	## ataque do player conectou").
	##
	## MEDIDO na varredura dos 155 `jal 0x800746c0`: os 5 pedidos de `cat 0 / ids 0..3` estão
	## todos em `0x8003d1a8`, `0x8003d2d8`, `0x8003d4c0`, `0x8003d780` e `0x8003da3c`, e essas
	## cinco funções são a REAÇÃO DE DANO — `exe_combat.md §1.3` mediu por exaustão os 168
	## escritores de `player+0xc8` e as anims de hurt são 4/5/9/10/11/12, com escritores
	## `0x8003d200` (esta função, anim 4), `0x8003d52c`, `0x8003d630`, `0x8003d6ec`,
	## `0x8003d72c`, `0x8003d910` e `0x8003d990` — todos dentro dessas mesmas funções. O idioma
	## é idêntico nas cinco: `player+0xc8 = anim`, `player+6 = 1`, `SE_pede(..., a1 = player+0x34)`.
	##
	## `variante` 0..3 escolhe o id; qual gravidade é qual continua DECLARADO (o `0x8003d354`
	## alterna entre 1 e 2 pela paridade de `u8 @ player+5`).
	const NOMES := ["dano_player", "dano_player_2", "dano_player_3", "dano_player_4"]
	return tocar_acao(NOMES[clampi(variante, 0, 3)])


func agarrado() -> bool:
	## Player AGARRADO/mordido: `cat 0 / id 11` em `0x8003cf10` — sub 0 da macro-ação 13
	## (`0x8003cea0`), que grava anim 18 (`player+0xc8 = 0x30012`), liga `gs+0x77f4 |= 0x100`,
	## INCREMENTA `u16 gs+0x785e` e, no mesmo bloco (`0x8003d114`), pede um SE de **cat 3**
	## (banco do INIMIGO, id 3 ou 19 pelo tipo) — os dois soando juntos.
	## Nome DECLARADO: o id 11 é o mesmo que a rotina 7 (mira) pede em `0x8003ad6c`.
	return tocar_acao("agarrado")


func arquivo_pagina() -> bool:
	## VIRAR A PÁGINA de um documento. **`cat 0 / id 8`, MEDIDO** — era a peça que faltava.
	##
	## `0x80063850` é o estado 8 da task do menu (a tela de ARQUIVO). No sub-estado 0:
	##   • `*(0x800cc830) & 0x8000` **e** `ctx+0xbd != 0` → `0x80063948` põe `a0 = 8`, faz
	##     `ctx+0xbd -= 1`, grava `ctx+0xc6 = 2` e `ctx+0x11++`; o pedido é `0x80063984`;
	##   • `*(0x800cc830) & 0x2000` **e** `ctx+0xbd < u16 *(0x8009f2ac + ctx+0xbc*2) - 1` →
	##     `0x800639f0` põe `a0 = 8`, faz `ctx+0xbd += 1`, `ctx+0xc6 = -2`; pedido em `0x80063a2c`.
	## Ou seja **os dois únicos call sites do id 8 no EXE são as duas direções de virar página**,
	## cada um com a checagem de borda (`0x8009f2ac` = nº de páginas por documento). Só toca
	## quando a página REALMENTE vira — é o que `MenuArquivo.virar_pagina` reproduz.
	##
	## Atenção ao banco: `C_00`/`C_01` (bancos de MENU) **não definem o id 8**; quem define são
	## os `C_02..C_0D` de personagem, que é o banco de `cat 0` carregado em jogo
	## (`definir_banco_area`). O `re3_se.json` já cai no `C_02` como `banco_declarado`.
	return tocar_acao("arquivo_pagina")


func item_pego() -> bool:
	## Item entrou no inventário: `cat 0 / id 5` — o MESMO id do "cancelar", e é o dado que
	## manda. Os dois pedidos da janela de OBTER ITEM (`0x80069c3c`, sub 0xb / kind 1) são
	## `0x80069ed0` (`a0 = 5` imediato) e `0x80069fb0`, cujo `a0` sai do delay slot do
	## `beq v0,a1,0x80069f9c` de `0x80069eb8` — único predecessor daquele bloco.
	return tocar_acao("item_pego")


func combinar_ok() -> bool:
	## Combinação deu certo: `cat 0 / id 6` em `0x80068a10`, no executor genérico da combinação
	## (`0x80068024`). O `a0` não é imediato no bloco: os **7** predecessores de `0x800689b0`
	## (`0x8006857c` `0x800685c4` `0x80068660` `0x800686a4` `0x8006884c` `0x8006892c`
	## `0x80068970`) carregam TODOS `a0 = 6`.
	return tocar_acao("combinar_ok")


func combinar_erro() -> bool:
	## A receita não fecha: `cat 0 / id 7` em `0x800687b0`, mesmo executor `0x80068024`.
	return tocar_acao("combinar_erro")


func examinar() -> bool:
	## CHECK/examinar: `cat 0 / id 6` em `0x80069454` (comando 2, `0x80069280`).
	return tocar_acao("examinar")


func equipar() -> bool:
	## USE/EQUIP: `cat 0 / id 5` em `0x80067b40` — o ÚNICO pedido de SE do comando 0
	## (`0x800676b8`).
	return tocar_acao("equipar")


func mensagem_avanca() -> bool:
	## Caixa de mensagem avança: `cat 0 / id 4` (`0x8003054c`, `0x800308f8`).
	return tocar_acao("mensagem_avanca")


func mensagem_fecha() -> bool:
	## Caixa de mensagem fecha: `cat 0 / id 5` (`0x800304e0`, `0x8003088c`).
	return tocar_acao("mensagem_fecha")


func subir() -> bool:
	## SUBIR/DESCER (a macro-ação 9, que `port/script_vm/subir.gd` reimplementa): `cat 2 / id 0`
	## em `0x8003b224`. **Banco de SALA** — desde a extração dos 169 bancos embutidos nos
	## `R???.ARD` isto TOCA, desde que `definir_banco_sala()` tenha sido chamado.
	## Só **9 salas** definem o id 0; nas outras o motor original também fica em silêncio
	## (o descritor é `0xffffffff` e `0x80074770` descarta).
	return se_de_sala(SE_SUBIR)


func subir_impacto() -> bool:
	## Impacto ao terminar de subir/descer: `cat 2 / id 44` em `0x8003b3e8` (sub 5 com
	## `+0xc9 == 1`) — é o `SFX_IMPACTO` que `subir.gd` já sinaliza. 5 salas definem o id.
	return se_de_sala(SE_SUBIR_IMPACTO)


func bau_abrir() -> bool:
	## Abrir a CAIXA DE ITENS: `cat 2 / id 20` em `0x80051578`, dentro do driver de tela
	## `0x800514f0` que o `sce 9` instala em `gs+0x75e0`. **20 salas** definem o id — e são
	## justamente as que têm baú (a `R100` é uma delas), o que é sanidade a favor da base da
	## tabela de SE usada na extração.
	return se_de_sala(SE_BAU_ABRIR)


func bau_mover() -> bool:
	## Transferir item no baú: `cat 2 / id 0x15`, 4 sítios em `0x800646f0` (`0x80064b2c`,
	## `0x80064bc8`, `0x80064d1c`, `0x80064d90`). 19 salas definem o id.
	return se_de_sala(SE_BAU_MOVER)


func mapa_navegar() -> bool:
	## Único SE de `cat 2` da tela de MAPA: `id 43` em `0x8006f790` (`0x8006f708`). Os outros
	## 7 sítios daquela função são `cat 0`. 2 salas definem o id — o resto fica mudo, como no
	## original. Nome DECLARADO.
	return se_de_sala(SE_MAPA_NAVEGAR)


func ricochete(base: int, variante := 0) -> bool:
	## IMPACTO/RICOCHETE de bala na sala: `cat 2 / idx = base + a0`, em `0x80077b50` (a única
	## chamada de `0x800776b0`). MEDIDO: a `base` sai de `{0x17, 0x1a, retorno&0x7f}` ou `0x2d`
	## e o `a0` é 0 ou 1 — ver a CORREÇÃO de `exe_combat.md` no `_meta` do `re3_se.json`
	## (o doc antigo dizia que `0x800776b0` escolhia seco/tiro/vazio pelos bits `0x200/0x400`
	## de `player+0xe4`; não existe esse teste na função).
	##
	## Qual base vale em qual superfície **NÃO FOI MEDIDO** — por isso quem chama passa a base,
	## em vez de o `Sfx` adivinhar. As bases medidas estão em `RICOCHETE_BASES`.
	return se_de_sala(base + (1 if variante != 0 else 0))


## As bases de `idx` que `0x800776b0` usa para o SE de impacto na sala (MEDIDAS na função;
## qual corresponde a qual superfície não foi medido).
const RICOCHETE_BASES := [0x17, 0x1A, 0x2D]


func se_do_script(idx: int) -> bool:
	## SE pedido pelo BYTECODE: `cat 2`, `idx = próximo byte do stream`. MEDIDO em `0x80030010`
	## (dentro do interpretador de mensagem/cena `0x8002fee8`, cujos opcodes `0xEA..0xFE` —
	## jump-table `0x80010508`, 21 entradas — leem um byte e o transformam neste pedido).
	## É o caminho por onde o script toca som de ambiente da sala.
	return se_de_sala(idx)


func se_de_objeto(idx: int, alterna := false) -> bool:
	## SE de OBJETO do cenário (tipo 5/6): `cat 2`, `idx = u16 @ obj+0x22`. Dois sítios em
	## `0x8001c5bc`: `0x8001c864` pede o idx cru e `0x8001c838` pede `idx + (rand & 1)` — as
	## duas variantes de um mesmo par de amostras. `alterna` reproduz o segundo.
	return se_de_sala(idx + (1 if alterna else 0))


func se_de_inimigo_na_sala(idx: int) -> bool:
	## Sons de inimigo que saem do banco da SALA (não do `cat 3`): `id 42` da IA do tipo 21
	## (`0x8001db0c`, em `0x8001d7d0`) e `id 14`/`30` do ZUMBI (`0x8001edb8`, em `0x8001e444`).
	## Nomes DECLARADOS. Use `SE_INIMIGO_T21`, `SE_ZUMBI`, `SE_ZUMBI_ALT`.
	return se_de_sala(idx)


func se_de_sala(id_se: int) -> bool:
	## O pedido cru `cat 2 / id_se` no banco da SALA carregada. É por aqui que passam TODOS os
	## 26 pedidos de `cat 2` do EXE — inclusive os que seguem `NÃO IDENTIFICADOS`
	## (`SE_ATOR_19`, `SE_ATOR_2`, `SE_SCE11_40`, `SE_DRAW_46`), que ficam expostos com esse
	## nome exatamente para não fingir que sabemos o evento.
	##
	## Devolve false, sem reclamar, quando o banco da sala não define o id: é o que
	## `0x80074770` faz com o descritor `0xffffffff`. Reclama só quando NENHUM banco de sala
	## está selecionado — aí é bug de integração, não silêncio do dado.
	if _banco_sala == "":
		_reclamar("sem_banco_sala",
			"nenhum banco de SALA (cat 2) selecionado — chame Sfx.definir_banco_sala(<sala>) "
			+ "ao carregar a sala (o Audio já faz isso em tocar_bgm_da_sala)")
		return false
	return tocar_id(2, id_se, _banco_sala)


func definir_banco_sala(sala_id: String) -> bool:
	## Diz qual banco `cat 2` está carregado. O banco de sala tem o **nome da sala**
	## (`R100`, `R10D`, ...) porque é o próprio `R???.ARD` que o embute.
	##
	## No original quem faz isso é o room-loader `0x800493ec` (o mesmo que carrega o `C_02` de
	## `cat 0` em `0x800495d0`); o registro é `0x8007836c(a0 = 2, a1 = base da tabela de SE)`,
	## que grava `*(0x800e0610 + 2*4)` e deriva o header VAB como `a1 + 48*4`.
	## No port o gancho equivalente é `Audio.tocar_bgm_da_sala()`, chamado na troca de sala.
	if _bancos.has(sala_id):
		_banco_sala = sala_id
		return true
	_banco_sala = ""
	if sala_id != "":
		_reclamar("banco_sala:%s" % sala_id,
			"banco de sala '%s' não existe no data/%s — rode " % [sala_id, DADOS]
			+ "`NOSTALGIA_OUT=port python tools/exe_audio.py` e `... --salas`")
	return false


func banco_sala() -> String:
	return _banco_sala


func impacto_projetil() -> bool:
	## `cat 0 / id 13` (`0x80045b10`, `0x80045e68`, `0x800465fc`, todos em `0x80045950` = a
	## colisão/integração de projétil). Nome DECLARADO.
	return tocar_acao("impacto_projetil")


func sala_entrada() -> bool:
	## `cat 0 / id 14` (`0x80077f40` em `0x80077ed4`, chamada por `0x800495fc` DENTRO do
	## room-loader `0x800493ec`). Nome DECLARADO.
	return tocar_acao("sala_entrada")


func arma_mecanismo(idx: int) -> bool:
	## Som de MECANISMO da arma: `cat 1 / idx`, do banco `A_{w}`. Use `arma_evento()` quando o
	## que você tem é (sequência, quadro) — é assim que o motor decide o `idx` (ver abaixo).
	if idx < 0:
		return false
	return tocar_id(1, idx, _banco_arma)


func arma_vazia() -> bool:
	## **CLIQUE SECO — pediu recarga e não tem bala.** `cat 1 / id 1`, do banco da arma.
	##
	## MEDIDO: os 4 sítios de `cat 1 / id 1` do EXE são o MESMO idioma, em 4 subestados de arma
	## (`0x8003f190` no sub 1 = mira/hold · `0x8003fd90` no sub 8 = mira de corpo inteiro ·
	## `0x8004029c` · `0x8004070c`):
	## ```
	## if (*(gs+0x2108) & 0x40) {                     ; pedido de RECARREGAR
	##     if (0x8006cf0c(0) == -1)  SE cat 1 / id 1  ; a munição NÃO está no inventário
	##     else                      player+6 = 4    ; TEM -> vai para o subestado de RECARGA
	## }
	## ```
	## `0x8006cf0c(a0 = 0)` é a CONSULTA de munição (`exe_items.md §144`): com `a0 = 0` ela não
	## consolida nada e sai por `0x8006cf84` com `v0 = 0` quando `0x8006cc8c` **acha** o item de
	## munição, ou com `v0 = -1` quando **não acha**. Logo o SE só sai no ramo "sem bala".
	##
	## Sanidade: `A_01` (a FACA) é um dos dois únicos bancos de arma que **não** definem o id 1
	## — e faca não recarrega. O NOME "clique seco" é DECLARADO; o ramo é medido.
	return tocar_id(1, SE_ARMA_VAZIA, _banco_arma)


func recarregar(quadro := -1) -> bool:
	## **RECARGA.** O som dela **não tem id fixo** — são EVENTOS POR QUADRO da animação de
	## recarga. `quadro < 0` toca o PRIMEIRO evento da sequência de recarga (útil para quem
	## ainda não anima quadro a quadro); com `quadro >= 0` toca só se aquele quadro exato tem
	## evento, que é o comportamento do motor.
	##
	## MEDIDO em `0x8003f5b0..0x8003f5e8` (subestado 4, `0x8003f520`, que grava
	## `player+0xc8 = 0x00070007` = sequência 7 do banco 2 do `.PLW`):
	## ```
	## v0 = u16 @ *(player+0xe4)      ; o QUADRO corrente da frame-list do EDD
	## if ((v0 & 0xf000) == 0) pula   ; nibble 0 = quadro sem som
	## a0 = 0x10100 | ((v0 >> 12) - 1)
	## ```
	## E `player+0xe4` é o **cursor da frame-list**, escrito pelo avançador de animação
	## (`0x8001ae04`/`0x8001ae20`, que caminha pelo bit `0x100` de cada u16, e
	## `0x80026ca8`/`0x80026cc0` dentro de `0x80026be8` — chamado pelos subestados com
	## `gs+0x2614`/`gs+0x2618` = o banco 2 do `.PLW`). Ou seja o id **é dado do disco**, e
	## `tools/exe_audio.py --armas` o extrai: 58 eventos nas 21 armas.
	##
	## Exemplo (pistola, `w = 2`): `seq 7 quadro 7 -> id 3` e `quadro 23 -> id 5` — os dois
	## tempos da recarga (soltar e encaixar o pente).
	var evs := eventos_da_arma(seq_de_recarga())
	if evs.is_empty():
		return false
	if quadro < 0:
		return arma_mecanismo(int((evs[0] as Dictionary).get("id", -1)))
	for e: Variant in evs:
		if int((e as Dictionary).get("quadro", -1)) == quadro:
			return arma_mecanismo(int((e as Dictionary).get("id", -1)))
	return false


func arma_evento(seq: int, quadro: int) -> bool:
	## O SE de mecanismo daquele (sequência, quadro) da arma equipada, se houver. É o pedido
	## exato do motor: um evento por quadro de animação (ver `recarregar()`).
	## Sequências medidas: **7 = recarga**, **1/3/5 = as três variantes de FOGO**
	## (`recuo_tiro.md`); o resto do banco 2 não tem rótulo medido.
	for e: Variant in eventos_da_arma(seq):
		if int((e as Dictionary).get("quadro", -1)) == quadro:
			return arma_mecanismo(int((e as Dictionary).get("id", -1)))
	return false


func eventos_da_arma(seq := -1) -> Array:
	## Os eventos de som por quadro da arma equipada: `[{seq, quadro, id, wav}]`.
	## `seq < 0` devolve todos. Vem de `re3_se.json.eventos_arma`, extraído do `.PLW`.
	var ea: Variant = _dados.get("eventos_arma")
	if not (ea is Dictionary):
		return []
	var pa: Variant = (ea as Dictionary).get("por_arma")
	if not (pa is Dictionary):
		return []
	var out: Array = []
	for w: String in pa as Dictionary:
		var e: Dictionary = (pa as Dictionary)[w]
		if str(e.get("banco", "")) != _banco_arma:
			continue
		for it: Variant in (e.get("eventos", []) as Array):
			if seq < 0 or int((it as Dictionary).get("seq", -1)) == seq:
				out.append(it)
	return out


func seq_de_recarga() -> int:
	## Índice da sequência de RECARGA no banco 2 do `.PLW`. **7** em 20 das 21 armas
	## (`player+0xc8 = 0x00070007` no subestado 4, `0x8003f554`); a `w = 15` é a exceção
	## medida — o banco 2 dela tem 11 sequências e os eventos de recarga estão na **10**.
	var ea: Variant = _dados.get("eventos_arma")
	if ea is Dictionary:
		var m: Variant = (ea as Dictionary).get("_meta")
		if m is Dictionary and (m as Dictionary).has("seq_recarga"):
			var padrao := int((m as Dictionary)["seq_recarga"])
			## se a arma equipada não tem evento na seq padrão, usa a maior seq com evento
			var maior := -1
			for e: Variant in eventos_da_arma():
				maior = maxi(maior, int((e as Dictionary).get("seq", -1)))
				if int((e as Dictionary).get("seq", -1)) == padrao:
					return padrao
			return maior
	return SEQ_RECARGA_PADRAO


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


func porta_trancada(knock := 0) -> bool:
	## Porta trancada. É **cat 2 (banco de SALA)**, não o banco da porta: o produtor de porta
	## `0x80050d28` (jump-table de SCE `0x8009e0bc[1]`) pede `a0 = 0x216` em `0x80050ed8` /
	## `0x80050f14` no caminho "não tem a chave" e em `0x80050e10` quando `Key_Type == 0xff`.
	## Com `Knock_Type != 0` (4 das 453 portas) o id é **5** em vez de 22 (`0x80050ec8`).
	##
	## Agora TOCA: 33 salas definem o id 22 no banco embutido no `.ARD`.
	return se_de_sala(SE_PORTA_TRANCADA_KNOCK if knock != 0 else SE_PORTA_TRANCADA)


func porta_emperrada() -> bool:
	## Porta BLOQUEADA (`Key_Type == 0xfe`, 10 das 453 portas em 9 salas): `cat 2 / id 38` em
	## `0x80050dd8`, junto da mensagem `0x11`.
	##
	## **As 9 salas que registram uma porta `Key_Type == 0xfe` definem TODAS o id 38** — e é
	## essa correlação, entre dois dados independentes (o SCD e a tabela de SE do banco), que
	## provou onde a tabela de SE da sala começa. Ver `exe_audio.md §13`.
	return se_de_sala(SE_PORTA_EMPERRADA)


func porta_destrancar(knock := 0) -> bool:
	## Destrancou com a chave: `cat 2 / id 0x25` (`0x80050e74`, caminho "tem a chave"), ou
	## **id 4** quando `Knock_Type != 0` (`0x80050e64`). 24 salas definem o id 37.
	return se_de_sala(SE_PORTA_DESTRANCAR_KNOCK if knock != 0 else SE_PORTA_DESTRANCAR)


func porta_trancamento(sala: String, aot: int) -> Dictionary:
	## Os campos de trancamento daquela porta, lidos do `data/porta_banco.json` (extraído do
	## SCD por `tools/exe_audio.py --portas-salas`):
	## `{trancada, flag, key_type, key_id, knock}` — ou `{}` se a porta não estiver no mapa.
	##
	## **`Key_Id` (descriptor+0x0f) não é só o id da chave**: MEDIDO em `0x80050d74`..`0x80050d80`,
	## o **bit 0x80 é o "esta porta é trancada"** (sem ele `0x80050d28` desvia direto para
	## `0x80050f3c` e a porta abre, sem SE nenhum) e os **bits 0..5 são o índice da flag** de
	## "já destrancada", usada em `0x80078930(gs+0x7994, key_id & 0x3f)` para testar e em
	## `0x800788dc(...)` para marcar depois de usar a chave. Quem é a CHAVE é o `Key_Type`
	## (`+0x10`), que `0x8006cc8c` procura no inventário.
	## Duas salas registram DUAS portas no mesmo índice de AOT com trancamento diferente
	## (`R203` aot 0: `key_id` 128 e 0 · `R508` aot 2: 0 e 139). Como o `SCE_DOOR_AOT_SET`
	## escreve no SLOT do AOT, o registro MAIS RECENTE vence — então aqui vale o ÚLTIMO do
	## SCD. Qual dos dois o script realmente instala depende do fluxo em runtime, logo isto é
	## **DECLARADO**, não medido.
	var v: Variant = _portas.get(sala)
	if not (v is Array):
		return {}
	var achado: Dictionary = {}
	for e: Variant in v as Array:
		if e is Dictionary and int((e as Dictionary).get("aot", -1)) == aot:
			var d := e as Dictionary
			var kid := int(d.get("key_id", 0))
			achado = {
				"trancada": (kid & 0x80) != 0,
				"flag": kid & 0x3F,
				"key_type": int(d.get("key_type", 0)),
				"key_id": kid,
				"knock": int(d.get("knock", 0)),
			}
	return achado


func porta_usada(sala: String, aot: int, tem_chave := false, ja_destrancada := false) -> Porta:
	## Reproduz o produtor de porta **`0x80050d28`** (o SCE 1 da jump-table `0x8009e0bc`), que é
	## o que roda quando o personagem USA uma porta. Toca o SE certo e devolve o desfecho, para
	## quem chama decidir se atravessa e qual mensagem mostrar. A ordem é a do binário:
	##
	## ```
	## if (u8@desc+0x0f & 0x80) == 0        -> 0x80050f3c : porta LIVRE, nenhum SE
	## if 0x80078930(gs+0x7994, kid & 0x3f) -> 0x80050f3c : já destrancada, nenhum SE
	## Key_Type == 0xfe                     -> SE 38 (0x80050dd8) + mensagem 0x11
	## Key_Type == 0xff                     -> SE 22 (0x80050e10) + mensagem 0x12
	## 0x8006cc8c(Key_Type) >= 0 (TEM)      -> mensagem 5, SE Knock ? 4 : 37 (0x80050e74),
	##                                        instala 0x80050fe0 e MARCA a flag (0x800788dc)
	## senão                                -> SE Knock ? 5 : 22 (0x80050ed8 / 0x80050f14)
	## ```
	##
	## O `Sfx` não guarda o estado das portas (`gs+0x7994` é do jogo): quem chama passa
	## `ja_destrancada` e `tem_chave`. Um só `if` no `World.atravessar` liga tudo isto.
	var t := porta_trancamento(sala, aot)
	if t.is_empty() or not bool(t.get("trancada", false)):
		return Porta.LIVRE
	if ja_destrancada:
		return Porta.LIVRE
	var kt := int(t.get("key_type", 0))
	var knock := int(t.get("knock", 0))
	if kt == 0xFE:
		porta_emperrada()
		return Porta.EMPERRADA
	if kt == 0xFF:
		se_de_sala(SE_PORTA_TRANCADA)
		return Porta.NUNCA_ABRE
	if tem_chave:
		porta_destrancar(knock)
		return Porta.DESTRANCOU
	porta_trancada(knock)
	return Porta.TRANCADA


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
	# Se o banco daquele `cat` está carregado, prefere o som DELE — é o que o original faz (o
	# mesmo id toca amostra diferente por banco). Vale para o `C_` da área (cat 0), o `A_` da
	# arma (cat 1) e agora o banco da SALA (cat 2), que é o caso em que o id é o MESMO e a
	# amostra muda de sala para sala.
	var carregado := _banco_de(int((a as Dictionary).get("cat", -1)))
	if carregado != "":
		var pb: Variant = (a as Dictionary).get("por_banco")
		if pb is Dictionary and (pb as Dictionary).has(carregado):
			rel = (pb as Dictionary)[carregado]
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
	## Qual banco está CARREGADO em cada `cat`, na mesma divisão do motor
	## (`0x800e0664`, 8 slots): 0 = personagem/área, 1 = arma, 2 = SALA, 4 = porta.
	if cat == 0 and _banco_area != "":
		return _banco_area
	if cat == 1 and _banco_arma != "":
		return _banco_arma
	if cat == 2 and _banco_sala != "":
		return _banco_sala
	if cat == 4 and _banco_porta != "":
		return _banco_porta
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
