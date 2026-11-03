extends SceneTree
## 看板・旗・柱・お店の看板の、当たり判定と見た目の大きさの比べ（数字で）。
##   Godot --path game --headless -s res://tools/sign_hitbox_check.gd -- --bots=0 --lodge-bots=0 --no-pip --no-sound --dir=/path/out
## 物ごとに、見た目（MeshInstance3D を包む箱、世界の向き）と、その近く（見た目の箱を 0.6 m 広げた中）にある当たり判定の形
## （地形の HeightMapShape3D とロッジの当たり判定は除く）を出す。高さは物の足もと（節点の高さ）から。
## <dir>/sign_hitbox.txt に書く

var args := {}
var main: Node3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/sign_hitbox")


func _say(s: String) -> void:
	print(s)
	lines.append(s)


## 見た目の箱（世界）。見えない MeshInstance3D は数えない
static func visual_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for mi in list:
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## 当たり判定の形の箱（世界）と、形の名前
static func shape_info(cs: CollisionShape3D) -> Dictionary:
	var s := cs.shape
	var kind := s.get_class().trim_suffix("Shape3D")
	var dims := ""
	var local := AABB()
	if s is BoxShape3D:
		dims = "%.2f×%.2f×%.2f" % [s.size.x, s.size.y, s.size.z]
		local = AABB(-s.size / 2.0, s.size)
	elif s is CylinderShape3D:
		dims = "半径 %.2f 高さ %.2f" % [s.radius, s.height]
		local = AABB(Vector3(-s.radius, -s.height / 2.0, -s.radius), Vector3(s.radius * 2.0, s.height, s.radius * 2.0))
	elif s is CapsuleShape3D:
		dims = "半径 %.2f 高さ %.2f" % [s.radius, s.height]
		local = AABB(Vector3(-s.radius, -s.height / 2.0, -s.radius), Vector3(s.radius * 2.0, s.height, s.radius * 2.0))
	elif s is ConvexPolygonShape3D or s is ConcavePolygonShape3D:
		var pts: PackedVector3Array = s.points if s is ConvexPolygonShape3D else s.get_faces()
		for i in pts.size():
			local = AABB(pts[i], Vector3.ZERO) if i == 0 else local.expand(pts[i])
		dims = "%d 点" % pts.size()
	return {"kind": kind, "dims": dims, "aabb": cs.global_transform * local}


func _colliders_near(box: AABB, skip: Array) -> Array:
	var out := []
	var grown := box.grow(0.6)
	for cs in main.find_children("*", "CollisionShape3D", true, false):
		var c := cs as CollisionShape3D
		if c.disabled or c.shape == null or c.shape is HeightMapShape3D or c.shape is WorldBoundaryShape3D:
			continue
		var body := c.get_parent()
		if not (body is StaticBody3D):
			continue
		if body.get_parent() in skip:
			continue
		var info := shape_info(c)
		if c.shape is ConcavePolygonShape3D:   # ロッジの当たり判定は大きいので数えない
			continue
		if (info.aabb as AABB).intersects(grown):
			info["path"] = String(main.get_path_to(c))
			out.append(info)
	return out


func _report(name: String, n: Node3D, skip := []) -> void:
	if n == null:
		_say("%s: 見つからない" % name)
		return
	var v := visual_aabb(n)
	var g: float = n.global_position.y
	_say("%s  （%s）" % [name, String(main.get_path_to(n))])
	_say("  見た目: 幅 %.2f × 奥 %.2f、足もとから %.2f〜%.2f m" % [v.size.x, v.size.z, v.position.y - g, v.end.y - g])
	var cols := _colliders_near(v, skip)
	if cols.is_empty():
		_say("  当たり判定: なし（すり抜ける）")
	for c in cols:
		var a: AABB = c.aabb
		_say("  当たり判定: %s %s  幅 %.2f × 奥 %.2f、足もとから %.2f〜%.2f m   %s" % [c.kind, c.dims, a.size.x, a.size.z,
				a.position.y - g, a.end.y - g, c.path])


func _run() -> void:
	await create_timer(2.5).timeout
	await physics_frame
	_say("看板・旗・柱の当たり判定と見た目（雪面からの高さは、その物の真ん中の雪面から）")
	var seen := {}
	for n in main.find_children("*", "Node3D", true, false):
		var f := String((n as Node).scene_file_path)
		for key in ["sign_slope", "sign_lodge", "flag_red", "flag_navy", "net_span", "speaker_pole"]:
			if f.ends_with(key + ".glb"):
				seen[key] = int(seen.get(key, 0)) + 1
				if key in ["sign_slope", "sign_lodge"] or seen[key] <= 2:
					var target: Node3D = n
					if key == "speaker_pole":
						target = n.get_parent()
					_report("%s #%d" % [key, seen[key]], target)
	_say("（数: %s）" % str(seen))
	_say("")
	_say("お店の看板と、そのまわり")
	_report("型紙と布の売り子（頭の上の看板）", main.find_child("Shopkeeper", true, false))
	var ms := main.find_child("Shopkeeper", true, false)
	if ms:
		_report("  看板の板だけ", ms.find_child("MenuSign", true, false))
	var mm := main.find_child("MountainMan", true, false)
	if mm:
		var set_node := mm.get_node_or_null("Set")
		for c in (set_node.get_children() if set_node else []):
			if c is Node3D and not (c is StaticBody3D):
				_report("山師の " + String(c.name), c, [])
	var pl := main.find_child("PaperLady", true, false)
	if pl:
		_report("紙細工屋さんのスタンド", pl.get("stand"))
	for b in ["Bandai_counter_patch", "Bandai_counter_indigo"]:
		_report("番台 " + b, main.find_child(b, true, false))
	_report("雪だるまの冷蔵庫", main.find_child("SnowmanFridge", true, false))
	_report("厨房の品書きの板", main.find_child("MenuBoard", true, false))
	var f := FileAccess.open(_dir().path_join("sign_hitbox.txt"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	quit(0)
