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
## この滑りで糸の上に縫い込まれたボタン {d（縫い込んだときの _spd_dist）, look（"wood"・"brass"）, claimed（財布へ飛ぶ番が決まった）,
## off（糸から外れて飛んでいった）}。滑った距離と速さの木（倍率が高いと真鍮）と、コンボの真鍮（snow_buttons.gd の ride_mark）
## 両替（2026-10-30 代表「ゲージが木のコインで埋まって獲得できないお金なんかは、真鍮にして場所を空ければいいのに」）:
## 同じ素材が EXCHANGE_N 個たまると、くるくる縫い縮まって上の素材 1 個に変わり、場所が空く（木 10 → 真鍮、真鍮 10 → 白蝶貝、
## 白蝶貝 10 → 螺鈿）。値打ちは変えない。変わるときに素材の音（チン など）ときらめき。entry には両替の進み mk（0〜1）・
## 行き先 into（番号）、変わってできたボタンには出てからの進み pk（0〜1）を入れる（speedo.gd が描く）
var _spd_sewn: Array = []
const EXCHANGE_N := 10
const EXCHANGE_T := 0.5       # 縫い縮まる長さ (s)
const NEXT_LOOK := {"wood": "brass", "brass": "pearl", "pearl": "raden"}
const LOOK_VALUE := {"wood": 1, "brass": 10, "pearl": 100, "raden": 1000}
var _merge_t0 := -1.0         # いま縫い縮まっている両替の始まり（_clock_now。なければ -1）
## 糸くず: 滑った分のうち、乗り物の倍率でまだ木 1 個に満たない端数（snow_buttons.gd の ride_lint）と、前の滑りから持ち越した端数。
## 糸の上の積もったボタンのいちばん上に、小さな糸くずの玉として見せ、たまるほど大きくなる（取りこぼしに見えないように）
var _lint_frac := 0.0
var _lint_carry := 0.0

func lint() -> float:
	return _lint_frac + _lint_carry
var _reel := 0.0              # 滑り終わって、縫い目の糸を巻き取っている残り (s)。糸の上のボタンは財布へ飛ぶ（craft_ui.gd）
var _reel_t := 1.6            # この巻き取りの長さ (s)。ボタンが多いほど長い
var _ride_seen := -99.0       # 最後に乗っていた時刻（止まってすぐ降りても、巻き取りを見せる）
var _ride_sled := ""          # 最後に乗っていたソリの名前（米袋をしまってソリが消えても、自分の分の出来事を見分ける）
const REEL_T := 1.6
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
const TAG_K := 1.4            # 名札の大きさ（2026-10-29 代表「名札もっと大きくていい」。HUD の大きさの設定にも合わせて変わる）
const FLIP_LEN := 0.42        # 札をめくる長さ (s)
const FLIP_HOLD := 6.0        # 手でめくったあと、遠くのソリの札でも出しておく長さ (s)
var cards: Array = []         # 名札の束: [{sled, item, design, key}]。自分の名札を付けたソリ（置いた・畳んで持つ・帯の米袋）と、
                              # 持ち主のいないソリに触ったときはロッジの名札を先頭に（hud.gd の _update_cards）
var _card := 0                # いま前の札（めくった先）
var _card_key := ""
var _shown_key := ""          # めくっている途中で、前に見えている札（半分めくるまでは前の札）
var _last_key := ""           # 最後に触ったソリの札（変わったら、その札を前へ）
var _flip := 0.0              # めくりの残り（1→0）
var _flip_dir := 1
var _flip_hold := 0.0
var _tag_sled: RigidBody3D    # 札に出すソリ（最後に触ったソリ）
var _tag_item := {}           # 畳んで持っていれば、その持ち物（_tag_sled は null）


func _ready() -> void:
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
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 刺繍枠の絵を縮めて描く
	_view.z_index = 10   # 板の印刷（重なりの順に z_index を使う）より上に。Esc の札が名札の下に隠れないように
	add_child(_view)
	var sbn = main.get("snow_buttons") if main else null
	if sbn:
		sbn.happened.connect(_on_buttons)
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
	var menu: bool = main.settings != null and main.settings.is_open
	var cu = main.get("craft_ui")
	if cu and (cu.get("shop_open") or cu.get("machine_open") or cu.get("gear_open")):
		menu = true   # 売り台・ミシン・装備の画面を開いているあいだは、めくらない
	if not menu and e.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:   # 名札の束をめくる（ほかの操作には使っていない）
		var step := -1 if e.physical_keycode in [KEY_LEFT, KEY_UP] else 1
		_select(_card + step, true)
		learn("flip")
		return
	match e.physical_keycode:
		KEY_BACKSPACE: learn("return")
		KEY_R: learn("lamp")
		KEY_T: learn("sew"); learn("set")
		KEY_N: learn("sack")
		KEY_I: learn("gear")
		KEY_Q, KEY_X, KEY_TAB, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_B: learn("gesture")


