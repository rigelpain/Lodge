extends CanvasLayer
## 画面の表示（HUD）。文字を使わず、アイコン・矢印・形で伝える。決まりと場面ごとの絵は design/hud.md。
##   左下: ソリの札。最後に触ったソリ（つかむ・紐・乗る・広げる）のタグの柄で描く（sled_tags.gd）。丘の断面の上をソリの印が動き、
##         登った分だけ赤い糸が伸びる。下に、いまソリにいる人の形と、押している人の数だけの糸の矢印。
##         そのソリを畳んで持っていれば、印は持っている人の所で、人の横に広げた姿がくるくる回る図
##   物の上: 近づいたときだけ、キーの形と動きの絵のワッペン。3 回したら（覚えたら）もう出さない
##   画面の下のまんなか: つかんでいる・紐を持っている・乗っているときの手引き。ほかの人のそばでは身ぶりの手引き
##   Esc: 設定の画面の左に、すべてのキーと絵を並べた札
##   確かめ用: --hud-debug か設定の「確かめ用の数字」で、左上にこれまでの文字（人数・高さ・速さ・fps）
## 絵は hud_icons.gd。ミシン（main.sewing）とエモート（main.emotes）は、あればその案内も出す。

const Icons := preload("res://hud_icons.gd")
const SledTags := preload("res://sled_tags.gd")
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
var _tag_sled: RigidBody3D    # 札に出すソリ（最後に触ったソリ）
var compass_style := "cushion" # 方位磁針の形（"cushion" 針山と待ち針、"yarn" 毛糸玉と縫い針、"glass" フィルムの玉。--compass=）
var _tag_item := {}           # 畳んで持っていれば、その持ち物（_tag_sled は null）


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


## 画面の高さと、設定の「HUD の大きさ」に合わせた大きさ（1080・100% で 1）
func ui() -> float:
	return Icons.ui_scale(_view.size.y)


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
		KEY_T: learn("sew"); learn("set")
		KEY_N: learn("sack")
		KEY_I: learn("gear")
		KEY_Q, KEY_X, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_B: learn("gesture")


