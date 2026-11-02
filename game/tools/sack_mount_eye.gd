extends SceneTree
## 走りながら（または止まって）米袋を出して乗る所を、一人称で 1/15 秒ごとに撮る（乗るときの目線の確かめ用）。
##   Godot --path game --resolution 960x540 --fixed-fps 30 -s res://tools/sack_mount_eye.gd -- --bots=0 --no-sound --no-pip --dir=/path/frames [--still] [--view=tp]
## 平らな所に立たせ、Shift+W で 1.2 秒走ってから N（--still なら立ったまま N）。W は押したまま。
## N の 0.2 秒前から 2 秒あとまでを、2 コマおき（15 枚／秒）に dir へ連番の PNG で。log.txt に、そのときの見下ろし（_pitch）と速さ

var args := {}
var main: Node3D
var p: CharacterBody3D
var f := 0          # 30 枚／秒のコマ
var n := 0
var lines: Array[String] = []
const START := 75   # 読み込みを待つ (2.5 秒)
const RUN := 36     # 走る長さ (1.2 秒)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())


func _dir() -> String:
	return args.get("dir", "/tmp/sack_mount_eye")


func _press(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _process(_dt: float) -> bool:
	f += 1
	p = main.player
	if p == null:
		return false
	if main.hud:
		main.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # 撮っているあいだに手もとのマウスが動いても、見ている向きが動かないように
	var still := args.has("still")
	var n_at := START + (15 if still else RUN)
	if f == START:
		var d := Vector2(1, -1).normalized()
		var at := Vector2(60, -60) - d * (0.0 if still else 4.0)   # 止まって乗るときは、走って N を押すあたりから
		var pos := Vector3(at.x, 0, at.y)
		pos.y = main.height(pos.x, pos.z) + 0.2
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-d.x, -d.y)
		p.set("_pitch", float(args.get("pitch", "-0.08")))   # ほぼ前を見て走る
		p.set_third(args.get("view", "fp") == "tp")
		if not still:
			_press(KEY_SHIFT, true)
			_press(KEY_W, true)
	if f == n_at:
		_press(KEY_N, true)
	if f == n_at + 1:
		_press(KEY_N, false)
		_press(KEY_SHIFT, false)
	if f >= n_at - 6 and f <= n_at + 60 and (f - n_at) % 2 == 0:
		root.get_texture().get_image().save_png("%s/%03d.png" % [_dir(), n])
		var v: float = p.sled.linear_velocity.length() if p.mode == p.Mode.RIDE else Vector2(p.velocity.x, p.velocity.z).length()
		lines.append("%03d  N%+.2fs  見下ろし %.3f  速さ %.1f  k=%d" % [n, (f - n_at) / 30.0, p.get("_pitch"), v, p.doll.sack_k("out")])
		n += 1
		if args.has("probe") and p.mode == p.Mode.RIDE and f == n_at + 30:
			var c: Camera3D = p.cam
			print("目（席から）", (p.sled.to_local(c.global_position) - p.seat).snapped(Vector3.ONE * 0.01), " 視野角 ", c.fov)
			for nm in ["手", "膝", "足先", "袋の前の縁"]:
				var at: Vector3 = {"手": Vector3(0.2, 0.1, -0.5), "膝": Vector3(0.1, 0.15, -0.25), "足先": Vector3(0.1, -0.08, -0.47), "袋の前の縁": Vector3(0, 0.05, -0.75)}[nm]
				var q := c.to_local(p.sled.to_global(p.seat + at))
				print(nm, " 下へ %.1f°" % rad_to_deg(atan2(-q.y, -q.z)))
	if f > n_at + 62:
		_press(KEY_W, false)
		var fa := FileAccess.open(_dir().path_join("log.txt"), FileAccess.WRITE)
		fa.store_string("\n".join(lines) + "\n")
		print("\n".join(lines))
		quit()
	return false
