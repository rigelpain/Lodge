@tool
## （各スクリプトから preload して使う）
## 見た目の部品。世界はフェルトと羊毛、人は紙にフェルトの上着、という決まりをここに集める。
## 質感はすべてコードで作る（外の素材を使わない）。

static var _fiber: NoiseTexture2D      # 羊毛の繊維の凹凸（法線）
static var _fiber_fine: NoiseTexture2D # 細かい毛羽
static var _knit: ImageTexture         # 編み目の模様
static var _paper_tex: NoiseTexture2D  # 紙の地


## 羊毛の繊維の法線マップ（細胞状のノイズ）
static func fiber_normal(fine := false) -> Texture2D:
	if fine:
		if _fiber_fine == null:
			_fiber_fine = _make_fiber(0.16, 9.0)
		return _fiber_fine
	if _fiber == null:
		_fiber = _make_fiber(0.07, 6.0)
	return _fiber


static func _make_fiber(freq: float, bump: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.frequency = freq
	n.fractal_octaves = 3
	n.fractal_lacunarity = 2.2
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = bump
	return t


## 編み目（メリヤス編みの V 字）を描いた画像
static func knit_texture() -> Texture2D:
	if _knit:
		return _knit
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	img.fill(Color(0.86, 0.87, 0.90))
	var cols := 6
	var w := float(s) / cols
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for j in cols * 2:
		for i in cols:
			var cx := i * w + w * 0.5
			var cy := j * w * 0.5 + w * 0.25
			var shade := rng.randf_range(0.74, 0.86)
			# 左右の斜めの糸を、楕円を点で埋めて描く
			for k in 2:
				var dx := -w * 0.17 if k == 0 else w * 0.17
				var ang := 0.55 if k == 0 else -0.55
				for yy in range(-int(w * 0.28), int(w * 0.28)):
					for xx in range(-int(w * 0.14), int(w * 0.14)):
						var fx := float(xx) / (w * 0.14)
						var fy := float(yy) / (w * 0.28)
						if fx * fx + fy * fy > 1.0:
							continue
						var rx := xx * cos(ang) - yy * sin(ang)
						var ry := xx * sin(ang) + yy * cos(ang)
						var px := int(cx + dx + rx)
						var py := int(cy + ry)
						var edge := 1.0 - (fx * fx + fy * fy)
						var v := shade + 0.08 * edge
						img.set_pixel(posmod(px, s), posmod(py, s), Color(v, v, v + 0.01))
	_knit = ImageTexture.create_from_image(img)
	return _knit


static func _paper_noise() -> Texture2D:
	if _paper_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.3
		n.fractal_octaves = 4
		_paper_tex = NoiseTexture2D.new()
		_paper_tex.noise = n
		_paper_tex.width = 128
		_paper_tex.height = 128
		_paper_tex.seamless = true
		_paper_tex.as_normal_map = true
		_paper_tex.bump_strength = 2.0
	return _paper_tex


## フェルト: つや消し、繊維の凹凸、輪郭が毛羽立って光る
static func felt(color: Color, scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = fiber_normal(true)
	m.normal_scale = 0.7
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.0 * scale
	m.rim_enabled = true
	m.rim = 0.55
	m.rim_tint = 0.6
	return m


## 羊毛の雪: 編み目と繊維。リムはなし（地面は浅い角度で見るので、リムがあると一面が白く飛んで形が消える）
static func snow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.975, 0.99)
	m.albedo_texture = knit_texture()
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = fiber_normal(false)
	m.normal_scale = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8   # 1.25 m に 1 回くり返す
	m.rim_enabled = true
	m.rim = 0.0
	m.rim_tint = 0.6
	return m


## 紙: さらりとして、わずかな凹凸
static func paper(color := Color(0.95, 0.93, 0.88)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.normal_enabled = true
	m.normal_texture = _paper_noise()
	m.normal_scale = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 3.0
	return m


## 木（ソリの滑り木など）
static func wood(color := Color(0.55, 0.36, 0.22)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	return m


## 雲を焼く: 正距円筒の小さな画像に、雲の濃さ（R）と陰（G）を書く。空はこれを読むだけ
const CLOUD_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return v;
}
float fbm3(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return v;
}
void fragment() {
	float lon = (UV.x - 0.5) * 6.2831853;
	float lat = (0.5 - UV.y) * 3.1415927;
	vec3 d = vec3(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat));
	float n = fbm(d * vec3(2.2, 4.0, 2.2) + vec3(t * 0.008, 0.0, 0.0));
	float fluff = fbm3(d * 14.0 + vec3(0.0, t * 0.01, 0.0)) * 0.12;
	COLOR = vec4(n + fluff, n + fluff * 0.5, 0.0, 1.0);
}
"""

## 空: 焼いた雲の画像を読み、フェルトの太陽を描く。雲の計算を毎画素でしないので軽い
const SKY_SHADER := """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.50, 0.66, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.87, 0.91, 0.95);
uniform vec3 ground_color : source_color = vec3(0.80, 0.85, 0.90);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.60);
uniform vec3 cloud_color : source_color = vec3(0.99, 0.98, 0.96);
uniform sampler2D clouds : filter_linear, repeat_enable;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	               mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	               mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.03 + vec3(1.7, 9.2, 3.1); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	if (h < 0.0) col = mix(horizon_color, ground_color, smoothstep(0.0, -0.3, h));

	// 羊毛の雲: 焼いた画像から読む（R 濃さ、G 陰）。低い所ほど大きく、縁はふわっと
	vec2 cuv = vec2(atan(d.x, -d.z) / 6.2831853 + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / 3.1415927);
	vec2 c = texture(clouds, cuv).rg;
	float cloud = smoothstep(0.50, 0.66, c.r) * smoothstep(0.02, 0.22, h);
	vec3 shade = mix(cloud_color * 0.82, cloud_color, smoothstep(0.5, 0.75, c.g));
	col = mix(col, shade, cloud * 0.95);

	// フェルトの太陽: はっきりした円と、毛羽立った縁、淡い光
	if (LIGHT0_ENABLED) {
		vec3 s = normalize(LIGHT0_DIRECTION);
		float ang = acos(clamp(dot(d, s), -1.0, 1.0));
		float fuzz = (ang < 0.12) ? fbm3(d * 60.0) * 0.012 : 0.0;   // 毛羽は太陽の近くだけ計算
		float disk = 1.0 - smoothstep(0.040, 0.046, ang + fuzz);
		float halo = exp(-ang * 7.0) * 0.35;
		col = mix(col, sun_color, disk);
		col += sun_color * halo * (1.0 - disk);
	}
	COLOR = col;
}
"""


static var _cloud_vp: SubViewport
static var _cloud_mat: ShaderMaterial


## host（木に入っているノード）に雲を焼くビューポートをぶら下げ、空を返す。
## 雲は tick_clouds() を呼んだときだけ描き直す（0.5 秒ごとで十分。ゆっくり流れる）
static func sky(host: Node) -> Sky:
	_cloud_vp = SubViewport.new()
	_cloud_vp.size = Vector2i(1024, 512)
	_cloud_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_cloud_vp.transparent_bg = false
	host.add_child(_cloud_vp)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var csh := Shader.new()
	csh.code = CLOUD_SHADER
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = csh
	rect.material = _cloud_mat
	_cloud_vp.add_child(rect)

	var sh := Shader.new()
	sh.code = SKY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("clouds", _cloud_vp.get_texture())
	var s := Sky.new()
	s.sky_material = mat
	s.radiance_size = Sky.RADIANCE_SIZE_64
	return s


static func tick_clouds(time: float) -> void:
	if _cloud_mat == null or _cloud_vp == null:
		return
	_cloud_mat.set_shader_parameter("t", time)
	_cloud_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static var _weave: ImageTexture        # 木綿の平織り


## 毛糸の編み地（セーター・マフラー）: 編み目の V と繊維。服の大きさに合わせて目を細かく
static func knit(color: Color, scale := 8.0) -> StandardMaterial3D:
	var m := felt(color * 1.12, 1.0)
	m.albedo_texture = knit_texture()
	m.uv1_scale = Vector3.ONE * scale
	m.normal_texture = fiber_normal(false)
	m.normal_scale = 0.8
	return m


## 木綿の布: 平織りの細かい格子。フェルトより少し張りがあり、縁の光は控えめ
static func cloth(color: Color, scale := 10.0) -> StandardMaterial3D:
	if _weave == null:
		var s := 32
		var img := Image.create(s, s, false, Image.FORMAT_RGB8)
		for y in s:
			for x in s:
				var over := ((x / 2) + (y / 2)) % 2 == 0
				var v := 0.93 if over else 0.82
				v += 0.05 * sin(float(x) * 0.8) * (1.0 if over else 0.0)
				img.set_pixel(x, y, Color(v, v, v))
		_weave = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 1.08
	m.albedo_texture = _weave
	m.roughness = 0.9
	m.normal_enabled = true
	m.normal_texture = fiber_normal(true)
	m.normal_scale = 0.3
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.5
	return m


static var _wagara := {}


## 和柄の布（千代紙の着物の柄を、木綿に染めたもの）。kind: seigaiha 青海波 / kikko 亀甲 / ichimatsu 市松 / mizutama 水玉 / koshi 格子
static func wagara(kind: String, base: Color, ink: Color, scale := 5.0) -> StandardMaterial3D:
	var key := "%s %s %s" % [kind, base.to_html(), ink.to_html()]
	if not _wagara.has(key):
		var s := 128
		var img := Image.create(s, s, false, Image.FORMAT_RGB8)
		for y in s:
			for x in s:
				img.set_pixel(x, y, ink if _wagara_ink(kind, x, y, s) else base)
		img.generate_mipmaps()
		_wagara[key] = ImageTexture.create_from_image(img)
	var m := cloth(Color.WHITE, scale)
	m.albedo_color = Color(1, 1, 1)
	m.albedo_texture = _wagara[key]
	return m


static func _wagara_ink(kind: String, x: int, y: int, s: int) -> bool:
	match kind:
		"seigaiha":
			# 重なった半円の波。下の段ほど手前に描く
			var r := s / 4.0
			var best := -1
			var dist := 0.0
			for j in range(-1, 9):
				for i in range(-1, 5):
					var cx := i * r * 2.0 + (r if j % 2 != 0 else 0.0)
					var cy := j * r * 0.5
					var d := Vector2(x - cx, y - cy).length()
					var dx := Vector2(posmod(x - int(cx) + s / 2, s) - s / 2, y - cy).length()
					d = minf(d, dx)
					if d < r and j >= best:
						best = j
						dist = d
			return fmod(dist / r * 4.0, 1.0) < 0.28
		"kikko":
			# 六角の格子
			var p := Vector2(x, y) / (s / 4.0)
			var q := Vector2(p.x * 1.1547, p.y + p.x * 0.57735)
			var fx := fmod(q.x, 1.0)
			var fy := fmod(q.y, 1.0)
			var fz := fmod(q.x + q.y, 1.0)
			var e := minf(minf(absf(fx - 0.5), absf(fy - 0.5)), absf(fz - 0.5))
			return absf(e) < 0.05
		"ichimatsu":
			return ((x / (s / 4)) + (y / (s / 4))) % 2 == 0
		"mizutama":
			var c := Vector2(posmod(x, s / 4) - s / 8, posmod(y + (s / 8 if (x / (s / 4)) % 2 == 0 else 0), s / 4) - s / 8)
			return c.length() < s / 22.0
		"koshi":
			return posmod(x, s / 2) < 5 or posmod(y, s / 2) < 5 or posmod(x + 9, s / 4) < 2 or posmod(y + 9, s / 4) < 2
	return false


## 滑りあとのステッチ（太い 2 本撚りの糸）。1 目ぶんの形を MultiMesh で並べる。
## 目の形は頂点シェーダーで作るので、各目の長さ・撚りの位相・雪に埋もれる時刻を
## INSTANCE_CUSTOM (長さ m, 位相 0〜1 ＋ 弧の向き, 消えていく時間 s, 消え始める時刻 s) で渡す。時刻は stitch_set_time で進める。
## 弧の向きは位相の整数の部分: 0 でまっすぐ、1・2 で左・右へふくらむ弧（くさり縫いの輪の半分）。
## 目は原点（入る針穴）から -z へ長さぶん伸び、もう一方の針穴へ沈む。面 0 が糸、面 1 が針穴のくぼみと糸の下の影（乗算）。
## 糸の管には粗い形（LOD）を 2 段つける。Godot が画面での大きさから選ぶので、遠くの目と 360° 映像の小窓では粗い形になる
static func stitch_mesh(color: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# 面 0: 糸の管。u（縫い目に沿って 0〜1、両端の沈む所を細かく）× a（まわり 0〜1）の格子
	var nu := 14
	var na := 8
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in nu + 1:
		var u := 0.5 - 0.5 * cos(PI * i / nu)
		for j in na + 1:
			var a := TAU * j / na
			verts.append(Vector3(cos(a) * 0.03, 0.02 + sin(a) * 0.03, -u * 0.3))
			norms.append(Vector3(cos(a), sin(a), 0))
			uvs.append(Vector2(u, float(j) / na))
	idx = _grid_index(range(nu + 1), range(na + 1), na)
	# 粗い形: 輪を間引き（両端の沈む所は残す）、まわりを 4 面に。キーは形の誤差 (m)。この誤差が 1 画素より小さく見える所で使われる
	var lods := {
		0.006: _grid_index([0, 1, 2, 4, 6, 8, 10, 12, 13, 14], [0, 2, 4, 6, 8], na),
		0.014: _grid_index([0, 2, 7, 12, 14], [0, 2, 4, 6, 8], na),
	}
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], lods)
	var sh := Shader.new()
	sh.code = THREAD_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("color", color)
	mesh.surface_set_material(0, mat)

	# 面 1: 目の下に敷く 1 枚の四角。針穴と影はシェーダーで描く
	var q := []
	q.resize(Mesh.ARRAY_MAX)
	q[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.1, 0, 0.08), Vector3(0.1, 0, 0.08), Vector3(-0.1, 0, -0.38), Vector3(0.1, 0, -0.38)])
	q[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	q[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)])
	q[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, q)
	var sh2 := Shader.new()
	sh2.code = STITCH_HOLE_SHADER
	var mat2 := ShaderMaterial.new()
	mat2.shader = sh2
	mat2.set_shader_parameter("shade", Color(0.50, 0.56, 0.74))
	mat2.render_priority = -1
	mesh.surface_set_material(1, mat2)
	mesh.custom_aabb = AABB(Vector3(-0.12, -0.06, -0.8), Vector3(0.24, 0.16, 0.9))
	stitch_set_color(mesh, color)
	return mesh


## 格子の点の番号（行 rows × 列 cols、1 行は na + 1 点）から、四角を 2 つの三角にした番号の列
static func _grid_index(rows: Array, cols: Array, na: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	for r in rows.size() - 1:
		for c in cols.size() - 1:
			var k00: int = rows[r] * (na + 1) + cols[c]
			var k01: int = rows[r] * (na + 1) + cols[c + 1]
			var k10: int = rows[r + 1] * (na + 1) + cols[c]
			var k11: int = rows[r + 1] * (na + 1) + cols[c + 1]
			idx.append_array([k00, k01, k10, k01, k11, k10])
	return idx


## 糸の色を変える（ソリのメインカラー）。雪に近い色（白・ごく淡い色）ほど、糸の輪郭と下の影を濃くして縁取る
static func stitch_set_color(mesh: ArrayMesh, color: Color) -> void:
	var edge := stitch_edge(color)
	var thread: ShaderMaterial = mesh.surface_get_material(0)
	thread.set_shader_parameter("color", color)
	thread.set_shader_parameter("edge", edge)
	(mesh.surface_get_material(1) as ShaderMaterial).set_shader_parameter("edge", edge)


## 雪の色からの離れぐあいで、縁取りの強さ 0〜1 を決める（白で 1、赤や紺で 0）
static func stitch_edge(color: Color) -> float:
	var snow_c := Color(0.97, 0.975, 0.99)   # snow() の地の色
	var d := Vector3(color.r - snow_c.r, color.g - snow_c.g, color.b - snow_c.b).length()
	return 1.0 - smoothstep(STITCH_EDGE_NEAR, STITCH_EDGE_FAR, d)


const STITCH_EDGE_NEAR := 0.12   # 雪からの色の距離（RGB）がこれより近いと、縁取りいっぱい
const STITCH_EDGE_FAR := 0.40    # これより離れていれば縁取りなし


## 縫い目の形: 糸の太さ（半径 m）と、くさり縫いの輪の半分の幅 (m)
static func stitch_set_shape(mesh: ArrayMesh, radius: float, bow: float) -> void:
	var thread: ShaderMaterial = mesh.surface_get_material(0)
	thread.set_shader_parameter("radius", radius)
	thread.set_shader_parameter("bow", bow)
	(mesh.surface_get_material(1) as ShaderMaterial).set_shader_parameter("bow", bow)


## 消え方: 0 は雪に埋もれる（白くなって沈む）、1 はほつれる（撚りがゆるみ、繊維がまんなかから切れていく）
static func stitch_set_style(mesh: ArrayMesh, style: int) -> void:
	for i in 2:
		(mesh.surface_get_material(i) as ShaderMaterial).set_shader_parameter("style", style)


## 滑りあとの時計（消え始める時刻と比べる、ソリごとの経過秒）
static func stitch_set_time(mesh: ArrayMesh, t: float) -> void:
	for i in 2:
		(mesh.surface_get_material(i) as ShaderMaterial).set_shader_parameter("now", t)


## 引きずられ跡のステッチ: ぐし縫いのギャザー。引きずられた人のかかとが雪（毛糸の編み地）を縫い縮め、
## 短いなみ縫いの目のまわりに、布が引き寄せられて寄ったひだ（ギャザー）ができる。
## 目の形は stitch_mesh と同じ（INSTANCE_CUSTOM: 長さ m, 位相, 明るさ, 寄りの強さ 0〜1）。
## 面 0 が細めの糸、面 1 が目のまわりのひだと針穴（乗算）。ひだは目に沿って並ぶ細い山と谷で、目に近いほど詰まって濃い
static func gather_stitch_mesh(color: Color) -> ArrayMesh:
	var mesh := stitch_mesh(color)
	var mat: ShaderMaterial = (mesh.surface_get_material(0) as ShaderMaterial).duplicate()
	mat.set_shader_parameter("radius", 0.018)
	mesh.surface_set_material(0, mat)
	var q := []
	q.resize(Mesh.ARRAY_MAX)
	q[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.17, 0, 0.1), Vector3(0.17, 0, 0.1), Vector3(-0.17, 0, -0.4), Vector3(0.17, 0, -0.4)])
	q[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	q[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 0)])
	q[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3])
	var arr := ArrayMesh.new()
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	arr.surface_set_material(0, mat)
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, q)
	var sh := Shader.new()
	sh.code = GATHER_SHADER
	var m2 := ShaderMaterial.new()
	m2.shader = sh
	m2.set_shader_parameter("shade", Color(0.2, 0.25, 0.48))   # 雪はとても明るいので、深い影の青で掛けないとひだが白く飛ぶ
	m2.render_priority = -1
	arr.surface_set_material(1, m2)
	arr.custom_aabb = AABB(Vector3(-0.2, -0.06, -0.8), Vector3(0.4, 0.16, 0.95))
	return arr


const GATHER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 shade : source_color;

varying vec2 v_p;
varying float v_len;
varying float v_pull;
varying float v_ph;

void vertex() {
	v_len = max(INSTANCE_CUSTOM.x, 0.05);
	v_ph = INSTANCE_CUSTOM.y;
	v_pull = INSTANCE_CUSTOM.w;
	VERTEX = vec3(VERTEX.x, 0.012, mix(0.1, -v_len - 0.1, UV.x));   // 雪面のでこぼこに沈まないよう少し浮かす
	v_p = VERTEX.xz;
}

void fragment() {
	vec2 p = v_p;
	float along = clamp(p.y, -v_len, 0.0);
	float d_line = length(vec2(p.x, p.y - along));
	// ひだ: 目に沿って細い山と谷が並ぶ（横から引き寄せられて寄ったしわ）。目の両端（針穴）へ扇のように集まる
	float t = clamp(-p.y / v_len, 0.0, 1.0);
	float pinch = 1.0 - 0.55 * sin(3.14159 * t);                 // 目のまんなかは寄りが浅く、針穴のそばで深い
	float wave = sin(abs(p.x) * 70.0 / pinch + p.y * 14.0 + v_ph * 6.28318);
	float reach = 1.0 - smoothstep(0.02, 0.17, abs(p.x));         // 目から離れると平らに戻る
	float ends = 1.0 - smoothstep(0.0, 0.09, max(-p.y - v_len, p.y));   // 目の先と後ろへは短く
	float fold = smoothstep(0.35, 0.95, wave) * reach * ends * v_pull;
	// 糸の下の影と、針穴（stitch_mesh と同じ）
	float under = (1.0 - smoothstep(0.01, 0.04, d_line)) * 0.4;
	vec2 hv = length(p) < length(p - vec2(0.0, -v_len)) ? p : p - vec2(0.0, -v_len);
	float dh = length(hv);
	float core = 1.0 - smoothstep(0.004, 0.02, dh);
	float dimple = 1.0 - smoothstep(0.015, 0.08, dh);
	float k = clamp(under + core * 0.5 + dimple * 0.3 + fold * 0.95, 0.0, 0.85);
	ALBEDO = mix(vec3(1.0), shade, k);
}
"""


