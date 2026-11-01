extends SceneTree
## 持ち物（手持ち 6 ＋ かばん 6）を一人称で撮る（確かめ用）。
##   Godot --path game --resolution 1600x900 -s res://tools/inventory_shots.gd -- --bots=0 --no-sound --no-pip --hud-idle=0 --out=/path/a.png
##     [--items=10] [--held=1] [--wait=秒（撮る前に待つ。--hud-idle と合わせて引っこんだ所を撮る）] [--gear（装備の画面）| --machine（ミシンの画面）] [--menu=N（N 番を押した小窓）] [--drag=N（N 番を引きずっている）]
## 名前の札は持ち替えてから 2 秒で消えるので、持ち替えて 0.6 秒で撮る

const ITEMS := [
	{"kind": "folded", "sled": "mid", "fabric": "navy", "tag": 1},
	{"kind": "pattern", "sled": "small"},
	{"kind": "fabric", "fabric": "plum"},
	{"kind": "folded", "sled": "small", "fabric": "holly", "tag": 4},
	{},
	{"kind": "pattern", "sled": "large"},
	{"kind": "food", "dish": "ramen", "step": 1},
	{"kind": "fabric", "fabric": "navy"},
	{"kind": "food", "dish": "taiyaki", "step": 0},
	{"kind": "pattern", "sled": "mid"},
	{"kind": "folded", "sled": "sack", "fabric": "", "tag": -1},
	{},
]

var args := {}
var main: Node3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.5).timeout
	var p = main.player
	var c = main.craft
	var ui = main.craft_ui
	p.set("_pitch", -0.1)
	p.set_third(false)
	var b: Array = ITEMS.slice(0, int(args.get("items", "12"))).duplicate(true)
	while b.size() < 12:
		b.append({})
	c.bags[p.id] = b
	c.wallets[p.id] = int(args.get("coins", "37"))
	if args.has("gear"):
		ui.open_gear()   # 装備の画面（I）
	if args.has("machine"):
		ui.open_machine()
	await create_timer(1.5).timeout
	c.send({"kind": "hand", "who": p.id, "slot": int(args.get("held", "0"))})
	if args.has("menu"):
		ui._inv_menu = int(args.menu)
	await create_timer(0.3).timeout
	if args.has("drag") and ui._inv_rects.size() > 0:
		var i := int(args.drag)
		var r: Rect2 = ui._inv_rects[i]
		ui._drag = {"from": i, "start": r.get_center(), "at": (ui._inv_rects[4] as Rect2).get_center() + Vector2(6, -4), "moved": true}
	await create_timer(0.3 + float(args.get("wait", "0"))).timeout
	await process_frame
	var path: String = args.get("out", "/tmp/inventory.png")
	root.get_texture().get_image().save_png(path)
	print("撮った: ", path)
	quit()
