extends Node3D
## 火の手本（2026-11-01 代表「火の表現は焚き火にそろえてほしい」）。焚き火（campfire.gd）の炎と灯りを、ほかの所でも使える部品にしたもの。
## キャンドル・松明なども、これを置いて大きさと明るさを変えて使う（lodge_lights.gd）。
##   形: 薄葉紙をくしゃっと重ねた炎（2026-11-02 代表が案 design/campfire/proposal-flames.jpg の左から 4 つ目を選んだ）。
##       花びらのような紙を、外から赤 7 枚・橙 5 枚・黄 4 枚、輪に立てて重ねる。上ですぼまり、しわで縁がよれる。
##       紙そのものが灯って見える（光を受けない塗り。しわの陰だけ付ける）
##   動き: 人形と同じ 12 コマ／秒。くしゃっとさせ方の違う 4 つの形を 2 コマごとに差し替える（置き換えのコマ撮り）。少し傾き、背が伸び縮みする
##   灯り: 電球色より赤みの点の灯り（影なし）。1 コマごとに揺らぐ
##   重さ: 1 つの形に、紙すべてをまとめて焼いてある（炎 1 つで描く回数は 1 回。並べても軽い）
## 形の種類（style）:
##   "tissue" 薄葉紙（上のとおり。既定）
##   "felt"   切ったフェルト（2026-11-02 代表がロッジの暖炉に、案 design/campfire/proposal-flames.jpg の左から 2 つ目を選んだ）。
##            赤・橙のフェルトと黄の紙を、下が丸く上に舌が 1〜3 本ある形に切り、3 枚重ねて十字に差す。はさみで切った縁のがたつき。
##            切り方の違う 4 つの形を、層ごとにずらして 2 コマごとに差し替える
## 使い方:
##   var f := preload("res://flame.gd").new()
##   f.size = 0.15          # 炎の高さの倍率（1 で焚き火の 0.9 m。キャンドルなら 0.1〜0.15）
##   f.brightness = 0.3     # 灯りの強さの倍率（1 で焚き火）。0 なら灯りを作らない
##   f.light_range = 3.0    # 灯りの届く距離 (m)
##   f.seed = 7             # 揺れ方をずらす（並べた火が同じに揺れないように）
##   f.style = "felt"       # 形の種類（既定は "tissue"）
##   add_child(f)           # 節の原点が炎の根元。炎は節の上（+Y）へ伸びる。傾いた物に付けても、炎はまっすぐ上
##   f.level = 0.5          # 強さ 0〜1（火がつく・弱る・消えるは持ち主が入れる。0 で炎も灯りも消える）

const Look := preload("res://look.gd")
const Doll := preload("res://doll.gd")

## 紙の層: [色, 枚数, 高さ, 輪の半径, 花びらの幅, 光る強さ]（大きさ 1。外から赤・橙・黄）
const LAYERS := [[Color(0.80, 0.15, 0.07), 7, 0.9, 0.2, 0.2, 0.2], [Color(0.98, 0.45, 0.06), 5, 0.69, 0.13, 0.15, 0.3],
	[Color(1.0, 0.78, 0.22), 4, 0.48, 0.07, 0.11, 0.5]]
const H := 0.9               # 大きさ 1 の炎の高さ (m)
## 切ったフェルトの層: [色, 大きさ, 光る強さ, 紙か]（外から赤・橙のフェルト、黄の紙）
const FELT_LAYERS := [[Color(0.84, 0.22, 0.12), 1.0, 0.45, false], [Color(0.95, 0.50, 0.14), 0.7, 0.6, false], [Color(1.0, 0.82, 0.36), 0.42, 0.8, true]]
const FELT_W := 0.25         # 大きさ 1 の切ったフェルトの炎の幅の半分 (m)
const CUTS := 4              # くしゃっとさせ方の数
const LIGHT_COLOR := Color(1.0, 0.60, 0.30)
const LIGHT_ENERGY := 2.6    # 明るさ 1 の灯りの強さ
const LIGHT_Y := 0.55        # 大きさ 1 のとき、灯りの芯の高さ (m)

