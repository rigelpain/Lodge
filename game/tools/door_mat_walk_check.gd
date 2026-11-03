extends SceneTree
## 出入り口のマット（lodge/dims.py の DOORMATS）の上を歩いて・走って通り、つまずきと足音を数える（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 60 -s res://tools/door_mat_walk_check.gd -- --bots=0 --lodge-bots=0 --no-pip --dir=/path/out
## マットごとに、戸から離れた所からマットを越えて戸の手前まで（縦）と、マットの両の縁を横切る線（横）を、本物の W キー（走るは Shift も）で行き来する。
## つまずきの数え方は tools/sign_walk_check.gd と同じ（着かない・6 割より遅いのが 0.1 秒より長い・1 コマで 10 cm より持ち上がる・落ちる）。
## 足音: 鳴った一歩ごとに、その時の足もとの床（audio.gd の surface_at）と鳴った音を数える。マットの上で雪の音が鳴る、
## または線の 4 回でマットの上の足音が 1 歩もなければ「ずれ」。
## <dir>/door_mat_walk.txt に書く。つまずき・ずれが 1 つでもあれば、終わりの番号を 1 にする

const WALK := 2.0
const RUN := 3.4
const POP := 0.04
const DROP := 0.06
const SLOW := 0.6
const SLOW_T := 0.1
const FL1 := 0.45
const FL2 := 6.1

# [名前, 始め (x, y), 終わり (x, y), 床の高さ（光線を落とし始める高さの目安）]。ロッジの座標
const LINES := [
	["自動ドア・中 縦", Vector2(-13.39, -8.5), Vector2(-13.39, -12.1), FL1],
	["自動ドア・中 横", Vector2(-16.3, -11.3), Vector2(-10.5, -11.3), FL1],
	["風除室のマット 縦", Vector2(-13.39, -16.9), Vector2(-13.39, -13.3), FL1],
	["アーチ・外 縦", Vector2(-13.39, -21.5), Vector2(-13.39, -17.95), FL1],
	["アーチ・外 横", Vector2(-16.3, -18.6), Vector2(-10.5, -18.6), FL1],
	["勝手口・中 縦", Vector2(11.9, 8.6), Vector2(11.9, 12.2), FL1],
	["勝手口・中 横", Vector2(10.2, 11.6), Vector2(14.2, 11.6), FL1],
	["勝手口・外 縦", Vector2(11.9, 16.8), Vector2(11.9, 13.4), 0.0],
	["勝手口・外 横", Vector2(9.4, 13.5), Vector2(14.4, 13.5), 0.0],
	["西の戸・中 縦", Vector2(-17.8, 11.45), Vector2(-21.4, 11.45), FL1],
	["西の戸・中 横", Vector2(-20.9, 8.6), Vector2(-20.9, 12.2), FL1],
	["西の戸・外 縦", Vector2(-26.0, 11.45), Vector2(-22.55, 11.45), 0.0],
	["西の戸・外 横", Vector2(-22.75, 8.6), Vector2(-22.75, 12.6), 0.0],
	["テラスへの戸・中 横", Vector2(-10.95, 0.2), Vector2(-10.95, 5.4), FL2],
	["テラスへの戸・外 縦", Vector2(-15.0, 3.27), Vector2(-12.4, 3.27), FL2],
	["テラスへの戸・外 横", Vector2(-12.7, 0.6), Vector2(-12.7, 6.0), FL2],
]

var args := {}
var main: Node3D
var lodge: Node3D
var audio: Node
var p: CharacterBody3D
var lines: Array[String] = []
var bad := 0
var steps := {}   # 床 → {音の種類: 数}
var mat_steps := 0   # 線ごとの、マットの上で鳴った足音の数（線の 4 回で 1 歩もなければ、マットを見分けていない「ずれ」）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/door_mat_walk")


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
	var pops := 0
	var pop_max := 0.0
	var drops := 0
	var ok := false
	var stall := 0.0
	var total := Vector2(goal.x - start.x, goal.z - start.z).length()
	var heard: int = audio.played.size()
	var on_mat := 0
	var mat_snow := 0
	while t < 12.0:
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
		if dy > POP:
			pops += 1
			pop_max = maxf(pop_max, dy)
		elif dy < -DROP:
			drops += 1
		stall = stall + dt if hv < 0.05 else 0.0
		last = now
		while heard < audio.played.size():   # この一歩の床と音
			var e: Dictionary = audio.played[heard]
			heard += 1
			if not e.near or not String(e.name).begins_with("step_"):
				continue
			var surf: String = audio.surface_at(now, p)
			var kind := "雪" if String(e.name).begins_with("step_snow") else "木"
			var c: Dictionary = steps.get(surf, {})
			c[kind] = c.get(kind, 0) + 1
			steps[surf] = c
			if surf == "mat":
				on_mat += 1
				if kind == "雪":
					mat_snow += 1
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
		why = "  止まった所 x=%.2f y=%.2f 高さ %.2f、当たった物 %s、W %s" % [at.x, -at.z, at.y, hits, Input.is_physical_key_pressed(KEY_W)]
	await _key(KEY_W, false)
	if run:
		await _key(KEY_SHIFT, false)
	var trip := not ok or pop_max > 0.1 or drops > 0 or slow_t > SLOW_T
	if trip:
		bad += 1
	if mat_snow > 0:
		bad += 1
	mat_steps += on_mat
	return "  %s %s: %s  遅い所 %.0f%%（%.2f 秒）  持ち上がり %d 回（いちばん %.1f cm）  落ち %d 回  マットの上の足音 %d 歩（雪の音 %d）%s" % [name,
			"走る" if run else "歩く", "着いた" if ok else "止まった", slowest * 100.0, slow_t, pops, pop_max * 100.0, drops, on_mat, mat_snow,
			"  ← つまずき" + why if trip else ("  ← ずれ" if mat_snow > 0 else "")]


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	lodge = main.get_node("Lodge")
	audio = main.get_node_or_null("Audio")
	if audio == null:
		print("音がない（--no-sound を付けない）")
		quit(1)
		return
	audio.log_on = true
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)
	for ln in LINES:
		_say(ln[0])
		mat_steps = 0
		for run in [false, true]:
			_say(await _pass("行き", ln[1], ln[2], ln[3], run))
			_say(await _pass("帰り", ln[2], ln[1], ln[3], run))
		if mat_steps == 0:
			bad += 1
			_say("  ← ずれ: マットの上の足音が 1 歩もない")
	_say("足もとの床ごとの足音（木 / 雪）")
	for surf in steps:
		_say("  %s: 木 %d / 雪 %d" % [surf, steps[surf].get("木", 0), steps[surf].get("雪", 0)])
	_say("つまずき・ずれ: %d" % bad)
	var f := FileAccess.open(_dir().path_join("door_mat_walk.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(1 if bad > 0 else 0)
