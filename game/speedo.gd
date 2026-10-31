extends RefCounted
## 乗って滑っているときの速さの表示（hud.gd が描く）。画面の左側の空いた所（左上の確かめ用の札と、左下の名札のあいだ）の縦の帯。
## 上に木の糸巻き（ボビン）があり、ほどけた糸が下へ、フェルトのリボンの上に縫い目になって縦に縫い進む
## （2026-10-29 代表「糸巻きと縫い目は、画面左側の空いているところに置いて、縦向きにしてほしい」）。
## 数字は出さない（代表「ボビンっていう回転するものを使うアイデアは好きだけど、それと数字ってダサいな」）。速さは動きと形だけで伝える:
##   回る速さ   速いほど速く回り、三つ穴がぶれて残像になる。まわりの勢いの弧が長く、重なる
##   糸         遅いとたるんでゆったり揺れ、速いほどぴんと張って細かく震える。速いと切れはしが舞う
##   縫い目     リボンの上を下へ縫い進む（滑った長さの分だけ流れる）。速いほど太く・濃く・目が長く、10 m/s の先は 2 列
##   色         糸の色が、ソリのメインカラーから明るい山吹へ少しずつ変わる
## ご褒美（今日いちばん・節目の速さを超えた瞬間）: ボビンがぽんと跳ね、糸がぱっと広がり、縫い目に小さな結び目ができて流れていく。
## 滑った距離と速さのボタン（snow_buttons.gd）: 12 m 滑るごとに木のボタン、いちばん速い所を超えると真鍮のボタンが、
## 糸の上へぽんと縫い込まれ（sewn）、縫い目と一緒に下へ流れて、糸の下の端にたまっていく（数珠のように上へ積もる）。
## 止まると、縫い目の糸が下の端から巻き取られていき（reel）、ボビンが逆に回る。糸の上のボタンは、上から順に財布へ飛ぶ（craft_ui.gd）。
## 立体の板を使うとき（hud_plates.gd）は、ボビンは Blender の glb、リボンは厚みのある板で、縫い目はリボンの板に重ねる。
## 案の見比べ（糸巻き・巻尺・フェルトのメーター）は design/hud/speedo-ideas.png。

const Icons := preload("res://hud_icons.gd")
const RideWind := preload("res://ride_wind.gd")
const TOP := 16.0            # 今日いちばんの印の目盛りの上限 (m/s)。米袋で蹴って届く上限（sled.gd の KICK_TOP）
const WOOD := Color(0.78, 0.60, 0.38)
const BRIGHT := Color(1.0, 0.72, 0.22)   # 速いときの糸の色（明るい山吹へ寄る。雪の白に埋もれない濃さ）
const RIBBON := Color(0.95, 0.92, 0.85)  # 縫い目を縫うリボン（生成りのフェルト）
const STITCH_PX := 26.0      # 縫い目が流れる長さ（滑った 1 m あたり、1080 のときの px）


## 盛り上がり（0〜2）: 風と同じく 2 m/s から出て 9 m/s で 1。その先（大のソリの下り・米袋の連打）も 15 m/s まで伸び続け、
## 連打の速さの差が、回り・糸・縫い目・色の差になる
static func level_of(speed: float) -> float:
	return RideWind.level_of(speed) + clampf((speed - RideWind.SPEED_FULL) / 6.0, 0.0, 1.0)


## 速さで変わる糸の色
static func thread_color(base: Color, k: float) -> Color:
	return base.lerp(BRIGHT, clampf((k - 0.25) / 1.5, 0.0, 0.85))


