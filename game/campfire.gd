extends Node3D
## 焚き火（2026-11-01 代表「焚き火セットを売って欲しい。焚き火をして体を乾かせるようにしてほしい」）。
## 旅のおじいさんの売り台で「焚き火セット」（持ち物 {kind: "campfire"}）を買い、手に持って外の雪の上で F を押すと、
## 前の雪に組んで火がつく（craft.gd の fire_lay。player.gd の fire_spot が組める所を決める）。1 つのセットで 1 回。
## 形は手芸の世界のもの:
##   フェルトの石の輪（灰・茶・青みの羊毛玉をつぶした形）、灰色のフェルトの敷物、
##   毛糸を巻いた木の薪を櫓に組んだもの（下に横たえた薪 2 本）、
##   炎は布（赤・橙のフェルト）とクラフト紙（黄）を切って重ね、2 枚を十字に差し込んだもの。熾火は小さな羊毛玉
## 動きは人形と同じ 12 コマ／秒（コマの間は止める）:
##   組む   石が 1 コマに 1 つずつ置かれ、薪が上から落ちてくる（LAY_FRAMES）
##   火がつく 炎が 2 コマごとに大きくなる（LIGHT_FRAMES）
##   燃える 炎は切り紙を 2 コマごとに差し替える（4 つの切り方。置き換えのコマ撮り）。灯りも 1 コマごとに揺らぐ。薪はだんだん焦げる
##   弱る   燃え尽きる前の FADE 秒で、炎と灯りが小さくなる
##   消える 燃え尽きる（LIFE 秒）か、組んだ人が F で雪をかける（fire_out）。炎が消えて、雪のしぶきが上がる。薪は炭の色に
##   片づく 消えて AFTER 秒たつと、石と薪が 1 コマずつ縮んで消える
## 燃えているあいだ、仲間分け "fires" に入る: damp.gd が近くの人を乾かし（dry_k 倍。暖炉と乾燥機の間）、temperature.gd が外の気温を上げる。
## 消えるまでの時間は画面ごとに数える（通信で届いた時から。あとから来た人には、ホストが燃えた秒を渡す: craft.gd の snapshot）

const Look := preload("res://look.gd")
const Audio := preload("res://audio.gd")

const LIFE := 180.0          # 燃えている秒（組んでから）
const FADE := 30.0           # 燃え尽きる前に弱っていく秒
const AFTER := 8.0           # 消えてから片づくまでの秒
const LAY_FRAMES := 14       # 組む動きのコマ
const LIGHT_FRAMES := 8      # 火がつく動きのコマ
const DRY_K := 2.5           # 乾く速さの倍率（暖炉 1。すぐそばなら 100 から −40 まで 11 秒ほど。暖炉 27 秒、乾燥機 4 秒）
const WARM := 16.0           # すぐそばで、外の気温をこれだけ上げる (°C。temperature.gd)
const RING_R := 0.36         # 石の輪の半径 (m)
const STONES := 9
const LIGHT_COLOR := Color(1.0, 0.60, 0.30)
const LIGHT_ENERGY := 2.6
const LIGHT_RANGE := 7.5
const STONE_COLORS := [Color(0.40, 0.38, 0.37), Color(0.34, 0.29, 0.26), Color(0.46, 0.44, 0.41), Color(0.30, 0.33, 0.37)]
const YARN_COLORS := [Color(0.80, 0.24, 0.20), Color(0.88, 0.66, 0.20), Color(0.24, 0.32, 0.55), Color(0.92, 0.88, 0.78), Color(0.25, 0.52, 0.34)]
## 炎の 3 枚: [色, 大きさ, 光る強さ, 紙か]（外から赤いフェルト・橙のフェルト・黄のクラフト紙）
const FLAME_LAYERS := [[Color(0.84, 0.22, 0.12), 1.0, 0.45, false], [Color(0.95, 0.50, 0.14), 0.7, 0.6, false], [Color(1.0, 0.82, 0.36), 0.42, 0.8, true]]
const FLAME_W := 0.25        # 炎の幅の半分 (m)
const FLAME_H := 0.9        # 炎の高さ (m)
const CUTS := 4              # 炎の切り方の数

