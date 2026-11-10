extends CanvasLayer
## 紙細工屋さん（paper_lady.gd）の前で F の、提灯と頭・肩の小物を買って付け替える画面。文字は使わない。
##   緑のフェルトの板（衣装掛けの画面と同じ）。左に段の札が縦に 3 枚: 提灯（帯のランタン）・頭（人の形の頭に小鳥）・肩（肩に小鳥）。
##   右に、その段の品物の紙の札が 5 枚ずつ並び（提灯は lantern.gd の LOOKS、小物は pals.gd）、札の中で品物がくるくる回る（12 コマ）。
##   提灯の札の中は夜の藍で、灯した提灯の光る紙は形ごとの揺らぎ方で明るさが変わる。
##   札の見え方はどの店も同じ（craft_icons.gd の foot・over。2026-11-10 代表「一般的なゲームのやりかたにしてほしい」）: 持っていない品物は札の下に値段のボタン
##   （足りなければ札がグレーで、選べない）、持っている品物は緑のチェック、いま身につけている札は赤い糸の太い縁、まだ売っていない品は南京錠。
##   札を押すと: 持っていれば身につける（つけている札をもう一度押すと外す）。持っていなければ買って、すぐ身につける。
##   ボタンが足りないと札が震える。板の下のまんなかに財布（持っているボタン）。
##   A/D（←/→）で札を選び、W/S（↑/↓）で段を替え、Enter か Space で押したのと同じ。閉じるのは右上の × の縫い目か、F か Esc
## 買う・つけるは craft.gd の出来事 lantern_buy・equip（提灯）と pal_buy・pal_wear（小物）。通信ではほかの人の画面でも、その人の物が替わる。
## 提灯の段の下に、色替えの段（2026-11-10 代表「なかったら紙細工師さんで色変え売って欲しい」）: いま提げているランタンを、キャラの色のパレット
##   （craft.gd の COLORS。山をめぐる仲間の服と同じ 12 色）の色で灯した札が 6 枚ずつ 2 段（布の見本帳の布 12 色と同じ並べ方）。札の左上に布の色。
##   押すと染める（染め代 craft.gd の LANTERN_DYE_PRICE、lantern_dye）。札の下に値段、いまの色の札はチェックと赤い糸の縁。左下の丸い布は形のもとの色に戻す（ただ）。
##   提げていなければ札は薄く、押すと震える
## 前は番台の横のランタン掛け（lantern_ui.gd）と 2 階の売り台（pals_ui.gd の頭・肩の段）だったものを、ここにまとめた（2026-11-02）

const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")
const Icons := preload("res://hud_icons.gd")
const CraftIcons := preload("res://craft_icons.gd")
const Doll := preload("res://doll.gd")

const SHOT := Vector2i(210, 240)   # 札の中の絵の大きさ (px)
const Craft := preload("res://craft.gd")
const TABS := ["lantern", "lantern_dye", "head", "shoulder"]
const TAB_ICONS := ["lamp", "dye", "pal_head", "pal_shoulder"]
const DYE_PER_ROW := 6       # 色替えの段の札の数（1 段）。布の見本帳の布 12 色と同じ 6 × 2
const PER_ROW := 5
const ROWS := 2              # 板の大きさは、いちばん多い段（提灯の 10 枚）でそろえる

var main: Node3D
var craft: Node
var player: Node3D
var is_open := false
var tab := 0                 # いま開いている段（TABS の番号）
var _asked := 0              # この画面から送って、まだ返ってきていない提灯の出来事の数（返ってきたら保存する）
var _view: Control
var _sel := 0
var _hover := -1
var _hover_tab := -1
var _hover_close := false
var _shots := []             # 札ごと [SubViewport, 回す節, 光る紙の素材, 揺らぎ方, ずらし]
var _cards: Array[Rect2] = []
var _tabs: Array[Rect2] = []
var _close_rect := Rect2()
var _bleach_rect := Rect2()  # 色替えの段の、もとの色に戻す丸い布
var _hover_bleach := false
var _pop := 0.0              # 身につけたときに札が跳ねる
var _pop_key := ""
var _shake := 0.0            # 足りないときに札が震える
var _shake_i := -1
var _frame := -1
var _dye_look := ""          # 色替えの段の札に灯している形
var _t := 0.0


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
	if craft:
		craft.happened.connect(_on_craft)


