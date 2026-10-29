extends Node3D
## 大きなミシン（props/craft_machine.glb）の動きの試作。design/facilities.md の「施設の動き」の 7 つの場面:
##   待つ   糸巻きがときどき半回転して跳ね、紙の灯りがゆらぐ
##   呼ぶ   人が立つ所に近づくと、針と押さえが持ち上がり、布送りの歯がカタッと一度動く
##   入れる 布が前に現れて針の下へ吸い込まれ、押さえが下り、糸がぴんと張る
##   ため   針の上下がだんだん速くなる（1〜3 秒）。布が奥へ送られ、縫い目が増え、はずみ車と糸巻きが回る
##   解放   糸切りの「パチン」、ごく短い止め（ミシンだけ。ほかの人の時間は止めない）。止めのあいだミシンがむぎゅっと縮み、
##          明けるとばねのように戻って、綿くずがふわっと舞う
##   見せる 布が長さ 1 m のソリになって前へ押し出され、台から床へ滑り下りて止まる
##   余韻   針がゆっくり止まり、上で止まってから元の高さへ戻る
## 協力: もう一人が足踏み（目印 pedal）に立つと、足踏みが揺れ、針の速さの上限が 1.6 倍、上がり方が倍になる。
## そばに立つだけでも少し速くなる。一人でも縫える。
## コマ撮り（既定）: 動きは同じまま、形に当てるのを 12 コマ／秒に刻む（人形と同じ。コマの間は止める）。
## 12 コマでは 1 秒に 6 回より速い上下は正しく見えない（遅く見えたり逆に回って見えたりする）ので、針の速さの上限は
## 5.5 回／秒、はずみ車は針 1 往復で半回転にしてある。
## 操作: 立つ所のそばで T で縫う。Y でコマ撮り／なめらか。H で仲間（ボット）を足踏みに呼ぶ／帰す。
## 工房（craft.gd）があるとき: 型紙か布を手に持って T でセットする（台の上に置かれる）。型紙と布の両方がそろうと縫い始め、
## 布はその色で入り、見せるで出てくるのは型紙の大きさの、広げた実寸のソリ（布の色）。床に着いたら本物のソリになる。
## 型紙と布はそれぞれ別の人がセットしてもよい（二人で一つのソリを作れる）。
## 起動引数: --sew-smooth（なめらかで始める）、--sew-helper（仲間を足踏みに立たせて始める）、--spawn=sew（ミシンの前から始める）

