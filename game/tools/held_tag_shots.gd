extends SceneTree
## 畳んだソリの包みを手に持ったときの名札の見え方を撮る（確かめ用）。名札の柄・大きさ・布の色を変えて、
## 一人称（右下の小窓つき）と三人称で撮る。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/held_tag_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots

var args := {}
var main: Node3D

const CASES := [
	{"kind": "folded", "sled": "mid", "fabric": "navy", "tag": 1},
	{"kind": "folded", "sled": "small", "fabric": "mustard", "tag": 4},
	{"kind": "folded", "sled": "large", "fabric": "plum", "tag": 10},
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/held"))
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path: String = args.get("dir", "/tmp/held").path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("撮った: ", path)


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	p.set("_pitch", -0.1)
	for i in CASES.size():
		c.bags[p.id] = [CASES[i].duplicate()]
		c.send({"kind": "hand", "who": p.id, "slot": 0})
		p.set_third(false)
		await create_timer(1.2).timeout
		await _shot("%d_fp_tag%d" % [i + 1, CASES[i].tag])
		if args.has("debug"):
			var sc = main.get("self_cam")
			var h: Node3D = sc._held if sc else null
			print("小窓の手: ", h, " ", h.global_position if h else "", " 見える=", h.is_visible_in_tree() if h else "", " 人形=", main.player.doll.global_position, " 球=", main.player.doll._ball.visible)
		await create_timer(0.5).timeout
		await _shot("%d_fp_tag%d_turn" % [i + 1, CASES[i].tag])   # 窓の図が回っている
		p.set_third(true)
		await create_timer(0.8).timeout
		await _shot("%d_third_tag%d" % [i + 1, CASES[i].tag])
	quit()
