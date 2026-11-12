extends Node3D
## 本物の地形のワールド（天下森・旭ヶ丘。どの場所かは site。use() で選ぶ）。
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

## どの場所か（2026-11-11: 倶知安町の旭ヶ丘スキー場を足し、このスクリプトを本物の地形のワールドの共通にした）。
## main.gd が stage を決めたら use() で選ぶ。焼いた表は res://<場所>/ にあり、格子の取り方は場所ごと（SITES）
const SITES := {
	"tenkamori": {"near": [-650.0, -150.0, 2.0, 513], "mid": [-3200.0, -4800.0, 16.0, 501], "far": [-19200.0, -19200.0, 96.0, 401],
		"cedar": 0.85, "fog": 0.00018},
	# 旭ヶ丘: 原点はペアリフトの乗り場。南南東 10 km の羊蹄山が景色の主役なので、谷の向かい（mid）を南東へ広く（24 m おき 16 km）とる。
	# 林は杉の植林でなく、葉の落ちた広葉樹が多い（北海道の低い山）。霧は羊蹄山が霞みすぎないよう薄く
	"asahigaoka": {"near": [-600.0, -650.0, 2.0, 513], "mid": [-4400.0, -2400.0, 24.0, 676], "far": [-19200.0, -19200.0, 96.0, 401],
		"cedar": 0.45, "fog": 0.00004, "glide": 0.25, "pull": 0.4, "bumps": 1.0, "rattle": 0.75,   # 0.75: 代表が「いい感じ」と言ったときの揺れ（そのときは設定の視点の揺れが切れていて 2.5 × 0.3 だった）   # 2026-11-12 代表「もっと視界ガクガク揺れていいし、ソリは少しの隆起でもう少し跳ねて良い。まだあんまり恐怖を感じない」
		   # ソリが速い（sled.gd の glide・pull。そりコースで時速 72 km、主コースで 91 km）
		"treeline": [700.0, 1150.0], "woods_above": [110.0, 200.0], "bare": Color(0.46, 0.45, 0.50)},   # 森林限界は標高 900〜1350 m（高さは標高 − 193 m）
}
static var site := "tenkamori"
static var NEAR_X0 := -650.0
static var NEAR_Z0 := -150.0
const STEP := 2.0
const N := 513
static var NEAR_X1 := NEAR_X0 + (N - 1) * STEP
static var NEAR_Z1 := NEAR_Z0 + (N - 1) * STEP
static var MID_X0 := -3200.0
static var MID_Z0 := -4800.0
static var MID_STEP := 16.0
static var MID_N := 501
static var FAR_X0 := -19200.0
static var FAR_Z0 := -19200.0
static var FAR_STEP := 96.0
static var FAR_N := 401


## 場所を選ぶ（表を読み直す）。近くの格子は 2 m おき 513 点四方でそろえる（当たり判定と見た目の区画の作りが同じなので）
static func use(name: String) -> void:
	if name == site and not _near.is_empty():
		return
	site = name
	var g: Dictionary = SITES[name]
	NEAR_X0 = g.near[0]
	NEAR_Z0 = g.near[1]
	NEAR_X1 = NEAR_X0 + (N - 1) * STEP
	NEAR_Z1 = NEAR_Z0 + (N - 1) * STEP
	MID_X0 = g.mid[0]
	MID_Z0 = g.mid[1]
	MID_STEP = g.mid[2]
	MID_N = g.mid[3]
	FAR_X0 = g.far[0]
	FAR_Z0 = g.far[1]
	FAR_STEP = g.far[2]
	FAR_N = g.far[3]
	_near = PackedFloat32Array()
	_map = {}


## 焼いた表のありか
static func res(file: String) -> String:
	return "res://%s/%s" % [site, file]


const SEAM_SINK := 40.0     # 細かい地面の下に隠れる粗い地面を、これだけ下げる (m)。16 m おきの粗い地面は、狭い沢で細かい地面より高く出る
const EDGE_FADE := 24.0     # 近くの地面の縁から、粗い地面へ溶かす幅（見た目の吹きだまりを消す）

