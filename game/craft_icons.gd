extends RefCounted
## 工房（型紙と布を買う・縫う・畳む）の絵。hud_icons.gd と同じ手芸の部品（フェルトのワッペン・刺繍の破線・糸）で、
## 文字を使わずに描く。どの絵も 64 × 64 の箱（中心が原点、y は下向き）。
##   品物: 型紙（クラフト紙に、ソリの形の切り取り線。大きいソリほど形が大きい）、布（たたんだ布の束）、
##         畳んだソリ（折り紙の包み。布の色に、折り目の線）
##   お金: 4 段のボタン（money。木 1・真鍮 10・白蝶貝 100・螺鈿 1000）。値段は段ごとに分けて並べる（craft.gd の split）。
##         文字は使わず、色・光り方・穴の数で見分ける（木は茶色で穴 2 つ、真鍮は金色でふちに刻みと光、白蝶貝は白に虹色、
##         螺鈿は漆黒に貝の小片の虹色）
##   案内の絵: shears（雪のボタンの糸を、裁ちばさみで切る）
##   案内の絵: shop（売り子）、fold（畳む）、unfold（広げる）、set（ミシンにセット）
## 看板（shopkeeper.gd）と売り台・持ち物の列（craft_ui.gd）が使う。

const Icons := preload("res://hud_icons.gd")
const Fabrics := preload("res://fabrics.gd")

const KRAFT := Color(0.84, 0.72, 0.52)       # 型紙のクラフト紙
const COIN := Color(0.70, 0.50, 0.30)        # 木のボタン
const SIZE_K := {"sack": 0.55, "small": 0.7, "mid": 0.85, "large": 1.0}


static func _at(center: Vector2, size: float) -> void:
	Icons._o = center
	Icons._s = size / 64.0


## 名前の絵（案内のワッペンの絵。hud_icons.gd の icon から呼ばれる）
static func draw(ci: CanvasItem, name: String, a: float, tint: Color) -> void:
	match name:
		"shop":
			_pattern(ci, Vector2(-8, 2), 0.7, "mid", a, -0.12)
			coin(ci, Vector2(14, 14), 9.0, a)
			coin(ci, Vector2(20, 2), 7.0, a)
		"fold":
			_folding(ci, a, true)
		"unfold":
			_folding(ci, a, false)
		"set":
			_pattern(ci, Vector2(-12, -6), 0.55, "mid", a, -0.2)
			_fabric(ci, Vector2(10, -4), 0.7, Fabrics.color("navy"), a)
			Icons.arrow(ci, Vector2(0, 12), Vector2(0, 28), Icons.THREAD, a, 2.0)
		"hand":
			Icons.mitten(ci, Vector2(0, 2), 0.0, tint, a, true, 1.5)
		"shears":   # 雪に縫い留めたボタンと、その糸を切る裁ちばさみ
			coin(ci, Vector2(-8, 12), 13.0, a)
			_shears(ci, Vector2(8, -6), a)
		"sack":   # 米袋（口を麻ひもで縛った、クラフト紙の袋に赤い帯）
			rice_sack(ci, Vector2(0, 2), 1.0, KRAFT, Color("B8402E"), a)
		"gear":   # 装備の画面: 背負いかばん（2026-10-29 代表「Iのインベントリは別でカードつくってバックか装備のアイコンが良い」）
			backpack(ci, Vector2(0, 2), 1.0, a)
		"lamp":   # 帯のランタン（点いている）
			lantern(ci, Vector2(0, 2), 1.0, "box", true, a)
		"shopkeeper":   # 売り子のおじさんの顔: 紺のとんがり帽、紙の顔、丸眼鏡、綿のひげ
			var indigo := Color(0.20, 0.25, 0.46)
			Icons.patch(ci, PackedVector2Array([Vector2(-20, -6), Vector2(4, -30), Vector2(14, -24), Vector2(20, -6)]), indigo, a, false)
			Icons.patch(ci, Icons.rr(-26, -10, 52, 7, 3), indigo.lightened(0.15), a, false)
			Icons.patch(ci, Icons.ell(Vector2(0, 4), 14, 13, 18), Color(0.93, 0.84, 0.70), a, false)
			Icons.patch(ci, PackedVector2Array([Vector2(-15, 6), Vector2(15, 6), Vector2(10, 22), Vector2(0, 30), Vector2(-10, 22)]), Color(0.97, 0.96, 0.93), a, false)
			for s in [-1.0, 1.0]:
				ci.draw_arc(Icons._o + Vector2(6 * s, 2) * Icons._s, 5.0 * Icons._s, 0, TAU, 14, Color(0.16, 0.14, 0.13, a), maxf(1.2 * Icons._s, 1.0), true)


