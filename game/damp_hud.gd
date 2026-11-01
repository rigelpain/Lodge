extends RefCounted

const Icons := preload("res://hud_icons.gd")
const Badges := preload("res://badges.gd")
const Damp := preload("res://damp.gd")
## 右下の刺繍枠（自分の小窓）の左の縁に沿って縫った「よれ」のゲージと、体の調子のバッジ（hud.gd が描く）。
## ゲージは紙の帯。下の端に水のワッペン（0 びしょびしょ）、上の端に炎のワッペン（200 パリパリ）。
## 境目（150）より下は水の青で、下の端へ行くほど濃い青。境目より上はブーストの赤で、上の端へ行くほど濃い赤
## （2026-11-01 代表「上端下端に行くに連れ色が赤、青に濃くなってほしい」）。帯の地は淡い色、縫った糸は濃い色。
## 境目には太い生成りの糸を渡す。下の端から今の所まで糸で縫い、今の所に赤い結び目。段の境目（40・90）に小さな十字。
## 帯そのものも、湿るほど縁が波打つ（紙の体と同じ）。数字は出さない。
## 水の猶予とブーストの残りを見るものなので、ふつうでも出しておく。
## バッジは刺繍枠の右上に、枠に沿って並べ、出たときに跳ねる（2026-11-01 代表「バフデバフは刺繍の右上に置きましょう」）

const ARC_WET := PI - 0.55      # 帯の下の端（0）の向き（刺繍枠の中心から。画面の座標、右が 0、下が正）
const ARC_CRISP := PI + 1.05    # 帯の上の端（200）
const GAP := 40.0               # 窓の縁から帯までの間（1080 のとき, px。木の輪の外）
const BAND := 17.0              # 帯の幅（px）
const END := 34.0               # 端のワッペンの直径（px）
const BADGE := 52.0             # バッジの直径（px）
const BADGE_R := 42.0           # 窓の縁から、バッジの真ん中までの間（px。木の輪に少しかかる）
const BADGE_FROM := -1.0        # 1 枚目のバッジの向き（右上）
const BADGE_STEP := 0.46       # 2 枚目からの、枠に沿った間（rad。右下へ回る）
# 帯の色: [値, 縫う糸の色]。あいだは混ぜる。帯の地は、これを生成りへ寄せた淡い色
const COLORS := [
	[0.0, Color(0.08, 0.20, 0.52)],     # 下の端: 濃い藍
	[150.0, Color(0.55, 0.72, 0.92)],   # 境目の下: 淡い水色
	[150.01, Color(0.98, 0.62, 0.42)],  # 境目の上: 淡い朱
	[200.0, Color(0.72, 0.08, 0.06)],   # 上の端: 濃い赤
]


## 値（0 〜 200）の、帯の上の向き
static func angle_of(v: float) -> float:
	return lerpf(ARC_WET, ARC_CRISP, (clampf(v, Damp.LO, Damp.HI) - Damp.LO) / (Damp.HI - Damp.LO))


## 値の、縫う糸の色
static func color_of(v: float) -> Color:
	for i in COLORS.size() - 1:
		if v <= COLORS[i + 1][0]:
			return (COLORS[i][1] as Color).lerp(COLORS[i + 1][1], clampf((v - COLORS[i][0]) / (COLORS[i + 1][0] - COLORS[i][0]), 0.0, 1.0))
	return COLORS[-1][1]


static func _on(c: Vector2, t: float, r: float) -> Vector2:
	return c + Vector2(cos(t), sin(t)) * r


