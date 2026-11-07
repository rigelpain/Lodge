extends RefCounted
## 双眼鏡（2026-11-07 代表「アイテムとしての双眼鏡と、テラスに固定の双眼鏡台が欲しいです。よく観光地にあるやつ」）。
## 持ち歩く双眼鏡の品目・値段・形・絵と、のぞいたときの画角・案内の絵。形は design/binoculars（フェルトを巻いた筒に木のボタンの目）。
## 売り場は山男の棚（mountain_goods.gd）。のぞく動きは player.gd の peek、画面の窓は binocular_view.gd、テラスの台は binocular_stand.gd。

const Icons := preload("res://hud_icons.gd")
const Props := preload("res://props.gd")

const KIND := "binoculars"
const NAME := "双眼鏡"
const ITEM := {"kind": KIND}
const PRICE := 30               # 木のボタンの何個分。ペグの束 6 と焚き火セット 15 より高く、何度でも使える
## 値段は代表が決めた（2026-11-08 代表「基本真鍮3、遠見白蝶貝5、夜目螺鈿1がいいです」）: 真鍮 3 枚 = 30、白蝶貝 5 枚 = 500、螺鈿 1 枚 = 1000
const WHEEL_STEP := 1.18        # ホイール 1 目盛りで画角を何倍にするか
const PAN_ZOOM := 0.12          # 二本指スクロールの効き。Godot は Mac のスクロール量の 0.03 倍で渡すので、約 430 pt の撫でで台の幅の端から端まで
const PINCH_ZOOM := 1.5         # つまむ・広げるの効き

## 手の双眼鏡の段（2026-11-08 代表「双眼鏡にグレード作って倍率の高いものとか暗視ができるもの（悪天候でも夜でも見える）など作ってほしい」）。
## 段は品物の kind で分ける（持ち物に別々に入り、山男の棚に 1 行ずつ並ぶ）。fov は始めの縦の画角、range は変えられる幅（x 最も寄る、y 最も引く）。
## 倍率はふだんの 75° との比: 40° 約 2 倍、24° 約 3.5 倍、16° 約 5.5 倍、12° 約 7 倍、6.5° 約 13.5 倍
const GRADES := {
	"binoculars": {"name": NAME, "price": PRICE, "fov": 24.0, "range": Vector2(16.0, 40.0), "night": false},
	"binoculars_far": {"name": "遠見の双眼鏡", "price": 500, "fov": 12.0, "range": Vector2(6.5, 40.0), "night": false},
	"binoculars_night": {"name": "夜目の双眼鏡", "price": 1000, "fov": 24.0, "range": Vector2(16.0, 40.0), "night": true},
}
const FOV_STAND := 10.0         # テラスの台の始めの画角（約 8.5 倍。観光地のものらしく強め）
const FOV_STAND_RANGE := Vector2(5.0, 24.0)    # テラスの台の幅（約 17 倍〜約 3.5 倍）
const STAND_SECONDS := 60.0     # テラスの台が 1 回で開いている長さ（秒）
const STAND_NARROW_FROM := 10.0 # 残りがこの秒になると、穴がゆっくりすぼみ始める（幕が下りてくる。赤や点滅の警告はしない）
const STAND_NARROW := 0.78      # 閉じる直前の穴の開き

static var hint_left := 1.0     # 案内の "free" の毛糸の長さ（0〜1。hud.gd が入れる）
const YARN := Color(0.95, 0.70, 0.22)   # のぞき窓の残りの毛糸と同じ色
const FELT := Color(0.25, 0.50, 0.53)
const INDIGO := Color(0.17, 0.24, 0.41)
const MUSTARD := Color(0.79, 0.60, 0.23)
const MIDNIGHT := Color(0.09, 0.12, 0.24)
const PEARL := Color(0.95, 0.95, 0.96)
const WOOD := Color(0.62, 0.42, 0.24)
const DARK := Color(0.14, 0.15, 0.18)


## 手の双眼鏡か（どの段でも）
static func is_item(it: Dictionary) -> bool:
	return GRADES.has(it.get("kind", ""))


