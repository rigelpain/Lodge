extends RefCounted
## 服の色。人形の焼いた色の絵（person/<人形>_<人形>_color.png）のうち、服の布の色の所だけを別の色に塗り直す。
## 絵は部品ごとに細かく散らばっているので、所ではなく色で見分ける: 布ごとに「焼いてある色」（CLOTH）を決め、
## 色相がそれに近く、鮮やかな所だけを差し替える。白い花や生成りの柄・黒い髪・肌は鮮やかでないので残る。
## 明るさのむら（しわ・陰・織り目）は元の絵のまま残し、色相と鮮やかさだけを新しい色に寄せる（props.gd の recolor と同じ考え）。
## 染めた色は 2 階の染め桶（dye_vat.gd・dye_ui.gd）で選び、craft.gd の出来事 dye でみんなに配る。
## 着ている人形は、塗り直した絵を GPU で 1 度描いて画像にし、(人形, 色) ごとに取っておく（染めたとき・着替えたときに 1 度だけ）。
## 染め桶の画面の見本は、色を動かすたびに描き直さず、材質（preview_material）で毎フレーム塗り直す

## 人形ごとの服の布 [焼いてある色, 色相の幅（度）]。0 番が 1 枚めの布、1 番があれば 2 枚めの布
## （2026-11-01 代表: 布が 2 つある人形は 2 枚めの布まで染められる）
const CLOTH := {
	"kasa": [[Color("335f60"), 22.0], [Color("29476b"), 12.0]],   # 緑の着物（千代紙の柄ごと）・藍の着物
	"origami": [[Color("2f4b79"), 16.0]],                          # 青いエプロン
	"news": [[Color("586440"), 16.0]],                             # 麻布の頭巾と上着
	"robo": [[Color("3a6c6d"), 16.0]],                             # 青緑に塗った箱
	"musha": [[Color("1b2339"), 16.0], [Color("62261e"), 12.0]],   # 紺のフェルトの兜と鎧・赤い縅の糸
	"ningyo": [[Color("843733"), 13.0]],                           # 茜の裙（赤い飾りもいっしょに）
	"golem": [[Color("242f46"), 16.0], [Color("3e261c"), 12.0]],   # 藍の継ぎ当て・茶の継ぎ当て
}
const MIN_SAT := 0.25          # これより鮮やかでない色（白・生成り・灰・黒）は塗り直さない
const CACHE_MAX := 12          # 取っておく絵の数。超えたら忘れる（着ている人形の材質は、自分の絵を持ち続ける）

static var _cache := {}        # "人形|色|色" → Texture2D


## 服の布がいくつあるか
static func cloth_count(kind: String) -> int:
	return CLOTH.get(kind, []).size()


## 服の布の、もとの色（i 番）
static func base_color(kind: String, i: int) -> Color:
	var c: Array = CLOTH.get(kind, [])
	return c[i][0] if i < c.size() else Color.WHITE


## 人形 kind の色の絵 src を、布ごとの色 cols（Color か null。null の布はもとのまま）で塗り直した絵。
## 1〜2 コマ待つので await で呼ぶ。描けない（画面なし）ときや、色を替えないときは src のまま
static func dress(host: Node, kind: String, src: Texture2D, cols: Array) -> Texture2D:
	var cloth: Array = CLOTH.get(kind, [])
	var key := kind
	var any := false
	for i in cloth.size():
		var c = cols[i] if i < cols.size() else null
		key += "|" + ((c as Color).to_html(false) if c is Color else "-")
		any = any or c is Color
	if not any or src == null or DisplayServer.get_name() == "headless":
		return src
	if _cache.has(key):
		return _cache[key]
	var size := src.get_size()
	var vp := SubViewport.new()
	vp.size = Vector2i(size)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = size
	var sm := ShaderMaterial.new()
	sm.shader = _shader("bake", BAKE_SHADER)
	sm.set_shader_parameter("src", src)
	set_params(sm, kind, cols)
	rect.material = sm
	vp.add_child(rect)
	var tree := host.get_tree()
	tree.root.add_child.call_deferred(vp)   # 人形が _ready の途中でも置けるように
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if _cache.has(key):   # 待つあいだに、ほかの人形が同じ色を描き終えた
		return _cache[key]
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	_cache[key] = tex
	return tex


## 人形 doll（doll.gd）の glb の body を、塗り直した絵に替える。描き終わるまでに人形が消えた・次の着替えが来た（n が古い）なら替えない
static func dress_into(doll: Node, body: Node3D, kind: String, src: Texture2D, cols: Array, n: int) -> void:
	var tex: Texture2D = await dress(doll, kind, src, cols)
	if is_instance_valid(doll) and is_instance_valid(body) and doll.is_inside_tree() and int(doll.get("_dress_n")) == n:
		put(body, tex)


## 塗り直しの材質（絵を描く方も、見本の方も）に、人形 kind の布ごとの色 cols を入れる
static func set_params(m: ShaderMaterial, kind: String, cols: Array) -> void:
	var cloth: Array = CLOTH.get(kind, [])
	for i in 2:
		var on := i < cloth.size() and i < cols.size() and cols[i] is Color
		m.set_shader_parameter("on%d" % i, on)
		if on:
			m.set_shader_parameter("key%d" % i, cloth[i][0])
			m.set_shader_parameter("width%d" % i, cloth[i][1] / 360.0)
			m.set_shader_parameter("to%d" % i, cols[i])
	m.set_shader_parameter("min_sat", MIN_SAT)