## 持ち物・品物の絵を center に size px で
static func item(ci: CanvasItem, it: Dictionary, center: Vector2, size: float, a := 1.0) -> void:
	_at(center, size)
	match it.get("kind", ""):
		"pattern":
			_pattern(ci, Vector2.ZERO, 1.0, it.get("sled", "mid"), a)
		"fabric":
			_fabric(ci, Vector2.ZERO, 1.0, Fabrics.color(it.get("fabric", "red")), a)
		"folded":
			_folded(ci, Vector2.ZERO, it.get("sled", "mid"), Fabrics.color(it.get("fabric", "red")), a)
			# 包みの面に貼った名札（手に持った包みと同じ並び）。窓に、広げた姿がくるくる回る
			var Tags := preload("res://sled_tags.gd")
			Tags.draw_on_packet(ci, center + Vector2(0, size * 0.02), size * 0.86, it.get("tag", 0),
					Tags.turntable(it.get("sled", "mid"), it.get("fabric", "")), a)
		_:
			Icons.mitten(ci, Vector2(0, 2), 0.0, Icons.RED, a, true, 1.5)


## 米袋の袋の色（標準はクラフト紙、色違いは布の色）と、帯の色（標準は印刷の赤、色違いは地の上で読める色）
static func sack_body(spec: Dictionary) -> Color:
	return Fabrics.color(spec.fabric) if spec.get("fabric", "") != "" else KRAFT


static func sack_band(spec: Dictionary) -> Color:
	if spec.get("fabric", "") == "":
		return Color("B8402E")
	var c := Fabrics.color(spec.fabric)
	return Color("EFE6D2") if c.get_luminance() < 0.5 else c.darkened(0.6)


## 雪に置いた米袋を斜め前から見た形（ゲームの米袋と同じ: クラフト紙の平たい袋、口と底に紙テープと縫い目、
## まんなかに赤い丸に「米」、前に 2 本の帯）。c は袋のまんなか、前は右。band は印刷の色、body は袋の色
static func sack_flat(ci: CanvasItem, c: Vector2, sc: float, band: Color, a := 1.0, body := KRAFT) -> void:
	var bag := PackedVector2Array([Vector2(-22, -5), Vector2(18, -7), Vector2(24, 5), Vector2(-20, 8)])   # 少し奥へ傾いた袋
	Icons.patch(ci, Icons.xf(bag, 0.0, c, sc), body, a, false)
	var shade := PackedVector2Array([Vector2(-20, 8), Vector2(24, 5), Vector2(24, 7.5), Vector2(-20, 10.5)])   # 厚み
	Icons.patch(ci, Icons.xf(shade, 0.0, c, sc), body.darkened(0.25), a, false)
	for t in [[-21.0, -18.0], [18.5, 21.5]]:   # 口と底の紙テープ
		var x0: float = t[0]
		var x1: float = t[1]
		Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(x0, -5.2 - (x0 + 22) * 0.05), Vector2(x1, -5.4 - (x1 + 22) * 0.05),
				Vector2(x1 + 0.6, 7.6 - (x1 + 20) * 0.07), Vector2(x0 + 0.6, 7.8 - (x0 + 20) * 0.07)]), 0.0, c, sc), Color("EFE6D2"), a, false)
	for k in [12.0, 14.5]:   # 前の 2 本の帯
		Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(k, -6.3), Vector2(k + 3.6, 6.0)]), 0.0, c, sc), band, 1.3, a)
	var mc := c + Vector2(-2, 0.5) * sc   # 赤い丸に「米」の十字
	ci.draw_arc(Icons._o + mc * Icons._s, 4.6 * sc * Icons._s, 0.0, TAU, 18, Color(band, a), maxf(1.1 * sc * Icons._s, 1.0), true)
	for ang in [0.0, PI / 2, PI / 4, -PI / 4]:
		var d := Vector2.from_angle(ang) * 3.0 * sc
		ci.draw_line(Icons._o + (mc - d) * Icons._s, Icons._o + (mc + d) * Icons._s, Color(band, a), maxf(0.9 * sc * Icons._s, 1.0), true)


