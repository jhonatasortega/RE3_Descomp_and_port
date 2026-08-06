class_name Collision
extends RefCounted
## Colisão do RE3 como o motor faz: **segmentos**, não caixas cheias (P3-10).
##
## O port começou tratando cada registro de 16 B do bloco `offset_table[6]` como um retângulo
## SÓLIDO e testando o ponto dentro dele. Isso está errado, e o erro é medível: na R101,
## 0% da sala fica caminhável (os 75 registros cobrem tudo). Foi a causa do relato
## "não consigo nem andar pelo mapa direito".
##
## ── O que o EXE faz (`0x8004e830`, provado por desassembly) ──
## Cada registro descreve uma **lista de segmentos de reta**. O teste é: o SEGMENTO DE
## MOVIMENTO (origem → destino) cruza algum segmento do collider? A interseção é feita na
## GTE por `0x8004ef74`: dois NCLIP (op `0x06`, produto vetorial) para ver se A e B ficam em
## lados opostos da reta CD, e outros dois para o inverso — o teste clássico de "straddle".
##
## Consequência de projeto: **estar dentro de um retângulo não bloqueia; atravessar a borda
## bloqueia**. É isso que faz salas com colliders enormes serem caminháveis.
##
## Tabela de formas: `0x8009e088`, 16 entradas, índice = `bits & 0x0f`. Ver
## docs/formatos/ARD.md §3.6 para a derivação de cada forma.
##
## Ordem dos filtros (idêntica à do laço do EXE):
##   1. `bits & mascara` — o movimento do player passa `0x40`
##   2. quadrante: `mask & codigo` (broadphase de 2 centros, `0x8004d6b8`)
##   3. altura: `topo > maxY` ou `base_y < minY` → pula
##   4. AABB do segmento contra a caixa envolvente (broadphase do próprio EXE)
##   5. forma (narrowphase)

const MASCARA_PLAYER := 0x40          ## `a2` nos chamadores do PREDICADO (`0x8004e830`)
const MASCARA_OUTRO := 0x2000         ## `a2` em `0x80021fd8`
## Máscara do RESOLVER (`0x8004af04`): o chamador `0x8003543c` passa `a2 = 0x4000`, aplicado
## ao campo `+0x08` (`0x8004b034/38`). NÃO é o 0x40 do predicado — medido: 4767/5289 registros
## têm o bit 0x4000 (vs 4707 com o 0x40; 60 registros diferem).
const MASCARA_RESOLVER := 0x4000
const ALTURA_POR_NIVEL := 1800        ## `lb +0x0c` × -1800 (sll/subu/sll/addu/sll no EXE)
const BIT_ROTACIONADO := 0x1000       ## `+0x0a & 0x1000`: collider girado 45° (437 registros)
## Cosseno/seno de 45° em ponto-fixo, EXATAMENTE como o EXE: `((v*3)*15*4 + v) >> 8` = v*181/256.
## (181/256 = 0,70703; 1/√2 = 0,70711 — o motor usa a aproximação, e o port copia.)
const ROT_NUM := 181
const ROT_SHIFT := 8


static func girar_para_rect(x: int, z: int, r: Rect) -> Vector2i:
	## `0x8004e970`: leva um ponto do MUNDO para o referencial do collider girado 45°.
	##     dx = x - f0 ; dz = z - f1
	##     x' = f0 + ((dx - dz) * 181 >> 8)
	##     z' = f1 + ((dx + dz) * 181 >> 8)
	var dx := x - r.f0
	var dz := z - r.f1
	return Vector2i(r.f0 + ((dx - dz) * ROT_NUM >> ROT_SHIFT),
		r.f1 + ((dx + dz) * ROT_NUM >> ROT_SHIFT))


static func girar_para_mundo(x: int, z: int, r: Rect) -> Vector2i:
	## Inversa da de cima. Serve para DESENHAR o collider girado onde ele realmente bloqueia —
	## sem isso o wireframe mostra o retângulo cru, num lugar diferente do que barra.
	##     dx = (a + b) * 181 >> 8   ·   dz = (b - a) * 181 >> 8
	var a := x - r.f0
	var b := z - r.f1
	return Vector2i(r.f0 + ((a + b) * ROT_NUM >> ROT_SHIFT),
		r.f1 + ((b - a) * ROT_NUM >> ROT_SHIFT))


