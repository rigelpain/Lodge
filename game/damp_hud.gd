extends RefCounted

const Icons := preload("res://hud_icons.gd")
const Badges := preload("res://badges.gd")
const Damp := preload("res://damp.gd")
## 右下の刺繍枠（自分の小窓）の左右の縁に沿って縫った、水と熱の 2 本のゲージと、体の調子のバッジ（hud.gd が描く）。
## 2026-11-01 代表「水は刺繍の左側、熱は刺繍の右にゲージ作ろう。水ゲージには水アイコンだけ、熱ゲージには氷アイコンと炎アイコン」。
##   水（左）: 紙の帯。下が乾いている（0）、上の端に水のワッペン（100 びしょびしょ）。上へ行くほど濃い藍。湿るほど帯の縁が波打つ
##   熱（右）: 紙の帯。下の端に氷のワッペン（0 凍える）、上の端に炎のワッペン（100 ほかほか）。まんなか（50 ふつう）に太い生成りの糸。
##             下へ行くほど濃い氷の青、上へ行くほど濃い赤
## 帯の地は淡い色、端から今の所まで縫った糸は濃い色。今の所に赤い結び目。数字は出さない。
## ご飯でこれから上がる熱は、今の所から行き先まで白いしつけ糸（あとで縫う所の目印）を渡し、行き先に白い小さな結び目。
## バッジ（水と熱を差し引いた押す力・速さの上がり下がり、ご飯）は刺繍枠の上に、2 本のゲージのあいだに並べ、出たときに跳ねる

const GAP := 40.0               # 窓の縁から帯までの間（1080 のとき, px。木の輪の外）
const BAND := 17.0              # 帯の幅（px）
const END := 34.0               # 端のワッペンの直径（px）
const SPAN := 0.55              # 帯の下の端の、真横からの下がり（rad）
const TOP := 0.75               # 帯の上の端の、真横からの上がり（rad。上の端のワッペンがバッジにかからないように）
const BADGE := 52.0             # バッジの直径（px）
## バッジの置き場: [向き, 窓の縁からバッジの真ん中までの間 (px)]。1 枚目は枠の上の右、2 枚目は左、3 枚目は留め具の真上の少し外
const BADGE_AT := [[-1.27, 44.0], [-1.87, 44.0], [-1.57, 80.0]]
# 帯の色: [値, 縫う糸の色]。あいだは混ぜる。帯の地は、これを生成りへ寄せた淡い色
const WATER_COLORS := [
	[0.0, Color(0.72, 0.82, 0.92)],     # 乾いている: 淡い水色
	[100.0, Color(0.08, 0.20, 0.52)],   # びしょびしょ: 濃い藍
]
const HEAT_COLORS := [
	[0.0, Color(0.16, 0.50, 0.78)],     # 凍える: 濃い氷の青
	[50.0, Color(0.86, 0.80, 0.68)],    # ふつう: 生成りに近い
	[100.0, Color(0.72, 0.08, 0.06)],   # ほかほか: 濃い赤
]


## 水（0 〜 100）の、左の帯の上の向き（画面の座標、右が 0、下が正）
static func water_angle(v: float) -> float:
	return lerpf(PI - SPAN, PI + TOP, clampf(v, 0.0, 100.0) / 100.0)


## 熱（0 〜 100）の、右の帯の上の向き
static func heat_angle(v: float) -> float:
	return lerpf(SPAN, -TOP, clampf(v, 0.0, 100.0) / 100.0)


static func color_in(cols: Array, v: float) -> Color:
	for i in cols.size() - 1:
		if v <= cols[i + 1][0]:
			return (cols[i][1] as Color).lerp(cols[i + 1][1], clampf((v - cols[i][0]) / (cols[i + 1][0] - cols[i][0]), 0.0, 1.0))
	return cols[-1][1]


static func _on(c: Vector2, t: float, r: float) -> Vector2:
	return c + Vector2(cos(t), sin(t)) * r


## 2 本のゲージとバッジ。c は刺繍枠の真ん中、r は窓の半径（px）。w・h は見せている水と熱、a は濃さ、
## pops は名前 → 跳ね（1→0）、coming はご飯でこれから上がる熱（しつけ糸）
static func draw(ci: CanvasItem, c: Vector2, r: float, u: float, w: float, h: float, a: float, badges: Array, pops: Dictionary, coming := 0.0) -> void:
	Icons.screen()
	var rr := r + GAP * u
	if a > 0.01:
		# 水（左）: 下の端から今の所まで
		_band(ci, c, rr, u, water_angle(-4.0), water_angle(104.0), WATER_COLORS, -4.0, 104.0, clampf(w / 100.0, 0.0, 1.0), a)
		_sew(ci, c, rr, u, 0.0, w, WATER_COLORS, water_angle, a)
		Badges.end_patch(ci, "drop", _on(c, water_angle(100.0) + 0.2, rr), END * u, a)
		_knot(ci, _on(c, water_angle(w), rr), u, a)
		# 熱（右）: 下の端（氷）から今の所まで。まんなかに太い生成りの糸
		_band(ci, c, rr, u, heat_angle(-4.0), heat_angle(104.0), HEAT_COLORS, -4.0, 104.0, 0.0, a)
		_sew(ci, c, rr, u, 0.0, h, HEAT_COLORS, heat_angle, a)
		var am := heat_angle(Damp.HEAT_MID)
		var d := Vector2(cos(am), sin(am))
		Icons.thread(ci, PackedVector2Array([c + d * (rr - BAND * 0.8 * u), c + d * (rr + BAND * 0.8 * u)]), Icons.PAPER, 3.4 * u, a)
		if coming > 0.5:
			_basting(ci, c, rr, u, h, minf(h + coming, 100.0), a)
		Badges.end_patch(ci, "ice", _on(c, heat_angle(0.0) + 0.2, rr), END * u, a)
		Badges.end_patch(ci, "fire", _on(c, heat_angle(100.0) - 0.2, rr), END * u, a)
		_knot(ci, _on(c, heat_angle(h), rr), u, a)
	# バッジ: 刺繍枠の上、2 本のゲージのあいだ
	for i in mini(badges.size(), BADGE_AT.size()):
		var b: Dictionary = badges[i]
		var p := _on(c, BADGE_AT[i][0], r + BADGE_AT[i][1] * u)
		Badges.draw_badge(ci, b, p, BADGE * u, 1.0, pops.get(b.key, 0.0))
	Icons.screen()


