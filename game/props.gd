@tool
## 外の小物（props/ の Blender の台本で作った glb）を置くための部品。
## glb の素材の名前は役割（felt_red, wood, cotton …）。品物ごとに焼いた色と凹凸の画像があればそれを使い、
## 役割の仲間（フェルト・木・毛糸・麻・綿・紙）ごとに、CC0 の写真の細部（明暗と凹凸）を重ねる。
## 焼いていない部品（糸・毛糸・麻ひも・綿・紙・フィルム）は、色に同じ細部を重ねる。
## 作り方と名前の一覧は props/README.md、細部の画像の出どころは props/SOURCES.md。

const Look := preload("res://look.gd")
const TEX := "res://props/textures/"

static var _mats := {}
static var _tex := {}


## glb を読んで、手芸の素材を着せた節点を返す
static func make(path: String) -> Node3D:
	var n: Node3D = (load(path) as PackedScene).instantiate()
	dress(n)
	return n


## 下にある MeshInstance3D の素材を差し替える。灯りの目印（light*）には暖色の灯りをともす。
## 湯気の形（*steam*）は隠して、もくもく立ちのぼる煙の粒子に替える（調理の道具の煙は、調理中だけ出す）
static func dress(root: Node) -> void:
	for node in root.find_children("*steam*", "Node3D", true, false):
		if node is MeshInstance3D:   # 古い glb: 湯気の形
			var mi: MeshInstance3D = node
			var box := mi.get_aabb()
			mi.visible = false
			var at := mi.position + mi.basis * Vector3(box.get_center().x, box.position.y, box.get_center().z)
			_smoke(mi.get_parent(), at, maxf(box.size.x, box.size.z), box.size.y, _cook_mark_above(mi) != null)
		elif node.get_child_count() == 0:   # 湯気の目印: 大きさは x＝幅、y＝高さ
			var size: Vector3 = node.scale
			node.scale = Vector3.ONE
			_smoke(node, Vector3.ZERO, size.x, size.y, "cook" in str(node.name) or _cook_mark_above(node) != null)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if not mi.visible:
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src:
				mi.set_surface_override_material(i, material_for(src))
	for node in root.find_children("light*", "Node3D", true, false):
		if node is MeshInstance3D:
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.46)   # 電球色より少し赤み（lodge.gd と同じ）
		l.light_energy = 0.8
		l.omni_range = 4.0
		l.shadow_enabled = false
		node.add_child(l)


## 主な色の差し替え（ソリのメインカラーなど）。焼いた色の画像のうち、色相が key に近く鮮やかな所だけを to の色へ移す。
## 明るさと鮮やかさは key に対する比で移すので、影・縫い目・暗い握り（felt_red_dark）は to の暗い色になる。
## ほかの色（金・緑・生成り・クラフト紙・木）はそのまま。素材は material_for と同じ組み方（写真の細部を 3 方向から、ふちの毛羽）を
## シェーダーで組み直したもの。2 回目からは色だけ変える。
## whole（米袋）: 色相で選ぶのでなく、地（クラフト紙）ごと to にし、印刷（赤い丸・「米」・稲穂・帯）と縫い目は
## 地の上で読める 1 色（ink。地が暗ければ生成りの白抜き、明るければ地の色の濃い色）にする。口のテープは生成りのまま
static func recolor(root: Node, key: Color, to: Color, whole := false) -> void:
	var ink := Color("EFE6D2") if to.get_luminance() < 0.5 else to.darkened(0.6)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is ShaderMaterial and m.has_meta("recolor"):
				m.set_shader_parameter("to", to)
				m.set_shader_parameter("ink", ink)
				continue
			var b := m as StandardMaterial3D
			if b == null or b.albedo_texture == null or family(b.resource_name)[0] in ["wood"]:
				continue
			var r := ShaderMaterial.new()
			r.shader = _recolor_shader()
			r.resource_name = b.resource_name
			r.set_meta("recolor", true)
			r.set_shader_parameter("albedo_tex", b.albedo_texture)
			r.set_shader_parameter("normal_tex", b.normal_texture if b.normal_enabled else null)
			r.set_shader_parameter("detail_albedo", b.detail_albedo)
			r.set_shader_parameter("detail_normal", b.detail_normal)
			r.set_shader_parameter("detail_scale", b.uv2_scale.x)
			r.set_shader_parameter("roughness", b.roughness)
			r.set_shader_parameter("rim", b.rim if b.rim_enabled else 0.0)
			r.set_shader_parameter("rim_tint", b.rim_tint)
			r.set_shader_parameter("key", key)
			r.set_shader_parameter("to", to)
			r.set_shader_parameter("whole", whole)
			r.set_shader_parameter("ink", ink)
			mi.set_surface_override_material(i, r)


