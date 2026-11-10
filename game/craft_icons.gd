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
const Peg := preload("res://peg.gd")
const MountainGoods := preload("res://mountain_goods.gd")

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
		"mountain":   # 山男の売り場: 焚き火セットとボタン
			var o := Icons._o
			var s := Icons._s
			_at(o + Vector2(-6, 0) * s, 64.0 * s * 0.8)
			MountainGoods.draw(ci, {"kind": "campfire"}, a)
			Icons._o = o
			Icons._s = s
			coin(ci, Vector2(18, 14), 9.0, a)
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
		"campfire":   # 焚き火を組む: 雪の上の、薪の櫓と切り紙の炎
			campfire(ci, Vector2(0, 4), 1.0, a, true)
		"fire_out":   # 焚き火を消す: 炎の上から雪（綿の玉）がかかる
			campfire(ci, Vector2(0, 8), 0.85, a, false)
			for k in 3:
				Icons.patch(ci, Icons.circ(Vector2(-12 + k * 12, -18 - (k % 2) * 6), 7.0, 12), Icons.SNOW, a, true, Color(0.75, 0.78, 0.86))
			Icons.arrow(ci, Vector2(0, -28), Vector2(0, -10), Icons.THREAD, a, 2.0)
		"shears":   # 雪に縫い留めたボタンと、その糸を切る裁ちばさみ
			coin(ci, Vector2(-8, 12), 13.0, a)
			_shears(ci, Vector2(8, -6), a)
		"peg", "unpeg":   # ペグを刺す・抜く（絵は peg.gd）
			Peg.hint(ci, a, name == "peg")
		"sack":   # 米袋（口を麻ひもで縛った、クラフト紙の袋に赤い帯）
			rice_sack(ci, Vector2(0, 2), 1.0, KRAFT, Color("B8402E"), a)
		"gear":   # 装備の画面: 背負いかばん（2026-10-29 代表「Iのインベントリは別でカードつくってバックか装備のアイコンが良い」）
			backpack(ci, Vector2(0, 2), 1.0, a)
		"lamp":   # 帯のランタン（点いている）
			lantern(ci, Vector2(0, 2), 1.0, "box", true, a)
		"food":   # 雪だるまの食べ物屋: 綿の雪玉とペレット（料理のもとの毛玉）
			Icons.patch(ci, Icons.circ(Vector2(-10, 6), 13.0, 16), Color(0.97, 0.97, 0.95), a, false)
			Icons.patch(ci, Icons.circ(Vector2(12, -4), 10.0, 14), Color(0.86, 0.55, 0.25), a, true)
			Icons.patch(ci, Icons.circ(Vector2(16, 14), 7.0, 12), Color(0.95, 0.85, 0.45), a, true)
		"dryer", "dryer_out":   # 乾燥機に入る・出る: 丸い戸（紺の縁に白い破線、窓に丸まった人形）と、回る矢印か外へ出る矢印
			_dryer_door(ci, Vector2(-4, 2), a, tint, name == "dryer")
		"cook":   # 調理: 湯気の上るどんぶり
			Icons.patch(ci, PackedVector2Array([Vector2(-22, 0), Vector2(22, 0), Vector2(16, 18), Vector2(-16, 18)]), Color(0.82, 0.30, 0.22), a, true)
			for x in [-8.0, 2.0, 12.0]:
				Icons.thread(ci, PackedVector2Array([Vector2(x, -4), Vector2(x - 4, -12), Vector2(x + 2, -20), Vector2(x - 2, -28)]), Color(0.98, 0.98, 0.96), 3.0, a)
		"eat":   # 食べる: ひと口かじったおにぎり（白い三角に海苔の帯、右上が欠けている）
			var rice := PackedVector2Array([Vector2(-2, -24), Vector2(4, -22), Vector2(22, 12), Vector2(20, 20), Vector2(-20, 20), Vector2(-22, 12)])
			Icons.patch(ci, rice, Color(0.98, 0.97, 0.94), a, true, Color(0.80, 0.76, 0.68))
			Icons.patch(ci, Icons.rr(-9, 6, 18, 15, 2), Color(0.16, 0.22, 0.18), a, false)
			for k in 3:   # かじった跡: 歯の形の小さな丸を 3 つ、地の色で抜く
				Icons.patch(ci, Icons.circ(Vector2(9 + k * 4.5, -8 + k * 5.5), 5.0, 12), Icons.CAP, a, false)
		"trash":   # 捨てる: 編みかご（紙ひもの屑かご）
			var basket := PackedVector2Array([Vector2(-18, -12), Vector2(18, -12), Vector2(13, 22), Vector2(-13, 22)])
			Icons.patch(ci, basket, Color(0.72, 0.56, 0.36), a, true, Color(0.50, 0.36, 0.22))
			for k in 4:   # 編み目の横の段
				var y := -5.0 + k * 7.0
				var hw := 17.0 - (y + 12.0) * 0.15
				Icons.thread(ci, PackedVector2Array([Vector2(-hw, y), Vector2(hw, y)]), Color(0.50, 0.36, 0.22), 1.6, a)
			Icons.patch(ci, Icons.rr(-21, -17, 42, 7, 3), Color(0.60, 0.44, 0.27), a, false)   # 縁
		"shopkeeper":   # 売り子のおじさんの顔: 紺のとんがり帽、紙の顔、丸眼鏡、綿のひげ
			var indigo := Color(0.20, 0.25, 0.46)
			Icons.patch(ci, PackedVector2Array([Vector2(-20, -6), Vector2(4, -30), Vector2(14, -24), Vector2(20, -6)]), indigo, a, false)
			Icons.patch(ci, Icons.rr(-26, -10, 52, 7, 3), indigo.lightened(0.15), a, false)
			Icons.patch(ci, Icons.ell(Vector2(0, 4), 14, 13, 18), Color(0.93, 0.84, 0.70), a, false)
			Icons.patch(ci, PackedVector2Array([Vector2(-15, 6), Vector2(15, 6), Vector2(10, 22), Vector2(0, 30), Vector2(-10, 22)]), Color(0.97, 0.96, 0.93), a, false)
			for s in [-1.0, 1.0]:
				ci.draw_arc(Icons._o + Vector2(6 * s, 2) * Icons._s, 5.0 * Icons._s, 0, TAU, 14, Color(0.16, 0.14, 0.13, a), maxf(1.2 * Icons._s, 1.0), true)


