extends SceneTree
## 画面の表示（hud.gd）を、場面ごとに一人称で撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/hud_shots.gd -- --scene=base --out=/path/to.png [--at=秒]
## 場面:
##   base    ふもと。ソリの後ろに立つ（つかむの案内）
##   side    ソリの横に立つ（つかむ・乗るの案内）
##   push    仲間と一緒に押して登っている（札の人の形と糸の矢印、押すの案内）
##   top     頂上で乗っている、止まっている（前に乗り出す・降りるの案内）
##   ride    乗って滑り降りている（体重をかける・止まるの案内）
##   people  ソリから離れて、仲間のそばにいる（身ぶりの案内）
##   lodge   ロッジの中（札は消える）
##   menu    Esc を押したとき（操作の札）
##   ring    Tab で身ぶりの輪を出したとき（仲間のそば）
## --tp で三人称（--cam-dist=m・--cam-height=m でカメラの距離と高さ。保存しない）。
## --hud-scale=0.7〜1.6 と --menu-scale=0.7〜1.6 で、設定の「HUD の大きさ」「メニューの大きさ」を、保存せずに当てて撮る。
## main.gd の引数（--bots など）もそのまま効く。

var args := {}
var main: Node3D
var t := 0.0
var _set := false
var _mash_n := -1
var _frame_k := -1


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


## ソリを丘の上の、頂上から r m の所に置く。yaw はソリの向き（0 で頂上を向く、PI で下りを向く）
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


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var sled: RigidBody3D = main.sled
	if p == null or sled == null:
		return false
	var scene: String = args.get("scene", "base")
	if not _set and t > 0.6:
		_set = true
		p.set_third(false)
		match scene:
			"base":
				_face(p, sled.global_position, -0.2)
			"side":
				p.global_position = sled.to_global(Vector3(2.1, 0, 0.3)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.3)
			"push":
				p.global_position = sled.to_global(Vector3(0, 0, 2.2)) + Vector3.UP * 0.2
				_face(p, sled.global_position, -0.15)
				p.grab()
				_key(KEY_W, true)
			"top":
				_place_sled(2.5, PI)
				p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
				p.get_on()
				p.rotation.y = sled.global_rotation.y
				p._pitch = -0.15
			"ride":
				_place_sled(float(args.get("from", "9")), PI)
				p.global_position = sled.global_position + sled.global_basis.x * 1.2 + Vector3.UP * 0.3
				p.get_on()
				p.rotation.y = sled.global_rotation.y
				p._pitch = -0.2
				sled.linear_velocity = -sled.global_basis.z * float(args.get("v0", "4"))
				if args.has("best"):   # 今日いちばんの速さを、前にこれだけ出したことにする（超えると紙吹雪）
					main.hud.spd_best = float(args["best"])
			"people":
				p.global_position = sled.to_global(Vector3(5.0, 0, 3.5)) + Vector3.UP * 0.3
			"lodge":
				if main.has_node("Audio"):
					p.global_position = main.get_node("Audio").spawn_point("inside")
				p._pitch = -0.05
			"menu":
				main.settings.set_open(true)
				p.menu_open = true
			"ring":
				p.global_position = sled.to_global(Vector3(5.0, 0, 3.5)) + Vector3.UP * 0.3
				_key(KEY_TAB, true)
		# --tp で三人称に。--cam-dist・--cam-height でカメラの距離と高さ（保存はしない）
		if args.has("tp"):
			p.set_third(true)
			p.cam_dist = float(args.get("cam-dist", str(p.cam_dist)))
			p.cam_height = float(args.get("cam-height", str(p.cam_height)))
		# 大きさの設定は、保存してある値に関わらず、引数の値で（保存はしない）
		if args.has("hud-scale"):
			preload("res://hud_icons.gd").user_scale = float(args["hud-scale"])
		if args.has("menu-scale"):
			main.settings.values["menu_scale"] = float(args["menu-scale"])
			main.settings._layout()
	if _set and t < 1.5:   # 360° 映像は、保存してある設定に関わらず出す（設定は書き換えない）
		main.pip_hidden = false
		if main._pip_layer: main._pip_layer.visible = true
	if _set and (scene == "base" or scene == "side"):   # 仲間がソリを動かしても、ソリとの位置を保つ
		var off := Vector3(0, 0, 2.6) if scene == "base" else Vector3(2.1, 0, 0.3)
		var want := sled.to_global(off)
		want.y = main.height(want.x, want.z) + 0.1
		p.global_position = want
		_face(p, sled.global_position, -0.3)
	if _set and scene != "menu" and main.settings.is_open:   # 撮るあいだは設定の画面を開かない（窓の切り替えなどで開くことがある）
		main.settings.set_open(false)
		p.menu_open = false
	if main.hud and not args.has("hud-debug"):
		main.hud.debug_on = false   # 保存してある「確かめ用の数字」に関わらず消す
	if _set and (scene == "people" or scene == "ring"):
		var bots := main.get_children().filter(func(c): return c != p and c is CharacterBody3D and c.get("doll") != null)
		if bots.size() > 0:
			_face(p, bots[0].global_position + Vector3.UP * 1.2, -0.05)
	if _set and args.has("pitch"):   # 見上げる・見下ろす（空や床を背景にして撮る）
		p._pitch = float(args["pitch"])
	if _set and scene == "ride":
		p.rotation.y = sled.global_rotation.y
		# --mash=回: 乗っているあいだ、1 秒にこの回数 Space を押す（米袋の足漕ぎ）
		if args.has("mash") and p.mode == p.Mode.RIDE:
			var n := int(t * float(args["mash"]))
			if n != _mash_n:
				_mash_n = n
				_key(KEY_SPACE, true)
				_key(KEY_SPACE, false)
		if args.has("log-speed") and int(t * 2.0) != int((t - dt) * 2.0):
			print("t=%.1f 速さ=%.1f 表示=%.2f いちばん=%.1f" % [t, sled.linear_velocity.length(), main.hud._spd_a, main.hud.spd_best])
	# --frames=N: --at から --every 秒ごとに N 枚、out の .png の前に _00 の番号を付けて保存する（動きを見る用）
	if args.has("frames") and t > float(args.get("at", "4")):
		var n := int(args["frames"])
		var every := float(args.get("every", "0.0417"))
		var k := int((t - float(args.get("at", "4"))) / every)
		if k != _frame_k and k < n:
			_frame_k = k
			var base: String = args.get("out", "/tmp/hud.png").trim_suffix(".png")
			root.get_texture().get_image().save_png("%s_%02d.png" % [base, k])
		if k >= n:
			print("保存: %d 枚  速さ: %.1f" % [n, sled.linear_velocity.length()])
			return true
		return false
	if t > float(args.get("at", "4")):
		var out: String = args.get("out", "/tmp/hud.png")
		root.get_texture().get_image().save_png(out)
		if p.get("ring"): print("輪: ", p.ring.visible, " ", p.ring.scale, " ", p.menu_open)
		print("保存: ", out, "  案内: ", main.hud.uses, "  押している人: ", sled.pushers, "  速さ: %.1f" % sled.linear_velocity.length())
		return true
	return false
