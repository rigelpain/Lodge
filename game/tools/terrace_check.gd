extends SceneTree
## 2 階のテラス（西の端を外にした所。lodge/dims.py の X2_0）の確かめ（数字で）。
##   Godot --path game --resolution 1280x720 -s res://tools/terrace_check.gd -- --bots=0 --lodge-bots=0 --no-pip
## 1. 中か外か（audio.gd の zone_at）・温度（temperature.gd）・足もとの床（audio.gd の surface_at）を、テラス・2 階の中・1 階で
## 2. 体（半径 0.3 の筒）を、テラスから西の壁の戸を抜けて中の通り道へ東へ押す。戸の外の壁の所では止まるか
## 3. 雪よけの箱（main.gd の _shelter_snow）が、テラスの上を覆っていないか
## 場所はロッジの座標（x 東, y 北, 高さ。Godot ではロッジの (x, 高さ, -y)）。合わない物が 1 つでもあれば終わりの番号を 1 にする

const Audio := preload("res://audio.gd")
const FL2 := 6.10
const DOOR_Y := 3.27    # 西の壁のテラスへの戸（dims の gy(2.6)）

## [名前, 場所, 期待する zone（0 外・2 中）, 期待する床]
const SPOTS := [
	["テラス西の端（卓のあいだ）", Vector3(-16.6, 5.8, FL2), 0, "wood"],
	["テラス西の端の北の隅", Vector3(-20.8, 12.0, FL2), 0, "wood"],
	["テラス南の帯（前からのテラス）", Vector3(0.0, -9.0, FL2), 0, "wood"],
	["テラス戸の前（外のマット）", Vector3(-12.6, DOOR_Y, FL2), 0, "mat"],
	["2 階の中の通り道（戸の内のマット）", Vector3(-11.0, DOOR_Y, FL2), 2, "mat"],
	["2 階の畳", Vector3(4.0, 3.0, FL2 + 0.4), 2, "wood"],
	["2 階の東の端（衣装掛けの前）", Vector3(19.5, 2.2, FL2), 2, "wood"],
	["1 階の食堂（テラスの下）", Vector3(-16.6, 5.8, 0.45), 2, "wood"],
	["1 階の食堂（南）", Vector3(0.0, -9.0, 0.45), 2, "wood"],
]

var main: Node3D
var lodge: Node3D
var bad := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _g(q: Vector3) -> Vector3:
	return lodge.to_global(Vector3(q.x, q.z, -q.y))


func _ok(cond: bool, msg: String) -> void:
	print(("  ok  " if cond else "  NG  ") + msg)
	if not cond:
		bad += 1


func _run() -> void:
	await create_timer(3.0).timeout
	lodge = main.get_node("Lodge")
	var audio = main.get_node_or_null("Audio")
	var temp = root.get_node_or_null("Temperature")
	print("1. 中か外か・温度・床")
	for s in SPOTS:
		var at := _g(s[1])
		var zone: int = Audio.zone_at(lodge, at + Vector3.UP * 0.02)
		var eye: int = Audio.zone_at(lodge, at + Vector3.UP * 1.55)
		var t: float = temp.at(at + Vector3.UP * 0.02) if temp else NAN
		var floor_kind: String = audio.surface_at(at + Vector3.UP * 0.02) if audio else "?"
		_ok(zone == s[2] and eye == s[2] and floor_kind == s[3],
			"%s: zone 足 %d 目 %d（期待 %d）、温度 %.1f、床 %s" % [s[0], zone, eye, s[2], t, floor_kind])
	print("2. 戸を抜ける")
	for row in [[DOOR_Y, true, "戸の真ん中"], [DOOR_Y - 0.55, true, "戸の南寄り"], [6.5, false, "戸の北の壁"], [-1.0, false, "戸の南の壁"]]:
		var b := CharacterBody3D.new()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.6
		cs.shape = cap
		cs.position.y = 0.8
		b.add_child(cs)
		root.add_child(b)
		b.global_position = _g(Vector3(-13.5, row[0], FL2 + 0.05))
		var east := lodge.global_basis * Vector3.RIGHT
		var opened := 0.0   # 2 階の戸（lodge.gd の開き戸）が開いた度合いのいちばん大きい所
		for i in 150:
			b.velocity = east * 2.0 + Vector3.DOWN * 2.0
			b.move_and_slide()
			await physics_frame
			for d in lodge.get("_swing"):
				if absf(d.center.x - (-11.82)) < 0.5 and absf(d.center.z + DOOR_Y) < 1.5:
					opened = maxf(opened, d.a)
		var l := lodge.to_local(b.global_position)
		var through := l.x > -11.2
		_ok(through == row[1], "%s（y %.2f）: x %.2f まで進んだ（%s）、戸の開き %.2f" % [row[2], row[0], l.x, "抜けた" if through else "止まった", opened])
		if row[1]:
			_ok(opened > 0.9, "  戸が開いた（%.2f）" % opened)
		b.queue_free()
	print("3. 雪よけの箱")
	var boxes := lodge.find_children("*", "GPUParticlesCollisionBox3D", false, false)
	var over := 0
	for c: GPUParticlesCollisionBox3D in boxes:
		for q in [Vector3(-16.6, 5.8, FL2 + 1.0), Vector3(-20.8, 12.0, FL2 + 1.0)]:
			var lq := c.to_local(_g(q))
			if absf(lq.x) < c.size.x / 2 and absf(lq.y) < c.size.y / 2 and absf(lq.z) < c.size.z / 2:
				over += 1
	_ok(over == 0, "テラスの西の端の上を覆う雪よけの箱: %d（箱 %d 個）" % [over, boxes.size()])
	var inside := 0
	for c: GPUParticlesCollisionBox3D in boxes:
		var lq := c.to_local(_g(Vector3(-11.0, DOOR_Y, FL2 + 1.0)))
		if absf(lq.x) < c.size.x / 2 and absf(lq.y) < c.size.y / 2 and absf(lq.z) < c.size.z / 2:
			inside += 1
	_ok(inside > 0, "2 階の中の通り道を覆う雪よけの箱: %d" % inside)
	print("合わない物: %d" % bad)
	quit(1 if bad > 0 else 0)
