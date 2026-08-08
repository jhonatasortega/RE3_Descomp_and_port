extends RefCounted
## Overlay de MIRA/TIRO do player — clipes `miraNN` do `PL00.glb`.
##
## De onde vêm: banco PARCIAL SUPERIOR (nb=9) do `PL00W00.PLW`, exportado por
## `tools/pld2gltf.py::build_partial_clips`. O de-para de osso é PROVADO por casamento de
## `relpos` INTEIRO EXATO + cadeia de pais entre o EMR do banco parcial e o esqueleto de 15
## ossos do `PL00.PLD` — ver `docs/decomp/notes/plw.md` §9 e `docs/formatos/animacoes_player.md`.
##
## O que estes testes travam:
##  1. os 8 clipes `mira00..mira07` existem no `.glb`;
##  2. cada um tem o nº EXATO de quadros da tabela EDD do banco (10/20/1/20/1/20/1/32);
##  3. eles animam EXATAMENTE os 9 ossos do de-para (`bone00..bone08` = raiz + cabeça +
##     braço-D + braço-E + pivô da pelve) e NENHUM osso de perna (`bone09..bone14`) —
##     é isso que faz deles um OVERLAY (as pernas seguem com o clipe de locomoção);
##  4. o punho direito (`bone04`) LEVANTA de verdade: a `mira00` sai da altura do quadril e
##     sobe ~0.9 m, e as poses mantidas `mira02`/`mira04`/`mira06` são três alturas distintas
##     (mira média / alta / baixa) — casa com os 3 `aim_tier` do EXE (`0x8003ac48`);
##  5. os `armNN` (banco 0, corpo inteiro) NÃO foram quebrados: seguem com 15 ossos.

const GLB := "PLD/PL00.glb"
## nº de quadros por sequência do EDD compartilhado dos bancos parciais do PL00W00.PLW
## (registros de 8 B em `blk5` @0x88f8: {u16 nframes, u16 frameOff, u32 poseStart}).
const QUADROS := [10, 20, 1, 20, 1, 20, 1, 32]
## de-para provado: banco parcial nb=9 -> ossos do esqueleto de 15
const OSSOS_SUP := [0, 1, 2, 3, 4, 5, 6, 7, 8]
const OSSOS_PERNA := [9, 10, 11, 12, 13, 14]


