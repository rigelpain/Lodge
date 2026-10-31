extends RefCounted
## 画面の表示（hud.gd）の絵。文字を使わない案内のための、手芸の部品で描いたアイコン。
## どの絵も 64 × 64 の箱（中心が原点、y は下向き）で描き、画面の大きさへ写して描く。
## 部品: フェルトのワッペン（毛羽のむらの面と、少しずれた影）、刺繍の線（内側の破線のステッチ）、
## 紙のタグ（穴と糸の輪）、糸の矢印（「＞」を糸で縫ったもの）。キーの形は刻印の文字だけ使う（キーの名前は言葉ではない）。
## 一覧は tools/hud_sheet.gd で design/hud/icons.png に書き出す。

const PAPER := Color(0.96, 0.93, 0.86)      # 生成りの紙（人の顔・札）
const PAPER_EDGE := Color(0.80, 0.72, 0.60)
const THREAD := Color(0.20, 0.25, 0.42)     # 藍の糸（刻印・刺繍の線）
const RED := Color(0.80, 0.24, 0.20)        # あなた
const NAVY := Color(0.24, 0.32, 0.55)       # 仲間（右・折り紙）
const MUSTARD := Color(0.88, 0.66, 0.20)    # 仲間（左・新聞紙）
const WOOD := Color(0.55, 0.38, 0.22)       # 滑り木
const STRAW := Color(0.86, 0.74, 0.48)      # 笠
const SNOW := Color(0.97, 0.97, 1.0)
const CAP := Color(0.98, 0.96, 0.92)        # キーのワッペン
const SHADOW := Color(0.10, 0.08, 0.16)
const LEG := Color(0.28, 0.27, 0.32)

const NAMES := ["grab", "release", "push", "ride", "rope", "pull", "scoop", "getoff", "sit", "standup", "lean_l", "lean_r", "brake",
	"wave", "point", "voice", "breath", "ring", "needle", "return", "walk", "run", "jump", "look", "zoom", "view",
	"cam_dist", "cam_frame", "tag_stack", "hill", "speed", "hourglass", "pip_cycle", "pip_off", "settings", "mouse_r", "mouse_move", "mouse_wheel", "mouse_pinch", "mouse_pan", "back", "untag", "tag_on"]

## HUD の物が受ける風（hud.gd が毎コマ入れる。0〜1.6 ほど）。設定「HUD が風で揺れる」を切ると 0、「視点の揺れ」を切ると小さく
static var wind := 0.0
static var wind_t := 0.0        # 揺れの時計 (s)
static var wind_stepped := true # 12 コマ／秒に刻む（人形と同じコマ撮り）。false でなめらか（見比べ用）
static var printing := false   # 立体の板に貼る印刷を描いているあいだ true（板の影は 3D で落とすので、外の落ち影を描かない）
static var user_scale := 1.0   # 設定の「HUD の大きさ」（settings.gd が入れる）
static var _felt: ImageTexture
static var _o := Vector2.ZERO   # いま描いている絵の中心（画面）
static var _s := 1.0            # 1 単位あたりの画面の px


## HUD の倍率: 画面の高さによる倍率（1080 で 1）に、設定の「HUD の大きさ」を掛ける。
## hud.gd・craft_ui.gd・emote_ring.gd・daycycle.gd の表示はみなこれでそろえる
static func ui_scale(view_h: float) -> float:
	return clampf(view_h / 1080.0, 0.6, 2.0) * user_scale


## 風の揺れの時計: コマ撮りなら 12 コマ／秒に刻んだ時間
static func _wt() -> float:
	return floorf(wind_t * 12.0) / 12.0 if wind_stepped else wind_t


static func _hash(n: float) -> float:
	return fposmod(sin(n * 12.9898 + 78.233) * 43758.5453, 1.0) * 2.0 - 1.0


## ガタガタの小刻み（-1〜1）。コマ撮りではコマごとに跳び、なめらかではコマの間をつなぐ
static func _jolt(seed: float) -> float:
	var f := wind_t * 12.0
	var n := floorf(f)
	if wind_stepped:
		return _hash(n + seed * 31.0)
	return lerpf(_hash(n + seed * 31.0), _hash(n + 1.0 + seed * 31.0), smoothstep(0.0, 1.0, f - n))


## 風を受けた物の傾き (rad): lean だけ後ろへなびき（風が満ちたとき）、flutter の振れでゆらぎ、速いほどガタガタ震える
static func wind_angle(seed: float, lean: float, flutter: float) -> float:
	if wind <= 0.001:
		return 0.0
	return wind * lean + sin(_wt() * 6.5 + seed) * flutter * wind + _jolt(seed) * flutter * 0.7 * wind * wind


## 風を受けた物のずれ (px): 速いほどガタガタ
static func wind_offset(seed: float, jit: float) -> Vector2:
	if wind <= 0.001:
		return Vector2.ZERO
	return Vector2(_jolt(seed + 0.3), _jolt(seed + 0.7)) * jit * wind * wind


## 支点 pivot のまわりに、風で傾けてずらす変換（draw_set_transform_matrix に渡す）
static func wind_xform(pivot: Vector2, seed: float, lean: float, flutter: float, jit: float) -> Transform2D:
	if wind <= 0.001:
		return Transform2D.IDENTITY
	return Transform2D(0.0, pivot + wind_offset(seed, jit)) * Transform2D(wind_angle(seed, lean, flutter), Vector2.ZERO) * Transform2D(0.0, -pivot)


## 貼った物の角が風でぱたぱためくれる: corner は角、e1・e2 はその角から辺に沿って内へ向かう向き（長さ 1）
static func flap(ci: CanvasItem, corner: Vector2, e1: Vector2, e2: Vector2, size: float, seed: float, col := PAPER) -> void:
	if wind <= 0.02:
		return
	var k := wind * (0.55 + 0.45 * sin(_wt() * 11.0 + seed)) + 0.15 * _jolt(seed + 2.0) * wind
	var s := size * clampf(k, 0.0, 1.4)
	if s < 1.0:
		return
	var a := corner + e1 * s
	var b := corner + e2 * s
	var tip := corner + (e1 + e2) * s * 0.85
	ci.draw_colored_polygon(PackedVector2Array([corner, a, b]), Color(SHADOW, 0.25))   # めくれた下の影
	ci.draw_colored_polygon(PackedVector2Array([a, tip, b]), col.darkened(0.08))       # めくれた裏
	ci.draw_polyline(PackedVector2Array([a, tip, b]), Color(PAPER_EDGE, 0.9), 1.0, true)


