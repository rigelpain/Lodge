extends CanvasLayer
## ソリの見本帳の画面（見本帳の前で F）。文字は使わない（2026-11-06 代表「見本帖＋自由な色にしてほしい」）。
## 今あるソリの色と滑りあとの縫い目を替える。新しいソリを縫うのは、これまでどおりミシン。
##   開いた帳面の左の面:
##     上の列: 替えるソリ（自分がオーナーのソリ。米袋・雪の上・畳んで持っている・立てかけ台）。乗っている・つかまれている・動いているソリは薄く、選べない
##     中: 選んだ色で回るソリと、色の輪・明るさの帯（dye_ui.gd と同じ color_wheel.gd。自由な色）
##     下: 布 12 色、元の色に戻す丸い布（ただ。戻す矢印）、染める札（桶の絵と、払うボタン）
##   右の面: 縫い目 24 柄。選んだ色の糸で描く。持っている柄は針の印、買える柄はボタンの値段。買える・買えないの見え方はどの店も同じ
##     （craft_icons.gd の card_state。2026-11-10 代表）: ボタンが足りない柄はグレーで選べない、まだ売っていない柄は麻ひもの包み
##   閉じるのは右上の × の縫い目か、F か Esc。Tab でソリを替え、←→ で色合い、↑↓ で明るさ、Q・E で縫い目、Backspace で元の色、Enter で染める
## 確かめは craft.gd の出来事 sled_dye・stitch_buy・sled_stitch（持ち主だけ・ホストが判定）

const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const ColorWheel := preload("res://color_wheel.gd")
const Fabrics := preload("res://fabrics.gd")
const Stitches := preload("res://stitches.gd")
const Tags := preload("res://sled_tags.gd")
const Props := preload("res://props.gd")
const Sled := preload("res://sled.gd")
const Doll := preload("res://doll.gd")

## 布 12 色（見本帳の形 design/sled-custom/build_book.py と同じ並び。売り子の布 6 色を含む）
const SWATCHES := ["D2553A", "E08A3C", "D8A43E", "8FA84A", "3F6B4A", "2F7F8F", "6F8FB8", "34477E", "7A4A6E", "C97A8A", "EFE6D2", "4A4038"]
const BOARD := Vector2(1500, 860)
const ROW := 6               # 替えるソリの列に並べる数（多ければ選んでいる所までずらす）
const SHOT := Vector2i(620, 460)

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var _view: Control
var _key: Dictionary = {}    # 替えるソリ（stitch_targets の値: {id}・{slot}・{sack}）
var _pick: Variant = null    # 選んでいる色（Color）。null は今の色のまま
var _hsv := Vector3(0, 0.5, 0.5)
var _stitch := ""            # 選んでいる縫い目
var _drag := ""
var _hover := ""
var _pop := 0.0
var _frame := -1
var _shot: SubViewport
var _spin: Node3D
var _model: Node3D
var _model_key := ""
var _recolored := false
# 描いたときに決まる所（画面の px）
var _rects := {}
var _wheel_c := Vector2.ZERO
var _wheel_r := 1.0


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


func _who() -> int:
	return int(player.get("id"))


func open() -> void:
	if is_open or player == null or player.menu_open or craft == null:
		return
	is_open = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	if not craft.happened.is_connected(_on_craft):
		craft.happened.connect(_on_craft)
	_make_shot()
	_key = _first_key()
	_take_target()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("sled_book")   # 開けたら、F の案内はもう出さない
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
		_shot.queue_free()
		_shot = null
		_model = null
		_model_key = ""
	_view.queue_redraw()


# ---------------------------------------------------------------- 替えるソリ

## 替えられるソリの並び: [key, 絵 {sled, fabric, folded?}, 柄の名前]。craft_ui.gd の持ち物の画面と同じ
func targets() -> Array:
	return main.craft_ui.stitch_targets()


func _target() -> Array:
	for t in targets():
		if t[0] == _key:
			return t
	return []