const Doll := preload("res://doll.gd")
const Bot := preload("res://bot.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Fabrics := preload("res://fabrics.gd")
const Sled := preload("res://sled.gd")

enum Phase { WAIT, CALL, FEED, CHARGE, RELEASE, SHOW, AFTER }
const PHASE_NAMES := ["wait", "call", "feed", "charge", "release", "show", "after"]

const NEAR := 2.4            # 立つ所からこの距離に人が来ると気づく (m)
const PEDAL_R := 0.9         # 足踏みに立っているとみなす距離 (m)
const HELP_R := 3.5          # そばにいるとみなす距離（ミシンの中心から）
const STITCHES := 8          # ためで縫う目の数。これを縫い終えたら解放
const RATE_START := 1.5      # 針の上下（回／秒）の出だし
const RATE_SOLO := 3.5       # 一人のときの上限
const RATE_PEDAL := 5.5      # 足踏みにもう一人いるときの上限（12 コマで読める速さの上限 6 の手前）
const RATE_NEAR := 0.6       # そばにいる人ひとりごとに上限へ足す（足しても RATE_PEDAL まで）
const RAMP_SOLO := 2.0       # 出だしから上限までの時間 (s)。足踏みがいると半分
const HITSTOP := 0.12        # 解放の止め (s)
const FEED_LEN := 0.85       # 入れる (s)
const SHOW_LEN := 1.35       # 見せる (s)
const NEEDLE_LIFT := 0.15    # 呼ぶ: 針を持ち上げる高さ (m)
const NEEDLE_MID := 0.04     # 縫うときの針の上下の中心と幅（針先が台に沈むまで）
const NEEDLE_AMP := 0.11
const PRESSER_LIFT := 0.08
const SEW_DIST := 0.24       # ためのあいだに布が奥へ送られる長さ (m)
const PRODUCT_LEN := 1.0     # できたソリの長さ (m)。1 人乗りのソリ（1.67 m）の 6 割
const WHEEL_TURN := 0.5      # 針 1 往復ではずみ車が回る回数
const STOP_LEN := 1.6        # 余韻: 針が止まるまで (s)

signal phase_changed(name: String)

var world: Node              # main.gd（あなたと仲間を探す、起動引数）
var stepped := true
var phase := Phase.WAIT
var phase_t := 0.0
var last_charge := 0.0       # 直前のためにかかった時間 (s)。確かめ用
var helper: Node3D           # H で呼んだ仲間
var loaded := {}             # セットした型紙と布 {"pattern": 大きさ, "fabric": 色, "who": 型紙をセットした人}
var _real := {}              # いま縫っている本物のソリ {"sled", "fabric", "who"}（空なら 1 m の見本）
var _set_look := {}          # 台の上に置いた型紙・布の形

var machine: Node3D
var _mv := {}                # 名前 → 動かす部品
var _rest := {}              # 名前 → 付け根の Transform3D
var _mark := {}              # 目印の位置（ミシンの座標）
var _thread_pts: Array[Vector3] = []
var _eye: Node3D

# いまの姿勢（毎フレーム決め、なめらか版は毎フレーム、コマ撮り版は 12 コマ／秒で形に当てる）
var _needle_h := 0.0
var _needle_base := 0.0      # 縫っていないときの針の高さ（呼ぶで上がる）
var _presser_h := 0.0
var _feed_off := Vector3.ZERO
var _wheel_a := 0.0
var _spool_a := [0.0, 0.0]
var _spool_hop := [0.0, 0.0]
var _pedal_a := 0.0
var _pedal_amt := 0.0
var _sag := 0.10             # 糸のたるみ（区間の長さに対する割合）
var _tail := 0.0             # 針から布へ下りる糸（0 なし〜1）
var _lamp_k := 1.0
var _flash := 0.0
var _squash := 0.0           # 解放でミシン全体がむぎゅっと縮んで戻る（ぬいぐるみの機械）
var _squash_t := -1.0
var _body: Node3D            # glb の根元（ミシンの形だけ。布やできた物は入らない）

var _phi := 0.0              # 針の位相（1 で 1 往復。整数で針がいちばん上）
var _rate := 0.0
var _sewn := 0
var _helpers := Vector2i.ZERO   # (足踏み, そば)
var _freeze := 0.0
var _clock := 0.0
var _turn := {}              # 待つ: 糸巻きの半回転 {"i", "t", "from"}
var _next_turn := 2.5
var _clacked := false
var _landed := false
var _charge_t := 0.0
var _stop := {}              # 余韻: 針を止める {"p0", "d", "m0", "t"}
var _post: Node3D
var _frame := -1
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()

var _cloth: Node3D
var _cloth_z0 := 0.0
var _cloth_pos := Vector3.ZERO   # 布とできた物の置き場も、形に当てるときに当てる（コマ撮りで一緒に刻む）
var _cloth_scl := Vector3.ONE
var _prod_pos := Vector3.ZERO
var _prod_scl := Vector3.ONE
var _prod_pitch := 0.0
var _product: Node3D
var _product_from := 0.0
var _lint: CPUParticles3D
var _lamp: OmniLight3D
var _lamp_mat: StandardMaterial3D
var _thread_mi: MeshInstance3D
var _thread_mat: StandardMaterial3D
var _snap := 0.0             # 切った糸が針へはね上がる途中（1→0）
var _dash_mesh: BoxMesh
var _dash_mat: StandardMaterial3D

var _audio: Node
var _snd_stitch: Array[AudioStreamPlayer3D] = []
var _snd_next := 0
var _snd_hum: AudioStreamPlayer3D
var _snd_fx: AudioStreamPlayer3D
var _snd_fx2: AudioStreamPlayer3D


func _ready() -> void:
	machine = get_parent()
	_rng.seed = 7
	_noise.frequency = 1.0
	for key in ["needle", "presser", "feed", "balance", "spool_red", "spool_cream", "pedal", "thread"]:
		var n := machine.find_child("mv_" + key, true, false) as Node3D
		if n == null:
			push_warning("ミシンの部品が見つからない: mv_" + key + "（props/build_machines.py で書き出し直す）")
			set_process(false)
			return
		_mv[key] = n
		_rest[key] = n.transform
	for key in ["work", "out", "stand", "pedal", "lamp"]:   # 目印は glb の根元の下（ミシンの座標で持つ）
		var m := machine.find_child(key, true, false) as Node3D
		_mark[key] = machine.to_local(m.global_position) if m else Vector3.ZERO
	for k in 5:
		var m := machine.find_child("thread_%d" % k, true, false) as Node3D
		if m:
			_thread_pts.append(machine.to_local(m.global_position))
	_eye = _mv["needle"].find_child("eye", false, false)
	_body = _mv["needle"].get_parent()
	_mv["thread"].visible = false   # 張り具合を描く糸に替える
	if world and "args" in world:
		stepped = not world.args.has("sew-smooth")
	_make_thread()
	_make_spool_tails()
	_make_lamp()
	_make_lint()
	_dash_mesh = BoxMesh.new()
	_dash_mesh.size = Vector3(0.02, 0.01, 0.04)
	_dash_mat = Look.felt(Color("B8402E"), 4.0)
	var craft: Node = world.get("craft") if world else null
	if craft:
		craft.happened.connect(_on_craft)


# ---- 操作 ------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.physical_keycode:
		KEY_T:
			if _user_near():
				if world.get("craft") and world.get("player"):
					world.player.load_machine(self)   # 手に持った型紙か布をセットする（両方そろうと縫い始める）
				else:
					use()
		KEY_Y:
			set_stepped(not stepped)
		KEY_H:
			toggle_helper()


## 縫い始める。待つ・呼ぶのときだけ受け付ける
func use() -> bool:
	if phase != Phase.WAIT and phase != Phase.CALL:
		return false
	_set_phase(Phase.FEED)
	return true


## 手に持った物をセットできるか（待つ・呼ぶのときだけ。型紙と布は 1 つずつ）
func accepts(it: Dictionary) -> bool:
	if phase != Phase.WAIT and phase != Phase.CALL:
		return false
	match it.get("kind", ""):
		"pattern": return not loaded.has("pattern")
		"fabric": return not loaded.has("fabric")
	return false


func _on_craft(ev: Dictionary) -> void:
	if ev.kind != "load":
		return
	var it: Dictionary = ev.item
	if it.kind == "pattern":
		loaded["pattern"] = it.sled
		loaded["who"] = ev.who
	else:
		loaded["fabric"] = it.fabric
	_show_loaded(it.kind)
	_fx("sew_clack", -10.0, 1.2)
	if loaded.has("pattern") and loaded.has("fabric"):
		_real = {"sled": loaded.pattern, "fabric": loaded.fabric, "who": int(loaded.who)}
		loaded = {}
		use()


## セットした型紙・布を、台の手前に置いて見せる（型紙は左、布は右）
func _show_loaded(kind: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	if kind == "pattern":
		bm.size = Vector3(0.34, 0.004, 0.42)
		mi.material_override = Look.paper(Color(0.84, 0.72, 0.52))
		mi.position = _bed_point(-0.45) + Vector3(0.38, 0.0, 0)
		mi.rotation.y = 0.12
	else:
		bm.size = Vector3(0.36, 0.05, 0.26)
		mi.material_override = Look.felt(Fabrics.color(loaded.fabric), 3.0)
		mi.position = _bed_point(-0.45) + Vector3(-0.38, 0.02, 0)
		mi.rotation.y = -0.1
	mi.mesh = bm
	machine.add_child(mi)
	_set_look[kind] = mi


func set_stepped(on: bool) -> void:
	stepped = on
	_lint.fixed_fps = Doll.FPS if on else 0
	_lint.fract_delta = not on
	_frame = -1


## 仲間（ボット）を足踏みに呼ぶ。もういれば帰す（消す）
func toggle_helper() -> void:
	if helper:
		helper.queue_free()
		helper = null
		return
	if world == null or world.get("sled") == null:
		return
	if _post == null:
		_post = Node3D.new()
		_post.name = "PedalPost"
		_post.position = _mark["pedal"]
		machine.add_child(_post)
	var b := Bot.new()
	b.sled = world.sled
	b.player = world.get("player")
	b.side = 1
	b.post = _post
	b.post_look = machine.to_global(_mark["work"])
	world.add_child(b)
	b.global_position = _post.global_position + Vector3.UP * 0.3
	helper = b


func phase_name() -> String:
	return PHASE_NAMES[phase]


# ---- 毎フレーム ------------------------------------------------------------------

func _process(dt: float) -> void:
	if world and "args" in world and world.args.has("sew-helper") and helper == null and world.get("sled") != null \
			and not has_meta("helped"):
		set_meta("helped", true)
		toggle_helper()
	if world and "args" in world and world.args.get("spawn", "") == "sew" and not has_meta("spawned") \
			and world.get("player") != null:
		set_meta("spawned", true)   # --spawn=sew: ミシンの前（立つ所の 1 m 手前）に立って始める
		var p: CharacterBody3D = world.player
		var at := machine.to_global(_mark["stand"] + Vector3(0, 0.05, -1.0))
		p.global_position = at
		var w := machine.to_global(_mark["work"])
		p.rotation.y = atan2(-(w.x - at.x), -(w.z - at.z))
	if _audio == null and world and world.has_node("Audio") and _snd_hum == null:
		_make_sound()   # main.gd は機械を置いたあとで音を作る
	_clock += dt
	if _freeze > 0.0:   # 解放の止め: ミシンの時間だけ止める
		_freeze -= dt
		if _freeze <= 0.0:
			_lint.restart()
			_lint.emitting = true
			_squash_t = 0.0
		dt = 0.0
	_count_helpers()
	_simulate(dt)
	var fi := Doll.frame_index()
	if not stepped or fi != _frame:
		_frame = fi
		_apply()


func _set_phase(p: Phase) -> void:
	phase = p
	phase_t = 0.0
	match p:
		Phase.FEED:
			_start_cloth()
			_fx("sew_draw", -10.0)
		Phase.CHARGE:
			_sewn = 0
			_rate = RATE_START
			_phi = 0.0
		Phase.RELEASE:
			last_charge = _charge_t
			_tail = 0.0
			_snap = 1.0
			_flash = 1.0
			_freeze = HITSTOP
			_squash = 0.05   # 止めのあいだは縮んだまま
			_fx("sew_snip", -4.0)
		Phase.SHOW:
			_landed = false
			_start_product()
		Phase.AFTER:
			_deliver()
			# いまの速さのまま入り、ちょうど針がいちばん上へ来た所で止まる（エルミート曲線）
			var d := ceilf(_phi + _rate * STOP_LEN / 2.2) - _phi
			_stop = {"p0": _phi, "d": d, "m0": _rate * STOP_LEN / d, "t": 0.0}
		Phase.WAIT, Phase.CALL:
			_clacked = false
	phase_changed.emit(PHASE_NAMES[p])



func _simulate(dt: float) -> void:
	phase_t += dt
	var near := _user_near()
	# 待つ: 糸巻きがときどき半回転して小さく跳ねる
	if phase == Phase.WAIT or phase == Phase.CALL:
		_next_turn -= dt
		if _next_turn <= 0.0 and _turn.is_empty():
			var i := _rng.randi_range(0, 1)
			_turn = {"i": i, "t": 0.0, "from": _spool_a[i]}
			_next_turn = _rng.randf_range(3.5, 6.5)
	if not _turn.is_empty():
		_turn["t"] += dt
		var u: float = clampf(_turn["t"] / 0.9, 0.0, 1.0)
		var i: int = _turn["i"]
		_spool_a[i] = _turn["from"] + PI * _ease_io(u)
		_spool_hop[i] = 0.012 * sin(PI * clampf(u * 1.4, 0.0, 1.0))
		if u >= 1.0:
			_spool_hop[i] = 0.0
			_turn = {}

	match phase:
		Phase.WAIT:
			_needle_base = move_toward(_needle_base, 0.0, dt * 0.25)
			_presser_h = move_toward(_presser_h, 0.0, dt * 0.15)
			_sag = lerpf(_sag, 0.10, 1.0 - exp(-dt * 2.0))
			if near:
				_set_phase(Phase.CALL)
		Phase.CALL:
			# 針と押さえが持ち上がり（少し行き過ぎて戻る）、布送りの歯がカタッ
			var u := clampf(phase_t / 0.45, 0.0, 1.0)
			_needle_base = NEEDLE_LIFT * _ease_back(u)
			_presser_h = PRESSER_LIFT * _ease_back(clampf((phase_t - 0.08) / 0.45, 0.0, 1.0))
			_sag = lerpf(_sag, 0.07, 1.0 - exp(-dt * 3.0))
			if phase_t > 0.35 and not _clacked:
				_clacked = true
				_fx("sew_clack", -8.0)
			var c := clampf((phase_t - 0.35) / 0.16, 0.0, 1.0)
			_feed_off = _feed_cycle(c) if c < 1.0 else Vector3.ZERO
			if not near and phase_t > 0.6:
				_set_phase(Phase.WAIT)
		Phase.FEED:
			_feed_cloth(dt)
			if phase_t >= FEED_LEN:
				_charge_t = 0.0
				_set_phase(Phase.CHARGE)
		Phase.CHARGE:
			_charge_t += dt
			_run_needle(dt, true)
			# 布が奥へ送られる
			if _cloth:
				_cloth_pos.z = _cloth_z0 + SEW_DIST * (float(_sewn) + fposmod(_phi, 1.0)) / STITCHES
			if _sewn >= STITCHES and fposmod(_phi, 1.0) > 0.45:   # 最後の目を縫い、針が上がりかけたら切る
				_set_phase(Phase.RELEASE)
		Phase.RELEASE:
			_run_needle(dt, false, 2.4)
			if phase_t > 0.25:
				_set_phase(Phase.SHOW)
		Phase.SHOW:
			_run_needle(dt, false, 1.2)
			_move_product(dt)
			if phase_t >= SHOW_LEN:
				_set_phase(Phase.AFTER)
		Phase.AFTER:
			# 針がゆっくり止まる
			if not _stop.is_empty():
				var before := _phi
				_stop["t"] += dt
				var u := clampf(_stop["t"] / STOP_LEN, 0.0, 1.0)
				var m0: float = _stop["m0"]
				_phi = _stop["p0"] + _stop["d"] * ((u * u * u - 2.0 * u * u + u) * m0 + (-2.0 * u * u * u + 3.0 * u * u))
				_rate = _stop["d"] / STOP_LEN * ((3.0 * u * u - 4.0 * u + 1.0) * m0 + (-6.0 * u * u + 6.0 * u))
				_stitch_sound_check(before)
				_needle_h = NEEDLE_MID + NEEDLE_AMP * cos(TAU * _phi)
				_wheel_a = -TAU * WHEEL_TURN * _phi
				_spool_a[0] += _rate * dt * 0.9
				_spool_a[1] += _rate * dt * 0.25
				_feed_off = _feed_cycle(fposmod(_phi + 0.25, 1.0))
				_needle_base = _needle_h
				if u >= 1.0:
					_stop = {}
					_rate = 0.0
					_feed_off = Vector3.ZERO
			else:
				var to := NEEDLE_LIFT if near else 0.0
				_needle_base = move_toward(_needle_base, to, dt * 0.12)
				_needle_h = _needle_base
				_presser_h = move_toward(_presser_h, PRESSER_LIFT if near else 0.0, dt * 0.1)
				if absf(_needle_base - to) < 0.001 and phase_t > STOP_LEN + 0.4:
					_set_phase(Phase.CALL if near else Phase.WAIT)
					phase_t = 1.0   # 呼ぶの持ち上げはもう済んでいる
					_clacked = true
			_sag = lerpf(_sag, 0.06, 1.0 - exp(-dt * 1.5))
	if phase != Phase.CHARGE and phase != Phase.RELEASE and phase != Phase.SHOW and phase != Phase.AFTER:
		_needle_h = _needle_base
	if phase != Phase.CHARGE:
		_pedal_amt = move_toward(_pedal_amt, 0.0, dt * 1.5)
	_pedal_a = 0.16 * _pedal_amt * sin(TAU * _phi)
	if _squash_t >= 0.0:   # 止めが明けたら、ばねのように戻る
		_squash_t += dt
		_squash = 0.05 * exp(-_squash_t * 7.0) * cos(_squash_t * 26.0)
		if _squash_t > 0.8:
			_squash_t = -1.0
			_squash = 0.0
	_snap = maxf(0.0, _snap - dt / 0.18)
	_flash = maxf(0.0, _flash - dt / 0.5)
	# 紙の灯り: ふだんはゆっくりゆらぎ、縫っているあいだは少し明るく速く
	var busy := phase == Phase.CHARGE or phase == Phase.RELEASE
	var f := _noise.get_noise_1d(_clock * (2.2 if not busy else 6.0))
	_lamp_k = (1.0 if not busy else 1.25) * (0.88 + 0.16 * f + 0.04 * sin(_clock * 13.0)) + 1.6 * _flash
	_update_sound(dt)


## 針を回す。charge なら速さを上げ、そうでなければ decay で落とす
func _run_needle(dt: float, charge: bool, decay := 0.0) -> void:
	var before := _phi
	if charge:
		var top := minf(RATE_PEDAL, RATE_SOLO + (RATE_PEDAL - RATE_SOLO) * float(_helpers.x > 0) + RATE_NEAR * _helpers.y)
		var ramp := RAMP_SOLO / (2.0 if _helpers.x > 0 else 1.0) / (1.0 + 0.15 * _helpers.y)
		_rate = minf(top, _rate + (top - RATE_START) / ramp * dt)
		_pedal_amt = move_toward(_pedal_amt, 1.0 if _helpers.x > 0 else 0.0, dt * 3.0)
		_presser_h = 0.003 * maxf(0.0, -cos(TAU * _phi))
		_sag = 0.004 * sin(_clock * 31.0) * clampf(_rate / RATE_PEDAL, 0.0, 1.0)
	else:
		_rate = maxf(1.6, _rate * exp(-dt * decay))
	_phi += _rate * dt
	_needle_h = NEEDLE_MID + NEEDLE_AMP * cos(TAU * _phi)
	_wheel_a = -TAU * WHEEL_TURN * _phi
	_spool_a[0] += _rate * dt * 0.9   # 糸が出るぶん、赤い糸巻きが回る
	_spool_a[1] += _rate * dt * 0.25
	_feed_off = _feed_cycle(fposmod(_phi + 0.25, 1.0))
	_tail = 1.0 if charge else _tail
	# 針がいちばん下へ来るたびに 1 目
	if floorf(before + 0.5) < floorf(_phi + 0.5):
		if charge:
			_sewn += 1
			_add_dash()
		_stitch_sound()


func _stitch_sound_check(before: float) -> void:
	if floorf(before + 0.5) < floorf(_phi + 0.5):
		_stitch_sound()


## 布送りの歯: 上がりながら奥へ送り、台の下へ沈んで前へ戻る（u は 0〜1 の 1 往復。0 で元の所）
func _feed_cycle(u: float) -> Vector3:
	var a := TAU * u
	return Vector3(0, maxf(-0.005, 0.013 * sin(a)), 0.022 * (0.5 - 0.5 * cos(a)))


func _count_helpers() -> void:
	_helpers = Vector2i.ZERO
	if world == null:
		return
	var user: Node3D = world.get("player")
	var pedal_w := machine.to_global(_mark["pedal"])
	var center := machine.global_position
	for c in world.get_children():
		if not (c is CharacterBody3D) or (c == user and _user_near()):
			continue
		var p: Vector3 = (c as Node3D).global_position
		if Vector2(p.x - pedal_w.x, p.z - pedal_w.z).length() < PEDAL_R and absf(p.y - pedal_w.y) < 1.0:
			_helpers.x += 1
		elif p.distance_to(center) < HELP_R:
			_helpers.y += 1


func _user_near() -> bool:
	if world == null:
		return false
	var p: Node3D = world.get("player")
	if p == null:
		return false
	var s := machine.to_global(_mark["stand"])
	return Vector2(p.global_position.x - s.x, p.global_position.z - s.z).length() < NEAR \
			and absf(p.global_position.y - s.y) < 1.5


# ---- 布とできた物 ----------------------------------------------------------------

func _start_cloth() -> void:
	if _product:   # 前にできた物は、縮んで消える
		var old := _product
		_product = null
		var tw := create_tween()
		tw.tween_property(old, "scale", Vector3.ONE * 0.01, 0.2)
		tw.tween_callback(old.queue_free)
	_cloth = Node3D.new()
	_cloth.name = "Cloth"
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.016, 0.48)
	mi.mesh = bm
	mi.material_override = Look.felt(Color(0.93, 0.89, 0.8) if _real.is_empty() else Fabrics.color(_real.fabric), 3.0)   # 布に、赤い糸の縫い目が並ぶ
	for k in _set_look:   # 台に置いた型紙と布は、縫う布になって消える
		(_set_look[k] as Node).queue_free()
	_set_look = {}
	_cloth.add_child(mi)
	machine.add_child(_cloth)
	_cloth_z0 = _mark["work"].z
	_cloth_pos = _bed_point(-0.4)
	_cloth_scl = Vector3.ONE * 0.01
	_cloth.position = _cloth_pos
	_cloth.scale = _cloth_scl


## 台の上の、針から前（-z）へ d の所（布の厚みの半分だけ上）
func _bed_point(d: float) -> Vector3:
	var w: Vector3 = _mark["work"]
	return Vector3(w.x, w.y - 0.016, w.z + d)


func _feed_cloth(_dt: float) -> void:
	var t := phase_t
	# 0〜0.18 s: 前にふわっと現れる。0.25〜0.6 s: 針の下へ吸い込まれる（だんだん速く）。押さえが下り、糸が張る
	_cloth_scl = Vector3.ONE * _ease_back(clampf(t / 0.18, 0.0, 1.0))
	var u := clampf((t - 0.25) / 0.35, 0.0, 1.0)
	_cloth_pos = _bed_point(-0.4 * (1.0 - u * u * u))
	_cloth_pos.y += 0.03 * (1.0 - clampf(t / 0.25, 0.0, 1.0))
	if t < 0.6:
		_presser_h = PRESSER_LIFT
		_needle_base = NEEDLE_LIFT
	else:
		var v := clampf((t - 0.6) / 0.12, 0.0, 1.0)
		_presser_h = PRESSER_LIFT * (1.0 - v * v)
		_needle_base = lerpf(NEEDLE_LIFT, NEEDLE_MID + NEEDLE_AMP, v)
		if v >= 1.0 and not _clacked:
			_clacked = true
			_fx("sew_clack", -6.0, 0.8)
	# 糸: 布が入るまではたるみ、押さえが下りるとぴんと張って小さく震える
	if t < 0.6:
		_sag = lerpf(0.07, 0.11, clampf(t / 0.6, 0.0, 1.0))
	else:
		var s := t - 0.6
		_sag = 0.03 * exp(-s * 9.0) * cos(s * 55.0)
	_tail = 1.0 if t > 0.6 else 0.0


func _add_dash() -> void:
	if _cloth == null:
		return
	var d := MeshInstance3D.new()
	d.mesh = _dash_mesh
	d.material_override = _dash_mat
	var w: Vector3 = _mark["work"]
	d.position = Vector3(w.x - _cloth_pos.x, 0.007, w.z - _cloth_pos.z)   # 針の刺した所（布の座標）
	_cloth.add_child(d)


func _start_product() -> void:
	if _cloth:
		_cloth.queue_free()
		_cloth = null
	_product = Node3D.new()
	_product.name = "Product"
	if not _real.is_empty():
		# 本物: 型紙の大きさの、広げた実寸のソリ（布の色）。原点はソリの体と同じ（床に着く所）
		var look := Props.make("res://props/sled_%s.glb" % _real.sled)
		Fabrics.tint(look, _real.sled, _real.fabric)
		_product.add_child(look)
		machine.add_child(_product)
		_prod_pos = _product_start()
		_prod_scl = Vector3.ONE * 0.01
		_prod_pitch = 0.0
		_product.position = _prod_pos
		_product.scale = _prod_scl
		_fx2("sew_pop", -6.0, 0.8)
		return
	var sled := Props.make("res://props/sled_small.glb")
	var box := _aabb(sled)   # 木の外に出す前に測る
	var k := PRODUCT_LEN / maxf(box.size.z, 0.01)
	sled.scale = Vector3.ONE * k
	sled.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	_product.add_child(sled)
	machine.add_child(_product)
	_prod_pos = _product_start()
	_prod_scl = Vector3.ONE * 0.01
	_prod_pitch = 0.0
	_product.position = _prod_pos
	_product.scale = _prod_scl
	_fx2("sew_pop", -8.0)


## 生まれる所: 台の上、押さえのすぐ前（後ろの端が押さえの前の縁に来る）
func _product_start() -> Vector3:
	var w: Vector3 = _mark["work"]
	return Vector3(w.x, w.y - 0.02, w.z - 0.28 - PRODUCT_LEN * 0.5)


## 見せる: 押さえの前でふくらむ → 前へ押し出され、鼻先が下がる → 台から床へ滑り下りる → 床を滑って止まる
func _move_product(_dt: float) -> void:
	if not _real.is_empty():
		_move_real()
		return
	var t := phase_t
	var s0 := _product_start()
	var o: Vector3 = _mark["out"]
	var p := s0
	var pitch := 0.0
	var sq := 1.0
	var tip_z := s0.z - 0.3
	var land_z := o.z + 0.35
	_prod_scl = Vector3.ONE * _ease_back(clampf(t / 0.25, 0.0, 1.0))
	if t < 0.25:
		pass
	elif t < 0.55:
		var u := (t - 0.25) / 0.3
		p.z = lerpf(s0.z, tip_z, u * u)
		pitch = -0.4 * u * u
	elif t < 0.85:
		var u := (t - 0.55) / 0.3
		p.z = lerpf(tip_z, land_z, 1.0 - (1.0 - u) * (1.0 - u))
		p.y = lerpf(s0.y, o.y, u * u)
		pitch = lerpf(-0.4, 0.0, u)
	else:
		if not _landed:
			_landed = true
			_fx2("sew_pop", -4.0, 0.6)
		var u := clampf((t - 0.85) / 0.45, 0.0, 1.0)
		p.y = o.y
		p.z = lerpf(land_z, o.z, 1.0 - (1.0 - u) * (1.0 - u))
		sq = 1.0 - 0.2 * exp(-(t - 0.85) * 8.0) * cos((t - 0.85) * 26.0)
	_prod_pos = p
	_prod_pitch = pitch
	if t > 0.25:
		_prod_scl = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))


