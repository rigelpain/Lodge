extends Node3D
## 乾燥機の胴の中で、回りながら踊る料理の中身（cook_motion.gd が置いて、1 コマごとに step で動かす）。
## 2026-11-01 代表「ラーメンとかになったらラーメンスープとか麺具材が中で回りながら踊っててほしい」。
## 中身は料理の模型（props/build_food.py）の部品を、フェルトの粒・毛糸の麺で大きく作り直したもの。料理ごとの並びは PIECES。
## 動きは胴といっしょに回りながら、1 拍（6 コマ）に 1 回はねる。はねて落ちたコマはつぶれ、上がるコマはのびる。
## 汁・麺・具の大きな物は拍の頭に落ちる（胴の回る音 cook_drum_loop の「ころん」は 0.5 秒＝6 コマごと。sound/gen/cook.py）。
## 置き方と動きは料理の名前とコマだけで決まる（乱数は料理の名前で種をまく）ので、通信ではどの画面でも同じに踊る

const Look := preload("res://look.gd")

## 料理 → [[形, 色, 数, 大きさ (m)], …]。形は _piece を見る。大きさは胴（半径 0.65 m）に合わせる
const PIECES := {
	"ramen": [["soup", "C8813A", 1, 0.17], ["drop", "C8813A", 3, 0.06], ["noodle", "EED07E", 3, 0.17], ["chashu", "7A4E34", 2, 0.13],
		["naruto", "FAF6EC", 1, 0.09], ["egg", "FAF6EC", 1, 0.09], ["sheet", "2C3A2E", 1, 0.15], ["ring", "7C9A5C", 4, 0.045],
		["stick", "C8925A", 2, 0.11], ["bead", "F6F7FA", 4, 0.03]],
	"udon": [["soup", "E6D5A6", 1, 0.17], ["drop", "E6D5A6", 3, 0.06], ["noodle_thick", "EFE6D2", 3, 0.15], ["tri", "C8925A", 1, 0.14],
		["kamaboko", "E59AA8", 1, 0.08], ["ring", "7C9A5C", 4, 0.045], ["bead", "F6F7FA", 4, 0.03]],
	"soba": [["soup", "C8813A", 1, 0.17], ["drop", "C8813A", 3, 0.06], ["noodle_thin", "6E5A48", 3, 0.15], ["lump", "C8925A", 1, 0.13],
		["ring", "7C9A5C", 4, 0.045], ["bead", "F6F7FA", 4, 0.03]],
	"yakisoba": [["noodle", "9A5A2A", 4, 0.19], ["flake", "7C9A5C", 4, 0.1], ["flake", "C8925A", 2, 0.09], ["stick", "D2553A", 3, 0.07],
		["bead", "F6F7FA", 4, 0.03]],
	"taiyaki": [["fish", "C98838", 1, 0.16], ["bead", "D2A04A", 6, 0.035], ["crumb", "C98A3E", 4, 0.03]],
	"nikuman": [["bun", "FAF6EC", 1, 0.17], ["bead", "D2A04A", 6, 0.035]],
	"korokke": [["patty", "D2A04A", 2, 0.14], ["bead", "D2A04A", 5, 0.035], ["crumb", "C98A3E", 6, 0.03]],
	"hashbrown": [["patty", "D2A04A", 1, 0.18], ["bead", "D2A04A", 6, 0.035], ["crumb", "E8C878", 4, 0.03]],
	"fries": [["stick", "E8C878", 7, 0.15], ["bead", "D2A04A", 6, 0.035]],
}
const HOP := 6               # はねる間（コマ。1 拍）

var _bits: Array = []        # [node, 奥行き, 半径, 位相, はねる高さ, ずれ, 回る軸, 回る速さ]
var _born := 0               # 置いたコマ（ぽんと出てくる）


static func has(dish: String) -> bool:
	return PIECES.has(dish)


