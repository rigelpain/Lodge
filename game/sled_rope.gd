extends Node3D
## ソリの引き紐。左右の手すりの前の端（渦の一番前）を、長くたわんだ一本の紐（ブライドル）で結び、
## そのまんなかの結び目から引っ張り紐が前へ出る。紐は点を棒でつないだだけの簡単な計算（Verlet）で、
## 重力でたわみ、雪の上に寝る。持つ人がいれば先が手に付き、張ると結び目が引かれる向きへ寄って、
## 手すりの両端と三角形になる。
## 見た目は撚った綿のロープ: 断面の丸い管を、ねじれの出ない枠で張り、3 本撚りの筋を描く。
## 管の形は GPU が作る（点と向きだけを渡し、頂点シェーダーが曲線と丸い断面にする）。CPU は点の計算だけ
## （前は短い円柱を世界の上下で伸び縮みさせていたため、紐が斜めになると円柱が平たい板になって重なり、縞に見えた）

## 右の手すりの前の端（ソリの座標）。左は x を逆に。glb に印 rope_tie_l・rope_tie_r があればそちらを使う
## （props/build_sled.py の手すりの巻き下りの一番前）
const TIE := Vector3(0.82, 0.52, -1.13)
const RAIL_R := 0.026        # 手すりの太さ（半径）。巻きはこの外に
const BRIDLE_LEN := 2.4      # 両端を結ぶ紐の長さ。左右の手すりのあいだ 1.64 m より長く、たわむ
const BRIDLE_SEG := 12       # 偶数。まんなかが結び目
const PULL_SEG := 14
const RADIUS := 0.017
const SIDES := 10
const SUB := 4               # 点のあいだを曲線で割る数（GPU で。見た目だけ）
const ITER := 10
const PITCH := 0.06          # 撚りの模様がひとまわりする長さ (m)
const COLOR := Color(0.88, 0.80, 0.66)   # 生成りの綿（雪の白に沈まないよう少し黄みに）

## 点の列（世界）と、点ごとの断面の向きから、丸い管を作る。UV.x は周り、UV.y は何番目の点か
const TUBE_SHADER := """
shader_type spatial;
uniform vec3 pts[16];
uniform vec3 nrm[16];
uniform int count = 2;
uniform float radius = 0.017;
uniform float seg_len = 0.15;
uniform float pitch = 0.06;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 tex_uv;

void vertex() {
	float f = UV.y;
	int i = clamp(int(floor(f)), 0, count - 2);
	float t = clamp(f - float(i), 0.0, 1.0);
	vec3 p0 = pts[max(i - 1, 0)];
	vec3 p1 = pts[i];
	vec3 p2 = pts[i + 1];
	vec3 p3 = pts[min(i + 2, count - 1)];
	// 点を通る曲線（Catmull-Rom）と、その向き
	vec3 a1 = -p0 + p2;
	vec3 a2 = 2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3;
	vec3 a3 = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
	vec3 c = 0.5 * (2.0 * p1 + a1 * t + a2 * t * t + a3 * t * t * t);
	vec3 tn = a1 + 2.0 * a2 * t + 3.0 * a3 * t * t;
	tn = length(tn) > 1e-5 ? normalize(tn) : normalize(p2 - p1 + vec3(0.0, 1e-5, 0.0));
	vec3 n = mix(nrm[i], nrm[i + 1], t);
	n = normalize(n - tn * dot(n, tn) + vec3(1e-6));
	vec3 b = cross(tn, n);
	float ang = UV.x * TAU;
	vec3 r = n * cos(ang) + b * sin(ang);
	VERTEX = c + r * radius;
	NORMAL = r;
	TANGENT = -n * sin(ang) + b * cos(ang);
	BINORMAL = tn;
	tex_uv = vec2(UV.x, f * seg_len / pitch);
}

void fragment() {
	ALBEDO = texture(albedo_tex, tex_uv).rgb;
	NORMAL_MAP = texture(normal_tex, tex_uv).rgb;
	ROUGHNESS = 1.0;
	RIM = 0.5;   // 綿の毛羽: 縁がふわっと明るい（フェルトと同じ）
	RIM_TINT = 0.6;
}
"""

