@tool
extends Node3D
## ロッジ（lodge/ の Blender の台本で作った glb）。エディタで開いても手芸の素材と灯りで見えるよう @tool にする。
## 素材は glb の役割の名前（log, roof, snow …）で look.gd の素材に差し替え、灯りの目印（light_*）に暖色の灯りを灯す。
## 当たり判定は lodge_collision.glb（名前の -colonly で、見た目なしの当たり判定になる）。

const Look := preload("res://look.gd")

var fire_light: OmniLight3D
var _t := 0.0
var _auto_doors: Array[Node3D] = []   # 風除室の内の自動ドア（左右へ引き分ける）
var _auto_home: Array[float] = []
var _auto_sign: Array[float] = []
var _auto_area: Area3D
var _auto_open := 0.0
const AUTO_SLIDE := 1.40               # 引き分ける幅 (m)。開くと丸太の壁の中へ隠れる


func _ready() -> void:
	var lamp := Look.paper(Color(0.96, 0.84, 0.63))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.74, 0.44)
	lamp.emission_energy_multiplier = 1.6
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.54, 0.23)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.5, 0.18)
	fire.emission_energy_multiplier = 4.0
	var mats := {
		"log": Look.felt(Color(0.49, 0.33, 0.21), 1.2),     # 丸太は巻いたフェルト
		"roof": Look.felt(Color(0.16, 0.20, 0.41), 1.2),    # 藍のフェルト
		"snow": Look.snow(),
		"stone": Look.felt(Color(0.50, 0.46, 0.42), 2.0),   # フェルトの小石
		"post": Look.wood(Color(0.44, 0.27, 0.16)),
		"door": Look.wood(Color(0.43, 0.29, 0.19)),
		"board": Look.wood(Color(0.78, 0.63, 0.42)),
		"ceiling": Look.wood(Color(0.78, 0.63, 0.42)),
		"floor": Look.wood(Color(0.60, 0.44, 0.29)),
		"deck": Look.wood(Color(0.73, 0.58, 0.40)),
		"rail": Look.wood(Color(0.66, 0.50, 0.31)),
		"frame": Look.paper(Color(0.93, 0.88, 0.79)),
		"tatami": Look.paper(Color(0.85, 0.82, 0.66)),
		"cushion": Look.felt(Color(0.79, 0.54, 0.40)),
		"quilt": Look.felt(Color(0.62, 0.37, 0.32)),
		"felt_red": Look.felt(Color(0.71, 0.35, 0.29)),
		"felt_blue": Look.felt(Color(0.30, 0.44, 0.66)),
		"felt_green": Look.felt(Color(0.49, 0.60, 0.36)),
		"felt_yellow": Look.felt(Color(0.84, 0.64, 0.29)),
		"paper": lamp,
		"fire": fire,
		"metal": _metal(),
		"dark": Look.felt(Color(0.17, 0.16, 0.16), 2.0),   # 雪落としのマット、自販機の口
	}
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and mats.has(src.resource_name):
				mi.set_surface_override_material(i, mats[src.resource_name])

	for e in find_children("light_*", "", true, false):
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.40)   # 電球色より少し赤み
		l.light_energy = 1.1
		l.omni_range = 6.5
		if e.name.begins_with("light_lamp"):      # 食堂の天井: 3 つで広く照らす
			l.omni_range = 11.0
			l.light_energy = 1.6
		elif e.name.begins_with("light_lantern"):  # 座敷: 2 つ
			l.omni_range = 9.0
			l.light_energy = 1.4
		if e.name == "light_fire":                 # 影は付けない（スマホでも軽く）
			l.light_color = Color(1.0, 0.45, 0.16)
			l.omni_range = 7.0
			l.position = Vector3(0, 0, 1.0)   # 炉の石の面から部屋の側へ離す（近いと石が白く飛ぶ）
			fire_light = l
		e.add_child(l)

	_make_auto_door()


static func _metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()   # 鉄（金網、戸の帯、自動ドアの框）
	m.albedo_color = Color(0.20, 0.20, 0.22)
	m.metallic = 0.6
	m.roughness = 0.45
	return m


## 自動ドア: 人（CharacterBody3D）が戸の前後 3 m に入ると左右へ開き、いなくなると閉まる
func _make_auto_door() -> void:
	var box := AABB()
	var first := true
	for side in ["l", "r"]:
		for nm in ["autodoor_" + side, "autodoor_glass_" + side]:
			var n := find_child(nm, true, false) as Node3D
			if n == null:
				continue
			_auto_doors.append(n)
			_auto_home.append(n.position.x)
			_auto_sign.append(-1.0 if side == "l" else 1.0)
			if n is MeshInstance3D:
				var b := (n as MeshInstance3D).get_aabb()
				b = (global_transform.affine_inverse() * n.global_transform) * b
				box = b if first else box.merge(b)
				first = false
	if _auto_doors.is_empty() or Engine.is_editor_hint():
		return
	_auto_area = Area3D.new()
	_auto_area.name = "AutoDoorSensor"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(box.size.x + 1.0, 3.0, 6.0)
	cs.shape = sh
	_auto_area.add_child(cs)
	_auto_area.position = box.get_center()
	add_child(_auto_area)


func _process(dt: float) -> void:
	_t += dt
	if fire_light:   # 炉の火の揺らぎ
		fire_light.light_energy = 1.2 + 0.3 * sin(_t * 13.0) + 0.2 * sin(_t * 7.3 + 1.0)
	if _auto_area:
		var someone := false
		for b in _auto_area.get_overlapping_bodies():
			if b is CharacterBody3D:
				someone = true
				break
		_auto_open = move_toward(_auto_open, 1.0 if someone else 0.0, dt / (0.9 if someone else 1.6))
		var e := _auto_open * _auto_open * (3.0 - 2.0 * _auto_open)   # なめらかに
		for i in _auto_doors.size():
			_auto_doors[i].position.x = _auto_home[i] + _auto_sign[i] * AUTO_SLIDE * e
