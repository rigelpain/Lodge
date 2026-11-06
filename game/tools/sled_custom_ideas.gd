extends SceneTree
## ソリの色と滑りあとの縫い目を替える場と画面の案を、ゲームの本物の見た目で撮って 1 枚に並べる（案を代表に見せる用。字は入れない）。
##   Godot --path game --resolution 1920x1080 -s res://tools/sled_custom_ideas.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --no-buttons \
##       --board=<design/trail-stitches/proposals-01.jpg> --dir=<design/sled-custom>
## 段ごとに 左が場所・右が画面。上から: 人台の桶に浸す、ミシンのそばの見本帳、立てかけ台の前。いちばん下が縫い目の棚。
## --board は feature/trail-stitch-shop の 24 案の絵（雪の上に本物の処理で縫った絵）。左上の番号と名前を切り落として使う。

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Fabrics := preload("res://fabrics.gd")
const Sled := preload("res://sled.gd")

## 縫い目の値段（feature/trail-stitch-shop の stitches.gd。絵の並びと同じ順）
const PRICES := [0, 0, 0, 30, 30, 30, 30, 60, 60, 60, 60, 120, 120, 120, 120, 120, 250, 250, 250, 250, 500, 500, 500, 500]
const STD_KIND := ["small", "mid", "large"]   # 標準の縫い目と、そのソリの大きさ（重いほど太く丈夫）
const TEAL := Color("2F7F8F")
const SWATCHES := ["D2553A", "E08A3C", "D8A43E", "8FA84A", "3F6B4A", "2F7F8F", "6F8FB8", "34477E", "7A4A6E", "C97A8A", "EFE6D2", "4A4038"]
const CENTER_CROP := Rect2(40, 40, 400, 230)

class Ov:
	extends Control
	var fn := Callable()

	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


var args := {}
var main: Node3D
var cam: Camera3D
var ov: Ov
var layer: CanvasLayer
var board: ImageTexture
var _shots := {}
var _keep := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(args.dir)
	_run.call_deferred()


func _lodge(x: float, y: float, h := 0.0) -> Vector3:
	return main.get_node("Lodge").to_global(Vector3(x, h, -y))


func _tile(ci: CanvasItem, i: int, r: Rect2) -> void:
	# 札の形に合わせて、絵の縦横の比を変えずに切り抜く
	var size := CENTER_CROP.size
	var want := r.size.x / r.size.y
	if size.x / size.y > want:
		size.x = size.y * want
	else:
		size.y = size.x / want
	var at := CENTER_CROP.position + (CENTER_CROP.size - size) / 2.0
	ci.draw_texture_rect_region(board, r, Rect2(at + Vector2((i % 4) * 480, (i / 4) * 270), size))


## 回っていないソリの見本（透ける背景）: 3D の本物の glb を、その色で撮る
func _sled_card(kind: String, c: Color, size: Vector2i, yaw := 0.7) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.86, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var body: Node3D = Props.make("res://props/sled_%s.glb" % kind)
	var k: Dictionary = Sled.KINDS[kind]
	Props.recolor(body, k.color, c, k.get("whole", false))
	body.rotation.y = yaw
	vp.add_child(body)
	var cm := Camera3D.new()
	cm.projection = Camera3D.PROJECTION_ORTHOGONAL
	var box: Vector3 = k.box
	cm.size = box.z * 0.92
	cm.keep_aspect = Camera3D.KEEP_WIDTH
	vp.add_child(cm)
	cm.look_at_from_position(Vector3(0, box.z * 0.75, box.z * 1.1), Vector3(0, box.y * 0.5, 0))
	_keep.append(vp)
	return vp


func _save(name: String) -> void:
	await create_timer(0.35).timeout
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	_shots[name] = img
	print("撮った: ", name, " ", img.get_size())


func _ui(on: Callable) -> void:
	ov.fn = on
	ov.queue_redraw()


func _hide_ui() -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = n == layer
	main.get_node("Lodge")


# ---------------------------------------------------------------- 場所の小物

