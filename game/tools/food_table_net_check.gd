extends SceneTree
## 通信の確かめ（机のある席の食べ方が相手の画面でも同じに見えるか）: 同じ Mac で 2 つ起動し、1 つをホストにする
##   Godot --path game --resolution 960x540 --position 0,40 -s res://tools/food_table_net_check.gd -- --host --dir=/path/
##   Godot --path game --resolution 960x540 --position 980,40 -s res://tools/food_table_net_check.gd -- --join=127.0.0.1 --dir=/path/
## ホストが机のある椅子に座り、ラーメン→肉まん→焼きサンマを食べる。つなぐ側はホストの人形を近くから撮り、
## 出来事（eat_t）と机の状況が届いたかを書き出す。

const Food := preload("res://food.gd")
const Doll := preload("res://doll.gd")

var args := {}
var main: Node3D
var p: CharacterBody3D
var _seen := {}
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/food_table_net")


func _wait(t: float) -> void:
	await create_timer(t).timeout


func _run() -> void:
	await _wait(0.5)
	p = main.player
	p.set_third(false)
	var t := 0.0
	while main.net.remotes.is_empty() and t < 40.0:
		await _wait(0.5)
		t += 0.5
	print("つながった ", main.net.remotes.keys())
	if args.has("host"):
		await _host()
	else:
		await _join()
	quit()


func _host() -> void:
	await _wait(6.0)
	var seats = p.seats
	var i := -1
	for j in seats.seats.size():
		if seats.seats[j].kind == "chair" and seats.seats[j].has("table"):
			i = j
			break
	p.global_position = seats.seats[i].stand
	await _wait(0.3)
	print("host 座る ", seats.send({"kind": "sit", "who": p.id, "seat": i}))
	await _wait(1.5)
	var craft = main.craft
	for dish in ["ramen", "nikuman", "sanma"]:
		var slot: int = craft.hands.get(p.id, -1)
		if slot >= 0:
			craft._clear(p.id, slot)
		craft.hands[p.id] = craft._put(p.id, {"kind": "food", "dish": dish, "step": Food.route(dish).size(), "bites": 0})
		await _wait(1.0)
		p.eat_held()
		await _wait(3.5)
	await _wait(1.0)


func _join() -> void:
	var t := 0.0
	var t0 := Time.get_ticks_msec()
	var cam: Camera3D = null
	while t < 30.0:
		await process_frame
		t = (Time.get_ticks_msec() - t0) / 1000.0
		for id in main.net.remotes:
			var r = main.net.remotes[id]
			var d = r.doll
			var em: Array = d.emote_now()
			var key := "%s/%s/%s" % [d.eat_table.get("dish", ""), em[0], d.emote.get("style", "")]
			if key != _seen.get("k", ""):
				_seen["k"] = key
				print("join 人%d 机=%s 身ぶり=%s 食べ方=%s" % [id, d.eat_table.get("dish", "なし"), em[0], d.emote.get("style", "")])
			if em[0] == "eat_t" and em[1] >= 0:
				if cam == null:
					cam = Camera3D.new()
					root.add_child(cam)
					var f: Vector3 = d.eat_table.face
					var right := f.cross(Vector3.UP).normalized()
					cam.look_at_from_position(r.global_position + right * -1.05 + f * 0.95 + Vector3.UP * 1.0, r.global_position + f * 0.28 + Vector3.UP * 0.6)
					cam.fov = 42.0
					cam.current = true
				if int(em[1]) % 8 == 2 and not _seen.has("%s_%d_%d" % [d.emote.dish, d.emote.frame, em[1]]):
					_seen["%s_%d_%d" % [d.emote.dish, d.emote.frame, em[1]]] = true
					for n in root.find_children("*", "CanvasLayer", true, false):
						(n as CanvasLayer).visible = false
					await process_frame
					root.get_texture().get_image().save_png(_dir().path_join("join_%s_%02d.png" % [d.emote.dish, em[1]]))
					_n += 1
	print("join 撮った ", _n)
