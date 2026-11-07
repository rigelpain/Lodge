extends RefCounted
## 雪玉ころがしの手袋（2026-11-08 代表「雪玉ころがしは手袋を買って装備したらできるようにしましょう」「手に厚い毛糸の手袋」
## 「や、やっぱ性能差付けて山師に売らせよう」。差は「押す力」「育つ速さ」「玉の丈夫さ」、3 段階で 100・500・1500）。
## 山師の棚（mountain_goods.gd）で買う。買った手袋は持ち物の場所を使わず、装備の枠に入ってすぐはまる（craft.gd の buy・equip の gear "gloves"）。
## はめているあいだ、しゃがんで F を押し続けて大玉の種を置け、大玉を押せる（player.gd。big_ball.gd）。人形の両手（doll.gd）と一人称の手（player.gd）が手袋になる。
##
## 段ごとの差（GRADES。どれも代表が遊んで決める前の仮の値）:
##   push  押す力の倍率（big_ball.gd の PUSH_FORCE に掛ける）。一人で押せる大きさが、毛糸 半径 0.9 m・フェルト 1.1 m・革 1.3 m ほど
##   grow  育つ速さの倍率。玉は、押した人の手袋のうちいちばんよいもので固められ（big_ball.gd の pack）、それからは転がった道のりでこの倍だけ速く育つ
##   hard  丈夫さの倍率。固めた玉は、崩れる強さ（big_ball.gd の BREAK_DV）がこの倍になる
## 見た目: 毛糸（錆びた赤のメリヤス編みに生成りのゴム編みの縁）、フェルト（分厚い藍のフェルトに赤い糸の縫い目）、革（茶の革に生成りの毛皮の縁）

const Look := preload("res://look.gd")
const Icons := preload("res://hud_icons.gd")

const ORDER := ["gloves", "gloves_felt", "gloves_leather"]
const GRADES := {
	"gloves": {"name": "毛糸の手袋", "price": 100, "push": 1.0, "grow": 1.0, "hard": 1.0,
			"color": Color("C9543F"), "cuff": Color("EDE3CF")},
	"gloves_felt": {"name": "フェルトの手袋", "price": 500, "push": 1.6, "grow": 1.4, "hard": 1.3,
			"color": Color("2F4E8A"), "cuff": Color("B8402E")},
	"gloves_leather": {"name": "革の手袋", "price": 1500, "push": 2.5, "grow": 2.0, "hard": 1.7,
			"color": Color("4A2A18"), "cuff": Color("F1EBDD")},
}
const PUFF := 1.35               # 手の袋の太さ（手の長さに対する割合の 2 倍）。紙の手より一回り太い

static var _mats := {}


static func is_gloves(kind: String) -> bool:
	return GRADES.has(kind)


## 段の番号（毛糸 1・フェルト 2・革 3。手袋でなければ 0）
static func rank(kind: String) -> int:
	return ORDER.find(kind) + 1


static func stat(kind: String, key: String) -> float:
	return float(GRADES.get(kind, {}).get(key, 1.0))


static func price(kind: String) -> int:
	return int(GRADES.get(kind, {}).get("price", 99))


static func item_name(kind: String) -> String:
	return String(GRADES.get(kind, {}).get("name", "手袋"))


## 手の袋の材質（段ごと）
static func body_mat(kind: String) -> StandardMaterial3D:
	var key := kind + ":body"
	if not _mats.has(key):
		var g: Dictionary = GRADES.get(kind, GRADES["gloves"])
		var m: StandardMaterial3D
		match kind:
			"gloves_felt":
				m = Look.felt(g.color, 3.0)
				m.rim = 0.25
			"gloves_leather":
				m = StandardMaterial3D.new()
				m.albedo_color = g.color
				m.roughness = 0.5
				m.normal_enabled = true
				m.normal_texture = Look.fiber_normal(false)
				m.normal_scale = 0.35
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 6.0
			_:
				m = StandardMaterial3D.new()
				m.albedo_color = (g.color as Color).lerp(Color.WHITE, 0.08)
				m.albedo_texture = Look.knit_texture()
				m.roughness = 1.0
				m.normal_enabled = true
				m.normal_texture = Look.fiber_normal(true)
				m.normal_scale = 0.9
				m.uv1_triplanar = true
				m.uv1_scale = Vector3.ONE * 14.0   # 7 cm に 1 回（編み目が手の上で 4〜5 段に見える）
		_mats[key] = m
	return _mats[key]


## 縁の材質（毛糸はゴム編み、フェルトは赤い縁、革は毛皮）
static func cuff_mat(kind: String) -> StandardMaterial3D:
	var key := kind + ":cuff"
	if not _mats.has(key):
		var g: Dictionary = GRADES.get(kind, GRADES["gloves"])
		var m := Look.felt(g.cuff, 6.0)
		m.rim = 0.5 if kind == "gloves_leather" else 0.2
		_mats[key] = m
	return _mats[key]


