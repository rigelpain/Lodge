extends Node3D
## 旭ヶ丘スキー場のゲレンデの小物（2026-11-11）。見取り図 design/asahigaoka/slope/01-slope-map.png の番号:
##   ① 乗り場の手前の無地の札  ④ ジャンプ台の櫓（使っていない）  ⑤ 小さなジャンプ台と審判の櫓 2 つ
##   ⑥ オレンジのネット（リフト沿い・降り場のまわり・主コースの上の縁）  ⑦ ナイターの照明の柱
##   ⑩ そり・子どもの広場の仕切り（灰のポールとピンクの帯）  ⑪ 休憩所の前の石の看板
## 手本は tenkamori_slope.gd。形は色ごとに 1 つの MeshInstance3D にためる。x = 東、z = 南。

const Tenka := preload("res://tenkamori.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Lift := preload("res://tenkamori_lift.gd")

const NET := "res://props/net_span.glb"
const SPAN := 2.5
const ORANGE := Color(1.0, 0.45, 0.10)
const IRON := Color(0.27, 0.15, 0.12)   # 赤茶の鉄骨
const POLE := Color(0.56, 0.58, 0.60)
const PINK := Color(1.0, 0.45, 0.65)

var world: Node3D
var _mats := {}
var _st := {}
var _body: StaticBody3D
var up := Vector2.ZERO      # リフトを上る向き
var side := Vector2.ZERO    # ゲレンデの側（北東）
var _lift: Array = []
var _lift_len := 0.0


func _ready() -> void:
	var m: Dictionary = Tenka.map()
	for l in m.get("lifts", []):
		if l["kind"] == "chair_lift":
			_lift = l["line"]
	if _lift.is_empty():
		return
	_body = StaticBody3D.new()
	_body.name = "SlopeColliders"
	add_child(_body)
	up = (_v(_lift[_lift.size() - 1]) - _v(_lift[0])).normalized()
	side = Vector2(-up.y, up.x)
	if side.x - side.y < 0.0:
		side = -side
	_lift_len = _length(_lift)
	var down_line: Array = []
	for p in m.get("pistes", []):
		if p["kind"] == "downhill" and down_line.is_empty():
			down_line = p["line"]
	if m.has("course2"):   # 初級コース: 空中写真の切り開きをなぞった線（bake_terrain.py の COURSE2）
		down_line = (m["course2"] as Array).duplicate()
	_nets()
	_lights(down_line)
	_jump_tower()
	_small_jump()
	_judge_tower(Vector2(-45, -105))
	_judge_tower(Vector2(-30, -88))
	_divider()
	_plate()
	_stone_sign()
	for key in _st:
		var mi := MeshInstance3D.new()
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _mat(key)
		mi.name = "Slope_" + key
		add_child(mi)


func _mat(key: String) -> Material:
	var m: BaseMaterial3D
	match key:
		"iron": m = Look.felt(IRON, 1.4)
		"pole": m = Look.felt(POLE, 1.4)
		"stone": m = Look.felt(Color(0.30, 0.31, 0.33), 1.6)
		"sledred": m = Look.felt(Color(0.80, 0.16, 0.12), 1.6)
		"pink": m = Look.felt(PINK, 1.2)
		"snow": m = Look.snow()
		"plate": m = Look.paper(Color(0.95, 0.95, 0.92))
		"lamp":
			m = Look.paper(Color(0.98, 0.95, 0.85))
			m.emission_enabled = true
			m.emission = Color(1.0, 0.92, 0.75)
			m.emission_energy_multiplier = 0.6
		_: m = Look.felt(Color.MAGENTA)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _s(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


static func _v(p) -> Vector2:
	return Vector2(p[0], p[1])


static func _length(line: Array) -> float:
	var acc := 0.0
	for k in line.size() - 1:
		acc += _v(line[k]).distance_to(_v(line[k + 1]))
	return acc


static func _along(line: Array, s: float) -> Array:
	var acc := 0.0
	for k in line.size() - 1:
		var a := _v(line[k])
		var b := _v(line[k + 1])
		var L := a.distance_to(b)
		if acc + L >= s:
			return [a.lerp(b, (s - acc) / L), (b - a).normalized()]
		acc += L
	var n := line.size()
	return [_v(line[n - 1]), (_v(line[n - 1]) - _v(line[n - 2])).normalized()]


## 水平の向き a（x = a、y = 上、z = a を 90° 回した向き）
static func _frame(a: Vector2) -> Basis:
	var fx := Vector3(a.x, 0, a.y)
	return Basis(fx, Vector3.UP, fx.cross(Vector3.UP))


static func _w(o: Vector2, b: Basis, lx: float, y: float, lz: float) -> Vector3:
	var h := b * Vector3(lx, 0, lz)
	return Vector3(o.x + h.x, y, o.y + h.z)


func _gy(p: Vector3, r := 0.3) -> float:
	return world.foot_y(p.x, p.z, r)


# ---- 形の部品 ----------------------------------------------------------------------------

func _box(key: String, c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	preload("res://asahi_lodge.gd")._bx(_s(key), c, size, b)   # 面の表を外へ向けた箱（Lift.box は裏返しで、雪の帽子が陰の色になる）


func _cyl(key: String, p0: Vector3, p1: Vector3, r: float, seg := 8) -> void:
	Lift.cyl(_s(key), p0, p1, r, seg)


## p0 から p1 へ渡した板（厚み th、幅 w）。lift は板の法線の向きへのずらし
func _plank(key: String, p0: Vector3, p1: Vector3, th: float, w: float, lift := 0.0) -> void:
	var x := (p1 - p0).normalized()
	var z := x.cross(Vector3.UP).normalized()
	var y := z.cross(x)
	_box(key, (p0 + p1) * 0.5 + y * lift, Vector3(p0.distance_to(p1), th, w), Basis(x, y, z))


func _col_box(c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(b, c)
	_body.add_child(cs)


func _col_cyl(p0: Vector3, p1: Vector3, r: float) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = p0.distance_to(p1)
	cs.shape = sh
	var y := (p1 - p0).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	cs.transform = Transform3D(Basis(x, y, x.cross(y)), (p0 + p1) * 0.5)
	_body.add_child(cs)


# ---- ⑥ ネット --------------------------------------------------------------------------

func _net(a: Vector2, b: Vector2, col: Color) -> void:
	var L := a.distance_to(b)
	if L < 0.5:
		return
	var n := maxi(1, int(round(L / SPAN)))
	var d := (b - a) / n
	var yaw := atan2(-d.y, d.x)
	for k in n + 1:
		var p := a + d * k
		var span := Props.make(NET)
		_dye(span, col)
		span.rotation.y = yaw
		span.position = Vector3(p.x, world.foot_y(p.x, p.y, 0.1) - 0.05, p.y)
		span.scale = Vector3(L / n / SPAN, 1.0, 1.0)
		if k == n:   # 最後は杭だけ
			for mi in span.find_children("*", "MeshInstance3D", true, false):
				if "_yarn" in mi.name or "_knots" in mi.name:
					mi.visible = false
		add_child(span)


func _dye(n: Node, col: Color) -> void:
	for node in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as BaseMaterial3D
			if m == null or not (m.resource_name.begins_with("yarn") or "_yarn" in mi.name or "_knots" in mi.name):
				continue
			var key := [m, col]
			if not _mats.has(key):
				var d := m.duplicate() as BaseMaterial3D
				d.albedo_color = col
				_mats[key] = d
			mi.set_surface_override_material(s, _mats[key])


func _nets() -> void:
	var L := _lift_len
	var lo := 25.0
	var hi := L - 20.0
	# 柱ごとに前後 12 m、柱と柱のあいだは 1 区間おきに中ほどの 10 m
	var anchors: Array[float] = [lo]
	var acc := 0.0
	for k in _lift.size() - 1:
		acc += _v(_lift[k]).distance_to(_v(_lift[k + 1]))
		if k + 1 >= 1 and k + 1 <= _lift.size() - 2:
			anchors.append(acc)
	anchors.append(hi)
	var runs: Array = []
	for i in range(1, anchors.size() - 1):
		runs.append([anchors[i] - 12.0, anchors[i] + 12.0])
	for i in anchors.size() - 1:
		if i % 2 == 0:
			var mid: float = (anchors[i] + anchors[i + 1]) * 0.5
			runs.append([mid - 5.0, mid + 5.0])
	for r in runs:
		var s0: float = maxf(r[0], lo)
		var s1: float = minf(r[1], hi)
		if s1 - s0 < 1.0:
			continue
		var a: Vector2 = _along(_lift, s0)[0] + side * 9.0
		var b: Vector2 = _along(_lift, s1)[0] + side * 9.0
		_net(a, b, ORANGE)
	# 降り場のまわり: コの字
	var t := _v(_lift[_lift.size() - 1])
	var p0 := t + side * 14.0
	var p1 := p0 + up * 10.0
	var p2 := t + up * 10.0 - side * 10.0
	_net(p0, p1, ORANGE)
	_net(p1, p2, ORANGE)
	# 主コースの北東の縁（ジャンプ台の櫓とコースのあいだ。写真 dzk-380・dzk-405）。
	# 2026-11-12 代表「柵おかしいかも頂上付近の。二方向からの作画が合流するとこある」: 前はリフト沿いのネットの上の端と X に交わっていた。
	# リフト沿いのネットの上の端（降り場の手前 20 m）から北へ 8 m ほど離して始め、降り場から主コースへ出る人が、そのあいだを通れるようにする
	var top_end: Vector2 = _along(_lift, hi)[0] + side * 9.0
	var c0 := top_end + side * 4.0 + up * 6.0
	_net(c0, Vector2(-203, -199), ORANGE)
	_net(Vector2(-203, -199), Vector2(-178, -186), ORANGE)


# ---- ⑦ ナイターの照明 ------------------------------------------------------------------

## at に灰の柱（高さ 10 m）。face = 灯具が向く水平の向き、arm = 横木の向き
func _lamp_pole(at: Vector2, face: Vector2, arm: Vector2) -> void:
	var g := _gy(Vector3(at.x, 0, at.y))
	var top := g + 10.0
	_cyl("pole", Vector3(at.x, g - 0.4, at.y), Vector3(at.x, top, at.y), 0.1, 8)
	_col_cyl(Vector3(at.x, g - 0.4, at.y), Vector3(at.x, top, at.y), 0.12)
	var a3 := Vector3(arm.x, 0, arm.y).normalized()
	var f3 := Vector3(face.x, 0, face.y).normalized()
	var c := Vector3(at.x, top, at.y) + f3 * 0.25
	_plank("pole", c - a3 * 1.1, c + a3 * 1.1, 0.1, 0.1)
	var n := (f3 * 0.35 + Vector3.DOWN).normalized()
	for k in [-0.8, -0.27, 0.27, 0.8]:
		var lc: Vector3 = c + a3 * k - Vector3.UP * 0.18 + f3 * 0.1
		_cyl("lamp", lc - n * 0.09, lc + n * 0.09, 0.22, 12)


func _lights(down_line: Array) -> void:
	for t in [0.12, 0.32, 0.52, 0.72, 0.9]:
		var p: Vector2 = _along(_lift, _lift_len * t)[0]
		for off in [16.0, 78.0 - 22.0 * t]:
			_lamp_pole(p + side * off, -up, side)
	# 麓へ下りる道の北の縁（林の島の先の側）に 2 本。南の斜面はそりコースなので、中には立てない
	for q in [Vector2(-112, 34), Vector2(-48, 24)]:
		_lamp_pole(q, Vector2(0, 1), Vector2(1, 0))
	if down_line.is_empty():
		return
	var cen := Vector2.ZERO
	for q in down_line:
		cen += _v(q)
	cen /= down_line.size()
	var L := _length(down_line)
	var s := 45.0
	var n := 0
	while s < L and n < 6:
		var r := _along(down_line, s)
		var p: Vector2 = r[0]
		var tan: Vector2 = r[1]
		var nrm := Vector2(-tan.y, tan.x)
		if nrm.dot(p - cen) < 0.0:
			nrm = -nrm
		_lamp_pole(p + nrm * 20.0, -nrm, tan)   # 切り開きの幅（26〜44 m）の縁
		s += 80.0
		n += 1


# ---- ④ ジャンプ台の櫓 -----------------------------------------------------------------

func _jump_tower() -> void:
	var o := Vector2(-222, -215)
	var B := _frame(up)
	var g0 := -INF
	var gs := {}
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var w := _w(o, B, 2.5 * sx, 0, 2.5 * sz)
			var g := _gy(w, 0.4)
			gs[Vector2i(sx, sz)] = g
			g0 = maxf(g0, g)
	var topY := g0 + 14.0
	# 4 本の柱（上へ少し広がる）
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p0 := _w(o, B, 2.5 * sx, gs[Vector2i(sx, sz)] - 0.4, 2.5 * sz)
			var p1 := _w(o, B, 3.0 * sx, topY, 3.0 * sz)
			_cyl("iron", p0, p1, 0.14, 8)
			_col_cyl(p0, p1, 0.16)
	# 輪（横の筋）と筋交い 3 段
	var corners := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	for band in 3:
		var t0 := band / 3.0
		var t1 := (band + 1) / 3.0
		for f in 4:
			var ca: Vector2i = corners[f]
			var cb: Vector2i = corners[(f + 1) % 4]
			var h0 := 2.5 + 0.5 * t0
			var h1 := 2.5 + 0.5 * t1
			var a0 := _w(o, B, h0 * ca.x, g0 + 14.0 * t0, h0 * ca.y)
			var b0 := _w(o, B, h0 * cb.x, g0 + 14.0 * t0, h0 * cb.y)
			var a1 := _w(o, B, h1 * ca.x, g0 + 14.0 * t1, h1 * ca.y)
			var b1 := _w(o, B, h1 * cb.x, g0 + 14.0 * t1, h1 * cb.y)
			if band > 0:
				_cyl("iron", a0, b0, 0.06, 6)
			if (band + f) % 2 == 0:
				_cyl("iron", a0, b1, 0.055, 6)
			else:
				_cyl("iron", b0, a1, 0.055, 6)
	# 床・手すり・小屋
	var cp := _w(o, B, 0, topY - 0.1, 0)
	_box("iron", cp, Vector3(6.4, 0.2, 6.4), B)
	_col_box(cp, Vector3(6.4, 0.2, 6.4), B)
	for sx in [-1, 0, 1]:
		for sz in [-1, 0, 1]:
			if sx == 0 and sz == 0 or sx == -1:   # 走り出しの側（−x）は手すりを開ける
				continue
			var q := _w(o, B, 3.1 * sx, topY, 3.1 * sz)
			_cyl("iron", q, q + Vector3.UP * 1.1, 0.04, 6)
	for h in [0.55, 1.1]:
		for sd in [-1, 1]:
			_plank("iron", _w(o, B, -3.1, topY + h, 3.1 * sd), _w(o, B, 3.1, topY + h, 3.1 * sd), 0.06, 0.06)
		_plank("iron", _w(o, B, 3.1, topY + h, -3.1), _w(o, B, 3.1, topY + h, 3.1), 0.06, 0.06)
	var hc := _w(o, B, 1.6, topY + 0.9, 0)
	_box("iron", hc, Vector3(2.4, 1.8, 2.8), B)
	_box("snow", hc + Vector3.UP * 1.05, Vector3(2.8, 0.3, 3.2), B)
	_col_box(hc, Vector3(2.4, 1.8, 2.8), B)
	# 助走路: −up の向き（斜面の下り）へ 22 m、35° で下がる
	var ang := deg_to_rad(35.0)
	var d3 := Vector3(-up.x, 0, -up.y)
	var fwd := d3 * cos(ang) + Vector3.DOWN * sin(ang)
	var z3 := Vector3(side.x, 0, side.y)
	var S := _w(o, B, -3.2, topY, 0)
	var E := S + fwd * 22.0
	_plank("iron", S, E, 0.15, 3.0, -0.08)
	for sd in [-1, 1]:
		_plank("iron", S + z3 * 1.46 * sd, E + z3 * 1.46 * sd, 0.5, 0.08, 0.3)
	for s in [8.0, 16.0]:
		var P: Vector3 = S + fwd * s
		var under: float = P.y - 0.16
		for sd in [-1, 1]:
			var q: Vector3 = P + z3 * 1.3 * sd
			var gq := _gy(q, 0.3)
			var from := Vector3(q.x, gq - 0.4, q.z)
			var to := Vector3(q.x, under, q.z)
			if to.y > from.y + 0.5:
				_cyl("iron", from, to, 0.1, 8)
				_col_cyl(from, to, 0.12)
		_plank("iron", P - z3 * 1.4, P + z3 * 1.4, 0.12, 0.12, -0.14)


# ---- ⑤ 小さな台と審判の櫓 ---------------------------------------------------------------

func _small_jump() -> void:
	var o := Vector2(-134, -186)
	var d := -up
	var P0 := Vector3(o.x, 0, o.y)
	P0.y = _gy(P0, 1.0) + 4.2   # 斜面の上の端が高く、下の端（踏み切り）が低い
	var q := o + d * 8.0
	var P1 := Vector3(q.x, _gy(Vector3(q.x, 0, q.y), 1.0) + 1.0, q.y)
	_plank("iron", P0, P1, 0.2, 3.0)
	_plank("snow", P0, P1, 0.35, 3.3, 0.26)
	var z3 := Vector3(side.x, 0, side.y)
	for f in [0.3, 0.65, 1.0]:
		var P: Vector3 = P0.lerp(P1, f)
		for sd in [-1, 1]:
			var qq: Vector3 = P + z3 * 1.3 * sd
			var gq := _gy(qq, 0.3)
			if P.y - 0.1 > gq:
				_cyl("iron", Vector3(qq.x, gq - 0.4, qq.z), Vector3(qq.x, P.y - 0.1, qq.z), 0.1, 8)
		_plank("iron", P - z3 * 1.4 - Vector3.UP * 0.2, P + z3 * 1.4 - Vector3.UP * 0.2, 0.1, 0.1)
	var mid := P0.lerp(P1, 0.5)
	var bx := (P1 - P0).normalized()
	var bz := bx.cross(Vector3.UP).normalized()
	_col_box(mid, Vector3(P0.distance_to(P1), 0.3, 3.2), Basis(bx, bz.cross(bx), bz))


func _judge_tower(o: Vector2) -> void:
	var B := _frame(up)
	var g0 := -INF
	var gs := {}
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var g := _gy(_w(o, B, 1.1 * sx, 0, 1.1 * sz), 0.3)
			gs[Vector2i(sx, sz)] = g
			g0 = maxf(g0, g)
	var topY := g0 + 5.0
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var p0 := _w(o, B, 1.1 * sx, gs[Vector2i(sx, sz)] - 0.4, 1.1 * sz)
			var p1 := _w(o, B, 1.1 * sx, topY, 1.1 * sz)
			_cyl("iron", p0, p1, 0.07, 6)
	for sd in [-1, 1]:
		_plank("iron", _w(o, B, -1.1, g0 + 1.8, 1.1 * sd), _w(o, B, 1.1, g0 + 3.4, 1.1 * sd), 0.05, 0.05)
		_plank("iron", _w(o, B, -1.1, g0 + 3.4, 1.1 * sd), _w(o, B, 1.1, g0 + 1.8, 1.1 * sd), 0.05, 0.05)
	var fc := _w(o, B, 0, topY - 0.08, 0)
	_box("iron", fc, Vector3(2.2, 0.16, 2.2), B)
	var hc := _w(o, B, 0, topY + 0.7, 0)
	_box("iron", hc, Vector3(1.6, 1.4, 1.6), B)
	_box("snow", hc + Vector3.UP * 0.82, Vector3(1.9, 0.25, 1.9), B)
	var cc := _w(o, B, 0, g0 + 2.5, 0)
	_col_box(Vector3(cc.x, g0 + 2.5, cc.z), Vector3(2.2, 5.0, 2.2), B)


# ---- ⑩ 仕切り ------------------------------------------------------------------------------

## そりコース（2026-11-11 代表「ソリコースなくない？…ロッジから見える V 字の坂が特徴的なのに」）: 乗り場の南西、麓へ下りる道の南の、
## 北向きの斜面（写真 blog-6207 の奥に南の建物の屋根が写る）。主コース（南東向き）とこの斜面が、林の島のとがった先をはさんで V 字の谷になる。
## 初級コースの出口とのあいだを、オレンジのネットとピンクの旗のポールで仕切る（動画のコマ intro-35）。下の入口に、そりの絵の札（字は使わない）
func _divider() -> void:
	var pts := [Vector2(22, 58), Vector2(-10, 60), Vector2(-42, 63), Vector2(-72, 67)]
	for k in pts.size() - 1:
		_net(pts[k], pts[k + 1], ORANGE)
	_net(pts[pts.size() - 1], Vector2(-74, 92), ORANGE)   # 上の端を閉じる
	# ピンクの旗のポール: ネットに沿って 9 m おき
	for k in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var n := maxi(1, int(round(a.distance_to(b) / 9.0)))
		for i in n:
			var q := a.lerp(b, float(i) / n) + Vector2(0, -0.6)
			var g := _gy(Vector3(q.x, 0, q.y), 0.1)
			var base := Vector3(q.x, g - 0.3, q.y)
			_cyl("pole", base, base + Vector3.UP * 2.7, 0.035, 6)
			_box("pink", base + Vector3(0.28, 2.45, 0), Vector3(0.5, 0.3, 0.03))
	# 入口の札: 2 本の木の杭に白い板、赤いそりの絵（座面と滑り木）
	var o := Vector2(26, 66)
	var gy := _gy(Vector3(o.x, 0, o.y), 0.5)
	for dz in [-0.45, 0.45]:
		_cyl("iron", Vector3(o.x, gy - 0.4, o.y + dz), Vector3(o.x, gy + 1.9, o.y + dz), 0.05, 6)
	_box("plate", Vector3(o.x + 0.07, gy + 1.5, o.y), Vector3(0.05, 0.7, 1.1))
	_box("sledred", Vector3(o.x + 0.11, gy + 1.56, o.y), Vector3(0.03, 0.14, 0.62))
	_box("sledred", Vector3(o.x + 0.11, gy + 1.36, o.y), Vector3(0.03, 0.05, 0.78))
	for dz in [-0.2, 0.2]:
		_box("sledred", Vector3(o.x + 0.11, gy + 1.44, o.y + dz), Vector3(0.03, 0.14, 0.05))
	_box("sledred", Vector3(o.x + 0.11, gy + 1.42, o.y + 0.42), Vector3(0.03, 0.16, 0.05), Basis(Vector3.RIGHT, 0.6))
	_col_box(Vector3(o.x, gy + 0.9, o.y), Vector3(0.15, 2.0, 1.1))


# ---- ① 札・⑪ 石の看板 -------------------------------------------------------------------

func _plate() -> void:
	var p := -up * 5.0 + side * 3.0
	var g := _gy(Vector3(p.x, 0, p.y), 0.3)
	var B := _frame(up)
	_cyl("pole", Vector3(p.x, g - 0.3, p.y), Vector3(p.x, g + 1.5, p.y), 0.03, 6)
	_box("plate", Vector3(p.x, g + 1.2, p.y), Vector3(0.04, 0.6, 0.9), B)


func _stone_sign() -> void:
	var o := Vector2(88, 20)
	var g := _gy(Vector3(o.x, 0, o.y), 1.5)
	var b := Basis(Vector3.BACK, -deg_to_rad(20.0))
	var c := Vector3(o.x, g + 0.632 - 0.3, o.y)
	_box("stone", c, Vector3(0.4, 1.2, 3.0), b)
	_box("snow", c + b * Vector3(0, 0.68, 0), Vector3(0.55, 0.2, 3.1), b)
	_col_box(c, Vector3(0.4, 1.2, 3.0), b)