static var _tex := {}   # 料理の絵（パス → Texture2D）

## 持ち物・品物の絵を center に size px で
static func item(ci: CanvasItem, it: Dictionary, center: Vector2, size: float, a := 1.0) -> void:
	_at(center, size)
	if MountainGoods.has(it.get("kind", "")):   # 山男の棚の品物（焚き火セット・ペグ）
		MountainGoods.draw(ci, it, a)
		return
	match it.get("kind", ""):
		"food":   # 雪だるまの店のペレットか、できあがった料理（Blender で描いた絵。food.gd）
			var Food := preload("res://food.gd")
			var path: String = Food.dish_icon(it.dish, int(it.get("bites", 0))) if Food.done(it) else Food.pellet_icon(it.dish)
			if not _tex.has(path):   # 取っておく（描く命令は絵を持たないので、手放すと描くまでに消えて白い四角になる）
				_tex[path] = load(path) if ResourceLoader.exists(path) else null
			var t: Texture2D = _tex[path]
			if t:
				var s := size * (1.15 if Food.done(it) else 1.5)
				ci.draw_texture_rect(t, Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, a))
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


## 持ち物の名前（日本語。持ち物の列の上に出す）
const SLED_NAMES := {"sack": "米袋", "small": "2人のソリ", "mid": "3人のソリ", "large": "8人のソリ"}
const FABRIC_NAMES := {"red": "赤", "navy": "紺", "mustard": "からし", "holly": "深緑", "cream": "生成り", "plum": "紫"}
const DISH_NAMES := {"onigiri": "おにぎり", "taiyaki": "たい焼き", "nikuman": "肉まん", "korokke": "コロッケ", "hashbrown": "ハッシュドポテト",
		"fries": "フライドポテト", "hotsand": "ホットサンド", "yakiimo": "焼き芋", "hotcake": "ホットケーキ", "sanma": "焼きサンマ",
		"kaki": "焼き牡蠣", "yakisoba": "焼きそば", "ramen": "ラーメン", "udon": "うどん", "soba": "そば", "cocoa": "ココア",
		"oshiruko": "おしるこ", "corn": "コーンスープ", "clam": "クラムチャウダー", "greentea": "緑茶", "milk": "ホットミルク", "milktea": "ミルクティー"}


