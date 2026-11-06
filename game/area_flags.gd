extends Node3D
## 山の目印の大きな旗。札の布の地と同じ色と柄（elev_card.gd）で、それぞれの山のそばに立つ。札を見て、同じ布の旗を探せばその山に着く。
## 2026-11-04 代表「その色と柄のフラッグを各山の近くに立てとけば良いもんね」。
## 布の絵は札と同じ描き方で一度だけ焼く。旗に当たりはない（ほかの旗と同じ）。
## ロッジの前には、同じ布を切り抜いて貼った地図の看板を立てる（2026-11-04 代表「ロッジの前に大きな地図看板欲しいかも」）。
## 地図は areas.gd の表から描くので、山を足すと地図にも載る。文字は使わない
## 地図の上に、いまいる人のまち針が刺さって動く（map_pins.gd）

const Card := preload("res://elev_card.gd")
const Icons := preload("res://hud_icons.gd")
const Areas := preload("res://areas.gd")
const MapPins := preload("res://map_pins.gd")

const POLE_H := 7.0          # 棒の高さ (m)。丘のコースの旗（1.7 m）の 4 倍ほど。ロッジの前から見つかる大きさ
const CLOTH := Vector2(3.6, 2.25)   # 布の大きさ (m)
const TEX := Vector2i(384, 240)    # 焼く布の絵の大きさ

## 旗の場所 (x, z): 麓の両脇と頂上。ロッジの側から見える麓に 2 本、登りきった頂上に 1 本。滑る道の真ん中は空ける
const PLACES := {
	"hill": [Vector2(-22, 56), Vector2(-40, 44), Vector2(4, -4)],
	"slope": [Vector2(12, 226), Vector2(-42, 226), Vector2(2, 487)],
	"peak": [Vector2(156, -14), Vector2(156, 78), Vector2(704, 42)],
}

const BOARD := Vector2(8.0, 5.33)   # 地図の看板の大きさ (m)
const BOARD_Y := 1.0               # 地面から看板の下の縁まで (m)
const BOARD_AT := Vector2(-25.0, 31.0)   # 看板の場所（ロッジの座標）。玄関を出て左、道と届いたソリの脇。表は玄関へ
const MAP_TEX := Vector2i(1500, 1000)
const LIT := Color(0.60, 0.60, 0.60, 1.0)   # 雪山の光で布が白く飛ぶので、札の色に見えるよう沈める
const HILL_MAP_K := 1.35               # 地図の丘は実際より大きく（見つけやすいように。絵地図なので縮尺どおりにしない）
const PIN_EDGE := 44.0                 # まち針が地図の縁の縫い目より外へ出ない幅（絵の上の画素）

static var _box := Rect2()   # 地図に入れる世界の範囲（一度だけ測る）

var main: Node3D
var cloth := {}   # 範囲の名前 → 焼いた布の絵


func _ready() -> void:
	for id in PLACES:
		cloth[id] = await _bake(id)
		for at in PLACES[id]:
			_put(id, cloth[id], at)
	_put_map(await _bake_map())


## 札と同じ描き方で布の絵を焼く（画面のない起動では焼かず、無地の布にする）
func _bake(id: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = TEX
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := _Cloth.new()
	c.id = id
	c.size = Vector2(TEX)
	vp.add_child(c)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


class _Cloth extends Control:
	var id := ""
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Card.area_color(id))
		var u := size.y / 22.0   # 札の段の倍の粗さ（遠くから柄が見えるように）
		Icons.screen()
		Card.stitches(self, id, r.grow(u), 1.0, u)


## 世界 (x, z) を地図の絵の上の位置へ（絵の大きさ size）。全部の範囲が入る縮尺
static func map_point(p: Vector2, size: Vector2) -> Vector2:
	if _box.size == Vector2.ZERO:
		_box = Rect2(Vector2(-35, 98), Vector2.ZERO)   # ロッジ
		for id in PLACES:
			var f := Areas.info(id)
			var t: Vector2 = f.top
			var dir: Vector2 = f.dir
			var side := Vector2(dir.y, -dir.x) * float(f.rx)
			for q in [t + dir * float(f.rn) + side, t + dir * float(f.rn) - side, t - dir * float(f.rs) + side, t - dir * float(f.rs) - side]:
				_box = _box.expand(q)
		_box = _box.grow(50.0)
	var k := minf(size.x / _box.size.x, size.y / _box.size.y)
	return size / 2.0 + (p - _box.get_center()) * k


