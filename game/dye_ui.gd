extends CanvasLayer
## 服を染める画面（2 階の染め桶の前で F）。文字は使わない（2026-11-01 代表「服の色変えもできるようにしたい」）。
##   左: 紙の札の中で、いま着ている人形が 12 コマでゆっくり回る。選んでいる色がその場で服に染まる（見本。まだ払っていない）。
##   右上: 服の布の見本（布が 2 つある人形は 2 枚）。押した布を染める。見本の右下の折り返しが、もとの色。
##   右: 色の輪（まわりで色合い、外ほど鮮やか）と、明るさの帯。色は自由に選べる（2026-11-01 代表「自由に選ぶ」）。
##       輪の下の小さな布は「もとの色に戻す」。
##   右下: 染める札（桶の絵と、染め代のボタン）。色ではなく 1 回ごとに染め代を払う（craft.gd の DYE_PRICE。何も変えていなければ押せない。
##       足りなければ値段が赤い）。染めると、みんなの画面でその人の人形が染まる（craft.gd の出来事 dye）
##   閉じるのは右上の × の縫い目か、F か Esc。Tab で布を替え、←→ で色合い、↑↓ で明るさ、Enter で染める

const Doll := preload("res://doll.gd")
const Outfit := preload("res://outfit.gd")
const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")

const SHOT := Vector2i(300, 420)   # 札の中の絵の大きさ (px)
const RINGS := 6             # 色の輪の、外へ向かう段の数
const SEGS := 48             # 色の輪の、まわりの分け数
const V_MIN := 0.12          # 明るさの帯のいちばん暗い所

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var _view: Control
var _kind := "kasa"
var _pick: Array = []        # 布ごとの、選んでいる色（Color か null = もとの色）
var _cloth := 0              # 染める布の番号
var _hsv := Vector3(0, 0.5, 0.5)   # いまの布の色（色合い・鮮やかさ・明るさ）
var _drag := ""              # "wheel" か "value" を引いている
var _shot: SubViewport
var _spin: Node3D
var _mat: ShaderMaterial
var _frame := -1
var _pop := 0.0              # 染めたときに札が跳ねる
var _hover := ""
# 描いたときに決まる所（画面の px）
var _wheel_c := Vector2.ZERO
var _wheel_r := 1.0
var _value_rect := Rect2()
var _swatches: Array[Rect2] = []
var _undo_rect := Rect2()
var _dye_rect := Rect2()
var _close_rect := Rect2()


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
	if is_open or player == null or player.menu_open or craft == null:
		return
	is_open = true
	_kind = player.doll.kind
	_pick = craft.outfit_of(int(player.get("id")), _kind)
	_pick.resize(Outfit.cloth_count(_kind))
	_cloth = 0
	_take_hsv()
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	_make_shot()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("dye")   # 開けたら、F の案内はもう出さない
	_view.queue_redraw()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_drag = ""
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	if _shot:
		Outfit.strip(_spin)   # 見本の材質を先に外す（outfit.gd の strip）
		_shot.queue_free()
		_shot = null
		_mat = null
	_view.queue_redraw()


## いま選んでいる布の色を、輪と帯の所に読む（もとの色なら、もとの色の所）
func _take_hsv() -> void:
	var c: Color = _pick[_cloth] if _pick[_cloth] is Color else Outfit.base_color(_kind, _cloth)
	_hsv = Vector3(c.h, c.s, c.v)


## 輪と帯の所から、いまの布の色を決める
func _set_from_hsv() -> void:
	_pick[_cloth] = Color.from_hsv(_hsv.x, _hsv.y, _hsv.z)
	_show_pick()


func _show_pick() -> void:
	if _mat:
		Outfit.set_params(_mat, _kind, _pick)


## 何か変えたか（変えていなければ染められない）
func _changed() -> bool:
	return craft.dye_colors(_kind, _pick) != craft.dye_colors(_kind, craft.outfit_of(int(player.get("id")), _kind))


func _can_pay() -> bool:
	return craft.wallet(int(player.get("id"))) >= craft.DYE_PRICE


## 染める（出来事を送る。染まるのは配られてから）
func dye() -> void:
	if not _changed() or not _can_pay():
		return
	if craft.send({"kind": "dye", "who": int(player.get("id")), "doll": _kind, "colors": craft.dye_colors(_kind, _pick)}):
		_pop = 1.0
		if player.has_method("save_tag"):
			player.save_tag()   # 次に起動しても同じ色


# ---------------------------------------------------------------- 札の中で回る人形（見本）

