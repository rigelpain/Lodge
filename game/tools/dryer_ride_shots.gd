extends SceneTree
## 厨房の乾燥機に入って乾く様子を撮る（確かめ用。design/damp.md の「乾燥機」）。
##   Godot --path game --resolution 1280x720 -s res://tools/dryer_ride_shots.gd -- --bots=0 --no-sound --hud-idle=0 --dir=/path/shots
## 1 回目は三人称（01 前で F の案内 → 02 とび込む → 03・04 回る → 05 とび出す → 06 出たあと）、
## 2 回目は一人称（11 前で F → 12 胴の中から丸い戸の窓ごしに外を見る）、
## 3 回目は乾燥機の前に置いたカメラで、回されて落ちる 36 コマ（3 秒）を 1 コマずつ（21_00 〜 21_35。動く絵にする）。
## どの回も水 100（びしょびしょ）から入る

const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var st: Node


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/dryer_ride")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path, "  水 %.0f  モード %d" % [main.damp.water_of(p.id), p.mode])


## 入ってからのコマ k まで待つ
func _until(k: int) -> void:
	while Doll.frame_index() - st._ride_f < k:
		await process_frame


## 乾燥機の前に立ち、乾燥機を向く（水 100 にする）
func _front() -> void:
	main.damp.put(p.id, 100.0)
	p.global_position = st.stand_point() + Vector3.UP * 0.05
	var d: Vector3 = st.get_parent().global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", -0.1)
	await _wait(0.8)


func _run() -> void:
	await _wait(3.0)
	if main.settings and main.settings.is_open:
		main.settings.set_open(false)
	p = main.player
	p.menu_open = false
	for s in main.stations:
		if s.kind == "dryer":
			st = s
	# 1 回目: 三人称
	p.set_third(true)
	await _front()
	print("入れる: ", p.dryer_near() == st)
	await _shot("01_third_near")
	st.ride(p)
	await _until(3)
	await _shot("02_third_hop_in")
	await _until(10)
	await _shot("03_third_spin")
	await _until(15)
	await _shot("04_third_spin")
	while st._out_f < 0:
		await process_frame
	await _until(st._out_f - st._ride_f + 2)
	await _shot("05_third_hop_out")
	await _wait(0.8)
	await _shot("06_third_after")
	# 2 回目: 一人称
	p.set_third(false)
	await _front()
	await _shot("11_fp_near")
	st.ride(p)
	await _until(14)
	await _shot("12_fp_inside")
	while p.mode == p.Mode.DRUM:
		await process_frame
	await _wait(0.6)
	# 3 回目: 乾燥機の前のカメラ（画面の表示は隠す）
	p.set_third(true)
	await _front()
	var dev: Node3D = st.get_parent()
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.cull_mask = p.cam.cull_mask   # プレイヤーのカメラと同じ層だけ（一人称の手のミトンを映さない）
	root.add_child(cam)
	cam.look_at_from_position(st.drum_center() + st.front() * 4.2 + Vector3.UP * 0.4, st.drum_center())
	cam.current = true
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	st.ride(p)
	for k in 36:
		await _until(st.RIDE_IN + 2 + k)
		await _shot("21_%02d" % k)
	quit()
