extends Node3D
## 焚き火（2026-11-01 代表「焚き火セットを売って欲しい。焚き火をして体を乾かせるようにしてほしい」）。
## 旅のおじいさんの売り台で「焚き火セット」（持ち物 {kind: "campfire"}）を買い、手に持って外の雪の上で F を押すと、
## 前の雪に組んで火がつく（craft.gd の fire_lay。player.gd の fire_spot が組める所を決める）。1 つのセットで 1 回。
## 形は手芸の世界のもの:
##   フェルトの石の輪（灰・茶・青みの羊毛玉をつぶした形）、灰色のフェルトの敷物、
##   巻いたフェルトのロールの薪を櫓に組んだもの（下に横たえた 2 本）。木口に渦の糸（暖炉の薪と同じ。2026-11-02 代表が案の左から 1 つ目を選んだ）、
##   炎と灯りは火の手本の部品（flame.gd。切ったフェルトの炎。2026-11-02 に薄葉紙からそろえた）。熾火は小さな羊毛玉。
##   煙は灰色のチュールの帯（tulle_smoke.gd）
## 動きは人形と同じ 12 コマ／秒（コマの間は止める）:
##   組む   石が 1 コマに 1 つずつ置かれ、薪が上から落ちてくる（LAY_FRAMES）
##   火がつく 炎が 2 コマごとに大きくなる（LIGHT_FRAMES）
##   燃える 炎と灯りの揺れは flame.gd。薪はだんだん焦げる
##   弱る   燃え尽きる前の FADE 秒で、炎と灯りが小さくなる
##   消える 燃え尽きる（LIFE 秒）か、組んだ人が F で雪をかける（fire_out）。炎が消えて、雪のしぶきが上がる。薪は炭の色に
##   片づく 消えて AFTER 秒たつと、石と薪が 1 コマずつ縮んで消える
## 燃えているあいだ、仲間分け "fires" に入る: damp.gd が近くの人を乾かし（dry_k 倍。暖炉と乾燥機の間）、temperature.gd が外の気温を上げる。
## 消えるまでの時間は画面ごとに数える（通信で届いた時から。あとから来た人には、ホストが燃えた秒を渡す: craft.gd の snapshot）

const Look := preload("res://look.gd")
const Audio := preload("res://audio.gd")
const Flame := preload("res://flame.gd")
const TulleSmoke := preload("res://tulle_smoke.gd")

## 品目: 持ち物としての焚き火セット（名前・値段・絵）。売り場はここを読む。
## 2026-11-01 代表「そういう道具類を売ってくれる山男？山師？みたいなキャラが欲しい」: 本当の売り場は山の道具を売る山男。
## 山男の店ができるまでは、仮に売り子のおじさんの売り台に並べている（craft_ui.gd の _goods）
const ITEM := {"kind": "campfire"}
const NAME := "焚き火セット"
const PRICE := 15            # ボタン（木の何個分）。1 つで 1 回燃える（LIFE、3 分）。布 10 と米袋の型紙 20 のあいだ