## 本物のソリの見せる: 押さえの前に 1 m ほどの大きさで現れ → 前へ押し出されながら実寸までふくらみ →
## 台から床へ滑り下りて、少しつぶれて止まる。止まる所は、ミシンのまんなかの前（人の立つ所の並び）で、
## 後ろの端が「出口」の目印の少し奥。横に立つ売り子のおじさんとは重ならない
func _move_real() -> void:
	var t := phase_t
	var L: float = Sled.KINDS[_real.sled].box.z
	var s0 := _product_start()
	var o: Vector3 = _mark["out"]
	var land := Vector3(_mark["stand"].x, o.y, o.z - L * 0.5 + 0.6)
	var first := minf(1.0, 1.0 / L)   # 出はじめは長さ 1 m
	var p := s0
	var pitch := 0.0
	var grow := first * _ease_back(clampf(t / 0.25, 0.0, 1.0))
	var sq := 1.0
	if t >= 0.25 and t < 0.85:
		var u := (t - 0.25) / 0.6
		grow = lerpf(first, 1.0, _ease_back(u))
		p = s0.lerp(land, u * u * (3.0 - 2.0 * u))
		p.y = lerpf(s0.y, o.y, u * u) + 0.3 * sin(u * PI)
		pitch = -0.35 * sin(u * PI)
	elif t >= 0.85:
		if not _landed:
			_landed = true
			_fx2("sew_pop", -3.0, 0.5)
		grow = 1.0
		p = land
		sq = 1.0 - 0.15 * exp(-(t - 0.85) * 8.0) * cos((t - 0.85) * 26.0)
	_prod_pos = p
	_prod_pitch = pitch
	_prod_scl = Vector3(grow / sqrt(sq), grow * sq, grow / sqrt(sq))


