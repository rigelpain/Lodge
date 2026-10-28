extends CanvasLayer
## 画面の表示（HUD）。文字を使わず、アイコン・矢印・形で伝える。決まりと場面ごとの絵は design/hud.md。
##   左下: ソリの札（紙のタグ）。丘の断面の上をソリの印が動き、登った分だけ赤い糸が伸びる。下に、いまソリにいる人の形と、
##         押している人の数だけの糸の矢印（人が加わるほど矢印が増え、速く流れる）
##   物の上: 近づいたときだけ、キーの形と動きの絵のワッペン。3 回したら（覚えたら）もう出さない
##   画面の下のまんなか: つかんでいる・紐を持っている・乗っているときの手引き。ほかの人のそばでは身ぶりの手引き
##   Esc: 設定の画面の左に、すべてのキーと絵を並べた札
##   確かめ用: --hud-debug か設定の「確かめ用の数字」で、左上にこれまでの文字（人数・高さ・速さ・fps）
## 絵は hud_icons.gd。ミシン（main.sewing）とエモート（main.emotes）は、あればその案内も出す。

const Icons := preload("res://hud_icons.gd")
const Player := preload("res://player.gd")
const LEARNED := 3            # この回数したら、その案内はもう出さない
const TAG_NEAR := 30.0        # ソリからこの距離より近いと札を出す (m)
const MEET_R := 5.0           # ほかの人がこの距離に来たら身ぶりの案内
const MEET_SHOW := 6.0        # 身ぶりの案内を出す長さ (s)
const PROFILE_R := 62.0       # 札の丘の断面の右端（頂上からの水平の距離, m）

var main: Node3D
var debug_on := false
var hints_on := true
var uses := {}                # 案内 → した回数（そのプレイの間だけ）

var _view: Control
var _debug: Label
var _tag_a := 0.0
var _flow := 0.0
var _n_push := 0
var _push_hold := 0.0
var _people: Array = []       # [人, 形（"stand" / "sit"）, 色, 力をかけているか]
var _pop := {}                # 人 → 跳ねの残り（1→0）
var _chev_pop := 0.0
var _hints := {}              # 案内 → {keys, icon, world, scr, a, on, bottom}
var _order: Array = []        # いまのコマの、画面の下の案内の並び
var _prev_mode := -1
var _work_t := 0.0            # 押す・引く・体重をかけた長さ（1 回に数えるまで）
var _meet_t := 0.0
var _meet_n := 0
var _meeting := false
var _still_t := 0.0
var _seen_back := false


func _ready() -> void:
	layer = 3
	_view = View.new()
	_view.hud = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_view)
	_debug = Label.new()
	_debug.position = Vector2(16, 12)
	_debug.add_theme_font_size_override("font_size", 16)
	_debug.add_theme_color_override("font_color", Color(0.12, 0.12, 0.12))
	_debug.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.7))
	_debug.add_theme_constant_override("outline_size", 3)
	add_child(_debug)


## 画面の高さに合わせた大きさ（1080 で 1）
func ui() -> float:
	return clampf(_view.size.y / 1080.0, 0.6, 2.0)


func learn(id: String, n := 1) -> void:
	uses[id] = uses.get(id, 0) + n


func known(id: String) -> bool:
	return uses.get(id, 0) >= LEARNED


func _input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			learn("gesture")
		return
	match e.physical_keycode:
		KEY_R: learn("return")
		KEY_T: learn("sew")
		KEY_Q, KEY_G, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_4, KEY_B: learn("gesture")


func _process(dt: float) -> void:
	if main == null or main.sled == null:
		return
	var sled: RigidBody3D = main.sled
	var p: CharacterBody3D = main.player
	_update_people(dt, sled, p)
	var want_tag := 1.0
	if p:
		var near: bool = p.global_position.distance_to(sled.global_position) < TAG_NEAR or p.mode != Player.Mode.WALK
		want_tag = 1.0 if near else 0.0
	_tag_a = move_toward(_tag_a, want_tag, dt * 2.5)
	for h in _hints.values():
		h.on = false
	_order.clear()
	var menu: bool = main.settings != null and main.settings.is_open
	if p and hints_on and not menu:
		_find_hints(dt, sled, p)
	for id in _hints:
		var h: Dictionary = _hints[id]
		h.a = move_toward(h.a, 1.0 if h.on else 0.0, dt * (4.0 if h.on else 3.0))
	_layout_bottom()
	_debug.visible = debug_on
	if debug_on:
		_debug.text = _debug_text(sled, p)
	_view.queue_redraw()


