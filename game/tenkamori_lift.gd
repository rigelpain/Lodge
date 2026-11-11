extends Node3D
## 天下森の第一ペアリフト（2026-11-09）。2026-11-09 代表「リフトって作れるの？」
## 線は OpenStreetMap の線（tenkamori/map.json の lifts。点が 14 個: 乗り場・柱 12 本・降り場）。787 m、高さの差 139 m。
## 形は PV の乗り場の絵から: 薄緑の鉄の骨組みに横倒しの大きな滑車、その上の床と手すりと黒い機械小屋、脇に木の小屋。
## 柱は灰の鉄の筒に腕木と滑車。椅子は 2 人掛けで、索に吊られて回り続ける。
## 乗る（2026-11-09 代表「リフトに乗れるようにしてほしい」）: 乗り場の乗る所（board_point）で F。次に来る椅子を待って座り、降り場で降ろされる（player.gd の lift_*）。
## 自分のソリがそばにあれば、椅子の下に吊って一緒に上げ、降り場の脇に置く（carry。ソリの物理はホストの画面が動かすので、つなぐ側はホストに頼む）。
## 椅子の位置は時計（世界の時刻）から決めるので、どの画面でも同じ所にある。
## 素材は手芸の世界に合わせてフェルト（look.gd）。当たりは柱と乗り場の柱だけ（ソリがぶつかる）

const Look := preload("res://look.gd")
const Tenka := preload("res://tenkamori.gd")

const GAUGE := 2.3          # 索のまんなかから、上りと下りの索までの横の幅 (m)
const HEAD := 8.6           # 柱の腕木の、地面からの高さ (m)
const WHEEL_Y := 2.9        # 乗り場・降り場の滑車の、床からの高さ (m)。椅子の座面が床から SEAT_UP になる高さ（索 − 吊り）
const SAG := 0.012          # 柱と柱のあいだの索のたるみ（あいだの長さに掛ける）
const DROP := 2.45          # 索から椅子の座面までの吊り (m)
const SPEED := 2.0          # 索の速さ (m/s)
const SPACING := 14.0       # 椅子の間 (m)
const SEAT_UP := 0.45        # 乗り場・降り場で、椅子の座面が床から上にある高さ (m)
const SEAT_LOCAL := [Vector3(0.22, -DROP + 0.05, -0.33), Vector3(0.22, -DROP + 0.05, 0.33)]   # 2 人の座面（椅子の座標。x が進む向き）
const BOARD_S := 1.5         # 乗る所: 乗り場の滑車を回りきってから索に沿った距離 (m)
const UNLOAD_BACK := 3.0     # 降りる所: 上りの索の終わりの手前 (m)
const BOARD_REACH := 2.6     # 乗る所からこれだけ近ければ F で乗れる (m。水平)
const SLED_HANG := 1.2       # 吊ったソリの、座面からの下がり (m)

const GREEN := Color(0.55, 0.72, 0.62)    # 乗り場の骨組み（PV の薄緑）
const STEEL := Color(0.46, 0.48, 0.51)    # 柱
const DARK := Color(0.17, 0.17, 0.18)     # 機械小屋・滑車・椅子の骨
const SEAT := Color(0.24, 0.30, 0.44)     # 椅子の座布団（藍）
const HUT := Color(0.33, 0.24, 0.17)      # 木の小屋

## 場所ごとの形と色（2026-11-11 旭ヶ丘: 動画のコマから。赤茶の鉄骨の乗り場と柱・灰の腕木、椅子は灰のパイプに黒い座面で前の手すりなし、
## 乗り場の上に機械小屋は無く、板張りの運転室はゲレンデの側（上りの索の側）にある）
const STYLES := {
	"tenkamori": {"frame": GREEN, "tower": STEEL, "chair": DARK, "seat": SEAT, "hut": HUT, "machine": true, "hut_side": -1.0, "bar": true},
	"asahigaoka": {"frame": Color(0.27, 0.15, 0.12), "tower": Color(0.26, 0.14, 0.11), "chair": Color(0.60, 0.62, 0.64), "seat": Color(0.10, 0.10, 0.11),
		"hut": Color(0.20, 0.13, 0.09), "machine": false, "hut_side": 1.0, "bar": false},
}
var style: Dictionary = STYLES["tenkamori"]

