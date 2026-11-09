extends Node3D
## 天下森の旧・夏虫沢ヒュッテ（平成7年竣工・木造平屋・284㎡。2019 年のストリートビューの姿）。2026-11-09。
## 代表「ロッジも天下森のを作ってほしい」→ 図面に起こしてから組む（「画像そのままで作る前に図面に起こしたほうが良い」）→「旧ヒュッテ（2019）」→ 図面案に「いいね！これで組んで！」
## 寸法は ../hutte/dims.py（図面は design/tenkamori/hutte-old/01-plans.png）。ここの定数はその写し。変えるときは両方を直す。
## 手本: 横手市「令和3年度 天下森スキー場等整備全体計画書」5〜6 頁の平面図と写真、ストリートビュー 2019-10、国土地理院の空中写真。
##
## 組み立て:
##   まんなか = ホール（上部吹抜）。急な A 字の屋根（46°）が、駐車場の側とゲレンデの側へ張り出した風除室までかかる。
##     入口の妻は両面同じ: まんなかに丸太の柱 1 本（土間から頂まで）、床から 3.2 m に横の丸太の梁 1 本と看板、柱の右にガラスの戸、左に白い戸
##   南東 = 休憩スペース 14 × 9 m（ゆるい切妻・ゲレンデの側に大きな窓・木の柱と方杖・長机とオレンジの椅子）、端に厨房の差し掛け（平成13年）
##   北西 = 青い屋根の低い棟（便所・救護室・事務室など。中には入れない）。端に小さな差し掛けの戸口と段
##   ゲレンデの側に全長のデッキ、駐車場の側に風除室の東のデッキ。入口の段はガラスの戸の前
## 座標（この節点の中）: x = u（長い辺。+ が南東）、z = v（+ がゲレンデの側）、y = 上。原点 = ホールのまんなか、ならした地面の高さ。
## 置き場所は空中写真から: ホールのまんなかが (48, 21)、長い辺が東から 26°

const Look := preload("res://look.gd")
const Lift := preload("res://tenkamori_lift.gd")   # 箱と筒の形の部品
const Lodge := preload("res://lodge/lodge.gd")       # 今までのロッジの素材（板・丸太・ガラス・鉄・玄関マット）を流用する
const Props := preload("res://props.gd")

const AT := Vector2(48.0, 21.0)
const YAW_DEG := 26.0

const FL := 0.75
const HALL_U := Vector2(-2.25, 2.25)
const HALL_V := Vector2(-4.5, 4.5)
const VEST_V := 8.0                       # 風除室の外の壁（± 両側）
## 風除室の幅の半分（2026-11-09 代表「壁なかったり」: 入口の両脇の A 字の屋根の下が筒抜けだった。A 字の軒の線まで壁で囲う）
const VEST_U := 5.0
const REST_U := Vector2(2.25, 17.0)
const KITCHEN_U := Vector2(17.0, 21.3)
const WING_U := Vector2(-10.85, -2.25)
const WING_V := Vector2(-6.5, 4.5)
const REST_EAVE := 3.0
const REST_PITCH := deg_to_rad(40.0)
const WING_EAVE := 3.0
const WING_PITCH := deg_to_rad(30.0)
const KITCHEN_EAVE := 2.4
const A_HALF := 5.0
const A_EAVE := 3.0   # 2026-11-09 代表「屋根の下端も低すぎでは？隣り合ってる屋根と合流するくらいの高さ」: 休憩室・北西の棟の軒と同じ
const A_PITCH := deg_to_rad(46.0)   # 頂は 8.9 m（代表「低くして」で 60° → 50°、軒を上げて 46°）
const A_V := 9.5
const OV_SIDE := 0.9
const OV_GABLE := 1.2
const DECK_S_V := Vector2(4.5, 6.4)
const DECK_N := Rect2(5.0, -7.2, 4.35, 2.7)    # u, v, 幅, 奥行き（風除室の東）
const PORCH := Vector2(4.5, 0.9)                # 風除室の前の土間: u の半分の幅、奥行き
const STEPS_U := Vector2(0.2, 2.6)              # 駐車場の側の段（u を裏返して -2.6〜-0.2: ガラスの入口の前）
const STEPS_LEN := 2.2
const POST_R := 0.18
## 入口の妻（2026-11-09 代表がくれた冬の入口の写真: research/natsumushi-hutte/sources/img/daihyo-entrance-winter.webp）:
## 丸太の柱の左（外から見て。u が負の側。両側とも同じ）に木の框のガラスの入口 = 嵌め殺し・両開き・嵌め殺し。梁は入口の上端のすぐ上。
## ゲレンデの側は柱の右が券売の窓、駐車場の側は白い戸。ゲレンデの側の入口の前は段でなく、雪と同じ高さの土間に赤と青のマット
const BEAM_Y := 2.95
const GLASS_U := Vector2(-3.4, -0.25)           # ガラスの入口の全体（両側とも）
const LEAVES_U := Vector2(-2.5, -0.7)           # そのうち両開きの戸
const ENTRY_H := 2.7                            # 入口の高さ（床から）
const WHITE_U := Vector2(0.6, 1.9)              # 駐車場の側の白い開き戸
const TICKET_U := Vector2(0.6, 2.8)             # ゲレンデの側の券売の窓
const RAMP_LEN := 6.0                           # ゲレンデの側: 土間から雪の地面へのゆるい坂
const T := 0.25                                 # 壁の厚さ

const BOARD := Color(0.36, 0.24, 0.16)    # 焦げ茶の横板の壁（日に焼けた茶）
const LOG := Color(0.38, 0.28, 0.20)      # 丸太の柱と梁（日に焼けて灰がかった茶）
const ROOF := Color(0.64, 0.66, 0.68)     # 灰の鉄板の屋根
const BLUE := Color(0.36, 0.48, 0.68)     # 北西の棟の青い屋根
const DECK := Color(0.55, 0.41, 0.27)
const BASE := Color(0.66, 0.66, 0.64)     # 基礎
const SOFFIT := Color(0.42, 0.29, 0.19)   # A 字の屋根の裏と妻の板
const INNER := Color(0.94, 0.93, 0.89)    # 中の白い壁
const CEILING := Color(0.70, 0.52, 0.34)  # 休憩室の天井の板
const FLOOR := Color(0.62, 0.47, 0.32)
const TABLE := Color(0.72, 0.56, 0.38)
const CHAIR := Color(0.78, 0.36, 0.10)    # オレンジの椅子（食事風景の写真）。座と背はビニールの張り地: 少しつやがあり、縁は光らせない
const SIGN := Color(0.90, 0.84, 0.70)

var _st := {}
var _body: StaticBody3D
var _lights: Array[Vector3] = []


## 遊びの座標（x, z）。u, v はこの節点の中の座標
static func to_world(u: float, v: float) -> Vector2:
	var c := cos(deg_to_rad(YAW_DEG))
	var s := sin(deg_to_rad(YAW_DEG))
	return AT + Vector2(u * c - v * s, u * s + v * c)


