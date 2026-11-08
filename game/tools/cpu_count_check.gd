extends SceneTree
## 設定の「CPU の数」の確かめ（main.gd の set_cpu_count）。遊んでいる途中で 5 → 20 → 3 → 0 → 8 人に変え、山をめぐる仲間の数・
## 席の空き・消えた仲間の後始末を見る。設定の保存（user://settings.cfg）は書き換えない（_apply_setting を直に呼ぶ）。
##   一人:   Godot --headless --fixed-fps 60 --path game -s res://tools/cpu_count_check.gd -- --no-sound --roam-bots=5
##   通信:   Godot --headless --fixed-fps 60 --path game -s res://tools/cpu_count_check.gd -- --no-sound --roam-bots=5 --host --port=24791
##           Godot --headless --fixed-fps 60 --path game -s res://tools/cpu_count_check.gd -- --no-sound --join=127.0.0.1 --port=24791
## ホスト（と一人）は段ごとに数を変え、つなぐ側は届いている仲間の体の数を 5 秒ごとに書く。最後に「よい」か「よくない」

const STEPS := [[8.0, 20], [30.0, 3], [45.0, 0], [55.0, 8]]   # [秒, 数]
const END := 75.0

var args := {}
var main: Node3D
var t := 0.0
var _step := 0
var _bad := 0
var _note := 0.0
var _gone: Array = []        # 消えた仲間の番号


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _roamers() -> Array:
	return main.get_children().filter(func(c): return c.is_in_group("bots") and c.get("roam") and not c.is_queued_for_deletion())


func _physics_process(dt: float) -> bool:
	t += dt
	if args.has("join"):
		return _join_side()
	if t < 2.0:
		return false
	if _step == 0 and t >= 2.0 and t < 2.0 + dt * 1.5:
		print("はじめ: %d 人" % _roamers().size())
		# 1 人をロッジの席に、1 人を米袋で滑らせて、消すときの後始末も見る
		var rs := _roamers()
		if rs.size() >= 2:
			var b = rs[-1]
			b.global_position = main.get_node("Lodge").to_global(Vector3(-13.4, 0.6, 11.0))
			b.visit.reason = "rest"
			b._area = "lodge"
			b._route = []
			b.visit.enter()
			b.visit.level = 1
			b.visit.plan = [{"kind": "seat", "what": "rest", "floor": 1}]
	if _step < STEPS.size() and t >= STEPS[_step][0]:
		var n: int = STEPS[_step][1]
		var before := _roamers()
		var seated := before.filter(func(b): return b.seat_i >= 0).map(func(b): return b.id)
		var riding := before.filter(func(b): return b.state == b.State.RIDE).map(func(b): return b.id)
		main._apply_setting("cpus", float(n))
		var after := _roamers()
		for b in before:
			if not b in after:
				_gone.append(b.id)
		print("%.0f 秒: %d 人 → %d 人にした（座っていた %s、滑っていた %s）→ いま %d 人" % [t, before.size(), n, str(seated), str(riding), after.size()])
		_step += 1
	_note -= dt
	if _note <= 0.0:
		_note = 5.0
		var seats = main.get("seats")
		var stale := 0
		if seats:
			for i in seats.taken:
				if int(seats.taken[i]) in _gone:
					stale += 1
		var net = main.get("net")
		var far := _roamers().filter(func(b): return b.far).size()
		print("  %.0f 秒: 山をめぐる仲間 %d 人（間引き %d）、消えた仲間が座ったままの席 %d、来ている人 %d" % [t, _roamers().size(), far, stale,
				net.remotes.size() if net else 0])
		if stale > 0:
			_bad += 1
		var want: int = STEPS[_step - 1][1] if _step > 0 else -1
		if want >= 0 and _roamers().size() > want:   # 手が空くのを待っている仲間（なぜ消せないか）
			var duel = main.get_node_or_null("Duel")
			for b in _roamers().slice(want):
				var d: Dictionary = duel.of(b.id) if duel else {}
				print("    待っている #%d: 対決%s 手伝い%.1f 乗る人%d" % [b.id, (" 相手#%d %s" % [duel.opponent(d, b.id), d.phase]) if not d.is_empty() else "なし",
						b._help_t, b.sled.riders.size() if b.state == b.State.RIDE else 0])
	if t >= END:
		var want: int = STEPS[-1][1]
		if _roamers().size() != want:
			print("よくない: 最後の数 %d（%d のはず）" % [_roamers().size(), want])
			_bad += 1
		print("よい" if _bad == 0 else "よくない（%d）" % _bad)
		quit(0 if _bad == 0 else 1)
		return true
	return false


func _join_side() -> bool:
	_note -= 1.0 / 60.0
	if _note <= 0.0:
		_note = 5.0
		var net = main.get("net")
		var alive := 0
		if net:
			for id in net.cpus:
				if is_instance_valid(net.cpus[id]):
					alive += 1
		print("つなぐ側 %.0f 秒: 仲間の体 %d、消えた仲間 %d" % [t, alive, net._cpus_gone.size() if net else 0])
	if t >= END + 3.0:
		quit()
		return true
	return false
