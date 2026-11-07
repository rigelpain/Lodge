extends SceneTree
## 上り斜面の減速の確かめ（数字だけ出す）。乗って、同じ速さで上り斜面に入ったとき、どこまで登って止まるか。大きさは main.gd と同じ --sled= で選ぶ。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/climb_check.gd -- --sled=mid --no-player --bots=0 --no-sound --no-lodge --roam-bots=0 --lodge-bots=0
##   丘（くぼみの底から頂上へ。いちばん急で約 24°）と、上り返し（くぼみの底から外の高台へ。ゆるい）。摩擦がなければ登れる高さは 速さ² / (2 × 9.8)
##   --case=push 押して登る（push_check と同じ線）と、平らな所を滑る距離も出す（下りと平らな所を変えていないことの確かめ）

const DUMMY_SRC := """extends Node3D
var sled: Node3D
var side := 1
func get_off() -> void:
	sled.dismount(self)
"""

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
	_rows.append("| 所 | ソリ | 入る速さ (m/s) | 登った高さ (m) | 摩擦なしの高さ (m) | 進んだ距離 (m) | 止まるまで (s) |")
	_rows.append("|---|---|---|---|---|---|---|")
	for v0 in [5.0, 8.0, 11.0, 14.0]:
		await _climb("丘", Vector2(-58, 0), Vector2(1, 0), v0)
	for v0 in [5.0, 8.0, 11.0]:
		await _climb("上り返し", Vector2(58, -22).normalized() * 58.0, Vector2(58, -22).normalized(), v0)
	print("\n".join(_rows))
	quit()


func _climb(label: String, from: Vector2, dir: Vector2, v0: float) -> void:
	sled.reset_to(Vector3(from.x, main.height(from.x, from.y) + 0.3, from.y))
	sled.rotation.y = atan2(-dir.x, -dir.y)
	sled.parked = false
	var d := Node3D.new()
	d.set_script(_dummy)
	d.sled = sled
	main.add_child(d)
	sled.mount(d)
	await create_timer(0.6).timeout
	sled.linear_velocity = Vector3(dir.x, 0, dir.y) * v0
	sled.angular_velocity = Vector3.ZERO
	var p0: Vector3 = sled.global_position
	var top: float = p0.y
	var far := 0.0
	var t := 0.0
	var w := Vector3(dir.x, 0, dir.y)
	while t < 40.0:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var q: Vector3 = sled.global_position
		top = maxf(top, q.y)
		far = maxf(far, (q - p0).dot(w))
		if t > 0.3 and sled.linear_velocity.dot(w) < 0.05:
			break
	_rows.append("| %s | %s | %.0f | %.2f | %.2f | %.1f | %.1f |" % [label, sled.kind, v0, top - p0.y, v0 * v0 / 19.6, far, t])
	sled.dismount(d)
	d.queue_free()