func _make_shot() -> void:
	_shot = SubViewport.new()
	_shot.size = SHOT
	_shot.transparent_bg = true
	_shot.own_world_3d = true
	_shot.msaa_3d = Viewport.MSAA_4X
	_shot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.86, 0.95)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_shot.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.3
	_shot.add_child(sun)
	_spin = Node3D.new()
	_shot.add_child(_spin)
	var inst: Node3D = (load(Doll.SCENES[_kind]) as PackedScene).instantiate()
	_spin.add_child(inst)
	_spin.rotation.y = 0.5
	_mat = Outfit.preview_material(inst)
	_show_pick()
	var h: float = Doll.TOP[_kind]
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = h * 1.12
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # 札の中のカメラは動かない
	_shot.add_child(cam)
	cam.look_at_from_position(Vector3(0, h * 0.5, 6.0), Vector3(0, h * 0.5, 0))


func _process(dt: float) -> void:
	if not is_open:
		return
	_pop = maxf(0.0, _pop - dt * 2.5)
	var f := Doll.frame_index()
	if f != _frame and _spin:   # 12 コマでゆっくり回す
		_frame = f
		_spin.rotation.y += 0.05
	_view.queue_redraw()


# ---------------------------------------------------------------- 描く

func _draw_on(ci: Control) -> void:
	var vs := ci.size
	var u := Icons.ui_scale(vs.y)
	var bw := minf(960.0 * u, vs.x - 60.0 * u)
	var bh := minf(600.0 * u, vs.y - 60.0 * u)
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	# 左: 見本の札
	var lift := sin(_pop * PI) * 16.0 * u
	var ch := bh - 70.0 * u
	var cw := ch * float(SHOT.x) / SHOT.y
	var card := Rect2(r.position + Vector2(36.0 * u, 36.0 * u - lift), Vector2(cw, ch))
	Icons.paper_tag(ci, card, 18.0 * u, u)
	if _shot:
		ci.draw_texture_rect(_shot.get_texture(), card.grow(-10.0 * u), false)
	# 右上: 布の見本
	var rx := card.end.x + 48.0 * u
	var n := _pick.size()
	var sw := 74.0 * u
	_swatches.clear()
	for i in n:
		var sr := Rect2(Vector2(rx + i * (sw + 26.0 * u), r.position.y + 40.0 * u), Vector2(sw, sw))
		_swatches.append(sr)
		_swatch(ci, sr, i, u)
	# 右: 色の輪と明るさの帯
	_wheel_r = minf(150.0 * u, (r.end.y - (r.position.y + 150.0 * u) - 40.0 * u) / 2.0)
	_wheel_c = Vector2(rx + _wheel_r + 4.0 * u, r.position.y + 150.0 * u + _wheel_r)
	_wheel(ci, u)
	_value_rect = Rect2(Vector2(_wheel_c.x + _wheel_r + 34.0 * u, _wheel_c.y - _wheel_r), Vector2(30.0 * u, _wheel_r * 2.0))
	_value(ci, u)
	# 輪の左下: もとの色に戻す小さな布
	var us := 44.0 * u
	_undo_rect = Rect2(Vector2(_wheel_c.x - _wheel_r - 6.0 * u, _wheel_c.y + _wheel_r - us + 6.0 * u), Vector2(us, us))
	_undo(ci, u)
	# 右下: 染める札（桶の絵と染め代）
	var dw := 150.0 * u
	var dh := 170.0 * u
	_dye_rect = Rect2(Vector2(r.end.x - dw - 40.0 * u, r.end.y - dh - 40.0 * u), Vector2(dw, dh))
	_dye_card(ci, u)
	# 右上: 閉じる（× の縫い目）
	var xs := 46.0 * u
	var xc := Vector2(r.end.x - 34.0 * u, r.position.y + 34.0 * u)
	_close_rect = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
	Icons.screen()
	Icons.patch(ci, Icons.circ(xc, xs * 0.5 * (1.08 if _hover == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
	Icons._o = xc
	Icons._s = xs / 64.0
	Icons.thread(ci, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)


## 布の見本: 選んだ色のフェルト。右下の角を折り返して、裏にもとの色。染める布は赤い糸で囲む
func _swatch(ci: CanvasItem, sr: Rect2, i: int, u: float) -> void:
	var base := Outfit.base_color(_kind, i)
	var c: Color = _pick[i] if _pick[i] is Color else base
	var fold := sr.size.x * 0.34
	Icons.screen()
	Icons.patch(ci, PackedVector2Array([sr.position, Vector2(sr.end.x, sr.position.y), Vector2(sr.end.x, sr.end.y - fold),
		Vector2(sr.end.x - fold, sr.end.y), Vector2(sr.position.x, sr.end.y)]), c, 1.0, true)
	Icons.patch(ci, PackedVector2Array([Vector2(sr.end.x, sr.end.y - fold), Vector2(sr.end.x - fold, sr.end.y - fold), Vector2(sr.end.x - fold, sr.end.y)]),
		base, 1.0, false)
	if i == _cloth or _hover == "swatch%d" % i:
		Icons.dashes(ci, Icons.rr(sr.position.x - 7.0 * u, sr.position.y - 7.0 * u, sr.size.x + 14.0 * u, sr.size.y + 14.0 * u, 8.0 * u),
			Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _cloth else 0.4, true)


## 色の輪: まわりで色合い、外ほど鮮やか（明るさは帯の値）。フェルトの毛羽を重ねる。いまの色の所に糸の輪
func _wheel(ci: CanvasItem, u: float) -> void:
	var felt := Icons.felt()
	Icons.screen()
	ci.draw_colored_polygon(Icons.circ(_wheel_c + Vector2(2, 3) * u, _wheel_r + 3.0 * u, 48), Color(Icons.SHADOW, 0.3))
	for ri in RINGS:
		var s0 := float(ri) / RINGS
		var s1 := float(ri + 1) / RINGS
		for k in SEGS:
			var a0 := TAU * k / SEGS
			var a1 := TAU * (k + 1) / SEGS
			var pts := PackedVector2Array([_polar(a0, s0), _polar(a0, s1), _polar(a1, s1), _polar(a1, s0)])
			var cols := PackedColorArray([_wheel_col(a0, s0), _wheel_col(a0, s1), _wheel_col(a1, s1), _wheel_col(a1, s0)])
			var uv := PackedVector2Array()
			for p in pts:
				uv.append(p / (40.0 * u))
			ci.draw_polygon(pts, cols, uv, felt)
	Icons.dashes(ci, Icons.circ(_wheel_c, _wheel_r - 5.0 * u, 48), Color(Icons.CAP, 0.7), 1.6 * u, 6.0 * u, 4.0 * u, 1.0, true)
	var at := _polar(_hsv.x * TAU, _hsv.y)
	ci.draw_circle(at, 11.0 * u, Color(Icons.SHADOW, 0.3))
	ci.draw_circle(at, 10.0 * u, Color.from_hsv(_hsv.x, _hsv.y, _hsv.z))
	ci.draw_arc(at, 10.0 * u, 0, TAU, 20, Icons.CAP, 3.0 * u, true)
	ci.draw_arc(at, 13.0 * u, 0, TAU, 20, Icons.THREAD, 1.6 * u, true)


func _polar(a: float, s: float) -> Vector2:
	return _wheel_c + Vector2(cos(a), -sin(a)) * s * _wheel_r


func _wheel_col(a: float, s: float) -> Color:
	return Color.from_hsv(a / TAU, s, _hsv.z)


## 明るさの帯: 上ほど明るい。いまの色合いと鮮やかさで。いまの明るさの所に赤い糸の結び目
func _value(ci: CanvasItem, u: float) -> void:
	var r := _value_rect
	Icons.screen()
	ci.draw_rect(Rect2(r.position + Vector2(2, 3) * u, r.size), Color(Icons.SHADOW, 0.3))
	var top := Color.from_hsv(_hsv.x, _hsv.y, 1.0)
	var bot := Color.from_hsv(_hsv.x, _hsv.y, V_MIN)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / (40.0 * u))
	ci.draw_polygon(pts, PackedColorArray([top, top, bot, bot]), uv, Icons.felt())
	ci.draw_rect(r, Color(Icons.THREAD, 0.6), false, 1.2 * u)
	var y := r.end.y - (_hsv.z - V_MIN) / (1.0 - V_MIN) * r.size.y
	Icons.dashes(ci, PackedVector2Array([Vector2(r.position.x - 8.0 * u, y), Vector2(r.end.x + 8.0 * u, y)]), Icons.RED, 3.0 * u, 7.0 * u, 3.0 * u, 1.0)
	ci.draw_circle(Vector2(r.end.x + 10.0 * u, y), 5.5 * u, Icons.RED)


## もとの色に戻す: もとの色の小さな布と、戻る矢印
func _undo(ci: CanvasItem, u: float) -> void:
	var sr := _undo_rect
	var a := 1.0 if _pick[_cloth] is Color else 0.4
	Icons.screen()
	var grow := 1.08 if _hover == "undo" and a > 0.5 else 1.0
	var c := sr.get_center()
	Icons.patch(ci, Icons.circ(c, sr.size.x * 0.5 * grow, 20), Outfit.base_color(_kind, _cloth), a, true)
	Icons.arc_arrow(ci, c, sr.size.x * 0.3, PI * 0.15, PI * 1.55, Icons.CAP, a, 3.0 * u)


## 染める札: 紙の札に、桶の絵（布はいま選んだ色）と染め代のボタン。押せないときは薄く、足りないときは値段が赤い
func _dye_card(ci: CanvasItem, u: float) -> void:
	var ok := _changed() and _can_pay()
	var a := 1.0 if ok else 0.45
	var r := _dye_rect
	if _hover == "dye" and ok:
		r = r.grow(4.0 * u)
	Icons.paper_tag(ci, r, 14.0 * u, u)
	var c: Color = _pick[_cloth] if _pick[_cloth] is Color else Outfit.base_color(_kind, _cloth)
	Icons.icon(ci, "dye", r.position + Vector2(r.size.x / 2.0, r.size.y * 0.38), 86.0 * u, a, c)
	Icons.screen()
	CraftIcons.price(ci, r.position + Vector2(r.size.x / 2.0, r.size.y * 0.8), craft.DYE_PRICE, 11.0 * u, a,
		Icons.RED if not _can_pay() else CraftIcons.COIN)
	if ok:
		Icons.dashes(ci, Icons.rr(r.position.x - 6.0 * u, r.position.y - 6.0 * u, r.size.x + 12.0 * u, r.size.y + 12.0 * u, 10.0 * u),
			Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 0.8, true)


## 濃い紫のフェルトの板と、縁のなみ縫い（衣装掛けの画面と同じ形。染め物の色）
func _board(ci: CanvasItem, r: Rect2, u: float) -> void:
	Icons.screen()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, Color(0.36, 0.30, 0.40), uv, Icons.felt())
	var inset := Rect2(r.position + Vector2(14, 14) * u, r.size - Vector2(28, 28) * u)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4 * u, 9.0 * u, 6.0 * u, 0.8, true)


