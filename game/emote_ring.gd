extends Control

const Palm := preload("res://palm.gd")
## 身ぶりの輪。Tab を押しているあいだ画面のまんなかに出て、マウスを動かした向きのものを選び、離すと出す。
## 挨拶のボタンではなく、手と声の材料。7 つ: 上が高い手のひら、右回りにおーーーい（遠くへ呼ぶ）・ウン・ンーン・低い手のひら・
## 首をかしげてウン？・指さし。手の 3 つは、いま選んでいる手（右・左・両手。Q と X で替える）で出す。
## 文字は出さない。紙の丸に、ゲームの手と同じ紙の手形（アップリケ）と、墨の線の絵。いま掲げている手には赤い縁。
## まんなかに、いまの手（右・左・両手）を小さな手袋で描く。

const SLOTS := ["high", "oi", "un", "nn", "low", "huh", "point"]
const NONE := "?"            # 何も選ばずに離した
const RING_R := 112.0
const DISC_R := 38.0
const PICK := 26.0           # これだけマウスを動かすと選ぶ (px)
const PAPER := Color(0.96, 0.93, 0.86)
const SKIN := Color(0.94, 0.82, 0.65)
const EDGE := Color(0.55, 0.42, 0.32)
const INK := Color(0.16, 0.12, 0.10)
const PICKED := Color(0.78, 0.3, 0.24)

var hand := "R"              # いまの手（"R" "L" "both"）
var held := ""               # いま掲げている高さ（"high" "low" ""）
var pointing := false
var _aim := Vector2.ZERO
var _sel := -1
var _icons := {}             # 形_側 → 画面の多角形（1 m を 1 px で、y は下向き）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	for sh in Palm.SHAPES:
		for side in [1, -1]:
			var pts := PackedVector2Array()
			for p in Palm.outline(sh, side):
				pts.append(Vector2(p.x, -p.y + 0.01))   # 画面は y が下向き。手の中ほどを丸の中心へ
			_icons["%s_%d" % [sh, side]] = pts


func open(hand_now: String, held_now: String, pointing_now: bool) -> void:
	hand = hand_now
	held = held_now
	pointing = pointing_now
	_aim = Vector2.ZERO
	_sel = -1
	visible = true
	queue_redraw()


## 輪を出したまま手を替えた（Q・X）
func set_hand(h: String) -> void:
	hand = h
	queue_redraw()


## マウスの動き。向きで選ぶ（輪の中で止まる）
func move(rel: Vector2) -> void:
	_aim += rel
	if _aim.length() > RING_R:
		_aim = _aim.normalized() * RING_R
	var was := _sel
	if _aim.length() < PICK:
		_sel = -1
	else:
		# 上が 0、時計回り
		var a := fposmod(atan2(_aim.x, -_aim.y) + PI / SLOTS.size(), TAU)
		_sel = int(a / (TAU / SLOTS.size())) % SLOTS.size()
	if _sel != was:
		queue_redraw()


## 離した。選んだもの（SLOTS のどれか）。選んでいなければ NONE
func close() -> String:
	visible = false
	return SLOTS[_sel] if _sel >= 0 else NONE


func _draw() -> void:
	var c := get_viewport_rect().size * 0.5   # 輪は CanvasLayer の下にあるので、画面のまんなかを直接とる
	var k: float = preload("res://hud_icons.gd").ui_scale(get_viewport_rect().size.y)   # HUD とそろえた大きさ（まんなかを中心に）
	draw_set_transform(c * (1.0 - k), 0.0, Vector2(k, k))
	draw_circle(c, RING_R + DISC_R + 14.0, Color(0.1, 0.1, 0.14, 0.18))   # 下の淡い丸（世界が透けて見える）
	for i in SLOTS.size():
		var a := TAU * i / SLOTS.size()
		var p := c + Vector2(sin(a), -cos(a)) * RING_R
		var name_: String = SLOTS[i]
		var big := i == _sel
		var r := DISC_R * (1.18 if big else 1.0)
		draw_circle(p + Vector2(2, 3), r, Color(0, 0, 0, 0.18))   # 紙の影
		draw_circle(p, r, Color(PAPER, 0.96))
		var on := name_ == held or (name_ == "point" and pointing)
		draw_arc(p, r, 0, TAU, 28, PICKED if big or on else EDGE, 3.0 if big or on else 2.0, true)
		_icon(name_, p, r / DISC_R)
	_hands_now(c + _aim * 0.4)


## 紙の手形を一つ描く（墨の縁つき）。at は中心、px は 1 m の大きさ
func _hand(shape: String, side: int, at: Vector2, px: float, tilt := 0.0) -> void:
	var src: PackedVector2Array = _icons["%s_%d" % [shape, side]]
	var pts := PackedVector2Array()
	for q in src:
		pts.append(at + q.rotated(tilt) * px)
	draw_colored_polygon(pts, SKIN)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, INK, 2.0, true)


