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
## ボビンの真ん中と半径（画面の px）。跳ねると上がって少しふくらむ
static func spool_at(box: Rect2, pop: float) -> Array:
	var u := box.size.y / 160.0
	var hop := sin(pop * PI)
	return [Vector2(box.end.x - 70.0 * u, box.position.y + 66.0 * u - hop * 18.0 * u), 54.0 * u * (1.0 + 0.12 * hop)]


## spool が false なら、ボビンの本体は描かない（hud_plates.gd の立体のボビンを使うとき）
static func draw(ci: CanvasItem, box: Rect2, speed: float, k: float, spin: float, dist: float, base: Color, best: float,
		pop: float, knots: Array, a: float, spool := true) -> void:
	var u := box.size.y / 160.0
	var col := thread_color(base, k)
	var sa := spool_at(box, pop)
	var c: Vector2 = sa[0]
	var r: float = sa[1]
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
	if spool:
		_spool(ci, c, r, col, k, spin, a)
	# 回る勢いの弧（速いほど長く、重なる）
	for j in int(1 + 2.5 * minf(k, 2.0)):
		var sweep := 0.5 + 1.2 * minf(k, 2.0) - j * 0.2
		var rr := r + (8.0 + j * 6.0) * u
		var st := -PI / 2.0 + j * 1.9
		ci.draw_arc(c, rr, st, st + sweep, 18, Color(Icons.THREAD, (0.55 - j * 0.12) * a), 2.0 * u, true)
	if not spool and k > 0.2:   # 立体のボビンの上に、穴の通り道のぶれの輪だけ重ねる
		ci.draw_arc(c, r * 0.34, 0, TAU, 32, Color(0.32, 0.22, 0.14, 0.16 * a * minf(k, 1.0)), r * 0.16, true)
	# 今日いちばんの印: ボビンのまわりの、その速さの角度に赤い待ち針（数字の代わりの目印）
	if best > 1.0:
		var ba := -PI / 2.0 + TAU * clampf(best / TOP, 0.0, 1.0)
		var bd := Vector2(cos(ba), sin(ba))
		var bp := c + bd * (r + 4.0 * u)
		Icons.thread(ci, PackedVector2Array([bp, bp + bd * 12.0 * u]), Color(0.7, 0.72, 0.76), 1.4 * u, a)
		ci.draw_circle(bp + bd * 13.0 * u, 3.6 * u, Color(Icons.RED, a))


## 平らなボビン（木の端の板、巻いた糸の縁、三つ穴。速いと穴がぶれて残像になる）
static func _spool(ci: CanvasItem, c: Vector2, r: float, col: Color, k: float, spin: float, a: float) -> void:
	var u := r / 54.0
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


## 視界の左右の端の縫い目（速さの線）: 目の高さの少し下から、画面の下の角へ向かう 2 本の縫い目が、滑る速さで外へ縫い流れる。
## 景色が横を流れていく向きと同じなので、目の端でも速さを感じる。速いほど太く・濃く・目が長く、10 m/s の先は 2 本目が並ぶ。
## 景色の真ん中は空け、左下の名札・右上の 360° 映像・右下の小窓にはかからない所を通す
static func seams(ci: CanvasItem, vs: Vector2, u: float, k: float, dist: float, base: Color, a: float) -> void:
	if a <= 0.01 or k <= 0.02:
		return
	var col := thread_color(base, k)
	var lines := [
		[Vector2(0.20, 0.50), Vector2(0.025, 0.74)],   # 左: 目の高さの少し下 → 左下（名札の上）
		[Vector2(0.80, 0.50), Vector2(0.975, 0.72)],   # 右: → 右下（小窓の上）
	]
	var strength := clampf(k, 0.0, 2.0)
	var rows := 1 if k < 1.05 else 2
	for ln in lines:
		var p0: Vector2 = ln[0] * vs
		var p1: Vector2 = ln[1] * vs
		var d := (p1 - p0)
		var L := d.length()
		var dir := d / L
		var nrm := Vector2(-dir.y, dir.x) * (1.0 if p0.x < vs.x / 2.0 else -1.0)
		for row in rows:
			var off_n := nrm * row * 16.0 * u
			var step := (26.0 + 22.0 * minf(strength, 1.5)) * u          # 速いほど目が長い
			var on := step * (0.45 + 0.2 * minf(strength, 1.0))
			var w := (2.2 + 3.2 * minf(strength, 1.6)) * u                 # 速いほど太い
			var flow := fposmod(dist * 38.0 * u, step)                       # 外へ縫い流れる
			var s := -step + flow
			while s < L:
				var s0 := maxf(s, 0.0)
				var s1 := minf(s + on, L)
				if s1 > s0:
					var f := (s0 + s1) / 2.0 / L
					var fade := smoothstep(0.0, 0.25, f) * (1.0 - smoothstep(0.85, 1.0, f))   # 端はふわっと
					var al := a * fade * (0.25 + 0.65 * minf(strength, 1.0)) * (1.0 if row == 0 else 0.6)
					Icons.screen()
					Icons.thread(ci, PackedVector2Array([p0 + dir * s0 + off_n, p0 + dir * s1 + off_n]), col, w * (0.7 + 0.5 * f), al)
				s += step
