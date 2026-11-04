extends SceneTree
## 紙細工屋さんのテントを確かめて撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/paper_tent_shots.gd -- --part=measure --bots=0 --no-sound --no-pip --dir=/path/shots
##   --part=measure  婦人のまわりの壁や家具までの距離を測って書き、真上から撮る
##   --part=idea --glb=/path/tent.glb --tag=A0 [--glow=0.45] [--top]  案の glb（person/ideas/kamizaiku/tent_ideas.py）を売り場に置いて撮る
##   --part=still  幕の開き具合を決めて止めて撮る（閉じた・途中・開いた。正面・客の立つ所・斜め。後ろの壁との隙間も）
##   --part=walk   あなたが前 8 m から歩いて来て、また離れる。12 コマごとに撮り（walk_000.png …）、幕の開き・婦人の動きを書く。--fixed-fps 30 で
##   --part=bump   壁の当たりを確かめる: まわりからテントへ歩いて止まる所と、壁に沿って歩けるか。1 階の真下と壁の向こうで開かないかも見る

const Props := preload("res://props.gd")
const TENT_AT := Vector3(0.85, 0.0, -0.085)
const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/paper-tent")


func _shot(name: String, from: Vector3, to: Vector3, fov := 55.0) -> void:
	var lady: Node3D = main.paper_lady
	cam.look_at_from_position(lady.to_global(from), lady.to_global(to), Vector3.UP)
	cam.fov = fov
	cam.make_current()
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(_dir().path_join(name + ".png"))
	print("撮った ", name)


