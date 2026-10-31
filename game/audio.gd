extends Node

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")
## Lodge の音。考え方は design/sound-concept.md。
## 場にあるものしか鳴らさない。外は響かない。言葉はない（声は言葉にならない「ワ〜」「ウン」「ンーン」だけ）。
##
## wav は sound/wav/ から実行時に読む（原型なので res:// の外。書き出すときは res:// に写す）。
## バス: Outdoor（外。ロッジの中ではこもる）← Speaker（柱の曲）、Wind（風）
##       Inside（ロッジの中。短い残響。外からは壁ごしにこもる）、Self（自分の足あと、戸）
## main.gd の _make_volume_buses() が、このあとに設定の音量バスを挿す:
##       Speaker → Music → Outdoor、Inside・Self → SFX → Master（Wind は Outdoor のまま、音量だけ SFX と同じ）、
##       息・声・スタンプの声は Voice → Master。バスの名前は設定が引くので変えない

const C_SOUND := 340.0          # 音の速さ (m/s)。柱ごとの遅れに使う
const SPEAKER_RATE := 16000     # 柱の曲の生成ストリームのレート。曲は 4 kHz までしかないので足りる
const POST_R := 95.0            # 柱を立てる半径 (m)。麓のずっと外、ロッジや木より外。頂上には置かない（2026-10-28 代表）
const POST_A0 := 75.0           # 1 本目の柱の角度 (度)。60° おきに 6 本。ロッジ（約 110°）に重ならない向き
const POST_H := 4.2
const LODGE_HALF := Vector2(21.8, 12.7)   # ロッジ 1 階の半分の幅と奥行き（glb の座標）
const VEST := Vector3(-13.4, 0.0, 15.2)   # 風除室の中心（glb の座標。南＝+Z が正面）
const VEST_HALF := Vector2(4.0, 2.5)
const STRIDE := 2.0             # 一歩の長さ (m)

var world: Node3D
var sled: RigidBody3D
var player: CharacterBody3D
var bots: Array = []
var lodge: Node3D
var rng := RandomNumberGenerator.new()
var debug := ""
## 確かめ用: true のあいだ、鳴らした音を played に書きとめる {t（ゲームの秒）, name, near（耳元か）, dist（聞く所からの m）, wind（滑走の風の dB）}
var log_on := false
var played: Array = []

var _streams := {}
var _last_pick := {}
var _posts: Array = []          # {node, player, pb, cursor, last_delay, sway}
var _pcm := PackedFloat32Array()
var _clock := 0.0
var _noise := FastNoiseLite.new()
var _zone := -1                 # 0 外、1 風除室、2 中
var _launched := false
var _rush_gate := 1.0

var _runner_fast: AudioStreamPlayer3D
var _creak: AudioStreamPlayer3D
var _wind_calm: AudioStreamPlayer
var _wind_rush: AudioStreamPlayer
var _self_step: AudioStreamPlayer
var _self_breath: AudioStreamPlayer
var _door: AudioStreamPlayer3D
var _fire_crack: AudioStreamPlayer3D
var _pot_lid: AudioStreamPlayer3D
var _dish: AudioStreamPlayer3D
var _dish_spots: Array[Vector3] = []
var _timers := {"crack": 2.0, "lid": 8.0, "dish": 5.0, "creak": 1.0}
var _walkers := {}              # 歩く人 → {acc, push_t, breath_t, pushing, step, breath}


func setup(w: Node3D, s: RigidBody3D, p: CharacterBody3D, b: Array, l: Node3D) -> void:
	world = w
	sled = s
	player = p
	bots = b
	lodge = l
	rng.seed = 3
	_noise.seed = 9
	_noise.frequency = 0.05


func _ready() -> void:
	_make_buses()
	_make_posts()
	_make_sled()
	_make_wind()
	_make_walkers()
	_make_lodge()
	_set_zone(0)
	var hub := world.get_node_or_null("Emotes")
	if hub:
		hub.happened.connect(_on_emote)


# ---- 読み込み ---------------------------------------------------------------

func _wav(name: String) -> AudioStreamWAV:
	if _streams.has(name):
		return _streams[name]
	var path := ProjectSettings.globalize_path("res://").path_join("../sound/wav/%s.wav" % name)
	if not FileAccess.file_exists(path):
		path = ProjectSettings.globalize_path("res://sound/wav/%s.wav" % name)
	var s: AudioStreamWAV = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	if s == null:
		push_warning("音が見つからない: " + name)
	elif name.ends_with("_loop"):
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / 2   # 16 bit モノラル
	_streams[name] = s
	return s


## 番号つきの音から、前と違うものを選ぶ
func _pick(prefix: String, count: int) -> AudioStreamWAV:
	var i := rng.randi_range(1, count)
	if count > 1 and _last_pick.get(prefix, 0) == i:
		i = i % count + 1
	_last_pick[prefix] = i
	return _wav("%s_%02d" % [prefix, i])


