extends RefCounted
## フェルトの色の輪と明るさの帯。服を染める画面（dye_ui.gd）とソリの見本帳（sled_book_ui.gd）で同じ物を使う。
## 色は Vector3（色合い 0〜1・鮮やかさ 0〜1・明るさ V_MIN〜1）で持つ。

const Icons := preload("res://hud_icons.gd")

const RINGS := 6             # 色の輪の、外へ向かう段の数
const SEGS := 48             # 色の輪の、まわりの分け数
const V_MIN := 0.12          # 明るさの帯のいちばん暗い所


static func polar(c: Vector2, r: float, a: float, s: float) -> Vector2:
	return c + Vector2(cos(a), -sin(a)) * s * r


## 色の輪: まわりで色合い、外ほど鮮やか（明るさは帯の値）。フェルトの毛羽を重ねる。いまの色の所に丸い布
static func wheel(ci: CanvasItem, c: Vector2, r: float, hsv: Vector3, u: float) -> void:
	var felt := Icons.felt()
	Icons.screen()
	ci.draw_colored_polygon(Icons.circ(c + Vector2(2, 3) * u, r + 3.0 * u, 48), Color(Icons.SHADOW, 0.3))
	for ri in RINGS:
		var s0 := float(ri) / RINGS
		var s1 := float(ri + 1) / RINGS
		for k in SEGS:
			var a0 := TAU * k / SEGS
			var a1 := TAU * (k + 1) / SEGS
			var pts := PackedVector2Array([polar(c, r, a0, s0), polar(c, r, a0, s1), polar(c, r, a1, s1), polar(c, r, a1, s0)])
			var cols := PackedColorArray([Color.from_hsv(a0 / TAU, s0, hsv.z), Color.from_hsv(a0 / TAU, s1, hsv.z), Color.from_hsv(a1 / TAU, s1, hsv.z), Color.from_hsv(a1 / TAU, s0, hsv.z)])
			var uv := PackedVector2Array()
			for p in pts:
				uv.append(p / (40.0 * u))
			ci.draw_polygon(pts, cols, uv, felt)
	Icons.dashes(ci, Icons.circ(c, r - 5.0 * u, 48), Color(Icons.CAP, 0.7), 1.6 * u, 6.0 * u, 4.0 * u, 1.0, true)
	var at := polar(c, r, hsv.x * TAU, hsv.y)
	ci.draw_circle(at, 11.0 * u, Color(Icons.SHADOW, 0.3))
	ci.draw_circle(at, 10.0 * u, Color.from_hsv(hsv.x, hsv.y, hsv.z))
	ci.draw_arc(at, 10.0 * u, 0, TAU, 20, Icons.CAP, 3.0 * u, true)
	ci.draw_arc(at, 13.0 * u, 0, TAU, 20, Icons.THREAD, 1.6 * u, true)


## 明るさの帯: 上ほど明るい。いまの色合いと鮮やかさで。いまの明るさの所に赤い糸の結び目
static func value_bar(ci: CanvasItem, r: Rect2, hsv: Vector3, u: float) -> void:
	Icons.screen()
	ci.draw_rect(Rect2(r.position + Vector2(2, 3) * u, r.size), Color(Icons.SHADOW, 0.3))
	var top := Color.from_hsv(hsv.x, hsv.y, 1.0)
	var bot := Color.from_hsv(hsv.x, hsv.y, V_MIN)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / (40.0 * u))
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]), uv, Icons.felt())
	ci.draw_rect(r, Color(Icons.THREAD, 0.6), false, 1.2 * u)
	var y := r.end.y - (hsv.z - V_MIN) / (1.0 - V_MIN) * r.size.y
	Icons.dashes(ci, PackedVector2Array([Vector2(r.position.x - 8.0 * u, y), Vector2(r.end.x + 8.0 * u, y)]), Icons.RED, 3.0 * u, 7.0 * u, 3.0 * u, 1.0)
	ci.draw_circle(Vector2(r.end.x + 10.0 * u, y), 5.5 * u, Icons.RED)


## 輪の上の点 p を押した: 色合いと鮮やかさを読む（明るさはそのまま）
static func pick_wheel(c: Vector2, r: float, p: Vector2, hsv: Vector3) -> Vector3:
	var d := p - c
	return Vector3(fposmod(atan2(-d.y, d.x) / TAU, 1.0), clampf(d.length() / r, 0.0, 1.0), hsv.z)


## 帯の上の点 p を押した: 明るさを読む
static func pick_value(r: Rect2, p: Vector2, hsv: Vector3) -> Vector3:
	return Vector3(hsv.x, hsv.y, clampf(V_MIN + (r.end.y - p.y) / r.size.y * (1.0 - V_MIN), V_MIN, 1.0))