class Rect:
	extends RefCounted
	## Um registro de 16 B do bloco de colisão, com os campos CRUS.
	var f0 := 0
	var f1 := 0
	var f2 := 0
	var f3 := 0
	var forma := 1
	var canto := 0                    ## forma 6: `bits & 0x30` >> 4
	var bits := 0
	var mask := 0
	var base_y := 0                   ## -1800 × `+0x0c`
	var topo := 0                     ## `+0x0e`
	var nivel := 0
	var wall := false
	var bits_rdt := 0                 ## valor de fábrica de `bits` (o que está no RDT)
	# caixa envolvente (broadphase e desenho)
	var x0 := 0
	var z0 := 0
	var x1 := 0
	var z1 := 0

	func envolve() -> void:
		x0 = mini(f0, f2); x1 = maxi(f0, f2)
		z0 = mini(f1, f3); z1 = maxi(f1, f3)

	func segmentos() -> Array:
		## Os segmentos desta forma, em unidades PS1. Cada item é [ax, az, bx, bz].
		## O EXE trabalha com as coordenadas divididas por 2 (para caber na GTE); aqui não
		## dividimos — os inteiros do Godot são de 64 bits e o sinal do produto vetorial é o
		## mesmo. Os deslocamentos internos das formas 2/3 seguem a aritmética do EXE, que
		## calcula o offset em unidades INTEIRAS e o aplica ao espaço dividido por 2 (ou
		## seja, vale metade da largura/profundidade em unidades cheias).
		match forma:
			8, 11, 12:
				return []                                  ## `return 0` no EXE
			5:
				return [[f0, f1, f2, f3]]
			1, 7:
				return [[f0, f3, f2, f1], [f0, f1, f2, f3]]
			4:
				var xm := f0 + (f2 - f0) / 2
				var zm := f1 + (f3 - f1) / 2
				return [[xm, f1, xm, f3], [f0, zm, f2, zm]]
			2:
				var zm2 := (f1 + f3) / 2
				var q2 := (f3 - f1) / 2                    ## desloca em X pela profundidade
				return [[f0, zm2, f2, zm2],
					[f0 + q2, f1, f2 - q2, f3],
					[f0 + q2, f3, f2 - q2, f1]]
			3:
				var xm3 := (f0 + f2) / 2
				var q3 := (f2 - f0) / 2                    ## desloca em Z pela largura
				return [[xm3, f1, xm3, f3],
					[f0, f1 + q3, f2, f3 - q3],
					[f2, f1 + q3, f0, f3 - q3]]
			6:
				# "L" de duas arestas; o canto vem de `bits & 0x30`. A 3ª diagonal do EXE
				# devolve 2 e o chamador do player descarta o 2 — por isso não entra aqui.
				var zl := f3 if (bits & 0x20) == 0 else f1
				var xl := f0 if (bits & 0x10) != 0 else f2
				return [[f0, zl, f2, zl], [xl, f1, xl, f3]]
			9, 10:
				var segs: Array = []
				if (mask & 0x100) != 0:
					segs.append([f0, f1, f0, f3])          ## aresta x0
				if (mask & 0x200) != 0:
					segs.append([f2, f3, f0, f3])          ## aresta z1
				if (mask & 0x400) != 0:
					segs.append([f2, f3, f2, f1])          ## aresta x1
				if (mask & 0x800) != 0:
					segs.append([f0, f1, f2, f1])          ## aresta z0
				return segs
			0:
				return []                                  ## círculo: ver `_circulo_bloqueia`
		return [[f0, f3, f2, f1], [f0, f1, f2, f3]]        ## desconhecida: trata como retângulo

	func raio() -> int:
		## Forma 0: raio = metade da largura (o EXE calcula `(f2-f0)/4` no espaço /2).
		return absi(f2 - f0) / 2

	func centro() -> Vector2i:
		return Vector2i(f0 + (f2 - f0) / 2, f1 + (f3 - f1) / 2)


var rects: Array[Rect] = []
var centro1 := Vector2i.ZERO
var centro2 := Vector2i.ZERO
var piso_padrao := 0                  ## cabeçalho SCA +0x0E: Y de piso fallback da sala


## Bits de PISO em `+0x08` (tabela `0x8009cbc8`): o passe do player usa o do type 0.
const MASCARA_PISO := 0x8000


