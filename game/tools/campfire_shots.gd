extends SceneTree
## 焚き火（campfire.gd・craft.gd の fire_lay / fire_out）を確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/campfire_shots.gd -- --bots=0 --lodge-bots=0 --no-pip --dir=/path/shots
## 売り子のおじさんの売り台で焚き火セットを買う → 手に持って外の雪の上で F → 組む・火がつく（夕方・夜、一人称・三人称）→
## そばで乾く（水 100 から、1 秒ごとの値。暖炉のそばの速さと比べる）→ F で雪をかけて消す → 片づく →
## 燃え尽きる（時間を進める）→ ロッジの中では組めない。数は log.txt に書く

const Campfire := preload("res://campfire.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var dc: Node
var lines: Array[String] = []
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/campfire")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _check(ok: bool, what: String) -> void:
	_say(("OK  " if ok else "NG  ") + what)
	if not ok:
		fails += 1


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _key(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = d
		Input.parse_input_event(e)
		await process_frame


func _put(at: Vector3, look: Vector3, pitch := -0.15) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	p.set("_pitch", pitch)


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z) + 0.15, z)


func _fire() -> Node3D:
	for f in main.craft.fires.values():
		if is_instance_valid(f):
			return f
	return null


func _run() -> void:
	await _wait(2.5)
	p = main.player
	dc = root.get_node("DayCycle")
	var c: Node = main.craft
	var damp: Node = main.damp
	var who: int = p.id
	var start: Vector3 = p.global_position

	# 1. 売り子のおじさんの売り台で買う
	var sk: Node3D = main.shopkeeper
	_put(sk.to_global(Vector3(0, 0.1, -3.6)), sk.global_position, 0.25)
	await _wait(0.6)
	await _shot("00_sign")   # 頭の上の品書きの看板（型紙 4 つと焚き火セット、布 6 つ）
	_put(sk.to_global(Vector3(0, 0.1, -2.2)), sk.global_position, -0.2)
	await _wait(0.4)
	main.craft_ui.open_shop()
	var gi := -1
	for i in main.craft_ui._goods.size():
		if main.craft_ui._goods[i].kind == "campfire":
			gi = i
	main.craft_ui.select(gi)
	await _wait(0.4)
	await _shot("01_shop")
	var before: int = c.wallet(who)
	_check(main.craft_ui.buy(), "焚き火セットを買えた")
	_check(c.wallet(who) == before - Campfire.PRICE, "ボタンが %d 減った（%d → %d）" % [Campfire.PRICE, before, c.wallet(who)])
	_check(c.held(who).get("kind", "") == "campfire", "買った焚き火セットを手に持っている")
	await _wait(0.4)
	main.craft_ui.close_shop()
	await _wait(0.3)
	# ロッジの中では組めない
	_check(p.fire_spot().is_empty(), "ロッジの中では組めない")
	await _key(KEY_F)
	await _wait(0.2)
	_check(c.fires.is_empty() and c.held(who).get("kind", "") == "campfire", "ロッジの中で F を押しても組まない")

	# 2. 夕方、外の雪の上で手に持つ
	await _hour(17.8)
	var at := _ground(start.x + 4.0, start.z + 6.0)
	_put(at, at + Vector3(0, 0, 10), -0.35)
	await _wait(0.6)
	_check(not p.fire_spot().is_empty(), "外の雪の上なら組める所がある")
	await _shot("02_held_1st")
	damp.put(who, 100.0)
	await _key(KEY_F)
	var f := _fire()
	_check(f != null, "F で焚き火を組んだ")
	_check(c.held(who).is_empty(), "焚き火セットが持ち物から消えた")
	await _wait(0.35)
	await _shot("03_lay_a")
	await _wait(0.4)
	await _shot("04_lay_b")
	await _wait(1.0)
	_check(f.level() > 0.0 and f.is_in_group("fires"), "火がついた（強さ %.2f）" % f.level())
	await _shot("05_lit_1st")
	p.set_third(true)
	await _wait(0.4)
	await _shot("06_lit_3rd")

	# 3. そばで乾く: 1 秒ごとの水（体は焚き火から 1.4 m）
	p.set_third(false)
	var near: Vector3 = f.global_position + Vector3(0, 0, -1.4)
	near.y = main.height(near.x, near.z) + 0.15
	_put(near, f.global_position, -0.35)
	damp.put(who, 100.0)
	var log_w := []
	for i in 16:
		log_w.append(int(damp.water_of(who)))
		await _wait(1.0)
	_say("焚き火から 1.4 m の水（1 秒ごと）: %s" % [log_w])
	_check(log_w[-1] < 0, "そばで 0 より下（パリッと）まで乾いた")
	_say("気温: 焚き火のそば %.1f °C、10 m 離れた所 %.1f °C" % [root.get_node("Temperature").at(near), root.get_node("Temperature").at(near + Vector3(10, 0, 0))])
	await _shot("07_dry_1st")

	# 4. 夜
	await _hour(21.5)
	var view: Vector3 = f.global_position + Vector3(2.2, 0, -2.6)
	view.y = main.height(view.x, view.z) + 0.15
	_put(view, f.global_position, -0.3)
	await _wait(0.4)
	await _shot("08_night_1st")
	p.set_third(true)
	await _wait(0.4)
	await _shot("09_night_3rd")
	p.set_third(false)
	await _wait(0.3)
	var close: Vector3 = f.global_position + Vector3(1.1, 0, -1.3)
	close.y = main.height(close.x, close.z) + 0.15
	_put(close, f.global_position, -0.42)
	await _wait(0.1)
	p.set("_pitch", -0.42)
	await _wait(0.3)
	await _shot("09b_night_close")
	p.set_third(true)
	for i in 3:   # 炎のコマ（2 コマごとに切り方が替わる）
		await _wait(1.0 / 6.0)
		await _shot("10_night_flame_%d" % i)
	p.set_third(false)

	# 5. F で雪をかけて消す
	_put(near, f.global_position, -0.35)
	await _wait(0.3)
	_check(p.own_fire_near() == f, "自分の焚き火のそば")
	await _key(KEY_F)
	await _wait(0.1)
	_check(not f.lit() and not f.is_in_group("fires"), "F で消えた")
	await _wait(0.4)
	await _shot("11_out")
	await _wait(Campfire.AFTER + 1.5)
	_check(not is_instance_valid(f), "消えて %.0f 秒ほどで片づいた" % Campfire.AFTER)

	# 6. 燃え尽きる: もう 1 つ組んで、時間を進める
	c._put(who, {"kind": "campfire"})
	await _wait(0.2)
	_put(at, at + Vector3(0, 0, 10), -0.35)
	await _wait(0.3)
	await _key(KEY_F)
	var g := _fire()
	_check(g != null, "2 つ目を組んだ")
	g.age = Campfire.LIFE - Campfire.FADE + 5.0
	await _wait(0.4)
	_say("弱っているときの強さ %.2f" % g.level())
	await _shot("12_fading")
	g.age = Campfire.LIFE - 0.5
	await _wait(1.0)
	_check(not g.lit() and not g.is_in_group("fires"), "燃え尽きた")
	await _shot("13_burnt")

	_say("済んだ（NG %d）" % fails)
	var fa := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(lines))
	quit(1 if fails > 0 else 0)
