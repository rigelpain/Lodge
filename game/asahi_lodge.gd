extends Node3D
## 旭ヶ丘スキー場の休憩所「雪ん子館」（2026-11-11）。代表「これで作って」（図面 design/asahigaoka/lodge/01-plans.png）。
## 寸法は ../asahigaoka/lodge_dims.py。ここの定数はその写し。変えるときは両方を直す。
## 手本: YouTube の動画のコマ（~/research/asahigaoka/sources/video/ の tokyu-133・rdj-190・tokyu-60・intro-5・intro-85・intro-120）と国土地理院の空中写真。
##
## 組み立て（平屋）:
##   東西に走る棟から、北へ短く急に、南へ長くゆるく下る大きな屋根（縁は白い板、上に厚い雪）。軒先に灰の細い鉄の柱、柱から壁へ木の梁
##   北の 6.5 m は壁が無く柱と屋根だけ。その南に低い灰の棟（中には入れない）。その南が休憩所の大きな一部屋
##   ゲレンデの側（西）が正面: 下 3 m が灰のパネル、上が縦張りの木、南の端は背の高いガラス。白い庇の下に入口（開いたまま）と券売所の小窓
##   西と南に木のデッキと手すり。南の壁は壁いっぱいの窓。駐車場の側（東）にも庇と入口（場所は推しはかり）
## 座標（この節点の中）: x = v（東へ。屋根の西の縁が 0）、z = u（南へ。屋根の北の縁が 0）、y = 上（ならした地面が 0）。
## 置き場所は空中写真から: 屋根の北西の角が (101, 10)。向きは東西南北にそろえる

const Look := preload("res://look.gd")
const Lift := preload("res://tenkamori_lift.gd")   # 箱と筒の形の部品
const Lodge := preload("res://lodge/lodge.gd")       # 今までのロッジの素材（板・ガラス・鉄）を流用する
const Tenka := preload("res://tenkamori.gd")

const AT := Vector2(101.0, 10.0)
const ROOF_U := 34.0
const ROOF_V := 15.5
const RIDGE_U := 14.0
const RIDGE_H := 8.4
const EAVE_N_H := 3.2
const EAVE_S_H := 4.2
const ROOF_T := 0.35
const SNOW_T := 0.55              # 屋根の上の雪の厚み（コマではもっと厚い所もある）
const WV := 2.6                   # 西の壁の v
const EV := 13.9                  # 東の壁の v
const PORCH_U := 6.5
const LOW_U := Vector2(6.5, 13.5)
const LOW_H := 3.0
const HALL_U := Vector2(13.5, 31.8)
const PANEL_H := 3.0
const FL := 0.6                   # 床とデッキの高さ
const WALL_T := 0.24
const DOOR_U := Vector2(14.6, 17.0)
const DOOR_H := 2.2               # 入口の高さ（床から）
const CANOPY_U := Vector2(13.2, 18.4)
const CANOPY_OUT := 3.2
const CANOPY_H := 2.9
const BAND_U := Vector2(22.5, 28.0)
const TALL_U := Vector2(28.0, 31.8)
const SILL := 1.0                 # 窓の下端（床から）
const BAND_TOP := 2.2
const SOUTH_TOP := 3.4
const EAST_WIN_U := Vector2(16.5, 27.6)
const EAST_DOOR_U := Vector2(28.2, 30.2)
const COLS_W := [0.4, 4.4, 8.4, 12.4, 16.4, 20.4, 24.4, 28.4, 33.6]
const COLS_E := [0.4, 4.4, 8.4, 12.4, 20.4, 26.6, 33.6]
const COL_R := 0.09

const WOOD := Color(0.72, 0.46, 0.23)     # 縦張りの木（橙がかった茶）
const PANEL := Color(0.27, 0.28, 0.30)    # 灰の横長パネル
const BEAM := Color(0.54, 0.35, 0.19)
const DECK := Color(0.50, 0.38, 0.27)
const FLOOR := Color(0.50, 0.50, 0.51)    # 中の床（灰のコンクリート）
const INNER := Color(0.78, 0.60, 0.40)    # 中の壁と天井の木

