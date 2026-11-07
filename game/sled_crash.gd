extends RefCounted
## ソリが雪の塊や木にぶつかって打ち上がる（2026-11-07 代表「クッションになる雪の塊を配置してぶつかったらソリが上空に飛んで乗ってた人も打ち上がり
## 四散するような感じが良い。その後ソリはひっくり返っていても着地点の傾斜に沿って滑っていってほしい」「同様のことを木に当たり判定をつけて木への衝突でも」）。
## 決まりと値の意味は design/controls-and-physics.md の「雪の塊と木にぶつかる」。ソリの動きは sled.gd の crash_lump・_launch。乗っている人の飛び方は flung.gd の throw_events。

const Props := preload("res://props.gd")
const Snowball := preload("res://snowball.gd")

# ---- 雪の塊: ロッジの正面に 2 列。列を半分ずらして、まっすぐ滑ってくるソリは必ずどちらかに当たる。歩く人は通り抜けられる（当たりはソリだけが読む）
const LUMP_ROWS := [33.0, 37.0] # 列の、ロッジの座標の正面向きの距離 (m)。届いたソリが並ぶ所（main.gd の DELIVER_Z）と案内板より先
const LUMP_X := Vector2(-48.0, 42.0)   # 列の両端（ロッジの座標の x）。丘から見たロッジの幅より広く
const LUMP_STEP := 5.2          # 塊の間隔 (m)
const LUMP_R := 1.9             # 塊の当たりの半径 (m)
const LUMP_SCALE := 1.8         # 塊の大きさ（雪のかたまりの glb に掛ける。幅 2.2 m・高さ 0.9 m の形）
const LUMP_LIFT := 0.25         # 塊を雪面から持ち上げる (m)。低いと雪に埋まって、砕けた粒に見える
const LUMP_ROAD := 0.7          # 道にかかる塊の大きさの割合。ロッジへ歩く人のじゃまにならないよう低く
const LUMP_GLB := "res://props/snow_pile_a.glb"


## ロッジの正面に雪の塊を並べる
static func build_lumps(world: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "CrashLumps"
	world.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for row in LUMP_ROWS.size():
		var x: float = LUMP_X.x + (LUMP_STEP * 0.5 if row == 1 else 0.0)
		while x <= LUMP_X.y:
			_put_lump(world, holder, world.lodge_to_world(Vector2(x, LUMP_ROWS[row])), rng)
			x += LUMP_STEP


static func _put_lump(world: Node3D, holder: Node3D, at: Vector2, rng: RandomNumberGenerator) -> void:
	var size := LUMP_SCALE * (LUMP_ROAD if world.path_weight(at.x, at.y, LUMP_R) > 0.0 else rng.randf_range(0.9, 1.1))
	var look := Props.make(LUMP_GLB)
	look.name = "Look"
	look.scale = Vector3.ONE * size
	look.rotation.y = rng.randf() * TAU
	look.position.y = LUMP_LIFT
	var area := Area3D.new()
	area.add_to_group("crash_lumps")
	area.position = Vector3(at.x, world.foot_y(at.x, at.y, 1.0) - 0.05, at.y)
	area.monitorable = false
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = LUMP_R * size / LUMP_SCALE
	shape.height = 2.6
	col.shape = shape
	col.position.y = 0.8
	area.add_child(col)
	area.add_child(look)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.has_method("crash_lump"):
			b.crash_lump(area))
	holder.add_child(area)


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
