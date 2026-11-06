extends RefCounted
## 滑りあとの縫い目の見本帳（2026-11-06）。どの柄も、太い 2 本撚りの糸の目（look.gd の stitch_mesh）を並べて描く。
## 実物の手縫い・刺繍・刺し子から形を取った。何を見て何を汲み取ったかは design/trail-stitches/README.md。
## 表の値:
##   ja     棚と持ち物の画面に出す名前
##   per    1 歩に置く糸の目の数の目安（残せる目の数を決める。sled.gd の TRAIL_N × per）
##   radius 糸の太さ（半径 m）
##   bow    弧の目のふくらみ (m)
##   price  ソリ屋の値段（ボタン）。0 は標準で、誰でも選べる
##   arc    弧の目を使う柄（粗い形にすると角ばるので、細かい形を長く使う）

const LIST := {
	# 標準。重いソリほど太く丈夫（2026-10-27 代表。sled.gd の KINDS の stitch）
	"running": {"ja": "なみ縫い", "per": 1, "radius": 0.02, "bow": 0.052, "price": 0},
	"chain": {"ja": "くさり縫い", "per": 2, "radius": 0.021, "bow": 0.052, "price": 0, "arc": true},
	"saddle": {"ja": "サドルステッチ", "per": 4, "radius": 0.025, "bow": 0.052, "price": 0},
	# ボタン 30
	"back": {"ja": "返し縫い", "per": 1, "radius": 0.024, "bow": 0.05, "price": 30},
	"zigzag": {"ja": "ジグザグ", "per": 1, "radius": 0.026, "bow": 0.05, "price": 30},
	"wave": {"ja": "波縫い", "per": 1, "radius": 0.022, "bow": 0.07, "price": 30, "arc": true},
	"juji": {"ja": "十字刺し", "per": 2, "radius": 0.018, "bow": 0.05, "price": 30},
	# ボタン 60
	"cross": {"ja": "クロス", "per": 2, "radius": 0.02, "bow": 0.05, "price": 60},
	"chevron": {"ja": "山形", "per": 2, "radius": 0.024, "bow": 0.05, "price": 60},
	"hitome": {"ja": "一目刺し", "per": 3, "radius": 0.015, "bow": 0.05, "price": 60},
	"ladder": {"ja": "はしご", "per": 3, "radius": 0.018, "bow": 0.05, "price": 60},
	# ボタン 120
	"herringbone": {"ja": "千鳥がけ", "per": 1, "radius": 0.022, "bow": 0.05, "price": 120},
	"blanket": {"ja": "ブランケット", "per": 2, "radius": 0.019, "bow": 0.05, "price": 120},
	"fly": {"ja": "フライ", "per": 3, "radius": 0.018, "bow": 0.05, "price": 120},
	"triple": {"ja": "三重ジグザグ", "per": 3, "radius": 0.016, "bow": 0.05, "price": 120},
	"kome": {"ja": "米刺し", "per": 2, "radius": 0.016, "bow": 0.05, "price": 120},
	# ボタン 250
	"feather": {"ja": "フェザー", "per": 2, "radius": 0.017, "bow": 0.05, "price": 250},
	"fishbone": {"ja": "フィッシュボーン", "per": 2, "radius": 0.02, "bow": 0.05, "price": 250},
	"seigaiha": {"ja": "青海波", "per": 3, "radius": 0.015, "bow": 0.04, "price": 250, "arc": true},
	"shippo": {"ja": "七宝", "per": 2, "radius": 0.014, "bow": 0.11, "price": 250, "arc": true},
	# ボタン 500
	"asanoha": {"ja": "麻の葉", "per": 5, "radius": 0.012, "bow": 0.05, "price": 500},
	"crystal": {"ja": "雪の結晶", "per": 5, "radius": 0.012, "bow": 0.05, "price": 500},
	"heart": {"ja": "ハート", "per": 2, "radius": 0.016, "bow": 0.055, "price": 500, "arc": true},
	"garden": {"ja": "花の蔓", "per": 5, "radius": 0.013, "bow": 0.035, "price": 500, "arc": true},
}

