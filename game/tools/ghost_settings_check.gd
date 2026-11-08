extends SceneTree
## 設定の画面の霊体化の切り替え（settings.gd の _build_ghost）の確かめ:
##   Godot --path game --resolution 1280x720 -s res://tools/ghost_settings_check.gd -- --no-sound --dir=/path/shots
## Esc で設定を開き、切り替えで霊体になる → 見える・見えないも切り替える → 撮る（設定を開いたまま、霊体の画面）。
## 閉じたまま（設定の外で）戻ると切り替えも戻るか、抜けると切り替えも入るか、O・U では何も起きないか、切り替えで戻ると抜けた所・向きへ戻るか。
## 霊体化は保存しない（settings.values に入らない）

var main: Node3D
var fails := 0
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _check(ok: bool, s: String) -> void:
	print(("○ " if ok else "× ") + s)
	if not ok:
		fails += 1


func _tap(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func _run() -> void:
	await create_timer(1.5).timeout
	var p: CharacterBody3D = main.player
	var g: Node = main.ghost
	var st: CanvasLayer = main.settings
	await create_timer(0.5).timeout
	var at0 := p.global_position
	var yaw0 := p.rotation.y

	# 1) 設定を開いて、切り替えで霊体へ
	await _tap(KEY_ESCAPE)
	_check(st.is_open, "Esc で設定の画面が開いた")
	_check(not st._ghost_cb.button_pressed and st._seen_cb.disabled, "はじめは体（霊体化は切、見える・見えないは触れない）")
	st._ghost_cb.button_pressed = true
	await process_frame
	_check(g.active and int(p.ghost) == 1, "切り替えで霊体になった（見えない霊体）")
	_check(not st._seen_cb.disabled, "霊体のあいだは、見える・見えないに触れる")
	st._seen_cb.button_pressed = true
	await process_frame
	_check(int(p.ghost) == 2 and g.seen, "切り替えで見える霊体になった")
	g.cam.global_position += Vector3.UP * 4.0   # 浮かんでいるのが分かるよう、少し上から
	g._pitch = -0.35
	g.cam.global_basis = Basis.from_euler(Vector3(g._pitch, g._yaw, 0))
	for i in 8:
		await process_frame
	var dir: String = args.get("dir", "")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		root.get_viewport().get_texture().get_image().save_png(dir + "/settings_ghost.png")

	# 2) 閉じたまま、O・U は効かない。設定の外で戻る → 切り替えも切に
	await _tap(KEY_ESCAPE)
	_check(not st.is_open, "Esc で閉じた（霊体のまま）")
	_check(g.active, "閉じても霊体のまま")
	await _tap(KEY_O)
	await _tap(KEY_U)
	_check(g.active and int(p.ghost) == 2, "O・U のキーでは何も変わらない（キーの切り替えは外した）")
	g.leave()
	await create_timer(0.3).timeout
	_check(not g.active and int(p.ghost) == 0, "体へ戻った")
	_check(not st._ghost_cb.button_pressed and not st._seen_cb.button_pressed and st._seen_cb.disabled, "設定の切り替えも切に戻った")

	# 3) 設定の外で抜ける → 切り替えも入に。設定の切り替えで戻る
	await _tap(KEY_O)
	_check(not g.active, "体のときも O では抜けない")
	g.enter()
	await process_frame
	_check(g.active, "抜けた")
	await _tap(KEY_ESCAPE)
	_check(st._ghost_cb.button_pressed and not st._seen_cb.button_pressed and not st._seen_cb.disabled, "設定の切り替えも入（見えない）になっている")
	g.cam.global_position += Vector3(3, 2, -4)
	st._ghost_cb.button_pressed = false
	await create_timer(0.3).timeout
	_check(not g.active and int(p.ghost) == 0, "切り替えで体へ戻った")
	_check(p.global_position.distance_to(at0) < 0.05, "抜けた所に戻った（ずれ %.3f m）" % p.global_position.distance_to(at0))
	_check(absf(angle_difference(p.rotation.y, yaw0)) < 0.01, "抜けたときの向き")
	_check(root.get_viewport().get_camera_3d() == p.cam, "体のカメラに戻った")
	_check(not st.values.has("ghost") and not st.values.has("ghost_seen"), "霊体化は保存する値に入っていない")
	await _tap(KEY_ESCAPE)
	print("食い違い %d" % fails)
	quit(1 if fails > 0 else 0)