func floor_height(x: int, z: int, y_atual: int) -> int:
	## `0x8004d720` — a altura do chão sob (x,z). **O Y do personagem não é integrado: é
	## rederivado daqui todo frame** (laço `0x80033b88` grava direto em `entity+0x38`).
	## Sem isto, descer escada deixava a Jill FLUTUANDO no Y do andar de cima (relato).
	##
	## Regras (variante do personagem, `a3 = 9` → tabela `0x8009e054`):
	##   • parte do PISO PADRÃO da sala (cabeçalho `+0x0E`);
	##   • só registros com bit de piso (`+0x08 & 0x8000`) e base NO PÉ OU ABAIXO
	##     (`-1800*base >= y_atual` numericamente — Y cresce para baixo);
	##   • forma 1 = patamar plano em `topo` (excluindo os com arestas, `mask & 0x0F00`);
	##     formas 9/10 = RAMPA LINEAR de `-1800*base` a `topo+1800` no sentido de
	##     `bits & 0x30`; forma 12 = cone radial; as demais não dão piso ao personagem;
	##   • vence o MENOR Y (o chão mais alto que ainda está sob os pés).
	var best := piso_padrao
	for r in rects:
		if (r.bits & MASCARA_PISO) == 0:                        # `0x8004d834`
			continue
		if r.base_y < y_atual:                                  # `0x8004d864`: base acima do pé
			continue
		var q := Vector2i(x, z)
		if (r.mask & BIT_ROTACIONADO) != 0:                     # `0x8004d894`
			q = girar_para_rect(x, z, r)
		if q.x - r.f0 < 0 or q.x - r.f0 > r.f2 - r.f0:          # AABB unsigned `0x8004d968`
			continue
		if q.y - r.f1 < 0 or q.y - r.f1 > r.f3 - r.f1:
			continue
		var h := 0x7FFFFFFF
		match r.forma:
			1:
				if (r.mask & 0x0F00) != 0:                      # parede com arestas: não é piso
					continue
				h = r.topo
			9, 10:
				h = _altura_rampa(r, q)
			12:
				h = _altura_cone(r, q)
			_:
				continue
		if h < best:
			best = h
	return best


func _altura_rampa(r: Rect, q: Vector2i) -> int:
	## `0x8004e10c`: rampa linear entre `-1800*base` (ponta baixa) e `topo+1800` (ponta alta),
	## no sentido de `bits & 0x30`; resultado clampado entre as pontas.
	var y_base := r.base_y
	var y_topo := r.topo + ALTURA_POR_NIVEL
	var span := y_topo - y_base
	var h := y_base
	match (r.bits >> 4) & 3:
		0:
			if r.f2 != r.f0:
				h = y_base + (q.x - r.f0) * span / (r.f2 - r.f0)
		1:
			if r.f2 != r.f0:
				h = y_base + (r.f2 - q.x) * span / (r.f2 - r.f0)
		2:
			if r.f3 != r.f1:
				h = y_base + (q.y - r.f1) * span / (r.f3 - r.f1)
		3:
			if r.f3 != r.f1:
				h = y_base + (r.f3 - q.y) * span / (r.f3 - r.f1)
	h = maxi(h, y_topo)                                         # clamp `0x8004e208/18`
	return mini(h, y_base)


func _altura_cone(r: Rect, q: Vector2i) -> int:
	## `0x8004e750`: cone radial — centro no `topo`, borda em `-1800*base`.
	var raio_c := (r.f2 - r.f0) / 2
	if raio_c <= 0:
		return piso_padrao
	var c := Vector2i(r.f0 + raio_c, r.f1 + raio_c)
	var d := int(sqrt(float((q.x - c.x) * (q.x - c.x) + (q.y - c.y) * (q.y - c.y))))
	if raio_c - d <= 0:
		return piso_padrao
	var alt := (r.topo & 0xFFFF) + ALTURA_POR_NIVEL * (r.base_y / -ALTURA_POR_NIVEL)
	alt = alt - 0x10000 if alt >= 0x8000 else alt               # sext16, como o EXE
	return r.topo - alt * d / raio_c


func reset_estado() -> void:
	## Volta os bits de estado ao valor do RDT. O PS1 recarrega o RDT inteiro do CD a cada
	## porta, então o efeito do opcode `0x6e` NÃO persiste entre visitas — quem persiste são as
	## FLAGS que o script consulta antes de chamar o 0x6e. Sem isto, o cache de salas do port
	## "lembraria" um portão aberto que o script decidiria fechar.
	for r in rects:
		r.bits = r.bits_rdt