## いま使っているソリ（替えられない）
func _busy(key: Dictionary) -> bool:
	if key.has("id"):
		return craft.sled_busy(craft.sleds.get(int(key.id)))
	if key.has("sack"):
		return craft.sled_busy(craft._sack_out_at(_who(), int(key.sack)))
	return false


func _racked(key: Dictionary) -> bool:
	return key.has("id") and craft.racked.has(int(key.id))


## 開いたときのソリ: 雪の上か台の自分のソリ、なければ畳んだソリ、なければ米袋。使っているソリは後まわし
func _first_key() -> Dictionary:
	var list := targets()
	for want in ["id", "slot", "sack"]:
		for t in list:
			if (t[0] as Dictionary).has(want) and not _busy(t[0]):
				return t[0]
	return list[0][0] if not list.is_empty() else {}


## 選んだソリの、いまの色の名前（"" は既定）
func _fabric_now() -> String:
	var t := _target()
	return String((t[1] as Dictionary).get("fabric", "")) if not t.is_empty() else ""


func _kind_now() -> String:
	var t := _target()
	return String((t[1] as Dictionary).get("sled", "mid")) if not t.is_empty() else "mid"


func _color_of(kind: String, fabric: String) -> Color:
	return Fabrics.color(fabric) if fabric != "" else Sled.KINDS[kind].color


## 選んだソリの今の色と柄を、画面の選びに写す
func _take_target() -> void:
	var t := _target()
	_pick = null
	_stitch = String(t[2]) if not t.is_empty() else ""
	var c := _color_of(_kind_now(), _fabric_now())
	_hsv = Vector3(c.h, c.s, clampf(c.v, ColorWheel.V_MIN, 1.0))
	_show_model()


func select(key: Dictionary) -> void:
	if _busy(key):
		return
	_key = key
	_take_target()


func _step_target(d: int) -> void:
	var list := targets()
	if list.is_empty():
		return
	var at := 0
	for i in list.size():
		if list[i][0] == _key:
			at = i
	for k in list.size():
		var j := posmod(at + d * (k + 1), list.size())
		if not _busy(list[j][0]):
			select(list[j][0])
			return


func _on_craft(ev: Dictionary) -> void:
	if not is_open or int(ev.get("who", -1)) != _who():
		return
	if ev.kind in ["sled_dye", "sled_stitch"]:   # 確かめられた: 選びを今の姿に戻す（つなぐ側は少し遅れて届く）
		_take_target()
	if _target().is_empty():   # 畳む・しまうで相手が消えた
		_key = _first_key()
		_take_target()


# ---------------------------------------------------------------- 色・柄を選ぶ

## いま選んでいる色（選んでいなければ今の色）
func picked_color() -> Color:
	return _pick if _pick is Color else _color_of(_kind_now(), _fabric_now())


func _color_changed() -> bool:
	return _pick is Color and not (_pick as Color).is_equal_approx(_color_of(_kind_now(), _fabric_now()))


func _stitch_changed() -> bool:
	var t := _target()
	return not t.is_empty() and _stitch != String(t[2])


func _stitch_owned(nm: String) -> bool:
	return craft.stitch_can_use(_who(), nm)


## 払う分: 染め代（色を替えるとき）と、買っていない柄の値段（その柄を選んでいるとき）
func price_now() -> int:
	var n := 0
	if _color_changed():
		n += craft.sled_dye_price(_kind_now())
	if _stitch_changed() and not _stitch_owned(_stitch):
		n += Stitches.price(_stitch)
	return n


func _coins() -> int:
	return int(craft.wallets.get(_who(), 0))


func can_apply() -> bool:
	return (_color_changed() or _stitch_changed()) and not _busy(_key) and price_now() <= _coins()


func pick_color(c: Color) -> void:
	_pick = c
	_hsv = Vector3(c.h, c.s, clampf(c.v, ColorWheel.V_MIN, 1.0))
	_show_model()


func _set_from_hsv() -> void:
	_pick = Color.from_hsv(_hsv.x, _hsv.y, _hsv.z)
	_show_model()


