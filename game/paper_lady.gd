extends Node3D
## 2 階の衣装掛けの横の、紙細工屋さん（黒い折り紙の婦人）と、大きなアフタヌーンティーのスタンド
## （2026-11-02 代表「紙細工屋さん。提灯とアクセサリ（鳥とかどんぐりとか）売ってくれる人」。案の絵は person/ideas/kamizaiku）。
## 婦人は着物とドレスを混ぜた黒い紙の人形（paper_lady.glb。節 upper_body＝腰から上、head_pivot＝頭）。
## 横のスタンドは背丈より大きい 5 段の紙の皿（tea_stand.glb）で、下の 2 段に腰に提げる提灯（lantern.gd の LOOKS）を 5 つずつ、
## 上の 3 段に頭・肩の小物（pals.gd の PERCH_ORDER）を 5・4・2 つ、同じ品は一つずつ客の側の弧に並べる（代表「ランタンの段とアクセサリの段で分けて」）。
## 前で F を押すと、買って付け替える画面（paper_shop_ui.gd）が開く。
## 動きは人形と同じ 12 コマ／秒に刻む（コマの間は止める）:
##   待つ   息をするように腰から上がわずかに揺れ、ゆっくりスタンドと客の側を見比べる
##   気づく 人が近づくと顔を向ける
##   売る   画面が開いているあいだは客を見る。だれかが買う・付け替えると、うなずいて腰から上で小さくお辞儀をする
## スタンドの品物は、あなたが近づいて（NEAR_LOAD）から置く。置き方は main.gd の _put_wardrobe（衣装掛けの横）。この節の +Z が正面

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")

const LADY_GLB := "res://props/paper_lady/paper_lady.glb"
const STAND_GLB := "res://props/paper_lady/tea_stand.glb"
## スタンドの所（この節の座標。+X は婦人の左手の側）
const STAND_AT := Vector3(1.35, 0.0, -0.3)
## スタンドの皿（半径, 皿の高さ, m）。person/ideas/kamizaiku/roughs.py の TIERS をゲームの大きさ（1.3 倍）にしたもの
const TIERS := [[0.728, 0.416], [0.611, 0.858], [0.494, 1.274], [0.377, 1.664], [0.26, 2.015]]
const LIFT := 0.016          # 皿の上に置く高さ
const ARC := 150.0           # 品物を並べる客の側の弧（度）
const LANTERN_IN := 0.66     # 提灯を置く所（皿の半径の割合）
const PERCH_IN := 0.6        # 小物を置く所
const PERCH_SIZE := 0.26     # 小物の見本の大きさ（いちばん長い辺, m）
const NOTICE_R := 4.0        # この距離に人が来ると顔を向ける (m)
const REACH := 2.4           # この距離 (m) の内で、婦人かスタンドの方を向いていれば F で開ける
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、品物を並べる

var player: Node3D           # main.gd が入れる
var craft: Node              # main.gd が入れる（買う・付け替えるの出来事でうなずく）
var ui: CanvasLayer          # 開いているあいだ客を見る（main.gd が入れる）
var lady: Node3D
var stand: Node3D
var _upper: Node3D
var _head: Node3D
var _loaded := false
var _lamps: Array = []       # [光る紙の素材, 揺らぎ方, ずらし]
var _frame := -1
var _check_t := 0.0
var _t := 0.0
var _nod := 0                # うなずきの残りのコマ
var _look := 0.0             # いまの顔の向き（ラジアン）


func _ready() -> void:
	lady = Props.make(LADY_GLB)
	lady.rotation.y = PI   # glb の正面（Blender の +Y＝Godot の -Z）を、この節の正面 +Z へ
	add_child(lady)
	_upper = lady.find_child("upper_body*", true, false) as Node3D
	_head = lady.find_child("head_pivot*", true, false) as Node3D
	stand = Node3D.new()
	stand.position = STAND_AT
	add_child(stand)
	var s := Props.make(STAND_GLB)
	s.rotation.y = PI
	stand.add_child(s)
	# スタンドのまわりをほんのり照らす灯り（提灯ごとには灯さない。影なし）
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.46)
	lamp.light_energy = 0.6
	lamp.omni_range = 3.0
	lamp.shadow_enabled = false
	lamp.position = Vector3(0, 1.0, 0.6)
	stand.add_child(lamp)
	# 当たり（婦人の裾とスタンド）
	var body := StaticBody3D.new()
	add_child(body)
	for c in [[Vector3.ZERO, 0.5, 1.6], [STAND_AT, 0.7, 2.4]]:
		var col := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = c[1]
		cy.height = c[2]
		col.shape = cy
		col.position = (c[0] as Vector3) + Vector3.UP * float(c[2]) / 2.0
		body.add_child(col)
	if craft:
		craft.happened.connect(_on_craft)


## だれかがここの品物を買った・付け替えた: うなずく（通信ではほかの人の画面でも）
func _on_craft(ev: Dictionary) -> void:
	var k := String(ev.get("kind", ""))
	if k in ["pal_buy", "pal_wear", "lantern_buy"] or (k == "equip" and ev.get("gear", "") == "lantern"):
		_nod = 8


