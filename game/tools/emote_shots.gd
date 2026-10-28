extends SceneTree
## 身ぶり（エモート）を一つずつ出して、いちばん大きく動くコマで撮る（確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/emote_shots.gd -- --dir=/path/to/dir [--view=fp|tp|front] [--only=wa,bow]
## fp 一人称（あなたの目。手と息が見えるか）、tp 三人称（C の視点）、front 正面から（人形の形）。
## あなたと仲間を向かい合わせて立たせ、仲間は動かさない（ハイタッチの相手は、配り役へ直接送る）。
## 撮るもの: 名前_視点.png。「hit_bot」はあなたが仲間へ雪玉を投げ、仲間がのけぞる所。「hit_me」は仲間からあなたへ。
## 「sled」はソリへ投げて、雪が残る所。「banzai」「ride_clap」はソリに乗って撮る。
## --check: 撮らずに、仲間の返し（ハイタッチ・声）が働くかを出来事の記録で確かめる

const Doll := preload("res://doll.gd")

## [名前, 出す身ぶり, 撮るコマ]
const SHOTS := [
	["hand_up", "hand_up", 8],
	["five_pull", "high_five", 1],
	["high_five", "high_five", 3],
	["five_burst", "high_five", 5],
	["whiff", "whiff", 3],
	["breath_in", "breath", 14],
	["breath_out", "breath", 40],
	["make_ball", "make_ball", 10],
	["windup", "windup", 4],
	["throw", "throw", 1],
	["hit_bot", "hit_bot", 1],
	["hit_me", "hit_me", 1],
	["sled", "sled", 6],
	["clap", "clap", 2],
	["bow", "bow", 8],
	["wa", "wa", 5],
	["un", "un", 1],
	["nn", "nn", 2],
	["banzai", "banzai", 8],
]

var args := {}
var main: Node3D
var cam: Camera3D
var p: Node3D
var bot: Node3D
var hub: Node3D
var _log: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)
	_run.call_deferred()


func _wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


## 姿勢の時計で、ev のコマ + k になるまで待つ
func _wait_pose(frame: int) -> void:
	while Doll.frame_index() < frame:
		await physics_frame
	await process_frame
	await process_frame


func _run() -> void:
	await _wait_frames(30)
	p = main.player
	hub = main.emotes
	var bots := main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))
	bot = bots[0]
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	hub.happened.connect(func(ev): _log.append("%d %s who=%s" % [ev.frame, ev.kind, str(ev.get("who", "-"))]))
	if args.has("check"):
		await _check()
		quit()
		return
	bot.set_physics_process(false)   # 仲間は止めて、人形だけ動かす
	var only: Array = args["only"].split(",") if args.has("only") else []
	var view: String = args.get("view", "fp")
	p.set_third(view == "tp")   # 保存された設定に関わらず、撮る視点で始める
	var dir: String = args.get("dir", "/tmp")
	DirAccess.make_dir_recursive_absolute(dir)
	for shot in SHOTS:
		if not only.is_empty() and not shot[0] in only:
			continue
		await _stage(shot[1])
		var f := await _act(shot[1])
		await _wait_pose(f + shot[2])
		_camera(view, shot[1])
		await process_frame
		await process_frame
		var path := dir.path_join("%s_%s.png" % [shot[0], view])
		root.get_texture().get_image().save_png(path)
		print("保存: ", path, "  人形=", p.doll.emote_now())
		# 身ぶりが終わるまで（振りかぶりは離すまで続くので、ここで解く）
		if shot[1] == "windup":
			p._winding = false
			p.doll.emote = {}
		while not p.doll.emote.is_empty() or p.rooted() or not bot.doll.emote.is_empty():
			await physics_frame
		await _wait_frames(30)
		p.holding_ball = false
		p._winding = false
	quit()


## 立ち位置をそろえる。あなたは丘の上を向き、仲間は 1.25 m 前でこちらを向く。ソリは横へ
func _stage(kind: String) -> void:
	var sled: RigidBody3D = main.sled
	if p.mode == p.Mode.RIDE:
		p.get_off()
	var base := Vector3(6.0, 0, 30.0)
	base.y = main.height(base.x, base.z)
	var riding := kind == "banzai"
	sled.freeze = true
	var sp := base + Vector3(-3.0, 0, 0) if not riding else base
	if kind == "sled":
		sp = base + Vector3(0, 0, -3.5)
	sp.y = main.height(sp.x, sp.z) + 0.02
	sled.global_transform = Transform3D(Basis.IDENTITY, sp)
	if riding:
		p.global_position = sp + Vector3(0, 0.3, 1.5)
		p.get_on()
		p.rotation.y = 0.0
		p._pitch = -0.1
	else:
		p.global_position = base + Vector3.UP * 0.05
		p.rotation.y = 0.0
		p._pitch = -0.18 if kind != "make_ball" else -0.35
		p.velocity = Vector3.ZERO
	var d := 1.25 if kind in ["whiff", "hand_up"] else 2.6
	var bp := base + Vector3(0.0 if d < 2.0 else 0.9, 0, -d)
	if kind == "sled":
		bp = base + Vector3(2.0, 0, 1.5)   # ソリの写りを塞がないよう、うしろへ
	bp.y = main.height(bp.x, bp.z)
	bot.global_position = bp
	bot.look_at(Vector3(p.global_position.x, bp.y, p.global_position.z), Vector3.UP)
	bot.doll.act = Doll.Act.WALK
	bot.doll.gaze = p.global_position + Vector3.UP * 1.25
	await _wait_frames(12)


