extends SceneTree
## 山男（mountain_man.gd）と、山の道具の売り場（mountain_ui.gd）を撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/mountain_shots.gd -- --spawn=mountain --dir=/path/shots [--shelf-all]
## 撮るもの:
##   man_front.png・man_quarter.png・man_side.png・man_back.png  山男を 4 つの向きから（棚も入る）
##   place.png       玄関（風除室）を出た所から見た、山男と棚と山への道
##   hint.png        山男の前（F の案内）
##   menu.png        F で開いた売り場（何も選んでいない）
##   menu_pick.png   1 つ目の品物を選んだ（--shelf-all のときだけ。売っていない品目は選べない）
##   bought.png      買ったあと（持ち物の列に入り、山男がうなずく。--shelf-all のとき）
## 買えたか・財布が減ったか・売っていない品目が断られたかを、ログに出す

const Goods := preload("res://mountain_goods.gd")

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
	return args.get("dir", "/tmp/mountain_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	if main and main.craft_ui and main.craft_ui.gear_open:   # 撮っているあいだに窓へ入ったキー（I）で開いた装備の画面は閉じる
		main.craft_ui.close_gear()
	return false


## 山男の前（話しかけられる所）に立って、山男を向く
func _stand_front() -> void:
	var mm: Node3D = main.mountain_man
	var at := mm.to_global(Vector3(0, 0.1, -1.9))
	main.player.global_position = at
	main.player.velocity = Vector3.ZERO
	var to := mm.global_position
	main.player.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _look_shot(name: String, from: Vector3, to: Vector3, fov := 45.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	main.add_child(cam)
	cam.look_at_from_position(from, to)
	cam.make_current()
	main.player.doll.visible = false
	await _wait(0.6)
	await _shot(name)
	cam.queue_free()
	main.player.doll.visible = true
	main.player.cam.make_current()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	await _wait(2.0)
	var mm: Node3D = main.mountain_man
	if mm == null:
		print("山男がいない")
		quit(1)
		return
	var c := mm.global_position + Vector3.UP * 1.1
	# 4 つの向き（山男の前は -Z）。棚が左手（+X）の側に入るよう、少し引く
	for v in [["man_front", Vector3(0.35, 0.25, -4.2)], ["man_quarter", Vector3(2.6, 0.35, -3.4)], ["man_side", Vector3(-4.0, 0.25, -0.3)],
			["man_back", Vector3(-0.8, 0.35, 4.0)]]:
		await _look_shot(v[0], mm.to_global(v[1]) + Vector3.UP * 1.1, c + mm.global_basis.x * 0.4, 42.0)
	# 玄関を出た所（ロッジの座標 (PATH_X, 18)、目の高さ）から
	var lodge: Node3D = main.get_node("Lodge")
	var door := lodge.to_global(Vector3(main.PATH_X, 0, 18.0))
	door.y = main.height(door.x, door.z) + 1.6
	await _look_shot("place", door, mm.global_position + Vector3.UP * 0.9, 60.0)
	# 山男の前で F の案内
	_stand_front()
	await _wait(1.0)
	await _shot("hint")
	print("話しかけられる: ", main.player.mountain_near())
	var who: int = main.player.id
	var ui = main.mountain_ui
	ui.open()
	await _wait(0.8)
	await _shot("menu")
	# 売っていない品目は、ホストが断る
	var off := Goods.SHELF[0].item as Dictionary
	if not Goods.sold(off.kind):
		print("売っていない品目を買う: ", main.craft.send({"kind": "buy", "who": who, "item": off.duplicate()}), "（false なら断った）")
	if Goods.sold(off.kind):
		ui.select(0)
		await _wait(0.4)
		await _shot("menu_pick")
		var before: int = main.craft.wallet(who)
		var ok: bool = ui.buy()
		print("買う: ", ok, "  財布 ", before, " → ", main.craft.wallet(who), "  持ち物 ", main.craft.bag(who).filter(func(x): return not x.is_empty()))
		await _wait(0.5)
		await _shot("bought")
		ui.close()
		await _wait(0.6)
		await _shot("bought_closed")
	quit(0)