const RUNNING_DASH := 0.62    # なみ縫いの 1 歩のうち、糸が表に出ている割合
const SADDLE_ROW := 0.08      # サドルステッチの 2 列の、中心からの距離 (m)
const SADDLE_SLANT := Vector2(0.055, 0.095)   # サドルステッチの 1 目の、横と前後の半分の長さ (m)
const ZIG := 0.045            # ジグザグの振れ幅（縫い目の中心から針穴まで, m）
const W := 0.08               # 飾りの柄の、中心からの幅 (m)
const ONE_MOTIF := ["kome", "asanoha", "crystal", "heart"]   # 2 歩に 1 つの大きな柄。画面の見本では 1 つを大きく描く


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


## 標準の柄の名前（誰でも選べる）
static func standard() -> Array:
	var out := []
	for n in LIST:
		if int(LIST[n].price) == 0:
			out.append(n)
	return out


## 画面の絵: 柄を rect の中に、下から上へ縫って描く。雪の上と同じ形（sew）を、そのまま平らに写す。col は糸の色
static func draw_swatch(ci: CanvasItem, name: String, rect: Rect2, col: Color, a := 1.0) -> void:
	if not LIST.has(name):
		return
	const STEP := 0.3
	var one: bool = name in ONE_MOTIF
	var view := 0.8 if one else 1.32   # 見せる長さ (m)。4 歩が収まる長さか、大きな柄 1 つぶん
	var spec: Dictionary = LIST[name]
	var sc := rect.size.y / view
	var c := rect.get_center()
	var w: float = maxf(spec.radius * 2.0 * sc, 1.5)
	var nn := Vector3.UP
	var thread := Color(col, a)
	var under := Color(col.darkened(0.45), a * 0.5)
	var emit := func(p: Vector3, q: Vector3, bow: int) -> void:
		var span := q - p
		var pts := PackedVector2Array()
		var side := nn.cross(-span.normalized())   # 糸の管の横（look.gd の thread_at の +x）
		var b: float = 0.0 if bow == 0 else (float(spec.bow) if bow == 1 else -float(spec.bow))
		var n := 1 if bow == 0 else 10
		for k in n + 1:
			var u := float(k) / n
			var at := p + span * u + side * b * sin(PI * pow(u, 1.4))
			var q2 := c + Vector2(at.x, at.z) * sc
			if not rect.grow(-1.0).has_point(q2):   # 枠からはみ出す目は描かない
				return
			pts.append(q2)
		ci.draw_polyline(pts, under, w + 1.5, true)
		ci.draw_polyline(pts, thread, w, true)
	if one:   # u = 1 が絵のまんなかに来る
		sew(name, emit, Vector3(0, 0, STEP), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.RIGHT, 0, 1.0)
		return
	for i in 4:
		var z := STEP * 2.0 - i * STEP
		sew(name, emit, Vector3(0, 0, z), Vector3(0, 0, z - STEP), Vector3.ZERO, Vector3.ZERO, Vector3.RIGHT, i, 1.0)