var _loop := PackedVector3Array()   # 索の輪（2 m おき）。上りの索を乗り場から降り場へ、回って下りの索を戻る
var _len := 0.0
var _cum := PackedFloat32Array()
var _chairs: MultiMeshInstance3D
var _s := 0.0
var _up_len := 0.0               # 上りの索の長さ（輪の 0 からここまでが上り）
var _side := Vector3.ZERO        # 上りの索の側（水平）
var _carried := {}               # 吊っているソリ → [椅子, 2 人のどちら]（ホストか一人の画面）


func _ready() -> void:
	var lifts: Array = Tenka.map().get("lifts", [])
	if lifts.is_empty():
		return
	style = STYLES.get(Tenka.site, STYLES["tenkamori"])
	var line: Array = lifts[0]["line"]
	var pads: Dictionary = Tenka.map().get("pads", {})
	var pts: Array[Vector2] = []
	for p in line:
		pts.append(Vector2(p[0], p[1]))
	var d := (pts[pts.size() - 1] - pts[0]).normalized()
	var side := Vector2(-d.y, d.x)   # 上りの索の側（乗り場から降り場を見て左）
	var meshes := {}   # 色 → SurfaceTool
	var body := StaticBody3D.new()
	body.name = "LiftBody"
	add_child(body)
	# 支え: 乗り場・柱・降り場の、索の高さ
	var heads: Array[Vector3] = []
	for i in pts.size():
		var p := pts[i]
		if i == 0 or i == pts.size() - 1:
			var key := "lift_bottom" if i == 0 else "lift_top"
			var fy: float = float(pads[key]["y"]) if pads.has(key) else Tenka.lift(p.x, p.y)
			heads.append(Vector3(p.x, fy + WHEEL_Y, p.y))
			_station(meshes, body, Vector3(p.x, fy, p.y), d, side, i == 0)
		else:
			var gy := Tenka.lift(p.x, p.y)
			heads.append(Vector3(p.x, gy + HEAD, p.y))
			_tower(meshes, body, Vector3(p.x, gy, p.y), d, side)
	# 索の輪
	var up := _span_points(heads, side * GAUGE)
	var down := _span_points(heads, -side * GAUGE)
	down.reverse()
	_loop = up
	_side = Vector3(side.x, 0, side.y)
	for k in up.size() - 1:
		_up_len += up[k].distance_to(up[k + 1])
	_turn(_loop, heads[heads.size() - 1], side, d, true)
	_loop.append_array(down)
	_turn(_loop, heads[0], side, d, false)
	_cum.resize(_loop.size() + 1)
	_cum[0] = 0.0
	for k in _loop.size():
		_len += _loop[k].distance_to(_loop[(k + 1) % _loop.size()])
		_cum[k + 1] = _len
	_cable(meshes, up)
	_cable(meshes, down)
	for col in meshes:
		var st: SurfaceTool = meshes[col]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(col)
		mi.name = "LiftParts"
		add_child(mi)
	_make_chairs()


func _mat(col: Color) -> Material:
	return _felt(col, 2.0 if col == DARK else 1.4)


## 形は面の向きをそろえていないので、裏も描く
static func _felt(col: Color, fiber: float) -> Material:
	var m := Look.felt(col, fiber)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---- 形 ----------------------------------------------------------------------------

static func _st(meshes: Dictionary, col: Color) -> SurfaceTool:
	if not meshes.has(col):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		meshes[col] = st
	return meshes[col]


