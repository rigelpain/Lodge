extends RefCounted
## 大玉（big_ball.gd）の縫い目の柄（2026-11-09 代表「作られた手袋のグレードによって雪玉のステッチの模様変えてほしい。雪玉のステッチも売って欲しい」）。
## 決まりと、何を見て何を汲み取ったかは design/ball-stitches/README.md。
##
## 玉は、固めた手袋の段（big_ball.gd の pack。gloves.gd）で縫い合わせの形と糸の色が決まる。どの柄にしても、この 2 つは変わらない
## （一目でどの手袋で固めた玉か分かる）:
##   毛糸   2 本の縫い合わせ（赤道と斜めの輪。前からの玉と同じ）、錆びた赤の太い毛糸
##   フェルト 3 本の直角に交わる輪（手まりの地割りの 8 等分。玉が 8 枚のフェルトの三角に見える）、藍の糸
##   革     野球の玉のような、2 枚の革を合わせた 1 本のうねる縫い合わせ、こげ茶の糸
## 柄（縫い方）は、標準なら段で決まり（毛糸 なみ縫い・フェルト ブランケット・革 サドルステッチ）、山師の棚で買った柄を持ち物で選ぶと替わる。
## 縫い合わせに沿って縫う柄（sew）は、滑りあとの縫い方（stitches.gd の sew）をそのまま玉の上で縫う。
## 手まりの柄（motif）は、縫い合わせのあいだの面のまんなか（多くて 4 か所）に刺し、縫い合わせは段の標準の縫い方のまま。
## 糸は滑りあとと同じ 2 本撚りの糸（look.gd の stitch_mesh）。目は玉ごとに 1 つの MultiMesh に並べる（玉 1 つで描くのは 1 回）。
## 表の値:
##   ja     名前（説明と確かめの出力用。画面には出さない）
##   price  山師の棚の値段（ボタン）。0 は標準（段で決まる）で、選ぶものではない
##   sew    縫い合わせに沿って縫う縫い方（stitches.gd の sew の名前）。motif の柄は書かない（段の標準の縫い方）
##   motif  面のまんなかに刺す手まりの柄
##   radius 糸の太さ（半径。玉の半径を 1 とした大きさ。玉と一緒に大きくなる）
##   bow    弧の目のふくらみ（同じ大きさ）

const Stitches := preload("res://stitches.gd")
const Gloves := preload("res://gloves.gd")
const Look := preload("res://look.gd")

const STEP := 0.3          # 縫い合わせの 1 歩（玉の半径を 1 とした長さ）。滑りあとの 1 歩 0.3 m と同じ数なので、柄の幅や目の長さが stitches.gd のまま使える
const MAX_PIECE := 0.34    # まっすぐの長い目はこれより短く分けて、玉の丸みに沿わせる（分けないと中ほどが玉に潜る。分けた目は中ほどが面に付くよう両端を持ち上げる。xform）
const LIFT := 1.004        # 目を置く高さ（玉の面のすぐ上）
const MAX_FACES := 4       # 手まりの柄を刺す面の数
const FACE_APART := 1.5    # 面どうしをこれより離す（角度 rad）
const KNOT := 0.07         # フレンチノットの粒の長さ