static func item_name(it: Dictionary) -> String:
	if MountainGoods.has(it.get("kind", "")):
		return MountainGoods.item_name(it)
	var sled: String = SLED_NAMES.get(it.get("sled", "mid"), "ソリ")
	var fab: String = FABRIC_NAMES.get(it.get("fabric", ""), "")
	match it.get("kind", ""):
		"pattern":
			return "%sの型紙" % sled
		"fabric":
			return "%sの布" % fab
		"folded":
			if it.get("sled") == "sack":
				return "畳んだ米袋" + ("（%s）" % fab if fab != "" else "")
			return "畳んだ%s（%s）" % [sled, fab] if fab != "" else "畳んだ" + sled
		"food":
			var dish: String = DISH_NAMES.get(it.get("dish", ""), "料理")
			return dish if preload("res://food.gd").done(it) else "%sのもと" % dish
	return ""


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


## ランタンの絵（帯のランタン）。look は lantern.gd の LOOKS（box 木の手提げ / paper 提灯 / 売り物の 8 つ）。lit なら芯が光り、
## まわりに形の色の光の輪。outline なら提げていない（破線の形）。hex は紙細工屋さんで染めた色（"" は形の色。lantern.gd の tint）
static func lantern(ci: CanvasItem, c: Vector2, sc: float, look := "box", lit := true, a := 1.0, outline := false, hex := "") -> void:
	var o := Icons._o + c * Icons._s
	var k := sc * Icons._s
	if outline:
		Icons.dashes(ci, Icons.xf(Icons.rr(-13, -16, 26, 34, 4), 0.0, c, sc), Icons.PAPER_EDGE, 1.4, 3.0, 2.0, a, true)
		return
	var Lt := preload("res://lantern.gd")
	if lit:   # 光の輪（重ねた薄い円）
		var lc: Color = Lt.tint(look, hex)
		for i in 4:
			ci.draw_circle(o + Vector2(0, 2) * k, (30.0 - i * 6.0) * k, Color(lc.r, lc.g * 1.08, lc.b * 0.95, 0.16 * a))
	var glow := Lt.tint(look, hex, true).lerp(Color.WHITE, 0.35) if lit else Color(0.62, 0.60, 0.58)
	if look in ["spool", "knit", "hoop", "yarnball", "thimble", "hotaru", "pearl"]:
		_lantern_ware(ci, c, sc, look, glow, lit, a)
		return
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
	var raden := look == "raden"   # 螺鈿の漆の灯籠: 木を黒い漆に、糸を金に、板に貝のかけら、下に茜の房
	var wood := Color(0.10, 0.08, 0.09) if raden else Icons.WOOD
	var dark := Color(0.06, 0.05, 0.06) if raden else Icons.WOOD.darkened(0.3)
	var gold := Color(0.85, 0.65, 0.24)
	if raden:
		Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(0, 19), Vector2(0, 27)]), 0.0, c, sc), Color("B8402E"), 2.4, a)
	Icons.thread(ci, Icons.xf(arc, 0.0, c, sc), gold if raden else Color("B8402E"), 2.6, a)
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(-15, -13), Vector2(0, -21), Vector2(15, -13)]), 0.0, c, sc), dark, a, false)   # 屋根
	var film := Color(1.0, 0.78, 0.42, 0.75) if lit else Color(0.36, 0.40, 0.50, 0.75)
	if lit and raden:
		film = Color(1.0, 0.62, 0.26, 0.8)
	if lit and hex != "":   # 染めた灯り
		film = Color(Lt.tint(look, hex, true), 0.75)
	Icons.patch(ci, Icons.xf(Icons.rr(-11, -12, 22, 26, 1), 0.0, c, sc), film, a, false)   # フィルムの窓
	Icons.patch(ci, Icons.xf(Icons.ell(Vector2(0, 3), 5, 7, 14), 0.0, c, sc), glow, a, false)   # 和紙で包んだ芯
	Icons.dashes(ci, Icons.xf(Icons.rr(-9, -10, 18, 22, 1), 0.0, c, sc), gold if raden else Color(1, 1, 1, 0.9), 0.9, 2.2, 1.6, a, true)   # 白い糸の枠
	for x in [-13.0, 10.0]:   # 柱
		Icons.patch(ci, Icons.xf(Icons.rr(x, -13, 3, 28, 1), 0.0, c, sc), wood, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-15, -15, 30, 3.5, 1), 0.0, c, sc), wood, a, false)
	Icons.patch(ci, Icons.xf(Icons.rr(-16, 14, 32, 5, 1.5), 0.0, c, sc), wood, a, false)
	if raden:
		for x in [-10.0, -3.0, 4.0, 11.0]:   # 貝のかけら
			Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(x - 2, 16.5), Vector2(x, 15), Vector2(x + 2, 16.5), Vector2(x, 18)]), 0.0, c, sc), Color(0.80, 0.90, 0.92), a, false)