var fire_id := -1            # craft.gd の番号
var owner_id := -1           # 組んだ人の番号（その人だけが F で消せる）
var age := 0.0               # 組んでからの秒
var dry_k := DRY_K           # damp.gd が読む
var _out_age := -1.0         # 消えた時の age（燃えていれば -1）
var _k := -1                 # いまのコマ
var _parts: Array = []       # [節, 出るコマ, 落ちてくるか]
var _logs: Array[StandardMaterial3D] = []
var _log_base: Array[Color] = []
var _planes: Array[Node3D] = []   # 炎の板（十字に 2 枚）。子は層ごとの MeshInstance3D
var _cuts: Array = []        # 層ごとの、切り方ごとの ArrayMesh
var _embers: Array[MeshInstance3D] = []
var _ember_mat: StandardMaterial3D
var _light: OmniLight3D
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
	# 炎: 切り方ごとの形を作っておき、十字の 2 枚の層に差し替える
	for li in FLAME_LAYERS.size():
		var list := []
		for c in CUTS:
			list.append(_flame_mesh(c, li))
		_cuts.append(list)
	for pi in 2:
		var plane := Node3D.new()
		plane.position = Vector3(0, 0.06, 0)
		add_child(plane)
		# 斜面に組んでも、炎はまっすぐ上へ（焚き火の傾きを打ち消す）
		var yaw := global_basis.get_euler().y + pi * PI / 2.0 + 0.4
		plane.set_meta("upright", global_basis.orthonormalized().inverse() * Basis(Vector3.UP, yaw))
		for li in FLAME_LAYERS.size():
			var col: Color = FLAME_LAYERS[li][0]
			var m: StandardMaterial3D = Look.paper(col) if FLAME_LAYERS[li][3] else Look.felt(col, 3.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.rim_enabled = false
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = FLAME_LAYERS[li][2]
			for side in ([0.0] if li == 0 else [-1.0, 1.0]):   # 外の層は 1 枚、内の層は表と裏に 1 枚ずつ（どちらから見ても重なって見える）
				var mi := MeshInstance3D.new()
				mi.material_override = m
				mi.position.z = side * 0.007 * li
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("layer", li)
				plane.add_child(mi)
		_planes.append(plane)
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.3
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.55, 0)
	add_child(_light)


## 毛糸を 2 か所に巻いた木の薪（長さは y 向き）
func _log(r: float, length: float, i: int) -> Node3D:
	var lg := Node3D.new()
	add_child(lg)
	var m := Look.wood(Color(0.52, 0.34, 0.20).lerp(Color(0.62, 0.44, 0.28), _rng.randf()))
	_logs.append(m)
	_log_base.append(m.albedo_color)
	var body := MeshInstance3D.new()
	body.mesh = _cyl(r, r * 1.08, length)
	body.material_override = m
	lg.add_child(body)
	var cut := MeshInstance3D.new()   # 切り口の明るい木
	cut.mesh = _cyl(r * 0.9, r * 0.9, 0.004)
	cut.material_override = Look.wood(Color(0.80, 0.66, 0.46))
	cut.position.y = length / 2.0
	lg.add_child(cut)
	var yarn := Look.knit(YARN_COLORS[i % YARN_COLORS.size()], 14.0)
	for y in [-0.22, 0.18]:
		var band := MeshInstance3D.new()
		band.mesh = _cyl(r * 1.25, r * 1.25, 0.035)
		band.material_override = yarn
		band.position.y = length * y
		lg.add_child(band)
	return lg


