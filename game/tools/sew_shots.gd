extends SceneTree
## ロッジの中の大きなミシン（sewing_machine.gd）の 7 つの場面を撮る（動きの確かめ用）。
##   Godot --path game --resolution 1280x720 --fixed-fps 30 -s res://tools/sew_shots.gd -- \
##       --bots=0 --no-snow --dir=/path/shots [--tag=smooth] [--sew-stepped] [--sew-helper] [--movie] [--view=front|close|spools]
## あなたはミシンから離れて立ち（待つ）→ 立つ所へ来て（呼ぶ）→ T と同じく use() で縫い始める。
## 場面ごとに決めた時刻で <dir>/<tag>_<番号>_<場面>_<秒>.png を書く。--movie なら全部のコマも <dir>/<tag>_movie/ に書く
## （--fixed-fps 30 で 1 コマ 1/30 秒に固定するので、なめらか版とコマ撮り版を同じ時間で比べられる）。
## 終わりに、ためにかかった秒と、足踏み・そばにいた人の数を出す。
## 撮るカメラはあなたの目ではなく、斜め前の見張りのカメラ（あなたの人形も写る）。

var args := {}
var main: Node3D
var sew: Node3D
var cam: Camera3D
var t := 0.0
var n := 0
var _phase_at := {}          # 場面の名前 → 始まった時刻
var _shots := []             # [時刻, 名前]
var _done_at := -1.0
var _used := false
var _charge_from := -1.0

# 場面の始まりから何秒後に撮るか
const AT := {
	"wait": [0.0, 0.3, 0.6, 0.9],
	"call": [0.05, 0.15, 0.3, 0.45, 0.6],
	"feed": [0.1, 0.3, 0.45, 0.62, 0.8],
	"charge": [0.1, 0.6, 1.2, 1.8, 2.4],
	"release": [0.0, 0.07, 0.14, 0.24],
	"show": [0.1, 0.35, 0.6, 0.75, 0.95, 1.3],
	"after": [0.3, 0.7, 1.1, 1.5, 2.2],
}
const ORDER := ["wait", "call", "feed", "charge", "release", "show", "after"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.get("dir", "/tmp/sew"))
	if args.has("movie"):
		DirAccess.make_dir_recursive_absolute(_dir().path_join(_tag() + "_movie"))


func _dir() -> String:
	return args.get("dir", "/tmp/sew")


func _tag() -> String:
	return args.get("tag", "stepped" if args.has("sew-stepped") else "smooth")


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	if p == null or main.sewing == null:
		return t > 5.0
	sew = main.sewing
	if main.hud:
		main.hud.visible = false
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	if main._pip_layer:
		main.pip_hidden = true
		main._pip_layer.visible = false
	var m: Node3D = sew.machine
	if cam == null and t > 0.3:
		cam = Camera3D.new()
		cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 4)   # 三人称と同じ（あなたの人形も写す）
		m.add_child(cam)
		# 前の少し上から全体（front）、針のまわりを近く（close）、糸巻き（spools）。ミシンの座標（前は -Z、針は x = -1.2）
		var view: String = args.get("view", "front")
		var eye := Vector3(0.4, 3.0, -3.7)
		var look := Vector3(-0.4, 1.95, 0.0)
		if view == "close":
			eye = Vector3(-2.15, 2.3, -1.75)
			look = Vector3(-1.05, 1.75, -0.35)
		elif view == "spools":
			eye = Vector3(0.3, 3.9, -1.7)
			look = Vector3(0.0, 3.2, 0.1)
		if args.has("eye"):   # 好きな所から: --eye=x,y,z --look=x,y,z（ミシンの座標）
			var e: PackedFloat64Array = args["eye"].split_floats(",")
			var l: PackedFloat64Array = args.get("look", "-0.4,1.6,0").split_floats(",")
			eye = Vector3(e[0], e[1], e[2])
			look = Vector3(l[0], l[1], l[2])
		cam.look_at_from_position(m.to_global(eye), m.to_global(look), Vector3.UP if absf(eye.x - look.x) + absf(eye.z - look.z) > 0.01 else Vector3.FORWARD)
		cam.fov = 55 if view == "front" else 42
		cam.current = true
		sew.phase_changed.connect(_on_phase)
		# 待つ: ミシンから離れて立つ
		_put_player(p, m, Vector3(1.4, 0.0, -5.2))
	if cam == null:
		return false
	if t > 1.2 and not _phase_at.has("wait"):
		_on_phase("wait")
	# 待つで糸巻きの半回転を 1 度起こしてから、立つ所へ歩み寄る（瞬間移動）
	if _phase_at.has("wait") and t > _phase_at["wait"] - 0.05 and sew._turn.is_empty() and t < _phase_at["wait"] + 0.1:
		sew._next_turn = 0.0
	if t > 5.0 and not _phase_at.has("call") and sew.phase_name() == "wait":
		_put_player(p, m, Vector3(0.0, 0.0, -1.65))
	if _phase_at.has("call") and not _used and t > _phase_at["call"] + 1.2:
		_used = true
		sew.use()
	# 撮る
	for s in _shots.duplicate():
		if t + 0.0001 >= s[0]:
			_shots.erase(s)
			_save(s[1])
	if args.has("movie"):
		root.get_texture().get_image().save_png(_dir().path_join(_tag() + "_movie/%05d.png" % n))
	n += 1
	if _phase_at.has("after") and _done_at < 0.0:
		_done_at = _phase_at["after"] + 2.6
	if _done_at > 0.0 and t > _done_at:
		print("ため %.2f 秒（足踏み %d 人、そば %d 人）　%s" % [sew.last_charge, sew._helpers.x, sew._helpers.y, _tag()])
		return true
	return t > 40.0


func _on_phase(name: String) -> void:
	if _phase_at.has(name):
		return
	_phase_at[name] = t
	print("%.2f 秒　%s" % [t, name])
	for k in AT[name].size():
		_shots.append([t + AT[name][k], "%d_%s_%d" % [ORDER.find(name) + 1, name, k]])


func _save(name: String) -> void:
	var path := _dir().path_join("%s_%s.png" % [_tag(), name])
	root.get_texture().get_image().save_png(path)


func _put_player(p: CharacterBody3D, m: Node3D, local: Vector3) -> void:
	var g := m.to_global(local)
	g.y = m.global_position.y + 0.05
	p.global_position = g
	p.velocity = Vector3.ZERO
	var w := m.to_global(Vector3(0, 0, 0))
	var d := Vector2(w.x - g.x, w.z - g.z)
	p.rotation.y = atan2(-d.x, -d.y)