## フェルトの毛羽のむら（明るさ 0.86〜1.0 の灰色）。色と掛け合わせて面に貼る
static func felt() -> Texture2D:
	if _felt == null:
		var n := FastNoiseLite.new()
		n.seed = 3
		n.frequency = 0.09
		n.fractal_octaves = 4
		var img := n.get_seamless_image(64, 64)
		img.convert(Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var v := 0.86 + 0.14 * img.get_pixel(x, y).r
				img.set_pixel(x, y, Color(v, v, v))
		_felt = ImageTexture.create_from_image(img)
	return _felt


# ---- 形の材料（どれも絵の座標） ----------------------------------------------------------

static func circ(c: Vector2, r: float, n := 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		p.append(c + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r)
	return p


static func ell(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		p.append(c + Vector2(cos(TAU * i / n) * rx, sin(TAU * i / n) * ry))
	return p


## 角の丸い長方形
static func rr(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	r = minf(r, minf(w, h) / 2.0)
	var cs := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	for k in 4:
		for i in 5:
			var a := -PI / 2.0 + (k + i / 4.0) * PI / 2.0
			p.append(cs[k] + Vector2(cos(a), sin(a)) * r)
	return p


static func xf(pts: PackedVector2Array, rot: float, pos: Vector2, sc := 1.0) -> PackedVector2Array:
	var t := Transform2D(rot, pos)
	var o := PackedVector2Array()
	for p in pts:
		o.append(t * (p * sc))
	return o


## 画面の px をそのまま絵の座標にする（タグや札など、画面の座標で描くとき）
static func screen() -> void:
	_o = Vector2.ZERO
	_s = 1.0


static func _map(pts: PackedVector2Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p in pts:
		o.append(_o + p * _s)
	return o


# ---- 描く道具（絵の座標で受けて、画面へ写す） ----------------------------------------------

## フェルトのワッペン: 影、毛羽のむらの面、毛羽立った縁、内側の破線のステッチ
static func patch(ci: CanvasItem, pts: PackedVector2Array, col: Color, a := 1.0, stitch := true, thread := Color(0, 0, 0, 0), shadow := true) -> void:
	var m := _map(pts)
	if shadow:
		var sh := PackedVector2Array()
		for p in m:
			sh.append(p + Vector2(0.9, 1.4) * maxf(_s, 0.6))
		ci.draw_colored_polygon(sh, Color(SHADOW, 0.26 * a))
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 22.0)
	ci.draw_colored_polygon(m, Color(col, a), uv, felt())
	var edge := m.duplicate()
	edge.append(m[0])
	ci.draw_polyline(edge, Color(col.lightened(0.25), 0.45 * a), 1.3 * maxf(_s, 0.7), true)
	if stitch and _s * 64.0 >= 26.0:
		var inset := Geometry2D.offset_polygon(pts, -2.2, Geometry2D.JOIN_ROUND)
		if inset.size() > 0:
			var th: Color = thread if thread.a > 0.0 else col.darkened(0.45)
			dashes(ci, inset[0], th, 0.9, 2.6, 1.8, a, true)


## 刺繍の破線（ランニングステッチ）。目の長さと間は絵の単位
static func dashes(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, on: float, off: float, a := 1.0, closed := false) -> void:
	var path := pts.duplicate()
	if closed:
		path.append(pts[0])
	var t := 0.0
	var draw_on := true
	var left := on
	for i in path.size() - 1:
		var p0 := path[i]
		var p1 := path[i + 1]
		var seg := p0.distance_to(p1)
		var d := 0.0
		while d < seg:
			var step := minf(left, seg - d)
			if draw_on:
				var q0 := p0.lerp(p1, d / seg)
				var q1 := p0.lerp(p1, (d + step) / seg)
				ci.draw_line(_o + q0 * _s, _o + q1 * _s, Color(col, col.a * a), maxf(w * _s, 1.0), true)
			d += step
			left -= step
			if left <= 0.0001:
				draw_on = not draw_on
				left = on if draw_on else off
		t += seg


## 糸の線: 太い糸に、撚りの明るい筋を細かく重ねる（サテンステッチ風）
static func thread(ci: CanvasItem, pts: PackedVector2Array, col: Color, w := 2.4, a := 1.0) -> void:
	var m := _map(pts)
	ci.draw_polyline(m, Color(SHADOW, 0.22 * a), w * _s + 1.0, true)
	ci.draw_polyline(m, Color(col, a), w * _s, true)
	dashes(ci, pts, col.lightened(0.35), w * 0.3, 1.2, 1.6, 0.8 * a)


## 糸の矢印「＞」。dir は向き（右が 0）
static func chevron(ci: CanvasItem, c: Vector2, size: float, col: Color, a := 1.0, dir := 0.0, w := 2.6) -> void:
	var p := PackedVector2Array([Vector2(-0.35, -0.5), Vector2(0.25, 0.0), Vector2(-0.35, 0.5)])
	thread(ci, xf(p, dir, c, size), col, w, a)


## 弧の矢印（曲がる・回る）。from から to（ラジアン）、先に矢じり
static func arc_arrow(ci: CanvasItem, c: Vector2, r: float, from: float, to: float, col: Color, a := 1.0, w := 2.4) -> void:
	var p := PackedVector2Array()
	for i in 13:
		var t := lerpf(from, to, i / 12.0)
		p.append(c + Vector2(cos(t), sin(t)) * r)
	thread(ci, p, col, w, a)
	var tip := p[12]
	var tan := (p[12] - p[11]).normalized()
	var nrm := Vector2(-tan.y, tan.x)
	patch(ci, PackedVector2Array([tip + tan * 4.0, tip - tan * 2.0 + nrm * 3.6, tip - tan * 2.0 - nrm * 3.6]), col, a, false)


## まっすぐな矢印
static func arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, a := 1.0, w := 2.4) -> void:
	var d := (to - from).normalized()
	var nrm := Vector2(-d.y, d.x)
	thread(ci, PackedVector2Array([from, to - d * 3.0]), col, w, a)
	patch(ci, PackedVector2Array([to + d * 2.0, to - d * 4.0 + nrm * 4.0, to - d * 4.0 - nrm * 4.0]), col, a, false)


# ---- 絵を描く入口 ----------------------------------------------------------------------

## 名前の絵を、画面の center に、size px の箱で描く
static func icon(ci: CanvasItem, name: String, center: Vector2, size: float, a := 1.0, tint := RED) -> void:
	_o = center
	_s = size / 64.0
	match name:
		"grab": _grab(ci, a, tint)
		"release": _release(ci, a, tint)
		"push": _push(ci, a, tint)
		"ride": _ride(ci, a, tint)
		"rope": _rope(ci, a, tint)
		"pull": _pull(ci, a, tint)
		"scoop": _scoop(ci, a, tint)
		"getoff": _getoff(ci, a, tint)
		"sit": _sit(ci, a, tint)
		"standup": _standup(ci, a, tint)
		"lean_l": _lean(ci, a, tint, -1)
		"lean_r": _lean(ci, a, tint, 1)
		"brake": _brake(ci, a, tint)
		"wave": _wave(ci, a, tint)
		"point": _point(ci, a, tint)
		"voice": _voice(ci, a)
		"breath": _breath(ci, a)
		"ring": _ring(ci, a, tint)
		"needle": _needle(ci, a)
		"return": _return(ci, a)
		"walk": doll(ci, Vector2(0, 26), tint, "walk", a)
		"run": _run(ci, a, tint)
		"jump": _jump(ci, a, tint)
		"look": _look(ci, a)
		"zoom": _zoom(ci, a)
		"hill": _hill(ci, a)
		"speed": _speed(ci, a)
		"hourglass": _hourglass(ci, a)
		"cam_dist": _cam_dist(ci, a, tint)
		"tag_stack": _tag_stack(ci, a)
		"cam_frame": _cam_frame(ci, a, tint)
		"view": _view(ci, a, tint)
		"pip_cycle": _pip(ci, a, false)
		"pip_off": _pip(ci, a, true)
		"settings": _button(ci, a)
		"mouse_r": mouse(ci, Vector2.ZERO, a, "right")
		"mouse_l": mouse(ci, Vector2.ZERO, a, "left")
		"mouse_move": _mouse_move(ci, a)
		"mouse_wheel": _mouse_wheel(ci, a)
		"mouse_pinch": _pinch(ci, a)
		"mouse_pan": _pan(ci, a)
		"back": _back(ci, a)
		"untag": _tag_move(ci, a, true)
		"tag_on": _tag_move(ci, a, false)
		"person": doll(ci, Vector2(0, 26), tint, "stand", a)
		"person_sit": doll(ci, Vector2(0, 22), tint, "sit", a)
		_:   # 工房の絵（型紙・布・畳む・広げる。craft_icons.gd）
			preload("res://craft_icons.gd").draw(ci, name, a, tint)


## キーの形のワッペンの幅（px）。size は高さ
static func keycap_w(key: String, size: float) -> float:
	var w := 28.0
	if key == "Shift":
		w = 40.0
	elif key == "Space":
		w = 58.0
	elif key in ["Left", "Right", "Up", "Down"]:
		w = 28.0
	elif key == "Backspace":
		w = 40.0
	elif key.length() > 1:
		w = 16.0 + key.length() * 8.0
	return w * size / 28.0


## キーの形のワッペン。刻印は key（"Shift" と "Space" は形で描く）。size は高さ（px）
static func keycap(ci: CanvasItem, key: String, center: Vector2, size: float, a := 1.0, pressed := false) -> float:
	_o = center
	_s = size / 28.0
	var w := keycap_w(key, 28.0)
	var col := CAP.darkened(0.12) if pressed else CAP
	patch(ci, rr(-w / 2.0, -14.0, w, 28.0, 6.0), col, a, true, THREAD.lightened(0.3))
	# 押す面（少し明るく、手前の縁を残す）
	var top := rr(-w / 2.0 + 2.5, -12.5, w - 5.0, 22.0, 5.0)
	ci.draw_colored_polygon(_map(top), Color(1, 1, 1, 0.35 * a))
	if key in ["Left", "Right", "Up", "Down"]:   # 矢印キー: 刻印の代わりに三角
		var ang: float = {"Right": 0.0, "Down": PI / 2.0, "Left": PI, "Up": -PI / 2.0}[key]
		var tri := xf(PackedVector2Array([Vector2(6, 0), Vector2(-4, -6), Vector2(-4, 6)]), ang, Vector2.ZERO)
		ci.draw_colored_polygon(_map(tri), Color(THREAD, a))
		return w * _s
	if key == "Shift":
		var p := PackedVector2Array([Vector2(0, -8), Vector2(7, 0), Vector2(3, 0), Vector2(3, 6), Vector2(-3, 6), Vector2(-3, 0), Vector2(-7, 0)])
		var m := _map(p)
		m.append(m[0])
		ci.draw_polyline(m, Color(THREAD, a), maxf(1.6 * _s, 1.0), true)
	elif key == "Backspace":   # 左向きの五角形に ×（文字にすると長い）
		var p := PackedVector2Array([Vector2(-11, 0), Vector2(-5, -7), Vector2(11, -7), Vector2(11, 7), Vector2(-5, 7), Vector2(-11, 0)])
		ci.draw_polyline(_map(p), Color(THREAD, a), maxf(1.6 * _s, 1.0), true)
		ci.draw_polyline(_map(PackedVector2Array([Vector2(-1, -3), Vector2(5, 3)])), Color(THREAD, a), maxf(1.6 * _s, 1.0), true)
		ci.draw_polyline(_map(PackedVector2Array([Vector2(5, -3), Vector2(-1, 3)])), Color(THREAD, a), maxf(1.6 * _s, 1.0), true)
	elif key != "Space":
		var font := ThemeDB.fallback_font
		var fs := int(round((15.0 if key.length() == 1 else 12.0) * _s))
		var tw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var asc := font.get_ascent(fs)
		var base := _o + Vector2(-tw / 2.0, asc * 0.36 - 1.0 * _s)
		ci.draw_string(font, base, key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(THREAD, a))
		ci.draw_string(font, base + Vector2(0.6, 0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(THREAD, 0.5 * a))   # 刺繍の糸の太さ
	return w * _s


## 案内のワッペン: 丸いフェルトの台に、キーと絵を並べる。keys は "F" のような刻印か "mouse_r" のような絵の名前。
## size はワッペンの高さ（px）。pop で一瞬ふくらむ
static func badge(ci: CanvasItem, keys: Array, icon_name: String, center: Vector2, size: float, a := 1.0, tint := RED, pop := 0.0) -> void:
	var sz := size * (1.0 + 0.25 * pop)
	var w := badge_w(keys, sz)
	_o = center
	_s = sz / 64.0
	var hw := w / 2.0 / _s
	patch(ci, rr(-hw, -30.0, hw * 2.0, 60.0, 26.0), Color(0.99, 0.97, 0.93), a if printing else 0.92 * a, true, PAPER_EDGE, not printing)
	var x := center.x - w / 2.0 + sz * 0.2
	for k in keys:
		var kw := _key_w(k, sz)
		if k.begins_with("mouse"):
			icon(ci, k, Vector2(x + kw / 2.0, center.y), sz * 0.7, a)
		else:
			keycap(ci, k, Vector2(x + kw / 2.0, center.y), sz * 0.5, a)
		x += kw + sz * 0.06
	icon(ci, icon_name, Vector2(x + sz * 0.5, center.y), sz * 1.0, a, tint)


## 案内のワッペンの幅（px）
static func badge_w(keys: Array, size: float) -> float:
	var w := size * 0.4 + size * 1.0
	for k in keys:
		w += _key_w(k, size) + size * 0.06
	return w


static func _key_w(k: String, size: float) -> float:
	return size * 0.42 if k.begins_with("mouse") else keycap_w(k, size * 0.5)


## 刺繍の文字（数字）: 太らせた字を、藍の縁の糸と、少し明るい糸で重ねる（判子のように輪郭がしっかりした字）。
## at は字の左の、縦のまんなか。返り値は字の幅（px）
static func stitched_text(ci: CanvasItem, text: String, at: Vector2, size: float, col: Color, bold := true) -> float:
	var font := _bold_font() if bold else ThemeDB.fallback_font
	var fs := maxi(8, int(round(size)))
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	var base := at + Vector2(0, (asc - desc) / 2.0)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string_outline(font, base + Vector2(0.8, 1.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 6), Color(SHADOW, 0.18))
	ci.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, fs / 7), Color(PAPER, 0.95))
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if bold and fs >= 14:   # 糸の撚り: 字の上に細い明るい筋を重ねる
		ci.draw_string(font, base + Vector2(-0.5, -0.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.lightened(0.45), 0.25))
	return w


static var _bold: FontVariation

static func _bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.7
	return _bold


## 吊るす紙の札: 上の両角を切った無地の紙。外側に影と藍の縁取り、内側に破線のステッチ（どの背景の上でも読める）。
## rect は画面の px、cut は角を切る長さ、u は線の太さの倍率
static func paper_tag(ci: CanvasItem, rect: Rect2, cut: float, u := 1.0) -> void:
	screen()
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var pts := PackedVector2Array([Vector2(x + cut, y), Vector2(x + w - cut, y), Vector2(x + w, y + cut), Vector2(x + w, y + h),
		Vector2(x, y + h), Vector2(x, y + cut)])
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(2.0, 3.0) * u)
	if not printing:
		ci.draw_colored_polygon(sh, Color(SHADOW, 0.30))
	ci.draw_colored_polygon(pts, PAPER)
	var edge := pts.duplicate()
	edge.append(pts[0])
	ci.draw_polyline(edge, Color(THREAD, 0.85), 1.6 * u, true)
	var inset := Geometry2D.offset_polygon(pts, -5.0 * u)
	if inset.size() > 0:
		dashes(ci, inset[0], Color(THREAD, 0.5), 1.1 * u, 4.0 * u, 3.0 * u, 1.0, true)


## 紙のタグ: 角を切った紙に、穴と糸の輪。rect は画面の px
static func tag(ci: CanvasItem, rect: Rect2, a := 1.0) -> void:
	_o = rect.position
	_s = 1.0
	var w := rect.size.x
	var h := rect.size.y
	var c := minf(h * 0.28, 26.0)
	var pts := PackedVector2Array([Vector2(c, 0), Vector2(w, 0), Vector2(w, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])
	patch(ci, pts, PAPER, a, false)
	# 縁のステッチ（藍の糸）
	var inset := Geometry2D.offset_polygon(pts, -5.0)
	if inset.size() > 0:
		dashes(ci, inset[0], Color(THREAD, 0.55), 1.2, 5.0, 3.5, a, true)
	# 穴（はとめ）と糸の輪
	var hole := Vector2(c * 0.62, h / 2.0)
	ci.draw_circle(_o + hole, 5.5, Color(PAPER_EDGE, a))
	ci.draw_circle(_o + hole, 3.6, Color(0.35, 0.30, 0.28, 0.85 * a))
	var loop := PackedVector2Array()
	for i in 16:
		var t := i / 15.0
		loop.append(hole + Vector2(-t * 22.0, sin(t * PI) * -10.0 - t * 6.0))
	thread(ci, loop, RED, 1.6, a)


# ---- 人形 ------------------------------------------------------------------------------

## 紙の人形（笠とフェルトの上着）。feet は足もと（絵の座標）。pose: stand walk run push pull sit lean_l lean_r
## sit_fwd sit_back wave jump back（後ろ姿で座る）
static func doll(ci: CanvasItem, feet: Vector2, col: Color, pose: String, a := 1.0, sc := 1.0) -> void:
	var rot := 0.0
	var sit := pose.begins_with("sit") or pose.begins_with("lean") or pose == "back"
	match pose:
		"push": rot = 0.42
		"pull": rot = 0.30
		"run": rot = 0.22
		"walk": rot = 0.08
		"lean_l": rot = -0.38
		"lean_r": rot = 0.38
		"sit_fwd": rot = 0.5
		"sit_back": rot = -0.45
	var hip := feet + Vector2(0, -8.0 * sc) if not sit else feet
	var X := func(p: PackedVector2Array) -> PackedVector2Array: return xf(p, rot, hip, sc)
	var legs: Array[PackedVector2Array] = []
	if sit:
		if pose == "back" or pose.begins_with("lean"):
			legs = [rr(-5, -1, 4, 5, 1.5), rr(1, -1, 4, 5, 1.5)]
		else:
			legs = [rr(-2, -3, 13, 4, 1.8), rr(0, -1, 12, 4, 1.8)]
	else:
		var st := 0.0
		match pose:
			"walk": st = 0.25
			"run", "push", "pull": st = 0.5
			"jump": st = 0.15
		legs = [xf(rr(-2, 0, 4, 9, 1.8), st, Vector2(-1.5, 0)), xf(rr(-2, 0, 4, 9, 1.8), -st, Vector2(1.5, 0))]
	for l in legs:
		patch(ci, X.call(l) if sit else xf(l, 0.0, hip, sc), LEG, a, false)
	# 上着
	var coat := PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(6, -16), Vector2(-6, -16)]) if not sit \
		else PackedVector2Array([Vector2(-8, 0), Vector2(8, 0), Vector2(6, -15), Vector2(-6, -15)])
	# 腕（上着の色の太い線）と手袋
	var sh_l := Vector2(-5.5, -13)
	var sh_r := Vector2(5.5, -13)
	var hands := [Vector2(-7, -3), Vector2(7, -3)]
	match pose:
		"push": hands = [Vector2(13, -11), Vector2(14, -8)]
		"pull": hands = [Vector2(-12, -6), Vector2(-11, -9)]
		"run": hands = [Vector2(-8, -6), Vector2(9, -11)]
		"walk": hands = [Vector2(-6, -4), Vector2(8, -5)]
		"wave", "jump": hands = [Vector2(-8, -4), Vector2(10, -24)]
		"sit", "sit_back": hands = [Vector2(8, -6), Vector2(9, -7)]
		"sit_fwd": hands = [Vector2(12, -2), Vector2(13, 0)]
		"back", "lean_l", "lean_r": hands = [Vector2(-9, -5), Vector2(9, -5)]
	for i in 2:
		var sh: Vector2 = [sh_l, sh_r][i]
		thread(ci, X.call(PackedVector2Array([sh, hands[i]])), col.darkened(0.1), 3.2 * sc, a)
	patch(ci, X.call(coat), col, a, true)
	for i in 2:
		patch(ci, X.call(circ(hands[i], 2.4, 10)), col.darkened(0.35), a, false)
	# 顔（紙）と笠
	patch(ci, X.call(circ(Vector2(0, -20.5), 4.6, 14)), PAPER, a, false)
	var hat := PackedVector2Array([Vector2(-10.5, -23.5), Vector2(10.5, -23.5), Vector2(0, -30.5)])
	patch(ci, X.call(hat), STRAW, a, false)
	if pose == "back":
		return
	# 向き: 顔の前の側に、小さな白い息の点
	if pose != "lean_l" and pose != "lean_r":
		var dir := -1.0 if pose == "pull" else 1.0
		ci.draw_circle(_o + (Transform2D(rot, hip) * (Vector2(6.5 * dir, -20) * sc)) * _s, 1.0 * _s * sc, Color(SNOW, 0.8 * a))