## 縦の帯の中の置き場: ボビンの真ん中 c と半径 r、縫い目の列の x、縫い始め y0 と縫い終わり y1、リボンの場所。pop で跳ねる
static func layout(box: Rect2, pop: float) -> Dictionary:
	var u := box.size.x / 110.0
	var hop := sin(pop * PI)
	var r := 44.0 * u * (1.0 + 0.12 * hop)
	var c := Vector2(box.position.x + box.size.x / 2.0, box.position.y + 50.0 * u - hop * 14.0 * u)
	var y0 := box.position.y + 50.0 * u + 44.0 * u + 22.0 * u
	var y1 := box.end.y - 6.0 * u
	return {"u": u, "c": c, "r": r, "x": c.x, "y0": y0, "y1": y1,
		"ribbon": Rect2(c.x - 21.0 * u, y0 - 10.0 * u, 42.0 * u, maxf(y1 - y0 + 16.0 * u, 20.0 * u))}


## ボビンのまわり（糸・弧・待ち針・ご褒美の広がり）。spool が true なら、ボビンの本体も平らに描く
static func draw_spool(ci: CanvasItem, g: Dictionary, k: float, spin: float, base: Color, best: float, pop: float, a: float, spool := true) -> void:
	var u: float = g.u
	var c: Vector2 = g.c
	var r: float = g.r
	var col := thread_color(base, k)
	Icons.screen()
	# ボビンから針の所（縫い始め）へ下りる糸: 遅いとたるみ、速いとぴんと張って細かく震える
	var from := c + Vector2(-r * 0.62, r * 0.55)
	var to := Vector2(g.x, g.y0)
	var tense := clampf(k, 0.0, 1.0)
	var line := PackedVector2Array()
	for i in 13:
		var f := i / 12.0
		var p := from.lerp(to, f)
		var env := sin(f * PI)
		p.x -= env * (1.0 - tense) * 16.0 * u
		p.x += sin(f * (4.0 + 16.0 * tense) - spin * (0.6 + 2.0 * tense)) * env * (1.5 + 2.0 * tense) * u
		line.append(p)
	Icons.thread(ci, line, col, (2.4 + 0.8 * tense) * u, a)
	# ご褒美: 糸がぱっと広がる（ボビンから放射状に短い糸）
	if pop > 0.0:
		for i in 12:
			var ang := TAU * i / 12.0 + 0.2
			var d := Vector2(cos(ang), sin(ang))
			var r0 := r + 6.0 * u + (1.0 - pop) * 22.0 * u
			Icons.thread(ci, PackedVector2Array([c + d * r0, c + d * (r0 + 14.0 * u * pop)]), col, 2.0 * u, a * pop)
	if spool:
		_spool(ci, c, r, col, k, spin, a)
	# 回る勢いの弧（速いほど長く、重なる）
	for j in int(1 + 2.5 * minf(k, 2.0)):
		var sweep := 0.5 + 1.2 * minf(k, 2.0) - j * 0.2
		var rr := r + (8.0 + j * 6.0) * u
		var st := -PI * 0.75 + j * 1.9
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


const SEWN_R := 8.0   # 糸の上のボタンの半径（1080 のときの px）


## 糸の上のボタンの、画面の場所（sewn の並びと同じ順。外れたものも、外れる前の場所）。縫い込んだときから下へ流れ、
## 下の端（巻き取り中はその上がっていく端）に着いたら、古いものから下に積もる。積もる数が多くて糸の長さに収まらないときは、
## 間を詰めて、いつでも糸の上に収める（両替で 10 個ずつ上の素材になるので、ふつうは詰めなくても収まる。hud.gd の _exchange）。
## 両替で縫い縮まっているボタン（mk 0〜1）は、行き先（into）へ寄っていく
static func sewn_positions(g: Dictionary, dist: float, sewn: Array, reel := 0.0) -> Array:
	var u: float = g.u
	var y0: float = g.y0
	var y1: float = g.y1
	if reel > 0.0:
		y1 = lerpf(y1, y0, ease(reel, 0.6))
	var r := SEWN_R * u
	var flow := []
	for e in sewn:
		flow.append(maxf(y0 + (dist - float(e.d)) * STITCH_PX * u, y0))
	# 何個が下の端に積もるか（ふつうの間で数える）。収まらなければ間を詰める
	var step := r * 1.15
	var limit := y1 - r
	var n := 0
	for i in sewn.size():
		if not sewn[i].get("off", false) and float(flow[i]) >= limit:
			n += 1
			limit -= step
	if n > 1:
		step = minf(step, maxf(y1 - y0 - 2.0 * r, r) / (n - 1))
	limit = y1 - r
	var out := []
	for i in sewn.size():
		var y: float = flow[i]
		if not sewn[i].get("off", false):
			if y >= limit:
				y = limit
				limit = maxf(limit - step, y0)
		else:
			y = minf(y, limit)
		out.append(Vector2(g.x, y))
	for i in sewn.size():   # 両替: 行き先へ、くるくる寄っていく
		var mk: float = sewn[i].get("mk", -1.0)
		var into: int = sewn[i].get("into", -1)
		if mk >= 0.0 and into >= 0 and into < out.size():
			var e := ease(mk, 0.5)
			var swirl := Vector2(cos(mk * TAU * 1.5 + i), sin(mk * TAU * 1.5 + i)) * r * 1.4 * sin(mk * PI)
			out[i] = (out[i] as Vector2).lerp(out[into], e) + swirl
	return out


