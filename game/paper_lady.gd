extends Node3D
## 1 階の南西の隅、人台の北どなりのテントの、紙細工屋さん（黒い折り紙の婦人）と、大きなアフタヌーンティーのスタンド
## （2026-11-02 代表「紙細工屋さん。提灯とアクセサリ（鳥とかどんぐりとか）売ってくれる人」。案の絵は person/ideas/kamizaiku）。
## 婦人は着物とドレスを混ぜた黒い紙の人形（paper_lady.glb。節 upper_body＝腰から上、head_pivot＝頭、shoulder_r/l → elbow_r/l → hand_r/l＝腕と手の目印）。
## 横のスタンドは背丈より大きい 5 段の紙の皿（tea_stand.glb）で、下の 2 段に腰に提げる提灯（lantern.gd の LOOKS）を 5 つずつ、
## 上の 3 段に頭・肩の小物（pals.gd の PERCH_ORDER）を 5・4・2 つ、同じ品は一つずつ客の側の弧に並べる（代表「ランタンの段とアクセサリの段で分けて」）。
## 前で F を押すと、買って付け替える画面（paper_shop_ui.gd）が開く。
## 動き（2026-11-03 代表「近づいたらおじぎしてほしい。雪だるまやパッチワークのようにお店アニメーションもほしい」。案の絵は
## person/ideas/kamizaiku/renders/07-motion.jpg）は人形と同じ 12 コマ／秒に刻む（コマの間は止める）。姿勢は lady_poses.json（Blender の台本が書き出す）:
##   おじぎ   人が近づくと、顔を向けて腰から深くおじぎ。離れてからまた近づくと、またおじぎ（自分もほかの人も。いちばん近い人へ）
##   紙細工   だれも近くにいないと、胸の前で千代紙を三角に折って鶴にする（紙の音）。次ははさみで紙を切る（はさみの音）。交互にくり返す
##   見る     近くに人がいるあいだは、手を前で重ねて、いちばん近い人へ顔を向ける。息をするように腰から上がわずかに揺れる
##   売る     だれかが買うと: スタンドの方へ体を向けて左手で品物を取る → 買った人から飛んできたお代のボタンを受ける →
##            両手で薄紙に包み朱の紐をかける → 両手で差し出し、包みは買った人の手もとへ飛ぶ → 会釈。付け替えだけなら小さくうなずく
## 売る動きは craft.gd の出来事（通信ではみんなに配られる）で始めるので、だれの画面でも同じ順で動く。おじぎは、それぞれの画面で人の位置から決める
## スタンドの品物は、あなたが近づいて（NEAR_LOAD）から置く。置き方は main.gd の _put_wardrobe（衣装掛けの横）。この節の +Z が正面
## 婦人とスタンドはテント（paper_tent.gd）の中。だれも近くにいないと幕が閉じていて、おじぎは幕が開いてから

const Doll := preload("res://doll.gd")
const Props := preload("res://props.gd")
const Look := preload("res://look.gd")
const Lantern := preload("res://lantern.gd")
const Pals := preload("res://pals.gd")
const PaperTent := preload("res://paper_tent.gd")
const Ghost := preload("res://ghost.gd")