## ぎざぎざに切ったフェルトの布（見本帳の 1 枚）。原点は上の端のまんなか
func _pinked(w: float, h: float, col: Color) -> MeshInstance3D:
	var pts := PackedVector2Array()
	var n := int(w / 0.09)
	var m := int(h / 0.09)
	var z := 0.035
	for i in n * 2:
		pts.append(Vector2(-w / 2.0 + w * i / (n * 2.0), 0.0 if i % 2 == 0 else z))
	for i in m * 2:
		pts.append(Vector2(w / 2.0 - (0.0 if i % 2 == 0 else z), -h * i / (m * 2.0)))
	for i in n * 2:
		pts.append(Vector2(w / 2.0 - w * i / (n * 2.0), -h + (0.0 if i % 2 == 0 else z)))
	for i in m * 2:
		pts.append(Vector2(-w / 2.0 + (0.0 if i % 2 == 0 else z), -h + h * i / (m * 2.0)))
	var tris := Geometry2D.triangulate_polygon(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		var p := pts[t]
		st.set_normal(Vector3.BACK)
		st.set_uv(p)
		st.add_vertex(Vector3(p.x, p.y, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := Look.felt(col)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


## 見本帳: 大きな真鍮の輪で綴じた、ぎざぎざのフェルトの布を扇に開く。木の台に立てる
func _fan_book(at: Vector3, yaw: float) -> Node3D:
	var root3 := Node3D.new()
	main.add_child(root3)
	root3.global_position = at
	root3.rotation.y = yaw
	var pin := Node3D.new()
	pin.position = Vector3(0, 2.7, 0)
	root3.add_child(pin)
	var n := SWATCHES.size()
	for i in n:
		var a := lerpf(-68.0, 68.0, float(i) / (n - 1))
		var sw := _pinked(0.62, 1.75, Color(SWATCHES[i]))
		sw.rotation.z = deg_to_rad(a)
		sw.position = Vector3(0, 0.05, 0.012 * i)
		pin.add_child(sw)
		# 布ごとに紙の札を縫い付ける（色番号の字はなし。白い札と赤の糸）
		var tag := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.24, 0.13)
		tag.mesh = q
		tag.material_override = Look.paper()
		tag.position = Vector3(0, -1.48, 0.006)
		sw.add_child(tag)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.1
	tm.outer_radius = 0.15
	ring.mesh = tm
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.66, 0.30)
	brass.metallic = 0.7
	brass.roughness = 0.35
	ring.material_override = brass
	ring.rotation.x = PI / 2.0
	ring.position = Vector3(0, 0.05, 0.08)
	pin.add_child(ring)
	var wood := Look.wood()
	for sx in [-1.0, 1.0]:   # 物差しの脚
		var leg := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.1, 2.85, 0.05)
		leg.mesh = b
		leg.material_override = wood
		leg.position = Vector3(sx * 0.42, 1.42, -0.1)
		leg.rotation.z = sx * 0.15
		root3.add_child(leg)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.6, 0.1, 0.08)
	top.mesh = tb
	top.material_override = wood
	top.position = Vector3(0, 2.76, -0.08)
	root3.add_child(top)
	var foot := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.6, 0.1, 0.6)
	foot.mesh = fb
	foot.material_override = wood
	foot.position = Vector3(0, 0.05, -0.1)
	root3.add_child(foot)
	return root3


## ソリが入る大きさの染め桶: 人台の桶と同じ、木の桶に 2 本のたが。液はフェルト
func _big_tub(at: Vector3, col: Color) -> Node3D:
	var tub := Node3D.new()
	main.add_child(tub)
	tub.global_position = at
	var wall := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.05
	cm.bottom_radius = 1.95
	cm.height = 0.82
	cm.cap_top = false
	cm.radial_segments = 28
	wall.mesh = cm
	var wood := Look.wood(Color(0.52, 0.34, 0.20))
	wood.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall.material_override = wood
	wall.position.y = 0.41
	tub.add_child(wall)
	for y in [0.16, 0.66]:
		var hoop := MeshInstance3D.new()
		var tm := TorusMesh.new()
		var rr: float = lerpf(1.95, 2.05, y / 0.82)
		tm.inner_radius = rr
		tm.outer_radius = rr + 0.07
		tm.rings = 48
		hoop.mesh = tm
		hoop.material_override = Look.felt(Color(0.20, 0.25, 0.42))
		hoop.position.y = y
		tub.add_child(hoop)
	var liquid := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 2.0
	dm.bottom_radius = 2.0
	dm.height = 0.02
	dm.radial_segments = 40
	liquid.mesh = dm
	liquid.material_override = Look.felt(col)
	liquid.position.y = 0.68
	tub.add_child(liquid)
	return tub


