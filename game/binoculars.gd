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
## 縦の画角。のぞいている間にホイール・二本指スクロール・つまむ操作で変えられる（2026-11-07 代表「倍率変えれるようにしてほしい」）
const FOV_HAND := 24.0          # 持ち歩く双眼鏡の始めの画角（ふだんの 75° から約 3.5 倍）
const FOV_HAND_RANGE := Vector2(16.0, 40.0)    # 持ち歩く双眼鏡の幅（約 5.5 倍〜約 2 倍）
const FOV_STAND := 10.0         # テラスの台の始めの画角（約 8.5 倍。観光地のものらしく強め）
const FOV_STAND_RANGE := Vector2(5.0, 24.0)    # テラスの台の幅（約 17 倍〜約 3.5 倍）
const WHEEL_STEP := 1.18        # ホイール 1 目盛りで画角を何倍にするか
const PAN_ZOOM := 0.12          # 二本指スクロールの効き。Godot は Mac のスクロール量の 0.03 倍で渡すので、約 430 pt の撫でで台の幅の端から端まで
const PINCH_ZOOM := 1.5         # つまむ・広げるの効き
const STAND_SECONDS := 60.0     # テラスの台が 1 回で開いている長さ（秒）

const FELT := Color(0.25, 0.50, 0.53)
const WOOD := Color(0.62, 0.42, 0.24)
const DARK := Color(0.14, 0.15, 0.18)


static func fov(kind: String) -> float:
	return FOV_STAND if kind == "stand" else FOV_HAND


## 変えられる幅（x が最も寄った画角、y が最も引いた画角）
static func fov_range(kind: String) -> Vector2:
	return FOV_STAND_RANGE if kind == "stand" else FOV_HAND_RANGE


## 画角の幅の中の位置（0 最も引いた … 1 最も寄った）。見た目の倍率に揃えるので対数で
static func zoom_of(kind: String, fov_deg: float) -> float:
	var r := fov_range(kind)
	return clampf(log(r.y / fov_deg) / log(r.y / r.x), 0.0, 1.0)


## 手に持つ形（-Z が景色の側、原点は筒の真ん中）。glb は +Z が景色の側なので裏返す
static func shape() -> Node3D:
	var holder := Node3D.new()
	var g := Props.make("res://props/binoculars/binoculars.glb")
	g.rotation.y = PI
	holder.add_child(g)
	return holder


## 持ち物・品物の絵（64 × 64 の箱。Icons._o・_s は呼ぶ側が決めてある）: フェルトの筒 2 本と、木のボタンの目
static func icon(ci: CanvasItem, a: float) -> void:
	_lenses(ci, Vector2(0, 2), 1.0, a)


static func _lenses(ci: CanvasItem, c: Vector2, sc: float, a: float) -> void:
	for s: float in [-1.0, 1.0]:
		var at := c + Vector2(13.0 * s, 0) * sc
		Icons.patch(ci, Icons.xf(Icons.rr(-11, -13, 22, 26, 8), 0.0, at, sc), FELT, a, false)
		ci.draw_circle(Icons._o + at * Icons._s, 9.5 * sc * Icons._s, Color(WOOD, a))
		ci.draw_arc(Icons._o + at * Icons._s, 6.8 * sc * Icons._s, 0, TAU, 18, Color(0.40, 0.25, 0.13, a), maxf(1.0, 1.0 * Icons._s), true)
		for p: Vector2 in [Vector2(-2.2, -2.2), Vector2(2.2, -2.2), Vector2(-2.2, 2.2), Vector2(2.2, 2.2)]:
			ci.draw_circle(Icons._o + (at + p * sc) * Icons._s, 1.0 * sc * Icons._s, Color(DARK, a))
	Icons.patch(ci, Icons.xf(Icons.rr(-4, -5, 8, 10, 2), 0.0, c, sc), FELT, a, false)


## 案内の絵（hud_icons.gd の icon から）。木のボタン 1 枚か雪玉 1 個を入れてのぞく。何もなければ赤い ×。字は使わない
##   which: "ball" 雪玉で / "button" 木のボタンで / "none" 入れる物がない / "hand" 手の双眼鏡をのぞく / "off" 双眼鏡を下ろす
static func hint(ci: CanvasItem, which: String, a: float) -> void:
	if which == "hand":
		_lenses(ci, Vector2(0, 0), 0.95, a)
		return
	_lenses(ci, Vector2(0, -13), 0.7, a)
	if which == "off":
		Icons.arrow(ci, Vector2(0, 5), Vector2(0, 27), Icons.RED, a, 3.2)
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
