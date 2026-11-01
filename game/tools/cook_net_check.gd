extends SceneTree
## 通信の確かめ: つなぐ側の人が厨房の装置で調理したとき、仕上がりが手に戻るか（cook_station.gd・craft.gd。数字だけ出す）。
##   Godot --headless --path game -s res://tools/cook_net_check.gd -- --host --port=24741 --bots=0 --no-sound
##   Godot --headless --path game -s res://tools/cook_net_check.gd -- --join=127.0.0.1 --port=24741 --bots=0 --no-sound
## つながってから:
##   A（1 秒〜）  つなぐ側がラーメン（乾燥機だけ）を買って乾燥機で調理する。両方の画面で、装置のようすと、つなぐ側の人の持ち物を出す
##   B（12 秒〜） つなぐ側の持ち物をいっぱいにしてから、もう一度調理する。仕上がりは装置に残り、1 つ空けて F で受け取れるか
##   C（26 秒〜） ホストが調理する（前からの道がこわれていないか）

const Food := preload("res://food.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var st: Node
var _t0 := 0
var _other := -1


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


## 乾燥機の前に立つ（side で横へずらす）
func _front(side: float) -> void:
	var dev: Node3D = st.get_parent()
	var slot := dev.get_parent() as Node3D
	var fw: Vector3 = slot.global_basis.z
	fw.y = 0
	fw = fw.normalized()
	p.global_position = dev.global_position + fw * 2.0 + fw.cross(Vector3.UP) * side + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO


## つなぐ側の人の番号（ホストの画面では相手、つなぐ側では自分）
func _joiner() -> int:
	return _other if args.has("host") else p.id


func _bag(who: int) -> String:
	var names := []
	for it in main.craft.bag(who):
		names.append("-" if it.is_empty() else "%s%d" % [it.get("dish", it.get("kind")), int(it.get("step", 0))])
	return "手 %d [%s]" % [main.craft.hands.get(who, -1), ", ".join(names)]


func _station() -> String:
	return "装置: 調理の人 %d 入っている物 %s 仕上がり %s" % [st.who, st.item.get("dish", "-"), st.result.get("dish", "-")]


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
	_other = int(main.net.remotes.keys()[0])
	for s in main.stations:
		if s.kind == "dryer":
			st = s
	var host := args.has("host")
	_front(-1.0 if host else 1.0)
	if host:
		main.emotes.balls[_other] = 200   # つなぐ側の人の雪玉（ホストが払いを確かめる）
		main.emotes.balls[p.id] = 200
	await _wait(1.0)
	# A: つなぐ側がラーメンを買って乾燥機で調理する
	if not host:
		_say("ラーメンを買う: %s" % main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")}))
		await _wait(0.6)
		_say("買ったあと %s 手に %s 使えるか %s" % [_bag(p.id), p.held().get("dish", "-"), st.can_use(p)])
		_say("調理を始める: %s" % st.use(p))
	for i in 9:
		await _wait(1.0)
		_say("%s / つなぐ側の %s" % [_station(), _bag(_joiner())])
	var held: Dictionary = main.craft.held(_joiner())
	_say("A の結果: つなぐ側の手に %s（ramen の step 1 なら仕上がりが戻った）" % [held])
	await _wait(1.0)
	# B: 持ち物がいっぱいのときは装置に残り、空けて F で受け取る
	if not host:
		_say("ラーメンを買う: %s" % main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")}))
		await _wait(0.6)
		var cook_slot: int = main.craft.hands.get(p.id, -1)
		for i in 20:   # 持ち物がいっぱいになるまで買う
			if main.craft.free_slot(p.id) < 0:
				break
			main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")})
			await _wait(0.4)
		main.craft.send({"kind": "hand", "who": p.id, "slot": cook_slot})
		await _wait(0.4)
		_say("いっぱい %s" % _bag(p.id))
		_say("調理を始める: %s" % st.use(p))
		await _wait(0.6)
		main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")})   # 抜けた枠も埋める
		await _wait(0.6)
		_say("調理のあいだに買い足した %s" % _bag(p.id))
		await _wait(7.0)
		_say("仕上がったあと %s / %s（装置に残るはず）" % [_station(), _bag(p.id)])
		var drop := -1
		for i in main.craft.bag(p.id).size():
			if i != main.craft.hands.get(p.id, -1) and not main.craft.bag(p.id)[i].is_empty():
				drop = i
		main.craft.send({"kind": "drop", "who": p.id, "slot": drop})
		await _wait(0.5)
		_say("1 つ捨てた %s 受け取れるか %s（true のはず）" % [_bag(p.id), st.can_use(p)])
		_say("F で受け取る: %s" % st.use(p))
		await _wait(1.5)
		_say("B の結果: %s / %s" % [_station(), _bag(p.id)])
	else:
		for i in 16:
			await _wait(1.0)
			_say("%s / つなぐ側の %s" % [_station(), _bag(_other)])
	await _wait(1.0)
	# C: ホストが調理する
	if host:
		_say("ラーメンを買う: %s" % main.craft.send({"kind": "food_buy", "who": p.id, "item": Food.item("ramen")}))
		await _wait(0.3)
		_say("調理を始める: %s" % st.use(p))
	for i in 8:
		await _wait(1.0)
		_say("%s / ホストの %s" % [_station(), _bag(1)])
	_say("C の結果: ホストの手に %s" % [main.craft.held(1)])
	await _wait(1.0)
	quit()
