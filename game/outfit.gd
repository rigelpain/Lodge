extends RefCounted
## 服の色。人形の焼いた色の絵（person/<人形>_<人形>_color.png）のうち、染められる部位の所だけを別の色に塗り直す。
## どこがどの部位かは、塗り分けの絵（person/<人形>_dye.png。部位 k の所に k × 60 の値）で引く。
## 塗り分けの絵は Blender の台本で、部品の名前と素材から作る（person/rig_export.py の DYE と dye_mask。人形を焼き直したら作り直す）。
## 明るさのむら（しわ・陰・織り目・毛羽）は元の絵のまま残し、色合いと鮮やかさだけを新しい色にする（明るさは部位のもとの色からの比）。
## 柄のある部位（千代紙・絣・継ぎ当ての柄）は、鮮やかな所だけを塗り直し、白い花や生成りの柄は残す（PARTS の 2 番め）。
## 染めた色は 1 階の人台の桶（dye_vat.gd・dye_ui.gd）で選び、craft.gd の出来事 dye でみんなに配る。
## 着ている人形は、塗り直した絵を GPU で 1 度描いて画像にし、(人形, 色) ごとに取っておく（染めたとき・着替えたときに 1 度だけ）。
## 染め桶の画面の見本は、色を動かすたびに描き直さず、材質（preview_material）で毎フレーム塗り直す。
## 見本の上で部位を指す輪郭と光は、部位の型紙（part_material）をもとに dye_ui.gd が画面の絵に重ねる。人形の材質は光らせない

## 人形ごとの、染められる部位 4 つ [もとの色, 柄を残すか]。0 番が主の色、1〜3 番が 2〜4 番目の色
## （2026-11-03 代表「部位ごとに染めたい」「全キャラフォースカラーまで」。部位の決め方は person/rig_export.py の DYE）
## もとの色は、焼いた色の絵のその部位の、いちばん光の当たる側の色（dye_mask が書き出す「dye base」。柄を残す部位は「sat」の方）。
## 選んだ色がその明るい側に来て、陰の所はそれより暗くなる。人形を焼き直したら測り直す
const PARTS := {
	"kasa": [[Color("558f94"), true], [Color("537bab"), true], [Color("d4a637"), false], [Color("bb6f4f"), true]],   # 緑の着物（桜と青海波）・藍の着物（亀甲）・笠・帯（七宝）
	"origami": [[Color("3c619c"), false], [Color("f8f4ec"), false], [Color("f2eee6"), false], [Color("eee2ca"), false]],   # 青いエプロン・頭巾・上着と袖・裾と靴
	"news": [[Color("707e50"), false], [Color("748453"), false], [Color("67574b"), false], [Color("884d2d"), false]],   # 麻布の上着・頭巾・背負い袋・革ひも
	"robo": [[Color("49898b"), false], [Color("b68b5b"), false], [Color("baa072"), false], [Color("855e3d"), false]],   # 青緑の塗り・段ボール・縄とひも・アンテナの玉とボタン
	"musha": [[Color("2a365d"), false], [Color("35456d"), false], [Color("a13e31"), false], [Color("a6a6a2"), false]],   # 紺・もう 1 つの紺・赤い縅の糸・三日月
	"ningyo": [[Color("a83f3a"), true], [Color("d6ddd0"), false], [Color("5e4d59"), true], [Color("e1d3b8"), false]],   # 茜の裙・月白の上着・藍の刺繍・結びと披帛
	"golem": [[Color("3b4369"), false], [Color("747069"), false], [Color("b89435"), false], [Color("ae8270"), true]],   # 藍の肩当て・腕の灰色・無地の継ぎ当て・柄の継ぎ当て
}
const COUNT := 4               # 部位の数（どの人形も 4 つ）
const STEP := 60.0             # 塗り分けの絵の値の刻み（rig_export.py の DYE_STEP）
const MIN_SAT := 0.25          # 柄を残す部位で、これより鮮やかでない色（白・生成り・灰・黒）は塗り直さない
const CACHE_MAX := 12          # 取っておく絵の数。超えたら忘れる（着ている人形の材質は、自分の絵を持ち続ける）
## 前の保存（部位でなく布で、1〜2 色）の、布 i の色を入れる部位（2026-11-03 までの CLOTH の順）
const LEGACY := {
	"kasa": [[0], [1]], "origami": [[0]], "news": [[0, 1]], "robo": [[0]],
	"musha": [[0, 1], [2]], "ningyo": [[0]], "golem": [[0], [2]],
}
## 一人称の袖（右・左）と脚が、どの部位の布か（-1 は染めない。fp_hands.gd の STYLE）
const FP := {
	"kasa": {"sleeve": [0, 1], "leg": 0},
	"origami": {"sleeve": [2, 2], "leg": 3},
	"news": {"sleeve": [0, 0], "leg": -1},
	"robo": {"sleeve": [1, 1], "leg": 1},
	"musha": {"sleeve": [1, 1], "leg": 1},
	"ningyo": {"sleeve": [1, 1], "leg": 0},
	"golem": {"sleeve": [1, 1], "leg": -1},
}

