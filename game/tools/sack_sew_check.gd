extends SceneTree
## ミシンで米袋の型紙と布を縫い上げても止まらないかを確かめる（2026-11-01）。
##   Godot --path game --headless --fixed-fps 30 -s res://tools/sack_sew_check.gd -- --bots=0 --no-pip
## 米袋は装備に入り床にソリが出ないので、sewn に id がない。player.gd がそれを読まずに飛ばすこと。
## 縫い上がったら、装備の米袋が 1 つ増え、床のソリの数は変わらない。
## player.gd の止まりは出来事のあとで起きて数には出ないので、出力に SCRIPT ERROR がないことも見る

var main: Node3D


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(sec: float) -> void:
	var until := Engine.get_physics_frames() + int(sec * Engine.physics_ticks_per_second)
	while Engine.get_physics_frames() < until:
		await physics_frame


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	var craft = main.craft
	if p == null or craft == null or main.sewing == null:
		print("あなた・工房・ミシンのどれかがない（--no-player を付けない）")
		quit(1)
		return
	var sew = main.sewing
	sew.phase_changed.connect(func(n: String) -> void: print("   ミシン: ", n))
	craft.wallets[p.id] = 100
	var ok := true
	ok = craft.send({"kind": "buy", "who": p.id, "item": {"kind": "pattern", "sled": "sack"}}) and ok
	ok = craft.send({"kind": "buy", "who": p.id, "item": {"kind": "fabric", "fabric": "red"}}) and ok
	var sacks0: int = craft.sacks[p.id].size()
	var sleds0: int = craft.sleds.size()
	var bag: Array = craft.bags[p.id]
	var ps := -1
	var fs := -1
	for i in bag.size():
		if bag[i].kind == "pattern":
			ps = i
		elif bag[i].kind == "fabric":
			fs = i
	print("買う: ", ok, "  型紙 %d・布 %d" % [ps, fs])
	ok = ok and ps >= 0 and fs >= 0 and craft.send({"kind": "sew", "who": p.id, "pattern": bag[ps].duplicate(),
			"fabric": bag[fs].duplicate(), "pattern_slot": ps, "fabric_slot": fs})
	print("縫う: ", ok)
	await _wait(12.0)
	var sacks1: int = craft.sacks[p.id].size()
	var sleds1: int = craft.sleds.size()
	print("装備の米袋 %d → %d・床のソリ %d → %d" % [sacks0, sacks1, sleds0, sleds1])
	var pass_ := ok and sacks1 == sacks0 + 1 and sleds1 == sleds0
	print("よい" if pass_ else "だめ")
	quit(0 if pass_ else 1)
