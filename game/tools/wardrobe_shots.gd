extends SceneTree
## 2 階の衣装掛けと、人形の選び直しを撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/wardrobe_shots.gd -- --spawn=wardrobe --doll=kasa --dir=/path/shots [--kinds=robo,golem]
## 撮るもの:
##   rack.png        衣装掛けの前（F の案内。いま着ている人形のハンガーは空）
##   menu.png        F で開いた、人形を選ぶ画面
##   <人形>_fp.png   その人形に着替えた一人称（袖と手、左の袖の雪玉のストック、右上の小窓）
##   <人形>_tp.png   同じく三人称（うしろから、少し横に回って）
## 着替えは画面と同じく craft.gd の出来事 doll で送る（保存はしない。--doll で始めの人形を決める）

const Doll := preload("res://doll.gd")

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
	return args.get("dir", "/tmp/wardrobe_shots")


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


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(4.0)
	var p: CharacterBody3D = main.player
	var w: Node3D = main.wardrobe
	print("衣装掛け: ", w.global_position, " あなた: ", p.global_position, " 開ける: ", p.wardrobe_near())
	await _wait(1.5)
	await _shot("rack")
	main.wardrobe_ui.open()
	await _wait(1.2)
	await _shot("menu")
	main.wardrobe_ui.close()
	main.emotes.balls[p.id] = 3   # 左の袖のストックに雪玉を 3 つ
	var kinds: Array = Doll.KINDS if not args.has("kinds") else Array(String(args.kinds).split(","))
	# 衣装掛けに背を向けて、2 階の畳の方を向く（一人称の手の向こうが明るい）
	for k in kinds:
		main.craft.send({"kind": "doll", "who": p.id, "doll": k})
		await _wait(0.6)
		print(k, ": 人形=", p.doll.kind, " 背丈=", p.doll.height(), " 手=", p.hands.size())
		p.set_third(false)
		p.rotation.y = w.global_rotation.y + PI * 0.75
		await _wait(0.8)
		await _shot(k + "_fp")
		p.set_third(true)
		await _wait(1.2)
		await _shot(k + "_tp")
	p.set_third(false)
	quit()
