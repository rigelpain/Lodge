extends Node3D
## ソリの立てかけ台（2026-11-04 代表「ソリ屋の隣に今困ってるソリ放置問題を解決するために、ソリ立てかけスペースにインタラクトして、
## だれも触ってない状態の自分がオーナーのソリを立てかけ台に戻したり、持ってきてしまったりできるようにしたい」）。
## 形は design/sled-rack（刺繍枠の衝立・枠のあいだの糸巻き・物差しの横木・床の板に刺した待ち針のストッパー）。目印 slot_sled_rack（lodge/dims.py）の子。
## この節の座標: +Z が人の側（前）、X に長い。原点は足もとの縁のまんなかの雪の上。
## ソリは鼻を上に、裏を物差しへ向けて LEAN で立てかける。背は大（4.8 m）で約 4.2 m（下屋の屋根の下に収まる）。
## 大きさごとの幅で、端から空いた所に詰めて並べる（縫い分けはしない）。戻す・持ち出すの出来事は craft.gd の rack_in・rack_out

const Sled := preload("res://sled.gd")
const Props := preload("res://props.gd")

const LEAN := PI / 3.0              # 立てかける角度（雪の面から）
const LEN := 9.6                    # 並べられる長さ (m)。2026-11-07 に 12 m から、布の見本帳の幅のぶん短くした（代表「ソリ立てちょっと幅減らしても良いかも」「見本帖の大きさ分」）
const SLOT_SHIFT := 1.2              # 目印 slot_sled_rack（12 m の台のまんなか）からずらす (m)。南の端（ミシンの側）を前の位置に残し、北の端を詰める
const WIDTHS := {"small": 0.95, "mid": 1.7, "large": 2.4}   # 1 台が取る幅。大は 4 台、小は 10 台
const USE_Z := Vector2(0.6, 4.2)    # F が届く前の奥行き (m)
const USE_X := 0.8                  # 両端の外へ届く分 (m)
const USE_FACE := 0.2               # 台の方を向いている（見ている向きと台の奥の向きの合い具合）
const OUT_Z := 2.9                  # 持ち出したソリを置く、足もとの縁からの距離 (m)。人が通れて、大も柱の台に当たらない
const OUT_TRY := [0.0, -3.0, 3.0, -6.0, 6.0]   # 持ち出す所がふさがっていたら、横へずらす

## [大きさ, 中心, 高さ] と、ぶつかる所。glb の形に合わせた箱（土台・衝立・物差し）
const BOXES := [
	[Vector3(10.4, 0.2, 1.5), Vector3(0, 0.1, -1.25)],     # 土台
	[Vector3(10.4, 0.45, 0.24), Vector3(0, 0.225, 0.46)],  # 手前の床の板に刺した、ストッパーの待ち針の列
	[Vector3(10.0, 2.5, 0.2), Vector3(0, 1.25, -1.72)],    # 刺繍枠の衝立
	[Vector3(10.1, 0.25, 0.3), Vector3(0, 1.1, -0.8)],     # 物差しと糸巻き
]


func _ready() -> void:
	position.x = SLOT_SHIFT
	var g := Props.make("res://props/sled_rack/sled_rack.glb")
	g.rotation.y = PI      # 模型の正面は -Z
	add_child(g)
	var body := StaticBody3D.new()
	body.name = "RackBody"
	for b in BOXES:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = b[0]
		col.shape = box
		col.position = b[1]
		body.add_child(col)
	add_child(body)


## 大きさ kind の置き場の中心（X）。taken は置いてある物 [[中心, 幅], ...]。空きがなければ NAN
static func fit(kind: String, taken: Array) -> float:
	var w: float = WIDTHS.get(kind, WIDTHS.large)
	var x := LEN / 2.0 - w / 2.0
	var moved := true
	while moved:
		moved = false
		for t in taken:
			if absf(float(t[0]) - x) < (float(t[1]) + w) / 2.0 - 0.001:
				x = float(t[0]) - (float(t[1]) + w) / 2.0
				moved = true
	return x if x - w / 2.0 >= -LEN / 2.0 - 0.001 else NAN


## 中心 u に立てかけたソリの姿（世界の座標）。ソリの原点は箱の底のまんなか、鼻は -Z
func lean_at(kind: String, u: float) -> Transform3D:
	var L: float = Sled.KINDS.get(kind, Sled.KINDS.mid).box.z
	var b := Basis(Vector3.RIGHT, LEAN)
	return global_transform * Transform3D(b, Vector3(u, 0.03, 0.0) + b * Vector3(0, 0, -L / 2.0))


## 持ち出したソリを置く所（世界の座標。向きは台に沿って）。ふさがっていれば横へずらし、どこも空かなければ Vector3.INF を origin に入れて返す
func out_at(kind: String, u: float, world: Node3D) -> Transform3D:
	var k: Dictionary = Sled.KINDS.get(kind, Sled.KINDS.mid)
	var half := LEN / 2.0
	for dx in OUT_TRY:
		var loc := Vector3(clampf(u + float(dx), -half, half), 0, OUT_Z)
		var p := to_global(loc)
		if world.has_method("height"):
			p.y = world.height(p.x, p.z)
		var xf := Transform3D(global_basis * Basis(Vector3.UP, -PI / 2.0), p)
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = k.box
		q.shape = box
		q.transform = Transform3D(xf.basis, p + Vector3.UP * (k.box.y * 0.5 + 0.3))
		var clear := true
		for r in world.get_world_3d().direct_space_state.intersect_shape(q, 8):
			if not r.collider is CharacterBody3D:   # 人はよけてもらう（craft.gd の _make_room）
				clear = false
		if clear:
			return xf
	return Transform3D(Basis(), Vector3.INF)


## F が届く所にいるか（向きは見ない）
func in_reach(who: Node3D) -> bool:
	if who == null:
		return false
	var l := to_local(who.global_position)
	return absf(l.x) < LEN / 2.0 + USE_X and l.z > USE_Z.x and l.z < USE_Z.y and absf(l.y) < 2.0


## F が届く所で、台の方を向いているか
func can_use(who: Node3D) -> bool:
	return in_reach(who) and (-who.global_basis.z).dot(-global_basis.z) > USE_FACE