static var _near := PackedFloat32Array()
static var _map := {}

var world: Node3D
var hits: TreeHits


static func near() -> PackedFloat32Array:
	if _near.is_empty():
		_near = FileAccess.get_file_as_bytes(res("near.bin")).to_float32_array()
	return _near


static func map() -> Dictionary:
	if _map.is_empty():
		_map = JSON.parse_string(FileAccess.get_file_as_string(res("map.json")))
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
	if site != "tenkamori":   # ほかの場所: 焼いたときに決めた始める所（map.json の start）
		var st: Array = map().get("start", [0.0, 0.0])
		return Vector3(st[0], 0.0, st[1])
	var f: Vector2 = preload("res://hutte.gd").front_spot()
	return Vector3(f.x, 0.0, f.y)


## 始めたときに向く所（天下森: ヒュッテの入口の妻。ほかの場所: map.json の look）
static func start_look() -> Vector3:
	if site != "tenkamori":
		var lk: Array = map().get("look", [0.0, 0.0])
		return Vector3(lk[0], lift(lk[0], lk[1]) + 3.0, lk[1])
	var H := preload("res://hutte.gd")
	var f: Vector2 = H.to_world(0.0, -H.VEST_V)
	return Vector3(f.x, lift(f.x, f.y) + 3.0, f.y)


func _ready() -> void:
	var far_snow := _woods_material()
	var snow := Look.snow()
	snow.next_pass = _woods_material(true)   # 林の所は、離れて見ると向かいの山と同じ林の色（足もとは雪の白）
	_make_near(snow)
	_make_coarse("Mid", _bin(res("mid.bin")), MID_X0, MID_Z0, MID_STEP, MID_N, 25, Rect2(NEAR_X0, NEAR_Z0, NEAR_X1 - NEAR_X0, NEAR_Z1 - NEAR_Z0), far_snow)
	_make_coarse("Far", _bin(res("far.bin")), FAR_X0, FAR_Z0, FAR_STEP, FAR_N, 50,
			Rect2(MID_X0, MID_Z0, (MID_N - 1) * MID_STEP, (MID_N - 1) * MID_STEP), far_snow)
	hits = TreeHits.new()   # 林の外（区画に入らない木）用の 1 つ。林の木は区画ごとの体（_hit_cells）
	add_child(hits)
	_trees()
	for cell in _hit_cells:   # 形を全部足してから世界に入れる（入ったあとに 1 つずつ足すと、そのたびに組み直しになる）
		add_child(_hit_cells[cell])
	var lift := preload("res://tenkamori_lift.gd").new()
	lift.name = "Lift"
	add_child(lift)
	if site == "asahigaoka":   # 旭ヶ丘: ゲレンデの小物（asahi_slope.gd）と休憩所「雪ん子館」（asahi_lodge.gd）
		for part in ["Slope", "Lodge"]:
			var path := "res://asahi_%s.gd" % part.to_lower()
			if ResourceLoader.exists(path):
				var n: Node3D = load(path).new()
				n.name = part
				n.set("world", world)
				add_child(n)
	if site != "tenkamori":
		return
	preload("res://hutte.gd").place(self)
	var slope := preload("res://tenkamori_slope.gd").new()   # ゲレンデの作り込み（ネット・柱のマット・照明・小屋）
	slope.name = "Slope"
	slope.world = world
	add_child(slope)


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
	var hi: Array = SITES[site].get("woods_above", [])
	if not hi.is_empty():   # 平野（町と畑）より高い所は、なだらかでも林（羊蹄山の裾）
		woods = maxf(woods, smoothstep(float(hi[0]), float(hi[1]), h))
	var tl: Array = SITES[site].get("treeline", [])
	if not tl.is_empty():   # 森林限界（羊蹄山）: ここから上は木が無く、雪の白だけ
		woods *= 1.0 - smoothstep(float(tl[0]), float(tl[1]), h)
	var dense := smoothstep(0.32, 0.68, _patch(x, z)) * (1.0 - 0.5 * smoothstep(250.0, 700.0, h))
	var cedar := dense * float(SITES[site].cedar) * woods
	return Color(cedar, woods * (1.0 - cedar), 0.0)