func pick_stitch(nm: String) -> void:
	if Stitches.has(nm) and CraftIcons.pickable(stitch_state(nm)):   # ボタンが足りない・ロックの柄は選べない
		_stitch = nm


## 柄 nm の札のようす（craft_icons.gd の card_state。どの店も同じ見え方。2026-11-10 代表）
func stitch_state(nm: String) -> String:
	return CraftIcons.card_state(preload("res://shop_locks.gd").locked("stitch:" + nm), _stitch_owned(nm), Stitches.price(nm) <= _coins())


func _step_stitch(d: int) -> void:
	var names: Array = Stitches.standard() + Stitches.for_sale()
	var at := names.find(_stitch)
	for k in names.size():   # 選べない柄は飛ばす
		at = posmod(at + d, names.size())
		if CraftIcons.pickable(stitch_state(names[at])):
			pick_stitch(names[at])
			return


## 決める: 買っていない柄を買い、柄を替え、色を染める（ホストが順に確かめる）
func apply() -> bool:
	if not can_apply():
		return false
	var who := _who()
	var ok := true
	# 先に読んでおく（確かめられると _on_craft が選びを今の姿に戻す）
	var nm := _stitch
	var dye_hex: String = Fabrics.dyed_name(_pick) if _color_changed() else ""
	var key := _key.duplicate()
	if _stitch_changed():
		if not _stitch_owned(nm):
			ok = craft.send({"kind": "stitch_buy", "who": who, "stitch": nm})
		if ok:
			var ev := {"kind": "sled_stitch", "who": who, "stitch": nm}
			ev.merge(key)
			ok = craft.send(ev)
	if ok and dye_hex != "":
		var ev := {"kind": "sled_dye", "who": who, "color": dye_hex}
		ev.merge(key)
		ok = craft.send(ev)
	if ok:
		_pop = 1.0
		if player.has_method("save_tag"):
			player.save_tag()
	return ok


## 元の色に戻す（ただ）
func bleach() -> bool:
	if not Fabrics.is_dyed(_fabric_now()) or _busy(_key):
		return false
	var ev := {"kind": "sled_dye", "who": _who(), "color": ""}
	ev.merge(_key)
	var ok: bool = craft.send(ev)
	if ok and player.has_method("save_tag"):
		player.save_tag()
	return ok


# ---------------------------------------------------------------- 回るソリの見本

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
	env.ambient_light_energy = 0.5   # 布の見本と同じ色に見えるよう、染めの画面の人形より暗め
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_shot.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 0.8
	_shot.add_child(sun)
	_spin = Node3D.new()
	_spin.rotation.y = 0.7
	_shot.add_child(_spin)
	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_shot.add_child(cam)