## 丸めた米袋（帯に下げる形）。band は帯の色、body は袋の色
static func sack_roll(ci: CanvasItem, c: Vector2, sc: float, band: Color, a := 1.0, body := KRAFT) -> void:
	Icons.patch(ci, Icons.xf(Icons.rr(-20, -9, 40, 18, 9), 0.0, c, sc), body, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-5, -9.5, 10, 19, 2), 0.0, c, sc), band, a, false)
	var end := c + Vector2(15, 0) * sc
	ci.draw_arc(Icons._o + end * Icons._s, 6.0 * sc * Icons._s, 0.0, TAU * 0.8, 14, Color(body.darkened(0.35), a), maxf(1.2 * Icons._s, 1.0), true)
	ci.draw_arc(Icons._o + end * Icons._s, 3.0 * sc * Icons._s, 0.0, TAU * 0.8, 10, Color(body.darkened(0.35), a), maxf(1.0 * Icons._s, 1.0), true)
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-12, -9), Vector2(-12, 9)]), 0.0, c, sc), Icons.CAP, 1.4, a)


## 米袋の絵: 立てた袋。口を麻ひもで縛ってすぼめ、胴に帯と丸の印刷、底に縫い目。body は袋の色、band は帯と印刷の色。
## 2026-10-29 代表「米袋のアイコン変えてほしい」: 丸めた形（sack_roll）は帯に下げた包みに見えず、米袋と読めなかった
static func rice_sack(ci: CanvasItem, c: Vector2, sc: float, body := KRAFT, band := Color("B8402E"), a := 1.0, outline := false) -> void:
	var shape := PackedVector2Array([Vector2(-7, -10), Vector2(-12, -21), Vector2(-5, -17), Vector2(0, -22), Vector2(5, -17), Vector2(12, -21),
		Vector2(7, -10), Vector2(13, -3), Vector2(16, 9), Vector2(15, 19), Vector2(11, 23), Vector2(-11, 23), Vector2(-15, 19), Vector2(-16, 9), Vector2(-13, -3)])
	var pts := Icons.xf(shape, 0.0, c, sc)
	if outline:   # 出している: 帯は空で、破線の形
		Icons.dashes(ci, pts, Icons.PAPER_EDGE, 1.4, 3.0, 2.0, a, true)
		return
	var edge := body.darkened(0.35)
	Icons.patch(ci, pts, body, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-15.5, 1, 31, 7, 1), 0.0, c, sc), band, a, false)   # 帯
	Icons.patch(ci, Icons.circ(c + Vector2(0, 14) * sc, 4.2 * sc, 14), band, a, false)   # 丸の印刷
	ci.draw_circle(Icons._o + (c + Vector2(0, 14) * sc) * Icons._s, 1.6 * sc * Icons._s, Color(body, a))
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-9, -10), Vector2(9, -10)]), 0.0, c, sc), Color("C9AC78").darkened(0.15), 2.4, a)   # 麻ひも
	for s in [-1.0, 1.0]:   # 結び目の輪
		ci.draw_arc(Icons._o + (c + Vector2(4.0 * s, -12.5) * sc) * Icons._s, 2.6 * sc * Icons._s, 0.0, TAU, 12, Color(Color("C9AC78").darkened(0.15), a), maxf(1.4 * Icons._s * sc, 1.0), true)
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-3, -15), Vector2(-5, -6)]), 0.0, c, sc), edge, 0.9, 0.7 * a)   # すぼめた口のしわ
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(3, -15), Vector2(5, -6)]), 0.0, c, sc), edge, 0.9, 0.7 * a)
	Icons.dashes(ci, Icons.xf(PackedVector2Array([Vector2(-13, 20), Vector2(13, 20)]), 0.0, c, sc), edge, 1.0, 2.6, 1.8, a)   # 底の縫い目
	ci.draw_polyline(Icons._map(pts + PackedVector2Array([pts[0]])), Color(edge, 0.8 * a), maxf(1.0 * Icons._s * sc, 1.0), true)