## 横から見たソリ（赤いフェルトの台に、曲げ木の滑り木）。c は台の中心。前は右（flip で左）
static func sled_side(ci: CanvasItem, c: Vector2, sc: float, a := 1.0, tilt := 0.0, flip := false) -> void:
	var F := func(pts: PackedVector2Array) -> PackedVector2Array:
		var o := PackedVector2Array()
		for p in pts:
			o.append(Vector2(-p.x, p.y) if flip else p)
		return xf(o, tilt, c, sc)
	var run := PackedVector2Array()
	for i in 9:
		var x := lerpf(-17.0, 15.0, i / 8.0)
		run.append(Vector2(x, 6.0))
	for i in 6:   # 前の曲がり
		var t := i / 5.0 * PI * 0.9
		run.append(Vector2(15.0 + sin(t) * 4.0, 6.0 - (1.0 - cos(t)) * 3.5))
	thread(ci, F.call(run), WOOD, 2.2 * sc, a)
	for x: float in [-10.0, 8.0]:
		thread(ci, F.call(PackedVector2Array([Vector2(x, 1), Vector2(x, 6)])), WOOD, 1.8 * sc, a)
	patch(ci, F.call(rr(-18, -4, 34, 6, 3)), RED, a, false)
	patch(ci, F.call(rr(-19, -10, 5, 9, 2)), RED.darkened(0.15), a, false)   # 背もたれ（後ろ）


