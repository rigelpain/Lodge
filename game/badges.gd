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
const DROP := Color(0.66, 0.82, 0.95)
const FIRE_FELT := Color(0.93, 0.55, 0.24)  # ゲージの上端の炎のワッペン
const WATER_FELT := Color(0.30, 0.45, 0.72) # ゲージの下端の水のワッペン
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


## ゲージの端の小さなワッペン（"fire" 炎・"drop" 水）
static func end_patch(ci: CanvasItem, icon: String, center: Vector2, size: float, a := 1.0) -> void:
	Icons._o = center
	Icons._s = size / 64.0
	Icons.patch(ci, Icons.circ(Vector2.ZERO, 30.0, 24), FIRE_FELT if icon == "fire" else WATER_FELT, a, true, Color(1, 1, 1, 0.9))
	Icons._s = size / 64.0 * 1.25
	draw_icon(ci, icon, a)


## バッジの中の絵（いまの _o・_s の箱。半径 20 ほどに収める）
static func draw_icon(ci: CanvasItem, name: String, a := 1.0) -> void:
	match name:
		"push":
			_push(ci, a)
		"speed":
			_speed(ci, a)
		"drop":
			_drop(ci, Vector2(0, -2), 1.0, a)
		"fire":
			_fire(ci, a)
		"bowl":
			_bowl(ci, a)
		_:
			Icons.icon(ci, name, Icons._o, Icons._s * 40.0, a)


## 押す力: 袖から伸びた腕の、赤い手袋の手のひら（指を上に）で、木の板（ソリの縁）をぐっと押す。腕の上下に力の線
static func _push(ci: CanvasItem, a: float) -> void:
	Icons.patch(ci, Icons.rr(10, -19, 8, 38, 2.5), Icons.WOOD, a, false)
	Icons.thread(ci, PackedVector2Array([Vector2(14, -16), Vector2(14, 16)]), Icons.WOOD.lightened(0.3), 0.9, 0.7 * a)
	Icons.patch(ci, Icons.rr(-24, -1, 22, 11, 3), Icons.PAPER, a, true)                 # 袖（生成りのフェルト）
	Icons.patch(ci, Icons.xf(Icons.rr(-4, -2, 6, 13, 2), 0.0, Vector2.ZERO), Icons.RED.darkened(0.3), a, false)   # 袖口
	Icons.patch(ci, Icons.rr(0, -16, 10, 26, 5), Icons.RED, a, true)                    # 手のひら（指を上に、板に当てる）
	Icons.patch(ci, Icons.xf(Icons.ell(Vector2.ZERO, 2.6, 5.5, 12), -0.6, Vector2(-0.5, -3)), Icons.RED.darkened(0.1), a, false)   # 親指
	for y in [-11.0, 17.0]:
		Icons.thread(ci, PackedVector2Array([Vector2(-24, y), Vector2(-9, y)]), Icons.PAPER, 1.8, 0.95 * a)


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


## しずく: 水色のフェルトの涙形に、白い糸の照り
static func _drop(ci: CanvasItem, c: Vector2, k: float, a: float) -> void:
	var p := PackedVector2Array()
	p.append(c + Vector2(0, -17) * k)
	for i in 15:
		var t := deg_to_rad(-40.0 + 260.0 * i / 14.0)   # 右上から下を回って左上へ
		p.append(c + (Vector2(0, 4) + Vector2(cos(t), sin(t)) * 11.0) * k)
	Icons.patch(ci, p, DROP, a, false)
	var hl := PackedVector2Array()
	for i in 5:
		var t := deg_to_rad(200.0 + 50.0 * i / 4.0)
		hl.append(c + (Vector2(0, 4) + Vector2(cos(t), sin(t)) * 6.5) * k)
	Icons.thread(ci, hl, Color(1, 1, 1), 1.6, 0.9 * a)


## 炎（暖炉の火）: 赤いフェルトの炎に、山吹の芯
static func _fire(ci: CanvasItem, a: float) -> void:
	var outer := PackedVector2Array([Vector2(0, -18), Vector2(7, -8), Vector2(12, 1), Vector2(10, 10), Vector2(3, 14), Vector2(-5, 14),
			Vector2(-11, 9), Vector2(-12, 0), Vector2(-7, -6), Vector2(-5, 1), Vector2(-2, -8)])
	Icons.patch(ci, outer, Color(0.80, 0.22, 0.16), a, false)
	var inner := PackedVector2Array([Vector2(1, -5), Vector2(6, 3), Vector2(5, 10), Vector2(-1, 12), Vector2(-6, 9), Vector2(-5, 3), Vector2(-2, 4)])
	Icons.patch(ci, inner, Color(1.0, 0.82, 0.32), a, false)


## ご飯で乾いている: 藍のフェルトの椀に赤い縁、上に白い糸の湯気が 3 すじ（12 コマでゆらぐ）
static func _bowl(ci: CanvasItem, a: float) -> void:
	var t := floorf(Time.get_ticks_msec() / 1000.0 * 12.0) / 12.0   # 人形と同じコマ撮り
	for k in 3:
		var x := -8.0 + k * 8.0
		var sway := sin(t * TAU * 0.5 + k * 1.7) * 1.6
		var steam := PackedVector2Array()
		for i in 7:
			var y := -4.0 - i * 2.6
			steam.append(Vector2(x + sin(i * 0.9 + k) * 2.2 + sway * i / 6.0, y))
		Icons.thread(ci, steam, Color(1, 1, 1), 1.8, 0.95 * a)
	var bowl := PackedVector2Array()
	for i in 13:
		var u := PI * i / 12.0   # 左の縁から下を回って右の縁へ
		bowl.append(Vector2(-cos(u) * 17.0, 2.0 + sin(u) * 14.0))
	Icons.patch(ci, bowl, Icons.NAVY, a, true)
	Icons.patch(ci, Icons.rr(-18, -1, 36, 5, 2.5), Icons.RED, a, false)          # 椀の縁
	Icons.patch(ci, Icons.rr(-6, 15, 12, 3.5, 1.5), Icons.NAVY.darkened(0.25), a, false)   # 高台