func run(t: Object) -> bool:
	t.group("Anim mira")
	var modelo := AssetIO.model(GLB)
	if not t.check(modelo != null, "%s carrega (rode tools/build_assets.py --out port --only pld)" % GLB):
		return true
	var ap := AssetIO.anim_player(modelo)
	if not t.check(ap != null, "o .glb traz um AnimationPlayer"):
		modelo.free()
		return true
	var esq: Skeleton3D = _skeleton(modelo)
	if not t.check(esq != null, "o .glb traz um Skeleton3D"):
		modelo.free()
		return true
	t.eq(esq.get_bone_count(), 15, "esqueleto do PLD = 15 ossos")

	# ── 1) os clipes existem ──
	var lista := ap.get_animation_list()
	for i in QUADROS.size():
		t.check(lista.has("mira%02d" % i), "clipe mira%02d existe no .glb" % i)
	var n_mira := 0
	for nome in lista:
		if String(nome).begins_with("mira"):
			n_mira += 1
	t.eq(n_mira, QUADROS.size(), "exatamente %d clipes miraNN (as 8 seqs do banco parcial)" % QUADROS.size())

	# ── 2) nº de quadros e 3) ossos animados ──
	for i in QUADROS.size():
		var nome := "mira%02d" % i
		var a: Animation = ap.get_animation(nome)
		if not t.check(a != null, "%s carrega" % nome):
			continue
		t.eq(a.get_track_count(), OSSOS_SUP.size(),
			"%s tem 1 trilha por osso do de-para (%d)" % [nome, OSSOS_SUP.size()])
		t.eq(a.track_get_key_count(0), int(QUADROS[i]),
			"%s tem %d quadros (EDD do banco parcial)" % [nome, int(QUADROS[i])])
		var animados := {}
		var so_rotacao := true
		for k in a.get_track_count():
			var p := String(a.track_get_path(k))
			animados[p.get_slice(":", 1)] = true
			if a.track_get_type(k) != Animation.TYPE_ROTATION_3D:
				so_rotacao = false
		t.check(so_rotacao, "%s só tem trilhas de ROTAÇÃO (sem translação de raiz — é overlay)" % nome)
		var faltou := ""
		for b in OSSOS_SUP:
			if not animados.has("bone%02d" % b):
				faltou += " bone%02d" % b
		t.eq(faltou, "", "%s anima os 9 ossos do de-para (raiz+cabeça+braços+pelve)" % nome)
		var sobrou := ""
		for b in OSSOS_PERNA:
			if animados.has("bone%02d" % b):
				sobrou += " bone%02d" % b
		t.eq(sobrou, "", "%s NÃO anima osso de perna (bone09..14 ficam p/ a locomoção)" % nome)

	# ── 4) o braço LEVANTA (medição no esqueleto, não fé) ──
	var i_punho := esq.find_bone("bone04")            ## punho direito (plw.md §6)
	t.check(i_punho >= 0, "osso bone04 (punho direito) existe no esqueleto")
	var y_repouso := _altura_punho(modelo, ap, esq, i_punho, "", 0.0)
	var y_mira00_ini := _altura_punho(modelo, ap, esq, i_punho, "mira00", 0.0)
	var y_mira00_fim := _altura_punho(modelo, ap, esq, i_punho, "mira00", 1.0)
	var y_media := _altura_punho(modelo, ap, esq, i_punho, "mira02", 0.0)
	var y_alta := _altura_punho(modelo, ap, esq, i_punho, "mira04", 0.0)
	var y_baixa := _altura_punho(modelo, ap, esq, i_punho, "mira06", 0.0)
	## No glTF o eixo Y aponta para CIMA (pld2gltf converte o (x,-y,-z) do PS1), então SUBIR
	## a arma = Y AUMENTA. Medido no PL00W00.PLW: punho y=+297 (PS1) no repouso -> -598 na
	## seq0, i.e. +0,895 m em Godot.
	t.check(y_mira00_fim - y_mira00_ini > 0.5,
		"mira00 LEVANTA o punho direito (>0,5 m)",
		"inicio=%.3f fim=%.3f repouso=%.3f" % [y_mira00_ini, y_mira00_fim, y_repouso])
	t.check(y_mira00_fim > y_repouso + 0.5,
		"no fim da mira00 o punho está acima do repouso do esqueleto",
		"fim=%.3f repouso=%.3f" % [y_mira00_fim, y_repouso])
	## as 3 poses mantidas = os 3 `aim_tier` (EXE `0x8003ac48`: pose 14/15/16)
	t.check(y_alta > y_media and y_media > y_baixa,
		"mira04 (alta) > mira02 (média) > mira06 (baixa) — os 3 aim_tier são alturas distintas",
		"alta=%.3f media=%.3f baixa=%.3f" % [y_alta, y_media, y_baixa])
	t.check(y_alta - y_baixa > 0.5, "a faixa de mira cobre >0,5 m entre o tier alto e o baixo",
		"alta=%.3f baixa=%.3f" % [y_alta, y_baixa])
	## mira07 = TIRO: oscila (recuo) em torno da mira média, não é pose parada
	var a7: Animation = ap.get_animation("mira07")
	if a7 != null:
		var y0 := _altura_punho(modelo, ap, esq, i_punho, "mira07", 0.0)
		var ymax := y0
		var ymin := y0
		for s in 16:
			var y := _altura_punho(modelo, ap, esq, i_punho, "mira07", float(s) / 15.0)
			ymax = maxf(ymax, y)
			ymin = minf(ymin, y)
		t.check(ymax - ymin > 0.05, "mira07 tem excursão de recuo no punho (>5 cm)",
			"min=%.3f max=%.3f" % [ymin, ymax])
		t.check(absf(y0 - y_media) < 0.30, "mira07 parte da altura da mira média (tier 0)",
			"mira07[0]=%.3f media=%.3f" % [y0, y_media])

	# ── 5) os armNN (banco 0) continuam íntegros ──
	var a_arm: Animation = ap.get_animation("arm02")
	if t.check(a_arm != null, "arm02 (idle armado, banco 0) continua no .glb"):
		var ossos_arm := {}
		for k in a_arm.get_track_count():
			ossos_arm[String(a_arm.track_get_path(k)).get_slice(":", 1)] = true
		t.eq(ossos_arm.size(), 15, "arm02 segue animando os 15 ossos (corpo inteiro)")
	var n_arm := 0
	var n_anim := 0
	for nome in lista:
		if String(nome).begins_with("arm"):
			n_arm += 1
		elif String(nome).begins_with("anim"):
			n_anim += 1
	t.eq(n_arm, 18, "18 clipes armNN (banco 0 do PLW)")
	t.eq(n_anim, 22, "22 clipes animNN (banco do PLD)")

	modelo.free()
	return true


func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _skeleton(c)
		if r != null:
			return r
	return null


func _altura_punho(_raiz: Node3D, ap: AnimationPlayer, esq: Skeleton3D, idx: int,
		clipe: String, frac: float) -> float:
	## Y (em metros, espaço do Skeleton3D) do osso `idx` com o clipe posicionado em `frac`
	## (0..1) do seu comprimento. `clipe` vazio = pose de repouso do esqueleto.
	##
	## A FK é feita À MÃO de propósito: o `AnimationPlayer` só aplica pose quando o nó está
	## na árvore e processando, e este teste roda num `SceneTree` sem cena. Ler as trilhas
	## direto também é o que queremos medir — o DADO do `.glb`, não o player.
	var a: Animation = null if clipe == "" else ap.get_animation(clipe)
	var tempo := 0.0 if a == null else a.length * clampf(frac, 0.0, 1.0)
	var acc := Transform3D()
	var b := idx
	while b >= 0:
		var rest := esq.get_bone_rest(b)
		var base := Basis(_rot_do_clipe(esq, a, tempo, b))
		acc = Transform3D(base, rest.origin) * acc
		b = esq.get_bone_parent(b)
	return acc.origin.y


func _rot_do_clipe(esq: Skeleton3D, a: Animation, tempo: float, osso: int) -> Quaternion:
	## Rotação do osso no instante `tempo`; sem trilha (osso fora do de-para) = repouso.
	var rest := esq.get_bone_rest(osso).basis.get_rotation_quaternion()
	if a == null:
		return rest
	var alvo := esq.get_bone_name(osso)
	for k in a.get_track_count():
		if a.track_get_type(k) != Animation.TYPE_ROTATION_3D:
			continue
		if String(a.track_get_path(k)).get_slice(":", 1) == alvo:
			return a.rotation_track_interpolate(k, tempo)
	return rest