## 後ろから見たソリ（左右の滑り木と台）
static func sled_back(ci: CanvasItem, c: Vector2, sc: float, a := 1.0, tilt := 0.0) -> void:
	for x: float in [-9.0, 9.0]:
		thread(ci, xf(PackedVector2Array([Vector2(x, -1), Vector2(x, 5)]), tilt, c, sc), WOOD, 2.0 * sc, a)
		patch(ci, xf(rr(x - 3.5, 4, 7, 3, 1.5), tilt, c, sc), WOOD, a, false)
	patch(ci, xf(rr(-14, -5, 28, 6, 3), tilt, c, sc), RED, a, false)


## 手袋（ミトン）。open: 指をそろえて開く、閉じると握る
static func mitten(ci: CanvasItem, c: Vector2, rot: float, col: Color, a := 1.0, open := true, sc := 1.0) -> void:
	if open:
		patch(ci, xf(rr(-6, -9, 12, 17, 6), rot, c, sc), col, a, true)
		patch(ci, xf(ell(Vector2(-7.5, 1), 2.8, 5.0, 12), rot - 0.5, c, sc), col.darkened(0.08), a, false)
		patch(ci, xf(rr(-6.5, 6, 13, 5, 2), rot, c, sc), col.darkened(0.3), a, false)   # 袖口
	else:
		patch(ci, xf(rr(-7, -6, 14, 12, 5.5), rot, c, sc), col, a, true)
		patch(ci, xf(rr(-7.5, 4, 15, 5, 2), rot, c, sc), col.darkened(0.3), a, false)