const WOODS_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 snow : source_color = vec3(0.97, 0.975, 0.99);
uniform vec3 bare : source_color = vec3(0.70, 0.69, 0.71);
uniform vec3 cedar : source_color = vec3(0.20, 0.27, 0.29);
uniform sampler2D grain : filter_linear_mipmap, repeat_enable;
uniform float bare_k = 1.0;       // 雑木の濃さ（旭ヶ丘: 遠い羊蹄山の裾でも林の帯が見えるよう強める）
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
	float br = clamp(col.g * smoothstep(0.25, 0.75, n2) * (0.45 + 0.55 * n) * bare_k, 0.0, 1.0);
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
varying vec3 wnrm;
varying vec4 col;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col = COLOR;
}
void fragment() {
	float n = texture(grain, wpos.xz * scale).r;
	float n2 = texture(grain, wpos.xz * scale * 0.37 + vec2(0.31, 0.77)).r;
	float c = col.r;
	float ced = smoothstep(1.0 - c - 0.12, 1.0 - c + 0.12, n);
	float br = col.g * smoothstep(0.25, 0.75, n2) * (0.45 + 0.55 * n);
	vec3 k = mix(mix(vec3(1.0), bare, br), cedar, ced);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float fade = smoothstep(60.0, 220.0, dist);
	// ゲレンデ（頂点の色の a）: 圧雪車の筋。斜面を下る向きに細い畝（25 cm おき）と、5 m 幅の通り道の境のかすかな線。近くだけ（遠くはちらつくので消す）
	vec2 down = -wnrm.xz;
	float steep = length(down);
	if (col.a > 0.01 && steep > 0.03) {
		down /= steep;
		float across = dot(wpos.xz, vec2(-down.y, down.x));
		float rib = 0.5 + 0.5 * sin(across * 6.2832 / 0.25);
		float lane = smoothstep(0.92, 1.0, abs(fract(across / 5.0) * 2.0 - 1.0));
		float near_k = 1.0 - smoothstep(12.0, 45.0, dist);
		k *= 1.0 - col.a * (rib * 0.07 * near_k + lane * 0.06 * (1.0 - smoothstep(40.0, 120.0, dist)));
	}
	// 道と駐車場（頂点の色の b）: 除雪して踏み固めた雪。轍の灰が少しまだらに
	vec3 road = mix(road_a, road_b, smoothstep(0.3, 0.7, texture(grain, wpos.xz * 0.05).r));
	ALBEDO = mix(mix(vec3(1.0), k, fade), road, col.b);
	// 圧雪の筋は、林の色が溶けて出る遠さより手前だけ（k をそのまま使う所）
	if (col.a > 0.01) { ALBEDO = mix(k, road, col.b); }
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
	if SITES[site].has("bare") and not over:   # 遠くの雑木の色（旭ヶ丘: 羊蹄山の裾の葉の落ちた林が、10 km 先でも帯に見えるよう濃いめ）
		m.set_shader_parameter("bare", SITES[site].bare)
		m.set_shader_parameter("bare_k", 2.4)
	return m


# ---- 近くの地面 --------------------------------------------------------------------

## 当たりは 513 点四方 1 枚。見た目は 128 m 四方ずつ（画面の外を描かないように）。高さは焼いた表、吹きだまりは main.gd の drift
func _make_near(snow: Material) -> void:
	var h := near()
	world._add_height_body(h, N, Vector3(NEAR_X0 + (N - 1) * STEP * 0.5, 0, NEAR_Z0 + (N - 1) * STEP * 0.5), STEP)
	var clear := FileAccess.get_file_as_bytes(res("clear.bin"))
	var road := FileAccess.get_file_as_bytes(res("road.bin"))   # 道と駐車場の濃さ（bake_terrain.py）
	var piste := FileAccess.get_file_as_bytes(res("piste.bin"))   # ゲレンデの雪面の濃さ（圧雪の筋を描く所）
	var forest := FileAccess.get_file_as_bytes(res("forest.bin"))   # 空中写真の林（4 m おき）
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
					var wk := 1.0 if cv > 0 else 0.0   # ゲレンデ・道・リフトの下は林でない
					var fo := forest[clampi(int((z - NEAR_Z0) / 4.0), 0, 255) * 256 + clampi(int((x - NEAR_X0) / 4.0), 0, 255)] / 255.0   # 空中写真の林
					var wc := Color(fo * float(SITES[site].cedar) * 1.06, (1.0 - fo) * 0.25 * smoothstep(4.0, 11.0, rad_to_deg(atan(slope))), 0.0)
					var rd := road[c] / 255.0
					cols[v] = Color(wc.r * wk * (1.0 - rd), wc.g * wk * (1.0 - rd), rd, piste[c] / 255.0)
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
	# 杉: とがった 2 つの形だけ（丸い木と小さな木は雑木に見えるので使わない）。色は本物の杉に近い濃い青緑（_cedar）。
	# 立てる所は空中写真の林（forest.bin。2026-11-09 動画では林間コースもゲレンデの縁も杉の壁）。4.5 m おきの格子をずらして、林の濃さの割合で立てる。
	# 見た目は全部 MultiMesh（何千本でも軽い）。開けた所（ゲレンデ・林間コース・道）から 12 m までの木には幹の当たりを付ける（滑って突っ込める）
	const TREES := ["res://props/tree_tall.glb", "res://props/tree_zigzag.glb"]
	const GAP := 4.5
	var clear := FileAccess.get_file_as_bytes(res("clear.bin"))   # 4 m おき 256 点四方（bake_terrain.py）
	var forest := FileAccess.get_file_as_bytes(res("forest.bin"))
	var cell := func(x: float, z: float) -> int:
		return clampi(int((z - NEAR_Z0) / 4.0), 0, 255) * 256 + clampi(int((x - NEAR_X0) / 4.0), 0, 255)
	var open := func(x: float, z: float) -> bool:
		var c: int = cell.call(x, z)
		return clear[c] == 0 or forest[c] < 80
	var conifer := float(SITES[site].cedar) / 0.85   # 林のうち針葉樹の割合（旭ヶ丘は葉の落ちた広葉樹が多く、その分は地面の林の灰で見せる）
	var bare := site == "asahigaoka"   # 旭ヶ丘: 葉の落ちた木（BARE）を主に、針葉樹は少しだけ
	if bare:
		conifer = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var bulk := {}
	for path in TREES:
		bulk[path] = []
		var proto := Props.make(path)   # 幹の太さと木の高さを一度だけ測る（tree_hits.gd）
		TreeHits._sizes[path] = TreeHits._measure(proto)
		proto.free()
	if bare:
		for path in BARE:
			bulk[path] = []
			TreeHits._sizes[path] = Vector2(BARE[path][1], BARE[path][0])   # 幹は木の組（*_wood）でないので、太さと高さは台本の値
	var gap := 3.7 if bare else GAP   # 葉の落ちた木は細いので、林に見えるよう少し詰める
	var x := NEAR_X0 + 6.0
	while x < NEAR_X1 - 6.0:
		var z := NEAR_Z0 + 6.0
		while z < NEAR_Z1 - 6.0:
			var px := x + rng.randf_range(-1.8, 1.8)
			var pz := z + rng.randf_range(-1.8, 1.8)
			var keep := rng.randf()
			var hgt := rng.randf_range(9.0, 16.0)
			var yaw := rng.randf() * TAU
			var path: String = TREES[rng.randi() % TREES.size()]
			var c: int = cell.call(px, pz)
			z += gap
			if clear[c] == 0 or keep * 255.0 > forest[c] * conifer or bulk[path].size() >= 40000:
				continue
			var y := lift(px, pz)
			var edge := false
			for o in [Vector2(12, 0), Vector2(-12, 0), Vector2(0, 12), Vector2(0, -12), Vector2(8, 8), Vector2(-8, 8), Vector2(8, -8), Vector2(-8, -8)]:
				if open.call(px + o.x, pz + o.y):
					edge = true
					break
			var model_h := 6.0
			if bare:
				# どの木か: 開けた所の縁はシラカバが多い（コースの縁の白い幹の壁）。大きな斑の濃い所はカラマツの林、ほかは雑木。針葉樹は 7%
				var u := fposmod(sin(px * 12.9898 + pz * 78.233) * 43758.5453, 1.0)
				var u2 := fposmod(sin(px * 39.3468 + pz * 11.135) * 24634.6345, 1.0)
				if u > 0.97:
					pass   # フェルトの針葉樹のまま
				elif edge and u < 0.55:
					path = BARE_KABA
				elif _patch(px * 2.0, pz * 2.0) > 0.52:
					path = BARE_KARA
				else:
					path = BARE_ZOKI
				if BARE.has(path):
					model_h = BARE[path][0]
					hgt = lerpf(BARE[path][2], BARE[path][3], u2)
			bulk[path].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * hgt / model_h), Vector3(px, y - 0.3, pz)))
			if edge or ALL_TRUNKS:   # 幹の当たりだけ（見た目は MultiMesh）。区画ごとの体へ
				var stand := Node3D.new()
				stand.scene_file_path = path
				stand.position = Vector3(px, y - 0.3, pz)
				stand.scale = Vector3.ONE * hgt / model_h
				_hits_for(px, pz).add_tree(stand)
				stand.free()
		x += gap
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


