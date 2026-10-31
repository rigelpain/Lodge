extends Node

const Doll := preload("res://doll.gd")
## ロッジの席の配り役。食堂の椅子・窓辺の丸椅子・炉を囲む長椅子・2 階のこたつの座布団に、F で座れる。
## 座る・立つは「誰が・どの席に・座った／立った」の短い出来事 {kind, who, seat, frame}（emotes.gd と同じ形）。
## 中身は数だけにして、そのまま通信に乗せられるようにする。seat は席の番号（seats の並び。同じ glb なら全員の画面で同じ）。
##   sit   {seat}   その席に座る（空いていなければ断る）
##   stand {seat}   その席から立つ
## いまは一人の画面の中だけ: send() がすぐ frame を付けて配る。通信を入れたら、ホストが席の空きを確かめてから全員に配る。
##
## 席はロッジの glb（lodge/build_lodge.py）の座面（素材 cushion の面）から、ゲームを始めたときに見つける。
## 家具は 1 つの形にまとめて書き出されていて、椅子ごとの名前がないので、面をつながったかたまりに分け、高さと形で見分ける。
## 向きは、座面の少し上から四方へ当たりを探り、机（窓辺のカウンター・こたつ）に当たる向き。長椅子は炉の灯りの目印（light_fire）の向き。
## ロッジの台本で家具を動かしても、書き出し直せばそのまま合う。
##
## 座る・立つの動き（人形と同じ 12 コマ／秒）: 席の立つ所（椅子の後ろ・長椅子の前）へ 3 コマで歩み寄って向きを変え、
## 1 コマ中腰、座る。立つときは中腰を 1 コマ挟んで、立つ所へ。居場所は place()、人形の姿勢は doll.gd の Act.SIT

signal happened(ev: Dictionary)

const REACH := 1.5           # 座れる、席までの距離 (m)
const BENCH_STEP := 0.75     # 長椅子に並ぶ間
const KOTATSU_PIT := 0.40    # 掘りごたつの穴の深さ（lodge/dims.py の PIT_DEPTH）。座布団の席の足はここまで下ろせる
const KOTATSU_HIPS := 0.32   # 座布団の席: 腰の所を、こたつ布団の縁からこれだけ手前に（穴の縁に腰かけ、脚を穴へ下ろす）
const STAND_BACK := {"chair": 0.62, "stool": 0.6, "bench": -0.6, "zabuton": 0.48}   # 立つ所: 席の後ろへ（負は前へ）
const STEP_IN := 3           # 歩み寄るコマ。その次の 1 コマが中腰
const SIT_IN := STEP_IN + 2  # 座りきるまでのコマ
const SIT_OUT := 2           # 立ちきるまでのコマ（中腰 1 コマ）

var lodge: Node3D
var seats: Array = []        # 席: {kind, pos（腰を下ろす座面の上、世界）, face（座って向く向き、水平）, floor（足を下ろす高さ）, stand（立つ所）}
var taken := {}              # 席の番号 → 座っている人の番号
var seat_of := {}            # 人の番号 → 席の番号
var _found := false


func _physics_process(_dt: float) -> void:
	if not _found and lodge:
		_found = true
		_find()


## 出来事を出す（いまはすぐ配る。通信ではホストへ）。断られたら false
func send(ev: Dictionary) -> bool:
	var who: int = ev.get("who", -1)
	var s: int = ev.get("seat", -1)
	if s < 0 or s >= seats.size():
		return false
	match ev.kind:
		"sit":
			if taken.has(s) or seat_of.has(who):
				return false
			taken[s] = who
			seat_of[who] = s
		"stand":
			if taken.get(s, -1) != who:
				return false
			taken.erase(s)
			seat_of.erase(who)
		_:
			return false
	ev = ev.duplicate()
	ev["frame"] = Doll.frame_index() + 1
	happened.emit(ev)
	return true


func seat(i: int) -> Dictionary:
	return seats[i] if i >= 0 and i < seats.size() else {}


