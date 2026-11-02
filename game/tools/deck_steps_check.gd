extends SceneTree
## ロッジの前のデッキの足音の確かめ（数字で）。デッキ・雪・ロッジの中で、どの足音が鳴ったかを数える。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/deck_steps_check.gd -- --bots=0 --lodge-bots=0 --no-pip --dir=/path/out
## 場所はロッジの座標（lodge/dims.py の x, y。Godot ではロッジの (x, 0, -y)）で出す。
## 1. 床しらべ: 雪・玄関前の広場・外階段・ミニテラス・風除室・食堂・2 階のテラスで、足もとの床の種類（audio.gd の surface_at）と当たった物
## 2. あなたが本物の W キーで歩く: 雪 → 広場 → 風除室 → 食堂 → 広場 → 広場の西の縁 → 雪 → 広場 → 外階段 → ミニテラス
## 3. 通信の体（remote_person.gd）を同じ道で動かす（届いた姿を写すだけの体。net.gd が足すのと同じく audio.add_walker で足す）
## 4. 踏ん張り・米袋の蹴りの音（_push_name）が、デッキの上で木、雪の上で雪になるか
## 鳴った足音を、鳴った所の区分（雪・デッキ・風除室・中）ごとに数える。区分と違う床の音が鳴ったら「ずれ」。
## 縁（デッキの外 1.2 m まで）は、段の上か雪の上かが場所だけでは分からないので数えるだけにする。床の音が切り替わった所も出す。
## <dir>/deck_steps.txt に書く。ずれが 1 つでもあれば終わりの番号を 1 にする

const RemotePerson := preload("res://remote_person.gd")
const PLAZA := Rect2(-21.46, -23.88, 12.87, 6.15)       # 玄関前の広場（dims.py の PLAZA）
const MINI := Rect2(-24.26, -19.83, 4.40, 4.60)         # ミニテラス（MINI）
const STAIR := Rect2(-19.86, -22.28, 1.82, 9.50)        # 外階段（ESTAIR。登り口から 2 階のテラスまで）
const EDGE := 1.2

var args := {}
var main: Node3D
var lodge: Node3D
var audio: Node
var p: CharacterBody3D
var lines: Array[String] = []
var counts := {}        # 区分 → {wood, snow}
var seq: Array = []     # 鳴った順の [区分, 床の音, 誰, x, y]
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/deck_steps")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:   # 窓から目が離れると設定が開くことがある
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _l(g: Vector3) -> Vector2:   # 世界 → ロッジの座標
	var q := lodge.to_local(g)
	return Vector2(q.x, -q.z)


func _w(q: Vector2, top := 2.5) -> Vector3:   # ロッジの座標 → 世界（床の高さ。top はロッジの床からどの高さから下を見るか）
	var g := lodge.to_global(Vector3(q.x, top, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g, g + Vector3.DOWN * (top + 6.0))
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	if hit:
		return hit.position
	return Vector3(g.x, main.height(g.x, g.z), g.z)


func _area(g: Vector3) -> String:   # 鳴った所の区分
	var z: int = audio.zone_at(lodge, g)
	if z == 2:
		return "中"
	if z == 1:
		return "風除室"
	var q := _l(g)
	for r in [PLAZA, MINI, STAIR]:
		if (r as Rect2).has_point(q):
			return "デッキ"
	for r in [PLAZA, MINI, STAIR]:
		if (r as Rect2).grow(EDGE).has_point(q):
			return "縁"
	return "雪"


func _ray_hit(g: Vector3) -> String:   # 足もとの光線が当たった物（surface_at と同じ光線）
	var q := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 0.3, g + Vector3.DOWN * 0.6)
	q.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "（なし）"
	return String((hit.collider as Node).get_path()).replace(String(main.get_path()) + "/", "")


