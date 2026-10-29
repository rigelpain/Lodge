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
const Speedo := preload("res://speedo.gd")
const RideWind := preload("res://ride_wind.gd")
const Plates := preload("res://hud_plates.gd")
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
var plates: Node             # 立体の板（hud_plates.gd）。--flat-hud で使わない（前の平らな絵）
var _tag_view: Control
# 乗って滑っているときの速さ（糸巻き。speedo.gd）
var spd_best := 0.0           # 今日いちばんの速さ（このプレイの間）
var _spd := 0.0               # 表示している速さ（なめらかに追う）
var _spd_a := 0.0
var _spd_pop := 0.0
var _spd_slow := 9.0          # 遅いのが続いている長さ (s)
var _wind := 0.0              # HUD の物が受ける風（設定を掛ける前）。速さの盛り上がりを追い、止まるとふわっと戻る
var _spd_marks := {}          # この滑りで、もう弾んだ節目（"best"・10 m/s など）
var _spd_spin := 0.0          # ボビンを回した角度
var _spd_dist := 0.0          # 滑った長さ (m)。下の端の縫い目が、これだけ流れる
var _spd_knots: Array = []    # ご褒美の結び目を結んだときの _spd_dist
var _spd_color := Icons.RED   # 乗っているソリのメインカラー（糸の色のもと）
var _dbg := {}                # 確かめ用の札に出す値（_debug_values）
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
var compass_style := "3d"      # 方位磁針の形（"3d" 3D のピンクッション、2D の "pillow" 四角いピンクッション・"cushion" トマトの針山・"yarn" 毛糸玉・"glass" フィルムの玉。--compass=）
var pin3d: SubViewport          # 3D のピンクッションと待ち針（pin_cushion_3d.gd）
var _tag_item := {}           # 畳んで持っていれば、その持ち物（_tag_sled は null）


func _ready() -> void:
	pin3d = preload("res://pin_cushion_3d.gd").new()
	pin3d.main = main
	add_child(pin3d)
	layer = 3
	_tag_view = View.new()   # 左下の名札（風で入れ物ごと傾ける）。ほかの表示より下に
	_tag_view.hud = self
	_tag_view.part = "tag"
	_tag_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tag_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_tag_view)
	_view = View.new()
	_view.hud = self
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(_view)
	if main and not main.args.has("flat-hud"):
		plates = Plates.new()
		add_child(plates)
		plates.setup(self)
		plates.scale_k = clampf(float(main.args.get("hud3d-scale", "0.5")), 0.3, 1.0)   # 板の 3D の絵の解像度（印刷は画面のまま）
		_tag_view.visible = false


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
	# 札: 最後に触ったソリ。畳んで持っていれば、その包み
	_tag_item = {}
	_tag_sled = main.sled
	if p:
		var last = p.get("last_sled")
		if last != null and is_instance_valid(last) and last.visible:
			_tag_sled = last
		elif not (p.get("last_item") as Dictionary).is_empty():
			_tag_sled = null
			_tag_item = p.last_item
	_update_people(dt, _tag_sled, p)
	var want_tag := 1.0
	if p and _tag_sled:
		var near: bool = p.global_position.distance_to(_tag_sled.global_position) < TAG_NEAR or p.mode != Player.Mode.WALK
		want_tag = 1.0 if near else 0.0
	_tag_a = move_toward(_tag_a, want_tag, dt * 2.5)
	# 名札の上の方位磁針（3D のピンクッション）: 自分のソリの方へ待ち針が倒れる
	if pin3d and p:
		pin3d.set_color(SledTags.cushion_color(main.craft.tag_designs.get(p.id, 0)) if main.get("craft") else Color(0.96, 0.78, 0.82))
		pin3d.update_pins(get_viewport().get_camera_3d(), p)

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
	_place_hints()
	if debug_on:
		_dbg = _debug_values(sled, p)
	_update_speedo(dt, p, menu)
	if plates:
		_update_plates()
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


