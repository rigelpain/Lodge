extends Node
## 観戦モード（霊体）。2026-11-08 代表「観戦モードが欲しい。これは実験目的でもあるから、3次元自由に動けてプレイヤーからは見えなくて
## なににも衝突しない霊体みたいな状態。可視不可視はスイッチできると良いな。」
##
## 設定の画面（Esc）の「霊体になる」で体から抜けて霊体になり、切ると体へ戻る（2026-11-08 代表「キーボードでのショートカットは消して」）。抜けているあいだ、体は抜けた所に止まって消える（当たり・人形・影・連れ・
## まち針・足音・息、どれも出ない）。霊体は別のカメラで、重力も当たりもなく 3 次元を飛ぶ。
##   マウス 見回す / W・S 見ている向きへ前後（上下も） / A・D 横 / Space 上がる / 左 Ctrl 下がる / Shift 速く /
##   ホイール・二本指スクロール 速さを変える。見える ⇄ 見えないも設定の画面で（はじめは見えない）
## 見えないあいだは、周りのゲームの動きを一切変えない（体がその場から帰ったのと同じに扱う）。そのため霊体の人は:
##   名簿（emotes.gd の people）から外す → 施設の「近づくと動く」・番台ののれん・地図のまち針・湿り気・雪玉の当たりが見ない
##   仲間（bot.gd の _humans）・山男・柵の動物・紙細工屋さんが見ない / 足音と息（audio.gd）を出さない / 連れ（companions.gd）を隠す
## 見えるときも、周りは同じく見ない（姿が透けて見えるだけ）。姿は透けた紙の人形（LOOKS。--ghost-look= で見比べ）。
## 入れるのは、歩いている・つかんでいる・紐を持っているとき（つかんでいれば手を離す）。乗っている・座っている・乾燥機・吹き飛んでいる・
## 大玉の中・雪合戦の対決・のぞいている・画面を開いているときは入れない。戻ると、抜けた所に、抜けたときの向きで立って歩いている。
## 持ち物・雪玉・装備・お金・ソリはそのまま（抜けているあいだ、ソリは置いたまま。だれも持たない）。
## 通信: 姿の代わりに "gh"（1 見えない・2 見える）を送る。見えないあいだは位置も送らない（ほかの画面の体はその場で消える）。
## 見えるときは霊体の位置を送り、ほかの画面では透けた人形がそこに浮かぶ（remote_person.gd）。来ている人の数・番号・持ち主は変えない。

const Doll := preload("res://doll.gd")

const EYE := 1.55             # 抜けるときの目の高さ（player.gd のカメラ）
const SPEED := 6.0            # はじめの飛ぶ速さ (m/s)
const SPEED_RANGE := Vector2(0.5, 80.0)
const SPEED_STEP := 1.25      # ホイール 1 目盛りで掛ける・割る
const FAST := 4.0             # Shift で掛ける
const EASE := 10.0            # 速さが入力に追いつく速さ（1/s）。止まるときもすっと止まる
const PAN_STEP := 1.0         # 二本指スクロールで、これだけたまったら 1 目盛り（player.gd の PAN_STEP と同じ）
## 見えるときの姿の案: [人形の透け具合（0 そのまま〜1 消える）, 上に重ねる薄紙の色（a が濃さ）]
const LOOKS := {
	"a": [0.55, Color(1, 1, 1, 0.0)],             # 透けた紙: 色はそのまま、半分透ける
	"b": [0.5, Color(0.97, 0.97, 1.0, 0.55)],     # 薄紙（トレーシングペーパー）: 白く褪せて透ける
	"c": [0.45, Color(0.80, 0.66, 0.46, 0.5)],    # 型紙（ハトロン紙）: 薄茶の紙で透ける
}
static var look := "b"        # --ghost-look=a|b|c

var main: Node3D
var player: CharacterBody3D
var active := false           # 抜けている
var seen := false             # 見える
var cam: Camera3D
var speed := SPEED            # 基本の速さ（ホイールで変える）
var _vel := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _saved := Transform3D()   # 抜けた所の体
var _saved_pitch := 0.0
var _saved_layer := 0
var _saved_mask := 0
var _pan_acc := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "GhostCam"
	cam.near = 0.05
	cam.cull_mask = (1 << 0) | (1 << 3) | (1 << 4) | (1 << 7)   # 世界・飾り・風・太陽。自分の体（層 2）と一人称の手（層 3）は映さない
	add_child(cam)
	var a = main.get("args") if main else null
	if a is Dictionary and a.has("ghost-look") and LOOKS.has(String(a["ghost-look"])):
		look = String(a["ghost-look"])