## 持ち物の名前
static func item_name(it: Dictionary) -> String:
	return String(GRADES.get(it.get("kind", ""), GRADES[KIND]).name)


## 暗視ができる段か
static func night(kind: String) -> bool:
	return bool(GRADES.get(kind, GRADES[KIND]).night)


## 始めの画角。kind は "stand"（テラスの台）か品物の kind
static func fov(kind: String) -> float:
	return FOV_STAND if kind == "stand" else float(GRADES.get(kind, GRADES[KIND]).fov)


## 変えられる幅（x が最も寄った画角、y が最も引いた画角）
static func fov_range(kind: String) -> Vector2:
	return FOV_STAND_RANGE if kind == "stand" else GRADES.get(kind, GRADES[KIND]).range


## 画角の幅の中の位置（0 最も引いた … 1 最も寄った）。見た目の倍率に揃えるので対数で
static func zoom_of(kind: String, fov_deg: float) -> float:
	var r := fov_range(kind)
	return clampf(log(r.y / fov_deg) / log(r.y / r.x), 0.0, 1.0)


## 手に持つ形（-Z が景色の側、原点は筒の真ん中）。glb は +Z が景色の側なので裏返す
static func shape(kind := KIND) -> Node3D:
	var holder := Node3D.new()
	var g := Props.make("res://props/binoculars/%s.glb" % (kind if GRADES.has(kind) else KIND))
	g.rotation.y = PI
	holder.add_child(g)
	return holder


## 持ち物・品物の絵（64 × 64 の箱。Icons._o・_s は呼ぶ側が決めてある）。段ごとに描く
static func icon(ci: CanvasItem, a: float, kind := KIND) -> void:
	match kind:
		"binoculars_far":
			_far(ci, a)
		"binoculars_night":
			_lenses(ci, Vector2(0, 2), 1.0, a, MIDNIGHT, PEARL, Color(0.72, 0.74, 0.80))
			_moon(ci, Vector2(0, -19), a)
		_:
			_lenses(ci, Vector2(0, 2), 1.0, a)


## 基本・夜目: 2 本の筒とボタンの目
static func _lenses(ci: CanvasItem, c: Vector2, sc: float, a: float, felt := FELT, eye := WOOD, rim := Color(0.40, 0.25, 0.13)) -> void:
	for s: float in [-1.0, 1.0]:
		var at := c + Vector2(13.0 * s, 0) * sc
		Icons.patch(ci, Icons.xf(Icons.rr(-11, -13, 22, 26, 8), 0.0, at, sc), felt, a, false)
		ci.draw_circle(Icons._o + at * Icons._s, 9.5 * sc * Icons._s, Color(eye, a))
		ci.draw_arc(Icons._o + at * Icons._s, 6.8 * sc * Icons._s, 0, TAU, 18, Color(rim, a), maxf(1.0, 1.0 * Icons._s), true)
		for p: Vector2 in [Vector2(-2.2, -2.2), Vector2(2.2, -2.2), Vector2(-2.2, 2.2), Vector2(2.2, 2.2)]:
			ci.draw_circle(Icons._o + (at + p * sc) * Icons._s, 1.0 * sc * Icons._s, Color(DARK, a))
	Icons.patch(ci, Icons.xf(Icons.rr(-4, -5, 8, 10, 2), 0.0, c, sc), felt, a, false)