## 案内のワッペンの、このコマの画面の真ん中と大きさ（物の上の案内は、カメラに映した所）
func _place_hints() -> void:
	var u := ui()
	var cam := get_viewport().get_camera_3d()
	for id in _hints:
		var h: Dictionary = _hints[id]
		h.shown = false
		if h.a < 0.02:
			continue
		var at: Vector2 = h.scr
		var sz := 74.0 * u
		if not h.bottom:
			if cam == null or cam.is_position_behind(h.world):
				continue
			at = cam.unproject_position(h.world)
			sz = 66.0 * u
		h.draw_at = at + Vector2(0, (1.0 - ease(h.a, 0.5)) * 10.0 * u)
		h.draw_sz = sz
		h.shown = true


func _badge_w(h: Dictionary, sz: float) -> float:
	return Icons.badge_w(h.keys, sz)


## 乗って滑っているときだけ、糸巻きの速さの表示を出す。止まるとふわっと消える。
## 今日いちばんの速さを超えた瞬間と、10・13・15 m/s を超えた瞬間に、ボビンが跳ねて糸が広がり、結び目ができる（一回の滑りで一度ずつ）
func _update_speedo(dt: float, p: Node, menu: bool) -> void:
	var on := false
	var speed := 0.0
	if p and p.mode == Player.Mode.RIDE and is_instance_valid(p.sled):
		speed = p.sled.linear_velocity.length()
		# 1 m/s より遅いのが 1.2 秒続いたら止まったとみなして消す（ふもとでじりじり進むあいだは出さない）
		_spd_slow = 0.0 if speed > 1.0 else _spd_slow + dt
		on = _spd_slow < 1.2
	# HUD の物が受ける風: 乗って滑っているあいだ、速さの盛り上がり（風・速さの表示と同じ値）を追う
	var want_wind := minf(Speedo.level_of(speed), 1.3) if p and p.mode == Player.Mode.RIDE else 0.0   # 読めなくなるほどは揺らさない
	_wind = move_toward(_wind, want_wind, dt * (2.5 if want_wind > _wind else 0.8))
	var vals: Dictionary = main.settings.values if main.settings else {}
	var calm := 0.0 if not vals.get("hud_wind", true) else (0.2 if not vals.get("bob", true) else 1.0)
	Icons.wind = _wind * calm
	Icons.wind_t += dt
	Icons.wind_stepped = main.args.get("hud-shake", "step") != "smooth"
	if _tag_view and not plates:   # 名札: 左の糸の輪を支点に、自由な端（右）が風で持ち上がり、ガタガタ震える
		var tr: Rect2 = _tag_view.tag_rect(ui())
		_tag_view.pivot_offset = Vector2(tr.position.x, tr.position.y + tr.size.y * 0.5)
		_tag_view.rotation = Icons.wind_angle(1.0, -0.09, 0.05)
		_tag_view.position = Icons.wind_offset(1.0, 2.0 * ui())
		_tag_view.queue_redraw()
	var allowed: bool = main.settings == null or main.settings.values.get("speedo", true)
	on = on and allowed and not menu
	_spd_a = move_toward(_spd_a, 1.0 if on else 0.0, dt * (3.0 if on else 1.2))
	_spd = lerpf(_spd, speed, minf(1.0, dt * 8.0))
	_spd_spin += dt * _spd * 2.0
	_spd_dist += dt * _spd
	if p and is_instance_valid(p.sled) and p.sled.has_method("color"):
		_spd_color = p.sled.color()
	_spd_pop = maxf(0.0, _spd_pop - dt * 2.2)
	if not on:
		if _spd_a <= 0.0:
			_spd_marks.clear()
	else:
		if speed > spd_best + 0.2 and speed > 4.0:
			if spd_best > 0.0 and not _spd_marks.has("best"):
				_spd_marks["best"] = true
				_cheer()
			spd_best = speed
		for m in [10.0, 13.0, 15.0]:
			if speed >= m and not _spd_marks.has(m):
				_spd_marks[m] = true
				_cheer()
	_spd_knots = _spd_knots.filter(func(d): return _spd_dist - d < 60.0)