## 料理 dish の中身を作る（胴の中で回るのは step）
func build(dish: String, born: int) -> void:
	_born = born
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(dish)
	var list: Array = PIECES.get(dish, [])
	var n := 0
	for p in list:
		n += int(p[2])
	var i := 0
	for p in list:
		for k in int(p[2]):
			var node := _piece(String(p[0]), Color(String(p[1])), float(p[3]), rng)
			add_child(node)
			var big := float(p[3]) > 0.08
			var sz := float(p[3]) * (1.5 if p[0] in ["soup", "fish", "patty"] else 1.0)   # 横に長い物は半径から引く
			_bits.append([node,
				rng.randf_range(-0.35, 0.25),                       # 奥行き（胴の真ん中から戸の側へ）
				rng.randf_range(0.4, 0.6 - sz),                   # 胴の軸からの半径（胴の壁 0.65 m の内側で、壁ぎわを回る）
				TAU * float(i) / n + rng.randf_range(-0.2, 0.2),   # 回る位相（ばらして散らす）
				rng.randf_range(0.1, 0.18) if big else rng.randf_range(0.12, 0.26),  # はねる高さ
				0 if big else rng.randi_range(0, HOP - 1),          # はねるコマのずれ（大きな物は拍の頭に落ちる: 胴の音「ごろごろ」の当たりと同じ）
				Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
				rng.randf_range(0.25, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0)])
			i += 1


## コマ f: 胴の真ん中 c、戸の向き fw、胴の回った角 a のときの中身の居場所
func step(f: int, c: Vector3, fw: Vector3, a: float) -> void:
	var age := f - _born
	var pop: float = [0.35, 0.7, 1.0][age] if age >= 0 and age < 3 else 1.0
	for b in _bits:
		var n: Node3D = b[0]
		var beat := posmod(f + int(b[5]), HOP)
		var hop: float = float(b[4]) * sin(PI * beat / HOP)
		var turn := Basis(fw, a * 0.9 + float(b[3]))
		n.global_position = c + fw * float(b[1]) + turn * (Vector3.DOWN * (float(b[2]) - hop))
		n.global_basis = turn * Basis(b[6], f * float(b[7]))
		var sq: Vector3 = Vector3(1.25, 0.72, 1.25) if beat == 0 else (Vector3(0.88, 1.15, 0.88) if beat == 1 else Vector3.ONE)
		n.scale = sq * pop


# ---------------------------------------------------------------- 形（フェルトの粒と毛糸の麺）

