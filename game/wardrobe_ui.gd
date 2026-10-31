extends CanvasLayer
## 人形を選び直す画面（2 階の衣装掛けの前で F）。文字は使わない。
##   緑のフェルトの板に、選べる人形（doll.gd の KINDS）の紙の札が 1 列に並ぶ。札の中で、その人形がくるくる回る（12 コマ）。
##   いま着ている人形の札には、赤い糸の結び目（あなたの印）。選んでいる札は少し持ち上がり、赤い糸で囲む。
##   札を押すか、A/D（←/→）で選んで Enter か Space で着替える。閉じるのは右上の × の縫い目か、F か Esc
## 着替えは craft.gd の出来事 doll（みんなに配られ、通信ではほかの人の画面でもその人の人形が作り直される）。
## 回る人形は、開いているあいだだけ札ごとに小さな画面（SubViewport）を作って撮る

const Doll := preload("res://doll.gd")
const Icons := preload("res://hud_icons.gd")

const SHOT := Vector2i(220, 300)   # 札の中の絵の大きさ (px)

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
	if is_open or player == null:
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
		var top: float = Doll.TOP[k]
		var spin := Node3D.new()
		vp.add_child(spin)
		var inst: Node3D = (load(Doll.SCENES[k]) as PackedScene).instantiate()
		var sc := 1.0 / top   # 背丈をそろえて、札いっぱいに
		inst.scale = Vector3.ONE * sc
		spin.add_child(inst)
		var cam := Camera3D.new()
		cam.fov = 30
		vp.add_child(cam)
		cam.look_at_from_position(Vector3(0, 0.6, 2.35), Vector3(0, 0.5, 0))
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
	var cw := minf(196.0 * u, (vs.x - 120.0 * u) / n - 14.0 * u)
	var ch := cw * 1.42
	var gap := 14.0 * u
	var bw := n * cw + (n - 1) * gap + 90.0 * u
	var bh := ch + 150.0 * u
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	_cards.clear()
	var worn: String = player.doll.kind
	for i in n:
		var lift := 14.0 * u if (i == _sel or i == _hover) else 0.0
		if Doll.KINDS[i] == worn:
			lift += sin(_pop * PI) * 18.0 * u
		var cr := Rect2(r.position + Vector2(45.0 * u + i * (cw + gap), 80.0 * u - lift), Vector2(cw, ch))
		_cards.append(Rect2(cr.position + Vector2(0, lift), cr.size))
		Icons.paper_tag(ci, cr, 16.0 * u, u)
		if i < _shots.size():
			var tex: Texture2D = (_shots[i][0] as SubViewport).get_texture()
			var pad := 8.0 * u
			var ir := Rect2(cr.position + Vector2(pad, pad + 6.0 * u), cr.size - Vector2(pad * 2.0, pad * 2.0 + 6.0 * u))
			var asp := float(SHOT.x) / SHOT.y
			var w := minf(ir.size.x, ir.size.y * asp)
			var h := w / asp
			ci.draw_texture_rect(tex, Rect2(ir.position + (ir.size - Vector2(w, h)) / 2.0, Vector2(w, h)), false)
		if i == _sel:   # 選んでいる札: 赤い糸で囲む
			var rim := Icons.rr(cr.position.x - 6.0 * u, cr.position.y - 6.0 * u, cr.size.x + 12.0 * u, cr.size.y + 12.0 * u, 10.0 * u)
			Icons.screen()
			Icons.dashes(ci, rim, Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0, true)
		if Doll.KINDS[i] == worn:   # いま着ている人形: 札の上の赤い糸の結び目（あなたの印）
			var c := cr.position + Vector2(cw / 2.0, -2.0 * u)
			ci.draw_circle(c, 9.0 * u, Icons.RED)
			ci.draw_arc(c, 9.0 * u, 0, TAU, 18, Icons.RED.darkened(0.4), 1.6 * u, true)
			for s in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(s * 6.0, 4.0) * u, c + Vector2(s * 14.0, 20.0) * u, Icons.RED, 3.0 * u, true)
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