func _p3(parent: Node3D, bus: String, db: float, unit := 6.0, max_dist := 60.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = max_dist
	p.attenuation_filter_cutoff_hz = 6000
	p.attenuation_filter_db = -18
	parent.add_child(p)
	return p


func _shot(p: AudioStreamPlayer3D, s: AudioStreamWAV, db: float, pitch := 1.0) -> void:
	if s == null:
		return
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _shot2(p: AudioStreamPlayer, s: AudioStreamWAV, db: float, pitch := 1.0) -> void:
	if s == null:
		return
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


# ---- バス -------------------------------------------------------------------

func _make_buses() -> void:
	var lp_out := AudioEffectLowPassFilter.new()
	lp_out.cutoff_hz = 600
	_bus("Outdoor", "Master", [lp_out])
	_bus("Speaker", "Outdoor", [])
	_bus("Wind", "Outdoor", [])
	var rv := AudioEffectReverb.new()   # 木の部屋。短く
	rv.room_size = 0.25
	rv.damping = 0.6
	rv.wet = 0.12
	rv.dry = 1.0
	rv.predelay_msec = 12
	var lp_in := AudioEffectLowPassFilter.new()
	lp_in.cutoff_hz = 600
	_bus("Inside", "Master", [rv, lp_in])
	_bus("Self", "Master", [])


func _bus(bus_name: String, send: String, effects: Array) -> void:
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, send)
	for e in effects:
		AudioServer.add_bus_effect(i, e)


## バスの音量を変える（dur 秒かけて）。バスは毎回名前で引く: 変えているあいだに main.gd が設定の音量バス（SFX・Voice・Music）を
## 差し込むと番号がずれ、番号で覚えていると別のバス（設定の音量）を書きかえてしまう（2026-10-30 に、効果音と音楽が設定より大きく、
## 声が埋もれていた原因）
func _bus_db(bus_name: String, db: float, dur := 0.0) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	if dur <= 0.0:
		AudioServer.set_bus_volume_db(i, db)
		return
	var tw := create_tween()
	tw.tween_method(func(v: float):
		var j := AudioServer.get_bus_index(bus_name)
		if j >= 0:
			AudioServer.set_bus_volume_db(j, v), AudioServer.get_bus_volume_db(i), db, dur)


func _bus_lowpass(bus_name: String, slot: int, enabled: bool, cutoff := 600.0) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_effect_enabled(i, slot, enabled)
	var e := AudioServer.get_bus_effect(i, slot) as AudioEffectLowPassFilter
	if e:
		e.cutoff_hz = cutoff


# ---- 柱のスピーカー -----------------------------------------------------------

## 同じ曲を柱ごとに遅らせて読む。遅れは聞く人との距離 / 音の速さ。近づくと縮み、離れると伸びるので、
## 追い越すときの高さの変化（ドップラー）も自然に出る。曲はラッパ型の色を焼き込んだ wav
func _make_posts() -> void:
	var src := _wav("music_speaker_loop")
	if src == null:
		return
	var d := src.data
	var n := d.size() / 2
	_pcm.resize(n / 3)
	for i in _pcm.size():   # 48 kHz → 16 kHz（曲は 4 kHz までなので間引くだけでよい）
		_pcm[i] = d.decode_s16(i * 6) / 32768.0
	var pole_mat := Look.wood(Color(0.32, 0.24, 0.17))
	var horn_mat := Look.felt(Color(0.55, 0.56, 0.58), 1.5)
	for k in 6:
		var a := deg_to_rad(POST_A0 + 60.0 * k)
		var x := cos(a) * POST_R
		var z := sin(a) * POST_R
		var node := Node3D.new()
		node.name = "SpeakerPost%d" % k
		node.position = Vector3(x, world.height(x, z), z)
		world.add_child(node)
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.09
		cyl.height = POST_H
		pole.mesh = cyl
		pole.material_override = pole_mat
		pole.position.y = POST_H / 2
		node.add_child(pole)
		var head := Node3D.new()   # ラッパ。丘の方を向く
		head.position.y = POST_H - 0.3
		node.add_child(head)
		head.look_at(Vector3(0, world.HILL_H * 0.6, 0), Vector3.UP)
		var horn := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.22
		cone.bottom_radius = 0.06
		cone.height = 0.5
		horn.mesh = cone
		horn.material_override = horn_mat
		horn.rotation.x = -PI / 2
		horn.position.z = -0.25
		head.add_child(horn)
		var p := AudioStreamPlayer3D.new()
		p.bus = "Speaker"
		p.unit_size = 9.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 3800   # 雪と空気が高い音を先に吸う
		p.attenuation_filter_db = -30
		p.emission_angle_enabled = true          # ラッパの向きの外では細る
		p.emission_angle_degrees = 60.0
		p.emission_angle_filter_attenuation_db = -14.0
		p.volume_db = 2.0
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = SPEAKER_RATE
		gen.buffer_length = 0.25
		p.stream = gen
		head.add_child(p)
		p.play()
		_posts.append({"node": node, "player": p, "pb": p.get_stream_playback(),
				"cursor": 0.0, "last_delay": -1.0, "sway": rng.randf() * 1000.0})