## ランタンの絵（帯のランタン）。look は lantern.gd の LOOKS（box 木の手提げ / paper 提灯）。lit なら芯が光り、まわりに暖かい光の輪。
## outline なら提げていない（破線の形）
static func lantern(ci: CanvasItem, c: Vector2, sc: float, look := "box", lit := true, a := 1.0, outline := false) -> void:
	var o := Icons._o + c * Icons._s
	var k := sc * Icons._s
	if outline:
		Icons.dashes(ci, Icons.xf(Icons.rr(-13, -16, 26, 34, 4), 0.0, c, sc), Icons.PAPER_EDGE, 1.4, 3.0, 2.0, a, true)
		return
	if lit:   # 光の輪（重ねた薄い円）
		for i in 4:
			ci.draw_circle(o + Vector2(0, 2) * k, (30.0 - i * 6.0) * k, Color(1.0, 0.74, 0.38, 0.16 * a))
	var glow := Color(1.0, 0.90, 0.55) if lit else Color(0.62, 0.60, 0.58)
	var arc := PackedVector2Array()
	for i in 13:   # 毛糸を巻いた取っ手
		var t := PI + PI * i / 12.0
		arc.append(Vector2(cos(t) * 8.0, -20.0 + sin(t) * 8.0))
	if look == "paper":   # 提灯: 赤い毛糸で提げ、骨の輪の入った紙の胴、上下に濃い木の口
		Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(0, -27), Vector2(0, -16)]), 0.0, c, sc), Color("B8402E"), 2.2, a)
		Icons.patch(ci, Icons.xf(Icons.ell(Vector2(0, 2), 13, 17, 20), 0.0, c, sc), glow, a, false)
		for y in [-10.0, -4.0, 2.0, 8.0, 14.0]:
			var w := 13.0 * sqrt(maxf(0.0, 1.0 - pow((y - 2.0) / 17.0, 2.0)))
			Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-w, y), Vector2(w, y)]), 0.0, c, sc), Icons.WOOD.darkened(0.3), 1.0, 0.8 * a)
		Icons.patch(ci, Icons.xf(Icons.rr(-7, -17, 14, 4, 1.5), 0.0, c, sc), Icons.WOOD.darkened(0.35), a, false)
		Icons.patch(ci, Icons.xf(Icons.rr(-7, 18, 14, 4, 1.5), 0.0, c, sc), Icons.WOOD.darkened(0.35), a, false)
		return
	Icons.thread(ci, Icons.xf(arc, 0.0, c, sc), Color("B8402E"), 2.6, a)
	var dark := Icons.WOOD.darkened(0.3)
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(-15, -13), Vector2(0, -21), Vector2(15, -13)]), 0.0, c, sc), dark, a, false)   # 屋根
	Icons.patch(ci, Icons.xf(Icons.rr(-11, -12, 22, 26, 1), 0.0, c, sc), Color(1.0, 0.78, 0.42, 0.75) if lit else Color(0.36, 0.40, 0.50, 0.75), a, false)   # フィルムの窓
	Icons.patch(ci, Icons.xf(Icons.ell(Vector2(0, 3), 5, 7, 14), 0.0, c, sc), glow, a, false)   # 和紙で包んだ芯
	Icons.dashes(ci, Icons.xf(Icons.rr(-9, -10, 18, 22, 1), 0.0, c, sc), Color(1, 1, 1, 0.9), 0.9, 2.2, 1.6, a, true)   # 白い糸の枠
	for x in [-13.0, 10.0]:   # 柱
		Icons.patch(ci, Icons.xf(Icons.rr(x, -13, 3, 28, 1), 0.0, c, sc), Icons.WOOD, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-15, -15, 30, 3.5, 1), 0.0, c, sc), Icons.WOOD, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-16, 14, 32, 5, 1.5), 0.0, c, sc), Icons.WOOD, a, false)


## 背負いかばん（装備の画面の印）: フェルトの胴に、ボタンで留めるかぶせ、前のポケット、上の持ち手
static func backpack(ci: CanvasItem, c: Vector2, sc: float, a := 1.0) -> void:
	var felt := Color(0.62, 0.40, 0.26)
	var arc := PackedVector2Array()
	for i in 11:
		var t := PI + PI * i / 10.0
		arc.append(Vector2(cos(t) * 7.0, -17.0 + sin(t) * 6.0))
	Icons.thread(ci, Icons.xf(arc, 0.0, c, sc), felt.darkened(0.35), 2.6, a)   # 持ち手
	Icons.patch(ci, Icons.xf(Icons.rr(-17, -17, 34, 40, 10), 0.0, c, sc), felt, a, true, felt.lightened(0.4))   # 胴
	Icons.patch(ci, Icons.xf(Icons.rr(-11, 6, 22, 13, 4), 0.0, c, sc), felt.lightened(0.12), a, true, felt.lightened(0.5))   # ポケット
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(-17, -9), Vector2(-17, -12), Vector2(-12, -17), Vector2(12, -17), Vector2(17, -12), Vector2(17, -9),
		Vector2(12, 2), Vector2(0, 5), Vector2(-12, 2)]), 0.0, c, sc), felt.darkened(0.18), a, true, felt.lightened(0.35))   # かぶせ
	coin(ci, c + Vector2(0, 1) * sc, 3.6 * sc, a)   # 木のボタンで留める
	for x in [-9.0, 9.0]:   # 肩ひもの付け根
		Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(x, 2), Vector2(x, 22)]), 0.0, c, sc), felt.darkened(0.3), 1.4, 0.8 * a)