const LADY_GLB := "res://props/paper_lady/paper_lady.glb"
const POSES_JSON := "res://props/paper_lady/lady_poses.json"
const STAND_GLB := "res://props/paper_lady/tea_stand.glb"
## スタンドの所（この節の座標。+X は婦人の左手の側）
const STAND_AT := Vector3(1.35, 0.0, -0.3)
## テントの真ん中（この節の座標）。婦人とスタンドの両方が楕円の内に入る所
const TENT_AT := Vector3(0.85, 0.0, -0.085)
## スタンドの皿（半径, 皿の高さ, m）。person/ideas/kamizaiku/roughs.py の TIERS をゲームの大きさ（1.3 倍）にしたもの
const TIERS := [[0.728, 0.416], [0.611, 0.858], [0.494, 1.274], [0.377, 1.664], [0.26, 2.015]]
const LIFT := 0.016          # 皿の上に置く高さ
const ARC := 150.0           # 品物を並べる客の側の弧（度）
const LANTERN_IN := 0.66     # 提灯を置く所（皿の半径の割合）
const PERCH_IN := 0.6        # 小物を置く所
const PERCH_SIZE := 0.26     # 小物の見本の大きさ（いちばん長い辺, m）
const NOTICE_R := 3.2        # この距離に人が来ると顔を向けて、おじぎをする (m)
const LEAVE_R := 5.0         # この距離より離れたら、次に近づいたときにまたおじぎをする (m)
const JOINTS := ["upper", "head", "sh_r", "el_r", "sh_l", "el_l"]
const JOINT_NODES := {"upper": "upper_body", "head": "head_pivot", "sh_r": "shoulder_r", "el_r": "elbow_r", "sh_l": "shoulder_l", "el_l": "elbow_l"}
## 動きの並び: [姿勢, その姿勢へ移るコマ数]。前の姿勢からコマごとに寄せる（12 コマ／秒）
const SEQ := {
	"bow": [["bow_a", 2], ["bow_b", 2], ["bow_b", 4], ["bow_a", 2], ["rest", 3]],
	"nod": [["nod", 2], ["nod", 2], ["rest", 3]],
	"fold": [["fold_hold", 4], ["fold_hold", 6], ["fold_open", 3], ["fold_hold", 3], ["fold_open", 3], ["fold_hold", 9], ["rest", 4], ["rest", 16]],
	"cut": [["cut", 4], ["cut", 15], ["rest", 4], ["rest", 16]],
	"sale": [["reach", 5], ["reach", 2], ["receive", 4], ["receive", 4], ["wrap", 4], ["wrap", 7], ["give", 4], ["give", 4], ["nod", 3], ["nod", 3], ["rest", 4]],
}
## 動きの中で手に持つ物を出す・消すコマ: [始め, 終わり]（その動きの始めから数える）
const PROPS_IN := {
	"fold": {"paper_sq": [3, 12], "paper_tri": [13, 18], "crane": [19, 29]},
	"cut": {"paper_sq": [3, 21], "scissors": [3, 21]},
	"sale": {"item": [4, 16], "coin": [11, 16], "parcel": [17, 30]},
}
const FOLD_AT := [10, 16, 19]   # 紙の音を鳴らすコマ（fold）
const SNIP_AT := [7, 10, 13, 16]   # はさみの音（cut）
const REACH := 2.4           # この距離 (m) の内で、婦人かスタンドの方を向いていれば F で開ける
const NEAR_LOAD := 30.0      # あなたがこの距離まで来たら、品物を並べる

var main: Node3D             # main.gd が入れる（ほかの人・買った人・音を探す）
var player: Node3D           # main.gd が入れる
var craft: Node              # main.gd が入れる（買う・付け替えるの出来事でうなずく）
var ui: CanvasLayer          # 開いているあいだ客を見る（main.gd が入れる）
var lady: Node3D
var stand: Node3D
var tent: Node3D             # 婦人とスタンドを囲むテント（paper_tent.gd）
var _joints := {}            # 節の名前（JOINTS）→ 節
var _hand_r: Node3D
var _hand_l: Node3D
var _poses := {}             # 姿勢の名前 → {節の名前: Vector3}
var _cur := {}               # いまの姿勢（節の名前 → Vector3）
var _act := ""               # いまの動き（SEQ の名前。"" は見る・休む）
var _act_k := 0              # 動きの始めのコマ
var _act_from := {}          # 動きを始めたときの姿勢
var _next_craft := "fold"    # 次の紙細工
var _greeted := {}           # おじぎした人（節の instance id → true）。離れたら消す
var _props := {}             # 手に持つ物の名前 → 節
var _sale_item: Node3D       # 売るときに手に取った品物の写し
var _sale_buyer := -1        # 買った人の番号
var _flights: Array = []     # 飛ぶ物 {node, from, to_fn, start, len, h}
var _k := 0                  # 12 コマの数
var _loaded := false
var _lamps: Array = []       # [光る紙の素材, 揺らぎ方, ずらし]
var _frame := -1
var _check_t := 0.0
var _t := 0.0
var _look := 0.0             # いまの顔の向き（ラジアン）


func _ready() -> void:
	lady = Props.make(LADY_GLB)
	lady.rotation.y = PI   # glb の正面（Blender の +Y＝Godot の -Z）を、この節の正面 +Z へ
	add_child(lady)
	for j in JOINTS:
		_joints[j] = lady.find_child(JOINT_NODES[j] + "*", true, false) as Node3D
	_hand_r = lady.find_child("hand_r*", true, false) as Node3D
	_hand_l = lady.find_child("hand_l*", true, false) as Node3D
	_load_poses()
	_make_props()
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
	tent = PaperTent.new()
	tent.name = "PaperTent"
	tent.lady = self
	tent.position = TENT_AT
	add_child(tent)
	if craft:
		craft.happened.connect(_on_craft)