func _feed_posts(listener: Vector3) -> void:
	if _pcm.is_empty():
		return
	var n_pcm := _pcm.size()
	for post in _posts:
		var pb: AudioStreamGeneratorPlayback = post.pb
		if pb == null:
			continue
		var n: int = mini(pb.get_frames_available(), 4096)
		if n <= 0:
			continue
		var d1: float = listener.distance_to(post.node.global_position) / C_SOUND
		var d0: float = post.last_delay if post.last_delay >= 0.0 else d1
		var cursor: float = post.cursor
		var buf := PackedVector2Array()
		buf.resize(n)
		for k in n:
			var t_emit: float = cursor + float(k) / SPEAKER_RATE - lerpf(d0, d1, float(k) / n)
			var idx := fposmod(t_emit * SPEAKER_RATE, float(n_pcm))
			var i0 := int(idx)
			var v := lerpf(_pcm[i0], _pcm[(i0 + 1) % n_pcm], idx - i0)
			buf[k] = Vector2(v, v)
		pb.push_buffer(buf)
		post.cursor = cursor + float(n) / SPEAKER_RATE
		post.last_delay = d1
		# 風で近づいたり遠のいたり。柱ごとに位相が違う
		post.player.volume_db = 2.0 + 3.5 * _noise.get_noise_1d(_clock * 6.0 + post.sway)


# ---- ソリ -----------------------------------------------------------------------

func _make_sled() -> void:
	_runner_fast = _p3(sled, "Outdoor", -80, 5.0, 50.0)
	_runner_fast.stream = _wav("runner_fast_loop")
	_runner_fast.play()
	_creak = _p3(sled, "Outdoor", -14, 4.0, 30.0)


func _update_sled(dt: float) -> void:
	# 滑り木は「しゃー」の 1 本だけ。止まりかけの「ざ、ざ」は代表が要らないと言ったので外した（2026-10-27）
	var v := sled.linear_velocity.length()
	var fast := lerpf(-60.0, -6.0, clampf((v - 0.4) / 7.2, 0.0, 1.0)) if v > 0.3 else -80.0
	_runner_fast.volume_db = lerpf(_runner_fast.volume_db, fast, minf(1.0, dt * 8.0))
	_runner_fast.pitch_scale = clampf(0.85 + 0.04 * v, 0.85, 1.25)
	# 押す力が入った瞬間に、まれに木がきしむ
	_timers.creak -= dt
	if sled.pushers > 0 and v < 1.5 and _timers.creak <= 0.0:
		_timers.creak = rng.randf_range(0.5, 1.5)
		if rng.randf() < 0.12:
			_shot(_creak, _pick("sled_creak", 3), -14.0, rng.randf_range(0.95, 1.05))


# ---- 風と、滑り出す一瞬 ----------------------------------------------------------------

func _make_wind() -> void:
	_wind_calm = AudioStreamPlayer.new()
	_wind_calm.bus = "Wind"
	_wind_calm.stream = _wav("wind_loop")
	_wind_calm.volume_db = -26
	add_child(_wind_calm)
	_wind_calm.play()
	_wind_rush = AudioStreamPlayer.new()
	_wind_rush.bus = "Wind"
	_wind_rush.stream = _wav("wind_rush_loop")
	_wind_rush.volume_db = -60
	add_child(_wind_rush)
	_wind_rush.play()


func _riding() -> bool:
	if player:
		return player.mode == player.Mode.RIDE
	return sled.riders.size() > 0


func _update_wind(dt: float, listener: Vector3) -> void:
	# 麓は薄く、高いほど強い
	var h := clampf(listener.y / world.HILL_H, 0.0, 1.0)
	var calm := lerpf(-26.0, -14.0, h)
	_wind_calm.volume_db = lerpf(_wind_calm.volume_db, calm, minf(1.0, dt * 2.0))
	# 滑走の風は速さで。滑り出しの無音のあと、ゲートが開いて立ち上がる
	var v := sled.linear_velocity.length() if _riding() else 0.0
	var rush := lerpf(-50.0, -5.0, clampf((v - 1.5) / 6.5, 0.0, 1.0)) * 1.0
	rush = lerpf(-60.0, rush, _rush_gate)
	_wind_rush.volume_db = lerpf(_wind_rush.volume_db, rush, minf(1.0, dt * 3.0))
	_wind_rush.pitch_scale = clampf(0.9 + 0.035 * v, 0.9, 1.2)
	# 滑り出す一瞬: 乗ってそろって動き出したら、外の音が消え、息ひとつ、風が立ち上がる
	var speed := sled.linear_velocity.length()
	if _riding() and not _launched and speed > 1.5:
		_launched = true
		_launch()
	if speed < 0.6 or not _riding():
		_launched = false


func _launch() -> void:
	_rush_gate = 0.0
	_bus_db("Outdoor", -60.0, 0.3)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(_breath_once)
	tw.tween_interval(0.55)
	tw.tween_callback(func(): _bus_db("Outdoor", _zone_outdoor_db(), 1.6))
	tw.tween_method(_set_gate, 0.0, 1.0, 1.5)


func _breath_once() -> void:
	if player:
		_shot2(_self_breath, _pick("breath", 4), -18.0, 1.0)


func _set_gate(g: float) -> void:
	_rush_gate = g


# ---- 足あとと息 -------------------------------------------------------------------

