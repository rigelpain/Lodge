extends SceneTree
## 黒く染めたランタン（lantern.gd の is_black。まわりの光を引く灯り）を、ふつうのランタンと並べて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/lantern_black_shots.gd -- --bots=0 --lodge-bots=0 --roam-bots=0 --no-sound --no-pip --no-save --tag-file=user://lantern_black_none.cfg --dir=/path/shots
##   --energies=1.6  引く灯りの濃さ（lantern.gd の BLACK_ENERGY。並べると案ごとに撮る。既定は lantern.gd のまま）
## 左に和紙の提灯（もとの色）、右に同じ提灯を黒に染めた人形を立て、どちらも点ける。
##   night_<濃さ>  夜の雪の上
##   fire_<濃さ>   夜、焚き火のそば（黒い方が焚き火に寄る）
##   lodge_<濃さ>  夜、ロッジの中（紙細工屋さんのテントの前。暖炉やつり灯りの光の中）
##   day_<濃さ>    昼の雪の上
##   inside_<濃さ> 夜、黒い方の暗がりの球の中から（カメラが球の中にいるとき）
##   shop_999 / shop_1000  紙細工屋さんの色替えの段。黒の札は 1 螺鈿（ボタンが 999 なら灰色で選べない、1000 なら選べる）

const Doll := preload("res://doll.gd")
const Lantern := preload("res://lantern.gd")
const Craft := preload("res://craft.gd")

var args := {}
var main: Node3D
var dc: Node
var cam: Camera3D
var hosts: Array[Node3D] = []
var black: String = Craft.lantern_palette()[10]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # 昼夜の時計（daycycle.gd）が、今の場面から太陽を探す
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return String(args.get("dir", "/tmp/lantern-black"))


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String, ui := false) -> void:
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	for n in main.get_children():   # 札や小窓は隠す（灯りだけを見る）。ui なら店の画面だけ見せる
		if n is CanvasLayer:
			n.visible = ui and n == main.paper_shop_ui
	cam.make_current()
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("撮った ", name)


func _hour(h: float) -> void:
	dc.hour = h
	dc.day_seconds = 1.0e9   # 撮るあいだは時刻を止める
	await _wait(1.2)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, main.height(x, z), z)


## 人形 2 つ（左: もとの色、右: 黒）を、mid を中心に横へ gap m 離して立て、カメラを前から向ける
func _pair(mid: Vector3, gap: float, yaw: float, outdoor: bool) -> void:
	var side := Basis(Vector3.UP, yaw).x
	var front := -Basis(Vector3.UP, yaw).z
	for i in 2:
		var at := mid + side * (gap * (i - 0.5))
		if outdoor:
			at = _ground(at.x, at.z)
		hosts[i].global_position = at
		var d: Node3D = hosts[i].get_child(0)
		d.facing = front   # カメラの方を向く
	var eye := mid + front * 6.5 + Vector3.UP * 2.2
	if outdoor:
		eye.y = main.height(eye.x, eye.z) + 2.2
	cam.look_at_from_position(eye, mid + Vector3.UP * 0.6)


func _run() -> void:
	await _wait(2.5)
	dc = root.get_node("DayCycle")
	main.player.global_position += Vector3(40, 0, 40)   # 遊ぶ人は離しておく（その人のランタンが混ざらないように）
	main.player.global_position.y = main.height(main.player.global_position.x, main.player.global_position.z) + 0.2
	cam = Camera3D.new()
	cam.fov = 55.0
	main.add_child(cam)
	for i in 2:
		var h := Node3D.new()
		main.add_child(h)
		var d: Node3D = Doll.new()
		d.kind = "kasa"
		h.add_child(d)
		d.gaze = Vector3.INF
		d.lantern = "paper"
		d.lantern_lit = true
		d.lantern_color = "" if i == 0 else black
		hosts.append(h)
	var es: Array = []
	for s in String(args.get("energies", str(Lantern.BLACK_ENERGY))).split(","):
		es.append(float(s))
	var s0: Vector3 = main.sled.global_position + Vector3(6.0, 0.0, 6.0)
	# 夜の雪の上
	await _hour(21.0)
	_pair(s0, 4.0, 0.6, true)
	for e in es:
		Lantern.BLACK_ENERGY = e
		await _wait(0.6)
		await _shot("night_%s" % str(e))
	# 焚き火のそば（黒い方の 1.6 m 右）
	var fire_at: Vector3 = hosts[1].global_position + Basis(Vector3.UP, 0.6).x * 1.6
	fire_at = _ground(fire_at.x, fire_at.z)
	main.craft._light_fire(990, -1, fire_at, 0.0, Vector3.UP, 30.0)
	for e in es:
		Lantern.BLACK_ENERGY = e
		await _wait(0.8)
		await _shot("fire_%s" % str(e))
	# ロッジの中（紙細工屋さんのテントの前）
	var lady: Node3D = main.get("paper_lady")
	if lady:   # 紙細工屋さんの前（main.gd の --spawn=paper_shop と同じ所）に並べ、横から撮る
		var mid := lady.to_global(Vector3(0.6, 0.0, 3.4))
		var f := lady.global_basis.z   # テントの前（婦人の向き）から見る。人形はテントに沿って横に並ぶ
		f.y = 0
		_pair(mid, 2.4, atan2(-f.x, -f.z), false)
		cam.look_at_from_position(mid + f.normalized() * 4.5 + Vector3.UP * 1.8, mid + Vector3.UP * 0.6)
		for e in es:
			Lantern.BLACK_ENERGY = e
			await _wait(0.8)
			await _shot("lodge_%s" % str(e))
	# 夜、黒い方の暗がりの球の中から
	await _hour(21.0)
	_pair(s0, 4.0, 0.6, true)
	var bk: Vector3 = hosts[1].global_position
	var fw := Basis(Vector3.UP, 0.6).z
	cam.look_at_from_position(bk + fw * 1.6 + Vector3.UP * 1.5, bk + Vector3.UP * 0.6 - fw * 3.0)
	for e in es:
		Lantern.BLACK_ENERGY = e
		await _wait(0.6)
		await _shot("inside_%s" % str(e))
	# 昼の雪の上
	await _hour(12.0)
	_pair(s0, 4.0, 0.6, true)
	for e in es:
		Lantern.BLACK_ENERGY = e
		await _wait(0.6)
		await _shot("day_%s" % str(e))
	# 紙細工屋さんの色替えの段（黒の札の値段）
	var c: Node = main.craft
	var who: int = main.player.id
	await _hour(21.0)
	_pair(s0, 4.0, 0.6, true)
	c.send({"kind": "lamp", "who": who, "on": true})
	main.paper_shop_ui.open("lantern_dye")
	for w in [999, 1000]:
		c.wallets[who] = w
		await _wait(0.8)
		await _shot("shop_%d" % w, true)
	quit(0)