## 葉の落ちた木（2026-11-11 代表「①②③ で入れて」。props/build_bare_tree.py。絵 design/asahigaoka/trees/01-bare-tree-ideas.jpg）:
## 雑木（毛糸を巻いた枝）・シラカバ（白いフェルトの幹に黒い糸の縫い目）・カラマツ（フェルトの幹に毛糸の枝を段々に）。
## 値は [形の高さ, 幹の半径, 立てる高さの下限, 上限] (m)
const BARE_ZOKI := "res://props/tree_bare_zoki.glb"
const BARE_KABA := "res://props/tree_bare_kaba.glb"
const BARE_KARA := "res://props/tree_bare_kara.glb"
const BARE := {
	BARE_ZOKI: [8.0, 0.40, 7.0, 11.0],
	BARE_KABA: [9.5, 0.40, 9.0, 13.5],
	BARE_KARA: [11.0, 0.40, 11.0, 17.0],
}

## 林の木ぜんぶに幹の当たりを付ける（2026-11-12 代表「木にソリで当たったときの衝突判定がないかも」）。前は、開けた所から 12 m までの
## 木にだけ付けていて、縁の 3 列ほどをすり抜けると、その奥は 85 m 進んでも当たらなかった（tools/asahi_tree_hit_check.gd）。
## 幹は旭ヶ丘で 4 万本ほど。1 つの体に全部入れると物理が止まった（1 コマ目から進まない）ので、HIT_CELL (m) 四方の区画ごとに体を分ける
## （区画あたり 100〜200 本。物理は近くの区画の体だけを見る）
const ALL_TRUNKS := true
const HIT_CELL := 64.0
var _hit_cells := {}   # 区画 → TreeHits（まだ世界に入れていない）


func _hits_for(x: float, z: float) -> TreeHits:
	var key := Vector2i(floori(x / HIT_CELL), floori(z / HIT_CELL))
	if not _hit_cells.has(key):
		var h := TreeHits.new()
		h.name = "TreeHits_%d_%d" % [key.x, key.y]
		_hit_cells[key] = h
	return _hit_cells[key]

const WOODS_FAR := 330.0   # 林の木（MultiMesh）を描く遠さ (m)。区画のまんなかまでの距離。その先の林は地面の林の色で見える
const WOODS_CELL := 64.0   # 林を分ける区画の大きさ (m)

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
			var key := Vector2i(floori(o.x / WOODS_CELL), floori(o.z / WOODS_CELL))
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
