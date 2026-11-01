extends SceneTree
## 厨房の装置が調理のあいだ動く様子を撮る（確かめ用。cook_motion.gd・cook_tumble.gd）。
##   Godot --path game --resolution 1280x720 -s res://tools/cook_motion_shots.gd -- --bots=0 --no-pip --hud-idle=0 --dir=/path/shots
## 装置の前に置いたカメラ（画面の表示は隠す）で、調理を始めてからのコマ（12 コマで 1 秒）を撮る:
##   press_NN   プレス機（たい焼き）: 上の板が下りて押さえ、開く
##   fry_NN     乾燥機（たい焼きを揚げる）: 胴が回り、たい焼きと油の粒が踊る
##   iron_NN    アイロン台（ホットサンド）: アイロンが布の上を行き来する
##   ramen_NN   乾燥機（ラーメン）: 窓ごしに、汁・麺・具が回りながら踊る
##   drink_NN   衣類スチーマー（ココア）
## --only=press,iron などで、撮る装置を絞る（たい焼きの乾燥機はプレス機のあと）

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/cook_motion")


func _want(k: String) -> bool:
	return not args.has("only") or k in String(args.only).split(",")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _station(kind: String) -> Node:
	for st in main.stations:
		if st.kind == kind:
			return st
	return null


## 雪だるまの店で料理のペレットを買って手に持つ
func _buy(dish: String) -> void:
	var sh = main.snowman_shop
	p.global_position = sh.counter.global_position + sh.counter.global_basis.z * -1.6 + Vector3.UP * 0.1
	await _wait(0.3)
	main.food_ui.open()
	main.food_ui.select(preload("res://food.gd").ORDER.find(dish))
	main.food_ui.buy()
	main.food_ui.close()
	p.menu_open = false
	await _wait(0.3)


## 装置の前に立って入れ、カメラ（装置ごと）でコマ shots を撮る
func _cook(kind: String, prefix: String, shots: Array) -> void:
	var st := _station(kind)
	var dev: Node3D = st.get_parent()
	var slot: Node3D = dev.get_parent()
	p.global_position = dev.global_position + slot.global_basis.z * (2.2 if kind != "drink" else 1.8) + Vector3.UP * 0.1
	var d := dev.global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	await _wait(0.4)
	if p.station_near() != st:
		print("装置に届かない: ", kind, " 手に ", p.held())
		return
	st.use(p)
	var cam := Camera3D.new()
	cam.fov = 45.0
	root.add_child(cam)
	match kind:
		"dryer":   # 丸い戸の窓の正面から
			cam.look_at_from_position(st.drum_center() + st.front() * 4.0 + Vector3.UP * 0.25, st.drum_center())
		"iron":   # アイロン台の手前、斜め上から
			cam.look_at_from_position(dev.global_position + slot.global_basis.z * 3.4 + slot.global_basis.x * 0.6 + Vector3.UP * 2.6,
					dev.global_position + Vector3.UP * 1.0)
		_:
			cam.look_at_from_position(dev.global_position + slot.global_basis.z * 4.2 + slot.global_basis.x * 1.4 + Vector3.UP * 2.3,
					dev.global_position + Vector3.UP * 1.3)
	cam.current = true
	p.visible = false
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var start: int = st._k
	for at in shots:   # 調理を始めてからのコマ（入れてから飛ぶ 6 コマを含む）
		while st._k - start < int(at):
			await process_frame
		await _shot("%s_%02d" % [prefix, int(at)])
	while st.busy():
		await process_frame
	cam.queue_free()
	p.visible = true
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = true
	await _wait(0.6)
	print(kind, " のあと 手に ", p.held())


func _run() -> void:
	await _wait(3.0)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	p = main.player
	p.menu_open = false
	main.emotes.balls[p.id] = 20
	if _want("press") or _want("fry"):
		await _buy("taiyaki")
		await _cook("press", "press", [7, 8, 9, 10, 12, 16, 19, 20, 21])
		if _want("fry"):
			await _cook("dryer", "fry", [9, 12, 15, 18, 21, 30])
	if _want("iron"):
		await _buy("hotsand")
		await _cook("iron", "iron", [7, 10, 12, 14, 16, 18, 20, 24, 60, 64])
	if _want("ramen"):
		await _buy("ramen")
		await _cook("dryer", "ramen", [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 40])
	if _want("drink"):
		await _buy("cocoa")
		await _cook("drink", "drink", [10, 30, 45])
	quit()
