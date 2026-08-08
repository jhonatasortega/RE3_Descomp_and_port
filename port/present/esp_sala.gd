class_name EspSala
extends Node2D
## Efeitos **ESP da sala** (fogo, brasa, fumaça) — o que faltava no cenário do `R10D`.
##
## Irmão do `esp_brilho.gd` (que faz o cintilar do item, banco `0x05` do `ETC/CORE00.ESP`) e
## com a MESMA máquina: tabela A de quadros com duração em ticks de 30 Hz, sprite 4bpp
## recortado da VRAM, blend por `abr` do `tpage`, desenho em 2D sobre o quadro. A diferença
## é a fonte: aqui os bancos vêm do RDT da sala e quem cria os efeitos é o **script** dela.
##
## ── QUEM CRIA (provado no EXE, SLUS_009.23) ───────────────────────────────────────────
## Não é o carregador de sala: é o **opcode SCD `0x70`**, handler `0x80056004` (entrada
## `0x8009e2b8` da jump-table `0x8009e0f8`), 16 bytes, que chama `esp_spawn` (`0x8001b484`)
## direto — `jal 0x8001b484` em `0x8005608c`, `addiu $s0,$s0,0x10` em `0x80056094`.
## Campos lidos do handler:
##     +0x01 u8  TIPO do banco      (`lbu v1,1(s0)`  -> `id & 0xff`)
##     +0x02 u8  EFEITO             (`lhu s1,2(s0)`  -> `(id >> 8) & 0xff`)
##     +0x03 u8  VARIANTE (nibble)  (`srl a0,s1,8` · `andi 0xf` · `sll 0x18`)
##     +0x04 s8  âncora_tipo   } vão para `0x80055e38`, que devolve a `MATRIX*` (arg `a2`)
##     +0x05 s8  âncora_índice }
##     +0x06 u16 param_hi -> `slot+0x2e` = ESCALA base
##     +0x08..+0x0d 3 × s16 = `ofs` (SVECTOR passado em `a3`)
##     +0x0e u16 param_lo -> `slot+0x2c`
##
## ── ONDE APARECE (provado) ────────────────────────────────────────────────────────────
## `0x80055e38` com âncora_tipo `0` devolve **`0x80098970`**, que no binário é
## `00 10 00 00 00 00 | 00 00 00 10 00 00 | 00 00 00 00 00 10 | 00 00 | 00×12` — ou seja
## **matriz identidade com translação ZERO**. Logo, para âncora `0`, o `ofs` do opcode
## **é a posição absoluta de mundo do efeito**. Os outros casos (1..4) ancoram em
## personagem (`[0x800ccd94]+0x20`) ou objeto de sala (`0x800cea60 + i*0x194 + 0x20`) e por
## isso ficam de fora aqui (ver `carregar`).
##
## No `R10D` as 29 instâncias do `0x70` usam **âncora `(0,0)`**, e as 12 que rodam na
## ENTRADA da sala (`f0 → gosub f2 → gosub f38`, tudo em bloco incondicional) são:
##   • 4 × banco `0x24` e 4 × banco `0x26`, efeito `0x00` — **CHAMA**: 10 quadros de 48 px,
##     1 tick cada, `ctl_dur = 0xff` na 11ª entrada = LAÇO, `tpage_or = 0x20` = **aditivo**.
##     Pivô `oy = -48` (banco `0x24`) põe a BASE da chama exatamente no ponto âncora, que
##     está em `y = 0` — o chão. Conferido na folha
##     `assets/ESP/sala/R10D/_prova_bancos_v0.png`.
##   • 4 × banco `0x03` (do CORE, não da sala) efeito `0x12`: `flags = 0x8000`, **não
##     desenha** — é um CONTROLADOR (handler `0x04`), que este nó ainda não emula.
##
## **O `y` das 8 chamas é `0` no dado do opcode — MEDIDO, não escolhido.** Nenhuma delas
## está "na parede na altura do peito": o que punha a chama na parede era a falta de
## PROFUNDIDADE (abaixo). Uma chama de chão que fica atrás de uma quina/batente projeta na
## tela na altura da parede, e sem teste de ordem ela era pintada por cima do cenário. Não
## há Y para corrigir; o que havia para corrigir era a ordem de desenho.
##
## ── TAMANHO NA TELA (provado; a fórmula que faltava em esp_efeitos.md §5) ─────────────
## `esp_draw_all` chama `0x80022ccc` (rota billboard, `flags & 0x200 == 0`) com
## `a2 = size` (`u8[A+3]`) e `a0 = fov = u16[camera + 0x02] >> 7` (`0x80022a00`/`0x80022a0c`):
##     v0         = (size * param_hi * fov) / (z << 4)       `0x80022d30`..`0x80022e50`
##     largura_px = (v0 * escala_x) >> 16                    `0x80022e5c` + `0x80022ecc`
##     x0         = tela_x + ((ox * (v0 * escala_x / size)) >> 16)   `0x80022eb0`
##     x1         = x0 + largura_px                          `0x80022ecc`
## Como o PS1 projeta `tela_x = x * fov / z`, o `fov` e o `z` se cancelam e sobra um
## **tamanho de MUNDO** constante:
##     largura_mundo_ps1 = size * param_hi * escala_x / (256 * 4096)
## Para o fogo do `R10D` isso dá de 768 a 2796 unidades PS1 (0,95 a 3,46 unidades Godot).
## Este nó converte esse tamanho de mundo em pixels **projetando o próprio segmento** com
## a câmera do port (`unproject_position` da âncora e da âncora + largura no eixo X da
## câmera), que é a mesma conta `L * h / z` do GTE, só usando a câmera já calibrada.
##
## ── PROFUNDIDADE: a ordem de desenho (a regra do motor, aplicada ao efeito) ───────────
## No PS1 não há z-buffer: é painter's algorithm na **Ordering Table**, e quem entra com
## chave MENOR é desenhado DEPOIS, ou seja fica NA FRENTE (`0x80029618`, ver
## `port/room/occlusion.gd`, que provou a regra para os priority sprites do cenário).
##   • sprite de máscara do cenário → chave = `depth` CRU do RDT (`0x80048844`);
##   • personagem → `zona_de_prioridade(x,z) * 1024 + min(SZ >> 5, 1023)` (`0x80037d50` +
##     `0x8002b86c`), com `SZ` = Z de câmera em unidades de mundo;
##   • **efeito ESP** → `OT_index = z >> 5` (`0x80022de0`), com o mesmo `z` de câmera.
## Então as três chaves são comparáveis. O que **NÃO está provado** é o BANCO de OT em que
## `esp_draw_all` insere: a base da tabela vem por `sp+0x44` e não foi rastreada até a
## origem (lacuna 5 de `docs/decomp/notes/esp_efeitos.md §9`). DECISÃO DECLARADA: uso a
## MESMA zona de prioridade do ponto do efeito que o motor usa para o personagem — é a
## regra do lugar, não da entidade, e evita o viés de fixar banco 0 (que faria toda chama
## ganhar de um personagem que está numa zona de banco ≥ 1).
##
## Com isso o efeito vive em DUAS camadas, escolhidas por chama e por tick:
##   • `chave >= chave_do_personagem` → camada de TRÁS: filha deste nó, que fica ANTES do
##     `Frame` (o `SubViewportContainer` do 3D) na árvore do `screen.gd` — o 3D desenha por
##     cima, a chama fica atrás da Jill;
##   • `chave < chave_do_personagem` → camada da FRENTE: um `CanvasLayer` próprio
##     (`layer = 1`), que compõe DEPOIS do 3D e depois dos recortes de oclusão.
## E, nas duas camadas, este nó desenha por conta própria os **recortes do cenário que
## estão na frente da chama** (máscara com `chave < chave_da_chama` que cruza o retângulo
## do sprite), lendo os pixels do mesmo background HD que a oclusão usa. Sem isso a chama
## da camada da frente não teria nada que a cobrisse (o `Occlusion` desenha em `layer 0`,
## abaixo do nosso), e a de trás só seria coberta pelas máscaras que passam no teste do
## PERSONAGEM — que é uma pergunta diferente.
##
## ── DECISÕES DO PORT (declaradas, não medidas) ────────────────────────────────────────
## • **2D sobre o quadro, não billboard 3D.** Tentei billboard dentro do SubViewport do
##   mundo e o aditivo fica ERRADO: o viewport tem fundo transparente e o background é um
##   `Sprite2D` ATRÁS dele, então `dst + src` soma contra transparência e o `SubViewportContainer`
##   depois compõe por alpha — os pixels escuros da borda da chama APAGAM o cenário
##   (halo preto, visível em `port/dev/_esp/`). Em 2D sobre o quadro o aditivo soma no
##   cenário de verdade. É também o que o `esp_brilho.gd` faz.
## • `modulate` branco: o PS1 modula `textura * rgb / 128` e o neutro é `0x80`
##   (`0x8001b784` grava `0x80` nos três quando `flags & 4 == 0`), que é fator 1,0.
## • A decisão de camada é por CHAMA INTEIRA (uma chave por sprite), como a oclusão faz
##   por personagem inteiro. O motor decide por primitiva, e a chama é uma só primitiva —
##   aqui a aproximação está no personagem, não no efeito.
## • Instâncias com `alcance = "thread"` (criadas por outra thread do script, depois da
##   entrada) só entram com `incluir_threads = true` — não dá para afirmar que estão
##   ligadas no instante em que a sala abre.
## • A camada da frente é ESCONDIDA enquanto há tela modal aberta (o menu de status/arquivo
##   é irmão em `layer 0` e ficaria abaixo dela). O nó não conhece o menu: procura nos
##   irmãos qualquer nó com a propriedade `aberto` ligada.
##
## ── QUADROS EM HD ─────────────────────────────────────────────────────────────────────
## `tools/esp_decode.py hd` casa cada banco/variante com a página de `hires/effect` do pack
## HD (o de-para é por conteúdo, com o vínculo geométrico `(u,v) × 4`) e recorta os quadros
## em 4× para `assets/ESP/sala/<SALA>/hd/`. Este nó prefere o HD quando existe e cai no SD
## quando não — o tamanho na tela é o mesmo (vem do mundo), só muda a densidade de pixel.
##
## ── API (o engate fica com quem edita o `screen.gd`) ──────────────────────────────────
##     var esp_sala := EspSala.new()
##     add_child(esp_sala)                  # 2D, ANTES do `Frame` (a camada de trás)
##     esp_sala.carregar(room_id)           # em `carregar_sala`, devolve nº de efeitos
##     esp_sala.avancar(cam3d, room, camera_index, occlusion.char_key)   # tick de 30 Hz

