extends Node

const Doll := preload("res://doll.gd")
## ロッジの席の配り役。食堂の椅子・窓辺の丸椅子・暖炉のまわりのソファ・揺り椅子・ビーズクッション・2 階のこたつの座布団に、F で座れる。
## 座る・立つは「誰が・どの席に・座った／立った」の短い出来事 {kind, who, seat, frame}（emotes.gd と同じ形）。
## 中身は数だけにして、そのまま通信に乗せられるようにする。seat は席の番号（seats の並び。同じ glb なら全員の画面で同じ）。
##   sit   {seat}   その席に座る（空いていなければ断る）
##   stand {seat}   その席から立つ
## いまは一人の画面の中だけ: send() がすぐ frame を付けて配る。通信を入れたら、ホストが席の空きを確かめてから全員に配る。
##
## 席はロッジの glb（lodge/build_lodge.py）の座面（素材 cushion の面）から、ゲームを始めたときに見つける。
## 家具は 1 つの形にまとめて書き出されていて、椅子ごとの名前がないので、面をつながったかたまりに分け、高さと形で見分ける。
## 向きは、座面の少し上から四方へ当たりを探り、机（窓辺のカウンター）に当たる向き。長椅子は炉の灯りの目印（light_fire）の向き。
## 暖炉のまわりの家具（hearth_nook.gd）は、座る所の目印 nook_seat_<番号>（-Z が座って向く向き。種類・高さ・奥行き・揺れは目印の meta）。
##   sofa: 何人かで並ぶ（座る所が人数分）、rocker: 座りきると前後に揺れる、beanbag: 沈み込み、うしろへもたれる
## 2 階の座布団は、こたつの組（props/sets/kotatsu_lodge_*。main.gd が slot_kotatsu_* に置く）の座る所の目印 sit_<番号>
## （目印の -Z がこたつの側、大きさは座布団の幅・厚み・奥行き）。
## ロッジの台本で家具を動かしても、書き出し直せばそのまま合う。
##
## 座る・立つの動き（人形と同じ 12 コマ／秒）: 席の立つ所（椅子の後ろ・長椅子の前）へ 3 コマで歩み寄って向きを変え、
## 1 コマ中腰、座る。立つときは中腰を 1 コマ挟んで、立つ所へ。居場所は place()、人形の姿勢は doll.gd の Act.SIT

signal happened(ev: Dictionary)

const REACH := 1.5           # 座れる、席までの距離 (m)
const BENCH_STEP := 0.75     # 長椅子に並ぶ間
const KOTATSU_PIT := 0.40    # 掘りごたつの穴の深さ（lodge/dims.py の PIT_DEPTH）。座布団の席の足はここまで下ろせる
const KOTATSU_HIPS := 0.56   # 座布団の席: 腰の所を、こたつ（天板と垂れた布団）の縁からこれだけ手前に（座布団に腰かけ、脚を穴へ下ろす。大きな人形の腹が天板に当たらない）
const STAND_BACK := {"chair": 0.62, "stool": 0.6, "bench": -0.6, "zabuton": 0.48,
		"sofa": -1.0, "rocker": -0.95, "beanbag": 0.95}   # 立つ所: 席の後ろへ（負は前へ）。ビーズクッションはラグの上でまわりを囲まれるので、うしろ（部屋の側）から乗り込む
const ROCK_EASE := 18        # 揺り椅子: 座りきってから、揺れが大きくなりきるまでのコマ
const LEAN_EASE := 3         # ビーズクッション: 座りきってから、もたれきるまでのコマ
const STEP_IN := 3           # 歩み寄るコマ。その次の 1 コマが中腰
const SIT_IN := STEP_IN + 2  # 座りきるまでのコマ
const SIT_OUT := 2           # 立ちきるまでのコマ（中腰 1 コマ）

var lodge: Node3D
var seats: Array = []        # 席: {kind, pos（腰を下ろす座面の上、世界）, face（座って向く向き、水平）, floor（足を下ろす高さ）, stand（立つ所）,
                             #      edge（pos から座面の前の縁までの奥行き、m）, size（座面の幅と奥行き、m）}
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


## 空いた席のうち、at に近い順に最大 n 個（床の高さが at と同じもの）。仲間が座る席を選ぶ。kinds を決めると、その種類の席だけ
func free_near(at: Vector3, n: int, max_d := 30.0, kinds := []) -> Array:
	var list := []
	for i in seats.size():
		var s: Dictionary = seats[i]
		if taken.has(i) or absf(at.y - s.stand.y) > 0.6 or (not kinds.is_empty() and not s.kind in kinds):
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


