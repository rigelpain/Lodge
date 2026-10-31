extends CanvasLayer
## 画面の表示（HUD）。文字を使わず、アイコン・矢印・形で伝える。決まりと場面ごとの絵は design/hud.md。
##   左下: ソリの札。最後に触ったソリ（つかむ・紐・乗る・広げる）の名札の柄で描く（sled_tags.gd。名札はソリごと）。
##         上は丘の断面: ソリの印が動き、登った分だけ赤い糸が伸びる。
##         下の左はそのソリがゆっくり回る図（12 コマの刻みで 12 秒で 1 周）。いま触れている人・乗っている人を、そのソリの上の
##         実際の所に 3D の人型で乗せて、いっしょに回す（座る・押す・紐で引く・つかむ。人型はキャラの色、頭の上に名前）。
##         下の右に王冠を載せた持ち主（名札を持っている人。ロッジのソリは家、名札を外したソリは空の輪）。
##         （2026-10-31 代表「タグにはそのタグが付いたソリがくるくる 360° 回転するアニメーションと、誰がインタラクトしてるか、
##         乗ってるか、だれがオーナーか」「押してる乗ってる表示は回転してるソリに、乗ってる位置押してる位置実態に合わせて」
##         「オーナーは王冠表示」「シンプルな人型アイコンにキャラカラー、プレイヤー名を頭の上に」）
##         そのソリを畳んで持っていれば、印は持っている人の所で、回る図に人は乗せない
##   物の上: 近づいたときだけ、キーの形と動きの絵のワッペン。3 回したら（覚えたら）もう出さない
##   画面の下のまんなか: つかんでいる・紐を持っている・乗っているときの手引き。ほかの人のそばでは身ぶりの手引き
##   Esc: 設定の画面の左に、すべてのキーと絵を並べた札
##   確かめ用: --hud-debug か設定の「確かめ用の数字」で、左上の隅に小さな文字で fps と通信の速さ（開発用なので文字でよい）。
##         押している人数は左下の札、速さは滑るときの糸巻き（speedo.gd）が伝える
## 絵は hud_icons.gd。ミシン（main.sewing）とエモート（main.emotes）は、あればその案内も出す。

const Icons := preload("res://hud_icons.gd")
const Speedo := preload("res://speedo.gd")
const RideWind := preload("res://ride_wind.gd")
const Plates := preload("res://hud_plates.gd")
const SledTags := preload("res://sled_tags.gd")
const PersonIcon := preload("res://person_icon.gd")
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
## コンボ（snow_buttons.gd の ride_combo）: 段が上がるたびに、リボンの左の縁に結び目が一つずつ増え、糸が少し明るくなる。
## 切れたら、結び目がほどけてふっと消える（speedo.gd の draw_combo）。{t（結んだ時刻）, off（ほどけ始めた時刻。まだなら -1）}
var _combo_knots: Array = []
const COMBO_TINT := 0.1       # 一段ごとに、糸の色を明るい山吹へ寄せる割合（5 段で頭打ち）
const UNTIE_T := 0.7          # ほどけて消えるまで (s)

## 糸の色のもと: ソリのメインカラーを、コンボの段の数だけ明るく
func thread_base() -> Color:
	var n := _combo_knots.filter(func(e): return float(e.off) < 0.0).size()
	return _spd_color.lerp(Speedo.BRIGHT, minf(COMBO_TINT * n, 0.5))


## コンボの結び目をほどく（切れた・滑り終わった）
func _untie() -> void:
	for e in _combo_knots:
		if float(e.off) < 0.0:
			e.off = _clock_now()

func lint() -> float:
	return _lint_frac + _lint_carry