## 箱（まんなか c、向き b の各軸に大きさ size）
static func box(st: SurfaceTool, c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := n * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		var wn := (b * n).normalized()
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(wn)
			st.add_vertex(c + b * q[k])


## 筒（p0 から p1、半径 r）
static func cyl(st: SurfaceTool, p0: Vector3, p1: Vector3, r: float, seg := 10) -> void:
	var ax := (p1 - p0).normalized()
	var a := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := ax.cross(a)
	for k in seg:
		var t0 := TAU * k / seg
		var t1 := TAU * (k + 1) / seg
		var n0 := a * cos(t0) + b * sin(t0)
		var n1 := a * cos(t1) + b * sin(t1)
		for v in [[p0, n0], [p1, n0], [p1, n1], [p0, n0], [p1, n1], [p0, n1]]:
			st.set_normal(v[1])
			st.add_vertex(v[0] + v[1] * r)
	for cap in [[p0, -ax], [p1, ax]]:
		for k in seg:
			var t0 := TAU * k / seg
			var t1 := TAU * (k + 1) / seg
			for v in [cap[0], cap[0] + (a * cos(t0) + b * sin(t0)) * r, cap[0] + (a * cos(t1) + b * sin(t1)) * r]:
				st.set_normal(cap[1])
				st.add_vertex(v)


static func _basis(d: Vector2) -> Basis:
	# x = 索の向き（乗り場から降り場）、y = 上、z = 横
	var fx := Vector3(d.x, 0, d.y)
	var fz := fx.cross(Vector3.UP)
	return Basis(fx, Vector3.UP, fz)


## 柱: 灰の鉄の筒、てっぺんに横の腕木、腕木の両端に滑車の列
func _tower(meshes: Dictionary, body: StaticBody3D, g: Vector3, d: Vector2, side: Vector2) -> void:
	var st := _st(meshes, STEEL)
	var top := g + Vector3(0, HEAD + 0.4, 0)
	cyl(_st(meshes, style.tower), g + Vector3(0, -1.0, 0), top, 0.28)
	var b := _basis(d)
	box(st, top + Vector3(0, 0.15, 0), Vector3(0.35, 0.35, GAUGE * 2.0 + 1.2), b)
	var dk := _st(meshes, DARK)
	for s in [-1.0, 1.0]:
		var at: Vector3 = g + Vector3(side.x, 0, side.y) * GAUGE * s + Vector3(0, HEAD + 0.05, 0)
		box(dk, at, Vector3(2.4, 0.3, 0.22), b)
		for k in 4:
			cyl(dk, at + b.x * (-0.9 + 0.6 * k) + b.z * -0.14, at + b.x * (-0.9 + 0.6 * k) + b.z * 0.14, 0.17, 8)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.35
	sh.height = HEAD + 1.0
	cs.shape = sh
	cs.position = g + Vector3(0, (HEAD + 1.0) * 0.5 - 0.5, 0)
	body.add_child(cs)


## 乗り場・降り場: 薄緑の骨組みに横倒しの大きな滑車、上に床と手すりと黒い機械小屋。乗り場には木の小屋
func _station(meshes: Dictionary, body: StaticBody3D, f: Vector3, d: Vector2, side: Vector2, bottom: bool) -> void:
	var b := _basis(d)
	var gr := _st(meshes, style.frame)
	var dk := _st(meshes, DARK)
	var back := -1.0 if bottom else 1.0   # 滑車の骨組みは、索の来る向きと逆へ張り出す
	var c := f + Vector3(0, WHEEL_Y, 0)
	# 柱 2 本（滑車の奥）
	for s in [-1.0, 1.0]:
		var at: Vector3 = f + b.x * (back * 1.8) + b.z * (s * 1.2)
		box(gr, at + Vector3(0, WHEEL_Y * 0.5, 0), Vector3(0.9, WHEEL_Y + 0.6, 0.9), b)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.7, WHEEL_Y + 0.6, 0.7)
		cs.shape = sh
		cs.transform = Transform3D(b, at + Vector3(0, WHEEL_Y * 0.5, 0))
		body.add_child(cs)
	# 腕: 柱から滑車の軸へ
	box(gr, c + b.x * (back * 0.9) + Vector3(0, 0.55, 0), Vector3(2.6, 0.5, 1.0), b)
	# 滑車（横倒しの円盤）と、その縁の索の溝
	cyl(gr, c + Vector3(0, -0.12, 0), c + Vector3(0, 0.12, 0), GAUGE + 0.15, 28)
	cyl(dk, c + Vector3(0, -0.2, 0), c + Vector3(0, 0.2, 0), 0.5, 12)
	# 床と手すりと機械小屋（乗り場は PV のとおり大きく。降り場は小さな屋根）
	var deck := c + Vector3(0, 0.95, 0) + b.x * (back * 1.2)
	box(gr, deck, Vector3(7.4, 0.35, 7.0), b)
	box(gr, deck + Vector3(0, -0.5, 0), Vector3(7.0, 0.7, 0.5), b)   # 床の下の梁（滑車の上を横切る）
	for s in [-1.0, 1.0]:
		box(gr, deck + b.z * (s * 3.2) + Vector3(0, -0.5, 0), Vector3(7.0, 0.7, 0.4), b)
	if bottom:
		for s in [-1.0, 1.0]:
			box(_st(meshes, STEEL), deck + b.z * (s * 3.4) + Vector3(0, 0.6, 0), Vector3(7.4, 0.07, 0.07), b)
			box(_st(meshes, STEEL), deck + b.z * (s * 3.4) + Vector3(0, 1.15, 0), Vector3(7.4, 0.07, 0.07), b)
			for k in 7:
				box(_st(meshes, STEEL), deck + b.z * (s * 3.4) + b.x * (-3.6 + 1.2 * k) + Vector3(0, 0.6, 0), Vector3(0.06, 1.15, 0.06), b)
		if style.machine:
			box(dk, deck + b.x * (back * 1.4) + Vector3(0, 1.7, 0), Vector3(3.6, 3.0, 4.6), b)
			box(gr, deck + b.x * (back * 1.4) + Vector3(0, 3.3, 0), Vector3(3.9, 0.15, 4.9), b)
			box(_st(meshes, STEEL), deck + b.x * (back * 1.4 - 1.81) + Vector3(0, 2.0, 0), Vector3(0.04, 1.4, 3.8), b)   # 窓の帯
		# 木の小屋（係の人の小屋）。乗り場の脇、索の外
		var hs: float = style.hut_side
		var hut := f + b.z * (hs * (GAUGE + 4.2)) + b.x * 1.5
		box(_st(meshes, style.hut), hut + Vector3(0, 1.2, 0), Vector3(2.4, 2.4, 2.2), b)
		box(_st(meshes, DARK), hut + Vector3(0, 2.5, 0), Vector3(2.9, 0.25, 2.7), b)
		if not style.machine:   # 旭ヶ丘の運転室: 索の側と斜面の上の側に横長の窓、屋根に雪
			box(_st(meshes, Color(0.72, 0.84, 0.90)), hut + b.z * (-hs * 1.11) + Vector3(0, 1.5, 0), Vector3(1.7, 0.7, 0.04), b)
			box(_st(meshes, Color(0.72, 0.84, 0.90)), hut + b.x * 1.21 + Vector3(0, 1.5, 0), Vector3(0.04, 0.7, 1.5), b)
			box(_st(meshes, Color(0.97, 0.98, 1.0)), hut + Vector3(0, 2.8, 0), Vector3(2.7, 0.35, 2.5), b)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(2.4, 2.4, 2.2)
		cs.shape = sh
		cs.transform = Transform3D(b, hut + Vector3(0, 1.2, 0))
		body.add_child(cs)
	elif style.machine:
		box(dk, deck + Vector3(0, 0.9, 0), Vector3(2.0, 1.6, 2.4), b)
	else:   # 旭ヶ丘の降り場: 脇に小さな木の小屋
		var hut2 := f + b.z * (float(style.hut_side) * (GAUGE + 3.6)) - b.x * 2.0
		box(_st(meshes, style.hut), hut2 + Vector3(0, 1.1, 0), Vector3(2.0, 2.2, 1.8), b)
		box(_st(meshes, Color(0.97, 0.98, 1.0)), hut2 + Vector3(0, 2.4, 0), Vector3(2.4, 0.4, 2.2), b)
		var cs2 := CollisionShape3D.new()
		var sh2 := BoxShape3D.new()
		sh2.size = Vector3(2.0, 2.2, 1.8)
		cs2.shape = sh2
		cs2.transform = Transform3D(b, hut2 + Vector3(0, 1.1, 0))
		body.add_child(cs2)


