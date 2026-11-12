extends Node3D
## 本物の地形のワールド（天下森・旭ヶ丘）の、スキー場の大きな地図の掲示板（2026-11-12 代表「倶知安も天下森も地図欲しいね、デカい掲示板の」
## 「実際のコースも書いてほしい」）。
## 地図の絵は ../tenkamori/draw_trail_map.py が焼いた表から描いた game/<場所>/trail_map.png。同じ向き・縮尺の値（trail_map.json）で、
## いまいる人のまち針を刺す（map_pins.gd。ロッジ前の地図と同じ）。日が傾くと、額の上の提灯が照らす（map_light.gd）。
## 地図の上は山の上。表は山を見上げる人の側（下る向き）へ向けて立てるので、地図の右と左が、前に立って見上げた右と左にそろう。文字は使わない

const Tenka := preload("res://tenkamori.gd")
const Icons := preload("res://hud_icons.gd")
const MapPins := preload("res://map_pins.gd")
const MapLight := preload("res://map_light.gd")

const BOARD := Vector2(9.0, 6.0)   # 看板の大きさ (m)。ロッジ前の地図（8 × 5.33）より一回り大きく
const BOARD_Y := 1.0               # 地面から看板の下の縁まで (m)
const LIT := Color(0.62, 0.62, 0.62, 1.0)   # 雪山の光で紙が白く飛ばないよう沈める（ロッジ前の地図と同じ）

var main: Node3D
var _map := {}


func _ready() -> void:
	var path := Tenka.res("trail_map.json")
	if not FileAccess.file_exists(path):
		return
	_map = JSON.parse_string(FileAccess.get_file_as_string(path))
	var at := Vector2(_map.board[0], _map.board[1])
	var up := Vector2(_map.up[0], _map.up[1])
	position = Vector3(at.x, main.foot_y(at.x, at.y, 0.6) - 0.05, at.y)
	rotation.y = atan2(-up.x, -up.y)   # 表（+Z）を下る向き（見上げる人の側）へ
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Icons.WOOD * LIT
	wood.roughness = 0.7
	# 額と 2 本の脚と、雪よけの小さな屋根
	var frame := _box(Vector3(BOARD.x + 0.4, BOARD.y + 0.4, 0.18), Vector3(0, BOARD_Y + BOARD.y / 2.0, 0), wood)
	var roof := _box(Vector3(BOARD.x + 1.0, 0.16, 1.0), Vector3(0, BOARD_Y + BOARD.y + 0.35, 0.3), wood)
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.97, 0.975, 0.99)
	snow.roughness = 1.0
	_box(Vector3(BOARD.x + 0.9, 0.22, 0.95), Vector3(0, BOARD_Y + BOARD.y + 0.53, 0.3), snow)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.3, BOARD_Y + BOARD.y + 0.5, 0.26), Vector3(sx * (BOARD.x / 2.0 - 0.8), (BOARD_Y + BOARD.y + 0.5) / 2.0 - 0.3, -0.03), wood)
	var face := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = BOARD
	face.mesh = q
	var m := StandardMaterial3D.new()
	var tex_path := Tenka.res("trail_map.png")
	m.albedo_texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
	m.albedo_color = LIT if m.albedo_texture else Icons.PAPER
	m.roughness = 0.95
	face.material_override = m
	face.position = Vector3(0, BOARD_Y + BOARD.y / 2.0, 0.1)
	add_child(face)
	var pins := MapPins.new()
	pins.name = "MapPins"
	pins.main = main
	pins.to_board = on_board
	add_child(pins)
	var lamps := MapLight.new()
	lamps.name = "MapLight"
	lamps.top = BOARD_Y + BOARD.y + 0.2
	lamps.wood = wood
	add_child(lamps)
	for g: GeometryInstance3D in [frame, roof, face, pins]:
		g.layers |= MapLight.LAYER
	# 脚の当たり（板は脚より上なので、脚だけ）
	var body := StaticBody3D.new()
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.34, BOARD_Y + BOARD.y, 0.3)
		cs.shape = bs
		cs.position = Vector3(sx * (BOARD.x / 2.0 - 0.8), (BOARD_Y + BOARD.y) / 2.0, 0)
		body.add_child(cs)
	add_child(body)


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


## 世界 (x, z) → 看板の上の位置 (x, y)（看板の足もとから, m）。地図の外の人は、縁の縫い目の内側で止まる
func on_board(p: Vector2) -> Vector2:
	var right := Vector2(_map.right[0], _map.right[1])
	var up := Vector2(_map.up[0], _map.up[1])
	var k: float = _map.scale
	var size := Vector2(_map.size[0], _map.size[1])
	var px := size.x / 2.0 + (p.dot(right) - float(_map.origin[0])) * k
	var py := size.y / 2.0 - (p.dot(up) - float(_map.origin[1])) * k
	var at := Vector2(px, py).clamp(Vector2.ONE * 50.0, size - Vector2.ONE * 50.0) / size
	return Vector2((at.x - 0.5) * BOARD.x, BOARD_Y + (1.0 - at.y) * BOARD.y)