const ARQ_JSON := "esp_sala.json"
## `256 * 4096`: o divisor da fórmula de tamanho de mundo provada acima.
const DIV_TAMANHO := 1048576.0
## Só cria efeitos cuja âncora seja a matriz identidade (`0x80098970`), a única cujo `ofs`
## é posição de mundo sem depender de uma entidade viva.
const ANCORA_MUNDO := 0
## Entradas por banco da Ordering Table (`ClearOTagR(ot, 1024)`, `0x80028ff0`).
const OT_BANCO := 1024
## 320×240 (PS1) -> 1280×960, a mesma escala de tela do `occlusion.gd`.
const TELA_ESCALA := 4.0
## Quadro do port em pixels (o `Occlusion` usa a mesma referência para a região-fonte).
const QUADRO_W := 1280.0
const QUADRO_H := 960.0
## Chave de OT "infinitamente longe": nada fica atrás dela.
const CHAVE_LONGE := 0x7FFFFFFF
## Chave do personagem NÃO informada: sem ela nada vai para a camada da frente (é o
## comportamento antigo, "fogo sempre atrás do 3D"), em vez de mandar tudo para a frente.
const CHAVE_INDEFINIDA := -1
## O pack HD é exatamente 4× o SD (medido em todas as categorias; ver `hd_ui_map.json`).
const HD_ESCALA := 4

