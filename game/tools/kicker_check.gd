extends SceneTree
## 大きな山のジャンプ台（mountain.gd の KICKERS）で、ソリがちゃんと飛んで、着地で地面をすり抜けないかの確かめ（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/kicker_check.gd -- --sled=KIND --no-player --bots=0 --no-sound
##     [--kick=0,1]      調べるジャンプ台（既定は全部）
##     [--speeds=6,9,12] 踏み切りの 14 m 手前で入れる速さ (m/s)
##     [--offsets=0]     踏み切りの坂のまんなかから横へずらして入れる (m)。いくつも渡すと、その数だけ回す
##     [--riders=1]      乗せる人の数
##     [--kicks=10]      踏み切りの坂の手前まで、1 秒にこの回数蹴り続ける（米袋用。蹴れるのは下りだけ）
##     [--trace]         1 回ごとに、5 コマおきの様子（縁からの位置・速さ・下の面からの高さ）も出す
## 1 回ごとに: 踏み切りの縁での速さ、宙にいた時間、飛んだ長さ（水平）、いちばん高く浮いた高さ（下の雪面から）、
## 着地のあと 2 秒のうちにいちばん雪面より下へ沈んだ量（すり抜け = 1 m 以上）、ひっくり返ったか

const Mountain := preload("res://mountain.gd")
const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var sled: RigidBody3D
var t := 0.0
var _queue: Array = []
var _cur := {}
var _rows: Array[String] = []
var _dummy: GDScript
var _started := false
var _bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


## 真下の面（雪面かジャンプ台）の高さ
func _surface(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 40.0)
	q.exclude = [sled.get_rid()]
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else main.height(p.x, p.z)


## いまソリが触れている物の名前（--trace 用）
func _touching() -> PackedStringArray:
	var out := PackedStringArray()
	var st := PhysicsServer3D.body_get_direct_state(sled.get_rid())
	for i in st.get_contact_count():
		var o: Object = st.get_contact_collider_object(i)
		var nm: String = ((o as Node).name if o is Node else "?") + str(st.get_contact_local_normal(i).snapped(Vector3.ONE * 0.1))
		if not out.has(nm):
			out.append(nm)
	return out


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null or t < 0.5:
		return false
	if not _started:
		_started = true
		sled = main.sled
		_dummy = GDScript.new()
		_dummy.source_code = DUMMY_SRC
		_dummy.reload()
		var kicks := range(Mountain.KICKERS.size())
		if args.has("kick"):
			kicks = Array(args["kick"].split_floats(",")).map(func(v): return int(v))
		var speeds: Array = Array(args.get("speeds", "6,9,12").split_floats(","))
		var offs: Array = Array(args.get("offsets", "0").split_floats(","))
		for k in kicks:
			for v in speeds:
				for o in offs:
					_queue.append({"kick": k, "v": v, "off": o})
		return false
	if _cur.is_empty():
		if _queue.is_empty():
			print("%s（%s 人%s）: %d 回のうち、すり抜け・ひっくり返り %d 回" % [sled.kind, args.get("riders", "1"), ("、1 秒に %s 回蹴る" % args["kicks"]) if args.has("kicks") else "", _rows.size(), _bad])
			for r in _rows:
				print("  " + r)
			quit()
			return true
		_cur = _queue.pop_front()
		_start(_cur)
		return false
	_step(_cur, dt)
	return false


func _start(c: Dictionary) -> void:
	var k := Mountain.kicker(c.kick)
	var lip: Vector2 = k.lip
	var f: Vector2 = k.f
	var at := lip - f * (Mountain.KICK_L + 14.0) + Vector2(-f.y, f.x) * float(c.off)
	var y: float = main.height(at.x, at.y)
	var ahead := at + f
	var d := Vector3(f.x, main.height(ahead.x, ahead.y) - y, f.y).normalized()
	sled.reset_to(Vector3(at.x, y + 0.3, at.y))
	sled.global_transform = Transform3D(Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP), sled.global_position)
	sled.parked = false
	sled.linear_velocity = d * float(c.v)
	sled.angular_velocity = Vector3.ZERO
	if args.has("trace"):
		sled.contact_monitor = true
		sled.max_contacts_reported = 8
	c.riders = []
	for i in int(args.get("riders", "1")):
		var r := Node3D.new()
		r.set_script(_dummy)
		r.sled = sled
		main.add_child(r)
		sled.mount(r)
		c.riders.append(r)
	c.t = 0.0
	c.next_kick = 0.0
	c.lip = lip
	c.f = f
	c.v_lip = -1.0
	c.air = -1.0
	c.peak = 0.0
	c.low = 1e9
	c.flip = false


func _step(c: Dictionary, dt: float) -> void:
	c.t += dt
	var p := sled.global_position
	var f: Vector2 = c.f
	var along := (Vector2(p.x, p.z) - (c.lip as Vector2)).dot(f)
	if c.v_lip < 0.0 and along > 0.0:
		c.v_lip = sled.linear_velocity.length()
	var clear := p.y - _surface(p)
	if args.has("kicks") and along < -Mountain.KICK_L:
		c.next_kick -= dt
		if c.next_kick <= 0.0:
			c.next_kick += 1.0 / float(args["kicks"])
			sled.kick(c.riders[0])
	if args.has("trace") and int(c.t * 60.0) % 5 == 0:
		var side_off := (Vector2(p.x, p.z) - (c.lip as Vector2)).cross(f)
		var pitch := rad_to_deg(asin(clampf(-sled.global_basis.z.y, -1.0, 1.0)))
		print("  t=%.2f 縁から %.1f m 横 %.2f m 速さ %.1f m/s 下の面から %.2f m 前の上がり %.0f° 当たり %s" % [c.t, along, side_off,
				sled.linear_velocity.length(), clear, pitch, ",".join(_touching())])
	if c.v_lip >= 0.0 and c.air < 0.0 and clear > 0.35:
		c.air = 0.0
		c.from = Vector2(p.x, p.z)
	elif c.air >= 0.0 and not c.has("land"):
		if clear > 0.35:
			c.air += dt
			c.peak = maxf(c.peak, clear)
		else:
			c.land = Vector2(p.x, p.z)
			c.land_t = c.t
			c.v_land = sled.linear_velocity
	if c.has("land"):
		c.low = minf(c.low, p.y - main.height(p.x, p.z))
		if sled.global_basis.y.y < 0.2:
			c.flip = true
	if (c.has("land") and c.t > c.land_t + 2.0) or c.t > 9.0:
		var dist: float = (c.land - c.from).length() if c.has("land") and c.air >= 0.0 else 0.0
		var bad: bool = c.low < -1.0 or c.flip
		if bad:
			_bad += 1
		var vl: Vector3 = c.get("v_land", Vector3.ZERO)
		_rows.append("K%d %2.0f m/s・横 %+.1f m で入れる → 縁で %.1f m/s、宙 %.2f 秒、飛んだ長さ %.1f m、いちばん高く %.1f m、着地の速さ 下へ %.1f m/s、沈み %.2f m%s" % [
				c.kick + 1, c.v, c.off, c.v_lip, maxf(c.air, 0.0), dist, c.peak, -vl.y, c.low if c.low < 1e8 else 0.0,
				"（すり抜け）" if c.low < -1.0 else ("（ひっくり返った）" if c.flip else "")])
		for r in c.riders:
			sled.dismount(r)
			r.queue_free()
		_cur = {}
