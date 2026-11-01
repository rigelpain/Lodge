extends SceneTree
## 通信の確かめ: 装置の動く部品（cook_motion.gd）が、どの画面でも同じコマに同じ形になるか（数字だけ出す）。
##   Godot --headless --path game -s res://tools/cook_motion_net_check.gd -- --host --port=24735 --bots=0 --no-sound
##   Godot --headless --path game -s res://tools/cook_motion_net_check.gd -- --join=127.0.0.1 --port=24735 --bots=0 --no-sound
## つながってから:
##   A（1 秒〜）  つなぐ側が乾燥機に入る。両方の画面が、入ってからのコマ 8・12・20 で胴の向きと中の人の居場所を出す
##   B（8 秒〜）  ホストがラーメンのペレットを買って乾燥機で調理する。両方の画面が、調理のコマ 10・20 で胴の向きと中身の数を出す
##                （つなぐ側の画面でほかの人の調理が動くのは、PR #105 の「どの画面の装置も同じ調理をする」が入ってから）
## 同じ「コマ」の行の数字が、ホストとつなぐ側でそろっていればよい

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
	print("[%s] %s" % ["host" if args.has("host") else "join", s])


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _drum() -> String:
	var part: Node3D = st._mo.part
	var a := part.basis.get_euler() if part else Vector3.ZERO
	return "胴 (%.3f, %.3f, %.3f)" % [a.x, a.y, a.z]


func _bits() -> int:
	var b: Node3D = st._mo._bits
	return b.get_child_count() if b else 0


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	await _wait(0.5)
	var t0 := 0.0
	while main.net.remotes.is_empty() and t0 < 20.0:
		await _wait(0.5)
		t0 += 0.5
	await _wait(2.0)
	p = main.player
	for s in main.stations:
		if s.kind == "dryer":
			st = s
	var host := args.has("host")
	# A: つなぐ側が入る
	await _wait(1.0)
	if not host:
		p.global_position = st.stand_point() + Vector3.UP * 0.05
		await _wait(0.4)
		_say("入る: %s" % st.ride(p))
	while st.rider < 0:
		await process_frame
	for k in [8, 12, 20]:
		while Doll.frame_index() - st._ride_f < k:
			await process_frame
		var who: Node3D = st.rider_node
		var doll = who.get("doll") if who else null
		_say("入って %d コマ  %s  人の回った角 %.3f" % [k, _drum(), doll.spin if doll else -1.0])
	while st.riding():
		await process_frame
	_say("出た。胴 %s" % _drum())
	# B: ホストがラーメンを調理する
	await _wait(1.0)
	if host:
		main.emotes.balls[p.id] = 5   # 雪玉で払う
		main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")})
		await _wait(0.3)
		p.global_position = st.stand_point() + Vector3.UP * 0.05
		await _wait(0.4)
		_say("調理: %s" % st.use(p))
	var t := Time.get_ticks_msec()
	while st.who < 0 and Time.get_ticks_msec() - t < 4000:
		await process_frame
	if st.who < 0:
		_say("この画面では調理が動いていない")
		quit()
		return
	var start: int = st._start
	for k in [10, 20]:
		while st._k - start < k + st.FLY:
			await process_frame
		_say("調理 %d コマ  %s  中身 %d" % [k, _drum(), _bits()])
	await _wait(5.0)
	quit()