## 売り物のランタンの絵（lantern の続き）。どれも上に提げる紐、体の形、光る所（glow）
static func _lantern_ware(ci: CanvasItem, c: Vector2, sc: float, look: String, glow: Color, lit: bool, a: float) -> void:
	var P := func(pts: PackedVector2Array, col: Color, al := 1.0) -> void:
		Icons.patch(ci, Icons.xf(pts, 0.0, c, sc), col, a * al, false)
	var T := func(pts: PackedVector2Array, col: Color, w: float, al := 1.0) -> void:
		Icons.thread(ci, Icons.xf(pts, 0.0, c, sc), col, w, a * al)
	var hemp := Color(0.79, 0.67, 0.47)
	var red := Color("B8402E")
	var cream := Color(0.94, 0.90, 0.82)
	var brass := Color(0.79, 0.60, 0.24)
	var wood := Icons.WOOD
	match look:
		"spool":   # 糸巻き: 木のつばを上下に、光る胴に生成りの糸の帯 3 つ
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -19)]), hemp, 1.8)
			P.call(Icons.rr(-9, -16, 18, 32, 1), glow)
			for y in [-12.0, -1.0, 9.0]:
				P.call(Icons.rr(-10, y, 20, 6, 1), cream)
				for j in 3:
					T.call(PackedVector2Array([Vector2(-10, y + 1.5 + j * 1.6), Vector2(10, y + 1.5 + j * 1.6)]), Color(0.70, 0.64, 0.55), 0.6, 0.8)
			P.call(Icons.rr(-15, -20, 30, 5, 2), wood)
			P.call(Icons.rr(-15, 16, 30, 5, 2), wood)
		"knit":    # 毛糸の編み帽子: 茜と生成りの縞、裾のゴム編み、てっぺんのぼんぼり
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -20)]), red, 2.0)
			P.call(Icons.ell(Vector2(0, 2), 13, 16, 20), glow)
			for i in 7:
				var y := -11.0 + i * 3.6
				var w := 13.0 * sqrt(maxf(0.0, 1.0 - pow((y - 2.0) / 16.0, 2.0)))
				T.call(PackedVector2Array([Vector2(-w, y), Vector2(w, y)]), cream if i % 3 == 1 else red, 2.2)
			P.call(Icons.rr(-10, 14, 20, 5, 1.5), red.darkened(0.15))
			P.call(Icons.circ(Vector2(0, -16), 4.5, 12), cream)
		"hoop":    # 刺繍枠と麻布: 3 本の麻ひも、上下の木の輪、生成りの布に赤いクロスステッチの雪
			for x in [-12.0, 0.0, 12.0]:
				T.call(PackedVector2Array([Vector2(0, -27), Vector2(x, -15)]), hemp, 1.0)
			P.call(Icons.rr(-13, -14, 26, 30, 1), glow)
			P.call(Icons.rr(-15, -16, 30, 4, 2), Color(0.82, 0.69, 0.49))
			P.call(Icons.rr(-15, 14, 30, 4, 2), Color(0.82, 0.69, 0.49))
			P.call(Icons.rr(14, -17, 3, 5, 1), brass)
			for f in [Vector2(-5, -4), Vector2(5, 6)]:
				for d in [Vector2(0, 0), Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
					var q: Vector2 = f + d
					T.call(PackedVector2Array([q + Vector2(-1.1, -1.1), q + Vector2(1.1, 1.1)]), red, 0.8)
					T.call(PackedVector2Array([q + Vector2(-1.1, 1.1), q + Vector2(1.1, -1.1)]), red, 0.8)
		"yarnball":   # 糸玉: 光る小さな玉を、からし色の毛糸の輪で包む
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -15)]), hemp, 1.8)
			P.call(Icons.circ(Vector2(0, 2), 8.0, 16), glow)
			for i in 6:
				var pts := Icons.ell(Vector2.ZERO, 16.0, 6.0 + 2.0 * i, 24)
				var rot := PI * i / 6.0
				var q := PackedVector2Array()
				for v in pts:
					q.append(v.rotated(rot) + Vector2(0, 2))
				q.append(q[0])
				T.call(q, Color(0.85, 0.64, 0.23) if i % 3 else hemp, 1.3)
		"thimble":   # 真鍮の指ぬき: 伏せた筒の、くぼみの穴から光の粒
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -19)]), red, 2.0)
			P.call(Icons.rr(-13, -19, 26, 38, 11), brass)
			P.call(Icons.rr(-14, 15, 28, 4, 1.5), brass.darkened(0.2))
			for j in 6:
				for i in 5:
					var x := -9.0 + i * 4.5 + (2.25 if j % 2 else 0.0)
					if absf(x) < 11.5:
						ci.draw_circle(Icons._o + (c + Vector2(x, -11.0 + j * 4.4) * sc) * Icons._s, 1.25 * sc * Icons._s, Color(glow, a) if lit else Color(0.30, 0.22, 0.12, a))
		"hotaru":   # 麻ひもの蛍かご: 濃い木の屋根と底、麻ひもの格子、中に光るおしりの蛍
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -19)]), hemp, 1.8)
			if lit:
				P.call(Icons.rr(-12, -13, 24, 27, 1), Color(glow, 0.35))
			for x in [-10.0, -5.0, 0.0, 5.0, 10.0]:
				T.call(PackedVector2Array([Vector2(x, -14), Vector2(x, 14)]), hemp, 0.9)
			for y in [-8.0, -2.0, 4.0, 10.0]:
				T.call(PackedVector2Array([Vector2(-12, y), Vector2(12, y)]), hemp, 0.9)
			for f in [Vector2(-5, -4), Vector2(4, 2), Vector2(-2, 8)]:
				ci.draw_circle(Icons._o + (c + f * sc) * Icons._s, 2.4 * sc * Icons._s, Color(glow, a) if lit else Color(0.45, 0.48, 0.30, a))
				ci.draw_circle(Icons._o + (c + (f + Vector2(2.4, -1.2)) * sc) * Icons._s, 1.5 * sc * Icons._s, Color(0.2, 0.18, 0.17, a))
			P.call(PackedVector2Array([Vector2(-15, -14), Vector2(-6, -20), Vector2(6, -20), Vector2(15, -14)]), wood.darkened(0.3))
			P.call(Icons.rr(-15, 14, 30, 4, 1.5), wood.darkened(0.3))
		"pearl":   # 白蝶貝のボタン: 真鍮の笠から、2 つ穴のボタンを鱗のように重ねて垂らす。奥に月白の灯り
			T.call(PackedVector2Array([Vector2(0, -27), Vector2(0, -20)]), cream, 1.4)
			P.call(Icons.ell(Vector2(0, 1), 9, 14, 18), glow)
			for j in 4:
				for i in 4:
					var q := Vector2(-10.5 + i * 7.0 + (3.5 if j % 2 else 0.0), -10.0 + j * 7.0)
					if absf(q.x) > 13.0:
						continue
					P.call(Icons.circ(q, 3.4, 12), Color(0.90, 0.92, 0.94), 0.92)
					for hx in [-1.0, 1.0]:
						ci.draw_circle(Icons._o + (c + (q + Vector2(hx, 0)) * sc) * Icons._s, 0.5 * sc * Icons._s, Color(0.55, 0.58, 0.62, a))
			P.call(PackedVector2Array([Vector2(-14, -14), Vector2(-5, -20), Vector2(5, -20), Vector2(14, -14)]), brass)


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