## 席といっしょに体ごと傾く角 (rad。正でうしろへ)。揺り椅子は座りきってから前後に揺れ、ビーズクッションはうしろへもたれる。
## 揺れは全員の画面で同じコマの時計（Doll.frame_index）から決まるので、通信で揃えなくても同じ形になる。
## f はいまのコマ、sit_f・stand_f は座る・立つ出来事のコマ（立っていなければ stand_f は -1）
static func rock_of(s: Dictionary, f: int, sit_f: int, stand_f: int) -> float:
	if not s.has("rock_axis") or (stand_f >= 0 and f >= stand_f):
		return 0.0
	var k := f - sit_f - (SIT_IN - 1)   # 座りきってからのコマ
	if k < 0:
		return 0.0
	var a: float = float(s.get("rock_lean", 0.0)) * minf(1.0, float(k + 1) / LEAN_EASE)
	var amp: float = float(s.get("rock_amp", 0.0))
	if amp > 0.0:
		var period: float = float(s.get("rock_period", 2.0)) * 12.0
		a += amp * minf(1.0, float(k + 1) / ROCK_EASE) * sin(TAU * float(f) / period + float(s.get("rock_phase", 0.0)))
	return a


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
				_add(kind, Vector3(p.x, top, p.z), face, floor_y, _edge(b, p, face), (along * BENCH_STEP + across * (b.size.x + b.size.z - long)).abs())
			continue
		var hit := _table_dir(space, Vector3(c.x, top + 0.12, c.z))
		if hit.is_empty():
			continue
		var face: Vector3 = hit[0]
		var p := Vector3(c.x, top, c.z)
		if kind == "zabuton":
			_add_zabuton(b, face, hit[1])
			continue
		_add(kind, p, face, floor_y, _edge(b, p, face), b.size)
	# 暖炉のまわりの家具（hearth_nook.gd の目印。名前の番号の順）
	var nook := lodge.find_children("nook_seat_*", "Node3D", true, false)
	nook.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for m: Node3D in nook:
		_add_nook(m)
	# 2 階の座布団（こたつの組の目印）。2 階なので、並びは 1 階の席のあと。奥（-Z）から、西から
	var marks := lodge.find_children("sit_*", "Node3D", true, false)
	var at_of := func(m: Node3D) -> Vector3: return lodge.to_local(m.global_position)
	marks.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var ca: Vector3 = at_of.call(a)
		var cb: Vector3 = at_of.call(b)
		return ca.z < cb.z - 0.05 or (absf(ca.z - cb.z) <= 0.05 and ca.x < cb.x))
	for m: Node3D in marks:
		var top: Vector3 = at_of.call(m)
		var size := m.scale.abs()
		var b := AABB(top - Vector3(size.x * 0.5, size.y, size.z * 0.5), size)
		var face := lodge.global_basis.inverse() * -m.global_basis.z
		face.y = 0
		var hit := _table_dir(space, top + Vector3.UP * 0.12, [face.normalized()])
		if hit.is_empty():
			continue
		_add_zabuton(b, hit[0], hit[1])


## 暖炉のまわりの家具の席: 目印の所が腰を下ろす所、-Z が座って向く向き。meta は
##   kind（sofa・rocker・beanbag）、height（腰の所から足を下ろす床まで、m）、edge（腰の所から座面の前の縁まで）、size（座面の幅と奥行き）、back（腰の所から背もたれまで）、
##   rock_amp・rock_period・rock_phase・rock_pivot・rock_roll（揺り椅子: 揺れの角・周期 s・ずれ・弓の円の中心（目印の座標）・弓が床を転がる半径）、rock_lean（もたれる角）
func _add_nook(m: Node3D) -> void:
	var kind: String = m.get_meta("kind", "sofa")
	var p := lodge.to_local(m.global_position)
	var face := lodge.global_basis.inverse() * -m.global_basis.z
	face.y = 0
	face = face.normalized()
	var k := lodge.global_basis.get_scale().x
	var size: Vector2 = m.get_meta("size", Vector2(0.6, 0.5))
	var floor_y := p.y - float(m.get_meta("height", 0.45)) / k
	_add(kind, p, face, floor_y, float(m.get_meta("edge", 0.2)) / k, Vector3.ZERO)
	var st: Dictionary = seats[-1]
	st.size = size
	st["back"] = float(m.get_meta("back", 0.3)) * k   # 腰の所から背もたれの前の面まで
	if m.has_meta("rock_amp") or m.has_meta("rock_lean"):
		var fw: Vector3 = st.face
		st["rock_axis"] = fw.cross(Vector3.UP).normalized()
		st["rock_at"] = m.to_global(m.get_meta("rock_pivot", Vector3.ZERO))
		st["rock_amp"] = float(m.get_meta("rock_amp", 0.0))
		st["rock_period"] = float(m.get_meta("rock_period", 2.0))
		st["rock_phase"] = float(m.get_meta("rock_phase", 0.0))
		st["rock_lean"] = float(m.get_meta("rock_lean", 0.0))
		st["rock_roll"] = float(m.get_meta("rock_roll", 0.0)) * m.global_basis.get_scale().y   # 世界の長さに


## 座布団の席: 腰の所を、こたつ（布団と天板の当たり）から KOTATSU_HIPS 手前まで前へ出し、足は穴の底まで下ろせる
func _add_zabuton(b: AABB, face: Vector3, hit: float) -> void:
	var c := b.get_center()
	var p := Vector3(c.x, b.end.y, c.z) + face * maxf(0.0, hit - KOTATSU_HIPS)
	_add("zabuton", p, face, b.position.y - KOTATSU_PIT, _edge(b, p, face), b.size, Vector3(c.x, b.position.y, c.z))


## p（ロッジの座標）から face の向きに、座面の箱 b の前の縁までの奥行き (m)。座布団で縁を越えていれば 0
static func _edge(b: AABB, p: Vector3, face: Vector3) -> float:
	var half := absf(face.dot(b.size)) * 0.5
	return maxf(0.0, (b.get_center() - p).dot(face) + half)


## 席を足す（座標はロッジの座標で受け、世界にして持つ）。size は座面の箱の大きさ（ロッジの座標）。center は立つ所を測る中心（座布団は座布団のまんなか）
func _add(kind: String, p: Vector3, face: Vector3, floor_y: float, edge: float, size: Vector3, center := Vector3.INF) -> void:
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
		"edge": edge * lodge.global_basis.get_scale().x,
		"size": Vector2(absf(face.cross(Vector3.UP).dot(size)), absf(face.dot(size))) * lodge.global_basis.get_scale().x,
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


## 座面の少し上（ロッジの座標）から四方（dirs）へ当たりを探り、机に当たる向き（ロッジの座標）と、その距離。なければ空
func _table_dir(space: PhysicsDirectSpaceState3D, at: Vector3, dirs := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]) -> Array:
	var best := []
	for d in dirs:
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