## glb の人形 body の、色の絵を差し替える。glb の材質は同じ人形のみんなで分け合っているので、写してから替える。
## 材質を置き換えたもの（湿り気の紙の材質など、albedo_tex を持つもの）は、その値を替える
static func put(body: Node3D, tex: Texture2D) -> void:
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is ShaderMaterial:
				if (mat as ShaderMaterial).get_shader_parameter("albedo_tex") is Texture2D:
					(mat as ShaderMaterial).set_shader_parameter("albedo_tex", tex)
			elif mat is StandardMaterial3D:
				if mi.get_surface_override_material(s) != mat:
					mat = mat.duplicate()
					mi.set_surface_override_material(s, mat)
				(mat as StandardMaterial3D).albedo_texture = tex


## glb の人形 body のいまの色の絵
static func albedo(body: Node3D) -> Texture2D:
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				return (mat as StandardMaterial3D).albedo_texture
			if mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("albedo_tex") is Texture2D:
				return (mat as ShaderMaterial).get_shader_parameter("albedo_tex")
	return null


## 写した材質を外す（人形が消える前に。先に材質が消えて、描く側が消えた材質を引いてエラーになるのを防ぐ）
static func strip(body: Node3D) -> void:
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.get_surface_override_material_count():
			if mi.get_surface_override_material(s) != null:
				mi.set_surface_override_material(s, null)


## 染め桶の画面の見本: glb の人形 body の材質を、色をその場で塗り直す材質に替える。返した材質に set_params で色を入れる
static func preview_material(body: Node3D) -> ShaderMaterial:
	var src: StandardMaterial3D
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			if mi.get_active_material(s) is StandardMaterial3D:
				src = mi.get_active_material(s)
	var sm := ShaderMaterial.new()
	sm.shader = _shader("preview", PREVIEW_SHADER)
	if src:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		sm.set_shader_parameter("normal_tex", src.normal_texture)
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, sm)
	return sm


## 1 つの色を、絵と同じ決まりで塗り直す（一人称の袖や脚の布の色。fp_hands.gd）。どの布にも当たらなければそのまま
static func tint(kind: String, c: Color, cols: Array) -> Color:
	var cloth: Array = CLOTH.get(kind, [])
	var o := c
	for i in cloth.size():
		if i >= cols.size() or not cols[i] is Color:
			continue
		var k: Color = cloth[i][0]
		var t: Color = cols[i]
		var dh := absf(c.h - k.h)
		dh = minf(dh, 1.0 - dh)
		var width: float = cloth[i][1] / 360.0
		var w := (1.0 - smoothstep(width * 0.7, width, dh)) * smoothstep(MIN_SAT * 0.7, MIN_SAT, c.s)
		var to := Color.from_hsv(t.h, clampf(c.s * t.s / maxf(k.s, 1e-3), 0.0, 1.0), clampf(c.v * t.v / maxf(k.v, 1e-3), 0.0, 1.0))
		o = o.lerp(to, w)
	return o


static var _shaders := {}


static func _shader(name: String, body: String) -> Shader:
	if not _shaders.has(name):
		var sh := Shader.new()
		sh.code = body.replace("#SWAP", SWAP)
		_shaders[name] = sh
	return _shaders[name]


## 塗り直しの決まり（絵を描く方と見本の方で同じ）。色は sRGB のまま比べる
const SWAP := """
uniform bool on0 = false;
uniform bool on1 = false;
uniform vec3 key0;
uniform vec3 key1;
uniform vec3 to0;
uniform vec3 to1;
uniform float width0 = 0.05;
uniform float width1 = 0.05;
uniform float min_sat = 0.25;

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

// key に近い色を to へ。明るさと鮮やかさは key からの比で残す（しわ・陰・織り目・柄の濃淡）
vec3 swap(vec3 c, vec3 h, vec3 key, vec3 to, float width) {
	vec3 k = rgb2hsv(key);
	vec3 t = rgb2hsv(to);
	float dh = abs(h.x - k.x);
	dh = min(dh, 1.0 - dh);
	float w = (1.0 - smoothstep(width * 0.7, width, dh)) * smoothstep(min_sat * 0.7, min_sat, h.y);
	float sat = clamp(h.y * t.y / max(k.y, 1e-3), 0.0, 1.0);
	float val = clamp(h.z * t.z / max(k.z, 1e-3), 0.0, 1.0);
	return mix(c, hsv2rgb(vec3(t.x, sat, val)), w);
}

vec3 dye(vec3 c) {
	vec3 h = rgb2hsv(c);
	vec3 o = c;
	if (on0) o = swap(o, h, key0, to0, width0);
	if (on1) o = swap(o, h, key1, to1, width1);
	return o;
}
"""

## 着ている人形の絵を描く（2D の描画は sRGB の空間なので、読んだ色をそのまま比べて、そのまま書く）
const BAKE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_nearest;
#SWAP
void fragment() {
	COLOR = vec4(dye(texture(src, UV).rgb), 1.0);
}
"""

## 染め桶の画面の見本（焼いた人形の材質と同じ: 粗さ 0.9・両面。色の絵は sRGB のまま読んで塗り直し、明るさの空間に直す）
const PREVIEW_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
#SWAP
void fragment() {
	vec3 c = dye(texture(albedo_tex, UV).rgb);
	ALBEDO = pow(c, vec3(2.2));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
"""
