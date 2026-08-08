extends SceneTree
## Prova visual do ECG (`res://present/ecg.gd`) SEM depender de `menu_status.gd`.
##
## Desenha o painel B1 `(0,64,96,56,72,20)` recortado do `stmain0u_p0.png` (com o `+128` da
## tpage `0x9B`) e, por cima, o ECG em 12 fases de uma condição. Salva
## `port/dev/_shot_ecg.png` (não vai PNG na raiz do `port/`).
##
## godot --rendering-driver opengl3 --path port --script res://dev/shot_ecg.gd
##     godot ... --script res://dev/shot_ecg.gd -- 3      # condição 3 (DANGER)

const U_TPAGE_9B := 128
const PAINEL := [0, 64, 96, 56]                  ## u, v, w, h do B1
const DESTINO := Vector2i(72, 20)                ## dx, dy do B1
const FASES := [-28, -16, 0, 12, 20, 24, 28, 34, 40, 52, 64, 73]
const CELULA := Vector2i(104, 64)          ## painel 96x56 + 4 px de margem
const COLUNAS := 4
## ZOOM = **4**, a escala real do `MenuStatus` (`ESCALA`, 1280/320). Era 3, o que escondia
## justamente o defeito que o dono do repo viu: em 4× cada pixel de 320×240 é um quadrado de 4.
const ZOOM := 4

var _t := 0
var _no: Node2D = null
var _cond := 0


class Tira:
	extends Node2D
	var atlas: Texture2D
	var fator := 1                             ## 4 quando o atlas é o bloco HD `chrome_9b`
	var cond := 0

	func _draw() -> void:
		var ecg := Ecg.new()
		for n in FASES.size():
			var org := Vector2i((n % COLUNAS) * CELULA.x, (n / COLUNAS) * CELULA.y)
			# `desloc` é o `base[0]` (`ctx+0xe4`): desloca painel E ECG juntos, como no EXE
			var desloc := org + Vector2i(4, 4) - DESTINO
			draw_rect(Rect2(org.x, org.y, CELULA.x, CELULA.y), Color.BLACK)
			if atlas != null:
				## O bloco HD já começa no x=128 do atlas SD (é a tpage `0x9B`), então o `u` entra
				## direto ×4; no SD é preciso somar o `+128`.
				var du := 0 if fator == 4 else U_TPAGE_9B
				draw_texture_rect_region(atlas,
					Rect2(DESTINO.x + desloc.x, DESTINO.y + desloc.y, PAINEL[2], PAINEL[3]),
					Rect2((PAINEL[0] + du) * fator, PAINEL[1] * fator,
						PAINEL[2] * fator, PAINEL[3] * fator))
			ecg.fase = int(FASES[n])
			ecg.desenhar(self, cond, 1.0, desloc)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_cond = clampi(int(args[0]), 0, 5)
	var t := Tira.new()
	## Mesma preferência do `menu_status.gd`: bloco HD primeiro (é onde as LISTRAS de fundo do
	## gráfico vêm em 4×), atlas do PS1 como queda.
	t.atlas = AssetIO.texture("MENU/status/hd/chrome_9b.webp")
	t.fator = 4
	if t.atlas == null:
		t.atlas = AssetIO.texture("MENU/status/stmain0u_p0.png")
		t.fator = 1
	if t.atlas == null:
		print("[ecg] falta o atlas — rode: python tools/status_assets.py --atlas")
	t.cond = _cond
	t.scale = Vector2(ZOOM, ZOOM)
	_no = t
	get_root().add_child(t)


func _process(_d: float) -> bool:
	_t += 1
	if _t < 4:
		return false
	var img := get_root().get_texture().get_image()
	var w: int = CELULA.x * COLUNAS * ZOOM
	var h: int = CELULA.y * int(ceil(float(FASES.size()) / COLUNAS)) * ZOOM
	img = img.get_region(Rect2i(0, 0, mini(w, img.get_width()), mini(h, img.get_height())))
	img.save_png(ProjectSettings.globalize_path("res://dev/_shot_ecg.png"))
	print("[ecg] salvo dev/_shot_ecg.png · condição %d · fases %s" % [_cond, FASES])
	return true