## この画面で買った・提げ替えた提灯が替わったら保存する（通信では、ホストが確かめて配り返したときに。
## つなぐ側は送った時点ではまだ替わっていない）。保存から戻すときの出来事では保存しない（_asked が 0）
func _on_craft(ev: Dictionary) -> void:
	if _asked <= 0 or int(ev.get("who", -1)) != _who() or player == null or not player.has_method("save_tag"):
		return
	if ev.kind in ["lantern_buy", "lantern_dye"] or (ev.kind == "equip" and ev.get("gear", "") == "lantern"):
		_asked -= 1
		if ev.kind == "lantern_dye" and TABS[tab] == "lantern_dye":   # 札の中のランタンは、もう染めた色（いまの色の印が移るだけ）
			_view.queue_redraw()
		player.save_tag()   # 次に起動しても同じ


func _who() -> int:
	return int(player.get("id"))


func keys() -> Array:
	match TABS[tab]:
		"lantern": return Lantern.LOOKS
		"lantern_dye": return Craft.lantern_palette()
	return Pals.keys_of(TABS[tab])


## いま提げているランタンの形（"" は提げていない）
func _lamp_look() -> String:
	return String(craft.lantern(_who()).get("look", ""))


## いま身につけている品物（"" はなし）。色替えの段では、いまのランタンの色（"" は形のもとの色）
func _worn() -> String:
	match TABS[tab]:
		"lantern": return _lamp_look()
		"lantern_dye": return String(craft.lantern(_who()).get("color", ""))
	return craft.pal_worn(_who(), TABS[tab])


func _owned(key: String) -> bool:
	match TABS[tab]:
		"lantern": return craft.lantern_index(_who(), key) >= 0
		"lantern_dye": return key == _worn()   # いまの色は払わない
	return craft.pal_owned(_who(), key)


func _price(key: String) -> int:
	match TABS[tab]:
		"lantern": return Lantern.price(key)
		"lantern_dye": return Craft.LANTERN_DYE_PRICE
	return Pals.price(key)


## 色替えの段: いま提げているランタンを色 hex（"" はもとの色）に染める。提げていない・同じ色・足りないなら false
func dye(hex: String) -> bool:
	var look := _lamp_look()
	var cost := 0 if hex == "" else Craft.LANTERN_DYE_PRICE
	if look == "" or hex == _worn() or craft.wallet(_who()) < cost:   # つなぐ側の send は、断られても true を返すので、先に見る
		return false
	_asked += 1
	var ok: bool = craft.send({"kind": "lantern_dye", "who": _who(), "look": look, "color": hex})
	if not ok:
		_asked = maxi(0, _asked - 1)
	return ok


func open(slot := "") -> void:
	if is_open or player == null or player.menu_open:
		return
	is_open = true
	if slot in TABS:
		tab = TABS.find(slot)
	_sel = maxi(0, keys().find(_worn()))
	_hover = -1
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.menu_open = true
	player.set("shopping", true)
	_make_shots()
	var hud = main.get("hud") if main else null
	if hud:
		hud.learn("paper_shop")   # 開けたら、F の案内はもう出さない
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
	i = posmod(i, TABS.size())
	if i == tab:
		return
	tab = i
	_sel = maxi(0, keys().find(_worn()))
	_hover = -1
	_free_shots()
	_make_shots()


