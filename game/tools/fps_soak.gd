extends SceneTree
## 遊んでいるうちに FPS が落ちないかを、実時間で測る（時間は早めない。画面ありで起動する）。
##   Godot --path game -s res://tools/fps_soak.gd -- --secs=600 --out=/path/soak.csv [--play=loop|still] [--every=5] [--time=時] [--vsync=on|off] [--cap=FPS]
## --play=loop: あなたがソリを押して登り、乗って滑り、降りて歩き回る（ふつうの遊びに近い動きをくり返す）
## --play=still: スポーンの場所に立ったまま（動きをなくして、時間で増える物だけを見る）
## --probe-every=秒: 遊びの途中で、この間隔で決まった場所（丘の上とロッジの中を交互）に PROBE_SECS 秒立つ。場所の違いを抜いて、時間で重くなるかを見る
## --recover=秒: 測り終わる前のこの秒だけ、時刻を朝の 10 時へ戻す（落ちた FPS が戻るなら熱ではなく中身の原因）
## out に 1 行ずつ CSV を書き、out.census に 30 秒ごとの「親ごとの子の数・種類ごとの数」のふえた分を書く。

const CENSUS_EVERY := 30.0
const PROBE_SECS := 15.0

var args := {}
var main: Node3D
var t := 0.0
var _out: FileAccess
var _census: FileAccess
var _next_log := 0.0
var _next_census := 0.0
var _base := {}
var _frames := 0
var _sum := 0.0
var _max := 0.0
var _slow := 0
var _cpu := 0.0
var _gpu := 0.0
var _vp_rid: RID
var _phase := "wait"
var _phase_t := 0.0
var _walk_turn := 0.0
var _recovering := false
var _w_down := false
var _vsync_set := false
var _next_probe := 30.0
var _probe_n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var path: String = args.get("out", "/tmp/soak.csv")
	_out = FileAccess.open(path, FileAccess.WRITE)
	_census = FileAccess.open(path + ".census", FileAccess.WRITE)
	_out.store_line("secs,fps,avg_ms,max_ms,slow,cpu_vp_ms,gpu_vp_ms,process_ms,physics_ms,nodes,objects,resources,orphans,draw_calls,primitives,objs_in_frame,vram_mb,tex_mb,buf_mb,static_mb,phys_active,phys_pairs,phys_islands,tweens,hour,phase,y,mode,scale3d,x,z,cam_x,cam_y,cam_z")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main   # これがないと一日の巡り（daycycle.gd）が太陽を見つけられず、時刻が進まない。コマの出し方も遊ぶときと同じになる
	AudioServer.set_bus_mute(0, true)   # 音の仕組みは動かしたまま、スピーカーからは鳴らさない
	_vp_rid = root.get_viewport_rid()
	print("窓 %s 画面 %s" % [str(root.size), str(DisplayServer.screen_get_size())])
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(dt: float) -> bool:
	t += dt
	Engine.max_fps = int(args.get("cap", str(main.GAME_FPS)))   # 窓が裏に回っても落とさない（main.gd の BACKGROUND_FPS）
	if args.has("vsync") and not _vsync_set:   # --vsync=off|on で縦同期を比べる
		_vsync_set = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if args["vsync"] == "off" else DisplayServer.VSYNC_ENABLED)
	if t < 1.0:
		return false
	_frames += 1
	_sum += dt
	_max = maxf(_max, dt)
	_slow += 1 if dt > 1.0 / 30.0 else 0
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	if main.get("settings") and main.settings:
		main.settings.set_open(false)
	var play: String = args.get("play", "loop")
	if play == "loop":
		_drive(dt)
	var secs := float(args.get("secs", "600"))
	if args.has("recover") and not _recovering and t > secs - float(args["recover"]):
		_recovering = true
		get_root().get_node("DayCycle").hour = 10.0
		print("朝へ戻す t=%.0f" % t)
	if t >= _next_log:
		_next_log = t + float(args.get("every", "5"))
		_log()
	if t >= _next_census:
		_next_census = t + CENSUS_EVERY
		_write_census()
	if t > secs:
		_out.flush()
		_census.flush()
		quit()
	return false


