extends SceneTree
## 画面の明るさのちらつきを測る（確かめ用）。立ったまま動かずに、画面全体の平均の明るさを 1 コマごとに記録し、
## 前のコマとの差が大きいコマの数と、明るさの最小・最大を出す。
##   Godot --path game --resolution 1280x720 -s res://tools/flicker_probe.gd -- --bots=0 [--secs=8] [--from=2] [main.gd の引数]
## 動かないので、明るさが変わるならそれは画面のちらつき（光・露出・空の更新など）。

var args := {}
var main: Node3D
var t := 0.0
var _prev := -1.0
var _vals: Array[float] = []
var _jumps := 0
var _big := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 時刻の仕組み（daycycle.gd）は current_scene から太陽と空を探す


var _placed := false


func _process(dt: float) -> bool:
	t += dt
	var from := float(args.get("from", "2"))
	var p = main.player
	if p and t < 0.5:   # 保存してある設定によらず、一人称（--third で三人称）
		p.set_third(args.has("third"))
	if main.settings and main.settings.is_open:   # 窓へ入ったキーやマウスで設定画面が開かないように
		main.settings.set_open(false)
		p.menu_open = false
	if main.hud and args.has("no-hud"):
		main.hud.visible = false
	if main.get("self_cam") and args.has("no-self"):
		main.self_cam.visible = false
	if p and args.has("look"):   # 見回す（度/秒）
		p.rotation.y += deg_to_rad(float(args["look"])) * dt
	if p and args.has("ride") and not _placed and t > 0.6:   # 頂上のすぐ下でソリに乗り、W を押したまま滑る
		_placed = true
		var sled: RigidBody3D = main.sled
		var at := Vector3(0, 0, 3)
		at.y = main.height(at.x, at.z) + 0.6
		sled.reset_to(at)
		sled.global_transform = Transform3D(Basis(Vector3.UP, PI), at)
		p.global_position = at + Vector3(1.2, 0.3, 0)
		p.get_on()
		p.rotation.y = PI
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
	if args.has("sweep"):   # --sweep=始め,終わり: 測る間に、時刻を 1 コマずつ決まった分だけ進める（窓の前後に左右されない）
		var se: PackedStringArray = String(args["sweep"]).split(",")
		var k := clampf((t - from) / float(args.get("secs", "8")), 0.0, 1.0)
		root.get_node("/root/DayCycle").hour = lerpf(float(se[0]), float(se[1]), k)
	if t < from:
		return false
	var full := root.get_texture().get_image()
	if args.has("dump") and t >= float(args.get("dump-from", "0")) and t <= float(args.get("dump-to", "0")):   # 決めた時間のコマを全部保存
		DirAccess.make_dir_recursive_absolute(args["dump"])
		full.save_jpg("%s/f_%05.2f.jpg" % [args["dump"], t], 0.8)
	var img := full.duplicate()
	img.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var s := 0.0
	for y in img.get_height():
		for x in img.get_width():
			s += img.get_pixel(x, y).get_luminance()
	var v := s / float(img.get_width() * img.get_height())
	_vals.append(v)
	if _prev >= 0.0:
		var d := absf(v - _prev)
		_big = maxf(_big, d)
		if d > 0.01:
			_jumps += 1
			print("t=%.2f 明るさ %.3f → %.3f（差 %.3f）" % [t, _prev, v, d])
	_prev = v
	if t >= from + float(args.get("secs", "8")):
		var lo: float = _vals.min()
		var hi: float = _vals.max()
		print("結果: コマ %d・差 0.01 を超えたコマ %d・いちばん大きい差 %.3f・明るさ %.3f〜%.3f" % [_vals.size(), _jumps, _big, lo, hi])
		quit()
	return false
