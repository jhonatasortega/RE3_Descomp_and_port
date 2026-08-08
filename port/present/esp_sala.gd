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
## ── DECISÕES DO PORT (declaradas, não medidas) ────────────────────────────────────────
## • **2D sobre o quadro, não billboard 3D.** Tentei billboard dentro do SubViewport do
##   mundo e o aditivo fica ERRADO: o viewport tem fundo transparente e o background é um
##   `Sprite2D` ATRÁS dele, então `dst + src` soma contra transparência e o `SubViewportContainer`
##   depois compõe por alpha — os pixels escuros da borda da chama APAGAM o cenário
##   (halo preto, visível em `port/dev/_esp/`). Em 2D sobre o quadro o aditivo soma no
##   cenário de verdade. É também o que o `esp_brilho.gd` faz.
## • Sem teste de profundidade: no PS1 não há z-buffer, a primitiva entra na Ordering Table
##   em `z >> 5` (`0x80022de0`). A ordenação fina contra móveis é do item de oclusão.
## • `modulate` branco: o PS1 modula `textura * rgb / 128` e o neutro é `0x80`
##   (`0x8001b784` grava `0x80` nos três quando `flags & 4 == 0`), que é fator 1,0.
## • Instâncias com `alcance = "thread"` (criadas por outra thread do script, depois da
##   entrada) só entram com `incluir_threads = true` — não dá para afirmar que estão
##   ligadas no instante em que a sala abre.
##
## ── API (o engate fica com quem edita o `screen.gd`) ──────────────────────────────────
##     var esp_sala := EspSala.new()
##     add_child(esp_sala)                  # 2D, na mesma altura do `esp` (EspBrilho)
##     esp_sala.carregar(room_id)           # em `carregar_sala`, devolve nº de efeitos
##     esp_sala.avancar(cam3d)              # no tick de 30 Hz, junto de `esp.avancar(cam3d)`

const ARQ_JSON := "esp_sala.json"
## `256 * 4096`: o divisor da fórmula de tamanho de mundo provada acima.
const DIV_TAMANHO := 1048576.0
## Só cria efeitos cuja âncora seja a matriz identidade (`0x80098970`), a única cujo `ofs`
## é posição de mundo sem depender de uma entidade viva.
const ANCORA_MUNDO := 0

## Traz também os efeitos criados por threads do script (não provados no instante da
## entrada da sala). Falso = só a corrente `f0 → gosub …` do init.
@export var incluir_threads := false

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
var _dados: Dictionary = {}
var _cache_tex: Dictionary = {}


func _init() -> void:
	name = "EspSala"


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
		e.texturas.append(tex)

	e.no = Sprite2D.new()
	e.no.name = "Esp_t%02x_e%02x_f%d" % [e.tipo, e.efeito, e.func_id]
	# `centered = false`: o PS1 põe o CANTO em `tela + ofs*tam/size` e o quad tem `tam` de
	# lado (`0x80022eb0`/`0x80022ecc`). Com o canto explícito o pivô é o do dado, não o meio.
	e.no.centered = false
	e.no.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	e.no.visible = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = _blend(e.abr)
	e.no.material = mat
	e.no.modulate = _cor(e.abr)
	add_child(e.no)

	e.indice = 0
	e.restante = int((e.quadros[0] as Dictionary)["ticks"])
	e.no.texture = e.texturas[0]
	return e


func avancar(cam: Camera3D) -> void:
	## Um tick de 30 Hz: `esp_anim_step` (`0x8001c168`) + a integração de `0x8001bc80`,
	## e depois reprojeta cada sprite com a câmera corrente.
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


func reprojetar(cam: Camera3D) -> void:
	## Reposiciona sem avançar o tempo (para quando só a câmera trocou).
	for e: Efeito in efeitos:
		_desenhar(e, cam)


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
	e.no.scale = Vector2(w_px / px, h_px / px)
	# canto = tela + ofs * tamanho / size (o `ofs` da tabela B é em texels, com sinal)
	e.no.position = p0 + Vector2(
		float(int(q["ox"])) * w_px / px,
		float(int(q["oy"])) * h_px / px)
	e.no.visible = true


func limpar() -> void:
	for e: Efeito in efeitos:
		if e.no != null:
			e.no.queue_free()
	efeitos.clear()
	n_puladas_ancora = 0
	n_puladas_controlador = 0
	n_puladas_thread = 0
	n_puladas_sem_banco = 0
	n_puladas_sem_sprite = 0


func vivos() -> int:
	var n := 0
	for e: Efeito in efeitos:
		if e.vivo:
			n += 1
	return n


func resumo() -> String:
	return ("%s: %d efeito(s) de sala · %d vivo(s) · puladas: âncora=%d controlador=%d "
		+ "thread=%d banco-do-core=%d sem-sprite=%d") % [
		sala, efeitos.size(), vivos(), n_puladas_ancora, n_puladas_controlador,
		n_puladas_thread, n_puladas_sem_banco, n_puladas_sem_sprite]


func _textura(tipo: int, a: int, b: int, variante: int, px: int) -> Texture2D:
	var rel := "ESP/sala/%s/t%02x_A%02d_B%02d_v%d_%dx%d.png" % [
		sala, tipo, a, b, variante, px, px]
	if _cache_tex.has(rel):
		return _cache_tex[rel]
	var tex := AssetIO.texture(rel)
	if tex != null:
		_cache_tex[rel] = tex
	return tex


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
