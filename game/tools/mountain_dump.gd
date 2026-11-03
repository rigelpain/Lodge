extends SceneTree
## 大きな山の地面の高さを 2 m おきに JSON へ書く（上から見た等高線の図・断面の図を描く用）。main.tscn は読まないので軽い。
##   Godot --headless --path game -s res://tools/mountain_dump.gd -- --out=/path/heights.json

const World := preload("res://main.gd")
const Mountain := preload("res://mountain.gd")


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var x0 := -128.0
	var z0 := 100.0
	var step := 2.0
	var nx := 129
	var nz := 271
	var h := []
	var base := []   # 山を足す前（丘とくぼみと高台）
	for j in nz:
		for i in nx:
			var x := x0 + i * step
			var z := z0 + j * step
			h.append(snappedf(World.height(x, z), 0.01))
			base.append(snappedf(World.hill(x, z) + World.bowl(x, z), 0.01))
	var info := {"x0": x0, "z0": z0, "step": step, "nx": nx, "nz": nz, "h": h, "base": base, "top_z": Mountain.top_z}
	var consts: Dictionary = (Mountain as GDScript).get_script_constant_map()
	if consts.has("KICKERS"):
		info["kickers"] = consts["KICKERS"]
	var f := FileAccess.open(args.get("out", "/tmp/heights.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(info))
	print("書いた: ", args.get("out", "/tmp/heights.json"))
	quit()