## ご褒美: ボビンがぽんと跳ね、糸がぱっと広がり、縫い目に小さな結び目ができる（speedo.gd が描く）
func _cheer() -> void:
	_spd_pop = 1.0
	_spd_knots.append(_spd_dist)


## 立体の板を置く: 名札・吊るした札・ワッペン・ボビン・右下の小窓の刺繍枠・持ち物の列。
## 風の揺れは、板を支点のまわりに傾ける形でかける（平らな絵のときと同じ値）
func _update_plates() -> void:
	var u := ui()
	plates.begin()
	plates.moving = Icons.wind > 0.001 or _spd_a > 0.01
	if _tag_a > 0.01:
		var tr: Rect2 = _view.tag_rect(u)
		plates.plate("tag", _painter.bind("tag"), tr, 12.0 * u, 8.0 * u, "paper", Vector2(tr.position.x, tr.get_center().y),
			[1.0, -0.09, 0.05, 2.0 * u], _tag_a)
	if _spd_a > 0.01:   # 速さの表示: 立体のボビンと、縫い目を縫うフェルトのリボンの板（ボビンから吊るす）
		var g := Speedo.layout(speedo_box_now(), _spd_pop)
		plates.model("bobbin", "res://props/hud/hud_bobbin.glb", g.c, g.r / 0.5, -_spd_spin, [4.0, 0.0, 0.03, 2.0 * u], _spd_a)
		var rb: Rect2 = g.ribbon
		plates.plate("ribbon", _painter.bind("ribbon"), rb, 8.0 * u, 5.0 * u, "felt", Vector2(rb.get_center().x, rb.position.y),
			[6.0, 0.05, 0.05, 1.5 * u], _spd_a)
	var sc = main.get("self_cam")
	if sc and is_instance_valid(sc) and not sc.get("hidden") and sc.get("_frame"):
		sc.plain_frame = true
		var fr: Control = sc._frame
		var rr := fr.size.x / 2.0
		plates.model("hoop", "res://props/hud/hud_hoop.glb", fr.position + fr.size / 2.0, (rr + 3.0 * u) / 1.03, 0.0, [5.0, 0.0, 0.03, 2.5 * u], 1.0)
	plates.end()


## 板に貼る印刷を描く入れ物（View の part だけを描く）
func _painter(part: String) -> Control:
	var v := View.new()
	v.hud = self
	v.part = part
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return v


## 吊るした札（確かめ用）の場所
func debug_rect(u: float) -> Rect2:
	return Rect2(18.0 * u, 26.0 * u, 176.0 * u, 30.0 * u + 34.0 * u * 5.0 + 12.0 * u)


## 速さの表示の置き場（画面の px）: 画面の左側の縦の帯。左上の確かめ用の札の下から、左下の名札の上のピンクッションの上まで
func speedo_box() -> Rect2:
	var u := ui()
	var vs := _view.size
	var top := 26.0 * u + debug_rect(u).size.y + 18.0 * u        # 確かめ用の札の下（出していなくても同じ所）
	var bottom := vs.y - (146.0 + 18.0) * u - 150.0 * u          # 名札と、その上のピンクッションの上
	return Rect2(22.0 * u, top, 126.0 * u, maxf(bottom - top, 200.0 * u))


## いまの置き場（出てくるときは、上からふわっと下りてくる）
func speedo_box_now() -> Rect2:
	var r := speedo_box()
	r.position.y -= (1.0 - ease(_spd_a, 0.6)) * 24.0 * ui()
	return r


## 確かめ用の札に出す値: 押している人数・ソリの高さ（頂上まで）・速さ・fps・いまの状態・覚えた案内の数
func _debug_values(sled: RigidBody3D, p: Node) -> Dictionary:
	var known_n := 0
	for id in uses:
		if known(id):
			known_n += 1
	return {
		"push": sled.pushers,
		"h": sled.global_position.y,
		"top": main.HILL_H,
		"speed": sled.linear_velocity.length(),
		"fps": int(Engine.get_frames_per_second()),
		"mode": p.mode if p else -1,
		"known": known_n,
	}