## 立っている at（足もと）から look（見ている向き）で、座れる空いた席の番号。なければ -1。
## 近くて、見ている向きにある席を選ぶ（すぐそばなら向きは問わない）。床の高さが違う席（1 階と 2 階）は選ばない
func near(at: Vector3, look: Vector3) -> int:
	var best := -1
	var best_score := INF
	look.y = 0
	look = look.normalized()
	for i in seats.size():
		if taken.has(i):
			continue
		var s: Dictionary = seats[i]
		if absf(at.y - s.stand.y) > 0.6:
			continue
		var d: Vector3 = s.pos - at
		d.y = 0
		var dist := d.length()
		if dist > REACH:
			continue
		var facing := look.dot(d.normalized()) if dist > 0.05 else 1.0
		if dist > 0.7 and facing < 0.5:
			continue
		var score := dist - facing * 0.6
		if score < best_score:
			best_score = score
			best = i
	return best


## 空いた席のうち、at に近い順に最大 n 個（床の高さが at と同じもの）。仲間が座る席を選ぶ
func free_near(at: Vector3, n: int, max_d := 30.0) -> Array:
	var list := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		if taken.has(i) or absf(at.y - s.stand.y) > 0.6:
			continue
		var d: float = (s.stand - at).length()
		if d <= max_d:
			list.append([d, i])
	list.sort_custom(func(a, b): return a[0] < b[0])
	return list.slice(0, n).map(func(x): return x[1])


## 座る・立つの途中の居場所と姿勢の段。from は座ると決めたときの足もと、f はいまのコマ。
## 返り値 [居場所（足もと＝人形の付け根）, 段（0 立つ、1 中腰、2 座る）, 立ちきった]
static func place(s: Dictionary, from: Vector3, f: int, sit_f: int, stand_f: int) -> Array:
	if stand_f >= 0 and stand_f >= sit_f:
		var u := f - stand_f
		if u < 0:
			return [s.pos, 2, false]
		if u < SIT_OUT - 1:
			return [s.pos, 1, false]
		return [s.stand, 0, true]
	var k := f - sit_f
	if k < 0:
		return [from, 0, false]
	if k < STEP_IN:
		return [from.lerp(s.stand, (k + 1.0) / STEP_IN), 0, false]
	if k < SIT_IN - 1:
		return [s.pos, 1, false]
	return [s.pos, 2, false]


# ---------------------------------------------------------------- 席を見つける

