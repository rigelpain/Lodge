extends SceneTree
## 乗り心地の調整（ride_tune.gd・ride_tune_ui.gd）の確かめ。旭ヶ丘でソリに乗って下り、
##   1. 一人称と三人称の画面の揺れ（1 コマで向きが変わる角度の最大）を測る（三人称は RATTLE_THIRD 倍で抑えめ）
##   2. 調整の画面のスライダーを動かして、値が効くこと（三人称の倍率 0 で三人称の揺れが消える、雪の抵抗で最高速度が変わる、飛ぶ距離が変わる）
##   3. 「JSON をコピー」→「既定に戻す」→「貼り付けて読む」で、同じ値に戻ること（クリップボードはもとの中身に戻す）
##   Godot --path game --resolution 960x540 -s res://tools/ride_tune_check.gd -- --world=asahigaoka --no-sound

const Tune := preload("res://ride_tune.gd")
const Flung := preload("res://flung.gd")
var main: Node3D
var fails := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print(("OK  " if cond else "NG  ") + what)
	if not cond:
		fails += 1


func _slider(ui: Control, var_name: String, sub: String) -> HSlider:
	for r in ui._rows:
		if r[0][1] == var_name and r[0][2] == sub:
			return r[1]
	return null


func _run() -> void:
	for i in 30:
		await physics_frame
	if main.start:
		main.start._solo()
	var p = main.player
	var sled: RigidBody3D = main.sled
	var settings = main.settings
	# 確かめで切り替える設定（確かめ用の数字・三人称）は保存されるので、終わりにファイルごと元に戻す（遊ぶ人の設定を変えない）
	var keep_cfg := FileAccess.get_file_as_string(settings.PATH)
	# 調整の画面を開く（確かめ用の数字を入れて、ボタンから）
	settings.choose("hud_debug", true)
	settings.set_open(true)
	_ok(settings._tune_btn.visible, "確かめ用の数字を入れると「乗り心地の調整」ボタンが出る")
	settings._tune_btn.pressed.emit()
	var ui: Control = settings._tune
	_ok(ui.visible and not settings._panel.get_parent().visible, "ボタンで調整の画面に切り替わる")
	settings.set_open(false)

	var start_ride := func() -> void:
		var at := Vector2(-200, -190)
		var dir := (Vector2(18, -18) - at).normalized()
		if p.mode == p.Mode.RIDE:
			p.get_off()
			for i in 10:
				await physics_frame
		sled.reset_to(Vector3(at.x, main.height(at.x, at.y) + 0.6, at.y))
		sled.rotation.y = atan2(-dir.x, -dir.y)
		sled.parked = false
		for i in 10:
			await physics_frame
		p.global_position = sled.global_position + Vector3(1.5, 0.5, 0)
		for i in 5:
			await physics_frame
		p.get_on()
		for i in 120:
			await physics_frame

	# ---- 1. 一人称・三人称の揺れ
	var shake := func(third: bool) -> float:
		p.set_third(third)
		var big := 0.0
		var prev: Transform3D = p.cam.global_transform
		var sum := 0.0
		for i in 180:
			await process_frame
			var t: Transform3D = p.cam.global_transform
			var a := rad_to_deg(prev.basis.get_rotation_quaternion().angle_to(t.basis.get_rotation_quaternion()))
			sum += a
			prev = t
		return sum / 180.0
	await start_ride.call()
	_ok(p.mode == p.Mode.RIDE, "ソリに乗った")
	var fps: float = await shake.call(false)
	var tps: float = await shake.call(true)
	print("    一人称: 1 コマの向きの変わり 平均 %.3f°・三人称 %.3f°（三人称の倍率 %.2f）・速さ %.1f m/s" % [fps, tps, p.RATTLE_THIRD, sled.linear_velocity.length()])
	_ok(tps < fps, "三人称の揺れが一人称より小さい")
	# 調整の画面で三人称の倍率を 0 に
	var sl := _slider(ui, "RATTLE_THIRD", "")
	sl.value = 0.0
	_ok(is_zero_approx(p.RATTLE_THIRD), "スライダーで三人称の倍率が 0 になる")
	await start_ride.call()
	var tps0: float = await shake.call(true)
	print("    三人称の倍率 0: 1 コマの向きの変わり 平均 %.3f°" % tps0)
	_ok(tps0 < tps * 0.6, "三人称の倍率 0 で三人称の揺れが減る（残りはソリそのものの傾き）")

	# ---- 2. 雪の抵抗（最高速度）
	var top := func() -> float:
		await start_ride.call()
		var best := 0.0
		for i in 360:
			await physics_frame
			best = maxf(best, sled.linear_velocity.length())
		return best
	var v_def: float = await top.call()
	_slider(ui, "FEEL", "glide").value = 1.0
	_ok(is_equal_approx(sled.glide, 1.0) and is_equal_approx(sled.FEEL.glide, 1.0), "スライダーで雪の抵抗がすぐ効く（いまのワールドの値と FEEL の両方）")
	var v_slow: float = await top.call()
	print("    8 秒のうちの最高の速さ: 雪の抵抗 0.25 で %.1f m/s・1.0 で %.1f m/s" % [v_def, v_slow])
	_ok(v_slow < v_def * 0.85, "雪の抵抗を上げると遅くなる")

	# ---- 飛ぶ距離（放り投げの水平・上向きの速さ）
	var f0: Vector2 = Flung.throw_speeds(10.0, 1.1)
	_slider(ui, "THROW_DIST_K", "").value = 2.4
	var f1: Vector2 = Flung.throw_speeds(10.0, 1.1)
	print("    10 m/s で放り投げ（水平, 上）: 距離の係数 1.2 で %s・2.4 で %s" % [f0, f1])
	_ok(is_equal_approx(f1.x, f0.x * sqrt(2.0)), "距離の係数を 2 倍にすると速さが √2 倍（距離が 2 倍）")
	_slider(ui, "CRASH_UP", "y").value = 20.0
	_ok(is_equal_approx(sled.CRASH_UP.y, 20.0) and is_equal_approx(sled.CRASH_UP.x, 5.0), "Vector2 の片方だけ変わる")

	# ---- 3. JSON のコピーと貼り戻し
	var keep := DisplayServer.clipboard_get()
	var before := {}
	for it in Tune.items():
		before[Tune.id(it)] = Tune.value(it)
	ui._copy()
	var copied := DisplayServer.clipboard_get()
	print("    コピーした JSON（%d 字）: %s" % [copied.length(), ui._status.text])
	ui._reset()
	_ok(is_equal_approx(p.RATTLE_THIRD, 0.4) and is_equal_approx(sled.glide, 0.25), "既定に戻す")
	ui._paste()
	print("    " + ui._status.text)
	var same := true
	for it in Tune.items():
		if not is_equal_approx(Tune.value(it), before[Tune.id(it)]):
			same = false
			print("    違う: %s %f %f" % [Tune.id(it), Tune.value(it), before[Tune.id(it)]])
	_ok(same, "貼り戻すと、すべて同じ値になる")
	_ok(is_equal_approx(sled.glide, 1.0) and is_zero_approx(p.RATTLE_THIRD), "貼り戻した値が、いまのワールドにも効く")
	var shown := true
	for r in ui._rows:
		if not is_equal_approx(r[1].value, Tune.value(r[0])):
			shown = false
			print("    表示が違う: %s %f %f" % [Tune.id(r[0]), r[1].value, Tune.value(r[0])])
	_ok(shown, "スライダーの表示も貼った値になる")
	DisplayServer.clipboard_set(keep)
	# ファイルにも残す（本番に入れる道具 ride_tune_apply.gd の確かめに使う）
	if main.args.has("json"):
		var f := FileAccess.open(String(main.args["json"]), FileAccess.WRITE)
		f.store_string(copied)
		f.close()
	if keep_cfg != "":
		var cf := FileAccess.open(settings.PATH, FileAccess.WRITE)
		cf.store_string(keep_cfg)
		cf.close()
	print("NG の数: %d" % fails)
	quit(1 if fails > 0 else 0)
