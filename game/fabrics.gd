extends RefCounted
## 布の色（ソリのメインカラー）。売り子のおじさんが売る布と、ミシンで縫ったソリの色の表。
## ソリの glb（props/build_sled.py）は色を 1 枚の絵に焼いてあるので、絵の中のメインの色（中・小・大は赤いフェルト、
## 米袋はクラフト紙）だけを、明るさの差を残したまま布の色へ置き換える（シェーダーで。ほかの色の部品はそのまま）。
## 色の表はここが正。ソリのメインカラーの仕組み（別の作業）ができたら、そちらの表とここを一つにする。

const ORDER := ["red", "navy", "mustard", "holly", "cream", "plum"]
const COLORS := {
	"red": Color("D2553A"),       # 元のソリの赤（props/common.py の felt_red）
	"navy": Color("34477E"),
	"mustard": Color("D8A43E"),
	"holly": Color("3F6B4A"),
	"cream": Color("EFE6D2"),
	"plum": Color("7A4A6E"),
}
## 絵の中の、置き換えるメインの色（大きさごと）
const MAIN := {"sack": Color("C9A87A"), "small": Color("D2553A"), "mid": Color("D2553A"), "large": Color("D2553A")}

const SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_detail = false;
uniform float detail_scale = 1.6;
uniform vec3 ref_color;      // sRGB
uniform vec3 to_color;       // sRGB
uniform float hue_width = 0.05;
varying vec3 l_pos;
varying vec3 l_nrm;

vec3 hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void vertex() {
	l_pos = VERTEX;
	l_nrm = NORMAL;
}

void fragment() {
	vec3 lin = texture(albedo_tex, UV).rgb;
	vec3 c = pow(lin, vec3(1.0 / 2.2));
	vec3 h = hsv(c);
	vec3 r = hsv(ref_color);
	float dh = abs(h.x - r.x);
	dh = min(dh, 1.0 - dh);
	float w = (1.0 - smoothstep(hue_width, hue_width * 2.2, dh)) * smoothstep(0.12, 0.28, h.y);
	float k = h.z / max(r.z, 0.01);
	vec3 t = clamp(to_color * k, 0.0, 1.0);
	vec3 col = pow(mix(c, t, w), vec3(2.2));
	if (has_detail) {
		vec3 bl = pow(abs(l_nrm), vec3(4.0));
		bl /= (bl.x + bl.y + bl.z);
		vec3 p = l_pos * detail_scale;
		vec3 d = texture(detail_tex, p.yz).rgb * bl.x + texture(detail_tex, p.xz).rgb * bl.y + texture(detail_tex, p.xy).rgb * bl.z;
		col *= d;
	}
	ALBEDO = col;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = 0.95;
	RIM = 0.25;
	RIM_TINT = 0.5;
}
"""

static var _shader: Shader
static var _cache := {}


static func color(fabric: String) -> Color:
	return COLORS.get(fabric, COLORS["red"])


## ソリの見た目（Props.make した glb）のメインの色を、布の色にする。"" や "red" の中・小・大はそのまま
static func tint(root: Node, kind: String, fabric: String) -> void:
	if fabric == "" or (fabric == "red" and kind != "sack"):
		return
	for mi in root.find_children("*_felt", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var src := (mi as MeshInstance3D).get_surface_override_material(i)
			if src == null:
				src = (mi as MeshInstance3D).mesh.surface_get_material(i)
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
				(mi as MeshInstance3D).set_surface_override_material(i, _material(src, kind, fabric))


static func _material(src: BaseMaterial3D, kind: String, fabric: String) -> ShaderMaterial:
	var key := "%s|%s|%s" % [src.albedo_texture.get_instance_id(), kind, fabric]
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("has_normal", true)
	if src.detail_enabled and src.detail_albedo:
		m.set_shader_parameter("detail_tex", src.detail_albedo)
		m.set_shader_parameter("has_detail", true)
		m.set_shader_parameter("detail_scale", src.uv2_scale.x)
	var ref: Color = MAIN.get(kind, COLORS["red"])
	var to := color(fabric)
	m.set_shader_parameter("ref_color", Vector3(ref.r, ref.g, ref.b))
	m.set_shader_parameter("to_color", Vector3(to.r, to.g, to.b))
	m.set_shader_parameter("hue_width", 0.035 if kind == "sack" else 0.05)
	_cache[key] = m
	return m