## だれかがここの品物を買った: 売る動き。ランタンの色替え（lantern_dye）も、染めたランタンを渡す売る動き。
## 付け替えただけ・もとの色に戻しただけ（ただ）なら、うなずく（通信ではほかの人の画面でも、同じ出来事で）
func _on_craft(ev: Dictionary) -> void:
	var k := String(ev.get("kind", ""))
	var dyed := k == "lantern_dye" and int(ev.get("price", 0)) > 0
	if k == "pal_buy" or k == "lantern_buy" or dyed:
		_start_sale(String(ev.get("look", ev.get("key", ""))), k != "pal_buy", int(ev.get("who", -1)), String(ev.get("color", "")))
	elif (k == "pal_wear" or k == "lantern_dye" or (k == "equip" and ev.get("gear", "") == "lantern")) and _act != "sale":
		_start("nod")


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
	_k += 1
	_step()


# ---------------------------------------------------------------- 姿勢と動き

func _load_poses() -> void:
	var f := FileAccess.open(POSES_JSON, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(d) != TYPE_DICTIONARY:
		d = {"rest": {}}
	for name in d:
		var p := {}
		for j in JOINTS:
			var v: Array = d[name].get(j, [0, 0, 0])
			p[j] = Vector3(v[0], v[1], v[2])
		_poses[name] = p
	_cur = (_poses["rest"] as Dictionary).duplicate()


func _start(act: String) -> void:
	_act = act
	_act_k = _k
	_act_from = _cur.duplicate()


## 動きの中の姿勢（コマ n）。並びの区切りごとに、前の姿勢から次の姿勢へコマで寄せる
func _seq_pose(act: String, n: int) -> Variant:
	var from: Dictionary = _act_from
	var t := 0
	for seg in SEQ[act]:
		var to: Dictionary = _poses.get(seg[0], _poses["rest"])
		var len: int = seg[1]
		if n < t + len:
			var a := float(n - t + 1) / float(len)
			var p := {}
			for j in JOINTS:
				p[j] = (from[j] as Vector3).lerp(to[j], a)
			return p
		from = to
		t += len
	return null   # 終わった


## 近くの人（自分とほかの人。通信の相手の体も）
func _people() -> Array:
	var out: Array = [player] if not Ghost.gone(player) else []   # 観戦モードの霊体（ghost.gd）は見ない
	var net = main.get("net") if main else null
	if net and net.get("remotes"):
		for r in (net.remotes as Dictionary).values():
			if is_instance_valid(r) and not Ghost.gone(r):
				out.append(r)
	return out


func _step() -> void:
	# いちばん近い人。近づいた人にはおじぎ（離れたら、またおじぎできる）
	var nearest: Node3D = null
	var best := NOTICE_R
	var bow_to: Node3D = null
	for p in _people():
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		var id: int = p.get_instance_id()
		if d < best:
			best = d
			nearest = p
		if d < NOTICE_R and not _greeted.has(id) and _act != "sale" and _act != "bow" and tent.bow_ready():   # 幕が開いてからおじぎ
			bow_to = p
			_greeted[id] = true
		elif d > LEAVE_R:
			_greeted.erase(id)
	if bow_to:
		_start("bow")
	# 動きを進める。終わったら、近くに人がいなければ紙細工、いれば見る
	var pose = _seq_pose(_act, _k - _act_k) if _act != "" else null
	if _act != "" and pose == null:
		if _act == "sale":
			_end_sale()
		_act = ""
	if _act in ["fold", "cut"] and nearest != null:   # 人が来たら紙細工をやめる（おじぎが先に入っていなければ、手を下ろす）
		_act = ""
	if _act == "" and nearest == null:
		_start(_next_craft)
		_next_craft = "cut" if _next_craft == "fold" else "fold"
		pose = _seq_pose(_act, 0)
	if pose == null:   # 見る・休む: 手を前で重ねる（いまの姿勢から休む姿勢へ寄せる）
		pose = {}
		for j in JOINTS:
			pose[j] = (_cur[j] as Vector3).lerp(_poses["rest"][j], 0.5)
	_cur = pose
	_show_props()
	_sounds()
	# 顔: いちばん近い人へ（glb の座標では正面が -Z）。紙細工のあいだは手もとを見る
	var want := 0.0
	if nearest and _act != "sale":
		var d := lady.to_local(nearest.global_position)
		want = clampf(atan2(-d.x, -d.z), -1.0, 1.0)
	_look = lerpf(_look, want, 0.35)
	var breath := 0.012 * sin(float(_k / 3 * 3) * 0.075 * TAU) if _act == "" else 0.0
	for j in JOINTS:
		var n: Node3D = _joints[j]
		if n == null:
			continue
		var r: Vector3 = _cur[j]
		if j == "upper":
			r += Vector3(breath, _look * 0.25, 0.0)
		elif j == "head":
			r += Vector3(0.0, _look * 0.7, 0.02 * sin(_k * 0.21))
		n.rotation = r
	_fly()


# ---------------------------------------------------------------- 手に持つ物

func _make_props() -> void:
	if _hand_r == null or _hand_l == null:
		return
	var tmp := Node.new()
	Pals.paint(tmp)   # 素材の表（game/pals/mats.json）を読んでおく
	tmp.free()
	var chiyo: Material = Pals.material("chiyo_red")
	if chiyo == null:
		chiyo = Look.paper(Color(0.72, 0.28, 0.23))
	var mid := Vector3(-0.05, 0.0, 0.0)   # 右手から見た両手のあいだ（glb の座標。正面は -Z）
	# 千代紙（四角）と、三角に折った紙
	var sq := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.17, 0.17)
	sq.mesh = qm
	sq.material_override = _two_sided(chiyo)
	sq.position = mid + Vector3(0, 0.1, -0.08)
	sq.rotation = Vector3(-0.35, PI, 0)
	_hand_r.add_child(sq)
	_props["paper_sq"] = sq
	var tri := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.17, 0.12, 0.004)
	tri.mesh = pm
	tri.material_override = chiyo
	tri.position = mid + Vector3(0, 0.09, -0.08)
	tri.rotation = Vector3(-0.3, 0, 0)
	_hand_r.add_child(tri)
	_props["paper_tri"] = tri
	# 鶴（頭・肩の小物の折り鶴を小さく）
	var crane: Node3D = Pals.scene("crane").instantiate()
	Pals.paint(crane)
	_fit(crane, 0.2)
	var holder := Node3D.new()
	holder.position = mid + Vector3(0, 0.05, -0.07)
	holder.rotation.y = PI
	holder.add_child(crane)
	_hand_r.add_child(holder)
	_props["crane"] = holder
	# はさみ: 真鍮の刃 2 枚。切るときに開いて閉じる
	var sc := Node3D.new()
	sc.position = Vector3(0.0, 0.06, -0.08)
	sc.rotation = Vector3(-0.6, 0.5, 0)
	for side in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.008, 0.003, 0.1)
		b.mesh = bm
		b.material_override = Look.shine("brass")
		b.name = "blade"
		b.position = Vector3(0, 0, -0.03)
		b.rotation.y = side * 0.05
		sc.add_child(b)
	_hand_r.add_child(sc)
	_props["scissors"] = sc
	# お代のボタン（左手に）
	_props["coin"] = _coin()
	_props["coin"].position = Vector3(0, 0.03, -0.02)
	_hand_l.add_child(_props["coin"])
	# 包み: 白い薄紙の箱に朱の紐を十字に
	var pc := Node3D.new()
	pc.position = mid + Vector3(0, 0.05, -0.04)
	var box := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.12, 0.08, 0.09)
	box.mesh = bx
	box.material_override = Look.paper(Color(0.96, 0.95, 0.92))
	pc.add_child(box)
	for size in [Vector3(0.125, 0.084, 0.012), Vector3(0.012, 0.084, 0.095)]:
		var rb := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = size
		rb.mesh = rm
		rb.material_override = Look.felt(Color(0.72, 0.2, 0.18))
		pc.add_child(rb)
	_hand_r.add_child(pc)
	_props["parcel"] = pc
	for n in _props.values():
		(n as Node3D).visible = false