const STANDARD := {"gloves": "yarn", "gloves_felt": "felt", "gloves_leather": "leather"}
const LIST := {
	# 標準（段で決まる）。毛糸は太く丈夫な素朴な縫い目、フェルトはフェルトの縁かがり、革は革細工の縫い方
	"yarn": {"ja": "なみ縫い", "price": 0, "sew": "running", "radius": 0.036, "bow": 0.05},
	"felt": {"ja": "ブランケット", "price": 0, "sew": "blanket", "radius": 0.024, "bow": 0.05},
	"leather": {"ja": "サドルステッチ", "price": 0, "sew": "saddle", "radius": 0.022, "bow": 0.05},
	# ボタン 30
	"back": {"ja": "返し縫い", "price": 30, "sew": "back", "radius": 0.028, "bow": 0.05},
	"zigzag": {"ja": "ジグザグ", "price": 30, "sew": "zigzag", "radius": 0.028, "bow": 0.05},
	"wave": {"ja": "波縫い", "price": 30, "sew": "wave", "radius": 0.026, "bow": 0.07},
	# ボタン 60
	"chain": {"ja": "くさり縫い", "price": 60, "sew": "chain", "radius": 0.024, "bow": 0.055},
	"cross": {"ja": "クロス", "price": 60, "sew": "cross", "radius": 0.022, "bow": 0.05},
	"chevron": {"ja": "山形", "price": 60, "sew": "chevron", "radius": 0.025, "bow": 0.05},
	# ボタン 120
	"herringbone": {"ja": "千鳥がけ", "price": 120, "sew": "herringbone", "radius": 0.024, "bow": 0.05},
	"fly": {"ja": "フライ", "price": 120, "sew": "fly", "radius": 0.021, "bow": 0.05},
	"knots": {"ja": "フレンチノット", "price": 120, "motif": "knots", "radius": 0.03, "bow": 0.04},
	# ボタン 250
	"feather": {"ja": "フェザー", "price": 250, "sew": "feather", "radius": 0.02, "bow": 0.05},
	"fishbone": {"ja": "フィッシュボーン", "price": 250, "sew": "fishbone", "radius": 0.022, "bow": 0.05},
	"daisy": {"ja": "レゼーデージー", "price": 250, "motif": "daisy", "radius": 0.022, "bow": 0.075},
	"kiku": {"ja": "菊かがり", "price": 250, "motif": "kiku", "radius": 0.02, "bow": 0.05},
	# ボタン 500
	"hoshi": {"ja": "星かがり", "price": 500, "motif": "hoshi", "radius": 0.02, "bow": 0.05},
	"asanoha": {"ja": "麻の葉", "price": 500, "motif": "asanoha", "radius": 0.018, "bow": 0.05},
	"crystal": {"ja": "雪の結晶", "price": 500, "motif": "crystal", "radius": 0.02, "bow": 0.05},
}

static var _segs := {}     # "柄:段" → 目の配列 [入る針穴, 出る針穴, 弧の向き]（半径 1 の玉の上）
static var _faces := {}    # 段 → 面 [[まんなかの向き, 柄の大きさ], ...]
static var _meshes := {}   # "柄:段" → 糸の形（look.gd の stitch_mesh。色と太さ入り）
static var _felts := {}    # 段 → はじけ飛ぶ目の材質
static var _dash: BoxMesh


static func has(name: String) -> bool:
	return LIST.has(name)


static func price(name: String) -> int:
	return int(LIST.get(name, {}).get("price", 0))


static func ja(name: String) -> String:
	return String(LIST.get(name, {}).get("ja", name))


## 売っている柄の名前（安い順。同じ値段は表の順）
static func for_sale() -> Array:
	var out := []
	for n in LIST:
		if int(LIST[n].price) > 0:
			out.append(n)
	return out


## 段の標準の柄
static func standard(grade: String) -> String:
	return String(STANDARD.get(grade, "yarn"))


## 玉に縫う柄: 選んだ柄（買った柄）があればそれ、なければ段の標準
static func pattern_of(chosen: String, grade: String) -> String:
	if LIST.has(chosen) and int(LIST[chosen].price) > 0:
		return chosen
	return standard(grade)


## 糸の色（手袋の色）
static func thread_color(grade: String) -> Color:
	return Gloves.GRADES.get(grade, Gloves.GRADES["gloves"]).color


# ---- 形

## 縫い合わせ（段ごと）。それぞれ、閉じた輪の細かい点の列（半径 1 の玉の上）
static func seams(grade: String) -> Array:
	match grade:
		"gloves_felt":
			return [_circle(Vector3.RIGHT), _circle(Vector3.UP), _circle(Vector3.BACK)]
		"gloves_leather":
			return [_ball_seam()]
	return [_circle(Vector3.UP), _circle(Vector3(sin(1.1), 0.0, cos(1.1)))]


static func _circle(n: Vector3) -> PackedVector3Array:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var out := PackedVector3Array()
	for i in 192:
		var a := TAU * i / 192.0
		out.append(u * cos(a) + v * sin(a))
	return out


## 野球の玉の縫い合わせ（2 枚の同じ形の革を合わせたうねる 1 本の線）。よく使われる近似の曲線を、玉の面に寄せる
static func _ball_seam() -> PackedVector3Array:
	const B := 0.3
	const A := 1.0 - B
	var c := 2.0 * sqrt(A * B)
	var out := PackedVector3Array()
	for i in 256:
		var t := TAU * i / 256.0
		out.append(Vector3(A * cos(t) + B * cos(3.0 * t), c * sin(2.0 * t), A * sin(t) - B * sin(3.0 * t)).normalized())
	return out