## 炎の切り紙 1 枚の形: 下が丸く、上に舌が 1〜3 本。はさみで切ったように縁を少しがたつかせる
func _flame_mesh(cut: int, layer: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + cut * 37 + layer * 11
	var s: float = FLAME_LAYERS[layer][1]
	var w := FLAME_W * s
	var h := FLAME_H * s * rng.randf_range(0.9, 1.08)
	var tips: int = [2, 2, 1][layer] + (1 if cut % 2 == 1 and layer == 0 else 0)
	var pts: Array[Vector2] = []
	# 下の丸み（右から左へ）
	for j in 7:
		var a := PI * (0.05 + 0.9 * j / 6.0)
		pts.append(Vector2(cos(a) * w, -sin(a) * w * 0.35))
	# 左の縁から舌を 1 本ずつ（いちばん高い舌は真ん中あたり）
	var lean := rng.randf_range(-0.25, 0.25) * w
	for t in tips:
		var x0 := lerpf(-w, w, float(t) / tips)
		var x1 := lerpf(-w, w, float(t + 1) / tips)
		var mid := (x0 + x1) / 2.0
		var centre := 1.0 - absf(mid) / w
		var th := h * lerpf(0.55, 1.0, centre) * rng.randf_range(0.85, 1.1)
		var base_y := h * lerpf(0.18, 0.38, centre) if t > 0 else h * 0.12
		pts.append(Vector2(x0 * 0.92, base_y))
		pts.append(Vector2(lerpf(x0, mid, 0.25) + rng.randf_range(-0.01, 0.01), th * 0.55))   # 舌はふっくら（根元から半ばまで幅を保つ）
		pts.append(Vector2(lerpf(x0, mid, 0.6) + lean * centre * 0.6, th * 0.85))
		pts.append(Vector2(mid + lean * centre, th))
		pts.append(Vector2(lerpf(x1, mid, 0.55) + lean * centre * 0.6, th * 0.8))
		pts.append(Vector2(lerpf(x1, mid, 0.2) + rng.randf_range(-0.01, 0.01), th * 0.5))
	pts.append(Vector2(w * 0.95, h * 0.12))
	# はさみのがたつき: 辺の途中に、少しずれた点を足す
	var cutpts := PackedVector2Array()
	for j in pts.size():
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[(j + 1) % pts.size()]
		cutpts.append(a)
		var n := (b - a).orthogonal().normalized()
		cutpts.append((a + b) / 2.0 + n * rng.randf_range(-0.006, 0.006))
	if Geometry2D.is_polygon_clockwise(cutpts):
		cutpts.reverse()
	var idx := Geometry2D.triangulate_polygon(cutpts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in idx:
		var p: Vector2 = cutpts[i]
		st.set_uv(Vector2(p.x, -p.y) * 2.0)
		st.add_vertex(Vector3(p.x, p.y, 0))
	return st.commit()


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
	# 炎: 2 コマごとに切り方を替える（同じ切り方は続けない）。大きさは火の強さ
	var step := k / 2
	for pi in _planes.size():
		var plane: Node3D = _planes[pi]
		var on := lv > 0.0 and gone > 0.0
		plane.visible = on
		if not on:
			continue
		var cut := int(_hash(step * 3 + pi * 17) * CUTS)
		if cut == int(_hash((step - 1) * 3 + pi * 17) * CUTS):
			cut = (cut + 1) % CUTS
		var jit := 1.0 + (_hash(step * 5 + pi) - 0.5) * 0.12
		var up_b: Basis = plane.get_meta("upright")
		plane.basis = (up_b * Basis(Vector3.BACK, (_hash(step * 7 + pi * 3) - 0.5) * 0.12)).scaled_local(Vector3(lv * (2.0 - jit), lv * jit, lv))
		for c in plane.get_children():
			var mi := c as MeshInstance3D
			var li: int = mi.get_meta("layer")
			var lc := cut if li == 0 else (cut + li + int(_hash(step + li) * 2.0)) % CUTS   # 内の層は外とずらす（いっしょに動かない）
			mi.mesh = _cuts[li][lc]
	# 熾火: コマごとにいくつかが明るく、いくつかが暗く。消えたら灰色
	for i in _embers.size():
		_embers[i].visible = k >= LAY_FRAMES and gone > 0.0
		_embers[i].scale = Vector3.ONE * (1.0 if _hash(k * 11 + i) > 0.35 else 0.7)
	_ember_mat.emission_energy_multiplier = 1.4 * lv if lv > 0.0 else 0.0
	_ember_mat.albedo_color = Color(0.95, 0.40, 0.12) if lv > 0.0 else Color(0.25, 0.23, 0.22)
	# 灯り: コマごとに揺らぐ
	var flick := 0.82 + 0.18 * _hash(k * 13 + 5)
	_light.light_energy = LIGHT_ENERGY * lv * flick
	_light.position = Vector3((_hash(k * 3) - 0.5) * 0.06, 0.55 + (_hash(k * 5) - 0.5) * 0.05, (_hash(k * 9) - 0.5) * 0.06)
	_light.visible = lv > 0.0


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


# ---------------------------------------------------------------- 持ち物の形

## 手に持った焚き火セット: 毛糸で縛った薪 3 本の束に、丸めたクラフト紙の焚きつけを挟んだもの（player.gd の held_shape）
static func kit_shape() -> Node3D:
	var root := Node3D.new()
	var wood := Look.wood(Color(0.56, 0.37, 0.22))
	for i in 3:
		var lg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.022
		cm.bottom_radius = 0.024
		cm.height = 0.2
		cm.radial_segments = 10
		lg.mesh = cm
		lg.material_override = wood
		lg.rotation.z = PI / 2.0
		lg.position = [Vector3(0, 0, -0.024), Vector3(0, 0, 0.024), Vector3(0, 0.04, 0)][i]
		root.add_child(lg)
	var yarn := Look.knit(Color(0.80, 0.24, 0.20), 14.0)
	for x in [-0.06, 0.06]:
		var band := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.052
		tm.outer_radius = 0.062
		band.mesh = tm
		band.material_override = yarn
		band.rotation.z = PI / 2.0
		band.position = Vector3(x, 0.014, 0)
		band.scale = Vector3(1.0, 1.0, 0.95)
		root.add_child(band)
	var tinder := MeshInstance3D.new()   # 丸めたクラフト紙
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.05
	tinder.mesh = sm
	tinder.material_override = Look.paper(Color(0.84, 0.72, 0.52))
	tinder.position = Vector3(0.0, 0.07, 0.0)
	tinder.scale = Vector3(1.3, 0.8, 1.0)
	root.add_child(tinder)
	root.rotation = Vector3(0.3, 0.5, 0)
	return root


## その位置が外か（ロッジの中・風除室では組めない）
static func outside(tree: SceneTree, at: Vector3) -> bool:
	var temp := tree.root.get_node_or_null("Temperature")
	var lodge: Node3D = temp._find_lodge() if temp else null
	return lodge == null or Audio.zone_at(lodge, at + Vector3.UP) == 0