## 支えの点を、横へ off ずらして、あいだをたるませながら 2 m おきの点にする
static func _span_points(heads: Array[Vector3], off: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array()
	var o := Vector3(off.x, 0, off.y)
	for i in heads.size() - 1:
		var a := heads[i] + o
		var b := heads[i + 1] + o
		var L := a.distance_to(b)
		var n := maxi(2, int(L / 2.0))
		for k in n:
			var t := float(k) / n
			var p := a.lerp(b, t)
			p.y -= 4.0 * SAG * L * t * (1.0 - t)
			out.append(p)
	out.append(heads[heads.size() - 1] + o)
	return out


## 滑車のまわりを半周（top: 降り場で上りから下りへ、でなければ乗り場で下りから上りへ）
static func _turn(loop: PackedVector3Array, c: Vector3, side: Vector2, d: Vector2, top: bool) -> void:
	var s := Vector3(side.x, 0, side.y)
	var f := Vector3(d.x, 0, d.y) * (1.0 if top else -1.0)
	var from := s if top else -s
	for k in range(1, 12):
		var a := PI * k / 12.0
		var dir := from * cos(a) + f * sin(a)
		loop.append(c + dir * GAUGE)


func _cable(meshes: Dictionary, pts: PackedVector3Array) -> void:
	var st := _st(meshes, DARK)
	for k in range(0, pts.size() - 1):
		cyl(st, pts[k], pts[k + 1], 0.035, 4)


# ---- 椅子 --------------------------------------------------------------------------

## 2 人掛けの椅子: 握り・吊りの棒・座面・背もたれ・前の手すり。x が進む向き、原点が索の握り
func _make_chairs() -> void:
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pad := SurfaceTool.new()
	pad.begin(Mesh.PRIMITIVE_TRIANGLES)
	box(frame, Vector3(0, -0.1, 0), Vector3(0.5, 0.22, 0.18))                    # 握り
	cyl(frame, Vector3(0, -0.1, 0), Vector3(0, -DROP + 0.5, 0), 0.04, 6)          # 吊りの棒
	cyl(frame, Vector3(0, -DROP + 0.5, -0.65), Vector3(0, -DROP + 0.5, 0.65), 0.04, 6)   # 肩の横棒
	for s in [-1.0, 1.0]:
		cyl(frame, Vector3(0, -DROP + 0.5, s * 0.65), Vector3(0.0, -DROP - 0.05, s * 0.65), 0.035, 6)
		cyl(frame, Vector3(0.0, -DROP - 0.05, s * 0.65), Vector3(0.45, -DROP - 0.05, s * 0.65), 0.035, 6)
	if style.bar:
		cyl(frame, Vector3(0.75, -DROP + 0.35, -0.65), Vector3(0.75, -DROP + 0.35, 0.65), 0.03, 6)   # 前の手すり
	box(pad, Vector3(0.22, -DROP, 0), Vector3(0.5, 0.08, 1.3))                     # 座面
	box(pad, Vector3(-0.04, -DROP + 0.3, 0), Vector3(0.07, 0.5, 1.3), Basis(Vector3.BACK, -0.15))   # 背もたれ
	var mesh := frame.commit()
	pad.commit(mesh)
	mesh.surface_set_material(0, _felt(style.chair, 2.0))
	mesh.surface_set_material(1, _felt(style.seat, 1.4))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = int(_len / SPACING)
	_chairs = MultiMeshInstance3D.new()
	_chairs.name = "LiftChairs"
	_chairs.multimesh = mm
	add_child(_chairs)
	_place_chairs()


## 輪の上の s (m) の所: 位置と進む向き
func _at(s: float) -> Array:
	s = fposmod(s, _len)
	var lo := 0
	var hi := _loop.size()
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var a := _loop[lo]
	var b := _loop[(lo + 1) % _loop.size()]
	var seg := _cum[lo + 1] - _cum[lo]
	var t := (s - _cum[lo]) / maxf(seg, 0.001)
	return [a.lerp(b, t), b - a]


func _place_chairs() -> void:
	if _chairs == null:
		return
	var mm := _chairs.multimesh
	for i in mm.instance_count:
		var r := _at(_s + i * (_len / mm.instance_count))
		var p: Vector3 = r[0]
		var dir: Vector3 = r[1]
		dir.y = 0.0
		if dir.length() < 0.001:
			dir = Vector3.RIGHT
		dir = dir.normalized()
		var b := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
		mm.set_instance_transform(i, Transform3D(b, p))


func _process(_dt: float) -> void:
	if _len <= 0.0:
		return
	_s = fposmod(SPEED * Time.get_unix_time_from_system(), _len)   # どの画面でも同じ時刻なら同じ所
	_place_chairs()
	_carry_step()


# ---- 乗る ----------------------------------------------------------------------------

func chairs() -> int:
	return _chairs.multimesh.instance_count if _chairs else 0


## 椅子 i の、輪の上の位置 (m)
func chair_s(i: int) -> float:
	return fposmod(_s + i * (_len / chairs()), _len)


## 椅子 i の姿（原点が索の握り、x が進む向き）
func chair_xform(i: int) -> Transform3D:
	var r := _at(chair_s(i))
	var dir: Vector3 = r[1]
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.RIGHT
	return Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), r[0])