## 世界 (x, z) を看板の上の位置 (x, y) へ。地図の外にいる人のまち針は、地図の縁の内側で止まる
static func on_board(p: Vector2) -> Vector2:
	var size := Vector2(MAP_TEX)
	var at := map_point(p, size).clamp(Vector2.ONE * PIN_EDGE, size - Vector2.ONE * PIN_EDGE) / size
	return Vector2((at.x - 0.5) * BOARD.x, BOARD_Y + (1.0 - at.y) * BOARD.y)


## 地図の絵を焼く
func _bake_map() -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = MAP_TEX
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := _Map.new()
	c.cloth = cloth
	c.point = map_point
	c.size = Vector2(MAP_TEX)
	c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	vp.add_child(c)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 地図の絵: 上がロッジから丘の向き（北）。範囲の楕円を布から切り抜いて貼り、ロッジと、ロッジから山へ行く道を縫う
class _Map extends Control:
	var cloth := {}
	var point: Callable   # map_point（中の class からは外の関数を呼べないので受け取る）

	func to_map(p: Vector2) -> Vector2:
		return point.call(p, size)

	func _draw() -> void:
		Icons.screen()
		draw_rect(Rect2(Vector2.ZERO, size), Icons.PAPER)
		var u := size.y / 160.0
		Icons.dashes(self, Icons.rr(5.0 * u, 5.0 * u, size.x - 10.0 * u, size.y - 10.0 * u, 3.0 * u), Icons.THREAD, 0.7 * u, 3.0 * u, 2.0 * u, 1.0, true)
		var lodge := to_map(Vector2(-35, 98))
		for id in cloth:
			var f := Areas.info(id)
			var t: Vector2 = f.top
			var dir: Vector2 = f.dir
			var pts := PackedVector2Array()
			for i in 48:   # 範囲より少し内の楕円（手前と奥で半径が違う）
				var a := TAU * i / 48.0
				var k := 0.86 * (HILL_MAP_K if id == "hill" else 1.0)
				var along := cos(a) * float(f.rn if cos(a) >= 0.0 else f.rs) * k
				var side := sin(a) * float(f.rx) * k
				pts.append(to_map(t + dir * along + Vector2(dir.y, -dir.x) * side))
			# 道: ロッジから麓へ、藍の糸
			var foot: Vector2 = pts[0]
			Icons.dashes(self, PackedVector2Array([lodge, lodge.lerp(foot, 0.5) + Vector2(6.0, 0) * u, foot]), Icons.THREAD, 1.1 * u, 3.5 * u, 2.5 * u)
			var sh := PackedVector2Array()
			var uv := PackedVector2Array()
			for q in pts:
				sh.append(q + Vector2(1.0, 1.6) * u)
				uv.append(q / Vector2(384.0, 240.0))
			draw_colored_polygon(sh, Color(Icons.SHADOW, 0.3))
			if cloth[id]:
				draw_colored_polygon(pts, Color.WHITE, uv, cloth[id])
			else:
				draw_colored_polygon(pts, Card.area_color(id))
			var rim := pts.duplicate()
			rim.append(pts[0])
			draw_polyline(rim, Color(Card.area_color(id).darkened(0.35)), 1.4 * u, true)
			Icons.dashes(self, Geometry2D.offset_polygon(pts, -2.4 * u)[0], Color(Icons.SNOW, 0.9), 0.7 * u, 2.6 * u, 1.8 * u, 1.0, true)
			# 頂上の赤い旗
			var top := to_map(t)
			var fk := 1.1 * u
			draw_line(top, top - Vector2(0, 13) * fk, Icons.WOOD.darkened(0.2), 1.1 * u, true)
			draw_circle(top, 2.0 * fk, Icons.THREAD)
			draw_colored_polygon(PackedVector2Array([top - Vector2(0, 13) * fk, top + Vector2(9, -10) * fk, top - Vector2(0, 7) * fk]), Icons.RED)
		# ロッジと、いまいる所の赤いボタン
		Card._lodge(self, lodge + Vector2(0, 7.0) * u, 1.5 * u, 1.0)
		draw_circle(lodge + Vector2(13.0, -3.0) * u, 4.4 * u, Icons.SNOW)
		draw_circle(lodge + Vector2(13.0, -3.0) * u, 3.4 * u, Icons.RED)


