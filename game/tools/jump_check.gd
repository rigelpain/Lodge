extends SceneTree
## ジャンプを測る（確かめ用。本物の Space・W・Shift のキーで跳ぶ）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/jump_check.gd -- --bots=0 --no-sound --no-pip --no-selfcam
##   1. その場跳び: 跳んでからの足もとの高さを 1 コマ（1/60 秒）ごとに。いちばん高い所、宙にいた時間、着いたときの下向きの速さ
##   2. 走り跳び（Shift）: 宙にいるあいだに前へ進んだ長さ
##   3. 段: 宙に浮かせた平らな板の上に高さの違う箱を置き、走って（歩いて）手前で跳び、箱の上に乗れたか。乗れたいちばん高い箱
##   --shots=/path/dir   絵も撮る（--headless を外し、--resolution 640x360 を付ける）。その場跳びを一人称・三人称・横から動かないカメラで、2 コマおきに
##   --views=first,third,side   撮る向き
##   --skip-ledge        3 を飛ばす

var args := {}
var main: Node3D
var p: CharacterBody3D
var lines: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## 平らな所に立たせ、落ち着くまで待つ
func _stand(at: Vector3, yaw := 0.0) -> void:
	p.global_position = at
	p.rotation = Vector3(0, yaw, 0)
	p.velocity = Vector3.ZERO
	await _frames(40)


## その場で 1 回跳び、着いてから少しまでの [秒, 高さ, 縦の速さ, 床] を返す
func _hop(shoot := "") -> Array:
	var y0 := p.global_position.y
	var rows: Array = []
	_key(KEY_SPACE, true)
	var t := -1.0
	var landed_at := -1
	for i in 120:
		await physics_frame
		if i == 3:
			_key(KEY_SPACE, false)   # 押しっぱなしだと着くたびにまた跳ぶので、宙にいるうちに離す
		var h := p.global_position.y - y0
		if t < 0.0 and h > 0.001:
			t = 0.0
			rows.append([0.0, 0.0, 0.0, true])   # 踏み切りのコマ
		if t < 0.0:
			continue
		t += 1.0 / 60.0
		rows.append([t, h, p.velocity.y, p.is_on_floor()])
		if shoot != "" and rows.size() % 2 == 1:
			await process_frame
			root.get_texture().get_image().save_png(shoot % rows.size())
		if landed_at < 0 and p.is_on_floor():
			landed_at = rows.size()
		if landed_at >= 0 and rows.size() > landed_at + 18:
			break
	return rows