# ---- ソリの札 ------------------------------------------------------------------------

func _update_people(dt: float, sled: RigidBody3D, p: Node3D) -> void:
	var raw: int = sled.pushers
	if raw >= _n_push:
		if raw > _n_push and _n_push >= 0:
			_chev_pop = 1.0
		_n_push = raw
		_push_hold = 0.35
	else:
		_push_hold -= dt
		if _push_hold <= 0.0:
			_n_push = raw
	var list: Array = []
	var others_push := maxi(0, _n_push - (1 if p and (p.pushing or p.pulling) else 0))
	var who: Array = sled.holders.keys()
	if sled.rope_holder and not who.has(sled.rope_holder):
		who.append(sled.rope_holder)
	for w in who:
		var strong: bool = (w.pushing or w.pulling) if w == p else others_push > 0
		list.append([w, "stand", _color_of(w), strong])
	for w in sled.riders:
		list.append([w, "sit", _color_of(w), true])
	var before: Array = _people.map(func(x): return x[0])
	for x in list:
		if not before.has(x[0]):
			_pop[x[0]] = 1.0
	_people = list
	for k in _pop.keys():
		_pop[k] = maxf(0.0, _pop[k] - dt * 2.5)
	_chev_pop = maxf(0.0, _chev_pop - dt * 2.0)
	_flow += dt * (0.4 + clampf(sled.linear_velocity.length(), 0.0, 6.0) * 0.9)


func _color_of(w: Node) -> Color:
	if w == main.player:
		return Icons.RED
	return Icons.NAVY if int(w.get("side")) >= 0 else Icons.MUSTARD


# ---- 手引き --------------------------------------------------------------------------

func _hint(id: String, keys: Array, icon: String, world := Vector3.INF) -> void:
	if known(id) and id != "gesture":
		return
	if not _hints.has(id):
		_hints[id] = {"keys": keys, "icon": icon, "world": world, "scr": Vector2.ZERO, "a": 0.0, "on": false, "bottom": world == Vector3.INF}
	var h: Dictionary = _hints[id]
	h.keys = keys
	h.icon = icon
	h.world = world
	h.bottom = world == Vector3.INF
	h.on = true
	if h.bottom:
		_order.append(id)


func _find_hints(dt: float, sled: RigidBody3D, p: CharacterBody3D) -> void:
	var mode: int = p.mode
	if mode != _prev_mode:
		match mode:
			Player.Mode.GRIP: learn("grab")
			Player.Mode.ROPE: learn("rope")
			Player.Mode.RIDE: learn("ride")
			Player.Mode.WALK:
				if _prev_mode == Player.Mode.RIDE:
					learn("getoff")
				elif _prev_mode >= 0:
					learn("letgo")
		_prev_mode = mode
		_work_t = 0.0
	var key := func(k: Key) -> bool: return Input.is_physical_key_pressed(k)
	match mode:
		Player.Mode.GRIP:
			_count_work("push", dt, p.pushing, 2.0)
			_hint("push", ["W"], "push")
			_hint("ride", ["E"], "ride")
			_hint("letgo", ["F"], "release")
		Player.Mode.ROPE:
			_count_work("pull", dt, p.pulling, 2.0)
			_hint("pull", ["W"], "pull")
			_hint("letgo", ["F"], "release")
		Player.Mode.RIDE:
			if sled.linear_velocity.length() < 1.0:
				_count_work("scoop", dt, key.call(KEY_W), 1.0)
				_hint("scoop", ["W"], "scoop")
				_hint("getoff", ["E"], "getoff")
			else:
				_count_work("lean", dt, key.call(KEY_A) or key.call(KEY_D), 1.0)
				_count_work("brake", dt, key.call(KEY_S), 1.0)
				_hint("lean", ["A", "D"], "lean_r")
				_hint("brake", ["S"], "brake")
		Player.Mode.WALK:
			_walk_hints(dt, sled, p)


## 押す・引く・体重をかけるは、合わせて need 秒したら 1 回と数える
func _count_work(id: String, dt: float, doing: bool, need: float) -> void:
	if not doing:
		return
	_work_t += dt
	if _work_t >= need:
		_work_t = 0.0
		learn(id)


