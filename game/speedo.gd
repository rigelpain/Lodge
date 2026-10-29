extends RefCounted
## 乗って滑っているときの速さの表示（hud.gd が描く）。木の糸巻き（ボビン）が回り、ほどけた糸が後ろへ流れて、
## 画面の下の端に縫い目を縫っていく。数字は出さない（2026-10-29 代表「ボビンっていう回転するものを使うアイデアは好きだけど、
## それと数字ってダサいな」）。速さは動きと形だけで伝える:
##   回る速さ   速いほど速く回り、三つ穴がぶれて残像になる
##   糸         遅いとたるんでゆったり波打ち、速いほど長く、ぴんと張って細かく震える。速いと切れはしが舞う
##   縫い目     糸の行き先で、下の端に縫い目がだだだっと縫われて後ろへ流れる（滑った長さの分だけ）
##   色         糸の色が、ソリのメインカラーから明るい色へ少しずつ変わる
## ご褒美（今日いちばん・節目の速さを超えた瞬間）: ボビンがぽんと跳ね、糸がぱっと広がり、縫い目に小さな結び目ができて流れていく。
## 案の見比べ（糸巻き・巻尺・フェルトのメーター）は design/hud/speedo-ideas.png。

const Icons := preload("res://hud_icons.gd")
const RideWind := preload("res://ride_wind.gd")
const TOP := 16.0            # 今日いちばんの印の目盛りの上限 (m/s)。米袋で蹴って届く上限（sled.gd の KICK_TOP）
const WOOD := Color(0.78, 0.60, 0.38)
const BRIGHT := Color(1.0, 0.72, 0.22)   # 速いときの糸の色（明るい山吹へ寄る。雪の白に埋もれない濃さ）
const STITCH_PX := 16.0      # 縫い目 1 m の長さ（1080 のときの px）。滑った長さだけ縫い目が流れる


## 盛り上がり（0〜2）: 風と同じく 2 m/s から出て 9 m/s で 1。その先（大のソリの下り・米袋の連打）も 15 m/s まで伸び続け、
## 連打の速さの差が、回り・糸・色の差になる
static func level_of(speed: float) -> float:
	return RideWind.level_of(speed) + clampf((speed - RideWind.SPEED_FULL) / 6.0, 0.0, 1.0)


## 速さで変わる糸の色
static func thread_color(base: Color, k: float) -> Color:
	return base.lerp(BRIGHT, clampf((k - 0.25) / 1.5, 0.0, 0.85))