## 値段: 段ごとに分けたボタンを並べる（価値の低い順に左から。財布の山と同じ向き。3 個ずつの段）。center は画面の px、
## r はボタンの半径（px）。col は木のボタンの色（足りないときの赤など）
static func price(ci: CanvasItem, center: Vector2, n: int, r: float, a := 1.0, col := COIN) -> void:
	var list: Array = preload("res://craft.gd").pieces(n)
	list.reverse()
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


## 燃えている焚き火: 灰色の石の輪、薪の櫓、赤・橙・黄の切り紙の炎（lit が false なら炎は小さく）
static func campfire(ci: CanvasItem, c: Vector2, sc: float, a: float, lit: bool) -> void:
	Icons.patch(ci, Icons.xf(Icons.ell(Vector2(0, 18), 28, 7, 20), 0.0, c, sc), Icons.SNOW, a, false)
	for k in 5:
		Icons.patch(ci, Icons.xf(Icons.ell(Vector2(-22 + k * 11, 18), 6, 4, 10), 0.0, c, sc), Color(0.55, 0.53, 0.52), a, false)
	var bark := Color(0.52, 0.34, 0.20)
	for s in [-1.0, 1.0]:
		Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(16 * s, 16), Vector2(2 * s, -10)]), 0.0, c, sc), bark, 5.0, a)
	var fl := 1.0 if lit else 0.5
	var layers := [[Color(0.86, 0.26, 0.13), 1.0], [Color(0.96, 0.55, 0.16), 0.7], [Color(1.0, 0.86, 0.42), 0.42]]
	for l in layers:
		var k: float = l[1] * fl
		var flame := PackedVector2Array([Vector2(-12, 14), Vector2(-14, 2), Vector2(-7, -10), Vector2(-4, -2), Vector2(0, -24),
			Vector2(5, -6), Vector2(9, -14), Vector2(14, 2), Vector2(12, 14)])
		Icons.patch(ci, Icons.xf(flame, 0.0, c + Vector2(0, 14 - 14 * k) * sc, sc * k), l[0], a, false)


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