func _make_walkers() -> void:
	if player:
		_self_step = AudioStreamPlayer.new()
		_self_step.bus = "Self"
		add_child(_self_step)
		_self_breath = AudioStreamPlayer.new()
		_self_breath.bus = "Voice"   # 息は Voice（main.gd の設定の音量バス。再生時に名前で引く）
		add_child(_self_breath)
		_walkers[player] = {"acc": 0.0, "push_t": 0.4, "breath_t": 2.0, "pushing": 0.0, "step": _self_step, "breath": _self_breath}
	for b in bots:
		_walkers[b] = {"acc": rng.randf(), "push_t": rng.randf(), "breath_t": rng.randf_range(1.0, 3.0), "pushing": 0.0,
				"step": _p3(b, "Outdoor", -8, 4.0, 40.0), "breath": _p3(b, "Voice", -16, 3.0, 20.0)}


func _update_walkers(dt: float) -> void:
	for who in _walkers:
		var w: Dictionary = _walkers[who]
		var is_player: bool = who == player
		var vel: Vector3 = who.velocity
		var speed := Vector2(vel.x, vel.z).length()
		var pushing: bool
		var free: bool
		if is_player:
			pushing = (player.mode == player.Mode.GRIP and player.pushing) or (player.mode == player.Mode.ROPE and player.pulling)
			free = player.mode == player.Mode.WALK or player.mode == player.Mode.ROPE
		else:
			pushing = who.handle != Vector3.INF and sled.pushers > 0
			free = who.handle == Vector3.INF and who.seat == Vector3.INF
		# 引きずられている: かかとが雪をすべる「ざざざ」。踏ん張りの音を速く、速いほど大きく高く。息も上がる
		var dragged: bool = who.handle != Vector3.INF and sled.is_dragged(who)
		var inside := _zone_of(who.global_position) == 2
		var db_step := -10.0 if is_player else -8.0
		if dragged:
			var sv := sled.linear_velocity.length()
			w.drag_t = w.get("drag_t", 0.0) - dt
			if w.drag_t <= 0.0:
				w.drag_t = rng.randf_range(0.09, 0.15)
				_play_step(w, _pick("step_snow_push", 4), db_step - 4.0 + 4.0 * clampf(sv / 6.0, 0.0, 1.0),
						rng.randf_range(1.1, 1.25) + 0.02 * sv, is_player)
			pushing = true
		if free and speed > 0.5 and who.is_on_floor():
			w.acc += speed * dt
			var stride := STRIDE + 0.3 * clampf((speed - 4.0) / 3.0, 0.0, 1.0)
			if w.acc >= stride:
				w.acc = 0.0
				var s := _pick("step_wood", 4) if inside else _pick("step_snow", 6)
				var loud := db_step + 4.0 * clampf((speed - 4.0) / 3.0, 0.0, 1.0)
				_play_step(w, s, loud, rng.randf_range(0.94, 1.06), is_player)
		else:
			w.acc = minf(w.acc, STRIDE * 0.6)
		if pushing:
			w.pushing += dt
			w.push_t -= dt
			if w.push_t <= 0.0:
				w.push_t = rng.randf_range(0.8, 1.1)
				_play_step(w, _pick("step_snow_push", 4), db_step - 2.0, rng.randf_range(0.95, 1.05), is_player)
			w.breath_t -= dt
			if w.breath_t <= 0.0:
				w.breath_t = lerpf(4.0, 2.0, clampf(w.pushing / 20.0, 0.0, 1.0)) * rng.randf_range(0.85, 1.15)
				var s := _pick("breath", 4)
				if is_player:
					_shot2(w.breath, s, -16.0, rng.randf_range(0.95, 1.05))
				else:
					_shot(w.breath, s, -14.0, rng.randf_range(0.9, 1.1))
		else:
			w.pushing = maxf(0.0, w.pushing - dt * 2.0)   # 休むと息が落ち着く
			w.push_t = minf(w.push_t, 0.4)
			w.breath_t = maxf(w.breath_t, 1.5)


## 米袋に乗ったまま足で雪を蹴った（player.gd が呼ぶ）。踏ん張りの音を短く高めに
func kick(who: Node3D) -> void:
	var w: Dictionary = _walkers.get(who, {})
	if w.is_empty():
		return
	_play_step(w, _pick("step_snow_push", 4), -6.0, rng.randf_range(1.15, 1.3), who == player)


## 米袋を出す・座る・しまう（player.gd が呼ぶ）。what: "fling" ばさっと広げる / "sit" ぽふっと座る / "roll" くるくる丸める
func sack(who: Node3D, what: String) -> void:
	var near := who == player
	var at := who.global_position + Vector3.UP * 0.3
	var ev := {"frame": Doll.frame_index()}
	match what:
		"fling":
			_emote_sound(ev, 0, "swish", 2, -8.0, rng.randf_range(0.78, 0.86), at, near)
		"sit":
			_emote_sound(ev, 0, "felt_pat", 3, -2.0, rng.randf_range(0.62, 0.7), at, near)
			_emote_sound(ev, 0, "snow_splat", 3, -13.0, rng.randf_range(1.1, 1.2), at, near)
		"roll":
			_emote_sound(ev, 2, "swish", 2, -15.0, rng.randf_range(1.25, 1.4), at, near)
			_emote_sound(ev, 8, "felt_pat", 3, -8.0, rng.randf_range(1.1, 1.2), at, near)


