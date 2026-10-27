@tool
extends Node3D
## ロッジ（lodge/ の Blender の台本で作った glb）。エディタで開いても手芸の素材と灯りで見えるよう @tool にする。
## 素材は glb の役割の名前（log, roof, snow …）で look.gd の素材に差し替え、灯りの目印（light_*）に暖色の灯りを灯す。
## 当たり判定は lodge_collision.glb（名前の -colonly で、見た目なしの当たり判定になる）。

const Look := preload("res://look.gd")

var fire_light: OmniLight3D
var _t := 0.0


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
		if e.name == "light_fire":
			l.light_color = Color(1.0, 0.45, 0.16)
			l.omni_range = 7.0
			l.shadow_enabled = true
			l.position = Vector3(0, 0, 1.0)   # 炉の石の面から部屋の側へ離す（近いと石が白く飛ぶ）
			fire_light = l
		e.add_child(l)


func _process(dt: float) -> void:
	_t += dt
	if fire_light:   # 炉の火の揺らぎ
		fire_light.light_energy = 1.2 + 0.3 * sin(_t * 13.0) + 0.2 * sin(_t * 7.3 + 1.0)