static var _cache := {}        # "人形|色|色|色|色" → Texture2D
static var _masks := {}        # 人形 → 塗り分けの絵（なければ null）


## 染められる部位がいくつあるか
static func cloth_count(kind: String) -> int:
	return COUNT if PARTS.has(kind) else 0


## 部位 i の、もとの色
static func base_color(kind: String, i: int) -> Color:
	var p: Array = PARTS.get(kind, [])
	return p[i][0] if i < p.size() else Color.WHITE


## 人形 kind の塗り分けの絵（person/<人形>_dye.png）
static func mask(kind: String) -> Texture2D:
	if not _masks.has(kind):
		var path := "res://person/%s_dye.png" % kind
		_masks[kind] = load(path) if ResourceLoader.exists(path) else null
	return _masks[kind]


## 前の保存（布ごとの 1〜2 色）を、部位ごとの 4 色の並びにする。もう 4 色ならそのまま
static func upgrade(kind: String, cols: Array) -> Array:
	if cols.size() == COUNT or cols.is_empty():
		return cols
	var out := []
	out.resize(COUNT)
	out.fill("")
	var map: Array = LEGACY.get(kind, [[0]])
	for i in mini(cols.size(), map.size()):
		for slot in map[i]:
			out[slot] = cols[i]
	return out


## 人形 kind の色の絵 src を、部位ごとの色 cols（Color か null。null の部位はもとのまま）で塗り直した絵。
## 1〜2 コマ待つので await で呼ぶ。描けない（画面なし）ときや、色を替えないときは src のまま
static func dress(host: Node, kind: String, src: Texture2D, cols: Array) -> Texture2D:
	var key := kind
	var any := false
	for i in cloth_count(kind):
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


## 塗り直しの材質（絵を描く方も、見本の方も）に、人形 kind の塗り分けの絵と、部位ごとの色 cols を入れる
static func set_params(m: ShaderMaterial, kind: String, cols: Array) -> void:
	var mk := mask(kind)
	var n := cloth_count(kind) if mk else 0   # 塗り分けの絵がなければ塗らない（どこが部位かわからない）
	m.set_shader_parameter("dye_mask", mk)
	for i in COUNT:
		var on := i < n and i < cols.size() and cols[i] is Color
		m.set_shader_parameter("on%d" % i, on)
		if on:
			m.set_shader_parameter("key%d" % i, base_color(kind, i))
			m.set_shader_parameter("keep%d" % i, bool(PARTS[kind][i][1]))
			m.set_shader_parameter("to%d" % i, cols[i])
	m.set_shader_parameter("min_sat", MIN_SAT)


## glb の人形 body の、色の絵を差し替える。glb の材質は同じ人形のみんなで分け合っているので、写してから替える。
## 材質を置き換えたもの（湿り気の紙の材質など、albedo_tex を持つもの）は、その値を替える
static func put(body: Node3D, tex: Texture2D) -> void:
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if _on_bone(mi, body):   # 骨に付けた物（頭・肩の小物、手に持った物）は人形の服ではない。人形の色の絵を貼らない
			continue
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