## 乾燥機の丸い戸（cook_station.gd の乾燥機）。spin なら、窓のまわりに回る矢印。でなければ、戸から右へ出る矢印
static func _dryer_door(ci: CanvasItem, c: Vector2, a: float, tint: Color, spin: bool) -> void:
	Icons.patch(ci, Icons.circ(c, 25.0, 28), Color(0.16, 0.22, 0.52), a, true)       # 紺の縁
	Icons.patch(ci, Icons.circ(c, 17.0, 24), Color(0.80, 0.86, 0.92), a, false)      # 窓（透明なフィルム）
	Icons.dashes(ci, Icons.circ(c, 20.5, 32), Icons.CAP, 1.6, 3.0, 2.5, a, true)    # 白い糸の留め
	if spin:
		Icons.doll(ci, c + Vector2(-4, 8), tint, "sit", a, 0.62)
		Icons.arc_arrow(ci, c, 30.0, -PI * 0.15, PI * 0.45, Icons.THREAD, a, 2.4)
	else:
		Icons.doll(ci, c + Vector2(20, 22), tint, "stand", a, 0.62)
		Icons.arrow(ci, c + Vector2(2, -2), c + Vector2(30, -8), Icons.THREAD, a, 2.4)



# ---- 店の札の、買える・買えないの見え方（2026-11-10 代表「単純にグレーにして選択不可にするだけでいいんだけど」
#      「LOCKしてるのを麻紐のつつみにして、でも荷物がパンパンなときは…画面全体をグレーにして荷物がパンパンですよって巾着からモノ溢れてるアイコンにする」）。
#      どの店の画面も、札の中身を描いたあとでこれを呼ぶ（山師・ソリ屋・見本帳・紙細工屋さん・連れ・雪だるまの店）。
#      札のようす（card_state）: "can" 買える・"money" お金（雪玉）が足りない（グレー、選べない）・"owned" もう持っている（今のまま、針の印）・
#      "locked" まだ売っていない（麻ひもの包み、選べない。shop_locks.gd）・"full" 持ち物がいっぱい（札ごとではなく、画面全体をグレーにしてあふれる巾着）

const SHADE := Color(0.46, 0.46, 0.49, 0.66)   # 買えない札にかぶせるグレー
const HEMP := Color(0.78, 0.66, 0.46)          # 麻ひも
const WRAP := Color(0.80, 0.68, 0.48)          # 包みのクラフト紙
const BAG := Color(0.30, 0.48, 0.33)           # かばんの巾着（装備の画面のかばんと同じ緑のフェルト）


## 札のようす。locked（ロック）・owned（もう持っている）・pay（払える）・room（持ち物に入る。場所を使わない品は true）の順に見る
static func card_state(locked: bool, owned: bool, pay: bool, room := true) -> String:
	if locked:
		return "locked"
	if owned:
		return "owned"
	if not room:
		return "full"
	return "can" if pay else "money"


## 選べる札か（買える・もう持っている）
static func pickable(state: String) -> bool:
	return state == "can" or state == "owned"


