extends SceneTree
## Prova do BRILHO: roda a R100 (a Chave do armazém é o único item com `iflags & 0x80`) por vários
## ticks e salva um PNG a cada quadro do cintilar, mais um relatório do estado da máquina.
## Se o brilho estiver certo, os PNGs mostram a estrela de 4 pontas aparecendo e sumindo.
##
## env: BRILHO_SALA=R100 · BRILHO_TICKS=140
var _cena: Node
var _t := 0
var _salvos := 0
var _antes := false
var _apagado := false


func _initialize() -> void:
	var pk: PackedScene = load("res://scenes/game.tscn")
	_cena = pk.instantiate()
	_cena.set("occlusion_mode", Occlusion.Modo.DESLIGADA)
	get_root().add_child(_cena)


func _process(_d: float) -> bool:
	_t += 1
	if _t == 4:
		var sala := OS.get_environment("BRILHO_SALA")
		if sala == "":
			sala = "R100"
		if not _cena.call("carregar_sala", sala):
			print("[br] %s nao carregou" % sala)
			return true
		var esp: Object = _cena.get("esp")
		print("[br] %s: %d fonte(s) de brilho" % [sala, (esp.get("fontes") as Array).size()])
		for f: Object in esp.get("fontes"):
			print("[br]   fonte em %s · intervalo inicial %d quadros" % [
				f.get("mundo"), f.get("intervalo")])
		return false
	if _t < 5:
		return false
	var esp2: Object = _cena.get("esp")
	var fontes: Array = esp2.get("fontes")
	if fontes.is_empty():
		print("[br] sem fonte de brilho nesta sala")
		return true
	var f0: Object = fontes[0]
	var vivo: int = f0.get("quadro")
	if _t % 20 == 0:
		var g: Node = _cena.get_node_or_null("/root/Game")
		print("[br] tick %d: estado=%d contador=%d intervalo=%d quadro=%d (clock=%d)" % [
			_t, f0.get("estado"), f0.get("contador"), f0.get("intervalo"), vivo,
			g.get("clock").get("frame") if g != null and g.get("clock") != null else -1])
	if vivo >= 0:
		var n: Node2D = f0.get("no")
		print("[br]   sprite: visivel=%s pos=%s escala=%s tex=%s pai_visivel=%s" % [
			n.visible, n.position, n.scale,
			(n.texture as Texture2D).get_size() if n.texture != null else "nula",
			(_cena.get("esp") as CanvasItem).visible])
	if vivo < 0 and not _apagado and _salvos > 0:
		# mesmo recorte SEM o cintilar: separa "o sprite escureceu" de "a malha está escura"
		var n3: Node2D = f0.get("no")
		var img0 := get_root().get_texture().get_image()
		var r0 := Rect2i(int(n3.position.x) - 80, int(n3.position.y) - 80, 160, 160)
		r0 = r0.intersection(Rect2i(0, 0, img0.get_width(), img0.get_height()))
		if r0.size.x > 8:
			var c0 := img0.get_region(r0)
			c0.resize(r0.size.x * 4, r0.size.y * 4, Image.INTERPOLATE_NEAREST)
			c0.save_png(ProjectSettings.globalize_path("res://_shot_brilho_apagado_zoom.png"))
			print("[br] tick %d: recorte com o brilho APAGADO salvo" % _t)
			_apagado = true
	if vivo >= 0 and _salvos < 4:
		var img := get_root().get_texture().get_image()
		var nome := "_shot_brilho_q%d.png" % vivo
		img.save_png(ProjectSettings.globalize_path("res://%s" % nome))
		# recorte ampliado onde o sprite está, que é onde se vê se ele saiu
		var n2: Node2D = f0.get("no")
		var r := Rect2i(int(n2.position.x) - 80, int(n2.position.y) - 80, 160, 160)
		r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		if r.size.x > 8:
			var corte := img.get_region(r)
			corte.resize(r.size.x * 4, r.size.y * 4, Image.INTERPOLATE_NEAREST)
			corte.save_png(ProjectSettings.globalize_path("res://_shot_brilho_q%d_zoom.png" % vivo))
		print("[br] tick %d: quadro %d do cintilar -> %s (contador=%d intervalo=%d)" % [
			_t, vivo, nome, f0.get("contador"), f0.get("intervalo")])
		_salvos += 1
	if vivo >= 0 and not _antes:
		print("[br] tick %d: PISCOU (nasceu o cintilar)" % _t)
	_antes = vivo >= 0
	var limite := int(OS.get_environment("BRILHO_TICKS")) if OS.get_environment("BRILHO_TICKS") != "" else 140
	if _t > limite:
		print("[br] fim: %d PNG(s) salvos" % _salvos)
		return true
	return false
