extends SceneTree
## 滑りあとが途切れない・ちらつかないことの確かめ用。大山の西の斜面を長く滑り、1 秒ごとに次を出す。
##   Godot --path game --resolution 960x540 -s res://tools/trail_stable_check.gd -- --bots=0 --no-sound --sled=mid --time=30 --out=/path/trail [--stitch=running] [--no-shots]
##   見えない目  カメラから 20 m 以内にまだ残っている目のうち、描かれない塊に入っているものの数（0 でないと、足もとの跡が消えて見える）
##   塊の広がり  同じ塊の中で、いちばん離れた目どうしの距離 (m) の最大
##   抜け        前の歩みとの間が TRAIL_STEP の 2.5 倍より開いた所の数（滑り木 2 本ぶんの合計。同じ塊の並びから数える）
##   宙          雪面から 0.15 m より離れた目の数
## --no-shots でなければ <out>_<秒>.png（ソリの後ろ上から）を 2 秒ごとに書く

var args := {}
var main: Node3D
var cam: Camera3D
var t := 0.0
var phase := 0
var _start := 0.0
var _next_report := 0.0
var _next_shot := 0.0
var _worst_hidden := 0
var _worst_spread := 0.0
var _vmax := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	root.scaling_3d_scale = 1.0
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	cam = Camera3D.new()
	cam.fov = 60
	cam.cull_mask = (1 << 0) | (1 << 1)
	root.add_child(cam)


func _process(dt: float) -> bool:
	t += dt
	var sled: RigidBody3D = main.sled
	var p = main.player
	if sled == null or p == null:
		return false
	if main.settings:
		main.settings.set_open(false)
	if main.hud:
		main.hud.visible = false
	if main._pip_layer:
		main._pip_layer.visible = false
	if phase == 0 and t > 0.6:
		# 大山の頂上の西に、-x（下り）を向けて置く
		var at := Vector3(float(args.get("x", "680")), 0, float(args.get("z", "30")))
		at.y = main.height(at.x, at.z) + 0.6 + sled.place_lift()
		sled.reset_to(at)
		sled.rotation.y = PI / 2
		p.global_position = at + Vector3.UP * 0.5
		p.get_on()
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		phase = 1
		_start = t
	elif phase == 1:
		var fwd: Vector3 = -sled.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized()
		cam.global_position = sled.global_position - fwd * 7.0 + Vector3.UP * 3.5
		cam.look_at(sled.global_position - fwd * 2.0, Vector3.UP)
		cam.current = true
		var s := t - _start
		_vmax = maxf(_vmax, sled.linear_velocity.length())
		if s >= _next_report:
			_next_report += 1.0
			_report(sled, s)
		if not args.has("no-shots") and s >= _next_shot:
			_next_shot += 2.0
			root.get_texture().get_image().save_png("%s_%02d.png" % [args.get("out", "/tmp/trail"), int(s)])
		if s > float(args.get("time", "30")):
			print("まとめ: いちばん多い見えない目=%d 塊の広がりの最大=%.0f m 速さの最大=%.1f m/s" % [_worst_hidden, _worst_spread, _vmax])
			quit()
	return false


func _report(sled: RigidBody3D, s: float) -> void:
	var cpos := cam.global_position
	var hidden := 0
	var near := 0
	var spread := 0.0
	var off := 0
	var gaps := 0
	var now: float = sled._trail_now
	var pos := {}
	for ci in sled._trails.size():
		var mi: MultiMeshInstance3D = sled._trails[ci]
		var mm := mi.multimesh
		var n := mm.visible_instance_count
		if n <= 0:
			continue
		var box := mm.get_aabb()
		var c := mi.global_transform * box.get_center()
		var far: bool = mi.visibility_range_end > 0.0 and c.distance_to(cpos) > mi.visibility_range_end
		spread = maxf(spread, box.size.length())
		var drawn: bool = mi.visible and not far
		for j in n:
			var slot: int = ci * sled._trail_chunk + j
			if sled._trail_end[slot] <= now:
				continue
			var at := mm.get_instance_transform(j).origin
			if at == Vector3.ZERO:   # 置いたばかりで、次のコマまで読み返せない目
				continue
			pos[slot] = at
			if at.distance_to(cpos) < 20.0:
				near += 1
				if not drawn:
					hidden += 1
			var ground: float = main.snow_plane(at.x, at.z).w
			if absf(at.y - ground) > 0.15:
				off += 1
	var keys := pos.keys()
	keys.sort()
	# 同じ滑り木の次の目は、番号のすぐ先にある。番号の先 2 歩ぶんのどれにも近い目がなければ、抜け
	var look: int = 4 * int(sled._st.per) + 2
	var last_k: int = keys[-1] if not keys.is_empty() else 0
	for k in keys:
		if k + look > last_k:
			continue
		var best := INF
		for d in range(1, look + 1):
			if pos.has(k + d):
				best = minf(best, (pos[k] as Vector3).distance_to(pos[k + d]))
		if best > sled.TRAIL_STEP * 2.5:
			gaps += 1
	_worst_hidden = maxi(_worst_hidden, hidden)
	_worst_spread = maxf(_worst_spread, spread)
	print("%5.1f s  速さ=%5.1f m/s  位置=(%.0f,%.0f)  残っている目=%d  20m以内=%d  見えない目=%d  塊の広がり=%.0f m  抜け=%d  宙=%d  fps=%d  三角=%d" % [
		s, sled.linear_velocity.length(), sled.global_position.x, sled.global_position.z, pos.size(), near, hidden, spread, gaps, off, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