## 木のボタン（1）。c と r は絵の座標。茶色、穴 2 つに糸を 2 本渡す、つやなし
static func coin(ci: CanvasItem, c: Vector2, r: float, a := 1.0, col := COIN) -> void:
	Icons.patch(ci, Icons.circ(c, r, 18), col, a, false)
	ci.draw_arc(Icons._o + c * Icons._s, r * 0.72 * Icons._s, 0, TAU, 18, Color(col.darkened(0.3), 0.7 * a), maxf(0.8 * Icons._s, 1.0), true)
	for k in 2:
		var h := c + Vector2(r * 0.3 * (1 if k == 0 else -1), 0)
		ci.draw_circle(Icons._o + h * Icons._s, maxf(r * 0.15 * Icons._s, 0.8), Color(Icons.SHADOW, 0.75 * a))
	if r * Icons._s > 5.0:   # 穴に通した糸（2 本）
		for dy in [-0.09, 0.09]:
			Icons.thread(ci, PackedVector2Array([c + Vector2(-r * 0.3, r * dy), c + Vector2(r * 0.3, r * dy)]), Icons.CAP, 0.45 * r / 7.0, a)


const BRASS := Color(0.86, 0.66, 0.26)
const PEARL := Color(0.95, 0.94, 0.91)
const LACQUER := Color(0.07, 0.05, 0.06)

## お金のボタン（look: wood・brass・pearl・raden）。c と r は絵の座標。t は光の時計（きらっと光る向きが回る）
static func money(ci: CanvasItem, c: Vector2, r: float, look: String, a := 1.0, t := 0.0) -> void:
	var o := Icons._o + c * Icons._s
	var rr := r * Icons._s
	match look:
		"wood":
			coin(ci, c, r, a)
		"brass":   # 金色、ふちに刻み、穴 4 つ、きらっと光る
			var rim := PackedVector2Array()
			for k in 40:
				var ang := TAU * k / 40
				rim.append(c + Vector2(cos(ang), sin(ang)) * r * (1.0 if k % 2 == 0 else 0.9))
			Icons.patch(ci, rim, BRASS, a, false)
			ci.draw_circle(o, rr * 0.78, Color(BRASS.lightened(0.12), a))
			ci.draw_arc(o, rr * 0.62, 0, TAU, 20, Color(BRASS.darkened(0.3), 0.7 * a), maxf(0.8 * Icons._s, 1.0), true)
			_holes4(ci, o, rr, Color(0.35, 0.22, 0.05, 0.8 * a))
			ci.draw_arc(o, rr * 0.72, -2.4 + t, -1.5 + t, 8, Color(1, 0.97, 0.85, 0.85 * a), maxf(rr * 0.14, 1.0), true)   # 光の筋
			_glint(ci, o + Vector2(rr * 0.45, -rr * 0.5), rr * 0.5, Color(1.0, 0.95, 0.75, a))
		"pearl":   # 白く薄い、穴 4 つ、見る向きで虹色
			Icons.patch(ci, Icons.circ(c, r, 22), PEARL, a, false)
			for k in 3:   # 虹色のにじみ（色の弧がゆっくり回る）
				var hue := fposmod(t * 0.08 + k * 0.33, 1.0)
				ci.draw_arc(o, rr * (0.5 + 0.13 * k), t * 0.5 + k * 2.1, t * 0.5 + k * 2.1 + 1.6, 12, Color.from_hsv(hue, 0.3, 1.0, 0.55 * a), maxf(rr * 0.13, 1.0), true)
			ci.draw_arc(o, rr * 0.92, 0, TAU, 22, Color(0.75, 0.75, 0.78, 0.7 * a), maxf(0.7 * Icons._s, 1.0), true)
			_holes4(ci, o, rr * 0.85, Color(0.55, 0.55, 0.6, 0.8 * a))
			_glint(ci, o + Vector2(-rr * 0.4, -rr * 0.45), rr * 0.45, Color(1, 1, 1, a))
		"raden":   # 漆黒に、貝の小片が花の形に虹色にきらめく。穴 4 つを金の輪で
			Icons.patch(ci, Icons.circ(c, r, 22), LACQUER, a, false)
			for k in 6:
				for j in 2:
					var ang := TAU * k / 6 + j * 0.12
					var p := o + Vector2(cos(ang), sin(ang)) * rr * (0.5 + 0.22 * j)
					var hue := fposmod(t * 0.1 + k * 0.17 + j * 0.3, 1.0)
					var sz := rr * (0.13 - 0.03 * j)
					ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -sz), p + Vector2(sz, 0), p + Vector2(0, sz * 0.8), p + Vector2(-sz * 0.9, 0)]),
							Color.from_hsv(hue, 0.4, 1.0, 0.95 * a))
			_holes4(ci, o, rr * 0.7, Color(BRASS, a))
			ci.draw_arc(o, rr * 0.97, 0, TAU, 22, Color(0.3, 0.25, 0.28, a), maxf(0.8 * Icons._s, 1.0), true)
			_glint(ci, o + Vector2(rr * 0.42, -rr * 0.48), rr * 0.55, Color.from_hsv(fposmod(t * 0.15, 1.0), 0.35, 1.0, a))


