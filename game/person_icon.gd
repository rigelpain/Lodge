extends RefCounted
## HUD の札に出す人の形: 丸い頭と、太い線の胴・腕・脚だけの人型（笠や服は描かない。2026-10-31 代表「人形表示は傘とか服とか
## 付けずに、シンプルな人型アイコンにキャラカラー」）。色はその人のキャラの色（装備の画面で自分で決める。craft.gd の colors）。
## 頭の上にその人の名前（装備の画面で自分で決める。craft.gd の names）。持ち主には王冠を載せる。
##   姿: stand（立つ。つかんでいるだけの人）/ push（前のめりで両手を前へ）/ pull（前のめりで片手を後ろへ。紐を引く）/ sit（座る）
##   face は顔の向き（1 は右、-1 は左）。feet は足もと（座る姿は尻）、h は立った背の高さ（px）

const PAPER := Color(0.96, 0.93, 0.86)
const INK := Color(0.16, 0.15, 0.22)
const GOLD := Color(0.96, 0.76, 0.22)


## 人の形を描く
static func draw(ci: CanvasItem, feet: Vector2, h: float, col: Color, pose := "stand", face := 1.0, a := 1.0) -> void:
	var w := maxf(h * 0.17, 2.0)          # 胴の太さ
	var lw := maxf(h * 0.12, 1.6)         # 腕と脚の太さ
	var rim := maxf(h * 0.035, 1.0)       # 縁（どの地の上でも形が浮くように、暗い縁）
	var lean := 0.0
	match pose:
		"push": lean = 0.42
		"pull": lean = 0.32
	var X := func(v: Vector2) -> Vector2:   # 足もとを支点に前へ傾け、向きで左右を返す
		return feet + Vector2(v.x * face, v.y).rotated(lean * face) * h
	var hip := Vector2(0, -0.40)
	var neck := Vector2(0, -0.70)
	var head := Vector2(0, -0.86)
	var hr := 0.13
	var limbs: Array = []   # [始め, 終わり, 太さ]
	match pose:
		"sit":
			hip = Vector2(0, -0.02)
			neck = Vector2(-0.02, -0.32)
			head = Vector2(-0.02, -0.48)
			limbs = [[hip, Vector2(0.24, -0.02), lw], [Vector2(0.24, -0.02), Vector2(0.27, 0.16), lw],
				[Vector2(0, -0.27), Vector2(0.20, -0.12), lw]]
		"push":
			limbs = [[hip, Vector2(-0.10, 0.0), lw], [hip, Vector2(0.10, 0.0), lw],
				[Vector2(0, -0.64), Vector2(0.30, -0.66), lw]]
		"pull":
			limbs = [[hip, Vector2(-0.11, 0.0), lw], [hip, Vector2(0.11, 0.0), lw],
				[Vector2(0, -0.64), Vector2(-0.24, -0.46), lw], [Vector2(0, -0.64), Vector2(0.14, -0.44), lw]]
		_:
			limbs = [[hip, Vector2(-0.07, 0.0), lw], [hip, Vector2(0.07, 0.0), lw],
				[Vector2(0, -0.64), Vector2(-0.13, -0.40), lw], [Vector2(0, -0.64), Vector2(0.13, -0.40), lw]]
	var dark := col.darkened(0.55)
	# 縁を先に太く描いてから、色を重ねる
	for pass_i in 2:
		var c := Color(dark, a) if pass_i == 0 else Color(col, a)
		var e := rim if pass_i == 0 else 0.0
		for l in limbs:
			_bar(ci, X.call(l[0]), X.call(l[1]), l[2] + e * 2.0, c)
		_bar(ci, X.call(hip), X.call(neck), w + e * 2.0, c)
		ci.draw_circle(X.call(head), hr * h + e, c)
	# 顔の向き: 頭の前の側に小さな白い点
	ci.draw_circle(X.call(head + Vector2(hr * 0.45, -hr * 0.1)), maxf(h * 0.025, 0.8), Color(PAPER, 0.85 * a))


## 頭の上の所（王冠と名前を載せる所）
static func head_top(feet: Vector2, h: float, pose := "stand", face := 1.0) -> Vector2:
	var lean := 0.0
	var top := Vector2(0, -1.0)
	match pose:
		"push": lean = 0.42
		"pull": lean = 0.32
		"sit": top = Vector2(-0.02, -0.62)
	return feet + Vector2(top.x * face, top.y).rotated(lean * face) * h


## 王冠（持ち主の印）。c は王冠の下の縁のまんなか、s は幅（px）
static func crown(ci: CanvasItem, c: Vector2, s: float, a := 1.0) -> void:
	var hh := s * 0.62
	var pts := PackedVector2Array([c + Vector2(-s / 2.0, 0), c + Vector2(s / 2.0, 0), c + Vector2(s / 2.0, -hh),
		c + Vector2(s * 0.25, -hh * 0.45), c + Vector2(0, -hh * 1.05), c + Vector2(-s * 0.25, -hh * 0.45), c + Vector2(-s / 2.0, -hh)])
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_colored_polygon(pts, Color(GOLD, a))
	ci.draw_polyline(rim, Color(GOLD.darkened(0.55), a), maxf(s * 0.08, 1.0), true)
	ci.draw_rect(Rect2(c + Vector2(-s / 2.0, -hh * 0.28), Vector2(s, hh * 0.28)), Color(GOLD.darkened(0.15), a))
	for x in [-0.5, 0.0, 0.5]:   # 先の玉
		var tip := c + Vector2(s * x, -hh * (1.05 if x == 0.0 else 1.0))
		ci.draw_circle(tip, maxf(s * 0.09, 1.0), Color(0.86, 0.24, 0.22, a))


## 名前（頭の上）。at は字の下の縁のまんなか。字は紙の縁取りに、その人の色を濃くした色
static func name_label(ci: CanvasItem, text: String, at: Vector2, px: float, col: Color, a := 1.0) -> void:
	if text == "" or px < 5.0:
		return
	var font: Font = preload("res://hud_icons.gd")._bold_font()
	var fs := maxi(6, int(round(px)))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := at + Vector2(-tw / 2.0, -font.get_descent(fs))
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 3), Color(PAPER, a))
	var ink := col.darkened(0.3)
	if ink.get_luminance() > 0.32:   # 明るい色（からし・空色など）は、字だけ濃く
		ink = col.darkened(0.6)
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, a))


## 人の形・王冠・名前をまとめて
static func person(ci: CanvasItem, feet: Vector2, h: float, col: Color, pose: String, face: float, a: float, owner: bool, who_name: String, px: float) -> void:
	draw(ci, feet, h, col, pose, face, a)
	var top := head_top(feet, h, pose, face)
	if owner:
		crown(ci, top + Vector2(0, h * 0.02), h * 0.30, a)
		top.y -= h * 0.22
	name_label(ci, who_name, top - Vector2(0, h * 0.03), px, col, a)


static func _bar(ci: CanvasItem, p: Vector2, q: Vector2, w: float, c: Color) -> void:
	ci.draw_line(p, q, c, w, true)
	ci.draw_circle(p, w / 2.0, c)
	ci.draw_circle(q, w / 2.0, c)