# ---------------------------------------------------------------- 画面の部品

func _felt_board(ci: CanvasItem, r: Rect2, col: Color) -> void:
	Icons.screen()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, col, uv, Icons.felt())
	var inset := r.grow(-14.0)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4, 9.0, 6.0, 0.8, true)


func _close(ci: CanvasItem, c: Vector2) -> void:
	Icons.screen()
	Icons.patch(ci, Icons.circ(c, 24.0, 20), Icons.PAPER, 1.0, false)
	Icons._o = c
	Icons._s = 46.0 / 64.0
	Icons.thread(ci, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)


func _picked(ci: CanvasItem, r: Rect2) -> void:
	Icons.screen()
	var g := r.grow(7.0)
	Icons.dashes(ci, Icons.rr(g.position.x, g.position.y, g.size.x, g.size.y, 8.0), Icons.RED, 3.0, 9.0, 5.0, 1.0, true)


func _stitch_card(ci: CanvasItem, i: int, r: Rect2, owned: bool, pick := false) -> void:
	Icons.screen()
	Icons.paper_tag(ci, r, 10.0, 0.7)
	var inner := Rect2(r.position + Vector2(8, 10), r.size - Vector2(16, 38 if PRICES[i] > 0 and not owned else 18))
	_tile(ci, i, inner)
	if PRICES[i] > 0 and not owned:
		CraftIcons.price(ci, Vector2(r.get_center().x, r.end.y - 16.0), PRICES[i], 8.0)
	if pick:
		_picked(ci, r)


func _pinked_patch(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array()
	var z := 5.0
	var n := int(r.size.x / 10.0)
	var m := int(r.size.y / 10.0)
	for i in n * 2:
		pts.append(r.position + Vector2(r.size.x * i / (n * 2.0), 0.0 if i % 2 == 0 else z))
	for i in m * 2:
		pts.append(Vector2(r.end.x - (0.0 if i % 2 == 0 else z), r.position.y + r.size.y * i / (m * 2.0)))
	for i in n * 2:
		pts.append(r.end - Vector2(r.size.x * i / (n * 2.0), 0.0 if i % 2 == 0 else z))
	for i in m * 2:
		pts.append(Vector2(r.position.x + (0.0 if i % 2 == 0 else z), r.end.y - r.size.y * i / (m * 2.0)))
	Icons.screen()
	Icons.patch(ci, pts, col, 1.0, false)


# ---------------------------------------------------------------- 画面 3 案

## A: 服を染める画面（dye_ui.gd）と同じ板・色の輪。札の中がソリ。右に縫い目の棚
func _screen_a(ci: CanvasItem, tex: Texture2D) -> void:
	var vs: Vector2 = ov.size
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.25))
	var r := Rect2((vs - Vector2(1420, 800)) / 2.0, Vector2(1420, 800))
	_felt_board(ci, r, Color(0.36, 0.30, 0.40))
	var card := Rect2(r.position + Vector2(40, 40), Vector2(470, 500))
	Icons.screen()
	Icons.paper_tag(ci, card, 18.0, 1.0)
	ci.draw_texture_rect(tex, Rect2(card.position + Vector2(10, 40), Vector2(450, 420)), false)
	# 自分のソリの札（押して替えるソリを選ぶ）
	var items := [{"sled": "large", "c": Color("D2553A")}, {"sled": "mid", "c": TEAL}, {"sled": "small", "c": Color("D8A43E")}, {"sled": "sack", "c": Color("B8402E")}]
	for i in items.size():
		var b := Rect2(r.position + Vector2(40 + i * 118.0, 590), Vector2(106, 150))
		Icons.screen()
		Icons.paper_tag(ci, b, 10.0, 0.7)
		var tx: Texture2D = _mini[i]
		ci.draw_texture_rect(tx, Rect2(b.position + Vector2(4, 30), Vector2(98, 98)), false)
		if i == 1:
			_picked(ci, b)
	# 色の輪と明るさの帯
	var ui = main.dye_ui
	ui._hsv = Vector3(TEAL.h, TEAL.s, TEAL.v)
	ui._wheel_r = 200.0
	ui._wheel_c = r.position + Vector2(560 + 200, 60 + 200)
	ui._wheel(ci, 1.0)
	ui._value_rect = Rect2(ui._wheel_c + Vector2(232, -200), Vector2(36, 400))
	ui._value(ci, 1.0)
	# 色の輪の下: 染める札（桶の絵と染め代）
	var d := Rect2(r.position + Vector2(620, 520), Vector2(280, 240))
	Icons.screen()
	Icons.paper_tag(ci, d, 14.0, 1.0)
	Icons.icon(ci, "dye", d.position + Vector2(140, 80), 112.0, 1.0, TEAL)
	Icons.screen()
	CraftIcons.price(ci, d.position + Vector2(140, 190), 40, 16.0)
	Icons.screen()
	Icons.dashes(ci, Icons.rr(d.position.x - 6, d.position.y - 6, d.size.x + 12, d.size.y + 12, 10.0), Icons.RED, 3.0, 9.0, 5.0, 0.8, true)
	# 右: 縫い目の棚
	var names := [0, 1, 2, 4, 7, 11, 14, 18, 23]
	for i in names.size():
		var s := Rect2(r.position + Vector2(980 + (i % 3) * 136.0, 70 + (i / 3) * 228.0), Vector2(124, 214))
		_stitch_card(ci, names[i], s, names[i] < 3 or names[i] == 7, names[i] == 7)
	_close(ci, Vector2(r.end.x - 34, r.position.y + 34))