## audio.played に増えた who の足音を、who のいまの所で区分けして数える
func _tally(from: int, who: Node3D) -> int:
	for i in range(from, audio.played.size()):
		var e: Dictionary = audio.played[i]
		var n := String(e.name)
		if not n.begins_with("step_") or String(e.get("who", "")) != String(who.name):   # 仲間の足音は数えない
			continue
		var floor_ := "wood" if n.begins_with("step_wood") else "snow"
		var area := _area(who.global_position)
		if not counts.has(area):
			counts[area] = {"wood": 0, "snow": 0}
		counts[area][floor_] += 1
		var q := _l(who.global_position)
		seq.append([area, floor_, String(e.get("who", "")), q.x, q.y])
		var want: String = {"中": "wood", "風除室": "wood", "デッキ": "wood", "雪": "snow"}.get(area, "")
		if want != "" and want != floor_:
			bad += 1
			_say("  ずれ: %s で %s（%s、x=%.1f y=%.1f）" % [area, n, e.get("who", ""), q.x, q.y])
	return audio.played.size()


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	await process_frame


func _walk(goal: Vector2, name: String) -> void:   # いまの所から goal へ、向きを合わせながら W で歩く
	var gw := _w(goal)
	await _key(KEY_W, true)
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	var mark: int = audio.played.size()
	var ok := false
	while t < 25.0:
		var d := gw - p.global_position
		d.y = 0
		if d.length() < 0.5:
			ok = true
			break
		p.rotation.y = atan2(-d.x, -d.z)
		await physics_frame
		mark = _tally(mark, p)
		t += 1.0 / 30.0
		stuck = stuck + 1.0 / 30.0 if p.global_position.distance_to(last) < 0.004 else 0.0
		last = p.global_position
		if stuck > 1.5:
			break
	await _key(KEY_W, false)
	for i in 3:
		await physics_frame
		mark = _tally(mark, p)
	var lp := _l(p.global_position)
	_say("  %s: %s（%.1f 秒、x=%.1f y=%.1f）" % [name, "着いた" if ok else "止まった", t, lp.x, lp.y])


func _remote_walk(r: Node3D, path: Array) -> void:   # 通信の体を、届いた姿として 4 m/s で道に沿って動かす
	var at := _w(path[0])
	r.put({"p": at, "y": 0.0, "m": 0})
	for i in 10:
		await physics_frame
	var mark: int = audio.played.size()
	for k in range(1, path.size()):
		var goal := _w(path[k])
		while true:
			var d := goal - at
			var flat := Vector2(d.x, d.z).length()
			if flat < 0.1:
				break
			var stepv := minf(flat, 4.0 / 30.0)
			at += d * (stepv / maxf(d.length(), 0.001))
			at.y = _w(_l(at)).y
			r.put({"p": at, "y": atan2(-d.x, -d.z), "m": 0})
			await physics_frame
			mark = _tally(mark, r)
	for i in 10:
		await physics_frame
		mark = _tally(mark, r)