func _process(dt: float) -> void:
	if main == null or main.sled == null:
		return
	var p: CharacterBody3D = main.player
	var sled: RigidBody3D = p.sled if p and is_instance_valid(p.sled) else main.sled   # あなたのそばのソリ（案内に使う。縫ったソリも）
	# 札: 名札の束のうち、前に見えている札のソリ（畳んで持っていれば、その包み）
	_update_cards(dt, p)
	var cur: Dictionary = shown_card()
	_tag_sled = cur.get("sled") if cur.get("sled") != null and is_instance_valid(cur.get("sled")) else null
	_tag_item = cur.get("item", {})

	_update_people(dt, _tag_sled, p)
	# 名札はいつも出しておく（2026-10-29 代表「タグは消えないようにしてほしい」）。ソリから離れていても、その札のソリの丘と印を出す
	_tag_a = move_toward(_tag_a, 1.0, dt * 2.5)

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
			Player.Mode.SIT: learn("sit")
			Player.Mode.WALK:
				if _prev_mode == Player.Mode.RIDE:
					learn("getoff")
				elif _prev_mode == Player.Mode.SIT:
					learn("standup")
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
		Player.Mode.SIT:
			_hint("standup", ["F"], "standup")   # ロッジの席から立つ（移動キーでも立てる）


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
	# 雪に縫い留めたボタン（snow_buttons.gd）: 近くで向いていれば、F で裁ちばさみ
	var sbn = main.get("snow_buttons")
	if sbn and not p.rooted():
		var nb = sbn.reachable(p)
		if nb != null:
			_hint("shears", ["F"], "shears", nb.at + Vector3.UP * 0.7)
	# ロッジの席（seats.gd）: 空いた席のそばで、席の方を向いていれば、F と座る絵を席の上に
	var si: int = p.seat_near()
	if si >= 0 and not p.rooted():
		_hint("sit", ["F"], "sit", p.seats.seat(si).pos + Vector3.UP * 0.85)
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
	# 暗いのにランタンが消えている: R で点ける（覚えるまで）
	var cr = main.get("craft")
	var dc := get_node_or_null("/root/DayCycle")
	if cr and dc and dc.has_method("daylight") and dc.daylight() < 0.4 and not known("lamp") \
			and not cr.lantern(p.id).is_empty() and not cr.lamp_on(p.id):
		_hint("lamp", ["R"], "lamp")
	# ソリが止まったまま遠い: Backspace で ふもとへ戻せる（ロッジの中では出さない）
	_still_t = _still_t + dt if sled.linear_velocity.length() < 0.3 else 0.0
	var outside: bool = main.lodge_weight(pos.x, pos.z) >= 1.0
	if _still_t > 6.0 and pos.distance_to(sled.global_position) > 35.0 and outside:
		_hint("return", ["Backspace"], "return")


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
		_ride_seen = _clock_now()
		_ride_sled = String(p.sled.name)
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
		var fp := flip_pose()
		_tag_view.rotation = Icons.wind_angle(1.0, -0.09, 0.05)
		_tag_view.position = Icons.wind_offset(1.0, 2.0 * ui()) + Vector2(0, -16.0 * ui() * fp[1])
		_tag_view.scale = Vector2(maxf(fp[0], 0.01), 1.0)
		_tag_view.queue_redraw()
	var allowed: bool = main.settings == null or main.settings.values.get("speedo", true)
	# 糸の上にボタンがあるあいだは、滑り終わり（snow_buttons.gd の ride_pay。0.5 m/s より遅いのが 1 秒）まで出しておく
	# （遅くなると先に消えて、糸の上のボタンが見えないまま財布へ飛んでしまうので）
	if not _spd_sewn.is_empty() and _clock_now() - _ride_seen < 3.0:
		on = true
	_exchange()
	if _reel > 0.0:   # 巻き取っているあいだは出しておく
		_reel = maxf(0.0, _reel - dt)
		on = true
		_spd_spin -= dt * 18.0   # ボビンが逆に回って糸を巻き取る
		if _reel <= 0.0:
			_spd_sewn.clear()
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
	if not on and _spd_a <= 0.0 and _reel <= 0.0:
		_spd_sewn.clear()