## 身ぶりを出す。返り値は出来事のコマ
func _act(kind: String) -> int:
	var f := Doll.frame_index() + 1
	match kind:
		"high_five":
			# 2.6 m 離れて二人とも手のひらを掲げ、あなたが歩いて近づく → 届いた所で合う
			hub.send({"kind": "hand_up", "who": bot.id})
			await _wait_frames(12)
			p.emote("hand_up")
			var n := _log.size()
			for i in 200:
				if _log.slice(n).any(func(l): return " high_five " in l):
					break
				p.global_position += Vector3(0, 0, -0.025)
				await physics_frame
			f = await _until_logged(n, "high_five")
		"whiff":
			hub.send({"kind": "hand_up", "who": bot.id})
			await _wait_frames(10)
			bot.look_at(bot.global_position + Vector3(1, 0, 0), Vector3.UP)   # 仲間がよそを向いている → 合わない
			await _wait_frames(10)
			var n := _log.size()
			p.emote("hand_up")
			f = await _until_logged(n, "whiff")   # 待ちが切れて空振り
		"windup", "throw":
			p.holding_ball = true
			p.wind_up()
			if kind == "throw":
				await _wait_frames(30)
				f = Doll.frame_index() + 1
				p.throw_ball()
		"hit_bot", "sled":
			# あなたが投げ、当たったコマを撮る
			p.holding_ball = true
			var at: Vector3 = main.sled.global_position if kind == "sled" else bot.global_position + Vector3.UP * 0.8
			var to := at - p.global_position
			p.rotation.y = atan2(-to.x, -to.z)
			p._pitch = -0.32 if kind == "sled" else -0.12
			await _wait_frames(6)
			p.wind_up()
			await _wait_frames(20)
			var n := _log.size()
			p.throw_ball()
			f = await _until_logged(n, "hit" if kind == "hit_bot" else "splat")
		"hit_me":
			var from: Vector3 = bot.global_position + Vector3.UP * 1.0
			var to: Vector3 = p.global_position + Vector3.UP * 0.9
			var n := _log.size()
			hub.send({"kind": "throw", "who": bot.id, "origin": from, "velocity": (to - from) / 0.35 + Vector3.UP * 0.5 * 9.8 * 0.35})
			f = await _until_logged(n, "hit")
		_:
			p.emote(kind)
	return f


## 記録の n 番目から先に kind が出るまで待ち、そのコマを返す
func _until_logged(n: int, kind: String) -> int:
	for i in 600:
		for j in range(n, _log.size()):
			var parts := _log[j].split(" ")
			if parts[1] == kind:
				return int(parts[0])
		await physics_frame
	print("出なかった: ", kind)
	return Doll.frame_index()


func _camera(view: String, kind: String) -> void:
	match view:
		"fp", "tp":
			p.set_third(view == "tp")
			p._place_camera(1.0, 0.0, false)   # 視点をすぐ合わせる（寄ってくる途中を撮らない）
			p.cam.current = true
		_:
			# 正面の少し横から、二人が見えるように
			var me: Vector3 = p.global_position
			var tgt := me + Vector3(0, 0.75, -0.6)
			if kind == "banzai":
				tgt = me + Vector3(0, 0.6, 0)
				cam.look_at_from_position(me + Vector3(2.8, 1.2, -2.2), tgt)
			elif kind == "sled":
				var at: Vector3 = main.sled.global_position
				cam.look_at_from_position(at + Vector3(2.6, 1.3, 1.6), at + Vector3(0, 0.6, 0))
			elif kind in ["high_five", "whiff", "hand_up", "hit_bot", "hit_me"]:
				# 二人のあいだを、横から
				var mid: Vector3 = (me + bot.global_position) * 0.5
				var across: Vector3 = bot.global_position - me
				across.y = 0
				var side := across.normalized().cross(Vector3.UP)
				cam.look_at_from_position(mid + side * 2.8 + Vector3.UP * 1.0, mid + Vector3.UP * 0.75)
			else:
				cam.look_at_from_position(me + Vector3(2.9, 1.1, -0.9), tgt)
			cam.current = true


## 仲間の返しを確かめる: 近くで手を上げる → 仲間が来てハイタッチ。声 → 同じ声。おじぎ → おじぎ
func _check() -> void:
	var sled: RigidBody3D = main.sled
	await _wait_frames(240)   # 仲間がソリを押しはじめるまで
	p.global_position = bot.global_position + Vector3(2.5, 0.3, 1.5)
	p.look_at(Vector3(bot.global_position.x, p.global_position.y, bot.global_position.z), Vector3.UP)
	await _wait_frames(10)
	p.emote("hand_up")
	await _wait_frames(240)
	p.emote("wa")
	await _wait_frames(120)
	p.emote("nn")
	await _wait_frames(120)
	p.global_position = bot.global_position + Vector3(0, 0.3, 2.0)
	p.look_at(Vector3(bot.global_position.x, p.global_position.y, bot.global_position.z), Vector3.UP)
	await _wait_frames(4)
	p.emote("bow")
	await _wait_frames(180)
	for line in _log:
		print("出来事: ", line)
	var five := _log.filter(func(l): return " high_five " in l).size()
	print("ハイタッチ=%d 仲間の声=%d おじぎ返し=%d 仲間の状態=%s" % [five,
			_log.filter(func(l): return (" wa " in l or " nn " in l) and l.ends_with("who=%d" % bot.id)).size(),
			_log.filter(func(l): return " bow " in l and l.ends_with("who=%d" % bot.id)).size(), bot.state])
