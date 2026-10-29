extends SceneTree
## 右下の自分の小窓（self_cam.gd）を、場面ごとに一人称の画面で撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/self_cam_shots.gd -- --scene=walk --out=/path/to.png [--at=秒]
## 場面:
##   walk    ふもとを歩く（向きを途中で大きく変える）
##   push    ソリをつかんで押して登る
##   drag    ソリが下りへずり落ち、つかんだまま引きずられる
##   ride    乗って滑り降りる
##   five    仲間とハイタッチ（片手どうし）
##   palm    高い両手のひらを掲げる
##   voice   声（「ワ〜」の白い息）
##   snow    しゃがんで雪玉を作り、振りかぶる
##   held    買った布を手に持つ
##   lodge   ロッジの中
## --fps=秒: 撮らずに、その秒数だけ画面を描き、平均の fps とコマの長さを出す（--scene と一緒に。小窓を切って比べるのは --no-selfcam）

var args := {}
var main: Node3D
var t := 0.0
var _set := false
var _frames := 0
var _ft := 0.0
var _ft_max := 0.0
var _turned := false
var _gpu := {}
var _gpu_sum := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _place_sled(r: float, yaw: float) -> void:
	var sled: RigidBody3D = main.sled
	var p := Vector3(0, 0, r)
	p.y = main.height(p.x, p.z) + 0.35
	sled.reset_to(p)
	sled.rotation.y = yaw


func _face(p: Node3D, at: Vector3, pitch := -0.15) -> void:
	var d := at - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p._pitch = pitch


func _bot() -> Node3D:
	for c in main.get_children():
		if c != main.player and c is CharacterBody3D and c.get("doll") != null:
			return c
	return null


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var sled: RigidBody3D = main.sled
	if p == null or sled == null:
		return false
	var scene: String = args.get("scene", "walk")
	if not _set and t > 0.6:
		_set = true
		p.set_third(false)
		main.settings.set_open(false)
		p.menu_open = false
		if main.self_cam: main.self_cam.set_shown(true)   # 保存してある設定に関わらず出す（設定は書き換えない）
		main.pip_hidden = false
		if main._pip_layer: main._pip_layer.visible = true
		match scene:
			"walk":
				_face(p, sled.global_position + Vector3(8, 0, 0), -0.1)
				_key(KEY_W, true)
			"push":
				p.global_position = sled.to_global(Vector3(0, 0, 2.2)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.15)
				p.grab()
				_key(KEY_W, true)
			"drag":
				_place_sled(18.0, PI)
				p.global_position = sled.to_global(Vector3(0, 0, -2.2)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.2)
				p.grab()
			"ride":
				_place_sled(9.0, PI)
				p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
				p.get_on()
				p.rotation.y = sled.global_rotation.y
				p._pitch = -0.2
				sled.linear_velocity = -sled.global_basis.z * 4.0
			"five", "palm", "voice", "snow", "held":
				var at := Vector3(6.0, 0, 30.0)
				at.y = main.height(at.x, at.z) + 0.05
				p.global_position = at
				p.rotation.y = 0.0
				p._pitch = -0.12
				var b := _bot()
				if b:
					var bp := at + Vector3(0.0 if scene == "five" else 1.6, 0, -2.8)
					bp.y = main.height(bp.x, bp.z)
					b.global_position = bp
					b.set_physics_process(false)
					b.look_at(Vector3(at.x, bp.y, at.z), Vector3.UP)
			"lodge":
				if main.has_node("Audio"):
					p.global_position = main.get_node("Audio").spawn_point("inside")
				p._pitch = -0.05
	if not _set:
		return false
	var em_at := float(args.get("at", "4")) - 1.2
	match scene:
		"walk":
			if t > 2.4 and not _turned:   # 急に左へ振り向く（小窓はゆっくり回って追いつく）
				_turned = true
				p.rotate_y(1.8)
		"ride":
			p.rotation.y = sled.global_rotation.y
		"five":   # 二人とも手のひらを掲げ、あなたが歩いて近づく（届いた所で合う）
			var b := _bot()
			if t > 1.0 and t - dt <= 1.0 and b:
				p.hub.send({"kind": "hands", "who": b.id, "hands": "high_R"})
				p._set_hand("R")
				p.set_height("high")
				_key(KEY_W, true)
			if b and t > 1.0 and p.global_position.distance_to(b.global_position) < 1.1:
				_key(KEY_W, false)
		"palm":
			if t > em_at and t - dt <= em_at:
				p.set_hands("high_both")
		"voice":
			if t > em_at + 0.6 and t - dt <= em_at + 0.6:
				p.emote("wa")
		"snow":
			if t > 1.0 and t - dt <= 1.0:
				_key(KEY_CTRL, true)
			if t > 1.6 and t - dt <= 1.6:
				p.emote("make_ball")
			if t > em_at + 0.4 and t - dt <= em_at + 0.4:
				_key(KEY_CTRL, false)
				p.holding_ball = true
				p.wind_up()
		"held":
			if t > 1.0 and t - dt <= 1.0 and main.craft:
				main.craft.send({"kind": "buy", "who": p.id, "item": {"kind": "fabric", "fabric": "red"}})
	if args.has("fps"):
		if _gpu.is_empty():   # 描画の GPU 時間を、画面ごとに測る（本体・右上の 360°・右下の小窓）
			_gpu = {"本体": [root.get_viewport_rid()], "360": main._pip_vps.map(func(v): return v.get_viewport_rid()),
				"小窓": [main.self_cam.vp.get_viewport_rid()] if main.self_cam else []}
			for k in _gpu:
				for rid in _gpu[k]:
					RenderingServer.viewport_set_measure_render_time(rid, true)
				_gpu_sum[k] = 0.0
		if t > 2.0:
			_frames += 1
			_ft += dt
			_ft_max = maxf(_ft_max, dt)
			for k in _gpu:
				for rid in _gpu[k]:
					_gpu_sum[k] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if t > 2.0 + float(args["fps"]):
			var g := ""
			for k in _gpu:
				g += " %s=%.2fms" % [k, _gpu_sum[k] / _frames]
			print("fps 場面=%s 平均=%.1f コマ平均=%.1fms 最長=%.1fms 小窓=%s  GPU（1 コマあたり）:%s" % [scene, _frames / _ft, 1000.0 * _ft / _frames, 1000.0 * _ft_max, "なし" if main.self_cam == null else "あり", g])
			return true
		return false
	if t > float(args.get("at", "4")):
		var out: String = args.get("out", "/tmp/self_cam.png")
		root.get_texture().get_image().save_png(out)
		var sc = main.self_cam
		print("保存: ", out, "  mode=", p.mode, "  カメラ-見る所=", sc.cam.global_position - sc._aim, " 上下=", sc._extent(), " 人形=", p.doll.global_position.y, " 距離=", sc._dist, " 収まる距離=", sc._fit, " ずれ=", sc._side)
		return true
	return false