## 始める所: 駐車場の側の入口の段の前（2026-11-09 代表「スポーン場所をロッジの前にしてほしい」「駐車場側というか」）
static func front_spot() -> Vector2:
	return to_world(-1.4, -VEST_V - PORCH.y - STEPS_LEN - 2.5)


static func place(world: Node3D) -> Node3D:
	var pads: Dictionary = preload("res://tenkamori.gd").map().get("pads", {})
	var h := new()
	h.name = "Hutte"
	h.position = Vector3(AT.x, float(pads.get("hutte", {}).get("y", 0.0)), AT.y)
	h.rotation.y = -deg_to_rad(YAW_DEG)   # x（長い辺）を東から 26° の向きへ
	world.add_child(h)
	return h


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.name = "HutteBody"
	add_child(_body)
	_make_planes()   # 壁の上を屋根の裏まで届かせるので、屋根の面を先に決める（2026-11-09 代表「塞がってない」: 壁を先に組んでいて、どの壁も軒の高さで止まり、妻の三角が開いていた）
	_floors()
	_walls()
	_roofs()
	_gables()
	_decks()
	_inside()
	_doors()
	for key in _st:
		var mi := MeshInstance3D.new()
		mi.name = "Hutte_" + key
		mi.mesh = (_st[key] as SurfaceTool).commit()
		mi.material_override = _material(key)
		add_child(mi)
	for p in _lights:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.80, 0.58)
		l.light_energy = 1.3
		l.omni_range = 9.0
		l.position = p
		add_child(l)


## 素材は今までのロッジ（lodge/lodge.gd）の物を流用する（2026-11-09 代表「テクスチャが全然なかった」「デフォルトワールドから流用できるものいっぱいある」）:
## 壁・床・デッキ・天井は幅 40 cm の荒い板（_planks）、丸太の柱と梁は木肌と樹皮のむら（_log_wood）、ガラス（_glass）、戸の框（_metal）
func _material(key: String) -> Material:
	var m: BaseMaterial3D
	match key:
		"board": m = Lodge._planks(BOARD, true)
		"log":
			var lm: ShaderMaterial = Lodge._log_wood().duplicate()
			var sh := Shader.new()
			sh.code = Lodge.LOG_SHADER.replace("render_mode diffuse_burley;", "render_mode diffuse_burley, cull_disabled;")
			lm.shader = sh
			return lm
		"roof": m = Look.felt(ROOF, 1.2)
		"blue": m = Look.felt(BLUE, 1.2)
		"deck": m = Lodge._planks(DECK)
		"step": m = Lodge._planks(DECK, true)
		"base": m = Look.felt(BASE, 2.0)
		"soffit": m = Lodge._planks(SOFFIT, true)
		"ceiling": m = Lodge._planks(CEILING, true)
		"floor": m = Lodge._planks(FLOOR)
		"table": m = Lodge._planks(TABLE, true)
		"chair":   # 2026-11-09 代表「なんで椅子が光ってんの？」: フェルトの縁の光（rim）と明るすぎる橙が、低い灯りで白くにじんでいた
			m = StandardMaterial3D.new()
			m.albedo_color = CHAIR
			m.roughness = 0.55
			m.metallic_specular = 0.3
		"snow": m = Look.snow()
		"inner":
			m = Look.paper(INNER)
			m.emission_enabled = true   # 灯りの照り返しで明るく（空の青い光で青白くならないように）
			m.emission = INNER * Color(1.0, 0.92, 0.80)
			m.emission_energy_multiplier = 0.15
		"sign": m = Look.paper(SIGN)
		"door": m = Look.paper(Color(0.93, 0.93, 0.92))
		"metal": m = Lodge._metal()
		"mat_out": m = Lodge._doormat(false)
		"mat_in": m = Look.felt(Color(0.24, 0.45, 0.22), 2.0)   # 中の緑のマット（写真）
		"mat_red": m = Look.felt(Color(0.80, 0.33, 0.16), 2.0)  # 外の赤（オレンジがかった）マット
		"mat_blue": m = Look.felt(Color(0.13, 0.32, 0.72), 2.0)
		"frame": m = Look.wood(Color(0.42, 0.27, 0.15))         # 入口の木の框
		"lamp":
			m = Look.paper(Color(0.98, 0.90, 0.72))
			m.emission_enabled = true
			m.emission = Color(1.0, 0.78, 0.48)
			m.emission_energy_multiplier = 1.4
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


func _box(key: String, c: Vector3, size: Vector3, b := Basis.IDENTITY, col := false) -> void:
	Lift.box(_s(key), c, size, b)
	if col:
		_col(c, size, b)


