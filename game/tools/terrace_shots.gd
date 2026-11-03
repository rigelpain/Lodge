extends SceneTree
## ロッジ 2 階の西の端（外からの戸がつながる板の床）とテラスを、上から・外から・中から・テラスに立った目線で撮る（確かめ用）。
##   Godot --path game --resolution 1600x1000 -s res://tools/terrace_shots.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --dir=/path/shots
##   --sit を付けると、テラスの椅子（lodge/dims.py の TERRACE_TABLES）に 7 体の人形を座らせて sit_terrace も撮る。
##   --marks を付けると、床に範囲の色と名前の札を置いて撮る（代表に場所を指して聞く絵）。--only=名前,名前 で一部だけ
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ。Godot ではロッジの (x, 高さ, -y)）。<dir>/<名前>.png に書く

const FL2 := 6.10

## [名前, 目の所 (x, y, 高さ), 見る所 (x, y, 高さ), 真上から撮るときの幅（0 なら遠近）]
const VIEWS := [
	["top_all", Vector3(0.0, -1.5, 9.5), Vector3(0.0, -1.5, 0.0), 50.0],               # 上: 2 階とテラスぜんぶ（屋根の下で切る）
	["top_west", Vector3(-13.5, 0.0, 9.5), Vector3(-13.5, 0.0, 0.0), 30.0],            # 上: 西の端とテラス
	["out_sw", Vector3(-44.0, -30.0, 19.0), Vector3(-13.0, 1.0, 7.0), 0.0],            # 外: 南西の上から
	["out_nw", Vector3(-42.0, 32.0, 17.0), Vector3(-13.0, 2.0, 7.0), 0.0],             # 外: 北西の上から
	["in_west", Vector3(-4.0, 1.0, FL2 + 0.40 + 1.55), Vector3(-21.0, 1.5, FL2 + 1.0), 0.0],   # 中: 畳から西の端を見る
	["in_corner", Vector3(-11.0, 10.0, FL2 + 1.55), Vector3(-18.5, -4.5, FL2 + 0.9), 0.0],     # 中: 北の板の床から南西の戸と長椅子
	["terrace_eye", Vector3(-17.0, -10.5, FL2 + 1.55), Vector3(-13.0, -4.0, FL2 + 1.6), 0.0], # テラス: 南のテラスから戸と西の端
	["terrace_west", Vector3(-12.6, -4.6, FL2 + 1.55), Vector3(-17.5, 6.0, FL2 + 0.6), 0.0],  # テラス: 西の端の卓と椅子
	["terrace_door", Vector3(-19.5, 1.0, FL2 + 1.55), Vector3(-11.8, 3.3, FL2 + 1.4), 0.0],   # テラス: 卓の西から戸
	["sit_terrace", Vector3(-14.4, 0.6, FL2 + 1.75), Vector3(-16.6, 3.0, FL2 + 0.7), 0.0],    # 座った人形（--sit）
]
const Doll := preload("res://doll.gd")

## 範囲の色: [x0, y0, x1, y1, 色]（--marks のとき）
const AREAS := [
	[-21.62, -5.27, -10.0, 12.55, Color(1.0, 0.45, 0.1, 0.30)],   # A: 外からの戸がつながる板の床（西の端）
	[-21.8, -12.7, 21.8, -5.63, Color(0.2, 0.55, 1.0, 0.22)],     # 今のテラス
]
## 線: [x0, y0, x1, y1, 色]
const LINES := [
	[-11.8, -5.6, -11.8, 12.7, Color(0.85, 0.0, 0.0)],   # B: 新しい外の壁の案
]
## 札: [字, (x, y, 高さ)]
const TAGS := [
	["A 板の床（西の端）", Vector3(-16.0, 4.0, FL2 + 2.2)],
	["今のテラス", Vector3(-2.0, -9.2, FL2 + 1.6)],
	["テラスへの戸", Vector3(-12.71, -6.4, FL2 + 2.9)],
	["長椅子と卓", Vector3(-19.0, -3.2, FL2 + 1.3)],
	["畳（こたつ 8 卓）", Vector3(4.0, 3.5, FL2 + 1.6)],
	["衣装掛け・染め桶・紙細工屋さん", Vector3(19.0, 0.5, FL2 + 2.6)],
	["内階段", Vector3(19.5, 9.8, FL2 + 1.6)],
	["B 新しい外の壁の案", Vector3(-11.8, 7.0, FL2 + 3.4)],
]

