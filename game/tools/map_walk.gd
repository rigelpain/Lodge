extends SceneTree
## あなたをマップのある場所に立たせ、見る先を向いて（W で歩いてから）一人称の画面を撮る。配置の確かめ用。
##   Godot --path game --resolution 1280x720 -s res://tools/map_walk.gd -- --out=/path/to.png
##     --stand=x,z,tx,tz[,pitch]  立つ所 (x, z) と見る先 (tx, tz)、上下の向き（ラジアン。既定 -0.05）
##                                --spawn=lodge と一緒なら x, z は使わず、ロッジの前に立つ
##     [--walk=秒]                 撮る前に、見る先へ W で歩く
##     [--no-pip --no-snow など]   main.gd の引数はそのまま効く

var args := {}
var main: Node3D
var t := 0.0
var _placed := false
var _walk_end := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if not _placed and t > 0.5:
		_placed = true
		var v: PackedFloat64Array = args["stand"].split_floats(",")
		var pos: Vector3 = p.global_position
		if not args.has("spawn"):
			pos = Vector3(v[0], main.height(v[0], v[1]) + 0.2, v[1])
			p.global_position = pos
		var d := Vector2(v[2] - pos.x, v[3] - pos.z)
		p.rotation.y = atan2(-d.x, -d.y)
		p._pitch = v[4] if v.size() > 4 else -0.05
		_walk_end = -1.0
		if args.has("walk"):
			_walk_end = t + float(args["walk"])
			_key(true)
	if _placed and args.has("walk") and t > _walk_end and _walk_end > 0.0:
		_walk_end = -1.0
		_key(false)
	if _placed and _walk_end <= 0.0 and t > maxf(2.0, float(args.get("walk", "0")) + 1.5):
		root.get_texture().get_image().save_png(args["out"])
		var q: Vector3 = p.global_position
		print("保存: %s　立っている所 (%.1f, %.1f, %.1f)　%d fps" % [args["out"], q.x, q.y, q.z, Engine.get_frames_per_second()])
		return true
	return false


func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.pressed = down
	Input.parse_input_event(ev)
