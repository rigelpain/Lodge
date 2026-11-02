extends SceneTree
## 頭・肩の小物とミニオン（pals.gd・companions.gd・pals_ui.gd・pal_stall.gd）を撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/pals_shots.gd -- --part=<名前> --dir=/path/shots [main.gd の引数]
## --part:
##   stall   衣装掛けの横の紙細工屋さんの前（一人称・三人称）と、買って付け替える画面の頭・肩の段（--spawn=pals を付ける）
##   dolls   7 体の人形に頭と肩の小物を載せて、前から撮る（三人称・HUD の自分の顔・360° の映像も入る）。--spawn=pals を付ける
##   pets    外で、ミニオン 7 匹の 歩く・座る・寝る を横から撮る
##   ride    ソリに乗って滑ると、ミニオンが横を走ってついてくる
##   hearth  ロッジの中で、ミニオンが暖炉の前で寝て待つ（--spawn=inside を付ける）
## 保存（user://my_tag.cfg）は、始めに写しを取り、終わりに戻す（確かめで買った物が残らないように）

const Doll := preload("res://doll.gd")
const Pals := preload("res://pals.gd")

const SAVE := "user://my_tag.cfg"
var args := {}
var main: Node3D
var _save := PackedByteArray()
var _had_save := false
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_save = FileAccess.get_file_as_bytes(SAVE)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/pals_shots")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and main.player:
		main.settings.set_open(false)
		main.player.menu_open = false
	return false


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var path := _dir().path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("保存: ", path)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _end() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_buffer(_save)
		f.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()


func _pals(p: Node) -> Node:
	return main.get_node_or_null("Pals%d" % int(p.get("id")))


## 確かめ用のカメラ: at から to を見る
func _look(at: Vector3, to: Vector3, fov := 40.0) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.cull_mask = 0xFFFFF & ~(1 << 2)   # 一人称の手（層 3）は映さない
		main.add_child(cam)
	cam.fov = fov
	cam.global_position = at
	cam.look_at(to, Vector3.UP)
	cam.make_current()


func _give_all(p: Node) -> void:
	var c: Node = main.craft
	c.wallets[p.id] = 0
	for k in Pals.PERCH_ORDER + Pals.PET_ORDER:
		c.send({"kind": "pal_own", "who": p.id, "key": k})


func _wear(p: Node, k: String) -> void:
	main.craft.send({"kind": "pal_wear", "who": p.id, "slot": Pals.slot_of(k), "key": k})


func _run() -> void:
	await _wait(4.0)
	var p: CharacterBody3D = main.player
	match args.get("part", "stall"):
		"stall":
			await _part_stall(p)
		"dolls":
			await _part_dolls(p)
		"pets":
			await _part_pets(p)
		"ride":
			await _part_ride(p)
		"hearth":
			await _part_hearth(p)
	_end()


func _part_stall(p: CharacterBody3D) -> void:
	print("紙細工屋さん: ", main.paper_lady.global_position, " 開ける: ", p.paper_shop_near())
	p.set_third(false)
	await _wait(1.5)
	await _shot("stall_fp")
	p.set_third(true)
	await _wait(1.2)
	await _shot("stall_tp")
	p.set_third(false)
	main.craft.wallets[p.id] = 260
	var ui = main.paper_shop_ui
	for i in 2:
		ui.open(Pals.SLOTS[i])
		await _wait(1.0)
		await _shot("ui_" + Pals.SLOTS[i])
		if i == 0:   # 買う: どんぐり（40）を押すと、すぐ頭に付く。足りないモモンガ（200 → 財布 220）は買える、月と兎は震える
			var ks: Array = ui.keys()
			print("どんぐり: ", ui.choose(ks.find("acorn")), " 財布: ", main.craft.wallet(p.id))
			await _wait(0.15)
			await _shot("ui_head_bought")
			print("月と兎: ", ui.choose(ks.find("moon_rabbit")))
			await _wait(0.1)
			await _shot("ui_head_short")
		ui.close()
	print("付けている: ", main.craft.pals_wear[p.id])


func _part_dolls(p: CharacterBody3D) -> void:
	_give_all(p)
	var wear := {"kasa": ["crane", "blue_bird"], "origami": ["acorn", "chameleon"], "news": ["chiyo_bird", "hummingbird"],
		"robo": ["pumpkin", "phoenix"], "musha": ["maple", "blue_bird"], "ningyo": ["moon_rabbit", "hummingbird"], "golem": ["squirrel", "phoenix"]}
	var kinds: Array = Doll.KINDS if not args.has("kinds") else Array(String(args.kinds).split(","))
	_outside(p)   # 雪の上（前から撮ると、うしろが雪の丘）
	for k in kinds:
		main.craft.send({"kind": "doll", "who": p.id, "doll": k})
		for it in wear[k]:
			_wear(p, it)
		await _wait(0.8)
		var d: Node3D = p.doll
		var top := float(Doll.TOP[k]) * float(Doll.SCALE[k])
		var fwd := -d.global_basis.z
		var right := d.global_basis.x
		_look(d.global_position + fwd * (top * 1.5 + 0.6) + right * 0.5 + Vector3.UP * (top * 0.75), d.global_position + Vector3.UP * top * 0.62, 38.0)
		await _wait(0.4)
		await _shot("doll_%s_front" % k)
		_look(d.global_position + right * (top * 1.2 + 0.5) + fwd * 0.3 + Vector3.UP * (top * 0.8), d.global_position + Vector3.UP * top * 0.7, 38.0)
		await _wait(0.3)
		await _shot("doll_%s_side" % k)
		p.cam.make_current()
		p.set_third(true)
		await _wait(0.8)
		await _shot("doll_%s_tp" % k)
		p.set_third(false)
		await _wait(0.5)
		await _shot("doll_%s_fp" % k)


