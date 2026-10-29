extends SceneTree
## 型紙と布を買って、ミシンでソリを縫い、畳んで持ち、外で広げて乗るまでを通して、場面ごとに一人称で撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/shop_shots.gd -- \
##       --bots=0 --no-sound --no-pip --spawn=shop --dir=/path/shots [--sled=mid] [--fabric=navy]
## 流れ: おじさんの前 → 売り台を開く → 型紙を選んで買う → 布を選んで買う → ミシンの前で型紙をセット → 布をセット →
##       縫う（入れる・ため・解放・見せる・余韻）→ 出てきたソリ → G で畳む → 持ち物 → 外の坂で広げる → 乗って滑る。
## 操作は人の手と同じ入口（player.gd の関数、craft_ui.gd の選ぶ・買う）を呼ぶ。<dir>/<番号>_<名前>.png を書き、
## 終わりに財布・持ち物・置いたソリの数を出す。

var args := {}
var main: Node3D
var p: CharacterBody3D
var n := 0
var log_lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/shop")


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	n += 1
	var path := _dir().path_join("%02d_%s.png" % [n, name])
	root.get_texture().get_image().save_png(path)
	print("撮った: ", path)


func _say(s: String) -> void:
	print(s)
	log_lines.append(s)


## あなたを at に立たせて、look の所を見る
func _stand(at: Vector3, look: Vector3, pitch := -0.15) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(look.x - at.x), -(look.z - at.z))
	p.set("_pitch", pitch)


