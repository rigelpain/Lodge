extends SceneTree
## 長い滑りで、速さの表示の糸の上に積もるボタンが表示からはみ出さず、10 個ずつ上の素材に両替されるのを、続けて撮った絵と
## 音の記録で確かめる（hud.gd の _exchange・speedo.gd）。あなたが大きな山（mountain.gd）の頂上から滑る。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/spool_exchange_shots.gd -- --bots=0 --no-pip --dir=/path/shots \
##       [--sled=large --riders=7]（大に、あなたと人形 7 人）[--sled=sack --mash=10]（米袋で 1 秒に 10 回漕ぐ。受け皿の 30 m 手前まで）
## 速さの表示のまわりを、1 秒ごとと、両替が始まった所から 2 コマおきに切り抜いて並べる（<dir>/spool_<ソリ>.png）。
## 終わりに、鳴った音（両替のチン・財布のチャリ・締めくくり）と、自分の分（ride_pay_one）、財布に入った値打ちを出す。

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

var args := {}
var main: Node3D
var _crops: Array[Image] = []
var _t0 := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/spool"))
	_run.call_deferred()


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second) - _t0


func _crop() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var hud = main.hud
	var box: Rect2 = hud.speedo_box_now()
	var rect := Rect2i(int(box.position.x - 6), int(box.position.y - 6), int(box.size.x + 12), int(box.size.y + 12))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	_crops.append(img.get_region(rect))


func _run() -> void:
	for i in 20:
		await process_frame
	var p = main.player
	var sb = main.snow_buttons
	var audio = main.get_node_or_null("Audio")
	var Mountain := preload("res://mountain.gd")
	sb.auto = false
	sb.clear()
	var sled: RigidBody3D = main.sled
	var top := Vector3(Mountain.COURSE_X, 0, Mountain.section("頂上")[1] + 1.0)
	var at := Vector3(top.x, main.height(top.x, top.z) + 0.6, top.z)
	if args.get("sled", "") == "sack":
		p.global_position = at + Vector3.UP * 0.2
		p.rotation.y = 0.0   # 前は -z（山を下る向き）
		p.toggle_sack()
		for i in 40:
			await process_frame
		sled = main.craft.sack_sled(p.id)
	else:
		sled.reset_to(at)
		sled.global_transform = Transform3D(Basis(), at)
		p.global_position = at + Vector3(1.2, 0.3, 0)
		p.get_on()
		p.rotation.y = 0.0
		var dummy := GDScript.new()
		dummy.source_code = DUMMY_SRC
		dummy.reload()
		for i in int(args.get("riders", "0")):
			var d := Node3D.new()
			d.set_script(dummy)
			d.sled = sled
			main.add_child(d)
			sled.mount(d)
	p._pitch = -0.1
	var mine: Array = []
	var marks := [0]
	var earned := [0]
	sb.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "ride_mark":
			marks[0] += 1
		elif ev.kind == "ride_pay_one" and int(ev.who) == int(p.id):
			mine.append("%.1f 秒  自分の分 %d（縫い込んだ数 %d）" % [_now(), ev.n, ev.sewn.size()]))
	main.craft.happened.connect(func(ev: Dictionary) -> void:
		if ev.kind == "earn" and int(ev.who) == int(p.id):
			earned[0] += int(ev.n))
	audio.log_on = true
	_t0 = Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)
	sled.linear_velocity = Vector3(0, 0, -2.0)
	var next_shot := 0.0
	var merging_shots := 0
	var mash := float(args.get("mash", "0"))
	var next_kick := 0.0
	var end_at := -1.0
	var hud = main.hud
	var most := 0
	while true:
		await process_frame
		if main.settings and main.settings.is_open:
			main.settings.set_open(false)
			p.menu_open = false
		var t := _now()
		# 漕ぐのは受け皿（Mountain.BOTTOM_Z）の手前まで。平らな所でも漕げるので、やめないと止まらない
		if mash > 0.0 and is_instance_valid(sled) and p.mode == p.Mode.RIDE and t >= next_kick and sled.global_position.z > Mountain.BOTTOM_Z + 30.0:
			next_kick = t + 1.0 / mash
			sled.kick(p)
		most = maxi(most, hud.sewn_looks().size())
		if hud._merge_t0 >= 0.0 and merging_shots < 4 and _crops.size() < 40:
			merging_shots += 1
			await _crop()
			for k in 2:
				await process_frame
			continue
		if hud._merge_t0 < 0.0:
			merging_shots = 0
		if t >= next_shot and _crops.size() < 40:
			next_shot = t + 2.0
			await _crop()
		if not mine.is_empty() and end_at < 0.0:
			end_at = t
		if end_at >= 0.0 and t - end_at < 2.5 and _crops.size() < 48:
			await _crop()
			for k in 4:
				await process_frame
		if end_at >= 0.0 and t - end_at > 4.0:
			break
		if t > 150.0:
			print("時間切れ")
			break
	audio.log_on = false
	print("---- 鳴った音（両替・財布・締めくくり）")
	for e in audio.played:
		var n: String = e.name
		if n.begins_with("button_take") or n.begins_with("button_glint") or n.begins_with("button_reward") or n.begins_with("button_chari"):
			print("%.2f 秒  %s" % [e.t - _t0, n])
	print("---- 自分の分")
	for e in mine:
		print(e)
	print("縫い込まれた数 %d、糸の上にいちばん多く並んだ数 %d、財布に入った値打ち %d" % [marks[0], most, earned[0]])
	_sheet()
	quit()


func _sheet() -> void:
	if _crops.is_empty():
		return
	var w := _crops[0].get_width()
	var h := _crops[0].get_height()
	var cols := 12
	var rows := ceili(_crops.size() / float(cols))
	var out := Image.create(cols * (w + 4) + 4, rows * (h + 4) + 4, false, Image.FORMAT_RGB8)
	out.fill(Color(0.15, 0.15, 0.18))
	for i in _crops.size():
		var im := _crops[i]
		im.convert(Image.FORMAT_RGB8)
		if im.get_width() != w or im.get_height() != h:
			im.resize(w, h)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(4 + (i % cols) * (w + 4), 4 + (i / cols) * (h + 4)))
	var path := "%s/spool_%s.png" % [args.get("dir", "/tmp/spool"), args.get("sled", "mid")]
	out.save_png(path)
	print("並べた 1 枚: ", path)
