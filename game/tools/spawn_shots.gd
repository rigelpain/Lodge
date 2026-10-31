extends SceneTree
## 始める所（--spawn=inside / shop / lodge）の画面と、ロッジの 1 階を見渡す絵を撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/spawn_shots.gd -- --spawn=inside --dir=/path/shots
## 設定の画面（窓から目が離れると開く）は閉じたまま撮る。--look を付けると、決まった所からの見渡しも撮る。
## 見渡しの場所はロッジの座標（lodge/dims.py の x, y。Godot ではロッジの (x, 0, -y)）。

## 見渡し: [名前, 目の所 (x, y, 高さ), 見る所 (x, y, 高さ)]
const LOOKS := [
	["look_entrance", Vector3(-13.4, -11.5, 1.6), Vector3(-10.4, 10.0, 1.4)],   # 入口から正面の炉
	["look_hearth", Vector3(-10.4, 2.0, 4.2), Vector3(-10.4, 11.0, 0.6)],       # 炉のまわり
	["look_kitchen", Vector3(3.5, 2.5, 3.0), Vector3(3.5, 10.5, 1.2)],          # 炉の右の厨房
	["look_machine", Vector3(-9.0, -3.4, 3.0), Vector3(-19.0, -4.5, 1.0)],      # 南西の隅のミシンと売り子
	["look_hall", Vector3(20.0, -11.0, 4.6), Vector3(-6.0, 4.0, 0.5)],          # 南東の隅から 1 階ぜんぶ
	["look_bandai_seller", Vector3(-14.6, -8.0, 1.7), Vector3(-18.0, -8.7, 1.1)],   # おじいさんの番台（客の側から）
	["look_bandai_snowman", Vector3(-2.4, 4.8, 1.7), Vector3(-1.6, 8.6, 1.5)],      # 雪だるまの番台（客の側から）
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
	return args.get("dir", "/tmp/spawn_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _run() -> void:
	await create_timer(4.0).timeout
	await _shot("spawn_" + str(args.get("spawn", "start")))
	if args.has("look"):
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
			await create_timer(0.3).timeout
			await _shot(l[0])
	quit()
