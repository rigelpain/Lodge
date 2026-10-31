extends SceneTree
## ロッジの席に座った姿を撮り、脚や体が机の天板・床を突き抜けていないかを数える（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/seat_shots.gd -- --seat=chair|stool|bench|zabuton [--n=番目] [--out=DIR]
## あなた（笠の人形）と、ロッジでくつろぐ仲間 2 人（折り紙・新聞紙）を、同じ種類の隣り合う席に座らせる。
## 撮るのは一人称・三人称（どちらも右下の小窓つき）と、前と横からの近写し。--hands=high_R などで、座ったまま手を掲げた姿に
## 突き抜けは、人形の形を骨で曲げた頂点（CPU で計算）で数える: 席の向いた先の机の天板の厚みの中に入った頂点と、床より下の頂点

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var _step := 0
var _seat := -1
var _out := ""
var _shot_at := 0.0
var _side_list := []
var _side_k := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = args.get("out", "/tmp")
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 45
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)   # 世界と体と飾り（一人称の手は映さない）
	root.add_child(cam)


func _process(dt: float) -> bool:
	t += dt
	var p = main.player
	var seats = main.seats
	if p == null or seats == null or seats.seats.is_empty() or t < 1.0:
		return false
	if main.settings:
		main.settings.set_open(false)
	match _step:
		0:
			_step = 1
			_report_seats(seats)
			_sit_all(p, seats)
			_shot_at = t + 1.5
		1:
			if t >= _shot_at:
				_check(p, seats)
				if args.has("hands"):   # 座ったまま手を掲げる（身ぶりが使えるかを見る）
					main.emotes.send({"kind": "hands", "who": p.id, "hands": args["hands"]})
				p.set_third(false)
				p.cam.current = true
				_step = 2
				_shot_at = t + 0.6
		2:
			if t >= _shot_at:
				_save("fp")
				p.set_third(true)
				_step = 3
				_shot_at = t + 0.8
		3:
			if t >= _shot_at:
				_save("third")
				var st: Dictionary = seats.seat(_seat)
				var c: Vector3 = st.pos + Vector3.UP * 0.2
				cam.look_at_from_position(c + st.face * 2.4 + Vector3.UP * 0.9, c)
				cam.current = true
				main.hud.visible = false
				_step = 4
				_shot_at = t + 0.6
		4:
			if t >= _shot_at:
				_save("front")
				_side_list = seats.seat_of.keys()
				_step = 5
				_shot_at = t
		5:
			# 一人ずつ真横から（ほかの人は隠す）。机の天板の裏と膝・腿が見える高さで
			if t >= _shot_at:
				if _side_k > 0:
					_save("side_%s" % main.emotes.who_of(_side_list[_side_k - 1]).doll.kind)
				if _side_k >= _side_list.size():
					return true
				var who: int = _side_list[_side_k]
				for w in _side_list:
					main.emotes.who_of(w).visible = w == who
				var st: Dictionary = seats.seat(seats.seat_of[who])
				var side: Vector3 = st.face.cross(Vector3.UP)
				var c: Vector3 = st.pos + Vector3.UP * 0.15 + st.face * 0.25
				cam.look_at_from_position(c + side * float(args.get("dist", "1.9")) + Vector3.UP * 0.05, c)
				_side_k += 1
				_shot_at = t + 0.5
	return false


func _report_seats(seats) -> void:
	var by := {}
	for s in seats.seats:
		by[s.kind] = by.get(s.kind, 0) + 1
	print("席: ", by, " 合わせて ", seats.seats.size())


## あなたと仲間を、選んだ種類の隣り合う席に座らせる
func _sit_all(p, seats) -> void:
	var kind: String = args.get("seat", "chair")
	var list := []
	for i in seats.seats.size():
		if seats.seats[i].kind == kind:
			list.append(i)
	var n := clampi(int(args.get("n", str(list.size() / 2))), 0, list.size() - 1)
	# いま座っている人をいったん立たせる
	for who in seats.seat_of.keys():
		seats.taken.erase(seats.seat_of[who])
		seats.seat_of.erase(who)
	_seat = list[n]
	var st: Dictionary = seats.seat(_seat)
	# 立つ所で席の方を向くと、座れる席に選ばれるか（案内が出るか）
	p.global_position = st.stand + Vector3.UP * 0.05
	p.rotation.y = atan2(-(st.pos - st.stand).x, -(st.pos - st.stand).z)
	print("立つ所からの席の選び: ", p.seats.near(st.stand, -p.global_basis.z), "（座る席 ", _seat, "）")
	seats.send({"kind": "sit", "who": p.id, "seat": _seat})
	var bots := main.get_children().filter(func(c): return c.get("lounge") == true)
	var others: Array = seats.free_near(st.stand, 6, 4.0).filter(func(i): return seats.seat(i).kind == kind)
	for k in bots.size():
		var b = bots[k]
		if k >= others.size():
			break
		var o: Dictionary = seats.seat(others[k])
		if b.seat_i >= 0:
			b.seat_i = -1
		b._started = true
		b.global_position = o.stand + Vector3.UP * 0.05
		seats.send({"kind": "sit", "who": b.id, "seat": others[k]})


