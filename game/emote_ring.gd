extends Control
## 身ぶりの輪。Tab を押しているあいだ画面のまんなかに出て、マウスを動かした向きの身ぶりを選び、離すと出す。
## 文字は出さない。8 つの紙の丸に、墨の線で身ぶりの絵を描く。いまできない身ぶりは薄くする。
## 並びは歩いているときも乗っているときも同じ場所（手が覚える）。上は「手を上げる」（乗っていると万歳）、
## 右の 3 つが声、下がしゃがむ雪玉、左下がおじぎ、左が拍手、左上が深呼吸。

signal chosen(kind: String)

const SLOTS_WALK := ["hand_up", "wa", "un", "nn", "make_ball", "bow", "clap", "breath"]
const SLOTS_RIDE := ["banzai", "wa", "un", "nn", "make_ball", "bow", "clap", "breath"]
const RING_R := 118.0
const DISC_R := 34.0
const PICK := 26.0           # これだけマウスを動かすと選ぶ (px)
const PAPER := Color(0.96, 0.93, 0.86)
const EDGE := Color(0.55, 0.42, 0.32)
const INK := Color(0.16, 0.12, 0.10)
const PICKED := Color(0.78, 0.3, 0.24)

var slots: Array = SLOTS_WALK
var can := {}                # 身ぶり → いまできるか
var _aim := Vector2.ZERO
var _sel := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(riding: bool, available: Dictionary) -> void:
	slots = SLOTS_RIDE if riding else SLOTS_WALK
	can = available
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


## 離した。選んだ身ぶり（できないものや、選んでいなければ空）
func close() -> String:
	visible = false
	if _sel < 0:
		return ""
	var k: String = slots[_sel]
	return k if can.get(k, false) else ""


func _draw() -> void:
	var c := size * 0.5
	# 下の淡い丸（世界が透けて見えるくらい）
	draw_circle(c, RING_R + DISC_R + 14.0, Color(0.1, 0.1, 0.14, 0.18))
	for i in 8:
		var a := TAU * i / 8.0
		var p := c + Vector2(sin(a), -cos(a)) * RING_R
		var kind: String = slots[i]
		var on: bool = can.get(kind, false)
		var big := i == _sel and on
		var r := DISC_R * (1.18 if big else 1.0)
		var fade := 1.0 if on else 0.32
		draw_circle(p + Vector2(2, 3), r, Color(0, 0, 0, 0.18 * fade))   # 紙の影
		draw_circle(p, r, Color(PAPER, 0.95 * fade))
		draw_arc(p, r, 0, TAU, 28, Color(PICKED if big else EDGE, fade), 3.0 if big else 2.0, true)
		_icon(kind, p, r * 0.62, Color(INK, fade))
	# まんなかの点: いま向いている所
	draw_circle(c + _aim * 0.5, 5.0, Color(PAPER, 0.9))
	draw_arc(c + _aim * 0.5, 5.0, 0, TAU, 16, Color(EDGE, 0.9), 1.5, true)


# ---------------------------------------------------------------- 絵（墨の線）

func _line(a: Vector2, b: Vector2, col: Color, w := 3.0) -> void:
	draw_line(a, b, col, w, true)


## 立った人の形。arms は肩から見た右手と左手の先（u 単位）
func _figure(c: Vector2, u: float, col: Color, right: Vector2, left: Vector2) -> void:
	var head := c + Vector2(0, -0.62) * u
	draw_arc(head, 0.2 * u, 0, TAU, 16, col, 2.6, true)
	var neck := c + Vector2(0, -0.4) * u
	var hip := c + Vector2(0, 0.25) * u
	_line(neck, hip, col)
	_line(hip, c + Vector2(0.28, 0.85) * u, col)
	_line(hip, c + Vector2(-0.28, 0.85) * u, col)
	var sh := c + Vector2(0, -0.28) * u
	_line(sh, sh + right * u, col)
	_line(sh, sh + left * u, col)