## Traz também os efeitos criados por threads do script (não provados no instante da
## entrada da sala). Falso = só a corrente `f0 → gosub …` do init.
@export var incluir_threads := false
## Desliga o teste de profundidade (tudo na camada de trás) — para comparação A/B.
@export var profundidade := true

class Efeito:
	extends RefCounted
	## Um slot de ESP vivo: o dado do banco + o estado da animação (`esp_anim_step`).
	var tipo := 0                          ## tipo do banco (byte +1 do opcode)
	var efeito := 0                        ## índice do efeito (byte +2)
	var variante := 0                      ## nibble do byte +3 -> linha de CLUT
	var escala := 0                        ## `param_hi` -> `slot+0x2e`
	var func_id := 0                       ## função do SCD que criou
	var alcance := ""                      ## "init" ou "thread"
	var pos := Vector3i.ZERO               ## posição de mundo em unidades PS1
	var quadros: Array = []                ## [{a,b,px,ticks,ox,oy}] da tabela A
	var texturas: Array[Texture2D] = []    ## uma por quadro (mesma ordem)
	var hd := false                        ## os quadros vieram do pack HD (4×)
	var indice := 0                        ## quadro corrente
	var restante := 0                      ## `slot+0x2b`: ticks que faltam no quadro
	var loop_para := -1                    ## índice na lista onde o `0xff` reinicia
	var fim := ""                          ## "loop" | "morre" | "congela"
	var vivo := true
	var congelado := false
	var abr := 0                           ## modo de semi-transparência efetivo
	var escala_x := 4096
	var escala_y := 4096
	var vel := Vector3i.ZERO               ## `slot+0x10..0x14` (s16)
	var acc := Vector3i.ZERO               ## `slot+0x0c..0x0e` (s8)
	var desloc := Vector3i.ZERO            ## `slot+0x30..0x34`, integrado se `fisica`
	var fisica := false
	var no: Sprite2D = null
	## Estado de PROFUNDIDADE do tick corrente.
	var chave := CHAVE_LONGE               ## chave de OT (banco*1024 + z>>5)
	var na_frente := false                 ## está na camada da frente (na frente da Jill)
	var rect_tela := Rect2()               ## retângulo do sprite em pixels do quadro

	func larg_ps1() -> float:
		## `size * param_hi * escala_x / (256 * 4096)` — em unidades de MUNDO do PS1.
		var px := float(int((quadros[indice] as Dictionary)["px"]))
		return px * float(escala) * float(escala_x) / 1048576.0

	func alt_ps1() -> float:
		var px := float(int((quadros[indice] as Dictionary)["px"]))
		return px * float(escala) * float(escala_y) / 1048576.0


