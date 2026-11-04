extends SceneTree
## ロッジのガラスの壁（lodge/dims.py の POST）の柱に沿って歩いて・走って通り、つまずきを数える（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 60 -s res://tools/window_post_walk_check.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound --dir=/path/out
## 線は柱の面から体（半径 0.35）が 2 cm 離れる所を通し、本物の W キー（走るは Shift も）で行き来する。
## つまずきの数え方は tools/sign_walk_check.gd と同じ（着かない・6 割より遅いのが 0.1 秒より長い・1 コマで 10 cm より持ち上がる・落ちる）。
## 当たり判定の面も光線で測る: 柱の面は芯から POST / 2、柱のあいだのガラスも同じ。合わなければ「ずれ」。
## <dir>/window_post_walk.txt に書く。つまずき・ずれが 1 つでもあれば、終わりの番号を 1 にする

const WALK := 2.0
const RUN := 3.4
const DROP := 0.06
const SLOW := 0.6
const SLOW_T := 0.1
const FL1 := 0.45
const POST := 0.24
const K := 1.818
const X0 := -12.0 * K
const X1 := 12.0 * K
const Y0 := -7.0 * K
const Y1 := 7.0 * K
const GLASS_S_X0 := X0 + 7.0 * K
const NEAR := POST / 2.0 + 0.35 + 0.02   # 柱の芯から体の芯まで

# [名前, 始め (x, y), 終わり (x, y), 床の高さ（光線を落とし始める高さの目安）]。ロッジの座標
const LINES := [
	["南の窓の外（デッキの上）", Vector2(-7.3, Y0 - NEAR), Vector2(-0.6, Y0 - NEAR), FL1],
	["南の窓の外（雪の上）", Vector2(1.0, Y0 - NEAR), Vector2(X1 + 1.0, Y0 - NEAR), 0.0],
	["西の窓の外（下屋の下を南から北へ）", Vector2(X0 - NEAR, Y0 + 0.5), Vector2(X0 - NEAR, Y1 - 0.5), 0.0],
	["西の窓の中（貸出の棚と柵のあいだ）", Vector2(X0 + NEAR, -6.0), Vector2(X0 + NEAR, -3.0), FL1],
	["西の窓の中（柵の北）", Vector2(X0 + NEAR, 8.4), Vector2(X0 + NEAR, Y1 - 0.8), FL1],
	["西の窓の中、斜めに柱へ寄る", Vector2(-18.0, 10.8), Vector2(X0 + NEAR, 9.0), FL1],
	["南東の隅をまわる", Vector2(X1 - 1.0, Y0 - 1.0), Vector2(X1 + 1.0, Y0 - 0.2), 0.0],
	["北西の隅をまわる", Vector2(X0 - 1.0, Y1 - 0.5), Vector2(X0 - 0.5, Y1 + 1.0), 0.0],
]

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
	return args.get("dir", "/tmp/window_post_walk")


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