var args := {}
var main: Node3D
var lodge: Node3D
var _floor_marks: Array[Node3D] = []   # 範囲の色と線（真上から撮るときだけ見せる）


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/terrace_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _g(q: Vector3) -> Vector3:
	return lodge.to_global(Vector3(q.x, q.z, -q.y))


func _marks() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans", "Hiragino Kaku Gothic ProN"])
	for a in AREAS:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(a[2] - a[0], 0.04, a[3] - a[1])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = a[4]
		b.material = mat
		m.mesh = b
		lodge.add_child(m)
		_floor_marks.append(m)
		m.position = Vector3((a[0] + a[2]) / 2.0, FL2 + 0.45, -(a[1] + a[3]) / 2.0)
	for l in LINES:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(maxf(absf(l[2] - l[0]), 0.18), 3.0, maxf(absf(l[3] - l[1]), 0.18))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(l[4], 0.8)
		b.material = mat
		m.mesh = b
		lodge.add_child(m)
		_floor_marks.append(m)
		m.position = Vector3((l[0] + l[2]) / 2.0, FL2 + 1.5, -(l[1] + l[3]) / 2.0)
	for t in TAGS:
		var lb := Label3D.new()
		lb.text = t[0]
		lb.font = font
		lb.font_size = 30
		lb.pixel_size = 0.0018
		lb.outline_size = 14
		lb.modulate = Color(1, 1, 1)
		lb.outline_modulate = Color(0.05, 0.05, 0.05)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.fixed_size = true
		lodge.add_child(lb)
		lb.position = Vector3(t[1].x, t[1].z, -t[1].y)


## テラスの椅子に 7 体を座らせる（tools/sit_side_shots.gd と同じ座らせ方）
func _sit() -> void:
	var seats = main.get("seats")
	var list := []
	for i in seats.seats.size():
		var l := lodge.to_local(seats.seats[i].pos)
		if seats.seats[i].kind == "chair" and l.y > 5.9:
			list.append(i)
	print("テラスの椅子: ", list.size())
	for c in main.get_children():   # ゲームの人（あなた・仲間）は隠す
		if c.get("doll") != null:
			c.visible = false
	var order := [6, 7, 4, 5, 8, 9, 10]   # 真ん中の卓（4 脚）から
	for k in Doll.KINDS.size():
		if k >= order.size() or order[k] >= list.size():
			break
		var st: Dictionary = seats.seat(list[order[k]])
		var host := Node3D.new()
		root.add_child(host)
		var d := Doll.new()
		d.kind = Doll.KINDS[k]
		host.add_child(d)
		d.act = Doll.Act.SIT
		d.sit_stage = 2
		host.global_position = st.pos
		d.facing = st.face
		d.set("_yaw", atan2(-st.face.x, -st.face.z))
		d.seat_drop = st.pos.y - st.floor
		if "seat_edge" in d:
			d.seat_edge = st.get("edge", 0.2)


func _run() -> void:
	await create_timer(3.5).timeout
	lodge = main.get_node("Lodge")
	if args.has("sit"):
		_sit()
	if args.has("marks"):
		_marks()
	for c in main.find_children("*", "CanvasLayer", true, false):   # 画面の飾り（HUD）は写さない
		(c as CanvasLayer).visible = false
	var only: PackedStringArray = args.get("only", "").split(",", false)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.far = 400.0
	for v in VIEWS:
		if not only.is_empty() and not only.has(v[0]):
			continue
		if v[0] == "sit_terrace" and not args.has("sit"):
			continue
		for m in _floor_marks:
			m.visible = v[3] > 0.0
		var eye := _g(v[1])
		var at := _g(v[2])
		cam.global_position = eye
		if v[3] > 0.0:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = v[3]
			cam.near = 0.05
			cam.look_at(at, lodge.global_basis * Vector3(0, 0, -1))   # 上が北
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 70.0
			cam.near = 0.05
			cam.look_at(at)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
		print("撮った: ", v[0])
	quit()
