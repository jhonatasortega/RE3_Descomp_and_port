class_name Coords
extends RefCounted
## Conversão de coordenadas PS1 <-> Godot, num só lugar (P0-06).
##
## O RE3 usa **+Y para baixo** e unidades de mundo inteiras (as mesmas do ARD/RDT: câmeras,
## portas, colisão). O Godot usa +Y para cima e metros float. Regra:
##
##     godot = Vector3(ps1.x, -ps1.y, ps1.z) / WORLD_SCALE
##
## `WORLD_SCALE = 808` vem de `2400 / 2.971`: um personagem tem ~2400 unidades PS1 de altura
## e o `PL00.glb` tem 2.971 unidades no Godot — dividir por 808 faz o modelo casar com as
## proporções do jogo (`model_scale = 1.0`). Fonte: docs/godot_gameplay.md.
##
## ⚠ **DOIS eixos são negados, não um.** O PS1 é canhoto (Y para baixo) e o Godot é destro;
## negar UM só eixo troca a mão do sistema e **espelha a cena inteira**. Com `(x, -y, z)` o
## mundo 3D saía espelhado em relação ao background: medido na R100, o fichário (que aparece à
## DIREITA no cenário) projetava em x=543 com a Jill em 640 — ou seja, à esquerda. A conversão
## correta é a mesma que o `pld2gltf` usa para os modelos: `(x, -y, -z)`.
##
## REGRA DE OURO: a lógica de jogo trabalha SEMPRE em unidades PS1 inteiras. Esta classe só
## é chamada na fronteira com o visual (posicionar nó, montar câmera). Converter cedo e
## arrastar float pela lógica é como se perde fidelidade de 1:1.

const WORLD_SCALE := 808.0

## Relação entre o ângulo 0 do PS1 e o yaw do node no Godot: **0°**, com a FRENTE em -Z.
## Fixado por observação em jogo (2026-07-31): com a frente em +Z, o W andava para trás e o S
## para frente. Consistente com a orientação do mesh medida no protótipo (ver abaixo).
##
## Cuidado para não confundir com outra rotação, essa sim medida: o protótipo antigo usa
## `model_yaw_offset_deg = 90` para alinhar o "frente" VISUAL do mesh ao -Z do node
## (verificado por render em `godot/dev/tools_orient_test.gd`: com yaw=90 a câmera olhando
## -Z vê as costas; 180 e 0 davam perfil, e a Jill "andava de lado"). Isso é
## mesh -> node; aqui é ângulo PS1 -> node. São eixos diferentes e valores diferentes.
## (`docs/godot_gameplay.md` ainda cita 180 — está defasado em relação ao código.)
const YAW_OFFSET_DEG := 0.0

## Offset só do MESH dentro do node, medido por render no protótipo (ver acima).
const MESH_YAW_OFFSET_DEG := -90.0   ## era +90 no mundo espelhado (ver nota da conversão)


static func to_godot(ps1: Vector3) -> Vector3:
	return Vector3(ps1.x, -ps1.y, -ps1.z) / WORLD_SCALE


static func to_godot_i(x: int, y: int, z: int) -> Vector3:
	return Vector3(float(x), float(-y), float(-z)) / WORLD_SCALE


static func to_ps1(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.y, -g.z) * WORLD_SCALE


static func to_ps1_i(g: Vector3) -> Vector3i:
	var p := to_ps1(g)
	return Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))


static func len_to_godot(units: float) -> float:
	## Comprimento/raio em unidades PS1 -> unidades do Godot (sem inverter eixo).
	return units / WORLD_SCALE


static func len_to_ps1(g: float) -> float:
	return g * WORLD_SCALE


static func yaw_from_ps1_angle(a: int) -> float:
	## Ângulo PS1 (12 bits) -> yaw do node em radianos, já com o offset do modelo.
	return deg_to_rad(PS1Math.to_deg(a) + YAW_OFFSET_DEG)


static func ps1_angle_from_yaw(yaw_rad: float) -> int:
	return PS1Math.from_deg(rad_to_deg(yaw_rad) - YAW_OFFSET_DEG)


static func basis_from_ps1_rot(rot: Vector3i) -> Basis:
	## Rotação de 3 eixos do dado do jogo (`RotMatrix` do opcode `0x7f`: `rot` s16, 4096 = 360°)
	## para a `Basis` do Godot. **Medido, não escolhido** — ver `port/dev/diag_rot_om.gd`.
	##
	## Critério da medição: muitos itens de chão são QUADS PLANOS (a Chave do armazém da R100 tem
	## AABB 123×**0**×61). Num plano a normal precisa apontar para a câmera que o enquadra, senão
	## o jogador veria o avesso — ou nada, se o plano ficar de perfil. Rodando os 30 itens planos
	## do jogo contra as 12 convenções possíveis (2 ordens de composição × sinais):
	##
	##     Rx·Ry·Rz com (+x, −y, −z)  →  26/30 (87%)   ← esta
	##     Rx·Ry·Rz com (−x, −y, −z)  →  24/30
	##     as outras 10               →  17..22/30 (57–73%)
	##
	## E a medição CONCORDA com a teoria: a conversão de mundo do port é `(x, −y, −z)`, que é uma
	## rotação de 180° em X; conjugar uma rotação por ela mantém o ângulo de X e inverte os de Y e
	## Z. Duas linhas independentes no mesmo lugar.
	##
	## Os 4/30 que sobram foram olhados um por um, e três não são contra-exemplo:
	##   • R210 aot4 e R219 aot4 (`rot(0,3390,0)`): `dot = -0.03`, ou seja o plano está DE PERFIL
	##     para a câmera — empate técnico, o sinal do teste é ruído;
	##   • R40F aot3 (`rot(0,0,0)`): sem rotação, **nenhuma** convenção muda o resultado (a normal
	##     do próprio modelo aponta para longe da câmera que o enquadra);
	##   • R501 aot9 (`rot(0,-6528,0)`): discrepância real, 1 caso, declarada.
	## Entre os casos decidíveis e não degenerados: **26/27**. O `.glb` é `doubleSided`, então no
	## caso ruim se vê o verso do plano, não um buraco.
	var bx := Basis(Vector3.RIGHT, deg_to_rad(PS1Math.to_deg(rot.x)))
	var by := Basis(Vector3.UP, deg_to_rad(PS1Math.to_deg(-rot.y)))
	var bz := Basis(Vector3.BACK, deg_to_rad(PS1Math.to_deg(-rot.z)))
	return bx * by * bz