var world: Node3D
var _st := {}
var _body: StaticBody3D


func _ready() -> void:
	var pads: Dictionary = Tenka.map().get("pads", {})
	position = Vector3(AT.x, float(pads.get("lodge", {}).get("y", Tenka.lift(AT.x + 8.0, AT.y + 17.0))), AT.y)
	_body = StaticBody3D.new()
	_body.name = "LodgeBody"
	add_child(_body)
	_floors()
	_walls()
	_roof()
	_columns()
	_canopies()
	_inside()
	for key in _st:
		var mi := MeshInstance3D.new()
		mi.name = "Lodge_" + key
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _material(key)
		add_child(mi)
	for p in [Vector3(8.2, 4.2, 18.0), Vector3(8.2, 3.8, 24.0), Vector3(8.2, 3.4, 29.0)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.84, 0.64)
		l.light_energy = 1.1
		l.omni_range = 9.0
		l.position = p
		add_child(l)


## 屋根の上の面の高さ（u = 南への距離）
static func roof_h(u: float) -> float:
	if u <= RIDGE_U:
		return lerpf(EAVE_N_H, RIDGE_H, u / RIDGE_U)
	return lerpf(RIDGE_H, EAVE_S_H, (u - RIDGE_U) / (ROOF_U - RIDGE_U))


## 屋根の裏の高さ
static func under(u: float) -> float:
	return roof_h(u) - ROOF_T - 0.05


func _material(key: String) -> Material:
	var m: BaseMaterial3D
	match key:
		"wood": m = Lodge._planks(WOOD)
		"inner": m = Lodge._planks(INNER, true)
		"beam": m = Look.wood(BEAM)
		"panel": m = Look.felt(PANEL, 1.2)
		"deck": m = Lodge._planks(DECK)
		"floor": m = Look.felt(FLOOR, 2.0)
		"fascia": m = Look.paper(Color(0.95, 0.95, 0.93))
		"canopy": m = Look.paper(Color(0.96, 0.96, 0.95))
		"snow":   # 地面の雪の素材は、天下森・旭ヶ丘では林の色を重ねる next_pass が付く（tenkamori.gd）。屋根の雪には要らないので写しを使う
			m = Look.snow().duplicate()
			m.next_pass = null
		"steel": m = Look.felt(Color(0.48, 0.49, 0.51), 1.2)
		"black": m = Look.felt(Color(0.12, 0.12, 0.13), 1.2)
		"blue": m = Look.felt(Color(0.16, 0.42, 0.78), 1.6)
		"red": m = Look.felt(Color(0.82, 0.14, 0.12), 1.6)
		"table": m = Lodge._planks(Color(0.80, 0.78, 0.74), true)
		"metal": m = Lodge._metal()
		"glass": return Lodge._glass()
		_: m = Look.felt(Color.MAGENTA)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _s(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]


