extends CanvasLayer
## 頭・肩の小物とミニオンを買って付け替える画面（2 階の衣装掛けの横の売り台 pal_stall.gd の前で F）。文字は使わない。
##   緑のフェルトの板（衣装掛けの画面と同じ）。左に段の札が縦に 3 枚: 頭（人の形の頭に小鳥）・肩（肩に小鳥）・連れ（足もとに子狐）。
##   右に、その段の品物（pals.gd）の紙の札が 1 列に並び、札の中で品物がくるくる回る（12 コマ。ミニオンは座った姿）。
##   持っていない品物の札の下には値段のボタン、持っている品物は値段なし。いま付けている札には赤い糸の結び目（あなたの印）。
##   札を押すと: 持っていれば付ける（付けている札をもう一度押すと外す）。持っていなければ買って、すぐ付ける。
##   ボタンが足りないと札が震える。板の下のまんなかに財布（持っているボタン）。
##   A/D（←/→）で札を選び、W/S（↑/↓）で段を替え、Enter か Space で押したのと同じ。閉じるのは右上の × の縫い目か、F か Esc
## 買う・付けるは craft.gd の出来事 pal_buy・pal_wear（通信ではほかの人の画面でも、その人の小物とミニオンが替わる）

const Pals := preload("res://pals.gd")
const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Doll := preload("res://doll.gd")

const SHOT := Vector2i(220, 240)   # 札の中の絵の大きさ (px)
const TABS := ["head", "shoulder", "pet"]

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var tab := 0                 # いま開いている段（TABS の番号）
var _view: Control
var _sel := 0
var _hover := -1
var _hover_tab := -1
var _hover_close := false
var _shots := []             # 札ごと [SubViewport, 回す節]
var _cards: Array[Rect2] = []
var _tabs: Array[Rect2] = []
var _close_rect := Rect2()
var _pop := 0.0              # 付けたときに札が跳ねる
var _pop_key := ""
var _shake := 0.0            # 足りないときに札が震える
var _shake_i := -1
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


func _who() -> int:
	return int(player.get("id"))


func keys() -> Array:
	return Pals.keys_of(TABS[tab])


func open(slot := "") -> void:
	if is_open or player == null or player.menu_open:
		return
	is_open = true
	if slot in TABS:
		tab = TABS.find(slot)
	_sel = maxi(0, keys().find(craft.pal_worn(_who(), TABS[tab])))
	_hover = -1
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	_make_shots()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("pals")   # 開けたら、F の案内はもう出さない
	_view.queue_redraw()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.menu_open = false
	player.set("shopping", false)
	_free_shots()
	_view.queue_redraw()


func set_tab(i: int) -> void:
	if i == tab:
		return
	tab = posmod(i, TABS.size())
	_sel = maxi(0, keys().find(craft.pal_worn(_who(), TABS[tab])))
	_hover = -1
	_free_shots()
	_make_shots()


## 札を押した: 持っていれば付ける（付けている物なら外す）、持っていなければ買って付ける。できなければ false（札が震える）
func choose(i: int) -> bool:
	var ks := keys()
	if i < 0 or i >= ks.size() or craft == null:
		return false
	_sel = i
	var key: String = ks[i]
	var slot: String = TABS[tab]
	var ok := false
	if craft.pal_owned(_who(), key):
		var now: String = craft.pal_worn(_who(), slot)
		ok = craft.send({"kind": "pal_wear", "who": _who(), "slot": slot, "key": "" if now == key else key})
	else:
		ok = craft.send({"kind": "pal_buy", "who": _who(), "key": key})
		if ok:
			var au = main.get_node_or_null("Audio") if main else null
			if au and au.has_method("coin"):
				au.coin("brass")
	if ok:
		_pop = 1.0
		_pop_key = key
		if player.has_method("save_tag"):
			player.save_tag()   # 次に起動しても同じ
	else:
		_shake = 1.0
		_shake_i = i
	return ok


# ---------------------------------------------------------------- 札の中で回る品物

func _make_shots() -> void:
	for key in keys():
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
		sun.rotation_degrees = Vector3(-35, -30, 0)
		sun.light_color = Color(1.0, 0.95, 0.86)
		sun.light_energy = 1.3
		vp.add_child(sun)
		var spin := Node3D.new()
		vp.add_child(spin)
		var inst: Node3D = Pals.scene(key).instantiate()
		Pals.paint(inst)
		spin.add_child(inst)
		var pet := Pals.PET.has(key)
		if pet:
			for c in inst.get_children():
				(c as Node3D).visible = Pals.part_name(c) == "sit"
		# 品物の大きさに合わせて撮る（座ったミニオン・小物の外形の箱）
		var box := _bounds(inst)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(box.size.y, maxf(box.size.x, box.size.z)) * 1.3
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		vp.add_child(cam)
		# 少し上から見下ろす（頭に腹ばいのモモンガのような平たい物も、背中が見える）
		var c := Vector3(0, box.get_center().y, 0)
		cam.look_at_from_position(c + Vector3(0, 4.0, 6.0), c)
		_shots.append([vp, spin])


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var b := m.get_global_transform() * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _free_shots() -> void:
	for s in _shots:
		(s[0] as Node).queue_free()
	_shots.clear()


