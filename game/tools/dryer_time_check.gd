extends SceneTree
## 乾燥機に入ってから出るまでの長さの確かめ（数字だけ出す。design/damp.md の「乾燥機に入る」）。
##   Godot --headless --path game -s res://tools/dryer_time_check.gd -- --bots=0 --values=100,60,0
## 音は実時間でないと回らないので --fixed-fps は付けない。水 v ごとに F で入り、ひとりでに出るまでを 1 行ずつ出す:
##   秒（とび込み〜回る〜出きる）、出たときの水、回るあいだ鳴り続けた音の割合と音が頭へ戻った回数、胴と人形が動かなかったいちばん長いコマ、「ぽすっ」の数
## 最後に、人形ごとの体の物理（dryer_flop.gd）を長さいっぱい回して、壁に落ちる間がいちばん空いた所と、壁の外へ出ていないかを出す

const Doll := preload("res://doll.gd")
const DryerFlop := preload("res://dryer_flop.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var st: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(1.0).timeout
	p = main.player
	for s in main.stations:
		if s.kind == "dryer":
			st = s
	for v in String(args.get("values", "100,60,0")).split(","):
		await _one(float(v))
	_flops()
	quit()


## 水 v で F を押して入り、出るまで
func _one(v: float) -> void:
	p.global_position = st.stand_point() + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO
	var d: Vector3 = st.get_parent().global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	await create_timer(0.3).timeout
	main.damp.put(p.id, v)
	if not st.ride(p):
		print("水 %.0f: 入れなかった" % v)
		return
	var last_f := -1
	var heard := 0            # 回るあいだの音が 2 つとも鳴っていたコマ
	var spun := 0             # 回るあいだのコマ
	var wraps := {}           # 音 → 頭へ戻った回数
	var heads := {}           # 音 → 前の再生位置
	var still := 0            # 人形と胴が同じ形のまま続いたコマ
	var still_max := 0
	var lands := 0
	var prev_spin := INF
	var prev_shake := Transform3D()
	while st.rider == p.id or p.mode == p.Mode.DRUM:
		await process_frame
		var f := Doll.frame_index()
		if f == last_f or st._ride_f < 0:
			continue
		last_f = f
		var k: int = f - st._ride_f - st.RIDE_IN
		if k < 1 or (st._out_f >= 0 and f >= st._out_f):
			continue
		spun += 1
		var on := 0
		for a in st._ride_snd:
			if is_instance_valid(a) and a.playing:
				on += 1
				var pos: float = a.get_playback_position()
				var key: String = a.stream.resource_path if a.stream.resource_path != "" else str(a.stream.get_instance_id())
				if heads.has(key) and pos + 0.5 < heads[key]:
					wraps[key] = wraps.get(key, 0) + 1
				heads[key] = pos
		if on == 2:
			heard += 1
		var spin: float = st.ride_pose(f).spin
		var shake: Transform3D = st._dev.transform
		still = still + 1 if spin == prev_spin and shake == prev_shake else 0
		still_max = maxi(still_max, still)
		prev_spin = spin
		prev_shake = shake
		if st._flop and st._flop.at(k).land:
			lands += 1
	var inside: int = st._out_f - st._ride_f - st.RIDE_IN
	print("水 %4.0f → %4.0f | 入ってから出きるまで %5.1f 秒（とび込み %.2f・回る %.2f・とび出す %.2f）| 音 %d/%d コマ 頭へ戻った %d 回 | 止まったいちばん長い %d コマ | ぽすっ %d 回" % [
		v, main.damp.water_of(p.id), (inside + st.RIDE_IN + st.RIDE_OUT) / 12.0, st.RIDE_IN / 12.0, inside / 12.0, st.RIDE_OUT / 12.0,
		heard, spun, wraps.values().reduce(func(a, b): return a + b, 0), still_max, lands])


## 人形ごとに、RIDE_MAX のコマまで体の物理を回す
func _flops() -> void:
	for kind in Doll.KINDS:
		var d: Doll = Doll.new()
		d.kind = kind
		root.add_child(d)
		var fl = DryerFlop.new(st.SPIN * 12.0, Vector2(st.HIP, 0.0), d.drum_extent())
		d.queue_free()
		var last := 0
		var gap := 0
		var far := 0.0
		var n := 0
		for k in st.RIDE_MAX + 1:
			var s: Dictionary = fl.at(k)
			if s.land:
				gap = maxi(gap, k - last)
				last = k
				n += 1
			far = maxf(far, (s.p as Vector2).length())
		gap = maxi(gap, st.RIDE_MAX - last)
		print("%-8s 倍 %.2f | %d コマで ぽすっ %d 回、いちばん空いた %.1f 秒 | 足もとが胴の真ん中から最大 %.2f m（壁 %.2f m）" % [kind, fl.fit, st.RIDE_MAX, n, gap / 12.0, far, DryerFlop.INNER])