var _reel := 0.0              # 滑り終わって、縫い目の糸を巻き取っている残り (s)。糸の上のボタンは財布へ飛ぶ（craft_ui.gd）
var _reel_t := 1.6            # この巻き取りの長さ (s)。ボタンが多いほど長い
var _ride_seen := -99.0       # 最後に乗っていた時刻（止まってすぐ降りても、巻き取りを見せる）
var _ride_sled := ""          # 最後に乗っていたソリの名前（米袋をしまってソリが消えても、自分の分の出来事を見分ける）
const REEL_T := 1.6
var _dbg := {}                # 左上の確かめ用の数字（_debug_values）
var _tag_a := 0.0
var _people: Array = []       # 札のソリにいる人 {who, pose（"stand" / "push" / "pull" / "sit"）, at（ソリの座標）, col, name, strong}
var _push_t := {}             # 人 → 押す姿の残り (s)。押した瞬間に入れ、離しても少し残す（1 コマごとのちらつきを消す）
var _pop := {}                # 人 → 跳ねの残り（1→0）
var _hints := {}              # 案内 → {keys, icon, world, scr, a, on, bottom}
var _order: Array = []        # いまのコマの、画面の下の案内の並び
var _prev_mode := -1
var _work_t := 0.0            # 押す・引く・体重をかけた長さ（1 回に数えるまで）
var _meet_t := 0.0
var _meet_n := 0
var _meeting := false
var _still_t := 0.0
var _seen_back := false
const TAG_K := 1.82           # 名札の大きさ（2026-10-29 代表「名札もっと大きくていい」。2026-10-31 回るソリと人を載せるので 1.3 倍に。
                              # HUD の大きさの設定にも合わせて変わる）
const FLIP_LEN := 0.42        # 札をめくる長さ (s)
const FLIP_HOLD := 6.0        # 手でめくったあと、遠くのソリの札でも出しておく長さ (s)
var cards: Array = []         # 名札の束: [{sled, item, design, key}]。自分が持ち主のソリ（置いた・畳んで持つ）と、持ち主のいないソリに
                              # 触ったときはそのソリの札（ロッジの名札か、名札を外したソリは無地）を先頭に（_update_cards）。米袋は入れない
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
		_dbg = _debug_values()
	_update_speedo(dt, p, menu)
	if plates:
		_update_plates()
	_view.queue_redraw()


# ---- ソリの札 ------------------------------------------------------------------------

func _update_people(dt: float, sled: RigidBody3D, _p: Node3D) -> void:
	if sled == null:   # 畳んだソリ: 回る図に人は乗せない
		_people = []
		return
	var list: Array = []
	var who: Array = sled.holders.keys()
	if sled.rope_holder and not who.has(sled.rope_holder):
		who.append(sled.rope_holder)
	for w in who:
		if not is_instance_valid(w):
			continue
		# 押しているかは、このコマ押した人（sled._pushed_by）で一人ずつ見る。押している人は前のめりの「押す」姿、
		# 紐で引いている人は「引く」姿、つかんでいるだけの人は立った姿で薄く
		var rope: bool = w == sled.rope_holder
		if sled._pushed_by.has(w) or (rope and w.get("pulling")):
			_push_t[w] = 0.35
		var pushing: bool = _push_t.get(w, 0.0) > 0.0
		var at: Vector3 = sled.to_local(w.global_position)
		at.y = 0.0   # 足もとは雪の上
		list.append({"who": w, "pose": ("pull" if rope else "push") if pushing else "stand", "at": at,
			"col": _color_of(w), "name": _name_of(w), "strong": pushing or sled.is_dragged(w)})
	for k in _push_t.keys():
		_push_t[k] -= dt
		if _push_t[k] <= 0.0 or not who.has(k):
			_push_t.erase(k)
	for w in sled.riders:
		if is_instance_valid(w):
			list.append({"who": w, "pose": "sit", "at": sled.to_local(w.global_position), "col": _color_of(w), "name": _name_of(w), "strong": true})
	var before: Array = _people.map(func(x): return x.who)
	for x in list:
		if not before.has(x.who):
			_pop[x.who] = 1.0
	_people = list
	for k in _pop.keys():
		_pop[k] = maxf(0.0, _pop[k] - dt * 2.5)


## その人のキャラの色（装備の画面で決める。craft.gd の colors）。工房がなければ、前の決まり（あなたは赤、仲間は藍・からし）
func _color_of(w: Node) -> Color:
	var craft = main.get("craft")
	var id: int = int(w.get("id")) if w and w.get("id") != null else -1
	if craft and craft.colors.has(id):
		return craft.color_of(id)
	if w == main.player:
		return Icons.RED
	return Icons.NAVY if int(w.get("side")) >= 0 else Icons.MUSTARD