# ---------------------------------------------------------------- 押す・引く

func _hit(p: Vector2) -> String:
	if _close_rect.has_point(p):
		return "close"
	if _dye_rect.has_point(p):
		return "dye"
	if _undo_rect.has_point(p):
		return "undo"
	for i in _swatches.size():
		if _swatches[i].has_point(p):
			return "swatch%d" % i
	if p.distance_to(_wheel_c) <= _wheel_r + 4.0:
		return "wheel"
	if _value_rect.grow(8.0).has_point(p):
		return "value"
	return ""


func _drag_to(p: Vector2) -> void:
	if _drag == "wheel":
		var d := p - _wheel_c
		_hsv.x = fposmod(atan2(-d.y, d.x) / TAU, 1.0)
		_hsv.y = clampf(d.length() / _wheel_r, 0.0, 1.0)
		_set_from_hsv()
	elif _drag == "value":
		_hsv.z = clampf(V_MIN + (_value_rect.end.y - p.y) / _value_rect.size.y * (1.0 - V_MIN), V_MIN, 1.0)
		_set_from_hsv()


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed:
		match e.physical_keycode:
			KEY_ESCAPE, KEY_F:
				if not e.echo:
					close()
			KEY_TAB:
				if not e.echo and _pick.size() > 1:
					_cloth = (_cloth + 1) % _pick.size()
					_take_hsv()
			KEY_A, KEY_LEFT:
				_hsv.x = fposmod(_hsv.x - 1.0 / SEGS, 1.0)
				_set_from_hsv()
			KEY_D, KEY_RIGHT:
				_hsv.x = fposmod(_hsv.x + 1.0 / SEGS, 1.0)
				_set_from_hsv()
			KEY_W, KEY_UP:
				_hsv.z = minf(1.0, _hsv.z + 0.05)
				_set_from_hsv()
			KEY_S, KEY_DOWN:
				_hsv.z = maxf(V_MIN, _hsv.z - 0.05)
				_set_from_hsv()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not e.echo:
					dye()
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if _drag != "":
			_drag_to(e.position)
		else:
			_hover = _hit(e.position)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if not e.pressed:
			_drag = ""
			return
		var h := _hit(e.position)
		match h:
			"close":
				close()
			"dye":
				dye()
			"undo":
				_pick[_cloth] = null
				_take_hsv()
				_show_pick()
			"wheel", "value":
				_drag = h
				_drag_to(e.position)
			_:
				if h.begins_with("swatch"):
					_cloth = int(h.trim_prefix("swatch"))
					_take_hsv()
