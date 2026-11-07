extends SceneTree
## ジャンプ台から飛ぶともらえるボタン（snow_buttons.gd の ride_jump）の確かめ（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/jump_pay_check.gd -- --sled=mid --no-player --bots=0 --no-sound [--riders=1] [--speeds=6,12,18]
## 大きな山の 1 つ目の台と、大山の 1 つ目の台へ、14 m 手前から入れる。1 回ごとに: 宙の時間、もらえる分、縫い込まれた素材。
## そのあと、同じ台へすぐもう一度（もらえない）、台の脇を通す（もらえない）、20 秒あけてもう一度（もらえる）を確かめる。

const Mountain := preload("res://mountain.gd")
const Grand := preload("res://grand_mountain.gd")
const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var sb: Node3D
var t := 0.0
var _dummy: GDScript
var _riders: Array = []
var _queue: Array = []
var _cur := {}
var _jumps: Array = []
var _sewn: Array = []
var _started := false
var _bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null or main.snow_buttons == null or t < 0.5:
		return false
	if not _started:
		_started = true
		sled = main.sled
		sb = main.snow_buttons
		sb.auto = false
		sb.clear()
		sb.happened.connect(func(ev: Dictionary) -> void:
			if ev.kind == "ride_jump":
				_jumps.append(ev)
			elif ev.kind == "ride_mark":
				_sewn.append(ev.look))
		for i in int(args.get("riders", "1")):
			var r := Node3D.new()
			r.set_script(_dummy)
			r.sled = sled
			main.add_child(r)
			sled.mount(r)
			_riders.append(r)
		var m := Mountain.kicker(0)
		var g := Grand.kicker(0)
		for v in Array(args.get("speeds", "6,12,18").split_floats(",")):
			_queue.append({"name": "大きな山", "k": m, "v": v, "pay": true, "before": 21.0})
		_queue.append({"name": "大山", "k": g, "v": 12.0, "pay": true, "before": 21.0})
		_queue.append({"name": "大山・すぐもう一度", "k": g, "v": 12.0, "pay": false})
		_queue.append({"name": "大きな山・台の脇を通す", "k": Mountain.kicker(1), "v": 12.0, "off": 7.0, "pay": false})
		_queue.append({"name": "大山・21 秒あけて", "k": g, "v": 12.0, "pay": true, "before": 21.0})
		return false
	if _cur.is_empty():
		if _queue.is_empty():
			print("ジャンプ台のボタン %s（%s 人）: 食い違い %d 回" % [sled.kind, args.get("riders", "1"), _bad])
			quit()
			return true
		_cur = _queue.pop_front()
		_cur.t = -float(_cur.get("before", 0.0))
		return false
	_cur.t += dt
	if sled.kind == "sack" and _cur.has("in") and not _riders.is_empty():   # 米袋は漕いで飛ぶ（漕がないと縁を乗り越えるだけ）
		var d: Vector2 = Vector2(sled.global_position.x, sled.global_position.z) - (_cur.k.lip as Vector2)
		if d.dot(_cur.k.f) < -Mountain.KICK_L and Engine.get_physics_frames() % 6 == 0:
			sled.kick(_riders[0])
	if not _cur.has("in") and _cur.t >= 0.0:
		_cur.in = true
		_jumps.clear()
		_sewn.clear()
		sb._runs.erase(sled)   # 置き直すので、前の滑りは続けない
		var k: Dictionary = _cur.k
		var f: Vector2 = k.f
		var at: Vector2 = (k.lip as Vector2) - f * (Mountain.KICK_L + 14.0) + Vector2(-f.y, f.x) * float(_cur.get("off", 0.0))
		var y: float = main.height(at.x, at.y)
		var ahead := at + f
		var d := Vector3(f.x, main.height(ahead.x, ahead.y) - y, f.y).normalized()
		sled.reset_to(Vector3(at.x, y + 0.3, at.y))
		sled.global_transform = Transform3D(Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP), sled.global_position)
		sled.parked = false
		sled.linear_velocity = d * float(_cur.v)
		sled.angular_velocity = Vector3.ZERO
		for r in _riders:
			if not sled.riders.has(r):
				sled.mount(r)
	if _cur.has("in") and _cur.t >= 6.0:
		var got := not _jumps.is_empty()
		var line := "%s %2.0f m/s:" % [_cur.name, _cur.v]
		if got:
			var counts := {}
			for l in _sewn:
				counts[l] = counts.get(l, 0) + 1
			line += " 宙 %.2f 秒、もらえる分 %.1f、縫い込み %s" % [_jumps[0].air, _jumps[0].value, counts]
		else:
			line += " もらえない"
		if got != bool(_cur.pay):
			_bad += 1
			line += "（食い違い）"
		print(line)
		_cur = {}
	return false
