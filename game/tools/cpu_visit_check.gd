extends SceneTree
## 仲間（CPU）のロッジへの寄り道の確かめ（数字）。山をめぐる仲間を何人か出し、ロッジへ寄って、座る・2 階のこたつ・買う・着替える・
## 見る・濡れきって乾かす、をして外へ出るのを記録する（bot_visit.gd）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/cpu_visit_check.gd -- --no-sound --roam-bots=20 --cpu-visit=1 --secs=600
## --wet=n を足すと、はじめに n 人の水をいっぱい（100）にする（濡れきって帰ってくるのを早く見る）。--near を足すと、遊ぶ人をロッジの中に置く
## （人から遠い仲間は間引いて歩くので、近くの歩き方を見る）。出来事ごとに 1 行、60 秒ごとに全員の表、最後にまとめ。
## 詰まり: 点へ体を移した回数（warps。WARP_T 秒近づけなかった）。少ないほどよい

var args := {}
var main: Node3D
var t := 0.0
var _next_table := 60.0
var _was := {}
var _bots: Array = []
var _secs := 600.0
var _frames := 0
var _ms_sum := 0.0
var _ms_max := 0.0
var _last_us := 0
const NAV_HALF := [12, 40]
var _slow: Array = []        # 50 ms を超えたコマ


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("seed"):
		seed(int(args.seed))
	_secs = float(args.get("secs", "600"))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _state(b) -> String:
	var v = b.visit
	if v == null:
		return "-"
	if v.inside:
		var what := String(v.task.get("what", ""))
		var s := "中%d階" % v.level
		if v.leaving:
			s += "→外"
		elif not v.route.is_empty():
			s += "→歩く"
		if what != "":
			s += ":" + what
		if b.seat_i >= 0:
			s += "(座る)"
		return s
	if b._area == "lodge":
		return "ロッジへ"
	if b.state == b.State.RIDE:
		return "滑る"
	return "山:" + String(b._area)


func _physics_process(dt: float) -> bool:
	t += dt
	var now := Time.get_ticks_usec()
	if _last_us > 0 and t > 3.0:
		var ms := (now - _last_us) / 1000.0
		_frames += 1
		_ms_sum += ms
		_ms_max = maxf(_ms_max, ms)
		if ms > 50.0:
			var scan := []
			for b in _bots:
				if not b._nav_job.is_empty():
					scan.append("#%d %s 範囲%d" % [b.id, _state(b), NAV_HALF[int(b._nav_job.size)]])
			_slow.append("%.1f秒 %.0fms 道を調べている%s" % [t, ms, str(scan)])
	_last_us = now
	if _bots.is_empty() and t > 1.0:
		_bots = main.get_children().filter(func(c): return c.is_in_group("bots") and c.get("roam"))
		print("山をめぐる仲間: ", _bots.size())
		if not _bots.is_empty():   # 寄り道ですることの行き先（物が見つからなければ空）
			var lodge: Node3D = main.get_node("Lodge")
			for k in _bots[0].visit.POOL:
				var tk: Dictionary = _bots[0].visit._task_of(k)
				print("  %s: %s" % [k, ("%d 階 %s" % [tk.floor, str(lodge.to_local(tk.at).snapped(Vector3.ONE * 0.1))]) if tk.has("at") else (("%d 階 席" % tk.floor) if tk.has("floor") else "なし")])
		var dm = main.get_node_or_null("Damp")
		for i in mini(int(args.get("wet", "0")), _bots.size()):
			dm.put(_bots[i].id, 100.0)
			print("  #%d の水をいっぱいに" % _bots[i].id)
		if args.has("near"):
			var p = main.get("player")
			if p:
				p.global_position = main.get_node("Lodge").to_global(Vector3(6.0, 0.6, -1.0))
		return false
	var dm = main.get_node_or_null("Damp")
	for b in _bots:
		var s := _state(b)
		if _was.get(b, "") != s:
			if not s.begins_with("山") and s != "滑る" or String(_was.get(b, "")).begins_with("中"):
				print("%6.1f #%d %s → %s  水%.0f" % [t, b.id, _was.get(b, ""), s, dm.water_of(b.id) if dm else 0.0])
			_was[b] = s
	if t >= _next_table:
		_next_table += 60.0
		_table()
	if t >= _secs:
		_table()
		var visits := 0
		var warps := 0
		var done := {}
		for b in _bots:
			visits += b.visit.visits
			warps += b.visit.warps
			for d in b.visit.done:
				done[d] = done.get(d, 0) + 1
		print("まとめ: 寄り道 %d 回、点へ体を移した %d 回、したこと %s" % [visits, warps, str(done)])
		print("50 ms を超えたコマ %d: %s" % [_slow.size(), ", ".join(_slow.slice(0, 30))])
		print("1 コマ平均 %.2f ms、いちばん重いコマ %.1f ms（%d コマ）" % [_ms_sum / maxi(1, _frames), _ms_max, _frames])
		quit()
		return true
	return false


func _table() -> void:
	var dm = main.get_node_or_null("Damp")
	var rows := []
	for b in _bots:
		rows.append("#%d %s 水%.0f 寄%d 移%d" % [b.id, _state(b), dm.water_of(b.id) if dm else 0.0, b.visit.visits, b.visit.warps])
	print("---- %.0f 秒: " % t, " | ".join(rows))