func _put_map(tex: Texture2D) -> void:
	var at: Vector2 = main.lodge_to_world(BOARD_AT)
	var root := Node3D.new()
	root.name = "AreaMap"
	root.position = Vector3(at.x, main.foot_y(at.x, at.y, 0.1) - 0.05, at.y)
	var door: Vector2 = main.lodge_to_world(Vector2(main.PATH_X, 17.0))
	var look := door - at
	root.rotation.y = atan2(look.x, look.y)   # 表（+Z）を玄関へ
	add_child(root)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Icons.WOOD * LIT
	wood.roughness = 0.7
	# 額と 2 本の脚
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(BOARD.x + 0.36, BOARD.y + 0.36, 0.16)
	frame.mesh = fm
	frame.material_override = wood
	frame.position = Vector3(0, BOARD_Y + BOARD.y / 2.0, 0)
	root.add_child(frame)
	for sx in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.28, BOARD_Y + 0.5, 0.24)
		leg.mesh = lm
		leg.material_override = wood
		leg.position = Vector3(sx * (BOARD.x / 2.0 - 0.7), (BOARD_Y + 0.5) / 2.0 - 0.1, -0.02)
		root.add_child(leg)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = BOARD
	face.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = LIT if tex else Icons.PAPER
	m.roughness = 0.95
	face.material_override = m
	face.position = Vector3(0, BOARD_Y + BOARD.y / 2.0, 0.09)
	root.add_child(face)
	var pins := MapPins.new()
	pins.name = "MapPins"
	pins.main = main
	pins.to_board = on_board
	root.add_child(pins)
	# 脚の当たり（板は脚より上なので、脚だけ）
	var body := StaticBody3D.new()
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.32, BOARD_Y + BOARD.y, 0.28)
		cs.shape = bs
		cs.position = Vector3(sx * (BOARD.x / 2.0 - 0.7), (BOARD_Y + BOARD.y) / 2.0, 0)
		body.add_child(cs)
	root.add_child(body)


func _put(id: String, tex: Texture2D, at: Vector2) -> void:
	var root := Node3D.new()
	root.name = "AreaFlag_" + id
	root.position = Vector3(at.x, main.foot_y(at.x, at.y, 0.1) - 0.1, at.y)
	root.rotation.y = _yaw(at)
	add_child(root)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.1
	cyl.height = POLE_H
	pole.mesh = cyl
	pole.position.y = POLE_H / 2.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Icons.WOOD * LIT
	wood.roughness = 0.7
	pole.material_override = wood
	root.add_child(pole)
	var cloth := MeshInstance3D.new()
	cloth.mesh = _cloth_mesh()
	cloth.position = Vector3(0.07, POLE_H - 0.1 - CLOTH.y, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = LIT if tex else Card.area_color(id)
	m.albedo_texture = tex
	if tex:   # 日の当たらない向きでも、札の色と分かるように少し自分で光らせる
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission_energy_multiplier = 0.28
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_albedo = load("res://props/textures/felt_detail.png") if ResourceLoader.exists("res://props/textures/felt_detail.png") else null
	m.uv2_triplanar = true
	m.uv2_scale = Vector3.ONE * 0.8
	cloth.material_override = m
	root.add_child(cloth)


## 旗の布の面を、ロッジの側へ向ける
func _yaw(at: Vector2) -> float:
	var look: Vector2 = main.LODGE_POS - at
	return atan2(look.x, look.y)


## 少し波打つ布（x が棒から先へ、y が上）
static func _cloth_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 14
	var nv := 6
	var p := func(i: int, j: int) -> Vector3:
		var t := i / float(nu)
		return Vector3(t * CLOTH.x, j / float(nv) * CLOTH.y - sin(t * 2.0) * 0.07, sin(t * 7.0) * 0.09 * t)
	for i in nu:
		for j in nv:
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				st.set_uv(Vector2(q[0] / float(nu), 1.0 - q[1] / float(nv)))
				st.add_vertex(p.call(q[0], q[1]))
	st.generate_normals()
	return st.commit()
