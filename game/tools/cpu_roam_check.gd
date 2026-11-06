extends SceneTree
## 仲間（CPU）の山めぐりの確かめ（数字）。5 人が山を選び、頂上まで登り、米袋で滑り降り、別の山へ移るのを記録する。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/cpu_roam_check.gd -- --no-sound --secs=900
## --at=x,z で遊ぶ人の立つ所を替える（既定はスタート）。--near を足すと、遊ぶ人をゆきのそばに置き続ける（当たりを見て歩く道も試す）。
## --rich を足すと、はじめから財布に 200 入れる（ソリを買うのを早く見る）。仲間どうしの雪合戦・ソリ運び・買い物も 1 行ずつ出す。
## 出来事ごとに 1 行、60 秒ごとに全員の表、最後に山ごとの回数。
## 詰まりの数（最後の「詰まり:」の行）: 頂上以外で米袋を広げた回数、短い滑り（米袋で SHORT_RIDE m 未満）、諦めた点（着かずに次の点へ進んだ）、
## 動けなくなった回数（歩いているのに STUCK_T 秒で 1 m も動かない）、組から抜けた回数（ソリまで着けなかった）、当たりを消して抜けた回数（閉じた所に入り込んだ）。--seed=n で乱数を固定する。

var args := {}
var main: Node3D
var _was := {}
var _stats := {}
var count := {}
const SHORT_RIDE := 30.0     # これより短い米袋の滑りは「短い滑り」(m)
const STUCK_T := 10.0        # 歩いているのに、これだけ 1 m も動かなければ「動けない」(s)
const OFF_TOP := 10.0        # 頂上か広げる所からこれより離れて広げたら「頂上以外」(m)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("seed"):
		seed(int(args.seed))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


func _say(s: String) -> void:
	print("[%6.1f] %s" % [_now(), s])


func _name(b) -> String:
	return "%d %s" % [b.id, main.craft.name_of(b.id)]


func _run() -> void:
	await create_timer(1.0).timeout
	var bots: Array = get_nodes_in_group("bots")
	_say("仲間 %d 人: %s" % [bots.size(), ", ".join(bots.map(func(b): return _name(b) + " " + b.doll.kind))])
	for b in bots:
		_was[b] = {"area": b._area, "ride": false}
		_stats[b] = {"rides": [], "max_y": 0.0}
	main.duel.happened.connect(_on_duel)
	main.craft.happened.connect(_on_craft)
	if args.has("rich"):
		for b in bots:
			main.craft.wallets[b.id] = 200
	if args.has("at"):
		var v: PackedFloat64Array = String(args.at).split_floats(",")
		main.player.global_position = Vector3(v[0], main.height(v[0], v[1]) + 0.3, v[1])
	var secs := float(args.get("secs", "600"))
	var t0 := _now()
	var next_table := 0.0
	while _now() - t0 < secs:
		await physics_frame
		if args.has("near"):
			var y: Node3D = bots[0]
			var at: Vector3 = y.global_position + Vector3(4, 0, 4)
			main.player.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z)
			main.player.velocity = Vector3.ZERO
		for b in bots:
			_watch(b)
		if _now() - t0 >= next_table:
			next_table += 60.0
			_table(bots)
	_table(bots)
	var bad := 0
	for b in bots:
		var rides: Array = _stats[b].rides
		var areas := {}
		for r in rides:
			areas[r.area] = int(areas.get(r.area, 0)) + 1
		_say("%s 滑った回数 %d 山ごと %s" % [_name(b), rides.size(), str(areas)])
		for r in rides:
			_say("   %s 頂上から %.0f m 下へ %.1f m、%.0f 秒、速さの上限 %.1f m/s、止まった所 (%.0f, %.0f)" % [r.area, r.dist, r.drop, r.t, r.top_v, r.end.x, r.end.y])
		if b.global_position.y < -20.0:
			bad += 1
	_say("数: %s" % str(count))
	var sacks := 0
	for b in bots:
		sacks += (_stats[b].rides as Array).filter(func(r): return r.sack).size()
	_say("詰まり: 米袋で滑った %d 回 / 頂上以外で広げた %d / 短い滑り %d / 諦めた点 %d / 動けなくなった %d / 組から抜けた %d / 当たりを消して抜けた %d" % [sacks, int(count.get("off_top", 0)), int(count.get("short", 0)), int(count.get("skip", 0)), int(count.get("stuck", 0)), int(count.get("left", 0)), bots.reduce(func(n, b): return n + int(b.get("give_ups") if b.get("give_ups") != null else 0), 0)])
	for b in bots:
		_say("%s 財布 %d 自分のソリ %s" % [_name(b), main.craft.wallet(b.id), str(is_instance_valid(b.own_sled))])
	_say("おわり")
	quit(bad)


