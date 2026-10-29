extends Node3D
## 滑るときの風（あなたの画面だけ）。空気の流れを手芸の素材で見せる:
## 進む向きのまわりの筒に、毛糸の切れはし・綿の毛・毛玉の雪を浮かべ、目の横を後ろへ流す。
## 速いほど多く、長く、濃く。乗っていないとき・止まると消える。画面の真ん中は空けて景色を隠さない。
## 滑り木の前からは、パウダーの毛玉を舞い上げる。
## 粒は世界に置き（あなたが空気の中を進むので流れて見える）、層 5 にして、あなたのカメラだけが映す。
## 右上の 360° 映像と、ほかの人には出ない。

const LAYER := 1 << 4
const SPEED_MIN := 2.0      # これより遅いと出さない (m/s)
const SPEED_FULL := 9.0     # これで最も強い（頂上からまっすぐ下ると 10 m/s ほど）
const DRIFT := 0.35         # 粒そのものも後ろへ流れる（ソリの速さに対する割合）。止まった空気より風らしく
const TUBE_R := 2.6         # 流れる筒の外の半径 (m)
const TUBE_IN := 0.8        # 内の半径。目の前の筋は空ける

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float stretch = 1.0;    // 糸の長さ（進む向きに伸ばす）
uniform float strength = 1.0;   // 濃さ
uniform float clear_r = 0.2;    // 画面の真ん中の空ける半径（画面の高さに対する割合）
uniform bool billboard = false; // 綿の毛は、いつもこちらを向く
uniform bool along = false;     // 糸と粒は、長さ（y）を流れの向きにそろえる
uniform vec3 flow = vec3(0.0, 0.0, 1.0);   // 流れの向き（世界）
uniform float bright = 2.0;     // 光を受けない粒を、日なたの雪と同じ明るさに（露出 0.7 と ACES の分）
uniform sampler2D tex : source_color, filter_linear_mipmap, hint_default_white;