## 穴 4 つ（画面の px）
static func _holes4(ci: CanvasItem, o: Vector2, rr: float, col: Color) -> void:
	for k in 4:
		var h := o + Vector2(cos(TAU * k / 4 + PI / 4), sin(TAU * k / 4 + PI / 4)) * rr * 0.26
		ci.draw_circle(h, maxf(rr * 0.09, 0.8), col)


## きらっ: 4 本の細い光の筋（画面の px）
static func _glint(ci: CanvasItem, p: Vector2, len: float, col: Color) -> void:
	if len < 2.0:
		return
	for d in [Vector2(1, 0), Vector2(0, 1)]:
		ci.draw_line(p - d * len, p + d * len, col, maxf(len * 0.14, 1.0), true)
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		ci.draw_line(p - d * len * 0.4, p + d * len * 0.4, Color(col, col.a * 0.7), maxf(len * 0.09, 1.0), true)


## 裁ちばさみ（絵の座標）: 開いた 2 枚の刃と、黒い持ち手の輪
static func _shears(ci: CanvasItem, c: Vector2, a: float) -> void:
	var steel := Color(0.78, 0.8, 0.84)
	for side in [-1.0, 1.0]:
		var tip := c + Vector2(side * 9.0, -20.0)
		var pv := c + Vector2(0, 2)
		Icons.patch(ci, Icons.xf(PackedVector2Array([pv + Vector2(-2, 0), tip, pv + Vector2(2, 0)]), 0.0, Vector2.ZERO, 1.0), steel, a, false)
		var ring := c + Vector2(-side * 8.0, 14.0)
		Icons.thread(ci, PackedVector2Array([pv, ring + Vector2(side * 2.0, -4.0)]), Color(0.1, 0.08, 0.1), 2.6, a)
		Icons.patch(ci, Icons.circ(ring, 5.5, 14), Color(0.1, 0.08, 0.1), a, false)
		Icons.patch(ci, Icons.circ(ring, 3.0, 12), Icons.CAP, a, false)
	Icons.patch(ci, Icons.circ(c + Vector2(0, 2), 2.0, 10), BRASS, a, false)


## 値段: 段ごとに分けたボタンを並べる（大きい段から、3 個ずつの段）。center は画面の px、r はボタンの半径（px）。
## col は木のボタンの色（足りないときの赤など）
static func price(ci: CanvasItem, center: Vector2, n: int, r: float, a := 1.0, col := COIN) -> void:
	var list: Array = preload("res://craft.gd").pieces(n)
	var m := list.size()
	var per := 3 if m > 3 else m
	var rows := ceili(m / 3.0)
	for i in m:
		var row := i / 3
		var in_row := mini(per, m - row * 3)
		var x := (i % 3 - (in_row - 1) / 2.0) * r * 2.2
		var y := (row - (rows - 1) / 2.0) * r * 2.1
		_at(center + Vector2(x, y), 64.0)
		if list[i] == "wood":
			coin(ci, Vector2.ZERO, r, a, col)
		else:
			money(ci, Vector2.ZERO, r, list[i], a)


