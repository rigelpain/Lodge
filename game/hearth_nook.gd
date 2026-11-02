extends Node3D
## ロッジ 1 階の暖炉と、そのまわりの居場所（2026-11-02 代表「暖炉がちゃっちい。暖炉前のベンチもなんか味気ない。
## まんなかに毛足の長いラグ、その周りに揺り椅子がいくつか、ビーズクッションがいくつか、大きなソファがいくつかって感じが良い」）。
## main.gd がロッジの目印 slot_hearth（暖炉の前の面のまんなか、床の高さ）に置く。品物の形は props/build_nook.py（game/props/nook/）。
##
## 並べ方の座標は build_nook.py の PLANS と同じ: 暖炉の前の面のまんなかが原点、+Y が部屋の側（ロッジでは南）、向きは度（0 で +Y を向く）。
## このノードは目印から 180° 回して置くので、子の位置は (X, 0, -Y)、向きは Y まわりに同じ度（glTF の前は -Z）。
##
## 席: 品物の glb の目印 seat_<番号>（座面の上の腰を下ろす所。build_nook.py が布の計算のあとの座面の高さに置く）から、
## 座る所の目印 nook_seat_<番号> を作り、seats.gd が拾う（種類・高さ・奥行き・揺れは meta）。
##   ソファ: 何人かで並んで座る（座る所が人数分）
##   揺り椅子: 座りきると前後に揺れる（人形も椅子といっしょに。弓の円の中心まわりに回すので、弓は床から離れない）
##   ビーズクッション: 座ると袋がつぶれて沈み込み、うしろへもたれる
## 揺れの角は、座っている人形（仲間分け dolls）の rock から読む。あなた・仲間・つないだ人の誰が座っても、その画面の人形と同じに揺れる。
## ラグの毛足はここで作る（シェルの層を重ねて、毛糸の房を立てる。glb にはしない）

const Props := preload("res://props.gd")
const Doll := preload("res://doll.gd")
const HearthFire := preload("res://hearth_fire.gd")

const DIR := "res://props/nook/"
const FIREPLACE := "fireplace_sweater"   # 案 3（2026-11-02 代表が選んだ）: 炉のまわりはフェルトの小石、煙突の胸はなわ編みのセーター
## ラグ: [柄, 横の半径, 奥行きの半径, X, Y]（北欧のリヤ。菱形の柄）
const RUG := ["rya", 2.6, 1.9, 0.0, 4.2]
## 家具: [glb の名前, X, Y, 向き（度）]。案 3「半円」（build_nook.py の PLANS の "3"）
const ITEMS := [
	["sofa_patch", -3.45, 5.9, -125], ["sofa_rust", 3.45, 5.9, 125],
	["rocker_indigo", -3.6, 1.7, -110], ["rocker_indigo", 3.6, 1.7, 110], ["rocker_indigo", 0.0, 7.4, 180],
	["bean_mustard", -1.3, 3.1, 200], ["bean_patch", 1.3, 3.1, 160], ["bean_mustard", -0.65, 4.85, 185], ["bean_patch", 0.85, 4.95, 175],
	["log_basket", -3.7, 0.5, 0],
]
## 居場所の入り口: [外の所, 内の所]（X, Y）。仲間（bot.gd）が、まっすぐ行けない内側の席へ、ここを通って回り込む
const ENTRIES := [[Vector2(-1.3, 9.2), Vector2(-1.1, 6.3)], [Vector2(1.3, 9.2), Vector2(1.1, 6.3)],
		[Vector2(-5.8, 2.6), Vector2(-3.0, 3.6)], [Vector2(5.8, 2.6), Vector2(3.0, 3.6)]]
