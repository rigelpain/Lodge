extends SceneTree
## 通信の確かめ: 山男（mountain_man.gd）がどの画面にもいて、山男の棚で買った物（craft.gd の buy）がほかの画面にも配られ、
## 山男が買った人を向くか（数字だけ出す）。両方 --shelf-all で、まだ売っていない品目も売る。
##   Godot --headless --path game -s res://tools/mountain_net_check.gd -- --host --port=24741 --bots=0 --no-sound --shelf-all
##   Godot --headless --path game -s res://tools/mountain_net_check.gd -- --join=127.0.0.1 --port=24741 --bots=0 --no-sound --shelf-all
## つながってから:
##   A（1 秒〜）  山男の位置を出す（どの画面も同じ所のはず）。つなぐ側が売り場で焚き火セットを買う。
##                ホストは、相手の持ち物と財布、山男が見ている人（相手の体のはず）を出す
##   B（5 秒〜）  ホストがペグを買う。つなぐ側が同じことを出す
##   C（9 秒〜）  両方で「まだ売っていない」に戻し、つなぐ側が焚き火セットを買おうとする。ホストが断り、持ち物が増えないか

const Goods := preload("res://mountain_goods.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var mm: Node3D
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


func _items(who: int) -> Array:
	return main.craft.bag(who).filter(func(x): return not x.is_empty()).map(func(x): return x.kind)


func _other() -> Node3D:
	for pid in main.net.remotes:
		return main.net.remotes[pid]
	return null


func _looking_at() -> String:
	var b = mm.get("_buyer")
	if b == null or not is_instance_valid(b):
		return "だれも"
	return "自分" if b == p else ("相手（%d）" % int(b.get("id")) if b == _other() else str(b))


func _report_other() -> void:
	var o := _other()
	var who: int = int(o.get("id"))
	_say("相手 %d の持ち物 %s 財布 %d / 山男が見ている人: %s" % [who, _items(who), main.craft.wallet(who), _looking_at()])


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
	mm = main.mountain_man
	var host := args.has("host")
	var at := mm.to_global(Vector3(-0.8 if host else 0.8, 0.1, -1.9))
	p.global_position = at
	p.rotation.y = atan2(-(mm.global_position.x - at.x), -(mm.global_position.z - at.z))
	await _wait(1.0)
	# A: つなぐ側が買う
	_say("山男 %s 棚の品目 %d" % [mm.global_position.snapped(Vector3.ONE * 0.01), Goods.SHELF.size()])
	if not host:
		var near: bool = p.mountain_near()
		main.mountain_ui.open()
		main.mountain_ui.select(0)
		_say("話しかけられる %s / 焚き火セットを買う: %s" % [near, main.mountain_ui.buy()])
		main.mountain_ui.close()
		await _wait(1.0)
		_say("自分の持ち物 %s 財布 %d" % [_items(p.id), main.craft.wallet(p.id)])
	else:
		await _wait(1.0)
		_report_other()
	await _wait(2.5)
	# B: ホストが買う
	if host:
		main.mountain_ui.open()
		main.mountain_ui.select(1)
		_say("ペグを買う: %s" % main.mountain_ui.buy())
		main.mountain_ui.close()
		await _wait(1.0)
		_say("自分の持ち物 %s 財布 %d" % [_items(p.id), main.craft.wallet(p.id)])
	else:
		await _wait(1.5)
		_report_other()
	await _wait(2.5)
	# C: まだ売っていない品目は断られる
	Goods.all_on = false
	if not host:
		var before := _items(p.id).size()
		_say("売っていない焚き火セットを買う: %s（つなぐ側は送るだけなので true）" % main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "campfire"}}))
		await _wait(1.0)
		_say("持ち物の数 %d → %d（増えないはず）" % [before, _items(p.id).size()])
	else:
		await _wait(1.5)
		_report_other()
	await _wait(1.0)
	quit()
