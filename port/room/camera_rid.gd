class_name CameraRID
extends RefCounted
## Monta a Camera3D a partir do registro RID da sala (P1-04).
##
## Cada câmera do RDT é `flag, attr, from[3], to[3], mask_data_ptr` (struct de 32 B). A câmera
## fica em `from` olhando para `to` — fixa, como no RE clássico.
##
## ── O campo `attr` É o FOV: DECIFRADO (P1-04) ──
## A documentação marcava `attr` como 🟡 "FOV?". Ele é a **distância de projeção da GTE em
## ponto-fixo**: `h = attr / 128`, e como a tela do PS1 tem 240 linhas (meia-altura 120):
##
##     FOV_vertical = 2 · atan(120 / (attr / 128))
##
## Evidência (medida nas 2105 câmeras, 24 valores distintos de `attr`):
##
## | attr | câmeras | h | FOV |
## |---|--:|--:|--:|
## | 29623 | 902 (42,9%) | 231,4 | **54,81° ≈ 55°** |
## | 37165 | 486 (23,1%) | 290,4 | **44,91° ≈ 45°** |
## | 32946 | 461 (21,9%) | 257,4 | **49,99° ≈ 50°** |
##
## 1. Os 24 valores caem em **graus INTEIROS** (desvio médio 0,11°, máximo 0,47°) — os
##    artistas escolheram FOVs redondos: 55, 45, 50, 49, 52, 60, 47, 48, 54, 53, 65, 51, 57,
##    40, 35, 46, 59, 61, 32, 38, 70, 77, 37.
## 2. Teste da hipótese nula: 2000 amostras de 24 `attr` aleatórios na mesma faixa dão desvio
##    médio esperado de 0,25 — e **nenhuma das 2000** chega a ser tão próxima de inteiros
##    quanto o dado real. A coincidência é estatisticamente descartada.
## 3. A classe dominante (43% das câmeras, inclusive as duas da R100) dá **54,81°**, que é
##    exatamente o **55° validado por render** no protótipo antigo — o valor que antes era
##    calibração manual agora **sai do dado**.
##
## Consequência: as **2105** câmeras têm FOV próprio, não só as 43% calibradas à mão.

const H_ESCALA := 128.0             ## attr -> distância de projeção (ponto-fixo)
const TELA_MEIA_ALTURA := 120.0     ## PS1: 240 linhas
const FOV_DEFAULT := 55.0           ## só para attr ausente/zerado (não deve acontecer)


static func fov_for(attr: int) -> float:
	if attr <= 0:
		return FOV_DEFAULT
	var h := float(attr) / H_ESCALA
	return rad_to_deg(2.0 * atan(TELA_MEIA_ALTURA / h))


static func projection_distance(attr: int) -> float:
	## `h` da GTE, em pixels de tela do PS1 (útil para conferir contra o disassembly).
	return float(attr) / H_ESCALA


static func is_calibrated(attr: int) -> bool:
	## Todo attr válido tem FOV derivado do dado — não há mais calibração manual.
	return attr > 0


static func apply(cam3d: Camera3D, c: RoomData.Camera) -> void:
	## Posiciona/orienta a câmera e ajusta o FOV. `keep_aspect = KEEP_HEIGHT` porque o mundo
	## é sempre 4:3 1280×960 e o modo 16:9 recorta a apresentação (P1-15) — o campo de visão
	## VERTICAL é que precisa ser estável entre os dois modos.
	var from_g := Coords.to_godot_i(c.from_ps1.x, c.from_ps1.y, c.from_ps1.z)
	var to_g := Coords.to_godot_i(c.to_ps1.x, c.to_ps1.y, c.to_ps1.z)
	cam3d.keep_aspect = Camera3D.KEEP_HEIGHT
	cam3d.fov = fov_for(c.attr)
	cam3d.near = 0.05
	cam3d.far = 200.0
	cam3d.position = from_g
	if not from_g.is_equal_approx(to_g):
		cam3d.look_at(to_g, Vector3.UP)


static func background_rel(room_id: String, cam_index: int) -> String:
	## Caminho relativo do background da câmera, preferindo o HD.
	## O pipeline grava `assets/STAGE{n}/R###_{cam}.webp` (HD 1280×960) e mantém o
	## `.png` (PS1 320×240) onde não existe HD — ~600 câmeras (ver P1-02).
	var st := RoomData.stage_of(room_id)
	var webp := "STAGE%d/%s_%d.webp" % [st, room_id, cam_index]
	if AssetIO.exists(webp):
		return webp
	var png := "STAGE%d/%s_%d.png" % [st, room_id, cam_index]
	return png if AssetIO.exists(png) else ""


static func background(room_id: String, cam_index: int) -> Texture2D:
	var rel := background_rel(room_id, cam_index)
	return AssetIO.texture(rel) if rel != "" else null
