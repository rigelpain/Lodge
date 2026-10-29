extends RefCounted
## 乗って滑っているときの速さの表示（hud.gd が描く）。手芸の形で、速いほど盛り上がる。
## 案は 3 つ（design/hud/speedo-ideas.jpg で見比べた）:
##   bobbin  糸巻きがくるくる回り、ほどけた赤い糸が後ろ（左）へ流れる。横に大きな刺繍の数字   ← 決めたもの
##   tape    巻尺のケースからテープが勢いよく引き出され、目盛りが流れる
##   gauge   フェルトの半円に刺繍の目盛り。フェルトの針が振れる
## どれも box（画面の px の四角）の中に描く。speed は m/s、phase は回す・流すための積み上げ（速さ × 時間）、
## best は今日いちばんの速さ、pop は弾み（1→0）、a は薄さ。数字の単位は文字でなく、小さな風の筋の印。

const Icons := preload("res://hud_icons.gd")
const RideWind := preload("res://ride_wind.gd")
const TOP := 16.0            # 目盛りの上限 (m/s)。米袋で蹴って届く上限（sled.gd の KICK_TOP）
const SPOOL_WOOD := Color(0.78, 0.60, 0.38)
const TAPE := Color(0.98, 0.80, 0.30)


## k は盛り上がり（0〜1.6）。滑るときの風（ride_wind.gd）と同じ曲線にそろえる: level_of(speed)
static func draw(ci: CanvasItem, style: String, box: Rect2, speed: float, k: float, phase: float, best: float, pop: float, a: float) -> void:
	match style:
		"tape": _tape(ci, box, speed, k, phase, best, pop, a)
		"gauge": _gauge(ci, box, speed, k, phase, best, pop, a)
		_: _bobbin(ci, box, speed, k, phase, best, pop, a)


## 盛り上がり: 風と同じく 2 m/s から出て 9 m/s で満ち、その先（米袋の連打など）はさらに少しずつ増える
static func level_of(speed: float) -> float:
	return RideWind.level_of(speed) + clampf((speed - RideWind.SPEED_FULL) / 12.0, 0.0, 0.6)


## 速さの数字（大きな刺繍）と、単位の印（小さな風の筋）。at は数字の左の縦のまんなか
static func number(ci: CanvasItem, speed: float, at: Vector2, size: float, pop: float, a: float) -> void:
	var s := size * (1.0 + 0.35 * sin(pop * PI))
	var col := Icons.RED if pop > 0.0 else Icons.THREAD
	var w := Icons.stitched_text(ci, "%d" % int(speed), at, s, Color(col, a))
	Icons.icon(ci, "speed", at + Vector2(w + size * 0.55, size * 0.12), size * 0.85, a)


## 糸巻き: 木の端の板（三つ穴）が回り、巻いた赤い糸から、ほどけた糸が後ろへ波打って流れる
static func _bobbin(ci: CanvasItem, box: Rect2, speed: float, k: float, phase: float, best: float, pop: float, a: float) -> void:
	var u := box.size.y / 150.0
	var c := Vector2(box.position.x + box.size.x * 0.50, box.position.y + box.size.y * 0.5)
	var r := 56.0 * u
	# ほどけて後ろへ流れる糸（速いほど長く、波が細かく、流れが速い）
	var tail := PackedVector2Array()
	var start := c + Vector2(0, r * 0.62)
	var len := minf((70.0 + 150.0 * minf(k, 1.4)) * u, start.x - box.position.x)
	for i in 33:
		var f := i / 32.0
		var x := start.x - f * len
		var wave := sin(f * (6.0 + 10.0 * k) - phase * 1.4) * (3.0 + 6.0 * f) * u
		tail.append(Vector2(x, start.y + wave + f * f * 10.0 * u))
	Icons.screen()
	Icons.thread(ci, tail, Icons.RED, 3.2 * u, a * (0.4 + 0.6 * minf(1.0, k)))
	# 糸から舞う短い切れはし（速いときだけ）
	for i in int(6.0 * k):
		var f := fposmod(phase * 0.07 + i * 0.17, 1.0)
		var p := start + Vector2(-f * len * 1.1, sin(i * 2.3) * 16.0 * u - 6.0 * u)
		Icons.thread(ci, PackedVector2Array([p, p + Vector2(-10.0 * u, sin(i + phase) * 2.0 * u)]), Icons.RED.lightened(0.2), 1.6 * u, a * (1.0 - f))
	# 糸巻き（正面から: 木の端の板、巻いた糸の縁、三つ穴が回る）
	Icons.screen()
	Icons.patch(ci, Icons.circ(c, r, 32), SPOOL_WOOD, a, false)
	Icons.patch(ci, Icons.circ(c, r * 0.82, 28), Icons.RED, a, false)
	for i in 3:   # 巻いた糸の筋
		ci.draw_arc(c, r * (0.66 + i * 0.05), 0, TAU, 28, Color(Icons.RED.darkened(0.25), 0.5 * a), 1.2 * u, true)
	Icons.patch(ci, Icons.circ(c, r * 0.48, 24), SPOOL_WOOD.lightened(0.1), a, false)
	var spin := -phase * 0.9
	for i in 3:
		var ang := spin + TAU * i / 3.0
		var hp := c + Vector2(cos(ang), sin(ang)) * r * 0.28
		ci.draw_circle(hp, r * 0.09, Color(0.32, 0.22, 0.14, a))
	ci.draw_circle(c, r * 0.07, Color(0.25, 0.17, 0.11, a))
	# 回る勢いの弧（速いほど長い）
	if k > 0.2:
		var sweep := 0.6 + 1.6 * minf(k, 1.0)
		ci.draw_arc(c, r + 8.0 * u, -PI / 2.0 - spin * 0.0, -PI / 2.0 + sweep, 20, Color(Icons.THREAD, 0.55 * a), 2.0 * u, true)
		ci.draw_arc(c, r + 14.0 * u, PI / 2.0, PI / 2.0 + sweep * 0.7, 16, Color(Icons.THREAD, 0.35 * a), 1.6 * u, true)
	# 今日いちばんの印: 糸巻きのまわりの、その速さの角度に赤い待ち針
	if best > 1.0:
		var ba := -PI / 2.0 + TAU * clampf(best / TOP, 0.0, 1.0)
		var bp := c + Vector2(cos(ba), sin(ba)) * (r + 4.0 * u)
		Icons.thread(ci, PackedVector2Array([bp, bp + Vector2(cos(ba), sin(ba)) * 12.0 * u]), Color(0.7, 0.72, 0.76), 1.4 * u, a)
		ci.draw_circle(bp + Vector2(cos(ba), sin(ba)) * 13.0 * u, 3.6 * u, Color(Icons.RED, a))
	number(ci, speed, Vector2(c.x + r + 18.0 * u, c.y), 84.0 * u, pop, a)