const LIFE := 180.0          # 燃えている秒（組んでから）
const FADE := 30.0           # 燃え尽きる前に弱っていく秒
const AFTER := 8.0           # 消えてから片づくまでの秒
const LAY_FRAMES := 14       # 組む動きのコマ
const LIGHT_FRAMES := 8      # 火がつく動きのコマ
const DRY_K := 2.5           # 乾く速さの倍率（暖炉 1。すぐそばなら 100 から −40 まで 11 秒ほど。暖炉 27 秒、乾燥機 4 秒）
const WARM := 16.0           # すぐそばで、外の気温をこれだけ上げる (°C。temperature.gd)
const RING_R := 0.36         # 石の輪の半径 (m)
const STONES := 9
const LIGHT_RANGE := 7.5
const STONE_COLORS := [Color(0.40, 0.38, 0.37), Color(0.34, 0.29, 0.26), Color(0.46, 0.44, 0.41), Color(0.30, 0.33, 0.37)]
## 薪のフェルトの色（props の felt_tan・felt_brown）。巻いた色と、木口の渦の糸の色を入れ替えて交互に
const FELT_TAN := Color(0.66, 0.46, 0.28)
const FELT_BROWN := Color(0.42, 0.27, 0.17)
const HEMP := Color(0.80, 0.68, 0.48)   # 束ねる麻ひも
const PUFF := 2.0            # 消えた直後、チュールの煙が大きく上る秒
var fire_id := -1            # craft.gd の番号
var owner_id := -1           # 組んだ人の番号（その人だけが F で消せる）
var age := 0.0               # 組んでからの秒
var dry_k := DRY_K           # damp.gd が読む
var _out_age := -1.0         # 消えた時の age（燃えていれば -1）
var _k := -1                 # いまのコマ
var _parts: Array = []       # [節, 出るコマ, 落ちてくるか]
var _logs: Array[StandardMaterial3D] = []
var _log_base: Array[Color] = []
var _flame: Node3D          # 炎と灯り（flame.gd）
var _smoke: Node3D          # チュールの煙（tulle_smoke.gd）
var _embers: Array[MeshInstance3D] = []
var _ember_mat: StandardMaterial3D
var _bed: AudioStreamPlayer3D
var _crack: AudioStreamPlayer3D
var _crack_t := 0.5
var _audio: Node
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = fire_id * 7919 + 13
	_build()
	_audio = get_tree().root.find_child("Audio", true, false)
	if _audio and _audio.has_method("campfire"):
		var ps: Array = _audio.campfire(self)
		_bed = ps[0]
		_crack = ps[1]
	_step(int(age * 12.0))


## 燃えているか（組んでいるあいだも含む。消えていなければ true）
func lit() -> bool:
	return _out_age < 0.0 and age < LIFE


## 火の強さ（0 〜 1）: 組んでいるあいだ 0、火がつくと 1、燃え尽きる前に弱る
func level() -> float:
	if not lit():
		return 0.0
	var k := age * 12.0
	if k < LAY_FRAMES:
		return 0.0
	var on := clampf(floorf((k - LAY_FRAMES) / 2.0) * 2.0 / LIGHT_FRAMES, 0.15, 1.0)
	return on * lerpf(1.0, 0.3, clampf((age - (LIFE - FADE)) / FADE, 0.0, 1.0))


## 雪をかけて消す（組んだ人の F。craft.gd の fire_out）
func put_out() -> void:
	if not lit():
		return
	_out_age = age
	var parent := get_parent()
	if parent:
		for i in 3:
			var a := TAU * i / 3.0
			preload("res://snowball.gd").splat_at(parent, to_global(Vector3(cos(a), 0.4, sin(a)) * 0.22), Vector3.UP, true)


## あとから来た人へ渡す形（craft.gd の snapshot）
func snap() -> Dictionary:
	return {"id": fire_id, "owner": owner_id, "at": global_position, "yaw": rotation.y, "up": global_basis.y, "age": age,
		"out": _out_age}


func _process(dt: float) -> void:
	age += dt
	if _out_age < 0.0 and age >= LIFE:
		_out_age = LIFE   # 燃え尽きた
	if level() > 0.0 and not is_in_group("fires"):
		add_to_group("fires")   # 火がついてから暖かい（組んでいるあいだはまだ）
	elif not lit() and is_in_group("fires"):
		remove_from_group("fires")
	var k := int(age * 12.0)
	if k != _k:
		_step(k)
	_sound(dt)
	if _out_age >= 0.0 and age > _out_age + AFTER + 1.0:
		queue_free()


# ---------------------------------------------------------------- 形