var sala := ""
var efeitos: Array[Efeito] = []
## Contadores do último `carregar` — para o relatório/teste, sem inventar sucesso.
var n_puladas_ancora := 0                  ## âncora != 0 (matriz de entidade)
var n_puladas_controlador := 0             ## efeito que não desenha (`flags` sem bit 13)
var n_puladas_thread := 0
var n_puladas_sem_banco := 0               ## banco do CORE (tipo < 8): não é da sala
var n_puladas_sem_sprite := 0
var n_quadros_hd := 0                      ## quantos quadros carregados vieram do pack HD
var chave_personagem := CHAVE_INDEFINIDA   ## última chave de OT do personagem recebida

var _dados: Dictionary = {}
var _cache_tex: Dictionary = {}
## Camada de TRÁS (antes do 3D): sprites + os recortes que os cobrem.
var _atras: Node2D
var _atras_cobre: Node2D
## Camada da FRENTE (depois do 3D e da oclusão): `CanvasLayer` próprio.
var _frente: CanvasLayer
var _frente_raiz: Node2D
var _frente_cobre: Node2D
var _cobre_atras: Array[Rect2] = []
var _cobre_frente: Array[Rect2] = []
## Cenário do tick: câmera do RDT, máscaras de prioridade e o background (fonte de pixel).
var _cam_dados: RoomData.Camera = null
var _mascaras: Array[Dictionary] = []      ## {rect: Rect2, chave: int}
var _zonas: Array = []
var _fonte: Texture2D = null
var _sala_cena := ""
var _cam_cena := -1


func _init() -> void:
	name = "EspSala"


func _ready() -> void:
	_montar_camadas()


func _montar_camadas() -> void:
	if _atras != null:
		return
	_atras = Node2D.new()
	_atras.name = "Atras"
	add_child(_atras)
	_atras_cobre = Node2D.new()
	_atras_cobre.name = "AtrasCobre"
	_atras_cobre.draw.connect(_desenhar_cobertura.bind(false))
	add_child(_atras_cobre)                ## irmão DEPOIS de `Atras`: cobre os sprites
	_frente = CanvasLayer.new()
	_frente.name = "Frente"
	# `layer = 1`: acima da camada 0 (background, 3D, oclusão, menus) e abaixo do HUD
	# de diagnóstico do `screen.gd`, que usa `layer = 100`.
	_frente.layer = 1
	add_child(_frente)
	_frente_raiz = Node2D.new()
	_frente_raiz.name = "Sprites"
	_frente.add_child(_frente_raiz)
	_frente_cobre = Node2D.new()
	_frente_cobre.name = "Cobre"
	_frente_cobre.draw.connect(_desenhar_cobertura.bind(true))
	_frente.add_child(_frente_cobre)


func _process(_dt: float) -> void:
	if _frente == null:
		return
	# O `CanvasLayer` ignora a transformação do pai: o deslocamento do recorte 16:9 do
	# `screen.gd` (que move o nó em Y) tem de ser repetido aqui.
	_frente.offset = global_position
	# Tela modal aberta (status/arquivo): a camada da frente ficaria POR CIMA dela.
	# (escondo os nós de dentro, não o `CanvasLayer`, para não depender da versão)
	# `visible` deste nó também vale para a camada da frente: um `CanvasLayer` NÃO herda a
	# visibilidade do pai, e sem isto "apagar o fogo" (o A/B dos scripts de `dev/`) deixava
	# as chamas da frente acesas.
	var ver := visible and not _modal_aberto()
	_frente_raiz.visible = ver
	_frente_cobre.visible = ver


func _modal_aberto() -> bool:
	var p := get_parent()
	if p == null:
		return false
	for n in p.get_children():
		if n == self:
			continue
		var v: Variant = n.get("aberto")
		if v is bool and bool(v):
			return true
	return false


func dados_carregados() -> bool:
	if _dados.is_empty():
		var raw: Variant = AssetIO.json(ARQ_JSON)
		if raw is Dictionary and (raw as Dictionary).has("salas"):
			_dados = (raw as Dictionary)["salas"]
	return not _dados.is_empty()


func salas_conhecidas() -> int:
	return _dados.size() if dados_carregados() else 0