static func from_json(col: Dictionary) -> Collision:
	var c := Collision.new()
	var ctr: Array = col.get("center", [0, 0])
	if ctr.size() >= 2:
		c.centro1 = Vector2i(int(ctr[0]), int(ctr[1]))
	var ctr2: Array = col.get("center2", ctr)
	if ctr2.size() >= 2:
		c.centro2 = Vector2i(int(ctr2[0]), int(ctr2[1]))
	c.piso_padrao = int(col.get("piso_padrao", 0))
	for rc: Dictionary in col.get("rects", []):
		var r := Rect.new()
		var cru: Array = rc.get("raw", [])
		if cru.size() >= 4:
			r.f0 = int(cru[0]); r.f1 = int(cru[1]); r.f2 = int(cru[2]); r.f3 = int(cru[3])
		else:
			# dado antigo (sem `raw`): cai para a caixa normalizada. Registrado como
			# degradação, não silenciado — quem carrega deve regerar o `_col.json`.
			var q: Array = rc.get("rect", [0, 0, 0, 0])
			if q.size() >= 4:
				r.f0 = int(q[0]); r.f1 = int(q[1]); r.f2 = int(q[2]); r.f3 = int(q[3])
		r.bits = int(rc.get("bits", 1))
		r.bits_rdt = r.bits
		r.forma = int(rc.get("forma", r.bits & 0x0F))
		r.canto = int(rc.get("canto", (r.bits >> 4) & 0x03))
		r.mask = int(rc.get("mask", 0xFFFF))
		r.base_y = int(rc.get("base_y", 0))
		r.topo = int(rc.get("topo", -28800))
		r.nivel = int(rc.get("nivel", 0))
		r.wall = bool(rc.get("wall", false))
		r.envolve()
		c.rects.append(r)
	return c


# ─────────────────────────── interseção segmento × segmento ───────────────────────────

static func _cruz(ax: int, az: int, bx: int, bz: int, cx: int, cz: int) -> int:
	## Sinal do produto vetorial (NCLIP da GTE: MAC0 = (b-a) × (c-a)).
	return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)


static func segmentos_cruzam(ax: int, az: int, bx: int, bz: int,
		cx: int, cz: int, dx: int, dz: int) -> bool:
	## `0x8004ef74`: A e B em lados opostos de CD **e** C e D em lados opostos de AB.
	## O EXE compara os sinais com `xor` + `bgez` (mesmo sinal → sem interseção), o que
	## trata o zero como "mesmo lado" — colinear/tocando NÃO conta como cruzar.
	var s1 := _cruz(ax, az, cx, cz, dx, dz)
	var s2 := _cruz(bx, bz, cx, cz, dx, dz)
	if (s1 ^ s2) >= 0:
		return false
	var s3 := _cruz(cx, cz, ax, az, bx, bz)
	var s4 := _cruz(dx, dz, ax, az, bx, bz)
	return (s3 ^ s4) < 0


# ─────────────────────────────── filtros do laço ───────────────────────────────

static func quadrante(x: int, z: int, c1: Vector2i, c2: Vector2i) -> int:
	## `0x8004d6b8`: bit = 1 << (sinal_x + 2·sinal_z) para o centro 1 (bits 0..3) e o mesmo
	## deslocado 4 para o centro 2 (bits 4..7).
	var q1: int = 1 << ((1 if x < c1.x else 0) + 2 * (1 if z < c1.y else 0))
	var q2: int = 1 << ((1 if x < c2.x else 0) + 2 * (1 if z < c2.y else 0))
	return q1 | (q2 << 4)


func _codigo_quadrante(ax: int, az: int, bx: int, bz: int) -> int:
	var qa := quadrante(ax, az, centro1, centro2)
	var qb := quadrante(bx, bz, centro1, centro2)
	return 0xFF if qa != qb else qa       ## quadrantes diferentes → considera todos


func _altura_ok(r: Rect, min_y: int, max_y: int) -> bool:
	if r.topo > max_y:                    ## `slt maxY, topo` → pula
		return false
	if r.base_y < min_y:                  ## `slt (-1800*base), minY` → pula
		return false
	return true


func _circulo_bloqueia(r: Rect, ax: int, az: int, bx: int, bz: int) -> bool:
	## Forma 0. Dois testes, na ordem do EXE (`0x8004f098`):
	##   1. o trajeto cruza o DIÂMETRO PERPENDICULAR à direção do movimento;
	##   2. o DESTINO está dentro do círculo.
	var raio := r.raio()
	if raio <= 0:
		return false
	var c := r.centro()
	var dx := bx - ax
	var dz := bz - az
	var comp := int(sqrt(float(dx * dx + dz * dz)))
	if comp > 0:
		var ox := dz * raio / comp
		var oz := -dx * raio / comp
		if segmentos_cruzam(ax, az, bx, bz, c.x + ox, c.y + oz, c.x - ox, c.y - oz):
			return true
	var ddx := bx - c.x
	var ddz := bz - c.y
	return int(sqrt(float(ddx * ddx + ddz * ddz))) < raio