## 型紙: クラフト紙の 1 枚に、ソリを上から見た形の切り取り線（破線）。紙の大きさは同じで、ソリの形が大きさで変わる
static func _pattern(ci: CanvasItem, c: Vector2, sc: float, kind: String, a: float, rot := -0.08) -> void:
	var sheet := Icons.xf(Icons.rr(-20, -25, 40, 50, 3), rot, c, sc)
	Icons.patch(ci, sheet, KRAFT, a, false)
	var fold := Icons.xf(PackedVector2Array([Vector2(12, -25), Vector2(20, -25), Vector2(20, -17)]), rot, c, sc)   # 折った角
	Icons.patch(ci, fold, KRAFT.darkened(0.15), a, false)
	var k: float = SIZE_K.get(kind, 0.85)
	var shape: PackedVector2Array
	match kind:
		"sack":   # 米袋: 口を縛った袋
			shape = PackedVector2Array([Vector2(-9, -6), Vector2(-3, -10), Vector2(3, -10), Vector2(9, -6), Vector2(10, 14), Vector2(-10, 14)])
		"small":  # 成形ソリ: 丸い桶
			shape = Icons.rr(-9, -16, 18, 32, 8)
		"large":  # 8 人乗り: 長く、前が反る
			shape = Icons.rr(-10, -16, 20, 36, 3)
		_:
			shape = Icons.rr(-10, -15, 20, 32, 3)
	var cut := Icons.xf(shape, rot, c, sc * k)
	Icons.dashes(ci, cut, Icons.THREAD, 1.2, 3.0, 2.2, a, true)
	var dots: Array = []
	match kind:
		"mid": dots = [Vector2(0, -8), Vector2(0, 1), Vector2(0, 10)]
		"large": dots = [Vector2(-4, -9), Vector2(4, -9), Vector2(-4, -1), Vector2(4, -1), Vector2(-4, 7), Vector2(4, 7), Vector2(-4, 14), Vector2(4, 14)]
		"small": dots = [Vector2(0, -6), Vector2(0, 6)]
		"sack": dots = [Vector2(0, 4)]
	for d in dots:   # 席の印
		var p: Vector2 = Transform2D(rot, c) * (d * sc * k)
		ci.draw_circle(Icons._o + p * Icons._s, maxf(1.6 * Icons._s * sc, 1.0), Color(Icons.RED, 0.85 * a))
	if kind == "large":   # 反った前
		var curl := PackedVector2Array()
		for i in 7:
			var t := i / 6.0 * PI
			curl.append(Vector2(-10 + 20 * i / 6.0, -16 - sin(t) * 4))
		Icons.dashes(ci, Icons.xf(curl, rot, c, sc * k), Icons.THREAD, 1.2, 3.0, 2.2, a)
	# 留めた待ち針の赤い頭
	ci.draw_circle(Icons._o + (Transform2D(rot, c) * (Vector2(-14, -19) * sc)) * Icons._s, 2.6 * Icons._s * sc, Color(Icons.RED, a))
	# 畳める（一人用）型紙の印: 右下の角に、折り目の入った小さな折り紙の包み
	if preload("res://craft.gd").foldable(kind):
		var fc: Vector2 = Transform2D(rot, c) * (Vector2(11, 16) * sc)
		Icons.patch(ci, Icons.xf(Icons.rr(-6, -6, 12, 12, 1.5), PI / 4 + rot, fc, sc), Icons.RED, a, false)
		Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(-6, -6), Vector2(6, -6), Vector2(0, 0)]), PI / 4 + rot, fc, sc), Icons.RED.darkened(0.2), a, false)
		Icons.dashes(ci, Icons.xf(PackedVector2Array([Vector2(-6, 0), Vector2(6, 0)]), PI / 4 + rot, fc, sc), Icons.CAP, 0.9, 1.6, 1.2, a)


