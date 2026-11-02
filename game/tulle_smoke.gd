extends Node3D
## 焚き火の煙: 灰色のチュール（網目の薄い布）の帯を 3 本、ねじりながら上へ重ねる
## （2026-11-02 代表が案 design/campfire/proposal-smokes.jpg の左から 3 つ目を選んだ）。
## 帯は根元で細く、上ほど幅が広がって、上と下の端で薄く消える。網目が透けて後ろの景色が見える。
## 動きは人形と同じ 12 コマ／秒: 帯のうねりの違う 8 つの形を 2 コマごとに順に差し替える（ゆっくりねじれながら昇って見える）。
## 光は受ける（夜は暗い灰色で、根元だけ火に照らされる。白い息のように光らない）
## 使い方: add_child(preload("res://tulle_smoke.gd").new())。原点が帯の根元、+Y へ HEIGHT 伸びる。level（0〜1）で大きさ、0 で消える

const Doll := preload("res://doll.gd")

const BANDS := 3
const ROWS := 24
const PHASES := 8            # うねりの形の数（2 コマごとに 1 つ進む）
const HEIGHT := 1.25         # 帯の高さ (m)
const COLOR := Color(0.74, 0.73, 0.71)

const TULLE_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D net : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.74, 0.73, 0.71);
uniform float opacity = 0.42;
void fragment() {
	float a = texture(net, UV * vec2(9.0, 26.0)).r;   // 細かい網目（遠くでは、うっすら透ける布に見える）
	float ends = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));   // 下と上の端で薄く消える
	ALBEDO = tint;
	ROUGHNESS = 1.0;
	ALPHA = a * ends * opacity * COLOR.a;
}
"""

var level := 1.0
static var _meshes: Array[ArrayMesh] = []
static var _mat: ShaderMaterial
var _body: MeshInstance3D
var _k := -1


func _ready() -> void:
	_body = MeshInstance3D.new()
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	_step(Doll.frame_index())


func _process(_dt: float) -> void:
	var k := Doll.frame_index()
	if k != _k:
		_step(k)


func _step(k: int) -> void:
	_k = k
	_body.visible = level > 0.0 and is_visible_in_tree()
	if not _body.visible:
		return
	if _meshes.is_empty():
		for p in PHASES:
			_meshes.append(_bake(TAU * p / PHASES))
	_body.mesh = _meshes[posmod(k / 2, PHASES)]
	var up := global_basis.orthonormalized().inverse()   # 傾いた物に付けても、煙はまっすぐ上へ
	_body.basis = up.scaled_local(Vector3.ONE * clampf(level, 0.0, 1.6))


## うねりの位相 ph の帯 3 本（UV の y は根元 0 〜 上 1、x は帯の幅）
static func _bake(ph: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for b in BANDS:
		var bp := ph + b * 2.1
		var rows := []
		for i in ROWS + 1:
			var t := float(i) / ROWS
			var c := Vector3(0.1 * sin(t * 4.0 + bp) * t, HEIGHT * t, 0.1 * cos(t * 3.0 + bp) * t)
			var w := 0.04 + 0.18 * t
			var ang := bp * 0.5 + t * 2.5 + b * 1.0
			var d := Vector3(cos(ang), 0, sin(ang)) * w
			rows.append([c - d, c + d, t])
		for i in ROWS:
			var r0: Array = rows[i]
			var r1: Array = rows[i + 1]
			var q: Array[Vector3] = [r0[0], r0[1], r1[1], r1[0]]
			var uv: Array[Vector2] = [Vector2(0, r0[2]), Vector2(1, r0[2]), Vector2(1, r1[2]), Vector2(0, r1[2])]
			for j in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uv[j])
				st.add_vertex(q[j])
	var m := st.commit()
	m.surface_set_material(0, _material())
	return m


static func _material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = TULLE_SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("net", _net())
		_mat.set_shader_parameter("tint", COLOR)
	return _mat


## チュールの網目: 六角に近い菱形の目の糸（白）と、透ける穴（薄い）
static func _net() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var d1 := absf(fposmod(u + v, 0.5) - 0.25)   # 斜めの糸 2 本で菱形の目
			var d2 := absf(fposmod(u - v, 0.5) - 0.25)
			var thread := 1.0 - smoothstep(0.015, 0.04, minf(0.25 - d1, 0.25 - d2))
			var a := maxf(thread, 0.18)
			img.set_pixel(x, y, Color(a, a, a, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