var sled: RigidBody3D
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _links: Array[Vector2i] = []   # つないだ 2 点
var _rest := PackedFloat32Array() # その長さ
var _mid := BRIDLE_SEG / 2
var _end := 0
var _last_tie := Vector3.INF
var _calm := 0               # 動きがほとんどないコマが続いた数。続けば計算も描き直しも休む
var _bridle: MeshInstance3D
var _pull: MeshInstance3D
var _knots: Array[MeshInstance3D] = []   # 結び目と、先のこぶ
var _ties: Array[Vector3] = [Vector3(-TIE.x, TIE.y, TIE.z), TIE]   # 左右の結び先（ソリの座標）
var _tie_axis: Array[Vector3] = [Vector3.UP, Vector3.UP]            # そこでの手すりの向き。巻きの軸

static var _mat: StandardMaterial3D
static var _shader: Shader


func _ready() -> void:
	_read_ties()
	# 点: 0..BRIDLE_SEG がブライドル（0 が左の端、まんなかが結び目）、そのあとが引っ張り紐
	var n := BRIDLE_SEG + 1 + PULL_SEG
	_pos.resize(n)
	_prev.resize(n)
	var bl := BRIDLE_LEN / BRIDLE_SEG
	for i in BRIDLE_SEG:
		_link(i, i + 1, bl)
	# 引っ張り紐: 張ってまっすぐ前へ引いたとき、sled.gd の紐の付け根から手までが、その紐の長さになるように
	var half := _ties[0].distance_to(_ties[1]) * 0.5
	var apex := (_ties[0] + _ties[1]) * 0.5 + Vector3.FORWARD * sqrt(BRIDLE_LEN * BRIDLE_LEN * 0.25 - half * half)
	var pl: float = (sled.ROPE_LEN - sled.ROPE_ANCHOR.distance_to(apex)) / PULL_SEG
	var prev_i := _mid
	for k in PULL_SEG:
		var i := BRIDLE_SEG + 1 + k
		_link(prev_i, i, pl)
		prev_i = i
	_end = n - 1
	_bridle = _make_tube(BRIDLE_SEG + 1, bl)
	_pull = _make_tube(PULL_SEG + 1, pl)
	for r in [0.036, 0.03]:
		var k := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.6
		sm.radial_segments = 10
		sm.rings = 5
		k.mesh = sm
		k.material_override = material()
		k.top_level = true
		add_child(k)
		_knots.append(k)
	# 手すりの前の端の巻き: 3 巻きして結ぶ。ソリと一緒に動くだけなので一度だけ作る
	var coils := MeshInstance3D.new()
	coils.mesh = _coil_mesh()
	coils.material_override = material()
	add_child(coils)
	_lay_out()


## glb の印から結び先を読む。印の上（Blender の Z）を手すりの向きとする
func _read_ties() -> void:
	for k in 2:
		var found := sled.find_children("rope_tie_%s*" % ["l", "r"][k], "Node3D", true, false)
		if found.is_empty():
			continue
		var mark: Node3D = found[0]
		_ties[k] = sled.to_local(mark.global_position)
		_tie_axis[k] = (sled.global_basis.inverse() * mark.global_basis.y).normalized()


func _link(i: int, j: int, len: float) -> void:
	_links.append(Vector2i(i, j))
	_rest.append(len)