## 椅子 i の座面 side（0 / 1）の所（世界）
func seat_point(i: int, side: int) -> Vector3:
	return chair_xform(i) * (SEAT_LOCAL[side] as Vector3)


## 椅子の進む向き（水平）
func chair_dir(i: int) -> Vector3:
	return chair_xform(i).basis.x


## 乗る所（座面の真下の地面。2 人のどちらか）
func board_point(side := 0) -> Vector3:
	var p: Vector3 = (_at(BOARD_S)[0] as Vector3)
	var b := Transform3D(Basis((_at(BOARD_S)[1] as Vector3).normalized(), Vector3.UP, (_at(BOARD_S)[1] as Vector3).normalized().cross(Vector3.UP)), p)
	var sp: Vector3 = b * (SEAT_LOCAL[side] as Vector3)
	return Vector3(sp.x, sp.y - SEAT_UP, sp.z)


## (x, z) から乗る所までの水平の距離
func board_dist(at: Vector3) -> float:
	var b := board_point(0).lerp(board_point(1), 0.5)
	return Vector2(at.x - b.x, at.z - b.z).length()


## 乗る所へ次に来る椅子（乗る所までの残りが、間の半分より大きいもの。すぐ前を過ぎた椅子には乗らない）
func next_chair() -> int:
	var best := -1
	var gap := INF
	for i in chairs():
		var d := fposmod(BOARD_S - chair_s(i), _len)
		if d > 0.3 and d < gap:
			gap = d
			best = i
	return best