## お金が足りない札: 札の形 pts の上に、グレーをかぶせる（中の絵も値段もグレーに沈む）
static func shade_card(ci: CanvasItem, pts: PackedVector2Array) -> void:
	ci.draw_colored_polygon(pts, SHADE)


## まだ売っていない札: 札をクラフト紙で包み、麻ひもで十字に縛って蝶結び（中は見えない）。u は画面の倍率
static func wrap_card(ci: CanvasItem, card: Rect2, u := 1.0) -> void:
	Icons.screen()
	Icons.patch(ci, Icons.rr(card.position.x, card.position.y, card.size.x, card.size.y, 12.0 * u), WRAP, 1.0, true, WRAP.darkened(0.3))
	var c := card.get_center() + Vector2(0, -card.size.y * 0.06)
	for k in 3:   # 包みの折り目
		var x := card.position.x + card.size.x * (0.22 + 0.28 * k)
		Icons.thread(ci, PackedVector2Array([Vector2(x, card.position.y + 8.0 * u), Vector2(x + card.size.x * 0.08, card.end.y - 8.0 * u)]), WRAP.darkened(0.12), 1.4 * u, 0.6)
	var hw := maxf(4.0 * u, card.size.x * 0.04)
	Icons.thread(ci, PackedVector2Array([Vector2(card.position.x + 4.0 * u, c.y), Vector2(card.end.x - 4.0 * u, c.y)]), HEMP, hw, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(c.x, card.position.y + 4.0 * u), Vector2(c.x, card.end.y - 4.0 * u)]), HEMP, hw, 1.0)
	var b := minf(card.size.x, card.size.y) * 0.1
	for s in [-1.0, 1.0]:   # 蝶結び
		Icons.patch(ci, Icons.ell(c + Vector2(s * b * 1.1, -b * 0.35), b, b * 0.6, 14), HEMP, 1.0, false)
		Icons.thread(ci, PackedVector2Array([c, c + Vector2(s * b * 0.8, b * 1.6)]), HEMP.darkened(0.1), hw * 0.8, 1.0)
	Icons.patch(ci, Icons.circ(c, b * 0.45, 10), HEMP.darkened(0.15), 1.0, false)


## 持ち物がいっぱい: 売り場の板 board の全体をグレーにし、巾着から物があふれる印を大きく出す。
## 印は、at を渡せばそこに大きさ size で（グレーの上に残す札と重ならない所）、渡さなければ板のまんなかに
static func bag_full(ci: CanvasItem, board: Rect2, u := 1.0, at := Vector2.INF, size := 0.0) -> void:
	Icons.screen()
	ci.draw_colored_polygon(Icons.rr(board.position.x, board.position.y, board.size.x, board.size.y, 22.0 * u), SHADE)
	var s := size / 1.24 if size > 0.0 else minf(board.size.x, board.size.y) * 0.42
	var c := at if at != Vector2.INF else board.get_center()
	Icons.patch(ci, Icons.circ(c, s * 0.62, 36), Icons.CAP, 0.96, true, Icons.PAPER_EDGE)
	full_bag(ci, c + Vector2(0, s * 0.06), s * 0.9)


## 巾着から物があふれる印（大きさ s。まんなかが c）: 口の閉まらない緑の巾着の口から、型紙・布・ペレットがこぼれ出る
static func full_bag(ci: CanvasItem, c: Vector2, s: float) -> void:
	Icons.screen()
	# あふれた物（巾着のうしろと口の上）
	item(ci, {"kind": "pattern", "sled": "mid"}, c + Vector2(-s * 0.26, -s * 0.34), s * 0.42)
	item(ci, {"kind": "fabric", "fabric": "red"}, c + Vector2(s * 0.24, -s * 0.38), s * 0.4)
	Icons.screen()
	Icons.patch(ci, Icons.circ(c + Vector2(s * 0.02, -s * 0.5), s * 0.09, 12), Icons.PAPER, 1.0, true, Icons.PAPER_EDGE)   # 転がり出た雪玉
	# 巾着: ふくらんで、口の紐がゆるみ、口が開いたまま
	Icons.patch(ci, Icons.ell(c + Vector2(0, s * 0.1), s * 0.4, s * 0.34, 22), BAG, 1.0, true, BAG.darkened(0.35))
	Icons.patch(ci, Icons.ell(c - Vector2(0, s * 0.18), s * 0.3, s * 0.08, 16), BAG.darkened(0.45), 1.0, false)
	Icons.dashes(ci, PackedVector2Array([c + Vector2(-s * 0.32, -s * 0.12), c + Vector2(s * 0.32, -s * 0.12)]), Icons.CAP, 2.0, 5.0, 3.0, 0.9)
	Icons.thread(ci, PackedVector2Array([c + Vector2(s * 0.3, -s * 0.12), c + Vector2(s * 0.46, s * 0.05), c + Vector2(s * 0.42, s * 0.2)]), Icons.RED, 2.4, 1.0)   # ほどけた紐
	# 下へこぼれた物
	item(ci, {"kind": "fabric", "fabric": "navy"}, c + Vector2(-s * 0.4, s * 0.42), s * 0.3)