## その人の名前（装備の画面で決める。craft.gd の names）
func _name_of(w: Node) -> String:
	var craft = main.get("craft")
	var id: int = int(w.get("id")) if w and w.get("id") != null else -1
	return craft.name_of(id) if craft else ""


## 札のソリの持ち主の番号（-1 は持ち主なし）。畳んで持っている包みは、持っている人（あなた）
func tag_owner() -> int:
	if _tag_sled:
		return int(_tag_sled.get("owner_id"))
	if not _tag_item.is_empty() and SledTags.has_tag(_tag_item.get("tag", -1)) and main.player:
		return int(main.player.get("id"))
	return -1


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
	# 2 階の衣装掛け: F で人形を選び直す（ハンガーと入れ替わる矢印の絵）
	if p.has_method("wardrobe_near") and p.wardrobe_near() and not p.shopping:
		_hint("wardrobe", ["F"], "wardrobe", main.wardrobe.global_position + Vector3.UP * 2.3)

	# 名札の結び目のそば: G の長押しで、自分のソリの名札を外す・名札入れの名札を持ち主のいないソリに付ける
	var tt: Array = p.tag_target() if p.has_method("tag_target") else []
	if not tt.is_empty():
		_hint(tt[1], ["G"], tt[1], tt[0].tag_point() + Vector3.UP * 0.45)

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
	var now := _clock_now()
	_combo_knots = _combo_knots.filter(func(e): return float(e.off) < 0.0 or now - float(e.off) < UNTIE_T + 0.3)
	if not on and _spd_a <= 0.0:
		_untie()
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
		"ride_combo":
			if p.mode == Player.Mode.RIDE:
				var audio = main.get_node_or_null("Audio")
				if int(ev.n) > 0:
					_combo_knots.append({"t": _clock_now(), "off": -1.0})
					_spd_pop = 1.0
				elif _combo_knots.any(func(e): return float(e.off) < 0.0):
					_untie()
				else:
					audio = null
				if audio:
					audio.combo(int(ev.n))   # 一段ずつ上がる木琴と鈴・切れたら短く下がる 2 音
		"ride_pay_one":
			# 自分の分（止まったとき・途中で降りたとき）: 糸を巻き取って、糸の上のボタンを財布へ。端数は次の滑りへ持ち越す
			if int(ev.who) == int(p.id):
				_lint_carry = float(ev.get("carry", 0.0))
				_lint_frac = 0.0
				_untie()
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
	if craft and p:   # 名札はソリごと（2026-10-31 代表「タグはソリごとにデザインできるべき」）。米袋には名札がないので札にしない
		for s in craft.sleds.values():
			if is_instance_valid(s) and s.visible and int(s.get("owner_id")) == me and s.kind != "sack":
				list.append({"sled": s, "item": {}, "design": s.tag, "key": "s%d" % s.get_instance_id()})
		var bag: Array = craft.bag(me)
		for i in bag.size():
			if bag[i] is Dictionary and bag[i].has("sled") and bag[i].sled != "sack":
				list.append({"sled": null, "item": bag[i], "design": bag[i].get("tag", -1), "key": "i%d" % i})
	var last = p.get("last_sled") if p else null
	var lodge: RigidBody3D = null
	if last != null and is_instance_valid(last) and last.visible and int(last.get("owner_id")) < 0 and last.get("kind") != "sack":
		lodge = last
	elif list.is_empty() and p == null:
		lodge = main.sled   # あなたのいない確かめ用の場面
	if list.is_empty() and lodge == null:   # 自分のソリが 1 台もなく、ほかのソリにも触っていない: 自分の名札だけ（窓は空の丘）
		list.append({"sled": null, "item": {}, "design": mine, "key": "me", "empty": true})
	if lodge:   # 持ち主のいないソリ: ロッジのソリはロッジの名札、名札を外したソリは無地（-1）
		list.push_front({"sled": lodge, "item": {}, "design": lodge.get("tag"), "key": "lodge%d" % lodge.get_instance_id()})
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