## 札を押した: 持っていれば身につける（つけている物なら外す）、持っていなければ買って身につける。できなければ false（札が震える）
func choose(i: int) -> bool:
	var ks := keys()
	if i < 0 or i >= ks.size() or craft == null:
		return false
	if not CraftIcons.pickable(card_state(i)):
		return false   # ボタンが足りない・ロックの札は選べない（押しても何も起きない）
	_sel = i
	var key: String = ks[i]
	var ok := false   # 買った音は audio.gd が出来事から一度だけ鳴らす
	if TABS[tab] == "lantern_dye":
		ok = dye(key)
	elif TABS[tab] == "lantern":
		var have: int = craft.lantern_index(_who(), key)
		_asked += 1   # 一人のときは send の中で出来事が起きるので、送る前に数える
		if have >= 0:
			ok = craft.send({"kind": "equip", "who": _who(), "gear": "lantern", "index": -1 if _worn() == key else have})
		elif craft.wallet(_who()) >= Lantern.price(key):   # ボタンが足りなければ送らない（つなぐ側の send は、断られても true を返すので）
			ok = craft.send({"kind": "lantern_buy", "who": _who(), "look": key})
		if not ok:
			_asked = maxi(0, _asked - 1)
	else:
		var slot: String = TABS[tab]
		if craft.pal_owned(_who(), key):
			ok = craft.send({"kind": "pal_wear", "who": _who(), "slot": slot, "key": "" if _worn() == key else key})
		else:
			ok = craft.send({"kind": "pal_buy", "who": _who(), "key": key})
		if ok and player.has_method("save_tag"):
			player.save_tag()   # 次に起動しても同じ
	if ok:
		_pop = 1.0
		_pop_key = key
	else:
		_shake = 1.0
		_shake_i = i
	return ok


# ---------------------------------------------------------------- 札の中で回る品物

