extends CanvasLayer
## 人形を選び直す画面（2 階の衣装掛けの前で F）。文字は使わない。
##   緑のフェルトの板に、選べる人形（doll.gd の KINDS）の紙の札が 1 列に並ぶ。札の中で、その人形がくるくる回る（12 コマ）。
##   人形はゲームの中と同じ縮尺で、どの札も同じ床の線に立つ（遠近のない撮り方なので、高さをそのまま比べられる）。
##   板の左に手芸の巻き尺（目盛りは 10 cm ごと、50 cm と 1 m は長く。数字はなし）。選んでいる人形の頭の高さに、
##   巻き尺から全部の札を横切る赤い糸を張る（2026-10-31 代表「キャラ選択では身長の差がわかるような表示にしてほしい」）。
##   いま着ている人形の札には、赤い糸の結び目（あなたの印）。選んでいる札は赤い糸で囲む（持ち上げると床の線がずれるので、持ち上げない）。
##   札を押すか、A/D（←/→）で選んで Enter か Space で着替える。閉じるのは右上の × の縫い目か、F か Esc
## 着替えは craft.gd の出来事 doll（みんなに配られ、通信ではほかの人の画面でもその人の人形が作り直される）。
## 回る人形は、開いているあいだだけ札ごとに小さな画面（SubViewport）を作って撮る

const Doll := preload("res://doll.gd")
const Icons := preload("res://hud_icons.gd")

const SHOT := Vector2i(220, 300)   # 札の中の絵の大きさ (px)
const VIEW_H := 2.1          # 札の絵の縦の広さ (m)。いちばん大きい巨人（1.69 m）が収まる
const FLOOR_PAD := 0.06      # 絵の下の縁から床までの高さ (m)
const TAPE := Color(0.93, 0.80, 0.42)   # 巻き尺の布の色（からし色）

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var _view: Control
var _sel := 0
var _hover := -1
var _hover_close := false
var _shots := []             # 人形ごと [SubViewport, 回す人形の節]
var _cards: Array[Rect2] = []
var _close_rect := Rect2()
var _pop := 0.0              # 着替えたときに札が跳ねる
var _frame := -1


class View:
	extends Control
	var ui

	func _draw() -> void:
		if ui.is_open:
			ui._draw_on(self)


func _ready() -> void:
	layer = 4
	_view = View.new()
	_view.ui = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)


func open() -> void:
	if is_open or player == null or player.menu_open:   # ほかの画面（装備・売り台など）が開いていれば開かない
		return
	is_open = true
	_sel = maxi(0, Doll.KINDS.find(player.doll.kind))
	_hover = -1
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	_make_shots()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("wardrobe")   # 開けたら、F の案内はもう出さない
	_view.queue_redraw()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	for s in _shots:
		(s[0] as Node).queue_free()
	_shots.clear()
	_view.queue_redraw()


## 選んだ人形に着替える（出来事を送る。着替えるのは配られてから）
func choose(i: int) -> void:
	var k: String = Doll.KINDS[i]
	_sel = i
	if k == player.doll.kind or craft == null:
		return
	if craft.send({"kind": "doll", "who": int(player.get("id")), "doll": k}):
		_pop = 1.0
		if player.has_method("save_tag"):
			player.save_tag()   # 次に起動しても同じ人形


# ---------------------------------------------------------------- 札の中で回る人形

func _make_shots() -> void:
	for k in Doll.KINDS:
		var vp := SubViewport.new()
		vp.size = SHOT
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.82, 0.86, 0.95)
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-30, -35, 0)
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 1.3
		vp.add_child(sun)
		var spin := Node3D.new()
		vp.add_child(spin)
		var inst: Node3D = (load(Doll.SCENES[k]) as PackedScene).instantiate()
		inst.scale = Vector3.ONE * float(Doll.SCALE[k])   # ゲームの中と同じ大きさ
		spin.add_child(inst)
		var cam := Camera3D.new()   # 遠近のない撮り方: 札の絵の高さが、そのまま身長に比例する
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = VIEW_H
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		vp.add_child(cam)
		cam.look_at_from_position(Vector3(0, VIEW_H / 2.0 - FLOOR_PAD, 6.0), Vector3(0, VIEW_H / 2.0 - FLOOR_PAD, 0))
		_shots.append([vp, spin])