const THREAD_SHADER := """
shader_type spatial;
render_mode cull_back;

uniform vec3 color : source_color;
uniform float radius = 0.026;   // 糸の太さ（半径 m）
uniform float twist = 12.0;     // 撚りの回数（1 m あたり）
uniform float dive = 0.06;      // 針穴へ沈んでいく長さ (m)
uniform float now = 0.0;        // 滑りあとの時計 (s)。stitch_set_time
uniform float edge = 0.0;       // 雪に近い色の糸の縁取り 0〜1。stitch_set_color
uniform vec3 snow : source_color = vec3(0.84, 0.86, 0.92);   // かぶる雪の粉の色（編み地の雪の、陰りもこみの見た目の色）
uniform int style = 1;          // 消え方。0: 雪に埋もれる、1: ほつれる。stitch_set_style
uniform float bow = 0.04;       // 弧の目（くさり縫いの輪）のふくらみ (m)。stitch_set_shape

varying float v_len;
varying float v_ph;
varying float v_tint;
varying float v_rise;
varying float v_bury;   // 消えていくぐあい 0〜1（埋もれる・ほつれる）
varying float v_up;     // 糸の面が上を向いているか（雪の粉は上から積もる）

// 目のふくらみ: 中ほどが少し太く、両端は細って布の下へ潜る。張られて少し平たい。
// b: 埋もれるにつれて糸は細り、雪の中へ沈む（b = 1 で雪面の下）。
// f: ほつれるにつれて撚りがゆるみ、2 本が離れてふくらみ、張りがなくなって波打つ
vec3 thread_at(float u, float a, float len, float b, float f, float ph, float bw) {
	float e = clamp(min(u, 1.0 - u) * len / dive, 0.0, 1.0);
	float s = sin(e * 1.5708);
	float r = radius * mix(0.68, 1.0, s) * (1.0 + 0.08 * sin(3.14159 * u)) * (1.0 - 0.45 * b);
	float tw = 2.0 * (a + (u * len * twist + ph) * 6.28318);
	r *= 1.0 + 0.5 * f * cos(tw);
	float yc = mix(-1.3 * radius, 0.88 * radius, s) - b * b * 3.0 * radius + f * 0.5 * radius * sin(3.14159 * u);
	float wob = f * 0.35 * radius * sin(u * 9.0 + ph * 30.0) * sin(3.14159 * u);
	float arc = bw * sin(3.14159 * pow(u, 1.4));   // しずく形: 根元はすぼまり、先の近くでいちばんふくらむ
	return vec3(cos(a) * r + wob + arc, yc + sin(a) * r * 0.82, -u * len);
}

void vertex() {
	v_len = max(INSTANCE_CUSTOM.x, 0.05);
	v_ph = fract(INSTANCE_CUSTOM.y);
	float mode = floor(INSTANCE_CUSTOM.y + 0.0005);
	float bw = mode < 0.5 ? 0.0 : (mode < 1.5 ? bow : -bow);
	v_tint = 0.9 + 0.16 * fract(v_ph * 91.7);
	// 消え始め（w）から、消えていく時間（z）で 0 → 1。
	// 埋もれるときは端の針穴から先に埋もれる。ほつれるときは形はゆるむだけで、切れて消えるのは fragment
	float b0 = clamp((now - INSTANCE_CUSTOM.w) / max(INSTANCE_CUSTOM.z, 0.01), 0.0, 1.0);
	float u = UV.x;
	float a = UV.y * 6.28318;
	float b = style == 0 ? clamp(b0 * 1.15 - 0.15 * sin(3.14159 * u), 0.0, 1.0) : b0;
	float sink = style == 0 ? b : 0.0;
	float f = style == 1 ? smoothstep(0.0, 0.6, b) : 0.0;
	vec3 tu = thread_at(min(u + 0.01, 1.0), a, v_len, sink, f, v_ph, bw) - thread_at(max(u - 0.01, 0.0), a, v_len, sink, f, v_ph, bw);
	vec3 ta = thread_at(u, a + 0.05, v_len, sink, f, v_ph, bw) - thread_at(u, a - 0.05, v_len, sink, f, v_ph, bw);
	vec3 n = normalize(cross(ta, tu));
	if (dot(n, vec3(cos(a), sin(a), 0.0)) < 0.0) {
		n = -n;
	}
	VERTEX = thread_at(u, a, v_len, sink, f, v_ph, bw);
	NORMAL = n;
	TANGENT = normalize(tu);
	BINORMAL = normalize(ta);
	v_rise = clamp(min(u, 1.0 - u) * v_len / dive, 0.0, 1.0);
	v_bury = b;
	v_up = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz).y;
	if (b0 >= 1.0) {
		VERTEX = vec3(0.0);   // 消えきった目は描かない（三角が点につぶれる）
	}
}

void fragment() {
	float a = UV.y * 6.28318;
	float sm = UV.x * v_len;   // 縫い目に沿った長さ (m)
	// 2 本撚り: まわり 1 周に山が 2 つ。山は縫い目に沿って斜めにずれていく
	float tw = 2.0 * (a + (sm * twist + v_ph) * 6.28318);
	float c = cos(tw);
	float groove = smoothstep(0.35, 1.0, -c);   // 2 本の撚り糸が合わさる細い谷
	// ほつれる: 繊維（撚りに沿った細い筋）が、目のまんなかから先に切れてなくなる。切れ口の繊維は白っぽく毛羽立つ
	float frayed = 0.0;
	if (style == 1 && v_bury > 0.0) {
		float fib = fract(sin(dot(vec2(floor(tw * 1.3), floor(sm * 28.0 + v_ph * 7.0)), vec2(12.9898, 78.233))) * 43758.5453);
		float cut = v_bury * 1.6 - 0.3 - 0.55 * abs(UV.x - 0.5) * 2.0;
		if (fib < cut) {
			discard;
		}
		frayed = (1.0 - smoothstep(0.0, 0.3, fib - cut)) * smoothstep(0.0, 0.15, v_bury);
		groove *= 1.0 + v_bury;   // 2 本のあいだが開く
	}
	// 撚りの山と谷で面を傾ける（斜めの筋が光を受ける）
	NORMAL = normalize(NORMAL + (TANGENT * 0.9 + BINORMAL * 0.35) * sin(tw) * 0.45);
	// 撚りと逆向きの細い繊維。遠くではちらつくので消す
	float fp = a * 7.0 - sm * 230.0 + v_ph * 40.0;
	float fiber = sin(fp) * (1.0 - smoothstep(0.8, 2.5, fwidth(fp)));
	float sink = mix(0.62, 1.0, smoothstep(0.0, 1.0, v_rise));   // 針穴へ潜る所は暗い
	vec3 col = color * v_tint * (1.0 - 0.32 * groove) * sink * (0.94 + 0.06 * fiber);
	// 雪に近い色の糸: 輪郭（横から見える縁）と撚りの谷を暗くして、雪から浮かせる
	float sil = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 1.5);
	col *= 1.0 - edge * (0.45 * sil + 0.25 * groove);
	// 雪の粉: 上を向いた面から、まだらにかぶっていく（粒は撚りの山ひとつほど）
	float grain = fract(sin(dot(vec2(floor(sm * 60.0 + v_ph * 17.0), floor(a * 1.3)), vec2(12.9898, 78.233))) * 43758.5453);
	float fine = fract(sin(dot(floor(vec2(sm * 400.0, a * 6.0)), vec2(39.346, 11.135))) * 24634.6345);
	float dust = style == 0 ? clamp(v_bury * 1.8 - 0.25 + 0.45 * v_up - 0.5 * grain, 0.0, 1.0) : 0.0;
	dust = smoothstep(0.0, 1.0, dust);
	col = mix(col, col * 0.6 + vec3(0.3), frayed * 0.8);   // 毛羽立った繊維は色が抜けて明るい
	ALBEDO = mix(col, snow * (0.9 + 0.1 * fine), dust);
	ROUGHNESS = mix(mix(0.6, 0.85, groove), 1.0, dust); // 山の頂に糸のつや。雪をかぶるとつやが消える
	SPECULAR = 0.3;
	RIM = 0.35 * (1.0 - dust) + 0.4 * frayed;   // 輪郭の毛羽（ほつれると増える）
	RIM_TINT = 0.55;
}
"""