## ゲージとバッジ。c は刺繍枠の真ん中、r は窓の半径（px）。v は見せている値、a は濃さ、pops は名前 → 跳ね（1→0）
static func draw(ci: CanvasItem, c: Vector2, r: float, u: float, v: float, a: float, badges: Array, pops: Dictionary) -> void:
	Icons.screen()
	var rr := r + GAP * u
	var wet := clampf((Damp.MID - v) / Damp.MID, 0.0, 1.0)
	if a > 0.01:
		_band(ci, c, rr, u, wet, a)
		# 下の端から今の所まで、値ごとの色で縫う（少しずつ区切って色を変える）
		var steps := int(clampf(v, Damp.LO, Damp.HI) / 4.0)
		var w := 9.0 * u
		for i in steps:
			var v0 := i * 4.0
			var v1 := minf(v0 + 4.0 + 0.6, v)
			var pts := PackedVector2Array([_on(c, angle_of(v0), rr), _on(c, angle_of((v0 + v1) / 2.0), rr), _on(c, angle_of(v1), rr)])
			ci.draw_polyline(pts, Color(color_of(v0 + 2.0), a), w, true)
		if v > 1.0:
			var all := PackedVector2Array()
			for i in 33:
				all.append(_on(c, lerpf(ARC_WET, angle_of(v), i / 32.0), rr))
			Icons.dashes(ci, all, Color(1, 1, 1), 1.2 * u, 3.0 * u, 3.0 * u, 0.45 * a)   # 糸の撚りの筋
		# 境目（150）: 帯を横切る太い生成りの糸
		var ab := angle_of(Damp.BOOST)
		var d := Vector2(cos(ab), sin(ab))
		Icons.thread(ci, PackedVector2Array([c + d * (rr - BAND * 0.8 * u), c + d * (rr + BAND * 0.8 * u)]), Icons.PAPER, 3.4 * u, a)
		# 段の境目の十字
		for b in [40.0, 90.0]:
			var t := angle_of(b)
			var dd := Vector2(cos(t), sin(t))
			var p := c + dd * rr
			var e := dd.orthogonal()
			for k in [-1.0, 1.0]:
				ci.draw_line(p + (dd + e * k) * 3.5 * u, p - (dd + e * k) * 3.5 * u, Color(Icons.THREAD, 0.75 * a), maxf(1.4 * u, 1.0), true)
		# 両端のワッペン
		Badges.end_patch(ci, "drop", _on(c, ARC_WET - 0.2, rr), END * u, a)
		Badges.end_patch(ci, "fire", _on(c, ARC_CRISP + 0.2, rr), END * u, a)
		# 今の所の赤い結び目
		Icons._o = _on(c, angle_of(v), rr)
		Icons._s = u
		Icons.patch(ci, Icons.circ(Vector2.ZERO, 8.5, 16), Icons.RED, a, false)
		ci.draw_circle(Icons._o + Vector2(-2.4, -2.4) * u, 2.3 * u, Color(1, 1, 1, 0.5 * a))
		Icons.screen()
	# バッジ: 刺繍枠の右上に、枠に沿って並べる（矢印はそれぞれの下）
	for i in badges.size():
		var b: Dictionary = badges[i]
		var p := _on(c, BADGE_FROM + i * BADGE_STEP, r + BADGE_R * u)
		Badges.draw_badge(ci, b, p, BADGE * u, 1.0, pops.get(b.key, 0.0))
	Icons.screen()


## 紙の帯（両側にランニングステッチ）。地は値ごとの色を生成りへ寄せた淡い色（下ほど青く、上ほど赤く）。湿るほど縁が波打つ
static func _band(ci: CanvasItem, c: Vector2, rr: float, u: float, wet: float, a: float) -> void:
	var n := 48
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var vals := PackedFloat32Array()
	for i in n + 1:
		var k := i / float(n)
		var t := lerpf(ARC_WET - 0.06, ARC_CRISP + 0.06, k)
		var wave := sin(t * 38.0) * wet * 1.6 * u
		outer.append(_on(c, t, rr + BAND * 0.5 * u + wave))
		inner.append(_on(c, t, rr - BAND * 0.5 * u - wave))
		vals.append(lerpf(Damp.LO - 6.0, Damp.HI + 6.0, k))
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
		ci.draw_colored_polygon(q, Color(Icons.PAPER.lerp(color_of((vals[i] + vals[i + 1]) / 2.0), 0.45), a))
	var edge := poly.duplicate()
	edge.append(poly[0])
	ci.draw_polyline(edge, Color(Icons.PAPER_EDGE, 0.9 * a), maxf(1.2 * u, 1.0), true)
	for k in 2:   # 縁から少し内に、両側のステッチ
		var line := PackedVector2Array()
		for p in (outer if k == 0 else inner):
			line.append(p + (c - p).normalized() * (2.4 * u if k == 0 else -2.4 * u))
		Icons.dashes(ci, line, Icons.THREAD, 1.1 * u, 4.0 * u, 3.0 * u, 0.7 * a)