## B: 開いた見本帳（左の面に布、右の面に縫い目）。布と縫い目は買って持ち、ミシンの前で縫い直す
func _screen_b(ci: CanvasItem, tex: Texture2D) -> void:
	var vs: Vector2 = ov.size
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.25))
	var r := Rect2((vs - Vector2(1500, 860)) / 2.0, Vector2(1500, 860))
	_felt_board(ci, r, Color(0.20, 0.25, 0.42))
	var lp := Rect2(r.position + Vector2(36, 36), Vector2(704, 788))
	var rp := Rect2(r.position + Vector2(760, 36), Vector2(704, 788))
	Icons.screen()
	Icons.paper_tag(ci, lp, 16.0, 1.0)
	Icons.screen()
	Icons.paper_tag(ci, rp, 16.0, 1.0)
	# 綴じの輪
	Icons.screen()
	for k in 5:
		var y := r.position.y + 130.0 + k * 150.0
		ci.draw_arc(Vector2(r.position.x + 750, y), 30.0, 0.0, TAU, 28, Color(0.82, 0.66, 0.30), 7.0, true)
	# 左の面: いま選んでいる布で張ったソリ、その下に布
	ci.draw_texture_rect(tex, Rect2(lp.position + Vector2(170, 44), Vector2(360, 300)), false)
	for i in SWATCHES.size():
		var s := Rect2(lp.position + Vector2(40 + (i % 6) * 106.0, 368 + (i / 6) * 196.0), Vector2(94, 118))
		_pinked_patch(ci, s, Color(SWATCHES[i]))
		Icons.screen()
		CraftIcons.price(ci, s.get_center() + Vector2(0, 80), [8, 8, 8, 12, 8, 12, 12, 8, 8, 12, 8, 12][i], 9.0)
		if i == 5:
			_picked(ci, s)
	# 右の面: 縫い目
	var names := [0, 1, 2, 3, 4, 5, 8, 11, 14, 18, 20, 23]
	for i in names.size():
		var s := Rect2(rp.position + Vector2(36 + (i % 4) * 160.0, 44 + (i / 4) * 206.0), Vector2(150, 194))
		_stitch_card(ci, names[i], s, names[i] < 3 or names[i] == 8, names[i] == 8)
	# 右の面の下: 布 → ミシン → ソリの流れ
	var f := rp.position + Vector2(120, 716)
	CraftIcons.item(ci, {"kind": "fabric", "fabric": "red"}, f, 64.0)
	Icons.screen()
	Icons._o = Vector2.ZERO
	Icons._s = 1.0
	Icons.thread(ci, PackedVector2Array([f + Vector2(60, -14), f + Vector2(84, 0), f + Vector2(60, 14)]), Icons.THREAD, 4.0, 1.0)
	Icons.icon(ci, "needle", f + Vector2(170, 0), 86.0, 1.0)
	Icons.screen()
	Icons._o = Vector2.ZERO
	Icons._s = 1.0
	Icons.thread(ci, PackedVector2Array([f + Vector2(232, -14), f + Vector2(256, 0), f + Vector2(232, 14)]), Icons.THREAD, 4.0, 1.0)
	ci.draw_texture_rect(tex, Rect2(f + Vector2(270, -70), Vector2(150, 125)), false)
	_close(ci, Vector2(r.end.x - 34, r.position.y + 34))


