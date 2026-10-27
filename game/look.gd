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


## 羊毛の雪: 編み目と繊維、強めのリム
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
	m.rim = 0.35
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


## 空: 羊毛の雲とフェルトの太陽
const SKY_SHADER := """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.50, 0.66, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.87, 0.91, 0.95);
uniform vec3 ground_color : source_color = vec3(0.80, 0.85, 0.90);
uniform vec3 sun_color : source_color = vec3(1.0, 0.86, 0.60);
uniform vec3 cloud_color : source_color = vec3(0.99, 0.98, 0.96);

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

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	if (h < 0.0) col = mix(horizon_color, ground_color, smoothstep(0.0, -0.3, h));

	// 羊毛の雲: 低い所ほど大きく、縁はふわっと
	vec3 q = d * vec3(2.2, 4.0, 2.2) + vec3(TIME * 0.008, 0.0, 0.0);
	float n = fbm(q);
	float fluff = fbm3(d * 14.0 + vec3(0.0, TIME * 0.01, 0.0)) * 0.12;
	float cloud = smoothstep(0.50, 0.66, n + fluff) * smoothstep(0.02, 0.22, h);
	vec3 shade = mix(cloud_color * 0.82, cloud_color, smoothstep(0.5, 0.75, n + fluff * 0.5));
	col = mix(col, shade, cloud * 0.95);

	// フェルトの太陽: はっきりした円と、毛羽立った縁、淡い光
	if (LIGHT0_ENABLED) {
		vec3 s = normalize(LIGHT0_DIRECTION);
		float ang = acos(clamp(dot(d, s), -1.0, 1.0));
		float fuzz = fbm3(d * 60.0) * 0.012;
		float disk = 1.0 - smoothstep(0.040, 0.046, ang + fuzz);
		float halo = exp(-ang * 7.0) * 0.35;
		col = mix(col, sun_color, disk);
		col += sun_color * halo * (1.0 - disk);
	}
	COLOR = col;
}
"""


static func sky() -> Sky:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var s := Sky.new()
	s.sky_material = mat
	s.radiance_size = Sky.RADIANCE_SIZE_64
	s.process_mode = Sky.PROCESS_MODE_INCREMENTAL   # 周囲光の更新を数フレームに分けて、山をなくす
	return s


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