func _icon(kind: String, c: Vector2, u: float, col: Color) -> void:
	match kind:
		"hand_up":
			_figure(c, u, col, Vector2(0.35, -0.75), Vector2(-0.3, 0.45))
			draw_circle(c + Vector2(0.38, -1.05) * u, 0.11 * u, col)   # 上げた手
		"banzai":
			_figure(c, u, col, Vector2(0.45, -0.7), Vector2(-0.45, -0.7))
		"wa":
			_figure(c, u, col, Vector2(0.55, -0.4), Vector2(-0.55, -0.4))
			for k in 3:   # うれしさの線
				var a := -PI / 2 + (k - 1) * 0.6
				var d := Vector2(cos(a), sin(a))
				_line(c + Vector2(0, -0.62) * u + d * 0.34 * u, c + Vector2(0, -0.62) * u + d * 0.5 * u, col, 2.2)
		"un":
			# うなずく頭と、下へ回る矢印
			var h := c + Vector2(-0.15, -0.1) * u
			draw_arc(h, 0.42 * u, 0, TAU, 20, col, 2.6, true)
			draw_arc(h, 0.72 * u, -0.9, 0.9, 12, col, 2.4, true)
			var tip := h + Vector2(cos(0.9), sin(0.9)) * 0.72 * u
			_line(tip, tip + Vector2(-0.22, -0.02) * u, col, 2.4)
			_line(tip, tip + Vector2(0.02, -0.24) * u, col, 2.4)
		"nn":
			# 横に振る頭と、左右の矢印
			var h := c + Vector2(0, -0.25) * u
			draw_arc(h, 0.4 * u, 0, TAU, 20, col, 2.6, true)
			var y := c.y + 0.5 * u
			_line(Vector2(c.x - 0.7 * u, y), Vector2(c.x + 0.7 * u, y), col, 2.4)
			for s in [-1.0, 1.0]:
				var e := Vector2(c.x + s * 0.7 * u, y)
				_line(e, e + Vector2(-s * 0.2, -0.16) * u, col, 2.4)
				_line(e, e + Vector2(-s * 0.2, 0.16) * u, col, 2.4)
		"make_ball":
			# しゃがんで、足もとの雪玉を丸める
			var head := c + Vector2(0.15, -0.3) * u
			draw_arc(head, 0.2 * u, 0, TAU, 16, col, 2.6, true)
			var hip := c + Vector2(-0.3, 0.35) * u
			_line(c + Vector2(0.05, -0.1) * u, hip, col)
			_line(hip, c + Vector2(0.05, 0.45) * u, col)
			_line(c + Vector2(0.05, 0.45) * u, c + Vector2(-0.05, 0.85) * u, col)
			_line(c + Vector2(0.0, 0.0) * u, c + Vector2(0.45, 0.45) * u, col)
			draw_circle(c + Vector2(0.55, 0.65) * u, 0.2 * u, col)
		"bow":
			# 腰から前へ折れる
			var hip := c + Vector2(-0.2, 0.15) * u
			var sh := c + Vector2(0.45, -0.25) * u
			_line(hip, sh, col)
			draw_arc(sh + Vector2(0.25, 0.12) * u, 0.2 * u, 0, TAU, 16, col, 2.6, true)
			_line(hip, c + Vector2(-0.1, 0.85) * u, col)
			_line(hip, c + Vector2(-0.35, 0.85) * u, col)
			_line(sh, sh + Vector2(0.05, 0.55) * u, col)
		"clap":
			# 二つの手袋が合わさる。まわりに小さな線
			for s in [-1.0, 1.0]:
				var p := c + Vector2(s * 0.22, 0.1) * u
				draw_set_transform(p, s * 0.35, Vector2.ONE)
				draw_circle(Vector2.ZERO, 0.0, col)
				var pts := PackedVector2Array()
				for k in 14:
					var a := TAU * k / 14.0
					pts.append(Vector2(cos(a) * 0.22, sin(a) * 0.42) * u)
				pts.append(pts[0])
				draw_polyline(pts, col, 2.6, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for k in 3:
				var a := -PI / 2 + (k - 1) * 0.7
				var d := Vector2(cos(a), sin(a))
				_line(c + Vector2(0, -0.35) * u + d * 0.25 * u, c + Vector2(0, -0.35) * u + d * 0.48 * u, col, 2.2)
		"breath":
			# 横顔と、長く伸びる白い息
			var h := c + Vector2(-0.5, -0.1) * u
			draw_arc(h, 0.32 * u, 0, TAU, 18, col, 2.6, true)
			var r := 0.1
			var x := -0.1
			for k in 4:
				draw_arc(c + Vector2(x, -0.15 - k * 0.06) * u, r * u, 0, TAU, 14, col, 2.0, true)
				x += r + 0.12 + k * 0.03
				r += 0.05
