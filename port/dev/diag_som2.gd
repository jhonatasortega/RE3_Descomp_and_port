extends SceneTree


func _init() -> void:
	var p := "res://data/re3_se.json"
	print("existe: ", FileAccess.file_exists(p))
	var txt := FileAccess.get_file_as_string(p)
	print("bytes lidos: ", txt.length())
	var j := JSON.new()
	var err := j.parse(txt)
	print("parse err: ", err, " msg: ", j.get_error_message(), " linha ", j.get_error_line())
	var d: Variant = j.data
	print("tipo: ", typeof(d))
	if d is Dictionary:
		print("chaves: ", (d as Dictionary).keys())
	print("--- AssetIO.json ---")
	var v: Variant = AssetIO.json("re3_se.json")
	print("tipo AssetIO: ", typeof(v))
	print("--- Sfx.carregar() ---")
	var s := Sfx.new()
	print("carregar: ", s.carregar(), " pronto: ", s.pronto())
	quit()