## 点 m 個の管。形は頂点シェーダーが点から作るので、ここでは周り（UV.x）と何番目の点か（UV.y）の格子だけ
func _make_tube(m: int, seg_len: float) -> MeshInstance3D:
	var rows := (m - 1) * SUB + 1
	var uv := PackedVector2Array()
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rows:
		for k in SIDES + 1:
			uv.append(Vector2(float(k) / SIDES, float(j) / SUB))
			v.append(Vector3.ZERO)
	var row := SIDES + 1
	for j in rows - 1:
		for k in SIDES:
			var a := j * row + k
			idx.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])
	# 法線と接線はシェーダーが書くが、枠は要る
	var nm := PackedVector3Array()
	nm.resize(v.size())
	nm.fill(Vector3.UP)
	var tg := PackedFloat32Array()
	for i in v.size():
		tg.append_array([1.0, 0.0, 0.0, 1.0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nm
	arrays[Mesh.ARRAY_TANGENT] = tg
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = TUBE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	sm.set_shader_parameter("count", m)
	sm.set_shader_parameter("radius", RADIUS)
	sm.set_shader_parameter("seg_len", seg_len)
	sm.set_shader_parameter("pitch", PITCH)
	sm.set_shader_parameter("albedo_tex", material().albedo_texture)
	sm.set_shader_parameter("normal_tex", material().normal_texture)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.material_override = sm
	mi.top_level = true   # 点は世界の座標
	add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return mi


## 先の位置（世界）。持っていない紐を拾うときに使う
func end_point() -> Vector3:
	return _pos[_end]


## 雪の上に、ソリの前へ伸ばして置き直す（始めと、ソリが遠くへ移されたとき）
func _lay_out() -> void:
	var l := sled.to_global(_ties[0])
	var r := sled.to_global(_ties[1])
	var fwd := -sled.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	for i in BRIDLE_SEG + 1:
		var t := float(i) / BRIDLE_SEG
		_pos[i] = l.lerp(r, t) + fwd * sin(PI * t) * 0.8
	for k in PULL_SEG:
		_pos[BRIDLE_SEG + 1 + k] = _pos[_mid] + fwd * _rest[BRIDLE_SEG + k] * (k + 1)
	for i in _pos.size():
		_pos[i].y = maxf(_pos[i].y, _ground(_pos[i]) + RADIUS)
	_prev = _pos.duplicate()
	_last_tie = r


## 見た目の雪面の高さ（当たり判定の地面に、吹きだまりのうねりを足す）
func _ground(p: Vector3) -> float:
	var world := sled.get_parent()
	if not world.has_method("height"):
		return -INF
	return world.height(p.x, p.z) + (world.snow_lift(p.x, p.z) if world.has_method("snow_lift") else 0.0)


func _physics_process(dt: float) -> void:
	var l := sled.to_global(_ties[0])
	var r := sled.to_global(_ties[1])
	if r.distance_to(_last_tie) > 2.0:   # ふもとへ戻したときなど
		_lay_out()
	_last_tie = r
	var holder: Node3D = sled.rope_holder
	var hand: Vector3 = holder.rope_hand() if holder and holder.has_method("rope_hand") else Vector3.INF
	# 持つ人がなく、ソリも紐も止まっていれば休む
	if hand == Vector3.INF and l.distance_squared_to(_pos[0]) + r.distance_squared_to(_pos[BRIDLE_SEG]) < 1e-6:
		if _calm > 30:
			return
	else:
		_calm = 0
	var n := _pos.size()
	var pinned := PackedByteArray()
	pinned.resize(n)
	pinned[0] = 1
	pinned[BRIDLE_SEG] = 1
	if hand != Vector3.INF:
		pinned[_end] = 1
	# 動かす: 前のコマの動きを少し弱めて残し、重力で落とす
	var g := Vector3.DOWN * 9.8 * dt * dt
	for i in n:
		if pinned[i]:
			continue
		var p := _pos[i]
		_pos[i] = p + (p - _prev[i]) * 0.985 + g
		_prev[i] = p
	_pos[0] = l
	_pos[BRIDLE_SEG] = r
	if hand != Vector3.INF:
		_pos[_end] = hand
	# 長さを保つ（棒）
	for it in ITER:
		for c in _links.size():
			var a := _links[c].x
			var b := _links[c].y
			var d := _pos[b] - _pos[a]
			var len := d.length()
			if len < 1e-5:
				continue
			var wa := 0.0 if pinned[a] else 1.0
			var wb := 0.0 if pinned[b] else 1.0
			if wa + wb == 0.0:
				continue
			var fix := d * ((len - _rest[c]) / len / (wa + wb))
			_pos[a] += fix * wa
			_pos[b] -= fix * wb
	# ソリの台にめり込んだ点は前か横へ出す。雪には潜らない。雪に触れている所は横の動きを摩擦で弱める
	var inv := sled.global_transform.affine_inverse()
	var moved := 0.0
	for i in n:
		if pinned[i]:
			continue
		_pos[i] = _out_of_sled(_pos[i], inv)
		var h := _ground(_pos[i]) + RADIUS
		if _pos[i].y <= h + 0.003:
			_pos[i].y = maxf(_pos[i].y, h)
			# 雪に寝た紐はほとんど滑らない。ゆっくりならその場に留まる（坂でもソリの下へ流れ込まない）
			var v := _pos[i] - _prev[i]
			var keep := 0.0 if Vector2(v.x, v.z).length() < 0.02 * dt * 60.0 else 0.3
			_prev[i].x = _pos[i].x - v.x * keep
			_prev[i].z = _pos[i].z - v.z * keep
		moved = maxf(moved, _pos[i].distance_squared_to(_prev[i]))
	_calm = _calm + 1 if moved < 1e-8 else 0
	_show()


## ソリの台の中（手すりより後ろ）に入った点を、近い方の縁（前か左右）へ出す
func _out_of_sled(p: Vector3, inv: Transform3D) -> Vector3:
	var q := inv * p
	# 滑り木の前の反り（x = ±0.6、中心 y 0.32・z -1.2、外の半径 0.32）には上から載る
	if abs(abs(q.x) - 0.6) < 0.05 and q.z < -1.2 and q.y > 0.32:
		var c := Vector2(q.y - 0.32, q.z + 1.2)
		if c.length() < 0.32 + RADIUS:
			c = c.normalized() * (0.32 + RADIUS)
			q.y = 0.32 + c.x
			q.z = -1.2 + c.y
			return sled.global_transform * q
	const HX := 0.8
	const Z0 := -1.42
	const Z1 := 1.5
	if q.y > 0.5 or q.y < -0.1 or abs(q.x) > HX or q.z < Z0 or q.z > Z1:
		return p
	var to_front := q.z - Z0
	var to_side: float = HX - abs(q.x)
	if to_front < to_side:
		q.z = Z0
	else:
		q.x = signf(q.x) * HX
	return sled.global_transform * q


# ---------------------------------------------------------------- 見た目

## 点と、点ごとの断面の向きをシェーダーへ渡す。向きは前の点から最小の回転で運ぶ（parallel transport）ので、
## 紐がどう曲がっても断面がねじれない
func _show() -> void:
	var pull := PackedVector3Array([_pos[_mid]])
	pull.append_array(_pos.slice(BRIDLE_SEG + 1))
	_send(_bridle, _pos.slice(0, BRIDLE_SEG + 1))
	_send(_pull, pull)
	_knots[0].global_position = _pos[_mid]
	_knots[1].global_position = _pos[_end]


func _send(mi: MeshInstance3D, pts: PackedVector3Array) -> void:
	var m := pts.size()
	var nrm := PackedVector3Array()
	nrm.resize(m)
	var t0 := (pts[1] - pts[0]).normalized()
	var n := t0.cross(Vector3.UP if abs(t0.y) < 0.9 else Vector3.RIGHT).normalized()
	var lo := pts[0]
	var hi := pts[0]
	for i in m:
		var t := pts[mini(i + 1, m - 1)] - pts[maxi(i - 1, 0)]
		if t.length() > 1e-6:
			t = t.normalized()
			n = n - t * n.dot(t)
			n = n.normalized() if n.length() > 1e-4 else t.cross(Vector3.UP).normalized()
		nrm[i] = n
		lo = lo.min(pts[i])
		hi = hi.max(pts[i])
	var sm: ShaderMaterial = mi.material_override
	sm.set_shader_parameter("pts", pts)
	sm.set_shader_parameter("nrm", nrm)
	# 形は GPU で動くので、見える範囲は点から決める（曲線のふくらみと太さの分だけ広げる）
	mi.custom_aabb = AABB(lo, hi - lo).grow(0.15)


## 手すりの両端の巻き（ソリの座標で一度だけ作る）
func _coil_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var nm := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for k in 2:
		var ax := _tie_axis[k]
		var e1 := ax.cross(Vector3.RIGHT if abs(ax.x) < 0.9 else Vector3.FORWARD).normalized()
		var e2 := ax.cross(e1)
		var rr := RAIL_R + RADIUS * 0.75
		var coil := PackedVector3Array()
		for i in 37:
			var t := i / 36.0
			var a := t * TAU * 3.0
			coil.append(_ties[k] + ax * (t - 0.5) * 0.08 + (e1 * cos(a) + e2 * sin(a)) * rr)
		_tube(coil, RADIUS * 0.75, v, nm, tg, uv, idx)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nm
	arrays[Mesh.ARRAY_TANGENT] = tg
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## 丸い管（CPU で。巻きのように一度だけ作る物に）。U は周り、V は紐に沿った長さ（PITCH で 1）
func _tube(pts: PackedVector3Array, rad: float, v: PackedVector3Array, nm: PackedVector3Array, tg: PackedFloat32Array,
		uv: PackedVector2Array, idx: PackedInt32Array) -> void:
	var m := pts.size()
	if m < 2:
		return
	var base := v.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var n := t0.cross(Vector3.UP if abs(t0.y) < 0.9 else Vector3.RIGHT).normalized()
	var s := 0.0
	for i in m:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == m - 1:
			t = pts[i] - pts[i - 1]
		else:
			t = pts[i + 1] - pts[i - 1]
		if t.length() < 1e-6:
			t = t0
		t = t.normalized()
		n = (n - t * n.dot(t))
		n = n.normalized() if n.length() > 1e-4 else t.cross(Vector3.UP).normalized()
		var b := t.cross(n)
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		for k in SIDES + 1:
			var a := TAU * k / SIDES
			var r := n * cos(a) + b * sin(a)
			var around := -n * sin(a) + b * cos(a)
			v.append(pts[i] + r * rad)
			nm.append(r)
			tg.append_array([around.x, around.y, around.z, 1.0])
			uv.append(Vector2(float(k) / SIDES, s / PITCH))
		t0 = t
	var row := SIDES + 1
	for i in m - 1:
		for k in SIDES:
			var a := base + i * row + k
			idx.append_array([a, a + row, a + 1, a + 1, a + row, a + row + 1])


## 撚った綿の素材: 3 本の撚り（斜めの筋と、そのあいだの溝）と、筋に沿った細い繊維。管のシェーダーも同じ絵を使う
static func material() -> StandardMaterial3D:
	if _mat:
		return _mat
	const W := 64
	const H := 64
	var hgt := PackedFloat32Array()
	hgt.resize(W * H)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var streak := PackedFloat32Array()   # 繊維の細い筋（撚りの向きに沿う）
	streak.resize(W)
	for i in W:
		streak[i] = rng.randf()
	var alb := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var u := float(x) / W
			var vv := float(y) / H
			var f := fposmod(3.0 * u + 3.0 * vv, 1.0)          # 3 本の撚り。周りと長さの両方でつながる
			var strand := pow(sin(PI * f), 0.55)               # 撚りの丸み（溝で 0）
			var fiber := streak[posmod(int((3.0 * u + 3.0 * vv) * 21.0 + (u - vv) * 2.0), W)]
			var hh := strand * (0.85 + 0.15 * fiber)
			hgt[y * W + x] = hh
			var shade := 0.62 + 0.38 * hh
			alb.set_pixel(x, y, Color(COLOR.r * shade, COLOR.g * shade, COLOR.b * shade))
	var nrm := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var dx := hgt[y * W + posmod(x + 1, W)] - hgt[y * W + posmod(x - 1, W)]
			var dy := hgt[posmod(y + 1, H) * W + x] - hgt[posmod(y - 1, H) * W + x]
			var nn := Vector3(-dx * 2.0, -dy * 2.0, 1.0).normalized()
			nrm.set_pixel(x, y, Color(nn.x * 0.5 + 0.5, nn.y * 0.5 + 0.5, nn.z * 0.5 + 0.5))
	alb.generate_mipmaps()
	nrm.generate_mipmaps()
	_mat = StandardMaterial3D.new()
	_mat.albedo_texture = ImageTexture.create_from_image(alb)
	_mat.normal_enabled = true
	_mat.normal_texture = ImageTexture.create_from_image(nrm)
	_mat.normal_scale = 1.0
	_mat.roughness = 1.0
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat.rim_enabled = true   # 綿の毛羽: 縁がふわっと明るい（フェルトと同じ）
	_mat.rim = 0.5
	_mat.rim_tint = 0.6
	return _mat
