extends SceneTree
## 雪だるまの食べ物屋を、買う → 調理 → 受け取るまで通して撮る（確かめ用。design/snowman-food/）。
##   Godot --path game --resolution 1280x720 -s res://tools/food_flow_shots.gd -- --bots=0 --no-pip --dir=/path/shots [--third]
## 撮るもの:
##   01 番台の前（ヒント）  02 売り場の画面（たい焼きを選んだ）  03 買った（雪だるまがベルを振り、ペレットが跳ぶ）
##   10〜 プレス機（入れる・押す）→ 乾燥機（揺れる・湯気）→ 手にたい焼き
##   30〜 ココアを買って、衣類スチーマー（ふたが開く・泡・ホースのふくらみ・ぷしゅっ・棚のカップ）→ 手にココア
## --third で三人称から撮る（人形の手の物も見る）。--devcam で、調理のあいだは装置に寄ったカメラ（画面の表示は隠す）

var args := {}
var main: Node3D
var p: CharacterBody3D
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/food_flow")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		if not main.food_ui.is_open:
			p.menu_open = false
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _face(at: Vector3, pitch := -0.2) -> void:
	var d := at - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", pitch)


## 装置の前（食堂の側）に立って、装置を向く
func _stand_at(st: Node, dist := 2.0, side := 0.0) -> void:
	var dev: Node3D = st.get_parent()
	var slot: Node3D = dev.get_parent()
	p.global_position = dev.global_position + slot.global_basis.z * dist + slot.global_basis.x * side + Vector3.UP * 0.1
	_face(dev.global_position + Vector3.UP * 1.0, -0.25)


func _station(kind: String) -> Node:
	for st in main.stations:
		if st.kind == kind:
			return st
	return null


## 手の物を、その装置で調理して、受け取るまで撮る
func _cook(kind: String, prefix: String, shots: Array) -> void:
	var st := _station(kind)
	_stand_at(st, 2.2 if kind != "drink" else 1.8, 0.0)
	await _wait(0.4)
	print("near ", kind, " ", p.station_near() == st, " held ", p.held())
	if p.station_near() != st:
		print("装置に届かない: ", kind)
		return
	await _shot("%s_0_near" % prefix)
	st.use(p)
	var cam: Camera3D = null
	if args.has("devcam"):
		var dev: Node3D = st.get_parent()
		var slot: Node3D = dev.get_parent()
		cam = Camera3D.new()
		cam.fov = 50.0
		root.add_child(cam)
		cam.look_at_from_position(dev.global_position + slot.global_basis.z * 4.6 + slot.global_basis.x * 1.2 + Vector3.UP * 2.4,
				dev.global_position + Vector3.UP * 1.3)
		cam.current = true
		p.visible = false
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
	var start: int = st._k
	for at in shots:   # 調理を始めてからのコマ（12 コマで 1 秒）
		while st._k - start < int(at):
			await process_frame
		await _shot("%s_%02d" % [prefix, int(at)])
	while st.busy():
		await process_frame
	if cam:
		cam.queue_free()
		p.visible = true
		for c in root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = true
	await _wait(0.6)
	await _shot("%s_9_got" % prefix)
	print("手に ", p.held())


func _run() -> void:
	await _wait(3.0)
	p = main.player
	p.set_third(args.has("third"))   # 既定は一人称（保存してある設定によらず）
	var hub = main.emotes
	hub.balls[p.id] = 5   # 雪玉を 5 つ持たせる
	# 01 番台の前
	var sh = main.snowman_shop
	p.global_position = sh.counter.global_position + sh.counter.global_basis.z * -1.6 + Vector3.UP * 0.1
	_face(sh.counter.global_position + Vector3.UP * 0.9, -0.2)
	await _wait(0.6)
	print("food_near ", p.food_near())
	await _shot("01_counter")
	# 02 売り場の画面
	main.food_ui.open()
	main.food_ui.select(1)   # たい焼き
	await _wait(0.4)
	await _shot("02_ui_taiyaki")
	main.food_ui.buy()
	await _wait(0.15)
	await _shot("03_bought")
	main.food_ui.close()
	await _wait(0.5)
	await _shot("04_after")
	print("手に ", p.held(), " 雪玉 ", hub.balls_of(p.id))
	# 10〜 プレス機 → 乾燥機
	await _cook("press", "10_press", [3, 8, 13, 19, 30])
	await _cook("dryer", "20_dryer", [8, 20, 40])
	# 30〜 ココアを買ってスチーマー
	p.global_position = sh.counter.global_position + sh.counter.global_basis.z * -1.6 + Vector3.UP * 0.1
	_face(sh.counter.global_position + Vector3.UP * 0.9, -0.2)
	await _wait(0.3)
	main.food_ui.open()
	main.food_ui.select(15)   # ココア
	main.food_ui.buy()
	await _wait(0.2)
	await _shot("30_ui_cocoa")
	main.food_ui.close()
	await _cook("drink", "40_drink", [8, 10, 16, 30, 33, 42, 55, 70])
	# アイロン台も一度（ホットサンド）
	p.global_position = sh.counter.global_position + sh.counter.global_basis.z * -1.6 + Vector3.UP * 0.1
	main.food_ui.open()
	main.food_ui.select(6)
	main.food_ui.buy()
	main.food_ui.close()
	await _cook("iron", "50_iron", [10, 30])
	print("雪玉 ", hub.balls_of(p.id), " 持ち物 ", main.craft.bag(p.id))
	quit()