func bloqueia(r: Rect, ax: int, az: int, bx: int, bz: int) -> bool:
	## Narrowphase de um registro (sem os filtros) — usada também pelo diagnóstico.
	if r.forma == 0:
		return _circulo_bloqueia(r, ax, az, bx, bz)
	for s: Array in r.segmentos():
		if segmentos_cruzam(ax, az, bx, bz, s[0], s[1], s[2], s[3]):
			return true
	return false


# ───────────────────────── resposta de colisão (o movimento real) ─────────────────────────
#
# ACHADO (2026-08-01, provado por desassembly — ver docs/formatos/ARD.md §3.7): o laço
# `0x8004e830` (segmentos) é um PREDICADO — linha de visão, "dá para ir de A a B". O movimento
# do personagem usa OUTRA rotina: `0x8004af04`, que percorre TODOS os registros e CORRIGE a
# posição (empurra para fora), com:
#   • RAIO de personagem (`ator+0x1A/+0x1C`, inicializado 450/450 em `0x80033538`);
#   • broadphase = ponto ATUAL dentro da caixa CHEIA inflada pelo raio (Minkowski, unsigned);
#   • filtro de NÍVEL: `+0x0C ≤ nivel_ator ≤ +0x0D` (faixa, não altura!) — as paredes têm
#     faixa 0..15 (sempre), os móveis 0..0 (só térreo);
#   • resposta por forma: clamp por eixo na face inflada, escolhido pelo lado de ONDE SE
#     VINHA (`0x8004c960`); é daí que nasce o deslize;
#   • flag 0x100 = correção grande demais → o chamador RESTAURA a posição (parada seca).

const RAIO_ATOR := 450                ## `0x80033538`: raio X/Z do ator do player
const REJEICAO_CAP := 400             ## `0x8004cc68`: teto do escape no caso "dentro"


class Resolvido:
	extends RefCounted
	var x := 0                        ## posição corrigida
	var z := 0
	var empurrado := false            ## flags 0x20: algum collider respondeu
	var rejeitado := false            ## flags 0x100: correção grande demais → cancelar o passo
	var quem: Rect = null             ## último collider que respondeu (`ator+0x3C`)


func resolver(prev_x: int, prev_z: int, nx: int, nz: int, nivel: int,
		raio_x: int = RAIO_ATOR, raio_z: int = RAIO_ATOR) -> Resolvido:
	## `0x8004af04`. (prev) = posição do tick anterior, (nx,nz) = candidata deste tick.
	## Devolve a posição corrigida — o EXE grava em `ator+0x08/+0x10` DENTRO do laço, então
	## um tick pode deslizar em vários colliders (não há break).
	var res := Resolvido.new()
	res.x = nx
	res.z = nz
	# quadrante da posição CANDIDATA contra os dois centros; o filtro do resolver exige
	# `(mask & codigo) == codigo` (`0x8004b020`: `and; bne != mask → skip`).
	for r in rects:
		if (r.bits & MASCARA_RESOLVER) == 0:                     # `0x8004b038` (a2 = 0x4000)
			continue
		# faixa de nível `0x8004b054/0x8004b068`: +0x0C (base_y/-1800) e +0x0D (nivel)
		var nivel_lo := r.base_y / -ALTURA_POR_NIVEL
		if nivel < nivel_lo or r.nivel < nivel:
			continue
		var codigo := quadrante(res.x, res.z, centro1, centro2)
		if (r.mask & codigo) != codigo:                          # `0x8004b020`
			continue
		# posição candidata no referencial do collider (rot 45°)
		var girado := (r.mask & BIT_ROTACIONADO) != 0
		var atual := Vector2i(res.x, res.z)
		if girado:
			atual = girar_para_rect(res.x, res.z, r)
		# broadphase: ponto atual dentro da caixa INFLADA (comparação unsigned no EXE;
		# aqui os valores cabem em int e a forma com sinal é equivalente)
		if atual.x + raio_x - r.f0 < 0 or atual.x + raio_x - r.f0 >= (r.f2 + 2 * raio_x - r.f0):
			continue
		if atual.y + raio_z - r.f1 < 0 or atual.y + raio_z - r.f1 >= (r.f3 + 2 * raio_z - r.f1):
			continue
		if _responder(r, res, prev_x, prev_z, raio_x, raio_z, girado):
			res.empurrado = true
			res.quem = r
			if res.rejeitado:
				return res
	return res


