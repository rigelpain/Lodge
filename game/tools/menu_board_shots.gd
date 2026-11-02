extends SceneTree
## 厨房の装置の上の品書きの板（menu_board.gd）の見え方（確かめ用）。画面（CanvasLayer）は全部隠して撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/menu_board_shots.gd -- --dir=/path/shots
## --flat で板の絵（flat_<装置>.png）も書き出す。--only=board_enter,board_dryer で撮る目線を絞る
## 場所はロッジの座標（lodge/dims.py の x, y, z。Godot ではロッジの (x, z, -y)）。目の高さは床（FL1 0.45）+ 1.6。
## 板はロッジの y 9.0、高さ 4.0〜5.4。装置の x は プレス機 0.3・アイロン台 3.2・乾燥機 6.7・スチーマー 9.5

const LOOKS := [
	["board_enter", Vector3(4.6, 0.5, 2.05), Vector3(4.9, 9.0, 3.4)],       # 食堂から厨房へ向かう目線（板 4 枚と装置）
	["board_counter", Vector3(-1.6, 4.4, 2.05), Vector3(2.5, 9.0, 3.8)],    # 雪だるまの番台の前から
	["board_press", Vector3(0.3, 5.0, 2.05), Vector3(0.3, 9.0, 4.2)],       # 板の前（装置の前に立って見上げる）
	["board_iron", Vector3(3.2, 5.0, 2.05), Vector3(3.2, 9.0, 4.2)],
	["board_dryer", Vector3(6.7, 5.0, 2.05), Vector3(6.7, 9.0, 4.2)],
	["board_drink", Vector3(9.5, 5.0, 2.05), Vector3(9.5, 9.0, 4.2)],
]

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/menu_board_shots")


func _hide_ui() -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false


func _run() -> void:
	await create_timer(4.0).timeout
	var lodge := main.get_node("Lodge") as Node3D
	var board := lodge.find_child("MenuBoard", true, false)
	if board and args.has("flat"):
		for k in ["press", "iron", "dryer", "drink"]:
			var img: Image = await board.render(k)
			if img:
				img.save_png(_dir().path_join("flat_%s.png" % k))
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	var only: String = args.get("only", "")
	for l in LOOKS:
		if only != "" and not (l[0] as String) in only.split(","):
			continue
		var eye: Vector3 = l[1]
		var at: Vector3 = l[2]
		cam.global_position = lodge.to_global(Vector3(eye.x, eye.z, -eye.y))
		cam.look_at(lodge.to_global(Vector3(at.x, at.z, -at.y)))
		cam.current = true
		cam.reset_physics_interpolation()
		await create_timer(0.3).timeout
		_hide_ui()
		await process_frame
		await process_frame
		var path := _dir().path_join(l[0] + ".png")
		root.get_texture().get_image().save_png(path)
		print("保存: ", path)
	quit()