## 速さの表示の置き場（画面の px）: 画面の左側の縦の帯。上の端は前の確かめ用の札の下の所（256）のまま、左下の名札の束の上まで
func speedo_box() -> Rect2:
	var u := ui()
	var vs := _view.size
	var top := 256.0 * u
	var bottom: float = (_view.tag_rect(u) as Rect2).position.y - 30.0 * u         # 名札（束の後ろの札の縁も）の上
	return Rect2(22.0 * u, top, 126.0 * u, maxf(bottom - top, 200.0 * u))


## いまの置き場（出てくるときは、上からふわっと下りてくる）
func speedo_box_now() -> Rect2:
	var r := speedo_box()
	r.position.y -= (1.0 - ease(_spd_a, 0.6)) * 24.0 * ui()
	return r


## 左上の確かめ用の数字: fps と通信の往復の時間（ms。つながっていなければ -1）
## （2026-10-31 代表「押してる人数はタグで表示すべきだし、速度は糸巻き、fps や通信速度は残しましょう。もっと小さい HUD で間に合うはず」。
## 人数・高さ・速さ・いまの状態・覚えた案内の数は、札と糸巻きと手引きが伝えるので出さない）
func _debug_values() -> Dictionary:
	return {"fps": int(Engine.get_frames_per_second()), "ms": _net_ms()}


## 通信の往復の時間 (ms)。ENet でつながっている相手のうち、いちばん遅い相手。ひとりで遊んでいるときは -1
func _net_ms() -> int:
	var mp := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if mp == null or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or mp.host == null:
		return -1
	var ms := -1
	for pp in mp.host.get_peers():
		ms = maxi(ms, int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)))
	return ms


# ---- 描く ----------------------------------------------------------------------------

