extends SceneTree
## 持ち物（手持ち 6 ＋ かばん 6）の確かめ用。数字だけ出す。
##   Godot --headless --path game -s res://tools/inventory_check.gd -- --bots=0 --no-sound
## 入る場所（手持ちの空き → かばん）・いっぱい・引きずって入れ替え・捨てる・手に持てるのは手持ちだけ・
## ホイールは空いたマスとかばんを飛ばす・使い切った場所は空いたまま・かばんの料理を食べる

var main: Node3D
var _fails := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _ok(what: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails += 1
	print("%s %s %s" % ["OK " if cond else "NG ", what, detail])


func _kinds(c, who: int) -> String:
	return str(c.bag(who).map(func(it): return "_" if it.is_empty() else str(it.get("kind", "?"))[0]))


func _run() -> void:
	await create_timer(1.5).timeout
	var p = main.player
	var c = main.craft
	var who: int = p.id
	c.wallets[who] = 9999
	_ok("最初は 12 の空いた場所", c.bag(who).size() == 12 and c.count(who) == 0, _kinds(c, who))
	for i in 12:
		c.send({"kind": "buy", "who": who, "item": {"kind": "fabric", "fabric": ["red", "navy", "plum"][i % 3]}})
	_ok("12 個まで入る", c.count(who) == 12, _kinds(c, who))
	_ok("13 個目は入らない", not c.send({"kind": "buy", "who": who, "item": {"kind": "fabric", "fabric": "red"}}))
	_ok("手に持つのは最後に手持ちへ入った物（かばんへ入った物は持たない）", c.hands[who] == 5, "手=%d" % c.hands[who])
	_ok("かばんの物は手に持てない", not c.send({"kind": "hand", "who": who, "slot": 8}))
	# 捨てる・空いたまま
	_ok("手持ちの 2 番を捨てる", c.send({"kind": "drop", "who": who, "slot": 2}))
	_ok("捨てた場所は空いたまま（ほかは動かない）", c.bag(who)[2].is_empty() and c.count(who) == 11, _kinds(c, who))
	_ok("空いた場所は手に持てない", not c.send({"kind": "hand", "who": who, "slot": 2}))
	# ホイールは空いたマスを飛ばす
	c.send({"kind": "hand", "who": who, "slot": 1})
	p.cycle_hand(1)
	_ok("ホイールで 1 → 3（空いた 2 を飛ばす）", c.hands[who] == 3, "手=%d" % c.hands[who])
	c.send({"kind": "hand", "who": who, "slot": 5})
	p.cycle_hand(1)
	_ok("ホイールで 5 → 素手（かばんへは行かない）", c.hands[who] == -1, "手=%d" % c.hands[who])
	# 新しい物は手持ちの空きへ
	c.send({"kind": "buy", "who": who, "item": {"kind": "pattern", "sled": "small"}})
	_ok("新しい物は手持ちの空き（2 番）へ入って手に持つ", c.bag(who)[2].get("kind") == "pattern" and c.hands[who] == 2, _kinds(c, who))
	# 引きずって入れ替え
	var a: Dictionary = c.bag(who)[2]
	var b: Dictionary = c.bag(who)[9]
	_ok("手に持っている 2 番を、かばんの 9 番と入れ替える", c.send({"kind": "move", "who": who, "from": 2, "to": 9}))
	_ok("入れ替わった", c.bag(who)[9] == a and c.bag(who)[2] == b, _kinds(c, who))
	_ok("手に持っていた物がかばんへ行ったら素手", c.hands[who] == -1, "手=%d" % c.hands[who])
	c.send({"kind": "drop", "who": who, "slot": 4})
	c.send({"kind": "hand", "who": who, "slot": 3})
	_ok("空いた場所へ引きずる", c.send({"kind": "move", "who": who, "from": 3, "to": 4}) and c.bag(who)[3].is_empty(), _kinds(c, who))
	_ok("手に持っていた物を手持ちの中で動かすと、持ったまま", c.hands[who] == 4, "手=%d" % c.hands[who])
	_ok("空いた場所からは引きずれない", not c.send({"kind": "move", "who": who, "from": 3, "to": 0}))
	# かばんの料理を食べる
	c.bag(who)[10] = {"kind": "food", "dish": "onigiri", "step": 1}
	main.craft_ui.open_gear()
	await create_timer(0.3).timeout
	main.craft_ui.eat_slot(10)
	_ok("かばんの料理は手持ちの空き（3 番）へ出て手に持つ", c.bag(who)[3].get("dish", "") == "onigiri" and c.hands[who] == 3, _kinds(c, who))
	_ok("食べると画面は閉じる", not main.craft_ui.gear_open)
	await create_timer(4.0).timeout
	_ok("食べ終わると、その場所は空く", c.bag(who)[3].is_empty() and c.hands[who] == -1, _kinds(c, who) + " 手=%d" % c.hands[who])
	print("確かめ: %s" % ("全部 OK" if _fails == 0 else "%d 件 NG" % _fails))
	quit(1 if _fails else 0)