func _build() -> void:
	# 灰色のフェルトの敷物（雪の上の焦げた所）
	var bed := _mesh(_cyl(0.30, 0.30, 0.015), Look.felt(Color(0.30, 0.28, 0.27), 2.0), Vector3(0, 0.008, 0))
	_parts.append([bed, 0, false])
	# 石の輪: つぶした羊毛玉
	for i in STONES:
		var a := TAU * i / STONES + _rng.randf_range(-0.12, 0.12)
		var r := _rng.randf_range(0.075, 0.095)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		var st := _mesh(sm, Look.felt(STONE_COLORS[i % STONE_COLORS.size()], 3.0), Vector3(cos(a), 0, sin(a)) * RING_R + Vector3.UP * r * 0.55)
		st.scale = Vector3(1.15, 0.7, 1.0)
		st.rotation.y = -a
		_parts.append([st, i, false])
	# 横たえた薪 2 本（十字）
	for i in 2:
		var lg := _log(0.034, 0.5, i)
		lg.position = Vector3(0, 0.05 + i * 0.05, 0)
		lg.rotation = Vector3(PI / 2.0, i * PI / 2.0 + 0.3, 0)
		_parts.append([lg, 6 + i, true])
	# 櫓に組んだ薪 5 本: 下を輪の内に、上を真ん中に寄せる
	for i in 5:
		var a := TAU * i / 5.0 + 0.2
		var foot := Vector3(cos(a), 0, sin(a)) * 0.24 + Vector3.UP * 0.03
		var top := Vector3(cos(a), 0, sin(a)) * 0.04 + Vector3.UP * 0.4
		var lg := _log(0.03, foot.distance_to(top) + 0.06, i + 2)
		lg.position = (foot + top) / 2.0
		lg.basis = Basis(Quaternion(Vector3.UP, (top - foot).normalized()))
		_parts.append([lg, 8 + i, true])
	# 熾火: 小さな羊毛玉が薪の足もとで光る
	_ember_mat = Look.felt(Color(0.95, 0.40, 0.12), 4.0)
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color(1.0, 0.42, 0.12)
	_ember_mat.emission_energy_multiplier = 1.4
	for i in 5:
		var a := TAU * i / 5.0 + 0.7
		var sm := SphereMesh.new()
		sm.radius = 0.03
		sm.height = 0.05
		sm.radial_segments = 8
		sm.rings = 4
		var e := _mesh(sm, _ember_mat, Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.06, 0.16) + Vector3.UP * 0.035)
		_embers.append(e)
	_flame = Flame.new()
	_flame.position = Vector3(0, 0.06, 0)
	_flame.seed = fire_id
	_flame.light_range = LIGHT_RANGE
	_flame.level = 0.0
	add_child(_flame)
	_smoke = TulleSmoke.new()
	_smoke.position = Vector3(0, 0.38, 0)
	_smoke.level = 0.0
	add_child(_smoke)


## 巻いたフェルトのロールの薪（長さは y 向き）。焦げる色を変えられるよう、素材は薪ごと
func _log(r: float, length: float, i: int) -> Node3D:
	var m := Look.felt(FELT_TAN if i % 2 else FELT_BROWN, 2.0)
	_logs.append(m)
	_log_base.append(m.albedo_color)
	var lg := felt_log(r, length, m, Look.felt(FELT_BROWN if i % 2 else FELT_TAN, 4.0))
	add_child(lg)
	return lg


## 巻いたフェルトのロール 1 本（長さは y 向き）: 筒と、両端の木口に渦の糸（暖炉の薪と同じ。props/build_hearth.py の log）
static func felt_log(r: float, length: float, body_mat: Material, swirl_mat: Material) -> Node3D:
	var lg := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 14
	cm.rings = 1
	body.mesh = cm
	body.material_override = body_mat
	lg.add_child(body)
	for sg in [1.0, -1.0]:
		var sw := MeshInstance3D.new()
		sw.mesh = _swirl(r)
		sw.material_override = swirl_mat
		sw.position.y = sg * (length / 2.0 + 0.0015)
		if sg < 0.0:
			sw.rotation.x = PI
		lg.add_child(sw)
	return lg


static var _swirls := {}