## 種類ごとの座り方（seats.gd の席の meta）
const ROCK_AMP := 0.085       # 揺り椅子の揺れの角 (rad、片側)
const ROCK_PERIOD := 2.2      # 揺り椅子の 1 往復 (s)
const ROCK_PIVOT := Vector3(0.0, 1.435, 0.05)   # 揺り椅子の弓の円の中心（glb の座標。build_nook.py の R + 0.035 の高さ）
const BEAN_SINK := 0.12       # ビーズクッション: 座ると袋がこれだけ（割合）低くつぶれる
const BEAN_LEAN := 0.2        # ビーズクッション: うしろへもたれる角 (rad)
const SEAT_EDGE := {"sofa": 0.36, "rocker": 0.24, "beanbag": 0.3}   # 前へ出す前の値   # 腰の所から座面の前の縁まで (m)
## 腰の所を、glb の目印から前へ出す (m)。いちばん大きな巨人（golem）の背中が、背のクッション・背の棒に入らないように
const SEAT_FORWARD := {"sofa": 0.11, "rocker": 0.08, "beanbag": 0.0}
const SEAT_BACK := {"sofa": 0.25, "rocker": 0.28, "beanbag": 0.4}   # 腰の所から背もたれ（背のクッション・背の棒・袋のうしろ）の前の面まで (m)
const SEAT_SIZE := {"sofa": Vector2(0.86, 0.82), "rocker": Vector2(0.62, 0.5), "beanbag": Vector2(0.8, 0.7)}

var _rockers: Array = []      # [品物, 置いた形, 座る所の目印]
var _beans: Array = []        # [品物, 置いた形, 座る所の目印, いまのつぶれ 0〜1]
var _k := -1


func _ready() -> void:
	name = "HearthNook"
	rotation.y = PI
	var fp := _put(FIREPLACE, 0.0, 0.0, 0.0)
	var fire: Node3D = HearthFire.new()
	fp.add_child(fire)
	var rug := _make_rug(RUG[0], RUG[1], RUG[2])
	rug.position = Vector3(RUG[3], 0.0, -RUG[4])
	add_child(rug)
	var n := 0
	for it in ITEMS:
		var item := _put(it[0], it[1], it[2], it[3])
		var kind := _kind_of(it[0])
		for m in item.find_children("seat_*", "Node3D", true, false):
			var mk := Node3D.new()
			mk.name = "nook_seat_%02d" % n
			n += 1
			mk.position = item.to_local((m as Node3D).global_position) + Vector3(0.0, 0.0, -SEAT_FORWARD[kind])
			mk.position.y = _top_at(item, mk.position, mk.position.y)   # 座面の高さは、置いた形の面から測り直す
			mk.set_meta("kind", kind)
			mk.set_meta("height", mk.position.y)
			mk.set_meta("edge", SEAT_EDGE[kind] - SEAT_FORWARD[kind])
			mk.set_meta("size", SEAT_SIZE[kind])
			mk.set_meta("back", SEAT_BACK[kind] + SEAT_FORWARD[kind])
			if kind == "rocker":
				mk.set_meta("rock_amp", ROCK_AMP)
				mk.set_meta("rock_period", ROCK_PERIOD)
				mk.set_meta("rock_phase", float(n) * 1.7)   # 揺り椅子ごとに少しずらす
				mk.set_meta("rock_pivot", ROCK_PIVOT - mk.position)
			elif kind == "beanbag":
				mk.position.y *= 1.0 - BEAN_SINK   # 沈んだ所に腰を下ろす
				mk.set_meta("height", mk.position.y)
				mk.set_meta("rock_lean", BEAN_LEAN)
			add_child(mk)
			mk.transform = item.transform * mk.transform
			if kind == "rocker":
				_rockers.append([item, item.transform, mk])
			elif kind == "beanbag":
				_beans.append([item, item.transform, mk, 0.0])


func _kind_of(glb: String) -> String:
	if glb.begins_with("sofa"):
		return "sofa"
	if glb.begins_with("rocker"):
		return "rocker"
	if glb.begins_with("bean"):
		return "beanbag"
	return ""


## 品物を置く（手芸の素材を着せ、外形の箱の当たりを足す）。太陽の影は落とさない（ロッジの中）
func _put(glb: String, x: float, y: float, deg: float) -> Node3D:
	if not ResourceLoader.exists(DIR + glb + ".glb"):   # 書き出す前（確かめ用）: 置く所だけ
		var empty := Node3D.new()
		empty.position = Vector3(x, 0.0, -y)
		empty.rotation.y = deg_to_rad(deg)
		add_child(empty)
		return empty
	var item := Props.make(DIR + glb + ".glb")
	item.position = Vector3(x, 0.0, -y)
	item.rotation.y = deg_to_rad(deg)
	add_child(item)
	var box := AABB()
	var first := true
	for mi in item.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = item.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not first:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		if glb.begins_with("bean") or glb.begins_with("rocker"):   # 丸い袋・前後に伸びた弓: 外形の箱より内へ（そばの立つ所をふさがない）
			shape.size *= Vector3(0.7, 1.0, 0.7)
		col.shape = shape
		col.position = box.get_center()
		body.add_child(col)
		item.add_child(body)
	return item