func _process(dt: float) -> void:
	if not is_open:
		return
	_pop = maxf(0.0, _pop - dt * 3.0)
	_shake = maxf(0.0, _shake - dt * 2.5)
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
	var ks := keys()
	var n := 7   # 札の幅は、いちばん多い段（7 枚）でそろえる
	var gap := 14.0 * u
	var left := 120.0 * u   # 段の札のぶん、左を空ける
	var cw := minf(176.0 * u, (vs.x - 80.0 * u - left - 45.0 * u + gap) / n - gap)
	var ch := cw * 1.36
	var bw := n * cw + (n - 1) * gap + left + 45.0 * u
	var bh := ch + 190.0 * u
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	# 左: 段の札（頭・肩・連れ）
	_tabs.clear()
	for i in TABS.size():
		var ts := 84.0 * u
		var tr := Rect2(r.position + Vector2(24.0 * u, 70.0 * u + i * (ts + 16.0 * u)), Vector2(ts, ts))
		_tabs.append(tr)
		var on := i == tab
		Icons.screen()
		Icons.patch(ci, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.12), 1.0 if on or i == _hover_tab else 0.75, true, Icons.PAPER_EDGE)
		Icons.icon(ci, "pal_" + TABS[i], tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
		if on:
			Icons.screen()
			Icons.dashes(ci, Icons.rr(tr.position.x - 5 * u, tr.position.y - 5 * u, ts + 10 * u, ts + 10 * u, 15.0 * u), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
	# 札
	_cards.clear()
	var worn: String = craft.pal_worn(_who(), TABS[tab])
	var coins: int = craft.wallet(_who())
	var pad := 8.0 * u
	var asp := float(SHOT.x) / SHOT.y
	for i in ks.size():
		var key: String = ks[i]
		var lift := sin(_pop * PI) * 18.0 * u if key == _pop_key else 0.0
		var shake := sin(_shake * 40.0) * 8.0 * u * _shake if i == _shake_i else 0.0
		var cr := Rect2(r.position + Vector2(left + i * (cw + gap) + shake, 70.0 * u - lift), Vector2(cw, ch))
		_cards.append(Rect2(cr.position + Vector2(0, lift), cr.size))
		var owned: bool = craft.pal_owned(_who(), key)
		var price := Pals.price(key)
		Icons.paper_tag(ci, cr, 16.0 * u, u)
		var iw := minf(cw - pad * 2.0, (ch * 0.72) * asp)
		var ih := iw / asp
		if i < _shots.size():
			var tex: Texture2D = (_shots[i][0] as SubViewport).get_texture()
			ci.draw_texture_rect(tex, Rect2(cr.position + Vector2((cw - iw) / 2.0, 14.0 * u), Vector2(iw, ih)), false, Color(1, 1, 1, 1.0 if owned or price <= coins else 0.55))
		if not owned:   # 値段（足りなければ薄く）
			CraftIcons.price(ci, cr.position + Vector2(cw / 2.0, ch - 26.0 * u), price, 10.0 * u, 1.0 if price <= coins else 0.45)
		if i == _sel or i == _hover:
			var rim := Icons.rr(cr.position.x - 6.0 * u, cr.position.y - 6.0 * u, cr.size.x + 12.0 * u, cr.size.y + 12.0 * u, 10.0 * u)
			Icons.screen()
			Icons.dashes(ci, rim, Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _sel else 0.4, true)
		if key == worn:   # いま付けている: 札の上の赤い糸の結び目（あなたの印）
			var c := cr.position + Vector2(cw / 2.0, -2.0 * u)
			ci.draw_circle(c, 9.0 * u, Icons.RED)
			ci.draw_arc(c, 9.0 * u, 0, TAU, 18, Icons.RED.darkened(0.4), 1.6 * u, true)
			for s in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(s * 6.0, 4.0) * u, c + Vector2(s * 14.0, 20.0) * u, Icons.RED, 3.0 * u, true)
	# 下のまんなか: 財布（持っているボタン）
	Icons.screen()
	var py := r.end.y - 52.0 * u
	Icons.patch(ci, Icons.rr(r.position.x + bw / 2.0 - 170.0 * u, py - 34.0 * u, 340.0 * u, 68.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
	CraftIcons.price(ci, Vector2(r.position.x + bw / 2.0, py), coins, 10.0 * u)
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


## 濃い緑のフェルトの板と、縁のなみ縫い（衣装掛けの画面と同じ）
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


func _hit_tab(p: Vector2) -> int:
	for i in _tabs.size():
		if _tabs[i].has_point(p):
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
				_sel = posmod(_sel - 1, keys().size())
			KEY_D, KEY_RIGHT:
				_sel = posmod(_sel + 1, keys().size())
			KEY_W, KEY_UP:
				set_tab(tab - 1)
			KEY_S, KEY_DOWN:
				set_tab(tab + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				choose(_sel)
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		_hover = _hit(e.position)
		_hover_tab = _hit_tab(e.position)
		_hover_close = _close_rect.has_point(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close()
		elif _hit_tab(e.position) >= 0:
			set_tab(_hit_tab(e.position))
		else:
			var i := _hit(e.position)
			if i >= 0:
				choose(i)