## 見本のソリを、いま選んでいる色で。もとの色は染め直さない（米袋の印刷などを元の絵のまま見せる）
func _show_model() -> void:
	if _shot == null:
		return
	var kind := _kind_now()
	var fabric := _fabric_now()
	var plain := not (_pick is Color) and fabric == ""
	if _model == null or _model_key != kind or (plain and _recolored):
		if _model:
			_spin.remove_child(_model)
			_model.queue_free()
		_model = Props.make("res://props/sled_%s.glb" % kind)
		_spin.add_child(_model)
		_model_key = kind
		_recolored = false
		var box: Vector3 = Sled.KINDS[kind].box
		var cam: Camera3D = _shot.get_node("Cam")
		cam.size = box.z * 1.25
		cam.look_at_from_position(Vector3(0, box.z * 0.75, box.z * 1.1), Vector3(0, box.y * 0.5, 0))
	if not plain:
		var k: Dictionary = Sled.KINDS[kind]
		Props.recolor(_model, k.color, picked_color(), k.get("whole", false))
		_recolored = true


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
	var k := minf(Icons.ui_scale(vs.y), minf((vs.x - 40.0) / BOARD.x, (vs.y - 40.0) / BOARD.y))
	var o := (vs - BOARD * k) / 2.0
	var R := func(x: float, y: float, w: float, h: float) -> Rect2:
		return Rect2(o + Vector2(x, y) * k, Vector2(w, h) * k)
	_rects.clear()
	_felt_board(ci, R.call(0, 0, BOARD.x, BOARD.y), k)
	var lp: Rect2 = R.call(36, 36, 704, 788)
	var rp: Rect2 = R.call(760, 36, 704, 788)
	Icons.screen()
	Icons.paper_tag(ci, lp, 16.0 * k, k)
	Icons.screen()
	Icons.paper_tag(ci, rp, 16.0 * k, k)
	Icons.screen()
	for j in 5:   # 綴じの輪
		ci.draw_arc(o + Vector2(750, 130 + j * 150) * k, 30.0 * k, 0.0, TAU, 28, Color(0.82, 0.66, 0.30), 7.0 * k, true)
	# ---- 左の面
	_draw_targets(ci, o, k)
	# 回るソリ
	var lift := sin(_pop * PI) * 14.0 * k
	if _shot:
		ci.draw_texture_rect(_shot.get_texture(), Rect2(o + Vector2(52, 176 - lift / k) * k, Vector2(330, 245) * k), false)
	# 色の輪と帯
	_wheel_r = 122.0 * k
	_wheel_c = o + Vector2(530, 296) * k
	ColorWheel.wheel(ci, _wheel_c, _wheel_r, _hsv, k)
	var vr: Rect2 = R.call(672, 174, 28, 244)
	_rects["value"] = vr
	ColorWheel.value_bar(ci, vr, _hsv, k)
	# 布 12 色
	var now := picked_color()
	for i in SWATCHES.size():
		var s: Rect2 = R.call(60 + (i % 6) * 78.0, 440 + (i / 6) * 80.0, 66, 68)
		var c := Color(SWATCHES[i])
		_rects["swatch%d" % i] = s
		_pinked(ci, s.grow(2.0 * k if _hover == "swatch%d" % i else 0.0), c, k)
		if c.is_equal_approx(now):
			_dashes(ci, s, k)
	# 元の色に戻す丸い布と、染める札
	var dyed := Fabrics.is_dyed(_fabric_now())
	var a := 1.0 if dyed and not _busy(_key) else 0.3
	var br: Rect2 = R.call(60, 620, 76, 76)
	_rects["bleach"] = br
	var base := String((_target_base()))
	Icons.screen()
	var grow := 1.08 if _hover == "bleach" and a > 0.5 else 1.0
	Icons.patch(ci, Icons.circ(br.get_center(), br.size.x * 0.5 * grow, 18), _color_of(_kind_now(), base), a, true)
	Icons.arc_arrow(ci, br.get_center(), br.size.x * 0.3, PI * 0.15, PI * 1.55, Icons.CAP, a, 3.0 * k)
	# 今の色 > 選んだ色
	var c0 := _color_of(_kind_now(), _fabric_now())
	var row := br.get_center() + Vector2(100, 0) * k
	Icons.screen()
	Icons.patch(ci, Icons.circ(row, 26.0 * k, 16), c0, 1.0, true)
	Icons._o = Vector2.ZERO
	Icons._s = 1.0
	Icons.thread(ci, PackedVector2Array([row + Vector2(36, -12) * k, row + Vector2(50, 0) * k, row + Vector2(36, 12) * k]), Icons.THREAD, 3.2 * k, 1.0)
	Icons.screen()
	Icons.patch(ci, Icons.circ(row + Vector2(86, 0) * k, 26.0 * k, 16), now, 1.0, true)
	_draw_apply(ci, R.call(476, 606, 226, 196), k)
	# ---- 右の面
	_draw_stitches(ci, o, k)
	# × の縫い目
	var xc := o + Vector2(BOARD.x - 34, 34) * k
	var xs := 46.0 * k
	_rects["close"] = Rect2(xc - Vector2(xs, xs) / 2.0, Vector2(xs, xs))
	Icons.screen()
	Icons.patch(ci, Icons.circ(xc, xs * 0.5 * (1.08 if _hover == "close" else 1.0), 20), Icons.PAPER, 1.0, false)
	Icons._o = xc
	Icons._s = xs / 64.0
	Icons.thread(ci, PackedVector2Array([Vector2(-12, -12), Vector2(12, 12)]), Icons.THREAD, 4.0, 1.0)
	Icons.thread(ci, PackedVector2Array([Vector2(12, -12), Vector2(-12, 12)]), Icons.THREAD, 4.0, 1.0)


