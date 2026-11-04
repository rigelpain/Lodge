extends SceneTree
## ロッジのガラスの壁の柱を、中から・外から撮る（細くする前と後を比べる確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/window_post_shots.gd -- --bots=0 --no-sound --no-pip --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ）

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D

# [名前, 立つ所 (x, y), 見る所 (x, y, 高さ)]
const VIEWS := [
	["01_in_south", Vector2(4.0, -8.5), Vector3(4.0, -30.0, 3.2)],          # 食堂から南の窓の外
	["02_in_south_wide", Vector2(14.0, -4.0), Vector3(-2.0, -24.0, 2.6)],    # 食堂から斜めに南の窓の外（柱が重なって見える向き）
	["03_in_south_bar", Vector2(1.6, -11.5), Vector3(1.6, -30.0, 2.4)],      # 窓向きのカウンターの椅子のあたりから
	["04_in_west", Vector2(-15.5, 0.0), Vector3(-40.0, 0.0, 2.6)],           # 食堂の西から西の窓の外
	["05_out_south", Vector2(6.0, -34.0), Vector3(6.0, -12.7, 3.0)],         # 外の正面から
	["06_out_south_near", Vector2(-4.0, -19.0), Vector3(1.0, -12.7, 2.8)],   # 正面に寄って（左に自販機 3）
	["07_out_west", Vector2(-36.0, 0.0), Vector3(-21.8, 0.0, 2.8)],          # 外の西から
	["08_rental", Vector2(-16.0, -11.0), Vector3(-21.8, -7.5, 1.4)],         # 貸出の棚（西のガラスの壁ぎわ）
	["09_corner_sw_in", Vector2(-7.0, -9.5), Vector3(-9.1, -12.7, 2.0)],     # 丸太の壁とガラスの壁のつなぎ目を中から
	["10_corner_se_out", Vector2(24.0, -16.0), Vector3(21.8, -12.7, 2.4)],   # 南東の隅を外から
	["11_corner_nw_out", Vector2(-25.0, 15.0), Vector3(-21.8, 12.7, 2.4)],   # 北西の隅を外から
	["12_west_door", Vector2(-16.5, 11.45), Vector3(-21.8, 11.45, 2.0)],     # 西のガラスの戸
	["13_post_foot", Vector2(4.8, -14.6), Vector3(3.27, -12.7, 0.9)],        # 柱の足もとと水切りを外から
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
	return args.get("dir", "/tmp/window_posts")


func _process(_dt: float) -> bool:
	if main and main.settings and main.settings.is_open and p:
		main.settings.set_open(false)
		p.menu_open = false
	return false


func _w(q: Vector2) -> Vector3:
	var g := lodge.to_global(Vector3(q.x, 0, -q.y))
	var r := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 3.0, g + Vector3.DOWN * 30.0)
	r.exclude = [p.get_rid()]
	var hit := root.get_world_3d().direct_space_state.intersect_ray(r)
	return hit.position if hit else g


func _run() -> void:
	await create_timer(3.0).timeout
	p = main.player
	p.set_third(false)
	lodge = main.get_node("Lodge")
	for v in VIEWS:
		var at := _w(v[1]) + Vector3.UP * 0.05
		var to := lodge.to_global(Vector3(v[2].x, v[2].z, -v[2].y))
		var eye := at + Vector3.UP * 1.55
		p.doll.set("_cold_t", 999.0)   # 白い息が景色にかぶらないように、息を止める
		p.doll.set("_cold", 0.0)
		p.doll.set("_cold_want", 0.0)
		for i in 2:   # 着地や仲間に押されてずれた分を戻し、向きも合わせ直す
			p.global_position = at
			p.velocity = Vector3.ZERO
			p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
			p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))
			await create_timer(0.5).timeout
		await process_frame
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
	quit()
