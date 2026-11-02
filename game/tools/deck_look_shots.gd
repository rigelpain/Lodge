extends SceneTree
## ロッジの前のデッキ（玄関前の広場・前のデッキ）・外階段・ミニテラスの見た目を、外から見た目線と歩く目線で撮る（確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/deck_look_shots.gd -- --bots=0 --lodge-bots=0 --no-sound --no-pip --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ）。<dir>/<名前>.png に書く

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D

# [名前, 立つ所 (x, y), 立つ高さ（null なら床へ落とす）, 見る所 (x, y, 高さ)]
const VIEWS := [
	["out1_front", Vector2(-12.0, -42.0), null, Vector3(-12.0, -18.0, 1.0)],          # 外: 正面から広場と前のデッキ
	["out2_southwest", Vector2(-34.0, -32.0), null, Vector3(-19.0, -19.0, 2.0)],      # 外: 南西から外階段とミニテラス
	["out3_east", Vector2(14.0, -30.0), null, Vector3(-2.0, -15.0, 0.5)],             # 外: 南東から前のデッキと広場
	["walk1_plaza", Vector2(-13.4, -23.0), null, Vector3(-13.4, -17.0, 0.6)],         # 歩く: 広場から風除室へ
	["walk2_feet", Vector2(-15.0, -21.5), null, Vector3(-15.0, -19.6, 0.0)],         # 歩く: 広場の足もと
	["walk3_stair", Vector2(-18.95, -23.6), null, Vector3(-18.95, -17.0, 3.0)],       # 歩く: 外階段の登り口から見上げる
	["walk4_mini", Vector2(-18.95, -17.4), 3.28, Vector3(-23.5, -18.5, 2.6)],         # 歩く: 踊り場からミニテラス
	["walk5_deck", Vector2(-4.0, -14.5), null, Vector3(6.0, -14.0, 0.0)],            # 歩く: 前のデッキを東へ
]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(_dir())
	_run.call_deferred()


func _dir() -> String:
	return args.get("dir", "/tmp/deck_look")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _w(q: Vector2, h: Variant) -> Vector3:
	if h != null:
		return lodge.to_global(Vector3(q.x, float(h) + 0.02, -q.y))
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 3.0, g + Vector3.DOWN * 30.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _aim(at: Vector3, to: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
	var eye := at + Vector3.UP * 1.55
	p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	main.sled.reset_to(lodge.to_global(Vector3(10.0, 0.0, 40.0)) + Vector3.UP * 3.0)
	for v in VIEWS:
		var at := _w(v[1], v[2]) + Vector3.UP * 0.05
		var to := lodge.to_global(Vector3(v[3].x, v[3].z, -v[3].y))
		_aim(at, to)
		await create_timer(0.6).timeout
		_aim(at, to)   # 着地でずれた分を戻す
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
		print("撮った: ", v[0])
	quit()
