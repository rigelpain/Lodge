extends RefCounted
## 名札の窓の上の段に描く標高の札。範囲ごとに布の地（色と柄）が替わる: 丘は若草に水玉、大斜面は山吹に斜めの縞、山は藍にジグザグ、
## ロッジのまわりは生成りの無地。同じ布の旗が、それぞれの山のそばに立っている（area_flags.gd）。
## 2026-11-04 代表「背景＋柄のやつがいいな。その色と柄のフラッグを各山の近くに立てとけば良いもんね」。

const Icons := preload("res://hud_icons.gd")
const Areas := preload("res://areas.gd")

const GRASS := Color(0.50, 0.64, 0.38)      # 丘の若草のフェルト
const AMBER := Icons.MUSTARD                # 大斜面の山吹のフェルト
const INDIGO := Color(0.27, 0.33, 0.56)     # 山の藍のフェルト
const COLORS := {"hill": GRASS, "slope": AMBER, "peak": INDIGO, "lodge": Color(0.90, 0.85, 0.75)}
## 札の中の旗とロッジの大きさ: 山が大きいほど小さくして、山の大きさを見せる（2026-11-04 代表「山の大きさがわかんない。フラッグそのぶん小さくするとかは」）。
## 本当の比（18 m と 140 m で 8 倍）だと見えないので、札で読める所まで。ソリの印は探す物なので、旗ほどは小さくしない
const PROP_K := {"hill": 1.0, "slope": 0.7, "peak": 0.5, "lodge": 1.25}
const SLED_K := {"hill": 1.0, "slope": 0.85, "peak": 0.72, "lodge": 1.0}


static func area_color(id: String) -> Color:
	return COLORS.get(id, Icons.PAPER_EDGE)


## 布の柄（rc の中に縫う。旗の布もこれで描く）: 丘は水玉、大斜面は斜めの縞、山はジグザグ。ロッジのまわりは無地
static func stitches(ci: CanvasItem, id: String, rc: Rect2, a: float, u: float) -> void:
	var ink := Color(Icons.SNOW, 0.82)
	match id:
		"hill":
			var row := 0
			var y := rc.position.y + 5.0 * u
			while y < rc.end.y:
				var x := rc.position.x + (5.0 if row % 2 == 0 else 11.0) * u
				while x < rc.end.x - 2.0 * u:
					ci.draw_circle(Vector2(x, y), 1.5 * u, Color(ink, ink.a * a))
					x += 12.0 * u
				y += 7.0 * u
				row += 1
		"slope":
			var inner := Icons.rr(rc.position.x + 1.0 * u, rc.position.y + 1.0 * u, rc.size.x - 2.0 * u, rc.size.y - 2.0 * u, 3.0 * u)
			var x := rc.position.x - rc.size.y * 1.6
			while x < rc.end.x:
				var p0 := Vector2(x, rc.position.y)
				var p1 := p0 + Vector2(rc.size.y * 1.6, rc.size.y)
				for s in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([p0, p1]), inner):
					Icons.dashes(ci, s, ink, 1.0 * u, 3.0 * u, 2.0 * u, a)
				x += 11.0 * u
		"peak":
			var y := rc.position.y + 7.0 * u
			while y < rc.end.y:
				var z := PackedVector2Array()
				var x := rc.position.x + 2.0 * u
				var up := true
				while x < rc.end.x - 2.0 * u:
					z.append(Vector2(x, y + (-2.5 if up else 2.5) * u))
					x += 5.0 * u
					up = not up
				Icons.dashes(ci, z, ink, 1.0 * u, 3.0 * u, 1.5 * u, a)
				y += 9.5 * u