func _col(c: Vector3, size: Vector3, b := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = Transform3D(b, c)
	_body.add_child(cs)


## 隅 a から b までの箱（軸にそろった）
func _span(key: String, a: Vector3, b: Vector3, col := false) -> void:
	_box(key, (a + b) * 0.5, (b - a).abs(), Basis.IDENTITY, col)


## 三角の板: 3 点の面を、法線の向きに厚さ th
func _tri(key: String, p: Array, th: float) -> void:
	var st := _s(key)
	var n: Vector3 = ((p[1] - p[0]) as Vector3).cross(p[2] - p[0]).normalized()
	for s in [-0.5, 0.5]:
		for v in p:
			st.set_normal(n * signf(s))
			st.add_vertex(v + n * th * s)
	for k in 3:
		var a: Vector3 = p[k]
		var b: Vector3 = p[(k + 1) % 3]
		var sn := (b - a).cross(n).normalized()
		for v in [a - n * th * 0.5, b - n * th * 0.5, b + n * th * 0.5, a - n * th * 0.5, b + n * th * 0.5, a + n * th * 0.5]:
			st.set_normal(sn)
			st.add_vertex(v)


## 丸太（a から b）
func _log(a: Vector3, b: Vector3, r: float, col := false) -> void:
	Lift.cyl(_s("log"), a, b, r, 12)
	if col:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = a.distance_to(b)
		cs.shape = sh
		var up := (b - a).normalized()
		var bx := up.cross(Vector3.BACK if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		cs.transform = Transform3D(Basis(bx, up, bx.cross(up)), (a + b) * 0.5)
		_body.add_child(cs)


# ---- 床 ----------------------------------------------------------------------------

func _floors() -> void:
	# 基礎と床（ホール・風除室・休憩室・厨房・北西の棟）
	for r in [Rect2(-VEST_U, -VEST_V, VEST_U * 2.0, VEST_V * 2.0), Rect2(REST_U.x, HALL_V.x, KITCHEN_U.y - REST_U.x, HALL_V.y - HALL_V.x),
			Rect2(WING_U.x, WING_V.x, WING_U.y - WING_U.x, WING_V.y - WING_V.x)]:
		_span("base", Vector3(r.position.x, -0.6, r.position.y), Vector3(r.end.x, FL - 0.04, r.end.y), true)
	_span("floor", Vector3(-VEST_U + T, FL - 0.04, -VEST_V + T), Vector3(VEST_U - T, FL, VEST_V - T))
	_span("floor", Vector3(REST_U.x, FL - 0.04, HALL_V.x + T), Vector3(REST_U.y - T, FL, HALL_V.y - T))


# ---- 屋根（一つの面） ----------------------------------------------------------------
## 2026-11-09 代表「屋根を棟にぶっ刺した感じなのやめてほしい」「▲の屋根が棟の中でも障害物のように干渉している」「屋根同士の接続部分が汚すぎる」:
## 屋根を別々の板として重ねるのをやめ、どの点でも「そこを覆う屋根の面のうち、いちばん高い面」をとる一つの面にする（本当の屋根の取り合いと同じ）。
## 面どうしが交わる所はそのまま谷の線になる。屋根の裏はその面を厚さ分下げた面で、中から見える天井もそれ（屋根が部屋を突き抜けない）。
## 壁の上は、その場所の屋根の裏まで届かせる（すき間ができない）。
## 面: [u の範囲, v の範囲, 高さの式 h = c + cu·u + cv·v, 上の素材, 裏の素材, 縁の色]。範囲は軒と妻の出を含む

const ROOF_T := 0.3   # 屋根の厚さ
var _planes := []


func _make_planes() -> void:
	var rr := FL + REST_EAVE + HALL_V.y * tan(REST_PITCH)                     # 休憩室の棟
	var wc := (WING_V.x + WING_V.y) * 0.5
	var wh := (WING_V.y - WING_V.x) * 0.5
	var rw := FL + WING_EAVE + wh * tan(WING_PITCH)                            # 北西の棟の棟
	var ra := FL + A_EAVE + A_HALF * tan(A_PITCH)                              # A 字の頂
	var tr := tan(REST_PITCH)
	var tw := tan(WING_PITCH)
	var ta := tan(A_PITCH)
	var rv := HALL_V.y + OV_SIDE
	var wv0 := WING_V.x - OV_SIDE
	var wv1 := WING_V.y + OV_SIDE
	var au := A_HALF + OV_SIDE
	_planes = [
		# 休憩室（棟は u に沿う）。北西は A 字の頂の線まで延ばしておく（A 字の面の下に入ると、そこで谷になって消える）
		{"u": Vector2(0.0, REST_U.y + OV_GABLE), "v": Vector2(0.0, rv), "c": rr, "cu": 0.0, "cv": -tr, "under": "ceiling", "edge": "roof"},
		{"u": Vector2(0.0, REST_U.y + OV_GABLE), "v": Vector2(-rv, 0.0), "c": rr, "cu": 0.0, "cv": tr, "under": "ceiling", "edge": "roof"},
		# 北西の棟（棟は u に沿い、まんなかは v = wc）
		{"u": Vector2(WING_U.x - OV_GABLE, 0.0), "v": Vector2(wc, wv1), "c": rw + wc * tw, "cu": 0.0, "cv": -tw, "under": "soffit", "edge": "blue"},
		{"u": Vector2(WING_U.x - OV_GABLE, 0.0), "v": Vector2(wv0, wc), "c": rw - wc * tw, "cu": 0.0, "cv": tw, "under": "soffit", "edge": "blue"},
		# ホールの A 字（棟は v に沿う）
		{"u": Vector2(0.0, au), "v": Vector2(-A_V, A_V), "c": ra, "cu": -ta, "cv": 0.0, "under": "soffit", "edge": "roof"},
		{"u": Vector2(-au, 0.0), "v": Vector2(-A_V, A_V), "c": ra, "cu": ta, "cv": 0.0, "under": "soffit", "edge": "roof"},
	]


static func _ph(pl: Dictionary, u: float, v: float) -> float:
	return pl.c + pl.cu * u + pl.cv * v


static func _in(pl: Dictionary, u: float, v: float, e := 0.001) -> bool:
	return u >= pl.u.x - e and u <= pl.u.y + e and v >= pl.v.x - e and v <= pl.v.y + e


## 屋根の上の面の高さ（覆う面がなければ -INF）
func _env(u: float, v: float) -> float:
	var h := -INF
	for pl in _planes:
		if _in(pl, u, v):
			h = maxf(h, _ph(pl, u, v))
	return h


static func _rect_poly(pl: Dictionary) -> PackedVector2Array:
	return PackedVector2Array([Vector2(pl.u.x, pl.v.x), Vector2(pl.u.y, pl.v.x), Vector2(pl.u.y, pl.v.y), Vector2(pl.u.x, pl.v.y)])


## 凸の多角形を、d(u, v) = c0 + cu·u + cv·v >= 0 の側で切る
static func _clip_half(poly: PackedVector2Array, c0: float, cu: float, cv: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		var da := c0 + cu * a.x + cv * a.y
		var db := c0 + cu * b.x + cv * b.y
		if da >= 0.0:
			out.append(a)
		if (da >= 0.0) != (db >= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## 面 i が見えている所（自分の範囲から、ほかの面が自分より高い所を抜いた多角形の列）
func _region(i: int) -> Array:
	var me: Dictionary = _planes[i]
	var polys := [_rect_poly(me)]
	for j in _planes.size():
		if j == i:
			continue
		var o: Dictionary = _planes[j]
		# o が me より高い所: (o - me) > 0。同じ高さのときは番号の小さい面を残す
		var c0: float = o.c - me.c
		var cu: float = o.cu - me.cu
		var cv: float = o.cv - me.cv
		var cut := _clip_half(_rect_poly(o), c0 - (0.0005 if j > i else -0.0005), cu, cv)
		if cut.size() < 3:
			continue
		var next := []
		for p in polys:
			for r in Geometry2D.clip_polygons(p, cut):
				if not Geometry2D.is_polygon_clockwise(r) or Geometry2D.is_polygon_clockwise(p):
					next.append(r)
		polys = next
	return polys


func _roofs() -> void:
	var top := _s("snow")
	for i in _planes.size():
		var pl: Dictionary = _planes[i]
		var nrm := Vector3(-pl.cu, 1.0, -pl.cv).normalized()
		var under := _s(pl.under)
		for poly in _region(i):
			var ids := Geometry2D.triangulate_polygon(poly)
			for k in range(0, ids.size(), 3):
				for q in 3:
					var p2: Vector2 = poly[ids[k + q]]
					var y := _ph(pl, p2.x, p2.y)
					top.set_normal(nrm)
					top.add_vertex(Vector3(p2.x, y, p2.y))
					under.set_normal(-nrm)
					under.add_vertex(Vector3(p2.x, y - ROOF_T, p2.y))
	# 縁（鼻隠し・破風）: 屋根の外形に沿って、上の面から厚さ分の帯
	var outline := [_rect_poly(_planes[0])]
	for pl in _planes.slice(1):
		var merged := []
		for o in outline:
			merged = Geometry2D.merge_polygons(o, _rect_poly(pl))
		outline = merged.filter(func(p): return not Geometry2D.is_polygon_clockwise(p))
	for o in outline:
		var n: int = o.size()
		for k in n:
			var a: Vector2 = o[k]
			var b: Vector2 = o[(k + 1) % n]
			var steps := maxi(1, int(a.distance_to(b) / 0.5))
			for q in steps:
				var p0 := a.lerp(b, float(q) / steps)
				var p1 := a.lerp(b, float(q + 1) / steps)
				var m := (p0 + p1) * 0.5
				var key := "roof"
				var best := -INF
				for pl in _planes:
					if _in(pl, m.x, m.y) and _ph(pl, m.x, m.y) > best:
						best = _ph(pl, m.x, m.y)
						key = pl.edge
				var y0 := _env(p0.x, p0.y)
				var y1 := _env(p1.x, p1.y)
				var st := _s(key)
				var en := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized() * -1.0
				for v in [Vector3(p0.x, y0 + 0.02, p0.y), Vector3(p1.x, y1 + 0.02, p1.y), Vector3(p1.x, y1 - ROOF_T - 0.06, p1.y),
						Vector3(p0.x, y0 + 0.02, p0.y), Vector3(p1.x, y1 - ROOF_T - 0.06, p1.y), Vector3(p0.x, y0 - ROOF_T - 0.06, p0.y)]:
					st.set_normal(en)
					st.add_vertex(v)
	# 厨房の差し掛け: 休憩室の妻の軒の下に収まる低い片流れ（大きな屋根の面には入れない）
	var hi := FL + KITCHEN_EAVE + 0.5
	var lo := FL + KITCHEN_EAVE - 0.2
	var run := KITCHEN_U.y + 0.6 - KITCHEN_U.x
	var p := atan2(hi - lo, run)
	var bs := Basis(Vector3.BACK, -p)
	var c := Vector3((KITCHEN_U.x + KITCHEN_U.y + 0.6) * 0.5, (hi + lo) * 0.5, 0.0)
	_box("roof", c + bs.y * 0.1, Vector3(run / cos(p), 0.2, HALL_V.y * 2.0 + 0.6), bs)
	_box("snow", c + bs.y * 0.27, Vector3(run / cos(p) - 0.3, 0.14, HALL_V.y * 2.0 + 0.3), bs)
	# 北西の端の小さな差し掛け（戸口の上）
	_box("roof", Vector3(WING_U.x - 0.9, FL + 2.45, 2.35), Vector3(2.0, 0.15, 2.6), Basis(Vector3.BACK, deg_to_rad(18.0)))


# ---- 壁（上は屋根の裏まで） ----------------------------------------------------------

## 平面の線 a → b（u, v）に沿った壁。上はその場所の屋根の裏（_env − 厚さ）まで。
## holes: [s0, s1, y0, y1, 種類]（線に沿った距離 m と、床からの高さ）。種類 "win" 窓（ガラスと窓台）、"open" 開口、"door" 閉じた戸（板）
func _pwall(a: Vector2, b: Vector2, holes := []) -> void:
	var L := a.distance_to(b)
	var dir := (b - a) / L
	var nrm := Vector2(-dir.y, dir.x)
	var cuts := [0.0, L]
	for h in holes:
		cuts.append(h[0])
		cuts.append(h[1])
	var s := 0.5
	while s < L:
		cuts.append(s)
		s += 0.5
	cuts.sort()
	var st := _s("board")
	var top_at := func(d: float) -> float:
		var p: Vector2 = a + dir * d
		var y := _env(p.x, p.y)
		return (y - ROOF_T - 0.01 - FL) if y > -INF else 3.0
	for k in cuts.size() - 1:
		var s0: float = cuts[k]
		var s1: float = cuts[k + 1]
		if s1 - s0 < 0.001:
			continue
		var mid := (s0 + s1) * 0.5
		var hs := holes.filter(func(h): return mid > h[0] and mid < h[1])
		hs.sort_custom(func(x, y): return x[2] < y[2])
		var t0: float = top_at.call(s0)
		var t1: float = top_at.call(s1)
		var y := 0.0
		var spans := []
		for h in hs:
			if h[2] > y:
				spans.append([y, h[2], false])
			y = h[3]
		spans.append([y, 0.0, true])
		for sp in spans:
			var ya0: float = sp[0]
			var yb0: float = t0 if sp[2] else sp[1]
			var yb1: float = t1 if sp[2] else sp[1]
			if yb0 <= ya0 and yb1 <= ya0:
				continue
			var q := []
			for side in [-0.5, 0.5]:
				var o: Vector2 = nrm * T * side
				var p0: Vector2 = a + dir * s0 + o
				var p1: Vector2 = a + dir * s1 + o
				q.append([Vector3(p0.x, FL + ya0, p0.y), Vector3(p1.x, FL + ya0, p1.y), Vector3(p1.x, FL + yb1, p1.y), Vector3(p0.x, FL + yb0, p0.y)])
			_quad(st, q[0], Vector3(-nrm.x, 0, -nrm.y))
			_quad(st, q[1], Vector3(nrm.x, 0, nrm.y))
			_quad(st, [q[0][3], q[0][2], q[1][2], q[1][3]], Vector3.UP)
			_quad(st, [q[0][0], q[0][3], q[1][3], q[1][0]], Vector3(-dir.x, 0, -dir.y))
			_quad(st, [q[0][1], q[0][2], q[1][2], q[1][1]], Vector3(dir.x, 0, dir.y))
	# 当たり: 戸や窓の切れ目ごとの箱（高さは 3.4 m まで）
	var marks := [0.0, L]
	for h in holes:
		marks.append(h[0])
		marks.append(h[1])
	marks.sort()
	for k in marks.size() - 1:
		var s0: float = marks[k]
		var s1: float = marks[k + 1]
		if s1 - s0 < 0.01:
			continue
		var mid := (s0 + s1) * 0.5
		var lo := 0.0
		var hs := holes.filter(func(h): return mid > h[0] and mid < h[1] and h[4] != "win")
		for h in hs:
			lo = maxf(lo, h[3])
		var hi := minf(3.4, minf(top_at.call(s0), top_at.call(s1)))
		if hi > lo + 0.05:
			var c2: Vector2 = a + dir * mid
			_col(Vector3(c2.x, FL + (lo + hi) * 0.5, c2.y), Vector3(s1 - s0, hi - lo, T), Basis(Vector3.UP, -atan2(dir.y, dir.x)))
	# 窓と戸の見た目
	for h in holes:
		var c3: Vector2 = a + dir * (h[0] + h[1]) * 0.5
		var w: float = h[1] - h[0]
		var bs := Basis(Vector3.UP, -atan2(dir.y, dir.x))
		if h[4] == "win":
			_box("glass", Vector3(c3.x, FL + (h[2] + h[3]) * 0.5, c3.y), Vector3(w, h[3] - h[2], 0.05), bs)
			_box("log", Vector3(c3.x, FL + h[2] - 0.04, c3.y), Vector3(w + 0.12, 0.08, T + 0.1), bs)
		elif h[4] == "door":
			_box("door", Vector3(c3.x, FL + (h[2] + h[3]) * 0.5, c3.y), Vector3(w, h[3] - h[2], 0.08), bs)


func _quad(st: SurfaceTool, q: Array, n: Vector3) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.add_vertex(q[k])


## 窓を等しい間で並べた穴の列（長さ L の壁に、幅 w の窓を bay ごとに）
static func _windows(L: float, w: float, bay: float, sill: float, head: float) -> Array:
	var n := maxi(1, int(L / bay))
	var gap := (L - n * w) / (n + 1)
	var out := []
	for k in n:
		var s0 := gap + k * (w + gap)
		out.append([s0, s0 + w, sill, head, "win"])
	return out


func _walls() -> void:
	var hz := T * 0.5
	# 休憩室: ゲレンデの側は大きな窓、駐車場の側は小さな窓。南東の妻は高い所に小窓
	var rl := REST_U.y - REST_U.x
	_pwall(Vector2(REST_U.x, HALL_V.y - hz), Vector2(REST_U.y, HALL_V.y - hz), _windows(rl, 2.3, 2.9, 0.6, 2.55))
	_pwall(Vector2(REST_U.x, HALL_V.x + hz), Vector2(REST_U.y, HALL_V.x + hz), _windows(rl, 1.6, 2.9, 1.2, 2.3))
	_pwall(Vector2(REST_U.y - hz, HALL_V.x), Vector2(REST_U.y - hz, HALL_V.y), [[3.7, 5.3, REST_EAVE + 0.6, REST_EAVE + 1.4, "win"]])
	# 厨房の差し掛け: 低い箱、裏口と小窓
	_span("board", Vector3(KITCHEN_U.x, FL, HALL_V.x), Vector3(KITCHEN_U.y, FL + KITCHEN_EAVE, HALL_V.y), true)
	_span("glass", Vector3(KITCHEN_U.y, FL + 1.0, -3.4), Vector3(KITCHEN_U.y + 0.04, FL + 2.0, -1.4))
	_span("door", Vector3(KITCHEN_U.y, FL, 2.0), Vector3(KITCHEN_U.y + 0.05, FL + 2.1, 3.6))
	# ホールの壁（u = ±2.25）。北西の棟へは開き戸、休憩室へは大きく開ける。風除室の所には壁がない（広い風除室）
	_pwall(Vector2(HALL_U.x + hz, WING_V.x), Vector2(HALL_U.x + hz, HALL_V.y), [[-1.2 - WING_V.x, 1.2 - WING_V.x, 0.0, 2.2, "open"]])
	_pwall(Vector2(HALL_U.y - hz, HALL_V.x), Vector2(HALL_U.y - hz, HALL_V.y), [[0.6, HALL_V.y * 2.0 - 0.6, 0.0, 2.8, "open"]])
	# 風除室の脇の壁（A 字の軒の線 u = ±5）。南は休憩室・北西の棟の壁から、北は休憩室の壁と北西の棟の壁から
	_pwall(Vector2(-VEST_U + hz, HALL_V.y), Vector2(-VEST_U + hz, VEST_V), [[1.2, 2.4, 1.0, 2.2, "win"]])
	_pwall(Vector2(VEST_U - hz, HALL_V.y), Vector2(VEST_U - hz, VEST_V), [[1.2, 2.4, 1.0, 2.2, "win"]])
	_pwall(Vector2(-VEST_U + hz, -VEST_V), Vector2(-VEST_U + hz, WING_V.x), [])
	_pwall(Vector2(VEST_U - hz, -VEST_V), Vector2(VEST_U - hz, HALL_V.x), [[1.0, 2.2, 1.0, 2.2, "win"]])
	# 風除室の外の壁（入口の妻。両側）: 柱の左にガラスの入口、右にゲレンデの側は券売の窓・駐車場の側は白い戸、その外に小窓。上は A 字の屋根の裏まで
	for s in [1.0, -1.0]:
		var z: float = s * (VEST_V - hz)
		var hs := [[GLASS_U.x + VEST_U, GLASS_U.y + VEST_U, 0.0, ENTRY_H, "open"], [VEST_U * 2.0 - 1.8, VEST_U * 2.0 - 0.6, 1.0, 2.2, "win"]]
		if s > 0.0:
			hs.append([TICKET_U.x + VEST_U, TICKET_U.y + VEST_U, 1.0, 2.1, "win"])
		else:
			hs.append([WHITE_U.x + VEST_U, WHITE_U.y + VEST_U, 0.0, 2.3, "open"])
		# 壁の線は、外から見て左が u の負の側になるよう、ゲレンデの側と駐車場の側で u を裏返さない（どちらも柱の左が u の負の側）
		_pwall(Vector2(-VEST_U, z), Vector2(VEST_U, z), hs)
		_glass_front(s)
		if s > 0.0:   # 券売の窓の下の台
			_box("frame", Vector3((TICKET_U.x + TICKET_U.y) * 0.5, FL + 0.97, z + s * 0.2), Vector3(TICKET_U.y - TICKET_U.x + 0.2, 0.06, 0.45))
		# マット: 外は写真の赤と青、中は緑
		var gc := (LEAVES_U.x + LEAVES_U.y) * 0.5
		_box("mat_in", Vector3(gc, FL + 0.012, s * (VEST_V - 1.0)), Vector3(2.0, 0.025, 1.2))
	# 北西の棟: 外の壁（窓 1 つずつ）と、端の戸口
	var wl := WING_U.y - WING_U.x
	_pwall(Vector2(WING_U.x, WING_V.y - hz), Vector2(HALL_U.x, WING_V.y - hz), _windows(wl, 1.4, 4.0, 1.0, 2.0))
	_pwall(Vector2(WING_U.x, WING_V.x + hz), Vector2(HALL_U.x, WING_V.x + hz), _windows(wl, 1.4, 4.0, 1.0, 2.0))
	_pwall(Vector2(WING_U.x + hz, WING_V.x), Vector2(WING_U.x + hz, WING_V.y), [[3.5, 5.5, 1.0, 2.0, "win"], [8.0, 9.7, 0.0, 2.1, "door"]])


# ---- 入口の妻（両面） --------------------------------------------------------------

func _gables() -> void:
	var apex := FL + A_EAVE + A_HALF * tan(A_PITCH)
	for s in [1.0, -1.0]:
		var zf: float = s * VEST_V
		# 梁の上の三角の板（妻の壁。A 字の屋根の裏まで）
		var y0 := FL + BEAM_Y + 0.2
		var w0 := A_HALF - (BEAM_Y + 0.2 - A_EAVE) / tan(A_PITCH)
		_tri("soffit", [Vector3(-w0, y0, zf + s * 0.08), Vector3(w0, y0, zf + s * 0.08), Vector3(0.0, apex - 0.35, zf + s * 0.08)], 0.06)
		# 横の丸太の梁 1 本（A 字の幅いっぱい）と看板（柱の右）
		var wb := A_HALF - (BEAM_Y - A_EAVE) / tan(A_PITCH)
		var zb: float = zf + s * 0.3
		_log(Vector3(-wb - 0.3, FL + BEAM_Y, zb), Vector3(wb + 0.3, FL + BEAM_Y, zb), 0.17)
		var gu := (LEAVES_U.x + LEAVES_U.y) * 0.5
		_box("sign", Vector3(gu, FL + BEAM_Y + 0.45, zb), Vector3(2.6, 0.5, 0.1))   # 看板（入口の上）
		# 拡声器（看板の左上）と時計（柱の右の梁）
		Lift.cyl(_s("metal"), Vector3(gu - 1.0, FL + BEAM_Y + 1.15, zb), Vector3(gu - 1.0, FL + BEAM_Y + 1.15, zb + s * 0.45), 0.2, 12)
		_box("metal", Vector3(gu - 1.0, FL + BEAM_Y + 0.85, zb), Vector3(0.06, 0.5, 0.06))
		Lift.cyl(_s("door"), Vector3(1.3, FL + BEAM_Y, zb + s * 0.16), Vector3(1.3, FL + BEAM_Y, zb + s * 0.2), 0.22, 18)
		# まんなかの丸太の柱 1 本（土間から頂まで）
		var zp: float = zf + s * 0.55
		_log(Vector3(0.0, 0.0, zp), Vector3(0.0, apex - 0.4, zp), POST_R, true)
		# 軒の灯り（入口の上の軒裏）
		_box("lamp", Vector3(gu, FL + BEAM_Y - 0.3, zf + s * 0.9), Vector3(0.3, 0.12, 0.3))
		_lights.append(Vector3(gu, FL + BEAM_Y - 0.5, zf + s * 1.2))


# ---- デッキと段 ----------------------------------------------------------------------

func _deck(r: Rect2, posts := true) -> void:
	_span("deck", Vector3(r.position.x, FL - 0.12, r.position.y), Vector3(r.end.x, FL, r.end.y), true)
	_col(Vector3(r.get_center().x, (FL - 0.12) * 0.5, r.get_center().y), Vector3(r.size.x, FL - 0.12, r.size.y))
	if posts:
		var x := r.position.x + 0.3
		while x < r.end.x:
			for z in [r.position.y + 0.15, r.end.y - 0.15]:
				_span("deck", Vector3(x - 0.07, 0.0, z - 0.07), Vector3(x + 0.07, FL - 0.12, z + 0.07))
			x += 2.4


## 段（z の向き）: z0 の床の縁から、s の向きへ地面まで下りる（踏み板 5 枚）。当たりは坂
func _steps(u: Vector2, z0: float, s: float) -> void:
	var n := 5
	for k in n:
		var y := FL * (n - k) / float(n + 1)
		var za := z0 + s * STEPS_LEN * k / float(n)
		var zb := z0 + s * STEPS_LEN * (k + 1) / float(n)
		_span("step", Vector3(u.x, y - 0.06, minf(za, zb)), Vector3(u.y, y + 0.04, maxf(za, zb)))
	var a := atan2(FL, STEPS_LEN)
	var slen := sqrt(FL * FL + STEPS_LEN * STEPS_LEN)
	_col(Vector3((u.x + u.y) * 0.5, FL * 0.5 - 0.1, z0 + s * STEPS_LEN * 0.5), Vector3(u.y - u.x, 0.2, slen), Basis(Vector3.RIGHT, a * s))


func _decks() -> void:
	# ゲレンデの側: 全長のデッキ（風除室の所は風除室）
	_deck(Rect2(WING_U.x, DECK_S_V.x, -VEST_U - WING_U.x, DECK_S_V.y - DECK_S_V.x))
	_deck(Rect2(VEST_U, DECK_S_V.x, REST_U.y - VEST_U, DECK_S_V.y - DECK_S_V.x))
	# 駐車場の側: 風除室の東
	_deck(DECK_N)
	# 風除室の前の土間（両側）と段
	for s in [1.0, -1.0]:
		var z0: float = s * VEST_V
		var z1: float = s * (VEST_V + PORCH.y)
		if s > 0.0:
			# ゲレンデの側: コンクリートの土間（雪と同じ高さ）と、雪の地面へのゆるい坂。土間に赤と青のマット
			_span("base", Vector3(-PORCH.x, FL - 0.3, z0), Vector3(PORCH.x, FL, z1 + 1.2), true)
			var a := atan2(FL, RAMP_LEN)
			var c := Vector3(0.0, FL * 0.5 - 0.15, z1 + 1.2 + RAMP_LEN * 0.5)
			var b := Basis(Vector3.RIGHT, a)
			_box("snow", c, Vector3(PORCH.x * 2.0 + 2.0, 0.3, RAMP_LEN / cos(a) + 0.2), b, true)
			_box("mat_red", Vector3((LEAVES_U.x + LEAVES_U.y) * 0.5, FL + 0.012, z1 + 0.1), Vector3(2.3, 0.025, 1.9))
			_box("mat_blue", Vector3(1.2, FL + 0.012, z1 + 0.1), Vector3(3.0, 0.025, 1.6))
		else:
			_span("base", Vector3(-PORCH.x, FL - 0.3, minf(z0, z1)), Vector3(PORCH.x, FL, maxf(z0, z1)), true)
			_box("mat_out", Vector3((LEAVES_U.x + LEAVES_U.y) * 0.5, FL + 0.012, s * (VEST_V + 0.45)), Vector3(1.8, 0.025, 0.7))
			var su: Vector2 = STEPS_U * s
			_steps(Vector2(minf(su.x, su.y), maxf(su.x, su.y)), z1, s)
	# デッキから斜面へ下りる段（ゲレンデの側の両端）
	_steps(Vector2(-9.5, -7.5), DECK_S_V.y, 1.0)
	_steps(Vector2(12.0, 14.0), DECK_S_V.y, 1.0)
	# 北西の端の戸口の土間と段（x の向きへ下りる）
	_deck(Rect2(WING_U.x - 1.2, 1.5, 1.2, 1.7), false)
	var n := 4
	for k in n:
		var y := FL * (n - k) / float(n + 1)
		var x1 := WING_U.x - 1.2 - 0.4 * k
		_span("deck", Vector3(x1 - 0.4, y - 0.06, 1.5), Vector3(x1, y + 0.04, 3.2))
	var a := atan2(FL, 1.6)
	_col(Vector3(WING_U.x - 2.0, FL * 0.5 - 0.1, 2.35), Vector3(sqrt(FL * FL + 2.56), 0.2, 1.7), Basis(Vector3.BACK, a))


# ---- 中 ----------------------------------------------------------------------------

## 休憩室: 白い壁、木の柱と方杖（窓の間）、木の天井（屋根の裏）、長机とオレンジの椅子、吊りの灯り。ホール: 木の床、A 字の屋根の裏
func _inside() -> void:
	var zi := HALL_V.y - T - 0.02
	_span("inner", Vector3(REST_U.x, FL, zi - 0.03), Vector3(REST_U.y - T, FL + REST_EAVE, zi))
	_span("inner", Vector3(REST_U.x, FL, -zi), Vector3(REST_U.y - T, FL + REST_EAVE, -zi + 0.03))
	_span("inner", Vector3(REST_U.y - T - 0.03, FL, -zi), Vector3(REST_U.y - T, FL + REST_EAVE, zi))
	# 木の柱と方杖（窓の間ごと。両側）
	var x := REST_U.x + 0.4
	while x < REST_U.y - 0.3:
		for z in [zi - 0.15, -zi + 0.15]:
			_span("log", Vector3(x - 0.12, FL, z - 0.12), Vector3(x + 0.12, FL + REST_EAVE, z + 0.12))
			var dz := -0.7 if z > 0.0 else 0.7
			Lift.cyl(_s("log"), Vector3(x, FL + REST_EAVE - 0.9, z), Vector3(x, FL + REST_EAVE - 0.1, z + dz), 0.06, 6)
		x += 2.9
	# 梁（壁の上を長い辺に沿って）
	for z in [zi - 0.15, -zi + 0.15]:
		_span("log", Vector3(REST_U.x, FL + REST_EAVE - 0.25, z - 0.15), Vector3(REST_U.y - T, FL + REST_EAVE, z + 0.15))
	# 長机とオレンジの椅子: 3 列
	x = REST_U.x + 2.2
	while x < REST_U.y - 1.5:
		for z in [-2.6, 0.0, 2.6]:
			_table(Vector3(x, FL, z))
		x += 3.0
	# 灯り（今までのロッジの吊り灯り）
	x = REST_U.x + 2.5
	while x < REST_U.y - 1.0:
		_hang("res://props/furniture/pendant_drum.glb", Vector3(x, 0.0, 0.0), FL + 2.6)   # 傘の下端は床から 2.6 m（休憩室の軒 3.0 m より少し下）
		_lights.append(Vector3(x, FL + 2.85, 0.0))   # 灯りの芯は傘の中（椅子のすぐ上に置くと、近い物が白く飛ぶ）
		x += 4.5
	# ホールの中の白い壁（写真の中は白い壁に木の柱）
	var hx := HALL_U.y - T * 0.5 - 0.02
	_span("inner", Vector3(hx, FL + 2.8, HALL_V.x), Vector3(hx - 0.03, FL + 3.4, HALL_V.y))
	_span("inner", Vector3(-hx, FL + 2.2, -1.2), Vector3(-hx + 0.03, FL + 3.4, 1.2))
	_span("inner", Vector3(-hx, FL, HALL_V.x), Vector3(-hx + 0.03, FL + 3.4, -1.2))
	_span("inner", Vector3(-hx, FL, 1.2), Vector3(-hx + 0.03, FL + 3.4, HALL_V.y))
	# 吹き抜けのホールの吊り灯り（今までのロッジのこたつの上の筒の灯り）
	for z in [-5.5, 0.0, 5.5]:
		_hang("res://props/furniture/pendant_drum.glb", Vector3(0.0, 0.0, z), FL + 3.2)
		_lights.append(Vector3(0.0, FL + 3.45, z))


## 今までのロッジの吊り灯りを、屋根の裏からコードで吊る。y_bottom は傘の下端の高さ（地面から）。
## 2026-11-09 代表「ライト低すぎ」: glb の大きさにはコード（2 m）も入っていて、上端で合わせると傘が机の上まで下りていた。傘の下端で合わせる
func _hang(path: String, at: Vector3, y_bottom: float) -> void:
	var lamp := Props.make(path)
	add_child(lamp)
	var box := AABB()
	var first := true
	for mi in lamp.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (lamp.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	lamp.position = Vector3(at.x, y_bottom - box.position.y, at.z)
	var cord_top := y_bottom + box.size.y   # glb のコードの上端
	var ceil_y := _env(at.x, at.z) - ROOF_T
	if ceil_y > cord_top:
		Lift.cyl(_s("metal"), Vector3(at.x, cord_top, at.z), Vector3(at.x, ceil_y, at.z), 0.012, 4)


## 長机 1 つ（2.0 × 0.8 m）とオレンジの椅子 6 脚
func _table(c: Vector3) -> void:
	_box("table", c + Vector3(0, 0.7, 0), Vector3(2.0, 0.05, 0.8))
	for sx in [-0.9, 0.9]:
		for sz in [-0.33, 0.33]:
			_box("table", c + Vector3(sx, 0.34, sz), Vector3(0.05, 0.68, 0.05))
	_col(c + Vector3(0, 0.36, 0), Vector3(2.0, 0.72, 0.8))
	for sx in [-0.65, 0.0, 0.65]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(sx, 0.0, sz * 0.68)
			_box("chair", p + Vector3(0, 0.44, 0), Vector3(0.42, 0.06, 0.4))
			_box("chair", p + Vector3(0, 0.72, sz * 0.19), Vector3(0.42, 0.42, 0.05))
			for lx in [-0.18, 0.18]:
				for lz in [-0.17, 0.17]:
					_box("table", p + Vector3(lx, 0.21, lz), Vector3(0.025, 0.42, 0.025))


# ---- 戸（今までのロッジの自動ドアと開き戸と同じ動き） ------------------------------------
## 2026-11-09 代表「出入り口のドアがあかなかったり」: 入口のガラスの戸は自動ドア（人が前後 3 m に入ると左右へ引き分ける）、
## 白い戸とホールから北西の棟への戸は開き戸（近づいた人の向こう側へ開く）。当たりはない（今までのロッジと同じ。開口は通れる）

const AUTO_REACH := 3.0
const SWING_OPEN := deg_to_rad(95.0)
const SWING_REACH := 2.0

var _autos := []
var _swings := []


## 戸の板 1 枚（幅 w・高さ h・厚さ th）。glass なら鉄の框にガラス、でなければ板
func _leaf(w: float, h: float, glass: bool) -> Node3D:
	var n := Node3D.new()
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	if glass:
		var f := 0.08
		Lift.box(frame, Vector3(0, 0.9, 0), Vector3(w, 0.05, 0.06))   # 押し桟
		Lift.box(frame, Vector3(0, f * 0.5, 0), Vector3(w, f, 0.05))
		Lift.box(frame, Vector3(0, h - f * 0.5, 0), Vector3(w, f, 0.05))
		Lift.box(frame, Vector3(-w * 0.5 + f * 0.5, h * 0.5, 0), Vector3(f, h, 0.05))
		Lift.box(frame, Vector3(w * 0.5 - f * 0.5, h * 0.5, 0), Vector3(f, h, 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = frame.commit()
		mi.material_override = _material("frame")
		n.add_child(mi)
		var gl := SurfaceTool.new()
		gl.begin(Mesh.PRIMITIVE_TRIANGLES)
		Lift.box(gl, Vector3(0, h * 0.5, 0), Vector3(w - 0.1, h - 0.1, 0.02))
		var gm := MeshInstance3D.new()
		gm.mesh = gl.commit()
		gm.material_override = _material("glass")
		n.add_child(gm)
	else:
		Lift.box(frame, Vector3(0, h * 0.5, 0), Vector3(w, h, 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = frame.commit()
		mi.material_override = _material("door")
		n.add_child(mi)
		var knob := SurfaceTool.new()
		knob.begin(Mesh.PRIMITIVE_TRIANGLES)
		Lift.box(knob, Vector3(w * 0.5 - 0.1, 1.0, 0), Vector3(0.04, 0.16, 0.12))
		var km := MeshInstance3D.new()
		km.mesh = knob.commit()
		km.material_override = _material("metal")
		n.add_child(km)
	return n


## ガラスの入口の嵌め殺しの部分（両開きの左右）と、框の縦の柱
func _glass_front(s: float) -> void:
	var z: float = s * (VEST_V - T * 0.5)
	for seg in [Vector2(GLASS_U.x, LEAVES_U.x), Vector2(LEAVES_U.y, GLASS_U.y)]:
		_box("glass", Vector3((seg.x + seg.y) * 0.5, FL + ENTRY_H * 0.5, z), Vector3(seg.y - seg.x, ENTRY_H, 0.03))
		_col(Vector3((seg.x + seg.y) * 0.5, FL + ENTRY_H * 0.5, z), Vector3(seg.y - seg.x, ENTRY_H, 0.1))
	for u in [GLASS_U.x, LEAVES_U.x, LEAVES_U.y, GLASS_U.y]:
		_box("frame", Vector3(u, FL + ENTRY_H * 0.5, z), Vector3(0.1, ENTRY_H, 0.14))
	_box("frame", Vector3((GLASS_U.x + GLASS_U.y) * 0.5, FL + ENTRY_H - 0.05, z), Vector3(GLASS_U.y - GLASS_U.x + 0.1, 0.1, 0.14))


func _sensor(center: Vector3, size: Vector3) -> Area3D:
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	area.add_child(cs)
	area.position = center
	add_child(area)
	return area


func _doors() -> void:
	var hz := T * 0.5
	for s in [1.0, -1.0]:
		# 木の框のガラスの両開き（写真）。近づいた人の向こう側へ開く
		var z: float = s * (VEST_V - hz)
		var lw := (LEAVES_U.y - LEAVES_U.x) * 0.5
		_add_swing([[Vector3(LEAVES_U.x, FL, z), Vector3(1, 0, 0), lw], [Vector3(LEAVES_U.y, FL, z), Vector3(-1, 0, 0), lw]], Vector3(0, 0, s), true, ENTRY_H - 0.05)
		if s < 0.0:   # 駐車場の側の白い開き戸（柱から遠い側に蝶番）
			_add_swing([[Vector3(WHITE_U.y, FL, z), Vector3(-1, 0, 0), WHITE_U.y - WHITE_U.x]], Vector3(0, 0, s), false, 2.3)
	# ホールから北西の棟への両開き（u = -2.25、v = -1.2〜1.2）
	var hx := HALL_U.x + hz
	_add_swing([[Vector3(hx, FL, -1.2), Vector3(0, 0, 1), 1.2], [Vector3(hx, FL, 1.2), Vector3(0, 0, -1), 1.2]], Vector3(1, 0, 0), false, 2.2)


## 開き戸: leaves = [[蝶番の位置, 蝶番から板の先への向き, 幅]]、normal は戸の面に垂直な向き
func _add_swing(leaves: Array, normal: Vector3, glass: bool, h: float) -> void:
	var d := {"pivots": [], "signs": [], "normal": normal, "side": 0, "a": 0.0}
	var center := Vector3.ZERO
	for lf in leaves:
		var hinge: Vector3 = lf[0]
		var along: Vector3 = lf[1]
		var w: float = lf[2]
		var pivot := Node3D.new()
		pivot.position = hinge
		pivot.rotation.y = atan2(-along.z, along.x)   # 板の x を along へ
		add_child(pivot)
		var leaf := _leaf(w, h, glass)
		leaf.position = Vector3(w * 0.5, 0, 0)
		pivot.add_child(leaf)
		d.pivots.append(pivot)
		d.signs.append(1.0 if Vector3.UP.cross(along).dot(normal) > 0.0 else -1.0)
		center += hinge + along * w * 0.5
	center /= leaves.size()
	d["center"] = center
	d["base"] = (d.pivots as Array).map(func(p): return (p as Node3D).rotation.y)
	d["area"] = _sensor(center + Vector3(0, 1.2, 0), Vector3.ONE * 0.6 + (Vector3.ONE - normal.abs()) * 2.4 + normal.abs() * SWING_REACH * 2.0)
	_swings.append(d)


func _someone(area: Area3D) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for b in area.get_overlapping_bodies():
		if b is CharacterBody3D:
			var dd: float = (b as Node3D).global_position.distance_to(area.global_position)
			if dd < bd:
				bd = dd
				best = b
	return best


func _process(dt: float) -> void:
	for d in _autos:
		var on := _someone(d.area) != null
		d.open = move_toward(d.open, 1.0 if on else 0.0, dt / (0.9 if on else 1.6))
		var e: float = d.open * d.open * (3.0 - 2.0 * d.open)
		for k in d.leaves.size():
			var leaf: Node3D = d.leaves[k]
			leaf.position.x = d.home[k] + d.dir[k] * (GLASS_U.y - GLASS_U.x) * 0.5 * e
	for d in _swings:
		var near := _someone(d.area)
		if near and d.side == 0:   # 閉まっている戸を、人の向こう側へ開く
			d.side = -1 if (to_local(near.global_position) - d.center).dot(d.normal) > 0.0 else 1
		d.a = move_toward(d.a, 1.0 if near else 0.0, dt / (0.45 if near else 1.2))
		if d.a <= 0.0:
			d.side = 0
		var e: float = d.a * d.a * (3.0 - 2.0 * d.a)
		for k in d.pivots.size():
			(d.pivots[k] as Node3D).rotation.y = d.base[k] + d.signs[k] * d.side * SWING_OPEN * e