## マウス。button: right / wheel / none
static func mouse(ci: CanvasItem, c: Vector2, a := 1.0, button := "none") -> void:
	patch(ci, xf(rr(-11, -16, 22, 32, 11), 0.0, c), CAP, a, true, THREAD.lightened(0.3))
	thread(ci, PackedVector2Array([c + Vector2(-10.5, -3), c + Vector2(10.5, -3)]), THREAD.lightened(0.4), 1.0, 0.7 * a)
	thread(ci, PackedVector2Array([c + Vector2(0, -15.5), c + Vector2(0, -3)]), THREAD.lightened(0.4), 1.0, 0.7 * a)
	if button == "right":
		patch(ci, PackedVector2Array([c + Vector2(1.5, -14.5), c + Vector2(6, -13), c + Vector2(9, -9), c + Vector2(9.5, -4.5), c + Vector2(1.5, -4.5)]), RED, a, false)
	elif button == "left":
		patch(ci, PackedVector2Array([c + Vector2(-1.5, -14.5), c + Vector2(-6, -13), c + Vector2(-9, -9), c + Vector2(-9.5, -4.5), c + Vector2(-1.5, -4.5)]), RED, a, false)
	elif button == "wheel":
		patch(ci, xf(rr(-2.2, -13, 4.4, 8, 2.2), 0.0, c), RED, a, false)


# ---- 一つずつの絵 ------------------------------------------------------------------------

static func _grab(ci: CanvasItem, a: float, col: Color) -> void:
	patch(ci, rr(-26, 4, 52, 8, 3), WOOD, a, true)   # ソリの縁
	mitten(ci, Vector2(-2, 2), 0.0, col, a, false, 1.4)
	for x: float in [-14.0, 10.0]:
		thread(ci, PackedVector2Array([Vector2(x, -20), Vector2(x + 2, -14)]), THREAD, 1.6, 0.6 * a)


static func _release(ci: CanvasItem, a: float, col: Color) -> void:
	patch(ci, rr(-26, 14, 52, 8, 3), WOOD, a, true)
	mitten(ci, Vector2(0, -6), 0.0, col, a, true, 1.3)
	for s: float in [-1.0, 1.0]:
		arc_arrow(ci, Vector2(0, -6), 20.0, -PI / 2.0 + s * 0.5, -PI / 2.0 + s * 1.2, THREAD, 0.8 * a, 1.8)


static func _push(ci: CanvasItem, a: float, col: Color) -> void:
	doll(ci, Vector2(-14, 24), col, "push", a, 1.05)
	sled_side(ci, Vector2(14, 12), 0.8, a)
	chevron(ci, Vector2(14, -14), 12.0, THREAD, a)
	chevron(ci, Vector2(22, -14), 12.0, THREAD, 0.6 * a)


static func _ride(ci: CanvasItem, a: float, col: Color) -> void:
	sled_side(ci, Vector2(0, 16), 1.3, a)
	doll(ci, Vector2(-4, 10), col, "sit", a, 1.05)


static func _rope(ci: CanvasItem, a: float, col: Color) -> void:
	var rope := PackedVector2Array()
	for i in 12:
		var t := i / 11.0
		rope.append(Vector2(lerpf(-22.0, 8.0, t), lerpf(22.0, -4.0, t) + sin(t * PI) * 7.0))
	thread(ci, rope, Color(0.78, 0.66, 0.46), 2.4, a)
	sled_side(ci, Vector2(-20, 26), 0.55, a)
	mitten(ci, Vector2(10, -6), 0.4, col, a, false, 1.3)


static func _pull(ci: CanvasItem, a: float, col: Color) -> void:
	sled_side(ci, Vector2(-16, 20), 0.65, a)
	thread(ci, PackedVector2Array([Vector2(-5, 18), Vector2(6, 9), Vector2(10, 7)]), Color(0.78, 0.66, 0.46), 1.8, a)
	doll(ci, Vector2(14, 26), col, "walk", a, 1.0)
	chevron(ci, Vector2(26, -6), 10.0, THREAD, a)


static func _scoop(ci: CanvasItem, a: float, col: Color) -> void:
	sled_side(ci, Vector2(-4, 18), 1.1, a)
	doll(ci, Vector2(-8, 13), col, "sit_fwd", a, 1.0)
	for i in 3:
		ci.draw_circle(_o + Vector2(20 + i * 3.5, 20 - i * 4.0) * _s, (2.2 - i * 0.4) * _s, Color(SNOW, 0.9 * a))
		ci.draw_arc(_o + Vector2(20 + i * 3.5, 20 - i * 4.0) * _s, (2.2 - i * 0.4) * _s, 0, TAU, 10, Color(THREAD, 0.35 * a), 0.8, true)
	chevron(ci, Vector2(22, -10), 10.0, THREAD, a)


static func _getoff(ci: CanvasItem, a: float, col: Color) -> void:
	sled_side(ci, Vector2(-8, 20), 0.95, a)
	doll(ci, Vector2(20, 28), col, "stand", a, 0.9)
	arc_arrow(ci, Vector2(4, 12), 14.0, PI * 1.1, PI * 1.85, THREAD, a, 2.0)