func _run() -> void:
	await create_timer(2.5).timeout
	p = main.player
	lodge = main.get_node_or_null("Lodge")
	audio = main.get_node_or_null("Audio")
	if p == null or lodge == null or audio == null:
		print("あなた・ロッジ・音のどれかがない（--no-player・--no-lodge・--no-sound を付けない）")
		quit(1)
		return
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)   # ソリは道からどけておく
	# 1. 床しらべ
	_say("1. 床しらべ（ロッジの座標 x, y と、見下ろす高さ）")
	var probes := [
		["雪（広場の南）", Vector2(-13.4, -32.0), 2.5, "snow"],
		["雪（広場の西）", Vector2(-27.0, -22.0), 2.5, "snow"],
		["玄関前の広場", Vector2(-13.4, -21.0), 2.5, "wood"],
		["広場の東の端", Vector2(-9.2, -20.0), 2.5, "wood"],
		["広場の南の縁の段", Vector2(-13.4, -24.2), 2.5, ""],
		["外階段の下の段", Vector2(-18.95, -21.8), 2.5, "wood"],
		["外階段の踊り場", Vector2(-18.95, -17.5), 4.5, "wood"],
		["ミニテラス", Vector2(-22.0, -17.5), 4.5, "wood"],
		["風除室", Vector2(-13.4, -15.2), 2.5, "wood"],
		["食堂", Vector2(6.0, 4.0), 2.5, "wood"],
		["2 階のテラス", Vector2(0.0, -9.0), 7.5, "wood"],
	]
	for pr in probes:
		var g := _w(pr[1], pr[2])
		var s: String = audio.surface_at(g)
		var mark := "" if pr[3] == "" else ("○" if s == pr[3] else "×")
		if mark == "×":
			bad += 1
		_say("  %s %s（x=%.1f y=%.1f 高さ %.2f）: %s ← %s" % [mark, pr[0], pr[1].x, pr[1].y, lodge.to_local(g).y, s, _ray_hit(g)])
	# 2. あなたが歩く
	audio.log_on = true
	_say("2. あなたが W で歩く")
	p.global_position = _w(Vector2(-13.4, -32.0)) + Vector3.UP * 0.1
	for i in 20:
		await physics_frame
	audio.played.clear()
	for leg in [[Vector2(-13.4, -21.0), "雪 → 広場"], [Vector2(-13.4, -15.2), "広場 → 風除室"], [Vector2(-13.4, -8.0), "風除室 → 食堂"],
			[Vector2(-13.4, -21.0), "食堂 → 広場"], [Vector2(-20.8, -23.3), "広場の西の端へ"], [Vector2(-27.0, -23.3), "西の縁から雪へ下りる"],
			[Vector2(-20.8, -23.3), "雪から広場へ上がる"], [Vector2(-18.95, -22.6), "外階段の登り口"], [Vector2(-18.95, -17.6), "外階段を踊り場まで"],
			[Vector2(-22.5, -17.6), "ミニテラスへ"]]:
		await _walk(leg[0], leg[1])
	var mine := seq.size()
	# 3. 通信の体
	_say("3. 通信の体（remote_person.gd）を同じ道で動かす")
	p.global_position = lodge.to_global(Vector3(10.0, 0.6, -4.0))   # あなたは食堂の奥で待つ
	var r := RemotePerson.new()
	r.name = "RemoteTest"
	r.position = _w(Vector2(-13.4, -32.0))
	main.add_child(r)
	audio.add_walker(r, true)
	await _remote_walk(r, [Vector2(-13.4, -32.0), Vector2(-13.4, -21.0), Vector2(-13.4, -15.2), Vector2(-13.4, -8.0), Vector2(-13.4, -21.0),
			Vector2(-20.8, -23.3), Vector2(-27.0, -23.3), Vector2(-20.8, -23.3)])
	_say("  通信の体の足音: %d 歩" % (seq.size() - mine))
	# 4. 踏ん張り・蹴りの音
	_say("4. 踏ん張り・米袋の蹴りの音（_push_name）")
	for pl in [["広場", Vector2(-13.4, -21.0), "step_wood"], ["雪", Vector2(-13.4, -32.0), "step_snow_push"]]:
		p.global_position = _w(pl[1]) + Vector3.UP * 0.02
		await physics_frame
		await physics_frame
		var n: String = audio._push_name(p)
		var ok := n.begins_with(pl[2] + "_")
		if not ok:
			bad += 1
		_say("  %s %s: %s" % ["○" if ok else "×", pl[0], n])
	# まとめ
	_say("まとめ（区分ごとの足音の数。木 / 雪）")
	for area in ["雪", "縁", "デッキ", "風除室", "中"]:
		var c: Dictionary = counts.get(area, {"wood": 0, "snow": 0})
		_say("  %s: 木 %d / 雪 %d" % [area, c.wood, c.snow])
	_say("床の音が切り替わった所（同じ人の、前の一歩 → 次の一歩。区分と x, y）:")
	for i in range(1, seq.size()):
		var a: Array = seq[i - 1]
		var b: Array = seq[i]
		if a[2] == b[2] and a[1] != b[1]:
			_say("  %s: %s %s（x=%.1f y=%.1f）→ %s %s（x=%.1f y=%.1f）" % [b[2], a[0], a[1], a[3], a[4], b[0], b[1], b[3], b[4]])
	_say("ずれ: %d" % bad)
	var f := FileAccess.open(_dir().path_join("deck_steps.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0 if bad == 0 else 1)
