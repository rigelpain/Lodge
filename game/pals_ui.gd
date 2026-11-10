extends CanvasLayer
## 頭・肩の小物とミニオンを買って付け替える画面（2 階の衣装掛けの横の売り台 pal_stall.gd の前で F）。文字は使わない。
##   緑のフェルトの板（衣装掛けの画面と同じ）。左に段の札が縦に 3 枚: 頭（人の形の頭に小鳥）・肩（肩に小鳥）・連れ（足もとに子狐）。
##   右に、その段の品物（pals.gd）の紙の札が 1 列に並び、札の中で品物がくるくる回る（12 コマ。ミニオンは座った姿）。
##   札の見え方はどの店も同じ（craft_icons.gd の foot・over。2026-11-10 代表「一般的なゲームのやりかたにしてほしい」）: 持っていない品物は札の下に値段のボタン
##   （足りなければ札がグレーで、選べない）、持っている品物は緑のチェック、いま付けている札は赤い糸の太い縁、まだ売っていない品は南京錠。
##   札を押すと: 持っていれば付ける（付けている札をもう一度押すと外す）。持っていなければ買って、すぐ付ける。
##   ボタンが足りないと札が震える。板の下のまんなかに財布（持っているボタン）。
##   A/D（←/→）で札を選び、W/S（↑/↓）で段を替え、Enter か Space で押したのと同じ。閉じるのは右上の × の縫い目か、F か Esc
## 買う・付けるは craft.gd の出来事 pal_buy・pal_wear（通信ではほかの人の画面でも、その人の小物とミニオンが替わる）
## 出す段は tabs で選ぶ（2026-11-02 代表「ミニオンは山師が育てているのを買う感じにしてほしい」）: 2 階の売り台は頭・肩、
## 山師（mountain_man.gd）は連れだけ。山師の画面では、段の札の上に lead_tab の札（山の道具の売り場へ戻る）を、下に tail_tabs の札
## （雪玉の柄の棚へ。2026-11-10 代表「山師でミニオン欄開いたら雪玉ステッチタブが消えちゃう」）を足し、板の色も替える。
## 札の並びは山師の売り場（mountain_ui.gd）と同じ: 道具・連れ・雪玉の柄

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
var tabs: Array = TABS       # 出す段（main.gd が決める）
var board_color := Color(0.36, 0.42, 0.33)   # 板のフェルトの色
var lead_tab := ""           # 段の札の上に足す札の絵（"" なら出さない）。押すと lead_pressed
signal lead_pressed
var tail_tabs: Array = []    # 段の札の下に足す札 [{draw: func(ci, rect, a), press: func()}]。押すとこの画面を閉じて press を呼ぶ
var _tail_rects: Array[Rect2] = []
var _hover_tail := -1
var tab := 0                 # いま開いている段（tabs の番号）
var _lead_rect := Rect2()
var _hover_lead := false
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
	return Pals.keys_of(tabs[tab])


func open(slot := "") -> void:
	if is_open or player == null or player.menu_open:
		return
	is_open = true
	tab = clampi(tab, 0, tabs.size() - 1)
	if slot in tabs:
		tab = tabs.find(slot)
	_sel = maxi(0, keys().find(craft.pal_worn(_who(), tabs[tab])))
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
	tab = posmod(i, tabs.size())
	_sel = maxi(0, keys().find(craft.pal_worn(_who(), tabs[tab])))
	_hover = -1
	_free_shots()
	_make_shots()