func _make_shots() -> void:
	var lantern: bool = TABS[tab] in ["lantern", "lantern_dye"]
	var tinting: bool = TABS[tab] == "lantern_dye"
	_dye_look = _lamp_look()
	for k in keys():
		var key: String = _dye_look if tinting else k   # 色替えの段: どの札も、いま提げている形（提げていなければ標準）を札の色で灯す
		var hex: String = k if tinting else ""
		if tinting and key == "":
			key = Lantern.LOOKS[0]
		var vp := SubViewport.new()
		vp.size = SHOT
		vp.transparent_bg = not lantern
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var env := Environment.new()
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		if lantern:   # 夜の藍（灯りの色が見えるように）
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.12, 0.14, 0.24)
			env.ambient_light_color = Color(0.62, 0.66, 0.82)
			env.ambient_light_energy = 0.45
			env.glow_enabled = true
			env.glow_intensity = 0.5
		else:
			env.background_mode = Environment.BG_CLEAR_COLOR
			env.ambient_light_color = Color(0.82, 0.86, 0.95)
			env.ambient_light_energy = 0.75
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-30, -35, 0) if lantern else Vector3(-35, -30, 0)
		sun.light_color = Color(1.0, 0.92, 0.82) if lantern else Color(1.0, 0.95, 0.86)
		sun.light_energy = 0.55 if lantern else 1.3
		vp.add_child(sun)
		var spin := Node3D.new()
		vp.add_child(spin)
		var mat: StandardMaterial3D = null
		var inst: Node3D
		if lantern:
			var made := Lantern.make_body(key, hex)
			inst = made[0]
			for m in made[1]:
				if mat == null:
					var src := (m as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
					mat = src.duplicate() if src else null
				if mat:
					(m as MeshInstance3D).set_surface_override_material(0, mat)
			var glow := OmniLight3D.new()   # 中の灯り（形の色）
			glow.light_color = Lantern.tint(key, hex)
			glow.light_energy = 0.9
			glow.omni_range = 0.6
			glow.position = Vector3(0, -0.15, 0)
			vp.add_child(glow)
		else:
			inst = Pals.scene(key).instantiate()
			Pals.paint(inst)
		spin.add_child(inst)
		var box := _bounds(inst)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(box.size.y, maxf(box.size.x, box.size.z)) * (1.25 if lantern else 1.3)
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		vp.add_child(cam)
		# 少し上から見下ろす（頭に腹ばいのモモンガのような平たい物も、背中が見える）
		var c := Vector3(0, box.get_center().y, 0)
		cam.look_at_from_position(c + (Vector3(0, 1.4, 6.0) if lantern else Vector3(0, 4.0, 6.0)), c)
		_shots.append([vp, spin, mat, String(Lantern.LOOK[key].style) if lantern else "", randf() * 100.0])


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		var p := m.get_parent()
		while p != n and p is Node3D:
			b = (p as Node3D).transform * b
			p = p.get_parent()
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
	if TABS[tab] == "lantern_dye" and _lamp_look() != _dye_look:   # 提げ替えた（ほかの画面や通信で）: 札を灯し直す
		_free_shots()
		_make_shots()
	_t += dt
	_pop = maxf(0.0, _pop - dt * 3.0)
	_shake = maxf(0.0, _shake - dt * 2.5)
	for s in _shots:
		if s[2]:
			(s[2] as StandardMaterial3D).emission_energy_multiplier = 1.6 * Lantern.flicker(s[3], _t, s[4])
	var f := Doll.frame_index()
	if f != _frame:   # 12 コマで回す。選んでいる札は速く
		_frame = f
		for i in _shots.size():
			var spin: Node3D = _shots[i][1]
			spin.rotation.y += 0.21 if i == _sel else 0.065
	_view.queue_redraw()


# ---------------------------------------------------------------- 描く

func _draw_on(ci: Control) -> void:
	var vs := ci.size
	var u := Icons.ui_scale(vs.y)
	var ks := keys()
	var gap := 16.0 * u
	var left := 120.0 * u   # 段の札のぶん、左を空ける
	var cw := minf(150.0 * u, (vs.x - 120.0 * u - left + gap) / PER_ROW - gap)
	var ch := minf(cw * 1.42, (vs.y - 260.0 * u - (ROWS - 1) * gap) / ROWS)
	cw = minf(cw, ch / 1.25)
	var bw := PER_ROW * cw + (PER_ROW - 1) * gap + left + 45.0 * u
	var bh := maxf(ROWS * ch + (ROWS - 1) * gap, TABS.size() * 100.0 * u) + 170.0 * u
	var r := Rect2((vs - Vector2(bw, bh)) / 2.0, Vector2(bw, bh))
	_board(ci, r, u)
	# 左: 段の札（提灯・頭・肩）
	_tabs.clear()
	for i in TABS.size():
		var ts := 84.0 * u
		var tr := Rect2(r.position + Vector2(24.0 * u, 60.0 * u + i * (ts + 16.0 * u)), Vector2(ts, ts))
		_tabs.append(tr)
		var on := i == tab
		Icons.screen()
		Icons.patch(ci, Icons.rr(tr.position.x, tr.position.y, ts, ts, 12.0 * u), Icons.PAPER if on else Icons.PAPER.darkened(0.12), 1.0 if on or i == _hover_tab else 0.75, true, Icons.PAPER_EDGE)
		Icons.icon(ci, TAB_ICONS[i], tr.get_center(), ts * 0.8, 1.0 if on else 0.6)
		if on:
			Icons.screen()
			Icons.dashes(ci, Icons.rr(tr.position.x - 5 * u, tr.position.y - 5 * u, ts + 10 * u, ts + 10 * u, 15.0 * u), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
	# 札（色替えの段は、同じ幅に 6 枚ずつ）
	_cards.clear()
	var worn := _worn()
	var coins: int = craft.wallet(_who())
	var pad := 8.0 * u
	var asp := float(SHOT.x) / SHOT.y
	var dyeing: bool = TABS[tab] == "lantern_dye"
	var per := DYE_PER_ROW if dyeing else PER_ROW
	var ccw := (PER_ROW * cw - (per - PER_ROW) * gap) / per if dyeing else cw
	var no_lamp := dyeing and _lamp_look() == ""   # 提げていなければ染められない（札は薄く）
	for i in ks.size():
		var key: String = ks[i]
		var lift := sin(_pop * PI) * 18.0 * u if key == _pop_key else 0.0
		var shake := sin(_shake * 40.0) * 8.0 * u * _shake if i == _shake_i else 0.0
		var cr := Rect2(r.position + Vector2(left + (i % per) * (ccw + gap) + shake, 60.0 * u + (i / per) * (ch + gap) - lift), Vector2(ccw, ch))
		_cards.append(Rect2(cr.position + Vector2(0, lift), cr.size))
		var price := _price(key)
		var st := card_state(i)
		# 札と品物の絵（いつも見せる）。下に値段かチェック、身につけていれば赤い糸の縁、ロックなら南京錠（どの店も同じ。craft_icons.gd の foot・over）。
		# 色替えの段も同じ（いまの色が「身につけている」）。提げていなければ染められないので、札は薄く、値段も印も出さない
		Icons.paper_tag(ci, cr, 14.0 * u, u)
		var ih := minf(ch - pad * 2.0 - 34.0 * u, (ccw - pad * 2.0) / asp)
		var iw := ih * asp
		if i < _shots.size():
			ci.draw_texture_rect((_shots[i][0] as SubViewport).get_texture(), Rect2(cr.position + Vector2((ccw - iw) / 2.0, 10.0 * u), Vector2(iw, ih)), false, Color(1, 1, 1, 0.4 if no_lamp else 1.0))
		if dyeing:   # 札の左上に、パレットの布の色（灯りは明るくそろえるので、元の色を見せる）
			var sw := Icons.circ(cr.position + Vector2(20.0, 22.0) * u, 12.0 * u, 16)
			Icons.screen()
			Icons.patch(ci, sw, Color(key), 0.45 if no_lamp else 1.0, true, Color(key).darkened(0.4))
		if not no_lamp:
			CraftIcons.foot(ci, st, cr.position + Vector2(ccw / 2.0, ch - 22.0 * u), price, 8.0 * u, u)
			CraftIcons.over(ci, st, cr, CraftIcons.tag_pts(cr, 14.0 * u), u)
		if i == _sel or i == _hover and CraftIcons.pickable(st):
			var rim := Icons.rr(cr.position.x - 6.0 * u, cr.position.y - 6.0 * u, cr.size.x + 12.0 * u, cr.size.y + 12.0 * u, 10.0 * u)
			Icons.screen()
			Icons.dashes(ci, rim, Icons.RED, 3.0 * u, 9.0 * u, 5.0 * u, 1.0 if i == _sel else 0.4, true)
	# 色替えの段の左下: 形のもとの色に戻す丸い布（ただ。布の見本帳の脱色と同じ）。もとの色なら赤い破線
	_bleach_rect = Rect2()
	if dyeing:
		var bc := Vector2(r.position.x + left + 40.0 * u, r.end.y - 50.0 * u)
		var br := 34.0 * u * (1.08 if _hover_bleach else 1.0)
		_bleach_rect = Rect2(bc - Vector2(br, br), Vector2(br, br) * 2.0)
		var base := Lantern.tint(_lamp_look() if not no_lamp else Lantern.LOOKS[0], "", true)
		Icons.screen()
		Icons.patch(ci, Icons.circ(bc, br, 24), base, 0.45 if no_lamp else 1.0, true, Icons.PAPER_EDGE)
		if worn == "" and not no_lamp:
			Icons.screen()
			Icons.dashes(ci, Icons.circ(bc, br + 6.0 * u, 24), Icons.RED, 3.0 * u, 8.0 * u, 5.0 * u, 1.0, true)
	# 下のまんなか: 財布（持っているボタン）
	Icons.screen()
	var py := r.end.y - 50.0 * u
	Icons.patch(ci, Icons.rr(r.position.x + bw / 2.0 - 170.0 * u, py - 32.0 * u, 340.0 * u, 64.0 * u, 14.0 * u), Icons.PAPER, 0.95, true, Icons.PAPER_EDGE)
	CraftIcons.price(ci, Vector2(r.position.x + bw / 2.0, py), coins, 10.0 * u)
	# 右上: 閉じる（× の縫い目）
	var xs := 46.0 * u
	var xc := Vector2(r.end.x - 32.0 * u, r.position.y + 32.0 * u)
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
		_hover_bleach = _bleach_rect.has_point(e.position)
		_hover_tab = _hit_tab(e.position)
		_hover_close = _close_rect.has_point(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _close_rect.has_point(e.position):
			close()
		elif _hit_tab(e.position) >= 0:
			set_tab(_hit_tab(e.position))
		elif _bleach_rect.has_point(e.position):
			if dye(""):
				_pop = 1.0
				_pop_key = ""
			else:
				_shake = 1.0
				_shake_i = -1
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
	var lock := ("lantern:" if TABS[tab] == "lantern" else "pal:") + key
	return CraftIcons.card_state(preload("res://shop_locks.gd").locked(lock), _owned(key), _price(key) <= craft.wallet(_who()), true, key == _worn())