## 滑った距離と速さのボタン（snow_buttons.gd）。自分が乗っているソリのことだけ:
##   ride_mark 滑った距離・速さの分が一つ分たまった・コンボの節目（真鍮） → 糸の上にボタンが一つ、ぽんと縫い込まれる（真鍮はボビンも跳ねる）
##   ride_pay  一回の滑りが終わった → 縫い目の糸がくるくる巻き取られる。そのあいだ、糸の上のボタンが上から順にぽんぽん財布へ飛ぶ
func _on_buttons(ev: Dictionary) -> void:
	var p = main.player if main else null
	# 自分が乗っている（か、さっきまで乗っていた）ソリのことだけ。米袋をしまうとソリは消えるので、名前で覚えておいた方と比べる
	if p and ev.kind == "ride_carry":   # 斜面のボタンを倍率つきで取った: 持ち越しの端数（糸くず）が変わる
		if int(ev.who) == int(p.id):
			_lint_carry = float(ev.carry)
		return
	if p == null or _ride_sled == "" or _ride_sled != String(ev.get("sled", "")):
		return
	match ev.kind:
		"ride_mark":
			if p.mode == Player.Mode.RIDE:
				var look := String(ev.get("look", "brass"))
				_spd_sewn.append({"d": _spd_dist, "look": look, "claimed": false, "off": false, "mk": -1.0, "into": -1, "pk": 1.0, "t": -1.0})
				if look != "wood":
					_spd_pop = 1.0
				var audio = main.get_node_or_null("Audio")
				if audio:
					audio.stitch(look)   # 糸に縫い付いて積もる、ぷつっ・ころん（真鍮は、きらっ）
		"ride_lint":
			if p.mode == Player.Mode.RIDE:
				_lint_frac = float(ev.frac)
		"ride_pay_one":
			# 自分の分（止まったとき・途中で降りたとき）: 糸を巻き取って、糸の上のボタンを財布へ。端数は次の滑りへ持ち越す
			if int(ev.who) == int(p.id):
				_lint_carry = float(ev.get("carry", 0.0))
				_lint_frac = 0.0
				_exchange(true)   # 縫い縮まっている途中なら、すぐ済ませる（財布へ飛ぶボタンを決める前に）
				_reel_t = maxf(REEL_T, 1.1 + sewn_looks().size() * 0.065)
				_reel = _reel_t


## 巻き取りの進み 0〜1（巻き取っていなければ 0）
func _clock_now() -> float:
	return Time.get_ticks_msec() / 1000.0


func reel_k() -> float:
	return 1.0 - _reel / _reel_t if _reel > 0.0 else 0.0


## 両替を進める。縫い縮まり中なら進み mk を動かし、済んだら 10 個を上の素材 1 個にする（いちばん古い 1 個の所に）。
## 縫い縮まっていなければ、同じ素材が EXCHANGE_N 個たまっているか見て始める。now が true なら、残りを全部すぐ済ませる
## （巻き取りの前。音は鳴らす）。財布へ飛ぶ番が決まったあと（claimed がある）は両替しない
func _exchange(now := false) -> void:
	var t := _clock_now()
	for guard in 12:
		if _merge_t0 >= 0.0:
			var k := 1.0 if now else clampf((t - _merge_t0) / EXCHANGE_T, 0.0, 1.0)
			var group: Array = []
			for e in _spd_sewn:
				if e.mk >= 0.0:
					e.mk = k
					group.append(e)
			if k < 1.0:
				return
			# 済んだ: 10 個を取り除き、いちばん古い所に上の素材を 1 個
			var at: int = _spd_sewn.find(group[0])
			var nl: String = NEXT_LOOK[group[0].look]
			var d: float = group[0].d
			for e in group:
				_spd_sewn.erase(e)
			_spd_sewn.insert(at, {"d": d, "look": nl, "claimed": false, "off": false, "mk": -1.0, "into": -1, "pk": 0.0, "t": t})
			_merge_t0 = -1.0
			var audio = main.get_node_or_null("Audio") if main else null
			if audio:
				audio.exchange(nl)   # チン（上の素材の音）ときらっ
		for e in _spd_sewn:   # 変わってできたボタンの、ぽんとふくらむきらめき
			if e.t >= 0.0:
				e.pk = clampf((t - e.t) / 0.6, 0.0, 1.0)
		if _spd_sewn.any(func(e): return e.claimed):
			return
		var started := false
		for look in NEXT_LOOK:
			var same: Array = _spd_sewn.filter(func(e): return e.look == look and not e.off and e.mk < 0.0)
			if same.size() >= EXCHANGE_N:
				var into: int = _spd_sewn.find(same[0])
				for e in same.slice(0, EXCHANGE_N):
					e.mk = 0.0
					e.into = into
				_merge_t0 = t
				started = true
				break
		if not started or not now:
			return


## 糸の上の、まだ財布へ飛んでいないボタンの素材の並び（上＝あとで縫い込んだものから）
func sewn_looks() -> Array:
	var out := []
	for i in range(_spd_sewn.size() - 1, -1, -1):
		var e: Dictionary = _spd_sewn[i]
		if not e.off and not e.claimed:
			out.append(e.look)
	return out


## 糸の上の、まだ財布へ飛んでいないボタンの値打ちの合計
func sewn_value() -> int:
	var n := 0
	for look in sewn_looks():
		n += int(LOOK_VALUE[look])
	return n