## 閉じた輪を、だいたい STEP ごとの歩みに分ける（歩みの数は偶数。交互の柄が輪の継ぎ目でそろう）
static func _resample(loop: PackedVector3Array) -> PackedVector3Array:
	var n0 := loop.size()
	var acc := PackedFloat32Array([0.0])
	for i in n0:
		acc.append(acc[i] + loop[i].distance_to(loop[(i + 1) % n0]))
	var total: float = acc[n0]
	var n := maxi(6, roundi(total / STEP))
	n += n % 2
	var out := PackedVector3Array()
	var j := 0
	for k in n:
		var s := total * k / n
		while acc[j + 1] < s:
			j += 1
		var f := (s - acc[j]) / maxf(acc[j + 1] - acc[j], 0.00001)
		out.append(loop[j].lerp(loop[(j + 1) % n0], f).normalized())
	return out


## 手まりの柄を刺す面: 縫い合わせからいちばん離れた所を、離れた順に MAX_FACES まで。大きさは縫い合わせまでの角度の 8 割
static func faces(grade: String) -> Array:
	if _faces.has(grade):
		return _faces[grade]
	var pts := PackedVector3Array()
	for loop in seams(grade):
		for i in range(0, loop.size(), 3):
			pts.append(loop[i])
	var cand := []
	const N := 400
	for i in N:   # 玉の面に、だいたい同じ間をあけた点（フィボナッチの並び）
		var y := 1.0 - 2.0 * (i + 0.5) / N
		var rr := sqrt(1.0 - y * y)
		var a := i * 2.39996323
		var d := Vector3(cos(a) * rr, y, sin(a) * rr)
		var best := -1.0
		for p in pts:
			best = maxf(best, d.dot(p))
		cand.append([acos(clampf(best, -1.0, 1.0)), d])
	cand.sort_custom(func(x, y): return x[0] > y[0])
	var out := []
	for c in cand:
		var ok := true
		for f in out:
			if (f[0] as Vector3).angle_to(c[1]) < FACE_APART:
				ok = false
				break
		if ok:
			out.append([c[1], minf(float(c[0]) * 0.8, 0.5)])
			if out.size() >= MAX_FACES:
				break
	_faces[grade] = out
	return out


## 柄 name を段 grade の玉に縫った目の並び [入る針穴, 出る針穴, 弧の向き 0・1・2]（半径 1 の玉の上。柄と段ごとに一度だけ作る）
static func segments(name: String, grade: String) -> Array:
	var key := name + ":" + grade
	if _segs.has(key):
		return _segs[key]
	var spec: Dictionary = LIST.get(name, LIST["yarn"])
	var out := []
	var emit := func(a: Vector3, b: Vector3, bow: int) -> void:
		_put(out, a, b, bow)
	var how := String(spec.get("sew", LIST[standard(grade)].sew))
	for loop in seams(grade):
		var pts := _resample(loop)
		var n := pts.size()
		for i in n:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[(i + 1) % n]
			var nn := (p0 + p1).normalized()
			var side := (p1 - p0).normalized().cross(nn).normalized()
			Stitches.sew(how, emit, p0, p1, Vector3.ZERO, Vector3.ZERO, side, i, 1.0)
	if spec.has("motif"):
		for f in faces(grade):
			_motif(String(spec.motif), f[0], float(f[1]), emit)
	_segs[key] = out
	return out


## 目を 1 つ足す。両端は玉の面へ寄せ、まっすぐの長い目は丸みに沿って分ける
static func _put(out: Array, a: Vector3, b: Vector3, bow: int) -> void:
	var pa := a.normalized()
	var pb := b.normalized()
	var ang := pa.angle_to(pb)
	if ang < 0.03:
		return
	var n := 1 if bow != 0 else maxi(1, ceili(ang / MAX_PIECE))
	for k in n:
		out.append([pa.slerp(pb, float(k) / n), pa.slerp(pb, float(k + 1) / n), bow])