## 骨に付けた物（BoneAttachment3D の下）か
static func _on_bone(n: Node, body: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != body:
		if p is BoneAttachment3D:
			return true
		p = p.get_parent()
	return false


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


## 染め桶の画面の、部位の型紙: glb の人形 body を、部位 part のうち見えている所だけ白く、ほかを黒く塗る材質に替える。
## 同じカメラで別に撮り、dye_ui.gd がこの絵から輪郭と光を重ねる。返した材質の part に部位の番号を入れる
static func part_material(body: Node3D, kind: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader("part", PART_SHADER)
	sm.set_shader_parameter("dye_mask", mask(kind))
	for m in body.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, sm)
	return sm


## 1 つの色を、絵と同じ決まりで塗り直す（一人称の袖や脚の布の色。fp_hands.gd）。part は FP の "sleeve" か "leg"、side は袖の右 0・左 1
static func tint(kind: String, part: String, side: int, c: Color, cols: Array) -> Color:
	var f = FP.get(kind, {}).get(part, -1)
	var i: int = f[side] if f is Array else int(f)
	if i < 0 or i >= cols.size() or not cols[i] is Color:
		return c
	var k := base_color(kind, i)
	var w := smoothstep(MIN_SAT * 0.7, MIN_SAT, c.s) if PARTS[kind][i][1] else 1.0
	var t: Color = cols[i]
	return c.lerp(Color.from_hsv(t.h, t.s, clampf(t.v * _lum(c) / maxf(_lum(k), 0.02), 0.0, 1.0)), w)


static func _lum(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


static var _shaders := {}


static func _shader(name: String, body: String) -> Shader:
	if not _shaders.has(name):
		var sh := Shader.new()
		sh.code = body.replace("#SWAP", SWAP)
		_shaders[name] = sh
	return _shaders[name]


## 塗り直しの決まり（絵を描く方と見本の方で同じ）。色は sRGB のまま比べる
const SWAP := """
uniform sampler2D dye_mask : filter_nearest;
uniform bool on0 = false;
uniform bool on1 = false;
uniform bool on2 = false;
uniform bool on3 = false;
uniform vec3 key0;
uniform vec3 key1;
uniform vec3 key2;
uniform vec3 key3;
uniform vec3 to0;
uniform vec3 to1;
uniform vec3 to2;
uniform vec3 to3;
uniform bool keep0 = false;
uniform bool keep1 = false;
uniform bool keep2 = false;
uniform bool keep3 = false;
uniform float min_sat = 0.25;

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

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

// 部位の色を to へ。色合いと鮮やかさは to のまま、明るさだけをもとの色からの比で残す（しわ・陰・織り目・毛羽）。
// keep なら鮮やかでない所（白い柄）は残す
vec3 paint(vec3 c, vec3 key, vec3 to, bool keep) {
	vec3 h = rgb2hsv(c);
	vec3 t = rgb2hsv(to);
	float w = keep ? smoothstep(min_sat * 0.7, min_sat, h.y) : 1.0;
	float v = clamp(t.z * lum(c) / max(lum(key), 0.02), 0.0, 1.0);
	return mix(c, hsv2rgb(vec3(t.x, t.y, v)), w);
}

// 塗り分けの絵の部位の番号（0〜3。染めない所は -1）
int part_at(vec2 uv) {
	return int(round(texture(dye_mask, uv).r * 255.0 / 60.0)) - 1;
}

vec3 dye(vec3 c, int k) {
	if (k == 0 && on0) return paint(c, key0, to0, keep0);
	if (k == 1 && on1) return paint(c, key1, to1, keep1);
	if (k == 2 && on2) return paint(c, key2, to2, keep2);
	if (k == 3 && on3) return paint(c, key3, to3, keep3);
	return c;
}
"""

## 着ている人形の絵を描く（2D の描画は sRGB の空間なので、読んだ色をそのまま比べて、そのまま書く）
const BAKE_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D src : filter_nearest;
#SWAP
void fragment() {
	COLOR = vec4(dye(texture(src, UV).rgb, part_at(UV)), 1.0);
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
	vec3 c = dye(texture(albedo_tex, UV).rgb, part_at(UV));
	ALBEDO = pow(c, vec3(2.2));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
"""

## 部位の型紙（part_material）。光を受けず、部位 part の所が白、ほかが黒
const PART_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform int part = 0;
#SWAP
void fragment() {
	ALBEDO = vec3(part_at(UV) == part ? 1.0 : 0.0);
}
"""
