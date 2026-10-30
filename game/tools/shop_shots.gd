extends SceneTree
## 型紙と布を買って、ミシンでソリを縫い、畳んで持ち、外で広げて乗るまでを通して、場面ごとに一人称で撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/shop_shots.gd -- \
##       --bots=0 --no-sound --no-pip --spawn=shop --dir=/path/shots [--sled=mid] [--fabric=navy] [--money=N]
## 流れ: おじさんの前 → 売り台を開く → 型紙を選んで買う → 布を選んで買う → ミシンの画面で型紙と布を選んで縫う →
##       縫う（入れる・ため・解放・見せる・余韻）→ 出てきたソリ（米袋なら装備の枠に入る。大はロッジの前に出る）。
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
	if main.settings and main.settings.is_open:   # 窓から目が離れると設定が開くことがある（撮るときは閉じる）
		main.settings.set_open(false)
		main.player.menu_open = false
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
	var kind: String = args.get("sled", "sack")   # 畳めるのは一人用（米袋）だけ
	var fabric: String = args.get("fabric", "navy")
	# 型紙と布の分が足りなければ足す（最初の財布 craft.gd の START_BUTTONS では、米袋より大きいソリはまだ買えない）。--money=N で財布を N に
	var need: int = craft.price({"kind": "pattern", "sled": kind}) + craft.price({"kind": "fabric"})
	craft.wallets[who] = int(args.get("money", str(maxi(int(craft.wallets[who]), need))))
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
	if kind == "sack":
		# 米袋は装備: 床には出ず、装備の枠に入って、呼び出す米袋になる（持ち物の列は使わない）
		_say("装備の米袋 %s 選んでいる %d 持ち物 %s" % [craft.sacks.get(who), craft.sack_sel.get(who, 0), craft.bag(who)])
		p.set("_pitch", 0.0)
		await _wait(0.4)
		await _shot("sewn_gear")
		var lf := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
		lf.store_string("\n".join(log_lines) + "\n")
		quit()
		return
	var made: RigidBody3D = null
	for s in get_nodes_in_group("sleds"):
		if s.get("crafted"):
			made = s
	_say("縫ったソリ: %s" % (made.kind + " " + made.fabric if made else "なし"))
	if made == null:
		quit(1)
		return
	if kind in preload("res://craft.gd").OUT_FRONT:
		# 運び出せない大きさ: ロッジの前に、空から包みが落ちて開いて出てくる
		var lp: Vector3 = main.get_node("Lodge").to_local(made.global_position)
		_say("ロッジの前に出た: %s（ロッジの座標 x=%.1f y=%.1f）" % [lp.z > 25.0, lp.x, -lp.z])
		var front: Vector3 = made.global_position - made.global_basis.z * (made.HALF.y + 4.5) + made.global_basis.x * 2.0
		front.y = main.height(front.x, front.z) + 0.1
		_stand(front, made.global_position, -0.3)   # 坂の上の側から、ロッジの方を見下ろす
		await _wait(0.1)
		await _shot("delivered_drop")
		await _wait(1.6)
		await _shot("delivered")
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
	# 畳めるのは米袋だけで、米袋は装備（N で呼び出す。tools/sack_gear_shots.gd）。ほかのソリは押して運ぶ（tools/carry_out_check.gd）
	_say("持ち物 %s（ソリは入らない）" % [craft.bag(who)])
	var lf := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
	lf.store_string("\n".join(log_lines) + "\n")
	quit()