# ---- 描く ----------------------------------------------------------------------------

class View extends Control:
	var hud: Node
	var part := ""      # "tag" なら左下の名札だけ、"ribbon" なら速さの縫い目だけを描く（立体の板に重ねる印刷）

	func _draw() -> void:
		var u: float = hud.ui()
		Icons.printing = part != "" and hud.plates != null
		if part == "ribbon":
			var g := Speedo.layout(hud.speedo_box_now(), hud._spd_pop)
			Speedo.draw_stitches(self, g, Speedo.level_of(hud._spd), hud._spd_spin, hud._spd_dist, hud._spd_color, hud._spd_knots, 1.0, false)
			Icons.printing = false
			return
		if part == "tag":   # 名札だけを描く入れ物（風で、この入れ物ごと傾ける。名札の絵は中で描く向きを自分で変えるので）
			if hud._tag_a > 0.01:
				var tr := tag_rect(u)
				_draw_tag(u, hud._tag_a)
				Icons.flap(self, tr.position + Vector2(tr.size.x, 0), Vector2.LEFT, Vector2.DOWN, 22.0 * u, 1.0)
			Icons.printing = false
			return
		_draw_compass_above(u)
		for id in hud._hints:
			var h: Dictionary = hud._hints[id]
			if h.a < 0.02 or not h.get("shown", false):
				continue
			Icons.badge(self, h.keys, h.icon, h.draw_at, h.draw_sz, ease(h.a, 0.5))   # 操作のための表示なので、平らで、風でも揺らさない
		_draw_pip_back(u)
		if hud._spd_a > 0.01:
			_draw_speedo(u)
		if hud.debug_on and not hud._dbg.is_empty():
			_draw_debug(u)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		if hud.main.settings and hud.main.settings.is_open:
			_draw_card(u)

	## 左下の札: 自分の名札（形・色・判子は自分の名札のデザイン）の中に、丘の断面の上をいま関わっているソリ（最後に触ったソリ）の
	## 印が進み、ふもとからの赤い糸が登った分だけ伸びる。下に、そのソリにいる人の形と、押している人の数だけの糸の矢印。
	## 名札の上には、自分のソリの方へ待ち針が倒れる 3D のピンクッション（_draw_compass_above。名札が消えていても出る）
	## 左下の名札の場所（_draw_tag と同じ）
	func tag_rect(u: float) -> Rect2:
		var w := 262.0 * u
		var h := 146.0 * u
		return Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)

	func _draw_tag(u: float, a: float) -> void:
		var main: Node3D = hud.main
		var sled: RigidBody3D = hud._tag_sled
		var item: Dictionary = hud._tag_item
		var w := 262.0 * u
		var h := 146.0 * u
		var r := Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)
		var craft = main.get("craft")
		var idx = craft.tag_designs.get(main.player.id, 0) if craft and main.player else 0   # 自分の名札
		SledTags.draw_tag(self, r, idx, a, false)
		var ink: Color = SledTags.design(idx).edge
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
		# ソリの印と、ふもとからソリまでの赤い糸（畳んでいれば、持っている人の所）
		var sp: Vector3 = sled.global_position if sled else (main.player.global_position if main.player else Vector3.ZERO)
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
		if sled:
			Icons.sled_side(self, Vector2.ZERO, 1.0, a, slope, true)   # 前は左（頂上）
		else:   # 畳んだ包み
			Icons.patch(self, Icons.xf(Icons.rr(-7, -7, 14, 14, 2), PI / 4, Vector2(0, 2), 1.0), preload("res://fabrics.gd").color(item.get("fabric", "red")), a, false)
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
		if sled == null and not item.is_empty():
			# 畳んだソリは形がわからないので、広げた姿をくるくる回して見せる（タグの窓）
			var tw := 62.0 * u
			var win := Rect2(Vector2(r.end.x - tw - 14.0 * u, r.end.y - tw - 8.0 * u), Vector2(tw, tw))
			Icons.screen()
			Icons.patch(self, Icons.rr(win.position.x, win.position.y, tw, tw, 8.0 * u), Color(0.86, 0.90, 0.97), a, true, ink)
			draw_texture_rect(SledTags.turntable(item.get("sled", "mid"), item.get("fabric", "")), win.grow(-3.0 * u), false, Color(1, 1, 1, a))
			return
		Icons.screen()
		var n: int = mini(hud._n_push, 5)
		px += 8.0 * u
		for i in n:
			var wave := 0.5 + 0.5 * sin((hud._flow - i * 0.3) * TAU)
			var big: float = 1.0 + 0.5 * hud._chev_pop * float(i == n - 1)
			Icons.chevron(self, Vector2(px + i * 16.0 * u, py + 6.0 * u), 20.0 * u * big, Icons.THREAD, a * (0.45 + 0.55 * wave), 0.0, 3.0 * u)

	## 名札の上に、方位磁針（3D のピンクッションと待ち針）。玉の所に距離の巻尺
	func _draw_compass_above(u: float) -> void:
		var w := 262.0 * u
		var h := 146.0 * u
		var tag := Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)
		if hud.compass_style != "3d":   # 2D の形（--compass=pillow|cushion|yarn|glass）
			_draw_compass(Vector2(tag.position.x + 110.0 * u, tag.position.y - 62.0 * u), 56.0 * u, u, 1.0)
			return
		var pc = hud.pin3d
		if pc == null or pc.count == 0:
			return
		var vs := Vector2(pc.size)
		var dw := 210.0 * u
		var dr := Rect2(Vector2(tag.position.x + 6.0 * u, tag.position.y - dw * vs.y / vs.x + 26.0 * u), Vector2(dw, dw * vs.y / vs.x))
		draw_texture_rect(pc.get_texture(), dr, false)
		for hp in pc.head_points:
			if float(hp[1]) <= 0.0:
				continue
			var at: Vector2 = dr.position + (hp[0] as Vector2) * dr.size / vs
			var out := (at - dr.get_center()).normalized()
			out = (out + Vector2(0, -0.5)).normalized()
			_tape(at + out * 6.0 * u, out, float(hp[1]), u, 1.0)

	## 自分のソリの向きと距離: [画面での向き（玉の半径 1 で）, 前の度合い（1 真正面、-1 真後ろ）, 色, 距離（0 は乗っている）,
	## 水平の向き（x 右、y 前。カメラの前と右を水平にした基準の、長さ 1）]
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
				pins.append([Vector2.ZERO, 0.0, col, 0.0, Vector2.ZERO])
				continue
			var w: Vector3 = s.global_position + Vector3.UP * 0.3 - cam.global_position
			var d: Vector3 = cam.global_basis.inverse() * w
			var dist := d.length()
			var dir := d / maxf(dist, 0.001)
			var fwd: Vector3 = -cam.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			var right := fwd.cross(Vector3.UP)
			var flat := Vector2(w.dot(right), w.dot(fwd))
			pins.append([Vector2(dir.x, -dir.y), -dir.z, col, dist, flat.normalized() if flat.length() > 0.01 else Vector2(0, 1)])
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

	## 方位磁針（hud.compass_style: "pillow" ピンクッション・"cushion" トマトの針山・"yarn" 毛糸玉・"glass" フィルムの玉）。
	## 自分のソリが 1 台も無いときは出さない（何も指さない飾りに見えるので）
	func _draw_compass(bc: Vector2, R: float, u: float, a: float) -> void:
		if _compass_pins().is_empty():
			return
		match hud.compass_style:
			"cushion": _draw_cushion(bc, R, u, a)
			"yarn": _draw_yarn(bc, R, u, a)
			"glass": _draw_glass(bc, R, u, a)
			_: _draw_pillow(bc, R, u, a)

	## 斜め上から見下ろすピンクッション（代表が見せた「ピンクッション 角型」）: ふっくらした四角いフェルトの枕に、
	## ぽこぽこした玉縁のレース。色は自分の名札の cushion の部品（sled_tags.gd の cushion_color）。
	## 自分のソリの数だけ、玉の付いた待ち針が刺さり、そのソリのある水平の向き（自分の前が奥、右が右）へ倒れる。
	## 針はクッションの、ソリの側の斜面に刺す。後ろのソリの針は手前の斜面から手前へ倒れるので、短く重ならない。
	## 奥の針から先に描く。乗っているソリの針は、クッションの上に寝かせる
	func _draw_pillow(bc: Vector2, R: float, u: float, a: float) -> void:
		var pins := _compass_pins()
		var main: Node3D = hud.main
		var craft = main.get("craft")
		var mine = craft.tag_designs.get(main.player.id, 0) if craft and main.player else 0
		var col: Color = SledTags.cushion_color(mine)
		var rx := R * 0.9
		var sq := 0.5                          # 斜めから見た上の面のつぶれ
		var ry := rx * sq
		var hb := R * 0.2                      # 側面（縫い目の下）の高さ
		var puff := R * 0.16                   # まんなかのふくらみ
		var c := bc + Vector2(0, R * 0.24)
		# 上の面の輪郭: 角の丸い四角の、辺のなかほどが外へふくらむ形（平面の座標 -1〜1 で）
		var plane := PackedVector2Array()
		for side in 4:
			for k in 10:
				var t := k / 10.0
				var a0: Vector2 = [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)][side]
				var a1: Vector2 = [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)][side]
				var nrm := (a0 + a1) * 0.5
				var q := a0.lerp(a1, t) * 0.86 + nrm.normalized() * 0.1 * sin(PI * t)
				plane.append(q)
		var to_s := func(q: Vector2, lift := 0.0) -> Vector2:
			return c + Vector2(q.x * rx, -q.y * ry) - Vector2(0, lift)
		var top := PackedVector2Array()
		var low := PackedVector2Array()
		for q in plane:
			top.append(to_s.call(q))
			low.append(to_s.call(q) + Vector2(0, hb))
		Icons.screen()
		draw_colored_polygon(Icons.ell(c + Vector2(0, hb + 3.0 * u), rx * 0.95, ry * 0.9, 28), Color(Icons.SHADOW, 0.18 * a))   # 落ち影
		Icons.patch(self, low, col.darkened(0.22), a, false)
		Icons.patch(self, top, col.darkened(0.08), a, false)   # 上の面（下の輪郭の手前の半分が、側面に見える）
		var dome := PackedVector2Array()   # ふくらんだまんなか（縁より少し上へ）
		for q in plane:
			dome.append(to_s.call(q * 0.78, puff * 0.6))
		Icons.patch(self, dome, col, a, false)
		# ふくらみ: まんなかの明るさ（毛羽のフェルトの上に、淡い光）
		draw_colored_polygon(Icons.ell(c - Vector2(rx * 0.12, ry * 0.25 + puff * 0.5), rx * 0.55, ry * 0.5, 24), Color(1, 1, 1, 0.22 * a))
		draw_colored_polygon(Icons.ell(c - Vector2(rx * 0.18, ry * 0.32 + puff * 0.6), rx * 0.25, ry * 0.22, 18), Color(1, 1, 1, 0.18 * a))
		# 玉縁のレース: 縫い目の線に、ぽこぽこした白い玉
		var seam := top.duplicate()
		seam.append(top[0])
		draw_polyline(seam, Color(col.darkened(0.3), a), 1.2 * u, true)
		var per := 0.0
		for k in seam.size() - 1:
			per += seam[k].distance_to(seam[k + 1])
		var n := int(per / (5.5 * u))
		for k in n:
			var p := _along_poly(seam, per * k / n)
			draw_circle(p, 2.3 * u, Color(0.99, 0.97, 0.94, a))
			draw_circle(p, 2.3 * u, Color(col.darkened(0.15), 0.35 * a), false, 0.6 * u)
		# 待ち針: ソリの側の斜面に刺し、そのソリの方へ倒す。奥から手前へ
		var order := pins.duplicate()
		order.sort_custom(func(x, y): return (x[4] as Vector2).y > (y[4] as Vector2).y)
		for pin in order:
			var pc: Color = pin[2]
			var dist: float = pin[3]
			if dist <= 0.0:   # 乗っている: クッションの上に寝かせる
				var l: Vector2 = to_s.call(Vector2(-0.6, 0.05), puff)
				var r2: Vector2 = to_s.call(Vector2(0.6, 0.05), puff)
				draw_line(l, r2, Color(0.70, 0.72, 0.78, a), 2.2 * u, true)
				draw_circle(r2, 6.6 * u, Color(1, 1, 1, a))
				draw_circle(r2, 5.4 * u, Color(pc, a))
				continue
			var b: Vector2 = pin[4]
			var q := b * 0.32
			var base: Vector2 = to_s.call(q, puff * (1.0 - q.length_squared()))
			# 倒れる向き: 奥（前のソリ）へは上へ、手前（後ろのソリ）へは手前の斜面の上を大きく手前へ。真後ろでも点にならない
			var tip := base + Vector2(b.x * R * 0.6, -b.y * R * (0.42 if b.y > 0.0 else 0.8)) + Vector2(0, -R * 0.34)
			draw_line(base, tip, Color(0.62, 0.64, 0.70, a), 2.2 * u, true)   # 待ち針の軸
			draw_line(base, tip, Color(1, 1, 1, 0.5 * a), 0.8 * u, true)
			draw_circle(base, 1.6 * u, Color(col.darkened(0.35), 0.7 * a))     # 刺さった所のくぼみ
			var hr := (6.0 - 1.2 * b.y) * u   # 奥へ倒れた針の玉は小さく、手前へ倒れた針の玉は大きく
			draw_circle(tip, hr + 1.4 * u, Color(1, 1, 1, a))
			draw_circle(tip, hr, Color(pc, a))
			draw_circle(tip - Vector2(hr, hr) * 0.35, hr * 0.3, Color(1, 1, 1, 0.6 * a))
			var out := Vector2(b.x, -b.y * sq).normalized() if Vector2(b.x, b.y * sq).length() > 0.05 else Vector2.UP
			out = (out + Vector2(0, -0.6)).normalized()
			_tape(tip + out * hr, out, dist, u, a)

	## 折れ線の上の、始まりから d の所
	func _along_poly(pts: PackedVector2Array, d: float) -> Vector2:
		for k in pts.size() - 1:
			var l := pts[k].distance_to(pts[k + 1])
			if d <= l:
				return pts[k].lerp(pts[k + 1], d / maxf(l, 0.001))
			d -= l
		return pts[pts.size() - 1]

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

	## 乗って滑っているときの速さ（ボビン。数字は出さない）
	func _draw_speedo(u: float) -> void:
		var e := ease(hud._spd_a, 0.6)
		if e > 0.01:
			var g := Speedo.layout(hud.speedo_box_now(), hud._spd_pop)
			var k := Speedo.level_of(hud._spd)
			if hud.plates == null:   # 平らなとき: リボンは糸巻きから吊るして揺れる。ボビンは小刻みに
				var rb: Rect2 = g.ribbon
				draw_set_transform_matrix(Icons.wind_xform(Vector2(rb.get_center().x, rb.position.y), 6.0, 0.05, 0.05, 1.5 * u))
				Speedo.draw_stitches(self, g, k, hud._spd_spin, hud._spd_dist, hud._spd_color, hud._spd_knots, e)
			draw_set_transform_matrix(Icons.wind_xform(g.c, 4.0, 0.0, 0.03, 2.0 * u))
			Speedo.draw_spool(self, g, k, hud._spd_spin, hud._spd_color, hud.spd_best, hud._spd_pop, e, hud.plates == null)
			draw_set_transform_matrix(Transform2D.IDENTITY)

	## 確かめ用の札（設定の「確かめ用の数字」か --hud-debug のとき）: 左上に、画面の上の縁から赤い糸で吊るした紙の札。
	## 段ごとに絵と数字: 人の形（押している人数）、丘（ソリの高さ／頂上）、風（速さ）、砂時計（fps）、いまの状態の絵と、
	## 覚えた案内の数だけの玉止め。地は無地の生成りで、外側に影と藍の縁取り（雪・空・ロッジの中でも読める）
	func _draw_debug(u: float) -> void:
		var d: Dictionary = hud._dbg
		var row := 34.0 * u
		var w := 176.0 * u
		var top := 30.0 * u
		var h := top + row * 5.0 + 12.0 * u
		var x0 := 18.0 * u
		var y0 := 26.0 * u
		var hole := Vector2(x0 + w / 2.0, y0 + 13.0 * u)
		# 吊るす糸（画面の上の縁から、はとめへ）
		Icons.screen()
		Icons.thread(self, PackedVector2Array([Vector2(hole.x - 10.0 * u, -2.0), hole + Vector2(0, -4.0 * u), Vector2(hole.x + 10.0 * u, -2.0)]),
			Icons.RED, 1.8 * u, 1.0)
		# 吊るした札は、はとめを支点に、風で外（左）へなびいて揺れる
		draw_set_transform_matrix(Icons.wind_xform(hole, 2.0, 0.14, 0.06, 1.5 * u))
		Icons.paper_tag(self, Rect2(x0, y0, w, h), 10.0 * u, u)
		draw_circle(hole, 5.0 * u, Icons.PAPER_EDGE)
		draw_circle(hole, 3.2 * u, Color(0.35, 0.30, 0.28, 0.9))
		var lx := x0 + 30.0 * u
		var tx := x0 + 58.0 * u
		var y := y0 + top + row / 2.0
		var main: Node3D = hud.main
		var lines := [
			["person", str(d.push), "", Icons.RED],
			["hill", "%.1f" % d.h, "/%d m" % int(d.top), Icons.THREAD],
			["speed", "%.1f" % d.speed, "m/s", Icons.THREAD],
			["hourglass", str(d.fps), "fps", Icons.RED if d.fps < 30 else Icons.THREAD],
		]
		for i in lines.size():
			var ln: Array = lines[i]
			Icons.icon(self, ln[0], Vector2(lx, y - (5.0 * u if ln[0] == "person" else 0.0)), (48.0 if ln[0] == "person" else 40.0) * u, 1.0)
			var nw := Icons.stitched_text(self, ln[1], Vector2(tx, y), 20.0 * u, ln[3])
			if ln[2] != "":
				Icons.stitched_text(self, ln[2], Vector2(tx + nw + 4.0 * u, y + 2.0 * u), 12.0 * u, Icons.THREAD.lightened(0.25), false)
			Icons.screen()
			Icons.dashes(self, PackedVector2Array([Vector2(x0 + 12.0 * u, y + row / 2.0), Vector2(x0 + w - 12.0 * u, y + row / 2.0)]),
				Icons.PAPER_EDGE, 1.0 * u, 3.0 * u, 3.0 * u, 0.9)
			y += row
		# いまの状態（歩く・つかむ・乗る・紐）の絵と、覚えた案内の数だけの玉止め
		var mode: int = d.mode
		if mode >= 0:
			var st: String = ["walk", "grab", "ride", "rope"][mini(mode, 3)]
			Icons.icon(self, st, Vector2(lx, y + (6.0 * u if st == "walk" else 0.0)), (60.0 if st == "walk" else 46.0) * u, 1.0)
		for k in mini(int(d.known), 12):
			var c := Vector2(tx + 4.0 * u + (k % 6) * 15.0 * u, y - 5.0 * u + (k / 6) * 12.0 * u)
			draw_circle(c + Vector2(0.6, 1.0) * u, 4.2 * u, Color(Icons.SHADOW, 0.25))
			draw_circle(c, 4.2 * u, Icons.RED)
			draw_arc(c, 2.4 * u, 0.4, 4.0, 8, Icons.RED.lightened(0.35), 1.0 * u, true)   # 糸の巻き

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