func _run() -> void:
	await create_timer(3.0).timeout
	var lady: Node3D = main.paper_lady
	var dc := root.get_node_or_null("DayCycle")
	if dc:
		dc.hour = float(args.get("hour", "13"))
		dc.day_seconds = 1.0e9
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	cam = Camera3D.new()
	main.add_child(cam)
	cam.cull_mask = (1 << 0) | (1 << 1) | (1 << 3)
	cam.near = 0.05
	cam.current = true
	match args.get("part", "measure"):
		"idea":
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			doc.append_from_file(args.glb, st)
			var t: Node3D = doc.generate_scene(st)
			Props.dress(t)
			for mi in t.find_children("*", "MeshInstance3D", true, false):
				var m: MeshInstance3D = mi
				for s in m.mesh.get_surface_count():
					var mat := m.get_active_material(s)
					if mat is BaseMaterial3D:
						var d: BaseMaterial3D = mat.duplicate()
						d.cull_mode = BaseMaterial3D.CULL_DISABLED
						if args.has("glow") and d.albedo_texture:
							d.emission_enabled = true
							d.emission = Color(1.0, 0.8, 0.55)
							d.emission_texture = d.albedo_texture
							d.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # 地の色に掛ける（足すと墨まで明るくなる）
							d.emission_energy_multiplier = float(args.glow)
						m.set_surface_override_material(s, d)
			t.rotation.y = PI
			t.position = TENT_AT
			lady.add_child(t)
			var pl: Node3D = main.player
			pl.global_position = lady.to_global(Vector3(0.85, 0.1, 9.0))   # カメラの後ろ（写らない）
			await create_timer(2.0).timeout
			var tag: String = args.tag
			await _shot(tag + "_front", Vector3(0.85, 1.5, 6.3), Vector3(0.85, 1.75, 0), 50.0)
			await _shot(tag + "_near", Vector3(0.7, 1.45, 3.1), Vector3(0.75, 1.35, 0), 62.0)
			await _shot(tag + "_side", Vector3(-3.1, 1.6, 5.0), Vector3(0.85, 1.6, 0), 50.0)
			if args.has("top"):
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.size = 8.0
				cam.global_transform = Transform3D(lady.global_basis * Basis(Vector3.RIGHT, -PI / 2.0), lady.to_global(Vector3(0.85, 4.9, -0.1)))
				await create_timer(0.3).timeout
				root.get_texture().get_image().save_png(_dir().path_join(tag + "_top.png"))
				await _shot(tag + "_back", Vector3(3.3, 1.7, -1.1), Vector3(0.6, 1.9, -1.5), 62.0)
		"still":
			var t: Node3D = lady.tent
			main.player.global_position = lady.to_global(Vector3(0.85, 0.1, 12.0))
			await create_timer(1.5).timeout
			for o in [0.0, 0.5, 1.0]:
				t.force = o
				await create_timer(0.4).timeout
				var tag := "open%d" % int(o * 100)
				await _shot(tag + "_front", Vector3(0.85, 1.5, 6.3), Vector3(0.85, 1.75, 0), 50.0)
				await _shot(tag + "_near", Vector3(0.7, 1.45, 3.1), Vector3(0.75, 1.35, 0), 62.0)
				await _shot(tag + "_side", Vector3(-3.1, 1.6, 5.0), Vector3(0.85, 1.6, 0), 50.0)
			t.force = 0.0
			await create_timer(0.3).timeout
			await _shot("gap_back", Vector3(1.6, 5.4, 2.4), Vector3(0.85, 0.6, -0.9), 58.0)   # 後ろの壁との隙間
		"walk":
			var t: Node3D = lady.tent
			var pl: Node3D = main.player
			var z := 8.5
			pl.global_position = lady.to_global(Vector3(0.6, 0.1, z))
			await create_timer(1.5).timeout
			if pl.get("doll"):   # 絵の前を横切らないように、あなたの人形は隠す（歩く所は同じ）
				pl.doll.visible = false
			cam.look_at_from_position(lady.to_global(Vector3(0.75, 1.5, 4.4)), lady.to_global(Vector3(0.75, 1.45, 0)), Vector3.UP)
			cam.fov = 52.0
			var f := Doll.frame_index()
			var n := 0
			var phase := "来る"
			var bow_at := -1.0
			var opened_at := -1
			var rest := 0
			while n < 150:
				while Doll.frame_index() == f:
					await process_frame
				f = Doll.frame_index()
				if phase == "来る":
					z = maxf(z - 3.2 / 12.0, 1.7)
					if z <= 1.7:
						rest += 1
						if rest > 36:
							phase = "去る"
				else:
					z = minf(z + 3.2 / 12.0, 9.0)
				pl.global_position = lady.to_global(Vector3(0.6, 0.1, z))
				var act: String = lady.get("_act")
				if opened_at < 0 and t.open > 0.0:
					opened_at = n
				if act == "bow" and bow_at < 0.0:
					bow_at = t.open
				print("コマ %d %s 前 %.1f m 開き %.2f 裾 %.2f 婦人 %s" % [n, phase, z, t.open, t._hem, act])
				root.get_texture().get_image().save_png(_dir().path_join("walk_%03d.png" % n))
				n += 1
				if phase == "去る" and z >= 9.0 and t.open <= 0.0:
					break
			print("%s おじぎは幕が開いてから: 始めたときの開き %.2f" % ["OK" if bow_at >= t.BOW_OPEN else "NG", bow_at])
			print("%s 離れると閉じた: 開き %.2f" % ["OK" if t.open <= 0.0 else "NG", t.open])
		"bump":
			var t: Node3D = lady.tent
			var pl: CharacterBody3D = main.player
			var ng := 0
			# 前と左右の歩ける所から真ん中へ歩く。壁で止まるか、前は入口から入れるか（後ろと南の隙間は人の幅より狭く、入れない）
			for d in [-90, -60, -30, 0, 30, 60]:
				var a := deg_to_rad(float(d))
				var dir := Vector3(sin(a), 0, cos(a))
				var from: Vector3 = dir * 3.0
				from.x = minf(from.x, 2.1)
				pl.global_position = t.to_global(from + Vector3.UP * 0.1)
				pl.velocity = Vector3.ZERO
				var inward: Vector3 = t.global_basis * (-from.normalized())
				for i in 90:
					await physics_frame
					pl.move_and_collide(inward * 0.04)
				var l: Vector3 = t.to_local(pl.global_position)
				var k := Vector2(l.x / t.RX, l.z / t.RY).length()
				var at_front: bool = absf(rad_to_deg(atan2(l.x / t.RX, l.z / t.RY))) < t.E
				print("%d° から: 止まった所 %s 楕円の %.2f 倍 %s" % [d, l.snappedf(0.01), k, "入口" if at_front else "壁の外"])
				if not at_front and k < 1.0:
					print("NG 壁を抜けた")
					ng += 1
			# 壁に沿って、左の横から前を通って右まで歩く（入口の外では押さない。壁の所では内へ少し押す）
			pl.global_position = t.to_global(Vector3(-2.1, 0.1, 0.3))
			var last: Vector3 = pl.global_position
			var moved := 0.0
			var stuck := 0
			var far_x := -9.0
			for i in 300:
				await physics_frame
				var l: Vector3 = t.to_local(pl.global_position)
				var radial := Vector3(l.x, 0, l.z).normalized()
				var press := 0.0 if absf(rad_to_deg(atan2(l.x / t.RX, l.z / t.RY))) < t.E + 6.0 else 0.25
				var dirn: Vector3 = t.global_basis * (Vector3(l.z, 0, -l.x).normalized() - radial * press)
				pl.velocity = dirn * 3.0
				pl.move_and_slide()
				var step: float = pl.global_position.distance_to(last)
				moved += step
				far_x = maxf(far_x, t.to_local(pl.global_position).x)
				stuck = stuck + 1 if step < 0.01 else 0
				last = pl.global_position
				if stuck > 40:
					break
			var end_at: Vector3 = t.to_local(pl.global_position).snappedf(0.01)
			var through := far_x > 1.2
			print("%s 壁に沿って歩いた: 道のり %.1f m、右へ x=%.2f まで、止まった所 %s" % ["OK" if through else "NG", moved, far_x, end_at])
			if not through:
				ng += 1
			# 開かないはずの所
			for w in [["1 階の真下", Vector3(0, -6.0, 0)], ["遠く", Vector3(0, 0.1, 9.0)]]:
				pl.global_position = t.to_global(w[1])
				await create_timer(1.8).timeout
				print("%s %s: 開き %.2f" % ["OK" if t.open <= 0.0 else "NG", w[0], t.open])
			print("NG の数 ", ng)
		"measure":
			print("婦人 ", lady.global_position, " 向き ", lady.global_basis.z)
			var space := (main as Node3D).get_world_3d().direct_space_state
			var ex: Array[RID] = []
			for b in lady.find_children("*", "StaticBody3D", true, false):
				ex.append((b as CollisionObject3D).get_rid())
			for centre in [Vector3(0.7, 0, -0.2), Vector3(-0.5, 0, 0), Vector3(1.9, 0, -0.2)]:
				for h in [0.3, 1.2, 2.2, 3.0]:
					var s := "中心 %s 高さ %.1f:" % [centre, h]
					for d in 12:
						var a := TAU * d / 12.0
						var dir := Vector3(sin(a), 0, cos(a))
						var from: Vector3 = lady.to_global(centre + Vector3.UP * h)
						var to: Vector3 = lady.to_global(centre + Vector3.UP * h + dir * 8.0)
						var q := PhysicsRayQueryParameters3D.create(from, to)
						q.exclude = ex
						var hit := space.intersect_ray(q)
						s += " %d°=%.2f" % [d * 30, from.distance_to(hit.position) if hit else 9.9]
					print(s)
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 14.0
			cam.global_transform = Transform3D(lady.global_basis * Basis(Vector3.RIGHT, -PI / 2.0), lady.to_global(Vector3(0.7, 2.75, -0.2)))
			await create_timer(0.6).timeout
			root.get_texture().get_image().save_png(_dir().path_join("top.png"))
	quit()
