extends RefCounted
## ソリが雪の塊や木にぶつかって打ち上がる（2026-11-07 代表「クッションになる雪の塊を配置してぶつかったらソリが上空に飛んで乗ってた人も打ち上がり
## 四散するような感じが良い。その後ソリはひっくり返っていても着地点の傾斜に沿って滑っていってほしい」「同様のことを木に当たり判定をつけて木への衝突でも」）。
## 決まりと値の意味は design/controls-and-physics.md の「雪の塊と木にぶつかる」。ソリの動きは sled.gd の crash_lump・_launch。乗っている人の飛び方は flung.gd の throw_events。

const Props := preload("res://props.gd")
const Snowball := preload("res://snowball.gd")

# ---- 雪の塊: ロッジの正面の帯に、自然に積もった・寄せた雪だまりを散らす（2026-11-08 代表「ロッジ前の雪山、規則的すぎて気持ち悪いです。おおきさも形も配置も」）。
# 形は 4 つ: こんもりした山（heap）、大小がくっついた山（cluster）、風の吹きだまりや雪かきで寄せた長い土手（bank）、低くなだらかな雪だまり（low）。
# どれも毛糸の雪の glb（props/build_snow.py）を、大きさ・縦横・高さ・向きを変えて組む。
# 置き方は種を固定した乱数（どの画面でも同じ）。最後に、丘から来るまっすぐな道すじを細かく調べ、米袋の幅でも抜けられる隙間に小さな塊を足す（ソリはどこかに必ず当たる）。
# 当たりは見た目の形に合わせた丸棒（横に寝かせたカプセル）と円柱。ソリだけが読むので、歩く人と CPU は通り抜ける
const LUMP_SEED := 41
const LUMP_BAND := Rect2(-50.0, 29.0, 94.0, 13.0)   # 散らす帯（ロッジの座標の x, 正面向きの距離）。届いたソリが並ぶ所（main.gd の DELIVER_Z）と案内板より先
const LUMP_GAP := Vector2(3.0, 8.0)  # となりの塊までの、帯に沿った間隔の範囲 (m)
const LUMP_KINDS := {"heap": 0.35, "cluster": 0.25, "bank": 0.2, "low": 0.2}   # 形の出やすさ
const LUMP_LIFT := 0.25         # 塊を雪面から持ち上げる (m)。低いと雪に埋まって、砕けた粒に見える
const LUMP_ROAD := 0.6          # 道にかかる塊の高さに掛ける割合。ロッジへ歩く人のじゃまにならないよう低く（形は low だけ）
const LUMP_FILL_W := 0.3        # 抜け道を調べる幅の半分 (m)。米袋の幅の半分
const LUMP_HIT_H := 2.6         # 当たりの高さ (m)
const PILE_A := "res://props/snow_pile_a.glb"
const PILE_B := "res://props/snow_pile_b.glb"
const DRIFT := "res://props/snow_drift.glb"

static var _sizes := {}         # glb → 倍率 1 の足もとの大きさ Vector3(横, 高さ, 奥)