func _piece(kind: String, col: Color, s: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	match kind:
		"soup":   # 汁: ふくらんだフェルトの塊（汁の色）
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3(1.3, 0.55, 1.1))
		"drop", "bead":   # 汁のしずく・湯や油の泡
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3.ONE, kind == "bead" and col.r > 0.95)
		"noodle", "noodle_thick", "noodle_thin":   # 麺: 毛糸のかたまり（3 本が波打って重なる）
			var r: float = {"noodle": 0.018, "noodle_thick": 0.03, "noodle_thin": 0.013}[kind]
			for k in 3:
				_add(root, _coil(s, r, rng), col, Vector3(rng.randf_range(-0.03, 0.03), 0.02 * k, rng.randf_range(-0.03, 0.03)))
		"chashu":   # 焼き豚: 茶色の円板に明るい縁
			_add(root, _disc(s, s * 0.3), col)
			_add(root, _ring(s * 0.85, s), Color("C8925A"), Vector3(0, s * 0.12, 0))
		"naruto":   # なると: 白い円板に桃色の渦（輪を 2 つ重ねる）
			_add(root, _disc(s, s * 0.35), col)
			_add(root, _ring(s * 0.5, s * 0.62), Color("E59AA8"), Vector3(0, s * 0.18, 0))
			_add(root, _ring(s * 0.18, s * 0.28), Color("E59AA8"), Vector3(0, s * 0.18, 0))
		"egg":   # 半分の卵: 白い半球に黄身
			var h := SphereMesh.new()
			h.radius = s
			h.height = s
			h.is_hemisphere = true
			_add(root, h, col, Vector3.ZERO, Vector3(1.0, 0.9, 0.8))
			_add(root, _disc(s * 0.55, s * 0.08), Color("D8A43E"), Vector3(0, 0.005, 0))
		"sheet":   # のり
			var b := BoxMesh.new()
			b.size = Vector3(s, s * 0.08, s * 1.3)
			_add(root, b, col)
		"ring":   # ねぎの小口切り
			_add(root, _ring(s * 0.55, s), col)
		"stick", "kamaboko":   # メンマ・紅しょうが・ポテト・かまぼこ
			var b := BoxMesh.new()
			b.size = Vector3(s * 0.32, s * 0.32, s * 1.2) if kind == "stick" else Vector3(s * 1.4, s * 0.6, s * 0.9)
			_add(root, b, col)
			if kind == "kamaboko":
				var w := BoxMesh.new()
				w.size = Vector3(s * 1.42, s * 0.3, s * 0.92)
				_add(root, w, Color("FAF6EC"), Vector3(0, -s * 0.2, 0))
		"tri":   # きつね: 三角の油揚げ
			var c := CylinderMesh.new()
			c.radial_segments = 3
			c.rings = 1
			c.top_radius = s
			c.bottom_radius = s
			c.height = s * 0.28
			_add(root, c, col)
		"lump":   # かき揚げ: ふくらんだ茶色の塊に、野菜のかけら
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3(1.2, 0.65, 1.0))
			for k in 4:
				var b := BoxMesh.new()
				b.size = Vector3(s * 0.35, s * 0.15, s * 0.2)
				_add(root, b, [Color("E58A2E"), Color("7C9A5C")][k % 2], Vector3(cos(k * 1.7) * s * 0.6, s * 0.45, sin(k * 1.7) * s * 0.5))
		"flake":   # キャベツ・豚のかけら
			var b := BoxMesh.new()
			b.size = Vector3(s, s * 0.14, s * 0.7)
			_add(root, b, col)
		"fish":   # たい焼き: ふくらんだ胴に、二股の尾
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3(1.5, 0.5, 1.0))
			var t := CylinderMesh.new()
			t.radial_segments = 3
			t.rings = 1
			t.top_radius = s * 0.55
			t.bottom_radius = s * 0.55
			t.height = s * 0.2
			_add(root, t, col, Vector3(-s * 1.6, 0, 0))
		"bun":   # 肉まん: 白い丸に、てっぺんのひねり
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = s * 0.3
			c.height = s * 0.3
			_add(root, c, col, Vector3(0, s * 0.85, 0))
		"patty":   # コロッケ・ハッシュドポテト: 衣の小判形
			_add(root, _sphere(s), col, Vector3.ZERO, Vector3(1.3, 0.5, 0.9))
		"crumb":   # パン粉・揚げかす
			var b := BoxMesh.new()
			b.size = Vector3.ONE * s
			_add(root, b, col)
	return root


func _add(root: Node3D, mesh: Mesh, col: Color, at := Vector3.ZERO, sc := Vector3.ONE, snow := false) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var mat := Look.snow() if snow else Look.felt(col, 0.5)
	if not snow:
		mat.rim = 0.15   # 縁の光が強いと、胴の中の小さな粒が平たい切り絵に見える
	m.material_override = mat
	m.position = at
	m.scale = sc
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m


func _disc(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 16
	m.rings = 1
	return m


func _ring(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 12
	m.ring_segments = 6
	return m


## 毛糸の麺 1 本: 渦を巻いて波打つ管（大きさ s、太さ r）
func _coil(s: float, r: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var a0 := rng.randf_range(0.0, TAU)
	var turns := rng.randf_range(1.5, 2.6)
	var pts: Array[Vector3] = []
	for i in 22:
		var t := i / 21.0
		var ang := a0 + t * turns * PI
		var rr := s * (0.25 + 0.75 * t)
		pts.append(Vector3(rr * cos(ang), s * 0.12 * sin(t * 19.0 + a0), rr * sin(ang)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	for i in pts.size():
		var tan := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var nrm := tan.cross(Vector3.UP).normalized()
		if nrm.length() < 0.5:
			nrm = Vector3.RIGHT
		var bin := tan.cross(nrm).normalized()
		for k in sides:
			var a := TAU * k / sides
			var d := nrm * cos(a) + bin * sin(a)
			st.set_normal(d)
			st.set_uv(Vector2(float(k) / sides, i / 4.0))
			st.add_vertex(pts[i] + d * r)
	for i in pts.size() - 1:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			st.add_index(a)
			st.add_index(a + sides)
			st.add_index(b)
			st.add_index(b)
			st.add_index(a + sides)
			st.add_index(b + sides)
	return st.commit()
