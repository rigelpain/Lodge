extends SceneTree
## 二本指スクロール（パン）とホイールで、手に持つ物を前・次へ替える確かめ用。数字を出して、持ち替えるたびに一人称で撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/scroll_hand_check.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## パンは Mac のひと撫でをまねて送る: 指で撫でる 8 回（だんだん速く、また遅く）→ 動かない知らせ → 指を離したあとの慣性 40 回
## （だんだん弱く）→ 動かない知らせ。時刻で区切るので --fixed-fps はつけない（本当の時間で流す）

const ITEMS := [
	{"kind": "folded", "sled": "mid", "fabric": "navy", "tag": 1},
	{"kind": "fabric", "fabric": "plum"},
	{"kind": "folded", "sled": "small", "fabric": "mustard", "tag": 4},
]

var args := {}
var main: Node3D
var _fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/scroll_hand"))
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path: String = args.get("dir", "/tmp/scroll_hand").path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("撮った: ", path)


func _hand() -> int:
	return int(main.craft.hands.get(main.player.id, -1))


func _pan(d: Vector2) -> void:
	var ev := InputEventPanGesture.new()
	ev.delta = d
	ev.position = root.get_visible_rect().size * 0.5   # マウスをつかんでいるあいだのカーソルは画面の真ん中
	Input.parse_input_event(ev)
	await process_frame


## 1 回のひと撫で。dir は +1（下へ）か -1（上へ）。side は横の量の割合。scale は強さ
func _stroke(dir: float, side := 0.0, scale := 1.0) -> void:
	for v in [0.1, 0.3, 0.6, 0.9, 1.0, 0.8, 0.5, 0.3]:
		await _pan(Vector2(v * side, v * dir) * scale)
	await _pan(Vector2.ZERO)
	var m := 0.9
	for i in 40:
		await _pan(Vector2(m * side, m * dir) * scale)
		m *= 0.92
	await _pan(Vector2.ZERO)


func _wheel(b: MouseButton) -> void:
	for on in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		ev.pressed = on
		ev.factor = 1.0
		ev.position = root.get_visible_rect().size * 0.5
		Input.parse_input_event(ev)
	await process_frame
	await process_frame


func _expect(what: String, before: int, want: int) -> void:
	await create_timer(0.3).timeout   # 次のひと撫でと区切る（PAN_GAP より長く）
	var got := _hand()
	var ok := got == want
	if not ok:
		_fails += 1
	print("%s %s: %d → %d（期待 %d）" % ["OK " if ok else "NG ", what, before, got, want])


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	p.set("_pitch", -0.1)
	p.set_third(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	c.bags[p.id] = ITEMS.duplicate(true)
	c.send({"kind": "hand", "who": p.id, "slot": -1})
	await create_timer(1.0).timeout
	await _shot("0_bare")

	var h := _hand()
	await _stroke(1.0)
	await _expect("下へひと撫で（慣性つき）で 1 つ次へ", h, 0)
	await create_timer(0.8).timeout
	await _shot("1_flick_next")
	h = _hand()
	await _stroke(1.0, 0.0, 2.5)
	await _expect("強いひと撫でも 1 つだけ", h, 1)
	await create_timer(0.8).timeout
	await _shot("2_flick_next_strong")
	h = _hand()
	await _stroke(-1.0)
	await _expect("上へひと撫でで 1 つ前へ", h, 0)
	print("fps: ", Engine.get_frames_per_second())
	await create_timer(0.8).timeout
	await _shot("3_flick_back")
	h = _hand()
	await _stroke(0.25, 1.0)
	await _expect("横へのひと撫ででは替えない", h, h)
	h = _hand()
	await _stroke(1.0, 0.0, 0.03)
	await _expect("ごく軽く触れただけでは替えない", h, h)

	# 慣性の途中で指を戻し、すぐ逆へ撫でる（間をあけない）
	h = _hand()
	for v in [0.3, 0.8, 1.0, 0.6]:
		await _pan(Vector2(0, v))
	for v in [0.3, 0.8, 1.0, 0.6]:
		await _pan(Vector2(0, -v))
	await _expect("下へ撫でてすぐ上へ戻すと、行って戻る", h, h)

	h = _hand()
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _expect("ホイールを下へ 2 目盛りで 2 つ次へ", h, posmod(h + 1 + 2, ITEMS.size() + 1) - 1)
	h = _hand()
	await _wheel(MOUSE_BUTTON_WHEEL_UP)
	await _expect("ホイールを上へ 1 目盛りで 1 つ前へ", h, posmod(h + 1 - 1, ITEMS.size() + 1) - 1)

	# 装備の画面（I）を開いているあいだは替えない
	main.craft_ui.open_gear()
	await create_timer(0.5).timeout
	h = _hand()
	await _stroke(1.0)
	await _wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _expect("装備の画面を開いているあいだは替えない", h, h)
	await _shot("4_gear_open_no_change")
	main.craft_ui.close_gear()
	await create_timer(0.5).timeout
	h = _hand()
	await _stroke(1.0)
	await _expect("画面を閉じたら、また替わる", h, posmod(h + 2, ITEMS.size() + 1) - 1)

	print("確かめ: %s" % ("全部 OK" if _fails == 0 else "%d 件 NG" % _fails))
	quit(1 if _fails else 0)