## 品物の形の、p（品物の座標の x, z）の真上から下へ探って当たる、いちばん高い面の高さ（品物の座標）。なければ fallback
func _top_at(item: Node3D, p: Vector3, fallback: float) -> float:
	var best := -INF
	var inv := item.global_transform.affine_inverse()
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := inv * mi.global_transform
		var f := mi.mesh.get_faces()
		for i in range(0, f.size(), 3):
			var a := xf * f[i]
			var b := xf * f[i + 1]
			var c := xf * f[i + 2]
			if maxf(a.x, maxf(b.x, c.x)) < p.x or minf(a.x, minf(b.x, c.x)) > p.x or maxf(a.z, maxf(b.z, c.z)) < p.z or minf(a.z, minf(b.z, c.z)) > p.z:
				continue
			var hit = Geometry3D.ray_intersects_triangle(Vector3(p.x, 3.0, p.z), Vector3.DOWN, a, b, c)
			if hit != null:
				best = maxf(best, (hit as Vector3).y)
	return best if best > -INF else fallback


## 座っている人形（仲間分け dolls）のうち、目印 mk の席に座りきっているもの
func _sitter(mk: Node3D) -> Node:
	for d in get_tree().get_nodes_in_group("dolls"):
		var host := (d as Node).get_parent() as Node3D
		if host == null or d.act != Doll.Act.SIT or d.sit_stage < 1:
			continue
		var to := host.global_position - mk.global_position
		if absf(to.y) < 0.35 and Vector2(to.x, to.z).length() < 0.3:
			return d
	return null


## 12 コマ／秒で、揺り椅子を座っている人形と同じ角に傾け、ビーズクッションをつぶす
func _process(_dt: float) -> void:
	var k := Doll.frame_index()
	if k == _k:
		return
	_k = k
	for r in _rockers:
		var d = _sitter(r[2])
		var a: float = d.rock if d else 0.0
		var base: Transform3D = r[1]
		var piv := ROCK_PIVOT
		(r[0] as Node3D).transform = base * Transform3D(Basis(Vector3.RIGHT, a), piv - Basis(Vector3.RIGHT, a) * piv)
	for b in _beans:
		var d = _sitter(b[2])
		var goal := 1.0 if d and d.sit_stage == 2 else (0.5 if d else 0.0)
		b[3] = move_toward(b[3], goal, 0.34)   # 3 コマでつぶれる・ふくらむ
		var s: float = b[3] * BEAN_SINK
		(b[0] as Node3D).transform = (b[1] as Transform3D) * Transform3D(Basis.from_scale(Vector3(1.0 + s * 0.45, 1.0 - s, 1.0 + s * 0.45)), Vector3.ZERO)


## at（世界）から、内側の席の立つ所 to（世界）へ回り込む道（世界の点の列。外の所 → 内の所）。いちばん短い入り口
func route(at: Vector3, to: Vector3) -> Array:
	var best := []
	var best_d := INF
	for e in ENTRIES:
		var o := to_global(Vector3(e[0].x, 0.0, -e[0].y))
		var i := to_global(Vector3(e[1].x, 0.0, -e[1].y))
		var d := Vector2(at.x - o.x, at.z - o.z).length() + Vector2(o.x - i.x, o.z - i.z).length() + Vector2(i.x - to.x, i.z - to.z).length()
		if d < best_d:
			best_d = d
			best = [Vector3(o.x, at.y, o.z), Vector3(i.x, at.y, i.z)]
	return best


## ペット（companions.gd）が暖炉の前で寝る所（世界）。ラグの暖炉の側の縁に、人ごとに散らす
func pet_spot(i: int) -> Vector3:
	var t := float(posmod(i * 3, 7)) / 6.0 - 0.5
	return to_global(Vector3(RUG[3] + t * RUG[1] * 1.1, 0.0, -(RUG[4] - RUG[2] * 0.6 * (1.0 - absf(t)))))


# ---------------------------------------------------------------- 毛足の長いラグ