## ロッジの正面に雪の塊を散らす
static func build_lumps(world: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "CrashLumps"
	world.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = LUMP_SEED
	var parts_all: Array = []   # [ロッジの座標の中心 Vector2, 半分の長さ, 半径, 向き]（抜け道を調べる）
	var x := LUMP_BAND.position.x + rng.randf_range(0.0, LUMP_GAP.x)
	while x < LUMP_BAND.end.x:
		var at := Vector2(x, rng.randf_range(LUMP_BAND.position.y, LUMP_BAND.end.y))
		var kind := _pick(rng)
		parts_all.append_array(_put_lump(world, holder, at, kind, rng))
		x += rng.randf_range(LUMP_GAP.x, LUMP_GAP.y)
	# 抜け道をふさぐ: 丘の頂上から帯を横切る道すじと、ロッジへまっすぐ向かう道すじを 0.2 m おきに調べ、塊に触れない道すじが帯のまんなかを通る所に小さな塊を足す
	for k in 60:
		var hole := _first_hole(world, parts_all)
		if hole == Vector2.INF:
			break
		parts_all.append_array(_put_lump(world, holder, hole, "low" if rng.randf() < 0.5 else "heap", rng, 0.6))


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


## 塊を 1 つ置く（at はロッジの座標）。形の部品を返す [中心, 半分の長さ, 半径, 向き]（ロッジの座標）。small は大きさの倍率
static func _put_lump(world: Node3D, holder: Node3D, at: Vector2, kind: String, rng: RandomNumberGenerator, small := 1.0) -> Array:
	var w: Vector2 = world.lodge_to_world(at)
	var road: bool = world.path_weight(w.x, w.y, 2.0) > 0.0
	if road:
		kind = "low"
	var area := Area3D.new()
	area.add_to_group("crash_lumps")
	area.set_meta("kind", kind)
	area.position = Vector3(w.x, world.foot_y(w.x, w.y, 1.0) - 0.05, w.y)
	area.rotation.y = world.LODGE_YAW
	area.monitorable = false
	var look := Node3D.new()
	look.name = "Look"
	look.position.y = LUMP_LIFT
	area.add_child(look)
	var yaw := rng.randf_range(-0.6, 0.6)   # 帯に沿った向きから、少しずつずらす
	var parts: Array = []   # [glb, 中心（塊の中）, 大きさ Vector3, 向き]
	match kind:
		"heap":
			var s := rng.randf_range(1.3, 2.3) * small
			parts.append([PILE_A, Vector2.ZERO, Vector3(s * rng.randf_range(0.9, 1.25), s * rng.randf_range(0.75, 1.1), s), rng.randf() * TAU])
		"cluster":
			var s := rng.randf_range(1.2, 1.9) * small
			parts.append([PILE_A, Vector2.ZERO, Vector3(s, s * rng.randf_range(0.8, 1.05), s * 0.95), rng.randf() * TAU])
			for i in rng.randi_range(1, 3):
				var a := rng.randf() * TAU
				var r := s * rng.randf_range(0.9, 1.5)
				var t := s * rng.randf_range(0.35, 0.8)
				parts.append([PILE_B if rng.randf() < 0.6 else PILE_A, Vector2.from_angle(a) * r, Vector3(t * 1.8, t * rng.randf_range(1.2, 1.7), t * 1.8), rng.randf() * TAU])
		"bank":
			var s := rng.randf_range(0.55, 0.9) * small
			parts.append([DRIFT, Vector2.ZERO, Vector3(s, s * rng.randf_range(1.0, 1.5), s * rng.randf_range(1.0, 1.4)), yaw + (PI if rng.randf() < 0.5 else 0.0)])
			if rng.randf() < 0.5:   # 寄せた土手の端に、こぼれた山
				parts.append([PILE_A, Vector2(s * 3.4 * (1.0 if rng.randf() < 0.5 else -1.0), rng.randf_range(-0.6, 0.6)).rotated(yaw), Vector3.ONE * s * rng.randf_range(1.0, 1.4), rng.randf() * TAU])
		_:   # low: 平たく広い雪だまり
			var s := rng.randf_range(1.8, 2.8) * small
			parts.append([PILE_A, Vector2.ZERO, Vector3(s * rng.randf_range(1.0, 1.5), s * rng.randf_range(0.4, 0.55) * (LUMP_ROAD if road else 1.0), s), yaw])
	var out: Array = []
	for pt in parts:
		var size := _size_of(pt[0])
		var n := Props.make(pt[0])
		n.scale = pt[2]
		n.position = Vector3(pt[1].x, 0.0, pt[1].y)
		n.rotation.y = pt[3]
		look.add_child(n)
		# 当たり: 足もとの大きさの長いほうに沿って寝かせた丸棒。半径は短いほうの半分の 9 割（形の縁は丸い）
		var hx: float = size.x * pt[2].x * 0.5
		var hz: float = size.z * pt[2].z * 0.5
		var r := minf(hx, hz) * 0.9
		var half := maxf(hx, hz) - minf(hx, hz)
		var axis_yaw: float = pt[3] - (0.0 if hx >= hz else PI * 0.5)   # 塊の中での、長いほうの向き（y 回り。0 で x の向き）
		var col := CollisionShape3D.new()
		if half < 0.2:
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = LUMP_HIT_H
			col.shape = cyl
			col.position = Vector3(pt[1].x, LUMP_HIT_H * 0.5 - 0.5, pt[1].y)
		else:
			var cap := CapsuleShape3D.new()   # 横に寝かせて、少し縦につぶれた丸棒（半径は高さの分も含む）
			cap.radius = maxf(r, 0.6)
			cap.height = half * 2.0 + cap.radius * 2.0
			col.shape = cap
			col.position = Vector3(pt[1].x, 0.4, pt[1].y)
			col.rotation = Vector3(0.0, axis_yaw, PI * 0.5)
		area.add_child(col)
		# ロッジの座標で: 塊の中の (x, z) は、ロッジの座標の (x, z) と同じ向き（area の向き = ロッジの向き）
		var lc: Vector2 = at + pt[1]
		out.append([lc, half, r, -axis_yaw])
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.has_method("crash_lump"):
			b.crash_lump(area))
	holder.add_child(area)
	return out


## glb の足もとの大きさ（倍率 1）。形から一度だけ測る
static func _size_of(path: String) -> Vector3:
	if _sizes.has(path):
		return _sizes[path]
	var n := Props.make(path)
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		var p: Node = mi
		while p != n:
			b = (p as Node3D).transform * b
			p = p.get_parent()
		box = b if first else box.merge(b)
		first = false
	n.free()
	_sizes[path] = box.size
	return box.size


## 出来事 "crash" が届いた（どの画面でも。emotes.gd が呼ぶ）。雪の粉を出し、塊をへこませる。乗っていた人は出来事 "flung" で飛ぶ
static func on_event(world: Node3D, ev: Dictionary) -> void:
	var s = world.get_node_or_null(ev.get("sled", NodePath()))
	if s is RigidBody3D:
		s.crash_seen()
	Snowball.splat_at(world, ev.point, Vector3.UP, false, 8.0)
	var lump = world.get_node_or_null(ev.get("lump", NodePath())) if ev.has("lump") else null
	if lump:
		_squash(lump.get_node_or_null("Look"))


## 塊がぼふっとへこんで戻る（12 コマ／秒）
static func _squash(look: Node3D) -> void:
	if look == null or not look.is_inside_tree():
		return
	var base := look.scale
	var tree := look.get_tree()
	for k in [Vector2(1.35, 0.4), Vector2(1.3, 0.5), Vector2(1.2, 0.65), Vector2(1.1, 0.8), Vector2(1.03, 0.95), Vector2(1.0, 1.0)]:
		if not is_instance_valid(look):
			return
		look.scale = Vector3(base.x * k.x, base.y * k.y, base.z * k.x)
		await tree.create_timer(1.0 / 12.0).timeout