## 品物を並べる（近づいてから一度だけ）。下の 2 段に提灯、上の 3 段に小物。光る紙は 1 つずつ素材を写して、形ごとの揺らぎ方で光らせる
func _load_goods() -> void:
	_loaded = true
	var rows := [Lantern.LOOKS.slice(0, 5), Lantern.LOOKS.slice(5, 10),
			Pals.PERCH_ORDER.slice(0, 5), Pals.PERCH_ORDER.slice(5, 9), Pals.PERCH_ORDER.slice(9)]
	for t in rows.size():
		var keys: Array = rows[t]
		var lantern := t < 2
		for i in keys.size():
			var n := keys.size()
			var a := deg_to_rad((i - (n - 1) / 2.0) * (ARC / maxf(n - 1, 1)) if n > 1 else 0.0)
			var r: float = TIERS[t][0] * (LANTERN_IN if lantern else PERCH_IN)
			var spot := Vector3(sin(a) * r, float(TIERS[t][1]) + LIFT, cos(a) * r)
			var item: Node3D
			if lantern:
				var made := Lantern.make_body(keys[i])
				item = made[0]
				var mat: StandardMaterial3D = null
				for m in made[1]:
					if mat == null:
						var src := (m as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
						mat = src.duplicate() if src else null
					if mat:
						(m as MeshInstance3D).set_surface_override_material(0, mat)
				_lamps.append([mat, String(Lantern.LOOK[keys[i]].style), randf() * 100.0])
			else:
				item = Pals.scene(keys[i]).instantiate()
				Pals.paint(item, 1)
			var holder := Node3D.new()
			holder.rotation.y = a
			stand.add_child(holder)
			holder.add_child(item)
			var box := _bounds(item)
			if not lantern:   # 小物は皿の上で見えるように大きさをそろえる
				var k := PERCH_SIZE / maxf(box.size.x, maxf(box.size.y, box.size.z))
				item.scale = Vector3.ONE * k
				box = AABB(box.position * k, box.size * k)
			# 置く所へ: 外形の箱の下の真ん中を、皿の上の点に（holder は向きだけ。位置は holder の座標で）
			var c := box.get_center()
			item.position = Vector3(-c.x, -box.position.y, -c.z)
			holder.position = spot


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.transform * m.get_aabb()
		var p := m.get_parent()
		while p != n and p is Node3D:
			b = (p as Node3D).transform * b
			p = p.get_parent()
		box = b if first else box.merge(b)
		first = false
	return box


## あなたが婦人かスタンドの前で、そちらを向いているか
func can_use(p: Node3D) -> bool:
	for at in [global_position, stand.global_position]:
		var d: Vector3 = at - p.global_position
		if absf(d.y) > 1.5:
			continue
		d.y = 0
		if d.length() > REACH:
			continue
		if (-p.global_basis.z).dot(d.normalized()) > 0.35 or d.length() < 0.9:
			return true
	return false


func _process(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	_check_t -= dt
	if not _loaded and _check_t <= 0.0:
		_check_t = 0.5
		if player.global_position.distance_to(global_position) < NEAR_LOAD:
			_load_goods()
	_t += dt
	for l in _lamps:   # 光の揺らぎは毎フレーム（なめらかに）
		if l[0]:
			(l[0] as StandardMaterial3D).emission_energy_multiplier = 1.6 * Lantern.flicker(l[1], _t, l[2])
	var f := Doll.frame_index()
	if f == _frame:
		return
	_frame = f
	_pose(f)


## 12 コマごとの姿勢: 腰から上の息と揺れ、顔の向き、うなずきとお辞儀
func _pose(f: int) -> void:
	var k := float(f) / 12.0
	var shopping: bool = ui != null and ui.get("is_open")
	var d := lady.to_local(player.global_position)
	var near := Vector2(d.x, d.z).length() < NOTICE_R
	# 顔を向ける先（glb の座標では正面が -Z）。近くにいなければ、スタンドと客の側をゆっくり見比べる
	var want := 0.0
	if near or shopping:
		want = clampf(atan2(-d.x, -d.z), -1.0, 1.0)
	else:
		want = 0.55 * sin(k * 0.35) - 0.25
	_look = lerpf(_look, want, 0.35)
	var bow := 0.0
	var nod := 0.0
	if _nod > 0:
		_nod -= 1
		nod = 0.32 * sin(PI * (8 - _nod) / 8.0)
		bow = 0.1 * sin(PI * (8 - _nod) / 8.0)
	if _upper:
		_upper.rotation = Vector3(-bow + 0.015 * sin(k * 0.9), _look * 0.25, 0.012 * sin(k * 0.45))
	if _head:
		_head.rotation = Vector3(-nod + 0.02 * sin(k * 0.7 + 1.0), _look * 0.75, 0.04 * sin(k * 0.3))