## 横から見た椅子（座布団つき。前は右）。c は座面の上のまんなか
static func chair_side(ci: CanvasItem, c: Vector2, sc: float, a := 1.0) -> void:
	var P := func(x: float, y: float, w: float, h: float) -> PackedVector2Array: return xf(rr(x, y, w, h, 1.2), 0.0, c, sc)
	patch(ci, P.call(-11.0, -24.0, 3.6, 25.0), WOOD, a, false)               # 背もたれ
	patch(ci, P.call(-10.0, 2.0, 3.2, 16.0), WOOD.darkened(0.2), a, false)    # 後ろの脚
	patch(ci, P.call(7.0, 2.0, 3.2, 16.0), WOOD.darkened(0.2), a, false)      # 前の脚
	patch(ci, P.call(-12.0, 0.0, 23.0, 4.0), WOOD, a, false)                  # 座面
	patch(ci, P.call(-9.0, -3.0, 19.0, 3.6), Color(0.79, 0.54, 0.40), a, false)   # 座布団


static func _sit(ci: CanvasItem, a: float, col: Color) -> void:
	chair_side(ci, Vector2(-4, 10), 1.05, a)
	doll(ci, Vector2(-6, 6), col, "sit", a, 1.0)
	chevron(ci, Vector2(20, -10), 10.0, THREAD, a, PI / 2.0)          # 腰を下ろす
	chevron(ci, Vector2(20, -3), 10.0, THREAD, 0.6 * a, PI / 2.0)


static func _standup(ci: CanvasItem, a: float, col: Color) -> void:
	chair_side(ci, Vector2(-10, 10), 0.95, a)
	doll(ci, Vector2(16, 28), col, "stand", a, 0.9)
	arc_arrow(ci, Vector2(2, 10), 14.0, PI * 1.1, PI * 1.85, THREAD, a, 2.0)


static func _lean(ci: CanvasItem, a: float, col: Color, side: int) -> void:
	var tilt := 0.18 * side
	sled_back(ci, Vector2(0, 20), 1.2, a, tilt)
	doll(ci, Vector2(0, 15), col, "lean_r" if side > 0 else "lean_l", a, 1.0)
	arc_arrow(ci, Vector2(0, 10), 26.0, -PI / 2.0 - 0.15 * side, -PI / 2.0 + 0.9 * side, THREAD, a, 2.2)


static func _brake(ci: CanvasItem, a: float, col: Color) -> void:
	sled_side(ci, Vector2(-2, 16), 1.1, a)
	doll(ci, Vector2(-6, 11), col, "sit_back", a, 1.0)
	for i in 4:   # 前で舞い上がる雪
		var p := Vector2(22 + i * 2.5, 16 - i * 4.5)
		ci.draw_circle(_o + p * _s, (2.6 - i * 0.4) * _s, Color(SNOW, 0.95 * a))
		ci.draw_arc(_o + p * _s, (2.6 - i * 0.4) * _s, 0, TAU, 10, Color(THREAD, 0.35 * a), 0.8, true)
	thread(ci, PackedVector2Array([Vector2(-26, -14), Vector2(-14, -14)]), THREAD, 2.2, a)   # 止まる: 前で止める線
	thread(ci, PackedVector2Array([Vector2(-26, -20), Vector2(-26, -8)]), THREAD, 2.2, a)


static func _wave(ci: CanvasItem, a: float, col: Color) -> void:
	mitten(ci, Vector2(0, 2), -0.25, col, a, true, 1.5)
	for s: float in [-1.0, 1.0]:
		for k in 2:
			var r := 20.0 + k * 6.0
			var ctr := Vector2(0, 2)
			var p := PackedVector2Array()
			for i in 6:
				var t := -PI / 2.0 + s * lerpf(0.55, 0.95, i / 5.0)
				p.append(ctr + Vector2(cos(t), sin(t)) * r)
			thread(ci, p, THREAD, 1.6, (0.8 - k * 0.3) * a)


static func _point(ci: CanvasItem, a: float, col: Color) -> void:
	thread(ci, PackedVector2Array([Vector2(-26, 14), Vector2(-6, 2)]), col.darkened(0.1), 6.0, a)   # 腕
	mitten(ci, Vector2(-2, 0), -2.1, col, a, true, 1.0)
	dashes(ci, PackedVector2Array([Vector2(8, -6), Vector2(22, -14)]), THREAD, 1.4, 2.4, 2.0, a)
	ci.draw_arc(_o + Vector2(25, -16) * _s, 5.0 * _s, 0, TAU, 16, Color(THREAD, a), 1.6 * _s, true)
	ci.draw_circle(_o + Vector2(25, -16) * _s, 1.8 * _s, Color(RED, a))


static func _voice(ci: CanvasItem, a: float) -> void:
	patch(ci, PackedVector2Array([Vector2(-22, -8), Vector2(-10, -18), Vector2(6, -18), Vector2(16, -8), Vector2(14, 6), Vector2(2, 12),
		Vector2(-8, 12), Vector2(-14, 22), Vector2(-14, 10), Vector2(-22, 4)]), PAPER, a, true, PAPER_EDGE)
	for k in 3:
		var p := PackedVector2Array()
		for i in 7:
			var t := lerpf(-0.6, 0.6, i / 6.0)
			p.append(Vector2(14, -2) + Vector2(cos(t), sin(t)) * (8.0 + k * 6.0))
		thread(ci, p, THREAD, 1.6, (1.0 - k * 0.25) * a)
	for i in 3:
		ci.draw_circle(_o + Vector2(-10 + i * 7, -3) * _s, 1.5 * _s, Color(THREAD, a))


static func _breath(ci: CanvasItem, a: float) -> void:
	for i in 4:
		var c := Vector2(-16 + i * 11, 4 - i * 4)
		patch(ci, circ(c, 6.0 + i * 2.0, 14), SNOW, (1.0 - i * 0.15) * a, true, Color(0.7, 0.75, 0.88))


static func _ring(ci: CanvasItem, a: float, col: Color) -> void:
	for i in 8:
		var t := -PI / 2.0 + TAU * i / 8.0
		patch(ci, circ(Vector2(cos(t), sin(t)) * 22.0, 6.0, 12), PAPER, a, false)
		ci.draw_arc(_o + Vector2(cos(t), sin(t)) * 22.0 * _s, 6.0 * _s, 0, TAU, 14, Color(PAPER_EDGE, a), 1.0, true)
	ci.draw_arc(_o + Vector2(0, -22) * _s, 7.5 * _s, 0, TAU, 16, Color(RED, a), 1.8 * _s, true)
	mitten(ci, Vector2(0, 1), 0.0, col, a, true, 0.95)


static func _needle(ci: CanvasItem, a: float) -> void:
	var p0 := Vector2(-18, 20)
	var p1 := Vector2(16, -18)
	var d := (p1 - p0).normalized()
	var n := Vector2(-d.y, d.x)
	patch(ci, PackedVector2Array([p0, p1 + n * 2.6, p1 + d * 4.0, p1 - n * 2.6]), Color(0.78, 0.80, 0.84), a, false)
	ci.draw_arc(_o + (p1 - d * 1.0) * _s, 1.2 * _s, 0, TAU, 8, Color(SHADOW, 0.6 * a), 1.0, true)
	var th := PackedVector2Array()
	for i in 16:
		var t := i / 15.0
		th.append(p1 - d * 1.0 + Vector2(10 * sin(t * PI * 1.4), 6 + t * 26.0 - 10 * sin(t * PI)))
	thread(ci, th, RED, 1.8, a)