## 箱（まんなか c、向き b の各軸に大きさ size）。tenkamori_lift.gd の box は面が裏返し（外から見て反時計回り）で、
## 裏も描く素材だと法線が逆になり、陽の当たる面が陰の色になる（屋根の雪が暗い藍に写った）。ここは表を外へ向ける
static func _bx(st: SurfaceTool, c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f in faces:
		var n: Vector3 = f[0]
		var o := n * h
		var du: Vector3 = (f[1] as Vector3) * h
		var dv: Vector3 = (f[2] as Vector3) * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		var wn := (b * n).normalized()
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.add_vertex(c + b * q[k])


func _col(c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(b, c)
	_body.add_child(cs)


## 隅 a から b までの箱。座標は (v, y, u)
func _span(key: String, a: Vector3, b: Vector3, col := false) -> void:
	var c := (a + b) * 0.5
	var size := (b - a).abs()
	_bx(_s(key), c, size)
	if col:
		_col(c, size)


## 南北に走る壁（v が一定）: u0〜u1、下 y0、上は u0 で ya・u1 で yb（屋根の裏に沿って斜め）。厚み WALL_T
func _wall_u(key: String, v: float, u0: float, u1: float, y0: float, ya: float, yb: float, col := true, t := WALL_T) -> void:
	var st := _s(key)
	for s in [-0.5, 0.5]:
		var x: float = v + t * s
		var q := [Vector3(x, y0, u0), Vector3(x, y0, u1), Vector3(x, yb, u1), Vector3(x, ya, u0)]
		for k in ([0, 1, 2, 0, 2, 3] if s > 0.0 else [0, 2, 1, 0, 3, 2]):   # 表を外へ
			st.set_normal(Vector3(signf(s), 0, 0))
			st.add_vertex(q[k])
	for e in [[u0, ya, -1.0], [u1, yb, 1.0]]:   # 端の小口
		var q := [Vector3(v - t * 0.5, y0, e[0]), Vector3(v + t * 0.5, y0, e[0]), Vector3(v + t * 0.5, e[1], e[0]), Vector3(v - t * 0.5, e[1], e[0])]
		for k in ([0, 1, 2, 0, 2, 3] if e[2] < 0.0 else [0, 2, 1, 0, 3, 2]):
			st.set_normal(Vector3(0, 0, e[2]))
			st.add_vertex(q[k])
	if col:
		var top := minf(ya, yb)
		if top - y0 > 0.05:
			_col(Vector3(v, (y0 + top) * 0.5, (u0 + u1) * 0.5), Vector3(t, top - y0, u1 - u0))


## 窓の桟: v が一定の壁の、u0〜u1・y0〜y1 に、step おきの縦の桟と上下の枠
func _mullions_u(v: float, u0: float, u1: float, y0: float, y1: float, step: float) -> void:
	var n := maxi(1, int(round((u1 - u0) / step)))
	for k in n + 1:
		var u := lerpf(u0, u1, float(k) / n)
		_span("metal", Vector3(v - 0.04, y0, u - 0.03), Vector3(v + 0.04, y1, u + 0.03))
	for y in [y0, y1]:
		_span("metal", Vector3(v - 0.04, y - 0.03, u0), Vector3(v + 0.04, y + 0.03, u1))


# ---- 床とデッキ ------------------------------------------------------------------------

func _floors() -> void:
	# 休憩所の床（灰のコンクリート）と、その下の基礎
	_span("floor", Vector3(WV, FL - 0.12, HALL_U.x), Vector3(EV, FL, HALL_U.y), true)
	_span("panel", Vector3(WV, -0.6, HALL_U.x), Vector3(EV, FL - 0.12, HALL_U.y), true)
	# デッキ: 西（入口の前から南の端まで）と南
	_span("deck", Vector3(0.3, FL - 0.15, HALL_U.x), Vector3(WV, FL, ROOF_U), true)
	_span("deck", Vector3(WV, FL - 0.15, HALL_U.y), Vector3(EV, FL, ROOF_U), true)
	_span("panel", Vector3(0.45, -0.6, HALL_U.x + 0.15), Vector3(WV, FL - 0.15, ROOF_U - 0.15), true)
	_span("panel", Vector3(WV, -0.6, HALL_U.y), Vector3(EV - 0.15, FL - 0.15, ROOF_U - 0.15), true)
	# 手すり: 西のデッキの縁（庇の南から）、南の縁、東の端
	_rail(Vector3(0.36, FL, CANOPY_U.y + 0.2), Vector3(0.36, FL, ROOF_U - 0.06))
	_rail(Vector3(0.36, FL, ROOF_U - 0.06), Vector3(EV - 0.06, FL, ROOF_U - 0.06))
	_rail(Vector3(EV - 0.06, FL, ROOF_U - 0.06), Vector3(EV - 0.06, FL, HALL_U.y + 0.2))
	# 入口の前: 踏み固めた雪の坂（地面からデッキへ）。西と東
	_ramp(-0.3, -2.9, CANOPY_U.x + 0.4, CANOPY_U.y - 0.4)
	_span("floor", Vector3(EV - 0.05, FL - 0.4, EAST_DOOR_U.x), Vector3(EV + 0.4, FL, EAST_DOOR_U.y), true)   # 東の入口の敷居（床と坂のあいだを埋める）
	_ramp(EV + 0.4, EV + 3.6, EAST_DOOR_U.x - 0.6, EAST_DOOR_U.y + 0.6)
	# 北の吹きさらしの下: 青いシートの箱（コマ rdj-190・tokyu-60）
	_span("blue", Vector3(0.9, 0.0, 3.4), Vector3(2.3, 1.15, 6.0), true)
	_span("snow", Vector3(0.85, 1.15, 3.35), Vector3(2.35, 1.3, 6.05))


## 手すり（金属）: 上の棒と中の棒と、1.7 m おきの柱
func _rail(a: Vector3, b: Vector3) -> void:
	var st := _s("steel")
	for h in [1.0, 0.55]:
		Lift.cyl(st, a + Vector3(0, h, 0), b + Vector3(0, h, 0), 0.03, 6)
	var n := maxi(1, int(round(a.distance_to(b) / 1.7)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		Lift.cyl(st, p, p + Vector3(0, 1.0, 0), 0.03, 6)
	var c := (a + b) * 0.5 + Vector3(0, 0.5, 0)
	var d := (b - a).abs()
	_col(c, Vector3(maxf(d.x, 0.08), 1.0, maxf(d.z, 0.08)))


## 雪の坂: v0（デッキの高さ）から v1（地面）へ、u0〜u1 の幅
func _ramp(v0: float, v1: float, u0: float, u1: float) -> void:
	var run := absf(v1 - v0)
	var L := Vector2(run, FL).length()
	var ang := atan2(FL, run) * signf(v0 - v1)
	var b := Basis(Vector3.BACK, ang)
	var mid := Vector3((v0 + v1) * 0.5, FL * 0.5, (u0 + u1) * 0.5)
	var c := mid - b.y * 0.2
	_bx(_s("snow"), c, Vector3(L, 0.4, u1 - u0), b)
	_col(c, Vector3(L, 0.4, u1 - u0), b)


# ---- 壁 ------------------------------------------------------------------------------

func _walls() -> void:
	var f := FL
	# 低い灰の棟（中には入れない）: 西に小さな窓 2 つ
	_span("panel", Vector3(WV, 0.0, LOW_U.x), Vector3(EV, LOW_H, LOW_U.y), true)
	_span("fascia", Vector3(WV - 0.1, LOW_H, LOW_U.x - 0.1), Vector3(EV + 0.1, LOW_H + 0.12, LOW_U.y))
	for u in [8.0, 10.6]:
		_span("glass", Vector3(WV - 0.03, 1.3, u), Vector3(WV - 0.01, 2.1, u + 1.2))
		_mullions_u(WV - 0.02, u, u + 1.2, 1.3, 2.1, 0.6)

	# 西の壁（ゲレンデの側）: 下は灰のパネル
	_wall_u("panel", WV, HALL_U.x, DOOR_U.x, 0.0, PANEL_H, PANEL_H)
	_wall_u("panel", WV, DOOR_U.x, DOOR_U.y, f + DOOR_H, PANEL_H, PANEL_H, false)            # 入口の上
	_wall_u("panel", WV, DOOR_U.y, BAND_U.x, 0.0, PANEL_H, PANEL_H)
	_wall_u("panel", WV, BAND_U.x, BAND_U.y, 0.0, f + SILL, f + SILL)
	_wall_u("panel", WV, BAND_U.x, BAND_U.y, f + BAND_TOP, PANEL_H, PANEL_H, false)
	_wall_u("panel", WV, TALL_U.x, TALL_U.y, 0.0, f + SILL, f + SILL)
	#   入口: ガラスの引き戸を両脇へ開けたまま（まんなか 1.3 m が通れる）
	var dm := (DOOR_U.x + DOOR_U.y) * 0.5
	_wall_u("glass", WV, DOOR_U.x, dm - 0.65, f, f + DOOR_H, f + DOOR_H, true, 0.04)
	_wall_u("glass", WV, dm + 0.65, DOOR_U.y, f, f + DOOR_H, f + DOOR_H, true, 0.04)
	for u in [DOOR_U.x, dm - 0.65, dm + 0.65, DOOR_U.y]:
		_span("metal", Vector3(WV - 0.05, f, u - 0.03), Vector3(WV + 0.05, f + DOOR_H, u + 0.03))
	#   券売所の小窓（入口の北）と、救護の赤い十字の札
	_span("glass", Vector3(WV - 0.14, f + 1.0, 13.75), Vector3(WV - 0.12, f + 1.7, 14.4))
	_mullions_u(WV - 0.13, 13.75, 14.4, f + 1.0, f + 1.7, 0.65)
	_span("fascia", Vector3(WV - 0.15, f + 1.5, 17.5), Vector3(WV - 0.13, f + 2.1, 18.1))
	_span("red", Vector3(WV - 0.17, f + 1.72, 17.6), Vector3(WV - 0.15, f + 1.88, 18.0))
	_span("red", Vector3(WV - 0.17, f + 1.58, 17.72), Vector3(WV - 0.15, f + 2.02, 17.88))
	#   横長の窓と、南の端の背の高いガラス
	_wall_u("glass", WV, BAND_U.x, BAND_U.y, f + SILL, f + BAND_TOP, f + BAND_TOP, true, 0.04)
	_mullions_u(WV, BAND_U.x, BAND_U.y, f + SILL, f + BAND_TOP, 1.1)
	_wall_u("glass", WV, TALL_U.x, TALL_U.y, f + SILL, under(TALL_U.x) - 0.3, under(TALL_U.y) - 0.3, true, 0.04)
	_mullions_u(WV, TALL_U.x, TALL_U.y, f + SILL, under(TALL_U.y) - 0.3, 0.95)
	_wall_u("wood", WV, TALL_U.x, TALL_U.y, under(TALL_U.y) - 0.3, under(TALL_U.x), under(TALL_U.y), false)
	_wall_u("metal", WV, TALL_U.x, TALL_U.y, PANEL_H - 0.04, PANEL_H + 0.04, PANEL_H + 0.04, false, 0.08)
	#   上は縦張りの木（棟で折れる）
	_wall_u("wood", WV, HALL_U.x, RIDGE_U, PANEL_H, under(HALL_U.x), under(RIDGE_U), false)
	_wall_u("wood", WV, RIDGE_U, TALL_U.x, PANEL_H, under(RIDGE_U), under(TALL_U.x), false)

	# 東の壁（駐車場・道の側）: 腰までパネル、横長の窓、上は木。南寄りに入口（開いたまま）
	_wall_u("panel", EV, HALL_U.x, EAST_DOOR_U.x, 0.0, f + SILL, f + SILL)
	_wall_u("panel", EV, EAST_DOOR_U.y, HALL_U.y, 0.0, f + SILL, f + SILL)
	_wall_u("panel", EV, HALL_U.x, EAST_WIN_U.x, f + SILL, PANEL_H, PANEL_H)
	_wall_u("panel", EV, EAST_WIN_U.y, EAST_DOOR_U.x, f + SILL, PANEL_H, PANEL_H)
	_wall_u("panel", EV, EAST_DOOR_U.y, HALL_U.y, f + SILL, PANEL_H, PANEL_H)
	_wall_u("panel", EV, EAST_WIN_U.x, EAST_WIN_U.y, f + BAND_TOP + 0.3, PANEL_H, PANEL_H, false)
	_wall_u("panel", EV, EAST_DOOR_U.x, EAST_DOOR_U.y, f + DOOR_H, PANEL_H, PANEL_H, false)
	_wall_u("glass", EV, EAST_WIN_U.x, EAST_WIN_U.y, f + SILL, f + BAND_TOP + 0.3, f + BAND_TOP + 0.3, true, 0.04)
	_mullions_u(EV, EAST_WIN_U.x, EAST_WIN_U.y, f + SILL, f + BAND_TOP + 0.3, 1.1)
	_wall_u("wood", EV, HALL_U.x, RIDGE_U, PANEL_H, under(HALL_U.x), under(RIDGE_U), false)
	_wall_u("wood", EV, RIDGE_U, HALL_U.y, PANEL_H, under(RIDGE_U), under(HALL_U.y), false)

	# 南の壁: 壁いっぱいの窓（腰はパネル）
	var su := HALL_U.y
	var top := under(su)
	_span("panel", Vector3(WV, 0.0, su - WALL_T * 0.5), Vector3(EV, f + SILL, su + WALL_T * 0.5), true)
	_span("panel", Vector3(WV, f + SOUTH_TOP, su - WALL_T * 0.5), Vector3(EV, top, su + WALL_T * 0.5))
	_span("glass", Vector3(WV, f + SILL, su - 0.02), Vector3(EV, f + SOUTH_TOP, su + 0.02), true)
	var n := 10
	for k in n + 1:
		var v := lerpf(WV + 0.1, EV - 0.1, float(k) / n)
		_span("metal", Vector3(v - 0.03, f + SILL, su - 0.04), Vector3(v + 0.03, f + SOUTH_TOP, su + 0.04))
	for y in [f + SILL, f + SOUTH_TOP]:
		_span("metal", Vector3(WV, y - 0.03, su - 0.04), Vector3(EV, y + 0.03, su + 0.04))

	# 北の壁（休憩所と低い棟のあいだ。低い棟の上は外から見える）
	_span("wood", Vector3(WV, 0.0, HALL_U.x - WALL_T * 0.5), Vector3(EV, under(HALL_U.x), HALL_U.x + WALL_T * 0.5), true)


# ---- 屋根 ----------------------------------------------------------------------------

func _roof() -> void:
	_plane(0.0, EAVE_N_H, RIDGE_U, RIDGE_H)
	_plane(RIDGE_U, RIDGE_H, ROOF_U, EAVE_S_H)
	# 棟の雪の丸み
	Lift.cyl(_s("snow"), Vector3(0.15, RIDGE_H + SNOW_T * 0.55, RIDGE_U), Vector3(ROOF_V - 0.15, RIDGE_H + SNOW_T * 0.55, RIDGE_U), SNOW_T * 0.6, 10)


## 屋根の 1 面: 白い縁の板、上に厚い雪、裏は木の天井
func _plane(u0: float, h0: float, u1: float, h1: float) -> void:
	var L := Vector2(u1 - u0, h1 - h0).length()
	var b := Basis(Vector3.RIGHT, -atan2(h1 - h0, u1 - u0))
	var mid := Vector3(ROOF_V * 0.5, (h0 + h1) * 0.5, (u0 + u1) * 0.5)
	_bx(_s("fascia"), mid - b.y * ROOF_T * 0.5, Vector3(ROOF_V, ROOF_T, L), b)
	_col(mid - b.y * ROOF_T * 0.5, Vector3(ROOF_V, ROOF_T, L), b)
	_bx(_s("snow"), mid + b.y * SNOW_T * 0.5, Vector3(ROOF_V - 0.2, SNOW_T, L - 0.1), b)
	_bx(_s("inner"), mid - b.y * (ROOF_T + 0.03), Vector3(ROOF_V - 0.16, 0.04, L - 0.08), b)


# ---- 柱と梁 --------------------------------------------------------------------------

func _post(v: float, u: float, y0 := 0.0) -> void:
	var top := under(u)
	Lift.cyl(_s("steel"), Vector3(v, y0 - 0.3, u), Vector3(v, top, u), COL_R, 10)
	_col(Vector3(v, (y0 + top) * 0.5, u), Vector3(COL_R * 2.0, top - y0, COL_R * 2.0))


## 柱の頭から壁へ（または向かいの柱へ）の木の梁
func _beam(u: float, v0: float, v1: float) -> void:
	var y := under(u) - 0.2
	_span("beam", Vector3(v0, y - 0.18, u - 0.09), Vector3(v1, y + 0.18, u + 0.09))


func _columns() -> void:
	for u in COLS_W:   # 西の軒先（ゲレンデの側）
		_post(0.35, u)
		_beam(u, 0.1, WV if u > PORCH_U else ROOF_V - 0.1)
	for u in COLS_E:   # 東の軒先
		_post(ROOF_V - 0.35, u)
		if u > PORCH_U:
			_beam(u, EV, ROOF_V - 0.1)
	for u in [0.4, 4.4]:   # 北の吹きさらしの中の柱
		for v in [5.3, 10.2]:
			_post(v, u)
	for v in [4.0, 7.6, 11.2]:   # 南の軒先
		_post(v, 33.6, FL)


# ---- 庇 ------------------------------------------------------------------------------

func _canopies() -> void:
	# ゲレンデの側: 白い角丸の庇（西へ 3.2 m 出る）と、先の 2 本の白い脚
	_canopy(WV - CANOPY_OUT, WV, CANOPY_U.x, CANOPY_U.y, WV - CANOPY_OUT + 0.3)
	# 駐車場の側（場所は推しはかり）
	_canopy(EV, EV + 2.6, EAST_DOOR_U.x - 1.0, EAST_DOOR_U.y + 1.0, EV + 2.3)


func _canopy(v0: float, v1: float, u0: float, u1: float, leg_v: float) -> void:
	var y := FL + CANOPY_H
	_span("canopy", Vector3(v0, y - 0.45, u0 + 0.22), Vector3(v1, y, u1 - 0.22))
	for u in [u0 + 0.22, u1 - 0.22]:   # 角丸: 縁に筒
		Lift.cyl(_s("canopy"), Vector3(v0 + 0.1, y - 0.225, u), Vector3(v1 - 0.1, y - 0.225, u), 0.225, 12)
	_span("snow", Vector3(v0 + 0.1, y, u0 + 0.15), Vector3(v1, y + 0.3, u1 - 0.15))
	for u in [u0 + 0.55, u1 - 0.55]:
		_span("canopy", Vector3(leg_v - 0.25, -0.3, u - 0.25), Vector3(leg_v + 0.25, y - 0.45, u + 0.25), true)


# ---- 中 ------------------------------------------------------------------------------

func _inside() -> void:
	var f := FL
	# 中の壁の木（外の壁の内側に薄く重ねる）: 北の壁と、東西の壁のパネルの裏
	_span("inner", Vector3(WV + 0.13, f, HALL_U.x + 0.13), Vector3(EV - 0.13, under(HALL_U.x), HALL_U.x + 0.16))
	# 黒い鉄の丸柱（場所は推しはかり）
	for u in [17.5, 23.0, 28.0]:
		for v in [6.2, 10.3]:
			var top := under(u)
			Lift.cyl(_s("black"), Vector3(v, f, u), Vector3(v, top, u), 0.11, 12)
			_col(Vector3(v, (f + top) * 0.5, u), Vector3(0.22, top - f, 0.22))
	# 食堂のカウンター（北の壁ぎわの東寄り）と、閉めたシャッター
	_span("inner", Vector3(8.6, f, HALL_U.x + 0.16), Vector3(EV - 0.2, f + 1.0, HALL_U.x + 0.9), true)
	_span("steel", Vector3(8.6, f + 1.0, HALL_U.x + 0.16), Vector3(EV - 0.2, f + 2.3, HALL_U.x + 0.22))
	# 長机とベンチ（南の窓の側に 2 列）
	for u in [20.5, 24.5, 28.5]:
		for v in [4.6, 11.6]:
			_table(Vector3(v, f, u))


func _table(c: Vector3) -> void:
	_span("table", c + Vector3(-0.4, 0.68, -0.9), c + Vector3(0.4, 0.72, 0.9))
	_col(c + Vector3(0, 0.36, 0), Vector3(0.8, 0.72, 1.8))
	for su in [-0.8, 0.8]:
		for sv in [-0.32, 0.32]:
			Lift.cyl(_s("steel"), c + Vector3(sv, 0, su), c + Vector3(sv, 0.68, su), 0.025, 6)
	for sv in [-0.75, 0.75]:   # ベンチ
		_span("table", c + Vector3(sv - 0.16, 0.40, -0.85), c + Vector3(sv + 0.16, 0.44, 0.85))
		for su in [-0.75, 0.75]:
			Lift.cyl(_s("steel"), c + Vector3(sv, 0, su), c + Vector3(sv, 0.40, su), 0.025, 6)