func _run() -> void:
	await _frames(30)
	p = main.player
	var flat := Node3D.new()
	root.add_child(flat)
	# 宙に浮かせた広い板（雪の起伏や物に左右されないように）
	var base := Vector3(0, 300, 38)
	_box(flat, base + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	await _stand(base + Vector3(0, 0.1, 0))

	var shots: String = args.get("shots", "")
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		# 絵は雪の上で（宙の板では景色が空だけになる）。少し待って、雪と人形が落ち着いてから
		var g: Vector3 = main.START + Vector3(0, main.height(main.START.x, main.START.z) + 0.1, 0)
		for c in main.find_children("*", "CanvasLayer", true, false):
			c.visible = false   # 札や手の列は隠す（跳ぶ姿だけを見る）
		for view in String(args.get("views", "first,third,side")).split(","):
			p.set_third(view != "first")
			await _stand(g, PI * 0.5)
			var side: Camera3D = null
			if view == "side":
				# 横から動かないカメラで（三人称のカメラは体についてくるので、跳ぶ高さが見えにくい）
				side = Camera3D.new()
				side.fov = 40
				root.add_child(side)
				var at := p.global_position + Vector3(0, 0.75, 0)
				side.look_at_from_position(at - p.global_basis.x * 4.5 + Vector3(0, 0.2, 0), at)   # 左から（右にはソリがある）
				side.make_current()
			await _frames(30)
			await _hop(shots.path_join(view + "_%02d.png"))
			if side:
				side.queue_free()
				p.cam.make_current()
		quit()
		return

	var rows := [] if args.has("ledge-only") else await _hop()
	lines.append("== その場跳び（足もとの高さ。1 コマ = 1/60 秒） ==")
	lines.append("秒\t高さ cm\t縦の速さ m/s\t床")
	var apex := 0.0
	var air := 0.0
	var land_v := 0.0
	var prev_v := 0.0
	for r in rows:
		lines.append("%.3f\t%.1f\t%.2f\t%s" % [r[0], r[1] * 100.0, r[2], "床" if r[3] else ""])
		apex = maxf(apex, r[1])
		if air == 0.0 and r[3] and r[0] > 0.0:
			air = r[0]
			land_v = -prev_v
		prev_v = r[2]
	lines.append("いちばん高い所 %.1f cm　宙にいた時間 %.3f 秒　着いたときの下向きの速さ %.2f m/s" % [apex * 100.0, air, land_v])

	# 走り跳び
	for run in ([] if args.has("ledge-only") else [["歩いて", false], ["走って", true]]):
		await _stand(base + Vector3(0, 0.1, 30), 0.0)
		if run[1]:
			_key(KEY_SHIFT, true)
		_key(KEY_W, true)
		await _frames(30)
		var z0 := p.global_position.z
		_key(KEY_SPACE, true)
		var left := -1.0
		var t := 0
		for i in 120:
			await physics_frame
			if i == 3:
				_key(KEY_SPACE, false)
			if left < 0.0 and not p.is_on_floor():
				left = p.global_position.z
			elif left >= 0.0:
				t += 1
				if p.is_on_floor():
					break
		_key(KEY_W, false)
		_key(KEY_SHIFT, false)
		lines.append("%s跳んで、宙にいるあいだに前へ %.2f m（%.3f 秒）" % [run[0], absf(p.global_position.z - left), (t + 1) / 60.0])
		await _frames(10)

	if not args.has("skip-ledge"):
		lines.append("== 段（宙の板の上の箱。手前で跳んで、上に乗れたか） ==")
		var best := {}
		var h := float(args.get("from", "0.30"))
		var lane := 0
		while h <= float(args.get("to", "1.20")) + 0.01:
			var ok_any := []
			for run in [["歩き", false], ["走り", true]]:
				for d in [-1.0, 0.2, 0.5, 0.8, 1.1]:   # -1 は跳ばずに歩いて当たる
					# 箱は手前の縁が z = -1 の所。プレイヤーは z = 2 から歩き出し、縁の d m 手前で Space
					var x := -36.0 + lane * 3.0
					lane += 1
					if lane > 24:
						lane = 0
					var box := _box(flat, base + Vector3(x, h * 0.5, -1.0 - 1.0), Vector3(2.0, h, 2.0))
					await _stand(base + Vector3(x, 0.1, 2.0), 0.0)
					if run[1]:
						_key(KEY_SHIFT, true)
					_key(KEY_W, true)
					var pressed := false
					for i in 150:
						await physics_frame
						var front := p.global_position.z - base.z - 0.35 - (-1.0)   # 体の前の縁から箱の手前の縁まで
						if not pressed and d >= 0.0 and front <= d:
							_key(KEY_SPACE, true)
							pressed = true
						elif pressed and p.velocity.y > 0.5:
							_key(KEY_SPACE, false)
						if p.global_position.z - base.z < -1.6:
							break
					_key(KEY_SPACE, false)
					_key(KEY_W, false)
					_key(KEY_SHIFT, false)
					await _frames(45)
					if args.has("debug"):
						lines.append("  %s %.1f: 終わりの位置 %s" % [run[0], d, p.global_position - base])
					var on := p.global_position.y > base.y + h - 0.05 and p.global_position.z - base.z < -1.0
					if on:
						ok_any.append("%s 跳ばずに" % run[0] if d < 0.0 else "%s %.1f m 手前" % [run[0], d])
						var k: String = run[0] + ("跳ばず" if d < 0.0 else "")
						best[k] = maxf(best.get(k, 0.0), h)
					box.queue_free()
					await _frames(2)
			lines.append("%.2f m\t%s" % [h, ", ".join(PackedStringArray(ok_any)) if ok_any.size() else "乗れない"])
			h += 0.05
		lines.append("乗れたいちばん高い箱: 跳んで 歩き %.2f m・走り %.2f m　跳ばずに 歩き %.2f m・走り %.2f m（STEP_UP = %.2f m）"
				% [best.get("歩き", 0.0), best.get("走り", 0.0), best.get("歩き跳ばず", 0.0), best.get("走り跳ばず", 0.0), p.STEP_UP])

	print("\n".join(lines))
	quit()


func _box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var c := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	c.shape = s
	b.add_child(c)
	parent.add_child(b)
	b.global_position = center
	return b