## 巻尺: 丸いケースから黄色いテープが左へ引き出され、目盛りが速さで流れる
static func _tape(ci: CanvasItem, box: Rect2, speed: float, k: float, phase: float, best: float, pop: float, a: float) -> void:
	var u := box.size.y / 150.0
	var c := Vector2(box.position.x + box.size.x * 0.55, box.position.y + box.size.y * 0.5)
	var r := 44.0 * u
	var len := minf((80.0 + 180.0 * minf(k, 1.3)) * u, c.x - box.position.x)
	var y0 := c.y + r * 0.45
	var tape := Rect2(c.x - len, y0 - 9.0 * u, len, 18.0 * u)
	Icons.screen()
	Icons.patch(ci, Icons.rr(tape.position.x, tape.position.y, tape.size.x, tape.size.y, 2.0 * u), TAPE, a, false)
	var step := 12.0 * u
	var off := fposmod(phase * 6.0 * u, step)
	var x := c.x - off
	var n := 0
	while x > tape.position.x + 2.0:
		var big := (n + int(phase * 6.0 * u / step)) % 5 == 0
		ci.draw_line(Vector2(x, y0 - 9.0 * u), Vector2(x, y0 - 9.0 * u + (9.0 if big else 5.0) * u), Color(Icons.SHADOW, 0.7 * a), 1.2 * u, true)
		x -= step
		n += 1
	patch_case(ci, c, r, a)
	ci.draw_arc(c, r * 0.55, -phase * 0.6, -phase * 0.6 + 4.5, 20, Color(Icons.THREAD, 0.6 * a), 2.0 * u, true)
	number(ci, speed, Vector2(c.x + r + 16.0 * u, c.y), 58.0 * u, pop, a)


static func patch_case(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	Icons.patch(ci, Icons.circ(c, r, 30), Icons.RED, a, false)
	Icons.patch(ci, Icons.circ(c, r * 0.7, 26), Icons.RED.lightened(0.15), a, false)
	Icons.dashes(ci, Icons.circ(c, r * 0.86, 30), Icons.PAPER, 1.2, 4.0, 3.0, a, true)


## フェルトのメーター: 半円のフェルトに刺繍の目盛り、フェルトの針が振れる
static func _gauge(ci: CanvasItem, box: Rect2, speed: float, k: float, phase: float, best: float, pop: float, a: float) -> void:
	var u := box.size.y / 150.0
	var c := Vector2(box.position.x + box.size.x * 0.40, box.position.y + box.size.y * 0.80)
	var r := 92.0 * u
	var half := PackedVector2Array()
	for i in 25:
		var t := PI + PI * i / 24.0
		half.append(c + Vector2(cos(t), sin(t)) * r)
	Icons.screen()
	Icons.patch(ci, half, Icons.PAPER, a, false)
	for i in 9:   # 刺繍の目盛り（2 m/s ごと）
		var t := PI + PI * i / 8.0
		var d := Vector2(cos(t), sin(t))
		Icons.thread(ci, PackedVector2Array([c + d * r * 0.78, c + d * r * 0.93]), Icons.THREAD if i < 6 else Icons.RED, 2.0 * u, a)
	var wob := sin(phase * 3.0) * 0.02 * minf(speed / 8.0, 1.0)
	var ang := PI + PI * clampf(speed / TOP, 0.0, 1.0) + wob
	var d2 := Vector2(cos(ang), sin(ang))
	var n := Vector2(-d2.y, d2.x)
	Icons.patch(ci, PackedVector2Array([c + n * 5.0 * u, c + d2 * r * 0.82, c - n * 5.0 * u]), Icons.RED, a, false)
	ci.draw_circle(c, 8.0 * u, Color(Icons.WOOD, a))
	number(ci, speed, Vector2(c.x + r + 14.0 * u, c.y - 28.0 * u), 58.0 * u, pop, a)