## 上の段を描く。mark は断面の上のソリの位置（NAN なら印なし）。draw_mark は印を描く関数 (中心, 坂の傾き, 大きさの倍率)
static func draw(ci: CanvasItem, id: String, u: float, a: float, fw: float, height: Callable, mark: float, draw_mark: Callable) -> void:
	var f := Areas.info(id)
	var sec := Areas.section(id, height)
	var x0 := 6.0 * u
	var x1 := fw - 6.0 * u
	var yb := 40.0 * u
	var yt := 6.0 * u
	var yfull := lerpf(yb, yt, float(f.tall))
	var rmin: float = sec[0].x
	var rmax: float = sec[sec.size() - 1].x
	var to_x := func(r: float) -> float: return lerpf(x0, x1, (r - rmin) / (rmax - rmin))
	var to_y := func(l: float) -> float: return lerpf(yb, yfull, l) if float(f.tall) > 0.0 else yb - 5.0 * u
	var rc := Rect2(x0 - 3.0 * u, 2.0 * u, x1 - x0 + 6.0 * u, 41.5 * u)
	Icons.screen()
	Icons.patch(ci, Icons.rr(rc.position.x, rc.position.y, rc.size.x, rc.size.y, 4.0 * u), area_color(id), a, false)
	stitches(ci, id, rc, a, u)
	var prof := PackedVector2Array()
	for q in sec:
		prof.append(Vector2(to_x.call(q.x), to_y.call(q.y)))
	var mound := prof.duplicate()
	mound.append(Vector2(x1, yb + 3.0 * u))
	mound.append(Vector2(x0, yb + 3.0 * u))
	Icons.screen()
	Icons.patch(ci, mound, Icons.SNOW, a, false)
	Icons.thread(ci, prof, Icons.THREAD, 1.4 * u, a)
	var k: float = PROP_K.get(id, 1.0) * u
	if id == Areas.NONE:   # ロッジのまわり: 平らな高台の、ロッジの本当の位置に（ソリの印と同じ物差し）
		var lp: Vector2 = preload("res://main.gd").LODGE_POS
		_lodge(ci, Vector2(to_x.call(Areas.locate(id, lp)), to_y.call(0.0)), k, a)
	else:   # 頂上の旗と、ふもとのロッジ
		var top := Vector2(to_x.call(0.0), to_y.call(Areas.level(sec, 0.0)))
		Icons.thread(ci, PackedVector2Array([top, top - Vector2(0, 12) * k]), Icons.WOOD.darkened(0.2), maxf(1.4 * k, 0.9 * u), a)
		Icons.patch(ci, PackedVector2Array([top - Vector2(0, 12) * k, top + Vector2(8.5, -9.5) * k, top - Vector2(0, 7) * k]), Icons.RED, a, false)
		_lodge(ci, Vector2(x1 - 5.5 * k - 1.0 * u, yb), k, a)
	if is_nan(mark):
		return
	var climbed := PackedVector2Array()
	for i in 25:
		var r := lerpf(rmax, mark, i / 24.0)
		climbed.append(Vector2(to_x.call(r), to_y.call(Areas.level(sec, r)) - 1.0 * u))
	if id != Areas.NONE:   # 登った分の赤い糸。ロッジのまわりは登らない
		Icons.thread(ci, climbed, Icons.RED, 2.0 * u, a)
	var pt := Vector2(to_x.call(mark), to_y.call(Areas.level(sec, mark)))
	var d := (rmax - rmin) / 60.0
	var slope := atan2(to_y.call(Areas.level(sec, mark + d)) - to_y.call(Areas.level(sec, mark - d)), to_x.call(mark + d) - to_x.call(mark - d))
	var ks: float = SLED_K.get(id, 1.0)
	draw_mark.call(pt + Vector2(0, -5.0 * u * ks).rotated(slope), slope, ks)


static func _lodge(ci: CanvasItem, at: Vector2, k: float, a: float) -> void:
	Icons.patch(ci, PackedVector2Array([at + Vector2(-5.5, 0) * k, at + Vector2(5.5, 0) * k, at + Vector2(5.5, -6) * k,
		at + Vector2(0, -11) * k, at + Vector2(-5.5, -6) * k]), Icons.WOOD, a, false)
	ci.draw_rect(Rect2(at + Vector2(-1.7, -5) * k, Vector2(3.4, 3.0) * k), Color(1.0, 0.72, 0.30, a))