## 座っている人ごとに、骨で曲げた形の頂点が机の天板の厚みと床に入っていないかを数える
func _check(p, seats) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for who in seats.seat_of:
		var person = main.emotes.who_of(who)
		var st: Dictionary = seats.seat(seats.seat_of[who])
		var doll = person.doll
		var top := -INF
		var edge := INF
		# 机: 席の向いた先へ当たりを探り、当たった所の少し奥の真上から天板の上の面を探す
		var q := PhysicsRayQueryParameters3D.create(st.pos + Vector3.UP * 0.12, st.pos + Vector3.UP * 0.12 + st.face * 1.2)
		q.exclude = [person.get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			edge = (hit.position - st.pos).dot(st.face)
			var q2 := PhysicsRayQueryParameters3D.create(hit.position + st.face * 0.1 + Vector3.UP * 1.0, hit.position + st.face * 0.1 + Vector3.DOWN * 0.3)
			var h2 := space.intersect_ray(q2)
			if h2:
				top = h2.position.y
		var board := 0.05 if st.kind != "stool" else 0.06
		var in_board := 0
		var deepest := 0.0
		var below := 0
		var lowest := 0.0
		var thigh_top := -INF
		for v in _skinned(doll):
			var along: float = (v - st.pos).dot(st.face)
			if top > -INF and along > edge and v.y < top and v.y > top - board:
				in_board += 1
				deepest = maxf(deepest, v.y - (top - board))
			if top > -INF and along > edge and v.y <= top - board:
				thigh_top = maxf(thigh_top, v.y)
			if st.kind != "zabuton" and v.y < st.floor - 0.01:
				below += 1
				lowest = minf(lowest, v.y - st.floor)
		print("%s（%s）席 %d %s: 座面 %.2f m、机の天板 %s、天板の厚みに入った頂点 %d（いちばん深く %.3f m）、机の下の体のいちばん上 %s、床より下の頂点 %d（%.3f m）" % [
			doll.kind, "あなた" if person == p else "仲間", seats.seat_of[who], st.kind, st.pos.y - st.floor,
			("%.2f m（縁まで %.2f m）" % [top - st.floor, edge]) if top > -INF else "なし", in_board, deepest,
			("%.2f m" % (thigh_top - st.floor)) if thigh_top > -INF else "-", below, lowest])


## 人形の形の頂点を、いまの骨の姿勢で曲げて世界の座標で返す（Godot は GPU で曲げるので、同じ計算を CPU で）
func _skinned(doll) -> PackedVector3Array:
	var out := PackedVector3Array()
	var skel: Skeleton3D = doll.skel
	for m in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.skin == null:
			continue
		var skin := mi.skin
		var bind_xf := []
		for b in skin.get_bind_count():
			var bi := skin.get_bind_bone(b)
			if bi < 0:
				bi = skel.find_bone(skin.get_bind_name(b))
			bind_xf.append(skel.get_bone_global_pose(bi) * skin.get_bind_pose(b))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per: int = bones.size() / vs.size()
			for vi in vs.size():
				var acc := Vector3.ZERO
				var wsum := 0.0
				for j in per:
					var w: float = weights[vi * per + j]
					if w <= 0.0:
						continue
					acc += (bind_xf[bones[vi * per + j]] as Transform3D) * vs[vi] * w
					wsum += w
				if wsum > 0.0:
					out.append(skel.global_transform * (acc / wsum))
	return out


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/seat_%s_%s.png" % [_out, args.get("seat", "chair"), name]
	img.save_png(path)
	print("撮った: ", path)
