class_name CameraRVD
extends RefCounted
## Troca de câmera pelas zonas RVD — o algoritmo do EXE, não uma heurística (P1-05).
##
## O protótipo antigo escolhia a câmera por "melhor enquadramento" (projetava o torso e
## comparava `ndc_x`). Funciona, mas **não é o que o jogo faz** — e num port 1:1 a posição
## exata do corte de câmera é parte da experiência. Aqui está a rotina real.
##
## ── Consumidor per-frame provado no EXE: `0x8002a84c` ── (docs/formatos/ARD.md §3.5.1)
## Por frame, varrendo as entradas de 20 B (stride `0x14`):
##
##   1. `from_cam` (+2) tem de ser a câmera ATUAL (`gs+0x2486`)          `lbu +2 / bne`
##   2. zona ATIVA: byte baixo dos flags (+0) != 0                        `lbu +0 / beqz`
##   3. GRUPO: byte alto dos flags (+1) == 0x80 (global) OU == grupo      `lb +1 / beq -0x80`
##      corrente (`gs+0x2495`)
##   4. PONTO-EM-QUAD do jogador (X,Z) contra os 4 pontos                 `0x8001020c`
##   5. dentro → commit `to_cam` (+3) em `gs+0x2486`, ancorando a         `0x8002a938`
##      entrada em `gs+0x2148` (é essa âncora que dá a histerese)
##
## A histerese vem em 2 fases (chamadores `0x80023b84` a0=0 = detectar, `0x80024abc` a0=1 =
## commitar) e da ÂNCORA: enquanto o jogador continua dentro do quad que causou a troca, não
## se troca de novo. Sem isso as faixas opostas (`A→B` e `B→A`, deslocadas de propósito)
## fariam a câmera piscar na fronteira.
##
## Nota honesta do dado: o teste de "ativa" no código é `byte_baixo != 0`, não um `& 1`
## literal; como os flags reais só têm byte baixo `0x00`/`0x01`, coincide com o bit 0.

const GRUPO_GLOBAL := 0x80


static func flags_active(flags: int) -> bool:
	return (flags & 0xFF) != 0


static func flags_group(flags: int) -> int:
	return (flags >> 8) & 0xFF


static func group_matches(flags: int, grupo_corrente: int) -> bool:
	var g := flags_group(flags)
	return g == GRUPO_GLOBAL or g == grupo_corrente


static func _s32(v: int) -> int:
	## O EXE multiplica com `mult`/`mflo`: fica só a palavra BAIXA (32 bits com sinal). Com
	## coordenadas de quad em ±32768 os produtos passam de 2³¹ e **estouram** — e o resultado
	## do estouro faz parte do comportamento (é o que descarta os quads degenerados). Emular em
	## 64 bits "corrigiria" o motor e mudaria onde a câmera troca.
	var w := v & 0xFFFFFFFF
	return w - 0x100000000 if w >= 0x80000000 else w


static func point_in_quad(quad: Array, x: int, z: int) -> bool:
	## `0x8001020c` instrução por instrução. NÃO é "todos os sinais iguais": são 4 meias-retas
	## com orientação FIXA, dos dois cantos OPOSTOS (q0 e q2), e o quad só conta se a ordem dos
	## seus pontos casar com essa orientação.
	##
	## Isto substitui a versão anterior, que aceitava as duas orientações. A diferença é visível
	## em jogo: zonas que o motor NUNCA aceita disparavam no port, e a câmera trocava em lugar
	## errado (relato do usuário: "área de transição da câmera 2", "parece testar em 2 lugares").
	##
	##     t0 = px-q0.x   t1 = pz-q0.z   t2 = q1.x-q0.x   t3 = q1.z-q0.z
	##     exige  t3*t0 >= t2*t1                                   (aresta q0→q1)
	##     t4 = q3.x-q0.x   t5 = q3.z-q0.z
	##     exige  t4*t1 >= t5*t0                                   (aresta q0→q3)
	##     rebase em q2: t0..t5 -= (q2-q0)
	##     exige  t2*t1 >= t3*t0                                   (aresta q2→q1)
	##     exige  t5*t0 >= t4*t1                                   (aresta q2→q3)
	if quad.size() < 4:
		return false
	var q0: Vector2i = quad[0]
	var q1: Vector2i = quad[1]
	var q2: Vector2i = quad[2]
	var q3: Vector2i = quad[3]
	var t0 := x - q0.x
	var t1 := z - q0.y
	var t2 := q1.x - q0.x
	var t3 := q1.y - q0.y
	if _s32(t3 * t0) < _s32(t2 * t1):
		return false
	var t4 := q3.x - q0.x
	var t5 := q3.y - q0.y
	if _s32(t4 * t1) < _s32(t5 * t0):
		return false
	var dx := q2.x - q0.x
	var dz := q2.y - q0.y
	t0 -= dx; t1 -= dz
	t2 -= dx; t3 -= dz
	t4 -= dx; t5 -= dz
	if _s32(t2 * t1) < _s32(t3 * t0):
		return false
	return _s32(t5 * t0) >= _s32(t4 * t1)


