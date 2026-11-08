extends SceneTree
## ロッジの 1 階・2 階の床の上で、仲間（CPU）の体（半径 0.35 の筒）が立てる所を 0.5 m おきに調べて、字の地図にする（寄り道の道の点を決める用）。
##   Godot --headless --path game -s res://tools/lodge_floor_map.gd -- --no-sound
## 座標はロッジの glb の座標（x 東、z 南。+Z が正面＝ゲレンデ）。. 立てる、# ふさがる、空白は床がない（その階の高さの範囲に）。
## --mark=x,z;x,z… を付けると、その所を数字で描く（道の点の確かめ）

const STEP := 0.5

var main: Node3D
var t := 0.0
var args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _physics_process(dt: float) -> bool:
	t += dt
	if t < 2.0:
		return false
	var lodge: Node3D = main.get_node("Lodge")
	var space := main.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	q.shape = cap
	var marks := {}
	if args.has("mark"):
		var i := 0
		for p in String(args.mark).split(";"):
			var xz := p.split(",")
			marks[Vector2i(roundi(float(xz[0]) / STEP), roundi(float(xz[1]) / STEP))] = str(i % 10)
			i += 1
	for fl in [[0.0, 2.6, "1 階"], [4.5, 8.5, "2 階"]]:
		print("---- ", fl[2], "（x -24〜24 を左から右、z -14〜30 を上から下。1 字 0.5 m）")
		var z := -14.0
		while z <= 30.0:
			var row := ""
			var x := -24.0
			while x <= 24.0:
				var top := lodge.to_global(Vector3(x, fl[1], z))
				var bot := lodge.to_global(Vector3(x, fl[0] - 1.0, z))
				var rq := PhysicsRayQueryParameters3D.create(top, bot)
				var hit := space.intersect_ray(rq)
				var ch := " "
				if hit:
					var ly: float = lodge.to_local(hit.position).y
					if ly >= fl[0] - 0.6:
						q.transform = Transform3D(Basis.IDENTITY, hit.position + Vector3.UP * (0.08 + 0.85))
						ch = "#" if not space.intersect_shape(q, 1).is_empty() else "."
				var k := Vector2i(roundi(x / STEP), roundi(z / STEP))
				if marks.has(k):
					ch = marks[k]
				row += ch
				x += STEP
			print("%6.1f %s" % [z, row])
			z += STEP
	quit()
	return true