## ロッジの座標 (x, y) の床（当たり判定）。床の高さ h の 1.2 m 上から光線を落とす
func _floor(q: Vector2, h: float) -> Vector3:
	var g := lodge.to_global(Vector3(q.x, h + 1.2, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g, g + Vector3.DOWN * 3.0)
	r.exclude = [p.get_rid(), main.sled.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else lodge.to_global(Vector3(q.x, h, -q.y))


func _pass(name: String, a: Vector2, b: Vector2, h: float, run: bool) -> String:
	var start := _floor(a, h) + Vector3.UP * 0.1
	var goal := _floor(b, h)
	p.global_position = start
	p.velocity = Vector3.ZERO
	for i in 20:   # 着地を待つ
		await physics_frame
		p.global_position.x = start.x
		p.global_position.z = start.z
	if run:
		await _key(KEY_SHIFT, true)
	await _key(KEY_W, true)
	var nominal := RUN if run else WALK
	var last := p.global_position
	var t := 0.0
	var slowest := 9.0
	var slow_t := 0.0
	var pop_max := 0.0
	var drops := 0
	var fell := ""
	var ok := false
	var stall := 0.0
	var total := Vector2(goal.x - start.x, goal.z - start.z).length()
	while t < 30.0:
		var to := goal - p.global_position
		to.y = 0
		if to.length() < 0.25:
			ok = true
			break
		p.rotation.y = atan2(-to.x, -to.z)
		if not Input.is_physical_key_pressed(KEY_W):   # 窓の手元が外れると、押したキーが放される。押しなおす
			if run:
				await _key(KEY_SHIFT, true)
			await _key(KEY_W, true)
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var now := p.global_position
		var dy := now.y - last.y
		var hv := Vector2(now.x - last.x, now.z - last.z).length() / dt
		var done := total - Vector2(goal.x - now.x, goal.z - now.z).length()
		if t > 0.35 and done < total - 0.4:
			slowest = minf(slowest, hv / nominal)
			if hv / nominal < SLOW:
				slow_t += dt
		pop_max = maxf(pop_max, dy)
		if t > 0.35 and dy < -DROP:   # 始めの着地は数えない
			drops += 1
			var d := lodge.to_local(now)
			fell = "  落ちた所 x=%.2f y=%.2f 高さ %.2f（%.1f cm）" % [d.x, -d.z, d.y, -dy * 100.0]
		stall = stall + dt if hv < 0.05 else 0.0
		last = now
		if stall > 1.0:
			break
	var why := ""
	if not ok:   # 止まった所（ロッジの座標）と、体が当たっている物
		var at := lodge.to_local(p.global_position)
		var hits := []
		for i in p.get_slide_collision_count():
			var col := p.get_slide_collision(i).get_collider() as Node
			if col and not col.name in hits:
				hits.append(String(col.name))
		why = "  止まった所 x=%.2f y=%.2f 高さ %.2f、当たった物 %s" % [at.x, -at.z, at.y, hits]
	await _key(KEY_W, false)
	if run:
		await _key(KEY_SHIFT, false)
	var trip := not ok or pop_max > 0.1 or drops > 0 or slow_t > SLOW_T
	if trip:
		bad += 1
	return "  %s %s: %s  遅い所 %.0f%%（%.2f 秒）  持ち上がり いちばん %.1f cm  落ち %d 回%s" % [name,
			"走る" if run else "歩く", "着いた" if ok else "止まった", slowest * 100.0, slow_t, pop_max * 100.0, drops,
			"  ← つまずき" + why + fell if trip else ""]


## ロッジの座標 from から to へ光線を飛ばし、当たるまでの長さ（当たらなければ -1）
func _ray(from: Vector3, to: Vector3) -> float:
	var a := lodge.to_global(Vector3(from.x, from.z, -from.y))
	var b := lodge.to_global(Vector3(to.x, to.z, -to.y))
	var r := PhysicsRayQueryParameters3D.create(a, b)
	r.exclude = [p.get_rid(), main.sled.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return a.distance_to(hit.position) if hit else -1.0


## 当たり判定の面が、ガラスの壁の芯から POST / 2 にあるか（柱の位置と、柱のあいだの両方を、中と外から）
func _measure() -> void:
	var z := FL1 + 1.2
	var got := []
	for x in [GLASS_S_X0 + 3.09, GLASS_S_X0 + 1.5, X1 - 3.09 * 2.0]:   # 南: 柱・柱のあいだ・柱
		got.append(["南の壁 x=%.2f 外から" % x, _ray(Vector3(x, Y0 - 1.0, z), Vector3(x, Y0, z)) - (1.0 - POST / 2.0)])
	for y in [Y0 + 2.545 * 3.0, Y0 + 2.545 * 3.5]:   # 西: 柱・柱のあいだ（貸出の棚と柵のあいだ）
		got.append(["西の壁 y=%.2f 外から" % y, _ray(Vector3(X0 - 1.0, y, z), Vector3(X0, y, z)) - (1.0 - POST / 2.0)])
		got.append(["西の壁 y=%.2f 中から" % y, _ray(Vector3(X0 + 1.0, y, z), Vector3(X0, y, z)) - (1.0 - POST / 2.0)])
	for g in got:
		var off: bool = absf(g[1]) > 0.01
		if off:
			bad += 1
		_say("  %s: 面のずれ %.3f m%s" % [g[0], g[1], "  ← ずれ" if off else ""])


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	lodge = main.get_node("Lodge")
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)
	_say("当たり判定の面")
	_measure()
	for ln in LINES:
		_say(ln[0])
		for run in [false, true]:
			_say(await _pass("行き", ln[1], ln[2], ln[3], run))
			_say(await _pass("帰り", ln[2], ln[1], ln[3], run))
	_say("つまずき・ずれ: %d" % bad)
	var f := FileAccess.open(_dir().path_join("window_post_walk.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(1 if bad > 0 else 0)