static var _recolor_sh: Shader


static func _recolor_shader() -> Shader:
	if _recolor_sh == null:
		_recolor_sh = Shader.new()
		_recolor_sh.code = RECOLOR_SHADER
	return _recolor_sh


const RECOLOR_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 1.6;   // 写真の細部を 1 m に何回くり返すか（family の 2 つめ）
uniform float roughness = 0.95;
uniform float rim = 0.25;
uniform float rim_tint = 0.5;
uniform vec3 key : source_color;    // 焼いてある主な色
uniform vec3 to : source_color;     // 差し替える色
uniform float hue_width = 0.04;     // key の色相から、これだけ離れた色まで差し替える（0〜1 の色相環で）
uniform float min_sat = 0.3;        // これより鮮やかでない色（生成り・白・灰）は差し替えない
uniform bool whole = false;         // 米袋: 地ごと to にし、印刷は ink に（recolor の説明）
uniform vec3 ink : source_color;

varying vec3 v_tri_w;
varying vec3 v_tri_p;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

vec3 recolor(vec3 c) {
	vec3 h = rgb2hsv(c);
	vec3 k = rgb2hsv(key);
	vec3 t = rgb2hsv(to);
	float dh = abs(h.x - k.x);
	dh = min(dh, 1.0 - dh);
	float w = (1.0 - smoothstep(hue_width * 0.6, hue_width, dh)) * smoothstep(min_sat * 0.7, min_sat, h.y);
	float sat = clamp(h.y * t.y / max(k.y, 1e-3), 0.0, 1.0);
	float val = min(h.z * max(t.z, 0.06) / max(k.z, 1e-3), 1.0);
	return mix(c, hsv2rgb(vec3(t.x, sat, val)), w);
}

// 米袋の焼いた色（sRGB の色相環で、クラフト紙は色相 0.1・鮮やかさ 0.25〜0.55、金の印刷は同じ色相でもっと鮮やか、
// 赤は 0〜0.05、緑は 0.2〜0.3、口のテープは淡い）を、地・テープ・印刷に分けて塗り直す
vec3 paint_whole(vec3 c) {
	vec3 h = rgb2hsv(pow(c, vec3(1.0 / 2.2)));
	float dh = abs(h.x - 0.1);
	dh = min(dh, 1.0 - dh);
	float ground = (1.0 - smoothstep(0.03, 0.05, dh)) * smoothstep(0.16, 0.24, h.y) * (1.0 - smoothstep(0.54, 0.62, h.y))
			* smoothstep(0.38, 0.5, h.z);
	float tape = (1.0 - smoothstep(0.14, 0.22, h.y)) * smoothstep(0.72, 0.84, h.z);
	float printed = clamp(1.0 - ground - tape, 0.0, 1.0);
	float shade = pow(clamp(h.z / 0.8, 0.0, 1.25), 2.2);   // 地の明るさのむら（しわ・影）を残す
	vec3 g = to * shade;
	vec3 tp = mix(c, to, 0.15);
	vec3 p = ink * pow(clamp(h.z / 0.72, 0.55, 1.15), 2.2);
	return g * ground + tp * tape + p * printed;
}

vec4 triplanar(sampler2D s, vec3 p, vec3 w) {
	return texture(s, p.zy * vec2(-1.0, 1.0)) * w.x + texture(s, p.xz) * w.y + texture(s, p.xy) * w.z;
}

