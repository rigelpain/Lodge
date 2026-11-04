extends SceneTree
## 標高の札（hud.gd・areas.gd・elev_card.gd）の確かめ。範囲ごとに正しい札と現在地が出るか、境目でちらちら替わらないか、山の旗が見えるか。
##   Godot --path game --resolution 1600x900 --fixed-fps 30 -s res://tools/elev_tag_check.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
##   スマホの縦画面は --resolution 390x844 で同じものを撮る。--cards-only で札だけ
## 撮る絵: 場所ごとの画面（左下に札）、flag_*（旗を見る）

const Areas := preload("res://areas.gd")

## 札の確かめの場所: [名前, x, z, 正しい札]
const SPOTS := [
	["hill_top", 0.0, 1.5, "hill"], ["hill_mid", 0.0, 28.0, "hill"], ["hill_foot", 0.0, 60.0, "hill"], ["hill_east", 55.0, -10.0, "hill"],
	["lodge_front", -20.0, 74.0, "lodge"], ["lodge_south", -35.0, 150.0, "lodge"],
	["slope_foot", -5.0, 200.0, "slope"], ["slope_mid", -12.0, 372.0, "slope"], ["slope_side", 80.0, 372.0, "slope"], ["slope_top", -6.0, 482.0, "slope"],
	["peak_foot", 170.0, 32.0, "peak"], ["peak_bench", 505.0, 32.0, "peak"], ["peak_side", 505.0, 180.0, "peak"], ["peak_top", 700.0, 32.0, "peak"],
]

var args := {}
var main: Node3D
var p: CharacterBody3D
var bad := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()
	process_frame.connect(_keep_awake)


## 無操作で札が引っこまないように、確かめのあいだは無操作の時計を止める
func _keep_awake() -> void:
	if main and main.get("hud"):
		main.hud.set("_idle", 0.0)


func _dir() -> String:
	return args.get("dir", "/tmp/elev_tag")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))


func _put_sled(x: float, z: float) -> void:
	var sled: RigidBody3D = main.sled
	sled.freeze = false
	sled.reset_to(Vector3(x, main.height(x, z) + 0.4, z))
	sled.linear_velocity = Vector3.ZERO
	sled.freeze = true


func _run() -> void:
	await _wait(2.5)
	p = main.player
	p.set_third(false)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
		p.menu_open = false
	var hud: Node = main.hud
	# 1. 場所ごとに、正しい札か
	for s in SPOTS:
		_put_sled(s[1], s[2])
		p.global_position = Vector3(s[1] + 3.0, main.height(s[1] + 3.0, s[2]) + 0.2, s[2])
		await _wait(0.7)
		var got: String = hud.shown_area()
		var ok: bool = got == s[3]
		bad += 0 if ok else 1
		print("%s %s: 札=%s 正=%s 断面の上の位置=%.1f" % ["OK" if ok else "NG", s[0], got, s[3], Areas.locate(got, Vector2(s[1], s[2]))])
		await _shot(s[0])
	# 2. 境目のちらつき: 境目のまわりを ±4 m で行き来する（半径 68 m の入り、76 m の出のあいだ）。札が替わった回数を数える
	var edges := [["丘の入り", 0.0, 68.0, 80.0], ["丘の出", 0.0, 76.16, 60.0], ["大斜面の入り", -5.0, 180.0, 150.0], ["大斜面の出", -5.0, 142.56, 190.0]]   # [名前, x, 境目の z, 始める z]
	for e in edges:
		_put_sled(e[1], e[3])
		await _wait(0.8)
		var last: String = hud.shown_area()
		var changes := 0
		for k in 90:   # 30 コマ／秒で 3 秒。1 秒に 3 往復
			_put_sled(e[1], e[2] + sin(k * 0.6) * 1.5)
			await process_frame
			var now: String = hud.shown_area()
			if now != last:
				changes += 1
				last = now
		print("%s: 札が替わった回数 %d（1 回以下なら OK）" % [e[0], changes])
		bad += 0 if changes <= 1 else 1
	if not args.has("cards-only"):
		# 3. 旗を見る
		main.sled.freeze = false
		var door: Vector2 = main.lodge_to_world(Vector2(main.PATH_X, 19.0))
		var board: Vector2 = main.lodge_to_world(preload("res://area_flags.gd").BOARD_AT)
		var mid: Vector2 = main.lodge_to_world(Vector2(main.PATH_X - 6.0, 24.0))
		var views := [["map_from_door", Vector3(door.x, 0, door.y), Vector3(board.x, 3.0, board.y)], ["map_close", Vector3(mid.x, 0, mid.y), Vector3(board.x, 3.0, board.y)],
			["flag_hill_from_lodge", Vector3(-30, 0, 76), Vector3(-30, 3, 48)], ["flag_hill_top", Vector3(12, 0, 14), Vector3(4, 3, -4)],
			["flag_slope_from_foot", Vector3(-15, 0, 190), Vector3(-15, 4, 226)], ["flag_slope_top", Vector3(10, 0, 460), Vector3(2, 70, 487)],
			["flag_peak_from_foot", Vector3(120, 0, 32), Vector3(156, 4, 32)], ["flag_peak_top", Vector3(660, 0, 50), Vector3(704, 0, 42)]]
		for v in views:
			var at: Vector3 = v[1]
			p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.2, at.z)
			var look: Vector3 = v[2]
			if v[0].ends_with("top"):
				look.y = main.height(look.x, look.z) + 3.0
			var d := look - p.global_position
			p.rotation.y = atan2(-d.x, -d.z)
			p.set("_pitch", 0.05)
			await _wait(0.5)
			await _shot(v[0])
	print("確かめ: NG %d 件" % bad)
	quit()