## 木口の渦: 平たい糸を 3 巻き（真ん中から外へ）。上（+Y）向きの面
static func _swirl(r: float) -> ArrayMesh:
	var key := snappedf(r, 0.001)
	if _swirls.has(key):
		return _swirls[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	st.set_normal(Vector3.UP)
	var w := r * 0.07
	for k in 73:
		var t := k / 72.0 * 3.0
		var rr := r * (0.1 + 0.78 * t / 3.0)
		var d := Vector3(cos(t * TAU), 0, sin(t * TAU))
		st.add_vertex(d * (rr - w))
		st.add_vertex(d * (rr + w))
	_swirls[key] = st.commit()
	return _swirls[key]


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 12
	cm.rings = 1
	return cm


func _mesh(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


# ---------------------------------------------------------------- 動き（12 コマ／秒）

func _step(k: int) -> void:
	_k = k
	var gone := 1.0   # 片づく: 1 → 0（1 コマずつ縮む）
	if _out_age >= 0.0:
		gone = clampf(1.0 - (age - _out_age - AFTER) * 12.0 / 6.0, 0.0, 1.0)
	# 組む: 石と薪が 1 コマずつ。置かれたコマは少し大きく（ぽんと置く）、薪は上から落ちてくる
	for p in _parts:
		var n: Node3D = p[0]
		var f: int = p[1]
		if not n.has_meta("rest"):
			n.set_meta("rest", n.transform)
		var rest: Transform3D = n.get_meta("rest")
		n.visible = k >= f and gone > 0.0
		var t := rest
		if k == f:
			t = Transform3D(rest.basis.scaled(Vector3.ONE * 1.15), rest.origin + (Vector3.UP * 0.18 if p[2] else Vector3.ZERO))
		elif k == f + 1 and p[2]:
			t = Transform3D(rest.basis, rest.origin + Vector3.UP * 0.05)
		if gone < 1.0:
			t = Transform3D(rest.basis.scaled(Vector3.ONE * maxf(gone, 0.01)), rest.origin * Vector3(gone, 1.0, gone))
		n.transform = t
	var lv := level()
	# 薪がだんだん焦げる。消えたら炭の色
	var char_k := clampf(age / LIFE, 0.0, 1.0) * 0.55 + (0.35 if _out_age >= 0.0 else 0.0)
	for i in _logs.size():
		_logs[i].albedo_color = _log_base[i].lerp(Color(0.12, 0.10, 0.09), char_k)
	_flame.level = lv if gone > 0.0 else 0.0
	# 煙: 燃えているあいだは強さのぶん。消えた直後の PUFF 秒は大きく（雪をかけた湯気）、そのあと消える
	var puff := _out_age >= 0.0 and age - _out_age < PUFF
	_smoke.level = (lv if lv > 0.0 else (1.35 * (1.0 - (age - _out_age) / PUFF) if puff else 0.0)) * gone
	# 熾火: コマごとにいくつかが明るく、いくつかが暗く。消えたら灰色
	for i in _embers.size():
		_embers[i].visible = k >= LAY_FRAMES and gone > 0.0
		_embers[i].scale = Vector3.ONE * (1.0 if _hash(k * 11 + i) > 0.35 else 0.7)
	_ember_mat.emission_energy_multiplier = 1.4 * lv if lv > 0.0 else 0.0
	_ember_mat.albedo_color = Color(0.95, 0.40, 0.12) if lv > 0.0 else Color(0.25, 0.23, 0.22)


## 0 〜 1 の決まった乱数（コマの番号から。どの画面でも同じ揺れ方）
func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + fire_id * 78.233) * 43758.5453, 1.0)


func _sound(dt: float) -> void:
	if _bed:
		_bed.volume_db = lerpf(-40.0, -9.0, clampf(level() * 1.4, 0.0, 1.0))
		if level() <= 0.0 and _bed.playing and _out_age >= 0.0:
			_bed.stop()
	if _crack == null or level() <= 0.0 or _audio == null:
		return
	_crack_t -= dt
	if _crack_t <= 0.0:
		_crack_t = _rng.randf_range(0.4, 2.2)
		_audio.fire_crack(_crack, level())


# ---------------------------------------------------------------- 持ち物の形と絵