## 札を押した: 持っていれば付ける（付けている物なら外す）、持っていなければ買って付ける。できなければ false（札が震える）
func choose(i: int) -> bool:
	var ks := keys()
	if i < 0 or i >= ks.size() or craft == null:
		return false
	if not CraftIcons.pickable(card_state(i)):
		return false   # ボタンが足りない・ロックの札は選べない（押しても何も起きない）
	_sel = i
	var key: String = ks[i]
	var slot: String = tabs[tab]
	var ok := false
	if craft.pal_owned(_who(), key):
		var now: String = craft.pal_worn(_who(), slot)
		ok = craft.send({"kind": "pal_wear", "who": _who(), "slot": slot, "key": "" if now == key else key})
	else:
		ok = craft.send({"kind": "pal_buy", "who": _who(), "key": key})   # 買った音は audio.gd が出来事から一度だけ鳴らす
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
	# 左: 段の札（頭・肩・連れ）。lead_tab があれば、その上に
	_tabs.clear()
	var lead := 1 if lead_tab != "" else 0
	# 段の札の大きさ: 札が多ければ（山師の画面は 5 枚）板の高さに収まるように小さく
	var count := lead + tabs.size() + tail_tabs.size()
	var step := minf(100.0 * u, (bh - 40.0 * u) / maxf(count, 1))
	var ts0 := minf(84.0 * u, step - 10.0 * u)
	var ty0 := r.position.y + (70.0 * u if count * 100.0 * u <= bh - 90.0 * u else 20.0 * u)
	if lead_tab != "":
		var ts := ts0
		_lead_rect = Rect2(Vector2(r.position.x + 24.0 * u, ty0), Vector2(ts, ts))
		Icons.screen()
		Icons.patch(ci, Icons.rr(_lead_rect.position.x, _lead_rect.position.y, ts, ts, 12.0 * u), Icons.PAPER.darkened(0.12), 1.0 if _hover_lead else 0.75, true, Icons.PAPER_EDGE)
		Icons.icon(ci, lead_tab, _lead_rect.get_center(), ts * 0.8, 0.6)
	for i in tabs.size():
		var ts := ts0
		var tr := Rect2(Vector2(r.position.x + 24.0 * u, ty0 + (i + lead) * step), Vector2(ts, ts))
		_tabs.append(tr)
		var on := i == tab
		Icons.screen()
		Icons.patch(ci, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.12), 1.0 if on or i == _hover_tab else 0.75, true, Icons.PAPER_EDGE)
		Icons.icon(ci, "pal_" + tabs[i], tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
		if on:
			Icons.screen()
			Icons.dashes(ci, Icons.rr(tr.position.x - 5 * u, tr.position.y - 5 * u, ts + 10 * u, ts + 10 * u, 15.0 * u), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
	_tail_rects.clear()
	for k in tail_tabs.size():
		var ts := ts0
		var tr := Rect2(Vector2(r.position.x + 24.0 * u, ty0 + (tabs.size() + lead + k) * step), Vector2(ts, ts))
		_tail_rects.append(tr)
		Icons.screen()
		Icons.patch(ci, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER.darkened(0.12), 1.0 if k == _hover_tail else 0.75, true, Icons.PAPER_EDGE)
		(tail_tabs[k].draw as Callable).call(ci, tr.grow(-ts * 0.1), 0.6)
	# 札
	_cards.clear()
	var coins: int = craft.wallet(_who())
	var pad := 8.0 * u
	var asp := float(SHOT.x) / SHOT.y
	for i in ks.size():
		var key: String = ks[i]
		var lift := sin(_pop * PI) * 18.0 * u if key == _pop_key else 0.0
		var shake := sin(_shake * 40.0) * 8.0 * u * _shake if i == _shake_i else 0.0
		var cr := Rect2(r.position + Vector2(left + i * (cw + gap) + shake, 70.0 * u - lift), Vector2(cw, ch))
		_cards.append(Rect2(cr.position + Vector2(0, lift), cr.size))
		var price := Pals.price(key)
		var st := card_state(i)
		# 札と品物の絵（いつも見せる）。下に値段かチェック、付けていれば赤い糸の縁、ロックなら南京錠（どの店も同じ。craft_icons.gd の foot・over）
		Icons.paper_tag(ci, cr, 16.0 * u, u)
		var iw := minf(cw - pad * 2.0, (ch * 0.68) * asp)
		var ih := iw / asp
		if i < _shots.size():
			ci.draw_texture_rect((_shots[i][0] as SubViewport).get_texture(), Rect2(cr.position + Vector2((cw - iw) / 2.0, 12.0 * u), Vector2(iw, ih)), false)
		CraftIcons.foot(ci, st, cr.position + Vector2(cw / 2.0, ch - 28.0 * u), price, 9.0 * u, u)
		CraftIcons.over(ci, st, cr, CraftIcons.tag_pts(cr, 16.0 * u), u)
		if i == _sel or i == _hover and CraftIcons.pickable(st):
			var rim := Icons.rr(cr.position.x - 6.0 * u, cr.position.y - 6.0 * u, cr.size.x + 12.0 * u, cr.size.y + 12.0 * u, 10.0 * u)
			Icons.screen()
			Icons.dashes(ci, rim, Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _sel else 0.4, true)
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
	ci.draw_colored_polygon(pts, board_color, uv, Icons.felt())
	var inset := Rect2(r.position + Vector2(14, 14) * u, r.size - Vector2(28, 28) * u)
	Icons.dashes(ci, PackedVector2Array([inset.position, Vector2(inset.end.x, inset.position.y), inset.end, Vector2(inset.position.x, inset.end.y)]),
			Icons.CAP, 2.4 * u, 9.0 * u, 6.0 * u, 0.8, true)


func _hit(p: Vector2) -> int:
	for i in _cards.size():
		if _cards[i].has_point(p):
			return i
	return -1


func _hit_tail(p: Vector2) -> int:
	for i in _tail_rects.size():
		if _tail_rects[i].has_point(p):
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
		_hover_lead = lead_tab != "" and _lead_rect.has_point(e.position)
		_hover_tail = _hit_tail(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close()
		elif lead_tab != "" and _lead_rect.has_point(e.position):
			close()
			lead_pressed.emit()
		elif _hit_tail(e.position) >= 0:
			var press: Callable = tail_tabs[_hit_tail(e.position)].press
			close()
			press.call()
		elif _hit_tab(e.position) >= 0:
			set_tab(_hit_tab(e.position))
		else:
			var i := _hit(e.position)
			if i >= 0:
				choose(i)


## i 番目の札のようす（craft_icons.gd の card_state。どの店も同じ見え方。2026-11-10 代表）
func card_state(i: int) -> String:
	var ks := keys()
	if i < 0 or i >= ks.size():
		return ""
	var key: String = ks[i]
	return CraftIcons.card_state(preload("res://shop_locks.gd").locked("pal:" + key), craft.pal_owned(_who(), key), Pals.price(key) <= craft.wallet(_who()), true,
			craft.pal_worn(_who(), tabs[tab]) == key)