func _process(dt: float) -> void:
	if not is_open:
		return
	_pop = maxf(0.0, _pop - dt * 3.0)
	var f := Doll.frame_index()
	if f != _frame:   # 12 コマで回す。選んでいる札は速く
		_frame = f
		for i in _shots.size():
			var spin: Node3D = _shots[i][1]
			spin.rotation.y += 0.22 if i == _sel else 0.07
	_view.queue_redraw()


# ---------------------------------------------------------------- 描く

func _draw_on(ci: Control) -> void:
	var vs := ci.size
	var u := Icons.ui_scale(vs.y)
	var n := Doll.KINDS.size()
	var gap := 14.0 * u
	var left := 92.0 * u   # 巻き尺のぶん、左を空ける
	var cw := minf(196.0 * u, (vs.x - 80.0 * u - left - 45.0 * u + gap) / n - gap)
	var ch := cw * 1.42
	var bw := n * cw + (n - 1) * gap + left + 45.0 * u
	var bh := ch + 150.0 * u
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	_cards.clear()
	var worn: String = player.doll.kind
	# 札の絵の所（どの札も同じ高さ）。高さ (m) → 画面の y は _y_of
	var pad := 8.0 * u
	var asp := float(SHOT.x) / SHOT.y
	var iw := minf(cw - pad * 2.0, (ch - pad * 2.0 - 6.0 * u) * asp)
	var ih := iw / asp
	var top_y := r.position.y + 80.0 * u + pad + 6.0 * u + (ch - pad * 2.0 - 6.0 * u - ih) / 2.0
	var y_of := func(m: float) -> float: return top_y + ih * (1.0 - (m + FLOOR_PAD) / VIEW_H)
	for i in n:
		var lift := sin(_pop * PI) * 18.0 * u if Doll.KINDS[i] == worn else 0.0   # 着替えたとき、札がぽんと跳ねる
		var cr := Rect2(r.position + Vector2(left + i * (cw + gap), 80.0 * u - lift), Vector2(cw, ch))
		_cards.append(Rect2(cr.position + Vector2(0, lift), cr.size))
		Icons.paper_tag(ci, cr, 16.0 * u, u)
		var ix := cr.position.x + (cw - iw) / 2.0
		# 札の中の床の線（雪の糸）
		ci.draw_line(Vector2(ix + 4.0 * u, y_of.call(0.0) - lift), Vector2(ix + iw - 4.0 * u, y_of.call(0.0) - lift), Color(Icons.THREAD, 0.35), 1.5 * u, true)
		if i < _shots.size():
			var tex: Texture2D = (_shots[i][0] as SubViewport).get_texture()
			ci.draw_texture_rect(tex, Rect2(Vector2(ix, top_y - lift), Vector2(iw, ih)), false)
		if i == _sel or i == _hover:   # 選んでいる札: 赤い糸で囲む（指しているだけの札は薄く）
			var rim := Icons.rr(cr.position.x - 6.0 * u, cr.position.y - 6.0 * u, cr.size.x + 12.0 * u, cr.size.y + 12.0 * u, 10.0 * u)
			Icons.screen()
			Icons.dashes(ci, rim, Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _sel else 0.4, true)
		if Doll.KINDS[i] == worn:   # いま着ている人形: 札の上の赤い糸の結び目（あなたの印）
			var c := cr.position + Vector2(cw / 2.0, -2.0 * u)
			ci.draw_circle(c, 9.0 * u, Icons.RED)
			ci.draw_arc(c, 9.0 * u, 0, TAU, 18, Icons.RED.darkened(0.4), 1.6 * u, true)
			for s in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(s * 6.0, 4.0) * u, c + Vector2(s * 14.0, 20.0) * u, Icons.RED, 3.0 * u, true)
	# 左: 巻き尺と、選んでいる人形の頭の高さの赤い糸
	var tape_x := r.position.x + 40.0 * u
	_tape(ci, tape_x, y_of, u)
	var k: String = Doll.KINDS[_sel]
	var hy: float = y_of.call(float(Doll.TOP[k]) * float(Doll.SCALE[k]))
	var x1 := r.position.x + left + n * (cw + gap) - gap
	Icons.screen()
	Icons.dashes(ci, PackedVector2Array([Vector2(tape_x + 14.0 * u, hy), Vector2(x1, hy)]), Icons.RED, 2.2 * u, 10.0 * u, 6.0 * u, 0.9)
	ci.draw_circle(Vector2(tape_x + 14.0 * u, hy), 5.0 * u, Icons.RED)   # 巻き尺に留めた糸の結び目
	# 右上: 閉じる（× の縫い目）
	var xs := 46.0 * u
	var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
	_close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
	Icons.screen()
	Icons.patch(ci, Icons.circ(xc, xs * 0.5 * (1.08 if _hover_close else 1.0), 20), Icons.PAPER, 1.0, false)
	Icons._o = xc
	Icons._s = xs / 64.0
	Icons.thread(ci, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)
	# 下: 衣装掛けの絵（何の画面かを絵で）
	Icons.icon(ci, "wardrobe", Vector2(r.position.x + bw / 2.0, r.end.y - 44.0 * u), 50.0 * u, 0.9)