func _run() -> void:
	# main.gd の起動引数は main の _ready が読む（--spawn=shop はここで足した）
	await _wait(2.5)
	p = main.player
	var craft: Node = main.craft
	var ui: CanvasLayer = main.craft_ui
	var who: int = p.id
	var kind: String = args.get("sled", "mid")
	var fabric: String = args.get("fabric", "navy")
	p.set("_pitch", 0.12)
	await _wait(0.6)
	await _shot("shop_front")
	# ---- 買う
	ui.open_shop()
	await _wait(0.5)
	await _shot("shop_open")
	ui.select(["sack", "small", "mid", "large"].find(kind))
	await _wait(0.3)
	await _shot("pick_pattern")
	_say("型紙を買う: %s" % ui.buy())
	await _wait(0.4)
	# 布がまだないときのミシンの画面: 布の枠が空いて、おじさん（売り台）を指す矢印
	ui.close_shop()
	ui.open_machine()
	await _wait(0.3)
	await _shot("machine_missing")
	_say("布がないと縫えない: %s" % (not ui.sew()))
	ui.close_machine()
	ui.open_shop()
	await _wait(0.3)
	ui.select(4 + ["red", "navy", "mustard", "holly", "cream", "plum"].find(fabric))
	await _wait(0.2)
	_say("布を買う: %s" % ui.buy())
	await _wait(0.5)
	await _shot("bought")
	ui.close_shop()
	await _wait(0.3)
	_say("財布 %d 持ち物 %s" % [craft.wallet(who), craft.bag(who)])
	# ---- ミシンにセット
	var sew: Node3D = main.sewing
	var m: Node3D = sew.machine
	var stand: Vector3 = m.to_global(sew._mark["stand"])
	var work: Vector3 = m.to_global(sew._mark["work"])
	var stand_l: Vector3 = sew._mark["stand"]
	var watch := m.to_global(stand_l + Vector3(-0.5, 0.05, -0.9))   # 立つ所の少し手前（ミシンの台と針が見える）
	_stand(watch, work, -0.2)
	await _wait(1.0)
	# トラックパッドの二本指スクロールで持ち替える（Mac ではホイールでなく、これで届く）
	var held0: int = craft.hands.get(who, -1)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 2.0)
	Input.parse_input_event(pan)
	await _wait(0.2)
	_say("二本指スクロールで持ち替え: %d → %d" % [held0, craft.hands.get(who, -1)])
	var zk := InputEventKey.new()
	zk.physical_keycode = KEY_Z
	zk.pressed = true
	Input.parse_input_event(zk)
	await _wait(0.2)
	_say("Z で持ち替え: → %d" % craft.hands.get(who, -1))
	await _shot("hold_switch")
	# ミシンの画面: F で開き、型紙と布が枠に入っているのを見て、縫うボタン
	var fk := InputEventKey.new()
	fk.physical_keycode = KEY_F
	fk.pressed = true
	Input.parse_input_event(fk)
	await _wait(0.5)
	_say("ミシンの画面: %s 枠 %s" % [ui.machine_open, ui._pick])
	await _shot("machine_open")
	_say("縫う: %s" % ui.sew())
	_say("持ち物 %s（型紙も布も使った）" % [craft.bag(who)])
	# ---- 縫う: 場面ごとに
	var seen := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000:
		var ph: String = sew.phase_name()
		if not seen.has(ph):
			seen[ph] = true
			if ph == "show":   # 見せる: 出口の方へ振り向いて、ソリが出てくるのを見る
				var o_l: Vector3 = sew._mark["out"]
				var land := m.to_global(Vector3(stand_l.x, o_l.y, o_l.z - 1.2))
				_stand(m.to_global(Vector3(stand_l.x + 1.5, o_l.y + 0.05, o_l.z - 2.6)), land, -0.25)   # 出る所の斜め前（窓の側）
			await _wait(0.18 if ph != "charge" else 1.2)
			await _shot("sew_" + ph)
			if ph == "show":
				await _wait(0.6)
				await _shot("sew_show_land")
		if ph == "after" and sew.phase_t > 0.4:
			break
		await process_frame
	await _wait(0.5)
	var made: RigidBody3D = null
	for s in get_nodes_in_group("sleds"):
		if s.get("crafted"):
			made = s
	_say("縫ったソリ: %s" % (made.kind + " " + made.fabric if made else "なし"))
	if made == null:
		quit(1)
		return
	# 出てきたソリを、少し離れて見る
	var back: Vector3 = made.global_position - made.global_basis.z * (made.HALF.y + 2.2) + Vector3.UP * 0.1
	_stand(back, made.global_position, -0.3)
	await _wait(0.4)
	await _shot("sewn_sled")
	# 手すりの前に吊るした名札の寄り
	var tag_n: Node3D = made.get_node_or_null("Tag")
	if tag_n:
		var tp := tag_n.global_position + Vector3.DOWN * 0.15
		var from := tp + made.global_basis.x * 1.1 - made.global_basis.z * 0.3
		from.y = made.global_position.y
		_stand(from, tp, 0.0)
		p.set("_pitch", atan2(tp.y - (from.y + 1.55), Vector2(tp.x - from.x, tp.z - from.z).length()))
		await _wait(0.4)
		await _shot("sewn_tag")
	# ---- 畳む（12 コマで 30 コマ。何コマ目かで撮る）
	var side: Vector3 = made.global_position + made.global_basis.x * (made.HALF.x + 1.4) + Vector3.UP * 0.1
	_stand(side, made.global_position, -0.45)
	await _wait(0.4)
	_say("畳めるソリ: %s" % (p.foldable_near() != null))
	await _shot("before_fold")
	_say("畳む: %s" % p.fold_near())
	await _wait(3.0 / 12.0)
	await _shot("fold_a")
	for i in 4:
		await _wait(5.0 / 12.0)
		await _shot("fold_" + "bcde"[i])
	await _wait(0.8)
	p.set("_pitch", 0.0)
	await _shot("in_bag")
	await _wait(0.5)
	await _shot("in_bag_turn")   # 名札の回る図が回っている
	_say("財布 %d 持ち物 %s 手 %d" % [craft.wallet(who), craft.bag(who), craft.hands.get(who, -1)])
	# ---- 外の坂で広げる（ふもとから少し上で、坂の下へ向いて）
	var out_at := Vector3(2.0, 0, 22.0)
	out_at.y = main.height(out_at.x, out_at.z) + 0.2
	_stand(out_at, Vector3(2.0, 0.0, 60.0), -0.35)
	await _wait(1.2)
	await _shot("outside_hold")
	_say("広げる所: %s" % p.unfold_spot())
	_say("広げる: %s" % p.unfold_ahead())
	await _wait(3.0 / 12.0)
	await _shot("unfold_a")
	for i in 4:
		await _wait(5.0 / 12.0)
		await _shot("unfold_" + "bcde"[i])
	await _wait(1.0)
	await _shot("unfolded")
	var placed: RigidBody3D = null
	for s in get_nodes_in_group("sleds"):
		if s.get("crafted") and s.visible:
			placed = s
	if placed == null:
		_say("広げたソリがない")
		quit(1)
		return
	# ---- 乗って滑る: 広げたソリは坂の下を向いている。E と同じく乗って、W（前傾）で滑り出す
	p.set("sled", placed)
	p.get_on()
	_say("乗った: %s" % (p.mode == p.Mode.RIDE))
	placed.parked = false
	placed.apply_central_impulse(-placed.global_basis.z * 1.5 * placed.mass)
	await _wait(1.5)
	await _shot("ride_1")
	await _wait(1.5)
	await _shot("ride_2")
	_say("滑る速さ %.1f m/s" % placed.linear_velocity.length())
	var f := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\n")
	quit()