## お金のボタンが財布に入った瞬間の音（craft_ui.gd が、飛んでいったボタンが財布に着くたびに呼ぶ）。自分の耳元で鳴らす。
## 1 枚ごとに、ボタンが財布の山に当たって重なる硬く軽い「チャリ」（button_chari、8 つから選ぶ）。続けて入るときは
## COIN_GAP のあいだ（少しずつばらつかせる）で続けて鳴らし、チャリチャリチャリ…と小気味よく連なる（2026-10-30 代表）。
## 真鍮・白蝶貝・螺鈿は、そのチャリに素材の音（チン・シャラン・螺鈿の特別な音）を重ねて、連打の中で光らせる
const COIN_GAP := Vector2(0.05, 0.075)
const COIN_SHINE := {"brass": ["button_take_brass", -3.0], "pearl": ["button_take_pearl", -2.0], "raden": ["button_take_raden", 1.0]}
var _coin_at := 0.0   # 次のチャリを鳴らせる時刻（_clock）


## step: 続けて入る何枚目か（0 から）。続くほど、ほんの少しずつ音が上がる
func coin(look: String, step := 0) -> void:
	var wait := maxf(0.0, _coin_at - _clock)
	_coin_at = _clock + wait + rng.randf_range(COIN_GAP.x, COIN_GAP.y)
	if wait > 0.0:
		await get_tree().create_timer(wait).timeout
	var s := _pick("button_chari", 8)
	if s == null:
		return
	_note("button_chari", true, Vector3.ZERO)
	var p := AudioStreamPlayer.new()
	p.bus = "Self"
	add_child(p)
	_shot2(p, s, rng.randf_range(-3.0, -1.0), (1.0 + 0.012 * mini(step, 16)) * rng.randf_range(0.92, 1.08))
	p.finished.connect(p.queue_free)
	if COIN_SHINE.has(look):   # 上の素材: 連打の中で光る
		var spec: Array = COIN_SHINE[look]
		var t := _wav("%s_01" % spec[0])
		if t:
			_note(spec[0], true, Vector3.ZERO)
			var q := AudioStreamPlayer.new()
			q.bus = "Self"
			add_child(q)
			_shot2(q, t, spec[1], rng.randf_range(0.98, 1.03))
			q.finished.connect(q.queue_free)


## 滑っている最中、速さの表示の糸の上にボタンが縫い付いて積もる（hud.gd が呼ぶ）。ぷつっ・ころん。真鍮は、きらっを重ねる。
## 耳元で、滑走の風に埋もれない大きさ（2026-10-30 代表「滑り降りている最中もスタックする報酬のコインの音はしてほしい」）
func stitch(look: String) -> void:
	var s := _pick("button_stitch", 3)
	if s == null:
		return
	_note("button_stitch", true, Vector3.ZERO)
	var p := AudioStreamPlayer.new()
	p.bus = "Self"
	add_child(p)
	_shot2(p, s, 0.0, rng.randf_range(0.94, 1.06))
	p.finished.connect(p.queue_free)
	if look != "wood":
		var g := _wav("button_glint_01")
		if g:
			_note("button_glint", true, Vector3.ZERO)
			var q := AudioStreamPlayer.new()
			q.bus = "Self"
			add_child(q)
			_shot2(q, g, -1.0, rng.randf_range(0.98, 1.03))
			q.finished.connect(q.queue_free)


## 止まらずに滑って、距離の節目でコンボが一段上がった（level 1〜）・切れた（level 0）（hud.gd が呼ぶ）。耳元で、滑走の風に埋もれない大きさ。
## 上がるたびに、木琴と鈴の音が五音音階で一つずつ上がり、段が上がるほどきらめきが増える（8 段より上は 8 段目の音）。
## 切れたら、短くやさしく下がる 2 音（2026-10-31 代表「コンボしていることを、なにかで表示＋気持ちがいい音を追加で出してほしい」）
func combo(level: int) -> void:
	var name_ := "button_combo_%02d" % clampi(level, 1, 8) if level > 0 else "button_combo_break_01"
	var s := _wav(name_)
	if s == null:
		return
	_note(name_, true, Vector3.ZERO)
	var p := AudioStreamPlayer.new()
	p.bus = "Self"
	add_child(p)
	_shot2(p, s, 1.0 if level > 0 else -2.0, 1.0)
	p.finished.connect(p.queue_free)


## 速さの表示の糸の上で、同じ素材が 10 個たまって上の素材に両替された（hud.gd が呼ぶ）。look は変わってできた素材。
## その素材の音（真鍮のチン・白蝶貝のシャラン・螺鈿）を少し小さく、きらっを重ねて、耳元で
func exchange(look: String) -> void:
	var spec: Array = COIN_SHINE.get(look, COIN_SHINE["brass"])
	var s := _wav("%s_01" % spec[0])
	if s:
		_note(spec[0], true, Vector3.ZERO)
		var p := AudioStreamPlayer.new()
		p.bus = "Self"
		add_child(p)
		_shot2(p, s, spec[1] - 1.0, 1.0)
		p.finished.connect(p.queue_free)
	var g := _wav("button_glint_01")
	if g:
		_note("button_glint", true, Vector3.ZERO)
		var q := AudioStreamPlayer.new()
		q.bus = "Self"
		add_child(q)
		_shot2(q, g, -3.0, 1.0)
		q.finished.connect(q.queue_free)