func carregar(room_id: String) -> int:
	## Monta os efeitos de uma sala. Devolve quantos foram criados (0 = nada a desenhar,
	## que é o caso honesto de 71 das 156 salas com ESP: têm banco mas nenhum `0x70`).
	limpar()
	_montar_camadas()
	sala = room_id
	if not dados_carregados() or not _dados.has(room_id):
		return 0
	var d: Dictionary = _dados[room_id]
	var bancos: Dictionary = d.get("bancos", {})
	for inst_v: Variant in d.get("instancias", []):
		var inst: Dictionary = inst_v
		if int(inst.get("ancora_tipo", -1)) != ANCORA_MUNDO:
			n_puladas_ancora += 1
			continue
		var alc := str(inst.get("alcance", ""))
		if alc != "init" and not incluir_threads:
			n_puladas_thread += 1
			continue
		var chave := str(int(inst["tipo"]))
		if not bancos.has(chave):
			# tipo < 0x08 = banco do `ETC/CORE00.ESP`, não do RDT da sala. Os sprites do
			# CORE existem (`assets/ESP/t03_*`), mas o efeito pedido no R10D (`0x12`) é um
			# controlador que não desenha — então não há o que mostrar de qualquer forma.
			n_puladas_sem_banco += 1
			continue
		var e := _montar(inst, bancos[chave])
		if e != null:
			efeitos.append(e)
	return efeitos.size()


func _montar(inst: Dictionary, banco: Dictionary) -> Efeito:
	var efs: Dictionary = banco.get("efeitos", {})
	var ch := str(int(inst["efeito"]))
	if not efs.has(ch):
		n_puladas_sem_banco += 1
		return null
	var slots: Array = (efs[ch] as Dictionary).get("slots", [])
	if slots.is_empty():
		n_puladas_sem_banco += 1
		return null
	# `n_slots > 1` cria vários slots de ESP encadeados (`0x8001b7c8`); aqui só o primeiro,
	# porque nenhum efeito de sala usado no R10D tem mais de um.
	var fr: Dictionary = slots[0]
	if not bool(fr.get("desenha", false)):
		n_puladas_controlador += 1
		return null

	var e := Efeito.new()
	e.tipo = int(inst["tipo"])
	e.efeito = int(inst["efeito"])
	e.variante = int(inst["variante"])
	e.escala = int(inst["escala"])
	e.func_id = int(inst.get("func", -1))
	e.alcance = str(inst.get("alcance", ""))
	var p: Array = inst["pos"]
	e.pos = Vector3i(int(p[0]), int(p[1]), int(p[2]))
	e.abr = int(fr.get("abr", 0))
	e.escala_x = int(fr.get("escala_x", 4096))
	e.escala_y = int(fr.get("escala_y", 4096))
	e.fisica = bool(fr.get("fisica", false))
	e.vel = _s16v(fr.get("vel", [0, 0, 0]))
	e.acc = _vec(fr.get("acc", [0, 0, 0]))

	var anim: Dictionary = fr.get("anim", {})
	e.quadros = anim.get("quadros", [])
	e.fim = str(anim.get("fim", "?"))
	if e.quadros.is_empty():
		n_puladas_sem_sprite += 1
		return null
	if e.fim == "loop":
		# `ctl_dur == 0xff` volta para a ENTRADA da tabela A dada em `b_index`; aqui a lista
		# começa em `a_start`, então converto para índice de lista.
		var destino := int(anim.get("loop_para", -1))
		var base := int((e.quadros[0] as Dictionary)["a"])
		e.loop_para = clampi(destino - base, 0, e.quadros.size() - 1)

	for q_v: Variant in e.quadros:
		var q: Dictionary = q_v
		var tex := _textura(e.tipo, int(q["a"]), int(q["b"]), e.variante, int(q["px"]))
		if tex == null:
			n_puladas_sem_sprite += 1
			return null
		if tex.get_width() >= int(q["px"]) * HD_ESCALA:
			e.hd = true
			n_quadros_hd += 1
		e.texturas.append(tex)

	e.no = Sprite2D.new()
	e.no.name = "Esp_t%02x_e%02x_f%d" % [e.tipo, e.efeito, e.func_id]
	# `centered = false`: o PS1 põe o CANTO em `tela + ofs*tam/size` e o quad tem `tam` de
	# lado (`0x80022eb0`/`0x80022ecc`). Com o canto explícito o pivô é o do dado, não o meio.
	e.no.centered = false
	# NEAREST no SD (é o pixel do PS1); LINEAR no HD, que já é arte redesenhada em 4× e
	# quase sempre entra na tela REDUZIDO (a chama de 192 px ocupa ~120 px no quadro).
	e.no.texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR if e.hd
		else CanvasItem.TEXTURE_FILTER_NEAREST)
	e.no.visible = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = _blend(e.abr)
	e.no.material = mat
	e.no.modulate = _cor(e.abr)
	_atras.add_child(e.no)

	e.indice = 0
	e.restante = int((e.quadros[0] as Dictionary)["ticks"])
	e.no.texture = e.texturas[0]
	return e


