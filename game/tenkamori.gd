extends Node3D
## 天下森のワールド（2026-11-09）。横手市増田町の天下森スキー場を、本物の標高で起こした別の世界。
## 2026-11-09 代表「今まで作ってたのをプレーンなデフォルトワールドとして、別のワールドって感じで作ってほしい」
## 同日「ノスタルジーを感じさせる目的でつくるので、ゲレンデから見える景色、つまりコースの逆側の山の作りがかなり重要」
##
## 地形は ../tenkamori/bake_terrain.py が国土地理院の標高タイルから焼いた表（tenkamori/*.bin）。座標は
##   原点 = 第一ペアリフトの乗り場、x = 東、z = 南 (m)。高さ = 標高 - 227.3 m（乗り場の標高）
##   近く（near）: 2 m おき 513 点四方。当たり判定と見た目。ゲレンデの全部と、麓の谷と、まわりの林
##   谷の向かい（mid）: 16 m おき 501 点四方（8 km）。見た目だけ。北東の谷の向こうの山（ゲレンデから見える景色）
##   地平線まで（far）: 96 m おき 401 点四方（38 km）。見た目だけ
## 遠くの山の林は、雪の白・葉の落ちた雑木の灰・杉の濃い帯を、斜面の急さと大きな斑で塗り分ける（PV と YouTube の絵の見え方）。
## ゲレンデの囲い・コース・リフト・ヒュッテの形は OpenStreetMap（tenkamori/map.json）

const Props := preload("res://props.gd")
const TreeHits := preload("res://tree_hits.gd")
const Look := preload("res://look.gd")

const NEAR_X0 := -650.0
const NEAR_Z0 := -150.0
const STEP := 2.0
const N := 513
const NEAR_X1 := NEAR_X0 + (N - 1) * STEP   # 374
const NEAR_Z1 := NEAR_Z0 + (N - 1) * STEP   # 874
const MID_X0 := -3200.0
const MID_Z0 := -4800.0
const MID_STEP := 16.0
const MID_N := 501
const FAR_X0 := -19200.0
const FAR_Z0 := -19200.0
const FAR_STEP := 96.0
const FAR_N := 401

## 始める所: 天下森コースの下の端、リフトの乗り場の少し上（ソリは坂の上の側に置く）
const START := Vector3(-14.0, 0.0, 26.0)
const SEAM_SINK := 40.0     # 細かい地面の下に隠れる粗い地面を、これだけ下げる (m)。16 m おきの粗い地面は、狭い沢で細かい地面より高く出る
const EDGE_FADE := 24.0     # 近くの地面の縁から、粗い地面へ溶かす幅（見た目の吹きだまりを消す）

static var _near := PackedFloat32Array()
static var _map := {}

var world: Node3D
var hits: TreeHits


static func near() -> PackedFloat32Array:
	if _near.is_empty():
		_near = FileAccess.get_file_as_bytes("res://tenkamori/near.bin").to_float32_array()
	return _near


static func map() -> Dictionary:
	if _map.is_empty():
		_map = JSON.parse_string(FileAccess.get_file_as_string("res://tenkamori/map.json"))
	return _map


static func _bin(path: String) -> PackedFloat32Array:
	return FileAccess.get_file_as_bytes(path).to_float32_array()