## box（画面の px）の中に描く。k は盛り上がり（level_of）、spin は回した角度、dist は滑った長さ (m)、
## base はソリのメインカラー、best は今日いちばんの速さ、pop は跳ね（1→0）、knots は結び目を結んだときの dist、a は薄さ
static func draw(ci: CanvasItem, box: Rect2, speed: float, k: float, spin: float, dist: float, base: Color, best: float,
		pop: float, knots: Array, a: float) -> void:
	var u := box.size.y / 160.0
	var col := thread_color(base, k)
	var hop := sin(pop * PI)
	var r := 54.0 * u * (1.0 + 0.12 * hop)
	var c := Vector2(box.end.x - 70.0 * u, box.position.y + 66.0 * u - hop * 18.0 * u)
	# ---- 下の端の縫い目（糸の行き先）。滑った長さだけ左へ流れる
	var y_st := box.end.y - 12.0 * u
	var x_needle := c.x - r * 0.9
	var x_end := box.position.x + 6.0 * u
	var step := STITCH_PX * u
	var on := step * 0.62
	var off := fposmod(dist * STITCH_PX * u, step)
	var x := x_needle - off
	Icons.screen()
	while x - on > x_end:
		var f := clampf((x_needle - x) / (x_needle - x_end), 0.0, 1.0)
		Icons.thread(ci, PackedVector2Array([Vector2(x, y_st), Vector2(x - on, y_st)]), col, 3.0 * u, a * (1.0 - f * 0.6))
		x -= step
	# 結び目: 縫い目と一緒に流れていく
	for kd in knots:
		var kx: float = x_needle - (dist - float(kd)) * STITCH_PX * u
		if kx > x_end and kx < x_needle:
			var f := clampf((x_needle - kx) / (x_needle - x_end), 0.0, 1.0)
			ci.draw_circle(Vector2(kx, y_st) + Vector2(0.8, 1.2) * u, 7.0 * u, Color(Icons.SHADOW, 0.25 * a))
			ci.draw_circle(Vector2(kx, y_st), 7.0 * u, Color(col.darkened(0.15), a * (1.0 - f * 0.5)))
			ci.draw_arc(Vector2(kx, y_st), 4.2 * u, 0.3, 4.2, 10, Color(col.lightened(0.4), a * (1.0 - f * 0.5)), 1.2 * u, true)
	# ---- ボビンから針の所（縫い目の始まり）へ下りる糸: 遅いとたるみ、速いとぴんと張って細かく震える
	var from := c + Vector2(-r * 0.55, r * 0.55)
	var to := Vector2(x_needle, y_st)
	var tense := clampf(k, 0.0, 1.0)
	var sag := (1.0 - tense) * 26.0 * u
	var line := PackedVector2Array()
	for i in 17:
		var f := i / 16.0
		var p := from.lerp(to, f)
		var env := sin(f * PI)
		p.y += env * sag
		p += Vector2(0, sin(f * (4.0 + 18.0 * tense) - spin * (0.6 + 2.0 * tense)) * env * (2.0 + 2.5 * tense) * u)
		line.append(p)
	Icons.thread(ci, line, col, (2.6 + 0.8 * tense) * u, a)
	# 縫い目の上を後ろへ流れる糸（速いほど長く、波が細かい）
	var tail := PackedVector2Array()
	var len := (x_needle - x_end) * clampf(0.25 + 0.75 * k, 0.25, 1.0)
	for i in 25:
		var f := i / 24.0
		tail.append(Vector2(x_needle - f * len, y_st - 10.0 * u - f * 6.0 * u + sin(f * (6.0 + 14.0 * k) - spin * 1.3) * (2.0 + 5.0 * f) * u))
	Icons.thread(ci, tail, col, 2.2 * u, a * (0.25 + 0.6 * minf(k, 1.0)))
	# 速いと、糸の切れはしが後ろへ舞う
	for i in int(6.0 * minf(k, 2.0)):
		var f := fposmod(spin * 0.05 + i * 0.137, 1.0)
		var p := Vector2(x_needle - f * len, y_st - 14.0 * u + sin(i * 2.3) * 12.0 * u - f * 10.0 * u)
		Icons.thread(ci, PackedVector2Array([p, p + Vector2(-11.0 * u, sin(i + spin) * 2.0 * u)]), col.lightened(0.2), 1.5 * u, a * (1.0 - f))
	# ご褒美: 糸がぱっと広がる（ボビンから放射状に短い糸）
	if pop > 0.0:
		for i in 12:
			var ang := TAU * i / 12.0 + 0.2
			var d := Vector2(cos(ang), sin(ang))
			var r0 := r + 6.0 * u + (1.0 - pop) * 22.0 * u
			Icons.thread(ci, PackedVector2Array([c + d * r0, c + d * (r0 + 14.0 * u * pop)]), col, 2.0 * u, a * pop)
	# ---- ボビン（正面から: 木の端の板、巻いた糸の縁、三つ穴が回る。速いと穴がぶれて残像になる）
	Icons.screen()
	Icons.patch(ci, Icons.circ(c, r, 32), WOOD, a, false)
	Icons.patch(ci, Icons.circ(c, r * 0.82, 28), col, a, false)
	for i in 3:   # 巻いた糸の筋
		ci.draw_arc(c, r * (0.66 + i * 0.05), 0, TAU, 28, Color(col.darkened(0.25), 0.5 * a), 1.2 * u, true)
	Icons.patch(ci, Icons.circ(c, r * 0.48, 24), WOOD.lightened(0.1), a, false)
	var blur := clampf(k, 0.0, 2.0) * 1.0                        # 残像が伸びる角度 (rad)
	var ghosts := 1 + int(blur * 6.0)
	for g in ghosts:
		var back := -spin + blur * g / maxf(ghosts - 1, 1)
		var ga := a * (1.0 if g == 0 else 0.45 * (1.0 - float(g) / ghosts))
		for i in 3:
			var ang := back + TAU * i / 3.0
			ci.draw_circle(c + Vector2(cos(ang), sin(ang)) * r * 0.28, r * 0.09, Color(0.32, 0.22, 0.14, ga))
	if blur > 0.2:   # 速いと、穴の通り道が輪のぶれになって見える
		ci.draw_arc(c, r * 0.28, 0, TAU, 32, Color(0.32, 0.22, 0.14, 0.18 * a * minf(blur, 1.0)), r * 0.16, true)
	ci.draw_circle(c, r * 0.07, Color(0.25, 0.17, 0.11, a))
	# 回る勢いの弧（速いほど長く、重なる）
	for j in int(1 + 2.5 * minf(k, 2.0)):
		var sweep := 0.5 + 1.2 * minf(k, 2.0) - j * 0.2
		var rr := r + (8.0 + j * 6.0) * u
		var st := -PI / 2.0 + j * 1.9
		ci.draw_arc(c, rr, st, st + sweep, 18, Color(Icons.THREAD, (0.55 - j * 0.12) * a), 2.0 * u, true)
	# 今日いちばんの印: ボビンのまわりの、その速さの角度に赤い待ち針（数字の代わりの目印）
	if best > 1.0:
		var ba := -PI / 2.0 + TAU * clampf(best / TOP, 0.0, 1.0)
		var bd := Vector2(cos(ba), sin(ba))
		var bp := c + bd * (r + 4.0 * u)
		Icons.thread(ci, PackedVector2Array([bp, bp + bd * 12.0 * u]), Color(0.7, 0.72, 0.76), 1.4 * u, a)
		ci.draw_circle(bp + bd * 13.0 * u, 3.6 * u, Color(Icons.RED, a))
