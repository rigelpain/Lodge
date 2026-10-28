extends SceneTree
## ソリに乗ったときの、あなたの目線と、連れの子狐の座り方を撮る（確かめ用）。ソリは止めておく。
##   Godot --path game --resolution 960x540 -s res://tools/ride_eye_shots.gd -- --out=/path/to.png [--view=fp|side|front] [--seat=0〜2] [--tilt=度] [--pitch=rad]
## あなたは --seat 番目の席に乗る（前の席はほかの人で埋める）。仲間は --bots（main.gd の引数）。
## --tilt: ソリを左右に傾ける（子狐がソリと一緒に傾くかを見る）

const Companions := preload("res://companions.gd")

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _done := false
var _kit_err := 0.0
var _speed := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 40
	cam.cull_mask = (1 << 0) | (1 << 1)   # 世界と体（一人称の手は映さない）
	root.add_child(cam)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var sled: RigidBody3D = main.sled
	if p == null or sled == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if not _done and t > 0.5:
		_done = true
		if p.get_parent().find_children("*", "", false, false).filter(func(c): return c.get_script() == Companions).is_empty():
			var pets := Companions.new()
			pets.host = p
			main.add_child(pets)
		sled.freeze = not args.has("slide")
		var sp := sled.global_position
		sp.y = main.height(sp.x, sp.z) + 0.02
		var b := Basis(Vector3.UP, sled.global_basis.get_euler().y) * Basis(Vector3.BACK, deg_to_rad(float(args.get("tilt", "0"))))
		sled.global_transform = Transform3D(b, sp)
		var bots := main.get_children().filter(func(c): return c != p and c.get("doll") != null and c.has_method("get_off"))
		var seat := int(args.get("seat", "0"))
		var k := 0
		for i in 3:
			if i == seat:
				p.global_position = sled.global_position + sled.global_basis.z * 1.5 + Vector3.UP * 0.3
				p.get_on()
			elif k < bots.size():
				var bt = bots[k]
				k += 1
				bt.seat = sled.mount(bt)
				bt._col.disabled = true
				bt.state = bt.State.RIDE
		p.set_third(false)
		p.rotation.y = sled.global_rotation.y
		p._pitch = float(args.get("pitch", "-0.12"))
	var c: Vector3 = sled.global_position + Vector3.UP * 0.6
	var x: Vector3 = sled.global_basis.x
	var z: Vector3 = sled.global_basis.z
	match args.get("view", "side"):
		"front":
			cam.look_at_from_position(c - z * 4.0 + x * 1.0 + Vector3.UP * 0.8, c)
		"fp":
			pass
		_:
			cam.look_at_from_position(c + x * float(args.get("dist", "3.4")) + Vector3.UP * 0.4, c)
	if args.get("view", "side") == "fp":
		p.cam.current = true
	else:
		cam.current = true
	if args.has("slide") and _done and t > 1.0:
		for pet in main.get_children():
			if pet.get_script() == Companions and pet._kit:
				var want: Vector3 = sled.to_global(sled.to_local(p.doll.global_position) + Companions.LAP)
				_kit_err = maxf(_kit_err, pet._kit.global_position.distance_to(want))
		_speed = maxf(_speed, sled.linear_velocity.length())
	if t > float(args.get("at", "2.0")):
		if args.has("slide"):
			print("滑る: 最高の速さ=%.1f m/s 子狐のずれの最大=%.3f m" % [_speed, _kit_err])
		root.get_texture().get_image().save_png(args.get("out", "/tmp/ride.png"))
		print("保存: %s 乗る人=%d 目の高さ（席から）=%.2f m" % [args.get("out", ""), sled.riders.size(), p.cam.global_position.y - p.global_position.y])
		quit()
	return false
