extends SceneTree
## 紙の体の湿り気（damp.gd の段）で、押して登る速さがどう変わるかを測る（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/push_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge
##     [--people=1,2,4] [--ks=0.7,0.85,1,1.12,1.25]
## ふもと（頂上から 36 m）に頂上を向けて置いたソリを、人数ぶんの押す人がソリの後ろから頂上へ押し続ける（力の倍率 k）。
## 頂上から 4 m まで登る時間、いちばん遅かった速さとその所の傾き、止まってしまったか（3 秒ほぼ動かない）を出す。
## 押す人は形だけ（sled.push に渡す人）。人の歩く速さは入れない（押す力だけの違いを見る）

const DUMMY_SRC := """extends Node3D
"""
const FROM := 36.0
const TO := 4.0
const LIMIT := 150.0

var args := {}
var main: Node3D
var sled: RigidBody3D
var _dummy: GDScript
var _queue: Array = []
var _run := {}
var _rows: Array[String] = []
var _started := false
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()


## 頂上からの距離 z の、x = 0 の線での傾き（度）
func _slope(z: float) -> float:
	return rad_to_deg(atan((main.height(0, z - 0.5) - main.height(0, z + 0.5))))


func _physics_process(dt: float) -> bool:
	t += dt
	if main.sled == null:
		return false
	sled = main.sled
	if not _started:
		if t < 0.5:
			return false
		_started = true
		var steep := 0.0
		var at := 0.0
		for i in 400:
			var z := lerpf(TO, FROM, i / 399.0)
			if _slope(z) > steep:
				steep = _slope(z)
				at = z
		print("ソリ %s（%d kg）。登る線（x = 0、頂上から %d 〜 %d m）のいちばん急な所: 頂上から %.1f m、%.1f°" % [sled.kind, int(sled.kind_mass), int(FROM), int(TO), at, steep])
		for n in Array(String(args.get("people", "1,2,4")).split(",")).map(func(s): return int(s)):
			for k in Array(String(args.get("ks", "0.7,0.85,1,1.12,1.25")).split_floats(",")):
				_queue.append([n, k])
		_rows.append("| ソリ | 押す人 | 力の倍率 | 1 人の力 (N) | 登る時間 (s) | 平均の速さ (m/s) | いちばん遅い速さ (m/s) | その所（頂上から m, 傾き°） |")
		_rows.append("|---|---|---|---|---|---|---|---|")
		return false
	if _run.is_empty():
		if _queue.is_empty():
			print("\n".join(_rows))
			quit()
			return true
		var job: Array = _queue.pop_front()
		sled.reset_to(Vector3(0, main.height(0, FROM) + 0.3, FROM))
		sled.rotation.y = 0.0   # 前（-Z）を頂上へ
		sled.parked = false
		var ps := []
		for i in job[0]:
			var d := Node3D.new()
			d.set_script(_dummy)
			main.add_child(d)
			ps.append(d)
		_run = {"n": job[0], "k": job[1], "ps": ps, "t": 0.0, "min": INF, "min_z": 0.0, "still": 0.0, "z": FROM}
		return false
	var r := _run
	r.t += dt
	var p := sled.global_position
	# 後ろの縁を、人数ぶん横に並んで頂上（-Z）へ押す
	var n: int = r.n
	for i in n:
		var x: float = (i - (n - 1) / 2.0) / maxf(n, 1.0) * sled.HALF.x * 1.6
		var at: Vector3 = sled.to_global(Vector3(x, 0.2, sled.HALF.y))
		sled.push(Vector3(0, 0, -1), at, r.ps[i], r.k)
	var v := sled.linear_velocity.length()
	var z := p.z
	if r.t > 3.0 and z < FROM - 1.0 and z > TO + 1.0 and v < r.min:
		r.min = v
		r.min_z = z
	r.still = r.still + dt if v < 0.05 and r.t > 3.0 else 0.0
	var done := z <= TO
	if done or r.still > 3.0 or r.t > LIMIT:
		var climbed := FROM - z
		var time := "%.1f" % r.t if done else ("止まった（%.1f m 登って）" % climbed if r.still > 3.0 else "%d 秒で %.1f m" % [int(LIMIT), climbed])
		_rows.append("| %s | %d | ×%.2f | %d | %s | %.2f | %.2f | %.1f m, %.1f° |" % [sled.kind, n, r.k, int(sled.PUSH_FORCE * r.k), time,
			climbed / r.t, r.min if r.min != INF else 0.0, r.min_z, _slope(r.min_z)])
		for d in r.ps:
			sled.release_handle(d)
			d.queue_free()
		_run = {}
	return false