const STITCH_HOLE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform vec3 shade : source_color;
uniform float now = 0.0;    // 滑りあとの時計 (s)
uniform float edge = 0.0;   // 雪に近い色の糸の縁取り 0〜1（糸の両脇の影を濃く、少し広く）
uniform int style = 1;      // 消え方。0: 雪に埋もれる、1: ほつれる
uniform float bow = 0.04;   // 弧の目のふくらみ (m)

varying vec2 v_p;
varying float v_len;
varying float v_bury;
varying float v_bw;
varying float v_holes;      // 針穴を描くか（弧の 2 本目は、1 本目と同じ針穴なので描かない）

void vertex() {
	v_len = max(INSTANCE_CUSTOM.x, 0.05);
	v_bury = clamp((now - INSTANCE_CUSTOM.w) / max(INSTANCE_CUSTOM.z, 0.01), 0.0, 1.0);
	float mode = floor(INSTANCE_CUSTOM.y + 0.0005);
	v_bw = mode < 0.5 ? 0.0 : (mode < 1.5 ? bow : -bow);
	v_holes = mode > 1.5 ? 0.0 : 1.0;
	VERTEX = vec3(VERTEX.x, 0.0, mix(0.08, -v_len - 0.08, UV.x));
	v_p = VERTEX.xz;
	if (v_bury >= 1.0) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec2 p = v_p;
	// 糸の下の影（糸の両脇ににじむ）。縁取りのときは濃く、少し広く
	float arc = v_bw * sin(3.14159 * pow(clamp(-p.y / v_len, 0.0, 1.0), 1.4));
	float d_line = length(vec2(p.x - arc, p.y - clamp(p.y, -v_len, 0.0)));
	float under = (1.0 - smoothstep(0.012, 0.05 + 0.012 * edge, d_line)) * (0.42 + 0.25 * edge);
	// 針穴: 小さく暗い芯と、まわりのくぼみ。布が穴へ引かれて放射状のしわが寄る
	vec2 h0 = p;
	vec2 h1 = p - vec2(0.0, -v_len);
	vec2 hv = length(h0) < length(h1) ? h0 : h1;
	float dh = length(hv);
	float core = (1.0 - smoothstep(0.004, 0.022, dh)) * v_holes;
	float dimple = (1.0 - smoothstep(0.015, 0.07, dh)) * v_holes;
	float pull = pow(0.5 + 0.5 * cos(atan(hv.y, hv.x) * 7.0), 4.0) * dimple * (1.0 - core);
	float k = clamp(under + core * 0.45 + dimple * 0.22 + pull * 0.08, 0.0, 0.7);
	// 埋もれる: 針穴とくぼみは、糸より先に雪で埋まる。ほつれる: 糸がなくなるのに合わせて、影とくぼみが消える
	k *= style == 0 ? 1.0 - smoothstep(0.0, 0.6, v_bury) : 1.0 - smoothstep(0.3, 0.9, v_bury);
	ALBEDO = mix(vec3(1.0), shade, k);
}
"""


## 光る素材（props の役割 brass・pearl・lacquer・shell・steel。お金のボタンと裁ちばさみ）。
## 真鍮と鋼は金属のつや。白蝶貝と貝の小片（螺鈿）は、見る向きで虹色に変わる（真珠層の薄膜）。漆は黒く深いつや（上塗り）。
## 白蝶貝と貝の小片は少し自分で光り、雪の上で遠くからも分かる
const SHINES := ["brass", "pearl", "lacquer", "shell", "steel"]
const SHINE_SPEC := {   # 色, 金属, 粗さ, 虹色, 自分で光る, 上塗り
	"brass": [Color(0.80, 0.60, 0.24), 1.0, 0.28, 0.0, 0.06, 0.0],
	"steel": [Color(0.66, 0.68, 0.71), 0.95, 0.24, 0.0, 0.0, 0.0],
	"lacquer": [Color(0.025, 0.018, 0.02), 0.0, 0.1, 0.0, 0.0, 1.0],
	"pearl": [Color(0.93, 0.92, 0.90), 0.0, 0.22, 0.4, 0.12, 0.5],
	"shell": [Color(0.86, 0.90, 0.93), 0.0, 0.14, 0.95, 0.45, 0.0],
}
const SHINE_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base : source_color;
uniform float metal = 0.0;
uniform float rough = 0.3;
uniform float iri = 0.0;      // 虹色の強さ
uniform float glow = 0.0;     // 自分で光る強さ
uniform float coat = 0.0;     // 上塗りのつや
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 rainbow(float h) {
	return 0.5 + 0.5 * cos(6.28318 * (h + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// 薄膜の色: 見る向き（nv）と、真珠層の細かな波（場所）で色相がずれる
	float h = nv * 1.7 + sin(wpos.x * 23.0 + wpos.z * 17.0) * 0.16 + sin(wpos.x * 61.0 - wpos.z * 47.0) * 0.07;
	vec3 film = rainbow(h);
	vec3 col = mix(base, base * 0.5 + film * 0.62, iri * (0.4 + 0.6 * (1.0 - nv)));
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5 + 0.3 * coat;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.06;
	EMISSION = col * glow * (0.5 + 0.5 * (1.0 - nv));
}
"""
static var _shines := {}
static var _shine_sh: Shader


static func shine(role: String) -> ShaderMaterial:
	if _shines.has(role):
		return _shines[role]
	if _shine_sh == null:
		_shine_sh = Shader.new()
		_shine_sh.code = SHINE_SHADER
	var sp: Array = SHINE_SPEC.get(role, SHINE_SPEC["steel"])
	var m := ShaderMaterial.new()
	m.shader = _shine_sh
	m.resource_name = role
	m.set_shader_parameter("base", sp[0])
	m.set_shader_parameter("metal", sp[1])
	m.set_shader_parameter("rough", sp[2])
	m.set_shader_parameter("iri", sp[3])
	m.set_shader_parameter("glow", sp[4])
	m.set_shader_parameter("coat", sp[5])
	_shines[role] = m
	return m