func _log() -> void:
	var n := maxi(_frames, 1)
	var P := Performance
	var mb := 1.0 / (1024.0 * 1024.0)
	var p = main.get("player")
	var sled = main.get("sled")
	var row := PackedStringArray([
		"%.0f" % t, "%.1f" % (_frames / maxf(_sum, 0.001)), "%.2f" % (1000.0 * _sum / n), "%.1f" % (1000.0 * _max), str(_slow),
		"%.2f" % (_cpu / n), "%.2f" % (_gpu / n),
		"%.2f" % (1000.0 * P.get_monitor(P.TIME_PROCESS)), "%.2f" % (1000.0 * P.get_monitor(P.TIME_PHYSICS_PROCESS)),
		str(int(P.get_monitor(P.OBJECT_NODE_COUNT))), str(int(P.get_monitor(P.OBJECT_COUNT))), str(int(P.get_monitor(P.OBJECT_RESOURCE_COUNT))), str(int(P.get_monitor(P.OBJECT_ORPHAN_NODE_COUNT))),
		str(int(P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))), str(int(P.get_monitor(P.RENDER_TOTAL_PRIMITIVES_IN_FRAME))), str(int(P.get_monitor(P.RENDER_TOTAL_OBJECTS_IN_FRAME))),
		"%.1f" % (P.get_monitor(P.RENDER_VIDEO_MEM_USED) * mb), "%.1f" % (P.get_monitor(P.RENDER_TEXTURE_MEM_USED) * mb), "%.1f" % (P.get_monitor(P.RENDER_BUFFER_MEM_USED) * mb), "%.1f" % (P.get_monitor(P.MEMORY_STATIC) * mb),
		str(int(P.get_monitor(P.PHYSICS_3D_ACTIVE_OBJECTS))), str(int(P.get_monitor(P.PHYSICS_3D_COLLISION_PAIRS))), str(int(P.get_monitor(P.PHYSICS_3D_ISLAND_COUNT))),
		str(get_processed_tweens().size()),
		"%.2f" % float(get_root().get_node("DayCycle").hour), _phase,
		"%.1f" % (sled.global_position.y if sled else 0.0), str(p.mode) if p else "-", "%.2f" % root.get_viewport().scaling_3d_scale,
		"%.0f" % (sled.global_position.x if sled else 0.0), "%.0f" % (sled.global_position.z if sled else 0.0),
		"%.0f" % _cam_at().x, "%.0f" % _cam_at().y, "%.0f" % _cam_at().z,
	])
	_out.store_line(",".join(row))
	_out.flush()
	print(",".join(row))
	_frames = 0
	_sum = 0.0
	_max = 0.0
	_slow = 0
	_cpu = 0.0
	_gpu = 0.0


func _cam_at() -> Vector3:
	var c := root.get_viewport().get_camera_3d()
	return c.global_position if c else Vector3.ZERO