## 手まりの柄を、面のまんなか f に、大きさ s（角度 rad）で刺す。柄の中の場所は (r, 角度) で、r = 1 が柄の外の縁
static func _motif(kind: String, f: Vector3, s: float, emit: Callable) -> void:
	var t1 := f.cross(Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := f.cross(t1)
	var at := func(r: float, a: float) -> Vector3:
		return (f + (t1 * cos(a) + t2 * sin(a)) * r * s).normalized()
	var knot := func(p: Vector3) -> void:   # フレンチノット: 糸を巻いた小さな粒（左右へふくらむ短い弧を 2 本と、上を渡る 1 本）
		var q := (p + t1 * KNOT).normalized()
		emit.call(p, q, 1)
		emit.call(p, q, 2)
		emit.call((p - t2 * KNOT * 0.5).normalized(), (p + t1 * KNOT * 0.5 + t2 * KNOT * 0.5).normalized(), 0)
	match kind:
		"kiku":      # 菊かがり: まんなかから 12 枚の花びら。花びらは外へ尖る山形を 2 重に（千鳥にかがった糸の重なり）
			for k in 12:
				var a := TAU * k / 12.0
				for ring in [[0.32, 1.0, 0.16], [0.18, 0.6, 0.12]]:
					emit.call(at.call(ring[0], a - ring[2]), at.call(ring[1], a), 0)
					emit.call(at.call(ring[0], a + ring[2]), at.call(ring[1], a), 0)
		"hoshi":     # 星かがり: 五芒星の一筆書きを、内へ 2 周重ねる
			for rr in [1.0, 0.68]:
				for k in 5:
					var a0 := TAU * k / 5.0 - PI / 2.0
					emit.call(at.call(rr, a0), at.call(rr, a0 + TAU * 2.0 / 5.0), 0)
		"asanoha":   # 麻の葉: 六角形を 6 つの三角に割り、三角ごとに、まんなかから 3 つの角へ渡す
			for k in 6:
				var a0 := TAU * k / 6.0
				var a1 := TAU * (k + 1) / 6.0
				var v0: Vector3 = at.call(1.0, a0)
				var v1: Vector3 = at.call(1.0, a1)
				emit.call(v0, v1, 0)
				var g: Vector3 = at.call(0.58, (a0 + a1) / 2.0)   # 三角のまんなか（中心と 2 つの角の重心は、半径 1 の 0.58 の所）
				emit.call(g, f, 0)
				emit.call(g, v0, 0)
				emit.call(g, v1, 0)
		"crystal":   # 雪の結晶: 6 本の腕と、腕の 6 割の所の短い横棒、腕の先の小さな山形
			for k in 6:
				var a := TAU * k / 6.0
				emit.call(f, at.call(1.0, a), 0)
				emit.call(at.call(0.62, a - 0.4), at.call(0.62, a + 0.4), 0)
				emit.call(at.call(0.82, a - 0.2), at.call(1.0, a), 0)
				emit.call(at.call(0.82, a + 0.2), at.call(1.0, a), 0)
		"knots":     # フレンチノット: まんなかに 1 つ、まわりに 6 つ、外に 6 つの粒（散らし）
			knot.call(f)
			for k in 6:
				knot.call(at.call(0.5, TAU * k / 6.0))
				knot.call(at.call(0.95, TAU * (k + 0.5) / 6.0))
		"daisy":     # レゼーデージー: 6 枚の花びら（輪にした糸を先で留める）と、まんなかの粒
			knot.call(f)
			for k in 6:
				var a := TAU * k / 6.0
				emit.call(at.call(0.2, a), at.call(0.92, a), 1)
				emit.call(at.call(0.2, a), at.call(0.92, a), 2)
				emit.call(at.call(0.86, a), at.call(1.06, a), 0)


## 目の置き方（半径 1 の玉の座標）。入る針穴から -z へ長さぶん伸びる。長い目ほど少し持ち上げて、中ほどが玉に潜らないように
static func xform(seg: Array) -> Transform3D:
	var a: Vector3 = seg[0]
	var b: Vector3 = seg[1]
	var span := b - a
	var len := span.length()
	var z := -span / len
	var nn := (a + b).normalized()
	var y := (nn - z * nn.dot(z)).normalized()
	return Transform3D(Basis(y.cross(z), y, z), a * (LIFT + len * len / 8.0))


## 目ごとの値（look.gd の THREAD_SHADER の INSTANCE_CUSTOM: 長さ, 位相＋弧の向き, 消えていく時間, 消え始める時刻）。off ならもう消えている
static func custom(seg: Array, i: int, off := false) -> Color:
	var len := (seg[1] as Vector3).distance_to(seg[0])
	return Color(len, fposmod(i * 0.618034, 0.999) + int(seg[2]), 0.01 if off else 1.0, -1.0 if off else 1.0e6)


## 糸の形（柄と段ごとに 1 つ。どの玉でも使い回す）。針穴の影の面は付けない（平らな四角は丸い玉の面に合わない）
static func mesh(name: String, grade: String) -> ArrayMesh:
	var key := name + ":" + grade
	if not _meshes.has(key):
		var spec: Dictionary = LIST.get(name, LIST["yarn"])
		var m := Look.stitch_mesh(thread_color(grade), false)
		Look.stitch_set_shape(m, float(spec.radius), float(spec.bow))
		Look.stitch_set_style(m, 1)   # 消えるのは、はじけたときだけ（すぐ消える）
		_meshes[key] = m
	return _meshes[key]


## はじけ飛ぶ目（長さ 1・太さ 1 の箱。置く所で大きさを決める）と、その材質（糸の色のフェルト）
static func dash_mesh() -> BoxMesh:
	if _dash == null:
		_dash = BoxMesh.new()
		_dash.size = Vector3.ONE
	return _dash


static func dash_mat(grade: String) -> StandardMaterial3D:
	if not _felts.has(grade):
		var m := Look.felt(thread_color(grade), 2.0)
		m.rim = 0.0
		_felts[grade] = m
	return _felts[grade]


# ---- 画面の絵

## 玉の絵: rect の中に、柄 name を段 grade で縫った玉を描く（手前の半分の目だけ。奥へ回る目は薄く）。
## 手まりの柄は、刺した面の 1 つを正面に向ける
static func draw_ball(ci: CanvasItem, name: String, grade: String, rect: Rect2, a := 1.0) -> void:
	var c := rect.get_center()
	var big := minf(rect.size.x, rect.size.y) * 0.46
	var spec: Dictionary = LIST.get(name, LIST["yarn"])
	# 正面の向き: 手まりの柄は面のまんなかへ、ほかは少し上から斜めに
	var view := Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.UP, 0.35)
	if spec.has("motif") and not faces(grade).is_empty():
		var f: Vector3 = faces(grade)[0][0]
		view = Basis(Quaternion(f, Vector3(0.18, 0.22, 1.0).normalized()))
	ci.draw_circle(c + Vector2(big * 0.06, big * 0.08), big, Color(0.45, 0.5, 0.62, 0.35 * a))   # 影
	ci.draw_circle(c, big, Color(0.93, 0.94, 0.97, a))
	ci.draw_circle(c - Vector2(big, big) * 0.28, big * 0.45, Color(1.0, 1.0, 1.0, 0.35 * a))   # 光の当たる所
	ci.draw_arc(c, big, 0.0, TAU, 40, Color(0.62, 0.68, 0.80, a), maxf(big * 0.03, 1.0), true)
	var col := thread_color(grade)
	var w := maxf(float(spec.radius) * 2.0 * big, 1.2)
	var segs := segments(name, grade)
	for seg in segs:
		var pa: Vector3 = view * (seg[0] as Vector3)
		var pb: Vector3 = view * (seg[1] as Vector3)
		var z := (pa.z + pb.z) * 0.5
		if z < -0.05:
			continue
		var k := clampf((z + 0.05) / 0.35, 0.0, 1.0)   # 縁へ回る目は薄く
		var bow := int(seg[2])
		var pts := PackedVector2Array()
		var span := pb - pa
		var nn := (pa + pb).normalized()
		var side := nn.cross(-span.normalized())
		var bv: float = 0.0 if bow == 0 else (float(spec.bow) if bow == 1 else -float(spec.bow))
		var n := 1 if bow == 0 else 6
		for j in n + 1:
			var u := float(j) / n
			var p := pa + span * u + side * bv * sin(PI * pow(u, 1.4))
			pts.append(c + Vector2(p.x, -p.y) * big)
		ci.draw_polyline(pts, Color(col.darkened(0.45), 0.45 * a * k), w + 1.2, true)
		ci.draw_polyline(pts, Color(col, a * k), w, true)
