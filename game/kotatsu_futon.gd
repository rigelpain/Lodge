extends Node
## 2 階のこたつの布団を、座布団に座った人の側だけめくって膝に掛ける（2026-11-02 代表「ひざにかけるのは追加の布をくっつけるんじゃなくて、
## こたつ布団をめくってかけないと。座った辺のこたつ布団が変形してほしい」）。
## 置いたこたつの組（props/sets/kotatsu_lodge_*.tscn）の子に attach() で足す。組の布団（焼いた素材 felt の面）の素材を、同じ見た目で
## 頂点を曲げるシェーダーに替える。座布団の席（目印 sit_*）に座った人形の lap_line（doll.gd。お腹の前から天板の縁まで、脚の上を通る線）
## ごとに、その席の前に垂れた布団を、天板の縁から膝の上を通ってお腹の前まで持ち上げる。人形の姿勢と同じく 12 コマ／秒で決め直す

const Props := preload("res://props.gd")
## 天板の縁（中心から x と z）と、天板の下の面の高さ（props/build_room.py の kotatsu_lodge を 2 倍したあと。組の座標）
const PLATE := Vector3(1.1688, 0.363, 0.714)
const HANG := 0.64      # 天板の下から、垂れた布団の裾まで (m)
## めくる幅の半分（席のまんなかから辺に沿って）。長い辺の席の間（0.73）の半分まで: 隣の席の前は垂れたまま（2026-11-04 代表「自分が座った両隣もめくれ上がっている」）。
## 隣どうしで座っても、席のあいだで 0 になるので、体の大きさが違っても布団が裂けない。まんなかの 6 割はそっくり、外へ向かってもとの垂れた形へ
const HALF_W := 0.36
const NEAR := 0.3       # 席の目印から人形までがこれより近ければ、その席に座っている（座った人形は目印から 0.03。隣の席までは 0.73）
const FPS := 12.0
const SEATS := 8

var _set: Node3D
var _mats: Array[ShaderMaterial] = []
var _seats := []        # [{mark: Node3D, out: Vector2（外向き、組の xz）, edge: float（中心から天板の縁）, along: float（辺に沿った席のまんなか）}]
var _t := 0.0


static func attach(kotatsu_set: Node3D) -> void:
	var f := new()
	f.name = "KotatsuFuton"
	kotatsu_set.add_child(f)


func _ready() -> void:
	_set = get_parent() as Node3D
	for m in _set.find_children("sit_*", "Node3D", true, false):
		var z := (_set.global_basis.inverse() * (m as Node3D).global_basis.z)
		var out := Vector2(z.x, z.z).normalized()
		var at := _set.to_local((m as Node3D).global_position)
		_seats.append({"mark": m, "out": out, "edge": absf(out.x) * PLATE.x + absf(out.y) * PLATE.z,
			"along": Vector2(at.x, at.z).dot(Vector2(-out.y, out.x))})
	_seats = _seats.slice(0, SEATS)
	for mi in _set.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).get_surface_override_material(i)
			if m == null:
				m = (mi as MeshInstance3D).mesh.surface_get_material(i)
			var b := m as StandardMaterial3D
			if b and b.resource_name.begins_with("felt") and not b.resource_name.begins_with("felt_heat") and b.albedo_texture:
				var s := _material(b)
				(mi as MeshInstance3D).set_surface_override_material(i, s)
				_mats.append(s)
	var side := PackedVector4Array()
	for st in _seats:
		side.append(Vector4(st.out.x, st.out.y, st.edge, 0.0))
	side.resize(SEATS)
	for s in _mats:
		s.set_shader_parameter("seat_side", side)
		s.set_shader_parameter("seat_lap", _empty())


func _process(dt: float) -> void:
	_t += dt
	if _t < 1.0 / FPS or _mats.is_empty():
		return
	_t = 0.0
	var lap := _empty()
	var inv := _set.global_transform.affine_inverse()
	for d in get_tree().get_nodes_in_group("dolls"):
		var line: PackedVector3Array = d.lap_line
		if line.size() < 2 or not (d as Node3D).is_visible_in_tree():
			continue
		for k in _seats.size():
			var st: Dictionary = _seats[k]
			if (st.mark as Node3D).global_position.distance_to((d as Node3D).global_position) > NEAR:
				continue
			# お腹の前（線の始まり）までの、天板の縁から外への距離と、膝の上の高さ（線の前半のいちばん高い所）
			var out: Vector2 = st.out
			var p0 := inv * line[0]
			var reach := Vector2(p0.x, p0.z).dot(out) - float(st.edge)
			var h := 0.0
			for i in line.size() / 2 + 1:
				h = maxf(h, (inv * line[i]).y)
			lap[k] = Vector4(st.along, reach, h, 1.0)
	for s in _mats:
		s.set_shader_parameter("seat_lap", lap)


func _empty() -> PackedVector4Array:
	var a := PackedVector4Array()
	a.resize(SEATS)
	return a