func _on_duel(ev: Dictionary) -> void:
	var d: Dictionary = ev.get("duel", {})
	if d.is_empty():
		return
	var cue := String(ev.get("cue", ""))
	if cue in ["bet", "start", "end", "paid", "cancel"]:
		_say("雪合戦 %s: %s と %s 所 (%.0f, %.0f) 掛金 %d 当てた %d・%d 勝ち %d 段 %s" % [cue, main.craft.name_of(int(d.a)), main.craft.name_of(int(d.b)), d.at.x, d.at.z, int(d.stake), int(d.hits_a), int(d.hits_b), int(d.winner), d.phase])
		count[cue] = int(count.get(cue, 0)) + 1


func _on_craft(ev: Dictionary) -> void:
	if ev.kind in ["buy", "sew", "sewn"] and _was.keys().any(func(b): return b.id == int(ev.get("who", -1))):
		_say("買い物 %s %s: %s 財布 %d" % [main.craft.name_of(int(ev.who)), ev.kind, str(ev.get("item", ev.get("sled", ""))), main.craft.wallet(int(ev.who))])
		count[ev.kind] = int(count.get(ev.kind, 0)) + 1


func _watch(b) -> void:
	var w: Dictionary = _was[b]
	var ride: bool = b.state == b.State.RIDE
	var team: bool = not b._team.is_empty()
	if team and not w.get("team", false):
		var names: Array = b._team.members.map(func(m): return main.craft.name_of(m.id))
		_say("組 %s が %s のソリ（%s）を %s へ運ぶ %s ソリの所 (%.0f, %.0f)" % [_name(b), "自分" if b._team.sled == b.own_sled else "ロッジ", b._team.sled.kind, b._team.area, str(names), b._team.sled.global_position.x, b._team.sled.global_position.z])
		w["team_from"] = b._team.sled.global_position
		count["team"] = int(count.get("team", 0)) + 1
	if not team and w.get("team", false):
		var s = b.sled
		_say("組おわり %s %s: ソリの所 (%.0f, %.1f, %.0f)、%s の所 (%.1f, %.1f)" % [_name(b), "乗った" if ride else "抜けた", s.global_position.x, s.global_position.y, s.global_position.z, s.kind, b.global_position.x, b.global_position.z])
		count["board" if ride else "left"] = int(count.get("board" if ride else "left", 0)) + 1
	w["team"] = team
	if b._area != w.area:
		if b._area != "":
			_say("%s は %s へ向かう（前の山 %s）所 (%.0f, %.0f)" % [_name(b), b._area, b._last_area, b.global_position.x, b.global_position.z])
		w.area = b._area
	if ride and not w.ride:
		w.start = b.global_position
		w.t = _now()
		w.top_v = 0.0
		w.ride_area = b._area
		w.ride_sack = b.sled.kind == "sack"
		var off := _off_top(b)
		_say("%s が %s の頂上で%sを広げた 高さ %.1f 所 (%.0f, %.0f) 行き先 (%.0f, %.0f) 頂上から %.0f m%s" % [_name(b), b._area, "米袋" if w.ride_sack else "ソリ", b.global_position.y, b.global_position.x, b.global_position.z, b._ride_goal.x, b._ride_goal.y, off, " ※頂上以外" if off > OFF_TOP else ""])
		if w.ride_sack and off > OFF_TOP:
			count["off_top"] = int(count.get("off_top", 0)) + 1
	if ride and is_instance_valid(b.sled):
		w.top_v = maxf(w.top_v, b.sled.linear_velocity.length())
		w.last = b.global_position
	if w.ride and not ride:
		var p: Vector3 = w.last
		var r := {"sack": w.ride_sack, "area": w.ride_area, "dist": Vector2(p.x - w.start.x, p.z - w.start.z).length(), "drop": w.start.y - p.y, "t": _now() - w.t, "top_v": w.top_v, "end": Vector2(p.x, p.z)}
		_stats[b].rides.append(r)
		if r.sack and r.dist < SHORT_RIDE:
			count["short"] = int(count.get("short", 0)) + 1
		_say("%s が滑り終えた %s: %.0f m、%.1f m 下へ、%.0f 秒、上限 %.1f m/s" % [_name(b), r.area, r.dist, r.drop, r.t, r.top_v])
	w.ride = ride
	_watch_stuck(b, w, ride, team)