## その人（player.gd・remote_person.gd）が霊体か。仲間（bot.gd）は霊体にならない
static func gone(who: Object) -> bool:
	if who == null or not is_instance_valid(who):
		return false
	var g = who.get("ghost")
	return g != null and int(g) != 0


## いま抜けられるか
## from_menu: 設定の画面の切り替えから（設定を開いたままでも抜けられる）
func can_enter(from_menu := false) -> bool:
	var p := player
	if p == null or not is_instance_valid(p) or (p.menu_open and not from_menu) or p.shopping:
		return false
	if main.settings != null and main.settings.is_open and not from_menu:
		return false
	if not p.mode in [p.Mode.WALK, p.Mode.GRIP, p.Mode.ROPE]:
		return false
	if p.fling.active() or p.rolled.active() or p.peek != "" or p.dueling() or p.busy_until >= Doll.frame_index():
		return false
	return not (p.ring and p.ring.visible)


func enter(from_menu := false) -> bool:
	if active or not can_enter(from_menu):
		return false
	var p := player
	if p.mode in [p.Mode.GRIP, p.Mode.ROPE]:
		p.let_go()   # つかんでいたソリ・紐から手を離す（ソリはそのまま置いていく）
	if p.pointing:
		p.toggle_point()   # 指さしを下ろす
	p._stop_exhale()
	p._eating = false
	p._winding = false
	p._wind_wait = false
	_saved = p.global_transform
	_saved_pitch = p._pitch
	_saved_layer = p.collision_layer
	_saved_mask = p.collision_mask
	# 目の所から抜ける（三人称でも、人形の目から）
	_yaw = p.rotation.y
	_pitch = p._pitch
	cam.fov = p.base_fov
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0)), p.global_position + Vector3.UP * EYE)
	_vel = Vector3.ZERO
	p.velocity = Vector3.ZERO
	p.collision_layer = 0
	p.collision_mask = 0
	p._col.disabled = true
	p.doll.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED   # 体の動き・入力・当たりを止める（抜けた所にそのまま）
	cam.make_current()
	active = true
	seen = false
	_set_ghost(1)
	return true


func leave() -> void:
	if not active:
		return
	var p := player
	active = false
	seen = false
	p.process_mode = Node.PROCESS_MODE_INHERIT
	p.global_transform = _saved
	p._pitch = _saved_pitch
	p.velocity = Vector3.ZERO
	p.collision_layer = _saved_layer
	p.collision_mask = _saved_mask
	p._col.disabled = false
	p.doll.visible = true
	p.cam.make_current()
	_set_ghost(0)


func set_seen(on: bool) -> void:
	if not active:
		return
	seen = on
	_set_ghost(2 if on else 1)


## 体の印と、名簿・右下の小窓・右上の映像
func _set_ghost(g: int) -> void:
	player.set("ghost", g)
	var hub = main.get("emotes")
	var id := int(player.id)
	if hub and id >= 0:
		if g != 0 and hub.people.get(id) == player:
			hub.people.erase(id)   # 名簿から外す（施設・まち針・湿り気・雪玉は、名簿の人だけを見る）
		elif g == 0 and not hub.people.has(id):
			hub.people[id] = player
	if main.get("self_cam"):
		main.self_cam.set_ghost_off(g != 0)
	if main.has_method("_sync_pip_shown"):
		main._sync_pip_shown()
	if main.get("settings") and main.settings.has_method("sync_ghost"):
		main.settings.sync_ghost(g != 0, g == 2)   # 設定の画面の切り替えも、いまの様子に（抜けられず戻したときも）


## 霊体の姿（net.gd が送る）。見えないときは位置を入れない
func net_state() -> Dictionary:
	var s := {"gh": 2 if seen else 1, "m": 0, "d": player.doll.kind}
	if seen:
		s["p"] = cam.global_position - Vector3.UP * EYE
		s["y"] = _yaw
	return s