class Estado:
	extends RefCounted
	var camera := 0                 ## câmera corrente (gs+0x2486)
	var grupo := GRUPO_GLOBAL       ## seletor de grupo corrente (gs+0x2495) = nível do piso
	var trocas := 0                 ## contador (diagnóstico/validação)
	## Zonas MORTAS nesta visita à sala (índices). Mecânica real do EXE (`0x80051864`, estado
	## 35 da máquina de fade): ao COMMITAR uma troca via RVD, a primeira zona da corrida da
	## câmera NOVA tem o quad REESCRITO para um quadradinho fora do mapa (−32700..−32600) —
	## morre até o RDT ser recarregado. É a supressão do retorno imediato (anti-flicker):
	## a zona `B→A` degenerada que cobre a sala toda morre quando se entra em B.
	## Chegada por PORTA não mata nada — por isso câmeras de zona única (R200 8..11,
	## alcançáveis só por porta) conseguem sair pela própria zona.
	var mortas: Dictionary = {}


static func inicio_da_corrida(room: RoomData, camera: int) -> int:
	## `0x8002a968`: primeira entrada cujo `from_cam` é a câmera (início da corrida contígua).
	if room.rvd.is_empty():
		return 0
	for i in room.rvd.size():
		if room.rvd[i].from_cam == camera:
			return i
	return room.rvd.size()                             ## câmera sem zona: corrida vazia


static func matar_supressora(room: RoomData, st: Estado, camera_nova: int) -> void:
	## Ao ENTRAR numa câmera (troca RVD ou porta), a primeira zona da corrida dela sai de
	## jogo. Duas evidências independentes no EXE:
	##   • fade (`0x8005182c` commit + `0x80051864` DESTRÓI o quad da zona ancorada);
	##   • carga de sala (`0x80049728` commit com a câmera de chegada) — e o consumidor varre
	##     a partir de âncora+20, ou seja, exclui a ancorada.
	## É a supressão do retorno imediato: a zona `B→A` degenerada que cobre a sala morre
	## quando se entra em B, sobrando a faixa deslocada (a histerese desenhada pelo jogo).
	##
	## REGRA DECLARADA DO PORT (não provada instrução a instrução): corrida com UMA zona só
	## não perde nada. Sem isso, as câmeras 8..11 da R200 (uma zona cada, alcançáveis só por
	## porta) ficariam sem saída — e o usuário mediu exatamente essa prisão em jogo. A
	## semântica exata do EXE nesse canto fica para a comparação com o emulador (P1-14).
	var i := inicio_da_corrida(room, camera_nova)
	if i >= room.rvd.size() or room.rvd[i].from_cam != camera_nova:
		return
	var fim := i
	while fim < room.rvd.size() and room.rvd[fim].from_cam == camera_nova:
		fim += 1
	if fim - i > 1:
		st.mortas[i] = true


static func update(room: RoomData, st: Estado, x: int, z: int) -> int:
	## Um passo do consumidor `0x8002a84c`. Varre a CORRIDA contígua da câmera atual (a tabela
	## é ordenada por `from_cam` em 169/169 salas), pulando as zonas MORTAS; a primeira que
	## contém o ponto (ativa e com grupo compatível) commita.
	##
	## Histórico: a versão anterior pulava SEMPRE a primeira zona da corrida ("skip-first"),
	## lendo `anchor+20` do consumidor. Estava certa para trocas via RVD (a primeira zona morre
	## mesmo — mas pelo `0x80051864`, não pelo scan) e errada para chegadas por PORTA: câmeras
	## com UMA zona só (R200 8..11, alcançáveis só por porta) ficavam sem saída — era a câmera
	## presa que o usuário viu na rua da R200.
	var i := inicio_da_corrida(room, st.camera)
	while i < room.rvd.size():
		var e := room.rvd[i]
		if e.from_cam != st.camera:                    # fim da corrida: o laço para aqui
			break
		if st.mortas.has(i):                           # zona destruída pelo `0x80051864`
			i += 1
			continue
		if not flags_active(e.flags):                  # `lbu +0 / beqz` → próxima
			i += 1
			continue
		if not group_matches(e.flags, st.grupo):       # `lb +1`: 0x80 global ou o grupo corrente
			i += 1
			continue
		if e.to_cam == st.camera:                      # zona "ficar aqui": não commita nem
			i += 1                                     # encerra a varredura (senão a 0→0
			continue                                   # degenerada da R100 come tudo)
		if point_in_quad(e.quad, x, z):                # `jal 0x8001020c` → primeira que casa vence
			st.trocas += 1
			st.camera = e.to_cam                       # commit (`0x8002a938`)
			matar_supressora(room, st, e.to_cam)       # fade estado 35 (`0x80051864`)
			return st.camera
		i += 1
	return st.camera


static func best_camera_for(room: RoomData, x: int, z: int) -> int:
	## Câmera INICIAL ao entrar na sala. O EXE recebe isso do descriptor da porta
	## (`to_camera` do SCD, ver P3-03); este fallback existe para spawn de debug e para
	## salas sem porta de entrada conhecida: escolhe a câmera cuja zona `from == to`
	## (região de permanência) contenha o ponto; senão, a câmera 0.
	for e in room.rvd:
		if e.from_cam == e.to_cam and flags_active(e.flags) and point_in_quad(e.quad, x, z):
			return e.from_cam
	return 0