## C: 立てかけ台のソリを見たまま替える。下の細い札だけ（世界を隠さない）。色はその場でソリに当たる
func _screen_c(ci: CanvasItem) -> void:
	var vs: Vector2 = ov.size
	var r := Rect2(Vector2(170, vs.y - 330), Vector2(vs.x - 340, 300))
	_felt_board(ci, r, Color(0.31, 0.25, 0.20))
	var dia := 70.0
	for i in SWATCHES.size():
		var c := r.position + Vector2(70 + i * (dia + 26.0), 72)
		Icons.screen()
		Icons.patch(ci, Icons.circ(c, dia * 0.5, 24), Color(SWATCHES[i]), 1.0, true)
		if i == 5:
			_picked(ci, Rect2(c - Vector2(dia, dia) / 2.0, Vector2(dia, dia)))
	# 輪: 自由な色へ（染めの画面の色の輪を小さく）
	var ui = main.dye_ui
	ui._hsv = Vector3(TEAL.h, TEAL.s, TEAL.v)
	ui._wheel_r = 44.0
	ui._wheel_c = r.position + Vector2(70 + SWATCHES.size() * (dia + 26.0) + 10.0, 72)
	ui._wheel(ci, 0.5)
	var names := [0, 1, 2, 3, 4, 7, 11, 14, 18, 23]
	for i in names.size():
		var s := Rect2(r.position + Vector2(40 + i * 118.0, 136), Vector2(108, 146))
		_stitch_card(ci, names[i], s, names[i] < 3 or names[i] == 7, names[i] == 7)
	var d := Vector2(r.end.x - 150, r.position.y + 150)
	Icons.screen()
	Icons.icon(ci, "dye", d, 96.0, 1.0, TEAL)
	Icons.screen()
	CraftIcons.price(ci, d + Vector2(0, 86), 40, 13.0)
	_close(ci, Vector2(r.end.x - 34, r.position.y + 34))


## 縫い目の棚の一覧: 雪の上に縫った本物の絵に、ボタンの値段。左上の 3 つは標準（ソリの大きさの型紙）
func _stitch_sheet(ci: CanvasItem) -> void:
	var vs: Vector2 = ov.size
	Icons.screen()
	_felt_board(ci, Rect2(Vector2.ZERO, vs), Color(0.31, 0.25, 0.20))
	var cols := 6
	var w: float = (vs.x - 80.0) / cols
	var h: float = (vs.y - 60.0) / 4.0
	for i in 24:
		var r := Rect2(Vector2(40 + (i % cols) * w, 30 + (i / cols) * h), Vector2(w - 14, h - 14))
		Icons.screen()
		Icons.paper_tag(ci, r, 12.0, 0.8)
		var inner := Rect2(r.position + Vector2(10, 16), Vector2(r.size.x - 20, r.size.y - 76))
		_tile(ci, i, inner)
		var at := Vector2(r.get_center().x, r.end.y - 34.0)
		if PRICES[i] > 0:
			Icons.screen()
			CraftIcons.price(ci, at, PRICES[i], 9.5)
		else:
			CraftIcons.item(ci, {"kind": "pattern", "sled": STD_KIND[i]}, at, 54.0)


# ---------------------------------------------------------------- 撮る

