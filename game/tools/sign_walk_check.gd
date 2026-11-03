extends SceneTree
## 看板・旗・柱のそばを、歩いて・走って・ソリ（米袋）で滑って通り、つまずき・止まりを数える（確かめ用）。
##   Godot --path game --headless --fixed-fps 60 -s res://tools/sign_walk_check.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound --dir=/path/out
##   米袋で滑るときは --sled=sack を足す。--only=walk・deck・sled で一部だけ
## あなたは本物の W キー（走るは Shift も）で、物の真ん中を通る線と、横へずらした線を、前後・左右の 4 向きに 8 m 歩く。
## 1 回ごとに出す: 着いたか、途中の歩く速さのいちばん遅い所（速さの割合）と、6 割より遅かった時間、体が 1 コマで 4 cm より上に
## 持ち上がった回数（段を上った）とその高さのいちばん大きい所、落ちた回数（1 コマで 6 cm より下がった）。
## つまずき: 着かない・6 割より遅いのが 0.1 秒より長い・1 コマで 10 cm より持ち上がる・落ちる
## ソリはあなたが乗って、物の 6 m 上（坂の上の側）から、物の真ん中と横を通る向きに 6 m/s で滑り出し、速さの落ち（1 コマで 0.5 m/s より）と跳ねを数える。
## <dir>/sign_walk.txt に書く。つまずき（持ち上がり・止まり・落ち）が 1 つでもあれば、終わりの番号を 1 にする

const WALK := 2.0             # player.gd の SPEED
const RUN := 3.4              # player.gd の DASH
const POP := 0.04             # 1 コマでこれより上がったら「段を上った」
const DROP := 0.06            # 1 コマでこれより下がったら「落ちた」
const SLOW := 0.6             # 速さの割合がこれより下がっている時間が SLOW_T より長ければ「止まりかけた」
const SLOW_T := 0.1

var args := {}
var main: Node3D
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
	return args.get("dir", "/tmp/sign_walk")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


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