## 外の、ふもとのスタートの横に立たせる（丘を横に見る）
func _outside(p: CharacterBody3D) -> Vector3:
	var at: Vector3 = _on_ground(p, main.START + Vector3(7.0, 0, 3.0))
	p.global_position = at
	p.rotation.y = PI * 0.5
	return at


## その所の地面の上（あなたの体は当たりから外して探る）
func _on_ground(p: CharacterBody3D, at: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 200.0, at + Vector3.DOWN * 200.0)
	q.exclude = [p.get_rid()]
	var hit := main.get_world_3d().direct_space_state.intersect_ray(q)
	return Vector3(at.x, (hit.position.y if hit else main.height(at.x, at.z)) + 0.05, at.z)


func _part_pets(p: CharacterBody3D) -> void:
	_give_all(p)
	_wear(p, "chiyo_bird")
	var keys: Array = Pals.PET_ORDER if not args.has("keys") else Array(String(args["keys"]).split(","))
	var at := _outside(p)
	await _wait(1.0)
	var pc := _pals(p)
	for k in keys:
		p.global_position = at
		p.velocity = Vector3.ZERO
		await _wait(0.3)
		_wear(p, k)
		await _wait(0.6)
		# 歩く: あなたを横へ 2 m/s で動かすと、ついて歩く
		var side: Vector3 = p.global_basis.x
		var t := 0.0
		while t < 1.6:
			p.global_position = _on_ground(p, at + side * (2.0 * t))
			p.velocity = Vector3.ZERO
			await process_frame
			t += 1.0 / 60.0
		var pp: Vector3 = pc._pos
		var fw: Vector3 = Basis(Vector3.UP, pc._yaw) * Vector3.FORWARD
		var lf: Vector3 = fw.cross(Vector3.UP)
		_look(pp + lf * 1.6 + fw * 0.4 + Vector3.UP * 0.55, pp + Vector3.UP * 0.2, 36.0)
		await _shot("pet_%s_walk" % k)
		await _wait(1.6)
		pp = pc._pos
		var to_owner: Vector3 = (p.global_position - pp)
		to_owner.y = 0
		var perp: Vector3 = to_owner.normalized().cross(Vector3.UP)
		_look(pp + perp * 1.5 - to_owner.normalized() * 0.4 + Vector3.UP * 0.6, pp + Vector3.UP * 0.2, 36.0)
		await _shot("pet_%s_sit" % k)
		pc._still = 40.0
		await _wait(0.4)
		await _shot("pet_%s_sleep" % k)
		print(k, ": 姿 ", pc._pose, " ミニオンの高さ ", snappedf(pc._pos.y, 0.01), " あなた ", snappedf(p.global_position.y, 0.01))
		p.cam.make_current()


func _part_ride(p: CharacterBody3D) -> void:
	_give_all(p)
	_wear(p, args.get("pet", "kit"))
	var s: RigidBody3D = main.sled
	await _wait(0.5)
	p.global_position = s.global_position + s.global_basis.x * 1.2
	await _wait(0.3)
	p.get_on()
	print("乗った: ", p.mode)
	var pc := _pals(p)
	for i in 6:
		s.linear_velocity = -s.global_basis.z * (4.0 + i * 3.5)
		await _wait(0.5)
		var sp: Vector3 = s.global_position
		var right: Vector3 = s.global_basis.x
		_look(sp + right * 3.0 + s.global_basis.z * 5.0 + Vector3.UP * 2.4, sp + right * 0.9 + Vector3.UP * 0.3, 50.0)
		await _shot("ride_%d" % i)
		print("ソリの速さ ", snappedf(s.linear_velocity.length(), 0.1), " ミニオンまで ", snappedf(pc._pos.distance_to(sp), 0.1), " 姿 ", pc._pose)
	p.cam.make_current()
	p.set_third(true)
	await _wait(0.6)
	await _shot("ride_tp")


func _part_hearth(p: CharacterBody3D) -> void:
	_give_all(p)
	_wear(p, args.get("pet", "kit"))
	var pc := _pals(p)
	# 食堂の中へ（ロッジでくつろぐ仲間が始まる所の近く）
	p.global_position = main.get_node("Lodge").to_global(Vector3(4.0, 1.6, -4.0))
	await _wait(2.0)
	print("ロッジの中: あなた ", p.global_position)
	await _wait(6.0)
	var spot: Vector3 = pc._hearth
	print("暖炉の前: ", spot, " ミニオン: ", pc._pos, " 姿 ", pc._pose)
	var mark: Node3D = main.get_node("Lodge").find_child("light_fire", true, false)
	_look(spot + (spot - mark.global_position).normalized() * 2.2 + Vector3.UP * 1.3, spot + Vector3.UP * 0.2, 50.0)
	await _shot("hearth_sleep")
	# 外へ出る: 起きて、うしろから駆けてくる
	var at := _outside(p)
	await _wait(1.2)
	print("外へ: ミニオン ", pc._pos, " あなた ", at, " 姿 ", pc._pose)
	p.cam.make_current()
	p.set_third(true)
	await _wait(0.6)
	await _shot("hearth_out_tp")
