extends SceneTree
## 売り台で買う音・ミシンで縫う音・厨房の調理音を、ゲームの中で順に鳴らして書き出す（音の確かめ。2026-11-01）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/craft_sound_check.gd -- --bots=0 --no-pip
## 1. おじいさんの番台で、型紙（米袋）と布を買う（craft.gd の buy。audio.gd が出来事から拾って鳴らす）
## 2. 雪だるまの番台と 2 階の売り台の音（audio.gd の purchase を直に呼ぶ。売り場ができたら出来事から鳴る）
## 3. 買った型紙と布でミシンを縫う（craft.gd の sew → sewing_machine.gd の縫い始め・縫っている間・できあがり）
## 4. 厨房の 4 つの装置で、入れる → 動いている → できた（audio.gd の cook を直に呼ぶ）
## 鳴った音を、時刻・名前・聞く所からの距離で出す。ミシンの音はミシンの段の移り変わりを出す

var main: Node3D
var _t0 := 0.0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second) - _t0


func _wait(sec: float) -> void:
	var until := _now() + sec
	while _now() < until:
		await physics_frame


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	var audio = main.get_node_or_null("Audio")
	var craft = main.craft
	if p == null or audio == null or craft == null:
		print("あなた・音・工房のどれかがない（--no-player・--no-sound を付けない）")
		quit(1)
		return
	audio.log_on = true
	var sk: Node3D = main.shopkeeper
	p.global_position = sk.to_global(Vector3(0, 0.1, -1.9))
	await _wait(0.5)
	craft.wallets[p.id] = 230   # 小のソリの型紙（100）・布・2 階の小物が買えるように（米袋の型紙は縫い上げで player.gd が止まるので使わない）
	print("1. おじいさんの番台で買う（財布 %d）" % craft.wallets.get(p.id, 0))
	print("   型紙: ", craft.send({"kind": "buy", "who": p.id, "item": {"kind": "pattern", "sled": "small"}}))
	await _wait(2.5)
	print("   布: ", craft.send({"kind": "buy", "who": p.id, "item": {"kind": "fabric", "fabric": "red"}}))
	await _wait(2.5)
	print("2. 雪だるまの番台・2 階の売り台")
	audio.purchase("snow", p.global_position, 2)
	await _wait(2.5)
	audio.purchase("pal", p.global_position, 3, ["wood", "brass", "wood"])
	await _wait(2.5)
	print("3. ミシンで縫う")
	var sew = main.sewing
	sew.phase_changed.connect(func(n: String) -> void: print("   %.2f ミシン: %s" % [_now(), n]))
	var bag: Array = craft.bags[p.id]
	var ps := -1
	var fs := -1
	for i in bag.size():
		if bag[i].kind == "pattern":
			ps = i
		elif bag[i].kind == "fabric":
			fs = i
	if ps >= 0 and fs >= 0:
		print("   縫う: ", craft.send({"kind": "sew", "who": p.id, "pattern": bag[ps].duplicate(), "fabric": bag[fs].duplicate(),
				"pattern_slot": ps, "fabric_slot": fs}))
	await _wait(9.0)
	print("4. 厨房")
	var slot := main.get_node("Lodge").find_child("slot_food_kitchen", true, false) as Node3D
	var x := -3.0
	for dev in ["press", "iron", "dryer", "drink"]:
		var at: Vector3 = slot.global_position + Vector3(x, 0, 0) if slot else p.global_position
		x += 3.0
		audio.cook(dev, "in", at)
		await _wait(4.0)
		audio.cook(dev, "done", at)
		await _wait(2.0)
	print("鳴った音:")
	for e in audio.played:
		if String(e.name).begins_with("button_"):
			continue
		print("   %6.2f  %-24s %5.1f m" % [e.t - _t0, e.name, e.dist])
	print("おわり（エラーがなければ、上に音の名前が並ぶ）")
	quit()
