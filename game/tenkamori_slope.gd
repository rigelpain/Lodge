extends Node3D
## 天下森のゲレンデの作り込み（2026-11-09）。代表「この動画を参考にゲレンデを作り込むことってできますか？」→ 見取り図（design/tenkamori/slope/01-slope-map.png）→「これで作って」
## 地形（林間コースの道と雪の壁、圧雪の筋の範囲）は ../tenkamori/bake_terrain.py。ここは雪の上に置く物:
##   - リフトの柱の足もとのマット（赤いフェルトの筒）と、柱の上の側（滑ってくる側）の赤いネット（見取り図 9）
##   - ナイターの照明の柱（リフト沿い、ゲレンデの側。見取り図 9）
##   - 林間コースの谷の側のオレンジのネット（曲がりと、ゲレンデへの合流。見取り図 5・7）
##   - 下の斜面の縁の、雪をかぶった小さな小屋（看板。見取り図 10）
##   - 降り場の柱の案内の札（見取り図 3）
## ネットは今までの世界の毛糸の安全ネット（props/net_span.glb）の毛糸を、オレンジ・赤に染め替えて使う

const Tenka := preload("res://tenkamori.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Lift := preload("res://tenkamori_lift.gd")

const NET := "res://props/net_span.glb"
const SPAN := 2.5
const ORANGE := Color(1.0, 0.45, 0.10)
const RED := Color(0.85, 0.14, 0.12)
const POLE := Color(0.56, 0.58, 0.60)
const PAD := Color(0.82, 0.16, 0.14)

var world: Node3D
var _mats := {}
var _st := {}


func _ready() -> void:
	var m: Dictionary = Tenka.map()
	var lift: Array = []
	for l in m.get("lifts", []):
		if l["kind"] == "chair_lift":
			lift = l["line"]
	var main_c: Array = []
	var rinkan: Array = []
	for p in m.get("pistes", []):
		if p["name"] == "天下森コース":
			main_c = p["line"]
		elif p["name"] == "夏虫沢林間コース":
			rinkan.append(p["line"])
	if rinkan.size() == 2:
		var a: Array = rinkan[0].duplicate()
		a.append_array(rinkan[1].slice(1))
		rinkan = [a]
	if not lift.is_empty():
		_towers(lift)
		_lights(lift, main_c)
		_top_sign(lift)
	if not rinkan.is_empty():
		_rinkan_nets(rinkan[0])
	if not main_c.is_empty():
		_sign_hut(main_c)
	for key in _st:
		var mi := MeshInstance3D.new()
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _mat(key)
		mi.name = "Slope_" + key
		add_child(mi)


func _mat(key: String) -> Material:
	var m: BaseMaterial3D
	match key:
		"pad": m = Look.felt(PAD, 1.6)
		"pole": m = Look.felt(POLE, 1.4)
		"lamp":
			m = Look.paper(Color(0.98, 0.95, 0.85))
			m.emission_enabled = true
			m.emission = Color(1.0, 0.92, 0.75)
			m.emission_energy_multiplier = 0.6
		"wood": m = Look.wood(Color(0.36, 0.25, 0.16))
		"snow": m = Look.snow()
		"plate": m = Look.paper(Color(0.95, 0.95, 0.92))
		"blue": m = Look.felt(Color(0.18, 0.36, 0.70), 1.4)
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


static func _y(x: float, z: float) -> float:
	return Tenka.lift(x, z)


## 線の上の、端から s (m) の所と向き
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


static func _length(line: Array) -> float:
	var acc := 0.0
	for k in line.size() - 1:
		acc += _v(line[k]).distance_to(_v(line[k + 1]))
	return acc


# ---- ネット ----------------------------------------------------------------------------

## 毛糸を col に染めたネットを、a から b まで（2.5 m ごとの区間を並べ、最後に杭）
func _net(a: Vector2, b: Vector2, col: Color) -> void:
	var L := a.distance_to(b)
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


# ---- リフトの柱 --------------------------------------------------------------------------

## 柱の足もとのマット（赤いフェルトの筒）と、柱の上の側（滑ってくる側）に V の字の赤いネット
func _towers(lift: Array) -> void:
	var dir := (_v(lift[lift.size() - 1]) - _v(lift[0])).normalized()   # 上る向き
	for i in range(1, lift.size() - 1):
		var p := _v(lift[i])
		var g := _y(p.x, p.y)
		Lift.cyl(_s("pad"), Vector3(p.x, g - 0.3, p.y), Vector3(p.x, g + 2.0, p.y), 0.6, 16)
		Lift.cyl(_s("pad"), Vector3(p.x, g + 2.0, p.y), Vector3(p.x, g + 2.06, p.y), 0.5, 16)
		if i % 2 == 0 or i == lift.size() - 2:
			var side := Vector2(-dir.y, dir.x)
			var tip := p + dir * 5.0
			_net(tip + side * 0.2, p + side * 3.0 + dir * 0.6, RED)
			_net(tip - side * 0.2, p - side * 3.0 + dir * 0.6, RED)


# ---- ナイターの照明 ------------------------------------------------------------------------

## リフト沿いの、ゲレンデの側に 70 m おき。灰の柱（高さ 9 m）の上に腕木と灯具 2 つ
func _lights(lift: Array, main_c: Array) -> void:
	var L := _length(lift)
	var s := 40.0
	while s < L - 40.0:
		var r := _along(lift, s)
		var p: Vector2 = r[0]
		var dir: Vector2 = r[1]
		var side := Vector2(-dir.y, dir.x)
		if not main_c.is_empty():   # ゲレンデ（天下森コース）のある側へ
			var q := _closest(main_c, p)
			if (q - p).dot(side) < 0.0:
				side = -side
		var at := p + side * 11.0
		var g := _y(at.x, at.y)
		Lift.cyl(_s("pole"), Vector3(at.x, g - 0.5, at.y), Vector3(at.x, g + 9.0, at.y), 0.14, 10)
		var arm := Vector3(dir.x, 0, dir.y)
		Lift.box(_s("pole"), Vector3(at.x, g + 9.0, at.y), Vector3(1.6, 0.12, 0.12), Basis(Vector3.UP, -atan2(dir.y, dir.x)))
		for k in [-0.6, 0.6]:
			var c: Vector3 = Vector3(at.x, g + 8.85, at.y) + arm * k
			Lift.box(_s("lamp"), c, Vector3(0.45, 0.22, 0.35), Basis(Vector3.UP, -atan2(dir.y, dir.x)))
		s += 70.0


static func _closest(line: Array, p: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for k in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, _v(line[k]), _v(line[k + 1]))
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return best


# ---- 林間コースのネット ----------------------------------------------------------------------

## 谷の側（低い側）の縁に沿ってオレンジのネット: 曲がり（全長の 28〜40%）と、ゲレンデへの合流の手前（80〜92%）
func _rinkan_nets(line: Array) -> void:
	var L := _length(line)
	for rng in [Vector2(0.28, 0.40), Vector2(0.80, 0.92)]:
		var pts: Array[Vector2] = []
		var s: float = L * rng.x
		while s <= L * rng.y:
			var r := _along(line, s)
			var p: Vector2 = r[0]
			var dir: Vector2 = r[1]
			var side := Vector2(-dir.y, dir.x)
			var a := p + side * 6.0
			var b := p - side * 6.0
			var low := a if _y(a.x, a.y) < _y(b.x, b.y) else b
			pts.append(p + (low - p).normalized() * 5.6)   # 道の縁（幅 9 m の半分）の少し外、雪の壁の手前
			s += SPAN * 2.0
		for k in pts.size() - 1:
			_net(pts[k], pts[k + 1], ORANGE)


# ---- 小屋と札 ------------------------------------------------------------------------------

## 下の斜面の縁の、雪をかぶった小さな板の小屋（看板の小屋）
func _sign_hut(main_c: Array) -> void:
	var L := _length(main_c)
	var r := _along(main_c, L * 0.8)
	var p: Vector2 = r[0]
	var dir: Vector2 = r[1]
	var at := p + Vector2(-dir.y, dir.x) * 16.0
	var g: float = world.foot_y(at.x, at.y, 1.0)
	var b := Basis(Vector3.UP, -atan2(dir.y, dir.x))
	Lift.box(_s("wood"), Vector3(at.x, g + 1.0, at.y), Vector3(1.4, 2.0, 1.2), b)
	Lift.box(_s("snow"), Vector3(at.x, g + 2.15, at.y), Vector3(1.8, 0.35, 1.6), b)
	Lift.box(_s("plate"), Vector3(at.x, g + 1.3, at.y) + b * Vector3(0, 0, 0.62), Vector3(1.0, 0.7, 0.04), b)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.4, 2.0, 1.2)
	cs.shape = sh
	cs.transform = Transform3D(b, Vector3(at.x, g + 1.0, at.y))
	var body := StaticBody3D.new()
	body.add_child(cs)
	add_child(body)


## 降り場の手前の柱に、青い縁の白い案内の札
func _top_sign(lift: Array) -> void:
	var p := _v(lift[lift.size() - 2])
	var g := _y(p.x, p.y)
	var dir := (_v(lift[lift.size() - 1]) - p).normalized()
	var b := Basis(Vector3.UP, -atan2(dir.y, dir.x) + PI / 2)
	var c := Vector3(p.x, g + 3.0, p.y) - Vector3(dir.x, 0, dir.y) * 0.35
	Lift.box(_s("blue"), c, Vector3(0.8, 0.9, 0.04), b)
	Lift.box(_s("plate"), c - Vector3(dir.x, 0, dir.y) * 0.03, Vector3(0.66, 0.76, 0.04), b)
