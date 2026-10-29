extends RefCounted
## 工房（型紙と布を買う・縫う・畳む）の絵。hud_icons.gd と同じ手芸の部品（フェルトのワッペン・刺繍の破線・糸）で、
## 文字を使わずに描く。どの絵も 64 × 64 の箱（中心が原点、y は下向き）。
##   品物: 型紙（クラフト紙に、ソリの形の切り取り線。大きいソリほど形が大きい）、布（たたんだ布の束）、
##         畳んだソリ（折り紙の包み。布の色に、折り目の線）
##   値段: 木のボタン（お金の代わり。いまは仮）を数だけ並べる
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
			Tags.draw_on_packet(ci, center + Vector2(0, size * 0.02), size * 0.86, int(it.get("tag", 0)),
					Tags.turntable(it.get("sled", "mid"), it.get("fabric", "")), a)
		_:
			Icons.mitten(ci, Vector2(0, 2), 0.0, Icons.RED, a, true, 1.5)


## 木のボタン（お金）。c と r は絵の座標
static func coin(ci: CanvasItem, c: Vector2, r: float, a := 1.0, col := COIN) -> void:
	Icons.patch(ci, Icons.circ(c, r, 18), col, a, false)
	ci.draw_arc(Icons._o + c * Icons._s, r * 0.72 * Icons._s, 0, TAU, 18, Color(col.darkened(0.3), 0.7 * a), maxf(0.8 * Icons._s, 1.0), true)
	for k in 4:
		var h := c + Vector2(cos(TAU * k / 4 + PI / 4), sin(TAU * k / 4 + PI / 4)) * r * 0.3
		ci.draw_circle(Icons._o + h * Icons._s, maxf(r * 0.12 * Icons._s, 0.8), Color(Icons.SHADOW, 0.75 * a))
	if r * Icons._s > 5.0:   # 穴に通した糸の十字
		Icons.thread(ci, PackedVector2Array([c + Vector2(-r * 0.21, -r * 0.21), c + Vector2(r * 0.21, r * 0.21)]), Icons.CAP, 0.5 * r / 7.0, a)
		Icons.thread(ci, PackedVector2Array([c + Vector2(r * 0.21, -r * 0.21), c + Vector2(-r * 0.21, r * 0.21)]), Icons.CAP, 0.5 * r / 7.0, a)


## 値段: n 個のボタンを並べる（3 個ずつの段）。center は画面の px、r はボタンの半径（px）
static func price(ci: CanvasItem, center: Vector2, n: int, r: float, a := 1.0, col := COIN) -> void:
	var per := 3 if n > 3 else n
	var rows := ceili(n / 3.0)
	for i in n:
		var row := i / 3
		var in_row := mini(per, n - row * 3)
		var x := (i % 3 - (in_row - 1) / 2.0) * r * 2.2
		var y := (row - (rows - 1) / 2.0) * r * 2.1
		_at(center + Vector2(x, y), 64.0)
		coin(ci, Vector2.ZERO, r, a, col)


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
