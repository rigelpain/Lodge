extends SceneTree
## 壁の灯り（松明・ガス灯）の裏に壁があるか、吊りの車輪の縄の先に天井があるかを測る（確かめ用）。
##   Godot --headless --path game -s res://tools/lodge_light_walls.gd [-- --csv=/path/out.csv]
## ロッジ（lodge.tscn）だけを置き、灯りの付け根から裏へ光線を飛ばす。座金の真ん中と四隅の 5 本。
## 当たり判定（lodge_collision.glb）と、見た目の面（lodge.glb から作った当たり）の両方で測る。
## 当たり判定の壁が座金から 3 cm より遠い・当たらない、見た目の丸太が座金の裏の木の台（BACKING）より遠い物を「浮いている」、
## 当たり判定の壁が付け根より 5 cm 以上手前にある物を「埋まっている」とし、1 つでもあれば終わりの値を 1 にする。
## 吊りの車輪は、縄の先から上へ光線を飛ばし、見た目の天井まで 3 cm より遠ければ浮いている（垂木に 35 cm までは刺さってよい）。

const GAP := 0.03          # 座金と壁のすき間がこれより大きいと浮いている
const PLATE := Vector2(0.09, 0.17)   # 座金の半分の幅と高さ（torch。gas は少し小さいが同じで測る）
const VIS := 2             # 見た目の面から作った当たりの層

var lodge: Node3D
var frames := 0


func _initialize() -> void:
	lodge = load("res://lodge/lodge.tscn").instantiate()
	root.add_child(lodge)
	for mi: MeshInstance3D in lodge.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()
		for c in mi.get_children():
			if c is StaticBody3D:
				c.collision_layer = 1 << (VIS - 1)


func _physics_process(_dt: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var bad := 0
	var rows := ["i,kind,x,y,z,deg,col_center,col_worst,vis_center,vis_worst,state"]
	var space := lodge.get_world_3d().direct_space_state
	var ll: GDScript = load("res://lodge_lights.gd")
	var has_places := ll.get_script_method_list().any(func(m: Dictionary) -> bool: return m.name == "places")
	var places: Array = ll.call("places") if has_places else ll.get_script_constant_map()["PLACES"]
	var backing: float = ll.get_script_constant_map().get("BACKING", 0.0)
	for i in places.size():
		var p: Array = places[i]
		var kind: String = p[0]
		var at: Vector3 = p[1]
		var g := lodge.global_transform * Vector3(at.x, at.z, -at.y)
		if kind == "torch" or kind == "gas":
			var b := Basis(Vector3.UP, deg_to_rad(p[2]))
			var front := b * Vector3(0, 0, 1)
			var side := b * Vector3(1, 0, 0)
			var res := []
			for mask in [1, 1 << (VIS - 1)]:
				var center := _back(space, g, front, mask)
				var worst := center
				for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					var d := _back(space, g + side * c.x * PLATE.x + Vector3.UP * c.y * PLATE.y, front, mask)
					worst = maxf(worst, d)
				res.append_array([center, worst])
			var state := "ok"
			if res[1] > GAP or res[3] > backing + 0.01:
				state = "FLOAT"
			elif res[0] < -0.05:
				state = "BURIED"
			if state != "ok":
				bad += 1
			rows.append("%d,%s,%.2f,%.2f,%.2f,%.0f,%.3f,%.3f,%.3f,%.3f,%s" % [i, kind, at.x, at.y, at.z, p[2], res[0], res[1], res[2], res[3], state])
		elif kind == "wheel":
			var top := g + Vector3(0, p[3], 0)
			var up := []
			for mask in [1, 1 << (VIS - 1)]:
				var q := PhysicsRayQueryParameters3D.create(top - Vector3(0, 0.3, 0), top + Vector3(0, 3.0, 0), mask)
				var hit := space.intersect_ray(q)
				up.append(hit.position.y - top.y if hit else 99.0)
			var ok: bool = up[1] <= GAP and up[1] >= -0.35
			if not ok:
				bad += 1
			rows.append("%d,%s,%.2f,%.2f,%.2f,%.0f,%.3f,,%.3f,,%s" % [i, kind, at.x, at.y, at.z, p[2], up[0], up[1], "ok" if ok else "FLOAT"])
	for r in rows:
		print(r)
	print("浮いている・埋まっている: %d" % bad)
	var a := OS.get_cmdline_user_args()
	for s in a:
		if s.begins_with("--csv="):
			var f := FileAccess.open(s.trim_prefix("--csv="), FileAccess.WRITE)
			f.store_string("\n".join(rows) + "\n")
	quit(1 if bad > 0 else 0)
	return true


## 付け根 g から裏（-front）へ飛ばし、壁の面が付け根からどれだけ裏にあるか（m）。当たらなければ 99。
## 付け根より手前（部屋の側）に壁があれば負（壁に埋まっている）
func _back(space: PhysicsDirectSpaceState3D, g: Vector3, front: Vector3, mask: int) -> float:
	var q := PhysicsRayQueryParameters3D.create(g + front * 0.25, g - front * 1.5, mask)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return (g - hit.position).dot(front)