func _walk_hints(dt: float, sled: RigidBody3D, p: CharacterBody3D) -> void:
	var pos := p.global_position
	var lp := sled.to_local(pos)
	var ex: float = sled.HALF.x + sled.STAND
	var ez: float = sled.HALF.y + sled.STAND
	var near_sled := false
	var rope_end: Vector3 = sled.rope.end_point()
	var to_rope := Vector2(rope_end.x - pos.x, rope_end.z - pos.z).length()
	if to_rope < 2.4 and lp.z < 0.0:
		_hint("rope", ["F"], "rope", rope_end + Vector3.UP * 0.55)
		near_sled = true
	else:
		var gp: Array = sled.grip_point_near(pos)
		var stand: Vector3 = sled.to_global(gp[0])
		if pos.distance_to(stand) < p.GRAB_REACH + 0.8:
			near_sled = true
			var edge: Vector3 = sled.to_global(gp[0] + gp[1] * sled.STAND)
			_hint("grab", ["F"], "grab", edge + Vector3.UP * 0.75)
			var at_side: bool = absf(lp.x) / ex > absf(lp.z) / ez
			if at_side and sled.riders.size() < sled.SEATS.size():
				var seat: Vector3 = sled.to_global(sled.SEATS[sled.riders.size()])
				_hint("ride", ["E"], "ride", seat + Vector3.UP * 0.75)
	# ミシンの前（PR #12 の sewing_machine.gd。人が近づくと「呼ぶ」= 1 になる）
	var sew = main.get("sewing")
	if sew and is_instance_valid(sew) and int(sew.get("phase")) == 1:
		_hint("sew", ["T"], "needle", sew.global_position + Vector3.UP * 2.2)
	# ほかの人のそば: 手を振る・指さす・声
	var someone := false
	var far := true
	for b in main.get_children():
		if b == p or not (b is CharacterBody3D) or b.get("doll") == null:
			continue
		var d: float = b.global_position.distance_to(pos)
		someone = someone or d < MEET_R
		far = far and d > MEET_R + 3.0
	if someone and not _meeting:
		_meeting = true
		_meet_n += 1
		_meet_t = 0.0
	elif far:
		_meeting = false
	_meet_t += dt
	if _meeting and not near_sled and _meet_t < MEET_SHOW and _meet_n <= LEARNED and not known("gesture"):
		if main.get("emotes") != null:
			_hint("g_ring", ["Tab"], "ring")
			_hint("g_voice", ["1"], "voice")
			_hint("g_breath", ["B"], "breath")
		else:
			_hint("g_wave", ["Q"], "wave")
			_hint("g_voice", ["G"], "voice")
		_hint("g_point", ["mouse_r"], "point")
	# ソリが止まったまま遠い: R で ふもとへ戻せる（ロッジの中では出さない）
	_still_t = _still_t + dt if sled.linear_velocity.length() < 0.3 else 0.0
	var outside: bool = main.lodge_weight(pos.x, pos.z) >= 1.0
	if _still_t > 6.0 and pos.distance_to(sled.global_position) > 35.0 and outside:
		_hint("return", ["R"], "return")


## 画面の下の案内を、まんなかに横一列に並べる（つかんでいる手の少し上）
func _layout_bottom() -> void:
	var u := ui()
	var sz := 74.0 * u
	var ws: Array = []
	var total := 0.0
	for id in _order:
		if id == "return":
			continue
		var w := _badge_w(_hints[id], sz)
		ws.append(w)
		total += w
	total += maxf(0, ws.size() - 1) * 14.0 * u
	var x := _view.size.x / 2.0 - total / 2.0
	var y := _view.size.y * 0.80
	var i := 0
	for id in _order:
		if id == "return":
			_hints[id].scr = Vector2(24.0 * u + _badge_w(_hints[id], sz) / 2.0, _view.size.y - 60.0 * u)
			continue
		_hints[id].scr = Vector2(x + ws[i] / 2.0, y)
		x += ws[i] + 14.0 * u
		i += 1


func _badge_w(h: Dictionary, sz: float) -> float:
	return Icons.badge_w(h.keys, sz)


func _debug_text(sled: RigidBody3D, p: Node) -> String:
	var s := sled.global_position
	var t := "押している人: %d　ソリの高さ: %.1f m（頂上 %.0f m）　速さ: %.1f m/s　%d fps" % [sled.pushers, s.y, main.HILL_H,
		sled.linear_velocity.length(), Engine.get_frames_per_second()]
	if p:
		t += "\n" + ["歩く", "つかむ", "乗る", "紐"][p.mode] + ("　" + p.prompt if p.prompt != "" else "")
		t += "\n覚えた案内: " + str(uses)
	return t