var _mini: Array[Texture2D] = []


func _run() -> void:
	await create_timer(3.0).timeout
	var img := Image.load_from_file(args.board)
	board = ImageTexture.create_from_image(img)
	layer = CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	ov = Ov.new()
	# 画面の倍率によらず、1920 × 1080 の座標で描く
	var vis: Vector2 = root.get_visible_rect().size
	print("画面 ", root.size, " 見える範囲 ", vis)
	ov.size = Vector2(1920, 1080)
	ov.scale = vis / ov.size
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ov)
	var craft = main.craft
	var p = main.player
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	root.add_child(cam)
	cam.current = true
	_hide_ui()
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.hour = 11.0
		dc.day_seconds = 1.0e9
	var tmid := _sled_card("mid", TEAL, Vector2i(900, 840))
	_mini = []
	for it in [["large", Color("D2553A")], ["mid", TEAL], ["small", Color("D8A43E")], ["sack", Color("B8402E")]]:
		_mini.append(_sled_card(it[0], it[1], Vector2i(200, 200)).get_texture())
	await create_timer(0.4).timeout

	# A: 人台の桶にソリを浸す
	var vat = main.dye_vat
	var liquid: StandardMaterial3D = vat._liquid
	liquid.albedo_color = TEAL
	if vat._cloth:
		vat._cloth.albedo_color = TEAL
	vat._to = TEAL
	vat._from = TEAL
	# 人台の桶は人台の裾を囲む輪で、ソリは入らない。となりに、同じ作りの大きな桶を置く
	var tub_at: Vector3 = vat.to_global(Vector3(float(args.get("tx", "1.2")), 0.0, float(args.get("tz", "4.4"))))
	tub_at.y = vat.global_position.y
	var tub := _big_tub(tub_at, TEAL)
	var dunk: Node3D = Props.make("res://props/sled_mid.glb")   # 形だけ（物理で動かない）
	Props.recolor(dunk, Sled.KINDS.mid.color, TEAL, false)
	main.add_child(dunk)
	var b := Basis(vat.global_basis.get_rotation_quaternion()) * Basis.from_euler(Vector3(deg_to_rad(-20), deg_to_rad(35), deg_to_rad(-7)))
	dunk.global_transform = Transform3D(b, tub_at + Vector3(0, 0.48, 0))
	p.global_position = tub_at + vat.global_basis * Vector3(-3.0, 0.1, 1.2)
	p.look_at(tub_at + Vector3(0, p.global_position.y - tub_at.y, 0))
	await create_timer(0.4).timeout
	cam.look_at_from_position(tub_at + vat.global_basis * Vector3(1.4, 3.3, 6.0), tub_at + vat.global_basis * Vector3(-0.2, 0.9, -1.0))
	cam.reset_physics_interpolation()
	_ui(Callable())
	await _save("a_place")
	_ui(_screen_a.bind(tmid.get_texture()))
	await _save("a_screen")
	_ui(Callable())
	dunk.queue_free()
	tub.queue_free()

	# B: ミシンのそばの見本帳
	var sk: Node3D = main.shopkeeper
	var mc: Node3D = main.sewing
	print("おじさん ", sk.global_position, " ミシン ", mc.global_position)
	var lodge: Node3D = main.get_node("Lodge")
	var ml: Vector3 = lodge.to_local(mc.global_position)
	print("ミシン（ロッジの座標） ", ml)
	var book_at: Vector3 = lodge.to_global(Vector3(ml.x + float(args.get("bx", "-5.0")), ml.y, ml.z + float(args.get("bz", "-1.5"))))
	book_at.y = main.height(book_at.x, book_at.z)
	var book := _fan_book(book_at, 0.0)
	# 正面（+Z）を、ロッジの -x（開けた雪の側）へ向ける
	var out: Vector3 = (lodge.to_global(Vector3(-1, 0, 0)) - lodge.to_global(Vector3.ZERO)).normalized()
	book.global_rotation.y = atan2(out.x, out.z)
	p.global_position = book.to_global(Vector3(1.3, 0.1, 2.0))
	p.look_at(book.global_position + Vector3(0, p.global_position.y - book.global_position.y, 0))
	cam.look_at_from_position(book.to_global(Vector3(-1.6, 1.5, 4.6)), book.to_global(Vector3(0.3, 1.6, 0)))
	cam.reset_physics_interpolation()
	await _save("b_place")
	_ui(_screen_b.bind(tmid.get_texture()))
	await _save("b_screen")
	_ui(Callable())

	# C: 立てかけ台の前
	var far := _lodge(-40.0, 2.0)
	var ids := []
	var cols := [Color("D2553A"), TEAL, Color("D8A43E"), Color("7A4A6E")]
	var kinds := ["large", "mid", "small", "mid"]
	for i in 4:
		var id: int = craft._place(kinds[i], "", far, 0.0, 0, Vector3.UP, craft.tag_designs[p.id], false, p.id)
		craft.sleds[id].set_main_color(cols[i])
		ids.append(id)
		far += Vector3(0, 0, 6)
	await create_timer(0.3).timeout
	p.global_position = _lodge(-27.5, 3.0, 0.1)
	await create_timer(0.1).timeout
	for id in ids:
		print("戻す ", id, " ", craft.send({"kind": "rack_in", "who": p.id, "id": id}))
	await create_timer(1.8).timeout
	var midsled: Node3D = craft.sleds[ids[1]]
	var ms := midsled.global_position
	print("中のソリ ", ms)
	p.global_position = ms + _lodge(-3.2, 0.0, 0.1) - _lodge(0.0, 0.0, 0.0) + Vector3(0, -ms.y + 0.1, 0)
	p.look_at(ms + Vector3(0, 0.1 - ms.y + p.global_position.y - 0.1, 0))
	cam.look_at_from_position(_lodge(-33.5, 1.5, 2.2), _lodge(-24.0, 3.5, 1.7))
	cam.reset_physics_interpolation()
	var mark := func(ci: CanvasItem) -> void:
		var at: Vector2 = cam.unproject_position(ms + Vector3(0, 1.1, 0))
		Icons.keycap(ci, "F", at + Vector2(-50, 0), 44.0)
		Icons.icon(ci, "dye", at + Vector2(30, 0), 80.0, 1.0, TEAL)
	_ui(mark)
	await _save("c_place")
	cam.fov = 48.0
	cam.cull_mask = 1   # 一人称（自分の人形と飾りは映らない）
	p.global_position = _lodge(-60.0, 3.0, 0.1)   # 自分の息と連れた小物が前をふさがないように
	cam.fov = 54.0
	await create_timer(1.8).timeout   # 息が消えるまで
	cam.look_at_from_position(ms + _lodge(-5.6, 0.0, 0.0) - _lodge(0.0, 0.0, 0.0) + Vector3(0, 0.3, 0), ms + Vector3(0, -1.3, 0))
	cam.reset_physics_interpolation()
	_ui(_screen_c)
	await _save("c_screen")

	# 縫い目の棚
	_ui(_stitch_sheet)
	await _save("stitches")
	_compose()
	quit()


func _compose() -> void:
	var dir: String = args.dir
	var tw := 960
	var th := 540
	var rows := [["a_place", "a_screen", "a"], ["b_place", "b_screen", "b"], ["c_place", "c_screen", "c"]]
	var sheet := Image.create(tw * 2, th * 3 + th * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.95, 0.93, 0.88))
	for r in rows.size():
		var row := Image.create(tw * 2, th, false, Image.FORMAT_RGB8)
		for c in 2:
			var im: Image = _shots[rows[r][c]].duplicate()
			im.resize(tw, th, Image.INTERPOLATE_LANCZOS)
			row.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i(c * tw, 0))
			sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i(c * tw, r * th))
		row.save_jpg(dir.path_join(rows[r][2] + ".jpg"), 0.88)
	var st: Image = _shots["stitches"].duplicate()
	st.resize(tw * 2, th * 2, Image.INTERPOLATE_LANCZOS)
	sheet.blit_rect(st, Rect2i(0, 0, tw * 2, th * 2), Vector2i(0, th * 3))
	st.save_jpg(dir.path_join("stitches.jpg"), 0.88)
	sheet.save_jpg(dir.path_join("00-proposals.jpg"), 0.88)
	print("書いた: ", dir)