func avancar(cam: Camera3D, sala_dados: RoomData = null, cam_idx := -1,
		chave_do_personagem := CHAVE_INDEFINIDA) -> void:
	## Um tick de 30 Hz: `esp_anim_step` (`0x8001c168`) + a integração de `0x8001bc80`,
	## e depois reprojeta cada sprite com a câmera corrente.
	##
	## `sala_dados`/`cam_idx`/`chave_do_personagem` são o que liga a PROFUNDIDADE: sem eles
	## o nó ainda anda e desenha, mas tudo fica na camada de trás (o comportamento antigo).
	_atualizar_cena(sala_dados, cam_idx)
	chave_personagem = chave_do_personagem
	for e: Efeito in efeitos:
		if not e.vivo:
			continue
		if e.fisica:
			# `vel += acc` e o deslocamento acumula `vel` — some na posição de desenho.
			# No fogo do R10D `vel` e `acc` são ZERO, então isto não move nada lá; está
			# aqui porque outros efeitos de sala (o banco 0x03 do CORE) usam.
			e.vel += e.acc
			e.desloc += e.vel
		if not e.congelado:
			e.restante -= 1
			if e.restante <= 0:
				_proximo(e)
		_desenhar(e, cam)
	_atualizar_cobertura()


func reprojetar(cam: Camera3D) -> void:
	## Reposiciona sem avançar o tempo (para quando só a câmera trocou).
	for e: Efeito in efeitos:
		_desenhar(e, cam)
	_atualizar_cobertura()


func _proximo(e: Efeito) -> void:
	var prox := e.indice + 1
	if prox < e.quadros.size():
		e.indice = prox
		e.restante = int((e.quadros[prox] as Dictionary)["ticks"])
		return
	match e.fim:
		"loop":
			e.indice = e.loop_para
			e.restante = int((e.quadros[e.indice] as Dictionary)["ticks"])
		"congela":
			e.congelado = true                 ## `0xfe`: para de animar no quadro anterior
			e.restante = 1
		_:
			e.vivo = false                     ## `0x00`: MATA o efeito
			if e.no != null:
				e.no.visible = false


func _desenhar(e: Efeito, cam: Camera3D) -> void:
	if e.no == null or cam == null:
		return
	if not e.vivo:
		e.no.visible = false
		return
	var m := e.pos + e.desloc
	var ancora := Coords.to_godot_i(m.x, m.y, m.z)
	if cam.is_position_behind(ancora):
		e.no.visible = false
		return
	var p0 := cam.unproject_position(ancora)
	# Tamanho em PIXELS do quadro: projeta o próprio segmento de mundo nos eixos da câmera
	# (o quad do PS1 é de TELA, não orientado pela matriz — `flags & 0x200 == 0`).
	var b := cam.global_transform.basis
	var lg := Coords.len_to_godot(e.larg_ps1())
	var ag := Coords.len_to_godot(e.alt_ps1())
	var w_px := p0.distance_to(cam.unproject_position(ancora + b.x * lg))
	var h_px := p0.distance_to(cam.unproject_position(ancora + b.y * ag))
	if w_px < 0.5 or h_px < 0.5:
		e.no.visible = false
		return
	var q: Dictionary = e.quadros[e.indice]
	var px := float(int(q["px"]))
	e.no.texture = e.texturas[e.indice]
	# O denominador é a largura REAL da textura (48 no SD, 192 no HD): o tamanho na tela
	# vem do mundo e não muda com a densidade de pixel do asset.
	var tw := float(maxi(1, e.no.texture.get_width()))
	e.no.scale = Vector2(w_px / tw, h_px / tw)
	# canto = tela + ofs * tamanho / size (o `ofs` da tabela B é em texels SD, com sinal)
	e.no.position = p0 + Vector2(
		float(int(q["ox"])) * w_px / px,
		float(int(q["oy"])) * h_px / px)
	e.no.visible = true
	e.rect_tela = Rect2(e.no.position, Vector2(w_px, h_px))
	e.chave = chave_ot(m, cam)
	_por_na_camada(e, profundidade and chave_personagem >= 0 and e.chave < chave_personagem)


# ───────────────────────────── profundidade (ordering table) ─────────────────────────────


func _por_na_camada(e: Efeito, na_frente: bool) -> void:
	e.na_frente = na_frente
	var alvo: Node = _frente_raiz if na_frente else _atras
	if alvo == null or e.no == null or e.no.get_parent() == alvo:
		return
	var pos := e.no.position
	if e.no.get_parent() != null:
		e.no.get_parent().remove_child(e.no)
	alvo.add_child(e.no)
	e.no.position = pos                    ## reparent não preserva o espaço da camada


