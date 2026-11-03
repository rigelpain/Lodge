extends SceneTree
## ロッジの内階段ののぼり下りの確かめ（数字で）。あなたが本物の W キーで、幅の西寄り・まんなか・東寄りの 3 本の筋を歩く。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/instair_check.gd -- --bots=0 --lodge-bots=0 --no-pip --dir=/path/out
## 道: 1 階ののぼり口の手前 → 1 本目（内側・西）を北へ → 踊り場 → 2 本目（東の壁ぎわ）を南へ → 2 階 → 同じ道を下って 1 階へ。
## 区間ごとに、着いたか・かかった秒・止まった秒・1 コマで跳ね上がった高さの最大・足が床を離れた秒・頭が天井に当たったコマを出す。
## 場所はロッジの座標（lodge/dims.py の x 東, y 北, 高さ。Godot ではロッジの (x, 高さ, -y)）。寸法は dims.py の INSTAIR と同じ。
## <dir>/instair.txt に書く。着かない区間・頭が当たったコマ・0.25 m を超える跳ね上がりが 1 つでもあれば終わりの番号を 1 にする

const FL1 := 0.45
const FL2 := 6.1
const X0 := 16.836        # 1 本目の西の縁
const XM := 19.236        # 1 本目と 2 本目の境
const X1 := 21.636        # 2 本目の東の縁（東の壁の内の面）
const Y_LAND := 10.146    # 踊り場の南の縁
const Y_TOP := 12.546     # 踊り場の北の縁（北の壁の内の面）
const Y_BOTTOM := 6.506   # 1 本目の 1 段目
const HOLE_Y0 := 6.246    # 2 本目の上がり口（2 階の床の穴の南の縁）
const LANES := [0.5, 1.2, 1.9]   # 筋: 階段の西の縁からの距離 (m)

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D
var lines: Array[String] = []
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/instair_check")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:   # 窓から目が離れると設定が開くことがある
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _l(g: Vector3) -> Vector3:   # 世界 → ロッジの座標 (x, y, 高さ)
	var q := lodge.to_local(g)
	return Vector3(q.x, -q.z, q.y)


func _g(x: float, y: float, h: float) -> Vector3:   # ロッジの座標 → 世界
	return lodge.to_global(Vector3(x, h, -y))


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


## いまの所から (x, y) へ、向きを合わせながら W で歩く。h は着いたときに足もとがあるはずの高さ（床の面）
func _walk(x: float, y: float, h: float, name: String) -> void:
	var goal := _g(x, y, h)
	await _key(KEY_W, true)
	var t := 0.0
	var stuck := 0.0
	var stuck_max := 0.0
	var air := 0.0
	var air_max := 0.0
	var ceil_hits := 0
	var pop := 0.0
	var last := p.global_position
	var ok := false
	var dt := 1.0 / Engine.physics_ticks_per_second
	while t < 30.0:
		if not Input.is_physical_key_pressed(KEY_W):   # 窓から目が離れると、押したキーが離される
			await _key(KEY_W, true)
		var d := goal - p.global_position
		d.y = 0
		if d.length() < 0.35:
			ok = true
			break
		p.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		t += dt
		var now := p.global_position
		pop = maxf(pop, now.y - last.y)
		stuck = stuck + dt if Vector2(now.x - last.x, now.z - last.z).length() < 0.002 else 0.0
		stuck_max = maxf(stuck_max, stuck)
		air = 0.0 if p.is_on_floor() else air + dt
		air_max = maxf(air_max, air)
		ceil_hits += int(p.is_on_ceiling())
		last = now
		if stuck > 2.0:
			break
	var why := ""
	if not ok:   # 止まった: 何に当たっているか
		for c in p.get_slide_collision_count():
			var k := p.get_slide_collision(c)
			var at := _l(k.get_position())
			why += "  当たり %s（x=%.2f y=%.2f 高さ %.2f、向き %s）" % [String((k.get_collider() as Node).name), at.x, at.y, at.z, str(k.get_normal().snapped(Vector3(0.01, 0.01, 0.01)))]
	await _key(KEY_W, false)
	for i in 6:
		await physics_frame
	var q := _l(p.global_position)
	var foot := q.z - h
	var good := ok and ceil_hits == 0 and pop < 0.25 and absf(foot) < 0.3
	if not good:
		bad += 1
	_say("  %s %s: %s（%.1f 秒、止まった最大 %.2f 秒、1 コマの跳ね上がり最大 %.3f m、足が離れた最大 %.2f 秒、頭 %d コマ、着いた所 x=%.2f y=%.2f 高さ %.2f・床とのずれ %+.2f）"
		% ["○" if good else "×", name, "着いた" if ok else "止まった", t, stuck_max, pop, air_max, ceil_hits, q.x, q.y, q.z, foot] + why)


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	lodge = main.get_node_or_null("Lodge")
	if p == null or lodge == null:
		print("あなたかロッジがない（--no-player・--no-lodge を付けない）")
		quit(1)
		return
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)   # ソリは道からどけておく
	var land := (Y_LAND + Y_TOP) / 2.0
	var z_land := FL1 + 15.0 * (FL2 - FL1) / 31.0
	for i in LANES.size():
		var a: float = X0 + LANES[i]   # 1 本目の筋
		var b: float = XM + LANES[i]   # 2 本目の筋
		_say("筋 %d（1 本目 x=%.2f、2 本目 x=%.2f）" % [i + 1, a, b])
		p.velocity = Vector3.ZERO
		p.global_position = _g(a, Y_BOTTOM - 2.0, FL1 + 0.1)
		for k in 10:
			await physics_frame
		await _walk(a, land, z_land, "のぼり 1 本目 → 踊り場")
		await _walk(b, land, z_land, "踊り場を東へ")
		await _walk(b, HOLE_Y0 - 1.5, FL2, "のぼり 2 本目 → 2 階")
		await _walk(b, land, z_land, "くだり 2 本目 → 踊り場")
		await _walk(a, land, z_land, "踊り場を西へ")
		await _walk(a, Y_BOTTOM - 2.0, FL1, "くだり 1 本目 → 1 階")
	# 斜めに: 1 階の南西から 1 本目へ斜めに入り、踊り場で大回りに折り返す
	_say("斜め（のぼり口へ斜めに入り、踊り場で角を回る）")
	p.global_position = _g(X0 - 1.5, Y_BOTTOM - 3.0, FL1 + 0.1)
	for k in 10:
		await physics_frame
	await _walk(X0 + 1.8, Y_BOTTOM + 1.0, FL1 + 1.26 * (z_land - FL1) / (Y_LAND - Y_BOTTOM), "1 階 → 1 本目へ斜めに")   # 坂の高さ
	await _walk(X0 + 0.6, Y_TOP - 0.6, z_land, "踊り場の北西の隅")
	await _walk(X1 - 0.6, Y_TOP - 0.6, z_land, "踊り場の北東の隅")
	await _walk(X1 - 0.5, HOLE_Y0 - 1.0, FL2, "2 本目の壁ぎわ → 2 階")
	_say("ずれ %d" % bad)
	var f := FileAccess.open(_dir().path_join("instair.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(1 if bad > 0 else 0)