## 縫い上がったソリを、本物のソリとして床に出す（craft.gd の sewn。見せるの形は消す）
func _deliver() -> void:
	if _real.is_empty() or _product == null:
		return
	var craft: Node = world.get("craft")
	var at := machine.to_global(_prod_pos)
	var fwd := -machine.global_basis.z
	craft.send({"kind": "sewn", "who": _real.who, "sled": _real.sled, "fabric": _real.fabric, "at": at,
			"yaw": atan2(-fwd.x, -fwd.z)})
	_product.queue_free()
	_product = null
	_real = {}


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur != null and cur != n:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# ---- 形に当てる ------------------------------------------------------------------

func _apply() -> void:
	var r: Transform3D
	_mv["needle"].position = _rest["needle"].origin + Vector3(0, _needle_h, 0)
	_mv["presser"].position = _rest["presser"].origin + Vector3(0, _presser_h, 0)
	_mv["feed"].position = _rest["feed"].origin + _feed_off
	r = _rest["balance"]
	_mv["balance"].transform = Transform3D(r.basis * Basis(Vector3.RIGHT, _wheel_a), r.origin)
	r = _rest["spool_red"]
	_mv["spool_red"].transform = Transform3D(r.basis * Basis(Vector3.UP, _spool_a[0]), r.origin + Vector3(0, _spool_hop[0], 0))
	r = _rest["spool_cream"]
	_mv["spool_cream"].transform = Transform3D(r.basis * Basis(Vector3.RIGHT, -_spool_a[1]), r.origin + Vector3(0, _spool_hop[1], 0))
	r = _rest["pedal"]
	_mv["pedal"].transform = Transform3D(r.basis * Basis(Vector3.RIGHT, _pedal_a), r.origin)
	if _cloth:
		_cloth.position = _cloth_pos
		_cloth.scale = _cloth_scl
	if _product:
		_product.transform = Transform3D(Basis(Vector3.RIGHT, _prod_pitch).scaled(_prod_scl), _prod_pos)
	_body.scale = Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5)
	_lamp.light_energy = 0.4 * _lamp_k
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = 1.6 * _lamp_k
	_draw_thread()