## 角を切った紙の札（hud_icons.gd の paper_tag）の形。お金が足りない札のグレーをかぶせるのに使う
static func tag_pts(rect: Rect2, cut: float) -> PackedVector2Array:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	return PackedVector2Array([Vector2(x + cut, y), Vector2(x + w - cut, y), Vector2(x + w, y + cut), Vector2(x + w, y + h),
		Vector2(x, y + h), Vector2(x, y + cut)])


## 米マークのワッペン（装備の画面の米袋の段の印。2026-11-10 代表「米袋のアイコン微妙。実物についてる米マークワッペンにしてほしい」）。
## 実物の米袋の布（props/sled_sack の刷り）にある、赤い輪の中の米の字形と、左右から上へ伸びる緑の稲穂を、生成りのフェルトの丸に縫い取る。c は真ん中、s は直径 (px)
static func kome_patch(ci: CanvasItem, c: Vector2, s: float, a := 1.0) -> void:
	Icons.screen()
	var r := s * 0.5
	Icons.patch(ci, Icons.circ(c, r, 28), Color(0.86, 0.76, 0.58), a, true, Color(0.62, 0.50, 0.34))
	Icons.dashes(ci, Icons.circ(c, r * 0.86, 28), Color(0.55, 0.42, 0.28), maxf(1.0, s * 0.02), s * 0.05, s * 0.035, 0.9 * a, true)
	var green := Color(0.36, 0.56, 0.30)
	var red := Color(0.76, 0.22, 0.17)
	var w := maxf(1.2, s * 0.045)
	for side in [-1.0, 1.0]:   # 稲穂: 下から外へふくらんで上へ伸び、穂先が内へ垂れる
		var arc := PackedVector2Array()
		for k in 10:
			var t := k / 9.0
			arc.append(c + Vector2(side * (r * 0.62 + sin(t * PI) * r * 0.06), lerpf(r * 0.48, -r * 0.42, t)))
		arc.append(c + Vector2(side * r * 0.40, -r * 0.62))
		Icons.thread(ci, arc, green, w, a)
		Icons.patch(ci, Icons.ell(c + Vector2(side * r * 0.46, -r * 0.6), r * 0.14, r * 0.06, 10), green, a, false)
	var ring := PackedVector2Array()
	for k in 25:
		ring.append(c + Vector2.from_angle(TAU * k / 24.0) * r * 0.42)
	Icons.thread(ci, ring, red, w, a)
	var q := r * 0.3   # 米の字形: 縦と横、上の 2 つの点（中へ向く）、下の 2 本の払い（真ん中から外へ）
	Icons.thread(ci, PackedVector2Array([c + Vector2(0, -q), c + Vector2(0, q)]), red, w * 1.1, a)
	Icons.thread(ci, PackedVector2Array([c + Vector2(-q, 0), c + Vector2(q, 0)]), red, w * 1.1, a)
	Icons.thread(ci, PackedVector2Array([c + Vector2(-q * 0.72, -q * 0.78), c + Vector2(-q * 0.36, -q * 0.34)]), red, w, a)
	Icons.thread(ci, PackedVector2Array([c + Vector2(q * 0.72, -q * 0.78), c + Vector2(q * 0.36, -q * 0.34)]), red, w, a)
	Icons.thread(ci, PackedVector2Array([c + Vector2(-q * 0.08, q * 0.1), c + Vector2(-q * 0.8, q * 0.82)]), red, w, a)
	Icons.thread(ci, PackedVector2Array([c + Vector2(q * 0.08, q * 0.1), c + Vector2(q * 0.8, q * 0.82)]), red, w, a)
