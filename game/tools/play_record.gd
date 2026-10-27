extends SceneTree
## ゲームの場面をそのまま動かし、ソリを横から追うカメラで録画する（人形の動きの確かめ用）。
##   Godot --path game --resolution 960x540 -s res://tools/play_record.gd -- --sim=1 --bots=2 --dir=/path/frames [--secs=30] [--point=秒]
## あなたは --sim=1 でソリをつかんで押し、頂上の近くで乗る（W を押したままなので前に体重をかけて滑り出す）。
## 仲間はあなたが乗ると一緒に乗る。コマは 30 枚／秒で dir に連番の PNG で書く（ffmpeg で動画にする）。

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var n := 0
var rode := false
var _acc := 0.0
var _sun := Vector3.ZERO
var _said := 0.0
var _grabbed := false
var _pointing := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 50
	cam.cull_mask = (1 << 0) | (1 << 1)   # 世界と、あなたの体。一人称の手（層 3）は映さない
	root.add_child(cam)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/frames"))


func _process(dt: float) -> bool:
	t += dt
	var sled: Node3D = main.sled
	if sled == null:
		return false
	cam.current = true
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	# 太陽を背にして、ソリの横から追う（人形が逆光にならないように）。乗って滑るときは少し引く
	if _sun == Vector3.ZERO:
		for c in main.get_children():
			if c is DirectionalLight3D:
				_sun = -(c as DirectionalLight3D).global_basis.z
				_sun.y = 0
				_sun = _sun.normalized()
	var fwd: Vector3 = -sled.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var side: Vector3 = sled.global_basis.x
	side.y = 0
	side = side.normalized()
	if side.dot(_sun) > 0.0:
		side = -side
	var dist := 5.0 if not rode else 7.0
	var want: Vector3 = sled.global_position + side * dist + fwd * 1.0 + Vector3.UP * 1.6
	var look_at_pt: Vector3 = sled.global_position + Vector3.UP * 0.7 - fwd * 0.6
	if args.has("front"):
		# ソリの前の斜めから、押している人たちの顔と腕を見る
		want = sled.global_position + fwd * 3.6 + side * 2.2 + Vector3.UP * 1.7
		look_at_pt = sled.global_position - fwd * 1.6 + Vector3.UP * 1.0
	var p = main.player
	if args.has("solo") and p:
		# ソリから離れて立つあなたを、斜めうしろから（指さしと顔の向きを見る）
		var pf: Vector3 = -p.global_basis.z
		var pr: Vector3 = p.global_basis.x
		want = p.global_position - pf * 2.4 + pr * 1.6 + Vector3.UP * 1.9
		look_at_pt = p.global_position + pf * 1.5 + Vector3.UP * 0.9
	cam.global_position = want if t < 0.1 else cam.global_position.lerp(want, minf(1.0, dt * 4.0))
	cam.look_at(look_at_pt, Vector3.UP)

	if p and not _grabbed and t > 0.8 and not args.has("solo"):
		# あなたをソリのうしろに立たせて、つかませる（W は --sim=1 で押したまま）
		_grabbed = true
		var back: Vector3 = sled.global_basis.z
		p.global_position = sled.global_position + back * 2.0 + Vector3.UP * 0.3
		p.rotation.y = atan2(back.x, back.z)
		p.grab()
		print("つかむ: mode=%d 速さ=%.1f" % [p.mode, sled.linear_velocity.length()])
	# --point=秒: その秒から 3 秒、右クリックを押したままにする（指さし）
	if p and args.has("point"):
		var t0 := float(args["point"])
		var want_on := t > t0 and t < t0 + 3.0
		if want_on and not _pointing:
			p._pitch = float(args.get("pitch", "-0.25"))   # 前の雪を指す
		if want_on != _pointing:
			_pointing = want_on
			p.force_point = want_on
			if want_on and args.has("solo"):
				p.rotate_y(-0.6)   # 右の前を指す
			print("指さし: ", want_on)
	if _pointing and int(t * 4) % 4 == 0 and p.point_at != Vector3.INF:
		for b in main.get_children():
			if b.get("doll") != null and b != p:
				print("指す所=%s 仲間の目線=%s" % [str(p.point_at.snapped(Vector3.ONE * 0.1)), str(b.doll.gaze.snapped(Vector3.ONE * 0.1))])
	if p and not rode and t > 2.0:
		var top := Vector2(sled.global_position.x, sled.global_position.z).length()
		if top < 5.0 or sled.global_position.y > 16.6:
			p.let_go()
			p.get_on()
			rode = true
			print("乗る: t=%.1f mode=%d 高さ=%.1f" % [t, p.mode, sled.global_position.y])
	if t - _said > 0.5 and t < 3.0 or t - _said > 2.0:
		_said = t
		print("t=%.0f 高さ=%.1f 速さ=%.1f あなた=%s 乗る人=%d" % [t, sled.global_position.y, sled.linear_velocity.length(), str(p.mode) if p else "-", sled.riders.size()])
	# 30 枚／秒で書く
	_acc += dt
	if _acc >= 1.0 / 30.0 and t > 0.5:
		_acc = 0.0
		var img := root.get_texture().get_image()
		img.save_png("%s/%05d.png" % [args.get("dir", "/tmp/frames"), n])
		n += 1
	if t > float(args.get("secs", "30")):
		print("frames: ", n)
		quit()
	return false
