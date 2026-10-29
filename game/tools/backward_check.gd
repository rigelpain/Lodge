extends SceneTree
## 後ろ向きに滑っているときの、乗ったままの W（雪をかく）と米袋の Space（漕ぐ）の効きを測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/backward_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge
## 頂上の少し下（z = 3）に置き、前向き（ソリの前をふもと +z へ）と後ろ向き（前を頂上へ）で比べる。乗る人は 1 人（--riders=で変える）。
##   雪をかく（--sled=mid など）: 0.6 m/s でふもとへ少し押し出し、乗っている人が W（前傾）を押し続ける。
##       1.5 m/s・3 m/s（水平の速さ。置いて 0.3 秒は雪に落ち着くので数えない）に届くまでの時間と、4 秒後の速さ。止まった所（0 m/s）からも
##   漕ぐ（--sled=sack）: 2 m/s で押し出し、1 秒に 0・6・10 回 Space で漕ぐ（ふもとの平らな所、高さ 1 m より下ではやめる）。
##       いちばん速い所と、滑った分の真鍮（snow_buttons.gd の ride_pay。10・13 m/s を超えるたびに 1）
## 押し出す向きはどれも +z（ふもと）。後ろ向きはソリの前が頂上（-z）を向いたまま後ろへ、横向きはソリの前を横（-x）へ向けたまま横へ滑り出す。

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
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _paid := {}
var t := 0.0
var _started := false


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
	if main.sled == null:
		return false
	sled = main.sled
	if t < 0.5:
		return false
	if not _started:
		_started = true
		if main.snow_buttons:
			main.snow_buttons.auto = false
			main.snow_buttons.clear()
			main.snow_buttons.happened.connect(func(ev: Dictionary) -> void:
				if ev.kind == "ride_pay":
					_paid = ev)
		for face in ["前向き", "後ろ向き", "横向き"]:
			if sled.kind == "sack":
				for rate in [0, 6, 10]:
					_queue.append({"face": face, "rate": rate, "v0": 2.0})
			else:
				_queue.append({"face": face, "rate": 0, "v0": 0.6, "scoop": true})
				if face != "横向き":
					_queue.append({"face": face, "rate": 0, "v0": 0.0, "scoop": true})
		if sled.kind == "sack":
			_rows.append("| ソリ | 向き | 連打（回/秒） | いちばん速い所 | 滑った長さ | 真鍮 |")
			_rows.append("|---|---|---|---|---|---|")
		else:
			_rows.append("| ソリ | 向き | 押し出し | 1.5 m/s まで | 3 m/s まで | 4 秒後の速さ |")
			_rows.append("|---|---|---|---|---|---|")
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return true
		var q: Dictionary = _queue.pop_front()
		sled.reset_to(Vector3(0, main.height(0, 3.0) + 0.3, 3.0))
		sled.rotation.y = {"前向き": PI, "後ろ向き": 0.0, "横向き": PI / 2}[q.face]
		sled.parked = false
		sled.linear_velocity = Vector3(0, 0, q.v0)
		var rs := []
		for i in int(args.get("riders", "1")):
			var d := Node3D.new()
			d.set_script(_dummy)
			d.sled = sled
			main.add_child(d)
			sled.mount(d)
			rs.append(d)
		_paid = {}
		_run = q.merged({"rs": rs, "t": 0.0, "t15": -1.0, "t3": -1.0, "v4": -1.0, "best": 0.0, "next": 0.0})
		return false
	var r := _run
	r.t += dt
	var v := sled.linear_velocity.length()
	r.best = maxf(r.best, v)
	var hv := Vector2(sled.linear_velocity.x, sled.linear_velocity.z).length()   # 置いた直後に雪へ落ち着く分（縦）を入れない
	if r.get("scoop", false):
		for d in r.rs:
			sled.lean(0.0, true)
		if r.t > 0.3 and r.t15 < 0.0 and hv >= 1.5:
			r.t15 = r.t
		if r.t > 0.3 and r.t3 < 0.0 and hv >= 3.0:
			r.t3 = r.t
		if r.v4 < 0.0 and r.t >= 4.0:
			r.v4 = hv
		if r.t >= 4.0:
			_rows.append("| %s | %s | %.1f m/s | %s | %s | %.1f m/s |" % [sled.kind, r.face, r.v0,
					("%.1f 秒" % r.t15) if r.t15 >= 0.0 else "届かない", ("%.1f 秒" % r.t3) if r.t3 >= 0.0 else "届かない", r.v4])
			_end()
		return false
	if r.rate > 0 and sled.global_position.y > 1.0:
		r.next -= dt
		if r.next <= 0.0:
			r.next = 1.0 / float(r.rate)
			sled.kick(r.rs[0])
	if not _paid.is_empty() or r.t > 60.0:
		_rows.append("| %s | %s | %d | %.1f m/s | %.0f m | %d |" % [sled.kind, r.face, r.rate, r.best,
				float(_paid.get("dist", 0.0)), int(_paid.get("brass", 0))])
		_end()
	return false


func _end() -> void:
	for d in _run.rs:
		sled.dismount(d)
		d.queue_free()
	_run = {}