## 薄葉紙: 色は頂点の色（a は明るさ）。光を受けない塗り（炎の中の灯りに照らされて白く飛ばないように。紙そのものが灯って見える）。
## 面の向きで、しわの陰を少し付ける（正面を向いた所ほど明るく、斜めの縁は濃い色）。紙のざらつきでむらを付ける
const PAPER_SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;
uniform sampler2D paper_n : hint_normal, filter_linear_mipmap, repeat_enable;
void fragment() {
	float face = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float grain = texture(paper_n, UV * 3.0).r;
	float shade = mix(0.62, 1.0, face) * (0.9 + 0.2 * grain);
	ALBEDO = COLOR.rgb * shade * (0.7 + 0.6 * COLOR.a);
}
"""

@export var size := 1.0
@export var brightness := 1.0
@export var light_range := 7.5
@export var seed := 0
@export var style := "tissue"   # "tissue" 薄葉紙、"felt" 切ったフェルト
var level := 1.0             # 強さ（0〜1）

static var _meshes := {}     # くしゃっとさせ方 → ArrayMesh（大きさ 1。どの火も同じ形を使い回す）
static var _mat: ShaderMaterial
static var _felt_meshes := {}   # Vector2i(層, 切り方) → ArrayMesh（切ったフェルト）
var _body: MeshInstance3D
var _planes: Array[Node3D] = []   # 切ったフェルト: 十字に差した 2 枚の面（層ごとの形をのせる）
var _light: OmniLight3D
var _k := -1


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	if style == "felt":
		_make_planes()
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


## 1 コマ: 形を 2 コマごとに替え（同じ形は続けない）、大きさは強さで。灯りは 1 コマごとに揺らぐ
func _step(k: int) -> void:
	_k = k
	var on := level > 0.0 and is_visible_in_tree()
	var step := k / 2
	var up := global_basis.orthonormalized().inverse()   # 傾いた物に付けても、炎はまっすぐ上へ
	_body.visible = on and style != "felt"
	if on and style == "felt":
		_step_felt(step, up)
	elif on:
		var cut := int(_hash(step * 3) * CUTS)
		if cut == int(_hash((step - 1) * 3) * CUTS):
			cut = (cut + 1) % CUTS
		var jit := 1.0 + (_hash(step * 5) - 0.5) * 0.12
		var s := size * level
		_body.mesh = mesh(cut)
		_body.basis = (up * Basis(Vector3.UP, seed * 0.7) * Basis(Vector3.BACK, (_hash(step * 7) - 0.5) * 0.1)) \
				.scaled_local(Vector3(s * (2.0 - jit), s * jit, s * (2.0 - jit)))
	if _light:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY * brightness * level * (0.82 + 0.18 * _hash(k * 13 + 5))
		_light.position = up * Vector3((_hash(k * 3) - 0.5) * 0.06 * size, LIGHT_Y * size + (_hash(k * 5) - 0.5) * 0.05 * size, (_hash(k * 9) - 0.5) * 0.06 * size)


## 0 〜 1 の決まった乱数（コマの番号から。どの画面でも同じ揺れ方）
func _hash(n: int) -> float:
	return fposmod(sin(float(n) * 12.9898 + seed * 78.233) * 43758.5453, 1.0)


## くしゃっとさせ方 cut の炎の形（大きさ 1。根元が原点、上が +Y）: 薄葉紙の花びらを層ごとに輪に立てて重ねる
static func mesh(cut: int) -> ArrayMesh:
	if _meshes.has(cut):
		return _meshes[cut]
	var rng := RandomNumberGenerator.new()
	rng.seed = 211 + cut * 53
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li in LAYERS.size():
		var L: Array = LAYERS[li]
		var col: Color = L[0]
		col.a = L[5]
		var n: int = L[1]
		for j in n:
			var a := TAU * j / n + rng.randf_range(-0.3, 0.3) + li
			var h: float = L[2] * rng.randf_range(0.85, 1.08)
			var lean := rng.randf_range(0.12, 0.3)   # 上で真ん中へ寄る
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -lean)
			var at := Vector3(sin(a), 0, cos(a)) * float(L[3]) * 0.5
			_petal(st, Transform3D(b, at), float(L[4]), h, col, rng)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, material())
	_meshes[cut] = m
	return m


## 花びら 1 枚: 下が広く上ですぼまり、横に少し丸まって（内へくぼむ）、しわで面がよれ、縁ががたつく。xf の上で、外（+Z）を向く
static func _petal(st: SurfaceTool, xf: Transform3D, w: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	const COLS := 5
	const ROWS := 8
	var grid := []
	for r in ROWS + 1:
		var t := float(r) / ROWS
		var half := w * 0.5 * sin(PI * (0.08 + 0.92 * t)) * (1.0 - 0.55 * t) + w * 0.06 * (1.0 - t)
		var row := []
		for c in COLS + 1:
			var u := float(c) / COLS * 2.0 - 1.0
			var x := u * half + rng.randf_range(-0.006, 0.006)
			var y := h * (1.0 - cos(PI * t)) * 0.5 + rng.randf_range(-0.008, 0.008)
			var z := -0.35 * half * (1.0 - u * u) + rng.randf_range(-0.012, 0.012)   # 丸まりと、しわ
			row.append(xf * Vector3(x, y, z))
		grid.append(row)
	st.set_color(col)
	for r in ROWS:
		for c in COLS:
			var q: Array[Vector3] = [grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]]
			var uv: Array[Vector2] = [Vector2(c, r), Vector2(c + 1, r), Vector2(c + 1, r + 1), Vector2(c, r + 1)]
			var nrm := (q[1] - q[0]).cross(q[3] - q[0]).normalized()
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrm)
				st.set_uv(uv[i] / Vector2(COLS, ROWS))
				st.add_vertex(q[i])


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = PAPER_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("paper_n", Look._paper_noise())
	return _mat



# ---------------------------------------------------------------- 切ったフェルト

## 十字に差す 2 枚の面。層ごとに 1 つずつ形をのせる（外の層は 1 枚、内の層は表と裏に 1 枚ずつ。どちらから見ても重なって見える）
func _make_planes() -> void:
	for pi in 2:
		var plane := Node3D.new()
		add_child(plane)
		plane.set_meta("yaw", pi * PI / 2.0 + 0.4 + seed * 0.7)
		for li in FELT_LAYERS.size():
			var col: Color = FELT_LAYERS[li][0]
			var m: StandardMaterial3D = Look.paper(col) if FELT_LAYERS[li][3] else Look.felt(col, 3.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.rim_enabled = false
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = FELT_LAYERS[li][2]
			for side in ([0.0] if li == 0 else [-1.0, 1.0]):
				var mi := MeshInstance3D.new()
				mi.material_override = m
				mi.position.z = side * 0.007 * li
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.set_meta("layer", li)
				plane.add_child(mi)
		_planes.append(plane)


## 1 コマ（切ったフェルト）: 面ごとに切り方を 2 コマごとに替え、内の層は外とずらす（いっしょに動かない）
func _step_felt(step: int, up: Basis) -> void:
	for pi in _planes.size():
		var plane := _planes[pi]
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
			var lc := cut if li == 0 else (cut + li + int(_hash(step + li) * 2.0)) % CUTS
			mi.mesh = felt_mesh(li, lc)


## 層 layer・切り方 cut の切ったフェルトの形（大きさ 1）: 下が丸く、上に舌が 1〜3 本。はさみで切ったように縁を少しがたつかせる
static func felt_mesh(layer: int, cut: int) -> ArrayMesh:
	var key := Vector2i(layer, cut)
	if _felt_meshes.has(key):
		return _felt_meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + cut * 37 + layer * 11
	var sc: float = FELT_LAYERS[layer][1]
	var w := FELT_W * sc
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
	_felt_meshes[key] = st.commit()
	return _felt_meshes[key]