## 元の布の名前（戻す丸い布の色）
func _target_base() -> String:
	if _key.has("id"):
		var s = craft.sleds.get(int(_key.id))
		return String(s.base_fabric) if is_instance_valid(s) else ""
	if _key.has("slot"):
		var b: Array = craft.bag(_who())
		var i := int(_key.slot)
		return String(b[i].get("base", "")) if i < b.size() else ""
	if _key.has("sack"):
		var l: Array = craft.sacks.get(_who(), [])
		var i := int(_key.sack)
		return String(l[i].get("base", "")) if i < l.size() else ""
	return ""


func _draw_targets(ci: Control, o: Vector2, k: float) -> void:
	var list := targets()
	var at := 0
	for i in list.size():
		if list[i][0] == _key:
			at = i
	var from := clampi(at - ROW / 2, 0, maxi(0, list.size() - ROW))
	var x0 := 92.0
	for j in mini(ROW, list.size()):
		var i := from + j
		var t: Array = list[i]
		var look: Dictionary = t[1]
		var picked: bool = t[0] == _key
		var busy := _busy(t[0])
		var a := 0.3 if busy else 1.0
		var r := Rect2(o + Vector2(x0 + j * 92.0, 56 - (6.0 if picked else 0.0)) * k, Vector2(84, 104) * k)
		_rects["target%d" % i] = r
		Icons.screen()
		Icons.patch(ci, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 9.0 * k), Icons.CAP, a, true, Icons.PAPER_EDGE)
		var tw := r.size.x * 0.96
		ci.draw_texture_rect(Tags.turntable(look.sled, look.get("fabric", "")), Rect2(r.get_center() - Vector2(tw, tw) / 2.0, Vector2(tw, tw)), false, Color(1, 1, 1, a))
		Icons.screen()
		var corner := r.position + Vector2(16, 16) * k
		if look.get("folded", false):   # 畳んだソリ: 包みの色の角
			Icons.patch(ci, Icons.xf(Icons.rr(-7, -7, 14, 14, 2), PI / 4, corner, k), _color_of(look.sled, look.get("fabric", "")), a, false)
		elif _racked(t[0]):   # 立てかけ台のソリ
			Icons.icon(ci, "rack_out", corner + Vector2(4, 4) * k, 34.0 * k, a)
		if picked:
			_dashes(ci, r, k)
	# ずらす糸の矢印
	for d in [-1, 1]:
		var c := o + Vector2(x0 - 24.0 if d < 0 else x0 + ROW * 92.0 + 16.0, 108) * k
		var more: bool = from > 0 if d < 0 else from + ROW < list.size()
		_rects["step%d" % d] = Rect2(c - Vector2(22, 34) * k, Vector2(44, 68) * k)
		Icons._o = Vector2.ZERO
		Icons._s = 1.0
		Icons.thread(ci, PackedVector2Array([c + Vector2(-d * 9, -16) * k, c + Vector2(d * 9, 0) * k, c + Vector2(-d * 9, 16) * k]), Icons.THREAD, 4.0 * k, 1.0 if more else 0.25)