## 足もとの床（当たり判定）の高さ。上から光線を落とす
func _floor(x: float, z: float, top: float) -> Vector3:
	var r := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, top - 40.0, z))
	r.exclude = [p.get_rid(), main.sled.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else Vector3(x, main.height(x, z), z)


## a から b へ（世界の x, z）、W で歩く。run なら Shift も押す。結果を 1 行で返し、つまずきなら bad を足す
func _pass(name: String, a: Vector2, b: Vector2, run: bool, top: float) -> String:
	var start := _floor(a.x, a.y, top) + Vector3.UP * 0.1
	p.global_position = start
	p.velocity = Vector3.ZERO
	var d := Vector3(b.x - a.x, 0, b.y - a.y)
	p.rotation.y = atan2(-d.x, -d.z)
	for i in 20:   # 着地を待つ
		await physics_frame
		p.global_position.x = start.x
		p.global_position.z = start.z
	var goal := Vector3(b.x, 0, b.y)
	if run:
		await _key(KEY_SHIFT, true)
	await _key(KEY_W, true)
	var nominal := RUN if run else WALK
	var last := p.global_position
	var t := 0.0
	var slowest := 9.0
	var slow_t := 0.0
	var pops := 0
	var pop_max := 0.0
	var drops := 0
	var ok := false
	var stall := 0.0
	var total := Vector2(a.x - b.x, a.y - b.y).length()
	while t < 12.0:
		var to := goal - p.global_position
		to.y = 0
		if to.length() < 0.25:
			ok = true
			break
		p.rotation.y = atan2(-to.x, -to.z)
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var now := p.global_position
		var dy := now.y - last.y
		var hv := Vector2(now.x - last.x, now.z - last.z).length() / dt
		var done := total - Vector2(goal.x - now.x, goal.z - now.z).length()
		if t > 0.35 and done < total - 0.4:   # 歩き出しと着く手前は数えない
			slowest = minf(slowest, hv / nominal)
			if hv / nominal < SLOW:
				slow_t += dt
		if dy > POP:
			pops += 1
			pop_max = maxf(pop_max, dy)
		elif dy < -DROP:
			drops += 1
		stall = stall + dt if hv < 0.05 else 0.0
		last = now
		if stall > 1.0:
			break
	await _key(KEY_W, false)
	if run:
		await _key(KEY_SHIFT, false)
	var trip := not ok or pop_max > 0.1 or drops > 0 or slow_t > SLOW_T
	if trip:
		bad += 1
	return "  %s %s: %s  遅い所 %.0f%%（%.0f%% より遅いのが %.2f 秒）  持ち上がり %d 回（いちばん %.0f cm）  落ち %d 回%s" % [name,
			"走る" if run else "歩く", "着いた" if ok else "止まった", slowest * 100.0, SLOW * 100.0, slow_t, pops, pop_max * 100.0, drops,
			"  ← つまずき" if trip else ""]


## 物 o（世界の x, z）のまわりを、4 向き × ずらし × 歩く・走るで通る
func _around(name: String, o: Vector2, top: float, offs := [0.0, 0.5]) -> void:
	_say("%s（x=%.1f z=%.1f）" % [name, o.x, o.y])
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var side: Vector2 = Vector2(-dir.y, dir.x)
		for off in offs:
			var a: Vector2 = o - dir * 4.0 + side * off
			var b: Vector2 = o + dir * 4.0 + side * off
			for run in [false, true]:
				_say(await _pass("向き (%+d,%+d) ずらし %.1f m" % [dir.x, dir.y, off], a, b, run, top))


## ソリ（米袋）にあなたが乗り、物 o の 6 m 上（地面の高い側）から、o を通る線と横へずらした線で 6 m/s で滑り出す（W で前傾）。
## 1 コマで 0.5 m/s より速さが落ちる・上向きに 1 m/s より跳ねたら、つまずき（摩擦でゆっくり遅くなるのは数えない）
func _slide(name: String, o: Vector2, offs := [0.0, 0.6, -0.6]) -> void:
	var s: RigidBody3D = main.sled
	var g := Vector2(main.height(o.x + 1.0, o.y) - main.height(o.x - 1.0, o.y), main.height(o.x, o.y + 1.0) - main.height(o.x, o.y - 1.0))
	var down := -g.normalized() if g.length() > 0.01 else Vector2(0, 1)
	_say("%s をソリ（%s）に乗って（坂の下りの向き (%.2f, %.2f)、傾き %.0f°）" % [name, s.kind, down.x, down.y, rad_to_deg(atan(g.length() / 2.0))])
	for off in offs:
		var side: Vector2 = Vector2(-down.y, down.x) * float(off)
		var a: Vector2 = o - down * 6.0 + side
		s.reset_to(Vector3(a.x, main.height(a.x, a.y) + 0.3, a.y))
		s.global_basis = Basis(Vector3.UP, atan2(-down.x, -down.y))
		for i in 10:
			await physics_frame
		p.global_position = s.global_position + s.global_basis.x * 1.5
		p.get_on()
		await _key(KEY_W, true)
		s.parked = false
		s.linear_velocity = Vector3(down.x, 0, down.y) * 6.0
		var last_v := 6.0
		var worst := 0.0
		var hop := 0.0
		var t := 0.0
		var passed := false
		while t < 4.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			var v := Vector2(s.linear_velocity.x, s.linear_velocity.z).length()
			worst = maxf(worst, last_v - v)
			hop = maxf(hop, s.linear_velocity.y)
			last_v = v
			var rel := Vector2(s.global_position.x, s.global_position.z) - o
			if rel.dot(down) > 3.0:
				passed = true
				break
		await _key(KEY_W, false)
		var rode: int = s.riders.size()
		p.get_off()
		var trip := worst > 0.5 or hop > 1.0
		if trip:
			bad += 1
		_say("  ずらし %+.1f m: %s  1 コマの速さの落ち いちばん %.2f m/s  上向きの速さ いちばん %.2f m/s  そのときの速さ %.1f m/s  乗った人 %d%s" % [off,
				"通り抜けた" if passed else "手前で止まった（摩擦）", worst, hop, last_v, rode, "  ← つまずき" if trip else ""])
	s.reset_to(Vector3(30, main.height(30, -30) + 0.5, -30))


func _signs() -> Array:
	var out := []
	for n in main.find_children("*", "Node3D", true, false):
		var f := String((n as Node).scene_file_path)
		for key in ["sign_lodge", "sign_slope"]:
			if f.ends_with(key + ".glb"):
				out.append([key, n])
	return out


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	if p == null:
		print("あなたがいない（--no-player を付けない）")
		quit(1)
		return
	var lodge: Node3D = main.get_node_or_null("Lodge")
	main.sled.reset_to(Vector3(30, main.height(30, -30) + 0.5, -30))
	var only: String = args.get("only", "")
	if only in ["", "walk"]:
		for e in _signs():
			var s: Node3D = e[1]
			await _around("道しるべ %s" % e[0], Vector2(s.global_position.x, s.global_position.z), s.global_position.y + 4.0)
	if only in ["", "walk", "deck"]:
		# 玄関前の広場の南の縁の段（前の道しるべは、ここの段の上に立っていた）。段を上る・下りる
		if lodge:
			_say("玄関前の広場の南の縁の段（ロッジの座標 x、z=23.3 ↔ 30 を歩く）")
			for lx in [-8.0, -9.0, -10.0, -10.4, -11.0, -12.0, -13.4, -16.0, -19.0, -21.0]:
				var a := lodge.to_global(Vector3(lx, 0, 30.0))
				var b := lodge.to_global(Vector3(lx, 0, 23.3))   # 外階段の登り口（z=22.3）より南
				for run in [false, true]:
					_say(await _pass("x=%.1f 上る" % lx, Vector2(a.x, a.z), Vector2(b.x, b.z), run, lodge.global_position.y + 1.2))
					_say(await _pass("x=%.1f 下りる" % lx, Vector2(b.x, b.z), Vector2(a.x, a.z), run, lodge.global_position.y + 1.2))
	if only in ["", "walk"]:
		# 旗・網・スピーカーの柱: 大きな山のコースの旗と網、登り道の旗、柱をひとつずつ
		var seen := {}   # 先に集める（歩くあいだに消える物があるので、探しながら待たない）
		for n in main.find_children("*", "Node3D", true, false):
			var f := String((n as Node).scene_file_path)
			for key in ["flag_red", "net_span", "speaker_pole"]:
				if f.ends_with(key + ".glb") and not seen.has(key):
					seen[key] = (n as Node3D).global_position
		for key in seen:
			var g: Vector3 = seen[key]
			await _around(key, Vector2(g.x, g.z), g.y + 4.0, [0.0])
	if only in ["", "sled"]:
		for e in _signs():
			var s: Node3D = e[1]
			await _slide("道しるべ %s" % e[0], Vector2(s.global_position.x, s.global_position.z))
	_say("つまずき: %d" % bad)
	var f := FileAccess.open(_dir().path_join("sign_walk%s.txt" % args.get("tag", "")), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(1 if bad > 0 else 0)
