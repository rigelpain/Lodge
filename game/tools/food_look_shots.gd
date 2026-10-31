extends SceneTree
## 雪だるまの食べ物屋の見渡し（確かめ用）。画面（CanvasLayer）は全部隠して、決まった所から撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/food_look_shots.gd -- --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y。Godot ではロッジの (x, 0, -y)）。

const LOOKS := [
	["food_counter", Vector3(-2.4, 4.6, 1.7), Vector3(-1.8, 8.6, 1.3)],     # 雪だるまの番台（客の側から）
	["food_kitchen", Vector3(4.0, 1.5, 3.6), Vector3(4.0, 10.0, 1.2)],      # 厨房の装置の並び（冷蔵庫 → プレス機 → アイロン台 → 乾燥機 → スチーマー）
	["food_wide", Vector3(-6.0, 1.0, 3.4), Vector3(0.5, 9.5, 1.0)],         # 炉の右を斜めから
	["food_drink", Vector3(8.0, 5.5, 2.4), Vector3(9.5, 10.0, 1.6)],        # 衣類スチーマー
	["food_fridge", Vector3(-3.5, 5.0, 2.2), Vector3(-1.6, 10.0, 1.6)],     # 左へ開く冷蔵庫の扉
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
	return args.get("dir", "/tmp/food_look_shots")


func _hide_ui() -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false


func _shot(name: String) -> void:
	_hide_ui()
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _run() -> void:
	await create_timer(4.0).timeout
	var lodge := main.get_node("Lodge") as Node3D
	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	for l in LOOKS:
		var eye: Vector3 = l[1]
		var at: Vector3 = l[2]
		cam.global_position = lodge.to_global(Vector3(eye.x, eye.z, -eye.y))
		cam.look_at(lodge.to_global(Vector3(at.x, at.z, -at.y)))
		cam.current = true
		await create_timer(0.3).timeout
		await _shot(l[0])
	quit()
