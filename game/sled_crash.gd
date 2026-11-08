extends RefCounted
## ソリが雪の塊や木にぶつかって打ち上がる（2026-11-07 代表「クッションになる雪の塊を配置してぶつかったらソリが上空に飛んで乗ってた人も打ち上がり
## 四散するような感じが良い。その後ソリはひっくり返っていても着地点の傾斜に沿って滑っていってほしい」「同様のことを木に当たり判定をつけて木への衝突でも」）。
## 決まりと値の意味は design/controls-and-physics.md の「雪の塊と木にぶつかる」。ソリの動きは sled.gd の crash_lump・_launch。乗っている人の飛び方は flung.gd の throw_events。

const Look := preload("res://look.gd")
const Snowball := preload("res://snowball.gd")

# ---- 雪の塊: ロッジの正面の帯に、地面の雪が盛り上がった雪だまりを散らす（2026-11-08 代表「ロッジ前の雪山、規則的すぎて気持ち悪いです。おおきさも形も配置も」、
# 2026-11-08 代表「ロッジ前の雪が形が気持ち悪いです。スカスカだし」「あと地面から浮いてる」）。
# 綿の山の glb を置くのをやめ、地面と同じ毛糸の編み地（Look.snow）を、地面の見た目の高さからなめらかに盛り上げた 1 枚の形にした。裾は地面そのものなので浮かない。
# 形は自然な吹きだまりに合わせる: 上は丸く、風上（丘の側）はなだらか、風下（ロッジの側）は少し急。長く伸びた土手、くっついた盛り、低く広い雪だまり。
# 帯全体で 1 つの形なので、数を増やしても描く回数は増えない（遠くでは描かない: LUMP_SEE）。
# 置き方は種を固定した乱数（どの画面でも同じ）。最後に、丘から来るまっすぐな道すじを調べ、米袋の幅でも抜けられる隙間に小さな盛りを足す（ソリはどこかに必ず当たる）。
# 当たりは盛りの形に合わせた円柱と寝かせた丸棒。ソリだけが読むので、歩く人と CPU は通り抜ける
const LUMP_SEED := 41
const LUMP_BAND := Rect2(-50.0, 29.0, 94.0, 13.0)   # 散らす帯（ロッジの座標の x, 正面向きの距離）。届いたソリが並ぶ所（main.gd の DELIVER_Z）と案内板より先
const LUMP_GAP := Vector2(1.6, 4.2)  # 帯に沿って、次の盛りまでの間隔の範囲 (m)
const LUMP_EXTRA := 0.45        # 同じ所に、前後をずらしてもう 1 つ盛る割合（帯の奥行きを埋める）
const LUMP_KINDS := {"heap": 0.3, "cluster": 0.25, "bank": 0.25, "low": 0.2}   # 形の出やすさ
const LUMP_ROAD := 0.5          # 道にかかる盛りの高さに掛ける割合。ロッジへ歩く人のじゃまにならないよう低く（形は low だけ）
const LUMP_FILL_W := 0.3        # 抜け道を調べる幅の半分 (m)。米袋の幅の半分
const LUMP_HIT_H := 2.6         # 当たりの高さ (m)
const LUMP_HIT_K := 0.8         # 当たりの半径 = 盛りの裾の半径 × これ（裾の薄い所は当たらない）
const LUMP_LEE := 0.7           # 風下（ロッジの側）の裾の長さの割合。小さいほど風下が急
const LUMP_CELL := 0.4          # 形の格子の間隔 (m)
const LUMP_SINK := 0.06         # 盛りのない所は、地面の見た目よりこれだけ下へ（地面と重ならないように隠す）
const LUMP_SEE := 160.0         # これより遠いと描かない (m)