## 財布へ飛ばす糸の上のボタンを一つ選ぶ（素材 look の、まだ選ばれていないうち、いちばん上＝あとで縫い込んだもの）。番号（なければ -1）
func sewn_claim(look: String) -> int:
	for i in range(_spd_sewn.size() - 1, -1, -1):
		var e: Dictionary = _spd_sewn[i]
		if not e.claimed and e.look == look:
			e.claimed = true
			return i
	return -1


## 糸の上の i 番のボタンの、画面の場所
func sewn_screen(i: int) -> Vector2:
	var ps := Speedo.sewn_positions(Speedo.layout(speedo_box_now(), _spd_pop), _spd_dist, _spd_sewn, reel_k())
	return ps[i] if i >= 0 and i < ps.size() else Speedo.layout(speedo_box_now(), 0.0).c


## 糸の上の i 番のボタンが外れて、財布へ飛んでいった
func sewn_off(i: int) -> void:
	if i >= 0 and i < _spd_sewn.size():
		_spd_sewn[i].off = true


## ご褒美: ボビンがぽんと跳ね、糸がぱっと広がり、縫い目に小さな結び目ができる（speedo.gd が描く）
func _cheer() -> void:
	_spd_pop = 1.0
	_spd_knots.append(_spd_dist)


## 名札の束を作る: 自分の名札を付けたソリ（置いてある・畳んで持っている・帯の米袋）。持ち主のいないソリ（最初からあるソリ）に
## 最後に触ったときは、そのソリの札をロッジの名札として先頭に出す（自分のソリが一台もないときも）。
## 最後に触ったソリが変わったら、その札が前に来る。手でめくった札は、次に別のソリに触るまでそのまま
func _update_cards(dt: float, p: Node) -> void:
	var list: Array = []
	var craft = main.get("craft")
	var me: int = int(p.get("id")) if p else -1
	var mine = craft.tag_designs.get(me, 0) if craft else 0
	if craft and p:
		for s in craft.sleds.values():
			if is_instance_valid(s) and s.visible and int(s.get("owner_id")) == me:
				list.append({"sled": s, "item": {}, "design": mine, "key": "s%d" % s.get_instance_id()})
		var bag: Array = craft.bag(me)
		for i in bag.size():
			if bag[i] is Dictionary and bag[i].has("sled"):
				list.append({"sled": null, "item": bag[i], "design": mine, "key": "i%d" % i})
		var sacks: Array = craft.sacks.get(me, [])
		var out = craft.sack_out.get(me)
		for i in sacks.size():
			if i == int(craft.sack_sel.get(me, 0)) and out != null and is_instance_valid(out):
				continue   # 出している米袋は、置いてあるソリとして入っている
			list.append({"sled": null, "item": {"sled": "sack", "fabric": sacks[i].get("fabric", "")}, "design": mine, "key": "k%d" % i})
	var last = p.get("last_sled") if p else null
	var lodge: RigidBody3D = null
	if last != null and is_instance_valid(last) and last.visible and int(last.get("owner_id")) < 0:
		lodge = last
	elif list.is_empty() and p == null:
		lodge = main.sled   # あなたのいない確かめ用の場面
	if list.is_empty() and lodge == null:   # 自分のソリが 1 台もなく、ほかのソリにも触っていない: 自分の名札だけ（窓は空の丘）
		list.append({"sled": null, "item": {}, "design": mine, "key": "me", "empty": true})
	if lodge:
		var t = lodge.get("tag")
		list.push_front({"sled": lodge, "item": {}, "design": t if not (t is int and int(t) < 0) else 0, "key": "lodge%d" % lodge.get_instance_id()})
	cards = list
	# 最後に触ったソリの札
	var lk := ""
	if last != null and is_instance_valid(last) and last.visible:
		lk = ("lodge%d" if int(last.get("owner_id")) < 0 else "s%d") % last.get_instance_id()
	elif p and not (p.get("last_item") as Dictionary).is_empty():
		for c in list:
			if c.item == p.last_item:
				lk = c.key
				break
	var idx := _index_of(_card_key)
	_card = idx if idx >= 0 else clampi(_card, 0, maxi(cards.size() - 1, 0))
	if lk != _last_key:
		_last_key = lk
		var li := _index_of(lk)
		if li >= 0:
			_select(li, false)
	if not cards.is_empty():
		_card_key = cards[_card].key
	_flip = maxf(0.0, _flip - dt / FLIP_LEN)
	if _flip < 0.5 or _index_of(_shown_key) < 0:
		_shown_key = _card_key
	_flip_hold = maxf(0.0, _flip_hold - dt)


func _index_of(key: String) -> int:
	for i in cards.size():
		if cards[i].key == key:
			return i
	return -1