## 帯の端（v0）から今の所（v1）まで、値ごとの色で縫う（少しずつ区切って色を変える）。糸の撚りの筋も
static func _sew(ci: CanvasItem, c: Vector2, rr: float, u: float, v0: float, v1: float, cols: Array, angle: Callable, a: float) -> void:
	var steps := int(clampf(v1 - v0, 0.0, 100.0) / 2.0)
	for i in steps:
		var s0 := v0 + i * 2.0
		var s1 := minf(s0 + 2.0 + 0.3, v1)
		var pts := PackedVector2Array([_on(c, angle.call(s0), rr), _on(c, angle.call((s0 + s1) / 2.0), rr), _on(c, angle.call(s1), rr)])
		ci.draw_polyline(pts, Color(color_in(cols, s0 + 1.0), a), 9.0 * u, true)
	if v1 - v0 > 1.0:
		var all := PackedVector2Array()
		for i in 25:
			all.append(_on(c, angle.call(lerpf(v0, v1, i / 24.0)), rr))
		Icons.dashes(ci, all, Color(1, 1, 1), 1.2 * u, 3.0 * u, 3.0 * u, 0.45 * a)


## 今の所の赤い結び目
static func _knot(ci: CanvasItem, at: Vector2, u: float, a: float) -> void:
	Icons._o = at
	Icons._s = u
	Icons.patch(ci, Icons.circ(Vector2.ZERO, 8.5, 16), Icons.RED, a, false)
	ci.draw_circle(at + Vector2(-2.4, -2.4) * u, 2.3 * u, Color(1, 1, 1, 0.5 * a))
	Icons.screen()


## ご飯でこれから上がる熱: 白いしつけ糸（藍の縁どり）と、行き先の結び目
static func _basting(ci: CanvasItem, c: Vector2, rr: float, u: float, from: float, to: float, a: float) -> void:
	var n := maxi(2, int((to - from) / 1.5))
	var pts := PackedVector2Array()
	for i in n + 1:
		pts.append(_on(c, heat_angle(lerpf(from, to, i / float(n))), rr))
	Icons.dashes(ci, pts, Icons.THREAD, 6.4 * u, 5.0 * u, 3.0 * u, 0.85 * a)
	Icons.dashes(ci, pts, Color(1, 1, 1), 4.0 * u, 5.0 * u, 3.0 * u, a)
	var tip := _on(c, heat_angle(to), rr)
	ci.draw_circle(tip, 5.4 * u, Color(Icons.THREAD, 0.85 * a))
	ci.draw_circle(tip, 4.0 * u, Color(1, 1, 1, a))


## 紙の帯（両側にランニングステッチ）。地は値ごとの色を生成りへ寄せた淡い色。wet ほど縁が波打つ
static func _band(ci: CanvasItem, c: Vector2, rr: float, u: float, t0: float, t1: float, cols: Array, v0: float, v1: float, wet: float, a: float) -> void:
	var n := 40
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var vals := PackedFloat32Array()
	for i in n + 1:
		var k := i / float(n)
		var t := lerpf(t0, t1, k)
		var wave := sin(t * 38.0) * wet * 1.6 * u
		outer.append(_on(c, t, rr + BAND * 0.5 * u + wave))
		inner.append(_on(c, t, rr - BAND * 0.5 * u - wave))
		vals.append(lerpf(v0, v1, k))
	var poly := outer.duplicate()
	var back := inner.duplicate()
	back.reverse()
	poly.append_array(back)
	var shadow := PackedVector2Array()
	for p in poly:
		shadow.append(p + Vector2(1.5, 2.5) * u)
	ci.draw_colored_polygon(shadow, Color(Icons.SHADOW, 0.25 * a))
	for i in n:   # 少しずつ区切って、地の色を変える
		var q := PackedVector2Array([outer[i], outer[i + 1], inner[i + 1], inner[i]])
		ci.draw_colored_polygon(q, Color(Icons.PAPER.lerp(color_in(cols, (vals[i] + vals[i + 1]) / 2.0), 0.45), a))
	var edge := poly.duplicate()
	edge.append(poly[0])
	ci.draw_polyline(edge, Color(Icons.PAPER_EDGE, 0.9 * a), maxf(1.2 * u, 1.0), true)
	for k in 2:   # 縁から少し内に、両側のステッチ
		var line := PackedVector2Array()
		for p in (outer if k == 0 else inner):
			line.append(p + (c - p).normalized() * (2.4 * u if k == 0 else -2.4 * u))
		Icons.dashes(ci, line, Icons.THREAD, 1.1 * u, 4.0 * u, 3.0 * u, 0.7 * a)
