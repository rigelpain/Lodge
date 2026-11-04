extends SceneTree
## 通信の確かめ: 厨房の乾燥機に入る・出る（cook_station.gd）が、ほかの画面でも同じに見え、ぶつからないか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/dryer_net_check.gd -- --host --port=24733 --bots=0 --no-sound
##   Godot --headless --path game -s res://tools/dryer_net_check.gd -- --join=127.0.0.1 --port=24733 --bots=0 --no-sound
## つながってから:
##   A（1 秒〜）  つなぐ側が乾燥機に入る。ホストは 3 秒あとに入ろうとして断られるか、相手の体が胴の真ん中で回っているかを出す
##   B（9 秒〜）  ホストが入る。つなぐ側が同じことを出す
##   C（17 秒〜） ホストがラーメンのペレットを買って乾燥機で調理する。つなぐ側は入ろうとして断られ、仕上がったあとは入れるか
## A・B の終わりに、入ってから出きるまでのコマと秒を出す（どちらの画面でも同じなら、相手も同じ長さに見える）

const Doll := preload("res://doll.gd")
const Food := preload("res://food.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var st: Node
var _t0 := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _say(s: String) -> void:
	print("[%s %.1f] %s" % ["host" if args.has("host") else "join", (Time.get_ticks_msec() - _t0) / 1000.0, s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


## 乾燥機の前に立つ（side で横へずらす。二人が重ならないように）
func _front(side: float) -> void:
	var fw: Vector3 = st.front()
	p.global_position = st.stand_point() + fw.cross(Vector3.UP) * side + Vector3.UP * 0.05
	var d: Vector3 = st.get_parent().global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)


## 相手の体のようす
func _watch(n: int) -> void:
	for i in n:
		for pid in main.net.remotes:
			var rp = main.net.remotes[pid]
			var off: Vector3 = rp.doll.global_position - st.drum_center()
			_say("中の人 %d（相手は %d） 相手のモード %d 胴の真ん中から %.2f m 回る角 %.2f 軸 %s" % [st.rider, rp.id, rp.mode, off.length(),
					rp.doll.spin, "あり" if rp.doll.spin_axis != Vector3.ZERO else "なし"])
		await _wait(0.5)


## 中の人が出きるまで待って、入ってから出きるまでのコマを出す（乾ききって出るまで 6 秒ほど）
func _measure(what: String) -> void:
	var t := 0.0
	var who: int = st.rider
	var in_f: int = st._ride_f
	var out_f: int = st._out_f
	while st.rider >= 0 and t < 40.0:
		out_f = st._out_f
		await _wait(0.1)
		t += 0.1
	var n: int = out_f + st.RIDE_OUT - in_f
	_say("%s: 中の人 %d 入ってから出きるまで %d コマ（%.1f 秒） 水 %.0f" % [what, who, n, n / 12.0, main.damp.water_of(who)])


func _run() -> void:
	await _wait(0.5)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 20.0:
		await _wait(0.5)
		t += 0.5
	if main.net.remotes.is_empty():
		_say("相手が来なかった")
		quit(1)
		return
	_t0 = Time.get_ticks_msec()
	p = main.player
	for s in main.stations:
		if s.kind == "dryer":
			st = s
	var host := args.has("host")
	_front(-1.0 if host else 1.0)
	main.damp.put(p.id, 100.0)
	await _wait(1.0)
	# A: つなぐ側が入る
	if not host:
		_say("入る: %s" % st.ride(p))
		for i in 8:
			await _wait(0.5)
			_say("自分のモード %d 水 %.0f 中の人 %d" % [p.mode, main.damp.water_of(p.id), st.rider])
	else:
		await _wait(3.0)   # 読み込みが遅いと、つなぐ側が入る前にホストが入ってしまう
		_say("相手が中にいるときに入る: %s（入れないはず）" % st.ride(p))
		await _watch(7)
	await _measure("A つなぐ側が入った")
	await _wait(1.0)
	_front(-1.0 if host else 1.0)
	# B: ホストが入る
	if host:
		_say("入る: %s" % st.ride(p))
		for i in 8:
			await _wait(0.5)
			_say("自分のモード %d 水 %.0f 中の人 %d" % [p.mode, main.damp.water_of(p.id), st.rider])
	else:
		await _wait(1.5)   # 時計は画面ごとに少しずれるので、ホストが先に入るまで待つ
		_say("相手が中にいるときに入る: %s（入れないはず）" % st.ride(p))
		await _watch(5)
	await _measure("B ホストが入った")
	await _wait(1.0)
	_front(-1.0 if host else 1.0)
	# C: ホストが乾燥機で調理する
	if host:
		main.emotes.balls[p.id] = 5
		_say("ラーメンを買う: %s 手に %s" % [main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")}), p.held()])
		await _wait(0.3)
		_say("調理を始める: %s" % st.use(p))
		await _wait(9.0)
		_say("手に %s" % p.held())
	else:
		await _wait(1.0)
		_say("相手が調理しているときに入れるか: %s / 入る: %s（どちらも false のはず）" % [st.can_ride(p), st.ride(p)])
		await _wait(8.0)
		_say("仕上がったあとに入れるか: %s（true のはず）" % st.can_ride(p))
	await _wait(1.0)
	quit()