func chave_ot(ps1: Vector3i, cam: Camera3D) -> int:
	## Chave de Ordering Table do efeito: `zona(x,z) * 1024 + min(z_camera >> 5, 1023)`.
	## Pública porque é o que o teste compara com a chave do personagem — a decisão de
	## camada é uma comparação de inteiros, e dá para verificar sem renderizar nada.
	## O `z >> 5` é o do `esp_draw_all` (`0x80022de0`); o `z` é o Z de CÂMERA em unidades
	## de mundo, o mesmo `SZ` que o personagem usa (`0x8002b86c`).
	var sz := 0
	if _cam_dados != null:
		var eixo := Vector3(float(_cam_dados.to_ps1.x - _cam_dados.from_ps1.x),
			float(_cam_dados.to_ps1.y - _cam_dados.from_ps1.y),
			float(_cam_dados.to_ps1.z - _cam_dados.from_ps1.z))
		if eixo.length_squared() > 0.0:
			eixo = eixo.normalized()
			var v := Vector3(float(ps1.x - _cam_dados.from_ps1.x),
				float(ps1.y - _cam_dados.from_ps1.y), float(ps1.z - _cam_dados.from_ps1.z))
			sz = clampi(int(v.dot(eixo)), 0, 32767)
	elif cam != null:
		# Sem o dado do RDT: o mesmo Z, medido na câmera do port (que foi montada a partir
		# do `from`/`to` do RDT, então é o mesmo eixo).
		var local := cam.to_local(Coords.to_godot_i(ps1.x, ps1.y, ps1.z))
		sz = clampi(int(-local.z * Coords.WORLD_SCALE), 0, 32767)
	return _banco_do_ponto(ps1.x, ps1.z) * OT_BANCO + mini(sz >> 5, OT_BANCO - 1)


func _banco_do_ponto(x: int, z: int) -> int:
	## `0x80037d50`: primeira zona de prioridade (na ordem do arquivo) que contém o ponto
	## decide o banco; `flags` bit 1 = ignorar; sem seção ou sem zona → banco 0.
	## Mesma regra do `occlusion.gd` — repetida aqui porque aquele arquivo é de outro
	## território; se um dia virar API pública, esta cópia sai.
	for zona: Dictionary in _zonas:
		if (int(zona.get("flags", 0)) & 0x02) != 0:
			continue
		if zona.has("rect"):
			var r: Array = zona["rect"]
			var dx := x - int(r[0])
			var dz := z - int(r[1])
			if dx >= 0 and dx <= int(r[2]) and dz >= 0 and dz <= int(r[3]):
				return int(zona.get("bank", 0))
		elif zona.has("quad"):
			var q: Array[Vector2i] = []
			for pt: Array in zona["quad"]:
				q.append(Vector2i(int(pt[0]), int(pt[1])))
			if CameraRVD.point_in_quad(q, x, z):
				return int(zona.get("bank", 0))
	return 0


func _atualizar_cena(sala_dados: RoomData, cam_idx: int) -> void:
	## Cacheia máscaras/zonas/background da câmera corrente. Só refaz quando a câmera muda
	## — era isto que fazia a varredura do teste demorar: recarregar textura por chamada.
	if sala_dados == null or cam_idx < 0:
		if _sala_cena != "":
			_sala_cena = ""
			_cam_cena = -1
			_cam_dados = null
			_mascaras.clear()
			_zonas.clear()
			_fonte = null
		return
	if sala_dados.room_id == _sala_cena and cam_idx == _cam_cena:
		return
	_sala_cena = sala_dados.room_id
	_cam_cena = cam_idx
	_cam_dados = sala_dados.camera(cam_idx)
	_zonas = sala_dados.priority_zones_da_camera(cam_idx)
	_mascaras.clear()
	_fonte = null
	if _cam_dados == null:
		return
	_fonte = CameraRID.background(sala_dados.room_id, cam_idx)
	for g: Dictionary in _cam_dados.mask_groups:
		for bl: Dictionary in (g.get("blocks", []) as Array):
			var w := float(bl.get("w", 0))
			var h := float(bl.get("h", 0))
			if w <= 0.0 or h <= 0.0:
				continue
			_mascaras.append({
				"rect": Rect2(float(bl.get("dx", 0)) * TELA_ESCALA,
					float(bl.get("dy", 0)) * TELA_ESCALA, w * TELA_ESCALA, h * TELA_ESCALA),
				# chave de OT = o `depth` CRU do RDT (o JSON guarda `z = depth*16`)
				"chave": int(bl.get("z", 0)) >> 4,
			})


func _atualizar_cobertura() -> void:
	## Recortes do cenário que ficam NA FRENTE de alguma chama (chave menor). São os pixels
	## do próprio background HD, como no `occlusion.gd` — a diferença é a pergunta: lá é
	## "está na frente do PERSONAGEM", aqui é "está na frente DESTA chama".
	var antes_a := _cobre_atras.size()
	var antes_f := _cobre_frente.size()
	_cobre_atras.clear()
	_cobre_frente.clear()
	if profundidade and _fonte != null:
		for e: Efeito in efeitos:
			if not e.vivo or e.no == null or not e.no.visible:
				continue
			for m: Dictionary in _mascaras:
				if int(m["chave"]) >= e.chave:
					continue
				var r: Rect2 = m["rect"]
				if not r.intersects(e.rect_tela):
					continue
				if e.na_frente:
					if not _cobre_frente.has(r):
						_cobre_frente.append(r)
				elif not _cobre_atras.has(r):
					_cobre_atras.append(r)
	if _atras_cobre != null and (antes_a > 0 or not _cobre_atras.is_empty()):
		_atras_cobre.queue_redraw()
	if _frente_cobre != null and (antes_f > 0 or not _cobre_frente.is_empty()):
		_frente_cobre.queue_redraw()


