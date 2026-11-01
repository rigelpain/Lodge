extends Node

const Icons := preload("res://hud_icons.gd")
## 体の調子のバッジ（効き目の印）の配り役と、その絵。下がっている調子は「下降バッジ」、上がっている調子は「上昇バッジ」。
## 文字は使わず、何が変わったか（押す力は押す手袋、速さは速さの線を引く靴）をフェルトのまるいワッペンに刺繍し、
## その下に糸の矢印を縫う（上がるは上向きの赤、下がるは下向きの藍。強いときは 2 本）。
## 2026-11-01 代表「手で押すマークのワッペンと、靴にスピードを感じるエフェクトを付けたマークのワッペン。その下に上下矢印でバフデバフ」
## 入れるのは効き目を決める仕組み（湿り気の damp.gd。あとでご飯の効き目なども同じ put で入れる）。
## 描くのは hud.gd（自分のバッジ）。中身は数・文字だけなので、そのまま通信に乗せられる。
##
## put(人の番号, 名前, 向き, 段, 絵) の名前は仕組みごとに 1 つ（"damp" など）。同じ名前は上書き。
## 絵（"push" 押す力・"speed" 速さ など）は draw_icon に足す。"" なら名前を絵の名前にする

signal changed(id: int)

const DOWN := Color(0.24, 0.32, 0.55)      # 下降のワッペン（藍のフェルト）
const UP := Color(0.90, 0.68, 0.22)        # 上昇のワッペン（山吹のフェルト）
const DOWN_THREAD := Color(0.95, 0.95, 1.0)
const UP_THREAD := Color(0.80, 0.24, 0.20)
const ARROW_UP := Color(0.85, 0.26, 0.18)   # 上がる矢印（赤い糸）
const ARROW_DOWN := Color(0.22, 0.34, 0.62) # 下がる矢印（藍の糸）
const ARROW_STRETCH := 0.1     # 上がる矢印の伸び縮み（長さの割合の振れ。控えめに）
const ARROW_PULSE := 0.45      # その速さ（1 秒に何回。ゆっくり）

var _by := {}                  # 番号 → {名前 → {key, dir, level, icon}}


func put(id: int, key: String, dir: int, level: int, icon := "") -> void:
	var m: Dictionary = _by.get(id, {})
	var old: Dictionary = m.get(key, {})
	if old.get("dir") == dir and old.get("level") == level and old.get("icon") == icon:
		return
	m[key] = {"key": key, "dir": dir, "level": level, "icon": icon}
	_by[id] = m
	changed.emit(id)


func clear(id: int, key: String) -> void:
	var m: Dictionary = _by.get(id, {})
	if m.has(key):
		m.erase(key)
		changed.emit(id)


## その人のバッジ（下降が先、そのあと上昇。同じ向きは名前の順）
func of(id: int) -> Array:
	var out: Array = _by.get(id, {}).values()
	out.sort_custom(func(a, b): return a.key < b.key if a.dir == b.dir else a.dir < b.dir)
	return out


# ---- 絵 ----------------------------------------------------------------------------------

## バッジ 1 枚を、画面の center（ワッペンの真ん中）に、直径 size px で描く。矢印はワッペンの下に。pop は出たときの跳ね（1→0）
static func draw_badge(ci: CanvasItem, b: Dictionary, center: Vector2, size: float, a := 1.0, pop := 0.0) -> void:
	var s := size * (1.0 + 0.25 * sin(pop * PI) * pop)
	Icons._o = center
	Icons._s = s / 64.0
	var up: bool = b.dir > 0
	Icons.patch(ci, Icons.circ(Vector2.ZERO, 30.0, 28), UP if up else DOWN, a, true, (UP_THREAD if up else DOWN_THREAD).darkened(0.1))
	var icon: String = b.get("icon", "")
	draw_icon(ci, icon if icon != "" else b.key, a)
	# 矢印をワッペンに重ねる。上がるはワッペンの右上で、根もとを留めたまま 12 コマで伸び縮みして上へ伸びる。
	# 下がるはワッペンの右下に重ねる。強いときは 2 本（2026-11-01 代表「上昇矢印はワッペンの右上重なる場所に配置して
	# 伸び縮みして上がってることをわからせて。下降矢印はワッペン右下に重ならせて」）
	var n: int = clampi(b.level, 1, 2)
	var t := floorf(Time.get_ticks_msec() / 1000.0 * 12.0) / 12.0   # 人形と同じコマ撮り
	var stretch := 1.0 + ARROW_STRETCH * sin(t * TAU * ARROW_PULSE)
	for i in n:
		var x := 27.0 - (n - 1 - i) * 8.0
		if up:
			_arrow(ci, Vector2(x, -10), Vector2(x, -10 - 18.0 * stretch), ARROW_UP, a)
		else:
			_arrow(ci, Vector2(x, 20), Vector2(x, 38), ARROW_DOWN, a)