## 親ごとの子の数と、種類ごとの数を数え、始めからふえた分だけを書く
func _write_census() -> void:
	var now := {}
	var stack: Array[Node] = [root]
	var lights_on := 0
	var shadows_on := 0
	var parts_on := 0
	var aud_on := 0
	var vp_live := 0
	var mm_on := 0
	var mm_inst := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var kids := n.get_child_count(true)
		var cls := n.get_class()
		var scr: Script = n.get_script()
		if scr and scr.resource_path != "":
			now["script " + scr.resource_path.get_file()] = int(now.get("script " + scr.resource_path.get_file(), 0)) + 1
		now["class " + cls] = int(now.get("class " + cls, 0)) + 1
		if kids > 5:
			now["kids " + str(n.get_path())] = kids
		if n is Light3D and (n as Light3D).is_visible_in_tree():
			lights_on += 1
			if (n as Light3D).shadow_enabled:
				shadows_on += 1
		if (n is GPUParticles3D or n is CPUParticles3D) and n.get("emitting") and (n as Node3D).is_visible_in_tree():
			parts_on += 1
		if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
			if n.get("playing"):
				aud_on += 1
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).is_visible_in_tree() and (n as MultiMeshInstance3D).multimesh:
			mm_on += 1
			var mm := (n as MultiMeshInstance3D).multimesh
			mm_inst += mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if n is SubViewport and (n as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			vp_live += 1
		for c in n.get_children(true):
			stack.append(c)
	now["on lights"] = lights_on
	now["on shadow_lights"] = shadows_on
	now["on particles_emitting"] = parts_on
	now["on audio_playing"] = aud_on
	now["on subviewports_always"] = vp_live
	now["on multimesh_shown"] = mm_on
	now["on multimesh_instances"] = mm_inst
	if _base.is_empty():
		_base = now
		var keys := now.keys()
		_census.store_line("# t=%.0f 始めの数: lights=%d shadow=%d particles=%d audio=%d vp=%d nodes=%d" % [t, lights_on, shadows_on, parts_on, aud_on, vp_live, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		for k in keys:
			if String(k).begins_with("class "):
				_census.store_line("# %s=%d" % [k, now[k]])
		_census.flush()
		return
	var diffs := PackedStringArray()
	for k in now:
		var d: int = int(now[k]) - int(_base.get(k, 0))
		if d != 0:
			diffs.append("%s %+d(=%d)" % [k, d, now[k]])
	for k in _base:
		if not now.has(k):
			diffs.append("%s %+d(=0)" % [k, -int(_base[k])])
	diffs.sort()
	_census.store_line("t=%.0f " % t + " | ".join(diffs))
	_census.flush()


func _key(code: Key, on: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = on
	Input.parse_input_event(ev)


func _set_w(on: bool) -> void:
	if on != _w_down:
		_w_down = on
		_key(KEY_W, on)


## ふつうの遊びのくり返し: 押して登る → 乗って滑る → 降りて歩く
func _drive(dt: float) -> void:
	var p = main.get("player")
	var sled = main.get("sled")
	if p == null or sled == null:
		return
	_phase_t += dt
	if args.has("probe-every") and t >= _next_probe and not _phase.begins_with("probe"):
		if p.mode == p.Mode.RIDE:
			p.get_off()
		elif p.mode == p.Mode.GRIP:
			p.let_go()
		_begin("probe_hill" if _probe_n % 2 == 0 else "probe_lodge")
		_probe_n += 1
		_set_w(false)
	if _phase.begins_with("probe"):
		# 少し落ち着くまで置き直す
		if _phase_t < 1.0:
			if _phase == "probe_hill":
				p.global_position = Vector3(1.5, main.height(1.5, 35.0) + 1.0, 35.0)
				p.rotation.y = 2.62
			else:
				var au := main.get_node_or_null("Audio")   # --no-sound では音の配り役がないので、同じ所（audio.gd の spawn_point）をロッジから
				p.global_position = au.spawn_point("inside") if au else main.get_node("Lodge").to_global(Vector3(6.0, 0.5, -4.0))
				p.rotation.y = 0.8
		if _phase_t > PROBE_SECS:
			_next_probe = t + float(args["probe-every"])
			_begin("push")
		return
	match _phase:
		"wait":
			if t > 3.0:
				_begin("push")
		"push":
			if p.mode != p.Mode.GRIP:
				var back: Vector3 = sled.global_basis.z
				p.global_position = sled.global_position + back * 2.0 + Vector3.UP * 0.3
				p.rotation.y = atan2(back.x, back.z)
				p.grab()
			else:
				var fwd: Vector3 = -sled.global_basis.z
				p.rotation.y = atan2(-fwd.x, -fwd.z)
			_set_w(true)
			var top := Vector2(sled.global_position.x, sled.global_position.z).length()
			if top < 5.0 or sled.global_position.y > 16.6 or _phase_t > 75.0:
				p.let_go()
				# 丘のふもとへ向けて押し出してから乗る（頂上の平らな所で止まらないように）
				var out := Vector3(sled.global_position.x, 0, sled.global_position.z)
				out = out.normalized() if out.length() > 0.5 else Vector3.BACK
				sled.global_position += out * 6.0
				sled.global_rotation.y = atan2(-out.x, -out.z)
				p.global_position = sled.global_position + Vector3.UP * 0.5
				p.get_on()
				sled.linear_velocity = out * 8.0
				_begin("ride")
		"ride":
			_set_w(true)
			if _phase_t > 6.0 and sled.linear_velocity.length() < 1.0 or _phase_t > 50.0:
				p.get_off()
				_begin("walk")
		"walk":
			# 雪の上を歩き回る（足あと）。ときどき向きを変える
			_set_w(true)
			_walk_turn -= dt
			if _walk_turn <= 0.0:
				_walk_turn = randf_range(1.5, 4.0)
				p.rotation.y += randf_range(-1.6, 1.6)
			if _phase_t > 25.0:
				# ロッジの食堂へ入って歩く
				var au := main.get_node_or_null("Audio")   # --no-sound では音の配り役がないので、同じ所（audio.gd の spawn_point）をロッジから
				p.global_position = au.spawn_point("inside") if au else main.get_node("Lodge").to_global(Vector3(6.0, 0.5, -4.0))
				_begin("lodge")
		"lodge":
			_set_w(true)
			_walk_turn -= dt
			if _walk_turn <= 0.0:
				_walk_turn = randf_range(1.0, 2.5)
				p.rotation.y += randf_range(-2.4, 2.4)
			if _phase_t > 20.0:
				_begin("push")


func _begin(ph: String) -> void:
	_phase = ph
	_phase_t = 0.0
	print("t=%.0f -> %s" % [t, ph])