func _desenhar_cobertura(na_frente: bool) -> void:
	if _fonte == null:
		return
	var lista := _cobre_frente if na_frente else _cobre_atras
	if lista.is_empty():
		return
	var no := _frente_cobre if na_frente else _atras_cobre
	# O background pode ser HD (1280×960) ou PS1 (320×240): a região-fonte é o mesmo
	# retângulo em proporção, então basta escalar pelo tamanho real da textura.
	var k := Vector2(float(_fonte.get_width()) / QUADRO_W, float(_fonte.get_height()) / QUADRO_H)
	for r: Rect2 in lista:
		no.draw_texture_rect_region(_fonte, r, Rect2(r.position * k, r.size * k))


func recortes_de_cobertura() -> Vector2i:
	## (na camada de trás, na camada da frente) — diagnóstico/teste.
	return Vector2i(_cobre_atras.size(), _cobre_frente.size())


func na_frente() -> int:
	var n := 0
	for e: Efeito in efeitos:
		if e.na_frente:
			n += 1
	return n


func limpar() -> void:
	for e: Efeito in efeitos:
		if e.no != null:
			e.no.queue_free()
	efeitos.clear()
	_cobre_atras.clear()
	_cobre_frente.clear()
	n_puladas_ancora = 0
	n_puladas_controlador = 0
	n_puladas_thread = 0
	n_puladas_sem_banco = 0
	n_puladas_sem_sprite = 0
	n_quadros_hd = 0


func vivos() -> int:
	var n := 0
	for e: Efeito in efeitos:
		if e.vivo:
			n += 1
	return n


func resumo() -> String:
	return ("%s: %d efeito(s) de sala · %d vivo(s) · %d na frente · %d quadro(s) HD · "
		+ "puladas: âncora=%d controlador=%d thread=%d banco-do-core=%d sem-sprite=%d") % [
		sala, efeitos.size(), vivos(), na_frente(), n_quadros_hd, n_puladas_ancora,
		n_puladas_controlador, n_puladas_thread, n_puladas_sem_banco, n_puladas_sem_sprite]


func _textura(tipo: int, a: int, b: int, variante: int, px: int) -> Texture2D:
	## Quadro do efeito: o HD do pack quando existe (`hd/`, lado 4×), senão o SD do PS1.
	var hd := "ESP/sala/%s/hd/t%02x_A%02d_B%02d_v%d_%dx%d.png" % [
		sala, tipo, a, b, variante, px * HD_ESCALA, px * HD_ESCALA]
	var sd := "ESP/sala/%s/t%02x_A%02d_B%02d_v%d_%dx%d.png" % [
		sala, tipo, a, b, variante, px, px]
	for rel in [hd, sd]:
		if _cache_tex.has(rel):
			return _cache_tex[rel]
		if not AssetIO.exists(rel):
			continue
		var tex := AssetIO.texture(rel)
		if tex != null:
			_cache_tex[rel] = tex
			return tex
	return null


static func _blend(abr: int) -> int:
	## `abr` são os bits 5-6 do `tpage` (`tpage_banco | tpage_or`).
	match abr:
		1: return CanvasItemMaterial.BLEND_MODE_ADD          ## B + F
		2: return CanvasItemMaterial.BLEND_MODE_SUB          ## B - F
		3: return CanvasItemMaterial.BLEND_MODE_ADD          ## B + F/4 (o /4 vai no modulate)
		_: return CanvasItemMaterial.BLEND_MODE_MIX          ## B/2 + F/2


static func _cor(abr: int) -> Color:
	## Neutro = branco (o PS1 modula por `0x80/128 = 1,0`). `abr 0` e `abr 3` levam o fator
	## da própria equação de blend para o alpha, que é o que o Godot tem à mão.
	match abr:
		0: return Color(1.0, 1.0, 1.0, 0.5)
		3: return Color(1.0, 1.0, 1.0, 0.25)
		_: return Color(1.0, 1.0, 1.0, 1.0)


static func _vec(a: Variant) -> Vector3i:
	var l: Array = a
	return Vector3i(int(l[0]), int(l[1]), int(l[2])) if l.size() >= 3 else Vector3i.ZERO


static func _s16v(a: Variant) -> Vector3i:
	## `vel` vem do frame record como u16; no motor é s16 (`0x8001bc80` soma com `lh`).
	var v := _vec(a)
	return Vector3i(
		v.x - 0x10000 if v.x >= 0x8000 else v.x,
		v.y - 0x10000 if v.y >= 0x8000 else v.y,
		v.z - 0x10000 if v.z >= 0x8000 else v.z)