## 札をめくる（manual なら矢印キーで手で。しばらく遠くのソリの札でも出しておく）
func _select(i: int, manual: bool) -> void:
	if cards.is_empty():
		return
	i = posmod(i, cards.size())
	if manual:
		_flip_hold = FLIP_HOLD
	if i == _card and _card_key == cards[i].key:
		return
	_flip_dir = 1 if i > _card or (i == 0 and _card == cards.size() - 1) else -1
	_shown_key = _card_key
	_card = i
	_card_key = cards[i].key
	_flip = 1.0


## 前に見えている札（めくっている途中は、半分まで前の札）
func shown_card() -> Dictionary:
	var i := _index_of(_shown_key)
	if i < 0:
		i = _card
	return cards[i] if i < cards.size() else {}


## めくる動き（12 コマで刻む）: 札が左の縁を支点に細くなって裏返り、次の札が開く。少し持ち上がる
func flip_pose() -> Array:
	var f := floorf((1.0 - _flip) * FLIP_LEN * 12.0) / maxf(FLIP_LEN * 12.0, 1.0) if _flip > 0.0 else 1.0
	return [absf(cos(f * PI)), sin(f * PI)]   # [横の縮み, 持ち上がり（0〜1）]


## 立体の板を置く: 名札・吊るした札・ワッペン・ボビン・右下の小窓の刺繍枠・持ち物の列。
## 風の揺れは、板を支点のまわりに傾ける形でかける（平らな絵のときと同じ値）
func _update_plates() -> void:
	var u := ui()
	plates.begin()
	plates.moving = Icons.wind > 0.001 or _spd_a > 0.01
	if _tag_a > 0.01:
		var tr: Rect2 = _view.tag_rect(u)
		var piv := Vector2(tr.position.x, tr.get_center().y)
		for k in range(1, 3):   # 束の後ろの札（あれば。後ろほど奥へ）
			if k < cards.size():
				var bo: Array = _view.back_offset(u, k)
				plates.plate("tagb%d" % k, _painter.bind("tagback:%d" % k), tr, 12.0 * u, 7.0 * u, "paper", piv,
					[1.0 + k, -0.09, 0.05, 2.0 * u], _tag_a, bo[1], 1.0, bo[0], 0.03 * k, 3 - k)
		var fp := flip_pose()
		plates.plate("tag", _painter.bind("tag"), tr, 12.0 * u, 8.0 * u, "paper", piv,
			[1.0, -0.09, 0.05, 2.0 * u], _tag_a, 0.0, fp[0], Vector2(0, -16.0 * u * fp[1]), 0.0, 3)
	if _spd_a > 0.01:   # 速さの表示: 立体のボビンと、縫い目を縫うフェルトのリボンの板（ボビンから吊るす）
		var g := Speedo.layout(speedo_box_now(), _spd_pop)
		# 回る向き: 糸はボビンの左下から下へ出ていくので、左側が下へ動く向き（画面で反時計回り）に回して糸を送り出す。
		# 平らな絵（speedo.gd の _spool）と同じ向き。板の 3D は +Z まわりの正の角が画面で反時計回り（2026-10-30 代表「糸巻きの回転方向、逆だね？」）
		plates.model("bobbin", "res://props/hud/hud_bobbin.glb", g.c, g.r / 0.5, _spd_spin, [4.0, 0.0, 0.03, 2.0 * u], _spd_a)
		var rb: Rect2 = g.ribbon
		plates.plate("ribbon", _painter.bind("ribbon"), rb, 8.0 * u, 5.0 * u, "felt", Vector2(rb.get_center().x, rb.position.y),
			[6.0, 0.05, 0.05, 1.5 * u], _spd_a)
	plates.end()


var _hoop_tex: ImageTexture

## 刺繍枠の絵（縮めて描くので、ミップマップを作っておく）
func hoop_texture() -> ImageTexture:
	if _hoop_tex == null:
		var t := load("res://props/hud/hoop.png") as Texture2D
		if t == null:
			return null
		var img := t.get_image()
		img.decompress()
		img.generate_mipmaps()
		_hoop_tex = ImageTexture.create_from_image(img)
	return _hoop_tex


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