class View extends Control:
	var hud: Node
	var part := ""      # "tag" なら左下の名札だけ、"ribbon" なら速さの縫い目だけを描く（立体の板に重ねる印刷）

	func _draw() -> void:
		var u: float = hud.ui()
		Icons.printing = part != "" and hud.plates != null
		if part == "ribbon":
			var g := Speedo.layout(hud.speedo_box_now(), hud._spd_pop)
			Speedo.draw_stitches(self, g, Speedo.level_of(hud._spd), hud._spd_spin, hud._spd_dist, hud.thread_base(), hud._spd_knots, 1.0, false,
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
		_draw_tag_hold(u)
		_draw_hoop(u)
		_draw_pip_back(u)
		if hud._spd_a > 0.01:
			_draw_speedo(u)
		if hud.debug_on and not hud._dbg.is_empty():
			_draw_debug(u)
			draw_set_transform_matrix(Transform2D.IDENTITY)
		if hud.main.settings and hud.main.settings.is_open:
			_draw_card(u)

	## G の長押しの進み: 名札の結び目のまわりに、赤い糸の輪が満ちていく（満ちたら外れる・付く。player.gd の tag_hold）
	func _draw_tag_hold(u: float) -> void:
		var p = hud.main.player
		if p == null or float(p.get("tag_hold")) <= 0.0:
			return
		var tt: Array = p.tag_target()
		var cam := get_viewport().get_camera_3d()
		if tt.is_empty() or cam == null or cam.is_position_behind(tt[0].tag_point()):
			return
		var c := cam.unproject_position(tt[0].tag_point())
		var r := 22.0 * u
		draw_arc(c, r, 0.0, TAU, 40, Color(Icons.PAPER, 0.75), 6.0 * u, true)
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * float(p.tag_hold), 40, Icons.RED, 4.0 * u, true)

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

	## 窓の中の絵（左上を原点に fw × fh）。上の段は丘の断面: ソリの印が進み、ふもとからの赤い糸が登った分だけ伸びる。
	## 下の段の左は、そのソリがくるくる回る図に、いま触れている人・乗っている人を実際の所に乗せたもの（_draw_turn）。
	## 下の段の右は、王冠を載せた持ち主（_draw_owner）。窓の地はいつも明るいので、線は濃く、印には白い縁
	func _draw_tag_info(u: float, a: float, fw: float, fh: float, sled: RigidBody3D, item: Dictionary) -> void:
		var main: Node3D = hud.main
		# 丘の断面（頂上から PROFILE_R までの右半分と、頂上の向こうを少し）
		var x0 := 6.0 * u
		var x1 := fw - 6.0 * u
		var yb := 40.0 * u
		var yt := 6.0 * u
		var rmin := -14.0
		var to_x := func(rr: float) -> float: return lerpf(x0, x1, (rr - rmin) / (PROFILE_R - rmin))
		var to_y := func(hh: float) -> float: return lerpf(yb, yt, hh / main.HILL_H)
		var prof := PackedVector2Array()
		for i in 33:
			var rr := lerpf(rmin, PROFILE_R, i / 32.0)
			prof.append(Vector2(to_x.call(rr), to_y.call(main.hill(rr, 0.0))))
		var mound := prof.duplicate()
		mound.append(Vector2(x1, yb + 3.0 * u))
		mound.append(Vector2(x0, yb + 3.0 * u))
		Icons.screen()
		Icons.patch(self, mound, Color(0.74, 0.83, 0.95), a, false)
		Icons.thread(self, prof, Icons.THREAD, 1.4 * u, a)
		# 頂上の旗とふもとのロッジ
		var top := Vector2(to_x.call(0.0), to_y.call(main.HILL_H))
		Icons.thread(self, PackedVector2Array([top, top - Vector2(0, 12) * u]), Icons.WOOD.darkened(0.2), 1.4 * u, a)
		Icons.patch(self, PackedVector2Array([top - Vector2(0, 12) * u, top + Vector2(8.5, -9.5) * u, top - Vector2(0, 7) * u]), Icons.RED, a, false)
		var lodge := Vector2(x1 - 5.0 * u, yb)
		Icons.patch(self, PackedVector2Array([lodge + Vector2(-5.5, 0) * u, lodge + Vector2(5.5, 0) * u, lodge + Vector2(5.5, -6) * u,
			lodge + Vector2(0, -11) * u, lodge + Vector2(-5.5, -6) * u]), Icons.WOOD, a, false)
		draw_rect(Rect2(lodge + Vector2(-1.7, -5) * u, Vector2(3.4, 3.0) * u), Color(1.0, 0.72, 0.30, a))
		var tw := Rect2(Vector2(4.0, 46.0) * u, Vector2(150.0, 71.0) * u)   # 回る図の窓
		if hud.shown_card().get("empty", false):   # 自分のソリがまだない: 空の丘と、空の窓だけ
			Icons.screen()
			Icons.dashes(self, Icons.rr(tw.position.x, tw.position.y, tw.size.x, tw.size.y, 8.0 * u), Icons.PAPER_EDGE, 1.4 * u, 5.0 * u, 3.5 * u, a, true)
			return
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
		var mc := mark + Vector2(0, -5.0 * u).rotated(slope)
		draw_circle(mc, 8.5 * u, Color(1, 1, 1, 0.8 * a))   # 印の白い縁（丘の線や雪から浮かせる）
		Icons._o = mc
		Icons._s = 0.4 * u
		if sled:
			Icons.sled_side(self, Vector2.ZERO, 1.0, a, slope, true)   # 前は左（頂上）
		else:   # 畳んだ包み
			Icons.patch(self, Icons.xf(Icons.rr(-7, -7, 14, 14, 2), PI / 4, Vector2(0, 2), 1.0), preload("res://fabrics.gd").color(item.get("fabric", "red")), a, false)
		_draw_turn(u, a, tw, sled, item)
		_draw_owner(u, a, Rect2(Vector2(158.0, 46.0) * u, Vector2(fw - 160.0 * u, 71.0 * u)), sled)

	## 回る図の窓: ソリがゆっくり回り（sled_tags.gd の turntable_wide。12 コマの刻みで 5° ずつ、12 秒で 1 周）、いま触れている人・
	## 乗っている人を、そのソリの上の実際の所に 3D の人型（person_icon.gd の model。キャラの色）で乗せて、いっしょに回す。
	## どの向きから見ても人型は正しく見え、ソリの陰にも隠れる。頭の上の名前と、持ち主の王冠は、ここで上に描く
	func _draw_turn(u: float, a: float, tw: Rect2, sled: RigidBody3D, item: Dictionary) -> void:
		Icons.screen()
		Icons.patch(self, Icons.rr(tw.position.x, tw.position.y, tw.size.x, tw.size.y, 8.0 * u), Color(0.86, 0.90, 0.97), a, true, Icons.THREAD)
		var kind: String = sled.kind if sled else String(item.get("sled", "mid"))
		var fabric: String = sled.fabric if sled else String(item.get("fabric", ""))
		var ar := float(SledTags.WIDE_SIZE.x) / SledTags.WIDE_SIZE.y
		var ih := tw.size.y - 3.0 * u
		var img := Rect2(tw.get_center() - Vector2(ih * ar, ih) / 2.0, Vector2(ih * ar, ih))
		# 乗せる人: 窓から出る遠くの人（紐の先で引く人など）は、ソリの近くへ寄せる
		var reach: float = (sled.HALF.y + 0.9) if sled else 0.0
		var list: Array = []
		for x in (hud._people if sled else []):
			var at: Vector3 = x.at
			var flat := Vector3(at.x, 0, at.z)
			if x.pose != "sit" and flat.length() > reach:
				at = flat.normalized() * reach
			var face := Vector3(0, 0, -1)   # 座る人はソリの前を向く
			match x.pose:
				"pull": face = flat   # 引く人はソリから離れる向き（紐を後ろに持つ）
				"push", "stand": face = -flat   # 押す・つかむ人はソリを向く
			var id: int = int(x.who.get("id")) if x.who.get("id") != null else x.who.get_instance_id()
			var col: Color = x.col if x.strong else x.col.lerp(Color(0.95, 0.95, 0.97), 0.45)   # つかんでいるだけの人は淡く
			list.append({"key": id, "at": at, "pose": x.pose, "col": col, "face": face, "name": x.name, "who": x.who})
		draw_texture_rect(SledTags.turntable_wide(kind, fabric, list), img, false, Color(1, 1, 1, a))
		if sled == null:
			return
		# 頭の上の名前と、持ち主の王冠（手前の人を後に）
		var deg := SledTags.turn_deg(true)
		var owner: int = hud.tag_owner()
		var tops: Array = []
		for x in list:
			var top: Vector3 = x.at + Vector3(0, 0.95 if x.pose == "sit" else 1.62, 0)
			var q := SledTags.turn_project(kind, true, top, deg)
			tops.append([x, Vector2(img.position.x + q.x * img.size.x, img.position.y + q.y * img.size.y), q.z])
		tops.sort_custom(func(m, n): return m[2] < n[2])
		for m in tops:
			var x: Dictionary = m[0]
			var c: Vector2 = m[1]
			c.x = clampf(c.x, tw.position.x + 10.0 * u, tw.end.x - 10.0 * u)
			c.y = maxf(c.y, tw.position.y + 22.0 * u)
			if int(x.key) == owner:
				PersonIcon.crown(self, c, 11.0 * u, a)
				c.y -= 8.0 * u
			PersonIcon.name_label(self, String(x.name), c - Vector2(0, 1.0 * u), 10.0 * u, x.col, a)

	## 持ち主（名札を持っている人）: 3D の人型を正面から少し斜めに撮った図（キャラの色）に王冠と、頭の上に名前。
	## ロッジのソリは王冠を載せた家、名札を外したソリは空の輪
	func _draw_owner(u: float, a: float, r: Rect2, sled: RigidBody3D) -> void:
		var owner: int = hud.tag_owner()
		var c := Vector2(r.get_center().x, r.end.y - 4.0 * u)
		Icons.screen()
		if owner >= 0:
			var craft = hud.main.get("craft")
			var who: Node = null
			var hub = hud.main.get_node_or_null("Emotes")
			if hub:
				who = hub.who_of(owner)
			var col: Color = craft.color_of(owner) if craft else (hud._color_of(who) if who else Icons.RED)
			var nm: String = craft.name_of(owner) if craft else ""
			var ph := r.size.y * 0.82
			var pw := ph * SledTags.PERSON_SIZE.x / SledTags.PERSON_SIZE.y
			var pr := Rect2(Vector2(c.x - pw / 2.0, r.end.y - ph), Vector2(pw, ph))
			draw_texture_rect(SledTags.person_portrait(col), pr, false, Color(1, 1, 1, a))
			var top := Vector2(c.x, pr.position.y + ph * 0.12)
			PersonIcon.crown(self, top, 13.0 * u, a)
			PersonIcon.name_label(self, nm, top - Vector2(0, 10.0 * u), 10.0 * u, col, a)
		elif sled and SledTags.has_tag(sled.get("tag")):   # ロッジのソリ
			var hc := c - Vector2(0, 2.0 * u)
			Icons.patch(self, PackedVector2Array([hc + Vector2(-13, 0) * u, hc + Vector2(13, 0) * u, hc + Vector2(13, -15) * u,
				hc + Vector2(0, -27) * u, hc + Vector2(-13, -15) * u]), Icons.WOOD, a, false)
			draw_rect(Rect2(hc + Vector2(-4, -12) * u, Vector2(8, 7) * u), Color(1.0, 0.72, 0.30, a))
			PersonIcon.crown(self, hc + Vector2(0, -29.0 * u), 15.0 * u, a)
		else:   # 名札を外したソリ: 持ち主はいない
			Icons.dashes(self, Icons.circ(c - Vector2(0, r.size.y * 0.32), r.size.y * 0.2, 20), Icons.PAPER_EDGE, 1.5 * u, 4.0 * u, 3.0 * u, a, true)

	## 乗って滑っているときの速さ（ボビン。数字は出さない）
	func _draw_speedo(u: float) -> void:
		var e := ease(hud._spd_a, 0.6)
		if e > 0.01:
			var g := Speedo.layout(hud.speedo_box_now(), hud._spd_pop)
			var k := Speedo.level_of(hud._spd)
			if hud.plates == null:   # 平らなとき: リボンは糸巻きから吊るして揺れる。ボビンは小刻みに
				var rb: Rect2 = g.ribbon
				draw_set_transform_matrix(Icons.wind_xform(Vector2(rb.get_center().x, rb.position.y), 6.0, 0.05, 0.05, 1.5 * u))
				Speedo.draw_stitches(self, g, k, hud._spd_spin, hud._spd_dist, hud.thread_base(), hud._spd_knots, e, true, hud._spd_sewn, hud.reel_k(), hud.lint())
			Speedo.draw_combo(self, g, hud._combo_knots, hud._clock_now(), hud.UNTIE_T, hud.thread_base(), e)
			draw_set_transform_matrix(Icons.wind_xform(g.c, 4.0, 0.0, 0.03, 2.0 * u))
			Speedo.draw_spool(self, g, k, hud._spd_spin, hud.thread_base(), hud.spd_best, hud._spd_pop, e, hud.plates == null)
			draw_set_transform_matrix(Transform2D.IDENTITY)

	## 確かめ用の数字（設定の「確かめ用の数字」か --hud-debug のとき）: 左上の隅に、小さな素の文字で「60 fps  12 ms」。
	## 開発用なので、絵にせず目立たなくする（藍の字に白いふち。雪・空・ロッジの中のどれでも読める。fps が 30 より下なら赤、
	## ひとりのときの通信は「-- ms」）
	func _draw_debug(u: float) -> void:
		var d: Dictionary = hud._dbg
		var font := ThemeDB.fallback_font
		var fs := int(round(14.0 * u))
		var at := Vector2(10.0, 6.0) * u + Vector2(0, font.get_ascent(fs))
		var parts := [["%d fps" % d.fps, Icons.RED if d.fps < 30 else Icons.THREAD],
			["%s ms" % (str(d.ms) if d.ms >= 0 else "--"), Icons.THREAD]]
		for x in parts:
			draw_string_outline(font, at, x[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(3.0 * u)), Color(1, 1, 1, 0.55))
			draw_string(font, at, x[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(x[1], 0.8))
			at.x += font.get_string_size(x[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0 * u

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