func _make_thread() -> void:
	_thread_mi = MeshInstance3D.new()
	_thread_mi.name = "Thread"
	_thread_mat = StandardMaterial3D.new()
	_thread_mat.albedo_color = Color("B8402E")
	_thread_mat.roughness = 0.95
	_thread_mat.rim_enabled = true
	_thread_mat.rim = 0.3
	_thread_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	machine.add_child(_thread_mi)


## 糸巻きから針までの糸。区間ごとに _sag だけ下へたわませ、縫っているあいだは針から布へも下ろす
func _draw_thread() -> void:
	var eye := machine.to_local(_eye.global_position) if _eye else _thread_pts[-1]
	var pts := _thread_pts.duplicate()
	pts.append(eye)
	var path := PackedVector3Array()
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var c := (a + b) * 0.5 + Vector3.DOWN * _sag * a.distance_to(b)
		for k in 4:
			var u := k / 4.0
			path.append(a.lerp(c, u).lerp(c.lerp(b, u), u))
	path.append(eye)
	var cloth_y: float = _mark["work"].y - 0.008
	if _tail > 0.0:   # 針から布へ
		path.append(Vector3(eye.x, cloth_y, eye.z))
	elif _snap > 0.0:   # 切った端が針へはね上がる
		path.append(Vector3(eye.x + 0.02 * _snap, lerpf(eye.y, cloth_y, _snap * _snap), eye.z - 0.03 * _snap))
	_thread_mi.mesh = _tube(path, 0.013, _thread_mat)


