extends SceneTree
## 通信の確かめ: 手の双眼鏡の解放（2026-11-10）。つなぐ側が双眼鏡を買い、首の枠で手に持ってのぞくと、ホストの画面でも
## 同じ段を持ち、相手の人形がその段の双眼鏡を目に当てる。手袋もつなぐ側ではめ替えると、ホストの画面で同じ段になる。
##   Godot --path game --resolution 1000x640 -s res://tools/inventory_unlock_net.gd -- --host --port=24791 --no-sound --no-pip --no-buttons --bots=0 --lodge-bots=0 --roam-bots=0 --no-save --dir=/path
##   Godot --path game --resolution 1000x640 -s res://tools/inventory_unlock_net.gd -- --join=127.0.0.1 --port=24791 --no-sound --no-pip --no-buttons --bots=0 --lodge-bots=0 --roam-bots=0 --no-save --dir=/path

const Craft := preload("res://craft.gd")

var args := {}
var main: Node3D
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	DirAccess.make_dir_recursive_absolute(_dir())
	(_host if args.has("host") else _join).call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/inventory_unlock_net")


func _check(what: String, ok: bool) -> void:
	print("OK  " if ok else "だめ ", what)
	if not ok:
		fails += 1


func _wait(cond: Callable, limit := 40.0) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call():
			return true
		await create_timer(0.1).timeout
		t += 0.1
	return false


func _host() -> void:
	await _wait(func() -> bool: return not main.net.remotes.is_empty())
	var r: Node3D = main.net.remotes.values()[0]
	await create_timer(2.0).timeout
	main.craft.send({"kind": "earn", "who": r.id, "n": 2000, "at": r.global_position})
	var c = main.craft
	_check("相手が遠見と夜目を買った（ホストの画面で）", await _wait(func() -> bool: return c.scope_index(r.id, "binoculars_far") >= 0 and c.scope_index(r.id, "binoculars_night") >= 0))
	_check("相手の持ち物の場所は空いたまま（%d）" % c.count(r.id), c.count(r.id) == 0)
	_check("相手の首は夜目（ホストの画面で）", await _wait(func() -> bool: return c.scope(r.id).get("kind", "") == "binoculars_night"))
	_check("相手の人形は夜目の双眼鏡を目に当てる", await _wait(func() -> bool: return r.doll.peek == "binoculars_night"))
	_check("相手が遠見に替えると、ホストの画面でも遠見", await _wait(func() -> bool: return c.scope(r.id).get("kind", "") == "binoculars_far"))
	_check("相手の人形は遠見の双眼鏡を目に当てる", await _wait(func() -> bool: return r.doll.peek == "binoculars_far"))
	_check("相手の手袋はフェルト（ホストの画面で）", await _wait(func() -> bool: return is_instance_valid(r) and c.glove_grade(r.id) == "gloves_felt"))
	_check("相手の人形の手袋もフェルト", await _wait(func() -> bool: return is_instance_valid(r) and String(r.doll.gloves) == "gloves_felt"))
	await _wait(func() -> bool: return main.net.remotes.is_empty(), 15.0)
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)


func _join() -> void:
	await _wait(func() -> bool: return main.net.online and not main.net.remotes.is_empty())
	await create_timer(3.0).timeout
	var p: CharacterBody3D = main.player
	var c = main.craft
	await _wait(func() -> bool: return c.wallet(p.id) >= 2000, 10.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	p.set_third(false)
	c.send({"kind": "buy", "who": p.id, "item": {"kind": "binoculars_far"}})
	await _wait(func() -> bool: return c.scope_index(p.id, "binoculars_far") >= 0, 6.0)
	c.send({"kind": "buy", "who": p.id, "item": {"kind": "binoculars_night"}})
	_check("つなぐ側で夜目を買い、首の枠で手に持つ", await _wait(func() -> bool: return p.held().get("kind", "") == "binoculars_night" and c.hands[p.id] == Craft.NECK, 6.0))
	_check("つなぐ側の持ち物の場所は空いたまま", c.count(p.id) == 0)
	p._left_click()
	_check("つなぐ側で夜目をのぞく", await _wait(func() -> bool: return p.peek == "hand", 3.0))
	await create_timer(3.0).timeout
	p.peek_stop()
	await create_timer(1.0).timeout
	main.craft_ui.equip(0, "binoculars")   # 遠見に替える（装備の画面の札を押すのと同じ）
	await _wait(func() -> bool: return c.scope(p.id).get("kind", "") == "binoculars_far", 6.0)
	c.send({"kind": "hand", "who": p.id, "slot": Craft.NECK})
	await _wait(func() -> bool: return p.held().get("kind", "") == "binoculars_far", 6.0)
	p._left_click()
	_check("つなぐ側で遠見をのぞく", await _wait(func() -> bool: return p.peek == "hand", 3.0))
	await create_timer(3.0).timeout
	p.peek_stop()
	if c.gloves_index(p.id, "gloves_felt") < 0:   # 保存から手袋を持っていれば、選び替える
		c.send({"kind": "buy", "who": p.id, "item": {"kind": "gloves_felt"}})
	else:
		main.craft_ui.equip(c.gloves_index(p.id, "gloves_felt"), "gloves")
	_check("つなぐ側でフェルトの手袋をはめる", await _wait(func() -> bool: return c.glove_grade(p.id) == "gloves_felt", 6.0))
	await create_timer(4.0).timeout
	print("だめの数: ", fails)
	quit(0 if fails == 0 else 1)