## リボンと、その上を下へ縫い進む縫い目・結び目・流れる糸・舞う切れはし。ribbon が true ならリボンの地も描く（平らなとき）
static func draw_stitches(ci: CanvasItem, g: Dictionary, k: float, spin: float, dist: float, base: Color, knots: Array, a: float, ribbon := true,
		sewn := [], reel := 0.0, lint := 0.0) -> void:
	var u: float = g.u
	var x: float = g.x
	var y0: float = g.y0
	var y1: float = g.y1
	var y1_full := y1
	if reel > 0.0:   # 巻き取り: 縫い目の下の端が、上（ボビン）へ上がっていく
		y1 = lerpf(y1, y0, ease(reel, 0.6))
	var col := thread_color(base, k)
	Icons.screen()
	if ribbon:
		var rb: Rect2 = g.ribbon
		Icons.patch(ci, Icons.rr(rb.position.x, rb.position.y, rb.size.x, rb.size.y, 8.0 * u), RIBBON, a, true, Icons.PAPER_EDGE)
	var s := clampf(k, 0.0, 1.6)
	var step := (16.0 + 14.0 * minf(s, 1.5)) * u          # 速いほど目が長い
	var on := step * (0.5 + 0.2 * minf(s, 1.0))
	var w := (2.4 + 3.0 * minf(s, 1.6)) * u                 # 速いほど太い
	var al := a * (0.45 + 0.55 * minf(s, 1.0))              # 速いほど濃い
	var flow := fposmod(dist * STITCH_PX * u, step)         # 下へ縫い流れる
	var cols := [0.0] if k < 1.05 else [-6.0 * u, 6.0 * u]  # 10 m/s の先は 2 列
	for dx: float in cols:
		var y := y0 - step + flow
		while y < y1:
			var a0 := maxf(y, y0)
			var a1 := minf(y + on, y1)
			if a1 > a0:
				var f := (a0 - y0) / maxf(y1 - y0, 1.0)
				var fade := 1.0 - smoothstep(0.8, 1.0, f)   # 下の端はふわっと
				Icons.thread(ci, PackedVector2Array([Vector2(x + dx, a0), Vector2(x + dx, a1)]), col, w, al * fade)
			y += step
	# 結び目: 縫い目と一緒に下へ流れていく
	for kd in knots:
		var ky: float = y0 + (dist - float(kd)) * STITCH_PX * u
		if ky > y0 and ky < y1:
			var f := (ky - y0) / maxf(y1 - y0, 1.0)
			ci.draw_circle(Vector2(x, ky) + Vector2(0.8, 1.2) * u, 6.0 * u, Color(Icons.SHADOW, 0.25 * a))
			ci.draw_circle(Vector2(x, ky), 6.0 * u, Color(col.darkened(0.15), a * (1.0 - f * 0.5)))
			ci.draw_arc(Vector2(x, ky), 3.6 * u, 0.3, 4.2, 10, Color(col.lightened(0.4), a * (1.0 - f * 0.5)), 1.2 * u, true)
	# 縫い込まれたボタン: 縫い目と一緒に下へ流れ、下の端にたまる（巻き取りでは、下の端に追われて上へ）。
	# 縫い込んだばかりは、ぽんとふくらむ
	# 両替: 10 個がくるくる縫い縮まって小さくなり、行き先に上の素材がぽんと出て、きらっと光る
	var ps := sewn_positions(g, dist, sewn, reel)
	var CI := preload("res://craft_icons.gd")
	for i in sewn.size():
		var e: Dictionary = sewn[i]
		if e.get("off", false):
			continue
		var age := (dist - float(e.d)) * STITCH_PX * u / (14.0 * u)   # 縫い込んでから流れた長さ（ボタン 1 つ半ほどで 1）
		var pop := 1.0 + 0.6 * sin(clampf(age, 0.0, 1.0) * PI) if age < 1.0 else 1.0
		var mk: float = e.get("mk", -1.0)
		if mk >= 0.0:
			pop *= 1.0 - 0.75 * mk
		var pk: float = e.get("pk", 1.0)
		if pk < 1.0:
			pop *= 1.0 + 0.7 * sin(pk * PI)
		Icons._o = ps[i]
		Icons._s = 1.0
		CI.money(ci, Vector2.ZERO, SEWN_R * u * pop, String(e.look), a * (1.0 - 0.4 * maxf(mk, 0.0)), spin * 0.2 + i)
		if pk < 1.0:
			CI._glint(ci, ps[i] + Vector2(SEWN_R, -SEWN_R) * u * 0.6, SEWN_R * u * 1.6 * (1.0 - pk * 0.6), Color(1.0, 0.95, 0.75, a * (1.0 - pk)))
	# 糸くず: 木 1 個に満たない端数（乗り物の倍率）。積もったボタンのいちばん上に、ほつれた糸の玉。たまるほど大きく
	if lint > 0.02:
		var top := y1 - SEWN_R * u
		for i in sewn.size():
			if not sewn[i].get("off", false):
				top = minf(top, (ps[i] as Vector2).y - SEWN_R * u * 1.3)
		top = maxf(top, y0 + SEWN_R * u)
		var lr := SEWN_R * u * (0.35 + 0.65 * clampf(lint, 0.0, 1.0))
		var lc := col.lightened(0.25)
		for j in 7:
			var a0 := j * 0.9 + spin * 0.05
			var arc := PackedVector2Array()
			for q in 6:
				var t := a0 + q * 0.5
				var rr := lr * (0.45 + 0.55 * sin(j * 1.7 + q * 0.8) * 0.5 + 0.3)
				arc.append(Vector2(x, top) + Vector2(cos(t), sin(t)) * rr)
			Icons.thread(ci, arc, lc, 1.3 * u, a * 0.9)
	# 縫い目の横を下へ流れる糸（速いほど長く、波が細かい）
	var len := (y1 - y0) * clampf(0.2 + 0.8 * k, 0.2, 1.0)
	var tail := PackedVector2Array()
	for i in 21:
		var f := i / 20.0
		tail.append(Vector2(x + 11.0 * u + sin(f * (6.0 + 14.0 * k) - spin * 1.3) * (1.5 + 3.5 * f) * u, y0 + f * len))
	Icons.thread(ci, tail, col, 2.0 * u, a * (0.2 + 0.55 * minf(k, 1.0)))
	# 速いと、糸の切れはしが下へ舞う
	for i in int(6.0 * minf(k, 2.0)):
		var f := fposmod(spin * 0.05 + i * 0.137, 1.0)
		var p := Vector2(x + sin(i * 2.3) * 14.0 * u, y0 + f * len)
		Icons.thread(ci, PackedVector2Array([p, p + Vector2(sin(i + spin) * 2.0 * u, 11.0 * u)]), col.lightened(0.2), 1.5 * u, a * (1.0 - f))