## 布: たたんだ布を 2 枚重ねた束。上の布の角が折り返る
static func _fabric(ci: CanvasItem, c: Vector2, sc: float, col: Color, a: float) -> void:
	Icons.patch(ci, Icons.xf(Icons.rr(-22, -6, 44, 22, 4), 0.0, c + Vector2(2, 4) * sc, sc), col.darkened(0.18), a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-22, -16, 44, 24, 4), 0.0, c, sc), col, a, true, col.lightened(0.45) if col.get_luminance() < 0.6 else col.darkened(0.45))
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(10, 8), Vector2(22, 8), Vector2(22, -2)]), 0.0, c, sc), col.lightened(0.2), a, false)
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-22, -2), Vector2(22, -2)]), 0.0, c, sc), col.darkened(0.3), 0.8, 0.6 * a)


## 畳んだソリ: 布の色の折り紙の包み（四角を対角に折った形）。大きいソリほど包みが大きい
static func _folded(ci: CanvasItem, c: Vector2, kind: String, col: Color, a: float) -> void:
	var k: float = 0.65 + 0.35 * SIZE_K.get(kind, 0.85)
	var sq := Icons.xf(Icons.rr(-20, -20, 40, 40, 3), PI / 4, c, k)
	Icons.patch(ci, sq, col, a, true, col.lightened(0.45) if col.get_luminance() < 0.6 else col.darkened(0.45))
	var crease := col.lightened(0.3) if col.get_luminance() < 0.6 else col.darkened(0.25)
	Icons.dashes(ci, Icons.xf(PackedVector2Array([Vector2(-20, 0), Vector2(20, 0)]), PI / 4, c, k), crease, 1.0, 2.5, 2.0, a)
	Icons.dashes(ci, Icons.xf(PackedVector2Array([Vector2(0, -20), Vector2(0, 20)]), PI / 4, c, k), crease, 1.0, 2.5, 2.0, a)
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(0, 0)]), PI / 4, c, k), col.darkened(0.12), a, false)


## 畳む・広げるの絵: 大きな四角が半分に折れる（矢印つき）
static func _folding(ci: CanvasItem, a: float, fold: bool) -> void:
	var col := Fabrics.color("red")
	Icons.patch(ci, Icons.rr(-24, -2, 24, 22, 2), col.darkened(0.1), a, false)
	if fold:
		Icons.patch(ci, PackedVector2Array([Vector2(0, -2), Vector2(18, -18), Vector2(18, 4), Vector2(0, 20)]), col, a, true)
		Icons.arc_arrow(ci, Vector2(0, 0), 18.0, -0.3, -PI + 0.5, Icons.THREAD, a, 2.0)
	else:
		Icons.patch(ci, Icons.rr(0, -2, 24, 22, 2), col, a, true)
		Icons.arc_arrow(ci, Vector2(0, 0), 18.0, -PI + 0.4, -0.4, Icons.THREAD, a, 2.0)
	Icons.dashes(ci, PackedVector2Array([Vector2(0, -4), Vector2(0, 22)]), Icons.THREAD, 1.0, 2.5, 2.0, a)


## 看板の品書き: 上の段に型紙 4 枚と値段、下の段に布 6 色と値段。rect は板の px
static func menu(ci: CanvasItem, r: Rect2) -> void:
	Icons.screen()
	ci.draw_rect(r, Color(0.36, 0.42, 0.33))   # 濃い緑のフェルトの板
	var uv := PackedVector2Array()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, Color(0.36, 0.42, 0.33), uv, Icons.felt())
	var inset := Rect2(r.position + Vector2(14, 14), r.size - Vector2(28, 28))
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4, 9.0, 6.0, 0.8, true)
	var w := r.size.x
	var h := r.size.y
	var big := h * 0.40
	var coin_r := h * 0.032
	for i in 4:
		var kind: String = ["sack", "small", "mid", "large"][i]
		var cx := r.position.x + w * (0.14 + 0.24 * i)
		var cy := r.position.y + h * 0.26
		item(ci, {"kind": "pattern", "sled": kind}, Vector2(cx - big * 0.22, cy), big)
		price(ci, Vector2(cx + big * 0.36, cy), preload("res://craft.gd").PATTERN_PRICE[kind], coin_r)
	var small := h * 0.30
	for i in Fabrics.ORDER.size():
		var cx := r.position.x + w * (0.1 + 0.16 * i)
		var cy := r.position.y + h * 0.66
		item(ci, {"kind": "fabric", "fabric": Fabrics.ORDER[i]}, Vector2(cx, cy), small)
		price(ci, Vector2(cx, cy + small * 0.55), preload("res://craft.gd").FABRIC_PRICE, coin_r)