## 速さの表示の糸の上のボタンが、ぽんと外れて財布へ飛び出す（ぷつ。小さく高く、耳元で）
func coin_off() -> void:
	var s := _pick("button_snap", 3)
	if s == null:
		return
	_note("button_snap", true, Vector3.ZERO)
	var p := AudioStreamPlayer.new()
	p.bus = "Self"
	add_child(p)
	_shot2(p, s, -16.0, rng.randf_range(1.3, 1.45))
	p.finished.connect(p.queue_free)


## 滑り終わって、もらったボタンが全部財布に入ったときの締めくくり（ちゃりん）。count 枚、brass は真鍮が混ざったか。
## 少し（〜5）・ふつう（〜12）・たくさんか真鍮入りで、3 つの大きさ。最後の取得音のすぐあとに、耳元で
func reward(count: int, brass: bool) -> void:
	var size := 3 if brass or count > 12 else (2 if count > 5 else 1)
	var wait := maxf(0.0, _coin_at - _clock) + 0.08
	_coin_at = _clock + wait + 0.3
	await get_tree().create_timer(wait).timeout
	var s := _wav("button_reward_%02d" % size)
	if s == null:
		return
	_note("button_reward_%02d" % size, true, Vector3.ZERO)
	var p := AudioStreamPlayer.new()
	p.bus = "Self"
	add_child(p)
	_shot2(p, s, [0.0, -1.0, 0.0, 1.0][size], 1.0)
	p.finished.connect(p.queue_free)


## 雪に縫い留められたボタン（snow_buttons.gd が呼ぶ）。frame は出来事のコマ。その場所から鳴らす。
## what: "snap" 糸がぷつん / "pop" ボタンがぽん / "land" 降ってきて雪にぽふ / "sew" 糸がするっと縫い付く /
##       "take" 取った（tier: 0 木のコッ・1 真鍮のチン・2 白蝶貝のシャラン・3 螺鈿） / "shears" 裁ちばさみのシャキン / "swish" はさみを出す
func button(what: String, at: Vector3, frame: int, tier := 0) -> void:
	var ev := {"frame": frame}
	match what:
		"snap":
			_emote_sound(ev, 0, "button_snap", 3, -4.0, rng.randf_range(0.95, 1.08), at, false)
		"pop":
			_emote_sound(ev, 0, "button_pop", 3, -2.0, rng.randf_range(0.94, 1.06), at, false)
		"land":
			_emote_sound(ev, 0, "button_land", 2, -12.0, rng.randf_range(0.9, 1.1), at, false)
		"sew":
			_emote_sound(ev, 0, "button_sew", 1, -14.0, rng.randf_range(0.95, 1.05), at, false)
		"take":
			var name_: String = ["button_take_wood", "button_take_brass", "button_take_pearl", "button_take_raden"][clampi(tier, 0, 3)]
			_emote_sound(ev, 0, name_, 1, [-4.0, -3.0, -2.0, 0.0][clampi(tier, 0, 3)], 1.0, at, false)
		"shears":
			_emote_sound(ev, 0, "shears", 2, -3.0, rng.randf_range(0.96, 1.05), at, false)
		"swish":
			_emote_sound(ev, 0, "swish", 2, -14.0, rng.randf_range(1.3, 1.45), at, false)


func _play_step(w: Dictionary, s: AudioStreamWAV, db: float, pitch: float, is_player: bool) -> void:
	if is_player:
		_shot2(w.step, s, db, pitch)
	else:
		_shot(w.step, s, db, pitch)


# ---- ロッジ ------------------------------------------------------------------------

func _make_lodge() -> void:
	if lodge == null:
		return
	var fire := _marker("light_fire", Vector3(-10.4, 1.0, -10.8))
	var kitchen := _marker("light_kitchen", Vector3(-8.0, 1.2, -9.0))
	var bed := _p3(lodge, "Inside", -10, 4.0, 60.0)
	bed.position = fire
	bed.stream = _wav("fire_bed_loop")
	bed.play()
	_fire_crack = _p3(lodge, "Inside", -8, 4.0, 60.0)
	_fire_crack.position = fire
	var steam := _p3(lodge, "Inside", -16, 3.0, 40.0)
	steam.position = kitchen
	steam.stream = _wav("pot_steam_loop")
	steam.play()
	_pot_lid = _p3(lodge, "Inside", -14, 3.0, 40.0)
	_pot_lid.position = kitchen
	_dish = _p3(lodge, "Inside", -12, 3.0, 40.0)
	for n in lodge.find_children("light_lamp_*", "", true, false):
		_dish_spots.append(lodge.to_local((n as Node3D).global_position) - Vector3(0, 1.3, 0))
	if _dish_spots.is_empty():
		_dish_spots.append(Vector3(0, 1.0, 6.0))
	_door = _p3(lodge, "Self", -8, 4.0, 40.0)   # Master に直結しない（Self → SFX の音量を通す）
	_door.position = _marker("light_vestibule", VEST)


func _marker(marker_name: String, fallback: Vector3) -> Vector3:
	var n := lodge.find_child(marker_name, true, false)
	return lodge.to_local((n as Node3D).global_position) if n else fallback