static func _return(ci: CanvasItem, a: float) -> void:
	sled_side(ci, Vector2(0, 4), 0.8, a)
	arc_arrow(ci, Vector2(0, 2), 22.0, -0.2, PI * 1.55, THREAD, a, 2.2)


static func _run(ci: CanvasItem, a: float, col: Color) -> void:
	doll(ci, Vector2(4, 26), col, "run", a)
	for i in 3:
		thread(ci, PackedVector2Array([Vector2(-28, -6 + i * 8), Vector2(-14 + i * 2, -6 + i * 8)]), THREAD, 1.6, (0.9 - i * 0.2) * a)


static func _jump(ci: CanvasItem, a: float, col: Color) -> void:
	thread(ci, PackedVector2Array([Vector2(-24, 28), Vector2(24, 28)]), Color(0.7, 0.75, 0.88), 2.0, a)
	doll(ci, Vector2(-4, 20), col, "jump", a, 0.95)
	arrow(ci, Vector2(18, 20), Vector2(18, -18), THREAD, a, 2.2)


static func _look(ci: CanvasItem, a: float) -> void:
	patch(ci, ell(Vector2.ZERO, 22, 12, 22), PAPER, a, true, PAPER_EDGE)
	patch(ci, circ(Vector2(4, 0), 8, 16), NAVY, a, false)
	ci.draw_circle(_o + Vector2(6, -2) * _s, 2.0 * _s, Color(1, 1, 1, 0.85 * a))
	arrow(ci, Vector2(-8, 22), Vector2(-26, 22), THREAD, a, 1.8)
	arrow(ci, Vector2(8, 22), Vector2(26, 22), THREAD, a, 1.8)


## 小さな丘（頂上に旗）。確かめ用の札の「高さ」
static func _hill(ci: CanvasItem, a: float) -> void:
	var p := PackedVector2Array()
	for i in 17:
		var x := lerpf(-26.0, 26.0, i / 16.0)
		p.append(Vector2(x, 16.0 - 26.0 * exp(-x * x / 180.0)))
	p.append(Vector2(26, 18))
	p.append(Vector2(-26, 18))
	patch(ci, p, Color(0.88, 0.92, 0.99), a, true, THREAD)
	thread(ci, PackedVector2Array([Vector2(0, -10), Vector2(0, -24)]), WOOD, 1.8, a)
	patch(ci, PackedVector2Array([Vector2(0, -24), Vector2(11, -20.5), Vector2(0, -17)]), RED, a, false)


## 風の筋（速さ）。確かめ用の札の「速さ」
static func _speed(ci: CanvasItem, a: float) -> void:
	sled_side(ci, Vector2(8, 10), 0.8, a)
	for i in 3:
		var y := -14.0 + i * 8.0
		var p := PackedVector2Array()
		for k in 9:
			var x := lerpf(-28.0, 2.0 - i * 4.0, k / 8.0)
			p.append(Vector2(x, y + sin(k * 0.9 + i) * 1.6))
		thread(ci, p, THREAD, 1.6, (1.0 - i * 0.2) * a)


## 砂時計（木の枠に、白い砂）。確かめ用の札の「fps」
static func _hourglass(ci: CanvasItem, a: float) -> void:
	patch(ci, PackedVector2Array([Vector2(-11, -18), Vector2(11, -18), Vector2(2, 0), Vector2(11, 18), Vector2(-11, 18), Vector2(-2, 0)]),
		Color(0.80, 0.90, 0.99), a, false)
	patch(ci, PackedVector2Array([Vector2(-6, -9), Vector2(6, -9), Vector2(1.2, -1), Vector2(-1.2, -1)]), PAPER, a, false)
	patch(ci, PackedVector2Array([Vector2(-1.2, 5), Vector2(1.2, 5), Vector2(9, 16), Vector2(-9, 16)]), PAPER, a, false)
	for y: float in [-21.0, 18.0]:
		patch(ci, rr(-15, y, 30, 4, 1.5), WOOD, a, false)
	for x: float in [-13.0, 13.0]:
		thread(ci, PackedVector2Array([Vector2(x, -18), Vector2(x, 18)]), WOOD, 2.0, a)


## 名札を外す（off: 結び目からほどけた名札が、弧を描いて手もとへ）・付ける（手もとの名札が、弧を描いて結び目へ）。
## 左上の木の棒が手すりの結び目
static func _tag_move(ci: CanvasItem, a: float, off: bool) -> void:
	thread(ci, PackedVector2Array([Vector2(-28, -22), Vector2(-4, -22)]), WOOD, 3.4, a)
	var c := Vector2(12, 10) if off else Vector2(-14, -2)
	var rot := 0.35 if off else 1.45
	if not off:   # 結び目から吊るした糸
		thread(ci, PackedVector2Array([Vector2(-16, -21), Vector2(-14, -12)]), RED, 1.6, a)
	var body := xf(PackedVector2Array([Vector2(-8, -6), Vector2(14, -6), Vector2(14, 6), Vector2(-8, 6), Vector2(-13, 0)]), rot, c)
	patch(ci, body, PAPER, a, true, THREAD)
	ci.draw_circle(_o + xf(PackedVector2Array([Vector2(-8, 0)]), rot, c)[0] * _s, 1.6 * _s, Color(THREAD, a))
	if off:
		arc_arrow(ci, Vector2(-4, 6), 18.0, -PI * 0.75, -PI * 0.15, RED, a, 2.2)
	else:
		arc_arrow(ci, Vector2(4, 4), 18.0, PI * 0.35, -PI * 0.55, RED, a, 2.2)


## 名札の束（めくる）: 少しずつずらした 3 枚の札と、めくる弧
static func _tag_stack(ci: CanvasItem, a: float) -> void:
	for k in range(2, -1, -1):
		var o := Vector2(5, -5) * k
		patch(ci, xf(rr(-20, -12, 36, 24, 4), -0.05 * k, o + Vector2(-4, 6)), PAPER.darkened(0.06 * k), a, k == 0, PAPER_EDGE)
	patch(ci, xf(rr(-14, -6, 22, 10, 2), 0.0, Vector2(-4, 6)), Color(0.74, 0.83, 0.95), a, false)
	arc_arrow(ci, Vector2(2, 2), 22.0, -PI * 0.95, -PI * 0.35, THREAD, a, 2.0)


## 小さなフェルトのカメラ（右を向く）
static func _camera(ci: CanvasItem, c: Vector2, a: float, sc := 1.0) -> void:
	patch(ci, xf(rr(-9, -6, 18, 12, 3), 0.0, c, sc), Color(0.34, 0.36, 0.42), a, false)
	patch(ci, xf(rr(-5, -9, 6, 4, 1.5), 0.0, c, sc), Color(0.34, 0.36, 0.42), a, false)
	patch(ci, xf(circ(Vector2(1, 0), 4.2, 14), 0.0, c, sc), Color(0.70, 0.84, 0.97), a, false)
	ci.draw_arc(_o + (c + Vector2(1, 0) * sc) * _s, 4.2 * sc * _s, 0, TAU, 16, Color(SHADOW, 0.5 * a), 1.0, true)
	ci.draw_circle(_o + (c + Vector2(-6, -3.5) * sc) * _s, 1.2 * sc * _s, Color(RED, a))