func _draw_apply(ci: Control, r: Rect2, k: float) -> void:
	var ok := can_apply()
	var changed := _color_changed() or _stitch_changed()
	var a := 1.0 if ok else 0.45
	if _hover == "apply" and ok:
		r = r.grow(4.0 * k)
	_rects["apply"] = r
	Icons.screen()
	Icons.paper_tag(ci, r, 14.0 * k, k)
	Icons.icon(ci, "dye", r.position + Vector2(r.size.x * 0.32, r.size.y * 0.32), 92.0 * k, a, picked_color())
	Icons.screen()
	var th := Rect2(r.position + Vector2(r.size.x * 0.58, r.size.y * 0.12), Vector2(r.size.x * 0.34, r.size.y * 0.42))
	ci.draw_rect(th, Color(0.82, 0.86, 0.94, a))
	Stitches.draw_swatch(ci, _stitch, th, picked_color(), a)
	var pay := price_now()
	if changed and pay > 0:
		var short := pay > _coins()
		var many: bool = craft.pieces(pay).size() > 6   # ボタンが多ければ小さく（札からはみ出さないように）
		CraftIcons.price(ci, r.position + Vector2(r.size.x / 2.0, r.size.y * 0.76), pay, (9.0 if many else 13.0) * k, a, Icons.RED if short else CraftIcons.COIN)
	if ok:
		_dashes(ci, r, k)


func _draw_stitches(ci: Control, o: Vector2, k: float) -> void:
	var names: Array = Stitches.standard() + Stitches.for_sale()
	var col := picked_color()
	var cur := String(_target()[2]) if not _target().is_empty() else ""
	for i in names.size():
		var nm: String = names[i]
		var r := Rect2(o + Vector2(778 + (i % 6) * 112.0, 54 + (i / 6) * 190.0) * k, Vector2(104, 178) * k)
		var owned := _stitch_owned(nm)
		var price: int = Stitches.price(nm)
		var st := stitch_state(nm)
		if _hover == "stitch%d" % i and CraftIcons.pickable(st):
			r.position.y -= 3.0 * k
		_rects["stitch%d" % i] = r
		if st == "locked":   # まだ売っていない: 麻ひもの包み（どの店も同じ。craft_icons.gd）
			CraftIcons.wrap_card(ci, r, k)
			continue
		if not owned:   # まだ買っていない柄: 小包（上に値段、荷札に選んだ色の糸の柄）。足りなければグレー（craft_icons.gd）
			CraftIcons.parcel(ci, r, price, st == "money", func(c2: CanvasItem, tr: Rect2) -> void:
				c2.draw_rect(tr, Color(0.82, 0.86, 0.94))
				Stitches.draw_swatch(c2, nm, tr, col), k)
		else:
			if price > 0:   # 買ったあと: 札のうしろに開いた包み紙
				CraftIcons.unwrapped(ci, r, k)
			Icons.screen()
			Icons.patch(ci, Icons.rr(r.position.x, r.position.y, r.size.x, r.size.y, 9.0 * k), Icons.CAP, 1.0, true, Icons.PAPER_EDGE)
			var snow := Rect2(r.position + Vector2(5, 5) * k, Vector2(r.size.x - 10.0 * k, r.size.y - 50.0 * k))
			ci.draw_rect(snow, Color(0.82, 0.86, 0.94))
			Stitches.draw_swatch(ci, nm, snow, col)
			Icons.screen()   # 持っている柄: 針の印
			Icons.icon(ci, "needle", r.position + Vector2(r.size.x / 2.0, r.size.y - 22.0 * k), 30.0 * k, 1.0)
		if nm == cur:   # いまそのソリの柄: 藍の糸の縁
			Icons.screen()
			Icons.dashes(ci, Icons.rr(r.position.x + 2 * k, r.position.y + 2 * k, r.size.x - 4 * k, r.size.y - 4 * k, 8.0 * k), Icons.THREAD, 2.0 * k, 5.0 * k, 3.0 * k, 0.9, true)
		if nm == _stitch:
			_dashes(ci, r, k)


func _felt_board(ci: CanvasItem, r: Rect2, k: float) -> void:
	Icons.screen()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p / 40.0)
	ci.draw_colored_polygon(pts, Color(0.20, 0.25, 0.42), uv, Icons.felt())
	var inset := r.grow(-14.0 * k)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4 * k, 9.0 * k, 6.0 * k, 0.8, true)


func _dashes(ci: CanvasItem, r: Rect2, k: float) -> void:
	Icons.screen()
	var g := r.grow(5.0 * k)
	Icons.dashes(ci, Icons.rr(g.position.x, g.position.y, g.size.x, g.size.y, 8.0 * k), Icons.RED, 3.0 * k, 8.0 * k, 4.0 * k, 1.0, true)


