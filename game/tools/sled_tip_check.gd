extends SceneTree
## ソリが縦や横倒しのまま押されないか・つかんでいる人が宙に浮かないかの確かめ。
## 仲間（--bots=N）がふもとのソリを頂上まで押し、乗って滑り、また押すのを secs 秒見る。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_tip_check.gd -- --sled=small --bots=2 --no-player --roam-bots=0 --lodge-bots=0 --no-sound --secs=240
## 数: ソリの傾き（上向きと真上のなす角）の最大と、60° を超えていた長さ。つかんでいる人・乗っている人の足と雪面の差の最大と、0.5 m を超えた長さ。
## --dir=… を書くと（--headless なしで）、傾きが 30° を超えて 10° 大きくなるごとと、足が 0.5 m を超えて 0.3 m 浮くごとに横から撮る。--at=24,30 の時刻 (s) にも撮る。--tag= を名前の頭に付ける

var args := {}
var main: Node3D
var sled: RigidBody3D
var cam: Camera3D
var _worst_tilt := 0.0
var _worst_gap := 0.0
var _tipped_t := 0.0
var _float_t := 0.0
var _shot_tilt := 0.0      # 撮った傾き（これより 10° 大きくなったら撮り直す）
var _shot_gap := 0.0
var _shot_at: Array = []    # --at=24,30 この時刻 (s) にも撮る


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("seed"):
		seed(int(args.seed))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	if args.has("dir"):
		DirAccess.make_dir_recursive_absolute(args.dir)
	if args.has("at"):
		_shot_at = Array(String(args.at).split_floats(","))
	_run.call_deferred()


func _now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


## 足もとの地面の高さ。ソリと人の体を除いて真下へ光線を飛ばす（ほかの山の上でも測れる）。雪のうねり（snow_lift）を足す
func _ground(p: Vector3) -> float:
	var ex: Array[RID] = [sled.get_rid()]
	for b in get_nodes_in_group("bots"):
		ex.append(b.get_rid())
	if main.player:
		ex.append(main.player.get_rid())
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 40.0)
	q.exclude = ex
	var hit := sled.get_world_3d().direct_space_state.intersect_ray(q)
	var g: float = hit.position.y if hit else main.height(p.x, p.z)
	return g + main.snow_lift(p.x, p.z)


func _run() -> void:
	await create_timer(1.0).timeout
	sled = main.sled
	if args.has("dir"):
		if main.hud:
			main.hud.visible = false
		if main.settings:
			main.settings.set_open(false)
		cam = Camera3D.new()
		cam.fov = 50
		root.add_child(cam)
	var bots: Array = get_nodes_in_group("bots").filter(func(b): return not b.lounge)
	var secs := float(args.get("secs", "240"))
	var rope: bool = args.get("case", "") == "rope"
	if rope:
		_rope_begin(bots)
	var t0 := _now()
	var next := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	while _now() - t0 < secs:
		await physics_frame
		if rope:
			_rope_step(_now() - t0)
		var tilt := rad_to_deg(acos(clampf(sled.global_basis.y.y, -1.0, 1.0)))
		if tilt > 60.0:
			_tipped_t += dt
		var gap := 0.0
		var who := ""
		for b in bots:
			if b.sled != sled or (b.handle == Vector3.INF and b.state != b.State.RIDE):
				continue   # 別の所で自分の米袋に乗っている仲間は数えない
			var g: float = b.global_position.y - _ground(b.global_position)
			if b.state == b.State.RIDE:
				g = b.global_position.y - _ground(sled.global_position) - 0.6   # 席はソリの底より上なので、0.6 m までは浮きと数えない
			if g > gap:
				gap = g
				who = "%s %s" % [b.doll.kind, "乗る" if b.state == b.State.RIDE else "つかむ"]
		if gap > 0.5:
			_float_t += dt
		if tilt > _worst_tilt:
			_worst_tilt = tilt
		if gap > _worst_gap:
			_worst_gap = gap
		if cam and _shot_at.size() > 0 and _now() - t0 >= _shot_at[0]:
			_shot_at.remove_at(0)
			await _shot("at", tilt, gap)
		if cam and tilt > _shot_tilt + 10.0 and tilt > 30.0:
			_shot_tilt = tilt
			await _shot("tilt", tilt, gap)
		if cam and gap > _shot_gap + 0.3 and gap > 0.5:
			_shot_gap = gap
			await _shot("float", tilt, gap)
		if _now() - t0 >= next:
			next += 2.0
			var s := sled.global_position
			print("[%5.1f] ソリ (%.0f, %.1f, %.0f) 傾き %3.0f° 速さ %.1f 押%d 乗%d つかむ%d 足の浮き %.2f %s %s" % [_now() - t0, s.x, s.y, s.z, tilt, sled.linear_velocity.length(), sled.pushers, sled.riders.size(), sled.holders.size(), gap, who,
				" ".join(bots.map(func(b): return str(b.State.keys()[b.state])))])
	print("おわり: 傾きの最大 %.0f° / 60° を超えていた %.1f 秒 / 足の浮きの最大 %.2f m / 0.5 m を超えていた %.1f 秒" % [_worst_tilt, _tipped_t, _worst_gap, _float_t])
	quit()