## 楕円のラグ: フェルトの土台に、毛糸の房のシェル（同じ楕円を少しずつ上に重ね、房の芯だけ残す）。描くのは 1 回
func _make_rug(pattern: String, rx: float, ry: float) -> MeshInstance3D:
	const LAYERS := 16
	const SEG := 64
	const PILE := 0.13   # 毛足の長さ (m)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l in LAYERS:
		var h := float(l) / float(LAYERS - 1)
		var grow := 1.0 + 0.05 * h   # 外の層ほど、縁から房が少しはみ出す
		var y := 0.006 + PILE * h
		for i in SEG:
			var a0 := TAU * i / SEG
			var a1 := TAU * (i + 1) / SEG
			for p in [Vector2.ZERO, Vector2(cos(a1), sin(a1)), Vector2(cos(a0), sin(a0))]:
				var q: Vector2 = p * Vector2(rx, ry) * grow
				st.set_normal(Vector3.UP)
				st.set_uv(q)
				st.set_uv2(Vector2(h, 0.0))
				st.add_vertex(Vector3(q.x, y, q.y))
	var mi := MeshInstance3D.new()
	mi.name = "Rug"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = _rug_shader()
	m.set_shader_parameter("radii", Vector2(rx, ry))
	m.set_shader_parameter("pattern", ["cream", "rings", "rya"].find(pattern))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _rug: Shader


static func _rug_shader() -> Shader:
	if _rug:
		return _rug
	_rug = Shader.new()
	_rug.code = RUG_SHADER
	return _rug


const RUG_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform vec2 radii = vec2(2.5, 1.75);
uniform int pattern = 0;     // 0 生成り一色、1 同心の輪、2 北欧のリヤ（菱形）
const float CELL = 0.06;     // 房の間隔 (m)

varying float h;

void vertex() {
	h = UV2.x;
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

vec3 hexc(float r, float g, float b) { return pow(vec3(r, g, b) / 255.0, vec3(2.2)); }

vec3 yarn(vec2 c, float v) {
	float e = length(c / radii);
	if (pattern == 1) {
		int k = int(min(e * 6.0, 5.0));
		vec3 ring[6] = vec3[](hexc(239.,230.,210.), hexc(201.,154.,58.), hexc(239.,230.,210.), hexc(168.,83.,46.), hexc(217.,201.,168.), hexc(168.,83.,46.));
		return ring[k];
	}
	if (pattern == 2) {
		if (e > 0.86) return hexc(46.,63.,102.);
		int k = int(mod(floor(abs(c.x) / 0.55 + abs(c.y) / 0.55), 4.0));
		vec3 rya[4] = vec3[](hexc(181.,99.,106.), hexc(201.,154.,58.), hexc(239.,230.,210.), hexc(110.,127.,74.));
		return v < 0.9 ? rya[k] : hexc(239.,230.,210.);
	}
	return v < 0.8 ? hexc(239.,230.,210.) : hexc(217.,201.,168.);
}

void fragment() {
	vec2 p = UV;
	if (h < 0.001) {   // 土台のフェルト（房のあいだに見える暗い所）
		if (length(p / radii) > 1.0) discard;
		ALBEDO = hexc(120., 108., 92.);
		ROUGHNESS = 1.0;
	} else {
		vec2 g = p / CELL;
		vec2 ip = floor(g);
		float best = 9.0;
		vec2 bc = vec2(0.0);
		float bv = 0.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 n = ip + vec2(float(i), float(j));
				vec2 o = hash2(n);
				vec2 dir = normalize(hash2(n + 17.0) - 0.5);
				vec2 c = n + o + dir * h * h * 0.9;   // 房は立ち上がってから倒れる
				float d = length(g - c);
				if (d < best) { best = d; bc = (n + o) * CELL; bv = hash2(n + 3.0).x; }
			}
		}
		float r = 0.62 * (1.0 - h * 0.5);
		if (best > r || length(bc / radii) > 0.985) discard;
		vec3 col = yarn(bc, bv) * (0.85 + 0.3 * bv);
		col *= mix(0.42, 1.08, h) * (1.0 - 0.25 * best / r);   // 根元は暗く、房の芯は明るい
		ALBEDO = col;
		ROUGHNESS = 1.0;
		SPECULAR = 0.2;
		BACKLIGHT = vec3(0.12);
	}
}
"""
