extends SceneTree
## Detalhe dos itens de UMA sala: opcode, payload, objeto do `0x7f`, brilho e se há malha.
## env: SALA=R100
func _initialize() -> void:
	var sala := OS.get_environment("SALA")
	if sala == "":
		sala = "R100"
	var w := World.new()
	if not w.carregar(sala):
		print("[is] %s nao carregou" % sala)
		quit(1)
		return
	print("[is] %s · %d objetos do 0x7f · %d AOTs" % [
		sala, w.vm.objetos.size(), w.vm.aots.size()])
	for k in w.vm.objetos.keys():
		var o: ObjetoSala = w.vm.objetos[k]
		print("[is]   om %2d: %s" % [k, o.resumo()])
	for a: Aot in w.vm.itens():
		var obj := w.objeto_do_item(a)
		var malha := "OMODEL/%s/om%d.glb" % [sala, a.item_om]
		print("[is]   item op=0x%02x aot=%2d id=0x%02x qtd=%d flag=%d om=%d iflags=0x%02x%s · area=%s · obj=%s · glb=%s" % [
			a.opcode, a.id, a.item_id, a.item_qtd, a.item_flag, a.item_om, a.item_flags,
			"  BRILHO(var %d)" % ((a.item_flags & 0x60) >> 5) if a.tem_brilho() else "",
			("box %s" % a.box) if a.kind == Aot.Kind.BOX else ("quad %s" % a.quad),
			obj.resumo() if obj != null else "NENHUM",
			"sim" if AssetIO.exists(malha) else "NAO"])
	quit(0)