func _tube(path: PackedVector3Array, r: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	var n := path.size()
	for i in n:
		var t := (path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.1:
			side = t.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(t)
		for j in sides:
			var a := TAU * j / sides
			var nrm := side * cos(a) + up * sin(a)
			st.set_normal(nrm)
			st.add_vertex(path[i] + nrm * r)
	for i in n - 1:
		for j in sides:
			var j2 := (j + 1) % sides
			var a := i * sides + j
			var b := i * sides + j2
			var c := (i + 1) * sides + j2
			var d := (i + 1) * sides + j
			st.add_index(a)
			st.add_index(d)
			st.add_index(c)
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
	st.set_material(mat)
	return st.commit()


## 糸巻きの糸の端: 半回転が見えるよう、巻いた糸から短い端を垂らす（ゲームの側で足した形）
func _make_spool_tails() -> void:
	var k := 1.45   # 糸巻きは模型で 1.45 倍にした
	var specs := [["spool_red", Color("B8402E"),
			[Vector3(0.16, 0.30, 0.0), Vector3(0.2, 0.285, 0.0), Vector3(0.215, 0.23, 0.015), Vector3(0.208, 0.17, 0.03)]],
			["spool_cream", Color("EFE6D2"),
			[Vector3(0.1, 0.0, -0.162), Vector3(0.1, -0.05, -0.19), Vector3(0.11, -0.11, -0.2), Vector3(0.12, -0.16, -0.185)]]]
	for s in specs:
		var mi := MeshInstance3D.new()
		mi.name = "Tail"
		var m := StandardMaterial3D.new()
		m.albedo_color = s[1]
		m.roughness = 0.95
		var pts := PackedVector3Array()
		for q in s[2]:
			pts.append(q * k)
		mi.mesh = _tube(pts, 0.014, m)
		_mv[s[0]].add_child(mi)


func _make_lamp() -> void:
	_lamp = OmniLight3D.new()
	_lamp.name = "LampLight"
	_lamp.light_color = Color(1.0, 0.72, 0.46)
	_lamp.omni_range = 1.6
	_lamp.light_energy = 0.4
	_lamp.shadow_enabled = true   # 影がないと、台（ベッド）の下の天板まで照らしてしまう
	_lamp.position = _mark["lamp"] + Vector3(0, -0.05, 0)
	machine.add_child(_lamp)
	var paper := machine.find_child("*paper*", true, false) as MeshInstance3D
	if paper:
		var src := paper.get_surface_override_material(0)
		if src == null:
			src = paper.mesh.surface_get_material(0)
		if src is StandardMaterial3D:
			_lamp_mat = (src as StandardMaterial3D).duplicate()
			paper.set_surface_override_material(0, _lamp_mat)


## 綿くず: 針のまわりから、ふわっと舞い上がってゆっくり落ちる
func _make_lint() -> void:
	var p := CPUParticles3D.new()
	p.name = "Lint"
	p.emitting = false
	p.one_shot = true
	p.amount = 50
	p.lifetime = 2.4
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.local_coords = false
	p.position = _mark["work"] + Vector3(0, 0.05, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.1
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.3
	p.gravity = Vector3(0, -0.22, 0)
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(0.12, 1.0))
	grow.add_point(Vector2(1.0, 0.8))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.7, Color(1, 1, 1, 0.85))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.08
	q.material = Props._smoke_material()
	p.mesh = q
	machine.add_child(p)
	_lint = p
	set_stepped(stepped)


# ---- 音 ----------------------------------------------------------------------------
## 仮の音（sound/gen/sew.py）。main.gd の Audio があるときだけ鳴らす（--no-sound では鳴らない）

func _make_sound() -> void:
	_audio = world.get_node_or_null("Audio") if world else null
	if _audio == null:
		return
	var at: Vector3 = _mark["work"] + Vector3(0, 0.3, 0)
	for i in 3:
		_snd_stitch.append(_p3(at, -12.0))
	_snd_hum = _p3(at, -40.0)
	_snd_hum.stream = _audio._wav("sew_hum_loop")
	_snd_fx = _p3(at, -8.0)
	_snd_fx2 = _p3(at, -8.0)


func _p3(at: Vector3, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "Inside"
	p.volume_db = db
	p.unit_size = 3.0
	p.max_distance = 30.0
	p.position = at
	machine.add_child(p)
	return p


func _stitch_sound() -> void:
	if _snd_stitch.is_empty():
		return
	var p := _snd_stitch[_snd_next]
	_snd_next = (_snd_next + 1) % _snd_stitch.size()
	p.stream = _audio._wav("sew_stitch_%02d" % (_rng.randi_range(1, 3)))
	p.pitch_scale = 0.9 + 0.05 * _rate + _rng.randf_range(-0.03, 0.03)
	p.volume_db = -14.0 + 1.0 * minf(_rate, 6.0)
	p.play()


func _update_sound(_dt: float) -> void:
	if _snd_hum == null or _snd_hum.stream == null:
		return
	var on := _rate > 0.0 and phase in [Phase.CHARGE, Phase.RELEASE, Phase.SHOW, Phase.AFTER]
	if on and not _snd_hum.playing:
		_snd_hum.play()
	var target := -16.0 + 1.2 * minf(_rate, 9.0) if on else -50.0
	_snd_hum.volume_db = lerpf(_snd_hum.volume_db, target, 0.15)
	_snd_hum.pitch_scale = 0.7 + 0.08 * _rate
	if not on and _snd_hum.volume_db < -48.0:
		_snd_hum.stop()


func _fx(name: String, db: float, pitch := 1.0) -> void:
	_shot(_snd_fx, name, db, pitch)


func _fx2(name: String, db: float, pitch := 1.0) -> void:
	_shot(_snd_fx2, name, db, pitch)


func _shot(p: AudioStreamPlayer3D, name: String, db: float, pitch: float) -> void:
	if p == null:
		return
	p.stream = _audio._wav(name)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# ---- なめらかさ ------------------------------------------------------------------

static func _ease_io(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


## 少し行き過ぎて戻る（0 にはしない。大きさに使うと向きが壊れるので）
static func _ease_back(u: float) -> float:
	var c := 1.7
	var v := u - 1.0
	return maxf(0.01, 1.0 + (c + 1.0) * v * v * v + c * v * v)