func _update_lodge(dt: float) -> void:
	if lodge == null:
		return
	_timers.crack -= dt
	if _timers.crack <= 0.0:
		_timers.crack = rng.randf_range(1.0, 4.0)
		_shot(_fire_crack, _pick("fire_crack", 8), rng.randf_range(-12.0, -5.0), rng.randf_range(0.9, 1.1))
	_timers.lid -= dt
	if _timers.lid <= 0.0:
		_timers.lid = rng.randf_range(6.0, 15.0)
		_shot(_pot_lid, _pick("pot_lid", 3), -14.0, rng.randf_range(0.95, 1.05))
	_timers.dish -= dt
	if _timers.dish <= 0.0:
		_timers.dish = rng.randf_range(4.0, 10.0)
		_dish.position = _dish_spots[rng.randi() % _dish_spots.size()]
		_shot(_dish, _pick("dish", 6), -12.0, rng.randf_range(0.95, 1.05))


## 0 外、1 風除室、2 中
func _zone_of(pos: Vector3) -> int:
	return zone_at(lodge, pos)


## ロッジに対して、その位置が 0 外・1 風除室・2 中のどこか（temperature.gd も、この判定で中か外かを決める）
static func zone_at(lodge: Node3D, pos: Vector3) -> int:
	if lodge == null:
		return 0
	var l := lodge.to_local(pos)
	if absf(l.x) < LODGE_HALF.x and absf(l.z) < LODGE_HALF.y and l.y > -1.0 and l.y < 12.0:
		return 2
	if absf(l.x - VEST.x) < VEST_HALF.x and absf(l.z - VEST.z) < VEST_HALF.y and l.y > -1.0 and l.y < 6.0:
		return 1
	return 0


func _zone_outdoor_db() -> float:
	return [0.0, -6.0, -12.0][_zone]


func _set_zone(z: int) -> void:
	if z == _zone:
		return
	var prev := _zone
	_zone = z
	match z:
		0:
			_bus_lowpass("Outdoor", 0, false)
			_bus_lowpass("Inside", 1, true, 600.0)
			_bus_db("Inside", -10.0, 0.4)
		1:
			_bus_lowpass("Outdoor", 0, true, 1500.0)
			_bus_lowpass("Inside", 1, true, 1500.0)
			_bus_db("Inside", -5.0, 0.4)
		2:
			_bus_lowpass("Outdoor", 0, true, 600.0)
			_bus_lowpass("Inside", 1, false)
			_bus_db("Inside", 0.0, 0.4)
	if not _launched:
		_bus_db("Outdoor", _zone_outdoor_db(), 0.4)
	if prev >= 0 and _door:   # 戸を通った
		_shot(_door, _wav("door_open"), -8.0)
		var tw := create_tween()
		tw.tween_interval(0.9)
		tw.tween_callback(func(): _shot(_door, _wav("door_close"), -6.0))


## --spawn=lodge（風除室の前、デッキの手前）、--spawn=inside（食堂の中、炉の近く）の立ち位置
func spawn_point(where: String) -> Vector3:
	if lodge == null:
		return Vector3.ZERO
	var local := Vector3(VEST.x, 0.0, VEST.z + 6.0) if where == "lodge" else Vector3(6.0, 0.5, -4.0)
	var p := lodge.to_global(local)
	if where == "lodge":
		p.y = world.height(p.x, p.z) + 0.2
	return p


# ---- 毎フレーム ----------------------------------------------------------------------

func _listener() -> Vector3:
	if player:
		return player.global_position + Vector3.UP * 1.55
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _process(dt: float) -> void:
	_clock += dt
	_feed_posts(_listener())


func _physics_process(dt: float) -> void:
	var listener := _listener()
	_set_zone(_zone_of(listener))
	_update_sled(dt)
	_update_wind(dt, listener)
	_update_walkers(dt)
	_update_lodge(dt)
	if not _posts.is_empty():
		var near: Dictionary = _posts[0]
		var best := INF
		for post in _posts:
			var d: float = listener.distance_to(post.node.global_position)
			if d < best:
				best = d
				near = post
		debug = "音: 区域=%d 風=%.0f/%.0f dB 滑り木=%.0f dB 近い柱 %.0f m 遅れ %.0f ms ゲート %.1f" % [
				_zone, _wind_calm.volume_db, _wind_rush.volume_db, _runner_fast.volume_db,
				best, near.last_delay * 1000.0, _rush_gate]


# ---- 身ぶりと声（emotes.gd の出来事） ------------------------------------------
# 声は Voice、身ぶりの小さな音は Self（自分）か Outdoor（人の）。人形の姿勢と同じコマで鳴らす