void vertex() {
	if (billboard) {
		mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
		float a = INSTANCE_CUSTOM.x;
		w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * w * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	} else if (along) {
		// 粒の向きは流れで決める（粒の仕組みの align_y は、流れが世界の z に近いと崩れる）。
		// 生まれたときの角度で、流れを軸に回してばらつかせる
		vec3 y = normalize(flow);
		vec3 x = normalize(cross(abs(y.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0), y));
		vec3 z = cross(x, y);
		float a = INSTANCE_CUSTOM.x;
		vec3 xr = x * cos(a) + z * sin(a);
		vec3 zr = cross(xr, y);
		float s = length(MODEL_MATRIX[0].xyz);
		VERTEX.y *= stretch;
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(xr * s, 0.0), vec4(y * s, 0.0), vec4(zr * s, 0.0), MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 p = SCREEN_UV - 0.5;
	p.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float edge = smoothstep(clear_r, clear_r + 0.2, length(p));
	float near = smoothstep(0.2, 0.7, -VERTEX.z);   // 目に当たる寸前は消す
	vec4 t = texture(tex, UV);
	ALBEDO = COLOR.rgb * t.rgb * bright;
	ALPHA = COLOR.a * t.a * strength * edge * near;
}
"""

var player: CharacterBody3D
var sled: RigidBody3D
var strength := 1.0   # 設定「風の流れ」: 0〜1
var calm := false     # 設定「視点の揺れ」が切れているとき: 量を減らし、糸のゆらぎを止める
var level := 0.0      # いまの強さ（0〜1。確かめ用に外から読む）
var _threads: GPUParticles3D
var _fluff: GPUParticles3D
var _grains: GPUParticles3D
var _spray: GPUParticles3D
var _flows: Array[GPUParticles3D] = []


func setup(p: CharacterBody3D, s: RigidBody3D) -> void:
	player = p
	sled = s


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER

	# 毛糸の切れはし: 細くよじれた短い糸。雪の影の青と生成りが多く、ところどころ赤と山吹。
	# 白い雪と淡い空の前で読めるよう、色は少し沈める
	_threads = _flow(260, 1.1, _thread_mesh(), _mat(shader, 0.2, false, null, true),
			[Color(0.55, 0.64, 0.84), Color(0.86, 0.80, 0.68), Color(0.62, 0.70, 0.88), Color(0.80, 0.33, 0.30),
			Color(0.90, 0.86, 0.78), Color(0.58, 0.66, 0.86), Color(0.86, 0.68, 0.30), Color(0.84, 0.78, 0.66)])
	_threads.process_material.scale_min = 0.7
	_threads.process_material.scale_max = 1.3
	# 綿の毛: ふわっとした小さなかたまりに、細い繊維が数本。ゆっくり回りながら流れる
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	_fluff = _flow(36, 1.3, q, _mat(shader, 0.22, true, _fluff_texture()),
			[Color(1, 1, 1, 0.9), Color(0.96, 0.97, 1.0, 0.8)])
	var fm: ParticleProcessMaterial = _fluff.process_material
	fm.scale_min = 0.6
	fm.scale_max = 1.4
	fm.angle_min = -180.0
	fm.angle_max = 180.0
	fm.angular_velocity_min = -160.0
	fm.angular_velocity_max = 160.0
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 0.8
	fm.turbulence_noise_scale = 1.5
	fm.turbulence_influence_min = 0.05
	fm.turbulence_influence_max = 0.15
	# 毛玉の雪: 小さな粒。速いと少し尾を引く
	var g := SphereMesh.new()
	g.radius = 0.016
	g.height = 0.032
	g.radial_segments = 5
	g.rings = 3
	_grains = _flow(140, 1.0, g, _mat(shader, 0.18, false, null, true),
			[Color(1, 1, 1), Color(0.90, 0.93, 1.0)])

	# 滑り木の前から舞い上がるパウダー。ソリについて動き出し、空気に止められて後ろへ流れる
	_spray = GPUParticles3D.new()
	_spray.amount = 120
	_spray.lifetime = 0.9
	_spray.local_coords = false
	_spray.layers = LAYER
	_spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spray.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))
	_spray.position = Vector3(0, 0.1, -1.3)
	var sm := ParticleProcessMaterial.new()
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(0.75, 0.03, 0.1)
	sm.direction = Vector3(0, 1, 0.3)
	sm.spread = 60.0
	sm.inherit_velocity_ratio = 0.85
	sm.gravity = Vector3(0, -5.0, 0)
	sm.damping_min = 4.0
	sm.damping_max = 8.0
	sm.scale_min = 0.8
	sm.scale_max = 1.8
	sm.color_ramp = _life_ramp()
	_spray.process_material = sm
	var sg := SphereMesh.new()
	sg.radius = 0.02
	sg.height = 0.04
	sg.radial_segments = 5
	sg.rings = 3
	_spray.draw_pass_1 = sg
	_spray.material_override = _mat(shader, 0.0, false, null)
	_spray.emitting = false
	sled.add_child(_spray)


## 進む向きのまわりの筒から、粒を後ろへ流す仕掛け
func _flow(amount: int, life: float, mesh: Mesh, mat: Material, colors: Array) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.randomness = 0.3
	p.local_coords = false
	p.top_level = true
	p.layers = LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = TUBE_R
	pm.emission_ring_inner_radius = TUBE_IN
	pm.emission_ring_height = 8.0
	pm.direction = Vector3(0, 1, 0)   # この仕掛けの +y が後ろ
	pm.spread = 6.0
	pm.gravity = Vector3(0, -0.3, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color_ramp = _life_ramp()
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i in colors.size():
		g.add_point(float(i) / colors.size(), colors[i])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.material_override = mat
	p.emitting = false
	add_child(p)
	_flows.append(p)
	return p


func _mat(shader: Shader, clear_r: float, billboard: bool, tex: Texture2D, along := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("clear_r", clear_r)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("along", along)
	if tex:
		m.set_shader_parameter("tex", tex)
	return m


## 生まれてすぐ濃くなり、終わりに消える
func _life_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.15, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## 毛糸の切れはし: 長さ 0.3 m の細い管を、ゆるい S 字によじる（長さの向きが y）
func _thread_mesh() -> ArrayMesh:
	const SEGS := 8
	const SIDES := 4
	const LEN := 0.3
	const R := 0.007
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGS + 1:
		var t := float(i) / SEGS
		var c := Vector3(sin(t * PI * 1.6) * 0.03, (t - 0.5) * LEN, sin(t * PI * 2.6 + 0.7) * 0.014)
		var r := R * (1.0 - 0.45 * absf(t - 0.5) * 2.0)   # 端ほど細い（ほつれ）
		for j in SIDES:
			var a := TAU * j / SIDES
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(c + Vector3(cos(a) * r, 0, sin(a) * r))
	for i in SEGS:
		for j in SIDES:
			var a := i * SIDES + j
			var b := i * SIDES + (j + 1) % SIDES
			st.add_index(a)
			st.add_index(a + SIDES)
			st.add_index(b)
			st.add_index(b)
			st.add_index(a + SIDES)
			st.add_index(b + SIDES)
	return st.commit()


## 綿の毛: やわらかい芯から、細い繊維が何本かのびる
func _fluff_texture() -> Texture2D:
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var a := PackedFloat32Array()
	a.resize(N * N)
	for y in N:
		for x in N:
			var d := Vector2(x - N / 2.0 + 0.5, y - N / 2.0 + 0.5).length() / (N / 2.0)
			a[y * N + x] = exp(-d * d * 14.0) * 0.9
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 9:
		var ang := rng.randf() * TAU
		var bend := rng.randf_range(-1.2, 1.2)
		var len := rng.randf_range(0.55, 0.95)
		for s in 60:
			var t := s / 59.0 * len
			var th := ang + bend * t * t
			var px := N / 2.0 + cos(th) * t * N / 2.0
			var py := N / 2.0 + sin(th) * t * N / 2.0
			var ix := clampi(int(px), 0, N - 1)
			var iy := clampi(int(py), 0, N - 1)
			a[iy * N + ix] = maxf(a[iy * N + ix], 0.75 * (1.0 - t))
	for y in N:
		for x in N:
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a[y * N + x], 0.0, 1.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	if player == null or sled == null:
		return
	if player.mode == player.Mode.RIDE and player.sled != sled and is_instance_valid(player.sled):
		# 乗ったソリが替わった（縫ったソリなど）: 雪しぶきもそのソリへ移す
		sled = player.sled
		_spray.reparent(sled, false)
	elif player.mode != player.Mode.RIDE and sled.get("crafted") and get_parent().get("sled"):
		# 降りた縫ったソリは畳まれて消えることがあるので、しぶきはもとのソリへ戻しておく
		sled = get_parent().sled
		_spray.reparent(sled, false)
	var v := sled.linear_velocity
	var speed := v.length()
	var riding: bool = player.mode == player.Mode.RIDE and player.sled == sled
	var want := smoothstep(SPEED_MIN, SPEED_FULL, speed) * strength * (0.55 if calm else 1.0) if riding else 0.0
	level = move_toward(level, want, dt * (1.2 if want > level else 2.5))
	var on := level > 0.01
	for p in _flows:
		p.emitting = on
		p.amount_ratio = level
	_spray.emitting = on and speed > SPEED_MIN + 2.0
	_spray.amount_ratio = level
	# 濃さ: 強いほど濃い。弱まると、まだ宙に残っている粒も一緒に薄れて消える
	var dens := (0.35 + 0.65 * level) * minf(1.0, level * 8.0)
	for p in _flows:
		(p.material_override as ShaderMaterial).set_shader_parameter("strength", dens)
	(_spray.material_override as ShaderMaterial).set_shader_parameter("strength", dens)
	if not on:
		return

	# 筒を、あなたの目から進む向きへ伸ばす。粒は筒の中に生まれ、あなたが追い越すと後ろで消える
	var dir := v / speed if speed > 0.5 else -sled.global_basis.z
	var rel := speed * (1.0 + DRIFT)
	var lead := clampf(rel * 0.9, 3.0, 16.0)
	var eye: Vector3 = player.cam.global_position
	var back := -dir
	var side := (Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD).cross(back).normalized()
	var at := Transform3D(Basis(side, back, side.cross(back)), eye + dir * lead * 0.55 + Vector3.UP * 0.4)
	var stretch := 0.7 + 1.8 * level
	for p in _flows:
		p.global_transform = at
		var pm: ParticleProcessMaterial = p.process_material
		pm.emission_ring_height = lead
		pm.initial_velocity_min = speed * DRIFT * 0.7
		pm.initial_velocity_max = speed * DRIFT * 1.3
		var m: ShaderMaterial = p.material_override
		m.set_shader_parameter("flow", back)
		m.set_shader_parameter("stretch", stretch if p != _grains else 1.0 + 1.5 * level)
	(_fluff.process_material as ParticleProcessMaterial).turbulence_enabled = not calm
	var sp: ParticleProcessMaterial = _spray.process_material
	sp.initial_velocity_min = 1.0 + speed * 0.15
	sp.initial_velocity_max = 2.0 + speed * 0.3