func _find() -> void:
	var mi := lodge.find_child("lodge_props_interior", true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var to_lodge := lodge.global_transform.affine_inverse() * mi.global_transform
	var fire := lodge.find_child("light_fire", true, false) as Node3D
	var boxes: Array[AABB] = []
	for si in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(si)
		if m and m.resource_name == "cushion":
			boxes.append_array(_clusters(mi.mesh.surface_get_arrays(si), to_lodge))
	# 並びは、ロッジの座標の位置で決める（同じ glb なら全員の画面で同じ番号）
	boxes.sort_custom(func(a: AABB, b: AABB) -> bool:
		var ca := a.get_center()
		var cb := b.get_center()
		return ca.y < cb.y - 0.5 or (absf(ca.y - cb.y) <= 0.5 and (ca.z < cb.z - 0.05 or (absf(ca.z - cb.z) <= 0.05 and ca.x < cb.x))))
	var space := lodge.get_world_3d().direct_space_state
	for b in boxes:
		var c := b.get_center()
		var top := b.end.y
		var long := maxf(b.size.x, b.size.z)
		var kind := ""
		var floor_y: float = _floor_below(space, Vector3(c.x, top + 0.05, c.z), b.position.y)
		var h := top - floor_y
		if long > 1.0:
			kind = "bench"
		elif b.size.y <= 0.1 and h < 0.2:
			kind = "zabuton"
		elif h > 0.7:
			kind = "stool"
		elif h > 0.3:
			kind = "chair"
		else:
			continue
		if kind == "bench":
			# 長い向きに並べ、炉の向きを向く
			var along := Vector3.RIGHT if b.size.x >= b.size.z else Vector3.BACK
			var across := Vector3(along.z, 0, along.x)
			var to_fire := (lodge.to_local(fire.global_position) - c) if fire else across
			var face := across * signf(across.dot(to_fire))
			floor_y = _floor_below(space, c + face * 0.5 + Vector3.UP * (top - c.y), b.position.y)   # 長椅子の前の床
			var n := maxi(1, int(long / BENCH_STEP))
			for j in n:
				var p := c + along * (long * ((j + 0.5) / n - 0.5))
				_add(kind, Vector3(p.x, top, p.z), face, floor_y)
			continue
		var hit := _table_dir(space, Vector3(c.x, top + 0.12, c.z))
		if hit.is_empty():
			continue
		var face: Vector3 = hit[0]
		var p := Vector3(c.x, top, c.z)
		if kind == "zabuton":
			p += face * maxf(0.0, hit[1] - KOTATSU_HIPS)
			floor_y = b.position.y - KOTATSU_PIT
			_add(kind, p, face, floor_y, Vector3(c.x, b.position.y, c.z))
			continue
		_add(kind, p, face, floor_y)


## 席を足す（座標はロッジの座標で受け、世界にして持つ）。center は立つ所を測る中心（座布団は座布団のまんなか）
func _add(kind: String, p: Vector3, face: Vector3, floor_y: float, center := Vector3.INF) -> void:
	var c := center if center != Vector3.INF else Vector3(p.x, floor_y, p.z)
	var stand: Vector3 = c - face * STAND_BACK[kind]
	stand.y = c.y if center != Vector3.INF else floor_y
	var fw: Vector3 = lodge.global_basis * face
	fw.y = 0
	seats.append({
		"kind": kind,
		"pos": lodge.to_global(p),
		"face": fw.normalized(),
		"floor": lodge.to_global(Vector3(p.x, floor_y, p.z)).y,
		"stand": lodge.to_global(stand),
	})


## 面をつながったかたまりに分け、かたまりごとの箱（ロッジの座標）を返す。
## glTF は角で頂点を分けて書き出すので、同じ所にある頂点は 1 つと数える
static func _clusters(arr: Array, xf: Transform3D) -> Array[AABB]:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	var key_of := {}
	for i in vs.size():
		parent[i] = i
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	var join := func(a: int, b: int) -> void:
		var ra: int = find.call(a)
		var rb: int = find.call(b)
		if ra != rb:
			parent[ra] = rb
	for i in vs.size():
		var k := Vector3i((vs[i] * 500.0).round())
		if key_of.has(k):
			join.call(i, key_of[k])
		else:
			key_of[k] = i
	for t in range(0, idx.size() - 2, 3):
		join.call(idx[t], idx[t + 1])
		join.call(idx[t], idx[t + 2])
	var box := {}
	for i in vs.size():
		var r: int = find.call(i)
		var p := xf * vs[i]
		box[r] = (box[r] as AABB).expand(p) if box.has(r) else AABB(p, Vector3.ZERO)
	var out: Array[AABB] = []
	for b in box.values():
		out.append(b)
	return out


## 座面の少し上（ロッジの座標）から四方へ当たりを探り、机に当たる向き（ロッジの座標）と、その距離。なければ空
func _table_dir(space: PhysicsDirectSpaceState3D, at: Vector3) -> Array:
	var best := []
	for d in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var from := lodge.to_global(at)
		var q := PhysicsRayQueryParameters3D.create(from, lodge.to_global(at + d * 0.8))
		var hit := space.intersect_ray(q)
		if hit and (best.is_empty() or from.distance_to(hit.position) < best[1]):
			best = [d, from.distance_to(hit.position)]
	return best


## at（ロッジの座標）の真下の床の高さ（ロッジの座標）。見つからなければ fallback
func _floor_below(space: PhysicsDirectSpaceState3D, at: Vector3, fallback: float) -> float:
	var from := lodge.to_global(at)
	var q := PhysicsRayQueryParameters3D.create(from, lodge.to_global(at + Vector3.DOWN * 2.0))
	var hit := space.intersect_ray(q)
	return lodge.to_local(hit.position).y if hit else fallback
