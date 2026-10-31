extends SceneTree
## ハイタッチの手のひらの向きを、立ち位置を変えて測る（手が内側に傾きすぎないかの確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/five_tilt_check.gd -- [--dir=/path/to/dir]
## あなたと仲間を、距離・横のずれ・体の向き・使う手を変えて立たせ、手が合ったコマで、二人の手形の向きを出す。
##   相手へ: 手のひらの向きと、相手への向き（体どうし、水平）の角度。0° なら相手へまっすぐ
##   体から: 手のひらの向きと、自分の体の前の角度
##   重なり: 二人の手のひらの向きの角度（180° でぴったり向かい合う）
##   傾き: 手形の指（+y）の、真上からの角度
## --dir を付けると、場面ごとに、あなたの三人称と一人称で撮る（番号_tp.png・番号_fp.png）

const Doll := preload("res://doll.gd")

## [名前, 距離 m, 仲間の横のずれ m（あなたの右が +）, あなたの体の向き（度、左が +）, あなたの手, 仲間の手]
const CASES := [
	["正面 1.25m 右と右", 1.25, 0.0, 0.0, "R", "R"],
	["正面 0.8m 右と右", 0.8, 0.0, 0.0, "R", "R"],
	["正面 0.5m 右と右", 0.5, 0.0, 0.0, "R", "R"],
	["正面 0.8m 右と左", 0.8, 0.0, 0.0, "R", "L"],
	["斜め 0.9m 仲間が左へ 0.6m", 0.9, -0.6, 0.0, "R", "R"],
	["斜め 0.9m 仲間が右へ 0.6m", 0.9, 0.6, 0.0, "R", "R"],
	["体が 50° 左向き 0.9m", 0.9, 0.0, 50.0, "R", "R"],
	["正面 0.8m 両手と両手", 0.8, 0.0, 0.0, "both", "both"],
]

var args := {}
var main: Node3D
var p
var bot
var hub


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	await _frames(30)
	p = main.player
	hub = main.emotes
	bot = main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))[0]
	bot.set_physics_process(false)
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	p.set_third(true)
	var dir: String = args.get("dir", "")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var i := 0
	for c in CASES:
		hub.send({"kind": "hands", "who": p.id, "hands": ""})
		hub.send({"kind": "hands", "who": bot.id, "hands": ""})
		while not p.doll.emote.is_empty() or not bot.doll.emote.is_empty():
			await physics_frame
		# 離して立たせてから手を掲げ、仲間を置く（置いたとたんに合う）
		var base := Vector3(6.0, 0, 30.0)
		base.y = main.height(base.x, base.z)
		p.global_position = base + Vector3.UP * 0.05
		p.velocity = Vector3.ZERO
		p.rotation.y = deg_to_rad(c[3])
		p.doll.rotation.y = 0.0
		bot.global_position = base + Vector3(30, 0, 0)
		await _frames(10)
		p._set_hand(c[4])
		p.set_height("high")
		hub.send({"kind": "hands", "who": bot.id, "hands": "high_%s" % c[5]})
		await _frames(4)
		p.global_position = base + Vector3.UP * 0.05   # 坂で滑っていたら戻す
		p.velocity = Vector3.ZERO
		var bp: Vector3 = base + Vector3(c[2], 0, -c[1])
		bp.y = main.height(bp.x, bp.z)
		bot.global_position = bp
		bot.look_at(Vector3(base.x, bp.y, base.z), Vector3.UP)
		bot.doll.act = Doll.Act.WALK
		var ok := false
		for n in 60:
			await physics_frame
			var em: Array = p.doll.emote_now()
			if em[0] == "high_five" and em[1] == 4:
				ok = true
				break
		await process_frame
		if not ok:
			print("%s: 合わなかった（あなたの身ぶり %s、二人の間 %.1f m）" % [c[0], p.doll.emote_now(), p.global_position.distance_to(bot.global_position)])
			continue
		print("%s:%s" % [c[0], _measure()])
		if dir != "":
			# 遊ぶ人の目で: 三人称（うしろから）と一人称
			for v in ["tp", "fp"]:
				p.set_third(v == "tp")
				p._place_camera(1.0, 0.0, false)
				p.cam.current = true
				await process_frame
				await process_frame
				RenderingServer.force_draw()
				root.get_texture().get_image().save_png(dir.path_join("%02d_%s.png" % [i, v]))
			p.set_third(true)
		i += 1
	quit()


func _measure() -> String:
	var out := ""
	var normals := []
	for who in [p, bot]:
		var other = bot if who == p else p
		var d: Doll = who.doll
		var ab: Vector3 = other.global_position - who.global_position
		ab.y = 0
		ab = ab.normalized()
		var fwd := -d.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		for side in [1, -1]:
			var node: Node3D = d._shapes["palm"][side]
			if not node.visible:
				continue
			var b := node.global_basis.orthonormalized()
			var n := b.z   # 手のひら
			var nf := Vector3(n.x, 0, n.z).normalized()
			normals.append(n)
			out += "  %s%s: 相手へ %.0f° 体から %.0f° 傾き %.0f°" % ["あなた" if who == p else "仲間", "右" if side > 0 else "左",
				rad_to_deg(nf.angle_to(ab)), rad_to_deg(nf.angle_to(fwd)), rad_to_deg(b.y.angle_to(Vector3.UP))]
	if normals.size() >= 2:
		out += "  重なり %.0f°" % rad_to_deg((normals[0] as Vector3).angle_to(normals[normals.size() - 1]))
	return out
