extends Control

const Palm := preload("res://palm.gd")
## 手の形の輪。Tab を押しているあいだ画面のまんなかに出て、マウスを動かした向きの形を選び、離すと手をその形にする。
## 挨拶のボタンではなく、手の材料。選んだ形は下ろすまで掲げたまま、腕は見ている向きへ上がる（意味は遊ぶ人が作る）。
## 文字は出さない。8 つの紙の丸に、ゲームの手と同じ紙の手形（アップリケ）を描く。いま掲げている形には赤い縁。
## 上が両手のひら、右回りに手のひら・サムズアップ・ピース、下が「下ろす」、左下がグー、左が両手グー、左上が両手サムズアップ。

const SLOTS := ["palms", "palm", "thumb", "peace", "", "fist", "fists", "thumbs"]
const NONE := "?"            # 何も選ばずに離した
const RING_R := 118.0
const DISC_R := 36.0
const PICK := 26.0           # これだけマウスを動かすと選ぶ (px)
const PAPER := Color(0.96, 0.93, 0.86)
const SKIN := Color(0.94, 0.82, 0.65)
const EDGE := Color(0.55, 0.42, 0.32)
const INK := Color(0.16, 0.12, 0.10)
const PICKED := Color(0.78, 0.3, 0.24)

var current := ""            # いま掲げている形（赤い縁）
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


func open(now: String) -> void:
	current = now
	_aim = Vector2.ZERO
	_sel = -1
	visible = true
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
		# 上が 0、時計回りに 8 つ
		var a := fposmod(atan2(_aim.x, -_aim.y) + PI / 8.0, TAU)
		_sel = int(a / (TAU / 8.0)) % 8
	if _sel != was:
		queue_redraw()


## 離した。選んだ手の形（"" は下ろす）。選んでいなければ NONE
func close() -> String:
	visible = false
	return SLOTS[_sel] if _sel >= 0 else NONE


func _draw() -> void:
	var c := get_viewport_rect().size * 0.5   # 輪は CanvasLayer の下にあるので、画面のまんなかを直接とる
	draw_circle(c, RING_R + DISC_R + 14.0, Color(0.1, 0.1, 0.14, 0.18))   # 下の淡い丸（世界が透けて見える）
	for i in 8:
		var a := TAU * i / 8.0
		var p := c + Vector2(sin(a), -cos(a)) * RING_R
		var name_: String = SLOTS[i]
		var big := i == _sel
		var r := DISC_R * (1.18 if big else 1.0)
		draw_circle(p + Vector2(2, 3), r, Color(0, 0, 0, 0.18))   # 紙の影
		draw_circle(p, r, Color(PAPER, 0.96))
		var held := name_ == current and name_ != ""
		draw_arc(p, r, 0, TAU, 28, PICKED if big or held else EDGE, 3.0 if big or held else 2.0, true)
		_icon(name_, p, r / DISC_R)
	# まんなかの点: いま向いている所
	draw_circle(c + _aim * 0.5, 5.0, Color(PAPER, 0.9))
	draw_arc(c + _aim * 0.5, 5.0, 0, TAU, 16, Color(EDGE, 0.9), 1.5, true)


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


func _icon(name_: String, c: Vector2, k: float) -> void:
	match name_:
		"":
			# 下ろす: 手のひらを下へ向けて、下向きの矢印
			_hand("palm", 1, c + Vector2(0, -6) * k, 150.0 * k, PI)
			var y := c.y + 14.0 * k
			draw_line(Vector2(c.x, y - 6 * k), Vector2(c.x, y + 10 * k), INK, 2.4, true)
			draw_line(Vector2(c.x, y + 10 * k), c + Vector2(-6, 18) * k + Vector2(0, 6 * k), INK, 2.4, true)
			draw_line(Vector2(c.x, y + 10 * k), c + Vector2(6, 18) * k + Vector2(0, 6 * k), INK, 2.4, true)
		"palms", "fists", "thumbs":
			var sh: String = {"palms": "palm", "fists": "fist", "thumbs": "thumb"}[name_]
			# 向かいの人から見た形（右手は向かって左、親指は内側）
			_hand(sh, 1, c + Vector2(-11, 0) * k, 175.0 * k, -0.12)
			_hand(sh, -1, c + Vector2(11, 0) * k, 175.0 * k, 0.12)
		_:
			_hand(name_, 1, c, 260.0 * k)