func _two_sided(m: Material) -> Material:
	var d := m.duplicate()
	if d is BaseMaterial3D:
		(d as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return d


func _coin() -> MeshInstance3D:
	var c := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.024
	cm.bottom_radius = 0.024
	cm.height = 0.006
	c.mesh = cm
	c.material_override = Look.shine("brass")
	return c


## n をいちばん長い辺が size (m) になるように縮める
func _fit(n: Node3D, size: float) -> void:
	var box := _bounds(n)
	n.scale = Vector3.ONE * size / maxf(box.size.x, maxf(box.size.y, box.size.z))


func _show_props() -> void:
	var n := _k - _act_k
	var table: Dictionary = PROPS_IN.get(_act, {})
	for name in _props:
		var span = table.get(name)
		(_props[name] as Node3D).visible = span != null and n >= span[0] and n <= span[1]
	if _sale_item:
		var span: Array = PROPS_IN.sale.item
		_sale_item.visible = _act == "sale" and n >= span[0] and n <= span[1]
	if _act == "cut":   # はさみ: 3 コマごとに開いて閉じる
		var open := 0.35 if (n / 3) % 2 == 0 else 0.05
		var i := 0
		for b in (_props["scissors"] as Node3D).get_children():
			(b as Node3D).rotation.y = open * (1.0 if i == 0 else -1.0)
			i += 1
	if _act == "sale" and n >= 17 and n <= 19:   # 包むとき、包みが少しずつふくらむ
		(_props["parcel"] as Node3D).scale = Vector3.ONE * [0.5, 0.8, 1.0][n - 17]


func _sounds() -> void:
	var audio = main.get_node_or_null("Audio") if main else null
	if audio == null or not audio.has_method("kitchen"):
		return
	var n := _k - _act_k
	if _act == "fold" and n in FOLD_AT:
		audio.kitchen(lady, "wrap_paper", -22.0, 3, 1.3)
	elif _act == "cut" and n in SNIP_AT:
		audio.kitchen(lady, "sew_snip", -20.0, 2, 1.1)


# ---------------------------------------------------------------- 売る

func _start_sale(key: String, lantern: bool, who: int, hex := "") -> void:
	if _sale_item:
		_sale_item.queue_free()
		_sale_item = null
	if _hand_l and key != "":
		var item: Node3D
		if lantern and Lantern.LOOK.has(key):
			item = Lantern.make_body(key, hex)[0]
			item.scale = Vector3.ONE * 0.55
		elif Pals.PERCH.has(key) or Pals.PET.has(key):
			item = Pals.scene(key).instantiate()
			Pals.paint(item)
			_fit(item, 0.16)
		if item:
			var h := Node3D.new()
			h.position = Vector3(0, 0.0 if lantern else 0.02, -0.04)
			h.rotation.y = PI
			h.add_child(item)
			_hand_l.add_child(h)
			_sale_item = h
			h.visible = false
	_sale_buyer = who
	_start("sale")
	# お代のボタン: 買った人の手もとから、婦人の左手へ飛ぶ
	var buyer := _buyer()
	if buyer and _hand_l:
		var c := _coin()
		add_child(c)
		c.visible = false
		_flights.append({"node": c, "from": buyer.global_position + Vector3.UP * 1.1, "to": func() -> Vector3: return _hand_l.global_position + Vector3.UP * 0.03,
				"start": _k + 7, "len": 4, "h": 0.25, "free": true})


func _end_sale() -> void:
	if _sale_item:
		_sale_item.queue_free()
		_sale_item = null


func _buyer() -> Node3D:
	var hub = main.get_node_or_null("Emotes") if main else null
	if hub and hub.has_method("who_of") and _sale_buyer >= 0:
		return hub.who_of(_sale_buyer)
	return null


## 飛ぶ物（お代のボタン・包み）を 12 コマで動かす。包みは渡すときに右手から買った人の手もとへ
func _fly() -> void:
	if _act == "sale" and _k - _act_k == 30 and _hand_r:
		var buyer := _buyer()
		if buyer:
			var pc: Node3D = _props["parcel"]
			var copy := pc.duplicate() as Node3D
			add_child(copy)
			copy.global_transform = pc.global_transform
			copy.scale = Vector3.ONE
			var b := buyer
			_flights.append({"node": copy, "from": pc.global_position, "to": func() -> Vector3: return b.global_position + Vector3.UP * 1.1 - b.global_basis.z * 0.3 if is_instance_valid(b) else pc.global_position,
					"start": _k, "len": 6, "h": 0.35, "free": true})
	for f in _flights.duplicate():
		var node: Node3D = f.node
		if not is_instance_valid(node):
			_flights.erase(f)
			continue
		var t := float(_k - int(f.start)) / float(f.len)
		if t < 0.0:
			continue
		node.visible = true
		var to: Vector3 = (f.to as Callable).call()
		var tt := minf(t, 1.0)
		node.global_position = (f.from as Vector3).lerp(to, tt) + Vector3.UP * float(f.h) * 4.0 * tt * (1.0 - tt)
		if t >= 1.0:
			node.queue_free()
			_flights.erase(f)