void vertex() {
	vec3 w = abs(NORMAL);   // StandardMaterial3D の uv2_triplanar（なめらかさ 1）と同じ
	v_tri_w = w / (w.x + w.y + w.z);
	v_tri_p = VERTEX * detail_scale * vec3(1.0, -1.0, 1.0);
}

void fragment() {
	vec4 d = triplanar(detail_albedo, v_tri_p, v_tri_w);
	vec3 a = whole ? paint_whole(texture(albedo_tex, UV).rgb) : recolor(texture(albedo_tex, UV).rgb);
	ALBEDO = mix(a, a * d.rgb, d.a);   // 写真の細部の明暗をかけ算（StandardMaterial3D の BLEND_MODE_MUL と同じ）
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, triplanar(detail_normal, v_tri_p, v_tri_w).rgb, d.a);
	ROUGHNESS = roughness;
	RIM = rim;
	RIM_TINT = rim_tint;
}
"""


static func _t(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load(TEX + name + ".png")
	return _tex[name]


## 役割の名前から、細部の仲間と、細部の細かさ（1 m に何回くり返すか）
static func family(role: String) -> Array:
	if role.begins_with("wood") or role in ["pole", "trunk", "button", "floor"]:
		return ["wood", 1.2]
	if role.begins_with("yarn") or role.begins_with("thread"):
		return ["yarn", 6.0]
	if role == "hemp":
		return ["hemp", 4.0]
	if role == "cotton" or role == "snow":
		return ["cotton", 2.0]
	if role.begins_with("paper"):
		return ["paper", 2.0]
	return ["felt", 1.6]


static func material_for(src: Material) -> Material:
	var role := src.resource_name.get_slice(".", 0)
	var base := src as BaseMaterial3D
	var baked := base != null and base.albedo_texture != null
	# 焼いた素材は名前（felt.001 など）が小物どうしで重なるので、色の画像で見分ける
	var key: String = (base.albedo_texture.resource_path if base.albedo_texture.resource_path != "" \
			else str(base.albedo_texture.get_instance_id())) if baked else role
	if _mats.has(key):
		return _mats[key]
	if role in Look.SHINES:   # 焼いていない光る素材（お金のボタン・裁ちばさみ）
		_mats[key] = Look.shine(role)
		return _mats[key]
	var col := base.albedo_color if base else Color.WHITE
	var m := StandardMaterial3D.new()
	m.resource_name = role
	var fam: Array = family(role)
	if baked:
		m.albedo_texture = base.albedo_texture
		if base.normal_texture:
			m.normal_enabled = true
			m.normal_texture = base.normal_texture
			m.normal_scale = 1.0
	else:
		m.albedo_color = col
	# 写真の細部（明暗をかけ算、凹凸を重ねる）。物の向きに合わせて 3 方向から貼る
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_albedo = _t(fam[0] + "_detail")
	m.detail_normal = _t(fam[0] + "_normal")
	m.uv2_triplanar = true
	m.uv2_scale = Vector3.ONE * float(fam[1])
	m.roughness = 0.65 if fam[0] == "wood" else 0.95
	m.rim_enabled = fam[0] in ["felt", "cotton", "yarn"]
	m.rim = 0.25 if fam[0] != "cotton" else 0.5
	m.rim_tint = 0.5
	if role == "felt_heat" or role == "fire" or role.begins_with("felt_flame"):   # 熱をもったフェルト・炎
		m.emission_enabled = true
		m.emission = Color.WHITE if baked else col
		m.emission_texture = base.albedo_texture if baked else null   # 焼いた色のまま光る
		m.emission_energy_multiplier = 0.5 if role == "felt_heat" else 4.0   # 熱は橙のまま（強いと白く飛ぶ）
	elif role == "paper":                       # 紙の灯り
		m.emission_enabled = true
		m.emission = Color(1.0, 0.74, 0.44)
		m.emission_texture = base.albedo_texture if baked else null
		m.emission_energy_multiplier = 1.6
	elif role == "glass":                       # 透明なフィルム
		m.detail_enabled = false
		m.albedo_color = Color(col, 0.3)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.1
		m.rim_enabled = false
	elif role == "snow":                        # 外の雪（毛糸の編み地）は look.gd のまま
		_mats[key] = Look.snow()
		return _mats[key]
	_mats[key] = m
	return m


# ---------------------------------------------------------------- 煙
static var _puff: Texture2D
static var _smoke_mat: StandardMaterial3D


## 調理の道具（目印 cook* のある品物）の煙を出す・止める
static func set_cooking(item: Node, on: bool) -> void:
	for p in item.find_children("Smoke", "GPUParticles3D", true, false):
		(p as GPUParticles3D).emitting = on


## 場面の調理の道具の煙を、順にずらして「調理中」と「休み」をくり返させる（調理の仕組みができるまでの見せ方）
static func cook_cycle(set_root: Node, on_s := 9.0, off_s := 6.0) -> void:
	var k := 0
	for p in set_root.find_children("Smoke", "GPUParticles3D", true, false):
		if not p.get_meta("cook", false):
			continue
		var t := Timer.new()
		t.one_shot = true
		p.add_child(t)
		var smoke: GPUParticles3D = p
		t.timeout.connect(func() -> void:
			smoke.emitting = not smoke.emitting
			t.start(on_s if smoke.emitting else off_s))
		t.start(0.5 + 3.0 * k)
		k += 1


static func _cook_mark(item: Node) -> Node:
	for c in item.get_children():
		if c.name.begins_with("cook"):
			return c
	return null


## 煙の粒子を parent の at に置く。w は湯気の幅、h は高さ。cooking なら調理中だけ出す（set_cooking・cook_cycle）
static func _smoke(parent: Node, at: Vector3, w: float, h: float, cooking: bool) -> void:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.position = at
	p.set_meta("cook", cooking)
	p.amount = 28
	p.lifetime = 3.2
	p.preprocess = 3.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-w * 3, -w, -w * 3), Vector3(w * 6, h * 2.5 + w * 2, w * 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = w * 0.25
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = h * 0.35
	pm.initial_velocity_max = h * 0.55
	pm.gravity = Vector3(0, h * 0.05, 0)   # 温かい煙は少しずつ上へ
	pm.damping_min = h * 0.05
	pm.damping_max = h * 0.12
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -12.0
	pm.angular_velocity_max = 12.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var grow := Curve.new()   # もくもく: 生まれてすぐふくらみ、上でゆっくり広がる
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(0.25, 1.0))
	grow.add_point(Vector2(1.0, 2.2))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()   # 濃く出て、上で薄れて消える
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.12, Color(1, 1, 1, 0.75))
	fade.add_point(0.5, Color(0.97, 0.96, 0.95, 0.45))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * w * 1.4
	q.material = _smoke_material()
	p.draw_pass_1 = q
	p.emitting = not cooking
	parent.add_child(p)


static func _cook_mark_above(n: Node) -> Node:
	var cur := n.get_parent()
	while cur != null:
		var m := _cook_mark(cur)
		if m != null:
			return m
		cur = cur.get_parent()
	return null


static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat:
		return _smoke_mat
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.proximity_fade_enabled = true   # 物に触れる所で、ふちを溶かす
	m.proximity_fade_distance = 0.3
	m.disable_receive_shadows = true
	m.backlight_enabled = true        # 灯りに透けて明るむ
	m.backlight = Color(0.5, 0.45, 0.4)
	_smoke_mat = m
	return m


## 煙のひとかたまり: ふちの溶けた丸に、雲の雑音で濃淡と、もこもこの輪郭
static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var n := 96
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_octaves = 4
	noise.frequency = 0.045
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length() / (n / 2.0)
			var v := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - smoothstep(0.35 + 0.35 * v, 1.0, d), 0.0, 1.0) * (0.55 + 0.45 * v)
			var c := 0.86 + 0.14 * v
			img.set_pixel(x, y, Color(c, c, c, a))
	_puff = ImageTexture.create_from_image(img)
	return _puff