## 身ぶりの何コマ目に、どの音を鳴らすか: [コマ, 名前, 数, 音量 dB, 高さ]
const EMOTE_SOUNDS := {
	"wa": [[2, "voice_wa", 3, -4.0, 1.0]],
	"un": [[0, "voice_un", 3, -5.0, 1.0]],
	"nn": [[0, "voice_nn", 3, -5.0, 1.0]],
	"huh": [[2, "voice_unq", 3, -5.0, 1.0]],
	"oi": [[2, "voice_oi", 3, -1.0, 1.0]],    # 遠くまで届く（_emote_sound で、届く距離を長く）
	"hit": [[0, "voice_surprise", 3, -4.0, 1.0]],   # 雪玉が当たって、わっ
	"whiff": [[2, "swish", 2, -10.0, 1.0]],
	"throw": [[0, "swish", 2, -8.0, 1.15]],
	"clap": [[2, "felt_pat", 3, -12.0, 1.3], [6, "felt_pat", 3, -12.0, 1.25], [10, "felt_pat", 3, -12.0, 1.3], [14, "felt_pat", 3, -12.0, 1.2]],
	"make_ball": [[4, "step_snow", 6, -16.0, 1.7], [6, "step_snow", 6, -17.0, 1.8], [8, "step_snow", 6, -16.0, 1.7], [10, "step_snow", 6, -17.0, 1.8], [12, "step_snow", 6, -16.0, 1.75], [14, "step_snow", 6, -18.0, 1.9]],
	"breath": [[0, "breath", 4, -22.0, 1.1], [5, "breath", 4, -14.0, 0.6]],
}


func _on_emote(ev: Dictionary) -> void:
	var hub: Node = world.get_node("Emotes")
	var who: Node3D = hub.who_of(ev.get("who", -1)) if ev.has("who") else null
	var is_self: bool = who != null and who == player
	# 声は人形ごとの wav（sound/wav/voice_*_<人形>。高さは性別と身長で wav に焼き込んである）
	var doll_kind: String = (who.get("doll") as Doll).kind if who and who.get("doll") != null else "kasa"
	match ev.kind:
		"high_five", "shake":
			# 二人に配られるので、片方のぶんだけ鳴らす。手が合う所で（握手は低く、そっと握る音）
			if ev.who < ev.with:
				var near_self: bool = who == player or hub.who_of(ev.with) == player
				var at: Vector3 = ev.grips[0][1]
				if ev.kind == "high_five":
					_emote_sound(ev, 3, "felt_pat", 3, -2.0 if near_self else -5.0, rng.randf_range(0.95, 1.05), at, near_self)
				else:
					_emote_sound(ev, 2, "felt_pat", 3, -9.0 if near_self else -12.0, rng.randf_range(0.72, 0.8), at, near_self)
			return
		"hands":
			# 手の形を掲げる: 袖が切る小さな音（下ろすときは鳴らさない）
			if ev.hands == "" or who == null:
				return
			_emote_sound(ev, 0, "swish", 2, -16.0, rng.randf_range(1.3, 1.5), who.global_position + Vector3.UP * 1.0, is_self)
			return
		"splat":
			_emote_sound(ev, 0, "snow_splat", 3, -6.0, rng.randf_range(0.9, 1.1), ev.point, false)
			return
	if who == null or not EMOTE_SOUNDS.has(ev.kind):
		return
	var voice: bool = ev.kind in ["wa", "un", "nn", "huh", "oi", "hit", "breath"]
	for s in EMOTE_SOUNDS[ev.kind]:
		var p: float = s[4] * (rng.randf_range(0.98, 1.02) if voice else rng.randf_range(0.95, 1.05))
		# 声（voice_*）はその人形の 1 つ。ほかの音は毎回選ぶ
		var fixed: String = doll_kind if (s[1] as String).begins_with("voice_") else ""
		_emote_sound(ev, s[0], s[1], s[2], s[3], p, who.global_position + Vector3.UP * 1.0, is_self, "Voice" if voice else "", fixed)


## 出来事のコマ + k に、音を 1 つ鳴らす。自分の音は耳元（Self／Voice）、人の音はその場所から
func _note(name_: String, near: bool, at: Vector3) -> void:
	if log_on:
		played.append({"t": Engine.get_physics_frames() / float(Engine.physics_ticks_per_second), "name": name_, "near": near,
				"dist": 0.0 if near else _listener().distance_to(at), "wind": _wind_rush.volume_db if _wind_rush else -80.0})


func _emote_sound(ev: Dictionary, k: int, name_: String, count: int, db: float, pitch: float, at: Vector3, near: bool, bus := "", fixed := "") -> void:
	var tps := Engine.physics_ticks_per_second
	var tick := (int(ev.frame) + k) * tps / Doll.FPS
	var wait := maxf(0.0, float(tick - Engine.get_physics_frames()) / tps)
	var s := _wav("%s_%s" % [name_, fixed]) if fixed != "" else _pick(name_, count)
	if s == null and fixed != "":
		s = _wav("%s_kasa" % name_)   # 声をまだ作っていない人形は、あなたの声で
	if s == null:
		return
	if wait > 0.0:
		await get_tree().create_timer(wait, true, true).timeout
	_note(name_, near, at)
	if near:
		var p := AudioStreamPlayer.new()
		p.bus = bus if bus != "" else "Self"
		add_child(p)
		_shot2(p, s, db - 4.0, pitch)
		p.finished.connect(p.queue_free)
	else:
		# 呼ぶ声は遠くまで届く（ほかの音は 45 m で消える）
		var far := name_ == "voice_oi"
		var p := _p3(world, bus if bus != "" else "Outdoor", db, 14.0 if far else 5.0, 120.0 if far else 45.0)
		p.global_position = at
		_shot(p, s, db, pitch)
		p.finished.connect(p.queue_free)