## 片手の手袋。原点は手首、+y が指先の向き、side は 1 右 / -1 左（親指が内側 = -x × side）。hand は手の長さ (m)
static func mitten(kind: String, hand: float, side: int, layers := 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Glove"
	var bag := SphereMesh.new()
	bag.radius = 0.5
	bag.height = 1.0
	bag.radial_segments = 12
	bag.rings = 6
	var m := MeshInstance3D.new()
	m.mesh = bag
	m.material_override = body_mat(kind)
	m.layers = layers
	m.scale = Vector3(hand * PUFF * 0.62, hand * 1.25, hand * PUFF * 0.42)
	m.position = Vector3(0, hand * 0.55, 0)
	root.add_child(m)
	var th := MeshInstance3D.new()
	th.mesh = bag
	th.material_override = body_mat(kind)
	th.layers = layers
	th.scale = Vector3(hand * 0.32, hand * 0.62, hand * 0.3)
	th.position = Vector3(-hand * 0.38 * side, hand * 0.4, hand * 0.08)
	th.rotation = Vector3(0, 0, 0.55 * side)
	root.add_child(th)
	var rib := CylinderMesh.new()
	rib.top_radius = 0.5
	rib.bottom_radius = 0.55 if kind != "gloves_leather" else 0.62   # 革は毛皮の縁がふくらむ
	rib.height = 1.0
	rib.radial_segments = 14
	var c := MeshInstance3D.new()
	c.mesh = rib
	c.material_override = cuff_mat(kind)
	c.layers = layers
	c.scale = Vector3(hand * PUFF * 0.6, hand * (0.38 if kind != "gloves_leather" else 0.5), hand * PUFF * 0.46)
	c.position = Vector3(0, -hand * 0.05, 0)
	root.add_child(c)
	return root


## 品物の絵（64 × 64 の箱。中心が原点。Icons._o と _s は呼ぶ側が決める）: 手袋を 2 つ、少しずらして重ねる。段ごとの色と縁、
## 毛糸は編み目の V、フェルトは縁の赤い縫い目、革は毛皮の縁の毛羽
static func icon(ci: CanvasItem, kind: String, a := 1.0) -> void:
	var g: Dictionary = GRADES.get(kind, GRADES["gloves"])
	var wool: Color = g.color
	var cuff: Color = g.cuff
	for k in 2:
		var c := Vector2(-6.0 + 12.0 * k, 2.0 - 4.0 * k)
		var rot := -0.25 + 0.5 * k
		Icons.patch(ci, Icons.xf(Icons.rr(-9, -15, 18, 24, 9), rot, c, 1.0), wool.darkened(0.06 * (1 - k)), a, true)
		Icons.patch(ci, Icons.xf(Icons.ell(Vector2(-10.5, 0), 3.6, 6.5, 12), rot - 0.5, c, 1.0), wool.darkened(0.12), a, false)   # 親指
		match kind:
			"gloves_leather":   # 毛皮の縁: ふくらんだ生成りに、毛羽
				Icons.patch(ci, Icons.xf(Icons.rr(-11, 6, 22, 10, 5), rot, c, 1.0), cuff, a, true)
				for i in 5:
					var x := -8.0 + 4.0 * i
					Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(x, 6.0), Vector2(x + 1.0, 4.0)]), rot, c, 1.0), cuff.darkened(0.15), 1.0, 0.8 * a)
				Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-4, -11), Vector2(-5, -2), Vector2(-4, 4)]), rot, c, 1.0), wool.lightened(0.35), 1.0, 0.6 * a)   # 革の光
			"gloves_felt":   # 赤い縁と、手の甲の縫い目
				Icons.patch(ci, Icons.xf(Icons.rr(-9.5, 7, 19, 8, 2.5), rot, c, 1.0), cuff, a, true)
				Icons.dashes(ci, Icons.xf(Icons.rr(-6, -11, 12, 16, 6), rot, c, 1.0), cuff.lightened(0.2), 1.1, 2.4, 1.8, a, true)
			_:   # 毛糸: ゴム編みの縁と、編み目の V
				Icons.patch(ci, Icons.xf(Icons.rr(-9.5, 7, 19, 8, 2.5), rot, c, 1.0), cuff, a, true)
				for i in 4:
					var x := -6.0 + 4.0 * i
					Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(x, 8.0), Vector2(x, 14.0)]), rot, c, 1.0), cuff.darkened(0.25), 1.0, 0.8 * a)
				for j in 2:
					var y := -8.0 + 7.0 * j
					Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-5, y), Vector2(-2.5, y + 2.5), Vector2(0, y), Vector2(2.5, y + 2.5), Vector2(5, y)]), rot, c, 1.0), wool.lightened(0.3), 1.2, 0.8 * a)
	# 段の印: 段の数だけ、右下に小さな星（毛糸 1・フェルト 2・革 3。字を使わずに段が読める）
	for i in rank(kind):
		var p := Vector2(16.0 - i * 8.0, 20.0)
		Icons.patch(ci, Icons.circ(p, 3.2, 10), Color("E2B33C"), a, false)