## コンボの結び目（2026-10-31 代表「コンボしていることを、なにかで表示」）: リボンの左の縁を上から下へ、段の数だけ玉結び（フレンチノット）が
## 縦の糸でつながって並ぶ。結んだばかりはぽんとふくらみ、きらっと光る。段が上がるほど結び目の色が明るい山吹へ寄る。
## ほどけ始めたら（off）、一つずつ少しずつずれて、結び目がゆるんで輪になり、広がりながら下へふわっと落ちて消える。数字は出さない
const COMBO_SHOW := 8         # 並べて見せる結び目の数（それより上は、いちばん下の結び目が大きく光る）
static func draw_combo(ci: CanvasItem, g: Dictionary, knots: Array, now: float, untie_t: float, base: Color, a: float) -> void:
	if knots.is_empty():
		return
	var u: float = g.u
	var rb: Rect2 = g.ribbon
	var x := rb.position.x + 7.5 * u
	var y := float(g.y0) + 3.0 * u
	var gap := 15.0 * u
	var n := knots.size()
	var CI := preload("res://craft_icons.gd")
	Icons.screen()
	# つなぐ糸（ほどけていない結び目のあいだ）
	var tied := 0
	for e in knots:
		if float(e.off) < 0.0:
			tied += 1
	if tied > 1:
		Icons.thread(ci, PackedVector2Array([Vector2(x, y), Vector2(x, y + gap * (mini(tied, COMBO_SHOW) - 1))]), base.darkened(0.1), 1.6 * u, a * 0.8)
	for i in n:
		var e: Dictionary = knots[i]
		var slot := mini(i, COMBO_SHOW - 1)
		var p := Vector2(x, y + gap * slot)
		var col := base.lerp(BRIGHT, minf(0.3 + 0.1 * i, 0.9)).lightened(0.1)
		var off: float = e.off
		if off >= 0.0:
			var q := clampf((now - off - 0.05 * (n - 1 - i)) / untie_t, 0.0, 1.0)
			if q >= 1.0:
				continue
			# ほどける: ゆるんで輪になり、広がりながら下へ落ちて消える
			var lr := 5.0 * u * (1.0 + 1.6 * q)
			var c := p + Vector2(sin(i * 1.7) * 3.0 * u * q, 10.0 * u * q * q)
			var arc := PackedVector2Array()
			for k in 13:
				var t := 0.4 + k * (TAU - 0.9) / 12.0 + q * 2.0
				arc.append(c + Vector2(cos(t), sin(t) * 0.8) * lr)
			Icons.thread(ci, arc, col, 1.5 * u, a * (1.0 - q))
			continue
		var age := now - float(e.t)
		var pop := 1.0 + 0.7 * sin(clampf(age / 0.35, 0.0, 1.0) * PI)
		var r := 5.6 * u * pop * (1.25 if i >= COMBO_SHOW else 1.0)
		ci.draw_circle(p + Vector2(0.8, 1.2) * u, r * 1.1, Color(Icons.SHADOW, 0.3 * a))
		ci.draw_circle(p, r * 1.12, Color(col.darkened(0.55), a))   # 縁取り（リボンの生成りと縫い目に埋もれないように）
		ci.draw_circle(p, r, Color(col.darkened(0.08), a))
		for k in 3:   # 巻いた糸の筋
			ci.draw_arc(p, r * (0.75 - k * 0.22), 0.4 + k * 1.3, 3.6 + k * 1.3, 8, Color(col.lightened(0.35), a), 1.1 * u, true)
		if age < 0.6:
			CI._glint(ci, p + Vector2(r * 0.9, -r * 0.9), 9.0 * u * (1.0 - age / 0.6 * 0.6), Color(1.0, 0.95, 0.75, a * (1.0 - age / 0.6)))


## 平らなボビン（木の端の板、巻いた糸の縁、三つ穴。速いと穴がぶれて残像になる）
static func _spool(ci: CanvasItem, c: Vector2, r: float, col: Color, k: float, spin: float, a: float) -> void:
	var u := r / 44.0
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
