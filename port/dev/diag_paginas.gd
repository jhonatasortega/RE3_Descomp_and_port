extends SceneTree
## Vira todas as páginas de um documento e reporta qual arquivo cada página resolve.
func _initialize() -> void:
	var st := GameState.new()
	st.novo_jogo()
	for id: int in range(0x85, 0xa4):
		st.marcar_arquivo_lido(id)
	var a := MenuArquivo.new()
	get_root().add_child(a)
	a.carregar(st)
	a.abrir()
	print("[pg] %d documentos na lista" % a.docs.size())
	a.sel = 0
	a.confirmar()                            ## abre o documento
	var doc: Dictionary = a.docs[a.sel]
	print("[pg] doc%d n_pages=%d text_pages=%s" % [doc.get("doc"), doc.get("n_pages"),
		str(doc.get("text_pages"))])
	for i in 12:
		var p: int = a.pagina
		var rel := "FILE/capa_%03d.png" % int(doc.get("cover_page", 1)) if p == 0 else ""
		if p > 0:
			var tp: Array = doc.get("text_pages", [])
			rel = "FILE/pag_%03d.png" % int(tp[p - 1]) if p - 1 < tp.size() else "(fora da lista)"
		print("[pg]   pagina %d -> %s · existe=%s" % [p, rel, AssetIO.exists(rel)])
		a.virar_pagina(1)
		if a.pagina == p:
			print("[pg]   parou em %d" % p)
			break
	quit(0)