## ロッジの正面に雪だまりを散らす
static func build_lumps(world: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "CrashLumps"
	world.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = LUMP_SEED
	var bumps: Array = []       # 見た目の盛り [ロッジの座標の中心, 長いほうの半分, 短いほうの半分, 向き, 高さ]
	var parts_all: Array = []   # 当たり [ロッジの座標の中心, 半分の長さ, 半径, 向き]（抜け道を調べる）
	var x := LUMP_BAND.position.x + rng.randf_range(0.0, LUMP_GAP.x)
	while x < LUMP_BAND.end.x:
		for k in (2 if rng.randf() < LUMP_EXTRA else 1):
			var at := Vector2(x + rng.randf_range(-0.8, 0.8), rng.randf_range(LUMP_BAND.position.y, LUMP_BAND.end.y))
			parts_all.append_array(_put_lump(world, holder, at, _pick(rng), rng, bumps))
		x += rng.randf_range(LUMP_GAP.x, LUMP_GAP.y)
	# 抜け道をふさぐ: 丘の頂上から帯を横切る道すじと、ロッジへまっすぐ向かう道すじを 0.2 m おきに調べ、塊に触れない道すじが帯のまんなかを通る所に小さな盛りを足す
	for k in 60:
		var hole := _first_hole(world, parts_all)
		if hole == Vector2.INF:
			break
		parts_all.append_array(_put_lump(world, holder, hole, "low" if rng.randf() < 0.5 else "heap", rng, bumps, 0.7))
	holder.add_child(_drift_mesh(world, bumps))


static func _pick(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	for k in LUMP_KINDS:
		r -= LUMP_KINDS[k]
		if r <= 0.0:
			return k
	return "heap"


## 塊にどれも触れない道すじ（米袋の幅で）があれば、その道すじが帯のまんなかを通る所（ロッジの座標）。なければ INF。
## 道すじは 2 とおり: 丘の頂上（世界の原点）から帯を横切る放射状の線と、ロッジへまっすぐ向かう線
static func _first_hole(world: Node3D, parts: Array) -> Vector2:
	var mid_z := LUMP_BAND.get_center().y
	var lines: Array = []   # [世界の起点, 向き, 帯のまんなかを通る所（ロッジの座標）]
	var a0: Vector2 = world.lodge_to_world(Vector2(LUMP_BAND.position.x + 4.0, mid_z))
	var a1: Vector2 = world.lodge_to_world(Vector2(LUMP_BAND.end.x - 4.0, mid_z))
	var t0 := a0.angle()
	var dt := wrapf(a1.angle() - t0, -PI, PI)
	var steps := int(absf(dt) * a0.length() / 0.2)
	for i in steps + 1:
		var d := Vector2.from_angle(t0 + dt * i / steps)
		lines.append([Vector2.ZERO, d, _to_lodge(world, d * a0.length())])
	var x := LUMP_BAND.position.x + 4.0
	while x <= LUMP_BAND.end.x - 4.0:
		var o: Vector2 = world.lodge_to_world(Vector2(x, LUMP_BAND.end.y + 20.0))
		var e: Vector2 = world.lodge_to_world(Vector2(x, LUMP_BAND.position.y - 5.0))
		lines.append([o, (e - o).normalized(), Vector2(x, mid_z)])
		x += 0.2
	for ln in lines:
		var hit := false
		for p in parts:
			if _line_near(ln[0], ln[1], p, world):
				hit = true
				break
		if not hit:
			return ln[2]
	return Vector2.INF


## o から向き dir のまっすぐな道すじが、塊 p（ロッジの座標の丸棒）に米袋の幅で触れるか
static func _line_near(o: Vector2, dir: Vector2, p: Array, world: Node3D) -> bool:
	var c: Vector2 = world.lodge_to_world(p[0])
	var ax: Vector2 = world.lodge_to_world(p[0] + Vector2.from_angle(p[3])) - c
	var e0: Vector2 = c - ax * p[1] - o
	var e1: Vector2 = c + ax * p[1] - o
	var n := Vector2(-dir.y, dir.x)
	var d0 := e0.dot(n)
	var d1 := e1.dot(n)
	var reach: float = p[2] + LUMP_FILL_W
	if d0 * d1 <= 0.0:
		return true   # 丸棒が道すじをまたぐ
	return minf(absf(d0), absf(d1)) <= reach


static func _to_lodge(world: Node3D, w: Vector2) -> Vector2:
	var d: Vector2 = w - world.LODGE_POS
	var c := cos(world.LODGE_YAW)
	var s := sin(world.LODGE_YAW)
	return Vector2(d.x * c - d.y * s, d.x * s + d.y * c)


## 盛りを 1 つ置く（at はロッジの座標）。見た目の盛りを bumps に足し、当たりの部品を返す [中心, 半分の長さ, 半径, 向き]（ロッジの座標）。small は大きさの倍率
static func _put_lump(world: Node3D, holder: Node3D, at: Vector2, kind: String, rng: RandomNumberGenerator, bumps: Array, small := 1.0) -> Array:
	var w: Vector2 = world.lodge_to_world(at)
	var road: bool = world.path_weight(w.x, w.y, 2.5) > 0.0
	if road:
		kind = "low"
	var yaw := rng.randf_range(-0.5, 0.5)   # 帯に沿った向き（ロッジの座標の x）から、少しずつずらす
	var mine: Array = []   # [中心（ロッジの座標）, 長いほうの半分, 短いほうの半分, 向き, 高さ]
	match kind:
		"heap":   # こんもりした盛り。少しだけ楕円
			var r := rng.randf_range(1.3, 2.3) * small
			mine.append([at, r * rng.randf_range(1.0, 1.35), r, yaw, r * rng.randf_range(0.45, 0.6)])
		"cluster":   # 大きな盛りに、小さな盛りがくっつく
			var r := rng.randf_range(1.4, 2.1) * small
			mine.append([at, r * 1.15, r, yaw, r * rng.randf_range(0.45, 0.55)])
			for i in rng.randi_range(1, 3):
				var q := r * rng.randf_range(0.4, 0.7)
				var off := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.8, 1.2)
				mine.append([at + off, q * rng.randf_range(1.0, 1.4), q, rng.randf() * TAU, q * rng.randf_range(0.5, 0.7)])
		"bank":   # 吹きだまり・寄せた雪の、長い土手
			var r := rng.randf_range(1.0, 1.5) * small
			mine.append([at, r * rng.randf_range(2.2, 3.4), r, yaw, r * rng.randf_range(0.5, 0.75)])
		_:   # low: 低く広い雪だまり
			var r := rng.randf_range(1.8, 2.8) * small
			mine.append([at, r * rng.randf_range(1.2, 1.7), r, yaw, r * rng.randf_range(0.18, 0.26) * (LUMP_ROAD if road else 1.0)])
	bumps.append_array(mine)
	var area := Area3D.new()
	area.add_to_group("crash_lumps")
	area.set_meta("kind", kind)
	area.position = Vector3(w.x, world.height(w.x, w.y), w.y)
	area.rotation.y = world.LODGE_YAW   # 塊の中の (x, z) は、ロッジの座標と同じ向き
	area.monitorable = false
	var out: Array = []
	for b in mine:
		var long: float = b[1] * LUMP_HIT_K
		var r: float = b[2] * LUMP_HIT_K
		var half := maxf(long - r, 0.0)
		var lc: Vector2 = b[0] - at
		var col := CollisionShape3D.new()
		if half < 0.2:
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = LUMP_HIT_H
			col.shape = cyl
			col.position = Vector3(lc.x, LUMP_HIT_H * 0.5 - 0.5, lc.y)
		else:
			var cap := CapsuleShape3D.new()   # 横に寝かせた丸棒（半径は高さの分も含む）
			cap.radius = maxf(r, 0.6)
			cap.height = half * 2.0 + cap.radius * 2.0
			col.shape = cap
			col.position = Vector3(lc.x, 0.4, lc.y)
			col.rotation = Vector3(0.0, -float(b[3]), PI * 0.5)
		area.add_child(col)
		out.append([b[0], half, r, b[3]])
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.has_method("crash_lump"):
			body.crash_lump(area))
	holder.add_child(area)
	return out