## 前の歩み p0 から p1 までを、柄 name で縫う。emit.call(a, b, bow) が糸の目を 1 つ置く（bow は 0 でまっすぐ、1・2 で左右にふくらむ弧）。
## j0・j1 は針穴のばらつき、side は雪面に沿った横向き、i はその滑り木の歩みの番号、m は左右の鏡（柄の向きを、外側・内側にそろえる）。
## 中の st は (u, x) で場所を指す。u は 1 歩で 0 → 1（2 を超えてもよい。そのときは今の向きのまま先へ伸ばす）、x は横 (m)
static func sew(name: String, emit: Callable, p0: Vector3, p1: Vector3, j0: Vector3, j1: Vector3, side: Vector3, i: int, m: float) -> void:
	var fwd := p1 - p0
	var s := 1.0 if i % 2 == 0 else -1.0
	var at := func(u: float, x: float) -> Vector3:
		return p0 + fwd * u + side * x * m
	var st := func(u0: float, x0: float, u1: float, x1: float, bow := 0) -> void:
		emit.call(at.call(u0, x0) + j0 * 0.4, at.call(u1, x1) + j1 * 0.4, bow)
	match name:
		"running":   # 中心線に沿って、表に出る目と、裏に潜る隙間をくり返す
			emit.call(p0 + j0, p0.lerp(p1, RUNNING_DASH) + j1 * 0.5, 0)
		"chain":     # しずく形の輪: 根元から左右にふくらむ 2 本の弧。先は次の輪の根元の少し先
			var tip := p1 + fwd.normalized() * 0.04 + j1 * 0.5
			emit.call(p0 + j0 * 0.5, tip, 1)
			emit.call(p0 + j0 * 0.5, tip, 2)
		"saddle":    # 斜めの短い目を 2 列。列どうしは半目ずらす
			var f := fwd.normalized()
			for row in 2:
				var x0 := SADDLE_ROW * (1.0 if row == 0 else -1.0)
				for sub in 2:
					var cm := p0.lerp(p1, 0.25 + 0.5 * sub + (0.25 if row == 1 else 0.0) - 0.125)
					var a := cm + side * (x0 - SADDLE_SLANT.x) - f * SADDLE_SLANT.y
					var b := cm + side * (x0 + SADDLE_SLANT.x) + f * SADDLE_SLANT.y
					emit.call(a + j0 * 0.3, b + j1 * 0.3, 0)
		"zigzag":    # 針穴を中心から左右交互にずらす
			emit.call(p0 - side * ZIG * s + j0, p1 + side * ZIG * s + j1, 0)
		"back":      # 返し縫い: 目と目のあいだを空けない実線
			st.call(0.0, 0.0, 1.0, 0.0)
		"wave":      # 波縫い: 左右へ交互にふくらむ弧
			st.call(0.0, 0.0, 1.0, 0.0, 1 if s > 0.0 else 2)
		"juji":      # 十字刺し: 雪国の刺し子の、布を丈夫にする十字
			st.call(0.15, 0.0, 0.85, 0.0)
			st.call(0.5, -W * 0.8, 0.5, W * 0.8)
		"cross":     # クロス: × が 1 つずつ
			st.call(0.1, -W, 0.9, W)
			st.call(0.1, W, 0.9, -W)
		"chevron":   # 山形: 太い目の V が重なる（進む向きへ尖る）
			st.call(0.0, -W * 1.1, 0.55, 0.0)
			st.call(0.0, W * 1.1, 0.55, 0.0)
		"hitome":    # 一目刺し: 3 列の短い目を、となりの列と半目ずらす
			for row in 3:
				var o := 0.5 if row == 1 else 0.0
				st.call(o, (row - 1) * W, o + 0.55, (row - 1) * W)
		"ladder":    # はしご: 2 本の線と横木
			st.call(0.0, -W * 0.9, 1.0, -W * 0.9)
			st.call(0.0, W * 0.9, 1.0, W * 0.9)
			st.call(0.5, -W * 0.9, 0.5, W * 0.9)
		"herringbone":   # 千鳥がけ: 斜めの目が、端で交差しながら左右へ渡る
			st.call(0.0, -s * W, 1.25, s * W)
		"blanket":   # ブランケット: 外側を向いた櫛の歯と、縁の線（ソリの座布団の縁と同じ）
			st.call(0.0, -W, 1.0, -W)
			st.call(0.0, -W, 0.0, W)
		"fly":       # フライ: Y の字が並ぶ
			st.call(0.0, -W, 0.6, 0.0)
			st.call(0.0, W, 0.6, 0.0)
			st.call(0.6, 0.0, 0.95, 0.0)
		"triple":    # 三重ジグザグ: 同じジグザグを 3 回ずらして重ねた帯
			for o in [-0.22, 0.0, 0.22]:
				st.call(o, -s * W * 0.8, 1.0 + o, s * W * 0.8)
		"kome":      # 米刺し: 十字と短い × を重ねた「米」の字が、2 歩に 1 つ
			if i % 2 == 0:
				st.call(0.35, 0.0, 1.65, 0.0)
				st.call(1.0, -W * 1.1, 1.0, W * 1.1)
				st.call(0.65, -W * 0.65, 1.35, W * 0.65)
				st.call(0.65, W * 0.65, 1.35, -W * 0.65)
		"feather":   # フェザー: まんなかの茎が左右へ振れ、そのたびに外へ枝が出る
			st.call(0.0, s * W * 0.45, 1.0, -s * W * 0.45)
			st.call(0.0, s * W * 0.45, 0.75, s * W * 1.5)
		"fishbone":  # フィッシュボーン: 葉脈のように、左右から中心へ斜めの目が交互に入る
			st.call(0.0, -W, 0.6, 0.012)
			st.call(0.5, W, 1.1, -0.012)
		"seigaiha":  # 青海波: 波の弧を 2 段、半分ずらして重ねる
			st.call(0.0, -W, 0.0, 0.0, 2)
			st.call(0.0, 0.0, 0.0, W, 2)
			st.call(0.5, -W * 0.5, 0.5, W * 0.5, 2)
		"shippo":    # 七宝: 輪が半分ずつ重なってつながる
			st.call(0.0, 0.0, 1.8, 0.0, 1)
			st.call(0.0, 0.0, 1.8, 0.0, 2)
		"asanoha":   # 麻の葉: 六角形と、まんなかから角へ渡る線が 2 歩に 1 つ
			if i % 2 == 0:
				var r := 0.14 / maxf(fwd.length(), 0.05)
				var w := 0.14
				for k in 6:
					var a0 := TAU * k / 6.0
					var a1 := TAU * (k + 1) / 6.0
					st.call(1.0 + cos(a0) * r, sin(a0) * w, 1.0 + cos(a1) * r, sin(a1) * w)
					if k < 3:
						st.call(1.0 + cos(a0) * r, sin(a0) * w, 1.0 - cos(a0) * r, -sin(a0) * w)
		"crystal":   # 雪の結晶: 3 本の線と、腕の先の短い横棒が 2 歩に 1 つ
			if i % 2 == 0:
				var r := 0.16 / maxf(fwd.length(), 0.05)
				var w := 0.16
				for k in 6:
					var a := TAU * k / 6.0
					var ca := cos(a)
					var sa := sin(a)
					if k < 3:
						st.call(1.0 + ca * r, sa * w, 1.0 - ca * r, -sa * w)
					# 腕の 3 分の 2 の所に、腕に直角な短い棒
					var mu := 1.0 + ca * r * 0.66
					var mx := sa * w * 0.66
					st.call(mu - sa * r * 0.28, mx + ca * w * 0.28, mu + sa * r * 0.28, mx - ca * w * 0.28)
		"heart":     # ハート: 下の先から両脇へまっすぐ上がり、丸い山がくぼみで合わさる。2 歩に 1 つ
			if i % 2 == 0:
				for sd in [-1.0, 1.0]:
					st.call(0.45, 0.0, 1.05, sd * 0.11)
					st.call(1.3, sd * 0.012, 1.05, sd * 0.11, 2 if sd * m > 0.0 else 1)
		"garden":    # 花の蔓: 波打つ茎に、5 枚の花びらの花（レゼーデージー）が 3 歩に 1 つ
			st.call(0.0, 0.0, 1.0, 0.0, 1 if s > 0.0 else 2)
			if i % 3 == 0:
				var r := 0.13 / maxf(fwd.length(), 0.05)
				var w := 0.13
				for k in 5:
					var a := TAU * k / 5.0
					st.call(0.5, 0.09, 0.5 + cos(a) * r, 0.09 + sin(a) * w, 1)
					st.call(0.5, 0.09, 0.5 + cos(a) * r, 0.09 + sin(a) * w, 2)
		_:
			st.call(0.0, 0.0, RUNNING_DASH, 0.0)