func _process(dt: float) -> void:
	if main == null or main.sled == null:
		return
	var p: CharacterBody3D = main.player
	var sled: RigidBody3D = p.sled if p and is_instance_valid(p.sled) else main.sled   # あなたのそばのソリ（案内に使う。縫ったソリも）
	# 札: 自分の名札に、自分のソリを指す球の方位磁針。いまつかんでいる・乗っているソリにいる人も
	_tag_item = {}
	_tag_sled = sled
	_update_people(dt, _tag_sled, p)
	var want_tag := 1.0
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
	if sled == null:   # 畳んだソリ: 持っている人だけ
		_n_push = 0
		_people = [[p, "stand", Icons.RED, true]] if p else []
		_flow += dt * 0.4
		return
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
		var strong: bool = ((w.pushing or w.pulling) if w == p else others_push > 0) or sled.is_dragged(w)
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
			if sled.is_dragged(p):
				# 引きずられている間は押せない（踏ん張るのはひとりでに）。出すのは手を離す、だけ
				_hint("letgo", ["F"], "release")
				return
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
	# ミシンの前（PR #12 の sewing_machine.gd。人が近づくと「呼ぶ」= 1 になる）。
	# 工房があるときは、型紙か布を手に持っていればセットの案内（T と型紙と布の絵）
	var sew = main.get("sewing")
	if sew and is_instance_valid(sew) and int(sew.get("phase")) == 1:
		if main.get("craft") == null:
			_hint("sew", ["T"], "needle", sew.global_position + Vector3.UP * 2.2)
		elif p.machine_near():
			_hint("set", ["F"], "set", sew.global_position + Vector3.UP * 2.2)
	# 売り子のおじさん: F で売り台
	if p.shop_near() and not p.shopping:
		_hint("shop", ["F"], "shop", main.shopkeeper.global_position + Vector3.UP * 2.0)

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
			_hint("g_voice", ["4"], "voice")   # 1〜3 は手（高い・低い手のひら、指さし）、4〜7 が声
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

	## 左下の札: 自分の名札（sled_tags.gd）に載せた、針山と待ち針の方位磁針（_draw_cushion）。
	## 自分の名札が付いたソリ（縫ったソリ・出している米袋）の数だけ待ち針が立ち、いま見ている向きから
	## そのソリの方を 3D で指す（前にあれば玉が大きく、後ろにあれば針山の陰）。玉の色はソリのメインカラー。
	## 距離は、玉の先の巻尺のテープの切れはしに小さな数（m）。乗っているソリの針は、針山の上に寝かせる。
	## 右に、いまつかんでいる・乗っているソリにいる人と、押している人の数だけの糸の矢印
	func _draw_tag(u: float, a: float) -> void:
		var main: Node3D = hud.main
		var p = main.player
		var craft = main.get("craft")
		var mine = craft.tag_designs.get(p.id, 0) if craft and p else 0
		var w := 262.0 * u
		var h := 146.0 * u
		var r := Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)
		SledTags.draw_tag(self, r, mine, a, false)
		var bc := Vector2(r.position.x + 112.0 * u, r.position.y + h * 0.5)
		_draw_compass(bc, 56.0 * u, u, a)
		if p == null or p.mode == Player.Mode.WALK:
			return
		var px := r.position.x + 192.0 * u
		var py := r.end.y - 14.0 * u - 26.0 * 56.0 * u / 64.0
		for x in hud._people.slice(0, 3):
			var pop: float = hud._pop.get(x[0], 0.0)
			Icons.icon(self, "person" if x[1] == "stand" else "person_sit", Vector2(px, py - 5.0 * u * sin(pop * PI)), 56.0 * u * (1.0 + 0.3 * sin(pop * PI)), a * (1.0 if x[3] else 0.5), x[2])
			px += 24.0 * u
		Icons.screen()
		for i in mini(hud._n_push, 4):
			var wave := 0.5 + 0.5 * sin((hud._flow - i * 0.3) * TAU)
			Icons.chevron(self, Vector2(r.position.x + 186.0 * u + i * 14.0 * u, r.position.y + 26.0 * u), 16.0 * u, Icons.THREAD, a * (0.45 + 0.55 * wave), 0.0, 2.6 * u)

	## 自分のソリの向きと距離: [画面での向き（玉の半径 1 で）, 前の度合い（1 真正面、-1 真後ろ）, 色, 距離（0 は乗っている）]
	func _compass_pins() -> Array:
		var main: Node3D = hud.main
		var p = main.player
		var cam := get_viewport().get_camera_3d()
		var pins := []
		if cam == null or p == null:
			return pins
		for s in main.get_tree().get_nodes_in_group("sleds"):
			if not is_instance_valid(s) or not s.visible or int(s.get("owner_id")) != int(p.id):
				continue
			var col: Color = s.color() if s.has_method("color") else Icons.RED
			if p.mode == Player.Mode.RIDE and p.sled == s:
				pins.append([Vector2.ZERO, 0.0, col, 0.0])
				continue
			var d: Vector3 = cam.global_basis.inverse() * (s.global_position + Vector3.UP * 0.3 - cam.global_position)
			var dist := d.length()
			var dir := d / maxf(dist, 0.001)
			pins.append([Vector2(dir.x, -dir.y), -dir.z, col, dist])
		pins.sort_custom(func(x, y): return x[1] < y[1])   # 後ろのから描く
		return pins

	## 距離の札: 巻尺のテープの切れはし（黄色い紙に目盛り）に、小さな数（m）
	func _tape(at: Vector2, out: Vector2, dist: float, u: float, a: float) -> void:
		var font := ThemeDB.fallback_font
		var fs := int(round(11.0 * u))
		var txt := "%d" % roundi(dist)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w := tw + 8.0 * u
		var h := fs + 4.0 * u
		var c := at + out * (w * 0.5 + 2.0 * u)
		var r := Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 2.0 * u), Color(0.97, 0.84, 0.30), a, false)
		for k in int(w / (3.0 * u)):   # 目盛り
			var x := r.position.x + 1.5 * u + k * 3.0 * u
			draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + (2.5 if k % 2 == 0 else 1.5) * u), Color(0.25, 0.2, 0.1, 0.8 * a), 0.8 * u)
		draw_string(font, Vector2(r.position.x + 4.0 * u, r.end.y - 2.5 * u), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.20, 0.16, 0.10, a))

	## 方位磁針（hud.compass_style: "cushion" 針山と待ち針・"yarn" 毛糸玉と縫い針・"glass" フィルムの玉）
	func _draw_compass(bc: Vector2, R: float, u: float, a: float) -> void:
		match hud.compass_style:
			"yarn": _draw_yarn(bc, R, u, a)
			"glass": _draw_glass(bc, R, u, a)
			_: _draw_cushion(bc, R, u, a)

	## 針山（トマトの形の赤いフェルト、緑のへた）に、ソリの数だけ待ち針。上のまんなかから、そのソリの方へ傾いて立つ。
	## 後ろのソリの針は針山の陰（先に描いて、針山で隠す）。玉はソリのメインカラー。乗っているソリの針は針山の上に寝かせる
	func _draw_cushion(bc: Vector2, R: float, u: float, a: float) -> void:
		var pins := _compass_pins()
		var c := bc + Vector2(0, R * 0.32)
		var rx := R * 0.82
		var ry := R * 0.58
		var base := c - Vector2(0, ry * 0.42)   # 針の刺さる所
		var drawn := func(pin: Array, part := "all") -> void:
			var front: float = pin[1]
			var dist: float = pin[3]
			if dist <= 0.0:   # 乗っている: 針山の上に寝かせる
				var l := base + Vector2(-R * 0.62, -ry * 0.18)
				var r2 := base + Vector2(R * 0.62, -ry * 0.18)
				draw_line(l, r2, Color(0.70, 0.72, 0.78, a), 2.2 * u, true)
				draw_circle(r2, 6.0 * u, Color(1, 1, 1, a))
				draw_circle(r2, 4.8 * u, Color(pin[2], a))
				return
			var al: float = a * (0.6 if front < -0.05 else 1.0)
			var tip: Vector2 = base + (pin[0] as Vector2) * R * 0.98
			if part != "head":
				draw_line(base, tip, Color(0.62, 0.64, 0.70, al), 2.0 * u, true)
				draw_line(base, tip, Color(1, 1, 1, 0.5 * al), 0.8 * u, true)
			if part == "shaft":
				return
			var hr: float = (4.6 + 2.6 * maxf(front, 0.0)) * u
			draw_circle(tip, hr + 1.4 * u, Color(1, 1, 1, al))
			draw_circle(tip, hr, Color(pin[2], al))
			draw_circle(tip - Vector2(hr, hr) * 0.35, hr * 0.3, Color(1, 1, 1, 0.6 * al))
			var out: Vector2 = (tip - base).normalized() if tip.distance_to(base) > 1.0 else Vector2.UP
			_tape(tip + out * hr, out, dist, u, al)
		for pin in pins:   # 後ろ: 軸は針山の陰に（玉と距離は、あとで薄く上に描く）
			if pin[1] < -0.05 and pin[3] > 0.0:
				drawn.call(pin, "shaft")
		Icons.screen()
		# 針山: 赤いフェルトのトマト。房の筋、緑のへた、下に木の台
		Icons.patch(self, Icons.rr(c.x - rx * 0.9, c.y + ry * 0.62, rx * 1.8, ry * 0.42, 5.0 * u), Icons.WOOD, a, true, Icons.CAP)
		Icons.patch(self, Icons.ell(c, rx, ry, 32), Color(0.80, 0.26, 0.22), a, false)
		var rim := Icons.ell(c, rx + 1.5 * u, ry + 1.5 * u, 40)   # 生成りの縁取り（赤い名札の上でも針山が見えるように）
		rim.append(rim[0])
		draw_polyline(rim, Color(0.98, 0.94, 0.86, 0.9 * a), 2.2 * u, true)
		for k in [-0.55, 0.0, 0.55]:
			var arc := PackedVector2Array()
			for t in 9:
				var y := lerpf(-ry * 0.92, ry * 0.92, t / 8.0)
				arc.append(c + Vector2(rx * k * sqrt(maxf(0.0, 1.0 - pow(y / ry, 2.0))), y))
			Icons.dashes(self, arc, Color(0.55, 0.14, 0.12), 1.2 * u, 3.0 * u, 2.0 * u, 0.8 * a)
		draw_arc(c + Vector2(-rx * 0.35, -ry * 0.3), rx * 0.35, PI * 1.05, PI * 1.5, 10, Color(1, 1, 1, 0.35 * a), 2.0 * u, true)
		var leaf := PackedVector2Array()
		for k in 10:
			var ang := -PI / 2 + TAU * k / 10.0
			leaf.append(base + Vector2(cos(ang), sin(ang) * 0.55) * (R * (0.28 if k % 2 == 0 else 0.1)))
		Icons.patch(self, leaf, Color(0.36, 0.55, 0.30), a, false)
		for pin in pins:   # 後ろの玉と距離、前と、乗っている
			drawn.call(pin, "head" if pin[1] < -0.05 and pin[3] > 0.0 else "all")

	## 毛糸玉に、ソリの数だけ縫い針。針の先がそのソリの方を指し、針の穴からソリの色の糸が垂れる
	func _draw_yarn(bc: Vector2, R: float, u: float, a: float) -> void:
		var pins := _compass_pins()
		var rr := R * 0.62
		var drawn := func(pin: Array) -> void:
			var front: float = pin[1]
			var dist: float = pin[3]
			var al: float = a * (0.6 if front < -0.05 else 1.0)
			var v: Vector2 = pin[0] if dist > 0.0 else Vector2(0, 0.7)
			var tip: Vector2 = bc + v * R
			var eye: Vector2 = bc - v * R * 0.25
			draw_line(eye, tip, Color(0.70, 0.72, 0.78, al), 2.4 * u, true)
			draw_line(eye, tip, Color(1, 1, 1, 0.5 * al), 0.9 * u, true)
			draw_circle(eye, 2.2 * u, Color(0.3, 0.3, 0.35, al))
			var tail := PackedVector2Array()
			for k in 8:
				var t := k / 7.0
				tail.append(eye + Vector2(-6.0 * t, 10.0 * t + 4.0 * sin(t * PI)) * u)
			Icons.thread(self, tail, pin[2], 2.4 * u, al)
			if dist > 0.0:
				_tape(tip, v.normalized() if v.length() > 0.01 else Vector2.UP, dist, u, al)
		for pin in pins:
			if pin[1] < -0.05 and pin[3] > 0.0:
				drawn.call(pin)
		Icons.screen()
		Icons.patch(self, Icons.circ(bc, rr, 28), Color(0.86, 0.74, 0.50), a, false)
		for k in 4:   # 巻いた毛糸の筋
			var e := Icons.ell(Vector2.ZERO, rr * 0.95, rr * (0.3 + 0.15 * k), 28)
			Icons.dashes(self, Icons.xf(e, 0.5 + k * 0.7, bc, 1.0), Color(0.62, 0.48, 0.28), 1.3 * u, 4.0 * u, 1.5 * u, 0.8 * a, true)
		for pin in pins:
			if not (pin[1] < -0.05 and pin[3] > 0.0):
				drawn.call(pin)

	## フィルムと白い糸の枠の玉（はじめの案）
	func _draw_glass(bc: Vector2, R: float, u: float, a: float) -> void:
		var pins := _compass_pins()
		Icons.screen()
		Icons.patch(self, Icons.rr(bc.x - R * 0.55, bc.y + R * 0.78, R * 1.1, R * 0.28, 6.0 * u), Icons.WOOD, a, true, Icons.CAP)
		draw_circle(bc, R, Color(0.86, 0.92, 1.0, 0.42 * a))
		draw_arc(bc, R, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * a), 2.6 * u, true)
		Icons.dashes(self, Icons.ell(bc, R - 2.0 * u, (R - 2.0 * u) * 0.28, 36), Color(0.55, 0.62, 0.78), 1.0 * u, 3.0 * u, 3.0 * u, 0.6 * a, true)
		for pin in pins:
			var dist: float = pin[3]
			var tip: Vector2 = bc + ((pin[0] as Vector2) * 0.82 if dist > 0.0 else Vector2(0, 0.55)) * R
			var al: float = a * (0.45 if pin[1] < -0.1 else 1.0)
			draw_line(bc, tip, Color(0.62, 0.64, 0.70, al), 2.0 * u, true)
			draw_circle(tip, 5.0 * u, Color(1, 1, 1, al))
			draw_circle(tip, 3.8 * u, Color(pin[2], al))
			if dist > 0.0:
				_tape(tip, (tip - bc).normalized(), dist, u, al)

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
	func _draw_card(u: float, fit := true) -> void:
		var rows: Array = [
			[["W", "A", "S", "D"], "walk"], [["Shift"], "run"], [["Space"], "jump"], [["mouse_move"], "look"],
			[["F"], "grab"], [["F"], "rope"], [["E"], "ride"], [["R"], "return"],
			[["mouse_r"], "point"], [["C"], "view"], [["V"], "pip_cycle"], [["P"], "pip_off"],
			[["Esc"], "settings"],
		]
		# Alt＋ホイール（ピンチ・二本指も）: 一人称は視野角、三人称はカメラの距離。Alt＋Shift＋ホイール（二本指の横）で高さ
		var pl = hud.main.player
		if pl and pl.third:
			rows += [[["Alt", "mouse_wheel"], "cam_dist"], [["Alt", "Shift", "mouse_wheel"], "cam_height"]]
		else:
			rows.append([["Alt", "mouse_wheel"], "zoom"])
		if hud.main.get("emotes") != null:
			rows += [[["Tab"], "ring"], [["1", "2", "3"], "ring"], [["4", "5", "6", "7"], "voice"], [["B"], "breath"]]
		else:
			rows += [[["Q"], "wave"], [["G"], "voice"]]
		if hud.main.get("sewing") != null:
			rows.append([["T"], "needle"])
		if hud.main.get("craft") != null:   # 工房: 売り子に F、ミシンに T でセット、G で畳む、左クリックで広げる、ホイールで持ち替え
			rows += [[["F"], "shop"], [["F"], "set"], [["N"], "sack"], [["I"], "gear"], [["mouse_wheel"], "hand"], [["Z"], "hand"]]
		var bs := 46.0 * u                # 一つの段のワッペンの高さ
		var row_h := bs * 1.08
		var col_w := 0.0
		for row in rows:
			col_w = maxf(col_w, Icons.badge_w(row[0], bs))
		col_w += 12.0 * u
		var per := ceili(rows.size() / 2.0)
		var w := col_w * 2.0 + 24.0 * u
		var h := per * row_h + 28.0 * u
		# 設定の画面（メニューの大きさで変わる）の左に置く。入らなければ札を縮める
		var st = hud.main.settings
		var pr: Rect2 = st.panel_rect() if st.has_method("panel_rect") else Rect2(size.x / 2.0 - 250.0, 0, 500, size.y)
		var room := pr.position.x - 24.0 * u
		if fit and (room < w or h > size.y - 24.0):
			_draw_card(u * clampf(minf(room / w, (size.y - 24.0) / h), 0.35, 1.0), false)
			return
		var left := maxf(8.0, pr.position.x - 16.0 * u - w)
		var r := Rect2(left, size.y / 2.0 - h / 2.0, w, h)
		Icons.screen()
		Icons.patch(self, Icons.rr(r.position.x, r.position.y, w, h, 14.0 * u), Icons.PAPER, 0.97, false)
		var inset := Icons.rr(r.position.x + 6 * u, r.position.y + 6 * u, w - 12 * u, h - 12 * u, 10.0 * u)
		Icons.dashes(self, inset, Icons.THREAD, 1.2 * u, 5.0 * u, 3.5 * u, 0.6, true)
		for i in rows.size():
			var cx := r.position.x + 18.0 * u + (i / per) * col_w
			var cy := r.position.y + 14.0 * u + (i % per) * row_h + row_h / 2.0
			Icons.badge(self, rows[i][0], rows[i][1], Vector2(cx + Icons.badge_w(rows[i][0], bs) / 2.0, cy), bs)
