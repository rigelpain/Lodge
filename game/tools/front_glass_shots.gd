extends SceneTree
## ロッジ正面（南）のガラスの壁を、外から・中から撮る（格子を外す前と後を比べる確かめ用）。
##   Godot --path game --resolution 1280x720 -s res://tools/front_glass_shots.gd -- --bots=0 --no-sound --dir=/path/shots
## 場所はロッジの座標（lodge/dims.py の x, y, 高さ）

var args := {}
var main: Node3D
var lodge: Node3D
var p: CharacterBody3D

# [名前, 立つ所 (x, y), 目の高さの足し, 見る所 (x, y, 高さ)]
const VIEWS := [
	["01_out_front", Vector2(6.0, -34.0), 0.0, Vector3(6.0, -12.7, 3.0)],
	["02_out_near", Vector2(0.0, -20.0), 0.0, Vector3(6.0, -12.7, 2.8)],
	["03_in_out", Vector2(4.0, -9.0), 0.0, Vector3(4.0, -30.0, 3.4)],
	["04_in_wide", Vector2(14.0, -3.0), 0.0, Vector3(0.0, -22.0, 2.4)],
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
	return args.get("dir", "/tmp/front_glass")


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
		var to := lodge.to_global(Vector3(v[3].x, v[3].z, -v[3].y))
		p.global_position = at
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		var eye := at + Vector3.UP * 1.55
		p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))
		await create_timer(0.5).timeout
		p.global_position = at   # 着地や仲間に押されてずれた分を戻し、向きも合わせ直す
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-(to.x - at.x), -(to.z - at.z))
		p.set("_pitch", atan2(to.y - eye.y, Vector2(to.x - eye.x, to.z - eye.z).length()))
		await create_timer(0.5).timeout
		await process_frame
		root.get_texture().get_image().save_png(_dir().path_join(v[0] + ".png"))
	quit()
