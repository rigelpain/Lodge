extends SceneTree
## 人形ごとの一人称の絵を撮る（目の高さの確かめ用）。ソリの 4 m うしろに立ち、まっすぐ前（ソリとその横の kasa の人形）を見る。
## 1 回の起動で人形を順に着替え（player.set_doll）、着替えてすぐの目の高さも出す。
##   Godot --path game --resolution 960x540 -s res://tools/eye_fp_shots.gd -- --dir=/path/to/dir [--kinds=kasa,golem]
## 絵は <dir>/fp_<人形>.png。標準出力に、着替えた直後と撮るときのカメラの高さ（足もとから）を出す

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var t := 0.0
var _kinds: Array = []
var _i := -1
var _next := 1.0
var _ref: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	args["bots"] = "0"
	args["lodge-bots"] = "0"
	args["roam-bots"] = "0"
	root.scaling_3d_scale = 1.0
	_kinds = Doll.KINDS if not args.has("kinds") else Array(String(args.kinds).split(","))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _place(p) -> void:
	var sled: Node3D = main.sled
	var back: Vector3 = sled.global_basis.z
	back.y = 0.0
	back = back.normalized()
	p.global_position = sled.global_position + back * 4.0 + Vector3.UP * 0.3
	p.rotation.y = atan2(back.x, back.z)
	p._pitch = 0.0
	p.velocity = Vector3.ZERO
	if p.third:
		p.set_third(false)
	if _ref == null:
		# 見比べの目安: ソリの右に kasa の人形を立てる（背丈 TOP × SCALE）
		_ref = Doll.new()
		_ref.kind = "kasa"
		main.add_child(_ref)
		var side: Vector3 = sled.global_basis.x
		side.y = 0.0
		var at: Vector3 = sled.global_position + side.normalized() * 1.4 + back * 1.0
		at.y = main.height(at.x, at.z)
		_ref.global_position = at
		_ref.facing = back
		_ref.gaze = Vector3.INF


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null or main.sled == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if t < _next:
		if _i >= 0:
			_place(p)
		return false
	if _i >= 0:
		var k: String = _kinds[_i]
		var out := "%s/fp_%s.png" % [args.get("dir", "/tmp"), k]
		root.get_texture().get_image().save_png(out)
		print("撮った %s: カメラ %.2f m（目 %.2f m・背丈 %.2f m）" % [k, p.cam.global_position.y - p.global_position.y, p.eye_height(), p.doll.height()])
	_i += 1
	if _i >= _kinds.size():
		quit()
		return false
	p.set_doll(_kinds[_i], true)
	print("着替えた %s: すぐのカメラ %.2f m" % [_kinds[_i], p.cam.position.y])
	_place(p)
	_next = t + 1.2
	return false
