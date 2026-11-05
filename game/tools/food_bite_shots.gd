extends SceneTree
## 手に持った料理を、食べる前・1 口・2 口で撮る（確かめ用。design/food-look/）。ゲームの一人称の手のまま、ロッジの中で撮る。
##   Godot --path game --resolution 1280x720 -s res://tools/food_bite_shots.gd -- --dir=/path/shots --dishes=onigiri,taiyaki [--mouth]
## --mouth で、口もとへ運んでいるコマも撮る。名前は <料理>_<口数>.png・<料理>_<口数>_mouth.png

var args := {}
var main: Node3D
var p: CharacterBody3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/food_bite")


func _shot(name: String) -> void:
	for n in root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


## 番台の前の、灯りのある所に立つ（毎回置き直す。歩いていないのに少しずつずれるので）
func _stand() -> void:
	var sh = main.snowman_shop
	p.global_position = sh.counter.global_position + sh.counter.global_basis.z * -2.2 + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO
	var d: Vector3 = sh.counter.global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.set("_pitch", float(args.get("pitch", "-0.12")))


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	_stand()
	await create_timer(1.5).timeout
	var Food := preload("res://food.gd")
	var dishes: Array = String(args.get("dishes", "onigiri")).split(",")
	var craft = main.craft
	for dish in dishes:
		for b in 3:
			var slot: int = craft.hands.get(p.id, -1)
			if slot >= 0:
				craft._clear(p.id, slot)
			var i: int = craft._put(p.id, {"kind": "food", "dish": dish, "step": Food.route(dish).size(), "bites": b})
			craft.hands[p.id] = i
			_stand()
			await create_timer(0.5).timeout
			await _shot("%s_%d" % [dish, b])
			if args.has("mouth"):
				p.eat_held()
				p.set("_eating", false)
				for k in 40:
					await process_frame
					if p.get("_em").get("kind", "") == "eat" and p._em_k() >= 3:
						break
				await _shot("%s_%d_mouth" % [dish, b])
				await create_timer(1.6).timeout
	quit()
