extends SceneTree
## Prova VISUAL da caixa de mensagem (`res://present/mensagem.gd`).
##
## Monta uma tira 320×240 por caso, com a mesma geometria do jogo (34,185 / 14,173), a fonte do
## jogo e a marcação do dado — inclusive a página, a cor `{c:1}`, a seta ▼ e o prompt SIM/NÃO.
## Salva `port/dev/_shot_mensagem.png` (nada de PNG na raiz do `port/`).
##
##     godot --rendering-driver opengl3 --path port --script res://dev/shot_mensagem.gd
##     godot ... --script res://dev/shot_mensagem.gd -- R110      # só uma sala

const ZOOM := 3                             ## 3× de 320×240 por quadro da tira
const TELA := Vector2i(320, 240)
const COLUNAS := 2

## Os casos que interessam ver: mensagem de sala, item pegado, porta trancada, escada, prompt.
const CASOS := [
	["sala", "R100", 0, "AOT sce 4 — exame de cenário (R100[0])"],
	["sala", "R110", 0, "duas páginas (o {p} do dado) + seta ▼"],
	["sala", "R110", 1, "prompt de 2 opções ({sn} + {op})"],
	["item_pego", "", 0x21, "pegar item — sistema[6] com {i:00} verde"],
	["porta", "R101", 1, "porta trancada — prompt[20] (Key_Type 0x73)"],
	["porta", "R119", 1, "porta trancada — prompt[22] (Key_Type 0x75)"],
	["prompt", "", 10, "escada — prompt[10] 'Quer subir?'"],
	["sistema", "", 0, "sistema[0] 'quer pegar?' + Sim/Não da mini-pool"],
]

var _t := 0
var _filtro := ""


class Tira:
	extends Node2D
	var casos: Array = []

	func _draw() -> void:
		var n := 0
		for c: Array in casos:
			var org := Vector2i((n % COLUNAS) * TELA.x, (n / COLUNAS) * TELA.y)
			draw_rect(Rect2(org.x, org.y, TELA.x, TELA.y), Color8(24, 24, 32))
			var cx := Mensagem.new()
			cx.fundo_visivel = true            # só na prova visual: marca a caixa
			var ok := _abrir(cx, c)
			if ok:
				# revela tudo e, quando há mais de uma página, mostra a ÚLTIMA (é onde estão as
				# opções do prompt) — mas guarda um quadro com a seta ▼ na primeira.
				cx.acao()
				if int(c[2]) == 0 and String(c[0]) == "sala" and cx.total_paginas() > 1:
					pass                       # fica na página 1 para a seta ▼ aparecer
				elif cx.total_paginas() > 1:
					while cx.total_paginas() > cx.pagina() + 1:
						cx.acao()
						cx.acao()


				cx.desenhar(self, org)
			Texto.desenhar(self, String(c[3]).substr(0, 44), Vector2i(org.x + 6, org.y + 6),
				0, Color8(0xff, 0xd0, 0x60))
			Texto.desenhar(self, cx.resumo().substr(0, 48), Vector2i(org.x + 6, org.y + 22),
				0, Color8(0x80, 0xc0, 0xff))
			cx.free()
			n += 1

	func _abrir(cx: Mensagem, c: Array) -> bool:
		match String(c[0]):
			"sala":
				return cx.mostrar_da_sala(String(c[1]), int(c[2]))
			"prompt":
				return cx.mostrar_prompt(int(c[2]))
			"sistema":
				return cx.mostrar_sistema(int(c[2]), 0x21)
			"item_pego":
				return cx.mostrar_item_pego(int(c[2]))
			"porta":
				return cx.mostrar_da_porta_da_sala(String(c[1]), int(c[2]), false)
		return false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_filtro = String(args[0])
	var casos: Array = []
	for c: Array in CASOS:
		if _filtro == "" or String(c[1]) == _filtro:
			casos.append(c)
	if casos.is_empty():
		casos = CASOS
	var t := Tira.new()
	t.casos = casos
	t.scale = Vector2(ZOOM, ZOOM)
	get_root().add_child(t)


func _process(_d: float) -> bool:
	_t += 1
	if _t < 4:
		return false
	var n: int = (get_root().get_child(0) as Tira).casos.size()
	var img := get_root().get_texture().get_image()
	var w: int = TELA.x * COLUNAS * ZOOM
	var h: int = TELA.y * int(ceil(float(n) / COLUNAS)) * ZOOM
	img = img.get_region(Rect2i(0, 0, mini(w, img.get_width()), mini(h, img.get_height())))
	img.save_png(ProjectSettings.globalize_path("res://dev/_shot_mensagem.png"))
	print("[mensagem] salvo dev/_shot_mensagem.png · %d casos" % n)
	quit(0)
	return true