## 三人称のカメラの距離: 後ろ姿の人形と、前後に動くカメラ
static func _cam_dist(ci: CanvasItem, a: float, col: Color) -> void:
	doll(ci, Vector2(16, 26), col, "back", a, 0.95)
	_camera(ci, Vector2(-18, -8), a, 0.9)
	arrow(ci, Vector2(-14, 8), Vector2(2, 8), THREAD, a, 1.8)
	arrow(ci, Vector2(-14, 8), Vector2(-30, 8), THREAD, a, 1.8)


## 三人称の人形の画面の高さ: 画面の枠の中の後ろ姿の人形と、その目の高さの線を上下に動かす矢印
static func _cam_frame(ci: CanvasItem, a: float, col: Color) -> void:
	patch(ci, rr(-22, -26, 38, 52, 5), Color(0.80, 0.88, 0.98), a, false)          # 画面（空）
	patch(ci, rr(-22, 6, 38, 20, 4), SNOW, a, false)                                  # 雪
	doll(ci, Vector2(-3, 22), col, "back", a, 0.62)
	dashes(ci, PackedVector2Array([Vector2(-21, 6), Vector2(15, 6)]), RED, 1.4, 3.0, 2.0, a)   # 目の高さの線
	arrow(ci, Vector2(24, 4), Vector2(24, -22), THREAD, a, 1.8)
	arrow(ci, Vector2(24, 8), Vector2(24, 28), THREAD, a, 1.8)


static func _zoom(ci: CanvasItem, a: float) -> void:
	thread(ci, PackedVector2Array([Vector2(8, 8), Vector2(22, 22)]), WOOD, 5.0, a)
	patch(ci, circ(Vector2(-4, -4), 16, 22), Color(0.82, 0.90, 0.98), a, true, THREAD)
	ci.draw_arc(_o + Vector2(-4, -4) * _s, 16.0 * _s, 0, TAU, 28, Color(WOOD, a), 3.0 * _s, true)
	doll(ci, Vector2(-4, 8), RED, "stand", a, 0.55)


static func _view(ci: CanvasItem, a: float, col: Color) -> void:
	mitten(ci, Vector2(-22, 6), 0.3, col, a, true, 0.8)
	mitten(ci, Vector2(-10, 8), -0.3, col, a, true, 0.8)
	doll(ci, Vector2(18, 26), col, "back", a, 0.95)
	arc_arrow(ci, Vector2(0, -2), 14.0, PI * 1.15, PI * 1.85, THREAD, a, 1.8)
	arc_arrow(ci, Vector2(0, 6), 14.0, PI * 0.15, PI * 0.85, THREAD, a, 1.8)


static func _pip(ci: CanvasItem, a: float, off: bool) -> void:
	patch(ci, rr(-13, -24, 26, 46, 6), CAP, a, true, THREAD.lightened(0.3))
	patch(ci, circ(Vector2(0, -1), 10, 18), Color(0.70, 0.84, 0.97), a, false)
	ci.draw_arc(_o + Vector2(0, -1) * _s, 10.0 * _s, 0.1, PI - 0.1, 12, Color(SNOW, a), 4.0 * _s, true)
	ci.draw_circle(_o + Vector2(-7, -18) * _s, 1.6 * _s, Color(RED, a))
	if off:
		thread(ci, PackedVector2Array([Vector2(-22, 20), Vector2(22, -20)]), RED, 3.0, a)
	else:
		arc_arrow(ci, Vector2(0, -1), 20.0, PI * 0.2, PI * 0.8, THREAD, a, 1.8)


## Esc: 設定はボタン（縫い付ける四つ穴のボタン）
static func _button(ci: CanvasItem, a: float) -> void:
	patch(ci, circ(Vector2.ZERO, 20, 24), Color(0.62, 0.46, 0.36), a, false)
	ci.draw_arc(_o, 15.0 * _s, 0, TAU, 24, Color(SHADOW, 0.25 * a), 1.4 * _s, true)
	for p: Vector2 in [Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
		ci.draw_circle(_o + p * _s, 2.4 * _s, Color(0.25, 0.17, 0.13, a))
	thread(ci, PackedVector2Array([Vector2(-5, -5), Vector2(5, 5)]), RED, 1.6, a)
	thread(ci, PackedVector2Array([Vector2(5, -5), Vector2(-5, 5)]), RED, 1.6, a)


static func _mouse_move(ci: CanvasItem, a: float) -> void:
	mouse(ci, Vector2.ZERO, a)
	arrow(ci, Vector2(-14, 0), Vector2(-28, 0), THREAD, a, 1.8)
	arrow(ci, Vector2(14, 0), Vector2(28, 0), THREAD, a, 1.8)
	arrow(ci, Vector2(0, -19), Vector2(0, -30), THREAD, a, 1.8)
	arrow(ci, Vector2(0, 19), Vector2(0, 30), THREAD, a, 1.8)


## トラックパッドのピンチ: 板の上の 2 本の指先と、開く・閉じる斜めの矢印
static func _pinch(ci: CanvasItem, a: float) -> void:
	patch(ci, rr(-20, -16, 40, 32, 5), CAP, a, true, THREAD.lightened(0.3))
	for s: float in [-1.0, 1.0]:
		ci.draw_circle(_o + Vector2(5 * s, 4 * s) * _s, 4.2 * _s, Color(RED, a))
		arrow(ci, Vector2(9 * s, 7 * s), Vector2(17 * s, 13 * s), THREAD, a, 1.6)


## トラックパッドの二本指スクロール: 板の上の並んだ 2 本の指先と、上下の矢印
static func _pan(ci: CanvasItem, a: float) -> void:
	patch(ci, rr(-20, -16, 40, 32, 5), CAP, a, true, THREAD.lightened(0.3))
	for s: float in [-1.0, 1.0]:
		ci.draw_circle(_o + Vector2(5 * s - 4, 0) * _s, 4.2 * _s, Color(RED, a))
	arrow(ci, Vector2(10, -3), Vector2(10, -13), THREAD, a, 1.6)
	arrow(ci, Vector2(10, 3), Vector2(10, 13), THREAD, a, 1.6)


static func _mouse_wheel(ci: CanvasItem, a: float) -> void:
	mouse(ci, Vector2(-6, 0), a, "wheel")
	arrow(ci, Vector2(16, -4), Vector2(16, -22), THREAD, a, 1.8)
	arrow(ci, Vector2(16, 4), Vector2(16, 22), THREAD, a, 1.8)


## 後ろ向き（360° 映像が背中側を映しているしるし）: U の字に戻る矢印
static func _back(ci: CanvasItem, a: float) -> void:
	var p := PackedVector2Array([Vector2(-12, -10)])
	for i in 13:
		var t: float = -PI / 2.0 + PI * i / 12.0
		p.append(Vector2(6, 0) + Vector2(cos(t), sin(t)) * 10.0)
	p.append(Vector2(-8, 10))
	thread(ci, p, SNOW, 3.0, a)
	patch(ci, PackedVector2Array([Vector2(-17, 10), Vector2(-8, 3), Vector2(-8, 17)]), SNOW, a, false)