# ---- --case=rope: あなたが紐で頂上へ引き、山をめぐる仲間（--roam-bots=2）が手伝って押す。頂上で手を離して待ち、また紐で下りへ引く
#   Godot --headless --fixed-fps 60 --path game -s res://tools/sled_tip_check.gd -- --case=rope --sled=small --bots=0 --roam-bots=2 --lodge-bots=0 --no-sound --secs=150
var _phase := "up"
var _top_t := 0.0


func _rope_begin(bots: Array) -> void:
	var s := sled.global_position
	for i in bots.size():
		var at: Vector3 = s + Vector3(2.5 * (1 if i % 2 == 0 else -1), 0, 2.0)
		bots[i].global_position = Vector3(at.x, main.height(at.x, at.z) + 0.2, at.z)
	main.player.grab_rope()
	print("紐を持った: ", main.player.mode == main.player.Mode.ROPE)


## 地面に沿った上り（水平。長さは傾き）
func _uphill(p: Vector3) -> Vector3:
	var e := 0.5
	return Vector3(main.height(p.x + e, p.z) - main.height(p.x - e, p.z), 0, main.height(p.x, p.z + e) - main.height(p.x, p.z - e)) / (2.0 * e)


## あなたを、紐の先がぴんと張る所へ（上りか下りへ）置き続ける。player.gd が手の位置から紐を引く
func _rope_step(t: float) -> void:
	var p: CharacterBody3D = main.player
	var a: Vector3 = sled.to_global(sled.ROPE_ANCHOR)
	var up := _uphill(a)
	match _phase:
		"up":
			if up.length() < 0.04 or t > 100.0:
				_phase = "top"
				_top_t = t
				p.let_go()
				print("[%5.1f] 頂上で手を離した" % t)
				return
		"top":
			if t - _top_t > 12.0:
				_phase = "down"
				p.grab_rope()
				print("[%5.1f] また紐を持って下りへ引く（持てた %s）" % [t, str(p.mode == p.Mode.ROPE)])
			return
	if p.mode != p.Mode.ROPE:
		return
	var dir := up.normalized() if _phase == "up" else -up.normalized()
	if dir.length() < 0.5:
		dir = Vector3.FORWARD
	var at: Vector3 = a + dir * (sled.ROPE_LEN + 0.12)
	p.global_position = Vector3(at.x, main.height(at.x, at.z) + 0.05, at.z)
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-dir.x, -dir.z)


## ソリの横から撮る
func _shot(name: String, tilt: float, gap: float) -> void:
	var c: Vector3 = sled.global_position
	var right: Vector3 = sled.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length() > 0.1 else Vector3.RIGHT
	var at := c + right * 6.0 + Vector3.UP * 0.5
	at.y = maxf(at.y, _ground(at) + 1.2)
	cam.global_position = at
	cam.look_at(c + Vector3.UP * 0.8)
	cam.reset_physics_interpolation()
	cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	var tag: String = args.get("tag", "")
	var path := String(args.dir).path_join("%s%s_%.0fs_tilt%.0f_gap%.1f.png" % [tag + "_" if tag != "" else "", name, _now(), tilt, gap])
	root.get_texture().get_image().save_png(path)
	print("撮った: ", path)