## ぎざぎざに切った布
func _pinked(ci: CanvasItem, r: Rect2, col: Color, k: float) -> void:
	var pts := PackedVector2Array()
	var z := 5.0 * k
	var n := maxi(2, int(r.size.x / (10.0 * k)))
	var m := maxi(2, int(r.size.y / (10.0 * k)))
	for i in n * 2:
		pts.append(r.position + Vector2(r.size.x * i / (n * 2.0), 0.0 if i % 2 == 0 else z))
	for i in m * 2:
		pts.append(Vector2(r.end.x - (0.0 if i % 2 == 0 else z), r.position.y + r.size.y * i / (m * 2.0)))
	for i in n * 2:
		pts.append(r.end - Vector2(r.size.x * i / (n * 2.0), 0.0 if i % 2 == 0 else z))
	for i in m * 2:
		pts.append(Vector2(r.position.x + (0.0 if i % 2 == 0 else z), r.end.y - r.size.y * i / (m * 2.0)))
	Icons.screen()
	Icons.patch(ci, pts, col, 1.0, false)


# ---------------------------------------------------------------- 押す・引く

func _hit(p: Vector2) -> String:
	if p.distance_to(_wheel_c) <= _wheel_r + 4.0:
		return "wheel"
	for key in _rects:
		if (_rects[key] as Rect2).has_point(p):
			return key
	return ""


func _drag_to(p: Vector2) -> void:
	if _drag == "wheel":
		_hsv = ColorWheel.pick_wheel(_wheel_c, _wheel_r, p, _hsv)
		_set_from_hsv()
	elif _drag == "value":
		_hsv = ColorWheel.pick_value(_rects["value"], p, _hsv)
		_set_from_hsv()


func _press(h: String, p: Vector2) -> void:
	match h:
		"close":
			close()
		"apply":
			apply()
		"bleach":
			bleach()
		"wheel", "value":
			_drag = h
			_drag_to(p)
		"step-1":
			_step_target(-1)
		"step1":
			_step_target(1)
		_:
			if h.begins_with("swatch"):
				pick_color(Color(SWATCHES[int(h.trim_prefix("swatch"))]))
			elif h.begins_with("stitch"):
				var names: Array = Stitches.standard() + Stitches.for_sale()
				var nm: String = names[int(h.trim_prefix("stitch"))]
				if _stitch_owned(nm) or Stitches.price(nm) <= _coins():
					pick_stitch(nm)
			elif h.begins_with("target"):
				var list := targets()
				var i := int(h.trim_prefix("target"))
				if i < list.size():
					select(list[i][0])


func _input(e: InputEvent) -> void:
	if not is_open:
		return
	if e is InputEventKey and e.pressed:
		match e.physical_keycode:
			KEY_ESCAPE, KEY_F:
				if not e.echo:
					close()
			KEY_TAB:
				if not e.echo:
					_step_target(-1 if e.shift_pressed else 1)
			KEY_A, KEY_LEFT:
				_hsv.x = fposmod(_hsv.x - 1.0 / ColorWheel.SEGS, 1.0)
				_set_from_hsv()
			KEY_D, KEY_RIGHT:
				_hsv.x = fposmod(_hsv.x + 1.0 / ColorWheel.SEGS, 1.0)
				_set_from_hsv()
			KEY_W, KEY_UP:
				_hsv.z = minf(1.0, _hsv.z + 0.05)
				_set_from_hsv()
			KEY_S, KEY_DOWN:
				_hsv.z = maxf(ColorWheel.V_MIN, _hsv.z - 0.05)
				_set_from_hsv()
			KEY_Q:
				if not e.echo:
					_step_stitch(-1)
			KEY_E:
				if not e.echo:
					_step_stitch(1)
			KEY_BACKSPACE, KEY_DELETE:
				if not e.echo:
					bleach()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if not e.echo:
					apply()
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
		_press(_hit(e.position), e.position)