func _responder(r: Rect, res: Resolvido, prev_x: int, prev_z: int,
		rx: int, rz: int, girado: bool) -> bool:
	## Resposta POR FORMA (tabela `0x8009dfec` do EXE):
	##   • 1/7/8 → caixa cheia (`0x8004c960` — desassemblada);
	##   • 0 → radial (aprox. declarada de `0x8004c408`);
	##   • 6 "L" → SÓ as duas arestas; 2/3/4 → SÓ a(s) linha(s) média(s) — respondê-las como
	##     caixa cheia selava salas inteiras: 17 chegadas de porta nasciam PRESAS dentro de
	##     caixas forma 6 (R10B, R207, R209, R303, R305, R20B…) e o usuário batia em "paredes"
	##     onde o jogo só tem uma mureta ("problema de colisão geral, em diversas cenas");
	##   • 5 → sem resposta (3 registros; o predicado ainda barra a linha de visão);
	##   • 9..15 → rampas/escadas, não empurram no plano (`0x8004ce2c` cuida do Y).
	if r.forma >= 9 or r.forma == 5:
		return false
	if r.forma == 0:
		return _responder_circulo(r, res, prev_x, prev_z, rx)
	if r.forma in [2, 3, 4, 6]:
		return _responder_arestas(r, res, prev_x, prev_z, rx, rz, girado)
	if (r.mask & 0x0F00) == 0 and r.forma in [1, 5, 7, 8]:       # `0x8004c988`: sem arestas
		return false
	var p := Vector2i(prev_x, prev_z)
	var n := Vector2i(res.x, res.z)
	if girado:
		p = girar_para_rect(prev_x, prev_z, r)
		n = girar_para_rect(res.x, res.z, r)
	var w := r.f2 - r.f0
	var h := r.f3 - r.f1
	var u := p.x + rx - r.f0
	var v := p.y + rz - r.f1
	var fora_x := u < 0 or u >= w + 2 * rx
	var fora_z := v < 0 or v >= h + 2 * rz
	# casos de toque exato (`0x8004caa8/0x8004cad4`): força um único eixo
	if u == -1 or u == w + 2 * rx + 1:
		fora_x = true
		fora_z = false
	elif v == -1 or v == h + 2 * rz + 1:
		fora_x = false
		fora_z = true
	var corr_x := 0
	var corr_z := 0
	if not fora_x and not fora_z:
		return _escapar_de_dentro(r, res, p, n, rx, rz, girado)
	# A face-alvo é escolhida pelo LADO DE ONDE SE VINHA — o sinal de `u`/`v` (posição anterior
	# relativa à caixa inflada), não o sinal do movimento. O EXE usa `(nx-px) < 0` porque no
	# caso de TRAVESSIA os dois coincidem; mas na aproximação de CANTO (fora nos dois eixos) o
	# eixo SEM movimento escolheria a face do lado OPOSTO, a correção sairia gigante e o passo
	# seria rejeitado — era isso que congelava o andar perto de qualquer quina de móvel
	# (relato: "ainda não consigo andar pelo cenário", parada em -21516 = face inflada − 1).
	if fora_x:
		var alvo := (r.f0 - rx - 1) if u < 0 else (r.f2 + rx + 1)
		corr_x = alvo - n.x
		if absi(corr_x) > 2 * rx:                                # `0x8004cb48`
			res.rejeitado = true
			return true
	if fora_z:
		var alvo_z := (r.f1 - rz - 1) if v < 0 else (r.f3 + rz + 1)
		corr_z = alvo_z - n.y
		if absi(corr_z) > 2 * rx:                                # `0x8004cba8`: rx, NÃO rz
			res.rejeitado = true
			return true
	# Só corrige o eixo que o passo realmente INVADIU: se o candidato continua fora da faixa
	# inflada num eixo, não há o que clampar ali (senão a quina "suga" o personagem).
	if corr_x != 0 and (n.x + rx - r.f0 < 0 or n.x + rx - r.f0 >= w + 2 * rx):
		corr_x = 0
	if corr_z != 0 and (n.y + rz - r.f1 < 0 or n.y + rz - r.f1 >= h + 2 * rz):
		corr_z = 0
	_aplicar(res, corr_x, corr_z, girado)
	return corr_x != 0 or corr_z != 0


