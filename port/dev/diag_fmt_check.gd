extends SceneTree
## diag_fmt_check: prova A/B do format string da HUD (screen.gd:494-510).
## A = string ATUAL (16 placeholders) com 15 args -> deve falhar e devolver a crua.
## B = string PATCHADA (3o %s da linha "trilha" removido) -> deve formatar sem erro.


func _initialize() -> void:
	var args_15: Array = [
		"R100", 1, 6, 0, 51.8,
		Vector3i(-21820, 0, -21977), 0, 1, "andar",
		0x001, "W ", 123, 60,
		"-", ""]
	var atual := ("sala %s  câmera %d/%d (attr %d, fov %.1f)\n"
		+ "pos PS1 %s  ângulo %d  ação %d  clipe %s\n"
		+ "pad 0x%03x [%s]  tick %d  fps %d\n"
		+ "trilha %s   %s   %s\n"
		+ "E ação · F1 hud · ...")
	var patchada := ("sala %s  câmera %d/%d (attr %d, fov %.1f)\n"
		+ "pos PS1 %s  ângulo %d  ação %d  clipe %s\n"
		+ "pad 0x%03x [%s]  tick %d  fps %d\n"
		+ "trilha %s   %s\n"
		+ "E ação · F1 hud · ...")
	print("[fmt] A) string ATUAL % 15 args (espere ERROR acima/abaixo):")
	var ra: String = atual % args_15
	print("[fmt]    resultado == crua (sem formatar)? %s" % (ra == atual))
	print("[fmt] B) string PATCHADA % 15 args:")
	var rb: String = patchada % args_15
	print("[fmt]    formatou? %s · primeira linha: %s" % [rb != patchada, rb.get_slice("\n", 0)])
	quit()