## 頂上か広げる所までの距離（山の道の終わりに着いていれば小さい）
func _off_top(b) -> float:
	var a: Dictionary = b.ROAM_AREAS.get(b._area, {})
	if a.is_empty():
		return 0.0
	var at := Vector2(b.global_position.x, b.global_position.z)
	var d: float = at.distance_to(a.top)
	if a.has("launch"):
		d = minf(d, at.distance_to(a.launch))
	return d


## 歩いているのに動かない・着かずに次の点へ進んだのを数える（動けなければ、まわりの物を 1 度だけ出す）
func _watch_stuck(b, w: Dictionary, ride: bool, team: bool) -> void:
	var at := Vector2(b.global_position.x, b.global_position.z)
	var walking: bool = not ride and not team and b._area != "" and not b._route.is_empty() and b.handle == Vector3.INF and b._five_with < 0 and not b._in_duel() and b._help_t <= 0.0
	var n: int = b._route.size()
	if walking and n == int(w.get("route_n", -1)) - 1 and (w.wp as Vector2).distance_to(at) > 2.5:
		count["skip"] = int(count.get("skip", 0)) + 1
		_say("%s 着かずに次の点へ: 所 (%.1f, %.1f, %.1f) 点 (%.0f, %.0f) 山 %s 残り %d%s" % [_name(b), at.x, b.global_position.y, at.y, w.wp.x, w.wp.y, b._area, n, " 遠い" if b.far else ""])
	w["route_n"] = n
	if n > 0:
		w["wp"] = b._route[0]
	if not walking or at.distance_to(w.get("still_at", Vector2.INF)) > 1.0:
		w["still_at"] = at
		w["still_t"] = _now()
		w["still_said"] = false
	elif _now() - float(w.still_t) > STUCK_T and not w.still_said:
		w["still_said"] = true
		count["stuck"] = int(count.get("stuck", 0)) + 1
		_say("%s 動けない: 所 (%.1f, %.1f, %.1f) 点 (%.0f, %.0f) 山 %s 残り %d 当たり %s" % [_name(b), at.x, b.global_position.y, at.y, w.wp.x, w.wp.y, b._area, n, _touching(b)])


## いま当たっている物の名前
func _touching(b) -> String:
	var out := []
	for i in b.get_slide_collision_count():
		var c: KinematicCollision3D = b.get_slide_collision(i)
		var o = c.get_collider()
		if o is Node and absf(c.get_normal().y) < 0.7:
			out.append("%s%s" % [(o as Node).name, (c.get_position() as Vector3).snapped(Vector3(0.1, 0.1, 0.1))])
	return str(out)


func _table(bots: Array) -> void:
	for b in bots:
		_say("  %s 山 %s 残り %d 点 (%.0f, %.1f, %.0f) %s%s" % [_name(b), b._area, b._route.size(), b.global_position.x, b.global_position.y, b.global_position.z,
			"滑っている" if b.state == b.State.RIDE else ("運ぶ" if not b._team.is_empty() else "歩く"), " 遠い" if b.far else ""])
