extends SceneTree
## ソリの底が雪にめり込んで見えるかを測る（数字だけ出す）。大きさは --sled=（main.gd と同じ）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_sink_check.gd -- --sled=small --no-player --bots=0 --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
## 平らな所と斜面（丘の登る線の途中、頂上から 20 m）に置いて、乗る人 0 人・席いっぱいで止まるまで待ち、
## 見た目（glb）の頂点のうち、見た目の雪面（main.height ＋ 吹きだまりのうねり main.snow_lift）より下にあるものを数える。
## いちばん深い所（cm）、下にある頂点の割合、当たりの箱の底の 4 隅の雪面からの高さ（cm。負はめり込み）を出す

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var id := -1
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""
const FLAT := Vector3(-30, 0, 30)   # 丘のふもとの西の平らな雪（ロッジの外）
const SLOPE := Vector3(0, 0, 20)

var args := {}
var main: Node3D
var sled: RigidBody3D
var _dummy: GDScript
var _rows: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	_dummy = GDScript.new()
	_dummy.source_code = DUMMY_SRC
	_dummy.reload()
	_run.call_deferred()


func _run() -> void:
	await create_timer(0.5).timeout
	sled = main.sled
	_rows.append("| ソリ | 所 | 乗る人 | いちばん深い (cm) | 雪の下の頂点 | 箱の底の 4 隅（前左・前右・後左・後右, cm） | 傾き（前後°） |")
	_rows.append("|---|---|---|---|---|---|---|")
	for at in [["平ら", FLAT, 0.0], ["斜面（頂上向き）", SLOPE, 0.0], ["斜面（ふもと向き）", SLOPE, PI]]:
		for n in [0, sled.SEATS.size()]:
			await _measure(at[0], at[1], at[2], n)
	_rows.append("")
	_rows.append("### 滑っているあいだ（頂上から +z へ 4 m/s で押し出して 12 秒。コマごとのいちばん深い頂点）")
	_rows.append("| ソリ | 乗る人 | いちばん深い (cm) | コマの平均 (cm) | 2 cm より深いコマ | 5 cm より深いコマ | 当たりの箱の底のいちばん深い (cm) |")
	_rows.append("|---|---|---|---|---|---|---|")
	for n in [0, 1, sled.SEATS.size()]:
		if n == 1 and sled.SEATS.size() == 1:
			continue
		await _slide(n)
	var lo := INF
	for v in _body_verts():
		lo = minf(lo, v.y)
	_rows.append("形のいちばん低い頂点（ソリの座標）: %.3f m。当たりの箱の底: %.3f m" % [lo, sled._box_col.position.y - (sled._box_col.shape as BoxShape3D).size.y * 0.5])
	print("\n".join(_rows))
	quit()


## 本体の形（glb）の頂点（ソリの座標）。一度だけ集める
var _verts := PackedVector3Array()
func _body_verts() -> PackedVector3Array:
	if _verts.is_empty():
		var inv := (sled._body as Node3D).global_transform.affine_inverse()   # 形の座標で覚える（見た目の上下 vis_lift は、測るときの形の位置で入る）
		for mi in sled._body.find_children("*", "MeshInstance3D", true, false) + ([sled._body] if sled._body is MeshInstance3D else []):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree():
				continue
			var xf := inv * m.global_transform
			for si in m.mesh.get_surface_count():
				for v in (m.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					_verts.append(xf * v)
	return _verts


## いまのコマで、雪面より下にある頂点のいちばん深い所 (m)
func _deep_now() -> float:
	var xf := (sled._body as Node3D).global_transform
	var deep := 0.0
	for v in _body_verts():
		var w := xf * v
		deep = maxf(deep, main.height(w.x, w.z) + main.snow_lift(w.x, w.z) - w.y)
	return deep


func _slide(n: int) -> void:
	sled.reset_to(Vector3(0, main.height(0, 3.0) + 0.3, 3.0))
	sled.rotation.y = PI
	sled.parked = true
	await create_timer(1.0).timeout
	_body_verts()
	var rs := []
	for i in n:
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		rs.append(d)
	sled.parked = false
	sled.linear_velocity = Vector3(0, 0, 4.0)
	var t := 0.0
	var top := 0.0
	var sum := 0.0
	var frames := 0
	var over2 := 0
	var over5 := 0
	var box := 0.0
	while t < 12.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var d := _deep_now()
		top = maxf(top, d)
		sum += d
		frames += 1
		if d > 0.02:
			over2 += 1
		if d > 0.05:
			over5 += 1
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var w := sled.to_global(Vector3(c.x * sled.HALF.x, 0.0, c.y * sled.HALF.y))
			box = maxf(box, main.height(w.x, w.z) + main.snow_lift(w.x, w.z) - w.y)
	_rows.append("| %s | %d | %.1f | %.1f | %d%% | %d%% | %.1f |" % [sled.kind, n, top * 100.0, sum / frames * 100.0, over2 * 100 / frames, over5 * 100 / frames, box * 100.0])
	for d in rs:
		sled.dismount(d)
		d.queue_free()


func _measure(label: String, at: Vector3, yaw: float, n: int) -> void:
	sled.reset_to(Vector3(at.x, main.height(at.x, at.z) + 0.3, at.z))
	sled.rotation.y = yaw
	sled.parked = true
	# 斜面でずり落ちないよう、置いて落ち着くまではつかんだ人がいることにする（parked で留まる）
	await create_timer(1.5).timeout
	var rs := []
	for i in n:
		var d := Node3D.new()
		d.set_script(_dummy)
		d.sled = sled
		main.add_child(d)
		sled.mount(d)
		rs.append(d)
	sled.parked = true
	await create_timer(1.5).timeout
	var deep := 0.0
	var under := 0
	var total := 0
	for mi in sled._body.find_children("*", "MeshInstance3D", true, false) + ([sled._body] if sled._body is MeshInstance3D else []):   # 本体の形だけ（滑りあと・紐は数えない）
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var xf := m.global_transform
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				var w := xf * v
				var d: float = main.height(w.x, w.z) + main.snow_lift(w.x, w.z) - w.y
				total += 1
				if d > 0.0:
					under += 1
					deep = maxf(deep, d)
	var corners := []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := sled.to_global(Vector3(c.x * sled.HALF.x, 0.0, c.y * sled.HALF.y))
		corners.append("%+.0f" % ((w.y - main.height(w.x, w.z)) * 100.0))
	var pitch := rad_to_deg(asin(clampf((-sled.global_basis.z).y, -1.0, 1.0)))
	_rows.append("| %s | %s | %d | %.1f | %d / %d | %s | %.1f |" % [sled.kind, label, n, deep * 100.0, under, total, " ".join(corners), pitch])
	for d in rs:
		sled.dismount(d)
		d.queue_free()
