extends SceneTree
## 米袋を出して乗る → 滑って漕ぐ → しまう、を録る（動きの確かめ用）。
##   Godot --path game --resolution 960x540 --fixed-fps 30 -s res://tools/sack_record.gd -- --dir=/path/frames [--view=fp|third|side] [--no-sound]
## あなたを坂の途中に下りの向きで立たせ、0.6 秒で N（toggle_sack）、1.4〜2.2 秒で Space を 3 回（漕ぐ）、3.0 秒でもう一度 N。
## コマは 30 枚／秒で dir に連番の PNG（fp は一人称と右上の小窓、third は三人称、side は横から追うカメラ）

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var n := 0
var _step := 0
var _kicks := [1.4, 1.8, 2.2]   # --early-kick: 乗り込みの途中（0.75 秒）でも蹴る


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)
	root.add_child(cam)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/sack"))


func _process(dt: float) -> bool:
	var p = main.player
	if p == null:
		return false
	t += dt
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	var view: String = args.get("view", "fp")
	if _step == 0 and t > 0.3:
		_step = 1
		var at := Vector3(0, 0, float(args.get("z", "16")))
		at.y = main.height(at.x, at.z) + 0.1
		p.global_position = at
		p.rotation.y = atan2(-at.x, -at.z)   # 頂上に背を向ける（下りの向き）
		p._pitch = float(args.get("pitch", "-0.15"))
		p.set_third(view == "third")
	if _step == 1 and t > 0.6:
		_step = 2
		if args.has("early-kick"):
			_kicks.push_front(0.75)
		p.toggle_sack()
		print("N: mode=%d" % p.mode)
	if _step >= 2 and not _kicks.is_empty() and t > _kicks[0]:
		_kicks.pop_front()
		if p.mode == p.Mode.RIDE and p.sled.kick(p):
			p._kicked()
	if _step == 2 and t > 3.0:
		_step = 3
		p.toggle_sack()
		print("N: mode=%d" % p.mode)
	if args.has("debug") and int(t * 30) % 3 == 0:
		var df: Vector3 = -p.doll.global_basis.z
		print("t=%.2f 人形の前=%s ソリ=%s 速さ=%.1f mode=%d k=%d 見下ろし=%.2f 目の高さ=%.2f 脚=%s" % [t, str(df.snapped(Vector3.ONE * 0.01)), str((-p.sled.global_basis.z).snapped(Vector3.ONE * 0.01)), p.sled.linear_velocity.length(), p.mode, p.doll.sack_k("out"), p._pitch, p.cam.position.y, str(p._fp_legs.visible)])
	if view == "side":
		var c: Vector3 = p.global_position + Vector3.UP * 0.5
		var fwd: Vector3 = -p.doll.global_basis.z   # 人形の向き（乗っているあいだは米袋の向き）
		fwd.y = 0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP).normalized() * (-1.0 if args.has("left") else 1.0)
		var want := c + side * float(args.get("dist", "2.4")) + fwd * 0.4 + Vector3.UP * 0.25
		cam.global_position = want if t < 0.62 else cam.global_position.lerp(want, minf(1.0, dt * 6.0))
		cam.look_at(c, Vector3.UP)
		cam.current = true
	if t > 0.45:   # --fixed-fps 30 で動かすと、1 コマが 1/30 秒になる
		root.get_texture().get_image().save_png("%s/%05d.png" % [args.get("dir", "/tmp/sack"), n])
		n += 1
	if t > float(args.get("secs", "4.2")):
		print("frames: ", n)
		quit()
	return false
