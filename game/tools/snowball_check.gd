extends SceneTree
## しゃがんで F で雪玉を丸められるかを、一人称と三人称で確かめる（確かめ用）。キーは本物の入力のイベントで流す。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/snowball_check.gd -- --bots=0 --no-sound --no-pip [--dir=/path/shots]
## 坂のふもとの雪の上に立ち、左 Ctrl を押したまま F。2 秒後に雪玉を持っているか。
## 一人称は雪面を見下ろしたときだけ（まっすぐ前ではできない）。三人称はカメラの向きによらず、人形の足もとの少し先の雪面で
## そのあと、持てる数: 6 回丸めても 5 つまで。左クリックで 2 つ投げると 3 つ。丸めている途中に雪玉が当たると、その玉はできない

var args := {}
var main: Node3D
var p: CharacterBody3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


## 窓から目が離れると設定が開くことがある（開いているとキーが効かない）。毎コマ閉じる
func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _try(third: bool, pitch: float, name: String, want := true) -> void:
	main.emotes.balls.erase(p.id)
	p.set_third(third)
	var at := Vector3(4.0, 0, 44.0)
	at.y = main.height(at.x, at.z) + 0.1
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = 0.0
	p.set("_pitch", pitch)
	await create_timer(0.6).timeout
	await _key(KEY_CTRL, true)
	await create_timer(0.4).timeout
	await _key(KEY_F, true)
	await _key(KEY_F, false)
	await create_timer(2.2).timeout
	var ok: bool = p.ball_count() > 0
	print("%s: 雪玉 %s%s" % [name, "できた" if ok else "できない", "" if ok == want else "（ちがう）"])
	if ok != want:
		fails += 1
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(args["dir"])
		root.get_texture().get_image().save_png(String(args["dir"]).path_join(name + ".png"))
	await _key(KEY_CTRL, false)
	await create_timer(0.6).timeout


func _want(name: String, got: int, want: int) -> void:
	print("%s: %d（%d のはず）%s" % [name, got, want, "" if got == want else "　ちがう"])
	if got != want:
		fails += 1


func _click(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _make_one() -> void:
	await _key(KEY_F, true)
	await _key(KEY_F, false)
	await create_timer(2.2).timeout


## 持てる数・投げて減る・丸めている途中に当たる
func _stock() -> void:
	main.emotes.balls.erase(p.id)
	p.set_third(false)
	p.set("_pitch", -0.6)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await create_timer(0.4).timeout
	await _key(KEY_CTRL, true)
	await create_timer(0.4).timeout
	for i in 6:
		await _make_one()
	_want("6 回丸める", p.ball_count(), 5)
	await _key(KEY_CTRL, false)
	await create_timer(0.6).timeout
	for i in 2:
		await _click(true)
		await create_timer(0.5).timeout
		await _click(false)
		await create_timer(0.9).timeout
	_want("2 つ投げる", p.ball_count(), 3)
	# 丸めている途中に当たる: その玉はできない
	await _key(KEY_CTRL, true)
	await create_timer(0.4).timeout
	await _key(KEY_F, true)
	await _key(KEY_F, false)
	await create_timer(0.5).timeout
	var by: Node3D = preload("res://snowball.gd").new()   # 誰か（番号なし）の雪玉
	main.emotes.ball_hit_person(by, p.id, p.global_position + Vector3.UP, Vector3.FORWARD)
	await create_timer(2.0).timeout
	_want("丸めている途中に当たる", p.ball_count(), 3)
	by.free()
	await _key(KEY_CTRL, false)


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	await _try(false, -0.6, "1_一人称_見下ろす")
	await _try(true, -0.6, "2_三人称_見下ろす")
	await _try(true, 0.0, "3_三人称_まっすぐ")
	await _try(true, 0.5, "4_三人称_見上げる")
	await _try(false, 0.0, "5_一人称_まっすぐ（雪面を見ていないので、できないのが正しい）", false)
	await _stock()
	print("思ったとおりでない: %d" % fails)
	quit(1 if fails > 0 else 0)