## 地面の高さ（当たり判定と同じ。近くの表の外は縁の高さを延ばす）
static func lift(x: float, z: float) -> float:
	var h := near()
	var fx := clampf((x - NEAR_X0) / STEP, 0.0, N - 1.001)
	var fz := clampf((z - NEAR_Z0) / STEP, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := j * N + i
	return lerpf(lerpf(h[a], h[a + 1], tx), lerpf(h[a + N], h[a + N + 1], tx), tz)


static func on_ground(x: float, z: float) -> bool:
	return x > NEAR_X0 and x < NEAR_X1 and z > NEAR_Z0 and z < NEAR_Z1


## 地面の端までの距離 (m)。外は負
static func edge_gap(x: float, z: float) -> float:
	return minf(minf(x - NEAR_X0, NEAR_X1 - x), minf(z - NEAR_Z0, NEAR_Z1 - z))


## 見た目の吹きだまりの効き（ゲレンデの中は圧雪で弱く、地面の縁で 0）
static func drift_k(x: float, z: float) -> float:
	return clampf(edge_gap(x, z) / EDGE_FADE, 0.0, 1.0)


static func start_pos() -> Vector3:
	return START


func _ready() -> void:
	var far_snow := _woods_material()
	var snow := Look.snow()
	snow.next_pass = _woods_material(true)   # 林の所は、離れて見ると向かいの山と同じ林の色（足もとは雪の白）
	_make_near(snow)
	_make_coarse("Mid", _bin("res://tenkamori/mid.bin"), MID_X0, MID_Z0, MID_STEP, MID_N, 25, Rect2(NEAR_X0, NEAR_Z0, NEAR_X1 - NEAR_X0, NEAR_Z1 - NEAR_Z0), far_snow)
	_make_coarse("Far", _bin("res://tenkamori/far.bin"), FAR_X0, FAR_Z0, FAR_STEP, FAR_N, 50,
			Rect2(MID_X0, MID_Z0, (MID_N - 1) * MID_STEP, (MID_N - 1) * MID_STEP), far_snow)
	hits = TreeHits.new()
	add_child(hits)
	_trees()
	var lift := preload("res://tenkamori_lift.gd").new()
	lift.name = "Lift"
	add_child(lift)
	preload("res://hutte.gd").place(self)


# ---- 林の塗り分け ------------------------------------------------------------------

## 大きな斑（0〜1）: 向きの違う波を重ねる。近く・向かい・遠くで同じ式なので、継ぎ目で斑がずれない
static func _patch(x: float, z: float) -> float:
	var s := 0.0
	s += sin(x * 0.0071 + z * 0.0043 + 1.3) * 0.32
	s += sin(-x * 0.0052 + z * 0.0089 + 4.1) * 0.26
	s += sin(x * 0.0163 - z * 0.0121 + 2.2) * 0.18
	s += sin(x * 0.0311 + z * 0.0257 + 0.7) * 0.12
	s += sin(-x * 0.061 + z * 0.047 + 5.3) * 0.07
	return clampf(0.5 + s * 0.55, 0.0, 1.0)


## 向かいの山と地平線の林: 頂点の色に林の濃さ（r 杉、g 雑木）を入れ、木立のざらつきはシェーダーで描く
static func _woods(x: float, z: float, slope: float, h: float) -> Color:
	var deg := rad_to_deg(atan(slope))
	var woods := smoothstep(4.0, 11.0, deg)
	var dense := smoothstep(0.32, 0.68, _patch(x, z)) * (1.0 - 0.5 * smoothstep(250.0, 700.0, h))
	var cedar := dense * 0.85 * woods
	return Color(cedar, woods * (1.0 - cedar), 0.0)


const WOODS_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 snow : source_color = vec3(0.97, 0.975, 0.99);
uniform vec3 bare : source_color = vec3(0.70, 0.69, 0.71);
uniform vec3 cedar : source_color = vec3(0.20, 0.27, 0.29);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float scale = 0.0028;     // 画像の 1 枚が 360 m（粒はおよそ 8 m の木立）
varying vec3 wpos;
varying vec4 col;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	col = COLOR;
}
void fragment() {
	float n = texture(grain, wpos.xz * scale).r;
	float n2 = texture(grain, wpos.xz * scale * 0.37 + vec2(0.31, 0.77)).r;
	float c = col.r;
	float ced = smoothstep(1.0 - c - 0.12, 1.0 - c + 0.12, n);      // 濃い所ほど、粒の多くが杉
	float br = col.g * smoothstep(0.25, 0.75, n2) * (0.45 + 0.55 * n);
	vec3 a = mix(snow, bare, br);
	ALBEDO = mix(a, cedar, ced);
	ROUGHNESS = 1.0;
}
"""

## 近くの地面に重ねる林の色: 雪の素材の上に掛け算で重ねる。カメラから 60 m までは掛けない（木の形があり、足もとは雪の白）
const WOODS_OVER := """
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_back, fog_disabled;
uniform vec3 bare : source_color = vec3(0.72, 0.71, 0.73);
uniform vec3 cedar : source_color = vec3(0.21, 0.28, 0.30);
uniform vec3 road_a : source_color = vec3(0.70, 0.70, 0.74);
uniform vec3 road_b : source_color = vec3(0.58, 0.57, 0.60);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float scale = 0.0028;
varying vec3 wpos;
varying vec4 col;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	col = COLOR;
}
void fragment() {
	float n = texture(grain, wpos.xz * scale).r;
	float n2 = texture(grain, wpos.xz * scale * 0.37 + vec2(0.31, 0.77)).r;
	float c = col.r;
	float ced = smoothstep(1.0 - c - 0.12, 1.0 - c + 0.12, n);
	float br = col.g * smoothstep(0.25, 0.75, n2) * (0.45 + 0.55 * n);
	vec3 k = mix(mix(vec3(1.0), bare, br), cedar, ced);
	float fade = smoothstep(60.0, 220.0, length(wpos - CAMERA_POSITION_WORLD));
	// 道と駐車場（頂点の色の b）: 除雪して踏み固めた雪。轍の灰が少しまだらに
	vec3 road = mix(road_a, road_b, smoothstep(0.3, 0.7, texture(grain, wpos.xz * 0.05).r));
	ALBEDO = mix(mix(vec3(1.0), k, fade), road, col.b);
}
"""

static func _woods_material(over := false) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WOODS_OVER if over else WOODS_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	fn.frequency = 0.09
	fn.seed = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = fn
	m.set_shader_parameter("grain", tex)
	return m


# ---- 近くの地面 --------------------------------------------------------------------

## 当たりは 513 点四方 1 枚。見た目は 128 m 四方ずつ（画面の外を描かないように）。高さは焼いた表、吹きだまりは main.gd の drift
func _make_near(snow: Material) -> void:
	var h := near()
	world._add_height_body(h, N, Vector3(NEAR_X0 + (N - 1) * STEP * 0.5, 0, NEAR_Z0 + (N - 1) * STEP * 0.5), STEP)
	var clear := FileAccess.get_file_as_bytes("res://tenkamori/clear.bin")
	var road := FileAccess.get_file_as_bytes("res://tenkamori/road.bin")   # 道と駐車場の濃さ（bake_terrain.py）
	var vs := PackedFloat32Array()
	vs.resize(N * N)
	for j in N:
		var z := NEAR_Z0 + j * STEP
		for i in N:
			var x := NEAR_X0 + i * STEP
			vs[j * N + i] = h[j * N + i] + world.drift(x, z)
	const CHUNK := 64
	var cn := CHUNK + 1
	var ids := _grid_ids(CHUNK)
	var k := 0
	for cj in (N - 1) / CHUNK:
		for ci in (N - 1) / CHUNK:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(cn * cn)
			norms.resize(cn * cn)
			cols.resize(cn * cn)
			for j in cn:
				var gj := cj * CHUNK + j
				for i in cn:
					var gi := ci * CHUNK + i
					var c := gj * N + gi
					var x := NEAR_X0 + gi * STEP
					var z := NEAR_Z0 + gj * STEP
					var l := c - 1 if gi > 0 else c
					var r := c + 1 if gi < N - 1 else c
					var u := c - N if gj > 0 else c
					var d := c + N if gj < N - 1 else c
					var nrm := Vector3((vs[l] - vs[r]) / (STEP * (r - l)), 1.0, (vs[u] - vs[d]) / (STEP * (d - u) / N)).normalized()
					var v := j * cn + i
					verts[v] = Vector3(x, vs[c], z)
					norms[v] = nrm
					var slope := Vector2(nrm.x, nrm.z).length() / maxf(nrm.y, 0.05)
					var cv := clear[clampi(int((z - NEAR_Z0) / 4.0), 0, 255) * 256 + clampi(int((x - NEAR_X0) / 4.0), 0, 255)]
					var wk := smoothstep(4.0, 20.0, float(cv) - 1.0) if cv > 0 else 0.0   # ゲレンデ・道・リフトの下は林でない
					var wc := _woods(x, z, slope, h[c])
					var rd := road[c] / 255.0
					cols[v] = Color(wc.r * wk * (1.0 - rd), wc.g * wk * (1.0 - rd), rd)
			add_child(_mesh("Near%d" % k, verts, norms, cols, ids, snow))
			k += 1


# ---- 粗い地面（見た目だけ） --------------------------------------------------------

## hole の中（細かい地面の下）は SEAM_SINK だけ下げる。縁の 1 マスは下げない（継ぎ目にすき間を作らない）
func _make_coarse(nm: String, h: PackedFloat32Array, x0: float, z0: float, step: float, n: int, chunk: int, hole: Rect2, mat: Material) -> void:
	var inner := hole.grow(-step * 1.5)
	var ids := _grid_ids(chunk)
	var cn := chunk + 1
	var k := 0
	for cj in (n - 1) / chunk:
		for ci in (n - 1) / chunk:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var cols := PackedColorArray()
			verts.resize(cn * cn)
			norms.resize(cn * cn)
			cols.resize(cn * cn)
			var any := false
			for j in cn:
				var gj := cj * chunk + j
				for i in cn:
					var gi := ci * chunk + i
					var c := gj * n + gi
					var x := x0 + gi * step
					var z := z0 + gj * step
					var y := h[c]
					var inside := inner.has_point(Vector2(x, z))
					if inside:
						y -= SEAM_SINK
					else:
						any = true
					var l := c - 1 if gi > 0 else c
					var r := c + 1 if gi < n - 1 else c
					var u := c - n if gj > 0 else c
					var d := c + n if gj < n - 1 else c
					var nrm := Vector3((h[l] - h[r]) / (step * (r - l)), 1.0, (h[u] - h[d]) / (step * (d - u) / n)).normalized()
					var v := j * cn + i
					verts[v] = Vector3(x, y, z)
					norms[v] = nrm
					var slope := Vector2(nrm.x, nrm.z).length() / maxf(nrm.y, 0.05)
					cols[v] = _woods(x, z, slope, y)
			if any:   # 全部が細かい地面の下に隠れる区画は作らない
				var mi := _mesh("%s%d" % [nm, k], verts, norms, cols, ids, mat)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.name = "FarMound%s%d" % [nm, k]   # 名前に mound: 右上の 360° 映像には映さない（main.gd の PIP_SKIP_WORDS）
				add_child(mi)
				k += 1


static func _grid_ids(chunk: int) -> PackedInt32Array:
	var cn := chunk + 1
	var ids := PackedInt32Array()
	ids.resize(chunk * chunk * 6)
	var q := 0
	for j in chunk:
		for i in chunk:
			var a := j * cn + i
			ids[q] = a
			ids[q + 1] = a + 1
			ids[q + 2] = a + cn
			ids[q + 3] = a + cn
			ids[q + 4] = a + 1
			ids[q + 5] = a + cn + 1
			q += 6
	return ids


static func _mesh(nm: String, verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, ids: PackedInt32Array, mat: Material) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = ids
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = am
	mi.material_override = mat
	return mi


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0], p[1]))
	return out


# ---- 林 ----------------------------------------------------------------------------

## フェルトの木（props の glb）。ゲレンデの囲いの縁から 40 m までは 1 本ずつ置いて幹に当たりを付け（滑って突っ込める）、
## その外の林は MultiMesh でまとめて描く（何千本でも重くならないように）。杉の斑の濃い所ほど密に
func _trees() -> void:
	# 杉: とがった 2 つの形だけ（丸い木と小さな木は雑木に見えるので使わない）。色は本物の杉に近い濃い青緑（_cedar）
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb", "res://props/tree_tall.glb", "res://props/tree_zigzag.glb"]
	var clear := FileAccess.get_file_as_bytes("res://tenkamori/clear.bin")   # 4 m おき 256 点四方（bake_terrain.py）
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var near_n := 0
	var bulk := {}   # glb → [Transform3D]
	for path in TREES:
		bulk[path] = []
	for k in 160000:
		if near_n >= 420 and k > 120000:
			break
		var x := rng.randf_range(NEAR_X0 + 6.0, NEAR_X1 - 6.0)
		var z := rng.randf_range(NEAR_Z0 + 6.0, NEAR_Z1 - 6.0)
		var keep := rng.randf()
		var hgt := rng.randf_range(5.0, 11.0)
		var yaw := rng.randf() * TAU
		var path: String = TREES[k % TREES.size()]
		var cv := clear[clampi(int((z - NEAR_Z0) / 4.0), 0, 255) * 256 + clampi(int((x - NEAR_X0) / 4.0), 0, 255)]
		var gap := float(cv) - 1.0   # ゲレンデの囲いからの距離 (m)
		if cv == 0 or gap < 4.0:
			continue
		var y := lift(x, z)
		var gx := lift(x + 2.0, z) - lift(x - 2.0, z)
		var gz := lift(x, z + 2.0) - lift(x, z - 2.0)
		var slope := Vector2(gx, gz).length() * 0.25
		var deg := rad_to_deg(atan(slope))
		var dense := smoothstep(4.0, 11.0, deg) * (0.35 + 0.65 * smoothstep(0.42, 0.58, _patch(x, z)))
		if keep > dense * 0.95 + 0.05:
			continue
		if gap < 40.0:
			if near_n >= 420:
				continue
			var tree := _cedar(Props.make(path))
			tree.scale = Vector3.ONE * hgt / 6.0
			tree.position = Vector3(x, world.foot_y(x, z, 0.35 * hgt / 6.0) - 0.05, z)
			tree.rotation.y = yaw
			add_child(tree)
			hits.add_tree(tree)
			near_n += 1
		else:
			if bulk[path].size() >= 5000:
				continue
			bulk[path].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * hgt / 6.0), Vector3(x, y - 0.3, z)))
	for path in bulk:
		_bulk_trees(path, bulk[path])


## フェルトの木の葉の色を、本物の杉に近い濃い青緑へ（2026-11-09 代表「色は近いものにしましょう」。PV と YouTube の杉は黒に近い緑）。
## 葉の素材（felt_tree_*）にだけ色を掛ける。幹と雪の帽子はそのまま
const CEDAR_LEAF := Color(0.50, 0.58, 0.58)
static var _cedar_mats := {}

static func _cedar(tree: Node3D) -> Node3D:
	for n in tree.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as BaseMaterial3D
			if m == null or not m.resource_name.begins_with("felt_tree"):
				continue
			if not _cedar_mats.has(m):
				var d := m.duplicate() as BaseMaterial3D
				d.albedo_color = m.albedo_color * CEDAR_LEAF
				_cedar_mats[m] = d
			mi.set_surface_override_material(s, _cedar_mats[m])
	return tree


const WOODS_FAR := 420.0   # 林の木（MultiMesh）を描く遠さ (m)。区画のまんなかまでの距離

## 1 種類の木を MultiMesh で。glb の中の形ごとに 1 つずつ（素材はその形の面ごとに付け替えた物を写す）
func _bulk_trees(path: String, xf: Array) -> void:
	if xf.is_empty():
		return
	var proto := _cedar(Props.make(path))
	add_child(proto)   # 形の位置を測るため一度だけ入れる
	for node in proto.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if not mi.visible or mi.mesh == null:
			continue
		var local := proto.global_transform.affine_inverse() * mi.global_transform
		var mesh: Mesh = mi.mesh.duplicate()
		for s in mesh.get_surface_count():
			var m := mi.get_surface_override_material(s)
			if m:
				(mesh as ArrayMesh).surface_set_material(s, m)
		# 128 m 四方の区画ごとに分け、WOODS_FAR より遠い区画は描かない（遠くの林は地面に重ねた林の色で見える）
		var cells := {}
		for q in xf.size():
			var o: Vector3 = (xf[q] as Transform3D).origin
			var key := Vector2i(floori(o.x / 128.0), floori(o.z / 128.0))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(xf[q] * local)
		for key in cells:
			var list: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = list.size()
			for q in list.size():
				mm.set_instance_transform(q, list[q])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Woods_%s_%s_%d_%d" % [path.get_file().get_basename(), mi.name, key.x, key.y]
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mmi.visibility_range_end = WOODS_FAR
			mmi.visibility_range_end_margin = 40.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(mmi)
	proto.queue_free()