## 入力は _input で先に受ける（ほかの物の _unhandled_input より前）。抜けているあいだ、霊体の操作のほかのキーは止める
## （体の操作は体ごと止まっているが、ミシンの T・ソリを戻す Backspace などは体の外で受けている）。止めないのは Esc（設定）・V・P（右上の映像）
func _input(e: InputEvent) -> void:
	if main.get("start") != null and is_instance_valid(main.start):
		return
	var menu: bool = main.settings != null and main.settings.is_open
	if not active:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not menu:
		var k: float = player.mouse_sens
		_yaw -= e.relative.x * 0.003 * k
		_pitch = clampf(_pitch - e.relative.y * 0.003 * k, -1.55, 1.55)
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not menu:
		_speed_step(1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
	elif e is InputEventPanGesture and not menu:
		_pan_acc += -e.delta.y
		while absf(_pan_acc) >= PAN_STEP:
			_speed_step(1 if _pan_acc > 0.0 else -1)
			_pan_acc -= signf(_pan_acc) * PAN_STEP
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	if e is InputEventKey and not e.physical_keycode in [KEY_ESCAPE, KEY_V, KEY_P]:
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and not menu:
		get_viewport().set_input_as_handled()


func _speed_step(d: int) -> void:
	speed = clampf(speed * pow(SPEED_STEP, d), SPEED_RANGE.x, SPEED_RANGE.y)
	_learn("ghost_speed")


func _learn(id: String) -> void:
	var hud = main.get("hud")
	if hud and hud.has_method("learn"):
		hud.learn(id)


## 動かす向き（カメラの座標: x 右、y 上、z 後ろ）
func _input_dir() -> Vector3:
	var k := func(key: Key) -> float: return 1.0 if Input.is_physical_key_pressed(key) else 0.0
	return Vector3(k.call(KEY_D) - k.call(KEY_A), k.call(KEY_SPACE) + k.call(KEY_E) - k.call(KEY_CTRL) - k.call(KEY_Q), k.call(KEY_S) - k.call(KEY_W))


func _process(dt: float) -> void:
	if not active:
		return
	if not is_instance_valid(player):
		active = false
		return
	var menu: bool = main.settings != null and main.settings.is_open
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0))
	var want := Vector3.ZERO
	if not menu:
		var d := _input_dir()
		# 前後は見ている向き（上下も）、横は水平、上下は世界の上下
		var fwd := -basis.z
		var right := basis.x
		right.y = 0.0
		var mv := fwd * -d.z + right.normalized() * d.x + Vector3.UP * d.y
		if mv.length() > 1.0:
			mv = mv.normalized()
		var fast := FAST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
		want = mv * speed * fast
		if d.y != 0.0:
			_learn("ghost_up" if d.y > 0.0 else "ghost_down")
	_vel = _vel.lerp(want, 1.0 - exp(-EASE * dt))
	cam.global_transform = Transform3D(basis, cam.global_position + _vel * dt)


## 見えるときの霊体の人形を、透けた紙にする（どの画面でも。remote_person.gd が 12 コマごとに呼ぶ。人形は部品を作り直すので、毎コマ当て直す）
static func paint(doll: Node3D, on: bool) -> void:
	var spec: Array = LOOKS.get(look, LOOKS["b"])
	var over: StandardMaterial3D = null
	if on and (spec[1] as Color).a > 0.0:
		over = _overlay(spec[1])
	_paint(doll, on, float(spec[0]), over)


static var _over_cache := {}

static func _overlay(c: Color) -> StandardMaterial3D:
	if _over_cache.has(c):
		return _over_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 1.0
	_over_cache[c] = m
	return m


static func _paint(n: Node, on: bool, t: float, over: Material) -> void:
	for c in n.get_children():
		if c is Decal or c is CPUParticles3D or c is GPUParticles3D:
			if on and not c.has_meta("gh_vis"):
				c.set_meta("gh_vis", c.visible)
			if on:
				c.visible = false   # 足もとの影と白い息は出さない（息は霊体のあいだ止まらず、顔に白い玉が残る）
			elif c.has_meta("gh_vis"):
				c.visible = c.get_meta("gh_vis")
				c.remove_meta("gh_vis")
		elif c is GeometryInstance3D:
			var g := c as GeometryInstance3D
			if on:
				if not g.has_meta("gh_shadow"):   # 元の影・重ねを覚えておき、戻すときに返す
					g.set_meta("gh_shadow", g.cast_shadow)
					g.set_meta("gh_over", g.material_overlay if g is MeshInstance3D else null)
				g.transparency = t
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if g is MeshInstance3D:   # 重ねのない案（a）なら元の重ねへ（案を替えたとき、前の案の紙が残らない）
					(g as MeshInstance3D).material_overlay = over if over else g.get_meta("gh_over")
			elif g.has_meta("gh_shadow"):
				g.transparency = 0.0
				g.cast_shadow = g.get_meta("gh_shadow")
				if g is MeshInstance3D:
					(g as MeshInstance3D).material_overlay = g.get_meta("gh_over")
				g.remove_meta("gh_shadow")
				g.remove_meta("gh_over")
		_paint(c, on, t, over)
