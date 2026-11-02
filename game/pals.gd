extends RefCounted
## 頭・肩に載せる小物（perch）と、連れて歩くミニオン（pet）の品書き。形は person/pets/build_pets.py で作った glb（game/pals/）。
## どれも代表の参考ボードの折り紙・ペーパークラフト・フェルトの作品から取った（毛糸玉だけはボードになく、手芸の素材から）。
## 一覧と値段は代表が絵（person/pets/renders/01〜03）を見て決めた（2026-11-01）。値段は木のボタンの何個分。0 ははじめから持っている。
## 頭・肩の小物を売る所と付け替える所は、2 階の衣装掛けの横の紙細工屋さん（paper_lady.gd と paper_shop_ui.gd。2026-11-02）。
## 身につけられるのは、頭に 1 つ・肩に 1 つ・連れ 1 匹。出来事は craft.gd の pal_buy・pal_wear（通信ではほかの人の画面にも出る）

const Look := preload("res://look.gd")

## 頭・肩の小物: 名前 → {slot 載せる所, price, move 動き}。
## move: bird 首を振ってかしげ、ときどき羽をつくろう / crane 羽をゆっくり上下 / hover 肩の上に浮いて羽ばたく /
##       squirrel しっぽを振る / chameleon ゆっくり見回し、しっぽを巻き直す / rabbit 月の上の兎が見回す / thing 物（揺れるだけ）
const PERCH := {
	"chiyo_bird": {"slot": "head", "price": 0, "move": "bird"},
	"blue_bird": {"slot": "shoulder", "price": 30, "move": "bird"},
	"acorn": {"slot": "head", "price": 40, "move": "thing"},
	"crane": {"slot": "head", "price": 60, "move": "crane"},
	"pumpkin": {"slot": "head", "price": 80, "move": "thing"},
	"maple": {"slot": "head", "price": 100, "move": "thing"},
	"hummingbird": {"slot": "shoulder", "price": 150, "move": "hover"},
	"squirrel": {"slot": "head", "price": 200, "move": "squirrel"},
	"chameleon": {"slot": "shoulder", "price": 300, "move": "chameleon"},
	"moon_rabbit": {"slot": "head", "price": 500, "move": "rabbit"},
	"phoenix": {"slot": "shoulder", "price": 1000, "move": "bird"},
}
const PERCH_ORDER := ["chiyo_bird", "blue_bird", "acorn", "crane", "pumpkin", "maple", "hummingbird", "squirrel", "chameleon", "moon_rabbit", "phoenix"]

## ミニオン: 名前 → {price, gait 歩き方, speed 歩く速さの上限 (m/s), size 座った背丈 (m), step 1 歩の長さ (m)}。
## gait: trot 四つ足で歩く / hop 跳ねる / roll 転がる / strut 二本足で首を振って歩く
const PET := {
	"kit": {"price": 0, "gait": "trot", "speed": 7.0, "step": 0.32},
	"frog": {"price": 40, "gait": "hop", "speed": 6.0, "step": 0.5},
	"rabbit": {"price": 80, "gait": "hop", "speed": 7.0, "step": 0.6},
	"yarn": {"price": 120, "gait": "roll", "speed": 7.0, "step": 0.69},
	"chiyo_fox": {"price": 300, "gait": "trot", "speed": 7.0, "step": 0.32},
	"pony": {"price": 800, "gait": "trot", "speed": 8.0, "step": 0.4},
	"peacock": {"price": 1500, "gait": "strut", "speed": 6.0, "step": 0.22},
}
const PET_ORDER := ["kit", "frog", "rabbit", "yarn", "chiyo_fox", "pony", "peacock"]
const SLOTS := ["head", "shoulder", "pet"]
const START := ["chiyo_bird", "kit"]   # はじめから持っている（標準。いまの小鳥と子狐）
const START_WEAR := {"head": "chiyo_bird", "shoulder": "", "pet": "kit"}

## 人形ごとの載せる所（glb の座標、人形の大きさのまま。前は -Z、右は +X）。
## 頭は頭のいちばん上（companions.gd の前の PERCH と同じ）: kasa は笠の先、origami は頭巾の上、news は頭巾の前寄りの上、
## robo は箱の頭の上、musha は兜の鉢、ningyo は髪の上、golem は小さな頭の雪の上。
## 肩は右の肩: 腕の付け根の少し内側を、首の高さから下へ探って当たった面（build_pets.py --sheet dolls の PERCH の出力）。
## kasa は笠のつばの下、golem は大きな肩当ての上
const HEAD := {"kasa": Vector3(0, 1.372, 0.0), "origami": Vector3(0, 1.49, 0.0), "news": Vector3(0, 0.955, -0.04),
	"robo": Vector3(0, 0.79, 0.03), "musha": Vector3(0, 0.745, 0.02), "ningyo": Vector3(0, 0.89, 0.02), "golem": Vector3(0, 1.235, -0.12)}
const SHOULDER := {"kasa": Vector3(0.11, 0.84, 0.0), "origami": Vector3(0.145, 1.04, 0.0), "news": Vector3(0.128, 0.54, 0.0),
	"robo": Vector3(0.162, 0.463, 0.0), "musha": Vector3(0.111, 0.441, 0.0), "ningyo": Vector3(0.094, 0.643, 0.0), "golem": Vector3(0.357, 0.941, 0.04)}

