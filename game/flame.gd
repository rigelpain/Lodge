extends Node3D
## 火の手本（2026-11-01 代表「火の表現は焚き火にそろえてほしい」）。焚き火（campfire.gd）の炎と灯りを、ほかの所でも使える部品にしたもの。
## キャンドル・松明・ガス火なども、これを置いて大きさと明るさを変えて使う。
##   形: 赤・橙のフェルトと黄のクラフト紙を、はさみで切ったような舌の形にして 3 枚重ね、2 枚を十字に差し込む（どこから見ても炎）
##   動き: 人形と同じ 12 コマ／秒。4 つの切り方を 2 コマごとに差し替える（置き換えのコマ撮り）。少し傾き、背が伸び縮みする
##   灯り: 電球色より赤みの点の灯り（影なし）。1 コマごとに揺らぐ
## 使い方:
##   var f := preload("res://flame.gd").new()
##   f.size = 0.15          # 炎の高さの倍率（1 で焚き火の 0.9 m。キャンドルなら 0.1〜0.15）
##   f.brightness = 0.3     # 灯りの強さの倍率（1 で焚き火）。0 なら灯りを作らない
##   f.light_range = 3.0    # 灯りの届く距離 (m)
##   f.seed = 7             # 揺れ方をずらす（並べた火が同じに揺れないように）
##   add_child(f)           # 節の原点が炎の根元。炎は節の上（+Y）へ伸びる。傾いた物に付けても、炎はまっすぐ上
##   f.level = 0.5          # 強さ 0〜1（火がつく・弱る・消えるは持ち主が入れる。0 で炎も灯りも消える）
## 2026-11-01 時点の形は、代表に案（design/campfire/proposal-flames.png）を見てもらっている途中。決まったら、ここだけを替えれば使う所すべてに効く

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

## 炎の 3 枚: [色, 大きさ, 光る強さ, 紙か]（外から赤いフェルト・橙のフェルト・黄のクラフト紙）
const LAYERS := [[Color(0.84, 0.22, 0.12), 1.0, 0.45, false], [Color(0.95, 0.50, 0.14), 0.7, 0.6, false], [Color(1.0, 0.82, 0.36), 0.42, 0.8, true]]
const W := 0.25              # 大きさ 1 の炎の幅の半分 (m)
const H := 0.9               # 大きさ 1 の炎の高さ (m)
const CUTS := 4              # 切り方の数
const LIGHT_COLOR := Color(1.0, 0.60, 0.30)
const LIGHT_ENERGY := 2.6    # 明るさ 1 の灯りの強さ
const LIGHT_Y := 0.55        # 大きさ 1 のとき、灯りの芯の高さ (m)

@export var size := 1.0
@export var brightness := 1.0
@export var light_range := 7.5
@export var seed := 0
var level := 1.0             # 強さ（0〜1）

static var _meshes := {}     # [層, 切り方] → ArrayMesh（大きさ 1。どの火も同じ形を使い回す）
var _planes: Array[Node3D] = []
var _light: OmniLight3D
var _k := -1