## 盛りの高さ (m)。p はロッジの座標。盛りどうしはなめらかにつながる（大きいほうに、ほかの盛りの裾を少し足す）
static func _drift_height(p: Vector2, bumps: Array) -> float:
	var top := 0.0
	var rest := 0.0
	for b in bumps:
		var d: Vector2 = (p - b[0]).rotated(-float(b[3]))   # 盛りの向きに沿った座標（x が長いほう）
		var long: float = b[1]
		var short: float = b[2] * (LUMP_LEE if d.y < 0.0 else 1.0)   # ロッジの側（座標の z が小さい側）は裾が短く、急
		var q := (d.x / long) * (d.x / long) + (d.y / short) * (d.y / short)
		if q >= 1.0:
			continue
		var h: float = b[4] * pow(1.0 - q, 1.6)   # 上は丸く、裾はなだらかに地面へ
		if h > top:
			rest += top
			top = h
		else:
			rest += h
	return top + rest * 0.25


## 帯の雪だまりの形（地面の見た目の高さから盛り上げる。毛糸の編み地）
static func _drift_mesh(world: Node3D, bumps: Array) -> MeshInstance3D:
	var x0 := LUMP_BAND.position.x - 6.0
	var z0 := LUMP_BAND.position.y - 6.0
	var nx := int((LUMP_BAND.size.x + 12.0) / LUMP_CELL) + 1
	var nz := int((LUMP_BAND.size.y + 12.0) / LUMP_CELL) + 1
	var noise := FastNoiseLite.new()   # 盛りの表面のゆるいうねり（吹きだまりの風の跡）
	noise.seed = LUMP_SEED
	noise.frequency = 0.35
	var ys := PackedFloat32Array()
	var hs := PackedFloat32Array()
	var ws := PackedVector2Array()
	ys.resize(nx * nz)
	hs.resize(nx * nz)
	ws.resize(nx * nz)
	for j in nz:
		for i in nx:
			var l := Vector2(x0 + i * LUMP_CELL, z0 + j * LUMP_CELL)
			var w: Vector2 = world.lodge_to_world(l)
			var h := _drift_height(l, bumps)
			if h > 0.0:
				h *= 1.0 + 0.12 * noise.get_noise_2d(l.x, l.y)
			var g: float = world.height(w.x, w.y) + world.snow_lift(w.x, w.y)
			var k := j * nx + i
			hs[k] = h
			ys[k] = g + h if h > 0.005 else g - LUMP_SINK
			ws[k] = w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, nx - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, nz - 1)
			var a: Vector3 = Vector3(ws[j * nx + ir].x, ys[j * nx + ir], ws[j * nx + ir].y) - Vector3(ws[j * nx + il].x, ys[j * nx + il], ws[j * nx + il].y)
			var b: Vector3 = Vector3(ws[ju * nx + i].x, ys[ju * nx + i], ws[ju * nx + i].y) - Vector3(ws[jd * nx + i].x, ys[jd * nx + i], ws[jd * nx + i].y)
			var n := b.cross(a).normalized()
			st.set_normal(n if n.y > 0.0 else -n)
			st.set_uv(ws[k] * 0.5)
			st.add_vertex(Vector3(ws[k].x, ys[k], ws[k].y))
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			if hs[a] <= 0.005 and hs[a + 1] <= 0.005 and hs[a + nx] <= 0.005 and hs[a + nx + 1] <= 0.005:
				continue   # 盛りのない升は描かない
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + nx)
			st.add_index(a + nx)
			st.add_index(a + 1)
			st.add_index(a + nx + 1)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Drifts"
	mi.mesh = st.commit()
	var mat := Look.snow()
	mat.vertex_color_use_as_albedo = true   # 地面と同じ色の出し方
	mi.material_override = mat
	mi.visibility_range_end = LUMP_SEE
	return mi


## 出来事 "crash" が届いた（どの画面でも。emotes.gd が呼ぶ）。雪の粉を出し、塊をへこませる。乗っていた人は出来事 "flung" で飛ぶ
static func on_event(world: Node3D, ev: Dictionary) -> void:
	var s = world.get_node_or_null(ev.get("sled", NodePath()))
	if s is RigidBody3D:
		s.crash_seen()
	Snowball.splat_at(world, ev.point, Vector3.UP, false, 8.0)