const SHOULDER_BONE := {"kasa": "head"}   # 肩の物を付ける骨（書いていない人形は chest）


static func slot_of(key: String) -> String:
	if PERCH.has(key):
		return String(PERCH[key].slot)
	return "pet" if PET.has(key) else ""


static func price(key: String) -> int:
	if PERCH.has(key):
		return int(PERCH[key].price)
	return int(PET[key].price) if PET.has(key) else -1


## その載せる所（slot）の品物の並び（売り台の札の順）
static func keys_of(slot: String) -> Array:
	if slot == "pet":
		return PET_ORDER
	return PERCH_ORDER.filter(func(k): return PERCH[k].slot == slot)


static func scene(key: String) -> PackedScene:
	return load("res://pals/%s_%s.glb" % ["pet" if PET.has(key) else "perch", key]) as PackedScene


## 部品の節点の名前から、Blender の重なりよけの番号（.001・_001）を外す
static func part_name(n: Node) -> String:
	var s := String(n.name)
	var i := s.find(".")
	if i < 0:
		var j := s.rfind("_")
		if j > 0 and s.substr(j + 1).is_valid_int():
			i = j
	return s.substr(0, i) if i >= 0 else s


# ---------------------------------------------------------------- 素材

static var _mats := {}
static var _table := {}
static var _pats := {}


## glb の素材の名前（game/pals/mats.json の表）を、look.gd の紙・フェルト・毛糸に置き換える。
## 面ごとの明るさの違い（折り紙の面の陰。頂点の色）を掛ける
static func paint(root: Node, layers := -1) -> void:
	if _table.is_empty():
		var f := FileAccess.open("res://pals/mats.json", FileAccess.READ)
		if f:
			_table = JSON.parse_string(f.get_as_text())
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if layers >= 0:
			m.layers = layers
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			var mat := material(key)
			if mat:
				m.set_surface_override_material(i, mat)


static func material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	if not _table.has(key):
		return null
	var spec: Array = _table[key]
	var col := Color("#" + String(spec[1]))
	var m: StandardMaterial3D
	match String(spec[0]):
		"felt":
			m = Look.felt(col, 3.0)
		"yarn":
			m = Look.knit(col, 14.0)
		"plain":
			m = StandardMaterial3D.new()
			m.albedo_color = col
			m.roughness = 0.35 if key in ["ink", "brass"] else 0.7
			m.metallic = 0.6 if key == "brass" else 0.0
		_:
			m = Look.paper(col)
			if spec[2] != null:
				var pat: Array = spec[2]
				m.albedo_color = Color.WHITE
				m.albedo_texture = _pattern(String(pat[0]), col, Color("#" + String(pat[1])), Color("#" + String(pat[2])) if pat[2] != null else Color("#" + String(pat[1])))
				m.uv1_scale = Vector3.ONE * (12.0 if pat[0] in ["seigaiha", "shippo"] else 6.0)
	m.vertex_color_use_as_albedo = true   # 面ごとの明るさの違い
	_mats[key] = m
	return m


## 千代紙の柄（triplanar で貼る 128 px の繰り返し）。青海波は look.gd の和柄と同じ描き方
static func _pattern(kind: String, base: Color, ink: Color, ink2: Color) -> Texture2D:
	var key := "%s %s" % [kind, base.to_html()]
	if _pats.has(key):
		return _pats[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	img.fill(base)
	match kind:
		"seigaiha":
			for y in s:
				for x in s:
					if Look._wagara_ink("seigaiha", x, y, s):
						img.set_pixel(x, y, ink)
		"shippo":   # 重なった円の輪（七宝）
			var r := s / 4.0
			for y in s:
				for x in s:
					for o in [Vector2(0, 0), Vector2(r, r)]:
						var p := Vector2(fposmod(x - o.x, r * 2.0) - r, fposmod(y - o.y, r * 2.0) - r)
						if absf(p.length() - r * 1.414 * 0.7) < 1.6:
							img.set_pixel(x, y, ink)
		"sakura":   # 散らした五弁の花と、小さな葉
			for i in 9:
				var c := Vector2(rng.randf() * s, rng.randf() * s)
				var rr := 8.0 + rng.randf() * 5.0
				var col := ink if i % 3 else ink2
				for y in range(-16, 17):
					for x in range(-16, 17):
						var d := Vector2(x, y)
						var a := d.angle()
						if d.length() < rr * (0.62 + 0.38 * absf(cos(2.5 * a + i))):
							img.set_pixel(posmod(int(c.x) + x, s), posmod(int(c.y) + y, s), Color("#E8C25A") if d.length() < rr * 0.2 else col)
		"sumi":   # 文字に見えない、墨の短い筆の線
			for i in 18:
				var c := Vector2(rng.randf() * s, rng.randf() * s)
				var ang := rng.randf() * PI
				var ln := 4.0 + rng.randf() * 7.0
				var dir := Vector2(cos(ang), sin(ang))
				for k in range(-int(ln), int(ln) + 1):
					var w := 1.4 * (1.0 - absf(k) / (ln + 1.0)) + 0.4
					for j in range(-2, 3):
						if absf(j) <= w:
							var p := c + dir * k + dir.orthogonal() * j
							img.set_pixel(posmod(int(p.x), s), posmod(int(p.y), s), ink)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_pats[key] = tex
	return tex
