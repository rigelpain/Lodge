extends SceneTree
## ロッジの席に座る・立つ動き（12 コマ／秒）を、斜め前から 1 コマずつ撮って 1 枚に並べる（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/seat_anim_shots.gd -- --seat=chair|stool|bench|zabuton [--n=番目] [--out=DIR]
## はじめに、席の立つ所で席を向いたときの一人称（席の上に F と座る絵の案内が出るか）を撮る。
## 座るのは F と同じ sit_down()、立つのは移動キーと同じ stand_up()。立ったあと歩ける（当たりが戻る）かを書き出す

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _step := 0
var _seat := -1
var _out := ""
var _at := 0.0
var _frames: Array[Image] = []
var _last_f := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = args.get("out", "/tmp")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	root.add_child(cam)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var seats = main.seats
	if p == null or seats == null or seats.seats.is_empty() or t < 1.0:
		return false
	if main.settings:
		main.settings.set_open(false)
	var kind: String = args.get("seat", "chair")
	match _step:
		0:
			var list := []
			for i in seats.seats.size():
				if seats.seats[i].kind == kind and not seats.taken.has(i):
					list.append(i)
			_seat = list[clampi(int(args.get("n", "4")), 0, list.size() - 1)]
			var st: Dictionary = seats.seat(_seat)
			# 席の後ろ 1.2 m から、席を向いて立つ（ここで案内が出る）
			var from: Vector3 = st.stand - st.face * 0.6
			p.global_position = from + Vector3.UP * 0.1
			p.rotation.y = atan2(-(st.pos - from).x, -(st.pos - from).z)
			p._pitch = -0.35
			_step = 1
			_at = t + 1.0
		1:
			if t >= _at:
				_save(root.get_texture().get_image(), "hint")
				print("案内の席: ", p.seat_near(), "（ねらいの席 ", _seat, "）")
				print("座れた: ", p.sit_down())
				var st: Dictionary = seats.seat(_seat)
				var side: Vector3 = st.face.cross(Vector3.UP)
				var c: Vector3 = st.pos + Vector3.UP * 0.2 - st.face * 0.2
				cam.look_at_from_position(c + side * 2.6 + st.face * 1.6 + Vector3.UP * 1.1, c)
				cam.current = true
				main.hud.visible = false
				_frames.clear()
				_last_f = Doll.frame_index()
				_step = 2
		2:
			if Doll.frame_index() != _last_f:
				_last_f = Doll.frame_index()
				_frames.append(root.get_texture().get_image())
				if _frames.size() >= 8:
					_sheet("sit")
					print("座ったあと: mode=%d 席=%d 当たり=%s" % [p.mode, p.seat_i, "切" if p._col.disabled else "入"])
					p.stand_up()
					_frames.clear()
					_step = 3
		3:
			if Doll.frame_index() != _last_f:
				_last_f = Doll.frame_index()
				_frames.append(root.get_texture().get_image())
				if _frames.size() >= 4:
					_sheet("stand")
					var st: Dictionary = seats.seat(_seat)
					print("立ったあと: mode=%d 席=%d 当たり=%s 立つ所から %.2f m 席の空き=%s" % [p.mode, p.seat_i,
						"切" if p._col.disabled else "入", Vector2(p.global_position.x - st.stand.x, p.global_position.z - st.stand.z).length(),
						not seats.taken.has(_seat)])
					return true
	return false


## 撮ったコマを 4 つずつ並べて 1 枚に（半分の大きさで）
func _sheet(name: String) -> void:
	var w := _frames[0].get_width() / 2
	var h := _frames[0].get_height() / 2
	var cols := mini(4, _frames.size())
	var rows := ceili(_frames.size() / 4.0)
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		var im := _frames[i]
		im.convert(Image.FORMAT_RGBA8)
		im.resize(w, h)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, (i / 4) * h))
	_save(sheet, name)


func _save(img: Image, name: String) -> void:
	var path := "%s/seat_anim_%s_%s.png" % [_out, args.get("seat", "chair"), name]
	img.save_png(path)
	print("撮った: ", path)