func _material(b: StandardMaterial3D) -> ShaderMaterial:
	var s := ShaderMaterial.new()
	s.shader = _shader()
	s.resource_name = b.resource_name
	s.set_shader_parameter("albedo_tex", b.albedo_texture)
	s.set_shader_parameter("normal_tex", b.normal_texture if b.normal_enabled else null)
	s.set_shader_parameter("detail_albedo", b.detail_albedo)
	s.set_shader_parameter("detail_normal", b.detail_normal)
	s.set_shader_parameter("detail_scale", b.uv2_scale.x)
	s.set_shader_parameter("roughness", b.roughness)
	s.set_shader_parameter("rim", b.rim if b.rim_enabled else 0.0)
	s.set_shader_parameter("rim_tint", b.rim_tint)
	s.set_shader_parameter("plate_y", PLATE.y)
	s.set_shader_parameter("hang", HANG)
	s.set_shader_parameter("half_w", HALF_W)
	return s


static var _sh: Shader


static func _shader() -> Shader:
	if _sh == null:
		_sh = Shader.new()
		_sh.code = SHADER
	return _sh


## 見た目は props.gd の material_for（焼いた色・凹凸、写真の細部を 3 方向から、ふちの毛羽）と同じ。
## 頂点: 席ごとに、その辺の外へ垂れた布団の頂点を、天板の下から垂れた長さ（u）で、天板の縁 → 膝の上 → お腹の前の曲線に移す。
## 布の厚み（辺から外への離れ）は曲線の外向きへ。席のまんなかから辺に沿って離れるほど、もとの垂れた形に戻す。
## しわの所は曲げると面が裏返るので、両面を描く（片面だと裏返った面が消えて、穴の底が透ける）
const SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 1.6;
uniform float roughness = 0.95;
uniform float rim = 0.25;
uniform float rim_tint = 0.5;
uniform vec4 seat_lap[8];    // x: 辺に沿った席のまんなか, y: 天板の縁からお腹の前まで, z: 膝の上の高さ, w: 座っている（0 か 1）
uniform vec4 seat_side[8];   // xy: 辺の外向き（xz）, z: 中心から天板の縁まで
uniform float plate_y = 0.363;
uniform float hang = 0.64;
uniform float half_w = 0.36;

varying vec3 v_tri_w;
varying vec3 v_tri_p;

vec4 triplanar(sampler2D s, vec3 p, vec3 w) {
	return texture(s, p.zy * vec2(-1.0, 1.0)) * w.x + texture(s, p.xz) * w.y + texture(s, p.xy) * w.z;
}

void vertex() {
	vec3 v0 = VERTEX;
	vec3 w = abs(NORMAL);
	v_tri_w = w / (w.x + w.y + w.z);
	v_tri_p = v0 * detail_scale * vec3(1.0, -1.0, 1.0);   // 写真の細部は布に付いたまま
	float best = 0.0;
	vec3 pos = v0;
	vec3 nrm = NORMAL;
	for (int i = 0; i < 8; i++) {
		vec4 L = seat_lap[i];
		if (L.w <= 0.0) {
			continue;
		}
		vec2 n = seat_side[i].xy;
		float d = dot(v0.xz, n) - seat_side[i].z;
		float a = dot(v0.xz, vec2(-n.y, n.x)) - L.x;
		// 垂れた布団だけ（座布団は天板の縁から 0.31 外、穴の底のフェルトは畳から -0.38 より下、みかんは天板の上）
		if (d < -0.05 || d > 0.2 || v0.y > plate_y + 0.005 || v0.y < -0.35) {
			continue;
		}
		float wgt = L.w * (1.0 - smoothstep(half_w * 0.6, half_w, abs(a))) * smoothstep(-0.05, 0.0, d)
				* (1.0 - smoothstep(0.14, 0.2, d)) * smoothstep(-0.35, -0.3, v0.y);
		if (wgt <= best) {
			continue;
		}
		float u = clamp((plate_y - v0.y) / hang, 0.0, 1.0);
		vec2 pe = vec2(0.0, plate_y);    // 天板の縁
		vec2 pk = vec2(L.y, L.z);        // お腹の前
		vec2 pc = vec2(L.y * 0.35, L.z); // 膝の上へ向かう
		vec2 B = mix(mix(pe, pc, u), mix(pc, pk, u), u);
		vec2 T = normalize(2.0 * (1.0 - u) * (pc - pe) + 2.0 * u * (pk - pc) + vec2(0.0, -1e-4));
		vec2 N = vec2(-T.y, T.x);   // 垂れた布の外向き（辺の外）が、曲線では上を向く
		vec2 q = B + N * clamp(d, 0.0, 0.06);
		vec3 p = v0;
		p.xz += n * (q.x + seat_side[i].z - dot(v0.xz, n));
		p.y = q.y;
		// 法線も、垂れた向き（真下）から曲線の向き T へ回す
		float c = -T.y;
		float s = T.x;
		float nn = dot(NORMAL.xz, n);
		vec3 nr = NORMAL;
		nr.xz += n * ((nn * c - NORMAL.y * s) - nn);
		nr.y = nn * s + NORMAL.y * c;
		best = wgt;
		pos = mix(v0, p, wgt);
		nrm = normalize(mix(NORMAL, nr, wgt));
	}
	VERTEX = pos;
	NORMAL = nrm;
}

void fragment() {
	vec4 d = triplanar(detail_albedo, v_tri_p, v_tri_w);
	vec3 a = texture(albedo_tex, UV).rgb;
	ALBEDO = mix(a, a * d.rgb, d.a);
	NORMAL_MAP = mix(texture(normal_tex, UV).rgb, triplanar(detail_normal, v_tri_p, v_tri_w).rgb, d.a);
	ROUGHNESS = roughness;
	RIM = rim;
	RIM_TINT = rim_tint;
}
"""
