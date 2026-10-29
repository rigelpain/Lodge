extends SceneTree
## 頂上からソリに乗って滑り降り、一人称の画面を撮る（滑るときの風の確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/ride_shots.gd -- --bots=0 --dir=/path/shots [--slow=4] [--fast=8.5]
##       [--wind=0〜1] [--calm] [--no-wind] [--novsync] [--tag=名前] [--secs=40]
## 重さを比べるときは --novsync（画面の書き換えを待たずに描く）で、--no-wind と並べる。
## 乗ってすぐ（止まっている）、--slow の速さを超えたとき、--fast を超えたとき、止まって風が消えたときに撮る。
## 頂上のすぐ下に、ふもと（+z）へ向けてソリを置き、W を押したまま（前傾）で滑り出す。
## 1 秒ごとに速さ・風の強さ・fps を出し、終わりに滑っている間の平均と最も重いコマを出す。
## 360° 映像と文字は撮らない（風が流れる画面の端を見るため）。
## 滑るときの視野角の確かめ: --sled=sack|small|mid|large（main.gd の引数）で大きさを変え、--mash=回/秒 で
## 乗っているあいだ Space を連打する（米袋の足漕ぎ）。いちばん速かった所を 4_top に撮り、撮るたびに足した視野角を出す。

var args := {}
var main: Node3D
var t := 0.0
var _placed := false
var _riding_t := -1.0
var _taken := {}
var _top_speed := 0.0
var _log_t := 0.0
var _ft_sum := 0.0
var _ft_n := 0
var _ft_max := 0.0
var _top_img: Image
var _top_grab := 0.0
var _mash_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	# 窓が隠れると描画が止まり、前の絵を保存してしまうので、撮る間はいちばん前に置く
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if args.has("novsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/ride_shots"))


func _shot(name: String) -> void:
	if _taken.has(name):
		return
	_taken[name] = true
	var tag: String = args.get("tag", "")
	var path := "%s/%s%s.png" % [args.get("dir", "/tmp/ride_shots"), name, ("_" + tag) if tag != "" else ""]
	root.get_texture().get_image().save_png(path)
	var w = main.ride_wind
	var p = main.player
	print("撮影: %s 速さ=%.1f 風=%.2f 視野角=%.1f°（足した分 %.1f°）" % [path, main.sled.linear_velocity.length(), w.level if w else 0.0, p.cam.fov, p.ride_fov])


func _process(dt: float) -> bool:
	t += dt
	var sled: RigidBody3D = main.sled
	var p = main.player
	if sled == null or p == null:
		return false
	if main.hud:
		main.hud.visible = false
	# 撮っている間に窓へ入ったキーやマウスで、設定画面が開いたり視点が動いたりしないように
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	if _riding_t >= 0.0:
		p.rotation.y = PI
		p._pitch = float(args.get("pitch", "-0.1"))
	if main._pip_layer:
		main.pip_hidden = true
		main._pip_layer.visible = false
	if main.ride_wind:
		if args.has("wind"):
			main.ride_wind.strength = float(args["wind"])
		main.ride_wind.calm = args.has("calm")   # 保存してある「視点の揺れ」によらず、既定の強さで撮る

	if not _placed and t > 0.6:
		# 頂上のすぐ下に、ふもとへ向けて置いて乗る
		_placed = true
		var at := Vector3(0, 0, float(args.get("from", "3")))
		at.y = main.height(at.x, at.z) + 0.6
		sled.reset_to(at)
		sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
		p.global_position = at + Vector3(1.2, 0.3, 0)
		p.get_on()
		p.set_third(args.has("third"))   # 保存してある設定が三人称でも、一人称で撮る（--third で三人称）
		p.base_fov = float(args.get("fov", "75"))   # 保存してある視野角によらず、既定の 75° で撮る（--fov= で変える）
		p.ride_fov_enabled = not args.has("no-ride-fov")
		p.cam_dist = float(args.get("cam-dist", "3.4"))   # 三人称のカメラの距離も既定で
		p.cam_frame = -0.2
		p.rotation.y = PI
		p._pitch = float(args.get("pitch", "-0.1"))
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		_riding_t = t
		print("乗る: mode=%d 高さ=%.1f" % [p.mode, at.y])
		return false
	if _riding_t < 0.0:
		return false

	var speed := sled.linear_velocity.length()
	var rt := t - _riding_t
	_top_speed = maxf(_top_speed, speed)
	if speed > 2.0:
		_ft_sum += dt
		_ft_n += 1
		_ft_max = maxf(_ft_max, dt)
	if rt > 0.3 and rt < 0.6:
		_shot("0_still")
	if speed > float(args.get("slow", "4")) and rt > 1.0:
		_shot("1_slow")
	if speed > float(args.get("fast", "8.5")):
		_shot("2_fast")
	var w = main.ride_wind
	if _taken.has("1_slow") and speed < 1.0 and rt > 6.0 and (w == null or w.level < 0.02) and p.ride_fov < 0.3:   # 風が消え、画角が戻ってから
		_shot("3_stopped")
	# いちばん速い所: 速さが伸びるたびに（0.2 秒おきに）画面を取っておき、終わりに書く
	_top_grab -= dt
	if speed >= _top_speed and _top_grab <= 0.0 and speed > 2.0:
		_top_grab = 0.2
		_top_img = root.get_texture().get_image()
		_top_img.set_meta("info", "速さ=%.1f 風=%.2f 視野角=%.1f°（足した分 %.1f°）" % [speed, w.level if w else 0.0, p.cam.fov, p.ride_fov])
	# --mash=回/秒: 乗っているあいだ Space を連打する（米袋の足漕ぎ）
	if args.has("mash") and p.mode == p.Mode.RIDE and not _taken.has("3_stopped"):
		_mash_t -= dt
		if _mash_t <= 0.0:
			_mash_t = 1.0 / float(args["mash"])
			for down in [true, false]:
				var ev := InputEventKey.new()
				ev.physical_keycode = KEY_SPACE
				ev.pressed = down
				Input.parse_input_event(ev)
	_log_t += dt
	if _log_t >= 1.0:
		_log_t = 0.0
		print("t=%.0f 速さ=%.1f 高さ=%.1f 風=%.2f 足した視野角=%.1f° fps=%d" % [rt, speed, sled.global_position.y, w.level if w else 0.0, p.ride_fov, Engine.get_frames_per_second()])
	if rt > float(args.get("secs", "40")) or _taken.has("3_stopped"):
		if _top_img:
			var tag: String = args.get("tag", "")
			var path := "%s/4_top%s.png" % [args.get("dir", "/tmp/ride_shots"), ("_" + tag) if tag != "" else ""]
			_top_img.save_png(path)
			print("撮影: %s %s" % [path, _top_img.get_meta("info")])
		print("最高の速さ=%.1f m/s　滑っている間 平均 %.1f ms（%.0f fps）最も重いコマ %.1f ms" % [_top_speed, 1000.0 * _ft_sum / maxi(_ft_n, 1), _ft_n / maxf(_ft_sum, 0.001), 1000.0 * _ft_max])
		quit()
	return false