func _responder_arestas(r: Rect, res: Resolvido, prev_x: int, prev_z: int,
		rx: int, rz: int, girado: bool) -> bool:
	## Formas 6 ("L"), 2, 3 e 4: o collider são ARESTAS, não uma caixa — o personagem pode
	## estar "dentro" da envolvente livremente; o que não pode é CRUZAR uma aresta. Cada
	## aresta eixo-alinhada vira uma parede fina inflada pelo raio: cruzou → clampa no lado
	## de onde veio. Aproximação declarada das respostas `0x8004d194`/`0x8004c57c`/
	## `0x8004c6ec` (não desassembladas); as diagonais das formas 2/3 ficam com o predicado.
	var p := Vector2i(prev_x, prev_z)
	var n := Vector2i(res.x, res.z)
	if girado:
		p = girar_para_rect(prev_x, prev_z, r)
		n = girar_para_rect(res.x, res.z, r)
	var arestas: Array = []                        # [eixo("x"/"z"), coord, span_lo, span_hi]
	match r.forma:
		6:
			# canto por `bits & 0x30` (mesma seleção de `segmentos()`)
			var zl := r.f3 if (r.bits & 0x20) == 0 else r.f1
			var xl := r.f0 if (r.bits & 0x10) != 0 else r.f2
			arestas = [["z", zl, r.f0, r.f2], ["x", xl, r.f1, r.f3]]
		2:
			arestas = [["z", (r.f1 + r.f3) / 2, r.f0, r.f2]]
		3:
			arestas = [["x", (r.f0 + r.f2) / 2, r.f1, r.f3]]
		4:
			arestas = [["z", (r.f1 + r.f3) / 2, r.f0, r.f2],
				["x", (r.f0 + r.f2) / 2, r.f1, r.f3]]
	var corr_x := 0
	var corr_z := 0
	for a: Array in arestas:
		var coord := int(a[1])
		var lo := mini(int(a[2]), int(a[3])) - rx
		var hi := maxi(int(a[2]), int(a[3])) + rx
		if String(a[0]) == "z":
			# parede horizontal em z=coord: bloqueia cruzar a banda coord±rz dentro do vão
			if n.x < lo or n.x > hi:
				continue
			var lado_p := p.y - coord               # de que lado se vinha
			var alvo_z := coord - rz - 1 if lado_p < 0 else coord + rz + 1
			var dentro_banda := absi(n.y - coord) <= rz
			var cruzou := (p.y - coord) * (n.y - coord) < 0
			if dentro_banda or cruzou:
				corr_z = alvo_z - n.y
		else:
			if n.y < lo or n.y > hi:
				continue
			var lado_px := p.x - coord
			var alvo_x := coord - rx - 1 if lado_px < 0 else coord + rx + 1
			var dentro_banda_x := absi(n.x - coord) <= rx
			var cruzou_x := (p.x - coord) * (n.x - coord) < 0
			if dentro_banda_x or cruzou_x:
				corr_x = alvo_x - n.x
	if corr_x == 0 and corr_z == 0:
		return false
	if absi(corr_x) > 2 * rx or absi(corr_z) > 2 * rx:
		res.rejeitado = true
		return true
	_aplicar(res, corr_x, corr_z, girado)
	return true


func _responder_circulo(r: Rect, res: Resolvido, prev_x: int, prev_z: int, rx: int) -> bool:
	## Forma 0: empurra RADIALMENTE para fora do círculo inflado (raio do círculo + raio do
	## ator). Aproximação declarada da resposta `0x8004c408`.
	var c := r.centro()
	var alcance := r.raio() + rx
	if alcance <= 0:
		return false
	var dx := res.x - c.x
	var dz := res.z - c.y
	var d := int(sqrt(float(dx * dx + dz * dz)))
	if d > alcance:
		return false
	if absi(alcance - d) > 2 * rx:                     # fundo demais: mesmo espírito do 0x100
		res.rejeitado = true
		return true
	if d == 0:                                         # em cima do centro: sai por onde veio
		dx = prev_x - c.x
		dz = prev_z - c.y
		d = maxi(1, int(sqrt(float(dx * dx + dz * dz))))
	res.x = c.x + dx * (alcance + 1) / d
	res.z = c.y + dz * (alcance + 1) / d
	return true