## 品目の絵（山男の棚・持ち物の列。64 × 64 の箱、中心が原点）: 麻ひもで縛った巻いたフェルトの薪 3 本（木口の渦を見せて積む）と、
## くしゃっとした薄葉紙の焚きつけ。描く前に hud_icons.gd の _o・_s が入っていること（craft_icons.gd の item が入れる）
static func icon(ci: CanvasItem, c: Vector2, sc: float, a: float) -> void:
	var Icons := preload("res://hud_icons.gd")
	Icons.patch(ci, Icons.xf(Icons.rr(-26, -10, 52, 32, 6), 0.0, c + Vector2(0, 4) * sc, sc), FELT_BROWN.darkened(0.2), a, false)
	var ends := [[Vector2(-12, 10), FELT_TAN, FELT_BROWN], [Vector2(12, 10), FELT_BROWN, FELT_TAN], [Vector2(0, -8), FELT_TAN, FELT_BROWN]]
	for e in ends:
		var at: Vector2 = c + (e[0] as Vector2) * sc
		Icons.patch(ci, Icons.circ(at, 11.0 * sc, 18), e[1], a, true, (e[1] as Color).lightened(0.35))
		var sp := PackedVector2Array()   # 木口の渦の糸
		for k in 25:
			var t := k / 24.0 * 2.5
			sp.append(at + Vector2(cos(t * TAU), sin(t * TAU)) * (1.0 + 8.0 * t / 2.5) * sc)
		Icons.thread(ci, sp, e[2], 1.6, a)
	Icons.thread(ci, Icons.xf(PackedVector2Array([Vector2(-26, 2), Vector2(-8, -2), Vector2(8, -2), Vector2(26, 2)]), 0.0, c, sc), HEMP.lightened(0.15), 3.2, a)
	# 薄葉紙の焚きつけ: 赤と橙の紙をくしゃっと
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(10, -14), Vector2(14, -26), Vector2(19, -18), Vector2(24, -28), Vector2(27, -14), Vector2(22, -8), Vector2(13, -8)]), 0.0, c, sc),
			Color(0.86, 0.24, 0.13), a, false)
	Icons.patch(ci, Icons.xf(PackedVector2Array([Vector2(14, -10), Vector2(17, -20), Vector2(20, -14), Vector2(23, -20), Vector2(24, -10)]), 0.0, c, sc),
			Color(0.96, 0.52, 0.15), a, false)


## 手に持った焚き火セット: 巻いたフェルトの薪 3 本を麻ひもで縛った束に、くしゃっとした薄葉紙の焚きつけを挟んだもの（player.gd の held_shape）
static func kit_shape() -> Node3D:
	var root := Node3D.new()
	for i in 3:
		var lg := felt_log(0.024, 0.2, Look.felt(FELT_TAN if i != 1 else FELT_BROWN, 4.0), Look.felt(FELT_BROWN if i != 1 else FELT_TAN, 6.0))
		lg.rotation.z = PI / 2.0
		lg.position = [Vector3(0, 0, -0.025), Vector3(0, 0, 0.025), Vector3(0, 0.042, 0)][i]
		root.add_child(lg)
	var yarn := Look.knit(HEMP, 14.0)   # 麻ひもで縛る（赤い輪だと、赤い薪の束がダイナマイトに見える）
	for x in [-0.06, 0.06]:
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.054
		tm.outer_radius = 0.06
		band.mesh = tm
		band.material_override = yarn
		band.rotation.z = PI / 2.0
		band.position = Vector3(x, 0.014, 0)
		band.scale = Vector3(1.0, 1.0, 0.95)
		root.add_child(band)
	for k in 2:   # くしゃっとした薄葉紙（赤と橙）
		var tinder := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.026
		sm.height = 0.05
		sm.radial_segments = 6
		sm.rings = 3
		tinder.mesh = sm
		tinder.material_override = Look.paper([Color(0.86, 0.24, 0.13), Color(0.96, 0.52, 0.15)][k])
		tinder.position = Vector3(-0.015 + k * 0.03, 0.075 - k * 0.006, 0.004 * k)
		tinder.rotation = Vector3(0.6 * k, 0.9, 0.3)
		tinder.scale = Vector3(1.2, 0.85, 1.0)
		root.add_child(tinder)
	root.rotation = Vector3(0.3, 0.5, 0)
	return root


## その位置が外か（ロッジの中・風除室では組めない）
static func outside(tree: SceneTree, at: Vector3) -> bool:
	var temp := tree.root.get_node_or_null("Temperature")
	var lodge: Node3D = temp._find_lodge() if temp else null
	return lodge == null or Audio.zone_at(lodge, at + Vector3.UP) == 0