# ---- 描く ----------------------------------------------------------------------------

class View extends Control:
	var hud: Node

	func _draw() -> void:
		var u: float = hud.ui()
		if hud._tag_a > 0.01:
			_draw_tag(u, hud._tag_a)
		var cam := get_viewport().get_camera_3d()
		for id in hud._hints:
			var h: Dictionary = hud._hints[id]
			if h.a < 0.02:
				continue
			var at: Vector2 = h.scr
			var sz := 74.0 * u
			if not h.bottom:
				if cam == null or cam.is_position_behind(h.world):
					continue
				at = cam.unproject_position(h.world)
				sz = 66.0 * u
			var e := ease(h.a, 0.5)
			Icons.badge(self, h.keys, h.icon, at + Vector2(0, (1.0 - e) * 10.0 * u), sz, e)
		_draw_pip_back(u)
		if hud.main.settings and hud.main.settings.is_open:
			_draw_card(u)

	## 左下の札
	func _draw_tag(u: float, a: float) -> void:
		var main: Node3D = hud.main
		var sled: RigidBody3D = main.sled
		var w := 262.0 * u
		var h := 146.0 * u
		var r := Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)
		Icons.tag(self, r, a)
		# 丘の断面（頂上から PROFILE_R までの右半分と、頂上の向こうを少し）
		var x0 := r.position.x + 44.0 * u
		var x1 := r.end.x - 14.0 * u
		var yb := r.position.y + 76.0 * u
		var yt := r.position.y + 16.0 * u
		var rmin := -14.0
		var to_x := func(rr: float) -> float: return lerpf(x0, x1, (rr - rmin) / (PROFILE_R - rmin))
		var to_y := func(hh: float) -> float: return lerpf(yb, yt, hh / main.HILL_H)
		var prof := PackedVector2Array()
		for i in 33:
			var rr := lerpf(rmin, PROFILE_R, i / 32.0)
			prof.append(Vector2(to_x.call(rr), to_y.call(main.hill(rr, 0.0))))
		var mound := prof.duplicate()
		mound.append(Vector2(x1, yb + 4.0 * u))
		mound.append(Vector2(x0, yb + 4.0 * u))
		Icons.screen()
		Icons.patch(self, mound, Color(0.90, 0.93, 0.99), a, false)
		Icons.dashes(self, prof, Icons.THREAD, 1.3 * u, 4.0 * u, 3.0 * u, 0.8 * a)
		# 頂上の旗とふもとのロッジ
		var top := Vector2(to_x.call(0.0), to_y.call(main.HILL_H))
		Icons.thread(self, PackedVector2Array([top, top - Vector2(0, 16) * u]), Icons.WOOD, 1.6 * u, a)
		Icons.patch(self, PackedVector2Array([top - Vector2(0, 16) * u, top + Vector2(11, -12.5) * u, top - Vector2(0, 9) * u]), Icons.RED, a, false)
		var lodge := Vector2(x1 - 6.0 * u, yb)
		Icons.patch(self, PackedVector2Array([lodge + Vector2(-7, 0) * u, lodge + Vector2(7, 0) * u, lodge + Vector2(7, -8) * u,
			lodge + Vector2(0, -14) * u, lodge + Vector2(-7, -8) * u]), Icons.WOOD, a, false)
		draw_rect(Rect2(lodge + Vector2(-2.2, -6.5) * u, Vector2(4.4, 4.0) * u), Color(1.0, 0.72, 0.30, a))
		# ソリの印と、ふもとからソリまでの赤い糸
		var sp := sled.global_position
		var sr := clampf(Vector2(sp.x, sp.z).length(), 0.0, PROFILE_R)
		var climbed := PackedVector2Array()
		for i in 25:
			var rr := lerpf(PROFILE_R, sr, i / 24.0)
			climbed.append(Vector2(to_x.call(rr), to_y.call(main.hill(rr, 0.0)) - 1.0 * u))
		Icons.thread(self, climbed, Icons.RED, 2.0 * u, a)
		var mark := Vector2(to_x.call(sr), to_y.call(main.hill(sr, 0.0)))
		var slope := atan2(to_y.call(main.hill(sr + 1.0, 0.0)) - to_y.call(main.hill(sr - 1.0, 0.0)), to_x.call(sr + 1.0) - to_x.call(sr - 1.0))
		Icons._o = mark + Vector2(0, -6.0 * u).rotated(slope)
		Icons._s = 0.5 * u
		Icons.sled_side(self, Vector2.ZERO, 1.0, a, slope, true)   # 前は左（頂上）
		# いまソリにいる人と、押している人の数だけの糸の矢印
		var px := r.position.x + 52.0 * u
		var py := r.end.y - 12.0 * u - 26.0 * 70.0 * u / 64.0   # 人形の箱の中心（足もとが札の下の縁の少し上）
		var ppl: Array = hud._people
		if ppl.is_empty():
			Icons.icon(self, "person", Vector2(px, py), 70.0 * u, 0.25 * a, Icons.PAPER_EDGE)
			px += 30.0 * u
		for x in ppl:
			var pop: float = hud._pop.get(x[0], 0.0)
			var sz := 70.0 * u * (1.0 + 0.35 * sin(pop * PI))
			var lift := 6.0 * u * sin(pop * PI)
			Icons.icon(self, "person" if x[1] == "stand" else "person_sit", Vector2(px, py - lift), sz, a * (1.0 if x[3] else 0.5), x[2])
			px += 30.0 * u
		Icons.screen()
		var n: int = mini(hud._n_push, 5)
		px += 8.0 * u
		for i in n:
			var wave := 0.5 + 0.5 * sin((hud._flow - i * 0.3) * TAU)
			var big: float = 1.0 + 0.5 * hud._chev_pop * float(i == n - 1)
			Icons.chevron(self, Vector2(px + i * 16.0 * u, py + 6.0 * u), 20.0 * u * big, Icons.THREAD, a * (0.45 + 0.55 * wave), 0.0, 3.0 * u)

	## 右上の 360° 映像が後ろ向きのしるし（「後ろ」の文字の代わり）
	func _draw_pip_back(u: float) -> void:
		var main: Node3D = hud.main
		if main.pip_label == null or main._pip_layer == null or main.pip_mode != 0 or not main._pip_layer.visible:
			return
		var lr: Rect2 = main.pip_label.get_global_rect()
		var font: Font = main.pip_label.get_theme_font("font")
		var tw: float = font.get_string_size(main.pip_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		Icons.icon(self, "back", Vector2(lr.position.x + tw + 14.0, lr.position.y + lr.size.y / 2.0), 22.0, 0.95)

	## Esc の札: すべてのキーと絵（設定の画面の左）
	func _draw_card(u: float) -> void:
		var rows: Array = [
			[["W", "A", "S", "D"], "walk"], [["Shift"], "run"], [["Space"], "jump"], [["mouse_move"], "look"],
			[["F"], "grab"], [["F"], "rope"], [["E"], "ride"], [["R"], "return"],
			[["mouse_r"], "point"], [["mouse_wheel"], "zoom"], [["C"], "view"], [["V"], "pip_cycle"], [["P"], "pip_off"],
			[["Esc"], "settings"],
		]
		if hud.main.get("emotes") != null:
			rows += [[["Tab"], "ring"], [["1", "2", "3", "4"], "voice"], [["B"], "breath"]]
		else:
			rows += [[["Q"], "wave"], [["G"], "voice"]]
		if hud.main.get("sewing") != null:
			rows.append([["T"], "needle"])
		var bs := 46.0 * u                # 一つの段のワッペンの高さ
		var row_h := bs * 1.08
		var col_w := 0.0
		for row in rows:
			col_w = maxf(col_w, Icons.badge_w(row[0], bs))
		col_w += 12.0 * u
		var per := ceili(rows.size() / 2.0)
		var w := col_w * 2.0 + 24.0 * u
		var h := per * row_h + 28.0 * u
		var left := maxf(16.0 * u, size.x / 2.0 - 250.0 - w - 16.0 * u)
		var r := Rect2(left, size.y / 2.0 - h / 2.0, w, h)
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 14.0 * u), Icons.PAPER, 0.97, false)
		var inset := Icons.rr(r.position.x + 6 * u, r.position.y + 6 * u, w - 12 * u, h - 12 * u, 10.0 * u)
		Icons.dashes(self, inset, Icons.THREAD, 1.2 * u, 5.0 * u, 3.5 * u, 0.6, true)
		for i in rows.size():
			var cx := r.position.x + 18.0 * u + (i / per) * col_w
			var cy := r.position.y + 14.0 * u + (i % per) * row_h + row_h / 2.0
			Icons.badge(self, rows[i][0], rows[i][1], Vector2(cx + Icons.badge_w(rows[i][0], bs) / 2.0, cy), bs)