## 糸の矢印（太い糸の軸と、フェルトの矢じり）。ワッペンに重ねても読めるよう、生成りの縁取りをしてから縫う
static func _arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, a: float) -> void:
	var d := (to - from).normalized()
	var nrm := Vector2(-d.y, d.x)
	var head := PackedVector2Array([to + d * 1.0, to - d * 6.5 + nrm * 5.0, to - d * 6.5 - nrm * 5.0])
	var rim := Icons._map(PackedVector2Array([from - d * 1.2, to - d * 5.0]))
	ci.draw_polyline(rim, Color(Icons.PAPER, a), 5.8 * Icons._s, true)
	var head_rim := Geometry2D.offset_polygon(head, 1.4, Geometry2D.JOIN_ROUND)
	if head_rim.size() > 0:
		ci.draw_colored_polygon(Icons._map(head_rim[0]), Color(Icons.PAPER, a))
	Icons.thread(ci, PackedVector2Array([from, to - d * 5.0]), col, 3.0, a)
	Icons.patch(ci, head, col, a, false)


## バッジの中の絵（いまの _o・_s の箱。半径 20 ほどに収める）
static func draw_icon(ci: CanvasItem, name: String, a := 1.0) -> void:
	match name:
		"push":
			_push(ci, a)
		"speed":
			_speed(ci, a)
		_:
			Icons.icon(ci, name, Icons._o, Icons._s * 40.0, a)


## 押す力: 腕を曲げて力こぶを見せる（2026-11-01 代表「押す力は力こぶのワッペンにしてほしい」）。生成りのフェルトの腕を、
## 縁を縫ったアップリケにする。肩に赤い半袖、ひじから上へ曲げた前腕の先に握りこぶし。力こぶの上に力の線を白い糸で
static func _push(ci: CanvasItem, a: float) -> void:
	var skin := Icons.PAPER
	# 上腕（肩から右のひじまで。上の縁がもり上がって力こぶ）と、ひじから上へ立てた前腕を 1 枚のフェルトで
	var arm := PackedVector2Array([Vector2(-21, 5), Vector2(-18, 0), Vector2(-15, -6), Vector2(-10, -10), Vector2(-4, -10),
			Vector2(0, -6), Vector2(2, -2), Vector2(4, -11), Vector2(15, -11), Vector2(16, 3), Vector2(13, 11), Vector2(6, 15), Vector2(-21, 15)])
	Icons.patch(ci, arm, skin, a, true)
	Icons.patch(ci, Icons.rr(1, -25, 17, 15, 6), skin, a, true)                          # 握りこぶし
	Icons.thread(ci, PackedVector2Array([Vector2(5, -17), Vector2(14, -17)]), skin.darkened(0.35), 1.2, 0.9 * a)   # 指の折り目
	Icons.thread(ci, PackedVector2Array([Vector2(-14, 1), Vector2(-9, -3), Vector2(-3, -2), Vector2(0, 2)]), skin.darkened(0.3), 1.2, 0.8 * a)   # 力こぶのふくらみ
	Icons.patch(ci, Icons.rr(-26, 1, 9, 16, 3), Icons.RED, a, true)                      # 肩の半袖
	for k in 3:   # 力の線
		var t := -2.4 + k * 0.45
		var d := Vector2(cos(t), sin(t))
		Icons.thread(ci, PackedVector2Array([Vector2(-8, -6) + d * 8.0, Vector2(-8, -6) + d * 13.0]), Color(1, 1, 1), 1.8, 0.95 * a)


## 速さ: 赤いフェルトの靴が前へ駆け、かかとの後ろに速さの線と小さな雪けむり
static func _speed(ci: CanvasItem, a: float) -> void:
	for k in 3:
		var y := -7.0 + k * 6.0
		Icons.thread(ci, PackedVector2Array([Vector2(-25 + k * 3, y), Vector2(-12 + k * 2, y)]), Icons.PAPER, 1.8, 0.95 * a)
	Icons.patch(ci, Icons.circ(Vector2(-14, 12), 3.2, 10), Icons.SNOW, 0.9 * a, false)
	Icons.patch(ci, Icons.circ(Vector2(-19, 10), 2.4, 10), Icons.SNOW, 0.8 * a, false)
	var boot := PackedVector2Array([Vector2(-9, -15), Vector2(1, -15), Vector2(2, -3), Vector2(11, -1), Vector2(17, 3),
			Vector2(17, 8), Vector2(-10, 8), Vector2(-11, 0)])
	Icons.patch(ci, Icons.xf(boot, -0.12, Vector2(2, 2)), Icons.RED, a, true)
	Icons.patch(ci, Icons.xf(Icons.rr(-11, 7, 29, 4.5, 2), -0.12, Vector2(2, 2)), Icons.PAPER, a, false)   # 靴底
	Icons.patch(ci, Icons.xf(Icons.rr(-10, -16, 12, 4, 1.5), -0.12, Vector2(2, 2)), Icons.PAPER, a, false)  # はき口の折り返し