## 椅子 i が乗る所へ着くまでの距離 (m。過ぎたら負)
func to_board(i: int) -> float:
	var d := fposmod(BOARD_S - chair_s(i), _len)
	return d if d < _len * 0.5 else d - _len


## 椅子 i が降りる所を過ぎたか（上りの索の終わりの手前）
func past_unload(i: int) -> bool:
	var s := chair_s(i)
	return s > _up_len - UNLOAD_BACK and s < _up_len + 20.0


## 降りて立つ所: 降りる所の座面の真下から、索の外へ少し出た地面
func unload_point(side: int) -> Vector3:
	var s := _up_len - UNLOAD_BACK
	var r := _at(s)
	var dir: Vector3 = r[1]
	dir.y = 0.0
	dir = dir.normalized()
	var p: Vector3 = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), r[0]) * (SEAT_LOCAL[side] as Vector3)
	p += dir * 1.5 + _side * (1.2 if side == 0 else 0.6)
	return Vector3(p.x, Tenka.lift(p.x, p.z), p.z)


# ---- ソリを吊って上げる ------------------------------------------------------------------

## ソリを椅子 i の下に吊る。ホストか一人の画面で（つなぐ側は player.gd が net.up("lift") で頼む）
func carry(sled: RigidBody3D, i: int, side: int) -> void:
	if sled == null or not is_instance_valid(sled) or _carried.has(sled):
		return
	sled.let_everyone_go()
	sled.unpeg(false)
	sled.freeze = true
	sled.parked = true
	_carried[sled] = [i, side]


## 吊っているソリを、いまの所で放す（乗っている人が途中で飛び降りた。ソリはそのまま落ちる）
func drop(sled: RigidBody3D) -> void:
	if sled == null or not _carried.has(sled):
		return
	var c: Array = _carried[sled]
	_carried.erase(sled)
	sled.freeze = false
	sled.parked = false
	sled.linear_velocity = chair_dir(c[0]) * SPEED
	sled.angular_velocity = Vector3.ZERO


func _carry_step() -> void:
	for sled in _carried.keys():
		if not is_instance_valid(sled):
			_carried.erase(sled)
			continue
		var c: Array = _carried[sled]
		var i: int = c[0]
		var side: int = c[1]
		if past_unload(i):
			# 降り場の脇の雪へ置く
			_carried.erase(sled)
			var at := unload_point(side) + _side * 2.5 + chair_dir(i) * 2.0
			sled.freeze = false
			sled.reset_to(Vector3(at.x, Tenka.lift(at.x, at.z) + 0.6, at.z))
			sled.reset_physics_interpolation()
			continue
		var xf := chair_xform(i)
		var p: Vector3 = xf * ((SEAT_LOCAL[side] as Vector3) + Vector3(-0.1, -SLED_HANG, 0.0))
		# ソリは進む向きに長く、前を上へ少し起こして吊る
		var b := Basis(xf.basis.x.cross(Vector3.UP).normalized(), Vector3.UP, -xf.basis.x).rotated(xf.basis.z.normalized(), 0.35)
		sled.global_transform = Transform3D(b.orthonormalized(), p)
		sled.linear_velocity = xf.basis.x * SPEED   # 通信で、動いているソリとして多めに送られるように
		sled.angular_velocity = Vector3.ZERO