## いまの手で、その形を描く。自分から見た向き（右手は右、親指は内側。一人称で見える手の甲と同じ）
func _hands_icon(shape: String, c: Vector2, k: float, tilt: float, lift := Vector2.ZERO) -> void:
	if hand == "both":
		_hand(shape, -1, c + Vector2(12, 0) * k + lift, 170.0 * k, 0.12 + tilt)    # 右手（親指が左に来る輪郭）
		_hand(shape, 1, c + Vector2(-12, 0) * k + lift, 170.0 * k, -0.12 - tilt)   # 左手
	else:
		var side := 1 if hand == "L" else -1
		_hand(shape, side, c + lift, 240.0 * k, tilt * side)


func _line(a: Vector2, b: Vector2, w := 2.4) -> void:
	draw_line(a, b, INK, w, true)


func _icon(name_: String, c: Vector2, k: float) -> void:
	match name_:
		"high":
			# 高い手のひら: 上へ掲げる。わきに、上向きの小さな矢印
			_hands_icon("palm", c, k, 0.0, Vector2(0, -4) * k)
			_line(c + Vector2(-25, 20) * k, c + Vector2(-25, 6) * k)
			_line(c + Vector2(-25, 6) * k, c + Vector2(-29, 11) * k)
			_line(c + Vector2(-25, 6) * k, c + Vector2(-21, 11) * k)
		"low":
			# 低い手のひら: 指を前へ倒して、おさえる。下に、押さえる線
			_hands_icon("palm", c, k, PI * 0.5, Vector2(0, -5) * k)
			_line(c + Vector2(-20, 19) * k, c + Vector2(20, 19) * k)
			for x in [-12.0, 0.0, 12.0]:
				_line(c + Vector2(x, 11) * k, c + Vector2(x, 16) * k, 2.0)
		"point":
			_hands_icon("point", c, k, PI * 0.5)
		"un":
			# うなずく頭と、下へ回る矢印
			var h := c + Vector2(-5, -2) * k
			draw_arc(h, 12.0 * k, 0, TAU, 20, INK, 2.6, true)
			draw_arc(h, 20.0 * k, -0.9, 0.9, 12, INK, 2.4, true)
			var tip := h + Vector2(cos(0.9), sin(0.9)) * 20.0 * k
			_line(tip, tip + Vector2(-6, -1) * k)
			_line(tip, tip + Vector2(1, -7) * k)
		"nn":
			# 横に振る頭と、左右の矢印
			var h := c + Vector2(0, -7) * k
			draw_arc(h, 11.0 * k, 0, TAU, 20, INK, 2.6, true)
			var y := c.y + 14.0 * k
			_line(Vector2(c.x - 19 * k, y), Vector2(c.x + 19 * k, y))
			for s in [-1.0, 1.0]:
				var e := Vector2(c.x + s * 19 * k, y)
				_line(e, e + Vector2(-s * 5, -4) * k)
				_line(e, e + Vector2(-s * 5, 4) * k)
		"oi":
			# 呼ぶ: 横顔の口に手を当てて、声が遠くへ広がる弧
			var h := c + Vector2(-12, -2) * k
			draw_arc(h, 11.0 * k, 0, TAU, 20, INK, 2.6, true)
			_hand("palm", 1, h + Vector2(12, 4) * k, 120.0 * k, 0.9)
			for i in 3:
				var r := (9.0 + i * 6.0) * k
				draw_arc(c + Vector2(8, 0) * k, r, -0.6, 0.6, 10, INK, 2.0, true)
		"huh":
			# かしげた頭（傾いた肩の線）と、問いかけの小さな巻き
			var h := c + Vector2(-4, 0) * k
			draw_arc(h, 12.0 * k, 0, TAU, 20, INK, 2.6, true)
			_line(h + Vector2(-11, 17).rotated(-0.35) * k, h + Vector2(11, 17).rotated(-0.35) * k)
			draw_arc(c + Vector2(16, -12) * k, 6.0 * k, PI * 1.1, PI * 2.4, 12, INK, 2.2, true)
			draw_circle(c + Vector2(17, 0) * k, 1.8 * k, INK)


## まんなかの小さな手袋: いまの手（右・左・両手）。選んでいる手を塗る
func _hands_now(at: Vector2) -> void:
	draw_circle(at, 19.0, Color(PAPER, 0.92))
	draw_arc(at, 19.0, 0, TAU, 20, Color(EDGE, 0.9), 1.5, true)
	for side in [1, -1]:
		var on: bool = hand == "both" or (hand == "R") == (side > 0)
		# 自分の手を、自分から見た向きで（右手は右）。親指は内側
		var p := at + Vector2(7.0 * side, 1.0)
		var pts := PackedVector2Array()
		for q in _icons["palm_%d" % -side]:
			pts.append(p + q * 100.0)
		if on:
			draw_colored_polygon(pts, SKIN)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, INK if on else Color(INK, 0.35), 1.4, true)