func _escapar_de_dentro(r: Rect, res: Resolvido, p: Vector2i, n: Vector2i,
		rx: int, rz: int, girado: bool) -> bool:
	## `0x8004c85c` + `0x8004cc54`: a posição ANTERIOR já estava dentro da caixa inflada.
	## Escapa pela face CONTRA o movimento (ou a mais próxima, se parado); o eixo escolhido é
	## o de menor fuga; acima do teto (400) rejeita sem mover.
	var mx := n.x - p.x
	var mz := n.y - p.y
	var dir_x := (r.f2 + rx) - n.x + 1                           # sair pela face +X
	var esq_x := (r.f0 - rx) - n.x - 1                           # sair pela face -X (negativo)
	var esc_x := 0
	if mx == 0 and mz == 0:
		esc_x = esq_x if -esq_x < dir_x else dir_x
	else:
		esc_x = dir_x if mx < 0 else esq_x
	var dir_z := (r.f3 + rz) - n.y + 1
	var esq_z := (r.f1 - rz) - n.y - 1
	var esc_z := 0
	if mx == 0 and mz == 0:
		esc_z = esq_z if -esq_z < dir_z else dir_z
	else:
		esc_z = dir_z if mz < 0 else esq_z
	var lim := mini(rx, REJEICAO_CAP)                            # `0x8004cc68`
	# eixo de menor fuga (o bloco de 2 bits de `0x8004ccb0` foi lido em estrutura;
	# esta escolha "menor magnitude" é a leitura declarada, não instrução a instrução)
	var usa_x := absi(esc_x) <= absi(esc_z)
	var fuga := esc_x if usa_x else esc_z
	if absi(fuga) > lim:
		# Fallback declarado: antes de rejeitar, tenta a face MAIS PRÓXIMA (a escolha do caso
		# parado). O escape "contra o movimento" explode quando a posição é ILEGAL (fundo de
		# caixa inflada — chegada de porta, estado herdado) e andar na diagonal; rejeitar aqui
		# congelava o personagem enquanto o input estivesse pressionado.
		var perto_x := esq_x if -esq_x < dir_x else dir_x
		var perto_z := esq_z if -esq_z < dir_z else dir_z
		usa_x = absi(perto_x) <= absi(perto_z)
		fuga = perto_x if usa_x else perto_z
		if absi(fuga) > lim:
			res.rejeitado = true
			return true
		_aplicar(res, fuga if usa_x else 0, 0 if usa_x else fuga, girado)
		return true
	_aplicar(res, esc_x if usa_x else 0, 0 if usa_x else esc_z, girado)
	return true


func _aplicar(res: Resolvido, corr_x: int, corr_z: int, girado: bool) -> void:
	if corr_x == 0 and corr_z == 0:
		return
	if girado:                                                   # des-rotação `0x8004cbd0`
		var dx := (corr_x + corr_z) * ROT_NUM >> ROT_SHIFT
		var dz := (corr_z - corr_x) * ROT_NUM >> ROT_SHIFT
		res.x += dx
		res.z += dz
	else:
		res.x += corr_x
		res.z += corr_z


# ─────────────────────────────── consulta pública ───────────────────────────────

func trajeto_livre(ax: int, az: int, bx: int, bz: int,
		y: int = 0, mascara: int = MASCARA_PLAYER, testa_altura: bool = true) -> bool:
	## O teste do motor: o trajeto (ax,az) → (bx,bz) está livre?
	return primeiro_bloqueio(ax, az, bx, bz, y, mascara, testa_altura) == null


func primeiro_bloqueio(ax: int, az: int, bx: int, bz: int,
		y: int = 0, mascara: int = MASCARA_PLAYER, testa_altura: bool = true) -> Rect:
	## Igual a `trajeto_livre`, mas devolve QUEM barrou (para depuração e para a resposta
	## de deslize, que no EXE usa o ponteiro do retângulo).
	var codigo := _codigo_quadrante(ax, az, bx, bz)
	for r in rects:
		if (r.bits & mascara) == 0:                       # filtro 1
			continue
		if r.forma == 0x0B:                               # filtro 2 (o EXE pula o tipo 0x0b)
			continue
		if (r.mask & codigo) == 0:                        # filtro 3: quadrante
			continue
		# ROTAÇÃO 45° (`mask & 0x1000`, 437 registros): o motor NÃO gira o collider — ele leva o
		# TRAJETO para o referencial do collider (`0x8004e970`), com o mesmo teste depois.
		# Faltava aqui: sem isso esses colliders barram no lugar ERRADO (o retângulo cru), que é
		# o sintoma de "parece testar em dois lugares".
		var px := ax
		var pz := az
		var qx := bx
		var qz := bz
		if (r.mask & BIT_ROTACIONADO) != 0:
			var p := girar_para_rect(px, pz, r)
			var q := girar_para_rect(qx, qz, r)
			px = p.x; pz = p.y; qx = q.x; qz = q.y
		var min_x := mini(px, qx)
		var max_x := maxi(px, qx)
		var min_z := mini(pz, qz)
		var max_z := maxi(pz, qz)
		if testa_altura and not _altura_ok(r, y, y):      # filtro 4: altura/nível
			continue
		if r.x1 < min_x or r.x0 > max_x:                  # broadphase do EXE
			continue
		if r.z1 < min_z or r.z0 > max_z:
			continue
		if bloqueia(r, px, pz, qx, qz):                   # narrowphase: a forma
			return r
	return null