func _ready() -> void:
	for pi in 2:
		var plane := Node3D.new()
		add_child(plane)
		plane.set_meta("yaw", pi * PI / 2.0 + 0.4 + seed * 0.7)
		for li in LAYERS.size():
			var col: Color = LAYERS[li][0]
			var m: StandardMaterial3D = Look.paper(col) if LAYERS[li][3] else Look.felt(col, 3.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.rim_enabled = false
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = LAYERS[li][2]
			for side in ([0.0] if li == 0 else [-1.0, 1.0]):   # 外の層は 1 枚、内の層は表と裏に 1 枚ずつ（どちらから見ても重なって見える）
				var mi := MeshInstance3D.new()
				mi.material_override = m
				mi.position.z = side * 0.007 * li
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("layer", li)
				plane.add_child(mi)
		_planes.append(plane)
	if brightness > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = LIGHT_COLOR
		_light.omni_range = light_range
		_light.omni_attenuation = 1.3
		_light.shadow_enabled = false
		add_child(_light)
	_step(Doll.frame_index())


func _process(_dt: float) -> void:
	var k := Doll.frame_index()
	if k != _k:
		_step(k)


## 1 コマ: 切り方を 2 コマごとに替え（同じ切り方は続けない）、大きさは強さで。灯りは 1 コマごとに揺らぐ
func _step(k: int) -> void:
	_k = k
	var on := level > 0.0 and is_visible_in_tree()
	var step := k / 2
	var up := global_basis.orthonormalized().inverse()   # 傾いた物に付けても、炎はまっすぐ上へ
	for pi in _planes.size():
		var plane := _planes[pi]
		plane.visible = on
		if not on:
			continue
		var cut := int(_hash(step * 3 + pi * 17) * CUTS)
		if cut == int(_hash((step - 1) * 3 + pi * 17) * CUTS):
			cut = (cut + 1) % CUTS
		var jit := 1.0 + (_hash(step * 5 + pi) - 0.5) * 0.12
		var s := size * level
		plane.basis = (up * Basis(Vector3.UP, plane.get_meta("yaw")) * Basis(Vector3.BACK, (_hash(step * 7 + pi * 3) - 0.5) * 0.12)) \
				.scaled_local(Vector3(s * (2.0 - jit), s * jit, s))
		for c in plane.get_children():
			var mi := c as MeshInstance3D
			var li: int = mi.get_meta("layer")
			var lc := cut if li == 0 else (cut + li + int(_hash(step + li) * 2.0)) % CUTS   # 内の層は外とずらす（いっしょに動かない）
			mi.mesh = mesh(li, lc)
	if _light:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY * brightness * level * (0.82 + 0.18 * _hash(k * 13 + 5))
		_light.position = up * Vector3((_hash(k * 3) - 0.5) * 0.06 * size, LIGHT_Y * size + (_hash(k * 5) - 0.5) * 0.05 * size, (_hash(k * 9) - 0.5) * 0.06 * size)


## 0 〜 1 の決まった乱数（コマの番号から。どの画面でも同じ揺れ方）
func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + seed * 78.233) * 43758.5453, 1.0)


## 層 layer・切り方 cut の炎の形（大きさ 1）: 下が丸く、上に舌が 1〜3 本。はさみで切ったように縁を少しがたつかせる
static func mesh(layer: int, cut: int) -> ArrayMesh:
	var key := Vector2i(layer, cut)
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + cut * 37 + layer * 11
	var sc: float = LAYERS[layer][1]
	var w := W * sc
	var h := H * sc * rng.randf_range(0.9, 1.08)
	var tips: int = [2, 2, 1][layer] + (1 if cut % 2 == 1 and layer == 0 else 0)
	var pts: Array[Vector2] = []
	for j in 7:   # 下の丸み（右から左へ）
		var a := PI * (0.05 + 0.9 * j / 6.0)
		pts.append(Vector2(cos(a) * w, -sin(a) * w * 0.35))
	var lean := rng.randf_range(-0.25, 0.25) * w
	for t in tips:   # 左の縁から舌を 1 本ずつ（いちばん高い舌は真ん中あたり）
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
	var cutpts := PackedVector2Array()   # はさみのがたつき: 辺の途中に、少しずれた点を足す
	for j in pts.size():
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[(j + 1) % pts.size()]
		cutpts.append(a)
		cutpts.append((a + b) / 2.0 + (b - a).orthogonal().normalized() * rng.randf_range(-0.006, 0.006))
	if Geometry2D.is_polygon_clockwise(cutpts):
		cutpts.reverse()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in Geometry2D.triangulate_polygon(cutpts):
		var p: Vector2 = cutpts[i]
		st.set_uv(Vector2(p.x, -p.y) * 2.0)
		st.add_vertex(Vector3(p.x, p.y, 0))
	_meshes[key] = st.commit()
	return _meshes[key]