## 速さの表示の置き場（画面の px）: 画面の左側の縦の帯。左上の確かめ用の札の下から、左下の名札の束の上まで
func speedo_box() -> Rect2:
	var u := ui()
	var vs := _view.size
	var top := 26.0 * u + debug_rect(u).size.y + 18.0 * u        # 確かめ用の札の下（出していなくても同じ所）
	var bottom: float = (_view.tag_rect(u) as Rect2).position.y - 30.0 * u         # 名札（束の後ろの札の縁も）の上
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
			Speedo.draw_stitches(self, g, Speedo.level_of(hud._spd), hud._spd_spin, hud._spd_dist, hud._spd_color, hud._spd_knots, 1.0, false,
					hud._spd_sewn, hud.reel_k(), hud.lint())
			Icons.printing = false
			return
		if part.begins_with("tagback:"):   # 束の後ろの札（名札の柄だけ。中の窓は無地）
			var k := int(part.substr(8))
			var c: Dictionary = hud.cards[posmod(hud._card + k, hud.cards.size())] if not hud.cards.is_empty() else {}
			if hud._tag_a > 0.01 and not c.is_empty():
				SledTags.draw_tag(self, tag_rect(u), c.design, hud._tag_a, false, true)
			Icons.printing = false
			return
		if part == "tag":   # 名札だけを描く入れ物（風で、この入れ物ごと傾ける。名札の絵は中で描く向きを自分で変えるので）
			if hud._tag_a > 0.01:
				var tr := tag_rect(u)
				if hud.plates == null:   # 平らなとき: 束の後ろの札の縁を、前の札の後ろにずらして描く
					for k in range(mini(hud.cards.size() - 1, 2), 0, -1):
						var c: Dictionary = hud.cards[posmod(hud._card + k, hud.cards.size())]
						SledTags.draw_tag(self, Rect2(tr.position + back_offset(u, k)[0], tr.size), c.design, hud._tag_a, false, true)
				_draw_tag(u, hud._tag_a)
				Icons.flap(self, tr.position + Vector2(tr.size.x, 0), Vector2.LEFT, Vector2.DOWN, 22.0 * u, 1.0)
			Icons.printing = false
			return
		for id in hud._hints:
			var h: Dictionary = hud._hints[id]
			if h.a < 0.02 or not h.get("shown", false):
				continue
			Icons.badge(self, h.keys, h.icon, h.draw_at, h.draw_sz, ease(h.a, 0.5))   # 操作のための表示なので、平らで、風でも揺らさない
		_draw_hoop(u)
		_draw_pip_back(u)
		if hud._spd_a > 0.01:
			_draw_speedo(u)
		if hud.debug_on and not hud._dbg.is_empty():
			_draw_debug(u)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		if hud.main.settings and hud.main.settings.is_open:
			_draw_card(u)

	## 左下の札: 自分の名札（形・色・柄・素材は自分の名札のデザイン）の中に無地の窓を敷き（sled_tags.gd の window_rect）、
	## その窓に、いま関わっているソリ（最後に触ったソリ）の丘の断面・印・人の形・糸の矢印を描く（_draw_tag_info）。
	## 左下の名札の場所（_draw_tag と同じ）
	func tag_rect(u: float) -> Rect2:
		var w := 262.0 * u * TAG_K
		var h := 146.0 * u * TAG_K
		return Rect2(18.0 * u, size.y - h - 18.0 * u, w, h)

	## 束の後ろの k 枚目の札（右上へずらし、少し傾ける）
	func back_offset(u: float, k: int) -> Array:
		return [Vector2(7.0, -8.0) * u * k, -0.035 * k]

	func _draw_tag(u: float, a: float) -> void:
		var sled: RigidBody3D = hud._tag_sled
		var item: Dictionary = hud._tag_item
		var r := tag_rect(u)
		var idx = hud.shown_card().get("design", 0)   # その札の名札（自分の名札か、ロッジの名札）
		u *= TAG_K
		# 名札の外の影と縁: 雪の白・空の青・ロッジの茶色のどれの上でも、名札の形が浮いて見えるように
		var pts := SledTags.outline(r, SledTags.design(idx).shape)
		var halo := Geometry2D.offset_polygon(pts, 1.6 * u, Geometry2D.JOIN_ROUND)
		if halo.size() > 0:
			var sh := PackedVector2Array()
			for q in halo[0]:
				sh.append(q + Vector2(1.2, 2.2) * u)
			draw_colored_polygon(sh, Color(Icons.SHADOW, 0.30 * a))
			var rim := halo[0].duplicate()
			rim.append(halo[0][0])
			draw_polyline(rim, Color(Icons.SHADOW, 0.35 * a), 1.2 * u, true)
		# 名札の中に無地の窓を敷き、情報はその上に描く（名札の柄は、窓のまわりの縁として見える）
		var win := SledTags.draw_tag(self, r, idx, a, false, true)
		# 窓の中の絵は 210 × 120（u）の枠で組み、窓に収まるよう縮めて真ん中に置く
		var fw := 210.0 * u
		var fh := 120.0 * u
		var k := minf(minf(win.size.x / fw, win.size.y / fh), 1.06)
		draw_set_transform(win.get_center() - Vector2(fw, fh) * k / 2.0, 0.0, Vector2(k, k))
		_draw_tag_info(u, a, fw, fh, sled, item)
		draw_set_transform(Vector2.ZERO)
		Icons.screen()

	## 窓の中の絵（左上を原点に fw × fh）: 丘の断面の上をソリの印が進み、ふもとからの赤い糸が登った分だけ伸びる。
	## 下に、そのソリにいる人の形と、押している人の数だけの糸の矢印。窓の地はいつも明るいので、線は濃く、印には白い縁
	func _draw_tag_info(u: float, a: float, fw: float, fh: float, sled: RigidBody3D, item: Dictionary) -> void:
		var main: Node3D = hud.main
		# 丘の断面（頂上から PROFILE_R までの右半分と、頂上の向こうを少し）
		var x0 := 6.0 * u
		var x1 := fw - 6.0 * u
		var yb := 64.0 * u
		var yt := 7.0 * u
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
		Icons.patch(self, mound, Color(0.74, 0.83, 0.95), a, false)
		Icons.thread(self, prof, Icons.THREAD, 1.5 * u, a)
		# 頂上の旗とふもとのロッジ
		var top := Vector2(to_x.call(0.0), to_y.call(main.HILL_H))
		Icons.thread(self, PackedVector2Array([top, top - Vector2(0, 16) * u]), Icons.WOOD.darkened(0.2), 1.6 * u, a)
		Icons.patch(self, PackedVector2Array([top - Vector2(0, 16) * u, top + Vector2(11, -12.5) * u, top - Vector2(0, 9) * u]), Icons.RED, a, false)
		var lodge := Vector2(x1 - 6.0 * u, yb)
		Icons.patch(self, PackedVector2Array([lodge + Vector2(-7, 0) * u, lodge + Vector2(7, 0) * u, lodge + Vector2(7, -8) * u,
			lodge + Vector2(0, -14) * u, lodge + Vector2(-7, -8) * u]), Icons.WOOD, a, false)
		draw_rect(Rect2(lodge + Vector2(-2.2, -6.5) * u, Vector2(4.4, 4.0) * u), Color(1.0, 0.72, 0.30, a))
		if hud.shown_card().get("empty", false):   # 自分のソリがまだない: 空の丘だけ
			return
		# ソリの印と、ふもとからソリまでの赤い糸（畳んでいれば、持っている人の所）
		var sp: Vector3 = sled.global_position if sled else (main.player.global_position if main.player else Vector3.ZERO)
		var sr := clampf(Vector2(sp.x, sp.z).length(), 0.0, PROFILE_R)
		var climbed := PackedVector2Array()
		for i in 25:
			var rr := lerpf(PROFILE_R, sr, i / 24.0)
			climbed.append(Vector2(to_x.call(rr), to_y.call(main.hill(rr, 0.0)) - 1.0 * u))
		Icons.thread(self, climbed, Icons.RED, 2.2 * u, a)
		var mark := Vector2(to_x.call(sr), to_y.call(main.hill(sr, 0.0)))
		var slope := atan2(to_y.call(main.hill(sr + 1.0, 0.0)) - to_y.call(main.hill(sr - 1.0, 0.0)), to_x.call(sr + 1.0) - to_x.call(sr - 1.0))
		var mc := mark + Vector2(0, -6.0 * u).rotated(slope)
		draw_circle(mc, 10.5 * u, Color(1, 1, 1, 0.8 * a))   # 印の白い縁（丘の線や雪から浮かせる）
		Icons._o = mc
		Icons._s = 0.5 * u
		if sled:
			Icons.sled_side(self, Vector2.ZERO, 1.0, a, slope, true)   # 前は左（頂上）
		else:   # 畳んだ包み
			Icons.patch(self, Icons.xf(Icons.rr(-7, -7, 14, 14, 2), PI / 4, Vector2(0, 2), 1.0), preload("res://fabrics.gd").color(item.get("fabric", "red")), a, false)
		# いまソリにいる人と、押している人の数だけの糸の矢印
		var px := 14.0 * u
		var py := fh - 29.0 * u   # 人形の箱の中心（足もとが窓の下の縁の少し上）
		var ppl: Array = hud._people
		if ppl.is_empty():
			Icons.icon(self, "person", Vector2(px, py), 70.0 * u, 0.3 * a, Icons.PAPER_EDGE.darkened(0.2))
			px += 30.0 * u
		for x in ppl:
			var pop: float = hud._pop.get(x[0], 0.0)
			var sz := 70.0 * u * (1.0 + 0.35 * sin(pop * PI))
			var lift := 6.0 * u * sin(pop * PI)
			Icons.icon(self, "person" if x[1] == "stand" else "person_sit", Vector2(px, py - lift), sz, a * (1.0 if x[3] else 0.5), x[2])
			px += 30.0 * u
		if sled == null and not item.is_empty():
			# 畳んだソリは形がわからないので、広げた姿をくるくる回して見せる（タグの窓）
			var tw := 58.0 * u
			var tr := Rect2(Vector2(fw - tw - 4.0 * u, fh - tw - 2.0 * u), Vector2(tw, tw))
			Icons.screen()
			Icons.patch(self, Icons.rr(tr.position.x, tr.position.y, tw, tw, 8.0 * u), Color(0.86, 0.90, 0.97), a, true, Icons.THREAD)
			draw_texture_rect(SledTags.turntable(item.get("sled", "mid"), item.get("fabric", "")), tr.grow(-3.0 * u), false, Color(1, 1, 1, a))
			return
		Icons.screen()
		var n: int = mini(hud._n_push, 5)
		px += 8.0 * u
		for i in n:
			var wave := 0.5 + 0.5 * sin((hud._flow - i * 0.3) * TAU)
			var big: float = 1.0 + 0.5 * hud._chev_pop * float(i == n - 1)
			Icons.chevron(self, Vector2(px + i * 16.0 * u, py + 6.0 * u), 20.0 * u * big, Icons.THREAD, a * (0.55 + 0.45 * wave), 0.0, 3.0 * u)

	## 乗って滑っているときの速さ（ボビン。数字は出さない）
	func _draw_speedo(u: float) -> void:
		var e := ease(hud._spd_a, 0.6)
		if e > 0.01:
			var g := Speedo.layout(hud.speedo_box_now(), hud._spd_pop)
			var k := Speedo.level_of(hud._spd)
			if hud.plates == null:   # 平らなとき: リボンは糸巻きから吊るして揺れる。ボビンは小刻みに
				var rb: Rect2 = g.ribbon
				draw_set_transform_matrix(Icons.wind_xform(Vector2(rb.get_center().x, rb.position.y), 6.0, 0.05, 0.05, 1.5 * u))
				Speedo.draw_stitches(self, g, k, hud._spd_spin, hud._spd_dist, hud._spd_color, hud._spd_knots, e, true, hud._spd_sewn, hud.reel_k(), hud.lint())
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

	## 右下の小窓の刺繍枠: Blender で本物らしく作って正面から撮った絵（props/build_hud.py の --hoop-png）を、画面の解像度のまま重ねる
	## （2026-10-29 代表「刺繍小窓の刺繍枠をリアルな木枠にしてほしい。いまなんかぼやぼやしてモチーフが伝わらない」）。
	## 絵の内の輪の半径は 228.6 px（640 px を 2.8 単位で撮った 1 単位）。窓の縁に少しかぶせる。風では小窓と同じだけ揺れる
	func _draw_hoop(u: float) -> void:
		var sc = hud.main.get("self_cam")
		if sc == null or not is_instance_valid(sc) or sc.get("hidden") or sc.get("_frame") == null:
			return
		sc.plain_frame = true   # 小窓の側は、赤い糸の縁取りだけ
		var fr: Control = sc._frame
		var c := fr.position + fr.size / 2.0 - Icons.wind_offset(5.0, 2.5 * sc.ui())   # 小窓のずれを除いた真ん中（揺れは下で同じだけかける）
		var tex: Texture2D = hud.hoop_texture()
		if tex == null:
			return
		var s := (fr.size.x / 2.0 + 3.0 * u) / 228.6
		var sz := Vector2(tex.get_width(), tex.get_height()) * s
		draw_set_transform_matrix(Icons.wind_xform(c, 5.0, 0.0, 0.03, 2.5 * u))
		draw_texture_rect(tex, Rect2(c - sz / 2.0 + Vector2(3.0, 5.0) * u, sz), false, Color(Icons.SHADOW, 0.32))   # 落ち影
		draw_texture_rect(tex, Rect2(c - sz / 2.0, sz), false)
		draw_set_transform_matrix(Transform2D.IDENTITY)

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
			[["F"], "grab"], [["F"], "rope"], [["E"], "ride"], [["Backspace"], "return"],
			[["mouse_r"], "point"], [["C"], "view"], [["V"], "pip_cycle"], [["P"], "pip_off"],
			[["Esc"], "settings"], [["Left", "Right"], "tag_stack"],
		]
		# ピンチ: 三人称のカメラの距離（一人称で閉じ続けると三人称へ）。視野角と人形の画面の高さは設定からだけ
		rows.append([["mouse_pinch"], "cam_dist" if hud.main.player and hud.main.player.third else "view"])
		if hud.main.get("emotes") != null:
			rows += [[["Tab"], "ring"], [["1", "2", "3"], "ring"], [["4", "5", "6", "7"], "voice"], [["B"], "breath"]]
		else:
			rows += [[["Q"], "wave"], [["G"], "voice"]]
		if hud.main.get("sewing") != null:
			rows.append([["T"], "needle"])
		if hud.main.get("craft") != null:   # 工房: 売り子に F、ミシンに T でセット、G で畳む、左クリックで広げる、ホイールで持ち替え
			rows += [[["F"], "shop"], [["F"], "set"], [["N"], "sack"], [["R"], "lamp"], [["I"], "gear"], [["mouse_wheel", "mouse_pan"], "hand"], [["Z"], "hand"]]
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