## 縦に張った巻き尺: からし色の布の帯に、10 cm ごとの目盛り（50 cm と 1 m は長く太く、1 m ごとに赤い点）。床から 2 m まで
func _tape(ci: CanvasItem, x: float, y_of: Callable, u: float) -> void:
	var w := 26.0 * u
	var y0: float = y_of.call(-0.02)
	var y1: float = y_of.call(2.0)
	Icons.screen()
	ci.draw_rect(Rect2(x - w / 2.0 + 2.0 * u, y1 + 3.0 * u, w, y0 - y1), Color(Icons.SHADOW, 0.3))   # 影
	ci.draw_rect(Rect2(x - w / 2.0, y1, w, y0 - y1), TAPE)
	ci.draw_rect(Rect2(x - w / 2.0, y1, w, y0 - y1), Color(Icons.THREAD, 0.6), false, 1.2 * u)
	for i in 21:
		var y: float = y_of.call(i * 0.1)
		var big := i % 10 == 0
		var mid := i % 5 == 0
		var L := w * (0.85 if big else (0.6 if mid else 0.35))
		ci.draw_line(Vector2(x - w / 2.0, y), Vector2(x - w / 2.0 + L, y), Color(0.12, 0.10, 0.10), (2.2 if big or mid else 1.2) * u, true)
		if big and i > 0:
			ci.draw_circle(Vector2(x + w * 0.3, y - 6.0 * u), 3.2 * u, Icons.RED)
	# 床の所の金具（巻き尺の端の金属の爪）
	ci.draw_rect(Rect2(x - w / 2.0 - 2.0 * u, y0 - 2.0 * u, w + 4.0 * u, 5.0 * u), Color(0.62, 0.62, 0.66))


## 濃い緑のフェルトの板と、縁のなみ縫い（売り台と同じ）
func _board(ci: CanvasItem, r: Rect2, u: float) -> void:
	Icons.screen()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, Color(0.36, 0.42, 0.33), uv, Icons.felt())
	var inset := Rect2(r.position + Vector2(14, 14) * u, r.size - Vector2(28, 28) * u)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4 * u, 9.0 * u, 6.0 * u, 0.8, true)


func _hit(p: Vector2) -> int:
	for i in _cards.size():
		if _cards[i].has_point(p):
			return i
	return -1


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE, KEY_F:
				close()
			KEY_A, KEY_LEFT:
				_sel = posmod(_sel - 1, Doll.KINDS.size())
			KEY_D, KEY_RIGHT:
				_sel = posmod(_sel + 1, Doll.KINDS.size())
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				choose(_sel)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
		_hover_close = _close_rect.has_point(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close()
		else:
			var i := _hit(e.position)
			if i >= 0:
				choose(i)
