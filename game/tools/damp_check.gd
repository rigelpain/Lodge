extends SceneTree
## 紙の人形の水と熱（damp.gd）が、場所と出来事でどう動くかを確かめる（数字だけ出す）。
##   Godot --headless --fixed-fps 60 --path game -s res://tools/damp_check.gd -- --no-sound
## あなたを順に置いて、水・熱・差し引きの点・段・歩く速さ・押す力・人形の見た目・姿勢のコマの間隔・バッジを出す:
##   外（ふもと）に 60 秒立つ → 雪玉が 3 回当たる → 濡れて冷えた（水 60・熱 40）から暖炉のそば（1.5 m）に 30 秒 → 外に 180 秒 →
##   乾燥機の前に 20 秒 → ロッジの中（暖炉から離れた所）に 150 秒 → 風除室に 30 秒
## 仲間（押す係）は止めずに動かし、ソリを押して登るあいだの値も出す

const Doll := preload("res://doll.gd")
const Audio := preload("res://audio.gd")

var args := {}
var main: Node3D
var p: Node3D
var _rows: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _wait(sec: float) -> void:
	for i in int(sec * Engine.physics_ticks_per_second):
		await physics_frame


func _put(at: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO


func _floor(at: Vector3) -> Vector3:
	var hit := root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at - Vector3.UP * 4.0))
	return hit.position + Vector3.UP * 0.05 if hit else at


func _row(what: String) -> void:
	var dm = main.damp
	var bs := ""
	for b in main.badges.of(p.id):
		bs += "%s%s " % [b.icon, "↑" if b.dir > 0 else "↓".repeat(b.level)]
	_rows.append("| %s | %.0f | %.0f | %+.2f | %s | ×%.2f | ×%.2f | %.2f | %.1f | %s | %.1f °C |" % [what, dm.water_of(p.id), dm.heat_of(p.id), dm.score(p.id),
		dm.STAGES[dm.stage_of(dm.score(p.id))][1], dm.speed_k(p.id), dm.push_k(p.id),
		p.doll.damp, p.doll.pose_step, bs if bs != "" else "なし", root.get_node("Temperature").at(p.global_position + Vector3.UP)])


func _run() -> void:
	await _wait(0.5)
	p = main.player
	if main.settings:
		main.settings.set_open(false)
	var lodge: Node3D = main.get_node("Lodge")
	var fire := lodge.find_child("light_fire", true, false) as Node3D
	var dryer := root.find_child("slot_food_kitchen", true, false) as Node3D
	var foot := Vector3(6.0, main.height(6.0, 30.0) + 0.1, 30.0)
	_rows.append("| 場面 | 水 | 熱 | 点 | 段 | 歩く速さ | 押す力 | 人形の見た目 | コマの間隔 | バッジ | 気温 |")
	_rows.append("|---|---|---|---|---|---|---|---|---|---|---|")
	_row("始め")
	_put(foot)
	await _wait(60.0)
	_row("外に 60 秒立つ")
	for i in 3:
		main.emotes.happened.emit({"kind": "hit", "who": p.id, "by": -1, "frame": Doll.frame_index() + 1, "point": p.global_position, "dir": Vector3.FORWARD})
		await _wait(0.5)
	_row("雪玉が 3 回当たる")
	main.damp.put(p.id, 60.0, 40.0)
	_row("（濡れて冷えた: 水 60・熱 40 にする）")
	var near_fire := _floor(fire.global_position + lodge.global_basis.z * 1.5) if fire else foot
	_put(near_fire)
	for t in [5, 10, 20]:
		await _wait(5.0 if t == 5 else (5.0 if t == 10 else 10.0))
		_row("暖炉のそば %d 秒" % t)
	await _wait(10.0)
	_row("暖炉のそば 30 秒")
	_put(foot)
	await _wait(60.0)
	_row("外に 60 秒（熱が抜けていく）")
	await _wait(120.0)
	_row("外にさらに 120 秒")
	if dryer:
		main.damp.put(p.id, 60.0, 40.0)
		var front: Vector3 = dryer.to_global(main.damp.DRYER_AT + Vector3(0, 0, 2.0))   # 乾燥機の前（部屋の側）
		_put(_floor(front + Vector3.UP * 0.5))
		await _wait(20.0)
		_row("水 60・熱 40 から乾燥機の前に 20 秒")
	main.damp.put(p.id, 90.0, 40.0)
	_put(_floor(lodge.to_global(Vector3(14.0, 0.5, 4.0))))
	await _wait(60.0)
	_row("水 90・熱 40 からロッジの中（暖炉から遠く）に 60 秒")
	await _wait(90.0)
	_row("ロッジの中に 150 秒")
	var vest: Vector3 = lodge.to_global(Audio.VEST)
	_put(_floor(vest))
	await _wait(30.0)
	_row("風除室に 30 秒")
	print("\n".join(_rows))
	# 押す係の仲間の値（外でソリを押している）
	for id in main.emotes.people:
		var who: Node3D = main.emotes.people[id]
		if who != p and who.get("state") != null:
			print("仲間 %d（%s）: 水 %.0f 熱 %.0f %s" % [id, who.doll.kind, main.damp.water_of(id), main.damp.heat_of(id), "押している" if who.doll.effort else ""])
	quit()