## 遠見: 上から見た長い 3 段の筒に山吹の帯、先に木のボタン
static func _far(ci: CanvasItem, a: float) -> void:
	for s: float in [-1.0, 1.0]:
		var x := 13.5 * s
		Icons.patch(ci, Icons.xf(Icons.rr(-8, 13, 16, 13, 3), 0.0, Vector2(x, 0)), INDIGO, a, false)
		Icons.patch(ci, Icons.xf(Icons.rr(-10, -3, 20, 16, 3), 0.0, Vector2(x, 0)), INDIGO, a, false)
		Icons.patch(ci, Icons.xf(Icons.rr(-12, -22, 24, 19, 4), 0.0, Vector2(x, 0)), INDIGO, a, false)
		Icons.patch(ci, Icons.xf(Icons.rr(-10, 10, 20, 4, 1), 0.0, Vector2(x, 0)), MUSTARD, a, false)
		Icons.patch(ci, Icons.xf(Icons.rr(-12, -6, 24, 4, 1), 0.0, Vector2(x, 0)), MUSTARD, a, false)
		ci.draw_circle(Icons._o + Vector2(x, -22) * Icons._s, 10.0 * Icons._s, Color(WOOD, a))
		ci.draw_arc(Icons._o + Vector2(x, -22) * Icons._s, 7.2 * Icons._s, 0, TAU, 18, Color(0.40, 0.25, 0.13, a), maxf(1.0, 1.0 * Icons._s), true)
		for p: Vector2 in [Vector2(-2.3, 0), Vector2(2.3, 0)]:
			ci.draw_circle(Icons._o + (Vector2(x, -22) + p) * Icons._s, 1.1 * Icons._s, Color(DARK, a))
	Icons.patch(ci, Icons.rr(-3.5, 2, 7, 12, 2), MUSTARD, a, false)


## 夜目の三日月と星（濃い丸を重ねて欠けさせる）
static func _moon(ci: CanvasItem, c: Vector2, a: float) -> void:
	ci.draw_circle(Icons._o + c * Icons._s, 8.0 * Icons._s, Color(0.96, 0.92, 0.70, a))
	ci.draw_circle(Icons._o + (c + Vector2(3.8, -1.8)) * Icons._s, 7.0 * Icons._s, Color(0.99, 0.97, 0.93, a))


## 案内の絵（hud_icons.gd の icon から）。木のボタン 1 枚か雪玉 1 個を入れてのぞく。何もなければ赤い ×。字は使わない
##   which: "ball" 雪玉で / "button" 木のボタンで / "none" 入れる物がない / "hand" 手の双眼鏡をのぞく / "off" 双眼鏡を下ろす /
##          "free" 払った時間の中（値段の絵の代わりに、のぞき窓と同じ残りの毛糸。長さは hint_left）
static func hint(ci: CanvasItem, which: String, a: float) -> void:
	if which == "hand":
		_lenses(ci, Vector2(0, 0), 0.95, a)
		return
	_lenses(ci, Vector2(0, -13), 0.7, a)
	if which == "off":
		Icons.arrow(ci, Vector2(0, 5), Vector2(0, 27), Icons.RED, a, 3.2)
		return
	if which == "free":
		Icons.patch(ci, Icons.rr(-24, 11, 48, 9, 4), Color(0.17, 0.18, 0.21), a, false)
		var w := 44.0 * clampf(hint_left, 0.0, 1.0)
		if w > 0.5:
			Icons.patch(ci, Icons.rr(-w * 0.5, 13, w, 5, 2.5), YARN, a, false)
		return
	var at := Vector2(0, 15)
	match which:
		"ball":
			ci.draw_circle(Icons._o + at * Icons._s, 12.0 * Icons._s, Color(0.97, 0.97, 1.0, a))
			ci.draw_arc(Icons._o + at * Icons._s, 12.0 * Icons._s, 0, TAU, 22, Color(0.28, 0.40, 0.62, a), maxf(1.4, 1.8 * Icons._s), true)
		"button":
			ci.draw_circle(Icons._o + at * Icons._s, 12.0 * Icons._s, Color(WOOD, a))
			ci.draw_arc(Icons._o + at * Icons._s, 8.6 * Icons._s, 0, TAU, 20, Color(0.40, 0.25, 0.13, a), maxf(1.0, 1.4 * Icons._s), true)
			for s: float in [-1.0, 1.0]:
				ci.draw_circle(Icons._o + (at + Vector2(3.0 * s, 0)) * Icons._s, 1.5 * Icons._s, Color(DARK, a))
		"none":
			for s: float in [-1.0, 1.0]:
				Icons.thread(ci, PackedVector2Array([at + Vector2(-10, -10 * s), at + Vector2(10, 10 * s)]), Icons.RED, 3.6, a)
